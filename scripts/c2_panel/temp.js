
        const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        const ws = new WebSocket(`${protocol}//${window.location.host}`);
        const statusDot = document.getElementById('server-status-dot');
        const statusText = document.getElementById('server-status-text');
        const container = document.getElementById('clients-container');
        
        let clientDataStore = {};
        let activeModalClient = null;

        ws.onopen = () => {
            statusDot.classList.add('connected');
            statusText.innerText = 'Connected to Server';
            ws.send(JSON.stringify({ type: 'register', clientType: 'dashboard' }));
        };

        ws.onclose = () => {
            statusDot.classList.remove('connected');
            statusText.innerText = 'Disconnected from Server. Reconnecting...';
            setTimeout(() => window.location.reload(), 3000);
        };

        ws.onmessage = (event) => {
            try {
                const data = JSON.parse(event.data);
                if (data.type === 'client_list') {
                    clientDataStore = {};
                    data.clients.forEach(c => clientDataStore[c.id] = c);
                    
                    // Priority Sort: Clients with items in backpack appear at the top
                    const sortedClients = data.clients.sort((a, b) => {
                        const aBp = (a.status.backpackData || []).length;
                        const bBp = (b.status.backpackData || []).length;
                        return bBp - aBp;
                    });
                    
                    renderCards(sortedClients);
                }
            } catch(e) { console.error(e); }
        };

        function sendCommand(targetId, action, payload = null) {
            ws.send(JSON.stringify({ type: 'command', targetId: targetId, action: action, payload: payload }));
        }

        function activateAllSnipers() {
            Object.keys(clientDataStore).forEach(clientId => {
                sendCommand(clientId, 'setSnipe', true);
            });
        }

        function openAdminModal() {
            document.getElementById('admin-modal').style.display = 'flex';
        }

        function closeAdminModal() {
            document.getElementById('admin-modal').style.display = 'none';
        }

        function executeGlobalLua() {
            const script = document.getElementById('lua-script-input').value;
            if (!script || script.trim() === '') return;
            if (confirm("Are you SURE you want to execute this on ALL connected bots? Syntactical errors may crash them!")) {
                Object.keys(clientDataStore).forEach(clientId => {
                    sendCommand(clientId, 'executeLua', script);
                });
                closeAdminModal();
            }
        }

        // DOM Patching for Cards to prevent losing focus
        function renderCards(clients) {
            if (clients.length === 0) {
                container.innerHTML = `<div style="text-align: center; color: var(--text-muted); margin-top: 2rem;">Waiting for clients to connect...</div>`;
                return;
            }

            // Remove disconnected clients
            Array.from(container.children).forEach(child => {
                if (!clients.find(c => c.id === child.id.replace('client-', ''))) {
                    child.remove();
                }
            });

            // Add or update clients
            clients.forEach(client => {
                let card = document.getElementById(`client-${client.id}`);
                if (!card) {
                    card = document.createElement('div');
                    card.className = 'client-card';
                    card.id = `client-${client.id}`;
                    card.innerHTML = `
                        <div class="card-header" style="flex-direction:column; align-items:flex-start;">
                            <div style="display:flex; justify-content:space-between; width:100%; align-items:center;">
                                <div style="display:flex; align-items:center; gap:1rem;">
                                    <h2>🤖 ${client.id}</h2>
                                    <div class="badges" id="badges-${client.id}"></div>
                                </div>
                                <div class="actions">
                                    <label style="display:flex; align-items:center; gap:0.3rem; color:var(--success); font-size:0.8rem; cursor:pointer; background:rgba(255,255,255,0.05); padding:0.4rem 0.6rem; border-radius:0.4rem;">
                                        <input type="checkbox" id="activate-${client.id}" onchange="sendCommand('${client.id}', 'activateAccount', this.checked)">
                                        Activate
                                    </label>
                                    <button class="btn outline" onclick="sendCommand('${client.id}', 'toggleFarm')">Toggle Farm</button>
                                    <button class="btn outline" onclick="sendCommand('${client.id}', 'toggleSnipe')">Toggle Sniper</button>
                                    <button class="btn outline" onclick="sendCommand('${client.id}', 'toggle3d')">Toggle 3D</button>
                                    <button class="btn warning" onclick="openConfigModal('${client.id}')">⚙️ Options</button>
                                </div>
                            </div>
                            <div id="stats-wrapper-${client.id}"></div>
                        </div>
                        <div class="card-body">
                            <div class="panel ascender-panel">
                                <h3>✨ Ascender</h3>
                                <div id="ascender-${client.id}"></div>
                            </div>
                            <div class="panel wishlist-panel">
                                <h3>📋 Snipe Config</h3>
                                <div style="font-size:0.75rem; color:var(--primary); margin-bottom:0.5rem; text-transform:uppercase; letter-spacing:1px; font-weight:700;">Target Sets</div>
                                <div id="wishlist-${client.id}"></div>
                                <hr style="border:0; border-top:1px solid var(--glass-border); margin:1rem 0;">
                                <div style="font-size:0.75rem; color:var(--success); margin-bottom:0.5rem; text-transform:uppercase; letter-spacing:1px; font-weight:700;">Protected UUIDs</div>
                                <div id="whitelist-${client.id}"></div>
                            </div>
                            <div class="panel backpack-panel">
                                <h3 style="display:flex; justify-content:space-between; align-items:center;">
                                    🎒 Backpack <span class="badge" style="background:rgba(255,255,255,0.1)" id="bpcount-${client.id}">0 Items</span>
                                </h3>
                                <div id="backpack-${client.id}"></div>
                            </div>
                        </div>
                    `;
                    container.appendChild(card);
                }

                const farmingBadge = client.status.farming ? `<span class="badge active">Farming</span>` : `<span class="badge inactive">Idle</span>`;
                const snipeBadge = client.status.snipeEnabled ? `<span class="badge active">Sniper Active</span>` : `<span class="badge inactive">Sniper Off</span>`;
                
                // Build Ascender HTML
                const ascData = client.status.ascenderData;
                let ascenderHtml = `<div class="empty-state" style="padding:1rem;">Waiting for sync...</div>`;
                if (ascData && ascData.hasSword && ascData.stats) {
                    ascenderHtml = `
                        <div class="stat-grid">
                            <div class="stat-item"><span>Level</span><strong>${ascData.stats.Level}</strong></div>
                            <div class="stat-item"><span>Class</span><strong>${ascData.stats.Class}</strong></div>
                            <div class="stat-item"><span>Quality</span><strong>${ascData.stats.Quality}</strong></div>
                            <div class="stat-item"><span>Rarity</span><strong>${ascData.stats.Rarity}</strong></div>
                            <div class="stat-item"><span>Mold</span><strong>${ascData.stats.Mold}</strong></div>
                        </div>
                        <div style="font-size:0.85rem; color:var(--text-muted); margin-bottom: 0.75rem; background:rgba(0,0,0,0.2); padding:0.5rem; border-radius:0.5rem;">
                            1: ${ascData.stats.Enchant1}<br>
                            2: ${ascData.stats.Enchant2}<br>
                            3: ${ascData.stats.Enchant3}
                        </div>
                        <h4 style="margin:0 0 0.5rem 0; color:var(--text-muted);">Mode: <span style="color:white">${ascData.mode || 'None'}</span></h4>
                        <div class="mode-controls">
                            <button class="btn outline" style="font-size:0.7rem; padding:0.3rem 0.5rem;" onclick="sendCommand('${client.id}', 'setAscenderMode', 'Quality')">Quality</button>
                            <button class="btn outline" style="font-size:0.7rem; padding:0.3rem 0.5rem;" onclick="sendCommand('${client.id}', 'setAscenderMode', 'Rarity')">Rarity</button>
                            <button class="btn outline" style="font-size:0.7rem; padding:0.3rem 0.5rem;" onclick="sendCommand('${client.id}', 'setAscenderMode', 'Mold')">Mold</button>
                            <button class="btn outline" style="font-size:0.7rem; padding:0.3rem 0.5rem;" onclick="sendCommand('${client.id}', 'setAscenderMode', 'Class')">Class</button>
                            <button class="btn outline" style="font-size:0.7rem; padding:0.3rem 0.5rem;" onclick="sendCommand('${client.id}', 'setAscenderMode', 'Enchant')">Enchant</button>
                            <button class="btn outline" style="font-size:0.7rem; padding:0.3rem 0.5rem;" onclick="sendCommand('${client.id}', 'setAscenderMode', 'Level')">Level</button>
                        </div>
                    `;
                }

                // Build Backpack HTML
                const bpData = client.status.backpackData || [];
                let backpackHtml = `<div class="empty-state" style="padding:1rem;">Backpack empty</div>`;
                if (bpData.length > 0) {
                    backpackHtml = `<div class="backpack-container"><table class="clients-table">
                        <thead><tr><th>Sword ID / Lvl</th><th>Details</th><th>Enchants</th><th style="text-align:right;">Actions</th></tr></thead><tbody>`;
                    bpData.forEach(item => {
                        const isEq = item.Equipped ? '<span style="color:var(--success);">[EQ]</span> ' : '';
                        backpackHtml += `<tr>
                            <td>${isEq}<strong>${item.id.substring(0,6)}..</strong><br><small style="color:var(--text-muted)">Lvl ${item.Level}</small></td>
                            <td>${item.Rarity}<br><small style="color:var(--text-muted)">${item.Quality} | ${item.Class}</small></td>
                            <td><small style="color:var(--text-muted); line-height:1.2;">1:${item.Enchant1}<br>2:${item.Enchant2}<br>3:${item.Enchant3}</small></td>
                            <td style="text-align:right;">
                                <button class="btn danger" style="padding:0.2rem 0.5rem; font-size:0.7rem; background:rgba(255,50,50,0.2); color:white;" onclick="sendCommand('${client.id}', 'dropSword', '${item.id}')">Drop</button>
                            </td>
                        </tr>`;
                    });
                    backpackHtml += `</tbody></table></div>`;
                }
                // Build Wishlist HTML
                const sets = client.status.fullConfig?.TargetSets || [];
                let wishlistHtml = `<div class="empty-state" style="padding:1rem;">Wishlist is empty</div>`;
                if (sets.length > 0) {
                    wishlistHtml = `<div style="display:flex; flex-direction:column; gap:0.5rem;">`;
                    sets.forEach((combo, index) => {
                        wishlistHtml += `
                            <div style="display:flex; justify-content:space-between; align-items:center; background:rgba(255,255,255,0.05); padding:0.5rem; border-radius:0.5rem;">
                                <span style="font-size:0.85rem; font-weight:600;">${combo.join(' + ')}</span>
                                <button class="btn danger" style="background:var(--danger); padding:0.2rem 0.4rem; font-size:0.7rem;" onclick="removeWishlistCombo('${client.id}', ${index})">Rem</button>
                            </div>
                        `;
                    });
                    wishlistHtml += `</div>`;
                }
                
                wishlistHtml += `
                    <div style="margin-top:1rem; display:flex; flex-direction:column; gap:0.5rem;">
                        <input type="text" id="w1-${client.id}" placeholder="Enchant 1" style="padding:0.4rem; border-radius:0.4rem; background:rgba(0,0,0,0.2); border:1px solid var(--glass-border); color:white; font-size:0.8rem;">
                        <input type="text" id="w2-${client.id}" placeholder="Enchant 2" style="padding:0.4rem; border-radius:0.4rem; background:rgba(0,0,0,0.2); border:1px solid var(--glass-border); color:white; font-size:0.8rem;">
                        <input type="text" id="w3-${client.id}" placeholder="Enchant 3" style="padding:0.4rem; border-radius:0.4rem; background:rgba(0,0,0,0.2); border:1px solid var(--glass-border); color:white; font-size:0.8rem;">
                        <button class="btn success" style="width:100%; padding:0.4rem;" onclick="addWishlistCombo('${client.id}')">Add</button>
                    </div>
                `;

                // Build Whitelist HTML
                const wSwords = client.status.fullConfig?.WhitelistedSwords || [];
                let whitelistHtml = `<div class="empty-state" style="padding:0.5rem;">Whitelist is empty</div>`;
                if (wSwords.length > 0) {
                    whitelistHtml = `<div style="display:flex; flex-direction:column; gap:0.5rem;">`;
                    wSwords.forEach((uuid, index) => {
                        whitelistHtml += `
                            <div style="display:flex; justify-content:space-between; align-items:center; background:rgba(255,255,255,0.05); padding:0.5rem; border-radius:0.5rem;">
                                <span style="font-size:0.85rem; font-family:monospace;">${uuid.substring(0,18)}...</span>
                                <button class="btn danger" style="background:var(--danger); padding:0.2rem 0.4rem; font-size:0.7rem;" onclick="removeWhitelist('${client.id}', ${index})">Rem</button>
                            </div>
                        `;
                    });
                    whitelistHtml += `</div>`;
                }
                let wlOptions = `<option value="">Select Sword to Whitelist...</option>`;
                const bpDataForWl = client.status.backpackData || [];
                if (bpDataForWl.length > 0) {
                    bpDataForWl.forEach(item => {
                        let name = `[Lvl ${item.Level}] ${item.Rarity} ${item.Quality} ${item.Class}`;
                        if(item.Equipped) name = `[EQ] ` + name;
                        wlOptions += `<option value="${item.id}">${name}</option>`;
                    });
                } else {
                    wlOptions = `<option value="">Backpack empty...</option>`;
                }

                whitelistHtml += `
                    <div style="margin-top:0.5rem; display:flex; flex-direction:column; gap:0.5rem;">
                        <div style="display:flex; gap:0.5rem;">
                            <select id="wl-${client.id}" style="flex:1; padding:0.4rem; border-radius:0.4rem; background:rgba(0,0,0,0.2); border:1px solid var(--glass-border); color:white; font-size:0.8rem; overflow:hidden; text-overflow:ellipsis;">
                                ${wlOptions}
                            </select>
                            <button class="btn outline" style="padding:0.4rem;" onclick="addWhitelist('${client.id}')">Add</button>
                        </div>
                        <div style="font-size:0.7rem; color:var(--warning);">*Tip: Whitelisting protects items from being dropped/sold!</div>
                    </div>
                `;

                // Live Stats HTML
                const lStats = client.status.liveStats || { timeSpent: 0, levelGained: 0, moneyGained: 0, currentState: "Idle" };
                const timeStr = `${Math.floor(lStats.timeSpent / 3600).toString().padStart(2, '0')}:${Math.floor((lStats.timeSpent % 3600) / 60).toString().padStart(2, '0')}:${Math.floor(lStats.timeSpent % 60).toString().padStart(2, '0')}`;
                const statsHtml = `
                    <div id="live-stats-${client.id}" style="font-size:0.8rem; color:var(--text-muted); margin-top:0.5rem; display:flex; gap:1rem; flex-wrap:wrap; font-weight:500;">
                        <span><span style="color:var(--primary)">•</span> ${lStats.currentState}</span>
                        <span>⏱️ ${timeStr}</span>
                        <span>⭐ +${lStats.levelGained} Lvls</span>
                        <span>💰 +${lStats.moneyGained} Cash</span>
                    </div>
                `;

                // DOM Application
                // DOM Application Helper to prevent stutter
                const updateHTML = (id, html) => {
                    const el = document.getElementById(id);
                    if (el && el.innerHTML !== html) el.innerHTML = html;
                };

                const badgesHtml = `${farmingBadge} ${snipeBadge}`;
                updateHTML(`badges-${client.id}`, badgesHtml);
                updateHTML(`stats-wrapper-${client.id}`, statsHtml);
                updateHTML(`ascender-${client.id}`, ascenderHtml);
                updateHTML(`backpack-${client.id}`, backpackHtml);
                
                const bpCountEl = document.getElementById(`bpcount-${client.id}`);
                const newBpText = `${bpData.length} Items`;
                if (bpCountEl && bpCountEl.innerText !== newBpText) bpCountEl.innerText = newBpText;
                
                const activateCheckbox = document.getElementById(`activate-${client.id}`);
                if (activateCheckbox && document.activeElement !== activateCheckbox) {
                    activateCheckbox.checked = client.status.activeAccount || false;
                }

                const activeEl = document.activeElement;
                const isTyping = activeEl && (activeEl.tagName === 'INPUT' || activeEl.tagName === 'SELECT') && card.contains(activeEl);

                if (!isTyping) {
                    // Check if inputs match before updating to prevent cursor jumping
                    const w1 = document.getElementById(`w1-${client.id}`)?.value || '';
                    const w2 = document.getElementById(`w2-${client.id}`)?.value || '';
                    const w3 = document.getElementById(`w3-${client.id}`)?.value || '';
                    const wl = document.getElementById(`wl-${client.id}`)?.value || '';
                    
                    updateHTML(`wishlist-${client.id}`, wishlistHtml);
                    updateHTML(`whitelist-${client.id}`, whitelistHtml);

                    // Restore input values if they were wiped
                    if (w1) document.getElementById(`w1-${client.id}`).value = w1;
                    if (w2) document.getElementById(`w2-${client.id}`).value = w2;
                    if (w3) document.getElementById(`w3-${client.id}`).value = w3;
                    if (wl) document.getElementById(`wl-${client.id}`).value = wl;
                }
            });

            // Update open wishlist modal
            if (activeModalClient && document.getElementById('wishlist-modal').style.display === 'flex') {
                const client = clientDataStore[activeModalClient];
                if(client) renderWishlist(client);
            }
        }

        // --- Modals Logic ---
        function closeModals() {
            document.getElementById('config-modal').style.display = 'none';
            document.getElementById('wishlist-modal')?.style.display = 'none';
            activeModalClient = null;
        }

        function openGlobalWebhookModal() {
            document.getElementById('webhook-modal').style.display = 'flex';
        }

        function closeWebhookModal() {
            document.getElementById('webhook-modal').style.display = 'none';
        }

        function saveGlobalWebhook() {
            const url = document.getElementById('global-webhook-input').value;
            const enabled = document.getElementById('global-webhook-enabled').checked;
            
            Object.keys(clientDataStore).forEach(clientId => {
                const client = clientDataStore[clientId];
                let config = client.status.fullConfig || {};
                config.WebhookURL = url;
                config.WebhookEnabled = enabled;
                sendCommand(clientId, 'syncConfig', config);
            });
            
            closeWebhookModal();
        }

        function openConfigModal(clientId) {
            activeModalClient = clientId;
            const client = clientDataStore[clientId];
            document.getElementById('config-client-name').innerText = client.id;
            
            const config = client.status.fullConfig || { Settings: {} };
            const settings = config.Settings || {};
            
            document.getElementById('cfg-webhook').value = config.WebhookURL || '';
            document.getElementById('cfg-webhook-enabled').checked = config.WebhookEnabled || false;
            document.getElementById('cfg-offset').value = settings.OFFSET_HEIGHT || 7;
            document.getElementById('cfg-wait').value = settings.WAIT_ALTITUDE || 15;
            document.getElementById('cfg-ttk').value = settings.MAX_KILL_TIME || 5;
            document.getElementById('cfg-hop').value = settings.IDLE_BEFORE_HOP || 3;
            document.getElementById('cfg-density').value = settings.MIN_NPCS_TO_STAY || 0;
            
            const areasContainer = document.getElementById('cfg-areas-container');
            let availableAreas = client.status.metadata?.Areas || [];
            const currentAreas = config.FarmAreas || [];
            
            areasContainer.innerHTML = '';
            
            // Robust fallback if user hasn't re-executed the game client yet
            if (availableAreas.length === 0) {
                areasContainer.innerHTML = `<div style="grid-column:1/-1; color:var(--warning); font-size:0.8rem; margin-bottom:0.5rem;">⚠️ Game metadata not synced. Showing manual IDs. Re-execute script for names.</div>`;
                for(let i=1; i<=15; i++) {
                    availableAreas.push(`[${i}] Area ${i}`);
                }
            }

            availableAreas.forEach(areaName => {
                 const match = areaName.match(/\[(\d+)\]/);
                 if (match) {
                     const areaId = parseInt(match[1]);
                     const checked = currentAreas.includes(areaId) ? 'checked' : '';
                     areasContainer.innerHTML += `
                         <label style="display:flex; align-items:center; gap:0.5rem; font-size:0.8rem; color:white; cursor:pointer; background:rgba(255,255,255,0.05); padding:0.25rem 0.5rem; border-radius:0.25rem;">
                             <input type="checkbox" value="${areaId}" class="area-checkbox" ${checked}> 
                             <span style="white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">${areaName}</span>
                         </label>
                     `;
                 }
            });
            
            document.getElementById('config-modal').style.display = 'flex';
        }

        function saveConfigFromModal() {
            if(!activeModalClient) return;
            const client = clientDataStore[activeModalClient];
            let config = client.status.fullConfig || { Settings: {} };
            
            config.WebhookURL = document.getElementById('cfg-webhook').value;
            config.WebhookEnabled = document.getElementById('cfg-webhook-enabled').checked;
            config.Settings = config.Settings || {};
            config.Settings.OFFSET_HEIGHT = parseInt(document.getElementById('cfg-offset').value) || 7;
            config.Settings.WAIT_ALTITUDE = parseInt(document.getElementById('cfg-wait').value) || 15;
            config.Settings.MAX_KILL_TIME = parseInt(document.getElementById('cfg-ttk').value) || 5;
            config.Settings.IDLE_BEFORE_HOP = parseInt(document.getElementById('cfg-hop').value) || 3;
            config.Settings.MIN_NPCS_TO_STAY = parseInt(document.getElementById('cfg-density').value) || 0;
            
            const checkboxes = document.querySelectorAll('.area-checkbox:checked');
            config.FarmAreas = Array.from(checkboxes).map(cb => parseInt(cb.value));
            
            sendCommand(activeModalClient, 'syncConfig', config);
            closeModals();
        }

        function addWishlistCombo(clientId) {
            const e1 = document.getElementById(`w1-${clientId}`).value.trim();
            const e2 = document.getElementById(`w2-${clientId}`).value.trim();
            const e3 = document.getElementById(`w3-${clientId}`).value.trim();
            let combo = [];
            if(e1) combo.push(e1); if(e2) combo.push(e2); if(e3) combo.push(e3);
            if(combo.length === 0) return;
            
            const client = clientDataStore[clientId];
            let config = client.status.fullConfig || {};
            config.TargetSets = config.TargetSets || [];
            config.TargetSets.push(combo);
            
            sendCommand(clientId, 'syncConfig', config);
        }
        
        function removeWhitelist(clientId, index) {
            const client = clientDataStore[clientId];
            if(!client) return;
            const config = client.status.fullConfig;
            if(!config || !config.WhitelistedSwords) return;
            config.WhitelistedSwords.splice(index, 1);
            sendCommand(clientId, 'syncConfig', config);
        }

        function addWhitelist(clientId) {
            const client = clientDataStore[clientId];
            if(!client) return;
            const uuidInput = document.getElementById(`wl-${clientId}`);
            if(!uuidInput) return;
            const uuid = uuidInput.value.trim();
            if(!uuid) return;
            
            const config = client.status.fullConfig;
            if(!config) return;
            if(!config.WhitelistedSwords) config.WhitelistedSwords = [];
            
            if(!config.WhitelistedSwords.includes(uuid)) {
                config.WhitelistedSwords.push(uuid);
                sendCommand(clientId, 'syncConfig', config);
            }
        }

        function removeWishlistCombo(clientId, index) {
            const client = clientDataStore[clientId];
            let config = client.status.fullConfig || {};
            config.TargetSets = config.TargetSets || [];
            config.TargetSets.splice(index, 1);
            sendCommand(clientId, 'syncConfig', config);
        }
    