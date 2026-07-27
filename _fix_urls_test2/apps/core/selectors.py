"""Lecture / agregations (couche selector).

Les querysets optimises (select_related / prefetch) vivent ici.
"""

from __future__ import annotations

from typing import TypedDict


class StaffDemoItem(TypedDict):
    """Element de demonstration pour le back-office HTMX."""

    id: int
    title: str
    status: str
    summary: str


_STAFF_DEMO_ITEMS: tuple[StaffDemoItem, ...] = (
    {
        "id": 1,
        "title": "Revue permissions staff",
        "status": "ouvert",
        "summary": "Verifier les acces back-office et les mixins LoginRequired.",
    },
    {
        "id": 2,
        "title": "Audit partials HTMX",
        "status": "en cours",
        "summary": "Controle hx-target / hx-swap et indicateurs .htmx-request.",
    },
    {
        "id": 3,
        "title": "CSRF mutations",
        "status": "fait",
        "summary": "Les POST HTMX doivent envoyer le token (meta + hx-headers).",
    },
)


def example_selector() -> str:
    """Exemple de selector a remplacer par une lecture metier.

    Returns:
        Identifiant symbolique du selector d'exemple.
    """
    return "selector"


def list_staff_demo_items(*, query: str = "") -> list[StaffDemoItem]:
    """Liste les elements demo du back-office, avec filtre texte optionnel.

    Args:
        query: Filtre insensible a la casse sur titre / statut / resume.

    Returns:
        Liste d'items demo (copie superficielle).
    """
    needle = (query or "").strip().lower()
    if not needle:
        return [dict(item) for item in _STAFF_DEMO_ITEMS]
    return [
        dict(item)
        for item in _STAFF_DEMO_ITEMS
        if needle in item["title"].lower()
        or needle in item["status"].lower()
        or needle in item["summary"].lower()
    ]


def get_staff_demo_item(item_id: int) -> StaffDemoItem | None:
    """Retourne un element demo par identifiant.

    Args:
        item_id: Identifiant numerique de l'element.

    Returns:
        L'item trouve, ou None.
    """
    for item in _STAFF_DEMO_ITEMS:
        if item["id"] == item_id:
            return dict(item)
    return None