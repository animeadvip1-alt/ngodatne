local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local P = string.char(0xE2, 0x81, 0x82) -- Tiền tố gói tin của game

-- Cấu hình đơn vị & tọa độ đã ghi
local CONFIG = {
    Difficulty = "Easy",
    StartDelay = 1.5,
    PlaceDelay = 0.6,
    Placements = {
        {unit = "CarSpeakerman", pos = Vector3.new(-60.6, 0.3, -52.4), rot = 1},
        {unit = "CarSpeakerman", pos = Vector3.new(-83.2, 0.3, -51.5), rot = 1},
        {unit = "CarSpeakerman", pos = Vector3.new(-102.5, 0.3, -42.7), rot = 1},
    }
}

-- Xóa UI cũ nếu chạy lại script
local guiParent = (gethui and gethui()) or game:GetService("CoreGui")
if not pcall(function() local _ = guiParent.Name end) then
    guiParent = LocalPlayer:WaitForChild("PlayerGui")
end
local oldGui = guiParent:FindFirstChild("TDAutoHub_V3Style")
if oldGui then oldGui:Destroy() end

-- Tạo ScreenGui
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "TDAutoHub_V3Style"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = guiParent

local function addCorner(obj, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 8)
    c.Parent = obj
    return c
end

local function addStroke(obj, color, transparency)
    local s = Instance.new("UIStroke")
    s.Color = color or Color3.fromRGB(48, 52, 62)
    s.Transparency = transparency or 0.4
    s.Thickness = 1
    s.Parent = obj
    return s
end

-- Khung chính (294x385 chuẩn mobile)
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 294, 0, 385)
MainFrame.Position = UDim2.new(0.5, -147, 0.5, -192)
MainFrame.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.Parent = ScreenGui
addCorner(MainFrame, 10)
addStroke(MainFrame, Color3.fromRGB(55, 60, 72), 0.3)

-- Thanh tiêu đề (Kéo thả)
local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 36)
Header.BackgroundColor3 = Color3.fromRGB(24, 27, 35)
Header.BorderSizePixel = 0
Header.Parent = MainFrame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -76, 1, 0)
Title.Position = UDim2.new(0, 12, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "TD Auto Hub"
Title.TextColor3 = Color3.fromRGB(235, 238, 245)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 14
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Header

local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.new(0, 26, 0, 26)
MinBtn.Position = UDim2.new(1, -60, 0, 5)
MinBtn.BackgroundColor3 = Color3.fromRGB(34, 38, 48)
MinBtn.Text = "-"
MinBtn.TextColor3 = Color3.fromRGB(210, 215, 225)
MinBtn.Font = Enum.Font.GothamBold
MinBtn.TextSize = 15
MinBtn.Parent = Header
addCorner(MinBtn, 6)

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 26, 0, 26)
CloseBtn.Position = UDim2.new(1, -30, 0, 5)
CloseBtn.BackgroundColor3 = Color3.fromRGB(48, 30, 34)
CloseBtn.Text = "×"
CloseBtn.TextColor3 = Color3.fromRGB(240, 110, 115)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 15
CloseBtn.Parent = Header
addCorner(CloseBtn, 6)

-- Kéo thả khung UI (Hỗ trợ cả cảm ứng & chuột)
do
    local dragging, dragStart, startPos
    Header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = MainFrame.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

-- Vùng nội dung
local Body = Instance.new("Frame")
Body.Size = UDim2.new(1, -20, 1, -46)
Body.Position = UDim2.new(0, 10, 0, 40)
Body.BackgroundTransparency = 1
Body.Parent = MainFrame

-- 1. Thanh trạng thái với chấm màu chỉ báo
local StatusBar = Instance.new("Frame")
StatusBar.Size = UDim2.new(1, 0, 0, 34)
StatusBar.BackgroundColor3 = Color3.fromRGB(25, 28, 36)
StatusBar.Parent = Body
addCorner(StatusBar, 8)
addStroke(StatusBar)

local StatusDot = Instance.new("Frame")
StatusDot.Size = UDim2.new(0, 10, 0, 10)
StatusDot.Position = UDim2.new(0, 12, 0.5, -5)
StatusDot.BackgroundColor3 = Color3.fromRGB(245, 185, 65)
StatusDot.Parent = StatusBar
addCorner(StatusDot, 99)

local StatusText = Instance.new("TextLabel")
StatusText.Size = UDim2.new(1, -34, 1, 0)
StatusText.Position = UDim2.new(0, 28, 0, 0)
StatusText.BackgroundTransparency = 1
StatusText.Text = "Đang khởi tạo..."
StatusText.TextColor3 = Color3.fromRGB(225, 230, 240)
StatusText.Font = Enum.Font.GothamMedium
StatusText.TextSize = 12
StatusText.TextXAlignment = Enum.TextXAlignment.Left
StatusText.TextTruncate = Enum.TextTruncate.AtEnd
StatusText.Parent = StatusBar

-- 2. Hàng công tắc gạt (Toggle Switch)
local ToggleCard = Instance.new("Frame")
ToggleCard.Size = UDim2.new(1, 0, 0, 42)
ToggleCard.Position = UDim2.new(0, 0, 0, 42)
ToggleCard.BackgroundColor3 = Color3.fromRGB(25, 28, 36)
ToggleCard.Parent = Body
addCorner(ToggleCard, 8)
addStroke(ToggleCard)

local ToggleLabel = Instance.new("TextLabel")
ToggleLabel.Size = UDim2.new(1, -68, 1, 0)
ToggleLabel.Position = UDim2.new(0, 12, 0, 0)
ToggleLabel.BackgroundTransparency = 1
ToggleLabel.Text = "Tự chọn Easy + Đặt 3 quân"
ToggleLabel.TextColor3 = Color3.fromRGB(230, 234, 242)
ToggleLabel.Font = Enum.Font.GothamMedium
ToggleLabel.TextSize = 12
ToggleLabel.TextXAlignment = Enum.TextXAlignment.Left
ToggleLabel.Parent = ToggleCard

local SwitchBg = Instance.new("TextButton")
SwitchBg.Size = UDim2.new(0, 42, 0, 22)
SwitchBg.Position = UDim2.new(1, -52, 0.5, -11)
SwitchBg.BackgroundColor3 = Color3.fromRGB(52, 56, 68)
SwitchBg.Text = ""
SwitchBg.AutoButtonColor = false
SwitchBg.Parent = ToggleCard
addCorner(SwitchBg, 99)

local SwitchKnob = Instance.new("Frame")
SwitchKnob.Size = UDim2.new(0, 16, 0, 16)
SwitchKnob.Position = UDim2.new(0, 3, 0.5, -8)
SwitchKnob.BackgroundColor3 = Color3.fromRGB(240, 242, 248)
SwitchKnob.Parent = SwitchBg
addCorner(SwitchKnob, 99)

-- 3. Nút thao tác nhanh
local RunOnceBtn = Instance.new("TextButton")
RunOnceBtn.Size = UDim2.new(0.62, -3, 0, 30)
RunOnceBtn.Position = UDim2.new(0, 0, 0, 92)
RunOnceBtn.BackgroundColor3 = Color3.fromRGB(46, 125, 235)
RunOnceBtn.Text = "Chạy đặt quân ngay"
RunOnceBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
RunOnceBtn.Font = Enum.Font.GothamBold
RunOnceBtn.TextSize = 12
RunOnceBtn.Parent = Body
addCorner(RunOnceBtn, 7)

local ClearBtn = Instance.new("TextButton")
ClearBtn.Size = UDim2.new(0.38, -3, 0, 30)
ClearBtn.Position = UDim2.new(0.62, 3, 0, 92)
ClearBtn.BackgroundColor3 = Color3.fromRGB(34, 38, 48)
ClearBtn.Text = "Xóa Log"
ClearBtn.TextColor3 = Color3.fromRGB(200, 206, 218)
ClearBtn.Font = Enum.Font.GothamMedium
ClearBtn.TextSize = 12
ClearBtn.Parent = Body
addCorner(ClearBtn, 7)

-- 4. Bảng thông tin trực tiếp (Stats)
local InfoBox = Instance.new("Frame")
InfoBox.Size = UDim2.new(1, 0, 0, 52)
InfoBox.Position = UDim2.new(0, 0, 0, 130)
InfoBox.BackgroundColor3 = Color3.fromRGB(25, 28, 36)
InfoBox.Parent = Body
addCorner(InfoBox, 8)
addStroke(InfoBox)

local RemoteStat = Instance.new("TextLabel")
RemoteStat.Size = UDim2.new(1, -20, 0, 20)
RemoteStat.Position = UDim2.new(0, 10, 0, 5)
RemoteStat.BackgroundTransparency = 1
RemoteStat.Text = "Remote: Đang dò..."
RemoteStat.TextColor3 = Color3.fromRGB(175, 185, 205)
RemoteStat.Font = Enum.Font.Gotham
RemoteStat.TextSize = 11
RemoteStat.TextXAlignment = Enum.TextXAlignment.Left
RemoteStat.Parent = InfoBox

local ServerStat = Instance.new("TextLabel")
ServerStat.Size = UDim2.new(1, -20, 0, 20)
ServerStat.Position = UDim2.new(0, 10, 0, 26)
ServerStat.BackgroundTransparency = 1
ServerStat.Text = "Server phản hồi: Chưa có dữ liệu"
ServerStat.TextColor3 = Color3.fromRGB(130, 210, 165)
ServerStat.Font = Enum.Font.Gotham
ServerStat.TextSize = 11
ServerStat.TextXAlignment = Enum.TextXAlignment.Left
ServerStat.TextTruncate = Enum.TextTruncate.AtEnd
ServerStat.Parent = InfoBox

-- 5. Khung nhật ký hoạt động (Event Log)
local LogFrame = Instance.new("ScrollingFrame")
LogFrame.Size = UDim2.new(1, 0, 1, -190)
LogFrame.Position = UDim2.new(0, 0, 0, 190)
LogFrame.BackgroundColor3 = Color3.fromRGB(14, 16, 21)
LogFrame.BorderSizePixel = 0
LogFrame.ScrollBarThickness = 3
LogFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
LogFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
LogFrame.Parent = Body
addCorner(LogFrame, 8)
addStroke(LogFrame)

local LogLayout = Instance.new("UIListLayout")
LogLayout.Padding = UDim.new(0, 4)
LogLayout.SortOrder = Enum.SortOrder.LayoutOrder
LogLayout.Parent = LogFrame

local LogPad = Instance.new("UIPadding")
LogPad.PaddingTop = UDim.new(0, 6)
LogPad.PaddingBottom = UDim.new(0, 6)
LogPad.PaddingLeft = UDim.new(0, 8)
LogPad.PaddingRight = UDim.new(0, 8)
LogPad.Parent = LogFrame

-- Hàm cập nhật giao diện & log
local logOrder = 0
local function setStatus(text, color)
    StatusText.Text = text
    StatusDot.BackgroundColor3 = color or Color3.fromRGB(90, 210, 130)
end

local function addLog(msg, color)
    logOrder += 1
    local item = Instance.new("TextLabel")
    item.LayoutOrder = logOrder
    item.Size = UDim2.new(1, 0, 0, 0)
    item.AutomaticSize = Enum.AutomaticSize.Y
    item.BackgroundTransparency = 1
    item.Text = string.format("[%s] %s", os.date("%H:%M:%S"), msg)
    item.TextColor3 = color or Color3.fromRGB(205, 212, 224)
    item.Font = Enum.Font.Code
    item.TextSize = 11
    item.TextWrapped = true
    item.TextXAlignment = Enum.TextXAlignment.Left
    item.Parent = LogFrame
    task.defer(function()
        LogFrame.CanvasPosition = Vector2.new(0, math.huge)
    end)
end

-- Tìm DataRemote
local container = ReplicatedStorage:FindFirstChild("NetworkingContainer")
local DataRemote = (container and container:FindFirstChild("DataRemote"))
    or ReplicatedStorage:FindFirstChild("DataRemote", true)

if DataRemote then
    RemoteStat.Text = "Remote: Đã kết nối (" .. DataRemote.Name .. ")"
    RemoteStat.TextColor3 = Color3.fromRGB(115, 220, 145)
    setStatus("Sẵn sàng hoạt động", Color3.fromRGB(90, 210, 130))
    addLog("Tìm thấy DataRemote thành công.", Color3.fromRGB(115, 220, 145))

    -- Lắng nghe phản hồi từ server để xác nhận lệnh có ăn hay không
    DataRemote.OnClientEvent:Connect(function(header, a1)
        if header == P .. "/" then
            ServerStat.Text = "Server: " .. tostring(a1)
            addLog("Server thông báo: " .. tostring(a1), Color3.fromRGB(130, 195, 255))
        elseif header == P .. "k" then
            ServerStat.Text = "Server: Đã đặt " .. tostring(a1) .. " đơn vị trên sân"
            addLog("Xác nhận số đơn vị trên sân: " .. tostring(a1), Color3.fromRGB(115, 220, 145))
        end
    end)
else
    RemoteStat.Text = "Remote: Không tìm thấy DataRemote"
    RemoteStat.TextColor3 = Color3.fromRGB(245, 105, 110)
    setStatus("Lỗi: Thiếu DataRemote", Color3.fromRGB(245, 105, 110))
    addLog("Không tìm thấy DataRemote trong ReplicatedStorage.", Color3.fromRGB(245, 105, 110))
end

-- Hàm thực thi chính
local isRunning = false
local autoEnabled = false

local function runSequence()
    if isRunning then
        addLog("Đang chạy tiến trình, vui lòng chờ...", Color3.fromRGB(245, 195, 80))
        return
    end
    if not DataRemote then
        addLog("Không thể chạy vì thiếu DataRemote.", Color3.fromRGB(245, 105, 110))
        return
    end

    isRunning = true
    setStatus("Đang chọn độ khó " .. CONFIG.Difficulty .. "...", Color3.fromRGB(95, 175, 255))
    DataRemote:FireServer(P .. "}", CONFIG.Difficulty)
    addLog("Gửi lệnh chọn độ khó: " .. CONFIG.Difficulty)

    task.wait(CONFIG.StartDelay)

    for i, d in ipairs(CONFIG.Placements) do
        if not autoEnabled and i > 1 and not isRunning then break end
        setStatus(string.format("Đặt %s (%d/%d)...", d.unit, i, #CONFIG.Placements), Color3.fromRGB(245, 195, 80))
        DataRemote:FireServer(P .. "e", d.unit, d.pos, d.rot)
        addLog(string.format("Đặt #%d %s tại (%.1f, %.1f, %.1f)", i, d.unit, d.pos.X, d.pos.Y, d.pos.Z))
        task.wait(CONFIG.PlaceDelay)
    end

    isRunning = false
    setStatus("Hoàn tất lượt đặt quân", Color3.fromRGB(90, 210, 130))
    addLog("Đã gửi xong toàn bộ lệnh đặt đơn vị.", Color3.fromRGB(115, 220, 145))
end

-- Sự kiện nút bấm & công tắc
local function updateToggleVisual(state)
    TweenService:Create(SwitchBg, TweenInfo.new(0.18), {
        BackgroundColor3 = state and Color3.fromRGB(46, 125, 235) or Color3.fromRGB(52, 56, 68)
    }):Play()
    TweenService:Create(SwitchKnob, TweenInfo.new(0.18), {
        Position = state and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
    }):Play()
end

SwitchBg.MouseButton1Click:Connect(function()
    autoEnabled = not autoEnabled
    updateToggleVisual(autoEnabled)
    if autoEnabled then
        addLog("Đã BẬT tự động.", Color3.fromRGB(115, 220, 145))
        task.spawn(runSequence)
    else
        setStatus("Đã tạm dừng", Color3.fromRGB(170, 175, 190))
        addLog("Đã TẮT tự động.", Color3.fromRGB(245, 195, 80))
    end
end)

RunOnceBtn.MouseButton1Click:Connect(function()
    task.spawn(runSequence)
end)

ClearBtn.MouseButton1Click:Connect(function()
    for _, child in ipairs(LogFrame:GetChildren()) do
        if child:IsA("TextLabel") then child:Destroy() end
    end
end)

local minimized = false
MinBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    MinBtn.Text = minimized and "+" or "-"
    TweenService:Create(MainFrame, TweenInfo.new(0.2), {
        Size = minimized and UDim2.new(0, 294, 0, 36) or UDim2.new(0, 294, 0, 385)
    }):Play()
end)

CloseBtn.MouseButton1Click:Connect(function()
    ScreenGui:Destroy()
end)

UserInputService.InputBegan:Connect(function(input, gp)
    if not gp and input.KeyCode == Enum.KeyCode.RightShift then
        MainFrame.Visible = not MainFrame.Visible
    end
end)
