"""
Django settings for c2_dashboard project.
"""

import os
from pathlib import Path
import environ

# Initialize environment variables reader
env = environ.Env(
    DEBUG=(bool, False)
)

BASE_DIR = Path(__file__).resolve().parent.parent

# Read .env file if it exists
environ.Env.read_env(os.path.join(BASE_DIR, '.env'))

SECRET_KEY = env('SECRET_KEY', default='django-insecure-coolify-c2-dashboard-super-secret-key-123')
DEBUG = env('DEBUG', default=True)

ALLOWED_HOSTS = env.list('ALLOWED_HOSTS', default=['*'])

INSTALLED_APPS = [
    'daphne', # Must be before django.contrib.staticfiles
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    
    # django-allauth
    'allauth',
    'allauth.account',
    'allauth.socialaccount',
    'allauth.socialaccount.providers.discord',
    
    # Core app
    'dashboard',
    
    # Utilities
    'channels',
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'whitenoise.middleware.WhiteNoiseMiddleware', # WhiteNoise for static files serving in Docker
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'allauth.account.middleware.AccountMiddleware', # Required by django-allauth
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

AUTHENTICATION_BACKENDS = [
    'django.contrib.auth.backends.ModelBackend',
    'allauth.account.auth_backends.AuthenticationBackend',
]

ROOT_URLCONF = 'c2_dashboard.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [BASE_DIR / 'templates'],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

WSGI_APPLICATION = 'c2_dashboard.wsgi.application'
ASGI_APPLICATION = 'c2_dashboard.asgi.application'

# Channel layer for WebSockets (using In-Memory for development and fallback, 
# can easily swap to Redis by configuring CHANNEL_LAYERS if needed in prod)
CHANNEL_LAYERS = {
    'default': {
        'BACKEND': 'channels.layers.InMemoryChannelLayer',
    },
}

# Database configuration
# Connects to PostgreSQL if variables exist, else falls back to SQLite
if env('DB_HOST', default=''):
    DATABASES = {
        'default': {
            'ENGINE': 'django.db.backends.postgresql',
            'NAME': env('DB_NAME', default='c2_db'),
            'USER': env('DB_USER', default='c2_admin'),
            'PASSWORD': env('DB_PASSWORD', default='c2_secure_pass_998'),
            'HOST': env('DB_HOST', default='db'),
            'PORT': env('DB_PORT', default='5432'),
        }
    }
else:
    DATABASES = {
        'default': {
            'ENGINE': 'django.db.backends.sqlite3',
            'NAME': BASE_DIR / 'db.sqlite3',
        }
    }

AUTH_PASSWORD_VALIDATORS = [
    {
        'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator',
    },
]

LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'UTC'
USE_I18N = True
USE_TZ = True

STATIC_URL = 'static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'
STATICFILES_STORAGE = 'whitenoise.storage.CompressedManifestStaticFilesStorage'

DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

LOGIN_URL = 'login'
LOGIN_REDIRECT_URL = 'dashboard'
LOGOUT_REDIRECT_URL = 'login'

# django-allauth configs for seamless Discord OAuth
SOCIALACCOUNT_PROVIDERS = {
    'discord': {
        'APP': {
            'client_id': env('DISCORD_CLIENT_ID', default=''),
            'secret': env('DISCORD_CLIENT_SECRET', default=''),
            'key': ''
        },
        'SCOPE': ['identify'],
    }
}

# Simplify social login flow (skip intermediate signup form)
SOCIALACCOUNT_AUTO_SIGNUP = True
ACCOUNT_SIGNUP_REDIRECT_URL = 'dashboard'

