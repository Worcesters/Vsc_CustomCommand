"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import {
  ArrowDown,
  ArrowUp,
  ArrowUpDown,
  ChevronLeft,
  ChevronRight,
  ChevronsLeft,
  ChevronsRight,
  Check,
  Copy,
  Key,
  LinkIcon,
  Pencil,
  Plus,
  RefreshCw,
  Search,
  Trash2,
} from "lucide-react";
import {
  createModelRow,
  deleteModelRow,
  fetchModelRows,
  updateModelRow,
} from "@/lib/admin-api";
import { RowFormDialog } from "@/components/admin/RowFormDialog";
import type { StudioRow, StudioTable } from "@/lib/admin-studio-types";

type AdminDataTableProps = {
  table: StudioTable;
  onRowCount?: (count: number) => void;
};

const PAGE_SIZE = 10;

function emptyRow(table: StudioTable): StudioRow {
  const row: StudioRow = {};
  table.columns.forEach((col) => {
    row[col.name] = col.type === "boolean" ? false : null;
  });
  return row;
}

export function AdminDataTable({ table, onRowCount }: AdminDataTableProps) {
  const [data, setData] = useState<StudioRow[]>([]);
  const [pkField, setPkField] = useState("id");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [searchTerm, setSearchTerm] = useState("");
  const [sortColumn, setSortColumn] = useState<string | null>(null);
  const [sortDir, setSortDir] = useState<"asc" | "desc">("asc");
  const [page, setPage] = useState(1);
  const [copied, setCopied] = useState<string | null>(null);
  const [selected, setSelected] = useState<Set<number>>(new Set());
  const [formOpen, setFormOpen] = useState<"create" | "edit" | null>(null);
  const [deleteOpen, setDeleteOpen] = useState(false);
  const [activeRow, setActiveRow] = useState<StudioRow | null>(null);
  const [formData, setFormData] = useState<StudioRow>({});

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await fetchModelRows(table.appLabel, table.modelName);
      setData(res.results ?? []);
      setPkField(res.pk_field ?? "id");
      onRowCount?.(res.count ?? res.results?.length ?? 0);
    } catch {
      setData([]);
      onRowCount?.(0);
    } finally {
      setLoading(false);
    }
  }, [table.appLabel, table.modelName, onRowCount]);

  useEffect(() => {
    void load();
    setSelected(new Set());
    setPage(1);
  }, [load, table.id]);

  const filtered = useMemo(() => {
    let rows = [...data];
    if (searchTerm) {
      const q = searchTerm.toLowerCase();
      rows = rows.filter((row) =>
        Object.values(row).some((v) => String(v ?? "").toLowerCase().includes(q)),
      );
    }
    if (sortColumn) {
      rows.sort((a, b) => {
        const av = a[sortColumn];
        const bv = b[sortColumn];
        if (av == null) return 1;
        if (bv == null) return -1;
        const c = String(av).localeCompare(String(bv), undefined, { numeric: true });
        return sortDir === "asc" ? c : -c;
      });
    }
    return rows;
  }, [data, searchTerm, sortColumn, sortDir]);

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const pageRows = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

  const globalIndex = (rowIndex: number) => (page - 1) * PAGE_SIZE + rowIndex;

  const toggleSort = (col: string) => {
    if (sortColumn === col) {
      setSortDir(sortDir === "asc" ? "desc" : "asc");
    } else {
      setSortColumn(col);
      setSortDir("asc");
    }
  };

  const copyCell = async (key: string, value: unknown) => {
    await navigator.clipboard.writeText(value == null ? "NULL" : String(value));
    setCopied(key);
    setTimeout(() => setCopied(null), 2000);
  };

  const openCreate = () => {
    setFormData(emptyRow(table));
    setActiveRow(null);
    setFormOpen("create");
  };

  const openEdit = (row: StudioRow) => {
    setActiveRow(row);
    setFormData({ ...row });
    setFormOpen("edit");
  };

  const openDelete = (row: StudioRow) => {
    setActiveRow(row);
    setDeleteOpen(true);
  };

  const submitForm = async () => {
    setSaving(true);
    try {
      if (formOpen === "create") {
        await createModelRow(table.appLabel, table.modelName, formData);
      } else if (formOpen === "edit" && activeRow) {
        const pk = activeRow[pkField];
        if (pk == null) throw new Error("PK manquante");
        await updateModelRow(table.appLabel, table.modelName, String(pk), formData);
      }
      setFormOpen(null);
      await load();
    } catch (err) {
      alert(err instanceof Error ? err.message : "Erreur enregistrement");
    } finally {
      setSaving(false);
    }
  };

  const confirmDelete = async () => {
    if (!activeRow) return;
    const pk = activeRow[pkField];
    if (pk == null) return;
    setSaving(true);
    try {
      await deleteModelRow(table.appLabel, table.modelName, String(pk));
      setDeleteOpen(false);
      await load();
    } catch (err) {
      alert(err instanceof Error ? err.message : "Erreur suppression");
    } finally {
      setSaving(false);
    }
  };

  const deleteSelected = async () => {
    const indices = [...selected];
    setSaving(true);
    try {
      for (const idx of indices) {
        const row = filtered[idx];
        if (!row) continue;
        const pk = row[pkField];
        if (pk != null) {
          await deleteModelRow(table.appLabel, table.modelName, String(pk));
        }
      }
      setSelected(new Set());
      await load();
    } catch (err) {
      alert(err instanceof Error ? err.message : "Erreur suppression");
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="ds-grid" style={{ display: "flex", flexDirection: "column", height: "100%" }}>
      <div className="ds-grid-toolbar">
        <div className="data-studio__search-wrap ds-grid-search" style={{ padding: 0, border: 0 }}>
          <Search className="data-studio__search-icon" size={16} />
          <input
            className="data-studio__search"
            placeholder="Rechercher dans les lignes..."
            value={searchTerm}
            onChange={(e) => {
              setSearchTerm(e.target.value);
              setPage(1);
            }}
          />
        </div>
        <button type="button" className="ds-btn ds-btn--ghost" onClick={() => void load()}>
          <RefreshCw size={16} />
          Actualiser
        </button>
        {selected.size > 0 ? (
          <button type="button" className="ds-btn" style={{ borderColor: "var(--ds-danger)", color: "var(--ds-danger)" }} onClick={() => void deleteSelected()}>
            <Trash2 size={16} />
            Supprimer ({selected.size})
          </button>
        ) : null}
        <button type="button" className="ds-btn ds-btn--primary" onClick={openCreate}>
          <Plus size={16} />
          Ajouter
        </button>
      </div>

      <div className="ds-grid-table-wrap">
        {loading ? (
          <p className="shell__muted" style={{ padding: "1rem" }}>
            Chargement...
          </p>
        ) : (
          <table className="ds-grid-table">
            <thead>
              <tr>
                <th style={{ width: 40 }}>
                  <input
                    type="checkbox"
                    checked={
                      pageRows.length > 0 &&
                      pageRows.every((_, ri) => selected.has(globalIndex(ri)))
                    }
                    onChange={(e) => {
                      const next = new Set(selected);
                      pageRows.forEach((_, ri) => {
                        const gi = globalIndex(ri);
                        if (e.target.checked) next.add(gi);
                        else next.delete(gi);
                      });
                      setSelected(next);
                    }}
                  />
                </th>
                {table.columns.map((col) => (
                  <th key={col.name} onClick={() => toggleSort(col.name)}>
                    <span style={{ display: "inline-flex", alignItems: "center", gap: 4 }}>
                      {col.primaryKey ? <Key size={12} color="#eab308" /> : null}
                      {col.foreignKey ? <LinkIcon size={12} color="#60a5fa" /> : null}
                      {col.name}
                      {sortColumn === col.name ? (
                        sortDir === "asc" ? <ArrowUp size={12} /> : <ArrowDown size={12} />
                      ) : (
                        <ArrowUpDown size={12} opacity={0.4} />
                      )}
                    </span>
                  </th>
                ))}
                <th style={{ width: 48 }} />
              </tr>
            </thead>
            <tbody>
              {pageRows.length === 0 ? (
                <tr>
                  <td colSpan={table.columns.length + 2} className="ds-null">
                    Aucune ligne
                  </td>
                </tr>
              ) : (
                pageRows.map((row, ri) => {
                  const gi = globalIndex(ri);
                  return (
                    <tr key={gi} className={selected.has(gi) ? "ds-grid-row--selected" : ""}>
                      <td>
                        <input
                          type="checkbox"
                          checked={selected.has(gi)}
                          onChange={(e) => {
                            const next = new Set(selected);
                            if (e.target.checked) next.add(gi);
                            else next.delete(gi);
                            setSelected(next);
                          }}
                        />
                      </td>
                      {table.columns.map((col) => {
                        const val = row[col.name];
                        const cellKey = `${gi}-${col.name}`;
                        return (
                          <td
                            key={col.name}
                            onDoubleClick={() => void copyCell(cellKey, val)}
                            title="Double-clic pour copier"
                          >
                            {val == null ? (
                              <span className="ds-null">NULL</span>
                            ) : typeof val === "boolean" ? (
                              <span className="schema-relations__badge">{String(val)}</span>
                            ) : (
                              String(val).slice(0, 80)
                            )}
                            {copied === cellKey ? <Check size={12} style={{ marginLeft: 4 }} /> : null}
                          </td>
                        );
                      })}
                      <td>
                        <div style={{ display: "flex", gap: 4 }}>
                          <button type="button" className="ds-btn ds-btn--icon" onClick={() => openEdit(row)} title="Modifier">
                            <Pencil size={14} />
                          </button>
                          <button type="button" className="ds-btn ds-btn--icon" onClick={() => openDelete(row)} title="Supprimer">
                            <Trash2 size={14} />
                          </button>
                        </div>
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        )}
      </div>

      <div className="ds-grid-footer">
        <span>
          {filtered.length} ligne(s) · page {page}/{totalPages}
        </span>
        <div style={{ display: "flex", gap: "0.25rem" }}>
          <button type="button" className="ds-btn ds-btn--icon" disabled={page <= 1} onClick={() => setPage(1)}>
            <ChevronsLeft size={16} />
          </button>
          <button type="button" className="ds-btn ds-btn--icon" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>
            <ChevronLeft size={16} />
          </button>
          <button type="button" className="ds-btn ds-btn--icon" disabled={page >= totalPages} onClick={() => setPage((p) => p + 1)}>
            <ChevronRight size={16} />
          </button>
          <button type="button" className="ds-btn ds-btn--icon" disabled={page >= totalPages} onClick={() => setPage(totalPages)}>
            <ChevronsRight size={16} />
          </button>
        </div>
      </div>

      <RowFormDialog
        title={formOpen === "create" ? `Ajouter — ${table.name}` : `Modifier — ${table.name}`}
        columns={table.columns}
        formData={formData}
        pkField={pkField}
        mode={formOpen === "create" ? "create" : "edit"}
        open={formOpen !== null}
        saving={saving}
        onClose={() => setFormOpen(null)}
        onChange={setFormData}
        onSubmit={() => void submitForm()}
      />

      {deleteOpen ? (
        <div className="ds-modal" role="alertdialog">
          <button type="button" className="ds-modal__backdrop" onClick={() => setDeleteOpen(false)} />
          <div className="ds-modal__panel ds-modal__panel--sm">
            <header className="ds-modal__header">
              <h3>Supprimer la ligne ?</h3>
            </header>
            <p className="shell__muted" style={{ padding: "0 1rem 1rem" }}>
              Action irreversible sur {table.schema}.{table.name}.
            </p>
            <footer className="ds-modal__footer">
              <button type="button" className="ds-btn ds-btn--ghost" onClick={() => setDeleteOpen(false)}>
                Annuler
              </button>
              <button type="button" className="ds-btn" style={{ background: "var(--ds-danger)", color: "#fff", borderColor: "var(--ds-danger)" }} disabled={saving} onClick={() => void confirmDelete()}>
                Supprimer
              </button>
            </footer>
          </div>
        </div>
      ) : null}
    </div>
  );
}
