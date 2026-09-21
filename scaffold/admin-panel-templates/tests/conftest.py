"""Fixtures Pytest pour les tests admin_panel."""

from __future__ import annotations

import pytest
from django.test import Client


@pytest.fixture
def api_client() -> Client:
    """Client Django pour tests API."""
    return Client()


@pytest.fixture
def superuser(db):
    """Superuser Django pour tests admin."""
    from django.contrib.auth import get_user_model

    User = get_user_model()
    return User.objects.create_superuser(
        username="admin",
        email="admin@test.local",
        password="admin-secret",
    )


@pytest.fixture
def api_client_superuser(api_client: Client, superuser) -> Client:
    """Client authentifie JWT superuser."""
    from apps.admin_panel.auth import create_token_pair

    tokens = create_token_pair(superuser)
    api_client.defaults["HTTP_AUTHORIZATION"] = f"Bearer {tokens['access']}"
    return api_client
