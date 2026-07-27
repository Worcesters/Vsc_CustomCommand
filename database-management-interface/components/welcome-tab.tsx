"use client"

import { useEffect, useRef, useState } from "react"
import { Database, Table2, GitBranch, Pencil, ArrowRight } from "lucide-react"
import { Button } from "@/components/ui/button"

type Stat = { label: string; value: string; hint: string }

const features = [
  {
    icon: Table2,
    title: "Explorer les tables",
    body: "Parcourez chaque table, ses colonnes, types et clés primaires en un coup d'œil.",
  },
  {
    icon: GitBranch,
    title: "Visualiser les liens",
    body: "Comprenez les relations entre vos tables grâce à une carte des clés étrangères.",
  },
  {
    icon: Pencil,
    title: "Modifier les valeurs",
    body: "Éditez n'importe quelle cellule directement, sans quitter l'interface.",
  },
]

export function WelcomeTab({
  onEnterAdmin,
  stats,
}: {
  onEnterAdmin: () => void
  stats: Stat[]
}) {
  const [pointer, setPointer] = useState({ x: 0.5, y: 0.5 })
  const ref = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const el = ref.current
    if (!el) return
    function onMove(e: PointerEvent) {
      const rect = el!.getBoundingClientRect()
      setPointer({
        x: (e.clientX - rect.left) / rect.width,
        y: (e.clientY - rect.top) / rect.height,
      })
    }
    el.addEventListener("pointermove", onMove)
    return () => el.removeEventListener("pointermove", onMove)
  }, [])

  return (
    <div className="flex flex-col gap-16">
      <section
        ref={ref}
        className="relative overflow-hidden rounded-3xl border border-border bg-card px-6 py-16 sm:px-12 sm:py-24"
      >
        {/* interactive glow following the cursor */}
        <div
          aria-hidden
          className="pointer-events-none absolute -inset-px opacity-70 transition-[background] duration-200"
          style={{
            background: `radial-gradient(600px circle at ${pointer.x * 100}% ${pointer.y * 100}%, color-mix(in oklch, var(--primary) 18%, transparent), transparent 60%)`,
          }}
        />
        <div className="relative mx-auto flex max-w-2xl flex-col items-center text-center">
          <span className="mb-6 inline-flex items-center gap-2 rounded-full border border-border bg-secondary px-4 py-1.5 text-xs font-medium text-muted-foreground">
            <span className="size-1.5 rounded-full bg-primary" />
            Base de données connectée
          </span>
          <h1 className="text-balance text-4xl font-semibold tracking-tight sm:text-6xl">
            Votre console de données, <span className="text-primary">épurée</span> et vivante
          </h1>
          <p className="mt-6 max-w-xl text-pretty text-lg leading-relaxed text-muted-foreground">
            Bienvenue. Explorez le schéma de votre base, visualisez les liens entre les tables et modifiez vos données —
            le tout depuis une interface claire et interactive.
          </p>
          <div className="mt-10 flex flex-col gap-3 sm:flex-row">
            <Button size="lg" onClick={onEnterAdmin} className="group gap-2">
              Ouvrir l&apos;admin
              <ArrowRight className="size-4 transition-transform group-hover:translate-x-0.5" />
            </Button>
          </div>
        </div>
      </section>

      <section className="grid gap-4 sm:grid-cols-3">
        {stats.map((s) => (
          <div key={s.label} className="rounded-2xl border border-border bg-card p-6">
            <div className="text-3xl font-semibold tracking-tight text-foreground">{s.value}</div>
            <div className="mt-1 text-sm font-medium text-foreground">{s.label}</div>
            <div className="mt-0.5 text-sm text-muted-foreground">{s.hint}</div>
          </div>
        ))}
      </section>

      <section className="grid gap-4 md:grid-cols-3">
        {features.map((f) => (
          <div
            key={f.title}
            className="group rounded-2xl border border-border bg-card p-6 transition-colors hover:border-primary/40"
          >
            <div className="mb-4 inline-flex size-11 items-center justify-center rounded-xl bg-secondary text-primary transition-colors group-hover:bg-primary group-hover:text-primary-foreground">
              <f.icon className="size-5" />
            </div>
            <h3 className="text-base font-semibold">{f.title}</h3>
            <p className="mt-2 text-sm leading-relaxed text-muted-foreground">{f.body}</p>
          </div>
        ))}
      </section>

      <section className="flex flex-col items-center gap-4 rounded-3xl border border-border bg-card px-6 py-12 text-center">
        <Database className="size-8 text-primary" />
        <h2 className="text-balance text-2xl font-semibold">Prêt à plonger dans vos données ?</h2>
        <p className="max-w-md text-pretty text-sm text-muted-foreground">
          L&apos;onglet Admin vous donne un contrôle complet sur les tables, colonnes et valeurs de votre base.
        </p>
        <Button variant="secondary" onClick={onEnterAdmin} className="mt-2 gap-2">
          Aller à l&apos;admin
          <ArrowRight className="size-4" />
        </Button>
      </section>
    </div>
  )
}
