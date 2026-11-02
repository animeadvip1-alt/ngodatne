-- =====================================================================
-- [ANIME ADVENTURES] - AUTO FARM v3.1 FINAL (Fixed Critical Bugs)
-- Fixes: UUID regex | Vote Start retry | Upgrade owner filter | Replay timeout
-- Zero UI | Không spam log/RAM | Auto vote replay khi game_finished
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

-- ================= CẤU HÌNH =================
local LOBBY_PLACE_ID = 8304191830
local MapID = "_lobbytemplategreen3"
local LevelID = "namek_level_1"
local Difficulty = "Normal"

-- Danh sách CFrame đặt vị trí unit (có thể điều chỉnh tùy map)
local PLACEMENT_CFRAMES = {
    CFrame.new(-2944.945556640625, 91.806205749511719, -690.08197021484375),
    CFrame.new(-2943.427978515625, 91.806205749511719, -692.01861572265625),
    CFrame.new(-2946.0390625, 91.80621337890625, -692.96728515625),
    CFrame.new(-2945.37353515625, 91.80621337890625, -694.9530029296875),
    CFrame.new(-2943.212890625, 91.806205749511719, -695.11309814453125),
}

-- ================= LẤY API =================
local function getRemote(path)
    local current = ReplicatedStorage
    for part in string.gmatch(path, "[^.]+") do
        if current then current = current:FindFirstChild(part) end
    end
    return current
end

-- API Calls
local api_join          = getRemote("endpoints.client_to_server.request_join_lobby")
local api_lock          = getRemote("endpoints.client_to_server.request_lock_level")
local api_start         = getRemote("endpoints.client_to_server.request_start_game")
local api_vote          = getRemote("endpoints.client_to_server.vote_start")
local api_vote_skip     = getRemote("endpoints.client_to_server.vote_wave_skip")
local api_spawn         = getRemote("endpoints.client_to_server.spawn_unit")
local api_upgrade       = getRemote("endpoints.client_to_server.upgrade_unit_ingame")
local api_finished_vote = getRemote("endpoints.client_to_server.set_game_finished_vote")

-- Incoming Events
local endpoints_s2c      = ReplicatedStorage:WaitForChild("endpoints"):WaitForChild("server_to_client")
local ev_start_vote_skip = endpoints_s2c:WaitForChild("start_vote_wave_skip")
local ev_show_message    = endpoints_s2c:WaitForChild("show_message")
local ev_unit_spawned    = endpoints_s2c:WaitForChild("unit_spawned")
local ev_game_finished   = endpoints_s2c:WaitForChild("game_finished")
local ev_vote_replay     = endpoints_s2c:WaitForChild("vote_replay_changed")

-- ================= STATE =================
local EquippedUUIDs      = {}
local currentPlaceIndex  = 1
local hasFetchedUnits    = false
local lastSpawnTime      = 0
local lastUpgradeTime    = 0
local moneyBlockTime     = 0
local placementCooldowns = {}

-- Lobby
local isInLobbyState         = false
local hasVotedStart          = false
local lastVoteStartAttempt   = 0

-- Replay
local isGameFinished   = false
local replayVoted      = false
local lastVoteAttempt  = 0
local replayAttempts   = 0
local REPLAY_MAX_ATTEMPTS = 15   -- ~30s (mỗi 2s)

-- Wave skip
local skipCooldown = 0

local function log(msg) print("[AUTO-AA] " .. msg) end

-- ================= HELPERS =================
-- Kiểm tra xem unit có phải kẻ địch hay không (dựa trên log thực tế)
local function isEnemyUnit(unit)
    if not unit or not unit.Name then return true end
    local name = unit.Name
    -- Quái trong AA có tên bắt đầu bằng "alien_soldier"
    if string.match(name, "^alien_soldier") then
        return true
    end
    -- Không có Humanoid -> coi như đã chết / không hợp lệ
    if not unit:FindFirstChildOfClass("Humanoid") then
        return true
    end
    return false
end

-- Kiểm tra unit có phải CỦA MÌNH hay không (fix bug upgrade unit player khác)
local function isMyUnit(u)
    if not u or not u:IsA("Model") then return false end

    -- Thử nhiều kiểu attribute phổ biến trong AA
    local owner = u:GetAttribute("owner")
               or u:GetAttribute("Owner")
               or u:GetAttribute("user_id")
               or u:GetAttribute("UserId")

    -- Fallback qua ObjectValue / StringValue trong model
    if not owner then
        local ov = u:FindFirstChild("Owner") or u:FindFirstChild("owner")
        if ov and (ov:IsA("ObjectValue") or ov:IsA("StringValue")) then
            owner = ov.Value
        end
    end

    -- Không xác định được owner -> giữ hành vi cũ (coi như của mình)
    if owner == nil then return true end

    local s = tostring(owner)
    return s == tostring(LocalPlayer.UserId)
        or s == tostring(LocalPlayer.Name)
end

local function CountPlayerUnits()
    local folder = workspace:FindFirstChild("_UNITS")
    if not folder then return 0 end
    local c = 0
    for _, u in ipairs(folder:GetChildren()) do
        if u:IsA("Model") and not isEnemyUnit(u) and isMyUnit(u) then
            c = c + 1
        end
    end
    return c
end

local function ResetForNewGame()
    hasVotedStart         = false
    hasFetchedUnits       = false
    currentPlaceIndex     = 1
    placementCooldowns    = {}
    lastSpawnTime         = 0
    lastUpgradeTime       = 0
    moneyBlockTime        = 0
    isGameFinished        = false
    replayVoted           = false
    lastVoteAttempt       = 0
    lastVoteStartAttempt  = 0
    replayAttempts        = 0
    log("🔄 Đã reset state cho trận mới")
end

-- ================= FETCH UUID =================
local function FetchEquippedUnits()
    EquippedUUIDs = {}
    pcall(function()
        for _, gui in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
            if gui:IsA("StringValue") or gui:IsA("Folder") then
                local str = tostring(gui.Name) .. tostring(gui.Value)
                -- FIX: escape dấu "-" bằng "%-" trong Lua pattern
                for uuid in string.gmatch(str, "({%x+%-%x+%-%x+%-%x+%-%x+})") do
                    if not table.find(EquippedUUIDs, uuid) then
                        table.insert(EquippedUUIDs, uuid)
                    end
                end
            end
        end
    end)
    -- Fallback UUID mặc định nếu không quét được
    if #EquippedUUIDs == 0 then
        table.insert(EquippedUUIDs, "{cf08f291-6071-4f30-ad4a-db345453a82e}")
        log("⚠️ Không quét được UUID, dùng fallback mặc định")
    end
    hasFetchedUnits = true
    log("Đã lấy thành công " .. #EquippedUUIDs .. " UUID unit.")
end

-- ================= LOBBY =================
local function HandleLobby()
    if isInLobbyState then return end
    isInLobbyState = true
    log("Đang tự động vào sảnh và bắt đầu game...")
    task.spawn(function()
        local startPlaceId = game.PlaceId

        pcall(function() api_join:InvokeServer(MapID) end); task.wait(1)
        pcall(function() api_lock:InvokeServer(MapID, LevelID, true, Difficulty) end); task.wait(1)
        pcall(function() api_start:InvokeServer(MapID) end)

        -- Chờ tối đa 15s hoặc tới khi place thay đổi (tránh block mù 10s)
        local t0 = os.clock()
        while game.PlaceId == startPlaceId and (os.clock() - t0) < 15 do
            task.wait(0.5)
        end

        isInLobbyState = false
    end)
end

-- ================= EVENT HANDLERS =================

-- Auto Wave Skip
ev_start_vote_skip.OnClientEvent:Connect(function()
    if os.clock() - skipCooldown < 1 then return end
    skipCooldown = os.clock()
    pcall(function() api_vote_skip:InvokeServer() end)
    log("⚡ Auto Wave Skip thành công!")
end)

-- Xử lý khi thiếu tiền (server gửi message "Not enough money!")
ev_show_message.OnClientEvent:Connect(function(msg, typeMsg)
    if msg == "Not enough money!" then
        -- Tạm dừng spawn/upgrade 3s để tích lũy tiền
        moneyBlockTime = os.clock() + 3
    end
end)

-- Detect trận mới thông qua sự kiện spawn quái sau khi game kết thúc
ev_unit_spawned.OnClientEvent:Connect(function(unit)
    if isEnemyUnit(unit) and isGameFinished then
        ResetForNewGame()
    end
end)

-- Game Finished -> Log thống kê (vote replay xử lý trong main loop)
ev_game_finished.OnClientEvent:Connect(function(data)
    if isGameFinished then return end
    isGameFinished  = true
    replayVoted     = false
    lastVoteAttempt = 0
    replayAttempts  = 0

    local stats = data and data.stats
    if stats then
        log(string.format("🏁 Kết thúc game! Wave %s/%s | Chiến thắng=%s | Thời gian=%.1fs",
            tostring(stats.waves_completed),
            tostring(stats.num_waves),
            tostring(data.victory),
            stats.time_taken or 0))
    else
        log("🏁 Kết thúc game! Tiến hành auto-replay...")
    end

    if data then
        if data.new_units and #data.new_units > 0 then
            log("🎁 Nhận được " .. #data.new_units .. " unit mới!")
        end
        if data.gold_reward and data.gold_reward > 0 then
            log("💰 Nhận thưởng Gold: +" .. data.gold_reward)
        end
    end
end)

ev_vote_replay.OnClientEvent:Connect(function(current, needed)
    current = tonumber(current) or 0
    needed  = tonumber(needed) or 0
    log(string.format("🗳️ Trạng thái Vote Replay: %d/%d", current, needed))
end)

-- ================= SMART SPAWN =================
local function SmartSpawn()
    if os.clock() - lastSpawnTime < 1.5 then return end
    if os.clock() < moneyBlockTime then return end

    if CountPlayerUnits() >= #PLACEMENT_CFRAMES then return end
    if not api_spawn or #EquippedUUIDs == 0 then return end

    lastSpawnTime = os.clock()
    local uuid = EquippedUUIDs[(currentPlaceIndex - 1) % #EquippedUUIDs + 1]

    for i = 1, #PLACEMENT_CFRAMES do
        if not placementCooldowns[i] or (os.clock() - placementCooldowns[i]) > 5 then
            local ok, result = pcall(function()
                return api_spawn:InvokeServer(uuid, PLACEMENT_CFRAMES[i])
            end)
            if ok and result == true then
                currentPlaceIndex = currentPlaceIndex + 1
            else
                -- Vị trí bị lỗi/chặn -> chờ 5s trước khi thử lại
                placementCooldowns[i] = os.clock()
            end
            return
        end
    end
end

-- ================= SMART UPGRADE =================
local function SmartUpgrade()
    if os.clock() - lastUpgradeTime < 2 then return end
    if os.clock() < moneyBlockTime then return end
    lastUpgradeTime = os.clock()

    if not api_upgrade then return end
    local folder = workspace:FindFirstChild("_UNITS")
    if not folder then return end

    for _, u in ipairs(folder:GetChildren()) do
        -- FIX: chỉ upgrade unit CỦA MÌNH (loại quái + unit player khác)
        if u:IsA("Model") and not isEnemyUnit(u) and isMyUnit(u) then
            local ok = pcall(function()
                return api_upgrade:InvokeServer(u)
            end)
            -- KHÔNG set moneyBlockTime ở đây nữa
            -- (để ev_show_message "Not enough money!" tự xử lý)
            task.wait(0.15)
            if not ok then break end
        end
    end
end

-- ================= VOTE START =================
local function TryVoteStart()
    if hasVotedStart or not api_vote then return end
    if os.clock() - lastVoteStartAttempt < 2 then return end
    lastVoteStartAttempt = os.clock()

    local ok, result = pcall(function()
        return api_vote:InvokeServer()
    end)

    if ok and result == true then
        hasVotedStart = true
        log("✅ Đã gửi Vote Start thành công.")
    else
        log(string.format("⚠️ Vote Start fail (ok=%s, result=%s), retry sau 2s",
            tostring(ok), tostring(result)))
    end
end

-- ================= VOTE REPLAY =================
local function TryReplayVote()
    if not isGameFinished or replayVoted then return end
    if os.clock() - lastVoteAttempt < 2 then return end
    lastVoteAttempt = os.clock()

    -- Nếu đã thử quá nhiều lần -> force reset để không kẹt state
    if replayAttempts >= REPLAY_MAX_ATTEMPTS then
        log("⏱️ Vote replay timeout sau " .. REPLAY_MAX_ATTEMPTS ..
            " lần. Force reset state.")
        ResetForNewGame()
        return
    end

    replayAttempts = replayAttempts + 1

    local ok, result = pcall(function()
        return api_finished_vote:InvokeServer("replay")
    end)

    if ok and result == true then
        replayVoted    = true
        replayAttempts = 0
        log("✅ Đã bỏ phiếu Replay thành công!")
    else
        log(string.format("⚠️ Vote replay lần %d/%d fail (ok=%s, result=%s)",
            replayAttempts, REPLAY_MAX_ATTEMPTS,
            tostring(ok), tostring(result)))
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
            if not hasFetchedUnits then
                FetchEquippedUnits()
                task.wait(1)
            end

            SmartSpawn()
            SmartUpgrade()
            TryVoteStart()
            TryReplayVote()

            -- In trạng thái định kỳ mỗi 15s (không spam log)
            if not _dbg or os.clock() - _dbg > 15 then
                _dbg = os.clock()
                log(string.format("[TRẠNG THÁI] Units=%d | Finished=%s | Voted=%s | ReplayAttempts=%d",
                    CountPlayerUnits(),
                    tostring(isGameFinished),
                    tostring(replayVoted),
                    replayAttempts))
            end
        end
        task.wait(1)
    end
end)

log("🚀 Khởi chạy thành công Auto Farm v3.1 FINAL (4 bug Critical đã fix)!")
