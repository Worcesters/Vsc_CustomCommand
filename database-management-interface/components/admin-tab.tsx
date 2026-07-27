"use client"

import { useState } from "react"
import type { SchemaOverview } from "@/app/actions/admin"
import { SchemaView } from "@/components/schema-view"
import { TableEditor } from "@/components/table-editor"
import { Table2, Network } from "lucide-react"

export function AdminTab({ schema }: { schema: SchemaOverview }) {
  const [view, setView] = useState<"data" | "schema">("data")
  const [selectedTable, setSelectedTable] = useState(schema.tables[0]?.name ?? "")

  if (schema.tables.length === 0) {
    return (
      <div className="rounded-2xl border border-border bg-card py-16 text-center text-sm text-muted-foreground">
        Aucune table trouvée dans la base.
      </div>
    )
  }

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h2 className="text-xl font-semibold tracking-tight">Administration</h2>
          <p className="text-sm text-muted-foreground">Explorez le schéma et modifiez vos données.</p>
        </div>
        <div className="inline-flex rounded-xl border border-border bg-card p-1">
          <button
            onClick={() => setView("data")}
            className={`inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-sm font-medium transition-colors ${
              view === "data" ? "bg-primary text-primary-foreground" : "text-muted-foreground hover:text-foreground"
            }`}
          >
            <Table2 className="size-4" />
            Données
          </button>
          <button
            onClick={() => setView("schema")}
            className={`inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-sm font-medium transition-colors ${
              view === "schema" ? "bg-primary text-primary-foreground" : "text-muted-foreground hover:text-foreground"
            }`}
          >
            <Network className="size-4" />
            Schéma &amp; liens
          </button>
        </div>
      </div>

      {view === "schema" ? (
        <SchemaView schema={schema} />
      ) : (
        <div className="flex flex-col gap-4 lg:flex-row">
          <aside className="flex shrink-0 gap-2 overflow-x-auto lg:w-52 lg:flex-col lg:overflow-visible">
            {schema.tables.map((t) => (
              <button
                key={t.name}
                onClick={() => setSelectedTable(t.name)}
                className={`flex items-center justify-between gap-2 rounded-lg border px-3 py-2 text-left text-sm transition-colors ${
                  selectedTable === t.name
                    ? "border-primary/50 bg-secondary text-foreground"
                    : "border-border bg-card text-muted-foreground hover:text-foreground"
                }`}
              >
                <span className="font-mono">{t.name}</span>
                <span className="shrink-0 text-xs text-muted-foreground">{t.rowCount}</span>
              </button>
            ))}
          </aside>
          <div className="min-w-0 flex-1">
            {selectedTable && <TableEditor key={selectedTable} tableName={selectedTable} />}
          </div>
        </div>
      )}
    </div>
  )
}
