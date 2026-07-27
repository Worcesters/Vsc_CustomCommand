"""Tests API admin panel (auth superuser)."""

import json

import pytest
from django.contrib.auth import get_user_model


@pytest.mark.django_db
def test_registry_anonymous_forbidden(api_client) -> None:
    response = api_client.get("/api/admin/registry/")
    assert response.status_code == 401


@pytest.mark.django_db
def test_registry_non_superuser_forbidden(api_client, db) -> None:
    User = get_user_model()
    user = User.objects.create_user(username="user", password="pass")
    # Forge un access JWT hors create_token_pair (reserve aux superusers).
    from datetime import UTC, datetime, timedelta

    import jwt
    from django.conf import settings

    token = jwt.encode(
        {
            "user_id": user.pk,
            "username": user.username,
            "type": "access",
            "exp": datetime.now(tz=UTC) + timedelta(hours=1),
            "iat": datetime.now(tz=UTC),
        },
        settings.SECRET_KEY,
        algorithm="HS256",
    )
    response = api_client.get(
        "/api/admin/registry/",
        HTTP_AUTHORIZATION=f"Bearer {token}",
    )
    assert response.status_code == 401


@pytest.mark.django_db
def test_registry_superuser_ok(api_client_superuser) -> None:
    response = api_client_superuser.get("/api/admin/registry/")
    assert response.status_code == 200
    assert "results" in response.json()


@pytest.mark.django_db
def test_schema_global_superuser_ok(api_client_superuser) -> None:
    response = api_client_superuser.get("/api/admin/schema/")
    assert response.status_code == 200
    assert "nodes" in response.json()


@pytest.mark.django_db
def test_login_rejects_non_superuser(api_client, db) -> None:
    User = get_user_model()
    User.objects.create_user(username="user", password="pass")
    response = api_client.post(
        "/api/auth/login/",
        data=json.dumps({"username": "user", "password": "pass"}),
        content_type="application/json",
    )
    assert response.status_code == 403
    assert response.json()["code"] == "not_superuser"


def test_login_rejects_wrong_password(api_client, superuser) -> None:
    response = api_client.post(
        "/api/auth/login/",
        data=json.dumps({"username": "admin", "password": "wrong-password"}),
        content_type="application/json",
    )
    assert response.status_code == 401
    assert response.json()["code"] == "invalid_credentials"


@pytest.mark.django_db
def test_login_accepts_superuser(api_client, superuser) -> None:
    response = api_client.post(
        "/api/auth/login/",
        data=json.dumps({"username": "admin", "password": "admin-secret"}),
        content_type="application/json",
    )
    assert response.status_code == 200
    data = response.json()
    assert "access" in data
    assert data["user"]["is_superuser"] is True


@pytest.mark.django_db
def test_db_schema_requires_auth(api_client) -> None:
    response = api_client.get("/api/admin/db/schema/")
    assert response.status_code == 401


@pytest.mark.django_db
def test_db_create_table_rejects_blacklist(api_client_superuser) -> None:
    response = api_client_superuser.post(
        "/api/admin/db/tables/",
        data=json.dumps(
            {
                "name": "auth_user",
                "columns": [
                    {
                        "name": "id",
                        "type": "integer",
                        "nullable": False,
                        "primary_key": True,
                    }
                ],
            }
        ),
        content_type="application/json",
    )
    assert response.status_code == 400
    assert "blacklist" in response.json()["detail"].lower()


@pytest.mark.django_db
def test_db_create_table_rejects_invalid_identifier(api_client_superuser) -> None:
    response = api_client_superuser.post(
        "/api/admin/db/tables/",
        data=json.dumps(
            {
                "name": "1bad",
                "columns": [
                    {
                        "name": "id",
                        "type": "integer",
                        "nullable": False,
                        "primary_key": True,
                    }
                ],
            }
        ),
        content_type="application/json",
    )
    assert response.status_code == 400


@pytest.mark.django_db
def test_db_drop_table_requires_confirm_name(api_client_superuser) -> None:
    response = api_client_superuser.delete("/api/admin/db/tables/demo_tbl/")
    # Ninja : query param requis -> 422 ; ou 400 si confirm invalide vide.
    assert response.status_code in {400, 422}


@pytest.mark.django_db
def test_db_drop_table_reject_confirm_mismatch(api_client_superuser) -> None:
    response = api_client_superuser.delete(
        "/api/admin/db/tables/demo_tbl/?confirm_name=wrong"
    )
    assert response.status_code == 400
    assert "confirm" in response.json()["detail"].lower() or "invalide" in response.json()[
        "detail"
    ].lower()