import uuid
import secrets
from django.db import models

class BotAccount(models.Model):
    STATUS_CHOICES = [
        ('Farming', 'Farming'),
        ('Sniping', 'Sniping'),
        ('Idle', 'Idle'),
        ('Dead', 'Dead'),
        ('Offline', 'Offline'),
    ]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    username = models.CharField(max_length=100, unique=True, help_text="Roblox Username")
    roblox_id = models.BigIntegerField(null=True, blank=True)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='Offline')
    last_seen = models.DateTimeField(auto_now=True)
    level = models.IntegerField(default=1)
    money = models.DecimalField(max_digits=18, decimal_places=2, default=0.0)
    session_time = models.IntegerField(default=0, help_text="Session time in seconds")
    c2_token = models.CharField(max_length=64, unique=True, blank=True, help_text="Authentication token for Roblox bot websocket connection")

    def save(self, *args, **kwargs):
        if not self.c2_token:
            self.c2_token = secrets.token_hex(32)
        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.username} ({self.status})"

class BotConfiguration(models.Model):
    bot = models.OneToOneField(BotAccount, on_delete=models.CASCADE, related_name='config')
    farm_enabled = models.BooleanField(default=False)
    sniper_enabled = models.BooleanField(default=False)
    
    # Custom configurations stored cleanly in JSON format
    active_areas = models.JSONField(default=list, blank=True, help_text="List of active area IDs")
    target_enchant_sets = models.JSONField(default=list, blank=True, help_text="Target sets of enchants (wishlist)")
    whitelisted_uuids = models.JSONField(default=list, blank=True, help_text="Protected sword UUIDs/names")
    
    webhook_url = models.URLField(max_length=500, blank=True)
    webhook_enabled = models.BooleanField(default=False)

    def __str__(self):
        return f"Config for {self.bot.username}"

class TelemetryLog(models.Model):
    bot = models.ForeignKey(BotAccount, on_delete=models.CASCADE, related_name='logs')
    timestamp = models.DateTimeField(auto_now_add=True)
    event_type = models.CharField(max_length=50, help_text="e.g. drop, snipe, teleport")
    message = models.TextField()

    class Meta:
        ordering = ['-timestamp']

    def __str__(self):
        return f"[{self.timestamp.strftime('%Y-%m-%d %H:%M:%S')}] {self.bot.username}: {self.message}"
