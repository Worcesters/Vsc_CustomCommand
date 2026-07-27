"""API racine Django Ninja."""

from __future__ import annotations

from ninja import NinjaAPI

api = NinjaAPI(
    title="API",
    version="1.0.0",
    urls_namespace="api",
)


@api.get("/health/", tags=["system"])
def health_check(request) -> dict[str, str]:
    """GET /api/health/ - sonde disponibilite."""
    return {"status": "ok"}


def register_api_routers() -> None:
    """Enregistre les routers optionnels (admin, celery, apps metier)."""
    try:
        from apps.admin_panel.api import admin_router, auth_router

        api.add_router("/auth/", auth_router)
        api.add_router("/admin/", admin_router)
    except ImportError:
        pass

    try:
        from apps.core.api import core_router

        api.add_router("/core/", core_router)
    except ImportError:
        pass


register_api_routers()