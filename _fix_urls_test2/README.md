# Monorepo Django Ninja + Astro + HTMX + uv

## Demarrage rapide

```powershell
cd <racine_projet>
uv sync
uv run python manage.py migrate

# Demarrer backend + frontend Astro (obligatoire pour le port 4321) :
.\scripts\dev-local.ps1
```



## Base de donnees (PostgreSQL)

Avec Docker, le script genere un fichier `.env` : Django utilise **PostgreSQL** sur le port hote mappe (voir `.env` / compose).

```bash
docker compose up -d db
uv run python manage.py migrate
uv run python manage.py createsuperuser
docker compose up          # web + frontend Astro + worker/beat
```

Sans `DJANGO_USE_POSTGRES=1` : fallback SQLite (`db.sqlite3`).


- Backend : http://localhost:8000
- Frontend Astro : http://localhost:4321
- Console DataStudio : http://localhost:8000/console/
- Connexion staff : http://localhost:8000/accounts/login/
- Back-office HTMX : http://localhost:8000/backoffice/

## Compte superuser

Cree a l'init (etape Superuser) ou via `createsuperuser` - compte **superuser** requis pour `/console/` et `/accounts/login/`.

## Backend

App metier : `apps.core`
Admin custom : `apps.admin_panel` (registry, schema, CRUD, query SELECT, DDL Postgres `/api/admin/db/`)

UI interne staff : templates Django + **HTMX** (`/backoffice/`).

**Structure BDD** : `models.py` + migrations uniquement.


## Frontend (Astro)

L'init **ne demarre pas** Astro : le port 4321 reste ferme tant que `pnpm dev` n'est pas lance.

```powershell
# Option A : deux fenetres automatiques (recommande Windows)
.\scripts\dev-local.ps1

# Option B : manuel (2 terminaux)
cd frontend
pnpm install   # deja fait a l'init si Node/pnpm disponible
pnpm dev
```

Puis ouvrir http://127.0.0.1:4321 (ou http://localhost:4321).

Variables publiques : `PUBLIC_API_URL` (health API) et `PUBLIC_DJANGO_URL` (liens Django).
Console admin : `PUBLIC_DJANGO_URL` + `/console/` (HTMX, pas Astro).
Jamais de secrets dans `PUBLIC_*`.

## Cursor

Voir `.cursor/AGENTS.md` et `.cursor/skills/STACK.md`.