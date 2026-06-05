/**
 * Appels API admin cote navigateur via le BFF `/api/bff` (pas de next/headers).
 */
import { throwAdminApiError } from "@/lib/admin-api-errors";
import type {
  ModelRowsResponse,
  QueryExecuteResponse,
  RegistryEntry,
} from "@/lib/admin-api-types";

export { AdminApiClientError } from "@/lib/admin-api-errors";

async function fetchApi(path: string, init?: RequestInit): Promise<Response> {
  return fetch(`/api/bff${path}`, {
    ...init,
    credentials: "same-origin",
    cache: "no-store",
  });
}

async function assertOk(res: Response, label: string): Promise<Response> {
  if (res.ok) {
    return res;
  }
  await throwAdminApiError(res, label);
}

export type { ModelRowsResponse, QueryExecuteResponse, RegistryEntry };

export async function fetchModelRows(
  app: string,
  model: string,
): Promise<ModelRowsResponse> {
  const res = await assertOk(
    await fetchApi(`/api/admin/models/${app}/${model}/`),
    "model rows fetch",
  );
  return res.json();
}

export async function createModelRow(
  app: string,
  model: string,
  payload: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const res = await assertOk(
    await fetchApi(`/api/admin/models/${app}/${model}/`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    }),
    "model row create",
  );
  return res.json();
}

export async function updateModelRow(
  app: string,
  model: string,
  pk: string | number,
  payload: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const res = await assertOk(
    await fetchApi(`/api/admin/models/${app}/${model}/${pk}/`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    }),
    "model row update",
  );
  return res.json();
}

export async function deleteModelRow(
  app: string,
  model: string,
  pk: string | number,
): Promise<void> {
  const res = await fetchApi(`/api/admin/models/${app}/${model}/${pk}/`, {
    method: "DELETE",
  });
  if (!res.ok && res.status !== 204) {
    await throwAdminApiError(res, "model row delete");
  }
}

export async function executeQuery(sql: string): Promise<QueryExecuteResponse> {
  const res = await assertOk(
    await fetchApi("/api/admin/query/", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ sql }),
    }),
    "query execute",
  );
  return res.json();
}

export async function fetchSchemaExport(): Promise<{ markdown: string }> {
  const res = await assertOk(
    await fetchApi("/api/admin/schema/export/"),
    "schema export fetch",
  );
  return res.json();
}

export async function downloadSchemaMermaid(): Promise<void> {
  const data = await fetchSchemaExport();
  const blob = new Blob([data.markdown], { type: "text/markdown;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = "schema-er.mmd";
  anchor.click();
  URL.revokeObjectURL(url);
}
