#Requires -Version 5.1
<#
.SYNOPSIS
  Genere .cursor/AGENTS.md, rules MDC et cartographie app pour le projet cible.

.NOTES
  Stack documentee : Django Ninja + Astro + HTMX (Next.js interdit).
  Frontiere : Astro = UI produit ; HTMX = UI interne staff.
#>

function New-CursorProjectRules {
    <#
    .SYNOPSIS
      Ecrit les regles Cursor du projet genere (Ninja + Astro + HTMX).

    .PARAMETER Root
      Racine du projet.

    .PARAMETER AppName
      App metier.

    .PARAMETER HasCustomAdmin
      Documente admin_panel si vrai.

    .PARAMETER HasFrontend
      Documente frontend/ Astro si vrai.
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$AppName,
        [bool]$HasCustomAdmin = $true,
        [bool]$HasFrontend = $true
    )

    $cursorDir = Join-Path $Root ".cursor"
    $rulesDir = Join-Path $cursorDir "rules"
    $skillsDir = Join-Path $cursorDir "skills"
    New-Item -ItemType Directory -Path $rulesDir -Force | Out-Null
    New-Item -ItemType Directory -Path $skillsDir -Force | Out-Null

    $htmxRows = "| ``templates/`` | UI interne HTMX (back-office, partials) |`n| ``static/scss/`` | SCSS 7-1 (HTMX + tokens) |`n"
    $feRow = if ($HasFrontend) {
        "| ``frontend/`` | Astro UI produit (port 4321, zero React) |`n"
    } else {
        ""
    }
    $adminPanelRow = if ($HasCustomAdmin) {
        "| ``apps/admin_panel/`` | Registry whitelist + API Django Ninja ``/api/admin/`` |`n"
    } else {
        ""
    }
    $feSection = if ($HasFrontend) {
        @"

## Front Astro (UI produit)
- UI produit dans ``frontend/`` : pages Astro pures (HTML + SCSS, zero React).
- Port dev **4321**. ``PUBLIC_API_URL`` (API) et ``PUBLIC_DJANGO_URL`` (liens Django).
- Admin DataStudio = HTMX Django ``/admin/`` (pas d'islands Astro).
- **Next.js interdit.** Pas de Tailwind / utility-first.
- Pas de logique metier cote client ; API = Django Ninja.
"@
    } else {
        @"

## UI produit
- Pas de dossier ``frontend/`` : pages publiques via templates Django + HTMX si besoin.
"@
    }
    $adminSection = if ($HasCustomAdmin) {
        @"

## Admin custom (admin_panel)
- API ``/api/admin/`` + auth JWT ``/api/auth/`` pour Console HTMX et outils.
- Registry whitelist, schema, CRUD, requetes SQL lecture seule.
"@
    } else {
        @"

## Administration
- ``django.contrib.admin`` sur ``/django-admin/`` (active en dev par defaut).
- Pas de ``apps/admin_panel`` ni d'API ``/api/admin/``.
"@
    }

    $structure = @"
# Structure applicative

## Racine monorepo
| Chemin | Role |
|--------|------|
| ``config/`` | Settings Django (dev/qua/prod), urls, wsgi/asgi, celery |
| ``apps/`` | Apps metier (Service Layer strict) |
$htmxRows$feRow$adminPanelRow| ``tests/`` | Pytest |
| ``docker-compose.yml`` / ``docker-compose.prod.yml`` | Dev local / prod |

## Apps Django
| App | Role |
|-----|------|
| ``apps.$AppName`` | App metier (modeles custom ; User = ``auth.User``) |

## Frontiere UI
- Surface **publique / produit** → Astro (``frontend/``).
- Surface **staff / admin / CRUD interne** → HTMX (templates Django).
- Ne pas melanger HTMX dans ``frontend/`` ni islands Astro dans les templates Django.
$feSection$adminSection
"@
    Write-TextFile -Path (Join-Path $cursorDir "app-structure.md") -Content $structure

    $umlFrontend = if ($HasFrontend) {
        @"
package "frontend" {
  [Astro pages]
  [Astro landing]
}
[frontend] --> [schemas] : HTTP JSON
"@
    } else {
        ""
    }
    $umlAdminPanel = if ($HasCustomAdmin) {
        @"
  package "admin_panel" {
    [registry]
    [API /api/admin/]
  }
"@
    } else {
        ""
    }

    $uml = @"
@startuml
package "config" {
  [settings/base]
  [settings/dev]
  [settings/qua]
  [settings/prod]
  [urls]
  [celery]
}
package "apps" {
  package "$AppName" {
    [models]
    [services]
    [selectors]
    [schemas]
    [api]
    [views HTMX]
  }
  package "auth" {
    [User]
  }
$umlAdminPanel
}
package "templates" {
  [HTMX partials]
}
$umlFrontend
database "PostgreSQL" as db
[apps] --> db : ORM
@enduml
"@
    Write-TextFile -Path (Join-Path $cursorDir "app-architecture.uml") -Content $uml

    $agentsTitle = if ($HasFrontend) {
        "monorepo Django Ninja + Astro + HTMX"
    } elseif ($HasCustomAdmin) {
        "Django Ninja + HTMX + admin_panel (sans Astro)"
    } else {
        "projet Django Ninja + HTMX (admin natif)"
    }
    Write-TextFile -Path (Join-Path $cursorDir "AGENTS.md") -Content @"
# Agents Cursor - $agentsTitle

## Lead par defaut
**@ProjectManager** - plan d'action, dispatch, Definition of Done.

## Matrice rapide
| Sujet | Agent |
|-------|--------|
| Service Layer, CBV, Django Ninja, MRO | @Architect (django-architect) |
| SCSS, tokens, BEM (Astro et HTMX) | @UI-Engineer |
| Astro, frontend/, PUBLIC_API_URL | @astro-specialist |
| HTMX, partials, back-office | @htmx-specialist |
| Docker, compose, CI | devops-engineer |
| CSRF, permissions, prod | security-auditor |
| ORM, N+1, SQL | database-optimizer |
| Pytest, edge cases | qa-specialist |
| Regles metier Python | logic-dev |

## Interdits
- **Next.js**
- Tailwind / utility-first
- pip / poetry / pipenv (uv uniquement)

Skills globales : ``~/.cursor/skills/<nom>/SKILL.md``
"@

    Write-TextFile -Path (Join-Path $skillsDir "STACK.md") -Content @"
# Conventions stack (genere par New-DjangoNinjaUvDockerHtmxProject.ps1)

## Python / Django
- Python 3.12+, typing strict, ``from __future__ import annotations``
- ``uv`` exclusif (``uv add``, ``uv sync``, ``uv run``)
- Service Layer : ``services.py`` (write), ``selectors.py`` (read), ``views.py`` = CBV uniquement
- Pas de logique metier dans models, signals, templates, forms
- Django Ninja pour API consommee par Astro (+ clients externes)

## UI interne HTMX
- Templates Django + HTMX : back-office staff, CRUD internes
- Partials ``hx-*``, CSRF, OOB ; logique via **services** partages avec Ninja
- SCSS 7-1 + tokens ``:root`` ; Flat High-End ; **Tailwind interdit**

## UI produit Astro (frontend/)
- Port **4321** ; ``PUBLIC_API_URL`` + ``PUBLIC_DJANGO_URL`` (secrets hors ``PUBLIC_*``)
- Zero React — Admin DataStudio sur Django ``/admin/`` (HTMX)
- **Next.js interdit**

## Docker
- ``docker compose up --build`` (db, redis, web, frontend?, worker, beat)
- Backend : image ``uv`` (context ``.``) ; Frontend : Node 22 + Astro :4321

## Definition of Done (rappel)
- [ ] Services/selectors separes ; CBV documentees (MRO si mixins)
- [ ] Tests Pytest (happy + edge + failure) pour chaque nouveau service
- [ ] ``ruff`` + ``mypy --strict`` sans warning sur code touche
- [ ] Mettre a jour ``.cursor/app-structure.md`` si structure change
"@

    $ruleContent = @"
---
description: Stack projet Django Ninja + Astro + HTMX + uv + Docker
globs: ["**/*"]
alwaysApply: true
---

# Stack monorepo (genere)

## Architecture
- Django racine : ``config/settings/`` (base, dev, qua, prod)
- ``apps/`` : Service Layer strict
- ``templates/`` + HTMX : UI interne staff
- ``frontend/`` : UI produit Astro (port 4321) si present
- API admin : ``/api/admin/`` (``apps.admin_panel``) si present
- ``django-admin/`` : fallback dev si ``DJANGO_ADMIN_ENABLED=true``

## Interdits
- **Next.js** (Astro pour l'UI produit)
- pip/poetry/pipenv (uv uniquement)
- Fonctions dans ``views.py`` (CBV seulement)
- Tailwind / utility-first CSS
- Logique metier dans signals ou templates
- Secrets dans ``PUBLIC_*``
- ``DEBUG=True`` en prod

## Orchestration Cursor
Lire ``.cursor/AGENTS.md`` et ``.cursor/skills/STACK.md`` en debut de tache.
"@
    Write-TextFile -Path (Join-Path $rulesDir "00-project-stack.mdc") -Content $ruleContent
}
