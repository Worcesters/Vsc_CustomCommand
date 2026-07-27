from django.urls import path

from apps.admin_panel import views

app_name = "admin_panel"

urlpatterns = [
    path("", views.ConsoleShellView.as_view(), name="console_shell"),
    path("admin/", views.ConsoleAdminPartialView.as_view(), name="console_admin"),
    path("tables/<str:table>/", views.ConsoleTablePanelView.as_view(), name="console_table"),
    path("tables/<str:table>/cell/", views.ConsoleCellUpdateView.as_view(), name="console_cell_update"),
    path("tables/<str:table>/rows/", views.ConsoleRowInsertView.as_view(), name="console_row_insert"),
    path("tables/<str:table>/rows/delete/", views.ConsoleRowDeleteView.as_view(), name="console_row_delete"),
    path("tables/<str:table>/columns/add/", views.ConsoleColumnAddView.as_view(), name="console_column_add"),
    path("tables/<str:table>/columns/rename/", views.ConsoleColumnRenameView.as_view(), name="console_column_rename"),
    path("tables/<str:table>/columns/drop/", views.ConsoleColumnDropView.as_view(), name="console_column_drop"),
    path("ddl/create-table/", views.ConsoleTableCreateView.as_view(), name="console_table_create"),
    path("ddl/drop-table/", views.ConsoleTableDropView.as_view(), name="console_table_drop"),
    path("query/", views.ConsoleQueryView.as_view(), name="console_query"),
]