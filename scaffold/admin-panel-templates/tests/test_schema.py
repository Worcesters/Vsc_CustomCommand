"""Tests schema admin panel."""

import pytest

from apps.admin_panel.selectors import export_schema_mermaid, get_model_schema


@pytest.mark.django_db
def test_model_schema_user_fields() -> None:
    schema = get_model_schema("auth", "user")
    assert "relations" in schema
    assert "incoming" in schema
    names = {f["name"] for f in schema["fields"]}
    assert "username" in names
    assert "email" in names


def test_export_mermaid_contains_erdiagram() -> None:
    md = export_schema_mermaid()
    assert "erDiagram" in md