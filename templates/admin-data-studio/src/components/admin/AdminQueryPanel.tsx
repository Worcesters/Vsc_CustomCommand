"use client";

import { useCallback, useState } from "react";
import { AlertCircle, Play, RotateCcw, Terminal } from "lucide-react";
import {
  AdminApiClientError,
  executeQuery,
  type QueryExecuteResponse,
} from "@/lib/admin-api-client";
import type { StudioTable } from "@/lib/admin-studio-types";

type AdminQueryPanelProps = {
  tables: StudioTable[];
  initialSql?: string;
};

const DEFAULT_SQL = "SELECT id, username, email, is_active\nFROM auth_user\nLIMIT 50";

export function AdminQueryPanel({ tables, initialSql }: AdminQueryPanelProps) {
  const [sql, setSql] = useState(initialSql ?? DEFAULT_SQL);
  const [running, setRunning] = useState(false);
  const [error, setError] = useState("");
  const [result, setResult] = useState<QueryExecuteResponse | null>(null);

  const runQuery = useCallback(async () => {
    const trimmed = sql.trim();
    if (!trimmed) {
      setError("Saisissez une requete SQL.");
      setResult(null);
      return;
    }
    setRunning(true);
    setError("");
    try {
      const data = await executeQuery(trimmed);
      setResult(data);
    } catch (err) {
      setResult(null);
      setError(
        err instanceof AdminApiClientError
          ? err.message
          : err instanceof Error
            ? err.message
            : "Erreur execution requete",
      );
    } finally {
      setRunning(false);
    }
  }, [sql]);

  const handleKeyDown = (event: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if ((event.ctrlKey || event.metaKey) && event.key === "Enter") {
      event.preventDefault();
      void runQuery();
    }
  };

  const insertTableQuery = (table: StudioTable) => {
    const snippet = `SELECT *\nFROM ${table.schema}_${table.name}\nLIMIT 50`;
    setSql(snippet);
    setError("");
  };

  const resetEditor = () => {
    setSql(DEFAULT_SQL);
    setError("");
    setResult(null);
  };

  return (
    <div className="ds-query">
      <div className="ds-query__toolbar">
        <div className="ds-query__title">
          <Terminal size={18} />
          <span>Editeur SQL</span>
          <span className="ds-query__hint">Lecture seule · Ctrl+Entree pour executer</span>
        </div>
        <div className="ds-query__actions">
          <button type="button" className="ds-btn ds-btn--ghost" onClick={resetEditor}>
            <RotateCcw size={16} />
            Reinitialiser
          </button>
          <button
            type="button"
            className="ds-btn ds-btn--primary"
            disabled={running}
            onClick={() => void runQuery()}
          >
            <Play size={16} />
            {running ? "Execution..." : "Executer"}
          </button>
        </div>
      </div>

      <div className="ds-query__editor-wrap">
        <textarea
          className="ds-query__editor"
          value={sql}
          spellCheck={false}
          aria-label="Requete SQL"
          onChange={(e) => {
            setSql(e.target.value);
            if (error) setError("");
          }}
          onKeyDown={handleKeyDown}
        />
      </div>

      {tables.length > 0 ? (
        <div className="ds-query__shortcuts">
          <span className="shell__muted">Raccourcis :</span>
          {tables.slice(0, 6).map((table) => (
            <button
              key={table.id}
              type="button"
              className="ds-query__shortcut-btn"
              onClick={() => insertTableQuery(table)}
            >
              {table.schema}.{table.name}
            </button>
          ))}
        </div>
      ) : null}

      {error ? (
        <div className="ds-query__error" role="alert">
          <AlertCircle size={16} />
          <span>{error}</span>
        </div>
      ) : null}

      <div className="ds-query__results">
        {result ? (
          <>
            <div className="ds-query__meta">
              <span>
                {result.row_count} ligne(s)
                {result.truncated ? " (tronque a 500)" : ""}
              </span>
              <span>{result.elapsed_ms} ms</span>
            </div>
            {result.columns.length === 0 ? (
              <p className="shell__muted ds-query__empty">Aucun resultat.</p>
            ) : (
              <div className="ds-query__table-wrap">
                <table className="ds-grid-table">
                  <thead>
                    <tr>
                      {result.columns.map((col) => (
                        <th key={col}>{col}</th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {result.rows.length === 0 ? (
                      <tr>
                        <td colSpan={result.columns.length} className="ds-null">
                          Aucune ligne
                        </td>
                      </tr>
                    ) : (
                      result.rows.map((row, rowIndex) => (
                        <tr key={rowIndex}>
                          {result.columns.map((col) => {
                            const val = row[col];
                            return (
                              <td key={col}>
                                {val == null ? (
                                  <span className="ds-null">NULL</span>
                                ) : (
                                  String(val).slice(0, 200)
                                )}
                              </td>
                            );
                          })}
                        </tr>
                      ))
                    )}
                  </tbody>
                </table>
              </div>
            )}
          </>
        ) : (
          <p className="shell__muted ds-query__empty">
            Executez une requete SELECT pour afficher les resultats ici.
          </p>
        )}
      </div>
    </div>
  );
}
