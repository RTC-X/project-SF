import os
from django.core.asgi import get_asgi_application
from channels.routing import ProtocolTypeRouter, URLRouter
from channels.auth import AuthMiddlewareStack

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'c2_dashboard.settings')

# Initialize Django ASGI application early to ensure AppRegistry is populated before importing consumers
django_asgi_app = get_asgi_application()

import dashboard.routing

application = ProtocolTypeRouter({
    "http": django_asgi_app,
    "websocket": AuthMiddlewareStack(
        URLRouter(
            dashboard.routing.websocket_urlpatterns
        )
    ),
})
