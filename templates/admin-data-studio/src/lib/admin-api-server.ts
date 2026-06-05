import "server-only";

import { authHeaders } from "@/lib/auth-cookie-names";
import { getServerAccessToken } from "@/lib/auth-cookies.server";
import type { ModelRowsResponse, RegistryEntry } from "@/lib/admin-api-types";

function getApiBase(): string {
  return (
    process.env.API_INTERNAL_URL ??
    process.env.NEXT_PUBLIC_API_URL ??
    "http://localhost:8000"
  );
}

async function fetchApi(path: string, init?: RequestInit): Promise<Response> {
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

export class AdminApiError extends Error {
  readonly status: number;

  constructor(message: string, status: number) {
    super(message);
    this.name = "AdminApiError";
    this.status = status;
  }
}

async function assertOk(res: Response, label: string): Promise<Response> {
  if (res.ok) {
    return res;
  }
  const body = (await res.text().catch(() => "")).slice(0, 300);
  throw new AdminApiError(`${label} failed: HTTP ${res.status} ${body}`, res.status);
}

export type { ModelRowsResponse, RegistryEntry };

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
