from .base import *  # noqa: F403
import os

DEBUG = True
ALLOWED_HOSTS = ["localhost", "127.0.0.1", "web", "host.docker.internal"]


def _load_dotenv() -> None:
    """Charge .env a la racine (PostgreSQL hote = meme base que Docker db)."""
    env_path = BASE_DIR / ".env"
    if not env_path.is_file():
        return
    for raw in env_path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


_load_dotenv()

_use_pg = os.environ.get("DJANGO_USE_POSTGRES", "").lower() in ("1", "true", "yes")
if _use_pg and os.environ.get("DJANGO_DB_HOST"):
    DATABASES = {
        "default": {
            "ENGINE": os.environ.get(
                "DJANGO_DB_ENGINE", "django.db.backends.postgresql"
            ),
            "NAME": os.environ.get("DJANGO_DB_NAME", "app"),
            "USER": os.environ.get("DJANGO_DB_USER", "app"),
            "PASSWORD": os.environ.get("DJANGO_DB_PASSWORD", ""),
            "HOST": os.environ["DJANGO_DB_HOST"],
            "PORT": os.environ.get("DJANGO_DB_PORT", "5432"),
        }
    }
else:
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.sqlite3",
            "NAME": BASE_DIR / "db.sqlite3",
        }
    }

EMAIL_BACKEND = "django.core.mail.backends.console.EmailBackend"

# Fallback django.contrib.admin en dev local
DJANGO_ADMIN_ENABLED = True