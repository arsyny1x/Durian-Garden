--==================================================
-- Services & Variables
--==================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")
local Backpack = LocalPlayer:WaitForChild("Backpack")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Garage = Remotes:WaitForChild("Garage")
local SellFruitsRemote = Remotes:WaitForChild("SellDurians")
local WaterRemote = Remotes:WaitForChild("Water")
local SeedShopRemote = Remotes:WaitForChild("SeedShop")
local SellDurians = Remotes:WaitForChild("SellDurians")

local DurianWarehouse = workspace:WaitForChild("Map"):WaitForChild("DurianWarehouse")
local SellFruitsNpc = DurianWarehouse:WaitForChild("Flex_Guy"):WaitForChild("RootPart")
local SeedShopNpc = DurianWarehouse:WaitForChild("ShanaKung")

-- Global Configuration & Environment
local _env = getgenv()
_env.Config = _env.Config or {}

if _env.Config.SellFruitAmount == nil then
    _env.Config.SellFruitAmount = 10
end

if _env.Config.SeedsToBuy == nil then
    _env.Config.SeedsToBuy = { "Kradumthong", "Chanee", "Puangmanee" }
end

if _env.Config.FertsToBuy == nil then
    _env.Config.FertsToBuy = { "Basic" }
end

if _env.Config.MinFertKeep == nil then
    _env.Config.MinFertKeep = 1
end

-- สวิตช์เปิด/ปิดโหมดการทำงาน
if _env.AutoSell == nil then _env.AutoSell = true end
if _env.AutoBuySeed == nil then _env.AutoBuySeed = false end
if _env.AutoBuyFert == nil then _env.AutoBuyFert = false end
if _env.AutoWater == nil then _env.AutoWater = true end
if _env.AutoFertilize == nil then _env.AutoFertilize = true end
if _env.AutoHarvest == nil then _env.AutoHarvest = true end
if _env.AutoSteal == nil then _env.AutoSteal = true end
if _env.AutoAntiSteal == nil then _env.AutoAntiSteal = true end
if _env.AutoSaveEnabled == nil then _env.AutoSaveEnabled = true end

-- ตารางแปลงชื่อปุ๋ยระหว่าง UI กับ Server
local FertiMap = {
    ["Basic Fertilizer"] = "Basic",
    ["Super Fertilizer"] = "Super",
    ["Mega Fertilizer"]  = "Mega",
    ["Basic Tree Tonic"] = "TonicBasic",
    ["Super Tree Tonic"] = "TonicSuper",
    ["Mega Tree Tonic"]  = "TonicMega",
    -- รองรับกรณีส่งค่าสั้นมาอยู่แล้ว
    ["Basic"]            = "Basic",
    ["Super"]            = "Super",
    ["Mega"]             = "Mega",
    ["TonicBasic"]       = "TonicBasic",
    ["TonicSuper"]       = "TonicSuper",
    ["TonicMega"]        = "TonicMega",
}

local ReverseFertiMap = {
    ["Basic"]      = "Basic Fertilizer",
    ["Super"]      = "Super Fertilizer",
    ["Mega"]       = "Mega Fertilizer",
    ["TonicBasic"] = "Basic Tree Tonic",
    ["TonicSuper"] = "Super Tree Tonic",
    ["TonicMega"]  = "Mega Tree Tonic",
}

local DefaultFertPrices = {
    ["Basic"]      = 100,
    ["Super"]      = 500,
    ["Mega"]       = 2500,
    ["TonicBasic"] = 150,
    ["TonicSuper"] = 750,
    ["TonicMega"]  = 3000,
}

local function NormalizeFertList(input)
    local result = {}
    local seen = {}

    local function addFert(rawName)
        if type(rawName) ~= "string" then return end
        local mapped = FertiMap[rawName] or rawName
        if DefaultFertPrices[mapped] and not seen[mapped] then
            seen[mapped] = true
            table.insert(result, mapped)
        end
    end

    if type(input) == "table" then
        -- เช็คทั้งแบบ Array (ipairs) และ Dictionary (pairs สำหรับ WindUI Multi-Dropdown)
        for k, v in pairs(input) do
            if type(k) == "number" and type(v) == "string" then
                addFert(v)
            elseif type(k) == "string" and v == true then
                addFert(k)
            elseif type(v) == "string" then
                addFert(v)
            end
        end
    elseif type(input) == "string" then
        addFert(input)
    end

    if #result == 0 then
        table.insert(result, "Basic")
    end
    return result
end

local function GetDropdownDisplayFerts()
    local display = {}
    for _, code in ipairs(NormalizeFertList(_env.Config.FertsToBuy)) do
        table.insert(display, ReverseFertiMap[code] or code)
    end
    return display
end

_env.Config.FertsToBuy = NormalizeFertList(_env.Config.FertsToBuy)

--==================================================
-- Auto-Save / Load Settings (JSON)
--==================================================
local SAVE_FOLDER = "DurianElectDriver"
local SAVE_FILE = SAVE_FOLDER .. "/config.json"

local function _buildSaveData()
    return {
        AutoSell = _env.AutoSell,
        AutoBuySeed = _env.AutoBuySeed,
        AutoBuyFert = _env.AutoBuyFert,
        AutoWater = _env.AutoWater,
        AutoFertilize = _env.AutoFertilize,
        AutoHarvest = _env.AutoHarvest,
        AutoSteal = _env.AutoSteal,
        AutoAntiSteal = _env.AutoAntiSteal,
        AutoSaveEnabled = _env.AutoSaveEnabled,
        Config = {
            SellFruitAmount = _env.Config.SellFruitAmount,
            SeedsToBuy = _env.Config.SeedsToBuy,
            FertsToBuy = NormalizeFertList(_env.Config.FertsToBuy),
            MinFertKeep = _env.Config.MinFertKeep,
        },
    }
end

local function saveSettings(silent)
    if not writefile then
        if not silent then warn("[ElectDriver] writefile unavailable, cannot save.") end
        return false
    end
    local ok = pcall(function()
        if makefolder and isfolder and not isfolder(SAVE_FOLDER) then
            pcall(makefolder, SAVE_FOLDER)
        elseif makefolder and not isfolder then
            pcall(makefolder, SAVE_FOLDER)
        end
        writefile(SAVE_FILE, HttpService:JSONEncode(_buildSaveData()))
    end)
    if ok and not silent then
        print("[ElectDriver] Settings saved -> " .. SAVE_FILE)
    end
    return ok
end

local function loadSettings()
    if not readfile or not isfile then return false end
    local okExist, exists = pcall(isfile, SAVE_FILE)
    if not okExist or not exists then return false end
    local okRead, content = pcall(readfile, SAVE_FILE)
    if not okRead or not content or content == "" then return false end
    local okDec, decoded = pcall(function()
        return HttpService:JSONDecode(content)
    end)
    if not okDec or type(decoded) ~= "table" then return false end

    if type(decoded.AutoSell) == "boolean" then _env.AutoSell = decoded.AutoSell end
    if type(decoded.AutoBuySeed) == "boolean" then _env.AutoBuySeed = decoded.AutoBuySeed end
    if type(decoded.AutoBuyFert) == "boolean" then _env.AutoBuyFert = decoded.AutoBuyFert end
    if type(decoded.AutoWater) == "boolean" then _env.AutoWater = decoded.AutoWater end
    if type(decoded.AutoFertilize) == "boolean" then _env.AutoFertilize = decoded.AutoFertilize end
    if type(decoded.AutoHarvest) == "boolean" then _env.AutoHarvest = decoded.AutoHarvest end
    if type(decoded.AutoSteal) == "boolean" then _env.AutoSteal = decoded.AutoSteal end
    if type(decoded.AutoAntiSteal) == "boolean" then _env.AutoAntiSteal = decoded.AutoAntiSteal end
    if type(decoded.AutoSaveEnabled) == "boolean" then _env.AutoSaveEnabled = decoded.AutoSaveEnabled end

    if type(decoded.Config) == "table" then
        local c = decoded.Config
        if type(c.SellFruitAmount) == "number" then _env.Config.SellFruitAmount = c.SellFruitAmount end
        if type(c.SeedsToBuy) == "table" and #c.SeedsToBuy > 0 then _env.Config.SeedsToBuy = c.SeedsToBuy end
        if type(c.FertsToBuy) == "table" then _env.Config.FertsToBuy = NormalizeFertList(c.FertsToBuy) end
        if type(c.MinFertKeep) == "number" then _env.Config.MinFertKeep = c.MinFertKeep end
    end
    print("[ElectDriver] Loaded saved settings from " .. SAVE_FILE)
    return true
end

loadSettings()

local _savePending = false
local function scheduleSave()
    if not _env.AutoSaveEnabled then return end
    if _savePending then return end
    _savePending = true
    task.delay(0.5, function()
        _savePending = false
        saveSettings(true)
    end)
end

--==================================================
-- Glossy Status Popup UI (Top-Center, English)
--==================================================
local UpdateStatusUI
do
    local guiParent = (gethui and gethui()) or CoreGui
    local oldGui = guiParent:FindFirstChild("GlossyDriverHUD")
    if oldGui then oldGui:Destroy() end

    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "GlossyDriverHUD"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.IgnoreGuiInset = true
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ScreenGui.Parent = guiParent

    local MainFrame = Instance.new("Frame")
    MainFrame.Name = "MainPopup"
    MainFrame.AnchorPoint = Vector2.new(0.5, 0)
    MainFrame.Position = UDim2.new(0.5, 0, 0, -60)
    MainFrame.Size = UDim2.new(0, 290, 0, 44)
    MainFrame.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
    MainFrame.BackgroundTransparency = 0.12
    MainFrame.BorderSizePixel = 0
    MainFrame.ClipsDescendants = true
    MainFrame.Parent = ScreenGui

    local Corner = Instance.new("UICorner")
    Corner.CornerRadius = UDim.new(1, 0)
    Corner.Parent = MainFrame

    local BgGrad = Instance.new("UIGradient")
    BgGrad.Rotation = 90
    BgGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(45, 50, 70)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(22, 25, 36)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 14, 20)),
    })
    BgGrad.Parent = MainFrame

    local GlossHighlight = Instance.new("Frame")
    GlossHighlight.Name = "Gloss"
    GlossHighlight.Size = UDim2.new(1, 0, 0.48, 0)
    GlossHighlight.Position = UDim2.new(0, 0, 0, 0)
    GlossHighlight.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    GlossHighlight.BackgroundTransparency = 0.88
    GlossHighlight.BorderSizePixel = 0
    GlossHighlight.Parent = MainFrame

    local GlossCorner = Instance.new("UICorner")
    GlossCorner.CornerRadius = UDim.new(1, 0)
    GlossCorner.Parent = GlossHighlight

    local GlossGrad = Instance.new("UIGradient")
    GlossGrad.Rotation = 90
    GlossGrad.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.78),
        NumberSequenceKeypoint.new(1, 1),
    })
    GlossGrad.Parent = GlossHighlight

    local Stroke = Instance.new("UIStroke")
    Stroke.Thickness = 2
    Stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    Stroke.Color = Color3.fromRGB(255, 255, 255)
    Stroke.Parent = MainFrame

    local StrokeGrad = Instance.new("UIGradient")
    StrokeGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 235, 255)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(165, 95, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 255, 180)),
    })
    StrokeGrad.Parent = Stroke

    local StatusDot = Instance.new("Frame")
    StatusDot.AnchorPoint = Vector2.new(0, 0.5)
    StatusDot.Position = UDim2.new(0, 18, 0.5, 0)
    StatusDot.Size = UDim2.new(0, 10, 0, 10)
    StatusDot.BackgroundColor3 = Color3.fromRGB(0, 255, 170)
    StatusDot.BorderSizePixel = 0
    StatusDot.Parent = MainFrame

    local DotCorner = Instance.new("UICorner")
    DotCorner.CornerRadius = UDim.new(1, 0)
    DotCorner.Parent = StatusDot

    local DotGlow = Instance.new("UIStroke")
    DotGlow.Thickness = 3
    DotGlow.Transparency = 0.55
    DotGlow.Color = Color3.fromRGB(0, 255, 170)
    DotGlow.Parent = StatusDot

    local TitleLabel = Instance.new("TextLabel")
    TitleLabel.BackgroundTransparency = 1
    TitleLabel.Position = UDim2.new(0, 38, 0, 5)
    TitleLabel.Size = UDim2.new(1, -50, 0, 14)
    TitleLabel.Font = Enum.Font.GothamBold
    TitleLabel.Text = "ELECT DRIVER STATUS"
    TitleLabel.TextColor3 = Color3.fromRGB(160, 175, 205)
    TitleLabel.TextSize = 10
    TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
    TitleLabel.Parent = MainFrame

    local StatusLabel = Instance.new("TextLabel")
    StatusLabel.BackgroundTransparency = 1
    StatusLabel.Position = UDim2.new(0, 38, 0, 19)
    StatusLabel.Size = UDim2.new(1, -50, 0, 20)
    StatusLabel.Font = Enum.Font.GothamBold
    StatusLabel.Text = "Initializing..."
    StatusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    StatusLabel.TextSize = 14
    StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
    StatusLabel.Parent = MainFrame

    TweenService:Create(
        MainFrame,
        TweenInfo.new(0.65, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {Position = UDim2.new(0.5, 0, 0, 16)}
    ):Play()

    task.spawn(function()
        local rot = 0
        while ScreenGui.Parent do
            rot = (rot + 2) % 360
            StrokeGrad.Rotation = rot
            task.wait(0.03)
        end
    end)

    local DriverThemes = {
        anti_steal = {text = "Anti-Steal: Hitting Thief", color = Color3.fromRGB(255, 45, 85)},
        steal      = {text = "Purge: Stealing Fruit",     color = Color3.fromRGB(255, 65, 65)},
        sell       = {text = "Selling Durians",           color = Color3.fromRGB(255, 200, 50)},
        buy_seed   = {text = "Buying Seeds",              color = Color3.fromRGB(190, 110, 255)},
        buy_fert   = {text = "Buying Fertilizer",         color = Color3.fromRGB(255, 110, 195)},
        water      = {text = "Watering Trees",            color = Color3.fromRGB(50, 195, 255)},
        fertilize  = {text = "Applying Fertilizer",       color = Color3.fromRGB(110, 255, 120)},
        harvest    = {text = "Harvesting Ripe Fruit",     color = Color3.fromRGB(255, 135, 55)},
        idle       = {text = "Standby / Waiting",         color = Color3.fromRGB(145, 155, 175)},
    }

    UpdateStatusUI = function(driverKey, detailText)
        local theme = DriverThemes[driverKey or "idle"] or DriverThemes.idle
        local finalText = detailText and (theme.text .. " (" .. detailText .. ")") or theme.text

        StatusLabel.Text = finalText
        TweenService:Create(StatusDot, TweenInfo.new(0.25), {BackgroundColor3 = theme.color}):Play()
        TweenService:Create(DotGlow, TweenInfo.new(0.25), {Color = theme.color}):Play()

        MainFrame.Size = UDim2.new(0, 308, 0, 48)
        TweenService:Create(
            MainFrame,
            TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            {Size = UDim2.new(0, 290, 0, 44)}
        ):Play()
    end
end

--==================================================
-- Initialization & Helpers
--==================================================

local function PressKeyE(holdTime)
    holdTime = holdTime or 0.2
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
    task.wait(holdTime)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
end

local function GetWalkToWorldPosition(hum)
    if not hum then return nil end
    local walkPos = hum.WalkToPoint
    if hum.WalkToPart then
        walkPos = hum.WalkToPart.CFrame:PointToWorldSpace(walkPos)
    end
    return walkPos
end

-- วาร์ปไปเก็บผลไม้ แล้ววาร์ปไปจุดที่ Humanoid.WalkToPoint สั่งเดินทันทีเพื่อข้ามอนิเมชั่น
local function CollectAndSkipWalk(prompt, targetPos)
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not char or not hum or not hrp then return end

    -- วาร์ปไปที่ผลไม้และรีเซ็ตจุด WalkToPoint ปัจจุบัน
    char:PivotTo(CFrame.new(targetPos))
    hum:MoveTo(hrp.Position)
    task.wait(0.5)

    local lastWalkPos = GetWalkToWorldPosition(hum)

    PressKeyE(0.5)

    local walkConn
    walkConn = hum:GetPropertyChangedSignal("WalkToPoint"):Connect(function()
        local newWalkPos = GetWalkToWorldPosition(hum)
        if newWalkPos and newWalkPos.Magnitude > 1 and (not lastWalkPos or (newWalkPos - lastWalkPos).Magnitude > 0.5) then
            lastWalkPos = newWalkPos
            if char and char.Parent then
                char:PivotTo(CFrame.new(newWalkPos + Vector3.new(0, 2, 0)))
            end
        end
    end)
    return walkConn, lastWalkPos
end

local function LoadPlayerBase()
    local Bases = workspace:WaitForChild("Map"):WaitForChild("Bases")
    for _, Base in ipairs(Bases:GetChildren()) do
        if Base:GetAttribute("OwnerName") == LocalPlayer.DisplayName or Base:GetAttribute("OwnerName") == LocalPlayer.Name then
            _env.Config.LocalPlayerBase = Base
            print("Selected Base:", Base.Name)
            break
        end
    end
    _env.LoadedData = (_env.Config.LocalPlayerBase ~= nil)
end

LoadPlayerBase()

local function _wait(seconds)
    seconds = seconds or 0.1
    local start = os.clock()
    repeat task.wait() until os.clock() >= start + seconds
    return true
end

LocalPlayer.CharacterAdded:Connect(function(char)
    Character = char
    Humanoid = char:WaitForChild("Humanoid")
    Backpack = LocalPlayer:WaitForChild("Backpack")
end)

LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

local function Error(msg)
    warn("[Error] " .. tostring(msg))
end

local function GetTool(name)
    local bp = LocalPlayer:FindFirstChild("Backpack")
    local char = LocalPlayer.Character

    if bp and bp:FindFirstChild(name) then
        return bp:FindFirstChild(name)
    end
    if char and char:FindFirstChild(name) then
        return char:FindFirstChild(name)
    end
    return nil
end

local function ForceEquipTool(tool, timeout)
    timeout = timeout or 2.5
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not tool or not char or not hum then return false end

    if tool.Parent == char then
        return true
    end

    local start = os.clock()
    repeat
        if not tool or not tool.Parent then return false end
        hum:EquipTool(tool)
        task.wait(0.15)
        if tool.Parent ~= char then
            pcall(function()
                tool.Parent = char
            end)
        end
    until tool.Parent == char or (os.clock() - start >= timeout)

    task.wait(0.2)
    return tool.Parent == char
end

local function GetAllSlots()
    local slots = {}
    local Base = _env.Config.LocalPlayerBase
    if not Base then return slots end

    local Items = Base:FindFirstChild("Items")
    if not Items then return slots end

    for _, item in ipairs(Items:GetChildren()) do
        if item.Name:match("^FarmPlot") and item:FindFirstChild("Slots") then
            for _, slot in ipairs(item.Slots:GetChildren()) do
                table.insert(slots, slot)
            end
        end
    end
    return slots
end

local function GetPlayerCash()
    if _env.LatestSeedData and type(_env.LatestSeedData.Cash) == "number" then
        return _env.LatestSeedData.Cash
    end
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    if ls then
        local cashObj = ls:FindFirstChild("Cash") or ls:FindFirstChild("Money") or ls:FindFirstChild("Coins") or ls:FindFirstChild("Baht")
        if cashObj and tonumber(cashObj.Value) then
            return tonumber(cashObj.Value)
        end
    end
    local attrCash = LocalPlayer:GetAttribute("Cash") or LocalPlayer:GetAttribute("Money")
    if type(attrCash) == "number" then
        return attrCash
    end
    return math.huge
end

local AntiStealStatus
local function IsAntiStealUrgent()
    return AntiStealStatus ~= nil and AntiStealStatus() == "ready"
end

local function GetBatTool()
    local exact = GetTool("Bat")
    if exact then return exact end

    local char = LocalPlayer.Character
    if char then
        for _, item in ipairs(char:GetChildren()) do
            if item:IsA("Tool") and item.Name:lower():find("bat") then
                return item
            end
        end
    end

    local bp = LocalPlayer:FindFirstChild("Backpack")
    if bp then
        for _, item in ipairs(bp:GetChildren()) do
            if item:IsA("Tool") and item.Name:lower():find("bat") then
                return item
            end
        end
    end
    return nil
end

--==================================================
-- Sub-Functions: Fertilizer Helper
--==================================================
local function GetAllFertilizers()
    local ferts = {}
    local char = LocalPlayer.Character
    if char then
        for _, item in ipairs(char:GetChildren()) do
            if item:IsA("Tool") and item:GetAttribute("FertId") ~= nil then
                table.insert(ferts, item)
            end
        end
    end

    local bp = LocalPlayer:FindFirstChild("Backpack")
    if bp then
        for _, item in ipairs(bp:GetChildren()) do
            if item:IsA("Tool") and item:GetAttribute("FertId") ~= nil then
                table.insert(ferts, item)
            end
        end
    end
    return ferts
end

local function GetFertilizerTool()
    local ferts = GetAllFertilizers()
    return ferts[1]
end

local function GetFertilizerCount()
    return #GetAllFertilizers()
end

--==================================================
-- Sub-Functions: Seed & Fertilizer Shop
--==================================================
_env.LatestSeedData = _env.LatestSeedData or nil
local lastShopRefresh = 0
local lastFertBuyAttempt = 0

if not _env.SeedShopListenerConnected then
    _env.SeedShopListenerConnected = true
    SeedShopRemote.OnClientEvent:Connect(function(...)
        local args = {...}
        local action, data = args[1], args[2]
        if (action == "Open" or action == "Update") and data then
            _env.LatestSeedData = data
        end
    end)
end

SeedShopRemote:FireServer("Refresh")
lastShopRefresh = os.clock()

local function IsWantedSeed(seedName)
    local list = _env.Config.SeedsToBuy or {}
    for k, wanted in pairs(list) do
        local name = (type(k) == "string" and wanted == true) and k or tostring(wanted)
        if name:lower() == tostring(seedName):lower() then
            return true
        end
    end
    return false
end

local function GetBuyableSeedItem()
    local data = _env.LatestSeedData
    if not data or not data.Items then return nil end

    local currentCash = GetPlayerCash()
    for _, item in ipairs(data.Items) do
        if IsWantedSeed(item.Name) and (item.Stock or 0) > 0 and currentCash >= (item.Price or 0) then
            return item
        end
    end
    return nil
end

local function GetFertPrice(fertName)
    local mapped = FertiMap[fertName] or fertName
    local data = _env.LatestSeedData
    if data then
        local fertList = data.Fertilizers or data.Ferts or data.FertItems or data.Items
        if type(fertList) == "table" then
            for _, item in ipairs(fertList) do
                if type(item) == "table" and (item.Name == mapped or item.Id == mapped or item.FertId == mapped) then
                    if type(item.Price) == "number" then
                        return item.Price
                    end
                end
            end
        end
    end
    return DefaultFertPrices[mapped] or 100
end

local function GetAffordableWantedFert()
    local wantedFerts = NormalizeFertList(_env.Config.FertsToBuy)
    local currentCash = GetPlayerCash()
    local data = _env.LatestSeedData

    for _, rawName in ipairs(wantedFerts) do
        local fertName = FertiMap[rawName] or rawName
        local price = GetFertPrice(fertName)
        local inStock = true

        if data then
            local fertList = data.Fertilizers or data.Ferts or data.FertItems
            if type(fertList) == "table" then
                for _, item in ipairs(fertList) do
                    if type(item) == "table" and (item.Name == fertName or item.Id == fertName or item.FertId == fertName) then
                        if item.Stock ~= nil and item.Stock <= 0 then
                            inStock = false
                        end
                    end
                end
            end
        end

        if inStock and currentCash >= price then
            return fertName, price
        end
    end
    return nil, 0
end

local function BuySeedStatus()
    if not _env.AutoBuySeed then return nil end

    if not _env.LatestSeedData then
        if os.clock() - lastShopRefresh > 5 then
            lastShopRefresh = os.clock()
            SeedShopRemote:FireServer("Refresh")
        end
        return "ready"
    end

    if os.clock() - lastShopRefresh > 15 then
        lastShopRefresh = os.clock()
        SeedShopRemote:FireServer("Refresh")
    end

    if GetBuyableSeedItem() ~= nil then
        return "ready"
    end
    return nil
end

local function BuySeedTick()
    if not SeedShopNpc or IsAntiStealUrgent() then return end

    Character:PivotTo(SeedShopNpc:GetPivot() * CFrame.new(0, 2, 4))
    task.wait(0.4)
    if IsAntiStealUrgent() then return end

    if not _env.LatestSeedData then
        SeedShopRemote:FireServer("Refresh")
        PressKeyE(0.25)
        local waitStart = os.clock()
        repeat task.wait(0.1) until _env.LatestSeedData or IsAntiStealUrgent() or (os.clock() - waitStart > 3)
    end
    if IsAntiStealUrgent() then return end

    local targetItem = GetBuyableSeedItem()
    if not targetItem then return end

    UpdateStatusUI("buy_seed", targetItem.Name .. " x" .. tostring(targetItem.Stock))

    for _ = 1, (targetItem.Stock or 1) do
        if not _env.AutoBuySeed or IsAntiStealUrgent() then break end
        if GetPlayerCash() < (targetItem.Price or 0) then break end

        SeedShopRemote:FireServer("Buy", targetItem.Name)
        task.wait(0.25)

        local updated = GetBuyableSeedItem()
        if not updated or updated.Name ~= targetItem.Name then
            break
        end
    end

    SeedShopRemote:FireServer("Refresh")
end

local function BuyFertStatus()
    if not _env.AutoBuyFert then return nil end
    local wantedFerts = NormalizeFertList(_env.Config.FertsToBuy)
    if #wantedFerts == 0 then return nil end

    if not _env.LatestSeedData and (os.clock() - lastShopRefresh > 5) then
        lastShopRefresh = os.clock()
        SeedShopRemote:FireServer("Refresh")
    end

    local minKeep = _env.Config.MinFertKeep or 1
    if GetFertilizerCount() < minKeep and (os.clock() - lastFertBuyAttempt > 6) then
        local affordableFert = GetAffordableWantedFert()
        if affordableFert ~= nil then
            return "ready"
        end
    end
    return nil
end

local function BuyFertTick()
    if not SeedShopNpc or IsAntiStealUrgent() then return end
    lastFertBuyAttempt = os.clock()

    SeedShopRemote:FireServer("Refresh")
    task.wait(0.2)
    if IsAntiStealUrgent() then return end

    local testFert = GetAffordableWantedFert()
    if not testFert then return end

    Character:PivotTo(SeedShopNpc:GetPivot() * CFrame.new(0, 2, 4))
    task.wait(0.4)
    if IsAntiStealUrgent() then return end

    local wantedFerts = NormalizeFertList(_env.Config.FertsToBuy)
    local minKeep = _env.Config.MinFertKeep or 1

    for _, rawName in ipairs(wantedFerts) do
        if not _env.AutoBuyFert or IsAntiStealUrgent() then break end
        if GetFertilizerCount() >= minKeep then break end

        local fertName = FertiMap[rawName] or rawName
        local price = GetFertPrice(fertName)

        if GetPlayerCash() >= price then
            UpdateStatusUI("buy_fert", fertName .. " ($" .. tostring(price) .. ")")

            local attempts = 0
            while GetFertilizerCount() < minKeep and attempts < 5 do
                if GetPlayerCash() < price or IsAntiStealUrgent() then
                    break
                end
                attempts = attempts + 1
                SeedShopRemote:FireServer("BuyFert", fertName)
                task.wait(0.35)
                SeedShopRemote:FireServer("Refresh")
            end
        end
    end
end

--==================================================
-- Sub-Functions: Sell Fruits
--==================================================
local function GetAllFruits()
    local fruits = {}
    local char = LocalPlayer.Character
    if char then
        for _, item in ipairs(char:GetChildren()) do
            if item:IsA("Tool") and item:GetAttribute("FruitId") then
                table.insert(fruits, item)
            end
        end
    end

    local bp = LocalPlayer:FindFirstChild("Backpack")
    if bp then
        for _, item in ipairs(bp:GetChildren()) do
            if item:IsA("Tool") and item:GetAttribute("FruitId") then
                table.insert(fruits, item)
            end
        end
    end
    return fruits
end

local function GetFruitCount()
    return #GetAllFruits()
end

local function SellStatus()
    local limit = _env.Config.SellFruitAmount or 10
    if _env.AutoSell and GetFruitCount() >= limit then
        return "ready"
    end
    return nil
end

local function SellFruitsTick()
    Character:PivotTo(SellFruitsNpc:GetPivot() * CFrame.new(0, 2, 5))
    task.wait(1)
    SellDurians:FireServer("All")
end

--==================================================
-- Sub-Functions: Watering
--==================================================
local function IsSlotThirsty(slot)
    local plantSpot = slot:FindFirstChild("PlantSpot")
    if plantSpot and plantSpot:FindFirstChild("ThirstSign") then
        local sign = plantSpot.ThirstSign
        if sign:IsA("BillboardGui") or sign:IsA("SurfaceGui") then
            return sign.Enabled
        elseif sign:IsA("GuiObject") then
            return sign.Visible
        end
        return true
    end
    return false
end

local function GetThirstySlots()
    local thirstyList = {}
    for _, slot in ipairs(GetAllSlots()) do
        if IsSlotThirsty(slot) then
            table.insert(thirstyList, slot)
        end
    end
    return thirstyList
end

local function GetSlotTargetPosition(slot)
    local plantSpot = slot:FindFirstChild("PlantSpot")

    if plantSpot then
        if plantSpot:IsA("Model") then
            return plantSpot:GetPivot().Position
        elseif plantSpot:IsA("BasePart") then
            return plantSpot.Position
        end

        local part = plantSpot:FindFirstChildWhichIsA("BasePart", true)
        if part then
            return part.Position
        end
    end

    return nil
end

local function EnsureWateringCanFilled(itemsFolder)
    if IsAntiStealUrgent() then return false end
    local Well = itemsFolder:FindFirstChild("Well")
    if not Well or not Well:FindFirstChild("PromptPart") then return false end

    local Prompt = Well.PromptPart:FindFirstChild("FillPrompt")
    local WateringCan = GetTool("Watering Can")

    if not WateringCan then
        warn("Watering Can not found")
        return false
    end

    ForceEquipTool(WateringCan, 2)

    local currentUses = WateringCan:GetAttribute("Uses") or 0
    if currentUses <= 0 then
        Character:PivotTo(Well:GetPivot() * CFrame.new(0, 5, 5))
        task.wait(0.25)
        repeat
            if IsAntiStealUrgent() then return false end
            if Prompt then
                fireproximityprompt(Prompt)
            end
            task.wait(0.5)
            currentUses = WateringCan:GetAttribute("Uses") or 0
        until currentUses >= 3 or IsAntiStealUrgent()
    end
    return not IsAntiStealUrgent()
end

local function WaterSingleSlot(slot, itemsFolder)
    if IsAntiStealUrgent() then return end
    if not IsSlotThirsty(slot) then return end
    if not EnsureWateringCanFilled(itemsFolder) then return end
    if IsAntiStealUrgent() then return end

    local pos = GetSlotTargetPosition(slot)
    if pos then
        Character:PivotTo(CFrame.new(pos) + Vector3.new(0, 3, 3))
        task.wait(0.3)
        if IsAntiStealUrgent() then return end

        pcall(function()
            WaterRemote:FireServer("Water", Vector3.new(pos.X, pos.Y, pos.Z))
        end)
        task.wait(0.5)
    end
end

local function WaterStatus()
    if not _env.AutoWater then return nil end
    if not GetTool("Watering Can") then return nil end
    if #GetThirstySlots() > 0 then
        return "ready"
    end
    return nil
end

local function WateringTick()
    if IsAntiStealUrgent() then return end
    local Base = _env.Config.LocalPlayerBase
    local Items = Base and Base:WaitForChild("Items", 5)
    if not Items then return end

    local thirstySlots = GetThirstySlots()
    for _, slot in ipairs(thirstySlots) do
        if IsAntiStealUrgent() then break end
        WaterSingleSlot(slot, Items)
    end
end

--==================================================
-- Sub-Functions: Fertilize
--==================================================
local function DoesSlotNeedFertilizer(slot)
    local plantSpot = slot:FindFirstChild("PlantSpot")
    if not plantSpot then return false end

    local tonicSign = plantSpot:FindFirstChild("TonicSign")
    if not tonicSign then return false end

    if (tonicSign:IsA("BillboardGui") or tonicSign:IsA("SurfaceGui")) and not tonicSign.Enabled then
        return false
    end

    local textLabel = tonicSign:FindFirstChild("TextLabel") or tonicSign:FindFirstChildWhichIsA("TextLabel", true)
    if textLabel then
        if not textLabel.Visible then return false end
        local txt = (textLabel.ContentText ~= "" and textLabel.ContentText or textLabel.Text):upper()
        if txt:find("NEEDS FERTILIZER") then
            return true
        end
    end

    return false
end

local function GetFertilizerSlots()
    local list = {}
    for _, slot in ipairs(GetAllSlots()) do
        if DoesSlotNeedFertilizer(slot) then
            table.insert(list, slot)
        end
    end
    return list
end

local function FertilizeSingleSlot(slot)
    if IsAntiStealUrgent() then return end
    if not DoesSlotNeedFertilizer(slot) then return end

    local fertTool = GetFertilizerTool()
    if not fertTool then return end

    local pos = GetSlotTargetPosition(slot)
    if not pos then return end

    ForceEquipTool(fertTool, 2)
    if IsAntiStealUrgent() then return end

    local standPos = pos + Vector3.new(0, 2, 3)
    Character:PivotTo(CFrame.lookAt(standPos, pos))
    task.wait(0.35)
    if IsAntiStealUrgent() then return end

    local promptFound = false
    for _, desc in ipairs(slot:GetDescendants()) do
        if desc:IsA("ProximityPrompt") and desc.Enabled and desc.Name ~= "Harvest" then
            promptFound = true
            fireproximityprompt(desc)
            PressKeyE(math.max(0.2, (desc.HoldDuration or 0) + 0.15))
            break
        end
    end

    if fertTool and fertTool.Parent == LocalPlayer.Character then
        pcall(function() fertTool:Activate() end)
    end

    pcall(function()
        local fertRemote = Remotes:FindFirstChild("Fertilize") or Remotes:FindFirstChild("Tonic")
        if fertRemote then
            fertRemote:FireServer(Vector3.new(pos.X, pos.Y, pos.Z))
        else
            WaterRemote:FireServer("Fertilize", Vector3.new(pos.X, pos.Y, pos.Z))
        end
    end)

    if not promptFound then
        PressKeyE(0.25)
    end

    task.wait(0.5)
end

local function FertilizeStatus()
    if not _env.AutoFertilize then return nil end
    if #GetFertilizerSlots() > 0 then
        if GetFertilizerTool() ~= nil then
            return "ready"
        elseif _env.AutoBuyFert and GetAffordableWantedFert() ~= nil then
            return "need_buy"
        end
    end
    return nil
end

local function FertilizeTick()
    if IsAntiStealUrgent() then return end
    local slots = GetFertilizerSlots()
    for _, slot in ipairs(slots) do
        if IsAntiStealUrgent() or not GetFertilizerTool() then break end
        FertilizeSingleSlot(slot)
    end
end

--==================================================
-- Sub-Functions: Harvest & Purge Steal
--==================================================
-- ฟังก์ชันหา Grow.Pct จากโครงสร้างลูกทุเรียน (รองรับทั้ง Durian_Fruit_X2_Node.Durian_Fruit_X2.Grow.Pct)
local function FindGrowPctObject(prompt)
    local curr = prompt.Parent
    -- 1. เช็คใน Parent โดยตรงก่อน
    if curr then
        local grow = curr:FindFirstChild("Grow")
        if grow and grow:FindFirstChild("Pct") then
            return grow.Pct
        end
    end

    -- 2. ไต่ขึ้นไปหา Root ของผลไม้ลูกนั้น (เช่น Fruit_5) แล้วค้นหา Grow.Pct ใน Descendants
    local fruitRoot = prompt
    while fruitRoot.Parent and fruitRoot.Parent.Name ~= "Fruits" do
        fruitRoot = fruitRoot.Parent
    end

    if fruitRoot then
        local grow = fruitRoot:FindFirstChild("Grow", true)
        if grow and grow:FindFirstChild("Pct") then
            return grow.Pct
        end
        local pct = fruitRoot:FindFirstChild("Pct", true)
        if pct then
            return pct
        end
    end

    return nil
end

local function IsFruitRipe(prompt)
    if not prompt or not prompt.Parent then return false end

    local pct = FindGrowPctObject(prompt)
    if not pct then
        return false
    end

    local text = ""
    if pct:IsA("TextLabel") or pct:IsA("TextButton") or pct:IsA("TextBox") then
        text = (pct.Text ~= "" and pct.Text) or pct.ContentText or ""
    elseif pct:IsA("StringValue") then
        text = pct.Value
    end

    local lowerText = text:lower()

    -- ถ้ามีคำว่า growing หรือมีเครื่องหมาย % (เช่น Growing 11%) แปลว่ายังไม่สุก
    if text == "" or lowerText:find("growing") or text:find("%%") then
        return false
    end

    -- ถ้ามีคำว่า ripe! หรือมีน้ำหนัก [..kg] แปลว่าสุกพร้อมเก็บแล้ว
    if lowerText:find("ripe") or lowerText:find("kg") then
        return true
    end

    return true
end

--==================================================
-- Market Price Reader & Fruit Value Calculator
--==================================================
local cachedMarketPanel = nil
local function GetMarketPanel()
    if cachedMarketPanel and cachedMarketPanel.Parent then
        return cachedMarketPanel
    end
    local pGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not pGui then return nil end

    for _, obj in ipairs(pGui:GetDescendants()) do
        if obj.Name == "MarketPanel" and obj:IsA("Frame") then
            cachedMarketPanel = obj
            return obj
        end
    end
    return nil
end

local DefaultFruitPrices = {
    kradumthong = 16,
    chanee      = 52,
    puangmanee  = 144,
    kanyao      = 441,
    nokyip      = 1236,
    monthong    = 3640,
}

local function ParseNumberFromText(str)
    if type(str) ~= "string" then return nil end
    local cleaned = str:gsub(",", "")
    local num = cleaned:match("([%d]+%.?[%d]*)")
    return num and tonumber(num) or nil
end

local function GetMarketPriceTable()
    local prices = {}
    for k, v in pairs(DefaultFruitPrices) do
        prices[k] = v
    end

    local panel = GetMarketPanel()
    local rows = panel and panel:FindFirstChild("Rows")
    if rows then
        for _, c in ipairs(rows:GetChildren()) do
            if c:IsA("Frame") and c.Name ~= "Template" then
                local nLbl = c:FindFirstChild("Name")
                local pLbl = c:FindFirstChild("Price")
                if pLbl then
                    local rawPrice = (pLbl:IsA("TextLabel") or pLbl:IsA("TextButton") or pLbl:IsA("TextBox"))
                        and ((pLbl.Text ~= "" and pLbl.Text) or pLbl.ContentText or "")
                        or ""
                    local priceVal = ParseNumberFromText(rawPrice)
                    if priceVal and priceVal > 0 then
                        prices[c.Name:lower()] = priceVal
                        if nLbl then
                            local rawName = (nLbl:IsA("TextLabel") or nLbl:IsA("TextButton") or nLbl:IsA("TextBox"))
                                and ((nLbl.Text ~= "" and nLbl.Text) or nLbl.ContentText or "")
                                or ""
                            local cleanName = rawName:match("^%s*(.-)%s*$")
                            if cleanName and cleanName ~= "" then
                                prices[cleanName:lower()] = priceVal
                            end
                        end
                    end
                end
            end
        end
    end

    return prices
end

local function GetFruitPartVolume(prompt)
    local parent = prompt.Parent
    if not parent then return 0 end

    if parent:IsA("BasePart") then
        return parent.Size.X * parent.Size.Y * parent.Size.Z
    elseif parent:IsA("Model") then
        local _, size = parent:GetBoundingBox()
        return size.X * size.Y * size.Z
    end

    local model = prompt:FindFirstAncestorOfClass("Model")
    if model then
        local _, size = model:GetBoundingBox()
        return size.X * size.Y * size.Z
    end

    local part = prompt:FindFirstAncestorWhichIsA("BasePart")
    if part then
        return part.Size.X * part.Size.Y * part.Size.Z
    end

    return 0
end

-- อ่านชื่อพันธุ์และน้ำหนัก [..kg] จาก Grow.Pct เช่น "Chanee [4.08kg]\nRipe!" แล้วคำนวณราคารวมจาก MarketPanel
local function GetFruitEstimatedValue(prompt, marketPrices)
    marketPrices = marketPrices or GetMarketPriceTable()

    local pct = FindGrowPctObject(prompt)
    local text = ""
    if pct then
        if pct:IsA("TextLabel") or pct:IsA("TextButton") or pct:IsA("TextBox") then
            text = (pct.Text ~= "" and pct.Text) or pct.ContentText or ""
        elseif pct:IsA("StringValue") then
            text = pct.Value
        end
    end

    -- ดึงน้ำหนักจาก [4.08kg]
    local weightStr = text:match("%[([%d%.]+)%s*[kK][gG]%]") or text:match("([%d%.]+)%s*[kK][gG]")
    local weightKg = tonumber(weightStr) or 0

    -- ดึงชื่อพันธุ์จากข้อความหน้า [..kg] (เช่น "Chanee") หรือจากชื่อ Model "Durian_Fruit_Chanee"
    local fruitName = text:match("^%s*([%a]+)")
    if not fruitName or fruitName:lower() == "ripe" or fruitName:lower() == "growing" then
        local curr = prompt.Parent
        while curr and curr.Name ~= "Fruits" and curr ~= workspace do
            local matched = curr.Name:match("^Durian_Fruit_([%a]+)")
            if matched then
                fruitName = matched
                break
            end
            curr = curr.Parent
        end
    end
    fruitName = fruitName or "Durian"

    local unitPrice = marketPrices[fruitName:lower()] or 1
    local weightOrFallback = (weightKg > 0) and weightKg or GetFruitPartVolume(prompt)
    local estimatedPrice = weightOrFallback * unitPrice

    return estimatedPrice, fruitName, weightKg, unitPrice
end

local function FindHarvestPrompt()
    local marketPrices = GetMarketPriceTable()
    local bestPrompt = nil
    local maxPrice = -1
    local bestName, bestKg = nil, 0

    for _, slot in ipairs(GetAllSlots()) do
        local fruitsFolder = slot:FindFirstChild("Fruits")
        if fruitsFolder then
            for _, desc in ipairs(fruitsFolder:GetDescendants()) do
                if desc:IsA("ProximityPrompt") and desc.Enabled and IsFruitRipe(desc) then
                    local estPrice, fName, fKg = GetFruitEstimatedValue(desc, marketPrices)
                    if estPrice > maxPrice then
                        maxPrice = estPrice
                        bestPrompt = desc
                        bestName = fName
                        bestKg = fKg
                    end
                end
            end
        end
    end
    return bestPrompt, maxPrice, bestName, bestKg
end

local function GetPromptPosition(prompt)
    local parent = prompt.Parent
    if not parent then return nil end

    if parent:IsA("BasePart") then
        return parent.Position
    elseif parent:IsA("Model") then
        return parent:GetPivot().Position
    elseif parent:IsA("Attachment") then
        return parent.WorldPosition
    end

    local part = parent:FindFirstChildWhichIsA("BasePart", true) or prompt:FindFirstAncestorWhichIsA("BasePart")
    if part then
        return part.Position
    end
    return nil
end

local function FindBiggestStealableFruitPrompt()
    local Bases = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Bases")
    if not Bases then return nil end

    local marketPrices = GetMarketPriceTable()
    local myBase = _env.Config.LocalPlayerBase
    local bestPrompt = nil
    local maxPrice = -1
    local bestName, bestKg = nil, 0

    for _, base in ipairs(Bases:GetChildren()) do
        local owner = base:GetAttribute("OwnerName")
        local isOtherPlayerBase = (base ~= myBase)
            and (owner ~= LocalPlayer.DisplayName)
            and (owner ~= LocalPlayer.Name)

        if isOtherPlayerBase then
            local items = base:FindFirstChild("Items")
            if items then
                for _, item in ipairs(items:GetChildren()) do
                    if item.Name:match("^FarmPlot") and item:FindFirstChild("Slots") then
                        for _, slot in ipairs(item.Slots:GetChildren()) do
                            local fruitsFolder = slot:FindFirstChild("Fruits")
                            if fruitsFolder then
                                for _, desc in ipairs(fruitsFolder:GetDescendants()) do
                                    if desc:IsA("ProximityPrompt") and desc.Enabled and IsFruitRipe(desc) then
                                        local estPrice, fName, fKg = GetFruitEstimatedValue(desc, marketPrices)
                                        if estPrice > maxPrice then
                                            maxPrice = estPrice
                                            bestPrompt = desc
                                            bestName = fName
                                            bestKg = fKg
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return bestPrompt, maxPrice, bestName, bestKg
end

local function IsPurgeOrStealableActive()
    -- เช็คจาก Attribute "Phase" ของ workspace (เช่น workspace:GetAttribute("Phase") == "Night")
    local phaseAttr = workspace:GetAttribute("Phase")
    if type(phaseAttr) == "string" and phaseAttr:lower() == "night" then
        return true
    end

    -- รองรับกรณี workspace.Phase เป็น Object (เช่น StringValue)
    local phaseObj = workspace:FindFirstChild("Phase")
    if phaseObj and phaseObj:IsA("ValueBase") and tostring(phaseObj.Value):lower() == "night" then
        return true
    end

    return false
end

local function GetHomeHutFloorCFrame()
    local myBase = _env.Config.LocalPlayerBase
    if not myBase then return nil end

    local hut = myBase:FindFirstChild("Hut")
    local node0 = hut and hut:FindFirstChild("Node0")
    local woodenHut = node0 and node0:FindFirstChild("Wooden_Hut")
    local floorNode = woodenHut and woodenHut:FindFirstChild("Floor_Node")
    local floorPart = floorNode and floorNode:FindFirstChild("Floor")

    if not floorPart and hut then
        floorPart = hut:FindFirstChild("Floor", true)
    end

    if floorPart then
        if floorPart:IsA("BasePart") then
            return floorPart.CFrame * CFrame.new(0, 3, 0)
        elseif floorPart:IsA("Model") then
            return floorPart:GetPivot() * CFrame.new(0, 3, 0)
        end
    end

    return myBase:GetPivot() * CFrame.new(0, 3, 0)
end

local function StealStatus()
    if not _env.AutoSteal then return nil end
    if not IsPurgeOrStealableActive() then return nil end
    if FindBiggestStealableFruitPrompt() ~= nil then
        return "ready"
    end
    return nil
end

local function StealTick()
    if IsAntiStealUrgent() or not IsPurgeOrStealableActive() then return end
    local prompt, estPrice, fName, fKg = FindBiggestStealableFruitPrompt()
    if not prompt then return end

    local targetPos = GetPromptPosition(prompt)
    if not targetPos then return end

    UpdateStatusUI("steal", string.format("%s %.2fkg (~$%.0f)", fName or "Fruit", fKg or 0, estPrice or 0))

    local walkConn, lastWalkPos = CollectAndSkipWalk(prompt, targetPos)

    local startWait = os.clock()
    local carriedFruit

    repeat
        if IsAntiStealUrgent() then break end
        task.wait(0.05)
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if char and hum then
            local walkPos = GetWalkToWorldPosition(hum)
            if walkPos and walkPos.Magnitude > 1 and (not lastWalkPos or (walkPos - lastWalkPos).Magnitude > 0.5) then
                lastWalkPos = walkPos
                char:PivotTo(CFrame.new(walkPos + Vector3.new(0, 2, 0)))
            end
        end

        local playerModel = workspace:FindFirstChild(LocalPlayer.Name)
        carriedFruit = (playerModel and playerModel:FindFirstChild("CarriedDurian"))
            or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("CarriedDurian"))
    until carriedFruit or IsAntiStealUrgent() or os.clock() - startWait > 2.5

    if walkConn then
        walkConn:Disconnect()
    end

    if IsAntiStealUrgent() then return end

    if carriedFruit then
        local homeFloorCF = GetHomeHutFloorCFrame()

        if homeFloorCF then
            UpdateStatusUI("steal", "Returning to Base Floor")
            local returnStart = os.clock()
            repeat
                if IsAntiStealUrgent() then break end
                task.wait()
                if LocalPlayer.Character then
                    LocalPlayer.Character:PivotTo(homeFloorCF)
                end
                local pm = workspace:FindFirstChild(LocalPlayer.Name)
                local stillCarrying = (pm and pm:FindFirstChild("CarriedDurian"))
                    or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("CarriedDurian"))
            until not stillCarrying or IsAntiStealUrgent() or (os.clock() - returnStart > 8)
        end
    end
end

local function HarvestStatus()
    if not _env.AutoHarvest then return nil end
    if FindHarvestPrompt() ~= nil then
        return "ready"
    end
    return nil
end

local function HarvestTick()
    if IsAntiStealUrgent() then return end
    local prompt, estPrice, fName, fKg = FindHarvestPrompt()
    if not prompt then return end

    local targetPos = GetPromptPosition(prompt)
    if not targetPos then return end

    if not IsFruitRipe(prompt) then
        return
    end

    UpdateStatusUI("harvest", string.format("%s %.2fkg (~$%.0f)", fName or "Fruit", fKg or 0, estPrice or 0))

    local beforeCount = GetFruitCount()
    local walkConn, lastWalkPos = CollectAndSkipWalk(prompt, targetPos)

    local startWait = os.clock()
    repeat
        if IsAntiStealUrgent() then break end
        task.wait(0.05)
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if char and hum then
            local walkPos = GetWalkToWorldPosition(hum)
            if walkPos and walkPos.Magnitude > 1 and (not lastWalkPos or (walkPos - lastWalkPos).Magnitude > 0.5) then
                lastWalkPos = walkPos
                char:PivotTo(CFrame.new(walkPos + Vector3.new(0, 2, 0)))
            end
        end
    until GetFruitCount() > beforeCount or IsAntiStealUrgent() or not prompt.Parent or not prompt.Enabled or (os.clock() - startWait > 2.5)

    if walkConn then
        walkConn:Disconnect()
    end
end

--==================================================
-- Sub-Functions: Anti-Steal (Hit Carrier with Bat)
--==================================================
local function IsPositionInMyBase(pos)
    local myBase = _env.Config.LocalPlayerBase
    if not myBase or not pos then return false end

    local pad = 35 -- ระยะเผื่อรอบสวนของเรา (studs)

    -- 1. คำนวณขอบเขตจริงจาก BasePart ทั้งหมดในสวนของเรา (แม่นยำที่สุด)
    local minX, maxX = math.huge, -math.huge
    local minZ, maxZ = math.huge, -math.huge
    local foundPart = false

    for _, desc in ipairs(myBase:GetDescendants()) do
        if desc:IsA("BasePart") then
            foundPart = true
            local p = desc.Position
            local s = desc.Size * 0.5
            if p.X - s.X < minX then minX = p.X - s.X end
            if p.X + s.X > maxX then maxX = p.X + s.X end
            if p.Z - s.Z < minZ then minZ = p.Z - s.Z end
            if p.Z + s.Z > maxZ then maxZ = p.Z + s.Z end
        end
    end

    if foundPart then
        if (pos.X >= minX - pad and pos.X <= maxX + pad)
            and (pos.Z >= minZ - pad and pos.Z <= maxZ + pad) then
            return true
        end
    end

    -- 2. เช็คผ่าน GetBoundingBox เผื่อกรณีพิเศษ
    if myBase:IsA("Model") then
        local ok, boxCF, boxSize = pcall(function()
            return myBase:GetBoundingBox()
        end)
        if ok and boxCF and boxSize and boxSize.Magnitude > 0 then
            local rel = boxCF:PointToObjectSpace(pos)
            if math.abs(rel.X) <= (boxSize.X * 0.5 + pad)
                and math.abs(rel.Z) <= (boxSize.Z * 0.5 + pad)
                and math.abs(rel.Y) <= (boxSize.Y * 0.5 + 60) then
                return true
            end
        end
    end

    -- 3. เช็คระยะห่างจากแปลงปลูก (Slots) ในสวนของเรา
    for _, slot in ipairs(GetAllSlots()) do
        local slotPos = GetSlotTargetPosition(slot)
        if slotPos and (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(slotPos.X, 0, slotPos.Z)).Magnitude <= 55 then
            return true
        end
    end

    return false
end

local lockedThiefPlayer = nil
local recentBaseVisitors = {}

_env.FarmLoopRunId = (_env.FarmLoopRunId or 0) + 1
local currentRunId = _env.FarmLoopRunId

-- Background Watcher คอยจับตาดูคนเข้าสวนเราทุกๆ 0.05 วินาที แม้บอทกำลังทำอย่างอื่นอยู่
task.spawn(function()
    while _env.FarmLoopRunId == currentRunId and task.wait(0.05) do
        if _env.AutoAntiSteal and _env.Config.LocalPlayerBase then
            local now = os.clock()
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer then
                    local playerModel = workspace:FindFirstChild(plr.Name) or plr.Character
                    local hrp = playerModel and playerModel:FindFirstChild("HumanoidRootPart")
                    local hum = playerModel and playerModel:FindFirstChildOfClass("Humanoid")
                    if hrp and (not hum or hum.Health > 0) then
                        local inBase = IsPositionInMyBase(hrp.Position)
                        if inBase then
                            recentBaseVisitors[plr] = now
                        end
                        -- ถ้าถือ CarriedDurian และอยู่ในสวนเรา (หรือเพิ่งอยู่ในสวนเราเมื่อไม่เกิน 8 วินาทีที่แล้ว) ล็อกเป้าทันที!
                        if playerModel:FindFirstChild("CarriedDurian") then
                            if inBase or (recentBaseVisitors[plr] and (now - recentBaseVisitors[plr] <= 8)) then
                                lockedThiefPlayer = plr
                            end
                        end
                    end
                end
            end
        end
    end
end)

local function FindPlayerCarryingDurian()
    -- ถ้าล็อกเป้าหมายไว้แล้ว และยังถือ CarriedDurian อยู่ ให้ตามตีต่อเรื่อยๆ แม้จะวิ่งพ้นระยะสวนไปแล้ว
    if lockedThiefPlayer and lockedThiefPlayer.Parent == Players then
        local lockedModel = workspace:FindFirstChild(lockedThiefPlayer.Name) or lockedThiefPlayer.Character
        if lockedModel and lockedModel:FindFirstChild("CarriedDurian") then
            local hrp = lockedModel:FindFirstChild("HumanoidRootPart")
            local hum = lockedModel:FindFirstChildOfClass("Humanoid")
            if hrp and (not hum or hum.Health > 0) then
                return lockedThiefPlayer, lockedModel, hrp
            end
        end
    end
    lockedThiefPlayer = nil

    -- ค้นหาผู้เล่นที่เริ่มขโมยในระยะสวนของเรา (หรือเพิ่งอยู่ในสวนเราไม่เกิน 8 วินาที)
    local now = os.clock()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local playerModel = workspace:FindFirstChild(plr.Name) or plr.Character
            if playerModel and playerModel:FindFirstChild("CarriedDurian") then
                local hrp = playerModel:FindFirstChild("HumanoidRootPart")
                local hum = playerModel:FindFirstChildOfClass("Humanoid")
                if hrp and (not hum or hum.Health > 0) then
                    if IsPositionInMyBase(hrp.Position) or (recentBaseVisitors[plr] and (now - recentBaseVisitors[plr] <= 8)) then
                        lockedThiefPlayer = plr
                        return plr, playerModel, hrp
                    end
                end
            end
        end
    end
    return nil, nil, nil
end

AntiStealStatus = function()
    if not _env.AutoAntiSteal then return nil end
    if not GetBatTool() then return nil end
    if FindPlayerCarryingDurian() ~= nil then
        return "ready"
    end
    return nil
end

local function AntiStealTick()
    local targetPlr, playerModel, targetHrp = FindPlayerCarryingDurian()
    if not targetPlr or not playerModel or not targetHrp then return end

    local batTool = GetBatTool()
    if not batTool then return end

    UpdateStatusUI("anti_steal", targetPlr.DisplayName or targetPlr.Name)
    ForceEquipTool(batTool, 2)

    -- ตีไปเรื่อยๆ จนกว่าเป้าหมายจะไม่มี CarriedDurian (ไม่หยุดแม้จะวิ่งออกนอกระยะสวน)
    repeat
        local char = LocalPlayer.Character
        if not char then break end

        batTool = GetBatTool()
        if not batTool then break end
        if batTool.Parent ~= char then
            ForceEquipTool(batTool, 1)
        end

        targetHrp = playerModel:FindFirstChild("HumanoidRootPart")
        local targetHum = playerModel:FindFirstChildOfClass("Humanoid")
        if not targetHrp or (targetHum and targetHum.Health <= 0) then
            break
        end

        -- วาร์ปไปดักตีจากด้านหน้าเป้าหมาย และหันหน้าเข้าหาเป้าหมาย
        local frontCF = targetHrp.CFrame * CFrame.new(0, 0, -2.5) * CFrame.Angles(0, math.pi, 0)
        char:PivotTo(frontCF)

        pcall(function()
            batTool:Activate()
        end)
        pcall(function()
            VirtualUser:ClickButton1(Vector2.new())
        end)

        task.wait(0.08)
    until not _env.AutoAntiSteal
        or not playerModel.Parent
        or not playerModel:FindFirstChild("CarriedDurian")

    if not playerModel.Parent or not playerModel:FindFirstChild("CarriedDurian") then
        lockedThiefPlayer = nil
    end
end

--==================================================
-- Driver Selection (ElectDriver)
--==================================================
local function ElectDriver()
    if AntiStealStatus() == "ready" then
        return "anti_steal"
    end

    if SellStatus() == "ready" then
        return "sell"
    end

    if StealStatus() == "ready" then
        return "steal"
    end

    if BuySeedStatus() == "ready" then
        return "buy_seed"
    end

    local fertState = FertilizeStatus()
    if fertState == "need_buy" or BuyFertStatus() == "ready" then
        return "buy_fert"
    end

    if WaterStatus() == "ready" then
        return "water"
    end

    if fertState == "ready" then
        return "fertilize"
    end

    if HarvestStatus() == "ready" then
        return "harvest"
    end

    return nil
end

local DriverTick = {
    anti_steal = AntiStealTick,
    steal      = StealTick,
    sell       = SellFruitsTick,
    buy_seed   = BuySeedTick,
    buy_fert   = BuyFertTick,
    water      = WateringTick,
    fertilize  = FertilizeTick,
    harvest    = HarvestTick,
}

--==================================================
-- WindUI Integration & Mobile Toggle Button
--==================================================
do
    local success, WindUI = pcall(function()
        return loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
    end)

    if success and WindUI then
        local Window = WindUI:CreateWindow({
            Title = "Durian Farm 🍈",
            Icon = "sprout",
            Author = "by a2c",
            Folder = "DurianFarm",
            Size = UDim2.fromOffset(560, 420),
            Transparent = true,
            Theme = "Dark",
            SideBarWidth = 175,
        })

        pcall(function()
            Window:EditOpenButton({
                Title = "Open Farm UI",
                Icon = "sprout",
                CornerRadius = UDim.new(1, 0),
                StrokeThickness = 2,
                Color = ColorSequence.new(
                    Color3.fromRGB(0, 235, 255),
                    Color3.fromRGB(165, 95, 255)
                ),
                Draggable = true,
            })
        end)

        local guiParent = (gethui and gethui()) or CoreGui
        local oldMob = guiParent:FindFirstChild("MobileWindUIToggle")
        if oldMob then oldMob:Destroy() end

        local MobGui = Instance.new("ScreenGui")
        MobGui.Name = "MobileWindUIToggle"
        MobGui.ResetOnSpawn = false
        MobGui.IgnoreGuiInset = true
        MobGui.Parent = guiParent

        local MobBtn = Instance.new("TextButton")
        MobBtn.Name = "ToggleBtn"
        MobBtn.Position = UDim2.new(0, 18, 0.5, -24)
        MobBtn.Size = UDim2.new(0, 50, 0, 50)
        MobBtn.BackgroundColor3 = Color3.fromRGB(20, 23, 32)
        MobBtn.BackgroundTransparency = 0.1
        MobBtn.Text = "UI"
        MobBtn.Font = Enum.Font.GothamBold
        MobBtn.TextSize = 15
        MobBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        MobBtn.AutoButtonColor = true
        MobBtn.Parent = MobGui

        local MobCorner = Instance.new("UICorner")
        MobCorner.CornerRadius = UDim.new(1, 0)
        MobCorner.Parent = MobBtn

        local MobStroke = Instance.new("UIStroke")
        MobStroke.Thickness = 2
        MobStroke.Color = Color3.fromRGB(0, 235, 255)
        MobStroke.Parent = MobBtn

        local dragging, dragInput, dragStart, startPos
        MobBtn.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                startPos = MobBtn.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        dragging = false
                    end
                end)
            end
        end)

        MobBtn.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                dragInput = input
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if input == dragInput and dragging then
                local delta = input.Position - dragStart
                MobBtn.Position = UDim2.new(
                    startPos.X.Scale,
                    startPos.X.Offset + delta.X,
                    startPos.Y.Scale,
                    startPos.Y.Offset + delta.Y
                )
            end
        end)

        MobBtn.MouseButton1Click:Connect(function()
            pcall(function()
                if Window.Toggle then
                    Window:Toggle()
                else
                    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.RightControl, false, game)
                    task.wait(0.05)
                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.RightControl, false, game)
                end
            end)
        end)

        Window:Tag({
            Title = "v0.0.4",
            Icon = "github",
            Color = Color3.fromHex("#30ff6a"),
            Radius = 12,
        })

        -- TAB 1: Auto Farm
        local FarmTab = Window:Tab({
            Title = "Auto Farm",
            Icon = "tractor",
        })
        
        FarmTab:Select()

        FarmTab:Toggle({
            Title = "Auto Harvest Ripe Fruits",
            Desc = "Warp and press E on ripe durians only",
            Value = _env.AutoHarvest,
            Callback = function(state)
                _env.AutoHarvest = state
                scheduleSave()
            end
        })

        FarmTab:Toggle({
            Title = "Auto Steal (Other Bases)",
            Desc = "Steal highest value ripe fruit (Market Price x kg) & return to Hut floor",
            Value = _env.AutoSteal,
            Callback = function(state)
                _env.AutoSteal = state
                scheduleSave()
            end
        })

        FarmTab:Toggle({
            Title = "Auto Anti-Steal (Hit with Bat)",
            Desc = "Equip Bat and hit thief from the front continuously until CarriedDurian drops",
            Value = _env.AutoAntiSteal,
            Callback = function(state)
                _env.AutoAntiSteal = state
                scheduleSave()
            end
        })

        FarmTab:Toggle({
            Title = "Auto Water Trees",
            Desc = "Water trees when ThirstSign appears",
            Value = _env.AutoWater,
            Callback = function(state)
                _env.AutoWater = state
                scheduleSave()
            end
        })

        FarmTab:Toggle({
            Title = "Auto Apply Fertilizer",
            Desc = "Apply fertilizer when NEEDS FERTILIZER appears",
            Value = _env.AutoFertilize,
            Callback = function(state)
                _env.AutoFertilize = state
                scheduleSave()
            end
        })

        FarmTab:Toggle({
            Title = "Auto Sell Fruits",
            Desc = "Sell all fruits when reaching target amount",
            Value = _env.AutoSell,
            Callback = function(state)
                _env.AutoSell = state
                scheduleSave()
            end
        })

        FarmTab:Slider({
            Title = "Sell Fruit Amount",
            Desc = "Minimum fruits in backpack before selling",
            Step = 1,
            Value = {
                Min = 1,
                Max = 50,
                Default = _env.Config.SellFruitAmount or 10,
            },
            Callback = function(val)
                _env.Config.SellFruitAmount = tonumber(val) or 10
                scheduleSave()
            end
        })

        -- TAB 2: Seed & Fert Shop
        local ShopTab = Window:Tab({
            Title = "Seed & Fert Shop",
            Icon = "shopping-cart",
        })

        ShopTab:Toggle({
            Title = "Auto Buy Seeds",
            Desc = "Automatically buy selected seeds when in stock",
            Value = _env.AutoBuySeed,
            Callback = function(state)
                _env.AutoBuySeed = state
                scheduleSave()
            end
        })

        ShopTab:Dropdown({
            Title = "Select Seeds to Buy",
            Values = {
                "Kradumthong",
                "Chanee",
                "Puangmanee",
                "Kanyao",
                "Nokyip",
                "Monthong",
            },
            Value = _env.Config.SeedsToBuy,
            Multi = true,
            AllowNone = true,
            Callback = function(selected)
                local seeds = {}
                if type(selected) == "table" then
                    for k, v in pairs(selected) do
                        if type(k) == "number" and type(v) == "string" then
                            table.insert(seeds, v)
                        elseif type(k) == "string" and v == true then
                            table.insert(seeds, k)
                        end
                    end
                elseif type(selected) == "string" then
                    table.insert(seeds, selected)
                end
                _env.Config.SeedsToBuy = seeds
                scheduleSave()
            end
        })

        ShopTab:Toggle({
            Title = "Auto Buy Fertilizer",
            Desc = "Buy fertilizer at ShanaKung when out of FertId items",
            Value = _env.AutoBuyFert,
            Callback = function(state)
                _env.AutoBuyFert = state
                scheduleSave()
            end
        })

        ShopTab:Dropdown({
            Title = "Select Fertilizer Type",
            Values = {
                "Basic Fertilizer",
                "Super Fertilizer",
                "Mega Fertilizer",
                "Basic Tree Tonic",
                "Super Tree Tonic",
                "Mega Tree Tonic",
            },
            Value = GetDropdownDisplayFerts(),
            Multi = true,
            AllowNone = false,
            Callback = function(selected)
                _env.Config.FertsToBuy = NormalizeFertList(selected)
                print("[ElectDriver] Selected Fertilizers:", table.concat(_env.Config.FertsToBuy, ", "))
                scheduleSave()
            end
        })

        ShopTab:Slider({
            Title = "Keep Fertilizer Amount",
            Desc = "Minimum fertilizer count to keep in backpack",
            Step = 1,
            Value = {
                Min = 1,
                Max = 20,
                Default = _env.Config.MinFertKeep or 1,
            },
            Callback = function(val)
                _env.Config.MinFertKeep = tonumber(val) or 1
                scheduleSave()
            end
        })

        -- TAB 3: Settings (Auto-Save / Reset)
        local okTab, SettingsTab = pcall(function()
            return Window:Tab({
                Title = "Settings",
                Icon = "settings",
            })
        end)

        if okTab and SettingsTab then
            pcall(function()
                SettingsTab:Toggle({
                    Title = "Auto-Save Settings",
                    Desc = "Save toggles/sliders/dropdowns automatically to " .. SAVE_FILE,
                    Value = _env.AutoSaveEnabled,
                    Callback = function(state)
                        _env.AutoSaveEnabled = state
                        if state then
                            scheduleSave()
                        else
                            saveSettings(true)
                        end
                    end
                })
            end)

            pcall(function()
                SettingsTab:Button({
                    Title = "Save Settings Now",
                    Desc = "Manually save current configuration to file",
                    Callback = function()
                        saveSettings(false)
                    end
                })
            end)

            pcall(function()
                SettingsTab:Button({
                    Title = "Reset to Defaults",
                    Desc = "Reset everything and clear saved config file",
                    Callback = function()
                        _env.AutoSell = false
                        _env.AutoBuySeed = false
                        _env.AutoBuyFert = false
                        _env.AutoWater = false
                        _env.AutoFertilize = false
                        _env.AutoHarvest = false
                        _env.AutoSteal = false
                        _env.AutoAntiSteal = false
                        _env.AutoSaveEnabled = false
                        _env.Config.SellFruitAmount = 10
                        _env.Config.SeedsToBuy = { "Kradumthong", "Chanee", "Puangmanee" }
                        _env.Config.FertsToBuy = { "Basic" }
                        _env.Config.MinFertKeep = 1
                        if delfile then pcall(delfile, SAVE_FILE) end
                        saveSettings(true)
                        print("[ElectDriver] Settings reset to defaults. Re-open UI to refresh widgets.")
                    end
                })
            end)

            pcall(function()
                SettingsTab:Paragraph({
                    Title = "Config File Location",
                    Desc = "Saved to: " .. SAVE_FILE .. "\nExecutors must support writefile/readfile/isfile/makefolder.",
                })
            end)

            local Discord = Window:Tab({
                Title = "Discord",
                Icon = "accessibility",
                Locked = false,
            })

            Discord:Button({
                Title = "Copy Discord Link",
                Desc = "https://discord.com/invite/zSFhz9VfHu",
                Locked = false,
                Callback = function()
                    setclipboard("https://discord.com/invite/zSFhz9VfHu")
                    WindUI:Notify({
                        Title = "Discord Copied!",
                        Content = "https://discord.com/invite/zSFhz9VfHu",
                        Duration = 3,
                        Icon = "clipboard-copy",
                    })
                end
            })
        end
    else
        warn("Failed to load WindUI:", tostring(WindUI))
    end
end

--==================================================
-- Main Loop
--==================================================
task.spawn(function()
    while _env.FarmLoopRunId == currentRunId and _wait(0.1) do
        if not _env.LoadedData then
            UpdateStatusUI("idle", "Loading Base...")
            repeat
                LoadPlayerBase()
                _wait(0.5)
            until _env.LoadedData or _env.FarmLoopRunId ~= currentRunId
        end

        if _env.FarmLoopRunId ~= currentRunId then break end

        local driver = ElectDriver()
        if driver ~= _env._lastDriver then
            _env._lastDriver = driver
            print("Driver: " .. tostring(driver))
            UpdateStatusUI(driver)
        end

        if driver then
            local fn = DriverTick[driver]
            if fn then
                xpcall(fn, Error)
            end
        end
    end
end)
