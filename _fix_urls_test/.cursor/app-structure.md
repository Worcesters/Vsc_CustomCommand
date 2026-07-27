# Structure applicative

## Racine monorepo
| Chemin | Role |
|--------|------|
| `config/` | Settings Django (dev/qua/prod), urls, wsgi/asgi, celery |
| `apps/` | Apps metier (Service Layer strict) |
| `templates/` | UI interne HTMX (back-office, partials) |
| `static/scss/` | SCSS 7-1 (HTMX + tokens) |
| `frontend/` | Astro UI produit (port 4321, zero React) |
| `apps/admin_panel/` | Registry whitelist + API Django Ninja `/api/admin/` |
| `tests/` | Pytest |
| `docker-compose.yml` / `docker-compose.prod.yml` | Dev local / prod |

## Apps Django
| App | Role |
|-----|------|
| `apps.core` | App metier (modeles custom ; User = `auth.User`) |

## Frontiere UI
- Surface **publique / produit** → Astro (`frontend/`).
- Surface **staff / admin / CRUD interne** → HTMX (templates Django).
- Ne pas melanger HTMX dans `frontend/` ni islands Astro dans les templates Django.

## Front Astro (UI produit)
- UI produit dans `frontend/` : pages Astro pures (HTML + SCSS, zero React).
- Port dev **4321**. `PUBLIC_API_URL` (API) et `PUBLIC_DJANGO_URL` (liens Django).
- Admin DataStudio = HTMX Django `/admin/` (pas d'islands Astro).
- **Next.js interdit.** Pas de Tailwind / utility-first.
- Pas de logique metier cote client ; API = Django Ninja.
## Admin custom (admin_panel)
- API `/api/admin/` + auth JWT `/api/auth/` pour Console HTMX et outils.
- Registry whitelist, schema, CRUD, requetes SQL lecture seule.