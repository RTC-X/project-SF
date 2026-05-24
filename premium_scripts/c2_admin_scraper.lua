-- [[ C2 Admin Scraper (PRIVATE SCRIPT) ]]
-- Instructions: 
-- 1. Create a text file in your executor's workspace folder named "C2_ADMIN_KEY.txt"
-- 2. Put your super secret ADMIN_UPLOAD_KEY inside that file.
-- 3. Run this script in the Roblox game whenever it updates.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

print("========== [ C2 Admin Scraper Initializing ] ==========")

-- 1. Securely load the Admin Key from local file
local adminKey = ""
local success, err = pcall(function()
    if readfile then
        adminKey = readfile("C2_ADMIN_KEY.txt")
    end
end)

if not success or adminKey == "" then
    warn("[!] FATAL ERROR: Could not read 'C2_ADMIN_KEY.txt' from your executor workspace.")
    warn("Please create this file and paste your secret key inside it.")
    return
end

-- Strip whitespace
adminKey = string.gsub(adminKey, "%s+", "")

-- 2. Honeypot Protection limits
local MAX_ITEMS_PER_CATEGORY = 500
local MAX_STRING_LENGTH = 100

local function ExtractNames(module, maxItems)
    local entries = {}
    pcall(function()
        for id, data in pairs(module) do
            if type(id) == "number" and type(data) == "table" and data.Name then 
                local cleanName = string.sub(tostring(data.Name), 1, MAX_STRING_LENGTH)
                table.insert(entries, {id = id, name = cleanName})
            end
        end
    end)
    
    -- Sort exactly by the underlying numeric ID in the module
    table.sort(entries, function(a, b) return a.id < b.id end)
    
    local list = {}
    for i = 1, math.min(#entries, maxItems) do
        table.insert(list, entries[i].name)
    end
    return list
end

print("[+] Scraping ReplicatedStorage.Tables...")

local Tables = ReplicatedStorage:WaitForChild("Tables")
local AreasModule = require(Tables:WaitForChild("Areas"))

local AreaNamesList = {}
local AreaMap = {} 
local areaCount = 0

for id, data in pairs(AreasModule) do
    if areaCount >= MAX_ITEMS_PER_CATEGORY then break end
    if id ~= 0 then 
        local req = data.LevelReq or 0
        local str = "[" .. tostring(id) .. "] " .. string.sub(tostring(data.Name), 1, MAX_STRING_LENGTH) .. " (Lvl " .. req .. ")"
        table.insert(AreaNamesList, str)
        AreaMap[str] = id
        areaCount = areaCount + 1
    end
end
table.sort(AreaNamesList, function(a, b) return AreaMap[a] < AreaMap[b] end)

local EnchantNamesList = ExtractNames(require(Tables:WaitForChild("Enchant")), MAX_ITEMS_PER_CATEGORY)
local MoldNamesList = ExtractNames(require(Tables:WaitForChild("Mold")), MAX_ITEMS_PER_CATEGORY)
local QualityNamesList = ExtractNames(require(Tables:WaitForChild("Quality")), MAX_ITEMS_PER_CATEGORY)
local RarityNamesList = ExtractNames(require(Tables:WaitForChild("Rarity")), MAX_ITEMS_PER_CATEGORY)
local ClassNamesList = ExtractNames(require(Tables:WaitForChild("Class")), MAX_ITEMS_PER_CATEGORY)
local MobTraitNamesList = ExtractNames(require(Tables:WaitForChild("MobTrait")), MAX_ITEMS_PER_CATEGORY)

local globalMetadata = {
    Areas = AreaNamesList,
    Enchants = EnchantNamesList,
    Molds = MoldNamesList,
    Qualities = QualityNamesList,
    Rarities = RarityNamesList,
    Classes = ClassNamesList,
    MobTraits = MobTraitNamesList
}

print("[+] Connecting to Django C2 Server...")

local wsFunc = (syn and syn.websocket and syn.websocket.connect) or WebSocket.connect
if not wsFunc then
    warn("[!] Executor does not support WebSockets.")
    return
end

local ws
local connectSuccess, connectErr = pcall(function()
    ws = wsFunc("wss://c2scripts.xyz/ws/c2/")
end)

if not connectSuccess or not ws then
    warn("[!] Failed to connect to server:", connectErr)
    return
end

print("[+] Sending Admin Payload...")

local payload = {
    action = "update_metadata",
    admin_key = adminKey,
    metadata = globalMetadata
}

ws:Send(HttpService:JSONEncode(payload))

task.wait(1)

pcall(function()
    ws.OnMessage:Connect(function(msg)
        print("[SERVER RESPONSE]:", msg)
    end)
end)

task.wait(2)
pcall(function() ws:Close() end)

print("========== [ Upload Complete! Check Dashboard ] ==========")
