import { getSchemaOverview } from "@/app/actions/admin"
import { ConsoleShell } from "@/components/console-shell"

export const dynamic = "force-dynamic"

export default async function Page() {
  const schema = await getSchemaOverview()

  const totalRows = schema.tables.reduce((acc, t) => acc + t.rowCount, 0)
  const stats = [
    { label: "Tables", value: String(schema.tables.length), hint: "dans le schéma public" },
    { label: "Lignes", value: String(totalRows), hint: "toutes tables confondues" },
    { label: "Relations", value: String(schema.foreignKeys.length), hint: "clés étrangères" },
  ]

  return <ConsoleShell schema={schema} stats={stats} />
}
