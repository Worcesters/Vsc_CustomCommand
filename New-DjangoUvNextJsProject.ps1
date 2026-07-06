#Requires -Version 5.1
<#
.SYNOPSIS
  Cree un projet Django + uv + Docker, avec ou sans Next.js (question interactive).

.DESCRIPTION
  Pipeline : uv, Django (Service Layer), apps/admin_panel (API /api/admin/),
  option Next.js (DataStudio /admin, /login), Docker Compose (db + web, + frontend si Next),
  Cursor rules, pytest. Sans HTMX. Django /django-admin/ optionnel en dev (DJANGO_ADMIN_ENABLED).
  En mode interactif : question Next.js (UI DataStudio) puis admin custom (admin_panel).
  Reponse N admin custom = django.contrib.admin ; Next.js independant (avertissement si Next sans admin_panel).

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

.PARAMETER SkipCustomAdmin
  Ignore l'admin custom (pas de apps/admin_panel ni /api/admin/). Admin Django natif /django-admin/ active en dev.

.PARAMETER UseCustomAdmin
  Force l'admin custom admin_panel + API /api/admin/ (desactive la question interactive).

.PARAMETER SkipFrontend
  Ignore la generation Next.js (frontend/). En mode interactif, repondre N a la question Next.js equivaut a ce switch.

.PARAMETER UseNextJs
  Force la generation Next.js (desactive la question interactive). Par defaut : Next.js si mode interactif et reponse Y.

.PARAMETER SkipDocker
  Ignore Docker (Dockerfile, compose).

.PARAMETER SkipFrontendDeps
  N'installe pas les deps Node a l'init (pas de pnpm-lock.yaml ; Docker dev plus lent au 1er demarrage).

.PARAMETER SkipCreatesuperuser
  N'appelle pas manage.py createsuperuser apres les migrations.

.PARAMETER SkipMigrate
  Ignore la migration initiale Django.

.PARAMETER CommandTimeoutSeconds
  Timeout des commandes longues (uv, pnpm/npm install) en secondes (defaut : 900s).

.PARAMETER NoInteractive
  Desactive les questions interactives. Defaut sans flags : stack complete
  (Next.js + admin custom). Utiliser -SkipFrontend / -SkipCustomAdmin pour reduire.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\New-DjangoUvNextJsProject.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\New-DjangoUvNextJsProject.ps1 -NewFolder mon_site -NoInteractive -UseNextJs -UseCustomAdmin
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\New-DjangoUvNextJsProject.ps1 -NewFolder mon_site -NoInteractive -SkipFrontend -SkipCustomAdmin
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
    [switch]$SkipCustomAdmin,
    [switch]$UseCustomAdmin,
    [switch]$SkipFrontend,
    [switch]$UseNextJs,
    [switch]$SkipDocker,
    [switch]$SkipFrontendDeps,
    [switch]$SkipCreatesuperuser,
    [switch]$SkipMigrate,
    [switch]$NoInteractive,
    [int]$CommandTimeoutSeconds = 900
)

$script:PreviousErrorActionPreference = $ErrorActionPreference
$script:PreviousProgressPreference = $ProgressPreference
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
# Pas de bandeau Write-Progress (popup PowerShell) pendant le pipeline.
$ProgressPreference = "SilentlyContinue"
# Evite que les warnings stderr de "docker compose" (ex. variable attempt) declenchent un arret.
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $script:PreviousNativeCommandErrorPreference = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
}
$script:ScaffoldFailed = $false
$script:PreviousNativeCommandErrorPreference = $null
$script:ComposeDatabaseReady = $false
$script:DbEnvKeys = @(
    "DJANGO_DB_HOST", "DJANGO_DB_ENGINE", "DJANGO_DB_NAME",
    "DJANGO_DB_USER", "DJANGO_DB_PASSWORD", "DJANGO_DB_PORT", "DJANGO_USE_POSTGRES"
)

function Get-CorsOrigins {
    # Source unique des origines CORS/CSRF selon la presence du frontend Next.js.
    param([bool]$HasFrontend)
    if ($HasFrontend) {
        return "http://localhost:3000,http://127.0.0.1:3000"
    }
    return "http://localhost:8000"
}

function Test-LocalTcpPortAvailable {
    param([Parameter(Mandatory)][int]$Port)

    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $async = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
        $completed = $async.AsyncWaitHandle.WaitOne(300)
        if ($completed -and $client.Connected) {
            $client.EndConnect($async)
            return $false
        }
        return $true
    } catch {
        return $true
    } finally {
        if ($null -ne $client) {
            $client.Close()
            $client.Dispose()
        }
    }
}

function Find-AvailablePostgresHostPort {
    param(
        [int]$StartPort = 5433,
        [int]$EndPort = 5442
    )

    for ($port = $StartPort; $port -le $EndPort; $port++) {
        if (Test-LocalTcpPortAvailable -Port $port) {
            return $port
        }
    }
    throw "Aucun port hote libre entre $StartPort et $EndPort pour PostgreSQL Docker."
}

function Get-ProjectPostgresHostPort {
    param([Parameter(Mandatory)][string]$Root)

    $envFile = Join-Path $Root ".env"
    if (Test-Path -LiteralPath $envFile) {
        $match = Select-String -LiteralPath $envFile -Pattern '^\s*DJANGO_DB_PORT\s*=\s*(\d+)\s*$' -AllMatches
        if ($match -and $match.Matches.Count -gt 0) {
            return [int]$match.Matches[0].Groups[1].Value
        }
    }
    $composeFile = Join-Path $Root "docker-compose.yml"
    if (Test-Path -LiteralPath $composeFile) {
        $match = Select-String -LiteralPath $composeFile -Pattern '"(\d+):5432"' -AllMatches
        if ($match -and $match.Matches.Count -gt 0) {
            return [int]$match.Matches[0].Groups[1].Value
        }
    }
    return 5433
}

function Set-ProjectPostgresHostPort {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][int]$Port
    )

    $envFile = Join-Path $Root ".env"
    if (Test-Path -LiteralPath $envFile) {
        $envLines = Get-Content -LiteralPath $envFile -Encoding UTF8
        $updated = $false
        $envLines = $envLines | ForEach-Object {
            if ($_ -match '^\s*DJANGO_DB_PORT\s*=') {
                $updated = $true
                "DJANGO_DB_PORT=$Port"
            } else {
                $_
            }
        }
        if (-not $updated) {
            $envLines += "DJANGO_DB_PORT=$Port"
        }
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($envFile, ($envLines -join "`n") + "`n", $utf8NoBom)
    }

    foreach ($composeName in @("docker-compose.yml")) {
        $composePath = Join-Path $Root $composeName
        if (-not (Test-Path -LiteralPath $composePath)) {
            continue
        }
        $composeText = Get-Content -LiteralPath $composePath -Raw -Encoding UTF8
        $composeText = $composeText -replace '"\d+:5432"', "`"${Port}:5432`""
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($composePath, $composeText, $utf8NoBom)
    }
}

function Get-DockerCliOutputText {
    param($Output)

    if ($null -eq $Output) {
        return ""
    }
    return (($Output | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                $_.ToString()
            } else {
                "$_"
            }
        }) -join "`n").Trim()
}

function Test-PostgresHostTcpReady {
    param([Parameter(Mandatory)][int]$Port)

    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $async = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
        $completed = $async.AsyncWaitHandle.WaitOne(1500)
        if ($completed -and $client.Connected) {
            $client.EndConnect($async)
            return $true
        }
        return $false
    } catch {
        return $false
    } finally {
        if ($null -ne $client) {
            $client.Close()
            $client.Dispose()
        }
    }
}

function Test-PostgresHostSqlReady {
    param([Parameter(Mandatory)][string]$Root)

    Import-ProjectDotEnv -Root $Root
    $pythonExe = Join-Path $Root ".venv\Scripts\python.exe"
    if (-not (Test-Path -LiteralPath $pythonExe)) {
        return $false
    }
    $py = @'
import os
import sys
try:
    import psycopg
except ImportError:
    sys.exit(2)
host = os.environ.get("DJANGO_DB_HOST", "localhost")
port = int(os.environ.get("DJANGO_DB_PORT", "5432"))
dbname = os.environ.get("DJANGO_DB_NAME", "app")
user = os.environ.get("DJANGO_DB_USER", "app")
password = os.environ.get("DJANGO_DB_PASSWORD", "dev")
with psycopg.connect(
    host=host,
    port=port,
    dbname=dbname,
    user=user,
    password=password,
    connect_timeout=4,
) as conn:
    with conn.cursor() as cur:
        cur.execute("SELECT 1")
        cur.fetchone()
'@
    $probePath = Join-Path $Root ".postgres_probe.py"
    try {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($probePath, $py, $utf8NoBom)
        & $pythonExe $probePath 2>$null | Out-Null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    } finally {
        if (Test-Path -LiteralPath $probePath) {
            Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Wait-PostgresForMigrate {
    param(
        [Parameter(Mandatory)][string]$Root,
        [int]$TimeoutSeconds = 90
    )

    Import-ProjectDotEnv -Root $Root
    $hostPort = Get-ProjectPostgresHostPort -Root $Root
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $attempt = 0

    while ((Get-Date) -lt $deadline) {
        $attempt++
        if (Test-ComposeDatabaseAcceptsConnections -Root $Root) {
            if (Test-PostgresHostSqlReady -Root $Root) {
                $script:ComposeDatabaseReady = $true
                if ($attempt -gt 1) {
                    Write-Host "     PostgreSQL pret pour migrate (localhost:$hostPort, tentative $attempt)" -ForegroundColor DarkGray
                }
                return
            }
        } else {
            if ($attempt -eq 1) {
                Write-Host "     PostgreSQL indisponible - redemarrage du service db..." -ForegroundColor DarkYellow
            }
            $script:ComposeDatabaseReady = $false
            Start-ComposeDatabaseService -Root $Root -TimeoutSeconds 45
        }
        Start-Sleep -Seconds 2
    }

    throw @"
PostgreSQL non pret pour migrate apres ${TimeoutSeconds}s (localhost:$hostPort).
Verifiez : docker compose ps
Reinitialisez : docker compose down -v puis docker compose up -d db
"@
}

function Test-ComposeDatabaseAcceptsConnections {
    param(
        [Parameter(Mandatory)][string]$Root,
        [switch]$QuickTcpOnly
    )

    $hostPort = Get-ProjectPostgresHostPort -Root $Root
    if (-not (Test-PostgresHostTcpReady -Port $hostPort)) {
        return $false
    }
    if ($QuickTcpOnly) {
        return $true
    }

    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    Push-Location -LiteralPath $Root
    try {
        & docker compose exec -T db pg_isready -U app -d app 2>$null | Out-Null
        return ($LASTEXITCODE -eq 0)
    } finally {
        Pop-Location
        $ErrorActionPreference = $prevEap
    }
}

function Invoke-DockerCompose {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string[]]$ComposeArguments
    )

    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    Push-Location -LiteralPath $Root
    try {
        $output = & docker @ComposeArguments 2>&1
        $exitCode = $LASTEXITCODE
        if ($exitCode -eq 0) {
            return
        }
        $argsText = $ComposeArguments -join " "
        $detail = Get-DockerCliOutputText -Output $output
        $isDbUp = $argsText -match "compose\s+up\b" -and $argsText -match "\bdb\b"
        if ($isDbUp -and (Test-ComposeDatabaseAcceptsConnections -Root $Root -QuickTcpOnly)) {
            $script:ComposeDatabaseReady = $true
            Write-Host "     docker compose up : service db deja operationnel" -ForegroundColor DarkGray
            return
        }
        if ([string]::IsNullOrWhiteSpace($detail)) {
            throw "docker $argsText a echoue (code $exitCode)"
        }
        throw "docker $argsText a echoue (code $exitCode): $detail"
    } finally {
        Pop-Location
        $ErrorActionPreference = $prevEap
    }
}

function Ensure-ComposeDatabaseForDjango {
    param(
        [Parameter(Mandatory)][string]$Root,
        [int]$TimeoutSeconds = 60,
        [switch]$ForMigrate
    )

    if ($ForMigrate.IsPresent) {
        Wait-PostgresForMigrate -Root $Root -TimeoutSeconds $TimeoutSeconds
        return
    }

    if ($script:ComposeDatabaseReady) {
        if (Test-ComposeDatabaseAcceptsConnections -Root $Root) {
            $hostPort = Get-ProjectPostgresHostPort -Root $Root
            Write-Host "     PostgreSQL deja verifie (localhost:$hostPort)" -ForegroundColor DarkGray
            return
        }
        $script:ComposeDatabaseReady = $false
    }
    if (Test-ComposeDatabaseAcceptsConnections -Root $Root) {
        $hostPort = Get-ProjectPostgresHostPort -Root $Root
        Write-Host "     PostgreSQL deja operationnel (localhost:$hostPort)" -ForegroundColor DarkGray
        $script:ComposeDatabaseReady = $true
        return
    }
    Start-ComposeDatabaseService -Root $Root -TimeoutSeconds $TimeoutSeconds
}

function Import-ProjectDotEnv {
    param([Parameter(Mandatory)][string]$Root)

    $envFile = Join-Path $Root ".env"
    if (-not (Test-Path -LiteralPath $envFile)) {
        return
    }
    Get-Content -LiteralPath $envFile -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith("#")) {
            return
        }
        $eq = $line.IndexOf("=")
        if ($eq -lt 1) {
            return
        }
        $key = $line.Substring(0, $eq).Trim()
        $value = $line.Substring($eq + 1).Trim().Trim('"').Trim("'")
        if ($key.Length -gt 0) {
            Set-Item -Path "Env:$key" -Value $value
        }
    }
}

function Write-ProjectDotEnvForDocker {
    param(
        [Parameter(Mandatory)][string]$Root,
        [int]$PostgresHostPort = 5433,
        [bool]$HasFrontend = $true
    )

    $corsOrigins = Get-CorsOrigins -HasFrontend $HasFrontend
    $content = @"
# Genere par New-DjangoUvNextJsProject.ps1 - PostgreSQL = base Django unique (hote + Docker)

DJANGO_SETTINGS_MODULE=config.settings
DJANGO_ENV=dev
DJANGO_SECRET_KEY=dev-local-change-me
DJANGO_USE_POSTGRES=1
DJANGO_DB_ENGINE=django.db.backends.postgresql
DJANGO_DB_NAME=app
DJANGO_DB_USER=app
DJANGO_DB_PASSWORD=dev
DJANGO_DB_HOST=localhost
DJANGO_DB_PORT=$PostgresHostPort
CORS_ALLOWED_ORIGINS=$corsOrigins
CELERY_BROKER_URL=redis://localhost:6379/0
CELERY_RESULT_BACKEND=redis://localhost:6379/0

# Superuser (optionnel, init ou docker-compose service web)
# DJANGO_SUPERUSER_USERNAME=admin
# DJANGO_SUPERUSER_EMAIL=admin@local.test
# DJANGO_SUPERUSER_PASSWORD=change-me
"@
    Write-TextFile -Path (Join-Path $Root ".env") -Content $content
}

function Start-ComposeDatabaseService {
    param(
        [Parameter(Mandatory)][string]$Root,
        [int]$TimeoutSeconds = 90
    )

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw "Docker introuvable - impossible de demarrer PostgreSQL (service db)."
    }

    if (Test-ComposeDatabaseAcceptsConnections -Root $Root) {
        if (Test-PostgresHostSqlReady -Root $Root) {
            $readyPort = Get-ProjectPostgresHostPort -Root $Root
            $script:ComposeDatabaseReady = $true
            Write-Host "     PostgreSQL deja pret (localhost:$readyPort)" -ForegroundColor DarkGray
            return
        }
    }

    $hostPort = Get-ProjectPostgresHostPort -Root $Root
    $portRetries = 0
    $maxPortRetries = 10

    while ($true) {
        Push-Location $Root
        try {
            Write-Host "     docker compose up -d db (port hote $hostPort)" -ForegroundColor DarkGray
            Invoke-DockerCompose -Root $Root -ComposeArguments @("compose", "up", "-d", "db")
            break
        } catch {
            $msg = $_.Exception.Message
            if ($msg -match 'port is already allocated|already allocated|Bind for') {
                $portRetries++
                if ($portRetries -gt $maxPortRetries) {
                    throw @"
Impossible de demarrer PostgreSQL Docker : ports $hostPort+ occupes.
Arretez l'autre conteneur (docker ps) ou changez le mapping dans docker-compose.yml et DJANGO_DB_PORT dans .env.
"@
                }
                $hostPort = Find-AvailablePostgresHostPort -StartPort ($hostPort + 1)
                Set-ProjectPostgresHostPort -Root $Root -Port $hostPort
                Write-Host "     Port occupe - bascule sur localhost:$hostPort (.env + compose mis a jour)" -ForegroundColor DarkYellow
                continue
            }
            throw
        } finally {
            Pop-Location
        }
    }

    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    Push-Location -LiteralPath $Root
    try {
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        while ((Get-Date) -lt $deadline) {
            if (Test-PostgresHostTcpReady -Port $hostPort) {
                if (Test-ComposeDatabaseAcceptsConnections -Root $Root) {
                    if (Test-PostgresHostSqlReady -Root $Root) {
                        break
                    }
                }
            }
            Start-Sleep -Seconds 1
        }
        if (-not (Test-PostgresHostSqlReady -Root $Root)) {
            throw "PostgreSQL (service db) non pret apres $($TimeoutSeconds)s (pg_isready + connexion SQL)"
        }
        $script:ComposeDatabaseReady = $true
        Write-Host "     PostgreSQL pret (localhost:$hostPort, user app / password dev)" -ForegroundColor DarkGray
    } finally {
        Pop-Location
        $ErrorActionPreference = $prevEap
    }
}

function Test-ProjectDotEnvUsesPostgres {
    param([Parameter(Mandatory)][string]$Root)

    $envFile = Join-Path $Root ".env"
    if (-not (Test-Path -LiteralPath $envFile)) {
        return $false
    }
    $raw = Get-Content -LiteralPath $envFile -Raw -Encoding UTF8
    return $raw -match '(?m)DJANGO_USE_POSTGRES\s*=\s*(1|true|yes)'
}

function Test-AppDefinesModels {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$AppName
    )

    $modelsPath = Join-Path $Root "apps\$AppName\models.py"
    if (-not (Test-Path -LiteralPath $modelsPath)) {
        return $false
    }
    $content = Get-Content -LiteralPath $modelsPath -Raw -Encoding UTF8
    return $content -match 'class\s+\w+\s*\([^)]*models\.Model'
}

function Set-DjangoManageEnvironment {
    param(
        [Parameter(Mandatory)][string]$Root,
        [ref]$SavedEnv
    )

    $usePostgresEnv = Test-ProjectDotEnvUsesPostgres -Root $Root
    if ($usePostgresEnv) {
        Import-ProjectDotEnv -Root $Root
    } else {
        foreach ($key in $script:DbEnvKeys) {
            $item = Get-Item -Path "Env:$key" -ErrorAction SilentlyContinue
            if ($null -ne $item) {
                $SavedEnv.Value[$key] = $item.Value
                Remove-Item -Path "Env:$key" -ErrorAction SilentlyContinue
            }
        }
    }
    $env:DJANGO_ENV = "dev"
    $env:DJANGO_SETTINGS_MODULE = "config.settings"
    return $usePostgresEnv
}

function Restore-DjangoManageEnvironment {
    param(
        [bool]$UsePostgresEnv,
        [hashtable]$SavedEnv
    )

    if (-not $UsePostgresEnv) {
        foreach ($key in $script:DbEnvKeys) {
            Remove-Item -Path "Env:$key" -ErrorAction SilentlyContinue
        }
        foreach ($key in $SavedEnv.Keys) {
            Set-Item -Path "Env:$key" -Value $SavedEnv[$key]
        }
    }
}

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

function Write-Failure {
    param([string]$Message)
    $script:ScaffoldFailed = $true
    Write-Host ""
    Write-Host "  [ECHEC] $Message" -ForegroundColor Red
}

function Restore-ShellPreferences {
    $ErrorActionPreference = $script:PreviousErrorActionPreference
    if ($null -ne $script:PreviousProgressPreference) {
        $ProgressPreference = $script:PreviousProgressPreference
    }
    if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
        if ($null -ne $script:PreviousNativeCommandErrorPreference) {
            $PSNativeCommandUseErrorActionPreference = $script:PreviousNativeCommandErrorPreference
        }
    }
    Set-StrictMode -Off
}

function Test-DirectoryIsEmpty {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    $items = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
    return ($items.Count -eq 0)
}

function Get-AvailableProjectPath {
    param(
        [Parameter(Mandatory)][string]$ParentPath,
        [Parameter(Mandatory)][string]$BaseName
    )
    $candidate = $BaseName
    $i = 1
    do {
        $candidatePath = Join-Path $ParentPath $candidate
        if (-not (Test-Path -LiteralPath $candidatePath)) {
            return @{ Name = $candidate; Path = $candidatePath; Renamed = ($candidate -ne $BaseName) }
        }
        if (Test-DirectoryIsEmpty -Path $candidatePath) {
            return @{ Name = $candidate; Path = $candidatePath; Renamed = ($candidate -ne $BaseName) }
        }
        $candidate = "${BaseName}_$i"
        $i++
    } while ($i -lt 1000)
    throw "Impossible de trouver un nom de dossier libre pour '$BaseName'."
}

# --- Pipeline UI ---
# Valeur recalculee dynamiquement selon les options (cf. bloc principal).
$script:PipelineTotal = 11
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
    Write-Host ""
    Write-Host "  Backend (dev) :" -ForegroundColor White
    Write-Host "    cd `"$Root`""
    Write-Host "    uv run python manage.py runserver"
    if (-not $HasFrontend) {
        Write-Host ""
        Write-Host "  URLs (Django uniquement) :" -ForegroundColor White
        Write-Host "    http://127.0.0.1:8000/              (accueil)"
        Write-Host "    http://127.0.0.1:8000/django-admin/ (administration)"
        Write-Host "    http://127.0.0.1:8000/api/health/   (sante API)"
    }
    if ($HasFrontend) {
        Write-Host ""
        Write-Host "  IMPORTANT : le port 3000 ne repond que si Next.js est demarre." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Demarrage rapide (2 terminaux) :" -ForegroundColor White
        Write-Host "    .\scripts\dev-local.ps1"
        Write-Host ""
        Write-Host "  Ou manuellement :" -ForegroundColor White
        Write-Host "    Terminal 1 : cd `"$Root`" ; uv run python manage.py runserver"
        Write-Host "    Terminal 2 : cd `"$Root\frontend`" ; pnpm dev"
        Write-Host ""
        Write-Host "  URLs :" -ForegroundColor White
        Write-Host "    http://127.0.0.1:3000        (accueil)"
        Write-Host "    http://127.0.0.1:3000/admin  (DataStudio)"
        Write-Host "    http://127.0.0.1:3000/login"
    }
    if ($HasDocker) {
        Write-Host ""
        if ($HasFrontend) {
            Write-Host "  Docker (db + web + frontend) :" -ForegroundColor White
            Write-Host "    cd `"$Root`""
            Write-Host "    `$env:DOCKER_BUILDKIT=1; docker compose up --build"
            Write-Host "    (deps front au build ; conteneur demarre sur pnpm dev)"
        } else {
            Write-Host "  Docker (db + web Django uniquement) :" -ForegroundColor White
            Write-Host "    cd `"$Root`""
            Write-Host "    `$env:DOCKER_BUILDKIT=1; docker compose up --build"
            Write-Host "    API : http://localhost:8000 - admin Django dev : /django-admin/"
        }
    }
    Write-Host ""
    Write-Host "  Cursor      : .cursor/AGENTS.md + .cursor/rules/" -ForegroundColor DarkGray
    Write-Host ""
}

# --- Utilitaires ---

function Test-IsWindowsPlatform {
    # True sur Windows ; compatible PS 5.1 (pas de variable automatique $IsWindows).
    return ($env:OS -eq "Windows_NT")
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

function ConvertFrom-YesNoAnswer {
    # Accepte y/n, yes/no, oui/non (reponses francaises courantes).
    param(
        [string]$Answer,
        [bool]$DefaultWhenEmpty = $true
    )
    $a = $Answer.Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($a)) {
        return $DefaultWhenEmpty
    }
    if ($a -in @('y', 'yes', 'oui', 'o')) { return $true }
    if ($a -in @('n', 'no', 'non')) { return $false }
    return $null
}

function Read-YesNoPrompt {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [bool]$DefaultYes = $true
    )
    $hint = if ($DefaultYes) { 'Y/n' } else { 'y/N' }
    do {
        $raw = (Read-Host "$Prompt ($hint)").Trim()
        $parsed = ConvertFrom-YesNoAnswer -Answer $raw -DefaultWhenEmpty:$DefaultYes
        if ($null -ne $parsed) {
            return $parsed
        }
        Write-Host "  Reponse invalide. Utilisez oui/non, y/n, ou Entree pour la valeur par defaut." -ForegroundColor DarkYellow
    } while ($true)
}

function Test-ValidProjectFolderName {
    param([Parameter(Mandatory)][string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    if ($Name -match '^https?://') { return $false }
    if ($Name -match '[<>:"/\\|?*]') { return $false }
    if ($Name -match '\.(com|fr|eu|net|org|io)(/|$)') { return $false }
    return $true
}

function Write-MinimalMainCssFallback {
    param([Parameter(Mandatory)][string]$Root)
    $cssPath = Join-Path $Root "static\css\main.css"
    $content = @"
$(Get-BrandCharteTokensScss)
body {
  font-family: var(--font-sans);
  background: var(--color-bg);
  color: var(--color-text);
  margin: 0;
}
$(Get-BrandButtonsScss)
"@
    Write-TextFile -Path $cssPath -Content $content
}

function Invoke-ScssCompile {
    param([Parameter(Mandatory)][string]$Root)

    $mainScss = Join-Path $Root "static\scss\main.scss"
    $mainCss = Join-Path $Root "static\css\main.css"
    if (-not (Test-Path -LiteralPath $mainScss)) {
        return
    }
    $cssDir = Split-Path -Parent $mainCss
    if (-not (Test-Path -LiteralPath $cssDir)) {
        New-Item -ItemType Directory -Path $cssDir -Force | Out-Null
    }

    $npxPath = Resolve-NodeToolPath -Name "npx"
    if (-not $npxPath) {
        Write-Host "     Node/npx absent : CSS minimal genere (tokens + boutons)." -ForegroundColor DarkYellow
        Write-MinimalMainCssFallback -Root $Root
        return
    }

    try {
        Invoke-NativeCli -Exe "npx" -Arguments @(
            "--yes", "sass", "static/scss/main.scss", "static/css/main.css",
            "--no-source-map", "--style=expanded"
        ) -WorkingDirectory $Root -Quiet
        if (-not (Test-Path -LiteralPath $mainCss)) {
            throw "main.css non produit"
        }
    } catch {
        Write-Host "     sass echoue : $($_.Exception.Message) - CSS minimal genere." -ForegroundColor DarkYellow
        Write-MinimalMainCssFallback -Root $Root
    }
}

function Get-BrandCharteTokensScss {
    @'
:root {
  /* ================================================================
     PALETTE PRINCIPALE - source de verite unique.
     Modifiez uniquement ces 5 variables pour reskinner tout le site.
     ================================================================ */
  --brand-bg: #080808;          /* Fond principal */
  --brand-panel: #11100c;       /* Panneaux / Sidebar */
  --brand-text: #f5efe3;        /* Texte principal */
  --brand-text-muted: #a89a72;  /* Texte secondaire */
  --brand-accent: #d4af37;      /* Couleur d'accent : boutons, liens, selection */

  /* ---- Semantiques derivees de la palette (a ne pas modifier en priorite) ---- */
  --color-bg: var(--brand-bg);
  --color-surface: var(--brand-panel);
  --color-sidebar: var(--brand-panel);
  --color-text: var(--brand-text);
  --color-text-muted: var(--brand-text-muted);
  --color-border: color-mix(in srgb, var(--brand-text) 16%, var(--brand-bg));

  --primary-color: var(--brand-accent);
  --primary-color-hover: color-mix(in srgb, var(--brand-accent) 82%, #ffffff);
  --primary-color-active: color-mix(in srgb, var(--brand-accent) 82%, #000000);
  --primary-color-on: var(--brand-bg);

  --secondary-color: var(--brand-panel);
  --secondary-color-hover: color-mix(in srgb, var(--brand-panel) 80%, #ffffff);
  --secondary-color-active: color-mix(in srgb, var(--brand-panel) 82%, #000000);
  --secondary-color-on: var(--brand-accent);

  --tertiary-color: color-mix(in srgb, var(--brand-accent) 72%, #ffffff);
  --tertiary-color-hover: color-mix(in srgb, var(--brand-accent) 55%, #ffffff);
  --tertiary-color-active: var(--brand-accent);
  --tertiary-color-on: var(--brand-bg);

  --accent-color: var(--brand-accent);
  --accent-color-hover: color-mix(in srgb, var(--brand-accent) 80%, #ffffff);
  --accent-color-active: color-mix(in srgb, var(--brand-accent) 82%, #000000);
  --accent-color-on: var(--brand-bg);

  --success-color: #6b8f3c;
  --warning-color: #c9a227;
  --danger-color: #c45c4a;
  --info-color: #d4af37;

  --focus-ring: 0 0 0 2px color-mix(in srgb, var(--primary-color) 55%, transparent);
  --glow-gold: 0 0 24px color-mix(in srgb, var(--primary-color) 35%, transparent);
  --space-2: 0.5rem;
  --space-3: 0.75rem;
  --space-4: 1rem;
  --space-6: 1.5rem;
  --space-8: 2rem;
  --radius-md: 0.375rem;
  --radius-lg: 0.75rem;
  --font-sans: "Inter", "Geist", system-ui, sans-serif;
}

::selection {
  background: var(--brand-accent);
  color: var(--brand-bg);
}
'@
}

function Get-BrandButtonsScss {
    @'
.btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: var(--space-3) var(--space-4);
  border-radius: var(--radius-md);
  border: 1px solid transparent;
  font-weight: 600;
  text-decoration: none;
  transition: background 0.15s ease, color 0.15s ease, border-color 0.15s ease;
}

.btn--primary {
  background: linear-gradient(
    135deg,
    var(--primary-color),
    var(--tertiary-color)
  );
  color: var(--primary-color-on);
  box-shadow: var(--glow-gold);
}

.btn--primary:hover {
  background: linear-gradient(
    135deg,
    var(--primary-color-hover),
    var(--accent-color)
  );
}

.btn--secondary {
  background: transparent;
  color: var(--accent-color);
  border-color: color-mix(in srgb, var(--primary-color) 45%, var(--color-border));
}

.btn--secondary:hover {
  background: color-mix(in srgb, var(--primary-color) 12%, var(--color-surface));
  border-color: var(--primary-color-hover);
}

.btn--tertiary {
  background: var(--tertiary-color);
  color: var(--tertiary-color-on);
}

.btn--tertiary:hover {
  background: var(--tertiary-color-hover);
}
'@
}

function Get-BrandHomePageScss {
    @'
@keyframes brand-rise {
  from {
    opacity: 0;
    transform: translateY(1.25rem);
  }

  to {
    opacity: 1;
    transform: translateY(0);
  }
}

@keyframes brand-float {
  0%,
  100% {
    transform: translate(0, 0) scale(1);
  }

  50% {
    transform: translate(0.75rem, -1rem) scale(1.05);
  }
}

@keyframes brand-shimmer {
  0% {
    background-position: 0% 50%;
  }

  100% {
    background-position: 200% 50%;
  }
}

@keyframes brand-glow-pulse {
  0%,
  100% {
    opacity: 0.45;
  }

  50% {
    opacity: 0.85;
  }
}

@keyframes auth-panel-in {
  from {
    opacity: 0;
    transform: translateY(1.5rem) scale(0.98);
  }

  to {
    opacity: 1;
    transform: translateY(0) scale(1);
  }
}

.page-home {
  position: relative;
  min-height: 100vh;
  overflow: hidden;
  background: var(--color-bg);
}

.page-home__bg {
  position: absolute;
  inset: 0;
  pointer-events: none;
  overflow: hidden;
}

.page-home__orb {
  position: absolute;
  border-radius: 50%;
  filter: blur(72px);
  animation: brand-float 14s ease-in-out infinite;
}

.page-home__orb--1 {
  top: -8rem;
  right: -4rem;
  width: 22rem;
  height: 22rem;
  background: color-mix(in srgb, var(--primary-color) 28%, transparent);
}

.page-home__orb--2 {
  bottom: -10rem;
  left: -6rem;
  width: 26rem;
  height: 26rem;
  background: color-mix(in srgb, var(--tertiary-color) 18%, transparent);
  animation-delay: -5s;
}

.page-home__inner {
  position: relative;
  z-index: 1;
  display: flex;
  flex-direction: column;
  gap: var(--space-8);
  padding: var(--space-8) var(--space-4);
  max-width: 64rem;
  margin: 0 auto;
}

.page-home__hero {
  display: flex;
  flex-direction: column;
  gap: var(--space-4);
  padding: var(--space-8);
  border: 1px solid color-mix(in srgb, var(--primary-color) 35%, var(--color-border));
  border-radius: var(--radius-lg);
  background: linear-gradient(
    145deg,
    color-mix(in srgb, var(--primary-color) 10%, var(--color-surface)),
    var(--color-surface) 55%,
    var(--color-bg)
  );
  box-shadow: var(--glow-gold);
  animation: brand-rise 0.7s ease-out both;
}

.page-home__eyebrow {
  margin: 0;
  font-size: 0.875rem;
  font-weight: 600;
  color: var(--accent-color);
  text-transform: uppercase;
  letter-spacing: 0.12em;
}

.page-home__title {
  margin: 0;
  font-size: clamp(1.75rem, 4vw, 2.75rem);
  line-height: 1.15;
  background: linear-gradient(
    90deg,
    var(--color-text),
    var(--accent-color),
    var(--primary-color-hover)
  );
  background-size: 200% auto;
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
  animation: brand-shimmer 8s linear infinite;
}

.page-home__lead {
  margin: 0;
  max-width: 42rem;
  color: var(--color-text-muted);
  animation: brand-rise 0.7s ease-out 0.1s both;
}

.page-home__actions {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-3);
  animation: brand-rise 0.7s ease-out 0.2s both;
}

.page-home__grid {
  display: flex;
  flex-direction: column;
  gap: var(--space-4);
}

@media (min-width: 48rem) {
  .page-home__grid {
    flex-direction: row;
  }
}

.page-home__card {
  flex: 1;
  padding: var(--space-6);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  background: color-mix(in srgb, var(--color-surface) 92%, var(--color-bg));
  border-top: 2px solid var(--primary-color);
  transition: border-color 0.2s ease, box-shadow 0.2s ease, transform 0.2s ease;
  animation: brand-rise 0.7s ease-out both;
}

.page-home__card:nth-child(1) {
  animation-delay: 0.25s;
}

.page-home__card:nth-child(2) {
  animation-delay: 0.35s;
}

.page-home__card:nth-child(3) {
  animation-delay: 0.45s;
}

.page-home__card:hover {
  border-color: color-mix(in srgb, var(--primary-color) 55%, var(--color-border));
  box-shadow: var(--glow-gold);
  transform: translateY(-2px);
}

.page-home__card-title {
  margin: 0 0 var(--space-2);
  color: var(--accent-color);
}

.page-home__card-text {
  margin: 0;
  color: var(--color-text-muted);
}

.site-header {
  border-bottom: 1px solid var(--color-border);
  padding: var(--space-4) var(--space-6);
  background: var(--color-surface);
}

.site-header__brand {
  font-weight: 700;
  color: var(--accent-color);
}

.layout-main {
  min-height: calc(100vh - 4rem);
}

.page-auth {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
  min-height: 100vh;
  padding: var(--space-6);
  background: var(--color-bg);
  overflow: hidden;
}

.page-auth__bg {
  position: absolute;
  inset: 0;
  pointer-events: none;
  background:
    radial-gradient(
      circle at 20% 20%,
      color-mix(in srgb, var(--primary-color) 22%, transparent),
      transparent 45%
    ),
    radial-gradient(
      circle at 80% 80%,
      color-mix(in srgb, var(--tertiary-color) 14%, transparent),
      transparent 50%
    );
  animation: brand-glow-pulse 6s ease-in-out infinite;
}

.page-auth__panel {
  position: relative;
  z-index: 1;
  width: min(26rem, 100%);
  padding: var(--space-8);
  border: 1px solid color-mix(in srgb, var(--primary-color) 40%, var(--color-border));
  border-radius: var(--radius-lg);
  background: color-mix(in srgb, var(--color-surface) 88%, transparent);
  box-shadow: var(--glow-gold);
  animation: auth-panel-in 0.65s ease-out both;
}

.page-auth__brand {
  margin: 0 0 var(--space-2);
  font-size: 0.75rem;
  font-weight: 600;
  letter-spacing: 0.14em;
  text-transform: uppercase;
  color: var(--accent-color);
}

.page-auth__title {
  margin: 0 0 var(--space-2);
  font-size: clamp(1.5rem, 3vw, 2rem);
  color: var(--color-text);
}

.page-auth__lead {
  margin: 0 0 var(--space-6);
  color: var(--color-text-muted);
  font-size: 0.9375rem;
  line-height: 1.5;
}

.page-auth__form {
  display: flex;
  flex-direction: column;
  gap: var(--space-4);
}

.page-auth__label {
  font-size: 0.8125rem;
  font-weight: 600;
  color: var(--color-text-muted);
}

.page-auth__input {
  width: 100%;
  padding: var(--space-3) var(--space-4);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  background: var(--color-bg);
  color: var(--color-text);
  transition: border-color 0.2s ease, box-shadow 0.2s ease;
}

.page-auth__input:focus-visible {
  outline: none;
  border-color: var(--primary-color-hover);
  box-shadow: var(--focus-ring);
}

.page-auth__error {
  margin: 0;
  padding: var(--space-3);
  border-radius: var(--radius-md);
  border: 1px solid color-mix(in srgb, var(--danger-color) 40%, transparent);
  background: color-mix(in srgb, var(--danger-color) 12%, var(--color-surface));
  color: var(--danger-color);
  font-size: 0.875rem;
  animation: brand-rise 0.35s ease-out both;
}

.page-auth__submit {
  margin-top: var(--space-2);
}

.page-auth__back {
  color: var(--primary-color-hover);
  text-decoration: none;
  border-bottom: 1px solid color-mix(in srgb, var(--primary-color) 50%, transparent);
}

.page-auth__back:hover {
  color: var(--accent-color);
}

@media (prefers-reduced-motion: reduce) {
  .page-home__orb,
  .page-home__hero,
  .page-home__lead,
  .page-home__actions,
  .page-home__card,
  .page-home__title,
  .page-auth__panel,
  .page-auth__error,
  .page-auth__bg {
    animation: none;
  }

  .page-home__title {
    color: var(--color-text);
    background: none;
    -webkit-text-fill-color: unset;
  }
}
'@
}

function Get-BrandAdminScss {
    @'
@use "../tokens";

.admin-shell {
  display: flex;
  min-height: 100vh;
  background: var(--color-bg);
  color: var(--color-text);
  font-family: var(--font-sans);
}

.admin-shell__sidebar {
  display: flex;
  flex-direction: column;
  gap: var(--space-4);
  width: 14rem;
  border-right: 1px solid var(--color-border);
  padding: var(--space-4);
  background: linear-gradient(
    180deg,
    color-mix(in srgb, var(--secondary-color) 8%, var(--color-surface)),
    var(--color-surface)
  );
  border-top: 4px solid var(--primary-color);
}

.admin-shell__title {
  margin: 0;
  font-size: 1.125rem;
  color: var(--secondary-color);
}

.admin-shell__main {
  flex: 1;
  padding: var(--space-6);
}

.admin-nav {
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
}

.admin-nav__link {
  display: block;
  padding: var(--space-2) var(--space-3);
  border-radius: var(--radius-md);
  color: var(--color-text-muted);
  text-decoration: none;
}

.admin-nav__link:hover {
  color: var(--secondary-color);
  background: color-mix(in srgb, var(--primary-color) 12%, transparent);
}

.admin-card {
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  padding: var(--space-4);
  background: var(--color-surface);
  border-left: 3px solid var(--tertiary-color);
}

.admin-table {
  width: 100%;
  border-collapse: collapse;
}

.admin-table th {
  color: var(--secondary-color);
  font-weight: 600;
}

.admin-table th,
.admin-table td {
  border-bottom: 1px solid var(--color-border);
  padding: var(--space-2);
  text-align: left;
}

.admin-inline-links {
  display: inline-flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--space-2);
}

.admin-inline-links__sep {
  color: var(--color-text-muted);
}

.admin-registry {
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
  list-style: none;
  margin: 0;
  padding: 0;
}

.admin-registry__item {
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  padding: var(--space-3);
  background: var(--color-surface);
}

.schema-explorer {
  display: flex;
  flex-direction: column;
  gap: var(--space-4);
}

.schema-explorer__header {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--space-3);
}

.schema-explorer__layout {
  display: flex;
  flex-direction: column;
  gap: var(--space-4);
}

@media (min-width: 48rem) {
  .schema-explorer__layout {
    flex-direction: row;
    align-items: flex-start;
  }
}

.schema-explorer__fields {
  flex: 0 0 18rem;
  max-width: 100%;
}

.schema-explorer__diagram {
  flex: 1;
  min-width: 0;
}

.schema-flow {
  width: 100%;
  height: 28rem;
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  background: color-mix(in srgb, var(--color-bg) 92%, var(--color-surface));
}

.schema-flow__node {
  min-width: 9rem;
  padding: var(--space-2) var(--space-3);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  background: var(--color-surface);
  font-size: 0.8125rem;
  cursor: pointer;
  box-shadow: none;
}

.schema-flow__node--focus {
  border-color: var(--secondary-color);
  border-width: 2px;
}

.schema-flow__node-label {
  display: block;
  font-weight: 600;
  color: var(--secondary-color);
}

.schema-flow__node-id {
  display: block;
  margin-top: var(--space-1);
  color: var(--color-text-muted);
  font-size: 0.75rem;
}

.schema-relations {
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
}

.schema-relations__list {
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
  margin: 0;
  padding: 0;
  list-style: none;
}

.schema-relations__link {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-2);
  padding: var(--space-2) var(--space-3);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  text-decoration: none;
  color: var(--color-text);
}

.schema-relations__link:hover {
  border-color: var(--primary-color);
  background: color-mix(in srgb, var(--primary-color) 8%, transparent);
}

.schema-relations__badge {
  font-size: 0.75rem;
  padding: 0.125rem var(--space-2);
  border-radius: var(--radius-sm);
  background: color-mix(in srgb, var(--tertiary-color) 18%, transparent);
  color: var(--secondary-color);
}

.admin-export details pre {
  margin: var(--space-3) 0 0;
  padding: var(--space-3);
  border-radius: var(--radius-md);
  background: var(--color-bg);
  overflow-x: auto;
  font-size: 0.8125rem;
}
'@
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
    # LF uniquement : evite "set: Illegal option -" sous Linux (CRLF / shebang\r).
    $normalized = $Content -replace "`r`n", "`n" -replace "`r", "`n"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $normalized, $utf8NoBom)
}

function Resolve-ExecutablePath {
    param([Parameter(Mandatory)][string]$Name)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) { return $null }
    return $cmd.Source
}

function Resolve-NodeToolPath {
    param([Parameter(Mandatory)][string]$Name)

    # Priorite .cmd (evite pnpm.ps1 ouvert par Windows avec Bloc-notes / dialogue « Ouvrir avec »).
    $searchDirs = @()
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $searchDirs += (Join-Path $env:ProgramFiles "nodejs")
    }
    if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
        $searchDirs += (Join-Path ${env:ProgramFiles(x86)} "nodejs")
    }
    if (-not [string]::IsNullOrWhiteSpace($env:APPDATA)) {
        $searchDirs += (Join-Path $env:APPDATA "npm")
    }
    foreach ($dir in $searchDirs) {
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($suffix in @(".cmd", ".exe", ".ps1")) {
            $candidate = Join-Path $dir ($Name + $suffix)
            if (Test-Path -LiteralPath $candidate) {
                return $candidate
            }
        }
    }
    foreach ($suffix in @(".cmd", ".exe", ".ps1")) {
        $cmd = Get-Command ($Name + $suffix) -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source) {
            return $cmd.Source
        }
    }
    return $null
}

function New-CliProcessStartInfo {
    param(
        [Parameter(Mandatory)][string]$ExePath,
        [Parameter(Mandatory)][string]$ArgumentString,
        [Parameter(Mandatory)][string]$WorkingDirectory
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $ext = [System.IO.Path]::GetExtension($ExePath).ToLowerInvariant()
    if (Test-IsWindowsPlatform -and $ext -in @(".cmd", ".bat")) {
        $psi.FileName = if ([string]::IsNullOrWhiteSpace($env:ComSpec)) { "cmd.exe" } else { $env:ComSpec }
        $psi.Arguments = "/d /s /c `"`"$ExePath`" $ArgumentString`""
    } elseif (Test-IsWindowsPlatform -and $ext -eq ".ps1") {
        $psi.FileName = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
        if (-not (Test-Path -LiteralPath $psi.FileName)) {
            $psi.FileName = "powershell.exe"
        }
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ExePath`" $ArgumentString"
    } else {
        $psi.FileName = $ExePath
        $psi.Arguments = $ArgumentString
    }
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    return $psi
}

function Format-CliArgumentString {
    param([Parameter(Mandatory)][string[]]$Arguments)
    return ($Arguments | ForEach-Object {
            if ($_ -match '\s') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
        }) -join " "
}

function Get-PreferredNodeCmdPath {
    param([Parameter(Mandatory)][string]$Name)

    $path = Resolve-NodeToolPath -Name $Name
    if (-not $path) { return $null }
    if ($path -match '\.ps1$') {
        $cmdAlt = $path -replace '\.ps1$', '.cmd'
        if (Test-Path -LiteralPath $cmdAlt) {
            return $cmdAlt
        }
    }
    return $path
}

function Format-TextProgressBar {
    param(
        [int]$Percent,
        [int]$Width = 18
    )
    $pct = [math]::Max(0, [math]::Min(100, $Percent))
    $filled = [math]::Floor($Width * $pct / 100)
    $empty = $Width - $filled
    return ('[' + ('#' * $filled) + ('-' * $empty) + ']')
}

function Get-LogTailStatusLine {
    param(
        [Parameter(Mandatory)][string]$LogFile,
        [int]$MaxLength = 80
    )

    if (-not (Test-Path -LiteralPath $LogFile)) {
        return $null
    }
    $lines = @(Get-Content -LiteralPath $LogFile -Tail 8 -ErrorAction SilentlyContinue |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($lines.Count -eq 0) {
        return $null
    }
    $line = [string]$lines[-1]
    $line = $line -replace '\x1B\[[0-9;?]*[ -/]*[@-~]', ''
    $line = $line.Trim()
    if ($line.Length -gt $MaxLength) {
        return $line.Substring(0, $MaxLength - 3) + "..."
    }
    return $line
}

function Invoke-CmdBatchLogged {
    param(
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$CommandLine,
        [int]$TimeoutSeconds = 0,
        [int]$ProgressEstimateSeconds = 240,
        [switch]$Quiet,
        [switch]$ShowProgress,
        [string]$ProgressActivity = "Commande en cours"
    )

    $logFile = Join-Path $env:TEMP ("nextjs-cli-" + [guid]::NewGuid().ToString("n") + ".log")
    $batchFile = Join-Path $env:TEMP ("nextjs-run-" + [guid]::NewGuid().ToString("n") + ".cmd")
    $wd = $WorkingDirectory.Replace('"', '""')
    $log = $logFile.Replace('"', '""')

    $batchContent = @"
@echo off
setlocal
set CI=true
set FORCE_COLOR=0
set NO_COLOR=1
set npm_config_progress=false
set GIT_EDITOR=true
set EDITOR=true
set VISUAL=true
cd /d "$wd"
$CommandLine >> "$log" 2>&1
exit /b %ERRORLEVEL%
"@
    Set-Content -LiteralPath $batchFile -Value $batchContent -Encoding ASCII

    $exitCode = 1
    $proc = $null
    try {
        if (-not $Quiet -and -not $ShowProgress) {
            Write-Host "     Log temporaire : $logFile" -ForegroundColor DarkGray
        }

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "cmd.exe"
        $psi.Arguments = "/d /c `"`"$batchFile`"`""
        $psi.WorkingDirectory = $WorkingDirectory
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $proc = [System.Diagnostics.Process]::Start($psi)

        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $estimate = [math]::Max(60, $ProgressEstimateSeconds)
        $lastStatus = "Demarrage..."
        $lastPrintedSecond = -1

        while (-not $proc.HasExited) {
            if ($TimeoutSeconds -gt 0 -and $watch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                try { $proc.Kill() } catch {}
                throw "Timeout ($($TimeoutSeconds)s). Log : $logFile"
            }

            if ($ShowProgress) {
                $elapsed = [math]::Floor($watch.Elapsed.TotalSeconds)
                if ($elapsed -ne $lastPrintedSecond) {
                    $lastPrintedSecond = $elapsed
                    $statusLine = Get-LogTailStatusLine -LogFile $logFile
                    if ($statusLine) {
                        $lastStatus = $statusLine
                    }
                    $pct = [math]::Min(99, [int](($watch.Elapsed.TotalSeconds / $estimate) * 100))
                    $bar = Format-TextProgressBar -Percent $pct
                    $line = "     $bar $pct%  ${elapsed}s  $lastStatus"
                    if ($line.Length -gt 95) {
                        $line = $line.Substring(0, 92) + "..."
                    }
                    Write-Host ("`r$line".PadRight(95)) -NoNewline -ForegroundColor DarkGray
                }
            }

            Start-Sleep -Milliseconds 500
        }

        if ($ShowProgress) {
            $sec = [math]::Round($watch.Elapsed.TotalSeconds, 1)
            Write-Host ""
            Write-Host "     [OK] $ProgressActivity ($sec s)" -ForegroundColor Green
        }

        $exitCode = $proc.ExitCode
        if ($exitCode -ne 0) {
            $tail = @()
            if (Test-Path -LiteralPath $logFile) {
                $tail = @(Get-Content -LiteralPath $logFile -Tail 50 -ErrorAction SilentlyContinue)
            }
            $detail = if ($tail.Count -gt 0) { ($tail -join [Environment]::NewLine) } else { "(log vide)" }
            throw "Commande echouee (code $exitCode). Dernieres lignes :`n$detail"
        }
    } finally {
        if ($null -ne $proc -and -not $proc.HasExited) {
            try { $proc.Kill() } catch {}
        }
        Remove-Item -LiteralPath $batchFile -Force -ErrorAction SilentlyContinue
        if ($exitCode -eq 0) {
            Remove-Item -LiteralPath $logFile -Force -ErrorAction SilentlyContinue
        } elseif (-not $Quiet -and -not $ShowProgress) {
            Write-Host "     Log conserve pour diagnostic : $logFile" -ForegroundColor DarkYellow
        } elseif ($exitCode -ne 0 -and $ShowProgress) {
            Write-Host "     Log conserve pour diagnostic : $logFile" -ForegroundColor DarkYellow
        }
    }
}

function Invoke-NativeCli {
    param(
        [Parameter(Mandatory)][string]$Exe,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [switch]$Quiet
    )
    $nodeTools = @("node", "npm", "npx", "pnpm", "corepack")
    $exePath = if ($Exe -in $nodeTools) {
        Resolve-NodeToolPath -Name $Exe
    } else {
        Resolve-ExecutablePath -Name $Exe
    }
    if (-not $exePath) {
        throw "Executable introuvable : $Exe"
    }
    if (-not $Quiet) {
        Write-Host "     > $Exe $($Arguments -join ' ')" -ForegroundColor DarkGray
    }
    Push-Location -LiteralPath $WorkingDirectory
    try {
        $ext = [System.IO.Path]::GetExtension($exePath).ToLowerInvariant()
        if (Test-IsWindowsPlatform -and $ext -in @(".cmd", ".bat")) {
            $argString = Format-CliArgumentString -Arguments $Arguments
            & cmd.exe /d /s /c "`"$exePath`" $argString"
        } elseif (Test-IsWindowsPlatform -and $ext -eq ".ps1") {
            $pwsh = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
            if (-not (Test-Path -LiteralPath $pwsh)) { $pwsh = "powershell.exe" }
            & $pwsh -NoProfile -ExecutionPolicy Bypass -File $exePath @Arguments
        } else {
            & $exePath @Arguments
        }
        if ($LASTEXITCODE -ne 0) {
            throw "Commande echouee (code $LASTEXITCODE) : $Exe $($Arguments -join ' ')"
        }
    } finally {
        Pop-Location
    }
}

function Invoke-UvCommand {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [switch]$Quiet
    )
    Invoke-NativeCli -Exe "uv" -Arguments $Arguments -WorkingDirectory $WorkingDirectory -Quiet:$Quiet
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
        Write-Host "  Compte superuser requis pour /admin (DataStudio)" -ForegroundColor Cyan
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
    $templatesDirs = if ($HasFrontend) { "[]" } else { '[BASE_DIR / "templates"]' }
    $staticfilesDirsBlock = if ($HasFrontend) {
        ""
    } else {
        "STATICFILES_DIRS = [BASE_DIR / `"static`"]`n"
    }
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

from config.api import api

urlpatterns = [
    path("api/", api.urls),
$urlAdminApiBlock
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

    $homeEyebrow = if ($HasFrontend) { "Django + uv + Next.js" } else { "Django + uv" }
    $homeLead = if ($HasCustomAdmin -and $HasFrontend) {
        "UI produit et administration DataStudio via Next.js. API metier exposee par Django Ninja."
    } elseif ($HasCustomAdmin) {
        "Administration via API /api/admin/ (admin_panel). Interface Next.js optionnelle."
    } else {
        "Application Django avec admin natif. Service Layer et API Django Ninja pour votre metier."
    }
    $homeActions = if ($HasCustomAdmin -and $HasFrontend) {
        @'
        <a class="btn btn--primary" href="http://localhost:3000/admin">Administration</a>
        <a class="btn btn--secondary" href="http://localhost:3000/login">Connexion</a>
'@
    } elseif ($HasCustomAdmin) {
        @'
        <a class="btn btn--primary" href="/django-admin/">Admin Django (fallback)</a>
        <a class="btn btn--secondary" href="/api/health/">API Health</a>
'@
    } else {
        @'
        <a class="btn btn--primary" href="/django-admin/">Administration Django</a>
        <a class="btn btn--secondary" href="/api/health/">API Health</a>
'@
    }
    $card2Title = if ($HasCustomAdmin) { "Admin custom" } else { "Admin Django" }
    $card2Text = if ($HasCustomAdmin) {
        "Registry, schema et CRUD via admin_panel (API /api/admin/)."
    } else {
        "Gestion des utilisateurs et modeles via /django-admin/."
    }

    $appDir = Join-Path $Root "apps\$AppName"
    New-Item -ItemType Directory -Path $appDir -Force | Out-Null

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

    Write-TextFile -Path (Join-Path $appDir "schemas.py") -Content @'
"""Schemas Django Ninja (validation entree/sortie API)."""

from ninja import Schema
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

    if ($HasFrontend) {
        # UI produit servie par Next.js : la racine Django renvoie une info API (pas de template).
        Write-TextFile -Path (Join-Path $appDir "views.py") -Content @"
from __future__ import annotations

from django.http import HttpRequest, JsonResponse
from django.views import View


class HomeView(View):
    '''Racine de l'API Django (UI produit servie par Next.js sur le port 3000).

    MRO:
    1. View.get -> JsonResponse d'information API
    '''

    def get(self, request: HttpRequest) -> JsonResponse:
        return JsonResponse(
            {
                "service": "$AppName",
                "frontend": "http://localhost:3000",
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

function New-AdminPanelBackend {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$AppName
    )

    $panelDir = Join-Path $Root "apps\admin_panel"
    New-Item -ItemType Directory -Path (Join-Path $panelDir "tests") -Force | Out-Null

    Write-TextFile -Path (Join-Path $panelDir "apps.py") -Content @'
from django.apps import AppConfig


class AdminPanelConfig(AppConfig):
    """Panneau admin custom (API Django Ninja + registry whitelist)."""

    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.admin_panel"
    verbose_name = "Admin Panel"
'@

    Write-TextFile -Path (Join-Path $panelDir "registry.py") -Content @"
from __future__ import annotations

from typing import TypedDict


class RegistryEntry(TypedDict):
    app_label: str
    model_name: str
    label: str
    permissions: list[str]


# Whitelist des models exposes dans l'admin Next.js (pas de DDL via UI).
ADMIN_MODEL_REGISTRY: list[RegistryEntry] = [
    {
        "app_label": "auth",
        "model_name": "user",
        "label": "Utilisateurs",
        "permissions": ["list", "create", "edit", "delete", "schema"],
    },
]
"@

    Write-TextFile -Path (Join-Path $panelDir "selectors.py") -Content @'
from __future__ import annotations

import re
from decimal import Decimal

from django.apps import apps
from django.db import models

from .registry import ADMIN_MODEL_REGISTRY, RegistryEntry


def list_registry_entries() -> list[RegistryEntry]:
    """Retourne la whitelist des models admin."""
    return list(ADMIN_MODEL_REGISTRY)


def _schema_field_default(field: models.Field) -> object | None:
    """Valeur par defaut serialisable pour le schema API."""
    if not field.has_default():
        return None
    default_val = field.get_default()
    if callable(default_val):
        return None
    if hasattr(default_val, "isoformat"):
        return default_val.isoformat()
    return default_val


def _schema_field_is_auto_increment(field: models.Field) -> bool:
    """Indique si le champ PK est auto-genere (serial Django)."""
    return field.__class__.__name__ in {"AutoField", "BigAutoField"}


def _schema_required_on_create(model: type[models.Model], field: models.Field) -> bool:
    """Champ requis a la creation (hors PK auto, auto_now, M2M)."""
    if not getattr(field, "concrete", True):
        return False
    if not getattr(field, "editable", True):
        return False
    if getattr(field, "primary_key", False):
        return False
    if _schema_field_is_auto_increment(field):
        return False
    if getattr(field, "auto_now_add", False) or getattr(field, "auto_now", False):
        return False
    if isinstance(field, models.ManyToManyField):
        return False
    if field.name == "password" and model._meta.label_lower == "auth.user":
        return True
    return not getattr(field, "blank", False)


def get_model_schema(app_label: str, model_name: str) -> dict[str, object]:
    """Schema d'un model (champs, types, contraintes, relations)."""
    model = apps.get_model(app_label, model_name)
    fields: list[dict[str, object]] = []
    for field in model._meta.get_fields():
        if getattr(field, "auto_created", False) and not field.concrete:
            continue
        is_auto_pk = _schema_field_is_auto_increment(field)
        info: dict[str, object] = {
            "name": field.name,
            "type": field.__class__.__name__,
            "nullable": getattr(field, "null", False),
            "unique": getattr(field, "unique", False),
            "editable": getattr(field, "editable", True),
            "blank": getattr(field, "blank", False),
            "primary_key": getattr(field, "primary_key", False) or is_auto_pk,
            "auto_increment": is_auto_pk,
            "required_on_create": _schema_required_on_create(model, field),
        }
        if field.has_default():
            default_val = _schema_field_default(field)
            if default_val is not None:
                info["default"] = default_val
        if isinstance(field, (models.ForeignKey, models.OneToOneField)):
            info["relation"] = "FK"
            info["related_model"] = field.related_model._meta.label_lower
        elif isinstance(field, models.ManyToManyField):
            info["relation"] = "M2M"
            info["related_model"] = field.related_model._meta.label_lower
        fields.append(info)
    relations: list[dict[str, object]] = []
    for field in fields:
        related = field.get("related_model")
        if not related or "relation" not in field:
            continue
        rel_app, _, rel_model = str(related).partition(".")
        relations.append(
            {
                "field": field["name"],
                "type": field["relation"],
                "app_label": rel_app,
                "model_name": rel_model,
                "target_id": str(related),
            }
        )
    return {
        "app_label": app_label,
        "model_name": model_name,
        "table": model._meta.db_table,
        "fields": fields,
        "relations": relations,
        "incoming": _list_incoming_relations(app_label, model_name),
    }


def _list_incoming_relations(app_label: str, model_name: str) -> list[dict[str, object]]:
    """Relations entrantes (autres tables pointant vers ce model)."""
    target = f"{app_label}.{model_name}"
    incoming: list[dict[str, object]] = []
    for entry in ADMIN_MODEL_REGISTRY:
        peer_model = apps.get_model(entry["app_label"], entry["model_name"])
        for field in peer_model._meta.get_fields():
            if getattr(field, "auto_created", False) and not field.concrete:
                continue
            if not isinstance(
                field, (models.ForeignKey, models.OneToOneField, models.ManyToManyField)
            ):
                continue
            if field.related_model._meta.label_lower != target:
                continue
            rel_type = "M2M" if isinstance(field, models.ManyToManyField) else "FK"
            incoming.append(
                {
                    "field": field.name,
                    "type": rel_type,
                    "from_app_label": entry["app_label"],
                    "from_model_name": entry["model_name"],
                    "from_id": f"{entry['app_label']}.{entry['model_name']}",
                }
            )
    return incoming


def get_global_schema() -> dict[str, object]:
    """Schema global + liaisons pour diagramme."""
    nodes: list[dict[str, str]] = []
    edges: list[dict[str, str]] = []
    for entry in ADMIN_MODEL_REGISTRY:
        schema = get_model_schema(entry["app_label"], entry["model_name"])
        node_id = f"{entry['app_label']}.{entry['model_name']}"
        nodes.append(
            {
                "id": node_id,
                "label": entry["label"],
                "app_label": entry["app_label"],
                "model_name": entry["model_name"],
            }
        )
        for field in schema["fields"]:
            if "relation" in field and "related_model" in field:
                edges.append(
                    {
                        "from": node_id,
                        "to": str(field["related_model"]),
                        "type": str(field["relation"]),
                        "field": str(field["name"]),
                    }
                )
    return {"nodes": nodes, "edges": edges}


def export_schema_mermaid() -> str:
    """Export Mermaid ER (fichier .md)."""
    lines = ["```mermaid", "erDiagram"]
    for entry in ADMIN_MODEL_REGISTRY:
        schema = get_model_schema(entry["app_label"], entry["model_name"])
        entity = f"{entry['app_label']}_{entry['model_name']}".upper()
        lines.append(f"    {entity} {{")
        for field in schema["fields"]:
            if "relation" in field:
                continue
            lines.append(f"        {field['type']} {field['name']}")
        lines.append("    }")
    for entry in ADMIN_MODEL_REGISTRY:
        schema = get_model_schema(entry["app_label"], entry["model_name"])
        src = f"{entry['app_label']}_{entry['model_name']}".upper()
        for field in schema["fields"]:
            if field.get("relation") == "FK" and field.get("related_model"):
                dst = str(field["related_model"]).replace(".", "_").upper()
                lines.append(f"    {src} }}o--|| {dst} : {field['name']}")
    lines.append("```")
    return "\n".join(lines)


class AdminQueryError(ValueError):
    """Erreur validation ou execution d'une requete SQL admin."""


_MAX_QUERY_LENGTH = 10_000
_MAX_QUERY_ROWS = 500
_QUERY_TIMEOUT_MS = 5_000

_FORBIDDEN_SQL = re.compile(
    r"\b("
    r"INSERT|UPDATE|DELETE|DROP|ALTER|TRUNCATE|CREATE|GRANT|REVOKE|COPY|"
    r"EXECUTE|CALL|DO|MERGE|REPLACE|UPSERT|VACUUM|ANALYZE|REINDEX|CLUSTER|"
    r"REFRESH|COMMENT|LOCK|UNLOCK|SET|SHOW|LOAD|UNLISTEN|LISTEN|NOTIFY|"
    r"PREPARE|DEALLOCATE|DISCARD|RESET|REASSIGN|SECURITY|OWNER|INTO"
    r")\b",
    re.IGNORECASE,
)


def _strip_sql_comments(sql: str) -> str:
    """Retire les commentaires SQL (-- et /* */)."""
    without_block = re.sub(r"/\*.*?\*/", " ", sql, flags=re.DOTALL)
    return re.sub(r"--[^\n]*", " ", without_block)


def validate_readonly_sql(sql: str) -> str:
    """Valide qu'une requete est en lecture seule (SELECT / WITH / EXPLAIN)."""
    raw = sql.strip()
    if not raw:
        raise AdminQueryError("Requete vide.")
    if len(raw) > _MAX_QUERY_LENGTH:
        raise AdminQueryError(f"Requete trop longue (max {_MAX_QUERY_LENGTH} caracteres).")
    cleaned = raw.rstrip(";").strip()
    if ";" in cleaned:
        raise AdminQueryError("Une seule requete SQL a la fois.")
    normalized = _strip_sql_comments(cleaned)
    if _FORBIDDEN_SQL.search(normalized):
        raise AdminQueryError("Seules les requetes SELECT en lecture seule sont autorisees.")
    tokens = normalized.split()
    if not tokens:
        raise AdminQueryError("Requete vide.")
    first = tokens[0].upper()
    if first not in {"SELECT", "WITH", "EXPLAIN"}:
        raise AdminQueryError("La requete doit commencer par SELECT, WITH ou EXPLAIN.")
    return cleaned


def _ensure_row_limit(sql: str, max_rows: int) -> str:
    """Ajoute une limite de lignes si absente (sauf EXPLAIN)."""
    upper = sql.upper().lstrip()
    if upper.startswith("EXPLAIN"):
        return sql
    if re.search(r"\bLIMIT\b", upper):
        return sql
    return f"SELECT * FROM ({sql}) AS _dsq LIMIT {max_rows}"


def _serialize_query_cell(value: object) -> str | int | float | bool | None:
    """Convertit une cellule SQL en type JSON serialisable."""
    if value is None:
        return None
    if isinstance(value, bool):
        return value
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return value
    if isinstance(value, Decimal):
        return float(value)
    if hasattr(value, "isoformat"):
        return value.isoformat()  # type: ignore[union-attr]
    return str(value)


def execute_readonly_query(sql: str) -> dict[str, object]:
    """Execute une requete SELECT lecture seule et retourne colonnes + lignes."""
    import time

    from django.db import connection

    validated = validate_readonly_sql(sql)
    bounded = _ensure_row_limit(validated, _MAX_QUERY_ROWS)
    started = time.perf_counter()

    with connection.cursor() as cursor:
        cursor.execute("SET LOCAL statement_timeout = %s", [str(_QUERY_TIMEOUT_MS)])
        try:
            cursor.execute(bounded)
        except Exception as exc:
            raise AdminQueryError(f"Erreur SQL : {exc}") from exc

        if cursor.description is None:
            elapsed_ms = int((time.perf_counter() - started) * 1000)
            return {
                "columns": [],
                "rows": [],
                "row_count": 0,
                "truncated": False,
                "elapsed_ms": elapsed_ms,
            }

        columns = [col[0] for col in cursor.description]
        raw_rows = cursor.fetchmany(_MAX_QUERY_ROWS + 1)
        truncated = len(raw_rows) > _MAX_QUERY_ROWS
        if truncated:
            raw_rows = raw_rows[:_MAX_QUERY_ROWS]

        rows: list[dict[str, object]] = []
        for raw in raw_rows:
            row: dict[str, object] = {}
            for idx, col_name in enumerate(columns):
                row[col_name] = _serialize_query_cell(raw[idx])
            rows.append(row)

        elapsed_ms = int((time.perf_counter() - started) * 1000)
        return {
            "columns": columns,
            "rows": rows,
            "row_count": len(rows),
            "truncated": truncated,
            "elapsed_ms": elapsed_ms,
        }
'@

    Write-TextFile -Path (Join-Path $panelDir "services.py") -Content @'
from __future__ import annotations

from decimal import Decimal, InvalidOperation
from typing import Any

from django.apps import apps as django_apps
from django.core.exceptions import ValidationError
from django.db import IntegrityError, models
from django.utils.dateparse import parse_date, parse_datetime

from apps.admin_panel.registry import ADMIN_MODEL_REGISTRY


class AdminModelNotAllowedError(LookupError):
    """Model hors whitelist registry admin."""


class AdminModelValidationError(ValueError):
    """Erreur validation admin avec detail par champ."""

    def __init__(self, detail: str, fields: dict[str, str] | None = None) -> None:
        self.detail = detail
        self.fields = fields or {}
        super().__init__(detail)


def _field_validation_error(field_name: str, message: str) -> AdminModelValidationError:
    return AdminModelValidationError(message, {field_name: message})


def _validation_error_from_exception(exc: Exception) -> AdminModelValidationError:
    """Convertit ValidationError / IntegrityError en erreur API structuree."""
    if isinstance(exc, ValidationError):
        if hasattr(exc, "error_dict"):
            fields = {
                str(key): " ".join(str(item) for item in messages)
                for key, messages in exc.error_dict.items()
            }
            return AdminModelValidationError("Validation impossible.", fields)
        return AdminModelValidationError(str(exc))
    if isinstance(exc, IntegrityError):
        text = str(exc)
        fields: dict[str, str] = {}
        if "auth_user_username_key" in text:
            fields["username"] = "Ce nom d'utilisateur existe deja."
        elif "username" in text.lower() and "unique" in text.lower():
            fields["username"] = "Ce nom d'utilisateur existe deja."
        if "auth_user_email_key" in text:
            fields["email"] = "Cette adresse e-mail existe deja."
        detail = "Contrainte d'unicite en base de donnees."
        if fields:
            return AdminModelValidationError(detail, fields)
        return AdminModelValidationError(detail)
    return AdminModelValidationError(str(exc))


def _resolve_model(app_label: str, model_name: str) -> type[models.Model]:
    """Retourne le model Django si present dans le registry admin."""
    allowed = any(
        e["app_label"] == app_label and e["model_name"] == model_name
        for e in ADMIN_MODEL_REGISTRY
    )
    if not allowed:
        raise AdminModelNotAllowedError(f"{app_label}.{model_name}")
    return django_apps.get_model(app_label, model_name)


def _editable_fields(model: type[models.Model]) -> set[str]:
    return {f.name for f in model._meta.concrete_fields if f.editable}


def _serialize_value(value: object) -> object:
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return value


def _is_auth_user_model(model: type[models.Model]) -> bool:
    return model._meta.label_lower == "auth.user"


def serialize_instance(model: type[models.Model], instance: models.Model) -> dict[str, Any]:
    """Serialise une instance ORM en dict JSON-friendly."""
    row: dict[str, Any] = {}
    for field in model._meta.concrete_fields:
        if field.name == "password":
            if _is_auth_user_model(model):
                row["password_set"] = instance.has_usable_password()
            continue
        row[field.name] = _serialize_value(getattr(instance, field.attname))
    return row


def _coerce_field_value(field: models.Field, raw: object) -> object:
    """Convertit une valeur API vers le type ORM."""
    if raw is None or raw == "":
        if field.null or field.blank:
            return None
        raise _field_validation_error(field.name, "Ce champ est obligatoire.")
    if isinstance(field, models.BooleanField):
        if isinstance(raw, bool):
            return raw
        return str(raw).lower() in ("1", "true", "yes", "on")
    if isinstance(field, (models.IntegerField, models.BigIntegerField, models.SmallIntegerField)):
        return int(raw)
    if isinstance(field, models.DecimalField):
        try:
            return Decimal(str(raw))
        except InvalidOperation as exc:
            raise _field_validation_error(
                field.name, "Valeur decimale invalide."
            ) from exc
    if isinstance(field, models.DateTimeField):
        parsed = parse_datetime(str(raw))
        if parsed is None:
            raise _field_validation_error(field.name, "Date ou heure invalide.")
        return parsed
    if isinstance(field, models.DateField):
        parsed = parse_date(str(raw))
        if parsed is None:
            raise _field_validation_error(field.name, "Date invalide.")
        return parsed
    return raw


def _clean_payload(
    model: type[models.Model],
    payload: dict[str, Any],
    *,
    exclude_pk: bool = False,
) -> dict[str, Any]:
    allowed = _editable_fields(model)
    cleaned: dict[str, Any] = {}
    pk_name = model._meta.pk.name
    for key, value in payload.items():
        if key not in allowed:
            continue
        if exclude_pk and key == pk_name:
            continue
        field = model._meta.get_field(key)
        cleaned[key] = _coerce_field_value(field, value)
    return cleaned


def list_model_rows(app_label: str, model_name: str, *, limit: int = 500) -> dict[str, Any]:
    """Liste les lignes d'un model (lecture ORM pour grille admin)."""
    model = _resolve_model(app_label, model_name)
    rows = [
        serialize_instance(model, obj) for obj in model.objects.all()[:limit]
    ]
    return {"results": rows, "count": model.objects.count(), "pk_field": model._meta.pk.name}


def _create_auth_user(model: type[models.Model], payload: dict[str, Any]) -> dict[str, Any]:
    """Cree un utilisateur Django avec mot de passe hashe."""
    data = _clean_payload(model, payload, exclude_pk=True)
    password = data.pop("password", None)
    if not password:
        raise _field_validation_error("password", "Le mot de passe est obligatoire a la creation.")
    username = data.get("username")
    if not username:
        raise _field_validation_error("username", "Le nom d'utilisateur est obligatoire.")
    m2m_skip = {"groups", "user_permissions"}
    extra = {
        key: value
        for key, value in data.items()
        if key not in {"username", "email", "password"} and key not in m2m_skip
    }
    try:
        user = model.objects.create_user(
            username=str(username),
            email=str(data.get("email", "")),
            password=str(password),
            **extra,
        )
        user.full_clean()
    except (ValidationError, IntegrityError) as exc:
        raise _validation_error_from_exception(exc) from exc
    return serialize_instance(model, user)


def _update_auth_user(
    model: type[models.Model],
    instance: models.Model,
    payload: dict[str, Any],
) -> dict[str, Any]:
    """Met a jour un utilisateur Django (hash du mot de passe si fourni)."""
    raw = dict(payload)
    password = raw.pop("password", None)
    if password == "":
        password = None
    raw.pop("password_set", None)
    data = _clean_payload(model, raw, exclude_pk=True)
    m2m_skip = {"groups", "user_permissions"}
    for name, value in data.items():
        if name in m2m_skip:
            continue
        setattr(instance, name, value)
    if password:
        instance.set_password(str(password))
    try:
        instance.full_clean()
        instance.save()
    except (ValidationError, IntegrityError) as exc:
        raise _validation_error_from_exception(exc) from exc
    return serialize_instance(model, instance)


def create_model_row(app_label: str, model_name: str, payload: dict[str, Any]) -> dict[str, Any]:
    """Cree une ligne via ORM (whitelist registry)."""
    model = _resolve_model(app_label, model_name)
    if _is_auth_user_model(model):
        return _create_auth_user(model, payload)
    data = _clean_payload(model, payload, exclude_pk=True)
    try:
        instance = model(**data)
        instance.full_clean()
        instance.save()
    except (ValidationError, IntegrityError) as exc:
        raise _validation_error_from_exception(exc) from exc
    return serialize_instance(model, instance)


def update_model_row(
    app_label: str,
    model_name: str,
    pk: str,
    payload: dict[str, Any],
) -> dict[str, Any]:
    """Met a jour une ligne via ORM."""
    model = _resolve_model(app_label, model_name)
    instance = model.objects.get(pk=pk)
    if _is_auth_user_model(model):
        return _update_auth_user(model, instance, payload)
    data = _clean_payload(model, payload, exclude_pk=True)
    for name, value in data.items():
        setattr(instance, name, value)
    try:
        instance.full_clean()
        instance.save()
    except (ValidationError, IntegrityError) as exc:
        raise _validation_error_from_exception(exc) from exc
    return serialize_instance(model, instance)


def delete_model_row(app_label: str, model_name: str, pk: str) -> None:
    """Supprime une ligne via ORM."""
    model = _resolve_model(app_label, model_name)
    model.objects.filter(pk=pk).delete()
'@

    Write-TextFile -Path (Join-Path $panelDir "schemas.py") -Content @'
"""Schemas Django Ninja (validation entree API)."""

from ninja import Schema


class QueryExecuteIn(Schema):
    """Payload execution requete SQL lecture seule."""

    sql: str
'@

    Write-TextFile -Path (Join-Path $panelDir "auth.py") -Content @'
"""JWT utilitaires pour l''admin panel (superuser)."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import Any

import jwt
from django.conf import settings
from django.contrib.auth import get_user_model
from ninja.security import HttpBearer

User = get_user_model()

ACCESS_LIFETIME = timedelta(hours=8)
REFRESH_LIFETIME = timedelta(days=1)
ALGORITHM = "HS256"


def _encode(payload: dict[str, Any], lifetime: timedelta) -> str:
    now = datetime.now(tz=UTC)
    body = {
        **payload,
        "exp": now + lifetime,
        "iat": now,
    }
    return jwt.encode(body, settings.SECRET_KEY, algorithm=ALGORITHM)


def create_token_pair(user: User) -> dict[str, str]:
    """Genere une paire access/refresh JWT."""
    base = {"user_id": user.pk, "username": user.username}
    return {
        "access": _encode({**base, "type": "access"}, ACCESS_LIFETIME),
        "refresh": _encode({**base, "type": "refresh"}, REFRESH_LIFETIME),
    }


class AdminJWTAuth(HttpBearer):
    """Authentification Bearer JWT — superuser requis."""

    def authenticate(self, request, token: str) -> User | None:
        try:
            payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[ALGORITHM])
        except jwt.PyJWTError:
            return None
        if payload.get("type") != "access":
            return None
        user_id = payload.get("user_id")
        if not user_id:
            return None
        try:
            user = User.objects.get(pk=user_id)
        except User.DoesNotExist:
            return None
        if not user.is_active or not user.is_superuser:
            return None
        return user
'@

    Write-TextFile -Path (Join-Path $panelDir "api.py") -Content @'
"""Routes API admin panel (Django Ninja)."""

from __future__ import annotations

from django.contrib.auth import authenticate
from django.core.exceptions import ObjectDoesNotExist
from ninja import Router, Schema

from . import selectors
from .auth import AdminJWTAuth, create_token_pair
from .schemas import QueryExecuteIn

auth_router = Router(tags=["auth"])
admin_router = Router(tags=["admin"])
_admin_auth = AdminJWTAuth()


class LoginIn(Schema):
    username: str
    password: str


class LoginUserOut(Schema):
    username: str
    is_superuser: bool


class LoginOut(Schema):
    access: str
    refresh: str
    user: LoginUserOut


class SessionOut(Schema):
    username: str
    is_superuser: bool


@auth_router.post("/login/", response={200: LoginOut, 400: dict, 401: dict, 403: dict})
def admin_login(request, payload: LoginIn):
    """POST /api/auth/login/ - JWT si superuser."""
    username = payload.username.strip()
    password = payload.password
    if not username or not password:
        return 400, {
            "detail": "Identifiant et mot de passe requis.",
            "code": "missing_credentials",
        }
    user = authenticate(request=request, username=username, password=password)
    if user is None:
        return 401, {
            "detail": "Identifiants incorrects pour cette base de donnees.",
            "code": "invalid_credentials",
        }
    if not user.is_superuser:
        return 403, {
            "detail": (
                "Compte reconnu mais acces refuse : superuser Django requis "
                "(docker compose exec web uv run python manage.py createsuperuser)."
            ),
            "code": "not_superuser",
        }
    tokens = create_token_pair(user)
    return 200, LoginOut(
        access=tokens["access"],
        refresh=tokens["refresh"],
        user=LoginUserOut(username=user.username, is_superuser=user.is_superuser),
    )


@auth_router.get("/session/", response={200: SessionOut, 401: dict, 403: dict}, auth=_admin_auth)
def admin_session(request):
    """GET /api/auth/session/ - profil superuser connecte."""
    user = request.auth
    return SessionOut(username=user.username, is_superuser=user.is_superuser)


@admin_router.get("/registry/", auth=_admin_auth)
def registry_list(request):
    """GET /api/admin/registry/ - liste whitelist models."""
    return {"results": selectors.list_registry_entries()}


@admin_router.get("/schema/", auth=_admin_auth)
def schema_global(request):
    """GET /api/admin/schema/ - schema global + liaisons."""
    return selectors.get_global_schema()


@admin_router.get("/schema/{app_label}/{model_name}/", auth=_admin_auth)
def schema_model(request, app_label: str, model_name: str):
    """GET /api/admin/schema/<app>/<model>/ - schema d''une table."""
    return selectors.get_model_schema(app_label, model_name)


@admin_router.get("/schema/export/", auth=_admin_auth)
def schema_export(request):
    """GET /api/admin/schema/export/ - export Mermaid markdown."""
    mermaid = selectors.export_schema_mermaid()
    return {
        "format": "mermaid",
        "markdown": mermaid,
        "svg_hint": "Telecharger via frontend/admin/schema (V2)",
    }


@admin_router.get("/models/{app_label}/{model_name}/", auth=_admin_auth, response={200: dict, 404: dict})
def model_rows_list(request, app_label: str, model_name: str):
    """GET /api/admin/models/<app>/<model>/ - grille admin CRUD."""
    from .services import AdminModelNotAllowedError, list_model_rows

    try:
        return list_model_rows(app_label, model_name)
    except AdminModelNotAllowedError:
        return 404, {"detail": "Model non autorise"}


@admin_router.post("/models/{app_label}/{model_name}/", auth=_admin_auth, response={201: dict, 400: dict, 404: dict})
def model_rows_create(request, app_label: str, model_name: str, payload: dict):
    """POST /api/admin/models/<app>/<model>/ - creation."""
    from .services import (
        AdminModelNotAllowedError,
        AdminModelValidationError,
        create_model_row,
    )

    try:
        row = create_model_row(app_label, model_name, payload)
        return 201, row
    except AdminModelNotAllowedError:
        return 404, {"detail": "Model non autorise"}
    except AdminModelValidationError as exc:
        return 400, {"detail": exc.detail, "fields": exc.fields}
    except ValueError as exc:
        return 400, {"detail": str(exc)}


@admin_router.patch("/models/{app_label}/{model_name}/{pk}/", auth=_admin_auth, response={200: dict, 400: dict, 404: dict})
def model_row_update(request, app_label: str, model_name: str, pk: str, payload: dict):
    """PATCH /api/admin/models/<app>/<model>/<pk>/."""
    from .services import (
        AdminModelNotAllowedError,
        AdminModelValidationError,
        update_model_row,
    )

    try:
        return update_model_row(app_label, model_name, pk, payload)
    except AdminModelNotAllowedError:
        return 404, {"detail": "Model non autorise"}
    except ObjectDoesNotExist:
        return 404, {"detail": "Ligne introuvable"}
    except AdminModelValidationError as exc:
        return 400, {"detail": exc.detail, "fields": exc.fields}
    except ValueError as exc:
        return 400, {"detail": str(exc)}


@admin_router.delete("/models/{app_label}/{model_name}/{pk}/", auth=_admin_auth, response={204: None, 404: dict})
def model_row_delete(request, app_label: str, model_name: str, pk: str):
    """DELETE /api/admin/models/<app>/<model>/<pk>/."""
    from .services import AdminModelNotAllowedError, delete_model_row

    try:
        delete_model_row(app_label, model_name, pk)
        return 204, None
    except AdminModelNotAllowedError:
        return 404, {"detail": "Model non autorise"}
    except ObjectDoesNotExist:
        return 404, {"detail": "Ligne introuvable"}


@admin_router.post("/query/", auth=_admin_auth, response={200: dict, 400: dict})
def query_execute(request, payload: QueryExecuteIn):
    """POST /api/admin/query/ - execute une requete SELECT lecture seule."""
    from .selectors import AdminQueryError, execute_readonly_query

    sql = payload.sql.strip()
    try:
        return execute_readonly_query(sql)
    except AdminQueryError as exc:
        return 400, {"detail": str(exc)}
'@

    Write-TextFile -Path (Join-Path $panelDir "admin.py") -Content @'
"""Django admin natif non utilise pour les models registry (admin Next.js)."""
'@

    Write-TextFile -Path (Join-Path $panelDir "models.py") -Content @'
"""Pas de tables admin_panel - schema via models metier + migrations uniquement."""
'@

    Write-TextFile -Path (Join-Path $panelDir "tests\test_registry.py") -Content @'
"""Tests registry admin panel."""

from apps.admin_panel.registry import ADMIN_MODEL_REGISTRY
from apps.admin_panel.selectors import list_registry_entries


def test_registry_contains_user() -> None:
    entries = list_registry_entries()
    assert any(
        e["app_label"] == "auth" and e["model_name"] == "user" for e in entries
    )


def test_registry_whitelist_not_empty() -> None:
    assert len(ADMIN_MODEL_REGISTRY) >= 1
'@

    Write-TextFile -Path (Join-Path $panelDir "tests\test_schema.py") -Content @"
"""Tests schema admin panel."""

import pytest

from apps.admin_panel.selectors import export_schema_mermaid, get_model_schema


@pytest.mark.django_db
def test_model_schema_user_fields() -> None:
    schema = get_model_schema("auth", "user")
    assert "relations" in schema
    assert "incoming" in schema
    names = {f["name"] for f in schema["fields"]}
    assert "username" in names
    assert "email" in names


def test_export_mermaid_contains_erdiagram() -> None:
    md = export_schema_mermaid()
    assert "erDiagram" in md
"@

    Write-TextFile -Path (Join-Path $panelDir "tests\test_query.py") -Content @'
"""Tests execution requetes SQL lecture seule."""

import json

import pytest

from apps.admin_panel.selectors import AdminQueryError, validate_readonly_sql


def test_validate_rejects_empty() -> None:
    with pytest.raises(AdminQueryError, match="vide"):
        validate_readonly_sql("   ")


def test_validate_rejects_delete() -> None:
    with pytest.raises(AdminQueryError, match="lecture seule"):
        validate_readonly_sql("DELETE FROM auth_user")


def test_validate_rejects_multi_statement() -> None:
    with pytest.raises(AdminQueryError, match="Une seule"):
        validate_readonly_sql("SELECT 1; SELECT 2")


@pytest.mark.django_db
def test_execute_select_returns_rows(api_client_superuser) -> None:
    response = api_client_superuser.post(
        "/api/admin/query/",
        data=json.dumps({"sql": "SELECT 1 AS num"}),
        content_type="application/json",
    )
    assert response.status_code == 200
    data = response.json()
    assert data["columns"] == ["num"]
    assert data["rows"] == [{"num": 1}]


@pytest.mark.django_db
def test_execute_rejects_insert(api_client_superuser) -> None:
    response = api_client_superuser.post(
        "/api/admin/query/",
        data=json.dumps({"sql": "INSERT INTO auth_user (username) VALUES ('x')"}),
        content_type="application/json",
    )
    assert response.status_code == 400
    assert "lecture seule" in response.json()["detail"]
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

    Write-TextFile -Path (Join-Path $scssRoot "base\_root.scss") -Content (Get-BrandCharteTokensScss)

    $pagesDir = Join-Path $scssRoot "pages"
    New-Item -ItemType Directory -Path $pagesDir -Force | Out-Null
    Write-TextFile -Path (Join-Path $pagesDir "_home.scss") -Content (Get-BrandHomePageScss)
    Write-TextFile -Path (Join-Path $scssRoot "components\_buttons.scss") -Content (Get-BrandButtonsScss)

    Write-TextFile -Path (Join-Path $scssRoot "main.scss") -Content @'
@use "base/root";
@use "components/buttons";
@use "pages/home";

body {
  font-family: var(--font-sans);
  background: var(--color-bg);
  color: var(--color-text);
  margin: 0;
}
'@

    New-Item -ItemType Directory -Path (Join-Path $Root "static\css") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Root "static\js") -Force | Out-Null
    Write-TextFile -Path (Join-Path $Root "static\js\.gitkeep") -Content "`n"
    Invoke-ScssCompile -Root $Root
}

function Install-AdminDataStudioTemplates {
    param([Parameter(Mandatory)][string]$FeRoot)

    $srcRoot = Join-Path $PSScriptRoot "templates\admin-data-studio"
    if (-not (Test-Path -LiteralPath $srcRoot)) {
        throw "Templates DataStudio introuvables : $srcRoot"
    }
    Get-ChildItem -Path $srcRoot -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($srcRoot.Length + 1)
        $dest = Join-Path $FeRoot $rel
        $destDir = Split-Path -Parent $dest
        if ($destDir -and -not (Test-Path -LiteralPath $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        Write-TextFile -Path $dest -Content ([System.IO.File]::ReadAllText($_.FullName))
    }
}

function New-AdminFrontendScaffold {
    param(
        [Parameter(Mandatory)][string]$FeRoot,
        [Parameter(Mandatory)][string]$AppName
    )

    $adminApp = Join-Path $FeRoot "src\app\admin"
    $loginApp = Join-Path $FeRoot "src\app\login"
    $lib = Join-Path $FeRoot "src\lib"
    $adminStyles = Join-Path $FeRoot "src\styles\admin"
    foreach ($d in @($adminApp, $loginApp, $lib, $adminStyles)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }

    Install-AdminDataStudioTemplates -FeRoot $FeRoot

    Write-TextFile -Path (Join-Path $lib "schema-types.ts") -Content @'
export type SchemaNode = {
  id: string;
  label: string;
  app_label: string;
  model_name: string;
};

export type SchemaEdge = {
  from: string;
  to: string;
  type: string;
  field: string;
};

export type GlobalSchema = {
  nodes: SchemaNode[];
  edges: SchemaEdge[];
};

export type ModelField = {
  name: string;
  type: string;
  nullable: boolean;
  unique: boolean;
  editable?: boolean;
  blank?: boolean;
  primary_key?: boolean;
  auto_increment?: boolean;
  required_on_create?: boolean;
  default?: string | number | boolean | null;
  relation?: string;
  related_model?: string;
};

export type ModelRelation = {
  field: string;
  type: string;
  app_label?: string;
  model_name?: string;
  target_id?: string;
  from_app_label?: string;
  from_model_name?: string;
  from_id?: string;
};

export type ModelSchema = {
  app_label: string;
  model_name: string;
  table: string;
  fields: ModelField[];
  relations: ModelRelation[];
  incoming: ModelRelation[];
};
'@

    Write-TextFile -Path (Join-Path $adminStyles "admin.scss") -Content (Get-BrandAdminScss)

    $schemaDir = Join-Path $adminApp "schema"
    New-Item -ItemType Directory -Path $schemaDir -Force | Out-Null
    Write-TextFile -Path (Join-Path $schemaDir "page.tsx") -Content @'
import { redirect } from "next/navigation";

export default function AdminSchemaRedirectPage() {
  redirect("/admin?view=diagram");
}
'@

    $modelSchemaDir = Join-Path $schemaDir "[app]"
    New-Item -ItemType Directory -Path (Join-Path $modelSchemaDir "[model]") -Force | Out-Null
    Write-TextFile -Path (Join-Path $modelSchemaDir "[model]\page.tsx") -Content @'
import { redirect } from "next/navigation";

type PageProps = {
  params: Promise<{ app: string; model: string }>;
};

export default async function AdminModelSchemaRedirectPage({ params }: PageProps) {
  const { app, model } = await params;
  redirect(`/admin?table=${app}.${model}&view=structure`);
}
'@

    $modelsDir = Join-Path $adminApp "models"
    New-Item -ItemType Directory -Path (Join-Path $modelsDir "[app]\[model]") -Force | Out-Null
    Write-TextFile -Path (Join-Path $modelsDir "[app]\[model]\page.tsx") -Content @'
import { redirect } from "next/navigation";

type PageProps = {
  params: Promise<{ app: string; model: string }>;
};

export default async function AdminModelRedirectPage({ params }: PageProps) {
  const { app, model } = await params;
  redirect(`/admin?table=${app}.${model}&view=data`);
}
'@

}

function New-NextJsFrontend {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ProjectSlug,
        [Parameter(Mandatory)][string]$AppName
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
  "packageManager": "pnpm@9.15.9",
  "scripts": {
    "dev": "next dev --hostname 0.0.0.0 -p 3000",
    "build": "next build",
    "start": "next start -H 0.0.0.0 -p 3000",
    "lint": "next lint"
  },
  "dependencies": {
    "@dagrejs/dagre": "^1.1.4",
    "@xyflow/react": "^12.6.0",
    "lucide-react": "^0.469.0",
    "next": "^15.1.0",
    "react": "^19.0.0",
    "react-dom": "^19.0.0",
    "react-resizable-panels": "^2.1.7",
    "html-to-image": "^1.11.11"
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

    Write-TextFile -Path (Join-Path $fe ".npmrc") -Content @'
# Docker / CI : pas de prompt interactif (purge node_modules)
confirm-modules-purge=false
'@

    New-Item -ItemType Directory -Path (Join-Path $fe "public") -Force | Out-Null
    Write-TextFile -Path (Join-Path $fe "public\.gitkeep") -Content "`n"

    Write-TextFile -Path (Join-Path $fe "next.config.ts") -Content @'
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "standalone",
  allowedDevOrigins: ["127.0.0.1", "localhost"],
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

    $pagesStyleDir = Join-Path $stylesDir "pages"
    New-Item -ItemType Directory -Path $pagesStyleDir -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $stylesDir "components") -Force | Out-Null

    Write-TextFile -Path (Join-Path $stylesDir "_tokens.scss") -Content (Get-BrandCharteTokensScss)
    Write-TextFile -Path (Join-Path $pagesStyleDir "_home.scss") -Content (Get-BrandHomePageScss)
    Write-TextFile -Path (Join-Path $stylesDir "components\_buttons.scss") -Content (Get-BrandButtonsScss)

    Write-TextFile -Path (Join-Path $stylesDir "globals.scss") -Content @'
@use "tokens";
@use "components/buttons";
@use "pages/home";

* {
  box-sizing: border-box;
}

body {
  margin: 0;
  font-family: var(--font-sans);
  background: var(--color-bg);
  color: var(--color-text);
}

code {
  padding: 0.125rem 0.375rem;
  border-radius: var(--radius-md);
  border: 1px solid color-mix(in srgb, var(--primary-color) 35%, var(--color-border));
  background: color-mix(in srgb, var(--primary-color) 8%, var(--color-surface));
  color: var(--accent-color);
  font-size: 0.875em;
}
'@

    Write-TextFile -Path (Join-Path $appDir "layout.tsx") -Content @'
import type { Metadata } from "next";
import "@/styles/globals.scss";

export const metadata: Metadata = {
  title: "App",
  description: "Frontend Next.js - API Django Ninja",
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
import Link from "next/link";

const apiUrl = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8000";

export default function HomePage() {
  return (
    <main className="page-home">
      <div className="page-home__bg" aria-hidden="true">
        <span className="page-home__orb page-home__orb--1" />
        <span className="page-home__orb page-home__orb--2" />
      </div>
      <div className="page-home__inner">
        <header className="page-home__hero">
          <p className="page-home__eyebrow">Django · uv · Next.js</p>
          <h1 className="page-home__title">Votre stack, en or et noir</h1>
          <p className="page-home__lead">
            Interface produit et DataStudio admin. API metier :{" "}
            <code>{apiUrl}</code>
          </p>
          <div className="page-home__actions">
            <Link href="/admin" className="btn btn--primary">
              Administration
            </Link>
            <Link href="/login" className="btn btn--secondary">
              Connexion
            </Link>
          </div>
        </header>
        <section className="page-home__grid">
          <article className="page-home__card">
            <h2 className="page-home__card-title">API Django</h2>
            <p className="page-home__card-text">
              Service Layer, Django Ninja et persistance PostgreSQL.
            </p>
          </article>
          <article className="page-home__card">
            <h2 className="page-home__card-title">DataStudio</h2>
            <p className="page-home__card-text">
              Schema, relations FK et CRUD sur vos modeles.
            </p>
          </article>
          <article className="page-home__card">
            <h2 className="page-home__card-title">Docker</h2>
            <p className="page-home__card-text">
              Stack locale compose : backend, frontend et base.
            </p>
          </article>
        </section>
      </div>
    </main>
  );
}
'@

    Write-TextFile -Path (Join-Path $fe ".env.example") -Content @"
NEXT_PUBLIC_API_URL=http://localhost:8000
# Server Components (fetch Django depuis le conteneur Next) :
# Stack full Docker (defaut compose) :
# API_INTERNAL_URL=http://web:8000
# Hybride (Django sur l'hote, Next dans Docker) :
# API_INTERNAL_URL=http://host.docker.internal:8000
"@

    Write-TextFile -Path (Join-Path $fe ".env.local") -Content @"
NEXT_PUBLIC_API_URL=http://localhost:8000
"@

    Write-TextFile -Path (Join-Path $fe ".gitignore") -Content @'
node_modules/
.next/
out/
.env*.local
'@

    Write-TextFile -Path (Join-Path $fe ".dockerignore") -Content @'
node_modules/
.next/
out/
.git/
.env*.local
'@

    Write-TextFile -Path (Join-Path $fe "Dockerfile") -Content @'
# syntax=docker/dockerfile:1
FROM node:22-alpine AS deps
WORKDIR /app
RUN apk add --no-cache libc6-compat
RUN corepack enable && corepack prepare pnpm@9.15.9 --activate
COPY package.json .npmrc ./
COPY pnpm-lock.yaml* ./
RUN --mount=type=cache,id=pnpm-store,target=/root/.local/share/pnpm/store \
    sh -c "if [ -f pnpm-lock.yaml ]; then pnpm install --frozen-lockfile; else pnpm install; fi"

FROM deps AS dev
ENV CI=true
EXPOSE 3000
CMD ["pnpm", "dev"]

FROM deps AS builder
COPY . .
ARG NEXT_PUBLIC_API_URL=http://localhost:8000
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL
RUN pnpm build

FROM node:22-alpine AS runner
WORKDIR /app
RUN apk add --no-cache libc6-compat
ENV NODE_ENV=production
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public ./public
EXPOSE 3000
CMD ["node", "server.js"]
'@

    $feScripts = Join-Path $fe "scripts"
    New-Item -ItemType Directory -Path $feScripts -Force | Out-Null
    Write-TextFile -Path (Join-Path $feScripts "install-deps.cmd") -Content @'
@echo off
setlocal
cd /d "%~dp0.."
set CI=true
set FORCE_COLOR=0
set NO_COLOR=1
if exist "%ProgramFiles%\nodejs\pnpm.cmd" (
  "%ProgramFiles%\nodejs\pnpm.cmd" install --reporter=append-only
) else (
  call pnpm.cmd install --reporter=append-only
)
exit /b %ERRORLEVEL%
'@

    New-AdminFrontendScaffold -FeRoot $fe -AppName $AppName
}

function New-DockerStack {
    param(
        [Parameter(Mandatory)][string]$Root,
        [int]$PostgresHostPort = 5433,
        [bool]$HasFrontend = $true
    )

    $scriptsDir = Join-Path $Root "scripts"
    New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null

    Write-TextFile -Path (Join-Path $scriptsDir "docker-web-dev.sh") -Content @'
#!/bin/sh
# Entree Docker dev backend : attente db, migrations, runserver (evite $ dans compose.yml).
set -e
cd /app
echo "Attente DNS + PostgreSQL (service db)..."
attempt=0
max=60
while [ "$attempt" -lt "$max" ]; do
  if getent hosts db >/dev/null 2>&1; then
    break
  fi
  attempt=$((attempt + 1))
  sleep 2
done
if [ "$attempt" -ge "$max" ]; then
  echo "ERREUR: impossible de resoudre l'hote db sur le reseau Docker." >&2
  exit 1
fi
sleep 2
uv sync
attempt=0
while [ "$attempt" -lt "$max" ]; do
  if uv run python -c "import socket; s=socket.create_connection(('db',5432),3); s.close()"; then
    break
  fi
  attempt=$((attempt + 1))
  sleep 2
done
if [ "$attempt" -ge "$max" ]; then
  echo "ERREUR: PostgreSQL (db:5432) injoignable apres attente." >&2
  exit 1
fi
uv run python manage.py migrate --noinput
if [ -n "${DJANGO_SUPERUSER_USERNAME:-}" ] && [ -n "${DJANGO_SUPERUSER_PASSWORD:-}" ]; then
  export DJANGO_SUPERUSER_EMAIL="${DJANGO_SUPERUSER_EMAIL:-${DJANGO_SUPERUSER_USERNAME}@local.test}"
  uv run python manage.py createsuperuser --noinput || true
fi
exec uv run python manage.py runserver 0.0.0.0:8000
'@

    if ($HasFrontend) {
    $feScriptsDir = Join-Path $Root "frontend\scripts"
    New-Item -ItemType Directory -Path $feScriptsDir -Force | Out-Null
    Write-TextFile -Path (Join-Path $feScriptsDir "docker-entrypoint-dev.sh") -Content @'
#!/bin/sh
# Entree Docker dev frontend : deps dans l''image + reparation non interactive si volume vide.
set -e
export CI=true
cd /app
corepack enable
corepack prepare pnpm@9.15.9 --activate

pnpm_install_safe() {
  if [ -f pnpm-lock.yaml ]; then
    pnpm install --frozen-lockfile
  else
    echo "pnpm-lock.yaml absent - installation sans frozen-lockfile."
    echo "Conseil : cd frontend && pnpm install (puis commit pnpm-lock.yaml)."
    pnpm install
  fi
}

if [ ! -f node_modules/.modules.yaml ] || [ package.json -nt node_modules/.modules.yaml ]; then
  echo "Synchronisation node_modules..."
  pnpm_install_safe
elif [ ! -e node_modules/lucide-react ] && [ ! -e node_modules/.pnpm ]; then
  echo "node_modules incomplet - reinstallation pnpm..."
  pnpm_install_safe
fi

mkdir -p .next/cache .next/server .next/static
exec pnpm dev
'@

    Write-TextFile -Path (Join-Path $feScriptsDir "pnpm-docker.sh") -Content @'
#!/bin/sh
# Wrapper pnpm (shell interactif : docker compose exec frontend sh).
set -e
cd /app
corepack enable
corepack prepare pnpm@9.15.9 --activate
exec pnpm "$@"
'@
    }

    Write-TextFile -Path (Join-Path $scriptsDir "docker-web-prod.sh") -Content @'
#!/bin/sh
# Entree Docker prod backend : migrations puis Gunicorn.
set -e
cd /app
attempt=0
max=30
while [ "$attempt" -lt "$max" ]; do
  if getent hosts db >/dev/null 2>&1 && uv run python -c "import socket; s=socket.create_connection(('db',5432),3); s.close()"; then
    break
  fi
  attempt=$((attempt + 1))
  sleep 2
done
if [ "$attempt" -ge "$max" ]; then
  echo "ERREUR: PostgreSQL (db:5432) injoignable." >&2
  exit 1
fi
uv run python manage.py migrate --noinput
exec uv run gunicorn config.wsgi:application --bind 0.0.0.0:8000 --workers 2
'@

    Write-TextFile -Path (Join-Path $Root "Dockerfile") -Content @'
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS base
WORKDIR /app
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy
# Git requis : uv sync peut installer des deps depuis git+https://github.com/...
RUN apt-get update \
    && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

FROM base AS dev
COPY pyproject.toml uv.lock ./
RUN uv sync
EXPOSE 8000
CMD ["uv", "run", "python", "manage.py", "runserver", "0.0.0.0:8000"]

FROM base AS prod
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

    $corsOrigins = Get-CorsOrigins -HasFrontend $HasFrontend

    # Bloc unique @' : evite la fusion db: + image: sur une ligne (concat @" + @').
    $composeDev = @'
services:
  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: app
      POSTGRES_USER: app
      POSTGRES_PASSWORD: dev
    ports:
      - "POSTGRES_HOST_PORT:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app -d app"]
      interval: 5s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

  web:
    build:
      context: .
      dockerfile: Dockerfile
      target: dev
    command: ["/bin/sh", "scripts/docker-web-dev.sh"]
    volumes:
      - .:/app
      - backend_venv:/app/.venv
    environment:
      DJANGO_ENV: dev
      DJANGO_SETTINGS_MODULE: config.settings
      DJANGO_SECRET_KEY: dev-docker-only
      DJANGO_USE_POSTGRES: "1"
      DJANGO_DB_ENGINE: django.db.backends.postgresql
      DJANGO_DB_NAME: app
      DJANGO_DB_USER: app
      DJANGO_DB_PASSWORD: dev
      DJANGO_DB_HOST: db
      DJANGO_DB_PORT: "5432"
      CORS_ALLOWED_ORIGINS: CORS_ORIGINS_PLACEHOLDER
      CELERY_BROKER_URL: redis://redis:6379/0
      CELERY_RESULT_BACKEND: redis://redis:6379/0
    ports:
      - "8000:8000"
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test:
        [
          "CMD-SHELL",
          "uv run python -c \"import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/health/', timeout=3)\"",
        ]
      interval: 10s
      timeout: 5s
      retries: 6
      start_period: 120s
    restart: unless-stopped

  worker:
    build:
      context: .
      dockerfile: Dockerfile
      target: dev
    command: ["uv", "run", "celery", "-A", "config", "worker", "-l", "info"]
    volumes:
      - .:/app
      - backend_venv:/app/.venv
    environment:
      DJANGO_ENV: dev
      DJANGO_SETTINGS_MODULE: config.settings
      DJANGO_SECRET_KEY: dev-docker-only
      DJANGO_USE_POSTGRES: "1"
      DJANGO_DB_ENGINE: django.db.backends.postgresql
      DJANGO_DB_NAME: app
      DJANGO_DB_USER: app
      DJANGO_DB_PASSWORD: dev
      DJANGO_DB_HOST: db
      DJANGO_DB_PORT: "5432"
      CELERY_BROKER_URL: redis://redis:6379/0
      CELERY_RESULT_BACKEND: redis://redis:6379/0
    depends_on:
      redis:
        condition: service_healthy
      db:
        condition: service_healthy
    restart: unless-stopped

'@
    if ($HasFrontend) {
        $composeDev += @'
  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile
      target: dev
    extra_hosts:
      - "host.docker.internal:host-gateway"
    command: ["/bin/sh", "scripts/docker-entrypoint-dev.sh"]
    volumes:
      - ./frontend:/app
      - /app/node_modules
      - frontend_next:/app/.next
    environment:
      CI: "true"
      NEXT_PUBLIC_API_URL: http://localhost:8000
      API_INTERNAL_URL: ${API_INTERNAL_URL:-http://web:8000}
      HOSTNAME: "0.0.0.0"
    ports:
      - "3000:3000"
    depends_on:
      web:
        condition: service_healthy
    restart: unless-stopped

'@
    }

    if ($HasFrontend) {
        $composeDev += @'
volumes:
  pgdata:
  backend_venv:
  frontend_next:
'@
    } else {
        $composeDev += @'
volumes:
  pgdata:
  backend_venv:
'@
    }

    $composeDev = $composeDev -replace 'POSTGRES_HOST_PORT', [string]$PostgresHostPort
    $composeDev = $composeDev -replace 'CORS_ORIGINS_PLACEHOLDER', $corsOrigins

    Write-TextFile -Path (Join-Path $Root ".gitattributes") -Content @'
# Scripts shell : LF obligatoire pour Docker/Linux
*.sh text eol=lf
'@

    Write-TextFile -Path (Join-Path $Root "docker-compose.yml") -Content $composeDev

    if ($HasFrontend) {
        $composeProd = @'
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
    build:
      context: .
      dockerfile: Dockerfile
      target: prod
    command: ["/bin/sh", "scripts/docker-web-prod.sh"]
    environment:
      DJANGO_ENV: prod
      DJANGO_SECRET_KEY: ${DJANGO_SECRET_KEY:?required}
      DJANGO_ALLOWED_HOSTS: ${DJANGO_ALLOWED_HOSTS:?required}
      DJANGO_USE_POSTGRES: "1"
      DJANGO_DB_ENGINE: django.db.backends.postgresql
      DJANGO_DB_NAME: ${POSTGRES_DB:-app}
      DJANGO_DB_USER: ${POSTGRES_USER:-app}
      DJANGO_DB_PASSWORD: ${POSTGRES_PASSWORD:?required}
      DJANGO_DB_HOST: db
      CORS_ALLOWED_ORIGINS: ${CORS_ALLOWED_ORIGINS:-https://example.com}
    depends_on:
      db:
        condition: service_started
    ports:
      - "8000:8000"
    healthcheck:
      test:
        [
          "CMD-SHELL",
          "uv run python -c \"import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/health/', timeout=3)\"",
        ]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 90s

  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile
      target: runner
      args:
        NEXT_PUBLIC_API_URL: ${NEXT_PUBLIC_API_URL:-http://localhost:8000}
    environment:
      API_INTERNAL_URL: http://web:8000
      HOSTNAME: "0.0.0.0"
      PORT: "3000"
    ports:
      - "3000:3000"
    depends_on:
      web:
        condition: service_healthy

volumes:
  pgdata:
'@
    } else {
        $composeProd = @'
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
    build:
      context: .
      dockerfile: Dockerfile
      target: prod
    command: ["/bin/sh", "scripts/docker-web-prod.sh"]
    environment:
      DJANGO_ENV: prod
      DJANGO_SECRET_KEY: ${DJANGO_SECRET_KEY:?required}
      DJANGO_ALLOWED_HOSTS: ${DJANGO_ALLOWED_HOSTS:?required}
      DJANGO_USE_POSTGRES: "1"
      DJANGO_DB_ENGINE: django.db.backends.postgresql
      DJANGO_DB_NAME: ${POSTGRES_DB:-app}
      DJANGO_DB_USER: ${POSTGRES_USER:-app}
      DJANGO_DB_PASSWORD: ${POSTGRES_PASSWORD:?required}
      DJANGO_DB_HOST: db
      CORS_ALLOWED_ORIGINS: ${CORS_ALLOWED_ORIGINS:-https://example.com}
    depends_on:
      db:
        condition: service_started
    ports:
      - "8000:8000"
    healthcheck:
      test:
        [
          "CMD-SHELL",
          "uv run python -c \"import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/health/', timeout=3)\"",
        ]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 90s

volumes:
  pgdata:
'@
    }

    Write-TextFile -Path (Join-Path $Root "docker-compose.prod.yml") -Content $composeProd
}

function New-QualityTooling {
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
    from apps.admin_panel.auth import create_token_pair

    tokens = create_token_pair(user)
    response = api_client.get(
        "/api/admin/registry/",
        HTTP_AUTHORIZATION=f"Bearer {tokens['access']}",
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
'@
    } else {
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

function New-CursorProjectRules {
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

    $djangoUiRows = if ($HasFrontend) {
        ""
    } else {
        "| ``templates/`` | Templates Django (UI produit) |`n| ``static/scss/`` | SCSS 7-1 (UI produit) |`n"
    }
    $feRow = if ($HasFrontend) {
        "| ``frontend/`` | Next.js App Router + admin custom ``/admin`` (UI produit) |`n"
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

## Front Next.js
- UI produit dans ``frontend/`` : ``/admin``, ``/login`` (Flat High-End, SCSS + ``:root``).
- Django = API pure : aucun ``templates/`` ni ``static/scss`` custom (l'admin Django sert ses propres statics).
- Pas de HTMX. Pas de logique metier cote client.
- ``NEXT_PUBLIC_API_URL`` (navigateur) ; ``API_INTERNAL_URL`` (RSC Docker, defaut ``http://web:8000``).
"@
    } else {
        @"

## UI (Django uniquement)
- Pas de dossier ``frontend/`` : pages templates + SCSS sous ``templates/`` et ``static/scss/``.
"@
    }
    $adminSection = if ($HasCustomAdmin) {
        @"

## Admin custom (admin_panel)
- API ``/api/admin/`` + auth JWT ``/api/auth/`` pour DataStudio Next.js.
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
| ``config/`` | Settings Django (dev/qua/prod), urls, wsgi/asgi |
| ``apps/`` | Apps metier (Service Layer strict) |
$djangoUiRows$feRow$adminPanelRow| ``tests/`` | Pytest |
| ``docker-compose.yml`` / ``docker-compose.prod.yml`` | Dev local / prod |

## Apps Django
| App | Role |
|-----|------|
| ``apps.$AppName`` | App metier (modeles custom ; User = ``auth.User``) |
$feSection$adminSection
"@
    Write-TextFile -Path (Join-Path $cursorDir "app-structure.md") -Content $structure

    $umlFrontend = if ($HasFrontend) {
        @"
package "frontend" {
  [App Router]
  [admin UI]
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
}
package "apps" {
  package "$AppName" {
    [models]
  }
  package "auth" {
    [User]
  }
$umlAdminPanel
}
$umlFrontend
database "PostgreSQL" as db
[apps] --> db : ORM
@enduml
"@
    Write-TextFile -Path (Join-Path $cursorDir "app-architecture.uml") -Content $uml

    $agentsTitle = if ($HasFrontend) {
        "monorepo Django + Next.js"
    } elseif ($HasCustomAdmin) {
        "Django + admin_panel API (sans Next.js)"
    } else {
        "projet Django (admin natif, sans Next.js)"
    }
    Write-TextFile -Path (Join-Path $cursorDir "AGENTS.md") -Content @"
# Agents Cursor - $agentsTitle

## Lead par defaut
**@ProjectManager** - plan d'action, dispatch, Definition of Done.

## Matrice rapide
| Sujet | Agent |
|-------|--------|
| Service Layer, CBV, Django Ninja, MRO | @Architect (django-architect) |
| SCSS, tokens, BEM, admin Next | @UI-Engineer |
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
- Django Ninja pour API consommee par Next.js

## UI Django (legacy templates)
- Templates minimaux uniquement ; **pas de HTMX**
- Admin principal = Next.js ``frontend/src/app/admin/``

## UI Next.js (frontend/)
- Admin custom Flat High-End : ``/admin``, ``/login``
- SCSS + tokens ``:root`` (``src/styles/admin/``)
- CRUD/schema via API ``/api/admin/`` (stubs V1, V2 CRUD reel)
- **Tailwind interdit**

## Docker
- ``docker compose up --build`` (Django runserver + Next ``pnpm dev``)
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
- ``frontend/`` : UI produit + admin Next.js
- API admin : ``/api/admin/`` (``apps.admin_panel``)
- ``django-admin/`` : fallback dev si ``DJANGO_ADMIN_ENABLED=true``

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
.migrate_bootstrap.py
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
        [bool]$HasCustomAdmin,
        [bool]$HasFrontend,
        [bool]$HasDocker
    )
    $fe = if ($HasFrontend) { @"

## Frontend (Next.js)

L'init **ne demarre pas** Next.js : le port 3000 reste ferme tant que ``pnpm dev`` n'est pas lance.

``````powershell
# Option A : deux fenetres automatiques (recommande Windows)
.\scripts\dev-local.ps1

# Option B : manuel (2 terminaux)
cd frontend
pnpm install   # deja fait a l'init si Node/pnpm disponible
pnpm dev
``````

Puis ouvrir http://127.0.0.1:3000 (ou http://localhost:3000).
"@ } else { "" }

    $quickStart = if ($HasFrontend) {
        @"

``````powershell
cd <racine_projet>
uv sync
uv run python manage.py migrate

# Demarrer backend + frontend (obligatoire pour le port 3000) :
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

    $projectKind = if ($HasFrontend) { "Monorepo Django + uv + Next.js" } else { "Projet Django + uv (sans Next.js)" }
    $dk = if ($HasDocker) {
        if ($HasFrontend) {
            @"

## Docker (dev - db + web + frontend)
``````bash
docker compose up --build
``````

Production : ``docker compose -f docker-compose.prod.yml up --build``
"@
        } else {
            @"

## Docker (dev - db + web Django uniquement)
``````bash
docker compose up --build
``````

- API : http://localhost:8000
- Admin Django (dev) : http://localhost:8000/django-admin/

Production : ``docker compose -f docker-compose.prod.yml up --build``
"@
        }
    } else { "" }

    $urlsBlock = if ($HasFrontend) {
        @"

- Backend : http://localhost:8000
- Frontend : http://localhost:3000
- Admin DataStudio : http://localhost:3000/admin
- Login : http://localhost:3000/login (superuser Django uniquement)
"@
    } elseif ($HasCustomAdmin) {
        @"

- API : http://localhost:8000
- Admin Django (fallback dev) : http://localhost:8000/django-admin/
- API admin : http://localhost:8000/api/admin/
"@
    } else {
        @"

- API : http://localhost:8000
- Admin Django : http://localhost:8000/django-admin/
"@
    }

    $dockerUpHint = if ($HasFrontend) { "docker compose up          # web + frontend" } else { "docker compose up          # web uniquement" }

    $backendAdminLine = if ($HasCustomAdmin) {
        "Admin custom : ``apps.admin_panel`` (registry, schema, CRUD API) - modele par defaut ``auth.User``"
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

Cree a l'init (etape Superuser) ou via ``createsuperuser`` - compte **superuser** requis$(if ($HasFrontend) { " pour ``/login``" } else { " pour ``/django-admin/``" }).

## Backend

App metier : ``apps.$AppName``
$backendAdminLine

**Structure BDD** : ``models.py`` + migrations uniquement.

$fe

## Cursor

Voir ``.cursor/AGENTS.md`` et ``.cursor/skills/STACK.md``.
"@
    Write-TextFile -Path (Join-Path $Root "README.md") -Content $readme
}

function Test-ProjectStructure {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$AppName,
        [bool]$ExpectCustomAdmin,
        [bool]$ExpectFrontend,
        [bool]$ExpectDocker
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
        ".cursor\AGENTS.md",
        ".cursor\rules\00-project-stack.mdc"
    )
    if ($ExpectCustomAdmin) {
        $required += @(
            "apps\admin_panel\registry.py",
            "apps\admin_panel\api.py",
            "apps\admin_panel\schemas.py"
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
            "frontend\src\app\page.tsx",
            "frontend\src\app\admin\page.tsx",
            "frontend\src\app\login\page.tsx",
            "frontend\src\lib\admin-api-client.ts",
            "frontend\src\lib\admin-api-server.ts",
            "frontend\src\lib\auth-cookie-names.ts",
            "frontend\src\lib\schema-types.ts",
            "frontend\src\lib\admin-studio-types.ts",
            "frontend\src\lib\admin-studio-adapter.ts",
            "frontend\src\components\admin\DatabaseAdmin.tsx",
            "frontend\src\components\admin\AdminERDiagram.tsx",
            "frontend\src\components\admin\AdminDataTable.tsx",
            "frontend\src\components\admin\RowFormDialog.tsx",
            "frontend\src\styles\admin\data-studio.scss",
            "frontend\next.config.ts"
        )
    } else {
        $required += @(
            "templates\base.html",
            "static\scss\main.scss"
        )
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
            $required += "frontend\scripts\docker-entrypoint-dev.sh"
        }
    }
    foreach ($rel in $required) {
        $full = Join-Path $Root $rel
        if (-not (Test-Path -LiteralPath $full)) {
            throw "Structure incomplete, fichier manquant : $rel"
        }
    }
}

function Get-PnpmCliVersion {
    param([Parameter(Mandatory)][string]$WorkingDirectory)

    $pnpmPath = Resolve-NodeToolPath -Name "pnpm"
    if (-not $pnpmPath) { return $null }
    try {
        $psi = New-CliProcessStartInfo -ExePath $pnpmPath -ArgumentString "--version" -WorkingDirectory $WorkingDirectory
        $p = [System.Diagnostics.Process]::Start($psi)
        if (-not $p.WaitForExit(15000)) {
            try { $p.Kill() } catch {}
            return $null
        }
        if ($p.ExitCode -ne 0) { return $null }
        return ($p.StandardOutput.ReadToEnd().Trim())
    } catch {
        return $null
    }
}

function Ensure-PnpmVersion {
    param([Parameter(Mandatory)][string]$WorkingDirectory)

    $pnpmPath = Get-PreferredNodeCmdPath -Name "pnpm"
    if ($pnpmPath) {
        $ver = Get-PnpmCliVersion -WorkingDirectory $WorkingDirectory
        if ($ver) {
            Write-Host "     pnpm detecte : $ver" -ForegroundColor DarkGray
            return $true
        }
    }

    $corepackPath = Get-PreferredNodeCmdPath -Name "corepack"
    if ($corepackPath) {
        try {
            $corepackQuoted = '"' + $corepackPath.Replace('"', '""') + '"'
            Invoke-CmdBatchLogged -WorkingDirectory $WorkingDirectory `
                -CommandLine "$corepackQuoted prepare pnpm@9.15.9 --activate" -TimeoutSeconds 120 -Quiet
            if (Get-PnpmCliVersion -WorkingDirectory $WorkingDirectory) {
                return $true
            }
        } catch {
            Write-Host "     corepack prepare ignore : $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }

    $npmPath = Get-PreferredNodeCmdPath -Name "npm"
    if ($npmPath) {
        try {
            $npmQuoted = '"' + $npmPath.Replace('"', '""') + '"'
            Invoke-CmdBatchLogged -WorkingDirectory $WorkingDirectory `
                -CommandLine "$npmQuoted install -g pnpm@9.15.9" -TimeoutSeconds 180 -Quiet
            if (Get-PnpmCliVersion -WorkingDirectory $WorkingDirectory) {
                return $true
            }
        } catch {
            Write-Host "     npm install -g pnpm ignore : $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }

    return $false
}

function New-DevLocalScript {
    param(
        [Parameter(Mandatory)][string]$Root,
        [bool]$HasDocker = $true
    )

    $scriptsDir = Join-Path $Root "scripts"
    New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null

    $devScript = @'
# Demarre Django (8000) et Next.js (3000) dans deux fenetres PowerShell.
# Usage : .\scripts\dev-local.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$frontend = Join-Path $root 'frontend'

if (-not (Test-Path -LiteralPath (Join-Path $root 'manage.py'))) {
    Write-Error "manage.py introuvable. Lancez depuis la racine du projet genere."
}
if (-not (Test-Path -LiteralPath (Join-Path $frontend 'package.json'))) {
    Write-Error "frontend/package.json introuvable."
}

Write-Host 'Demarrage backend (uv run python manage.py runserver)...' -ForegroundColor Cyan
Start-Process powershell -ArgumentList @(
    '-NoExit', '-NoProfile', '-Command',
    ("Set-Location -LiteralPath '" + $root + "'; uv run python manage.py runserver 0.0.0.0:8000")
)

Write-Host 'Demarrage frontend (pnpm dev)...' -ForegroundColor Cyan
Start-Process powershell -ArgumentList @(
    '-NoExit', '-NoProfile', '-Command',
    ("Set-Location -LiteralPath '" + $frontend + "'; if (Get-Command pnpm -ErrorAction SilentlyContinue) { pnpm dev } else { npm run dev }")
)

Write-Host ''
Write-Host 'Serveurs en cours de demarrage :' -ForegroundColor Green
Write-Host '  Backend  : http://127.0.0.1:8000'
Write-Host '  Frontend : http://127.0.0.1:3000'
Write-Host '  Admin    : http://127.0.0.1:3000/admin'
Write-Host '  Login    : http://127.0.0.1:3000/login'
Write-Host ''
Write-Host 'Si le port 3000 reste inaccessible, verifiez la fenetre frontend (erreur pnpm/node).'
'@
    if ($HasDocker) {
        $devScript += @'

# Alternative Docker (db + web + frontend) :
#   docker compose up --build
# Puis http://127.0.0.1:3000 (attendre que le service frontend soit healthy)
'@
    }
    Write-TextFile -Path (Join-Path $scriptsDir "dev-local.ps1") -Content $devScript
}

function Install-FrontendDependencies {
    param(
        [Parameter(Mandatory)][string]$FrontendRoot,
        [int]$TimeoutSeconds = 900
    )

    $lockPath = Join-Path $FrontendRoot "pnpm-lock.yaml"
    $pnpmArgText = if (Test-Path -LiteralPath $lockPath) {
        "install --frozen-lockfile --reporter=append-only"
    } else {
        "install --reporter=append-only"
    }

    $null = Ensure-PnpmVersion -WorkingDirectory $FrontendRoot

    $pnpmPath = Get-PreferredNodeCmdPath -Name "pnpm"
    if ($pnpmPath) {
        try {
            Write-Host "     pnpm $pnpmArgText (via cmd.exe, peut prendre plusieurs minutes)..." -ForegroundColor DarkGray
            $pnpmQuoted = '"' + $pnpmPath.Replace('"', '""') + '"'
            Invoke-CmdBatchLogged -WorkingDirectory $FrontendRoot `
                -CommandLine "$pnpmQuoted $pnpmArgText" -TimeoutSeconds $TimeoutSeconds -Quiet `
                -ShowProgress -ProgressActivity "Installation dependances Next.js (pnpm)" `
                -ProgressEstimateSeconds ([math]::Min(600, [math]::Max(180, [int]($TimeoutSeconds / 2))))
            if (-not (Test-Path -LiteralPath $lockPath)) {
                Write-Host "     Avertissement : pnpm-lock.yaml absent apres install." -ForegroundColor DarkYellow
            }
            return "pnpm"
        } catch {
            Write-Host "     pnpm install ignore : $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }

    $npmPath = Get-PreferredNodeCmdPath -Name "npm"
    if ($npmPath) {
        try {
            Write-Host "     npm install (fallback, via cmd.exe)..." -ForegroundColor DarkYellow
            $npmQuoted = '"' + $npmPath.Replace('"', '""') + '"'
            Invoke-CmdBatchLogged -WorkingDirectory $FrontendRoot `
                -CommandLine "$npmQuoted install --no-fund --no-audit --loglevel=error" `
                -TimeoutSeconds $TimeoutSeconds -Quiet -ShowProgress `
                -ProgressActivity "Installation dependances Next.js (npm)" `
                -ProgressEstimateSeconds ([math]::Min(600, [math]::Max(180, [int]($TimeoutSeconds / 2))))
            return "npm"
        } catch {
            Write-Host "     npm install ignore : $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }

    Write-Host "     Installez les deps : cd frontend && pnpm install (ou Docker : docker compose up --build)." -ForegroundColor DarkYellow
    return $null
}

# --- Execution principale ---

$createdNewFolder = $false
$root = ""
$useCurrent = $UseCurrentFolder.IsPresent
$wantsNewFolder = $NewFolder.IsPresent

try {
    Write-PipelineBanner -Subtitle "Initialisation interactive"

    if (-not (Test-PythonIdentifier $AppName)) {
        throw "AppName invalide : lettres, chiffres, underscore uniquement."
    }
    if (-not (Resolve-ExecutablePath -Name "uv")) {
        throw "uv introuvable dans le PATH. https://docs.astral.sh/uv/"
    }
    if ($wantsNewFolder -and $useCurrent) {
        throw "Utilisez soit -NewFolder soit -UseCurrentFolder, pas les deux."
    }

    if (-not $NoInteractive.IsPresent -and -not $useCurrent -and -not $wantsNewFolder) {
        $wantsNewFolder = Read-YesNoPrompt -Prompt "Nouveau dossier projet ?" -DefaultYes:$false
        if ($wantsNewFolder) {
            $wantsNewFolder = $true
            $useCurrent = $false
        } else {
            $wantsNewFolder = $false
            $useCurrent = $true
        }
    }

    if ($NoInteractive.IsPresent -and -not $useCurrent -and -not $wantsNewFolder) {
        if (-not [string]::IsNullOrWhiteSpace($ProjectName)) {
            $wantsNewFolder = $true
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
                if (-not (Test-ValidProjectFolderName -Name $projectFolder)) {
                    Write-Host "  Nom invalide : utilisez un nom de dossier (pas une URL web)." -ForegroundColor DarkYellow
                    $projectFolder = ""
                }
            } while ([string]::IsNullOrWhiteSpace($projectFolder))
        } elseif (-not (Test-ValidProjectFolderName -Name $projectFolder)) {
            throw "Nom de dossier invalide : '$projectFolder' (pas une URL web, pas de \ / : * ? `" < > |)."
        }
        $parentPath = if ([string]::IsNullOrWhiteSpace($ParentPath)) {
            (Get-Location).Path
        } else {
            $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ParentPath)
        }
        if (-not (Test-Path -LiteralPath $parentPath)) {
            throw "Dossier parent introuvable : $parentPath"
        }

        $resolved = Get-AvailableProjectPath -ParentPath $parentPath -BaseName $projectFolder
        if ($resolved.Renamed) {
            Write-Host "  Dossier indisponible ou non vide: $(Join-Path $parentPath $projectFolder)" -ForegroundColor DarkYellow
            Write-Host "  Nom retenu automatiquement: $($resolved.Name)" -ForegroundColor DarkYellow
        }
        $projectFolder = $resolved.Name
        $root = $resolved.Path
        if (-not (Test-Path -LiteralPath $root)) {
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $createdNewFolder = $true
        } elseif (Test-DirectoryIsEmpty -Path $root) {
            $createdNewFolder = $true
        }
        Write-Host "  Nouveau dossier : $projectFolder" -ForegroundColor Green
        Write-Host "  $root" -ForegroundColor Green
    }

    $uvName = (Split-Path -Leaf $root) -replace '[^a-zA-Z0-9_]', '_'
    if ($uvName -match '^[0-9]') { $uvName = "_$uvName" }

    $wantsNextJs = $false
    if ($SkipFrontend.IsPresent -and $UseNextJs.IsPresent) {
        Write-Host "  Avertissement : -SkipFrontend et -UseNextJs ignores (-SkipFrontend prioritaire)." -ForegroundColor DarkYellow
        $wantsNextJs = $false
    } elseif ($SkipFrontend.IsPresent) {
        $wantsNextJs = $false
    } elseif ($UseNextJs.IsPresent) {
        $wantsNextJs = $true
    } elseif (-not $NoInteractive.IsPresent) {
        $wantsNextJs = Read-YesNoPrompt -Prompt "Utiliser Next.js pour l'UI DataStudio ?" -DefaultYes:$true
        if ($wantsNextJs) {
            Write-Host "  Frontend retenu : Next.js DataStudio (/admin, /login)" -ForegroundColor Cyan
        } else {
            Write-Host "  Frontend retenu : pas de frontend/ (UI Django templates + SCSS)" -ForegroundColor Cyan
        }
    } else {
        $wantsNextJs = $true
    }

    $wantsCustomAdmin = $true
    if ($SkipCustomAdmin.IsPresent -and $UseCustomAdmin.IsPresent) {
        Write-Host "  Avertissement : -SkipCustomAdmin et -UseCustomAdmin ignores (-SkipCustomAdmin prioritaire)." -ForegroundColor DarkYellow
        $wantsCustomAdmin = $false
    } elseif ($SkipCustomAdmin.IsPresent) {
        $wantsCustomAdmin = $false
    } elseif ($UseCustomAdmin.IsPresent) {
        $wantsCustomAdmin = $true
    } elseif (-not $NoInteractive.IsPresent) {
        $wantsCustomAdmin = Read-YesNoPrompt -Prompt "Utiliser l'admin custom (admin_panel + API /api/admin/) ?" -DefaultYes:$true
        if ($wantsCustomAdmin) {
            Write-Host "  Admin retenu : admin_panel + API /api/admin/" -ForegroundColor Cyan
        } else {
            Write-Host "  Admin retenu : django.contrib.admin (/django-admin/)" -ForegroundColor Cyan
        }
    } else {
        $wantsCustomAdmin = $true
    }

    if ($wantsNextJs -and -not $wantsCustomAdmin) {
        Write-Host "  Avertissement : Next.js DataStudio consomme l'API /api/admin/ - sans admin custom, /admin ne sera pas fonctionnel." -ForegroundColor DarkYellow
    }

    $doCustomAdmin = $wantsCustomAdmin
    $doFrontend = $wantsNextJs
    $doDocker = -not $SkipDocker.IsPresent

    # Total d'etapes calcule selon les options retenues (barre de progression exacte).
    # L'etape UI est unique : Next.js OU templates/SCSS Django (deja comptee dans le socle).
    $script:PipelineTotal = 8  # uv, config, app, UI, cursor, qualite, structure, migrate
    if ($doCustomAdmin) { $script:PipelineTotal++ }
    if ($doDocker) { $script:PipelineTotal += 2 }
    if (-not $SkipCreatesuperuser.IsPresent) { $script:PipelineTotal++ }

    Write-PipelineBanner -Subtitle "App: $AppName | Next.js: $doFrontend | Admin custom: $doCustomAdmin | Docker: $doDocker"

    Start-PipelineStep -Title "Environnement uv" -Detail "init + dependances runtime et dev"
    if (-not (Test-Path -LiteralPath (Join-Path $root "pyproject.toml"))) {
        Invoke-UvCommand -Arguments @("init", "--name", $uvName) -WorkingDirectory $root -Quiet
    }
    $pyDeps = @(
        "django", "django-ninja",
        "whitenoise", "django-cors-headers", "gunicorn", "psycopg[binary]"
    )
    if ($doCustomAdmin) {
        $pyDeps += "pyjwt"
    }
    if ($doDocker) {
        $pyDeps += "celery[redis]"
    }
    Invoke-UvCommand -Arguments (@("add") + $pyDeps) -WorkingDirectory $root -Quiet
    Invoke-UvCommand -Arguments @(
        "add", "--dev", "ruff", "pytest", "pytest-django", "mypy", "django-stubs"
    ) -WorkingDirectory $root -Quiet
    $mainPy = Join-Path $root "main.py"
    if (Test-Path -LiteralPath $mainPy) { Remove-Item -LiteralPath $mainPy -Force }
    Complete-PipelineStep -Message "pyproject.toml + uv.lock"

    Start-PipelineStep -Title "Configuration Django" -Detail "config/ + settings dev|qua|prod"
    New-DjangoConfigPackage -Root $root -AppName $AppName -HasCustomAdmin:$doCustomAdmin -HasFrontend:$doFrontend -HasDocker:$doDocker
    Complete-PipelineStep

    Start-PipelineStep -Title "Application metier" -Detail "apps/$AppName + Service Layer"
    New-Item -ItemType Directory -Path (Join-Path $root "apps") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root "apps\$AppName") -Force | Out-Null
    Write-TextFile -Path (Join-Path $root "apps\__init__.py") -Content @'
"""Applications metier du projet."""
'@
    Invoke-UvCommand -Arguments @(
        "run", "django-admin", "startapp", $AppName, "apps\$AppName"
    ) -WorkingDirectory $root -Quiet
    $appsPyPath = Join-Path $root "apps\$AppName\apps.py"
    if (Test-Path -LiteralPath $appsPyPath) {
        $appsPy = Get-Content -LiteralPath $appsPyPath -Raw -Encoding UTF8
        $appsPy = $appsPy.Replace("name = `"$AppName`"", "name = `"apps.$AppName`"")
        $appsPy = $appsPy.Replace("name = '$AppName'", "name = `"apps.$AppName`"")
        Write-TextFile -Path $appsPyPath -Content $appsPy
    }
    New-AppServiceLayer -Root $root -AppName $AppName -HasCustomAdmin:$doCustomAdmin -HasFrontend:$doFrontend
    if ($doDocker) {
        New-CoreCeleryFiles -Root $root -AppName $AppName
    }
    New-CoreModels -Root $root -AppName $AppName -HasCustomAdmin:$doCustomAdmin
    if (-not $doCustomAdmin) {
        New-DjangoNativeAdmin -Root $root -AppName $AppName
    }
    Complete-PipelineStep

    # UI exclusive : Next.js (frontend/) OU templates + SCSS Django, jamais les deux.
    if ($doFrontend) {
        Start-PipelineStep -Title "Frontend Next.js" -Detail "App Router + SCSS tokens (sans Tailwind)"
        New-NextJsFrontend -Root $root -ProjectSlug $uvName -AppName $AppName
        New-DevLocalScript -Root $root -HasDocker:$doDocker
        $pkgMgr = $null
        if (-not $SkipFrontendDeps.IsPresent) {
            try {
                $pkgMgr = Install-FrontendDependencies -FrontendRoot (Join-Path $root "frontend") `
                    -TimeoutSeconds $CommandTimeoutSeconds
            } catch {
                Write-Host "     deps frontend ignore : $($_.Exception.Message)" -ForegroundColor DarkYellow
                $pkgMgr = $null
            }
        } else {
            Write-Host "     (-SkipFrontendDeps) : pas de lockfile - le build Docker frontend sera plus lent." -ForegroundColor DarkYellow
        }
        Complete-PipelineStep -Message $(if ($pkgMgr) { "deps $pkgMgr + lockfile + scripts/dev-local.ps1" } else { "squelette Next.js + scripts/dev-local.ps1" })
    } else {
        Start-PipelineStep -Title "Templates et assets SCSS" -Detail "7-1 minimal (sans HTMX)"
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
  <header class="site-header">
    <span class="site-header__brand">Mon application</span>
  </header>
  <main class="layout-main">
    {% block content %}{% endblock %}
  </main>
  {% block extra_body %}{% endblock %}
</body>
</html>
'@
        New-StaticScssLayout -Root $root
        $contentMd = Join-Path $root "content\markdown"
        New-Item -ItemType Directory -Path $contentMd -Force | Out-Null
        Write-TextFile -Path (Join-Path $contentMd ".gitkeep") -Content "`n"
        Complete-PipelineStep
    }

    if ($doCustomAdmin) {
        Start-PipelineStep -Title "Admin panel API" -Detail "apps/admin_panel + registry + schema Django Ninja"
        New-Item -ItemType Directory -Path (Join-Path $root "apps\admin_panel") -Force | Out-Null
        Invoke-UvCommand -Arguments @(
            "run", "django-admin", "startapp", "admin_panel", "apps\admin_panel"
        ) -WorkingDirectory $root -Quiet
        $panelAppsPy = Join-Path $root "apps\admin_panel\apps.py"
        if (Test-Path -LiteralPath $panelAppsPy) {
            $panelApps = Get-Content -LiteralPath $panelAppsPy -Raw -Encoding UTF8
            $panelApps = $panelApps.Replace('name = "admin_panel"', 'name = "apps.admin_panel"')
            $panelApps = $panelApps.Replace("name = 'admin_panel'", 'name = "apps.admin_panel"')
            Write-TextFile -Path $panelAppsPy -Content $panelApps
        }
        New-AdminPanelBackend -Root $root -AppName $AppName
        Complete-PipelineStep
    } else {
        Write-Host "     (admin custom desactive - django.contrib.admin)" -ForegroundColor DarkYellow
    }

    if ($doDocker) {
        Start-PipelineStep -Title "Docker" -Detail "Dockerfile + compose dev/prod"
        $postgresHostPort = Find-AvailablePostgresHostPort
        Write-Host "     Port PostgreSQL hote : $postgresHostPort" -ForegroundColor DarkGray
        New-DockerStack -Root $root -PostgresHostPort $postgresHostPort -HasFrontend:$doFrontend
        Complete-PipelineStep

        Start-PipelineStep -Title "PostgreSQL (.env)" -Detail "base Django unique hote + Docker"
        Write-ProjectDotEnvForDocker -Root $root -PostgresHostPort $postgresHostPort -HasFrontend:$doFrontend
        try {
            Start-ComposeDatabaseService -Root $root -TimeoutSeconds 90
            $pgPortMsg = Get-ProjectPostgresHostPort -Root $root
            Complete-PipelineStep -Message "db sur localhost:$pgPortMsg"
        } catch {
            Write-Host "     $($_.Exception.Message)" -ForegroundColor DarkYellow
            Write-Host "     Demarrez plus tard : docker compose up -d db" -ForegroundColor DarkYellow
            Complete-PipelineStep -Message "db a demarrer manuellement"
        }
    } else {
        Write-Host "     (SkipDocker)" -ForegroundColor DarkYellow
    }

    Start-PipelineStep -Title "Regles Cursor et skills" -Detail "AGENTS.md, STACK.md, rule MDC"
    New-CursorProjectRules -Root $root -AppName $AppName -HasCustomAdmin:$doCustomAdmin -HasFrontend:$doFrontend
    Complete-PipelineStep

    Start-PipelineStep -Title "Qualite et documentation" -Detail "pytest, ruff, README, .gitignore"
    New-QualityTooling -Root $root -HasCustomAdmin:$doCustomAdmin
    New-RootGitignore -Root $root
    New-ProjectReadme -Root $root -AppName $AppName -HasCustomAdmin $doCustomAdmin -HasFrontend $doFrontend -HasDocker $doDocker
    $corsExample = Get-CorsOrigins -HasFrontend $doFrontend
    $nextEnvBlock = if ($doFrontend) {
        @"

# Next.js (frontend/.env.local)
# NEXT_PUBLIC_API_URL=http://localhost:8000
"@
    } else {
        ""
    }
    Write-TextFile -Path (Join-Path $root ".env.example") -Content @"
# Copier vers .env (ne jamais committer)

DJANGO_SETTINGS_MODULE=config.settings
DJANGO_ENV=dev
DJANGO_SECRET_KEY=change-me
CORS_ALLOWED_ORIGINS=$corsExample

# Superuser (init locale ou variables lues par docker-compose service web) :
# DJANGO_SUPERUSER_USERNAME=admin
# DJANGO_SUPERUSER_EMAIL=admin@local.test
# DJANGO_SUPERUSER_PASSWORD=change-me

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
$nextEnvBlock
"@
    Complete-PipelineStep

    Start-PipelineStep -Title "Verification structure" -Detail "fichiers obligatoires"
    Test-ProjectStructure -Root $root -AppName $AppName -ExpectCustomAdmin $doCustomAdmin -ExpectFrontend $doFrontend -ExpectDocker $doDocker
    Complete-PipelineStep

    Start-PipelineStep -Title "Migrations Django" -Detail "migrate initiale automatique"
    if ($SkipMigrate.IsPresent) {
        Write-Host "     Avertissement: -SkipMigrate detecte, migration ignoree." -ForegroundColor DarkYellow
        Complete-PipelineStep -Message "skipped"
    } else {
        $dbLabel = if (Test-ProjectDotEnvUsesPostgres -Root $root) {
            $pgPortLabel = Get-ProjectPostgresHostPort -Root $root
            "PostgreSQL localhost:$pgPortLabel (.env)"
        } else {
            "SQLite"
        }
        $needsMakemigrations = Test-AppDefinesModels -Root $root -AppName $AppName
        if ($needsMakemigrations) {
            Write-Host "     makemigrations $AppName + migrate ($dbLabel)" -ForegroundColor DarkGray
        } else {
            Write-Host "     migrate uniquement ($dbLabel) - auth/admin Django, pas de modeles $AppName" -ForegroundColor DarkGray
        }
        if (Test-ProjectDotEnvUsesPostgres -Root $root) {
            if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
                throw "Docker requis pour PostgreSQL (.env) : installez Docker Desktop"
            }
            try {
                Ensure-ComposeDatabaseForDjango -Root $root -TimeoutSeconds 90 -ForMigrate
            } catch {
                throw @"
PostgreSQL indisponible pour les migrations : $($_.Exception.Message)
Verifiez Docker (docker compose ps) ou reinitialisez : docker compose down -v puis docker compose up -d db
"@
            }
        }
        Invoke-DjangoMigrationBootstrap -Root $root -AppName $AppName -RunMakemigrations:$needsMakemigrations
        Complete-PipelineStep -Message "migrations appliquees"
    }

    if (-not $SkipCreatesuperuser.IsPresent) {
        $suDetail = if ($doFrontend) {
            "createsuperuser pour /login Next.js"
        } elseif ($doCustomAdmin) {
            "createsuperuser pour API admin + /django-admin/"
        } else {
            "createsuperuser pour /django-admin/"
        }
        Start-PipelineStep -Title "Superuser Django" -Detail $suDetail
        try {
            Invoke-DjangoCreatesuperuser -Root $root -NoInteractive:$NoInteractive.IsPresent
            $suMsg = if (Test-ProjectDotEnvUsesPostgres -Root $root) {
                "compte admin (PostgreSQL)"
            } else {
                "compte admin (SQLite)"
            }
            Complete-PipelineStep -Message $suMsg
        } catch {
            Write-Host "     createsuperuser echoue : $($_.Exception.Message)" -ForegroundColor DarkYellow
            Write-Host "     Relancez : uv run python manage.py createsuperuser" -ForegroundColor DarkYellow
            Complete-PipelineStep -Message "a completer manuellement"
        }
    } else {
        Write-Host "     (-SkipCreatesuperuser)" -ForegroundColor DarkYellow
    }

    Write-PipelineSummary -Root $root -AppName $AppName -HasCustomAdmin $doCustomAdmin -HasFrontend $doFrontend -HasDocker $doDocker
}
catch {
    Write-Failure -Message $_.Exception.Message
    if ($createdNewFolder -and -not [string]::IsNullOrWhiteSpace($root) -and (Test-Path -LiteralPath $root)) {
        Write-Host "  Nettoyage du dossier partiel : $root" -ForegroundColor DarkYellow
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    } elseif (-not $createdNewFolder -and -not [string]::IsNullOrWhiteSpace($root)) {
        Write-Host "  Dossier conserve (pas de suppression auto)." -ForegroundColor DarkYellow
    }
}
finally {
    Restore-ShellPreferences
}

if ($script:ScaffoldFailed) {
    exit 1
}
