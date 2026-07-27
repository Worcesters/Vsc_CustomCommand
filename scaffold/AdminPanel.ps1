#Requires -Version 5.1
<#
.SYNOPSIS
  Genere apps/admin_panel (API /api/admin/ + JWT + registry + DDL Postgres).

.NOTES
  Porte quasi 1:1 depuis New-DjangoNinjaUvDockerHtmxProject.ps1 (fonction New-AdminPanelBackend).
  Contrat API : /api/auth/*, /api/admin/* (registry/CRUD/query) + /api/admin/db/* (introspection + DDL).
  UI admin cible = HTMX Django (services partages) ; API Ninja pour outils externes.
  DDL : PostgreSQL only, superuser JWT, blacklist systeme (django_*, auth_*, …).
  Depend de Write-TextFile (Common.ps1).
  Layout monorepo : Django a la RACINE du projet genere (apps/, config/, manage.py) - pas de sous-dossier backend/.
#>
function New-AdminPanelBackend {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$AppName
    )

    $panelDir = Join-Path $Root "apps\admin_panel"
    New-Item -ItemType Directory -Path (Join-Path $panelDir "tests") -Force | Out-Null

    Write-TextFile -Path (Join-Path $panelDir "apps.py") -Content @'
from django.apps import AppConfig


class AdminPanelConfig(AppConfig):
    """Panneau admin custom (API Django Ninja + registry whitelist)."""

    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.admin_panel"
    verbose_name = "Admin Panel"
'@

    Write-TextFile -Path (Join-Path $panelDir "registry.py") -Content @"
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
"@

    Write-TextFile -Path (Join-Path $panelDir "selectors.py") -Content @'
from __future__ import annotations

import re
from decimal import Decimal

from django.apps import apps
from django.db import models

from .registry import ADMIN_MODEL_REGISTRY, RegistryEntry


def list_registry_entries() -> list[RegistryEntry]:
    """Retourne la whitelist des models admin."""
    return list(ADMIN_MODEL_REGISTRY)


def _schema_field_default(field: models.Field) -> object | None:
    """Valeur par defaut serialisable pour le schema API."""
    if not field.has_default():
        return None
    default_val = field.get_default()
    if callable(default_val):
        return None
    if hasattr(default_val, "isoformat"):
        return default_val.isoformat()
    return default_val


def _schema_field_is_auto_increment(field: models.Field) -> bool:
    """Indique si le champ PK est auto-genere (serial Django)."""
    return field.__class__.__name__ in {"AutoField", "BigAutoField"}


def _schema_required_on_create(model: type[models.Model], field: models.Field) -> bool:
    """Champ requis a la creation (hors PK auto, auto_now, M2M)."""
    if not getattr(field, "concrete", True):
        return False
    if not getattr(field, "editable", True):
        return False
    if getattr(field, "primary_key", False):
        return False
    if _schema_field_is_auto_increment(field):
        return False
    if getattr(field, "auto_now_add", False) or getattr(field, "auto_now", False):
        return False
    if isinstance(field, models.ManyToManyField):
        return False
    if field.name == "password" and model._meta.label_lower == "auth.user":
        return True
    return not getattr(field, "blank", False)


def get_model_schema(app_label: str, model_name: str) -> dict[str, object]:
    """Schema d'un model (champs, types, contraintes, relations)."""
    model = apps.get_model(app_label, model_name)
    fields: list[dict[str, object]] = []
    for field in model._meta.get_fields():
        if getattr(field, "auto_created", False) and not field.concrete:
            continue
        is_auto_pk = _schema_field_is_auto_increment(field)
        info: dict[str, object] = {
            "name": field.name,
            "type": field.__class__.__name__,
            "nullable": getattr(field, "null", False),
            "unique": getattr(field, "unique", False),
            "editable": getattr(field, "editable", True),
            "blank": getattr(field, "blank", False),
            "primary_key": getattr(field, "primary_key", False) or is_auto_pk,
            "auto_increment": is_auto_pk,
            "required_on_create": _schema_required_on_create(model, field),
        }
        if field.has_default():
            default_val = _schema_field_default(field)
            if default_val is not None:
                info["default"] = default_val
        if isinstance(field, (models.ForeignKey, models.OneToOneField)):
            info["relation"] = "FK"
            info["related_model"] = field.related_model._meta.label_lower
        elif isinstance(field, models.ManyToManyField):
            info["relation"] = "M2M"
            info["related_model"] = field.related_model._meta.label_lower
        fields.append(info)
    relations: list[dict[str, object]] = []
    for field in fields:
        related = field.get("related_model")
        if not related or "relation" not in field:
            continue
        rel_app, _, rel_model = str(related).partition(".")
        relations.append(
            {
                "field": field["name"],
                "type": field["relation"],
                "app_label": rel_app,
                "model_name": rel_model,
                "target_id": str(related),
            }
        )
    return {
        "app_label": app_label,
        "model_name": model_name,
        "table": model._meta.db_table,
        "fields": fields,
        "relations": relations,
        "incoming": _list_incoming_relations(app_label, model_name),
    }


def _list_incoming_relations(app_label: str, model_name: str) -> list[dict[str, object]]:
    """Relations entrantes (autres tables pointant vers ce model)."""
    target = f"{app_label}.{model_name}"
    incoming: list[dict[str, object]] = []
    for entry in ADMIN_MODEL_REGISTRY:
        peer_model = apps.get_model(entry["app_label"], entry["model_name"])
        for field in peer_model._meta.get_fields():
            if getattr(field, "auto_created", False) and not field.concrete:
                continue
            if not isinstance(
                field, (models.ForeignKey, models.OneToOneField, models.ManyToManyField)
            ):
                continue
            if field.related_model._meta.label_lower != target:
                continue
            rel_type = "M2M" if isinstance(field, models.ManyToManyField) else "FK"
            incoming.append(
                {
                    "field": field.name,
                    "type": rel_type,
                    "from_app_label": entry["app_label"],
                    "from_model_name": entry["model_name"],
                    "from_id": f"{entry['app_label']}.{entry['model_name']}",
                }
            )
    return incoming


def get_global_schema() -> dict[str, object]:
    """Schema global + liaisons pour diagramme."""
    nodes: list[dict[str, str]] = []
    edges: list[dict[str, str]] = []
    for entry in ADMIN_MODEL_REGISTRY:
        schema = get_model_schema(entry["app_label"], entry["model_name"])
        node_id = f"{entry['app_label']}.{entry['model_name']}"
        nodes.append(
            {
                "id": node_id,
                "label": entry["label"],
                "app_label": entry["app_label"],
                "model_name": entry["model_name"],
            }
        )
        for field in schema["fields"]:
            if "relation" in field and "related_model" in field:
                edges.append(
                    {
                        "from": node_id,
                        "to": str(field["related_model"]),
                        "type": str(field["relation"]),
                        "field": str(field["name"]),
                    }
                )
    return {"nodes": nodes, "edges": edges}


_MERMAID_UNSAFE = re.compile(r"[^A-Za-z0-9_]")
_MERMAID_TYPE_MAP: dict[str, str] = {
    "character varying": "varchar",
    "varchar": "varchar",
    "character": "char",
    "integer": "int",
    "bigint": "bigint",
    "smallint": "smallint",
    "boolean": "bool",
    "text": "text",
    "timestamp with time zone": "timestamptz",
    "timestamp without time zone": "timestamp",
    "numeric": "numeric",
    "double precision": "float",
    "real": "float",
    "uuid": "uuid",
    "jsonb": "jsonb",
    "json": "json",
    "date": "date",
    "bytea": "bytea",
    "charfield": "varchar",
    "textfield": "text",
    "integerfield": "int",
    "bigintegerfield": "bigint",
    "booleanfield": "bool",
    "datetimefield": "timestamp",
    "datefield": "date",
    "uuidfield": "uuid",
    "jsonfield": "jsonb",
    "emailfield": "varchar",
    "slugfield": "varchar",
    "urlfield": "varchar",
    "decimalfield": "numeric",
    "floatfield": "float",
    "autofield": "int",
    "bigautofield": "bigint",
}


def _mermaid_sanitize_ident(value: str, *, max_len: int = 48) -> str:
    """Identifiant Mermaid erDiagram (A-Za-z0-9_ uniquement)."""
    cleaned = _MERMAID_UNSAFE.sub("_", str(value).strip())
    cleaned = re.sub(r"_+", "_", cleaned).strip("_")
    if not cleaned:
        cleaned = "x"
    if cleaned[0].isdigit():
        cleaned = f"t_{cleaned}"
    return cleaned[:max_len]


def _mermaid_short_type(raw: str) -> str:
    """Type court compatible Mermaid (sans points / espaces / parentheses)."""
    key = str(raw).strip()
    lower = key.lower()
    if lower in _MERMAID_TYPE_MAP:
        return _MERMAID_TYPE_MAP[lower]
    base = re.split(r"[\(\s]", lower, maxsplit=1)[0]
    if base in _MERMAID_TYPE_MAP:
        return _MERMAID_TYPE_MAP[base]
    return _mermaid_sanitize_ident(base or "text", max_len=24)


def _export_schema_mermaid_from_postgres() -> str:
    """Corps erDiagram base sur catalogue Postgres (toutes tables public)."""
    tables = list_database_tables()
    fks = list_foreign_keys()
    lines = ["erDiagram"]
    for table in tables:
        entity = _mermaid_sanitize_ident(str(table["name"])).upper()
        lines.append(f"    {entity} {{")
        for col in table.get("columns") or []:
            assert isinstance(col, dict)
            ctype = _mermaid_short_type(str(col.get("data_type", "text")))
            cname = _mermaid_sanitize_ident(str(col["name"]))
            lines.append(f"        {ctype} {cname}")
        lines.append("    }")
    for fk in fks:
        src = _mermaid_sanitize_ident(fk["from_table"]).upper()
        dst = _mermaid_sanitize_ident(fk["to_table"]).upper()
        label = _mermaid_sanitize_ident(fk["from_column"])
        lines.append(f"    {src} }}o--|| {dst} : {label}")
    return "\n".join(lines)


def _export_schema_mermaid_from_registry() -> str:
    """Corps erDiagram fallback (registry ORM uniquement)."""
    lines = ["erDiagram"]
    for entry in ADMIN_MODEL_REGISTRY:
        schema = get_model_schema(entry["app_label"], entry["model_name"])
        entity = _mermaid_sanitize_ident(
            f"{entry['app_label']}_{entry['model_name']}"
        ).upper()
        lines.append(f"    {entity} {{")
        for field in schema["fields"]:
            if "relation" in field:
                continue
            ctype = _mermaid_short_type(str(field["type"]))
            cname = _mermaid_sanitize_ident(str(field["name"]))
            lines.append(f"        {ctype} {cname}")
        lines.append("    }")
    for entry in ADMIN_MODEL_REGISTRY:
        schema = get_model_schema(entry["app_label"], entry["model_name"])
        src = _mermaid_sanitize_ident(
            f"{entry['app_label']}_{entry['model_name']}"
        ).upper()
        for field in schema["fields"]:
            if field.get("relation") == "FK" and field.get("related_model"):
                dst = _mermaid_sanitize_ident(
                    str(field["related_model"]).replace(".", "_")
                ).upper()
                label = _mermaid_sanitize_ident(str(field["name"]))
                lines.append(f"    {src} }}o--|| {dst} : {label}")
    return "\n".join(lines)


def export_schema_mermaid_body(*, for_render: bool = True) -> str:
    """Corps Mermaid erDiagram sans fences (pour mermaid.render).

    Prefere le catalogue Postgres (toutes tables) ; fallback registry.
    ``for_render`` reserve pour API future (toujours True aujourd'hui).
    """
    _ = for_render
    try:
        return _export_schema_mermaid_from_postgres()
    except AdminIntrospectionError:
        return _export_schema_mermaid_from_registry()


def export_schema_mermaid() -> str:
    """Export Mermaid ER markdown (avec fences pour fichier .md)."""
    body = export_schema_mermaid_body(for_render=False)
    return f"```mermaid\n{body}\n```"


class AdminQueryError(ValueError):
    """Erreur validation ou execution d'une requete SQL admin."""


_MAX_QUERY_LENGTH = 10_000
_MAX_QUERY_ROWS = 500
_QUERY_TIMEOUT_MS = 5_000

_FORBIDDEN_SQL = re.compile(
    r"\b("
    r"INSERT|UPDATE|DELETE|DROP|ALTER|TRUNCATE|CREATE|GRANT|REVOKE|COPY|"
    r"EXECUTE|CALL|DO|MERGE|REPLACE|UPSERT|VACUUM|REINDEX|CLUSTER|"
    r"REFRESH|COMMENT|LOCK|UNLOCK|SET|SHOW|LOAD|UNLISTEN|LISTEN|NOTIFY|"
    r"PREPARE|DEALLOCATE|DISCARD|RESET|REASSIGN|SECURITY|OWNER|INTO"
    r")\b",
    re.IGNORECASE,
)

# Fonctions / extensions capables d'effets de bord hors SELECT pur.
_DANGEROUS_SQL_FUNCS = re.compile(
    r"\b("
    r"pg_sleep|pg_terminate_backend|pg_cancel_backend|"
    r"pg_read_file|pg_write_file|pg_ls_dir|pg_stat_file|"
    r"pg_reload_conf|pg_rotate_logfile|pg_create_restore_point|"
    r"lo_import|lo_export|lo_create|lo_unlink|"
    r"dblink|dblink_exec|dblink_connect|dblink_connect_u|"
    r"set_config|"
    r"pg_advisory_lock|pg_advisory_xact_lock|"
    r"pg_try_advisory_lock|pg_try_advisory_xact_lock"
    r")\s*\(",
    re.IGNORECASE,
)

_ROW_LOCK_SQL = re.compile(
    r"\bFOR\s+(UPDATE|NO\s+KEY\s+UPDATE|SHARE|KEY\s+SHARE)\b",
    re.IGNORECASE,
)


def _strip_sql_comments(sql: str) -> str:
    """Retire les commentaires SQL (-- et /* */)."""
    without_block = re.sub(r"/\*.*?\*/", " ", sql, flags=re.DOTALL)
    return re.sub(r"--[^\n]*", " ", without_block)


def validate_readonly_sql(sql: str) -> str:
    """Valide qu'une requete est en lecture seule (SELECT / WITH / EXPLAIN).

    Refuse les mots-cles mutateurs, les verrous ``FOR UPDATE``, et les
    fonctions Postgres a effet de bord (fichiers, dblink, terminate, …).
    ``EXPLAIN ANALYZE`` reste autorise (mot ``ANALYZE`` hors liste mutatrice).
    """
    raw = sql.strip()
    if not raw:
        raise AdminQueryError("Requete vide.")
    if len(raw) > _MAX_QUERY_LENGTH:
        raise AdminQueryError(f"Requete trop longue (max {_MAX_QUERY_LENGTH} caracteres).")
    cleaned = raw.rstrip(";").strip()
    if ";" in cleaned:
        raise AdminQueryError("Une seule requete SQL a la fois.")
    normalized = _strip_sql_comments(cleaned)
    if _FORBIDDEN_SQL.search(normalized):
        raise AdminQueryError("Seules les requetes SELECT en lecture seule sont autorisees.")
    if _DANGEROUS_SQL_FUNCS.search(normalized):
        raise AdminQueryError("Fonction SQL interdite en mode lecture seule.")
    if _ROW_LOCK_SQL.search(normalized):
        raise AdminQueryError("Verrous FOR UPDATE / SHARE interdits en lecture seule.")
    tokens = normalized.split()
    if not tokens:
        raise AdminQueryError("Requete vide.")
    first = tokens[0].upper()
    if first not in {"SELECT", "WITH", "EXPLAIN"}:
        raise AdminQueryError("La requete doit commencer par SELECT, WITH ou EXPLAIN.")
    return cleaned


def _ensure_row_limit(sql: str, max_rows: int) -> str:
    """Ajoute une limite de lignes si absente (sauf EXPLAIN)."""
    upper = sql.upper().lstrip()
    if upper.startswith("EXPLAIN"):
        return sql
    if re.search(r"\bLIMIT\b", upper):
        return sql
    return f"SELECT * FROM ({sql}) AS _dsq LIMIT {max_rows}"


def _serialize_query_cell(value: object) -> str | int | float | bool | None:
    """Convertit une cellule SQL en type JSON serialisable."""
    if value is None:
        return None
    if isinstance(value, bool):
        return value
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return value
    if isinstance(value, Decimal):
        return float(value)
    if hasattr(value, "isoformat"):
        return value.isoformat()  # type: ignore[union-attr]
    return str(value)


def execute_readonly_query(sql: str) -> dict[str, object]:
    """Execute une requete SELECT lecture seule et retourne colonnes + lignes."""
    import time

    from django.db import connection, transaction

    validated = validate_readonly_sql(sql)
    bounded = _ensure_row_limit(validated, _MAX_QUERY_ROWS)
    started = time.perf_counter()

    # SET LOCAL n'a d'effet qu'a l'interieur d'une transaction (sinon timeout ignore).
    with transaction.atomic():
        with connection.cursor() as cursor:
            cursor.execute(
                "SET LOCAL statement_timeout = %s",
                [str(_QUERY_TIMEOUT_MS)],
            )
            try:
                cursor.execute(bounded)
            except Exception as exc:
                raise AdminQueryError(f"Erreur SQL : {exc}") from exc

            if cursor.description is None:
                elapsed_ms = int((time.perf_counter() - started) * 1000)
                return {
                    "columns": [],
                    "rows": [],
                    "row_count": 0,
                    "truncated": False,
                    "elapsed_ms": elapsed_ms,
                }

            columns = [col[0] for col in cursor.description]
            raw_rows = cursor.fetchmany(_MAX_QUERY_ROWS + 1)
            truncated = len(raw_rows) > _MAX_QUERY_ROWS
            if truncated:
                raw_rows = raw_rows[:_MAX_QUERY_ROWS]

            rows: list[dict[str, object]] = []
            for raw in raw_rows:
                row: dict[str, object] = {}
                for idx, col_name in enumerate(columns):
                    row[col_name] = _serialize_query_cell(raw[idx])
                rows.append(row)

            elapsed_ms = int((time.perf_counter() - started) * 1000)
            return {
                "columns": columns,
                "rows": rows,
                "row_count": len(rows),
                "truncated": truncated,
                "elapsed_ms": elapsed_ms,
            }


class AdminIntrospectionError(ValueError):
    """Erreur d''introspection schema Postgres (vendor ou acces)."""


def _ensure_postgresql_vendor() -> None:
    """Exige un backend PostgreSQL pour l''introspection catalogue."""
    from django.db import connection

    if connection.vendor != "postgresql":
        raise AdminIntrospectionError(
            "L''introspection catalogue est reservee a PostgreSQL."
        )


def _quote_ident_safe(name: str) -> str:
    """Quote un identifiant deja valide (lettres/chiffres/underscore)."""
    if not re.match(r"^[a-zA-Z_][a-zA-Z0-9_]*$", name):
        raise AdminIntrospectionError(f"Identifiant invalide : {name}")
    return f'"{name}"'


def list_foreign_keys() -> list[dict[str, str]]:
    """Liste les FK du schema public (from/to table/column).

    Returns:
        Liste de dicts ``from_table``, ``from_column``, ``to_table``, ``to_column``.
    """
    from django.db import connection

    _ensure_postgresql_vendor()
    sql = """
        SELECT
            tc.table_name AS from_table,
            kcu.column_name AS from_column,
            ccu.table_name AS to_table,
            ccu.column_name AS to_column
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name
         AND tc.table_schema = kcu.table_schema
        JOIN information_schema.constraint_column_usage ccu
          ON ccu.constraint_name = tc.constraint_name
         AND ccu.table_schema = tc.table_schema
        WHERE tc.constraint_type = 'FOREIGN KEY'
          AND tc.table_schema = 'public'
        ORDER BY tc.table_name, kcu.ordinal_position
    """
    with connection.cursor() as cursor:
        cursor.execute(sql)
        rows = cursor.fetchall()
    return [
        {
            "from_table": r[0],
            "from_column": r[1],
            "to_table": r[2],
            "to_column": r[3],
        }
        for r in rows
    ]


def list_database_tables() -> list[dict[str, object]]:
    """Liste les tables BASE TABLE du schema public avec colonnes, PK et row_count.

    Returns:
        Liste de tables (name, columns, primary_keys, row_count) style SchemaOverview.
    """
    from django.db import connection

    _ensure_postgresql_vendor()

    with connection.cursor() as cursor:
        cursor.execute(
            """
            SELECT table_name
            FROM information_schema.tables
            WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
            ORDER BY table_name
            """
        )
        table_names = [r[0] for r in cursor.fetchall()]

        cursor.execute(
            """
            SELECT tc.table_name, kcu.column_name
            FROM information_schema.table_constraints tc
            JOIN information_schema.key_column_usage kcu
              ON tc.constraint_name = kcu.constraint_name
             AND tc.table_schema = kcu.table_schema
            WHERE tc.constraint_type = 'PRIMARY KEY'
              AND tc.table_schema = 'public'
            ORDER BY tc.table_name, kcu.ordinal_position
            """
        )
        pk_map: dict[str, list[str]] = {}
        for table_name, column_name in cursor.fetchall():
            pk_map.setdefault(table_name, []).append(column_name)

        cursor.execute(
            """
            SELECT table_name, column_name, data_type, is_nullable, column_default
            FROM information_schema.columns
            WHERE table_schema = 'public'
            ORDER BY table_name, ordinal_position
            """
        )
        cols_by_table: dict[str, list[dict[str, object]]] = {}
        for table_name, column_name, data_type, is_nullable, column_default in cursor.fetchall():
            pks = pk_map.get(table_name, [])
            cols_by_table.setdefault(table_name, []).append(
                {
                    "name": column_name,
                    "data_type": data_type,
                    "nullable": is_nullable == "YES",
                    "default": column_default,
                    "primary_key": column_name in pks,
                }
            )

    tables: list[dict[str, object]] = []
    with connection.cursor() as cursor:
        for name in table_names:
            quoted = _quote_ident_safe(name)
            cursor.execute(f"SELECT COUNT(*) FROM {quoted}")  # noqa: S608 - ident valide
            row_count = int(cursor.fetchone()[0])
            tables.append(
                {
                    "name": name,
                    "columns": cols_by_table.get(name, []),
                    "primary_keys": pk_map.get(name, []),
                    "row_count": row_count,
                }
            )
    return tables


def get_database_schema_overview() -> dict[str, object]:
    """Vue d''ensemble schema public (tables + FK) pour UI type DBeaver / SchemaOverview.

    Returns:
        Dict ``tables`` + ``foreign_keys`` consomable HTMX ou API outils.
    """
    return {
        "tables": list_database_tables(),
        "foreign_keys": list_foreign_keys(),
    }


def get_table_overview(table_name: str) -> dict[str, object]:
    """Detail d''une table public (colonnes, PK, row_count, FK incidentes).

    Args:
        table_name: Nom de table dans le schema public.

    Returns:
        Dict table + ``foreign_keys`` (sortantes et entrantes).

    Raises:
        AdminIntrospectionError: Table introuvable ou vendor non Postgres.
    """
    if not re.match(r"^[a-zA-Z_][a-zA-Z0-9_]*$", table_name):
        raise AdminIntrospectionError(f"Identifiant de table invalide : {table_name}")
    overview = get_database_schema_overview()
    tables = overview["tables"]
    assert isinstance(tables, list)
    match = next((t for t in tables if t["name"] == table_name), None)
    if match is None:
        raise AdminIntrospectionError(f"Table introuvable : {table_name}")
    fks = overview["foreign_keys"]
    assert isinstance(fks, list)
    related = [
        fk
        for fk in fks
        if fk["from_table"] == table_name or fk["to_table"] == table_name
    ]
    return {**match, "foreign_keys": related}


def get_console_welcome_stats() -> list[dict[str, str]]:
    """Stats Welcome Console (tables, lignes, relations).

    Returns:
        Liste de dicts ``label``, ``value``, ``hint`` pour la hero Welcome.
    """
    try:
        overview = get_database_schema_overview()
    except AdminIntrospectionError:
        return [
            {"label": "Tables", "value": "—", "hint": "PostgreSQL requis"},
            {"label": "Lignes", "value": "—", "hint": "Indisponible"},
            {"label": "Relations", "value": "—", "hint": "Indisponible"},
        ]
    tables = overview["tables"]
    fks = overview["foreign_keys"]
    assert isinstance(tables, list)
    assert isinstance(fks, list)
    total_rows = sum(int(t.get("row_count", 0)) for t in tables)  # type: ignore[union-attr]
    return [
        {
            "label": "Tables",
            "value": str(len(tables)),
            "hint": "Schema public",
        },
        {
            "label": "Lignes",
            "value": str(total_rows),
            "hint": "Toutes tables confondues",
        },
        {
            "label": "Relations",
            "value": str(len(fks)),
            "hint": "Cles etrangeres",
        },
    ]
'@

    Write-TextFile -Path (Join-Path $panelDir "services.py") -Content @'
from __future__ import annotations

import re
from collections.abc import Sequence
from decimal import Decimal, InvalidOperation
from typing import Any

from django.apps import apps as django_apps
from django.contrib.auth.base_user import AbstractBaseUser
from django.core.exceptions import ValidationError
from django.db import IntegrityError, connection, models, transaction
from django.utils.dateparse import parse_date, parse_datetime

from apps.admin_panel.registry import ADMIN_MODEL_REGISTRY


class AdminModelNotAllowedError(LookupError):
    """Model hors whitelist registry admin."""


class AdminModelValidationError(ValueError):
    """Erreur validation admin avec detail par champ."""

    def __init__(self, detail: str, fields: dict[str, str] | None = None) -> None:
        self.detail = detail
        self.fields = fields or {}
        super().__init__(detail)


def _field_validation_error(field_name: str, message: str) -> AdminModelValidationError:
    return AdminModelValidationError(message, {field_name: message})


def _validation_error_from_exception(exc: Exception) -> AdminModelValidationError:
    """Convertit ValidationError / IntegrityError en erreur API structuree."""
    if isinstance(exc, ValidationError):
        if hasattr(exc, "error_dict"):
            fields = {
                str(key): " ".join(str(item) for item in messages)
                for key, messages in exc.error_dict.items()
            }
            return AdminModelValidationError("Validation impossible.", fields)
        return AdminModelValidationError(str(exc))
    if isinstance(exc, IntegrityError):
        text = str(exc)
        fields: dict[str, str] = {}
        if "auth_user_username_key" in text:
            fields["username"] = "Ce nom d'utilisateur existe deja."
        elif "username" in text.lower() and "unique" in text.lower():
            fields["username"] = "Ce nom d'utilisateur existe deja."
        if "auth_user_email_key" in text:
            fields["email"] = "Cette adresse e-mail existe deja."
        detail = "Contrainte d'unicite en base de donnees."
        if fields:
            return AdminModelValidationError(detail, fields)
        return AdminModelValidationError(detail)
    return AdminModelValidationError(str(exc))


def _resolve_model(app_label: str, model_name: str) -> type[models.Model]:
    """Retourne le model Django si present dans le registry admin."""
    allowed = any(
        e["app_label"] == app_label and e["model_name"] == model_name
        for e in ADMIN_MODEL_REGISTRY
    )
    if not allowed:
        raise AdminModelNotAllowedError(f"{app_label}.{model_name}")
    return django_apps.get_model(app_label, model_name)


def _editable_fields(model: type[models.Model]) -> set[str]:
    return {f.name for f in model._meta.concrete_fields if f.editable}


def _serialize_value(value: object) -> object:
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return value


def _is_auth_user_model(model: type[models.Model]) -> bool:
    return model._meta.label_lower == "auth.user"


def serialize_instance(model: type[models.Model], instance: models.Model) -> dict[str, Any]:
    """Serialise une instance ORM en dict JSON-friendly."""
    row: dict[str, Any] = {}
    for field in model._meta.concrete_fields:
        if field.name == "password":
            if _is_auth_user_model(model):
                row["password_set"] = instance.has_usable_password()
            continue
        row[field.name] = _serialize_value(getattr(instance, field.attname))
    return row


def _coerce_field_value(field: models.Field, raw: object) -> object:
    """Convertit une valeur API vers le type ORM."""
    if raw is None or raw == "":
        if field.null or field.blank:
            return None
        raise _field_validation_error(field.name, "Ce champ est obligatoire.")
    if isinstance(field, models.BooleanField):
        if isinstance(raw, bool):
            return raw
        return str(raw).lower() in ("1", "true", "yes", "on")
    if isinstance(field, (models.IntegerField, models.BigIntegerField, models.SmallIntegerField)):
        return int(raw)
    if isinstance(field, models.DecimalField):
        try:
            return Decimal(str(raw))
        except InvalidOperation as exc:
            raise _field_validation_error(
                field.name, "Valeur decimale invalide."
            ) from exc
    if isinstance(field, models.DateTimeField):
        parsed = parse_datetime(str(raw))
        if parsed is None:
            raise _field_validation_error(field.name, "Date ou heure invalide.")
        return parsed
    if isinstance(field, models.DateField):
        parsed = parse_date(str(raw))
        if parsed is None:
            raise _field_validation_error(field.name, "Date invalide.")
        return parsed
    return raw


def _clean_payload(
    model: type[models.Model],
    payload: dict[str, Any],
    *,
    exclude_pk: bool = False,
) -> dict[str, Any]:
    """Filtre et coerce le payload ; rejette toute cle non editable."""
    allowed = _editable_fields(model)
    cleaned: dict[str, Any] = {}
    pk_name = model._meta.pk.name
    for key, value in payload.items():
        if key == "password_set":
            raise AdminModelValidationError(
                "Le champ password_set est en lecture seule "
                "(indique si un mot de passe est defini)."
            )
        if exclude_pk and key == pk_name:
            continue
        if key not in allowed:
            raise AdminModelValidationError(
                f"Le champ '{key}' n'est pas editable."
            )
        field = model._meta.get_field(key)
        cleaned[key] = _coerce_field_value(field, value)
    return cleaned


def list_model_rows(app_label: str, model_name: str, *, limit: int = 500) -> dict[str, Any]:
    """Liste les lignes d'un model (lecture ORM pour grille admin)."""
    model = _resolve_model(app_label, model_name)
    rows = [
        serialize_instance(model, obj) for obj in model.objects.all()[:limit]
    ]
    return {"results": rows, "count": model.objects.count(), "pk_field": model._meta.pk.name}


def _create_auth_user(model: type[models.Model], payload: dict[str, Any]) -> dict[str, Any]:
    """Cree un utilisateur Django avec mot de passe hashe."""
    data = _clean_payload(model, payload, exclude_pk=True)
    password = data.pop("password", None)
    if not password:
        raise _field_validation_error("password", "Le mot de passe est obligatoire a la creation.")
    username = data.get("username")
    if not username:
        raise _field_validation_error("username", "Le nom d'utilisateur est obligatoire.")
    m2m_skip = {"groups", "user_permissions"}
    extra = {
        key: value
        for key, value in data.items()
        if key not in {"username", "email", "password"} and key not in m2m_skip
    }
    try:
        user = model.objects.create_user(
            username=str(username),
            email=str(data.get("email", "")),
            password=str(password),
            **extra,
        )
        user.full_clean()
    except (ValidationError, IntegrityError) as exc:
        raise _validation_error_from_exception(exc) from exc
    return serialize_instance(model, user)


def _update_auth_user(
    model: type[models.Model],
    instance: models.Model,
    payload: dict[str, Any],
) -> dict[str, Any]:
    """Met a jour un utilisateur Django (hash du mot de passe si fourni)."""
    raw = dict(payload)
    password = raw.pop("password", None)
    if password == "":
        password = None
    data = _clean_payload(model, raw, exclude_pk=True)
    m2m_skip = {"groups", "user_permissions"}
    for name, value in data.items():
        if name in m2m_skip:
            continue
        setattr(instance, name, value)
    if password:
        instance.set_password(str(password))
    try:
        instance.full_clean()
        instance.save()
    except (ValidationError, IntegrityError) as exc:
        raise _validation_error_from_exception(exc) from exc
    return serialize_instance(model, instance)


def create_model_row(app_label: str, model_name: str, payload: dict[str, Any]) -> dict[str, Any]:
    """Cree une ligne via ORM (whitelist registry)."""
    model = _resolve_model(app_label, model_name)
    if _is_auth_user_model(model):
        return _create_auth_user(model, payload)
    data = _clean_payload(model, payload, exclude_pk=True)
    try:
        instance = model(**data)
        instance.full_clean()
        instance.save()
    except (ValidationError, IntegrityError) as exc:
        raise _validation_error_from_exception(exc) from exc
    return serialize_instance(model, instance)


def update_model_row(
    app_label: str,
    model_name: str,
    pk: str,
    payload: dict[str, Any],
) -> dict[str, Any]:
    """Met a jour une ligne via ORM."""
    model = _resolve_model(app_label, model_name)
    instance = model.objects.get(pk=pk)
    if _is_auth_user_model(model):
        return _update_auth_user(model, instance, payload)
    data = _clean_payload(model, payload, exclude_pk=True)
    for name, value in data.items():
        setattr(instance, name, value)
    try:
        instance.full_clean()
        instance.save()
    except (ValidationError, IntegrityError) as exc:
        raise _validation_error_from_exception(exc) from exc
    return serialize_instance(model, instance)


def delete_model_row(app_label: str, model_name: str, pk: str) -> None:
    """Supprime une ligne via ORM."""
    model = _resolve_model(app_label, model_name)
    model.objects.filter(pk=pk).delete()


# ---------------------------------------------------------------------------
# DDL Postgres (type DBeaver) — superuser JWT + blacklist systeme
# ---------------------------------------------------------------------------
#
# Politique :
# - Autorise CREATE/ALTER/DROP sur toute table ``public`` sauf blacklist
#   systeme (prefixes ``django_``, ``auth_``, ``celery_``).
# - Les tables metier custom (hors Django) sont OK, y compris hors Model ORM.
# - PostgreSQL uniquement ; identifiants valides ; types whitelist ;
#   jamais de SQL concatene non valide ; statement_timeout ; une instruction.
# ---------------------------------------------------------------------------


class AdminDdlError(ValueError):
    """Erreur DDL admin (identifiant, blacklist, vendor, validation)."""


_IDENT_RE = re.compile(r"^[a-zA-Z_][a-zA-Z0-9_]*$")
_DDL_TIMEOUT_MS = 10_000

# Prefixe blacklist : tables framework / auth / broker — non DDL-ables.
ADMIN_DDL_BLACKLIST_PREFIXES: tuple[str, ...] = (
    "django_",
    "auth_",
    "celery_",
)

# Types Postgres autorises (base + varchar(n) / numeric(p,s)).
_ALLOWED_TYPE_RE = re.compile(
    r"^(?:"
    r"varchar(?:\(\d+\))?|"
    r"character varying(?:\(\d+\))?|"
    r"text|integer|int|bigint|smallint|boolean|bool|"
    r"timestamptz|timestamp(?: without time zone)?|"
    r"timestamp with time zone|date|"
    r"numeric(?:\(\d+(?:\s*,\s*\d+)?\))?|"
    r"decimal(?:\(\d+(?:\s*,\s*\d+)?\))?|"
    r"uuid|jsonb|json|real|double precision|bytea|"
    r"serial|bigserial|smallserial"
    r")$",
    re.IGNORECASE,
)

_DEFAULT_LITERAL_RE = re.compile(
    r"^(?:NULL|TRUE|FALSE|CURRENT_TIMESTAMP|"
    r"[0-9]+(?:\.[0-9]+)?|"
    r"'(?:[^']|'')*')$",
    re.IGNORECASE,
)


def validate_sql_identifier(name: str, *, label: str = "Identifiant") -> str:
    """Valide un identifiant SQL (table/colonne).

    Args:
        name: Nom candidat.
        label: Libelle pour le message d''erreur.

    Returns:
        Le nom valide (inchange).

    Raises:
        AdminDdlError: Si le motif ``^[a-zA-Z_][a-zA-Z0-9_]*$`` echoue.
    """
    cleaned = (name or "").strip()
    if not cleaned or not _IDENT_RE.match(cleaned):
        raise AdminDdlError(
            f"{label} invalide : {name!r} "
            "(attendu ^[a-zA-Z_][a-zA-Z0-9_]*$)."
        )
    return cleaned


def validate_column_type(pg_type: str) -> str:
    """Valide un type Postgres contre la whitelist DDL.

    Args:
        pg_type: Type declare (ex. ``varchar(255)``, ``timestamptz``).

    Returns:
        Type normalise (strip, lower pour les alias simples).

    Raises:
        AdminDdlError: Type hors whitelist.
    """
    cleaned = (pg_type or "").strip()
    if not cleaned or not _ALLOWED_TYPE_RE.match(cleaned):
        raise AdminDdlError(f"Type Postgres non autorise : {pg_type!r}")
    return cleaned


def is_ddl_table_blacklisted(table_name: str) -> bool:
    """Indique si une table est dans la blacklist systeme DDL.

    Args:
        table_name: Nom de table (schema public).

    Returns:
        True si prefixe ``django_`` / ``auth_`` / ``celery_``.
    """
    lower = table_name.lower()
    return any(lower.startswith(prefix) for prefix in ADMIN_DDL_BLACKLIST_PREFIXES)


def _quote_ident(name: str, *, label: str = "Identifiant") -> str:
    """Retourne un identifiant quote apres validation stricte."""
    validated = validate_sql_identifier(name, label=label)
    return f'"{validated}"'


def _ensure_postgresql_ddl() -> None:
    """Refuse le DDL hors PostgreSQL."""
    if connection.vendor != "postgresql":
        raise AdminDdlError("Les operations DDL sont reservees a PostgreSQL.")


def _require_superuser(actor: AbstractBaseUser | None) -> None:
    """Defense en profondeur : DDL reserve aux superusers actifs."""
    if actor is None or not getattr(actor, "is_active", False):
        raise AdminDdlError("Authentification superuser requise pour le DDL.")
    if not getattr(actor, "is_superuser", False):
        raise AdminDdlError("Seuls les superusers peuvent executer du DDL.")


def _assert_table_ddl_allowed(table_name: str) -> str:
    """Valide le nom et refuse la blacklist systeme."""
    name = validate_sql_identifier(table_name, label="Nom de table")
    if is_ddl_table_blacklisted(name):
        raise AdminDdlError(
            f"Table systeme protegee (blacklist DDL) : {name}. "
            "Prefixes refuses : django_, auth_, celery_."
        )
    return name


def _validate_default_literal(default: str | None) -> str | None:
    """Valide un defaut SQL litteral simple (pas d''expression libre)."""
    if default is None:
        return None
    cleaned = default.strip()
    if not cleaned:
        return None
    if not _DEFAULT_LITERAL_RE.match(cleaned):
        raise AdminDdlError(
            f"Valeur DEFAULT non autorisee : {default!r} "
            "(NULL, TRUE/FALSE, nombre, CURRENT_TIMESTAMP ou 'texte')."
        )
    return cleaned


def _run_ddl(sql: str) -> None:
    """Execute une instruction DDL unique sous transaction + statement_timeout.

    Args:
        sql: Instruction deja construite avec identifiants valides uniquement.

    Raises:
        AdminDdlError: Erreur SQL ou vendor.
    """
    _ensure_postgresql_ddl()
    if ";" in sql.rstrip(";"):
        raise AdminDdlError("Une seule instruction DDL a la fois.")
    with transaction.atomic():
        with connection.cursor() as cursor:
            cursor.execute(
                "SET LOCAL statement_timeout = %s",
                [str(_DDL_TIMEOUT_MS)],
            )
            try:
                cursor.execute(sql)
            except Exception as exc:
                raise AdminDdlError(f"Erreur DDL : {exc}") from exc


def create_table(
    name: str,
    columns: Sequence[dict[str, object]],
    *,
    actor: AbstractBaseUser | None = None,
) -> dict[str, object]:
    """Cree une table public (DDL).

    Args:
        name: Nom de table (hors blacklist).
        columns: Liste de dicts ``name``, ``type``, ``nullable``, ``primary_key``.
        actor: Utilisateur JWT (superuser requis).

    Returns:
        Dict ``name`` + ``columns`` crees.

    Raises:
        AdminDdlError: Validation, blacklist ou erreur SQL.
    """
    _require_superuser(actor)
    table = _assert_table_ddl_allowed(name)
    if not columns:
        raise AdminDdlError("Au moins une colonne est requise.")

    col_sql_parts: list[str] = []
    pk_cols: list[str] = []
    seen: set[str] = set()
    normalized: list[dict[str, object]] = []

    for raw in columns:
        col_name = validate_sql_identifier(str(raw.get("name", "")), label="Nom de colonne")
        if col_name.lower() in seen:
            raise AdminDdlError(f"Colonne en double : {col_name}")
        seen.add(col_name.lower())
        col_type = validate_column_type(str(raw.get("type", "")))
        nullable = bool(raw.get("nullable", True))
        is_pk = bool(raw.get("primary_key", False))
        # PK implique NOT NULL ; nullable ignore si PK.
        null_clause = " NOT NULL" if (is_pk or not nullable) else " NULL"
        col_sql_parts.append(
            f"{_quote_ident(col_name, label='Nom de colonne')} {col_type}{null_clause}"
        )
        if is_pk:
            pk_cols.append(col_name)
        normalized.append(
            {
                "name": col_name,
                "type": col_type,
                "nullable": (not is_pk) and nullable,
                "primary_key": is_pk,
            }
        )

    if pk_cols:
        pk_list = ", ".join(_quote_ident(c, label="Nom de colonne") for c in pk_cols)
        col_sql_parts.append(f"PRIMARY KEY ({pk_list})")

    body = ", ".join(col_sql_parts)
    sql = f"CREATE TABLE {_quote_ident(table, label='Nom de table')} ({body})"
    _run_ddl(sql)
    return {"name": table, "columns": normalized}


def drop_table(
    name: str,
    *,
    confirm_name: str,
    actor: AbstractBaseUser | None = None,
) -> None:
    """Supprime une table public (hors blacklist systeme).

    Exige ``confirm_name`` egal au nom valide (defense hors ``hx-confirm``
    client, bypassable).

    Args:
        name: Nom de table.
        confirm_name: Doit correspondre exactement a ``name`` valide.
        actor: Superuser JWT.

    Raises:
        AdminDdlError: Blacklist, confirmation, validation ou erreur SQL.
    """
    _require_superuser(actor)
    table = _assert_table_ddl_allowed(name)
    if (confirm_name or "").strip() != table:
        raise AdminDdlError(
            "Confirmation invalide : ressaisir le nom exact de la table a supprimer."
        )
    sql = f"DROP TABLE {_quote_ident(table, label='Nom de table')}"
    _run_ddl(sql)


def add_column(
    table: str,
    name: str,
    pg_type: str,
    *,
    nullable: bool = True,
    default: str | None = None,
    actor: AbstractBaseUser | None = None,
) -> dict[str, object]:
    """Ajoute une colonne a une table public.

    Args:
        table: Nom de table (hors blacklist).
        name: Nom de colonne.
        pg_type: Type whitelist.
        nullable: Si False, NOT NULL (DEFAULT requis si table non vide cote PG).
        default: Litteral DEFAULT optionnel (valide strictement).
        actor: Superuser JWT.

    Returns:
        Dict decrivant la colonne ajoutee.
    """
    _require_superuser(actor)
    table_name = _assert_table_ddl_allowed(table)
    col_name = validate_sql_identifier(name, label="Nom de colonne")
    col_type = validate_column_type(pg_type)
    default_sql = _validate_default_literal(default)

    parts = [
        f"ALTER TABLE {_quote_ident(table_name, label='Nom de table')}",
        f"ADD COLUMN {_quote_ident(col_name, label='Nom de colonne')} {col_type}",
    ]
    if default_sql is not None:
        parts.append(f"DEFAULT {default_sql}")
    if not nullable:
        parts.append("NOT NULL")
    _run_ddl(" ".join(parts))
    return {
        "table": table_name,
        "name": col_name,
        "type": col_type,
        "nullable": nullable,
        "default": default_sql,
    }


def rename_column(
    table: str,
    old_name: str,
    new_name: str,
    *,
    actor: AbstractBaseUser | None = None,
) -> dict[str, str]:
    """Renomme une colonne.

    Args:
        table: Table cible (hors blacklist).
        old_name: Nom actuel.
        new_name: Nouveau nom.
        actor: Superuser JWT.

    Returns:
        Dict ``table``, ``old_name``, ``new_name``.
    """
    _require_superuser(actor)
    table_name = _assert_table_ddl_allowed(table)
    old_col = validate_sql_identifier(old_name, label="Nom de colonne")
    new_col = validate_sql_identifier(new_name, label="Nouveau nom de colonne")
    sql = (
        f"ALTER TABLE {_quote_ident(table_name, label='Nom de table')} "
        f"RENAME COLUMN {_quote_ident(old_col, label='Nom de colonne')} "
        f"TO {_quote_ident(new_col, label='Nouveau nom de colonne')}"
    )
    _run_ddl(sql)
    return {"table": table_name, "old_name": old_col, "new_name": new_col}


def drop_column(
    table: str,
    name: str,
    *,
    actor: AbstractBaseUser | None = None,
) -> None:
    """Supprime une colonne (refuse si colonne PK).

    Args:
        table: Table cible.
        name: Colonne a supprimer.
        actor: Superuser JWT.

    Raises:
        AdminDdlError: Si PK ou blacklist.
    """
    _require_superuser(actor)
    table_name = _assert_table_ddl_allowed(table)
    col_name = validate_sql_identifier(name, label="Nom de colonne")

    with connection.cursor() as cursor:
        cursor.execute(
            """
            SELECT kcu.column_name
            FROM information_schema.table_constraints tc
            JOIN information_schema.key_column_usage kcu
              ON tc.constraint_name = kcu.constraint_name
             AND tc.table_schema = kcu.table_schema
            WHERE tc.constraint_type = 'PRIMARY KEY'
              AND tc.table_schema = 'public'
              AND tc.table_name = %s
            """,
            [table_name],
        )
        pk_cols = {row[0] for row in cursor.fetchall()}
    if col_name in pk_cols:
        raise AdminDdlError(
            f"Impossible de supprimer la colonne PK : {col_name}."
        )

    sql = (
        f"ALTER TABLE {_quote_ident(table_name, label='Nom de table')} "
        f"DROP COLUMN {_quote_ident(col_name, label='Nom de colonne')}"
    )
    _run_ddl(sql)


def alter_column_type(
    table: str,
    name: str,
    new_type: str,
    *,
    actor: AbstractBaseUser | None = None,
) -> dict[str, str]:
    """Change le type d''une colonne (ALTER COLUMN ... TYPE).

    Args:
        table: Table cible.
        name: Colonne.
        new_type: Type whitelist.
        actor: Superuser JWT.

    Returns:
        Dict ``table``, ``name``, ``type``.
    """
    _require_superuser(actor)
    table_name = _assert_table_ddl_allowed(table)
    col_name = validate_sql_identifier(name, label="Nom de colonne")
    col_type = validate_column_type(new_type)
    quoted_table = _quote_ident(table_name, label="Nom de table")
    quoted_col = _quote_ident(col_name, label="Nom de colonne")
    # USING explicite pour conversions courantes ; identifiants deja valides.
    sql = (
        f"ALTER TABLE {quoted_table} "
        f"ALTER COLUMN {quoted_col} TYPE {col_type} "
        f"USING {quoted_col}::{col_type}"
    )
    _run_ddl(sql)
    return {"table": table_name, "name": col_name, "type": col_type}


# ---------------------------------------------------------------------------
# DML securise (tables custom hors ORM) — meme validation d''identifiants / blacklist
# ---------------------------------------------------------------------------

_DML_TIMEOUT_MS = 10_000
_MAX_TABLE_ROWS = 200


class AdminDmlError(ValueError):
    """Erreur DML admin (identifiant, blacklist, vendor, validation)."""


def find_registry_entry_for_table(table_name: str) -> dict[str, str] | None:
    """Retrouve une entree registry dont le ``db_table`` correspond.

    Args:
        table_name: Nom de table Postgres (schema public).

    Returns:
        Dict ``app_label`` / ``model_name`` / ``label``, ou None.
    """
    name = validate_sql_identifier(table_name, label="Nom de table")
    for entry in ADMIN_MODEL_REGISTRY:
        model = django_apps.get_model(entry["app_label"], entry["model_name"])
        if model._meta.db_table == name:
            return {
                "app_label": entry["app_label"],
                "model_name": entry["model_name"],
                "label": entry["label"],
            }
    return None


def _table_primary_keys(table_name: str) -> list[str]:
    """Liste les colonnes PK d''une table public."""
    with connection.cursor() as cursor:
        cursor.execute(
            """
            SELECT kcu.column_name
            FROM information_schema.table_constraints tc
            JOIN information_schema.key_column_usage kcu
              ON tc.constraint_name = kcu.constraint_name
             AND tc.table_schema = kcu.table_schema
            WHERE tc.constraint_type = 'PRIMARY KEY'
              AND tc.table_schema = 'public'
              AND tc.table_name = %s
            ORDER BY kcu.ordinal_position
            """,
            [table_name],
        )
        return [row[0] for row in cursor.fetchall()]


def _assert_public_table_exists(table_name: str) -> str:
    """Valide l''identifiant et confirme l''existence en schema public."""
    name = validate_sql_identifier(table_name, label="Nom de table")
    with connection.cursor() as cursor:
        cursor.execute(
            """
            SELECT 1 FROM information_schema.tables
            WHERE table_schema = 'public'
              AND table_type = 'BASE TABLE'
              AND table_name = %s
            """,
            [name],
        )
        if cursor.fetchone() is None:
            raise AdminDmlError(f"Table introuvable : {name}")
    return name


def _run_dml(sql: str, params: Sequence[object] | None = None) -> int:
    """Execute une instruction DML parametree sous transaction + timeout.

    Args:
        sql: SQL avec placeholders ``%s`` uniquement (identifiants deja quotes).
        params: Parametres binds.

    Returns:
        Nombre de lignes affectees (rowcount).
    """
    _ensure_postgresql_ddl()
    if ";" in sql.rstrip(";"):
        raise AdminDmlError("Une seule instruction DML a la fois.")
    with transaction.atomic():
        with connection.cursor() as cursor:
            cursor.execute(
                "SET LOCAL statement_timeout = %s",
                [str(_DML_TIMEOUT_MS)],
            )
            try:
                cursor.execute(sql, list(params or []))
            except Exception as exc:
                raise AdminDmlError(f"Erreur DML : {exc}") from exc
            return int(cursor.rowcount or 0)


def list_table_rows(
    table_name: str,
    *,
    limit: int = _MAX_TABLE_ROWS,
    actor: AbstractBaseUser | None = None,
) -> dict[str, object]:
    """Liste les lignes d''une table public (SELECT securise).

    Prefere le CRUD ORM si la table est mappee au registry.

    Args:
        table_name: Table cible.
        limit: Plafond de lignes (max ``_MAX_TABLE_ROWS``).
        actor: Superuser requis.

    Returns:
        Dict ``columns``, ``rows``, ``primary_keys``, ``row_count``, ``source``.
    """
    _require_superuser(actor)
    name = _assert_public_table_exists(table_name)
    capped = max(1, min(int(limit), _MAX_TABLE_ROWS))
    registry = find_registry_entry_for_table(name)
    if registry is not None:
        payload = list_model_rows(
            registry["app_label"],
            registry["model_name"],
            limit=capped,
        )
        rows = payload["results"]
        assert isinstance(rows, list)
        columns = list(rows[0].keys()) if rows else []
        if not columns:
            model = _resolve_model(registry["app_label"], registry["model_name"])
            columns = []
            for field in model._meta.concrete_fields:
                if field.name == "password":
                    if _is_auth_user_model(model):
                        columns.append("password_set")
                    continue
                columns.append(field.name)
        return {
            "table": name,
            "columns": columns,
            "rows": rows,
            "primary_keys": [payload["pk_field"]],
            "row_count": payload["count"],
            "source": "orm",
            "registry": registry,
        }

    quoted = _quote_ident(name, label="Nom de table")
    pks = _table_primary_keys(name)
    with transaction.atomic():
        with connection.cursor() as cursor:
            cursor.execute(
                "SET LOCAL statement_timeout = %s",
                [str(_DML_TIMEOUT_MS)],
            )
            cursor.execute(f"SELECT * FROM {quoted} LIMIT %s", [capped])  # noqa: S608
            if cursor.description is None:
                return {
                    "table": name,
                    "columns": [],
                    "rows": [],
                    "primary_keys": pks,
                    "row_count": 0,
                    "source": "sql",
                    "registry": None,
                }
            columns = [col[0] for col in cursor.description]
            raw_rows = cursor.fetchall()
            rows = [
                {col: _serialize_value(raw[idx]) for idx, col in enumerate(columns)}
                for raw in raw_rows
            ]
            cursor.execute(f"SELECT COUNT(*) FROM {quoted}")  # noqa: S608
            total = int(cursor.fetchone()[0])
    return {
        "table": name,
        "columns": columns,
        "rows": rows,
        "primary_keys": pks,
        "row_count": total,
        "source": "sql",
        "registry": None,
    }


def update_table_cell(
    table_name: str,
    *,
    primary_key: str,
    primary_key_value: object,
    column: str,
    value: object,
    actor: AbstractBaseUser | None = None,
) -> dict[str, object]:
    """Met a jour une cellule (ORM registry ou UPDATE SQL parametre).

    Args:
        table_name: Table cible.
        primary_key: Nom de la colonne PK.
        primary_key_value: Valeur PK.
        column: Colonne a modifier (pas la PK).
        value: Nouvelle valeur (None / "" -> NULL).
        actor: Superuser requis.

    Returns:
        Dict recapitulant la mise a jour.
    """
    _require_superuser(actor)
    name = _assert_public_table_exists(table_name)
    pk_col = validate_sql_identifier(primary_key, label="Nom de colonne PK")
    col = validate_sql_identifier(column, label="Nom de colonne")
    if col == pk_col:
        raise AdminDmlError("La cle primaire n''est pas editable.")
    if col == "password_set":
        raise AdminModelValidationError(
            "Le champ password_set est en lecture seule "
            "(indique si un mot de passe est defini)."
        )

    registry = find_registry_entry_for_table(name)
    if registry is not None:
        model = _resolve_model(registry["app_label"], registry["model_name"])
        if col not in _editable_fields(model):
            raise AdminModelValidationError(
                f"Le champ '{col}' n'est pas editable."
            )
        updated = update_model_row(
            registry["app_label"],
            registry["model_name"],
            str(primary_key_value),
            {col: value},
        )
        return {"table": name, "column": col, "row": updated, "source": "orm"}

    if is_ddl_table_blacklisted(name):
        raise AdminDmlError(
            f"Mutation refusee sur table systeme : {name}."
        )
    cell_value: object | None = None if value in ("", None) else value
    sql = (
        f"UPDATE {_quote_ident(name, label='Nom de table')} "
        f"SET {_quote_ident(col, label='Nom de colonne')} = %s "
        f"WHERE {_quote_ident(pk_col, label='Nom de colonne PK')} = %s"
    )
    affected = _run_dml(sql, [cell_value, primary_key_value])
    if affected == 0:
        raise AdminDmlError("Aucune ligne mise a jour (PK introuvable).")
    return {
        "table": name,
        "column": col,
        "primary_key": pk_col,
        "primary_key_value": primary_key_value,
        "value": cell_value,
        "source": "sql",
    }


def insert_table_row(
    table_name: str,
    payload: dict[str, object],
    *,
    actor: AbstractBaseUser | None = None,
) -> dict[str, object]:
    """Insert une ligne (ORM registry ou INSERT SQL).

    Args:
        table_name: Table cible.
        payload: Colonnes -> valeurs (identifiants valides uniquement).
        actor: Superuser requis.

    Returns:
        Dict ``table`` + ``row`` / confirmation.
    """
    _require_superuser(actor)
    name = _assert_public_table_exists(table_name)
    registry = find_registry_entry_for_table(name)
    if registry is not None:
        created = create_model_row(
            registry["app_label"],
            registry["model_name"],
            dict(payload),
        )
        return {"table": name, "row": created, "source": "orm"}

    if is_ddl_table_blacklisted(name):
        raise AdminDmlError(f"Insertion refusee sur table systeme : {name}.")
    if not payload:
        raise AdminDmlError("Payload vide.")
    cols: list[str] = []
    values: list[object] = []
    for key, raw in payload.items():
        col = validate_sql_identifier(str(key), label="Nom de colonne")
        cols.append(col)
        values.append(None if raw in ("", None) else raw)
    col_sql = ", ".join(_quote_ident(c, label="Nom de colonne") for c in cols)
    placeholders = ", ".join(["%s"] * len(cols))
    sql = (
        f"INSERT INTO {_quote_ident(name, label='Nom de table')} ({col_sql}) "
        f"VALUES ({placeholders})"
    )
    _run_dml(sql, values)
    return {"table": name, "columns": cols, "source": "sql"}


def delete_table_row(
    table_name: str,
    *,
    primary_key: str,
    primary_key_value: object,
    actor: AbstractBaseUser | None = None,
) -> None:
    """Supprime une ligne (ORM registry ou DELETE SQL).

    Args:
        table_name: Table cible.
        primary_key: Colonne PK.
        primary_key_value: Valeur PK.
        actor: Superuser requis.
    """
    _require_superuser(actor)
    name = _assert_public_table_exists(table_name)
    pk_col = validate_sql_identifier(primary_key, label="Nom de colonne PK")
    registry = find_registry_entry_for_table(name)
    if registry is not None:
        delete_model_row(
            registry["app_label"],
            registry["model_name"],
            str(primary_key_value),
        )
        return

    if is_ddl_table_blacklisted(name):
        raise AdminDmlError(f"Suppression refusee sur table systeme : {name}.")
    sql = (
        f"DELETE FROM {_quote_ident(name, label='Nom de table')} "
        f"WHERE {_quote_ident(pk_col, label='Nom de colonne PK')} = %s"
    )
    affected = _run_dml(sql, [primary_key_value])
    if affected == 0:
        raise AdminDmlError("Aucune ligne supprimee (PK introuvable).")
'@

    Write-TextFile -Path (Join-Path $panelDir "schemas.py") -Content @'
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
'@

    Write-TextFile -Path (Join-Path $panelDir "auth.py") -Content @'
"""JWT utilitaires pour l''admin panel (superuser)."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import Any

import jwt
from django.conf import settings
from django.contrib.auth import get_user_model
from ninja.security import HttpBearer

User = get_user_model()

ACCESS_LIFETIME = timedelta(hours=8)
REFRESH_LIFETIME = timedelta(days=1)
ALGORITHM = "HS256"


def _encode(payload: dict[str, Any], lifetime: timedelta) -> str:
    now = datetime.now(tz=UTC)
    body = {
        **payload,
        "exp": now + lifetime,
        "iat": now,
    }
    return jwt.encode(body, settings.SECRET_KEY, algorithm=ALGORITHM)


def create_token_pair(user: User) -> dict[str, str]:
    """Genere une paire access/refresh JWT (superuser actif uniquement)."""
    if not user.is_active or not user.is_superuser:
        raise PermissionError("JWT admin reserve aux superusers actifs.")
    base = {"user_id": user.pk, "username": user.username}
    return {
        "access": _encode({**base, "type": "access"}, ACCESS_LIFETIME),
        "refresh": _encode({**base, "type": "refresh"}, REFRESH_LIFETIME),
    }


class AdminJWTAuth(HttpBearer):
    """Authentification Bearer JWT - superuser requis."""

    def authenticate(self, request, token: str) -> User | None:
        try:
            payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[ALGORITHM])
        except jwt.PyJWTError:
            return None
        if payload.get("type") != "access":
            return None
        user_id = payload.get("user_id")
        if not user_id:
            return None
        try:
            user = User.objects.get(pk=user_id)
        except User.DoesNotExist:
            return None
        if not user.is_active or not user.is_superuser:
            return None
        return user
'@

    Write-TextFile -Path (Join-Path $panelDir "api.py") -Content @'
"""Routes API admin panel (Django Ninja)."""

from __future__ import annotations

from django.contrib.auth import authenticate
from django.core.exceptions import ObjectDoesNotExist
from ninja import Router, Schema

from . import selectors
from .auth import AdminJWTAuth, create_token_pair
from .schemas import AddColumnIn, ColumnPatchIn, CreateTableIn, QueryExecuteIn

auth_router = Router(tags=["auth"])
admin_router = Router(tags=["admin"])
_admin_auth = AdminJWTAuth()


class LoginIn(Schema):
    username: str
    password: str


class LoginUserOut(Schema):
    username: str
    is_superuser: bool


class LoginOut(Schema):
    access: str
    refresh: str
    user: LoginUserOut


class SessionOut(Schema):
    username: str
    is_superuser: bool


@auth_router.post("/login/", response={200: LoginOut, 400: dict, 401: dict, 403: dict})
def admin_login(request, payload: LoginIn):
    """POST /api/auth/login/ - JWT si superuser."""
    username = payload.username.strip()
    password = payload.password
    if not username or not password:
        return 400, {
            "detail": "Identifiant et mot de passe requis.",
            "code": "missing_credentials",
        }
    user = authenticate(request=request, username=username, password=password)
    if user is None:
        return 401, {
            "detail": "Identifiants incorrects pour cette base de donnees.",
            "code": "invalid_credentials",
        }
    if not user.is_superuser:
        return 403, {
            "detail": (
                "Compte reconnu mais acces refuse : superuser Django requis "
                "(docker compose exec web uv run python manage.py createsuperuser)."
            ),
            "code": "not_superuser",
        }
    tokens = create_token_pair(user)
    return 200, LoginOut(
        access=tokens["access"],
        refresh=tokens["refresh"],
        user=LoginUserOut(username=user.username, is_superuser=user.is_superuser),
    )


@auth_router.get("/session/", response={200: SessionOut, 401: dict, 403: dict}, auth=_admin_auth)
def admin_session(request):
    """GET /api/auth/session/ - profil superuser connecte."""
    user = request.auth
    return SessionOut(username=user.username, is_superuser=user.is_superuser)


@admin_router.get("/registry/", auth=_admin_auth)
def registry_list(request):
    """GET /api/admin/registry/ - liste whitelist models."""
    return {"results": selectors.list_registry_entries()}


@admin_router.get("/schema/", auth=_admin_auth)
def schema_global(request):
    """GET /api/admin/schema/ - schema global + liaisons."""
    return selectors.get_global_schema()


@admin_router.get("/schema/{app_label}/{model_name}/", auth=_admin_auth)
def schema_model(request, app_label: str, model_name: str):
    """GET /api/admin/schema/<app>/<model>/ - schema d''une table."""
    return selectors.get_model_schema(app_label, model_name)


@admin_router.get("/schema/export/", auth=_admin_auth)
def schema_export(request):
    """GET /api/admin/schema/export/ - export Mermaid markdown."""
    mermaid = selectors.export_schema_mermaid()
    return {
        "format": "mermaid",
        "markdown": mermaid,
        "svg_hint": "Telecharger via frontend/admin/schema (V2)",
    }


@admin_router.get("/models/{app_label}/{model_name}/", auth=_admin_auth, response={200: dict, 404: dict})
def model_rows_list(request, app_label: str, model_name: str):
    """GET /api/admin/models/<app>/<model>/ - grille admin CRUD."""
    from .services import AdminModelNotAllowedError, list_model_rows

    try:
        return list_model_rows(app_label, model_name)
    except AdminModelNotAllowedError:
        return 404, {"detail": "Model non autorise"}


@admin_router.post("/models/{app_label}/{model_name}/", auth=_admin_auth, response={201: dict, 400: dict, 404: dict})
def model_rows_create(request, app_label: str, model_name: str, payload: dict):
    """POST /api/admin/models/<app>/<model>/ - creation."""
    from .services import (
        AdminModelNotAllowedError,
        AdminModelValidationError,
        create_model_row,
    )

    try:
        row = create_model_row(app_label, model_name, payload)
        return 201, row
    except AdminModelNotAllowedError:
        return 404, {"detail": "Model non autorise"}
    except AdminModelValidationError as exc:
        return 400, {"detail": exc.detail, "fields": exc.fields}
    except ValueError as exc:
        return 400, {"detail": str(exc)}


@admin_router.patch("/models/{app_label}/{model_name}/{pk}/", auth=_admin_auth, response={200: dict, 400: dict, 404: dict})
def model_row_update(request, app_label: str, model_name: str, pk: str, payload: dict):
    """PATCH /api/admin/models/<app>/<model>/<pk>/."""
    from .services import (
        AdminModelNotAllowedError,
        AdminModelValidationError,
        update_model_row,
    )

    try:
        return update_model_row(app_label, model_name, pk, payload)
    except AdminModelNotAllowedError:
        return 404, {"detail": "Model non autorise"}
    except ObjectDoesNotExist:
        return 404, {"detail": "Ligne introuvable"}
    except AdminModelValidationError as exc:
        return 400, {"detail": exc.detail, "fields": exc.fields}
    except ValueError as exc:
        return 400, {"detail": str(exc)}


@admin_router.delete("/models/{app_label}/{model_name}/{pk}/", auth=_admin_auth, response={204: None, 404: dict})
def model_row_delete(request, app_label: str, model_name: str, pk: str):
    """DELETE /api/admin/models/<app>/<model>/<pk>/."""
    from .services import AdminModelNotAllowedError, delete_model_row

    try:
        delete_model_row(app_label, model_name, pk)
        return 204, None
    except AdminModelNotAllowedError:
        return 404, {"detail": "Model non autorise"}
    except ObjectDoesNotExist:
        return 404, {"detail": "Ligne introuvable"}


@admin_router.post("/query/", auth=_admin_auth, response={200: dict, 400: dict})
def query_execute(request, payload: QueryExecuteIn):
    """POST /api/admin/query/ - execute une requete SELECT lecture seule."""
    from .selectors import AdminQueryError, execute_readonly_query

    sql = payload.sql.strip()
    try:
        return execute_readonly_query(sql)
    except AdminQueryError as exc:
        return 400, {"detail": str(exc)}


# --- Introspection + DDL Postgres (/api/admin/db/...) ----------------------


@admin_router.get("/db/tables/", auth=_admin_auth, response={200: dict, 400: dict})
def db_tables_list(request):
    """GET /api/admin/db/tables/ - tables public (colonnes, PK, row_count)."""
    from .selectors import AdminIntrospectionError, list_database_tables

    try:
        return {"results": list_database_tables()}
    except AdminIntrospectionError as exc:
        return 400, {"detail": str(exc)}


@admin_router.get("/db/schema/", auth=_admin_auth, response={200: dict, 400: dict})
def db_schema_overview(request):
    """GET /api/admin/db/schema/ - overview tables + FK (SchemaOverview)."""
    from .selectors import AdminIntrospectionError, get_database_schema_overview

    try:
        return get_database_schema_overview()
    except AdminIntrospectionError as exc:
        return 400, {"detail": str(exc)}


@admin_router.post("/db/tables/", auth=_admin_auth, response={201: dict, 400: dict})
def db_table_create(request, payload: CreateTableIn):
    """POST /api/admin/db/tables/ - CREATE TABLE (hors blacklist)."""
    from .services import AdminDdlError, create_table

    columns = [
        {
            "name": col.name,
            "type": col.type,
            "nullable": col.nullable,
            "primary_key": col.primary_key,
        }
        for col in payload.columns
    ]
    try:
        created = create_table(payload.name, columns, actor=request.auth)
        return 201, created
    except AdminDdlError as exc:
        return 400, {"detail": str(exc)}


@admin_router.delete("/db/tables/{name}/", auth=_admin_auth, response={204: None, 400: dict})
def db_table_drop(request, name: str, confirm_name: str):
    """DELETE /api/admin/db/tables/<name>/?confirm_name= - DROP TABLE.

    ``confirm_name`` obligatoire (doit egaler ``name``) — anti-suppression
    accidentelle / client non conforme.
    """
    from .services import AdminDdlError, drop_table

    try:
        drop_table(name, confirm_name=confirm_name, actor=request.auth)
        return 204, None
    except AdminDdlError as exc:
        return 400, {"detail": str(exc)}


@admin_router.post(
    "/db/tables/{name}/columns/",
    auth=_admin_auth,
    response={201: dict, 400: dict},
)
def db_column_add(request, name: str, payload: AddColumnIn):
    """POST /api/admin/db/tables/<name>/columns/ - ADD COLUMN."""
    from .services import AdminDdlError, add_column

    try:
        created = add_column(
            name,
            payload.name,
            payload.type,
            nullable=payload.nullable,
            default=payload.default,
            actor=request.auth,
        )
        return 201, created
    except AdminDdlError as exc:
        return 400, {"detail": str(exc)}


@admin_router.patch(
    "/db/tables/{name}/columns/{col}/",
    auth=_admin_auth,
    response={200: dict, 400: dict},
)
def db_column_patch(request, name: str, col: str, payload: ColumnPatchIn):
    """PATCH /api/admin/db/tables/<name>/columns/<col>/ - rename et/ou type."""
    from .services import AdminDdlError, alter_column_type, rename_column

    if payload.new_name is None and payload.new_type is None:
        return 400, {"detail": "Fournir new_name et/ou new_type."}

    result: dict[str, object] = {"table": name, "column": col}
    try:
        current_col = col
        if payload.new_name is not None:
            renamed = rename_column(
                name, current_col, payload.new_name, actor=request.auth
            )
            result.update(renamed)
            current_col = renamed["new_name"]
        if payload.new_type is not None:
            typed = alter_column_type(
                name, current_col, payload.new_type, actor=request.auth
            )
            result.update(typed)
        return 200, result
    except AdminDdlError as exc:
        return 400, {"detail": str(exc)}


@admin_router.delete(
    "/db/tables/{name}/columns/{col}/",
    auth=_admin_auth,
    response={204: None, 400: dict},
)
def db_column_drop(request, name: str, col: str):
    """DELETE /api/admin/db/tables/<name>/columns/<col>/ - DROP COLUMN (pas PK)."""
    from .services import AdminDdlError, drop_column

    try:
        drop_column(name, col, actor=request.auth)
        return 204, None
    except AdminDdlError as exc:
        return 400, {"detail": str(exc)}
'@

    Write-TextFile -Path (Join-Path $panelDir "admin.py") -Content @'
"""Django admin natif non utilise pour les models registry (UI HTMX / API Ninja)."""
'@

    Write-TextFile -Path (Join-Path $panelDir "models.py") -Content @'
"""Pas de tables admin_panel - schema via models metier + migrations uniquement.
DDL ad-hoc = services DDL sur tables public hors blacklist (pas de Model Django).
"""
'@

    Write-TextFile -Path (Join-Path $panelDir "tests\test_registry.py") -Content @'
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
'@

    Write-TextFile -Path (Join-Path $panelDir "tests\test_schema.py") -Content @"
"""Tests schema admin panel."""

import pytest

from apps.admin_panel.selectors import (
    export_schema_mermaid,
    export_schema_mermaid_body,
    get_model_schema,
)


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
    assert md.strip().startswith("```mermaid")
    body = export_schema_mermaid_body()
    assert body.startswith("erDiagram")
    assert "```" not in body
"@

    Write-TextFile -Path (Join-Path $panelDir "tests\test_query.py") -Content @'
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
'@

    Write-TextFile -Path (Join-Path $panelDir "tests\test_ddl.py") -Content @'
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
'@
}
