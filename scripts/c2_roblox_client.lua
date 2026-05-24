--[[
    C2 ROBLOX FLEET NODE CLIENT v1.0
    This Lua script runs within a modern Roblox script executor (Synapse, Electron, Wave, etc.)
    It connects to the C2 WebSocket server, performs auto-registration,
    streams gameplay telemetry (level, money, backpack), and responds to remote commands in real-time.
--]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- C2 Connection Configuration
local SERVER_HOST = "c2scripts.xyz" -- Production Host
local TELEMETRY_DELAY = 6 -- Heartbeat delay in seconds
local WS_URL = "wss://" .. SERVER_HOST .. "/ws/c2/"

print("[C2 Client] Initializing Roblox Fleet Node...")

-- Global State Control Variables (used by your external autofarm scripts)
_G.C2_ApiKey = "your_api_key_here" -- Get your API Key from the c2scripts.xyz dashboard (Hover to reveal it) and paste it here
_G.Luarmor_License = "your_luarmor_license_here" -- Paste your active Luarmor license here
_G.C2_FarmEnabled = true
_G.C2_SnipeEnabled = true
_G.C2_TargetEnchantSets = {}
_G.C2_WhitelistedUUIDs = {}
_G.C2_3DRendering = true

-- Utility function to get current stats (modify these to bind to your specific game's leaderstats or state)
local function getLocalStats()
    local level = 1
    local money = 0
    local botClass = "Beginner"
    local quality = "Normal"
    local rarity = "Common"
    local mold = "Basic"

    -- Attempt dynamic game state bindings
    pcall(function()
        if LocalPlayer:FindFirstChild("leaderstats") then
            if LocalPlayer.leaderstats:FindFirstChild("Level") then
                level = LocalPlayer.leaderstats.Level.Value
            end
            if LocalPlayer.leaderstats:FindFirstChild("Gold") then
                money = LocalPlayer.leaderstats.Gold.Value
            elseif LocalPlayer.leaderstats:FindFirstChild("Money") then
                money = LocalPlayer.leaderstats.Money.Value
            end
        end
    end)

    return {
        level = level,
        money = money,
        bot_class = botClass,
        quality = quality,
        rarity = rarity,
        mold = mold
    }
end

-- Utility function to serialize current backpack items
local function getBackpackItems()
    local items = {}
    pcall(function()
        local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        if backpack then
            for _, item in ipairs(backpack:GetChildren()) do
                if item:IsA("Tool") then
                    table.insert(items, {
                        uuid = item.Name .. "_" .. tostring(item.Reference.Value or math.random(1000, 9999)),
                        name = item.Name,
                        traits = {"Bound", "Level 1"}
                    })
                end
            end
        end
    end)
    return items
end

-- Connect to WebSocket using WebSocket.connect or syn.websocket.connect
local ws
local isKicked = false

local function startC2Connection()
    while not isKicked do
        print("[C2 Client] Attempting to connect to C2 Server...")
        local socket = nil
        local success, err = pcall(function()
            if WebSocket and WebSocket.connect then
                socket = WebSocket.connect(WS_URL)
            elseif syn and syn.websocket and syn.websocket.connect then
                socket = syn.websocket.connect(WS_URL)
            else
                error("Executor does not support WebSockets! Need syn.websocket or WebSocket library.")
            end
        end)
        
        if success and socket then
            print("[C2 Client] Connected successfully to " .. WS_URL)
            
            -- Auto-register Node
            local registerPayload = {
                action = "register",
                username = LocalPlayer.Name,
                api_key = _G.C2_ApiKey or "",
                license_key = _G.Luarmor_License or ""
            }
            local regSuccess = pcall(function()
                socket:Send(HttpService:JSONEncode(registerPayload))
            end)
            
            if regSuccess then
                print("[C2 Client] Registered Node for user: " .. LocalPlayer.Name .. " (API Key: " .. tostring(_G.C2_ApiKey) .. ", License: " .. tostring(_G.Luarmor_License) .. ")")
                ws = socket -- Assign active socket globally for telemetry heartbeats
                
                -- Message receiver loop (blocks this thread until connection is severed)
                while not isKicked do
                    local message
                    local receiveSuccess = pcall(function()
                        message = socket:Receive()
                    end)
                    
                    if not receiveSuccess or not message then
                        warn("[C2 Client] Lost socket connection.")
                        break
                    end
                    
                    local decodeSuccess, data = pcall(function()
                        return HttpService:JSONDecode(message)
                    end)
                    
                    if decodeSuccess and data and data.type == "command" then
                        local command = data.command
                        local payload = data.payload or {}
                        
                        print("[C2 Client] Incoming Command: " .. tostring(command))
                        
                        if command == "syncConfig" then
                            -- Sync active config variables
                            _G.C2_FarmEnabled = payload.farm_enabled
                            _G.C2_SnipeEnabled = payload.snipe_enabled
                            _G.C2_TargetEnchantSets = payload.target_enchant_sets or {}
                            _G.C2_WhitelistedUUIDs = payload.whitelisted_uuids or {}
                            print("[C2 Client] Configuration synchronized successfully.")
                            
                        elseif command == "teleportHome" then
                            -- Relaying home teleportation logic
                            pcall(function()
                                local character = LocalPlayer.Character
                                if character and character:FindFirstChild("HumanoidRootPart") then
                                    character.HumanoidRootPart.CFrame = CFrame.new(0, 50, 0)
                                    print("[C2 Client] Teleported to home coordinates.")
                                end
                            end)
                            
                        elseif command == "toggle3D" then
                            -- Toggle 3D rendering to optimize CPU/RAM
                            _G.C2_3DRendering = not _G.C2_3DRendering
                            pcall(function()
                                game:GetService("RunService"):Set3dRenderingEnabled(_G.C2_3DRendering)
                            end)
                            print("[C2 Client] 3D rendering enabled: " .. tostring(_G.C2_3DRendering))
                            
                        elseif command == "kick" then
                            isKicked = true
                            local reason = payload.reason or "Disconnected by C2 Server."
                            print("[C2 Client] Kicking player: " .. reason)
                            pcall(function()
                                LocalPlayer:Kick(reason)
                            end)
                            break
                        end
                    end
                end
            else
                warn("[C2 Client] Registration failed.")
            end
        else
            warn("[C2 Client] Connection failure: " .. tostring(err))
        end
        
        -- Clean up references on disconnect
        ws = nil
        if isKicked then break end
        
        print("[C2 Client] Retrying connection in 10 seconds...")
        task.wait(10)
    end
end

-- Start connection coordinator thread
task.spawn(startC2Connection)

-- Send continuous gameplay telemetry heartbeat logs
task.spawn(function()
    while true do
        task.wait(TELEMETRY_DELAY)
        
        if ws and not isKicked then
            -- Generate realistic telemetry logs
            local stats = getLocalStats()
            local logPayload = {
                action = "log",
                username = LocalPlayer.Name,
                event_type = _G.C2_FarmEnabled and "Farming" or "Idle",
                message = "Farming nodes in active area. level = " .. tostring(stats.level) .. ", money = " .. tostring(stats.money)
            }
            
            pcall(function()
                ws:Send(HttpService:JSONEncode(logPayload))
            end)
        end
    end
end)
