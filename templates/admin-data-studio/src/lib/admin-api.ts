import { authHeaders, getServerAccessToken } from "@/lib/auth-cookies";

function getApiBase(): string {
  if (typeof window !== "undefined") {
    return process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8000";
  }
  return (
    process.env.API_INTERNAL_URL ??
    process.env.NEXT_PUBLIC_API_URL ??
    "http://localhost:8000"
  );
}

async function fetchApi(path: string, init?: RequestInit): Promise<Response> {
  const isServer = typeof window === "undefined";
  if (isServer) {
    const token = await getServerAccessToken();
    const url = `${getApiBase()}${path}`;
    const maxAttempts = 5;
    let lastError: unknown;
    for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
      try {
        return await fetch(url, {
          ...init,
          headers: {
            ...authHeaders(token),
            ...(init?.headers as Record<string, string> | undefined),
          },
          cache: "no-store",
        });
      } catch (error) {
        lastError = error;
        if (attempt < maxAttempts - 1) {
          await new Promise((resolve) => setTimeout(resolve, 1500));
        }
      }
    }
    throw lastError;
  }
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

export type RegistryEntry = {
  app_label: string;
  model_name: string;
  label: string;
  permissions: string[];
};

export async function fetchRegistry(): Promise<RegistryEntry[]> {
  const res = await assertOk(
    await fetchApi("/api/admin/registry/"),
    "registry fetch",
  );
  const data = await res.json();
  return data.results ?? [];
}

export async function fetchGlobalSchema(): Promise<unknown> {
  const res = await assertOk(await fetchApi("/api/admin/schema/"), "schema fetch");
  return res.json();
}

export async function fetchModelSchema(app: string, model: string): Promise<unknown> {
  const res = await assertOk(
    await fetchApi(`/api/admin/schema/${app}/${model}/`),
    "model schema fetch",
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

export type ModelRowsResponse = {
  results: Array<Record<string, string | number | boolean | null>>;
  count: number;
  pk_field?: string;
};

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
