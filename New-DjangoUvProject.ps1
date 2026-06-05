#Requires -Version 5.1
<#
.SYNOPSIS
  Cree un monorepo Django + uv + Next.js + Docker + admin custom Next.js.

.DESCRIPTION
  Pipeline : uv, Django (Service Layer), apps/admin_panel (API /api/admin/),
  Next.js admin Flat High-End (/admin, /login), Docker Compose, Cursor rules, pytest.
  Sans HTMX. Django /admin optionnel en dev (DJANGO_ADMIN_ENABLED).

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

.PARAMETER SkipFrontendDeps
  N'installe pas les deps Node a l'init (pas de pnpm-lock.yaml ; Docker dev plus lent au 1er demarrage).

.PARAMETER SkipCreatesuperuser
  N'appelle pas manage.py createsuperuser apres les migrations.

.PARAMETER InstallFrontendDeps
  Obsolete : les deps front sont installees par defaut. Utiliser -SkipFrontendDeps pour ignorer.

.PARAMETER SkipMigrate
  Ignore la migration initiale Django.

.PARAMETER MigrateTimeoutSeconds
  Timeout de la migration initiale (defaut : 120s).

.PARAMETER CommandTimeoutSeconds
  Timeout des commandes uv (defaut : 900s).

.PARAMETER NoInteractive
  Desactive les questions interactives (equivalent -NewFolder si ProjectName fourni).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\New-DjangoUvProject.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\New-DjangoUvProject.ps1 -NewFolder mon_site -AppName core -NoInteractive
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\New-DjangoUvProject.ps1 -NewFolder mon_site -ParentPath E:\Projets -NoInteractive
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
    [switch]$InstallFrontendDeps,
    [switch]$SkipFrontendDeps,
    [switch]$SkipCreatesuperuser,
    [switch]$SkipMigrate,
    [switch]$NoInteractive,
    [int]$MigrateTimeoutSeconds = 120,
    [int]$CommandTimeoutSeconds = 900
)

$script:PreviousErrorActionPreference = $ErrorActionPreference
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $script:PreviousNativeCommandErrorPreference = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
}
$script:ScaffoldFailed = $false
$script:PreviousNativeCommandErrorPreference = $null
$script:DbEnvKeys = @(
    "DJANGO_DB_HOST", "DJANGO_DB_ENGINE", "DJANGO_DB_NAME",
    "DJANGO_DB_USER", "DJANGO_DB_PASSWORD", "DJANGO_DB_PORT", "DJANGO_USE_POSTGRES"
)

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

    foreach ($composeName in @("docker-compose.yml", "docker-compose.dev.yml")) {
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

function Test-ComposeDatabaseAcceptsConnections {
    param([Parameter(Mandatory)][string]$Root)

    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    Push-Location -LiteralPath $Root
    try {
        & docker compose exec -T db pg_isready -U app -d app 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            return $false
        }
        $env:PGPASSWORD = "dev"
        & docker compose exec -T -e PGPASSWORD=dev db psql -U app -d app -c "SELECT 1" 2>$null | Out-Null
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
        if ($isDbUp -and (Test-ComposeDatabaseAcceptsConnections -Root $Root)) {
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
        [int]$TimeoutSeconds = 60
    )

    if (Test-ComposeDatabaseAcceptsConnections -Root $Root) {
        $hostPort = Get-ProjectPostgresHostPort -Root $Root
        Write-Host "     PostgreSQL deja operationnel (localhost:$hostPort)" -ForegroundColor DarkGray
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
        [int]$PostgresHostPort = 5433
    )

    $content = @"
# Genere par New-DjangoUvProject.ps1 - PostgreSQL = base Django unique (hote + Docker)

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
CORS_ALLOWED_ORIGINS=http://localhost:3000

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
        $readyPort = Get-ProjectPostgresHostPort -Root $Root
        Write-Host "     PostgreSQL deja pret (localhost:$readyPort)" -ForegroundColor DarkGray
        return
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
            if (Test-ComposeDatabaseAcceptsConnections -Root $Root) {
                break
            }
            Start-Sleep -Seconds 2
        }
        if (-not (Test-ComposeDatabaseAcceptsConnections -Root $Root)) {
            throw "PostgreSQL (service db) non pret apres ${TimeoutSeconds}s"
        }
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

function Invoke-DjangoManage {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $pythonExe = Join-Path $Root ".venv\Scripts\python.exe"
    if (-not (Test-Path -LiteralPath $pythonExe)) {
        throw "Python venv introuvable. Lancez d'abord: uv sync"
    }

    $savedEnv = @{}
    $usePostgresEnv = Test-ProjectDotEnvUsesPostgres -Root $Root
    if ($usePostgresEnv) {
        Import-ProjectDotEnv -Root $Root
    } else {
        foreach ($key in $script:DbEnvKeys) {
            $item = Get-Item -Path "Env:$key" -ErrorAction SilentlyContinue
            if ($null -ne $item) {
                $savedEnv[$key] = $item.Value
                Remove-Item -Path "Env:$key" -ErrorAction SilentlyContinue
            }
        }
    }

    try {
        $env:DJANGO_ENV = "dev"
        $env:DJANGO_SETTINGS_MODULE = "config.settings"
        Invoke-NativeCli -Exe $pythonExe -Arguments (@("manage.py") + $Arguments) `
            -WorkingDirectory $Root -Quiet
    } finally {
        if (-not $usePostgresEnv) {
            foreach ($key in $script:DbEnvKeys) {
                Remove-Item -Path "Env:$key" -ErrorAction SilentlyContinue
            }
            foreach ($key in $savedEnv.Keys) {
                Set-Item -Path "Env:$key" -Value $savedEnv[$key]
            }
        }
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
        Write-Host "    pnpm dev   # deps deja installees a l'init si lockfile present"
    }
    if ($HasDocker) {
        Write-Host ""
        Write-Host "  Docker (stack complete) :" -ForegroundColor White
        Write-Host "    cd `"$Root`""
        Write-Host "    `$env:DOCKER_BUILDKIT=1; docker compose up --build"
        Write-Host "    (deps front au build ; demarrage conteneur rapide)"
    }
    Write-Host ""
    Write-Host "  Admin DataStudio : http://localhost:3000/login (superuser Django)" -ForegroundColor DarkGray
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

function Get-BrandCharteTokensScss {
    @'
:root {
  --color-bg: #080808;
  --color-text: #f5efe3;
  --color-text-muted: #a89a72;
  --color-border: #2e2a1c;
  --color-surface: #11100c;

  --primary-color: #b8860b;
  --primary-color-hover: #d4af37;
  --primary-color-active: #96700a;
  --primary-color-on: #080808;

  --secondary-color: #1a1812;
  --secondary-color-hover: #262218;
  --secondary-color-active: #12100c;
  --secondary-color-on: #d4af37;

  --tertiary-color: #c9a227;
  --tertiary-color-hover: #e0bc42;
  --tertiary-color-active: #a68518;
  --tertiary-color-on: #080808;

  --accent-color: #e8c547;
  --accent-color-hover: #f2d96a;
  --accent-color-active: #c9a227;
  --accent-color-on: #080808;

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

.page-home__hero {
  display: flex;
  flex-direction: column;
  gap: var(--space-4);
  padding: var(--space-8);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  background: linear-gradient(
    135deg,
    color-mix(in srgb, var(--primary-color) 18%, var(--color-surface)),
    color-mix(in srgb, var(--secondary-color) 12%, var(--color-surface))
  );
}

.page-home__eyebrow {
  margin: 0;
  font-size: 0.875rem;
  font-weight: 600;
  color: var(--secondary-color);
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

.page-home__title {
  margin: 0;
  font-size: clamp(1.75rem, 4vw, 2.5rem);
  line-height: 1.2;
}

.page-home__lead {
  margin: 0;
  max-width: 42rem;
  color: var(--color-text-muted);
}

.page-home__actions {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-3);
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
  background: var(--color-surface);
  border-top: 3px solid var(--primary-color);
}

.page-home__card-title {
  margin: 0 0 var(--space-2);
  color: var(--secondary-color);
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
  color: var(--secondary-color);
}

.layout-main {
  min-height: calc(100vh - 4rem);
}

.page-auth {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: var(--space-4);
  min-height: 100vh;
  padding: var(--space-8);
  background: linear-gradient(
    160deg,
    color-mix(in srgb, var(--primary-color) 14%, var(--color-bg)),
    var(--color-bg)
  );
}

.page-auth__title {
  margin: 0;
  color: var(--secondary-color);
}

.page-auth__form {
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
  width: min(24rem, 100%);
}

.page-auth__label {
  font-size: var(--text-sm);
  color: var(--color-text-muted);
}

.page-auth__input {
  width: 100%;
  padding: var(--space-2) var(--space-3);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  background: var(--color-surface);
  color: var(--color-text);
}

.page-auth__error {
  margin: 0;
  color: var(--danger-color);
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

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory)][string]$Exe,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [switch]$Quiet,
        [int]$TimeoutSeconds = 0,
        [hashtable]$EnvironmentOverrides = @{}
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
    foreach ($key in $EnvironmentOverrides.Keys) {
        $value = [string]$EnvironmentOverrides[$key]
        if ([string]::IsNullOrEmpty($value)) {
            if ($psi.EnvironmentVariables.ContainsKey($key)) {
                [void]$psi.EnvironmentVariables.Remove($key)
            }
        } else {
            $psi.EnvironmentVariables[$key] = $value
        }
    }
    $p = [System.Diagnostics.Process]::Start($psi)
    $stdoutBuilder = New-Object System.Text.StringBuilder
    $stderrBuilder = New-Object System.Text.StringBuilder
    $outHandler = [System.Diagnostics.DataReceivedEventHandler]{
        param($sender, $args)
        if ($null -ne $args.Data) {
            [void]$stdoutBuilder.AppendLine($args.Data)
        }
    }
    $errHandler = [System.Diagnostics.DataReceivedEventHandler]{
        param($sender, $args)
        if ($null -ne $args.Data) {
            [void]$stderrBuilder.AppendLine($args.Data)
        }
    }
    $p.add_OutputDataReceived($outHandler)
    $p.add_ErrorDataReceived($errHandler)
    $p.BeginOutputReadLine()
    $p.BeginErrorReadLine()
    if ($TimeoutSeconds -gt 0) {
        $timedOut = -not $p.WaitForExit($TimeoutSeconds * 1000)
        if ($timedOut) {
            try { $p.Kill() } catch {}
            throw "Timeout (${TimeoutSeconds}s) : $Exe $($psi.Arguments)"
        }
    } else {
        $p.WaitForExit()
    }
    Start-Sleep -Milliseconds 150
    $out = $stdoutBuilder.ToString()
    $err = $stderrBuilder.ToString()
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

function Invoke-NativeCli {
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
    if (-not $Quiet) {
        Write-Host "     > $Exe $($Arguments -join ' ')" -ForegroundColor DarkGray
    }
    Push-Location -LiteralPath $WorkingDirectory
    try {
        & $exePath @Arguments
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

function Invoke-DjangoMigrate {
    param(
        [Parameter(Mandatory)][string]$Root,
        [int]$TimeoutSeconds
    )
    $pythonExe = Join-Path $Root ".venv\Scripts\python.exe"
    if (-not (Test-Path -LiteralPath $pythonExe)) {
        throw "Python venv introuvable. Lancez d'abord: uv sync"
    }

    $savedEnv = @{}
    $usePostgresEnv = Test-ProjectDotEnvUsesPostgres -Root $Root
    if ($usePostgresEnv) {
        Import-ProjectDotEnv -Root $Root
    } else {
        foreach ($key in $script:DbEnvKeys) {
            $item = Get-Item -Path "Env:$key" -ErrorAction SilentlyContinue
            if ($null -ne $item) {
                $savedEnv[$key] = $item.Value
                Remove-Item -Path "Env:$key" -ErrorAction SilentlyContinue
            }
        }
    }

    try {
        $env:DJANGO_ENV = "dev"
        $env:DJANGO_SETTINGS_MODULE = "config.settings"
        Invoke-NativeCli -Exe $pythonExe -Arguments @(
            "manage.py", "migrate", "--noinput", "--verbosity", "1"
        ) -WorkingDirectory $Root -Quiet
    } finally {
        if (-not $usePostgresEnv) {
            foreach ($key in $script:DbEnvKeys) {
                Remove-Item -Path "Env:$key" -ErrorAction SilentlyContinue
            }
            foreach ($key in $savedEnv.Keys) {
                Set-Item -Path "Env:$key" -Value $savedEnv[$key]
            }
        }
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
    $usePostgresEnv = Test-ProjectDotEnvUsesPostgres -Root $Root
    if ($usePostgresEnv) {
        Import-ProjectDotEnv -Root $Root
    } else {
        foreach ($key in $script:DbEnvKeys) {
            $item = Get-Item -Path "Env:$key" -ErrorAction SilentlyContinue
            if ($null -ne $item) {
                $savedEnv[$key] = $item.Value
                Remove-Item -Path "Env:$key" -ErrorAction SilentlyContinue
            }
        }
    }

    try {
        $env:DJANGO_ENV = "dev"
        $env:DJANGO_SETTINGS_MODULE = "config.settings"

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
        $skip = (Read-Host "Creer un superuser maintenant ? (O/n)").Trim()
        if ($skip -match '^[Nn]') {
            Write-Host "     createsuperuser ignore - plus tard : uv run python manage.py createsuperuser" -ForegroundColor DarkYellow
            return
        }

        Invoke-NativeCli -Exe $pythonExe -Arguments @(
            "manage.py", "createsuperuser"
        ) -WorkingDirectory $Root
    } finally {
        if (-not $usePostgresEnv) {
            foreach ($key in $script:DbEnvKeys) {
                Remove-Item -Path "Env:$key" -ErrorAction SilentlyContinue
            }
            foreach ($key in $savedEnv.Keys) {
                Set-Item -Path "Env:$key" -Value $savedEnv[$key]
            }
        }
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
    "apps.admin_panel",
]

# Admin Django natif : fallback dev uniquement (desactive en prod par defaut)
DJANGO_ADMIN_ENABLED = os.environ.get("DJANGO_ADMIN_ENABLED", "false").lower() in (
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
    "DEFAULT_AUTHENTICATION_CLASSES": [
        "rest_framework_simplejwt.authentication.JWTAuthentication",
    ],
    "DEFAULT_PERMISSION_CLASSES": [
        "rest_framework.permissions.IsAuthenticated",
    ],
}

from datetime import timedelta

SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(hours=8),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=1),
    "AUTH_HEADER_TYPES": ("Bearer",),
}

_cors = os.environ.get("CORS_ALLOWED_ORIGINS", "http://localhost:3000")
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

    Write-TextFile -Path (Join-Path $configDir "health.py") -Content @'
"""Sonde de disponibilite (Docker / load balancer)."""

from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView


class HealthCheckView(APIView):
    """GET /api/health/ - sans authentification."""

    permission_classes = [AllowAny]

    def get(self, request) -> Response:
        return Response({"status": "ok"})
'@

    $configUrls = @"
from django.conf import settings
from django.contrib import admin
from django.urls import include, path

from config.health import HealthCheckView

urlpatterns = [
    path("api/health/", HealthCheckView.as_view(), name="health"),
    path("api/auth/", include("apps.admin_panel.auth_urls")),
    path("api/admin/", include("apps.admin_panel.urls")),
    path("", include("apps.$AppName.urls")),
]

if getattr(settings, "DJANGO_ADMIN_ENABLED", False):
    urlpatterns.insert(0, path("django-admin/", admin.site.urls))
"@
    Write-TextFile -Path (Join-Path $configDir "urls.py") -Content $configUrls
}

function New-AppServiceLayer {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$AppName
    )

    $appDir = Join-Path $Root "apps\$AppName"
    New-Item -ItemType Directory -Path (Join-Path $appDir "templates\$AppName") -Force | Out-Null

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
    '''Page d'accueil minimale (legacy template).

    MRO:
    1. TemplateView.get -> rendu template $AppName/home.html
    '''

    template_name = "$AppName/home.html"
"@

    Write-TextFile -Path (Join-Path $appDir "templates\$AppName\home.html") -Content @'
{% extends "base.html" %}
{% block title %}Accueil{% endblock %}
{% block content %}
  <main class="page-home">
    <header class="page-home__hero">
      <p class="page-home__eyebrow">Django + uv + Next.js</p>
      <h1 class="page-home__title">Bienvenue sur votre application</h1>
      <p class="page-home__lead">
        UI produit et administration via Next.js. API metier exposee par Django/DRF.
      </p>
      <div class="page-home__actions">
        <a class="btn btn--primary" href="http://localhost:3000/admin">Administration</a>
        <a class="btn btn--secondary" href="http://localhost:3000/login">Connexion</a>
      </div>
    </header>
    <section class="page-home__grid">
      <article class="page-home__card">
        <h2 class="page-home__card-title">API Django</h2>
        <p class="page-home__card-text">Service Layer, DRF et migrations ORM.</p>
      </article>
      <article class="page-home__card">
        <h2 class="page-home__card-title">Admin custom</h2>
        <p class="page-home__card-text">Registry, schema et CRUD (roadmap V1-V3).</p>
      </article>
    </section>
  </main>
{% endblock %}
'@
}

function New-CoreModels {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$AppName
    )
    $modelsPath = Join-Path $Root "apps\$AppName\models.py"
    Write-TextFile -Path $modelsPath -Content @"
from __future__ import annotations

from django.db import models


class Transaction(models.Model):
    '''Exemple de model metier enregistre dans l'admin custom.'''

    label = models.CharField(max_length=120)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    currency = models.CharField(max_length=3, default="EUR")
    status = models.CharField(max_length=32, default="draft")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self) -> str:
        return f"{self.label} ({self.amount} {self.currency})"
"@
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
    """Panneau admin custom (API DRF + registry whitelist)."""

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
        "app_label": "$AppName",
        "model_name": "transaction",
        "label": "Transactions",
        "permissions": ["list", "create", "edit", "delete", "schema"],
    },
]
"@

    Write-TextFile -Path (Join-Path $panelDir "selectors.py") -Content @'
from __future__ import annotations

from django.apps import apps
from django.db import models

from .registry import ADMIN_MODEL_REGISTRY, RegistryEntry


def list_registry_entries() -> list[RegistryEntry]:
    """Retourne la whitelist des models admin."""
    return list(ADMIN_MODEL_REGISTRY)


def get_model_schema(app_label: str, model_name: str) -> dict[str, object]:
    """Schema d'un model (champs, types, contraintes, relations)."""
    model = apps.get_model(app_label, model_name)
    fields: list[dict[str, object]] = []
    for field in model._meta.get_fields():
        if getattr(field, "auto_created", False) and not field.concrete:
            continue
        info: dict[str, object] = {
            "name": field.name,
            "type": field.__class__.__name__,
            "nullable": getattr(field, "null", False),
            "unique": getattr(field, "unique", False),
        }
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
'@

    Write-TextFile -Path (Join-Path $panelDir "services.py") -Content @'
from __future__ import annotations

from decimal import Decimal, InvalidOperation
from typing import Any

from django.apps import apps as django_apps
from django.db import models
from django.utils.dateparse import parse_date, parse_datetime

from apps.admin_panel.registry import ADMIN_MODEL_REGISTRY


class AdminModelNotAllowedError(LookupError):
    """Model hors whitelist registry admin."""


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


def serialize_instance(model: type[models.Model], instance: models.Model) -> dict[str, Any]:
    """Serialise une instance ORM en dict JSON-friendly."""
    row: dict[str, Any] = {}
    for field in model._meta.concrete_fields:
        row[field.name] = _serialize_value(getattr(instance, field.attname))
    return row


def _coerce_field_value(field: models.Field, raw: object) -> object:
    """Convertit une valeur API vers le type ORM."""
    if raw is None or raw == "":
        if field.null:
            return None
        return raw
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
            raise ValueError(f"Valeur decimale invalide pour {field.name}") from exc
    if isinstance(field, models.DateTimeField):
        parsed = parse_datetime(str(raw))
        if parsed is None:
            raise ValueError(f"Date/heure invalide pour {field.name}")
        return parsed
    if isinstance(field, models.DateField):
        parsed = parse_date(str(raw))
        if parsed is None:
            raise ValueError(f"Date invalide pour {field.name}")
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


def create_model_row(app_label: str, model_name: str, payload: dict[str, Any]) -> dict[str, Any]:
    """Cree une ligne via ORM (whitelist registry)."""
    model = _resolve_model(app_label, model_name)
    data = _clean_payload(model, payload, exclude_pk=True)
    instance = model.objects.create(**data)
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
    data = _clean_payload(model, payload, exclude_pk=True)
    for name, value in data.items():
        setattr(instance, name, value)
    instance.save()
    return serialize_instance(model, instance)


def delete_model_row(app_label: str, model_name: str, pk: str) -> None:
    """Supprime une ligne via ORM."""
    model = _resolve_model(app_label, model_name)
    model.objects.filter(pk=pk).delete()
'@

    Write-TextFile -Path (Join-Path $panelDir "serializers.py") -Content @'
"""Serializers DRF pour l'admin panel."""

from rest_framework import serializers
'@

    Write-TextFile -Path (Join-Path $panelDir "permissions.py") -Content @'
"""Permissions DRF pour l''admin panel."""

from __future__ import annotations

from rest_framework.permissions import BasePermission
from rest_framework.request import Request
from rest_framework.views import APIView


class IsSuperUser(BasePermission):
    """Acces reserve aux superusers Django."""

    message = "Superuser requis."

    def has_permission(self, request: Request, view: APIView) -> bool:
        user = request.user
        return bool(
            user and user.is_authenticated and getattr(user, "is_superuser", False)
        )
'@

    Write-TextFile -Path (Join-Path $panelDir "auth_views.py") -Content @'
"""Authentification admin (JWT, superuser uniquement)."""

from __future__ import annotations

from django.contrib.auth import authenticate
from rest_framework import status
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken

from .permissions import IsSuperUser


class AdminLoginView(APIView):
    """POST /api/auth/login/ - JWT si superuser."""

    permission_classes = [AllowAny]

    def post(self, request: Request) -> Response:
        username = str(request.data.get("username", "")).strip()
        password = str(request.data.get("password", ""))
        if not username or not password:
            return Response(
                {
                    "detail": "Identifiant et mot de passe requis.",
                    "code": "missing_credentials",
                },
                status=status.HTTP_400_BAD_REQUEST,
            )
        user = authenticate(
            request=request,
            username=username,
            password=password,
        )
        if user is None:
            return Response(
                {
                    "detail": "Identifiants incorrects pour cette base de donnees.",
                    "code": "invalid_credentials",
                },
                status=status.HTTP_401_UNAUTHORIZED,
            )
        if not user.is_superuser:
            return Response(
                {
                    "detail": (
                        "Compte reconnu mais acces refuse : superuser Django requis "
                        "(docker compose exec web uv run python manage.py createsuperuser)."
                    ),
                    "code": "not_superuser",
                },
                status=status.HTTP_403_FORBIDDEN,
            )
        refresh = RefreshToken.for_user(user)
        return Response(
            {
                "access": str(refresh.access_token),
                "refresh": str(refresh),
                "user": {
                    "username": user.username,
                    "is_superuser": user.is_superuser,
                },
            }
        )


class AdminSessionView(APIView):
    """GET /api/auth/session/ - profil superuser connecte."""

    permission_classes = [IsAuthenticated, IsSuperUser]

    def get(self, request: Request) -> Response:
        user = request.user
        return Response(
            {
                "username": user.username,
                "is_superuser": user.is_superuser,
            }
        )
'@

    Write-TextFile -Path (Join-Path $panelDir "auth_urls.py") -Content @'
"""Routes auth admin panel."""

from django.urls import path

from . import auth_views

urlpatterns = [
    path("login/", auth_views.AdminLoginView.as_view(), name="admin-login"),
    path("session/", auth_views.AdminSessionView.as_view(), name="admin-session"),
]
'@

    Write-TextFile -Path (Join-Path $panelDir "views.py") -Content @'
from __future__ import annotations

from django.core.exceptions import ObjectDoesNotExist
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from . import selectors
from .permissions import IsSuperUser

_ADMIN_PERMS = [IsAuthenticated, IsSuperUser]


class RegistryListView(APIView):
    """GET /api/admin/registry/ - liste whitelist models."""

    permission_classes = _ADMIN_PERMS

    def get(self, request: Request) -> Response:
        return Response({"results": selectors.list_registry_entries()})


class SchemaGlobalView(APIView):
    """GET /api/admin/schema/ - schema global + liaisons."""

    permission_classes = _ADMIN_PERMS

    def get(self, request: Request) -> Response:
        return Response(selectors.get_global_schema())


class SchemaModelView(APIView):
    """GET /api/admin/schema/<app>/<model>/ - schema d'une table."""

    permission_classes = _ADMIN_PERMS

    def get(self, request: Request, app_label: str, model_name: str) -> Response:
        return Response(selectors.get_model_schema(app_label, model_name))


class SchemaExportView(APIView):
    """GET /api/admin/schema/export/ - Mermaid markdown (+ SVG a generer cote front V2)."""

    permission_classes = _ADMIN_PERMS

    def get(self, request: Request) -> Response:
        mermaid = selectors.export_schema_mermaid()
        return Response(
            {
                "format": "mermaid",
                "markdown": mermaid,
                "svg_hint": "Telecharger via frontend/admin/schema (V2)",
            }
        )


class ModelRowsListView(APIView):
    """GET/POST /api/admin/models/<app>/<model>/ - grille admin CRUD."""

    permission_classes = _ADMIN_PERMS

    def get(self, request: Request, app_label: str, model_name: str) -> Response:
        from .services import AdminModelNotAllowedError, list_model_rows

        try:
            return Response(list_model_rows(app_label, model_name))
        except AdminModelNotAllowedError:
            return Response({"detail": "Model non autorise"}, status=status.HTTP_404_NOT_FOUND)

    def post(self, request: Request, app_label: str, model_name: str) -> Response:
        from .services import AdminModelNotAllowedError, create_model_row

        try:
            row = create_model_row(app_label, model_name, request.data)
            return Response(row, status=status.HTTP_201_CREATED)
        except AdminModelNotAllowedError:
            return Response({"detail": "Model non autorise"}, status=status.HTTP_404_NOT_FOUND)
        except ValueError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)


class ModelRowDetailView(APIView):
    """PATCH/DELETE /api/admin/models/<app>/<model>/<pk>/."""

    permission_classes = _ADMIN_PERMS

    def patch(
        self,
        request: Request,
        app_label: str,
        model_name: str,
        pk: str,
    ) -> Response:
        from .services import AdminModelNotAllowedError, update_model_row

        try:
            row = update_model_row(app_label, model_name, pk, request.data)
            return Response(row)
        except AdminModelNotAllowedError:
            return Response({"detail": "Model non autorise"}, status=status.HTTP_404_NOT_FOUND)
        except ObjectDoesNotExist:
            return Response({"detail": "Ligne introuvable"}, status=status.HTTP_404_NOT_FOUND)
        except ValueError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)

    def delete(
        self,
        request: Request,
        app_label: str,
        model_name: str,
        pk: str,
    ) -> Response:
        from .services import AdminModelNotAllowedError, delete_model_row

        try:
            delete_model_row(app_label, model_name, pk)
            return Response(status=status.HTTP_204_NO_CONTENT)
        except AdminModelNotAllowedError:
            return Response({"detail": "Model non autorise"}, status=status.HTTP_404_NOT_FOUND)
        except ObjectDoesNotExist:
            return Response({"detail": "Ligne introuvable"}, status=status.HTTP_404_NOT_FOUND)
'@

    Write-TextFile -Path (Join-Path $panelDir "urls.py") -Content @'
from django.urls import path

from . import views

app_name = "admin_panel"

urlpatterns = [
    path("registry/", views.RegistryListView.as_view(), name="registry"),
    path("schema/", views.SchemaGlobalView.as_view(), name="schema-global"),
    path("schema/export/", views.SchemaExportView.as_view(), name="schema-export"),
    path(
        "schema/<str:app_label>/<str:model_name>/",
        views.SchemaModelView.as_view(),
        name="schema-model",
    ),
    path(
        "models/<str:app_label>/<str:model_name>/",
        views.ModelRowsListView.as_view(),
        name="model-rows",
    ),
    path(
        "models/<str:app_label>/<str:model_name>/<str:pk>/",
        views.ModelRowDetailView.as_view(),
        name="model-row-detail",
    ),
]
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


def test_registry_contains_transaction() -> None:
    entries = list_registry_entries()
    assert any(e["model_name"] == "transaction" for e in entries)


def test_registry_whitelist_not_empty() -> None:
    assert len(ADMIN_MODEL_REGISTRY) >= 1
'@

    Write-TextFile -Path (Join-Path $panelDir "tests\test_schema.py") -Content @"
"""Tests schema admin panel."""

import pytest

from apps.admin_panel.selectors import export_schema_mermaid, get_model_schema


@pytest.mark.django_db
def test_model_schema_transaction_fields() -> None:
    schema = get_model_schema("$AppName", "transaction")
    assert "relations" in schema
    assert "incoming" in schema
    names = {f["name"] for f in schema["fields"]}
    assert "amount" in names
    assert "label" in names


def test_export_mermaid_contains_erdiagram() -> None:
    md = export_schema_mermaid()
    assert "erDiagram" in md
"@
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
    Write-TextFile -Path (Join-Path $Root "static\css\.gitkeep") -Content "`n"
    Write-TextFile -Path (Join-Path $Root "static\js\.gitkeep") -Content "`n"
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
  },
  "pnpm": {
    "onlyBuiltDependencies": [
      "@parcel/watcher",
      "sharp",
      "unrs-resolver"
    ]
  }
}
"@

    Write-TextFile -Path (Join-Path $fe ".npmrc") -Content @'
# Docker / CI : pas de prompt interactif (purge node_modules)
confirm-modules-purge=false
# pnpm 10+ : autoriser les scripts de build requis par Next.js
only-built-dependencies[]=@parcel/watcher
only-built-dependencies[]=sharp
only-built-dependencies[]=unrs-resolver
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
  description: "Frontend Next.js - API Django/DRF",
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
          <p className="page-home__eyebrow">Django Â· uv Â· Next.js</p>
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
              Service Layer, DRF et persistance PostgreSQL.
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
# Docker dev (Server Components) - via port publie sur l'hote :
# API_INTERNAL_URL=http://host.docker.internal:8000
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

    New-AdminFrontendScaffold -FeRoot $fe -AppName $AppName
}

function New-DockerStack {
    param(
        [Parameter(Mandatory)][string]$Root,
        [int]$PostgresHostPort = 5433
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

    $feScriptsDir = Join-Path $Root "frontend\scripts"
    New-Item -ItemType Directory -Path $feScriptsDir -Force | Out-Null
    Write-TextFile -Path (Join-Path $feScriptsDir "docker-entrypoint-dev.sh") -Content @'
#!/bin/sh
# Entree Docker dev frontend : deps dans l''image + reparation non interactive si volume vide.
set -e
export CI=true
cd /app

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

    Write-TextFile -Path (Join-Path $feScriptsDir "docker-frontend-dev.sh") -Content @'
#!/bin/sh
# Alias - preferer scripts/docker-entrypoint-dev.sh
exec /app/scripts/docker-entrypoint-dev.sh
'@

    Write-TextFile -Path (Join-Path $Root "Dockerfile") -Content @'
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS base
WORKDIR /app
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy

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
      # Superuser auto dans PostgreSQL Docker (optionnel) :
      # DJANGO_SUPERUSER_USERNAME: admin
      # DJANGO_SUPERUSER_PASSWORD: admin
      # DJANGO_SUPERUSER_EMAIL: admin@local.test
      DJANGO_USE_POSTGRES: "1"
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
      API_INTERNAL_URL: http://host.docker.internal:8000
      HOSTNAME: "0.0.0.0"
    ports:
      - "3000:3000"
    depends_on:
      web:
        condition: service_healthy
    restart: unless-stopped

volumes:
  pgdata:
  backend_venv:
  frontend_next:
'@
    $composeDev = $composeDev -replace 'POSTGRES_HOST_PORT', [string]$PostgresHostPort

    Write-TextFile -Path (Join-Path $Root ".gitattributes") -Content @'
# Scripts shell : LF obligatoire pour Docker/Linux
*.sh text eol=lf
'@

    Write-TextFile -Path (Join-Path $Root "docker-compose.yml") -Content $composeDev
    Write-TextFile -Path (Join-Path $Root "docker-compose.dev.yml") -Content $composeDev

    Write-TextFile -Path (Join-Path $Root "docker-compose.prod.yml") -Content @'
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
      - db
    ports:
      - "8000:8000"

  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile
      target: runner
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
  """Client DRF authentifie en superuser."""
  api_client.force_authenticate(user=superuser)
  return api_client
'@

    Write-TextFile -Path (Join-Path $Root "pytest.ini") -Content @'
[pytest]
DJANGO_SETTINGS_MODULE = config.settings
python_files = tests.py test_*.py *_tests.py
addopts = -ra
'@

    Write-TextFile -Path (Join-Path $testsDir "test_admin_api.py") -Content @'
"""Tests API admin panel (auth superuser)."""

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
    api_client.force_authenticate(user=user)
    response = api_client.get("/api/admin/registry/")
    assert response.status_code == 403


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
        {"username": "user", "password": "pass"},
        format="json",
    )
    assert response.status_code == 403
    assert response.json()["code"] == "not_superuser"


def test_login_rejects_wrong_password(api_client, superuser) -> None:
    response = api_client.post(
        "/api/auth/login/",
        {"username": "admin", "password": "wrong-password"},
        format="json",
    )
    assert response.status_code == 401
    assert response.json()["code"] == "invalid_credentials"


@pytest.mark.django_db
def test_login_accepts_superuser(api_client, superuser) -> None:
    response = api_client.post(
        "/api/auth/login/",
        {"username": "admin", "password": "admin-secret"},
        format="json",
    )
    assert response.status_code == 200
    data = response.json()
    assert "access" in data
    assert data["user"]["is_superuser"] is True
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
| ``templates/`` | Templates Django legacy minimaux |
| ``static/scss/`` | SCSS 7-1 (pages internes optionnelles) |
| ``frontend/`` | Next.js App Router + admin custom ``/admin`` |
| ``apps/admin_panel/`` | Registry whitelist + API DRF ``/api/admin/`` |
| ``tests/`` | Pytest |
| ``docker-compose*.yml`` | Stack locale / prod |

## Apps Django
| App | Role |
|-----|------|
| ``apps.$AppName`` | App metier (ex. Transaction) |
| ``apps.admin_panel`` | Admin custom : registry, schema, stubs CRUD API |

## Front Next.js
- UI admin principale : ``/admin``, ``/login`` (Flat High-End, SCSS + ``:root``).
- Pas de HTMX. Pas de logique metier cote client.
- ``NEXT_PUBLIC_API_URL`` (navigateur) ; ``API_INTERNAL_URL`` (RSC Docker, ex. ``http://host.docker.internal:8000``).
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
    [Transaction]
  }
  package "admin_panel" {
    [registry]
    [API /api/admin/]
  }
}
package "frontend" {
  [App Router]
  [admin UI]
}
database "PostgreSQL" as db
[apps] --> db : ORM
[frontend] --> [serializers] : HTTP JSON
@enduml
"@
    Write-TextFile -Path (Join-Path $cursorDir "app-architecture.uml") -Content $uml

    Write-TextFile -Path (Join-Path $cursorDir "AGENTS.md") -Content @"
# Agents Cursor - monorepo Django + Next.js

## Lead par defaut
**@ProjectManager** - plan d'action, dispatch, Definition of Done.

## Matrice rapide
| Sujet | Agent |
|-------|--------|
| Service Layer, CBV, DRF, MRO | @Architect (django-architect) |
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
- DRF pour API consommee par Next.js

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

## Docker (dev - runserver + Next dev)
``````bash
docker compose up --build
``````

Production : ``docker compose -f docker-compose.prod.yml up --build``
"@ } else { "" }

    $readme = @"
# Monorepo Django + uv + Next.js$(if ($HasDocker) { " + Docker" })

## Demarrage rapide

``````powershell
# Generer un projet (script)
powershell -ExecutionPolicy Bypass -File .\New-DjangoUvProject.ps1 -NewFolder mon_projet -NoInteractive

cd mon_projet
uv sync
uv run python manage.py migrate
``````

## Docker (dev)

``````powershell
$env:DOCKER_BUILDKIT = "1"
docker compose up --build
``````

Les paquets frontend sont installes au **build** de l'image (``pnpm install --frozen-lockfile`` si ``pnpm-lock.yaml`` present - genere a l'init).
Le conteneur demarre directement sur ``pnpm dev`` (pas de reinstall au ``up``).
Le volume anonyme ``/app/node_modules`` conserve les deps de l'image (demarrage rapide).
Apres modification de ``package.json`` : ``docker compose build frontend --no-cache``.

Depannage :
- ``web`` en ``Restarting`` : ``docker compose logs web`` (souvent PostgreSQL : ``failed to resolve host 'db'``).
- Port 5432 deja utilise sous Windows : Postgres Docker mappe sur **5433** (hote) ; arreter un Postgres local ou changer le mapping.
- ``authentification par mot de passe echouee`` pour ``app`` : le port 5433 n'est pas le bon Postgres, ou volume obsolete. ``docker compose down -v`` puis ``docker compose up -d db``. Mot de passe attendu : ``dev`` (voir ``.env`` et ``POSTGRES_PASSWORD`` dans compose).
- ``fetch failed`` / ``ECONNREFUSED`` sur ``/admin`` : ``curl http://localhost:8000/api/health/`` ; sous Docker Desktop utiliser ``API_INTERNAL_URL=http://host.docker.internal:8000`` + ``extra_hosts: host-gateway``.
- ``app-paths-manifest.json`` ENOENT : supprimer ``frontend/.next`` sur l'hote, volume ``frontend_next`` dans compose, puis ``docker compose up --build``.
- ``ERR_PNPM_NO_LOCKFILE`` : ``cd frontend && pnpm install`` (cree ``pnpm-lock.yaml``), puis ``docker compose build frontend``.
- ``Cannot resolve lucide-react`` / prompt pnpm purge : ``docker compose down -v`` puis ``docker compose build frontend`` et ``docker compose up`` (volume ``node_modules`` vide ou Windows desync).
- ``dependency web failed to start`` : ``docker compose logs web`` (PostgreSQL, migrations, healthcheck).

- Backend : http://localhost:8000
- Frontend : http://localhost:3000
- Admin Next.js : http://localhost:3000/admin
- Login : http://localhost:3000/login (superuser Django uniquement)

## Base de donnees (PostgreSQL)

Avec Docker, le script genere un fichier ``.env`` : Django utilise **PostgreSQL** sur ``localhost:5433`` (meme instance que le service ``db`` du compose).

``````bash
docker compose up -d db
uv run python manage.py migrate
uv run python manage.py createsuperuser
docker compose up
``````

Sans ``.env`` / sans ``DJANGO_USE_POSTGRES=1`` : fallback SQLite (``db.sqlite3``).

## Compte superuser (obligatoire pour /admin)

Cree a l'init ou via ``createsuperuser`` - **superuser** requis pour ``/login``.

## Backend

App metier : ``apps.$AppName`` (ex. ``Transaction``)
Admin API : ``apps.admin_panel`` - registry whitelist, schema, stubs CRUD

Django ``/django-admin/`` : fallback **dev uniquement** (``DJANGO_ADMIN_ENABLED``).
Desactive en prod dans ``config/settings/prod.py``.

**Structure BDD** : ``models.py`` + migrations uniquement (pas de DDL via UI admin).

$fe

## Roadmap parite admin Django

| Phase | Perimetre |
|-------|-----------|
| **V1 (scaffold)** | Registry, schema table/global, export Mermaid, pages Next stub, API stubs |
| **V2** | CRUD reel (list/create/edit/delete), auth, permissions, export SVG |
| **V3** | Inlines, filtres avances, actions bulk, audit, parite fonctionnelle partielle |

> Ce scaffold ne pretend pas a une parite 100 % avec ``django.contrib.admin``.

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
        "apps\admin_panel\registry.py",
        "apps\admin_panel\urls.py",
        "apps\admin_panel\views.py",
        ".cursor\AGENTS.md",
        ".cursor\rules\00-project-stack.mdc"
    )
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
            "frontend\src\styles\admin\data-studio.scss",
            "frontend\next.config.ts"
        )
    }
    if ($ExpectDocker) {
        $required += @(
            "Dockerfile",
            "docker-compose.yml",
            "scripts\docker-web-dev.sh",
            "frontend\scripts\docker-entrypoint-dev.sh",
            "frontend\scripts\docker-frontend-dev.sh"
        )
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

    $lockPath = Join-Path $FrontendRoot "pnpm-lock.yaml"
    $installArgs = if (Test-Path -LiteralPath $lockPath) {
        @("install", "--frozen-lockfile")
    } else {
        @("install")
    }

    foreach ($tool in @("pnpm", "npm")) {
        if (-not (Resolve-ExecutablePath -Name $tool)) { continue }
        try {
            if ($tool -eq "npm") {
                $installArgs = @("install")
            }
            Write-Host "     $tool $($installArgs -join ' ') (genere pnpm-lock.yaml pour Docker rapide)..." -ForegroundColor DarkGray
            Invoke-CheckedCommand -Exe $tool -Arguments $installArgs -WorkingDirectory $FrontendRoot `
                -Quiet -TimeoutSeconds $CommandTimeoutSeconds
            if ($tool -eq "pnpm" -and -not (Test-Path -LiteralPath $lockPath)) {
                Write-Host "     Avertissement : pnpm-lock.yaml absent apres install." -ForegroundColor DarkYellow
            }
            return $tool
        } catch {
            Write-Host "     $tool install ignore : $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }
    Write-Host "     Installez les deps : cd frontend && pnpm install" -ForegroundColor DarkYellow
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
        do {
            $answer = (Read-Host "Nouveau dossier projet ? (Y/N)").Trim()
        } while ($answer -notmatch '^[YyNn]$')
        if ($answer -match '^[Yy]$') { $wantsNewFolder = $true } else { $useCurrent = $true }
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

    $doFrontend = -not $SkipFrontend.IsPresent
    $doDocker = -not $SkipDocker.IsPresent

    Write-PipelineBanner -Subtitle "App: $AppName | Frontend: $doFrontend | Docker: $doDocker"

    Start-PipelineStep -Title "Environnement uv" -Detail "init + dependances runtime et dev"
    if (-not (Test-Path -LiteralPath (Join-Path $root "pyproject.toml"))) {
        Invoke-UvCommand -Arguments @("init", "--name", $uvName) -WorkingDirectory $root -Quiet
    }
    Invoke-UvCommand -Arguments @(
        "add", "django", "djangorestframework", "djangorestframework-simplejwt",
        "whitenoise", "django-cors-headers", "gunicorn", "psycopg[binary]"
    ) -WorkingDirectory $root -Quiet
    Invoke-UvCommand -Arguments @(
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
    Invoke-UvCommand -Arguments @(
        "run", "django-admin", "startapp", $AppName, "apps\$AppName"
    ) -WorkingDirectory $root -Quiet
    $appsPyPath = Join-Path $root "apps\$AppName\apps.py"
    if (Test-Path -LiteralPath $appsPyPath) {
        $appsPy = Get-Content -LiteralPath $appsPyPath -Raw -Encoding UTF8
        $appsPy = $appsPy -replace "name = ['\`"]$AppName['\`"]", "name = `"apps.$AppName`""
        Write-TextFile -Path $appsPyPath -Content $appsPy
    }
    New-AppServiceLayer -Root $root -AppName $AppName
    New-CoreModels -Root $root -AppName $AppName
    Complete-PipelineStep

    Start-PipelineStep -Title "Admin panel API" -Detail "apps/admin_panel + registry + schema DRF"
    Invoke-UvCommand -Arguments @(
        "run", "django-admin", "startapp", "admin_panel", "apps\admin_panel"
    ) -WorkingDirectory $root -Quiet
    $panelAppsPy = Join-Path $root "apps\admin_panel\apps.py"
    if (Test-Path -LiteralPath $panelAppsPy) {
        $panelApps = Get-Content -LiteralPath $panelAppsPy -Raw -Encoding UTF8
        $panelApps = $panelApps -replace "name = ['\`"]admin_panel['\`"]", "name = `"apps.admin_panel`""
        Write-TextFile -Path $panelAppsPy -Content $panelApps
    }
    New-AdminPanelBackend -Root $root -AppName $AppName
    Complete-PipelineStep

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

    if ($doFrontend) {
        Start-PipelineStep -Title "Frontend Next.js" -Detail "App Router + SCSS tokens (sans Tailwind)"
        New-NextJsFrontend -Root $root -ProjectSlug $uvName -AppName $AppName
        $pkgMgr = $null
        if (-not $SkipFrontendDeps.IsPresent) {
            $pkgMgr = Install-FrontendDependencies -FrontendRoot (Join-Path $root "frontend")
        } else {
            Write-Host "     (-SkipFrontendDeps) : pas de lockfile - le build Docker frontend sera plus lent." -ForegroundColor DarkYellow
        }
        Complete-PipelineStep -Message $(if ($pkgMgr) { "deps $pkgMgr" } else { "squelette Next.js" })
    } else {
        Write-Host "     (SkipFrontend)" -ForegroundColor DarkYellow
    }

    if ($doDocker) {
        Start-PipelineStep -Title "Docker" -Detail "Dockerfile + compose dev/prod"
        $postgresHostPort = Find-AvailablePostgresHostPort
        Write-Host "     Port PostgreSQL hote : $postgresHostPort" -ForegroundColor DarkGray
        New-DockerStack -Root $root -PostgresHostPort $postgresHostPort
        Complete-PipelineStep

        Start-PipelineStep -Title "PostgreSQL (.env)" -Detail "base Django unique hote + Docker"
        Write-ProjectDotEnvForDocker -Root $root -PostgresHostPort $postgresHostPort
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

# Superuser non interactif (CI / -NoInteractive) :
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

# Next.js (frontend/.env.local)
# NEXT_PUBLIC_API_URL=http://localhost:8000
"@
    Complete-PipelineStep

    Start-PipelineStep -Title "Verification structure" -Detail "fichiers obligatoires"
    Test-ProjectStructure -Root $root -AppName $AppName -ExpectFrontend $doFrontend -ExpectDocker $doDocker
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
        Write-Host "     makemigrations + migrate ($dbLabel)" -ForegroundColor DarkGray
        if (Test-ProjectDotEnvUsesPostgres -Root $root) {
            if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
                throw "Docker requis pour PostgreSQL (.env) : installez Docker Desktop"
            }
            try {
                Ensure-ComposeDatabaseForDjango -Root $root -TimeoutSeconds 60
            } catch {
                throw @"
PostgreSQL indisponible pour les migrations : $($_.Exception.Message)
Verifiez Docker (docker compose ps) ou reinitialisez : docker compose down -v && docker compose up -d db
"@
            }
        }
        Invoke-DjangoManage -Root $root -Arguments @("makemigrations", $AppName, "--noinput")
        Invoke-DjangoManage -Root $root -Arguments @("migrate", "--noinput", "--verbosity", "1")
        Complete-PipelineStep -Message "migrations appliquees"
    }

    if (-not $SkipCreatesuperuser.IsPresent) {
        Start-PipelineStep -Title "Superuser Django" -Detail "createsuperuser pour /admin"
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

    Write-PipelineSummary -Root $root -AppName $AppName -HasFrontend $doFrontend -HasDocker $doDocker
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
