from django.urls import re_path
from . import consumers

websocket_urlpatterns = [
    re_path(r'ws/c2/$', consumers.C2Consumer.as_asgi()),
]
