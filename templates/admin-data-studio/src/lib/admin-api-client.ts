/**
 * Appels API admin cote navigateur via le BFF `/api/bff` (pas de next/headers).
 */
import type { ModelRowsResponse, RegistryEntry } from "@/lib/admin-api-types";

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
  const body = (await res.text().catch(() => "")).slice(0, 300);
  throw new Error(`${label} failed: HTTP ${res.status} ${body}`);
}

export type { ModelRowsResponse, RegistryEntry };

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
    const body = (await res.text().catch(() => "")).slice(0, 300);
    throw new Error(`model row delete failed: HTTP ${res.status} ${body}`);
  }
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
