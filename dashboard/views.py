from django.shortcuts import render, redirect
from django.contrib.auth import logout as auth_logout
from django.contrib.auth.decorators import login_required

import requests
import hashlib
from django.conf import settings

def index_view(request):
    sf_icon_url = None
    try:
        response = requests.get(
            'https://thumbnails.roblox.com/v1/places/gameicons?placeIds=82432929049078&returnPolicy=PlaceHolder&size=150x150&format=Png',
            timeout=2.0
        )
        if response.status_code == 200:
            data = response.json()
            if data and 'data' in data and len(data['data']) > 0:
                sf_icon_url = data['data'][0].get('imageUrl')
    except Exception:
        pass
        
    context = {
        'sf_icon_url': sf_icon_url or ''
    }
    return render(request, 'index.html', context)

def login_view(request):
    if request.user.is_authenticated:
        return redirect('dashboard')
    return render(request, 'login.html')

@login_required
def dashboard_view(request):
    user_id = request.user.id
    secret = getattr(settings, 'SECRET_KEY', 'default_secret')
    user_api_key = f"c2_usr_{hashlib.sha256(f'{user_id}:{secret}'.encode()).hexdigest()[:16]}"
    return render(request, 'dashboard.html', {'user_api_key': user_api_key})

def logout_view(request):
    auth_logout(request)
    return redirect('index')

from django.http import JsonResponse
from .models import GlobalMetadata

def metadata_api_view(request):
    try:
        meta = GlobalMetadata.objects.get(key='game_data')
        return JsonResponse({"success": True, "data": meta.data})
    except GlobalMetadata.DoesNotExist:
        return JsonResponse({"success": False, "error": "Metadata not initialized"}, status=404)
