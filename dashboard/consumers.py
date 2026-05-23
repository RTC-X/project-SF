import json
from channels.generic.websocket import AsyncWebsocketConsumer
from channels.db import database_sync_to_async

class C2Consumer(AsyncWebsocketConsumer):
    async def connect(self):
        self.room_group_name = 'c2_fleet'

        # Join fleet channel group
        await self.channel_layer.group_add(
            self.room_group_name,
            self.channel_name
        )

        await self.accept()

    async def disconnect(self, close_code):
        # Leave fleet channel group
        await self.channel_layer.group_discard(
            self.room_group_name,
            self.channel_name
        )

    # Receive message from WebSocket (from frontends or Roblox bots)
    async def receive(self, text_data):
        try:
            data = json.loads(text_data)
            action = data.get('action')
            
            if action == 'register':
                # Registering active bots from Roblox client
                bot_id = data.get('username')
                await self.update_bot_status(bot_id, 'Idle')
                await self.broadcast_fleet_update()
                
            elif action == 'command':
                # Relaying UI commands from control panels out to individual Roblox bots
                target_id = data.get('target_id')
                command = data.get('command')
                payload = data.get('payload', {})
                
                await self.channel_layer.group_send(
                    self.room_group_name,
                    {
                        'type': 'relay_command',
                        'target_id': target_id,
                        'command': command,
                        'payload': payload
                    }
                )
            elif action == 'log':
                # Bot streaming live telemetries / logs
                username = data.get('username')
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
    def get_active_bots(self):
        from .models import BotAccount
        bots = BotAccount.objects.exclude(status='Offline')
        return [
            {
                'id': str(bot.id),
                'username': bot.username,
                'status': bot.status,
                'level': bot.level,
                'money': float(bot.money),
                'session_time': bot.session_time
            }
            for bot in bots
        ]

    @database_sync_to_async
    def update_bot_status(self, username, status):
        from .models import BotAccount
        bot, created = BotAccount.objects.get_or_create(username=username)
        bot.status = status
        bot.save()

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
            log = TelemetryLog.objects.create(bot=bot, event_type=event_type, message=message)
            return {
                'id': log.id,
                'username': bot.username,
                'time': log.timestamp.strftime('%H:%M:%S'),
                'message': log.message
            }
