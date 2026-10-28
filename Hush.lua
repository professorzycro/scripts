-- HUSH helper. Uses compatible aim when Exunys/Drawing is unavailable.
-- Aimbot credit: Exunys https://github.com/Exunys/Aimbot-V3 (CC0-1.0).
-- Generic player-character support; not tested against this game's weapons.
-- Rayfield credit: Sirius https://docs.sirius.menu/rayfield
-- Defaults: RMB aim | F6 trigger | F7 hitboxes | F8 ESP | End unload | F1 menu | F4 recoil
local env = getgenv()
if env.HushHelper then pcall(env.HushHelper.Unload) end

local Config = {
    Aim = true, AimAlways = false, TeamCheck = true, WallCheck = true, AimIgnoreEffects = true,
    AimOrigin = "Auto", PauseAimWithMenu = false,
    AimPart = "Auto", Radius = 150, Smoothing = 0.04,
    StickyAim = true, AimPrediction = false, PredictionTime = 0.08,
    Trigger = false, TriggerDelay = 0, FireInterval = 0.06,
    TriggerMode = "Auto", TriggerPoint = "Auto", TriggerPattern = "Pulse", TriggerPressTime = 0.04,
    IgnoreBreakableGlass = true,
    TriggerIgnoreEffects = true,
    Hitboxes = false, HitboxSize = 6, HitboxPart = "Head", HitboxTransparency = 0.75, HitboxDistance = 1500,
    HitboxWallCheck = true, Highlights = false,
    MaxDistance = 1500, ShowFOV = true, Tracer = false,
    ESPNames = true, ESPHealth = true, ESPDistance = true, ESPTeamColors = false,
    ESPTeamCheck = true, ESPThroughWalls = true, ESPBoxes = false,
    ESPDistanceLimit = 1500, ESPTextSize = 14, Fullbright = false,
    Freecam = false, FreecamSpeed = 40, FreecamSensitivity = 0.15,
    CameraOverride = false, CameraFOV = 80,
    RecoilEnabled = false, RecoilStrength = 60,
    MotherESP=false, MonsterESP=false, WatcherESP=false, SentryESP=false, LootESP=false, SupplyESP=false, ExitESP=false, TrapESP=false,
    LockboxESP=true, LootBagESP=true,
    LootWeapons=true, LootAttachments=true, LootMedical=true, LootMaterials=true,
    LootAmmo=true, LootFood=true, LootGear=true, LootCodes=true, LootOther=true,
    DeepwellESP=false, CraftingESP=false, BountyESP=false,
    CodeESP=false,
    NoiseCeiling=false,
    MonsterESPRange=1200, ItemESPRange=1200, WorldESPMax=150, ThreatWarning=true,
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
local clearHush = function() end
local configControls, keyControls = {}, {}
local espFolder
local function destroyESP(visual)
    for _,name in ipairs({"Highlight","Tag","Box"}) do
        if visual[name] then pcall(function() visual[name]:Destroy() end) end
    end
end
local function clearESP()
    for player,visual in pairs(highlights) do destroyESP(visual); highlights[player]=nil end
end
local function ensureESPFolder()
    if not espFolder or not espFolder.Parent then
        espFolder=Instance.new("Folder")
        espFolder.Name,espFolder.Parent="HushESPObjects",workspace
    end
    return espFolder
end
local capturingKey, triggerStatus, fireHeld, heldTool, releaseAt
local keyButtons = {}
local keys = {Aim = Enum.UserInputType.MouseButton2, Trigger = Enum.KeyCode.F6,
    Hitboxes = Enum.KeyCode.F7, ESP = Enum.KeyCode.F8, Unload = Enum.KeyCode.End,
    Menu = Enum.KeyCode.F1, Recoil = Enum.KeyCode.F4, Freecam = Enum.KeyCode.F5}
local HttpService = game:GetService("HttpService")
local keyDefaults = {}
for action, key in pairs(keys) do keyDefaults[action] = key.Name end
local configPath = "ProfessorZycro/Hush-config.json"
local configReady, configStatus, lastConfigSignature, nextConfigCheck = false, nil, nil, 0
local lastConfigMessage = "No saved workspace config loaded"
local configRanges = {Radius={20,600},Smoothing={0,0.5},PredictionTime={0,0.25},TriggerDelay={0,1},
    FireInterval={0.03,1},TriggerPressTime={0.02,0.2},HitboxSize={2,20},HitboxTransparency={0,0.95},
    MaxDistance={50,5000},HitboxDistance={50,5000},ESPDistanceLimit={50,5000},ESPTextSize={10,24},CameraFOV={40,120},
    FreecamSpeed={5,200},FreecamSensitivity={0.05,0.5},
    RecoilStrength={0,100},MonsterESPRange={50,5000},ItemESPRange={50,5000},WorldESPMax={20,300}}
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
    snapshot.Settings.Freecam=false -- Camera mode starts off each session; speed and sensitivity persist.
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
        if name=="HitboxDistance" and value==nil then value=snapshot.Settings.MaxDistance end
        -- Migrate the old shared world range when separate ranges are not saved yet.
        if (name=="MonsterESPRange" or name=="ItemESPRange") and value==nil then
            value=snapshot.Settings.WorldESPRange
        end
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
            local control=configControls[name] or (Rayfield.Flags and Rayfield.Flags["HUSH_"..name])
            if control and control.Set then
                pcall(function() control:Set(type(value)=="string" and {value} or value) end)
            end
        end
    end
end
local function saveSettings(force)
    if type(writefile)~="function" then configNote("File saving is unavailable"); return false end
    local signature=configSignature()
    if not force and signature==lastConfigSignature then return true end
    local ok,err=pcall(function()
        if makefolder and (not isfolder or not isfolder("ProfessorZycro")) then makefolder("ProfessorZycro") end
        writefile(configPath,HttpService:JSONEncode(configSnapshot()))
    end)
    if ok then lastConfigSignature=signature; configNote("Saved to workspace")
    else configNote("Save failed - check file access");warn("Hush config save: "..tostring(err)) end
    return ok
end
local function loadSettings()
    if type(readfile)~="function" then configNote("File loading is unavailable");return false end
    if isfile then
        local existsOK,exists=pcall(isfile,configPath)
        if existsOK and not exists then configNote("No saved config yet");return false end
    end
    local ok,err=pcall(function()
        applyConfig(HttpService:JSONDecode(readfile(configPath)))
    end)
    if ok then lastConfigSignature=configSignature(); configNote("Loaded from workspace")
    else configNote("Config could not be loaded");warn("Hush config load: "..tostring(err)) end
    return ok
end
local function resetSettings()
    applyConfig({Version=1,Settings=configDefaults,Keys=keyDefaults})
    return saveSettings(true)
end
local keyFile = "Hush-keys-v3.json"
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
local previousBoot = playerGui:FindFirstChild("HushStartup")
if previousBoot then previousBoot:Destroy() end
local bootGui = Instance.new("ScreenGui")
bootGui.Name = "HushStartup"
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
bootText.Text = "HUSH build 18: starting..."
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
local aimRenderName = "HushAimRender"
local aimLock
local recoilRenderName = "HushRecoilRender"
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
local function markDead(character, humanoid)
    deadHumanoids[humanoid] = true
    if aimLock and aimLock.Character == character then aimLock = nil end
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
        connections[#connections + 1] = humanoid.Died:Connect(function() markDead(character, humanoid) end)
        connections[#connections + 1] = humanoid.HealthChanged:Connect(function(health)
            if health <= 0 then markDead(character, humanoid) end
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
local freecamState
local freecamAction="HushFreecamInput"
local freecamRender="HushFreecamRender"
local ContextActions=game:GetService("ContextActionService")
local function stopFreecam()
    ContextActions:UnbindAction(freecamAction)
    local state=freecamState
    if not state then return end
    freecamState=nil
    pcall(function()
        state.camera.CameraType=state.cameraType
        state.camera.CameraSubject=state.subject
        state.camera.CFrame=state.cframe
        state.camera.Focus=state.focus
    end)
    Input.MouseBehavior=state.mouseBehavior
    Input.MouseIconEnabled=state.mouseIcon
end
local function startFreecam(camera)
    releaseFire()
    aimLock=nil
    local pitch,yaw=camera.CFrame:ToOrientation()
    freecamState={camera=camera,cameraType=camera.CameraType,subject=camera.CameraSubject,
        cframe=camera.CFrame,focus=camera.Focus,mouseBehavior=Input.MouseBehavior,
        mouseIcon=Input.MouseIconEnabled,position=camera.CFrame.Position,pitch=pitch,yaw=yaw}
    camera.CameraType=Enum.CameraType.Scriptable
    ContextActions:BindActionAtPriority(freecamAction,function()
        return Enum.ContextActionResult.Sink
    end,false,10000,Enum.KeyCode.W,Enum.KeyCode.A,Enum.KeyCode.S,Enum.KeyCode.D,
        Enum.KeyCode.Q,Enum.KeyCode.E,Enum.KeyCode.Space,Enum.KeyCode.LeftControl,
        Enum.KeyCode.LeftShift,Enum.UserInputType.MouseButton1,Enum.UserInputType.MouseButton2)
    local humanoid=LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if humanoid then humanoid:Move(Vector3.zero,false) end
end
local function renderFreecam(dt)
    if not active then return end
    local camera=workspace.CurrentCamera
    if not Config.Freecam or not camera then stopFreecam();return end
    if freecamState and freecamState.camera~=camera then
        Config.Freecam=false
        stopFreecam()
        if uiToggles and uiToggles.Freecam then uiToggles.Freecam:Set(false) end
        return
    end
    if not freecamState then startFreecam(camera) end
    local state=freecamState
    camera.CameraType=Enum.CameraType.Scriptable
    local typing=Input:GetFocusedTextBox()~=nil or capturingKey~=nil
    local looking=not typing and Input:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
    Input.MouseBehavior=looking and Enum.MouseBehavior.LockCurrentPosition or Enum.MouseBehavior.Default
    Input.MouseIconEnabled=not looking
    if looking then
        local delta=Input:GetMouseDelta()*math.rad(Config.FreecamSensitivity)
        state.pitch=math.clamp(state.pitch-delta.Y,math.rad(-89),math.rad(89))
        state.yaw=state.yaw-delta.X
    end
    local rotation=CFrame.fromOrientation(state.pitch,state.yaw,0)
    local function down(key) return not typing and Input:IsKeyDown(key) and 1 or 0 end
    local x=down(Enum.KeyCode.D)-down(Enum.KeyCode.A)
    local z=down(Enum.KeyCode.S)-down(Enum.KeyCode.W)
    local y=math.max(down(Enum.KeyCode.E),down(Enum.KeyCode.Space))
        -math.max(down(Enum.KeyCode.Q),down(Enum.KeyCode.LeftControl))
    local move=rotation.RightVector*x+rotation.LookVector*(-z)+Vector3.yAxis*y
    if move.Magnitude>0 then
        local boost=down(Enum.KeyCode.LeftShift)>0 and 3 or 1
        state.position=state.position+move.Unit*Config.FreecamSpeed*boost*math.min(dt,0.1)
    end
    camera.CFrame=CFrame.new(state.position)*rotation
    camera.Focus=camera.CFrame*CFrame.new(0,0,-20)
end
connections[#connections+1]=LocalPlayer.CharacterRemoving:Connect(function()
    Config.Freecam=false
    stopFreecam()
    if uiToggles and uiToggles.Freecam then uiToggles.Freecam:Set(false) end
end)
RunService:BindToRenderStep(freecamRender,Enum.RenderPriority.Last.Value+2,renderFreecam)
local function unload()
    if not active then return end
    if configReady and Config.AutoSave then saveSettings(false) end
    active = false
    stopFreecam()
    RunService:UnbindFromRenderStep(freecamRender)
    releaseFire()
    for _, connection in ipairs(connections) do connection:Disconnect() end
    pcall(function() RunService:UnbindFromRenderStep(aimRenderName) end)
    pcall(function() RunService:UnbindFromRenderStep(recoilRenderName) end)
    if aimGui then aimGui:Destroy() end
    for part in pairs(originals) do restore(part) end
    clearESP()
    clearHush()
    if espFolder then espFolder:Destroy() end
    for property, value in pairs(lightingOriginals) do Lighting[property] = value end
    for camera, value in pairs(cameraOriginals) do
        pcall(function() camera.FieldOfView = value end)
    end
    if Aimbot then pcall(function() Aimbot:Exit() end) end
    Input.MouseDeltaSensitivity = originalSensitivity
    if Rayfield then pcall(function() Rayfield:Destroy() end) end
    bootGui:Destroy()
    env.HushHelper = nil
end
env.HushHelper = {Config = Config, Unload = unload,
    SaveSettings = function() return saveSettings(true) end,
    LoadSettings = function() releaseFire(); return loadSettings() end,
    ResetSettings = function() releaseFire(); return resetSettings() end}

bootMessage("HUSH: loading aim support...")
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
    warn("Hush: using compatible aim mode: " .. tostring(result))
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
    warn("Hush: compatible aim enabled: " .. tostring(loadError))
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
    local centered = Config.TriggerPoint ~= "Cursor"
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
    if input.KeyCode == keys.Freecam then flip("Freecam") end
end)

local elapsed = 0
connections[#connections + 1] = RunService.Heartbeat:Connect(function(dt)
    if not active then return end
    local now = os.clock()
    local fireRequested = Config.Trigger
    if releaseAt and now >= releaseAt then releaseFire(); releaseAt = nil end
    local blocked = Config.Freecam or capturingKey or Input:GetFocusedTextBox() or (Rayfield and Rayfield:IsVisible())
    local equippedTool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
    local target, targetCharacter
    if fireRequested and equippedTool and not blocked then target, targetCharacter = triggerTarget() end
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
        local inRange = root and camera and (root.Position - camera.CFrame.Position).Magnitude <= Config.HitboxDistance
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
        -- ESP can show a partially streamed character without its root, and does
        -- not inherit the targeting system's terminal corpse latch on a reused rig.
        local espCharacter = not isSelfPlayer(player) and player.Character
        local espHumanoid = espCharacter and espCharacter:FindFirstChildOfClass("Humanoid")
        if espHumanoid and (espHumanoid.Health<=0 or espHumanoid:GetState()==Enum.HumanoidStateType.Dead) then espCharacter=nil end
        local espAnchor = espCharacter and (espCharacter:FindFirstChild("Head") or espCharacter:FindFirstChild("HumanoidRootPart")
            or espCharacter:FindFirstChild("UpperTorso") or espCharacter:FindFirstChild("Torso") or espCharacter.PrimaryPart)
        local espRange = espAnchor and espAnchor:IsA("BasePart") and camera
            and (espAnchor.Position - camera.CFrame.Position).Magnitude <= Config.ESPDistanceLimit
        if espRange and Config.Highlights and (not Config.ESPTeamCheck or enemy(player)) then
            local character,root = espCharacter,espAnchor
            keepHighlights[player] = true
            local visual = highlights[player]
            local folder=ensureESPFolder()
            local currentPlayerGui=LocalPlayer:FindFirstChildOfClass("PlayerGui") or playerGui
            if visual and (visual.Character~=character or visual.Highlight.Parent~=folder
                or visual.Box.Parent~=folder or visual.Tag.Parent~=currentPlayerGui or not visual.Label.Parent) then
                destroyESP(visual);highlights[player]=nil;visual=nil
            end
            if not visual then
                local highlight = Instance.new("Highlight")
                highlight.Name = "HushHighlight"
                highlight.FillColor = Color3.new(1, 1, 1)
                highlight.FillTransparency = 0.65
                highlight.Parent = folder
                local tag = Instance.new("BillboardGui")
                tag.Name = "HushESP"
                tag.Size = UDim2.fromOffset(230, 70)
                -- Anchor the bottom of the entire text panel above the head.
                tag.SizeOffset = Vector2.new(0, 0.5)
                tag.ResetOnSpawn = false
                tag.LightInfluence = 0
                tag.Parent = currentPlayerGui
                local label = Instance.new("TextLabel")
                label.Size = UDim2.fromScale(1, 1)
                label.BackgroundTransparency = 1
                label.TextStrokeTransparency = 0.25
                label.Font = Enum.Font.GothamMedium
                label.Parent = tag
                local box = Instance.new("SelectionBox")
                box.LineThickness = 0.025
                box.SurfaceTransparency = 1
                box.Parent = folder
                visual = {Highlight = highlight, Tag = tag, Label = label, Box = box, Character=character}
                highlights[player] = visual
            end
            local color = Color3.new(1, 1, 1) -- White for highlights, labels and character boxes.
            visual.Highlight.Enabled = true
            visual.Tag.Enabled = true
            visual.Highlight.Adornee = character
            visual.Highlight.FillColor = color
            visual.Highlight.OutlineColor = color
            visual.Highlight.DepthMode = Config.ESPThroughWalls and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
            local espHead = character:FindFirstChild("Head")
            local textAnchor = espHead and espHead:IsA("BasePart") and espHead or root
            visual.Tag.Adornee = textAnchor
            local aboveHead = espHead == textAnchor and (textAnchor.Size.Y * 0.5 + 0.6) or 3.5
            visual.Tag.StudsOffsetWorldSpace = Vector3.new(0, aboveHead, 0)
            visual.Tag.Size = UDim2.fromOffset(230, Config.ESPTextSize * 3 + 20)
            visual.Label.TextYAlignment = Enum.TextYAlignment.Bottom
            visual.Tag.AlwaysOnTop = Config.ESPThroughWalls
            visual.Tag.MaxDistance = Config.ESPDistanceLimit
            visual.Label.TextColor3 = color
            visual.Label.TextSize = Config.ESPTextSize
            local lines = {}
            if Config.ESPNames then table.insert(lines, (player.DisplayName or player.Name) .. " (@" .. player.Name .. ")") end
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
            destroyESP(visual)
            highlights[player] = nil
        end
    end
end)
aimGui = Instance.new("ScreenGui")
aimGui.Name, aimGui.ResetOnSpawn, aimGui.IgnoreGuiInset = "HushAimVisuals", false, true
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
    if Config.Freecam then aimLock=nil;aimCircle.Visible=false;tracer.Visible=false;return end
    local camera = workspace.CurrentCamera
    if not camera then return end
    local cursor = Input:GetMouseLocation()
    -- GUI and target projection both use viewport coordinates, with no top-bar inset.
    -- Always-on is centered even when an older saved setting says Cursor.
    if Config.AimAlways or Config.AimOrigin == "Center" or (Config.AimOrigin == "Auto" and
        Input.MouseBehavior == Enum.MouseBehavior.LockCenter) then
        cursor = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
    end
    aimCircle.Visible = Config.Aim and Config.ShowFOV
    aimCircle.Position = UDim2.fromOffset(cursor.X, cursor.Y)
    aimCircle.Size = UDim2.fromOffset(Config.Radius * 2, Config.Radius * 2)
    circleStroke.Color = Color3.new(1, 1, 1)
    tracer.Visible = false
    if not Config.Aim then aimLock = nil; return end
    if capturingKey or Input:GetFocusedTextBox() then aimLock = nil; return end
    if Config.PauseAimWithMenu and Rayfield and Rayfield:IsVisible() then aimLock = nil; return end
    if not Config.AimAlways then
        local held = keys.Aim.EnumType == Enum.UserInputType and Input:IsMouseButtonPressed(keys.Aim)
            or keys.Aim.EnumType == Enum.KeyCode and Input:IsKeyDown(keys.Aim)
        if not held then aimLock = nil; return end
    end
    local function candidate(player)
        local character = enemy(player) and living(player)
        if not character then return end
        local names = Config.AimPart == "Auto" and {"Head", "UpperTorso", "Torso", "HumanoidRootPart"}
            or {Config.AimPart, "HumanoidRootPart"}
        for _, name in ipairs(names) do
            local part = character:FindFirstChild(name)
            if part then
            local point, visible = camera:WorldToViewportPoint(part.Position)
            local screenDistance = (Vector2.new(point.X, point.Y) - cursor).Magnitude
            if visible and screenDistance <= Config.Radius then
                local clear = true
                if Config.WallCheck then
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
    if Config.StickyAim and aimLock and aimLock.Player.Character == aimLock.Character then
        selected = candidate(aimLock.Player)
    end
    if not selected then
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
    local blocked = Config.Freecam or not Config.RecoilEnabled or not tool or not firing or capturingKey
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
    gui.Name, gui.ResetOnSpawn, gui.DisplayOrder = "HushFallback", false, 99999
    gui.Parent = playerGui
    pcall(function() if gethui then gui.Parent = gethui() end end)
    local panel = Instance.new("Frame")
    panel.Size, panel.Position = UDim2.fromScale(0.7, 0.75), UDim2.fromScale(0.15, 0.12)
    panel.BackgroundColor3, panel.Parent = Color3.fromRGB(24, 25, 31), gui
    local title = Instance.new("TextLabel")
    title.Size, title.BackgroundTransparency = UDim2.new(1, -20, 0, 38), 1
    title.Text, title.TextSize = "HUSH - compatible menu | F1 hide/show", 18
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
            function tab:CreateSection(name)
                return self:CreateLabel(name)
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

-- HUSH world markers use replicated folders found in both supplied place saves.
local worldMarkers = {}
local worldFolder=Instance.new("Folder")
worldFolder.Name="HushWorldMarkers"
worldFolder.Parent=workspace
local worldStatus
local codeStatus
local codeLetters={}
local codeRemote
local codeConnection
local codeRound=game:GetService("ReplicatedStorage"):GetAttribute("RoundEndsAt")
local codeTrail
local function updateCodePapers()
    local storage=game:GetService("ReplicatedStorage")
    local round=storage:GetAttribute("RoundEndsAt")
    local trail=workspace:FindFirstChild("DeepwellTrail")
    if round~=codeRound or (codeTrail and trail~=codeTrail) then codeLetters={} end
    codeRound=round
    codeTrail=trail
    local remotes=storage:FindFirstChild("Remotes")
    local remote=remotes and remotes:FindFirstChild("Bunker")
    if remote~=codeRemote then
        if codeConnection then codeConnection:Disconnect();codeConnection=nil end
        codeRemote=remote
        if remote and remote:IsA("RemoteEvent") then
            codeConnection=remote.OnClientEvent:Connect(function(action,paper)
                -- Record only the ordered fragment the game actually reveals.
                if action=="paper" and type(paper)=="table" and paper.kind=="fragment"
                    and type(paper.index)=="number" and paper.index%1==0
                    and paper.index>=1 and paper.index<=4
                    and type(paper.letter)=="string" and #paper.letter==1 then
                    codeLetters[paper.index]=paper.letter
                end
            end)
            connections[#connections+1]=codeConnection
        end
    end
    if codeStatus then
        local slots={}
        for i=1,4 do slots[i]=codeLetters[i] or "?" end
        local loaded=0
        if trail then
            for _,object in ipairs(trail:GetChildren()) do
                if object.Name=="CodeFragment" then loaded=loaded+1 end
            end
        end
        codeStatus:Set("Read code: "..table.concat(slots," ").." | Loaded papers: "..loaded)
    end
end
local noiseGui=Instance.new("ScreenGui")
noiseGui.Name="HushNoiseEstimate"
noiseGui.ResetOnSpawn=false
noiseGui.IgnoreGuiInset=true
noiseGui.DisplayOrder=100001
noiseGui.Enabled=false
noiseGui.Parent=playerGui
local noiseText=Instance.new("TextLabel")
noiseText.AnchorPoint=Vector2.new(0,1)
noiseText.Position=UDim2.new(0.012,0,0.86,-8)
noiseText.Size=UDim2.fromOffset(300,48)
noiseText.BackgroundTransparency=1
noiseText.TextColor3=Color3.new(1,1,1)
noiseText.Font=Enum.Font.GothamMedium
noiseText.TextSize=18
noiseText.TextWrapped=false
noiseText.TextXAlignment=Enum.TextXAlignment.Left
noiseText.TextYAlignment=Enum.TextYAlignment.Bottom
noiseText.TextStrokeTransparency=0.3
noiseText.Parent=noiseGui
local handsUpLabel
local nextHandsUpSearch=0
local function positionNoiseHUD()
    if (not handsUpLabel or not handsUpLabel.Parent) and os.clock()>=nextHandsUpSearch then
        nextHandsUpSearch=os.clock()+2
        for _,item in ipairs(playerGui:GetDescendants()) do
            if (item:IsA("TextLabel") or item:IsA("TextButton")) and item.Visible
                and string.upper(item.Text):match("^%s*HANDS UP%s*$") then
                handsUpLabel=item
                break
            end
        end
    end
    if handsUpLabel and handsUpLabel.Parent and handsUpLabel.AbsoluteSize.Y>0 then
        local row=handsUpLabel.Parent
        local left=math.max(12,handsUpLabel.AbsolutePosition.X-36)
        if row:IsA("GuiObject") and row.AbsoluteSize.X<400 then left=row.AbsolutePosition.X end
        noiseText.Position=UDim2.fromOffset(left,handsUpLabel.AbsolutePosition.Y-10)
    else
        noiseText.Position=UDim2.new(0.012,0,0.86,-8)
    end
end
local function updateNoiseEstimate()
    noiseGui.Enabled=Config.NoiseCeiling
    if not Config.NoiseCeiling then return end
    positionNoiseHUD()
    local character=LocalPlayer.Character
    local origin=character and character:FindFirstChild("HumanoidRootPart")
    if not origin then noiseText.Text="Nearest Listener: --\n-- dB";return end
    -- Independent of ESP toggles, marker range and marker count.
    local monsters=workspace:FindFirstChild("Monsters")
    local nearest=math.huge
    if monsters then
        for _,model in ipairs(monsters:GetChildren()) do
            local kind=model:GetAttribute("Kind")
            local hum=model:FindFirstChildOfClass("Humanoid")
            local root=model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Head")
                or (model:IsA("Model") and model.PrimaryPart)
            if (kind==nil or kind=="Listener") and root and root:IsA("BasePart")
                and (not hum or hum.Health>0) and model:GetAttribute("State")~="Dead" then
                nearest=math.min(nearest,(origin.Position-root.Position).Magnitude)
            end
        end
    end
    if nearest==math.huge then
        noiseText.Text="Nearest Listener: --\n-- dB"
        return
    end
    -- Saved Acoustics: radius = min(1200, 14 * 10^((db-55)/20)).
    -- Add a 1.15 hearing-distance allowance and subtract a 6 dB buffer.
    if nearest>1200*1.15 then
        noiseText.Text="Nearest Listener: "..math.floor(nearest).." studs\n-- dB"
        return
    end
    local ceiling=math.floor(55+20*math.log10(math.max(nearest,0.01)/(14*1.15))-6)
    noiseText.Text="Nearest Listener: "..math.floor(nearest).." studs\n"..math.max(0,ceiling).." dB"
end
-- Item names/categories from the supplied game's Items.Defs.
local itemCatalog={
    pistol={name="9mm Pistol",category="Weapons"},
    revolver={name=".357 Revolver",category="Weapons"},
    hand_cannon={name=".50 Hand Cannon",category="Weapons"},
    machine_pistol={name="Machine Pistol",category="Weapons"},
    shotgun={name="Pump Shotgun",category="Weapons"},
    double_barrel={name="Double Barrel",category="Weapons"},
    rifle={name="5.56 Carbine",category="Weapons"},
    ak47={name="AK-47",category="Weapons"},
    mp5={name="MP5",category="Weapons"},
    minigun={name="Minigun",category="Weapons"},
    rpk={name="RPK",category="Weapons"},
    sniper={name="Bolt-Action Sniper",category="Weapons"},
    honey_badger={name="Honey Badger",category="Weapons"},
    listener_tooth={name="Listener Tooth",category="Weapons"},
    sledgehammer={name="Sledgehammer",category="Weapons"},
    pistol_gold={name="Golden 9mm Pistol",category="Weapons"},
    double_barrel_gold={name="Golden Double Barrel",category="Weapons"},
    revolver_gold={name="Golden .357 Revolver",category="Weapons"},
    sniper_gold={name="Golden Bolt-Action Sniper",category="Weapons"},
    block_switch={name="Block with a Switch",category="Weapons"},
    canned_beans={name="Canned Beans",category="Food"},
    crackers={name="Crackers",category="Food"},
    energy_bar={name="Energy Bar",category="Food"},
    water_bottle={name="Water Bottle",category="Water"},
    soda_can={name="Soda Can",category="Water"},
    bandage={name="Bandage",category="Medical"},
    medkit={name="Medkit",category="Medical"},
    defib={name="Defibrillator",category="Medical"},
    light_ammo={name="Light Ammo",category="Ammo"},
    medium_ammo={name="Medium Ammo",category="Ammo"},
    heavy_ammo={name="Heavy Ammo",category="Ammo"},
    shotgun_ammo={name="Shotgun Ammo",category="Ammo"},
    pistol_mag_ext={name="Extended Light Mag",category="Attachments"},
    rifle_mag_ext={name="Extended Medium Mag",category="Attachments"},
    mag_drum={name="Medium Drum Mag",category="Attachments"},
    wooden_board={name="Wooden Board",category="Materials"},
    sheet_metal={name="Sheet Metal",category="Materials"},
    nails={name="Nails",category="Materials"},
    duct_tape={name="Duct Tape",category="Materials"},
    rags={name="Cloth Rags",category="Materials"},
    scrap_metal={name="Scrap Metal",category="Materials"},
    gunpowder={name="Gunpowder",category="Materials"},
    electronics={name="Electronics",category="Materials"},
    chemicals={name="Chemicals",category="Materials"},
    gun_parts_light={name="Light Gun Parts",category="Materials"},
    gun_parts_medium={name="Medium Gun Parts",category="Materials"},
    wood_wall={name="Wood Wall",category="Building"},
    wood_door={name="Wood Door",category="Building"},
    metal_wall={name="Metal Wall",category="Building"},
    wood_floor={name="Wood Floor",category="Building"},
    wood_barricade={name="Barricade",category="Building"},
    wood_ladder={name="Ladder",category="Building"},
    car_armor={name="Car Armor",category="Building"},
    flood_light={name="Flood Light",category="Building"},
    crowbar={name="Crowbar",category="Tools"},
    hammer={name="Hammer",category="Tools"},
    toolkit={name="Tool Kit",category="Tools"},
    flashlight={name="Flashlight",category="Tools"},
    nv_goggles={name="Night Vision Goggles",category="Tools"},
    handcuffs={name="Handcuffs",category="Tools"},
    supply_flare={name="Supply Flare",category="Tools"},
    deepwell_code={name="Deepwell Access Card",category="Tools"},
    armory_key={name="Armory Key",category="Tools"},
    bunker_code={name="Bunker Code",category="Tools"},
    owner_note={name="Note from Instiagtor",category="Tools"},
    frag_grenade={name="Frag Grenade",category="Tools"},
    remote_charge={name="Remote Charge",category="Tools"},
    noise_lure={name="Noise Lure",category="Tools"},
    grappling_hook={name="Grappling Hook",category="Tools"},
    banjo={name="Banjo",category="Tools"},
    detonator={name="Detonator",category="Tools"},
    silencer_1={name="Silencer I",category="Attachments"},
    silencer_2={name="Silencer II",category="Attachments"},
    silencer_3={name="Silencer III",category="Attachments"},
    grip_vertical={name="Vertical Grip",category="Attachments"},
    grip_angled={name="Angled Grip",category="Attachments"},
    mag_extended={name="Shotgun Tube Extension",category="Attachments"},
    junk={name="Junk",category="Junk"},
}
local lootCategories={
    Weapons="LootWeapons",Attachments="LootAttachments",Medical="LootMedical",
    Materials="LootMaterials",Building="LootMaterials",Junk="LootMaterials",
    Ammo="LootAmmo",Food="LootFood",Water="LootFood",
    Armor="LootGear",Tools="LootGear",Accessories="LootGear",
}
local function lootInfo(object)
    local id=object.Name:match("^Dropped_(.+)$") or object.Name:match("^Find_(.+)$")
    if id=="bunker_code" then return "Bunker code note","LootCodes" end
    local item=id and itemCatalog[id]
    if item then return item.name,lootCategories[item.category] or "LootOther" end
    return (id or object.Name):gsub("_"," "),"LootOther"
end
local function resolveWorldPath(path)
    local object=workspace
    for name in path:gmatch("[^.]+") do
        object=object:FindFirstChild(name)
        if not object then return nil end
    end
    return object
end
-- Index nested lockbox models once, then follow streamed additions/removals.
local nestedLockboxes={}
local function indexLockbox(object)
    if object:IsA("Model") and object.Name=="Lockbox" then
        local parent=object.Parent
        while parent and parent~=workspace do
            if parent.Name=="Lockboxes" then nestedLockboxes[object]=true;return end
            parent=parent.Parent
        end
    end
end
connections[#connections+1]=workspace.DescendantAdded:Connect(indexLockbox)
connections[#connections+1]=workspace.DescendantRemoving:Connect(function(object)
    nestedLockboxes[object]=nil
end)
task.spawn(function()
    local objects=workspace:GetDescendants()
    for i,object in ipairs(objects) do
        if not active then return end
        if object:IsDescendantOf(workspace) then indexLockbox(object) end
        if i%2000==0 then task.wait() end
    end
end)
local function groupObjects(group)
    if not Config[group[2]] then return {} end
    if group[1]=="NestedLockboxes" then
        if not Config.LockboxESP then return {} end
        local objects={}
        for object in pairs(nestedLockboxes) do
            if object:IsDescendantOf(workspace) then objects[#objects+1]=object
            else nestedLockboxes[object]=nil end
        end
        return objects
    end
    if group[1]=="LootBags" and not Config.LootBagESP then return {} end
    local container=resolveWorldPath(group[1])
    if not container then return {} end
    return group[5] and {container} or container:GetChildren()
end
local worldGroups={
    {"DeepwellTrail","CodeESP",Color3.fromRGB(0,235,255),"Code paper"},
    {"Monsters","MonsterESP",Color3.fromRGB(255,0,0),"Listeners"},
    {"Watchers","WatcherESP",Color3.fromRGB(255,255,0),"Watchers"},
    {"Sentries","SentryESP",Color3.fromRGB(255,140,0),"Sentries"},
    {"Mother","MotherESP",Color3.fromRGB(160,70,255),"Mother",true},
    {"WorldFinds","LootESP",Color3.fromRGB(150,150,150),"Loot"},
    {"LootBags","LootESP",Color3.fromRGB(150,150,150),"Loot bag"},
    {"NestedLockboxes","LootESP",Color3.fromRGB(150,150,150),"Lockbox"},
    {"SupplyDrops","SupplyESP",Color3.fromRGB(139,90,43),"Supply drop"},
    {"Town.Exits","ExitESP",Color3.fromRGB(0,255,0),"Extraction"},
    {"NoiseTraps","TrapESP",Color3.fromRGB(255,105,180),"Noise trap"},
    {"Deepwell.Rooms.PowerHall.BreakerLever","DeepwellESP",Color3.fromRGB(0,235,255),"DEEPWELL",true,"Power breaker"},
    {"Deepwell.Rooms.Stores.VaultDoor","DeepwellESP",Color3.fromRGB(0,235,255),"DEEPWELL",true,"Vault door"},
    {"Deepwell.Rooms.Armory.ArmoryDoor","DeepwellESP",Color3.fromRGB(0,235,255),"DEEPWELL",true,"Armory door"},
    {"Deepwell.Portal.BlastDoor","DeepwellESP",Color3.fromRGB(0,235,255),"DEEPWELL",true,"Blast door"},
    {"CraftingBenches","CraftingESP",Color3.fromRGB(230,230,230),"Crafting bench"},
    {"Town.Zones.HavenOutpost.BountyOffice.BountyWindow","BountyESP",Color3.fromRGB(230,230,230),"Bounty office",true,"Bounty office"},
}
local function removeWorld(object)
    local marker=worldMarkers[object]
    if marker then marker.gui:Destroy();if marker.highlight then marker.highlight:Destroy() end end
    worldMarkers[object]=nil
end
clearHush=function()
    for object in pairs(worldMarkers) do removeWorld(object) end
    table.clear(nestedLockboxes)
    worldFolder:Destroy()
    noiseGui:Destroy()
end
local elapsed=0
connections[#connections+1]=RunService.Heartbeat:Connect(function(dt)
    elapsed=elapsed+dt
    if elapsed<0.25 or not active then return end
    elapsed=0
    updateNoiseEstimate()
    updateCodePapers()
    local camera=workspace.CurrentCamera
    if not camera then return end
    local candidates={}
    for _,group in ipairs(worldGroups) do
        local creature=group[2]=="MonsterESP" or group[2]=="WatcherESP"
            or group[2]=="SentryESP" or group[2]=="MotherESP"
        local range=creature and Config.MonsterESPRange or Config.ItemESPRange
        for _,object in ipairs(groupObjects(group)) do
            local codePaper=group[2]=="CodeESP"
            local matches=not codePaper or object.Name=="CodeFragment"
            local displayName=group[6] or object.Name
            if group[1]=="WorldFinds" then
                local filter
                displayName,filter=lootInfo(object)
                matches=matches and Config[filter]
            elseif group[1]=="Sentries" then
                displayName=object.Name=="Sentry_PATROL" and "Patrol sentry"
                    or (object.Name=="Sentry_POWER" and "Power sentry" or object.Name)
            elseif codePaper then displayName="Code paper"
            elseif group[1]=="CraftingBenches" then displayName="Crafting bench" end
            if matches then
                local anchor=object:IsA("BasePart") and object
                    or object:FindFirstChild("Head",true)
                    or object:FindFirstChild("HumanoidRootPart",true)
                    or (object:IsA("Model") and object.PrimaryPart)
                    or object:FindFirstChildWhichIsA("BasePart",true)
                local hum=object:FindFirstChildOfClass("Humanoid")
                if anchor and anchor:IsA("BasePart") and (not hum or hum.Health>0) then
                    local distance=(camera.CFrame.Position-anchor.Position).Magnitude
                    if distance<=range then
                        candidates[#candidates+1]={object=object,anchor=anchor,distance=distance,
                            group=group,displayName=displayName}
                    end
                end
            end
        end
    end
    table.sort(candidates,function(a,b)
        local ac,bc=a.group[2]=="CodeESP",b.group[2]=="CodeESP"
        if ac~=bc then return ac end -- Keep code papers visible under the marker cap.
        return a.distance<b.distance
    end)
    local keep={}
    for i=1,math.min(#candidates,Config.WorldESPMax) do
        local c=candidates[i];local object=c.object
        keep[object]=true
        local marker=worldMarkers[object]
        if not marker then
            local gui=Instance.new("BillboardGui")
            gui.Name="WorldTag";gui.Size=UDim2.fromOffset(240,55)
            gui.StudsOffsetWorldSpace=Vector3.new(0,3,0);gui.AlwaysOnTop=true;gui.Parent=worldFolder
            local text=Instance.new("TextLabel")
            text.Size=UDim2.fromScale(1,1);text.BackgroundTransparency=1;text.TextSize=13
            text.Font=Enum.Font.GothamMedium;text.TextStrokeTransparency=0.25;text.Parent=gui
            marker={gui=gui,text=text};worldMarkers[object]=marker
            if object:IsA("Model") or object:IsA("BasePart") then
                local h=Instance.new("Highlight");h.Adornee=object;h.FillTransparency=0.8
                h.OutlineTransparency=0;h.Parent=worldFolder;marker.highlight=h
            end
        end
        marker.gui.Adornee=c.anchor
        marker.text.TextColor3=c.group[3]
        local state=object:GetAttribute("State")
        local health=object:FindFirstChildOfClass("Humanoid")
        local displayName=c.displayName
        marker.text.Text=displayName.." ["..c.group[4].."] "..math.floor(c.distance).." studs"
            ..(state and "\n"..tostring(state) or "")..(health and " | HP "..math.ceil(health.Health) or "")
        if marker.highlight then
            marker.highlight.FillColor=c.group[3];marker.highlight.OutlineColor=c.group[3]
        end
    end
    for object in pairs(worldMarkers) do if not keep[object] then removeWorld(object) end end
    if worldStatus then
        local hears=LocalPlayer:GetAttribute("MotherHears")==true
        local message=Config.ThreatWarning and hears and "WARNING: Mother hears you" or "Mother warning: no active signal"
        worldStatus:Set(message.." | Markers: "..math.min(#candidates,Config.WorldESPMax))
    end
end)

-- Configuration flags are unique; saved Rayfield values flow through callbacks.
local guiOK, guiError = pcall(function()
    bootMessage("HUSH: loading Rayfield menu...")
    local windowSettings = {
        Name = "HUSH", LoadingTitle = "HUSH", LoadingSubtitle = "professorzycro",
        Theme = "Default", ShowText = "HUSH", DisableRayfieldPrompts = true,
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
            warn("Hush: inline key row unavailable: " .. name)
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
        local control = tab:CreateToggle({Name = name, CurrentValue = Config[property], Flag = "HUSH_" .. property,
            Callback = function(value)
                Config[property] = value
                if property == "AutoSave" then saveSettings(true) end
            end})
        uiToggles[property] = control
        configControls[property] = control
        if action then
            local attached, err = pcall(attachKey, name, action)
            if not attached then warn("Hush inline key: " .. tostring(err)) end
        end
    end
    local function slider(tab, name, property, minimum, maximum, increment)
        local control = tab:CreateSlider({Name = name, Range = {minimum, maximum}, Increment = increment or 1,
            CurrentValue = Config[property], Flag = "HUSH_" .. property,
            Callback = function(value) Config[property] = value end})
        configControls[property] = control
        return control
    end

    local function dropdown(tab,name,property,options,onChange)
        local control=tab:CreateDropdown({Name=name,Options=options,CurrentOption={Config[property]},Flag="HUSH_"..property,
            Callback=function(values)
                Config[property]=values[1]
                if onChange then onChange() end
            end})
        configControls[property]=control
        return control
    end
    local function setControl(property,value)
        Config[property]=value
        local control=configControls[property]
        if control then control:Set(type(value)=="string" and {value} or value) end
    end
    local aim=window:CreateTab("Combat")
    aim:CreateSection("Aim assist")
    toggle(aim,"Aimbot","Aim","Aim")
    toggle(aim,"Always on","AimAlways")
    toggle(aim,"Pause while menu is open","PauseAimWithMenu")
    aim:CreateSection("Target selection")
    dropdown(aim,"Target part","AimPart",{"Auto","Head","UpperTorso","HumanoidRootPart"},function() aimLock=nil end)
    toggle(aim,"Keep current target","StickyAim")
    toggle(aim,"Ignore teammates","TeamCheck")
    toggle(aim,"Wall check","WallCheck")
    toggle(aim,"Ignore non-collidable effects","AimIgnoreEffects")
    aim:CreateSection("Aim circle")
    toggle(aim,"Show circle","ShowFOV")
    slider(aim,"Radius (pixels)","Radius",20,600)
    dropdown(aim,"Circle position","AimOrigin",{"Auto","Center","Cursor"})
    toggle(aim,"Show target line","Tracer")
    aim:CreateSection("Response")
    slider(aim,"Smoothing (seconds)","Smoothing",0,0.5,0.01)
    toggle(aim,"Movement prediction","AimPrediction")
    slider(aim,"Prediction lead (seconds)","PredictionTime",0,0.25,0.01)
    aim:CreateButton({Name="Apply responsive preset",Callback=function()
        aimLock=nil
        setControl("Aim",true);setControl("StickyAim",true);setControl("AimPart","Auto")
        setControl("Radius",180);setControl("Smoothing",0.03)
    end})
    aim:CreateParagraph({Title="Quick guide",Content="Always on stays centered. Auto selects a visible head or torso. Lower smoothing is faster; zero snaps. Prediction adds fixed-time movement lead."})

    local trigger=aim
    trigger:CreateSection("Triggerbot")
    toggle(trigger,"Triggerbot","Trigger","Trigger")
    triggerStatus=trigger:CreateLabel("Trigger: off")
    trigger:CreateSection("Firing")
    dropdown(trigger,"Input method","TriggerMode",{"Auto","Mouse","Tool"},releaseFire)
    dropdown(trigger,"Crosshair","TriggerPoint",{"Auto","Center","Cursor"})
    dropdown(trigger,"Firing pattern","TriggerPattern",{"Pulse","Hold"},function() releaseFire();releaseAt=nil end)
    slider(trigger,"Maximum range (studs)","MaxDistance",50,5000,50)
    trigger:CreateSection("Timing")
    slider(trigger,"Reaction delay (seconds)","TriggerDelay",0,1,0.01)
    slider(trigger,"Shot interval (seconds)","FireInterval",0.03,1,0.01)
    slider(trigger,"Press length (seconds)","TriggerPressTime",0.02,0.2,0.01)
    trigger:CreateButton({Name="Apply fast trigger preset",Callback=function()
        setControl("TriggerDelay",0);setControl("FireInterval",0.06)
        aimedAt,aimedCharacter,aimedSince,lastShot=nil,nil,0,0
    end})
    trigger:CreateSection("Detection")
    toggle(trigger,"Ignore non-collidable effects","TriggerIgnoreEffects")
    trigger:CreateParagraph({Title="Quick guide",Content="Equip a weapon and hide the menu. Hold suits automatic weapons; Pulse suits semi-auto. Auto crosshair uses screen center."})

    local hitboxes=aim
    hitboxes:CreateSection("Hitboxes")
    toggle(hitboxes,"Hitbox expander","Hitboxes","Hitboxes")
    hitboxes:CreateSection("Shape")
    dropdown(hitboxes,"Body parts","HitboxPart",{"Head","Torso","Both"})
    slider(hitboxes,"Size (studs)","HitboxSize",2,20)
    slider(hitboxes,"Transparency","HitboxTransparency",0,0.95,0.05)
    hitboxes:CreateSection("Visibility")
    toggle(hitboxes,"Wall check","HitboxWallCheck")
    slider(hitboxes,"Maximum range (studs)","HitboxDistance",50,5000,50)
    hitboxes:CreateParagraph({Title="Compatibility",Content="Expands recognized body parts locally and restores them when disabled or dead. Server validation may still reject expanded hits."})

    local esp=window:CreateTab("ESP")
    esp:CreateSection("Players — white")
    toggle(esp,"Player ESP","Highlights","ESP")
    esp:CreateSection("Visibility")
    toggle(esp,"Enemy only","ESPTeamCheck")
    toggle(esp,"Show through walls","ESPThroughWalls")
    slider(esp,"Player ESP distance (studs)","ESPDistanceLimit",50,5000,50)
    esp:CreateSection("Labels")
    toggle(esp,"Names","ESPNames")
    toggle(esp,"Health","ESPHealth")
    toggle(esp,"Distance","ESPDistance")
    slider(esp,"Text size","ESPTextSize",10,24)
    esp:CreateSection("Appearance")
    esp:CreateLabel("ESP color: White")
    toggle(esp,"Character boxes","ESPBoxes")
    esp:CreateButton({Name="Refresh ESP",Callback=clearESP})

    esp:CreateSection("Creatures")
    toggle(esp,"Listeners — red","MonsterESP")
    toggle(esp,"Watchers — yellow","WatcherESP")
    toggle(esp,"Sentries — orange","SentryESP")
    toggle(esp,"Mother — purple","MotherESP")
    slider(esp,"Creature distance (studs)","MonsterESPRange",50,5000,50)
    esp:CreateParagraph({Title="Sentries",Content="Patrol and power sentries have separate names on their markers."})
    esp:CreateSection("Noise awareness")
    toggle(esp,"Mother hearing warning","ThreatWarning")
    toggle(esp,"Noise ceiling HUD","NoiseCeiling")
    worldStatus=esp:CreateLabel("Waiting for world data")
    esp:CreateParagraph({Title="Noise estimate",Content="The HUD shows the nearest loaded Listener and an estimated dB ceiling with a 6 dB buffer. Walls, unloaded enemies and special hearing are not modeled."})

    local loot=window:CreateTab("Loot")
    loot:CreateSection("Loot markers — grey")
    toggle(loot,"Enable loot ESP","LootESP")
    toggle(loot,"Nested lockboxes","LockboxESP")
    toggle(loot,"Loot bags","LootBagESP")
    loot:CreateSection("Loose-item filters")
    toggle(loot,"Weapons","LootWeapons")
    toggle(loot,"Attachments","LootAttachments")
    toggle(loot,"Medical supplies","LootMedical")
    toggle(loot,"Materials and junk","LootMaterials")
    toggle(loot,"Ammunition","LootAmmo")
    toggle(loot,"Food and drinks","LootFood")
    toggle(loot,"Gear and tools","LootGear")
    toggle(loot,"Bunker code notes","LootCodes")
    toggle(loot,"Other items","LootOther")
    loot:CreateSection("Supplies and distance")
    toggle(loot,"Supply drops — brown","SupplyESP")
    slider(loot,"Item and map distance (studs)","ItemESPRange",50,5000,50)
    slider(loot,"Maximum world markers","WorldESPMax",20,300,10)
    loot:CreateParagraph({Title="Filters",Content="Filters apply to loose items. Bags and lockboxes show locations; their contents may not be revealed until opened. Bunker code notes are separate from DEEPWELL fragments."})

    local world=window:CreateTab("Map")
    world:CreateSection("DEEPWELL")
    toggle(world,"Code papers — cyan","CodeESP")
    toggle(world,"Breaker and doors — cyan","DeepwellESP")
    codeStatus=world:CreateLabel("Read code: ? ? ? ? | Loaded papers: 0")
    world:CreateParagraph({Title="Code tracker",Content="Read papers normally to fill the four code positions. Unknown letters stay ?. The tracker clears when the town resets."})
    world:CreateSection("Navigation")
    toggle(world,"Extraction — green","ExitESP")
    toggle(world,"Noise traps — pink","TrapESP")
    world:CreateSection("Services")
    toggle(world,"Crafting benches","CraftingESP")
    toggle(world,"Bounty office","BountyESP")
    world:CreateParagraph({Title="Map markers",Content="Uses the Item and map distance in Loot. Markers show loaded locations; extraction and door markers do not confirm availability or unlock them."})

    local visuals=window:CreateTab("Camera")
    visuals:CreateSection("Freecam")
    toggle(visuals,"Freecam","Freecam","Freecam")
    slider(visuals,"Freecam speed (studs/sec)","FreecamSpeed",5,200,5)
    slider(visuals,"Freecam mouse sensitivity","FreecamSensitivity",0.05,0.5,0.01)
    visuals:CreateParagraph({Title="Freecam controls",Content="F5 toggles. WASD moves, E/Space rises, Q/Left Ctrl lowers. Hold RMB to look and Left Shift for 3x speed. Your character stays in the game and can still be harmed. Camera mode starts off each session."})
    visuals:CreateSection("Shared visibility")
    toggle(visuals,"Ignore breakable glass","IgnoreBreakableGlass")
    visuals:CreateSection("Lighting & camera")
    toggle(visuals,"Fullbright","Fullbright")
    toggle(visuals,"Override camera FOV","CameraOverride")
    slider(visuals,"Camera FOV","CameraFOV",40,120)
    aim:CreateSection("Recoil")
    toggle(aim,"Camera recoil dampener","RecoilEnabled","Recoil")
    slider(aim,"Camera smoothing (%)","RecoilStrength",0,100,5)
    recoilStatus=aim:CreateLabel("Recoil: Off")

    local settings=window:CreateTab("Settings")
    settings:CreateSection("Saved settings")
    toggle(settings,"Auto-save","AutoSave")
    configStatus=settings:CreateLabel(lastConfigMessage)
    settings:CreateButton({Name="Save config",Callback=function() saveSettings(true) end})
    settings:CreateButton({Name="Load config",Callback=function() releaseFire();aimLock=nil;loadSettings() end})
    settings:CreateButton({Name="Reset to defaults",Callback=function() releaseFire();aimLock=nil;resetSettings() end})
    settings:CreateParagraph({Title="Config file",Content="workspace/ProfessorZycro/Hush-config.json\nIncludes settings and keybinds; loads at startup."})
    settings:CreateSection("Controls")
    settings:CreateButton({Name="Hide / show menu",Callback=function() Rayfield:SetVisibility(not Rayfield:IsVisible()) end})
    pcall(attachKey,"Hide / show menu","Menu")
    keyControls.Unload=settings:CreateKeybind({Name="Unload key",CurrentKeybind=keys.Unload.Name,CallOnChange=true,
        HoldToInteract=false,Flag="HUSH_UnloadKey",Callback=function(value)
            if type(value)=="string" and Enum.KeyCode[value] then keys.Unload=Enum.KeyCode[value] end
        end})
    settings:CreateParagraph({Title="Keybinds",Content="Click a key badge beside a feature to rebind it. Escape cancels. F1 shows/hides the menu by default."})
    settings:CreateSection("Session")
    settings:CreateButton({Name="Unload & restore changes",Callback=unload})
    configReady = true
    -- Create the config on first startup and preserve loaded settings.
    if Config.AutoSave then saveSettings(false) end
    Rayfield:SetVisibility(true)
    if Rayfield.IsFallback then
        bootMessage("HUSH build 17: compatible menu loaded. F1 hide/show. Type numeric values; click dropdowns to cycle choices. Workspace config is available in Settings.")
    else
        bootMessage("HUSH build 17: Rayfield loaded. F1 toggles the menu by default. " .. (nativeAimbot and "" or "Compatible aim mode active."))
    end
    task.delay(7, function() if bootGui.Parent then bootGui:Destroy() end end)
end)
if not guiOK then
    releaseFire()
    Config.Trigger, Config.Aim, Config.Hitboxes = false, false, false
    bootMessage("HUSH menu failed: " .. tostring(guiError) .. " — send this message to debug.")
    warn("Hush menu failed: " .. tostring(guiError))
end



