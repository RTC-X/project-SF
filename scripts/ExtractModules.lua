-- Module Reader Standalone
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tables = ReplicatedStorage:WaitForChild("Tables")

local SwordModules = {
    Enchant1 = require(Tables.Enchant), Enchant2 = require(Tables.Enchant), Enchant3 = require(Tables.Enchant),
    Mold = require(Tables.Mold), Quality = require(Tables.Quality), Rarity = require(Tables.Rarity), Class = require(Tables.Class)
}

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

print("--- Extracted Sword Metadata ---")
print("Enchants:", table.concat(EnchantNamesList, ", "))
print("Molds:", table.concat(MoldNamesList, ", "))
print("Qualities:", table.concat(QualityNamesList, ", "))
print("Rarities:", table.concat(RarityNamesList, ", "))
print("Classes:", table.concat(ClassNamesList, ", "))
print("--------------------------------")
