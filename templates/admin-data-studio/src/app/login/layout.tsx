import { redirect } from "next/navigation";
import { Suspense } from "react";
import {
  clearAdminAccessCookie,
  getServerAccessToken,
  validateAdminSession,
} from "@/lib/auth-cookies.server";

export default async function LoginLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  const token = await getServerAccessToken();
  if (token) {
    if (await validateAdminSession()) {
      redirect("/admin");
    }
    await clearAdminAccessCookie();
  }

  return (
    <Suspense
      fallback={
        <main className="page-auth">
          <p className="shell__muted">Chargement...</p>
        </main>
      }
    >
      {children}
    </Suspense>
  );
}
