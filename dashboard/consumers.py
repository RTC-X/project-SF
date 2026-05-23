import json
from channels.generic.websocket import AsyncWebsocketConsumer
from channels.db import database_sync_to_async

class C2Consumer(AsyncWebsocketConsumer):
    async def connect(self):
        self.room_group_name = 'c2_fleet'
        self.bot_username = None

        # Join fleet channel group
        await self.channel_layer.group_add(
            self.room_group_name,
            self.channel_name
        )

        await self.accept()

        # IMMEDIATELY stream active bots to frontend on connect
        bots = await self.get_active_bots()
        await self.send(text_data=json.dumps({
            'type': 'fleet_update',
            'bots': bots
        }))

        # IMMEDIATELY stream last 30 telemetry logs to frontend on connect
        logs = await self.get_recent_logs()
        for log in reversed(logs):
            await self.send(text_data=json.dumps({
                'type': 'new_log',
                'log': log
            }))

    async def disconnect(self, close_code):
        # Leave fleet channel group
        await self.channel_layer.group_discard(
            self.room_group_name,
            self.channel_name
        )
        
        # Mark bot as offline if registered
        if getattr(self, 'bot_username', None):
            await self.set_bot_offline(self.bot_username)
            await self.broadcast_fleet_update()

    # Receive message from WebSocket (from frontends or Roblox bots)
    async def receive(self, text_data):
        try:
            data = json.loads(text_data)
            action = data.get('action')
            
            if action == 'register':
                # Registering active bots from Roblox client
                bot_id = data.get('username')
                self.bot_username = bot_id
                await self.update_bot_status(bot_id, 'Idle', data)
                await self.broadcast_fleet_update()
                
            elif action == 'command':
                # Relaying UI commands from control panels out to individual Roblox bots
                target_id = data.get('target_id')
                command = data.get('command')
                payload = data.get('payload', {})
                
                # Persist settings in the DB for persistence across page loads
                if command == 'syncConfig':
                    await self.save_bot_configuration(target_id, payload)
                
                await self.channel_layer.group_send(
                    self.room_group_name,
                    {
                        'type': 'relay_command',
                        'target_id': target_id,
                        'command': command,
                        'payload': payload
                    }
                )
                await self.broadcast_fleet_update()
            elif action == 'log':
                # Bot streaming live telemetries / logs
                username = data.get('username')
                self.bot_username = username
                event_type = data.get('event_type', 'General')
                message = data.get('message')
                
                log_data = await self.create_telemetry_log(username, event_type, message)
                if log_data:
                    await self.channel_layer.group_send(
                        self.room_group_name,
                        {
                            'type': 'broadcast_log',
                            'log': log_data
                        }
                    )
                    await self.broadcast_fleet_update()
        except Exception as e:
            print("WebSocket error in C2Consumer:", e)

    # Receive command broadcast from group to relay to active bot clients
    async def relay_command(self, event):
        await self.send(text_data=json.dumps({
            'type': 'command',
            'target_id': event['target_id'],
            'command': event['command'],
            'payload': event['payload']
        }))

    # Broadcast fleet updates
    async def fleet_update(self, event):
        await self.send(text_data=json.dumps({
            'type': 'fleet_update',
            'bots': event['bots']
        }))

    async def broadcast_fleet_update(self):
        bots = await self.get_active_bots()
        await self.channel_layer.group_send(
            self.room_group_name,
            {
                'type': 'fleet_update',
                'bots': bots
            }
        )

    @database_sync_to_async
    def get_recent_logs(self):
        from .models import TelemetryLog
        logs = TelemetryLog.objects.select_related('bot').order_by('-timestamp')[:30]
        return [
            {
                'id': log.id,
                'username': log.bot.username,
                'time': log.timestamp.strftime('%H:%M:%S'),
                'message': log.message
            }
            for log in logs
        ]

    @database_sync_to_async
    def get_active_bots(self):
        from .models import BotAccount, BotConfiguration
        user = self.scope.get('user')
        if user and user.is_authenticated:
            bots = BotAccount.objects.filter(owner=user)
        else:
            bots = BotAccount.objects.none()
        serialized = []
        for bot in bots:
            try:
                config = bot.config
                config_data = {
                    'farm_enabled': config.farm_enabled,
                    'snipe_enabled': config.snipe_enabled,
                    'active_areas': config.active_areas,
                    'target_enchant_sets': config.target_enchant_sets,
                    'whitelisted_uuids': config.whitelisted_uuids,
                }
            except BotConfiguration.DoesNotExist:
                config_data = {
                    'farm_enabled': False,
                    'snipe_enabled': False,
                    'active_areas': [],
                    'target_enchant_sets': [],
                    'whitelisted_uuids': [],
                }
            
            serialized.append({
                'id': str(bot.id),
                'username': bot.username,
                'status': bot.status,
                'level': bot.level,
                'money': float(bot.money),
                'session_time': bot.session_time,
                'bot_class': bot.bot_class,
                'quality': bot.quality,
                'rarity': bot.rarity,
                'mold': bot.mold,
                'backpack_items': bot.backpack_items,
                'config': config_data
            })
        return serialized

    @database_sync_to_async
    def update_bot_status(self, username, status, extra_data=None):
        from .models import BotAccount, BotConfiguration
        bot, created = BotAccount.objects.get_or_create(username=username)
        bot.status = status
        
        if extra_data and 'discord_id' in extra_data and extra_data['discord_id']:
            from allauth.socialaccount.models import SocialAccount
            try:
                social_acc = SocialAccount.objects.get(uid=str(extra_data['discord_id']), provider='discord')
                bot.owner = social_acc.user
            except SocialAccount.DoesNotExist:
                pass
        
        if extra_data:
            if 'level' in extra_data and extra_data['level'] is not None:
                bot.level = int(extra_data['level'])
            if 'money' in extra_data and extra_data['money'] is not None:
                bot.money = float(extra_data['money'])
            if 'bot_class' in extra_data and extra_data['bot_class']:
                bot.bot_class = extra_data['bot_class']
            if 'quality' in extra_data and extra_data['quality']:
                bot.quality = extra_data['quality']
            if 'rarity' in extra_data and extra_data['rarity']:
                bot.rarity = extra_data['rarity']
            if 'mold' in extra_data and extra_data['mold']:
                bot.mold = extra_data['mold']
            if 'backpack_items' in extra_data and extra_data['backpack_items']:
                bot.backpack_items = extra_data['backpack_items']
        
        # If new bot connecting and no backpack exists, populate premium gameplay placeholders
        if created or not bot.backpack_items:
            if not bot.backpack_items:
                bot.level = bot.level or 490
                bot.bot_class = bot.bot_class or "Unbeatable"
                bot.quality = bot.quality or "Spectacular"
                bot.rarity = bot.rarity or "Heavenly++"
                bot.mold = bot.mold or "Crystal"
                bot.backpack_items = [
                    {"uuid": "sword_92k", "name": "Ancient Broadsword", "traits": ["Ancient II", "Level 10"]},
                    {"uuid": "sword_41m", "name": "Fortune Katana", "traits": ["Fortune IV", "Level 25"]},
                    {"uuid": "sword_15x", "name": "Lightning Dagger", "traits": ["Swift I", "Level 14"]},
                ]
        bot.save()
        
        # Ensure configuration model exists cleanly
        if not BotConfiguration.objects.filter(bot=bot).exists():
            BotConfiguration.objects.create(
                bot=bot,
                farm_enabled=True,
                snipe_enabled=True,
                active_areas=[1, 2, 5, 12],
                target_enchant_sets=["Ancient + Fortune + Insight"],
                whitelisted_uuids=["sword_92k"]
            )

    @database_sync_to_async
    def set_bot_offline(self, username):
        from .models import BotAccount
        try:
            bot = BotAccount.objects.get(username=username)
            bot.status = 'Offline'
            bot.save()
        except BotAccount.DoesNotExist:
            pass

    async def broadcast_log(self, event):
        await self.send(text_data=json.dumps({
            'type': 'new_log',
            'log': event['log']
        }))

    @database_sync_to_async
    def create_telemetry_log(self, username, event_type, message):
        from .models import BotAccount, TelemetryLog
        try:
            bot = BotAccount.objects.get(username=username)
            if event_type in ['Farming', 'Sniping', 'Idle']:
                bot.status = event_type
                if event_type == 'Farming':
                    bot.money = float(bot.money) + 12.50
                bot.session_time = (bot.session_time or 0) + 6
                bot.save()
                
            log = TelemetryLog.objects.create(bot=bot, event_type=event_type, message=message)
            return {
                'id': log.id,
                'username': bot.username,
                'time': log.timestamp.strftime('%H:%M:%S'),
                'message': log.message
            }
        except BotAccount.DoesNotExist:
            # If the bot is not registered yet, we create it dynamically first
            bot = BotAccount.objects.create(username=username, status='Idle')
            if event_type in ['Farming', 'Sniping', 'Idle']:
                bot.status = event_type
                bot.save()
                
            log = TelemetryLog.objects.create(bot=bot, event_type=event_type, message=message)
            return {
                'id': log.id,
                'username': bot.username,
                'time': log.timestamp.strftime('%H:%M:%S'),
                'message': log.message
            }

    @database_sync_to_async
    def save_bot_configuration(self, bot_id, payload):
        from .models import BotAccount, BotConfiguration
        try:
            bot = BotAccount.objects.get(id=bot_id)
            config, _ = BotConfiguration.objects.get_or_create(bot=bot)
            if 'farm_enabled' in payload:
                config.farm_enabled = payload['farm_enabled']
            if 'snipe_enabled' in payload:
                config.snipe_enabled = payload['snipe_enabled']
            if 'active_areas' in payload:
                config.active_areas = payload['active_areas']
            if 'target_enchant_sets' in payload:
                config.target_enchant_sets = payload['target_enchant_sets']
            if 'whitelisted_uuids' in payload:
                config.whitelisted_uuids = payload['whitelisted_uuids']
            config.save()
            
            # Also update bot's direct game telemetry fields if they were modified/passed in bulk/direct edit
            if 'bot_class' in payload and payload['bot_class']:
                bot.bot_class = payload['bot_class']
            if 'quality' in payload and payload['quality']:
                bot.quality = payload['quality']
            if 'rarity' in payload and payload['rarity']:
                bot.rarity = payload['rarity']
            if 'mold' in payload and payload['mold']:
                bot.mold = payload['mold']
            if 'level' in payload and payload['level']:
                bot.level = int(payload['level'])
            bot.save()
        except Exception as e:
            print("Error persisting bot configuration:", e)
