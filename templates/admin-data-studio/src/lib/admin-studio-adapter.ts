import type { ModelSchema } from "@/lib/schema-types";
import type { RegistryEntry } from "@/lib/admin-api-types";
import type { StudioColumn, StudioTable } from "@/lib/admin-studio-types";

function djangoTypeToSql(typeName: string): string {
  const map: Record<string, string> = {
    AutoField: "serial",
    BigAutoField: "bigserial",
    CharField: "varchar",
    TextField: "text",
    IntegerField: "integer",
    BigIntegerField: "bigint",
    BooleanField: "boolean",
    DateTimeField: "timestamp",
    DateField: "date",
    DecimalField: "decimal",
    ForeignKey: "integer",
    OneToOneField: "integer",
    ManyToManyField: "m2m",
    UUIDField: "uuid",
    JSONField: "jsonb",
  };
  return map[typeName] ?? typeName.toLowerCase();
}

export function buildStudioTables(
  registry: RegistryEntry[],
  schemas: ModelSchema[],
): StudioTable[] {
  const byId = new Map(schemas.map((s) => [`${s.app_label}.${s.model_name}`, s]));
  return registry.map((entry) => {
    const id = `${entry.app_label}.${entry.model_name}`;
    const schema = byId.get(id);
    const columns: StudioColumn[] = (schema?.fields ?? []).map((field) => {
      const isAutoPk =
        field.type === "AutoField" || field.type === "BigAutoField";
      const col: StudioColumn = {
        name: field.name,
        type: djangoTypeToSql(field.type),
        nullable: Boolean(field.nullable),
        blank: Boolean(field.blank),
        primaryKey: Boolean(field.primary_key) || isAutoPk,
        autoIncrement: Boolean(field.auto_increment) || isAutoPk,
        editable: field.editable !== false,
        requiredOnCreate: Boolean(field.required_on_create),
        required:
          Boolean(field.required_on_create) ||
          (!field.blank &&
            field.editable !== false &&
            !field.primary_key &&
            !field.auto_increment),
      };
      if (field.default != null && field.default !== "") {
        col.defaultValue = field.default as string | number | boolean;
      }
      if (field.related_model && field.relation === "FK") {
        const [relApp, relModel] = field.related_model.split(".");
        col.foreignKey = {
          table: relModel ?? field.related_model,
          column: "id",
          targetId: field.related_model,
        };
      }
      return col;
    });
    return {
      id,
      name: entry.model_name,
      schema: entry.app_label,
      appLabel: entry.app_label,
      modelName: entry.model_name,
      columns,
      rowCount: 0,
    };
  });
}

export function parseTableId(tableId: string): { app: string; model: string } | null {
  const dot = tableId.indexOf(".");
  if (dot < 0) return null;
  return { app: tableId.slice(0, dot), model: tableId.slice(dot + 1) };
}
