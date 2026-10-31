-- Slash Friend Boost Observer 2.0.0. Client observations, never a server grant.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local HTTP=game:GetService("HttpService")
local player=assert(Players.LocalPlayer,"Join the game before launching")
local env=type(getgenv)=="function" and getgenv() or _G
local KEY="SlashFriendBoostProbe"
local HOOK="SlashFriendBoostNamecallObserver2"
local prior=env[KEY]
if type(prior)=="table" and prior.running then if prior.focus then prior.focus() end;return end
if type(env.SlashModifierRecorderV2)=="table" and env.SlashModifierRecorderV2.running then
 warn("Close the modifier recorder with × before starting this observer");return
end
local LIMIT={events=12000,bytes=4000000,queue=512,routes=200,segments=256,inventory=200}
local S={version="2.0.0",running=true,active=false,generation=0,runId=0,events={},connections={}}
env[KEY]=S
local status,frame,jsonBox
local function now() return DateTime.now().UnixTimestampMillis end
local function finite(v) return type(v)=="number" and v==v and math.abs(v)~=math.huge end
local function number(v) return finite(v) and string.format("%.17g",v) or tostring(v) end
local function safe(v,n) return tostring(v or ""):sub(1,n or 160) end
local function tell(v) if status then status.Text=safe(v,600) end end
local function trunc() S.truncated=(S.truncated or 0)+1 end
local function clean(v,depth,budget,seen)
 depth=depth or 0;budget=budget or {n=128};seen=seen or {}
 budget.n=budget.n-1
 if budget.n<0 or depth>4 then trunc();return "(truncated)" end
 if v==nil or type(v)=="boolean" or finite(v) then return v end
 if type(v)=="string" then if #v>160 then trunc() end;return v:sub(1,160) end
 local kind=typeof(v)
 if kind=="Vector3" then return {type="Vector3",x=number(v.X),y=number(v.Y),z=number(v.Z)} end
 if kind=="Instance" then return {instance=safe(v:GetFullName(),220),class=safe(v.ClassName,60)} end
 if type(v)=="table" then
  if seen[v] then return "(cycle)" end;seen[v]=true
  local out={};local count=0
  for k,x in pairs(v) do
   count=count+1;if count>32 then trunc();out._truncated=true;break end
   local key=safe(k,64);local lower=key:lower()
   if lower:find("token",1,true) or lower:find("cookie",1,true) or lower:find("password",1,true) or lower:find("secret",1,true) or lower:find("pairingkey",1,true) then
    out[key]="(redacted)"
   else out[key]=clean(x,depth+1,budget,seen) end
  end
  return out
 end
 return safe(v,160)
end
-- Timestamp and sequence are assigned before asynchronous serialization.
local function enqueue(kind,data,at)
 if not S.active then return end
 S.seq=S.seq+1
 if #S.pending>=LIMIT.queue then S.queueDropped=S.queueDropped+1;return end
 local stamp=at or now()
 S.pending[#S.pending+1]={sequence=S.seq,observedAt=stamp,elapsedMs=stamp-S.startedAt,kind=kind,data=data}
end
local function drain()
 local queue=S.pending;S.pending={}
 for _,row in ipairs(queue) do
  local ok,j=pcall(function() return HTTP:JSONEncode(row) end)
  if ok and #S.events<LIMIT.events and S.eventBytes+#j<=LIMIT.bytes then
   S.events[#S.events+1]=row;S.eventBytes=S.eventBytes+#j
  else
   S.dropped=S.dropped+1;if not ok then S.serializationErrors=S.serializationErrors+1 end
  end
 end
end
local STATS={"Power","Wins","Rebirths","Crystals"}
local ATTRS={"FriendPowerPercent","PremiumPowerActive","CurrentWorld","EquippedSword","AuraMultiplier","PetMultiplier","SwordPowerMultiplier","SwordWinsMultiplier","SwordAttackSpeedMultiplier","PowerMultiplier","WinsMultiplier","AdminPowerMultiplier","AdminWinsMultiplier","AutoWin"}
local function statObject(name)
 for _,folder in ipairs({"NumericStats","PlayerStats"}) do
  local root=player:FindFirstChild(folder);local x=root and root:FindFirstChild(name)
  if x and x:IsA("ValueBase") and finite(x.Value) then return x end
 end
end
local function scalar(v) if finite(v) or type(v)=="boolean" then return v end;if v~=nil then return safe(v) end end
local function fingerprint(folderName,onlyEquipped)
 local folder=player:FindFirstChild(folderName);if not folder then return "(missing)" end
 local list={};local children=folder:GetChildren()
 for i,x in ipairs(children) do
  if i>LIMIT.inventory then trunc();break end
  if not onlyEquipped or x:GetAttribute("Equipped")==true then
   list[#list+1]=safe(x.Name,80).."="..(x:IsA("ValueBase") and safe(x.Value,80) or "")..":"..safe(x:GetAttribute("Multiplier"),80)..":"..safe(x:GetAttribute("MergeLevel"),30)
  end
 end
 table.sort(list);local joined=table.concat(list,";");if #joined>20000 then trunc() end;return joined:sub(1,20000)
end
local function roster(exclude)
 local list={}
 for i,p in ipairs(Players:GetPlayers()) do
  if i>200 then trunc();break end
  if p~=exclude then list[#list+1]={userId=p.UserId,name=safe(p.Name,80)} end
 end
 table.sort(list,function(a,b)return a.userId<b.userId end)
 return list
end
local function rosterKey(list) local ids={};for _,p in ipairs(list) do ids[#ids+1]=tostring(p.userId) end;return table.concat(ids,",") end
local function snapshot()
 local out={at=now(),stats={},raw={},context={},missingStats={}}
 for _,name in ipairs(STATS) do
  local x=statObject(name);local v=x and x.Value
  if finite(v) then
   out.stats[name]=v;out.raw[name]={value=number(v),precision="binary64",precisionLimited=math.abs(v)>9007199254740991,path=safe(x:GetFullName(),220)}
  else out.missingStats[#out.missingStats+1]=name end
 end
 for _,name in ipairs(ATTRS) do out.context[name]=scalar(player:GetAttribute(name)) end
 local ps=player:FindFirstChild("PlayerStats")
 for _,name in ipairs({"AFKPad","AutoRebirth","EquippedAura"}) do local x=ps and ps:FindFirstChild(name);if x and x:IsA("ValueBase") then out.context[name]=scalar(x.Value) end end
 out.context.EquippedCharms=fingerprint("EquippedCharms",false)
 out.context.EquippedPets=fingerprint("PetInventory",true)
 out.context.characterEpoch=S.characterEpoch
 out.context.roster=S.rosterKey
 return out
end
local function same(a,b)
 for k,v in pairs(a) do if b[k]~=v then return false end end
 for k,v in pairs(b) do if a[k]~=v then return false end end
 return true
end
local function newSegment(snap,reason)
 if S.segment then S.segment.endedAt=snap.at end
 if #S.segments>=LIMIT.segments then S.segment=nil;S.segmentDropped=S.segmentDropped+1;return end
 local seg={index=#S.segments+1,startedAt=snap.at,reason=reason,context=snap.context,positive={},negative={},resets={},changes={},precisionLimited={}}
 S.segments[#S.segments+1]=seg;S.segment=seg
end
local function sample(reason)
 local cur=snapshot();local prev=S.previous
 if not prev then S.previous=cur;newSegment(cur,"start");return cur end
 local changed=not same(prev.context,cur.context)
 if changed then
  enqueue("context_change",{reason=reason,before=prev.context,after=cur.context})
  if prev.context.FriendPowerPercent~=cur.context.FriendPowerPercent then
   enqueue("friend_boost_transition",{before=prev.context.FriendPowerPercent,after=cur.context.FriendPowerPercent,roster=S.roster})
  end
  newSegment(cur,reason)
 end
 for _,name in ipairs(STATS) do
  local a,b=prev.stats[name],cur.stats[name]
  if finite(a) and finite(b) and a~=b then
   local d=b-a;local limited=(cur.raw[name] and cur.raw[name].precisionLimited) or (prev.raw[name] and prev.raw[name].precisionLimited)
   enqueue("stat_change",{name=name,before=number(a),after=number(b),delta=number(d),precisionLimited=limited,source=reason,contextBoundary=changed})
   local total=S.totals[name] or {positive=0,negative=0,changes=0,resets=0};S.totals[name]=total
   total.changes=total.changes+1;total.precisionLimited=limited or total.precisionLimited
   if d>0 then total.positive=total.positive+d else total.negative=total.negative+d;total.resets=total.resets+1 end
   -- A delta crossing an observed context change belongs to neither comparison segment.
   local seg=S.segment
   if changed then S.boundaryDeltas=S.boundaryDeltas+1
   elseif seg then
    seg.changes[name]=(seg.changes[name] or 0)+1;seg.precisionLimited[name]=limited
    if d>0 then seg.positive[name]=(seg.positive[name] or 0)+d
    else seg.negative[name]=(seg.negative[name] or 0)+d;seg.resets[name]=(seg.resets[name] or 0)+1 end
   end
  elseif a~=b then enqueue("stat_availability",{name=name,before=prev.raw[name],after=cur.raw[name]}) end
 end
 S.previous=cur;return cur
end
local PAYLOAD={PunchRequest=true,PunchPowerFeedback=true,Effects=true,SlashSoundRequest=true,AFKExitRequest=true,AutoWinRequest=true,SettingsPreferenceRequest=true,RebirthRequest=true,MovementSpeedRequest=true}
local function routePolicy(r)
 if not r or typeof(r)~="Instance" or not (r:IsA("RemoteEvent") or r:IsA("RemoteFunction")) or not r:IsDescendantOf(RS) then return nil end
 local parent=r.Parent
 local payload=parent and parent.Name=="PunchEscapeRemotes" and parent.Parent==RS and PAYLOAD[r.Name]==true
 return {path=safe(r:GetFullName(),220),class=r.ClassName,payloadPolicy=payload and "gameplay_arguments" or "metadata_only"}
end
local function argsData(args,payload)
 local data={argumentCount=args.n}
 if payload then
  local limited={n=args.n};for i=1,math.min(args.n,24) do limited[i]=args[i] end
  if args.n>24 then trunc();limited._truncated=true end
  data.arguments=clean(limited)
 end
 return data
end
local function captureOutgoing(r,method,args)
 local info=routePolicy(r);if not info then return end
 local data=argsData(args,info.payloadPolicy=="gameplay_arguments")
 data.route=info.path;data.class=info.class;data.method=method;data.payloadPolicy=info.payloadPolicy
 S.outgoingObserved=S.outgoingObserved+1;enqueue("outgoing_request",data)
end
local function hook()
 local shared=env[HOOK]
 if type(shared)=="table" and shared.installed then
  shared.dispatch=captureOutgoing;shared.owner=S;S.outgoingCapability="installed_reused";return
 end
 if type(hookmetamethod)~="function" or type(getnamecallmethod)~="function" then S.outgoingCapability="unsupported_executor";return end
 shared={installed=false,dispatch=captureOutgoing,owner=S};local old
 local getMethod=getnamecallmethod
 local callback=function(self,...)
  local ok,method=pcall(getMethod)
  if ok and shared.dispatch and (method=="FireServer" or method=="InvokeServer") then
   -- Observation failures must not suppress, repeat or change the original call.
   local captured=pcall(shared.dispatch,self,method,table.pack(...))
   if not captured and shared.owner then shared.owner.hookErrors=(shared.owner.hookErrors or 0)+1 end
  end
  return old(self,...)
 end
 if type(newcclosure)=="function" then local ok,c=pcall(newcclosure,callback);if ok and type(c)=="function" then callback=c end end
 local ok,result=pcall(function()return hookmetamethod(game,"__namecall",callback)end)
 if ok and type(result)=="function" then
  old=result;shared.installed=true;env[HOOK]=shared;S.outgoingCapability="installed"
 else
  shared.dispatch=nil;shared.owner=nil;S.outgoingCapability="install_error";S.hookInstallError=safe(result)
 end
end
local function track(conn) S.connections[#S.connections+1]=conn end
local function addRoute(r)
 local info=routePolicy(r);if not info or S.routeObjects[r] then return end
 if #S.routes>=LIMIT.routes then S.routeLimitReached=true;return end
 S.routeObjects[r]=true;S.routes[#S.routes+1]=info
 info.incomingStatus=r:IsA("RemoteFunction") and "not_observed_remote_function_callback" or "pending"
 if r:IsA("RemoteEvent") then
  local generation=S.generation
  local ok,c=pcall(function()return r.OnClientEvent:Connect(function(...)
   if not S.active or S.generation~=generation then return end
   local data=argsData(table.pack(...),info.payloadPolicy=="gameplay_arguments")
   data.route=info.path;data.payloadPolicy=info.payloadPolicy
   S.incomingObserved=S.incomingObserved+1;enqueue("incoming_event",data)
  end)end)
  if ok and c then info.incomingStatus="subscribed";track(c) else info.incomingStatus="subscription_error";info.error=safe(c) end
 end
 enqueue("route_inventory",info)
end
local function scanRoutes()
 local root=RS:FindFirstChild("PunchEscapeRemotes")
 if root then for _,name in ipairs({"PunchPowerFeedback","Effects","PunchRequest","SlashSoundRequest","AFKExitRequest","SettingsPreferenceRequest","RebirthRequest"}) do addRoute(root:FindFirstChild(name)) end end
 for _,r in ipairs(RS:GetDescendants()) do addRoute(r) end
 track(RS.DescendantAdded:Connect(function(r)if S.active then addRoute(r) end end))
end
local function bindStats()
 for _,name in ipairs(STATS) do
  local x=statObject(name)
  if x and not S.boundStats[x] and S.statBindings<128 then
   S.boundStats[x]=true;S.statBindings=S.statBindings+1;local generation=S.generation
   track(x.Changed:Connect(function()if S.active and S.generation==generation then sample("stat_signal:"..name) end end))
  elseif x and not S.boundStats[x] then S.statListenerLimitReached=true
  end
 end
 local ps=player:FindFirstChild("PlayerStats")
 for _,name in ipairs({"AFKPad","AutoRebirth","EquippedAura"}) do
  local x=ps and ps:FindFirstChild(name)
  if x and x:IsA("ValueBase") and not S.boundStats[x] and S.statBindings<128 then
   S.boundStats[x]=true;S.statBindings=S.statBindings+1;local generation=S.generation
   track(x.Changed:Connect(function()if S.active and S.generation==generation then sample("setting_signal:"..name) end end))
  elseif x and not S.boundStats[x] then S.statListenerLimitReached=true end
 end
end
local function disconnect()
 for _,c in ipairs(S.connections) do pcall(function()c:Disconnect()end) end;S.connections={}
 local shared=env[HOOK];if type(shared)=="table" and shared.owner==S then shared.dispatch=nil;shared.owner=nil end
end
local function summary()
 for _,seg in ipairs(S.segments) do
  local seconds=((seg.endedAt or S.endedAt or now())-seg.startedAt)/1000
  seg.elapsedSeconds=seconds;seg.positiveRates={}
  if seconds>0 then for name,gain in pairs(seg.positive) do seg.positiveRates[name]=gain/seconds end end
 end
end
local function export()
 if not S.startedAt then tell("Press Start first.");return end
 if S.active then tell("Press Stop to finish and export this recording.");return end
 summary()
 local report={schemaVersion=2,version=S.version,runId=S.runId,startedAt=S.startedAt,endedAt=S.endedAt,placeId=game.PlaceId,jobId=game.JobId,
  initial=S.initial,final=S.final,initialRoster=S.initialRoster,finalRoster=S.roster,events=S.events,segments=S.segments,totals=S.totals,
  coverage={outgoingCapability=S.outgoingCapability,outgoingObserved=S.outgoingObserved,incomingObserved=S.incomingObserved,hookErrors=S.hookErrors,hookInstallError=S.hookInstallError,routes=S.routes,routeLimitReached=S.routeLimitReached,statListenerLimitReached=S.statListenerLimitReached,statListeners="Changed signals with 250ms replacement/context polling"},
  retention={eventBytes=S.eventBytes,droppedEvents=S.dropped,queueDropped=S.queueDropped,serializationErrors=S.serializationErrors,payloadTruncations=S.truncated,segmentsDropped=S.segmentDropped,boundaryDeltasExcludedFromSegments=S.boundaryDeltas,limits=LIMIT},
  conclusion="OBSERVATIONS_ONLY_NO_SPOOF_ESTABLISHED",
  limitations={"Client-visible observations only; private server code, friendship checks and calculations are unavailable.","An installed namecall observer is not proof of complete coverage: direct function calls, replaced hooks, other runtimes and calls outside the recording can be missed.","Incoming RemoteFunction callbacks and returned InvokeServer results are not intercepted. RemoteEvent subscription is distinct from message delivery.","Known gameplay routes retain bounded arguments; other ReplicatedStorage routes retain metadata only. Values may be truncated and credentials redacted.","No fields are edited or requests fired/replayed. Client callbacks and stats are observations, not authenticated proof of server awards or persistence.","Segments split on observed roster/boost/loadout/training changes; boundary deltas are excluded. Polling can miss brief changes. Rates are descriptive, not causal proof.","Large counters use binary64 precision; rounding, resets, batching, unobserved inputs and simultaneous events can confound comparisons."}}
 local ok,j=pcall(function()return HTTP:JSONEncode(report)end)
 if not ok then tell("Report encoding failed. Recording remains in memory: "..safe(j));return end
 S.report=report;S.json=j;jsonBox.Text=j
 local name="Slash-Friend-Boost-Observer-"..tostring(S.startedAt).."-run"..S.runId..".json"
 local wrote=type(writefile)=="function" and pcall(writefile,name,j) or false
 local verified=false
 if wrote and type(readfile)=="function" then local readOK,bytes=pcall(readfile,name);verified=readOK and bytes==j end
 local copied=type(setclipboard)=="function" and pcall(setclipboard,j) or false
 S.export={name=name,written=wrote,verified=verified,clipboard=copied}
 tell((verified and "Saved and verified: "..name or wrote and "Written; readback not verified: "..name or copied and "File unavailable. JSON copied to clipboard." or "File/clipboard unavailable. Use Show JSON to copy.").." Outgoing: "..tostring(S.outgoingCapability).." ("..S.outgoingObserved.." observed).")
end
local function stop(reason)
 if not S.active then return end
 S.final=sample("final");S.endedAt=now();if S.segment then S.segment.endedAt=S.endedAt end
 enqueue("stop",{reason=reason or "manual"});drain();S.active=false;disconnect();export()
end
local function start()
 if S.active then tell("Recording already running.");return end
 S.generation=S.generation+1;S.runId=S.runId+1;S.startedAt=now();S.endedAt=nil;S.final=nil;S.report=nil;S.json=nil;S.export=nil
 S.events={};S.pending={};S.routes={};S.routeObjects={};S.boundStats={};S.segments={};S.segment=nil;S.previous=nil;S.totals={};S.connections={}
 S.seq=0;S.eventBytes=0;S.dropped=0;S.queueDropped=0;S.serializationErrors=0;S.truncated=0;S.segmentDropped=0;S.boundaryDeltas=0
 S.incomingObserved=0;S.outgoingObserved=0;S.hookErrors=0;S.hookInstallError=nil;S.routeLimitReached=false
 S.characterEpoch=0;S.statBindings=0;S.statListenerLimitReached=false
 S.roster=roster();S.rosterKey=rosterKey(S.roster);S.initialRoster=S.roster;S.active=true;jsonBox.Text="";jsonBox.Visible=false
 S.initial=sample("start");enqueue("start",{initial=S.initial,roster=S.roster})
 hook();scanRoutes();bindStats()
 local generation=S.generation
 for _,name in ipairs(ATTRS) do track(player:GetAttributeChangedSignal(name):Connect(function()if S.active and S.generation==generation then sample("attribute:"..name) end end)) end
 track(Players.PlayerAdded:Connect(function(p)
  if not S.active then return end;S.roster=roster();S.rosterKey=rosterKey(S.roster)
  enqueue("player_added",{userId=p.UserId,name=safe(p.Name,80),relationship="unknown"});sample("player_added")
 end))
 track(Players.PlayerRemoving:Connect(function(p)
  if not S.active then return end;S.roster=roster(p);S.rosterKey=rosterKey(S.roster)
  enqueue("player_removing",{userId=p.UserId,name=safe(p.Name,80),relationship="unknown"});sample("player_removing")
 end))
 track(player.CharacterAdded:Connect(function()if S.active then S.characterEpoch=S.characterEpoch+1;enqueue("character_changed",{});sample("character_changed") end end))
 tell("Recording. Train normally; have the friend join AND leave, then Stop. Outgoing: "..S.outgoingCapability)
 task.spawn(function()
  local heartbeat=now()
  while S.active and S.generation==generation do
   task.wait(.25)
   if not S.active or S.generation~=generation then return end
   local ok,e=pcall(function()
    bindStats();local current=sample("poll")
    if now()-heartbeat>=2000 then heartbeat=now();enqueue("heartbeat",{stats=current.raw,context=current.context,outgoingObserved=S.outgoingObserved,incomingObserved=S.incomingObserved}) end
    drain()
   end)
   if not ok then enqueue("observer_error",{message=safe(e)});stop("observer_error");return end
  end
 end)
end
local gui=Instance.new("ScreenGui");gui.Name="SlashFriendBoostProbe";gui.ResetOnSpawn=false;gui.Parent=player:WaitForChild("PlayerGui")
frame=Instance.new("Frame");frame.Name="Panel";frame.Size=UDim2.fromOffset(560,310);frame.Position=UDim2.new(.5,-280,.5,-155);frame.Parent=gui
local function control(class,name,label,x,y,w,h)
 local c=Instance.new(class);c.Name=name;c.Text=label;c.Position=UDim2.fromOffset(x,y);c.Size=UDim2.fromOffset(w,h);c.Parent=frame;return c
end
control("TextLabel","Title","FRIEND BOOST OBSERVER 2 — START / STOP",10,5,500,30)
status=control("TextLabel","Status","Idle. Observes requests and gains. Does not edit the boost or access private server code.",10,40,540,75);status.TextWrapped=true
local a=control("TextButton","StartTest","Start",10,120,100,32)
local b=control("TextButton","StopTest","Stop + save",120,120,120,32)
local show=control("TextButton","ShowJSON","Show JSON",250,120,120,32)
jsonBox=control("TextBox","ExportJSON","",10,165,540,135);jsonBox.Visible=false;jsonBox.MultiLine=true;jsonBox.ClearTextOnFocus=false;jsonBox.TextEditable=false
local function guarded(fn)
 return function()
  local ok,e=pcall(fn)
  if not ok then
   tell("Observer error: "..safe(e))
   if S.active then local stopped=pcall(stop,"control_error");if not stopped then S.active=false;disconnect() end end
  end
 end
end
a.MouseButton1Click:Connect(guarded(start));b.MouseButton1Click:Connect(guarded(function()stop("manual")end))
show.MouseButton1Click:Connect(guarded(function()if S.active then tell("Stop before exporting.");return end;if not S.json then export() end;jsonBox.Visible=not jsonBox.Visible end))
local toggle=Instance.new("TextButton");toggle.Name="Toggle";toggle.Text="Hide/show observer";toggle.Size=UDim2.fromOffset(170,28);toggle.Position=UDim2.fromOffset(10,42);toggle.Parent=gui
toggle.MouseButton1Click:Connect(function()frame.Visible=not frame.Visible end)
local close=control("TextButton","Close","×",520,5,30,28)
close.MouseButton1Click:Connect(guarded(function()stop("closed");disconnect();S.running=false;env.SlashFriendBoostProbeLast=S;env[KEY]=nil;gui:Destroy()end))
S.focus=function()frame.Visible=true end
print("Friend Boost Observer 2 loaded. Start/Stop; no edits or replay. Live coverage is reported, not assumed.")
