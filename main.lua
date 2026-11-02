-- =====================================================================
-- [ANIME ADVENTURES] - AUTO FARM v4 (KẾT HỢP V3 FINAL & AUTO SCAN UUID)
-- Tự động dò UUID | Event-driven (Replay/Wave Skip) | Không spam
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

-- ================= CẤU HÌNH =================
local LOBBY_PLACE_ID = 8304191830 
local MapID = "_lobbytemplategreen3"
local LevelID = "namek_level_1"
local Difficulty = "Normal"

-- Danh sách CFrame đặt vị trí unit
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

local api_join          = getRemote("endpoints.client_to_server.request_join_lobby")
local api_lock          = getRemote("endpoints.client_to_server.request_lock_level")
local api_start         = getRemote("endpoints.client_to_server.request_start_game")
local api_vote          = getRemote("endpoints.client_to_server.vote_start")
local api_vote_skip     = getRemote("endpoints.client_to_server.vote_wave_skip")
local api_spawn         = getRemote("endpoints.client_to_server.spawn_unit")
local api_upgrade       = getRemote("endpoints.client_to_server.upgrade_unit_ingame")
local api_finished_vote = getRemote("endpoints.client_to_server.set_game_finished_vote")

-- Incoming Events
local endpoints_s2c = ReplicatedStorage:WaitForChild("endpoints"):WaitForChild("server_to_client")
local ev_start_vote_skip = endpoints_s2c:WaitForChild("start_vote_wave_skip")
local ev_show_message    = endpoints_s2c:WaitForChild("show_message")
local ev_unit_spawned    = endpoints_s2c:WaitForChild("unit_spawned")
local ev_game_finished   = endpoints_s2c:WaitForChild("game_finished")

-- ================= STATE =================
local LearnedUUIDs       = {}
local currentPlaceIndex  = 1
local hasScannedUUIDs    = false
local lastSpawnTime      = 0
local lastUpgradeTime    = 0
local moneyBlockTime     = 0

-- Lobby
local isInLobbyState = false
local hasVotedStart  = false

-- Replay
local isGameFinished  = false
local replayVoted     = false

local function log(msg) print("[AUTO-AA] " .. msg) end

-- ================= HELPERS =================
local function isEnemyUnit(unit)
    if not unit or not unit.Name then return true end
    local name = unit.Name
    if string.match(name, "^alien_soldier") then return true end
    if not unit:FindFirstChild("Humanoid") then return true end
    return false
end

local function CountPlayerUnits()
    local folder = workspace:FindFirstChild("_UNITS")
    if not folder then return 0 end
    local c = 0
    for _, u in ipairs(folder:GetChildren()) do
        if u:IsA("Model") and not isEnemyUnit(u) then c = c + 1 end
    end
    return c
end

local function ResetForNewGame()
    hasVotedStart     = false
    currentPlaceIndex = 1
    lastSpawnTime     = 0
    lastUpgradeTime   = 0
    moneyBlockTime    = 0
    isGameFinished    = false
    replayVoted       = false
    log("🔄 Đã reset state cho trận mới")
end

-- ================= QUÉT VÀ TEST UUID TỰ ĐỘNG =================
local function ScanAndLearnUUIDs()
    if hasScannedUUIDs then return end
    hasScannedUUIDs = true
    
    log("🔍 Đang quét tìm UUID...")
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
    
    -- Quét PlayerGui
    for _, v in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
        if v:IsA("StringValue") or v:IsA("Folder") then extract(v) end
    end
    -- Quét Nil Instances (Object ẩn)
    if getnilinstances then
        pcall(function() for _, v in ipairs(getnilinstances()) do extract(v) end end)
    end

    -- Nếu không tìm thấy gì, dùng hàng dự phòng
    if #uuids == 0 then
        table.insert(LearnedUUIDs, "{cf08f291-6071-4f30-ad4a-db345453a82e}")
        table.insert(LearnedUUIDs, "{337bcc00-f403-4722-87de-b5e2cf39c51c}")
        log("Không tìm thấy UUID trong bộ nhớ. Dùng UUID mặc định.")
        return
    end

    log("Tìm thấy " .. #uuids .. " mã tiềm năng. Đang test thử đặt Unit...")
    local testCFrame = PLACEMENT_CFRAMES[1]
    
    for i, uuid in ipairs(uuids) do
        if #LearnedUUIDs >= 6 then break end
        local success, result = pcall(function() return api_spawn:InvokeServer(uuid, testCFrame) end)
        if success and result == true then
            table.insert(LearnedUUIDs, uuid)
            log("✅ Đã học được Unit hợp lệ: " .. uuid)
        end
        task.wait(0.5) -- Nghỉ giữa các lần thử
    end
    
    if #LearnedUUIDs == 0 then
        table.insert(LearnedUUIDs, "{cf08f291-6071-4f30-ad4a-db345453a82e}")
        log("⚠️ Thử nghiệm thất bại. Dùng UUID mặc định.")
    end
end

-- ================= LOBBY =================
local function HandleLobby()
    if isInLobbyState then return end
    isInLobbyState = true
    log("Đang tự động vào sảnh và bắt đầu game...")
    task.spawn(function()
        pcall(function() api_join:InvokeServer(MapID) end); task.wait(1)
        pcall(function() api_lock:InvokeServer(MapID, LevelID, true, Difficulty) end); task.wait(1)
        pcall(function() api_start:InvokeServer(MapID) end)
        task.wait(10)
        isInLobbyState = false
    end)
end

-- ================= EVENT HANDLERS =================
ev_start_vote_skip.OnClientEvent:Connect(function()
    pcall(function() api_vote_skip:InvokeServer() end)
    log("⚡ Auto Wave Skip!")
end)

ev_show_message.OnClientEvent:Connect(function(msg, typeMsg)
    if msg == "Not enough money!" then
        moneyBlockTime = tick() + 3
    end
end)

ev_unit_spawned.OnClientEvent:Connect(function(unit)
    if isEnemyUnit(unit) and isGameFinished then
        ResetForNewGame()
    end
end)

ev_game_finished.OnClientEvent:Connect(function(data)
    if isGameFinished then return end
    isGameFinished = true
    replayVoted    = false
    
    log("🏁 Kết thúc game! Tiến hành auto-replay...")
    
    -- Tự động gửi Replay sau 3 giây
    task.delay(3, function()
        local ok, result = pcall(function()
            return api_finished_vote:InvokeServer("replay")
        end)
        if ok and result == true then
            replayVoted = true
            log("✅ Đã tự động Replay!")
        else
            log("⚠️ Replay thất bại, sẽ thử lại...")
        end
    end)
end)

-- ================= HÀNH ĐỘNG =================
local function SmartSpawn()
    if tick() - lastSpawnTime < 1.5 then return end
    if tick() < moneyBlockTime then return end
    
    if CountPlayerUnits() >= #PLACEMENT_CFRAMES then return end
    if not api_spawn or #LearnedUUIDs == 0 then return end
    
    lastSpawnTime = tick()
    local uuid = LearnedUUIDs[(currentPlaceIndex - 1) % #LearnedUUIDs + 1]
    
    for i = 1, #PLACEMENT_CFRAMES do
        local ok, result = pcall(function()
            return api_spawn:InvokeServer(uuid, PLACEMENT_CFRAMES[i])
        end)
        if ok and result == true then
            currentPlaceIndex = currentPlaceIndex + 1
            return
        end
    end
end

local function SmartUpgrade()
    if tick() - lastUpgradeTime < 2 then return end
    if tick() < moneyBlockTime then return end
    lastUpgradeTime = tick()
    
    if not api_upgrade then return end
    local folder = workspace:FindFirstChild("_UNITS")
    if not folder then return end
    
    for _, u in ipairs(folder:GetChildren()) do
        if u:IsA("Model") and not isEnemyUnit(u) then
            local ok, result = pcall(function() return api_upgrade:InvokeServer(u) end)
            -- Nếu không trả về true, có thể do thiếu tiền -> dừng up
            if ok and result ~= true then
                moneyBlockTime = tick() + 2
                return
            end
            task.wait(0.15)
        end
    end
end

local function TryVoteStart()
    if hasVotedStart or not api_vote then return end
    if pcall(function() api_vote:InvokeServer() end) then
        hasVotedStart = true
        log("✅ Đã gửi Vote Start.")
    end
end

local function TryReplayVote()
    if not isGameFinished or replayVoted then return end
    local ok, result = pcall(function() return api_finished_vote:InvokeServer("replay") end)
    if ok and result == true then
        replayVoted = true
        log("✅ Đã vote Replay lại (Kiểm tra định kỳ).")
    end
end

-- ================= MAIN LOOP =================
task.spawn(function()
    task.wait(3)
    local _dbg
    while true do
        if game.PlaceId == LOBBY_PLACE_ID then
            HandleLobby()
        else
            if not hasScannedUUIDs then
                ScanAndLearnUUIDs()
                task.wait(1)
            end
            
            SmartSpawn()
            SmartUpgrade()
            TryVoteStart()
            TryReplayVote()
            
            -- Log trạng thái mỗi 15 giây
            if not _dbg or tick() - _dbg > 15 then
                _dbg = tick()
                log(string.format("[STATUS] Units: %d | Finished: %s | Voted: %s", 
                    CountPlayerUnits(), tostring(isGameFinished), tostring(hasVotedStart)))
            end
        end
        task.wait(1)
    end
end)

log("🚀 Auto Farm v4 (Scan UUID + Event Driven) đã khởi động!")
