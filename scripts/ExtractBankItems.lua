-- Bank and Ascender Extractor
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local Tables = ReplicatedStorage:WaitForChild("Tables")
local SwordModules = {
    Mold = require(Tables.Mold), 
    Quality = require(Tables.Quality), 
    Rarity = require(Tables.Rarity), 
    Class = require(Tables.Class),
    Enchant = require(Tables.Enchant)
}

local function getActualStats(statType, statId)
    local m = SwordModules[statType]
    if m and m[statId] then return m[statId] end
    return nil
end 

local suffixes = {"K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc", "Ud", "Dd", "Td"}
local function formatValue(value)
    local n = tonumber(value)
    if not n then return tostring(value) end
    if n < 1000 then return tostring(math.floor(n)) end
    
    local i = math.floor(math.log10(n) / 3)
    if i > #suffixes then i = #suffixes end
    if i < 1 then return tostring(math.floor(n)) end
    
    local div = 10^(i*3)
    local formatted = n / div
    return string.format("%.2f", formatted) .. suffixes[i]
end

local function printSwordDetails(item, index, prefixStr)
    local uuid = item.Name
    local attrs = item:GetAttributes()
    
    -- Extract important attributes
    local qId = attrs.Quality
    local rId = attrs.Rarity
    local mId = attrs.Mold
    local cId = attrs.Class
    local level = attrs.Level or 0
    local rawValue = attrs.Value or 0
    
    -- Resolve Names from IDs
    local qData = getActualStats("Quality", qId)
    local rData = getActualStats("Rarity", rId)
    local mData = getActualStats("Mold", mId)
    local cData = getActualStats("Class", cId)
    
    local quality = (qData and qData.Name) or (qId and tostring(qId)) or "None"
    local rarity = (rData and rData.Name) or (rId and tostring(rId)) or "None"
    local mold = (mData and mData.Name) or (mId and tostring(mId)) or "None"
    local class = (cData and cData.Name) or (cId and tostring(cId)) or "None"
    
    -- Enchants
    local function getEnchantStr(num)
        local eId = attrs["Enchant"..num]
        local eLvl = attrs["Enchant"..num.."Level"] or 0
        local eData = getActualStats("Enchant", eId)
        local eName = (eData and eData.Name) or (eId and tostring(eId)) or "None"
        if eName == "None" then return "None" end
        return eName .. " (Lvl " .. tostring(eLvl) .. ")"
    end
    
    local formattedValue = formatValue(rawValue)
    
    print(string.format("[%s] %s UUID: %s", tostring(index), prefixStr, uuid))
    print(string.format("  -> Level: %s", tostring(level)))
    print(string.format("  -> Quality: %s", quality))
    print(string.format("  -> Rarity: %s", rarity))
    print(string.format("  -> Mold: %s", mold))
    print(string.format("  -> Class: %s", class))
    print(string.format("  -> Enchant 1: %s", getEnchantStr(1)))
    print(string.format("  -> Enchant 2: %s", getEnchantStr(2)))
    print(string.format("  -> Enchant 3: %s", getEnchantStr(3)))
    print(string.format("  -> Value: %s (Raw: %s)", formattedValue, tostring(rawValue)))
    print("-----------------------------------")
end

local function extractBankItems()
    local Stats = ReplicatedStorage:FindFirstChild("Stats")
    if not Stats then return warn("Stats folder not found") end
    
    local PlayerStats = Stats:FindFirstChild(player.Name)
    if not PlayerStats then return warn("Player stats not found") end
    
    local Bank = PlayerStats:FindFirstChild("Bank")
    if not Bank then return warn("Bank not found") end
    
    print("--- 🏦 Extracting Bank Items 🏦 ---")
    local items = Bank:GetChildren()
    if #items == 0 then
        print("Bank is empty.")
    else
        for i, item in ipairs(items) do
            if item:IsA("Folder") then
                printSwordDetails(item, i, "Bank")
            end
        end
    end
end

local function extractAscenderData()
    local Stats = ReplicatedStorage:FindFirstChild("Stats")
    if not Stats then return warn("Stats folder not found") end
    
    local PlayerStats = Stats:FindFirstChild(player.Name)
    if not PlayerStats then return warn("Player stats not found") end
    
    print("--- ⚙️ Extracting Ascender Data ⚙️ ---")
    
    local ascenderModeObj = PlayerStats:FindFirstChild("AscenderMode")
    local mode = ascenderModeObj and ascenderModeObj.Value or "Unknown"
    print("Current Ascender Mode: " .. tostring(mode))
    
    local Ascender = PlayerStats:FindFirstChild("Ascender")
    if not Ascender then return warn("Ascender folder not found") end
    
    local sword = Ascender:FindFirstChildOfClass("Folder")
    if not sword then
        print("No sword is currently in the Ascender.")
    else
        print("Sword currently in Ascender:")
        printSwordDetails(sword, 1, "Ascender")
    end
end

extractBankItems()
extractAscenderData()

-- Utility function for changing Ascender Mode independently
-- Usage: setAscenderMode("Quality")
_G.setAscenderMode = function(modeName)
    local Paper = ReplicatedStorage:WaitForChild("Paper", 5)
    if not Paper then return warn("Paper folder not found") end
    local AscenderRemote = Paper:WaitForChild("Remotes"):WaitForChild("__remoteevent")
    AscenderRemote:FireServer("Set Ascender Mode", tostring(modeName))
    print("Sent request to change Ascender Mode to:", modeName)
end
