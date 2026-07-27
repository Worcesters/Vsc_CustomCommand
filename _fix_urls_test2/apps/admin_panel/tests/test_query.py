"""Tests execution requetes SQL lecture seule."""

import json

import pytest

from apps.admin_panel.selectors import AdminQueryError, validate_readonly_sql


def test_validate_rejects_empty() -> None:
    with pytest.raises(AdminQueryError, match="vide"):
        validate_readonly_sql("   ")


def test_validate_rejects_delete() -> None:
    with pytest.raises(AdminQueryError, match="lecture seule"):
        validate_readonly_sql("DELETE FROM auth_user")


def test_validate_rejects_multi_statement() -> None:
    with pytest.raises(AdminQueryError, match="Une seule"):
        validate_readonly_sql("SELECT 1; SELECT 2")


def test_validate_rejects_dangerous_function() -> None:
    with pytest.raises(AdminQueryError, match="Fonction SQL interdite"):
        validate_readonly_sql("SELECT pg_sleep(1)")


def test_validate_rejects_for_update() -> None:
    with pytest.raises(AdminQueryError, match="Verrous"):
        validate_readonly_sql("SELECT id FROM auth_user FOR UPDATE")


def test_validate_allows_explain_analyze_select() -> None:
    assert validate_readonly_sql("EXPLAIN ANALYZE SELECT 1").startswith("EXPLAIN")


@pytest.mark.django_db
def test_execute_select_returns_rows(api_client_superuser) -> None:
    response = api_client_superuser.post(
        "/api/admin/query/",
        data=json.dumps({"sql": "SELECT 1 AS num"}),
        content_type="application/json",
    )
    assert response.status_code == 200
    data = response.json()
    assert data["columns"] == ["num"]
    assert data["rows"] == [{"num": 1}]


@pytest.mark.django_db
def test_execute_rejects_insert(api_client_superuser) -> None:
    response = api_client_superuser.post(
        "/api/admin/query/",
        data=json.dumps({"sql": "INSERT INTO auth_user (username) VALUES ('x')"}),
        content_type="application/json",
    )
    assert response.status_code == 400
    assert "lecture seule" in response.json()["detail"]