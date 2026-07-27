"""Tests securite Console HTMX (/admin/) — superuser, CSRF, path table."""

from __future__ import annotations

import pytest
from django.contrib.auth import get_user_model
from django.test import Client


@pytest.mark.django_db
def test_admin_anonymous_redirects_to_login(api_client: Client) -> None:
    response = api_client.get("/admin/")
    assert response.status_code in {302, 301}
    assert "/accounts/login/" in response.url


@pytest.mark.django_db
def test_console_legacy_redirects_to_admin(api_client: Client) -> None:
    response = api_client.get("/console/")
    assert response.status_code in {302, 301}
    assert response.url == "/admin/"


@pytest.mark.django_db
def test_admin_staff_non_superuser_forbidden(api_client: Client, db) -> None:
    User = get_user_model()
    user = User.objects.create_user(
        username="staffer",
        password="pass",
        is_staff=True,
        is_superuser=False,
    )
    api_client.force_login(user)
    response = api_client.get("/admin/")
    assert response.status_code == 403


@pytest.mark.django_db
def test_admin_superuser_ok(api_client: Client, superuser) -> None:
    api_client.force_login(superuser)
    response = api_client.get("/admin/")
    assert response.status_code == 200


@pytest.mark.django_db
def test_admin_table_path_rejects_injection(api_client: Client, superuser) -> None:
    api_client.force_login(superuser)
    response = api_client.get("/admin/tables/1bad;drop/")
    assert response.status_code == 404


@pytest.mark.django_db
def test_admin_drop_table_csrf_required(superuser) -> None:
    client = Client(enforce_csrf_checks=True)
    client.force_login(superuser)
    response = client.post(
        "/admin/ddl/drop-table/",
        data={"name": "demo", "confirm_name": "demo"},
    )
    assert response.status_code == 403


@pytest.mark.django_db
def test_admin_drop_table_confirm_mismatch(api_client: Client, superuser) -> None:
    api_client.force_login(superuser)
    response = api_client.post(
        "/admin/ddl/drop-table/",
        data={"name": "demo_tbl", "confirm_name": "other"},
        HTTP_HX_REQUEST="true",
    )
    assert response.status_code == 200
    body = response.content.lower()
    assert b"confirmation invalide" in body or b"invalide" in body
