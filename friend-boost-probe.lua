-- Friend boost probe 1.0: controlled local-field experiment, not a server grant.
local Players=game:GetService("Players")
local Http=game:GetService("HttpService")
local RS=game:GetService("ReplicatedStorage")
local player=assert(Players.LocalPlayer,"Join the game before launching")
local env=type(getgenv)=="function"and getgenv()or _G
local KEY="SlashFriendBoostProbe"
if env[KEY]and env[KEY].running then env[KEY].focus();return end
if env.SlashModifierRecorderV2 and env.SlashModifierRecorderV2.running then warn("Close the modifier recorder with × before starting this probe");return end
local S={running=true,active=false,runId=0,events={},phases={},invalidations={}}
env[KEY]=S
local function now()return DateTime.now().UnixTimestampMillis end
local function finite(v)return type(v)=="number"and v==v and math.abs(v)~=math.huge end
local function text(v)return finite(v)and string.format("%.17g",v)or tostring(v)end
local function field()
 if finite(player:GetAttribute("FriendPowerPercent"))then return {object=player,attribute=true}end
 local ps=player:FindFirstChild("PlayerStats");local v=ps and ps:FindFirstChild("FriendPowerPercent")
 if v and(v:IsA("NumberValue")or v:IsA("IntValue"))and finite(v.Value)then return {object=v}end
end
local function read(f)if not f then return nil end;if f.attribute then return f.object:GetAttribute("FriendPowerPercent")end;return f.object.Value end
local function same(a,b)return a and b and a.object==b.object and a.attribute==b.attribute end
local function write(f,v)if f.attribute then f.object:SetAttribute("FriendPowerPercent",v)else f.object.Value=v end end
local function snapshot()
 local ns=player:FindFirstChild("NumericStats");local stats,raw={},{}
 for _,name in ipairs({"Power","Wins","Rebirths"})do local v=ns and ns:FindFirstChild(name);if v and finite(v.Value)then stats[name]=v.Value;raw[name]={value=text(v.Value),precision="binary64",limited=math.abs(v.Value)>9007199254740991}end end
 local attrs=player:GetAttributes();local context={};for _,name in ipairs({"CurrentWorld","EquippedSword","AuraMultiplier","PetMultiplier","SwordPowerMultiplier","SwordWinsMultiplier","PowerMultiplier","WinsMultiplier"})do local v=attrs[name];if type(v)=="string"or type(v)=="boolean"or finite(v)then context[name]=v end end
 local ps=player:FindFirstChild("PlayerStats");local aura=ps and ps:FindFirstChild("EquippedAura");if aura then context.EquippedAura=aura.Value end
 for _,name in ipairs({"AutoRebirth","AFKPad"})do local item=ps and ps:FindFirstChild(name);if item then context[name]=item.Value end end
 local charmFolder=player:FindFirstChild("EquippedCharms");if charmFolder then local equipped={};for _,slot in ipairs(charmFolder:GetChildren())do if slot:IsA("ValueBase")then equipped[#equipped+1]=slot.Name.."="..tostring(slot.Value)end end;table.sort(equipped);context.charms=table.concat(equipped,";")end
 return {at=now(),stats=stats,raw=raw,boost=read(field()),context=context}
end
local function equivalent(a,b)for k,v in pairs(a)do if b[k]~=v then return false end end;for k,v in pairs(b)do if a[k]~=v then return false end end;return true end
local function record(kind,data)
 S.seq=(S.seq or 0)+1;local row={sequence=S.seq,at=now(),elapsedMs=now()-(S.startedAt or now()),phase=S.phase,kind=kind,data=data}
 local ok,j=pcall(function()return Http:JSONEncode(row)end)
 if ok and #S.events<3000 and(S.bytes or 0)+#j<=2000000 then S.events[#S.events+1]=row;S.bytes=(S.bytes or 0)+#j else S.dropped=(S.dropped or 0)+1 end
end
local function invalidate(reason)if not S.invalidations[reason]then S.invalidations[reason]=true;record("comparison_invalid",{reason=reason})end end
local function sanitize(v,depth,budget,seen)
 depth=depth or 0;budget=budget or {n=100};seen=seen or {};budget.n=budget.n-1
 if budget.n<0 or depth>3 then S.truncated=(S.truncated or 0)+1;return "(truncated)"end
 if v==nil or type(v)=="boolean"or finite(v)then return v end
 if type(v)=="string"then if #v>120 then S.truncated=(S.truncated or 0)+1 end;return v:sub(1,120)end
 if typeof(v)=="Instance"then return {instance=v:GetFullName():sub(1,160)}end
 if type(v)=="table"then if seen[v]then return "(cycle)"end;seen[v]=true;local out={};local n=0;for k,x in pairs(v)do n=n+1;if n>30 then out._truncated=true;S.truncated=(S.truncated or 0)+1;break end;local key=tostring(k):sub(1,60);local lower=key:lower();if lower:find("token",1,true)or lower:find("cookie",1,true)or lower:find("password",1,true)or lower:find("secret",1,true)then out[key]="(redacted)"else out[key]=sanitize(x,depth+1,budget,seen)end end;return out end
 return tostring(v):sub(1,120)
end
local function restore()
 if not S.owned then return true end
 local owned=S.owned;local f=field()
 if not same(f,owned.field)or read(f)~=owned.observed then S.restore={ok=false,reason="field changed/replaced; not overwritten"};S.owned=nil;return false end
 local ok,e=pcall(write,f,owned.original);S.restore={ok=ok,reason=ok and nil or tostring(e)};if ok then S.owned=nil end;record("restore",S.restore);return ok
end
local frame,status,requested,seconds,jsonBox
local function tell(msg)status.Text=tostring(msg):sub(1,420)end
local function export()
 local report={schemaVersion=1,version="1.0.0",runId=S.runId,startedAt=S.startedAt,endedAt=S.endedAt,placeId=game.PlaceId,jobId=game.JobId,requested=S.requested,windowSeconds=S.seconds,initial=S.initial,final=S.final,phases=S.phases,comparison=S.comparison,verdict=S.verdict,invalidations=S.invalidations,restore=S.restore,events=S.events,eventBytes=S.bytes,droppedEvents=S.dropped,payloadTruncations=S.truncated,limits={events=3000,eventBytes=2000000,remotes=100},limitations={"Local measurements do not prove server-side acceptance or a successful spoof.","Gain ratios are observations under assumed matched gameplay; action counts are not verified.","Only incoming events and visible state are recorded. Private server logic and outgoing requests are not inspected."}}
 local ok,p=pcall(function()return Http:JSONEncode(report)end);if not ok then tell("JSON export failed: "..tostring(p));return end
 S.report=report;S.json=p;jsonBox.Text=p
 local name="Slash-Friend-Boost-Probe-"..tostring(S.startedAt or now()).."-run"..S.runId..".json";S.export={name=name,verified=false}
 local wrote=false;if type(writefile)=="function"then wrote=pcall(writefile,name,p)end
 if wrote and type(readfile)=="function"then local readOK,bytes=pcall(readfile,name);S.export.verified=readOK and bytes==p end
 local copied=false;if type(setclipboard)=="function"then copied=pcall(setclipboard,p)end
 tell((S.verdict or "Stopped")..". "..(S.export.verified and "Saved and verified: "..name or wrote and "Written, readback unverified: "..name or copied and "JSON copied to clipboard"or "Use Show JSON to copy the report"))
end
local function disconnect()for _,c in ipairs(S.connections or {})do pcall(function()c:Disconnect()end)end;S.connections={}end
local function finish(reason)
 if not S.active then return end
 S.final=snapshot();S.endedAt=now();record("stop",{reason=reason});S.active=false;disconnect();if not restore()then invalidate("restore not confirmed")end
 if reason~="complete"or next(S.invalidations)then S.verdict="INCONCLUSIVE"end
 export()
end
local function listen()
 local n=0;for _,remote in ipairs(RS:GetDescendants())do if remote:IsA("RemoteEvent")then if n>=100 then record("route_limit",{limit=100});break end;n=n+1;local source=remote;local ok,c=pcall(function()return source.OnClientEvent:Connect(function(...)if S.active then record("incoming_event",{route=source:GetFullName():sub(1,160),args=sanitize(table.pack(...)),direction="server-to-client-observed"})end end)end);if ok then S.connections[#S.connections+1]=c end end end
 record("routes_subscribed",{count=n,delivery="not yet observed"})
 for _,item in ipairs({{Players.PlayerAdded,"player_added"},{Players.PlayerRemoving,"player_removing"},{player.CharacterAdded,"character_changed"}})do local signal,kind=item[1],item[2];if signal then S.connections[#S.connections+1]=signal:Connect(function(p)if S.active then record(kind,{name=p and p.Name,boost=read(field())});invalidate(kind)end end)end end
end
local function phaseStart(name)
 local p={name=name,start=snapshot(),positive={},negative={},resets={},samples=0};S.phases[name]=p;S.phase=name;S.previous=p.start;S.phaseAt=now();tell(name.." — keep the same normal action running")
end
local function sample()
 local p=S.phases[S.phase];local current=snapshot();local prev=S.previous
 if not equivalent(S.initial.context,current.context)then invalidate("loadout/world changed")end
 local expected=S.phase=="local_test"and S.requested or S.original
 if current.boost~=expected then invalidate("boost changed or requested value did not hold")end
 for name,old in pairs(prev.stats)do local v=current.stats[name];if finite(v)then local d=v-old;if d>0 then p.positive[name]=(p.positive[name]or 0)+d elseif d<0 then p.negative[name]=(p.negative[name]or 0)+d;p.resets[name]=(p.resets[name]or 0)+1 end;if d~=0 then record("stat_change",{name=name,before=text(old),after=text(v),delta=text(d)})end end end
 p.samples=p.samples+1;S.previous=current
end
local function phaseEnd()
 local p=S.phases[S.phase];p.finish=snapshot();p.elapsedMs=p.finish.at-p.start.at;p.rates={}
 for name,amount in pairs(p.positive)do if p.elapsedMs>0 then p.rates[name]=amount/(p.elapsedMs/1000)end end
 record("phase_complete",{name=S.phase,positive=p.positive,negative=p.negative,samples=p.samples,elapsedMs=p.elapsedMs})
end
local function compare()
 S.comparison={tolerance=0.10,metrics={}};S.verdict="INCONCLUSIVE"
 if next(S.invalidations)then return end
 local a,b,c=S.phases.baseline,S.phases.local_test,S.phases.restored;local eligible=0;local difference=false
 for _,name in ipairs({"Power","Wins","Rebirths"})do
  local ar,br,cr=a.rates[name],b.rates[name],c.rates[name]
  if finite(ar)and finite(br)and finite(cr)and ar>0 and cr>0 and not a.resets[name]and not b.resets[name]and not c.resets[name]then
   local limited=false;for _,p in ipairs({a,b,c})do if p.start.raw[name].limited or p.finish.raw[name].limited then limited=true end end
   local stable=math.abs(ar-cr)/math.max(ar,cr)<=0.10
   local ratio=br/((ar+cr)/2);S.comparison.metrics[name]={baselineRate=ar,testRate=br,restoredRate=cr,testRatio=ratio,controlsStable=stable,precisionLimited=limited}
   if stable and not limited then eligible=eligible+1;if math.abs(ratio-1)>0.10 then difference=true end end
  end
 end
 if eligible>0 then S.verdict=difference and "OBSERVED_CHANGE_UNVERIFIED"or "NO_OBSERVABLE_EFFECT_IN_THIS_RUN"end
end
local function start()
 if S.active then tell("Test already running");return end
 local value,window=tonumber(requested.Text),tonumber(seconds.Text);local f=field()
 if not finite(value)or not finite(window)or window<1 or window>60 then tell("Enter a finite boost and window of 1–60 seconds");return end
 if not f then tell("Existing numeric FriendPowerPercent was not found");return end
 if S.owned and not restore()then tell("Prior edit could not be restored; close and review the report");return end
 S.runId=S.runId+1;local ticket=S.runId;S.active=true;S.startedAt=now();S.endedAt=nil;S.requested=value;S.seconds=window;S.original=read(f);S.initial=snapshot();S.final=nil;S.events={};S.phases={};S.invalidations={};S.connections={};S.seq=0;S.bytes=0;S.dropped=0;S.truncated=0;S.restore=nil;S.verdict="INCONCLUSIVE";S.comparison=nil
 listen();phaseStart("baseline")
 task.spawn(function()
  local ok,err=pcall(function()
   for _,phase in ipairs({"baseline","local_test","restored"})do
    if not S.active or S.runId~=ticket then return end
    if phase=="local_test"then
     if not same(f,field())or read(f)~=S.original then invalidate("boost/field changed during baseline");finish("baseline changed");return end
     write(f,value);S.owned={field=f,original=S.original,observed=read(f)};record("local_write",{before=S.original,requested=value,observed=read(f)})
    elseif phase=="restored"then if not restore()then invalidate("restore not confirmed")end end
    if phase~="baseline"then phaseStart(phase)end
    while now()-S.phaseAt<window*1000 do task.wait(.25);if not S.active or S.runId~=ticket then return end;sample()end
    phaseEnd()
   end
   compare();finish("complete")
  end)
  if not ok and S.runId==ticket then invalidate("runtime failure: "..tostring(err));finish("runtime error")end
 end)
end
local gui=Instance.new("ScreenGui");gui.Name="SlashFriendBoostProbe";gui.ResetOnSpawn=false;gui.Parent=player:WaitForChild("PlayerGui");S.ui=gui
frame=Instance.new("Frame");frame.Size=UDim2.fromOffset(540,280);frame.Position=UDim2.new(.5,-270,.5,-140);frame.Visible=true;frame.Parent=gui
local function control(class,name,label,x,y,w,h)local c=Instance.new(class);c.Name=name;c.Text=label;c.Position=UDim2.fromOffset(x,y);c.Size=UDim2.fromOffset(w,h);c.Parent=frame;return c end
control("TextLabel","Title","FRIEND BOOST — NORMAL / EDITED / RESTORED",10,0,480,32)
status=control("TextLabel","Status","Idle. Keep the same normal action running throughout the test.",10,35,520,60);status.TextWrapped=true
control("TextLabel","BoostLabel","Test friend boost",10,100,180,28);requested=control("TextBox","RequestedBoost","100000",210,100,180,28);requested.ClearTextOnFocus=false
control("TextLabel","WindowLabel","Seconds per phase",10,135,180,28);seconds=control("TextBox","WindowSeconds","10",210,135,180,28);seconds.ClearTextOnFocus=false
local a=control("TextButton","StartTest","Start test",10,180,110,30);local b=control("TextButton","StopTest","Stop test",130,180,110,30);local show=control("TextButton","ShowJSON","Show JSON",250,180,110,30)
jsonBox=control("TextBox","ExportJSON","",10,35,520,130);jsonBox.Visible=false;jsonBox.MultiLine=true;jsonBox.ClearTextOnFocus=false;jsonBox.TextEditable=false
local function guarded(fn)return function()local ok,e=pcall(fn);if not ok then tell("Error: "..tostring(e));if S.active then invalidate("control error");finish("control error")end end end end
a.MouseButton1Click:Connect(guarded(start));b.MouseButton1Click:Connect(guarded(function()finish("manual stop")end));show.MouseButton1Click:Connect(guarded(function()jsonBox.Visible=not jsonBox.Visible;if jsonBox.Visible then export()end end))
local toggle=Instance.new("TextButton");toggle.Name="Toggle";toggle.Size=UDim2.fromOffset(160,28);toggle.Position=UDim2.fromOffset(10,45);toggle.Text="Hide/show boost probe";toggle.Parent=gui;toggle.MouseButton1Click:Connect(function()frame.Visible=not frame.Visible end)
local close=control("TextButton","Close","×",500,0,30,28);close.MouseButton1Click:Connect(guarded(function()if S.active then finish("closed")end;restore();disconnect();S.running=false;env.SlashFriendBoostProbeLast=S;env[KEY]=nil;gui:Destroy()end))
S.focus=function()frame.Visible=true end
print("Friend boost probe loaded. Local edits are not proof of server-side reward effects.")
