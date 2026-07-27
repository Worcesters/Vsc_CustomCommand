# Conventions stack (genere par New-DjangoNinjaUvDockerHtmxProject.ps1)

## Python / Django
- Python 3.12+, typing strict, `from __future__ import annotations`
- `uv` exclusif (`uv add`, `uv sync`, `uv run`)
- Service Layer : `services.py` (write), `selectors.py` (read), `views.py` = CBV uniquement
- Pas de logique metier dans models, signals, templates, forms
- Django Ninja pour API consommee par Astro (+ clients externes)

## UI interne HTMX
- Templates Django + HTMX : back-office staff, CRUD internes
- Partials `hx-*`, CSRF, OOB ; logique via **services** partages avec Ninja
- SCSS 7-1 + tokens `:root` ; Flat High-End ; **Tailwind interdit**

## UI produit Astro (frontend/)
- Port **4321** ; `PUBLIC_API_URL` + `PUBLIC_DJANGO_URL` (secrets hors `PUBLIC_*`)
- Zero React — Console admin sur Django `/admin/` (HTMX)
- **Next.js interdit**

## Docker
- `docker compose up --build` (db, redis, web, frontend?, worker, beat)
- Backend : image `uv` (context `.`) ; Frontend : Node 22 + Astro :4321

## Definition of Done (rappel)
- [ ] Services/selectors separes ; CBV documentees (MRO si mixins)
- [ ] Tests Pytest (happy + edge + failure) pour chaque nouveau service
- [ ] `ruff` + `mypy --strict` sans warning sur code touche
- [ ] Mettre a jour `.cursor/app-structure.md` si structure change