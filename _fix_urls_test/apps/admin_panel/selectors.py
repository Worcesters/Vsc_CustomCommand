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
    """Type court compatible Mermaid."""
    key = str(raw).strip()
    lower = key.lower()
    if lower in _MERMAID_TYPE_MAP:
        return _MERMAID_TYPE_MAP[lower]
    base = re.split(r"[\(\s]", lower, maxsplit=1)[0]
    if base in _MERMAID_TYPE_MAP:
        return _MERMAID_TYPE_MAP[base]
    return _mermaid_sanitize_ident(base or "text", max_len=24)


def _export_schema_mermaid_from_postgres() -> str:
    """Corps erDiagram base sur catalogue Postgres."""
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
    """Corps erDiagram fallback registry ORM."""
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
    """Corps Mermaid erDiagram sans fences (pour mermaid.render)."""
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