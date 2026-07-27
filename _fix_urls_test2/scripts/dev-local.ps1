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
Write-Host '  Frontend : http://127.0.0.1:4321'Write-Host '  Console  : http://127.0.0.1:8000/console/'
Write-Host '  Login    : http://127.0.0.1:8000/accounts/login/'Write-Host ''
Write-Host 'Si le port 4321 reste inaccessible, verifiez la fenetre frontend (erreur pnpm/node).'