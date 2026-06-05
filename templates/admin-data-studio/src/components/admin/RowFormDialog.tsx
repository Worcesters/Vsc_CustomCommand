"use client";

import type { StudioColumn, StudioRow } from "@/lib/admin-studio-types";

type RowFormDialogProps = {
  title: string;
  columns: StudioColumn[];
  formData: StudioRow;
  pkField?: string;
  mode: "create" | "edit";
  open: boolean;
  saving: boolean;
  onClose: () => void;
  onChange: (data: StudioRow) => void;
  onSubmit: () => void;
};

function inputTypeForColumn(col: StudioColumn): string {
  if (col.type === "boolean") return "checkbox";
  if (col.type.includes("int") || col.type === "decimal" || col.type === "serial") {
    return "number";
  }
  if (col.type === "timestamp" || col.type === "date") return "datetime-local";
  if (col.type === "text" || col.type === "jsonb") return "textarea";
  return "text";
}

export function RowFormDialog({
  title,
  columns,
  formData,
  pkField,
  mode,
  open,
  saving,
  onClose,
  onChange,
  onSubmit,
}: RowFormDialogProps) {
  if (!open) return null;

  const formColumns = columns.filter((col) => col.editable !== false);

  return (
    <div className="ds-modal" role="dialog" aria-modal="true" aria-labelledby="ds-modal-title">
      <button type="button" className="ds-modal__backdrop" onClick={onClose} aria-label="Fermer" />
      <div className="ds-modal__panel">
        <header className="ds-modal__header">
          <h3 id="ds-modal-title">{title}</h3>
          <button type="button" className="ds-btn ds-btn--ghost ds-btn--icon" onClick={onClose}>
            ×
          </button>
        </header>
        <div className="ds-modal__body">
          {formColumns.map((col) => {
            const isPk = col.primaryKey || col.name === pkField;
            const disabled = mode === "edit" && isPk;
            const inputType = inputTypeForColumn(col);
            const value = formData[col.name];

            if (inputType === "checkbox") {
              return (
                <label key={col.name} className="ds-modal__field ds-modal__field--row">
                  <input
                    type="checkbox"
                    checked={Boolean(value)}
                    disabled={disabled}
                    onChange={(e) =>
                      onChange({ ...formData, [col.name]: e.target.checked })
                    }
                  />
                  <span>
                    {col.name} <span className="shell__muted">({col.type})</span>
                  </span>
                </label>
              );
            }

            if (inputType === "textarea") {
              return (
                <label key={col.name} className="ds-modal__field">
                  <span className="ds-modal__label">
                    {col.name} <span className="shell__muted">({col.type})</span>
                  </span>
                  <textarea
                    className="data-studio__search"
                    rows={3}
                    disabled={disabled}
                    value={value == null ? "" : String(value)}
                    onChange={(e) =>
                      onChange({ ...formData, [col.name]: e.target.value || null })
                    }
                  />
                </label>
              );
            }

            return (
              <label key={col.name} className="ds-modal__field">
                <span className="ds-modal__label">
                  {col.name} <span className="shell__muted">({col.type})</span>
                </span>
                <input
                  className="data-studio__search"
                  type={inputType}
                  disabled={disabled}
                  value={value == null ? "" : String(value)}
                  onChange={(e) =>
                    onChange({
                      ...formData,
                      [col.name]:
                        inputType === "number"
                          ? e.target.value === ""
                            ? null
                            : Number(e.target.value)
                          : e.target.value,
                    })
                  }
                />
              </label>
            );
          })}
        </div>
        <footer className="ds-modal__footer">
          <button type="button" className="ds-btn ds-btn--ghost" onClick={onClose}>
            Annuler
          </button>
          <button
            type="button"
            className="ds-btn ds-btn--primary"
            disabled={saving}
            onClick={onSubmit}
          >
            {saving ? "Enregistrement..." : "Enregistrer"}
          </button>
        </footer>
      </div>
    </div>
  );
}
