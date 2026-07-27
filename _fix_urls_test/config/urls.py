from django.conf import settings
from django.contrib import admin
from django.urls import include, path
from django.views.generic import RedirectView

from config.api import api

urlpatterns = [
    path("api/", api.urls),
    path("accounts/", include("django.contrib.auth.urls")),
    path("admin/", include("apps.admin_panel.urls")),
    path(
        "console/",
        RedirectView.as_view(url="/admin/", permanent=False),
        name="console_legacy_redirect",
    ),
    path("", include("apps.core.urls")),
]

if getattr(settings, "DJANGO_ADMIN_ENABLED", False):
    urlpatterns.insert(0, path("django-admin/", admin.site.urls))
