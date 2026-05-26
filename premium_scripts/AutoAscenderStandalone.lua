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
getgenv().AutoAscenderEnabled = true
getgenv().TargetCriteria = {
    -- Uncomment and set any attributes you want to target!
    -- Quality = "Divine",
    -- Rarity = "Mythic",
    -- Mold = "Gold",
    -- Class = "Demonic",
    -- Enchant1Level = 5,
    -- Enchant2Level = 5,
    -- Enchant3Level = 5,
    -- Level = 50,
}

-- [[ 🛠️ UTILITY FUNCTIONS ]]
local function getIdFromName(statType, targetName)
    if not targetName then return 0 end
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
    if targetVal then
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

local function getNextBankSword()
    local Stats = ReplicatedStorage:FindFirstChild("Stats")
    local PlayerStats = Stats and Stats:FindFirstChild(player.Name)
    local Bank = PlayerStats and PlayerStats:FindFirstChild("Bank")
    
    if not Bank then return nil end
    
    for _, sword in ipairs(Bank:GetChildren()) do
        if sword:IsA("Folder") then
            if not swordMeetsCriteria(sword) then
                return sword.Name -- Return UUID
            end
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
            task.wait(1)
            
            print("[AutoAscender] Depositing to Bank...")
            pcall(function() RemoteFunction:InvokeServer("Teleport In Base", "Bank") end)
            task.wait(0.3)
            RemoteEvent:FireServer("Drop Sword", currentSword.Name)
            task.wait(1.5)
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
        local nextSwordUUID = getNextBankSword()
        if nextSwordUUID then
            print("[AutoAscender] 🔄 Grabbing new sword from Bank:", nextSwordUUID)
            
            -- Teleport to bank and pick it up
            pcall(function() RemoteFunction:InvokeServer("Teleport In Base", "Bank") end)
            task.wait(0.5)
            
            if not PickupPhysicalSword(nextSwordUUID) then
                print("[AutoAscender] ❌ Failed to physically pick up sword from bank.")
                return
            end
            
            -- Teleport to Ascender and Drop it
            pcall(function() RemoteFunction:InvokeServer("Teleport In Base", "Ascender") end)
            task.wait(0.3)
            RemoteEvent:FireServer("Drop Sword", nextSwordUUID)
            task.wait(0.5)
            
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
            print("[AutoAscender] ⚠️ Bank has no suitable swords left for ascending.")
            getgenv().AutoAscenderEnabled = false 
        end
    end
end

-- [[ 🔁 BACKGROUND LOOP ]]
if getgenv().AutoAscenderLoop then 
    getgenv().AutoAscenderEnabled = false
    task.wait(2.5) -- Safely kill previous execution
end

getgenv().AutoAscenderEnabled = true
getgenv().AutoAscenderLoop = task.spawn(function()
    print("--- ⚙️ Auto Ascender Started ⚙️ ---")
    while getgenv().AutoAscenderEnabled do
        pcall(processAscender)
        task.wait(2)
    end
end)
