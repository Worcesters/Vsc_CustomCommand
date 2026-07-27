# fix_urls_test2-frontend (Astro)

UI produit Astro 5 — port **4321**. App Django de reference : `core`.

**Zero React** — landing HTML + SCSS uniquement.

## Scripts

```bash
pnpm install
pnpm dev    # http://0.0.0.0:4321
pnpm build
```

## Env

- `PUBLIC_API_URL` (defaut `http://localhost:8000`) — health API `/api/health/`
- `PUBLIC_DJANGO_URL` (defaut `http://localhost:8000`) — liens HTML vers Django
- Jamais de secrets dans `PUBLIC_*`.

## Console DataStudio (HTMX Django)

- Console : `PUBLIC_DJANGO_URL` + `/console/` (ex. http://localhost:8000/console/)
- Connexion staff : `/accounts/login/`
- Pages Astro `/admin` et `/login` redirigent vers Django (compat legacy)
- API admin : `PUBLIC_API_URL` + `/api/admin/*` (consommee par la Console HTMX)

## Styles

SCSS 7-1 sous `src/styles/` — tokens Flat High-End, BEM. **Pas de Tailwind.**