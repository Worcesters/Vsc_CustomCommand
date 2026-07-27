"use client"

import { useState, useTransition } from "react"
import useSWR from "swr"
import { getTableData, updateCell, type TableData } from "@/app/actions/admin"
import { Input } from "@/components/ui/input"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Check, X, Loader2, KeyRound } from "lucide-react"
import { toast } from "sonner"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"

function formatValue(value: unknown): string {
  if (value === null || value === undefined) return ""
  if (value instanceof Date) return value.toISOString()
  return String(value)
}

export function TableEditor({ tableName }: { tableName: string }) {
  const { data, isLoading, mutate } = useSWR<TableData>(
    ["table-data", tableName],
    () => getTableData(tableName),
    { revalidateOnFocus: false },
  )

  const [editing, setEditing] = useState<{ rowIdx: number; column: string } | null>(null)
  const [draft, setDraft] = useState("")
  const [isPending, startTransition] = useTransition()

  if (isLoading || !data) {
    return (
      <div className="flex items-center justify-center gap-2 rounded-2xl border border-border bg-card py-16 text-sm text-muted-foreground">
        <Loader2 className="size-4 animate-spin" />
        Chargement de « {tableName} »…
      </div>
    )
  }

  const pk = data.primaryKeys[0]

  function startEdit(rowIdx: number, column: string, value: unknown) {
    if (!pk) {
      toast.error("Cette table n'a pas de clé primaire, édition impossible.")
      return
    }
    if (column === pk) return
    setEditing({ rowIdx, column })
    setDraft(formatValue(value))
  }

  function commit() {
    if (!editing || !pk || !data) return
    const row = data.rows[editing.rowIdx]
    const pkValue = row[pk] as string | number
    const column = editing.column
    const value = draft

    startTransition(async () => {
      const res = await updateCell({
        tableName,
        primaryKey: pk,
        primaryKeyValue: pkValue,
        column,
        value,
      })
      if (res.ok) {
        toast.success(`« ${column} » mis à jour`)
        setEditing(null)
        mutate()
      } else {
        toast.error(res.error)
      }
    })
  }

  return (
    <div className="overflow-hidden rounded-2xl border border-border bg-card">
      <div className="flex items-center justify-between border-b border-border px-4 py-3">
        <div className="flex items-center gap-2">
          <span className="font-mono text-sm font-semibold">{tableName}</span>
          <Badge variant="secondary" className="text-xs">
            {data.rows.length} affichées
          </Badge>
        </div>
        <p className="text-xs text-muted-foreground">Cliquez une cellule pour l&apos;éditer</p>
      </div>
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              {data.columns.map((col) => (
                <TableHead key={col} className="whitespace-nowrap font-mono text-xs">
                  <span className="inline-flex items-center gap-1">
                    {col === pk && <KeyRound className="size-3 text-primary" />}
                    {col}
                  </span>
                </TableHead>
              ))}
            </TableRow>
          </TableHeader>
          <TableBody>
            {data.rows.map((row, rowIdx) => (
              <TableRow key={rowIdx}>
                {data.columns.map((col) => {
                  const isEditing = editing?.rowIdx === rowIdx && editing?.column === col
                  const isPk = col === pk
                  return (
                    <TableCell
                      key={col}
                      className={`whitespace-nowrap text-sm ${
                        isPk ? "text-muted-foreground" : "cursor-pointer hover:bg-secondary/60"
                      }`}
                      onClick={() => !isEditing && startEdit(rowIdx, col, row[col])}
                    >
                      {isEditing ? (
                        <div className="flex items-center gap-1">
                          <Input
                            autoFocus
                            value={draft}
                            onChange={(e) => setDraft(e.target.value)}
                            onKeyDown={(e) => {
                              if (e.nativeEvent.isComposing || e.keyCode === 229) return
                              if (e.key === "Enter") commit()
                              if (e.key === "Escape") setEditing(null)
                            }}
                            className="h-8 w-40 font-mono text-sm"
                          />
                          <Button
                            size="icon"
                            className="size-8 shrink-0"
                            onClick={(e) => {
                              e.stopPropagation()
                              commit()
                            }}
                            disabled={isPending}
                          >
                            {isPending ? <Loader2 className="size-4 animate-spin" /> : <Check className="size-4" />}
                          </Button>
                          <Button
                            size="icon"
                            variant="secondary"
                            className="size-8 shrink-0"
                            onClick={(e) => {
                              e.stopPropagation()
                              setEditing(null)
                            }}
                          >
                            <X className="size-4" />
                          </Button>
                        </div>
                      ) : (
                        <span className={formatValue(row[col]) === "" ? "text-muted-foreground/50" : ""}>
                          {formatValue(row[col]) === "" ? "NULL" : formatValue(row[col])}
                        </span>
                      )}
                    </TableCell>
                  )
                })}
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </div>
  )
}
