-- ╔══════════════════════════════════════════════════════╗
-- ║          STEPTHEP  v1.0  |  Urban Reload            ║
-- ║   ESP · Skeleton · FOV Aimbot · Vehicle Lock        ║
-- ║   Executor: Xeno / Synapse X / UNC-compliant        ║
-- ╚══════════════════════════════════════════════════════╝

-- ══════════════════════════════════════════════
--  CONFIG
-- ══════════════════════════════════════════════
local CFG = {
    -- ESP
    ESP_ENABLED       = true,
    ESP_BOX           = true,
    ESP_NAME          = true,
    ESP_HEALTH        = true,
    ESP_DISTANCE      = true,
    ESP_COLOR         = Color3.fromRGB(80, 160, 255),
    ESP_THICKNESS     = 1.5,

    -- Skeleton
    SKE_ENABLED       = true,
    SKE_COLOR         = Color3.fromRGB(255, 210, 80),
    SKE_THICKNESS     = 1.2,

    -- Aimbot
    AIM_ENABLED       = true,
    AIM_FOV           = 120,
    AIM_FOV_VISIBLE   = true,
    AIM_FOV_COLOR     = Color3.fromRGB(255, 255, 255),
    AIM_BONE          = "Head",
    AIM_TEAM_CHECK    = true,
    AIM_VISIBLE_CHECK = true,
    AIM_VEHICLE       = true,    -- ล็อคผู้เล่นบนรถได้
    AIM_HEAD_OFFSET   = Vector3.new(0, 0, 0),

    -- Keys
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
local espObjects    = {}   -- [plr] = { box, name, health, dist }
local skelObjects   = {}   -- [plr] = { [bonePair] = Line }
local lockedTarget  = nil
local aimActive     = false
local uiVisible     = true
local mouseUnlocked = false

-- skeleton bone pairs — standard R6 + R15 compat
local BONE_PAIRS = {
    {"Head","UpperTorso"},  {"Head","Torso"},
    {"UpperTorso","LowerTorso"},
    {"Torso","HumanoidRootPart"},{"UpperTorso","HumanoidRootPart"},
    {"UpperTorso","LeftUpperArm"},  {"LeftUpperArm","LeftLowerArm"},  {"LeftLowerArm","LeftHand"},
    {"UpperTorso","RightUpperArm"}, {"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
    {"LowerTorso","LeftUpperLeg"},  {"LeftUpperLeg","LeftLowerLeg"},  {"LeftLowerLeg","LeftFoot"},
    {"LowerTorso","RightUpperLeg"}, {"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},
    -- R6 fallback
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
--  DRAWING HELPERS
-- ══════════════════════════════════════════════
local function newDraw(t, props)
    local d = Drawing.new(t)
    for k,v in pairs(props) do d[k]=v end
    return d
end

local fovCircle = newDraw("Circle",{
    Visible=CFG.AIM_FOV_VISIBLE, Radius=CFG.AIM_FOV,
    Color=CFG.AIM_FOV_COLOR, Thickness=1, Filled=false,
    Position=Vector2.new(Camera.ViewportSize.X/2,Camera.ViewportSize.Y/2),
})

-- ══════════════════════════════════════════════
--  UTILITY
-- ══════════════════════════════════════════════
local function getChar(plr) return plr and plr.Character end

local function getRootAndHuman(plr)
    local c=getChar(plr); if not c then return nil,nil end
    return c:FindFirstChild("HumanoidRootPart"), c:FindFirstChildOfClass("Humanoid")
end

local function isTeammate(plr)
    if not CFG.AIM_TEAM_CHECK then return false end
    return plr.Team and LocalPlayer.Team and plr.Team==LocalPlayer.Team
end

local function worldToScreen(pos)
    local sp,on=Camera:WorldToViewportPoint(pos)
    return Vector2.new(sp.X,sp.Y), on, sp.Z
end

local function getTargetBone(char)
    return char:FindFirstChild(CFG.AIM_BONE) or char:FindFirstChild("HumanoidRootPart")
end

local function distanceTo(plr)
    local root=getRootAndHuman(plr)
    local lroot=LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not root or not lroot then return math.huge end
    return (root.Position-lroot.Position).Magnitude
end

local function isVisible(char,bonePos)
    local origin=Camera.CFrame.Position
    local dir=bonePos-origin
    local ray=Ray.new(origin,dir.Unit*dir.Magnitude)
    local hit=workspace:FindPartOnRayWithIgnoreList(ray,{LocalPlayer.Character})
    if hit==nil then return true end
    return char:IsAncestorOf(hit) or hit:IsDescendantOf(char)
end

-- หา position จริงของ player รวมถึงตอนอยู่บนรถ
local function getPlayerRootPos(plr)
    local char=getChar(plr)
    if not char then return nil end
    local root=char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    -- CFrame.Position ใช้ได้ทั้งตอนเดินและตอนนั่งรถ
    -- (Roblox weld ผู้เล่นเข้า vehicle seat ผ่าน Motor6D)
    return root.Position
end

-- ══════════════════════════════════════════════

-- ══════════════════════════════════════════════
--  UI  — MacLib (STEPTHEP)
-- ══════════════════════════════════════════════

-- โหลด MacLib library
local MacLib = loadstring(game:HttpGet("https://raw.githubusercontent.com/6940213117-create/stepthep/refs/heads/main/ui.txt"))()
-- Assumption: ui.txt ถูก host ที่ URL ที่ Sam กำหนด
-- ถ้าใช้ local: ให้ require / dofile / loadstring แล้วแต่ executor

local Window = MacLib:Window({
    Name       = "STEPTHEP  v1.0",
    Subtitle   = "Urban Reload",
    Size       = UDim2.fromOffset(580, 460),
    KeyCode    = CFG.KEY_UI_TOGGLE,   -- INSERT
    AcrylicBlur = true,
})

local TabGroup = Window:TabGroup()

-- ── Tab: ESP ─────────────────────────────────
local TabESP = TabGroup:Tab({ Name = "ESP", Icon = "rbxassetid://10709791437" })

local SecESP = TabESP:Section({ Name = "ESP Settings", Side = "Left" })

SecESP:Toggle({
    Name    = "ESP Enable",
    Description = "กรอบ / ชื่อ / HP / ระยะ",
    Default = CFG.ESP_ENABLED,
}, function(v) CFG.ESP_ENABLED = v end)

SecESP:Toggle({
    Name    = "Box",
    Default = CFG.ESP_BOX,
}, function(v) CFG.ESP_BOX = v end)

SecESP:Toggle({
    Name    = "Name",
    Default = CFG.ESP_NAME,
}, function(v) CFG.ESP_NAME = v end)

SecESP:Toggle({
    Name    = "Health",
    Default = CFG.ESP_HEALTH,
}, function(v) CFG.ESP_HEALTH = v end)

SecESP:Toggle({
    Name    = "Distance",
    Default = CFG.ESP_DISTANCE,
}, function(v) CFG.ESP_DISTANCE = v end)

SecESP:Toggle({
    Name        = "Skeleton",
    Description = "โครงกระดูกผู้เล่น",
    Default     = CFG.SKE_ENABLED,
}, function(v) CFG.SKE_ENABLED = v end)

-- ── Tab: Aimbot ───────────────────────────────
local TabAim = TabGroup:Tab({ Name = "Aimbot", Icon = "rbxassetid://10709791437" })

local SecAim = TabAim:Section({ Name = "Aimbot Settings", Side = "Left" })

SecAim:Toggle({
    Name        = "Aimbot Enable",
    Description = "hard-lock หัว",
    Default     = CFG.AIM_ENABLED,
}, function(v) CFG.AIM_ENABLED = v end)

SecAim:Toggle({
    Name        = "Show FOV",
    Description = "วงกลม crosshair",
    Default     = CFG.AIM_FOV_VISIBLE,
}, function(v)
    CFG.AIM_FOV_VISIBLE = v
    fovCircle.Visible = v and CFG.AIM_ENABLED
end)

SecAim:Toggle({
    Name        = "Visible Check",
    Description = "ไม่ล็อคคนหลังกำแพง",
    Default     = CFG.AIM_VISIBLE_CHECK,
}, function(v) CFG.AIM_VISIBLE_CHECK = v end)

SecAim:Toggle({
    Name        = "Team Check",
    Description = "ข้ามทีมเดียวกัน",
    Default     = CFG.AIM_TEAM_CHECK,
}, function(v) CFG.AIM_TEAM_CHECK = v end)

SecAim:Toggle({
    Name        = "Vehicle Lock",
    Description = "ล็อคผู้เล่นบนรถได้",
    Default     = CFG.AIM_VEHICLE,
}, function(v) CFG.AIM_VEHICLE = v end)

SecAim:Slider({
    Name    = "FOV",
    Min     = 20,
    Max     = 500,
    Default = CFG.AIM_FOV,
    Suffix  = " px",
}, function(v)
    CFG.AIM_FOV = v
    fovCircle.Radius = v
end)

-- ── Tab: Keys ─────────────────────────────────
local TabKeys = TabGroup:Tab({ Name = "Keys", Icon = "rbxassetid://10709791437" })
local SecKeys = TabKeys:Section({ Name = "Keybinds", Side = "Left" })

SecKeys:Keybind({
    Name    = "Aimbot Lock (hold)",
    Default = CFG.KEY_LOCK,
}, function(v) CFG.KEY_LOCK = v end)

SecKeys:Keybind({
    Name    = "ESP Toggle",
    Default = CFG.KEY_ESP_TOGGLE,
}, function(v) CFG.KEY_ESP_TOGGLE = v end)

SecKeys:Keybind({
    Name    = "FOV Up",
    Default = CFG.KEY_FOV_UP,
}, function(v) CFG.KEY_FOV_UP = v end)

SecKeys:Keybind({
    Name    = "FOV Down",
    Default = CFG.KEY_FOV_DOWN,
}, function(v) CFG.KEY_FOV_DOWN = v end)

SecKeys:Keybind({
    Name    = "Mouse Unlock",
    Default = CFG.KEY_MOUSE_TOGGLE,
}, function(v) CFG.KEY_MOUSE_TOGGLE = v end)

-- ── UI visibility state ───────────────────────
local uiVisible = true

local function setUIVisible(v)
    uiVisible = v
    Window:SetState(v)
    if not v and mouseUnlocked then lockMouse() end
end

-- ══════════════════════════════════════════════
--  ESP + SKELETON BUILDER
-- ══════════════════════════════════════════════
local function buildESP(plr)
    if espObjects[plr] then return end
    espObjects[plr]={
        box    = newDraw("Square",{Visible=false,Color=CFG.ESP_COLOR,  Thickness=CFG.ESP_THICKNESS,Filled=false}),
        name   = newDraw("Text",  {Visible=false,Color=CFG.ESP_COLOR,  Size=13,Center=true,Outline=true}),
        health = newDraw("Text",  {Visible=false,Color=Color3.fromRGB(80,255,120),Size=12,Center=true,Outline=true}),
        dist   = newDraw("Text",  {Visible=false,Color=Color3.fromRGB(180,180,220),Size=11,Center=true,Outline=true}),
    }
    -- skeleton lines
    skelObjects[plr]={}
    for _,pair in ipairs(BONE_PAIRS) do
        local key=pair[1].."__"..pair[2]
        skelObjects[plr][key]=newDraw("Line",{
            Visible=false,Color=CFG.SKE_COLOR,Thickness=CFG.SKE_THICKNESS,
            From=Vector2.new(0,0),To=Vector2.new(0,0),
        })
    end
end

local function removeESP(plr)
    if espObjects[plr] then
        for _,d in pairs(espObjects[plr]) do if d and d.Remove then d:Remove() end end
        espObjects[plr]=nil
    end
    if skelObjects[plr] then
        for _,d in pairs(skelObjects[plr]) do if d and d.Remove then d:Remove() end end
        skelObjects[plr]=nil
    end
end

local function updateESP(plr)
    local esp=espObjects[plr]
    local ske=skelObjects[plr]
    if not esp then return end

    if not CFG.ESP_ENABLED then
        for _,d in pairs(esp) do d.Visible=false end
        if ske then for _,d in pairs(ske) do d.Visible=false end end
        return
    end

    local char=getChar(plr)
    local root,human=getRootAndHuman(plr)
    if not char or not root or not human or human.Health<=0 then
        for _,d in pairs(esp) do d.Visible=false end
        if ske then for _,d in pairs(ske) do d.Visible=false end end
        return
    end

    local hrpPos=root.Position
    local top2d,onTop=worldToScreen(hrpPos+Vector3.new(0,3.2,0))
    local bot2d,onBot=worldToScreen(hrpPos-Vector3.new(0,3.2,0))

    if not onTop and not onBot then
        for _,d in pairs(esp) do d.Visible=false end
        if ske then for _,d in pairs(ske) do d.Visible=false end end
        return
    end

    local height=math.abs(top2d.Y-bot2d.Y)
    local width=height*0.5
    local cx=(top2d.X+bot2d.X)/2

    esp.box.Visible=CFG.ESP_BOX
    if CFG.ESP_BOX then
        esp.box.Position=Vector2.new(cx-width/2,top2d.Y)
        esp.box.Size=Vector2.new(width,height)
    end
    esp.name.Visible=CFG.ESP_NAME
    if CFG.ESP_NAME then
        esp.name.Text=plr.Name
        esp.name.Position=Vector2.new(cx,top2d.Y-16)
    end
    esp.health.Visible=CFG.ESP_HEALTH
    if CFG.ESP_HEALTH then
        esp.health.Text=math.floor(human.Health).." HP"
        esp.health.Position=Vector2.new(cx,bot2d.Y+2)
    end
    esp.dist.Visible=CFG.ESP_DISTANCE
    if CFG.ESP_DISTANCE then
        esp.dist.Text=math.floor(distanceTo(plr)).."m"
        esp.dist.Position=Vector2.new(cx,bot2d.Y+14)
    end

    -- skeleton
    if ske then
        for _,pair in ipairs(BONE_PAIRS) do
            local key=pair[1].."__"..pair[2]
            local line=ske[key]
            if not line then continue end
            if not CFG.SKE_ENABLED then line.Visible=false continue end

            local b0=char:FindFirstChild(pair[1])
            local b1=char:FindFirstChild(pair[2])
            if not b0 or not b1 then line.Visible=false continue end

            local s0,on0=worldToScreen(b0.Position)
            local s1,on1=worldToScreen(b1.Position)
            if not on0 or not on1 then line.Visible=false continue end

            line.From=s0
            line.To=s1
            line.Visible=true
        end
    end
end

-- ══════════════════════════════════════════════
--  AIMBOT  — vehicle-aware
-- ══════════════════════════════════════════════

-- หา position จริงของ player รวมถึงตอนนั่งรถ
-- Roblox weld HRP เข้า VehicleSeat ผ่าน Motor6D
-- root.Position ยังใช้ได้ แต่บางเกม HRP ถูก anchor
-- → อ่านจาก PrimaryPart CFrame แทน หรือ root.CFrame.Position
local function getBoneWorldPos(char,boneName)
    local b=char:FindFirstChild(boneName)
    if b then return b.Position end
    return nil
end

local function getPlayerOnVehicle(plr)
    local char=getChar(plr)
    if not char then return false end
    local hum=char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    -- ถ้า SeatPart มีค่า แสดงว่านั่งอยู่
    return hum.SeatPart~=nil
end

local function getBestTarget()
    local center=Vector2.new(Camera.ViewportSize.X/2,Camera.ViewportSize.Y/2)
    local bestDist=CFG.AIM_FOV
    local bestPlr=nil

    for _,plr in ipairs(Players:GetPlayers()) do
        if plr==LocalPlayer then continue end
        if isTeammate(plr) then continue end

        local char=getChar(plr)
        local root,human=getRootAndHuman(plr)
        if not char or not root or not human or human.Health<=0 then continue end

        -- vehicle check: ถ้า AIM_VEHICLE=false ข้ามคนบนรถ
        if not CFG.AIM_VEHICLE and getPlayerOnVehicle(plr) then continue end

        local bone=getTargetBone(char)
        if not bone then continue end

        -- ใช้ bone.CFrame.Position เพื่อให้ได้ world pos ที่ถูกต้องแม้อยู่บนรถ
        local bonePos=bone.CFrame.Position+CFG.AIM_HEAD_OFFSET
        local screen2d,onScreen=worldToScreen(bonePos)
        if not onScreen then continue end

        if CFG.AIM_VISIBLE_CHECK and not isVisible(char,bonePos) then continue end

        local d=(screen2d-center).Magnitude
        if d<bestDist then bestDist=d bestPlr=plr end
    end
    return bestPlr
end

local function doAimbot()
    if not CFG.AIM_ENABLED or not aimActive or mouseUnlocked then
        lockedTarget=nil return
    end

    if lockedTarget then
        local char=getChar(lockedTarget)
        local _,human=getRootAndHuman(lockedTarget)
        if not human or human.Health<=0 then
            lockedTarget=nil
        elseif CFG.AIM_VISIBLE_CHECK and char then
            local bone=getTargetBone(char)
            if bone and not isVisible(char,bone.CFrame.Position+CFG.AIM_HEAD_OFFSET) then
                lockedTarget=nil
            end
        end
        -- ถ้า vehicle check เปิดอยู่และเป้าลงจากรถ / ขึ้นรถ ก็ยังล็อคได้ตาม CFG
        if lockedTarget and not CFG.AIM_VEHICLE and getPlayerOnVehicle(lockedTarget) then
            lockedTarget=nil
        end
    end

    if not lockedTarget then lockedTarget=getBestTarget() end
    if not lockedTarget then return end

    local char=getChar(lockedTarget)
    local bone=char and getTargetBone(char)
    if not bone then lockedTarget=nil return end

    -- ใช้ bone.CFrame.Position → world pos ถูกต้องทั้งเดินและบนรถ
    local bonePos=bone.CFrame.Position+CFG.AIM_HEAD_OFFSET
    local screen2d,onScreen=worldToScreen(bonePos)
    if not onScreen then lockedTarget=nil return end

    local center=Vector2.new(Camera.ViewportSize.X/2,Camera.ViewportSize.Y/2)
    if (screen2d-center).Magnitude>CFG.AIM_FOV then
        lockedTarget=nil return
    end

    Camera.CFrame=CFrame.lookAt(Camera.CFrame.Position,bonePos)

    local sp,on=worldToScreen(bonePos)
    if on then
        local vp=Camera.ViewportSize
        mousemoverel(sp.X-vp.X/2,sp.Y-vp.Y/2)
    end
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
    if plr~=LocalPlayer then onPlayerAdded(plr) end
end
Players.PlayerAdded:Connect(function(plr)
    if plr~=LocalPlayer then onPlayerAdded(plr) end
end)
Players.PlayerRemoving:Connect(removeESP)

-- ══════════════════════════════════════════════
--  INPUT
-- ══════════════════════════════════════════════
UserInputSvc.InputBegan:Connect(function(input,gpe)
    if input.KeyCode==CFG.KEY_UI_TOGGLE then
        setUIVisible(not uiVisible) return
    end
    if input.KeyCode==CFG.KEY_MOUSE_TOGGLE then
        if uiVisible then
            if mouseUnlocked then lockMouse() else unlockMouse() end
        end
        return
    end
    if gpe then return end
    if input.KeyCode==CFG.KEY_LOCK      then aimActive=true end
    if input.KeyCode==CFG.KEY_ESP_TOGGLE then
        CFG.ESP_ENABLED=not CFG.ESP_ENABLED
        if not CFG.ESP_ENABLED then
            for _,esp in pairs(espObjects) do
                for _,d in pairs(esp) do d.Visible=false end
            end
        end
    end
    if input.KeyCode==CFG.KEY_FOV_UP then
        CFG.AIM_FOV=math.min(CFG.AIM_FOV+10,500)
        fovCircle.Radius=CFG.AIM_FOV
    end
    if input.KeyCode==CFG.KEY_FOV_DOWN then
        CFG.AIM_FOV=math.max(CFG.AIM_FOV-10,20)
        fovCircle.Radius=CFG.AIM_FOV
    end
end)

UserInputSvc.InputEnded:Connect(function(input)
    if input.KeyCode==CFG.KEY_LOCK then
        aimActive=false lockedTarget=nil
    end
end)

-- ══════════════════════════════════════════════
--  MAIN LOOP
-- ══════════════════════════════════════════════
RunService.RenderStepped:Connect(function()
    doAimbot()
    fovCircle.Position=Vector2.new(Camera.ViewportSize.X/2,Camera.ViewportSize.Y/2)
    fovCircle.Visible=CFG.AIM_FOV_VISIBLE and CFG.AIM_ENABLED
    for _,plr in ipairs(Players:GetPlayers()) do
        if plr~=LocalPlayer then updateESP(plr) end
    end
end)

print("[ STEPTHEP v1.0 ] loaded — INSERT=menu | ALT=mouse | E=lock | X=ESP")
