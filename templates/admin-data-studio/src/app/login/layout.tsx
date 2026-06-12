import { redirect } from "next/navigation";
import { Suspense } from "react";
import {
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
    // Cookie present mais invalide : on le purge via un Route Handler (mutation
    // cookie interdite pendant le rendu) puis retour au formulaire.
    redirect("/api/auth/clear?next=/login");
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
