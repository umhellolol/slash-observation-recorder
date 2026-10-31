-- Slash Modifier Recorder v3.0.0 (diagnostic only)
-- Edits only existing replicated client fields; never fires remotes or claims server success.
local Players=game:GetService("Players")
local Http=game:GetService("HttpService")
local player=assert(Players.LocalPlayer,"Run this from a connected Roblox client")
local env=(getgenv and getgenv()) or _G
local KEY="SlashModifierRecorderV2"
local old=env[KEY]
if type(old)=="table" and old.running and old.focus then pcall(old.focus);print("Slash Modifier Experiment is already open.");return end
if type(old)=="table" and old.running==false then env[KEY]=nil end
if type(env.SlashModifierRecorder)=="table" and env.SlashModifierRecorder.running then print("Close the older modifier recorder before starting v3 so its writes can restore safely.");return end
local NOW=function()return DateTime.now().UnixTimestampMillis end
local state={version="3.0.0",running=true,startedAt=NOW(),events={},writes={},trials={},trialStages={},originals={},lastWrites={},connections={},testConnections={},boundRemotes={},testRunning=false,runId=0,ui=nil,droppedEvents=0,droppedWrites=0,droppedTrials=0,droppedRemoteEvents=0}
env[KEY]=state
local baseFactorNames={"FriendPowerPercent","AuraMultiplier","SwordPowerMultiplier","SwordWinsMultiplier","SwordAttackSpeedMultiplier","AdminPowerMultiplier","AdminWinsMultiplier","PetMultiplier","PowerMultiplier","WinsMultiplier"}
local factorNames={};for _,n in ipairs(baseFactorNames)do factorNames[#factorNames+1]=n end
local statNames={"Power","Wins","Rebirths","Crystals"}
local maxRows=1000
local extraFields={}
local function finite(v)return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge end
local function numberText(v)if type(v)=="number"then return string.format("%.17g",v)end;if v==nil then return "(missing)"end;return tostring(v)end
local function safeText(v,n)local s=tostring(v or "");return s:sub(1,n or 160)end
local function scalar(v)
 if v==nil then return nil end
 if finite(v) or type(v)=="string" or type(v)=="boolean" then return v end
 return tostring(v)
end
local function clone(v,d)d=d or 0;if d>8 then return "(depth)"end;if type(v)~="table"then return v end;local o={};for k,x in pairs(v)do o[k]=clone(x,d+1)end;return o end
local function findValue(parent,name)local x=parent and parent:FindFirstChild(name);return x and x:IsA("ValueBase") and x or nil end
local function readField(field)if not field then return nil end;if field.kind=="attribute"then return scalar(field.instance:GetAttribute(field.name))end;return scalar(field.instance.Value)end
local function attached(instance)
 if not instance then return false end
 local ok,found=pcall(function()local current=instance;for _=1,100 do if current==player then return true end;if not current then return false end;current=current.Parent end;return false end)
 return ok and found
end
local function writeField(field,value)
 if not field then return false,"missing field"end
 if not attached(field.instance) then return false,"field instance was replaced or detached" end
 if not finite(value) then return false,"value must be finite" end
 if field.kind=="attribute"then
  local current=field.instance:GetAttribute(field.name)
  if not finite(current) then return false,"existing attribute is not numeric" end
  local ok,err=pcall(function()field.instance:SetAttribute(field.name,value)end)
  return ok,ok and nil or tostring(err)
 end
 if field.instance:IsA("NumberValue")or field.instance:IsA("IntValue")then
  local ok,err=pcall(function()field.instance.Value=value end)
  return ok,ok and nil or tostring(err)
 end
 return false,"field is not writable"
end
local function fieldFor(name)
 local extra=extraFields[name]
 if extra and attached(extra.instance) then local value=extra.instance:GetAttribute(extra.attr);if finite(value) then return {kind="attribute",instance=extra.instance,name=extra.attr,original=value,id=name}end end
 local ps=player:FindFirstChild("PlayerStats");local a=player:GetAttribute(name)
 if finite(a) then return {kind="attribute",instance=player,name=name,original=a}end
 local v=findValue(ps,name);if v and finite(v.Value) then return {kind="value",instance=v,name=name,original=v.Value}end;return nil
end
local function discoverFields()
 factorNames={};for _,n in ipairs(baseFactorNames)do factorNames[#factorNames+1]=n end;extraFields={}
 local folders={"PetInventory","OwnedAuras","OwnedCharms","EquippedCharms","SwordUnlocks"};local attrsToCheck={"Multiplier","StrengthFactor","PowerMultiplier","WinsMultiplier","WinMultiplier","DropPercent","DropChance","SwordPower","SwordWins","AuraMultiplier"};local count=0
 for _,folderName in ipairs(folders)do local root=player:FindFirstChild(folderName);if root then for _,item in ipairs(root:GetChildren())do if count>=100 then break end;for _,attr in ipairs(attrsToCheck)do local value=item:GetAttribute(attr);if count<100 and finite(value) then local id=folderName.."/"..item.Name.."/"..attr;extraFields[id]={instance=item,attr=attr};factorNames[#factorNames+1]=id;count=count+1 end end end end end
end
local function statField(name)local ns=player:FindFirstChild("NumericStats");local ps=player:FindFirstChild("PlayerStats");local v=findValue(ns,name)or findValue(ps,name);if v and finite(v.Value) then return {kind="value",instance=v,name=name,original=v.Value}end;local a=player:GetAttribute(name);return finite(a) and {kind="attribute",instance=player,name=name,original=a}or nil end
local function attrs(item)local out={};for _,name in ipairs({"Multiplier","StrengthFactor","Equipped","Tier","MergeLevel","Owned","Rarity","SwordName","PetName"})do local v=item:GetAttribute(name);if v~=nil then out[name]=scalar(v)end end;return out end
local function folder(name)local root=player:FindFirstChild(name);if not root then return {available=false,items={}}end;local rows={};local children=root:GetChildren();table.sort(children,function(a,b)return a.Name<b.Name end);for i,item in ipairs(children)do if i>maxRows then break end;rows[#rows+1]={id=safeText(item.Name),value=item:IsA("ValueBase")and scalar(item.Value)or nil,attributes=attrs(item)}end;return {available=true,items=rows,truncated=#children>maxRows}end
local function snapshot()
 local out={stats={},statsRaw={},factors={},inventory={}};for _,n in ipairs(statNames)do local v=readField(statField(n));out.stats[n]=v;if finite(v)then out.statsRaw[n]={value=numberText(v),precision="binary64",precisionLimited=math.abs(v)>9007199254740991}end end;for _,n in ipairs(factorNames)do out.factors[n]=readField(fieldFor(n))end
 local ps=player:FindFirstChild("PlayerStats");local ev=findValue(ps,"EquippedAura");out.factors.EquippedAura=ev and scalar(ev.Value)or scalar(ps and ps:GetAttribute("EquippedAura"))
 for _,n in ipairs({"EquippedCharms","OwnedCharms","SwordUnlocks","OwnedAuras","PetInventory"})do out.inventory[n]=folder(n)end;return out
end
local function roster()
 local out={};local list=Players:GetPlayers();for i,p in ipairs(list)do if i>200 then break end;out[#out+1]={userId=p.UserId,name=safeText(p.Name,80)}end
 return {players=out,truncated=#list>200}
end
local function observed(v,depth,seen)
 depth=depth or 0;seen=seen or {_remaining=128};seen._remaining=seen._remaining-1;if seen._remaining<0 then state.payloadTruncations=(state.payloadTruncations or 0)+1;return "(payload limit)"end;if depth>3 then state.payloadTruncations=(state.payloadTruncations or 0)+1;return "(depth truncated)" end
 if v==nil or finite(v) or type(v)=="boolean" then return v end
 if type(v)=="string" then if #v>120 then state.payloadTruncations=(state.payloadTruncations or 0)+1 end;return safeText(v,120) end
 if type(v)=="table" then if seen[v] then return "(cycle)" end;seen[v]=true;local out={};local n=0;for k,x in pairs(v)do n=n+1;if n>40 then state.payloadTruncations=(state.payloadTruncations or 0)+1;out._truncated=true;break end;local key=safeText(k,60);local lower=key:lower();if lower:find("token",1,true)or lower:find("cookie",1,true)or lower:find("password",1,true)or lower:find("secret",1,true)or lower:find("pairingkey",1,true)then out[key]="(redacted)"else out[key]=observed(x,depth+1,seen)end end;return out end
 local ok,name=pcall(function()return v.GetFullName and v:GetFullName()end);return ok and {instance=safeText(name or tostring(v),160)}or safeText(v,120)
end
local testEvent
local remoteLimit=200
local function connectRemote(remote)
 if not remote or state.boundRemotes[remote] then return end
 if (state.remoteCount or 0)>=remoteLimit then state.remoteLimitReached=true;return end
 state.boundRemotes[remote]=true;state.remoteCount=(state.remoteCount or 0)+1
 local ok,conn=pcall(function()return remote.OnClientEvent:Connect(function(...)testEvent("incoming_event",{remote=safeText(remote:GetFullName(),180),args=observed(table.pack(...)),direction="server-to-client-observed"})end)end)
 if ok and conn then state.testConnections[#state.testConnections+1]=conn;testEvent("route_subscribed",{remote=safeText(remote:GetFullName(),180),delivery="not yet observed"})else testEvent("route_error",{remote=safeText(remote:GetFullName(),180),message=safeText(conn)})end
end
local function connectKnownRemotes()
 local okService,rs=pcall(function()return game:GetService("ReplicatedStorage")end);if not okService or not rs then return end
 for _,route in ipairs({{"PunchEscapeRemotes","Effects"},{"PunchEscapeRemotes","TradeRemote"},{"PunchEscapeRemotes","SwordDropEvent"},{"PunchEscapeRemotes","CharmShopRequest"},{"PunchEscapeAdminRemotes","CharmShowerVisuals"},{"PunchEscapeAdminBladeRemotes","Event"},{"PetInventoryResult"},{"LuckyBlockOpenResult"}})do
  local item=rs;for _,part in ipairs(route)do item=item and item:FindFirstChild(part)end
  if item and item:IsA("RemoteEvent")then connectRemote(item)else testEvent("route_unavailable",{remote=table.concat(route,"."),status=item and "wrong class"or "not visible"})end
 end
 local count=0
 for _,x in ipairs(rs:GetDescendants())do if count>=200 then break end;if x:IsA("RemoteEvent") then connectRemote(x);count=count+1 end end
 if rs.DescendantAdded then state.testConnections[#state.testConnections+1]=rs.DescendantAdded:Connect(function(x)if state.testRunning and x:IsA("RemoteEvent")then connectRemote(x)end end)end
 testEvent("remote_scan",{count=count,limit=200})
 local service=Players
 if service.PlayerAdded then state.testConnections[#state.testConnections+1]=service.PlayerAdded:Connect(function(p)testEvent("player_added",{userId=p.UserId,name=safeText(p.Name,80),friendPowerBefore=readField(fieldFor("FriendPowerPercent")),relationship="unknown"})end)end
 if service.PlayerRemoving then state.testConnections[#state.testConnections+1]=service.PlayerRemoving:Connect(function(p)testEvent("player_removing",{userId=p.UserId,name=safeText(p.Name,80),friendPowerAtRemoval=readField(fieldFor("FriendPowerPercent")),relationship="unknown"})end)end
end
discoverFields()
local function same(a,b)return type(a)==type(b)and a==b end
local function diff(a,b)if finite(a)and finite(b)then return b-a end end
local function logEvent(kind,data)
 if not state.testRunning and kind~="restore_all"and kind~="error"then return end
 state.sequence=(state.sequence or 0)+1
 local record={sequence=state.sequence,observedAt=NOW(),elapsedMs=NOW()-state.startedAt,kind=kind,data=clone(data)}
 local ok,encoded=pcall(function()return Http:JSONEncode(record)end)
 local bytes=ok and #encoded or 0
 if ok and #state.events<10000 and (state.eventBytes or 0)+bytes<=4000000 then state.events[#state.events+1]=record;state.eventBytes=(state.eventBytes or 0)+bytes
 else state.droppedEvents=(state.droppedEvents or 0)+1;if kind=="incoming_event"then state.droppedRemoteEvents=(state.droppedRemoteEvents or 0)+1 end end
end

testEvent=function(kind,data)if state.testRunning then logEvent(kind,data)end end
local function recordWrite(row)if #state.writes<500 then state.writes[#state.writes+1]=row else state.droppedWrites=state.droppedWrites+1 end end
local function fieldSame(a,b)return a and b and a.kind==b.kind and a.instance==b.instance and a.name==b.name end
local function restoreOne(name)
 local w=state.lastWrites[name];if not w then return false,"not written by this run"end
 local currentField=fieldFor(name)
 if not fieldSame(w.field,currentField) or not attached(w.field.instance) then return false,"field instance was replaced or detached; left untouched" end
 local cur=readField(w.field);if not same(cur,w.requested)then return false,"value changed; left untouched"end
 local ok,err=writeField(w.field,w.original);if ok then state.lastWrites[name]=nil;recordWrite({at=NOW(),name=name,action="restore",value=w.original});return true end;return false,err
end
local function apply(name,requested)
 if not state.testRunning then return false,"Press Start test before editing a value"end
 local n=tonumber(requested);if not finite(n)then return false,"enter a finite number"end
 local f=fieldFor(name);if not f then return false,"field is not present or not numeric"end
 local prior=state.lastWrites[name]
 local current=readField(f)
 local original=(prior and fieldSame(prior.field,f) and same(current,prior.requested) and prior.original) or f.original
 local ok,err=writeField(f,n);if not ok then return false,err end
 local observed=readField(f)
 state.lastWrites[name]={field=f,original=original,requested=observed};recordWrite({at=NOW(),name=name,action="apply",before=current,requested=n,observed=observed});logEvent("write",{name=name,before=current,requested=n,observed=observed});return true,"Requested "..numberText(n).."; local value "..numberText(observed)..". Reward effect unknown."
end
local function restoreAll()local results={};for name in pairs(state.lastWrites)do local ran,ok,err=pcall(restoreOne,name);results[name]=ran and (ok and "restored"or err)or "Restore failed: "..tostring(ok)end;state.restoreResults=results;logEvent("restore_all",results);return results end
local function export()
 local report={schemaVersion=3,version=state.version,runId=state.runId,testRunning=state.testRunning,startedAt=state.startedAt,endedAt=state.endedAt or NOW(),roster=state.initialRoster,finalRoster=state.finalRoster,eventBytes=state.eventBytes,payloadTruncations=state.payloadTruncations,remoteCount=state.remoteCount,remoteLimitReached=state.remoteLimitReached,placeId=tostring(game.PlaceId),jobId=tostring(game.JobId),initial=state.initial,final=state.final,events=state.events,droppedEvents=state.droppedEvents or 0,droppedRemoteEvents=state.droppedRemoteEvents or 0,droppedWrites=state.droppedWrites,droppedTrials=state.droppedTrials,writes=state.writes,trials=state.trials,trialStages=state.trialStages,restoreResults=state.restoreResults,limitations={"Client-visible fields only; edited values are not proof of server acceptance.","Incoming events are server-to-client observations; no remotes were fired, replayed or hooked.","Reward deltas are sampled observations; repeat the same action with one factor changed.","Large values retain exposed floating-point precision; abbreviated UI strings are excluded."}}
 local ok,payload=pcall(function()return Http:JSONEncode(report)end);if not ok then warn("Export failed: "..tostring(payload));return nil,"JSON encode failed: "..tostring(payload)end
 state.report=report;state.json=payload;local name="Slash-Modifier-Experiment-"..tostring(state.startedAt).."-run"..tostring(state.runId)..".json";state.export={name=name,ok=false,reason="no local write API"}
 if type(writefile)=="function"then local wrote,werr=pcall(writefile,name,payload);if wrote and type(readfile)=="function"then local rok,readback=pcall(readfile,name);if rok and readback==payload then state.export={name=name,ok=true,verified=true};else state.export={name=name,ok=false,written=true,reason="readback mismatch or failed"}end elseif wrote then state.export={name=name,ok=true,written=true,verified=false,reason="write succeeded; readback API unavailable"}else state.export={name=name,ok=false,reason=tostring(werr)}end end
 if type(setclipboard)=="function" then local cok=pcall(setclipboard,payload);state.export.clipboard=cok end
 local msg=state.export.verified and "Export verified: "..name or state.export.written and "File written; readback unverified: "..name or state.export.clipboard and "JSON copied to clipboard; file not verified" or "File/clipboard unavailable; use Show JSON to select and copy"
 return payload,msg end
local gui=Instance.new("ScreenGui");gui.Name="SlashModifierExperiment";gui.ResetOnSpawn=false;gui.DisplayOrder=999;gui.Parent=player:WaitForChild("PlayerGui");state.ui=gui
local frame=Instance.new("Frame");frame.Visible=true;frame.Size=UDim2.fromOffset(640,520);frame.Position=UDim2.new(.5,-320,.5,-260);frame.BackgroundColor3=Color3.fromRGB(22,25,33);frame.Parent=gui
local title=Instance.new("TextLabel");title.Size=UDim2.new(1,-44,0,34);title.Text="SLASH / EVENT RECORDER v3";title.TextColor3=Color3.new(1,1,1);title.BackgroundTransparency=1;title.Parent=frame
local close=Instance.new("TextButton");close.Size=UDim2.fromOffset(34,30);close.Position=UDim2.new(1,-38,0,2);close.Text="×";close.Parent=frame
local status=Instance.new("TextLabel");status.Size=UDim2.new(1,-20,0,42);status.Position=UDim2.fromOffset(10,35);status.TextWrapped=true;status.TextXAlignment=Enum.TextXAlignment.Left;status.Text="Only existing client fields can be tested. Server acceptance is unknown.";status.TextColor3=Color3.fromRGB(255,205,120);status.BackgroundTransparency=1;status.Parent=frame
local scroll=Instance.new("ScrollingFrame");scroll.Size=UDim2.new(1,-20,1,-185);scroll.Position=UDim2.fromOffset(10,82);scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y;scroll.BackgroundColor3=Color3.fromRGB(30,34,44);scroll.Parent=frame
local layout=Instance.new("UIListLayout");layout.Padding=UDim.new(0,5);layout.Parent=scroll
local rows={};local function setStatus(t)status.Text=safeText(t,300)end
local toggle=Instance.new("TextButton");toggle.Name="TogglePanel";toggle.Size=UDim2.fromOffset(180,30);toggle.Position=UDim2.fromOffset(12,50);toggle.Text="Hide modifier panel";toggle.Parent=gui
toggle.MouseButton1Click:Connect(function()frame.Visible=not frame.Visible;toggle.Text=frame.Visible and "Hide modifier panel" or "Show modifier panel"end)
local function callback(fn)local ok,err=pcall(fn);if not ok then logEvent("callback_error",{message=tostring(err)});setStatus("Error: "..tostring(err))end end
local function makeRow(name)
 local row=Instance.new("Frame");row.Name="Modifier_"..name;row.Size=UDim2.new(1,-14,0,76);row.BackgroundTransparency=1;row.Parent=scroll
 local label=Instance.new("TextLabel");label.Size=UDim2.new(.3,0,1,0);label.Text=name;label.TextXAlignment=Enum.TextXAlignment.Left;label.TextColor3=Color3.new(1,1,1);label.BackgroundTransparency=1;label.Parent=row
 local original=Instance.new("TextLabel");original.Name="Original";original.Size=UDim2.new(.2,0,0,20);original.Position=UDim2.fromScale(.3,0);original.Text="original: —";original.TextColor3=Color3.fromRGB(180,180,190);original.BackgroundTransparency=1;original.Parent=row
 local current=Instance.new("TextLabel");current.Name="Current";current.Size=UDim2.new(.2,0,0,20);current.Position=UDim2.fromScale(.3,.45);current.Text="current: —";current.TextColor3=Color3.fromRGB(180,210,255);current.BackgroundTransparency=1;current.Parent=row
 local input=Instance.new("TextBox");input.Name="Requested";input.Size=UDim2.new(.2,0,0,28);input.Position=UDim2.fromScale(.51,.18);input.PlaceholderText="requested";input.ClearTextOnFocus=false;input.Parent=row
 local button=Instance.new("TextButton");button.Name="Apply";button.Size=UDim2.fromOffset(48,28);button.Position=UDim2.new(1,-104,0,.18);button.Text="Set";button.Parent=row
 local undo=Instance.new("TextButton");undo.Name="Restore";undo.Size=UDim2.fromOffset(52,28);undo.Position=UDim2.new(1,-52,0,.18);undo.Text="Undo";undo.Parent=row
 button.MouseButton1Click:Connect(function()callback(function()local ok,msg=apply(name,input.Text);setStatus(msg);if ok then current.Text="current: "..numberText(readField(fieldFor(name)));original.Text="original: "..numberText(state.lastWrites[name] and state.lastWrites[name].original or fieldFor(name) and fieldFor(name).original)end end)end)
 undo.MouseButton1Click:Connect(function()callback(function()local ok,msg=restoreOne(name);setStatus(ok and "Restored "..name or "Restore refused: "..tostring(msg))end)end)
 label.Size=UDim2.new(1,0,0,22);label.TextSize=13;label.TextTruncate=Enum.TextTruncate.AtEnd
 original.Size=UDim2.fromOffset(170,22);original.Position=UDim2.fromOffset(0,25);original.TextSize=12
 current.Size=UDim2.fromOffset(170,22);current.Position=UDim2.fromOffset(175,25);current.TextSize=12
 input.Size=UDim2.fromOffset(140,28);input.Position=UDim2.fromOffset(350,25)
 button.Position=UDim2.new(1,-104,0,25);undo.Position=UDim2.new(1,-52,0,25)
 rows[name]={current=current,original=original,input=input}
end
for _,name in ipairs(factorNames)do makeRow(name)end
local function button(text,x,parent)local b=Instance.new("TextButton");b.Size=UDim2.fromOffset(105,30);b.Position=UDim2.fromOffset(x,0);b.Text=text;b.Parent=parent;return b end
local controls=Instance.new("Frame");controls.Name="TestControls";controls.Size=UDim2.new(1,-20,0,34);controls.Position=UDim2.new(0,10,1,-55);controls.BackgroundTransparency=1;controls.Parent=frame
local startTest=button("Start test",0,controls);startTest.Name="StartTest";local stopTestButton=button("Stop test",110,controls);stopTestButton.Name="StopTest"
local trialControls=Instance.new("Frame");trialControls.Size=UDim2.new(1,-20,0,34);trialControls.Position=UDim2.new(0,10,1,-90);trialControls.BackgroundTransparency=1;trialControls.Parent=frame
local restore=button("Restore all",0,trialControls);local save=button("Export",110,trialControls)
local show=button("Show JSON",220,trialControls)
local jsonBox=Instance.new("TextBox");jsonBox.Name="ExportJSON";jsonBox.Size=UDim2.new(1,-20,0,300);jsonBox.Position=UDim2.fromOffset(10,82);jsonBox.MultiLine=true;jsonBox.ClearTextOnFocus=false;jsonBox.TextEditable=false;jsonBox.TextSize=12;jsonBox.TextXAlignment=Enum.TextXAlignment.Left;jsonBox.TextYAlignment=Enum.TextYAlignment.Top;jsonBox.Visible=false;jsonBox.Parent=frame
show.MouseButton1Click:Connect(function()callback(function()if jsonBox.Visible then jsonBox.Visible=false;scroll.Visible=true;show.Text="Show JSON"else local p,msg=export();if p then jsonBox.Text=p;jsonBox.Visible=true;scroll.Visible=false;show.Text="Hide JSON"end;setStatus(msg)end end)end)
local function disconnectTest()for i,c in ipairs(state.testConnections)do pcall(function()c:Disconnect()end);state.testConnections[i]=nil end;state.boundRemotes={}end
local function beginTest()
 if state.testRunning then setStatus("Test already running");return end
 state.runId=state.runId+1;state.startedAt=NOW();state.endedAt=nil;state.initial=snapshot();state.lastSnapshot=state.initial;state.initialRoster=roster();state.final=nil;state.finalRoster=nil
 state.events={};state.writes={};state.trials={};state.trialStages={};state.restoreResults=nil;state.droppedEvents=0;state.droppedWrites=0;state.droppedTrials=0;state.droppedRemoteEvents=0;state.payloadTruncations=0;state.eventBytes=0;state.sequence=0;state.remoteCount=0;state.remoteLimitReached=false;state.nextHeartbeat=NOW()+5000
 state.testRunning=true;testEvent("test_started",{runId=state.runId,at=state.startedAt});connectKnownRemotes();setStatus("Recording. Have your friend join/leave and play normally, then Stop test.")
end
local function endTest()
 if not state.testRunning then setStatus("No test is running");return end
 state.final=snapshot();state.finalRoster=roster();state.endedAt=NOW();testEvent("test_stopped",{runId=state.runId,at=state.endedAt});state.testRunning=false;disconnectTest();state.restoreResults=restoreAll();local _,msg=export();setStatus("Test stopped. "..(msg or "Export retained for copying."))
end
startTest.MouseButton1Click:Connect(function()callback(beginTest)end);stopTestButton.MouseButton1Click:Connect(function()callback(endTest)end)
restore.MouseButton1Click:Connect(function()callback(function()restoreAll();setStatus("Restore results recorded; changed/replaced fields were left untouched.")end)end)
save.MouseButton1Click:Connect(function()callback(function()local p,msg=export();setStatus(p and msg or "Export failed; copy the selectable JSON from the recorder state.")end)end)
local function disconnectAll()for i,c in ipairs(state.connections)do pcall(function()c:Disconnect()end);state.connections[i]=nil end end
local function stop(reason)
 if not state.running then return end
 state.running=false;state.stopReason=reason or "closed";if state.testRunning then endTest()end;state.restoreResults=restoreAll();disconnectAll();local _,msg=export();if state.ui then pcall(function()state.ui:Destroy()end);state.ui=nil end;env.SlashModifierRecorderV2Last=state;if env[KEY]==state then env[KEY]=nil end;state.focus=nil;setStatus(msg or "Stopped")
end
close.MouseButton1Click:Connect(function()callback(function()stop("closed by user")end)end)
state.focus=function()if gui and gui.Parent then gui.Enabled=true;frame.Visible=true;toggle.Text="Hide modifier panel"end end
state.initial=snapshot()
local char=player.CharacterAdded:Connect(function()callback(function()testEvent("character_replaced",{});if state.running then restoreAll();state.trialStages={};state.lastSnapshot=snapshot();if state.testRunning then testEvent("character_snapshot",state.lastSnapshot)end;setStatus("Character changed; comparison cleared and restore attempted.")end end)end);state.connections[#state.connections+1]=char
task.spawn(function()
 local previous=state.lastSnapshot
 local ok,err=pcall(function()
  while state.running and NOW()-state.startedAt<900000 do
   local current=snapshot()
   for name,w in pairs(state.lastWrites)do
    local nowField=fieldFor(name);local value=readField(w.field)
    if not fieldSame(w.field,nowField) or not same(value,w.requested) then
     logEvent("write_overwritten",{name=name,requested=w.requested,current=value,reason=fieldSame(w.field,nowField) and "value changed" or "instance replaced"});state.lastWrites[name]=nil
    end
   end
   for name,row in pairs(rows)do local f=fieldFor(name);local v=readField(f);row.current.Text="current: "..numberText(v);local w=state.lastWrites[name];row.original.Text="original: "..numberText(w and w.original or f and f.original)end
   if state.testRunning and state.lastRunId~=state.runId then previous=state.initial;state.lastRunId=state.runId end
   if previous and state.testRunning then for _,n in ipairs(statNames)do local d=diff(previous.stats[n],current.stats[n]);if d~=nil and d~=0 then testEvent("stat_change",{name=n,before=numberText(previous.stats[n]),after=numberText(current.stats[n]),delta=numberText(d),precision="binary64-observed",precisionLimited=math.abs(previous.stats[n])>9007199254740992 or math.abs(current.stats[n])>9007199254740992})end end end
   if previous and state.testRunning and not same(previous.factors.FriendPowerPercent,current.factors.FriendPowerPercent) then testEvent("friend_boost_transition",{before=numberText(previous.factors.FriendPowerPercent),after=numberText(current.factors.FriendPowerPercent),authority="unknown"})end
   if previous and state.testRunning then
    for name,v in pairs(current.factors)do if name~="FriendPowerPercent" and not same(v,previous.factors[name])then testEvent("modifier_transition",{name=name,before=previous.factors[name],after=v,authority="unknown"})end end
    for name,rows in pairs(current.inventory)do local ok,a=pcall(function()return Http:JSONEncode(rows)end);local ok2,b=pcall(function()return Http:JSONEncode(previous.inventory[name])end);if ok and ok2 and a~=b then testEvent("inventory_transition",{folder=name,observation=rows})end end
    if NOW()>=(state.nextHeartbeat or 0)then testEvent("heartbeat",{stats=current.stats,friendPower=current.factors.FriendPowerPercent,eventCount=#state.events,incomingRoutes=state.remoteCount});state.nextHeartbeat=NOW()+5000 end
   end
   previous=current;state.lastSnapshot=current;task.wait(.25)
  end
 end)
 if not ok then logEvent("error",{message=tostring(err)});setStatus("Recorder error: "..tostring(err));stop("runtime error") elseif state.running then stop("15 minute limit") end
end)
print("Slash Modifier Recorder v3 idle. Press Start test to capture client-visible transitions.")
