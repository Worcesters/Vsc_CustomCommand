# Templates Console HTMX

Source de verite pour `New-HtmxConsoleScaffold` (`scaffold/HtmxConsole.ps1`).

```text
htmx-templates/
├── console/           → templates/console/
│   ├── base_console.html
│   ├── shell.html
│   └── partials/
├── registration/      → templates/registration/login.html
├── python/            → apps/admin_panel/views.py + urls.py
└── scss/_console.scss → static/scss/components/_console.scss
```

Editer ces fichiers, pas des here-strings dans `HtmxConsole.ps1`.
Le projet de reference `_fix_urls_test` doit rester aligne avec ce dossier.
