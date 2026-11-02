-- =====================================================================
-- [ANIME ADVENTURES] - ZERO UI (BẢN TỐI ƯU TỐC ĐỘ & CHỐNG LỖI GAME)
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapID = "_lobbytemplategreen3"
local LevelID = "namek_level_1"
local Difficulty = "Normal"

local PLACEMENT_CFRAMES = {
    CFrame.new(-2944.945556640625, 91.806205749511719, -690.08197021484375),
    CFrame.new(-2943.427978515625, 91.806205749511719, -692.01861572265625),
    CFrame.new(-2946.0390625, 91.80621337890625, -692.96728515625),
    CFrame.new(-2945.37353515625, 91.80621337890625, -694.9530029296875),
    CFrame.new(-2943.212890625, 91.806205749511719, -695.11309814453125),
    CFrame.new(-2941.320068359375, 91.806205749511719, -699.8656005859375)
}

local function getRemote(path)
    local current = ReplicatedStorage
    for _, part in ipairs(string.split(path, ".")) do
        if current then current = current:FindFirstChild(part) end
    end
    return current
end

local api_join = getRemote("endpoints.client_to_server.request_join_lobby")
local api_lock = getRemote("endpoints.client_to_server.request_lock_level")
local api_start = getRemote("endpoints.client_to_server.request_start_game")
local api_vote_start = getRemote("endpoints.client_to_server.vote_start")
local api_spawn = getRemote("endpoints.client_to_server.spawn_unit")
local api_upgrade = getRemote("endpoints.client_to_server.upgrade_unit_ingame")

local LearnedUUIDs = {}
local currentPlaceIndex = 1
local lastSpawnTime = 0
local lastUpgradeTime = 0
local hasVotedStart = false
local hasScanned = false

local function log(msg) print("[AUTO-AA] " .. msg) end

-- 1. HÀM DÒ TÌM UUID
local function GetPotentialUUIDs()
    local uuids = {}
    local seen = {}
    local function extractFromInstance(obj)
        local success, str = pcall(function() return tostring(obj.Name) .. tostring(obj.Value) end)
        if success then
            for uuid in string.gmatch(str, "({%x+-%x+-%x+-%x+-%x+})") do
                if not seen[uuid] then table.insert(uuids, uuid) seen[uuid] = true end
            end
        end
    end
    for _, v in ipairs(Players.LocalPlayer.PlayerGui:GetDescendants()) do
        if v:IsA("StringValue") or v:IsA("Folder") then extractFromInstance(v) end
    end
    if getnilinstances then
        pcall(function()
            for _, v in ipairs(getnilinstances()) do
                if v:IsA("StringValue") or v:IsA("Folder") then extractFromInstance(v) end
            end
        end)
    end
    return uuids
end

local function AutoScanAndVerifyUUIDs()
    if hasScanned then return end
    hasScanned = true
    log("Đang quét UUID...")
    local potentialUUIDs = GetPotentialUUIDs()
    
    if #potentialUUIDs == 0 then
        table.insert(LearnedUUIDs, "{cf08f291-6071-4f30-ad4a-db345453a82e}")
        table.insert(LearnedUUIDs, "{337bcc00-f403-4722-87de-b5e2cf39c51c}")
        return
    end

    local testCFrame = PLACEMENT_CFRAMES[1]
    for i, uuid in ipairs(potentialUUIDs) do
        if #LearnedUUIDs >= 6 then break end
        local success, result = pcall(function() return api_spawn:InvokeServer(uuid, testCFrame) end)
        if success and result == true then
            table.insert(LearnedUUIDs, uuid)
            log("✅ Tìm thấy Unit hợp lệ.")
        end
        task.wait(0.5)
    end
    if #LearnedUUIDs == 0 then
        table.insert(LearnedUUIDs, "{cf08f291-6071-4f30-ad4a-db345453a82e}")
        table.insert(LearnedUUIDs, "{337bcc00-f403-4722-87de-b5e2cf39c51c}")
    end
end

-- 2. KIỂM TRA TRẠNG THÁI
local function IsInLobby()
    local mapConfig = workspace:FindFirstChild("_MAP_CONFIG")
    if mapConfig and mapConfig:FindFirstChild("IsLobby") then return mapConfig.IsLobby.Value end
    return false
end

-- 3. HÀNH ĐỘNG (ĐÃ GIẢM TỐC ĐỘ)
local function HandleLobby()
    log("Đang ở Lobby, tự động vào trận...")
    pcall(function() api_join:InvokeServer(MapID) end) task.wait(1)
    pcall(function() api_lock:InvokeServer(MapID, LevelID, true, Difficulty) end) task.wait(1)
    pcall(function() api_start:InvokeServer(MapID) end)
    hasVotedStart = false
    hasScanned = false
    task.wait(10) -- Chờ 10s cho game load map xong hẳn
end

local function SmartSpawn()
    if tick() - lastSpawnTime < 3 then return end
    local unitFolder = workspace:FindFirstChild("_UNITS")
    local currentUnitCount = unitFolder and #unitFolder:GetChildren() or 0

    if currentUnitCount < #PLACEMENT_CFRAMES and api_spawn and #LearnedUUIDs > 0 then
        lastSpawnTime = tick()
        local currentUUID = LearnedUUIDs[currentPlaceIndex]
        local targetCFrame = PLACEMENT_CFRAMES[currentUnitCount + 1]
        pcall(function() api_spawn:InvokeServer(currentUUID, targetCFrame) end)
        currentPlaceIndex = currentPlaceIndex + 1
        if currentPlaceIndex > #LearnedUUIDs then currentPlaceIndex = 1 end
    end
end

local function SmartUpgrade()
    -- GIẢM TỐC ĐỘ: Chỉ nâng cấp mỗi 2 giây, tránh lỗi đồng bộ EXP
    if tick() - lastUpgradeTime < 2 then return end
    lastUpgradeTime = tick()
    if not api_upgrade then return end
    
    local unitFolder = workspace:FindFirstChild("_UNITS")
    if not unitFolder then return end
    
    for _, unit in ipairs(unitFolder:GetChildren()) do
        -- Chỉ up các Model hợp lệ, chưa chết
        if unit:IsA("Model") and unit:FindFirstChild("Humanoid") and unit.Humanoid.Health > 0 then
            pcall(function() api_upgrade:InvokeServer(unit) end)
            task.wait(0.5) -- Nghỉ nửa giây giữa mỗi lần up 1 unit
        end
    end
end

-- ================= VÒNG LẶP CHÍNH =================
task.spawn(function()
    task.wait(3)
    while true do
        if IsInLobby() then
            HandleLobby()
        else
            if not hasScanned then AutoScanAndVerifyUUIDs() end
            
            SmartSpawn()
            SmartUpgrade()
            
            if not hasVotedStart and api_vote_start then
                pcall(function() api_vote_start:InvokeServer() end)
                hasVotedStart = true
            end
        end
        -- Vòng lặp chính chạy 3 giây/lần để máy "thở"
        task.wait(3) 
    end
end)
