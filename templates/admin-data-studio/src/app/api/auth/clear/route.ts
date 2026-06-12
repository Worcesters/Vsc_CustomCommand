import { NextRequest, NextResponse } from "next/server";
import { ADMIN_ACCESS_COOKIE } from "@/lib/auth-cookie-names";

/**
 * Efface le cookie JWT admin puis redirige.
 * Les cookies ne peuvent etre modifies que dans un Route Handler ou une
 * Server Action (jamais pendant le rendu d'un layout/page RSC).
 */
export function GET(request: NextRequest): NextResponse {
  const requested = request.nextUrl.searchParams.get("next") ?? "/login";
  const safeNext = requested.startsWith("/") ? requested : "/login";
  const response = NextResponse.redirect(new URL(safeNext, request.url));
  response.cookies.set(ADMIN_ACCESS_COOKIE, "", {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: 0,
  });
  return response;
}
