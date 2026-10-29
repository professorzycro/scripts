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
    return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
end)
assert(ok, "Rayfield failed to load: " .. tostring(Rayfield))
local window = Rayfield:CreateWindow({Name="Naval Warfare", LoadingTitle="Naval Warfare",
    LoadingSubtitle="ESP / Teleports / Weapons", ToggleUIKeybind="RightShift",
    ConfigurationSaving={Enabled=false}, Discord={Enabled=false}, KeySystem=false})
local settings = {esp=false, teamCheck=true, names=true, distance=15000,
    infinite=false, noCooldown=false, silent=false, fov=180, wallCheck=true}
local alive, links, records, visuals = true, {}, {}, {}
local folder = Instance.new("Folder")
folder.Name = "NavalLocalVisuals"
folder.Parent = workspace
local function notify(message)
    Rayfield:Notify({Title="Naval Warfare", Content=message, Duration=5})
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
local function target(origin)
    local camera=workspace.CurrentCamera
    if not camera then return end
    local mouse=UIS:GetMouseLocation()
    local best, score=nil,settings.fov
    for _,p in ipairs(Players:GetPlayers()) do
        if enemy(p) then
            local c,_,root=validCharacter(p)
            local part=c and (c:FindFirstChild("Head") or root)
            if part and (part.Position-origin).Magnitude<=400 then
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
        local visible=settings.esp and enemy(p) and root and (root.Position-camera.CFrame.Position).Magnitude<=settings.distance
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
local function destination(code)
    if code=="USA" or code=="Japan" then
        local name=code=="USA" and "USSpawn" or "JapanSpawn"
        local dock=workspace:FindFirstChild(code=="USA" and "USDock" or "JapanDock")
        if dock then
            for _,v in ipairs(dock:GetDescendants()) do
                if v:IsA("SpawnLocation") and v.Name==name then return v end
            end
        end
        for _,v in ipairs(workspace:GetDescendants()) do
            if v:IsA("SpawnLocation") and v.Name==name then return v end
        end
        return dock and dock:FindFirstChild("Flag",true)
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
local function modsOn() return settings.infinite or settings.noCooldown or settings.silent end
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
    local part=settings.silent and target(handle.Position)
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
    r.connection=tool.Activated:Connect(function() fire(tool,r) end)
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
visualsTab:CreateToggle({Name="Player ESP",CurrentValue=false,Callback=function(v) settings.esp=v;updateESP() end})
visualsTab:CreateToggle({Name="Enemies only (also applies to silent aim)",CurrentValue=true,Callback=function(v) settings.teamCheck=v end})
visualsTab:CreateToggle({Name="Names, health and distance",CurrentValue=true,Callback=function(v) settings.names=v end})
visualsTab:CreateSlider({Name="ESP distance",Range={500,30000},Increment=500,Suffix="studs",CurrentValue=15000,Callback=function(v) settings.distance=v end})
local tpTab=window:CreateTab("Teleports",0)
for _,code in ipairs({"A","B","C","USA","Japan"}) do
    tpTab:CreateButton({Name=(#code==1 and "Island " or "Base ")..code,Callback=function() teleport(code) end})
end
tpTab:CreateParagraph({Title="Loaded destinations",Content="Uses IslandCode A/B/C, USSpawn and JapanSpawn from the supplied saves. Exit your vehicle first. Destinations must be loaded."})
local gunsTab=window:CreateTab("Weapons",0)
local function setMod(key,value)
    settings[key]=value
    for _,r in pairs(records) do r.ready=0;r.ammo=r.capacity end
    refreshTools()
end
gunsTab:CreateToggle({Name="Infinite ammo (rifle / RPG client)",CurrentValue=false,Callback=function(v) setMod("infinite",v) end})
gunsTab:CreateToggle({Name="No reload cooldown (rifle / RPG client)",CurrentValue=false,Callback=function(v) setMod("noCooldown",v) end})
gunsTab:CreateToggle({Name="Silent aim (rifle / RPG)",CurrentValue=false,Callback=function(v) setMod("silent",v) end})
gunsTab:CreateToggle({Name="Silent aim visibility check",CurrentValue=true,Callback=function(v) settings.wallCheck=v end})
gunsTab:CreateSlider({Name="Silent aim radius",Range={25,600},Increment=5,Suffix="pixels",CurrentValue=180,Callback=function(v) settings.fov=v end})
gunsTab:CreateParagraph({Title="Weapon scope",Content="M1 Garand and RPG only. Click normally to shoot. Silent aim selects a player near your cursor within 400 studs without moving your camera. Server checks still apply; vehicle ammo and cooldowns are not modified."})
local systemTab=window:CreateTab("Settings",0)
local cleanup
cleanup=function()
    if not alive then return end
    alive=false
    settings.esp=false;settings.infinite=false;settings.noCooldown=false;settings.silent=false
    for _,c in ipairs(links) do c:Disconnect() end
    refreshTools()
    folder:Destroy()
    pcall(function() Rayfield:Destroy() end)
    if env.NavalWarfareCleanup==cleanup then env.NavalWarfareCleanup=nil end
end
env.NavalWarfareCleanup=cleanup
systemTab:CreateButton({Name="Unload and restore weapon callbacks",Callback=cleanup})
systemTab:CreateParagraph({Title="Controls",Content="Right Shift opens/closes the menu. Re-running unloads the previous copy. Turn all weapon toggles off to restore the original firing callbacks."})
local elapsed=0
connect(RunService.Heartbeat,function(dt)
    elapsed+=dt
    if elapsed<0.2 then return end
    elapsed=0
    updateESP()
    refreshTools()
end)
notify("Loaded. Enable features in the tabs; Right Shift toggles the menu.")
