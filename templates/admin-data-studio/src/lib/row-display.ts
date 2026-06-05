import type { StudioColumn, StudioRow } from "@/lib/admin-studio-types";

const PASSWORD_MASK = "••••••••";

export function isPasswordColumn(col: StudioColumn): boolean {
  return col.name === "password";
}

export function passwordIsConfigured(row: StudioRow): boolean {
  return row.password_set === true;
}

export function formatGridCellValue(col: StudioColumn, row: StudioRow): string {
  if (isPasswordColumn(col)) {
    return passwordIsConfigured(row) ? PASSWORD_MASK : "NULL";
  }
  const val = row[col.name];
  if (val == null) {
    return "NULL";
  }
  if (typeof val === "boolean") {
    return String(val);
  }
  return String(val).slice(0, 80);
}

export function prepareEditRow(row: StudioRow): StudioRow {
  const next: StudioRow = { ...row, password: "" };
  return next;
}

export function prepareSubmitPayload(
  formData: StudioRow,
  mode: "create" | "edit",
): Record<string, unknown> {
  const payload: Record<string, unknown> = { ...formData };
  delete payload.password_set;
  if (mode === "edit") {
    const pwd = payload.password;
    if (pwd == null || pwd === "") {
      delete payload.password;
    }
  }
  return payload;
}
