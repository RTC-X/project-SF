# AI Agent Notes & Guidelines
**Project:** project-SF

## 1. CI/CD & Deployment
- **Coolify Integration:** This repository is connected to GitHub. Every push and pull operation reflects directly onto the production VPS server automatically via Coolify. All changes made to `server.js` or `index.html` must be pushed to GitHub to take effect on the live server.

## 2. C2 Dashboard & Server Synchronization
- **Strict PascalCase Standard:** ALL JSON payloads, websocket commands, and Frontend Alpine.js objects MUST exclusively use \PascalCase\ (e.g., \FarmAreas\, \WhitelistedSwords\, \BotClass\). 
- **Django ORM Boundary:** The Django Database (\models.py\) strictly remains \snake_case\ (e.g., \bot.bot_class\). 
- **Translation Layer (\consumers.py\):** The server's Websocket layer MUST actively map \snake_case\ database fields to \PascalCase\ when sending data out, and extract \PascalCase\ keys from JSON payloads to save into \snake_case\ database fields. Never send \snake_case\ over the WebSocket.
- **Frontend Caveats:** Since backend payloads use \PascalCase\, object references in HTML/AlpineJS like \bot.status\ MUST be capitalized as \bot.Status\ (e.g., \bots.filter(b => b.Status !== 'Offline')\). Failing this leads to \undefined\ filter evaluations.
- **API Metadata:** The C2 Dashboard must fetch its live metadata (Areas, Molds, Enchants, etc.) from `https://c2scripts.xyz/api/metadata/?api_key=c2_usr_5d6a6bf84ca9edf3`. It should NOT rely on the game client to provide this data in telemetry.
- **WebSocket Protocol:**
  - Game clients send telemetry to the C2 server using `action = "update_status"`. Ensure the NodeJS server handles both `type` and `action` gracefully.
  - The NodeJS server (`server.js`) MUST send commands to the game clients using the `command` key (e.g., `{ "command": "syncConfig", "payload": {...} }`), because the `autofarm_with_c2.lua` script strictly checks for `data.command`.
- **Global Configs & State Flow:** 
  - The Node server centrally manages `globalConfigs` on disk (`global_configs.json`). 
  - When the dashboard fetches active clients (broadcasted every 1 second), the server must inject `globalConfigs` into the telemetry `fullConfig` payload so the dashboard UI reflects the persistently saved state.
- **Website Flow:**
  - 1. **Dashboard connects:** Dashboard establishes WS connection with C2 Server and receives initial metadata.
  - 2. **Telemetry broadcast:** C2 Server broadcasts `client_list` to Dashboard every 1 second (containing game clients' telemetry + injected `globalConfigs`).
  - 3. **Config save:** Dashboard sends `{ type: "command", action: "syncConfig", payload: config }` to the server.
  - 4. **Server persistence & forwarding:** C2 Server intercepts this, saves `payload` into `globalConfigs`, and forwards `{ command: "syncConfig", payload: config }` to the specific Game Client.
  - 5. **Game application:** Game Client receives the command and applies the configuration (e.g., updates `_G.FarmAreas`).

## 3. In-Game AutoFarm Logic
- **Teleportation:** 
  - `InvokeServer("Teleport In Base", targetStr)` is the core method. 
  - `"Home"` targets the Base (Area 0), while `"Return"` is used for transitioning back to the base from other maps.
  - **Rule:** Do NOT force arguments arbitrarily. The `TeleportSequence` logic requires strict adherence to `_G.FarmAreas`.
- **Bank & Inventory:**
  - Bank slots increase based on bank level (Level 1 = 6 slots, Level 15 = 36 slots).
  - When referencing Protected UUIDs in the Dashboard, ALWAYS filter out swords that are already in the Bank (`item.inBank` = true) to prevent UI clutter and accidental deletion attempts.

## 4. General Rules
- If uncertain about RemoteEvent arguments or map logic, ASK for clarification instead of guessing or brute-forcing patches.
- Preserve all existing configurations and visual UI elements unless specifically asked to redesign them.
