from django.apps import AppConfig


class AdminPanelConfig(AppConfig):
    """Panneau admin custom (API Django Ninja + registry whitelist)."""

    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.admin_panel"
    verbose_name = "Admin Panel"