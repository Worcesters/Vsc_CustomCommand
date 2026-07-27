#Requires -Version 5.1
<#
.SYNOPSIS
  Genere config Django (settings, Ninja API, Service Layer, Celery) et helpers migrate.

.DESCRIPTION
  - New-DjangoConfigPackage : manage.py, config/, settings base|dev|qua|prod, api Ninja
  - New-AppServiceLayer / New-CoreModels / New-CoreCeleryFiles / New-DjangoNativeAdmin
  - Invoke-DjangoMigrationBootstrap / Invoke-DjangoCreatesuperuser

.NOTES
  Layout : Django a la RACINE du projet genere (pas de backend/).
  Templates Django + django-htmx TOUJOURS configures (UI interne staff),
  meme si UI produit = Astro (frontend/).
  CORS via Get-CorsOrigins (Astro :4321).
  Depend de Common.ps1 (Write-TextFile, Get-CorsOrigins, CLI, env Postgres).
#>

function Invoke-DjangoMigrationBootstrap {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$AppName,
        [switch]$RunMakemigrations
    )

    $pythonExe = Join-Path $Root ".venv\Scripts\python.exe"
    if (-not (Test-Path -LiteralPath $pythonExe)) {
        throw "Python venv introuvable. Lancez d'abord: uv sync"
    }

    $savedEnv = @{}
    $usePostgresEnv = Set-DjangoManageEnvironment -Root $Root -SavedEnv ([ref]$savedEnv)
    # Script dans le projet (pas %TEMP%) : sys.path[0] doit contenir config/
    $bootstrapPath = Join-Path $Root ".migrate_bootstrap.py"

    $pyLines = @(
        "from __future__ import annotations",
        "",
        "import os",
        "import sys",
        "",
        "_ROOT = os.path.dirname(os.path.abspath(__file__))",
        "if _ROOT not in sys.path:",
        "    sys.path.insert(0, _ROOT)",
        "os.chdir(_ROOT)",
        "",
        "import django",
        "from django.core.management import call_command",
        "",
        "os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')",
        "os.environ['DJANGO_ENV'] = 'dev'",
        "django.setup()"
    )
    if ($RunMakemigrations) {
        $pyLines += "call_command('makemigrations', '$AppName', verbosity=1, interactive=False)"
    }
    $pyLines += "call_command('migrate', verbosity=1, interactive=False)"
    $pyContent = ($pyLines -join "`n") + "`n"

    try {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($bootstrapPath, $pyContent, $utf8NoBom)
        Write-Host "     Chargement Django + migrate (sortie ci-dessous)..." -ForegroundColor DarkGray
        Invoke-NativeCli -Exe $pythonExe -Arguments @($bootstrapPath) -WorkingDirectory $Root
    } finally {
        if (Test-Path -LiteralPath $bootstrapPath) {
            Remove-Item -LiteralPath $bootstrapPath -Force -ErrorAction SilentlyContinue
        }
        Restore-DjangoManageEnvironment -UsePostgresEnv $usePostgresEnv -SavedEnv $savedEnv
    }
}

function Invoke-DjangoCreatesuperuser {
    param(
        [Parameter(Mandatory)][string]$Root,
        [switch]$NoInteractive
    )

    $pythonExe = Join-Path $Root ".venv\Scripts\python.exe"
    if (-not (Test-Path -LiteralPath $pythonExe)) {
        throw "Python venv introuvable. Lancez d'abord: uv sync"
    }

    $savedEnv = @{}
    $usePostgresEnv = Set-DjangoManageEnvironment -Root $Root -SavedEnv ([ref]$savedEnv)

    try {
        if ($NoInteractive) {
            $user = $env:DJANGO_SUPERUSER_USERNAME
            $pass = $env:DJANGO_SUPERUSER_PASSWORD
            $email = $env:DJANGO_SUPERUSER_EMAIL
            if ([string]::IsNullOrWhiteSpace($user) -or [string]::IsNullOrWhiteSpace($pass)) {
                Write-Host "     Mode non interactif : definir DJANGO_SUPERUSER_USERNAME, DJANGO_SUPERUSER_PASSWORD (et optionnellement DJANGO_SUPERUSER_EMAIL) puis relancer createsuperuser." -ForegroundColor DarkYellow
                return
            }
            if ([string]::IsNullOrWhiteSpace($email)) {
                $email = "$user@local.test"
            }
            $env:DJANGO_SUPERUSER_USERNAME = $user
            $env:DJANGO_SUPERUSER_PASSWORD = $pass
            $env:DJANGO_SUPERUSER_EMAIL = $email
            Invoke-NativeCli -Exe $pythonExe -Arguments @(
                "manage.py", "createsuperuser", "--noinput"
            ) -WorkingDirectory $Root -Quiet
            Write-Host "     Superuser cree (non interactif) : $user" -ForegroundColor Green
            return
        }

        Write-Host ""
        Write-Host "  Compte superuser requis pour Admin HTMX (/admin/) et/ou /django-admin/" -ForegroundColor Cyan
        if ($usePostgresEnv) {
            Write-Host "  Base : PostgreSQL (fichier .env, meme base que docker compose)." -ForegroundColor DarkGray
        } else {
            Write-Host "  Base : SQLite (db.sqlite3). Activez .env + Docker pour PostgreSQL." -ForegroundColor DarkGray
        }
        Write-Host "  Laissez vide uniquement si vous le creerez plus tard." -ForegroundColor DarkGray
        $skip = -not (Read-YesNoPrompt -Prompt "Creer un superuser maintenant ?" -DefaultYes:$true)
        if ($skip) {
            Write-Host "     createsuperuser ignore - plus tard : uv run python manage.py createsuperuser" -ForegroundColor DarkYellow
            return
        }

        Invoke-NativeCli -Exe $pythonExe -Arguments @(
            "manage.py", "createsuperuser"
        ) -WorkingDirectory $Root
    } finally {
        Restore-DjangoManageEnvironment -UsePostgresEnv $usePostgresEnv -SavedEnv $savedEnv
    }
}

function New-DjangoConfigPackage {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$AppName,
        [bool]$HasCustomAdmin = $true,
        [bool]$HasFrontend = $true,
        [bool]$HasDocker = $false
    )

    $adminPanelAppLine = if ($HasCustomAdmin) { '    "apps.admin_panel",' + "`n" } else { "" }
    $djangoAdminEnvDefault = if ($HasCustomAdmin) { '"false"' } else { '"true"' }
    $corsDefault = Get-CorsOrigins -HasFrontend $HasFrontend
    $templatesDirs = '[BASE_DIR / "templates"]'
    $staticfilesDirsBlock = "STATICFILES_DIRS = [BASE_DIR / `"static`"]`n"
    $celerySettingsBlock = if ($HasDocker) {
        @'

CELERY_BROKER_URL = os.environ.get("CELERY_BROKER_URL", "redis://localhost:6379/0")
CELERY_RESULT_BACKEND = os.environ.get("CELERY_RESULT_BACKEND", CELERY_BROKER_URL)
CELERY_ACCEPT_CONTENT = ["json"]
CELERY_TASK_SERIALIZER = "json"
CELERY_RESULT_SERIALIZER = "json"
CELERY_TIMEZONE = TIME_ZONE
'@
    } else {
        ""
    }
    $urlAdminApiBlock = ""
    $urlConsoleBlock = if ($HasCustomAdmin) {
        @'
    path("accounts/", include("django.contrib.auth.urls")),
    path("admin/", include("apps.admin_panel.urls")),
    path(
        "console/",
        RedirectView.as_view(url="/admin/", permanent=False),
        name="console_legacy_redirect",
    ),
'@
    } else {
        @'
    path("accounts/", include("django.contrib.auth.urls")),
'@
    }
    $urlDjangoAdminBlock = if ($HasCustomAdmin) {
        @'
if getattr(settings, "DJANGO_ADMIN_ENABLED", False):
    urlpatterns.insert(0, path("django-admin/", admin.site.urls))
'@
    } else {
        @'
urlpatterns.insert(0, path("django-admin/", admin.site.urls))
'@
    }

    $configDir = Join-Path $Root "config"
    $settingsDir = Join-Path $configDir "settings"
    New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null

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
    "corsheaders",
    "django_htmx",
    "apps.$AppName",
$adminPanelAppLine]

# Admin Django natif : principal si pas d'admin custom ; fallback dev sinon
DJANGO_ADMIN_ENABLED = os.environ.get("DJANGO_ADMIN_ENABLED", $djangoAdminEnvDefault).lower() in (
    "1",
    "true",
    "yes",
)

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",
    "corsheaders.middleware.CorsMiddleware",
    "django_htmx.middleware.HtmxMiddleware",
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
        "DIRS": $templatesDirs,
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
$staticfilesDirsBlock
STORAGES = {
    "default": {
        "BACKEND": "django.core.files.storage.FileSystemStorage",
    },
    "staticfiles": {
        "BACKEND": "whitenoise.storage.CompressedStaticFilesStorage",
    },
}

LOGIN_URL = "/accounts/login/"
LOGIN_REDIRECT_URL = $(if ($HasCustomAdmin) { '"/admin/"' } else { '"/"' })
LOGOUT_REDIRECT_URL = "/"
$celerySettingsBlock

_cors = os.environ.get("CORS_ALLOWED_ORIGINS", "$corsDefault")
CORS_ALLOWED_ORIGINS = [o.strip() for o in _cors.split(",") if o.strip()]
CORS_ALLOW_CREDENTIALS = True
CSRF_TRUSTED_ORIGINS = CORS_ALLOWED_ORIGINS
"@
    Write-TextFile -Path (Join-Path $settingsDir "base.py") -Content $baseSettings

    $devSettings = @'
from .base import *  # noqa: F403
import os

DEBUG = True
ALLOWED_HOSTS = ["localhost", "127.0.0.1", "web", "host.docker.internal"]


def _load_dotenv() -> None:
    """Charge .env a la racine (PostgreSQL hote = meme base que Docker db)."""
    env_path = BASE_DIR / ".env"
    if not env_path.is_file():
        return
    for raw in env_path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


_load_dotenv()

_use_pg = os.environ.get("DJANGO_USE_POSTGRES", "").lower() in ("1", "true", "yes")
if _use_pg and os.environ.get("DJANGO_DB_HOST"):
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

# Fallback django.contrib.admin en dev local
DJANGO_ADMIN_ENABLED = True
'@
    Write-TextFile -Path (Join-Path $settingsDir "dev.py") -Content $devSettings

    $quaSettings = @'
from .base import *  # noqa: F403
import os

DEBUG = False
ALLOWED_HOSTS = os.environ.get("DJANGO_ALLOWED_HOSTS", "localhost").split(",")

# Meme exigence que prod : pas de SECRET_KEY scaffold / JWT forgeable.
_INSECURE_SECRET_KEYS = frozenset(
    {
        "",
        "dev-only-change-me",
        "dev-local-change-me",
        "dev-docker-only",
        "change-me",
    }
)
SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY", "")
if SECRET_KEY in _INSECURE_SECRET_KEYS:
    raise RuntimeError(
        "DJANGO_SECRET_KEY doit etre defini avec une valeur non triviale (qua)."
    )

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

_INSECURE_SECRET_KEYS = frozenset(
    {
        "",
        "dev-only-change-me",
        "dev-local-change-me",
        "dev-docker-only",
        "change-me",
    }
)
SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY", "")
if SECRET_KEY in _INSECURE_SECRET_KEYS:
    raise RuntimeError(
        "DJANGO_SECRET_KEY doit etre defini avec une valeur non triviale (prod)."
    )

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

DJANGO_ADMIN_ENABLED = False
'@
    Write-TextFile -Path (Join-Path $settingsDir "prod.py") -Content $prodSettings

    Write-TextFile -Path (Join-Path $configDir "api.py") -Content @'
"""API racine Django Ninja."""

from __future__ import annotations

from ninja import NinjaAPI

api = NinjaAPI(
    title="API",
    version="1.0.0",
    urls_namespace="api",
)


@api.get("/health/", tags=["system"])
def health_check(request) -> dict[str, str]:
    """GET /api/health/ - sonde disponibilite."""
    return {"status": "ok"}


def register_api_routers() -> None:
    """Enregistre les routers optionnels (admin, celery, apps metier)."""
    try:
        from apps.admin_panel.api import admin_router, auth_router

        api.add_router("/auth/", auth_router)
        api.add_router("/admin/", admin_router)
    except ImportError:
        pass

    try:
        from apps.core.api import core_router

        api.add_router("/core/", core_router)
    except ImportError:
        pass


register_api_routers()
'@

    $configUrls = @"
from django.conf import settings
from django.contrib import admin
from django.urls import include, path
from django.views.generic import RedirectView

from config.api import api

urlpatterns = [
    path("api/", api.urls),
$urlAdminApiBlock
$urlConsoleBlock
    path("", include("apps.$AppName.urls")),
]

$urlDjangoAdminBlock
"@
    Write-TextFile -Path (Join-Path $configDir "urls.py") -Content $configUrls

    if ($HasDocker) {
        Write-TextFile -Path (Join-Path $configDir "celery.py") -Content @'
"""Application Celery (worker async)."""

from __future__ import annotations

import os

from celery import Celery

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

celery_app = Celery("config")
celery_app.config_from_object("django.conf:settings", namespace="CELERY")
celery_app.autodiscover_tasks()

app = celery_app
'@
        Write-TextFile -Path (Join-Path $configDir "__init__.py") -Content @'
"""Package config."""

from .celery import app as celery_app

__all__ = ("celery_app",)
'@
    } else {
        Write-TextFile -Path (Join-Path $configDir "__init__.py") -Content "# Package config.`n"
    }
}

function New-DjangoNativeAdmin {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$AppName
    )

    Write-TextFile -Path (Join-Path $Root "apps\$AppName\admin.py") -Content @'
"""Enregistrement modeles dans django.contrib.admin."""

from django.contrib import admin
from django.contrib.auth import get_user_model
from django.contrib.auth.admin import UserAdmin as DjangoUserAdmin

User = get_user_model()


class ProjectUserAdmin(DjangoUserAdmin):
    """Administration des utilisateurs Django (remplace auth.UserAdmin par defaut)."""

    list_display = (
        "username",
        "email",
        "is_staff",
        "is_superuser",
        "is_active",
        "date_joined",
    )
    list_filter = ("is_staff", "is_superuser", "is_active")
    search_fields = ("username", "email", "first_name", "last_name")
    ordering = ("username",)


# auth enregistre deja User : desenregistrer avant de personnaliser.
admin.site.unregister(User)
admin.site.register(User, ProjectUserAdmin)
'@
}

function New-AppServiceLayer {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$AppName,
        [bool]$HasCustomAdmin = $true,
        [bool]$HasFrontend = $true
    )

    $homeEyebrow = if ($HasFrontend) { "Django + uv + Astro + HTMX" } else { "Django + uv" }
    $homeLead = if ($HasCustomAdmin -and $HasFrontend) {
        "UI produit Astro ; Admin HTMX DataStudio (/admin/) ; API Django Ninja."
    } elseif ($HasCustomAdmin) {
        "Admin HTMX DataStudio (/admin/) + API /api/admin/ (admin_panel)."
    } else {
        "Application Django avec admin natif. Service Layer et API Django Ninja pour votre metier."
    }
    $homeActions = if ($HasCustomAdmin) {
        @'
        <a class="btn btn--primary" href="/admin/">Ouvrir l'Admin</a>
        <a class="btn btn--secondary" href="/accounts/login/">Connexion</a>
'@
    } else {
        @'
        <a class="btn btn--primary" href="/django-admin/">Administration Django</a>
        <a class="btn btn--secondary" href="/api/health/">API Health</a>
'@
    }
    $card2Title = if ($HasCustomAdmin) { "Console DataStudio" } else { "Admin Django" }
    $card2Text = if ($HasCustomAdmin) {
        "Admin HTMX /admin/ + API /api/admin/ (registry, DDL, query)."
    } else {
        "Gestion des utilisateurs et modeles via /django-admin/."
    }

    $appDir = Join-Path $Root "apps\$AppName"
    New-Item -ItemType Directory -Path $appDir -Force | Out-Null

    Write-TextFile -Path (Join-Path $appDir "services.py") -Content @'
"""Logique d'ecriture (couche service).

Les invariants metier et transactions vivent ici, pas dans les vues ni l'API.
"""

from __future__ import annotations


def example_action() -> str:
    """Exemple de service a remplacer par une regle metier reelle.

    Returns:
        Identifiant symbolique du service d'exemple.
    """
    return "service"
'@

    Write-TextFile -Path (Join-Path $appDir "selectors.py") -Content @'
"""Lecture / agregations (couche selector).

Les querysets optimises (select_related / prefetch) vivent ici.
"""

from __future__ import annotations


def example_selector() -> str:
    """Exemple de selector a remplacer par une lecture metier.

    Returns:
        Identifiant symbolique du selector d'exemple.
    """
    return "selector"
'@

    Write-TextFile -Path (Join-Path $appDir "schemas.py") -Content @'
"""Schemas Django Ninja (validation entree/sortie API)."""

from __future__ import annotations

from ninja import Schema


class HealthOut(Schema):
    """Schema de sortie minimal (exemple)."""

    status: str
'@

    Write-TextFile -Path (Join-Path $appDir "forms.py") -Content @'
"""Formulaires Django (rendu HTML templates HTMX uniquement)."""

from __future__ import annotations

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

    if ($HasFrontend) {
        # UI produit servie par Astro : la racine Django renvoie une info API (templates HTMX reserves au staff).
        Write-TextFile -Path (Join-Path $appDir "views.py") -Content @"
from __future__ import annotations

from django.http import HttpRequest, JsonResponse
from django.views import View


class HomeView(View):
    '''Racine de l'API Django (UI produit servie par Astro sur le port 4321).

    MRO:
    1. View.get -> JsonResponse d'information API
    '''

    def get(self, request: HttpRequest) -> JsonResponse:
        return JsonResponse(
            {
                "service": "$AppName",
                "frontend": "http://localhost:4321",
                "health": "/api/health/",
            }
        )
"@
    } else {
        New-Item -ItemType Directory -Path (Join-Path $appDir "templates\$AppName") -Force | Out-Null
        Write-TextFile -Path (Join-Path $appDir "views.py") -Content @"
from __future__ import annotations

from django.views.generic import TemplateView


class HomeView(TemplateView):
    '''Page d'accueil (template Django).

    MRO:
    1. TemplateView.get -> rendu template $AppName/home.html
    '''

    template_name = "$AppName/home.html"
"@

        $homeHtml = @"
{% extends "base.html" %}
{% block title %}Accueil{% endblock %}
{% block content %}
  <main class="page-home">
    <header class="page-home__hero">
      <p class="page-home__eyebrow">$homeEyebrow</p>
      <h1 class="page-home__title">Bienvenue sur votre application</h1>
      <p class="page-home__lead">
        $homeLead
      </p>
      <div class="page-home__actions">
$homeActions
      </div>
    </header>
    <section class="page-home__grid">
      <article class="page-home__card">
        <h2 class="page-home__card-title">API Django</h2>
        <p class="page-home__card-text">Service Layer, Django Ninja et migrations ORM.</p>
      </article>
      <article class="page-home__card">
        <h2 class="page-home__card-title">$card2Title</h2>
        <p class="page-home__card-text">$card2Text</p>
      </article>
    </section>
  </main>
{% endblock %}
"@
        Write-TextFile -Path (Join-Path $appDir "templates\$AppName\home.html") -Content $homeHtml
    }
}

function New-CoreModels {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$AppName,
        [bool]$HasCustomAdmin = $true
    )
    $adminHint = if ($HasCustomAdmin) {
        "L'admin DataStudio expose par defaut ``auth.User`` (voir ``apps.admin_panel.registry``)."
    } else {
        "Utilisateurs geres via ``django.contrib.admin`` (``/django-admin/``)."
    }
    $modelsPath = Join-Path $Root "apps\$AppName\models.py"
    Write-TextFile -Path $modelsPath -Content @"
from __future__ import annotations

"""Modeles metier de l'app $AppName.

$adminHint
Ajoutez ici vos modeles metier supplementaires.
"""
"@
}

function New-CoreCeleryFiles {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$AppName
    )

    $appDir = Join-Path $Root "apps\$AppName"
    Write-TextFile -Path (Join-Path $appDir "tasks.py") -Content @'
"""Taches Celery (async) pour l''app metier."""

from __future__ import annotations

from celery import shared_task


@shared_task(name="core.ping")
def ping() -> str:
    """Tache de test worker Celery."""
    return "pong"
'@

    Write-TextFile -Path (Join-Path $appDir "api.py") -Content @'
"""Routes API metier complementaires (Django Ninja)."""

from __future__ import annotations

from ninja import Router, Schema

from .tasks import ping

core_router = Router(tags=["core"])


class AsyncPingOut(Schema):
    task_id: str
    status: str


@core_router.post("/async-ping/", response=AsyncPingOut)
def async_ping(request):
    """POST /api/core/async-ping/ - declenche une tache Celery de test."""
    async_result = ping.delay()
    return AsyncPingOut(task_id=async_result.id, status="queued")
'@
}
