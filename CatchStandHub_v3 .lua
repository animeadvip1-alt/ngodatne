local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
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
local Training_Bonus = Remotes:FindFirstChild("Training_Bonus")
local Training_TapBonus = Remotes:FindFirstChild("Training_TapBonus")

local HUB_DIR = "CatchStandHub"
local CONFIG_FILE = HUB_DIR .. "/settings.json"

local DefaultConfig = {
    AutoThrowAndCatch = false,
    AutoEquipBest = false,
    AutoUpgradeStand = false,
    AutoBonus = false,
    AutoMoveOnTooFar = true,

    MoveMode = "Instant", -- "Instant" | "Tween"
    TweenSpeed = 140,
    NearThreshold = 8,

    TargetAccuracy = 0.96,
    ExtraWaitAfterFlight = 0.25,
    ThrowInterval = 0.30,
    UpgradeInterval = 2.50,
    EquipInterval = 4.00,
    BonusDuration = 3.00,
    BonusTapDelay = 0.08,
    FailBackoff = 1.20,

    SavedThrowCFrame = nil,
    SavedTrainCFrame = nil,
    SavedStandCFrame = nil,
    PanelPosOffset = { 320, 60 },
    ActiveTab = "Farm",
}

local Config = {}
for k, v in pairs(DefaultConfig) do
    if type(v) == "table" then
        Config[k] = { v[1], v[2] }
    else
        Config[k] = v
    end
end

local State = {
    IsThrowing = false,
    IsMoving = false,
    ActiveTween = nil,
    BonusActiveUntil = 0,
    CurrentBonusId = 1,
    StatusText = "Idle",
    StatusMode = "idle",
    SessionStart = os.clock(),
    Stats = {
        Catches = 0,
        Upgrades = 0,
        BonusTaps = 0,
        Moves = 0,
    },
    Logs = {},
}

local function pushLog(msg)
    local elapsed = math.floor(os.clock() - State.SessionStart)
    local mins = math.floor(elapsed / 60)
    local secs = elapsed % 60
    local entry = string.format("[%02d:%02d] %s", mins, secs, tostring(msg))
    table.insert(State.Logs, 1, entry)
    if #State.Logs > 6 then
        table.remove(State.Logs)
    end
end

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
        AutoBonus = Config.AutoBonus,
        AutoMoveOnTooFar = Config.AutoMoveOnTooFar,
        MoveMode = Config.MoveMode,
        TweenSpeed = Config.TweenSpeed,
        NearThreshold = Config.NearThreshold,
        TargetAccuracy = Config.TargetAccuracy,
        ThrowInterval = Config.ThrowInterval,
        UpgradeInterval = Config.UpgradeInterval,
        EquipInterval = Config.EquipInterval,
        BonusDuration = Config.BonusDuration,
        BonusTapDelay = Config.BonusTapDelay,
        SavedThrowCFrame = cframeToArray(Config.SavedThrowCFrame),
        SavedTrainCFrame = cframeToArray(Config.SavedTrainCFrame),
        SavedStandCFrame = cframeToArray(Config.SavedStandCFrame),
        PanelPosOffset = Config.PanelPosOffset,
        ActiveTab = Config.ActiveTab,
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
                if type(data.AutoBonus) == "boolean" then
                    Config.AutoBonus = data.AutoBonus
                elseif type(data.AutoStartTraining) == "boolean" then
                    Config.AutoBonus = data.AutoStartTraining
                end
                if type(data.AutoMoveOnTooFar) == "boolean" then
                    Config.AutoMoveOnTooFar = data.AutoMoveOnTooFar
                end
                if data.MoveMode == "Instant" or data.MoveMode == "Tween" then
                    Config.MoveMode = data.MoveMode
                end
                if type(data.TweenSpeed) == "number" then
                    Config.TweenSpeed = math.clamp(data.TweenSpeed, 40, 400)
                end
                if type(data.TargetAccuracy) == "number" then
                    Config.TargetAccuracy = math.clamp(data.TargetAccuracy, 0.10, 1.00)
                end
                if type(data.ThrowInterval) == "number" then
                    Config.ThrowInterval = math.clamp(data.ThrowInterval, 0.05, 5.00)
                end
                if type(data.UpgradeInterval) == "number" then
                    Config.UpgradeInterval = math.clamp(data.UpgradeInterval, 0.50, 15.00)
                end
                if type(data.EquipInterval) == "number" then
                    Config.EquipInterval = math.clamp(data.EquipInterval, 1.00, 30.00)
                end
                if type(data.BonusDuration) == "number" then
                    Config.BonusDuration = math.clamp(data.BonusDuration, 0.50, 10.00)
                end
                if type(data.BonusTapDelay) == "number" then
                    Config.BonusTapDelay = math.clamp(data.BonusTapDelay, 0.02, 1.00)
                end
                if type(data.PanelPosOffset) == "table" and #data.PanelPosOffset == 2 then
                    Config.PanelPosOffset = {
                        tonumber(data.PanelPosOffset[1]) or 320,
                        tonumber(data.PanelPosOffset[2]) or 60,
                    }
                end
                if data.ActiveTab == "Farm" or data.ActiveTab == "Move" or data.ActiveTab == "Config" then
                    Config.ActiveTab = data.ActiveTab
                end
                Config.SavedThrowCFrame = arrayToCFrame(data.SavedThrowCFrame)
                Config.SavedTrainCFrame = arrayToCFrame(data.SavedTrainCFrame)
                Config.SavedStandCFrame = arrayToCFrame(data.SavedStandCFrame)
            end
        end
    end)

    return ok
end

loadConfig()

local function mountScreenGui(screenGui)
    local ok = pcall(function()
        screenGui.Parent = CoreGui
    end)
    if not ok or not screenGui.Parent then
        screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end
end

local function clampPanelToScreen(x, y, width, height)
    local cam = workspace.CurrentCamera
    if not cam then
        return math.max(8, x), math.max(8, y)
    end
    local vp = cam.ViewportSize
    local maxX = math.max(8, vp.X - width - 8)
    local maxY = math.max(8, vp.Y - height - 8)
    return math.clamp(x, 8, maxX), math.clamp(y, 8, maxY)
end

local function isCharacterReady()
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    return root, humanoid, (root ~= nil and humanoid ~= nil and humanoid.Health > 0)
end

LocalPlayer.CharacterAdded:Connect(function()
    State.IsThrowing = false
    State.IsMoving = false
    if State.ActiveTween then
        pcall(function()
            State.ActiveTween:Cancel()
        end)
        State.ActiveTween = nil
    end
    pushLog("Character respawned")
end)

local function moveToCFrame(cf, label)
    if not cf then
        return false
    end
    local root, _, ready = isCharacterReady()
    if not ready then
        return false
    end

    local targetCf = cf + Vector3.new(0, 2, 0)
    local dist = (targetCf.Position - root.Position).Magnitude

    if dist <= Config.NearThreshold then
        root.CFrame = targetCf
        return true
    end

    if State.ActiveTween then
        pcall(function()
            State.ActiveTween:Cancel()
        end)
        State.ActiveTween = nil
    end

    if Config.MoveMode == "Tween" then
        State.IsMoving = true
        local duration = math.clamp(dist / math.max(40, Config.TweenSpeed), 0.1, 8.0)
        local tween = TweenService:Create(
            root,
            TweenInfo.new(duration, Enum.EasingStyle.Linear),
            { CFrame = targetCf }
        )
        State.ActiveTween = tween
        tween:Play()
        tween.Completed:Wait()
        State.ActiveTween = nil
        State.IsMoving = false
    else
        root.CFrame = targetCf
    end

    State.Stats.Moves += 1
    if label then
        pushLog("Moved -> " .. label)
    end
    return true
end

local function moveToThrowPos()
    return moveToCFrame(Config.SavedThrowCFrame, "Throw Pos")
end

local function moveToTrainPos()
    return moveToCFrame(Config.SavedTrainCFrame, "Train Pos")
end

local function moveToStandPos()
    return moveToCFrame(Config.SavedStandCFrame, "Stand Pos")
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

local function createProMobileUI()
    for _, container in ipairs({ CoreGui, LocalPlayer:FindFirstChild("PlayerGui") }) do
        if container then
            local oldGui = container:FindFirstChild("ProMobileAutoGui")
            if oldGui then
                oldGui:Destroy()
            end
        end
    end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "ProMobileAutoGui"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    mountScreenGui(screenGui)

    local bubbleBtn = Instance.new("TextButton")
    bubbleBtn.Name = "BubbleBtn"
    bubbleBtn.Size = UDim2.fromOffset(54, 54)
    bubbleBtn.Position = UDim2.fromOffset(16, 120)
    bubbleBtn.BackgroundColor3 = Color3.fromRGB(18, 21, 27)
    bubbleBtn.Text = "HUB"
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

    local panelWidth, panelHeight = 276, 376
    local safeX, safeY = clampPanelToScreen(
        Config.PanelPosOffset[1],
        Config.PanelPosOffset[2],
        panelWidth,
        panelHeight
    )

    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.fromOffset(panelWidth, panelHeight)
    mainFrame.Position = UDim2.fromOffset(safeX, safeY)
    mainFrame.BackgroundColor3 = Color3.fromRGB(17, 19, 24)
    mainFrame.BorderSizePixel = 0
    mainFrame.Active = true
    mainFrame.Parent = screenGui

    Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 12)
    local mainStroke = Instance.new("UIStroke", mainFrame)
    mainStroke.Color = Color3.fromRGB(45, 51, 64)
    mainStroke.Thickness = 1.2

    -- Header
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 38)
    header.BackgroundColor3 = Color3.fromRGB(24, 27, 34)
    header.BorderSizePixel = 0
    header.Active = true
    header.Parent = mainFrame
    Instance.new("UICorner", header).CornerRadius = UDim.new(0, 12)

    local accentBar = Instance.new("Frame", header)
    accentBar.Size = UDim2.fromOffset(4, 16)
    accentBar.Position = UDim2.fromOffset(10, 11)
    accentBar.BackgroundColor3 = Color3.fromRGB(56, 189, 128)
    accentBar.BorderSizePixel = 0
    Instance.new("UICorner", accentBar).CornerRadius = UDim.new(1, 0)

    local titleLabel = Instance.new("TextLabel", header)
    titleLabel.Size = UDim2.new(1, -96, 1, 0)
    titleLabel.Position = UDim2.fromOffset(20, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "CATCH & STAND V3"
    titleLabel.TextColor3 = Color3.fromRGB(242, 245, 250)
    titleLabel.TextSize = 13
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left

    local stopAllBtn = Instance.new("TextButton", header)
    stopAllBtn.Size = UDim2.fromOffset(38, 24)
    stopAllBtn.Position = UDim2.new(1, -74, 0.5, -12)
    stopAllBtn.BackgroundColor3 = Color3.fromRGB(153, 27, 27)
    stopAllBtn.Text = "STOP"
    stopAllBtn.TextColor3 = Color3.fromRGB(254, 226, 226)
    stopAllBtn.TextSize = 10
    stopAllBtn.Font = Enum.Font.GothamBold
    stopAllBtn.BorderSizePixel = 0
    Instance.new("UICorner", stopAllBtn).CornerRadius = UDim.new(0, 6)

    local minimizeBtn = Instance.new("TextButton", header)
    minimizeBtn.Size = UDim2.fromOffset(26, 24)
    minimizeBtn.Position = UDim2.new(1, -32, 0.5, -12)
    minimizeBtn.BackgroundColor3 = Color3.fromRGB(38, 43, 54)
    minimizeBtn.Text = "—"
    minimizeBtn.TextColor3 = Color3.fromRGB(220, 226, 236)
    minimizeBtn.TextSize = 13
    minimizeBtn.Font = Enum.Font.GothamBold
    minimizeBtn.BorderSizePixel = 0
    Instance.new("UICorner", minimizeBtn).CornerRadius = UDim.new(0, 6)

    -- Status Bar
    local statusCard = Instance.new("Frame", mainFrame)
    statusCard.Size = UDim2.new(1, -16, 0, 26)
    statusCard.Position = UDim2.fromOffset(8, 43)
    statusCard.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
    statusCard.BorderSizePixel = 0
    Instance.new("UICorner", statusCard).CornerRadius = UDim.new(0, 7)
    Instance.new("UIStroke", statusCard).Color = Color3.fromRGB(36, 41, 52)

    local statusDot = Instance.new("Frame", statusCard)
    statusDot.Size = UDim2.fromOffset(8, 8)
    statusDot.Position = UDim2.fromOffset(9, 9)
    statusDot.BackgroundColor3 = Color3.fromRGB(148, 163, 184)
    statusDot.BorderSizePixel = 0
    Instance.new("UICorner", statusDot).CornerRadius = UDim.new(1, 0)

    local statusLabel = Instance.new("TextLabel", statusCard)
    statusLabel.Size = UDim2.new(1, -24, 1, 0)
    statusLabel.Position = UDim2.fromOffset(22, 0)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = (Config.SavedThrowCFrame or Config.SavedTrainCFrame or Config.SavedStandCFrame)
        and "Ready (Saved Pos Loaded)"
        or "Idle"
    statusLabel.TextColor3 = Color3.fromRGB(203, 213, 225)
    statusLabel.TextSize = 11
    statusLabel.Font = Enum.Font.GothamMedium
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.TextTruncate = Enum.TextTruncate.AtEnd

    -- Tab Bar
    local tabBar = Instance.new("Frame", mainFrame)
    tabBar.Size = UDim2.new(1, -16, 0, 28)
    tabBar.Position = UDim2.fromOffset(8, 74)
    tabBar.BackgroundColor3 = Color3.fromRGB(13, 15, 20)
    tabBar.BorderSizePixel = 0
    Instance.new("UICorner", tabBar).CornerRadius = UDim.new(0, 8)

    local tabLayout = Instance.new("UIListLayout", tabBar)
    tabLayout.FillDirection = Enum.FillDirection.Horizontal
    tabLayout.Padding = UDim.new(0, 4)
    tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center

    -- Page Container
    local pageContainer = Instance.new("Frame", mainFrame)
    pageContainer.Size = UDim2.new(1, -16, 1, -112)
    pageContainer.Position = UDim2.fromOffset(8, 106)
    pageContainer.BackgroundTransparency = 1

    local pages = {}
    local tabButtons = {}
    local toggleRefreshers = {}
    local uiRefreshers = {}

    local function createPage(name)
        local page = Instance.new("Frame", pageContainer)
        page.Name = name .. "Page"
        page.Size = UDim2.new(1, 0, 1, 0)
        page.BackgroundTransparency = 1
        page.Visible = (Config.ActiveTab == name)

        local layout = Instance.new("UIListLayout", page)
        layout.Padding = UDim.new(0, 6)
        layout.FillDirection = Enum.FillDirection.Vertical
        layout.SortOrder = Enum.SortOrder.LayoutOrder

        pages[name] = page
        return page
    end

    local farmPage = createPage("Farm")
    local movePage = createPage("Move")
    local configPage = createPage("Config")

    local function switchTab(tabName)
        Config.ActiveTab = tabName
        for name, page in pairs(pages) do
            page.Visible = (name == tabName)
        end
        for name, btn in pairs(tabButtons) do
            local active = (name == tabName)
            btn.BackgroundColor3 = active and Color3.fromRGB(34, 41, 54) or Color3.fromRGB(18, 21, 28)
            btn.TextColor3 = active and Color3.fromRGB(56, 189, 128) or Color3.fromRGB(160, 172, 190)
        end
        saveConfig()
    end

    local function addTabButton(tabName, label, order)
        local btn = Instance.new("TextButton", tabBar)
        btn.Size = UDim2.new(0.333, -4, 1, -4)
        btn.BorderSizePixel = 0
        btn.Text = label
        btn.TextSize = 11
        btn.Font = Enum.Font.GothamBold
        btn.LayoutOrder = order
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

        btn.MouseButton1Click:Connect(function()
            switchTab(tabName)
        end)

        tabButtons[tabName] = btn
    end

    addTabButton("Farm", "Farm", 1)
    addTabButton("Move", "Pos & Move", 2)
    addTabButton("Config", "Config & Log", 3)
    switchTab(Config.ActiveTab)

    local function syncAllUI()
        for _, fn in ipairs(toggleRefreshers) do
            pcall(fn)
        end
        for _, fn in ipairs(uiRefreshers) do
            pcall(fn)
        end
    end

    local function setStatus(text, mode)
        State.StatusText = tostring(text)
        State.StatusMode = mode or "idle"
        statusLabel.Text = State.StatusText

        local dotColor = Color3.fromRGB(148, 163, 184)
        if State.StatusMode == "active" then
            dotColor = Color3.fromRGB(56, 189, 128)
        elseif State.StatusMode == "warn" then
            dotColor = Color3.fromRGB(251, 191, 36)
        end
        statusDot.BackgroundColor3 = dotColor
        bubbleStroke.Color = dotColor
    end

    local function addToggle(parent, text, key, order, onAfterToggle)
        local btn = Instance.new("TextButton", parent)
        btn.Size = UDim2.new(1, 0, 0, 35)
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
            saveConfig()
            if type(onAfterToggle) == "function" then
                onAfterToggle(Config[key])
            end
            syncAllUI()
        end)

        table.insert(toggleRefreshers, refresh)
        refresh()
        return btn
    end

    local function addStepper(parent, order, getLabelFn, onStepFn)
        local row = Instance.new("Frame", parent)
        row.Size = UDim2.new(1, 0, 0, 32)
        row.BackgroundColor3 = Color3.fromRGB(22, 25, 32)
        row.BorderSizePixel = 0
        row.LayoutOrder = order
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
        Instance.new("UIStroke", row).Color = Color3.fromRGB(40, 46, 58)

        local minusBtn = Instance.new("TextButton", row)
        minusBtn.Size = UDim2.fromOffset(34, 24)
        minusBtn.Position = UDim2.fromOffset(4, 4)
        minusBtn.BackgroundColor3 = Color3.fromRGB(38, 43, 54)
        minusBtn.Text = "-"
        minusBtn.TextColor3 = Color3.fromRGB(240, 244, 250)
        minusBtn.TextSize = 14
        minusBtn.Font = Enum.Font.GothamBold
        minusBtn.BorderSizePixel = 0
        Instance.new("UICorner", minusBtn).CornerRadius = UDim.new(0, 6)

        local lbl = Instance.new("TextLabel", row)
        lbl.Size = UDim2.new(1, -76, 1, 0)
        lbl.Position = UDim2.fromOffset(38, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = getLabelFn()
        lbl.TextColor3 = Color3.fromRGB(226, 232, 240)
        lbl.TextSize = 11
        lbl.Font = Enum.Font.GothamBold

        local plusBtn = Instance.new("TextButton", row)
        plusBtn.Size = UDim2.fromOffset(34, 24)
        plusBtn.Position = UDim2.new(1, -38, 0, 4)
        plusBtn.BackgroundColor3 = Color3.fromRGB(38, 43, 54)
        plusBtn.Text = "+"
        plusBtn.TextColor3 = Color3.fromRGB(240, 244, 250)
        plusBtn.TextSize = 14
        plusBtn.Font = Enum.Font.GothamBold
        plusBtn.BorderSizePixel = 0
        Instance.new("UICorner", plusBtn).CornerRadius = UDim.new(0, 6)

        local function refresh()
            lbl.Text = getLabelFn()
        end

        minusBtn.MouseButton1Click:Connect(function()
            onStepFn(-1)
            saveConfig()
            refresh()
        end)

        plusBtn.MouseButton1Click:Connect(function()
            onStepFn(1)
            saveConfig()
            refresh()
        end)

        table.insert(uiRefreshers, refresh)
    end

    -- ==========================================
    -- TAB 1: FARM
    -- ==========================================
    addToggle(farmPage, "Farm & Catch", "AutoThrowAndCatch", 1)
    addToggle(farmPage, "Equip Best", "AutoEquipBest", 2)
    addToggle(farmPage, "Upgrade Stand", "AutoUpgradeStand", 3)

    addToggle(farmPage, "Start Training", "AutoBonus", 4, function(isOn)
        if isOn then
            pushLog("Start Training -> ON")
            task.spawn(function()
                if moveToTrainPos() then
                    setStatus("Train Pos + Auto Bonus ON", "active")
                else
                    setStatus("Auto Bonus ON (No Train Pos)", "warn")
                end
            end)
        else
            pushLog("Start Training -> OFF")
            setStatus("Auto Bonus OFF", "idle")
        end
    end)

    addToggle(farmPage, "Move On TooFar", "AutoMoveOnTooFar", 5)

    addStepper(
        farmPage,
        6,
        function()
            return string.format("Throw Accuracy: %.2f", Config.TargetAccuracy)
        end,
        function(dir)
            local nextVal = tonumber(string.format("%.2f", Config.TargetAccuracy + (dir * 0.02))) or 0.96
            Config.TargetAccuracy = math.clamp(nextVal, 0.10, 1.00)
        end
    )

    -- ==========================================
    -- TAB 2: POS & MOVE
    -- ==========================================
    local modeBtn = Instance.new("TextButton", movePage)
    modeBtn.Size = UDim2.new(1, 0, 0, 34)
    modeBtn.BackgroundColor3 = Color3.fromRGB(31, 35, 44)
    modeBtn.TextColor3 = Color3.fromRGB(242, 245, 250)
    modeBtn.TextSize = 12
    modeBtn.Font = Enum.Font.GothamBold
    modeBtn.BorderSizePixel = 0
    modeBtn.LayoutOrder = 1
    Instance.new("UICorner", modeBtn).CornerRadius = UDim.new(0, 8)
    local modeStroke = Instance.new("UIStroke", modeBtn)
    modeStroke.Color = Color3.fromRGB(59, 130, 246)
    modeStroke.Thickness = 1

    local function refreshModeBtn()
        modeBtn.Text = "Move Mode  •  " .. Config.MoveMode
    end
    refreshModeBtn()
    table.insert(uiRefreshers, refreshModeBtn)

    modeBtn.MouseButton1Click:Connect(function()
        Config.MoveMode = (Config.MoveMode == "Instant") and "Tween" or "Instant"
        saveConfig()
        refreshModeBtn()
        pushLog("MoveMode -> " .. Config.MoveMode)
    end)

    addStepper(
        movePage,
        2,
        function()
            return string.format("Tween Speed: %d studs/s", Config.TweenSpeed)
        end,
        function(dir)
            Config.TweenSpeed = math.clamp(Config.TweenSpeed + (dir * 20), 40, 400)
        end
    )

    local function addPosRow(title, configKey, moveFn, order)
        local card = Instance.new("Frame", movePage)
        card.Size = UDim2.new(1, 0, 0, 42)
        card.BackgroundColor3 = Color3.fromRGB(22, 25, 32)
        card.BorderSizePixel = 0
        card.LayoutOrder = order
        Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)
        Instance.new("UIStroke", card).Color = Color3.fromRGB(40, 46, 58)

        local nameLbl = Instance.new("TextLabel", card)
        nameLbl.Size = UDim2.new(0.46, 0, 0, 20)
        nameLbl.Position = UDim2.fromOffset(8, 3)
        nameLbl.BackgroundTransparency = 1
        nameLbl.Text = title
        nameLbl.TextColor3 = Color3.fromRGB(240, 244, 250)
        nameLbl.TextSize = 11
        nameLbl.Font = Enum.Font.GothamBold
        nameLbl.TextXAlignment = Enum.TextXAlignment.Left

        local stateLbl = Instance.new("TextLabel", card)
        stateLbl.Size = UDim2.new(0.46, 0, 0, 16)
        stateLbl.Position = UDim2.fromOffset(8, 22)
        stateLbl.BackgroundTransparency = 1
        stateLbl.TextSize = 10
        stateLbl.Font = Enum.Font.GothamMedium
        stateLbl.TextXAlignment = Enum.TextXAlignment.Left

        local saveBtn = Instance.new("TextButton", card)
        saveBtn.Size = UDim2.fromOffset(62, 28)
        saveBtn.Position = UDim2.new(1, -130, 0.5, -14)
        saveBtn.BackgroundColor3 = Color3.fromRGB(37, 99, 235)
        saveBtn.Text = "Save"
        saveBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        saveBtn.TextSize = 11
        saveBtn.Font = Enum.Font.GothamBold
        saveBtn.BorderSizePixel = 0
        Instance.new("UICorner", saveBtn).CornerRadius = UDim.new(0, 6)

        local goBtn = Instance.new("TextButton", card)
        goBtn.Size = UDim2.fromOffset(58, 28)
        goBtn.Position = UDim2.new(1, -64, 0.5, -14)
        goBtn.BackgroundColor3 = Color3.fromRGB(45, 50, 62)
        goBtn.Text = "Go"
        goBtn.TextColor3 = Color3.fromRGB(235, 240, 248)
        goBtn.TextSize = 11
        goBtn.Font = Enum.Font.GothamBold
        goBtn.BorderSizePixel = 0
        Instance.new("UICorner", goBtn).CornerRadius = UDim.new(0, 6)

        local function refresh()
            local hasPos = (Config[configKey] ~= nil)
            stateLbl.Text = hasPos and "Saved" or "Not Set"
            stateLbl.TextColor3 = hasPos and Color3.fromRGB(56, 189, 128) or Color3.fromRGB(148, 163, 184)
        end
        refresh()
        table.insert(uiRefreshers, refresh)

        saveBtn.MouseButton1Click:Connect(function()
            local root, _, ready = isCharacterReady()
            if ready then
                Config[configKey] = root.CFrame
                saveConfig()
                refresh()
                pushLog("Saved " .. title)
                saveBtn.Text = "OK!"
                task.delay(0.8, function()
                    if saveBtn then
                        saveBtn.Text = "Save"
                    end
                end)
            end
        end)

        goBtn.MouseButton1Click:Connect(function()
            task.spawn(function()
                if moveFn() then
                    goBtn.Text = "Done"
                else
                    goBtn.Text = "None"
                end
                task.delay(0.8, function()
                    if goBtn then
                        goBtn.Text = "Go"
                    end
                end)
            end)
        end)
    end

    addPosRow("Throw Pos", "SavedThrowCFrame", moveToThrowPos, 3)
    addPosRow("Train Pos", "SavedTrainCFrame", moveToTrainPos, 4)
    addPosRow("Stand Pos", "SavedStandCFrame", moveToStandPos, 5)

    -- ==========================================
    -- TAB 3: CONFIG & LOG
    -- ==========================================
    addStepper(
        configPage,
        1,
        function()
            return string.format("Throw Interval: %.2fs", Config.ThrowInterval)
        end,
        function(dir)
            local nextVal = tonumber(string.format("%.2f", Config.ThrowInterval + (dir * 0.10))) or 0.30
            Config.ThrowInterval = math.clamp(nextVal, 0.10, 5.00)
        end
    )

    addStepper(
        configPage,
        2,
        function()
            return string.format("Upgrade Interval: %.1fs", Config.UpgradeInterval)
        end,
        function(dir)
            local nextVal = tonumber(string.format("%.1f", Config.UpgradeInterval + (dir * 0.5))) or 2.5
            Config.UpgradeInterval = math.clamp(nextVal, 0.5, 15.0)
        end
    )

    local statsCard = Instance.new("Frame", configPage)
    statsCard.Size = UDim2.new(1, 0, 0, 44)
    statsCard.BackgroundColor3 = Color3.fromRGB(22, 25, 32)
    statsCard.BorderSizePixel = 0
    statsCard.LayoutOrder = 3
    Instance.new("UICorner", statsCard).CornerRadius = UDim.new(0, 8)
    Instance.new("UIStroke", statsCard).Color = Color3.fromRGB(40, 46, 58)

    local statsLabel = Instance.new("TextLabel", statsCard)
    statsLabel.Size = UDim2.new(1, -12, 1, -6)
    statsLabel.Position = UDim2.fromOffset(6, 3)
    statsLabel.BackgroundTransparency = 1
    statsLabel.TextColor3 = Color3.fromRGB(203, 213, 225)
    statsLabel.TextSize = 10
    statsLabel.Font = Enum.Font.GothamMedium
    statsLabel.TextWrapped = true
    statsLabel.TextXAlignment = Enum.TextXAlignment.Left

    local logCard = Instance.new("Frame", configPage)
    logCard.Size = UDim2.new(1, 0, 0, 92)
    logCard.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
    logCard.BorderSizePixel = 0
    logCard.LayoutOrder = 4
    Instance.new("UICorner", logCard).CornerRadius = UDim.new(0, 8)
    Instance.new("UIStroke", logCard).Color = Color3.fromRGB(36, 41, 52)

    local logLabel = Instance.new("TextLabel", logCard)
    logLabel.Size = UDim2.new(1, -12, 1, -8)
    logLabel.Position = UDim2.fromOffset(6, 4)
    logLabel.BackgroundTransparency = 1
    logLabel.TextColor3 = Color3.fromRGB(148, 163, 184)
    logLabel.TextSize = 10
    logLabel.Font = Enum.Font.Code
    logLabel.TextWrapped = true
    logLabel.TextYAlignment = Enum.TextYAlignment.Top
    logLabel.TextXAlignment = Enum.TextXAlignment.Left

    local actionRow = Instance.new("Frame", configPage)
    actionRow.Size = UDim2.new(1, 0, 0, 30)
    actionRow.BackgroundTransparency = 1
    actionRow.LayoutOrder = 5

    local resetStatsBtn = Instance.new("TextButton", actionRow)
    resetStatsBtn.Size = UDim2.new(0.5, -3, 1, 0)
    resetStatsBtn.Position = UDim2.fromOffset(0, 0)
    resetStatsBtn.BackgroundColor3 = Color3.fromRGB(38, 43, 54)
    resetStatsBtn.Text = "Reset Stats"
    resetStatsBtn.TextColor3 = Color3.fromRGB(226, 232, 240)
    resetStatsBtn.TextSize = 11
    resetStatsBtn.Font = Enum.Font.GothamBold
    resetStatsBtn.BorderSizePixel = 0
    Instance.new("UICorner", resetStatsBtn).CornerRadius = UDim.new(0, 7)

    local resetCfgBtn = Instance.new("TextButton", actionRow)
    resetCfgBtn.Size = UDim2.new(0.5, -3, 1, 0)
    resetCfgBtn.Position = UDim2.new(0.5, 3, 0, 0)
    resetCfgBtn.BackgroundColor3 = Color3.fromRGB(127, 29, 29)
    resetCfgBtn.Text = "Reset Config"
    resetCfgBtn.TextColor3 = Color3.fromRGB(254, 226, 226)
    resetCfgBtn.TextSize = 11
    resetCfgBtn.Font = Enum.Font.GothamBold
    resetCfgBtn.BorderSizePixel = 0
    Instance.new("UICorner", resetCfgBtn).CornerRadius = UDim.new(0, 7)

    resetStatsBtn.MouseButton1Click:Connect(function()
        State.SessionStart = os.clock()
        State.Stats.Catches = 0
        State.Stats.Upgrades = 0
        State.Stats.BonusTaps = 0
        State.Stats.Moves = 0
        State.Logs = {}
        pushLog("Stats reset")
    end)

    resetCfgBtn.MouseButton1Click:Connect(function()
        for k, v in pairs(DefaultConfig) do
            if type(v) == "table" then
                Config[k] = { v[1], v[2] }
            else
                Config[k] = v
            end
        end
        saveConfig()
        syncAllUI()
        pushLog("Config reset to default")
        setStatus("Config reset!", "warn")
    end)

    -- Live Stats & Log updater
    task.spawn(function()
        while screenGui and screenGui.Parent do
            local up = math.floor(os.clock() - State.SessionStart)
            local m = math.floor(up / 60)
            local s = up % 60
            statsLabel.Text = string.format(
                "Catches: %d  |  Upgrades: %d\nBonus Taps: %d  |  Moves: %d  |  Time: %02d:%02d",
                State.Stats.Catches,
                State.Stats.Upgrades,
                State.Stats.BonusTaps,
                State.Stats.Moves,
                m,
                s
            )
            if #State.Logs > 0 then
                logLabel.Text = table.concat(State.Logs, "\n")
            else
                logLabel.Text = "No events logged yet."
            end
            task.wait(0.5)
        end
    end)

    -- Global Header Buttons
    stopAllBtn.MouseButton1Click:Connect(function()
        Config.AutoThrowAndCatch = false
        Config.AutoEquipBest = false
        Config.AutoUpgradeStand = false
        Config.AutoBonus = false
        saveConfig()
        syncAllUI()
        pushLog("Emergency STOP ALL")
        setStatus("All tasks stopped", "warn")
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
        local cx, cy = clampPanelToScreen(finalPos.X.Offset, finalPos.Y.Offset, panelWidth, panelHeight)
        mainFrame.Position = UDim2.fromOffset(cx, cy)
        Config.PanelPosOffset = { math.floor(cx), math.floor(cy) }
        saveConfig()
    end)

    makeDraggable(bubbleBtn, bubbleBtn)

    return setStatus
end

local setStatus = createProMobileUI()
pushLog("Hub V3 initialized")

local function safeInvoke(remoteFunc, ...)
    local ok, res = pcall(function(...)
        return remoteFunc:InvokeServer(...)
    end, ...)

    if not ok then
        return false, { Ok = false, Reason = tostring(res) }
    end
    if type(res) ~= "table" then
        return true, res
    end
    return true, res
end

local function isBonusWindowActive()
    return os.clock() < State.BonusActiveUntil
end

local function triggerBonusWindow(bonusArg)
    if typeof(bonusArg) == "number" and bonusArg > 0 then
        State.CurrentBonusId = math.floor(bonusArg)
    end
    State.BonusActiveUntil = os.clock() + Config.BonusDuration
    pushLog("Bonus window triggered (#" .. tostring(State.CurrentBonusId) .. ")")
end

local function bindTrainingBonusListener()
    local bonusEvent = Training_Bonus or Remotes:FindFirstChild("Training_Bonus")
    if bonusEvent and bonusEvent:IsA("RemoteEvent") then
        bonusEvent.OnClientEvent:Connect(function(arg1, _)
            if Config.AutoBonus then
                triggerBonusWindow(arg1)
            end
        end)
    end
end

bindTrainingBonusListener()

local function tryEquipBest()
    if not Config.AutoEquipBest then
        return
    end
    setStatus("Equipping best...", "active")
    local ok, res = safeInvoke(Plot_EquipBest)
    if ok and (type(res) ~= "table" or res.Ok ~= false) then
        setStatus("Plot updated", "active")
    end
end

local function runThrowAndCatchStep()
    if not Config.AutoThrowAndCatch then
        if not Config.AutoUpgradeStand and not isBonusWindowActive() and not State.IsThrowing then
            setStatus("Idle", "idle")
        end
        task.wait(0.35)
        return
    end

    if State.IsThrowing or State.IsMoving then
        task.wait(0.15)
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
    if not startOk or (type(startRes) == "table" and not startRes.Ok) then
        local reason = (type(startRes) == "table" and startRes.Reason) or "StartFail"
        State.IsThrowing = false

        if reason == "TooFar" then
            if Config.AutoMoveOnTooFar and Config.SavedThrowCFrame then
                setStatus("TooFar -> Moving to Throw Pos...", "warn")
                pushLog("Throw TooFar -> Auto move")
                moveToThrowPos()
                task.wait(0.30)
                return
            else
                setStatus("TooFar! Save Throw Pos", "warn")
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
    if not resolveOk or (type(resolveRes) == "table" and not resolveRes.Ok) then
        local reason = (type(resolveRes) == "table" and resolveRes.Reason) or "ResolveFail"
        State.IsThrowing = false
        setStatus("Resolve: " .. tostring(reason), "warn")
        task.wait(0.4)
        return
    end

    local flightTime = (type(resolveRes) == "table" and tonumber(resolveRes.FlightTime)) or 1.4
    setStatus(string.format("Flying (%.1fs)...", flightTime), "active")
    task.wait(math.clamp(flightTime, 0.2, 5) + Config.ExtraWaitAfterFlight)

    setStatus("Completing catch...", "active")
    local completeOk, completeRes = safeInvoke(Throw_Complete)
    State.IsThrowing = false

    if completeOk and (type(completeRes) ~= "table" or completeRes.Ok ~= false) then
        State.Stats.Catches += 1
        local caughtName = (type(resolveRes) == "table" and resolveRes.ModelName)
            or (type(completeRes) == "table" and completeRes.AnimalId)
            or "OK"
        setStatus("Caught: " .. tostring(caughtName), "active")
        pushLog("Caught: " .. tostring(caughtName))
        if type(completeRes) == "table" and (completeRes.AnimalId or (type(resolveRes) == "table" and resolveRes.IsNew)) then
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
    if not ready or State.IsThrowing or State.IsMoving then
        task.wait(0.4)
        return
    end

    setStatus("Upgrading stand...", "active")
    local ok, res = safeInvoke(Stand_Upgrade)

    if ok and (type(res) ~= "table" or res.Ok ~= false) then
        State.Stats.Upgrades += 1
        local lv = (type(res) == "table" and res.NewIndex) or "OK"
        setStatus("Stand Lv -> " .. tostring(lv), "active")
        pushLog("Upgraded Stand -> Lv " .. tostring(lv))
        tryEquipBest()
        task.wait(Config.UpgradeInterval)
    else
        local reason = (type(res) == "table" and res.Reason) or ""
        if reason == "TooFar" and Config.AutoMoveOnTooFar and Config.SavedStandCFrame then
            setStatus("Stand TooFar -> Moving...", "warn")
            moveToStandPos()
            task.wait(0.35)
            return
        end
        task.wait(Config.UpgradeInterval + Config.FailBackoff)
    end
end

local function runEquipLoop()
    if not Config.AutoEquipBest then
        task.wait(0.6)
        return
    end

    local _, _, ready = isCharacterReady()
    if ready and not State.IsThrowing and not State.IsMoving then
        tryEquipBest()
    end
    task.wait(Config.EquipInterval)
end

local function runBonusStep()
    if not Config.AutoBonus then
        task.wait(0.25)
        return
    end

    if not isBonusWindowActive() then
        task.wait(0.15)
        return
    end

    local tapRemote = Training_TapBonus or Remotes:FindFirstChild("Training_TapBonus")
    if not tapRemote then
        setStatus("Missing Training_TapBonus", "warn")
        task.wait(1)
        return
    end

    local remaining = math.max(0, State.BonusActiveUntil - os.clock())
    setStatus(string.format("Bonus x2 (%.1fs)...", remaining), "active")
    local ok = safeInvoke(tapRemote, State.CurrentBonusId)
    if ok then
        State.Stats.BonusTaps += 1
    end
    task.wait(Config.BonusTapDelay)
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

task.spawn(function()
    while true do
        runEquipLoop()
        task.wait(0.2)
    end
end)

task.spawn(function()
    while true do
        runBonusStep()
        task.wait(0.05)
    end
end)
