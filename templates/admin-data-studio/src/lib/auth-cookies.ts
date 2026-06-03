import { cookies } from "next/headers";

/** Cookie httpOnly pose par `/api/auth/login` (token JWT access). */
export const ADMIN_ACCESS_COOKIE = "admin_access";

export async function getServerAccessToken(): Promise<string | undefined> {
  const store = await cookies();
  return store.get(ADMIN_ACCESS_COOKIE)?.value;
}

export function authHeaders(token?: string): HeadersInit {
  if (!token) {
    return {};
  }
  return { Authorization: `Bearer ${token}` };
}
