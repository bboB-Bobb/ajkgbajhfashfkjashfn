task.wait(5)

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

-- Forward declarations so UI button Funcs registered below can reference
-- helpers that are actually defined further down in FEATURE IMPLEMENTATIONS.
-- The closures capture these locals by reference, so calls at click-time
-- see the assigned function bodies.
local postWebhook
local sendMatchWebhook
local getGold

-- Cache of the most recent S_Rewards table the Actor sniffer captured from
-- the game's own polling. Read by sendMatchWebhook (so we don't have to
-- fire the remote ourselves and lose the race). Written by the bridge
-- handler inside the sniffer section.
local latestRewardsCapture = nil  -- { ts = number, data = table } | nil

-- Built once at script load by requiring RS.Modules.Storage.Perks. Maps
-- perk name -> rarity ("Common"/"Rare"/"Epic"/"Legendary"/"Mythic").
-- Used in the webhook embed so each obtained perk is tagged with rarity.
local PERK_RARITY = {}

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
local GoldLabel      = CombatBox:AddLabel("Gold: ?",   true)

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

-- Lobby JobId captured from Roblox.GameLauncher.joinGameInstance; same
-- placeId/jobId pair the website uses for the AoT:R lobby instance.
MiscBox:AddButton({
    Text = "Return to Lobby",
    Func = function()
        pcall(function()
            game:GetService("TeleportService"):TeleportToPlaceInstance(
                14916516914,
                "a71dbaf1-06bc-4815-9cb2-fddf9ba88ff3",
                LocalPlayer
            )
        end)
    end,
})

MiscBox:AddButton({
    Text = "Check Shadow Banned",
    Func = function()
        local exploiter = LocalPlayer:GetAttribute("Exploiter")
        local blacklist = LocalPlayer:GetAttribute("Blacklist")
        local flagged = exploiter == true or blacklist == true
        if flagged then
            Library:Notify(string.format(
                "SHADOW BANNED — Exploiter=%s Blacklist=%s",
                tostring(exploiter), tostring(blacklist)
            ), 6)
        else
            Library:Notify("Not Shadow Banned — account is good", 4)
        end
    end,
})

local WebhookBox = Tabs.Misc:AddRightGroupbox("Webhook", "send")
WebhookBox:AddToggle("WebhookEnabled", {
    Text    = "Enable Match Webhook",
    Default = false,
    Tooltip = "POST to a Discord webhook every time a match ends (Win/Loss).",
})
WebhookBox:AddInput("WebhookURL", {
    Text        = "Discord URL",
    Default     = "",
    Placeholder = "https://discord.com/api/webhooks/...",
    Tooltip     = "Discord webhook URL. Saved with your config.",
})
WebhookBox:AddButton({
    Text = "Test Webhook",
    Func = function()
        if not postWebhook then
            Library:Notify("postWebhook not ready yet", 3)
            return
        end
        local ok, err = postWebhook({
            content = "AoT:R Freemium - test ping",
            embeds  = {{
                title       = "Test",
                description = "Webhook reachable",
                color       = 0xFFD700,
            }},
        })
        Library:Notify(ok and "Webhook sent" or ("Failed: " .. tostring(err)), 4)
    end,
})

local CreditsBox = Tabs.Misc:AddRightGroupbox("Credits", "heart")
CreditsBox:AddLabel("AoT:R Freemium by 777KM", true)
CreditsBox:AddLabel("UI: Obsidian by deividcomsono", true)

--===========================================================
-- ============== FEATURE IMPLEMENTATIONS ==================
--===========================================================

--------- Webhook HTTP helper ---------
-- Picks whichever request function the user's executor exposes. All major
-- executors (Synapse, Script-Ware, Krnl, AWP, Wave, etc.) expose at least
-- one of these globals.
local httpRequest = (syn and syn.request)
                 or (http and http.request)
                 or (fluxus and fluxus.request)
                 or request
                 or http_request
local HttpService = game:GetService("HttpService")

-- Assigned to the forward-declared `postWebhook` upvalue so the Test button
-- (registered above in the UI section) sees the live function body.
postWebhook = function(payload)
    if not httpRequest then return false, "no request function" end
    local url = Options.WebhookURL and Options.WebhookURL.Value
    if not url or url == "" then return false, "no URL" end
    local ok, resp = pcall(httpRequest, {
        Url     = url,
        Method  = "POST",
        Headers = { ["Content-Type"] = "application/json" },
        Body    = HttpService:JSONEncode(payload),
    })
    if not ok then return false, tostring(resp) end
    -- Discord returns 204 No Content on success; treat 2xx as ok.
    local status = (type(resp) == "table") and (resp.StatusCode or resp.Status) or nil
    if status and (status < 200 or status >= 300) then
        return false, "HTTP " .. tostring(status)
    end
    return true
end

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

--------- Money read (lobby UI label; nil during matches) ---------
-- Hardcoded PlayerGui path is filled in once the user runs the "Spy Money
-- Path" debug button in the lobby and pastes the result back. Until then,
-- the label and webhook show "?". `lastKnownGold` caches the most recent
-- read so the webhook still carries a value even after the lobby UI tears
-- down at match start (the label inside the lobby panel is unparented mid-
-- match in many Roblox games).
local cachedGoldLabel = nil
local lastKnownGold   = nil

-- Edit this list once you know the real path. Each entry is a function that
-- walks PlayerGui from a likely starting point and returns a TextLabel/TextBox.
-- The first one that resolves wins. Add the real path on top.
local moneyPathCandidates = {
    -- Primary: Topbar currency display (persistent across lobby + mission).
    -- Confirmed via Spy Lobby UI 2026-05-26.
    function()
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        local iface = pg and pg:FindFirstChild("Interface")
        local top = iface and iface:FindFirstChild("Topbar")
        local main = top and top:FindFirstChild("Main")
        local cur = main and main:FindFirstChild("Currencies")
        local gold = cur and cur:FindFirstChild("Gold")
        return gold and gold:FindFirstChild("Amount")
    end,
    -- Fallback: in-mission HUD top panel (often 0 mid-mission, but kept
    -- in case the topbar gets hidden in some game state).
    function()
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        local iface = pg and pg:FindFirstChild("Interface")
        local hud = iface and iface:FindFirstChild("HUD")
        local main = hud and hud:FindFirstChild("Main")
        local top = main and main:FindFirstChild("Top")
        local two = top and top:FindFirstChild("2")
        local gold = two and two:FindFirstChild("Gold")
        return gold and gold:FindFirstChild("Title")
    end,
}

-- Gems mirror — same Topbar.Currencies path, sibling of Gold.
local cachedGemsLabel = nil
local lastKnownGems   = nil
local function resolveGemsLabel()
    if cachedGemsLabel and cachedGemsLabel.Parent then return cachedGemsLabel end
    cachedGemsLabel = nil
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local iface = pg and pg:FindFirstChild("Interface")
    local top = iface and iface:FindFirstChild("Topbar")
    local main = top and top:FindFirstChild("Main")
    local cur = main and main:FindFirstChild("Currencies")
    local gems = cur and cur:FindFirstChild("Gems")
    cachedGemsLabel = gems and gems:FindFirstChild("Amount")
    return cachedGemsLabel
end

local function getGems()
    local lbl = resolveGemsLabel()
    if not lbl then return lastKnownGems end
    local cleaned = ((lbl.Text or ""):gsub("[^%d]", ""))
    local n = tonumber(cleaned)
    if n then lastKnownGems = n end
    return lastKnownGems
end
LocalPlayer.CharacterAdded:Connect(function() cachedGemsLabel = nil end)

local function resolveGoldLabel()
    if cachedGoldLabel and cachedGoldLabel.Parent then return cachedGoldLabel end
    cachedGoldLabel = nil
    for _, fn in ipairs(moneyPathCandidates) do
        local ok, result = pcall(fn)
        if ok and result and (result:IsA("TextLabel") or result:IsA("TextBox")) then
            cachedGoldLabel = result
            return result
        end
    end
    return nil
end

getGold = function()
    local lbl = resolveGoldLabel()
    if not lbl then return lastKnownGold end
    -- gsub returns (string, count); wrap in parens to keep only the string,
    -- otherwise tonumber sees count as the base arg and errors.
    local cleaned = ((lbl.Text or ""):gsub("[^%d]", ""))
    local n = tonumber(cleaned)
    if n then lastKnownGold = n end
    return lastKnownGold
end

task.spawn(function()
    while not Library.Unloaded do
        if GoldLabel and GoldLabel.SetText then
            local m = getGold()
            local txt = m and ("Gold: " .. tostring(m)) or "Gold: ?"
            pcall(function() GoldLabel:SetText(txt) end)
        end
        task.wait(0.5)
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

-- Use the game's own mission timer (workspace.Seconds attribute) instead of
-- the client's tick() — it's the same clock the server compares against for
-- anti-cheat heuristics, so pacing against it is what actually matters.
-- Falls back to tick() in lobby / between missions when the attribute is unset.
local function gameTime()
    local s = Workspace:GetAttribute("Seconds")
    if type(s) == "number" then return s end
    return tick()
end

local function resetPaceSession()
    sessionStart, sessionInitialCount = nil, 0
end

local function shouldPaceWait()
    local alive = countAliveTitans()
    if alive == 0 then
        resetPaceSession()
        return false
    end
    local now = gameTime()
    if not sessionStart then
        sessionStart            = now
        sessionInitialCount     = alive
        sessionTargetDuration   = PACE_MIN + math.random() * (PACE_MAX - PACE_MIN)
        return false  -- never delay the very first kill
    end
    -- workspace.Seconds resets between missions. If it jumped backwards,
    -- treat it as a new mission and reseed the session.
    if now < sessionStart then
        sessionStart        = now
        sessionInitialCount = alive
        return false
    end
    if alive > sessionInitialCount then
        sessionInitialCount = alive  -- wave grew — extend the schedule
    end
    local elapsed         = now - sessionStart
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

-- Set true while Auto Refill is TP'd to HQ and waiting for the refill to
-- land. Pauses Slash spam (which would block the refill remote server-side)
-- AND the hover loop (which would yank the player back above the titan
-- before the refill remote was accepted).
local refillingNow = false

-- Set true while the Rewards frame is visible (mission end / death). All the
-- gameplay loops (AutoKill, AutoReload, AutoRefill, AutoEscape) check this
-- and bail so their remote spam doesn't race the AutoRetry click + remote
-- and get them server-dropped. Cleared when Rewards goes invisible.
local mutedForRetry = false

-- Hover loop: runs on Heartbeat (every frame) so gravity never gets a chance
-- to pull you down between AutoKill ticks. Also zeroes velocity so a titan
-- swat can't fling you out of position.
RunService.Heartbeat:Connect(function()
    if not Toggles.AutoKill.Value then return end
    if mutedForRetry then return end
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
        if Toggles.AutoKill.Value and not mutedForRetry then
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
            if POST and not needPause and not paceHold and not refillingNow then
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

--------- Perk rarity LUT (built once from RS.Modules.Storage.Perks) ---------
-- Perks module shape (confirmed via Dump Perks + Stats):
--   { Common={Focus={Stats=..,Type=..}, Lightweight={...}, ...},
--     Rare={...}, Epic={...}, Legendary={...}, Mythic={...},
--     Check=fn, Setup=fn, Get_Converted_Stat=fn }
-- Walk each rarity bucket's keys to build a flat perkName -> rarity map.
do
    local ok, perksMod = pcall(function()
        return require(RS:WaitForChild("Modules"):WaitForChild("Storage"):WaitForChild("Perks"))
    end)
    if ok and type(perksMod) == "table" then
        for _, rarity in ipairs({ "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }) do
            local bucket = perksMod[rarity]
            if type(bucket) == "table" then
                for perkName, _ in pairs(bucket) do
                    if type(perkName) == "string" then
                        PERK_RARITY[perkName] = rarity
                    end
                end
            end
        end
    end
end

local function formatPerkWithRarity(name)
    local r = PERK_RARITY[name]
    return r and string.format("%s [%s]", name, r) or tostring(name)
end

--------- Path A: S_Rewards Actor-side passive sniffer ---------
-- Our main-thread GET("S_Rewards","Get",...) calls come back nil. The game's
-- own client script fires the same remote and presumably gets real data.
-- We can't change that from the main thread — but we CAN inject a hook into
-- each gameplay Actor that intercepts the actor's S_Rewards InvokeServer
-- calls, captures the return value, and bridges it to the main thread for
-- logging. Same per-actor injection pattern AOTR Spy.lua uses for namecall.
local SNIFF_BRIDGE = "AOTR_RewardsSniffer_777KM"
do
    local CoreGui = game:GetService("CoreGui")
    local existing = CoreGui:FindFirstChild(SNIFF_BRIDGE)
    if existing then existing:Destroy() end
    local b = Instance.new("BindableEvent")
    b.Name   = SNIFF_BRIDGE
    b.Parent = CoreGui
    local function deepPrint(t, indent, seen)
        indent = indent or "   "
        seen = seen or {}
        if seen[t] then print(indent .. "<cyclic>") return end
        seen[t] = true
        for k, v in pairs(t) do
            if type(v) == "table" then
                print(indent .. tostring(k) .. " = {")
                deepPrint(v, indent .. "    ", seen)
                print(indent .. "}")
            else
                print(indent .. tostring(k) .. " = " .. tostring(v) .. "  (" .. type(v) .. ")")
            end
        end
    end
    b.Event:Connect(function(data)
        if type(data) ~= "table" then return end
        print(string.format("[Sniff S_Rewards] action=%s arg3=%s returnType=%s",
            tostring(data.action), tostring(data.arg3), type(data.result)))
        if type(data.result) == "table" then
            deepPrint(data.result)
            -- Cache the latest non-nil capture for the webhook so we don't
            -- have to race the game's own polling loop. The game drains the
            -- data on its first successful Get; subsequent main-thread calls
            -- (ours) get nil. By listening passively we always have the real
            -- table without firing anything ourselves.
            latestRewardsCapture = { ts = tick(), data = data.result }
        else
            print("   value =", tostring(data.result))
        end
    end)
end

local sniffHookSrc = ([[
    local CoreGui = game:GetService("CoreGui")
    local bridge  = CoreGui:WaitForChild(%q, 10)
    if not bridge then return end

    local RS  = game:GetService("ReplicatedStorage")
    local GET = RS:WaitForChild("Assets"):WaitForChild("Remotes"):WaitForChild("GET")

    local SETID = setthreadidentity or setidentity
    local GETID = getthreadidentity or getidentity

    local old
    local hookFn = function(self, ...)
        -- pack everything once so we can reuse below without `...` leaking
        -- into a nested non-vararg function (that's a Lua parse error).
        local args = table.pack(...)

        local interesting = false
        if self == GET then
            local okC, isExecutor = pcall(checkcaller)
            local okM, m = pcall(getnamecallmethod)
            if okC and not isExecutor and okM and m == "InvokeServer" and args[1] == "S_Rewards" then
                interesting = true
            end
        end

        -- Call original with identity elevation (game scripts hold identity 8;
        -- our executor thread is lower and downstream Instance access fails).
        local results
        if SETID then
            local saved = GETID and GETID() or nil
            pcall(SETID, 8)
            results = table.pack(pcall(old, self, ...))
            if saved then pcall(SETID, saved) end
        else
            results = table.pack(pcall(old, self, ...))
        end

        if not results[1] then
            error(results[2], 2)
        end

        if interesting then
            local returnVal = results[2]
            pcall(function()
                bridge:Fire({
                    service = args[1],
                    action  = args[2],
                    arg3    = args[3],
                    result  = returnVal,
                })
            end)
        end

        return table.unpack(results, 2, results.n)
    end
    old = hookmetamethod(game, "__namecall", newcclosure(hookFn))
]]):format(SNIFF_BRIDGE)

local function injectSniffer()
    if not (getactors and run_on_actor) then return end
    local ok, actors = pcall(getactors)
    if not ok or type(actors) ~= "table" then return end
    for _, actor in ipairs(actors) do
        pcall(run_on_actor, actor, sniffHookSrc)
    end
end
injectSniffer()
LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    injectSniffer()
end)
game.DescendantAdded:Connect(function(d)
    if d:IsA("Actor") and run_on_actor then
        task.wait(0.3)
        pcall(run_on_actor, d, sniffHookSrc)
    end
end)

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

-- Each map has its own GasTanks assembly under a different parent (lobby:
-- Unclimbable.Props.HQ.GasTanks ; current map: Climbable._Walls.Gate.GasTanks ;
-- other maps likely elsewhere). Instead of hardcoding per-map paths, locate
-- any container named "GasTanks" in workspace and grab its Refill child.
-- Cached because GetDescendants on the world is expensive — invalidated
-- when the cached part loses its parent (map change / respawn).
local cachedRefill = nil
local function getRefillPart()
    if cachedRefill and cachedRefill.Parent then return cachedRefill end
    cachedRefill = nil
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d.Name == "GasTanks" then
            local r = d:FindFirstChild("Refill")
            if r and r:IsA("BasePart") then
                cachedRefill = r
                return r
            end
        end
    end
    return nil
end
LocalPlayer.CharacterAdded:Connect(function() cachedRefill = nil end)

--------- Auto Reload (blade durability -> fire Blades/Reload) ---------
-- Gradient.Offset.X is the durability ratio: 0 = empty, 1 = full.
local autoReloadCooldown = 0
task.spawn(function()
    while not Library.Unloaded do
        if Toggles.AutoReload.Value and not refillingNow and not mutedForRetry then
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
-- blade's durability is also at 0. The refill remote has a server-side
-- proximity check on the HQ refill part, so we TP the player there and
-- raise `refillingNow` to mute the Slash spam + hover loop while waiting
-- for the refill to land. Restores the player's original position after.
local function readSetsCount()
    local sets = getBladeSetsLabel(); if not sets then return nil end
    -- "Sets" might be the TextLabel itself OR a frame containing one,
    -- depending on whether the HUD got re-themed. Handle both.
    local txt
    if sets:IsA("TextLabel") or sets:IsA("TextBox") then
        txt = sets.Text
    else
        for _, c in ipairs(sets:GetDescendants()) do
            if (c:IsA("TextLabel") or c:IsA("TextBox")) and c.Text:find("%d") then
                txt = c.Text
                break
            end
        end
    end
    if not txt then return nil end
    return tonumber(txt:match("(%d+)"))
end

local autoRefillCooldown = 0

-- Fire the refill remote directly with the dynamically-found Refill part.
-- No TP needed — the server doesn't proximity-check, it just needs the
-- attack window from the last Slash to be clear (the 1s pause handles
-- that via refillingNow muting the kill + reload loops).
local function doRefillRoutine()
    if refillingNow then return false end
    local refill = getRefillPart()
    local POST   = getPOST()
    if not (refill and POST) then
        warn(string.format("[Refill] missing piece: refill=%s POST=%s",
            tostring(refill), tostring(POST)))
        return false
    end
    refillingNow = true
    task.wait(1)  -- let any in-flight Slash attack window expire
    pcall(function() POST:FireServer("Attacks", "Reload", refill) end)
    -- Wait for sets to recover (or 3s safety timeout).
    local startWait = tick()
    while tick() - startWait < 3 do
        local n = readSetsCount()
        if n and n > 0 then break end
        task.wait(0.1)
    end
    refillingNow = false
    autoRefillCooldown = tick() + 2
    return true
end

task.spawn(function()
    while not Library.Unloaded do
        if Toggles.AutoRefill.Value and not refillingNow and not mutedForRetry and tick() > autoRefillCooldown then
            local current = readSetsCount()
            local setsEmpty = current == 0
            local durEmpty  = bladeRatio() < EMPTY_BELOW
            if setsEmpty and durEmpty then
                doRefillRoutine()
            end
        end
        task.wait(0.4)
    end
end)

UtilBox:AddButton({
    Text = "Refill Now",
    Func = function()
        task.spawn(doRefillRoutine)
    end,
})

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
        if mutedForRetry then return end
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

-- 5s cooldown on first execution so the script doesn't auto-retry the
-- instant it loads (e.g., if a Rewards frame is already visible).
-- When Rewards is visible we raise `mutedForRetry` so AutoKill / AutoReload
-- / AutoRefill / AutoEscape all bail for a tick — their concurrent remote
-- spam was racing the Retry click + remote and getting it server-dropped.
-- Flag clears the instant Rewards goes invisible (success) or AutoRetry
-- is toggled off, so the gameplay loops resume immediately.
local autoRetryCooldown = tick() + 5
task.spawn(function()
    while not Library.Unloaded do
        local r       = getRewardsFrame()
        local visible = r and r.Visible

        if Toggles.AutoRetry.Value and visible then
            if not mutedForRetry then
                mutedForRetry = true
                -- One tick for the gameplay loops to notice and bail out
                -- before we click — otherwise an in-flight Slash can still
                -- be queued the instant the Rewards frame appears.
                task.wait(0.4)
            end
            if tick() > autoRetryCooldown then
                -- 2s cooldown so we re-fire if the first click/remote
                -- silently failed; the Rewards frame turning invisible
                -- naturally stops the loop on success.
                autoRetryCooldown = tick() + 2
                task.wait(0.5)
                local btn = getRetryButton()
                if btn then clickUI(btn) end
                local GET = getGET()
                if GET then
                    pcall(function() GET:InvokeServer("Functions", "Retry", "Add") end)
                end
            end
        else
            if mutedForRetry then mutedForRetry = false end
        end
        task.wait(0.3)
    end
end)

--------- Match-end webhook (edge-triggered on Rewards.Visible) ---------
-- Independent of AutoRetry: fires on every match end whether or not AutoRetry
-- is enabled. Primary data source is the remote GET("S_Rewards","Get","Match"),
-- which returns the full mission summary as a structured table — confirmed via
-- the actor sniffer + dump button on 2026-05-26.
-- Shape:
--   { Completed, Seconds, Claimed,
--     Stats    = { Damage, Kills, Crits, Boss_Damage },
--     Obtained = { Gold, XP, Silver, BP_XP, Shards, Gems, Canes,
--                  Perks={...}, Drops={...}, Chests={...} } }
-- "Get All" returns identical data. "Get true/false/nil/plr/name/Last/Current"
-- all return nil for us — server appears to whitelist specific action strings.

-- Returns the latest S_Rewards table captured by the Actor sniffer. Cache
-- lifecycle is tied to the match: cleared when Rewards.Visible flips off
-- (new match starting), so a non-nil entry always belongs to the current
-- match. NEVER fires `("Get", true)` ourselves — that's what the game
-- polls; calling it would either lose the race (we get nil) or worse,
-- drain the buffer before the game does, blanking the in-game Rewards UI.
local function fetchRewardsRemote()
    if latestRewardsCapture and type(latestRewardsCapture.data) == "table" then
        return latestRewardsCapture.data
    end
    -- Last-resort active fallback if the sniffer didn't fire (e.g., executor
    -- without getactors/run_on_actor). Skip arg3=true (the game's slot).
    local GET = getGET(); if not GET then return nil end
    for _, arg in ipairs({ LocalPlayer, "Last", "Match", "All" }) do
        local ok, r = pcall(GET.InvokeServer, GET, "S_Rewards", "Get", arg)
        if ok and type(r) == "table" then return r end
    end
    return nil
end

local function fmtSeconds(s)
    s = tonumber(s); if not s then return "?" end
    local m = math.floor(s / 60)
    local r = s % 60
    return string.format("%02d:%02d", m, r)
end

sendMatchWebhook = function(matchNum)
    local data  = fetchRewardsRemote()
    local money = getGold()
    local gems  = getGems()
    local level   = LocalPlayer:GetAttribute("Level")
    local streak  = LocalPlayer:GetAttribute("Streak")
    local title   = LocalPlayer:GetAttribute("Title")

    local win, fields
    if data then
        -- Trust the remote completely; it's authoritative server-side data.
        win = data.Completed == true
        local s = data.Stats    or {}
        local o = data.Obtained or {}

        local function fmt(v)
            if v == nil then return "0" end
            if type(v) == "number" then return tostring(v) end
            return tostring(v)
        end

        fields = {}
        fields[#fields + 1] = {
            name   = "Match",
            value  = string.format("#%d  -  %s", matchNum, win and "WIN" or "LOSS"),
            inline = false,
        }
        fields[#fields + 1] = {
            name   = "Time",
            value  = fmtSeconds(data.Seconds),
            inline = true,
        }
        fields[#fields + 1] = {
            name   = "Player",
            value  = string.format("Level: %s\nStreak: %s\n%s",
                tostring(level or "?"), tostring(streak or "?"),
                title and ("Title: " .. tostring(title)) or ""),
            inline = true,
        }
        fields[#fields + 1] = {
            name   = "Total",
            value  = string.format("Gold: %s\nGems: %s",
                money and tostring(money) or "?",
                gems and tostring(gems) or "?"),
            inline = true,
        }
        fields[#fields + 1] = {
            name   = "Stats",
            value  = string.format(
                "Damage: %s\nKills: %s\nCrits: %s\nBoss DMG: %s",
                fmt(s.Damage), fmt(s.Kills), fmt(s.Crits), fmt(s.Boss_Damage)
            ),
            inline = false,
        }
        -- Currencies/items. Show only non-zero numerics so the embed stays clean.
        local obtainedLines = {}
        local order = { "XP", "Gold", "Silver", "Gems", "Shards", "BP_XP", "Canes" }
        for _, k in ipairs(order) do
            local v = o[k]
            if type(v) == "number" and v > 0 then
                obtainedLines[#obtainedLines + 1] = string.format("%s: %s", k, tostring(v))
            end
        end
        -- Perks (string list) — tag each with rarity via PERK_RARITY LUT
        if type(o.Perks) == "table" and #o.Perks > 0 then
            local tagged = {}
            for _, p in ipairs(o.Perks) do
                tagged[#tagged + 1] = formatPerkWithRarity(p)
            end
            obtainedLines[#obtainedLines + 1] = "Perks: " .. table.concat(tagged, ", ")
        end
        -- Drops / Chests (only if populated; empty tables hidden)
        for _, k in ipairs({ "Drops", "Chests" }) do
            local t = o[k]
            if type(t) == "table" and next(t) then
                local parts = {}
                for kk, vv in pairs(t) do
                    parts[#parts + 1] = tostring(kk) .. "=" .. tostring(vv)
                end
                obtainedLines[#obtainedLines + 1] = k .. ": " .. table.concat(parts, ", ")
            end
        end
        if #obtainedLines > 0 then
            fields[#fields + 1] = {
                name   = "Obtained",
                value  = table.concat(obtainedLines, "\n"),
                inline = false,
            }
        end
    else
        -- Remote was nil — likely the sniffer hasn't installed (executor
        -- without getactors/run_on_actor). Send a minimal embed so the
        -- user still sees the match.
        win = false
        fields = {
            { name = "Match", value = string.format("#%d", matchNum), inline = false },
            { name = "Status", value = "S_Rewards capture missing — Actor sniffer may not be installed.", inline = false },
            { name = "Player", value = string.format("Level: %s\nStreak: %s",
                tostring(level or "?"), tostring(streak or "?")), inline = true },
            { name = "Total", value = string.format("Gold: %s\nGems: %s",
                money and tostring(money) or "?",
                gems and tostring(gems) or "?"), inline = true },
        }
    end

    local payload = {
        username = "AoT:R Freemium",
        embeds   = {{
            title  = win and "Mission Completed" or "Mission Failed",
            color  = win and 0x57F287 or 0xED4245,
            fields = fields,
        }},
    }

    local ok, err = postWebhook(payload)
    if not ok then warn("[Webhook] " .. tostring(err)) end
end

local matchCount         = 0
local lastRewardsVisible = false
task.spawn(function()
    while not Library.Unloaded do
        local r = getRewardsFrame()
        local v = (r and r.Visible) or false
        if v ~= lastRewardsVisible then
            if v then
                -- Match just ended (Rewards visible — works for win + death).
                -- One task per match handles BOTH gold/gems accumulation
                -- (always) AND the webhook send (if enabled). Doing the
                -- accumulation before the webhook fires guarantees the
                -- embed sees the updated Total values, no race.
                matchCount = matchCount + 1
                local n = matchCount
                task.spawn(function()
                    -- Wait for sniffer capture (up to 6s after match end)
                    local waited = 0
                    while waited < 6 do
                        if latestRewardsCapture
                           and type(latestRewardsCapture.data) == "table" then
                            break
                        end
                        task.wait(0.25)
                        waited = waited + 0.25
                    end

                    -- Accumulate Gold/Gems onto the lobby-seeded cache so
                    -- mid-session values stay fresh until next lobby visit
                    -- corrects any drift. Skip if no lobby baseline yet
                    -- (cache stays nil → embed shows "?" honestly).
                    if latestRewardsCapture
                       and type(latestRewardsCapture.data) == "table" then
                        local o = latestRewardsCapture.data.Obtained
                        if type(o) == "table" then
                            if type(o.Gold) == "number" and lastKnownGold then
                                lastKnownGold = lastKnownGold + o.Gold
                            end
                            if type(o.Gems) == "number" and lastKnownGems then
                                lastKnownGems = lastKnownGems + o.Gems
                            end
                        end
                    end

                    if Toggles.WebhookEnabled and Toggles.WebhookEnabled.Value then
                        sendMatchWebhook(n)
                    end
                end)
            else
                -- Rewards screen closed (new mission starting) — drop the
                -- cache so next match's webhook can't accidentally reuse it.
                latestRewardsCapture = nil
            end
        end
        lastRewardsVisible = v
        task.wait(0.3)
    end
end)

--------- Debug helpers (one-shot discovery) ---------
-- Path B: try every plausible arg shape against S_Rewards. If any variant
-- returns a non-nil value, we've found the calling convention the game
-- itself uses. Pair with the Actor sniffer (Path A) installed above —
-- the sniffer logs whatever the game's own call gets back, so we can
-- compare against our variants.
UtilBox:AddButton({
    Text = "Dump S_Rewards",
    Func = function()
        local GET = getGET()
        if not GET then warn("[Dump] no GET remote") return end

        local function dumpTable(t, indent, seen)
            indent = indent or "   "
            seen = seen or {}
            if seen[t] then print(indent .. "<cyclic>") return end
            seen[t] = true
            for k, v in pairs(t) do
                if type(v) == "table" then
                    print(indent .. tostring(k) .. " = {")
                    dumpTable(v, indent .. "    ", seen)
                    print(indent .. "}")
                else
                    print(indent .. tostring(k) .. " = " .. tostring(v) .. "  (" .. type(v) .. ")")
                end
            end
        end

        local function try(label, ...)
            local ok, r = pcall(GET.InvokeServer, GET, ...)
            print(string.format("[S_Rewards %-14s] ok=%s type=%s value=%s",
                label, tostring(ok), type(r), tostring(r)))
            if type(r) == "table" then dumpTable(r) end
        end

        try("Get true",      "S_Rewards", "Get", true)
        try("Get false",     "S_Rewards", "Get", false)
        try("Get nil",       "S_Rewards", "Get")
        try("Get plr",       "S_Rewards", "Get", LocalPlayer)
        try("Get name",      "S_Rewards", "Get", LocalPlayer.Name)
        try("Get Last",      "S_Rewards", "Get", "Last")
        try("Get Current",   "S_Rewards", "Get", "Current")
        try("Get Match",     "S_Rewards", "Get", "Match")
        try("Get All",       "S_Rewards", "Get", "All")
        try("Last",          "S_Rewards", "Last")
        try("Current",       "S_Rewards", "Current")
        try("Fetch",         "S_Rewards", "Fetch")
        try("Claim",         "S_Rewards", "Claim")

        Library:Notify("S_Rewards dump in console", 3)
    end,
})

UtilBox:AddButton({
    Text = "Spy Money Path",
    Func = function()
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if not pg then warn("[Spy] no PlayerGui") return end
        local count = 0
        for _, d in ipairs(pg:GetDescendants()) do
            if (d:IsA("TextLabel") or d:IsA("TextBox")) then
                local t = d.Text or ""
                -- Money labels are typically pure digits with optional commas
                -- and sometimes a "$" / "K" / "M" suffix.
                if t:match("^[%d,]+$") or t:match("^%$?[%d,]+[KM]?$") then
                    count = count + 1
                    print(string.format("[Money?] %s = %q", d:GetFullName(), t))
                end
            end
        end
        Library:Notify(string.format("Spy: %d candidate labels in console", count), 4)
    end,
})

UtilBox:AddButton({
    Text = "Probe Stats.Get",
    Func = function()
        local ok, statsMod = pcall(function()
            return require(RS.Modules.Utilities.Stats)
        end)
        if not ok or type(statsMod) ~= "table" or type(statsMod.Get) ~= "function" then
            warn("[Probe] Stats.Get not available:", statsMod)
            return
        end

        local function try(label, ...)
            local oks, r = pcall(statsMod.Get, ...)
            print(string.format("[Stats.Get(%s)] ok=%s type=%s value=%s",
                label, tostring(oks), type(r), tostring(r)))
            if type(r) == "table" then
                for k, v in pairs(r) do
                    print(string.format("    %s = %s  (%s)", tostring(k), tostring(v), type(v)))
                end
            end
        end

        try("(no args)")
        try("LocalPlayer", LocalPlayer)
        try("'Gold'", "Gold")
        try("'Gems'", "Gems")
        try("'Level'", "Level")
        try("'Prestige'", "Prestige")
        try("'Currency'", "Currency")
        try("'All'", "All")
        try("LP,'Gold'", LocalPlayer, "Gold")
        try("LP,'All'", LocalPlayer, "All")
        try("LP.Name,'Gold'", LocalPlayer.Name, "Gold")

        Library:Notify("Stats.Get probe done — check console", 4)
    end,
})

UtilBox:AddButton({
    Text = "Spy Lobby UI",
    Func = function()
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if not pg then warn("[Spy] no PlayerGui") return end
        print("\n========== LOBBY UI SCAN ==========\n")
        local hits = 0
        local keywords = { "gold", "gem", "level", "prestige", "money", "currency",
                           "candy", "shard", "cash", "balance", "coin", "stat" }
        for _, d in ipairs(pg:GetDescendants()) do
            if d:IsA("TextLabel") or d:IsA("TextBox") then
                local fp = d:GetFullName():lower()
                local matched = false
                for _, kw in ipairs(keywords) do
                    -- match either in the path (folder/label name) OR digit-only text
                    if fp:find(kw) then matched = true break end
                end
                if matched then
                    local parentName = d.Parent and d.Parent.Name or "?"
                    print(string.format("  %s  parent=%s  text=%q",
                        d:GetFullName(), parentName, d.Text or ""))
                    hits = hits + 1
                end
            end
        end
        print(string.format("\n========== %d matches ==========\n", hits))
        Library:Notify(string.format("Lobby UI: %d candidates in console", hits), 4)
    end,
})

UtilBox:AddButton({
    Text = "Dump Perks + Stats",
    Func = function()
        local function deep(t, indent, seen, depthLimit, depth)
            indent = indent or "  "
            seen = seen or {}
            depthLimit = depthLimit or 4
            depth = depth or 0
            if seen[t] then print(indent .. "<cyclic>") return end
            if depth > depthLimit then print(indent .. "<max depth>") return end
            seen[t] = true
            for k, v in pairs(t) do
                if type(v) == "table" then
                    print(indent .. tostring(k) .. " = {")
                    deep(v, indent .. "  ", seen, depthLimit, depth + 1)
                    print(indent .. "}")
                elseif type(v) == "function" then
                    print(indent .. tostring(k) .. " = <fn>")
                else
                    print(indent .. tostring(k) .. " = " .. tostring(v) .. "  (" .. type(v) .. ")")
                end
            end
        end

        local function tryRequire(path)
            local node = RS
            for _, seg in ipairs(path) do
                node = node and node:FindFirstChild(seg)
            end
            if not node then return nil, "path not found" end
            local ok, m = pcall(require, node)
            if not ok then return nil, m end
            return m
        end

        print("\n=========== PERKS MODULE ===========")
        local perks, err = tryRequire({"Modules", "Storage", "Perks"})
        if perks then deep(perks) else print("ERR:", err) end

        print("\n=========== STATS MODULE ===========")
        local stats, err2 = tryRequire({"Modules", "Utilities", "Stats"})
        if stats then deep(stats, "  ", nil, 3) else print("ERR:", err2) end

        Library:Notify("Perks + Stats dumped to console", 4)
    end,
})

UtilBox:AddButton({
    Text = "Discover Profile",
    Func = function()
        print("\n========== PROFILE DISCOVERY ==========\n")

        -- 1) LocalPlayer attributes (likely place for Gold/Gems/Level/Prestige)
        print("[LocalPlayer Attributes]")
        local attrCount = 0
        for k, v in pairs(LocalPlayer:GetAttributes()) do
            print(string.format("  %s = %s  (%s)", tostring(k), tostring(v), type(v)))
            attrCount = attrCount + 1
        end
        if attrCount == 0 then print("  (none)") end

        -- 2) LocalPlayer children (Data folders / leaderstats / Configuration / Profile)
        print("\n[LocalPlayer Children]")
        for _, c in ipairs(LocalPlayer:GetChildren()) do
            print(string.format("  %s: %s", c.ClassName, c.Name))
            if c:IsA("Folder") or c:IsA("Configuration") then
                for _, cc in ipairs(c:GetDescendants()) do
                    local val = ""
                    if cc:IsA("ValueBase") then val = " = " .. tostring(cc.Value) end
                    print(string.format("    %s: %s%s", cc.ClassName, cc.Name, val))
                end
            end
        end

        -- 3) Profile-style remote probes (try every plausible service+action combo)
        local GET = getGET()
        if GET then
            print("\n[Profile Remote Probes — non-nil hits only]")
            local services = {
                "S_Player", "S_Profile", "S_Data", "S_Currency", "S_Stats",
                "S_Account", "S_Inventory", "S_Save", "S_Save_Profile", "Profile",
                "Player", "Data", "Currency",
            }
            local actions  = { "Get", "Load", "Profile", "Stats", "Data", "Fetch", "All", "Read" }
            local hits = 0
            for _, svc in ipairs(services) do
                for _, act in ipairs(actions) do
                    local ok, r = pcall(GET.InvokeServer, GET, svc, act)
                    if ok and r ~= nil then
                        hits = hits + 1
                        print(string.format("  [%s/%s] type=%s value=%s", svc, act, type(r), tostring(r)))
                        if type(r) == "table" then
                            for k, v in pairs(r) do
                                print(string.format("    %s = %s  (%s)", tostring(k), tostring(v), type(v)))
                            end
                        end
                    end
                end
            end
            if hits == 0 then print("  (no non-nil returns from any combo)") end
        end

        -- 4) ReplicatedStorage scan for Perk / Item rarity LUT modules
        print("\n[RS Modules — perk/rarity/item/profile candidates]")
        local moduleCandidates = {}
        for _, d in ipairs(RS:GetDescendants()) do
            local n = d.Name:lower()
            if d:IsA("ModuleScript") and
               (n:find("perk") or n:find("rarity") or n:find("item")
                or n:find("currenc") or n:find("profile") or n:find("data")
                or n:find("save") or n:find("player") or n:find("stat")
                or n:find("gold") or n:find("gem")) then
                print("  ", d:GetFullName())
                moduleCandidates[#moduleCandidates + 1] = d
            end
        end
        if #moduleCandidates == 0 then print("  (no matches)") end

        -- 5) Try require()ing each candidate module and dump top-level keys
        print("\n[Module Requires — top-level keys]")
        for _, mod in ipairs(moduleCandidates) do
            local ok, val = pcall(require, mod)
            if ok and type(val) == "table" then
                local keyCount, sample = 0, {}
                for k, v in pairs(val) do
                    keyCount = keyCount + 1
                    if keyCount <= 12 then
                        local vs = type(v) == "table" and "<table>" or tostring(v)
                        sample[#sample + 1] = string.format("%s=%s", tostring(k), vs)
                    end
                end
                print(string.format("  %s -> table, %d keys: %s",
                    mod.Name, keyCount, table.concat(sample, ", ")))
            elseif ok then
                print(string.format("  %s -> %s = %s", mod.Name, type(val), tostring(val)))
            else
                print(string.format("  %s -> require ERR: %s", mod.Name, tostring(val)))
            end
        end

        -- 6) ReplicatedStorage.Assets top-level (find Perks / Items folders)
        local assets = RS:FindFirstChild("Assets")
        if assets then
            print("\n[RS.Assets top-level]")
            for _, c in ipairs(assets:GetChildren()) do
                print(string.format("  %s: %s (%d children)", c.ClassName, c.Name, #c:GetChildren()))
            end
            local rarities = assets:FindFirstChild("Rarities")
            if rarities then
                print("\n[RS.Assets.Rarities children]")
                for _, c in ipairs(rarities:GetChildren()) do
                    print("  ", c.ClassName, c.Name)
                end
            end
        end

        -- 7) Deep PlayerScripts scan — sometimes the client mirrors state here
        local ps = LocalPlayer:FindFirstChild("PlayerScripts")
        if ps then
            print("\n[PlayerScripts top-level]")
            for _, c in ipairs(ps:GetChildren()) do
                print(string.format("  %s: %s", c.ClassName, c.Name))
            end
        end

        -- 8) Workspace top-level + any folder named like player data
        print("\n[Workspace folders matching player/data/profile]")
        for _, c in ipairs(workspace:GetChildren()) do
            local n = c.Name:lower()
            if c:IsA("Folder") and (n:find("player") or n:find("data") or n:find("profile")) then
                print(string.format("  %s: %s (%d children)", c.ClassName, c.Name, #c:GetChildren()))
            end
        end

        print("\n========== END PROFILE DISCOVERY ==========\n")
        Library:Notify("Profile discovery in console", 4)
    end,
})

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
MenuGroup:AddToggle("AutoCloseUI", {
    Text    = "Auto Close UI",
    Default = false,
    Tooltip = "Hides the menu automatically on script load (press the menu keybind to reopen).",
})
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

-- Auto Close UI: respect the user's saved preference. Runs after autoload
-- so the toggle value has been restored. Library.Toggled is Obsidian's
-- visibility flag; setting it false then re-toggling collapses the menu
-- exactly as if the user pressed the keybind.
if Toggles.AutoCloseUI and Toggles.AutoCloseUI.Value then
    pcall(function()
        if Library.Toggle then Library:Toggle() else Library.Toggled = false end
    end)
end

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
