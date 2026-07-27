"""Agregation des settings par environnement (DJANGO_ENV=dev|qua|prod)."""
import os

_env = os.environ.get("DJANGO_ENV", "dev").lower()
if _env == "prod":
    from .prod import *  # noqa: F403
elif _env == "qua":
    from .qua import *  # noqa: F403
else:
    from .dev import *  # noqa: F403