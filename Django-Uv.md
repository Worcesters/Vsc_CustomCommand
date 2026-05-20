# 🏁 Démarrage rapide

## Installation

``` bash
# macOS / Linux
curl -LsSf https://astral.sh/uv/install.sh | sh

# Windows (PowerShell)
powershell -c "ir https://astral.sh/uv/install.ps1 | iex"
```

## 🏗️ Étape 1 : Initialisation de l'environnement avec uv
On crée le dossier, on initialise le projet et on installe toutes les briques nécessaires.

# 1. Créer le dossier et entrer dedans
``` bash
mkdir mon_projet_pro && cd mon_projet_pro
```

# 2. Initialiser le projet avec uv
``` bash
uv init
```

# 3. Ajouter les dépendances (Framework, API, Statics, Config)
``` bash
uv add django djangorestframework whitenoise django-environ
```

# 4. Ajouter les outils de développement
``` bash
uv add --dev ruff
```

Tu auras besoin de relancer uv sync dans trois scénarios principaux :

Modification manuelle : Si tu ajoutes manuellement une ligne dans la section [project.dependencies] de ton pyproject.toml.

Mise à jour Git : Si tu fais un git pull et qu'un collègue a mis à jour les dépendances (le fichier uv.lock aura changé).

Nettoyage : Si tu penses avoir cassé quelque chose dans ton .venv et que tu veux repartir sur une base saine et conforme au lockfile.
```bash
yv sync
```

## ⚙️ Étape 2 : Structure du projet Django
On crée la structure "Pro" avec le dossier config et une application users.

# Créer le projet Django dans le dossier 'config'
``` bash
uv run django-admin startproject config .
```

# Créer le dossier pour les apps et l'app users
``` bash
mkdir apps
ni apps/__init__.py
uv run python manage.py startapp users apps/users
```

## 👤 Étape 3 : Le Custom User Model (Obligatoire)
Dans apps/users/models.py, on crée l'utilisateur basé sur l'email :
``` python
from django.contrib.auth.models import AbstractUser
from django.db import models

class User(AbstractUser):
    username = None
    email = models.EmailField("Email address", unique=True)

    USERNAME_FIELD = "email"
    REQUIRED_FIELDS = []

    def __str__(self):
        return self.email
```

## 🛠️ Étape 4 : Configuration des Settings (config/settings.py)
Modifie ton fichier pour intégrer tout le monde (DRF, WhiteNoise, User) :

``` python

import environ
import os
from pathlib import Path

env = environ.Env(DEBUG=(bool, False))
BASE_DIR = Path(__file__).resolve().parent.parent
environ.Env.read_env(os.path.join(BASE_DIR, '.env'))

# --- Applications ---
INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    # Libs Tierces
    'rest_framework',
    'whitenoise.runserver_nostatic', # Pour le dev
    # Mes Apps
    'apps.users',
]

# --- Middleware (WhiteNoise en 2ème position !) ---
MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'whitenoise.middleware.WhiteNoiseMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    # ...
]

# --- Auth ---
AUTH_USER_MODEL = 'users.User'

# --- Static Files (WhiteNoise) ---
STATIC_URL = 'static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'
STATICFILES_DIRS = [BASE_DIR / 'static']

STORAGES = {
    "staticfiles": {
        "BACKEND": "whitenoise.storage.CompressedManifestStaticFilesStorage",
    },
}

# --- DRF ---
REST_FRAMEWORK = {
    'DEFAULT_PERMISSION_CLASSES': [
        'rest_framework.permissions.IsAuthenticatedOrReadOnly',
    ],
}

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [BASE_DIR / 'templates'], # <-- VERIFIE CETTE LIGNE
        'APP_DIRS': True,
        # ...
    },
]
```

## ⚡ Étape 5 : Exemple HTMX + DRF (Le combo Full-Stack)
Voici comment faire communiquer HTMX avec une API Django.

1. La Vue (Simple HTML + JSON)
Dans apps/users/views.py :

``` python

from django.shortcuts import render
from rest_framework.decorators import api_view
from rest_framework.response import Response

def index(request):
    return render(request, "index.html")

@api_view(['GET'])
def api_hello(request):
    # Si c'est HTMX qui appelle, on peut renvoyer du HTML partiel
    if request.headers.get('HX-Request'):
        return Response("<div>🚀 Réponse de l'API via HTMX !</div>")
    # Sinon on renvoie du JSON classique
    return Response({"message": "Hello from DRF"})
```

2. Le Template avec HTMX
Crée un dossier static/ à la racine et templates/index.html.

``` HTML

<script src="https://unpkg.com/htmx.org@1.9.10"></script>

<h1>Mon Projet Full Stack</h1>

<button hx-get="/api/hello/"
        hx-target="#resultat"
        style="padding: 10px; background: #007bff; color: white;">
    Appeler l'API avec HTMX
</button>

<div id="resultat" style="margin-top: 20px;"></div>
```

3. Dans le apps/users/apps.py
```python
from django.apps import AppConfig


class UsersConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'apps.users' # <--- AJOUTE 'apps.' ICI

```
## Etape 6 : Routing

1. Créer le fichier apps/users/urls.py
C'est ici qu'on définit les routes spécifiques à ton application "users".

``` Python

from django.urls import path
from . import views

urlpatterns = [
    path('', views.index, name='index'),  # Racine de l'app (la page custom)
    path('api/hello/', views.api_hello, name='api_hello'), # L'URL que HTMX appelle
]
```

2. Modifier le fichier config/urls.py
C'est le fichier "maître". Tu dois lui dire d'inclure les URLs que tu viens de créer.

```Python

from django.contrib import admin
from django.urls import path, include

urlpatterns = [
    path('admin/', admin.site.urls),
    path('', include('apps.users.urls')), # On branche l'app users sur la racine
]
```

## 🚀 Étape 7 : Finalisation et Lancement
``` Bash

# 1. Créer le fichier .env
echo "DEBUG=True\nSECRET_KEY=dev-key-123\nALLOWED_HOSTS=*" > .env

# 2. Migrations
uv run python manage.py makemigrations users
uv run python manage.py migrate

# 3. Collecter les statiques (test WhiteNoise)
uv run python manage.py collectstatic --noinput

# 4. Lancer !
uv run python manage.py runserver
```

## Résumé : Le Workflow "Magique"
Voici comment les outils communiquent entre eux lors d'une action utilisateur (ex: cliquer sur "S'abonner") :

1. **Utilisateur** clique sur le bouton (HTMX intercepte le clic).

2. **HTMX** envoie une requête discrète en arrière-plan à Django.

3. **Django** traite la logique (via un Service).

4. **DRF** (optionnel) valide les données.

5. **Django** renvoie juste le petit morceau de HTML du bouton (ex: "Abonné ✅").

6. **HTMX** remplace l'ancien bouton par le nouveau sans que l'utilisateur ne voie la page sauter ou recharger.

C'est la puissance du Full Stack : tu as la réactivité de React avec la simplicité de Django.