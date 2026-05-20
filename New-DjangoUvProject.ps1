#Requires -Version 5.1
<#
.SYNOPSIS
  Cree un projet Django + uv (architecture 2026).

.DESCRIPTION
  Demande : nouveau dossier ? (Y/N). Si N, initialise dans le repertoire courant.
  Structure : config/ (settings decoupes), apps/ (Service Layer), templates/, static/scss/.

.PARAMETER ProjectName
  Nom du nouveau dossier (si -NewFolder). Sinon ignore.

.PARAMETER AppName
  Slug de l'app metier sous apps/ (defaut : core).

.PARAMETER ParentPath
  Dossier parent pour un nouveau dossier (defaut : repertoire courant).

.PARAMETER NewFolder
  Force la creation d'un sous-dossier (sans prompt Y/N).

.PARAMETER UseCurrentFolder
  Force l'initialisation dans le repertoire courant (sans prompt Y/N).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\New-DjangoUvProject.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\New-DjangoUvProject.ps1 -NewFolder mon_site -AppName blog
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\New-DjangoUvProject.ps1 -UseCurrentFolder
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$ProjectName = "",

    [Parameter(Position = 1)]
    [string]$AppName = "core",

    [Parameter(Position = 2)]
    [string]$ParentPath = "",

    [switch]$NewFolder,
    [switch]$UseCurrentFolder
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-PythonIdentifier {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    if ($Name -notmatch '^[a-zA-Z_][a-zA-Z0-9_]*$') { return $false }
    $reserved = @(
        "if", "else", "elif", "for", "while", "break", "continue", "pass",
        "def", "class", "import", "from", "as", "return", "True", "False",
        "None", "and", "or", "not", "in", "is", "lambda", "with", "async", "await"
    )
    return $reserved -notcontains $Name.ToLowerInvariant()
}

function Write-TextFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory)][string]$Exe,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$WorkingDirectory
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = ($Arguments | ForEach-Object {
            if ($_ -match '\s') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
        }) -join " "
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $WorkingDirectory
    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEnd()
    $err = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    if ($p.ExitCode -ne 0) {
        if ($out) { Write-Host $out }
        if ($err) { Write-Host $err }
        throw "Commande echouee (code $($p.ExitCode)) : $Exe $($psi.Arguments)"
    }
    if ($out) { Write-Host $out.TrimEnd() }
}

function New-DjangoConfigPackage {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$AppName
    )

    $configDir = Join-Path $Root "config"
    $settingsDir = Join-Path $configDir "settings"
    New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null

    Write-TextFile -Path (Join-Path $configDir "__init__.py") -Content "# Package config.`n"

    $managePy = @'
#!/usr/bin/env python
"""Utilitaire en ligne de commande Django."""
import os
import sys


def main() -> None:
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
    try:
        from django.core.management import execute_from_command_line
    except ImportError as exc:
        raise ImportError(
            "Django introuvable. Verifiez l'environnement uv (uv sync)."
        ) from exc
    execute_from_command_line(sys.argv)


if __name__ == "__main__":
    main()
'@
    Write-TextFile -Path (Join-Path $Root "manage.py") -Content $managePy

    $wsgi = @'
"""Point d'entree WSGI."""
import os

from django.core.wsgi import get_wsgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

application = get_wsgi_application()
'@
    Write-TextFile -Path (Join-Path $configDir "wsgi.py") -Content $wsgi

    $asgi = @'
"""Point d'entree ASGI."""
import os

from django.core.asgi import get_asgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

application = get_asgi_application()
'@
    Write-TextFile -Path (Join-Path $configDir "asgi.py") -Content $asgi

    $settingsInit = @'
"""Agregation des settings par environnement (DJANGO_ENV=dev|qua|prod)."""
import os

_env = os.environ.get("DJANGO_ENV", "dev").lower()
if _env == "prod":
    from .prod import *  # noqa: F403
elif _env == "qua":
    from .qua import *  # noqa: F403
else:
    from .dev import *  # noqa: F403
'@
    Write-TextFile -Path (Join-Path $settingsDir "__init__.py") -Content $settingsInit

    $baseSettings = @"
from pathlib import Path
import os

BASE_DIR = Path(__file__).resolve().parent.parent.parent

SECRET_KEY = os.environ.get(
    "DJANGO_SECRET_KEY",
    "dev-only-change-me",
)

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "rest_framework",
    "apps.$AppName",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [BASE_DIR / "templates"],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.debug",
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

WSGI_APPLICATION = "config.wsgi.application"
ASGI_APPLICATION = "config.asgi.application"

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

LANGUAGE_CODE = "fr-fr"
TIME_ZONE = "Europe/Paris"
USE_I18N = True
USE_TZ = True

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

STATIC_URL = "/static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
STATICFILES_DIRS = [BASE_DIR / "static"]

STORAGES = {
    "default": {
        "BACKEND": "django.core.files.storage.FileSystemStorage",
    },
    "staticfiles": {
        "BACKEND": "whitenoise.storage.CompressedStaticFilesStorage",
    },
}

REST_FRAMEWORK = {
    "DEFAULT_RENDERER_CLASSES": [
        "rest_framework.renderers.JSONRenderer",
    ],
    "DEFAULT_PARSER_CLASSES": [
        "rest_framework.parsers.JSONParser",
    ],
}
"@
    Write-TextFile -Path (Join-Path $settingsDir "base.py") -Content $baseSettings

    $devSettings = @'
from .base import *  # noqa: F403

DEBUG = True
ALLOWED_HOSTS = ["localhost", "127.0.0.1"]

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.sqlite3",
        "NAME": BASE_DIR / "db.sqlite3",
    }
}

EMAIL_BACKEND = "django.core.mail.backends.console.EmailBackend"
'@
    Write-TextFile -Path (Join-Path $settingsDir "dev.py") -Content $devSettings

    $quaSettings = @'
from .base import *  # noqa: F403
import os

DEBUG = False
ALLOWED_HOSTS = os.environ.get("DJANGO_ALLOWED_HOSTS", "localhost").split(",")

DATABASES = {
    "default": {
        "ENGINE": os.environ.get("DJANGO_DB_ENGINE", "django.db.backends.sqlite3"),
        "NAME": os.environ.get("DJANGO_DB_NAME", str(BASE_DIR / "db_qua.sqlite3")),
        "USER": os.environ.get("DJANGO_DB_USER", ""),
        "PASSWORD": os.environ.get("DJANGO_DB_PASSWORD", ""),
        "HOST": os.environ.get("DJANGO_DB_HOST", ""),
        "PORT": os.environ.get("DJANGO_DB_PORT", ""),
    }
}
'@
    Write-TextFile -Path (Join-Path $settingsDir "qua.py") -Content $quaSettings

    $prodSettings = @'
from .base import *  # noqa: F403
import os

DEBUG = False
ALLOWED_HOSTS = os.environ.get("DJANGO_ALLOWED_HOSTS", "").split(",")
if not ALLOWED_HOSTS or ALLOWED_HOSTS == [""]:
    raise RuntimeError("DJANGO_ALLOWED_HOSTS doit etre defini en production.")

SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY")
if not SECRET_KEY:
    raise RuntimeError("DJANGO_SECRET_KEY doit etre defini en production.")

DATABASES = {
    "default": {
        "ENGINE": os.environ.get("DJANGO_DB_ENGINE", "django.db.backends.postgresql"),
        "NAME": os.environ.get("DJANGO_DB_NAME", ""),
        "USER": os.environ.get("DJANGO_DB_USER", ""),
        "PASSWORD": os.environ.get("DJANGO_DB_PASSWORD", ""),
        "HOST": os.environ.get("DJANGO_DB_HOST", ""),
        "PORT": os.environ.get("DJANGO_DB_PORT", "5432"),
    }
}

STORAGES = {
    "default": {
        "BACKEND": "django.core.files.storage.FileSystemStorage",
    },
    "staticfiles": {
        "BACKEND": "whitenoise.storage.CompressedManifestStaticFilesStorage",
    },
}

SECURE_SSL_REDIRECT = os.environ.get("DJANGO_SECURE_SSL_REDIRECT", "true").lower() == "true"
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
'@
    Write-TextFile -Path (Join-Path $settingsDir "prod.py") -Content $prodSettings

    $configUrls = @"
from django.contrib import admin
from django.urls import include, path

urlpatterns = [
    path("admin/", admin.site.urls),
    path("", include("apps.$AppName.urls")),
]
"@
    Write-TextFile -Path (Join-Path $configDir "urls.py") -Content $configUrls
}

function New-AppServiceLayer {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$AppName
    )

    $appDir = Join-Path $Root "apps\$AppName"
    New-Item -ItemType Directory -Path (Join-Path $appDir "services") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $appDir "templates\$AppName") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $appDir "templates\$AppName\partials") -Force | Out-Null

    Write-TextFile -Path (Join-Path $appDir "services\__init__.py") -Content @'
"""Logique d'ecriture (couche service)."""
'@

    Write-TextFile -Path (Join-Path $appDir "selectors.py") -Content @'
"""Lecture / agregations (couche selector)."""


def example_selector() -> str:
    """Exemple de selector a remplacer."""
    return "selector"
'@

    Write-TextFile -Path (Join-Path $appDir "serializers.py") -Content @'
"""Serializers DRF (validation API)."""

from rest_framework import serializers
'@

    Write-TextFile -Path (Join-Path $appDir "forms.py") -Content @'
"""Formulaires Django (rendu HTML uniquement)."""

from django import forms
'@

    Write-TextFile -Path (Join-Path $appDir "urls.py") -Content @"
from django.urls import path

from . import views

app_name = "$AppName"

urlpatterns = [
    path("", views.HomeView.as_view(), name="home"),
]
"@

    Write-TextFile -Path (Join-Path $appDir "views.py") -Content @"
from django.views.generic import TemplateView


class HomeView(TemplateView):
    """Page d'accueil minimale (CBV)."""

    template_name = "$AppName/home.html"
"@

    Write-TextFile -Path (Join-Path $appDir "templates\$AppName\home.html") -Content @'
{% extends "base.html" %}
{% block title %}Accueil{% endblock %}
{% block content %}
  <h1>Bienvenue</h1>
  <p>Projet Django + uv pret (architecture 2026).</p>
{% endblock %}
'@
}

function New-StaticScssLayout {
    param([Parameter(Mandatory)][string]$Root)

    $scssRoot = Join-Path $Root "static\scss"
    $dirs = @(
        "abstracts", "base", "layout", "components", "pages", "themes", "vendors"
    )
    foreach ($d in $dirs) {
        New-Item -ItemType Directory -Path (Join-Path $scssRoot $d) -Force | Out-Null
    }

    Write-TextFile -Path (Join-Path $scssRoot "base\_root.scss") -Content @'
:root {
  --color-bg: #fafafa;
  --color-text: #18181b;
  --color-text-muted: #71717a;
  --color-border: #e4e4e7;
  --color-surface: #ffffff;
  --primary-color: #18181b;
  --primary-color-hover: #27272a;
  --primary-color-active: #3f3f46;
  --primary-color-on: #fafafa;
  --focus-ring: 0 0 0 2px #a1a1aa;
  --space-2: 0.5rem;
  --space-4: 1rem;
  --radius-md: 0.375rem;
  --font-sans: "Inter", system-ui, sans-serif;
}

[data-theme="dark"] {
  --color-bg: #09090b;
  --color-text: #fafafa;
  --color-text-muted: #a1a1aa;
  --color-border: #27272a;
  --color-surface: #18181b;
}
'@

    Write-TextFile -Path (Join-Path $scssRoot "main.scss") -Content @'
@use "base/root";

body {
  font-family: var(--font-sans);
  background: var(--color-bg);
  color: var(--color-text);
  margin: 0;
}
'@

    New-Item -ItemType Directory -Path (Join-Path $Root "static\css") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Root "static\js") -Force | Out-Null
    Write-TextFile -Path (Join-Path $Root "static\css\.gitkeep") -Content "`n"
    Write-TextFile -Path (Join-Path $Root "static\js\.gitkeep") -Content "`n"
}

function New-CursorCartography {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$AppName
    )

    $cursorDir = Join-Path $Root ".cursor"
    New-Item -ItemType Directory -Path $cursorDir -Force | Out-Null

    $structure = @"
# Structure applicative

## Racine
- ``config/`` : configuration Django (settings dev/qua/prod, urls, wsgi/asgi)
- ``apps/`` : applications metier (Service Layer strict)
- ``templates/`` : templates globaux
- ``static/`` : assets (scss sources, css compile)
- ``content/markdown/`` : contenu statique optionnel

## Apps
| App | Role |
|-----|------|
| ``apps.$AppName`` | Application metier initiale (services, selectors, serializers, CBV) |
"@
    Write-TextFile -Path (Join-Path $cursorDir "app-structure.md") -Content $structure

    $uml = @"
@startuml
package "config" {
  [settings/base]
  [settings/dev]
  [settings/qua]
  [settings/prod]
  [urls]
}
package "apps" {
  package "$AppName" {
    [models]
    [services]
    [selectors]
    [serializers]
    [views CBV]
  }
}
@enduml
"@
    Write-TextFile -Path (Join-Path $cursorDir "app-architecture.uml") -Content $uml
}

# --- Execution ---

Write-Host "=== Nouveau projet Django + uv (2026) ===" -ForegroundColor Cyan

if (-not (Test-PythonIdentifier $AppName)) {
    throw "AppName invalide : lettres, chiffres, underscore uniquement."
}

if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    throw "uv introuvable dans le PATH. https://docs.astral.sh/uv/"
}

$createdNewFolder = $false
$useCurrent = $UseCurrentFolder.IsPresent

if ($NewFolder.IsPresent -and $UseCurrentFolder.IsPresent) {
    throw "Utilisez soit -NewFolder soit -UseCurrentFolder, pas les deux."
}

if (-not $useCurrent -and -not $NewFolder.IsPresent) {
    do {
        $answer = (Read-Host "New folder ? (Y/N)").Trim()
    } while ($answer -notmatch '^[YyNn]$')

    if ($answer -match '^[Yy]$') {
        $NewFolder = $true
    } else {
        $useCurrent = $true
    }
}

if ($useCurrent) {
    if ([string]::IsNullOrWhiteSpace($ParentPath)) {
        $root = (Get-Location).Path
    } else {
        $root = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ParentPath)
    }
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        throw "Repertoire courant introuvable : $root"
    }
    if (Test-Path -LiteralPath (Join-Path $root "manage.py")) {
        throw "Ce dossier contient deja un projet Django (manage.py present)."
    }
    if (Test-Path -LiteralPath (Join-Path $root "config\settings\base.py")) {
        throw "Ce dossier est deja initialise (config/settings/base.py present)."
    }
    Write-Host "Initialisation dans le dossier actuel : $root" -ForegroundColor Green
} else {
    $projectFolder = $ProjectName.Trim()
    if ([string]::IsNullOrWhiteSpace($projectFolder)) {
        do {
            $projectFolder = (Read-Host "Nom du nouveau dossier projet").Trim()
        } while ([string]::IsNullOrWhiteSpace($projectFolder))
    }
    if ($projectFolder -match '[<>:"/\\|?*]') {
        throw "Nom de dossier invalide pour Windows."
    }

    if ([string]::IsNullOrWhiteSpace($ParentPath)) {
        $parentPath = (Get-Location).Path
    } else {
        $parentPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ParentPath)
    }
    if (-not (Test-Path -LiteralPath $parentPath)) {
        throw "Dossier parent introuvable : $parentPath"
    }

    $root = Join-Path $parentPath $projectFolder
    if (Test-Path -LiteralPath $root) {
        $existing = Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue
        if ($existing -and $existing.Count -gt 0) {
            throw "Le dossier existe deja et n'est pas vide : $root"
        }
    } else {
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $createdNewFolder = $true
    }
    Write-Host "Nouveau dossier : $projectFolder | Cible : $root" -ForegroundColor Green
}

$uvName = (Split-Path -Leaf $root) -replace '[^a-zA-Z0-9_]', '_'
if ($uvName -match '^[0-9]') { $uvName = "_$uvName" }

Write-Host "App metier : $AppName" -ForegroundColor Green

try {
    Write-Host "`n[1/6] uv init + dependances …" -ForegroundColor Yellow
    Invoke-CheckedCommand -Exe "uv" -Arguments @("init", "--name", $uvName) -WorkingDirectory $root
    Invoke-CheckedCommand -Exe "uv" -Arguments @(
        "add", "django", "djangorestframework", "whitenoise"
    ) -WorkingDirectory $root

    $mainPy = Join-Path $root "main.py"
    if (Test-Path -LiteralPath $mainPy) {
        Remove-Item -LiteralPath $mainPy -Force
    }

    Write-Host "`n[2/6] config/ + settings/ (sans startproject) …" -ForegroundColor Yellow
    New-DjangoConfigPackage -Root $root -AppName $AppName

    Write-Host "`n[3/6] apps/ + Service Layer …" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path (Join-Path $root "apps") -Force | Out-Null
    Write-TextFile -Path (Join-Path $root "apps\__init__.py") -Content @'
"""Applications metier du projet."""
'@

    Invoke-CheckedCommand -Exe "uv" -Arguments @(
        "run", "django-admin", "startapp", $AppName, "apps\$AppName"
    ) -WorkingDirectory $root

    $appsPyPath = Join-Path $root "apps\$AppName\apps.py"
    if (Test-Path -LiteralPath $appsPyPath) {
        $appsPy = Get-Content -LiteralPath $appsPyPath -Raw -Encoding UTF8
        $appsPy = $appsPy -replace "name = ['\`"]$AppName['\`"]", "name = `"apps.$AppName`""
        Write-TextFile -Path $appsPyPath -Content $appsPy
    }

    New-AppServiceLayer -Root $root -AppName $AppName

    Write-Host "`n[4/6] templates, static/scss, content …" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path (Join-Path $root "templates") -Force | Out-Null
    Write-TextFile -Path (Join-Path $root "templates\base.html") -Content @'
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{% block title %}Projet{% endblock %}</title>
  <link rel="stylesheet" href="/static/css/main.css">
  {% block extra_head %}{% endblock %}
</head>
<body>
  <main>
    {% block content %}{% endblock %}
  </main>
</body>
</html>
'@

    New-StaticScssLayout -Root $root

    $contentMd = Join-Path $root "content\markdown"
    New-Item -ItemType Directory -Path $contentMd -Force | Out-Null
    Write-TextFile -Path (Join-Path $contentMd ".gitkeep") -Content "`n"

    New-CursorCartography -Root $root -AppName $AppName

    Write-TextFile -Path (Join-Path $root ".env.example") -Content @"
# Copier vers .env (ne jamais committer .env)

DJANGO_SETTINGS_MODULE=config.settings
DJANGO_ENV=dev
DJANGO_SECRET_KEY=change-me

# Production / qua
# DJANGO_ALLOWED_HOSTS=example.com,www.example.com
# DJANGO_DB_ENGINE=django.db.backends.postgresql
# DJANGO_DB_NAME=
# DJANGO_DB_USER=
# DJANGO_DB_PASSWORD=
# DJANGO_DB_HOST=
# DJANGO_DB_PORT=5432
"@

    Write-Host "`n[5/6] Verification structure …" -ForegroundColor Yellow
    $required = @(
        "manage.py",
        "config\settings\base.py",
        "config\settings\dev.py",
        "config\urls.py",
        "apps\$AppName\models.py",
        "apps\$AppName\services\__init__.py",
        "apps\$AppName\selectors.py",
        "apps\$AppName\serializers.py"
    )
    foreach ($rel in $required) {
        $full = Join-Path $root $rel
        if (-not (Test-Path -LiteralPath $full)) {
            throw "Structure incomplete, fichier manquant : $rel"
        }
    }

    Write-Host "`n[6/6] Migrations initiales …" -ForegroundColor Yellow
    Invoke-CheckedCommand -Exe "uv" -Arguments @(
        "run", "python", "manage.py", "migrate"
    ) -WorkingDirectory $root

    Write-Host "`nTermine." -ForegroundColor Green
    Write-Host "Repertoire : $root"
    Write-Host "Serveur     : cd `"$root`" ; uv run python manage.py runserver"
    Write-Host "Settings    : config.settings (DJANGO_ENV=dev|qua|prod)"
}
catch {
    if ($createdNewFolder -and (Test-Path -LiteralPath $root)) {
        Write-Host "Nettoyage du dossier partiel : $root" -ForegroundColor DarkYellow
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    } elseif (-not $createdNewFolder) {
        Write-Host "Echec dans le dossier courant (aucune suppression automatique)." -ForegroundColor DarkYellow
    }
    throw
}
