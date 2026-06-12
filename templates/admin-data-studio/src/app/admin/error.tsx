"use client";

import { AdminErrorState } from "@/components/admin/AdminErrorState";

export default function AdminError({
  error,
  reset,
}: Readonly<{
  error: Error & { digest?: string };
  reset: () => void;
}>) {
  return (
    <AdminErrorState
      code="Erreur"
      title="Administration inaccessible"
      message="Impossible de charger DataStudio. Verifiez que l'API Django repond et que la base de donnees est demarree."
      hint={error.message}
      onRetry={reset}
    />
  );
}
