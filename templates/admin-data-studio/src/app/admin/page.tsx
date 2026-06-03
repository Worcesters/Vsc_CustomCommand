import { redirect } from "next/navigation";
import { Suspense } from "react";
import { getServerAccessToken } from "@/lib/auth-cookies";
import {
  fetchGlobalSchema,
  fetchModelSchema,
  fetchRegistry,
} from "@/lib/admin-api";
import { DatabaseAdmin } from "@/components/admin/DatabaseAdmin";
import type { GlobalSchema, ModelSchema } from "@/lib/schema-types";

function getApiDisplayUrl(): string {
  return process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8000";
}

async function AdminStudioLoader() {
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
