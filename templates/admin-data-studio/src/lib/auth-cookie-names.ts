/** Constantes auth partagees (middleware, routes API, client) — sans next/headers. */
export const ADMIN_ACCESS_COOKIE = "admin_access";

export function authHeaders(token?: string): HeadersInit {
  if (!token) {
    return {};
  }
  return { Authorization: `Bearer ${token}` };
}
