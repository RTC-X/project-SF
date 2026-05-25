if _G.StandaloneAscenderRunning then return end
_G.StandaloneAscenderRunning = true

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local hrp = character:WaitForChild("HumanoidRootPart")
local PlayerStats = ReplicatedStorage:WaitForChild("Stats"):WaitForChild(player.Name)

player.CharacterAdded:Connect(function(char)
    character = char
    hrp = char:WaitForChild("HumanoidRootPart")
end)

local Tables = ReplicatedStorage:WaitForChild("Tables")
local AscenderFunc = ReplicatedStorage:WaitForChild("Paper"):WaitForChild("Remotes"):WaitForChild("__remotefunction")
local AscenderEvent = ReplicatedStorage:WaitForChild("Paper"):WaitForChild("Remotes"):WaitForChild("__remoteevent")

local SwordModules = {
    Enchant1 = require(Tables.Enchant), Enchant2 = require(Tables.Enchant), Enchant3 = require(Tables.Enchant),
    Mold = require(Tables.Mold), Quality = require(Tables.Quality), Rarity = require(Tables.Rarity), Class = require(Tables.Class)
}

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

_G.AscenderCriteria = {
    Quality = "None", Rarity = "None", Mold = "None", Class = "None",
    Enchant1 = "None", Enchant2 = "None", Enchant3 = "None", Level = 0
}
_G.AscenderQueue = {}
_G.AutoAscendEnabled = false

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

local function swordMeetsCriteria(swordFolder)
    if not _G.AscenderCriteria then return false end
    
    local currentLvl = tonumber(swordFolder:GetAttribute("Level")) or 0
    if currentLvl >= 100 then return true end

    local hasAnyCriteria = false
    local allCriteriaMet = true 

    if _G.AscenderCriteria.Level and tonumber(_G.AscenderCriteria.Level) and tonumber(_G.AscenderCriteria.Level) > 1 then
        hasAnyCriteria = true
        if currentLvl < tonumber(_G.AscenderCriteria.Level) then 
            allCriteriaMet = false 
        end
    end
    
    local function checkStat(attrName, criteriaVal, moduleName)
        if criteriaVal and criteriaVal ~= "None" and criteriaVal ~= "0" then
            hasAnyCriteria = true
            local targetId = getIdFromName(moduleName or attrName, criteriaVal)
            local currentId = tonumber(swordFolder:GetAttribute(attrName)) or 0
            if targetId > 0 and currentId < targetId then
                allCriteriaMet = false
            end
        end
    end

    checkStat("Quality", _G.AscenderCriteria.Quality)
    checkStat("Rarity", _G.AscenderCriteria.Rarity)
    checkStat("Mold", _G.AscenderCriteria.Mold)
    checkStat("Class", _G.AscenderCriteria.Class)
    checkStat("Enchant1", _G.AscenderCriteria.Enchant1)
    checkStat("Enchant2", _G.AscenderCriteria.Enchant2, "Enchant1")
    checkStat("Enchant3", _G.AscenderCriteria.Enchant3, "Enchant1")
    
    if hasAnyCriteria and allCriteriaMet then
        return true
    end

    return false
end

local function CheckAscenderNeedsAction()
    local currentSword = workspace.Swords:FindFirstChild("Ascender_Sword")
    if currentSword then
        if swordMeetsCriteria(currentSword) then
            return { type = "FinishAndSwap", uuid = currentSword:GetAttribute("UUID") }
        end
    elseif not currentSword and #_G.AscenderQueue > 0 then
        return { type = "StartNext" }
    end
    return nil
end

local function PickupPhysicalSword(uuid)
    local physicalSword = workspace.Swords:FindFirstChild(uuid)
    if not physicalSword then return false end
    
    local maxAttempts = 10
    local attempts = 0
    
    while not PlayerStats.Swords:FindFirstChild(uuid) and attempts < maxAttempts do
        if not physicalSword or not physicalSword.Parent then break end
        local pivot = physicalSword:GetPivot()
        local jiggleOffset = Vector3.new(math.random(-10, 10)/10, 0, math.random(-10, 10)/10)
        hrp.CFrame = pivot * CFrame.new(jiggleOffset)
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

local isTeleporting = false
local function ExecuteAscenderAction(actionDetails)
    if not hrp or isTeleporting then return end
    
    local success, err = pcall(function()
        if actionDetails.type == "FinishAndSwap" then
            local finishedUUID = actionDetails.uuid
            local inInventory = PlayerStats.Swords:FindFirstChild(finishedUUID)
            local physicalSword = workspace.Swords:FindFirstChild(finishedUUID)
            
            if physicalSword and physicalSword:GetAttribute("BankSlot") and not inInventory then
                if PickupPhysicalSword(finishedUUID) then
                    pcall(function() AscenderFunc:InvokeServer("Teleport In Base", "Bank") end)
                    task.wait(0.2)
                    AscenderEvent:FireServer("Drop Sword", finishedUUID)
                    task.wait(0.5)
                    print("[Ascender] ✅ Deposit successful!")
                end
            else
                pcall(function() AscenderFunc:InvokeServer("Teleport In Base", "Bank") end)
                task.wait(0.2)
                AscenderEvent:FireServer("Drop Sword", finishedUUID)
                task.wait(0.5)
                print("[Ascender] ✅ Deposit successful!")
            end
            
            if #_G.AscenderQueue > 0 then
                local nextUUID = _G.AscenderQueue[1]
                local nextInv = PlayerStats.Swords:FindFirstChild(nextUUID)
                local nextChar = character and character:FindFirstChild(nextUUID)
                local readyToDrop = false
                
                if nextInv or nextChar then
                    readyToDrop = true
                else
                    local pSword = workspace.Swords:FindFirstChild(nextUUID)
                    if pSword and pSword:GetAttribute("BankSlot") then
                        readyToDrop = PickupPhysicalSword(nextUUID)
                    else
                        warn("[Ascender] 🚨 Sword UUID " .. tostring(nextUUID) .. " not found! Removing from queue.")
                        table.remove(_G.AscenderQueue, 1)
                    end
                end
                
                if readyToDrop then
                    pcall(function() AscenderFunc:InvokeServer("Teleport In Base", "Ascender") end)
                    task.wait(0.2) 
                    AscenderEvent:FireServer("Drop Sword", nextUUID)
                    print("[Ascender] ⚔️ Added next sword to Ascender: " .. tostring(nextUUID))
                    table.remove(_G.AscenderQueue, 1)
                    task.wait(0.5)
                end
            end
            
        elseif actionDetails.type == "StartNext" then
            local nextUUID = _G.AscenderQueue[1]
            local nextInv = PlayerStats.Swords:FindFirstChild(nextUUID)
            local nextChar = character and character:FindFirstChild(nextUUID)
            local readyToDrop = false
            
            if nextInv or nextChar then
                readyToDrop = true
            else
                local pSword = workspace.Swords:FindFirstChild(nextUUID)
                if pSword and pSword:GetAttribute("BankSlot") then
                    readyToDrop = PickupPhysicalSword(nextUUID)
                else
                    warn("[Ascender] 🚨 Sword UUID " .. tostring(nextUUID) .. " not found! Removing from queue.")
                    table.remove(_G.AscenderQueue, 1)
                end
            end
            
            if readyToDrop then
                pcall(function() AscenderFunc:InvokeServer("Teleport In Base", "Ascender") end)
                task.wait(0.2) 
                AscenderEvent:FireServer("Drop Sword", nextUUID)
                print("[Ascender] ⚔️ Added first sword to Ascender: " .. tostring(nextUUID))
                table.remove(_G.AscenderQueue, 1)
                task.wait(0.5)
            end
        end
    end)
    if not success then warn("[Standalone Ascender Error] " .. tostring(err)) end
end

task.spawn(function()
    while _G.StandaloneAscenderRunning do
        if _G.AutoAscendEnabled then
            local actionDetails = CheckAscenderNeedsAction()
            if actionDetails then
                ExecuteAscenderAction(actionDetails)
            end
        end
        task.wait(1)
    end
end)

-- UI SETUP
if game.CoreGui:FindFirstChild("Rayfield") then
    game.CoreGui.Rayfield:Destroy()
end

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local Window = Rayfield:CreateWindow({
    Name = "Standalone Ascender UI",
    LoadingTitle = "Ascender Suite",
    LoadingSubtitle = "Independent Tester",
    ConfigurationSaving = { Enabled = false },
    KeySystem = false
})

local Tab = Window:CreateTab("Ascender Config")

local Section = Tab:CreateSection("Auto Control")
Tab:CreateToggle({
    Name = "Enable Auto Ascender",
    CurrentValue = false,
    Flag = "ToggleAutoAscend",
    Callback = function(Value)
        _G.AutoAscendEnabled = Value
    end
})

local Section = Tab:CreateSection("Target Metrics")

local function createDropdown(name, statType)
    local options = getNames(statType)
    Tab:CreateDropdown({
        Name = name,
        Options = options,
        CurrentOption = {"None"},
        MultipleOptions = false,
        Flag = "Target" .. statType,
        Callback = function(Options)
            _G.AscenderCriteria[statType] = Options[1]
        end
    })
end

createDropdown("Target Quality", "Quality")
createDropdown("Target Rarity", "Rarity")
createDropdown("Target Mold", "Mold")
createDropdown("Target Class", "Class")
createDropdown("Target Enchant 1", "Enchant1")
createDropdown("Target Enchant 2", "Enchant2")
createDropdown("Target Enchant 3", "Enchant3")

Tab:CreateInput({
    Name = "Target Level",
    PlaceholderText = "Minimum Level",
    RemoveTextAfterFocusLost = false,
    Callback = function(Text)
        _G.AscenderCriteria.Level = tonumber(Text) or 0
    end
})

local QueueTab = Window:CreateTab("Queue Management")

local availableSwords = {}
local swordOptions = {}

local function RefreshAvailableSwords()
    availableSwords = {}
    swordOptions = {}
    for _, f in pairs(PlayerStats.Swords:GetChildren()) do
        local lvl = f:GetAttribute("Level") or 0
        local uuid = f.Name
        table.insert(availableSwords, {uuid = uuid, label = "Lvl " .. lvl .. " - " .. uuid:sub(1,6)})
        table.insert(swordOptions, "Lvl " .. lvl .. " - " .. uuid:sub(1,6))
    end
    for _, f in pairs(workspace.Swords:GetChildren()) do
        if f:GetAttribute("BankSlot") then
            local lvl = f:GetAttribute("Level") or 0
            local uuid = f.Name
            table.insert(availableSwords, {uuid = uuid, label = "[Bank] Lvl " .. lvl .. " - " .. uuid:sub(1,6)})
            table.insert(swordOptions, "[Bank] Lvl " .. lvl .. " - " .. uuid:sub(1,6))
        end
    end
end

RefreshAvailableSwords()

local QueueDropdown = QueueTab:CreateDropdown({
    Name = "Select Sword to Queue",
    Options = swordOptions,
    CurrentOption = {},
    MultipleOptions = false,
    Callback = function() end
})

QueueTab:CreateButton({
    Name = "Refresh Swords List",
    Callback = function()
        RefreshAvailableSwords()
        QueueDropdown:Refresh(swordOptions)
    end
})

local selectedSwordUUID = nil
QueueDropdown.Callback = function(Options)
    local selectedLabel = Options[1]
    for _, data in ipairs(availableSwords) do
        if data.label == selectedLabel then
            selectedSwordUUID = data.uuid
            break
        end
    end
end

QueueTab:CreateButton({
    Name = "Add to Queue",
    Callback = function()
        if selectedSwordUUID then
            table.insert(_G.AscenderQueue, selectedSwordUUID)
            Rayfield:Notify({Title = "Queued", Content = "Sword added to queue!", Duration = 2})
        else
            Rayfield:Notify({Title = "Error", Content = "Select a sword first!", Duration = 2})
        end
    end
})

QueueTab:CreateButton({
    Name = "Clear Queue",
    Callback = function()
        _G.AscenderQueue = {}
        Rayfield:Notify({Title = "Cleared", Content = "Queue cleared!", Duration = 2})
    end
})
