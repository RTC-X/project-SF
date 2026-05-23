#!/usr/bin/env python3
"""
C2 Real-Time Bot Simulator / Test Client
This script simulates a Roblox farm bot connecting to the C2 WebSocket server.
It handles auto-registration, streams live telemetry logs to the System Feed,
and listens for hot incoming control commands dispatched from the Dashboard UI.

Usage:
  pip install websockets
  python scripts/test_c2_client.py --host c2scripts.xyz --username GoldGoblin_X
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
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")

async def send_heartbeat_logs(websocket, username, delay):
    """Periodically streams realistic telemetry logs to the C2 WebSocket."""
    while True:
        await asyncio.sleep(delay)
        event_type, message = random.choice(SIMULATED_LOGS)
        
        payload = {
            "action": "log",
            "username": username,
            "event_type": event_type,
            "message": message
        }
        
        try:
            await websocket.send(json.dumps(payload))
            print(f"[{get_timestamp()}] {GREEN}>>> [LOG SENT]{RESET} ({event_type}): {message}")
        except websockets.exceptions.ConnectionClosed:
            break

async def receive_commands(websocket):
    """Listens continuously for commands dispatched from the C2 Dashboard."""
    async for message in websocket:
        try:
            data = json.loads(message)
            msg_type = data.get("type")
            
            if msg_type == "command":
                target_id = data.get("target_id")
                command = data.get("command")
                payload = data.get("payload", {})
                
                # Check if this command is targeted specifically for us or a global broadcast
                print("\n" + "="*50)
                print(f"{YELLOW}{BOLD}[⚡ INCOMING C2 COMMAND RECEIVED]{RESET}")
                print(f"  Target ID: {target_id}")
                print(f"  Command:   {BOLD}{command}{RESET}")
                print(f"  Payload:   {json.dumps(payload, indent=2)}")
                print("="*50 + "\n")
                
                # Simulate executing the command
                print(f"[{get_timestamp()}] {TEAL}* Simulated execution of command '{command}' succeeded.*{RESET}\n")
        except json.JSONDecodeError:
            print(f"[{get_timestamp()}] {RED}Received raw invalid message format: {message}{RESET}")



async def start_client(host, username, delay, api_key=""):
    # Auto-resolve ws:// vs wss://
    is_secure = not (host.startswith("localhost") or host.startswith("127.0.0.1") or ":" in host and not host.endswith("443"))
    protocol = "wss" if is_secure else "ws"
    
    # Strip any existing prefixes user might pass
    clean_host = host.replace("http://", "").replace("https://", "").replace("ws://", "").replace("wss://", "")
    
    uri = f"{protocol}://{clean_host}/ws/c2/"
    
    print(f"\n{BOLD}{TEAL}C2 Fleet Bot Node Simulator v1.0{RESET}")
    print("--------------------------------------------------")
    print(f"Target Server : {BOLD}{uri}{RESET}")
    print(f"Bot Username  : {BOLD}{username}{RESET}")
    print(f"API Key       : {BOLD}{api_key if api_key else 'None'}{RESET}")
    print(f"Telemetry Delay: {delay}s")
    print("--------------------------------------------------")
    print(f"[{get_timestamp()}] Connecting to C2 Server...")

    while True:
        try:
            async with websockets.connect(uri) as websocket:
                print(f"[{get_timestamp()}] {GREEN}Connected successfully!{RESET}")
                
                # Step 1: Send registration payload
                register_payload = {
                    "action": "register",
                    "username": username,
                    "api_key": api_key
                }
                await websocket.send(json.dumps(register_payload))
                print(f"[{get_timestamp()}] {GREEN}Bot account registered on dashboard! (API Key: {api_key if api_key else 'None'}){RESET}")
                
                # Step 2: Run log streamer and command receiver concurrently
                await asyncio.gather(
                    send_heartbeat_logs(websocket, username, delay),
                    receive_commands(websocket)
                )
                
        except (websockets.exceptions.ConnectionClosed, OSError) as e:
            print(f"[{get_timestamp()}] {ORANGE}Connection lost or server down. Retrying in 5s... ({e}){RESET}")
            await asyncio.sleep(5)

def main():
    parser = argparse.ArgumentParser(description="C2 Real-Time Bot Simulator")
    parser.add_argument("--host", default="c2scripts.xyz", help="C2 Server domain/host (e.g. c2scripts.xyz or localhost:8000)")
    parser.add_argument("--username", default="GoldGoblin_X", help="Roblox Bot username to register and simulate")
    parser.add_argument("--delay", type=int, default=6, help="Delay in seconds between heartbeat logs (default: 6)")
    parser.add_argument("--api-key", default="", help="User API Key to bind bot to")
    
    args = parser.parse_args()
    
    try:
        asyncio.run(start_client(args.host, args.username, args.delay, args.api_key))
    except KeyboardInterrupt:
        print(f"\n[{get_timestamp()}] {RED}Simulator shut down by user.{RESET}\n")

if __name__ == "__main__":
    main()
