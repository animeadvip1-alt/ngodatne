local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local Throw_Start = Remotes:WaitForChild("Throw_Start")
local Throw_MeterStarted = Remotes:WaitForChild("Throw_MeterStarted")
local Throw_Resolve = Remotes:WaitForChild("Throw_Resolve")
local Throw_Complete = Remotes:WaitForChild("Throw_Complete")
local Plot_EquipBest = Remotes:WaitForChild("Plot_EquipBest")
local Stand_Upgrade = Remotes:WaitForChild("Stand_Upgrade")

-- Thư mục & file nằm trong workspace của Delta
local HUB_DIR = "CatchStandHub"
local CONFIG_FILE = HUB_DIR .. "/settings.json"

local Config = {
    AutoThrowAndCatch = false,
    AutoEquipBest = false,
    AutoUpgradeStand = false,
    AutoMoveOnTooFar = true,

    TargetAccuracy = 0.96,
    ExtraWaitAfterFlight = 0.25,
    ThrowInterval = 0.3,
    UpgradeInterval = 2.5,
    FailBackoff = 1.2,

    SavedThrowCFrame = nil,
    PanelPosOffset = { 480, 75 },
}

local State = {
    IsThrowing = false,
    StatusText = "Idle",
    StatusMode = "idle",
}

-- =========================================================
-- HỆ THỐNG LƯU / ĐỌC DỮ LIỆU DELTA WORKSPACE
-- =========================================================
local function hasFileApi()
    return type(writefile) == "function"
        and type(readfile) == "function"
        and type(isfile) == "function"
end

local function ensureDir()
    if type(makefolder) == "function" and type(isfolder) == "function" then
        pcall(function()
            if not isfolder(HUB_DIR) then
                makefolder(HUB_DIR)
            end
        end)
    end
end

local function cframeToArray(cf)
    if not cf then
        return nil
    end
    local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
    return { x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 }
end

local function arrayToCFrame(arr)
    if type(arr) == "table" and #arr == 12 then
        local ok, cf = pcall(function()
            return CFrame.new(unpack(arr))
        end)
        if ok then
            return cf
        end
    end
    return nil
end

local function saveConfig()
    if not hasFileApi() then
        return false
    end

    ensureDir()

    local payload = {
        AutoThrowAndCatch = Config.AutoThrowAndCatch,
        AutoEquipBest = Config.AutoEquipBest,
        AutoUpgradeStand = Config.AutoUpgradeStand,
        AutoMoveOnTooFar = Config.AutoMoveOnTooFar,
        TargetAccuracy = Config.TargetAccuracy,
        ThrowInterval = Config.ThrowInterval,
        UpgradeInterval = Config.UpgradeInterval,
        SavedThrowCFrame = cframeToArray(Config.SavedThrowCFrame),
        PanelPosOffset = Config.PanelPosOffset,
    }

    local ok = pcall(function()
        writefile(CONFIG_FILE, HttpService:JSONEncode(payload))
    end)

    return ok
end

local function loadConfig()
    if not hasFileApi() then
        return false
    end

    local ok = pcall(function()
        if isfile(CONFIG_FILE) then
            local raw = readfile(CONFIG_FILE)
            local data = HttpService:JSONDecode(raw)
            if type(data) == "table" then
                if type(data.AutoThrowAndCatch) == "boolean" then
                    Config.AutoThrowAndCatch = data.AutoThrowAndCatch
                end
                if type(data.AutoEquipBest) == "boolean" then
                    Config.AutoEquipBest = data.AutoEquipBest
                end
                if type(data.AutoUpgradeStand) == "boolean" then
                    Config.AutoUpgradeStand = data.AutoUpgradeStand
                end
                if type(data.AutoMoveOnTooFar) == "boolean" then
                    Config.AutoMoveOnTooFar = data.AutoMoveOnTooFar
                end
                if type(data.TargetAccuracy) == "number" then
                    Config.TargetAccuracy = math.clamp(data.TargetAccuracy, 0.05, 1)
                end
                if type(data.ThrowInterval) == "number" then
                    Config.ThrowInterval = math.max(0.05, data.ThrowInterval)
                end
                if type(data.UpgradeInterval) == "number" then
                    Config.UpgradeInterval = math.max(0.5, data.UpgradeInterval)
                end
                if type(data.PanelPosOffset) == "table" and #data.PanelPosOffset == 2 then
                    Config.PanelPosOffset = {
                        tonumber(data.PanelPosOffset[1]) or 480,
                        tonumber(data.PanelPosOffset[2]) or 75,
                    }
                end
                Config.SavedThrowCFrame = arrayToCFrame(data.SavedThrowCFrame)
            end
        end
    end)

    return ok
end

-- Đọc cấu hình ngay khi khởi động script
loadConfig()

-- =========================================================
-- TIỆN ÍCH CHUNG
-- =========================================================
local function getGuiParent()
    local ok, result = pcall(function()
        return CoreGui
    end)
    if ok and result then
        return result
    end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local function isCharacterReady()
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    return root, humanoid, (root ~= nil and humanoid ~= nil and humanoid.Health > 0)
end

local function makeDraggable(dragHandle, targetFrame, onDragEndCallback)
    local dragging = false
    local activeInput = nil
    local dragStart = Vector2.zero
    local startPos = targetFrame.Position

    dragHandle.InputBegan:Connect(function(input)
        local t = input.UserInputType
        if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
            dragging = true
            activeInput = input
            dragStart = input.Position
            startPos = targetFrame.Position
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and input == activeInput then
            local delta = input.Position - dragStart
            targetFrame.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input == activeInput then
            dragging = false
            activeInput = nil
            if type(onDragEndCallback) == "function" then
                onDragEndCallback(targetFrame.Position)
            end
        end
    end)
end

-- =========================================================
-- PHẦN 1: UI CHUYÊN NGHIỆP CHO MOBILE + TỰ LƯU DELTA WORKSPACE
-- =========================================================
local function createProMobileUI()
    local parentGui = getGuiParent()
    local oldGui = parentGui:FindFirstChild("ProMobileAutoGui")
    if oldGui then
        oldGui:Destroy()
    end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "ProMobileAutoGui"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = parentGui

    local bubbleBtn = Instance.new("TextButton")
    bubbleBtn.Name = "BubbleBtn"
    bubbleBtn.Size = UDim2.fromOffset(56, 56)
    bubbleBtn.Position = UDim2.fromOffset(16, 120)
    bubbleBtn.BackgroundColor3 = Color3.fromRGB(20, 23, 30)
    bubbleBtn.Text = "AUTO"
    bubbleBtn.TextColor3 = Color3.fromRGB(240, 245, 255)
    bubbleBtn.TextSize = 12
    bubbleBtn.Font = Enum.Font.GothamBold
    bubbleBtn.BorderSizePixel = 0
    bubbleBtn.Visible = false
    bubbleBtn.Parent = screenGui

    Instance.new("UICorner", bubbleBtn).CornerRadius = UDim.new(1, 0)
    local bubbleStroke = Instance.new("UIStroke", bubbleBtn)
    bubbleStroke.Color = Color3.fromRGB(56, 189, 128)
    bubbleStroke.Thickness = 2

    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.fromOffset(256, 334)
    mainFrame.Position = UDim2.fromOffset(Config.PanelPosOffset[1], Config.PanelPosOffset[2])
    mainFrame.BackgroundColor3 = Color3.fromRGB(17, 19, 24)
    mainFrame.BorderSizePixel = 0
    mainFrame.Active = true
    mainFrame.Parent = screenGui

    Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 12)
    local mainStroke = Instance.new("UIStroke", mainFrame)
    mainStroke.Color = Color3.fromRGB(45, 51, 64)
    mainStroke.Thickness = 1.2

    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 40)
    header.BackgroundColor3 = Color3.fromRGB(24, 27, 34)
    header.BorderSizePixel = 0
    header.Active = true
    header.Parent = mainFrame

    Instance.new("UICorner", header).CornerRadius = UDim.new(0, 12)

    local accentBar = Instance.new("Frame", header)
    accentBar.Size = UDim2.fromOffset(4, 18)
    accentBar.Position = UDim2.fromOffset(10, 11)
    accentBar.BackgroundColor3 = Color3.fromRGB(56, 189, 128)
    accentBar.BorderSizePixel = 0
    Instance.new("UICorner", accentBar).CornerRadius = UDim.new(1, 0)

    local titleLabel = Instance.new("TextLabel", header)
    titleLabel.Size = UDim2.new(1, -80, 1, 0)
    titleLabel.Position = UDim2.fromOffset(20, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "CATCH & STAND HUB"
    titleLabel.TextColor3 = Color3.fromRGB(242, 245, 250)
    titleLabel.TextSize = 13
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left

    local minimizeBtn = Instance.new("TextButton", header)
    minimizeBtn.Size = UDim2.fromOffset(28, 28)
    minimizeBtn.Position = UDim2.new(1, -36, 0.5, -14)
    minimizeBtn.BackgroundColor3 = Color3.fromRGB(38, 43, 54)
    minimizeBtn.Text = "—"
    minimizeBtn.TextColor3 = Color3.fromRGB(220, 226, 236)
    minimizeBtn.TextSize = 14
    minimizeBtn.Font = Enum.Font.GothamBold
    minimizeBtn.BorderSizePixel = 0
    Instance.new("UICorner", minimizeBtn).CornerRadius = UDim.new(0, 7)

    local content = Instance.new("Frame", mainFrame)
    content.Size = UDim2.new(1, -16, 1, -50)
    content.Position = UDim2.fromOffset(8, 44)
    content.BackgroundTransparency = 1

    local list = Instance.new("UIListLayout", content)
    list.Padding = UDim.new(0, 7)
    list.FillDirection = Enum.FillDirection.Vertical
    list.SortOrder = Enum.SortOrder.LayoutOrder

    -- Thanh trạng thái
    local statusCard = Instance.new("Frame", content)
    statusCard.Size = UDim2.new(1, 0, 0, 28)
    statusCard.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
    statusCard.BorderSizePixel = 0
    statusCard.LayoutOrder = 0
    Instance.new("UICorner", statusCard).CornerRadius = UDim.new(0, 8)
    Instance.new("UIStroke", statusCard).Color = Color3.fromRGB(36, 41, 52)

    local statusDot = Instance.new("Frame", statusCard)
    statusDot.Size = UDim2.fromOffset(8, 8)
    statusDot.Position = UDim2.fromOffset(10, 10)
    statusDot.BackgroundColor3 = Color3.fromRGB(148, 163, 184)
    statusDot.BorderSizePixel = 0
    Instance.new("UICorner", statusDot).CornerRadius = UDim.new(1, 0)

    local statusLabel = Instance.new("TextLabel", statusCard)
    statusLabel.Size = UDim2.new(1, -26, 1, 0)
    statusLabel.Position = UDim2.fromOffset(24, 0)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = Config.SavedThrowCFrame and "Loaded saved pos!" or "Idle"
    statusLabel.TextColor3 = Color3.fromRGB(203, 213, 225)
    statusLabel.TextSize = 11
    statusLabel.Font = Enum.Font.GothamMedium
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.TextTruncate = Enum.TextTruncate.AtEnd

    -- Nút Toggle có tự lưu trạng thái vào Delta workspace
    local function addToggle(text, key, order)
        local btn = Instance.new("TextButton", content)
        btn.Size = UDim2.new(1, 0, 0, 38)
        btn.BorderSizePixel = 0
        btn.TextSize = 12
        btn.Font = Enum.Font.GothamBold
        btn.TextColor3 = Color3.fromRGB(248, 250, 252)
        btn.LayoutOrder = order
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

        local stroke = Instance.new("UIStroke", btn)
        stroke.Thickness = 1

        local function refresh()
            local on = Config[key]
            btn.Text = text .. (on and "  •  ON" or "  •  OFF")
            btn.BackgroundColor3 = on and Color3.fromRGB(22, 101, 66) or Color3.fromRGB(31, 35, 44)
            stroke.Color = on and Color3.fromRGB(56, 189, 128) or Color3.fromRGB(52, 58, 72)
        end

        btn.MouseButton1Click:Connect(function()
            Config[key] = not Config[key]
            refresh()
            saveConfig()
        end)

        refresh()
    end

    addToggle("Farm & Catch", "AutoThrowAndCatch", 1)
    addToggle("Equip Best", "AutoEquipBest", 2)
    addToggle("Upgrade Stand", "AutoUpgradeStand", 3)
    addToggle("Move On TooFar", "AutoMoveOnTooFar", 4)

    -- Hàng chỉnh Accuracy nhanh (- / +)
    local accRow = Instance.new("Frame", content)
    accRow.Size = UDim2.new(1, 0, 0, 32)
    accRow.BackgroundColor3 = Color3.fromRGB(22, 25, 32)
    accRow.BorderSizePixel = 0
    accRow.LayoutOrder = 5
    Instance.new("UICorner", accRow).CornerRadius = UDim.new(0, 8)
    Instance.new("UIStroke", accRow).Color = Color3.fromRGB(40, 46, 58)

    local accMinus = Instance.new("TextButton", accRow)
    accMinus.Size = UDim2.fromOffset(34, 24)
    accMinus.Position = UDim2.fromOffset(4, 4)
    accMinus.BackgroundColor3 = Color3.fromRGB(38, 43, 54)
    accMinus.Text = "-"
    accMinus.TextColor3 = Color3.fromRGB(240, 244, 250)
    accMinus.TextSize = 14
    accMinus.Font = Enum.Font.GothamBold
    accMinus.BorderSizePixel = 0
    Instance.new("UICorner", accMinus).CornerRadius = UDim.new(0, 6)

    local accLabel = Instance.new("TextLabel", accRow)
    accLabel.Size = UDim2.new(1, -76, 1, 0)
    accLabel.Position = UDim2.fromOffset(38, 0)
    accLabel.BackgroundTransparency = 1
    accLabel.Text = string.format("Accuracy: %.2f", Config.TargetAccuracy)
    accLabel.TextColor3 = Color3.fromRGB(226, 232, 240)
    accLabel.TextSize = 11
    accLabel.Font = Enum.Font.GothamBold

    local accPlus = Instance.new("TextButton", accRow)
    accPlus.Size = UDim2.fromOffset(34, 24)
    accPlus.Position = UDim2.new(1, -38, 0, 4)
    accPlus.BackgroundColor3 = Color3.fromRGB(38, 43, 54)
    accPlus.Text = "+"
    accPlus.TextColor3 = Color3.fromRGB(240, 244, 250)
    accPlus.TextSize = 14
    accPlus.Font = Enum.Font.GothamBold
    accPlus.BorderSizePixel = 0
    Instance.new("UICorner", accPlus).CornerRadius = UDim.new(0, 6)

    local function updateAccuracy(delta)
        Config.TargetAccuracy = math.clamp(tonumber(string.format("%.2f", Config.TargetAccuracy + delta)) or 0.96, 0.10, 1.00)
        accLabel.Text = string.format("Accuracy: %.2f", Config.TargetAccuracy)
        saveConfig()
    end

    accMinus.MouseButton1Click:Connect(function()
        updateAccuracy(-0.02)
    end)

    accPlus.MouseButton1Click:Connect(function()
        updateAccuracy(0.02)
    end)

    -- Hàng nút lưu & dịch chuyển tọa độ
    local posRow = Instance.new("Frame", content)
    posRow.Size = UDim2.new(1, 0, 0, 34)
    posRow.BackgroundTransparency = 1
    posRow.LayoutOrder = 6

    local savePosBtn = Instance.new("TextButton", posRow)
    savePosBtn.Size = UDim2.new(0.5, -4, 1, 0)
    savePosBtn.Position = UDim2.fromOffset(0, 0)
    savePosBtn.BackgroundColor3 = Color3.fromRGB(37, 99, 235)
    savePosBtn.Text = Config.SavedThrowCFrame and "Overwrite Pos" or "Save Throw Pos"
    savePosBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    savePosBtn.TextSize = 11
    savePosBtn.Font = Enum.Font.GothamBold
    savePosBtn.BorderSizePixel = 0
    Instance.new("UICorner", savePosBtn).CornerRadius = UDim.new(0, 8)

    local goPosBtn = Instance.new("TextButton", posRow)
    goPosBtn.Size = UDim2.new(0.5, -4, 1, 0)
    goPosBtn.Position = UDim2.new(0.5, 4, 0, 0)
    goPosBtn.BackgroundColor3 = Color3.fromRGB(45, 50, 62)
    goPosBtn.Text = "Go To Pos"
    goPosBtn.TextColor3 = Color3.fromRGB(235, 240, 248)
    goPosBtn.TextSize = 11
    goPosBtn.Font = Enum.Font.GothamBold
    goPosBtn.BorderSizePixel = 0
    Instance.new("UICorner", goPosBtn).CornerRadius = UDim.new(0, 8)

    local function moveToSavedPos()
        if not Config.SavedThrowCFrame then
            return false
        end
        local root, _, ready = isCharacterReady()
        if not ready then
            return false
        end
        root.CFrame = Config.SavedThrowCFrame + Vector3.new(0, 2, 0)
        return true
    end

    savePosBtn.MouseButton1Click:Connect(function()
        local root, _, ready = isCharacterReady()
        if ready then
            Config.SavedThrowCFrame = root.CFrame
            local ok = saveConfig()
            savePosBtn.Text = ok and "Saved File!" or "Saved RAM!"
            task.delay(0.9, function()
                if savePosBtn then
                    savePosBtn.Text = "Overwrite Pos"
                end
            end)
        end
    end)

    goPosBtn.MouseButton1Click:Connect(function()
        if moveToSavedPos() then
            goPosBtn.Text = "Moved!"
        else
            goPosBtn.Text = "No Pos!"
        end
        task.delay(0.8, function()
            if goPosBtn then
                goPosBtn.Text = "Go To Pos"
            end
        end)
    end)

    minimizeBtn.MouseButton1Click:Connect(function()
        bubbleBtn.Position = mainFrame.Position
        mainFrame.Visible = false
        bubbleBtn.Visible = true
    end)

    bubbleBtn.MouseButton1Click:Connect(function()
        mainFrame.Position = bubbleBtn.Position
        bubbleBtn.Visible = false
        mainFrame.Visible = true
    end)

    makeDraggable(header, mainFrame, function(finalPos)
        Config.PanelPosOffset = { math.floor(finalPos.X.Offset), math.floor(finalPos.Y.Offset) }
        saveConfig()
    end)

    makeDraggable(bubbleBtn, bubbleBtn)

    return function(text, mode)
        State.StatusText = tostring(text)
        State.StatusMode = mode or "idle"
        statusLabel.Text = State.StatusText

        if State.StatusMode == "active" then
            statusDot.BackgroundColor3 = Color3.fromRGB(56, 189, 128)
        elseif State.StatusMode == "warn" then
            statusDot.BackgroundColor3 = Color3.fromRGB(251, 191, 36)
        else
            statusDot.BackgroundColor3 = Color3.fromRGB(148, 163, 184)
        end
    end, moveToSavedPos
end

local setStatus, moveToSavedPos = createProMobileUI()

-- =========================================================
-- PHẦN 2: LOGIC AUTO (KIỂM TRA -> CHẠY -> KIỂM TRA)
-- =========================================================
local function safeInvoke(remoteFunc, ...)
    local ok, res = pcall(function(...)
        return remoteFunc:InvokeServer(...)
    end, ...)

    if not ok then
        return false, { Ok = false, Reason = tostring(res) }
    end
    if type(res) ~= "table" then
        return false, { Ok = false, Reason = "InvalidResponseType" }
    end
    return true, res
end

local function tryEquipBest()
    if not Config.AutoEquipBest then
        return
    end
    setStatus("Equipping best...", "active")
    local ok, res = safeInvoke(Plot_EquipBest)
    if ok and res.Ok then
        setStatus("Plot updated", "active")
    end
end

local function runThrowAndCatchStep()
    if not Config.AutoThrowAndCatch then
        if not Config.AutoUpgradeStand and not State.IsThrowing then
            setStatus("Idle", "idle")
        end
        task.wait(0.35)
        return
    end

    if State.IsThrowing then
        task.wait(0.2)
        return
    end

    local _, _, ready = isCharacterReady()
    if not ready then
        setStatus("Waiting character...", "warn")
        task.wait(0.5)
        return
    end

    State.IsThrowing = true
    setStatus("Starting throw...", "active")

    local startOk, startRes = safeInvoke(Throw_Start)
    if not startOk or not startRes.Ok then
        local reason = (type(startRes) == "table" and startRes.Reason) or "StartFail"
        State.IsThrowing = false

        if reason == "TooFar" then
            if Config.AutoMoveOnTooFar and Config.SavedThrowCFrame then
                setStatus("TooFar -> Moving to pos...", "warn")
                moveToSavedPos()
                task.wait(0.35)
                return
            else
                setStatus("TooFar! Save pos & move", "warn")
                task.wait(Config.FailBackoff)
                return
            end
        end

        setStatus("Start: " .. tostring(reason), "warn")
        task.wait(Config.FailBackoff)
        return
    end

    pcall(function()
        Throw_MeterStarted:FireServer()
    end)
    task.wait(0.1)

    setStatus("Resolving throw...", "active")
    local resolveOk, resolveRes = safeInvoke(Throw_Resolve, Config.TargetAccuracy)
    if not resolveOk or not resolveRes.Ok then
        local reason = (type(resolveRes) == "table" and resolveRes.Reason) or "ResolveFail"
        State.IsThrowing = false
        setStatus("Resolve: " .. tostring(reason), "warn")
        task.wait(0.4)
        return
    end

    local flightTime = tonumber(resolveRes.FlightTime) or 1.4
    setStatus(string.format("Flying (%.1fs)...", flightTime), "active")
    task.wait(math.clamp(flightTime, 0.2, 5) + Config.ExtraWaitAfterFlight)

    setStatus("Completing catch...", "active")
    local completeOk, completeRes = safeInvoke(Throw_Complete)
    State.IsThrowing = false

    if completeOk and completeRes.Ok then
        setStatus("Caught: " .. tostring(resolveRes.ModelName or completeRes.AnimalId or "OK"), "active")
        if completeRes.AnimalId or resolveRes.IsNew then
            tryEquipBest()
        end
        task.wait(Config.ThrowInterval)
    else
        setStatus("Complete fail", "warn")
        task.wait(0.4)
    end
end

local function runUpgradeStep()
    if not Config.AutoUpgradeStand then
        task.wait(0.5)
        return
    end

    local _, _, ready = isCharacterReady()
    if not ready or State.IsThrowing then
        task.wait(0.5)
        return
    end

    setStatus("Upgrading stand...", "active")
    local ok, res = safeInvoke(Stand_Upgrade)

    if ok and res.Ok then
        setStatus("Stand Lv -> " .. tostring(res.NewIndex or "OK"), "active")
        tryEquipBest()
        task.wait(Config.UpgradeInterval)
    else
        setStatus("Upgrade not ready", "idle")
        task.wait(Config.UpgradeInterval + Config.FailBackoff)
    end
end

task.spawn(function()
    while true do
        runThrowAndCatchStep()
        task.wait(0.08)
    end
end)

task.spawn(function()
    while true do
        runUpgradeStep()
        task.wait(0.15)
    end
end)
