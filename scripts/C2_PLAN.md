# Command & Control (C2) Web Panel Plan

## 🎯 Objective
Build a lightweight local C2 (Command & Control) panel to manage multiple Roblox farming clients. The panel will allow toggling 3D rendering and auto-farm states per individual client.

## 🏗️ Architecture Decision
- **Backend/Frontend:** Node.js + Express + `ws` (WebSockets) for real-time bidirectional communication.
- **Frontend UI:** Vanilla HTML/CSS/JS served directly by Express. A simple dashboard table showing each connected client and action buttons.
- **Game Client (Lua):** Will utilize the executor's built-in `WebSocket.connect()` to maintain a persistent connection to the Node.js server. 

## 🚀 Phases

### Phase 1: Local Node.js Server Setup
- [ ] Initialize a new Node.js project.
- [ ] Install `express` and `ws` (WebSocket) packages.
- [ ] Create `server.js` to handle:
  - Serving the frontend dashboard.
  - Accepting WebSocket connections from the Lua clients.
  - Accepting WebSocket connections from the Web Dashboard.
  - Routing commands from the dashboard to specific Lua clients.

### Phase 2: Web Dashboard UI
- [ ] Create an `index.html` file served by Express.
- [ ] Build a dynamic HTML table to list connected clients (showing Username, Farm Status, 3D Render Status).
- [ ] Add Action Buttons for each row:
  - `Toggle 3D Rendering`
  - `Toggle Auto-Farm`
- [ ] Implement client-side JS to connect to the Node.js WebSocket and send/receive state updates.

### Phase 3: Lua Script Integration (Client)
- [ ] Implement WebSocket connection logic in the provided autofarm script using `syn.websocket.connect` or the standard executor `WebSocket.connect("ws://localhost:PORT")`.
- [ ] Implement a listener for incoming commands from the server.
- [ ] Implement `Toggle 3D Rendering` using `RunService:Set3dRenderingEnabled(false)` (if supported by the executor) or disabling rendering on the client workspace.
- [ ] Link the incoming `Toggle Auto-Farm` command to the existing `_G.on` state and UI toggle.

### Phase 4: Testing & Polish
- [ ] Run the Node.js server locally via Antigravity.
- [ ] Connect a test Roblox client and verify it appears on the dashboard.
- [ ] Test toggling 3D rendering and auto-farming via the dashboard buttons.
