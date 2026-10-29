-- Naval Warfare: based on the three supplied place 2210085102 saves.
-- Client-side only. Server-side ammo, damage and teleport checks still apply.
-- Rayfield API: https://docs-legacy.sirius.menu/rayfield
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
assert(player, "Run this on the client")
local env = (getgenv and getgenv()) or _G
if env.NavalWarfareCleanup then pcall(env.NavalWarfareCleanup) end
local ok, Rayfield = pcall(function()
    local source=game:HttpGet("https://sirius.menu/rayfield")
    -- Use Rayfield's existing visibility handler so each press toggles only once.
    source=source:gsub("return RayfieldLibrary%s*$",[[
function RayfieldLibrary:NavalSetMenuKey(key)
    overrideSetting("General", "rayfieldOpen", key)
end
return RayfieldLibrary
]])
    return loadstring(source)()
end)
assert(ok, "Rayfield failed to load: " .. tostring(Rayfield))
local window = Rayfield:CreateWindow({Name="Naval Warfare", LoadingTitle="Naval Warfare",
    LoadingSubtitle="ESP / Teleports / Weapons", ToggleUIKeybind=Enum.KeyCode.F1,
    ConfigurationSaving={Enabled=false}, Discord={Enabled=false}, KeySystem=false})
local settings = {esp=false, teamCheck=true, names=true, distance=15000,
    infinite=false, noCooldown=false, silent=false, fullAuto=false, fov=180, wallCheck=true,
    hitbox=false, hitboxSize=10, hitboxTransparency=0.7, menuKey="F1",
    vehicleESP=false, vehicleRange=15000, threats=false, threatRange=1800,
    filterPlayers=true, filterShips=true, filterAircraft=true, filterSubmarines=true,
    aimPlayerRange=400, aimVehicleRange=2000, teleportKeys=false,
    keyA="F2",keyB="F3",keyC="F4",keyUSA="F5",keyJapan="F6"}
local defaults=table.clone(settings)
local limits={distance={500,30000},fov={25,600},hitboxSize={2,30},hitboxTransparency={0,1},
    vehicleRange={500,30000},threatRange={250,5000},aimPlayerRange={25,400},aimVehicleRange={100,3000}}
local function validKey(key)
    return type(key)=="string" and key~="Unknown" and pcall(function() assert(Enum.KeyCode[key]) end)
end
local function applySettings(values)
    for key,default in pairs(defaults) do
        local value=values[key]
        if type(value)==type(default) then
            if type(value)=="number" then
                if value==value and math.abs(value)<math.huge then
                    local range=limits[key]
                    settings[key]=range and math.clamp(value,range[1],range[2]) or value
                end
            elseif type(value)=="string" then
                if validKey(value) then settings[key]=value end
            else settings[key]=value end
        end
    end
end
local alive, links, records, visuals = true, {}, {}, {}
local folder = Instance.new("Folder")
folder.Name = "NavalLocalVisuals"
folder.Parent = workspace
local function notify(message)
    Rayfield:Notify({Title="Naval Warfare", Content=message, Duration=5})
end
local configPath="NavalWarfare/settings.json"
local configAvailable=type(readfile)=="function" and type(writefile)=="function" and type(makefolder)=="function"
local HttpService=game:GetService("HttpService")
local configError
if configAvailable then
    pcall(function() makefolder("NavalWarfare") end)
    local exists=type(isfile)=="function" and isfile(configPath)
    if exists then
        local loaded,data=pcall(function() return HttpService:JSONDecode(readfile(configPath)) end)
        if loaded and type(data)=="table" and data.Version==1 and type(data.Settings)=="table" then
            applySettings(data.Settings)
        else configError="Saved settings could not be read; defaults were loaded." end
    end
end
local validMenuKey=pcall(function()
    assert(Enum.KeyCode[settings.menuKey] and settings.menuKey~="Unknown")
end)
if not validMenuKey then settings.menuKey="F1" end
if Rayfield.NavalSetMenuKey then Rayfield:NavalSetMenuKey(settings.menuKey) end
local function saveConfig(quiet)
    if not configAvailable then
        if not quiet then notify("This executor does not provide config file support.") end
        return false
    end
    local saved,err=pcall(function()
        writefile(configPath,HttpService:JSONEncode({Version=1,Settings=settings}))
    end)
    if not quiet then notify(saved and "Settings saved to NavalWarfare/settings.json" or "Config save failed: "..tostring(err)) end
    return saved
end
local savePending=false
local function queueSave()
    if savePending then return end
    savePending=true
    task.delay(0.3,function() savePending=false;if alive then saveConfig(true) end end)
end
local function connect(signal, fn)
    local c=signal:Connect(fn); table.insert(links,c); return c
end
local function enemy(p)
    return p ~= player and (not settings.teamCheck or p.Team == nil or player.Team == nil or p.Team ~= player.Team)
end
local function validCharacter(p)
    local c=p.Character
    local h=c and c:FindFirstChildOfClass("Humanoid")
    local root=c and c:FindFirstChild("HumanoidRootPart")
    if not h or h.Health<=0 or not root or c:FindFirstChildOfClass("ForceField") then return end
    return c,h,root
end
local vehicleKinds={Bomber="Aircraft",["Large Bomber"]="Aircraft",["Torpedo Bomber"]="Aircraft",
    Carrier="Ships",Battleship="Ships",Destroyer="Ships",Cruiser="Ships",["Heavy Cruiser"]="Ships",Submarine="Submarines"}
local vehicles={}
local vehicleVisuals={}
local function allowedKind(kind) return settings["filter"..kind]==true end
local function vehicleTeam(model)
    local team=model:FindFirstChild("Team")
    if team and team:IsA("ValueBase") then
        local value=team.Value
        if typeof(value)=="Instance" then return value.Name end
        if type(value)=="string" and value~="" then return value end
    end
    local ancestor=model.Parent
    while ancestor and ancestor~=workspace do
        if ancestor.Name=="JapanVehicles" then return "Japan" end
        if ancestor.Name=="USVehicles" then return "USA" end
        ancestor=ancestor.Parent
    end
end
local function vehicleHostile(v)
    return player.Team and v.team and v.team~=player.Team.Name
end
local function vehicleAllowed(v)
    return allowedKind(v.kind) and (not settings.teamCheck or vehicleHostile(v))
end
local function scanVehicles()
    local found={}
    local function visit(container)
        for _,m in ipairs(container:GetChildren()) do
            local kind=vehicleKinds[m.Name]
            if m:IsA("Model") and kind then
                local root=m:FindFirstChild("MainBody")
                local hp=m:FindFirstChild("HP")
                if root and root:IsA("BasePart") and (not hp or not hp:IsA("ValueBase") or tonumber(hp.Value)==nil or tonumber(hp.Value)>0) then
                    found[m]={model=m,root=root,kind=kind,team=vehicleTeam(m),hp=hp}
                end
            end
        end
    end
    visit(workspace)
    for _,name in ipairs({"USVehicles","JapanVehicles"}) do
        local container=workspace:FindFirstChild(name)
        if container then visit(container) end
    end
    vehicles=found
end
local function target(origin,isRPG)
    local camera=workspace.CurrentCamera
    if not camera then return end
    local mouse=UIS:GetMouseLocation()
    local best, score=nil,settings.fov
    local function consider(part,c,maxRange)
            if part and part.Parent and (part.Position-origin).Magnitude<=maxRange then
                local screen,onScreen=camera:WorldToScreenPoint(part.Position)
                local delta=(Vector2.new(screen.X,screen.Y)-mouse).Magnitude
                if onScreen and delta<score then
                    local clear=true
                    if settings.wallCheck then
                        local params=RaycastParams.new()
                        params.FilterType=Enum.RaycastFilterType.Exclude
                        params.FilterDescendantsInstances={player.Character,folder}
                        local result=workspace:Raycast(origin,part.Position-origin,params)
                        clear=not result or result.Instance:IsDescendantOf(c)
                    end
                    if clear then best=part; score=delta end
                end
            end
    end
    if settings.filterPlayers then
        for _,p in ipairs(Players:GetPlayers()) do
            if enemy(p) then
                local c,_,root=validCharacter(p)
                if c then consider(c:FindFirstChild("Head") or root,c,settings.aimPlayerRange) end
            end
        end
    end
    if isRPG then
        for _,v in pairs(vehicles) do
            if vehicleAllowed(v) then consider(v.root,v.model,settings.aimVehicleRange) end
        end
    end
    return best
end
local function removeVisual(p)
    local v=visuals[p]
    if v then v.highlight:Destroy();v.label:Destroy();visuals[p]=nil end
end
local function updateESP()
    local camera=workspace.CurrentCamera
    if not camera then return end
    for _,p in ipairs(Players:GetPlayers()) do
        local c,h,root=validCharacter(p)
        local visible=settings.esp and settings.filterPlayers and enemy(p) and root and (root.Position-camera.CFrame.Position).Magnitude<=settings.distance
        if visible then
            local v=visuals[p]
            if v and v.character~=c then removeVisual(p);v=nil end
            if not v then
                local hl=Instance.new("Highlight")
                hl.Adornee=c;hl.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
                hl.FillTransparency=0.65;hl.OutlineTransparency=0;hl.Parent=folder
                local bill=Instance.new("BillboardGui")
                bill.Adornee=c:FindFirstChild("Head") or root;bill.AlwaysOnTop=true
                bill.Size=UDim2.fromOffset(230,44);bill.StudsOffset=Vector3.new(0,3,0)
                bill.Parent=folder
                local text=Instance.new("TextLabel")
                text.Size=UDim2.fromScale(1,1);text.BackgroundTransparency=1
                text.TextColor3=Color3.new(1,1,1);text.TextStrokeTransparency=0.2
                text.Font=Enum.Font.GothamBold;text.TextSize=13;text.Parent=bill
                v={character=c,highlight=hl,label=bill,text=text};visuals[p]=v
            end
            local color=p.TeamColor.Color
            v.highlight.FillColor=color;v.highlight.OutlineColor=color
            v.label.Enabled=settings.names
            v.text.Text=string.format("%s (@%s)\n%d HP | %d studs",p.DisplayName,p.Name,math.floor(h.Health),math.floor((root.Position-camera.CFrame.Position).Magnitude))
        else removeVisual(p) end
    end
end
connect(Players.PlayerRemoving,removeVisual)
local threatTimes={}
local lastThreat=-math.huge
local function removeVehicleVisual(model)
    local v=vehicleVisuals[model]
    if v then v.highlight:Destroy();v.label:Destroy();vehicleVisuals[model]=nil end
end
local function updateVehicles()
    local camera=workspace.CurrentCamera
    if not camera then return end
    local character=player.Character
    local ownRoot=character and character:FindFirstChild("HumanoidRootPart")
    local observer=ownRoot and ownRoot.Position or camera.CFrame.Position
    local incoming,nearest=nil,math.huge
    for model,v in pairs(vehicles) do
        if not model.Parent or not v.root.Parent then removeVehicleVisual(model);continue end
        v.team=vehicleTeam(model)
        local distance=(v.root.Position-observer).Magnitude
        if settings.vehicleESP and vehicleAllowed(v) and distance<=settings.vehicleRange then
            local visual=vehicleVisuals[model]
            if not visual then
                local hl=Instance.new("Highlight")
                hl.Adornee=model;hl.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
                hl.FillTransparency=0.85;hl.Parent=folder
                local bill=Instance.new("BillboardGui")
                bill.Adornee=v.root;bill.AlwaysOnTop=true;bill.Size=UDim2.fromOffset(250,50)
                bill.StudsOffset=Vector3.new(0,12,0);bill.Parent=folder
                local text=Instance.new("TextLabel")
                text.Size=UDim2.fromScale(1,1);text.BackgroundTransparency=1
                text.Font=Enum.Font.GothamBold;text.TextSize=14;text.TextColor3=Color3.new(1,1,1)
                text.TextStrokeTransparency=0.2;text.Parent=bill
                visual={highlight=hl,label=bill,text=text};vehicleVisuals[model]=visual
            end
            local hostile=vehicleHostile(v)
            local color=hostile and Color3.fromRGB(255,90,80) or Color3.fromRGB(90,190,255)
            visual.highlight.FillColor=color;visual.highlight.OutlineColor=color
            local hp=v.hp and v.hp.Parent and tostring(v.hp.Value).." HP" or "HP unavailable"
            visual.text.Text=string.format("%s | %s\n%s | %d studs",model.Name,v.team or "Unknown team",hp,math.floor(distance))
        else removeVehicleVisual(model) end
        if settings.threats and ownRoot and vehicleHostile(v) and allowedKind(v.kind) and distance>1 and distance<=settings.threatRange then
            local relative=v.root.AssemblyLinearVelocity-ownRoot.AssemblyLinearVelocity
            local closing=-relative:Dot((v.root.Position-observer).Unit)
            if closing>5 and distance<nearest and os.clock()-(threatTimes[model] or -math.huge)>=20 then incoming=v;nearest=distance end
        end
    end
    for model in pairs(vehicleVisuals) do if not vehicles[model] then removeVehicleVisual(model) end end
    for model in pairs(threatTimes) do if not vehicles[model] then threatTimes[model]=nil end end
    if incoming and os.clock()-lastThreat>=6 then
        lastThreat=os.clock();threatTimes[incoming.model]=lastThreat
        notify(string.format("Incoming %s (%s): %d studs",incoming.model.Name,incoming.team,math.floor(nearest)))
    end
end
local expanded={}
local function restoreHitboxes()
    for part,original in pairs(expanded) do
        if part.Parent then
            part.Size=original.size
            part.Transparency=original.transparency
        end
        expanded[part]=nil
    end
end
local function updateHitboxes()
    local wanted={}
    if settings.hitbox and settings.filterPlayers then
        for _,p in ipairs(Players:GetPlayers()) do
            if enemy(p) then
                local _,_,root=validCharacter(p)
                if root then
                    wanted[root]=true
                    if not expanded[root] then expanded[root]={size=root.Size,transparency=root.Transparency} end
                    root.Size=Vector3.new(settings.hitboxSize,settings.hitboxSize,settings.hitboxSize)
                    root.Transparency=settings.hitboxTransparency
                end
            end
        end
    end
    for part,original in pairs(expanded) do
        if not wanted[part] then
            if part.Parent then part.Size=original.size;part.Transparency=original.transparency end
            expanded[part]=nil
        end
    end
end
local function destination(code)
    if code=="USA" or code=="Japan" then
        local dock=workspace:FindFirstChild(code=="USA" and "USDock" or "JapanDock")
        if not dock then return end
        -- Land on a broad harbor deck, not a lobby/team spawn or flagpole.
        for _,section in ipairs({"ShipsYard","ConcreteBases"}) do
            local area=dock:FindFirstChild(section,true)
            local best,score=nil,0
            for _,part in ipairs(area and area:GetDescendants() or {}) do
                if part:IsA("BasePart") and not part:IsA("SpawnLocation") and part.CanCollide and part.Anchored then
                    local surface=part.Size.X*part.Size.Z
                    if part.Size.Y<math.min(part.Size.X,part.Size.Z) and part.CFrame.UpVector.Y>0.95 and surface>score then
                        best=part;score=surface
                    end
                end
            end
            if best then return best end
        end
        return nil
    end
    for _,island in ipairs(workspace:GetChildren()) do
        local key=island:FindFirstChild("IslandCode")
        if island.Name=="Island" and key and string.upper(tostring(key.Value))==code then
            return island:FindFirstChild("FlagPad",true) or island:FindFirstChild("SpawnChecker",true) or island
        end
    end
end
local function teleport(code)
    local c=player.Character
    local hum=c and c:FindFirstChildOfClass("Humanoid")
    if not c or not hum or hum.Health<=0 then notify("Spawn your character first.");return end
    if hum.SeatPart then notify("Leave your vehicle before teleporting.");return end
    local point=destination(code)
    if not point then notify(code.." is not loaded. Move closer and try again.");return end
    local cf
    if point:IsA("BasePart") then cf=point.CFrame*CFrame.new(0,point.Size.Y/2+4,0)
    elseif point:IsA("Model") then cf=point:GetPivot()*CFrame.new(0,8,0) end
    if not cf then notify("No usable destination for "..code);return end
    c:PivotTo(cf)
    local root=c:FindFirstChild("HumanoidRootPart")
    if root then root.AssemblyLinearVelocity=Vector3.zero;root.AssemblyAngularVelocity=Vector3.zero end
end
local function modsOn() return settings.infinite or settings.noCooldown or settings.silent or settings.fullAuto end
local function gunHUD(tool,text)
    local pg=player:FindFirstChildOfClass("PlayerGui")
    local screen=pg and pg:FindFirstChild("ScreenGui")
    local label=screen and screen:FindFirstChild(tool.Name=="RPG" and "GunGui2" or "GunGui")
    if label and label:IsA("TextLabel") then label.Text=text;label.Visible=tool.Parent==player.Character end
end
local function fire(tool,record)
    if not alive or not modsOn() or tool.Parent~=player.Character or UIS:GetFocusedTextBox() then return end
    local now=os.clock()
    if now<record.ready then return end
    local event=ReplicatedStorage:FindFirstChild("Event")
    local handle=tool:FindFirstChild("Handle")
    if not event or not event:IsA("RemoteEvent") or not handle then return end
    if record.ammo<=0 and not settings.infinite and not settings.noCooldown then return end
    local mouse=player:GetMouse()
    local part=settings.silent and target(handle.Position,tool.Name=="RPG")
    local aim=part and part.Position or mouse.Hit.Position
    if (aim-handle.Position).Magnitude<0.01 then return end
    local sound=handle:FindFirstChild("FireSound")
    if sound then sound:Play() end
    if tool.Name=="RPG" then
        event:FireServer("fireRPG",{aim})
    else
        local params=RaycastParams.new()
        params.FilterType=Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances={player.Character,folder}
        local result=workspace:Raycast(handle.Position,(aim-handle.Position).Unit*400,params)
        local hit=result and result.Instance
        event:FireServer("shootRifle","",{hit})
        if hit then
            local model=hit:FindFirstAncestorOfClass("Model")
            local victim=model and Players:GetPlayerFromCharacter(model)
            local hum=model and model:FindFirstChildOfClass("Humanoid")
            -- Match the supplied TriggerScript's separate visual/hit messages.
            if victim and victim.Team~=player.Team and hum and hum.Health>0 and not model:FindFirstChildOfClass("ForceField") then
                event:FireServer("shootRifle","hit",{hum})
            end
        end
    end
    if not settings.infinite then record.ammo-=1 end
    local needsReload=record.ammo<=0 and not settings.infinite
    local delay=needsReload and not settings.noCooldown and 3 or 0.06
    record.ready=now+delay
    if needsReload and (settings.noCooldown or tool.Name=="RPG") then record.ammo=record.capacity end
    gunHUD(tool,settings.infinite and "Unlimited (client)" or (needsReload and not settings.noCooldown and "Reloading..." or record.ammo.."/"..record.capacity))
    if needsReload and not settings.noCooldown then
        task.delay(3,function()
            if alive and records[tool]==record then record.ammo=record.capacity;gunHUD(tool,record.ammo.."/"..record.capacity) end
        end)
    end
end
local function restoreTool(tool,r)
    if r.connection then r.connection:Disconnect() end
    if r.release then r.release:Disconnect() end
    for _,c in ipairs(r.originals) do pcall(function() c:Enable() end) end
    gunHUD(tool,tool.Name=="RPG" and "1/1" or "5/5")
    records[tool]=nil
end
local warned=false
local function installTool(tool)
    if records[tool] or not tool:IsA("Tool") or (tool.Name~="M1 Garand" and tool.Name~="RPG") then return end
    if type(getconnections)~="function" then
        if not warned then warned=true;notify("Weapon controls need getconnections support. ESP and teleport remain available.") end
        return
    end
    local success,connections=pcall(getconnections,tool.Activated)
    if not success or #connections==0 then return end -- Retry after TriggerScript initializes.
    local r={ammo=tool.Name=="RPG" and 1 or 5,capacity=tool.Name=="RPG" and 1 or 5,ready=0,originals={}}
    for _,c in ipairs(connections) do
        if c.Enabled~=false then
            local disabled=pcall(function() c:Disable() end)
            if not disabled then
                for _,prior in ipairs(r.originals) do pcall(function() prior:Enable() end) end
                notify("Cannot replace this weapon's firing callback.");return
            end
            table.insert(r.originals,c)
        end
    end
    if #r.originals==0 then return end
    records[tool]=r
    r.connection=tool.Activated:Connect(function() r.held=true;fire(tool,r) end)
    r.release=tool.Deactivated:Connect(function() r.held=false end)
end
local function refreshTools()
    if not modsOn() then
        local pending={};for t,r in pairs(records) do table.insert(pending,{t,r}) end
        for _,entry in ipairs(pending) do restoreTool(entry[1],entry[2]) end
        return
    end
    local backpack=player:FindFirstChildOfClass("Backpack")
    for _,container in pairs({player.Character,backpack}) do
        for _,tool in ipairs(container:GetChildren()) do installTool(tool) end
    end
    local stale={}
    for t,r in pairs(records) do
        if not t:IsDescendantOf(game) then table.insert(stale,{t,r}) end
    end
    for _,entry in ipairs(stale) do restoreTool(entry[1],entry[2]) end
end
local visualsTab=window:CreateTab("ESP",0)
local controls={}
local applyingPreset=false
local lastKeyEdit=-math.huge
local function settingControl(tab,method,key,options)
    local callback=options.Callback
    options.CurrentValue=settings[key]
    options.Callback=function(value)
        settings[key]=value
        if not applyingPreset then
            if callback then callback(value) end
            queueSave()
        end
    end
    local handle=tab[method](tab,options)
    controls[key]=handle
    return handle
end
settingControl(visualsTab,"CreateToggle","esp",{Name="Player ESP",Callback=updateESP})
settingControl(visualsTab,"CreateToggle","teamCheck",{Name="Enemies only (ESP, aim and hitboxes)",Callback=function() updateESP();updateHitboxes() end})
settingControl(visualsTab,"CreateToggle","names",{Name="Names, health and distance"})
settingControl(visualsTab,"CreateSlider","distance",{Name="ESP distance",Range={500,30000},Increment=500,Suffix="studs"})
settingControl(visualsTab,"CreateToggle","vehicleESP",{Name="Vehicle ESP",Callback=updateVehicles})
settingControl(visualsTab,"CreateSlider","vehicleRange",{Name="Vehicle ESP distance",Range={500,30000},Increment=500,Suffix="studs"})
settingControl(visualsTab,"CreateToggle","threats",{Name="Incoming vehicle alerts"})
settingControl(visualsTab,"CreateSlider","threatRange",{Name="Incoming alert radius",Range={250,5000},Increment=50,Suffix="studs"})
visualsTab:CreateParagraph({Title="Incoming alerts",Content="Warns about hostile ships, aircraft and submarines closing in faster than 5 studs/sec. Alerts pause for 6 seconds globally and 20 seconds per vehicle. Only loaded vehicles are tracked."})
local filtersTab=window:CreateTab("Target filters",0)
for _,kind in ipairs({"Players","Ships","Aircraft","Submarines"}) do
    settingControl(filtersTab,"CreateToggle","filter"..kind,{Name="Include "..kind,Callback=function() updateESP();updateHitboxes();updateVehicles() end})
end
settingControl(filtersTab,"CreateSlider","aimPlayerRange",{Name="Player aim distance",Range={25,400},Increment=25,Suffix="studs"})
settingControl(filtersTab,"CreateSlider","aimVehicleRange",{Name="RPG vehicle aim distance",Range={100,3000},Increment=100,Suffix="studs"})
filtersTab:CreateParagraph({Title="Filters",Content="Categories apply to ESP, incoming alerts and silent aim. Player hitbox expansion follows Include Players. Vehicle targeting is RPG only; the rifle uses player targets. Enemies-only is controlled in ESP. Unknown vehicle teams are hidden when enemies-only is on."})
local tpTab=window:CreateTab("Teleports",0)
for _,code in ipairs({"A","B","C","USA","Japan"}) do
    tpTab:CreateButton({Name=(#code==1 and "Island " or "Harbor ")..code,Callback=function() teleport(code) end})
end
tpTab:CreateParagraph({Title="Loaded destinations",Content="Uses IslandCode A/B/C and the USDock/JapanDock harbor decks. Exit your vehicle first. Destinations must be loaded."})
settingControl(tpTab,"CreateToggle","teleportKeys",{Name="Enable teleport hotkeys"})
local function keyControl(tab,key,name,onChange)
    local handle
    handle=tab:CreateKeybind({Name=name,CurrentKeybind=settings[key],HoldToInteract=false,CallOnChange=true,Callback=function(value)
        if not validKey(value) then return end
        lastKeyEdit=os.clock()
        if not applyingPreset then
            for _,other in ipairs({"menuKey","keyA","keyB","keyC","keyUSA","keyJapan"}) do
                if other~=key and settings[other]==value then
                    notify("That key is already assigned. Choose a different key.")
                    if handle then handle:Set(settings[key]) end
                    return
                end
            end
        end
        settings[key]=value
        if not applyingPreset then if onChange then onChange(value) end;queueSave() end
    end})
    controls[key]=handle
    return handle
end
for _,code in ipairs({"A","B","C","USA","Japan"}) do
    keyControl(tpTab,"key"..code,(#code==1 and "Island " or "Harbor ")..code.." hotkey")
end
tpTab:CreateParagraph({Title="Default hotkeys",Content="F2: A, F3: B, F4: C, F5: USA harbor, F6: Japan harbor. Enable teleport hotkeys above. Keys do not activate while typing or editing a keybind."})
local gunsTab=window:CreateTab("Weapons",0)
local function setMod(key,value)
    settings[key]=value
    for _,r in pairs(records) do r.ready=0;r.ammo=r.capacity end
    refreshTools()
end
settingControl(gunsTab,"CreateToggle","infinite",{Name="Infinite ammo (rifle / RPG client)",Callback=function(v) setMod("infinite",v) end})
settingControl(gunsTab,"CreateToggle","noCooldown",{Name="No reload cooldown (rifle / RPG client)",Callback=function(v) setMod("noCooldown",v) end})
settingControl(gunsTab,"CreateToggle","fullAuto",{Name="Full auto (hold fire)",Callback=function(v) setMod("fullAuto",v) end})
settingControl(gunsTab,"CreateToggle","silent",{Name="Silent aim (rifle / RPG)",Callback=function(v) setMod("silent",v) end})
settingControl(gunsTab,"CreateToggle","wallCheck",{Name="Silent aim visibility check"})
settingControl(gunsTab,"CreateSlider","fov",{Name="Silent aim radius",Range={25,600},Increment=5,Suffix="pixels"})
settingControl(gunsTab,"CreateToggle","hitbox",{Name="Hitbox expander",Callback=updateHitboxes})
settingControl(gunsTab,"CreateSlider","hitboxSize",{Name="Hitbox size",Range={2,30},Increment=1,Suffix="studs",Callback=updateHitboxes})
settingControl(gunsTab,"CreateSlider","hitboxTransparency",{Name="Hitbox transparency",Range={0,1},Increment=0.05,Callback=updateHitboxes})
gunsTab:CreateParagraph({Title="Hitboxes",Content="Expands player root hitboxes locally. Uses the enemies-only setting. Turning it off or unloading restores original sizes and visibility. Server hit validation still applies."})
gunsTab:CreateParagraph({Title="Weapon scope",Content="M1 Garand and RPG only. Full auto repeats while you hold fire. Silent aim selects targets near the cursor using Target filters; RPG can target vehicles. Server checks still apply; vehicle ammo and cooldowns are not modified."})
local systemTab=window:CreateTab("Settings",0)
keyControl(systemTab,"menuKey","Hide / show menu",function(key)
        if not Rayfield.NavalSetMenuKey then
            notify("This Rayfield version cannot rebind the menu; F1 remains active.");return
        end
        Rayfield:NavalSetMenuKey(key)
    end)
local presetsTab=window:CreateTab("Presets",0)
local function builtIn(changes)
    local result=table.clone(defaults)
    for key,value in pairs(changes) do result[key]=value end
    return result
end
local builtIns={
    Infantry=builtIn({esp=true,filterShips=false,filterAircraft=false,filterSubmarines=false}),
    Naval=builtIn({vehicleESP=true,threats=true,esp=true,vehicleRange=20000,threatRange=2000}),
    Flying=builtIn({vehicleESP=true,threats=true,vehicleRange=25000,threatRange=3000})}
local presets={}
local presetPath="NavalWarfare/presets.json"
if configAvailable then
    local success,data=pcall(function() return HttpService:JSONDecode(readfile(presetPath)) end)
    if success and type(data)=="table" and data.Version==1 and type(data.Presets)=="table" then
        for name,values in pairs(data.Presets) do
            if type(name)=="string" and #name<=32 and type(values)=="table" and not builtIns[name] then presets[name]=values end
        end
    end
end
local function presetNames()
    local names={"Infantry","Naval","Flying"}
    local custom={};for name in pairs(presets) do table.insert(custom,name) end
    table.sort(custom);for _,name in ipairs(custom) do table.insert(names,name) end
    return names
end
local selectedPreset="Infantry"
local customName=""
local presetDropdown=presetsTab:CreateDropdown({Name="Select preset",Options=presetNames(),CurrentOption={selectedPreset},MultipleOptions=false,Callback=function(value) selectedPreset=value[1] end})
presetsTab:CreateInput({Name="Custom preset name",PlaceholderText="Up to 32 characters",RemoveTextAfterFocusLost=false,Callback=function(value) customName=tostring(value):match("^%s*(.-)%s*$") end})
local function savePresets()
    if not configAvailable then notify("Preset saving requires file support.");return false end
    local success,err=pcall(function() writefile(presetPath,HttpService:JSONEncode({Version=1,Presets=presets})) end)
    if not success then notify("Could not save presets: "..tostring(err)) end
    return success
end
presetsTab:CreateButton({Name="Save current settings as custom preset",Callback=function()
    if customName=="" or #customName>32 then notify("Enter a preset name from 1 to 32 characters.");return end
    if builtIns[customName] then notify("Choose a custom name; built-in presets are reserved.");return end
    local old=presets[customName]
    presets[customName]=table.clone(settings)
    if not savePresets() then presets[customName]=old;return end
    presetDropdown:Refresh(presetNames());presetDropdown:Set({customName})
    selectedPreset=customName
    notify("Saved preset: "..customName)
end})
presetsTab:CreateButton({Name="Load selected preset",Callback=function()
    local values=builtIns[selectedPreset] or presets[selectedPreset]
    if not values then notify("Select a valid preset first.");return end
    applyingPreset=true
    applySettings(defaults);applySettings(values)
    local seen={}
    for _,key in ipairs({"menuKey","keyA","keyB","keyC","keyUSA","keyJapan"}) do
        if seen[settings[key]] then
            for _,reset in ipairs({"menuKey","keyA","keyB","keyC","keyUSA","keyJapan"}) do settings[reset]=defaults[reset] end
            break
        end
        seen[settings[key]]=true
    end
    local desired=table.clone(settings)
    local success,err=pcall(function()
        for key,handle in pairs(controls) do handle:Set(desired[key]) end
    end)
    applyingPreset=false
    applySettings(desired)
    if Rayfield.NavalSetMenuKey then Rayfield:NavalSetMenuKey(settings.menuKey) end
    for _,r in pairs(records) do r.held=false;r.ready=0;r.ammo=r.capacity end
    refreshTools();updateESP();updateHitboxes();updateVehicles();queueSave()
    notify(success and "Loaded preset: "..selectedPreset or "Settings loaded; a UI control could not refresh: "..tostring(err))
end})
presetsTab:CreateButton({Name="Delete selected custom preset",Callback=function()
    if not presets[selectedPreset] then notify("Only custom presets can be deleted.");return end
    local name,old=selectedPreset,presets[selectedPreset]
    presets[name]=nil
    if not savePresets() then presets[name]=old;return end
    selectedPreset="Infantry";presetDropdown:Refresh(presetNames());presetDropdown:Set({selectedPreset})
    notify("Deleted preset: "..name)
end})
presetsTab:CreateParagraph({Title="Preset files",Content="Infantry, Naval and Flying are built in. Custom presets store all settings and keybinds in NavalWarfare/presets.json. Loading a preset immediately applies it and updates the menu."})
local cleanup
cleanup=function()
    if not alive then return end
    saveConfig(true)
    alive=false
    settings.esp=false;settings.infinite=false;settings.noCooldown=false;settings.silent=false;settings.fullAuto=false
    for _,c in ipairs(links) do c:Disconnect() end
    refreshTools()
    restoreHitboxes()
    for model in pairs(vehicleVisuals) do removeVehicleVisual(model) end
    folder:Destroy()
    pcall(function() Rayfield:Destroy() end)
    if env.NavalWarfareCleanup==cleanup then env.NavalWarfareCleanup=nil end
end
env.NavalWarfareCleanup=cleanup
systemTab:CreateButton({Name="Unload and restore weapon callbacks",Callback=cleanup})
systemTab:CreateButton({Name="Save settings now",Callback=function() saveConfig(false) end})
systemTab:CreateParagraph({Title="Config file",Content=configAvailable and "Settings save automatically to NavalWarfare/settings.json in your executor workspace and load next time you run this script." or "Config saving is unavailable: this executor needs readfile, writefile and makefolder support."})
systemTab:CreateParagraph({Title="Controls",Content="F1 hides/shows the menu by default. Change Hide / show menu above to rebind; your choice saves in the config. Re-running unloads the previous copy."})
local elapsed,scanElapsed=0,0
scanVehicles()
connect(RunService.Heartbeat,function(dt)
    for tool,r in pairs(records) do
        if tool.Parent~=player.Character then r.held=false end
        if settings.fullAuto and r.held then fire(tool,r) end
    end
    elapsed+=dt
    scanElapsed+=dt
    if scanElapsed>=2 then scanElapsed=0;scanVehicles() end
    if elapsed<0.2 then return end
    elapsed=0
    updateESP()
    updateHitboxes()
    updateVehicles()
    refreshTools()
end)
local lastTeleport=-math.huge
connect(UIS.InputBegan,function(input,processed)
    if processed or UIS:GetFocusedTextBox() or not settings.teleportKeys or os.clock()-lastKeyEdit<0.3 or os.clock()-lastTeleport<1 then return end
    for _,code in ipairs({"A","B","C","USA","Japan"}) do
        if input.KeyCode==Enum.KeyCode[settings["key"..code]] then
            lastTeleport=os.clock();teleport(code);return
        end
    end
end)
connect(UIS.InputEnded,function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 then
        for _,r in pairs(records) do r.held=false end
    end
end)
connect(UIS.WindowFocusReleased,function()
    for _,r in pairs(records) do r.held=false end
end)
if configError then notify(configError) end
notify("Loaded. "..settings.menuKey.." hides/shows the menu. Change it under Settings.")
