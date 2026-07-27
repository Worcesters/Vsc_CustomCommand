from __future__ import annotations

from typing import TypedDict


class RegistryEntry(TypedDict):
    app_label: str
    model_name: str
    label: str
    permissions: list[str]


# Whitelist des models exposes au CRUD ORM (/api/admin/models/...).
# Le DDL Postgres (/api/admin/db/...) est orthogonal : tables public hors blacklist systeme.
ADMIN_MODEL_REGISTRY: list[RegistryEntry] = [
    {
        "app_label": "auth",
        "model_name": "user",
        "label": "Utilisateurs",
        "permissions": ["list", "create", "edit", "delete", "schema"],
    },
]