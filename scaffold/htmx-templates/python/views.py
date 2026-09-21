from __future__ import annotations

"""Vues template Console DataStudio (HTMX).

Toute logique passe par services / selectors admin_panel.
"""

from typing import Any

from django.contrib.auth.mixins import LoginRequiredMixin, UserPassesTestMixin
from django.http import Http404, HttpRequest, HttpResponse
from django.shortcuts import render
from django.views import View
from django.views.generic import TemplateView

from apps.admin_panel import selectors, services
from apps.admin_panel.services import (
    AdminDdlError,
    AdminDmlError,
    AdminModelValidationError,
    is_ddl_table_blacklisted,
    validate_sql_identifier,
)


class SuperuserRequiredMixin(LoginRequiredMixin, UserPassesTestMixin):
    """Exige un superuser authentifie (session Django).

    MRO:
    1. LoginRequiredMixin.dispatch -> redirection /accounts/login/
    2. UserPassesTestMixin.dispatch -> 403 si non superuser
    3. Vue concrete
    """

    login_url = "/accounts/login/"
    redirect_field_name = "next"

    def test_func(self) -> bool:
        user = self.request.user
        return bool(user.is_authenticated and user.is_active and user.is_superuser)


def _require_valid_table_name(table: str) -> str:
    """Valide l'identifiant de table (anti injection / path traversal URL).

    Raises:
        Http404: Identifiant hors motif ``^[a-zA-Z_][a-zA-Z0-9_]*$``.
    """
    try:
        return validate_sql_identifier(table, label="Nom de table")
    except AdminDdlError as exc:
        raise Http404("Table introuvable.") from exc


def _safe_overview() -> dict[str, Any]:
    try:
        return selectors.get_database_schema_overview()
    except selectors.AdminIntrospectionError:
        return {"tables": [], "foreign_keys": []}


def _build_display_rows(table_data: dict[str, Any]) -> tuple[list[dict[str, Any]], str | None]:
    """Construit les cellules d'affichage avec flag ``is_editable``."""
    pks = table_data.get("primary_keys") or []
    pk = str(pks[0]) if pks else None
    columns = list(table_data.get("columns") or [])
    source = str(table_data.get("source") or "sql")
    registry = table_data.get("registry")
    editable_cols: set[str] | None = None
    if source == "orm" and isinstance(registry, dict):
        from django.apps import apps as django_apps

        model = django_apps.get_model(registry["app_label"], registry["model_name"])
        editable_cols = {
            f.name for f in model._meta.concrete_fields if f.editable
        }
    display_rows: list[dict[str, Any]] = []
    for raw in table_data.get("rows") or []:
        assert isinstance(raw, dict)
        cells = []
        for col in columns:
            val = raw.get(col)
            is_null = val is None or val == ""
            is_pk = col == pk
            if is_pk or col == "password_set" or not pk:
                is_editable = False
            elif editable_cols is not None:
                is_editable = col in editable_cols
            else:
                is_editable = True
            cells.append(
                {
                    "name": col,
                    "display": "" if is_null else str(val),
                    "is_null": is_null,
                    "is_pk": is_pk,
                    "is_editable": is_editable,
                }
            )
        display_rows.append(
            {
                "pk_value": raw.get(pk) if pk else None,
                "cells": cells,
            }
        )
    return display_rows, pk


def _build_insert_fields(
    table_data: dict[str, Any],
    structure_columns: list[dict[str, Any]],
    pk: str | None,
) -> list[dict[str, Any]]:
    """Champs du formulaire d'insertion (obligatoires marques pour l'UI)."""
    columns = list(table_data.get("columns") or [])
    source = str(table_data.get("source") or "sql")
    registry = table_data.get("registry")
    meta = {
        str(col["name"]): col
        for col in structure_columns
        if isinstance(col, dict) and col.get("name")
    }
    orm_required: set[str] = set()
    if source == "orm" and isinstance(registry, dict):
        from django.apps import apps as django_apps

        model = django_apps.get_model(registry["app_label"], registry["model_name"])
        for field in model._meta.concrete_fields:
            if not field.editable or field.primary_key:
                continue
            if field.name == "password":
                orm_required.add("password")
                continue
            if not field.blank and not field.null:
                orm_required.add(field.name)

    fields: list[dict[str, Any]] = []
    seen: set[str] = set()
    for col in columns:
        if col in {pk, "password_set"} or col in seen:
            continue
        seen.add(col)
        info = meta.get(col, {})
        if source == "orm":
            is_required = col in orm_required
        else:
            is_required = (
                not bool(info.get("nullable", True))
                and info.get("default") is None
                and not bool(info.get("primary_key", False))
            )
        fields.append(
            {
                "name": col,
                "label": col,
                "required": is_required,
                "input_type": "text",
            }
        )

    if (
        source == "orm"
        and isinstance(registry, dict)
        and str(registry.get("app_label")) == "auth"
        and str(registry.get("model_name")) == "user"
        and "password" not in seen
    ):
        # password n'apparait pas dans les colonnes (expose comme password_set).
        insert_at = next(
            (i for i, item in enumerate(fields) if item["name"] == "username"),
            -1,
        )
        password_field = {
            "name": "password",
            "label": "password",
            "required": True,
            "input_type": "password",
        }
        if insert_at >= 0:
            fields.insert(insert_at + 1, password_field)
        else:
            fields.append(password_field)
    return fields


def _table_panel_context(request: HttpRequest, table_name: str) -> dict[str, Any]:
    safe_name = _require_valid_table_name(table_name)
    try:
        data = services.list_table_rows(safe_name, actor=request.user)
    except AdminDmlError as exc:
        raise Http404("Table introuvable.") from exc
    display_rows, pk = _build_display_rows(data)
    overview = _safe_overview()
    match = next((t for t in overview["tables"] if t["name"] == safe_name), None)
    structure_columns = list(match["columns"]) if match else []
    return {
        "table_name": safe_name,
        "columns": list(data.get("columns") or []),
        "display_rows": display_rows,
        "pk": pk,
        "source": data.get("source", "sql"),
        "structure_columns": structure_columns,
        "insert_fields": _build_insert_fields(data, structure_columns, pk),
        "can_ddl": not is_ddl_table_blacklisted(safe_name),
        "tables": overview["tables"],
        "foreign_keys": overview["foreign_keys"],
        "selected_table": safe_name,
    }


def _admin_context(request: HttpRequest, selected: str | None = None) -> dict[str, Any]:
    overview = _safe_overview()
    tables = overview["tables"]
    assert isinstance(tables, list)
    selected_table = selected or (tables[0]["name"] if tables else None)
    ctx: dict[str, Any] = {
        "tab": "admin",
        "tables": tables,
        "foreign_keys": overview["foreign_keys"],
        "selected_table": selected_table,
        "mermaid": selectors.export_schema_mermaid_body(),
        "stats": selectors.get_console_welcome_stats(),
    }
    if selected_table:
        ctx.update(_table_panel_context(request, str(selected_table)))
    return ctx


def _flash(request: HttpRequest, message: str, *, level: str = "success") -> str:
    return render(
        request,
        "console/partials/_flash.html",
        {"message": message, "level": level},
    ).content.decode("utf-8")


class ConsoleShellView(SuperuserRequiredMixin, TemplateView):
    """Shell Console (Welcome | Admin).

    MRO:
    1. SuperuserRequiredMixin.dispatch
    2. TemplateView.get -> shell ou partial HTMX
    """

    template_name = "console/shell.html"

    def get_template_names(self) -> list[str]:
        if getattr(self.request, "htmx", False) and self.request.htmx:
            tab = (self.request.GET.get("tab") or "welcome").strip()
            if tab == "admin":
                return ["console/partials/_admin.html"]
            return ["console/partials/_welcome.html"]
        return [self.template_name]

    def get_context_data(self, **kwargs: object) -> dict[str, object]:
        context = super().get_context_data(**kwargs)
        tab = (self.request.GET.get("tab") or "welcome").strip()
        if tab == "admin":
            context.update(_admin_context(self.request))
        else:
            context["tab"] = "welcome"
            context["stats"] = selectors.get_console_welcome_stats()
        return context


class ConsoleAdminPartialView(SuperuserRequiredMixin, TemplateView):
    """Partial Admin (Donnees / Schema / Query / Diagram).

    MRO:
    1. SuperuserRequiredMixin.dispatch
    2. TemplateView.get -> _admin.html
    """

    template_name = "console/partials/_admin.html"

    def get_context_data(self, **kwargs: object) -> dict[str, object]:
        context = super().get_context_data(**kwargs)
        context.update(_admin_context(self.request))
        return context


class ConsoleTablePanelView(SuperuserRequiredMixin, TemplateView):
    """Panneau editeur + structure pour une table.

    MRO:
    1. SuperuserRequiredMixin.dispatch
    2. TemplateView.get -> _table_editor.html
    """

    template_name = "console/partials/_table_editor.html"

    def get_context_data(self, **kwargs: object) -> dict[str, object]:
        context = super().get_context_data(**kwargs)
        table_name = str(self.kwargs["table"])
        context.update(_table_panel_context(self.request, table_name))
        return context


class ConsoleCellUpdateView(SuperuserRequiredMixin, View):
    """POST mise a jour cellule.

    MRO:
    1. SuperuserRequiredMixin.dispatch
    2. View.post -> services.update_table_cell + panel
    """

    def post(self, request: HttpRequest, table: str) -> HttpResponse:
        table = _require_valid_table_name(table)
        try:
            services.update_table_cell(
                table,
                primary_key=request.POST.get("primary_key", ""),
                primary_key_value=request.POST.get("primary_key_value", ""),
                column=request.POST.get("column", ""),
                value=request.POST.get("value"),
                actor=request.user,
            )
            msg = "Cellule mise a jour."
            level = "success"
        except (AdminDmlError, AdminDdlError, AdminModelValidationError, ValueError) as exc:
            msg = str(exc)
            level = "error"
        response = render(request, "console/partials/_table_editor.html", _table_panel_context(request, table))
        response.content = _flash(request, msg, level=level).encode("utf-8") + response.content
        return response


class ConsoleRowInsertView(SuperuserRequiredMixin, View):
    """POST insertion ligne.

    MRO:
    1. SuperuserRequiredMixin.dispatch
    2. View.post -> services.insert_table_row
    """

    def post(self, request: HttpRequest, table: str) -> HttpResponse:
        table = _require_valid_table_name(table)
        payload: dict[str, object] = {}
        for key, value in request.POST.items():
            if key.startswith("field__"):
                payload[key.removeprefix("field__")] = value
        try:
            services.insert_table_row(table, payload, actor=request.user)
            msg, level = "Ligne creee.", "success"
        except (AdminDmlError, AdminDdlError, AdminModelValidationError, ValueError) as exc:
            msg, level = str(exc), "error"
        response = render(request, "console/partials/_table_editor.html", _table_panel_context(request, table))
        response.content = _flash(request, msg, level=level).encode("utf-8") + response.content
        return response


class ConsoleRowDeleteView(SuperuserRequiredMixin, View):
    """POST suppression ligne.

    MRO:
    1. SuperuserRequiredMixin.dispatch
    2. View.post -> services.delete_table_row
    """

    def post(self, request: HttpRequest, table: str) -> HttpResponse:
        table = _require_valid_table_name(table)
        try:
            services.delete_table_row(
                table,
                primary_key=request.POST.get("primary_key", ""),
                primary_key_value=request.POST.get("primary_key_value", ""),
                actor=request.user,
            )
            msg, level = "Ligne supprimee.", "success"
        except (AdminDmlError, AdminDdlError, ValueError) as exc:
            msg, level = str(exc), "error"
        response = render(request, "console/partials/_table_editor.html", _table_panel_context(request, table))
        response.content = _flash(request, msg, level=level).encode("utf-8") + response.content
        return response


class ConsoleColumnAddView(SuperuserRequiredMixin, View):
    """POST ADD COLUMN.

    MRO: SuperuserRequiredMixin -> View.post -> services.add_column
    """

    def post(self, request: HttpRequest, table: str) -> HttpResponse:
        table = _require_valid_table_name(table)
        try:
            services.add_column(
                table,
                request.POST.get("name", ""),
                request.POST.get("pg_type", "text"),
                nullable=request.POST.get("nullable", "1") == "1",
                actor=request.user,
            )
            msg, level = "Colonne ajoutee.", "success"
        except AdminDdlError as exc:
            msg, level = str(exc), "error"
        response = render(request, "console/partials/_table_editor.html", _table_panel_context(request, table))
        response.content = _flash(request, msg, level=level).encode("utf-8") + response.content
        return response


class ConsoleColumnRenameView(SuperuserRequiredMixin, View):
    """POST RENAME COLUMN.

    MRO: SuperuserRequiredMixin -> View.post -> services.rename_column
    """

    def post(self, request: HttpRequest, table: str) -> HttpResponse:
        table = _require_valid_table_name(table)
        try:
            services.rename_column(
                table,
                request.POST.get("old_name", ""),
                request.POST.get("new_name", ""),
                actor=request.user,
            )
            msg, level = "Colonne renommee.", "success"
        except AdminDdlError as exc:
            msg, level = str(exc), "error"
        response = render(request, "console/partials/_table_editor.html", _table_panel_context(request, table))
        response.content = _flash(request, msg, level=level).encode("utf-8") + response.content
        return response


class ConsoleColumnDropView(SuperuserRequiredMixin, View):
    """POST DROP COLUMN.

    MRO: SuperuserRequiredMixin -> View.post -> services.drop_column
    """

    def post(self, request: HttpRequest, table: str) -> HttpResponse:
        table = _require_valid_table_name(table)
        try:
            services.drop_column(table, request.POST.get("column", ""), actor=request.user)
            msg, level = "Colonne supprimee.", "success"
        except AdminDdlError as exc:
            msg, level = str(exc), "error"
        response = render(request, "console/partials/_table_editor.html", _table_panel_context(request, table))
        response.content = _flash(request, msg, level=level).encode("utf-8") + response.content
        return response


class ConsoleTableCreateView(SuperuserRequiredMixin, View):
    """POST CREATE TABLE (formulaire minimal 2 colonnes).

    MRO: SuperuserRequiredMixin -> View.post -> services.create_table
    """

    def post(self, request: HttpRequest) -> HttpResponse:
        name = request.POST.get("name", "").strip()
        columns = [
            {
                "name": request.POST.get("pk_name", "id"),
                "type": request.POST.get("pk_type", "serial"),
                "nullable": False,
                "primary_key": True,
            },
        ]
        col2 = request.POST.get("col2_name", "").strip()
        if col2:
            columns.append(
                {
                    "name": col2,
                    "type": request.POST.get("col2_type", "text"),
                    "nullable": True,
                    "primary_key": False,
                }
            )
        try:
            services.create_table(name, columns, actor=request.user)
        except AdminDdlError as exc:
            ctx = _admin_context(request)
            ctx["flash_error"] = str(exc)
            return render(request, "console/partials/_admin.html", ctx)
        return render(request, "console/partials/_admin.html", _admin_context(request, selected=name))


class ConsoleTableDropView(SuperuserRequiredMixin, View):
    """POST DROP TABLE (confirm_name obligatoire cote serveur).

    MRO: SuperuserRequiredMixin -> View.post -> services.drop_table
    """

    def post(self, request: HttpRequest) -> HttpResponse:
        name = request.POST.get("name", "").strip()
        confirm_name = request.POST.get("confirm_name", "").strip()
        try:
            services.drop_table(name, confirm_name=confirm_name, actor=request.user)
        except AdminDdlError as exc:
            ctx = _admin_context(request)
            ctx["flash_error"] = str(exc)
            return render(request, "console/partials/_admin.html", ctx)
        return render(request, "console/partials/_admin.html", _admin_context(request))


class ConsoleQueryView(SuperuserRequiredMixin, View):
    """POST query SELECT readonly.

    MRO: SuperuserRequiredMixin -> View.post -> selectors.execute_readonly_query
    """

    def post(self, request: HttpRequest) -> HttpResponse:
        sql = request.POST.get("sql", "")
        try:
            result = selectors.execute_readonly_query(sql)
            columns = list(result.get("columns") or [])
            display_rows = []
            for raw in result.get("rows") or []:
                assert isinstance(raw, dict)
                row_cells = []
                for col in columns:
                    val = raw.get(col)
                    is_null = val is None
                    row_cells.append(
                        {
                            "display": "" if is_null else str(val),
                            "is_null": is_null,
                        }
                    )
                display_rows.append(row_cells)
            return render(
                request,
                "console/partials/_query_result.html",
                {
                    "columns": columns,
                    "display_rows": display_rows,
                    "row_count": result.get("row_count", 0),
                    "elapsed_ms": result.get("elapsed_ms", 0),
                    "truncated": result.get("truncated", False),
                },
            )
        except selectors.AdminQueryError as exc:
            return render(
                request,
                "console/partials/_query_result.html",
                {"error": str(exc)},
            )