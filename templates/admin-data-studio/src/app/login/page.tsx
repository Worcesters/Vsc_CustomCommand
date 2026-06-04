"use client";

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
          " Creez un superuser dans la base Docker : docker compose exec web uv run python manage.py createsuperuser";
      } else if (data.code === "invalid_credentials") {
        message +=
          " (Docker ? le compte doit exister dans PostgreSQL du compose, pas seulement en SQLite locale.)";
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
      <h1 className="page-auth__title">Connexion DataStudio</h1>
      <p className="page-home__lead">
        Acces reserve aux superusers Django.
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
        <button className="btn btn--primary" type="submit" disabled={loading}>
          {loading ? "Connexion..." : "Se connecter"}
        </button>
      </form>
    </main>
  );
}
