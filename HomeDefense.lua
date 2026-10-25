-- Home Defense helper. Uses compatible aim when Exunys/Drawing is unavailable.
-- Aimbot credit: Exunys https://github.com/Exunys/Aimbot-V3 (CC0-1.0).
-- Generic player-character support; not tested against this game's weapons.
-- Rayfield credit: Sirius https://docs.sirius.menu/rayfield
-- Defaults: RMB aim | F6 trigger | F7 hitboxes | F8 ESP | End unload | F1 menu | F4 recoil | F3 retaliate
local env = getgenv()
if env.HomeDefenseHelper then pcall(env.HomeDefenseHelper.Unload) end

local Config = {
    Aim = true, AimAlways = false, TeamCheck = true, WallCheck = true, AimIgnoreEffects = true,
    AimOrigin = "Auto", PauseAimWithMenu = false,
    AimPart = "Auto", Radius = 150, Smoothing = 0.04,
    StickyAim = true, AimPrediction = false, PredictionTime = 0.08,
    Trigger = false, TriggerDelay = 0, FireInterval = 0.06,
    TriggerMode = "Auto", TriggerPoint = "Auto", TriggerPattern = "Pulse", TriggerPressTime = 0.04,
    IgnoreBreakableGlass = true,
    TriggerIgnoreEffects = true,
    Hitboxes = false, HitboxSize = 6, HitboxPart = "Head", HitboxTransparency = 0.75,
    HitboxWallCheck = true, Highlights = false,
    MaxDistance = 1500, ShowFOV = true, Tracer = false,
    ESPNames = true, ESPHealth = true, ESPDistance = true, ESPTeamColors = true,
    ESPTeamCheck = true, ESPThroughWalls = true, ESPBoxes = false,
    ESPDistanceLimit = 1500, ESPTextSize = 14, Fullbright = false,
    CameraOverride = false, CameraFOV = 80,
    RecoilEnabled = false, RecoilStrength = 60,
    Retaliate = false, RetaliateDuration = 1.5,
    AutoSave = true,
}
local configDefaults = {}
for name, value in pairs(Config) do configDefaults[name] = value end
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local LocalPlayer = Players.LocalPlayer
local connections, originals, highlights = {}, {}, {}
local Rayfield, uiToggles
local configControls, keyControls = {}, {}
local capturingKey, triggerStatus, fireHeld, heldTool, releaseAt
local keyButtons = {}
local keys = {Aim = Enum.UserInputType.MouseButton2, Trigger = Enum.KeyCode.F6,
    Hitboxes = Enum.KeyCode.F7, ESP = Enum.KeyCode.F8, Unload = Enum.KeyCode.End,
    Menu = Enum.KeyCode.F1, Recoil = Enum.KeyCode.F4, Retaliate = Enum.KeyCode.F3}
local HttpService = game:GetService("HttpService")
local keyDefaults = {}
for action, key in pairs(keys) do keyDefaults[action] = key.Name end
local configPath = "ProfessorZycro/HomeDefense-config.json"
local configReady, configStatus, lastConfigSignature, nextConfigCheck = false, nil, nil, 0
local lastConfigMessage = "No saved workspace config loaded"
local configRanges = {Radius={20,600},Smoothing={0,0.5},PredictionTime={0,0.25},TriggerDelay={0,1},
    FireInterval={0.03,1},TriggerPressTime={0.02,0.2},HitboxSize={2,20},HitboxTransparency={0,0.95},
    MaxDistance={50,5000},ESPDistanceLimit={50,5000},ESPTextSize={10,24},CameraFOV={40,120},
    RecoilStrength={0,100},RetaliateDuration={0.5,4}}
local configOptions = {AimOrigin={Auto=true,Center=true,Cursor=true},AimPart={Auto=true,Head=true,UpperTorso=true,HumanoidRootPart=true},
    TriggerMode={Auto=true,Mouse=true,Tool=true},TriggerPoint={Auto=true,Center=true,Cursor=true},
    TriggerPattern={Pulse=true,Hold=true},HitboxPart={Head=true,Torso=true,Both=true}}
local function configNote(message)
    if message ~= lastConfigMessage and configStatus then configStatus:Set(message) end
    lastConfigMessage = message
end
local function configSnapshot()
    local snapshot = {Version=1,Settings={},Keys={}}
    for name,value in pairs(Config) do snapshot.Settings[name]=value end
    for action,key in pairs(keys) do snapshot.Keys[action]=key.Name end
    return snapshot
end
local function configSignature()
    local entries = {}
    for name,value in pairs(Config) do entries[#entries+1]="S:"..name.."="..tostring(value) end
    for action,key in pairs(keys) do entries[#entries+1]="K:"..action.."="..key.Name end
    table.sort(entries)
    return table.concat(entries,"\n")
end
local function applyConfig(snapshot)
    assert(type(snapshot)=="table" and snapshot.Version==1 and type(snapshot.Settings)=="table", "Unsupported config format")
    for name,default in pairs(configDefaults) do
        local value=snapshot.Settings[name]
        if type(value)==type(default) then
            if type(value)=="number" then
                if value==value and math.abs(value)<1e8 then
                    local range=configRanges[name]
                    Config[name]=range and math.clamp(value,range[1],range[2]) or value
                end
            elseif type(value)=="string" then
                if configOptions[name] and configOptions[name][value] then Config[name]=value end
            else Config[name]=value end
        end
    end
    if type(snapshot.Keys)=="table" then
        for action in pairs(keys) do
            local name=snapshot.Keys[action]
            if type(name)=="string" then
                local ok,key=pcall(function()
                    if action=="Aim" and name=="MouseButton2" then return Enum.UserInputType.MouseButton2 end
                    return Enum.KeyCode[name]
                end)
                if ok and key and name~="Unknown" and name~="None" then keys[action]=key end
            end
        end
    end
    for action,button in pairs(keyButtons) do button.Text=keys[action].Name end
    for action,control in pairs(keyControls) do pcall(function() control:Set(keys[action].Name) end) end
    if Rayfield then
        for name,value in pairs(Config) do
            local control=configControls[name] or (Rayfield.Flags and Rayfield.Flags["HD_"..name])
            if control and control.Set then
                pcall(function() control:Set(type(value)=="string" and {value} or value) end)
            end
        end
    end
end
local function saveSettings(force)
    if type(writefile)~="function" then configNote("Workspace saving unavailable in this executor"); return false end
    local signature=configSignature()
    if not force and signature==lastConfigSignature then return true end
    local ok,err=pcall(function()
        if makefolder and (not isfolder or not isfolder("ProfessorZycro")) then makefolder("ProfessorZycro") end
        writefile(configPath,HttpService:JSONEncode(configSnapshot()))
    end)
    if ok then lastConfigSignature=signature; configNote("Saved: workspace/"..configPath)
    else configNote("Save failed: "..tostring(err)) end
    return ok
end
local function loadSettings()
    local ok,err=pcall(function()
        assert(type(readfile)=="function", "Workspace reading unavailable")
        if isfile then assert(isfile(configPath), "No saved config file yet") end
        applyConfig(HttpService:JSONDecode(readfile(configPath)))
    end)
    if ok then lastConfigSignature=configSignature(); configNote("Loaded: workspace/"..configPath)
    else configNote("Load skipped: "..tostring(err)) end
    return ok
end
local function resetSettings()
    applyConfig({Version=1,Settings=configDefaults,Keys=keyDefaults})
    return saveSettings(true)
end
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
loadSettings()
local lightingOriginals, cameraOriginals = {}, {}
local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local previousBoot = playerGui:FindFirstChild("HomeDefenseStartup")
if previousBoot then previousBoot:Destroy() end
local bootGui = Instance.new("ScreenGui")
bootGui.Name = "HomeDefenseStartup"
bootGui.ResetOnSpawn = false
bootGui.DisplayOrder = 100000
bootGui.Parent = playerGui
-- Prefer the executor UI layer because some games replace PlayerGui contents.
pcall(function() if gethui then bootGui.Parent = gethui() end end)
local bootText = Instance.new("TextLabel")
bootText.Size = UDim2.new(0.8, 0, 0, 70)
bootText.Position = UDim2.new(0.1, 0, 0, 15)
bootText.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
bootText.BackgroundTransparency = 0.1
bootText.TextColor3 = Color3.new(1, 1, 1)
bootText.Font = Enum.Font.Gotham
bootText.TextSize = 16
bootText.TextWrapped = true
bootText.Text = "Home Defense build 15: starting..."
bootText.Parent = bootGui
local function bootMessage(message)
    if bootText.Parent then bootText.Text = message end
    print(message)
end
local function bounded(label, seconds, callback)
    local done, success, value = false, false, nil
    local thread = task.spawn(function()
        success, value = pcall(callback)
        done = true
    end)
    local deadline = os.clock() + seconds
    while not done and os.clock() < deadline do task.wait(0.05) end
    if not done then
        if task.cancel then pcall(task.cancel, thread) end
        return false, label .. " timed out after " .. seconds .. " seconds"
    end
    return success, value
end
local active, aimedAt, aimedSince, lastShot = true, nil, 0, 0
local aimedCharacter
local originalSensitivity = Input.MouseDeltaSensitivity
local function releaseFire()
    if fireHeld then pcall(function() mouse1release() end); fireHeld = false end
    if heldTool then pcall(function() heldTool:Deactivate() end); heldTool = nil end
end
local Aimbot
local nativeAimbot = false
local aimGui
local aimRenderName = "HomeDefenseAimRender"
local aimLock
local recoilRenderName = "HomeDefenseRecoilRender"
local recoilStatus, recoilCamera, recoilPrevious, recoilMessage
local localRigs = setmetatable({}, {__mode = "k"})
local function isSelfPlayer(player)
    if not player then return false end
    return player == LocalPlayer
        or (type(player.UserId) == "number" and player.UserId == LocalPlayer.UserId)
        or player.Name == LocalPlayer.Name
        or (player.Character ~= nil and player.Character == LocalPlayer.Character)
end
local function ownRig(instance)
    if LocalPlayer.Character then localRigs[LocalPlayer.Character] = true end
    local ancestor = instance
    while ancestor do
        if localRigs[ancestor] or ancestor == workspace.CurrentCamera then return ancestor end
        ancestor = ancestor.Parent
    end
end
local function localIgnoreList(camera)
    if LocalPlayer.Character then localRigs[LocalPlayer.Character] = true end
    local ignored = {camera}
    for rig in pairs(localRigs) do table.insert(ignored, rig) end
    return ignored
end
local function enemy(player)
    return not isSelfPlayer(player) and (not Config.TeamCheck
        or LocalPlayer.Neutral or player.Neutral
        or LocalPlayer.Team == nil or player.Team ~= LocalPlayer.Team)
end
local deadHumanoids = setmetatable({}, {__mode = "k"})
local watchedHumanoids = setmetatable({}, {__mode = "k"})
local restore
local onLocalDamage
local retaliation = {Shots = {}, Player = nil, Character = nil, Until = 0, DamageAt = nil, NextBind = 0}
local retaliateStatus
local function markDead(character, humanoid)
    deadHumanoids[humanoid] = true
    if aimLock and aimLock.Character == character then aimLock = nil end
    if character == LocalPlayer.Character or character == retaliation.Character then
        retaliation.Player, retaliation.Character, retaliation.DamageAt = nil, nil, nil
    end
    for part in pairs(originals) do if part:IsDescendantOf(character) then restore(part) end end
    if aimedCharacter == character or (aimedAt and aimedAt.Character == character) then
        aimedAt, aimedCharacter, aimedSince = nil, nil, 0
        releaseFire()
        releaseAt = nil
    end
end
local function living(player)
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not character or not humanoid then return nil end
    if not watchedHumanoids[humanoid] then
        watchedHumanoids[humanoid] = true
        local previousHealth = humanoid.Health
        connections[#connections + 1] = humanoid.Died:Connect(function() markDead(character, humanoid) end)
        connections[#connections + 1] = humanoid.HealthChanged:Connect(function(health)
            local lostHealth = health < previousHealth
            previousHealth = health
            if health <= 0 then markDead(character, humanoid) end
            if lostHealth and health > 0 and isSelfPlayer(player) and character == LocalPlayer.Character and onLocalDamage then
                onLocalDamage(character)
            end
        end)
        connections[#connections + 1] = humanoid.StateChanged:Connect(function(_, state)
            if state == Enum.HumanoidStateType.Dead then markDead(character, humanoid) end
        end)
    end
    if humanoid.Health <= 0 or humanoid:GetState() == Enum.HumanoidStateType.Dead then
        markDead(character, humanoid)
    end
    return not deadHumanoids[humanoid] and character or nil
end
local function retaliationNote(message)
    if retaliateStatus then retaliateStatus:Set("Retaliate: " .. message) end
end
local function selectRetaliation(now)
    if not Config.Retaliate or not retaliation.DamageAt then return end
    if now - retaliation.DamageAt < 0.05 then return end
    if not living(LocalPlayer) or retaliation.DamageCharacter ~= LocalPlayer.Character then retaliation.DamageAt = nil; return end
    local found, count = nil, 0
    for key, shot in pairs(retaliation.Shots) do
        if now - shot.Time > 0.75 then retaliation.Shots[key] = nil
        elseif shot.Time >= retaliation.DamageAt - 0.6 and shot.Time <= retaliation.DamageAt + 0.15
            and enemy(shot.Player) and living(shot.Player) == shot.Character then
            found, count = shot, count + 1
        end
    end
    if count == 1 then
        retaliation.Player, retaliation.Character, retaliation.Until = found.Player, found.Character, now + Config.RetaliateDuration
        retaliation.DamageAt = nil
        aimLock = nil
        retaliationNote("probable attacker: " .. found.Player.Name)
    elseif count > 1 then
        retaliation.DamageAt = nil
        retaliationNote("ambiguous incoming shots; skipped")
    elseif now - retaliation.DamageAt > 0.18 then
        retaliation.DamageAt = nil
        retaliationNote("damage source unknown; skipped")
    end
end
onLocalDamage = function(character)
    if not Config.Retaliate then return end
    retaliation.DamageAt, retaliation.DamageCharacter = os.clock(), character
end
local function retaliationTarget(now)
    if not Config.Retaliate or not retaliation.Player then return end
    if now > retaliation.Until or not living(LocalPlayer) or not enemy(retaliation.Player)
        or living(retaliation.Player) ~= retaliation.Character then
        if aimLock and aimLock.Player == retaliation.Player then aimLock = nil end
        retaliation.Player, retaliation.Character = nil, nil
        return
    end
    return retaliation.Player
end
local function updateRetaliation(now)
    if not Config.Retaliate then
        retaliation.Player, retaliation.Character, retaliation.DamageAt, retaliation.Shots = nil, nil, nil, {}
        return
    end
    living(LocalPlayer) -- Attach to the current Humanoid after each respawn.
    for key, shot in pairs(retaliation.Shots) do if now - shot.Time > 0.75 then retaliation.Shots[key] = nil end end
    if not retaliation.Remote and now >= retaliation.NextBind then
        retaliation.NextBind = now + 2
        local ok, remote = pcall(function()
            local storage = game:GetService("ReplicatedStorage")
            local engine = storage:FindFirstChild("ACS_Engine")
            local events = engine and engine:FindFirstChild("Events")
            return events and events:FindFirstChild("ServerBullet")
        end)
        if ok and remote and remote:IsA("RemoteEvent") then
            retaliation.Remote = remote
            connections[#connections + 1] = remote.OnClientEvent:Connect(function(shooter, origin, toward)
                if not active or not Config.Retaliate or not shooter or not shooter:IsA("Player") or not enemy(shooter)
                    or typeof(origin) ~= "Vector3" or typeof(toward) ~= "Vector3" then return end
                local character = living(LocalPlayer)
                local shooterCharacter = living(shooter)
                if not character or not shooterCharacter then return end
                local delta = toward - origin
                if delta.Magnitude < 0.001 then return end
                local direction, near = delta.Unit, false
                for _, name in ipairs({"Head", "HumanoidRootPart"}) do
                    local part = character:FindFirstChild(name)
                    if part then
                        local along = (part.Position - origin):Dot(direction)
                        if along >= 0 and along <= Config.MaxDistance
                            and (part.Position - (origin + direction * along)).Magnitude <= 4 then near = true; break end
                    end
                end
                if near then retaliation.Shots[shooter.UserId] = {Player = shooter, Character = shooterCharacter, Time = os.clock()} end
            end)
            retaliationNote("listening; incoming path + health loss required")
        else retaliationNote("ACS bullet signal unavailable") end
    end
    selectRetaliation(now)
end
restore = function(part)
    local old = originals[part]
    if old then
        pcall(function()
            part.Size = old.Size
            part.Transparency = old.Transparency
            part.CanCollide = old.CanCollide
            part.CanQuery = old.CanQuery
        end)
        originals[part] = nil
    end
end
local function unload()
    if not active then return end
    if configReady and Config.AutoSave then saveSettings(false) end
    active = false
    releaseFire()
    for _, connection in ipairs(connections) do connection:Disconnect() end
    pcall(function() RunService:UnbindFromRenderStep(aimRenderName) end)
    pcall(function() RunService:UnbindFromRenderStep(recoilRenderName) end)
    if aimGui then aimGui:Destroy() end
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
    bootGui:Destroy()
    env.HomeDefenseHelper = nil
end
env.HomeDefenseHelper = {Config = Config, Unload = unload,
    SaveSettings = function() return saveSettings(true) end,
    LoadSettings = function() releaseFire(); return loadSettings() end,
    ResetSettings = function() releaseFire(); return resetSettings() end}

bootMessage("Home Defense: loading aim support...")
local ok, result = bounded("Aim loader", 10, function()
    assert(type(loadstring) == "function", "loadstring unavailable")
    assert(Drawing and Drawing.new, "Drawing API unavailable")
    local source = game:HttpGet("https://raw.githubusercontent.com/Exunys/Aimbot-V3/main/src/Aimbot.lua")
    local chunk, err = loadstring(source)
    assert(chunk, err)
    return chunk()
end)
if ok then Aimbot = result or env.ExunysDeveloperAimbot end
if not ok or type(Aimbot) ~= "table" then
    warn("HomeDefense: using compatible aim mode: " .. tostring(result))
    local partial = env.ExunysDeveloperAimbot
    if type(partial) == "table" and partial.Exit then pcall(function() partial:Exit() end) end
    Aimbot = {Settings = {}, FOVSettings = {}, ClosestPlayerTracer = {}, Triggerbot = {},
        Load = function() end, Exit = function() end, Restart = function() end}
else
    nativeAimbot = true
end
Aimbot.Settings.Enabled = false
Aimbot.Settings.AliveCheck = true
Aimbot.Settings.TeamCheck = Config.TeamCheck
Aimbot.Settings.WallCheck = Config.WallCheck
Aimbot.Settings.LockPart = Config.AimPart
Aimbot.Settings.Sensitivity = Config.Smoothing
Aimbot.Settings.TriggerKey = keys.Aim
Aimbot.Settings.Toggle = false
Aimbot.FOVSettings.Radius = Config.Radius
Aimbot.FOVSettings.Visible = false
Aimbot.ClosestPlayerTracer.Enabled = false
-- Use our single-shot trigger loop so delayed callbacks cannot pile up.
Aimbot.Triggerbot.Enabled = false
local loaded, loadError = bounded("Aim initialization", 5, function() Aimbot.Load() end)
if not loaded then
    pcall(function() Aimbot:Exit() end)
    nativeAimbot = false
    Aimbot.Load, Aimbot.Exit, Aimbot.Restart = function() end, function() end, function() end
    warn("HomeDefense: compatible aim enabled: " .. tostring(loadError))
end

local mouse = LocalPlayer:GetMouse()
local function status(message)
    if triggerStatus and message ~= triggerStatus.LastMessage then
        triggerStatus.LastMessage = message
        triggerStatus:Set("Trigger: " .. message)
    end
end
local function playerForHit(instance)
    local ancestor = instance
    while ancestor and ancestor ~= workspace do
        if ancestor:IsA("Model") then
            local player = Players:GetPlayerFromCharacter(ancestor)
            if player then return player end
        end
        ancestor = ancestor.Parent
    end
end
local glassNames = {F=true,FLI=true,FRI=true,RLI=true,RRI=true,R=true,RV=true,Window=true,Windshield=true}
local function breakableGlass(part)
    if not Config.IgnoreBreakableGlass or not part:IsA("BasePart") then return false end
    return part.Name == "Glass" or part.Name == "DoorPane" or part.Name == "WindowGlass"
        or (glassNames[part.Name] == true and part.Material == Enum.Material.Glass)
end
local function hitboxVisible(part, character, camera)
    if not Config.HitboxWallCheck then return true end
    local params = RaycastParams.new()
    params.FilterType, params.IgnoreWater = Enum.RaycastFilterType.Exclude, true
    local ignored = localIgnoreList(camera)
    -- Exclude the target's enlarged geometry so it cannot hide a wall from this check.
    table.insert(ignored, character)
    for _ = 1, 12 do
        params.FilterDescendantsInstances = ignored
        local hit = workspace:Raycast(camera.CFrame.Position, part.Position - camera.CFrame.Position, params)
        if not hit then return true end
        local blocker = hit.Instance
        if not playerForHit(blocker) and (breakableGlass(blocker) or
            (blocker:IsA("BasePart") and not blocker.CanCollide and blocker.Name ~= "Armor")) then
            table.insert(ignored, blocker)
        else
            return false
        end
    end
    return false
end
local function triggerTarget()
    local camera = workspace.CurrentCamera
    if not camera then return end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.IgnoreWater = true
    local ignored = localIgnoreList(camera)
    params.FilterDescendantsInstances = ignored
    -- ACS fires along the centered crosshair. Auto must not switch between
    -- cursor and center when ADS or camera distance changes mid-shot.
    local centered = retaliationTarget(os.clock()) ~= nil or Config.TriggerPoint ~= "Cursor"
    local ray
    if centered then
        ray = camera:ViewportPointToRay(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
    else
        local location = Input:GetMouseLocation()
        ray = camera:ViewportPointToRay(location.X, location.Y)
    end
    for _ = 1, 12 do
        params.FilterDescendantsInstances = ignored
        local hit = workspace:Raycast(ray.Origin, ray.Direction * Config.MaxDistance, params)
        local target = hit and hit.Instance
        if not target then status("no player under crosshair"); return end
        local player = playerForHit(target)
        -- Resolve character ancestry before considering collision flags: limbs and
        -- accessory handles can be non-collidable but still belong to players.
        local selfRig = ownRig(target)
        if selfRig or isSelfPlayer(player) then
            table.insert(ignored, selfRig or (player and player.Character) or target)
            table.insert(ignored, target)
            status("skipping your character")
        elseif player then
            if not enemy(player) then status("teammate: " .. player.Name); return end
            local character = living(player)
            if not character then status("dead player: " .. player.Name); return end
            status("player: " .. player.Name)
            return player, character
        -- Match the saved ACS ray's treatment of non-collidable effects.
        -- Solid geometry and Armor remain blockers regardless of transparency.
        elseif breakableGlass(target) or (Config.TriggerIgnoreEffects and target:IsA("BasePart") and not target.CanCollide and target.Name ~= "Armor") then
            table.insert(ignored, target)
        else
            status("blocked by " .. target.Name)
            return
        end
    end
    status("too many effect layers; move crosshair")
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
        saveSettings(true)
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
    if input.KeyCode == keys.Recoil then flip("RecoilEnabled") end
    if input.KeyCode == keys.Retaliate then flip("Retaliate") end
end)

local elapsed = 0
connections[#connections + 1] = RunService.Heartbeat:Connect(function(dt)
    if not active then return end
    local now = os.clock()
    updateRetaliation(now)
    local retaliatingAt = retaliationTarget(now)
    local fireRequested = Config.Trigger or retaliatingAt ~= nil
    if releaseAt and now >= releaseAt then releaseFire(); releaseAt = nil end
    local blocked = capturingKey or Input:GetFocusedTextBox() or (Rayfield and Rayfield:IsVisible())
    local equippedTool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
    local target, targetCharacter
    if fireRequested and equippedTool and not blocked then target, targetCharacter = triggerTarget() end
    if retaliatingAt and (not target or target.UserId ~= retaliatingAt.UserId) then target, targetCharacter = nil, nil end
    if not fireRequested or blocked then
        releaseFire()
        status(Config.Trigger and "paused: hide menu to fire" or "off")
    elseif not equippedTool then
        releaseFire()
        status("equip a weapon")
    end
    if target ~= aimedAt or targetCharacter ~= aimedCharacter then
        aimedAt, aimedCharacter, aimedSince = target, targetCharacter, now
    end
    if target and isSelfPlayer(target) then
        target, aimedAt = nil, nil
        releaseFire()
        status("self-target rejected")
    end
    if not target or living(target) ~= targetCharacter then
        target, aimedAt, aimedCharacter = nil, nil, nil
        releaseFire()
    end
    if target and not (fireHeld or heldTool)
        and not isSelfPlayer(target) and enemy(target) and living(target) == targetCharacter
        and now - aimedSince >= Config.TriggerDelay and now - lastShot >= Config.FireInterval then
        local tool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
        local mode = Config.TriggerMode
        local canClick = type(mouse1press) == "function" and type(mouse1release) == "function"
        local canSingleClick = type(mouse1click) == "function"
        if mode == "Auto" then mode = (canClick or canSingleClick) and "Mouse" or "Tool" end
        if not tool then
            releaseFire()
            status("equip a weapon")
        elseif mode == "Mouse" and (canClick or canSingleClick) then
            local fired, err = pcall(function()
                if canClick then
                    mouse1press(); fireHeld = true
                    releaseAt = Config.TriggerPattern ~= "Hold" and now + math.clamp(Config.TriggerPressTime, 0.02, 0.2) or nil
                else mouse1click() end
            end)
            status(fired and ("clicking at " .. target.Name) or ("input failed: " .. tostring(err)))
            lastShot = now
        elseif mode == "Tool" and tool then
            local fired, err = pcall(function()
                tool:Activate(); heldTool = tool
                releaseAt = Config.TriggerPattern ~= "Hold" and now + math.clamp(Config.TriggerPressTime, 0.02, 0.2) or nil
            end)
            status(fired and ("activating " .. tool.Name) or ("tool failed: " .. tostring(err)))
            lastShot = now
        else
            status(mode == "Mouse" and "executor mouse input unavailable; try Tool mode" or "equip a weapon")
        end
    end
    elapsed = elapsed + dt
    if elapsed < 0.1 then return end
    elapsed = 0
    if configReady and Config.AutoSave and now >= nextConfigCheck then
        nextConfigCheck = now + 1
        saveSettings(false)
    end
    -- One local render path drives both hold-to-aim and always-on aiming.
    Aimbot.Settings.Enabled = false
    Aimbot.Settings.TeamCheck = Config.TeamCheck
    Aimbot.Settings.WallCheck = Config.WallCheck
    Aimbot.Settings.LockPart = Config.AimPart
    Aimbot.Settings.Sensitivity = Config.Smoothing
    Aimbot.FOVSettings.Radius = Config.Radius
    Aimbot.FOVSettings.Visible = false
    Aimbot.ClosestPlayerTracer.Enabled = false
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
        local character = not isSelfPlayer(player) and living(player)
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local camera = workspace.CurrentCamera
        local inRange = root and camera and (root.Position - camera.CFrame.Position).Magnitude <= Config.MaxDistance
        if inRange and enemy(player) and Config.Hitboxes then
            local parts = {}
            if Config.HitboxPart == "Head" or Config.HitboxPart == "Both" then
                local head = character:FindFirstChild("Head")
                if head then table.insert(parts, head) end
            end
            if Config.HitboxPart == "Torso" or Config.HitboxPart == "Both" then
                local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
                if torso then table.insert(parts, torso) end
            end
            for _, part in ipairs(parts) do
                if part:IsA("BasePart") and hitboxVisible(part, character, camera) then
                    keepParts[part] = true
                    originals[part] = originals[part] or {Size = part.Size, Transparency = part.Transparency,
                        CanCollide = part.CanCollide, CanQuery = part.CanQuery}
                    local size, original = math.clamp(Config.HitboxSize, 2, 20), originals[part].Size
                    part.Size = Vector3.new(math.max(original.X, size), math.max(original.Y, size), math.max(original.Z, size))
                    part.Transparency = math.clamp(Config.HitboxTransparency, 0, 0.95)
                    part.CanQuery = true
                end
            end
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
aimGui = Instance.new("ScreenGui")
aimGui.Name, aimGui.ResetOnSpawn, aimGui.IgnoreGuiInset = "HomeDefenseAimVisuals", false, true
aimGui.DisplayOrder, aimGui.Parent = 99998, playerGui
pcall(function() if gethui then aimGui.Parent = gethui() end end)
local aimCircle = Instance.new("Frame")
aimCircle.Name, aimCircle.AnchorPoint = "AimCircle", Vector2.new(0.5, 0.5)
aimCircle.BackgroundTransparency, aimCircle.BorderSizePixel, aimCircle.Parent = 1, 0, aimGui
local corner = Instance.new("UICorner")
corner.CornerRadius, corner.Parent = UDim.new(0.5, 0), aimCircle
local circleStroke = Instance.new("UIStroke")
circleStroke.Thickness, circleStroke.Color, circleStroke.Parent = 1.5, Color3.new(1, 1, 1), aimCircle
local tracer = Instance.new("Frame")
tracer.AnchorPoint, tracer.BorderSizePixel, tracer.Visible = Vector2.new(0, 0.5), 0, false
tracer.BackgroundColor3, tracer.Parent = Color3.fromRGB(255, 100, 100), aimGui
local function renderAim(dt)
    if not active then return end
    local camera = workspace.CurrentCamera
    if not camera then return end
    local retaliatingAt = retaliationTarget(os.clock())
    local cursor = Input:GetMouseLocation()
    -- GUI and target projection both use viewport coordinates, with no top-bar inset.
    -- Always-on is centered even when an older saved setting says Cursor.
    if retaliatingAt or Config.AimAlways or Config.AimOrigin == "Center" or (Config.AimOrigin == "Auto" and
        Input.MouseBehavior == Enum.MouseBehavior.LockCenter) then
        cursor = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
    end
    aimCircle.Visible = Config.Aim and Config.ShowFOV
    aimCircle.Position = UDim2.fromOffset(cursor.X, cursor.Y)
    aimCircle.Size = UDim2.fromOffset(Config.Radius * 2, Config.Radius * 2)
    circleStroke.Color = Color3.new(1, 1, 1)
    tracer.Visible = false
    if not Config.Aim and not retaliatingAt then aimLock = nil; return end
    if capturingKey or Input:GetFocusedTextBox() then aimLock = nil; return end
    if Config.PauseAimWithMenu and Rayfield and Rayfield:IsVisible() then aimLock = nil; return end
    if not Config.AimAlways and not retaliatingAt then
        local held = keys.Aim.EnumType == Enum.UserInputType and Input:IsMouseButtonPressed(keys.Aim)
            or keys.Aim.EnumType == Enum.KeyCode and Input:IsKeyDown(keys.Aim)
        if not held then aimLock = nil; return end
    end
    local function candidate(player, unrestricted)
        local character = enemy(player) and living(player)
        if not character then return end
        local names = Config.AimPart == "Auto" and {"Head", "UpperTorso", "Torso", "HumanoidRootPart"}
            or {Config.AimPart, "HumanoidRootPart"}
        for _, name in ipairs(names) do
            local part = character:FindFirstChild(name)
            if part then
            local point, visible = camera:WorldToViewportPoint(part.Position)
            local screenDistance = (Vector2.new(point.X, point.Y) - cursor).Magnitude
            if unrestricted or (visible and screenDistance <= Config.Radius) then
                local clear = true
                if Config.WallCheck or unrestricted then
                    local params = RaycastParams.new()
                    params.FilterType = Enum.RaycastFilterType.Exclude
                    local ignored = localIgnoreList(camera)
                    clear = false
                    for _ = 1, 12 do
                        params.FilterDescendantsInstances = ignored
                        local hit = workspace:Raycast(camera.CFrame.Position, part.Position - camera.CFrame.Position, params)
                        if not hit or hit.Instance:IsDescendantOf(character) then clear = true; break end
                        local blocker = hit.Instance
                        if not playerForHit(blocker) and (breakableGlass(blocker) or
                            (Config.AimIgnoreEffects and blocker:IsA("BasePart") and not blocker.CanCollide and blocker.Name ~= "Armor")) then
                            table.insert(ignored, blocker)
                        else
                            break
                        end
                    end
                end
                if clear then
                    return {Part = part, Player = player, Character = character, Distance = screenDistance}
                end
            end
            end
        end
    end
    local selected
    if retaliatingAt then selected = candidate(retaliatingAt, true)
    elseif Config.StickyAim and aimLock and aimLock.Player.Character == aimLock.Character then
        selected = candidate(aimLock.Player)
    end
    if not selected and not retaliatingAt then
        for _, player in ipairs(Players:GetPlayers()) do
            local option = candidate(player)
            if option and (not selected or option.Distance < selected.Distance) then selected = option end
        end
    end
    -- Recheck after selection so a death or respawn cannot leave a stale part locked.
    if selected and living(selected.Player) ~= selected.Character then selected = nil end
    aimLock = selected
    if selected then
        local closest = selected.Part
        local aimPosition = closest.Position
        if Config.AimPrediction then
            local velocity = closest.AssemblyLinearVelocity
            if velocity then
                local speed = velocity.Magnitude
                if speed > 120 then velocity = velocity * (120 / speed) end
                aimPosition = aimPosition + velocity * math.clamp(Config.PredictionTime, 0, 0.25)
            end
        end
        circleStroke.Color = Color3.fromRGB(255, 100, 100)
        if Config.Tracer then
            local point = camera:WorldToViewportPoint(aimPosition)
            local delta = Vector2.new(point.X, point.Y) - cursor
            tracer.Visible, tracer.Position = true, UDim2.fromOffset(cursor.X, cursor.Y)
            tracer.Size = UDim2.fromOffset(delta.Magnitude, 1)
            tracer.Rotation = math.deg(math.atan2(delta.Y, delta.X))
        end
        local goal = CFrame.lookAt(camera.CFrame.Position, aimPosition)
        local alpha = Config.Smoothing <= 0 and 1 or 1 - math.exp(-math.max(dt, 0) / Config.Smoothing)
        camera.CFrame = camera.CFrame:Lerp(goal, alpha)
    end
end
local function recoilNote(message)
    if recoilStatus and recoilMessage ~= message then recoilStatus:Set("Recoil: " .. message) end
    recoilMessage = message
end
local function renderRecoil()
    local camera = workspace.CurrentCamera
    if not active or not camera then return end
    local current = camera.CFrame
    if camera ~= recoilCamera then recoilCamera, recoilPrevious = camera, current; return end
    local tool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
    local firing = Input:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
        or fireHeld or heldTool ~= nil or (lastShot > 0 and os.clock() - lastShot < 0.12)
    local blocked = not Config.RecoilEnabled or not tool or not firing or capturingKey
        or Input:GetFocusedTextBox() or (Rayfield and Rayfield:IsVisible())
    if blocked then
        recoilPrevious = current
        recoilNote(not Config.RecoilEnabled and "Off" or (not tool and "Equip a weapon" or "Ready - camera only"))
        return
    end
    -- Do not damp deliberate mouse movement. No weapon modules, equip state,
    -- shared configuration or game input bindings are changed by this method.
    if Input:GetMouseDelta().Magnitude > 0.05 then
        recoilPrevious = current
        recoilNote("Paused while moving mouse")
        return
    end
    local multiplier = 1 - math.clamp(Config.RecoilStrength, 0, 100) / 100
    local rotation = recoilPrevious.Rotation:Lerp(current.Rotation, multiplier)
    camera.CFrame = CFrame.new(current.Position) * rotation
    recoilPrevious = camera.CFrame
    recoilNote("Camera smoothing: " .. Config.RecoilStrength .. "%")
end
-- Run after the camera and most weapon viewmodel updates.
RunService:BindToRenderStep(recoilRenderName, Enum.RenderPriority.Last.Value, renderRecoil)
RunService:BindToRenderStep(aimRenderName, Enum.RenderPriority.Last.Value + 1, renderAim)
-- Self-contained UI adapter used if Rayfield or its remote asset cannot load.
local function fallbackLibrary(reason)
    local library = {visible = true, Flags = {}, IsFallback = true}
    local gui = Instance.new("ScreenGui")
    gui.Name, gui.ResetOnSpawn, gui.DisplayOrder = "HomeDefenseFallback", false, 99999
    gui.Parent = playerGui
    pcall(function() if gethui then gui.Parent = gethui() end end)
    local panel = Instance.new("Frame")
    panel.Size, panel.Position = UDim2.fromScale(0.7, 0.75), UDim2.fromScale(0.15, 0.12)
    panel.BackgroundColor3, panel.Parent = Color3.fromRGB(24, 25, 31), gui
    local title = Instance.new("TextLabel")
    title.Size, title.BackgroundTransparency = UDim2.new(1, -20, 0, 38), 1
    title.Text, title.TextSize = "Home Defense - compatible menu | F1 hide/show", 18
    title.TextColor3, title.Parent = Color3.new(1, 1, 1), panel
    local tabs = Instance.new("ScrollingFrame")
    tabs.Size, tabs.Position = UDim2.new(1, -16, 0, 36), UDim2.fromOffset(8, 40)
    tabs.BackgroundTransparency, tabs.CanvasSize = 1, UDim2.fromOffset(0, 0)
    tabs.AutomaticCanvasSize, tabs.ScrollBarThickness = Enum.AutomaticSize.X, 3
    tabs.Parent = panel
    local tabLayout = Instance.new("UIListLayout")
    tabLayout.FillDirection, tabLayout.Padding = Enum.FillDirection.Horizontal, UDim.new(0, 4)
    tabLayout.Parent = tabs
    local bodies, index = {}, 0
    function library:IsVisible() return self.visible end
    function library:SetVisibility(value) self.visible = value; gui.Enabled = value end
    function library:Destroy() gui:Destroy() end
    function library:Notify(data) bootMessage(data.Title .. ": " .. data.Content) end
    function library:LoadConfiguration() end
    function library:CreateWindow()
        return {CreateTab = function(_, name)
            index = index + 1
            local body = Instance.new("ScrollingFrame")
            body.Size, body.Position = UDim2.new(1, -16, 1, -90), UDim2.fromOffset(8, 82)
            body.BackgroundTransparency, body.ScrollBarThickness = 1, 5
            body.CanvasSize, body.AutomaticCanvasSize = UDim2.fromOffset(0, 0), Enum.AutomaticSize.Y
            body.Visible, body.Parent = index == 1, panel
            table.insert(bodies, body)
            local layout = Instance.new("UIListLayout")
            layout.SortOrder, layout.Padding, layout.Parent = Enum.SortOrder.LayoutOrder, UDim.new(0, 5), body
            local tabButton = Instance.new("TextButton")
            tabButton.Size, tabButton.Text = UDim2.fromOffset(140, 30), name
            tabButton.BackgroundColor3, tabButton.TextColor3 = Color3.fromRGB(50, 52, 64), Color3.new(1, 1, 1)
            tabButton.Parent = tabs
            connections[#connections + 1] = tabButton.MouseButton1Click:Connect(function()
                for _, other in ipairs(bodies) do other.Visible = other == body end
            end)
            local order = 0
            local function row(name)
                order = order + 1
                local frame = Instance.new("Frame")
                frame.Name, frame.Size = name, UDim2.new(1, -8, 0, 44)
                frame.LayoutOrder, frame.BackgroundColor3 = order, Color3.fromRGB(36, 38, 47)
                frame.Parent = body
                local label = Instance.new("TextLabel")
                label.Name, label.Text = "Title", name
                label.Size, label.Position = UDim2.new(1, -180, 1, 0), UDim2.fromOffset(10, 0)
                label.BackgroundTransparency, label.TextSize = 1, 14
                label.TextXAlignment, label.TextColor3 = Enum.TextXAlignment.Left, Color3.new(1, 1, 1)
                label.TextWrapped, label.Parent = true, frame
                return frame
            end
            local function button(parent, text, width)
                local item = Instance.new("TextButton")
                item.Size, item.Position = UDim2.fromOffset(width or 150, 30), UDim2.new(1, -(width or 150) - 10, 0.5, -15)
                item.Text, item.TextSize = text, 13
                item.TextColor3, item.BackgroundColor3 = Color3.new(1, 1, 1), Color3.fromRGB(60, 63, 78)
                item.Parent = parent
                return item
            end
            local tab = {}
            function tab:CreateToggle(settings)
                local frame = row(settings.Name)
                local switch = button(frame, "", 48)
                switch.Name = "Switch"
                local control = {}
                function control:Set(value)
                    settings.CurrentValue = value
                    switch.Text = value and "ON" or "OFF"
                    settings.Callback(value)
                end
                switch.Text = settings.CurrentValue and "ON" or "OFF"
                connections[#connections + 1] = switch.MouseButton1Click:Connect(function() control:Set(not settings.CurrentValue) end)
                return control
            end
            function tab:CreateButton(settings)
                local frame = row(settings.Name)
                local press = button(frame, "Run", 60)
                connections[#connections + 1] = press.MouseButton1Click:Connect(settings.Callback)
                return {}
            end
            function tab:CreateSlider(settings)
                local frame = row(settings.Name)
                local input = Instance.new("TextBox")
                input.Size, input.Position = UDim2.fromOffset(100, 30), UDim2.new(1, -110, 0.5, -15)
                input.Text, input.TextSize = tostring(settings.CurrentValue), 14
                input.TextColor3, input.BackgroundColor3 = Color3.new(1, 1, 1), Color3.fromRGB(60, 63, 78)
                input.Parent = frame
                local control = {}
                function control:Set(value)
                    value = math.clamp(value, settings.Range[1], settings.Range[2])
                    settings.CurrentValue, input.Text = value, tostring(value)
                    settings.Callback(value)
                end
                connections[#connections + 1] = input.FocusLost:Connect(function()
                    local value = tonumber(input.Text)
                    if value then control:Set(value) end
                    input.Text = tostring(settings.CurrentValue)
                end)
                return control
            end
            function tab:CreateDropdown(settings)
                local frame = row(settings.Name)
                local current = 1
                for i, value in ipairs(settings.Options) do if value == settings.CurrentOption[1] then current = i end end
                local select = button(frame, settings.Options[current] .. " >")
                local control = {}
                function control:Set(options)
                    for i, option in ipairs(settings.Options) do if option == options[1] then current = i end end
                    select.Text = settings.Options[current] .. " >"
                    settings.Callback({settings.Options[current]})
                end
                connections[#connections + 1] = select.MouseButton1Click:Connect(function()
                    current = current % #settings.Options + 1
                    select.Text = settings.Options[current] .. " >"
                    settings.Callback({settings.Options[current]})
                end)
                return control
            end
            function tab:CreateLabel(text)
                local frame = row(text)
                frame.Title.Size = UDim2.new(1, -20, 1, 0)
                return {Set = function(_, value) frame.Title.Text = value end}
            end
            function tab:CreateParagraph(settings)
                local frame = row(settings.Title)
                frame.Size = UDim2.new(1, -8, 0, 96)
                frame.Title.Size = UDim2.new(1, -20, 1, 0)
                frame.Title.Text = settings.Title .. "\n" .. settings.Content
            end
            function tab:CreateKeybind(settings)
                local label = self:CreateLabel(settings.Name .. ": " .. settings.CurrentKeybind)
                return {Set=function(_,value)
                    label:Set(settings.Name .. ": " .. value)
                    settings.Callback(value)
                end}
            end
            return tab
        end}
    end
    bootMessage("Rayfield unavailable (" .. tostring(reason) .. "). Compatible menu ready.")
    return library
end
-- Configuration flags are unique; saved Rayfield values flow through callbacks.
local guiOK, guiError = pcall(function()
    bootMessage("Home Defense: loading Rayfield menu...")
    local windowSettings = {
        Name = "Home Defense", LoadingTitle = "Home Defense", LoadingSubtitle = "professorzycro",
        Theme = "Default", ShowText = "Home Defense", DisableRayfieldPrompts = true,
        -- Our handler supports rebinding the menu without rebuilding the window.
        ToggleUIKeybind = Enum.KeyCode.F15,
        ConfigurationSaving = {Enabled = false},
        Discord = {Enabled = false}, KeySystem = false,
    }
    local menuOK, window = bounded("Rayfield startup", 15, function()
        Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
        return Rayfield:CreateWindow(windowSettings)
    end)
    if not menuOK then
        if Rayfield then pcall(function() Rayfield:Destroy() end) end
        Rayfield = fallbackLibrary(window)
        window = Rayfield:CreateWindow(windowSettings)
    end
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
        if not row then
            warn("HomeDefense: inline key row unavailable: " .. name)
            return false
        end
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
            Callback = function(value)
                Config[property] = value
                if property == "AutoSave" then saveSettings(true) end
            end})
        uiToggles[property] = control
        configControls[property] = control
        if action then
            local attached, err = pcall(attachKey, name, action)
            if not attached then warn("HomeDefense inline key: " .. tostring(err)) end
        end
    end
    local function slider(tab, name, property, minimum, maximum, increment)
        local control = tab:CreateSlider({Name = name, Range = {minimum, maximum}, Increment = increment or 1,
            CurrentValue = Config[property], Flag = "HD_" .. property,
            Callback = function(value) Config[property] = value end})
        configControls[property] = control
        return control
    end
    local aim = window:CreateTab("Aim")
    toggle(aim, "Aimbot", "Aim", "Aim")
    toggle(aim, "Always on (no hold required)", "AimAlways")
    toggle(aim, "Keep current target while valid", "StickyAim")
    toggle(aim, "Pause aim while menu open", "PauseAimWithMenu")
    configControls.AimOrigin = aim:CreateDropdown({Name = "Aim circle position", Options = {"Auto", "Center", "Cursor"},
        CurrentOption = {Config.AimOrigin}, Flag = "HD_AimOrigin",
        Callback = function(options) Config.AimOrigin = options[1] end})
    toggle(aim, "Team check", "TeamCheck")
    toggle(aim, "Wall check", "WallCheck")
    toggle(aim, "Skip non-collidable effects", "AimIgnoreEffects")
    local radiusControl = slider(aim, "Aim radius (pixels)", "Radius", 20, 600)
    local smoothingControl = slider(aim, "Smoothing (seconds)", "Smoothing", 0, 0.5, 0.01)
    toggle(aim, "Show aim circle", "ShowFOV")
    toggle(aim, "Target tracer", "Tracer")
    local aimPartControl = aim:CreateDropdown({Name = "Aim part", Options = {"Auto", "Head", "UpperTorso", "HumanoidRootPart"},
        CurrentOption = {Config.AimPart}, Flag = "HD_AimPart",
        Callback = function(options)
            if Config.AimPart ~= options[1] then
                Config.AimPart = options[1]
                Aimbot.Settings.LockPart = Config.AimPart
                Input.MouseDeltaSensitivity = originalSensitivity
                Aimbot.Restart()
            end
        end})
    configControls.AimPart = aimPartControl
    toggle(aim, "Movement prediction", "AimPrediction")
    slider(aim, "Prediction lead (seconds)", "PredictionTime", 0, 0.25, 0.01)
    aim:CreateButton({Name = "Apply responsive aim preset", Callback = function()
        Config.Aim, Config.StickyAim, Config.AimPart = true, true, "Auto"
        Config.Radius, Config.Smoothing = 180, 0.03
        aimLock = nil
        if uiToggles.Aim then uiToggles.Aim:Set(true) end
        if uiToggles.StickyAim then uiToggles.StickyAim:Set(true) end
        if radiusControl then radiusControl:Set(180) end
        if smoothingControl then smoothingControl:Set(0.03) end
        if aimPartControl then aimPartControl:Set({"Auto"}) end
    end})
    aim:CreateParagraph({Title = "Tracking", Content = "Auto prefers a visible head, then torso/root. Target retention ends on death, obstruction, team change or leaving the circle. Lower smoothing responds faster; zero snaps. Prediction is optional fixed-time movement lead, not a weapon-specific ballistic solution."})
    local combat = window:CreateTab("Trigger & Hitboxes")
    toggle(combat, "Triggerbot", "Trigger", "Trigger")
    toggle(combat, "Skip non-collidable effects", "TriggerIgnoreEffects")
    triggerStatus = combat:CreateLabel("Trigger: off")
    configControls.TriggerMode = combat:CreateDropdown({Name = "Fire method", Options = {"Auto", "Mouse", "Tool"},
        CurrentOption = {Config.TriggerMode}, Flag = "HD_TriggerMode",
        Callback = function(options) releaseFire(); Config.TriggerMode = options[1] end})
    configControls.TriggerPoint = combat:CreateDropdown({Name = "Crosshair position", Options = {"Auto", "Center", "Cursor"},
        CurrentOption = {Config.TriggerPoint}, Flag = "HD_TriggerPoint",
        Callback = function(options) Config.TriggerPoint = options[1] end})
    configControls.TriggerPattern = combat:CreateDropdown({Name = "Firing pattern", Options = {"Pulse", "Hold"},
        CurrentOption = {Config.TriggerPattern}, Flag = "HD_TriggerPattern",
        Callback = function(options) releaseFire(); releaseAt = nil; Config.TriggerPattern = options[1] end})
    slider(combat, "Mouse press length (seconds)", "TriggerPressTime", 0.02, 0.2, 0.01)
    local delayControl = slider(combat, "Trigger delay (seconds)", "TriggerDelay", 0, 1, 0.01)
    local intervalControl = slider(combat, "Shot interval (seconds)", "FireInterval", 0.03, 1, 0.01)
    combat:CreateButton({Name = "Apply fast trigger preset", Callback = function()
        Config.TriggerDelay, Config.FireInterval = 0, 0.06
        if delayControl then delayControl:Set(0) end
        if intervalControl then intervalControl:Set(0.06) end
        aimedAt, aimedSince, lastShot = nil, 0, 0
    end})
    toggle(combat, "Expand enemy hitboxes", "Hitboxes", "Hitboxes")
    toggle(combat, "Hitbox wall check", "HitboxWallCheck")
    configControls.HitboxPart = combat:CreateDropdown({Name = "Expand body part", Options = {"Head", "Torso", "Both"},
        CurrentOption = {Config.HitboxPart}, Flag = "HD_HitboxPart",
        Callback = function(options) Config.HitboxPart = options[1] end})
    slider(combat, "Hitbox size (studs)", "HitboxSize", 2, 20)
    slider(combat, "Expanded part transparency", "HitboxTransparency", 0, 0.95, 0.05)
    combat:CreateParagraph({Title = "Hitbox compatibility", Content = "Expands recognized Head/Torso parts and enables ray queries. Collision settings stay original. Resets on death, team/range changes, disable or unload. Client-side geometry changes may still be rejected by server hit validation."})
    slider(combat, "Trigger / hitbox range (studs)", "MaxDistance", 50, 5000, 50)
    combat:CreateParagraph({Title = "Trigger troubleshooting", Content = "Auto crosshair uses screen center for ACS. Choose Hold for automatic weapons; Pulse for semi-auto. Hide the menu and equip a weapon. Auto prefers mouse input; Tool is a fallback. Status reports detection/input attempts, not confirmed damage."})
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
    toggle(visuals, "Treat breakable glass as passable", "IgnoreBreakableGlass")
    toggle(visuals, "Fullbright", "Fullbright")
    toggle(visuals, "Override camera FOV", "CameraOverride")
    slider(visuals, "Camera FOV", "CameraFOV", 40, 120)
    local recoilTab = window:CreateTab("Recoil")
    toggle(recoilTab, "Recoil dampener", "RecoilEnabled", "Recoil")
    slider(recoilTab, "Camera smoothing (%)", "RecoilStrength", 0, 100, 5)
    recoilStatus = recoilTab:CreateLabel("Recoil: Off")
    recoilTab:CreateParagraph({Title = "Camera-only dampener", Content = "Disabled by default. Smooths camera rotation while firing with the mouse stationary; pauses during mouse movement. Leaves weapon settings, animation recoil, spread and equip logic alone. Reloading restores the previous version's recoil settings."})
    local retaliateTab = window:CreateTab("Retaliate")
    toggle(retaliateTab, "Retaliate (best effort)", "Retaliate", "Retaliate")
    slider(retaliateTab, "Retaliation tracking time (seconds)", "RetaliateDuration", 0.5, 4, 0.1)
    retaliateStatus = retaliateTab:CreateLabel("Retaliate: Off")
    retaliateTab:CreateParagraph({Title = "How attribution works", Content = "Turns aim toward a probable attacker after health loss and a recent incoming bullet path. Does not teleport. Fires only when the crosshair hits that attacker, with a weapon equipped. Respects teams, walls and death. Client signals do not confirm damage ownership: fall damage near gunfire can be misattributed; ambiguous or unknown sources are skipped. Hide the menu to allow firing."})
    local settings = window:CreateTab("Settings")
    toggle(settings, "Auto-save config to workspace", "AutoSave")
    configStatus = settings:CreateLabel(lastConfigMessage)
    settings:CreateParagraph({Title = "Workspace file", Content = "ProfessorZycro/HomeDefense-config.json inside your executor workspace. Includes feature settings and keybinds. Loads at startup and works in the compatible menu too."})
    settings:CreateButton({Name = "Save config now", Callback = function() saveSettings(true) end})
    settings:CreateButton({Name = "Load saved config", Callback = function() releaseFire(); aimLock=nil; loadSettings() end})
    settings:CreateButton({Name = "Reset and save defaults", Callback = function() releaseFire(); aimLock=nil; resetSettings() end})
    settings:CreateParagraph({Title = "Home Defense v15", Content = "Click key badges to rebind; Escape cancels. F1 toggles the menu. Always-on uses screen center in Auto mode. Menu pause for aim is optional; trigger pauses while the menu is open. Live status explains target selection."})
    settings:CreateButton({Name = "Hide / show menu", Callback = function() Rayfield:SetVisibility(not Rayfield:IsVisible()) end})
    pcall(attachKey, "Hide / show menu", "Menu")
    keyControls.Unload = settings:CreateKeybind({Name = "Unload key", CurrentKeybind = keys.Unload.Name, CallOnChange = true,
        HoldToInteract = false, Flag = "HD_UnloadKey", Callback = function(value)
            if type(value) == "string" and Enum.KeyCode[value] then keys.Unload = Enum.KeyCode[value] end
        end})
    settings:CreateButton({Name = "Unload and restore changes", Callback = unload})
    configReady = true
    Rayfield:SetVisibility(true)
    if Rayfield.IsFallback then
        bootMessage("Home Defense build 15: compatible menu loaded. F1 hide/show. Type numeric values; click dropdowns to cycle choices. Workspace config is available in Settings.")
    else
        bootMessage("Home Defense build 15: Rayfield loaded. F1 toggles the menu by default. " .. (nativeAimbot and "" or "Compatible aim mode active."))
    end
    task.delay(7, function() if bootGui.Parent then bootGui:Destroy() end end)
end)
if not guiOK then
    releaseFire()
    Config.Trigger, Config.Aim, Config.Hitboxes = false, false, false
    bootMessage("Home Defense menu failed: " .. tostring(guiError) .. " — send this message to debug.")
    warn("HomeDefense menu failed: " .. tostring(guiError))
end

