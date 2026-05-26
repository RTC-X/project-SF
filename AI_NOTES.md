# AI Agent Notes & Guidelines
**Project:** project-SF

## 1. C2 Dashboard & Server Synchronization
- **API Metadata:** The C2 Dashboard must fetch its live metadata (Areas, Molds, Enchants, etc.) from `https://c2scripts.xyz/api/metadata/?api_key=c2_usr_5d6a6bf84ca9edf3`. It should NOT rely on the game client to provide this data in telemetry.
- **WebSocket Protocol:**
  - Game clients send telemetry using `action = "update_status"`. Ensure the NodeJS server handles both `type` and `action` gracefully.
  - The NodeJS server (`server.js`) MUST send commands to the game clients using `command: "<command_name>"` (e.g., `command: "syncConfig"`), as the `autofarm_with_c2.lua` script strictly checks for `data.command`.
- **Global Configs:** The Node server centrally manages `globalConfigs`. When the dashboard fetches active clients, the server must inject `globalConfigs` into the telemetry `fullConfig` payload so the dashboard UI reflects the persistently saved state.

## 2. In-Game AutoFarm Logic
- **Teleportation:** 
  - `InvokeServer("Teleport In Base", targetStr)` is the core method. 
  - `"Home"` targets the Base (Area 0), while `"Return"` is used for transitioning back to the base from other maps.
  - **Rule:** Do NOT force arguments arbitrarily. The `TeleportSequence` logic requires strict adherence to `_G.FarmAreas`.
- **Bank & Inventory:**
  - Bank slots increase based on bank level (Level 1 = 6 slots, Level 15 = 36 slots).
  - When referencing Protected UUIDs in the Dashboard, ALWAYS filter out swords that are already in the Bank (`item.inBank` = true) to prevent UI clutter and accidental deletion attempts.

## 3. General Rules
- If uncertain about RemoteEvent arguments or map logic, ASK for clarification instead of guessing or brute-forcing patches.
- Preserve all existing configurations and visual UI elements unless specifically asked to redesign them.
