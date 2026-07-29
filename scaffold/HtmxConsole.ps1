#Requires -Version 5.1
<#
.SYNOPSIS
  Console admin DataStudio HTMX (option A, zero React) â€” templates, CBV, SCSS.

.DESCRIPTION
  Genere /admin/ branchee sur apps.admin_panel (services/selectors).
  Legacy /console/ redirige vers /admin/.
  Appele depuis New-HtmxUiScaffold lorsque HasCustomAdmin=$true.
  Depend de Write-TextFile (Common.ps1).
#>

function Get-ConsoleTokensScss {
    <#
    .SYNOPSIS
      Tokens oklch dark Console (iso astro-templates Flat High-End).
    #>
    @'
/* Console DataStudio - scope .console (oklch dark + teal) */
.console {
  color-scheme: dark;
  --console-bg: oklch(0.16 0.008 260);
  --console-fg: oklch(0.95 0.005 260);
  --console-card: oklch(0.2 0.01 260);
  --console-muted: oklch(0.65 0.01 260);
  --console-border: oklch(1 0 0 / 10%);
  --console-primary: oklch(0.75 0.14 175);
  --console-primary-on: oklch(0.16 0.02 260);
  --console-secondary: oklch(0.26 0.012 260);
  --console-sidebar: oklch(0.18 0.009 260);
  --console-danger: oklch(0.62 0.2 20);
  --console-radius: 0.75rem;
  --console-radius-lg: 1.05rem;
  --console-radius-xl: 1.35rem;
  --console-radius-2xl: 1.8rem;
  --console-radius-3xl: 2.2rem;
  --console-max: 72rem;
  --console-font: "Geist", "Segoe UI", system-ui, sans-serif;
  --console-mono: "IBM Plex Mono", ui-monospace, monospace;
  --console-transition: 150ms ease;
  /* Fallback si tokens globaux absents */
  --space-5: 1.25rem;
  --space-10: 2.5rem;
  --space-12: 3rem;
  --space-16: 4rem;

  min-height: 100vh;
  background: var(--console-bg);
  color: var(--console-fg);
  font-family: var(--console-font);
}
'@
}

function Get-ConsoleScss {
    <#
    .SYNOPSIS
      Styles BEM Console (shell, welcome, admin, table editor, schema, DDL).
      Prefixe avec ``@use "../abstracts" as *;`` dans New-StaticScssLayout.
    #>
    @'
.console__header {
  position: sticky;
  top: 0;
  z-index: 30;
  border-bottom: 1px solid var(--console-border);
  background: color-mix(in oklch, var(--console-bg) 80%, transparent);
  backdrop-filter: blur(12px);
}

.console__header-inner {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-4);
  max-width: var(--console-max);
  margin: 0 auto;
  padding: var(--space-3) var(--space-4);
}

@include respond-to(sm) {
  .console__header-inner {
    padding-inline: var(--space-6);
  }
}

.console__brand {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  text-decoration: none;
  color: var(--console-fg);
}

.console__brand-mark {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 2rem;
  height: 2rem;
  border-radius: var(--console-radius-lg);
  background: var(--console-primary);
  color: var(--console-primary-on);
}

.console__brand-label {
  font-size: 0.875rem;
  font-weight: 600;
  letter-spacing: -0.01em;
}

.console__pills {
  display: inline-flex;
  padding: var(--space-1);
  border: 1px solid var(--console-border);
  border-radius: var(--console-radius-xl);
  background: var(--console-card);
}

.console__pill {
  display: inline-flex;
  align-items: center;
  gap: var(--space-2);
  padding: var(--space-2) var(--space-3);
  border: 0;
  border-radius: var(--console-radius-lg);
  background: transparent;
  color: var(--console-muted);
  font-size: 0.875rem;
  font-weight: 500;
  cursor: pointer;
  text-decoration: none;
  transition: color var(--console-transition), background var(--console-transition);
}

.console__pill:hover {
  color: var(--console-fg);
}

.console__pill--active {
  background: var(--console-secondary);
  color: var(--console-fg);
}

.console__main {
  max-width: var(--console-max);
  margin: 0 auto;
  padding: var(--space-8) var(--space-4);
}

@include respond-to(sm) {
  .console__main {
    padding: var(--space-12) var(--space-6);
  }
}

.console__flash {
  margin-bottom: var(--space-4);
}

.console-flash {
  margin: 0;
  padding: var(--space-3) var(--space-4);
  border-radius: var(--console-radius-lg);
  border: 1px solid var(--console-border);
  font-size: 0.875rem;
}

.console-flash--success {
  background: color-mix(in oklch, var(--console-primary) 12%, transparent);
  color: var(--console-fg);
}

.console-flash--error {
  background: color-mix(in oklch, var(--console-danger) 18%, transparent);
  color: var(--console-fg);
  border-color: color-mix(in oklch, var(--console-danger) 40%, transparent);
}

/* Welcome */
.console-welcome {
  display: flex;
  flex-direction: column;
  gap: var(--space-12);
}

.console-welcome__hero {
  position: relative;
  overflow: hidden;
  padding: var(--space-12) var(--space-6);
  border: 1px solid var(--console-border);
  border-radius: var(--console-radius-3xl);
  background: var(--console-card);
  text-align: center;
}

@include respond-to(sm) {
  .console-welcome__hero {
    padding: var(--space-16) var(--space-12);
  }
}

.console-welcome__badge {
  display: inline-flex;
  align-items: center;
  gap: var(--space-2);
  margin-bottom: var(--space-6);
  padding: var(--space-2) var(--space-4);
  border: 1px solid var(--console-border);
  border-radius: 999px;
  background: var(--console-secondary);
  color: var(--console-muted);
  font-size: 0.75rem;
  font-weight: 500;
}

.console-welcome__dot {
  width: 0.375rem;
  height: 0.375rem;
  border-radius: 999px;
  background: var(--console-primary);
}

.console-welcome__title {
  margin: 0 auto;
  max-width: 36rem;
  font-size: clamp(2rem, 5vw, 3.5rem);
  font-weight: 600;
  letter-spacing: -0.03em;
  line-height: 1.1;
}

.console-welcome__accent {
  color: var(--console-primary);
}

.console-welcome__lead {
  margin: var(--space-6) auto 0;
  max-width: 36rem;
  color: var(--console-muted);
  font-size: 1.0625rem;
  line-height: 1.6;
}

.console-welcome__actions {
  display: flex;
  flex-wrap: wrap;
  justify-content: center;
  gap: var(--space-3);
  margin-top: var(--space-8);
}

.console-welcome__stats {
  display: grid;
  gap: var(--space-4);
}

@include respond-to(sm) {
  .console-welcome__stats {
    grid-template-columns: repeat(3, 1fr);
  }
}

.console-stat {
  padding: var(--space-6);
  border: 1px solid var(--console-border);
  border-radius: var(--console-radius-2xl);
  background: var(--console-card);
}

.console-stat__value {
  font-size: 1.75rem;
  font-weight: 600;
  letter-spacing: -0.02em;
}

.console-stat__label {
  margin-top: var(--space-1);
  font-size: 0.875rem;
  font-weight: 500;
}

.console-stat__hint {
  margin-top: var(--space-1);
  font-size: 0.875rem;
  color: var(--console-muted);
}

.console-welcome__features {
  display: grid;
  gap: var(--space-4);
}

@include respond-to(md) {
  .console-welcome__features {
    grid-template-columns: repeat(3, 1fr);
  }
}

.console-feature {
  padding: var(--space-6);
  border: 1px solid var(--console-border);
  border-radius: var(--console-radius-2xl);
  background: var(--console-card);
  transition: border-color var(--console-transition);
}

.console-feature:hover {
  border-color: color-mix(in oklch, var(--console-primary) 40%, transparent);
}

.console-feature__icon {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 2.75rem;
  height: 2.75rem;
  margin-bottom: var(--space-4);
  border-radius: var(--console-radius-xl);
  background: var(--console-secondary);
  color: var(--console-primary);
}

.console-feature__title {
  margin: 0;
  font-size: 1rem;
  font-weight: 600;
}

.console-feature__body {
  margin: var(--space-2) 0 0;
  color: var(--console-muted);
  font-size: 0.875rem;
  line-height: 1.55;
}

.console-welcome__cta {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: var(--space-4);
  padding: var(--space-12) var(--space-6);
  border: 1px solid var(--console-border);
  border-radius: var(--console-radius-3xl);
  background: var(--console-card);
  text-align: center;
}

.console-welcome__cta-title {
  margin: 0;
  font-size: 1.5rem;
  font-weight: 600;
}

.console-welcome__cta-lead {
  margin: 0;
  max-width: 28rem;
  color: var(--console-muted);
  font-size: 0.875rem;
}

/* Admin */
.console-admin {
  display: flex;
  flex-direction: column;
  gap: var(--space-6);
}

.console-admin__toolbar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-4);
}

.console-admin__toolbar-right {
  display: flex;
  flex-wrap: wrap;
  align-items: flex-start;
  justify-content: flex-end;
  gap: var(--space-3);
}

.console-search {
  position: relative;
  width: min(100%, 18rem);
}

.console-search__label {
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

.console-search__field {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  padding: 0 var(--space-3);
  border: 1px solid var(--console-border);
  border-radius: var(--console-radius-xl);
  background: var(--console-card);
  transition: border-color var(--console-transition);
}

.console-search__field:focus-within {
  border-color: var(--console-primary);
}

.console-search__icon {
  flex: 0 0 auto;
  width: 1rem;
  height: 1rem;
  color: var(--console-muted);
}

.console-search__input {
  flex: 1 1 auto;
  min-width: 0;
  border: 0;
  background: transparent;
  color: var(--console-fg);
  font: inherit;
  font-size: 0.875rem;
  padding: var(--space-3) 0;
  outline: none;
}

.console-search__input::placeholder {
  color: var(--console-muted);
}

.console-search__input::-webkit-search-cancel-button,
.console-search__input::-webkit-search-decoration {
  -webkit-appearance: none;
  appearance: none;
  display: none;
}

.console-search__clear {
  flex: 0 0 auto;
  border: 0;
  background: transparent;
  color: var(--console-muted);
  font-size: 1.1rem;
  line-height: 1;
  cursor: pointer;
  padding: var(--space-1);
}

.console-search__clear:hover {
  color: var(--console-fg);
}

.console-search__list {
  position: absolute;
  z-index: 20;
  top: calc(100% + var(--space-2));
  left: 0;
  right: 0;
  margin: 0;
  padding: var(--space-2);
  list-style: none;
  border: 1px solid var(--console-border);
  border-radius: var(--console-radius-xl);
  background: var(--console-card);
  max-height: 16rem;
  overflow: auto;
}

.console-search__item {
  display: block;
  width: 100%;
  text-align: left;
  border: 0;
  border-radius: var(--console-radius-lg);
  background: transparent;
  color: var(--console-fg);
  font: inherit;
  font-size: 0.875rem;
  font-family: var(--console-mono);
  padding: var(--space-2) var(--space-3);
  cursor: pointer;
}

.console-search__item:hover,
.console-search__item:focus-visible {
  background: var(--console-secondary);
  outline: none;
}

.console-search__empty {
  padding: var(--space-2) var(--space-3);
  color: var(--console-muted);
  font-size: 0.8125rem;
}

.console-admin__title {
  margin: 0;
  font-size: 1.25rem;
  font-weight: 600;
  letter-spacing: -0.02em;
}

.console-admin__subtitle {
  margin: var(--space-1) 0 0;
  color: var(--console-muted);
  font-size: 0.875rem;
}

.console-admin__body {
  display: flex;
  flex-direction: column;
  gap: var(--space-4);
}

@include respond-to(lg) {
  .console-admin__body--data {
    flex-direction: row;
    align-items: flex-start;
  }
}

.console-admin__sidebar {
  position: relative;
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
  overflow-x: auto;
  padding-bottom: var(--space-1);
}

@include respond-to(lg) {
  .console-admin__sidebar {
    width: 14rem;
    flex-shrink: 0;
    overflow: visible;
  }
}

.console-admin__sidebar-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-2);
  padding-inline: var(--space-1);
}

.console-admin__sidebar-title {
  margin: 0;
  font-size: 0.8125rem;
  font-weight: 600;
  letter-spacing: 0.02em;
  text-transform: uppercase;
  color: var(--console-muted);
}

.console-admin__gear {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 2rem;
  height: 2rem;
  padding: 0;
  border: 1px solid var(--console-border);
  border-radius: var(--console-radius-lg);
  background: var(--console-card);
  color: var(--console-muted);
  cursor: pointer;
  transition: color var(--console-transition), background var(--console-transition),
    border-color var(--console-transition), transform var(--console-transition);
}

.console-admin__gear:hover {
  color: var(--console-fg);
  border-color: color-mix(in oklch, var(--console-primary) 40%, transparent);
}

.console-admin__gear[aria-expanded="true"] {
  color: var(--console-primary);
  border-color: color-mix(in oklch, var(--console-primary) 50%, transparent);
  background: var(--console-secondary);
}

.console-admin__gear-icon {
  width: 1rem;
  height: 1rem;
  transition: transform 220ms ease;
}

.console-admin__gear[aria-expanded="true"] .console-admin__gear-icon {
  transform: rotate(45deg);
}

.console-admin__sidebar-list {
  display: flex;
  gap: var(--space-2);
  overflow-x: auto;
}

@include respond-to(lg) {
  .console-admin__sidebar-list {
    flex-direction: column;
    overflow: visible;
  }
}

.console-admin__ddl-panel {
  position: absolute;
  z-index: 40;
  top: 2.75rem;
  left: 0;
  right: 0;
  min-width: 16rem;
  padding: var(--space-3);
  border: 1px solid var(--console-border);
  border-radius: var(--console-radius-xl);
  background: var(--console-sidebar);
  box-shadow: 0 12px 32px color-mix(in oklch, var(--console-bg) 70%, transparent);
}

@include respond-to(lg) {
  .console-admin__ddl-panel {
    right: auto;
    width: 22rem;
  }
}

.console-admin__ddl-panel-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-2);
  margin-bottom: var(--space-3);
  font-size: 0.8125rem;
  font-weight: 600;
  color: var(--console-fg);
}

.console-admin__ddl-panel .console-form {
  margin-top: var(--space-2);
}

.console-table-btn {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-2);
  min-width: 9rem;
  padding: var(--space-2) var(--space-3);
  border: 1px solid var(--console-border);
  border-radius: var(--console-radius-lg);
  background: var(--console-card);
  color: var(--console-muted);
  font-size: 0.875rem;
  text-align: left;
  cursor: pointer;
  transition: color var(--console-transition), background var(--console-transition),
    border-color var(--console-transition);
}

.console-table-btn:hover {
  color: var(--console-fg);
}

.console-table-btn--active {
  border-color: var(--console-primary);
  background: color-mix(in oklch, var(--console-primary) 12%, var(--console-secondary));
  color: var(--console-fg);
  box-shadow: 0 0 0 1px var(--console-primary);
}

.console-table-btn__name {
  font-family: var(--console-mono);
  font-size: 0.8125rem;
}

.console-table-btn__count {
  flex-shrink: 0;
  font-size: 0.75rem;
  color: var(--console-muted);
}

.console-admin__panel {
  min-width: 0;
  flex: 1;
}

/* Table editor */
.console-editor {
  overflow: hidden;
  border: 1px solid var(--console-border);
  border-radius: var(--console-radius-2xl);
  background: var(--console-card);
}

.console-editor__head {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-3);
  padding: var(--space-3) var(--space-4);
  border-bottom: 1px solid var(--console-border);
}

.console-editor__title {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  font-family: var(--console-mono);
  font-size: 0.875rem;
  font-weight: 600;
}

.console-badge {
  display: inline-flex;
  padding: 0.125rem 0.5rem;
  border-radius: var(--console-radius);
  background: var(--console-secondary);
  color: var(--console-muted);
  font-size: 0.75rem;
}

.console-editor__hint {
  margin: 0;
  color: var(--console-muted);
  font-size: 0.75rem;
}

.console-editor__scroll {
  overflow-x: auto;
}

.console-editor__table {
  width: 100%;
  border-collapse: collapse;
  font-size: 0.875rem;
}

.console-editor__table th,
.console-editor__table td {
  padding: var(--space-2) var(--space-3);
  border-bottom: 1px solid var(--console-border);
  white-space: nowrap;
  text-align: left;
  vertical-align: middle;
}

.console-editor__table th {
  font-family: var(--console-mono);
  font-size: 0.75rem;
  font-weight: 600;
  color: var(--console-muted);
}

.console-editor__pk {
  color: var(--console-primary);
  margin-right: var(--space-1);
}

.console-editor__cell {
  cursor: pointer;
}

.console-editor__cell:hover {
  background: color-mix(in oklch, var(--console-secondary) 60%, transparent);
}

.console-editor__cell--pk {
  color: var(--console-muted);
  cursor: default;
}

.console-editor__cell--pk:hover {
  background: transparent;
}

.console-editor__cell--readonly {
  color: var(--console-muted);
  cursor: default;
}

.console-editor__cell--readonly:hover {
  background: transparent;
}

.console-editor__null {
  color: color-mix(in oklch, var(--console-muted) 50%, transparent);
}

.console-editor__edit {
  display: flex;
  align-items: center;
  gap: var(--space-1);
}

.console-editor__input {
  width: 10rem;
  padding: var(--space-2);
  border: 1px solid var(--console-border);
  border-radius: var(--console-radius);
  background: var(--console-bg);
  color: var(--console-fg);
  font-family: var(--console-mono);
  font-size: 0.8125rem;
}

.console-editor__actions {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-2);
  padding: var(--space-3) var(--space-4);
  border-top: 1px solid var(--console-border);
}

.console-editor__empty {
  padding: var(--space-12);
  text-align: center;
  color: var(--console-muted);
  font-size: 0.875rem;
}

/* Schema */
.console-schema {
  display: flex;
  flex-direction: column;
  gap: var(--space-6);
}

.console-schema__relations {
  padding: var(--space-5);
  border: 1px solid var(--console-border);
  border-radius: var(--console-radius-2xl);
  background: var(--console-card);
}

.console-schema__relations-title {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  margin: 0 0 var(--space-1);
  font-size: 0.875rem;
  font-weight: 600;
}

.console-schema__fk-list {
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
  margin: var(--space-3) 0 0;
  padding: 0;
  list-style: none;
}

.console-schema__fk {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--space-2);
  padding: var(--space-2) var(--space-3);
  border: 1px solid var(--console-border);
  border-radius: var(--console-radius-lg);
  background: color-mix(in oklch, var(--console-secondary) 50%, transparent);
  font-size: 0.875rem;
}

.console-schema__fk-arrow {
  color: var(--console-primary);
}

.console-schema__mono {
  font-family: var(--console-mono);
}

.console-schema__muted {
  color: var(--console-muted);
  font-family: var(--console-mono);
}

.console-schema__grid {
  display: grid;
  gap: var(--space-4);
}

@include respond-to(md) {
  .console-schema__grid {
    grid-template-columns: repeat(2, 1fr);
  }
}

@include respond-to(xl) {
  .console-schema__grid {
    grid-template-columns: repeat(3, 1fr);
  }
}

.console-schema-card {
  overflow: hidden;
  border: 1px solid var(--console-border);
  border-radius: var(--console-radius-2xl);
  background: var(--console-card);
}

.console-schema-card__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-2);
  padding: var(--space-3) var(--space-4);
  border-bottom: 1px solid var(--console-border);
  background: color-mix(in oklch, var(--console-secondary) 40%, transparent);
}

.console-schema-card__name {
  font-family: var(--console-mono);
  font-size: 0.875rem;
  font-weight: 600;
}

.console-schema-card__cols {
  margin: 0;
  padding: 0;
  list-style: none;
}

.console-schema-card__col {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-3);
  padding: var(--space-2) var(--space-4);
  border-bottom: 1px solid var(--console-border);
  font-size: 0.875rem;
}

.console-schema-card__col:last-child {
  border-bottom: 0;
}

.console-schema-card__type {
  font-family: var(--console-mono);
  font-size: 0.75rem;
  color: var(--console-muted);
}

.console-schema-card__refs {
  padding: var(--space-2) var(--space-4);
  border-top: 1px solid var(--console-border);
  color: var(--console-muted);
  font-size: 0.75rem;
}

/* Structure / DDL forms */
.console-structure {
  margin-top: var(--space-4);
  padding: var(--space-4);
  border: 1px solid var(--console-border);
  border-radius: var(--console-radius-2xl);
  background: var(--console-card);
}

.console-structure__title {
  margin: 0 0 var(--space-3);
  font-size: 0.9375rem;
  font-weight: 600;
}

.console-structure__list {
  margin: 0 0 var(--space-4);
  padding: 0;
  list-style: none;
}

.console-structure__row {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-2);
  padding: var(--space-2) 0;
  border-bottom: 1px solid var(--console-border);
  font-size: 0.8125rem;
}

.console-structure__row:last-child {
  border-bottom: 0;
}

.console-form {
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
  margin-top: var(--space-4);
}

.console-form__row {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-2);
  align-items: flex-end;
}

.console-form__field {
  display: flex;
  flex-direction: column;
  gap: var(--space-1);
  min-width: 8rem;
}

.console-form__label {
  font-size: 0.75rem;
  color: var(--console-muted);
}

.console-form__hint {
  margin: 0 0 var(--space-2);
  font-size: 0.75rem;
  color: var(--console-muted);
}

.console-form__req {
  margin-left: 0.15rem;
  color: var(--console-danger);
  font-weight: 700;
  text-decoration: none;
  cursor: help;
}

.console-form__input,
.console-form__select,
.console-form__textarea {
  padding: var(--space-2) var(--space-3);
  border: 1px solid var(--console-border);
  border-radius: var(--console-radius);
  background: var(--console-bg);
  color: var(--console-fg);
  font-size: 0.875rem;
}

.console-form__input--invalid,
.console-form__input:user-invalid {
  border-color: var(--console-danger);
  box-shadow: 0 0 0 1px color-mix(in oklch, var(--console-danger) 45%, transparent);
}

.console-form__textarea {
  min-height: 6rem;
  font-family: var(--console-mono);
  resize: vertical;
}

.console-query {
  margin-top: var(--space-4);
  padding: var(--space-4);
  border: 1px solid var(--console-border);
  border-radius: var(--console-radius-2xl);
  background: var(--console-card);
}

.console-query__pre {
  margin: var(--space-3) 0 0;
  padding: var(--space-3);
  overflow: auto;
  border-radius: var(--console-radius);
  background: var(--console-bg);
  font-family: var(--console-mono);
  font-size: 0.75rem;
  white-space: pre-wrap;
}

.console-diagram {
  display: flex;
  flex-direction: column;
  gap: var(--space-4);
}

.console-diagram__toolbar {
  display: flex;
  flex-wrap: wrap;
  align-items: flex-start;
  justify-content: space-between;
  gap: var(--space-3);
}

.console-diagram__hint {
  margin: var(--space-1) 0 0;
  color: var(--console-muted);
  font-size: 0.8125rem;
  line-height: 1.45;
}

.console-diagram__canvas {
  overflow: hidden;
  border: 1px solid var(--console-border);
  border-radius: var(--console-radius-2xl);
  background: var(--console-bg);
  padding: var(--space-4);
}

.console-diagram__canvas--panning,
.console-diagram__canvas--panning * {
  cursor: grabbing !important;
}

.console-diagram__viewport {
  min-width: 100%;
  cursor: default;
}

.console-diagram__source {
  display: none;
}

.console-diagram__svg {
  width: 100%;
  max-width: 100%;
  height: auto;
  cursor: default;
}

.console-diagram__svg--interactive {
  cursor: default;
}

.console-diagram__svg--interactive .console-diagram__entity,
.console-diagram__svg--interactive .console-diagram__entity text,
.console-diagram__svg--interactive .console-diagram__entity rect,
.console-diagram__svg--interactive .console-diagram__entity path,
.console-diagram__svg--interactive .console-diagram__entity polygon,
.console-diagram__svg--interactive .console-diagram__entity foreignObject,
.console-diagram__svg--interactive .console-diagram__edge,
.console-diagram__svg--interactive .console-diagram__hit {
  pointer-events: all;
  cursor: pointer;
}

.console-diagram__svg--interactive .console-diagram__edge,
.console-diagram__svg--interactive .console-diagram__hit {
  pointer-events: stroke;
}

.console-diagram__token {
  font-family: var(--console-mono);
  font-size: 0.8em;
  color: var(--console-primary);
}

.console-diagram__svg--focus .console-diagram__dim {
  opacity: 0.18;
  filter: grayscale(0.35);
  transition: opacity 160ms ease, filter 160ms ease;
}

.console-diagram__svg .console-diagram__hot {
  opacity: 1;
  filter: none;
}

/* Mermaid 11 ER : bordures = paths stroke, pas des rect â€” couleur seule */
.console-diagram__svg .console-diagram__hot path.console-diagram__hot-border,
.console-diagram__svg g.console-diagram__hot path[stroke]:not([stroke="none"]):not(.console-diagram__hit) {
  stroke: var(--console-primary) !important;
}

.console-diagram__svg .console-diagram__hot rect {
  stroke: var(--console-primary) !important;
}

.console-diagram__svg .console-diagram__hot text {
  fill: var(--console-fg) !important;
  font-weight: 600;
}

/* Battre Mermaid lightgrey â€” sans changer stroke-width (markers) */
.console-diagram__svg path.relationshipLine.console-diagram__hot-edge,
.console-diagram__svg path.console-diagram__edge.console-diagram__hot-edge,
.console-diagram__svg path.console-diagram__hot-edge:not(.console-diagram__hit) {
  stroke: var(--console-primary) !important;
  opacity: 1 !important;
  filter: none !important;
  fill: none !important;
}

.console-diagram__svg path.console-diagram__hit {
  fill: none !important;
  stroke: rgba(0, 0, 0, 0.001) !important;
  stroke-width: 18px !important;
  pointer-events: stroke;
  cursor: pointer;
}

.console-diagram__svg .console-diagram__hot-label,
.console-diagram__svg .console-diagram__hot-fk {
  fill: var(--console-primary) !important;
  color: var(--console-primary) !important;
  font-weight: 700 !important;
  opacity: 1 !important;
  filter: none !important;
}


.console-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: var(--space-2);
  padding: var(--space-3) var(--space-4);
  border: 1px solid transparent;
  border-radius: var(--console-radius-lg);
  font-size: 0.875rem;
  font-weight: 600;
  cursor: pointer;
  text-decoration: none;
  transition: background var(--console-transition), color var(--console-transition),
    border-color var(--console-transition);
}

.console-btn--primary {
  background: var(--console-primary);
  color: var(--console-primary-on);
}

.console-btn--primary:hover {
  filter: brightness(1.05);
}

.console-btn--secondary {
  background: var(--console-secondary);
  color: var(--console-fg);
  border-color: var(--console-border);
}

.console-btn--ghost {
  background: transparent;
  color: var(--console-muted);
}

.console-btn--ghost:hover {
  color: var(--console-fg);
  background: var(--console-secondary);
}

.console-btn--danger {
  background: transparent;
  color: var(--console-danger);
  border-color: color-mix(in oklch, var(--console-danger) 40%, transparent);
}

.console-btn--sm {
  padding: var(--space-2) var(--space-3);
  font-size: 0.8125rem;
}

.console-btn--icon {
  width: 2rem;
  height: 2rem;
  padding: 0;
}

.console-empty {
  padding: var(--space-12);
  border: 1px solid var(--console-border);
  border-radius: var(--console-radius-2xl);
  background: var(--console-card);
  text-align: center;
  color: var(--console-muted);
  font-size: 0.875rem;
}

/* Login console */
.console-login {
  display: flex;
  align-items: center;
  justify-content: center;
  min-height: 100vh;
  padding: var(--space-6);
  background: var(--console-bg);
  color: var(--console-fg);
  font-family: var(--console-font);
}

.console-login__card {
  width: 100%;
  max-width: 24rem;
  padding: var(--space-8);
  border: 1px solid var(--console-border);
  border-radius: var(--console-radius-2xl);
  background: var(--console-card);
}

.console-login__title {
  margin: 0 0 var(--space-2);
  font-size: 1.25rem;
  font-weight: 600;
}

.console-login__lead {
  margin: 0 0 var(--space-6);
  color: var(--console-muted);
  font-size: 0.875rem;
}

.console-login__error {
  margin: 0 0 var(--space-4);
  color: var(--console-danger);
  font-size: 0.875rem;
}
'@
}

function Write-ConsoleTemplates {
    <#
    .SYNOPSIS
      Templates Console HTMX sous templates/console/ + login registration.
    #>
    param([Parameter(Mandatory)][string]$Root)

    $consoleDir = Join-Path $Root "templates\console"
    $partials = Join-Path $consoleDir "partials"
    $regDir = Join-Path $Root "templates\registration"
    New-Item -ItemType Directory -Path $partials -Force | Out-Null
    New-Item -ItemType Directory -Path $regDir -Force | Out-Null

    Write-TextFile -Path (Join-Path $consoleDir "base_console.html") -Content @'
{% load static %}
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="csrf-token" content="{{ csrf_token }}">
  <title>{% block title %}Console{% endblock %}</title>
  <link rel="stylesheet" href="{% static 'css/main.css' %}">
  <script src="https://unpkg.com/htmx.org@2.0.4" crossorigin="anonymous"></script>
  <script>
    document.addEventListener("alpine:init", () => {
      Alpine.data("consoleAdminSearch", (opts = {}) => ({
        view: "data",
        q: "",
        open: false,
        settingsOpen: false,
        selected: opts.selected || "",
        tableNames: Array.isArray(opts.tableNames) ? opts.tableNames : [],
        match(name) {
          const qq = this.q.trim().toLowerCase();
          return !qq || String(name).toLowerCase().includes(qq);
        },
        get suggestions() {
          const qq = this.q.trim().toLowerCase();
          const all = this.tableNames;
          if (!qq) return all.slice(0, 10);
          return all.filter((n) => n.toLowerCase().includes(qq)).slice(0, 12);
        },
        get suggestionEmpty() {
          return this.q.trim().length > 0 && this.suggestions.length === 0;
        },
        emitFilter() {
          const q = this.q.trim();
          window.__consoleTableQ = q;
          window.dispatchEvent(
            new CustomEvent("console:filter-tables", { detail: { q } }),
          );
        },
        onInput() {
          this.open = true;
          this.emitFilter();
        },
        pickTable(name) {
          this.q = name;
          this.open = false;
          this.selected = name;
          this.emitFilter();
          if (this.view === "data") {
            const btn = this.$root.querySelector(
              '[data-table-name="' + CSS.escape(name) + '"]',
            );
            if (btn) btn.click();
          }
          if (this.view === "diagram") {
            window.dispatchEvent(
              new CustomEvent("console:focus-table", { detail: { name } }),
            );
          }
          this.$nextTick(() => {
            const card = this.$root.querySelector(
              '[data-schema-table="' + CSS.escape(name) + '"]',
            );
            if (card) card.scrollIntoView({ behavior: "smooth", block: "nearest" });
          });
        },
        clearSearch() {
          this.q = "";
          this.open = false;
          this.emitFilter();
        },
        setView(next) {
          this.view = next;
          this.$nextTick(() => this.emitFilter());
        },
      }));
    });
  </script>
  <script defer src="https://cdn.jsdelivr.net/npm/alpinejs@3.14.8/dist/cdn.min.js"></script>
  {% block extra_head %}{% endblock %}
</head>
<body class="console" hx-headers='{"X-CSRFToken": "{{ csrf_token }}"}'>
  {% block body %}{% endblock %}
  <script>
    document.body.addEventListener("htmx:afterSwap", (event) => {
      if (window.Alpine && event.detail && event.detail.elt) {
        Alpine.initTree(event.detail.elt);
      }
    });
  </script>
</body>
</html>
'@

    Write-TextFile -Path (Join-Path $consoleDir "shell.html") -Content @'
{% extends "console/base_console.html" %}
{% block title %}Console - DataStudio{% endblock %}
{% block body %}
<header class="console__header">
  <div class="console__header-inner">
    <a class="console__brand" href="{% url 'admin_panel:console_shell' %}">
      <span class="console__brand-mark" aria-hidden="true">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M3 5v14c0 1.66 4 3 9 3s9-1.34 9-3V5"/>
          <path d="M3 12c0 1.66 4 3 9 3s9-1.34 9-3"/>
        </svg>
      </span>
      <span class="console__brand-label">Console</span>
    </a>
    <nav class="console__pills" aria-label="Onglets console">
      <a
        class="console__pill {% if tab == 'welcome' %}console__pill--active{% endif %}"
        href="{% url 'admin_panel:console_shell' %}?tab=welcome"
        hx-get="{% url 'admin_panel:console_shell' %}?tab=welcome"
        hx-target="#console-main"
        hx-swap="innerHTML"
        hx-push-url="true"
      >Bienvenue</a>
      <a
        class="console__pill {% if tab == 'admin' %}console__pill--active{% endif %}"
        href="{% url 'admin_panel:console_shell' %}?tab=admin"
        hx-get="{% url 'admin_panel:console_admin' %}"
        hx-target="#console-main"
        hx-swap="innerHTML"
        hx-push-url="{% url 'admin_panel:console_shell' %}?tab=admin"
      >Admin</a>
    </nav>
  </div>
</header>
<main id="console-main" class="console__main">
  {% if tab == 'admin' %}
    {% include "console/partials/_admin.html" %}
  {% else %}
    {% include "console/partials/_welcome.html" %}
  {% endif %}
</main>
<div id="console-flash" class="console__flash" aria-live="polite"></div>
{% endblock %}
'@

    Write-TextFile -Path (Join-Path $partials "_welcome.html") -Content @'
<section class="console-welcome">
  <div class="console-welcome__hero">
    <span class="console-welcome__badge">
      <span class="console-welcome__dot"></span>
      Base de donnees connectee
    </span>
    <h1 class="console-welcome__title">
      Votre console de donnees,
      <span class="console-welcome__accent">epuree</span>
      et vivante
    </h1>
    <p class="console-welcome__lead">
      Explorez le schema, visualisez les liens entre les tables et modifiez vos donnees
      depuis une interface claire (HTMX + services admin_panel).
    </p>
    <div class="console-welcome__actions">
      <a
        class="console-btn console-btn--primary"
        href="{% url 'admin_panel:console_shell' %}?tab=admin"
        hx-get="{% url 'admin_panel:console_admin' %}"
        hx-target="#console-main"
        hx-swap="innerHTML"
        hx-push-url="{% url 'admin_panel:console_shell' %}?tab=admin"
      >Ouvrir l&rsquo;admin</a>
    </div>
  </div>

  <div class="console-welcome__stats">
    {% for s in stats %}
      <article class="console-stat">
        <div class="console-stat__value">{{ s.value }}</div>
        <div class="console-stat__label">{{ s.label }}</div>
        <div class="console-stat__hint">{{ s.hint }}</div>
      </article>
    {% endfor %}
  </div>

  <div class="console-welcome__features">
    <article class="console-feature">
      <div class="console-feature__icon" aria-hidden="true">T</div>
      <h3 class="console-feature__title">Explorer les tables</h3>
      <p class="console-feature__body">Colonnes, types et cles primaires en un coup d&rsquo;oeil.</p>
    </article>
    <article class="console-feature">
      <div class="console-feature__icon" aria-hidden="true">L</div>
      <h3 class="console-feature__title">Visualiser les liens</h3>
      <p class="console-feature__body">Carte des cles etrangeres entre vos tables.</p>
    </article>
    <article class="console-feature">
      <div class="console-feature__icon" aria-hidden="true">E</div>
      <h3 class="console-feature__title">Modifier les valeurs</h3>
      <p class="console-feature__body">Edition cellule et CRUD via services (ORM ou SQL securise).</p>
    </article>
  </div>

  <section class="console-welcome__cta">
    <h2 class="console-welcome__cta-title">Pret a plonger dans vos donnees&nbsp;?</h2>
    <p class="console-welcome__cta-lead">
      L&rsquo;onglet Admin donne le controle sur tables, colonnes et valeurs.
    </p>
    <a
      class="console-btn console-btn--secondary"
      href="{% url 'admin_panel:console_shell' %}?tab=admin"
      hx-get="{% url 'admin_panel:console_admin' %}"
      hx-target="#console-main"
      hx-swap="innerHTML"
      hx-push-url="{% url 'admin_panel:console_shell' %}?tab=admin"
    >Aller a l&rsquo;admin</a>
  </section>
</section>
'@

    Write-TextFile -Path (Join-Path $partials "_admin.html") -Content @'
<section
  class="console-admin"
  x-data="consoleAdminSearch({
    selected: '{{ selected_table|default:''|escapejs }}',
    tableNames: [{% for t in tables %}'{{ t.name|escapejs }}'{% if not forloop.last %}, {% endif %}{% endfor %}]
  })"
  @keydown.escape.window="open = false; settingsOpen = false"
>
  {% if flash_error %}
    <p class="console-flash console-flash--error" role="alert">{{ flash_error }}</p>
  {% endif %}

  <div class="console-admin__toolbar">
    <div>
      <h2 class="console-admin__title">Administration</h2>
      <p class="console-admin__subtitle">Explorez le schema et modifiez vos donnees.</p>
    </div>
    <div class="console-admin__toolbar-right">
      <div
        class="console-search"
        x-show="view === 'data' || view === 'schema' || view === 'diagram'"
        @click.outside="open = false"
      >
        <label class="console-search__label" for="console-table-search">Rechercher une table</label>
        <div class="console-search__field">
          <svg class="console-search__icon" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
            <circle cx="11" cy="11" r="7" fill="none" stroke="currentColor" stroke-width="2"/>
            <path d="M20 20l-3.5-3.5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
          </svg>
          <input
            id="console-table-search"
            class="console-search__input"
            type="text"
            autocomplete="off"
            spellcheck="false"
            placeholder="Table, prediction..."
            x-model="q"
            @input="onInput()"
            @focus="open = true"
            @keydown.enter.prevent="suggestions.length && pickTable(suggestions[0])"
            @keydown.arrow-down.prevent="open = true"
            aria-autocomplete="list"
            aria-controls="console-table-suggestions"
            :aria-expanded="open.toString()"
          >
          <button
            type="button"
            class="console-search__clear"
            x-show="q.length"
            x-cloak
            @click="clearSearch()"
            aria-label="Effacer la recherche"
          >&times;</button>
        </div>
        <ul
          id="console-table-suggestions"
          class="console-search__list"
          role="listbox"
          x-show="open && (suggestions.length || suggestionEmpty)"
          x-cloak
          x-transition.opacity.duration.120ms
        >
          <template x-for="name in suggestions" :key="name">
            <li role="option">
              <button
                type="button"
                class="console-search__item"
                @click="pickTable(name)"
                x-text="name"
              ></button>
            </li>
          </template>
          <li class="console-search__empty" x-show="suggestionEmpty" x-cloak>
            Aucune table correspondante
          </li>
        </ul>
      </div>
      <div class="console__pills" role="tablist">
        <button type="button" class="console__pill" :class="view === 'data' && 'console__pill--active'" @click="setView('data')">Donnees</button>
        <button type="button" class="console__pill" :class="view === 'schema' && 'console__pill--active'" @click="setView('schema')">Schema &amp; liens</button>
        <button type="button" class="console__pill" :class="view === 'query' && 'console__pill--active'" @click="setView('query')">Query SQL</button>
        <button type="button" class="console__pill" :class="view === 'diagram' && 'console__pill--active'" @click="setView('diagram')">Diagram</button>
      </div>
    </div>
  </div>

  <div x-show="view === 'data'" class="console-admin__body console-admin__body--data">
    {% include "console/partials/_table_sidebar.html" %}
    <div id="console-table-panel" class="console-admin__panel">
      {% if selected_table %}
        {% include "console/partials/_table_editor.html" %}
      {% else %}
        <p class="console-empty">Selectionnez une table dans la liste.</p>
      {% endif %}
    </div>
  </div>

  <div x-show="view === 'schema'" x-cloak>
    {% include "console/partials/_schema.html" %}
  </div>

  <div x-show="view === 'query'" x-cloak class="console-query">
    {% include "console/partials/_query.html" %}
  </div>

  <div x-show="view === 'diagram'" x-cloak class="console-query">
    {% include "console/partials/_diagram.html" %}
  </div>
</section>
'@

    Write-TextFile -Path (Join-Path $partials "_table_sidebar.html") -Content @'
<aside
  class="console-admin__sidebar"
  id="console-sidebar"
  aria-label="Tables"
>
  <div class="console-admin__sidebar-head">
    <h3 class="console-admin__sidebar-title">Tables</h3>
    <button
      type="button"
      class="console-admin__gear"
      @click="settingsOpen = !settingsOpen"
      :aria-expanded="settingsOpen.toString()"
      aria-controls="console-ddl-panel"
      title="Creer / supprimer une table"
      aria-label="Creer ou supprimer une table"
    >
      <svg class="console-admin__gear-icon" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
        <path
          fill="currentColor"
          d="M19.14 12.94c.04-.31.06-.63.06-.94s-.02-.63-.06-.94l2.03-1.58a.49.49 0 0 0 .12-.61l-1.92-3.32a.49.49 0 0 0-.59-.22l-2.39.96a7.2 7.2 0 0 0-1.62-.94l-.36-2.54A.49.49 0 0 0 13.5 2h-3a.49.49 0 0 0-.48.41l-.36 2.54c-.59.24-1.13.55-1.62.94l-2.39-.96a.49.49 0 0 0-.59.22L2.76 8.87a.49.49 0 0 0 .12.61l2.03 1.58c-.04.31-.06.63-.06.94s.02.63.06.94L2.88 14.52a.49.49 0 0 0-.12.61l1.92 3.32c.12.22.37.3.59.22l2.39-.96c.49.39 1.03.7 1.62.94l.36 2.54c.05.24.25.41.48.41h3c.24 0 .43-.17.48-.41l.36-2.54c.59-.24 1.13-.55 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32a.49.49 0 0 0-.12-.61l-2.03-1.58zM12 15.5A3.5 3.5 0 1 1 12 8.5a3.5 3.5 0 0 1 0 7z"
        />
      </svg>
    </button>
  </div>
  <div class="console-admin__sidebar-list">
    {% for t in tables %}
      <button
        type="button"
        class="console-table-btn"
        data-table-name="{{ t.name }}"
        x-show="match('{{ t.name|escapejs }}')"
        :class="{ 'console-table-btn--active': selected === '{{ t.name|escapejs }}' }"
        @click="selected = '{{ t.name|escapejs }}'"
        hx-get="{% url 'admin_panel:console_table' t.name %}"
        hx-target="#console-table-panel"
        hx-swap="innerHTML"
      >
        <span class="console-table-btn__name">{{ t.name }}</span>
        <span class="console-table-btn__count">{{ t.row_count }}</span>
      </button>
    {% empty %}
      <p class="console-empty">Aucune table trouvee.</p>
    {% endfor %}
    <p class="console-empty" x-show="q.trim() && !suggestions.length" x-cloak>
      Aucune table pour Â« <span x-text="q"></span> Â»
    </p>
  </div>
  <div
    id="console-ddl-panel"
    class="console-admin__ddl-panel"
    x-show="settingsOpen"
    x-cloak
    x-transition.opacity.duration.150ms
    role="region"
    aria-label="Creer ou supprimer une table"
  >
    <div class="console-admin__ddl-panel-head">
      <span>Creer / supprimer</span>
      <button type="button" class="console-btn console-btn--ghost console-btn--sm" @click="settingsOpen = false">Fermer</button>
    </div>
    {% include "console/partials/_ddl_tables.html" %}
  </div>
</aside>
'@

    Write-TextFile -Path (Join-Path $partials "_table_editor.html") -Content @'
<div class="console-editor" id="console-editor">
  <div class="console-editor__head">
    <div class="console-editor__title">
      <span>{{ table_name }}</span>
      <span class="console-badge">{{ display_rows|length }} affichees</span>
      <span class="console-badge">{{ source }}</span>
    </div>
    <p class="console-editor__hint">Cliquez une cellule pour l&rsquo;editer</p>
  </div>
  {% if display_rows %}
  <div class="console-editor__scroll">
    <table class="console-editor__table">
      <thead>
        <tr>
          {% for col in columns %}
            <th>
              {% if col == pk %}<span class="console-editor__pk" title="Cle primaire">&#9670;</span>{% endif %}
              {{ col }}
            </th>
          {% endfor %}
          <th></th>
        </tr>
      </thead>
      <tbody>
        {% for row in display_rows %}
          <tr>
            {% for cell in row.cells %}
              <td class="console-editor__cell {% if cell.is_pk %}console-editor__cell--pk{% endif %} {% if not cell.is_editable %}console-editor__cell--readonly{% endif %}"
                  {% if cell.is_editable %}
                  x-data="{ editing: false, draft: '{{ cell.display|escapejs }}' }"
                  @click="if (!editing) editing = true"
                  {% endif %}>
                {% if not cell.is_editable %}
                  {% if cell.is_null %}<span class="console-editor__null">NULL</span>{% else %}{{ cell.display }}{% endif %}
                {% else %}
                  <span x-show="!editing">{% if cell.is_null %}<span class="console-editor__null">NULL</span>{% else %}{{ cell.display }}{% endif %}</span>
                  <form
                    x-show="editing"
                    x-cloak
                    class="console-editor__edit"
                    method="post"
                    hx-post="{% url 'admin_panel:console_cell_update' table_name %}"
                    hx-target="#console-table-panel"
                    hx-swap="innerHTML"
                    @click.stop
                  >
                    {% csrf_token %}
                    <input type="hidden" name="primary_key" value="{{ pk }}">
                    <input type="hidden" name="primary_key_value" value="{{ row.pk_value }}">
                    <input type="hidden" name="column" value="{{ cell.name }}">
                    <input class="console-editor__input" type="text" name="value" x-model="draft">
                    <button type="submit" class="console-btn console-btn--primary console-btn--sm">OK</button>
                    <button type="button" class="console-btn console-btn--ghost console-btn--sm" @click="editing = false">X</button>
                  </form>
                {% endif %}
              </td>
            {% endfor %}
            <td>
              {% if pk %}
              <form
                method="post"
                hx-post="{% url 'admin_panel:console_row_delete' table_name %}"
                hx-target="#console-table-panel"
                hx-swap="innerHTML"
                hx-confirm="Supprimer cette ligne ?"
              >
                {% csrf_token %}
                <input type="hidden" name="primary_key" value="{{ pk }}">
                <input type="hidden" name="primary_key_value" value="{{ row.pk_value }}">
                <button type="submit" class="console-btn console-btn--danger console-btn--sm">Suppr.</button>
              </form>
              {% endif %}
            </td>
          </tr>
        {% endfor %}
      </tbody>
    </table>
  </div>
  {% else %}
    <p class="console-editor__empty">Aucune ligne (ou table vide).</p>
  {% endif %}

  <div class="console-editor__actions">
    <details>
      <summary class="console-btn console-btn--secondary console-btn--sm">Inserer une ligne</summary>
      <form
        class="console-form"
        method="post"
        hx-post="{% url 'admin_panel:console_row_insert' table_name %}"
        hx-target="#console-table-panel"
        hx-swap="innerHTML"
        novalidate
        x-data="{ tried: false }"
        @submit="
          tried = true;
          if (!$el.checkValidity()) {
            $event.preventDefault();
            $event.stopPropagation();
          }
        "
      >
        {% csrf_token %}
        <p class="console-form__hint"><abbr class="console-form__req" title="Obligatoire">*</abbr> Champ obligatoire</p>
        <div class="console-form__row">
          {% for field in insert_fields %}
            <label class="console-form__field">
              <span class="console-form__label">
                {{ field.label }}
                {% if field.required %}<abbr class="console-form__req" title="Obligatoire">*</abbr>{% endif %}
              </span>
              <input
                class="console-form__input"
                type="{{ field.input_type|default:'text' }}"
                name="field__{{ field.name }}"
                {% if field.required %}required aria-required="true"{% endif %}
                :class="tried && $el.validity && !$el.validity.valid && 'console-form__input--invalid'"
                @input="if (tried) $el.reportValidity()"
              >
            </label>
          {% empty %}
            <p class="console-empty">Aucun champ insertable.</p>
          {% endfor %}
        </div>
        <button type="submit" class="console-btn console-btn--primary console-btn--sm">Creer</button>
      </form>
    </details>
  </div>

  {% include "console/partials/_structure.html" %}
</div>
'@

    Write-TextFile -Path (Join-Path $partials "_structure.html") -Content @'
<section class="console-structure" id="console-structure">
  <h3 class="console-structure__title">Structure - {{ table_name }}</h3>
  <ul class="console-structure__list">
    {% for col in structure_columns %}
      <li class="console-structure__row">
        <span>
          <span class="console-schema__mono">{{ col.name }}</span>
          <span class="console-schema__muted"> {{ col.data_type }}</span>
          {% if col.primary_key %}<span class="console-badge">PK</span>{% endif %}
        </span>
        <span class="console-form__row">
          {% if not col.primary_key and can_ddl %}
          <form
            method="post"
            hx-post="{% url 'admin_panel:console_column_rename' table_name %}"
            hx-target="#console-table-panel"
            hx-swap="innerHTML"
            class="console-form__row"
          >
            {% csrf_token %}
            <input type="hidden" name="old_name" value="{{ col.name }}">
            <input class="console-form__input" type="text" name="new_name" placeholder="Nouveau nom" required>
            <button type="submit" class="console-btn console-btn--ghost console-btn--sm">Renommer</button>
          </form>
          <form
            method="post"
            hx-post="{% url 'admin_panel:console_column_drop' table_name %}"
            hx-target="#console-table-panel"
            hx-swap="innerHTML"
            hx-confirm="Supprimer la colonne {{ col.name }} ?"
          >
            {% csrf_token %}
            <input type="hidden" name="column" value="{{ col.name }}">
            <button type="submit" class="console-btn console-btn--danger console-btn--sm">Drop</button>
          </form>
          {% endif %}
        </span>
      </li>
    {% empty %}
      <li class="console-structure__row">Aucune colonne.</li>
    {% endfor %}
  </ul>
  {% if can_ddl %}
  <form
    class="console-form"
    method="post"
    hx-post="{% url 'admin_panel:console_column_add' table_name %}"
    hx-target="#console-table-panel"
    hx-swap="innerHTML"
  >
    {% csrf_token %}
    <div class="console-form__row">
      <label class="console-form__field">
        <span class="console-form__label">Nouvelle colonne</span>
        <input class="console-form__input" type="text" name="name" required pattern="[A-Za-z_][A-Za-z0-9_]*">
      </label>
      <label class="console-form__field">
        <span class="console-form__label">Type</span>
        <select class="console-form__select" name="pg_type">
          <option value="text">text</option>
          <option value="varchar(255)">varchar(255)</option>
          <option value="integer">integer</option>
          <option value="bigint">bigint</option>
          <option value="boolean">boolean</option>
          <option value="timestamptz">timestamptz</option>
          <option value="numeric">numeric</option>
          <option value="uuid">uuid</option>
          <option value="jsonb">jsonb</option>
        </select>
      </label>
      <label class="console-form__field">
        <span class="console-form__label">Nullable</span>
        <select class="console-form__select" name="nullable">
          <option value="1">Oui</option>
          <option value="0">Non</option>
        </select>
      </label>
      <button type="submit" class="console-btn console-btn--secondary console-btn--sm">Ajouter</button>
    </div>
  </form>
  {% else %}
  <p class="console-editor__hint">DDL desactive (table systeme protegee).</p>
  {% endif %}
</section>
'@

    Write-TextFile -Path (Join-Path $partials "_schema.html") -Content @'
<section class="console-schema">
  <div class="console-schema__relations">
    <h3 class="console-schema__relations-title">Relations entre les tables</h3>
    {% if foreign_keys %}
      <ul class="console-schema__fk-list">
        {% for fk in foreign_keys %}
          <li
            class="console-schema__fk"
            data-fk-tables="{{ fk.from_table }} {{ fk.to_table }}"
            x-show="match('{{ fk.from_table|escapejs }}') || match('{{ fk.to_table|escapejs }}')"
          >
            <span class="console-schema__mono">{{ fk.from_table }}</span>
            <span class="console-schema__muted">.{{ fk.from_column }}</span>
            <span class="console-schema__fk-arrow">&rarr;</span>
            <span class="console-schema__mono">{{ fk.to_table }}</span>
            <span class="console-schema__muted">.{{ fk.to_column }}</span>
          </li>
        {% endfor %}
      </ul>
      <p class="console-schema__muted" x-show="q.trim() && !suggestions.length" x-cloak>
        Aucune relation pour cette recherche.
      </p>
    {% else %}
      <p class="console-schema__muted">Aucune cle etrangere detectee.</p>
    {% endif %}
  </div>
  <div class="console-schema__grid">
    {% for table in tables %}
      <article
        class="console-schema-card"
        data-schema-table="{{ table.name }}"
        x-show="match('{{ table.name|escapejs }}')"
      >
        <div class="console-schema-card__head">
          <span class="console-schema-card__name">{{ table.name }}</span>
          <span class="console-badge">{{ table.row_count }} ligne{{ table.row_count|pluralize }}</span>
        </div>
        <ul class="console-schema-card__cols">
          {% for col in table.columns %}
            <li class="console-schema-card__col">
              <span>
                {% if col.primary_key %}<span class="console-editor__pk">&#9670;</span>{% endif %}
                {{ col.name }}
              </span>
              <span class="console-schema-card__type">{{ col.data_type }}</span>
            </li>
          {% endfor %}
        </ul>
      </article>
    {% endfor %}
  </div>
</section>
'@

    Write-TextFile -Path (Join-Path $partials "_query.html") -Content @'
<h3 class="console-structure__title">Query SQL (lecture seule)</h3>
<form
  class="console-form"
  method="post"
  hx-post="{% url 'admin_panel:console_query' %}"
  hx-target="#console-query-result"
  hx-swap="innerHTML"
>
  {% csrf_token %}
  <label class="console-form__field">
    <span class="console-form__label">SELECT / WITH / EXPLAIN</span>
    <textarea class="console-form__textarea" name="sql" placeholder="SELECT * FROM auth_user LIMIT 10"></textarea>
  </label>
  <button type="submit" class="console-btn console-btn--primary console-btn--sm">Executer</button>
</form>
<div id="console-query-result"></div>
'@

    Write-TextFile -Path (Join-Path $partials "_query_result.html") -Content @'
{% if error %}
  <p class="console-flash console-flash--error">{{ error }}</p>
{% else %}
  <p class="console-editor__hint">{{ row_count }} ligne(s) Â· {{ elapsed_ms }} ms{% if truncated %} Â· tronque{% endif %}</p>
  <div class="console-editor__scroll">
    <table class="console-editor__table">
      <thead>
        <tr>{% for c in columns %}<th>{{ c }}</th>{% endfor %}</tr>
      </thead>
      <tbody>
        {% for row in display_rows %}
          <tr>{% for cell in row %}<td>{% if cell.is_null %}<span class="console-editor__null">NULL</span>{% else %}{{ cell.display }}{% endif %}</td>{% endfor %}</tr>
        {% endfor %}
      </tbody>
    </table>
  </div>
{% endif %}
'@

    Write-TextFile -Path (Join-Path $partials "_diagram.html") -Content @'
<section class="console-diagram" id="console-diagram-root">
  <div class="console-diagram__toolbar">
    <div>
      <h3 class="console-structure__title">Diagramme Mermaid (ER)</h3>
      <p class="console-diagram__hint">
        Cliquez une <strong>table</strong>, une <strong>colonne FK</strong> ou un <strong>lien</strong>
        pour colorer le trait. La recherche n'affiche que la table et ses voisins directs.
        <strong>Molette</strong> : zoom &middot; <strong>Clic droit maintenu</strong> : deplacer le graphe.
      </p>
    </div>
    <button type="button" class="console-btn console-btn--ghost console-btn--sm" id="console-diagram-clear" hidden>
      Effacer la selection
    </button>
  </div>

  {{ foreign_keys|json_script:"console-diagram-fks" }}
  <div id="console-mermaid-host" class="console-diagram__canvas">
    <pre class="console-query__pre console-diagram__source" id="console-mermaid">{{ mermaid }}</pre>
  </div>
</section>

<script type="module">
  import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs";

  const root = document.getElementById("console-diagram-root");
  const host = document.getElementById("console-mermaid-host");
  const source = document.getElementById("console-mermaid");
  const clearBtn = document.getElementById("console-diagram-clear");
  const fksEl = document.getElementById("console-diagram-fks");

  if (!root || !host || !source || root.dataset.bound === "1") {
    // HTMX / double init
  } else {
    root.dataset.bound = "1";

    const sanitize = (value) => {
      let cleaned = String(value || "").trim().replace(/[^A-Za-z0-9_]/g, "_");
      cleaned = cleaned.replace(/_+/g, "_").replace(/^_|_$/g, "");
      if (!cleaned) cleaned = "x";
      if (/^\d/.test(cleaned)) cleaned = `t_${cleaned}`;
      return cleaned.toUpperCase().slice(0, 48);
    };

    const readPrimary = () => {
      const scope = root.closest(".console") || root;
      const raw = getComputedStyle(scope).getPropertyValue("--console-primary").trim();
      return raw || "oklch(0.75 0.14 175)";
    };

    const readPrimaryOn = () => {
      const scope = root.closest(".console") || root;
      const raw = getComputedStyle(scope).getPropertyValue("--console-primary-on").trim();
      return raw || "oklch(0.16 0.02 260)";
    };

    const textOf = (node) => (node.textContent || "").replace(/\s+/g, " ").trim();

    const fullSource = (source.textContent || "").trim();

    const parseEntityBlocks = (body) => {
      const map = new Map();
      const re = /([A-Za-z0-9_]+)\s*\{([^}]*)\}/g;
      let m;
      while ((m = re.exec(body))) {
        map.set(sanitize(m[1]), `    ${sanitize(m[1])} {${m[2]}}`);
      }
      return map;
    };

    const parseRelationLines = (body) => {
      const out = [];
      const re =
        /([A-Za-z0-9_]+)\s+([|}o{\-]+--+[|}o{\-]+)\s+([A-Za-z0-9_]+)\s*:\s*([A-Za-z0-9_]+)/g;
      let m;
      while ((m = re.exec(body))) {
        out.push({
          from: sanitize(m[1]),
          op: m[2],
          to: sanitize(m[3]),
          label: sanitize(m[4]),
          line: `    ${sanitize(m[1])} ${m[2]} ${sanitize(m[3])} : ${sanitize(m[4])}`,
        });
      }
      return out;
    };

    const entityBlocks = parseEntityBlocks(fullSource);
    const relationLines = parseRelationLines(fullSource);

    const fksRaw = fksEl ? JSON.parse(fksEl.textContent || "[]") : [];
    let edges = fksRaw.map((fk) => ({
      from: sanitize(fk.from_table),
      to: sanitize(fk.to_table),
      fromCol: String(fk.from_column || "").toLowerCase(),
      toCol: String(fk.to_column || "").toLowerCase(),
      label: sanitize(fk.from_column),
    }));
    if (!edges.length) {
      edges = relationLines.map((r) => ({
        from: r.from,
        to: r.to,
        fromCol: r.label.toLowerCase(),
        toCol: "",
        label: r.label,
      }));
    }

    const allEntityNames = [...entityBlocks.keys()];

    const neighborsOf = (entity) => {
      const set = new Set([entity]);
      edges.forEach((e) => {
        if (e.from === entity) set.add(e.to);
        if (e.to === entity) set.add(e.from);
      });
      return set;
    };
    const edgesForEntity = (entity) =>
      edges.filter((e) => e.from === entity || e.to === entity);
    const edgesForColumn = (colName) => {
      const key = String(colName || "").toLowerCase();
      return edges.filter((e) => e.fromCol === key || e.toCol === key);
    };

    const resolveKeepSet = (q) => {
      const qq = String(q || "").trim().toLowerCase();
      if (!qq) return null;
      const matched = allEntityNames.filter((n) => n.toLowerCase().includes(qq));
      if (!matched.length) return new Set();
      const keep = new Set();
      matched.forEach((name) => {
        neighborsOf(name).forEach((n) => keep.add(n));
      });
      return keep;
    };

    const buildMermaidBody = (keep) => {
      if (!keep) return fullSource;
      if (!keep.size) {
        return "erDiagram\n    NO_MATCH {\n        text empty\n    }";
      }
      const lines = ["erDiagram"];
      keep.forEach((name) => {
        if (entityBlocks.has(name)) lines.push(entityBlocks.get(name));
      });
      relationLines.forEach((r) => {
        if (keep.has(r.from) && keep.has(r.to)) lines.push(r.line);
      });
      return lines.join("\n");
    };

    const isInsideEntity = (el) => Boolean(el.closest(".console-diagram__entity"));

    // Mermaid 11 : id = "...-entity-NOM_TABLE-N" ou "entity-NOM_TABLE-N"
    const entityNameFromId = (g) => {
      const id = g.getAttribute("id") || "";
      const m = id.match(/entity-([A-Za-z0-9_]+)-\d+$/i);
      return m ? sanitize(m[1]) : "";
    };

    const entityLabelFromNode = (g) => {
      const p = g.querySelector(".label.name .nodeLabel p, .label.name p, .nodeLabel p");
      if (p && p.textContent) return sanitize(p.textContent);
      const fo = g.querySelector("foreignObject");
      if (fo && fo.textContent) {
        const first = fo.textContent.trim().split(/\s+/)[0];
        return sanitize(first);
      }
      return "";
    };

    const findEntityGroups = (svg) => {
      let candidates = [
        ...svg.querySelectorAll("g.node[id*='entity-'], g[id*='entity-']"),
      ];
      if (!candidates.length) {
        [...svg.querySelectorAll("g.node")].forEach((g) => candidates.push(g));
      }
      candidates = candidates.filter((g) => {
        if (!g.querySelector("path, rect, polygon")) return false;
        // Mermaid 11 : labels en foreignObject, pas en <text>
        return Boolean(
          g.querySelector("foreignObject, text, .nodeLabel, .label"),
        );
      });
      const groups = [];
      const seen = new Set();
      candidates.forEach((g) => {
        if (seen.has(g)) return;
        if (candidates.some((other) => other !== g && g.contains(other))) return;
        const name = entityNameFromId(g) || entityLabelFromNode(g);
        if (!name) return;
        seen.add(g);
        const textNodes = [
          ...g.querySelectorAll("text, .nodeLabel p, .attribute-name p"),
        ];
        groups.push({
          el: g,
          name,
          texts: textNodes.map(textOf).filter(Boolean),
          textNodes,
        });
      });
      return groups;
    };

    const findEdgePaths = (svg) => {
      // Uniquement les traits visibles (jamais les hit-areas transparentes)
      const preferred = [
        ...svg.querySelectorAll("path.relationshipLine, g.edgePaths > path"),
      ].filter(
        (p) =>
          !p.classList.contains("console-diagram__hit") &&
          !isInsideEntity(p),
      );
      if (preferred.length) return preferred;

      let svgArea = 1;
      try {
        const b = svg.getBBox();
        svgArea = Math.max(1, b.width * b.height);
      } catch {
        /* ignore */
      }
      return [...svg.querySelectorAll("path, line")].filter((path) => {
        if (path.classList.contains("console-diagram__hit")) return false;
        if (isInsideEntity(path)) return false;
        const cls = `${path.getAttribute("class") || ""} ${path.getAttribute("id") || ""}`;
        if (/marker|background|outline|entityBox|brush/i.test(cls)) return false;
        try {
          const box = path.getBBox();
          const area = box.width * box.height;
          if (area > svgArea * 0.3) return false;
          if (path.tagName.toLowerCase() === "line") {
            return Math.hypot(box.width, box.height) > 10;
          }
          const len = typeof path.getTotalLength === "function" ? path.getTotalLength() : 0;
          return len >= 12;
        } catch {
          return false;
        }
      });
    };

    /** Bordures de table Mermaid 11 = paths avec stroke (pas des rect). */
    const entityBorderPaths = (entityEl) =>
      [...entityEl.querySelectorAll("path")].filter((p) => {
        const stroke = p.getAttribute("stroke");
        if (!stroke || stroke === "none" || stroke === "transparent") return false;
        if (p.classList.contains("console-diagram__hit")) return false;
        return true;
      });

    const entityFillPaths = (entityEl) =>
      [...entityEl.querySelectorAll("g.outer-path > path[fill], path")].filter((p) => {
        const fill = p.getAttribute("fill");
        const stroke = p.getAttribute("stroke");
        if (!fill || fill === "none") return false;
        if (stroke && stroke !== "none") return false;
        // Prefer the outer body fill
        return p.closest("g.outer-path") || p.parentElement === entityEl;
      });

    const fkFromEdgeEl = (path) => {
      const raw =
        path.getAttribute("data-id") ||
        path.getAttribute("id") ||
        "";
      const m = raw.match(
        /entity-([A-Za-z0-9_]+)-\d+_entity-([A-Za-z0-9_]+)-\d+/i,
      );
      if (!m) return null;
      return {
        from: sanitize(m[1]),
        to: sanitize(m[2]),
        fromCol: "",
        toCol: "",
        label: "",
      };
    };

    const centerOf = (el) => {
      const b = el.getBBox();
      return { x: b.x + b.width / 2, y: b.y + b.height / 2 };
    };

    const matchEdgeToFk = (path, entityMap) => {
      const fromId = fkFromEdgeEl(path);
      if (fromId) return fromId;

      const parent = path.parentNode;
      const labelText = parent ? textOf(parent).toLowerCase() : "";
      for (const e of edges) {
        if (
          (e.fromCol && labelText.includes(e.fromCol)) ||
          (e.label && labelText.includes(e.label.toLowerCase()))
        ) {
          return e;
        }
      }
      try {
        const p = centerOf(path);
        let best = null;
        let bestScore = Infinity;
        for (const e of edges) {
          const a = entityMap.get(e.from);
          const b = entityMap.get(e.to);
          if (!a || !b) continue;
          const ac = centerOf(a);
          const bc = centerOf(b);
          const dx = bc.x - ac.x;
          const dy = bc.y - ac.y;
          const len2 = dx * dx + dy * dy || 1;
          let t = ((p.x - ac.x) * dx + (p.y - ac.y) * dy) / len2;
          t = Math.max(0, Math.min(1, t));
          const qx = ac.x + t * dx;
          const qy = ac.y + t * dy;
          const dist = (p.x - qx) ** 2 + (p.y - qy) ** 2;
          if (dist < bestScore) {
            bestScore = dist;
            best = e;
          }
        }
        return best;
      } catch {
        return edges[0] || null;
      }
    };

    const nearestEntities = (path, entityMap) => {
      try {
        const p = centerOf(path);
        const ranked = [...entityMap.entries()]
          .map(([name, el]) => {
            const c = centerOf(el);
            return { name, d: (c.x - p.x) ** 2 + (c.y - p.y) ** 2 };
          })
          .sort((a, b) => a.d - b.d);
        if (ranked.length >= 2) {
          return {
            from: ranked[0].name,
            to: ranked[1].name,
            fromCol: "",
            toCol: "",
            label: "",
          };
        }
      } catch {
        /* ignore */
      }
      return null;
    };

    let activeKey = null;
    let hotColor = readPrimary();
    let renderToken = 0;
    let debounceTimer = null;
    let lastFilterQ = "";

    const rememberOrig = (el, attrs) => {
      attrs.forEach((name) => {
        const key = `data-orig-${name}`;
        if (el.hasAttribute(key)) return;
        const val = el.getAttribute(name);
        el.setAttribute(key, val == null ? "" : val);
      });
    };

    const restoreOrig = (el) => {
      ["stroke", "stroke-width", "fill", "opacity"].forEach((name) => {
        const key = `data-orig-${name}`;
        if (!el.hasAttribute(key)) return;
        const val = el.getAttribute(key);
        if (val === "") el.removeAttribute(name);
        else el.setAttribute(name, val);
        el.removeAttribute(key);
      });
      if (el.hasAttribute("data-orig-color")) {
        const c = el.getAttribute("data-orig-color");
        if (c === "") el.style.removeProperty("color");
        else el.style.color = c;
        el.removeAttribute("data-orig-color");
      }
      ["stroke", "stroke-width", "opacity", "fill", "font-weight", "filter", "color"].forEach((p) =>
        el.style.removeProperty(p),
      );
    };

    // Couleur uniquement â€” ne pas changer stroke-width (sinon markers/points grossissent)
    const setStrokeColor = (el, color) => {
      rememberOrig(el, ["stroke", "stroke-width"]);
      el.style.setProperty("stroke", color, "important");
      el.style.setProperty("opacity", "1", "important");
      el.setAttribute("stroke", color);
    };

    const setFill = (el, color) => {
      rememberOrig(el, ["fill"]);
      el.style.setProperty("fill", color, "important");
      el.setAttribute("fill", color);
    };

    const clearHighlight = (svg) => {
      activeKey = null;
      svg.classList.remove("console-diagram__svg--focus");
      svg.querySelectorAll("[data-console-hot], [data-console-target]").forEach((n) => {
        restoreOrig(n);
        n.removeAttribute("data-console-hot");
        n.removeAttribute("data-console-target");
      });
      svg
        .querySelectorAll(
          ".console-diagram__dim, .console-diagram__hot, .console-diagram__hot-edge, .console-diagram__hot-border, .console-diagram__hot-label, .console-diagram__hot-fk",
        )
        .forEach((n) => {
          restoreOrig(n);
          n.classList.remove(
            "console-diagram__dim",
            "console-diagram__hot",
            "console-diagram__hot-edge",
            "console-diagram__hot-border",
            "console-diagram__hot-label",
            "console-diagram__hot-fk",
          );
        });
      if (clearBtn) clearBtn.hidden = true;
    };

    const enrichFk = (fk) => {
      if (!fk) return null;
      if (fk.fromCol || fk.toCol) return fk;
      const hit = edges.find(
        (e) =>
          (e.from === fk.from && e.to === fk.to) ||
          (e.from === fk.to && e.to === fk.from),
      );
      if (!hit) return fk;
      return {
        ...fk,
        fromCol: hit.fromCol || "",
        toCol: hit.toCol || "",
        label: hit.label || fk.label || "",
      };
    };

    const highlightFkColumns = (entityGroups, hotEdges, targetEntities = new Set()) => {
      const colKeys = new Set();
      hotEdges.forEach((raw) => {
        const e = enrichFk(raw) || raw;
        if (e.fromCol) colKeys.add(String(e.fromCol).toLowerCase());
        if (e.toCol) colKeys.add(String(e.toCol).toLowerCase());
        if (e.label) colKeys.add(String(e.label).toLowerCase());
      });
      if (!colKeys.size) return;

      const paintLabel = (node, color) => {
        node.classList.add("console-diagram__hot-fk");
        node.setAttribute("data-console-hot", "1");
        if (!node.hasAttribute("data-orig-color")) {
          node.setAttribute("data-orig-color", node.style.color || "");
        }
        node.style.setProperty("color", color, "important");
        node.style.setProperty("font-weight", "700", "important");
        if (node.tagName && node.tagName.toLowerCase() === "text") {
          setFill(node, color);
        }
      };

      entityGroups.forEach((g) => {
        const fkColor = targetEntities.has(g.name) ? readPrimaryOn() : hotColor;

        // Mermaid 11 : colonnes = .label.attribute-name > foreignObject > p
        const attrLabels = [
          ...g.el.querySelectorAll(
            ".label.attribute-name .nodeLabel p, .label.attribute-name p, .attribute-name p",
          ),
        ];
        attrLabels.forEach((p) => {
          const name = (p.textContent || "").trim().toLowerCase();
          if (!name || !colKeys.has(name)) return;
          paintLabel(p, fkColor);
          // Colorer aussi le type sur la meme ligne (sibling attribute-type proche)
          const row = p.closest("g.label");
          if (row && row.parentElement) {
            // Pas de lien DOM direct type/name ; on colore uniquement le nom FK
          }
        });

        // Fallback SVG <text> (anciens renderers)
        g.textNodes.forEach((tNode, idx) => {
          if (idx === 0) return;
          const raw = textOf(tNode).toLowerCase();
          const tokens = raw.split(/[^a-z0-9_]+/).filter(Boolean);
          const last = tokens[tokens.length - 1] || "";
          const hit = [...colKeys].some(
            (c) => c && (last === c || tokens.includes(c)),
          );
          if (!hit) return;
          paintLabel(tNode, fkColor);
        });
      });
    };

    const pathNearHotEdge = (path, entityMap, hotEdges) => {
      try {
        const p = centerOf(path);
        return hotEdges.some((h) => {
          const a = entityMap.get(h.from);
          const b = entityMap.get(h.to);
          if (!a || !b) return false;
          const ac = centerOf(a);
          const bc = centerOf(b);
          const mid = { x: (ac.x + bc.x) / 2, y: (ac.y + bc.y) / 2 };
          return (mid.x - p.x) ** 2 + (mid.y - p.y) ** 2 < 16000;
        });
      } catch {
        return false;
      }
    };

    const paintEntity = (g, { isTarget }) => {
      g.el.classList.add("console-diagram__hot");
      g.el.classList.remove("console-diagram__dim");
      g.el.setAttribute("data-console-hot", "1");

      // Mermaid 11 : bordures = paths stroke="#ccc" (pas des rect)
      entityBorderPaths(g.el).forEach((p) => {
        p.setAttribute("data-console-hot", "1");
        p.classList.add("console-diagram__hot-border");
        setStrokeColor(p, hotColor);
      });

      // Fallback legacy rect
      g.el.querySelectorAll("rect").forEach((r) => {
        r.setAttribute("data-console-hot", "1");
        setStrokeColor(r, hotColor);
        if (isTarget) setFill(r, hotColor);
      });

      if (isTarget) {
        g.el.setAttribute("data-console-target", "1");
        const fills = entityFillPaths(g.el);
        (fills.length ? fills : [...g.el.querySelectorAll("g.outer-path > path")].slice(0, 1)).forEach(
          (p) => {
            p.setAttribute("data-console-hot", "1");
            setFill(p, hotColor);
          },
        );
        g.el.querySelectorAll(".nodeLabel p, text").forEach((t) => {
          t.setAttribute("data-console-hot", "1");
          if (!t.hasAttribute("data-orig-color")) {
            t.setAttribute("data-orig-color", t.style.color || "");
          }
          t.style.setProperty("color", readPrimaryOn(), "important");
          if (t.tagName && t.tagName.toLowerCase() === "text") setFill(t, readPrimaryOn());
        });
      } else {
        g.el.removeAttribute("data-console-target");
      }
    };

    const paintEdgePath = (path) => {
      if (!path || path.classList.contains("console-diagram__hit")) return;
      path.classList.remove("console-diagram__dim");
      path.classList.add("console-diagram__hot-edge");
      path.setAttribute("data-console-hot", "1");
      // Couleur seule â€” garder le stroke-width Mermaid (evite markers qui grossissent)
      setStrokeColor(path, hotColor);
      path.style.setProperty("fill", "none", "important");
    };

    const applyHighlight = (
      svg,
      hotEntities,
      hotEdges,
      targetEntities = new Set(),
      forcePaths = [],
    ) => {
      hotColor = readPrimary();
      svg.classList.add("console-diagram__svg--focus");
      const entityGroups = findEntityGroups(svg);
      const entityMap = new Map(entityGroups.map((g) => [g.name, g.el]));
      const edgePaths = findEdgePaths(svg);

      entityGroups.forEach((g) => {
        const isTarget = targetEntities.has(g.name);
        const hot = isTarget || hotEntities.has(g.name);
        if (hot) {
          paintEntity(g, { isTarget });
        } else {
          g.el.classList.add("console-diagram__dim");
          g.el.classList.remove("console-diagram__hot");
        }
      });

      const forceSet = new Set(
        forcePaths
          .map((p) => {
            if (!p) return null;
            if (p.classList && p.classList.contains("console-diagram__hit")) {
              const idx = p.getAttribute("data-console-edge");
              return idx != null ? edgePaths[Number(idx)] : null;
            }
            return p;
          })
          .filter(Boolean),
      );

      edgePaths.forEach((path) => {
        if (forceSet.has(path)) return;
        let fk = matchEdgeToFk(path, entityMap);
        if (!fk && hotEdges.length === 1) fk = hotEdges[0];
        const isHot =
          Boolean(fk) &&
          hotEdges.some(
            (h) =>
              (h.from === fk.from && h.to === fk.to) ||
              (h.from === fk.to && h.to === fk.from),
          );
        const near = !isHot && hotEdges.length
          ? pathNearHotEdge(path, entityMap, hotEdges)
          : false;
        if (isHot || near) {
          paintEdgePath(path);
        } else {
          path.classList.add("console-diagram__dim");
        }
      });

      forceSet.forEach((p) => paintEdgePath(p));

      highlightFkColumns(entityGroups, hotEdges, targetEntities);
      if (clearBtn) clearBtn.hidden = false;
    };

    const selectEntity = (svg, entity) => {
      const key = `entity:${entity}`;
      if (activeKey === key) {
        clearHighlight(svg);
        return;
      }
      clearHighlight(svg);
      activeKey = key;
      applyHighlight(svg, neighborsOf(entity), edgesForEntity(entity));
    };

    const selectEdge = (svg, fk, clickedPath = null) => {
      const full = enrichFk(fk);
      if (!full) return;
      const key = `edge:${full.from}:${full.to}:${full.fromCol || full.label}`;
      if (activeKey === key) {
        clearHighlight(svg);
        return;
      }
      clearHighlight(svg);
      activeKey = key;
      applyHighlight(
        svg,
        new Set([full.from, full.to]),
        [full],
        new Set(),
        clickedPath ? [clickedPath] : [],
      );
    };

    const selectColumn = (svg, colName, entityHint) => {
      const related = edgesForColumn(colName);
      if (!related.length) {
        if (entityHint) selectEntity(svg, entityHint);
        return;
      }
      const key = `col:${colName.toLowerCase()}`;
      if (activeKey === key) {
        clearHighlight(svg);
        return;
      }
      const hotEntities = new Set();
      related.forEach((e) => {
        hotEntities.add(e.from);
        hotEntities.add(e.to);
      });
      clearHighlight(svg);
      activeKey = key;
      applyHighlight(svg, hotEntities, related);
    };

    const wireSvg = (svg) => {
      svg.classList.add("console-diagram__svg", "console-diagram__svg--interactive");
      svg.style.cursor = "default";

      // Style injecte DANS le SVG pour battre `#mmd-xxx .relationshipLine { stroke: lightgrey }`
      const ns = "http://www.w3.org/2000/svg";
      const style = document.createElementNS(ns, "style");
      style.textContent = [
        "path.relationshipLine.console-diagram__hot-edge{",
        "stroke:var(--console-primary)!important;fill:none!important;opacity:1!important;",
        "}",
        "g.console-diagram__hot path.console-diagram__hot-border{",
        "stroke:var(--console-primary)!important;",
        "}",
        "g.console-diagram__hot[data-console-target] g.outer-path > path:first-child{",
        "fill:var(--console-primary)!important;",
        "}",
        ".console-diagram__hot-fk,.console-diagram__hot-fk p{",
        "color:var(--console-primary)!important;font-weight:700!important;",
        "}",
      ].join("");
      svg.insertBefore(style, svg.firstChild);

      const groups = findEntityGroups(svg);
      const entityMap = new Map(groups.map((g) => [g.name, g.el]));

      // Marquer les entites AVANT la detection des liens (exclusion fiable)
      groups.forEach(({ el, name }) => {
        el.classList.add("console-diagram__entity");
        el.setAttribute("data-console-entity", name);
        el.style.cursor = "pointer";
      });

      const edgePaths = findEdgePaths(svg);

      // Hit-areas larges au-dessus du diagramme pour cliquer les fils
      const hitLayer = document.createElementNS(ns, "g");
      hitLayer.setAttribute("class", "console-diagram__hits");
      const mount = svg.querySelector(":scope > g") || svg;
      mount.appendChild(hitLayer);

      edgePaths.forEach((path, idx) => {
        path.classList.add("console-diagram__edge");
        path.setAttribute("data-console-edge", String(idx));
        path.style.cursor = "pointer";

        // Hit-area dediee : PAS de class relationshipLine (sinon on colore le path invisible)
        const hit = document.createElementNS(ns, "path");
        const d = path.getAttribute("d");
        if (d) hit.setAttribute("d", d);
        hit.setAttribute("class", "console-diagram__hit");
        hit.setAttribute("data-console-edge", String(idx));
        hit.setAttribute("fill", "none");
        hit.setAttribute("stroke", "rgba(0,0,0,0.001)");
        hit.setAttribute("stroke-width", "18");
        hit.style.pointerEvents = "stroke";
        hit.style.cursor = "pointer";
        hitLayer.appendChild(hit);
      });

      // Delegation unique : plus robuste que les listeners par element
      svg.addEventListener("click", (ev) => {
        const target = ev.target instanceof Element ? ev.target : null;
        if (!target) return;

        const edgeEl = target.closest("[data-console-edge]");
        if (edgeEl) {
          ev.preventDefault();
          ev.stopPropagation();
          const idx = Number(edgeEl.getAttribute("data-console-edge"));
          const path = edgePaths[idx];
          if (!path) return;
          let fk = matchEdgeToFk(path, entityMap);
          if (!fk) fk = nearestEntities(path, entityMap);
          selectEdge(svg, fk, path);
          return;
        }

        const entEl = target.closest("[data-console-entity], g.node");
        if (entEl) {
          ev.preventDefault();
          ev.stopPropagation();
          const name =
            entEl.getAttribute("data-console-entity") ||
            entityNameFromId(entEl) ||
            entityLabelFromNode(entEl);
          if (!name) return;

          // Clic sur une ligne attribut (foreignObject / p)
          const attrName = target.closest(".attribute-name");
          if (attrName) {
            const label = (attrName.textContent || "").trim();
            if (label && sanitize(label) !== name) {
              selectColumn(svg, label, name);
              return;
            }
          }
          const textEl = target.closest("text");
          if (textEl) {
            const label = textOf(textEl);
            if (sanitize(label) !== name) {
              const tokens = label.replace(/[^A-Za-z0-9_]+/g, " ").trim().split(/\s+/);
              selectColumn(svg, tokens[tokens.length - 1] || label, name);
              return;
            }
          }
          selectEntity(svg, name);
        }
      });

      if (clearBtn) {
        clearBtn.onclick = (ev) => {
          ev.stopPropagation();
          clearHighlight(svg);
        };
      }

      // Si filtre actif : la table cible en fond primary, voisines en bordure
      if (lastFilterQ.trim()) {
        const keep = resolveKeepSet(lastFilterQ);
        if (keep && keep.size) {
          const qq = lastFilterQ.trim().toLowerCase();
          const matched = [...keep].filter((n) => n.toLowerCase().includes(qq));
          const targets = new Set(matched.length ? matched : [[...keep][0]]);
          const hotEntities = new Set();
          const hotEdges = [];
          targets.forEach((t) => {
            neighborsOf(t).forEach((n) => hotEntities.add(n));
            edgesForEntity(t).forEach((e) => hotEdges.push(e));
          });
          activeKey = `search:${lastFilterQ}`;
          applyHighlight(svg, hotEntities, hotEdges, targets);
        }
      }
    };

    const renderDiagram = async (body) => {
      const token = ++renderToken;
      if (!body.trim()) {
        host.innerHTML = '<p class="console-flash console-flash--error">Diagramme vide.</p>';
        return;
      }
      try {
        if (!window.__consoleMermaidReady) {
          mermaid.initialize({
            startOnLoad: false,
            theme: "dark",
            securityLevel: "loose",
            er: { useMaxWidth: true },
          });
          window.__consoleMermaidReady = true;
        }
        const id = "mmd-" + Date.now() + "-" + token;
        const { svg } = await mermaid.render(id, body);
        if (token !== renderToken) return;
        const wrap = document.createElement("div");
        wrap.className = "console-diagram__viewport";
        const parsed = new DOMParser().parseFromString(svg, "image/svg+xml");
        const svgNode = parsed.documentElement;
        if (
          !svgNode ||
          svgNode.nodeName.toLowerCase() !== "svg" ||
          parsed.querySelector("parsererror")
        ) {
          throw new Error("SVG invalide");
        }
        const imported = document.importNode(svgNode, true);
        wrap.appendChild(imported);
        host.innerHTML = "";
        host.appendChild(wrap);
        requestAnimationFrame(() => {
          if (token !== renderToken) return;
          wireSvg(imported);
          if (window.__consoleDiagramApplyPanZoom) window.__consoleDiagramApplyPanZoom();
        });
      } catch (err) {
        if (token !== renderToken) return;
        host.innerHTML =
          '<p class="console-flash console-flash--error" role="alert">' +
          "Impossible de rendre le diagramme Mermaid.</p>";
      }
    };

    const applySearchFilter = (q) => {
      lastFilterQ = String(q || "");
      window.__consoleTableQ = lastFilterQ.trim();
      const keep = resolveKeepSet(lastFilterQ);
      if (keep && !keep.size) {
        host.innerHTML =
          '<p class="console-empty">Aucune table correspondante pour cette recherche.</p>';
        if (clearBtn) clearBtn.hidden = true;
        return;
      }
      const body = buildMermaidBody(keep);
      void renderDiagram(body);
    };

    const onFilter = (ev) => {
      const q = ev.detail?.q || "";
      clearTimeout(debounceTimer);
      debounceTimer = setTimeout(() => applySearchFilter(q), 120);
    };
    const onFocus = (ev) => {
      const name = sanitize(ev.detail?.name || "");
      if (!name) return;
      lastFilterQ = name;
      window.__consoleTableQ = name;
      void renderDiagram(buildMermaidBody(neighborsOf(name))).then(() => {
        /* wireSvg applique deja le focus search si lastFilterQ set */
      });
    };

    window.addEventListener("console:filter-tables", onFilter);
    window.addEventListener("console:focus-table", onFocus);

    // Pan (clic droit maintenu) + zoom (molette), persistant entre re-rendus
    const panZoom = { scale: 1, tx: 0, ty: 0, panning: false, lastX: 0, lastY: 0 };

    const applyPanZoom = () => {
      const svg = host.querySelector("svg");
      if (!svg) return;
      svg.style.transformOrigin = "0 0";
      svg.style.transform =
        `translate(${panZoom.tx}px, ${panZoom.ty}px) scale(${panZoom.scale})`;
    };
    window.__consoleDiagramApplyPanZoom = applyPanZoom;

    host.addEventListener(
      "wheel",
      (ev) => {
        if (!host.querySelector("svg")) return;
        ev.preventDefault();
        const rect = host.getBoundingClientRect();
        const px = ev.clientX - rect.left;
        const py = ev.clientY - rect.top;
        const factor = ev.deltaY < 0 ? 1.1 : 1 / 1.1;
        const next = Math.min(4, Math.max(0.2, panZoom.scale * factor));
        const real = next / panZoom.scale;
        // Garde le point sous le curseur stable pendant le zoom
        panZoom.tx = px - (px - panZoom.tx) * real;
        panZoom.ty = py - (py - panZoom.ty) * real;
        panZoom.scale = next;
        applyPanZoom();
      },
      { passive: false },
    );

    host.addEventListener("contextmenu", (ev) => ev.preventDefault());

    host.addEventListener("mousedown", (ev) => {
      if (ev.button !== 2 || !host.querySelector("svg")) return;
      ev.preventDefault();
      panZoom.panning = true;
      panZoom.lastX = ev.clientX;
      panZoom.lastY = ev.clientY;
      host.classList.add("console-diagram__canvas--panning");
    });

    const onPanMove = (ev) => {
      if (!panZoom.panning) return;
      panZoom.tx += ev.clientX - panZoom.lastX;
      panZoom.ty += ev.clientY - panZoom.lastY;
      panZoom.lastX = ev.clientX;
      panZoom.lastY = ev.clientY;
      applyPanZoom();
    };
    const onPanEnd = (ev) => {
      if (!panZoom.panning || ev.button !== 2) return;
      panZoom.panning = false;
      host.classList.remove("console-diagram__canvas--panning");
    };
    window.addEventListener("mousemove", onPanMove);
    window.addEventListener("mouseup", onPanEnd);

    const mo = new MutationObserver(() => {
      if (!document.body.contains(root)) {
        window.removeEventListener("console:filter-tables", onFilter);
        window.removeEventListener("console:focus-table", onFocus);
        window.removeEventListener("mousemove", onPanMove);
        window.removeEventListener("mouseup", onPanEnd);
        mo.disconnect();
      }
    });
    mo.observe(document.body, { childList: true, subtree: true });

    applySearchFilter(window.__consoleTableQ || "");
  }
</script>
'@

    Write-TextFile -Path (Join-Path $partials "_ddl_tables.html") -Content @'
<form
  class="console-form"
  method="post"
  hx-post="{% url 'admin_panel:console_table_create' %}"
  hx-target="#console-main"
  hx-swap="innerHTML"
  novalidate
  x-data="{ tried: false }"
  @submit="tried = true; if (!$el.checkValidity()) { $event.preventDefault(); $event.stopPropagation(); }"
>
  {% csrf_token %}
  <div class="console-form__row">
    <label class="console-form__field">
      <span class="console-form__label">Nom de table <abbr class="console-form__req" title="Obligatoire">*</abbr></span>
      <input class="console-form__input" type="text" name="name" required pattern="[A-Za-z_][A-Za-z0-9_]*" aria-required="true" :class="tried && $el.validity && !$el.validity.valid && 'console-form__input--invalid'">
    </label>
    <label class="console-form__field">
      <span class="console-form__label">Colonne PK <abbr class="console-form__req" title="Obligatoire">*</abbr></span>
      <input class="console-form__input" type="text" name="pk_name" value="id" required aria-required="true" :class="tried && $el.validity && !$el.validity.valid && 'console-form__input--invalid'">
    </label>
    <label class="console-form__field">
      <span class="console-form__label">Type PK</span>
      <select class="console-form__select" name="pk_type">
        <option value="serial">serial</option>
        <option value="bigserial">bigserial</option>
        <option value="uuid">uuid</option>
      </select>
    </label>
    <label class="console-form__field">
      <span class="console-form__label">Colonne 2</span>
      <input class="console-form__input" type="text" name="col2_name" value="name">
    </label>
    <label class="console-form__field">
      <span class="console-form__label">Type col 2</span>
      <select class="console-form__select" name="col2_type">
        <option value="text">text</option>
        <option value="varchar(255)">varchar(255)</option>
        <option value="integer">integer</option>
      </select>
    </label>
    <button type="submit" class="console-btn console-btn--primary console-btn--sm">Creer table</button>
  </div>
</form>

<form
  class="console-form"
  method="post"
  hx-post="{% url 'admin_panel:console_table_drop' %}"
  hx-target="#console-main"
  hx-swap="innerHTML"
  hx-confirm="Supprimer definitivement cette table ? Action irreversible."
  novalidate
  x-data="{ tried: false }"
  @submit="tried = true; if (!$el.checkValidity()) { $event.preventDefault(); $event.stopPropagation(); }"
>
  {% csrf_token %}
  <div class="console-form__row">
    <label class="console-form__field">
      <span class="console-form__label">Table a supprimer <abbr class="console-form__req" title="Obligatoire">*</abbr></span>
      <input class="console-form__input" type="text" name="name" required pattern="[A-Za-z_][A-Za-z0-9_]*" list="console-table-names" autocomplete="off" aria-required="true" :class="tried && $el.validity && !$el.validity.valid && 'console-form__input--invalid'">
      <datalist id="console-table-names">
        {% for t in tables %}
          <option value="{{ t.name }}"></option>
        {% endfor %}
      </datalist>
    </label>
    <label class="console-form__field">
      <span class="console-form__label">Confirmer le nom <abbr class="console-form__req" title="Obligatoire">*</abbr></span>
      <input class="console-form__input" type="text" name="confirm_name" required pattern="[A-Za-z_][A-Za-z0-9_]*" placeholder="Ressaisir le nom" autocomplete="off" aria-required="true" :class="tried && $el.validity && !$el.validity.valid && 'console-form__input--invalid'">
    </label>
    <button type="submit" class="console-btn console-btn--danger console-btn--sm">Drop table</button>
  </div>
</form>
'@

    Write-TextFile -Path (Join-Path $partials "_flash.html") -Content @'
<div id="console-flash" hx-swap-oob="true">
  <p class="console-flash console-flash--{{ level|default:'success' }}">{{ message }}</p>
</div>
'@

    Write-TextFile -Path (Join-Path $regDir "login.html") -Content @'
{% load static %}
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Connexion - Console</title>
  <link rel="stylesheet" href="{% static 'css/main.css' %}">
</head>
<body class="console">
  <div class="console-login">
    <div class="console-login__card">
      <h1 class="console-login__title">Console DataStudio</h1>
      <p class="console-login__lead">Connexion superuser (session Django).</p>
      {% if form.errors %}
        <p class="console-login__error">Identifiants invalides.</p>
      {% endif %}
      <form method="post" action="{% url 'login' %}" class="console-form">
        {% csrf_token %}
        <label class="console-form__field">
          <span class="console-form__label">Utilisateur</span>
          <input class="console-form__input" type="text" name="username" autofocus required>
        </label>
        <label class="console-form__field">
          <span class="console-form__label">Mot de passe</span>
          <input class="console-form__input" type="password" name="password" required>
        </label>
        <input type="hidden" name="next" value="{{ next|default:'/admin/' }}">
        <button type="submit" class="console-btn console-btn--primary">Se connecter</button>
      </form>
    </div>
  </div>
</body>
</html>
'@
}

function Write-ConsoleViewsAndUrls {
    <#
    .SYNOPSIS
      CBV Console (superuser) + urls apps/admin_panel.
    #>
    param([Parameter(Mandatory)][string]$Root)

    $panelDir = Join-Path $Root "apps\admin_panel"
    if (-not (Test-Path -LiteralPath $panelDir)) {
        Write-Host "     Skip Console views : apps/admin_panel absent" -ForegroundColor DarkYellow
        return
    }

    Write-TextFile -Path (Join-Path $panelDir "views.py") -Content @'
from __future__ import annotations

"""Vues template Console DataStudio (HTMX).

Toute logique passe par services / selectors admin_panel.
"""

from typing import Any

from django.contrib.auth.mixins import LoginRequiredMixin, UserPassesTestMixin
from django.http import Http404, HttpRequest, HttpResponse
from django.shortcuts import render
from django.views import View
from django.views.generic import TemplateView

from apps.admin_panel import selectors, services
from apps.admin_panel.services import (
    AdminDdlError,
    AdminDmlError,
    AdminModelValidationError,
    is_ddl_table_blacklisted,
    validate_sql_identifier,
)


class SuperuserRequiredMixin(LoginRequiredMixin, UserPassesTestMixin):
    """Exige un superuser authentifie (session Django).

    MRO:
    1. LoginRequiredMixin.dispatch -> redirection /accounts/login/
    2. UserPassesTestMixin.dispatch -> 403 si non superuser
    3. Vue concrete
    """

    login_url = "/accounts/login/"
    redirect_field_name = "next"

    def test_func(self) -> bool:
        user = self.request.user
        return bool(user.is_authenticated and user.is_active and user.is_superuser)


def _require_valid_table_name(table: str) -> str:
    """Valide l'identifiant de table (anti injection / path traversal URL).

    Raises:
        Http404: Identifiant hors motif ``^[a-zA-Z_][a-zA-Z0-9_]*$``.
    """
    try:
        return validate_sql_identifier(table, label="Nom de table")
    except AdminDdlError as exc:
        raise Http404("Table introuvable.") from exc


def _safe_overview() -> dict[str, Any]:
    try:
        return selectors.get_database_schema_overview()
    except selectors.AdminIntrospectionError:
        return {"tables": [], "foreign_keys": []}


def _build_display_rows(table_data: dict[str, Any]) -> tuple[list[dict[str, Any]], str | None]:
    """Construit les cellules d'affichage avec flag ``is_editable``."""
    pks = table_data.get("primary_keys") or []
    pk = str(pks[0]) if pks else None
    columns = list(table_data.get("columns") or [])
    source = str(table_data.get("source") or "sql")
    registry = table_data.get("registry")
    editable_cols: set[str] | None = None
    if source == "orm" and isinstance(registry, dict):
        from django.apps import apps as django_apps

        model = django_apps.get_model(registry["app_label"], registry["model_name"])
        editable_cols = {
            f.name for f in model._meta.concrete_fields if f.editable
        }
    display_rows: list[dict[str, Any]] = []
    for raw in table_data.get("rows") or []:
        assert isinstance(raw, dict)
        cells = []
        for col in columns:
            val = raw.get(col)
            is_null = val is None or val == ""
            is_pk = col == pk
            if is_pk or col == "password_set" or not pk:
                is_editable = False
            elif editable_cols is not None:
                is_editable = col in editable_cols
            else:
                is_editable = True
            cells.append(
                {
                    "name": col,
                    "display": "" if is_null else str(val),
                    "is_null": is_null,
                    "is_pk": is_pk,
                    "is_editable": is_editable,
                }
            )
        display_rows.append(
            {
                "pk_value": raw.get(pk) if pk else None,
                "cells": cells,
            }
        )
    return display_rows, pk


def _build_insert_fields(
    table_data: dict[str, Any],
    structure_columns: list[dict[str, Any]],
    pk: str | None,
) -> list[dict[str, Any]]:
    """Champs du formulaire d'insertion (obligatoires marques pour l'UI)."""
    columns = list(table_data.get("columns") or [])
    source = str(table_data.get("source") or "sql")
    registry = table_data.get("registry")
    meta = {
        str(col["name"]): col
        for col in structure_columns
        if isinstance(col, dict) and col.get("name")
    }
    orm_required: set[str] = set()
    if source == "orm" and isinstance(registry, dict):
        from django.apps import apps as django_apps

        model = django_apps.get_model(registry["app_label"], registry["model_name"])
        for field in model._meta.concrete_fields:
            if not field.editable or field.primary_key:
                continue
            if field.name == "password":
                orm_required.add("password")
                continue
            if not field.blank and not field.null:
                orm_required.add(field.name)

    fields: list[dict[str, Any]] = []
    seen: set[str] = set()
    for col in columns:
        if col in {pk, "password_set"} or col in seen:
            continue
        seen.add(col)
        info = meta.get(col, {})
        if source == "orm":
            is_required = col in orm_required
        else:
            is_required = (
                not bool(info.get("nullable", True))
                and info.get("default") is None
                and not bool(info.get("primary_key", False))
            )
        fields.append(
            {
                "name": col,
                "label": col,
                "required": is_required,
                "input_type": "text",
            }
        )

    if (
        source == "orm"
        and isinstance(registry, dict)
        and str(registry.get("app_label")) == "auth"
        and str(registry.get("model_name")) == "user"
        and "password" not in seen
    ):
        insert_at = next(
            (i for i, item in enumerate(fields) if item["name"] == "username"),
            -1,
        )
        password_field = {
            "name": "password",
            "label": "password",
            "required": True,
            "input_type": "password",
        }
        if insert_at >= 0:
            fields.insert(insert_at + 1, password_field)
        else:
            fields.append(password_field)
    return fields


def _table_panel_context(request: HttpRequest, table_name: str) -> dict[str, Any]:
    safe_name = _require_valid_table_name(table_name)
    try:
        data = services.list_table_rows(safe_name, actor=request.user)
    except AdminDmlError as exc:
        raise Http404("Table introuvable.") from exc
    display_rows, pk = _build_display_rows(data)
    overview = _safe_overview()
    match = next((t for t in overview["tables"] if t["name"] == safe_name), None)
    structure_columns = list(match["columns"]) if match else []
    return {
        "table_name": safe_name,
        "columns": list(data.get("columns") or []),
        "display_rows": display_rows,
        "pk": pk,
        "source": data.get("source", "sql"),
        "structure_columns": structure_columns,
        "insert_fields": _build_insert_fields(data, structure_columns, pk),
        "can_ddl": not is_ddl_table_blacklisted(safe_name),
        "tables": overview["tables"],
        "foreign_keys": overview["foreign_keys"],
        "selected_table": safe_name,
    }


def _admin_context(request: HttpRequest, selected: str | None = None) -> dict[str, Any]:
    overview = _safe_overview()
    tables = overview["tables"]
    assert isinstance(tables, list)
    selected_table = selected or (tables[0]["name"] if tables else None)
    ctx: dict[str, Any] = {
        "tab": "admin",
        "tables": tables,
        "foreign_keys": overview["foreign_keys"],
        "selected_table": selected_table,
        "mermaid": selectors.export_schema_mermaid_body(),
        "stats": selectors.get_console_welcome_stats(),
    }
    if selected_table:
        ctx.update(_table_panel_context(request, str(selected_table)))
    return ctx


def _flash(request: HttpRequest, message: str, *, level: str = "success") -> str:
    return render(
        request,
        "console/partials/_flash.html",
        {"message": message, "level": level},
    ).content.decode("utf-8")


class ConsoleShellView(SuperuserRequiredMixin, TemplateView):
    """Shell Console (Welcome | Admin).

    MRO:
    1. SuperuserRequiredMixin.dispatch
    2. TemplateView.get -> shell ou partial HTMX
    """

    template_name = "console/shell.html"

    def get_template_names(self) -> list[str]:
        if getattr(self.request, "htmx", False) and self.request.htmx:
            tab = (self.request.GET.get("tab") or "welcome").strip()
            if tab == "admin":
                return ["console/partials/_admin.html"]
            return ["console/partials/_welcome.html"]
        return [self.template_name]

    def get_context_data(self, **kwargs: object) -> dict[str, object]:
        context = super().get_context_data(**kwargs)
        tab = (self.request.GET.get("tab") or "welcome").strip()
        if tab == "admin":
            context.update(_admin_context(self.request))
        else:
            context["tab"] = "welcome"
            context["stats"] = selectors.get_console_welcome_stats()
        return context


class ConsoleAdminPartialView(SuperuserRequiredMixin, TemplateView):
    """Partial Admin (Donnees / Schema / Query / Diagram).

    MRO:
    1. SuperuserRequiredMixin.dispatch
    2. TemplateView.get -> _admin.html
    """

    template_name = "console/partials/_admin.html"

    def get_context_data(self, **kwargs: object) -> dict[str, object]:
        context = super().get_context_data(**kwargs)
        context.update(_admin_context(self.request))
        return context


class ConsoleTablePanelView(SuperuserRequiredMixin, TemplateView):
    """Panneau editeur + structure pour une table.

    MRO:
    1. SuperuserRequiredMixin.dispatch
    2. TemplateView.get -> _table_editor.html
    """

    template_name = "console/partials/_table_editor.html"

    def get_context_data(self, **kwargs: object) -> dict[str, object]:
        context = super().get_context_data(**kwargs)
        table_name = str(self.kwargs["table"])
        context.update(_table_panel_context(self.request, table_name))
        return context


class ConsoleCellUpdateView(SuperuserRequiredMixin, View):
    """POST mise a jour cellule.

    MRO:
    1. SuperuserRequiredMixin.dispatch
    2. View.post -> services.update_table_cell + panel
    """

    def post(self, request: HttpRequest, table: str) -> HttpResponse:
        table = _require_valid_table_name(table)
        try:
            services.update_table_cell(
                table,
                primary_key=request.POST.get("primary_key", ""),
                primary_key_value=request.POST.get("primary_key_value", ""),
                column=request.POST.get("column", ""),
                value=request.POST.get("value"),
                actor=request.user,
            )
            msg = "Cellule mise a jour."
            level = "success"
        except (AdminDmlError, AdminDdlError, AdminModelValidationError, ValueError) as exc:
            msg = str(exc)
            level = "error"
        response = render(request, "console/partials/_table_editor.html", _table_panel_context(request, table))
        response.content = _flash(request, msg, level=level).encode("utf-8") + response.content
        return response


class ConsoleRowInsertView(SuperuserRequiredMixin, View):
    """POST insertion ligne.

    MRO:
    1. SuperuserRequiredMixin.dispatch
    2. View.post -> services.insert_table_row
    """

    def post(self, request: HttpRequest, table: str) -> HttpResponse:
        table = _require_valid_table_name(table)
        payload: dict[str, object] = {}
        for key, value in request.POST.items():
            if key.startswith("field__"):
                payload[key.removeprefix("field__")] = value
        try:
            services.insert_table_row(table, payload, actor=request.user)
            msg, level = "Ligne creee.", "success"
        except (AdminDmlError, AdminDdlError, AdminModelValidationError, ValueError) as exc:
            msg, level = str(exc), "error"
        response = render(request, "console/partials/_table_editor.html", _table_panel_context(request, table))
        response.content = _flash(request, msg, level=level).encode("utf-8") + response.content
        return response


class ConsoleRowDeleteView(SuperuserRequiredMixin, View):
    """POST suppression ligne.

    MRO:
    1. SuperuserRequiredMixin.dispatch
    2. View.post -> services.delete_table_row
    """

    def post(self, request: HttpRequest, table: str) -> HttpResponse:
        table = _require_valid_table_name(table)
        try:
            services.delete_table_row(
                table,
                primary_key=request.POST.get("primary_key", ""),
                primary_key_value=request.POST.get("primary_key_value", ""),
                actor=request.user,
            )
            msg, level = "Ligne supprimee.", "success"
        except (AdminDmlError, AdminDdlError, ValueError) as exc:
            msg, level = str(exc), "error"
        response = render(request, "console/partials/_table_editor.html", _table_panel_context(request, table))
        response.content = _flash(request, msg, level=level).encode("utf-8") + response.content
        return response


class ConsoleColumnAddView(SuperuserRequiredMixin, View):
    """POST ADD COLUMN.

    MRO: SuperuserRequiredMixin -> View.post -> services.add_column
    """

    def post(self, request: HttpRequest, table: str) -> HttpResponse:
        table = _require_valid_table_name(table)
        try:
            services.add_column(
                table,
                request.POST.get("name", ""),
                request.POST.get("pg_type", "text"),
                nullable=request.POST.get("nullable", "1") == "1",
                actor=request.user,
            )
            msg, level = "Colonne ajoutee.", "success"
        except AdminDdlError as exc:
            msg, level = str(exc), "error"
        response = render(request, "console/partials/_table_editor.html", _table_panel_context(request, table))
        response.content = _flash(request, msg, level=level).encode("utf-8") + response.content
        return response


class ConsoleColumnRenameView(SuperuserRequiredMixin, View):
    """POST RENAME COLUMN.

    MRO: SuperuserRequiredMixin -> View.post -> services.rename_column
    """

    def post(self, request: HttpRequest, table: str) -> HttpResponse:
        table = _require_valid_table_name(table)
        try:
            services.rename_column(
                table,
                request.POST.get("old_name", ""),
                request.POST.get("new_name", ""),
                actor=request.user,
            )
            msg, level = "Colonne renommee.", "success"
        except AdminDdlError as exc:
            msg, level = str(exc), "error"
        response = render(request, "console/partials/_table_editor.html", _table_panel_context(request, table))
        response.content = _flash(request, msg, level=level).encode("utf-8") + response.content
        return response


class ConsoleColumnDropView(SuperuserRequiredMixin, View):
    """POST DROP COLUMN.

    MRO: SuperuserRequiredMixin -> View.post -> services.drop_column
    """

    def post(self, request: HttpRequest, table: str) -> HttpResponse:
        table = _require_valid_table_name(table)
        try:
            services.drop_column(table, request.POST.get("column", ""), actor=request.user)
            msg, level = "Colonne supprimee.", "success"
        except AdminDdlError as exc:
            msg, level = str(exc), "error"
        response = render(request, "console/partials/_table_editor.html", _table_panel_context(request, table))
        response.content = _flash(request, msg, level=level).encode("utf-8") + response.content
        return response


class ConsoleTableCreateView(SuperuserRequiredMixin, View):
    """POST CREATE TABLE (formulaire minimal 2 colonnes).

    MRO: SuperuserRequiredMixin -> View.post -> services.create_table
    """

    def post(self, request: HttpRequest) -> HttpResponse:
        name = request.POST.get("name", "").strip()
        columns = [
            {
                "name": request.POST.get("pk_name", "id"),
                "type": request.POST.get("pk_type", "serial"),
                "nullable": False,
                "primary_key": True,
            },
        ]
        col2 = request.POST.get("col2_name", "").strip()
        if col2:
            columns.append(
                {
                    "name": col2,
                    "type": request.POST.get("col2_type", "text"),
                    "nullable": True,
                    "primary_key": False,
                }
            )
        try:
            services.create_table(name, columns, actor=request.user)
        except AdminDdlError as exc:
            ctx = _admin_context(request)
            ctx["flash_error"] = str(exc)
            return render(request, "console/partials/_admin.html", ctx)
        return render(request, "console/partials/_admin.html", _admin_context(request, selected=name))


class ConsoleTableDropView(SuperuserRequiredMixin, View):
    """POST DROP TABLE (confirm_name obligatoire cote serveur).

    MRO: SuperuserRequiredMixin -> View.post -> services.drop_table
    """

    def post(self, request: HttpRequest) -> HttpResponse:
        name = request.POST.get("name", "").strip()
        confirm_name = request.POST.get("confirm_name", "").strip()
        try:
            services.drop_table(name, confirm_name=confirm_name, actor=request.user)
        except AdminDdlError as exc:
            ctx = _admin_context(request)
            ctx["flash_error"] = str(exc)
            return render(request, "console/partials/_admin.html", ctx)
        return render(request, "console/partials/_admin.html", _admin_context(request))


class ConsoleQueryView(SuperuserRequiredMixin, View):
    """POST query SELECT readonly.

    MRO: SuperuserRequiredMixin -> View.post -> selectors.execute_readonly_query
    """

    def post(self, request: HttpRequest) -> HttpResponse:
        sql = request.POST.get("sql", "")
        try:
            result = selectors.execute_readonly_query(sql)
            columns = list(result.get("columns") or [])
            display_rows = []
            for raw in result.get("rows") or []:
                assert isinstance(raw, dict)
                row_cells = []
                for col in columns:
                    val = raw.get(col)
                    is_null = val is None
                    row_cells.append(
                        {
                            "display": "" if is_null else str(val),
                            "is_null": is_null,
                        }
                    )
                display_rows.append(row_cells)
            return render(
                request,
                "console/partials/_query_result.html",
                {
                    "columns": columns,
                    "display_rows": display_rows,
                    "row_count": result.get("row_count", 0),
                    "elapsed_ms": result.get("elapsed_ms", 0),
                    "truncated": result.get("truncated", False),
                },
            )
        except selectors.AdminQueryError as exc:
            return render(
                request,
                "console/partials/_query_result.html",
                {"error": str(exc)},
            )
'@

    Write-TextFile -Path (Join-Path $panelDir "urls.py") -Content @'
from django.urls import path

from apps.admin_panel import views

app_name = "admin_panel"

urlpatterns = [
    path("", views.ConsoleShellView.as_view(), name="console_shell"),
    path("panel/", views.ConsoleAdminPartialView.as_view(), name="console_admin"),
    path("tables/<str:table>/", views.ConsoleTablePanelView.as_view(), name="console_table"),
    path("tables/<str:table>/cell/", views.ConsoleCellUpdateView.as_view(), name="console_cell_update"),
    path("tables/<str:table>/rows/", views.ConsoleRowInsertView.as_view(), name="console_row_insert"),
    path("tables/<str:table>/rows/delete/", views.ConsoleRowDeleteView.as_view(), name="console_row_delete"),
    path("tables/<str:table>/columns/add/", views.ConsoleColumnAddView.as_view(), name="console_column_add"),
    path("tables/<str:table>/columns/rename/", views.ConsoleColumnRenameView.as_view(), name="console_column_rename"),
    path("tables/<str:table>/columns/drop/", views.ConsoleColumnDropView.as_view(), name="console_column_drop"),
    path("ddl/create-table/", views.ConsoleTableCreateView.as_view(), name="console_table_create"),
    path("ddl/drop-table/", views.ConsoleTableDropView.as_view(), name="console_table_drop"),
    path("query/", views.ConsoleQueryView.as_view(), name="console_query"),
]
'@
}

function New-HtmxConsoleScaffold {
    <#
    .SYNOPSIS
      Genere Console HTMX complete si HasCustomAdmin.
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [bool]$HasCustomAdmin = $true
    )

    if (-not $HasCustomAdmin) {
        Write-Host "     Console HTMX : skip (HasCustomAdmin=false)" -ForegroundColor DarkGray
        return
    }

    Write-Host "     Admin HTMX DataStudio : templates + CBV /admin/" -ForegroundColor DarkGray
    Write-ConsoleTemplates -Root $Root
    Write-ConsoleViewsAndUrls -Root $Root
}
