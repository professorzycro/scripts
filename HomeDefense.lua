-- Home Defense helper. Requires an executor supporting Exunys Aimbot V3.
-- Aimbot credit: Exunys https://github.com/Exunys/Aimbot-V3 (CC0-1.0).
-- Generic player-character support; not tested against this game's weapons.
-- RMB: aim | F6: trigger | F7: hitboxes | F8: highlights | End: unload
local env = getgenv()
if env.HomeDefenseHelper then env.HomeDefenseHelper.Unload() end

local Config = {
    Aim = true, TeamCheck = true, WallCheck = true,
    AimPart = "Head", Radius = 150, Smoothing = 0.08,
    Trigger = false, TriggerDelay = 0.12, FireInterval = 0.15,
    Hitboxes = false, HitboxSize = 6, Highlights = false,
    MaxDistance = 1500,
}
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local connections, originals, highlights = {}, {}, {}
local active, aimedAt, aimedSince, lastShot = true, nil, 0, 0
local Aimbot
local function enemy(player)
    return player ~= LocalPlayer and (not Config.TeamCheck
        or LocalPlayer.Neutral or player.Neutral
        or LocalPlayer.Team == nil or player.Team ~= LocalPlayer.Team)
end
local function living(player)
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    return character and humanoid and humanoid.Health > 0 and character
end
local function restore(part)
    local old = originals[part]
    if old then
        pcall(function()
            part.Size = old.Size
            part.Transparency = old.Transparency
            part.CanCollide = old.CanCollide
        end)
        originals[part] = nil
    end
end
local function unload()
    active = false
    for _, connection in ipairs(connections) do connection:Disconnect() end
    for part in pairs(originals) do restore(part) end
    for _, highlight in pairs(highlights) do highlight:Destroy() end
    if Aimbot then pcall(function() Aimbot.Exit() end) end
    env.HomeDefenseHelper = nil
end
env.HomeDefenseHelper = {Config = Config, Unload = unload}

local ok, result = pcall(function()
    assert(type(loadstring) == "function", "loadstring unavailable")
    assert(Drawing and Drawing.new, "Drawing API unavailable")
    local source = game:HttpGet("https://raw.githubusercontent.com/Exunys/Aimbot-V3/main/src/Aimbot.lua")
    local chunk, err = loadstring(source)
    assert(chunk, err)
    return chunk()
end)
if not ok then
    unload()
    error("Aimbot failed to load: " .. tostring(result))
end
Aimbot = result or env.ExunysDeveloperAimbot
if not Aimbot then unload(); error("Aimbot environment missing") end
Aimbot.Settings.Enabled = Config.Aim
Aimbot.Settings.AliveCheck = true
Aimbot.Settings.TeamCheck = Config.TeamCheck
Aimbot.Settings.WallCheck = Config.WallCheck
Aimbot.Settings.LockPart = Config.AimPart
Aimbot.Settings.Sensitivity = Config.Smoothing
Aimbot.Settings.TriggerKey = Enum.UserInputType.MouseButton2
Aimbot.Settings.Toggle = false
Aimbot.FOVSettings.Radius = Config.Radius
Aimbot.ClosestPlayerTracer.Enabled = false
-- Use our single-shot trigger loop so delayed callbacks cannot pile up.
Aimbot.Triggerbot.Enabled = false
local loaded, loadError = pcall(function() Aimbot.Load() end)
if not loaded then unload(); error(tostring(loadError)) end

local mouse = LocalPlayer:GetMouse()
local function triggerTarget()
    local camera = workspace.CurrentCamera
    if not camera then return end
    local target = mouse.Target
    if not target then return end
    local model = target:FindFirstAncestorOfClass("Model")
    local player
    while model and not player do
        player = Players:GetPlayerFromCharacter(model)
        if not player then model = model.Parent and model.Parent:FindFirstAncestorOfClass("Model") end
    end
    if not player or not enemy(player) or not living(player) then return end
    local position = mouse.Hit.Position
    if (position - camera.CFrame.Position).Magnitude > Config.MaxDistance then return end
    if Config.WallCheck then
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {LocalPlayer.Character, camera}
        local hit = workspace:Raycast(camera.CFrame.Position, position - camera.CFrame.Position, params)
        if hit and not hit.Instance:IsDescendantOf(player.Character) then return end
    end
    return player
end

connections[#connections + 1] = Input.InputBegan:Connect(function(input, processed)
    if processed or Input:GetFocusedTextBox() then return end
    if input.KeyCode == Enum.KeyCode.End then unload(); return end
    if input.KeyCode == Enum.KeyCode.F6 then Config.Trigger = not Config.Trigger end
    if input.KeyCode == Enum.KeyCode.F7 then Config.Hitboxes = not Config.Hitboxes end
    if input.KeyCode == Enum.KeyCode.F8 then Config.Highlights = not Config.Highlights end
end)

local elapsed = 0
connections[#connections + 1] = RunService.Heartbeat:Connect(function(dt)
    if not active then return end
    local now = os.clock()
    local target = Config.Trigger and not Input:GetFocusedTextBox() and triggerTarget() or nil
    if target ~= aimedAt then aimedAt, aimedSince = target, now end
    if target and now - aimedSince >= Config.TriggerDelay and now - lastShot >= Config.FireInterval then
        local tool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
        if tool then tool:Activate(); lastShot = now end
    end
    elapsed = elapsed + dt
    if elapsed < 0.1 then return end
    elapsed = 0
    Aimbot.Settings.Enabled = Config.Aim
    Aimbot.Settings.TeamCheck = Config.TeamCheck
    Aimbot.Settings.WallCheck = Config.WallCheck
    Aimbot.Settings.LockPart = Config.AimPart
    Aimbot.Settings.Sensitivity = Config.Smoothing
    Aimbot.FOVSettings.Radius = Config.Radius
    local keepParts, keepHighlights = {}, {}
    for _, player in ipairs(Players:GetPlayers()) do
        local character = enemy(player) and living(player)
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local camera = workspace.CurrentCamera
        local inRange = root and camera and (root.Position - camera.CFrame.Position).Magnitude <= Config.MaxDistance
        if inRange and Config.Hitboxes then
            keepParts[root] = true
            originals[root] = originals[root] or {
                Size = root.Size, Transparency = root.Transparency, CanCollide = root.CanCollide,
            }
            root.Size = Vector3.one * math.clamp(Config.HitboxSize, 2, 20)
            root.Transparency = 0.75
            root.CanCollide = false
        end
        if inRange and Config.Highlights then
            keepHighlights[player] = true
            local highlight = highlights[player]
            if not highlight then
                highlight = Instance.new("Highlight")
                highlight.Name = "HomeDefenseHighlight"
                highlight.FillColor = Color3.fromRGB(255, 90, 80)
                highlight.FillTransparency = 0.65
                highlight.Parent = LocalPlayer:WaitForChild("PlayerGui")
                highlights[player] = highlight
            end
            highlight.Adornee = character
            highlight.DepthMode = Config.WallCheck and Enum.HighlightDepthMode.Occluded or Enum.HighlightDepthMode.AlwaysOnTop
        end
    end
    for part in pairs(originals) do if not keepParts[part] then restore(part) end end
    for player, highlight in pairs(highlights) do
        if not keepHighlights[player] then highlight:Destroy(); highlights[player] = nil end
    end
end)
print("HomeDefense loaded: RMB aim | F6 trigger | F7 hitboxes | F8 highlights | End unload")

