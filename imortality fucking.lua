-- Immortality Incremental GUI helper.
-- Re-run this file to refresh the GUI. Use the Kill button to stop all loops.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remoteFolder = ReplicatedStorage:WaitForChild("RemoteEvents")

local remotes = {
    gainQi = remoteFolder:WaitForChild("GainQi"),
    realmPress = remoteFolder:WaitForChild("RealmPress"),
    purchaseUpgrade = remoteFolder:WaitForChild("PurchaseUpgrade"),
    purchaseInsight = remoteFolder:WaitForChild("PurchaseInsight"),
}

_G.ImmortalityAutoFarmRunning = false

local old = playerGui:FindFirstChild("ImmortalityAutoGui")
if old then
    old:Destroy()
end

if _G.ImmortalityAuto then
    _G.ImmortalityAuto.running = false
    task.wait(0.15)
end

local state = {
    running = true,
    collapsed = false,
    stats = {
        qiClicks = 0,
        breakthroughs = 0,
        qiUpgrades = 0,
        insightResets = 0,
        insightUpgrades = 0,
        insightSkips = 0,
        errors = 0,
    },
    settings = {
        autoQi = true,
        autoBreakthrough = true,
        autoQiUpgrades = true,
        autoInsightReset = true,
        autoInsightUpgrades = true,
        qiInterval = 0.08,
        breakthroughInterval = 0.25,
        qiUpgradeInterval = 0.55,
        insightResetInterval = 1.25,
        insightUpgradeInterval = 0.85,
        breakthroughBurst = 8,
        breakthroughStandTime = 1.4,
        resetExtraRealms = 25,
        resetGainMultiplier = 25,
    },
    qiUpgradePriority = {
        "QiMultiplier",
        "BreakthroughLuck",
        "QiMultiplier",
        "BreakthroughLuck",
        "MarkBulk",
    },
    insightUpgradePriority = {
        "InsightMultiplier",
    },
    qiIndex = 1,
    insightIndex = 1,
    statusNote = "Loaded",
}

_G.ImmortalityAuto = state

local function safeFire(statName, remote, ...)
    local ok, err = pcall(function(...)
        remote:FireServer(...)
    end, ...)

    if ok then
        state.stats[statName] += 1
    else
        state.stats.errors += 1
        warn("[ImmortalityAuto] " .. remote.Name .. " failed: " .. tostring(err))
    end
end

local function loopEvery(intervalKey, enabledKey, fn)
    task.spawn(function()
        while state.running do
            if state.settings[enabledKey] then
                fn()
            end
            task.wait(math.max(0.03, tonumber(state.settings[intervalKey]) or 0.25))
        end
    end)
end

local function bigFromAttributes(prefix)
    local mantissa = player:GetAttribute(prefix .. "Mantissa")
    local exponent = player:GetAttribute(prefix .. "Exponent")
    if type(mantissa) ~= "number" or type(exponent) ~= "number" then
        return { m = 0, e = 0 }
    end
    return { m = mantissa, e = exponent }
end

local function normalizeBig(value)
    if not value or value.m <= 0 then
        return { m = 0, e = 0 }
    end

    local mantissa = value.m
    local exponent = value.e

    while mantissa >= 10 do
        mantissa /= 10
        exponent += 1
    end

    while mantissa > 0 and mantissa < 1 do
        mantissa *= 10
        exponent -= 1
    end

    return { m = mantissa, e = exponent }
end

local function multiplyBig(value, multiplier)
    multiplier = tonumber(multiplier) or 1
    if multiplier <= 0 then
        multiplier = 1
    end

    return normalizeBig({
        m = (value and value.m or 0) * multiplier,
        e = value and value.e or 0,
    })
end

local function compareBig(left, right)
    left = normalizeBig(left)
    right = normalizeBig(right)

    if left.m <= 0 and right.m <= 0 then
        return 0
    end

    if left.m <= 0 then
        return -1
    end

    if right.m <= 0 then
        return 1
    end

    if left.e ~= right.e then
        return left.e > right.e and 1 or -1
    end

    if math.abs(left.m - right.m) < 0.000001 then
        return 0
    end

    return left.m > right.m and 1 or -1
end

local function formatBig(value)
    value = normalizeBig(value)
    if value.m <= 0 then
        return "0"
    end

    if value.e < 6 then
        return tostring(math.floor(value.m * 10 ^ value.e))
    end

    return string.format("%.2fe%d", value.m, value.e)
end

local function canAffordBreakthrough()
    return compareBig(bigFromAttributes("Qi"), bigFromAttributes("RealmNextBreakthroughCost")) >= 0
end

local function getRealmButtonTop()
    local realmButton = workspace:FindFirstChild("RealmButton")
    if realmButton then
        local top = realmButton:FindFirstChild("RealmButtonTop")
        if top and top:IsA("BasePart") then
            return top
        end
    end

    for _, item in ipairs(workspace:GetDescendants()) do
        if item:IsA("BasePart") and item.Name == "RealmButtonTop" then
            return item
        end
    end

    return nil
end

local function pressRealmButton(standTime)
    local top = getRealmButtonTop()
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")

    if top and root and firetouchinterest then
        local originalCFrame = root.CFrame
        local originalAssemblyLinearVelocity = root.AssemblyLinearVelocity
        local originalAssemblyAngularVelocity = root.AssemblyAngularVelocity
        local deadline = os.clock() + math.clamp(tonumber(standTime) or 1.4, 0.2, 10)
        local standCFrame = top.CFrame + top.CFrame.UpVector * (top.Size.Y * 0.5 + 3)

        while state.running and state.settings.autoBreakthrough and os.clock() < deadline do
            root.CFrame = standCFrame
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            firetouchinterest(root, top, 0)
            task.wait(0.04)
            firetouchinterest(root, top, 1)
            state.stats.breakthroughs += 1
            task.wait(0.04)
        end

        if root and root.Parent then
            root.CFrame = originalCFrame
            root.AssemblyLinearVelocity = originalAssemblyLinearVelocity
            root.AssemblyAngularVelocity = originalAssemblyAngularVelocity
        end

        state.statusNote = "Spoofed Realm button stand"
        return
    end

    safeFire("breakthroughs", remotes.realmPress)
end

local function shouldResetInsight()
    local realm = tonumber(player:GetAttribute("Realm")) or 0
    local minRealm = tonumber(player:GetAttribute("InsightResetMinRealm")) or 1
    local targetRealm = minRealm + math.max(0, tonumber(state.settings.resetExtraRealms) or 0)

    if player:GetAttribute("InsightResetRequirementMet") ~= true then
        state.statusNote = "Insight reset waiting for requirement"
        return false
    end

    if realm < targetRealm then
        state.statusNote = "Insight reset waiting for realm " .. tostring(targetRealm)
        return false
    end

    local currentInsight = bigFromAttributes("Insight")
    local previewGain = bigFromAttributes("InsightResetPreview")
    local neededGain = multiplyBig(currentInsight, state.settings.resetGainMultiplier)

    if currentInsight.m > 0 and compareBig(previewGain, neededGain) < 0 then
        state.statusNote = "Insight reset waiting for " .. tostring(state.settings.resetGainMultiplier) .. "x gain"
        return false
    end

    state.statusNote = "Insight reset ready: +" .. formatBig(previewGain)
    return true
end

local gui = Instance.new("ScreenGui")
gui.Name = "ImmortalityAutoGui"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local main = Instance.new("Frame")
main.Name = "Main"
main.AnchorPoint = Vector2.new(0, 0)
main.Position = UDim2.fromOffset(24, 160)
main.Size = UDim2.fromOffset(360, 610)
main.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
main.BorderSizePixel = 0
main.Parent = gui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 8)
mainCorner.Parent = main

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = Color3.fromRGB(132, 85, 255)
mainStroke.Thickness = 1
mainStroke.Transparency = 0.2
mainStroke.Parent = main

local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, 44)
titleBar.BackgroundColor3 = Color3.fromRGB(30, 33, 46)
titleBar.BorderSizePixel = 0
titleBar.Parent = main

local titleCorner = Instance.new("UICorner")
titleCorner.CornerRadius = UDim.new(0, 8)
titleCorner.Parent = titleBar

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(14, 0)
title.Size = UDim2.new(1, -96, 1, 0)
title.Font = Enum.Font.GothamBold
title.Text = "Immortality Auto"
title.TextColor3 = Color3.fromRGB(245, 241, 255)
title.TextSize = 18
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = titleBar

local function makeTopButton(name, text, x)
    local button = Instance.new("TextButton")
    button.Name = name
    button.Position = UDim2.new(1, x, 0, 8)
    button.Size = UDim2.fromOffset(30, 28)
    button.BackgroundColor3 = Color3.fromRGB(47, 51, 70)
    button.BorderSizePixel = 0
    button.Font = Enum.Font.GothamBold
    button.Text = text
    button.TextColor3 = Color3.fromRGB(245, 241, 255)
    button.TextSize = 14
    button.Parent = titleBar

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = button

    return button
end

local collapseButton = makeTopButton("Collapse", "-", -72)
local killButton = makeTopButton("Kill", "x", -36)
killButton.BackgroundColor3 = Color3.fromRGB(185, 62, 72)

local body = Instance.new("Frame")
body.Name = "Body"
body.Position = UDim2.fromOffset(0, 44)
body.Size = UDim2.new(1, 0, 1, -44)
body.BackgroundTransparency = 1
body.Parent = main

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = body

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 12)
padding.PaddingRight = UDim.new(0, 12)
padding.PaddingTop = UDim.new(0, 12)
padding.PaddingBottom = UDim.new(0, 12)
padding.Parent = body

local status = Instance.new("TextLabel")
status.Name = "Status"
status.Size = UDim2.new(1, 0, 0, 56)
status.BackgroundColor3 = Color3.fromRGB(24, 27, 38)
status.BorderSizePixel = 0
status.Font = Enum.Font.Gotham
status.TextColor3 = Color3.fromRGB(214, 222, 245)
status.TextSize = 13
status.TextWrapped = true
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Center
status.Parent = body

local statusCorner = Instance.new("UICorner")
statusCorner.CornerRadius = UDim.new(0, 8)
statusCorner.Parent = status

local statusPadding = Instance.new("UIPadding")
statusPadding.PaddingLeft = UDim.new(0, 10)
statusPadding.PaddingRight = UDim.new(0, 10)
statusPadding.Parent = status

local rows = {}

local function makeRow(labelText, key, intervalKey)
    local row = Instance.new("Frame")
    row.Name = key .. "Row"
    row.Size = UDim2.new(1, 0, 0, 42)
    row.BackgroundColor3 = Color3.fromRGB(24, 27, 38)
    row.BorderSizePixel = 0
    row.Parent = body

    local rowCorner = Instance.new("UICorner")
    rowCorner.CornerRadius = UDim.new(0, 8)
    rowCorner.Parent = row

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Position = UDim2.fromOffset(10, 0)
    label.Size = UDim2.new(1, -172, 1, 0)
    label.Font = Enum.Font.GothamSemibold
    label.Text = labelText
    label.TextColor3 = Color3.fromRGB(238, 242, 255)
    label.TextSize = 13
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = row

    local input = Instance.new("TextBox")
    input.Name = "Interval"
    input.Position = UDim2.new(1, -108, 0, 8)
    input.Size = UDim2.fromOffset(48, 26)
    input.BackgroundColor3 = Color3.fromRGB(13, 15, 22)
    input.BorderSizePixel = 0
    input.ClearTextOnFocus = false
    input.Font = Enum.Font.Gotham
    input.Text = tostring(state.settings[intervalKey])
    input.TextColor3 = Color3.fromRGB(230, 235, 255)
    input.TextSize = 12
    input.Parent = row

    local inputCorner = Instance.new("UICorner")
    inputCorner.CornerRadius = UDim.new(0, 6)
    inputCorner.Parent = input

    local toggle = Instance.new("TextButton")
    toggle.Name = "Toggle"
    toggle.Position = UDim2.new(1, -52, 0, 8)
    toggle.Size = UDim2.fromOffset(42, 26)
    toggle.BorderSizePixel = 0
    toggle.Font = Enum.Font.GothamBold
    toggle.TextSize = 12
    toggle.Parent = row

    local toggleCorner = Instance.new("UICorner")
    toggleCorner.CornerRadius = UDim.new(0, 6)
    toggleCorner.Parent = toggle

    local function paint()
        local enabled = state.settings[key]
        toggle.Text = enabled and "ON" or "OFF"
        toggle.BackgroundColor3 = enabled and Color3.fromRGB(73, 170, 103) or Color3.fromRGB(88, 92, 110)
        toggle.TextColor3 = Color3.fromRGB(255, 255, 255)
    end

    toggle.Activated:Connect(function()
        state.settings[key] = not state.settings[key]
        paint()
    end)

    input.FocusLost:Connect(function()
        local value = tonumber(input.Text)
        if value then
            state.settings[intervalKey] = math.clamp(value, 0.03, 10)
        end
        input.Text = tostring(state.settings[intervalKey])
    end)

    paint()
    table.insert(rows, row)
end

makeRow("Auto Qi", "autoQi", "qiInterval")
makeRow("Auto Breakthrough", "autoBreakthrough", "breakthroughInterval")
makeRow("Auto Qi Upgrades", "autoQiUpgrades", "qiUpgradeInterval")
makeRow("Auto Insight Reset", "autoInsightReset", "insightResetInterval")
makeRow("Auto Insight Upgrades", "autoInsightUpgrades", "insightUpgradeInterval")

local function makeNumberRow(labelText, settingKey, minValue, maxValue)
    local row = Instance.new("Frame")
    row.Name = settingKey .. "Row"
    row.Size = UDim2.new(1, 0, 0, 38)
    row.BackgroundColor3 = Color3.fromRGB(24, 27, 38)
    row.BorderSizePixel = 0
    row.Parent = body

    local rowCorner = Instance.new("UICorner")
    rowCorner.CornerRadius = UDim.new(0, 8)
    rowCorner.Parent = row

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Position = UDim2.fromOffset(10, 0)
    label.Size = UDim2.new(1, -76, 1, 0)
    label.Font = Enum.Font.GothamSemibold
    label.Text = labelText
    label.TextColor3 = Color3.fromRGB(238, 242, 255)
    label.TextSize = 12
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = row

    local input = Instance.new("TextBox")
    input.Name = "Value"
    input.Position = UDim2.new(1, -58, 0, 6)
    input.Size = UDim2.fromOffset(48, 26)
    input.BackgroundColor3 = Color3.fromRGB(13, 15, 22)
    input.BorderSizePixel = 0
    input.ClearTextOnFocus = false
    input.Font = Enum.Font.Gotham
    input.Text = tostring(state.settings[settingKey])
    input.TextColor3 = Color3.fromRGB(230, 235, 255)
    input.TextSize = 12
    input.Parent = row

    local inputCorner = Instance.new("UICorner")
    inputCorner.CornerRadius = UDim.new(0, 6)
    inputCorner.Parent = input

    input.FocusLost:Connect(function()
        local value = tonumber(input.Text)
        if value then
            state.settings[settingKey] = math.clamp(value, minValue, maxValue)
        end
        input.Text = tostring(state.settings[settingKey])
    end)
end

makeNumberRow("Breakthrough Burst", "breakthroughBurst", 1, 50)
makeNumberRow("Breakthrough Stand Time", "breakthroughStandTime", 0.2, 10)
makeNumberRow("Reset Extra Realms", "resetExtraRealms", 0, 1000)
makeNumberRow("Reset Gain x Current", "resetGainMultiplier", 1, 1000000)

local footer = Instance.new("TextLabel")
footer.Name = "Footer"
footer.Size = UDim2.new(1, 0, 0, 52)
footer.BackgroundTransparency = 1
footer.Font = Enum.Font.Gotham
footer.Text = "Insight upgrades only buy More Insight. Reset waits for extra realms and gain multiplier."
footer.TextColor3 = Color3.fromRGB(163, 171, 198)
footer.TextSize = 12
footer.TextWrapped = true
footer.TextXAlignment = Enum.TextXAlignment.Left
footer.TextYAlignment = Enum.TextYAlignment.Top
footer.Parent = body

local dragging = false
local dragStart
local startPos

titleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = main.Position
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

collapseButton.Activated:Connect(function()
    state.collapsed = not state.collapsed
    body.Visible = not state.collapsed
    main.Size = state.collapsed and UDim2.fromOffset(360, 44) or UDim2.fromOffset(360, 610)
    collapseButton.Text = state.collapsed and "+" or "-"
end)

killButton.Activated:Connect(function()
    state.running = false
    gui:Destroy()
end)

loopEvery("qiInterval", "autoQi", function()
    safeFire("qiClicks", remotes.gainQi)
end)

loopEvery("breakthroughInterval", "autoBreakthrough", function()
    if not canAffordBreakthrough() then
        state.statusNote = "Breakthrough waiting for qi"
        return
    end

    local burst = math.floor(tonumber(state.settings.breakthroughBurst) or 1)
    local standTime = tonumber(state.settings.breakthroughStandTime) or 1.4
    for _ = 1, math.clamp(burst, 1, 50) do
        if not state.running or not state.settings.autoBreakthrough then
            break
        end

        pressRealmButton(standTime)
        task.wait(0.035)
    end
end)

loopEvery("qiUpgradeInterval", "autoQiUpgrades", function()
    local upgradeId = state.qiUpgradePriority[state.qiIndex]
    state.qiIndex = state.qiIndex % #state.qiUpgradePriority + 1
    safeFire("qiUpgrades", remotes.purchaseUpgrade, upgradeId, true)
end)

loopEvery("insightResetInterval", "autoInsightReset", function()
    if shouldResetInsight() then
        safeFire("insightResets", remotes.purchaseInsight)
    else
        state.stats.insightSkips += 1
    end
end)

loopEvery("insightUpgradeInterval", "autoInsightUpgrades", function()
    local upgradeId = state.insightUpgradePriority[state.insightIndex]
    state.insightIndex = state.insightIndex % #state.insightUpgradePriority + 1
    safeFire("insightUpgrades", remotes.purchaseUpgrade, upgradeId, true)
end)

task.spawn(function()
    while state.running do
        status.Text = string.format(
            "Realm: #%d | Qi: %d | Breakthroughs: %d | Qi upgrades: %d\nInsight resets: %d | Skips: %d | Insight upgrades: %d | Errors: %d\n%s",
            tonumber(player:GetAttribute("Realm")) or 0,
            state.stats.qiClicks,
            state.stats.breakthroughs,
            state.stats.qiUpgrades,
            state.stats.insightResets,
            state.stats.insightSkips,
            state.stats.insightUpgrades,
            state.stats.errors,
            state.statusNote
        )
        task.wait(0.35)
    end
end)

print("[ImmortalityAuto] GUI loaded")
