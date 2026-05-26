local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local Tables = ReplicatedStorage:WaitForChild("Tables")
local Paper = ReplicatedStorage:WaitForChild("Paper")
local Remotes = Paper:WaitForChild("Remotes")
local RemoteEvent = Remotes:WaitForChild("__remoteevent")
local RemoteFunction = Remotes:WaitForChild("__remotefunction")

local SwordModules = {
    Mold = require(Tables:WaitForChild("Mold")), 
    Quality = require(Tables:WaitForChild("Quality")), 
    Rarity = require(Tables:WaitForChild("Rarity")), 
    Class = require(Tables:WaitForChild("Class")),
    Enchant = require(Tables:WaitForChild("Enchant"))
}

-- [[ 🎯 TARGET CONFIGURATION ]]
getgenv().AutoAscenderEnabled = false
getgenv().AscenderQueue = getgenv().AscenderQueue or {}
getgenv().TargetCriteria = {
    Quality = "None",
    Rarity = "None",
    Mold = "None",
    Class = "None",
    Enchant1Level = 0,
    Enchant2Level = 0,
    Enchant3Level = 0,
    Level = 0,
}

local BankCapacityPerLevel = {
    [1] = 6, [2] = 10, [3] = 12, [4] = 14, [5] = 16,
    [6] = 18, [7] = 20, [8] = 22, [9] = 24, [10] = 26,
    [11] = 28, [12] = 30, [13] = 32, [14] = 34, [15] = 36
}

local function GetMaxBankSlots(PlayerStats)
    local bankLvlObj = PlayerStats:FindFirstChild("BankLevel")
    local lvl = bankLvlObj and tonumber(bankLvlObj.Value) or 1
    return BankCapacityPerLevel[lvl] or (lvl > 15 and 36 or 6)
end

-- [[ 🛠️ UTILITY FUNCTIONS ]]
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

local function getIdFromName(statType, targetName)
    if not targetName or targetName == "None" then return 0 end
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
    local t = getgenv().TargetCriteria
    if not t then return "None" end
    
    if isStatUnmet(swordFolder, "Quality", t.Quality) then return "Quality" end
    if isStatUnmet(swordFolder, "Rarity", t.Rarity) then return "Rarity" end
    if isStatUnmet(swordFolder, "Mold", t.Mold) then return "Mold" end
    if isStatUnmet(swordFolder, "Class", t.Class) then return "Class" end
    if isStatUnmet(swordFolder, "Enchant1Level", t.Enchant1Level) then return "Enchant1" end
    if isStatUnmet(swordFolder, "Enchant2Level", t.Enchant2Level) then return "Enchant2" end
    if isStatUnmet(swordFolder, "Enchant3Level", t.Enchant3Level) then return "Enchant3" end
    if isStatUnmet(swordFolder, "Level", t.Level) then return "Level" end
    
    return "None"
end

local function swordMeetsCriteria(swordFolder)
    return getTargetMode(swordFolder) == "None"
end

local function getNextQueuedSword()
    local Stats = ReplicatedStorage:FindFirstChild("Stats")
    local PlayerStats = Stats and Stats:FindFirstChild(player.Name)
    if not PlayerStats then return nil end
    
    while #getgenv().AscenderQueue > 0 do
        local nextUUID = getgenv().AscenderQueue[1]
        local sword = PlayerStats.Swords:FindFirstChild(nextUUID) or (PlayerStats:FindFirstChild("Bank") and PlayerStats.Bank:FindFirstChild(nextUUID))
        
        if sword then
            if not swordMeetsCriteria(sword) then
                return nextUUID
            else
                table.remove(getgenv().AscenderQueue, 1)
            end
        else
            table.remove(getgenv().AscenderQueue, 1)
        end
    end
    return nil
end

local function PickupPhysicalSword(uuid)
    local physicalSword = workspace.Swords:FindFirstChild(uuid)
    if not physicalSword then return false end
    
    local character = player.Character or player.CharacterAdded:Wait()
    local hrp = character:WaitForChild("HumanoidRootPart")
    local PlayerStats = ReplicatedStorage:WaitForChild("Stats"):WaitForChild(player.Name)
    
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
    local Stats = ReplicatedStorage:FindFirstChild("Stats")
    local PlayerStats = Stats and Stats:FindFirstChild(player.Name)
    if not PlayerStats then return end
    
    local extraSwords = {}
    for _, s in ipairs(PlayerStats.Swords:GetChildren()) do
        if s.Name ~= allowedUUID then
            table.insert(extraSwords, s.Name)
        end
    end
    
    if #extraSwords > 0 then
        local currentBankCount = PlayerStats.Bank and #PlayerStats.Bank:GetChildren() or 0
        local dynamicMaxSlots = GetMaxBankSlots(PlayerStats)
        
        if currentBankCount >= dynamicMaxSlots then
            print("[AutoAscender] ⚠️ Bank full. Sweeper bypassed to protect inventory items.")
            return
        end
        
        print("[AutoAscender] 🧹 Found " .. #extraSwords .. " extra/stuck sword(s) in inventory. Strictly depositing to Bank...")
        pcall(function() RemoteFunction:InvokeServer("Teleport In Base", "Bank") end)
        task.wait(0.6) -- Strict wait to ensure character is on the bank
        
        for _, uuid in ipairs(extraSwords) do
            currentBankCount = PlayerStats.Bank and #PlayerStats.Bank:GetChildren() or 0
            if currentBankCount >= dynamicMaxSlots then
                print("[AutoAscender] ⚠️ Bank filled up during sweep! Halting sweeper.")
                break
            end
            RemoteEvent:FireServer("Drop Sword", uuid)
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

-- [[ ⚙️ CORE LOGIC ]]
local function processAscender()
    if not getgenv().AutoAscenderEnabled then return end
    
    local Stats = ReplicatedStorage:FindFirstChild("Stats")
    local PlayerStats = Stats and Stats:FindFirstChild(player.Name)
    if not PlayerStats then return end
    
    local Ascender = PlayerStats:FindFirstChild("Ascender")
    if not Ascender then return end
    
    local currentSword = Ascender:FindFirstChildOfClass("Folder")
    
    if currentSword then
        -- Sword is in Ascender. Check if it hit our target!
        if swordMeetsCriteria(currentSword) then
            print("[AutoAscender] 🎯 Target reached for sword:", currentSword.Name)
            print("[AutoAscender] Picking up from Ascender...")
            
            pcall(function() RemoteFunction:InvokeServer("Pickup Ascender") end)
            
            -- Wait strictly for it to enter inventory so it isn't lost
            local waitTime = 0
            while not PlayerStats.Swords:FindFirstChild(currentSword.Name) and waitTime < 5 do
                task.wait(0.2)
                waitTime = waitTime + 0.2
            end
            
            local currentBankCount = PlayerStats.Bank and #PlayerStats.Bank:GetChildren() or 0
            local dynamicMaxSlots = GetMaxBankSlots(PlayerStats)
            
            if currentBankCount >= dynamicMaxSlots then
                print("[AutoAscender] ⚠️ BANK IS AT MAXIMUM CAPACITY! (" .. currentBankCount .. "/" .. dynamicMaxSlots .. ")")
                print("[AutoAscender] Keeping finished sword in your Inventory to protect it!")
            else
                print("[AutoAscender] Depositing to Bank...")
                pcall(function() RemoteFunction:InvokeServer("Teleport In Base", "Bank") end)
                task.wait(0.6) -- Ensure character has landed on the bank platform before dropping
                RemoteEvent:FireServer("Drop Sword", currentSword.Name)
                
                -- Wait for it to leave inventory
                waitTime = 0
                while PlayerStats.Swords:FindFirstChild(currentSword.Name) and waitTime < 5 do
                    task.wait(0.2)
                    waitTime = waitTime + 0.2
                end
                
                -- Strict Measure: Sweep any stragglers immediately!
                enforceCleanInventory(nil)
            end
        else
            -- Ensure the mode is correctly set!
            local mode = getTargetMode(currentSword)
            if mode ~= "None" then
                RemoteEvent:FireServer("Set Ascender Mode", mode)
            end
            return
        end
    end
    
    -- Ascender is currently empty (or we just emptied it). Find next sword!
    currentSword = Ascender:FindFirstChildOfClass("Folder")
    if not currentSword then
        local nextSwordUUID = getNextQueuedSword()
        if nextSwordUUID then
            print("[AutoAscender] 🔄 Grabbing new sword from Queue:", nextSwordUUID)
            
            if not PickupPhysicalSword(nextSwordUUID) then
                print("[AutoAscender] ❌ Failed to physically pick up sword from bank.")
                return
            end
            
            -- Strict Measure: Clear out any accidental touches BEFORE going to Ascender!
            enforceCleanInventory(nextSwordUUID)
            
            -- Teleport to Ascender and Drop it
            pcall(function() RemoteFunction:InvokeServer("Teleport In Base", "Ascender") end)
            task.wait(0.5) -- Wait to securely land at the ascender
            RemoteEvent:FireServer("Drop Sword", nextSwordUUID)
            table.remove(getgenv().AscenderQueue, 1)
            
            -- Ensure it left inventory
            local waitTime = 0
            while PlayerStats.Swords:FindFirstChild(nextSwordUUID) and waitTime < 5 do
                task.wait(0.2)
                waitTime = waitTime + 0.2
            end
            
            local swordFolder = PlayerStats.Swords:FindFirstChild(nextSwordUUID) or (PlayerStats.Bank and PlayerStats.Bank:FindFirstChild(nextSwordUUID)) or workspace.Swords:FindFirstChild(nextSwordUUID)
            if swordFolder then
                local mode = getTargetMode(swordFolder)
                if mode ~= "None" then
                    RemoteEvent:FireServer("Set Ascender Mode", mode)
                    print("[AutoAscender] ⚙️ Set Ascender Mode to:", mode)
                end
            end
            task.wait(1.5)
        else
            if getgenv().AutoAscenderEnabled then
                print("[AutoAscender] ⚠️ Queue is empty or remaining swords already meet criteria.")
                getgenv().AutoAscenderEnabled = false 
                if getgenv().AscenderToggle then
                    getgenv().AscenderToggle:Set(false)
                end
            end
        end
    end
end

-- [[ 🔁 BACKGROUND LOOP ]]
if getgenv().AutoAscenderLoop then 
    getgenv().AutoAscenderEnabled = false
    task.wait(2.5) -- Safely kill previous execution
end

getgenv().AutoAscenderLoop = task.spawn(function()
    print("--- ⚙️ Auto Ascender Started ⚙️ ---")
    while task.wait(2) do
        if getgenv().AutoAscenderEnabled then
            pcall(processAscender)
        end
    end
end)

-- [[ 🖥️ RAYFIELD UI ]]
if game.CoreGui:FindFirstChild("Rayfield") then
    game.CoreGui.Rayfield:Destroy()
end

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local Window = Rayfield:CreateWindow({
    Name = "Standalone Auto Ascender",
    LoadingTitle = "Ascender Module",
    LoadingSubtitle = "Testing Environment",
    ConfigurationSaving = { Enabled = false },
    KeySystem = false
})

local Tab = Window:CreateTab("Auto Ascender")
local Section = Tab:CreateSection("Control")

getgenv().AscenderToggle = Tab:CreateToggle({
    Name = "Enable Auto Ascender",
    CurrentValue = false,
    Flag = "ToggleAutoAscend",
    Callback = function(Value)
        getgenv().AutoAscenderEnabled = Value
    end
})

Tab:CreateSection("Target Metrics")

local function createDropdown(name, statType)
    local options = getNames(statType)
    Tab:CreateDropdown({
        Name = name,
        Options = options,
        CurrentOption = {"None"},
        MultipleOptions = false,
        Flag = "Target" .. statType,
        Callback = function(Options)
            getgenv().TargetCriteria[statType] = Options[1]
        end
    })
end

createDropdown("Target Quality", "Quality")
createDropdown("Target Rarity", "Rarity")
createDropdown("Target Mold", "Mold")
createDropdown("Target Class", "Class")

Tab:CreateInput({
    Name = "Target Enchant 1 Level",
    PlaceholderText = "Minimum Lvl (e.g. 5)",
    RemoveTextAfterFocusLost = false,
    Callback = function(Text)
        getgenv().TargetCriteria.Enchant1Level = tonumber(Text) or 0
    end
})

Tab:CreateInput({
    Name = "Target Enchant 2 Level",
    PlaceholderText = "Minimum Lvl (e.g. 5)",
    RemoveTextAfterFocusLost = false,
    Callback = function(Text)
        getgenv().TargetCriteria.Enchant2Level = tonumber(Text) or 0
    end
})

Tab:CreateInput({
    Name = "Target Enchant 3 Level",
    PlaceholderText = "Minimum Lvl (e.g. 5)",
    RemoveTextAfterFocusLost = false,
    Callback = function(Text)
        getgenv().TargetCriteria.Enchant3Level = tonumber(Text) or 0
    end
})

Tab:CreateInput({
    Name = "Target Sword Level",
    PlaceholderText = "Minimum Level",
    RemoveTextAfterFocusLost = false,
    Callback = function(Text)
        getgenv().TargetCriteria.Level = tonumber(Text) or 0
    end
})

-- Queue Management Tab
local QueueTab = Window:CreateTab("Queue Management")

local availableSwords = {}
local swordOptions = {}

local function RefreshAvailableSwords()
    availableSwords = {}
    swordOptions = {}
    local Stats = ReplicatedStorage:FindFirstChild("Stats")
    local PlayerStats = Stats and Stats:FindFirstChild(player.Name)
    if not PlayerStats then return end
    
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
                        table.insert(getgenv().AscenderQueue, data.uuid)
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
        getgenv().AscenderQueue = {}
        Rayfield:Notify({Title = "Cleared", Content = "Queue cleared!", Duration = 2})
    end
})
