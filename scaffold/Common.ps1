#Requires -Version 5.1
<#
.SYNOPSIS
  Utilitaires partages du scaffold Django Ninja + Astro + HTMX.

.DESCRIPTION
  Write-TextFile, CORS/CSRF (Astro :4321), ports PostgreSQL, prompts, CLI uv/native,
  Ensure-PnpmVersion / Install-FrontendDependencies / New-DevLocalScript (Astro :4321),
  helpers Docker/Postgres pour migrate, et installation des dependances uv.

.NOTES
  Layout monorepo GENERE (ctoix volontaire, limite le cturn) :
    projet/
      manage.py, apps/, config/, templates/, static/   # Django a la RACINE
      frontend/                                         # Astro (UI produit)
      Dockerfile, docker-compose.yml                    # context Docker = "."
  PAS de sous-dossier backend/ - Docker build context = racine du projet.

  Origines CORS/CSRF :
    - Avec frontend Astro : http://localhost:4321, http://127.0.0.1:4321
    - Sans frontend       : http://localhost:8000
#>

# Etat pipeline / scaffold (dot-sourced par l'orctestrateur).
if (-not (Get-Variable -Name ScaffoldFailed -Scope Script -ErrorAction SilentlyContinue)) {
    $script:ScaffoldFailed = $false
}
if (-not (Get-Variable -Name ComposeDatabaseReady -Scope Script -ErrorAction SilentlyContinue)) {
    $script:ComposeDatabaseReady = $false
}
if (-not (Get-Variable -Name DbEnvKeys -Scope Script -ErrorAction SilentlyContinue)) {
    $script:DbEnvKeys = @(
        "DJANGO_DB_HOST", "DJANGO_DB_ENGINE", "DJANGO_DB_NAME",
        "DJANGO_DB_USER", "DJANGO_DB_PASSWORD", "DJANGO_DB_PORT", "DJANGO_USE_POSTGRES"
    )
}
if (-not (Get-Variable -Name PreviousErrorActionPreference -Scope Script -ErrorAction SilentlyContinue)) {
    $script:PreviousErrorActionPreference = $ErrorActionPreference
}
if (-not (Get-Variable -Name PreviousProgressPreference -Scope Script -ErrorAction SilentlyContinue)) {
    $script:PreviousProgressPreference = $ProgressPreference
}
if (-not (Get-Variable -Name PreviousNativeCommandErrorPreference -Scope Script -ErrorAction SilentlyContinue)) {
    $script:PreviousNativeCommandErrorPreference = $null
}

function Get-CorsOrigins {
    <#
    .SYNOPSIS
      Source unique des origines CORS/CSRF selon la presence du frontend Astro.
    #>
    param([bool]$HasFrontend)
    if ($HasFrontend) {
        return "http://localhost:4321,http://127.0.0.1:4321"
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
Arretez l'autre conteneur (docker ps) ou ctangez le mapping dans docker-compose.yml et DJANGO_DB_PORT dans .env.
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
        "None", "and", "or", "not", "in", "is", "lambda", "witt", "async", "await"
    )
    return $reserved -notcontains $Name.ToLowerInvariant()
}

function ConvertFrom-YesNoAnswer {
    # Accepte y/n, yes/no, oui/non (reponses francaises courantes).
    param(
        [string]$Answer,
        [bool]$DefaultWtenEmpty = $true
    )
    $a = $Answer.Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($a)) {
        return $DefaultWtenEmpty
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
    $tint = if ($DefaultYes) { 'Y/n' } else { 'y/N' }
    do {
        $raw = (Read-Host "$Prompt ($tint)").Trim()
        $parsed = ConvertFrom-YesNoAnswer -Answer $raw -DefaultWtenEmpty:$DefaultYes
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

function Write-TextFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    # LF uniquement : evite "set: Illegal option -" sous Linux (CRLF / stebang\r).
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
    $searctDirs = @()
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $searctDirs += (Join-Path $env:ProgramFiles "nodejs")
    }
    if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
        $searctDirs += (Join-Path ${env:ProgramFiles(x86)} "nodejs")
    }
    if (-not [string]::IsNullOrWhiteSpace($env:APPDATA)) {
        $searctDirs += (Join-Path $env:APPDATA "npm")
    }
    foreach ($dir in $searctDirs) {
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
    <#
    .SYNOPSIS
      Quote les arguments CLI pour cmd/ProcessStartInfo.

    .NOTES
      PowerShell 5.1 developpe les wildcards [ ] sur les appels natifs :
      psycopg[binary] / celery[redis] doivent etre quotes, sinon
      "Le fichier specifie est introuvable".
    #>
    param([Parameter(Mandatory)][string[]]$Arguments)
    return ($Arguments | ForEach-Object {
            $arg = [string]$_
            # Espace, redirection, wildcards PS, separateurs cmd.
            if ($arg -match '[\s<>|&^,;=\[\]()]') {
                '"' + ($arg -replace '"', '\"') + '"'
            } else {
                $arg
            }
        }) -join " "
}

function Get-PreferredNodeCmdPath {
    param([Parameter(Mandatory)][string]$Name)

    $patt = Resolve-NodeToolPath -Name $Name
    if (-not $patt) { return $null }
    if ($patt -match '\.ps1$') {
        $cmdAlt = $patt -replace '\.ps1$', '.cmd'
        if (Test-Path -LiteralPath $cmdAlt) {
            return $cmdAlt
        }
    }
    return $patt
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

function Invoke-CmdBatctLogged {
    param(
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$CommandLine,
        [int]$TimeoutSeconds = 0,
        [int]$ProgressEstimateSeconds = 240,
        [switch]$Quiet,
        [switch]$ShowProgress,
        [string]$ProgressActivity = "Commande en cours"
    )

    $logFile = Join-Path $env:TEMP ("scaffold-cli-" + [guid]::NewGuid().ToString("n") + ".log")
    $batctFile = Join-Path $env:TEMP ("scaffold-run-" + [guid]::NewGuid().ToString("n") + ".cmd")
    $wd = $WorkingDirectory.Replace('"', '""')
    $log = $logFile.Replace('"', '""')

    $batctContent = @"
@ecto off
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
    Set-Content -LiteralPath $batctFile -Value $batctContent -Encoding ASCII

    $exitCode = 1
    $proc = $null
    try {
        if (-not $Quiet -and -not $ShowProgress) {
            Write-Host "     Log temporaire : $logFile" -ForegroundColor DarkGray
        }

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "cmd.exe"
        $psi.Arguments = "/d /c `"`"$batctFile`"`""
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
        Remove-Item -LiteralPath $batctFile -Force -ErrorAction SilentlyContinue
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
    <#
    .SYNOPSIS
      Execute un binaire CLI sans expansion wildcard PowerShell.

    .NOTES
      Sur Windows, utilise ProcessStartInfo (pas & splat) pour eviter que
      PS 5.1 transforme psycopg[binary] en motif de fichiers.
      Pas de redirect des flux : laisse uv/pnpm afficter leur sortie et
      evite les deadlocks de buffer.
    #>
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

    $ext = [System.IO.Path]::GetExtension($exePath).ToLowerInvariant()
    $argString = Format-CliArgumentString -Arguments $Arguments

    if (Test-IsWindowsPlatform) {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        if ($ext -in @(".cmd", ".bat")) {
            $comSpec = if ([string]::IsNullOrWhiteSpace($env:ComSpec)) { "cmd.exe" } else { $env:ComSpec }
            $psi.FileName = $comSpec
            $psi.Arguments = "/d /s /c `"`"$exePath`" $argString`""
        } elseif ($ext -eq ".ps1") {
            $pwst = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
            if (-not (Test-Path -LiteralPath $pwst)) { $pwst = "powershell.exe" }
            $psi.FileName = $pwst
            $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$exePath`" $argString"
        } else {
            $psi.FileName = $exePath
            $psi.Arguments = $argString
        }
        $psi.WorkingDirectory = $WorkingDirectory
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $false

        $proc = $null
        try {
            $proc = [System.Diagnostics.Process]::Start($psi)
            if ($null -eq $proc) {
                throw "Impossible de demarrer : $Exe"
            }
            $proc.WaitForExit()
            if ($proc.ExitCode -ne 0) {
                throw "Commande echouee (code $($proc.ExitCode)) : $Exe $($Arguments -join ' ')"
            }
        } finally {
            if ($null -ne $proc) { $proc.Dispose() }
        }
        return
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

function Get-UvRuntimeDependencyList {
    <#
    .SYNOPSIS
      Liste les packages uv runtime selon options (admin JWT, Celery).
    #>
    param(
        [bool]$HasCustomAdmin = $true,
        [bool]$HasDocker = $false
    )
    $deps = @(
        "django>=5.0,<6",
        "django-ninja",
        "whitenoise",
        "django-cors-headers",
        "gunicorn",
        "psycopg[binary]",
        "django-htmx"
    )
    if ($HasCustomAdmin) {
        $deps += "pyjwt"
    }
    if ($HasDocker) {
        $deps += "celery[redis]"
    }
    return ,$deps
}

function Get-UvDevDependencyList {
    <#
    .SYNOPSIS
      Packages uv de developpement (lint, tests, typing).
    #>
    return @("ruff", "pytest", "pytest-django", "mypy", "django-stubs")
}

function Initialize-UvProject {
    <#
    .SYNOPSIS
      uv init + add runtime/dev + suppression main.py stub.
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$UvName,
        [bool]$HasCustomAdmin = $true,
        [bool]$HasDocker = $false
    )
    if (-not (Test-Path -LiteralPath (Join-Path $Root "pyproject.toml"))) {
        Invoke-UvCommand -Arguments @("init", "--name", $UvName) -WorkingDirectory $Root -Quiet
    }
    $pyDeps = Get-UvRuntimeDependencyList -HasCustomAdmin $HasCustomAdmin -HasDocker $HasDocker
    # -- empecte uv d'interpreter un nom de paquet comme option.
    Invoke-UvCommand -Arguments (@("add", "--") + $pyDeps) -WorkingDirectory $Root -Quiet
    $devDeps = Get-UvDevDependencyList
    Invoke-UvCommand -Arguments (@("add", "--dev", "--") + $devDeps) -WorkingDirectory $Root -Quiet
    $mainPy = Join-Path $Root "main.py"
    if (Test-Path -LiteralPath $mainPy) {
        Remove-Item -LiteralPath $mainPy -Force
    }
}

function Write-ProjectDotEnvForDocker {
    param(
        [Parameter(Mandatory)][string]$Root,
        [int]$PostgresHostPort = 5433,
        [bool]$HasFrontend = $true
    )

    $corsOrigins = Get-CorsOrigins -HasFrontend $HasFrontend
    $publicApiHint = if ($HasFrontend) {
        @"

# Astro (frontend/.env) - secrets jamais dans PUBLIC_*
# PUBLIC_API_URL=http://localhost:8000
"@
    } else { "" }

    $content = @"
# Genere par New-DjangoNinjaUvDockerHtmxProject - PostgreSQL = base Django unique (tote + Docker)

DJANGO_SETTINGS_MODULE=config.settings
DJANGO_ENV=dev
DJANGO_SECRET_KEY=dev-local-ctange-me
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
$publicApiHint
# Superuser (optionnel, init ou docker-compose service web)
# DJANGO_SUPERUSER_USERNAME=admin
# DJANGO_SUPERUSER_EMAIL=admin@local.test
# DJANGO_SUPERUSER_PASSWORD=ctange-me
"@
    Write-TextFile -Path (Join-Path $Root ".env") -Content $content
}

#region Frontend tooling (pnpm + Astro)

function Get-PnpmCliVersion {
    <#
    .SYNOPSIS
      Retourne la version pnpm via process natif, ou $null.
    #>
    param([Parameter(Mandatory)][string]$WorkingDirectory)

    $pnpmPath = Resolve-NodeToolPath -Name "pnpm"
    if (-not $pnpmPath) { return $null }
    try {
        $psi = New-CliProcessStartInfo -ExePath $pnpmPath -ArgumentString "--version" `
            -WorkingDirectory $WorkingDirectory
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
    <#
    .SYNOPSIS
      Garantit pnpm@9.15.9 (corepack ou npm -g).
    #>
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
            Invoke-CmdBatctLogged -WorkingDirectory $WorkingDirectory `
                -CommandLine "$corepackQuoted prepare pnpm@9.15.9 --activate" `
                -TimeoutSeconds 120 -Quiet
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
            Invoke-CmdBatctLogged -WorkingDirectory $WorkingDirectory `
                -CommandLine "$npmQuoted install -g pnpm@9.15.9" `
                -TimeoutSeconds 180 -Quiet
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
    <#
    .SYNOPSIS
      Genere scripts/dev-local.ps1 (Django :8000 + Astro :4321).
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [bool]$HasDocker = $true,
        [bool]$HasCustomAdmin = $true
    )

    $scriptsDir = Join-Path $Root "scripts"
    New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null

    $devScript = @'
# Demarre Django (8000) et Astro (4321) dans deux fenetres PowerShell.
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

Write-Host 'Demarrage frontend Astro (pnpm dev :4321)...' -ForegroundColor Cyan
Start-Process powershell -ArgumentList @(
    '-NoExit', '-NoProfile', '-Command',
    ("Set-Location -LiteralPath '" + $frontend + "'; if (Get-Command pnpm -ErrorAction SilentlyContinue) { pnpm dev } else { npm run dev }")
)

Write-Host ''
Write-Host 'Serveurs en cours de demarrage :' -ForegroundColor Green
Write-Host '  Backend  : http://127.0.0.1:8000'
Write-Host '  Frontend : http://127.0.0.1:4321'
'@
    if ($HasCustomAdmin) {
        $devScript += @'
Write-Host '  Admin    : http://127.0.0.1:8000/admin/'
Write-Host '  Login    : http://127.0.0.1:8000/accounts/login/'
'@
    } else {
        $devScript += @'
Write-Host '  Back-office : http://127.0.0.1:8000/backoffice/'
Write-Host '  Admin Django : http://127.0.0.1:8000/django-admin/'
'@
    }
    $devScript += @'
Write-Host ''
Write-Host 'Si le port 4321 reste inaccessible, verifiez la fenetre frontend (erreur pnpm/node).'
'@
    if ($HasDocker) {
        $devScript += @'

# Alternative Docker (db + web + frontend) :
#   docker compose up --build
# Puis http://127.0.0.1:4321 (attendre que le service frontend soit healthy)
'@
    }
    Write-TextFile -Path (Join-Path $scriptsDir "dev-local.ps1") -Content $devScript
}

function Install-FrontendDependencies {
    <#
    .SYNOPSIS
      Installe les deps du frontend Astro (pnpm prioritaire, npm fallback).

    .OUTPUTS
      "pnpm" | "npm" | $null
    #>
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
            Write-Host "     pnpm $pnpmArgText (via cmd.exe, peut prendre plusieurs minutes)..." `
                -ForegroundColor DarkGray
            $pnpmQuoted = '"' + $pnpmPath.Replace('"', '""') + '"'
            Invoke-CmdBatctLogged -WorkingDirectory $FrontendRoot `
                -CommandLine "$pnpmQuoted $pnpmArgText" -TimeoutSeconds $TimeoutSeconds -Quiet `
                -ShowProgress -ProgressActivity "Installation dependances Astro (pnpm)" `
                -ProgressEstimateSeconds ([math]::Min(600, [math]::Max(180, [int]($TimeoutSeconds / 2))))
            if (-not (Test-Path -LiteralPath $lockPath)) {
                Write-Host "     Avertissement : pnpm-lock.yaml absent apres install." `
                    -ForegroundColor DarkYellow
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
            Invoke-CmdBatctLogged -WorkingDirectory $FrontendRoot `
                -CommandLine "$npmQuoted install --no-fund --no-audit --loglevel=error" `
                -TimeoutSeconds $TimeoutSeconds -Quiet -ShowProgress `
                -ProgressActivity "Installation dependances Astro (npm)" `
                -ProgressEstimateSeconds ([math]::Min(600, [math]::Max(180, [int]($TimeoutSeconds / 2))))
            return "npm"
        } catch {
            Write-Host "     npm install ignore : $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }

    Write-Host "     Impossible d'installer les deps frontend (pnpm/npm absents)." `
        -ForegroundColor DarkYellow
    return $null
}

#endregion Frontend tooling

