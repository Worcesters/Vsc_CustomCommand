#Requires -Version 5.1
<#
.SYNOPSIS
  Genere l'UI interne Django HTMX (templates, partials, SCSS 7-1, Alpine).

.DESCRIPTION
  Surface staff / back-office uniquement (pas l'UI produit Astro).
  Depend de Common.ps1 (Write-TextFile, Resolve-NodeToolPath, Invoke-NativeCli)
  au runtime (dot-source par l'orchestrateur).
  Settings django_htmx + HtmxMiddleware deja poses par DjangoConfig.ps1.

.NOTES
  DataStudio admin BDD = Console HTMX (/admin/) si HasCustomAdmin.
  Generation console : New-HtmxConsoleScaffold (HtmxConsole.ps1).
#>

function Get-BrandCharteTokensScss {
    <#
    .SYNOPSIS
      Tokens :root Flat High-End (zinc/slate) pour SCSS 7-1.
    #>
    @'
:root {
  /* ================================================================
     PALETTE PRINCIPALE - source de verite unique (zinc / slate).
     ================================================================ */
  --brand-bg: #fafafa;
  --brand-panel: #ffffff;
  --brand-text: #18181b;
  --brand-text-muted: #71717a;
  --brand-accent: #3f3f46;

  --color-bg: var(--brand-bg);
  --color-surface: var(--brand-panel);
  --color-sidebar: #f4f4f5;
  --color-text: var(--brand-text);
  --color-text-muted: var(--brand-text-muted);
  --color-border: #e4e4e7;

  --primary-color: #27272a;
  --primary-color-hover: #18181b;
  --primary-color-active: #09090b;
  --primary-color-on: #fafafa;

  --secondary-color: #f4f4f5;
  --secondary-color-hover: #e4e4e7;
  --secondary-color-active: #d4d4d8;
  --secondary-color-on: #18181b;

  --accent-color: #52525b;
  --accent-color-hover: #3f3f46;
  --accent-color-active: #27272a;
  --accent-color-on: #fafafa;

  --success-color: #15803d;
  --warning-color: #a16207;
  --danger-color: #b91c1c;
  --info-color: #1d4ed8;

  --focus-ring: 0 0 0 2px color-mix(in srgb, var(--primary-color) 35%, transparent);
  --space-1: 0.25rem;
  --space-2: 0.5rem;
  --space-3: 0.75rem;
  --space-4: 1rem;
  --space-5: 1.25rem;
  --space-6: 1.5rem;
  --space-8: 2rem;
  --space-10: 2.5rem;
  --space-12: 3rem;
  --space-16: 4rem;
  --radius-sm: 0.25rem;
  --radius-md: 0.375rem;
  --radius-lg: 0.5rem;
  --font-sans: "Geist", "Inter", system-ui, sans-serif;
  --font-mono: "JetBrains Mono", ui-monospace, monospace;
  --transition-fast: 150ms ease;
  --z-header: 20;
}

[data-theme="dark"] {
  --brand-bg: #09090b;
  --brand-panel: #18181b;
  --brand-text: #fafafa;
  --brand-text-muted: #a1a1aa;
  --brand-accent: #e4e4e7;
  --color-bg: var(--brand-bg);
  --color-surface: var(--brand-panel);
  --color-sidebar: #111113;
  --color-text: var(--brand-text);
  --color-text-muted: var(--brand-text-muted);
  --color-border: #27272a;
  --primary-color: #e4e4e7;
  --primary-color-hover: #fafafa;
  --primary-color-active: #d4d4d8;
  --primary-color-on: #09090b;
  --secondary-color: #27272a;
  --secondary-color-hover: #3f3f46;
  --secondary-color-active: #52525b;
  --secondary-color-on: #fafafa;
  --accent-color: #a1a1aa;
  --accent-color-hover: #d4d4d8;
  --accent-color-active: #e4e4e7;
  --accent-color-on: #09090b;
  --space-5: 1.25rem;
  --space-10: 2.5rem;
  --space-12: 3rem;
  --space-16: 4rem;
}

::selection {
  background: var(--primary-color);
  color: var(--primary-color-on);
}

[x-cloak] {
  display: none !important;
}
'@
}

function Get-BrandButtonsScss {
    <#
    .SYNOPSIS
      Composants boutons BEM (Flat High-End).
    #>
    @'
.btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: var(--space-2);
  padding: var(--space-3) var(--space-4);
  border-radius: var(--radius-md);
  border: 1px solid transparent;
  font-weight: 600;
  font-size: 0.875rem;
  line-height: 1.25;
  text-decoration: none;
  cursor: pointer;
  transition:
    background var(--transition-fast),
    color var(--transition-fast),
    border-color var(--transition-fast);
}

.btn:focus-visible {
  outline: none;
  box-shadow: var(--focus-ring);
}

.btn--primary {
  background: var(--primary-color);
  color: var(--primary-color-on);
}

.btn--primary:hover {
  background: var(--primary-color-hover);
}

.btn--secondary {
  background: transparent;
  color: var(--color-text);
  border-color: var(--color-border);
}

.btn--secondary:hover {
  background: var(--secondary-color);
  border-color: var(--accent-color);
}

.btn--ghost {
  background: transparent;
  color: var(--color-text-muted);
  border-color: transparent;
}

.btn--ghost:hover {
  color: var(--color-text);
  background: var(--secondary-color);
}

.btn--sm {
  padding: var(--space-2) var(--space-3);
  font-size: 0.8125rem;
}
'@
}

function Get-BrandHomePageScss {
    <#
    .SYNOPSIS
      Styles page d'accueil Django (BEM, mobile-first).
    #>
    @'
@keyframes home-rise {
  from {
    opacity: 0;
    transform: translateY(0.75rem);
  }

  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.page-home {
  position: relative;
  min-height: calc(100vh - 3.5rem);
  overflow: hidden;
  background: var(--color-bg);
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
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  background: var(--color-surface);
  animation: home-rise 0.55s ease-out both;
}

.page-home__eyebrow {
  margin: 0;
  font-size: 0.75rem;
  font-weight: 600;
  color: var(--color-text-muted);
  text-transform: uppercase;
  letter-spacing: 0.1em;
}

.page-home__title {
  margin: 0;
  font-size: clamp(1.75rem, 4vw, 2.5rem);
  line-height: 1.15;
  color: var(--color-text);
}

.page-home__lead {
  margin: 0;
  max-width: 40rem;
  color: var(--color-text-muted);
  line-height: 1.55;
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

@include respond-to(md) {
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
  animation: home-rise 0.55s ease-out both;
}

.page-home__card:nth-child(1) {
  animation-delay: 0.08s;
}

.page-home__card:nth-child(2) {
  animation-delay: 0.16s;
}

.page-home__card:nth-child(3) {
  animation-delay: 0.24s;
}

.page-home__card-title {
  margin: 0 0 var(--space-2);
  font-size: 1rem;
  color: var(--color-text);
}

.page-home__card-text {
  margin: 0;
  color: var(--color-text-muted);
  font-size: 0.9375rem;
  line-height: 1.5;
}

@media (prefers-reduced-motion: reduce) {
  .page-home__hero,
  .page-home__card {
    animation: none;
  }
}
'@
}

function Get-BackofficeScss {
    <#
    .SYNOPSIS
      Styles shell + liste/detail back-office HTMX.
    #>
    @'
.site-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-4);
  padding: var(--space-3) var(--space-4);
  border-bottom: 1px solid var(--color-border);
  background: var(--color-surface);
  position: sticky;
  top: 0;
  z-index: var(--z-header);
}

.site-header__brand {
  font-weight: 700;
  font-size: 0.9375rem;
  color: var(--color-text);
  text-decoration: none;
}

.site-header__nav {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-2);
  align-items: center;
}

.site-header__link {
  color: var(--color-text-muted);
  text-decoration: none;
  font-size: 0.875rem;
  padding: var(--space-2) var(--space-3);
  border-radius: var(--radius-md);
}

.site-header__link:hover,
.site-header__link--active {
  color: var(--color-text);
  background: var(--secondary-color);
}

.layout-main {
  min-height: calc(100vh - 3.5rem);
}

.backoffice {
  display: flex;
  flex-direction: column;
  min-height: calc(100vh - 3.5rem);
  background: var(--color-bg);
}

@include respond-to(md) {
  .backoffice {
    flex-direction: row;
  }
}

.backoffice__sidebar {
  display: flex;
  flex-direction: column;
  gap: var(--space-4);
  padding: var(--space-4);
  border-bottom: 1px solid var(--color-border);
  background: var(--color-sidebar);
}

@include respond-to(md) {
  .backoffice__sidebar {
    width: 16rem;
    flex-shrink: 0;
    border-bottom: none;
    border-right: 1px solid var(--color-border);
  }
}

.backoffice__title {
  margin: 0;
  font-size: 1rem;
  font-weight: 700;
  color: var(--color-text);
}

.backoffice__meta {
  margin: 0;
  font-size: 0.8125rem;
  color: var(--color-text-muted);
}

.backoffice__main {
  flex: 1;
  display: flex;
  flex-direction: column;
  min-width: 0;
}

.backoffice__toolbar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--space-3);
  padding: var(--space-4);
  border-bottom: 1px solid var(--color-border);
  background: var(--color-surface);
}

.backoffice__search {
  flex: 1;
  min-width: 12rem;
  padding: var(--space-2) var(--space-3);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  background: var(--color-bg);
  color: var(--color-text);
  font-size: 0.875rem;
}

.backoffice__search:focus-visible {
  outline: none;
  border-color: var(--accent-color);
  box-shadow: var(--focus-ring);
}

.backoffice__body {
  display: flex;
  flex-direction: column;
  flex: 1;
  min-height: 0;
}

@include respond-to(lg) {
  .backoffice__body {
    flex-direction: row;
  }
}

.backoffice__list-panel {
  flex: 1;
  padding: var(--space-4);
  border-bottom: 1px solid var(--color-border);
  overflow: auto;
}

@include respond-to(lg) {
  .backoffice__list-panel {
    border-bottom: none;
    border-right: 1px solid var(--color-border);
    max-width: 28rem;
  }
}

.backoffice__detail {
  flex: 1;
  padding: var(--space-4);
  overflow: auto;
  background: var(--color-bg);
}

.item-list {
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
  margin: 0;
  padding: 0;
  list-style: none;
}

.item-list__row {
  display: flex;
  flex-direction: column;
  gap: var(--space-1);
  width: 100%;
  padding: var(--space-3) var(--space-4);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  background: var(--color-surface);
  text-align: left;
  cursor: pointer;
  color: inherit;
  font: inherit;
  transition: border-color var(--transition-fast), background var(--transition-fast);
}

.item-list__row:hover,
.item-list__row--active {
  border-color: var(--accent-color);
  background: color-mix(in srgb, var(--secondary-color) 80%, var(--color-surface));
}

.item-list__row.htmx-request {
  opacity: 0.65;
}

.item-list__title {
  margin: 0;
  font-size: 0.9375rem;
  font-weight: 600;
  color: var(--color-text);
}

.item-list__meta {
  margin: 0;
  font-size: 0.75rem;
  color: var(--color-text-muted);
}

.item-list__empty {
  margin: 0;
  padding: var(--space-6);
  text-align: center;
  color: var(--color-text-muted);
  border: 1px dashed var(--color-border);
  border-radius: var(--radius-md);
}

.item-detail {
  display: flex;
  flex-direction: column;
  gap: var(--space-4);
  padding: var(--space-6);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  background: var(--color-surface);
}

.item-detail__eyebrow {
  margin: 0;
  font-size: 0.75rem;
  font-weight: 600;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--color-text-muted);
}

.item-detail__title {
  margin: 0;
  font-size: 1.25rem;
  color: var(--color-text);
}

.item-detail__body {
  margin: 0;
  color: var(--color-text-muted);
  line-height: 1.55;
}

.item-detail__badge {
  display: inline-flex;
  align-items: center;
  padding: var(--space-1) var(--space-3);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-sm);
  font-size: 0.75rem;
  font-weight: 600;
  color: var(--color-text);
  background: var(--secondary-color);
  width: fit-content;
}

.item-detail__placeholder {
  margin: 0;
  padding: var(--space-8);
  text-align: center;
  color: var(--color-text-muted);
  border: 1px dashed var(--color-border);
  border-radius: var(--radius-lg);
  background: var(--color-surface);
}

.flash {
  margin: 0;
  padding: var(--space-3) var(--space-4);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  background: var(--secondary-color);
  color: var(--color-text);
  font-size: 0.875rem;
}

.flash--success {
  border-color: color-mix(in srgb, var(--success-color) 40%, var(--color-border));
  color: var(--success-color);
}

.htmx-indicator {
  display: none;
  font-size: 0.75rem;
  color: var(--color-text-muted);
}

.htmx-request .htmx-indicator,
.htmx-indicator.htmx-request {
  display: inline;
}

.visually-hidden {
  position: absolute;
  width: 1px;
  height: 1px;
  padding: 0;
  margin: -1px;
  overflow: hidden;
  clip: rect(0, 0, 0, 0);
  white-space: nowrap;
  border: 0;
}
'@
}

function Write-MinimalMainCssFallback {
    <#
    .SYNOPSIS
      Genere static/css/main.css sans compilateur sass (tokens + boutons + shell).
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [bool]$HasCustomAdmin = $true
    )

    $cssPath = Join-Path $Root "static\css\main.css"
    # Versions sans mixin SCSS (media queries brutes) pour le fallback.
    $homeCss = (Get-BrandHomePageScss) -replace '@include respond-to\(md\) \{', '@media (min-width: 48rem) {'
    $boCss = (Get-BackofficeScss) `
        -replace '@include respond-to\(md\) \{', '@media (min-width: 48rem) {' `
        -replace '@include respond-to\(lg\) \{', '@media (min-width: 64rem) {'
    $consoleCss = ""
    if ($HasCustomAdmin -and (Get-Command Get-ConsoleScss -ErrorAction SilentlyContinue)) {
        $consoleCss = (Get-ConsoleTokensScss) + "`n" + (
            (Get-ConsoleScss) `
                -replace '@include respond-to\(sm\) \{', '@media (min-width: 40rem) {' `
                -replace '@include respond-to\(md\) \{', '@media (min-width: 48rem) {' `
                -replace '@include respond-to\(lg\) \{', '@media (min-width: 64rem) {' `
                -replace '@include respond-to\(xl\) \{', '@media (min-width: 80rem) {'
        )
    }
    $content = @"
$(Get-BrandCharteTokensScss)
*,
*::before,
*::after { box-sizing: border-box; }
body {
  font-family: var(--font-sans);
  background: var(--color-bg);
  color: var(--color-text);
  margin: 0;
  line-height: 1.5;
}
$(Get-BrandButtonsScss)
$homeCss
$boCss
$consoleCss
"@
    Write-TextFile -Path $cssPath -Content $content
}

function Invoke-ScssCompile {
    <#
    .SYNOPSIS
      Compile static/scss/main.scss vers static/css/main.css (npx sass).
      Timeout 45s puis fallback CSS minimal si npx/sass bloque.
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [int]$TimeoutSeconds = 45
    )

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

    $job = Start-Job -ScriptBlock {
        param($WorkDir, $Npx)
        Set-Location -LiteralPath $WorkDir
        $ext = [System.IO.Path]::GetExtension($Npx).ToLowerInvariant()
        if ($ext -in @(".cmd", ".bat")) {
            & cmd.exe /d /s /c "`"$Npx`" --yes sass static/scss/main.scss static/css/main.css --no-source-map --style=expanded"
        } else {
            & $Npx --yes sass static/scss/main.scss static/css/main.css --no-source-map --style=expanded
        }
        if ($LASTEXITCODE -ne 0) {
            throw "sass exit $LASTEXITCODE"
        }
    } -ArgumentList $Root, $npxPath

    $completed = Wait-Job -Job $job -Timeout $TimeoutSeconds
    if ($null -eq $completed) {
        Stop-Job -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        Write-Host "     sass timeout (${TimeoutSeconds}s) : CSS minimal genere." -ForegroundColor DarkYellow
        Write-MinimalMainCssFallback -Root $Root
        return
    }

    try {
        Receive-Job -Job $job -ErrorAction Stop | Out-Null
        if (-not (Test-Path -LiteralPath $mainCss)) {
            throw "main.css non produit"
        }
    } catch {
        Write-Host "     sass echoue : $($_.Exception.Message) - CSS minimal genere." -ForegroundColor DarkYellow
        Write-MinimalMainCssFallback -Root $Root
    } finally {
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }
}

function New-StaticScssLayout {
    <#
    .SYNOPSIS
      Architecture SCSS 7-1 + compilation main.css.
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [bool]$HasCustomAdmin = $true
    )

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

    Write-TextFile -Path (Join-Path $scssRoot "abstracts\_index.scss") -Content @'
@forward "mixins";
'@

    Write-TextFile -Path (Join-Path $scssRoot "base\_root.scss") -Content (Get-BrandCharteTokensScss)

    Write-TextFile -Path (Join-Path $scssRoot "base\_reset.scss") -Content @'
*,
*::before,
*::after {
  box-sizing: border-box;
}

html {
  -webkit-text-size-adjust: 100%;
}

body {
  margin: 0;
}

img,
svg {
  display: block;
  max-width: 100%;
}

button,
input,
select,
textarea {
  font: inherit;
}
'@

    Write-TextFile -Path (Join-Path $scssRoot "components\_buttons.scss") -Content (Get-BrandButtonsScss)

    # pages/_home.scss utilise le mixin respond-to → @use abstracts
    $homeScss = @"
@use "../abstracts" as *;

$(Get-BrandHomePageScss)
"@
    Write-TextFile -Path (Join-Path $scssRoot "pages\_home.scss") -Content $homeScss

    $boScss = @"
@use "../abstracts" as *;

$(Get-BackofficeScss)
"@
    Write-TextFile -Path (Join-Path $scssRoot "pages\_backoffice.scss") -Content $boScss

    $consoleUseLine = ""
    if ($HasCustomAdmin -and (Get-Command Get-ConsoleScss -ErrorAction SilentlyContinue)) {
        Write-TextFile -Path (Join-Path $scssRoot "components\_console.scss") -Content @"
@use `"../abstracts`" as *;

$(Get-ConsoleTokensScss)

$(Get-ConsoleScss)
"@
        $consoleUseLine = '@use "components/console";'
    }

    Write-TextFile -Path (Join-Path $scssRoot "themes\_index.scss") -Content "/* Themes supplementaires (data-theme). */`n"
    Write-TextFile -Path (Join-Path $scssRoot "vendors\_index.scss") -Content "/* Vendors tiers si besoin. */`n"
    Write-TextFile -Path (Join-Path $scssRoot "layout\_index.scss") -Content "/* Layouts partages (header via pages/backoffice). */`n"

    Write-TextFile -Path (Join-Path $scssRoot "main.scss") -Content @"
@use "base/root";
@use "base/reset";
@use "components/buttons";
@use "pages/home";
@use "pages/backoffice";
$consoleUseLine

body {
  font-family: var(--font-sans);
  background: var(--color-bg);
  color: var(--color-text);
  margin: 0;
  line-height: 1.5;
}

a {
  color: inherit;
}
"@

    New-Item -ItemType Directory -Path (Join-Path $Root "static\css") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Root "static\js") -Force | Out-Null
    Write-TextFile -Path (Join-Path $Root "static\js\.gitkeep") -Content "`n"
    Invoke-ScssCompile -Root $Root
}

function Write-HtmxTemplates {
    <#
    .SYNOPSIS
      Ecrit templates/base.html, home.html et backoffice (+ partials).
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$AppName,
        [bool]$HasFrontend = $false,
        [bool]$HasCustomAdmin = $true
    )

    $templatesRoot = Join-Path $Root "templates"
    $boDir = Join-Path $templatesRoot "backoffice"
    $partialsDir = Join-Path $boDir "partials"
    New-Item -ItemType Directory -Path $partialsDir -Force | Out-Null

    $astroLink = if ($HasFrontend) {
        @'
    <a class="site-header__link" href="http://localhost:4321/">UI produit</a>
'@
    } else {
        ""
    }

    $adminLink = if ($HasCustomAdmin) {
        @'
    <a class="site-header__link" href="/admin/">Admin</a>
'@
    } else {
        @'
    <a class="site-header__link" href="/django-admin/">Admin Django</a>
'@
    }

    # Evite l'expansion PowerShell de $AppName:home dans les here-strings
    $homeUrlTag = "{% url '" + $AppName + ":home' %}"
    $boUrlTag = "{% url '" + $AppName + ":backoffice_list' %}"

    Write-TextFile -Path (Join-Path $templatesRoot "base.html") -Content @"
{% load static %}
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="csrf-token" content="{{ csrf_token }}">
  <title>{% block title %}Projet{% endblock %}</title>
  <link rel="stylesheet" href="{% static 'css/main.css' %}">
  <script src="https://unpkg.com/htmx.org@2.0.4" crossorigin="anonymous"></script>
  <script defer src="https://cdn.jsdelivr.net/npm/alpinejs@3.14.8/dist/cdn.min.js"></script>
  {% block extra_head %}{% endblock %}
</head>
<body hx-headers='{"X-CSRFToken": "{{ csrf_token }}"}'>
  <header class="site-header">
    <a class="site-header__brand" href="$homeUrlTag">$AppName</a>
    <nav class="site-header__nav" aria-label="Navigation principale">
      <a class="site-header__link" href="$homeUrlTag">Accueil</a>
      <a class="site-header__link" href="$boUrlTag">Back-office</a>
$astroLink
$adminLink
      <a class="site-header__link" href="/api/health/">API</a>
    </nav>
  </header>
  <div class="layout-main">
    {% block content %}{% endblock %}
  </div>
  {% block extra_body %}{% endblock %}
</body>
</html>
"@

    $eyebrow = if ($HasFrontend) { "Django Ninja + Astro + HTMX" } else { "Django Ninja + HTMX" }
    $lead = if ($HasFrontend) {
        "UI produit sur Astro (:4321). Cette surface Django sert l'API et le back-office staff HTMX."
    } else {
        "Accueil Django et back-office HTMX. Logique metier via services / selectors."
    }
    $actions = @"
        <a class="btn btn--primary" href="$boUrlTag">Ouvrir le back-office</a>
        <a class="btn btn--secondary" href="/api/health/">API Health</a>
"@
    if ($HasCustomAdmin) {
        $actions = @"
        <a class="btn btn--primary" href="/admin/">Ouvrir l'Admin</a>
        <a class="btn btn--secondary" href="$boUrlTag">Back-office</a>
        <a class="btn btn--ghost" href="/api/health/">API Health</a>
"@
    }
    if ($HasFrontend) {
        $actions += "`n        <a class=`"btn btn--ghost`" href=`"http://localhost:4321/`">UI produit Astro</a>"
    }

    Write-TextFile -Path (Join-Path $templatesRoot "home.html") -Content @"
{% extends "base.html" %}
{% block title %}Accueil{% endblock %}
{% block content %}
  <main class="page-home">
    <div class="page-home__inner">
      <header class="page-home__hero">
        <p class="page-home__eyebrow">$eyebrow</p>
        <h1 class="page-home__title">Bienvenue sur $AppName</h1>
        <p class="page-home__lead">$lead</p>
        <div class="page-home__actions">
$actions
        </div>
      </header>
      <section class="page-home__grid" aria-label="Pilieres">
        <article class="page-home__card">
          <h2 class="page-home__card-title">API Django Ninja</h2>
          <p class="page-home__card-text">Schemas Pydantic, orchestration vers services et selectors.</p>
        </article>
        <article class="page-home__card">
          <h2 class="page-home__card-title">Back-office HTMX</h2>
          <p class="page-home__card-text">Partials, CSRF, double rendu CBV pour le staff interne.</p>
        </article>
        <article class="page-home__card">
          <h2 class="page-home__card-title">Flat High-End</h2>
          <p class="page-home__card-text">SCSS 7-1, tokens :root zinc/slate, BEM, mobile-first.</p>
        </article>
      </section>
    </div>
  </main>
{% endblock %}
"@

    $pingUrlTag = "{% url '" + $AppName + ":backoffice_ping' %}"
    $detailUrlTpl = "{% url '" + $AppName + ":backoffice_detail' item.id %}"
    $listUrlTag = $boUrlTag

    Write-TextFile -Path (Join-Path $boDir "list.html") -Content @"
{% extends "base.html" %}
{% block title %}Back-office{% endblock %}
{% block content %}
  <div class="backoffice">
    <aside class="backoffice__sidebar">
      <h1 class="backoffice__title">Back-office</h1>
      <p class="backoffice__meta">Espace staff HTMX (demo). Pas de console BDD ici.</p>
      <form
        method="post"
        action="$pingUrlTag"
        hx-post="$pingUrlTag"
        hx-target="#bo-flash"
        hx-swap="innerHTML"
      >
        {% csrf_token %}
        <button type="submit" class="btn btn--secondary btn--sm">
          Ping workspace
          <span class="htmx-indicator">…</span>
        </button>
      </form>
      <div id="bo-flash" aria-live="polite"></div>
    </aside>
    <div class="backoffice__main">
      <div class="backoffice__toolbar">
        <label class="visually-hidden" for="bo-search">Filtrer</label>
        <input
          id="bo-search"
          class="backoffice__search"
          type="search"
          name="q"
          placeholder="Filtrer les elements…"
          value="{{ query }}"
          hx-get="$listUrlTag"
          hx-trigger="keyup changed delay:300ms, search"
          hx-target="#bo-item-list"
          hx-swap="outerHTML"
          hx-push-url="false"
        >
      </div>
      <div class="backoffice__body">
        <div class="backoffice__list-panel">
          {% include "backoffice/partials/_item_list.html" %}
        </div>
        <div id="bo-detail" class="backoffice__detail">
          {% include "backoffice/partials/_detail_placeholder.html" %}
        </div>
      </div>
    </div>
  </div>
{% endblock %}
"@

    Write-TextFile -Path (Join-Path $partialsDir "_item_list.html") -Content @"
<ul id="bo-item-list" class="item-list" aria-label="Liste staff">
  {% for item in items %}
    <li>
      <button
        type="button"
        class="item-list__row"
        hx-get="$detailUrlTpl"
        hx-target="#bo-detail"
        hx-swap="innerHTML"
      >
        <p class="item-list__title">{{ item.title }}</p>
        <p class="item-list__meta">#{{ item.id }} · {{ item.status }}</p>
      </button>
    </li>
  {% empty %}
    <li>
      <p class="item-list__empty">Aucun element ne correspond au filtre.</p>
    </li>
  {% endfor %}
</ul>
"@

    Write-TextFile -Path (Join-Path $partialsDir "_item_detail.html") -Content @'
<article class="item-detail">
  <p class="item-detail__eyebrow">Detail</p>
  <h2 class="item-detail__title">{{ item.title }}</h2>
  <span class="item-detail__badge">{{ item.status }}</span>
  <p class="item-detail__body">{{ item.summary }}</p>
</article>
'@

    Write-TextFile -Path (Join-Path $partialsDir "_detail_placeholder.html") -Content @'
<p class="item-detail__placeholder">Selectionnez un element dans la liste pour afficher le detail (swap HTMX).</p>
'@

    Write-TextFile -Path (Join-Path $partialsDir "_flash.html") -Content @'
<p class="flash flash--success">{{ message }}</p>
'@
}

function Write-HtmxViewsAndUrls {
    <#
    .SYNOPSIS
      CBV Home + Backoffice (list/detail/ping) et urls de l'app.
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$AppName,
        [bool]$HasFrontend = $false
    )

    $appDir = Join-Path $Root "apps\$AppName"

    # Selectors demo staff (pas de modele ORM — donnees de reference)
    Write-TextFile -Path (Join-Path $appDir "selectors.py") -Content @'
"""Lecture / agregations (couche selector).

Les querysets optimises (select_related / prefetch) vivent ici.
"""

from __future__ import annotations

from typing import TypedDict


class StaffDemoItem(TypedDict):
    """Element de demonstration pour le back-office HTMX."""

    id: int
    title: str
    status: str
    summary: str


_STAFF_DEMO_ITEMS: tuple[StaffDemoItem, ...] = (
    {
        "id": 1,
        "title": "Revue permissions staff",
        "status": "ouvert",
        "summary": "Verifier les acces back-office et les mixins LoginRequired.",
    },
    {
        "id": 2,
        "title": "Audit partials HTMX",
        "status": "en cours",
        "summary": "Controle hx-target / hx-swap et indicateurs .htmx-request.",
    },
    {
        "id": 3,
        "title": "CSRF mutations",
        "status": "fait",
        "summary": "Les POST HTMX doivent envoyer le token (meta + hx-headers).",
    },
)


def example_selector() -> str:
    """Exemple de selector a remplacer par une lecture metier.

    Returns:
        Identifiant symbolique du selector d'exemple.
    """
    return "selector"


def list_staff_demo_items(*, query: str = "") -> list[StaffDemoItem]:
    """Liste les elements demo du back-office, avec filtre texte optionnel.

    Args:
        query: Filtre insensible a la casse sur titre / statut / resume.

    Returns:
        Liste d'items demo (copie superficielle).
    """
    needle = (query or "").strip().lower()
    if not needle:
        return [dict(item) for item in _STAFF_DEMO_ITEMS]
    return [
        dict(item)
        for item in _STAFF_DEMO_ITEMS
        if needle in item["title"].lower()
        or needle in item["status"].lower()
        or needle in item["summary"].lower()
    ]


def get_staff_demo_item(item_id: int) -> StaffDemoItem | None:
    """Retourne un element demo par identifiant.

    Args:
        item_id: Identifiant numerique de l'element.

    Returns:
        L'item trouve, ou None.
    """
    for item in _STAFF_DEMO_ITEMS:
        if item["id"] == item_id:
            return dict(item)
    return None
'@

    Write-TextFile -Path (Join-Path $appDir "services.py") -Content @'
"""Logique d'ecriture (couche service).

Les invariants metier et transactions vivent ici, pas dans les vues ni l'API.
"""

from __future__ import annotations

from typing import TypedDict


class StaffPingResult(TypedDict):
    """Resultat du ping workspace staff."""

    status: str
    message: str


def example_action() -> str:
    """Exemple de service a remplacer par une regle metier reelle.

    Returns:
        Identifiant symbolique du service d'exemple.
    """
    return "service"


def ping_staff_workspace() -> StaffPingResult:
    """Confirme que le workspace staff est joignable (demo mutation HTMX).

    Returns:
        Statut et message affiches via partial flash.
    """
    return {
        "status": "ok",
        "message": "Workspace staff pret (service ping_staff_workspace).",
    }
'@

    if ($HasFrontend) {
        $homeViewBlock = @"
class HomeView(View):
    '''Racine Django (UI produit Astro sur :4321).

    MRO:
    1. View.get -> JsonResponse d'information API / liens staff
    '''

    def get(self, request: HttpRequest) -> JsonResponse:
        return JsonResponse(
            {
                "service": "$AppName",
                "frontend": "http://localhost:4321",
                "backoffice": "/backoffice/",
                "health": "/api/health/",
            }
        )
"@
        $homeImports = @"
from django.http import Http404, HttpRequest, HttpResponse, JsonResponse
from django.shortcuts import render
from django.views import View
from django.views.generic import TemplateView
"@
    } else {
        $homeViewBlock = @"
class HomeView(TemplateView):
    '''Page d'accueil Django (templates/home.html).

    MRO:
    1. TemplateView.get -> rendu home.html
    '''

    template_name = "home.html"
"@
        $homeImports = @"
from django.http import Http404, HttpRequest, HttpResponse
from django.shortcuts import render
from django.views import View
from django.views.generic import TemplateView
"@
    }

    Write-TextFile -Path (Join-Path $appDir "views.py") -Content @"
from __future__ import annotations

"""Vues template CBV (accueil + back-office HTMX).

Toute logique metier passe par services / selectors — pas de duplication Ninja.
"""

$homeImports
from django.contrib.auth.mixins import LoginRequiredMixin, UserPassesTestMixin

from . import selectors, services


class StaffRequiredMixin(LoginRequiredMixin, UserPassesTestMixin):
    '''Exige un utilisateur authentifie avec is_staff.

    MRO:
    1. LoginRequiredMixin.dispatch -> redirection login si anonyme
    2. UserPassesTestMixin.dispatch -> 403 si non staff
    3. Vue concrete (get/post)
    '''

    login_url = "/accounts/login/"
    redirect_field_name = "next"

    def test_func(self) -> bool:
        user = self.request.user
        return bool(user.is_authenticated and user.is_staff)


$homeViewBlock


class BackofficeListView(StaffRequiredMixin, TemplateView):
    '''Liste filtrable du back-office (plein page ou partial HTMX).

    MRO:
    1. StaffRequiredMixin.dispatch -> auth + is_staff
    2. TemplateView.get -> contexte items + query
    3. get_template_names -> partial _item_list si request.htmx
    '''

    template_name = "backoffice/list.html"
    partial_template_name = "backoffice/partials/_item_list.html"

    def get_template_names(self) -> list[str]:
        if getattr(self.request, "htmx", False) and self.request.htmx:
            return [self.partial_template_name]
        return [self.template_name]

    def get_context_data(self, **kwargs: object) -> dict[str, object]:
        context = super().get_context_data(**kwargs)
        query = (self.request.GET.get("q") or "").strip()
        context["query"] = query
        context["items"] = selectors.list_staff_demo_items(query=query)
        return context


class BackofficeDetailView(StaffRequiredMixin, TemplateView):
    '''Detail d'un element demo (partial HTMX ou page minimale).

    MRO:
    1. StaffRequiredMixin.dispatch -> auth + is_staff
    2. TemplateView.get -> item via selector
    '''

    template_name = "backoffice/partials/_item_detail.html"

    def get_context_data(self, **kwargs: object) -> dict[str, object]:
        context = super().get_context_data(**kwargs)
        item_id = int(self.kwargs["pk"])
        item = selectors.get_staff_demo_item(item_id)
        if item is None:
            raise Http404("Element introuvable")
        context["item"] = item
        return context


class BackofficePingView(StaffRequiredMixin, View):
    '''Mutation demo HTMX : ping workspace via service.

    MRO:
    1. StaffRequiredMixin.dispatch -> auth + is_staff
    2. View.post -> services.ping_staff_workspace + partial flash
    '''

    def post(self, request: HttpRequest) -> HttpResponse:
        result = services.ping_staff_workspace()
        return render(
            request,
            "backoffice/partials/_flash.html",
            {"message": result["message"]},
        )
"@

    Write-TextFile -Path (Join-Path $appDir "urls.py") -Content @"
from django.urls import path

from . import views

app_name = "$AppName"

urlpatterns = [
    path("", views.HomeView.as_view(), name="home"),
    path("backoffice/", views.BackofficeListView.as_view(), name="backoffice_list"),
    path(
        "backoffice/ping/",
        views.BackofficePingView.as_view(),
        name="backoffice_ping",
    ),
    path(
        "backoffice/<int:pk>/",
        views.BackofficeDetailView.as_view(),
        name="backoffice_detail",
    ),
]
"@
}

function New-HtmxUiScaffold {
    <#
    .SYNOPSIS
      Genere templates HTMX, SCSS 7-1, CBV Home + Backoffice et assets.

    .PARAMETER Root
      Racine du projet genere (Django a la racine).

    .PARAMETER AppName
      Slug de l'app metier sous apps/.

    .PARAMETER HasFrontend
      Si vrai, HomeView reste JSON (UI produit Astro) ; back-office HTMX conserve.

    .PARAMETER HasCustomAdmin
      Influence les liens header (DataStudio vs django-admin).
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$AppName,
        [bool]$HasFrontend = $false,
        [bool]$HasCustomAdmin = $true
    )

    Write-Host "     UI HTMX : templates + SCSS 7-1 + CBV back-office" -ForegroundColor DarkGray

    New-Item -ItemType Directory -Path (Join-Path $Root "templates") -Force | Out-Null
    Write-HtmxTemplates -Root $Root -AppName $AppName -HasFrontend:$HasFrontend -HasCustomAdmin:$HasCustomAdmin
    New-StaticScssLayout -Root $Root -HasCustomAdmin:$HasCustomAdmin
    Write-HtmxViewsAndUrls -Root $Root -AppName $AppName -HasFrontend:$HasFrontend
    # Console HTMX : generee APRES New-AdminPanelBackend (orchestrateur) pour ne pas
    # etre ecrasee par django-admin startapp.

    # Evite un home.html orphelin sous apps/ (DjangoConfig sans frontend)
    $legacyHome = Join-Path $Root "apps\$AppName\templates\$AppName\home.html"
    if (Test-Path -LiteralPath $legacyHome) {
        Remove-Item -LiteralPath $legacyHome -Force -ErrorAction SilentlyContinue
    }

    Write-Host "     templates/ + static/scss/ + /$AppName backoffice routes" -ForegroundColor DarkGray
}
