"""Logique d'ecriture (couche service).

Les invariants metier et transactions vivent ici, pas dans les vues ni l'API.
"""

from __future__ import annotations

from typing import TypedDict


class StaffPingResult(TypedDict):
    """Resultat du ping workspace staff."""

    status: str
    message: str


def example_action() -> str:
    """Exemple de service a remplacer par une regle metier reelle.

    Returns:
        Identifiant symbolique du service d'exemple.
    """
    return "service"


def ping_staff_workspace() -> StaffPingResult:
    """Confirme que le workspace staff est joignable (demo mutation HTMX).

    Returns:
        Statut et message affiches via partial flash.
    """
    return {
        "status": "ok",
        "message": "Workspace staff pret (service ping_staff_workspace).",
    }