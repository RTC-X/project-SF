const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const path = require('path');
const fs = require('fs');

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

// --- Basic Dashboard Security ---
const PANEL_USERNAME = process.env.C2_USER || 'admin';
const PANEL_PASSWORD = process.env.C2_PASS || 'antigravity';

app.use((req, res, next) => {
    // Authentication disabled per user request
    return next();
});

app.use(express.static(path.join(__dirname, 'public')));

// Secure Script Loader Endpoint
app.get('/api/get_script', (req, res) => {
    // Only allow HTTP GET requests from Roblox Executors
    const userAgent = req.headers['user-agent'] || '';
    if (!userAgent.includes('Roblox') && !userAgent.includes('Synapse') && !userAgent.includes('Krnl') && !userAgent.includes('Wave') && !userAgent.includes('Macsploit')) {
        return res.status(403).send('-- Unauthorized access. Executor not detected.');
    }
    
    const scriptPath = path.join(__dirname, '..', 'autofarm_with_c2.lua');
    if (fs.existsSync(scriptPath)) {
        res.sendFile(scriptPath);
    } else {
        res.status(404).send('-- Script not found on C2 Server');
    }
});

const CONFIG_FILE = path.join(__dirname, 'saved_configs.json');
let globalConfigs = {};
if (fs.existsSync(CONFIG_FILE)) {
    try {
        globalConfigs = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
    } catch(e) {
        console.error("Failed to load saved_configs.json", e);
    }
}

let GlobalMetaTable = {};
fetch('https://c2scripts.xyz/api/metadata/?api_key=c2_usr_5d6a6bf84ca9edf3')
    .then(r => r.json())
    .then(data => {
        if (data.success) {
            GlobalMetaTable = data.data;
            console.log('\x1b[36m[+] Fetched GlobalMetaTable from API\x1b[0m');
        }
    })
    .catch(err => console.error("Failed to fetch GlobalMetaTable:", err.message));

function saveGlobalConfigs() {
    fs.writeFileSync(CONFIG_FILE, JSON.stringify(globalConfigs, null, 4));
}

// Store connected clients
const clients = new Map();

// Heartbeat to detect disconnected clients
const pingInterval = setInterval(() => {
    wss.clients.forEach((ws) => {
        if (ws.isAlive === false) {
            const clientData = clients.get(ws);
            if (clientData && clientData.type === 'game') {
                console.log(`\x1b[31m[-] Game client disconnected (timeout): ${clientData.id}\x1b[0m`);
            }
            clients.delete(ws);
            broadcastToDashboards();
            return ws.terminate();
        }
        ws.isAlive = false;
        ws.ping();
    });
}, 10000);

wss.on('connection', (ws, req) => {
    let clientId = null;
    let clientType = 'unknown'; // 'dashboard' or 'game'

    ws.isAlive = true;
    ws.on('pong', () => { ws.isAlive = true; });

    ws.on('message', (message) => {
        try {
            const data = JSON.parse(message);
            
            if (data.type === 'register') {
                clientType = data.clientType;
                if (clientType === 'game') {
                    clientId = data.username || `Unknown_${Math.floor(Math.random()*1000)}`;
                    // Avoid duplicate connections with the same ID
                    for (const [existingWs, clientData] of clients.entries()) {
                        if (clientData.type === 'game' && clientData.id === clientId) {
                            existingWs.close();
                            clients.delete(existingWs);
                        }
                    }
                    clients.set(ws, { id: clientId, type: 'game', status: data.status || { farming: false, render3d: true, snipeEnabled: false } });
                    
                    // Push global config to client on connect if available
                    if (globalConfigs[clientId]) {
                        console.log(`\x1b[33m[>] Pushing saved web config to newly connected client: ${clientId}\x1b[0m`);
                        ws.send(JSON.stringify({ action: 'syncConfig', payload: globalConfigs[clientId] }));
                    }

                    broadcastToDashboards();
                    console.log(`\x1b[32m[+] Game client registered: ${clientId}\x1b[0m`);
                } else if (clientType === 'dashboard') {
                    clients.set(ws, { type: 'dashboard' });
                    ws.send(JSON.stringify({ type: 'metadata', data: GlobalMetaTable }));
                    sendClientsToDashboard(ws);
                    console.log('\x1b[35m[+] Dashboard connected\x1b[0m');
                }
            } else if (data.type === 'update_status') {
                if (clients.has(ws)) {
                    const clientData = clients.get(ws);
                    const incomingStatus = data.status || data.payload || {};
                    clientData.status = { ...clientData.status, ...incomingStatus };
                    // We don't broadcast here anymore to save bandwidth, a global interval handles it
                }
            } else if (data.type === 'save_config_to_server') {
                if (clientType === 'game' && clientId) {
                    globalConfigs[clientId] = data.payload;
                    saveGlobalConfigs();
                    console.log(`\x1b[32m[+] Config saved to server disk by game client ${clientId}\x1b[0m`);
                }
            } else if (data.type === 'command') {
                // Command coming from dashboard to be sent to a specific game client
                if (clientType === 'dashboard') {
                    if (data.action === 'syncConfig') {
                        // Dashboard saving config centrally on website server
                        globalConfigs[data.targetId] = data.payload;
                        saveGlobalConfigs();
                        console.log(`\x1b[32m[+] Config saved to server disk for ${data.targetId}\x1b[0m`);
                    }

                    for (const [clientWs, clientData] of clients.entries()) {
                        if (clientData.type === 'game' && clientData.id === data.targetId) {
                            clientWs.send(JSON.stringify({ command: data.action, payload: data.payload }));
                            console.log(`\x1b[33m[>] Sent command '${data.action}' to ${data.targetId}\x1b[0m`);
                            break;
                        }
                    }
                }
            }
        } catch (e) {
            console.error('Error parsing message', e);
        }
    });

    ws.on('close', () => {
        if (clientId) {
            console.log(`\x1b[31m[-] Game client disconnected: ${clientId}\x1b[0m`);
        } else if (clientType === 'dashboard') {
            console.log('\x1b[31m[-] Dashboard disconnected\x1b[0m');
        }
        clients.delete(ws);
        if (clientType === 'game') {
            broadcastToDashboards();
        }
    });
});

// --- Live Mock Roblox Bot Accounts Telemetry Generator ---
const mockClients = [
    {
        id: "RoboFarmer_Alpha",
        status: {
            farming: true,
            snipeEnabled: true,
            liveStats: {
                timeSpent: 3600,
                levelGained: 14,
                moneyGained: 250000,
                currentState: "Farming Area 12"
            },
            ascenderData: {
                hasSword: true,
                stats: {
                    Level: 82,
                    Quality: "94.6%",
                    Rarity: "Mythic God Roll",
                    Mold: "Duality Mold",
                    Enchant1: "Sharpness V",
                    Enchant2: "Looting III",
                    Enchant3: "Haste II"
                }
            },
            backpackData: [
                { id: "sword_01", Level: 45, Rarity: "Legendary", Quality: "89.2%", Class: "Gladiator", Equipped: true },
                { id: "sword_02", Level: 38, Rarity: "Rare", Quality: "74.1%", Class: "Vanguard", Equipped: false },
                { id: "sword_03", Level: 12, Rarity: "Common", Quality: "50.0%", Class: "Recruit", Equipped: false }
            ],
            fullConfig: {
                WebhookURL: "https://discord.com/api/webhooks/123456789/abcdefgh",
                WebhookEnabled: true,
                Settings: {
                    OFFSET_HEIGHT: 7,
                    WAIT_ALTITUDE: 15,
                    MAX_KILL_TIME: 5,
                    IDLE_BEFORE_HOP: 3,
                    MIN_NPCS_TO_STAY: 0
                },
                TargetPriority: "Closest",
                FarmAreas: [1, 2, 5, 12],
                TargetSets: [["Sharpness V", "Looting III"], ["Haste II"]],
                WhitelistedSwords: ["sword_01"]
            },
            metadata: {
                Areas: ["[1] Area 1", "[2] Area 2", "[5] Area 5", "[12] Area 12"]
            }
        }
    },
    {
        id: "GoldGoblin_X",
        status: {
            farming: true,
            snipeEnabled: true,
            liveStats: {
                timeSpent: 1800,
                levelGained: 6,
                moneyGained: 124000,
                currentState: "Sniping Active Area 5"
            },
            ascenderData: {
                hasSword: true,
                stats: {
                    Level: 41,
                    Quality: "88.1%",
                    Rarity: "Epic",
                    Mold: "Standard Mold",
                    Enchant1: "Looting II",
                    Enchant2: "Haste I",
                    Enchant3: "EMPTY"
                }
            },
            backpackData: [
                { id: "sword_04", Level: 22, Rarity: "Epic", Quality: "81.4%", Class: "Crusader", Equipped: true }
            ],
            fullConfig: {
                WebhookURL: "https://discord.com/api/webhooks/987654321/hgfedcba",
                WebhookEnabled: false,
                Settings: {
                    OFFSET_HEIGHT: 6,
                    WAIT_ALTITUDE: 12,
                    MAX_KILL_TIME: 6,
                    IDLE_BEFORE_HOP: 4,
                    MIN_NPCS_TO_STAY: 1
                },
                TargetPriority: "Highest XP",
                FarmAreas: [1, 5],
                TargetSets: [["Looting II"], ["Haste I"]],
                WhitelistedSwords: ["sword_04"]
            },
            metadata: {
                Areas: ["[1] Area 1", "[2] Area 2", "[5] Area 5"]
            }
        }
    },
    {
        id: "AscendedKnight",
        status: {
            farming: false,
            snipeEnabled: false,
            liveStats: {
                timeSpent: 7200,
                levelGained: 32,
                moneyGained: 980000,
                currentState: "Idle - Standby"
            },
            ascenderData: {
                hasSword: false
            },
            backpackData: [],
            fullConfig: {
                WebhookURL: "",
                WebhookEnabled: false,
                Settings: {
                    OFFSET_HEIGHT: 7,
                    WAIT_ALTITUDE: 15,
                    MAX_KILL_TIME: 5,
                    IDLE_BEFORE_HOP: 3,
                    MIN_NPCS_TO_STAY: 0
                },
                TargetPriority: "Closest",
                FarmAreas: [],
                TargetSets: [],
                WhitelistedSwords: []
            },
            metadata: {
                Areas: ["[1] Area 1", "[2] Area 2"]
            }
        }
    }
];

// Tick up live mock accounts telemetry
setInterval(() => {
    mockClients.forEach(c => {
        c.status.liveStats.timeSpent += 5;
        if (c.status.farming) {
            c.status.liveStats.moneyGained += Math.floor(Math.random() * 500) + 100;
            if (Math.random() > 0.92) {
                c.status.liveStats.levelGained += 1;
            }
        }
    });
    broadcastToDashboards();
}, 5000);

function getActiveGameClients() {
    const gameClients = [];
    for (const [clientWs, clientData] of clients.entries()) {
        if (clientData.type === 'game') {
            // Inject global config from server state so dashboard has persistent data
            const statusWithConfig = { ...clientData.status };
            if (globalConfigs[clientData.id]) {
                statusWithConfig.fullConfig = globalConfigs[clientData.id];
            }
            
            gameClients.push({
                id: clientData.id,
                status: statusWithConfig
            });
        }
    }
    // Concatenate our mock clients to preview visual fidelity
    gameClients.push(...mockClients);
    return gameClients;
}

function sendClientsToDashboard(dashboardWs) {
    if (dashboardWs.readyState === WebSocket.OPEN) {
        dashboardWs.send(JSON.stringify({
            type: 'client_list',
            clients: getActiveGameClients()
        }));
    }
}

// Global broadcast interval to batch all updates into 1 per second
setInterval(broadcastToDashboards, 1000);

function broadcastToDashboards() {
    const gameClients = getActiveGameClients();
    const message = JSON.stringify({
        type: 'client_list',
        clients: gameClients
    });

    for (const [clientWs, clientData] of clients.entries()) {
        if (clientData.type === 'dashboard' && clientWs.readyState === WebSocket.OPEN) {
            clientWs.send(message);
        }
    }
}

const PORT = 3000;
server.listen(PORT, () => {
    const banner = `\x1b[35m
   _____                          
  / ___/___  ______   _____  _____
  \\__ \\/ _ \\/ ___/ | / / _ \\/ ___/
 ___/ /  __/ /   | |/ /  __/ /    
/____/\\___/_/    |___/\\___/_/     
\x1b[36m   C O N T R O L L E R   v1.0\x1b[0m
`;
    console.log(banner);
    console.log(`\x1b[36m[i] C2 Server running on http://localhost:${PORT}\x1b[0m`);
    console.log(`\x1b[36m[i] WebSocket endpoint: ws://localhost:${PORT}\x1b[0m`);
    console.log(`\x1b[90m========================================================\x1b[0m\n`);
});
