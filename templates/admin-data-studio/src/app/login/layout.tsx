import { Suspense } from "react";

export default function LoginLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
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
