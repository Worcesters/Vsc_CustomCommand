/**
 * Client API minimal (health check Django Ninja).
 * Pas de logique metier : orchestration fetch uniquement.
 */

export type HealthResponse = {
  status: string;
};

function apiBase(): string {
  const raw = import.meta.env.PUBLIC_API_URL ?? "http://localhost:8000";
  return raw.replace(/\/$/, "");
}

/** Verifie la disponibilite de l'API via GET /api/health/. */
export async function fetchHealth(): Promise<HealthResponse> {
  const res = await fetch(`${apiBase()}/api/health/`, { cache: "no-store" });
  if (!res.ok) {
    throw new Error(`Health check failed (${res.status})`);
  }
  return res.json() as Promise<HealthResponse>;
}
