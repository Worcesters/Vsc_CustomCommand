#Requires -Version 5.1
<#
.SYNOPSIS
  Genere Dockerfile racine + docker-compose (db, redis, web, frontend, worker, beat).

.NOTES
  Layout (Architect) : Django a la RACINE - Docker context = "."
  (Dockerfile a la racine, PAS backend/Dockerfile).
  CORS Astro :4321 deja dans Common.Get-CorsOrigins / Write-ProjectDotEnvForDocker.
  Helpers Postgres (Start-ComposeDatabaseService, etc.) vivent dans Common.ps1
  pour le flux migrate - ne pas les redefinir ici.
#>

function New-DockerStack {
    <#
    .SYNOPSIS
      Dockerfile multi-stage uv + compose (db, redis, web, frontend Astro, worker, beat).

    .PARAMETER Root
      Racine du projet genere.

    .PARAMETER PostgresHostPort
      Port hote mappe vers 5432 du service db.

    .PARAMETER HasFrontend
      Inclure service frontend Astro si vrai.
    #>
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
# Entree Docker dev frontend Astro : deps dans l''image + reparation non interactive si volume vide.
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
elif [ ! -e node_modules/astro ] && [ ! -e node_modules/.pnpm ]; then
  echo "node_modules incomplet - reinstallation pnpm..."
  pnpm_install_safe
fi

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

        Write-TextFile -Path (Join-Path $Root "frontend\Dockerfile") -Content @'
# Frontend Astro — Node 22 (dev = astro dev :4321 ; runner = static dist via serve)
FROM node:22-alpine AS base
WORKDIR /app
RUN apk add --no-cache wget \
    && corepack enable && corepack prepare pnpm@9.15.9 --activate

FROM base AS deps
COPY package.json pnpm-lock.yaml* .npmrc* ./
RUN if [ -f pnpm-lock.yaml ]; then pnpm install --frozen-lockfile; else pnpm install; fi

FROM deps AS dev
COPY . .
ENV HOST=0.0.0.0 PORT=4321 CI=true
EXPOSE 4321
CMD ["pnpm", "dev"]

FROM deps AS build
COPY . .
ARG PUBLIC_API_URL=http://localhost:8000
ENV PUBLIC_API_URL=$PUBLIC_API_URL
RUN pnpm build

FROM node:22-alpine AS runner
WORKDIR /app
RUN apk add --no-cache wget \
    && addgroup -S app && adduser -S app -G app \
    && npm install -g serve@14
COPY --from=build --chown=app:app /app/dist ./dist
USER app
ENV HOST=0.0.0.0 PORT=4321 NODE_ENV=production
EXPOSE 4321
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:4321/ || exit 1
CMD ["serve", "-s", "dist", "-l", "4321"]
'@

        Write-TextFile -Path (Join-Path $Root "frontend\.dockerignore") -Content @'
node_modules/
dist/
.astro/
.git/
.env
.env.local
*.log
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

    # Multi-stage uv : base (git) -> builder -> dev (compose) / prod (non-root).
    Write-TextFile -Path (Join-Path $Root "Dockerfile") -Content @'
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS base
WORKDIR /app
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy PYTHONUNBUFFERED=1
# Git requis : uv sync peut installer des deps depuis git+https://github.com/...
RUN apt-get update \
    && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

FROM base AS builder
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-install-project --no-dev || uv sync --no-install-project --no-dev
COPY . .
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev || uv sync --no-dev

FROM base AS dev
COPY pyproject.toml uv.lock ./
RUN uv sync
EXPOSE 8000
CMD ["uv", "run", "python", "manage.py", "runserver", "0.0.0.0:8000"]

FROM base AS prod
COPY --from=builder /app /app
RUN groupadd -r app && useradd -r -g app -d /app app \
    && chown -R app:app /app
ENV PATH="/app/.venv/bin:$PATH"
USER app
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/health/')"
CMD ["gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "4"]
'@

    Write-TextFile -Path (Join-Path $Root ".dockerignore") -Content @'
.venv/
__pycache__/
*.pyc
db.sqlite3
staticfiles/
.git/
frontend/node_modules/
frontend/dist/
frontend/.astro/
.env
.pytest_cache/
.mypy_cache/
.ruff_cache/
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

  beat:
    build:
      context: .
      dockerfile: Dockerfile
      target: dev
    command: ["uv", "run", "celery", "-A", "config", "beat", "-l", "info"]
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
    environment:
      CI: "true"
      PUBLIC_API_URL: http://localhost:8000
      HOST: "0.0.0.0"
      PORT: "4321"
    ports:
      - "4321:4321"
    depends_on:
      web:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:4321/ || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 8
      start_period: 90s
    restart: unless-stopped

'@
    }

    if ($HasFrontend) {
        $composeDev += @'
volumes:
  pgdata:
  backend_venv:
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
    # Alias playbook skill : docker-compose.dev.yml = meme stack dev
    Write-TextFile -Path (Join-Path $Root "docker-compose.dev.yml") -Content $composeDev

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

  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile
      target: runner
      args:
        PUBLIC_API_URL: ${PUBLIC_API_URL:-http://localhost:8000}
    environment:
      HOST: "0.0.0.0"
      PORT: "4321"
    ports:
      - "4321:4321"
    depends_on:
      web:
        condition: service_healthy

  worker:
    build:
      context: .
      dockerfile: Dockerfile
      target: prod
    command: ["celery", "-A", "config", "worker", "-l", "info"]
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
    command: ["celery", "-A", "config", "beat", "-l", "info"]
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
    command: ["celery", "-A", "config", "worker", "-l", "info"]
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
    command: ["celery", "-A", "config", "beat", "-l", "info"]
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

    Write-TextFile -Path (Join-Path $Root "docker-compose.prod.yml") -Content $composeProd
}
