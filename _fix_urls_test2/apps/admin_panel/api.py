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