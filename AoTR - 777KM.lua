-- AoT:R Freemium by 777KM
-- UI: Obsidian (https://github.com/deividcomsono/Obsidian)

--===========================================================
-- Services & Locals
--===========================================================
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local Workspace          = game:GetService("Workspace")
local Lighting           = game:GetService("Lighting")
local TweenService       = game:GetService("TweenService")
local RS                 = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera

local function getRoot()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChildOfClass("Humanoid")
end

--===========================================================
-- Load Obsidian
--===========================================================
local repo          = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library       = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager  = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager   = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles

--===========================================================
-- Window
--===========================================================
local Window = Library:CreateWindow({
    Title       = "AoT:R Freemium",
    Footer      = "AOT:R by 777KM",
    NotifySide  = "Right",
    ShowCustomCursor = false,
})

local Tabs = {
    Combat     = Window:AddTab("Combat",     "sword"),
    Visuals    = Window:AddTab("Visuals",    "eye"),
    Utility    = Window:AddTab("Utility",    "wrench"),
    Misc       = Window:AddTab("Misc",       "settings-2"),
    ["UI Settings"] = Window:AddTab("UI Settings", "settings"),
}

--===========================================================
-- Common helpers
--===========================================================
-- Game-specific paths discovered via AOTR Spy:
--   workspace.Titans                     — folder; children are titan Models with random-UUID names
--   <titan>.Hitboxes.Hit.Nape            — kill-zone BasePart for the damage call
--   ReplicatedStorage.Assets.Remotes.POST — RemoteEvent; tunnel for all gameplay actions
-- Lazy-resolved: in the lobby this path may not exist yet, and WaitForChild
-- would yield the whole script (blocking the UI from being built).
local function getPOST()
    local assets  = RS:FindFirstChild("Assets")
    local remotes = assets and assets:FindFirstChild("Remotes")
    return remotes and remotes:FindFirstChild("POST")
end

local function iterTitans()
    local list = {}
    local container = Workspace:FindFirstChild("Titans")
    if not container then return list end
    for _, m in ipairs(container:GetChildren()) do
        if m:IsA("Model") then
            table.insert(list, m)
        end
    end
    return list
end

local function getTitanNape(titan)
    local hb  = titan:FindFirstChild("Hitboxes")
    local hit = hb and hb:FindFirstChild("Hit")
    return hit and hit:FindFirstChild("Nape")
end

-- Death detection: a titan is dead the moment its `Humanoid` child is gone.
-- The game removes/destroys it on kill before the model itself despawns,
-- so this fires faster and more reliably than state-attribute watching or
-- waiting for the whole model to unparent.
local function isTitanDead(titan)
    if not titan or not titan.Parent then return true end
    return titan:FindFirstChildOfClass("Humanoid") == nil
end

--===========================================================
-- COMBAT TAB
--===========================================================
local CombatBox = Tabs.Combat:AddLeftGroupbox("Auto Farm", "swords")

CombatBox:AddToggle("AutoKill", {
    Text    = "Auto Kill Titans",
    Default = false,
    Tooltip = "Fires Slash + Hitboxes:Register on the current target each tick.",
})

CombatBox:AddToggle("TPAboveTitan", {
    Text    = "Hover Above",
    Default = true,
    Tooltip = "Continuously holds your character above the current target's nape for safety while farming.",
})

CombatBox:AddSlider("TPHeight", {
    Text    = "Hover height",
    Default = 500,
    Min     = 5,
    Max     = 500,
    Rounding= 0,
    Suffix  = " studs",
})

CombatBox:AddToggle("MultiHit", {
    Text    = "Multi-hit",
    Default = false,
    Tooltip = "Hits multiple titan",
})

CombatBox:AddSlider("MultiHitCount", {
    Text    = "Multi-hit titans",
    Default = 5,
    Min     = 2,
    Max     = 10,
    Rounding= 0,
})

local TitanCountLabel = CombatBox:AddLabel("Titans: 0", true)

local NapeBox = Tabs.Combat:AddRightGroupbox("Nape", "target")

NapeBox:AddToggle("NapeExtender", {
    Text    = "Nape Extender",
    Default = false,
    Tooltip = "Scales every titan's nape hitbox so hits register easier.",
})

NapeBox:AddSlider("NapeExtenderSize", {
    Text    = "Nape size multiplier",
    Default = 3,
    Min     = 1,
    Max     = 10,
    Rounding= 1,
    Suffix  = "x",
})

NapeBox:AddToggle("NapeVisual", {
    Text    = "Nape Visual",
    Default = false,
    Tooltip = "Highlights the nape on every titan.",
})

NapeBox:AddLabel("Nape color"):AddColorPicker("NapeColor", {
    Default = Color3.fromRGB(255, 40, 40),
    Title   = "Nape color",
})

NapeBox:AddSlider("NapeVisualTransparency", {
    Text    = "Visual transparency",
    Default = 0.4,
    Min     = 0,
    Max     = 1,
    Rounding= 2,
})

--===========================================================
-- VISUALS TAB (ESP)
--===========================================================
local ESPBox = Tabs.Visuals:AddLeftGroupbox("ESP", "eye")

ESPBox:AddToggle("TitanESP", {
    Text    = "Titan ESP",
    Default = false,
})
ESPBox:AddLabel("Titan color"):AddColorPicker("TitanESPColor", {
    Default = Color3.fromRGB(255, 80, 80),
})

ESPBox:AddToggle("PlayerESP", {
    Text    = "Player ESP",
    Default = false,
})
ESPBox:AddLabel("Player color"):AddColorPicker("PlayerESPColor", {
    Default = Color3.fromRGB(80, 200, 255),
})

ESPBox:AddToggle("ESPNames", {
    Text    = "Show Names",
    Default = true,
})

ESPBox:AddToggle("ESPDistance", {
    Text    = "Show Distance",
    Default = true,
})

local WorldBox = Tabs.Visuals:AddRightGroupbox("World", "sun")

WorldBox:AddToggle("Fullbright", {
    Text    = "Fullbright",
    Default = false,
})

WorldBox:AddSlider("FOV", {
    Text    = "Camera FOV",
    Default = 70,
    Min     = 30,
    Max     = 120,
    Rounding= 0,
})

--===========================================================
-- UTILITY TAB
--===========================================================
local UtilBox = Tabs.Utility:AddLeftGroupbox("Auto", "zap")

UtilBox:AddToggle("AutoReload", {
    Text    = "Auto Reload",
    Default = false,
    Tooltip = "Reloads blades when the durability bar runs out.",
})

UtilBox:AddToggle("AutoRefill", {
    Text    = "Auto Refill",
    Default = false,
    Tooltip = "Refills blades at HQ refill station when out of sets.",
})

UtilBox:AddToggle("AutoEscape", {
    Text    = "Auto Escape",
    Default = false,
    Tooltip = "Auto-escapes when a titan grabs you.",
})

--===========================================================
-- MISC TAB
--===========================================================
local MiscBox = Tabs.Misc:AddLeftGroupbox("Misc", "wrench")

MiscBox:AddToggle("AutoRetry", {
    Text    = "Auto Retry",
    Default = false,
    Tooltip = "When you die, automatically respawn / requeue.",
})

MiscBox:AddToggle("AntiAFK", {
    Text    = "Anti-AFK",
    Default = true,
})

MiscBox:AddButton({
    Text = "Rejoin server",
    Func = function()
        game:GetService("TeleportService"):Teleport(game.PlaceId, LocalPlayer)
    end,
})

MiscBox:AddButton({
    Text = "Reset character",
    Func = function()
        local hum = getHumanoid()
        if hum then hum.Health = 0 end
    end,
})

local CreditsBox = Tabs.Misc:AddRightGroupbox("Credits", "heart")
CreditsBox:AddLabel("AoT:R Freemium by 777KM", true)
CreditsBox:AddLabel("UI: Obsidian by deividcomsono", true)

--===========================================================
-- ============== FEATURE IMPLEMENTATIONS ==================
--===========================================================

--------- FOV ---------
Options.FOV:OnChanged(function()
    Camera.FieldOfView = Options.FOV.Value
end)

--------- Fullbright ---------
local origAmbient, origBrightness, origColorShift
local function setFullbright(on)
    if on then
        if origAmbient == nil then
            origAmbient    = Lighting.Ambient
            origBrightness = Lighting.Brightness
            origColorShift = Lighting.ColorShift_Bottom
        end
        Lighting.Ambient            = Color3.new(1,1,1)
        Lighting.Brightness         = 2
        Lighting.ColorShift_Bottom  = Color3.new(1,1,1)
    else
        if origAmbient ~= nil then
            Lighting.Ambient            = origAmbient
            Lighting.Brightness         = origBrightness
            Lighting.ColorShift_Bottom  = origColorShift
        end
    end
end
Toggles.Fullbright:OnChanged(function() setFullbright(Toggles.Fullbright.Value) end)

--------- ESP ---------
local ESP = {} -- model -> { highlight, billboard }

local function destroyEsp(model)
    local entry = ESP[model]
    if entry then
        if entry.highlight then entry.highlight:Destroy() end
        if entry.billboard then entry.billboard:Destroy() end
        ESP[model] = nil
    end
end

local function ensureEsp(model, name, color)
    local entry = ESP[model]
    if not entry then
        local hl = Instance.new("Highlight")
        hl.Adornee = model
        hl.FillTransparency = 0.7
        hl.OutlineTransparency = 0
        hl.Parent = model

        local bb = Instance.new("BillboardGui")
        bb.Adornee = model:FindFirstChild("Head") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
        bb.Size = UDim2.new(0, 200, 0, 40)
        bb.StudsOffset = Vector3.new(0, 3, 0)
        bb.AlwaysOnTop = true
        bb.Parent = model

        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Size = UDim2.fromScale(1,1)
        label.TextColor3 = Color3.new(1,1,1)
        label.TextStrokeTransparency = 0
        label.Font = Enum.Font.GothamBold
        label.TextScaled = true
        label.Name = "ESPLabel"
        label.Parent = bb

        entry = { highlight = hl, billboard = bb, label = label }
        ESP[model] = entry
    end
    entry.highlight.FillColor    = color
    entry.highlight.OutlineColor = color
    local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
    local txt = name
    if Toggles.ESPDistance.Value and root and getRoot() then
        local d = (root.Position - getRoot().Position).Magnitude
        txt = string.format("%s [%dm]", name, math.floor(d))
    end
    if not Toggles.ESPNames.Value then
        txt = Toggles.ESPDistance.Value and string.format("[%dm]", math.floor((root and getRoot()) and (root.Position - getRoot().Position).Magnitude or 0)) or ""
    end
    entry.label.Text       = txt
    entry.label.TextColor3 = color
end

RunService.Heartbeat:Connect(function()
    -- Players
    local valid = {}
    if Toggles.PlayerESP.Value then
        local color = Options.PlayerESPColor.Value
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character and p.Character:FindFirstChildOfClass("Humanoid") and p.Character:FindFirstChildOfClass("Humanoid").Health > 0 then
                ensureEsp(p.Character, p.Name, color)
                valid[p.Character] = true
            end
        end
    end
    -- Titans
    if Toggles.TitanESP.Value then
        local color = Options.TitanESPColor.Value
        for _, t in ipairs(iterTitans()) do
            ensureEsp(t, t.Name, color)
            valid[t] = true
        end
    end
    -- Cleanup
    for model in pairs(ESP) do
        if not valid[model] or not model.Parent then
            destroyEsp(model)
        end
    end
end)

--------- Nape Visual + Extender ---------
local NapeFX = {} -- nape part -> { highlight, originalSize }

local function clearNapeFX(part)
    local e = NapeFX[part]
    if not e then return end
    if e.highlight and e.highlight.Parent then e.highlight:Destroy() end
    if part and part.Parent and e.originalSize then
        pcall(function() part.Size = e.originalSize end)
    end
    NapeFX[part] = nil
end

RunService.Heartbeat:Connect(function()
    local seen = {}
    if Toggles.NapeVisual.Value or Toggles.NapeExtender.Value then
        for _, t in ipairs(iterTitans()) do
            local nape = getTitanNape(t)
            if nape and nape:IsA("BasePart") then
                seen[nape] = true
                local entry = NapeFX[nape]
                if not entry then
                    entry = { originalSize = nape.Size }
                    NapeFX[nape] = entry
                end
                if Toggles.NapeVisual.Value then
                    if not entry.highlight then
                        local hl = Instance.new("Highlight")
                        hl.Adornee = nape
                        hl.Parent  = nape
                        entry.highlight = hl
                    end
                    entry.highlight.FillColor          = Options.NapeColor.Value
                    entry.highlight.OutlineColor       = Options.NapeColor.Value
                    entry.highlight.FillTransparency   = Options.NapeVisualTransparency.Value
                    entry.highlight.OutlineTransparency= 0
                else
                    if entry.highlight then entry.highlight:Destroy(); entry.highlight = nil end
                end
                if Toggles.NapeExtender.Value then
                    local mul = Options.NapeExtenderSize.Value
                    local target = entry.originalSize * mul
                    if (nape.Size - target).Magnitude > 0.1 then
                        pcall(function() nape.Size = target end)
                    end
                else
                    if (nape.Size - entry.originalSize).Magnitude > 0.1 then
                        pcall(function() nape.Size = entry.originalSize end)
                    end
                end
            end
        end
    end
    for part in pairs(NapeFX) do
        if not seen[part] or not part.Parent then
            clearNapeFX(part)
        end
    end
end)

--------- Auto Kill Titans ---------
-- Discovered formula: POST:FireServer("Attacks", "Slash", true) "unlocks" the
-- server's hit window, then POST:FireServer("Hitboxes", "Register", nape, dmg, mod)
-- damages each titan. Server caps ~9 successful Registers per Slash, so we
-- re-Slash every loop tick. No distance check on Register — we still hover
-- above the current target for safety (titans can grab/hit at close range).
--
-- Death detection: `isTitanDead()` (defined up top) checks if the titan's
-- Humanoid child is gone. The game removes it on kill, so this flips
-- instantly — far more reliable than guessing from State attributes or
-- waiting for the whole model to despawn.

-- Live "Titans: N" label — counts alive (Humanoid-present) titans currently
-- in workspace.Titans. Polled rather than event-driven so it stays accurate
-- even when titans die without their model immediately despawning.
local function countAliveTitans()
    local n = 0
    for _, t in ipairs(iterTitans()) do
        if not isTitanDead(t) then n = n + 1 end
    end
    return n
end

task.spawn(function()
    while not Library.Unloaded do
        if TitanCountLabel and TitanCountLabel.SetText then
            pcall(function() TitanCountLabel:SetText("Titans: " .. countAliveTitans()) end)
        end
        task.wait(0.25)
    end
end)

-- Anti-ban pacing: stretch a wave of kills out to 30-35 sec total so the
-- server never sees suspiciously fast clear times. NO toggle / NO notif —
-- always on, baked into the auto-farm cadence.
--
-- A "session" starts the first tick AutoKill is on with titans alive, and
-- resets when titans hit 0 (between waves) or when AutoKill is toggled off.
-- Within a session: kills-done-so-far must not exceed the linear schedule
-- (elapsed / targetDuration * sessionInitialCount). If it does, we skip
-- firing this tick — the hover loop runs on a separate Heartbeat so the
-- player stays parked above the current target during the pause.
-- New titan spawns mid-session bump sessionInitialCount up so the wave
-- still finishes in roughly the same window.
local PACE_MIN, PACE_MAX = 33, 35
local sessionStart, sessionInitialCount, sessionTargetDuration = nil, 0, 32.5

local function resetPaceSession()
    sessionStart, sessionInitialCount = nil, 0
end

local function shouldPaceWait()
    local alive = countAliveTitans()
    if alive == 0 then
        resetPaceSession()
        return false
    end
    if not sessionStart then
        sessionStart            = tick()
        sessionInitialCount     = alive
        sessionTargetDuration   = PACE_MIN + math.random() * (PACE_MAX - PACE_MIN)
        return false  -- never delay the very first kill
    end
    if alive > sessionInitialCount then
        sessionInitialCount = alive  -- wave grew — extend the schedule
    end
    local elapsed         = tick() - sessionStart
    local killsDone       = sessionInitialCount - alive
    local scheduledByNow  = math.min(1, elapsed / sessionTargetDuration) * sessionInitialCount
    return killsDone >= scheduledByNow  -- true → ahead of schedule, hold off
end

-- Pending registry: titan -> tick of last attack. Used by Multi-hit to spread
-- shots across FRESH titans instead of wasting them all on the same one in
-- back-to-back ticks. Short TTL so a survivor becomes re-attackable quickly.
local pendingAttacks = {}
local PENDING_TTL    = 0.15

local function markAttacked(t) pendingAttacks[t] = tick() end
local function isPending(t)
    local at = pendingAttacks[t]
    return at ~= nil and (tick() - at) < PENDING_TTL
end

task.spawn(function()
    while not Library.Unloaded do
        local now = tick()
        for t, at in pairs(pendingAttacks) do
            if not t.Parent or now - at > PENDING_TTL then
                pendingAttacks[t] = nil
            end
        end
        task.wait(0.2)
    end
end)

local function nearestAliveTitan(skipPending)
    local root = getRoot(); if not root then return nil end
    local best, bestDist = nil, math.huge
    for _, t in ipairs(iterTitans()) do
        if not isTitanDead(t) and not (skipPending and isPending(t)) then
            local nape = getTitanNape(t)
            if nape then
                local d = (nape.Position - root.Position).Magnitude
                if d < bestDist then best, bestDist = t, d end
            end
        end
    end
    return best
end

-- The 3rd arg the real client sends is actually the player's speed (~403 in
-- normal cases). 1000 keeps the server's range check happy. The 5th (0.07)
-- is a small modifier we leave as-is.
local AK_DAMAGE = 1000
local AK_TICK   = 0.01  -- fast single-target cadence

-- Reload coordination: pause ONLY when durability is fully drained AND
-- Auto Reload is on. Otherwise keep slashing at full speed.
local EMPTY_BELOW   = 0.02  -- treat anything below this as "empty"
local REFILLED_ABOVE = 0.20  -- resume slashing once back above this
local function bladeRatio()
    local pg = LocalPlayer:FindFirstChild("PlayerGui"); if not pg then return 1 end
    local iface = pg:FindFirstChild("Interface"); if not iface then return 1 end
    local hud = iface:FindFirstChild("HUD"); if not hud then return 1 end
    local main = hud:FindFirstChild("Main"); if not main then return 1 end
    local top = main:FindFirstChild("Top"); if not top then return 1 end
    local top7 = top:FindFirstChild("7"); if not top7 then return 1 end
    local blades = top7:FindFirstChild("Blades"); if not blades then return 1 end
    local inner = blades:FindFirstChild("Inner"); if not inner then return 1 end
    local bar = inner:FindFirstChild("Bar"); if not bar then return 1 end
    local g = bar:FindFirstChild("Gradient"); if not g then return 1 end
    return g.Offset and g.Offset.X or 1
end

-- Shared between the kill loop (picks target each tick) and the hover loop
-- (positions you every frame). Single source of truth, no double-CFrame.
local currentTarget = nil

-- Hover loop: runs on Heartbeat (every frame) so gravity never gets a chance
-- to pull you down between AutoKill ticks. Also zeroes velocity so a titan
-- swat can't fling you out of position.
RunService.Heartbeat:Connect(function()
    if not Toggles.AutoKill.Value then return end
    if not Toggles.TPAboveTitan.Value then return end
    if not currentTarget or not currentTarget.Parent then return end
    local nape = getTitanNape(currentTarget); if not nape then return end
    local root = getRoot(); if not root then return end
    root.CFrame    = CFrame.new(nape.Position + Vector3.new(0, Options.TPHeight.Value, 0))
    root.Velocity  = Vector3.zero
    root.RotVelocity = Vector3.zero
end)

task.spawn(function()
    while not Library.Unloaded do
        if Toggles.AutoKill.Value then
            -- Drop target the moment its Humanoid is gone (game removes it
            -- on kill) or its nape is missing. Otherwise stay sticky.
            if currentTarget and (isTitanDead(currentTarget) or not getTitanNape(currentTarget)) then
                currentTarget = nil
            end

            if not currentTarget then
                currentTarget = nearestAliveTitan(true) or nearestAliveTitan(false)
            end
            local target = currentTarget

            -- Only pause when truly empty AND Auto Reload is on; otherwise
            -- keep slashing at full cadence so single-target farm stays fast.
            local needPause = Toggles.AutoReload.Value and bladeRatio() < EMPTY_BELOW

            -- Anti-ban pacing: ahead of the 30-35s schedule → skip this tick's
            -- slash but keep target/hover state so the player stays in place.
            local paceHold = shouldPaceWait()

            local POST = getPOST()
            if POST and not needPause and not paceHold then
                -- One Slash unlocks the hit window
                pcall(function() POST:FireServer("Attacks", "Slash", true) end)

                -- Single target: just the current target.
                -- Multi-hit: target + up to N-1 OTHER titans that aren't
                -- already pending from the last few ticks — spreads damage
                -- across fresh victims instead of wasting hits.
                local victims = {}
                if target then
                    victims[#victims + 1] = target
                end
                if Toggles.MultiHit.Value then
                    local cap = Options.MultiHitCount.Value
                    for _, t in ipairs(iterTitans()) do
                        if t ~= target and not isPending(t) and #victims < cap then
                            victims[#victims + 1] = t
                        end
                    end
                end

                for _, t in ipairs(victims) do
                    local nape = getTitanNape(t)
                    if nape then
                        pcall(function()
                            POST:FireServer("Hitboxes", "Register", nape, AK_DAMAGE, 0.07)
                        end)
                        markAttacked(t)  -- pending; kept fresh in the queue spreader
                    end
                end
            end

            if needPause then
                -- Wait for Auto Reload to actually land + the bar to refill.
                -- 3s safety timeout so we never get stuck if reload silently fails.
                local startWait = tick()
                while tick() - startWait < 3 do
                    if bladeRatio() > REFILLED_ABOVE then break end
                    task.wait(0.1)
                end
            else
                task.wait(AK_TICK)
            end
        else
            currentTarget = nil
            resetPaceSession()
            task.wait(0.2)
        end
    end
end)

--------- Utility: GET helper ---------
local function getGET()
    local assets  = RS:FindFirstChild("Assets")
    local remotes = assets and assets:FindFirstChild("Remotes")
    return remotes and remotes:FindFirstChild("GET")
end

--------- Utility: shared UI paths ---------
-- All paths are inside PlayerGui.Interface; resolved each time because the
-- HUD instance can be rebuilt on respawn / mission start.
local function getHUDTop()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local iface = pg and pg:FindFirstChild("Interface")
    local hud = iface and iface:FindFirstChild("HUD")
    local main = hud and hud:FindFirstChild("Main")
    local top = main and main:FindFirstChild("Top")
    return top and top:FindFirstChild("7")
end

local function getBladeGradient()
    local top7 = getHUDTop(); if not top7 then return nil end
    local blades = top7:FindFirstChild("Blades")
    local inner  = blades and blades:FindFirstChild("Inner")
    local bar    = inner and inner:FindFirstChild("Bar")
    return bar and bar:FindFirstChild("Gradient")
end

local function getBladeSetsLabel()
    local top7 = getHUDTop(); if not top7 then return nil end
    local blades = top7:FindFirstChild("Blades")
    return blades and blades:FindFirstChild("Sets")
end

local function getButtonsFrame()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local iface = pg and pg:FindFirstChild("Interface")
    return iface and iface:FindFirstChild("Buttons")
end

local function getRefillPart()
    local u = Workspace:FindFirstChild("Unclimbable")
    local p = u and u:FindFirstChild("Props")
    local h = p and p:FindFirstChild("HQ")
    local g = h and h:FindFirstChild("GasTanks")
    return g and g:FindFirstChild("Refill")
end

--------- Auto Reload (blade durability -> fire Blades/Reload) ---------
-- Gradient.Offset.X is the durability ratio: 0 = empty, 1 = full.
local autoReloadCooldown = 0
task.spawn(function()
    while not Library.Unloaded do
        if Toggles.AutoReload.Value then
            local g = getBladeGradient()
            if g and tick() > autoReloadCooldown then
                local x = g.Offset and g.Offset.X or 1
                if x <= 0.05 then
                    local GET = getGET()
                    if GET then
                        pcall(function() GET:InvokeServer("Blades", "Reload") end)
                        autoReloadCooldown = tick() + 1.5
                    end
                end
            end
        end
        task.wait(0.25)
    end
end)

--------- Auto Refill (sets "0 / N" AND durability empty -> fire Attacks/Reload) ---------
-- Only fires when BOTH conditions hold: no blade sets left AND the current
-- blade's durability is also at 0. Otherwise the player can still get use
-- out of the current blade via a normal reload first.
local autoRefillCooldown = 0
task.spawn(function()
    while not Library.Unloaded do
        if Toggles.AutoRefill.Value then
            local sets = getBladeSetsLabel()
            if sets and tick() > autoRefillCooldown then
                local txt = (sets:IsA("TextLabel") or sets:IsA("TextBox")) and sets.Text or ""
                local current = tonumber((txt:match("^%s*(%d+)") or ""))
                local setsEmpty = current == 0
                local durEmpty  = bladeRatio() < EMPTY_BELOW
                if setsEmpty and durEmpty then
                    local refill = getRefillPart()
                    local POST   = getPOST()
                    if refill and POST then
                        pcall(function() POST:FireServer("Attacks", "Reload", refill) end)
                        autoRefillCooldown = tick() + 2
                    end
                end
            end
        end
        task.wait(0.4)
    end
end)

--------- Auto Escape (button appears in Interface.Buttons -> Slash_Escape) ---------
-- The game shows an escape prompt by inserting a button into Interface.Buttons
-- while a titan is grabbing you. Connection is re-bound when the frame is
-- replaced (e.g., on respawn).
local escapeConn
local function rebindEscape()
    if escapeConn then escapeConn:Disconnect(); escapeConn = nil end
    local frame = getButtonsFrame()
    if not frame then return end
    escapeConn = frame.ChildAdded:Connect(function(child)
        if not Toggles.AutoEscape.Value then return end
        local POST = getPOST()
        if POST then
            pcall(function() POST:FireServer("Attacks", "Slash_Escape") end)
        end
        -- Clear the grab prompt so it doesn't linger / re-trigger.
        pcall(function() child:Destroy() end)
    end)
end
rebindEscape()
LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    rebindEscape()
end)
-- If the Buttons frame itself gets rebuilt, rebind.
task.spawn(function()
    while not Library.Unloaded do
        if not escapeConn or not escapeConn.Connected then rebindEscape() end
        task.wait(2)
    end
end)

--------- Auto Retry (triggers when the Rewards screen shows) ---------
-- Triggers on PlayerGui.Interface.Rewards becoming Visible (death OR mission
-- complete). Instead of firing the Functions/Retry/Add remote directly, we
-- click the in-game Retry button: GuiService focus + VirtualInputManager
-- Enter keypress. Mirrors a real player input, less obvious to anti-cheat.
local GuiService = game:GetService("GuiService")
local VIM        = game:GetService("VirtualInputManager")

local function clickUI(targetButton)
    if not targetButton or not targetButton:IsA("GuiButton") then return end
    local previousFocus = GuiService.SelectedObject
    GuiService.SelectedObject = targetButton
    task.wait()
    VIM:SendKeyEvent(true,  Enum.KeyCode.Return, false, game)
    task.wait()
    VIM:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
end

local function getRewardsFrame()
    local pg    = LocalPlayer:FindFirstChild("PlayerGui")
    local iface = pg and pg:FindFirstChild("Interface")
    return iface and iface:FindFirstChild("Rewards")
end

local function getRetryButton()
    local rewards = getRewardsFrame(); if not rewards then return nil end
    local main    = rewards:FindFirstChild("Main");    if not main    then return nil end
    local info    = main:FindFirstChild("Info");       if not info    then return nil end
    local main2   = info:FindFirstChild("Main");       if not main2   then return nil end
    local buttons = main2:FindFirstChild("Buttons");   if not buttons then return nil end
    return buttons:FindFirstChild("Retry")
end

local autoRetryCooldown = 5
task.spawn(function()
    while not Library.Unloaded do
        if Toggles.AutoRetry.Value and tick() > autoRetryCooldown then
            local r = getRewardsFrame()
            if r and r.Visible then
                autoRetryCooldown = tick() + 5
                task.wait(0.5)
                local btn = getRetryButton()
                if btn then clickUI(btn) end
                local GET = getGET()
                if GET then
                    pcall(function() GET:InvokeServer("Functions", "Retry", "Add") end)
                end
            end
        end
        task.wait(0.3)
    end
end)

--------- Anti-AFK ---------
LocalPlayer.Idled:Connect(function()
    if not Toggles.AntiAFK.Value then return end
    local vu = game:GetService("VirtualUser")
    vu:Button2Down(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
    task.wait(1)
    vu:Button2Up(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
end)

--===========================================================
-- UI Settings tab (menu key, themes, configs)
--===========================================================
local MenuGroup = Tabs["UI Settings"]:AddLeftGroupbox("Menu", "wrench")
MenuGroup:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", {
    Default = "RightControl",
    NoUI    = true,
    Text    = "Menu keybind",
})
MenuGroup:AddButton("Unload", function() Library:Unload() end)

Library.ToggleKeybind = Options.MenuKeybind

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
ThemeManager:SetFolder("777KM")
SaveManager:SetFolder("777KM/AoTR")
SaveManager:BuildConfigSection(Tabs["UI Settings"])
ThemeManager:ApplyToTab(Tabs["UI Settings"])
SaveManager:LoadAutoloadConfig()

--===========================================================
-- Unload cleanup
--===========================================================
Library:OnUnload(function()
    setFullbright(false)
    for m in pairs(ESP)    do destroyEsp(m) end
    for p in pairs(NapeFX) do clearNapeFX(p) end
    if escapeConn then escapeConn:Disconnect() end
    Camera.FieldOfView = 70
end)

Library:Notify({
    Title       = "AoT:R Freemium",
    Description = "Loaded. Press RightControl to toggle.",
    Time        = 4,
})
