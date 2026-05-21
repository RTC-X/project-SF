-- Bank Items Extractor
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local Tables = ReplicatedStorage:WaitForChild("Tables")
local SwordModules = {
    Mold = require(Tables.Mold), 
    Quality = require(Tables.Quality), 
    Rarity = require(Tables.Rarity), 
    Class = require(Tables.Class)
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
        return
    end
    
    for i, item in ipairs(items) do
        if item:IsA("Folder") then
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
            
            local formattedValue = formatValue(rawValue)
            
            print(string.format("[%d] UUID: %s", i, uuid))
            print(string.format("  -> Level: %s", tostring(level)))
            print(string.format("  -> Quality: %s", quality))
            print(string.format("  -> Rarity: %s", rarity))
            print(string.format("  -> Mold: %s", mold))
            print(string.format("  -> Class: %s", class))
            print(string.format("  -> Value: %s (Raw: %s)", formattedValue, tostring(rawValue)))
            print("-----------------------------------")
        end
    end
end

extractBankItems()
