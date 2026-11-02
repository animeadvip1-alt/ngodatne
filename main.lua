-- =====================================================================
-- [ANIME ADVENTURES] - AUTO FARM v3.3 (Auto Detect UUID & Hook)
-- Fixes: Quét UUID siêu sâu, Hook hàm spawn để tự động lấy UUID
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
local REPLAY_MAX_ATTEMPTS = 15

-- Wave skip
local skipCooldown = 0

local function log(msg) print("[AUTO-AA] " .. msg) end

-- ================= HELPERS =================
local function isEnemyUnit(unit)
    if not unit or not unit.Name then return true end
    if string.match(unit.Name, "^alien_soldier") then return true end
    if not unit:FindFirstChildOfClass("Humanoid") then return true end
    return false
end

local function isMyUnit(u)
    if not u or not u:IsA("Model") then return false end
    local owner = u:GetAttribute("owner") or u:GetAttribute("Owner") or u:GetAttribute("user_id") or u:GetAttribute("UserId")
    if not owner then
        local ov = u:FindFirstChild("Owner") or u:FindFirstChild("owner")
        if ov and (ov:IsA("ObjectValue") or ov:IsA("StringValue")) then
            owner = ov.Value
        end
    end
    if owner == nil then return true end
    local s = tostring(owner)
    return s == tostring(LocalPlayer.UserId) or s == tostring(LocalPlayer.Name)
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

-- ================= FETCH UUID (V3.3 NÂNG CẤP) =================
local function FetchEquippedUnits()
    EquippedUUIDs = {}
    
    -- Danh sách UUID của Quest (Dựa vào log của bạn để loại bỏ)
    local QuestUUIDs = {
        "{fde93845-7cc2-4069-8804-205457280c67}",
        "{b53907e6-260d-4d6b-9879-25775125e6b8}",
        "{201029bb-4532-4307-a6c0-b14ea2e2bf43}",
        "{27ad82f9-6fd3-49c3-b1c4-6723f3000068}"
    }

    local function isQuest(uuid)
        for _, q in ipairs(QuestUUIDs) do
            if q == uuid then return true end
        end
        return false
    end

    -- Quét đệ quy mọi ngóc ngách
    local function scanObject(obj, depth)
        if not obj or depth > 12 then return end
        
        -- 1. Quét Tên, Giá trị (Value), và Chữ (Text)
        local stringsToCheck = { obj.Name }
        
        if obj:IsA("StringValue") or obj:IsA("IntValue") or obj:IsA("NumberValue") then
            table.insert(stringsToCheck, tostring(obj.Value))
        elseif obj:IsA("TextLabel") or obj:IsA("TextBox") or obj:IsA("TextButton") then
            table.insert(stringsToCheck, tostring(obj.Text))
        end
        
        -- Quét thêm Attributes
        for _, v in pairs(obj:GetAttributes()) do
            table.insert(stringsToCheck, tostring(v))
        end

        for _, str in ipairs(stringsToCheck) do
            -- Regex tìm UUID (có ngoặc nhọn)
            for uuid in string.gmatch(str, "({%x+%-%x+%-%x+%-%x+%-%x+})") do
                if not isQuest(uuid) and not table.find(EquippedUUIDs, uuid) then
                    table.insert(EquippedUUIDs, uuid)
                end
            end
        end
        
        -- Đệ quy xuống các object con
        for _, child in ipairs(obj:GetChildren()) do
            scanObject(child, depth + 1)
        end
    end

    -- Bắt đầu quét
    pcall(function() scanObject(LocalPlayer.PlayerGui, 1) end)
    pcall(function() scanObject(ReplicatedStorage, 1) end)
    pcall(function() scanObject(workspace:FindFirstChild("_UNITS"), 1) end)

    if #EquippedUUIDs == 0 then
        log("⚠️ CẢNH BÁO: Không tìm thấy UUID nào tự động! Hãy tự tay đặt 1 unit trong game để script tự học UUID.")
    else
        log("✅ Đã tìm thấy " .. #EquippedUUIDs .. " UUID Unit (Đã lọc bỏ Quest):")
        for i, id in ipairs(EquippedUUIDs) do
            log("   ["..i.."] " .. id)
        end
    end
    
    hasFetchedUnits = true
end

-- ================= HOOK API SPAWN (TỰ ĐỘNG HỌC UUID) =================
-- Nếu bạn tự tay đặt unit nào, script sẽ tự động thu thập UUID đó
if api_spawn and typeof(hookfunction) == "function" then
    local oldInvoke = hookfunction(api_spawn.InvokeServer, function(self, uuid, cframe)
        if type(uuid) == "string" and string.match(uuid, "^{%x+%-%x+%-%x+%-%x+%-%x+}$") then
            if not table.find(EquippedUUIDs, uuid) then
                table.insert(EquippedUUIDs, uuid)
                log("🎯 Hook thành công! Đã học được UUID Unit mới: " .. uuid)
            end
        end
        return oldInvoke(self, uuid, cframe)
    end)
else
    log("⚠️ Executor không hỗ trợ hookfunction. Sẽ dùng phương pháp quét UI.")
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

        local t0 = os.clock()
        while game.PlaceId == startPlaceId and (os.clock() - t0) < 15 do
            task.wait(0.5)
        end
        isInLobbyState = false
    end)
end

-- ================= EVENT HANDLERS =================
ev_start_vote_skip.OnClientEvent:Connect(function()
    if os.clock() - skipCooldown < 1 then return end
    skipCooldown = os.clock()
    pcall(function() api_vote_skip:InvokeServer() end)
end)

ev_show_message.OnClientEvent:Connect(function(msg, typeMsg)
    if msg == "Not enough money!" then
        moneyBlockTime = os.clock() + 3
    end
end)

ev_unit_spawned.OnClientEvent:Connect(function(unit)
    if isEnemyUnit(unit) and isGameFinished then
        ResetForNewGame()
    end
end)

ev_game_finished.OnClientEvent:Connect(function(data)
    if isGameFinished then return end
    isGameFinished  = true
    replayVoted     = false
    lastVoteAttempt = 0
    replayAttempts  = 0
    log("🏁 Kết thúc game! Tiến hành auto-replay...")
end)

ev_vote_replay.OnClientEvent:Connect(function(current, needed)
    current = tonumber(current) or 0
    needed  = tonumber(needed) or 0
    log(string.format("🗳️ Trạng thái Vote Replay: %d/%d", current, needed))
end)

-- ================= SMART SPAWN (CẬP NHẬT LOGIC CHỐNG KẸT) =================
local function SmartSpawn()
    if os.clock() - lastSpawnTime < 1.5 then return end
    if os.clock() < moneyBlockTime then return end
    if CountPlayerUnits() >= #PLACEMENT_CFRAMES then return end
    if not api_spawn or #EquippedUUIDs == 0 then return end

    lastSpawnTime = os.clock()
    
    -- Tìm CFrame trống
    local targetCFrame = nil
    local cframeIndex = nil
    for i = 1, #PLACEMENT_CFRAMES do
        if not placementCooldowns[i] or (os.clock() - placementCooldowns[i]) > 5 then
            targetCFrame = PLACEMENT_CFRAMES[i]
            cframeIndex = i
            break
        end
    end
    
    if not targetCFrame then return end
    
    -- Lấy UUID (xoay vòng)
    local uuid = EquippedUUIDs[(currentPlaceIndex - 1) % #EquippedUUIDs + 1]
    
    local ok, result = pcall(function()
        return api_spawn:InvokeServer(uuid, targetCFrame)
    end)
    
    -- Luôn tăng index để tránh kẹt ở một UUID bị lỗi
    currentPlaceIndex = currentPlaceIndex + 1 
    
    if ok and result == true then
        placementCooldowns[cframeIndex] = nil
    else
        -- Nếu lỗi, đưa CFrame đó vào cooldown và thử UUID tiếp theo ở vòng lặp sau
        placementCooldowns[cframeIndex] = os.clock()
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
        if u:IsA("Model") and not isEnemyUnit(u) and isMyUnit(u) then
            local ok = pcall(function()
                return api_upgrade:InvokeServer(u)
            end)
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

    local ok, result = pcall(function() return api_vote:InvokeServer() end)
    if ok and result == true then
        hasVotedStart = true
        log("✅ Đã gửi Vote Start thành công.")
    end
end

-- ================= VOTE REPLAY =================
local function TryReplayVote()
    if not isGameFinished or replayVoted then return end
    if os.clock() - lastVoteAttempt < 2 then return end
    lastVoteAttempt = os.clock()

    if replayAttempts >= REPLAY_MAX_ATTEMPTS then
        log("⏱️ Vote replay timeout. Force reset state.")
        ResetForNewGame()
        return
    end

    replayAttempts = replayAttempts + 1
    local ok, result = pcall(function() return api_finished_vote:InvokeServer("replay") end)

    if ok and result == true then
        replayVoted    = true
        replayAttempts = 0
        log("✅ Đã bỏ phiếu Replay thành công!")
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
                task.wait(2) -- Đợi 2s để UI load xong mới quét lại nếu chưa thấy
                if #EquippedUUIDs == 0 then hasFetchedUnits = false end
            end

            SmartSpawn()
            SmartUpgrade()
            TryVoteStart()
            TryReplayVote()

            if not _dbg or os.clock() - _dbg > 15 then
                _dbg = os.clock()
                log(string.format("[TRẠNG THÁI] Units=%d | Finished=%s | Voted=%s | ReplayAttempts=%d",
                    CountPlayerUnits(), tostring(isGameFinished), tostring(replayVoted), replayAttempts))
            end
        end
        task.wait(1)
    end
end)

log("🚀 Khởi chạy thành công Auto Farm v3.3 (Auto Detect UUID & Hook)!")
