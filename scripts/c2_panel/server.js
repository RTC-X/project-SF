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
    // Only protect the dashboard, not the script loader endpoint
    if (req.path === '/api/get_script') return next();

    const b64auth = (req.headers.authorization || '').split(' ')[1] || '';
    const [login, password] = Buffer.from(b64auth, 'base64').toString().split(':');

    if (login && password && login === PANEL_USERNAME && password === PANEL_PASSWORD) {
        return next();
    }

    res.set('WWW-Authenticate', 'Basic realm="Secure C2 Panel"');
    res.status(401).send('401 Unauthorized - Secure C2 Access Only.');
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
                    sendClientsToDashboard(ws);
                    console.log('\x1b[35m[+] Dashboard connected\x1b[0m');
                }
            } else if (data.type === 'update_status') {
                if (clients.has(ws)) {
                    const clientData = clients.get(ws);
                    clientData.status = { ...clientData.status, ...data.status };
                    broadcastToDashboards();
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
                            clientWs.send(JSON.stringify({ action: data.action, payload: data.payload }));
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

function getActiveGameClients() {
    const gameClients = [];
    for (const [clientWs, clientData] of clients.entries()) {
        if (clientData.type === 'game') {
            gameClients.push({
                id: clientData.id,
                status: clientData.status
            });
        }
    }
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
