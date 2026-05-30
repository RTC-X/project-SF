from django.contrib import admin
from .models import BotAccount, BotConfiguration, TelemetryLog

@admin.register(BotAccount)
class BotAccountAdmin(admin.ModelAdmin):
    list_display = ('username', 'status', 'level', 'money', 'last_seen', 'owner')
    list_filter = ('status', 'owner')
    search_fields = ('username',)

@admin.register(BotConfiguration)
class BotConfigurationAdmin(admin.ModelAdmin):
    list_display = ('bot', 'FarmEnabled', 'SnipeEnabled')

@admin.register(TelemetryLog)
class TelemetryLogAdmin(admin.ModelAdmin):
    list_display = ('bot', 'event_type', 'timestamp', 'message')
    list_filter = ('event_type', 'timestamp')
    search_fields = ('bot__username', 'message')
