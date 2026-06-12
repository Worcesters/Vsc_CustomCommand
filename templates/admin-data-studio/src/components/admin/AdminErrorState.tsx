"use client";

import Link from "next/link";
import "@/styles/admin/error-state.scss";

type AdminErrorStateProps = Readonly<{
  code?: string;
  title?: string;
  message?: string;
  hint?: string;
  homeHref?: string;
  loginHref?: string;
  onRetry?: () => void;
}>;

export function AdminErrorState({
  code = "Administration",
  title = "Aucun administrateur disponible",
  message = "Aucun compte superuser n'est accessible pour cette base de donnees. Creez-en un, puis reconnectez-vous.",
  hint = "docker compose exec web uv run python manage.py createsuperuser",
  homeHref = "/",
  loginHref = "/login",
  onRetry,
}: AdminErrorStateProps): React.ReactElement {
  return (
    <main className="page-error">
      <div className="page-error__bg" aria-hidden="true">
        <span className="page-error__orb page-error__orb--1" />
        <span className="page-error__orb page-error__orb--2" />
      </div>
      <section className="page-error__panel" role="alert">
        <span className="page-error__icon" aria-hidden="true">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6">
            <path
              d="M12 9v4m0 4h.01M10.3 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.7 3.86a2 2 0 0 0-3.4 0Z"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          </svg>
        </span>
        <p className="page-error__code">{code}</p>
        <h1 className="page-error__title">{title}</h1>
        <p className="page-error__message">{message}</p>
        {hint ? <p className="page-error__hint">{hint}</p> : null}
        <div className="page-error__actions">
          <Link href={homeHref} className="btn btn--primary">
            Retour a l&apos;accueil
          </Link>
          {onRetry ? (
            <button type="button" className="btn btn--secondary" onClick={onRetry}>
              Reessayer
            </button>
          ) : (
            <Link href={loginHref} className="btn btn--secondary">
              Aller a la connexion
            </Link>
          )}
        </div>
      </section>
    </main>
  );
}
