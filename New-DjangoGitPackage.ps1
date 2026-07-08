#Requires -Version 5.1
<#
.SYNOPSIS
  Cree un package Django installable via uv depuis une URL Git.

.DESCRIPTION
  Genere un depot autonome (pyproject.toml + uv.lock + .venv + app Django Service Layer) pret pour :
    uv add "django-monapp @ git+https://github.com/user/django-monapp.git"
    uv add "django-monapp @ git+https://github.com/user/monorepo.git#subdirectory=django-monapp"

  Ne necessite pas de projet Django existant. Apres installation dans un projet,
  ajoutez l'app dans INSTALLED_APPS et incluez les URLs si besoin.

.PARAMETER PackageName
  Nom Python du package (snake_case). Si absent, demande interactivement.

.PARAMETER OutputDir
  Dossier de sortie (defaut : ./django-<PackageName>).

.PARAMETER NoInteractive
  Pas de question ; PackageName obligatoire.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\New-DjangoGitPackage.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\New-DjangoGitPackage.ps1 -PackageName billing -OutputDir E:\packages\django-billing
#>

[CmdletBinding()]
param(
    [string]$PackageName = "",
    [string]$OutputDir = "",
    [switch]$NoInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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

function Get-PascalCaseFromSnake {
    param([Parameter(Mandatory)][string]$Name)
    return ($Name -split '_' | ForEach-Object {
            if ($_.Length -eq 0) { return "" }
            $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1).ToLowerInvariant()
        }) -join ''
}

function Invoke-UvNative {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$WorkingDirectory
    )
    $uv = Get-Command uv -ErrorAction SilentlyContinue
    if (-not $uv) {
        throw "uv introuvable dans le PATH. Installez uv puis relancez."
    }
    Push-Location -LiteralPath $WorkingDirectory
    try {
        & $uv.Source @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "uv $($Arguments -join ' ') a echoue (code $LASTEXITCODE)"
        }
    } finally {
        Pop-Location
    }
}

function Initialize-GitPackageUvEnvironment {
    param([Parameter(Mandatory)][string]$Root)

    Write-Host "  Initialisation uv (sync + dev)..." -ForegroundColor Yellow
    Invoke-UvNative -Arguments @("sync", "--extra", "dev") -WorkingDirectory $Root
    Write-Host "  [OK] .venv + uv.lock" -ForegroundColor Green
}

function New-GitPackageServiceLayer {
    param(
        [Parameter(Mandatory)][string]$AppDir,
        [Parameter(Mandatory)][string]$PackageName
    )

    $classPrefix = Get-PascalCaseFromSnake -Name $PackageName

    Write-TextFile -Path (Join-Path $AppDir "services.py") -Content @'
"""Logique d'ecriture (couche service)."""


def example_action() -> str:
    """Exemple de service a remplacer."""
    return "service"
'@

    Write-TextFile -Path (Join-Path $AppDir "selectors.py") -Content @'
"""Lecture / agregations (couche selector)."""


def example_selector() -> str:
    """Exemple de selector a remplacer."""
    return "selector"
'@

    Write-TextFile -Path (Join-Path $AppDir "schemas.py") -Content @'
"""Schemas Django Ninja (validation entree/sortie API)."""

from ninja import ModelSchema


class HealthOut(Schema):
    app: str
    status: str
'@

    Write-TextFile -Path (Join-Path $AppDir "forms.py") -Content @'
"""Formulaires Django (rendu HTML uniquement)."""

from django import forms
'@

    Write-TextFile -Path (Join-Path $AppDir "api.py") -Content @"
from __future__ import annotations

from ninja import Router

from .schemas import HealthOut

router = Router(tags=["$PackageName"])


@router.get("/health/", response=HealthOut)
def health(request) -> HealthOut:
    '''GET /api/$PackageName/health/ - sante du package.'''
    return HealthOut(app="$PackageName", status="ok")
"@

    Write-TextFile -Path (Join-Path $AppDir "admin.py") -Content @'
"""Enregistrement modeles dans django.contrib.admin."""

from django.contrib import admin

# from .models import MyModel
# admin.site.register(MyModel)
'@

    Write-TextFile -Path (Join-Path $AppDir "models.py") -Content @"
from __future__ import annotations

"""Modeles metier de l'app $PackageName."""
"@

    Write-TextFile -Path (Join-Path $AppDir "tests.py") -Content @"
"""Tests Pytest pour $PackageName."""

from ninja.testing import TestClient

from $PackageName.api import router


def test_health_ok() -> None:
    client = TestClient(router)
    response = client.get("/health/")
    assert response.status_code == 200
    data = response.json()
    assert data["app"] == "$PackageName"
    assert data["status"] == "ok"
"@
}

function New-GitPackagePyproject {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$PackageName,
        [Parameter(Mandatory)][string]$DistributionName
    )

    $content = @"
[project]
name = "$DistributionName"
version = "0.1.0"
description = "Application Django $PackageName (Service Layer, Django Ninja)"
readme = "README.md"
requires-python = ">=3.10"
dependencies = [
    "django>=5.0",
    "django-ninja>=1.0",
]

[project.optional-dependencies]
dev = [
    "pytest>=8.0",
    "pytest-django>=4.8",
    "ruff>=0.8",
    "mypy>=1.0",
]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.hatch.build.targets.wheel]
packages = ["$PackageName"]

[tool.pytest.ini_options]
DJANGO_SETTINGS_MODULE = "tests.settings"
python_files = ["test_*.py", "tests.py"]

[tool.ruff]
line-length = 100
target-version = "py312"
"@
    Write-TextFile -Path (Join-Path $Root "pyproject.toml") -Content $content
}

function New-GitPackagePythonVersion {
    param([Parameter(Mandatory)][string]$Root)

    Write-TextFile -Path (Join-Path $Root ".python-version") -Content "3.12`n"
}

function New-GitPackageReadme {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$PackageName,
        [Parameter(Mandatory)][string]$DistributionName,
        [Parameter(Mandatory)][string]$ConfigClass
    )

    $content = @"
# $DistributionName

Package Django installable via **uv** depuis Git.

## Installation dans un projet existant

Apres avoir pousse ce depot sur GitHub/GitLab :

**Depot dedie** (racine du repo = ce package) :

``````powershell
cd chemin/vers/votre/projet-django
uv add "$DistributionName @ git+https://github.com/VOTRE_ORG/$DistributionName.git"
``````

**Monorepo** (ce package vit dans un sous-dossier du depot Git) :

``````powershell
uv add "$DistributionName @ git+https://github.com/VOTRE_ORG/VOTRE_MONOREPO.git#subdirectory=$DistributionName"
``````

Branche ou tag specifique :

``````powershell
uv add "$DistributionName @ git+https://github.com/VOTRE_ORG/$DistributionName.git@main"
uv add "$DistributionName @ git+https://github.com/VOTRE_ORG/$DistributionName.git@v0.1.0"
uv add "$DistributionName @ git+https://github.com/VOTRE_ORG/VOTRE_MONOREPO.git@main#subdirectory=$DistributionName"
``````

## Developpement du package (uv local)

Depuis la racine de ce depot :

``````powershell
uv sync --extra dev
uv run ruff check $PackageName/
uv run pytest
``````

## Configuration Django

Dans ``config/settings/base.py`` :

``````python
INSTALLED_APPS = [
    # ...
    "$ConfigClass",
]
``````

Dans ``config/urls.py`` (via ``config/api.py`` du projet hote) :

``````python
from $PackageName.api import router as ${PackageName}_router

api.add_router("/$PackageName/", ${PackageName}_router)
``````

Puis :

``````powershell
uv run python manage.py makemigrations $PackageName
uv run python manage.py migrate
``````

## Developpement local (editable)

Sans Git, depuis ce dossier :

``````powershell
uv add --editable ./chemin/vers/$DistributionName
``````

## Structure

- ``$PackageName/`` — app Django (models, services, selectors, schemas, api Ninja)
- ``pyproject.toml`` + ``uv.lock`` — metadata pip/uv (hatchling), deps verrouillees
- ``.venv/`` — environnement local (gitignore, recree via ``uv sync``)
"@
    Write-TextFile -Path (Join-Path $Root "README.md") -Content $content
}

function New-GitPackageGitignore {
    param([Parameter(Mandatory)][string]$Root)

    Write-TextFile -Path (Join-Path $Root ".gitignore") -Content @'
.venv/
__pycache__/
*.py[cod]
*.egg-info/
dist/
build/
.ruff_cache/
.mypy_cache/
.pytest_cache/
*.sqlite3
.env
'@
}

try {
    Write-Host ""
    Write-Host "  Package Django installable via uv + Git" -ForegroundColor Cyan
    Write-Host ""

    $pkg = $PackageName.Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($pkg)) {
        if ($NoInteractive.IsPresent) {
            throw "PackageName obligatoire avec -NoInteractive."
        }
        do {
            $pkg = (Read-Host "Nom du package Python (snake_case)").Trim().ToLowerInvariant()
            if (-not (Test-PythonIdentifier $pkg)) {
                Write-Host "  Identifiant invalide (snake_case, pas de mot reserve)." -ForegroundColor DarkYellow
                $pkg = ""
            }
        } while ([string]::IsNullOrWhiteSpace($pkg))
    }

    if (-not (Test-PythonIdentifier $pkg)) {
        throw "PackageName invalide : '$pkg'"
    }

    $distName = "django-$pkg"
    $configClass = "$pkg.apps.$(Get-PascalCaseFromSnake -Name $pkg)Config"

    $out = $OutputDir.Trim()
    if ([string]::IsNullOrWhiteSpace($out)) {
        if ($NoInteractive.IsPresent) {
            $out = Join-Path (Get-Location).Path $distName
        } else {
            $defaultOut = Join-Path (Get-Location).Path $distName
            $answer = (Read-Host "Dossier de sortie [$defaultOut]").Trim()
            $out = if ([string]::IsNullOrWhiteSpace($answer)) { $defaultOut } else { $answer }
        }
    }
    $out = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($out)

    if (Test-Path -LiteralPath $out) {
        $children = @(Get-ChildItem -LiteralPath $out -Force -ErrorAction SilentlyContinue)
        if ($children.Count -gt 0) {
            throw "Le dossier existe deja et n'est pas vide : $out"
        }
    } else {
        New-Item -ItemType Directory -Path $out -Force | Out-Null
    }

    $appDir = Join-Path $out $pkg
    New-Item -ItemType Directory -Path $appDir -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $appDir "migrations") -Force | Out-Null

    $pascal = Get-PascalCaseFromSnake -Name $pkg

    Write-TextFile -Path (Join-Path $appDir "__init__.py") -Content @"
"""Application Django $pkg (package installable)."""
"@

    Write-TextFile -Path (Join-Path $appDir "apps.py") -Content @"
from django.apps import AppConfig


class ${pascal}Config(AppConfig):
    """Configuration Django pour le package $pkg."""

    default_auto_field = "django.db.models.BigAutoField"
    name = "$pkg"
    verbose_name = "$pascal"
"@

    Write-TextFile -Path (Join-Path $appDir "migrations\__init__.py") -Content "`n"

    New-GitPackageServiceLayer -AppDir $appDir -PackageName $pkg
    New-GitPackagePyproject -Root $out -PackageName $pkg -DistributionName $distName
    New-GitPackagePythonVersion -Root $out
    New-GitPackageReadme -Root $out -PackageName $pkg -DistributionName $distName -ConfigClass $configClass
    New-GitPackageGitignore -Root $out
    Initialize-GitPackageUvEnvironment -Root $out

    Write-Host "  [OK] Package cree : $out" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Prochaines etapes :" -ForegroundColor White
    Write-Host "    1. cd $out && git init && git add . && git commit -m 'feat: package initial'"
    Write-Host "    2. Poussez sur GitHub/GitLab"
    Write-Host "    3. Dans votre projet Django :"
    Write-Host "       uv add `"$distName @ git+https://github.com/VOTRE_ORG/$distName.git`""
    Write-Host "       uv add `"$distName @ git+https://github.com/VOTRE_ORG/VOTRE_MONOREPO.git#subdirectory=$distName`""
    Write-Host "    4. INSTALLED_APPS += `"$configClass`""
    Write-Host "    5. api.add_router(`"/$pkg/`", ${pkg}_router) dans config/api.py"
    Write-Host ""
}
catch {
    Write-Host ""
    Write-Host "  [ECHEC] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
