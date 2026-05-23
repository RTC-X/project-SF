from django.contrib import admin
from django.urls import path, include

urlpatterns = [
    path('admin/', admin.site.urls),
    path('accounts/', include('allauth.urls')), # Allauth standard flows (e.g. login, provider redirect)
    path('', include('dashboard.urls')),
]
