#Requires -Version 5.1
<#
.SYNOPSIS
  Banner, barre de progression et resume du pipeline scaffold.

.NOTES
  URLs frontend = Astro port 4321 (remplace l'ancien Next.js :3000).
#>

if (-not (Get-Variable -Name PipelineTotal -Scope Script -ErrorAction SilentlyContinue)) {
    $script:PipelineTotal = 11
}
if (-not (Get-Variable -Name PipelineStep -Scope Script -ErrorAction SilentlyContinue)) {
    $script:PipelineStep = 0
}
if (-not (Get-Variable -Name StepWatch -Scope Script -ErrorAction SilentlyContinue)) {
    $script:StepWatch = $null
}
function Write-PipelineBanner {
    param([string]$Subtitle = "")
    $line = ("=" * 62)
    Write-Host ""
    Write-Host "  $line" -ForegroundColor Cyan
    Write-Host "  |  MONOREPO DJANGO NINJA + ASTRO + HTMX + UV  (2026)     |" -ForegroundColor Cyan
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
        Write-Host "     [OK] $Message ($($sec)s)" -ForegroundColor Green
    } else {
        Write-Host "     [OK] $Message" -ForegroundColor Green
    }
}


function Write-PipelineSummary {
    param(
        [string]$Root,
        [string]$AppName,
        [bool]$HasCustomAdmin,
        [bool]$HasFrontend,
        [bool]$HasDocker
    )
    Write-Host ""
    Write-Host ("=" * 62) -ForegroundColor Green
    Write-Host "  PROJET PRET" -ForegroundColor Green
    Write-Host ("=" * 62) -ForegroundColor Green
    Write-Host "  Racine      : $Root"
    Write-Host "  App Django  : apps.$AppName"
    $adminLabel = if ($HasCustomAdmin) { "admin_panel + /api/admin/" } else { "django.contrib.admin (/django-admin/)" }
    Write-Host "  Admin       : $adminLabel"
    Write-Host "  Layout      : Django a la racine (manage.py, apps/, config/) + frontend/ Astro"
    Write-Host ""
    Write-Host "  Backend (dev) :" -ForegroundColor White
    Write-Host "    cd `"$Root`""
    Write-Host "    uv run python manage.py runserver"
    if (-not $HasFrontend) {
        Write-Host ""
        Write-Host "  URLs (Django + HTMX interne) :" -ForegroundColor White
        Write-Host "    http://127.0.0.1:8000/              (accueil)"
        Write-Host "    http://127.0.0.1:8000/backoffice/   (staff HTMX)"
        Write-Host "    http://127.0.0.1:8000/django-admin/ (administration)"
        Write-Host "    http://127.0.0.1:8000/api/health/   (sante API)"
    }
    if ($HasFrontend) {
        Write-Host ""
        Write-Host "  IMPORTANT : le port 4321 ne repond que si Astro est demarre." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Demarrage rapide (2 terminaux) :" -ForegroundColor White
        Write-Host "    .\scripts\dev-local.ps1"
        Write-Host ""
        Write-Host "  Ou manuellement :" -ForegroundColor White
        Write-Host "    Terminal 1 : cd `"$Root`" ; uv run python manage.py runserver"
        Write-Host "    Terminal 2 : cd `"$Root\frontend`" ; pnpm dev"
        Write-Host ""
        Write-Host "  URLs :" -ForegroundColor White
        Write-Host "    http://127.0.0.1:4321        (UI produit Astro)"
        if ($HasCustomAdmin) {
            Write-Host "    http://127.0.0.1:8000/admin/         (Admin DataStudio HTMX)"
            Write-Host "    http://127.0.0.1:8000/accounts/login/ (connexion staff)"
        }
        Write-Host "    http://127.0.0.1:8000/backoffice/  (staff HTMX)"
        Write-Host "    http://127.0.0.1:8000/api/health/"
    }
    if ($HasDocker) {
        Write-Host ""
        if ($HasFrontend) {
            Write-Host "  Docker (db + redis + web + frontend + worker/beat) :" -ForegroundColor White
            Write-Host "    cd `"$Root`""
            Write-Host "    `$env:DOCKER_BUILDKIT=1; docker compose up --build"
        } else {
            Write-Host "  Docker (db + web Django) :" -ForegroundColor White
            Write-Host "    cd `"$Root`""
            Write-Host "    `$env:DOCKER_BUILDKIT=1; docker compose up --build"
            Write-Host "    API : http://localhost:8000 - admin Django dev : /django-admin/"
        }
    }
    Write-Host ""
    Write-Host "  Cursor      : .cursor/AGENTS.md + .cursor/rules/" -ForegroundColor DarkGray
    Write-Host ""
}
