-- SnowFlake AutoFarm - Standalone Edition
-- Rayfield UI + Local Config Saving | No C2 | No LuaArmor
-- Full feature parity with the C2 version, controlled entirely via in-game UI.

-- [[ 0. MEMORY LEAK CLEANUP ]]
local function disconnectIfConnected(conn)
    if conn and typeof(conn) == "RBXScriptConnection" and conn.Connected then
        pcall(function() conn:Disconnect() end)
    end
end
disconnectIfConnected(_G.UltimateFarmConnection)
disconnectIfConnected(_G.CharRespawnConnection)
disconnectIfConnected(_G.SwordAddedConnection)
disconnectIfConnected(_G.InvAddedConnection)
disconnectIfConnected(_G.InvRemovedConnection)
disconnectIfConnected(_G.SellingAddedConnection)
disconnectIfConnected(_G.GraphicsStripperConnection1)
disconnectIfConnected(_G.GraphicsStripperConnection2)
disconnectIfConnected(_G.GraphicsStripperConnection3)

if _G.AntiAFKConnection then 
    if typeof(_G.AntiAFKConnection) == "thread" then task.cancel(_G.AntiAFKConnection) else pcall(function() _G.AntiAFKConnection:Disconnect() end) end
    _G.AntiAFKConnection = nil 
end
if _G.InventorySweeperConnection then task.cancel(_G.InventorySweeperConnection); _G.InventorySweeperConnection = nil end
if _G.MainLoopTask then task.cancel(_G.MainLoopTask); _G.MainLoopTask = nil end
if _G.TargetUpdaterTask then task.cancel(_G.TargetUpdaterTask); _G.TargetUpdaterTask = nil end
if _G.SniperTask then task.cancel(_G.SniperTask); _G.SniperTask = nil end
if _G.TeleportTask then task.cancel(_G.TeleportTask); _G.TeleportTask = nil end
if _G.StatusUpdateTask then task.cancel(_G.StatusUpdateTask); _G.StatusUpdateTask = nil end

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualInputManager = game:GetService("VirtualInputManager")
local HttpService = game:GetService("HttpService")
local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local hrp = character:WaitForChild("HumanoidRootPart")
local humanoid = character:WaitForChild("Humanoid")
local playerGui = player:WaitForChild("PlayerGui")

local PlayerStats = ReplicatedStorage:WaitForChild("Stats"):WaitForChild(tostring(player.Name))
local PlayerBackPackSwords = PlayerStats:WaitForChild("Swords")

-- [[ 1. STATE & CONFIGURATION ]]
_G.on = false 
_G.SavedSwordName = nil 
_G.CurrentState = "Idle"
_G.target_priority = "Closest"

_G.autoDropEnabled = false
_G.fetchingGodRoll = false 
_G.activate_panel = false
_G.target_enchant_sets = { {"Ancient", "Fortune", "Insight"} } 
_G.whitelisted_uuids = {} 
_G.KeptSwords = {}
_G.SpecialOverrides = {Enchant = {}, Mold = {}, Quality = {}, Rarity = {}, Class = {}}
_G.webhook_url = ""
_G.webhook_enabled = false

_G.ascender_enabled = false
_G.ascender_queue = {}
_G.ascender_criteria = {}
_G.HandlingAscender = false

_G.active_areas = {} 
local activeAreaRotationIds = {}

local StagedEnchant1, StagedEnchant2, StagedEnchant3 = "None", "None", "None"
local ManualWhitelistInput = ""
local currentArea = 0
local isTeleporting = false
local lastTeleportEnd = 0 
local isEscaping = false
local currentTarget = nil
local targetStartTime = 0
local idleStartTime = 0
local blacklistedNPCs = setmetatable({}, {__mode = "k"})

local SETTINGS = {
    OFFSET_HEIGHT = 7, WAIT_ALTITUDE = 15, RETREAT_ALTITUDE = 15,
    HP_ATTRIBUTE_NAME = "HP", AREA_ATTRIBUTE_NAME = "Area", DANGER_RADIUS = 40, SAFE_COOLDOWN = 0.5,
    MAX_KILL_TIME = 5, BLACKLIST_DURATION = 30, IDLE_BEFORE_HOP = 3, SPAWN_GRACE_PERIOD = 5, 
    MIN_NPCS_TO_STAY = 0,
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
if _G.UltimateFarmConnection then _G.UltimateFarmConnection:Disconnect() end
if _G.StatsConnection then task.cancel(_G.StatsConnection) end
if _G.AntiAFKConnection then 
    if typeof(_G.AntiAFKConnection) == "thread" then task.cancel(_G.AntiAFKConnection) else _G.AntiAFKConnection:Disconnect() end
end
if _G.InventorySweeperConnection then task.cancel(_G.InventorySweeperConnection) end
if _G.CharRespawnConnection then _G.CharRespawnConnection:Disconnect() end
    if _G.SwordAddedConnection then _G.SwordAddedConnection:Disconnect() end
    if _G.InvAddedConnection then _G.InvAddedConnection:Disconnect() end
    if _G.SellingAddedConnection then _G.SellingAddedConnection:Disconnect() end
  if _G.GraphicsStripperConnection1 then _G.GraphicsStripperConnection1:Disconnect() end
  if _G.GraphicsStripperConnection2 then _G.GraphicsStripperConnection2:Disconnect() end
  if _G.GraphicsStripperConnection3 then _G.GraphicsStripperConnection3:Disconnect() end
_G.UltimateFarmConnection = nil
isTeleporting = false
_G.fetchingGodRoll = false

if game.CoreGui:FindFirstChild("Rayfield") then
    game.CoreGui.Rayfield:Destroy()
end
ResetPhysics()

-- [[ 3.5. ANTI-AFK MECHANISM ]]
  if _G.AntiAFKConnection then 
      if typeof(_G.AntiAFKConnection) == "thread" then task.cancel(_G.AntiAFKConnection) else _G.AntiAFKConnection:Disconnect() end
  end
  
  local VirtualInputManager = game:GetService("VirtualInputManager")
  _G.AntiAFKConnection = task.spawn(function()
      while task.wait(20) do
          pcall(function()
              VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
              task.wait(0.1)
              VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
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
          
          local function stripGraphics(v)
              pcall(function()
                  if v:IsA("Texture") or v:IsA("Decal") then
                      v:Destroy()
                  elseif v:IsA("BasePart") and not (v.Parent and v.Parent:FindFirstChild("Humanoid")) then
                      if v.Material ~= Enum.Material.SmoothPlastic then v.Material = Enum.Material.SmoothPlastic end
                      if v.Reflectance ~= 0 then v.Reflectance = 0 end
                      v.CastShadow = false
                  elseif v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Beam") then
                      v.Enabled = false
                  end
              end)
          end

          local descendants = workspace:GetDescendants()
          for i, v in ipairs(descendants) do
              stripGraphics(v)
              if i % 200 == 0 then 
                  task.wait() 
              end
          end
          
          workspace.Terrain.WaterWaveSize = 0
          workspace.Terrain.WaterWaveSpeed = 0
          workspace.Terrain.WaterReflectance = 0
          workspace.Terrain.WaterTransparency = 0
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
    if not _G.webhook_enabled or _G.webhook_url == "" or _G.webhook_url == "Paste URL Here" then return end
    local req = request or http_request or (syn and syn.request)
    if not req then return end
    local data = {["embeds"] = {{["title"] = title, ["description"] = description, ["color"] = color, ["fields"] = fields, ["timestamp"] = DateTime.now():ToIsoDate()}}}
    pcall(function() req({Url = _G.webhook_url, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = HttpService:JSONEncode(data)}) end)
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
    if #_G.target_enchant_sets == 0 then return false end 
    for _, targetSet in ipairs(_G.target_enchant_sets) do
        local tLeft = {}
        if type(targetSet) == "string" then
            for enc in string.gmatch(targetSet, "[^+]+") do
                table.insert(tLeft, enc:match("^%s*(.-)%s*$"))
            end
        elseif type(targetSet) == "table" then
            for _, enc in ipairs(targetSet) do table.insert(tLeft, enc) end
        end
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

_G.DropQueue = _G.DropQueue or {}
_G.DropQueueProcessing = _G.DropQueueProcessing or false

local function processDropQueue()
    if _G.DropQueueProcessing then return end
    _G.DropQueueProcessing = true
    while #_G.DropQueue > 0 do
        local swordUUID = table.remove(_G.DropQueue, 1)
        if _G.autoDropEnabled then
            DropRemote:FireServer("Drop Sword", swordUUID)
        end
        task.wait(0.15)
    end
    _G.DropQueueProcessing = false
end

local function dropBadSword(swordFolder)
    if not _G.autoDropEnabled then return end
    if not table.find(_G.DropQueue, swordFolder.Name) then
        table.insert(_G.DropQueue, swordFolder.Name)
        task.spawn(processDropQueue)
    end
end

local function evaluateInventorySword(swordFolder)
    if not swordFolder:IsA("Folder") then return end
    task.wait(0.5)
    if not swordFolder or not swordFolder.Parent then return end
    
    local keep = false
    if table.find(_G.whitelisted_uuids, swordFolder.Name) then keep = true end
    if _G.ascender_queue and table.find(_G.ascender_queue, swordFolder.Name) then keep = true end
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
    _G.CurrentState = "Teleporting."
    isTeleporting = true 
    ResetPhysics()
    
    local remote = ReplicatedStorage:WaitForChild("Paper"):WaitForChild("Remotes"):WaitForChild("__remotefunction")
    local internalArea = PlayerStats:FindFirstChild("CurrentArea")
    
    if hrp then 
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.Anchored = true
    end
    
    local currentVal = internalArea and tostring(internalArea.Value) or "0"
    print("[DEBUG] Current Area before teleport:", currentVal)

    -- [[ STEP 1: ALWAYS RETURN TO BASE FIRST ]]
    if currentVal ~= "0" and currentVal ~= "Base" and currentVal ~= "Spawn" then
        print("[DEBUG] Returning to Base first.")
        task.spawn(function()
            pcall(function() 
                remote:InvokeServer("Teleport In Base", "Return") 
                remote:InvokeServer("Teleport In Base", "Home")
            end)
        end)
        
        local waitBase = tick()
        while internalArea and tostring(internalArea.Value) ~= "0" and tick() - waitBase < 15 do
            if not _G.on and not _G.fetchingGodRoll and not _G.HandlingAscender then 
                isTeleporting = false
                if hrp then hrp.Anchored = false end
                return 
            end
            task.wait(0.1)
        end
        
        if internalArea and tostring(internalArea.Value) ~= "0" then
            warn("[!] Teleport to Base timed out! Aborting sequence.")
            isTeleporting = false
            if hrp then hrp.Anchored = false end
            return
        end
        
        if not _G.on and not _G.fetchingGodRoll and not _G.HandlingAscender then 
            isTeleporting = false
            if hrp then hrp.Anchored = false end
            return 
        end
        print("[DEBUG] Arrived in Base.")
        task.wait(1)
    else
        print("[DEBUG] Already in Base.")
        if tostring(areaNum) == "0" then
            task.spawn(function()
                pcall(function() 
                    remote:InvokeServer("Teleport In Base", "Home") 
                    remote:InvokeServer("Teleport In Base", "Return")
                end)
            end)
        end
    end
    
    if not _G.on and not _G.fetchingGodRoll and not _G.HandlingAscender then 
        isTeleporting = false
        if hrp then hrp.Anchored = false end
        return 
    end
    DestroyCutscene() 
    
    -- [[ STEP 2: TELEPORT TO TARGET MAP ]]
    if tostring(areaNum) ~= "0" and tostring(areaNum) ~= "Base" and tostring(areaNum) ~= "Spawn" then
        print("[DEBUG] Teleporting from Base to Area:", areaNum)
        task.spawn(function() pcall(function() remote:InvokeServer("Teleport Area", tonumber(areaNum)) end) end)
        
        local waitArea = tick()
        while internalArea and tostring(internalArea.Value) ~= tostring(areaNum) and tick() - waitArea < 15 do
            if not _G.on and not _G.fetchingGodRoll and not _G.HandlingAscender then 
                isTeleporting = false
                if hrp then hrp.Anchored = false end
                return 
            end
            task.wait(0.1)
        end
        
        if internalArea and tostring(internalArea.Value) ~= tostring(areaNum) then
            warn("[!] Teleport to Area timed out! Aborting sequence.")
            isTeleporting = false
            if hrp then hrp.Anchored = false end
            return
        end
        
        if not _G.on and not _G.fetchingGodRoll and not _G.HandlingAscender then 
            isTeleporting = false
            if hrp then hrp.Anchored = false end
            return 
        end
        print("[DEBUG] Arrived in Target Area:", areaNum)
        task.wait(2.5) 
    end
    
    currentArea = tonumber(areaNum) or currentArea
    lastTeleportEnd = tick() 
    idleStartTime = 0 
    isTeleporting = false
    if hrp then hrp.Anchored = false end
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
    local originalCFrame = root.CFrame
    
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
    local machineFolders = {"Ascender", "Sell", "Plot", "Bank", "Auction", "Transcender"}
    
    for _, pStat in pairs(allStats:GetChildren()) do
        for _, folderName in ipairs(machineFolders) do
            local f = pStat:FindFirstChild(folderName)
            if f then
                if f:FindFirstChild(uuid) then return true end
                local uuidVal = f:FindFirstChild("SwordUUID")
                if uuidVal and uuidVal:IsA("StringValue") and uuidVal.Value == uuid then return true end
            end
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
local GetBestTarget = function()
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
                
                if _G.target_priority == "Closest" then
                    if dist < shortestDist then 
                        bestTarget = v
                        shortestDist = dist 
                    end
                else
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
                                if _G.target_priority == "Highest XP" and traitData.Boosts.XP then
                                    score = score * traitData.Boosts.XP
                                elseif _G.target_priority == "Highest Money" and traitData.Boosts.Money then
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
end

-- [[ 8. INVENTORY SWEEPER ]]
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
                            if table.find(_G.whitelisted_uuids, swordFolder.Name) then keep = true end
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
    if not _G.autoDropEnabled or not swordFolder:IsA("Folder") then return end
    task.wait(0.2) 
    if not swordFolder or not swordFolder.Parent then return end
    
    local keep = hasMatchingCombo(getEnchants(swordFolder)) or matchesSpecial(swordFolder)
    
    if keep then
        if _G.SniperTask then task.cancel(_G.SniperTask) end
        
        _G.SniperTask = task.spawn(function()
            print("Sniper: God Roll found in Selling queue!", swordFolder.Name)
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
                physicalSword = workspace.Swords:FindFirstChild(swordFolder.Name) or workspace:FindFirstChild(swordFolder.Name)
                if not physicalSword then task.wait(0.1) end
            end
            
            if physicalSword then
                local touchStart = tick()
                while physicalSword and physicalSword.Parent and tick() - touchStart < 2 do
                    local targetCFrame = physicalSword:IsA("Model") and physicalSword:GetPivot() or physicalSword.CFrame
                    if targetCFrame then
                        local offset = CFrame.new(math.sin(tick() * 15) * 2, 0, math.cos(tick() * 15) * 2)
                        pcall(function() hrp.CFrame = targetCFrame * offset end)
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
        end)
    end
end

-- [[ 9. SWORD EVENT CONNECTIONS ]]
task.spawn(function()
    local pStats = ReplicatedStorage:WaitForChild("Stats"):WaitForChild(tostring(player.Name))
    local invFolder = pStats:WaitForChild("Swords")
    if _G.InvAddedConnection then _G.InvAddedConnection:Disconnect() end
    _G.InvAddedConnection = invFolder.ChildAdded:Connect(evaluateInventorySword)
    
    local sellingFolder = pStats:WaitForChild("Selling", 10)
    if sellingFolder then
        _G.SellingAddedConnection = sellingFolder.ChildAdded:Connect(evaluateSellingSword)
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
        warn("💀 Respawn detected! Hopping zones to unlock interactions.")
        if not isTeleporting then
            if _G.TeleportTask then task.cancel(_G.TeleportTask) end
            _G.TeleportTask = task.spawn(function()
                local targetArea = (#_G.active_areas > 0 and _G.active_areas[1]) or currentArea
                TeleportSequence(targetArea)
            end)
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

  -- Target Updater Loop
  _G.TargetUpdaterTask = task.spawn(function()
      while task.wait(0.5) do
        if not _G.on or BotState == "Dead" or BotState == "Disabled" then continue end
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

local BankCapacityPerLevel = {
    6, 10, 12, 14, 16,
    18, 20, 22, 24, 26,
    28, 30, 32, 34, 36
}

local function GetMaxBankSlots()
    local bankLvlObj = PlayerStats:FindFirstChild("BankLevel")
    local lvl = bankLvlObj and tonumber(bankLvlObj.Value) or 1
    return BankCapacityPerLevel[lvl] or (lvl > 15 and 36 or 6)
end

local function getIdFromName(statType, targetName)
    if not targetName or targetName == "None" or targetName == "0" then return 0 end
    local m = SwordModules[statType]
    if not m then return 0 end
    for id, data in pairs(m) do
        if type(data) == "table" and data.Name == targetName then
            return tonumber(id) or 0
        elseif type(data) == "string" and data == targetName then
            return tonumber(id) or 0
        end
    end
    return 0
end

local function getNames(statType)
    local m = SwordModules[statType]
    local names = {"None"}
    if not m then return names end
    
    local sortedIds = {}
    for id, _ in pairs(m) do table.insert(sortedIds, tonumber(id)) end
    table.sort(sortedIds, function(a, b) return a < b end)
    
    for _, id in ipairs(sortedIds) do
        local data = m[id] or m[tostring(id)]
        if type(data) == "table" and data.Name then
            table.insert(names, data.Name)
        elseif type(data) == "string" then
            table.insert(names, data)
        end
    end
    return names
end

local function isStatUnmet(swordFolder, attrName, targetVal, moduleName)
    if targetVal and targetVal ~= "None" and targetVal ~= 0 then
        if type(targetVal) == "number" then
            local currentVal = tonumber(swordFolder:GetAttribute(attrName)) or 0
            if currentVal < targetVal then return true end
        else
            local targetId = getIdFromName(moduleName or attrName, targetVal)
            local currentId = tonumber(swordFolder:GetAttribute(attrName)) or 0
            if targetId > 0 and currentId < targetId then return true end
        end
    end
    return false
end

local function getTargetMode(swordFolder)
    local t = _G.ascender_criteria
    if not t then return "None" end
    
    if isStatUnmet(swordFolder, "Quality", t.Quality) then return "Quality" end
    if isStatUnmet(swordFolder, "Rarity", t.Rarity) then return "Rarity" end
    if isStatUnmet(swordFolder, "Mold", t.Mold) then return "Mold" end
    if isStatUnmet(swordFolder, "Class", t.Class) then return "Class" end
    
    if isStatUnmet(swordFolder, "Enchant1", t.Enchant1Name, "Enchant") or isStatUnmet(swordFolder, "Enchant1Level", t.Enchant1Level) then return "Enchant1" end
    if isStatUnmet(swordFolder, "Enchant2", t.Enchant2Name, "Enchant") or isStatUnmet(swordFolder, "Enchant2Level", t.Enchant2Level) then return "Enchant2" end
    if isStatUnmet(swordFolder, "Enchant3", t.Enchant3Name, "Enchant") or isStatUnmet(swordFolder, "Enchant3Level", t.Enchant3Level) then return "Enchant3" end
    
    if isStatUnmet(swordFolder, "Level", t.Level) then return "Level" end
    
    return "None"
end

local function swordMeetsCriteria(swordFolder)
    return getTargetMode(swordFolder) == "None"
end

local function PickupPhysicalSword(uuid)
    local physicalSword = workspace.Swords:FindFirstChild(uuid)
    if not physicalSword then return false end
    
    local character = player.Character or player.CharacterAdded:Wait()
    local hrp = character:WaitForChild("HumanoidRootPart")
    
    local maxAttempts = 15
    local attempts = 0
    
    while not PlayerStats.Swords:FindFirstChild(uuid) and attempts < maxAttempts do
        if not physicalSword or not physicalSword.Parent then break end
        
        local pivot = physicalSword:GetPivot()
        hrp.CFrame = pivot * CFrame.new(0, 15, 0) 
        
        attempts = attempts + 1
        task.wait(0.3)
    end
    return PlayerStats.Swords:FindFirstChild(uuid) ~= nil
end

local function enforceCleanInventory(allowedUUID)
    if not PlayerStats then return end
    
    local extraSwords = {}
    for _, s in ipairs(PlayerStats.Swords:GetChildren()) do
        local isWhitelisted = _G.whitelisted_uuids and table.find(_G.whitelisted_uuids, s.Name)
        if s.Name ~= allowedUUID and not isWhitelisted then
            table.insert(extraSwords, s.Name)
        end
    end
    
    if #extraSwords > 0 then
        local currentBankCount = PlayerStats.Bank and #PlayerStats.Bank:GetChildren() or 0
        local dynamicMaxSlots = GetMaxBankSlots()
        
        if currentBankCount >= dynamicMaxSlots then
            print("[AutoAscender] ⚠️ Bank full. Sweeper bypassed to protect inventory items.")
            return
        end
        
        print("[AutoAscender] 🧹 Found " .. #extraSwords .. " extra/stuck sword(s) in inventory. Strictly depositing to Bank.")
        local AscenderFunc = ReplicatedStorage:WaitForChild("Paper"):WaitForChild("Remotes"):WaitForChild("__remotefunction")
        local AscenderEvent = ReplicatedStorage:WaitForChild("Paper"):WaitForChild("Remotes"):WaitForChild("__remoteevent")
        task.spawn(function() pcall(function() AscenderFunc:InvokeServer("Teleport In Base", "Bank") end) end)
        task.wait(0.6)
        
        for _, uuid in ipairs(extraSwords) do
            currentBankCount = PlayerStats.Bank and #PlayerStats.Bank:GetChildren() or 0
            if currentBankCount >= dynamicMaxSlots then
                print("[AutoAscender] ⚠️ Bank filled up during sweep! Halting sweeper.")
                break
            end
            AscenderEvent:FireServer("Drop Sword", uuid)
            task.wait(0.2)
        end
        
        local waitTime = 0
        while waitTime < 3 do
            local stillHasExtra = false
            for _, uuid in ipairs(extraSwords) do
                if PlayerStats.Swords:FindFirstChild(uuid) then stillHasExtra = true end
            end
            if not stillHasExtra then break end
            task.wait(0.2)
            waitTime = waitTime + 0.2
        end
    end
end

-- [[ AUTO ASCENDER LOGIC ]]
local function ExecuteAscenderAction(actionDetails)
    if _G.HandlingAscender then return end
    _G.HandlingAscender = true
    _G.CurrentState = "Managing Ascender."

    local originalArea = currentArea
    local PaperRemotes = ReplicatedStorage:WaitForChild("Paper"):WaitForChild("Remotes")
    local AscenderFunc = PaperRemotes:WaitForChild("__remotefunction")
    local AscenderEvent = PaperRemotes:WaitForChild("__remoteevent")
    
    isTeleporting = true
    task.spawn(function() TeleportSequence(0) end)
    repeat task.wait(0.1) until not isTeleporting

    local success, err = pcall(function()
        if actionDetails.type == "FinishAndSwap" then
            local currentSword = PlayerStats.Ascender:FindFirstChild(actionDetails.finishedUUID)
            if not currentSword then return end
            
            print("[AutoAscender] 🎯 Target reached for sword:", currentSword.Name)
            print("[AutoAscender] Picking up from Ascender.")
            
            task.spawn(function() pcall(function() AscenderFunc:InvokeServer("Pickup Ascender") end) end)
            
            local waitTime = 0
            while not PlayerStats.Swords:FindFirstChild(currentSword.Name) and waitTime < 5 do
                task.wait(0.2)
                waitTime = waitTime + 0.2
            end
            
            local currentBankCount = PlayerStats.Bank and #PlayerStats.Bank:GetChildren() or 0
            local dynamicMaxSlots = GetMaxBankSlots()
            
            if currentBankCount >= dynamicMaxSlots then
                warn("[AutoAscender] ⚠️ BANK IS AT MAXIMUM CAPACITY (" .. currentBankCount .. "/" .. dynamicMaxSlots .. ")!")
                warn("[AutoAscender] 🛡️ Keeping finished sword in your Inventory and protecting it!")
                if not table.find(_G.whitelisted_uuids, currentSword.Name) then
                    table.insert(_G.whitelisted_uuids, currentSword.Name)
                    pcall(function() if _G.SaveComplexConfig then _G.SaveComplexConfig() end end)
                end
            else
                print("[AutoAscender] Depositing to Bank.")
                task.spawn(function() pcall(function() AscenderFunc:InvokeServer("Teleport In Base", "Bank") end) end)
                task.wait(0.6)
                AscenderEvent:FireServer("Drop Sword", currentSword.Name)
                
                waitTime = 0
                while PlayerStats.Swords:FindFirstChild(currentSword.Name) and waitTime < 5 do
                    task.wait(0.2)
                    waitTime = waitTime + 0.2
                end
                
                enforceCleanInventory(nil)
            end
            
            if #_G.ascender_queue > 0 then
                local nextUUID = _G.ascender_queue[1]
                local readyToDrop = PickupPhysicalSword(nextUUID)
                
                if readyToDrop then
                    enforceCleanInventory(nextUUID)
                    task.spawn(function() pcall(function() AscenderFunc:InvokeServer("Teleport In Base", "Ascender") end) end)
                    task.wait(0.5) 
                    AscenderEvent:FireServer("Drop Sword", nextUUID)
                    table.remove(_G.ascender_queue, 1)
                    
                    waitTime = 0
                    while PlayerStats.Swords:FindFirstChild(nextUUID) and waitTime < 5 do
                        task.wait(0.2)
                        waitTime = waitTime + 0.2
                    end
                    
                    local swordFolder = PlayerStats.Ascender:FindFirstChild(nextUUID)
                    if swordFolder then
                        local mode = getTargetMode(swordFolder)
                        if mode ~= "None" then
                            AscenderEvent:FireServer("Set Ascender Mode", mode)
                            print("[AutoAscender] ⚙️ Set Ascender Mode to:", mode)
                        end
                    end
                    task.wait(1.5)
                else
                    warn("[AutoAscender] 🚨 Sword UUID " .. tostring(nextUUID) .. " not found! Removing from queue.")
                    table.remove(_G.ascender_queue, 1)
                end
                
                pcall(function() if _G.SaveComplexConfig then _G.SaveComplexConfig() end end)
            end
            
        elseif actionDetails.type == "StartNext" then
            local nextUUID = _G.ascender_queue[1]
            local readyToDrop = PickupPhysicalSword(nextUUID)
            
            if readyToDrop then
                enforceCleanInventory(nextUUID)
                task.spawn(function() pcall(function() AscenderFunc:InvokeServer("Teleport In Base", "Ascender") end) end)
                task.wait(0.5) 
                AscenderEvent:FireServer("Drop Sword", nextUUID)
                table.remove(_G.ascender_queue, 1)
                
                local waitTime = 0
                while PlayerStats.Swords:FindFirstChild(nextUUID) and waitTime < 5 do
                    task.wait(0.2)
                    waitTime = waitTime + 0.2
                end
                
                local swordFolder = PlayerStats.Ascender:FindFirstChild(nextUUID)
                if swordFolder then
                    local mode = getTargetMode(swordFolder)
                    if mode ~= "None" then
                        AscenderEvent:FireServer("Set Ascender Mode", mode)
                        print("[AutoAscender] ⚙️ Set Ascender Mode to:", mode)
                    end
                end
                task.wait(1.5)
            else
                warn("[AutoAscender] 🚨 Sword UUID " .. tostring(nextUUID) .. " not found! Removing from queue.")
                table.remove(_G.ascender_queue, 1)
            end
            
            pcall(function() if _G.SaveComplexConfig then _G.SaveComplexConfig() end end)
        end
    end)
    if not success then warn("[Ascender Error] " .. tostring(err)) end

    if originalArea and originalArea ~= 0 then
        isTeleporting = true
        task.spawn(function() TeleportSequence(originalArea) end)
        repeat task.wait(0.1) until not isTeleporting
    end
    
    _G.HandlingAscender = false
end

local lastModeSet = 0
local function CheckAscenderNeedsAction()
    if not PlayerStats then return false end
    local AscenderFolder = PlayerStats:FindFirstChild("Ascender")
    if not AscenderFolder then return false end
    
    local currentSword = AscenderFolder:FindFirstChildOfClass("Folder")
    
    if currentSword then
        if swordMeetsCriteria(currentSword) then
            return { type = "FinishAndSwap", finishedUUID = currentSword.Name }
        end
    elseif not currentSword and #_G.ascender_queue > 0 then
        return { type = "StartNext" }
    end
    
    return false 
end

-- 🧠 FSM Brain: Determines absolute priority
local lastMissingCheck = 0

local DetermineState = function()
    -- Independent Background Logic: Auto-Set Ascender Mode
    pcall(function()
        local stats = game:GetService("ReplicatedStorage"):FindFirstChild("Stats")
        local myStats = stats and stats:FindFirstChild(tostring(game.Players.LocalPlayer.Name))
        local ascenderFolder = myStats and myStats:FindFirstChild("Ascender")
        local sword = ascenderFolder and ascenderFolder:FindFirstChildOfClass("Folder")
        if sword and os.time() - lastModeSet >= 2 then
            lastModeSet = os.time()
            local targetMode = getTargetMode(sword)
            if targetMode ~= "None" then
                local paper = game:GetService("ReplicatedStorage"):FindFirstChild("Paper")
                local remotes = paper and paper:FindFirstChild("Remotes")
                local remoteEvt = remotes and remotes:FindFirstChild("__remoteevent")
                if remoteEvt then
                    remoteEvt:FireServer("Set Ascender Mode", targetMode)
                end
            end
        end
    end)

    if not character or not character.Parent or not humanoid or humanoid.Health <= 0 then return "Dead" end
    if _G.fetchingGodRoll then return "Sniping" end
    if _G.HandlingAscender then return "Ascending" end
    if isTeleporting then return "Teleporting" end
    
    if _G.ascender_enabled and not _G.HandlingAscender then
        local actionNeeded = CheckAscenderNeedsAction()
        if actionNeeded then
            task.spawn(function() ExecuteAscenderAction(actionNeeded) end)
            return "Ascending"
        end
    end

    if not _G.on then return "Disabled" end
    if _G.on and #_G.active_areas == 0 then
        _G.on = false
        warn("[DEBUG] AutoFarm disabled because no Farm Areas are selected!")
        return "Idle (No Maps Selected)"
    end
    
    if isTeleporting then return "Teleporting" end

    local actualArea = currentArea
    local pStats = ReplicatedStorage:FindFirstChild("Stats")
    if pStats then
        local myStats = pStats:FindFirstChild(tostring(player.Name))
        local internalArea = myStats and myStats:FindFirstChild("CurrentArea")
        if internalArea then actualArea = internalArea.Value end
    end
    
    if tostring(actualArea) == "Base" or tostring(actualArea) == "Spawn" then actualArea = 0 end
    local actualNum, wantedNum = tonumber(actualArea) or 0, tonumber(currentArea)
    if actualNum ~= 0 then _G.LastKnownArea = actualNum end
    
    if (not wantedNum or wantedNum == 0) and #_G.active_areas > 0 then 
        wantedNum = _G.active_areas[1]
        currentArea = wantedNum
    elseif (not wantedNum or wantedNum == 0) then 
        wantedNum = 0; currentArea = 0 
    end

    if tick() - lastMissingCheck > 1 then
        lastMissingCheck = tick()
        StateData.MissingSwords = CheckMissingSwords()
    end
    if #StateData.MissingSwords > 0 then return "Recovering" end

    if actualNum ~= wantedNum then 
        isTeleporting = true
        task.spawn(function() TeleportSequence(wantedNum) end)
        return "Teleporting"
    end

    local currentTool = character:FindFirstChildOfClass("Tool")
    local bestSwordToEquip = nil
    
    if PlayerStats and PlayerStats:FindFirstChild("Swords") then
        for _, uuid in ipairs(_G.whitelisted_uuids or {}) do
            local sword = PlayerStats.Swords:FindFirstChild(uuid)
            if sword and sword:IsA("Folder") and not isSwordLockedInAnyMachine(uuid) then
                bestSwordToEquip = uuid
                break
            end
        end
    end
    
    if not bestSwordToEquip and currentTool and string.len(currentTool.Name) > 15 then
        bestSwordToEquip = currentTool.Name
    end
    
    if bestSwordToEquip then
        if not currentTool or currentTool.Name ~= bestSwordToEquip then
            _G.SavedSwordName = bestSwordToEquip
            return "Equipping"
        else
            _G.SavedSwordName = bestSwordToEquip
            _G.SentNoSwordNotif = false
            if not table.find(_G.KeptSwords, bestSwordToEquip) then table.insert(_G.KeptSwords, bestSwordToEquip) end
        end
    else
        if _G.on then
            _G.CurrentState = "No Valid Sword!"
            if hrp and hrp.Position.Y < 300 then
                pcall(function() hrp.CFrame = hrp.CFrame + Vector3.new(0, 300 - hrp.Position.Y + 50, 0) end)
            end
            return "No Valid Sword!"
        end
        return "Idle"
    end

    if currentTarget then return "Farming" end
    return "Idle"
end

-- ⚙️ Executor Loop
local lastSwing = 0

local FarmHeartbeatLoop = function()
    local newState, extraData = DetermineState()
    BotState = newState

    if BotState == "Disabled" then _G.CurrentState = "Idle"; return end
    if BotState == "Dead" then _G.CurrentState = "Dead/Respawning."; return end
    if BotState == "Sniping" or BotState == "Teleporting" or BotState == "Ascending" then return end

    humanoid:ChangeState(Enum.HumanoidStateType.Physics)
    humanoid.PlatformStand = true 
    humanoid.AutoRotate = false
    hrp.AssemblyLinearVelocity = Vector3.zero

    if BotState == "Recovering" then
        local myStats = game:GetService("ReplicatedStorage"):FindFirstChild("Stats") and game:GetService("ReplicatedStorage").Stats:FindFirstChild(tostring(game.Players.LocalPlayer.Name))
        local internalArea = myStats and myStats:FindFirstChild("CurrentArea")
        local actualNum = internalArea and tonumber(internalArea.Value) or 0
        if _G.LastKnownArea and _G.LastKnownArea ~= 0 and actualNum ~= _G.LastKnownArea then
            isTeleporting = true
            task.spawn(function() TeleportSequence(_G.LastKnownArea) end)
            return
        end

        StateData.SignalWaitStart = nil
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
            
            local hoverHeight = 0
            if (t % 2) < 1 then
                offsetPos = Vector3.new(math.sin(t * 15) * 2, hoverHeight, math.cos(t * 15) * 2)
            else
                local sweep = math.sin(t * 15) * 3
                offsetPos = Vector3.new(sweep, hoverHeight, sweep)
            end
            
            hrp.CFrame = CFrame.new(targetPos + offsetPos)
            
            if not StateData.LastTouch or tick() - StateData.LastTouch > 0.2 then
                StateData.LastTouch = tick()
            end
        end

    elseif BotState == "Equipping" then
        _G.CurrentState = "Equipping Main Weapon."
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

        if currentTarget:FindFirstChild("HumanoidRootPart") then
            local offsetHeight = SETTINGS.OFFSET_HEIGHT == 0 and 0.001 or SETTINGS.OFFSET_HEIGHT
            hrp.CFrame = CFrame.lookAt(currentTarget.HumanoidRootPart.Position + Vector3.new(0, offsetHeight, 0), currentTarget.HumanoidRootPart.Position)
            if tick() - lastSwing > 0.25 then
                lastSwing = tick()
                local currentTool = character:FindFirstChildOfClass("Tool")
                if currentTool then currentTool:Activate() end
            end
        end

    elseif BotState == "Idle" then
        StateData.EquipAttemptStart = nil
        local now = tick()
        
        if now - lastTeleportEnd < SETTINGS.SPAWN_GRACE_PERIOD then
            _G.CurrentState = "Waiting for Spawns."
            StateData.IdleStartTime = 0 
        elseif StateData.IdleStartTime == 0 then 
            StateData.IdleStartTime = now
        elseif now - StateData.IdleStartTime > SETTINGS.IDLE_BEFORE_HOP then
            _G.CurrentState = "Hopping Areas."
            
            local actualArea = tonumber(currentArea)
            local pStats = ReplicatedStorage:FindFirstChild("Stats")
            if pStats then
                local myStats = pStats:FindFirstChild(tostring(player.Name))
                local internalArea = myStats and myStats:FindFirstChild("CurrentArea")
                if internalArea then actualArea = tonumber(internalArea.Value) end
            end

            local nextArea = actualArea
            if #_G.active_areas > 0 then
                local currentIndex = table.find(_G.active_areas, actualArea)
                if currentIndex then
                    local nextIndex = currentIndex + 1
                    if nextIndex > #_G.active_areas then nextIndex = 1 end
                    nextArea = _G.active_areas[nextIndex]
                else 
                    nextArea = _G.active_areas[1] 
                end
            end
            
            StateData.IdleStartTime = 0
            isTeleporting = true 
            task.spawn(function() TeleportSequence(nextArea) end)
            return 
        end
        
        _G.CurrentState = "Area Clear / Hovering."
        hrp.CFrame = CFrame.new(hrp.Position.X, SETTINGS.WAIT_ALTITUDE, hrp.Position.Z)
    end
end

_G.UltimateFarmConnection = RunService.Heartbeat:Connect(FarmHeartbeatLoop)

-- =========================================================================
-- [[ 12. CONFIG SAVE/LOAD SYSTEM (Replaces C2 WebSocket) ]]
-- =========================================================================
local CONFIG_FOLDER = "SnowflakeAutoFarm"
local CONFIG_FILE = CONFIG_FOLDER .. "/data.json"

_G.SaveComplexConfig = function()
    pcall(function()
        if not isfolder(CONFIG_FOLDER) then makefolder(CONFIG_FOLDER) end
        local config = {
            target_enchant_sets = _G.target_enchant_sets,
            whitelisted_uuids = _G.whitelisted_uuids,
            active_areas = _G.active_areas,
            ascender_queue = _G.ascender_queue,
            ascender_criteria = _G.ascender_criteria,
            SpecialOverrides = _G.SpecialOverrides,
        }
        writefile(CONFIG_FILE, HttpService:JSONEncode(config))
    end)
end

local function LoadComplexConfig()
    pcall(function()
        if isfile(CONFIG_FILE) then
            local raw = readfile(CONFIG_FILE)
            local data = HttpService:JSONDecode(raw)
            if data.target_enchant_sets then _G.target_enchant_sets = data.target_enchant_sets end
            if data.whitelisted_uuids then _G.whitelisted_uuids = data.whitelisted_uuids end
            if data.active_areas then _G.active_areas = data.active_areas end
            if data.ascender_queue then _G.ascender_queue = data.ascender_queue end
            if data.ascender_criteria then _G.ascender_criteria = data.ascender_criteria end
            if data.SpecialOverrides then _G.SpecialOverrides = data.SpecialOverrides end
            print("[Config] Loaded saved complex config from " .. CONFIG_FILE)
        end
    end)
end

LoadComplexConfig()

-- =========================================================================
-- [[ 13. PERFORMANCE SETUP ]]
-- =========================================================================
task.spawn(function()
    pcall(function() 
        RunService:Set3dRenderingEnabled(false) 
        setfpscap(3)
    end)
end)

-- =========================================================================
-- [[ 14. RAYFIELD UI ]]
-- =========================================================================
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- Helper: format enchant sets for display
local function formatEnchantSets()
    if #_G.target_enchant_sets == 0 then return "None" end
    local lines = {}
    for i, set in ipairs(_G.target_enchant_sets) do
        if type(set) == "string" then
            table.insert(lines, i .. ". " .. set)
        elseif type(set) == "table" then
            table.insert(lines, i .. ". " .. table.concat(set, " + "))
        end
    end
    return table.concat(lines, "\n")
end

local function formatUUIDList(list, maxShow)
    maxShow = maxShow or 10
    if #list == 0 then return "None" end
    local lines = {}
    for i = 1, math.min(#list, maxShow) do
        table.insert(lines, i .. ". " .. tostring(list[i]))
    end
    if #list > maxShow then table.insert(lines, "... and " .. (#list - maxShow) .. " more") end
    return table.concat(lines, "\n")
end

local Window = Rayfield:CreateWindow({
    Name = "SnowFlake AutoFarm",
    LoadingTitle = "SnowFlake",
    LoadingSubtitle = "Standalone Edition",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "SnowflakeAutoFarm",
        FileName = "RayfieldConfig"
    },
    KeySystem = false
})

-- ========================
-- TAB 1: FARM CONTROL
-- ========================
local FarmTab = Window:CreateTab("⚔️ Farm", 4483362458)
FarmTab:CreateSection("Control")

FarmTab:CreateToggle({
    Name = "Enable AutoFarm",
    CurrentValue = false,
    Flag = "ToggleFarm",
    Callback = function(Value)
        _G.on = Value
        if _G.on then
            if #_G.active_areas > 0 then
                local actualArea = currentArea
                local pStats = ReplicatedStorage:FindFirstChild("Stats")
                if pStats then
                    local myStats = pStats:FindFirstChild(tostring(player.Name))
                    local internalArea = myStats and myStats:FindFirstChild("CurrentArea")
                    if internalArea then actualArea = internalArea.Value end
                end
                if not table.find(_G.active_areas, actualArea) and not isTeleporting then
                    isTeleporting = true
                    task.spawn(function() TeleportSequence(_G.active_areas[1]) end)
                end
            end
        else
            ResetPhysics()
        end
    end
})

FarmTab:CreateSection("Area Selection")

local areaOptions = {}
for i = 1, 30 do table.insert(areaOptions, tostring(i)) end

FarmTab:CreateDropdown({
    Name = "Farm Areas (Multi-Select)",
    Options = areaOptions,
    CurrentOption = {},
    MultipleOptions = true,
    Flag = "FarmAreas",
    Callback = function(Options)
        _G.active_areas = {}
        for _, opt in ipairs(Options) do
            local num = tonumber(opt)
            if num then table.insert(_G.active_areas, num) end
        end
        _G.SaveComplexConfig()
        
        if _G.on and #_G.active_areas > 0 and not isTeleporting then
            if not table.find(_G.active_areas, tonumber(currentArea)) then
                currentArea = _G.active_areas[1]
                isTeleporting = true
                task.spawn(function() TeleportSequence(currentArea) end)
            end
        end
    end
})

FarmTab:CreateSection("Combat")

FarmTab:CreateDropdown({
    Name = "Target Priority",
    Options = {"Closest", "Highest XP", "Highest Money"},
    CurrentOption = {"Closest"},
    MultipleOptions = false,
    Flag = "TargetPriority",
    Callback = function(Options)
        _G.target_priority = Options[1] or "Closest"
    end
})

FarmTab:CreateSlider({
    Name = "Offset Height",
    Range = {0, 20},
    Increment = 1,
    Suffix = " studs",
    CurrentValue = 7,
    Flag = "OffsetHeight",
    Callback = function(Value)
        SETTINGS.OFFSET_HEIGHT = Value
    end
})

FarmTab:CreateSlider({
    Name = "Wait Altitude",
    Range = {5, 100},
    Increment = 1,
    Suffix = " studs",
    CurrentValue = 15,
    Flag = "WaitAltitude",
    Callback = function(Value)
        SETTINGS.WAIT_ALTITUDE = Value
        SETTINGS.RETREAT_ALTITUDE = Value
    end
})

FarmTab:CreateSlider({
    Name = "Idle Before Hop",
    Range = {1, 30},
    Increment = 1,
    Suffix = "s",
    CurrentValue = 3,
    Flag = "IdleBeforeHop",
    Callback = function(Value)
        SETTINGS.IDLE_BEFORE_HOP = Value
    end
})

FarmTab:CreateSlider({
    Name = "Min NPCs to Stay",
    Range = {0, 10},
    Increment = 1,
    Suffix = " npcs",
    CurrentValue = 0,
    Flag = "MinNPCs",
    Callback = function(Value)
        SETTINGS.MIN_NPCS_TO_STAY = Value
    end
})

FarmTab:CreateSection("Quick Actions")

FarmTab:CreateButton({
    Name = "Teleport Home",
    Callback = function()
        task.spawn(function()
            pcall(function() hrp.CFrame = CFrame.new(hrp.Position.X, hrp.Position.Y + 500, hrp.Position.Z) end)
            task.wait(0.5)
            pcall(function()
                local remote = ReplicatedStorage:WaitForChild("Paper"):WaitForChild("Remotes"):WaitForChild("__remotefunction")
                task.spawn(function()
                    pcall(function()
                        remote:InvokeServer("Teleport In Base", "Return")
                        remote:InvokeServer("Teleport In Base", "Home")
                    end)
                end)
            end)
        end)
        Rayfield:Notify({Title = "Teleport", Content = "Teleporting Home!", Duration = 2})
    end
})

FarmTab:CreateButton({
    Name = "Reset Physics",
    Callback = function()
        ResetPhysics()
        Rayfield:Notify({Title = "Physics", Content = "Physics reset!", Duration = 2})
    end
})

-- ========================
-- TAB 2: SNIPER
-- ========================
local SniperTab = Window:CreateTab("🎯 Sniper", 4483362458)
SniperTab:CreateSection("Auto-Drop")

SniperTab:CreateToggle({
    Name = "Enable Auto-Drop / Sniper",
    CurrentValue = false,
    Flag = "ToggleSnipe",
    Callback = function(Value)
        _G.autoDropEnabled = Value
        if Value then
            pcall(function()
                local pStats = ReplicatedStorage:FindFirstChild("Stats"):FindFirstChild(tostring(player.Name))
                for _, f in pairs(pStats:FindFirstChild("Swords"):GetChildren()) do evaluateInventorySword(f) end 
            end)
        end
    end
})

SniperTab:CreateSection("Enchant Wishlist")

local EnchantSetsParagraph = SniperTab:CreateParagraph({Title = "Current Sets", Content = formatEnchantSets()})
local newEnchantSetInput = ""

SniperTab:CreateInput({
    Name = "New Enchant Set",
    PlaceholderText = "e.g. Ancient + Fortune + Insight",
    RemoveTextAfterFocusLost = true,
    Flag = "NewEnchantInput",
    Callback = function(Text)
        newEnchantSetInput = Text
    end
})

SniperTab:CreateButton({
    Name = "Add Enchant Set",
    Callback = function()
        if newEnchantSetInput == "" then Rayfield:Notify({Title = "Error", Content = "Type an enchant set first!", Duration = 2}); return end
        local parsed = {}
        for enc in string.gmatch(newEnchantSetInput, "[^+]+") do
            table.insert(parsed, enc:match("^%s*(.-)%s*$"))
        end
        if #parsed > 0 then
            table.insert(_G.target_enchant_sets, parsed)
            _G.SaveComplexConfig()
            EnchantSetsParagraph:Set({Title = "Current Sets (" .. #_G.target_enchant_sets .. ")", Content = formatEnchantSets()})
            Rayfield:Notify({Title = "Added", Content = "Set: " .. table.concat(parsed, " + "), Duration = 2})
        end
    end
})

SniperTab:CreateButton({
    Name = "Remove Last Set",
    Callback = function()
        if #_G.target_enchant_sets > 0 then
            table.remove(_G.target_enchant_sets)
            _G.SaveComplexConfig()
            EnchantSetsParagraph:Set({Title = "Current Sets (" .. #_G.target_enchant_sets .. ")", Content = formatEnchantSets()})
            Rayfield:Notify({Title = "Removed", Content = "Last enchant set removed!", Duration = 2})
        end
    end
})

SniperTab:CreateButton({
    Name = "Clear All Sets",
    Callback = function()
        _G.target_enchant_sets = {}
        _G.SaveComplexConfig()
        EnchantSetsParagraph:Set({Title = "Current Sets", Content = "None"})
        Rayfield:Notify({Title = "Cleared", Content = "All enchant sets cleared!", Duration = 2})
    end
})

SniperTab:CreateSection("Special Overrides")

local enchantNames = getNames("Enchant1")
table.remove(enchantNames, 1) -- Remove "None" for multi-select

SniperTab:CreateDropdown({
    Name = "Enchant Overrides",
    Options = enchantNames,
    CurrentOption = _G.SpecialOverrides.Enchant or {},
    MultipleOptions = true,
    Flag = "SpecialEnchants",
    Callback = function(Options)
        _G.SpecialOverrides.Enchant = Options
        _G.SaveComplexConfig()
    end
})

local moldNames = getNames("Mold")
table.remove(moldNames, 1)

SniperTab:CreateDropdown({
    Name = "Mold Overrides",
    Options = moldNames,
    CurrentOption = _G.SpecialOverrides.Mold or {},
    MultipleOptions = true,
    Flag = "SpecialMolds",
    Callback = function(Options)
        _G.SpecialOverrides.Mold = Options
        _G.SaveComplexConfig()
    end
})

local qualityNames = getNames("Quality")
table.remove(qualityNames, 1)

SniperTab:CreateDropdown({
    Name = "Quality Overrides",
    Options = qualityNames,
    CurrentOption = _G.SpecialOverrides.Quality or {},
    MultipleOptions = true,
    Flag = "SpecialQualities",
    Callback = function(Options)
        _G.SpecialOverrides.Quality = Options
        _G.SaveComplexConfig()
    end
})

local rarityNames = getNames("Rarity")
table.remove(rarityNames, 1)

SniperTab:CreateDropdown({
    Name = "Rarity Overrides",
    Options = rarityNames,
    CurrentOption = _G.SpecialOverrides.Rarity or {},
    MultipleOptions = true,
    Flag = "SpecialRarities",
    Callback = function(Options)
        _G.SpecialOverrides.Rarity = Options
        _G.SaveComplexConfig()
    end
})

local classNames = getNames("Class")
table.remove(classNames, 1)

SniperTab:CreateDropdown({
    Name = "Class Overrides",
    Options = classNames,
    CurrentOption = _G.SpecialOverrides.Class or {},
    MultipleOptions = true,
    Flag = "SpecialClasses",
    Callback = function(Options)
        _G.SpecialOverrides.Class = Options
        _G.SaveComplexConfig()
    end
})

-- ========================
-- TAB 3: WHITELIST
-- ========================
local WhitelistTab = Window:CreateTab("🗡️ Whitelist", 4483362458)
WhitelistTab:CreateSection("Sword Whitelist")

local WhitelistParagraph = WhitelistTab:CreateParagraph({Title = "Whitelisted (" .. #_G.whitelisted_uuids .. ")", Content = formatUUIDList(_G.whitelisted_uuids)})
local newWhitelistInput = ""

WhitelistTab:CreateInput({
    Name = "Sword UUID",
    PlaceholderText = "Paste UUID here",
    RemoveTextAfterFocusLost = true,
    Flag = "WhitelistInput",
    Callback = function(Text)
        newWhitelistInput = Text
    end
})

WhitelistTab:CreateButton({
    Name = "Add UUID",
    Callback = function()
        if newWhitelistInput == "" then Rayfield:Notify({Title = "Error", Content = "Enter a UUID first!", Duration = 2}); return end
        if not table.find(_G.whitelisted_uuids, newWhitelistInput) then
            table.insert(_G.whitelisted_uuids, newWhitelistInput)
            _G.SaveComplexConfig()
            WhitelistParagraph:Set({Title = "Whitelisted (" .. #_G.whitelisted_uuids .. ")", Content = formatUUIDList(_G.whitelisted_uuids)})
            Rayfield:Notify({Title = "Added", Content = "UUID whitelisted!", Duration = 2})
        end
    end
})

WhitelistTab:CreateButton({
    Name = "Whitelist Equipped Sword",
    Callback = function()
        local char = player.Character
        local tool = char and char:FindFirstChildOfClass("Tool")
        if tool and string.len(tool.Name) > 15 then
            if not table.find(_G.whitelisted_uuids, tool.Name) then
                table.insert(_G.whitelisted_uuids, tool.Name)
                _G.SaveComplexConfig()
                WhitelistParagraph:Set({Title = "Whitelisted (" .. #_G.whitelisted_uuids .. ")", Content = formatUUIDList(_G.whitelisted_uuids)})
                Rayfield:Notify({Title = "Added", Content = "Equipped sword whitelisted!", Duration = 2})
            else
                Rayfield:Notify({Title = "Info", Content = "Sword already whitelisted!", Duration = 2})
            end
        else
            Rayfield:Notify({Title = "Error", Content = "No valid sword equipped!", Duration = 2})
        end
    end
})

WhitelistTab:CreateButton({
    Name = "Remove Last UUID",
    Callback = function()
        if #_G.whitelisted_uuids > 0 then
            table.remove(_G.whitelisted_uuids)
            _G.SaveComplexConfig()
            WhitelistParagraph:Set({Title = "Whitelisted (" .. #_G.whitelisted_uuids .. ")", Content = formatUUIDList(_G.whitelisted_uuids)})
            Rayfield:Notify({Title = "Removed", Content = "Last UUID removed!", Duration = 2})
        end
    end
})

WhitelistTab:CreateButton({
    Name = "Clear All",
    Callback = function()
        _G.whitelisted_uuids = {}
        _G.SaveComplexConfig()
        WhitelistParagraph:Set({Title = "Whitelisted (0)", Content = "None"})
        Rayfield:Notify({Title = "Cleared", Content = "All UUIDs cleared!", Duration = 2})
    end
})

-- ========================
-- TAB 4: ASCENDER
-- ========================
local AscenderTab = Window:CreateTab("⬆️ Ascender", 4483362458)
AscenderTab:CreateSection("Control")

AscenderTab:CreateToggle({
    Name = "Enable Auto Ascender",
    CurrentValue = false,
    Flag = "ToggleAscender",
    Callback = function(Value)
        _G.ascender_enabled = Value
    end
})

AscenderTab:CreateSection("Queue")

local QueueParagraph = AscenderTab:CreateParagraph({Title = "Queue (" .. #_G.ascender_queue .. ")", Content = formatUUIDList(_G.ascender_queue)})
local newQueueInput = ""

AscenderTab:CreateInput({
    Name = "Sword UUID for Queue",
    PlaceholderText = "Paste UUID here",
    RemoveTextAfterFocusLost = true,
    Flag = "QueueInput",
    Callback = function(Text)
        newQueueInput = Text
    end
})

AscenderTab:CreateButton({
    Name = "Add to Queue",
    Callback = function()
        if newQueueInput == "" then Rayfield:Notify({Title = "Error", Content = "Enter a UUID first!", Duration = 2}); return end
        if not table.find(_G.ascender_queue, newQueueInput) then
            table.insert(_G.ascender_queue, newQueueInput)
            _G.SaveComplexConfig()
            QueueParagraph:Set({Title = "Queue (" .. #_G.ascender_queue .. ")", Content = formatUUIDList(_G.ascender_queue)})
            Rayfield:Notify({Title = "Queued", Content = "Sword added to queue!", Duration = 2})
        end
    end
})

AscenderTab:CreateButton({
    Name = "Add Equipped Sword to Queue",
    Callback = function()
        local char = player.Character
        local tool = char and char:FindFirstChildOfClass("Tool")
        if tool and string.len(tool.Name) > 15 then
            if not table.find(_G.ascender_queue, tool.Name) then
                table.insert(_G.ascender_queue, tool.Name)
                _G.SaveComplexConfig()
                QueueParagraph:Set({Title = "Queue (" .. #_G.ascender_queue .. ")", Content = formatUUIDList(_G.ascender_queue)})
                Rayfield:Notify({Title = "Queued", Content = "Equipped sword added to queue!", Duration = 2})
            end
        else
            Rayfield:Notify({Title = "Error", Content = "No valid sword equipped!", Duration = 2})
        end
    end
})

AscenderTab:CreateButton({
    Name = "Clear Queue",
    Callback = function()
        _G.ascender_queue = {}
        _G.SaveComplexConfig()
        QueueParagraph:Set({Title = "Queue (0)", Content = "None"})
        Rayfield:Notify({Title = "Cleared", Content = "Queue cleared!", Duration = 2})
    end
})

AscenderTab:CreateSection("Target Criteria")

local allEnchantNames = getNames("Enchant1")

AscenderTab:CreateDropdown({
    Name = "Target Quality",
    Options = getNames("Quality"),
    CurrentOption = {(_G.ascender_criteria and _G.ascender_criteria.Quality) or "None"},
    MultipleOptions = false,
    Flag = "AscenderQuality",
    Callback = function(Options)
        if not _G.ascender_criteria then _G.ascender_criteria = {} end
        _G.ascender_criteria.Quality = Options[1]
        _G.SaveComplexConfig()
    end
})

AscenderTab:CreateDropdown({
    Name = "Target Rarity",
    Options = getNames("Rarity"),
    CurrentOption = {(_G.ascender_criteria and _G.ascender_criteria.Rarity) or "None"},
    MultipleOptions = false,
    Flag = "AscenderRarity",
    Callback = function(Options)
        if not _G.ascender_criteria then _G.ascender_criteria = {} end
        _G.ascender_criteria.Rarity = Options[1]
        _G.SaveComplexConfig()
    end
})

AscenderTab:CreateDropdown({
    Name = "Target Mold",
    Options = getNames("Mold"),
    CurrentOption = {(_G.ascender_criteria and _G.ascender_criteria.Mold) or "None"},
    MultipleOptions = false,
    Flag = "AscenderMold",
    Callback = function(Options)
        if not _G.ascender_criteria then _G.ascender_criteria = {} end
        _G.ascender_criteria.Mold = Options[1]
        _G.SaveComplexConfig()
    end
})

AscenderTab:CreateDropdown({
    Name = "Target Class",
    Options = getNames("Class"),
    CurrentOption = {(_G.ascender_criteria and _G.ascender_criteria.Class) or "None"},
    MultipleOptions = false,
    Flag = "AscenderClass",
    Callback = function(Options)
        if not _G.ascender_criteria then _G.ascender_criteria = {} end
        _G.ascender_criteria.Class = Options[1]
        _G.SaveComplexConfig()
    end
})

AscenderTab:CreateInput({
    Name = "Target Enchant 1 Level",
    PlaceholderText = "Min level (e.g. 5)",
    RemoveTextAfterFocusLost = false,
    Flag = "AscenderE1Level",
    Callback = function(Text)
        if not _G.ascender_criteria then _G.ascender_criteria = {} end
        _G.ascender_criteria.Enchant1Level = tonumber(Text) or 0
        _G.SaveComplexConfig()
    end
})

AscenderTab:CreateInput({
    Name = "Target Enchant 2 Level",
    PlaceholderText = "Min level (e.g. 5)",
    RemoveTextAfterFocusLost = false,
    Flag = "AscenderE2Level",
    Callback = function(Text)
        if not _G.ascender_criteria then _G.ascender_criteria = {} end
        _G.ascender_criteria.Enchant2Level = tonumber(Text) or 0
        _G.SaveComplexConfig()
    end
})

AscenderTab:CreateInput({
    Name = "Target Enchant 3 Level",
    PlaceholderText = "Min level (e.g. 5)",
    RemoveTextAfterFocusLost = false,
    Flag = "AscenderE3Level",
    Callback = function(Text)
        if not _G.ascender_criteria then _G.ascender_criteria = {} end
        _G.ascender_criteria.Enchant3Level = tonumber(Text) or 0
        _G.SaveComplexConfig()
    end
})

AscenderTab:CreateInput({
    Name = "Target Level",
    PlaceholderText = "Min sword level (e.g. 100)",
    RemoveTextAfterFocusLost = false,
    Flag = "AscenderLevel",
    Callback = function(Text)
        if not _G.ascender_criteria then _G.ascender_criteria = {} end
        _G.ascender_criteria.Level = tonumber(Text) or 0
        _G.SaveComplexConfig()
    end
})

-- ========================
-- TAB 5: WEBHOOK
-- ========================
local WebhookTab = Window:CreateTab("🔔 Webhook", 4483362458)
WebhookTab:CreateSection("Discord Webhook")

WebhookTab:CreateToggle({
    Name = "Enable Webhook",
    CurrentValue = false,
    Flag = "ToggleWebhook",
    Callback = function(Value)
        _G.webhook_enabled = Value
    end
})

WebhookTab:CreateInput({
    Name = "Webhook URL",
    PlaceholderText = "Paste URL Here",
    RemoveTextAfterFocusLost = false,
    Flag = "WebhookURL",
    Callback = function(Text)
        _G.webhook_url = Text
    end
})

-- ========================
-- TAB 6: SETTINGS
-- ========================
local SettingsTab = Window:CreateTab("⚙️ Settings", 4483362458)
SettingsTab:CreateSection("Performance")

SettingsTab:CreateToggle({
    Name = "Disable 3D Rendering",
    CurrentValue = true,
    Flag = "Toggle3D",
    Callback = function(Value)
        pcall(function() RunService:Set3dRenderingEnabled(not Value) end)
    end
})

SettingsTab:CreateSlider({
    Name = "FPS Cap",
    Range = {1, 60},
    Increment = 1,
    Suffix = " fps",
    CurrentValue = 3,
    Flag = "FPSCap",
    Callback = function(Value)
        pcall(function() setfpscap(Value) end)
    end
})

SettingsTab:CreateSection("Advanced")

SettingsTab:CreateSlider({
    Name = "Max Kill Time",
    Range = {1, 15},
    Increment = 1,
    Suffix = "s",
    CurrentValue = 5,
    Flag = "MaxKillTime",
    Callback = function(Value)
        SETTINGS.MAX_KILL_TIME = Value
    end
})

SettingsTab:CreateSlider({
    Name = "Blacklist Duration",
    Range = {5, 120},
    Increment = 5,
    Suffix = "s",
    CurrentValue = 30,
    Flag = "BlacklistDuration",
    Callback = function(Value)
        SETTINGS.BLACKLIST_DURATION = Value
    end
})

SettingsTab:CreateSlider({
    Name = "Spawn Grace Period",
    Range = {1, 15},
    Increment = 1,
    Suffix = "s",
    CurrentValue = 5,
    Flag = "SpawnGrace",
    Callback = function(Value)
        SETTINGS.SPAWN_GRACE_PERIOD = Value
    end
})

SettingsTab:CreateSection("Status")

local StatusParagraph = SettingsTab:CreateParagraph({Title = "Current Status", Content = "Idle"})

_G.StatusUpdateTask = task.spawn(function()
    while task.wait(1) do
        pcall(function()
            local lvl = PlayerStats:FindFirstChild("Level") and PlayerStats.Level.Value or "?"
            local money = PlayerStats:FindFirstChild("Money") and PlayerStats.Money.Value or "?"
            local elapsed = math.floor(tick() - sessionStartTime)
            local mins = math.floor(elapsed / 60)
            local secs = elapsed % 60
            
            StatusParagraph:Set({
                Title = "Status: " .. (_G.CurrentState or "Idle"),
                Content = "Level: " .. tostring(lvl) .. " | Money: " .. tostring(money) .. "\nSession: " .. mins .. "m " .. secs .. "s\nAreas: " .. (#_G.active_areas > 0 and table.concat(_G.active_areas, ", ") or "None")
            })
        end)
    end
end)

print("✅ SnowFlake AutoFarm (Standalone) loaded successfully!")
print("📁 Config saves to: " .. CONFIG_FOLDER .. "/")
