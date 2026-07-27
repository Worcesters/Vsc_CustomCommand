#Requires -Version 5.1
<#
.SYNOPSIS
  Outils qualite (pytest, ruff, mypy), README, .gitignore, .env.example helpers.

.NOTES
  Stack documentee : Django Ninja + Astro + HTMX (Next.js interdit).
  PUBLIC_API_URL ; port Astro 4321.
#>

function New-QualityTooling {
    <#
    .SYNOPSIS
      pytest.ini, conftest, tests admin_panel ou health.
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [bool]$HasCustomAdmin = $true
    )

    $testsDir = Join-Path $Root "tests"
    New-Item -ItemType Directory -Path $testsDir -Force | Out-Null
    Write-TextFile -Path (Join-Path $testsDir "__init__.py") -Content "`n"
    Write-TextFile -Path (Join-Path $testsDir "conftest.py") -Content @'
"""Fixtures Pytest Django."""
import pytest


@pytest.fixture
def api_client():
    """Client Django pour tests API."""
    from django.test import Client

    return Client()


@pytest.fixture
def superuser(db):
    """Superuser Django pour tests admin."""
    from django.contrib.auth import get_user_model

    User = get_user_model()
    return User.objects.create_superuser(
        username="admin",
        email="admin@test.local",
        password="admin-secret",
    )


@pytest.fixture
def api_client_superuser(api_client, superuser):
    """Client authentifie JWT superuser."""
    from apps.admin_panel.auth import create_token_pair

    tokens = create_token_pair(superuser)
    api_client.defaults["HTTP_AUTHORIZATION"] = f"Bearer {tokens['access']}"
    return api_client
'@

    Write-TextFile -Path (Join-Path $Root "pytest.ini") -Content @'
[pytest]
DJANGO_SETTINGS_MODULE = config.settings
python_files = tests.py test_*.py *_tests.py
addopts = -ra
'@

    Write-TextFile -Path (Join-Path $Root "ruff.toml") -Content @'
line-length = 100
target-version = "py312"

[lint]
select = ["E", "F", "I", "UP", "B"]
'@

    Write-TextFile -Path (Join-Path $Root "mypy.ini") -Content @'
[mypy]
python_version = 3.12
strict = True
plugins = mypy_django_plugin.main

[mypy.plugins.django-stubs]
django_settings_module = config.settings
'@

    if ($HasCustomAdmin) {
        Write-TextFile -Path (Join-Path $testsDir "test_admin_api.py") -Content @'
"""Tests API admin panel (auth superuser)."""

import json

import pytest
from django.contrib.auth import get_user_model


@pytest.mark.django_db
def test_registry_anonymous_forbidden(api_client) -> None:
    response = api_client.get("/api/admin/registry/")
    assert response.status_code == 401


@pytest.mark.django_db
def test_registry_non_superuser_forbidden(api_client, db) -> None:
    User = get_user_model()
    user = User.objects.create_user(username="user", password="pass")
    # Forge un access JWT hors create_token_pair (reserve aux superusers).
    from datetime import UTC, datetime, timedelta

    import jwt
    from django.conf import settings

    token = jwt.encode(
        {
            "user_id": user.pk,
            "username": user.username,
            "type": "access",
            "exp": datetime.now(tz=UTC) + timedelta(hours=1),
            "iat": datetime.now(tz=UTC),
        },
        settings.SECRET_KEY,
        algorithm="HS256",
    )
    response = api_client.get(
        "/api/admin/registry/",
        HTTP_AUTHORIZATION=f"Bearer {token}",
    )
    assert response.status_code == 401


@pytest.mark.django_db
def test_registry_superuser_ok(api_client_superuser) -> None:
    response = api_client_superuser.get("/api/admin/registry/")
    assert response.status_code == 200
    assert "results" in response.json()


@pytest.mark.django_db
def test_schema_global_superuser_ok(api_client_superuser) -> None:
    response = api_client_superuser.get("/api/admin/schema/")
    assert response.status_code == 200
    assert "nodes" in response.json()


@pytest.mark.django_db
def test_login_rejects_non_superuser(api_client, db) -> None:
    User = get_user_model()
    User.objects.create_user(username="user", password="pass")
    response = api_client.post(
        "/api/auth/login/",
        data=json.dumps({"username": "user", "password": "pass"}),
        content_type="application/json",
    )
    assert response.status_code == 403
    assert response.json()["code"] == "not_superuser"


def test_login_rejects_wrong_password(api_client, superuser) -> None:
    response = api_client.post(
        "/api/auth/login/",
        data=json.dumps({"username": "admin", "password": "wrong-password"}),
        content_type="application/json",
    )
    assert response.status_code == 401
    assert response.json()["code"] == "invalid_credentials"


@pytest.mark.django_db
def test_login_accepts_superuser(api_client, superuser) -> None:
    response = api_client.post(
        "/api/auth/login/",
        data=json.dumps({"username": "admin", "password": "admin-secret"}),
        content_type="application/json",
    )
    assert response.status_code == 200
    data = response.json()
    assert "access" in data
    assert data["user"]["is_superuser"] is True


@pytest.mark.django_db
def test_db_schema_requires_auth(api_client) -> None:
    response = api_client.get("/api/admin/db/schema/")
    assert response.status_code == 401


@pytest.mark.django_db
def test_db_create_table_rejects_blacklist(api_client_superuser) -> None:
    response = api_client_superuser.post(
        "/api/admin/db/tables/",
        data=json.dumps(
            {
                "name": "auth_user",
                "columns": [
                    {
                        "name": "id",
                        "type": "integer",
                        "nullable": False,
                        "primary_key": True,
                    }
                ],
            }
        ),
        content_type="application/json",
    )
    assert response.status_code == 400
    assert "blacklist" in response.json()["detail"].lower()


@pytest.mark.django_db
def test_db_create_table_rejects_invalid_identifier(api_client_superuser) -> None:
    response = api_client_superuser.post(
        "/api/admin/db/tables/",
        data=json.dumps(
            {
                "name": "1bad",
                "columns": [
                    {
                        "name": "id",
                        "type": "integer",
                        "nullable": False,
                        "primary_key": True,
                    }
                ],
            }
        ),
        content_type="application/json",
    )
    assert response.status_code == 400


@pytest.mark.django_db
def test_db_drop_table_requires_confirm_name(api_client_superuser) -> None:
    response = api_client_superuser.delete("/api/admin/db/tables/demo_tbl/")
    # Ninja : query param requis -> 422 ; ou 400 si confirm invalide vide.
    assert response.status_code in {400, 422}


@pytest.mark.django_db
def test_db_drop_table_reject_confirm_mismatch(api_client_superuser) -> None:
    response = api_client_superuser.delete(
        "/api/admin/db/tables/demo_tbl/?confirm_name=wrong"
    )
    assert response.status_code == 400
    assert "confirm" in response.json()["detail"].lower() or "invalide" in response.json()[
        "detail"
    ].lower()
'@

        Write-TextFile -Path (Join-Path $testsDir "test_console_security.py") -Content @'
"""Tests securite Admin HTMX (/admin/) — superuser, CSRF, path table."""

from __future__ import annotations

import pytest
from django.contrib.auth import get_user_model
from django.test import Client


@pytest.mark.django_db
def test_admin_anonymous_redirects_to_login(api_client: Client) -> None:
    response = api_client.get("/admin/")
    assert response.status_code in {302, 301}
    assert "/accounts/login/" in response.url


@pytest.mark.django_db
def test_console_legacy_redirects_to_admin(api_client: Client) -> None:
    response = api_client.get("/console/")
    assert response.status_code in {302, 301}
    assert response.url == "/admin/"


@pytest.mark.django_db
def test_admin_staff_non_superuser_forbidden(api_client: Client, db) -> None:
    User = get_user_model()
    user = User.objects.create_user(
        username="staffer",
        password="pass",
        is_staff=True,
        is_superuser=False,
    )
    api_client.force_login(user)
    response = api_client.get("/admin/")
    assert response.status_code == 403


@pytest.mark.django_db
def test_admin_superuser_ok(api_client: Client, superuser) -> None:
    api_client.force_login(superuser)
    response = api_client.get("/admin/")
    assert response.status_code == 200


@pytest.mark.django_db
def test_admin_table_path_rejects_injection(api_client: Client, superuser) -> None:
    api_client.force_login(superuser)
    response = api_client.get("/admin/tables/1bad;drop/")
    assert response.status_code == 404


@pytest.mark.django_db
def test_admin_drop_table_csrf_required(superuser) -> None:
    client = Client(enforce_csrf_checks=True)
    client.force_login(superuser)
    response = client.post(
        "/admin/ddl/drop-table/",
        data={"name": "demo", "confirm_name": "demo"},
    )
    assert response.status_code == 403


@pytest.mark.django_db
def test_admin_drop_table_confirm_mismatch(api_client: Client, superuser) -> None:
    api_client.force_login(superuser)
    response = api_client.post(
        "/admin/ddl/drop-table/",
        data={"name": "demo_tbl", "confirm_name": "other"},
        HTTP_HX_REQUEST="true",
    )
    assert response.status_code == 200
    body = response.content.lower()
    assert b"confirmation invalide" in body or b"invalide" in body
'@
    } else {
        # conftest sans fixture JWT admin_panel
        Write-TextFile -Path (Join-Path $testsDir "conftest.py") -Content @'
"""Fixtures Pytest Django (sans admin_panel)."""
import pytest


@pytest.fixture
def api_client():
    """Client Django pour tests API."""
    from django.test import Client

    return Client()


@pytest.fixture
def superuser(db):
    """Superuser Django pour tests admin."""
    from django.contrib.auth import get_user_model

    User = get_user_model()
    return User.objects.create_superuser(
        username="admin",
        email="admin@test.local",
        password="admin-secret",
    )
'@
        Write-TextFile -Path (Join-Path $testsDir "test_health.py") -Content @'
"""Tests sante API sans admin custom."""

from django.test import Client


def test_health_endpoint_ok() -> None:
    response = Client().get("/api/health/")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"
'@
    }
}

function New-RootGitignore {
    <#
    .SYNOPSIS
      .gitignore racine (venv, node_modules, .env, staticfiles, Astro dist).
    #>
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
.migrate_bootstrap.py
*.egg-info/
.pytest_cache/
.mypy_cache/
.ruff_cache/
.idea/
.vscode/
frontend/node_modules/
frontend/dist/
frontend/.astro/
frontend/.env
frontend/.env.local
'@
}

function New-ProjectReadme {
    <#
    .SYNOPSIS
      README.md du projet genere (stack Ninja + Astro + HTMX).
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$AppName,
        [bool]$HasCustomAdmin = $true,
        [bool]$HasFrontend = $true,
        [bool]$HasDocker = $false
    )

    $scaffoldDir = $PSScriptRoot
    $fullstackTemplate = Join-Path $scaffoldDir "readme-templates\README.fullstack.md"

    if ($HasFrontend -and (Test-Path -LiteralPath $fullstackTemplate)) {
        $projectTitle = "Monorepo Django Ninja + Astro + HTMX + uv"
        if ($HasDocker) { $projectTitle += " + Docker" }
        $readme = Get-Content -LiteralPath $fullstackTemplate -Raw -Encoding UTF8
        $readme = $readme.Replace("__PROJECT_TITLE__", $projectTitle)
        $readme = $readme.Replace("__APP_NAME__", $AppName)
        Write-TextFile -Path (Join-Path $Root "README.md") -Content $readme
        return
    }

    $fe = if ($HasFrontend) { @"

## Frontend (Astro)

L'init **ne demarre pas** Astro : le port 4321 reste ferme tant que ``pnpm dev`` n'est pas lance.

``````powershell
# Option A : deux fenetres automatiques (recommande Windows)
.\scripts\dev-local.ps1

# Option B : manuel (2 terminaux)
cd frontend
pnpm install   # deja fait a l'init si Node/pnpm disponible
pnpm dev
``````

Puis ouvrir http://127.0.0.1:4321 (ou http://localhost:4321).

Variables publiques : ``PUBLIC_API_URL`` (health API) et ``PUBLIC_DJANGO_URL`` (liens Django).
Admin DataStudio : ``PUBLIC_DJANGO_URL`` + ``/admin/`` (HTMX, pas Astro).
Jamais de secrets dans ``PUBLIC_*``.
"@ } else { "" }

    $quickStart = if ($HasFrontend) {
        @"

``````powershell
cd <racine_projet>
uv sync
uv run python manage.py migrate

# Demarrer backend + frontend Astro (obligatoire pour le port 4321) :
.\scripts\dev-local.ps1
``````
"@
    } else {
        @"

``````powershell
cd <racine_projet>
uv sync
uv run python manage.py migrate
uv run python manage.py runserver
``````
"@
    }

    $projectKind = if ($HasFrontend) {
        "Monorepo Django Ninja + Astro + HTMX + uv"
    } else {
        "Projet Django Ninja + HTMX + uv (sans Astro)"
    }
    $dk = if ($HasDocker) {
        if ($HasFrontend) {
            @"

## Docker (dev - db + redis + web + frontend + worker + beat)
``````bash
docker compose up --build
``````

- API : http://localhost:8000
- Astro : http://localhost:4321
- Back-office HTMX : http://localhost:8000/backoffice/

Production : ``docker compose -f docker-compose.prod.yml up --build``
"@
        } else {
            @"

## Docker (dev - db + redis + web + worker + beat)
``````bash
docker compose up --build
``````

- API : http://localhost:8000
- Back-office HTMX : http://localhost:8000/backoffice/
- Admin Django (dev) : http://localhost:8000/django-admin/

Production : ``docker compose -f docker-compose.prod.yml up --build``
"@
        }
    } else { "" }

    $urlsBlock = if ($HasFrontend) {
        @"

- Backend : http://localhost:8000
- Frontend Astro : http://localhost:4321
- Admin DataStudio : http://localhost:8000/admin/
- Connexion staff : http://localhost:8000/accounts/login/
- Back-office HTMX : http://localhost:8000/backoffice/
"@
    } elseif ($HasCustomAdmin) {
        @"

- API : http://localhost:8000
- Back-office HTMX : http://localhost:8000/backoffice/
- Admin Django (fallback dev) : http://localhost:8000/django-admin/
- API admin : http://localhost:8000/api/admin/
"@
    } else {
        @"

- API : http://localhost:8000
- Back-office HTMX : http://localhost:8000/backoffice/
- Admin Django : http://localhost:8000/django-admin/
"@
    }

    $dockerUpHint = if ($HasFrontend) {
        "docker compose up          # web + frontend Astro + worker/beat"
    } else {
        "docker compose up          # web + worker/beat"
    }

    $backendAdminLine = if ($HasCustomAdmin) {
        "Admin custom : ``apps.admin_panel`` (registry, schema, CRUD, query SELECT, DDL Postgres ``/api/admin/db/``)"
    } else {
        'Administration : ``django.contrib.admin`` sur ``/django-admin/`` (pas d''admin_panel)'
    }

    $readme = @"
# $projectKind$(if ($HasDocker) { " + Docker" })

## Demarrage rapide
$quickStart

$dk

## Base de donnees (PostgreSQL)

Avec Docker, le script genere un fichier ``.env`` : Django utilise **PostgreSQL** sur le port hote mappe (voir ``.env`` / compose).

``````bash
docker compose up -d db
uv run python manage.py migrate
uv run python manage.py createsuperuser
$dockerUpHint
``````

Sans ``DJANGO_USE_POSTGRES=1`` : fallback SQLite (``db.sqlite3``).

$urlsBlock

## Compte superuser

Cree a l'init (etape Superuser) ou via ``createsuperuser`` - compte **superuser** requis$(if ($HasFrontend -and $HasCustomAdmin) { " pour ``/admin/`` et ``/accounts/login/``" } elseif ($HasCustomAdmin) { " pour ``/admin/``" } else { " pour ``/django-admin/``" }).

## Backend

App metier : ``apps.$AppName``
$backendAdminLine

UI interne staff : templates Django + **HTMX** (``/backoffice/``).

**Structure BDD** : ``models.py`` + migrations uniquement.

$fe

## Cursor

Voir ``.cursor/AGENTS.md`` et ``.cursor/skills/STACK.md``.
"@
    Write-TextFile -Path (Join-Path $Root "README.md") -Content $readme
}

function Test-ProjectStructure {
    <#
    .SYNOPSIS
      Verifie la presence des fichiers obligatoires apres scaffold (Astro, pas Next).
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$AppName,
        [bool]$ExpectCustomAdmin = $true,
        [bool]$ExpectFrontend = $true,
        [bool]$ExpectDocker = $false
    )
    $required = @(
        "manage.py",
        "config\settings\base.py",
        "config\settings\dev.py",
        "config\urls.py",
        "config\api.py",
        "apps\$AppName\models.py",
        "apps\$AppName\services.py",
        "apps\$AppName\selectors.py",
        "apps\$AppName\schemas.py",
        "templates\base.html",
        "static\scss\main.scss",
        ".cursor\AGENTS.md",
        ".cursor\rules\00-project-stack.mdc"
    )
    if ($ExpectCustomAdmin) {
        $required += @(
            "apps\admin_panel\registry.py",
            "apps\admin_panel\api.py",
            "apps\admin_panel\schemas.py",
            "apps\admin_panel\urls.py",
            "apps\admin_panel\views.py",
            "templates\console\shell.html",
            "templates\registration\login.html"
        )
    } else {
        $required += "apps\$AppName\admin.py"
    }
    if ($ExpectFrontend) {
        $lockFile = Join-Path $Root "frontend\pnpm-lock.yaml"
        if ($ExpectDocker -and -not (Test-Path -LiteralPath $lockFile)) {
            Write-Host "     Avertissement : frontend/pnpm-lock.yaml absent (Docker : cd frontend && pnpm install)." -ForegroundColor DarkYellow
        }
        $required += @(
            "frontend\package.json",
            "frontend\astro.config.mjs",
            "frontend\src\pages\index.astro"
        )
        if ($ExpectCustomAdmin) {
            $required += @(
                "frontend\src\pages\admin.astro",
                "frontend\src\pages\login.astro",
                "frontend\src\lib\api\client.ts"
            )
        }
    }
    if ($ExpectDocker) {
        $required += @(
            "Dockerfile",
            "docker-compose.yml",
            "docker-compose.prod.yml",
            "scripts\docker-web-dev.sh",
            "scripts\docker-web-prod.sh",
            "config\celery.py",
            "apps\$AppName\tasks.py",
            "apps\$AppName\api.py"
        )
        if ($ExpectFrontend) {
            $required += @(
                "frontend\Dockerfile",
                "frontend\scripts\docker-entrypoint-dev.sh"
            )
        }
    }
    foreach ($rel in $required) {
        $full = Join-Path $Root $rel
        if (-not (Test-Path -LiteralPath $full)) {
            throw "Structure incomplete, fichier manquant : $rel"
        }
    }
}
