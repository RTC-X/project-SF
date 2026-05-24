import uuid
import secrets
import requests
from django.db import models
from django.contrib.auth.models import User
from django.dispatch import receiver
from django.conf import settings
from allauth.socialaccount.signals import pre_social_login

class BotAccount(models.Model):
    STATUS_CHOICES = [
        ('Farming', 'Farming'),
        ('Sniping', 'Sniping'),
        ('Idle', 'Idle'),
        ('Dead', 'Dead'),
        ('Offline', 'Offline'),
    ]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    owner = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True, related_name='bots', help_text="Discord user owner")
    username = models.CharField(max_length=100, unique=True, help_text="Roblox Username")
    roblox_id = models.BigIntegerField(null=True, blank=True)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='Offline')
    last_seen = models.DateTimeField(auto_now=True)
    level = models.IntegerField(default=1)
    money = models.FloatField(default=0.0, help_text="Supports up to 10^308 for massive simulator values")
    session_time = models.IntegerField(default=0, help_text="Session time in seconds")
    c2_token = models.CharField(max_length=64, unique=True, blank=True, help_text="Authentication token for Roblox bot websocket connection")
    
    # Premium C2 Gaming Telemetries
    bot_class = models.CharField(max_length=100, default='Unbeatable', help_text="Ascender Class")
    quality = models.CharField(max_length=100, default='Spectacular', help_text="Ascender Quality")
    rarity = models.CharField(max_length=100, default='Heavenly++', help_text="Ascender Rarity")
    mold = models.CharField(max_length=100, default='Crystal', help_text="Ascender Mold")
    backpack_items = models.JSONField(default=list, blank=True, help_text="Roblox in-game inventory backpack items")

    def save(self, *args, **kwargs):
        if not self.c2_token:
            self.c2_token = secrets.token_hex(32)
        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.username} ({self.status})"

class BotConfiguration(models.Model):
    bot = models.OneToOneField(BotAccount, on_delete=models.CASCADE, related_name='config')
    farm_enabled = models.BooleanField(default=False)
    snipe_enabled = models.BooleanField(default=False)
    
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

# ==============================================================================
# GLOBAL GAME METADATA
# ==============================================================================

class GlobalMetadata(models.Model):
    """
    Stores the scraped game data (Areas, Enchants) uploaded by the Admin Scraper.
    Using a flexible JSONField allows new game mechanics to be added without DB migrations.
    """
    key = models.CharField(max_length=50, primary_key=True, default='game_data')
    data = models.JSONField(default=dict, blank=True, help_text="Stores the JSON payload containing Areas, Enchants, Molds, etc.")
    last_updated = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Global Metadata (Updated: {self.last_updated.strftime('%Y-%m-%d %H:%M')})"

# ==============================================================================
# DISCORD OAUTH AUTO-JOIN GUILD SIGNAL RECEIVER
# ==============================================================================

@receiver(pre_social_login)
def auto_join_discord_server(sender, request, sociallogin, **kwargs):
    # Triggers right before a user completes authentication via Discord OAuth
    if sociallogin.account.provider != 'discord':
        return
        
    bot_token = getattr(settings, 'DISCORD_BOT_TOKEN', '')
    guild_id = getattr(settings, 'DISCORD_GUILD_ID', '')
    
    if not bot_token or not guild_id:
        return
        
    access_token = sociallogin.token.token
    user_uid = sociallogin.account.uid
    
    # Request endpoint to programmatically join the user into the server
    url = f"https://discord.com/api/v10/guilds/{guild_id}/members/{user_uid}"
    headers = {
        "Authorization": f"Bot {bot_token}",
        "Content-Type": "application/json"
    }
    data = {
        "access_token": access_token
    }
    
    try:
        response = requests.put(url, headers=headers, json=data, timeout=8)
        if response.status_code in [201, 204]:
            print(f"[Discord OAuth] User {user_uid} joined server {guild_id} successfully (Status: {response.status_code})")
        else:
            print(f"[Discord OAuth] Failed to join user {user_uid} to server {guild_id}: {response.status_code} - {response.text}")
    except Exception as e:
        print(f"[Discord OAuth] Error calling auto-join API: {str(e)}")
