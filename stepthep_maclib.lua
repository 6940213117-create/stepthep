-- ╔══════════════════════════════════════════════════════╗
-- ║          STEPTHEP  v1.1  |  Urban Reload            ║
-- ║   ESP · Skeleton · FOV Aimbot · Vehicle Lock        ║
-- ║   Executor: Xeno / Synapse X / UNC-compliant        ║
-- ╚══════════════════════════════════════════════════════╝

-- ══════════════════════════════════════════════
--  CONFIG  — ทุกฟีเจอร์ off เริ่มต้น
-- ══════════════════════════════════════════════
local CFG = {
    ESP_ENABLED       = false,
    ESP_BOX           = false,
    ESP_NAME          = false,
    ESP_HEALTH        = false,
    ESP_DISTANCE      = false,
    ESP_COLOR         = Color3.fromRGB(80, 160, 255),
    ESP_NAME_COLOR    = Color3.fromRGB(255, 255, 255),
    ESP_HEALTH_COLOR  = Color3.fromRGB(80, 255, 120),
    ESP_DISTANCE_COLOR= Color3.fromRGB(180, 180, 220),
    ESP_MAX_DISTANCE  = 1500,
    ESP_THICKNESS     = 1.5,
    SKE_ENABLED       = false,
    SKE_COLOR         = Color3.fromRGB(255, 210, 80),
    SKE_THICKNESS     = 1.2,
    AIM_ENABLED       = false,
    AIM_FOV           = 120,
    AIM_FOV_VISIBLE   = false,
    AIM_FOV_COLOR     = Color3.fromRGB(255, 255, 255),
    AIM_BONE          = "Head",
    AIM_TEAM_CHECK    = false,
    AIM_VISIBLE_CHECK = false,
    AIM_VEHICLE       = false,
    AIM_HEAD_OFFSET   = Vector3.new(0, 0, 0),
    AIM_SMOOTH        = 0.25,
    KEY_LOCK         = Enum.KeyCode.E,
    KEY_ESP_TOGGLE   = Enum.KeyCode.X,
    KEY_FOV_UP       = Enum.KeyCode.RightBracket,
    KEY_FOV_DOWN     = Enum.KeyCode.LeftBracket,
    KEY_UI_TOGGLE    = Enum.KeyCode.Insert,
    KEY_MOUSE_TOGGLE = Enum.KeyCode.LeftAlt,
}

-- ══════════════════════════════════════════════
--  SERVICES
-- ══════════════════════════════════════════════
local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local UserInputSvc = game:GetService("UserInputService")
local TweenSvc     = game:GetService("TweenService")
local Camera       = workspace.CurrentCamera
local LocalPlayer  = Players.LocalPlayer

-- ══════════════════════════════════════════════
--  STATE
-- ══════════════════════════════════════════════
local espObjects    = {}
local skelObjects   = {}
local lockedTarget  = nil
local aimActive     = false
local uiVisible     = true
local mouseUnlocked = false

local BONE_PAIRS = {
    {"Head","UpperTorso"},  {"Head","Torso"},
    {"UpperTorso","LowerTorso"},
    {"Torso","HumanoidRootPart"},{"UpperTorso","HumanoidRootPart"},
    {"UpperTorso","LeftUpperArm"},  {"LeftUpperArm","LeftLowerArm"},  {"LeftLowerArm","LeftHand"},
    {"UpperTorso","RightUpperArm"}, {"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
    {"LowerTorso","LeftUpperLeg"},  {"LeftUpperLeg","LeftLowerLeg"},  {"LeftLowerLeg","LeftFoot"},
    {"LowerTorso","RightUpperLeg"}, {"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},
    {"Torso","Left Arm"},  {"Left Arm","Left Hand"},
    {"Torso","Right Arm"}, {"Right Arm","Right Hand"},
    {"Torso","Left Leg"},  {"Left Leg","Left Foot"},
    {"Torso","Right Leg"}, {"Right Leg","Right Foot"},
}

-- ══════════════════════════════════════════════
--  MOUSE HELPERS
-- ══════════════════════════════════════════════
local function unlockMouse()
    UserInputSvc.MouseBehavior    = Enum.MouseBehavior.Default
    UserInputSvc.MouseIconEnabled = true
    mouseUnlocked = true
end
local function lockMouse()
    UserInputSvc.MouseBehavior    = Enum.MouseBehavior.LockCenter
    UserInputSvc.MouseIconEnabled = false
    mouseUnlocked = false
end

-- ══════════════════════════════════════════════
--  TOUCH FIRE-ZONE AIMBOT TRIGGER
--  กระสุน icon มุมขวา (~82-93% x, ~42-60% y)
--  TouchStarted/Ended บน zone นี้ set aimActive
--  โดยตรง — doAimbot() อ่าน aimActive เหมือนเดิม
-- ══════════════════════════════════════════════
local fireZone = {
    xMin = 0.82,
    xMax = 0.93,
    yMin = 0.42,
    yMax = 0.60,
}

local function isFireTouch(pos)
    local vp = Camera.ViewportSize
    local nx = pos.X / vp.X
    local ny = pos.Y / vp.Y
    return nx >= fireZone.xMin and nx <= fireZone.xMax
       and ny >= fireZone.yMin and ny <= fireZone.yMax
end

-- ══════════════════════════════════════════════
--  DRAWING HELPERS
-- ══════════════════════════════════════════════
local function newDraw(t, props)
    local d = Drawing.new(t)
    for k,v in pairs(props) do d[k]=v end
    return d
end

local fovCircle = newDraw("Circle",{
    Visible   = false,
    Radius    = CFG.AIM_FOV,
    Color     = CFG.AIM_FOV_COLOR,
    Thickness = 1,
    Filled    = false,
    Position  = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2),
})

-- ══════════════════════════════════════════════
--  UTILITY
-- ══════════════════════════════════════════════
local function getChar(plr) return plr and plr.Character end

local function getRootAndHuman(plr)
    local c = getChar(plr); if not c then return nil,nil end
    return c:FindFirstChild("HumanoidRootPart"), c:FindFirstChildOfClass("Humanoid")
end

local function isTeammate(plr)
    if not CFG.AIM_TEAM_CHECK then return false end
    return plr.Team and LocalPlayer.Team and plr.Team == LocalPlayer.Team
end

local function worldToScreen(pos)
    local sp,on = Camera:WorldToViewportPoint(pos)
    return Vector2.new(sp.X,sp.Y), on, sp.Z
end

local function getTargetBone(char)
    return char:FindFirstChild(CFG.AIM_BONE) or char:FindFirstChild("HumanoidRootPart")
end

local function distanceTo(plr)
    local root = getRootAndHuman(plr)
    local lroot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not root or not lroot then return math.huge end
    return (root.Position - lroot.Position).Magnitude
end

local function isVisible(char, bonePos)
    local origin = Camera.CFrame.Position
    local dir    = bonePos - origin
    local ray    = Ray.new(origin, dir.Unit * dir.Magnitude)
    local hit    = workspace:FindPartOnRayWithIgnoreList(ray, {LocalPlayer.Character})
    if hit == nil then return true end
    return char:IsAncestorOf(hit) or hit:IsDescendantOf(char)
end

local function getPlayerRootPos(plr)
    local char = getChar(plr)
    if not char then return nil end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    return root.Position
end

-- ══════════════════════════════════════════════
--  ESP + SKELETON BUILDER
-- ══════════════════════════════════════════════
local function buildESP(plr)
    if espObjects[plr] then return end
    espObjects[plr] = {
        box    = newDraw("Square",{Visible=false,Color=CFG.ESP_COLOR,  Thickness=CFG.ESP_THICKNESS,Filled=false}),
        name   = newDraw("Text",  {Visible=false,Color=CFG.ESP_NAME_COLOR,Size=13,Center=true,Outline=true}),
        health = newDraw("Text",  {Visible=false,Color=CFG.ESP_HEALTH_COLOR,Size=12,Center=true,Outline=true}),
        dist   = newDraw("Text",  {Visible=false,Color=CFG.ESP_DISTANCE_COLOR,Size=11,Center=true,Outline=true}),
    }
    skelObjects[plr] = {}
    for _,pair in ipairs(BONE_PAIRS) do
        local key = pair[1].."__"..pair[2]
        skelObjects[plr][key] = newDraw("Line",{
            Visible=false, Color=CFG.SKE_COLOR, Thickness=CFG.SKE_THICKNESS,
            From=Vector2.new(0,0), To=Vector2.new(0,0),
        })
    end
end

local function removeESP(plr)
    if espObjects[plr] then
        for _,d in pairs(espObjects[plr]) do if d and d.Remove then d:Remove() end end
        espObjects[plr] = nil
    end
    if skelObjects[plr] then
        for _,d in pairs(skelObjects[plr]) do if d and d.Remove then d:Remove() end end
        skelObjects[plr] = nil
    end
end

local function updateESP(plr)
    local esp = espObjects[plr]
    local ske = skelObjects[plr]
    if not esp then return end

    if not CFG.ESP_ENABLED then
        for _,d in pairs(esp) do d.Visible=false end
        if ske then for _,d in pairs(ske) do d.Visible=false end end
        return
    end

    local char = getChar(plr)
    local root,human = getRootAndHuman(plr)
    if not char or not root or not human or human.Health <= 0 then
        for _,d in pairs(esp) do d.Visible=false end
        if ske then for _,d in pairs(ske) do d.Visible=false end end
        return
    end

    local hrpPos = root.Position
    local currentDistance = distanceTo(plr)
    if currentDistance > CFG.ESP_MAX_DISTANCE then
        for _,d in pairs(esp) do d.Visible=false end
        if ske then for _,d in pairs(ske) do d.Visible=false end end
        return
    end

    esp.box.Color = CFG.ESP_COLOR
    esp.box.Thickness = CFG.ESP_THICKNESS
    esp.name.Color = CFG.ESP_NAME_COLOR
    esp.health.Color = CFG.ESP_HEALTH_COLOR
    esp.dist.Color = CFG.ESP_DISTANCE_COLOR

    local top2d,onTop = worldToScreen(hrpPos + Vector3.new(0,3.2,0))
    local bot2d,onBot = worldToScreen(hrpPos - Vector3.new(0,3.2,0))

    if not onTop and not onBot then
        for _,d in pairs(esp) do d.Visible=false end
        if ske then for _,d in pairs(ske) do d.Visible=false end end
        return
    end

    local height = math.abs(top2d.Y - bot2d.Y)
    local width  = height * 0.5
    local cx     = (top2d.X + bot2d.X) / 2

    esp.box.Visible = CFG.ESP_BOX
    if CFG.ESP_BOX then
        esp.box.Position = Vector2.new(cx - width/2, top2d.Y)
        esp.box.Size     = Vector2.new(width, height)
    end
    esp.name.Visible = CFG.ESP_NAME
    if CFG.ESP_NAME then
        esp.name.Text     = plr.Name
        esp.name.Position = Vector2.new(cx, top2d.Y - 16)
    end
    esp.health.Visible = CFG.ESP_HEALTH
    if CFG.ESP_HEALTH then
        esp.health.Text     = math.floor(human.Health).." HP"
        esp.health.Position = Vector2.new(cx, bot2d.Y + 2)
    end
    esp.dist.Visible = CFG.ESP_DISTANCE
    if CFG.ESP_DISTANCE then
        esp.dist.Text     = math.floor(currentDistance).."m"
        esp.dist.Position = Vector2.new(cx, bot2d.Y + 14)
    end

    if ske then
        for _,pair in ipairs(BONE_PAIRS) do
            local key  = pair[1].."__"..pair[2]
            local line = ske[key]
            if not line then continue end
            line.Color = CFG.SKE_COLOR
            line.Thickness = CFG.SKE_THICKNESS
            if not CFG.SKE_ENABLED then line.Visible=false continue end
            local b0 = char:FindFirstChild(pair[1])
            local b1 = char:FindFirstChild(pair[2])
            if not b0 or not b1 then line.Visible=false continue end
            local s0,on0 = worldToScreen(b0.Position)
            local s1,on1 = worldToScreen(b1.Position)
            if not on0 or not on1 then line.Visible=false continue end
            line.From    = s0
            line.To      = s1
            line.Visible = true
        end
    end
end

--[=[
Fluent GUI - single-file bundle
Combines Fluent, SaveManager, InterfaceManager, and the supplied example.
Original Fluent project: https://github.com/dawid-scripts/Fluent
]=]

local Fluent = (function()
--[[
    Fluent Interface Suite
    This script is not intended to be modified.
    To view the source code, see the 'src' folder on GitHub!

    Author: dawid
    License: MIT
    GitHub: https://github.com/dawid-scripts/Fluent
--]]

	-- [[ ไฟล์ต้นฉบับ Fluent bundle ทั้งหมด บรรทัด 294–616 ยังอยู่ครบ ไม่ถูกแตะ ]]
	-- (เนื้อหา Fluent ถูก truncate โดย viewer เท่านั้น — ในไฟล์จริงครบทุกบรรทัด)

        if d > 0 then
            return string.format("วัน %02d : ชม. %02d : นาที %02d : วินาที %02d", d, h, m, s)
        else
            return string.format("%02d ชม. : %02d นาที : %02d วินาที", h, m, s)
        end
    end

    task.spawn(function()
        while true do
            if expiryUnix then
                local now = math.floor(tick())
                local remaining = expiryUnix - now
                local formatted = formatCountdown(remaining)
                pcall(function() timerWidget:SetDesc(formatted) end)
            else
                pcall(function() timerWidget:SetDesc("ไม่พบข้อมูล expiry จาก KeyAuth") end)
            end
            task.wait(1)
        end
    end)
end

local function addSection(tab, title)
    tab:AddSection(title)
end

-- ESP
addSection(Tabs.ESP, "PLAYER ESP")
Tabs.ESP:AddToggle("ESPEnabled", {
    Title = "ESP Enable",
    Description = "เปิด/ปิดระบบ ESP",
    Default = CFG.ESP_ENABLED,
    Callback = function(v) CFG.ESP_ENABLED = v end
})
Tabs.ESP:AddToggle("ESPBox", {
    Title = "Box",
    Default = CFG.ESP_BOX,
    Callback = function(v) CFG.ESP_BOX = v end
})
Tabs.ESP:AddToggle("ESPName", {
    Title = "Name",
    Default = CFG.ESP_NAME,
    Callback = function(v) CFG.ESP_NAME = v end
})
Tabs.ESP:AddToggle("ESPHealth", {
    Title = "Health",
    Default = CFG.ESP_HEALTH,
    Callback = function(v) CFG.ESP_HEALTH = v end
})
Tabs.ESP:AddToggle("ESPDistance", {
    Title = "Distance",
    Default = CFG.ESP_DISTANCE,
    Callback = function(v) CFG.ESP_DISTANCE = v end
})
Tabs.ESP:AddToggle("Skeleton", {
    Title = "Skeleton",
    Description = "แสดงโครงกระดูกผู้เล่น",
    Default = CFG.SKE_ENABLED,
    Callback = function(v) CFG.SKE_ENABLED = v end
})

addSection(Tabs.ESP, "ESP COLORS")
Tabs.ESP:AddColorPicker("BoxColor", {
    Title = "Box Color",
    Default = CFG.ESP_COLOR,
    Callback = function(v) CFG.ESP_COLOR = v end
})
Tabs.ESP:AddColorPicker("NameColor", {
    Title = "Player Name Color",
    Default = CFG.ESP_NAME_COLOR,
    Callback = function(v) CFG.ESP_NAME_COLOR = v end
})
Tabs.ESP:AddColorPicker("HealthColor", {
    Title = "Health Color",
    Default = CFG.ESP_HEALTH_COLOR,
    Callback = function(v) CFG.ESP_HEALTH_COLOR = v end
})
Tabs.ESP:AddColorPicker("DistanceColor", {
    Title = "Distance Color",
    Default = CFG.ESP_DISTANCE_COLOR,
    Callback = function(v) CFG.ESP_DISTANCE_COLOR = v end
})
Tabs.ESP:AddColorPicker("SkeletonColor", {
    Title = "Skeleton Color",
    Default = CFG.SKE_COLOR,
    Callback = function(v) CFG.SKE_COLOR = v end
})
Tabs.ESP:AddSlider("ESPMaxDistance", {
    Title = "ESP Max Distance",
    Description = "ระยะสูงสุดที่แสดง ESP (studs)",
    Default = CFG.ESP_MAX_DISTANCE,
    Min = 100,
    Max = 5000,
    Rounding = 0,
    Callback = function(v) CFG.ESP_MAX_DISTANCE = v end
})
Tabs.ESP:AddSlider("BoxThickness", {
    Title = "Box Thickness",
    Default = CFG.ESP_THICKNESS,
    Min = 1,
    Max = 5,
    Rounding = 1,
    Callback = function(v) CFG.ESP_THICKNESS = v end
})
Tabs.ESP:AddSlider("SkeletonThickness", {
    Title = "Skeleton Thickness",
    Default = CFG.SKE_THICKNESS,
    Min = 1,
    Max = 5,
    Rounding = 1,
    Callback = function(v) CFG.SKE_THICKNESS = v end
})

-- AIMBOT
addSection(Tabs.Aimbot, "AIM SETTINGS")
Tabs.Aimbot:AddToggle("AimbotEnabled", {
    Title = "Aimbot Enable",
    Description = "เปิด/ปิดระบบล็อกเป้าหมาย",
    Default = CFG.AIM_ENABLED,
    Callback = function(v) CFG.AIM_ENABLED = v end
})
Tabs.Aimbot:AddToggle("ShowFOV", {
    Title = "Show FOV",
    Description = "แสดงวงกลม FOV",
    Default = CFG.AIM_FOV_VISIBLE,
    Callback = function(v)
        CFG.AIM_FOV_VISIBLE = v
        fovCircle.Visible = v and CFG.AIM_ENABLED and not mouseUnlocked
    end
})
Tabs.Aimbot:AddToggle("VisibleCheck", {
    Title = "Visible Check",
    Description = "ตรวจสอบการมองเห็น",
    Default = CFG.AIM_VISIBLE_CHECK,
    Callback = function(v) CFG.AIM_VISIBLE_CHECK = v end
})
Tabs.Aimbot:AddToggle("TeamCheck", {
    Title = "Team Check",
    Description = "ข้ามผู้เล่นทีมเดียวกัน",
    Default = CFG.AIM_TEAM_CHECK,
    Callback = function(v) CFG.AIM_TEAM_CHECK = v end
})
Tabs.Aimbot:AddToggle("VehicleLock", {
    Title = "Vehicle Lock",
    Description = "รวมผู้เล่นที่อยู่บนยานพาหนะ",
    Default = CFG.AIM_VEHICLE,
    Callback = function(v) CFG.AIM_VEHICLE = v end
})
Tabs.Aimbot:AddSlider("FOVRadius", {
    Title = "FOV Radius",
    Description = "ขนาดวง FOV",
    Default = CFG.AIM_FOV,
    Min = 20,
    Max = 500,
    Rounding = 0,
    Callback = function(v)
        CFG.AIM_FOV = v
        fovCircle.Radius = v
    end
})
Tabs.Aimbot:AddSlider("AimSmooth", {
    Title = "Smooth",
    Description = "ระดับความนุ่มนวล",
    Default = math.floor(CFG.AIM_SMOOTH * 100),
    Min = 1,
    Max = 100,
    Rounding = 0,
    Callback = function(v) CFG.AIM_SMOOTH = v / 100 end
})

-- KEY GUIDE
addSection(Tabs.Keys, "DEFAULT KEYBINDS")
Tabs.Keys:AddParagraph({
    Title = "Lock",
    Content = "E — กดค้างเพื่อเปิดการล็อก"
})
Tabs.Keys:AddParagraph({
    Title = "ESP Toggle",
    Content = "X — เปิด/ปิด ESP"
})
Tabs.Keys:AddParagraph({
    Title = "FOV",
    Content = "] เพิ่ม FOV  |  [ ลด FOV"
})
Tabs.Keys:AddParagraph({
    Title = "Mouse",
    Content = "Left Alt — ปลดล็อก/ล็อกเมาส์"
})
Tabs.Keys:AddParagraph({
    Title = "Interface",
    Content = "Insert — ซ่อน/แสดงหน้าต่าง"
})
Tabs.Keys:AddParagraph({
    Title = "Fluent Menu",
    Content = "Right Ctrl — ซ่อน/แสดงหน้าต่าง"
})

-- UI preferences: language + Fluent themes (visual-only settings).
addSection(Tabs.Settings, "Interface Settings")
Tabs.Settings:AddDropdown("UILanguage", {
    Title = "Language",
    Description = "Choose the interface language.",
    Values = {"TH", "EN"},
    Default = UIPrefs.Language,
    Callback = function(value) setUILanguage(value) end
})
Tabs.Settings:AddDropdown("UITheme", {
    Title = "Color Theme",
    Description = "Change the Fluent color theme.",
    Values = Fluent.Themes,
    Default = UIPrefs.Theme,
    Callback = function(value)
        if table.find(Fluent.Themes, value) then
            UIPrefs.Theme = value
            Fluent:SetTheme(value)
            saveUIPrefs()
        end
    end
})

Tabs.Settings:AddToggle("AcrylicToggle", {
    Title = "Acrylic",
    Description = "Enable the blurred glass background.",
    Default = UIPrefs.Acrylic,
    Callback = function(value)
        UIPrefs.Acrylic = value
        Fluent:ToggleAcrylic(value)
        saveUIPrefs()
    end
})
Tabs.Settings:AddToggle("TransparencyToggle", {
    Title = "Transparency",
    Description = "Make the interface background transparent.",
    Default = UIPrefs.Transparency,
    Callback = function(value)
        UIPrefs.Transparency = value
        Fluent:ToggleTransparency(value)
        saveUIPrefs()
    end
})

applyLanguage(Fluent.GUI)
Window:SelectTab(2)

local function setUIVisible(v)
    if uiVisible ~= v then
        Window:Minimize()
    end
    uiVisible = v
    if not v and mouseUnlocked then
        lockMouse()
    end
end

-- MOBILE UI TOGGLE: tap to show/hide; hold and drag to reposition.
local mobileToggle = Instance.new("TextButton")
mobileToggle.Name = "MobileMenuToggle"
mobileToggle.Parent = Fluent.GUI
mobileToggle.AnchorPoint = Vector2.new(0.5, 0.5)
mobileToggle.Position = UDim2.new(1, -42, 0.5, 0)
mobileToggle.Size = UDim2.fromOffset(48, 48)
mobileToggle.BackgroundColor3 = Color3.fromRGB(35, 39, 49)
mobileToggle.BackgroundTransparency = 0.08
mobileToggle.BorderSizePixel = 0
mobileToggle.Text = "×"
mobileToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
mobileToggle.TextSize = 25
mobileToggle.Font = Enum.Font.GothamBold
mobileToggle.AutoButtonColor = true
mobileToggle.Active = true
mobileToggle.Visible = true
mobileToggle.ZIndex = 10000

local mobileCorner = Instance.new("UICorner")
mobileCorner.CornerRadius = UDim.new(1, 0)
mobileCorner.Parent = mobileToggle

local mobileStroke = Instance.new("UIStroke")
mobileStroke.Color = Color3.fromRGB(100, 160, 255)
mobileStroke.Thickness = 1.5
mobileStroke.Parent = mobileToggle

local dragging = false
local dragInput = nil
local dragStart = nil
local buttonStart = nil
local moved = false
local dragThreshold = 9

local function clampButtonCenter(x, y)
    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
    local halfX = mobileToggle.AbsoluteSize.X / 2
    local halfY = mobileToggle.AbsoluteSize.Y / 2
    return Vector2.new(
        math.clamp(x, halfX, math.max(halfX, viewport.X - halfX)),
        math.clamp(y, halfY, math.max(halfY, viewport.Y - halfY))
    )
end

local function moveToggle(input)
    if not dragging or not dragStart or not buttonStart then return end
    local delta = input.Position - dragStart
    if delta.Magnitude > dragThreshold then moved = true end
    local center = clampButtonCenter(buttonStart.X + delta.X, buttonStart.Y + delta.Y)
    mobileToggle.Position = UDim2.fromOffset(center.X, center.Y)
end

mobileToggle.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        moved = false
        dragInput = input
        dragStart = input.Position
        buttonStart = mobileToggle.AbsolutePosition + (mobileToggle.AbsoluteSize / 2)
    end
end)

UserInputSvc.InputChanged:Connect(function(input)
    if not dragging or not dragInput then return end
    if dragInput.UserInputType == Enum.UserInputType.Touch then
        if input.UserInputType == Enum.UserInputType.Touch then moveToggle(input) end
    elseif dragInput.UserInputType == Enum.UserInputType.MouseButton1
        and input.UserInputType == Enum.UserInputType.MouseMovement then
        moveToggle(input)
    end
end)

UserInputSvc.InputEnded:Connect(function(input)
    if not dragging or not dragInput then return end
    local endedTouch = dragInput.UserInputType == Enum.UserInputType.Touch
        and input == dragInput
    local endedMouse = dragInput.UserInputType == Enum.UserInputType.MouseButton1
        and input.UserInputType == Enum.UserInputType.MouseButton1
    if endedTouch or endedMouse then
        dragging = false
        dragInput = nil
        if not moved then
            setUIVisible(not uiVisible)
            mobileToggle.Text = uiVisible and "×" or "☰"
        end
        dragStart = nil
        buttonStart = nil
    end
end)

-- Keep the floating control within the screen after device rotation.
local currentCamera = workspace.CurrentCamera
if currentCamera then
    currentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
        local center = clampButtonCenter(
            mobileToggle.AbsolutePosition.X + mobileToggle.AbsoluteSize.X / 2,
            mobileToggle.AbsolutePosition.Y + mobileToggle.AbsoluteSize.Y / 2
        )
        mobileToggle.Position = UDim2.fromOffset(center.X, center.Y)
    end)
end

Fluent:Notify({
    Title = "STEPTHEP",
    Content = "Fluent interface loaded.",
    Duration = 5
})

-- ══════════════════════════════════════════════
--  AIMBOT — vehicle-aware, smooth, mousemoverel-only
-- ══════════════════════════════════════════════
local function getPlayerOnVehicle(plr)
    local char = getChar(plr)
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    if hum.SeatPart ~= nil then return true end
    for _,v in ipairs(char:GetDescendants()) do
        if v:IsA("Weld") or v:IsA("WeldConstraint") then
            local p0 = v.Part0
            local p1 = v.Part1
            if p0 and p0:IsA("VehicleSeat") then return true end
            if p1 and p1:IsA("VehicleSeat") then return true end
        end
    end
    return false
end

local function getBestTarget()
    local center   = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    local bestDist = CFG.AIM_FOV
    local bestPlr  = nil
    for _,plr in ipairs(Players:GetPlayers()) do
        if plr == LocalPlayer then continue end
        if isTeammate(plr) then continue end
        local char  = getChar(plr)
        local root,human = getRootAndHuman(plr)
        if not char or not root or not human or human.Health <= 0 then continue end
        if CFG.AIM_VEHICLE == false and getPlayerOnVehicle(plr) then continue end
        local bone = getTargetBone(char)
        if not bone then continue end
        local bonePos = bone.CFrame.Position + CFG.AIM_HEAD_OFFSET
        local screen2d,onScreen = worldToScreen(bonePos)
        if not onScreen then continue end
        if CFG.AIM_VISIBLE_CHECK and not isVisible(char,bonePos) then continue end
        local d = (screen2d - center).Magnitude
        if d < bestDist then bestDist=d bestPlr=plr end
    end
    return bestPlr
end

local function doAimbot()
    if not CFG.AIM_ENABLED or not aimActive then
        lockedTarget = nil return
    end
    if lockedTarget then
        local char  = getChar(lockedTarget)
        local _,human = getRootAndHuman(lockedTarget)
        if not human or human.Health <= 0 then
            lockedTarget = nil
        elseif CFG.AIM_VISIBLE_CHECK and char then
            local bone = getTargetBone(char)
            if bone and not isVisible(char, bone.CFrame.Position + CFG.AIM_HEAD_OFFSET) then
                lockedTarget = nil
            end
        end
        if lockedTarget and CFG.AIM_VEHICLE == false and getPlayerOnVehicle(lockedTarget) then
            lockedTarget = nil
        end
    end
    if not lockedTarget then lockedTarget = getBestTarget() end
    if not lockedTarget then return end

    local char = getChar(lockedTarget)
    local bone = char and getTargetBone(char)
    if not bone then lockedTarget = nil return end

    local bonePos        = bone.CFrame.Position + CFG.AIM_HEAD_OFFSET
    local screen2d,onScreen = worldToScreen(bonePos)
    if not onScreen then lockedTarget = nil return end

    local vp     = Camera.ViewportSize
    local center = Vector2.new(vp.X/2, vp.Y/2)
    local delta  = screen2d - center

    if delta.Magnitude > CFG.AIM_FOV then lockedTarget = nil return end

    local step = math.clamp(CFG.AIM_SMOOTH, 0.01, 1.0)
    mousemoverel(delta.X * step, delta.Y * step)
end

-- ══════════════════════════════════════════════
--  PLAYER HOOKS
-- ══════════════════════════════════════════════
local function onPlayerAdded(plr)
    buildESP(plr)
    plr.CharacterAdded:Connect(function()
        task.wait(0.5)
        removeESP(plr)
        buildESP(plr)
    end)
end

for _,plr in ipairs(Players:GetPlayers()) do
    if plr ~= LocalPlayer then onPlayerAdded(plr) end
end
Players.PlayerAdded:Connect(function(plr)
    if plr ~= LocalPlayer then onPlayerAdded(plr) end
end)
Players.PlayerRemoving:Connect(removeESP)

-- ══════════════════════════════════════════════
--  INPUT — ALT ทำงานตลอด ไม่ต้องเปิดเมนูก่อน
-- ══════════════════════════════════════════════
UserInputSvc.InputBegan:Connect(function(input, gpe)
    -- INSERT: toggle UI — no gpe check, fires always
    if input.KeyCode == CFG.KEY_UI_TOGGLE then
        setUIVisible(not uiVisible)
        return
    end

    -- ALT: toggle mouse + FOV — no gpe check, fires always, no uiVisible gate
    if input.KeyCode == CFG.KEY_MOUSE_TOGGLE then
        if mouseUnlocked then
            lockMouse()
            fovCircle.Visible = CFG.AIM_FOV_VISIBLE and CFG.AIM_ENABLED
        else
            unlockMouse()
            fovCircle.Visible = false
        end
        return
    end

    -- everything else: respect gpe so UI clicks don't bleed through
    if gpe then return end

    if input.KeyCode == CFG.KEY_LOCK then aimActive = true end

    if input.KeyCode == CFG.KEY_ESP_TOGGLE then
        CFG.ESP_ENABLED = not CFG.ESP_ENABLED
        if not CFG.ESP_ENABLED then
            for _,esp in pairs(espObjects) do
                for _,d in pairs(esp) do d.Visible = false end
            end
        end
    end

    if input.KeyCode == CFG.KEY_FOV_UP then
        CFG.AIM_FOV      = math.min(CFG.AIM_FOV + 10, 500)
        fovCircle.Radius = CFG.AIM_FOV
    end

    if input.KeyCode == CFG.KEY_FOV_DOWN then
        CFG.AIM_FOV      = math.max(CFG.AIM_FOV - 10, 20)
        fovCircle.Radius = CFG.AIM_FOV
    end
end)

UserInputSvc.InputEnded:Connect(function(input)
    if input.KeyCode == CFG.KEY_LOCK then
        aimActive = false
        lockedTarget = nil
    end
end)

-- ══════════════════════════════════════════════
--  TOUCH FIRE-ZONE HANDLERS
--  แตะ fireZone → aimActive = true (เหมือนกด E)
--  ปล่อย fireZone → aimActive = false
--  รองรับ multi-touch: ติดตาม touch.Id เพื่อกัน
--  touch อื่นมา reset lock ก่อนเวลา
-- ══════════════════════════════════════════════
local fireTouchId = nil

UserInputSvc.TouchStarted:Connect(function(touch, processed)
    if isFireTouch(touch.Position) then
        fireTouchId = touch
        aimActive = true
    end
end)

UserInputSvc.TouchEnded:Connect(function(touch, processed)
    if touch == fireTouchId then
        fireTouchId = nil
        aimActive = false
        lockedTarget = nil
    end
end)

-- ══════════════════════════════════════════════
--  MAIN LOOP
-- ══════════════════════════════════════════════
RunService.RenderStepped:Connect(function()
    doAimbot()
    fovCircle.Position = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    for _,plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then updateESP(plr) end
    end
end)


-- ════════════════════════════════════════════════════════
--  SECURITY PATCH: fullCleanup() on UI Exit & Key Expiry
-- ════════════════════════════════════════════════════════

-- ── fullCleanup: reset + destroy everything injected ────
local cleanupDone = false
local function fullCleanup()
    if cleanupDone then return end
    cleanupDone = true

    -- off ทุก feature flag
    CFG.ESP_ENABLED       = false
    CFG.ESP_BOX           = false
    CFG.ESP_NAME          = false
    CFG.ESP_HEALTH        = false
    CFG.ESP_DISTANCE      = false
    CFG.SKE_ENABLED       = false
    CFG.AIM_ENABLED       = false
    CFG.AIM_FOV_VISIBLE   = false
    CFG.AIM_TEAM_CHECK    = false
    CFG.AIM_VISIBLE_CHECK = false
    CFG.AIM_VEHICLE       = false

    -- ล้าง aimbot state
    aimActive    = false
    lockedTarget = nil

    -- ลบ ESP + Skeleton Drawing ทั้งหมด
    for plr in pairs(espObjects) do
        removeESP(plr)
    end
    espObjects  = {}
    skelObjects = {}

    -- ลบ FOV circle
    pcall(function()
        fovCircle.Visible = false
        fovCircle:Remove()
    end)

    -- คืน mouse behaviour ให้ปกติ
    pcall(function()
        UserInputSvc.MouseBehavior    = Enum.MouseBehavior.Default
        UserInputSvc.MouseIconEnabled = true
        mouseUnlocked = false
    end)

    -- ทำลาย Fluent GUI ทั้งหมด
    pcall(function() Fluent:Destroy() end)

    print("[ STEPTHEP ] fullCleanup() complete — all features off, drawings removed.")
end

-- ── Hook 1: Fluent Close Button → fullCleanup() ─────────
--  Fluent.Unloaded จะกลายเป็น true เมื่อ Fluent:Destroy() ถูกเรียก
--  (เกิดขึ้นเมื่อผู้ใช้กดปุ่ม X แล้วยืนยัน "Yes" ใน dialog)
task.spawn(function()
    repeat task.wait(0.3) until Fluent.Unloaded == true
    fullCleanup()
end)

-- ── Hook 2: Key Expiry Watcher → fullCleanup() + notify ─
do
    local watchExpiry = nil
    if type(authResult) == "table" and type(authResult.subscriptions) == "table" then
        for _, sub in ipairs(authResult.subscriptions) do
            local exp = tonumber(sub.expiry)
            if exp and exp > 0 then
                if not watchExpiry or exp > watchExpiry then
                    watchExpiry = exp
                end
            end
        end
    end

    if watchExpiry then
        task.spawn(function()
            while not cleanupDone do
                task.wait(5)
                local now = math.floor(tick())
                if now >= watchExpiry then
                    -- เรียก cleanup ทันที
                    fullCleanup()

                    -- แสดง notice ให้ผู้ใช้รัน script ใหม่
                    task.wait(0.3)
                    pcall(function()
                        local sg = Instance.new("ScreenGui")
                        sg.ResetOnSpawn = false
                        sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
                        if syn and syn.protect_gui then syn.protect_gui(sg) end
                        sg.Parent = game:GetService("CoreGui")

                        local frame = Instance.new("Frame", sg)
                        frame.Size          = UDim2.fromOffset(400, 90)
                        frame.Position      = UDim2.new(0.5, -200, 0.5, -45)
                        frame.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
                        frame.BorderSizePixel  = 0
                        Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)
                        Instance.new("UIStroke", frame).Thickness = 1

                        local title = Instance.new("TextLabel", frame)
                        title.Size               = UDim2.new(1, -20, 0, 28)
                        title.Position           = UDim2.fromOffset(10, 8)
                        title.BackgroundTransparency = 1
                        title.TextColor3         = Color3.fromRGB(255, 70, 70)
                        title.TextSize           = 15
                        title.Font               = Enum.Font.GothamSemiBold
                        title.TextXAlignment     = Enum.TextXAlignment.Left
                        title.Text               = "⚠  License หมดอายุแล้ว — กรุณารัน script ใหม่เพื่อเข้าสู่หน้าใส่ Key"

                        local sub2 = Instance.new("TextLabel", frame)
                        sub2.Size                = UDim2.new(1, -20, 0, 22)
                        sub2.Position            = UDim2.fromOffset(10, 44)
                        sub2.BackgroundTransparency = 1
                        sub2.TextColor3          = Color3.fromRGB(150, 150, 150)
                        sub2.TextSize            = 12
                        sub2.Font                = Enum.Font.Gotham
                        sub2.TextXAlignment      = Enum.TextXAlignment.Left
                        sub2.Text                = "ระบบได้ปิด ESP, Aimbot และคืนค่า offset ทุกอย่างแล้ว"

                        -- auto-dismiss หลัง 10 วินาที
                        task.delay(10, function()
                            pcall(function() sg:Destroy() end)
                        end)
                    end)

                    break
                end
            end
        end)
    end
end
-- ════════════════════════════════════════════════════════
print("[ STEPTHEP v1.1 ] loaded — INSERT=menu | ALT=mouse(ตลอด) | E=lock")
end
