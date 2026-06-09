-- [[ ⚙️ CONFIGURATION - EDIT THESE IF RUNNING STANDALONE ]]
getgenv().ApiKey = getgenv().ApiKey or "your_api_key_here"
getgenv().script_key = getgenv().script_key or "your_license_here"

-- [[ RESOLVE KEYS ]]
local args = {...}
local C2_API_KEY = (args[1] and type(args[1]) == "string" and args[1] ~= "") or (typeof(ApiKey) == "string" and ApiKey ~= "your_api_key_here" and ApiKey) or ""
local LUARMOR_LICENSE = (args[2] and type(args[2]) == "string" and args[2] ~= "") or (typeof(script_key) == "string" and script_key ~= "your_license_here" and script_key) or ""

if not C2_API_KEY or C2_API_KEY == "" then
    warn("[!] Missing ApiKey! Please set ApiKey='...' before running the script.")
    return
end
if not LUARMOR_LICENSE or LUARMOR_LICENSE == "" then
    warn("[!] Missing script_key! Please set script_key='...' before running the script.")
    return
end

if LPH_OBFUSCATED == nil then
    getgenv()["LPH_NO_" .. "VIRTUALIZE"] = function(f) return f end
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
  disconnectIfConnected(_G.GraphicsStripperConnection1)
  disconnectIfConnected(_G.GraphicsStripperConnection2)
  disconnectIfConnected(_G.GraphicsStripperConnection3)

if _G.AntiAFKConnection then 
    if typeof(_G.AntiAFKConnection) == "thread" then task.cancel(_G.AntiAFKConnection) else _G.AntiAFKConnection:Disconnect() end
    _G.AntiAFKConnection = nil 
end
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
_G.target_priority = "Closest"

-- Sniper, Drop & Mass Recovery States
_G.autoDropEnabled = false
_G.fetchingGodRoll = false 
_G.activate_panel = false
_G.target_enchant_sets = { {"Ancient", "Fortune", "Insight"} } 
_G.whitelisted_uuids = {} 
_G.KeptSwords = {} -- The Live Ledger for Mass Recovery
_G.SpecialOverrides = {Enchant = {}, Mold = {}, Quality = {}, Rarity = {}, Class = {}}
_G.webhook_url = ""
_G.webhook_enabled = false

-- Ascender Configuration
_G.ascender_enabled = false
_G.ascender_queue = {}
_G.ascender_criteria = {}
_G.HandlingAscender = false

-- C2 Server Configuration
_G.C2_SERVER_URL = "wss://c2scripts.xyz/ws/c2/"

-- Area Rotation States
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
  
  local VirtualUser = game:GetService("VirtualUser")
  _G.AntiAFKConnection = game.Players.LocalPlayer.Idled:Connect(function()
      VirtualUser:Button2Down(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
      task.wait(1)
      VirtualUser:Button2Up(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
      print("[Anti-AFK] Blocked idle disconnect!")
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
              if v:IsA("Texture") or v:IsA("Decal") then
                  v:Destroy()
              elseif v:IsA("BasePart") and not (v.Parent and v.Parent:FindFirstChild("Humanoid")) then
                  if v.Material ~= Enum.Material.SmoothPlastic then v.Material = Enum.Material.SmoothPlastic end
                  if v.Reflectance ~= 0 then v.Reflectance = 0 end
                  v.CastShadow = false
              elseif v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Beam") then
                  v.Enabled = false
              end
          end

          for _, v in pairs(workspace:GetDescendants()) do
              stripGraphics(v)
          end
          
          workspace.Terrain.WaterWaveSize = 0
          workspace.Terrain.WaterWaveSpeed = 0
          workspace.Terrain.WaterReflectance = 0
          workspace.Terrain.WaterTransparency = 0
          
          if workspace:FindFirstChild("Swords") then _G.GraphicsStripperConnection1 = workspace.Swords.DescendantAdded:Connect(stripGraphics) end
          if workspace:FindFirstChild("Spawns") then _G.GraphicsStripperConnection2 = workspace.Spawns.DescendantAdded:Connect(stripGraphics) end
          if workspace:FindFirstChild("Mobs") then _G.GraphicsStripperConnection3 = workspace.Mobs.DescendantAdded:Connect(stripGraphics) end
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
        task.spawn(function()
            pcall(function() 
                remote:InvokeServer("Teleport In Base", "Return") 
                remote:InvokeServer("Teleport In Base", "Home")
            end)
        end)
        
        local waitBase = tick()
        while internalArea and tostring(internalArea.Value) ~= "0" and tick() - waitBase < 5 do
            if not _G.on and not _G.fetchingGodRoll and not _G.HandlingAscender then isTeleporting = false; return end
            if hrp then hrp.AssemblyLinearVelocity = Vector3.zero end
            task.wait(0.1)
        end
        if not _G.on and not _G.fetchingGodRoll and not _G.HandlingAscender then isTeleporting = false; return end
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
    
    if not _G.on and not _G.fetchingGodRoll and not _G.HandlingAscender then isTeleporting = false; return end
    DestroyCutscene() 
    
    -- [[ STEP 2: TELEPORT TO TARGET MAP ]]
    if tostring(areaNum) ~= "0" and tostring(areaNum) ~= "Base" and tostring(areaNum) ~= "Spawn" then
        print("[DEBUG] Teleporting from Base to Area:", areaNum)
        task.spawn(function() pcall(function() remote:InvokeServer("Teleport Area", tonumber(areaNum)) end) end)
        
        local waitArea = tick()
        while internalArea and tostring(internalArea.Value) ~= tostring(areaNum) and tick() - waitArea < 7 do
            if not _G.on and not _G.fetchingGodRoll and not _G.HandlingAscender then isTeleporting = false; return end
            if hrp then hrp.AssemblyLinearVelocity = Vector3.zero end
            task.wait(0.1)
        end
        if not _G.on and not _G.fetchingGodRoll and not _G.HandlingAscender then isTeleporting = false; return end
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
                
                if _G.target_priority == "Closest" then
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
    _G.InvRemovedConnection = invFolder.ChildRemoved:Connect(function() _G.InventoryDirty = true end)
    
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
        warn("💀 Respawn detected! Hopping zones to unlock interactions...")
        if not isTeleporting then
            isTeleporting = true
            local targetArea = (#_G.active_areas > 0 and _G.active_areas[1]) or currentArea
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

  -- Target Updater Loop (Runs 2 times a second instead of 60 to save CPU)
  task.spawn(function()
      while task.wait(0.5) do
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

-- Server Progression array for Bank
local BankCapacityPerLevel = {
    [1] = 6, [2] = 10, [3] = 12, [4] = 14, [5] = 16,
    [6] = 18, [7] = 20, [8] = 22, [9] = 24, [10] = 26,
    [11] = 28, [12] = 30, [13] = 32, [14] = 34, [15] = 36
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
        
        -- Float directly above the sword to prevent body-blocking or touching neighboring swords!
        local pivot = physicalSword:GetPivot()
        hrp.CFrame = pivot * CFrame.new(0, 15, 0) 
        
        pcall(function()
            if firetouchinterest then
                local touchPart = physicalSword:IsA("BasePart") and physicalSword or physicalSword:FindFirstChildWhichIsA("BasePart", true)
                if touchPart then
                    firetouchinterest(hrp, touchPart, 0)
                    task.wait(0.05)
                    firetouchinterest(hrp, touchPart, 1)
                end
            end
        end)
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
        
        print("[AutoAscender] 🧹 Found " .. #extraSwords .. " extra/stuck sword(s) in inventory. Strictly depositing to Bank...")
        local AscenderFunc = ReplicatedStorage:WaitForChild("Paper"):WaitForChild("Remotes"):WaitForChild("__remotefunction")
        local AscenderEvent = ReplicatedStorage:WaitForChild("Paper"):WaitForChild("Remotes"):WaitForChild("__remoteevent")
        task.spawn(function() pcall(function() AscenderFunc:InvokeServer("Teleport In Base", "Bank") end) end)
        task.wait(0.6) -- Strict wait to ensure character is on the bank
        
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
    _G.CurrentState = "Managing Ascender..."

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
            print("[AutoAscender] Picking up from Ascender...")
            
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
                    if _G.C2_WS then
                        _G.C2_WS:Send(game:GetService("HttpService"):JSONEncode({
                            action = "update_status", username = player.Name, api_key = C2_API_KEY,
                            payload = { whitelisted_uuids = _G.whitelisted_uuids }
                        }))
                    end
                end
            else
                print("[AutoAscender] Depositing to Bank...")
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
            
            -- Try to process next sword if available
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
                
                if _G.C2_WS then
                    _G.C2_WS:Send(game:GetService("HttpService"):JSONEncode({
                        action = "update_status", username = player.Name, api_key = C2_API_KEY,
                        payload = { ascender_queue = _G.ascender_queue }
                    }))
                end
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
            
            if _G.C2_WS then
                _G.C2_WS:Send(game:GetService("HttpService"):JSONEncode({
                    action = "update_status", username = player.Name, api_key = C2_API_KEY,
                    payload = { ascender_queue = _G.ascender_queue }
                }))
            end
        end
    end)
    if not success then warn("[C2 Ascender Error] " .. tostring(err)) end

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

local DetermineState = LPH_NO_VIRTUALIZE(function()
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
                game:GetService("ReplicatedStorage"):WaitForChild("Paper"):WaitForChild("Remotes"):WaitForChild("__remoteevent"):FireServer("Set Ascender Mode", targetMode)
            end
        end
    end)

    if not character or not character.Parent or not humanoid or humanoid.Health <= 0 then return "Dead" end
    if _G.fetchingGodRoll then return "Sniping" end
    if _G.HandlingAscender then return "Ascending" end
    
    -- Priority 1.5: Auto Ascender Check (Elevated above Disabled check so it works independently)
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

    -- Priority 1: Check Area Sync Signal
    local actualArea = currentArea
    local pStats = ReplicatedStorage:FindFirstChild("Stats")
    if pStats then
        local myStats = pStats:FindFirstChild(tostring(player.Name))
        local internalArea = myStats and myStats:FindFirstChild("CurrentArea")
        if internalArea then actualArea = internalArea.Value end
    end
    
    if tostring(actualArea) == "Base" or tostring(actualArea) == "Spawn" then actualArea = 0 end
    local actualNum, wantedNum = tonumber(actualArea) or 0, tonumber(currentArea)
    if (not wantedNum or wantedNum == 0) and #_G.active_areas > 0 then 
        wantedNum = _G.active_areas[1]
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
    if tick() - lastMissingCheck > 1 then
        lastMissingCheck = tick()
        StateData.MissingSwords = CheckMissingSwords()
    end
    if #StateData.MissingSwords > 0 then return "Recovering" end

    -- Priority 3: Smart Equip Check
    local currentTool = character:FindFirstChildOfClass("Tool")
    local bestSwordToEquip = nil
    
    -- 1. Check for whitelisted sword in inventory
    if PlayerStats and PlayerStats:FindFirstChild("Swords") then
        for _, sword in pairs(PlayerStats.Swords:GetChildren()) do
            if sword:IsA("Folder") and table.find(_G.whitelisted_uuids, sword.Name) and not isSwordLockedInAnyMachine(sword.Name) then
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
        -- NO sword found at all! Hover safely and wait.
        if _G.on then
            _G.CurrentState = "No Valid Sword!"
            if hrp and hrp.Position.Y < 300 then
                pcall(function() hrp.CFrame = hrp.CFrame + Vector3.new(0, 300 - hrp.Position.Y + 50, 0) end)
            end
            
            pcall(function()
                if _G.C2_WS then
                    _G.C2_WS:Send(game:GetService("HttpService"):JSONEncode({
                        type = "notification",
                        message = "⚠️ Account " .. player.Name .. " hovering safely: No whitelisted/equipped sword found."
                    }))
                end
            end)
            return "No Valid Sword!"
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
local lastSwing = 0

_G.UltimateFarmConnection = RunService.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function()
    -- Ask the Brain what we should be doing right now
    local newState, extraData = DetermineState()
    BotState = newState

    -- Handle lockouts and physical resets
    if BotState == "Disabled" then _G.CurrentState = "Idle"; return end
    if BotState == "Dead" then _G.CurrentState = "Dead/Respawning..."; return end
    if BotState == "Sniping" or BotState == "Teleporting" or BotState == "Ascending" then return end

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
            
            if not StateData.LastTouch or tick() - StateData.LastTouch > 0.2 then
                StateData.LastTouch = tick()
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


        if currentTarget:FindFirstChild("HumanoidRootPart") then
            hrp.CFrame = CFrame.lookAt(currentTarget.HumanoidRootPart.Position + Vector3.new(0, SETTINGS.OFFSET_HEIGHT, 0), currentTarget.HumanoidRootPart.Position)
            if tick() - lastSwing > 0.05 then
                lastSwing = tick()
                local currentTool = character:FindFirstChildOfClass("Tool")
                if currentTool then currentTool:Activate() end
            end
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
                        
                        -- Clean up websocket to prevent ghost clients on Dashboard
                        game.Players.PlayerRemoving:Connect(function(plr)
                            if plr == game.Players.LocalPlayer then
                                if _G.C2_WS then pcall(function() _G.C2_WS:Close() end) end
                            end
                        end)
                        
                        if game.Players.LocalPlayer.OnTeleport then
                            game.Players.LocalPlayer.OnTeleport:Connect(function()
                                if _G.C2_WS then pcall(function() _G.C2_WS:Close() end) end
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
        
        local categoryData = populateData[moduleCat]
        if not categoryData then return tostring(id) end
        return categoryData[id] and categoryData[id].Name or tostring(id)
    end

    local function getAscenderPayload()
        local payload = { hasSword = false, mode = "None", stats = {} }
        pcall(function()
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

    _G.InventoryDirty = true
    
    task.spawn(function()
        local invFolder = PlayerStats:WaitForChild("Swords", 5)
        if invFolder then
            invFolder.DescendantAdded:Connect(function() _G.InventoryDirty = true end)
            invFolder.DescendantRemoving:Connect(function() _G.InventoryDirty = true end)
        end
        local bankFolder = PlayerStats:WaitForChild("Bank", 5)
        if bankFolder then
            bankFolder.DescendantAdded:Connect(function() _G.InventoryDirty = true end)
            bankFolder.DescendantRemoving:Connect(function() _G.InventoryDirty = true end)
        end
    end)

    local function getBackpackPayload()
        local payload = {}
        pcall(function()
            -- Add Inventory Swords
            local invFolder = PlayerStats:FindFirstChild("Swords")
            if invFolder then
                for _, sword in pairs(invFolder:GetChildren()) do
                    if sword:IsA("Folder") then
                        local entry = { id = sword.Name, inBank = false }
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
            
            -- Add Bank Swords
            local bankFolder = PlayerStats:FindFirstChild("Bank")
            if bankFolder then
                for _, sword in pairs(bankFolder:GetChildren()) do
                    if sword:IsA("Folder") then
                        local entry = { id = sword.Name, inBank = true }
                        entry.BankSlot = sword:GetAttribute("BankSlot") or 0
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
            print("[C2 DEBUG] Received Payload Command:", data.command)

            if data.command == "toggleAscender" then
                _G.ascender_enabled = data.payload
                print("C2 Command: AutoAscender forcefully set to", _G.ascender_enabled)
                
            elseif data.command == "setAscenderQueue" then
                _G.ascender_queue = data.payload or {}
                print("C2 Command: Updated Ascender Queue")
                
            elseif data.command == "setAscenderCriteria" then
                _G.ascender_criteria = data.payload or {}
                print("C2 Command: Updated Ascender Criteria")

            elseif data.command == "toggleFarm" then
                _G.on = not _G.on
                print("C2 Command: AutoFarm toggled to", _G.on)
                
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

            elseif data.command == "teleportHome" then
                print("C2 Command: Teleporting Home/Return!")
                task.spawn(function()
                    pcall(function() hrp.CFrame = CFrame.new(hrp.Position.X, hrp.Position.Y + 500, hrp.Position.Z) end)
                    task.wait(0.5)
                    pcall(function()
                        local remote = game:GetService("ReplicatedStorage"):WaitForChild("Paper", 9e9):WaitForChild("Remotes", 9e9):WaitForChild("__remotefunction", 9e9)
                        -- Try both arguments! The server will accept the correct one and safely reject the wrong one.
                        task.spawn(function()
                            pcall(function()
                                remote:InvokeServer("Teleport In Base", "Return")
                                remote:InvokeServer("Teleport In Base", "Home")
                            end)
                        end)
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

            elseif data.command == "dropSword" or data.command == "dropItem" then
                local swordUUID = data.payload
                if type(data.payload) == "table" and data.payload.itemId then
                    swordUUID = data.payload.itemId
                end
                if swordUUID then
                    local DropRemoteEvent = game:GetService("ReplicatedStorage"):WaitForChild("Paper"):WaitForChild("Remotes"):WaitForChild("__remoteevent")
                    DropRemoteEvent:FireServer("Drop Sword", swordUUID)
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
                
            elseif data.command == "syncConfig" then
                pcall(function()
                    local parsedData = data.payload
                    if parsedData then
                        local ts = parsedData.target_enchant_sets
                        if ts then _G.target_enchant_sets = ts end
                        
                        local wu = parsedData.whitelisted_uuids
                        if wu then
                            local clean_wu = {}
                            for _, id in ipairs(wu) do
                                if type(id) == "string" then
                                    table.insert(clean_wu, id:match("^%s*(.-)%s*$"))
                                else
                                    table.insert(clean_wu, id)
                                end
                            end
                            _G.whitelisted_uuids = clean_wu
                        end
                        
                        local fa = parsedData.active_areas or parsedData.FarmAreas
                        if fa then 
                            _G.active_areas = fa 
                            if #_G.active_areas > 0 and not table.find(_G.active_areas, tonumber(currentArea)) then
                                currentArea = _G.active_areas[1]
                                if _G.on and not isTeleporting then
                                    isTeleporting = true
                                    task.spawn(function() TeleportSequence(currentArea) end)
                                end
                            end
                        end
                        if parsedData.SpecialOverrides then _G.SpecialOverrides = parsedData.SpecialOverrides end
                        local to = parsedData.target_priority
                        if to then _G.target_priority = to end
                        
                        if parsedData.offset_height ~= nil then SETTINGS.OFFSET_HEIGHT = tonumber(parsedData.offset_height) or 7 end
                        if parsedData.wait_altitude ~= nil then 
                            SETTINGS.WAIT_ALTITUDE = tonumber(parsedData.wait_altitude) or 15 
                            SETTINGS.RETREAT_ALTITUDE = tonumber(parsedData.wait_altitude) or 15 
                        end
                        
                        if parsedData.ascender_enabled ~= nil then _G.ascender_enabled = parsedData.ascender_enabled end
                        
                        local wurl = parsedData.webhook_url
                        if wurl then _G.webhook_url = wurl end
                        
                        local wen = parsedData.webhook_enabled
                        if wen ~= nil then _G.webhook_enabled = wen end
                        
                        if parsedData.SpecialOverrides then _G.SpecialOverrides = parsedData.SpecialOverrides end
                        if parsedData.Settings then for k,v in pairs(parsedData.Settings) do SETTINGS[k] = v end end
                        
                        -- Toggle logic (if dashboard sends these specifically inside syncConfig)
                        if parsedData.activate_panel ~= nil then _G.activate_panel = parsedData.activate_panel end
                        if parsedData.farm_enabled ~= nil then 
                            if _G.on ~= parsedData.farm_enabled then
                                _G.on = parsedData.farm_enabled
                                if not _G.on then 
                                    ResetPhysics() 
                                else
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
                                end
                            end
                        end
                        if parsedData.snipe_enabled ~= nil then _G.autoDropEnabled = parsedData.snipe_enabled end
                        if parsedData.ascender_enabled ~= nil then _G.ascender_enabled = parsedData.ascender_enabled end
                        if parsedData.ascender_queue then _G.ascender_queue = parsedData.ascender_queue end
                        if parsedData.ascender_criteria then _G.ascender_criteria = parsedData.ascender_criteria end
                        print("C2 Command: Configuration Synced remotely from Website!")
                    end
                end)
                
            elseif data.command == "updateWishlist" then
                if typeof(data.payload) == "table" then
                    _G.target_enchant_sets = data.payload
                    print("C2 Command: Wishlist updated. Size: " .. tostring(#_G.target_enchant_sets))
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
                            local myBankLevel = PlayerStats:FindFirstChild("BankLevel") and PlayerStats.BankLevel.Value or 0
                            local ascenderData = getAscenderPayload()
                            
                            local payloadTable = {
                                Status = _G.CurrentState or "Idle",
                                Level = myLevel,
                                Money = myMoney,
                                BankLevel = myBankLevel,
                                Quality = ascenderData.stats.Quality or "Standard",
                                Rarity = ascenderData.stats.Rarity or "Common",
                                Mold = ascenderData.stats.Mold or "Basic",
                                BotClass = ascenderData.stats.Class or "None",
                                AscenderEnchant1 = ascenderData.stats.Enchant1 or "None",
                                AscenderEnchant2 = ascenderData.stats.Enchant2 or "None",
                                AscenderEnchant3 = ascenderData.stats.Enchant3 or "None",
                                AscenderMode = ascenderData.mode or "None",
                                TargetEnchantSets = (function()
                                    local formattedSets = {}
                                    local setsToUse = (#_G.target_enchant_sets > 0 and _G.target_enchant_sets) or {{"Ancient", "Fortune", "Insight"}}
                                    for _, set in ipairs(setsToUse) do
                                        if type(set) == "string" then
                                            table.insert(formattedSets, set)
                                        elseif type(set) == "table" then
                                            table.insert(formattedSets, table.concat(set, " + "))
                                        end
                                    end
                                    return formattedSets
                                end)(),
                                target_enchant_sets = _G.target_enchant_sets,
                                whitelisted_uuids = _G.whitelisted_uuids or {},
                                farm_enabled = _G.on,
                                snipe_enabled = _G.autoDropEnabled,
                                activate_panel = _G.activate_panel,
                                active_areas = _G.active_areas,
                                target_priority = _G.target_priority,
                                ascender_enabled = _G.ascender_enabled,
                                ascender_queue = _G.ascender_queue,
                                ascender_criteria = _G.ascender_criteria
                            }
                            
                            if _G.InventoryDirty then
                                payloadTable.BackpackItems = getBackpackPayload()
                                _G.InventoryDirty = false
                            end
                            
                            local success, err = pcall(function()
                                print("[C2 DEBUG] Sending Payload Update: Status & Data")
                                _G.C2_WS:Send(HttpService:JSONEncode({
                                    action = "update_status",
                                    username = player.Name,
                                    api_key = C2_API_KEY,
                                    payload = payloadTable
                                }))
                            end)
                            if not success then
                                warn("[C2] Silent disconnect detected (Send failed):", tostring(err))
                                _G.C2_WS = nil -- Force reconnection loop to trigger
                            end
                        end
                    end)
                end
            end
        end)
    end)
    
    _G.PeriodicLogTask = task.spawn(function()
        local lastLevel = -1
        while task.wait(60) do
            if _G.C2_WS then
                local pStats = ReplicatedStorage:FindFirstChild("Stats")
                local myStats = pStats and pStats:FindFirstChild(tostring(player.Name))
                if myStats then
                    local currentLevel = myStats:FindFirstChild("Level") and myStats.Level.Value or 0
                    
                    if lastLevel ~= -1 then
                        local levelDiff = currentLevel - lastLevel
                        
                        if levelDiff > 0 then
                            local messageStr = "Leveled up " .. levelDiff .. " times (Now Lvl " .. currentLevel .. ")"
                            pcall(function()
                                _G.C2_WS:Send(game:GetService("HttpService"):JSONEncode({
                                    action = "log",
                                    username = player.Name,
                                    event_type = "Leveling",
                                    message = "dY> " .. messageStr
                                }))
                            end)
                        end
                    end
                    lastLevel = currentLevel
                end
            end
        end
    end)

    
    _G.C2ConnectionTask = task.spawn(function()
        maintainC2Connection()
    end)
end)


