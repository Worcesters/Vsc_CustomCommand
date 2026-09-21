"""Tests registry admin panel."""

from apps.admin_panel.registry import ADMIN_MODEL_REGISTRY
from apps.admin_panel.selectors import list_registry_entries


def test_registry_contains_user() -> None:
    entries = list_registry_entries()
    assert any(
        e["app_label"] == "auth" and e["model_name"] == "user" for e in entries
    )


def test_registry_whitelist_not_empty() -> None:
    assert len(ADMIN_MODEL_REGISTRY) >= 1