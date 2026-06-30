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
        essenceUpgrades = 0,
        errors = 0,
    },
    settings = {
        autoQi = false,
        autoBreakthrough = false,
        autoQiUpgrades = false,
        autoInsightReset = false,
        autoInsightUpgrades = false,
        autoEssenceUpgrades = false,
        qiInterval = 0.08,
        breakthroughInterval = 0.2,
        qiUpgradeInterval = 0.55,
        insightResetInterval = 1.25,
        insightUpgradeInterval = 0.85,
        essenceUpgradeInterval = 0.85,
        insightResetWait = 120,
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
        "InsightMarkSpeed",
        "InsightLuckMultiplier",
        "InsightQiMultiplier",
    },
    insightUpgradeConfig = {
        InsightMultiplier = { baseCost = 1, costMult = 1.87, maxLevel = 75 },
        InsightMarkSpeed = { baseCost = 1000, costMult = 1000, maxLevel = 5 },
        InsightLuckMultiplier = { baseCost = 3, costMult = 1.89, maxLevel = 75 },
        InsightQiMultiplier = { baseCost = 2, costMult = 1.85, maxLevel = 75 },
    },
    essenceUpgradePriority = {
        "EssenceYield",
        "RefinementLink",
        "MoteFlow",
        "CauldronFocus",
    },
    qiIndex = 1,
    insightIndex = 1,
    essenceIndex = 1,
    lastRealm = nil,
    lastBreakthroughAt = os.clock(),
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

local function getRealm()
    local value = tonumber(player:GetAttribute("Realm"))

    if value then
        return math.floor(value)
    end

    local leaderstats = player:FindFirstChild("leaderstats")
    local realmValue = leaderstats and leaderstats:FindFirstChild("Realm")
    local text = realmValue and tostring(realmValue.Value) or ""
    return tonumber(text:match("%d+"))
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

local function numberToBig(value)
    return normalizeBig({ m = tonumber(value) or 0, e = 0 })
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

local function getInsightUpgradeCost(upgradeId)
    local config = state.insightUpgradeConfig[upgradeId]
    local level = tonumber(player:GetAttribute("Upgrade_" .. upgradeId)) or 0

    if not config or level >= config.maxLevel then
        return nil
    end

    return multiplyBig(numberToBig(config.baseCost), config.costMult ^ level)
end

local function getAffordableInsightUpgrade()
    local insight = bigFromAttributes("Insight")

    for _, upgradeId in ipairs(state.insightUpgradePriority) do
        local cost = getInsightUpgradeCost(upgradeId)
        if cost and compareBig(insight, cost) >= 0 then
            return upgradeId
        end
    end

    return nil
end

local function shouldResetInsight()
    local waitTime = math.max(1, tonumber(state.settings.insightResetWait) or 120)
    return os.clock() - state.lastBreakthroughAt >= waitTime
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

local function teleportToRealmButtonTop()
    local character = player.Character or player.CharacterAdded:Wait()
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    local realmButton = workspace:WaitForChild("RealmButton", 2)
    local realmButtonTop = realmButton and realmButton:WaitForChild("RealmButtonTop", 2)

    if rootPart and realmButtonTop then
        rootPart.CFrame = realmButtonTop.CFrame + Vector3.new(0, 4, 0)
    end

    return realmButtonTop
end

local function fireBreakthrough()
    local ok, err = pcall(function()
        teleportToRealmButtonTop()
        remotes.realmPress:FireServer()
    end)

    if ok then
        state.stats.breakthroughs += 1
    else
        state.stats.errors += 1
        warn("[ImmortalityAuto] breakthrough failed: " .. tostring(err))
    end
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
main.Size = UDim2.fromOffset(360, 560)
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
status.Size = UDim2.new(1, 0, 0, 68)
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
makeRow("Auto Essence Upgrades", "autoEssenceUpgrades", "essenceUpgradeInterval")

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

makeNumberRow("Insight Reset Wait", "insightResetWait", 1, 3600)

local footer = Instance.new("TextLabel")
footer.Name = "Footer"
footer.Size = UDim2.new(1, 0, 0, 52)
footer.BackgroundTransparency = 1
footer.Font = Enum.Font.Gotham
footer.Text = "Insight upgrades use priority order. Reset waits for no breakthrough."
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
    main.Size = state.collapsed and UDim2.fromOffset(360, 44) or UDim2.fromOffset(360, 560)
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
    fireBreakthrough()
end)

loopEvery("qiUpgradeInterval", "autoQiUpgrades", function()
    local upgradeId = state.qiUpgradePriority[state.qiIndex]
    state.qiIndex = state.qiIndex % #state.qiUpgradePriority + 1
    safeFire("qiUpgrades", remotes.purchaseUpgrade, upgradeId, true)
end)

loopEvery("insightResetInterval", "autoInsightReset", function()
    if shouldResetInsight() then
        safeFire("insightResets", remotes.purchaseInsight)
        state.lastBreakthroughAt = os.clock()
    end
end)

loopEvery("insightUpgradeInterval", "autoInsightUpgrades", function()
    local upgradeId = getAffordableInsightUpgrade()
    if upgradeId then
        safeFire("insightUpgrades", remotes.purchaseUpgrade, upgradeId, true)
    end
end)

loopEvery("essenceUpgradeInterval", "autoEssenceUpgrades", function()
    local upgradeId = state.essenceUpgradePriority[state.essenceIndex]
    state.essenceIndex = state.essenceIndex % #state.essenceUpgradePriority + 1
    safeFire("essenceUpgrades", remotes.purchaseUpgrade, upgradeId, true)
end)

task.spawn(function()
    while state.running do
        local currentRealm = getRealm()
        if currentRealm then
            if state.lastRealm and currentRealm > state.lastRealm then
                state.lastBreakthroughAt = os.clock()
            end
            state.lastRealm = currentRealm
        end

        status.Text = string.format(
            "Qi: %d | Breakthroughs: %d | Qi upgrades: %d\nInsight resets: %d | Insight upgrades: %d | Essence upgrades: %d\nReset wait: %ds | Errors: %d",
            state.stats.qiClicks,
            state.stats.breakthroughs,
            state.stats.qiUpgrades,
            state.stats.insightResets,
            state.stats.insightUpgrades,
            state.stats.essenceUpgrades,
            math.max(0, math.ceil((tonumber(state.settings.insightResetWait) or 120) - (os.clock() - state.lastBreakthroughAt))),
            state.stats.errors
        )
        task.wait(0.35)
    end
end)

print("[ImmortalityAuto] GUI loaded")
