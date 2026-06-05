"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { FormEvent, useState } from "react";

export default function LoginPage() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setLoading(true);
    setError("");

    const res = await fetch("/api/auth/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username, password }),
    });

    setLoading(false);

    if (!res.ok) {
      const data = (await res.json().catch(() => ({}))) as {
        detail?: string;
        code?: string;
      };
      let message = data.detail ?? "Identifiants invalides ou acces refuse.";
      if (data.code === "not_superuser") {
        message +=
          " Creez un superuser : docker compose exec web uv run python manage.py createsuperuser";
      } else if (data.code === "invalid_credentials") {
        message += " (compte superuser requis dans PostgreSQL Docker.)";
      }
      setError(message);
      return;
    }

    const next = searchParams.get("next") ?? "/admin";
    router.push(next);
    router.refresh();
  }

  return (
    <main className="page-auth">
      <div className="page-auth__bg" aria-hidden="true" />
      <section className="page-auth__panel">
        <p className="page-auth__brand">DataStudio</p>
        <h1 className="page-auth__title">Connexion</h1>
        <p className="page-auth__lead">
          Acces reserve aux superusers Django.{" "}
          <Link href="/" className="page-auth__back">
            Retour accueil
          </Link>
        </p>
        <form className="page-auth__form" onSubmit={onSubmit}>
          <label className="page-auth__label" htmlFor="username">
            Identifiant
          </label>
          <input
            id="username"
            className="page-auth__input"
            name="username"
            autoComplete="username"
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            required
          />
          <label className="page-auth__label" htmlFor="password">
            Mot de passe
          </label>
          <input
            id="password"
            className="page-auth__input"
            name="password"
            type="password"
            autoComplete="current-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
          />
          {error ? <p className="page-auth__error">{error}</p> : null}
          <button
            className="btn btn--primary page-auth__submit"
            type="submit"
            disabled={loading}
          >
            {loading ? "Connexion..." : "Se connecter"}
          </button>
        </form>
      </section>
    </main>
  );
}
