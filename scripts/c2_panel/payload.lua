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
_G.AvoidArchers = false 
_G.SavedSwordName = nil 
_G.CurrentState = "Idle"

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
_G.C2_SERVER_URL = "wss://snowflake-enslave-rigging.ngrok-free.dev" -- Change this to your VPS/ngrok IP when sharing!

-- Area Rotation States
_G.FarmAreas = {} 
local activeAreaRotationIds = {}

local StagedEnchant1, StagedEnchant2, StagedEnchant3 = "None", "None", "None"
local ManualWhitelistInput = ""
local SaveFileName = "UltimateFarm_" .. player.Name .. "_" .. player.UserId .. ".json"

local currentArea = 7
local isTeleporting = false
local lastTeleportEnd = 0 
local lastArcherTime = 0
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
if _G.UltimateFarmConnection then _G.UltimateFarmConnection:Disconnect() end
if _G.StatsConnection then task.cancel(_G.StatsConnection) end
if _G.AntiAFKConnection then task.cancel(_G.AntiAFKConnection) end
if _G.InventorySweeperConnection then task.cancel(_G.InventorySweeperConnection) end
if _G.CharRespawnConnection then _G.CharRespawnConnection:Disconnect() end
  if _G.SwordAddedConnection then _G.SwordAddedConnection:Disconnect() end
  if _G.InvAddedConnection then _G.InvAddedConnection:Disconnect() end
  if _G.SellingAddedConnection then _G.SellingAddedConnection:Disconnect() end
_G.UltimateFarmConnection = nil
isTeleporting = false
_G.fetchingGodRoll = false

if game.CoreGui:FindFirstChild("Rayfield") then
    game.CoreGui.Rayfield:Destroy()
end
ResetPhysics()

-- [[ 4. MODULES & REMOTES SETUP ]]
local Tables = ReplicatedStorage:WaitForChild("Tables")
local DropRemote = ReplicatedStorage:WaitForChild("Paper"):WaitForChild("Remotes"):WaitForChild("__remoteevent")

local SwordModules = {
    Enchant1 = require(Tables.Enchant), Enchant2 = require(Tables.Enchant), Enchant3 = require(Tables.Enchant),
    Mold = require(Tables.Mold), Quality = require(Tables.Quality), Rarity = require(Tables.Rarity), Class = require(Tables.Class)
}

local AreasModule = require(Tables.Areas)
local AreaNamesList = {}
local AreaMap = {} 
for id, data in pairs(AreasModule) do
    if id ~= 0 then 
        local req = data.LevelReq or 0
        local str = "[" .. tostring(id) .. "] " .. data.Name .. " (Lvl " .. req .. ")"
        table.insert(AreaNamesList, str)
        AreaMap[str] = id
    end
end
table.sort(AreaNamesList, function(a, b) return AreaMap[a] < AreaMap[b] end)

local function ExtractNames(module)
    local list = {}
    for _, data in pairs(module) do
        if type(data) == "table" and data.Name then table.insert(list, data.Name) end
    end
    table.sort(list)
    return list
end

local EnchantNamesList = ExtractNames(SwordModules.Enchant1)
local MoldNamesList = ExtractNames(SwordModules.Mold)
local QualityNamesList = ExtractNames(SwordModules.Quality)
local RarityNamesList = ExtractNames(SwordModules.Rarity)
local ClassNamesList = ExtractNames(SwordModules.Class)

-- [[ 5. ROBUST LEADERSTATS INITIALIZATION ]]
local sessionStartTime = tick()
local initialLevel, initialMoney = 0, 0

local function GetStatValue(statNameOptions)
    local ls = player:FindFirstChild("leaderstats")
    if not ls then return 0 end
    for _, name in pairs(statNameOptions) do
        local stat = ls:FindFirstChild(name)
        if stat then
            local val = tonumber(stat.Value)
            if val then return val end
        end
    end
    return 0
end

pcall(function()
    initialLevel = GetStatValue({"Level", "Lvl", "Levels"})
    initialMoney = GetStatValue({"Money", "Cash", "Coins", "Gold"})
end)

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
            if hrp then hrp.AssemblyLinearVelocity = Vector3.zero end
            task.wait(0.1)
        end
        print("[DEBUG] Arrived in Base.")
        task.wait(1)
    else
        print("[DEBUG] Already in Base.")
    end
    
    if not _G.on and not _G.fetchingGodRoll then isTeleporting = false return end 
    DestroyCutscene() 
    
    -- [[ STEP 2: TELEPORT TO TARGET MAP ]]
    if tostring(areaNum) ~= "0" and tostring(areaNum) ~= "Base" and tostring(areaNum) ~= "Spawn" then
        print("[DEBUG] Teleporting from Base to Area:", areaNum)
        pcall(function() remote:InvokeServer("Teleport Area", tonumber(areaNum)) end)
        
        local waitArea = tick()
        while internalArea and tostring(internalArea.Value) ~= tostring(areaNum) and tick() - waitArea < 7 do
            if hrp then hrp.AssemblyLinearVelocity = Vector3.zero end
            task.wait(0.1)
        end
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

    if isAtSpawn and areaToReturnTo ~= 0 then 
        TeleportSequence(areaToReturnTo) 
    end
    
    if not _G.on then
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
local function GetClosestTarget()
    local closest, shortestDist, now = nil, math.huge, tick()
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
                if dist < shortestDist then closest = v; shortestDist = dist end
            end
        end
    end
    
    if validNpcCount < SETTINGS.MIN_NPCS_TO_STAY then
        return nil
    end
    
    return closest
end

-- [[ 8. RAYFIELD GUI SETUP ]]
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local Window = Rayfield:CreateWindow({Name = "Ultimate Area Farm + Sniping", LoadingTitle = "Injecting Modules...", LoadingSubtitle = "Mass Recovery Active", Theme = "Default", ConfigurationSaving = { Enabled = false }, KeySystem = false})

local CombatTab = Window:CreateTab("⚔️ Combat")
local WhitelistTab = Window:CreateTab("🛡️ Whitelist")
local SniperTab = Window:CreateTab("🎯 Sniper")
local ConfigTab = Window:CreateTab("⚙️ Settings")

local WhitelistRemoveDrop, WishlistRemoveDrop, AreaRotationDrop, WebhookInput, WebhookToggle 
local SpecEnchantDrop, SpecMoldDrop, SpecQualityDrop, SpecRarityDrop, SpecClassDrop
local OffsetSlider, WaitSlider, TTKSlider, HopSlider, DensitySlider
local selectedUUIDToRemove, selectedSetToRemove = "", ""

CombatTab:CreateToggle({Name = "Enable Auto-Farm", CurrentValue = false, Flag = "FarmToggle", Callback = function(Value)
       _G.on = Value
       if _G.on then
           if #activeAreaRotationIds > 0 then
               local actualArea = currentArea
               local pStats = ReplicatedStorage:FindFirstChild("Stats")
               if pStats then
                   local myStats = pStats:FindFirstChild(tostring(player.Name))
                   local internalArea = myStats and myStats:FindFirstChild("CurrentArea")
                   if internalArea then actualArea = internalArea.Value end
               end
               if not table.find(activeAreaRotationIds, actualArea) and not isTeleporting then
                   isTeleporting = true
                   task.spawn(function() TeleportSequence(activeAreaRotationIds[1]) end)
               end
           end
       else ResetPhysics() end
   end,
})

CombatTab:CreateSection("🗺️ Map Rotation")
AreaRotationDrop = CombatTab:CreateDropdown({Name = "Select Farming Areas", Options = AreaNamesList, CurrentOption = {}, MultipleOptions = true, Callback = function(Options)
        _G.FarmAreas = Options; activeAreaRotationIds = {}
        for _, opt in ipairs(Options) do if AreaMap[opt] then table.insert(activeAreaRotationIds, AreaMap[opt]) end end
        table.sort(activeAreaRotationIds)
    end,
})

local StatusLabel = CombatTab:CreateParagraph({Title = "🤖 Bot Status", Content = "Initializing..."})

CombatTab:CreateSection("⚔️ Combat Controls")
CombatTab:CreateToggle({Name = "Avoid Archers", CurrentValue = false, Flag = "ArcherToggle", Callback = function(Value) _G.AvoidArchers = Value end})
CombatTab:CreateButton({Name = "Emergency Reset Physics", Callback = function() ResetPhysics(); isTeleporting = false end})

local StatsLabel = CombatTab:CreateParagraph({Title = "📊 Live Statistics", Content = "Connecting to Server Data..."})

WhitelistTab:CreateToggle({Name = "Enable Auto-Drop & Sniping", CurrentValue = false, Callback = function(v) 
    _G.autoDropEnabled = v
    if v then 
        pcall(function()
            local pStats = ReplicatedStorage:FindFirstChild("Stats"):FindFirstChild(tostring(player.Name))
            for _, f in pairs(pStats:FindFirstChild("Swords"):GetChildren()) do evaluateInventorySword(f) end 
        end)
    end 
end})

WhitelistTab:CreateSection("🔒 Protect Items")
local WhitelistLabel = WhitelistTab:CreateParagraph({Title = "Current Whitelisted UUIDs", Content = "None"})

local function UpdateWhitelistDisplay()
    local str = #_G.WhitelistedSwords > 0 and table.concat(_G.WhitelistedSwords, "\n") or "None"
    WhitelistLabel:Set({Title = "Current Whitelisted UUIDs", Content = str})
    local dropList = #_G.WhitelistedSwords > 0 and _G.WhitelistedSwords or {"None"}
    if WhitelistRemoveDrop then WhitelistRemoveDrop:Refresh(dropList, true) end
end

WhitelistTab:CreateButton({Name = "🛡️ Whitelist Equipped Weapon", Callback = function()
    local tool = character:FindFirstChildOfClass("Tool")
    if tool then
        if not table.find(_G.WhitelistedSwords, tool.Name) then table.insert(_G.WhitelistedSwords, tool.Name); UpdateWhitelistDisplay(); Rayfield:Notify({Title = "Whitelisted!", Content = "Saved your equipped weapon.", Duration = 3}) end
    else Rayfield:Notify({Title = "Error", Content = "Please equip a weapon first!", Duration = 3}) end
end})

WhitelistTab:CreateInput({Name = "Manual UUID Input", PlaceholderText = "Paste UUID Here", RemoveTextAfterFocusLost = false, Callback = function(Text) ManualWhitelistInput = Text end})
WhitelistTab:CreateButton({Name = "➕ Add UUID Manually", Callback = function()
    if ManualWhitelistInput ~= "" and not table.find(_G.WhitelistedSwords, ManualWhitelistInput) then table.insert(_G.WhitelistedSwords, ManualWhitelistInput); UpdateWhitelistDisplay() end
end})

WhitelistRemoveDrop = WhitelistTab:CreateDropdown({Name = "Select UUID to Remove", Options = {"None"}, CurrentOption = {"None"}, MultipleOptions = false, Callback = function(Opt) selectedUUIDToRemove = Opt[1] end})
WhitelistTab:CreateButton({Name = "➖ Remove Selected UUID", Callback = function()
    local idx = table.find(_G.WhitelistedSwords, selectedUUIDToRemove)
    if idx then 
        table.remove(_G.WhitelistedSwords, idx)
        selectedUUIDToRemove = "" 
        UpdateWhitelistDisplay()
        Rayfield:Notify({Title = "Removed", Content = "UUID removed from whitelist.", Duration = 2}) 
    end
end})
WhitelistTab:CreateButton({Name = "🗑️ Clear Entire Whitelist", Callback = function() _G.WhitelistedSwords = {}; UpdateWhitelistDisplay() end})

local CurrentSetsLabel = SniperTab:CreateParagraph({Title = "📋 Active Wishlist Sets", Content = "None"})

local function UpdateSetsDisplay()
    if #_G.ActiveTargetSets == 0 then 
        CurrentSetsLabel:Set({Title = "📋 Active Wishlist Sets", Content = "None"}); if WishlistRemoveDrop then WishlistRemoveDrop:Refresh({"None"}, true) end; return 
    end
    local str = ""; local setStrings = {}
    for i, set in ipairs(_G.ActiveTargetSets) do 
        local text = "Set " .. i .. ": " .. table.concat(set, " + ")
        str = str .. text .. "\n"; table.insert(setStrings, text)
    end
    CurrentSetsLabel:Set({Title = "📋 Active Wishlist Sets", Content = str})
    if WishlistRemoveDrop then WishlistRemoveDrop:Refresh(setStrings, true) end
end

SniperTab:CreateSection("🌟 Universal Special Overrides")
SpecEnchantDrop = SniperTab:CreateDropdown({Name = "Keep Specific Enchants", Options = EnchantNamesList, CurrentOption = {}, MultipleOptions = true, Callback = function(Opt) _G.SpecialOverrides.Enchant = Opt end})
SpecMoldDrop = SniperTab:CreateDropdown({Name = "Keep Specific Molds", Options = MoldNamesList, CurrentOption = {}, MultipleOptions = true, Callback = function(Opt) _G.SpecialOverrides.Mold = Opt end})
SpecQualityDrop = SniperTab:CreateDropdown({Name = "Keep Specific Qualities", Options = QualityNamesList, CurrentOption = {}, MultipleOptions = true, Callback = function(Opt) _G.SpecialOverrides.Quality = Opt end})
SpecRarityDrop = SniperTab:CreateDropdown({Name = "Keep Specific Rarities", Options = RarityNamesList, CurrentOption = {}, MultipleOptions = true, Callback = function(Opt) _G.SpecialOverrides.Rarity = Opt end})
SpecClassDrop = SniperTab:CreateDropdown({Name = "Keep Specific Classes", Options = ClassNamesList, CurrentOption = {}, MultipleOptions = true, Callback = function(Opt) _G.SpecialOverrides.Class = Opt end})

SniperTab:CreateSection("🎯 God Roll Wishlist Sets")
local StagedEnchantDropdowns = {"None", "None", "None"}; local StagedList = {"None"}
for _, v in ipairs(EnchantNamesList) do table.insert(StagedList, v) end

SniperTab:CreateDropdown({Name = "Enchant 1", Options = StagedList, CurrentOption = {"None"}, MultipleOptions = false, Callback = function(Opt) StagedEnchantDropdowns[1] = Opt[1] end})
SniperTab:CreateDropdown({Name = "Enchant 2", Options = StagedList, CurrentOption = {"None"}, MultipleOptions = false, Callback = function(Opt) StagedEnchantDropdowns[2] = Opt[1] end})
SniperTab:CreateDropdown({Name = "Enchant 3", Options = StagedList, CurrentOption = {"None"}, MultipleOptions = false, Callback = function(Opt) StagedEnchantDropdowns[3] = Opt[1] end})
SniperTab:CreateButton({Name = "➕ Add Combination to Wishlist", Callback = function()
    local nSet = {}
    if StagedEnchantDropdowns[1] ~= "None" then table.insert(nSet, StagedEnchantDropdowns[1]) end
    if StagedEnchantDropdowns[2] ~= "None" then table.insert(nSet, StagedEnchantDropdowns[2]) end
    if StagedEnchantDropdowns[3] ~= "None" then table.insert(nSet, StagedEnchantDropdowns[3]) end
    if #nSet > 0 then table.insert(_G.ActiveTargetSets, nSet); UpdateSetsDisplay() end
end})

WishlistRemoveDrop = SniperTab:CreateDropdown({Name = "Select Set to Remove", Options = {"None"}, CurrentOption = {"None"}, MultipleOptions = false, Callback = function(Opt) selectedSetToRemove = Opt[1] end})
SniperTab:CreateButton({Name = "➖ Remove Selected Set", Callback = function()
    local match = string.match(selectedSetToRemove, "Set (%d+):")
    if match then
        local idx = tonumber(match)
        if _G.ActiveTargetSets[idx] then 
            table.remove(_G.ActiveTargetSets, idx)
            selectedSetToRemove = "" 
            UpdateSetsDisplay()
            Rayfield:Notify({Title = "Removed", Content = "Set removed from wishlist.", Duration = 2}) 
        end
    end
end})
SniperTab:CreateButton({Name = "🗑️ Clear Entire Wishlist", Callback = function() _G.ActiveTargetSets = {}; UpdateSetsDisplay() end})

ConfigTab:CreateSection("💾 Profile Saving")
ConfigTab:CreateButton({Name = "💾 Sync & Save to Website", Callback = function()
    local data = {TargetSets = _G.ActiveTargetSets, WhitelistedSwords = _G.WhitelistedSwords, SpecialOverrides = _G.SpecialOverrides, WebhookURL = _G.WebhookURL, WebhookEnabled = _G.WebhookEnabled, FarmAreas = _G.FarmAreas, Settings = SETTINGS}
    pcall(function()
        if _G.C2_WS then
            _G.C2_WS:Send(HttpService:JSONEncode({
                type = "save_config_to_server",
                payload = data
            }))
            Rayfield:Notify({Title = "Saved!", Content = "Profile synced to C2 Server database.", Duration = 3})
        else
            Rayfield:Notify({Title = "Error", Content = "Not connected to C2 Server.", Duration = 3})
        end
    end)
end})

ConfigTab:CreateSection("📡 Webhooks")
WebhookToggle = ConfigTab:CreateToggle({Name = "Enable Discord Webhooks", CurrentValue = false, Callback = function(v) _G.WebhookEnabled = v end})
WebhookInput = ConfigTab:CreateInput({Name = "Webhook URL", PlaceholderText = "Paste URL Here", RemoveTextAfterFocusLost = false, Callback = function(Text) _G.WebhookURL = Text end})
ConfigTab:CreateButton({Name = "Test Webhook", Callback = function() SendWebhook("✅ Webhook Active!", "Your Webhook is successfully linked.", 5763719, {}) end})

ConfigTab:CreateSection("⚙️ Advanced Physics")
OffsetSlider = ConfigTab:CreateSlider({Name = "Hover Height (Offset)", Range = {0, 30}, Increment = 1, Suffix = "Studs", CurrentValue = SETTINGS.OFFSET_HEIGHT, Callback = function(v) SETTINGS.OFFSET_HEIGHT = v end})
WaitSlider = ConfigTab:CreateSlider({Name = "Wait / Retreat Altitude", Range = {0, 150}, Increment = 1, Suffix = "Studs", CurrentValue = SETTINGS.WAIT_ALTITUDE, Callback = function(v) SETTINGS.WAIT_ALTITUDE = v; SETTINGS.RETREAT_ALTITUDE = v end})
TTKSlider = ConfigTab:CreateSlider({Name = "Stuck Detection (Time-To-Kill)", Range = {1, 5000}, Increment = 1, Suffix = "Seconds", CurrentValue = SETTINGS.MAX_KILL_TIME, Callback = function(v) SETTINGS.MAX_KILL_TIME = v end})
HopSlider = ConfigTab:CreateSlider({Name = "Idle Time Before Map Hop", Range = {1, 15}, Increment = 1, Suffix = "Seconds", CurrentValue = SETTINGS.IDLE_BEFORE_HOP, Callback = function(v) SETTINGS.IDLE_BEFORE_HOP = v end})
DensitySlider = ConfigTab:CreateSlider({Name = "Min Enemies Before Hop", Range = {0, 15}, Increment = 1, Suffix = "Enemies left", CurrentValue = SETTINGS.MIN_NPCS_TO_STAY, Callback = function(v) SETTINGS.MIN_NPCS_TO_STAY = v end})

-- [[ 9. BACKGROUND THREADS & UI UPDATERS ]]
_G.AntiAFKConnection = task.spawn(function()
    while task.wait(30) do pcall(function() VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0); task.wait(0.1); VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0) end) end
end)

_G.StatsConnection = task.spawn(function()
    while task.wait(0.5) do
        pcall(function() 
            if not _G.on then StatusLabel:Set({Title = "🤖 Bot Status", Content = "Status: OFF\nToggle 'Enable Auto-Farm' to start."})
            else
                local actualArea = "Unknown"
                local pStats = ReplicatedStorage:FindFirstChild("Stats")
                if pStats then
                    local myStats = pStats:FindFirstChild(tostring(player.Name))
                    local internalArea = myStats and myStats:FindFirstChild("CurrentArea")
                    if internalArea then actualArea = tostring(internalArea.Value) end
                end
                local selAreas = #activeAreaRotationIds > 0 and table.concat(activeAreaRotationIds, ", ") or "None Selected"
                StatusLabel:Set({Title = "🤖 Bot Status", Content = string.format("🗺️ Selected Farm Area(s): %s\n📍 Actual Current Area: %s\n⚙️ Current Progress: %s", selAreas, actualArea, _G.CurrentState)})
            end
            local cl, cm = GetStatValue({"Level", "Lvl", "Levels"}), GetStatValue({"Money", "Cash", "Coins", "Gold"})
            if initialLevel == 0 and cl > 0 then initialLevel = cl end; if initialMoney == 0 and cm > 0 then initialMoney = cm end
            local elapsed = tick() - sessionStartTime
            StatsLabel:Set({Title = "📊 Live Statistics", Content = string.format("Time Spent: %02d:%02d:%02d\nLevel Gained: %d\nMoney Gained: %d\nAnti-AFK: Active ✅", math.floor(elapsed / 3600), math.floor((elapsed % 3600) / 60), math.floor(elapsed % 60), cl - initialLevel, cm - initialMoney)})
        end)
    end
end)

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
        
        if currentArea ~= 0 then
            task.spawn(function() TeleportSequence(0) end)
            task.wait(0.5)
        end
        
        local physicalSword = workspace.Swords:FindFirstChild(swordFolder.Name) or workspace:FindFirstChild(swordFolder.Name)
        if physicalSword then
            local targetCFrame = physicalSword:IsA("Model") and physicalSword:GetPivot() or physicalSword.CFrame
            if targetCFrame then
                local offset = CFrame.new(math.sin(tick() * 15) * 2, 0, math.cos(tick() * 15) * 2)
                hrp.CFrame = targetCFrame * offset
                task.wait(0.1)
                
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
        else
            warn("Could not find physical sword in workspace for Selling item:", swordFolder.Name)
        end
        
        task.wait(0.5)
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
            task.spawn(function() TeleportSequence(currentArea) end)
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
            currentTarget = GetClosestTarget()
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
local function DetermineState()
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
    if (not wantedNum or wantedNum == 0) and #activeAreaRotationIds > 0 then 
        wantedNum = activeAreaRotationIds[1]
        currentArea = wantedNum
    elseif (not wantedNum or wantedNum == 0) then 
        wantedNum = 7; currentArea = 7 
    end

    if actualNum ~= wantedNum then return "SignalWait", wantedNum end

    -- Priority 2: Mass Recovery Check
    StateData.MissingSwords = CheckMissingSwords()
    if #StateData.MissingSwords > 0 then return "Recovering" end

    -- Priority 3: Equip Main Weapon Check
    local currentTool = character:FindFirstChildOfClass("Tool")
    if _G.SavedSwordName and not isSwordLockedInAnyMachine(_G.SavedSwordName) and (not currentTool or currentTool.Name ~= _G.SavedSwordName) then
        return "Equipping"
    else
        -- Safely update saved sword if holding something new
        if currentTool and string.len(currentTool.Name) > 15 then
            _G.SavedSwordName = currentTool.Name
            if not table.find(_G.KeptSwords, _G.SavedSwordName) then table.insert(_G.KeptSwords, _G.SavedSwordName) end
        end
    end

    -- Priority 4: Archer Evasion
    if _G.AvoidArchers then
        local archerNearby = false
        if not (currentTarget and currentTarget.Name == "Archer") then
            local overlapParams = OverlapParams.new()
            overlapParams.FilterType = Enum.RaycastFilterType.Include
            overlapParams.FilterDescendantsInstances = {workspace.NPCs}
            local parts = workspace:GetPartBoundsInRadius(hrp.Position, SETTINGS.DANGER_RADIUS, overlapParams)
            for _, part in pairs(parts) do
                local model = part:FindFirstAncestorOfClass("Model")
                if model and model.Name == "Archer" then
                    local hp = model:GetAttribute(SETTINGS.HP_ATTRIBUTE_NAME)
                    if hp and hp > 0 then archerNearby = true break end
                end
            end
        end
        if archerNearby then lastArcherTime = tick(); return "Evading"
        elseif tick() - lastArcherTime <= SETTINGS.SAFE_COOLDOWN then return "Evading" end
    end

    -- Priority 5: Combat
    if currentTarget then return "Farming" end

    -- Priority 6: Nothing left to do
    return "Idle"
end

-- ⚙️ Executor Loop
_G.UltimateFarmConnection = RunService.Heartbeat:Connect(function()
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
    if BotState == "SignalWait" then
        _G.CurrentState = "Awaiting Green Signal (" .. tostring(extraData) .. ")..."
        if not StateData.SignalWaitStart then StateData.SignalWaitStart = tick() end
        if tick() - StateData.SignalWaitStart > 5 then
            StateData.SignalWaitStart = nil
            isTeleporting = true
            task.spawn(function() TeleportSequence(extraData) end)
        end

    elseif BotState == "Recovering" then
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
            local offset = CFrame.new(math.sin(tick() * 15) * 2, 0, math.cos(tick() * 15) * 2)
            hrp.CFrame = targetCFrame * offset
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
            warn("[DEBUG] Failed to equip sword after 5s! Dropping SavedSwordName.")
            _G.SavedSwordName = nil
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
            if #activeAreaRotationIds > 0 then
                local currentIndex = table.find(activeAreaRotationIds, actualArea)
                if currentIndex then
                    local nextIndex = currentIndex + 1
                    if nextIndex > #activeAreaRotationIds then nextIndex = 1 end
                    nextArea = activeAreaRotationIds[nextIndex]
                else 
                    nextArea = activeAreaRotationIds[1] 
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
end)

-- [[ 12. C2 WEB PANEL INTEGRATION ]]
task.spawn(function()
    -- Everything is wrapped inside a safe task.spawn and heavily pcall'ed.
    -- If the C2 server is completely offline, this thread gracefully fails and the rest of the autofarm continues untouched.
    
    local success, ws = pcall(function()
        local wsFunc = (syn and syn.websocket and syn.websocket.connect) or WebSocket.connect
        if wsFunc then
            local url = _G.C2_SERVER_URL or "ws://localhost:3000"
            return wsFunc(url)
        end
        return nil
    end)

    if not success or not ws then
        warn("⚠️ WebSocket C2 Server is unreachable or executor unsupported. Continuing standard autofarm...")
        return
    end

    print("🔌 Connected to Antigravity C2 Panel!")
    _G.C2_WS = ws
    
    local render3dActive = true

    -- Ascender & C2 Helpers
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

    local function getName(category, id)
        local categoryData = populateData[category]
        if not categoryData or id == nil then return "None" end
        return categoryData[id] and categoryData[id].Name or "None"
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

    local function getBackpackPayload()
        local payload = {}
        pcall(function()
            local invFolder = PlayerStats:FindFirstChild("Swords")
            if invFolder then
                for _, sword in pairs(invFolder:GetChildren()) do
                    if sword:IsA("Folder") then
                        local entry = {
                            id = sword.Name,
                            Equipped = sword:GetAttribute("Equipped") or false,
                            Level = sword:GetAttribute("Level") or 0,
                            Quality = getName("Quality", sword:GetAttribute("Quality")),
                            Rarity = getName("Rarity", sword:GetAttribute("Rarity")),
                            Mold = getName("Mold", sword:GetAttribute("Mold")),
                            Class = getName("Class", sword:GetAttribute("Class")),
                            Enchant1 = getName("Enchant", sword:GetAttribute("Enchant1")),
                            Enchant2 = getName("Enchant", sword:GetAttribute("Enchant2")),
                            Enchant3 = getName("Enchant", sword:GetAttribute("Enchant3"))
                        }
                        table.insert(payload, entry)
                    end
                end
            end
        end)
        return payload
    end

    -- 1. Register this specific client
    pcall(function()
        ws:Send(HttpService:JSONEncode({
            type = "register",
            clientType = "game",
            username = player.Name,
            status = {
                farming = _G.on or false,
                render3d = render3dActive,
                snipeEnabled = _G.autoDropEnabled or false,
                activeTargetSets = _G.ActiveTargetSets or {},
                ascenderData = getAscenderPayload(),
                backpackData = getBackpackPayload(),
                fullConfig = {
                    TargetSets = _G.ActiveTargetSets,
                    WhitelistedSwords = _G.WhitelistedSwords,
                    SpecialOverrides = _G.SpecialOverrides,
                    WebhookURL = _G.WebhookURL,
                    WebhookEnabled = _G.WebhookEnabled,
                    FarmAreas = _G.FarmAreas,
                    Settings = SETTINGS
                }
            }
        }))
    end)

    -- 2. Listen for incoming commands safely
    pcall(function()
        ws.OnMessage:Connect(function(msg)
            local s, data = pcall(function() return HttpService:JSONDecode(msg) end)
            if not s then return end

            if data.action == "toggleFarm" then
                _G.on = not _G.on
                print("C2 Command: AutoFarm toggled to", _G.on)
                
                -- Attempt to update Rayfield toggle visually if possible
                pcall(function()
                    if Window and CombatTab then
                        -- Emulate toggle click or set visual state if executor supports it
                    end
                end)
                
                pcall(function()
                    ws:Send(HttpService:JSONEncode({ type = "update_status", status = { farming = _G.on } }))
                end)

            elseif data.action == "toggle3d" then
                render3dActive = not render3dActive
                pcall(function() RunService:Set3dRenderingEnabled(render3dActive) end)
                print("C2 Command: 3D Render toggled to", render3dActive)
                pcall(function()
                    ws:Send(HttpService:JSONEncode({ type = "update_status", status = { render3d = render3dActive } }))
                end)
                
            elseif data.action == "toggleSnipe" then
                _G.autoDropEnabled = not _G.autoDropEnabled
                print("C2 Command: Sniper/AutoDrop toggled to", _G.autoDropEnabled)
                pcall(function()
                    ws:Send(HttpService:JSONEncode({ type = "update_status", status = { snipeEnabled = _G.autoDropEnabled } }))
                end)
                if _G.autoDropEnabled then
                    pcall(function()
                        local pStats = ReplicatedStorage:FindFirstChild("Stats"):FindFirstChild(tostring(player.Name))
                        for _, f in pairs(pStats:FindFirstChild("Swords"):GetChildren()) do evaluateInventorySword(f) end 
                    end)
                end
                
            elseif data.action == "saveConfig" then
                pcall(function()
                    if writefile then
                        local saveData = {TargetSets = _G.ActiveTargetSets, WhitelistedSwords = _G.WhitelistedSwords, SpecialOverrides = _G.SpecialOverrides, WebhookURL = _G.WebhookURL, WebhookEnabled = _G.WebhookEnabled, FarmAreas = _G.FarmAreas, Settings = SETTINGS}
                        writefile(SaveFileName, HttpService:JSONEncode(saveData))
                        print("C2 Command: Configuration Saved locally to " .. SaveFileName)
                    end
                end)

            elseif data.action == "loadConfig" then
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
                            pcall(function() ws:Send(HttpService:JSONEncode({ type = "update_status", status = { activeTargetSets = _G.ActiveTargetSets } })) end)
                            pcall(function() UpdateSetsDisplay(); UpdateWhitelistDisplay() end)
                        end
                    else
                        warn("C2 Command: No config file found to load.")
                    end
                end)
            
            elseif data.action == "syncConfig" then
                pcall(function()
                    local parsedData = data.payload
                    if parsedData then
                        if parsedData.TargetSets then _G.ActiveTargetSets = parsedData.TargetSets end
                        if parsedData.target_enchant_sets then _G.ActiveTargetSets = parsedData.target_enchant_sets end
                        
                        local wu = parsedData.WhitelistedSwords or parsedData.whitelisted_uuids
                        if wu then
                            local clean_wu = {}
                            for _, id in ipairs(wu) do
                                if type(id) == "string" then
                                    table.insert(clean_wu, id:match("^%s*(.-)%s*$"))
                                else
                                    table.insert(clean_wu, id)
                                end
                            end
                            _G.WhitelistedSwords = clean_wu
                        end
                        
                        if parsedData.SpecialOverrides then _G.SpecialOverrides = parsedData.SpecialOverrides end
                        if parsedData.WebhookURL then _G.WebhookURL = parsedData.WebhookURL end
                        if parsedData.WebhookEnabled ~= nil then _G.WebhookEnabled = parsedData.WebhookEnabled end
                        if parsedData.FarmAreas then _G.FarmAreas = parsedData.FarmAreas end
                        if parsedData.active_areas then _G.FarmAreas = parsedData.active_areas end
                        if parsedData.Settings then for k,v in pairs(parsedData.Settings) do SETTINGS[k] = v end end
                        print("C2 Command: Configuration Synced remotely from Website!")
                        
                        -- Update UI Elements dynamically if possible
                        pcall(function()
                            if UpdateSetsDisplay then UpdateSetsDisplay() end
                            if UpdateWhitelistDisplay then UpdateWhitelistDisplay() end
                            if AreaRotationDrop then AreaRotationDrop:Set(_G.FarmAreas) end
                            if WebhookInput then WebhookInput:Set(_G.WebhookURL) end
                            if WebhookToggle then WebhookToggle:Set(_G.WebhookEnabled) end
                            if OffsetSlider and SETTINGS.OFFSET_HEIGHT then OffsetSlider:Set(SETTINGS.OFFSET_HEIGHT) end
                            if WaitSlider and SETTINGS.WAIT_ALTITUDE then WaitSlider:Set(SETTINGS.WAIT_ALTITUDE) end
                            if TTKSlider and SETTINGS.MAX_KILL_TIME then TTKSlider:Set(SETTINGS.MAX_KILL_TIME) end
                            if HopSlider and SETTINGS.IDLE_BEFORE_HOP then HopSlider:Set(SETTINGS.IDLE_BEFORE_HOP) end
                            if DensitySlider and SETTINGS.MIN_NPCS_TO_STAY then DensitySlider:Set(SETTINGS.MIN_NPCS_TO_STAY) end
                        end)
                        pcall(function() ws:Send(HttpService:JSONEncode({ type = "update_status", status = { activeTargetSets = _G.ActiveTargetSets } })) end)
                    end
                end)
                
            elseif data.action == "updateWishlist" then
                if typeof(data.payload) == "table" then
                    _G.ActiveTargetSets = data.payload
                    print("C2 Command: Wishlist updated. Size: " .. tostring(#_G.ActiveTargetSets))
                    pcall(function() ws:Send(HttpService:JSONEncode({ type = "update_status", status = { activeTargetSets = _G.ActiveTargetSets } })) end)
                    pcall(function() UpdateSetsDisplay() end)
                end

            elseif data.action == "setAscenderMode" then
                pcall(function()
                    AscenderRemote:FireServer("Set Ascender Mode", tostring(data.payload))
                    print("C2 Command: Ascender Mode set to", tostring(data.payload))
                end)
            end
        end)
    end)
    
    -- 3. Heartbeat listener to push local Rayfield UI changes & Ascender data to the C2 Dashboard
    pcall(function()
        task.spawn(function()
            local lastFarmState = _G.on
            local lastSnipeState = _G.autoDropEnabled
            while task.wait(1) do
                local statusUpdates = {}
                local shouldUpdate = false

                if _G.on ~= lastFarmState then
                    lastFarmState = _G.on
                    statusUpdates.farming = _G.on
                    shouldUpdate = true
                end
                
                if _G.autoDropEnabled ~= lastSnipeState then
                    lastSnipeState = _G.autoDropEnabled
                    statusUpdates.snipeEnabled = _G.autoDropEnabled
                    shouldUpdate = true
                end
                
                -- Always sync Ascender Data periodically since stats can change internally
                statusUpdates.ascenderData = getAscenderPayload()
                statusUpdates.backpackData = getBackpackPayload()
                statusUpdates.fullConfig = {
                    TargetSets = _G.ActiveTargetSets,
                    WhitelistedSwords = _G.WhitelistedSwords,
                    SpecialOverrides = _G.SpecialOverrides,
                    WebhookURL = _G.WebhookURL,
                    WebhookEnabled = _G.WebhookEnabled,
                    FarmAreas = _G.FarmAreas,
                    Settings = SETTINGS
                }
                shouldUpdate = true

                if shouldUpdate then
                    pcall(function()
                        ws:Send(HttpService:JSONEncode({
                            type = "update_status",
                            status = statusUpdates
                        }))
                    end)
                end
            end
        end)
    end)
end)
