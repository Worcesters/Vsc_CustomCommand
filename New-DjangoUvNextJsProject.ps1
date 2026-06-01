#Requires -Version 5.1
<#
.SYNOPSIS
  Cree un monorepo Django + uv + Next.js + Docker avec pipeline visuel.

.DESCRIPTION
  Pipeline en 12 etapes : uv, Django (Service Layer), SCSS 7-1, Next.js App Router,
  Docker Compose, regles Cursor/skills, outillage qualite (ruff, pytest).

.PARAMETER ProjectName
  Nom du nouveau dossier (si -NewFolder).

.PARAMETER AppName
  Slug de l'app metier sous apps/ (defaut : core).

.PARAMETER ParentPath
  Dossier parent pour un nouveau dossier.

.PARAMETER NewFolder
  Force la creation d'un sous-dossier.

.PARAMETER UseCurrentFolder
  Force l'initialisation dans le repertoire courant.

.PARAMETER SkipFrontend
  Ignore la generation Next.js (frontend/).

.PARAMETER SkipDocker
  Ignore Docker (Dockerfile, compose).

.PARAMETER InstallFrontendDeps
  Lance pnpm/npm install dans frontend/ (peut etre long).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\New-DjangoUvProject.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\New-DjangoUvProject.ps1 -NewFolder mon_site -AppName blog
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
    [switch]$UseCurrentFolder,
    [switch]$SkipFrontend,
    [switch]$SkipDocker,
    [switch]$InstallFrontendDeps
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Pipeline UI ---
$script:PipelineTotal = 10
$script:PipelineStep = 0
$script:StepWatch = $null

function Write-PipelineBanner {
    param([string]$Subtitle = "")
    $line = ("=" * 62)
    Write-Host ""
    Write-Host "  $line" -ForegroundColor Cyan
    Write-Host "  |  MONOREPO DJANGO + UV + NEXT.JS + DOCKER  (2026)       |" -ForegroundColor Cyan
    if ($Subtitle) {
        Write-Host "  |  $($Subtitle.PadRight(54)) |" -ForegroundColor DarkCyan
    }
    Write-Host "  $line" -ForegroundColor Cyan
    Write-Host ""
}

function Write-PipelineBar {
    $done = [math]::Max(0, $script:PipelineStep - 1)
    $pct = [int]([math]::Min(100, ($done / $script:PipelineTotal) * 100))
    $width = 28
    $filled = [int]([math]::Round($width * $pct / 100))
    $bar = ("#" * $filled) + ("-" * ($width - $filled))
    Write-Host "  [$bar] $pct%  ($done/$script:PipelineTotal)" -ForegroundColor DarkGray
}

function Start-PipelineStep {
    param(
        [Parameter(Mandatory)][string]$Title,
        [string]$Detail = ""
    )
    $script:PipelineStep++
    Write-Host ""
    Write-PipelineBar
    Write-Host "  >> Etape $($script:PipelineStep)/$($script:PipelineTotal) : $Title" -ForegroundColor Yellow
    if ($Detail) {
        Write-Host "     $Detail" -ForegroundColor DarkGray
    }
    $script:StepWatch = [System.Diagnostics.Stopwatch]::StartNew()
}

function Complete-PipelineStep {
    param([string]$Message = "termine")
    if ($null -ne $script:StepWatch) {
        $script:StepWatch.Stop()
        $sec = [math]::Round($script:StepWatch.Elapsed.TotalSeconds, 1)
        Write-Host "     [OK] $Message (${sec}s)" -ForegroundColor Green
    } else {
        Write-Host "     [OK] $Message" -ForegroundColor Green
    }
}

function Write-PipelineSummary {
    param(
        [string]$Root,
        [string]$AppName,
        [bool]$HasFrontend,
        [bool]$HasDocker
    )
    Write-Host ""
    Write-Host ("=" * 62) -ForegroundColor Green
    Write-Host "  PROJET PRET" -ForegroundColor Green
    Write-Host ("=" * 62) -ForegroundColor Green
    Write-Host "  Racine      : $Root"
    Write-Host "  App Django  : apps.$AppName"
    Write-Host ""
    Write-Host "  Backend (dev) :" -ForegroundColor White
    Write-Host "    cd `"$Root`""
    Write-Host "    uv run python manage.py runserver"
    if ($HasFrontend) {
        Write-Host ""
        Write-Host "  Frontend (dev) :" -ForegroundColor White
        Write-Host "    cd `"$Root\frontend`""
        Write-Host "    pnpm install   # ou npm install"
        Write-Host "    pnpm dev"
    }
    if ($HasDocker) {
        Write-Host ""
        Write-Host "  Docker (stack complete) :" -ForegroundColor White
        Write-Host "    cd `"$Root`""
        Write-Host "    docker compose -f docker-compose.dev.yml up --build"
    }
    Write-Host ""
    Write-Host "  Cursor      : .cursor/AGENTS.md + .cursor/rules/" -ForegroundColor DarkGray
    Write-Host ""
}

# --- Utilitaires ---

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

function Resolve-ExecutablePath {
    param([Parameter(Mandatory)][string]$Name)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) { return $null }
    return $cmd.Source
}

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory)][string]$Exe,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [switch]$Quiet
    )
    $exePath = Resolve-ExecutablePath -Name $Exe
    if (-not $exePath) {
        throw "Executable introuvable : $Exe"
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exePath
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
    if (-not $Quiet -and $out) {
        $trimmed = $out.TrimEnd()
        if ($trimmed.Length -gt 0) { Write-Host "     $trimmed" -ForegroundColor DarkGray }
    }
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
from __future__ import annotations

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
from __future__ import annotations

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
    "corsheaders",
    "apps.$AppName",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",
    "corsheaders.middleware.CorsMiddleware",
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
    "DEFAULT_PERMISSION_CLASSES": [
        "rest_framework.permissions.IsAuthenticatedOrReadOnly",
    ],
}

_cors = os.environ.get("CORS_ALLOWED_ORIGINS", "http://localhost:3000")
CORS_ALLOWED_ORIGINS = [o.strip() for o in _cors.split(",") if o.strip()]
CORS_ALLOW_CREDENTIALS = True
"@
    Write-TextFile -Path (Join-Path $settingsDir "base.py") -Content $baseSettings

    $devSettings = @'
from .base import *  # noqa: F403
import os

DEBUG = True
ALLOWED_HOSTS = ["localhost", "127.0.0.1", "web"]

if os.environ.get("DJANGO_DB_HOST"):
    DATABASES = {
        "default": {
            "ENGINE": os.environ.get(
                "DJANGO_DB_ENGINE", "django.db.backends.postgresql"
            ),
            "NAME": os.environ.get("DJANGO_DB_NAME", "app"),
            "USER": os.environ.get("DJANGO_DB_USER", "app"),
            "PASSWORD": os.environ.get("DJANGO_DB_PASSWORD", ""),
            "HOST": os.environ["DJANGO_DB_HOST"],
            "PORT": os.environ.get("DJANGO_DB_PORT", "5432"),
        }
    }
else:
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
        "ENGINE": os.environ.get("DJANGO_DB_ENGINE", "django.db.backends.postgresql"),
        "NAME": os.environ.get("DJANGO_DB_NAME", "app"),
        "USER": os.environ.get("DJANGO_DB_USER", "app"),
        "PASSWORD": os.environ.get("DJANGO_DB_PASSWORD", ""),
        "HOST": os.environ.get("DJANGO_DB_HOST", "db"),
        "PORT": os.environ.get("DJANGO_DB_PORT", "5432"),
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
    path("api/", include("apps.$AppName.urls")),
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
    New-Item -ItemType Directory -Path (Join-Path $appDir "templates\$AppName\partials") -Force | Out-Null

    Write-TextFile -Path (Join-Path $appDir "services.py") -Content @'
"""Logique d'ecriture (couche service)."""


def example_action() -> str:
    """Exemple de service a remplacer."""
    return "service"
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
from __future__ import annotations

from django.views.generic import TemplateView


class HomeView(TemplateView):
    \"\"\"Page d'accueil admin/HTMX (CBV).

    MRO:
    1. TemplateView.get -> rendu template $AppName/home.html
    \"\"\"

    template_name = "$AppName/home.html"
"@

    Write-TextFile -Path (Join-Path $appDir "templates\$AppName\home.html") -Content @'
{% extends "base.html" %}
{% block title %}Accueil{% endblock %}
{% block content %}
  <section class="page-home">
    <h1 class="page-home__title">Bienvenue</h1>
    <p class="page-home__lead">Monorepo Django + uv + Next.js pret.</p>
    <p>UI produit : <code>frontend/</code> (Next.js). Admin/HTMX : ce template.</p>
  </section>
{% endblock %}
'@
}

function New-StaticScssLayout {
    param([Parameter(Mandatory)][string]$Root)

    $scssRoot = Join-Path $Root "static\scss"
    $dirs = @("abstracts", "base", "layout", "components", "pages", "themes", "vendors")
    foreach ($d in $dirs) {
        New-Item -ItemType Directory -Path (Join-Path $scssRoot $d) -Force | Out-Null
    }

    Write-TextFile -Path (Join-Path $scssRoot "abstracts\_mixins.scss") -Content @'
@mixin respond-to($breakpoint) {
  @if $breakpoint == sm {
    @media (min-width: 40rem) { @content; }
  } @else if $breakpoint == md {
    @media (min-width: 48rem) { @content; }
  } @else if $breakpoint == lg {
    @media (min-width: 64rem) { @content; }
  } @else if $breakpoint == xl {
    @media (min-width: 80rem) { @content; }
  } @else if $breakpoint == 2xl {
    @media (min-width: 96rem) { @content; }
  }
}
'@

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
  --secondary-color: #52525b;
  --secondary-color-hover: #3f3f46;
  --secondary-color-active: #27272a;
  --secondary-color-on: #fafafa;
  --accent-color: #2563eb;
  --accent-color-hover: #1d4ed8;
  --accent-color-active: #1e40af;
  --accent-color-on: #eff6ff;
  --success-color: #16a34a;
  --warning-color: #ca8a04;
  --danger-color: #dc2626;
  --info-color: #0891b2;
  --focus-ring: 0 0 0 2px #a1a1aa;
  --space-2: 0.5rem;
  --space-4: 1rem;
  --space-6: 1.5rem;
  --radius-md: 0.375rem;
  --font-sans: "Inter", "Geist", system-ui, sans-serif;
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

.page-home__title {
  margin: 0 0 var(--space-2);
}

.page-home__lead {
  color: var(--color-text-muted);
}
'@

    New-Item -ItemType Directory -Path (Join-Path $Root "static\css") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Root "static\js") -Force | Out-Null
    Write-TextFile -Path (Join-Path $Root "static\css\.gitkeep") -Content "`n"
    Write-TextFile -Path (Join-Path $Root "static\js\.gitkeep") -Content "`n"
}

function New-NextJsFrontend {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ProjectSlug
    )

    $fe = Join-Path $Root "frontend"
    $appDir = Join-Path $fe "src\app"
    $stylesDir = Join-Path $fe "src\styles"
    New-Item -ItemType Directory -Path $appDir -Force | Out-Null
    New-Item -ItemType Directory -Path $stylesDir -Force | Out-Null

    Write-TextFile -Path (Join-Path $fe "package.json") -Content @"
{
  "name": "$ProjectSlug-frontend",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "next dev --hostname 0.0.0.0 -p 3000",
    "build": "next build",
    "start": "next start -H 0.0.0.0 -p 3000",
    "lint": "next lint"
  },
  "dependencies": {
    "next": "^15.1.0",
    "react": "^19.0.0",
    "react-dom": "^19.0.0"
  },
  "devDependencies": {
    "@types/node": "^22.10.0",
    "@types/react": "^19.0.0",
    "@types/react-dom": "^19.0.0",
    "eslint": "^9.0.0",
    "eslint-config-next": "^15.1.0",
    "sass": "^1.83.0",
    "typescript": "^5.7.0"
  }
}
"@

    Write-TextFile -Path (Join-Path $fe "next.config.ts") -Content @'
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "standalone",
  sassOptions: {
    includePaths: ["./src/styles"],
  },
};

export default nextConfig;
'@

    Write-TextFile -Path (Join-Path $fe "tsconfig.json") -Content @'
{
  "compilerOptions": {
    "target": "ES2017",
    "lib": ["dom", "dom.iterable", "esnext"],
    "allowJs": true,
    "skipLibCheck": true,
    "strict": true,
    "noEmit": true,
    "esModuleInterop": true,
    "module": "esnext",
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "preserve",
    "incremental": true,
    "plugins": [{ "name": "next" }],
    "paths": { "@/*": ["./src/*"] }
  },
  "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx", ".next/types/**/*.ts"],
  "exclude": ["node_modules"]
}
'@

    Write-TextFile -Path (Join-Path $fe "next-env.d.ts") -Content @'
/// <reference types="next" />
/// <reference types="next/image-types/global" />
'@

    Write-TextFile -Path (Join-Path $stylesDir "_tokens.scss") -Content @'
:root {
  --color-bg: #fafafa;
  --color-text: #18181b;
  --color-text-muted: #71717a;
  --color-border: #e4e4e7;
  --color-surface: #ffffff;
  --primary-color: #18181b;
  --primary-color-on: #fafafa;
  --space-4: 1rem;
  --font-sans: "Inter", "Geist", system-ui, sans-serif;
}
'@

    Write-TextFile -Path (Join-Path $stylesDir "globals.scss") -Content @'
@use "tokens";

* {
  box-sizing: border-box;
}

body {
  margin: 0;
  font-family: var(--font-sans);
  background: var(--color-bg);
  color: var(--color-text);
}

.shell {
  display: flex;
  flex-direction: column;
  min-height: 100vh;
  padding: var(--space-4);
}

.shell__title {
  margin: 0 0 var(--space-4);
}

.shell__muted {
  color: var(--color-text-muted);
}
'@

    Write-TextFile -Path (Join-Path $appDir "layout.tsx") -Content @'
import type { Metadata } from "next";
import "@/styles/globals.scss";

export const metadata: Metadata = {
  title: "App",
  description: "Frontend Next.js — API Django/DRF",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="fr">
      <body>{children}</body>
    </html>
  );
}
'@

    Write-TextFile -Path (Join-Path $appDir "page.tsx") -Content @'
const apiUrl = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8000";

export default function HomePage() {
  return (
    <main className="shell">
      <h1 className="shell__title">Next.js + Django</h1>
      <p className="shell__muted">
        UI produit (App Router). Metier via API :{" "}
        <code>{apiUrl}</code>
      </p>
    </main>
  );
}
'@

    Write-TextFile -Path (Join-Path $fe ".env.example") -Content @"
NEXT_PUBLIC_API_URL=http://localhost:8000
"@

    Write-TextFile -Path (Join-Path $fe ".gitignore") -Content @'
node_modules/
.next/
out/
.env*.local
'@

    Write-TextFile -Path (Join-Path $fe "Dockerfile") -Content @'
FROM node:22-alpine AS deps
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@latest --activate
COPY package.json ./
RUN pnpm install --no-frozen-lockfile

FROM deps AS builder
COPY . .
ARG NEXT_PUBLIC_API_URL=http://localhost:8000
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL
RUN pnpm build

FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public ./public
EXPOSE 3000
CMD ["node", "server.js"]
'@
}

function New-DockerStack {
    param([Parameter(Mandatory)][string]$Root)

    Write-TextFile -Path (Join-Path $Root "Dockerfile") -Content @'
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS base
WORKDIR /app
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev
COPY . .
EXPOSE 8000
CMD ["uv", "run", "gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:8000"]
'@

    Write-TextFile -Path (Join-Path $Root ".dockerignore") -Content @'
.venv/
__pycache__/
*.pyc
db.sqlite3
staticfiles/
.git/
frontend/node_modules/
frontend/.next/
.env
'@

    Write-TextFile -Path (Join-Path $Root "docker-compose.dev.yml") -Content @'
services:
  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: app
      POSTGRES_USER: app
      POSTGRES_PASSWORD: dev
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app -d app"]
      interval: 5s
      timeout: 5s
      retries: 5

  web:
    build:
      context: .
      dockerfile: Dockerfile
    command: uv run python manage.py runserver 0.0.0.0:8000
    volumes:
      - .:/app
    environment:
      DJANGO_ENV: dev
      DJANGO_SETTINGS_MODULE: config.settings
      DJANGO_SECRET_KEY: dev-docker-only
      DJANGO_DB_ENGINE: django.db.backends.postgresql
      DJANGO_DB_NAME: app
      DJANGO_DB_USER: app
      DJANGO_DB_PASSWORD: dev
      DJANGO_DB_HOST: db
      DJANGO_DB_PORT: "5432"
      CORS_ALLOWED_ORIGINS: http://localhost:3000
    ports:
      - "8000:8000"
    depends_on:
      db:
        condition: service_healthy

  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile
      target: deps
    command: pnpm dev
    volumes:
      - ./frontend:/app
      - frontend_node_modules:/app/node_modules
    environment:
      NEXT_PUBLIC_API_URL: http://localhost:8000
    ports:
      - "3000:3000"
    depends_on:
      - web

volumes:
  pgdata:
  frontend_node_modules:
'@

    Write-TextFile -Path (Join-Path $Root "docker-compose.yml") -Content @'
services:
  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: ${POSTGRES_DB:-app}
      POSTGRES_USER: ${POSTGRES_USER:-app}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?required}
    volumes:
      - pgdata:/var/lib/postgresql/data

  web:
    build: .
    environment:
      DJANGO_ENV: prod
      DJANGO_SECRET_KEY: ${DJANGO_SECRET_KEY:?required}
      DJANGO_ALLOWED_HOSTS: ${DJANGO_ALLOWED_HOSTS:?required}
      DJANGO_DB_ENGINE: django.db.backends.postgresql
      DJANGO_DB_NAME: ${POSTGRES_DB:-app}
      DJANGO_DB_USER: ${POSTGRES_USER:-app}
      DJANGO_DB_PASSWORD: ${POSTGRES_PASSWORD:?required}
      DJANGO_DB_HOST: db
      CORS_ALLOWED_ORIGINS: ${CORS_ALLOWED_ORIGINS:-https://example.com}
    depends_on:
      - db
    ports:
      - "8000:8000"

  frontend:
    build:
      context: ./frontend
      args:
        NEXT_PUBLIC_API_URL: ${NEXT_PUBLIC_API_URL:-http://localhost:8000}
    ports:
      - "3000:3000"
    depends_on:
      - web

volumes:
  pgdata:
'@
}

function New-QualityTooling {
    param([Parameter(Mandatory)][string]$Root)

    $testsDir = Join-Path $Root "tests"
    New-Item -ItemType Directory -Path $testsDir -Force | Out-Null
    Write-TextFile -Path (Join-Path $testsDir "__init__.py") -Content "`n"
    Write-TextFile -Path (Join-Path $testsDir "conftest.py") -Content @'
"""Fixtures Pytest Django."""
import pytest


@pytest.fixture
def api_client():
  """Client DRF pour tests API."""
  from rest_framework.test import APIClient
  return APIClient()
'@

    Write-TextFile -Path (Join-Path $Root "pytest.ini") -Content @'
[pytest]
DJANGO_SETTINGS_MODULE = config.settings
python_files = tests.py test_*.py *_tests.py
addopts = -ra
'@
}

function New-CursorProjectRules {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$AppName
    )

    $cursorDir = Join-Path $Root ".cursor"
    $rulesDir = Join-Path $cursorDir "rules"
    $skillsDir = Join-Path $cursorDir "skills"
    New-Item -ItemType Directory -Path $rulesDir -Force | Out-Null
    New-Item -ItemType Directory -Path $skillsDir -Force | Out-Null

    $structure = @"
# Structure applicative

## Racine monorepo
| Chemin | Role |
|--------|------|
| ``config/`` | Settings Django (dev/qua/prod), urls, wsgi/asgi |
| ``apps/`` | Apps metier (Service Layer strict) |
| ``templates/`` | Templates globaux (admin / HTMX) |
| ``static/scss/`` | SCSS 7-1 Flat High-End (Django admin) |
| ``frontend/`` | Next.js App Router (UI produit) |
| ``tests/`` | Pytest |
| ``docker-compose*.yml`` | Stack locale / prod |

## Apps Django
| App | Role |
|-----|------|
| ``apps.$AppName`` | App initiale : models, services, selectors, serializers, CBV |

## Front Next.js
- Pas de logique metier : fetch vers API Django/DRF uniquement.
- SCSS + tokens ``:root`` (pas de Tailwind).
- ``NEXT_PUBLIC_API_URL`` pour l'URL API.
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
package "frontend" {
  [Next.js App Router]
  [fetch API DRF]
}
database "PostgreSQL" as db
[apps] --> db : ORM
[frontend] --> [serializers] : HTTP JSON
@enduml
"@
    Write-TextFile -Path (Join-Path $cursorDir "app-architecture.uml") -Content $uml

    Write-TextFile -Path (Join-Path $cursorDir "AGENTS.md") -Content @"
# Agents Cursor — monorepo Django + Next.js

## Lead par defaut
**@ProjectManager** — plan d'action, dispatch, Definition of Done.

## Matrice rapide
| Sujet | Agent |
|-------|--------|
| Service Layer, CBV, DRF, MRO | @Architect (django-architect) |
| SCSS, tokens, BEM, HTMX admin | @UI-Engineer |
| Next.js App Router, RSC | nextjs-specialist |
| Docker, compose, CI | devops-engineer |
| CSRF, permissions, prod | security-auditor |
| ORM, N+1, SQL | database-optimizer |
| Pytest, edge cases | qa-specialist |
| Regles metier Python | logic-dev |

Skills globales : ``~/.cursor/skills/<nom>/SKILL.md``
"@

    Write-TextFile -Path (Join-Path $skillsDir "STACK.md") -Content @"
# Conventions stack (genere par New-DjangoUvProject.ps1)

## Python / Django
- Python 3.12+, typing strict, ``from __future__ import annotations``
- ``uv`` exclusif (``uv add``, ``uv sync``, ``uv run``)
- Service Layer : ``services.py`` (write), ``selectors.py`` (read), ``views.py`` = CBV uniquement
- Pas de logique metier dans models, signals, templates, forms
- DRF pour API consommee par Next.js

## UI Django (admin / HTMX)
- SCSS 7-1, tokens ``:root``, BEM, mobile-first, flexbox
- HTMX pour interactions sans full reload
- **Tailwind interdit**

## UI Next.js (frontend/)
- App Router, Server Components par defaut
- Pas de logique metier cote client
- SCSS + variables CSS (alignees Django)
- ``NEXT_PUBLIC_API_URL`` uniquement pour URL publique API

## Docker
- ``docker compose -f docker-compose.dev.yml up --build``
- Backend : image ``uv`` ; Frontend : Node 22 + standalone Next

## Definition of Done (rappel)
- [ ] Services/selectors separes ; CBV documentees (MRO si mixins)
- [ ] Tests Pytest (happy + edge + failure) pour chaque nouveau service
- [ ] ``ruff`` + ``mypy --strict`` sans warning sur code touche
- [ ] Mettre a jour ``.cursor/app-structure.md`` si structure change
"@

    $ruleContent = @"
---
description: Stack projet Django + uv + Next.js + Docker
globs: ["**/*"]
alwaysApply: true
---

# Stack monorepo (genere)

## Architecture
- Django racine : ``config/settings/`` (base, dev, qua, prod)
- ``apps/`` : Service Layer strict
- ``frontend/`` : Next.js UI produit (pas HTMX)
- API : prefixe ``/api/`` + DRF serializers

## Interdits
- pip/poetry/pipenv (uv uniquement)
- Fonctions dans ``views.py`` (CBV seulement)
- Tailwind / utility-first CSS
- Logique metier dans signals ou templates
- ``DEBUG=True`` en prod

## Orchestration Cursor
Lire ``.cursor/AGENTS.md`` et ``.cursor/skills/STACK.md`` en debut de tache.
"@
    Write-TextFile -Path (Join-Path $rulesDir "00-project-stack.mdc") -Content $ruleContent
}

function New-RootGitignore {
    param([Parameter(Mandatory)][string]$Root)
    Write-TextFile -Path (Join-Path $Root ".gitignore") -Content @'
.venv/
__pycache__/
*.py[cod]
*.sqlite3
db.sqlite3
staticfiles/
.env
.env.local
*.egg-info/
.pytest_cache/
.mypy_cache/
.ruff_cache/
.idea/
.vscode/
frontend/node_modules/
frontend/.next/
frontend/out/
'@
}

function New-ProjectReadme {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$AppName,
        [bool]$HasFrontend,
        [bool]$HasDocker
    )
    $fe = if ($HasFrontend) { @"

## Frontend (Next.js)
``````bash
cd frontend
pnpm install
pnpm dev
``````
"@ } else { "" }

    $dk = if ($HasDocker) { @"

## Docker
``````bash
docker compose -f docker-compose.dev.yml up --build
``````
"@ } else { "" }

    $readme = @"
# Projet monorepo Django + uv$(if ($HasFrontend) { " + Next.js" })$(if ($HasDocker) { " + Docker" })

## Backend
``````bash
uv sync
uv run python manage.py migrate
uv run python manage.py runserver
``````

App metier initiale : ``apps.$AppName``
$fe$dk

## Cursor
Voir ``.cursor/AGENTS.md`` et ``.cursor/skills/STACK.md``.
"@
    Write-TextFile -Path (Join-Path $Root "README.md") -Content $readme
}

function Test-ProjectStructure {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$AppName,
        [bool]$ExpectFrontend,
        [bool]$ExpectDocker
    )
    $required = @(
        "manage.py",
        "config\settings\base.py",
        "config\settings\dev.py",
        "config\urls.py",
        "apps\$AppName\models.py",
        "apps\$AppName\services.py",
        "apps\$AppName\selectors.py",
        "apps\$AppName\serializers.py",
        ".cursor\AGENTS.md",
        ".cursor\rules\00-project-stack.mdc"
    )
    if ($ExpectFrontend) {
        $required += @(
            "frontend\package.json",
            "frontend\src\app\page.tsx",
            "frontend\next.config.ts"
        )
    }
    if ($ExpectDocker) {
        $required += @("Dockerfile", "docker-compose.dev.yml")
    }
    foreach ($rel in $required) {
        $full = Join-Path $Root $rel
        if (-not (Test-Path -LiteralPath $full)) {
            throw "Structure incomplete, fichier manquant : $rel"
        }
    }
}

function Install-FrontendDependencies {
    param([Parameter(Mandatory)][string]$FrontendRoot)
    foreach ($tool in @("pnpm", "npm")) {
        if (-not (Resolve-ExecutablePath -Name $tool)) { continue }
        try {
            Invoke-CheckedCommand -Exe $tool -Arguments @("install") -WorkingDirectory $FrontendRoot -Quiet
            return $tool
        } catch {
            Write-Host "     $tool install ignore : $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }
    Write-Host "     Installez les deps : cd frontend && pnpm install" -ForegroundColor DarkYellow
    return $null
}

# --- Execution principale ---

Write-PipelineBanner -Subtitle "Initialisation interactive"

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
        $answer = (Read-Host "Nouveau dossier projet ? (Y/N)").Trim()
    } while ($answer -notmatch '^[YyNn]$')
    if ($answer -match '^[Yy]$') { $NewFolder = $true } else { $useCurrent = $true }
}

if ($useCurrent) {
    if ([string]::IsNullOrWhiteSpace($ParentPath)) {
        $root = (Get-Location).Path
    } else {
        $root = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ParentPath)
    }
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        throw "Repertoire introuvable : $root"
    }
    if (Test-Path -LiteralPath (Join-Path $root "manage.py")) {
        throw "Projet Django deja present (manage.py)."
    }
    Write-Host "  Cible : dossier courant" -ForegroundColor Green
    Write-Host "  $root" -ForegroundColor Green
} else {
    $projectFolder = $ProjectName.Trim()
    if ([string]::IsNullOrWhiteSpace($projectFolder)) {
        do {
            $projectFolder = (Read-Host "Nom du nouveau dossier").Trim()
        } while ([string]::IsNullOrWhiteSpace($projectFolder))
    }
    if ($projectFolder -match '[<>:"/\\|?*]') {
        throw "Nom de dossier invalide pour Windows."
    }
    $parentPath = if ([string]::IsNullOrWhiteSpace($ParentPath)) {
        (Get-Location).Path
    } else {
        $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ParentPath)
    }
    if (-not (Test-Path -LiteralPath $parentPath)) {
        throw "Dossier parent introuvable : $parentPath"
    }
    $root = Join-Path $parentPath $projectFolder
    if (Test-Path -LiteralPath $root) {
        $existing = Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue
        if ($existing -and $existing.Count -gt 0) {
            throw "Dossier non vide : $root"
        }
    } else {
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $createdNewFolder = $true
    }
    Write-Host "  Nouveau dossier : $projectFolder" -ForegroundColor Green
    Write-Host "  $root" -ForegroundColor Green
}

$uvName = (Split-Path -Leaf $root) -replace '[^a-zA-Z0-9_]', '_'
if ($uvName -match '^[0-9]') { $uvName = "_$uvName" }

$doFrontend = -not $SkipFrontend.IsPresent
$doDocker = -not $SkipDocker.IsPresent

Write-PipelineBanner -Subtitle "App: $AppName | Frontend: $doFrontend | Docker: $doDocker"

try {
    Start-PipelineStep -Title "Environnement uv" -Detail "init + dependances runtime et dev"
    Invoke-CheckedCommand -Exe "uv" -Arguments @("init", "--name", $uvName) -WorkingDirectory $root -Quiet
    Invoke-CheckedCommand -Exe "uv" -Arguments @(
        "add", "django", "djangorestframework", "whitenoise", "django-cors-headers", "gunicorn"
    ) -WorkingDirectory $root -Quiet
    Invoke-CheckedCommand -Exe "uv" -Arguments @(
        "add", "--dev", "ruff", "pytest", "pytest-django", "mypy", "django-stubs"
    ) -WorkingDirectory $root -Quiet
    $mainPy = Join-Path $root "main.py"
    if (Test-Path -LiteralPath $mainPy) { Remove-Item -LiteralPath $mainPy -Force }
    Complete-PipelineStep -Message "pyproject.toml + uv.lock"

    Start-PipelineStep -Title "Configuration Django" -Detail "config/ + settings dev|qua|prod"
    New-DjangoConfigPackage -Root $root -AppName $AppName
    Complete-PipelineStep

    Start-PipelineStep -Title "Application metier" -Detail "apps/$AppName + Service Layer"
    New-Item -ItemType Directory -Path (Join-Path $root "apps") -Force | Out-Null
    Write-TextFile -Path (Join-Path $root "apps\__init__.py") -Content @'
"""Applications metier du projet."""
'@
    Invoke-CheckedCommand -Exe "uv" -Arguments @(
        "run", "django-admin", "startapp", $AppName, "apps\$AppName"
    ) -WorkingDirectory $root -Quiet
    $appsPyPath = Join-Path $root "apps\$AppName\apps.py"
    if (Test-Path -LiteralPath $appsPyPath) {
        $appsPy = Get-Content -LiteralPath $appsPyPath -Raw -Encoding UTF8
        $appsPy = $appsPy -replace "name = ['\`"]$AppName['\`"]", "name = `"apps.$AppName`""
        Write-TextFile -Path $appsPyPath -Content $appsPy
    }
    New-AppServiceLayer -Root $root -AppName $AppName
    Complete-PipelineStep

    Start-PipelineStep -Title "Templates et assets SCSS" -Detail "7-1 Flat High-End + base.html HTMX-ready"
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
  <main class="layout-main">
    {% block content %}{% endblock %}
  </main>
  <script src="https://unpkg.com/htmx.org@2.0.4" defer></script>
  {% block extra_body %}{% endblock %}
</body>
</html>
'@
    New-StaticScssLayout -Root $root
    $contentMd = Join-Path $root "content\markdown"
    New-Item -ItemType Directory -Path $contentMd -Force | Out-Null
    Write-TextFile -Path (Join-Path $contentMd ".gitkeep") -Content "`n"
    Complete-PipelineStep

    if ($doFrontend) {
        Start-PipelineStep -Title "Frontend Next.js" -Detail "App Router + SCSS tokens (sans Tailwind)"
        New-NextJsFrontend -Root $root -ProjectSlug $uvName
        $pkgMgr = $null
        if ($InstallFrontendDeps.IsPresent) {
            $pkgMgr = Install-FrontendDependencies -FrontendRoot (Join-Path $root "frontend")
        } else {
            Write-Host '     Fichiers generes - cd frontend; pnpm install' -ForegroundColor DarkGray
        }
        Complete-PipelineStep -Message $(if ($pkgMgr) { "deps $pkgMgr" } else { "squelette Next.js" })
    } else {
        Write-Host "     (SkipFrontend)" -ForegroundColor DarkYellow
    }

    if ($doDocker) {
        Start-PipelineStep -Title "Docker" -Detail "Dockerfile + compose dev/prod"
        New-DockerStack -Root $root
        Complete-PipelineStep
    } else {
        Write-Host "     (SkipDocker)" -ForegroundColor DarkYellow
    }

    Start-PipelineStep -Title "Regles Cursor et skills" -Detail "AGENTS.md, STACK.md, rule MDC"
    New-CursorProjectRules -Root $root -AppName $AppName
    Complete-PipelineStep

    Start-PipelineStep -Title "Qualite et documentation" -Detail "pytest, ruff, README, .gitignore"
    New-QualityTooling -Root $root
    New-RootGitignore -Root $root
    New-ProjectReadme -Root $root -AppName $AppName -HasFrontend $doFrontend -HasDocker $doDocker
    Write-TextFile -Path (Join-Path $root ".env.example") -Content @"
# Copier vers .env (ne jamais committer)

DJANGO_SETTINGS_MODULE=config.settings
DJANGO_ENV=dev
DJANGO_SECRET_KEY=change-me
CORS_ALLOWED_ORIGINS=http://localhost:3000

# PostgreSQL (Docker / qua / prod)
# POSTGRES_DB=app
# POSTGRES_USER=app
# POSTGRES_PASSWORD=
# DJANGO_DB_ENGINE=django.db.backends.postgresql
# DJANGO_DB_NAME=app
# DJANGO_DB_USER=app
# DJANGO_DB_PASSWORD=
# DJANGO_DB_HOST=localhost
# DJANGO_DB_PORT=5432

# Next.js (frontend/.env.local)
# NEXT_PUBLIC_API_URL=http://localhost:8000
"@
    Complete-PipelineStep

    Start-PipelineStep -Title "Verification structure" -Detail "fichiers obligatoires"
    Test-ProjectStructure -Root $root -AppName $AppName -ExpectFrontend $doFrontend -ExpectDocker $doDocker
    Complete-PipelineStep

    Start-PipelineStep -Title "Migrations Django" -Detail "migrate initiale"
    Invoke-CheckedCommand -Exe "uv" -Arguments @(
        "run", "python", "manage.py", "migrate"
    ) -WorkingDirectory $root -Quiet
    Complete-PipelineStep

    Write-PipelineSummary -Root $root -AppName $AppName -HasFrontend $doFrontend -HasDocker $doDocker
}
catch {
    Write-Host ""
    Write-Host "  [ECHEC] $($_.Exception.Message)" -ForegroundColor Red
    if ($createdNewFolder -and (Test-Path -LiteralPath $root)) {
        Write-Host "  Nettoyage du dossier partiel : $root" -ForegroundColor DarkYellow
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    } elseif (-not $createdNewFolder) {
        Write-Host "  Dossier courant conserve (pas de suppression auto)." -ForegroundColor DarkYellow
    }
    throw
}
