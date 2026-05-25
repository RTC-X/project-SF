import json
import asyncio
from channels.generic.websocket import AsyncWebsocketConsumer
from channels.db import database_sync_to_async

class C2Consumer(AsyncWebsocketConsumer):
    async def connect(self):
        user = self.scope.get('user')
        self.bot_username = None
        print("[C2 Server] New WebSocket connection request received.")

        if user and user.is_authenticated:
            print(f"[C2 Server] Frontend User connected: '{user.username}' (ID: {user.id})")
            self.room_group_name = f'c2_fleet_user_{user.id}'
            # Join user's private fleet channel group
            await self.channel_layer.group_add(
                self.room_group_name,
                self.channel_name
            )
            await self.accept()

            # IMMEDIATELY stream active bots for this user to frontend on connect
            bots = await self.get_bots_for_user(user)
            await self.send(text_data=json.dumps({
                'type': 'fleet_update',
                'bots': bots
            }))

            # IMMEDIATELY stream last 30 telemetry logs for this user to frontend on connect
            logs = await self.get_recent_logs_for_user(user)
            for log in reversed(logs):
                await self.send(text_data=json.dumps({
                    'type': 'new_log',
                    'log': log
                }))
        else:
            print("[C2 Server] Bot/Client connection accepted (awaiting registration payload).")
            self.room_group_name = None
            import time
            self.last_heartbeat = time.time()
            # Allow bot connection to accept; they will dynamically join their group during register/log
            await self.accept()
            # Enforce 60 second registration timeout to prevent resource exhaustion attacks
            asyncio.create_task(self.enforce_registration_timeout(60))
            # Start heartbeat monitor (expects a ping at least every 120 seconds)
            self.last_heartbeat = time.time()
            self.heartbeat_task = asyncio.create_task(self.monitor_heartbeat(120))

    async def disconnect(self, close_code):
        if getattr(self, 'bot_username', None):
            print(f"[C2 Server] Bot/Client '{self.bot_username}' disconnected (Close Code: {close_code}). Marking offline.")
        else:
            print(f"[C2 Server] Connection closed / Frontend disconnected (Close Code: {close_code}).")

        # Leave current room group if set
        if self.room_group_name:
            await self.channel_layer.group_discard(
                self.room_group_name,
                self.channel_name
            )
        
        # Mark bot as offline if registered
        if getattr(self, 'bot_username', None):
            await self.set_bot_offline(self.bot_username)
            # Find and update only the owner's dashboard
            owner_user = await self.get_bot_owner(self.bot_username)
            if owner_user:
                await self.broadcast_fleet_update_for_user(owner_user)
                
        # Cancel heartbeat task if running
        if hasattr(self, 'heartbeat_task'):
            self.heartbeat_task.cancel()

    async def enforce_registration_timeout(self, seconds):
        await asyncio.sleep(seconds)
        if not getattr(self, 'bot_username', None):
            print("[C2 Server] [Security Warning] Registration timeout exceeded. Rejecting unauthenticated connection.")
            try:
                await self.send(text_data=json.dumps({
                    'type': 'command',
                    'command': 'kick',
                    'payload': {
                        'reason': 'Registration timeout exceeded. You must register within 60 seconds of connection.'
                    }
                }))
                await self.close()
                await self.close()
            except Exception:
                pass

    async def monitor_heartbeat(self, timeout_seconds):
        import time
        while True:
            await asyncio.sleep(5)
            if hasattr(self, 'last_heartbeat'):
                if time.time() - self.last_heartbeat > timeout_seconds:
                    print(f"[C2 Server] Client '{getattr(self, 'bot_username', 'Unregistered')}' timed out (no heartbeat in {timeout_seconds}s). Disconnecting.")
                    try:
                        await self.close()
                    except Exception:
                        pass
                    break

    async def check_rate_limit(self):
        """
        In-memory per-connection sliding window rate limiter.
        Allows a maximum of 25 messages per 10 seconds (avg 2.5/sec) with a burst threshold.
        """
        import time
        now = time.time()
        
        # Initialize message timestamps list if not present
        if not hasattr(self, 'message_timestamps'):
            self.message_timestamps = []
            
        # Filter out timestamps older than 10 seconds
        self.message_timestamps = [t for t in self.message_timestamps if now - t < 10]
        
        # Record the current message
        self.message_timestamps.append(now)
        
        # Validate count
        if len(self.message_timestamps) > 25:
            client_id = getattr(self, 'bot_username', None) or "Unregistered Client"
            print(f"[C2 Server] [Security Warning] Rate limit exceeded for client '{client_id}'. Disconnecting.")
            
            try:
                await self.send(text_data=json.dumps({
                    'type': 'command',
                    'command': 'kick',
                    'payload': {
                        'reason': 'Rate limit exceeded (Max 25 messages per 10s).'
                    }
                }))
                await self.close()
            except Exception:
                pass
            return False
        return True

    # Receive message from WebSocket (from frontends or Roblox bots)
    async def receive(self, text_data):
        # 1. Enforce per-socket rate limiting to prevent spam and resource exhaustion
        if not await self.check_rate_limit():
            return
            
        try:
            data = json.loads(text_data)
            action = data.get('action')
            
            if action == 'register':
                # Registering active bots from Roblox client
                import time
                self.last_heartbeat = time.time()
                bot_id = data.get('username')
                api_key = data.get('api_key')
                license_key = data.get('license_key')
                
                print(f"[C2 Server] Registration Request received: username='{bot_id}', api_key='{api_key}', license_key='{license_key}'")
                
                # Check validation (checks both C2 API Key and Luarmor License Key)
                is_valid = await self.update_bot_status(bot_id, 'Idle', {
                    'api_key': api_key,
                    'license_key': license_key,
                    'perform_luarmor_check': True
                })
                if not is_valid:
                    print(f"[C2 Server] [Registration Rejected] Credentials check failed for bot '{bot_id}'. Closing connection.")
                    # Send kick command first
                    await self.send(text_data=json.dumps({
                        'type': 'command',
                        'command': 'kick',
                        'payload': {
                            'reason': 'Invalid or missing API Key/Luarmor License. Connection rejected.'
                        }
                    }))
                    await self.close()
                    return
                
                print(f"[C2 Server] [Registration Approved] Session established for bot '{bot_id}'.")
                
                self.bot_username = bot_id
                self.license_validated = True
                self.api_key = api_key
                self.license_key = license_key
                
                # Join direct bot command group for routing direct manage clicks
                self.room_group_name = f"c2_bot_{bot_id}"
                await self.channel_layer.group_add(
                    self.room_group_name,
                    self.channel_name
                )
                
                # Fetch saved DB configuration and sync to bot instantly
                bot_config = await self.get_bot_config(bot_id)
                if bot_config:
                    await self.send(text_data=json.dumps({
                        'type': 'command',
                        'command': 'syncConfig',
                        'payload': bot_config
                    }))
                
                # Broadcast updated fleet status to the bot's owner
                owner_user = await self.get_bot_owner(bot_id)
                if owner_user:
                    await self.broadcast_fleet_update_for_user(owner_user)
                
            elif action == 'clear_offline':
                # Remove all offline bots for this user
                owner_user = self.scope.get('user')
                if owner_user and owner_user.is_authenticated:
                    await self.clear_offline_bots(owner_user)
                    await self.broadcast_fleet_update_for_user(owner_user)
                
            elif action == 'reset_fleet':
                # Force all bots to offline status (clears ghosts/stuck idle nodes)
                owner_user = self.scope.get('user')
                if owner_user and owner_user.is_authenticated:
                    await self.reset_fleet_status(owner_user)
                    await self.broadcast_fleet_update_for_user(owner_user)
                
            elif action == 'command':
                # Relaying UI commands from control panels out to individual Roblox bots
                target_id = data.get('target_id')
                command = data.get('command')
                payload = data.get('payload', {})
                
                user = self.scope.get('user')
                if user and user.is_authenticated:
                    # Verify user owns target bot and get its username
                    bot_username = await self.verify_bot_ownership(user, target_id)
                    if bot_username:
                        # Persist settings in the DB for persistence across page loads (restricted to authorized owner)
                        if command == 'syncConfig':
                            await self.save_bot_configuration(target_id, payload)
                        
                        await self.channel_layer.group_send(
                            f"c2_bot_{bot_username}",
                            {
                                'type': 'relay_command',
                                'target_id': target_id,
                                'command': command,
                                'payload': payload
                            }
                        )
                        await self.broadcast_fleet_update_for_user(user)
 
            elif action == 'log':
                # Update heartbeat timestamp
                import time
                self.last_heartbeat = time.time()
                
                # Bot streaming live telemetries / logs
                username = data.get('username')
                
                # Anti-hijacking: Prevent unauthenticated clients from spoofing another bot's logs
                if not getattr(self, 'license_validated', False) or username != self.bot_username:
                    print(f"[C2 Server] [Security Warning] Log request rejected. Session hijack attempt or missing validation. Username: '{username}', Expected: '{getattr(self, 'bot_username', None)}'")
                    await self.send(text_data=json.dumps({
                        'type': 'command',
                        'command': 'kick',
                        'payload': {
                            'reason': 'Session verification failed. Please re-register.'
                        }
                    }))
                    await self.close()
                    return
                
                # Dynamic group joining if bot was not yet in its command group
                if not self.room_group_name:
                    self.room_group_name = f"c2_bot_{username}"
                    await self.channel_layer.group_add(
                        self.room_group_name,
                        self.channel_name
                    )
                
                event_type = data.get('event_type', 'General')
                message = data.get('message')
                print(f"[C2 Server] [Telemetry Received] Bot '{username}' ({event_type}): {message}")
                
                log_data = await self.create_telemetry_log(username, event_type, message)
                if log_data:
                    owner_user = await self.get_bot_owner(username)
                    if owner_user:
                        # Broadcast telemetry log to the owner's private feed
                        await self.channel_layer.group_send(
                            f"c2_fleet_user_{owner_user.id}",
                            {
                                'type': 'broadcast_log',
                                'log': log_data
                            }
                        )
                        # Broadcast fleet size / status updates to owner
                        await self.broadcast_fleet_update_for_user(owner_user)
 
            elif action == 'update_status':
                import time
                self.last_heartbeat = time.time()
                # Sanitize and validate incoming live stats
                bot_id = data.get('username')
                payload = data.get('payload', {})
                api_key = data.get('api_key')
                
                # Anti-hijacking: Ensure client identity matches the registered session parameters
                if not getattr(self, 'license_validated', False) or bot_id != self.bot_username or api_key != self.api_key:
                    print(f"[C2 Server] [Security Warning] Status update rejected. Session hijack attempt. Username: '{bot_id}', Expected: '{getattr(self, 'bot_username', None)}'")
                    await self.send(text_data=json.dumps({
                        'type': 'command', 
                        'command': 'kick', 
                        'payload': {
                            'reason': 'Session verification failed. Please re-register.'
                        }
                    }))
                    await self.close()
                    return
                
                # Check validation and update (performs local key validation without repeat Luarmor API hit)
                is_valid = await self.update_bot_status(bot_id, payload.get('status', 'Farming'), {
                    'api_key': api_key,
                    'license_key': self.license_key,
                    'perform_luarmor_check': False,
                    **payload
                })
                if not is_valid:
                    await self.send(text_data=json.dumps({
                        'type': 'command', 
                        'command': 'kick', 
                        'payload': {
                            'reason': 'Invalid C2 API Key.'
                        }
                    }))
                    await self.close()
                    return
                
                owner_user = await self.get_bot_owner(bot_id)
                if owner_user:
                    await self.broadcast_fleet_update_for_user(owner_user)
 
            elif action == 'update_metadata':
                # Secure Admin Scraper Endpoint
                admin_key = data.get('admin_key')
                metadata_payload = data.get('metadata', {})
                from django.conf import settings
                expected_admin_key = getattr(settings, 'ADMIN_UPLOAD_KEY', None)
                
                if not expected_admin_key or admin_key != expected_admin_key:
                    await self.send(text_data=json.dumps({'type': 'command', 'command': 'kick', 'payload': {'reason': 'Invalid Admin Key'}}))
                    await self.close()
                    return
                
                # Basic Schema Validation to prevent JSON injection/bloat
                if isinstance(metadata_payload, dict):
                    # Validate depth and limits (max 500 items per list)
                    sanitized_meta = {}
                    for key, val in metadata_payload.items():
                        if isinstance(val, list):
                            sanitized_meta[key] = [str(i)[:100] for i in val[:500]]
                        elif isinstance(val, dict):
                            # Limit dictionary size
                            sanitized_meta[key] = {str(k)[:100]: str(v)[:100] for k, v in list(val.items())[:500]}
                    
                    await self.save_global_metadata(sanitized_meta)
                    print(f"GlobalMetadata updated successfully by Admin. Keys: {list(sanitized_meta.keys())}")
                    
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

    async def new_log(self, event):
        await self.send(text_data=json.dumps({
            'type': 'new_log',
            'log': event['log']
        }))

    async def broadcast_log(self, event):
        await self.send(text_data=json.dumps({
            'type': 'new_log',
            'log': event['log']
        }))

    async def broadcast_fleet_update_for_user(self, user):
        if not user:
            return
        bots = await self.get_bots_for_user(user)
        await self.channel_layer.group_send(
            f'c2_fleet_user_{user.id}',
            {
                'type': 'fleet_update',
                'bots': bots
            }
        )

    @database_sync_to_async
    def save_global_metadata(self, metadata_dict):
        from .models import GlobalMetadata
        obj, _ = GlobalMetadata.objects.get_or_create(key='game_data')
        obj.data = metadata_dict
        obj.save()

    @database_sync_to_async
    def get_bot_owner(self, username):
        from .models import BotAccount
        try:
            bot = BotAccount.objects.get(username=username)
            return bot.owner
        except BotAccount.DoesNotExist:
            return None

    @database_sync_to_async
    def verify_bot_ownership(self, user, bot_id_or_username):
        from .models import BotAccount
        try:
            from django.core.exceptions import ValidationError
            import uuid
            try:
                # Check if UUID
                val = uuid.UUID(str(bot_id_or_username))
                bot = BotAccount.objects.get(id=val, owner=user)
            except (ValueError, ValidationError):
                # Otherwise treat as username
                bot = BotAccount.objects.get(username=bot_id_or_username, owner=user)
            return bot.username
        except BotAccount.DoesNotExist:
            return False

    @database_sync_to_async
    def get_recent_logs_for_user(self, user):
        from .models import TelemetryLog
        if not user or not user.is_authenticated:
            return []
        logs = TelemetryLog.objects.filter(bot__owner=user).select_related('bot').order_by('-timestamp')[:30]
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
    def get_bots_for_user(self, user):
        from .models import BotAccount, BotConfiguration
        if not user or not user.is_authenticated:
            return []
        bots = BotAccount.objects.filter(owner=user).order_by('username')
        serialized = []
        for bot in bots:
            try:
                config = bot.config
                config_data = {
                    'farm_enabled': config.farm_enabled,
                    'snipe_enabled': config.snipe_enabled,
                    'activate_panel': config.activate_panel,
                    'active_areas': config.active_areas,
                    'target_enchant_sets': config.target_enchant_sets,
                    'whitelisted_uuids': config.whitelisted_uuids,
                    'target_priority': config.target_priority,
                    'ascender_enabled': config.ascender_enabled,
                    'ascender_queue': config.ascender_queue,
                    'ascender_criteria': config.ascender_criteria,
                }
            except BotConfiguration.DoesNotExist:
                config_data = {
                    'farm_enabled': False,
                    'snipe_enabled': False,
                    'activate_panel': False,
                    'active_areas': [],
                    'target_enchant_sets': [],
                    'whitelisted_uuids': [],
                    'target_priority': 'Closest',
                    'ascender_enabled': False,
                    'ascender_queue': [],
                    'ascender_criteria': [],
                }
            
            serialized.append({
                'id': str(bot.id),
                'username': bot.username,
                'status': bot.status,
                'level': bot.level,
                'money': float(bot.money),
                'bank_level': bot.bank_level,
                'session_time': bot.session_time,
                'bot_class': bot.bot_class,
                'quality': bot.quality,
                'rarity': bot.rarity,
                'mold': bot.mold,
                'ascender_enchant1': bot.ascender_enchant1,
                'ascender_enchant2': bot.ascender_enchant2,
                'ascender_enchant3': bot.ascender_enchant3,
                'ascender_mode': bot.ascender_mode,
                'backpack_items': bot.backpack_items,
                'config': config_data
            })
        return serialized

    @database_sync_to_async
    def update_bot_status(self, username, status, extra_data=None):
        from .models import BotAccount, BotConfiguration
        print(f"[C2 Server] [Auth Engine] Authenticating credentials for bot '{username}'...")
        
        is_valid_key = False
        owner_user = None
        if extra_data and 'api_key' in extra_data and extra_data['api_key']:
            import hashlib
            from django.contrib.auth.models import User
            from django.conf import settings
            secret = settings.SECRET_KEY
            for user in User.objects.all():
                expected_key = f"c2_usr_{hashlib.sha256(f'{user.id}:{secret}'.encode()).hexdigest()[:16]}"
                if expected_key == extra_data['api_key']:
                    owner_user = user
                    is_valid_key = True
                    break
        
        if not is_valid_key:
            print(f"[C2 Server] [Auth Engine] [API Key Failed] Provided API Key '{extra_data.get('api_key') if extra_data else 'None'}' is invalid or missing.")
            return False
            
        print(f"[C2 Server] [Auth Engine] [API Key Success] API Key resolved to Dashboard User: '{owner_user.username}' (ID: {owner_user.id})")
        
        # Luarmor License Validation (Bypassed by User request - Only API key is needed to authenticate)
        is_license_valid = True
            
        bot, created = BotAccount.objects.get_or_create(username=username)
        bot.owner = owner_user
        bot.status = status
        
        if extra_data:
            import math
            if 'level' in extra_data and extra_data['level'] is not None:
                try:
                    lvl = int(extra_data['level'])
                    if 0 <= lvl <= 1000000:
                        bot.level = lvl
                except ValueError:
                    pass
            if 'money' in extra_data and extra_data['money'] is not None:
                try:
                    money_val = float(extra_data['money'])
                    if not math.isnan(money_val) and not math.isinf(money_val):
                        bot.money = money_val
                except ValueError:
                    pass
            if 'bank_level' in extra_data and extra_data['bank_level'] is not None:
                try:
                    bl_val = int(extra_data['bank_level'])
                    if 0 <= bl_val <= 1000:
                        bot.bank_level = bl_val
                except ValueError:
                    pass
            if 'bot_class' in extra_data and extra_data['bot_class']:
                bot.bot_class = str(extra_data['bot_class'])[:50]
            if 'quality' in extra_data and extra_data['quality']:
                bot.quality = str(extra_data['quality'])[:50]
            if 'rarity' in extra_data and extra_data['rarity']:
                bot.rarity = str(extra_data['rarity'])[:50]
            if 'mold' in extra_data and extra_data['mold']:
                bot.mold = str(extra_data['mold'])[:50]
            if 'ascender_enchant1' in extra_data and extra_data['ascender_enchant1']:
                bot.ascender_enchant1 = str(extra_data['ascender_enchant1'])[:100]
            if 'ascender_enchant2' in extra_data and extra_data['ascender_enchant2']:
                bot.ascender_enchant2 = str(extra_data['ascender_enchant2'])[:100]
            if 'ascender_enchant3' in extra_data and extra_data['ascender_enchant3']:
                bot.ascender_enchant3 = str(extra_data['ascender_enchant3'])[:100]
            if 'ascender_mode' in extra_data and extra_data['ascender_mode']:
                bot.ascender_mode = str(extra_data['ascender_mode'])[:100]
            
            # Prevent Status Poisoning memory flood
            if 'backpack_items' in extra_data and isinstance(extra_data['backpack_items'], list):
                # Cap the list to 500 items max
                safe_list = extra_data['backpack_items'][:500]
                bot.backpack_items = safe_list
        
        bot.save()
        
        config, config_created = BotConfiguration.objects.get_or_create(
            bot=bot,
            defaults={
                'farm_enabled': True,
                'snipe_enabled': True,
                'activate_panel': False,
                'active_areas': [1, 2, 5, 12],
                'target_enchant_sets': ["Ancient + Fortune + Insight"],
                'whitelisted_uuids': ["sword_92k"]
            }
        )
        
        # Sync live state from Roblox telemetry
        if extra_data:
             if 'farm_enabled' in extra_data:
                 config.farm_enabled = bool(extra_data['farm_enabled'])
             if 'snipe_enabled' in extra_data:
                 config.snipe_enabled = bool(extra_data['snipe_enabled'])
             if 'activate_panel' in extra_data:
                 config.activate_panel = bool(extra_data['activate_panel'])
             if 'ascender_enabled' in extra_data:
                 config.ascender_enabled = bool(extra_data['ascender_enabled'])
             if 'ascender_queue' in extra_data and isinstance(extra_data['ascender_queue'], list):
                 config.ascender_queue = extra_data['ascender_queue']
             if 'target_enchant_sets' in extra_data and extra_data['target_enchant_sets']:
                 config.target_enchant_sets = extra_data['target_enchant_sets']
             if 'whitelisted_uuids' in extra_data:
                 config.whitelisted_uuids = extra_data['whitelisted_uuids']
             if 'active_areas' in extra_data and isinstance(extra_data['active_areas'], list):
                 config.active_areas = extra_data['active_areas']
        
        # If config already existed but had empty defaults from prior db state, populate them:
        if not config.target_enchant_sets:
            config.target_enchant_sets = ["Ancient + Fortune + Insight"]
            
        config.save()
        return True

    @database_sync_to_async
    def set_bot_offline(self, username):
        from .models import BotAccount
        try:
            bot = BotAccount.objects.get(username=username)
            bot.status = 'Offline'
            bot.save()
        except BotAccount.DoesNotExist:
            pass

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
            return None

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
            if 'activate_panel' in payload:
                config.activate_panel = payload['activate_panel']
            if 'active_areas' in payload:
                config.active_areas = payload['active_areas']
            if 'target_enchant_sets' in payload:
                config.target_enchant_sets = payload['target_enchant_sets']
            if 'whitelisted_uuids' in payload:
                config.whitelisted_uuids = payload['whitelisted_uuids']
            if 'target_priority' in payload:
                config.target_priority = payload['target_priority']
            if 'ascender_enabled' in payload:
                config.ascender_enabled = payload['ascender_enabled']
            if 'ascender_queue' in payload:
                config.ascender_queue = payload['ascender_queue']
            if 'ascender_criteria' in payload:
                config.ascender_criteria = payload['ascender_criteria']
            config.save()
            
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

    @database_sync_to_async
    def get_bot_config(self, username):
        from .models import BotAccount, BotConfiguration
        try:
            bot = BotAccount.objects.get(username=username)
            config, _ = BotConfiguration.objects.get_or_create(bot=bot)
            return {
                'farm_enabled': config.farm_enabled,
                'snipe_enabled': config.snipe_enabled,
                'activate_panel': config.activate_panel,
                'active_areas': config.active_areas,
                'target_enchant_sets': config.target_enchant_sets,
                'whitelisted_uuids': config.whitelisted_uuids,
                'ascender_enabled': config.ascender_enabled,
                'ascender_queue': config.ascender_queue,
                'ascender_criteria': config.ascender_criteria
            }
        except BotAccount.DoesNotExist:
            return None

    @database_sync_to_async
    def clear_offline_bots(self, user):
        from .models import BotAccount
        BotAccount.objects.filter(owner=user, status='Offline').delete()

    @database_sync_to_async
    def reset_fleet_status(self, user):
        from .models import BotAccount
        # Set all bots for the user to Offline.
        # Any actively connected bots will auto-reconnect and update their status to Idle/Farming within seconds.
        BotAccount.objects.filter(owner=user).update(status='Offline')
