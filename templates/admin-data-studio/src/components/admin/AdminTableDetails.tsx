"use client";

import { Key, LinkIcon } from "lucide-react";
import type { StudioTable } from "@/lib/admin-studio-types";

type AdminTableDetailsProps = {
  table: StudioTable;
  compact?: boolean;
};

export function AdminTableDetails({ table, compact = false }: AdminTableDetailsProps) {
  const primaryKeys = table.columns.filter((c) => c.primaryKey);
  const foreignKeys = table.columns.filter((c) => c.foreignKey);
  const required = table.columns.filter((c) => !c.nullable && !c.primaryKey);

  const createSql = [
    `CREATE TABLE ${table.schema}.${table.name} (`,
    ...table.columns.map((c) => {
      const bits = [c.type, c.name];
      if (!c.nullable) bits.push("NOT NULL");
      if (c.primaryKey) bits.push("PRIMARY KEY");
      return `  ${bits.join(" ")}`;
    }),
    ");",
  ].join("\n");

  return (
    <div className={`ds-details${compact ? " ds-details--compact" : ""}`}>
      {!compact ? (
        <>
          <h3>{table.name}</h3>
          <p className="shell__muted">
            {table.rowCount.toLocaleString()} lignes · {table.columns.length} colonnes
          </p>
        </>
      ) : null}

      <div className="ds-details__stats">
        <div className="ds-details__stat">
          <div className="ds-details__stat-val">{primaryKeys.length}</div>
          <div className="ds-details__stat-label">PK</div>
        </div>
        <div className="ds-details__stat">
          <div className="ds-details__stat-val">{foreignKeys.length}</div>
          <div className="ds-details__stat-label">FK</div>
        </div>
        <div className="ds-details__stat">
          <div className="ds-details__stat-val">{required.length}</div>
          <div className="ds-details__stat-label">Required</div>
        </div>
      </div>

      <h4 className="ds-details__section-title">Colonnes</h4>
      {table.columns.map((col) => (
        <div key={col.name} className="ds-details__col-row">
          {col.primaryKey ? <Key size={14} className="text-yellow-500" /> : null}
          {col.foreignKey ? <LinkIcon size={14} /> : null}
          <span className="ds-er-node__col-name">{col.name}</span>
          <span className="ds-er-node__col-type">{col.type}</span>
          {!col.nullable ? (
            <span className="schema-relations__badge">NOT NULL</span>
          ) : null}
        </div>
      ))}

      {foreignKeys.length > 0 ? (
        <>
          <h4 className="ds-details__section-title">Relations</h4>
          {foreignKeys.map((col) => (
            <div key={col.name} className="ds-details__col-row">
              <LinkIcon size={14} />
              <span className="ds-er-node__col-name">{col.name}</span>
              <span className="ds-er-node__col-type">
                → {col.foreignKey?.targetId ?? col.foreignKey?.table}
              </span>
            </div>
          ))}
        </>
      ) : null}

      {!compact ? (
        <>
          <h4 className="ds-details__section-title">CREATE TABLE</h4>
          <pre className="ds-details__sql">{createSql}</pre>
        </>
      ) : null}
    </div>
  );
}
