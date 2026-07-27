"""Schemas Django Ninja (validation entree/sortie API)."""

from __future__ import annotations

from ninja import Schema


class HealthOut(Schema):
    """Schema de sortie minimal (exemple)."""

    status: str