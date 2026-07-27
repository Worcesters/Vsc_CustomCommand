"""Schemas Django Ninja (validation entree API) — Schema Pydantic, pas ModelSchema."""

from __future__ import annotations

from ninja import Schema


class QueryExecuteIn(Schema):
    """Payload execution requete SQL lecture seule (pas un ModelSchema ORM)."""

    sql: str


class ColumnDefIn(Schema):
    """Definition de colonne pour CREATE TABLE."""

    name: str
    type: str
    nullable: bool = True
    primary_key: bool = False


class CreateTableIn(Schema):
    """Payload creation de table DDL."""

    name: str
    columns: list[ColumnDefIn]


class AddColumnIn(Schema):
    """Payload ajout de colonne."""

    name: str
    type: str
    nullable: bool = True
    default: str | None = None


class ColumnPatchIn(Schema):
    """Payload rename et/ou changement de type de colonne.

    Au moins un des champs ``new_name`` / ``new_type`` doit etre fourni.
    """

    new_name: str | None = None
    new_type: str | None = None