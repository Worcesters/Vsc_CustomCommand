# __PROJECT_TITLE__

Monorepo full-stack :

| Pilier | Techno | Role |
|--------|--------|------|
| API / metier | **Django Ninja** | JSON, schemas Pydantic, services / selectors |
| UI produit | **Astro** (`frontend/`) | Site public / landing (HTML + SCSS) |
| UI interne | **HTMX** (templates Django) | Admin DataStudio, back-office staff |

**Interdits** : Next.js, React, Tailwind / utility-first. Python via **uv** uniquement.

---

## Demarrage rapide

```powershell
cd <racine_projet>
copy .env.example .env
uv sync
uv run python manage.py migrate
uv run python manage.py createsuperuser

# Backend + Astro (2 fenetres) :
.\scripts\dev-local.ps1
```

Manuel :

```powershell
# Terminal 1
uv run python manage.py runserver 0.0.0.0:8000

# Terminal 2
cd frontend
pnpm install
pnpm dev
```

## URLs

| Surface | URL |
|---------|-----|
| UI produit Astro | http://127.0.0.1:4321 |
| API / health | http://127.0.0.1:8000/api/health/ |
| Admin DataStudio (HTMX) | http://127.0.0.1:8000/admin/ |
| Connexion staff | http://127.0.0.1:8000/accounts/login/ |
| Back-office HTMX | http://127.0.0.1:8000/backoffice/ |
| Legacy `/console/` | redirect → `/admin/` |

## Architecture

```text
:4321 Astro (produit) ──liens──► :8000 Django
                 └──fetch──► /api/... (Ninja)

:8000 Django
  /admin/       Console HTMX DataStudio
  /backoffice/  Staff HTMX
  /api/         Django Ninja
  apps/__APP_NAME__/   metier (services / selectors)
  apps/admin_panel/    API admin + console
```

- Logique metier = **services / selectors** uniquement.
- Astro = presentation ; pas de secrets dans `PUBLIC_*`.

## Frontend Astro

### Structure

```text
frontend/src/
  pages/       → routes (/ = index.astro)
  layouts/     → BaseLayout.astro
  components/  → composants .astro (a creer)
  lib/api/     → client fetch Ninja
  styles/      → SCSS 7-1 + tokens :root
```

### Ajouter une page

Creer `frontend/src/pages/ma-page.astro` → URL `/ma-page` :

```astro
---
import BaseLayout from "../layouts/BaseLayout.astro";
---
<BaseLayout title="Ma page">
  <main class="page-ma-page">
    <h1 class="page-ma-page__title">Nouvelle page</h1>
  </main>
</BaseLayout>
```

### Ajouter un composant

`frontend/src/components/Hero.astro` puis `import Hero from "../components/Hero.astro"`.

### Styles

- Tokens : `src/styles/base/_root.scss`
- Page : `src/styles/pages/_ma-page.scss` + `@use` dans `main.scss`
- BEM, mobile-first, **pas de Tailwind**

### Env frontend

```env
PUBLIC_API_URL=http://localhost:8000
PUBLIC_DJANGO_URL=http://localhost:8000
```

## Backend (rappel)

App metier : `apps.__APP_NAME__`.  
Admin : `apps.admin_panel` → `/admin/` + `/api/admin/`.  
UI staff : templates + HTMX.  
Vues template = **CBV uniquement**.

## Tests

```powershell
uv run pytest
uv run ruff check .
cd frontend ; pnpm check
```

## Cursor

Voir `.cursor/AGENTS.md`, `.cursor/skills/STACK.md`, `.cursor/app-structure.md`.
