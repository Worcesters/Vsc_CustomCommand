"use client";

import { useCallback, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import {
  Panel,
  PanelGroup,
  PanelResizeHandle,
} from "react-resizable-panels";
import {
  ChevronDown,
  ChevronRight,
  Database,
  FolderOpen,
  GitBranch,
  History,
  Key,
  Layers,
  LogOut,
  Search,
  Settings,
  Table as TableIcon,
  Terminal,
} from "lucide-react";
import type { GlobalSchema, ModelSchema } from "@/lib/schema-types";
import type { RegistryEntry } from "@/lib/admin-api-types";
import { buildStudioTables } from "@/lib/admin-studio-adapter";
import type { StudioTable, StudioView } from "@/lib/admin-studio-types";
import { AdminDataTable } from "@/components/admin/AdminDataTable";
import { AdminERDiagram } from "@/components/admin/AdminERDiagram";
import { AdminTableDetails } from "@/components/admin/AdminTableDetails";

type DatabaseAdminProps = {
  registry: RegistryEntry[];
  schemas: ModelSchema[];
  global: GlobalSchema;
  apiUrl: string;
};

export function DatabaseAdmin({
  registry,
  schemas,
  global,
  apiUrl,
}: DatabaseAdminProps) {
  const router = useRouter();
  const searchParams = useSearchParams();

  const tables = useMemo(
    () => buildStudioTables(registry, schemas),
    [registry, schemas],
  );

  const initialTableId = searchParams.get("table") ?? tables[0]?.id ?? null;
  const initialView = (searchParams.get("view") as StudioView) || "data";

  const [selectedId, setSelectedId] = useState<string | null>(initialTableId);
  const [activeView, setActiveView] = useState<StudioView>(
    ["data", "structure", "diagram"].includes(initialView) ? initialView : "data",
  );
  const [searchTerm, setSearchTerm] = useState("");
  const [expandedSchemas, setExpandedSchemas] = useState<Set<string>>(() => {
    const s = new Set<string>();
    tables.forEach((t) => s.add(t.schema));
    return s;
  });
  const [rowCounts, setRowCounts] = useState<Record<string, number>>({});

  const handleRowCount = useCallback((tableId: string, count: number) => {
    setRowCounts((prev) => {
      if (prev[tableId] === count) {
        return prev;
      }
      return { ...prev, [tableId]: count };
    });
  }, []);

  const selectedTable = tables.find((t) => t.id === selectedId) ?? null;

  const syncUrl = useCallback(
    (tableId: string | null, view: StudioView) => {
      const params = new URLSearchParams();
      if (tableId) params.set("table", tableId);
      params.set("view", view);
      router.replace(`/admin?${params.toString()}`, { scroll: false });
    },
    [router],
  );

  const selectTable = useCallback(
    (tableId: string, view?: StudioView) => {
      setSelectedId(tableId);
      const v = view ?? activeView;
      syncUrl(tableId, v);
    },
    [activeView, syncUrl],
  );

  const setView = useCallback(
    (view: StudioView) => {
      setActiveView(view);
      if (selectedId) syncUrl(selectedId, view);
    },
    [selectedId, syncUrl],
  );

  const grouped = useMemo(() => {
    const acc: Record<string, StudioTable[]> = {};
    tables.forEach((t) => {
      const q = searchTerm.toLowerCase();
      if (q && !t.name.toLowerCase().includes(q) && !t.id.toLowerCase().includes(q)) {
        return;
      }
      if (!acc[t.schema]) acc[t.schema] = [];
      acc[t.schema].push({
        ...t,
        rowCount: rowCounts[t.id] ?? t.rowCount,
      });
    });
    return acc;
  }, [tables, searchTerm, rowCounts]);

  const handleLogout = async () => {
    await fetch("/api/auth/logout", { method: "POST" });
    router.push("/login");
    router.refresh();
  };

  const toggleSchema = (schema: string) => {
    const next = new Set(expandedSchemas);
    if (next.has(schema)) next.delete(schema);
    else next.add(schema);
    setExpandedSchemas(next);
  };

  return (
    <div className="data-studio">
      <header className="data-studio__header">
        <div className="data-studio__brand">
          <Database size={20} />
          <span>DataStudio</span>
        </div>
        <div className="data-studio__nav">
          <button type="button" className="data-studio__nav-btn">
            <FolderOpen size={16} />
            Explorer
          </button>
          <button type="button" className="data-studio__nav-btn">
            <Terminal size={16} />
            Query
          </button>
          <button type="button" className="data-studio__nav-btn">
            <History size={16} />
            History
          </button>
        </div>
        <div className="data-studio__header-spacer" />
        <span className="data-studio__badge">
          <span className="data-studio__badge-dot" />
          Connecte
        </span>
        <button type="button" className="ds-btn ds-btn--ghost ds-btn--icon" aria-label="Parametres">
          <Settings size={16} />
        </button>
        <button
          type="button"
          className="ds-btn ds-btn--ghost ds-btn--icon"
          aria-label="Deconnexion"
          onClick={handleLogout}
        >
          <LogOut size={16} />
        </button>
      </header>

      <div className="data-studio__main">
        <PanelGroup direction="horizontal">
          <Panel defaultSize={20} minSize={12} maxSize={35} className="data-studio__panel-sidebar">
            <div className="data-studio__sidebar-inner">
              <div className="data-studio__search-wrap">
                <Search className="data-studio__search-icon" size={16} />
                <input
                  className="data-studio__search"
                  placeholder="Rechercher tables..."
                  value={searchTerm}
                  onChange={(e) => setSearchTerm(e.target.value)}
                />
              </div>
              <div className="data-studio__conn">
                <Database size={12} style={{ display: "inline", marginRight: 6 }} />
                {apiUrl}
              </div>
              <div className="data-studio__tree">
                {Object.entries(grouped).map(([schema, schemaTables]) => (
                  <div key={schema}>
                    <button
                      type="button"
                      className="data-studio__schema-btn"
                      onClick={() => toggleSchema(schema)}
                    >
                      {expandedSchemas.has(schema) ? (
                        <ChevronDown size={16} />
                      ) : (
                        <ChevronRight size={16} />
                      )}
                      <Layers size={16} />
                      <span>{schema}</span>
                      <span className="data-studio__schema-count">{schemaTables.length}</span>
                    </button>
                    {expandedSchemas.has(schema) ? (
                      <div className="data-studio__tables">
                        {schemaTables.map((t) => (
                          <button
                            key={t.id}
                            type="button"
                            className={`data-studio__table-btn${
                              selectedId === t.id ? " data-studio__table-btn--active" : ""
                            }`}
                            onClick={() => selectTable(t.id)}
                          >
                            <TableIcon size={16} />
                            <span style={{ flex: 1, overflow: "hidden", textOverflow: "ellipsis" }}>
                              {t.name}
                            </span>
                            <span className="data-studio__table-rows">{t.rowCount || "—"}</span>
                          </button>
                        ))}
                      </div>
                    ) : null}
                  </div>
                ))}
              </div>
            </div>
          </Panel>

          <PanelResizeHandle />

          <Panel defaultSize={55} minSize={35}>
            <div className="data-studio__center">
              {selectedTable ? (
                <>
                  <div className="data-studio__table-header">
                    <div>
                      <h2 style={{ margin: 0, display: "flex", alignItems: "center", gap: 8 }}>
                        <TableIcon size={20} color="var(--ds-primary)" />
                        {selectedTable.name}
                        <span className="schema-relations__badge">{selectedTable.schema}</span>
                      </h2>
                      <p className="shell__muted" style={{ margin: "0.25rem 0 0", fontSize: "0.75rem" }}>
                        {selectedTable.columns.length} colonnes ·{" "}
                        {(rowCounts[selectedTable.id] ?? 0).toLocaleString()} lignes
                      </p>
                    </div>
                    <div className="data-studio__tabs">
                      <button
                        type="button"
                        className={`data-studio__tab${activeView === "data" ? " data-studio__tab--active" : ""}`}
                        onClick={() => setView("data")}
                      >
                        <TableIcon size={14} />
                        Data
                      </button>
                      <button
                        type="button"
                        className={`data-studio__tab${activeView === "structure" ? " data-studio__tab--active" : ""}`}
                        onClick={() => setView("structure")}
                      >
                        <Key size={14} />
                        Structure
                      </button>
                      <button
                        type="button"
                        className={`data-studio__tab${activeView === "diagram" ? " data-studio__tab--active" : ""}`}
                        onClick={() => setView("diagram")}
                      >
                        <GitBranch size={14} />
                        Diagram
                      </button>
                    </div>
                  </div>
                  <div className="data-studio__content">
                    {activeView === "data" ? (
                      <AdminDataTable
                        table={selectedTable}
                        onRowCount={(n) => handleRowCount(selectedTable.id, n)}
                      />
                    ) : null}
                    {activeView === "structure" ? (
                      <AdminTableDetails table={selectedTable} />
                    ) : null}
                    {activeView === "diagram" ? (
                      <AdminERDiagram
                        tables={tables}
                        global={global}
                        selectedTableId={selectedTable.id}
                        onTableSelect={(id) => selectTable(id, "diagram")}
                      />
                    ) : null}
                  </div>
                </>
              ) : (
                <div className="data-studio__empty">
                  <Database size={48} opacity={0.4} />
                  <p>Selectionnez une table dans la barre laterale</p>
                </div>
              )}
            </div>
          </Panel>

          <PanelResizeHandle />

          <Panel defaultSize={25} minSize={15} maxSize={40} collapsible>
            {selectedTable && activeView === "data" ? (
              <div style={{ height: "100%", borderLeft: "1px solid var(--ds-border)", background: "var(--ds-card)" }}>
                <div style={{ padding: "0.75rem", borderBottom: "1px solid var(--ds-border)", fontWeight: 600, fontSize: "0.875rem" }}>
                  Quick Info
                </div>
                <AdminTableDetails table={selectedTable} compact />
              </div>
            ) : (
              <div className="data-studio__empty" style={{ borderLeft: "1px solid var(--ds-border)" }}>
                <p style={{ fontSize: "0.875rem" }}>Quick Info (onglet Data)</p>
              </div>
            )}
          </Panel>
        </PanelGroup>
      </div>

      <footer className="data-studio__footer">
        <span>Django + PostgreSQL</span>
        <span style={{ marginLeft: "1rem" }}>Tables: {tables.length}</span>
        <div className="data-studio__footer-spacer" />
        <span>Admin API</span>
      </footer>
    </div>
  );
}
