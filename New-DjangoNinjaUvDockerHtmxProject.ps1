#Requires -Version 5.1
<#
.SYNOPSIS
  Cree un projet Django Ninja + uv + HTMX + Astro optionnel + Docker.

.DESCRIPTION
  Orchestrateur mince : dot-source des modules scaffold/, puis pipeline.
  Stack : Django a la racine, HTMX (UI interne) toujours, Astro (UI produit) optionnel,
  admin_panel optionnel, Docker Compose (db, redis, web, frontend, worker, beat).

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
  Ignore l'admin custom (pas de apps/admin_panel ni /api/admin/).

.PARAMETER UseCustomAdmin
  Force l'admin custom admin_panel + API /api/admin/.

.PARAMETER SkipFrontend
  Ignore la generation Astro (frontend/).

.PARAMETER UseAstro
  Force la generation Astro (desactive la question interactive).

.PARAMETER UseNextJs
  Alias deprecie de -UseAstro (meme effet + avertissement).

.PARAMETER SkipDocker
  Ignore Docker (Dockerfile, compose).

.PARAMETER SkipFrontendDeps
  N'installe pas les deps Node a l'init.

.PARAMETER SkipCreatesuperuser
  N'appelle pas manage.py createsuperuser apres les migrations.

.PARAMETER SkipMigrate
  Ignore la migration initiale Django.

.PARAMETER CommandTimeoutSeconds
  Timeout des commandes longues (uv, pnpm/npm) en secondes (defaut : 900s).

.PARAMETER NoInteractive
  Desactive les questions interactives. Defaut sans flags : Astro + admin custom.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\New-DjangoNinjaUvDockerHtmxProject.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\New-DjangoNinjaUvDockerHtmxProject.ps1 -NewFolder mon_site -NoInteractive -UseAstro -UseCustomAdmin
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\New-DjangoNinjaUvDockerHtmxProject.ps1 -NewFolder mon_site -NoInteractive -SkipFrontend -SkipCustomAdmin
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
    [switch]$UseAstro,
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
$ProgressPreference = "SilentlyContinue"
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
$script:PipelineTotal = 11
$script:PipelineStep = 0
$script:StepWatch = $null

# --- Dot-source modules scaffold/ (ordre impose) ---
$scaffoldDir = Join-Path $PSScriptRoot "scaffold"
$scaffoldModules = @(
    "Common.ps1",
    "Pipeline.ps1",
    "DjangoConfig.ps1",
    "AdminPanel.ps1",
    "HtmxConsole.ps1",
    "HtmxUi.ps1",
    "AstroFrontend.ps1",
    "Docker.ps1",
    "Quality.ps1",
    "CursorRules.ps1"
)
foreach ($mod in $scaffoldModules) {
    $modPath = Join-Path $scaffoldDir $mod
    if (-not (Test-Path -LiteralPath $modPath)) {
        throw "Module scaffold introuvable : $modPath"
    }
    . $modPath
}

# Alias deprecie -UseNextJs -> meme effet que -UseAstro
$forceAstro = $UseAstro.IsPresent
if ($UseNextJs.IsPresent) {
    Write-Host "  Avertissement : -UseNextJs est deprecie ; utilisez -UseAstro (meme effet, stack Astro)." -ForegroundColor DarkYellow
    $forceAstro = $true
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

    # uv exige un nom de package qui commence et finit par lettre/chiffre.
    $uvName = (Split-Path -Leaf $root) -replace '[^a-zA-Z0-9._-]', '-'
    $uvName = $uvName.Trim('._-')
    if ([string]::IsNullOrWhiteSpace($uvName)) { $uvName = "project" }
    if ($uvName -match '^[0-9]') { $uvName = "p$uvName" }

    $wantsAstro = $false
    if ($SkipFrontend.IsPresent -and $forceAstro) {
        Write-Host "  Avertissement : -SkipFrontend et -UseAstro/-UseNextJs ignores (-SkipFrontend prioritaire)." -ForegroundColor DarkYellow
        $wantsAstro = $false
    } elseif ($SkipFrontend.IsPresent) {
        $wantsAstro = $false
    } elseif ($forceAstro) {
        $wantsAstro = $true
    } elseif (-not $NoInteractive.IsPresent) {
        $wantsAstro = Read-YesNoPrompt `
            -Prompt "Utiliser Astro pour l'UI produit + DataStudio ?" `
            -DefaultYes:$true
        if ($wantsAstro) {
            Write-Host "  Frontend retenu : Astro UI produit + DataStudio (/admin, /login) :4321" -ForegroundColor Cyan
        } else {
            Write-Host "  Frontend retenu : pas de frontend/ (HTMX interne uniquement)" -ForegroundColor Cyan
        }
    } else {
        $wantsAstro = $true
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
        $wantsCustomAdmin = Read-YesNoPrompt `
            -Prompt "Utiliser l'admin custom (admin_panel + API /api/admin/) ?" `
            -DefaultYes:$true
        if ($wantsCustomAdmin) {
            Write-Host "  Admin retenu : admin_panel + API /api/admin/" -ForegroundColor Cyan
        } else {
            Write-Host "  Admin retenu : django.contrib.admin (/django-admin/)" -ForegroundColor Cyan
        }
    } else {
        $wantsCustomAdmin = $true
    }

    if ($wantsAstro -and -not $wantsCustomAdmin) {
        Write-Host "  Avertissement : DataStudio Astro consomme /api/admin/ - sans admin custom, /admin ne sera pas fonctionnel." -ForegroundColor DarkYellow
    }

    $doCustomAdmin = $wantsCustomAdmin
    $doFrontend = $wantsAstro
    $doDocker = -not $SkipDocker.IsPresent

    # Etapes : uv, config, app, HTMX, [admin], [Astro], [Docker+env], cursor, qualite, structure, migrate, [superuser]
    $script:PipelineTotal = 8
    if ($doCustomAdmin) { $script:PipelineTotal++ }
    if ($doFrontend) { $script:PipelineTotal++ }
    if ($doDocker) { $script:PipelineTotal += 2 }
    if (-not $SkipCreatesuperuser.IsPresent) { $script:PipelineTotal++ }

    Write-PipelineBanner -Subtitle "App: $AppName | Astro: $doFrontend | Admin: $doCustomAdmin | Docker: $doDocker"

    Start-PipelineStep -Title "Environnement uv" -Detail "init + dependances runtime et dev"
    Initialize-UvProject -Root $root -UvName $uvName -HasCustomAdmin:$doCustomAdmin -HasDocker:$doDocker
    Complete-PipelineStep -Message "pyproject.toml + uv.lock"

    Start-PipelineStep -Title "Configuration Django" -Detail "config/ + settings dev|qua|prod"
    New-DjangoConfigPackage -Root $root -AppName $AppName `
        -HasCustomAdmin:$doCustomAdmin -HasFrontend:$doFrontend -HasDocker:$doDocker
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
    New-AppServiceLayer -Root $root -AppName $AppName `
        -HasCustomAdmin:$doCustomAdmin -HasFrontend:$doFrontend
    if ($doDocker) {
        New-CoreCeleryFiles -Root $root -AppName $AppName
    }
    New-CoreModels -Root $root -AppName $AppName -HasCustomAdmin:$doCustomAdmin
    if (-not $doCustomAdmin) {
        New-DjangoNativeAdmin -Root $root -AppName $AppName
    }
    Complete-PipelineStep

    Start-PipelineStep -Title "UI HTMX interne" -Detail "templates + SCSS 7-1 + CBV back-office"
    New-HtmxUiScaffold -Root $root -AppName $AppName `
        -HasFrontend:$doFrontend -HasCustomAdmin:$doCustomAdmin
    Complete-PipelineStep

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
        New-HtmxConsoleScaffold -Root $root -HasCustomAdmin:$true
        Complete-PipelineStep
    } else {
        Write-Host "     (admin custom desactive - django.contrib.admin)" -ForegroundColor DarkYellow
    }

    if ($doFrontend) {
        Start-PipelineStep -Title "Frontend Astro" -Detail "UI produit :4321 (zero React, Console HTMX :8000/console/)"
        New-AstroFrontend -Root $root -ProjectSlug $uvName -AppName $AppName `
            -HasCustomAdmin:$doCustomAdmin
        New-DevLocalScript -Root $root -HasDocker:$doDocker -HasCustomAdmin:$doCustomAdmin
        $pkgMgr = $null
        if (-not $SkipFrontendDeps.IsPresent) {
            try {
                $pkgMgr = Install-FrontendDependencies `
                    -FrontendRoot (Join-Path $root "frontend") `
                    -TimeoutSeconds $CommandTimeoutSeconds
            } catch {
                Write-Host "     deps frontend ignore : $($_.Exception.Message)" -ForegroundColor DarkYellow
                $pkgMgr = $null
            }
        } else {
            Write-Host "     (-SkipFrontendDeps) : pas de lockfile - le build Docker frontend sera plus lent." -ForegroundColor DarkYellow
        }
        Complete-PipelineStep -Message $(
            if ($pkgMgr) { "deps $pkgMgr + lockfile + scripts/dev-local.ps1" }
            else { "squelette Astro + scripts/dev-local.ps1" }
        )
    }

    if ($doDocker) {
        Start-PipelineStep -Title "Docker" -Detail "Dockerfile uv + compose (db/redis/web/frontend/worker/beat)"
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
    New-CursorProjectRules -Root $root -AppName $AppName `
        -HasCustomAdmin:$doCustomAdmin -HasFrontend:$doFrontend
    Complete-PipelineStep

    Start-PipelineStep -Title "Qualite et documentation" -Detail "pytest, ruff, README, .gitignore"
    New-QualityTooling -Root $root -HasCustomAdmin:$doCustomAdmin
    New-RootGitignore -Root $root
    New-ProjectReadme -Root $root -AppName $AppName `
        -HasCustomAdmin $doCustomAdmin -HasFrontend $doFrontend -HasDocker $doDocker
    $corsExample = Get-CorsOrigins -HasFrontend $doFrontend
    $astroEnvBlock = if ($doFrontend) {
        @"

# Astro (frontend/.env) - secrets jamais dans PUBLIC_*
# PUBLIC_API_URL=http://localhost:8000
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

# Celery (si Docker)
# CELERY_BROKER_URL=redis://localhost:6379/0
# CELERY_RESULT_BACKEND=redis://localhost:6379/0
$astroEnvBlock
"@
    Complete-PipelineStep

    Start-PipelineStep -Title "Verification structure" -Detail "fichiers obligatoires"
    Test-ProjectStructure -Root $root -AppName $AppName `
        -ExpectCustomAdmin $doCustomAdmin -ExpectFrontend $doFrontend -ExpectDocker $doDocker
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
            "createsuperuser pour /login Astro"
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

    Write-PipelineSummary -Root $root -AppName $AppName `
        -HasCustomAdmin $doCustomAdmin -HasFrontend $doFrontend -HasDocker $doDocker
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
