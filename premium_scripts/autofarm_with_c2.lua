-- [[ ⚙️ CONFIGURATION - EDIT THESE IF RUNNING STANDALONE ]]
local STANDALONE_C2_API_KEY = "your_api_key_here"      -- Paste your C2 API Key here (or leave blank if using a loader)
local STANDALONE_LUARMOR_LICENSE = "your_license_here"  -- Paste your Luarmor License key here (or leave blank if using a loader)

-- [[ RESOLVE KEYS (Arguments -> Globals -> Config Variables) ]]
local args = {...}
local C2_API_KEY = (args[1] and type(args[1]) == "string" and args[1] ~= "") or (_G.C2_ApiKey and _G.C2_ApiKey ~= "") or (STANDALONE_C2_API_KEY ~= "your_api_key_here" and STANDALONE_C2_API_KEY) or ""
local LUARMOR_LICENSE = (args[2] and type(args[2]) == "string" and args[2] ~= "") or (_G.Luarmor_License and _G.Luarmor_License ~= "") or (STANDALONE_LUARMOR_LICENSE ~= "your_license_here" and STANDALONE_LUARMOR_LICENSE) or ""

if not C2_API_KEY or C2_API_KEY == "" then
    warn("[!] Missing C2_API_KEY! Please configure STANDALONE_C2_API_KEY at the top of this script, or ensure your loader passes it.")
    return
end
if not LUARMOR_LICENSE or LUARMOR_LICENSE == "" then
    warn("[!] Missing LUARMOR_LICENSE! Please configure STANDALONE_LUARMOR_LICENSE at the top of this script, or ensure your loader passes it.")
    return
end

if not LPH_NO_VIRTUALIZE then
    LPH_NO_VIRTUALIZE = function(f) return f end
end

-- [[ 0. MEMORY LEAK CLEANUP ]]
local function disconnectIfConnected(conn)
    if conn and typeof(conn) == "RBXScriptConnection" and conn.Connected then
        conn:Disconnect()
    end
end
disconnectIfConnected(_G.UltimateFarmConnection)
disconnectIfConnected(_G.CharRespawnConnection)
disconnectIfConnected(_G.SwordAddedConnection)
disconnectIfConnected(_G.InvAddedConnection)
disconnectIfConnected(_G.SellingAddedConnection)
disconnectIfConnected(_G.GraphicsStripperConnection)

if _G.AntiAFKConnection then task.cancel(_G.AntiAFKConnection); _G.AntiAFKConnection = nil end
if _G.InventorySweeperConnection then task.cancel(_G.InventorySweeperConnection); _G.InventorySweeperConnection = nil end
if _G.C2ConnectionTask then task.cancel(_G.C2ConnectionTask); _G.C2ConnectionTask = nil end
if _G.MainLoopTask then task.cancel(_G.MainLoopTask); _G.MainLoopTask = nil end
if _G.PeriodicLogTask then task.cancel(_G.PeriodicLogTask); _G.PeriodicLogTask = nil end

if _G.C2_WS then 
    pcall(function() _G.C2_WS:Close() end)
    _G.C2_WS = nil
end

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualInputManager = game:GetService("VirtualInputManager")
local HttpService = game:GetService("HttpService")
local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local hrp = character:WaitForChild("HumanoidRootPart")
local humanoid = character:WaitForChild("Humanoid")
local playerGui = player:WaitForChild("PlayerGui")

-- 🛑 DEFINED AT TOP TO PREVENT UI LOAD ERRORS
local PlayerStats = ReplicatedStorage:WaitForChild("Stats"):WaitForChild(tostring(player.Name))
local PlayerBackPackSwords = PlayerStats:WaitForChild("Swords")

-- [[ 1. STATE & CONFIGURATION ]]
_G.on = false 
_G.SavedSwordName = nil 
_G.CurrentState = "Idle"
_G.TargetPriority = "Closest"

-- Sniper, Drop & Mass Recovery States
_G.autoDropEnabled = false
_G.fetchingGodRoll = false 
_G.ActiveTargetSets = { {"Ancient", "Fortune", "Insight"} } 
_G.WhitelistedSwords = {} 
_G.KeptSwords = {} -- The Live Ledger for Mass Recovery
_G.SpecialOverrides = {Enchant = {}, Mold = {}, Quality = {}, Rarity = {}, Class = {}}
_G.WebhookURL = ""
_G.WebhookEnabled = false

-- C2 Server Configuration
_G.C2_SERVER_URL = "wss://c2scripts.xyz/ws/c2/"

-- Area Rotation States
_G.FarmAreas = {} 
local activeAreaRotationIds = {}

local StagedEnchant1, StagedEnchant2, StagedEnchant3 = "None", "None", "None"
local ManualWhitelistInput = ""
local SaveFileName = "UltimateFarm_" .. player.Name .. "_" .. player.UserId .. ".json"

local function SaveLocalConfig()
    pcall(function()
        if writefile then
            local saveData = {TargetSets = _G.ActiveTargetSets, WhitelistedSwords = _G.WhitelistedSwords, SpecialOverrides = _G.SpecialOverrides, WebhookURL = _G.WebhookURL, WebhookEnabled = _G.WebhookEnabled, FarmAreas = _G.FarmAreas, Settings = SETTINGS}
            writefile(SaveFileName, HttpService:JSONEncode(saveData))
        end
    end)
end

pcall(function()
    if isfile and isfile(SaveFileName) and readfile then
        local s2, parsedData = pcall(function() return HttpService:JSONDecode(readfile(SaveFileName)) end)
        if s2 and parsedData then
            _G.ActiveTargetSets = parsedData.TargetSets or _G.ActiveTargetSets
            _G.WhitelistedSwords = parsedData.WhitelistedSwords or _G.WhitelistedSwords
            _G.SpecialOverrides = parsedData.SpecialOverrides or _G.SpecialOverrides
            _G.WebhookURL = parsedData.WebhookURL or _G.WebhookURL
            _G.WebhookEnabled = parsedData.WebhookEnabled or _G.WebhookEnabled
            if parsedData.Settings then
                for k, v in pairs(parsedData.Settings) do SETTINGS[k] = v end
            end
        end
    end
end)

local currentArea = 0
local isTeleporting = false
local lastTeleportEnd = 0 
local isEscaping = false
local currentTarget = nil
local targetStartTime = 0
local idleStartTime = 0
local blacklistedNPCs = {}

local SETTINGS = {
    OFFSET_HEIGHT = 7, WAIT_ALTITUDE = 15, RETREAT_ALTITUDE = 15,
    HP_ATTRIBUTE_NAME = "HP", AREA_ATTRIBUTE_NAME = "Area", DANGER_RADIUS = 40, SAFE_COOLDOWN = 0.5,
    MAX_KILL_TIME = 5, BLACKLIST_DURATION = 30, IDLE_BEFORE_HOP = 3, SPAWN_GRACE_PERIOD = 5, 
    MIN_NPCS_TO_STAY = 0, -- Density Hopper Threshold
}

-- [[ 2. PHYSICS RESET ]]
local function ResetPhysics()
    if humanoid and humanoid.Parent then
        humanoid.PlatformStand = false 
        humanoid.AutoRotate = true
        humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
    end
    if hrp and hrp.Parent then
        hrp.AssemblyLinearVelocity = Vector3.zero
    end
end

-- [[ 3. MEMORY CLEANUP & RAYFIELD UN-STACKER ]]
if _G.C2_WS then 
    pcall(function() _G.C2_WS:Close() end) 
    _G.C2_WS = nil 
end
if _G.UltimateFarmConnection then _G.UltimateFarmConnection:Disconnect() end
if _G.StatsConnection then task.cancel(_G.StatsConnection) end
if _G.AntiAFKConnection then task.cancel(_G.AntiAFKConnection) end
if _G.InventorySweeperConnection then task.cancel(_G.InventorySweeperConnection) end
if _G.CharRespawnConnection then _G.CharRespawnConnection:Disconnect() end
  if _G.SwordAddedConnection then _G.SwordAddedConnection:Disconnect() end
  if _G.InvAddedConnection then _G.InvAddedConnection:Disconnect() end
  if _G.SellingAddedConnection then _G.SellingAddedConnection:Disconnect() end
if _G.GraphicsStripperConnection then _G.GraphicsStripperConnection:Disconnect() end
_G.UltimateFarmConnection = nil
isTeleporting = false
_G.fetchingGodRoll = false

if game.CoreGui:FindFirstChild("Rayfield") then
    game.CoreGui.Rayfield:Destroy()
end
ResetPhysics()

-- [[ 3.5. ANTI-AFK MECHANISM ]]
local VirtualInputManager = game:GetService("VirtualInputManager")
_G.AntiAFKConnection = task.spawn(function()
    while task.wait(20) do
        pcall(function()
            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
        end)
    end
end)

-- [[ 3.6. EXTREME RAM OPTIMIZATION ]]
task.spawn(function()
    pcall(function()
        settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
        UserSettings():GetService("UserGameSettings").MasterVolume = 0
        
        local Lighting = game:GetService("Lighting")
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 9e9
        Lighting.FogStart = 0
        for _, v in pairs(Lighting:GetDescendants()) do
            if v:IsA("PostEffect") or v:IsA("Atmosphere") or v:IsA("Sky") or v:IsA("ColorCorrectionEffect") or v:IsA("BloomEffect") or v:IsA("SunRaysEffect") or v:IsA("BlurEffect") or v:IsA("DepthOfFieldEffect") then
                v:Destroy()
            end
        end
        
        for _, v in pairs(workspace:GetDescendants()) do
            if v:IsA("Texture") or v:IsA("Decal") then
                v:Destroy()
            elseif v:IsA("BasePart") and not v.Parent:FindFirstChild("Humanoid") then
                v.Material = Enum.Material.Plastic
                v.Reflectance = 0
                v.CastShadow = false
            elseif v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Beam") then
                v.Enabled = false
            end
        end
        
        workspace.Terrain.WaterWaveSize = 0
        workspace.Terrain.WaterWaveSpeed = 0
        workspace.Terrain.WaterReflectance = 0
        workspace.Terrain.WaterTransparency = 0
        
        -- Connect to any new items to strip graphics immediately
        _G.GraphicsStripperConnection = workspace.DescendantAdded:Connect(function(v)
            if v:IsA("Texture") or v:IsA("Decal") then
                v:Destroy()
            elseif v:IsA("BasePart") and not v.Parent:FindFirstChild("Humanoid") then
                v.Material = Enum.Material.Plastic
                v.Reflectance = 0
                v.CastShadow = false
            elseif v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Beam") then
                v.Enabled = false
            end
        end)
    end)
end)

-- [[ 4. MODULES & REMOTES SETUP ]]
local Tables = ReplicatedStorage:WaitForChild("Tables")
local DropRemote = ReplicatedStorage:WaitForChild("Paper"):WaitForChild("Remotes"):WaitForChild("__remoteevent")

local SwordModules = {
    Enchant1 = require(Tables.Enchant), Enchant2 = require(Tables.Enchant), Enchant3 = require(Tables.Enchant),
    Mold = require(Tables.Mold), Quality = require(Tables.Quality), Rarity = require(Tables.Rarity), Class = require(Tables.Class),
    MobTrait = require(Tables.MobTrait)
}



-- [[ 5. ROBUST LEADERSTATS INITIALIZATION ]]
local sessionStartTime = tick()

-- [[ 6. SNIPER & AUTO-DROP LOGIC ]]
local function SendWebhook(title, description, color, fields)
    if not _G.WebhookEnabled or _G.WebhookURL == "" or _G.WebhookURL == "Paste URL Here" then return end
    local req = request or http_request or (syn and syn.request)
    if not req then return end
    local data = {["embeds"] = {{["title"] = title, ["description"] = description, ["color"] = color, ["fields"] = fields, ["timestamp"] = DateTime.now():ToIsoDate()}}}
    pcall(function() req({Url = _G.WebhookURL, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = HttpService:JSONEncode(data)}) end)
end

local function getActualStats(statType, statId)
    local m = SwordModules[statType]; 
    if m and m[statId] then return m[statId] end; 
    return nil
end 

local function getEnchants(instance)
    local env = {}
    for i = 1, 3 do
        local id = instance:GetAttribute("Enchant" .. i)
        if id then
            local d = getActualStats("Enchant" .. i, id)
            if d and d.Name then table.insert(env, d.Name) else table.insert(env, tostring(id)) end
        end
    end
    return env
end

local function getSwordDetails(instance)
    local mId, rId = instance:GetAttribute("Mold"), instance:GetAttribute("Rarity")
    local mData, rData = getActualStats("Mold", mId), getActualStats("Rarity", rId)
    local moldName = (mData and mData.Name) or (mId and tostring(mId)) or "Unknown"
    local rarityName = (rData and rData.Name) or (rId and tostring(rId)) or "Unknown"
    return {Enchants = getEnchants(instance), Mold = moldName, Rarity = rarityName}
end

local function hasMatchingCombo(swordEnchants)
    if #_G.ActiveTargetSets == 0 then return false end 
    for _, targetSet in ipairs(_G.ActiveTargetSets) do
        local tLeft = {}
        for _, enc in ipairs(targetSet) do table.insert(tLeft, enc) end
        for _, myEnc in ipairs(swordEnchants) do
            local idx = table.find(tLeft, myEnc)
            if idx then table.remove(tLeft, idx) end
        end
        if #tLeft == 0 then return true end
    end
    return false
end

local function matchesSpecial(instance)
    if _G.SpecialOverrides.Enchant and #_G.SpecialOverrides.Enchant > 0 then
        local enchants = getEnchants(instance)
        for _, sel in ipairs(_G.SpecialOverrides.Enchant) do
            if table.find(enchants, sel) then return true end
        end
    end
    local attrsToCheck = {"Mold", "Quality", "Rarity", "Class"}
    for _, attrName in ipairs(attrsToCheck) do
        if _G.SpecialOverrides[attrName] and #_G.SpecialOverrides[attrName] > 0 then
            local aId = instance:GetAttribute(attrName)
            if aId then
                local d = getActualStats(attrName, aId)
                if d and d.Name and table.find(_G.SpecialOverrides[attrName], d.Name) then return true end
                if table.find(_G.SpecialOverrides[attrName], tostring(aId)) then return true end
            end
        end
    end
    return false
end

local function dropBadSword(swordFolder)
    if not _G.autoDropEnabled then return end
    DropRemote:FireServer(unpack({[1] = "Drop Sword", [2] = swordFolder.Name}))
    task.wait(0.1) 
end

local function evaluateInventorySword(swordFolder)
    if not swordFolder:IsA("Folder") then return end
    task.wait(0.5)
    if not swordFolder or not swordFolder.Parent then return end
    
    local keep = false
    if table.find(_G.WhitelistedSwords, swordFolder.Name) then keep = true end
    if swordFolder:GetAttribute("Equipped") == true then keep = true end
    if character and character:FindFirstChild(swordFolder.Name) then keep = true end
    if _G.SavedSwordName and swordFolder.Name == _G.SavedSwordName then keep = true end
    if hasMatchingCombo(getEnchants(swordFolder)) or matchesSpecial(swordFolder) then keep = true end
    
    if keep then
        if not table.find(_G.KeptSwords, swordFolder.Name) then table.insert(_G.KeptSwords, swordFolder.Name) end
    else
        if _G.autoDropEnabled then dropBadSword(swordFolder) end
    end
end

local function DestroyCutscene()
   local mainGui = playerGui:FindFirstChild("Main")
    if mainGui then
        local cutscene = mainGui:FindFirstChild("CutScene") or mainGui:FindFirstChild("Cutscene")
        if cutscene then 
           cutscene:Destroy()
        end
    end
end

-- DYNAMIC YIELD TELEPORT (ALWAYS RETURN HOME FIRST)
local function TeleportSequence(areaNum)
    print("[DEBUG] --- TeleportSequence Initiated | Target Area:", tostring(areaNum), "---")
    _G.CurrentState = "Teleporting..."
    isTeleporting = true 
    ResetPhysics()
    
    local remote = ReplicatedStorage:WaitForChild("Paper"):WaitForChild("Remotes"):WaitForChild("__remotefunction")
    local internalArea = PlayerStats:FindFirstChild("CurrentArea")
    
    if hrp then hrp.AssemblyLinearVelocity = Vector3.zero end
    
    local currentVal = internalArea and tostring(internalArea.Value) or "0"
    print("[DEBUG] Current Area before teleport:", currentVal)

    -- [[ STEP 1: ALWAYS RETURN TO BASE FIRST ]]
    if currentVal ~= "0" and currentVal ~= "Base" and currentVal ~= "Spawn" then
        print("[DEBUG] Returning to Base first...")
        pcall(function() remote:InvokeServer("Teleport In Base", "Return") end)
        
        local waitBase = tick()
        while internalArea and tostring(internalArea.Value) ~= "0" and tick() - waitBase < 5 do
            if not _G.on and not _G.fetchingGodRoll then isTeleporting = false; return end
            if hrp then hrp.AssemblyLinearVelocity = Vector3.zero end
            task.wait(0.1)
        end
        if not _G.on and not _G.fetchingGodRoll then isTeleporting = false; return end
        print("[DEBUG] Arrived in Base.")
        task.wait(1)
    else
        print("[DEBUG] Already in Base.")
        if tostring(areaNum) == "0" then
            pcall(function() remote:InvokeServer("Teleport In Base", "Home") end)
        end
    end
    
    if not _G.on and not _G.fetchingGodRoll then isTeleporting = false; return end
    DestroyCutscene() 
    
    -- [[ STEP 2: TELEPORT TO TARGET MAP ]]
    if tostring(areaNum) ~= "0" and tostring(areaNum) ~= "Base" and tostring(areaNum) ~= "Spawn" then
        print("[DEBUG] Teleporting from Base to Area:", areaNum)
        pcall(function() remote:InvokeServer("Teleport Area", tonumber(areaNum)) end)
        
        local waitArea = tick()
        while internalArea and tostring(internalArea.Value) ~= tostring(areaNum) and tick() - waitArea < 7 do
            if not _G.on and not _G.fetchingGodRoll then isTeleporting = false; return end
            if hrp then hrp.AssemblyLinearVelocity = Vector3.zero end
            task.wait(0.1)
        end
        if not _G.on and not _G.fetchingGodRoll then isTeleporting = false; return end
        print("[DEBUG] Arrived in Target Area:", areaNum)
        task.wait(2.5) 
    end
    
    currentArea = tonumber(areaNum) or currentArea
    lastTeleportEnd = tick() 
    idleStartTime = 0 
    isTeleporting = false
    print("[DEBUG] --- TeleportSequence Completed ---")
end

local function TeleportToGodRoll(swordModel, isSpecialMatch)
    if _G.fetchingGodRoll then return end 
    _G.fetchingGodRoll = true
    _G.CurrentState = "Sniping Target Item!"
    
    local details = getSwordDetails(swordModel)
    local isAtSpawn = swordModel:GetAttribute("canSelect") or swordModel:GetAttribute("BankSlot")
    
    local internalArea = PlayerStats:FindFirstChild("CurrentArea")
    local actualArea = internalArea and internalArea.Value or currentArea
    local areaToReturnTo = actualArea 
    
    local root = character:WaitForChild("HumanoidRootPart")
    local originalCFrame = root.CFrame -- Save original position
    
    ResetPhysics()
    if isAtSpawn and actualArea ~= 0 then TeleportSequence(0) end
    
    local godRollName = swordModel.Name 
    local snipeTimer = tick() 
    
    while swordModel and swordModel.Parent == workspace.Swords and tick() - snipeTimer < 10 do
        if not character or not character.Parent or humanoid.Health <= 0 then break end
        pcall(function() root.CFrame = swordModel:GetPivot() end)
        task.wait(0.1)
    end
    
    local title = isSpecialMatch and "🌟 Special Override Found!" or "🎯 God Roll Secured!"
    local color = isSpecialMatch and 16766720 or 5763719 
    local encString = #details.Enchants > 0 and table.concat(details.Enchants, ", ") or "None"
    
    SendWebhook(title, "A targeted weapon has been successfully looted.", color, {
        {["name"] = "Rarity", ["value"] = details.Rarity, ["inline"] = true},
        {["name"] = "Mold", ["value"] = details.Mold, ["inline"] = true},
        {["name"] = "Enchants", ["value"] = encString, ["inline"] = false}
    })

    local currentInternalArea = PlayerStats:FindFirstChild("CurrentArea")
    local nowArea = currentInternalArea and currentInternalArea.Value or currentArea
    
    if _G.on and tostring(nowArea) ~= tostring(areaToReturnTo) then
        TeleportSequence(areaToReturnTo)
    else
        task.wait(0.5)
        pcall(function() root.CFrame = originalCFrame end)
    end
    
    _G.fetchingGodRoll = false
end

local function isSwordLockedInAnyMachine(uuid)
    local allStats = ReplicatedStorage:FindFirstChild("Stats")
    if not allStats then return false end
    local machineFolders = {"Ascender", "Sell", "Plot", "Bank", "Auction"}
    
    for _, pStat in pairs(allStats:GetChildren()) do
        for _, folderName in ipairs(machineFolders) do
            local f = pStat:FindFirstChild(folderName)
            if f and f:FindFirstChild(uuid) then return true end
        end
    end
    return false
end

local function evaluateWorkspaceSword(swordModel)
    if not _G.autoDropEnabled then return end
    
    if not (swordModel:IsA("Model") or swordModel:IsA("Tool") or swordModel:IsA("BasePart")) then return end
    
    task.wait(0.5) 
    if not swordModel or not swordModel.Parent then return end 
    if swordModel:GetAttribute("BankSlot") or swordModel:GetAttribute("canSelect") then return end
    if table.find(_G.KeptSwords, swordModel.Name) then return end
    
    if isSwordLockedInAnyMachine(swordModel.Name) then return end
    
    if hrp then
        local swordPos = swordModel:GetPivot().Position
        local dist = (hrp.Position - swordPos).Magnitude
        if dist > 1000 then
            return 
        end
    end
    
    local isGodRoll = hasMatchingCombo(getEnchants(swordModel))
    local isSpecial = matchesSpecial(swordModel)

    if isGodRoll or isSpecial then
        task.spawn(function() TeleportToGodRoll(swordModel, isSpecial) end)
    end
end

-- [[ 7. TARGETING ]]
local GetBestTarget = LPH_NO_VIRTUALIZE(function()
    local bestTarget, bestScore, shortestDist = nil, -math.huge, math.huge
    local now = tick()
    local validNpcCount = 0 
    
    local actualArea = currentArea
    local pStats = ReplicatedStorage:FindFirstChild("Stats")
    if pStats then
        local myStats = pStats:FindFirstChild(tostring(player.Name))
        local internalArea = myStats and myStats:FindFirstChild("CurrentArea")
        if internalArea then actualArea = internalArea.Value end
    end
    local actualAreaStr = tostring(actualArea)
    
    for _, v in pairs(workspace.NPCs:GetChildren()) do
        if blacklistedNPCs[v] and now - blacklistedNPCs[v] > SETTINGS.BLACKLIST_DURATION then blacklistedNPCs[v] = nil end
        
        local npcAreaVal = v:GetAttribute(SETTINGS.AREA_ATTRIBUTE_NAME)
        if tostring(npcAreaVal) == actualAreaStr then
            local npcRoot = v:FindFirstChild("HumanoidRootPart")
            local hp = v:GetAttribute(SETTINGS.HP_ATTRIBUTE_NAME)
            
            if npcRoot and hp and hp > 0 and not blacklistedNPCs[v] then
                validNpcCount = validNpcCount + 1
                local dist = (hrp.Position - npcRoot.Position).Magnitude
                
                if _G.TargetPriority == "Closest" then
                    if dist < shortestDist then 
                        bestTarget = v
                        shortestDist = dist 
                    end
                else
                    -- Score-based priority calculation
                    local baseScore = 1
                    local rarityId = v:GetAttribute("Rarity")
                    if rarityId and SwordModules.Rarity[rarityId] and SwordModules.Rarity[rarityId].ValueMulti then
                        baseScore = SwordModules.Rarity[rarityId].ValueMulti
                    end
                    
                    local score = baseScore
                    local attributes = v:GetAttributes()
                    for attrName, attrValue in pairs(attributes) do
                        if string.find(attrName, "MobTrait") then
                            local traitData = SwordModules.MobTrait[attrValue]
                            if traitData and traitData.Boosts then
                                if _G.TargetPriority == "Highest XP" and traitData.Boosts.XP then
                                    score = score * traitData.Boosts.XP
                                elseif _G.TargetPriority == "Highest Money" and traitData.Boosts.Money then
                                    score = score * traitData.Boosts.Money
                                end
                            end
                        end
                    end
                    
                    if score > bestScore then
                        bestScore = score
                        bestTarget = v
                        shortestDist = dist
                    elseif score == bestScore then
                        -- Tie-breaker: pick the closest one
                        if dist < shortestDist then
                            bestTarget = v
                            shortestDist = dist
                        end
                    end
                end
            end
        end
    end
    
    if validNpcCount < SETTINGS.MIN_NPCS_TO_STAY then return nil end
    return bestTarget
end)

-- UI REMOVED: Managed Entirely via C2 Dashboard

_G.InventorySweeperConnection = task.spawn(function()
    while task.wait(5) do
        if _G.on and _G.autoDropEnabled then
            pcall(function()
                local pStats = ReplicatedStorage:FindFirstChild("Stats")
                if pStats then
                    local myStats = pStats:FindFirstChild(tostring(player.Name))
                    local invFolder = myStats and myStats:FindFirstChild("Swords")
                    if invFolder then
                        for _, swordFolder in pairs(invFolder:GetChildren()) do
                            local keep = false
                            if table.find(_G.WhitelistedSwords, swordFolder.Name) then keep = true end
                            if swordFolder:GetAttribute("Equipped") == true then keep = true end
                            if character and character:FindFirstChild(swordFolder.Name) then keep = true end
                            if _G.SavedSwordName and swordFolder.Name == _G.SavedSwordName then keep = true end
                            if hasMatchingCombo(getEnchants(swordFolder)) or matchesSpecial(swordFolder) then keep = true end
                            
                            if keep then 
                                if not table.find(_G.KeptSwords, swordFolder.Name) then
                                    table.insert(_G.KeptSwords, swordFolder.Name)
                                end
                            elseif _G.autoDropEnabled then 
                                dropBadSword(swordFolder) 
                            end
                        end
                    end
                end
            end)
        end
    end
end)

local function evaluateSellingSword(swordFolder)
    if not _G.autoDropEnabled then return end
    if not swordFolder:IsA("Folder") then return end
    task.wait(0.2) 
    if not swordFolder or not swordFolder.Parent then return end
    
    local keep = false
    if hasMatchingCombo(getEnchants(swordFolder)) or matchesSpecial(swordFolder) then keep = true end
    
    if keep then
        print("C2 Sniper: God Roll found in Selling queue!", swordFolder.Name)
        _G.fetchingGodRoll = true
        _G.CurrentState = "Sniping God Roll from Sell Plot!"
        
        local pStats = ReplicatedStorage:FindFirstChild("Stats")
        local myStats = pStats and pStats:FindFirstChild(tostring(player.Name))
        local internalArea = myStats and myStats:FindFirstChild("CurrentArea")
        local actualArea = internalArea and internalArea.Value or currentArea
        local areaToReturnTo = actualArea 
        local originalCFrame = hrp.CFrame

        if tostring(actualArea) ~= "0" then
            TeleportSequence(0)
        end
        
        local physicalSword = nil
        local waitStart = tick()
        while not physicalSword and tick() - waitStart < 5 do
            physicalSword = workspace:FindFirstChild(swordFolder.Name, true)
            if not physicalSword then task.wait(0.1) end
        end
        
        if physicalSword then
            local touchStart = tick()
            -- Actively track and try to touch the weapon for 2 seconds
            while physicalSword and physicalSword.Parent and tick() - touchStart < 2 do
                local targetCFrame = physicalSword:IsA("Model") and physicalSword:GetPivot() or physicalSword.CFrame
                if targetCFrame then
                    local offset = CFrame.new(math.sin(tick() * 15) * 2, 0, math.cos(tick() * 15) * 2)
                    pcall(function() hrp.CFrame = targetCFrame * offset end)
                    
                    pcall(function()
                        if firetouchinterest then
                            local partToTouch = physicalSword:IsA("BasePart") and physicalSword or physicalSword:FindFirstChildWhichIsA("BasePart", true)
                            local limb = character:FindFirstChild("Left Leg") or character:FindFirstChild("LeftFoot") or hrp
                            if partToTouch and limb then
                                firetouchinterest(limb, partToTouch, 0)
                                firetouchinterest(limb, partToTouch, 1)
                            end
                        end
                    end)
                end
                task.wait(0.1)
            end
        else
            warn("Could not find physical sword in workspace for Selling item:", swordFolder.Name)
        end
        
        task.wait(0.5)
        
        if _G.on and tostring(actualArea) ~= "0" then
            TeleportSequence(areaToReturnTo)
        else
            task.wait(0.5)
            pcall(function() hrp.CFrame = originalCFrame end)
        end
        
        _G.fetchingGodRoll = false
    end
end

task.spawn(function()
    local pStats = ReplicatedStorage:WaitForChild("Stats"):WaitForChild(tostring(player.Name))
    local invFolder = pStats:WaitForChild("Swords")
    _G.InvAddedConnection = invFolder.ChildAdded:Connect(evaluateInventorySword)
    
    local sellingFolder = pStats:WaitForChild("Selling", 10)
    if sellingFolder then
        _G.SellingAddedConnection = sellingFolder.DescendantAdded:Connect(evaluateSellingSword)
    end
end)

_G.SwordAddedConnection = workspace.Swords.ChildAdded:Connect(evaluateWorkspaceSword)

-- [[ 10. DEATH & RESPAWN HANDLING ]]
_G.CharRespawnConnection = player.CharacterAdded:Connect(function(newCharacter)
    character = newCharacter
    hrp = character:WaitForChild("HumanoidRootPart")
    humanoid = character:WaitForChild("Humanoid")
    playerGui = player:WaitForChild("PlayerGui")
    
    if _G.on then
        warn("💀 Respawn detected! Hopping zones to unlock interactions...")
        if not isTeleporting then
            isTeleporting = true
            local targetArea = (#_G.FarmAreas > 0 and _G.FarmAreas[1]) or currentArea
            task.spawn(function() TeleportSequence(targetArea) end)
        end
    end
end)

local lastEquipAttempt = 0
local function EquipWeaponRemote(uuid)
    if tick() - lastEquipAttempt < 0.5 then return end
    lastEquipAttempt = tick()
    
    pcall(function()
        local remote = ReplicatedStorage:FindFirstChild("Paper") and ReplicatedStorage.Paper:FindFirstChild("Remotes") and ReplicatedStorage.Paper.Remotes:FindFirstChild("__remoteevent")
        if remote then
            remote:FireServer("Equip Sword", uuid)
        end
    end)
end

-- [[ 11. STATE MACHINE & MAIN LOOP ]]
local BotState = "Disabled"
local StateData = {
    SignalWaitStart = nil,
    EquipAttemptStart = nil,
    IdleStartTime = 0,
    TargetStartTime = 0,
    LastTarget = nil,
    MissingSwords = {}
}

-- 🎯 Target Updater Loop (Runs 5 times a second instead of 60 to save CPU)
task.spawn(function()
    while task.wait(0.2) do
        if not _G.on or BotState == "Dead" or BotState == "Disabled" then continue end
        -- Only search for targets if we are actively trying to fight
        if BotState == "Farming" or BotState == "Idle" then
            currentTarget = GetBestTarget()
        end
    end
end)

local function CheckMissingSwords()
    local missing = {}
    if workspace:FindFirstChild("Swords") then
        if _G.SavedSwordName and not isSwordLockedInAnyMachine(_G.SavedSwordName) then
            local mainDropped = workspace.Swords:FindFirstChild(_G.SavedSwordName)
            if mainDropped and not mainDropped:GetAttribute("canSelect") and not mainDropped:GetAttribute("BankSlot") then 
                table.insert(missing, mainDropped) 
            end
        end
        for _, uuid in ipairs(_G.KeptSwords) do
            if uuid ~= _G.SavedSwordName and not isSwordLockedInAnyMachine(uuid) then
                local dropped = workspace.Swords:FindFirstChild(uuid)
                if dropped and not dropped:GetAttribute("canSelect") and not dropped:GetAttribute("BankSlot") then 
                    table.insert(missing, dropped) 
                end
            end
        end
    end
    return missing
end

-- 🧠 FSM Brain: Determines absolute priority
local DetermineState = LPH_NO_VIRTUALIZE(function()
    if not _G.on then return "Disabled" end
    if not character or not character.Parent or not humanoid or humanoid.Health <= 0 then return "Dead" end
    if _G.fetchingGodRoll then return "Sniping" end
    if isTeleporting then return "Teleporting" end

    -- Priority 1: Check Area Sync Signal
    local actualArea = currentArea
    local pStats = ReplicatedStorage:FindFirstChild("Stats")
    if pStats then
        local myStats = pStats:FindFirstChild(tostring(player.Name))
        local internalArea = myStats and myStats:FindFirstChild("CurrentArea")
        if internalArea then actualArea = internalArea.Value end
    end
    
    local actualNum, wantedNum = tonumber(actualArea), tonumber(currentArea)
    if (not wantedNum or wantedNum == 0) and #_G.FarmAreas > 0 then 
        wantedNum = _G.FarmAreas[1]
        currentArea = wantedNum
    elseif (not wantedNum or wantedNum == 0) then 
        wantedNum = 0; currentArea = 0 
    end

    if actualNum ~= wantedNum then 
        isTeleporting = true
        task.spawn(function() TeleportSequence(wantedNum) end)
        return "Teleporting"
    end

    -- Priority 2: Mass Recovery Check
    StateData.MissingSwords = CheckMissingSwords()
    if #StateData.MissingSwords > 0 then return "Recovering" end

    -- Priority 3: Smart Equip Check
    local currentTool = character:FindFirstChildOfClass("Tool")
    local bestSwordToEquip = nil
    
    -- 1. Check for whitelisted sword in inventory
    if PlayerStats and PlayerStats:FindFirstChild("Swords") then
        for _, sword in pairs(PlayerStats.Swords:GetChildren()) do
            if sword:IsA("Folder") and table.find(_G.WhitelistedSwords, sword.Name) and not isSwordLockedInAnyMachine(sword.Name) then
                bestSwordToEquip = sword.Name
                break
            end
        end
    end
    
    -- 2. If no whitelisted sword found, check if we are currently holding a valid sword manually
    if not bestSwordToEquip and currentTool and string.len(currentTool.Name) > 15 then
        bestSwordToEquip = currentTool.Name
    end
    
    -- 3. Execute Smart Equip Logic
    if bestSwordToEquip then
        if not currentTool or currentTool.Name ~= bestSwordToEquip then
            _G.SavedSwordName = bestSwordToEquip
            return "Equipping"
        else
            _G.SavedSwordName = bestSwordToEquip
            if not table.find(_G.KeptSwords, bestSwordToEquip) then table.insert(_G.KeptSwords, bestSwordToEquip) end
        end
    else
        -- NO sword found at all! Stop farming and notify.
        if _G.on then
            _G.on = false
            _G.CurrentState = "No Valid Sword!"
            warn("[DEBUG] Smart Equip Failed! No valid sword found. Halting bot.")
            pcall(function()
                if _G.C2_WS then
                    _G.C2_WS:Send(game:GetService("HttpService"):JSONEncode({
                        type = "notification",
                        message = "⚠️ Account " .. player.Name .. " stopped farming: No whitelisted/equipped sword found."
                    }))
                end
            end)
        end
        return "Idle"
    end

    -- Priority 4 was Archer Evasion (Removed per user request)

    -- Priority 5: Combat
    if currentTarget then return "Farming" end

    -- Priority 6: Nothing left to do
    return "Idle"
end)

-- ⚙️ Executor Loop
_G.UltimateFarmConnection = RunService.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function()
    -- Ask the Brain what we should be doing right now
    local newState, extraData = DetermineState()
    BotState = newState

    -- Handle lockouts and physical resets
    if BotState == "Disabled" then _G.CurrentState = "Idle"; return end
    if BotState == "Dead" then _G.CurrentState = "Dead/Respawning..."; return end
    if BotState == "Sniping" or BotState == "Teleporting" then return end

    -- Global Physics enforcement
    humanoid:ChangeState(Enum.HumanoidStateType.Physics)
    humanoid.PlatformStand = true 
    humanoid.AutoRotate = false
    hrp.AssemblyLinearVelocity = Vector3.zero

    -- Execute State Actions
    if BotState == "Recovering" then
        StateData.SignalWaitStart = nil -- Reset other timers
        _G.CurrentState = "Mass Recovery! (" .. #StateData.MissingSwords .. " items left)"
        
        local droppedSword = StateData.MissingSwords[1]
        local targetCFrame
        if droppedSword:IsA("Model") then targetCFrame = droppedSword:GetPivot()
        elseif droppedSword:IsA("Tool") then
            local h = droppedSword:FindFirstChild("Handle") or droppedSword:FindFirstChildWhichIsA("BasePart")
            if h then targetCFrame = h.CFrame end
        elseif droppedSword:IsA("BasePart") then targetCFrame = droppedSword.CFrame end
        
        if targetCFrame then 
            local t = tick()
            local targetPos = targetCFrame.Position
            local offsetPos
            
            -- Alternate between spiraling and back-and-forth sweeping every 1 second
            if (t % 2) < 1 then
                offsetPos = Vector3.new(math.sin(t * 15) * 2, 0, math.cos(t * 15) * 2)
            else
                local sweep = math.sin(t * 15) * 3
                offsetPos = Vector3.new(sweep, 0, sweep)
            end
            
            -- Use CFrame.new(Position) to prevent inheriting the sword's rotation
            hrp.CFrame = CFrame.new(targetPos + offsetPos)
            
            pcall(function()
                if firetouchinterest then
                    local partToTouch = droppedSword:IsA("BasePart") and droppedSword or droppedSword:FindFirstChildWhichIsA("BasePart", true)
                    local limb = character:FindFirstChild("Left Leg") or character:FindFirstChild("LeftFoot") or character:FindFirstChild("HumanoidRootPart")
                    if partToTouch and limb then
                        firetouchinterest(limb, partToTouch, 0)
                        firetouchinterest(limb, partToTouch, 1)
                    end
                end
            end)
        end

    elseif BotState == "Equipping" then
        _G.CurrentState = "Equipping Main Weapon..."
        if not StateData.EquipAttemptStart then StateData.EquipAttemptStart = tick() end
        if tick() - StateData.EquipAttemptStart > 5 then
            warn("[DEBUG] Failed to equip sword after 5s! Retrying without dropping protection.")
            StateData.EquipAttemptStart = nil
            return
        end
        EquipWeaponRemote(_G.SavedSwordName)
        hrp.CFrame = CFrame.new(hrp.Position.X, SETTINGS.WAIT_ALTITUDE, hrp.Position.Z)

    elseif BotState == "Evading" then
        StateData.EquipAttemptStart = nil
        _G.CurrentState = "Evading Archers!"
        hrp.CFrame = CFrame.new(hrp.Position.X, SETTINGS.RETREAT_ALTITUDE, hrp.Position.Z)

    elseif BotState == "Farming" then
        StateData.EquipAttemptStart = nil
        _G.CurrentState = "Farming: " .. currentTarget.Name
        StateData.IdleStartTime = 0 
        
        if not StateData.LastTarget or StateData.LastTarget ~= currentTarget then
            StateData.LastTarget = currentTarget
            StateData.TargetStartTime = tick()
        end

        if tick() - StateData.TargetStartTime > SETTINGS.MAX_KILL_TIME then
            warn("⌛ Stuck Detection! " .. currentTarget.Name .. " blacklisted.")
            blacklistedNPCs[currentTarget] = tick()
            currentTarget = nil
            return
        end

        if currentTarget:FindFirstChild("HumanoidRootPart") then
            hrp.CFrame = CFrame.lookAt(currentTarget.HumanoidRootPart.Position + Vector3.new(0, SETTINGS.OFFSET_HEIGHT, 0), currentTarget.HumanoidRootPart.Position)
            local currentTool = character:FindFirstChildOfClass("Tool")
            if currentTool then currentTool:Activate() end
        end

    elseif BotState == "Idle" then
        StateData.EquipAttemptStart = nil
        local now = tick()
        
        if now - lastTeleportEnd < SETTINGS.SPAWN_GRACE_PERIOD then
            _G.CurrentState = "Waiting for Spawns..."
            StateData.IdleStartTime = 0 
        elseif StateData.IdleStartTime == 0 then 
            StateData.IdleStartTime = now
        elseif now - StateData.IdleStartTime > SETTINGS.IDLE_BEFORE_HOP then
            _G.CurrentState = "Hopping Areas..."
            
            local actualArea = tonumber(currentArea)
            local pStats = ReplicatedStorage:FindFirstChild("Stats")
            if pStats then
                local myStats = pStats:FindFirstChild(tostring(player.Name))
                local internalArea = myStats and myStats:FindFirstChild("CurrentArea")
                if internalArea then actualArea = tonumber(internalArea.Value) end
            end

            local nextArea = actualArea
            if #_G.FarmAreas > 0 then
                local currentIndex = table.find(_G.FarmAreas, actualArea)
                if currentIndex then
                    local nextIndex = currentIndex + 1
                    if nextIndex > #_G.FarmAreas then nextIndex = 1 end
                    nextArea = _G.FarmAreas[nextIndex]
                else 
                    nextArea = _G.FarmAreas[1] 
                end
            end
            
            StateData.IdleStartTime = 0
            isTeleporting = true 
            task.spawn(function() TeleportSequence(nextArea) end)
            return 
        end
        
        _G.CurrentState = "Area Clear / Hovering..."
        hrp.CFrame = CFrame.new(hrp.Position.X, SETTINGS.WAIT_ALTITUDE, hrp.Position.Z)
    end
end))

-- [[ 12. C2 WEB PANEL INTEGRATION ]]
task.spawn(function()
    local render3dActive = false
    pcall(function() 
        RunService:Set3dRenderingEnabled(false) 
        setfpscap(3)
    end)

    local AscenderRemote = ReplicatedStorage:WaitForChild("Paper", 9e9):WaitForChild("Remotes", 9e9):WaitForChild("__remoteevent", 9e9)
    local Tables = ReplicatedStorage:WaitForChild("Tables")
    local populateData = {}
    local RequiredModules = {"Mold", "Rarity", "Enchant", "Class", "Quality"}

    pcall(function()
        for _, moduleName in ipairs(RequiredModules) do 
            local moduleScript = Tables:FindFirstChild(moduleName)
            if moduleScript then populateData[moduleName] = require(moduleScript) end
        end
    end)

    local isC2Kicked = false
    local function maintainC2Connection()
        while not isC2Kicked do
            if not _G.C2_WS then
                local success, ws = pcall(function()
                    local wsFunc = (syn and syn.websocket and syn.websocket.connect) or WebSocket.connect
                    if wsFunc then
                        local url = _G.C2_SERVER_URL or "wss://c2scripts.xyz/ws/c2/"
                        return wsFunc(url)
                    end
                    error("Executor does not support WebSockets!")
                end)

                if success and ws then
                    print("🔌 Connected to Snowflake C2 Panel!")
                    _G.C2_WS = ws
                    
                    if _G.SetupC2Events then
                        task.spawn(function() _G.SetupC2Events(ws) end)
                    end
                    
                    pcall(function()
                        if ws.OnClose then
                            ws.OnClose:Connect(function()
                                print("⚠️ C2 Connection Lost! Reconnecting in 10s...")
                                _G.C2_WS = nil
                            end)
                        end
                    end)
                else
                    warn("⚠️ WebSocket C2 Server unreachable. Retrying in 10s...")
                end
            end
            
            task.wait(10)
        end
    end

    local function getName(category, id)
        if id == nil then return "None" end
        local moduleCat = category
        if string.find(category, "Enchant") then moduleCat = "Enchant1" end
        
        local categoryData = SwordModules[moduleCat]
        if not categoryData then return tostring(id) end
        return categoryData[id] and categoryData[id].Name or tostring(id)
    end

    local function getAscenderPayload()
        local payload = { hasSword = false, mode = "None", stats = {} }
        pcall(function()
            local stats = {}
            pcall(function()
                local ascenderStats = AscenderRemote:InvokeServer("GetStats")
                if ascenderStats then
                    stats.Level = ascenderStats.Level or 1
                    stats.Class = getName("Class", ascenderStats.Class)
                    stats.Quality = getName("Quality", ascenderStats.Quality)
                    stats.Rarity = getName("Rarity", ascenderStats.Rarity)
                    stats.Mold = getName("Mold", ascenderStats.Mold)
                end
            end)
            
            local ascenderModeObj = PlayerStats:FindFirstChild("AscenderMode")
            if ascenderModeObj then payload.mode = ascenderModeObj.Value end
            
            local ascenderBase = PlayerStats:FindFirstChild("Ascender")
            local getSword = ascenderBase and ascenderBase:FindFirstChildOfClass("Folder")
            
            if getSword then
                payload.hasSword = true
                payload.stats = {
                    Level = getSword:GetAttribute("Level") or 0,
                    Quality = getName("Quality", getSword:GetAttribute("Quality")),
                    Rarity = getName("Rarity", getSword:GetAttribute("Rarity")),
                    Mold = getName("Mold", getSword:GetAttribute("Mold")),
                    Class = getName("Class", getSword:GetAttribute("Class")),
                    Enchant1 = getName("Enchant", getSword:GetAttribute("Enchant1")) .. " (Lvl " .. tostring(getSword:GetAttribute("Enchant1Level") or 0) .. ")",
                    Enchant2 = getName("Enchant", getSword:GetAttribute("Enchant2")) .. " (Lvl " .. tostring(getSword:GetAttribute("Enchant2Level") or 0) .. ")",
                    Enchant3 = getName("Enchant", getSword:GetAttribute("Enchant3")) .. " (Lvl " .. tostring(getSword:GetAttribute("Enchant3Level") or 0) .. ")"
                }
            end
        end)
        return payload
    end

    local function getBackpackPayload()
        local payload = {}
        pcall(function()
            local invFolder = PlayerStats:FindFirstChild("Swords")
            if invFolder then
                for _, sword in pairs(invFolder:GetChildren()) do
                    if sword:IsA("Folder") then
                        local entry = { id = sword.Name }
                        if sword:GetAttribute("Equipped") then entry.Equipped = true end
                        entry.Level = sword:GetAttribute("Level") or 0
                        
                        local q = sword:GetAttribute("Quality")
                        if q and q > 0 then entry.Quality = getName("Quality", q) end
                        
                        entry.Rarity = getName("Rarity", sword:GetAttribute("Rarity"))
                        
                        local m = sword:GetAttribute("Mold")
                        if m and m > 0 then entry.Mold = getName("Mold", m) end
                        
                        local c = sword:GetAttribute("Class")
                        if c and c > 0 then entry.Class = getName("Class", c) end
                        
                        entry.Enchant1 = getName("Enchant", sword:GetAttribute("Enchant1"))
                        entry.Enchant2 = getName("Enchant", sword:GetAttribute("Enchant2"))
                        entry.Enchant3 = getName("Enchant", sword:GetAttribute("Enchant3"))
                        
                        table.insert(payload, entry)
                    end
                end
            end
        end)
        return payload
    end

    _G.SetupC2Events = function(ws)
        -- 1. Register this specific client
    pcall(function()
        ws:Send(HttpService:JSONEncode({
            action = "register",
            username = player.Name,
            api_key = C2_API_KEY,
            license_key = LUARMOR_LICENSE
        }))
    end)

    -- 2. Listen for incoming commands safely
    pcall(function()
        ws.OnMessage:Connect(function(msg)
            local s, data = pcall(function() return HttpService:JSONDecode(msg) end)
            if not s then return end

            if data.command == "toggleFarm" then
                _G.on = not _G.on
                print("C2 Command: AutoFarm toggled to", _G.on)
                
                if _G.on then
                   if #_G.FarmAreas > 0 then
                       local actualArea = currentArea
                       local pStats = ReplicatedStorage:FindFirstChild("Stats")
                       if pStats then
                           local myStats = pStats:FindFirstChild(tostring(player.Name))
                           local internalArea = myStats and myStats:FindFirstChild("CurrentArea")
                           if internalArea then actualArea = internalArea.Value end
                       end
                       if not table.find(_G.FarmAreas, actualArea) and not isTeleporting then
                           isTeleporting = true
                           task.spawn(function() TeleportSequence(_G.FarmAreas[1]) end)
                       end
                   end
                else
                   ResetPhysics() 
                end

            elseif data.command == "teleportHome" then
                print("C2 Command: Teleporting Home/Return!")
                task.spawn(function()
                    pcall(function() hrp.CFrame = CFrame.new(hrp.Position.X, hrp.Position.Y + 500, hrp.Position.Z) end)
                    task.wait(0.5)
                    local targetStr = "Return"
                    local pStats = ReplicatedStorage:FindFirstChild("Stats")
                    if pStats then
                        local myStats = pStats:FindFirstChild(tostring(player.Name))
                        if myStats and myStats:FindFirstChild("CurrentArea") then
                            if tostring(myStats.CurrentArea.Value) == "0" then
                                targetStr = "Home"
                            end
                        end
                    end
                    local args = { [1] = "Teleport In Base", [2] = targetStr }
                    pcall(function()
                        game:GetService("ReplicatedStorage"):WaitForChild("Paper", 9e9):WaitForChild("Remotes", 9e9):WaitForChild("__remotefunction", 9e9):InvokeServer(unpack(args))
                    end)
                end)

            elseif data.command == "activateAccount" then
                local isActive = data.payload
                render3dActive = isActive
                pcall(function() 
                    RunService:Set3dRenderingEnabled(render3dActive) 
                    setfpscap(isActive and 60 or 3)
                end)
                print("C2 Command: Account Activation toggled to", isActive)
                
            elseif data.command == "setFPS" then
                local fps = tonumber(data.payload) or 60
                pcall(function() setfpscap(fps) end)
                print("C2 Command: FPS Cap set to", fps)
                
            elseif data.command == "toggle3d" or data.command == "toggle3D" then
                render3dActive = not render3dActive
                pcall(function() RunService:Set3dRenderingEnabled(render3dActive) end)
                print("C2 Command: 3D Render forcefully toggled to", render3dActive)

            elseif data.command == "set3d" or data.command == "set3D" then
                if type(data.payload) == "boolean" then
                    render3dActive = data.payload
                elseif data.payload == "true" or data.payload == true then
                    render3dActive = true
                else
                    render3dActive = false
                end
                pcall(function() RunService:Set3dRenderingEnabled(render3dActive) end)
                print("C2 Command: 3D Render forcefully set to", render3dActive)

            elseif data.command == "dropSword" then
                local swordUUID = data.payload
                if swordUUID then
                    DropRemote:FireServer("Drop Sword", swordUUID)
                    print("C2 Command: Dropping sword manually ->", swordUUID)
                end
                
            elseif data.command == "toggleSnipe" then
                _G.autoDropEnabled = not _G.autoDropEnabled
                print("C2 Command: Sniper/AutoDrop toggled to", _G.autoDropEnabled)
                if _G.autoDropEnabled then
                    pcall(function()
                        local pStats = ReplicatedStorage:FindFirstChild("Stats"):FindFirstChild(tostring(player.Name))
                        for _, f in pairs(pStats:FindFirstChild("Swords"):GetChildren()) do evaluateInventorySword(f) end 
                    end)
                end
                
            elseif data.command == "setSnipe" then
                _G.autoDropEnabled = data.payload
                print("C2 Command: Sniper forcefully set to", _G.autoDropEnabled)
                if _G.autoDropEnabled then
                    pcall(function()
                        local pStats = ReplicatedStorage:FindFirstChild("Stats"):FindFirstChild(tostring(player.Name))
                        for _, f in pairs(pStats:FindFirstChild("Swords"):GetChildren()) do evaluateInventorySword(f) end 
                    end)
                end
                
            elseif data.command == "saveConfig" then
                pcall(function()
                    if writefile then
                        local saveData = {TargetSets = _G.ActiveTargetSets, WhitelistedSwords = _G.WhitelistedSwords, SpecialOverrides = _G.SpecialOverrides, WebhookURL = _G.WebhookURL, WebhookEnabled = _G.WebhookEnabled, FarmAreas = _G.FarmAreas, Settings = SETTINGS}
                        writefile(SaveFileName, HttpService:JSONEncode(saveData))
                        print("C2 Command: Configuration Saved locally to " .. SaveFileName)
                    end
                end)

            elseif data.command == "loadConfig" then
                pcall(function()
                    if isfile and isfile(SaveFileName) and readfile then
                        local s2, parsedData = pcall(function() return HttpService:JSONDecode(readfile(SaveFileName)) end)
                        if s2 and parsedData then
                            _G.ActiveTargetSets = parsedData.TargetSets or { {"Ancient", "Fortune", "Insight"} }
                            _G.WhitelistedSwords = parsedData.WhitelistedSwords or {}
                            _G.SpecialOverrides = parsedData.SpecialOverrides or {Enchant={}, Mold={}, Quality={}, Rarity={}, Class={}}
                            _G.WebhookURL = parsedData.WebhookURL or ""
                            _G.WebhookEnabled = parsedData.WebhookEnabled or false
                            _G.FarmAreas = parsedData.FarmAreas or {}
                            if parsedData.Settings then for k,v in pairs(parsedData.Settings) do SETTINGS[k] = v end end
                            print("C2 Command: Configuration Loaded locally from " .. SaveFileName)
                        end
                    else
                        warn("C2 Command: No config file found to load.")
                    end
                end)
            
            elseif data.command == "syncConfig" then
                pcall(function()
                    local parsedData = data.payload
                    if parsedData then
                        if parsedData.target_enchant_sets then 
                            local parsedSets = {}
                            for _, setStr in ipairs(parsedData.target_enchant_sets) do
                                local currentSet = {}
                                for enchant in string.gmatch(setStr, "([^%+]+)") do
                                    local trimmed = enchant:match("^%s*(.-)%s*$")
                                    if trimmed and trimmed ~= "" then
                                        table.insert(currentSet, trimmed)
                                    end
                                end
                                table.insert(parsedSets, currentSet)
                            end
                            _G.ActiveTargetSets = parsedSets
                        end
                        if parsedData.whitelisted_uuids then _G.WhitelistedSwords = parsedData.whitelisted_uuids end
                        if parsedData.active_areas then _G.FarmAreas = parsedData.active_areas end
                        if parsedData.farm_enabled ~= nil then 
                            if _G.on ~= parsedData.farm_enabled then
                                _G.on = parsedData.farm_enabled
                                if not _G.on then ResetPhysics() end
                            end
                        end
                        if parsedData.snipe_enabled ~= nil then _G.autoDropEnabled = parsedData.snipe_enabled end
                        
                        if parsedData.TargetSets then _G.ActiveTargetSets = parsedData.TargetSets end
                        if parsedData.WhitelistedSwords then _G.WhitelistedSwords = parsedData.WhitelistedSwords end
                        if parsedData.SpecialOverrides then _G.SpecialOverrides = parsedData.SpecialOverrides end
                        if parsedData.WebhookURL then _G.WebhookURL = parsedData.WebhookURL end
                        if parsedData.WebhookEnabled ~= nil then _G.WebhookEnabled = parsedData.WebhookEnabled end
                        if parsedData.FarmAreas then _G.FarmAreas = parsedData.FarmAreas end
                        if parsedData.TargetPriority then _G.TargetPriority = parsedData.TargetPriority end
                        if parsedData.Settings then for k,v in pairs(parsedData.Settings) do SETTINGS[k] = v end end
                        SaveLocalConfig()
                        print("C2 Command: Configuration Synced remotely from Website!")
                    end
                end)
                
            elseif data.command == "updateWishlist" then
                if typeof(data.payload) == "table" then
                    _G.ActiveTargetSets = data.payload
                    print("C2 Command: Wishlist updated. Size: " .. tostring(#_G.ActiveTargetSets))
                end

            elseif data.command == "setAscenderMode" then
                pcall(function()
                    AscenderRemote:FireServer("Set Ascender Mode", tostring(data.payload))
                    print("C2 Command: Ascender Mode set to", tostring(data.payload))
                end)
            
            elseif data.command == "kick" then
                isC2Kicked = true
                local reason = (data.payload and data.payload.reason) or "Disconnected by C2 Server."
                print("[C2 Client] Kicking player: " .. reason)
                pcall(function()
                    player:Kick(reason)
                end)
            end

        end)
    end)
    end -- End of _G.SetupC2Events

    -- 3. Heartbeat listener to push local Rayfield UI changes & Ascender data to the C2 Dashboard
    pcall(function()
        _G.MainLoopTask = task.spawn(function()
            local lastFarmState = _G.on
            local lastSnipeState = _G.autoDropEnabled
            while task.wait(1) do
                if not _G.LastC2SyncTime or tick() - _G.LastC2SyncTime >= 2 then
                    _G.LastC2SyncTime = tick()
                    
                    pcall(function()
                        if _G.C2_WS then
                            local myLevel = PlayerStats:FindFirstChild("Level") and PlayerStats.Level.Value or 1
                            local myMoney = PlayerStats:FindFirstChild("Money") and PlayerStats.Money.Value or 0
                            local ascenderData = getAscenderPayload()
                            
                            _G.C2_WS:Send(HttpService:JSONEncode({
                                action = "update_status",
                                username = player.Name,
                                api_key = C2_API_KEY,
                                payload = {
                                    status = _G.CurrentState or "Idle",
                                    level = myLevel,
                                    money = myMoney,
                                    backpack_items = getBackpackPayload(),
                                    bot_class = ascenderData.stats.Class or "Farmer",
                                    quality = ascenderData.stats.Quality or "Standard",
                                    rarity = ascenderData.stats.Rarity or "Common",
                                    mold = ascenderData.stats.Mold or "Basic",
                                    ascender_enchant1 = ascenderData.stats.Enchant1 or "None",
                                    ascender_enchant2 = ascenderData.stats.Enchant2 or "None",
                                    ascender_enchant3 = ascenderData.stats.Enchant3 or "None",
                                    ascender_mode = ascenderData.mode or "None",
                                    target_enchant_sets = (function()
                                        local formattedSets = {}
                                        local setsToUse = (#_G.ActiveTargetSets > 0 and _G.ActiveTargetSets) or {{"Ancient", "Fortune", "Insight"}}
                                        for _, set in ipairs(setsToUse) do
                                            table.insert(formattedSets, table.concat(set, " + "))
                                        end
                                        return formattedSets
                                    end)(),
                                    whitelisted_uuids = _G.WhitelistedSwords or {},
                                    farm_enabled = _G.on,
                                    snipe_enabled = _G.autoDropEnabled
                                }
                            }))
                        end
                    end)
                end
            end
        end)
    end)
    
    _G.PeriodicLogTask = task.spawn(function()
        local lastMoney = -1
        local lastLevel = -1
        while task.wait(60) do
            if _G.C2_WS then
                local pStats = ReplicatedStorage:FindFirstChild("Stats")
                local myStats = pStats and pStats:FindFirstChild(tostring(player.Name))
                if myStats then
                    local currentMoney = myStats:FindFirstChild("Money") and myStats.Money.Value or 0
                    local currentLevel = myStats:FindFirstChild("Level") and myStats.Level.Value or 0
                    
                    if lastMoney ~= -1 and lastLevel ~= -1 then
                        local moneyDiff = currentMoney - lastMoney
                        local levelDiff = currentLevel - lastLevel
                        
                        if moneyDiff > 0 or levelDiff > 0 then
                            local msgParts = {}
                            if levelDiff > 0 then table.insert(msgParts, "Leveled up " .. levelDiff .. " times (Now Lvl " .. currentLevel .. ")") end
                            if moneyDiff > 0 then table.insert(msgParts, "Earned " .. moneyDiff .. " Coins") end
                            
                            local messageStr = table.concat(msgParts, " | ")
                            pcall(function()
                                _G.C2_WS:Send(game:GetService("HttpService"):JSONEncode({
                                    action = "log",
                                    username = player.Name,
                                    event_type = "Farming",
                                    message = "dY> " .. messageStr
                                }))
                            end)
                        end
                    end
                    lastMoney = currentMoney
                    lastLevel = currentLevel
                end
            end
        end
    end)
    
    _G.C2ConnectionTask = task.spawn(function()
        maintainC2Connection()
    end)
end)
