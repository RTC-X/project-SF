if getgenv().StandaloneAscenderRunning then
    getgenv().StandaloneAscenderRunning = false
    task.wait(1.5) -- Wait for old loop to shut down safely
end
getgenv().StandaloneAscenderRunning = true

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

local AscenderCriteria = {
    Quality = "None", Rarity = "None", Mold = "None", Class = "None",
    Enchant1 = "None", Enchant2 = "None", Enchant3 = "None", Level = 0
}
local AscenderMode = "None"
local AscenderQueue = {}
local AutoAscendEnabled = false

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
    if not AscenderCriteria then return false end
    
    local currentLvl = tonumber(swordFolder:GetAttribute("Level")) or 0
    if currentLvl >= 100 then return true end

    local hasAnyCriteria = false
    local allCriteriaMet = true 

    if AscenderCriteria.Level and tonumber(AscenderCriteria.Level) and tonumber(AscenderCriteria.Level) > 1 then
        hasAnyCriteria = true
        if currentLvl < tonumber(AscenderCriteria.Level) then 
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

    checkStat("Quality", AscenderCriteria.Quality)
    checkStat("Rarity", AscenderCriteria.Rarity)
    checkStat("Mold", AscenderCriteria.Mold)
    checkStat("Class", AscenderCriteria.Class)
    checkStat("Enchant1", AscenderCriteria.Enchant1)
    checkStat("Enchant2", AscenderCriteria.Enchant2, "Enchant1")
    checkStat("Enchant3", AscenderCriteria.Enchant3, "Enchant1")
    
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
    elseif not currentSword and #AscenderQueue > 0 then
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
            
            if #AscenderQueue > 0 then
                local nextUUID = AscenderQueue[1]
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
                        table.remove(AscenderQueue, 1)
                    end
                end
                
                if readyToDrop then
                    pcall(function() AscenderFunc:InvokeServer("Teleport In Base", "Ascender") end)
                    task.wait(0.2) 
                    AscenderEvent:FireServer("Drop Sword", nextUUID)
                    if AscenderMode ~= "None" then
                        AscenderEvent:FireServer("Set Ascender Mode", AscenderMode)
                    end
                    print("[Ascender] ⚔️ Added next sword to Ascender: " .. tostring(nextUUID))
                    table.remove(AscenderQueue, 1)
                    task.wait(0.5)
                end
            end
            
        elseif actionDetails.type == "StartNext" then
            local nextUUID = AscenderQueue[1]
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
                    table.remove(AscenderQueue, 1)
                end
            end
            
            if readyToDrop then
                pcall(function() AscenderFunc:InvokeServer("Teleport In Base", "Ascender") end)
                task.wait(0.2) 
                AscenderEvent:FireServer("Drop Sword", nextUUID)
                if AscenderMode ~= "None" then
                    AscenderEvent:FireServer("Set Ascender Mode", AscenderMode)
                end
                print("[Ascender] ⚔️ Added first sword to Ascender: " .. tostring(nextUUID))
                table.remove(AscenderQueue, 1)
                task.wait(0.5)
            end
        end
    end)
    if not success then warn("[Standalone Ascender Error] " .. tostring(err)) end
end

task.spawn(function()
    while getgenv().StandaloneAscenderRunning do
        if AutoAscendEnabled then
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
        AutoAscendEnabled = Value
    end
})

local Section = Tab:CreateSection("Target Metrics")

Tab:CreateDropdown({
    Name = "Mode to Ascend (Required)",
    Options = {"None", "Quality", "Rarity", "Mold", "Class", "Enchant1", "Enchant2", "Enchant3"},
    CurrentOption = {"None"},
    MultipleOptions = false,
    Flag = "CurrentAscenderMode",
    Callback = function(Options)
        AscenderMode = Options[1]
        if AscenderMode ~= "None" then
            AscenderEvent:FireServer("Set Ascender Mode", AscenderMode)
            print("[Ascender] Set mode to:", AscenderMode)
        end
    end
})

local function createDropdown(name, statType)
    local options = getNames(statType)
    Tab:CreateDropdown({
        Name = name,
        Options = options,
        CurrentOption = {"None"},
        MultipleOptions = false,
        Flag = "Target" .. statType,
        Callback = function(Options)
            AscenderCriteria[statType] = Options[1]
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
        AscenderCriteria.Level = tonumber(Text) or 0
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
    
    local bankFolder = PlayerStats:FindFirstChild("Bank")
    if bankFolder then
        for _, f in pairs(bankFolder:GetChildren()) do
            local lvl = f:GetAttribute("Level") or 0
            local uuid = f.Name
            table.insert(availableSwords, {uuid = uuid, label = "[Bank] Lvl " .. lvl .. " - " .. uuid:sub(1,6)})
            table.insert(swordOptions, "[Bank] Lvl " .. lvl .. " - " .. uuid:sub(1,6))
        end
    end
end

RefreshAvailableSwords()

local QueueDropdown = QueueTab:CreateDropdown({
    Name = "Select Swords to Queue",
    Options = swordOptions,
    CurrentOption = {},
    MultipleOptions = true,
    Callback = function() end
})

QueueTab:CreateButton({
    Name = "Refresh Swords List",
    Callback = function()
        RefreshAvailableSwords()
        QueueDropdown:Refresh(swordOptions, true)
    end
})

local selectedSwordLabels = {}
QueueDropdown.Callback = function(Options)
    selectedSwordLabels = Options
end

QueueTab:CreateButton({
    Name = "Add to Queue",
    Callback = function()
        if #selectedSwordLabels > 0 then
            local count = 0
            for _, selectedLabel in ipairs(selectedSwordLabels) do
                for _, data in ipairs(availableSwords) do
                    if data.label == selectedLabel then
                        table.insert(AscenderQueue, data.uuid)
                        count = count + 1
                        break
                    end
                end
            end
            Rayfield:Notify({Title = "Queued", Content = "Added " .. count .. " swords to queue!", Duration = 2})
        else
            Rayfield:Notify({Title = "Error", Content = "Select at least one sword first!", Duration = 2})
        end
    end
})

QueueTab:CreateButton({
    Name = "Clear Queue",
    Callback = function()
        AscenderQueue = {}
        Rayfield:Notify({Title = "Cleared", Content = "Queue cleared!", Duration = 2})
    end
})
