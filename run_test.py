import os, django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'c2_dashboard.settings')
django.setup()
from django.template.loader import render_to_string
from dashboard.models import GlobalMetadata
meta = GlobalMetadata.objects.get(key='game_data')
try:
  render_to_string('dashboard.html', {'game_data_json': meta.data})
  print('Template rendered successfully')
except Exception as e:
  print('ERROR:', e)
