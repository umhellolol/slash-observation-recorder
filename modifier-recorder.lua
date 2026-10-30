-- Read-only diagnostic. No remote interception, replay, or stat modification.
-- Run again to stop the current recorder. Otherwise records for 10 minutes.
local Players=game:GetService("Players")
local Http=game:GetService("HttpService")
local player=Players.LocalPlayer
assert(player,"Run this from a connected Roblox client")
local env=(getgenv and getgenv()) or _G
local key="SlashModifierRecorder"
if env[key] and env[key].running then env[key].running=false;print("Modifier recorder stopping; export follows.");return end
local state={running=true,events={},startedAt=DateTime.now().UnixTimestampMillis}
env[key]=state
local factors={"FriendPowerPercent","AuraMultiplier","SwordPowerMultiplier","SwordWinsMultiplier","SwordAttackSpeedMultiplier","AdminPowerMultiplier","AdminWinsMultiplier","PetMultiplier","PowerMultiplier","WinsMultiplier","EquippedSword"}
local function scalar(v)
 local kind=typeof(v)
 if kind=="number" then if v~=v or v==math.huge or v==-math.huge then return tostring(v) end;return v end
 if kind=="string" then return string.sub(v,1,160) end
 if kind=="boolean" then return v end
 if v==nil then return nil end
 return tostring(v)
end
local function val(parent,name)
 local item=parent and parent:FindFirstChild(name)
 if item and item:IsA("ValueBase") then return scalar(item.Value) end
end
local function attrs(item)
 local out={}
 for _,name in ipairs({"Multiplier","StrengthFactor","Equipped","Tier","MergeLevel","Owned","Rarity","SwordName","PetName"}) do out[name]=scalar(item:GetAttribute(name)) end
 return out
end
local function folder(name)
 local root=player:FindFirstChild(name)
 if not root then return {available=false} end
 local rows={}
 local children=root:GetChildren()
 table.sort(children,function(a,b)return a.Name<b.Name end)
 for i,item in ipairs(children) do
  if i>200 then break end
  rows[#rows+1]={id=item.Name,value=item:IsA("ValueBase") and scalar(item.Value) or nil,attributes=attrs(item)}
 end
 return {available=true,items=rows,truncated=#children>200}
end
local function snapshot()
 local ps=player:FindFirstChild("PlayerStats")
 local ls=player:FindFirstChild("leaderstats")
 local out={stats={},factors={},inventory={}}
 for _,name in ipairs({"Power","Wins","Rebirths","Crystals"}) do
  local v=val(ls,name);if v==nil then v=val(ps,name) end;if v==nil then v=scalar(player:GetAttribute(name)) end
  out.stats[name]=v
 end
 for _,name in ipairs(factors) do
  local v=scalar(player:GetAttribute(name));if v==nil then v=val(ps,name) end
  out.factors[name]=v
 end
 out.factors.EquippedAura=val(ps,"EquippedAura")
 for _,name in ipairs({"EquippedCharms","OwnedCharms","SwordUnlocks","OwnedAuras","PetInventory"}) do out.inventory[name]=folder(name) end
 return out
end
local function equal(a,b)
 if type(a)~=type(b) then return false end
 if type(a)~="table" then return a==b end
 for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
 for k in pairs(b) do if a[k]==nil then return false end end
 return true
end
local function export()
 local report={schemaVersion=1,startedAt=state.startedAt,endedAt=DateTime.now().UnixTimestampMillis,placeId=tostring(game.PlaceId),jobId=game.JobId,events=state.events,
  limitations={"Client observations only; not proof of server authority or editable effective rewards.","Numeric deltas use the game's floating-point precision.","250ms sampling can combine multiple awards; record action times separately.","No remotes intercepted or fired; no stats changed."}}
 local payload=Http:JSONEncode(report)
 local name="Slash-Modifier-Observations-"..tostring(state.startedAt)..".json"
 state.report=report;state.json=payload
 if type(writefile)=="function" then
  local ok,err=pcall(writefile,name,payload)
  if ok then print("Modifier observations saved: "..name);return end
  warn("File export failed: "..tostring(err))
 end
 print("Modifier observations kept in getgenv().SlashModifierRecorder.json; file export unavailable.")
end
task.spawn(function()
 local previous
 local ok,err=pcall(function()
  while state.running and DateTime.now().UnixTimestampMillis-state.startedAt<600000 and #state.events<1200 do
   local current=snapshot()
   if not equal(previous,current) then
    local delta={}
    if previous then for name,v in pairs(current.stats) do local old=previous.stats[name];if type(v)=="number" and type(old)=="number" and v~=old then delta[name]=v-old end end end
    state.events[#state.events+1]={observedAt=DateTime.now().UnixTimestampMillis,state=current,statDelta=delta}
    previous=current
   end
   task.wait(0.25)
  end
 end)
 state.running=false
 if not ok then state.events[#state.events+1]={error=tostring(err)} end
 local exported,why=pcall(export);if not exported then warn("Modifier export failed: "..tostring(why)) end
end)
print("Read-only modifier recorder started. Re-run to stop/export; automatic stop at 10 minutes or 1200 changes.")
