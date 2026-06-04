from django.shortcuts import render, redirect
from django.contrib.auth import logout as auth_logout
from django.contrib.auth.decorators import login_required
from django.conf import settings
from django.http import JsonResponse, Http404
from django.contrib.auth.models import User
import requests
import hashlib

from .models import GlobalMetadata

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
    secret = settings.SECRET_KEY
    user_api_key = f"c2_usr_{hashlib.sha256(f'{user_id}:{secret}'.encode()).hexdigest()[:16]}"
    
    try:
        meta = GlobalMetadata.objects.get(key='game_data')
        game_data_json = meta.data
    except Exception:
        game_data_json = {}
        
    return render(request, 'dashboard.html', {'user_api_key': user_api_key, 'game_data_json': game_data_json})

def logout_view(request):
    auth_logout(request)
    return redirect('index')

def is_valid_api_key(api_key):
    if not api_key:
        return False
    secret = settings.SECRET_KEY
    for user in User.objects.all():
        expected_key = f"c2_usr_{hashlib.sha256(f'{user.id}:{secret}'.encode()).hexdigest()[:16]}"
        if api_key == expected_key:
            return True
    return False

def metadata_api_view(request):
    api_key = request.GET.get('api_key')
    
    # Strictly require a valid API key to access this endpoint
    if not is_valid_api_key(api_key):
        raise Http404("Page not found")
        
    try:
        meta = GlobalMetadata.objects.get(key='game_data')
        return JsonResponse({"success": True, "data": meta.data}, json_dumps_params={'indent': 4})
    except GlobalMetadata.DoesNotExist:
        raise Http404("Page not found")
