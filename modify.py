import re

file_path = r'c:\Users\Alex\Documents\GitHub\project-SF\templates\dashboard.html'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Change multiConfigSelectedIds initialization from [] to {}
content = re.sub(r'multiConfigSelectedIds:\s*\[\],', r'multiConfigSelectedIds: {},', content)
content = re.sub(r'multiConfigSelectedIds\s*=\s*\[\]', r'multiConfigSelectedIds = {}', content)

# 2. Change .includes() and .push() and .filter() for multiConfigSelectedIds
content = content.replace('multiConfigSelectedIds.includes(bot.id)', 'multiConfigSelectedIds[bot.id]')
content = content.replace('multiConfigSelectedIds.includes(id)', 'multiConfigSelectedIds[id]')
content = content.replace('multiConfigSelectedIds.push(bot.id)', 'multiConfigSelectedIds[bot.id] = true')
content = content.replace('multiConfigSelectedIds = multiConfigSelectedIds.filter(id => id !== bot.id)', 'delete multiConfigSelectedIds[bot.id]')
content = content.replace('multiConfigSelectedIds = multiConfigSelectedIds.filter(id => !visibleBots.map(b => b.id).includes(id))', 'visibleBots.forEach(b => delete multiConfigSelectedIds[b.id])')
content = content.replace('multiConfigSelectedIds.length', 'Object.keys(multiConfigSelectedIds).length')

# 3. Change multiConfigSelectedIds.forEach to Object.keys().forEach
content = content.replace('multiConfigSelectedIds.forEach(id => {', 'Object.keys(multiConfigSelectedIds).forEach(id => {')

# 4. Modify sendCommand in the script block
new_send_command = '''    sendCommand(botId, action, payload = {}) {
        if (this.ws && this.ws.readyState === WebSocket.OPEN) {
            this.ws.send(JSON.stringify({
                action: 'command',
                target_ids: Array.isArray(botId) ? botId : [botId],
                command: action,
                payload: payload
            }));
        }
    },'''
content = re.sub(r'sendCommand\s*\(botId,\s*action,\s*payload\s*=\s*\{\}\)\s*\{[\s\S]*?\},(?=\n\s*resetFleet)', new_send_command, content)

# 5. Modify the multi-config payload to send bulk command instead of looping
old_bulk = '''Object.keys(multiConfigSelectedIds).forEach(id => {
                            // 1. Sync config settings
                            sendCommand(id, 'syncConfig', {
                                farm_enabled: multiConfigData.farm_enabled,
                                snipe_enabled: multiConfigData.snipe_enabled,
                                bot_class: multiConfigData.BotClass || 'Unbeatable',
                                quality: multiConfigData.Quality || 'Spectacular',
                                rarity: multiConfigData.Rarity || 'Heavenly++',
                                mold: multiConfigData.Mold || 'Crystal',
                                level: parseInt(multiConfigData.Level) || 490,
                                target_enchant_sets: multiConfigData.target_enchant_sets,
                                whitelisted_uuids: multiConfigData.whitelisted_uuids,
                                offset_height: parseInt(multiConfigData.offset_height),
                                wait_altitude: parseInt(multiConfigData.wait_altitude)
                            });
                            // 2. Dispatch teleport Home or Toggle 3D rendering if enabled
                            if (multiConfigData.TeleportHome) {
                                sendCommand(id, 'teleportHome');
                            }
                            if (multiConfigData.Toggle3D) {
                                sendCommand(id, 'toggle3D');
                            }
                        });'''

new_bulk = '''let targetIds = Object.keys(multiConfigSelectedIds);
                        let payload = {
                            farm_enabled: multiConfigData.farm_enabled,
                            snipe_enabled: multiConfigData.snipe_enabled,
                            offset_height: parseInt(multiConfigData.offset_height) || 7,
                            wait_altitude: parseInt(multiConfigData.wait_altitude) || 15
                        };
                        if (multiConfigData.target_enchant_sets.length > 0) payload.target_enchant_sets = multiConfigData.target_enchant_sets;
                        if (multiConfigData.whitelisted_uuids.length > 0) payload.whitelisted_uuids = multiConfigData.whitelisted_uuids;
                        if (multiConfigData.BotClass || multiConfigData.Quality || multiConfigData.Rarity || multiConfigData.Mold || multiConfigData.Level) {
                            payload.ascender_criteria = {
                                Class: multiConfigData.BotClass || 'Unbeatable',
                                Quality: multiConfigData.Quality || 'Spectacular',
                                Rarity: multiConfigData.Rarity || 'Heavenly++',
                                Mold: multiConfigData.Mold || 'Crystal',
                                Level: parseInt(multiConfigData.Level) || 490
                            };
                        }
                        
                        sendCommand(targetIds, 'syncConfig', payload);
                        
                        if (multiConfigData.TeleportHome) sendCommand(targetIds, 'teleportHome');
                        if (multiConfigData.Toggle3D) sendCommand(targetIds, 'toggle3D');'''

content = content.replace(old_bulk, new_bulk)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Modifications applied successfully")
