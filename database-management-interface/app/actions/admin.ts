"use server"

import { pool } from "@/lib/db"

export type ColumnInfo = {
  name: string
  dataType: string
  isNullable: boolean
  default: string | null
  isPrimaryKey: boolean
}

export type ForeignKey = {
  fromTable: string
  fromColumn: string
  toTable: string
  toColumn: string
}

export type TableInfo = {
  name: string
  columns: ColumnInfo[]
  primaryKeys: string[]
  rowCount: number
}

export type SchemaOverview = {
  tables: TableInfo[]
  foreignKeys: ForeignKey[]
}

// Only allow identifiers that exist in the schema to be interpolated into SQL.
function assertKnownIdentifier(name: string, allowed: Set<string>, label: string) {
  if (!allowed.has(name)) {
    throw new Error(`${label} inconnu: ${name}`)
  }
}

async function getTableNames(): Promise<string[]> {
  const { rows } = await pool.query<{ table_name: string }>(
    `SELECT table_name FROM information_schema.tables
     WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
     ORDER BY table_name`,
  )
  return rows.map((r) => r.table_name)
}

export async function getSchemaOverview(): Promise<SchemaOverview> {
  const tableNames = await getTableNames()

  const primaryKeysRes = await pool.query<{ table_name: string; column_name: string }>(
    `SELECT tc.table_name, kcu.column_name
     FROM information_schema.table_constraints tc
     JOIN information_schema.key_column_usage kcu
       ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
     WHERE tc.constraint_type = 'PRIMARY KEY' AND tc.table_schema = 'public'`,
  )
  const pkMap = new Map<string, string[]>()
  for (const r of primaryKeysRes.rows) {
    const list = pkMap.get(r.table_name) ?? []
    list.push(r.column_name)
    pkMap.set(r.table_name, list)
  }

  const columnsRes = await pool.query<{
    table_name: string
    column_name: string
    data_type: string
    is_nullable: string
    column_default: string | null
  }>(
    `SELECT table_name, column_name, data_type, is_nullable, column_default
     FROM information_schema.columns
     WHERE table_schema = 'public'
     ORDER BY table_name, ordinal_position`,
  )

  const fkRes = await pool.query<{
    from_table: string
    from_column: string
    to_table: string
    to_column: string
  }>(
    `SELECT
       tc.table_name AS from_table,
       kcu.column_name AS from_column,
       ccu.table_name AS to_table,
       ccu.column_name AS to_column
     FROM information_schema.table_constraints tc
     JOIN information_schema.key_column_usage kcu
       ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
     JOIN information_schema.constraint_column_usage ccu
       ON ccu.constraint_name = tc.constraint_name AND ccu.table_schema = tc.table_schema
     WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_schema = 'public'`,
  )

  const tables: TableInfo[] = []
  for (const name of tableNames) {
    const pks = pkMap.get(name) ?? []
    const columns: ColumnInfo[] = columnsRes.rows
      .filter((c) => c.table_name === name)
      .map((c) => ({
        name: c.column_name,
        dataType: c.data_type,
        isNullable: c.is_nullable === "YES",
        default: c.column_default,
        isPrimaryKey: pks.includes(c.column_name),
      }))

    const countRes = await pool.query<{ count: string }>(`SELECT COUNT(*)::text AS count FROM "${name}"`)

    tables.push({
      name,
      columns,
      primaryKeys: pks,
      rowCount: Number(countRes.rows[0]?.count ?? 0),
    })
  }

  const foreignKeys: ForeignKey[] = fkRes.rows.map((r) => ({
    fromTable: r.from_table,
    fromColumn: r.from_column,
    toTable: r.to_table,
    toColumn: r.to_column,
  }))

  return { tables, foreignKeys }
}

export type TableData = {
  columns: string[]
  rows: Record<string, unknown>[]
  primaryKeys: string[]
}

export async function getTableData(tableName: string, limit = 100): Promise<TableData> {
  const allowedTables = new Set(await getTableNames())
  assertKnownIdentifier(tableName, allowedTables, "Table")

  const overview = await getSchemaOverview()
  const table = overview.tables.find((t) => t.name === tableName)
  if (!table) throw new Error(`Table inconnue: ${tableName}`)

  const orderBy = table.primaryKeys[0] ? `ORDER BY "${table.primaryKeys[0]}"` : ""
  const { rows } = await pool.query(`SELECT * FROM "${tableName}" ${orderBy} LIMIT $1`, [limit])

  return {
    columns: table.columns.map((c) => c.name),
    rows: rows as Record<string, unknown>[],
    primaryKeys: table.primaryKeys,
  }
}

export async function updateCell(params: {
  tableName: string
  primaryKey: string
  primaryKeyValue: string | number
  column: string
  value: string
}): Promise<{ ok: true } | { ok: false; error: string }> {
  try {
    const allowedTables = new Set(await getTableNames())
    assertKnownIdentifier(params.tableName, allowedTables, "Table")

    const overview = await getSchemaOverview()
    const table = overview.tables.find((t) => t.name === params.tableName)
    if (!table) return { ok: false, error: "Table inconnue" }

    const allowedColumns = new Set(table.columns.map((c) => c.name))
    assertKnownIdentifier(params.column, allowedColumns, "Colonne")
    assertKnownIdentifier(params.primaryKey, allowedColumns, "Clé primaire")

    // Prevent editing the primary key column itself for safety.
    if (params.column === params.primaryKey) {
      return { ok: false, error: "La clé primaire ne peut pas être modifiée." }
    }

    const col = table.columns.find((c) => c.name === params.column)!
    const value = params.value === "" && col.isNullable ? null : params.value

    await pool.query(
      `UPDATE "${params.tableName}" SET "${params.column}" = $1 WHERE "${params.primaryKey}" = $2`,
      [value, params.primaryKeyValue],
    )
    return { ok: true }
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : "Erreur inconnue" }
  }
}
