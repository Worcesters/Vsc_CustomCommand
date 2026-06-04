import "server-only";

import { cookies } from "next/headers";

import { ADMIN_ACCESS_COOKIE } from "@/lib/auth-cookie-names";

export { ADMIN_ACCESS_COOKIE } from "@/lib/auth-cookie-names";

/** Token JWT access lu depuis le cookie httpOnly (Server Components / RSC uniquement). */
export async function getServerAccessToken(): Promise<string | undefined> {
  const store = await cookies();
  return store.get(ADMIN_ACCESS_COOKIE)?.value;
}
