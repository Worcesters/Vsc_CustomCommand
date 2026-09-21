#Requires -Version 5.1
<#
.SYNOPSIS
  Compose locaux (backend/, frontend/) et compose global (include).
#>

function Write-SplitComposeFiles {
    <#
    .SYNOPSIS
      Ecrit docker-compose.yml / .prod.yml dans backend, frontend (optionnel) et a la racine.
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$BackendDirName,
        [string]$FrontendDirName = "frontend",
        [int]$PostgresHostPort = 5433,
        [bool]$HasFrontend = $true
    )

    $backendDir = Join-Path $Root $BackendDirName
    $corsOrigins = Get-CorsOrigins -HasFrontend $HasFrontend

    $backendDev = Get-BackendComposeDevYaml -PostgresHostPort $PostgresHostPort -CorsOrigins $corsOrigins
    Write-TextFile -Path (Join-Path $backendDir "docker-compose.yml") -Content $backendDev
    Write-TextFile -Path (Join-Path $backendDir "docker-compose.prod.yml") -Content (Get-BackendComposeProdYaml)

    if ($HasFrontend) {
        $feDir = Join-Path $Root $FrontendDirName
        New-Item -ItemType Directory -Path $feDir -Force | Out-Null
        Write-TextFile -Path (Join-Path $feDir "docker-compose.yml") -Content (Get-FrontendComposeDevYaml)
        Write-TextFile -Path (Join-Path $feDir "docker-compose.prod.yml") -Content (Get-FrontendComposeProdYaml)
    }

    $globalDev = Get-GlobalComposeYaml `
        -BackendDirName $BackendDirName `
        -FrontendDirName $FrontendDirName `
        -HasFrontend $HasFrontend `
        -Prod:$false
    $globalProd = Get-GlobalComposeYaml `
        -BackendDirName $BackendDirName `
        -FrontendDirName $FrontendDirName `
        -HasFrontend $HasFrontend `
        -Prod:$true

    Write-TextFile -Path (Join-Path $Root ".gitattributes") -Content @'
# Scripts shell : LF obligatoire pour Docker/Linux
*.sh text eol=lf
'@
    Write-TextFile -Path (Join-Path $Root "docker-compose.yml") -Content $globalDev
    Write-TextFile -Path (Join-Path $Root "docker-compose.dev.yml") -Content $globalDev
    Write-TextFile -Path (Join-Path $Root "docker-compose.prod.yml") -Content $globalProd
}

function Get-GlobalComposeYaml {
    param(
        [Parameter(Mandatory)][string]$BackendDirName,
        [string]$FrontendDirName = "frontend",
        [bool]$HasFrontend = $true,
        [bool]$Prod = $false
    )
    $suffix = if ($Prod) { ".prod.yml" } else { ".yml" }
    $lines = @(
        "# Compose global : inclut les fichiers locaux.",
        "# Usage : docker compose up --build",
        "# Backend seul : cd $BackendDirName && docker compose up --build  (uv sync --frozen a chaque up)",
        "# Ne pas lancer racine ET sous-dossier en parallele (conflit de ports)."
    )
    if ($HasFrontend) {
        $lines += "# Frontend seul : cd $FrontendDirName && docker compose up --build"
    }
    $lines += @(
        "include:",
        "  - path: ./$BackendDirName/docker-compose$suffix"
    )
    if ($HasFrontend) {
        $lines += @(
            "  - path: ./$FrontendDirName/docker-compose$suffix",
            "",
            "services:",
            "  frontend:",
            "    depends_on:",
            "      web:",
            "        condition: service_healthy"
        )
    }
    return ($lines -join "`n") + "`n"
}

function Get-BackendComposeDevYaml {
    param(
        [int]$PostgresHostPort = 5433,
        [Parameter(Mandatory)][string]$CorsOrigins
    )
    $yaml = @'
# Stack Django : db, redis, web, worker, beat.
# Chaque `up` execute `uv sync --frozen` (web via docker-web-dev.sh, worker/beat via docker-uv-sync.sh).
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
    command:
      [
        "/bin/sh",
        "scripts/docker-uv-sync.sh",
        "uv",
        "run",
        "celery",
        "-A",
        "config",
        "worker",
        "-l",
        "info",
      ]
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

  beat:
    build:
      context: .
      dockerfile: Dockerfile
      target: dev
    command:
      [
        "/bin/sh",
        "scripts/docker-uv-sync.sh",
        "uv",
        "run",
        "celery",
        "-A",
        "config",
        "beat",
        "-l",
        "info",
      ]
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

volumes:
  pgdata:
  backend_venv:
'@
    $yaml = $yaml -replace 'POSTGRES_HOST_PORT', [string]$PostgresHostPort
    $yaml = $yaml -replace 'CORS_ORIGINS_PLACEHOLDER', $CorsOrigins
    return $yaml
}

function Get-BackendComposeProdYaml {
    return @'
# Stack Django prod : db, redis, web, worker, beat. `uv sync --frozen` a chaque up.
services:
  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: ${POSTGRES_DB:-app}
      POSTGRES_USER: ${POSTGRES_USER:-app}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?required}
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-app} -d ${POSTGRES_DB:-app}"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5

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
      CELERY_BROKER_URL: ${CELERY_BROKER_URL:-redis://redis:6379/0}
      CELERY_RESULT_BACKEND: ${CELERY_RESULT_BACKEND:-redis://redis:6379/0}
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
    ports:
      - "8000:8000"
    healthcheck:
      test:
        [
          "CMD-SHELL",
          "python -c \"import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/health/', timeout=3)\"",
        ]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 90s

  worker:
    build:
      context: .
      dockerfile: Dockerfile
      target: prod
    command:
      [
        "/bin/sh",
        "scripts/docker-uv-sync.sh",
        "uv",
        "run",
        "celery",
        "-A",
        "config",
        "worker",
        "-l",
        "info",
      ]
    environment:
      DJANGO_ENV: prod
      DJANGO_SECRET_KEY: ${DJANGO_SECRET_KEY:?required}
      DJANGO_USE_POSTGRES: "1"
      DJANGO_DB_ENGINE: django.db.backends.postgresql
      DJANGO_DB_NAME: ${POSTGRES_DB:-app}
      DJANGO_DB_USER: ${POSTGRES_USER:-app}
      DJANGO_DB_PASSWORD: ${POSTGRES_PASSWORD:?required}
      DJANGO_DB_HOST: db
      CELERY_BROKER_URL: ${CELERY_BROKER_URL:-redis://redis:6379/0}
      CELERY_RESULT_BACKEND: ${CELERY_RESULT_BACKEND:-redis://redis:6379/0}
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy

  beat:
    build:
      context: .
      dockerfile: Dockerfile
      target: prod
    command:
      [
        "/bin/sh",
        "scripts/docker-uv-sync.sh",
        "uv",
        "run",
        "celery",
        "-A",
        "config",
        "beat",
        "-l",
        "info",
      ]
    environment:
      DJANGO_ENV: prod
      DJANGO_SECRET_KEY: ${DJANGO_SECRET_KEY:?required}
      DJANGO_USE_POSTGRES: "1"
      DJANGO_DB_ENGINE: django.db.backends.postgresql
      DJANGO_DB_NAME: ${POSTGRES_DB:-app}
      DJANGO_DB_USER: ${POSTGRES_USER:-app}
      DJANGO_DB_PASSWORD: ${POSTGRES_PASSWORD:?required}
      DJANGO_DB_HOST: db
      CELERY_BROKER_URL: ${CELERY_BROKER_URL:-redis://redis:6379/0}
      CELERY_RESULT_BACKEND: ${CELERY_RESULT_BACKEND:-redis://redis:6379/0}
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy

volumes:
  pgdata:
'@
}

function Get-FrontendComposeDevYaml {
    return @'
# Stack Astro (dev :4321). API Django via localhost:8000 (backend deja up, ou compose global).
services:
  frontend:
    build:
      context: .
      dockerfile: Dockerfile
      target: dev
    extra_hosts:
      - "host.docker.internal:host-gateway"
    command: ["/bin/sh", "scripts/docker-entrypoint-dev.sh"]
    volumes:
      - .:/app
      - /app/node_modules
    environment:
      CI: "true"
      PUBLIC_API_URL: http://localhost:8000
      HOST: "0.0.0.0"
      PORT: "4321"
    ports:
      - "4321:4321"
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:4321/ || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 8
      start_period: 90s
    restart: unless-stopped
'@
}

function Get-FrontendComposeProdYaml {
    return @'
# Stack Astro prod (static dist via serve :4321).
services:
  frontend:
    build:
      context: .
      dockerfile: Dockerfile
      target: runner
      args:
        PUBLIC_API_URL: ${PUBLIC_API_URL:-http://localhost:8000}
    environment:
      HOST: "0.0.0.0"
      PORT: "4321"
    ports:
      - "4321:4321"
'@
}
