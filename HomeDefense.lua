-- Home Defense helper. Requires an executor supporting Exunys Aimbot V3.
-- Aimbot credit: Exunys https://github.com/Exunys/Aimbot-V3 (CC0-1.0).
-- Generic player-character support; not tested against this game's weapons.
-- Rayfield credit: Sirius https://docs.sirius.menu/rayfield
-- Defaults: RMB aim | F6 trigger | F7 hitboxes | F8 ESP | End unload | K menu
local env = getgenv()
if env.HomeDefenseHelper then env.HomeDefenseHelper.Unload() end

local Config = {
    Aim = true, TeamCheck = true, WallCheck = true,
    AimPart = "Head", Radius = 150, Smoothing = 0.08,
    Trigger = false, TriggerDelay = 0.12, FireInterval = 0.15,
    Hitboxes = false, HitboxSize = 6, Highlights = false,
    MaxDistance = 1500, ShowFOV = true, Tracer = false,
    ESPNames = true, ESPHealth = true, ESPDistance = true, ESPTeamColors = true,
    ESPTeamCheck = true, ESPThroughWalls = true, ESPBoxes = false,
    ESPDistanceLimit = 1500, ESPTextSize = 14, Fullbright = false,
    CameraOverride = false, CameraFOV = 80,
}
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local LocalPlayer = Players.LocalPlayer
local connections, originals, highlights = {}, {}, {}
local Rayfield, uiToggles
local keys = {Aim = Enum.UserInputType.MouseButton2, Trigger = Enum.KeyCode.F6,
    Hitboxes = Enum.KeyCode.F7, ESP = Enum.KeyCode.F8, Unload = Enum.KeyCode.End}
local lightingOriginals, cameraOriginals = {}, {}
local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local active, aimedAt, aimedSince, lastShot = true, nil, 0, 0
local originalSensitivity = Input.MouseDeltaSensitivity
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
    if not active then return end
    active = false
    for _, connection in ipairs(connections) do connection:Disconnect() end
    for part in pairs(originals) do restore(part) end
    for _, visual in pairs(highlights) do
        visual.Highlight:Destroy(); visual.Tag:Destroy(); visual.Box:Destroy()
    end
    for property, value in pairs(lightingOriginals) do Lighting[property] = value end
    for camera, value in pairs(cameraOriginals) do
        pcall(function() camera.FieldOfView = value end)
    end
    if Aimbot then pcall(function() Aimbot:Exit() end) end
    Input.MouseDeltaSensitivity = originalSensitivity
    if Rayfield then pcall(function() Rayfield:Destroy() end) end
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
    local model = target
    local player
    while model and not player do
        if model:IsA("Model") then player = Players:GetPlayerFromCharacter(model) end
        if not player then model = model.Parent end
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
    if input.KeyCode == keys.Unload then unload(); return end
    local function flip(property)
        local value = not Config[property]
        Config[property] = value
        if uiToggles and uiToggles[property] then uiToggles[property]:Set(value) end
    end
    if input.KeyCode == keys.Trigger then flip("Trigger") end
    if input.KeyCode == keys.Hitboxes then flip("Hitboxes") end
    if input.KeyCode == keys.ESP then flip("Highlights") end
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
    Aimbot.FOVSettings.Visible = Config.ShowFOV
    Aimbot.ClosestPlayerTracer.Enabled = Config.Tracer
    local bright = {Brightness = 2, ClockTime = 14, FogEnd = 100000,
        GlobalShadows = false, Ambient = Color3.fromRGB(180, 180, 180)}
    for property, value in pairs(bright) do
        if Config.Fullbright then
            if lightingOriginals[property] == nil then lightingOriginals[property] = Lighting[property] end
            Lighting[property] = value
        elseif lightingOriginals[property] ~= nil then
            Lighting[property] = lightingOriginals[property]; lightingOriginals[property] = nil
        end
    end
    local camera = workspace.CurrentCamera
    if Config.CameraOverride and camera then
        cameraOriginals[camera] = cameraOriginals[camera] or camera.FieldOfView
        camera.FieldOfView = Config.CameraFOV
    else
        for savedCamera, value in pairs(cameraOriginals) do
            pcall(function() savedCamera.FieldOfView = value end)
            cameraOriginals[savedCamera] = nil
        end
    end
    local keepParts, keepHighlights = {}, {}
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player ~= LocalPlayer and living(player)
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local camera = workspace.CurrentCamera
        local inRange = root and camera and (root.Position - camera.CFrame.Position).Magnitude <= Config.MaxDistance
        if inRange and enemy(player) and Config.Hitboxes then
            keepParts[root] = true
            originals[root] = originals[root] or {
                Size = root.Size, Transparency = root.Transparency, CanCollide = root.CanCollide,
            }
            root.Size = Vector3.one * math.clamp(Config.HitboxSize, 2, 20)
            root.Transparency = 0.75
            root.CanCollide = false
        end
        local espRange = root and camera and (root.Position - camera.CFrame.Position).Magnitude <= Config.ESPDistanceLimit
        if espRange and Config.Highlights and (not Config.ESPTeamCheck or enemy(player)) then
            keepHighlights[player] = true
            local visual = highlights[player]
            if not visual then
                local highlight = Instance.new("Highlight")
                highlight.Name = "HomeDefenseHighlight"
                highlight.FillColor = Color3.fromRGB(255, 90, 80)
                highlight.FillTransparency = 0.65
                highlight.Parent = playerGui
                local tag = Instance.new("BillboardGui")
                tag.Name = "HomeDefenseESP"
                tag.Size = UDim2.fromOffset(230, 70)
                tag.StudsOffsetWorldSpace = Vector3.new(0, 3.5, 0)
                tag.Parent = playerGui
                local label = Instance.new("TextLabel")
                label.Size = UDim2.fromScale(1, 1)
                label.BackgroundTransparency = 1
                label.TextStrokeTransparency = 0.25
                label.Font = Enum.Font.GothamMedium
                label.Parent = tag
                local box = Instance.new("SelectionBox")
                box.LineThickness = 0.025
                box.SurfaceTransparency = 1
                box.Parent = playerGui
                visual = {Highlight = highlight, Tag = tag, Label = label, Box = box}
                highlights[player] = visual
            end
            local color = Config.ESPTeamColors and player.Team and player.TeamColor.Color or Color3.fromRGB(255, 90, 80)
            visual.Highlight.Adornee = character
            visual.Highlight.FillColor = color
            visual.Highlight.OutlineColor = color
            visual.Highlight.DepthMode = Config.ESPThroughWalls and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
            visual.Tag.Adornee = character:FindFirstChild("Head") or root
            visual.Tag.AlwaysOnTop = Config.ESPThroughWalls
            visual.Tag.MaxDistance = Config.ESPDistanceLimit
            visual.Label.TextColor3 = color
            visual.Label.TextSize = Config.ESPTextSize
            local lines = {}
            if Config.ESPNames then table.insert(lines, player.DisplayName .. " (@" .. player.Name .. ")") end
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if Config.ESPHealth and humanoid then
                table.insert(lines, string.format("HP %d / %d", math.ceil(humanoid.Health), math.ceil(humanoid.MaxHealth)))
            end
            if Config.ESPDistance then table.insert(lines, string.format("%d studs", (root.Position - camera.CFrame.Position).Magnitude)) end
            visual.Label.Text = table.concat(lines, "\n")
            visual.Box.Adornee = Config.ESPBoxes and character or nil
            visual.Box.Color3 = color
        end
    end
    for part in pairs(originals) do if not keepParts[part] then restore(part) end end
    for player, visual in pairs(highlights) do
        if not keepHighlights[player] then
            visual.Highlight:Destroy(); visual.Tag:Destroy(); visual.Box:Destroy()
            highlights[player] = nil
        end
    end
end)
-- Configuration flags are unique; saved Rayfield values flow through callbacks.
local guiOK, guiError = pcall(function()
    Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
    local window = Rayfield:CreateWindow({
        Name = "Home Defense", LoadingTitle = "Home Defense", LoadingSubtitle = "professorzycro",
        Theme = "Default", ShowText = "Home Defense", DisableRayfieldPrompts = true,
        ConfigurationSaving = {Enabled = true, FolderName = "ProfessorZycro", FileName = "HomeDefense-v2"},
        Discord = {Enabled = false}, KeySystem = false,
    })
    if not active then Rayfield:Destroy(); return end
    uiToggles = {}
    local function toggle(tab, name, property)
        local control = tab:CreateToggle({Name = name, CurrentValue = Config[property], Flag = "HD_" .. property,
            Callback = function(value) Config[property] = value end})
        uiToggles[property] = control
    end
    local function slider(tab, name, property, minimum, maximum, increment)
        tab:CreateSlider({Name = name, Range = {minimum, maximum}, Increment = increment or 1,
            CurrentValue = Config[property], Flag = "HD_" .. property,
            Callback = function(value) Config[property] = value end})
    end
    local aim = window:CreateTab("Aim")
    toggle(aim, "Enable aim (hold aim key)", "Aim")
    toggle(aim, "Team check", "TeamCheck")
    toggle(aim, "Wall check", "WallCheck")
    slider(aim, "Aim radius (pixels)", "Radius", 20, 600)
    slider(aim, "Smoothing (seconds)", "Smoothing", 0, 0.5, 0.01)
    toggle(aim, "Show aim circle", "ShowFOV")
    toggle(aim, "Target tracer", "Tracer")
    aim:CreateDropdown({Name = "Aim part", Options = {"Head", "HumanoidRootPart"},
        CurrentOption = {Config.AimPart}, Flag = "HD_AimPart",
        Callback = function(options)
            if Config.AimPart ~= options[1] then
                Config.AimPart = options[1]
                Aimbot.Settings.LockPart = Config.AimPart
                Input.MouseDeltaSensitivity = originalSensitivity
                Aimbot.Restart()
            end
        end})
    local combat = window:CreateTab("Trigger & Hitboxes")
    toggle(combat, "Triggerbot", "Trigger")
    slider(combat, "Trigger delay (seconds)", "TriggerDelay", 0, 1, 0.01)
    slider(combat, "Shot interval (seconds)", "FireInterval", 0.05, 1, 0.01)
    toggle(combat, "Expand enemy root hitboxes", "Hitboxes")
    slider(combat, "Hitbox size (studs)", "HitboxSize", 2, 20)
    slider(combat, "Trigger / hitbox range (studs)", "MaxDistance", 50, 5000, 50)
    combat:CreateParagraph({Title = "Compatibility", Content = "Triggerbot activates equipped Tools. Hitbox changes are local and may not affect server-validated weapons."})
    local esp = window:CreateTab("ESP")
    toggle(esp, "Enable ESP", "Highlights")
    toggle(esp, "Enemy only", "ESPTeamCheck")
    toggle(esp, "Show through walls (highlight and labels)", "ESPThroughWalls")
    toggle(esp, "Names", "ESPNames")
    toggle(esp, "Health", "ESPHealth")
    toggle(esp, "Distance", "ESPDistance")
    toggle(esp, "Team colors", "ESPTeamColors")
    toggle(esp, "Character boxes", "ESPBoxes")
    slider(esp, "ESP range (studs)", "ESPDistanceLimit", 50, 5000, 50)
    slider(esp, "Label size", "ESPTextSize", 10, 24)
    local visuals = window:CreateTab("Visuals")
    toggle(visuals, "Fullbright", "Fullbright")
    toggle(visuals, "Override camera FOV", "CameraOverride")
    slider(visuals, "Camera FOV", "CameraFOV", 40, 120)
    local binds = window:CreateTab("Keybinds")
    binds:CreateParagraph({Title = "Controls", Content = "K shows or hides the menu by default; change it in Rayfield's built-in settings (gear). Aim defaults to RMB. Choose Keyboard to use your saved aim key. Avoid assigning the same key to multiple actions."})
    local keyboardAim = Enum.KeyCode.E
    local aimMode = "RMB"
    local function applyAimKey()
        keys.Aim = aimMode == "RMB" and Enum.UserInputType.MouseButton2 or keyboardAim
        Aimbot.Settings.TriggerKey = keys.Aim
    end
    binds:CreateDropdown({Name = "Aim input", Options = {"RMB", "Keyboard"}, CurrentOption = {"RMB"}, Flag = "HD_AimMode",
        Callback = function(options) aimMode = options[1]; applyAimKey() end})
    binds:CreateKeybind({Name = "Keyboard aim key (hold)", CurrentKeybind = "E", HoldToInteract = false,
        Flag = "HD_AimKey", CallOnChange = true, Callback = function(value)
            if typeof(value) == "EnumItem" and value.EnumType == Enum.KeyCode then keyboardAim = value
            elseif type(value) == "string" and Enum.KeyCode[value] then keyboardAim = Enum.KeyCode[value] end
            applyAimKey()
        end})
    for _, entry in ipairs({{"Trigger", "Triggerbot", "F6"}, {"Hitboxes", "Hitboxes", "F7"},
        {"ESP", "ESP", "F8"}, {"Unload", "Unload", "End"}}) do
        local action, name, default = entry[1], entry[2], entry[3]
        binds:CreateKeybind({Name = name .. " key", CurrentKeybind = default, HoldToInteract = false,
            Flag = "HD_Key_" .. action, CallOnChange = true, Callback = function(value)
                if typeof(value) == "EnumItem" and value.EnumType == Enum.KeyCode then keys[action] = value
                elseif type(value) == "string" and Enum.KeyCode[value] then keys[action] = Enum.KeyCode[value] end
            end})
    end
    local settings = window:CreateTab("Settings")
    settings:CreateParagraph({Title = "Home Defense v2", Content = "Settings save through Rayfield when file APIs are available. ESP refreshes at 10 Hz and follows respawns. Credits: Exunys (aimbot), Sirius (Rayfield)."})
    settings:CreateButton({Name = "Unload and restore changes", Callback = unload})
    Rayfield:LoadConfiguration()
end)
if not guiOK then warn("HomeDefense menu failed: " .. tostring(guiError)); unload() end

