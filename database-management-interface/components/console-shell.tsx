"use client"

import { useState } from "react"
import type { SchemaOverview } from "@/app/actions/admin"
import { WelcomeTab } from "@/components/welcome-tab"
import { AdminTab } from "@/components/admin-tab"
import { Toaster } from "@/components/ui/sonner"
import { Database, Home, Settings } from "lucide-react"

type Stat = { label: string; value: string; hint: string }
type Tab = "welcome" | "admin"

export function ConsoleShell({ schema, stats }: { schema: SchemaOverview; stats: Stat[] }) {
  const [tab, setTab] = useState<Tab>("welcome")

  return (
    <div className="min-h-screen">
      <header className="sticky top-0 z-10 border-b border-border bg-background/80 backdrop-blur">
        <div className="mx-auto flex max-w-6xl items-center justify-between px-4 py-3 sm:px-6">
          <div className="flex items-center gap-2">
            <div className="inline-flex size-8 items-center justify-center rounded-lg bg-primary text-primary-foreground">
              <Database className="size-4" />
            </div>
            <span className="text-sm font-semibold tracking-tight">Console</span>
          </div>
          <nav className="inline-flex rounded-xl border border-border bg-card p-1">
            <button
              onClick={() => setTab("welcome")}
              className={`inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-sm font-medium transition-colors ${
                tab === "welcome" ? "bg-secondary text-foreground" : "text-muted-foreground hover:text-foreground"
              }`}
            >
              <Home className="size-4" />
              Bienvenue
            </button>
            <button
              onClick={() => setTab("admin")}
              className={`inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-sm font-medium transition-colors ${
                tab === "admin" ? "bg-secondary text-foreground" : "text-muted-foreground hover:text-foreground"
              }`}
            >
              <Settings className="size-4" />
              Admin
            </button>
          </nav>
        </div>
      </header>

      <main className="mx-auto max-w-6xl px-4 py-10 sm:px-6 sm:py-14">
        {tab === "welcome" ? (
          <WelcomeTab stats={stats} onEnterAdmin={() => setTab("admin")} />
        ) : (
          <AdminTab schema={schema} />
        )}
      </main>

      <Toaster />
    </div>
  )
}
