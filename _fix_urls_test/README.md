# fix_urls_test — Django Ninja + Astro + HTMX + uv

Monorepo full-stack :

| Pilier | Techno | Role |
|--------|--------|------|
| API / metier | **Django Ninja** | JSON, schemas Pydantic, services / selectors |
| UI produit | **Astro** (`frontend/`) | Site public / landing (HTML + SCSS) |
| UI interne | **HTMX** (templates Django) | Admin DataStudio, back-office staff |

**Interdits** : Next.js, React, Tailwind / utility-first. Python via **uv** uniquement.

---

## Sommaire

1. [Prerequis](#prerequis)
2. [Demarrage rapide](#demarrage-rapide)
3. [URLs utiles](#urls-utiles)
4. [Architecture et fonctionnement](#architecture-et-fonctionnement)
5. [Variables d'environnement](#variables-denvironnement)
6. [Frontend Astro (guide)](#frontend-astro-guide)
7. [Backend Django (rapide)](#backend-django-rapide)
8. [Tests et qualite](#tests-et-qualite)
9. [Cursor](#cursor)

---

## Prerequis

| Outil | Usage |
|-------|--------|
| **Python 3.12+** + [uv](https://docs.astral.sh/uv/) | Backend Django |
| **Node 22+** + [pnpm](https://pnpm.io/) | Frontend Astro |
| **PostgreSQL 16+** (optionnel en local) | BDD ; sinon SQLite en fallback dev |
| Docker (optionnel) | Compose db / redis / services |

---

## Demarrage rapide

### 1. Backend

```powershell
cd <racine_projet>
copy .env.example .env          # adapter les secrets
uv sync
uv run python manage.py migrate
uv run python manage.py createsuperuser   # requis pour /admin/
```

### 2. Frontend Astro

```powershell
cd frontend
copy .env.example .env          # PUBLIC_API_URL / PUBLIC_DJANGO_URL
pnpm install
```

### 3. Lancer les deux serveurs (Windows)

```powershell
# Depuis la racine du projet : ouvre 2 fenetres PowerShell
.\scripts\dev-local.ps1
```

**Manuel (2 terminaux)** :

```powershell
# Terminal 1 — Django
uv run python manage.py runserver 0.0.0.0:8000

# Terminal 2 — Astro
cd frontend
pnpm dev
```

### PostgreSQL (si Docker / compose present)

```bash
docker compose up -d db
# renseigner DJANGO_USE_POSTGRES / DJANGO_DB_* dans .env
uv run python manage.py migrate
```

Sans Postgres configure : Django utilise **SQLite** (`db.sqlite3`) en dev.

---

## URLs utiles

| Surface | URL |
|---------|-----|
| UI produit Astro | http://127.0.0.1:4321 |
| API Django / health | http://127.0.0.1:8000/api/health/ |
| Admin DataStudio (HTMX) | http://127.0.0.1:8000/admin/ |
| Connexion staff | http://127.0.0.1:8000/accounts/login/ |
| Back-office HTMX | http://127.0.0.1:8000/backoffice/ |
| Admin Django natif (si active) | http://127.0.0.1:8000/django-admin/ |
| Ancien chemin console | `/console/` → redirect vers `/admin/` |

Compte **superuser** obligatoire pour `/admin/` et la connexion staff.

---

## Architecture et fonctionnement

```text
Navigateur
   │
   ├─ :4321 ──► Astro (pages produit, SCSS)
   │               │
   │               ├─ liens HTML ──► Django (/admin/, /accounts/login/, …)
   │               └─ fetch JSON ──► Django Ninja (/api/…)
   │
   └─ :8000 ──► Django
                  ├─ /api/          Ninja (schemas + services)
                  ├─ /admin/        Console DataStudio HTMX
                  ├─ /backoffice/   UI staff HTMX
                  └─ apps/*/        models → services → selectors
```

### Separation des responsabilites

| Zone | Fait | Ne fait pas |
|------|------|-------------|
| `models.py` | Schema + proprietes simples | Logique metier |
| `services.py` | Ecritures, transactions, invariants | Rendu HTML |
| `selectors.py` | Lectures optimisees | Mutations |
| `schemas.py` + `api.py` | Contrat Ninja | Regles metier hors orchestration |
| `views.py` (CBV) + templates | UI HTMX interne | Logique metier dupliquee |
| `frontend/` Astro | Presentation produit | Regles metier / secrets |

### Apps presentes

| App | Role |
|-----|------|
| `apps.core` | App metier de reference |
| `apps.admin_panel` | Registry, API `/api/admin/`, Console HTMX `/admin/` |

Detail : `.cursor/app-structure.md` et `.cursor/app-architecture.uml`.

---

## Variables d'environnement

### Racine (`.env`)

Voir `.env.example` :

- `DJANGO_SECRET_KEY`, `DJANGO_ENV`
- `CORS_ALLOWED_ORIGINS` (inclure `http://localhost:4321`)
- Optionnel : `DJANGO_DB_*`, `CELERY_*`, superuser Docker

### Frontend (`frontend/.env`)

```env
PUBLIC_API_URL=http://localhost:8000
PUBLIC_DJANGO_URL=http://localhost:8000
```

- Prefixe **`PUBLIC_`** = expose au navigateur.
- **Jamais** de secrets (mots de passe, JWT prives, cles API) dans `PUBLIC_*`.

---

## Frontend Astro (guide)

Astro genere principalement du **HTML + CSS**. Peu (ou pas) de JavaScript envoye au client par defaut. Chez nous : **mode static**, port **4321**, **zero React**.

### Structure

```text
frontend/
├── astro.config.mjs          # output: "static", port 4321, SCSS
├── package.json              # pnpm scripts
├── .env.example
└── src/
    ├── pages/                # = routes (file-based routing)
    │   ├── index.astro       # → /
    │   ├── admin.astro       # → /admin (redirige vers Django)
    │   └── login.astro       # → /login (redirige vers Django)
    ├── layouts/
    │   └── BaseLayout.astro  # coquille HTML + import SCSS
    ├── lib/api/
    │   └── client.ts         # fetch /api/health/ (ex. client API)
    ├── styles/               # SCSS 7-1 (tokens, BEM)
    └── env.d.ts
```

### Anatomie d'une page `.astro`

```astro
---
// Frontmatter : execute au build / en dev (pas dans le navigateur)
import BaseLayout from "../layouts/BaseLayout.astro";

const title = "Ma page";
const apiUrl = import.meta.env.PUBLIC_API_URL ?? "http://localhost:8000";
---

<!-- Template HTML -->
<BaseLayout title={title}>
  <main class="page-exemple">
    <h1 class="page-exemple__title">Bonjour</h1>
    <p>API : <code>{apiUrl}</code></p>
  </main>
</BaseLayout>
```

- Au-dessus de `---` : TypeScript/JS (imports, donnees, `fetch` build-time).
- En-dessous : HTML avec `{expressions}`.
- `<slot />` dans un layout = contenu enfant injecte.

### Commandes

```bash
cd frontend
pnpm install
pnpm dev       # http://127.0.0.1:4321
pnpm build     # genere dist/
pnpm preview   # sert dist/ localement
pnpm check     # verif Astro + TypeScript
```

### Ajouter une nouvelle page

1. Creer `frontend/src/pages/ma-page.astro`.
2. L’URL devient automatiquement **`/ma-page`**.
3. Reutiliser `BaseLayout` et les classes BEM existantes.

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

Sous-routes : `pages/blog/index.astro` → `/blog`, `pages/blog/[slug].astro` → `/blog/:slug` (si besoin plus tard).

### Ajouter un composant reutilisable

1. Creer `frontend/src/components/Hero.astro` (dossier a creer si absent).
2. L’importer dans une page :

```astro
---
import BaseLayout from "../layouts/BaseLayout.astro";
import Hero from "../components/Hero.astro";
---
<BaseLayout title="Accueil">
  <Hero title="Mon produit" lead="Une phrase." />
</BaseLayout>
```

Exemple de composant :

```astro
---
interface Props {
  title: string;
  lead?: string;
}
const { title, lead = "" } = Astro.props;
---
<header class="hero">
  <h1 class="hero__title">{title}</h1>
  {lead && <p class="hero__lead">{lead}</p>}
</header>
```

### Ajouter / modifier des styles

1. Tokens globaux : `src/styles/base/_root.scss` (`:root` uniquement).
2. Nouveau bloc page : `src/styles/pages/_ma-page.scss`.
3. L’importer dans `src/styles/main.scss` :

```scss
@use "pages/ma-page";
```

Convention **BEM** (`.block`, `.block__element`, `.block--modifier`).  
Mobile-first, Flexbox, **pas de Tailwind**.

### Appeler l’API Django depuis Astro

- Client d’exemple : `src/lib/api/client.ts` (`fetchHealth`).
- Etendre avec de nouveaux `fetch` vers `/api/...` (schemas Ninja).
- En page static, un `await fetch(...)` dans le frontmatter s’execute **au build / en SSR** ; pour de l’interactif navigateur, prevoir une island (`client:load`) ou un script — rare dans ce projet.

```ts
// src/lib/api/client.ts — pattern
export async function fetchHealth() {
  const base = (import.meta.env.PUBLIC_API_URL ?? "http://localhost:8000").replace(/\/$/, "");
  const res = await fetch(`${base}/api/health/`, { cache: "no-store" });
  if (!res.ok) throw new Error(`Health ${res.status}`);
  return res.json();
}
```

### Ce qui ne va **pas** dans Astro

- Logique metier (validations, droits, SQL) → **services Django**.
- Admin / CRUD staff → **HTMX** (`/admin/`, `/backoffice/`).
- Secrets → variables serveur Django, jamais `PUBLIC_*`.

### Islands (optionnel, avance)

Astro peut hydrater un ilot interactif :

```astro
<MonWidget client:load />
```

Dans ce projet on privilegie le HTML statique. L’interactivite staff reste cote HTMX + Alpine.

---

## Backend Django (rapide)

### Ajouter un endpoint API

1. Schema Pydantic dans `apps/<app>/schemas.py`.
2. Logique dans `services.py` / `selectors.py`.
3. Route dans `apps/<app>/api.py` (orchestration seule).
4. Monter le router dans `config/api.py` si besoin.

### Ajouter une vue HTMX (interne)

1. CBV dans `views.py` (pas de fonctions).
2. Partial `templates/<app>/partials/_*.html`.
3. Route dans `urls.py`.
4. Reutiliser les **memes** services que l’API Ninja.

### Console `/admin/`

- Shell HTMX DataStudio (tables, schema, query, diagramme Mermaid, DDL).
- Partial principal : `/admin/panel/`.
- API JSON associee : `/api/admin/` (JWT pour outils API).

Compiler le SCSS Django (si modifie) vers `static/css/main.css` selon le workflow du projet (pipeline sass du scaffold).

---

## Tests et qualite

```powershell
uv run pytest
uv run ruff check .
uv run ruff format .
# mypy si configure
```

Frontend :

```powershell
cd frontend
pnpm check
```

---

## Cursor

- Agents / stack : `.cursor/AGENTS.md`, `.cursor/skills/STACK.md`
- Architecture : `.cursor/app-architecture.uml`, `.cursor/app-structure.md`
- Regles : `.cursor/rules/`

En cas de doute UI : **produit / public → Astro** ; **staff / admin → HTMX**.
