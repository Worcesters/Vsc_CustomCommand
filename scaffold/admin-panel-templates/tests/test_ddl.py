"""Tests DDL admin panel (validation + API Postgres)."""

from __future__ import annotations

import json

import pytest
from django.db import connection

from apps.admin_panel.services import (
    AdminDdlError,
    create_table,
    drop_table,
    is_ddl_table_blacklisted,
    validate_column_type,
    validate_sql_identifier,
)


def test_validate_identifier_rejects_injection() -> None:
    with pytest.raises(AdminDdlError, match="invalide"):
        validate_sql_identifier("users; DROP TABLE auth_user")


def test_validate_identifier_accepts_snake() -> None:
    assert validate_sql_identifier("my_table_1") == "my_table_1"


def test_validate_type_rejects_unknown() -> None:
    with pytest.raises(AdminDdlError, match="non autorise"):
        validate_column_type("varchar); DROP TABLE x;--")


def test_validate_type_accepts_varchar_length() -> None:
    assert validate_column_type("varchar(255)") == "varchar(255)"


def test_blacklist_protects_django_and_auth() -> None:
    assert is_ddl_table_blacklisted("django_migrations") is True
    assert is_ddl_table_blacklisted("auth_user") is True
    assert is_ddl_table_blacklisted("celery_taskmeta") is True
    assert is_ddl_table_blacklisted("inventory_item") is False


@pytest.mark.django_db
def test_create_table_refuses_blacklisted_without_db(superuser) -> None:
    with pytest.raises(AdminDdlError, match="blacklist"):
        create_table(
            "auth_user",
            [{"name": "id", "type": "integer", "nullable": False, "primary_key": True}],
            actor=superuser,
        )


@pytest.mark.django_db
def test_create_table_refuses_non_superuser(db) -> None:
    from django.contrib.auth import get_user_model

    User = get_user_model()
    user = User.objects.create_user(username="regular", password="pass")
    with pytest.raises(AdminDdlError, match="superuser"):
        create_table(
            "tmp_demo_table",
            [{"name": "id", "type": "integer", "nullable": False, "primary_key": True}],
            actor=user,
        )


@pytest.mark.django_db
@pytest.mark.skipif(
    connection.vendor != "postgresql",
    reason="DDL integration reserve a PostgreSQL",
)
def test_create_and_drop_table_happy(superuser) -> None:
    created = create_table(
        "adm_ddl_demo",
        [
            {"name": "id", "type": "serial", "nullable": False, "primary_key": True},
            {"name": "label", "type": "varchar(100)", "nullable": True, "primary_key": False},
        ],
        actor=superuser,
    )
    assert created["name"] == "adm_ddl_demo"
    drop_table("adm_ddl_demo", confirm_name="adm_ddl_demo", actor=superuser)


@pytest.mark.django_db
def test_drop_table_requires_confirm_name(superuser) -> None:
    with pytest.raises(AdminDdlError, match="Confirmation invalide"):
        drop_table("adm_ddl_missing", confirm_name="wrong", actor=superuser)


@pytest.mark.django_db
def test_api_db_tables_create_rejects_invalid_name(api_client_superuser) -> None:
    response = api_client_superuser.post(
        "/api/admin/db/tables/",
        data=json.dumps(
            {
                "name": "bad-name!",
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
    assert "invalide" in response.json()["detail"].lower()


@pytest.mark.django_db
def test_api_db_tables_create_rejects_blacklist(api_client_superuser) -> None:
    response = api_client_superuser.post(
        "/api/admin/db/tables/",
        data=json.dumps(
            {
                "name": "django_session",
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
def test_api_db_schema_anonymous_forbidden(api_client) -> None:
    response = api_client.get("/api/admin/db/schema/")
    assert response.status_code == 401