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
    allowed = _editable_fields(model)
    cleaned: dict[str, Any] = {}
    pk_name = model._meta.pk.name
    for key, value in payload.items():
        if key not in allowed:
            continue
        if exclude_pk and key == pk_name:
            continue
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
    raw.pop("password_set", None)
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
            columns = [
                f.name
                for f in model._meta.concrete_fields
                if f.name != "password"
            ]
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

    registry = find_registry_entry_for_table(name)
    if registry is not None:
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