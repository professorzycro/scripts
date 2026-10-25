-- Home Defense helper. Requires an executor supporting Exunys Aimbot V3.
-- Aimbot credit: Exunys https://github.com/Exunys/Aimbot-V3 (CC0-1.0).
-- Generic player-character support; not tested against this game's weapons.
-- Rayfield credit: Sirius https://docs.sirius.menu/rayfield
-- Defaults: RMB aim | F6 trigger | F7 hitboxes | F8 ESP | End unload | F1 menu
local env = getgenv()
if env.HomeDefenseHelper then env.HomeDefenseHelper.Unload() end

local Config = {
    Aim = true, AimAlways = false, TeamCheck = true, WallCheck = true,
    AimPart = "Head", Radius = 150, Smoothing = 0.08,
    Trigger = false, TriggerDelay = 0.12, FireInterval = 0.15,
    TriggerMode = "Auto", TriggerPoint = "Auto",
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
local capturingKey, triggerStatus, fireHeld, heldTool, releaseAt
local keyButtons = {}
local keys = {Aim = Enum.UserInputType.MouseButton2, Trigger = Enum.KeyCode.F6,
    Hitboxes = Enum.KeyCode.F7, ESP = Enum.KeyCode.F8, Unload = Enum.KeyCode.End,
    Menu = Enum.KeyCode.F1}
local HttpService = game:GetService("HttpService")
local keyFile = "HomeDefense-keys-v3.json"
pcall(function()
    if isfile and readfile and isfile(keyFile) then
        local saved = HttpService:JSONDecode(readfile(keyFile))
        for action in pairs(keys) do
            local name = saved[action]
            if type(name) == "string" then
                if action == "Aim" and name == "MouseButton2" then keys[action] = Enum.UserInputType.MouseButton2
                elseif Enum.KeyCode[name] then keys[action] = Enum.KeyCode[name] end
            end
        end
    end
end)
local lightingOriginals, cameraOriginals = {}, {}
local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local active, aimedAt, aimedSince, lastShot = true, nil, 0, 0
local originalSensitivity = Input.MouseDeltaSensitivity
local function releaseFire()
    if fireHeld then pcall(function() mouse1release() end); fireHeld = false end
    if heldTool then pcall(function() heldTool:Deactivate() end); heldTool = nil end
end
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
    releaseFire()
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
Aimbot.Settings.TriggerKey = keys.Aim
Aimbot.Settings.Toggle = false
Aimbot.FOVSettings.Radius = Config.Radius
Aimbot.ClosestPlayerTracer.Enabled = false
-- Use our single-shot trigger loop so delayed callbacks cannot pile up.
Aimbot.Triggerbot.Enabled = false
local loaded, loadError = pcall(function() Aimbot.Load() end)
if not loaded then unload(); error(tostring(loadError)) end

local mouse = LocalPlayer:GetMouse()
local function status(message)
    if triggerStatus and message ~= triggerStatus.LastMessage then
        triggerStatus.LastMessage = message
        triggerStatus:Set("Trigger: " .. message)
    end
end
local function triggerTarget()
    local camera = workspace.CurrentCamera
    if not camera then return end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ignored = {camera}
    if LocalPlayer.Character then table.insert(ignored, LocalPlayer.Character) end
    params.FilterDescendantsInstances = ignored
    local centered = Config.TriggerPoint == "Center" or
        (Config.TriggerPoint == "Auto" and Input.MouseBehavior == Enum.MouseBehavior.LockCenter)
    local ray
    if centered then
        ray = camera:ViewportPointToRay(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
    else
        local location = Input:GetMouseLocation()
        ray = camera:ScreenPointToRay(location.X, location.Y)
    end
    local hit = workspace:Raycast(ray.Origin, ray.Direction * Config.MaxDistance, params)
    local target = hit and hit.Instance
    if not target then status("no target under crosshair"); return end
    local model = target
    local player
    while model and not player do
        if model:IsA("Model") then player = Players:GetPlayerFromCharacter(model) end
        if not player then model = model.Parent end
    end
    if not player then status("crosshair on scenery / NPC"); return end
    if not enemy(player) then status("blocked by team check"); return end
    if not living(player) then status("target is dead"); return end
    -- The first ray hit must belong to the target, so walls always block firing.
    return player
end

connections[#connections + 1] = Input.InputBegan:Connect(function(input, processed)
    if capturingKey then
        local action = capturingKey
        local chosen = input.KeyCode
        if input.KeyCode == Enum.KeyCode.Escape then
            capturingKey = nil
            keyButtons[action].Text = keys[action].Name
            return
        end
        if action == "Aim" and input.UserInputType == Enum.UserInputType.MouseButton2 then chosen = input.UserInputType end
        if chosen == Enum.KeyCode.Unknown then return end
        for other, key in pairs(keys) do
            if other ~= action and key == chosen then
                if Rayfield then Rayfield:Notify({Title = "Key already used", Content = "Choose a different key; " .. other .. " uses this one.", Duration = 3}) end
                return
            end
        end
        keys[action] = chosen
        if action == "Aim" then Aimbot.Settings.TriggerKey = chosen end
        keyButtons[action].Text = chosen.Name
        capturingKey = nil
        pcall(function()
            if writefile then
                local saved = {}
                for name, key in pairs(keys) do saved[name] = key.Name end
                writefile(keyFile, HttpService:JSONEncode(saved))
            end
        end)
        return
    end
    if processed or Input:GetFocusedTextBox() then return end
    if input.KeyCode == keys.Menu and Rayfield then Rayfield:SetVisibility(not Rayfield:IsVisible()); return end
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
    if releaseAt and now >= releaseAt then releaseFire(); releaseAt = nil end
    local blocked = capturingKey or Input:GetFocusedTextBox() or (Rayfield and Rayfield:IsVisible())
    local target = Config.Trigger and not blocked and triggerTarget() or nil
    if not Config.Trigger or blocked then
        releaseFire()
        status(Config.Trigger and "paused: hide menu to fire" or "off")
    end
    if target ~= aimedAt then aimedAt, aimedSince = target, now end
    if target and now - aimedSince >= Config.TriggerDelay and now - lastShot >= Config.FireInterval then
        local tool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
        local mode = Config.TriggerMode
        local canClick = type(mouse1press) == "function" and type(mouse1release) == "function"
        local canSingleClick = type(mouse1click) == "function"
        if mode == "Auto" then mode = (canClick or canSingleClick) and "Mouse" or "Tool" end
        if mode == "Mouse" and (canClick or canSingleClick) then
            local fired, err = pcall(function()
                if canClick then mouse1press(); fireHeld = true; releaseAt = now + 0.04
                else mouse1click() end
            end)
            status(fired and ("clicking at " .. target.Name) or ("input failed: " .. tostring(err)))
            lastShot = now
        elseif mode == "Tool" and tool then
            local fired, err = pcall(function() tool:Activate(); heldTool = tool; releaseAt = now + 0.04 end)
            status(fired and ("activating " .. tool.Name) or ("tool failed: " .. tostring(err)))
            lastShot = now
        else
            status(mode == "Mouse" and "executor mouse input unavailable; try Tool mode" or "equip a weapon")
        end
    end
    elapsed = elapsed + dt
    if elapsed < 0.1 then return end
    elapsed = 0
    Aimbot.Settings.Enabled = Config.Aim and not Config.AimAlways
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
connections[#connections + 1] = RunService.RenderStepped:Connect(function(dt)
    if not active or not Config.Aim or not Config.AimAlways or capturingKey
        or Input:GetFocusedTextBox() or (Rayfield and Rayfield:IsVisible()) then return end
    local camera = workspace.CurrentCamera
    if not camera then return end
    local cursor = Input:GetMouseLocation()
    local closest, distance = nil, Config.Radius
    for _, player in ipairs(Players:GetPlayers()) do
        local character = enemy(player) and living(player)
        local part = character and character:FindFirstChild(Config.AimPart)
        if part then
            local point, visible = camera:WorldToScreenPoint(part.Position)
            local screenDistance = (Vector2.new(point.X, point.Y) - cursor).Magnitude
            if visible and screenDistance < distance then
                local clear = true
                if Config.WallCheck then
                    local params = RaycastParams.new()
                    params.FilterType = Enum.RaycastFilterType.Exclude
                    local ignored = {camera}
                    if LocalPlayer.Character then table.insert(ignored, LocalPlayer.Character) end
                    params.FilterDescendantsInstances = ignored
                    local hit = workspace:Raycast(camera.CFrame.Position, part.Position - camera.CFrame.Position, params)
                    clear = not hit or hit.Instance:IsDescendantOf(character)
                end
                if clear then closest, distance = part, screenDistance end
            end
        end
    end
    if closest then
        local goal = CFrame.lookAt(camera.CFrame.Position, closest.Position)
        local alpha = Config.Smoothing <= 0 and 1 or 1 - math.exp(-dt / Config.Smoothing)
        camera.CFrame = camera.CFrame:Lerp(goal, alpha)
    end
end)
-- Configuration flags are unique; saved Rayfield values flow through callbacks.
local guiOK, guiError = pcall(function()
    Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
    local window = Rayfield:CreateWindow({
        Name = "Home Defense", LoadingTitle = "Home Defense", LoadingSubtitle = "professorzycro",
        Theme = "Default", ShowText = "Home Defense", DisableRayfieldPrompts = true,
        -- Our handler supports rebinding the menu without rebuilding the window.
        ToggleUIKeybind = Enum.KeyCode.F24,
        ConfigurationSaving = {Enabled = true, FolderName = "ProfessorZycro", FileName = "HomeDefense-v2"},
        Discord = {Enabled = false}, KeySystem = false,
    })
    if not active then Rayfield:Destroy(); return end
    uiToggles = {}
    local function attachKey(name, action)
        local roots = {playerGui}
        pcall(function() table.insert(roots, game:GetService("CoreGui")) end)
        pcall(function() if gethui then table.insert(roots, gethui()) end end)
        local row
        for _, root in ipairs(roots) do
            pcall(function()
                for _, candidate in ipairs(root:GetDescendants()) do
                    local title = candidate:FindFirstChild("Title")
                    if candidate.Name == name and title and title:IsA("TextLabel") and title.Text == name then
                        row = candidate
                        break
                    end
                end
            end)
            if row then break end
        end
        if not row then error("Cannot attach inline key control: " .. name) end
        local button = Instance.new("TextButton")
        button.Name = "InlineKeybind"
        button.AnchorPoint = Vector2.new(1, 0.5)
        button.Position = UDim2.new(1, row:FindFirstChild("Switch") and -70 or -12, 0.5, 0)
        button.Size = UDim2.fromOffset(78, 26)
        button.BackgroundColor3 = Color3.fromRGB(48, 48, 56)
        button.TextColor3 = Color3.fromRGB(240, 240, 245)
        button.Font = Enum.Font.GothamMedium
        button.TextSize = 11
        button.Text = keys[action].Name
        button.ZIndex = row.ZIndex + 5
        button.Parent = row
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 5)
        corner.Parent = button
        local title = row.Title
        title.Size = UDim2.new(1, row:FindFirstChild("Switch") and -170 or -110, 1, 0)
        title.TextTruncate = Enum.TextTruncate.AtEnd
        keyButtons[action] = button
        connections[#connections + 1] = button.MouseButton1Click:Connect(function()
            if capturingKey and keyButtons[capturingKey] then keyButtons[capturingKey].Text = keys[capturingKey].Name end
            capturingKey = action
            button.Text = "Press key..."
            releaseFire()
        end)
    end
    local function toggle(tab, name, property, action)
        local control = tab:CreateToggle({Name = name, CurrentValue = Config[property], Flag = "HD_" .. property,
            Callback = function(value) Config[property] = value end})
        uiToggles[property] = control
        if action then attachKey(name, action) end
    end
    local function slider(tab, name, property, minimum, maximum, increment)
        tab:CreateSlider({Name = name, Range = {minimum, maximum}, Increment = increment or 1,
            CurrentValue = Config[property], Flag = "HD_" .. property,
            Callback = function(value) Config[property] = value end})
    end
    local aim = window:CreateTab("Aim")
    toggle(aim, "Aimbot", "Aim", "Aim")
    toggle(aim, "Always on (no hold required)", "AimAlways")
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
    toggle(combat, "Triggerbot", "Trigger", "Trigger")
    triggerStatus = combat:CreateLabel("Trigger: off")
    combat:CreateDropdown({Name = "Fire method", Options = {"Auto", "Mouse", "Tool"},
        CurrentOption = {Config.TriggerMode}, Flag = "HD_TriggerMode",
        Callback = function(options) releaseFire(); Config.TriggerMode = options[1] end})
    combat:CreateDropdown({Name = "Crosshair position", Options = {"Auto", "Center", "Cursor"},
        CurrentOption = {Config.TriggerPoint}, Flag = "HD_TriggerPoint",
        Callback = function(options) Config.TriggerPoint = options[1] end})
    slider(combat, "Trigger delay (seconds)", "TriggerDelay", 0, 1, 0.01)
    slider(combat, "Shot interval (seconds)", "FireInterval", 0.05, 1, 0.01)
    toggle(combat, "Expand enemy root hitboxes", "Hitboxes", "Hitboxes")
    slider(combat, "Hitbox size (studs)", "HitboxSize", 2, 20)
    slider(combat, "Trigger / hitbox range (studs)", "MaxDistance", 50, 5000, 50)
    combat:CreateParagraph({Title = "Trigger troubleshooting", Content = "Hide the menu to fire. Auto prefers mouse input; try Tool if mouse input is unavailable. If your gun uses a fixed crosshair, choose Center. Status shows detected targets and input attempts, not confirmed damage."})
    local esp = window:CreateTab("ESP")
    toggle(esp, "Enable ESP", "Highlights", "ESP")
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
    local settings = window:CreateTab("Settings")
    settings:CreateParagraph({Title = "Home Defense v3", Content = "Click a key badge beside Aimbot, Triggerbot, Hitboxes, ESP, or Menu to rebind it. Escape cancels. Aim accepts RMB or a keyboard key. F1 is the default menu key. Always-on aim and trigger pause while the menu is open. Settings and keys save when file APIs are available."})
    settings:CreateButton({Name = "Hide / show menu", Callback = function() Rayfield:SetVisibility(not Rayfield:IsVisible()) end})
    attachKey("Hide / show menu", "Menu")
    settings:CreateKeybind({Name = "Unload key", CurrentKeybind = keys.Unload.Name, CallOnChange = true,
        HoldToInteract = false, Flag = "HD_UnloadKey", Callback = function(value)
            if type(value) == "string" and Enum.KeyCode[value] then keys.Unload = Enum.KeyCode[value] end
        end})
    settings:CreateButton({Name = "Unload and restore changes", Callback = unload})
    Rayfield:LoadConfiguration()
end)
if not guiOK then warn("HomeDefense menu failed: " .. tostring(guiError)); unload() end

