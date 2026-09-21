"""JWT utilitaires pour l''admin panel (superuser)."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import Any

import jwt
from django.conf import settings
from django.contrib.auth import get_user_model
from ninja.security import HttpBearer

User = get_user_model()

ACCESS_LIFETIME = timedelta(hours=8)
REFRESH_LIFETIME = timedelta(days=1)
ALGORITHM = "HS256"


def _encode(payload: dict[str, Any], lifetime: timedelta) -> str:
    now = datetime.now(tz=UTC)
    body = {
        **payload,
        "exp": now + lifetime,
        "iat": now,
    }
    return jwt.encode(body, settings.SECRET_KEY, algorithm=ALGORITHM)


def create_token_pair(user: User) -> dict[str, str]:
    """Genere une paire access/refresh JWT (superuser actif uniquement)."""
    if not user.is_active or not user.is_superuser:
        raise PermissionError("JWT admin reserve aux superusers actifs.")
    base = {"user_id": user.pk, "username": user.username}
    return {
        "access": _encode({**base, "type": "access"}, ACCESS_LIFETIME),
        "refresh": _encode({**base, "type": "refresh"}, REFRESH_LIFETIME),
    }


class AdminJWTAuth(HttpBearer):
    """Authentification Bearer JWT - superuser requis."""

    def authenticate(self, request, token: str) -> User | None:
        try:
            payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[ALGORITHM])
        except jwt.PyJWTError:
            return None
        if payload.get("type") != "access":
            return None
        user_id = payload.get("user_id")
        if not user_id:
            return None
        try:
            user = User.objects.get(pk=user_id)
        except User.DoesNotExist:
            return None
        if not user.is_active or not user.is_superuser:
            return None
        return user