import { NextRequest, NextResponse } from "next/server";
import { ADMIN_ACCESS_COOKIE } from "@/lib/auth-cookie-names";

function getDjangoBase(): string {
  return (
    process.env.API_INTERNAL_URL ??
    process.env.NEXT_PUBLIC_API_URL ??
    "http://localhost:8000"
  );
}

async function proxyToDjango(
  request: NextRequest,
  pathSegments: string[],
): Promise<NextResponse> {
  const token = request.cookies.get(ADMIN_ACCESS_COOKIE)?.value;
  if (!token) {
    return NextResponse.json({ detail: "Non authentifie" }, { status: 401 });
  }

  const path = pathSegments.join("/");
  // Next.js normalise les URLs et retire le slash final ; Django APPEND_SLASH l'exige sur POST/PATCH.
  const djangoPath = path.endsWith("/") ? path : `${path}/`;
  const url = `${getDjangoBase()}/${djangoPath}${request.nextUrl.search}`;
  const headers = new Headers();
  headers.set("Authorization", `Bearer ${token}`);
  const contentType = request.headers.get("content-type");
  if (contentType) {
    headers.set("Content-Type", contentType);
  }

  const body = ["GET", "HEAD"].includes(request.method)
    ? undefined
    : await request.text();

  const djangoRes = await fetch(url, {
    method: request.method,
    headers,
    body,
    cache: "no-store",
  });

  return new NextResponse(await djangoRes.text(), {
    status: djangoRes.status,
    headers: {
      "Content-Type": djangoRes.headers.get("Content-Type") ?? "application/json",
    },
  });
}

type RouteContext = { params: Promise<{ path: string[] }> };

async function handle(
  request: NextRequest,
  context: RouteContext,
): Promise<NextResponse> {
  const { path } = await context.params;
  return proxyToDjango(request, path);
}

export const GET = handle;
export const POST = handle;
export const PATCH = handle;
export const DELETE = handle;
