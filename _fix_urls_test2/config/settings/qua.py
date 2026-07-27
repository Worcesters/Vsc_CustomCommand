from .base import *  # noqa: F403
import os

DEBUG = False
ALLOWED_HOSTS = os.environ.get("DJANGO_ALLOWED_HOSTS", "localhost").split(",")

# Meme exigence que prod : pas de SECRET_KEY scaffold / JWT forgeable.
_INSECURE_SECRET_KEYS = frozenset(
    {
        "",
        "dev-only-change-me",
        "dev-local-change-me",
        "dev-docker-only",
        "change-me",
    }
)
SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY", "")
if SECRET_KEY in _INSECURE_SECRET_KEYS:
    raise RuntimeError(
        "DJANGO_SECRET_KEY doit etre defini avec une valeur non triviale (qua)."
    )

DATABASES = {
    "default": {
        "ENGINE": os.environ.get("DJANGO_DB_ENGINE", "django.db.backends.postgresql"),
        "NAME": os.environ.get("DJANGO_DB_NAME", "app"),
        "USER": os.environ.get("DJANGO_DB_USER", "app"),
        "PASSWORD": os.environ.get("DJANGO_DB_PASSWORD", ""),
        "HOST": os.environ.get("DJANGO_DB_HOST", "db"),
        "PORT": os.environ.get("DJANGO_DB_PORT", "5432"),
    }
}