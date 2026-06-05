import type { StudioColumn, StudioRow } from "@/lib/admin-studio-types";

export type FieldErrors = Record<string, string>;

export function isColumnRequired(
  col: StudioColumn,
  mode: "create" | "edit",
): boolean {
  if (col.editable === false) {
    return false;
  }
  if (mode === "create" && (col.primaryKey || col.autoIncrement)) {
    return false;
  }
  if (mode === "create" && col.requiredOnCreate) {
    return true;
  }
  if (mode === "edit" && col.name === "password") {
    return false;
  }
  return Boolean(col.required);
}

export function validateStudioForm(
  columns: StudioColumn[],
  formData: StudioRow,
  mode: "create" | "edit",
): FieldErrors {
  const errors: FieldErrors = {};

  for (const col of columns) {
    if (!isColumnRequired(col, mode)) {
      continue;
    }
    const value = formData[col.name];
    const empty =
      col.type === "boolean"
        ? value == null
        : value == null || value === "";
    if (empty) {
      errors[col.name] = "Ce champ est obligatoire.";
    }
  }

  return errors;
}

export function columnsForForm(
  columns: StudioColumn[],
  mode: "create" | "edit",
): StudioColumn[] {
  return columns.filter((col) => {
    if (col.editable === false) {
      return false;
    }
    if (mode === "create" && (col.primaryKey || col.autoIncrement)) {
      return false;
    }
    return true;
  });
}

export function hasAutoIncrementPk(columns: StudioColumn[]): boolean {
  return columns.some((col) => col.primaryKey && col.autoIncrement);
}
