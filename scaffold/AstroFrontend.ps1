#Requires -Version 5.1
<#
.SYNOPSIS
  Genere le frontend Astro (UI produit uniquement — zero React).

.NOTES
  Sources : scaffold/astro-templates/ (copies + substitution __PROJECT_SLUG__).
  Next.js interdit. PUBLIC_API_URL (health API) ; PUBLIC_DJANGO_URL (liens HTML Django).
  Port dev Astro : 4321.
  Admin DataStudio = HTMX Django /admin/ (HtmxConsole.ps1).
  Depend de Write-TextFile, New-DevLocalScript (Common.ps1).
#>

$script:AstroFrontendModuleRoot = $PSScriptRoot

function Get-AstroTemplatesRoot {
    <#
    .SYNOPSIS
      Racine des templates Astro a copier dans frontend/.
    #>
    return (Join-Path $script:AstroFrontendModuleRoot "astro-templates")
}

function Copy-AstroTemplateTree {
    <#
    .SYNOPSIS
      Copie recursive des templates avec remplacement de placeholders.

    .PARAMETER SourceRoot
      Dossier scaffold/astro-templates.

    .PARAMETER DestRoot
      Dossier frontend/ du projet genere.

    .PARAMETER ProjectSlug
      Remplace __PROJECT_SLUG__.

    .PARAMETER IncludeRedirects
      Si faux, ignore les pages de redirection legacy /admin et /login.
    #>
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$DestRoot,
        [Parameter(Mandatory)][string]$ProjectSlug,
        [bool]$IncludeRedirects = $true
    )

    if (-not (Test-Path -LiteralPath $SourceRoot)) {
        throw "Templates Astro introuvables : $SourceRoot"
    }

    $skipFragments = @()
    if (-not $IncludeRedirects) {
        $skipFragments = @(
            "\pages\admin.astro",
            "\pages\login.astro"
        )
    }

    Get-ChildItem -Path $SourceRoot -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($SourceRoot.Length).TrimStart("\", "/")
        $relNorm = "\" + ($rel -replace "/", "\")
        foreach ($frag in $skipFragments) {
            if ($relNorm -like "*$frag*" -or $relNorm.EndsWith($frag.TrimEnd("\"))) {
                return
            }
        }

        $dest = Join-Path $DestRoot $rel
        $content = [System.IO.File]::ReadAllText($_.FullName)
        $content = $content.Replace("__PROJECT_SLUG__", $ProjectSlug)
        Write-TextFile -Path $dest -Content $content
    }
}

function New-AstroProductHomeOnly {
    <#
    .SYNOPSIS
      Page d'accueil sans liens Console (admin custom desactive).
    #>
    param(
        [Parameter(Mandatory)][string]$FeRoot,
        [Parameter(Mandatory)][string]$ProjectSlug
    )

    Write-TextFile -Path (Join-Path $FeRoot "src\pages\index.astro") -Content @"
---
import BaseLayout from "../layouts/BaseLayout.astro";

const apiUrl = import.meta.env.PUBLIC_API_URL ?? "http://localhost:8000";
const djangoUrl = (import.meta.env.PUBLIC_DJANGO_URL ?? "http://localhost:8000").replace(
  /\/`$/, "",
);
const backofficeUrl = "`${djangoUrl}/backoffice/";
const projectName = "$ProjectSlug";
---

<BaseLayout title={projectName + " — Accueil"}>
  <main class="page-home">
    <div class="page-home__inner">
      <header class="page-home__hero">
        <p class="page-home__eyebrow">Django Ninja · Astro · HTMX</p>
        <h1 class="page-home__title">{projectName}</h1>
        <p class="page-home__lead">
          UI produit Astro. API : <code>{apiUrl}</code>
        </p>
        <div class="page-home__actions">
          <a class="btn btn--primary" href={backofficeUrl}>Back-office staff</a>
        </div>
      </header>
    </div>
  </main>
</BaseLayout>
"@
}

function New-AstroFrontend {
    <#
    .SYNOPSIS
      Scaffold frontend/ Astro consommant Django Ninja (UI produit pure).

    .PARAMETER Root
      Racine du monorepo genere.

    .PARAMETER ProjectSlug
      Nom npm/package du frontend.

    .PARAMETER AppName
      App metier Django (contexte, non injecte en secrets).

    .PARAMETER HasCustomAdmin
      Si vrai, CTA Admin + pages redirect /admin et /login vers Django.
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ProjectSlug,
        [Parameter(Mandatory)][string]$AppName,
        [bool]$HasCustomAdmin = $true
    )

    $fe = Join-Path $Root "frontend"
    $templates = Get-AstroTemplatesRoot

    Write-Host "     Astro frontend -> $fe (templates: $templates)" -ForegroundColor DarkGray
    New-Item -ItemType Directory -Path $fe -Force | Out-Null

    Copy-AstroTemplateTree `
        -SourceRoot $templates `
        -DestRoot $fe `
        -ProjectSlug $ProjectSlug `
        -IncludeRedirects:$HasCustomAdmin

    if (-not $HasCustomAdmin) {
        New-AstroProductHomeOnly -FeRoot $fe -ProjectSlug $ProjectSlug
    }

    Write-TextFile -Path (Join-Path $fe ".env") -Content @"
PUBLIC_API_URL=http://localhost:8000
PUBLIC_DJANGO_URL=http://localhost:8000
"@

    Write-TextFile -Path (Join-Path $fe ".gitignore") -Content @'
# dependencies
node_modules/

# build
dist/
.astro/

# env (garder .env.example)
.env
.env.local
.env.*.local

# logs / OS
npm-debug.log*
pnpm-debug.log*
.DS_Store
Thumbs.db
'@

    $consoleNote = if ($HasCustomAdmin) {
        @"
## Console DataStudio (HTMX Django)

- Console : ``PUBLIC_DJANGO_URL`` + ``/admin/`` (ex. http://localhost:8000/admin/)
- Connexion staff : ``/accounts/login/``
- Pages Astro ``/admin`` et ``/login`` redirigent vers Django (compat legacy)
- API admin : ``PUBLIC_API_URL`` + ``/api/admin/*`` (consommee par la Console HTMX)
"@
    } else {
        "Admin custom desactive : pas de Console DataStudio ni de redirects Astro."
    }

    Write-TextFile -Path (Join-Path $fe "README.md") -Content @"
# $ProjectSlug-frontend (Astro)

UI produit Astro 5 — port **4321**. App Django de reference : ``$AppName``.

**Zero React** — landing HTML + SCSS uniquement.

## Scripts

``````bash
pnpm install
pnpm dev    # http://0.0.0.0:4321
pnpm build
``````

## Env

- ``PUBLIC_API_URL`` (defaut ``http://localhost:8000``) — health API ``/api/health/``
- ``PUBLIC_DJANGO_URL`` (defaut ``http://localhost:8000``) — liens HTML vers Django
- Jamais de secrets dans ``PUBLIC_*``.

$consoleNote

## Styles

SCSS 7-1 sous ``src/styles/`` — tokens Flat High-End, BEM. **Pas de Tailwind.**
"@

    if (Get-Command New-DevLocalScript -ErrorAction SilentlyContinue) {
        New-DevLocalScript -Root $Root -HasDocker $true -HasCustomAdmin:$HasCustomAdmin
    } else {
        Write-Host "     [warn] New-DevLocalScript absent — ajoutez Common.ps1 helpers" -ForegroundColor DarkYellow
    }

    Write-Host "     Astro OK (slug=$ProjectSlug, admin=$HasCustomAdmin, app=$AppName)" -ForegroundColor DarkGray
}
