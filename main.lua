-- =====================================================================
-- [ANIME ADVENTURES] - FULL AUTO (FIX LỖI, TỰ ĐỘNG REPLAY & VOTE START)
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

-- ================= LẤY API =================
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
local api_replay = getRemote("endpoints.client_to_server.set_game_finished_vote")

-- Sự kiện báo kết thúc trận đấu (Từ file Log của bạn)
local event_game_finished = getRemote("endpoints.server_to_client.game_finished")

-- ================= BIẾN TOÀN CỤC =================
local LearnedUUIDs = {}
local currentPlaceIndex = 1
local lastSpawnTime = 0
local lastUpgradeTime = 0
local lastVoteTime = 0
local hasScanned = false
local isMatchFinished = false

local function log(msg) print("[AUTO-AA] " .. msg) end

-- ================= 1. TỰ ĐỘNG DÒ TÌM UUID =================
local function AutoScanAndVerifyUUIDs()
    if hasScanned then return end
    hasScanned = true
    log("Đang quét UUID...")
    
    local uuids = {}
    local seen = {}
    local function extract(obj)
        local s, str = pcall(function() return tostring(obj.Name) .. tostring(obj.Value) end)
        if s then
            for uuid in string.gmatch(str, "({%x+-%x+-%x+-%x+-%x+})") do
                if not seen[uuid] then table.insert(uuids, uuid) seen[uuid] = true end
            end
        end
    end
    
    for _, v in ipairs(Players.LocalPlayer.PlayerGui:GetDescendants()) do
        if v:IsA("StringValue") or v:IsA("Folder") then extract(v) end
    end
    if getnilinstances then
        pcall(function() for _, v in ipairs(getnilinstances()) do extract(v) end end)
    end

    if #uuids == 0 then
        table.insert(LearnedUUIDs, "{cf08f291-6071-4f30-ad4a-db345453a82e}")
        table.insert(LearnedUUIDs, "{337bcc00-f403-4722-87de-b5e2cf39c51c}")
        log("Dùng UUID mặc định.")
        return
    end

    local testCFrame = PLACEMENT_CFRAMES[1]
    for i, uuid in ipairs(uuids) do
        if #LearnedUUIDs >= 6 then break end
        local success, result = pcall(function() return api_spawn:InvokeServer(uuid, testCFrame) end)
        if success and result == true then
            table.insert(LearnedUUIDs, uuid)
        end
        task.wait(0.5)
    end
    
    if #LearnedUUIDs == 0 then
        table.insert(LearnedUUIDs, "{cf08f291-6071-4f30-ad4a-db345453a82e}")
    end
    log("Đã tìm thấy " .. #LearnedUUIDs .. " UUID hợp lệ.")
end

-- ================= 2. CÁC HÀM KIỂM TRA =================
local function IsInLobby()
    local mapConfig = workspace:FindFirstChild("_MAP_CONFIG")
    if mapConfig and mapConfig:FindFirstChild("IsLobby") then return mapConfig.IsLobby.Value end
    return false
end

-- ================= 3. HOOK TỰ ĐỘNG REPLAY =================
if event_game_finished then
    event_game_finished.OnClientEvent:Connect(function(data)
        -- Nếu trận đấu kết thúc (thắng hoặc thua), tự động gửi Replay
        log("Phát hiện kết thúc trận! Tự động Replay sau 5s...")
        isMatchFinished = true
        task.wait(5) -- Chờ 5 giây cho bảng Victory hiện lên rồi Replay
        pcall(function() api_replay:InvokeServer("replay") end)
        isMatchFinished = false
        hasScanned = false -- Reset lại trạng thái để quét lại ở trận mới
    end)
end

-- ================= 4. HÀNH ĐỘNG CHÍNH =================
local function HandleLobby()
    log("Đang ở Lobby, tự động vào trận...")
    pcall(function() api_join:InvokeServer(MapID) end) task.wait(1)
    pcall(function() api_lock:InvokeServer(MapID, LevelID, true, Difficulty) end) task.wait(1)
    pcall(function() api_start:InvokeServer(MapID) end)
    hasScanned = false
    task.wait(10)
end

local function SmartSpawn()
    if tick() - lastSpawnTime < 2 then return end
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
    if tick() - lastUpgradeTime < 2 then return end
    lastUpgradeTime = tick()
    if not api_upgrade then return end
    
    local unitFolder = workspace:FindFirstChild("_UNITS")
    if not unitFolder then return end
    
    for _, unit in ipairs(unitFolder:GetChildren()) do
        if unit:IsA("Model") and unit:FindFirstChild("Humanoid") and unit.Humanoid.Health > 0 then
            pcall(function() api_upgrade:InvokeServer(unit) end)
            task.wait(0.3)
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
            if not isMatchFinished then
                if not hasScanned then AutoScanAndVerifyUUIDs() end
                
                SmartSpawn()
                SmartUpgrade()

                -- VOTE START: Cứ mỗi 15 giây gọi 1 lần (để bắt đầu các Wave mới)
                if tick() - lastVoteTime > 15 and api_vote_start then
                    pcall(function() api_vote_start:InvokeServer() end)
                    lastVoteTime = tick()
                    log("Đã Vote Start để sang Wave mới.")
                end
            end
        end
        task.wait(2) 
    end
end)
