import { NextResponse } from "next/server";
import { ADMIN_ACCESS_COOKIE } from "@/lib/auth-cookie-names";

function getDjangoBase(): string {
  return (
    process.env.API_INTERNAL_URL ??
    process.env.NEXT_PUBLIC_API_URL ??
    "http://localhost:8000"
  );
}

export async function POST(request: Request) {
  const body = await request.json();
  const djangoRes = await fetch(`${getDjangoBase()}/api/auth/login/`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    cache: "no-store",
  });

  const data = await djangoRes.json().catch(() => ({}));

  if (!djangoRes.ok) {
    return NextResponse.json(data, { status: djangoRes.status });
  }

  const response = NextResponse.json({
    user: data.user,
  });

  response.cookies.set(ADMIN_ACCESS_COOKIE, data.access, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: 8 * 60 * 60,
  });

  return response;
}
