# fix_urls_test-frontend (Astro)

UI produit **Astro 5** — port **4321**. Backend Django de reference : `apps.core`.

Le guide complet (lancement monorepo, architecture, ajouter pages/composants) est dans le **[README racine](../README.md#frontend-astro-guide)**.

## Demarrage

```bash
# Depuis frontend/
cp .env.example .env   # ou copy sous Windows
pnpm install
pnpm dev               # http://127.0.0.1:4321
```

Depuis la racine du monorepo (Django + Astro) :

```powershell
.\scripts\dev-local.ps1
```

## Scripts

| Commande | Role |
|----------|------|
| `pnpm dev` | Serveur de dev (hot reload) |
| `pnpm build` | Build static → `dist/` |
| `pnpm preview` | Previsualiser le build |
| `pnpm check` | Verif Astro + TypeScript |

## Variables `PUBLIC_*`

| Variable | Role |
|----------|------|
| `PUBLIC_API_URL` | Base API Ninja (ex. health `/api/health/`) |
| `PUBLIC_DJANGO_URL` | Liens HTML vers Django (`/admin/`, login, back-office) |

**Jamais de secrets** dans `PUBLIC_*`.

## Routing (rappel)

| Fichier | URL Astro |
|---------|-----------|
| `src/pages/index.astro` | `/` |
| `src/pages/admin.astro` | `/admin` → redirect Django `/admin/` |
| `src/pages/login.astro` | `/login` → redirect Django login |

Nouvelle page = nouveau fichier sous `src/pages/`.  
Nouveau composant = `src/components/*.astro`.  
Styles = SCSS 7-1 sous `src/styles/` (BEM, tokens `:root`, pas de Tailwind).

## Frontiere

- **Astro** = UI produit / publique.
- **HTMX Django** = admin DataStudio + back-office (`PUBLIC_DJANGO_URL` + `/admin/`, `/backoffice/`).
- **Zero React / Next.js.**
