import "server-only";

import { cookies } from "next/headers";

import { ADMIN_ACCESS_COOKIE, authHeaders } from "@/lib/auth-cookie-names";

export { ADMIN_ACCESS_COOKIE } from "@/lib/auth-cookie-names";

function getApiBase(): string {
  return (
    process.env.API_INTERNAL_URL ??
    process.env.NEXT_PUBLIC_API_URL ??
    "http://localhost:8000"
  );
}

/** Token JWT access lu depuis le cookie httpOnly (Server Components / RSC uniquement). */
export async function getServerAccessToken(): Promise<string | undefined> {
  const store = await cookies();
  return store.get(ADMIN_ACCESS_COOKIE)?.value;
}

/** Supprime le cookie JWT admin (session invalide ou logout). */
export async function clearAdminAccessCookie(): Promise<void> {
  const store = await cookies();
  store.delete(ADMIN_ACCESS_COOKIE);
}

/** Verifie aupres de Django que le JWT correspond encore a un superuser existant. */
export async function validateAdminSession(): Promise<boolean> {
  const token = await getServerAccessToken();
  if (!token) {
    return false;
  }
  try {
    const res = await fetch(`${getApiBase()}/api/auth/session/`, {
      headers: authHeaders(token),
      cache: "no-store",
    });
    return res.ok;
  } catch {
    return false;
  }
}
