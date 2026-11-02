-- =====================================================================
-- [ANIME ADVENTURES] AUTO FARM v5 - MOBILE EXECUTOR
-- Tu dong dat HET unit dang trang bi | Auto upgrade | Wave skip | Replay
-- Khong dung file/thu vien ngoai, co nut bat/tat cam ung
-- =====================================================================

-- ---------- Tuong thich executor mobile ----------
local task = task or { wait = wait, spawn = spawn, delay = delay }
local getnil = getnilinstances or get_nil_instances
local cloneref = cloneref or function(x) return x end

local Players           = cloneref(game:GetService("Players"))
local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
local UserInputService  = cloneref(game:GetService("UserInputService"))
local LocalPlayer       = Players.LocalPlayer

-- Chong chay 2 lan
if getgenv then
    if getgenv().AA_V5_LOADED then
        warn("[AUTO-AA] Script dang chay roi!")
        return
    end
    getgenv().AA_V5_LOADED = true
end

-- ================= CAU HINH =================
local CFG = {
    LOBBY_PLACE_ID = 8304191830,
    MapID          = "_lobbytemplategreen3",
    LevelID        = "namek_level_1",
    Difficulty     = "Normal",
    MAX_UNITS      = 6,      -- so unit toi da duoc trang bi
    SPAWN_DELAY    = 1.2,    -- giay giua cac dot dat unit
    UPGRADE_DELAY  = 2,      -- giay giua cac dot nang cap
    AUTO_UPGRADE   = true,
    AUTO_REPLAY    = true,
    AUTO_SKIP      = true,
}

-- Vi tri dat unit (sua theo map cua ban)
local PLACEMENT_CFRAMES = {
    CFrame.new(-2944.9455, 91.8062, -690.0819),
    CFrame.new(-2943.4279, 91.8062, -692.0186),
    CFrame.new(-2946.0390, 91.8062, -692.9672),
    CFrame.new(-2945.3735, 91.8062, -694.9530),
    CFrame.new(-2943.2128, 91.8062, -695.1130),
    CFrame.new(-2941.3200, 91.8062, -699.8656),
}

-- ================= STATE =================
local Enabled         = true
local LearnedUUIDs    = {}   -- danh sach unit hop le (da trang bi)
local BadUUIDs        = {}   -- uuid da thu va that bai khi chua co unit nao
local scanCount       = 0
local lastScan        = 0
local lastSpawnTime   = 0
local lastUpgradeTime = 0
local moneyBlockTime  = 0
local isInLobbyState  = false
local hasVotedStart   = false
local isGameFinished  = false
local replayVoted     = false
local statusText      = "Khoi dong..."

local function log(msg) print("[AUTO-AA] " .. tostring(msg)) end

-- ================= LAY REMOTE =================
local function getRemote(path)
    local cur = ReplicatedStorage
    for _, part in ipairs(string.split(path, ".")) do
        if not cur then return nil end
        cur = cur:FindFirstChild(part) or cur:WaitForChild(part, 5)
    end
    return cur
end

local api_join          = getRemote("endpoints.client_to_server.request_join_lobby")
local api_lock          = getRemote("endpoints.client_to_server.request_lock_level")
local api_start         = getRemote("endpoints.client_to_server.request_start_game")
local api_vote          = getRemote("endpoints.client_to_server.vote_start")
local api_vote_skip     = getRemote("endpoints.client_to_server.vote_wave_skip")
local api_spawn         = getRemote("endpoints.client_to_server.spawn_unit")
local api_upgrade       = getRemote("endpoints.client_to_server.upgrade_unit_ingame")
local api_finished_vote = getRemote("endpoints.client_to_server.set_game_finished_vote")

local s2c = ReplicatedStorage:WaitForChild("endpoints", 10)
s2c = s2c and s2c:WaitForChild("server_to_client", 10)

local function getEvent(name) return s2c and s2c:FindFirstChild(name) end
local ev_start_vote_skip = getEvent("start_vote_wave_skip")
local ev_show_message    = getEvent("show_message")
local ev_unit_spawned    = getEvent("unit_spawned")
local ev_game_finished   = getEvent("game_finished")

-- ================= HELPERS =================
local function isMyUnit(unit)
    if not unit or not unit:IsA("Model") then return false end
    local stats = unit:FindFirstChild("_stats")
    if stats then
        local p = stats:FindFirstChild("player")
        if p and p:IsA("ObjectValue") then
            return p.Value == LocalPlayer
        end
    end
    -- du phong: loai enemy theo ten / thieu Humanoid
    if string.match(unit.Name, "^alien_soldier") then return false end
    return unit:FindFirstChild("Humanoid") ~= nil
end

local function isEnemyUnit(unit)
    return not isMyUnit(unit)
end

local function getMyUnits()
    local list = {}
    local folder = workspace:FindFirstChild("_UNITS")
    if not folder then return list end
    for _, u in ipairs(folder:GetChildren()) do
        if isMyUnit(u) then table.insert(list, u) end
    end
    return list
end

local function isSpotTaken(cf, myUnits)
    for _, u in ipairs(myUnits) do
        local ok, pos = pcall(function() return u:GetPivot().Position end)
        if ok and (pos - cf.Position).Magnitude < 2.5 then
            return true
        end
    end
    return false
end

local function ResetForNewGame()
    hasVotedStart   = false
    lastSpawnTime   = 0
    lastUpgradeTime = 0
    moneyBlockTime  = 0
    isGameFinished  = false
    replayVoted     = false
    log("Reset state cho tran moi")
end

-- ================= QUET UNIT DA TRANG BI =================
-- Pattern UUID dang {xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx}
local UUID_PAT = "%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x"

local function findUUIDs(str, out, seen, priority)
    for raw in string.gmatch(str, UUID_PAT) do
        local uuid = "{" .. string.lower(raw) .. "}"
        if not seen[uuid] and not BadUUIDs[uuid] then
            seen[uuid] = true
            table.insert(out, { uuid = uuid, priority = priority })
        end
    end
end

local function pathHasLoadoutHint(obj)
    local ok, full = pcall(function() return obj:GetFullName() end)
    if not ok then return false end
    full = string.lower(full)
    return full:find("hotbar") or full:find("loadout") or full:find("equip")
        or full:find("unitbar") or full:find("units") or false
end

local function gatherCandidates()
    local out, seen = {}, {}

    local function scan(obj, prio)
        local ok, str = pcall(function()
            local s = tostring(obj.Name)
            if obj:IsA("ValueBase") then s = s .. tostring(obj.Value) end
            return s
        end)
        if ok then findUUIDs(str, out, seen, prio) end
        -- atribut cung co the chua uuid
        pcall(function()
            for _, v in pairs(obj:GetAttributes()) do
                if type(v) == "string" then findUUIDs(v, out, seen, prio) end
            end
        end)
    end

    -- 1) PlayerGui (uu tien cac object nam trong hotbar/loadout)
    pcall(function()
        for _, v in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
            scan(v, pathHasLoadoutHint(v) and 1 or 3)
        end
    end)
    -- 2) Player + cac value duoi LocalPlayer (_stats, data...)
    pcall(function()
        for _, v in ipairs(LocalPlayer:GetDescendants()) do
            scan(v, pathHasLoadoutHint(v) and 1 or 2)
        end
    end)
    -- 3) Nil instances (neu executor ho tro)
    if getnil then
        pcall(function()
            for _, v in ipairs(getnil()) do scan(v, 4) end
        end)
    end

    table.sort(out, function(a, b) return a.priority < b.priority end)
    return out
end

-- Thu dat tung ung vien; ung vien nao server chap nhan thi la unit da trang bi
local function ScanAndLearnUUIDs()
    scanCount = scanCount + 1
    lastScan = tick()
    statusText = "Dang quet unit (lan " .. scanCount .. ")..."
    local cands = gatherCandidates()
    log("Quet lan " .. scanCount .. ": " .. #cands .. " ma tiem nang")

    local learnedSet = {}
    for _, u in ipairs(LearnedUUIDs) do learnedSet[u] = true end

    local myUnits = getMyUnits()
    for _, c in ipairs(cands) do
        if #LearnedUUIDs >= CFG.MAX_UNITS then break end
        if not learnedSet[c.uuid] then
            for _, cf in ipairs(PLACEMENT_CFRAMES) do
                if not isSpotTaken(cf, myUnits) then
                    local ok, result = pcall(function()
                        return api_spawn:InvokeServer(c.uuid, cf)
                    end)
                    if ok and result == true then
                        table.insert(LearnedUUIDs, c.uuid)
                        learnedSet[c.uuid] = true
                        log("Hoc duoc unit: " .. c.uuid)
                        myUnits = getMyUnits()
                    elseif tick() < moneyBlockTime then
                        -- that bai vi thieu tien -> uuid co the van dung, thu lai sau
                        task.wait(0.3)
                    else
                        BadUUIDs[c.uuid] = true
                    end
                    task.wait(0.4)
                    break
                end
            end
        end
    end
end

-- ================= LOBBY =================
local function HandleLobby()
    if isInLobbyState then return end
    isInLobbyState = true
    statusText = "Dang o sanh..."
    log("Vao sanh va bat dau game...")
    task.spawn(function()
        pcall(function() api_join:InvokeServer(CFG.MapID) end)
        task.wait(1)
        pcall(function() api_lock:InvokeServer(CFG.MapID, CFG.LevelID, true, CFG.Difficulty) end)
        task.wait(1)
        pcall(function() api_start:InvokeServer(CFG.MapID) end)
        task.wait(10)
        isInLobbyState = false
    end)
end

-- ================= EVENT =================
if ev_start_vote_skip then
    ev_start_vote_skip.OnClientEvent:Connect(function()
        if not (Enabled and CFG.AUTO_SKIP) then return end
        pcall(function() api_vote_skip:InvokeServer() end)
        log("Auto Wave Skip")
    end)
end

if ev_show_message then
    ev_show_message.OnClientEvent:Connect(function(msg)
        if msg == "Not enough money!" then
            moneyBlockTime = tick() + 3
        end
    end)
end

if ev_unit_spawned then
    ev_unit_spawned.OnClientEvent:Connect(function(unit)
        if isGameFinished and unit and isEnemyUnit(unit) then
            ResetForNewGame()
        end
    end)
end

local function sendReplay()
    local ok, result = pcall(function()
        return api_finished_vote:InvokeServer("replay")
    end)
    if ok and result == true then
        replayVoted = true
        log("Da vote Replay")
        return true
    end
    return false
end

if ev_game_finished then
    ev_game_finished.OnClientEvent:Connect(function()
        if isGameFinished then return end
        isGameFinished = true
        replayVoted = false
        log("Ket thuc game")
        if Enabled and CFG.AUTO_REPLAY then
            task.delay(3, function()
                if not sendReplay() then log("Replay that bai, se thu lai") end
            end)
        end
    end)
end

-- ================= HANH DONG =================
-- Dat het unit: moi dot, thu dat moi unit da hoc vao cac cho trong
local function SmartSpawn()
    if tick() - lastSpawnTime < CFG.SPAWN_DELAY then return end
    if tick() < moneyBlockTime then return end
    if not api_spawn or #LearnedUUIDs == 0 then return end
    lastSpawnTime = tick()

    local myUnits = getMyUnits()
    if #myUnits >= #PLACEMENT_CFRAMES then return end

    for _, uuid in ipairs(LearnedUUIDs) do
        for _, cf in ipairs(PLACEMENT_CFRAMES) do
            if not isSpotTaken(cf, myUnits) then
                local ok, result = pcall(function()
                    return api_spawn:InvokeServer(uuid, cf)
                end)
                if ok and result == true then
                    myUnits = getMyUnits()
                    task.wait(0.3)
                    break -- sang unit ke tiep
                end
                if tick() < moneyBlockTime then return end -- het tien -> doi
                -- false: co the do gioi han so luong cua unit nay -> thu unit khac
                break
            end
        end
    end
end

local function SmartUpgrade()
    if not CFG.AUTO_UPGRADE or not api_upgrade then return end
    if tick() - lastUpgradeTime < CFG.UPGRADE_DELAY then return end
    if tick() < moneyBlockTime then return end
    lastUpgradeTime = tick()

    for _, u in ipairs(getMyUnits()) do
        if tick() < moneyBlockTime then return end
        local ok = pcall(function() api_upgrade:InvokeServer(u) end)
        if not ok then return end
        task.wait(0.2)
    end
end

local function TryVoteStart()
    if hasVotedStart or not api_vote then return end
    if pcall(function() api_vote:InvokeServer() end) then
        hasVotedStart = true
        log("Da gui Vote Start")
    end
end

-- ================= GIAO DIEN CAM UNG =================
local function buildGui()
    local gui = Instance.new("ScreenGui")
    gui.Name = "AAv5Panel"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 999
    local parented = false
    if gethui then parented = pcall(function() gui.Parent = gethui() end) end
    if not parented then
        parented = pcall(function() gui.Parent = game:GetService("CoreGui") end)
    end
    if not parented or not gui.Parent then gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 190, 0, 92)
    frame.Position = UDim2.new(0, 10, 0.35, 0)
    frame.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
    frame.BackgroundTransparency = 0.1
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Parent = gui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 22)
    title.BackgroundTransparency = 1
    title.Text = "AA Auto Farm v5 (keo de di chuyen)"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextSize = 11
    title.Font = Enum.Font.GothamBold
    title.Parent = frame

    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -10, 0, 34)
    status.Position = UDim2.new(0, 5, 0, 22)
    status.BackgroundTransparency = 1
    status.TextWrapped = true
    status.TextColor3 = Color3.fromRGB(200, 220, 255)
    status.TextSize = 11
    status.Font = Enum.Font.Gotham
    status.Text = statusText
    status.Parent = frame

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -16, 0, 26)
    btn.Position = UDim2.new(0, 8, 1, -32)
    btn.BackgroundColor3 = Color3.fromRGB(46, 160, 90)
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.TextSize = 13
    btn.Font = Enum.Font.GothamBold
    btn.Text = "DANG BAT"
    btn.Parent = frame
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

    btn.Activated:Connect(function()
        Enabled = not Enabled
        btn.Text = Enabled and "DANG BAT" or "DA TAT"
        btn.BackgroundColor3 = Enabled and Color3.fromRGB(46, 160, 90) or Color3.fromRGB(180, 55, 55)
    end)

    -- keo tha bang cam ung / chuot
    local dragging, dragStart, startPos
    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseMovement) then
            local d = input.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)

    task.spawn(function()
        while gui.Parent do
            status.Text = statusText
            task.wait(1)
        end
    end)
end

pcall(buildGui)

-- ================= VONG LAP CHINH =================
task.spawn(function()
    task.wait(3)
    while true do
        if Enabled then
            local okLoop, err = pcall(function()
                if game.PlaceId == CFG.LOBBY_PLACE_ID then
                    HandleLobby()
                else
                    -- quet unit: lan dau, hoac thu lai moi 15s neu chua du unit
                    if workspace:FindFirstChild("_UNITS")
                        and #LearnedUUIDs < CFG.MAX_UNITS
                        and scanCount < 8
                        and tick() - lastScan > 15 then
                        ScanAndLearnUUIDs()
                    end

                    SmartSpawn()
                    SmartUpgrade()
                    TryVoteStart()
                    if CFG.AUTO_REPLAY and isGameFinished and not replayVoted then
                        sendReplay()
                    end

                    statusText = string.format("Unit hoc: %d | Dang dat: %d/%d\nKet thuc: %s | Replay: %s",
                        #LearnedUUIDs, #getMyUnits(), #PLACEMENT_CFRAMES,
                        tostring(isGameFinished), tostring(replayVoted))
                end
            end)
            if not okLoop then log("Loi vong lap: " .. tostring(err)) end
        else
            statusText = "Da tat - bam nut de bat lai"
        end
        task.wait(1)
    end
end)

log("Auto Farm v5 (mobile) da khoi dong!")
