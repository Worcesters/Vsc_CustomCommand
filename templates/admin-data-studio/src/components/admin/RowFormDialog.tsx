"use client";

import type { FieldErrors } from "@/lib/form-validation";
import {
  columnsForForm,
  hasAutoIncrementPk,
  isColumnRequired,
} from "@/lib/form-validation";
import { passwordIsConfigured } from "@/lib/row-display";
import type { StudioColumn, StudioRow } from "@/lib/admin-studio-types";

type RowFormDialogProps = {
  title: string;
  columns: StudioColumn[];
  formData: StudioRow;
  pkField?: string;
  mode: "create" | "edit";
  open: boolean;
  saving: boolean;
  fieldErrors: FieldErrors;
  formError?: string;
  onClose: () => void;
  onChange: (data: StudioRow) => void;
  onSubmit: () => void;
};

function inputTypeForColumn(col: StudioColumn): string {
  if (col.name === "password") return "password";
  if (col.type === "boolean") return "checkbox";
  if (col.type.includes("int") || col.type === "decimal" || col.type === "serial") {
    return "number";
  }
  if (col.type === "timestamp" || col.type === "date") return "datetime-local";
  if (col.type === "text" || col.type === "jsonb") return "textarea";
  return "text";
}

function fieldLabel(col: StudioColumn): string {
  return col.name;
}

export function RowFormDialog({
  title,
  columns,
  formData,
  pkField,
  mode,
  open,
  saving,
  fieldErrors,
  formError,
  onClose,
  onChange,
  onSubmit,
}: RowFormDialogProps) {
  if (!open) return null;

  const formColumns = columnsForForm(columns, mode);
  const showPkHint = mode === "create" && hasAutoIncrementPk(columns);

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
          <p className="ds-modal__legend">
            Les champs marques <span className="ds-modal__label-required">*</span> sont
            obligatoires.
            {showPkHint ? (
              <>
                {" "}
                L&apos;identifiant (<code>{pkField ?? "id"}</code>) est genere automatiquement.
              </>
            ) : null}
          </p>
          {formError ? (
            <div className="ds-modal__banner ds-modal__banner--error" role="alert">
              {formError}
            </div>
          ) : null}
          {formColumns.map((col) => {
            const isPk = col.primaryKey || col.name === pkField;
            const disabled = mode === "edit" && isPk;
            const inputType = inputTypeForColumn(col);
            const value = formData[col.name];
            const required = isColumnRequired(col, mode);
            const error = fieldErrors[col.name];
            const fieldClass = `ds-modal__field${error ? " ds-modal__field--invalid" : ""}`;

            if (inputType === "checkbox") {
              return (
                <label key={col.name} className={`${fieldClass} ds-modal__field--row`}>
                  <input
                    type="checkbox"
                    checked={Boolean(value)}
                    disabled={disabled}
                    aria-invalid={Boolean(error)}
                    onChange={(e) =>
                      onChange({ ...formData, [col.name]: e.target.checked })
                    }
                  />
                  <span>
                    {fieldLabel(col)}
                    {required ? <span className="ds-modal__label-required"> *</span> : null}
                    <span className="shell__muted"> ({col.type})</span>
                  </span>
                  {error ? <span className="ds-modal__field-error">{error}</span> : null}
                </label>
              );
            }

            if (inputType === "textarea") {
              return (
                <label key={col.name} className={fieldClass}>
                  <span className="ds-modal__label">
                    {fieldLabel(col)}
                    {required ? <span className="ds-modal__label-required"> *</span> : null}
                    <span className="shell__muted"> ({col.type})</span>
                  </span>
                  <textarea
                    className="data-studio__search"
                    rows={3}
                    disabled={disabled}
                    aria-invalid={Boolean(error)}
                    value={value == null ? "" : String(value)}
                    onChange={(e) =>
                      onChange({ ...formData, [col.name]: e.target.value || null })
                    }
                  />
                  {error ? <span className="ds-modal__field-error">{error}</span> : null}
                </label>
              );
            }

            return (
              <label key={col.name} className={fieldClass}>
                <span className="ds-modal__label">
                  {fieldLabel(col)}
                  {required ? <span className="ds-modal__label-required"> *</span> : null}
                  <span className="shell__muted"> ({col.type})</span>
                  {mode === "edit" && col.name === "password" ? (
                    <span className="ds-modal__hint">
                      {passwordIsConfigured(formData)
                        ? " — mot de passe defini, laisser vide pour conserver"
                        : " — laisser vide pour ne pas changer"}
                    </span>
                  ) : null}
                </span>
                <input
                  className="data-studio__search"
                  type={inputType}
                  disabled={disabled}
                  aria-invalid={Boolean(error)}
                  placeholder={
                    mode === "edit" && col.name === "password" && passwordIsConfigured(formData)
                      ? "Mot de passe defini (non affiche)"
                      : undefined
                  }
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
                {error ? <span className="ds-modal__field-error">{error}</span> : null}
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
