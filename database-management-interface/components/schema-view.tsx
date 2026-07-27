"use client"

import type { SchemaOverview } from "@/app/actions/admin"
import { KeyRound, Link2 } from "lucide-react"
import { Badge } from "@/components/ui/badge"

function shortType(dataType: string) {
  const map: Record<string, string> = {
    "character varying": "varchar",
    "timestamp with time zone": "timestamptz",
    "timestamp without time zone": "timestamp",
    integer: "int4",
    numeric: "numeric",
    boolean: "bool",
    text: "text",
  }
  return map[dataType] ?? dataType
}

export function SchemaView({ schema }: { schema: SchemaOverview }) {
  const { tables, foreignKeys } = schema

  return (
    <div className="flex flex-col gap-6">
      <div className="rounded-2xl border border-border bg-card p-5">
        <div className="mb-1 flex items-center gap-2">
          <Link2 className="size-4 text-primary" />
          <h3 className="text-sm font-semibold">Relations entre les tables</h3>
        </div>
        {foreignKeys.length === 0 ? (
          <p className="text-sm text-muted-foreground">Aucune clé étrangère détectée.</p>
        ) : (
          <ul className="mt-3 flex flex-col gap-2">
            {foreignKeys.map((fk, i) => (
              <li
                key={i}
                className="flex flex-wrap items-center gap-2 rounded-lg border border-border bg-secondary/50 px-3 py-2 text-sm"
              >
                <span className="font-mono text-foreground">{fk.fromTable}</span>
                <span className="font-mono text-muted-foreground">.{fk.fromColumn}</span>
                <span className="text-primary">&rarr;</span>
                <span className="font-mono text-foreground">{fk.toTable}</span>
                <span className="font-mono text-muted-foreground">.{fk.toColumn}</span>
              </li>
            ))}
          </ul>
        )}
      </div>

      <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        {tables.map((table) => {
          const outgoing = foreignKeys.filter((fk) => fk.fromTable === table.name)
          const incoming = foreignKeys.filter((fk) => fk.toTable === table.name)
          return (
            <div key={table.name} className="overflow-hidden rounded-2xl border border-border bg-card">
              <div className="flex items-center justify-between border-b border-border bg-secondary/40 px-4 py-3">
                <span className="font-mono text-sm font-semibold">{table.name}</span>
                <Badge variant="secondary" className="text-xs">
                  {table.rowCount} {table.rowCount > 1 ? "lignes" : "ligne"}
                </Badge>
              </div>
              <ul className="divide-y divide-border">
                {table.columns.map((col) => {
                  const fkOut = outgoing.find((fk) => fk.fromColumn === col.name)
                  return (
                    <li key={col.name} className="flex items-center justify-between gap-3 px-4 py-2 text-sm">
                      <span className="flex items-center gap-1.5">
                        {col.isPrimaryKey && <KeyRound className="size-3.5 text-primary" />}
                        {fkOut && !col.isPrimaryKey && <Link2 className="size-3.5 text-chart-2" />}
                        <span className={col.isPrimaryKey ? "font-medium text-foreground" : "text-foreground"}>
                          {col.name}
                        </span>
                      </span>
                      <span className="font-mono text-xs text-muted-foreground">{shortType(col.dataType)}</span>
                    </li>
                  )
                })}
              </ul>
              {incoming.length > 0 && (
                <div className="border-t border-border px-4 py-2 text-xs text-muted-foreground">
                  Référencée par&nbsp;
                  <span className="font-mono text-foreground">
                    {incoming.map((fk) => fk.fromTable).join(", ")}
                  </span>
                </div>
              )}
            </div>
          )
        })}
      </div>
    </div>
  )
}
