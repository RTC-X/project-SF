#!/usr/bin/env python3
"""
C2 Fleet Node Telemetry Simulator v1.0
This simulator creates a large fleet of dummy Roblox farm bot nodes (e.g. GoldGoblin_X, RoboFarmer_Beta, SniperLegend_99),
registers them on the Django C2 Server, streams high-fidelity gameplay telemetry (leveling up, gold gains, sniping enchants),
and listens to real-time Multi-Config dispatches from the Dashboard!

Usage:
  pip install websockets
  python scripts/simulate_fleet.py --host localhost:8000 --bots 3
"""

import argparse
import asyncio
import json
import random
import sys
from datetime import datetime

try:
    import websockets
except ImportError:
    print("\n[!] Error: 'websockets' library is required to run this simulator.")
    print("    Please install it using: pip install websockets\n")
    sys.exit(1)

# Color terminal helpers
GREEN = "\033[92m"
TEAL = "\033[96m"
YELLOW = "\033[93m"
ORANGE = "\033[33m"
RED = "\033[91m"
RESET = "\033[0m"
BOLD = "\033[1m"

BOT_CLASSES = ["Unbeatable", "Grandmaster", "Bladesmith", "Dragonborn", "Berserker"]
QUALITIES = ["Spectacular", "Exquisite", "Fine", "Standard", "Perfect"]
RARITIES = ["Heavenly++", "Mythic", "Legendary", "Rare", "Relic"]
MOLDS = ["Crystal", "Golden", "Iron", "Obsidian", "Eldritch"]

SIMULATED_LOGS = [
    ("Farming", "Successfully defeated Elder Golem boss node in Area 12."),
    ("Farming", "Cleared out Area 5 trash mobs. Gained 14,800 Gold."),
    ("Sniping", "Scanning Trading Plaza auction list for target sword enchants..."),
    ("Sniping", "Sniped rare Fire Enchantment book for 25,000 Gold!"),
    ("System", "Auto-compacted local memory cache. Freed 42MB heap storage."),
    ("System", "Refreshed character pathfinding coordinates for teleport anchors."),
    ("Farming", "Collected drop items: 4x Obsidian Shards, 1x Mythic Key."),
    ("System", "Anti-detect cooldown triggered. Sleeping for 4 seconds..."),
]

def get_timestamp():
    return datetime.now().strftime("%H:%M:%S")

class SimulatedBot:
    def __init__(self, username):
        self.username = username
        self.level = random.randint(100, 500)
        self.money = random.uniform(1000.0, 500000.0)
        self.bot_class = random.choice(BOT_CLASSES)
        self.quality = random.choice(QUALITIES)
        self.rarity = random.choice(RARITIES)
        self.mold = random.choice(MOLDS)
        self.status = "Idle"
        self.farm_enabled = True
        self.snipe_enabled = True
        self.target_enchant_sets = ["Ancient + Fortune"]
        self.whitelisted_uuids = ["sword_92k"]
        self.backpack_items = [
            {"uuid": "sword_92k", "name": "Ancient Broadsword", "traits": ["Ancient II", "Level 10"]},
            {"uuid": "sword_41m", "name": "Fortune Katana", "traits": ["Fortune IV", "Level 25"]},
        ]

    def get_status_payload(self, event_type, message):
        self.status = event_type
        if event_type == "Farming":
            self.money += random.uniform(10.0, 100.0)
            if random.random() < 0.2:
                self.level += 1
        
        return {
            "action": "log",
            "username": self.username,
            "event_type": event_type,
            "message": f"[{self.username}] {message} (Level: {self.level}, Money: ${self.money:.2f})"
        }

async def bot_session(uri, bot, delay, discord_id=""):
    while True:
        try:
            print(f"[{get_timestamp()}] {TEAL}[{bot.username}]{RESET} Connecting to C2 Server...")
            async with websockets.connect(uri) as websocket:
                print(f"[{get_timestamp()}] {GREEN}[{bot.username}]{RESET} Connected successfully!")
                
                # Step 1: Register bot account details dynamically
                register_payload = {
                    "action": "register",
                    "username": bot.username,
                    "level": bot.level,
                    "money": bot.money,
                    "bot_class": bot.bot_class,
                    "quality": bot.quality,
                    "rarity": bot.rarity,
                    "mold": bot.mold,
                    "backpack_items": bot.backpack_items,
                    "discord_id": discord_id
                }
                await websocket.send(json.dumps(register_payload))
                print(f"[{get_timestamp()}] {GREEN}[{bot.username}]{RESET} Registered node statistics on dashboard! (Discord Owner: {discord_id if discord_id else 'Global'})")

                # Step 2: Concurrently stream logs and listen for Multi-Config events
                async def stream_logs():
                    while True:
                        await asyncio.sleep(random.uniform(delay - 2, delay + 2))
                        event_type, msg = random.choice(SIMULATED_LOGS)
                        payload = bot.get_status_payload(event_type, msg)
                        await websocket.send(json.dumps(payload))
                        print(f"[{get_timestamp()}] {GREEN}>>> [{bot.username} LOG SENT]{RESET} ({event_type}): {msg}")

                async def receive_configs():
                    async for message in websocket:
                        try:
                            data = json.loads(message)
                            if data.get("type") == "command":
                                target_id = data.get("target_id")
                                command = data.get("command")
                                payload = data.get("payload", {})
                                
                                # Process incoming dynamic action dispatches
                                print("\n" + "="*60)
                                print(f"{YELLOW}{BOLD}[⚡ INCOMING MULTI-CONFIG DIRECTIVE FOR {bot.username}]{RESET}")
                                print(f"  Command:   {BOLD}{command}{RESET}")
                                print(f"  Payload:   {json.dumps(payload, indent=2)}")
                                print("="*60 + "\n")
                                
                                if command == "syncConfig":
                                    bot.farm_enabled = payload.get("farm_enabled", bot.farm_enabled)
                                    bot.snipe_enabled = payload.get("snipe_enabled", bot.snipe_enabled)
                                    bot.bot_class = payload.get("bot_class", bot.bot_class)
                                    bot.quality = payload.get("quality", bot.quality)
                                    bot.rarity = payload.get("rarity", bot.rarity)
                                    bot.mold = payload.get("mold", bot.mold)
                                    bot.level = payload.get("level", bot.level)
                                    bot.target_enchant_sets = payload.get("target_enchant_sets", bot.target_enchant_sets)
                                    bot.whitelisted_uuids = payload.get("whitelisted_uuids", bot.whitelisted_uuids)
                                    print(f"[{get_timestamp()}] {GREEN}Node config successfully hot-reloaded!{RESET}")
                        except json.JSONDecodeError:
                            pass

                await asyncio.gather(stream_logs(), receive_configs())

        except (websockets.exceptions.ConnectionClosed, OSError) as e:
            print(f"[{get_timestamp()}] {ORANGE}[{bot.username}] Connection lost. Reconnecting in 5s... ({e}){RESET}")
            await asyncio.sleep(5)

async def start_fleet(host, bot_count, delay, discord_id=""):
    is_secure = not (host.startswith("localhost") or host.startswith("127.0.0.1") or ":" in host and not host.endswith("443"))
    protocol = "wss" if is_secure else "ws"
    clean_host = host.replace("http://", "").replace("https://", "").replace("ws://", "").replace("wss://", "")
    uri = f"{protocol}://{clean_host}/ws/c2/"

    # Generate distinct bot usernames
    bot_names = [f"GoldGoblin_{i}" for i in range(1, bot_count + 1)]
    if bot_count >= 2:
        bot_names[1] = "RoboFarmer_Beta"
    if bot_count >= 3:
        bot_names[2] = "SniperLegend_99"

    print(f"\n{BOLD}{TEAL}C2 Fleet Telemetry Simulator v1.0{RESET}")
    print(f"--------------------------------------------------")
    print(f"Target Server : {BOLD}{uri}{RESET}")
    print(f"Fleet Count   : {BOLD}{bot_count} Active Bots{RESET}")
    print(f"Discord Owner : {BOLD}{discord_id if discord_id else 'None (Global)'}{RESET}")
    print(f"Heartbeats    : Random every ~{delay}s")
    print(f"--------------------------------------------------\n")

    sessions = [bot_session(uri, SimulatedBot(name), delay, discord_id) for name in bot_names]
    await asyncio.gather(*sessions)

def main():
    parser = argparse.ArgumentParser(description="C2 fleet node simulator.")
    parser.add_argument("--host", default="c2scripts.xyz", help="C2 WebSocket Host (e.g. c2scripts.xyz or localhost:8000)")
    parser.add_argument("--bots", type=int, default=3, help="Number of simulated bot nodes to run concurrently")
    parser.add_argument("--delay", type=int, default=8, help="Average delay between telemetry logs")
    parser.add_argument("--discord-id", default="", help="Discord Account UID to bind bots to")
    
    args = parser.parse_args()
    try:
        asyncio.run(start_fleet(args.host, args.bots, args.delay, args.discord_id))
    except KeyboardInterrupt:
        print(f"\n[{datetime.now().strftime('%H:%M:%S')}] {RED}Simulation terminated by keyboard input.{RESET}\n")

if __name__ == "__main__":
    main()
