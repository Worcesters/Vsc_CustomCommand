from django.urls import path

from . import views

app_name = "core"

urlpatterns = [
    path("", views.HomeView.as_view(), name="home"),
    path("backoffice/", views.BackofficeListView.as_view(), name="backoffice_list"),
    path(
        "backoffice/ping/",
        views.BackofficePingView.as_view(),
        name="backoffice_ping",
    ),
    path(
        "backoffice/<int:pk>/",
        views.BackofficeDetailView.as_view(),
        name="backoffice_detail",
    ),
]