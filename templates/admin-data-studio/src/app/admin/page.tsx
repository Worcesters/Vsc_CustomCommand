import { redirect } from "next/navigation";
import { Suspense } from "react";
import {
  AdminApiError,
  fetchGlobalSchema,
  fetchModelSchema,
  fetchRegistry,
} from "@/lib/admin-api-server";
import { getServerAccessToken } from "@/lib/auth-cookies.server";
import { DatabaseAdmin } from "@/components/admin/DatabaseAdmin";
import type { GlobalSchema, ModelSchema } from "@/lib/schema-types";

function getApiDisplayUrl(): string {
  return process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8000";
}

async function AdminStudioLoader() {
  try {
    const registry = await fetchRegistry();
    const global = (await fetchGlobalSchema()) as GlobalSchema;
    const schemas: ModelSchema[] = await Promise.all(
      registry.map((entry) =>
        fetchModelSchema(entry.app_label, entry.model_name) as Promise<ModelSchema>,
      ),
    );

    return (
      <DatabaseAdmin
        registry={registry}
        schemas={schemas}
        global={global}
        apiUrl={getApiDisplayUrl()}
      />
    );
  } catch (error) {
    if (error instanceof AdminApiError && error.status === 401) {
      // Session expiree / token invalide : purge cookie puis retour login.
      redirect(
        `/api/auth/clear?next=${encodeURIComponent("/login?reason=session_expired")}`,
      );
    }
    if (error instanceof AdminApiError && error.status === 403) {
      // Compte sans droits superuser ou plus aucun admin : page dediee.
      redirect(`/api/auth/clear?next=${encodeURIComponent("/admin-unavailable")}`);
    }
    throw error;
  }
}

export default async function AdminPage() {
  if (!(await getServerAccessToken())) {
    redirect("/login");
  }

  return (
    <Suspense fallback={<p className="shell__muted">Chargement DataStudio...</p>}>
      <AdminStudioLoader />
    </Suspense>
  );
}
