-- Slash In-Game Test Suite 1.0.0. Source only; captured data is never uploaded.
-- mxssyo is the preferred test account. No second instrumented client is required.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Http = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local PromptService = game:GetService("ProximityPromptService")
assert(RunService:IsClient(), "Run this suite in a Roblox client.")
assert(game.PlaceId == 101558013317432 or RunService:IsStudio(), "This suite is for Slash place 101558013317432.")
local player = assert(Players.LocalPlayer, "Join the game before starting the suite.")
local playerGui = assert(player:WaitForChild("PlayerGui", 10), "PlayerGui is not ready; retry after loading.")
if playerGui:FindFirstChild("SlashInGameTestSuite") then warn("Suite already loaded. Export, stop and close it before reloading."); return end
if playerGui:FindFirstChild("SlashObservationRecorder") then warn("Older recorder is still present. Stop it to avoid duplicate recordings; this suite has its own recorder.") end

local Lab = { version = "1.0.0", running = true, expectedMain = "mxssyo", selectedTestId = nil,
    experiment = "mxssyo-001", notes = "", preserveLanes = true, trials = {}, results = {}, simulation = {},
    message = "Ready. Start with Survey, then choose a test. No gameplay mutations run automatically." }
local writer = type(writefile) == "function" and writefile or nil
local reader = type(readfile) == "function" and readfile or nil
local copier = type(setclipboard) == "function" and setclipboard or (type(toclipboard) == "function" and toclipboard or nil)
local function now() return DateTime.now():ToIsoDate() end
local function serverTime() local ok, v = pcall(function() return workspace:GetServerTimeNow() end); return ok and v or nil end
local session = { id = Http:GenerateGUID(false), account = player.Name, userId = player.UserId, placeId = game.PlaceId,
    placeVersion = game.PlaceVersion, jobId = game.JobId, startedAt = now(), recorderVersion = Lab.version,
    mode = "single-account-test-suite", expectedMain = Lab.expectedMain,
    capabilities = { fileWrite = writer ~= nil, fileRead = reader ~= nil, clipboard = copier ~= nil },
    provenance = "Client observations and tool-originated requests. Synthetic replay is explicitly separate." }
local rows, bytes, seq, evicted, lost, truncations, incoming, filtered = {}, 0, 0, 0, 0, 0, 0, 0
local connections, bindings, coverage, configs, configStatus = {}, {}, {}, {}, {}
local segments, savedSeq, saveError, lastSave = {}, 0, nil, os.clock()
local baseline, cache, lastStateKey, activeTrial, busy = nil, {}, nil, nil, false
local shop, shower, wallState, trade = nil, {}, { clearedStages = {}, segments = {} }, { active = false }
local bladeResult
local swordSignals = {}
local probes, ambientCounts, ambientSamples, prepared = {}, {}, {}, nil
local scanDrops, scanAnchors, instanceIds, nextInstanceId = {}, {}, setmetatable({}, { __mode = "k" }), 0
local record, snapshot, persist
local Model = {}
function Model.dropEligibility(drop, userId, clock)
    if type(drop) ~= "table" then return "UNKNOWN" end
    if drop.targetUserId and drop.targetUserId ~= 0 and drop.targetUserId ~= userId then return "OTHER_ACCOUNT" end
    if type(clock) ~= "number" or type(drop.readyAt) ~= "number" or type(drop.expiresAt) ~= "number" then return "UNKNOWN" end
    if clock < drop.readyAt then return "NOT_READY" end
    if clock >= drop.expiresAt then return "EXPIRED" end
    return "READY_BY_OBSERVED_FIELDS"
end
function Model.showerApply(registry, kind, data)
    if kind == "Spawn" and type(data) == "table" and data.id ~= nil then registry[tostring(data.id)] = data
    elseif kind == "Sync" and type(data) == "table" then
        -- The recovered client accepts Sync entries additively; Remove owns deletion.
        for _, drop in pairs(data) do if type(drop) == "table" and drop.id ~= nil then registry[tostring(drop.id)] = drop end end
    elseif kind == "Remove" and type(data) == "table" and data.id ~= nil then registry[tostring(data.id)] = nil end
    return registry
end
function Model.bladeDecision(owned, remaining, success, message)
    if owned == true then return "OWNED_STOP_ATTEMPTS" end
    if success == false and type(message) == "string" and string.find(string.lower(message), "already been claimed", 1, true) then return "EXHAUSTED_STOP_ATTEMPTS" end
    if success == true then return "VERIFY_OWNERSHIP" end
    if remaining == 0 then return "UNAVAILABLE_UNTIL_REVALIDATED" end
    return "ELIGIBILITY_UNKNOWN"
end
function Model.scopedKey(server, kind, id) return tostring(server) .. ":" .. kind .. ":" .. tostring(id) end
function Model.quantityDelta(before, after)
    if type(before) ~= "number" or type(after) ~= "number" then return nil end
    return after - before
end
function Model.localCoverage(hasVisibleObjects)
    return hasVisibleObjects and "PARTIAL_LOCAL_OBJECTS" or "UNKNOWN_NO_LOCAL_OBJECTS"
end
function Model.wallInit(stage, segment, health, cleared, clock)
    local result = { activeStage = stage, activeSegment = segment, health = health, clearedStages = {}, segments = {}, lastUpdate = clock }
    for _, value in pairs(type(cleared) == "table" and cleared or {}) do result.clearedStages[tostring(value)] = true end
    return result
end

local function safe(value)
    local budget, seen = 12000, {}
    local function visit(v, depth)
        budget = budget - 1
        if budget < 0 or depth > 12 then truncations = truncations + 1; return { omitted = "serialization limit" } end
        local kind = typeof(v)
        if kind == "nil" then return { type = "nil" } end
        if kind == "boolean" then return v end
        if kind == "number" then return (v == v and v ~= math.huge and v ~= -math.huge) and v or tostring(v) end
        if kind == "string" then
            if #v > 12000 then truncations = truncations + 1; return { text = string.sub(v, 1, 12000), truncated = true } end
            return v
        end
        if kind == "Instance" then return { type = v.ClassName, path = v:GetFullName() } end
        if kind == "Vector3" then return { x = v.X, y = v.Y, z = v.Z, type = kind } end
        if kind == "CFrame" then return { type = kind, components = { v:GetComponents() } } end
        if kind ~= "table" then return { type = kind, text = tostring(v) } end
        if seen[v] then return { omitted = "cycle" } end
        seen[v] = true
        local result, count = {}, 0
        for k, x in pairs(v) do
            count = count + 1
            if count > 1200 then result.__truncated = true; truncations = truncations + 1; break end
            result[tostring(k)] = visit(x, depth + 1)
        end
        seen[v] = nil
        return result
    end
    return visit(value, 0)
end
local function path(root, names)
    local item = root
    for _, name in ipairs(names) do item = item and item:FindFirstChild(name); if not item then return nil end end
    return item
end
local function rootPosition()
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    return root and root.Position or nil
end
local function world()
    local attr = player:GetAttribute("CurrentWorld")
    local stat = path(player, { "PlayerStats", "CurrentWorld" })
    return attr ~= nil and attr or (stat and stat.Value or nil)
end
local function countTable(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n end
local function folderValues(name, missing)
    local f = player:FindFirstChild(name)
    if not f then missing[#missing + 1] = "LocalPlayer." .. name; return nil end
    local out = {}
    for i, item in ipairs(f:GetChildren()) do
        if i > 1200 then out.__truncated = true; truncations = truncations + 1; break end
        if item:IsA("ValueBase") then out[item.Name] = item.Value end
    end
    return out
end
local function inventory(name, mode, missing)
    local f = player:FindFirstChild(name)
    if not f then missing[#missing + 1] = "LocalPlayer." .. name; return nil end
    local out = {}
    for i, item in ipairs(f:GetChildren()) do
        if i > 1200 then out.__truncated = true; truncations = truncations + 1; break end
        if mode == "pets" then out[item.Name] = item:GetAttributes()
        elseif mode == "swords" then
            local value = item:IsA("ValueBase") and item.Value or nil
            out[item.Name] = { rarity = value, owned = item:GetAttribute("Owned"), attributes = item:GetAttributes() }
        elseif item:IsA("ValueBase") then out[item.Name] = item.Value end
    end
    return out
end
local function attrs(name, missing)
    local item = RS:FindFirstChild(name)
    if not item then missing[#missing + 1] = "ReplicatedStorage." .. name; return nil end
    return item:GetAttributes()
end
snapshot = function()
    local missing = {}
    local observedShower = {}
    for id, drop in pairs(shower) do
        observedShower[id] = safe(drop)
        observedShower[id].eligibility = Model.dropEligibility(drop, player.UserId, serverTime())
    end
    local state = { world = world(), position = rootPosition(), stats = folderValues("NumericStats", missing),
        playerStats = folderValues("PlayerStats", missing), swords = inventory("SwordUnlocks", "swords", missing),
        charms = inventory("OwnedCharms", "values", missing), equippedCharms = inventory("EquippedCharms", "values", missing),
        pets = inventory("PetInventory", "pets", missing), ownedFists = inventory("OwnedFists", "values", missing),
        blade = attrs("AdminBladeState", missing), dropState = attrs("SwordDropState", missing),
        shop = shop, shower = observedShower, walls = wallState, trade = trade, drops = scanDrops, anchors = scanAnchors, swordSignals = swordSignals,
        coverage = coverage, missing = missing, characterPresent = player.Character ~= nil,
        objectCoverage = Model.localCoverage(countTable(scanDrops) > 0) }
    local observed = {}
    for _, name in ipairs({ "CurrentWorld", "MaxWorldUnlocked", "EquippedSword", "PetInventoryCapacity", "PunchEscapePolicyReady",
        "PunchEscapePaidTradingAllowed", "PunchEscapePaidRandomAllowed", "AdminBladeCutsceneActive", "AutoWin" }) do
        local v = player:GetAttribute(name)
        observed[name] = v == nil and { observed = false } or { observed = true, value = v }
    end
    state.playerAttributes = observed
    local max = player:GetAttribute("MaxWorldUnlocked")
    state.maxWorldUnlocked = max ~= nil and max or (state.playerStats and state.playerStats.MaxWorldUnlocked)
    state.bladeResult = bladeResult
    state.bladeDecision = Model.bladeDecision(nil, state.blade and state.blade.Remaining, bladeResult and bladeResult.success, bladeResult and bladeResult.message)
    state.gameWindows = {}
    local shade = path(playerGui, { "PunchEscapeUI", "Root", "ModalShade" })
    for _, name in ipairs({ "CharmsShopWindow", "TradeWindow", "PetsWindow", "CraftingWindow" }) do
        local window = shade and shade:FindFirstChild(name)
        state.gameWindows[name] = window and { observed = true, visible = window.Visible, parentVisible = shade.Visible } or { observed = false }
    end
    state.boosts = {}
    for _, name in ipairs({ "AdminPowerMultiplier", "AdminWinsMultiplier", "AdminCrystalsMultiplier", "AdminPowerEndsAt", "AdminWinsEndsAt", "AdminCrystalsEndsAt" }) do
        local value = RS:GetAttribute(name)
        state.boosts[name] = value == nil and { observed = false } or { observed = true, value = value }
    end
    local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    if humanoid then state.characterHealth = humanoid.Health; state.actualWalkSpeed = humanoid.WalkSpeed end
    return safe(state)
end
record = function(kind, data)
    if not Lab.running and kind ~= "stopped" and kind ~= "review" then return nil end
    seq = seq + 1
    local row = { seq = seq, kind = kind, utc = now(), monotonic = os.clock(), serverTime = serverTime(),
        experiment = Lab.experiment, trialId = activeTrial and activeTrial.id or nil, testId = activeTrial and activeTrial.testId or nil, data = safe(data) }
    local encoded = Http:JSONEncode(row)
    rows[#rows + 1] = { value = row, bytes = #encoded }; bytes = bytes + #encoded
    while #rows > 10000 or bytes > 4000000 do
        local old = table.remove(rows, 1); bytes = bytes - old.bytes; evicted = evicted + 1
        if old.value.seq > savedSeq then lost = lost + 1 end
    end
    return row
end
persist = function(force)
    if not writer then return false, "No file API; rolling capture only. Copy/export each short trial." end
    if not force and os.clock() - lastSave < 10 then return true end
    local pending = {}
    for _, entry in ipairs(rows) do if entry.value.seq > savedSeq then pending[#pending + 1] = entry.value end end
    if #pending == 0 then return true end
    local n = #segments + 1
    local filename = "slash-suite-" .. session.id .. "-part-" .. tostring(n) .. ".json"
    local json = Http:JSONEncode({ schemaVersion = 1, kind = "slash-recorder", session = session, records = pending,
        part = n, firstSeq = pending[1].seq, lastSeq = pending[#pending].seq, exportedAt = now(), droppedRecords = lost, truncations = truncations })
    local ok, err = pcall(writer, filename, json)
    if ok and reader then
        local readOK, contents = pcall(reader, filename)
        if not readOK or contents ~= json then ok = false; err = "File read-back failed" end
    end
    if not ok then saveError = tostring(err); return false, saveError end
    segments[#segments + 1] = { filename = filename, firstSeq = pending[1].seq, lastSeq = pending[#pending].seq, bytes = #json, readBackVerified = reader ~= nil }
    savedSeq = pending[#pending].seq; lastSave = os.clock(); saveError = nil
    return true
end
local function capture(kind, extra)
    cache = snapshot()
    return record(kind, { state = cache, notes = Lab.notes, details = extra })
end
local function notify(message) Lab.message = tostring(message); return false, Lab.message end
local function loadConfig(name)
    if configs[name] then return configs[name] end
    local item = RS:FindFirstChild(name)
    if not item or not item:IsA("ModuleScript") then configStatus[name] = "not visible"; return nil end
    local ok, value = pcall(require, item)
    if ok and type(value) == "table" then configs[name] = value; configStatus[name] = "client module read"; return value end
    configStatus[name] = "module read failed"; return nil
end
local function surveyConfigs()
    local result = {}
    local config = loadConfig("PunchEscapeConfig")
    if config then
        result.worlds = config.Worlds; result.walls = config.Walls; result.fists = config.Fists; result.training = config.Training; result.stageWins = config.StageWins
        result.punchInterval = config.PunchInterval; result.maximumWallPunchDistance = config.MaximumWallPunchDistance
    end
    local charm = loadConfig("PunchEscapeCharmConfig"); if charm then result.charms = charm.Items; result.restockSeconds = charm.RestockSeconds end
    local lucky = loadConfig("LuckyBlockConfig"); if lucky then result.luckyWinsCosts = lucky.WinsCosts end
    record("source-config-survey", { status = configStatus, values = result, evidenceClass = "runtime client configuration, not server guarantees" })
end
local function surveyGeometry()
    local worlds, total = {}, 0
    local root = workspace:FindFirstChild("Worlds")
    if root then
        for _, area in ipairs(root:GetChildren()) do
            local entry = { name = area.Name, attributes = area:GetAttributes(), anchors = {}, coverage = "Only current client-visible geometry" }
            for _, item in ipairs(area:GetDescendants()) do
                if total >= 2000 then truncations = truncations + 1; entry.truncated = true; break end
                if item:IsA("ProximityPrompt") then
                    total = total + 1
                    entry.anchors[#entry.anchors + 1] = { path = item:GetFullName(), name = item.Name, kind = "prompt", enabled = item.Enabled,
                        holdDuration = item.HoldDuration, maxDistance = item.MaxActivationDistance,
                        parentAttributes = item.Parent and item.Parent:GetAttributes() or {},
                        position = item.Parent and item.Parent:IsA("BasePart") and item.Parent.Position or nil }
                elseif item:IsA("BasePart") and (item.Name == "x1 Win" or item.Name == "WinPart" or string.find(item.Name, "Spawn", 1, true)) then
                    total = total + 1
                    entry.anchors[#entry.anchors + 1] = { path = item:GetFullName(), name = item.Name, kind = "route-anchor", position = item.Position, size = item.Size, attributes = item:GetAttributes() }
                end
            end
            worlds[#worlds + 1] = entry
        end
    end
    record("world-geometry-survey", { worlds = worlds, anchorCount = total, worldRootVisible = root ~= nil, scope = "Streaming limits apply; no path is declared safe from geometry alone." })
end
local function objectId(item)
    if not instanceIds[item] then nextInstanceId = nextInstanceId + 1; instanceIds[item] = session.id .. ":object:" .. tostring(nextInstanceId) end
    return instanceIds[item]
end
local function objectPosition(item)
    if item:IsA("BasePart") then return item.Position end
    if item:IsA("Attachment") then return item.WorldPosition end
    local part = item:FindFirstChildWhichIsA("BasePart", true)
    return part and part.Position or nil
end
local function objectWorld(item)
    local current = item
    for _ = 1, 15 do
        if not current then break end
        local value = current:GetAttribute("World") or current:GetAttribute("WorldId")
        if value ~= nil then return value end
        local name = string.match(current.Name, "^World (%d+)$")
        if name then return tonumber(name) end
        current = current.Parent
    end
    return nil
end
local function scan()
    local drops, anchors = {}, {}
    local function addDrop(item, kind)
        if #drops >= 250 then truncations = truncations + 1; return end
        local prompts = {}
        for _, v in ipairs(item:GetDescendants()) do
            if v:IsA("ProximityPrompt") then
                prompts[#prompts + 1] = { path = v:GetFullName(), name = v.Name, enabled = v.Enabled,
                    holdDuration = v.HoldDuration, maxDistance = v.MaxActivationDistance, position = v.Parent and objectPosition(v.Parent) }
            end
        end
        drops[#drops + 1] = { id = objectId(item), kind = kind, path = item:GetFullName(), world = objectWorld(item),
            position = objectPosition(item), attributes = item:GetAttributes(), prompts = prompts,
            scope = "locally visible objects only; streaming and local visuals affect coverage" }
    end
    for _, item in ipairs(workspace:GetChildren()) do
        if item.Name == "ActiveSwordDrop" then addDrop(item, "sword") end
    end
    local folder = workspace:FindFirstChild("AdminCharmDrops")
    if folder then for _, item in ipairs(folder:GetChildren()) do addDrop(item, "charm") end end
    for _, name in ipairs({ "AdminBladeShrine", "CharmShop", "Charm Shop" }) do
        local item = workspace:FindFirstChild(name)
        if item then anchors[#anchors + 1] = { path = item:GetFullName(), position = objectPosition(item), attributes = item:GetAttributes() } end
    end
    scanDrops, scanAnchors = safe(drops), safe(anchors)
end
local routes = {
    { "PunchEscapeRemotes", "Effects" }, { "PunchEscapeRemotes", "TradeRemote" },
    { "PunchEscapeRemotes", "SwordDropEvent" }, { "PunchEscapeRemotes", "CharmShopRequest" },
    { "PunchEscapeAdminRemotes", "CharmShowerVisuals" }, { "PunchEscapeAdminBladeRemotes", "Event" },
    { "PetInventoryResult" }, { "LuckyBlockOpenResult" }, { "LuckyBlockCinematicResult" },
}
local function probeResponse(name)
    for _, probe in ipairs(probes) do
        if probe.name == name and os.clock() - probe.monotonic <= 8 then
            probe.responses = probe.responses + 1; probe.lastResponseAt = now()
            record("probe-response-window", { probeId = probe.id, name = name, position = rootPosition(),
                note = "Response observed in request window; protocol has no request correlation ID." })
        end
    end
end
local function receive(key, args)
    local name, first = string.match(key, "([^%.]+)$"), args[1]
    if name == "Effects" then
        if first == "PersonalWallsInit" then
            wallState = Model.wallInit(args[2], args[3], args[4], args[5], serverTime())
        elseif first == "PersonalWallsReset" then wallState = { clearedStages = {}, segments = {}, lastUpdate = serverTime() }
        elseif first == "PersonalStageClear" then wallState.clearedStages[tostring(args[2])] = true; wallState.lastUpdate = serverTime()
        elseif first == "PersonalWallBreak" then wallState.segments[tostring(args[2]) .. ":" .. tostring(args[3])] = { broken = true }
        elseif first == "PersonalWallHealth" or first == "PersonalWallActivate" then
            wallState.segments[tostring(args[2]) .. ":" .. tostring(args[3])] = { health = args[4], maxHealth = args[5], kind = first }
        elseif first == "WorldTeleportPrepared" then prepared = { world = args[2], position = args[3], at = os.clock() } end
        if first == "PersonalWallsInit" then probeResponse("wall_sync") end
    elseif name == "SwordDropEvent" then
        if first == "Incoming" or first == "Impact" or first == "Collected" then
            local state = RS:FindFirstChild("SwordDropState")
            swordSignals[#swordSignals + 1] = { kind = first, receivedAt = now(), receivedServerTime = serverTime(),
                observerWorld = world(), singletonWorldHint = state and state:GetAttribute("World"),
                position = first == "Impact" and safe(args[2]) or nil,
                rarity = first == "Impact" and args[3] or args[2], swordName = first == "Impact" and args[4] or nil,
                scope = "Notification plus singleton world hint; not proof of a stable per-drop server identity." }
            if #swordSignals > 20 then table.remove(swordSignals, 1) end
        end
    elseif name == "CharmShopRequest" and type(first) == "table" then
        shop = safe(first); shop.receivedAt = now(); shop.receivedServerTime = serverTime(); shop.observerPosition = safe(rootPosition()); shop.observerWorld = world()
        probeResponse("shop_get")
    elseif name == "CharmShowerVisuals" then
        Model.showerApply(shower, first, safe(args[2]))
        if first == "Sync" then probeResponse("drop_sync") end
    elseif string.find(key, "PunchEscapeAdminBladeRemotes", 1, true) and first == "ClaimResult" then
        bladeResult = { success = args[2], message = args[3], observedAt = now() }
    elseif name == "TradeRemote" then
        if first == "Opened" then trade = { active = true, openedAt = now() }
        elseif first == "State" then trade.state = safe(args[2]); trade.lastUpdate = now()
        elseif first == "Request" then trade.request = safe(args[2]); trade.lastUpdate = now()
        elseif first == "Closed" then trade.active = false; trade.closedPayload = safe(args[2]); trade.closedAt = now() end
    end
end
local function bind()
    for _, names in ipairs(routes) do
        local key = "ReplicatedStorage." .. table.concat(names, ".")
        local item = path(RS, names)
        if bindings[key] and bindings[key].item ~= item then bindings[key].connection:Disconnect(); bindings[key] = nil end
        if item and item:IsA("RemoteEvent") then
            coverage[key] = "subscribed"
            if not bindings[key] then
                local connection = item.OnClientEvent:Connect(function(...)
                    incoming = incoming + 1
                    local args = table.pack(...)
                    local first, other = args[1], args[2]
                    local cosmetic = names[2] == "Effects" and (first == "AFKDummyRock" or first == "AnimationShockwave" or first == "Rebirth")
                        and typeof(other) == "Instance" and other:IsA("Player") and other ~= player
                    if cosmetic then
                        local k = tostring(first); ambientCounts[k] = (ambientCounts[k] or 0) + 1
                        if ambientSamples[k] then filtered = filtered + 1; return end
                        ambientSamples[k] = true
                    end
                    record("incoming-event", { path = key, args = args })
                    local ok, err = pcall(receive, key, args)
                    if not ok then record("observer-error", { source = key, message = tostring(err) }) end
                end)
                bindings[key] = { item = item, connection = connection }
                record("coverage", { path = key, status = "subscribed; earlier events not replayed" })
            end
        else coverage[key] = item and "wrong class" or "not visible" end
    end
end
local function send(remoteNames, action, ...)
    local remote = path(RS, remoteNames)
    assert(remote and remote:IsA("RemoteEvent"), "Required binding missing: " .. table.concat(remoteNames, "."))
    local args = table.pack(...)
    record("outgoing-request", { action = action, path = remote:GetFullName(), args = args, position = rootPosition(), world = world() })
    remote:FireServer(table.unpack(args, 1, args.n))
end
local function normal(remote, action, ...) return send({ "PunchEscapeRemotes", remote }, action, ...) end
local function probe(name, fn)
    local p = { id = Http:GenerateGUID(false), name = name, requestedAt = now(), monotonic = os.clock(), position = safe(rootPosition()), world = world(), responses = 0 }
    probes[#probes + 1] = p
    if #probes > 100 then table.remove(probes, 1) end
    record("probe-start", p); fn(); return p
end

Lab.actions = {
    { id = "shop_get", label = "Read Charm Shop here", risk = "read", fields = {} },
    { id = "wall_sync", label = "Read wall baseline", risk = "read", fields = {} },
    { id = "drop_sync", label = "Read Charm Shower records", risk = "read", fields = {} },
    { id = "travel", label = "Travel to unlocked world", risk = "position", fields = { { key = "world", label = "World 1-9", type = "number", default = "1" } } },
    { id = "disable_auto", label = "Disable Auto Win / AutoRebirth", risk = "policy", fields = {} },
    { id = "afk_exit", label = "Exit AFK training", risk = "position", fields = {} },
    { id = "equip_best", label = "Equip best pets", risk = "inventory", fields = {} },
    { id = "shop_buy", label = "Buy one charm slot", risk = "spend", fields = { { key = "slot", label = "Slot 1-3", type = "number" }, { key = "maxCrystals", label = "Maximum Crystals to spend", type = "number" } } },
    { id = "lucky_open", label = "Open Wins Lucky Blocks", risk = "spend", fields = { { key = "station", label = "Station 1-27", type = "number" }, { key = "count", label = "Count (1, 3 or 6)", type = "number", default = "1" }, { key = "maxWins", label = "Maximum Wins to spend", type = "number" } } },
    { id = "merge", label = "Merge three reviewed pets", risk = "consume", fields = { { key = "petIds", label = "Three pet IDs, comma separated", type = "list" } } },
    { id = "cleanup", label = "Delete disposable pets", risk = "consume", fields = { { key = "petIds", label = "Disposable pet IDs, comma separated", type = "list" } } },
    { id = "rebirth", label = "One reviewed rebirth", risk = "reset", fields = { { key = "acknowledgeReset", label = "Type RESET to acknowledge reset", type = "text" } } },
    { id = "speed", label = "Request movement speed", risk = "policy", fields = { { key = "speed", label = "Requested walk speed", type = "number" } } },
    { id = "trade_cancel", label = "Cancel current trade", risk = "trade", fields = {} },
    { id = "offline_claim", label = "Claim free offline reward", risk = "reward", fields = {} },
    { id = "group_claim", label = "Claim free group reward", risk = "reward", fields = {} },
    { id = "punch_probe", label = "Small recorded punch sample", risk = "progression", fields = { { key = "count", label = "Punches (1-6)", type = "number", default = "3" }, { key = "gap", label = "Seconds between punches (0.25-2)", type = "number", default = "0.5" } } },
}
local function integer(value, minimum, maximum, label)
    assert(type(value) == "number" and value == math.floor(value) and value >= minimum and value <= maximum, "Invalid " .. label)
    return value
end
local function reviewedPets(ids, merge)
    assert(type(ids) == "table" and #ids >= 1 and #ids <= 30, "Select 1-30 explicit pet IDs.")
    if merge then assert(#ids == 3, "Merge requires exactly three pet IDs.") end
    local seen, identity = {}, nil
    for _, id in ipairs(ids) do
        assert(type(id) == "string" and not seen[id], "Pet IDs must be unique strings."); seen[id] = true
        local pet = path(player, { "PetInventory", id }); assert(pet, "Pet no longer exists: " .. id)
        local a = pet:GetAttributes()
        assert(a.Equipped == false and a.Favorite == false, "Pet must be explicitly unequipped and unfavorited: " .. id)
        if merge then
            assert(type(a.MergeLevel) == "number" and a.MergeLevel < 3, "Unknown or maximum merge level.")
            assert(a.PetName ~= nil and a.Tier ~= nil, "Merge identity is incomplete.")
            local key = table.concat({ tostring(a.PetName), tostring(a.Tier), tostring(a.World or 1), tostring(a.Rarity or "Common"), tostring(a.Limited == true), tostring(a.StrengthFactor or ""), tostring(math.floor(a.MergeLevel)) }, ":")
            assert(identity == nil or identity == key, "Pets do not share the same merge identity."); identity = key
        end
    end
    return ids
end
function Lab.command(id, args)
    args = args or {}
    local action
    for _, a in ipairs(Lab.actions) do if a.id == id then action = a end end
    if not action then return notify("Unknown test action.") end
    if not Lab.running then return notify("Suite stopped. Export before closing.") end
    if busy then return notify("Another test action is still in progress.") end
    if action.risk ~= "read" and not activeTrial then return notify("Start a trial before a state-changing action.") end
    if action.risk ~= "read" then
        local allowed = false
        for _, test in ipairs(Lab.tests or {}) do
            if test.id == activeTrial.testId then for _, candidate in ipairs(test.actions or {}) do if candidate == id then allowed = true end end end
        end
        if not allowed then return notify("This action is not enabled for the active trial. Select its test and start a new trial first.") end
    end
    if trade.active and action.risk ~= "read" and id ~= "trade_cancel" then return notify("Trade is open. Inventory, movement and reset actions are held until it closes.") end
    busy = true
    local ok, err = pcall(function()
        if action.risk ~= "read" then capture("command-before", { action = id, args = args }) end
        if id == "shop_get" then probe(id, function() normal("CharmShopRequest", id, "Get") end)
        elseif id == "wall_sync" then probe(id, function() normal("WallSyncRequest", id) end)
        elseif id == "drop_sync" then probe(id, function() send({ "PunchEscapeAdminRemotes", "CharmShowerVisuals" }, id, "Sync") end)
        elseif id == "disable_auto" then normal("AutoWinRequest", id, false); normal("SettingsPreferenceRequest", id, "AutoRebirth", false)
        elseif id == "afk_exit" then normal("AFKExitRequest", id)
        elseif id == "equip_best" then send({ "PetInventoryAction" }, id, "EquipBest")
        elseif id == "shop_buy" then
            local slot = integer(args.slot, 1, 3, "shop slot")
            assert(type(args.maxCrystals) == "number" and args.maxCrystals >= 0, "Enter an explicit Crystal spending limit.")
            assert(shop and shop.Window ~= nil and shop.Offers, "Read current shop offers first.")
            assert(shop.EndsAt == nil or (serverTime() and serverTime() < shop.EndsAt), "Observed shop window expired; read it again.")
            local charmId = shop.Offers[tostring(slot)] or shop.Offers[slot]
            local config = assert(loadConfig("PunchEscapeCharmConfig"), "Charm price configuration unavailable.")
            local item = config.ById and config.ById[charmId]
            assert(item and type(item.Price) == "number", "Current slot price is unknown.")
            assert(item.Price <= args.maxCrystals, "Price exceeds your Crystal limit.")
            local stats = path(player, { "NumericStats", "Crystals" }); assert(stats and stats.Value >= item.Price, "Insufficient observed Crystals.")
            assert(not (shop.Purchased and (shop.Purchased[tostring(slot)] or shop.Purchased[slot])), "Slot already purchased in this window.")
            normal("CharmShopRequest", id, "Buy", slot, shop.Window)
        elseif id == "lucky_open" then
            local station = integer(args.station, 1, 27, "Lucky Block station")
            assert(args.count == 1 or args.count == 3 or args.count == 6, "Choose 1, 3 or 6 blocks.")
            assert(type(args.maxWins) == "number" and args.maxWins >= 0, "Enter an explicit Win spending limit.")
            assert(player:GetAttribute("PunchEscapePolicyReady") == true and player:GetAttribute("PunchEscapePaidRandomAllowed") == true, "Random-item policy not ready/allowed.")
            local config = assert(loadConfig("LuckyBlockConfig"), "Lucky Block cost configuration unavailable.")
            assert(type(config.GetWinsCost) == "function", "Cost function unavailable.")
            local cost = config.GetWinsCost(station, args.count)
            assert(type(cost) == "number" and cost >= 0 and cost <= args.maxWins, "Cost is unknown or exceeds your Win limit.")
            local stats = path(player, { "NumericStats", "Wins" }); assert(stats and stats.Value >= cost, "Insufficient observed Wins.")
            send({ "LuckyBlockOpenRequest" }, id, station, "Wins", args.count, false)
        elseif id == "merge" then send({ "PetInventoryAction" }, id, "Merge", reviewedPets(args.petIds, true))
        elseif id == "cleanup" then send({ "PetInventoryAction" }, id, "BulkDelete", reviewedPets(args.petIds, false))
        elseif id == "rebirth" then
            assert(not Lab.preserveLanes, "Rebirth blocked while Preserve lanes is on.")
            assert(args.acknowledgeReset == "RESET", "Type RESET to acknowledge progression loss.")
            normal("RebirthRequest", id)
        elseif id == "speed" then
            assert(type(args.speed) == "number" and args.speed >= 0 and args.speed == args.speed, "Invalid movement speed.")
            local config = assert(loadConfig("PunchEscapeConfig"), "Speed-limit configuration unavailable.")
            local level = path(player, { "PlayerStats", "Level" }); assert(level and type(config.GetMaxWalkSpeed) == "function", "Current speed limit is unknown.")
            local maximum = config.GetMaxWalkSpeed(level.Value); assert(type(maximum) == "number" and args.speed <= maximum, "Speed exceeds the configured level limit.")
            normal("MovementSpeedRequest", id, args.speed)
        elseif id == "trade_cancel" then
            local state = trade.state or {}; local countdown = tonumber(state.Countdown)
            assert(state.Locked ~= true and not (countdown and countdown > 0 and countdown <= 5), "Trade may be committing. Reconcile inventories before another command.")
            normal("TradeRemote", id, "Cancel")
        elseif id == "offline_claim" then normal("OfflineRewardRequest", id, "Claim")
        elseif id == "group_claim" then normal("GroupRewardRequest", id)
        elseif id == "punch_probe" then
            local count = integer(args.count, 1, 6, "punch sample count")
            assert(type(args.gap) == "number" and args.gap >= 0.25 and args.gap <= 2, "Punch sample gap must be 0.25-2 seconds.")
            assert(player:GetAttribute("AutoWin") ~= true, "Disable Auto Win before the punch sample.")
            local afk = path(player, { "PlayerStats", "AFKPad" }); assert(not afk or afk.Value == 0 or afk.Value == "" or afk.Value == false, "Exit AFK training first.")
            local walls = workspace:FindFirstChild("PunchEscapePersonalWalls")
            assert(walls and wallState.activeStage and wallState.activeSegment, "Read the wall baseline and stand near its active wall first.")
            local target
            for _, item in ipairs(walls:GetDescendants()) do
                if item:IsA("BasePart") then
                    local stage = item:GetAttribute("Stage") or (item.Parent and item.Parent:GetAttribute("Stage"))
                    local order = item:GetAttribute("WallOrder") or (item.Parent and item.Parent:GetAttribute("WallOrder"))
                    if stage == wallState.activeStage and order == wallState.activeSegment then target = item; break end
                end
            end
            assert(target and rootPosition(), "Active personal wall geometry is not visible; use normal game punches instead.")
            local cfg = assert(loadConfig("PunchEscapeConfig"), "Punch range configuration unavailable.")
            assert(type(cfg.MaximumWallPunchDistance) == "number", "Configured punch range is missing.")
            assert((target.Position - rootPosition()).Magnitude <= cfg.MaximumWallPunchDistance, "Stand within the game's wall range first.")
            local trialId = activeTrial.id
            for i = 1, count do
                assert(Lab.running and activeTrial and activeTrial.id == trialId and not trade.active and player:GetAttribute("AutoWin") ~= true, "Punch sample cancelled by changed state.")
                normal("PunchRequest", id, target.Position)
                if i < count then task.wait(args.gap) end
            end
        elseif id == "travel" then
            local target = integer(args.world, 1, 9, "world")
            local s = snapshot(); assert(type(s.maxWorldUnlocked) == "number" and target <= s.maxWorldUnlocked, "Target world is not observed unlocked.")
            if world() ~= target then
                prepared = nil; normal("WorldTeleportRequest", id, "Prepare", target)
                local deadline = os.clock() + 8
                while Lab.running and os.clock() < deadline and (not prepared or prepared.world ~= target) do task.wait(0.1) end
                assert(Lab.running and prepared and prepared.world == target and typeof(prepared.position) == "Vector3", "No valid preparation response. Commit was not sent.")
                if workspace.StreamingEnabled then
                    local streamOK = pcall(function() player:RequestStreamAroundAsync(prepared.position, 5) end)
                    assert(streamOK and Lab.running, "Streaming preparation failed. Commit was not sent.")
                end
                assert(Lab.running, "Travel cancelled because suite stopped.")
                normal("WorldTeleportRequest", id, "Commit", target)
                deadline = os.clock() + 10
                while Lab.running and os.clock() < deadline and world() ~= target do task.wait(0.1) end
                assert(world() == target, "Travel outcome unknown: target world not observed. Do not blindly retry.")
            end
        end
        record("command-issued", { action = id, args = args, meaning = "Issued request only; verify server response and replicated outcome." })
        task.delay(2, function() if Lab.running then capture("command-followup", { action = id }) end end)
    end)
    busy = false
    if not ok then record("command-blocked-or-uncertain", { action = id, reason = tostring(err) }); return notify(err) end
    Lab.message = action.label .. ": request recorded. Check responses and resulting state; no automatic PASS."
    return true, Lab.message
end
function Lab.selectTest(id)
    for _, t in ipairs(Lab.tests or {}) do if t.id == id then Lab.selectedTestId = id; return true end end
    return notify("Unknown test.")
end
function Lab.setExperiment(value) Lab.experiment = string.sub(tostring(value), 1, 120) end
function Lab.setNotes(value) Lab.notes = string.sub(tostring(value), 1, 8000) end
function Lab.setPreserve(value)
    if not Lab.running then return notify("Suite stopped. Policy requests are disabled.") end
    Lab.preserveLanes = value == true; record("preservation-policy", { enabled = Lab.preserveLanes })
    if Lab.preserveLanes then
        local ok, err = pcall(function() normal("AutoWinRequest", "preserve_lanes", false); normal("SettingsPreferenceRequest", "preserve_lanes", "AutoRebirth", false) end)
        Lab.message = ok and "Preserve-lanes guard on; disable requests sent. Verify actual automation flags before prep." or ("Guard on; could not disable game automation: " .. tostring(err))
    else Lab.message = "Preserve-lanes guard off. Manual claims/rebirth can reset preparation." end
end
function Lab.startTrial()
    if not Lab.running then return notify("Suite stopped.") end
    if not Lab.selectedTestId then return notify("Select a test first.") end
    if activeTrial then activeTrial.status = activeTrial.status == "RUNNING" and "OBSERVED" or activeTrial.status; activeTrial.endedAt = now() end
    local group
    for _, test in ipairs(Lab.tests or {}) do if test.id == Lab.selectedTestId then group = test.group end end
    activeTrial = { id = Http:GenerateGUID(false), testId = Lab.selectedTestId, experiment = Lab.experiment, startedAt = now(), status = "RUNNING", notes = Lab.notes, markers = {},
        evidenceScope = group == "Source replay" and "Source/synthetic case; not live event certification" or "This account/session's observation case" }
    Lab.trials[#Lab.trials + 1] = activeTrial
    local r = capture("before", { trialStart = true }); activeTrial.beforeSeq = r and r.seq; activeTrial.baseline = cache
    Lab.message = "Trial started; baseline captured. Follow the selected test's steps."
    return true
end
function Lab.mark(phase)
    if not Lab.running then return notify("Suite stopped. No new evidence markers can be recorded.") end
    if not activeTrial then return notify("Start a trial first.") end
    if phase ~= "before" and phase ~= "action" and phase ~= "after" and phase ~= "note" then return notify("Unknown marker phase.") end
    activeTrial.phase = phase
    local r = capture(phase, { label = Lab.experiment })
    if r then
        activeTrial.markers[#activeTrial.markers + 1] = { phase = phase, seq = r.seq, notes = Lab.notes }
        if phase == "after" then
            activeTrial.afterSeq = r.seq
            local previous = activeTrial.baseline or {}
            local delta = { stats = {}, charms = {}, swords = {}, petsAdded = {}, petsRemoved = {}, beforeWorld = previous.world, afterWorld = cache.world,
                scope = "Observed changes between markers; correlation does not prove sole causation." }
            for key, value in pairs(cache.stats or {}) do delta.stats[key] = Model.quantityDelta(previous.stats and previous.stats[key], value) end
            for key, value in pairs(cache.charms or {}) do delta.charms[key] = Model.quantityDelta(previous.charms and previous.charms[key], value) end
            for key, value in pairs(cache.swords or {}) do
                if type(value) == "table" then delta.swords[key] = Model.quantityDelta(previous.swords and previous.swords[key] and previous.swords[key].owned, value.owned) end
            end
            if previous.pets and cache.pets then
                for key in pairs(cache.pets) do if not previous.pets[key] then delta.petsAdded[#delta.petsAdded + 1] = key end end
                for key in pairs(previous.pets) do if not cache.pets[key] then delta.petsRemoved[#delta.petsRemoved + 1] = key end end
            end
            activeTrial.observedDelta = delta; Lab.lastDelta = delta; record("trial-observed-delta", delta)
        end
    end
    Lab.message = phase .. " captured."
end
function Lab.review(status)
    if not activeTrial then return notify("Start a trial first.") end
    local valid = { OBSERVED = true, PASS = true, FAIL = true, BLOCKED = true, NOT_RUN = true }
    if not valid[status] then return notify("Unknown review status.") end
    if status == "PASS" and not activeTrial.afterSeq then return notify("Capture an After state before marking this reviewed case PASS.") end
    activeTrial.status = status; activeTrial.reviewNotes = Lab.notes; activeTrial.reviewedAt = now()
    Lab.results[activeTrial.testId] = { status = status, notes = Lab.notes, trialId = activeTrial.id, scope = activeTrial.evidenceScope }
    record("review", { status = status, notes = Lab.notes, scope = "Operator review, not universal or automatic certification." })
    Lab.message = "Recorded operator review: " .. status
end
function Lab.survey()
    if not Lab.running then return notify("Suite stopped.") end
    local ok, err = pcall(function() scan(); surveyConfigs(); surveyGeometry(); capture("survey"); end)
    if not ok then record("observer-error", { source = "survey", message = tostring(err) }); return notify(err) end
    local results = {}
    for _, id in ipairs({ "shop_get", "wall_sync", "drop_sync" }) do local good, why = Lab.command(id, {}); results[#results + 1] = { action = id, requestIssued = good, message = why } end
    record("survey-requests", results)
    Lab.message = "Survey captured; read-only shop/wall/shower requests attempted. Inspect response windows; an empty event state is not a failure."
    return true
end
function Lab.replay()
    local out = {}
    local function test(id, fn)
        local ok, err = pcall(fn); out[#out + 1] = { id = id, status = ok and "PASS" or "FAIL", evidenceClass = "SYNTHETIC", details = ok and "Isolated fixture assertion passed" or tostring(err) }
    end
    -- Fixtures are plain local data. Never FireServer or fake live inventory/state.
    local registry = {}
    local fixture = { id = "fixture-1", world = 9, charmId = "AzureZephyr", readyAt = 10, expiresAt = 30, targetUserId = player.UserId }
    test("shower_target", function() assert(Model.dropEligibility(fixture, player.UserId, 15) == "READY_BY_OBSERVED_FIELDS"); assert(Model.dropEligibility(fixture, player.UserId + 1, 15) == "OTHER_ACCOUNT") end)
    test("shower_timing", function() assert(Model.dropEligibility(fixture, player.UserId, 9) == "NOT_READY"); assert(Model.dropEligibility(fixture, player.UserId, 30) == "EXPIRED"); assert(Model.dropEligibility(fixture, player.UserId, 10) == "READY_BY_OBSERVED_FIELDS") end)
    test("multi_world_registry", function() registry[Model.scopedKey("A", "charm", "1")] = { world = 1 }; registry[Model.scopedKey("A", "charm", "2")] = { world = 9 }; registry[Model.scopedKey("B", "charm", "1")] = { world = 3 }; assert(countTable(registry) == 3) end)
    test("spawn_sync_remove", function()
        local state = {}; Model.showerApply(state, "Spawn", fixture)
        Model.showerApply(state, "Sync", { { id = "fixture-2", world = 1, readyAt = 10, expiresAt = 30 } })
        assert(state["fixture-1"] and state["fixture-2"])
        Model.showerApply(state, "Remove", { id = "fixture-1", reason = "Collected" }); assert(not state["fixture-1"] and state["fixture-2"])
    end)
    test("duplicate_sword_quantity", function() assert(Model.quantityDelta(1, 2) == 1); assert(Model.quantityDelta(nil, 2) == nil) end)
    test("disappearance_not_reward", function() local delta = Model.quantityDelta(2, 2); assert(delta == 0); assert(not (delta > 0)) end)
    test("blade_decisions", function()
        assert(Model.bladeDecision(true, 10, nil, nil) == "OWNED_STOP_ATTEMPTS")
        assert(Model.bladeDecision(false, 0, false, "All 500 copies have already been claimed.") == "EXHAUSTED_STOP_ATTEMPTS")
        assert(Model.bladeDecision(false, 10, true, "Success") == "VERIFY_OWNERSHIP")
        assert(Model.bladeDecision(false, nil, nil, nil) == "ELIGIBILITY_UNKNOWN")
    end)
    test("missing_fields_and_streaming_unknown", function()
        assert(Model.dropEligibility({ targetUserId = player.UserId }, player.UserId, 15) == "UNKNOWN")
        assert(Model.localCoverage(false) == "UNKNOWN_NO_LOCAL_OBJECTS")
        assert(Model.localCoverage(true) == "PARTIAL_LOCAL_OBJECTS")
    end)
    test("wall_init_resets_projection", function()
        local projected = Model.wallInit(1, 1, 10, { 2, 3 }, 1)
        assert(projected.clearedStages["2"] and projected.clearedStages["3"])
        projected = Model.wallInit(1, 1, 10, {}, 2); assert(countTable(projected.clearedStages) == 0)
    end)
    Lab.simulation = out
    record("synthetic-replay", { results = out, fixture = fixture, scope = "Local fixture logic only; never a live event or server acceptance test." })
    Lab.message = tostring(#out) .. " isolated event-contract checks recorded separately from live tests. These do not establish server behavior."
    return out
end
function Lab.view()
    local players = {}
    for _, p in ipairs(Players:GetPlayers()) do players[#players + 1] = { username = p.Name, userId = p.UserId } end
    return { version = Lab.version, running = Lab.running, expectedMain = Lab.expectedMain, identity = { username = player.Name, userId = player.UserId, jobId = game.JobId, placeId = game.PlaceId, placeVersion = game.PlaceVersion },
        selectedTestId = Lab.selectedTestId, experiment = Lab.experiment, notes = Lab.notes, preserveLanes = Lab.preserveLanes, activeTrial = activeTrial,
        summary = { events = incoming, records = #rows, dropped = lost, evicted = evicted, truncations = truncations, segments = #segments, saveError = saveError, filteredAmbient = filtered },
        snapshot = cache, results = Lab.results, players = players, message = Lab.message, simulation = Lab.simulation, probes = probes, lastDelta = Lab.lastDelta }
end
function Lab.exportJSON()
    persist(true)
    local all, seen, unreadable = {}, {}, {}
    if reader then
        for _, part in ipairs(segments) do
            local ok, value = pcall(function() return Http:JSONDecode(reader(part.filename)) end)
            if ok and type(value) == "table" and type(value.records) == "table" then
                for _, r in ipairs(value.records) do if not seen[r.seq] then all[#all + 1] = r; seen[r.seq] = true end end
            else unreadable[#unreadable + 1] = part.filename end
        end
    end
    for _, e in ipairs(rows) do if not seen[e.value.seq] then all[#all + 1] = e.value; seen[e.value.seq] = true end end
    table.sort(all, function(a, b) return a.seq < b.seq end)
    return Http:JSONEncode({ schemaVersion = 1, kind = "slash-recorder", session = session, records = all, baseline = baseline,
        coverage = coverage, exportedAt = now(), droppedRecords = lost, truncations = truncations, evictedFromMemory = evicted,
        segmentManifest = segments, unreadableSegments = unreadable, fullHistoryReassembled = reader ~= nil and #unreadable == 0 and lost == 0,
        tests = Lab.tests, trials = Lab.trials, results = Lab.results, simulation = Lab.simulation, probes = probes,
        filteredAmbientEvents = filtered, ambientCounts = ambientCounts, configurationStatus = configStatus,
        health = { running = Lab.running, incomingEvents = incoming, retainedRecords = #all, droppedRecords = lost, truncations = truncations, subscribedRoutes = countTable(bindings), totalRoutes = #routes },
        limitations = { "Only this account is instrumented", "Only tool-originated outgoing requests are logged", "Manual game UI actions need markers for intent", "Empty or streamed-out drops do not prove absence", "Simulation is not live server evidence", "Physical reward-pad touches outside this suite cannot be blocked by its preserve setting" } })
end
function Lab.save()
    if not writer then return notify("File API unavailable. Use Copy or Show JSON and export after each short trial.") end
    local ok, result = pcall(function()
        local json = Lab.exportJSON(); local filename = "slash-suite-" .. session.id .. "-complete.json"
        writer(filename, json)
        if reader then assert(reader(filename) == json, "Complete export read-back failed.") end
        return filename
    end)
    if not ok then return notify(result) end
    Lab.message = "Exported " .. result .. ". Keep segment files until the complete file is checked."
    return true, Lab.message
end
function Lab.copy()
    if not copier then return notify("Clipboard API unavailable. Use Save or selectable JSON export.") end
    local ok, err = pcall(function() copier(Lab.exportJSON()) end)
    if not ok then return notify(err) end
    Lab.message = "Copy call returned. Paste into a .json file and retain it."
    return true
end
function Lab.stop()
    if not Lab.running then return end
    capture("stopped"); Lab.running = false
    for k, b in pairs(bindings) do b.connection:Disconnect(); coverage[k] = "disconnected: stopped" end
    for _, connection in ipairs(connections) do connection:Disconnect() end
    persist(true); Lab.message = "Stopped. Save/Copy remains available; export before closing."
end
function Lab.close() Lab.stop(); if Lab.gui then Lab.gui:Destroy() end end

record("started", session)
bind()
local scanOK, scanError = pcall(scan); if not scanOK then record("observer-error", { source = "initial scan", message = tostring(scanError) }) end
cache = snapshot(); baseline = record("initial-snapshot", { state = cache }); lastStateKey = Http:JSONEncode(cache)
table.insert(connections, PromptService.PromptTriggered:Connect(function(prompt, who)
    if who == nil or who == player then record("prompt-triggered", { prompt = prompt, position = rootPosition(), world = world(), enabled = prompt.Enabled, holdDuration = prompt.HoldDuration, maxDistance = prompt.MaxActivationDistance }) end
end))
table.insert(connections, Players.PlayerAdded:Connect(function(p) record("player-joined", { username = p.Name, userId = p.UserId }) end))
table.insert(connections, Players.PlayerRemoving:Connect(function(p) record("player-left", { username = p.Name, userId = p.UserId }) end))
table.insert(connections, player.CharacterAdded:Connect(function() record("character-added", { world = world() }) end))
local lastHeartbeat, lastScan = os.clock(), os.clock()
task.spawn(function()
    while Lab.running do
        local ok, err = pcall(function()
            bind()
            if os.clock() - lastScan >= 5 then scan(); lastScan = os.clock() end
            cache = snapshot()
            local encoded = Http:JSONEncode(cache)
            if encoded ~= lastStateKey then record("state-snapshot", { state = cache }); lastStateKey = encoded end
            if os.clock() - lastHeartbeat >= 10 then
                record("heartbeat", { incomingEvents = incoming, retainedRecords = #rows, durableSegments = #segments,
                    unsavedLostRecords = lost, evictedFromMemory = evicted, filteredAmbientEvents = filtered, ambientCounts = ambientCounts, saveError = saveError })
                lastHeartbeat = os.clock()
            end
            persist(false)
        end)
        if not ok then record("observer-error", { source = "poll", message = tostring(err) }) end
        task.wait(2)
    end
end)


-- Test catalog for the single-account Slash evidence suite.
-- This file is data only: engine.lua owns execution and UI owns presentation.
-- A test status is an operator review; the catalog never declares a server fact.

local TESTS = {
  {
    id = "T01", title = "Clear a lane, travel, and return", group = "Now",
    goal = "Verify the user-confirmed same-session lane rule without claiming Wins.",
    prerequisites = {"mxssyo is in World 9 or another unlocked world", "A lane can be cleared without claiming its reward", "Record the current server/job identity"},
    steps = {"Start a trial and mark before", "Clear one lane and do not claim the Wins pad", "Use the suite travel action to an unlocked world, then return", "Mark after and compare the lane, Wins, world, and server identity"},
    evidence = {"LT01: same jobId before/after", "LT01: cleared lane list or wall state", "LT01: Wins unchanged", "AC12: lane remains open after same-server travel"},
    limits = {"Do not infer reconnect, death, or claim behavior from this test", "A UI wall absence is not proof of authoritative readiness"},
    actions = {"travel", "wall_sync"}, requirements = {"LT01", "AC11", "AC12", "U05"}
  },
  {
    id = "T02", title = "Claim a prepared lane", group = "Now",
    goal = "Measure reward and reset scope after an explicit progression claim.",
    prerequisites = {"A disposable or deliberately selected lane is prepared", "Operator accepts that claiming may reset that lane"},
    steps = {"Mark before with lane and Wins snapshots", "Claim the selected lane through the game UI", "Mark after and survey all visible wall/lane states"},
    evidence = {"LT02: reward delta", "LT02: cleared-stage reset scope", "AC15: Main may claim only under progression policy"},
    limits = {"Do not claim a prepared minion lane in preserve mode", "No automatic Win claim is issued by the suite"},
    actions = {"wall_sync"}, requirements = {"LT02", "AC11", "AC15", "INV 05", "INV 06"}
  },
  {
    id = "T03", title = "Death and respawn after preparation", group = "Now",
    goal = "Determine whether death or respawn invalidates lane readiness and navigation state.",
    prerequisites = {"A disposable lane or safe test state", "No rebirth or cleanup action queued"},
    steps = {"Mark before after preparing a lane", "Die or use the normal game respawn", "Wait for the character and state to settle", "Mark after and survey walls, world, inventory, and position"},
    evidence = {"LT03: death/respawn transition", "AC13: readiness invalidation or explicitly observed persistence", "Navigation recovery evidence"},
    limits = {"Do not treat an unchanged client UI as server confirmation", "Use a disposable progression state if the game consumes progress"},
    actions = {"wall_sync"}, requirements = {"LT03", "AC13", "INV 08", "U01", "U05"}
  },
  {
    id = "T04", title = "Reconnect the observer in the same session", group = "Now",
    goal = "Separate a transport/recorder interruption from leaving the Roblox server.",
    prerequisites = {"A saveable recorder export", "Stable game session and server identity"},
    steps = {"Mark before, export/save the current trial, and stop the observer", "Restart the suite and create a new trial with the same experiment label", "Survey identity and lane state", "Export/save the new trial and compare the two separate exports"},
    evidence = {"LT04: session epoch and jobId continuity", "AC06: stale generation handling is a platform test", "Lane readiness is either reconciled or invalidated"},
    limits = {"If Roblox leaves the server, classify as LT05 instead", "No readiness is reused solely from a local file"},
    actions = {"wall_sync"}, requirements = {"LT04", "AC06", "INV 08", "U03"}
  },
  {
    id = "T05", title = "Leave, rejoin, and change server", group = "Now",
    goal = "Determine persistence scope across a genuine session boundary.",
    prerequisites = {"Disposable lane state", "A way to record the original jobId"},
    steps = {"Mark before, export/save the current trial, and stop the observer", "Leave and rejoin the game", "Restart the suite with the same experiment label and create a new trial", "Record the new jobId and world, survey lane state, then export/save the new trial"},
    evidence = {"LT05: old/new server identity", "AC13: previous readiness is not blindly reused", "Any durable inventory or world state changes"},
    limits = {"Do not call server migration equivalent to world travel", "Do not repeat if the state is costly to recreate"},
    actions = {"wall_sync"}, requirements = {"LT05", "AC13", "INV 08", "U04", "U05"}
  },
  {
    id = "T06", title = "World travel and unlock inventory", group = "Now",
    goal = "Verify each unlocked-world travel handshake and its server/session effects.",
    prerequisites = {"mxssyo provides access to World 9", "Target world is selected by the operator", "Record current jobId and position"},
    steps = {"For each selected unlocked world, mark before", "Travel using the suite action", "Wait for the destination state", "Mark after and compare world, jobId, and wall baseline"},
    evidence = {"LT06: destination world and unlock state", "AC14: locked world blocks safely", "U05: current build compatibility"},
    limits = {"Only use worlds reported unlocked", "Do not infer locked-world requirements from an unattempted request"},
    actions = {"travel", "wall_sync"}, requirements = {"LT06", "AC14", "U05", "INV 07"}
  },
  {
    id = "T07", title = "Ordinary sword drops and pickup", group = "Now",
    goal = "Capture drop identity, world, position, expiry, and quantity-confirmed pickup for ordinary drops.",
    prerequisites = {"A world where ordinary drops can occur", "Recorder running with sufficient segment retention", "Disposable pickup budget if a drop costs anything"},
    steps = {"Run drop_sync and mark before", "Observe a drop without immediately moving", "Record world, coordinates, identity, and timing", "Collect one eligible drop when prompted", "Mark after and compare sword quantity/inventory"},
    evidence = {"LT07: drop event and position", "AC19: unreachable/expired handling", "AC21: disappearance without inventory gain", "AC27: duplicate quantity reconciliation"},
    limits = {"One account cannot prove cross-account entitlement", "Absence is UNKNOWN when the world is not observable", "Do not treat object disappearance as pickup success"},
    actions = {"drop_sync"}, requirements = {"LT07", "AC19", "AC21", "AC22", "AC27", "U08"}
  },
  {
    id = "T08", title = "Charm Shower schema replay and live hook", group = "Source replay",
    goal = "Validate handling of the known event shape in isolation while retaining a later live event gate.",
    prerequisites = {"No live event is required for replay", "Recorder event schema is available"},
    steps = {"Run replay for start, target, world, position, expiry, and end records", "Review synthetic results separately from live results", "Use drop_sync during a real event only when one occurs"},
    evidence = {"LT08: synthetic lifecycle and target filtering", "AC26: account-targeted records remain scoped", "Live event evidence is marked later validation"},
    limits = {"Replay never emits a game remote", "Synthetic timing is not live timing", "Do not claim Charm Shower delivery is live-verified"},
    actions = {"drop_sync"}, requirements = {"LT08", "AC18", "AC26", "U08"}
  },
  {
    id = "T09", title = "Blade eligibility decision replay", group = "Source replay",
    goal = "Exercise Blade allocation decisions without attempting a depleted shrine or bypassing the server.",
    prerequisites = {"No live Blade stock is needed", "Synthetic cases: eligible, exhausted, owned, cooldown, and rejected"},
    steps = {"Run replay for each result and ownership transition", "Confirm owned accounts leave the candidate pool", "Record the live shrine result separately if observed"},
    evidence = {"LT09: no retry after owned/exhausted result", "AC18: spare collector/Blade allocation model", "AC20: ownership verification gate"},
    limits = {"The observed 500-copy post-event exhaustion is not a universal cap", "No direct grant, counter edit, or bypass is attempted", "Live eligibility remains UNKNOWN until an event provides it"},
    actions = {}, requirements = {"LT09", "AC18", "AC20", "U07"}
  },
  {
    id = "T10", title = "Charm Shop remote read and bounded purchase", group = "Now",
    goal = "Determine whether fresh shop stock can be requested away from the shop and reconcile one bounded purchase.",
    prerequisites = {"Character is intentionally away from the shop for the read", "Only an optional purchase needs enough Crystals and an explicit spending limit"},
    steps = {"Mark position and run shop_get", "Compare offers, refresh, and purchase flags without opening shop UI", "If approved, buy one slot under the stated budget", "Mark after and reconcile crystals and charm quantity"},
    evidence = {"LT12: request/response at distance", "AC24: monitoring does not imply purchases", "Price, slot, refresh, and inventory delta"},
    limits = {"A response does not prove server-wide or cross-account stock scope", "No purchase occurs without a fresh operator confirmation", "Do not exceed the supplied budget"},
    actions = {"shop_get", "shop_buy"}, requirements = {"LT12", "AC24", "U08", "INV 10"}
  },
  {
    id = "T11", title = "Training, speed, and game-owned automation", group = "Now",
    goal = "Measure AFK exit, speed request, and interference from Auto Win/AutoRebirth before preparation.",
    prerequisites = {"Current character is safe to move", "Operator records current speed and game-owned toggles"},
    steps = {"Mark before and survey", "Exit AFK training if active", "Request a bounded speed value only if approved", "Disable Auto Win/AutoRebirth", "Survey and mark after"},
    evidence = {"AC28: incompatible game-owned settings disabled and verified", "AFK and speed responses", "No claim or rebirth emitted by the suite"},
    limits = {"Do not infer that speed remains after reconnect", "Disabling a game-owned toggle is a policy mutation and requires confirmation"},
    actions = {"afk_exit", "speed", "disable_auto"}, requirements = {"AC28", "INV 05", "U01", "U03"}
  },
  {
    id = "T12", title = "Pets: equip, merge, and protected cleanup", group = "Now",
    goal = "Verify explicit pet guards, merge outputs, equip capacity, and deletion restrictions.",
    prerequisites = {"Three reviewed disposable pets for merge", "Separate reviewed disposable pets for cleanup", "No protected/equipped/reserved IDs selected"},
    steps = {"Survey and record IDs, equipped/favorite/protected flags", "Equip best only after baseline", "Merge exactly three reviewed pets", "Reconcile consumed IDs and output", "Delete only reviewed disposable IDs", "Mark after"},
    evidence = {"LT13: recipe/output and consumed IDs", "AC16: record any conflicting operator selection", "AC29: protected/equipped/favorite pets are blocked"},
    limits = {"No bulk AutoMerge", "The current tool only guards explicit operator-reviewed protected/equipped/favorite IDs; reservation arbitration is platform work", "No deletion of unknown IDs", "Inventory child count alone is insufficient"},
    actions = {"equip_best", "merge", "cleanup"}, requirements = {"LT13", "AC16", "AC29", "U01"}
  },
  {
    id = "T13", title = "Lucky Blocks and completion handshake", group = "Now",
    goal = "Measure cost, station scope, reward creation, capacity, and cinematic/skip behavior.",
    prerequisites = {"Disposable Wins budget and an approved station", "Count is 1, 3, or 6", "Operator chooses whether skip is allowed"},
    steps = {"Mark before with Wins and pet inventory", "Open one bounded batch through the suite's verified four-argument request with skip=false", "Wait for the normal game's cinematic handler to complete", "If separately testing skip, use the normal game UI only after confirming an owned entitlement", "Mark after and reconcile cost, new pets, and completion state"},
    evidence = {"LT14: request/result and Wins delta", "LT20: cinematic and optional skip state", "Capacity or cooldown failure evidence"},
    limits = {"Do not infer a universal cost from one batch", "The suite never sets skip=true", "Stop on missing completion or ambiguous reward", "Never spend over maxWins"},
    actions = {"lucky_open"}, requirements = {"LT14", "LT20", "U01", "U05"}
  },
  {
    id = "T14", title = "Rebirth on disposable state", group = "Now",
    goal = "Record exact reset scope and invalidate prepared-state assumptions.",
    prerequisites = {"A disposable progression state and explicit RESET acknowledgement", "No active trade or protected inventory mutation"},
    steps = {"Mark all visible progression, worlds, lanes, pets, charms, and gear", "Perform one reviewed rebirth", "Survey after the state settles", "Mark after with reset deltas"},
    evidence = {"LT15: exact resets and durable inventory", "AC17: prepared minion rebirth blocked by policy", "Readiness invalidation"},
    limits = {"Never run on the main prepared account without explicit operator policy", "The suite requires typed RESET acknowledgement", "No assumptions about hidden server fields"},
    actions = {"rebirth"}, requirements = {"LT15", "AC17", "INV 05", "U01"}
  },
  {
    id = "T15", title = "Lane-pad navigation in preserve mode", group = "Now",
    goal = "Measure safe movement to reward pads while preserving unclaimed lanes.",
    prerequisites = {"Auto Win/AutoRebirth disabled", "Preserve mode enabled", "At least one prepared lane"},
    steps = {"Enable preserve mode and mark before", "Navigate near the end-of-lane reward pad without claiming", "Observe route and wall state", "Mark after and leave the lane unclaimed"},
    evidence = {"LT16: route and positional ownership", "AC11: every lane remains open/unclaimed", "AC28: policy guard evidence"},
    limits = {"Do not click or trigger a reward pad", "Position observation is not a claim result", "Stop if game-owned automation re-enables"},
    actions = {"disable_auto", "wall_sync"}, requirements = {"LT16", "AC11", "AC28", "INV 05", "INV 09"}
  },
  {
    id = "T16", title = "Event-contract replay and isolation", group = "Source replay",
    goal = "Check the event contract projection that the engine implements: target, timing, Spawn/Sync/Remove, multiworld scope, quantity deltas, Blade availability, and streaming unknowns.",
    prerequisites = {"Synthetic event fixtures", "No live action required"},
    steps = {"Replay Spawn, Sync, and Remove records with identity, world, position, target, and expiry", "Replay two worlds with the same local drop label and a quantity delta", "Replay missing/streaming fields and verify UNKNOWN", "Review synthetic results separately"},
    evidence = {"AC22: streaming yields UNKNOWN", "AC27: duplicate quantity changes reconcile", "AC26: targeted records retain account scope", "Source bindings remain SOURCE VERIFIED only"},
    limits = {"Fixtures do not prove server acceptance or live timing", "Do not mark live tests PASS from replay alone", "World unlock, shop semantics, and broad architecture are not simulated here"},
    actions = {}, requirements = {"AC21", "AC22", "AC26", "AC27", "U01", "U08"}
  },
  {
    id = "T17", title = "Event routing and server-key replay", group = "Source replay",
    goal = "Exercise only event routing and server-key isolation using synthetic observations; architecture acceptance remains deferred platform software work.",
    prerequisites = {"Synthetic server keys and event records", "Synthetic drop/event records only"},
    steps = {"Replay identical local drop IDs under two server keys", "Replay Spawn/Sync/Remove and quantity deltas", "Replay targeted drops, expired/unreachable drops, and Blade availability/owned outcomes", "Review routing and isolation results"},
    evidence = {"AC02: no cross-server collision", "AC18–AC22: event planner projections", "Main protection and lease/scheduler acceptance are deferred platform tests"},
    limits = {"This is an event-contract check, not a platform architecture simulator", "No live commands are issued", "AC01–AC10, AC23–AC25 and other architecture rows require platform software tests", "Replay does not certify the adapter"},
    actions = {}, requirements = {"LT17", "LT19", "AC01", "AC02", "AC03", "AC04", "AC05", "AC06", "AC07", "AC08", "AC09", "AC10", "AC18", "AC19", "AC20", "AC21", "AC22", "AC23", "AC24", "AC25", "U02", "U07", "U08"}
  },
  {
    id = "T18", title = "Trade event flow and local inventory", group = "Later",
    goal = "Optionally validate one small trade with any willing player; the counterpart does not need the suite.",
    prerequisites = {"A willing player", "One disposable known item or quantity", "No other local inventory mutation during the test"},
    steps = {"Start the trial before opening a trade", "Use the normal trade UI and record its offer/state for the known item", "Confirm only the exact offer you intend, then wait for the trade to close", "Mark after and compare this account's actual inventory", "Evidence from the counterpart is optional additional confirmation"},
    evidence = {"LT10: local offer token and item eligibility", "AC11: bilateral reconciliation requires counterpart evidence", "AC16: note conflicting local selections", "AC27: duplicate quantity"},
    limits = {"No automatic trade acceptance", "The other player need not run the Lua suite", "The suite cannot see a remote player's inventory merely because TradeRemote state exists", "A closed window or acknowledgement is not completion"},
    actions = {"trade_cancel"}, requirements = {"LT10", "LT18", "AC11", "AC16", "AC23", "AC27", "U06"}
  },
  {
    id = "T19", title = "Trade cancellation and ambiguous commit", group = "Later",
    goal = "Record cancellation, disconnect, and near-confirmation behavior without unsafe replay.",
    prerequisites = {"A willing player and a disposable item", "A safe point before confirmation", "Operator controls all confirmations"},
    steps = {"Open a trade and mark before", "Cancel before confirmation, then reconcile", "If voluntarily testing near-commit interruption, stop and reconcile before any retry", "Use trade_cancel for an uncommitted window"},
    evidence = {"AC23: no blind replay", "AC08: safe cancellation boundary", "Final inventory deltas and unresolved status"},
    limits = {"Do not force disconnects or exploit timing", "Never retry an ambiguous consumptive action before reconciliation"},
    actions = {"trade_cancel"}, requirements = {"LT11", "AC08", "AC23", "U06"}
  },
  {
    id = "T20", title = "Event readiness contract review", group = "Source replay",
    goal = "Prepare the next Admin Abuse event by validating event schemas and required evidence without waiting for the event.",
    prerequisites = {"Source mappings and prior captures", "Synthetic fixtures for sword, Charm Shower, targeted charm, and Blade decisions"},
    steps = {"Run all isolated event replays", "Check event identity, world, coordinates, target, expiry, pickup, and ownership fields", "Record live event validation as later-only work", "Leave unsupported rules visibly BLOCKED"},
    evidence = {"U07: Blade eligibility/cadence/ownership unknowns", "U08: complete drop coverage unknowns", "AC18, AC20, AC26: planner decisions"},
    limits = {"Simulation never proves event timing, entitlement, or server acceptance", "No direct Blade grant or cap bypass", "Event observation during a future Admin Abuse remains a certification step"},
    actions = {"drop_sync"}, requirements = {"LT08", "LT09", "AC18", "AC20", "AC26", "U07", "U08"}
  },
  {
    id = "T21", title = "Slash and wall cadence with fist upgrades", group = "Now",
    goal = "Measure normal click/slash cadence, wall damage/threshold behavior, and fist upgrade requirements using the game UI.",
    prerequisites = {"A disposable or deliberately selected progression segment", "Record current Wins, wall, fist/upgrade state, and position", "No preserve-mode minion policy is active"},
    steps = {"Emit before snapshot and note the intended cadence", "Perform a short, manually controlled sequence of normal slashes through the game UI", "Record wall damage, reward threshold, and any accepted cadence limits", "Purchase or select one available fist upgrade in the normal UI only if affordable", "Emit after snapshot and reconcile stats, wall, and currency"},
    evidence = {"Master feature list: normal slash cadence", "Master feature list: wall damage/threshold", "Master feature list: fist upgrade requirements and resulting stats", "Before/action/after snapshots"},
    limits = {"The optional punch probe uses the discovered PunchRequest only: 1-6 punches, a 0.25-2 second interval, and visible active-wall geometry within the configured range", "Use normal game punches if the active wall cannot be resolved", "Do not infer a universal cadence from one segment", "Do not spend beyond an explicitly chosen budget", "A client-side animation is not a server-accepted hit"},
    actions = {"wall_sync", "punch_probe"}, requirements = {"AC11", "U01", "U05", "FEATURE_SLASH_CADENCE", "FEATURE_WALL_DAMAGE", "FEATURE_FIST_UPGRADES"}
  },
  {
    id = "T22", title = "Free, offline, and group rewards", group = "Now",
    goal = "Inspect available free/offline/group reward flows and their actual currency or inventory deltas.",
    prerequisites = {"A safe account state", "Record reward timers/eligibility and currencies before", "Use only normal game UI prompts"},
    steps = {"Emit before snapshot", "Open or claim each currently eligible free, offline, or group reward through the normal game UI", "Capture any timer, cooldown, eligibility, and result messages", "Emit after snapshot and reconcile exact deltas"},
    evidence = {"Master feature list: free reward eligibility and cooldown", "Master feature list: offline reward amount and claim state", "Master feature list: group reward eligibility and result", "Before/action/after snapshots"},
    limits = {"No reward is fabricated when unavailable", "The suite uses only the discovered free Claim and GroupRewardRequest interfaces; no paid Double", "One account cannot establish group membership rules for every account", "An unopened prompt remains NOT_RUN"},
    actions = {"offline_claim", "group_claim"}, requirements = {"U01", "U05", "FEATURE_FREE_REWARDS", "FEATURE_OFFLINE_REWARDS", "FEATURE_GROUP_REWARDS"}
  }
}

Lab.tests = TESTS

Lab.selectTest("T10")

-- Slash single-account evidence suite UI.
-- This part is intentionally service-agnostic: engine.lua owns Lab and catalog.lua owns Lab.tests.
local function buildUI(Lab)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local player = Players.LocalPlayer
    local gui = Instance.new("ScreenGui")
    gui.Name = "SlashInGameTestSuite"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 10000
    gui.Parent = player and player:WaitForChild("PlayerGui") or game:GetService("CoreGui")
    Lab.gui = gui

    local C = {
        bg = Color3.fromRGB(11, 18, 24), panel = Color3.fromRGB(18, 29, 37), panel2 = Color3.fromRGB(24, 38, 47),
        line = Color3.fromRGB(45, 65, 75), text = Color3.fromRGB(229, 242, 241), muted = Color3.fromRGB(151, 177, 180),
        mint = Color3.fromRGB(73, 220, 174), mintDark = Color3.fromRGB(22, 115, 92), amber = Color3.fromRGB(250, 189, 84),
        red = Color3.fromRGB(244, 110, 111), blue = Color3.fromRGB(107, 184, 244)
    }
    local fonts = Enum.Font.Gotham
    local compact = Enum.Font.GothamMedium
    local selectedId, minimized, alive = nil, false, true
    local refs, actionInputs = {}, {}
    local experiment, notes
    local function corner(o, radius)
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, radius or 7); c.Parent = o
    end
    local function stroke(o, color)
        local s = Instance.new("UIStroke"); s.Color = color or C.line; s.Thickness = 1; s.Transparency = .25; s.Parent = o
    end
    local function label(parent, text, size, color, bold)
        local l = Instance.new("TextLabel"); l.BackgroundTransparency = 1; l.Text = text or ""; l.TextColor3 = color or C.text
        l.Font = bold and compact or fonts; l.TextSize = size or 13; l.TextXAlignment = Enum.TextXAlignment.Left; l.TextYAlignment = Enum.TextYAlignment.Top
        l.TextWrapped = true; l.AutomaticSize = Enum.AutomaticSize.Y; l.Size = UDim2.new(1, 0, 0, size and math.max(18, size + 6) or 24); l.Parent = parent; return l
    end
    local function button(parent, text, callback, color, width)
        local b = Instance.new("TextButton"); b.AutoButtonColor = true; b.Text = text; b.Font = compact; b.TextSize = 12; b.TextColor3 = C.text
        b.BackgroundColor3 = color or C.panel2; b.Size = UDim2.new(0, width or 108, 0, 30); b.BorderSizePixel = 0; b.Parent = parent; corner(b, 6); stroke(b)
        if callback then b.Activated:Connect(callback) end
        return b
    end
    local function field(parent, placeholder, initial)
        local t = Instance.new("TextBox"); t.ClearTextOnFocus = false; t.PlaceholderText = placeholder or ""; t.Text = initial or ""; t.Font = fonts; t.TextSize = 12; t.TextColor3 = C.text
        t.PlaceholderColor3 = C.muted; t.BackgroundColor3 = C.bg; t.Size = UDim2.new(1, 0, 0, 30); t.BorderSizePixel = 0; t.Parent = parent; corner(t, 5); stroke(t); return t
    end
    local function list(parent, gap)
        local l = Instance.new("UIListLayout"); l.Padding = UDim.new(0, gap or 6); l.SortOrder = Enum.SortOrder.LayoutOrder; l.Parent = parent; return l
    end
    local function frame(parent, color, size)
        local f = Instance.new("Frame"); f.BackgroundColor3 = color or C.panel; f.BorderSizePixel = 0; f.Size = size or UDim2.new(1, 0, 0, 0); f.Parent = parent; corner(f, 8); return f
    end
    local function arr(v)
        if type(v) ~= "table" then return "" end
        local out = {}; for i, x in ipairs(v) do out[i] = "- " .. tostring(x) end; return table.concat(out, "\n")
    end
    local function safeView()
        local ok, v = pcall(function() return Lab.view() end); return ok and type(v) == "table" and v or {}
    end
    local function testById(id)
        for _, t in ipairs(Lab.tests or {}) do if tostring(t.id) == tostring(id) then return t end end
    end
    local function statLine(v)
        local id = v.identity or {}; local s = v.summary or {}; local snap = v.snapshot or {}
        local stats = snap.stats or snap.playerStats or {}
        return string.format("%s  •  %s  •  world %s  •  events %s  •  records %s", tostring(id.username or "player"), tostring(id.jobId or "server?"), tostring(snap.world or "?"), tostring(s.events or 0), tostring(s.records or 0))
    end

    local root = frame(gui, C.bg, UDim2.new(1, 0, 1, 0)); root.BackgroundTransparency = .08
    local top = Instance.new("Frame"); top.BackgroundColor3 = C.panel; top.BorderSizePixel = 0; top.Size = UDim2.new(1, 0, 0, 54); top.Parent = root
    local title = label(top, "SLASH  /  EVIDENCE SUITE", 16, C.mint, true); title.Position = UDim2.new(0, 18, 0, 9); title.Size = UDim2.new(1, -280, 0, 22)
    local subtitle = label(top, "single-account observation and validation", 11, C.muted, false); subtitle.Position = UDim2.new(0, 19, 0, 31); subtitle.Size = UDim2.new(1, -280, 0, 16)
    local body
    local minBtn
    minBtn = button(top, "MINIMIZE", function()
        minimized = not minimized
        if body then body.Visible = not minimized end
        root.Size = minimized and UDim2.new(1, 0, 0, 54) or UDim2.new(1, 0, 1, 0)
        root.BackgroundTransparency = minimized and 1 or .08
        minBtn.Text = minimized and "OPEN" or "MINIMIZE"
    end, C.panel2, 82); minBtn.Position = UDim2.new(1, -270, 0, 12)
    local stopBtn = button(top, "STOP", function() pcall(Lab.stop); refs.status.Text = "stopped (export remains available)" end, C.panel2, 54); stopBtn.Position = UDim2.new(1, -182, 0, 12)
    local closeBtn = button(top, "CLOSE", function() pcall(Lab.stop); pcall(Lab.save); alive = false; pcall(Lab.close); if gui.Parent then gui:Destroy() end end, C.red, 54); closeBtn.Position = UDim2.new(1, -120, 0, 12)

    body = Instance.new("Frame"); body.BackgroundTransparency = 1; body.Position = UDim2.new(0, 10, 0, 62); body.Size = UDim2.new(1, -20, 1, -70); body.Parent = root
    local left = frame(body, C.panel, UDim2.new(.29, -5, 1, 0)); left.Position = UDim2.new(0, 0, 0, 0)
    local right = frame(body, C.panel, UDim2.new(.71, -5, 1, 0)); right.Position = UDim2.new(.29, 10, 0, 0)
    label(left, "TEST PLAN", 13, C.mint, true).Position = UDim2.new(0, 12, 0, 10)
    local listScroll = Instance.new("ScrollingFrame"); listScroll.BackgroundTransparency = 1; listScroll.BorderSizePixel = 0; listScroll.Position = UDim2.new(0, 8, 0, 37); listScroll.Size = UDim2.new(1, -16, 1, -45); listScroll.ScrollBarThickness = 4; listScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y; listScroll.CanvasSize = UDim2.new(); listScroll.Parent = left
    list(listScroll, 5)
    local detailScroll = Instance.new("ScrollingFrame"); detailScroll.BackgroundTransparency = 1; detailScroll.BorderSizePixel = 0; detailScroll.Position = UDim2.new(0, 10, 0, 8); detailScroll.Size = UDim2.new(1, -20, 1, -16); detailScroll.ScrollBarThickness = 5; detailScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y; detailScroll.CanvasSize = UDim2.new(); detailScroll.Parent = right
    list(detailScroll, 8)
    local detail = detailScroll
    local function wipeDetail() for _, c in ipairs(detail:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end end

    local modal = frame(gui, C.panel, UDim2.new(0, 350, 0, 190)); modal.AnchorPoint = Vector2.new(.5, .5); modal.Position = UDim2.new(.5, 0, .5, 0); modal.Visible = false; modal.ZIndex = 30; stroke(modal, C.amber)
    local modalText = label(modal, "", 13, C.text, false); modalText.Position = UDim2.new(0, 16, 0, 16); modalText.Size = UDim2.new(1, -32, 0, 82); modalText.ZIndex = 31
    local modalCancel = button(modal, "CANCEL", function() modal.Visible = false end, C.panel2, 100); modalCancel.Position = UDim2.new(0, 28, 1, -48); modalCancel.ZIndex = 31
    local pendingCallback
    local modalGo = button(modal, "CONFIRM", function() modal.Visible = false; local callback = pendingCallback; pendingCallback = nil; if callback then callback() end end, C.mintDark, 110); modalGo.Position = UDim2.new(1, -138, 1, -48); modalGo.ZIndex = 31
    local function confirm(text, callback) modalText.Text = text; pendingCallback = callback; modal.Visible = true end

    local actionBox = frame(detail, C.panel2, UDim2.new(1, 0, 0, 0)); actionBox.AutomaticSize = Enum.AutomaticSize.Y; actionBox.LayoutOrder = 40
    label(actionBox, "ACTION CONSOLE", 13, C.mint, true).Position = UDim2.new(0, 12, 0, 10)
    local actionHint = label(actionBox, "Read-only probes can run from Survey. Mutations require an active trial and confirmation.", 11, C.muted, false); actionHint.Position = UDim2.new(0, 12, 0, 31); actionHint.Size = UDim2.new(1, -24, 0, 28)
    local actionList = Instance.new("Frame"); actionList.BackgroundTransparency = 1; actionList.Position = UDim2.new(0, 12, 0, 64); actionList.Size = UDim2.new(1, -24, 0, 0); actionList.AutomaticSize = Enum.AutomaticSize.Y; actionList.Parent = actionBox; list(actionList, 5)
    local trialBox, stateBox, markerBox, reviewBox
    local function parseValue(typ, text)
        if typ == "number" then return tonumber(text) end
        if typ == "list" then local out = {}; for x in string.gmatch(text or "", "[^,]+") do table.insert(out, (string.gsub(x, "^%s*(.-)%s*$", "%1"))) end; return out end
        return text
    end
    local function renderActions()
        for _, c in ipairs(actionList:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end
        actionInputs = {}
        local t = testById(selectedId)
        local wanted = {}
        for _, id in ipairs((t and t.actions) or {}) do wanted[tostring(id)] = true end
        local actions = {}
        for _, candidate in ipairs(Lab.actions or {}) do
            if wanted[tostring(candidate.id)] then table.insert(actions, candidate) end
        end
        for _, a in ipairs(actions) do
            local row = Instance.new("Frame"); row.BackgroundTransparency = 1; row.Size = UDim2.new(1, 0, 0, (#(a.fields or {}) * 34) + 34); row.Parent = actionList
            local run = button(row, a.label or a.id, nil, a.risk == "read" and C.mintDark or C.panel, 190); run.Position = UDim2.new(0, 0, 0, 1)
            local inputs = {}; actionInputs[a.id] = inputs
            for i, f in ipairs(a.fields or {}) do local t = field(row, f.label or f.key, tostring(f.default or "")); t.Position = UDim2.new(0, 198, 0, 1 + (i - 1) * 34); t.Size = UDim2.new(1, -198, 0, 29); inputs[f.key] = {box=t, spec=f} end
            run.Activated:Connect(function()
                local args = {}; for key, item in pairs(inputs) do args[key] = parseValue(item.spec.type, item.box.Text) end
                local read = a.risk == "read"; local v = safeView()
                if not read and not v.activeTrial then refs.status.Text = "Start a trial before a mutation action"; return end
                local invoke = function()
                    pcall(Lab.setNotes, notes and notes.Text or "")
                    local ok, success, msg = pcall(function() return Lab.command(a.id, args) end)
                    local now = safeView()
                    refs.status.Text = ok and (tostring(msg or now.message or (success and "action sent" or "action rejected"))) or "action failed: " .. tostring(success)
                end
                if read then invoke() else confirm("This action is marked " .. tostring(a.risk) .. ". It may change live state. Continue only if the prerequisites and budget are correct.", invoke) end
            end)
        end
    end
    -- Render once the selected test is known below; this avoids putting every mutation action in every test.

    local selected = label(detail, "Select a test from the plan", 18, C.text, true); selected.Size = UDim2.new(1, 0, 0, 28)
    local desc = label(detail, "", 12, C.muted, false); desc.Size = UDim2.new(1, 0, 0, 0)
    local info = frame(detail, C.panel2, UDim2.new(1, 0, 0, 0)); info.AutomaticSize = Enum.AutomaticSize.Y; list(info, 4)
    local function infoLine(caption, value) local l = label(info, caption .. "\n" .. (value or "—"), 11, C.text, false); l.Size = UDim2.new(1, -20, 0, 0); l.Position = UDim2.new(0, 10, 0, 0); return l end
    local goalLine, prereqLine, stepsLine, evidenceLine, limitsLine
    local function renderSelected()
        local t = testById(selectedId); if not t then selected.Text = "Select a test from the plan"; desc.Text = ""; return end
        selected.Text = tostring(t.title or t.name or t.id); desc.Text = tostring(t.goal or t.description or "")
        goalLine.Text = "GOAL\n" .. tostring(t.goal or t.description or "—"); prereqLine.Text = "PREREQUISITES\n" .. arr(t.prerequisites or t.prereqs or {}); stepsLine.Text = "STEPS\n" .. arr(t.steps or {}); evidenceLine.Text = "EXPECTED EVIDENCE\n" .. arr(t.evidence or t.expectedEvidence or {}); limitsLine.Text = "LIMITS\n" .. arr(t.limits or {})
        renderActions()
    end
    goalLine = infoLine("GOAL", ""); prereqLine = infoLine("PREREQUISITES", ""); stepsLine = infoLine("STEPS", ""); evidenceLine = infoLine("EXPECTED EVIDENCE", ""); limitsLine = infoLine("LIMITS", "")

    trialBox = frame(detail, C.panel2, UDim2.new(1, 0, 0, 0)); trialBox.AutomaticSize = Enum.AutomaticSize.Y; trialBox.LayoutOrder = 20; list(trialBox, 6)
    local trialTitle = label(trialBox, "TRIAL", 13, C.mint, true); trialTitle.Size = UDim2.new(1, -20, 0, 20); trialTitle.Position = UDim2.new(0, 10, 0, 8)
    local initialViewForFields = safeView()
    experiment = field(trialBox, "Experiment label (e.g. mxssyo-world9-shop)", tostring(initialViewForFields.experiment or "")); experiment.Position = UDim2.new(0, 10, 0, 34); experiment.Size = UDim2.new(1, -20, 0, 30)
    notes = field(trialBox, "Operator notes; do not include secrets", tostring(initialViewForFields.notes or "")); notes.Position = UDim2.new(0, 10, 0, 68); notes.Size = UDim2.new(1, -20, 0, 30)
    local preserve = button(trialBox, "", function()
        local current = safeView().preserveLanes == true; local desired = not current
        local ok, success, msg = pcall(function() return Lab.setPreserve(desired) end)
        refs.status.Text = ok and tostring(msg or (success and (desired and "lane protection enabled" or "lane protection disabled") or "lane protection rejected")) or tostring(success)
    end, C.panel, 0); preserve.Position = UDim2.new(0, 10, 0, 102); preserve.Size = UDim2.new(1, -20, 0, 28); preserve.TextXAlignment = Enum.TextXAlignment.Left
    local trialBtns = Instance.new("Frame"); trialBtns.BackgroundTransparency = 1; trialBtns.Size = UDim2.new(1, -20, 0, 34); trialBtns.Position = UDim2.new(0, 10, 0, 136); trialBtns.Parent = trialBox
    local start = button(trialBtns, "START TRIAL", function() if not selectedId then refs.status.Text = "Select a test first"; return end; pcall(Lab.setExperiment, experiment.Text); pcall(Lab.setNotes, notes.Text); pcall(Lab.startTrial); refs.status.Text = "trial started" end, C.mintDark, 112)
    local survey = button(trialBtns, "SURVEY", function() local ok, msg = pcall(Lab.survey); refs.status.Text = ok and tostring(msg or "survey complete") or tostring(msg) end, C.panel, 76); survey.Position = UDim2.new(0, 120, 0, 0)
    markerBox = frame(detail, C.panel2, UDim2.new(1, 0, 0, 0)); markerBox.AutomaticSize = Enum.AutomaticSize.Y; markerBox.LayoutOrder = 30; list(markerBox, 6)
    label(markerBox, "EVIDENCE MARKERS", 13, C.mint, true).Position = UDim2.new(0, 10, 0, 8)
    local markerBtns = Instance.new("Frame"); markerBtns.BackgroundTransparency = 1; markerBtns.Size = UDim2.new(1, -20, 0, 34); markerBtns.Position = UDim2.new(0, 10, 0, 30); markerBtns.Parent = markerBox
    local function mark(phase) return function() local v = safeView(); if not v.activeTrial then refs.status.Text = "Start a trial first"; return end; pcall(Lab.setNotes, notes.Text); local ok, msg = pcall(Lab.mark, phase); refs.status.Text = ok and tostring(msg or (phase .. " recorded")) or tostring(msg) end end
    button(markerBtns, "BASELINE", mark("before"), C.panel, 88); local ab = button(markerBtns, "ACTION", mark("action"), C.panel, 78); ab.Position = UDim2.new(0, 94, 0, 0); local af = button(markerBtns, "AFTER", mark("after"), C.panel, 74); af.Position = UDim2.new(0, 178, 0, 0); local no = button(markerBtns, "NOTE", mark("note"), C.panel, 66); no.Position = UDim2.new(0, 258, 0, 0)
    local review = Instance.new("Frame"); review.BackgroundTransparency = 1; review.Size = UDim2.new(1, -20, 0, 72); review.Position = UDim2.new(0, 10, 0, 70); review.Parent = markerBox
    local reviewLabel = label(review, "Operator review (does not certify game state):", 11, C.muted, false); reviewLabel.Position = UDim2.new(0, 0, 0, 0); reviewLabel.Size = UDim2.new(1, 0, 0, 24)
    local reviewButtons = Instance.new("Frame"); reviewButtons.BackgroundTransparency = 1; reviewButtons.Position = UDim2.new(0, 0, 0, 28); reviewButtons.Size = UDim2.new(1, 0, 0, 40); reviewButtons.Parent = review
    local reviewGrid = Instance.new("UIGridLayout"); reviewGrid.CellSize = UDim2.new(0, 84, 0, 30); reviewGrid.CellPadding = UDim2.new(0, 5, 0, 5); reviewGrid.Parent = reviewButtons
    local statuses = {"OBSERVED", "PASS", "FAIL", "BLOCKED", "NOT_RUN"}
    for _, st in ipairs(statuses) do button(reviewButtons, st, function() if not selectedId then return end; pcall(Lab.setNotes, notes.Text); local ok, success, msg = pcall(function() return Lab.review(st) end); local now = safeView(); refs.status.Text = ok and tostring(msg or now.message or (success and ("review " .. st) or "review rejected")) or tostring(success) end, st == "PASS" and C.mintDark or (st == "FAIL" and C.red or C.panel), 78) end

    stateBox = frame(detail, C.panel2, UDim2.new(1, 0, 0, 0)); stateBox.AutomaticSize = Enum.AutomaticSize.Y; stateBox.LayoutOrder = 50; list(stateBox, 4)
    local stateTitle = label(stateBox, "LIVE VIEW", 13, C.mint, true); stateTitle.Position = UDim2.new(0, 10, 0, 8)
    refs.status = label(stateBox, "connecting…", 11, C.muted, false); refs.status.Position = UDim2.new(0, 10, 0, 30); refs.status.Size = UDim2.new(1, -20, 0, 18)
    refs.live = label(stateBox, "", 11, C.text, false); refs.live.Position = UDim2.new(0, 10, 0, 51); refs.live.Size = UDim2.new(1, -20, 0, 0)
    local exportBox = frame(detail, C.panel2, UDim2.new(1, 0, 0, 0)); exportBox.AutomaticSize = Enum.AutomaticSize.Y; exportBox.LayoutOrder = 60; list(exportBox, 6)
    label(exportBox, "EXPORT", 13, C.mint, true).Position = UDim2.new(0, 10, 0, 8)
    local exportBtns = Instance.new("Frame"); exportBtns.BackgroundTransparency = 1; exportBtns.Size = UDim2.new(1, -20, 0, 34); exportBtns.Position = UDim2.new(0, 10, 0, 30); exportBtns.Parent = exportBox
    local exportText = field(exportBox, "Selectable JSON fallback appears here after Copy"); exportText.Position = UDim2.new(0, 10, 0, 70); exportText.Size = UDim2.new(1, -20, 0, 70); exportText.MultiLine = true; exportText.TextWrapped = false; exportText.TextYAlignment = Enum.TextYAlignment.Top
    button(exportBtns, "SAVE", function() local ok, msg = pcall(Lab.save); refs.status.Text = ok and tostring(msg or "saved") or tostring(msg) end, C.mintDark, 76)
    local copy = button(exportBtns, "COPY", function() local ok, success, msg = pcall(Lab.copy); local rawOK, raw = pcall(Lab.exportJSON); if rawOK then exportText.Text = tostring(raw) end; refs.status.Text = ok and tostring(msg or safeView().message or (success and "copied" or "use JSON below")) or "clipboard unavailable; JSON below" end, C.panel, 76); copy.Position = UDim2.new(0, 82, 0, 0)
    local replay = button(exportBtns, "REPLAY (ISOLATED)", function() local ok, msg = pcall(Lab.replay); refs.status.Text = ok and tostring(msg or "synthetic replay complete") or tostring(msg) end, C.panel, 142); replay.Position = UDim2.new(0, 164, 0, 0)

    for _, t in ipairs(Lab.tests or {}) do
        local id = tostring(t.id); local b = button(listScroll, tostring(t.group or "NOW") .. "  /  " .. tostring(t.title or t.name or id), function() selectedId = id; pcall(Lab.selectTest, id); renderSelected(); refs.status.Text = "selected " .. id end, C.panel2, 0); b.Size = UDim2.new(1, 0, 0, 38); b.TextXAlignment = Enum.TextXAlignment.Left; b.TextWrapped = true
    end
    local initialView = safeView(); selectedId = initialView.selectedTestId or (Lab.tests and Lab.tests[1] and tostring(Lab.tests[1].id)); if selectedId then pcall(Lab.selectTest, selectedId) end; renderSelected()
    local function count(v)
        if type(v) ~= "table" then return 0 end
        local n = 0; for _ in pairs(v) do n = n + 1 end; return n
    end
    local function resultText(v)
        local r = (v.results or {})[selectedId or ""]
        if type(r) ~= "table" then return "NOT_RUN" end
        return tostring(r.status or "NOT_RUN")
    end
    task.spawn(function()
        while alive and gui.Parent do
            task.wait(1)
            local v = safeView(); if not alive or not gui.Parent then break end
            local s = v.summary or {}; local snap = v.snapshot or {}; local shop = snap.shop; local drops = snap.drops or snap.currentDrops; local pos = snap.position
            local posText = type(pos) == "table" and (tostring(pos.X or pos.x or "?") .. "," .. tostring(pos.Z or pos.z or "?")) or tostring(pos or "—")
            local shopOffers = type(shop) == "table" and (shop.Offers or shop.offers) or nil
            local offerNames = {}; for _, offer in pairs(type(shopOffers) == "table" and shopOffers or {}) do offerNames[#offerNames + 1] = tostring(offer) end
            local shopText = type(shop) == "table" and (tostring(count(shopOffers)) .. " offer(s): " .. table.concat(offerNames, ", ")) or tostring(shop and "available" or "—")
            local dropText = type(drops) == "table" and tostring(count(drops)) .. " current" or tostring(drops and "visible" or "—")
            local active = v.activeTrial and (tostring(v.activeTrial.phase or "active") .. " / " .. tostring(v.activeTrial.id or "")) or "none"
            local err = s.saveError and (" saveError=" .. tostring(s.saveError)) or ""
            local clock = snap.dropState or {}; local signals = snap.swordSignals or {}; local lastSignal
            for _, signal in pairs(signals) do if signal.kind == "Impact" then lastSignal = signal end end
            local dropInfo = "Sword state: world " .. tostring(clock.World or "?") .. " / " .. tostring(clock.SwordName or "?") .. " / " .. tostring(clock.Phase or "?")
            if lastSignal and type(lastSignal.position) == "table" then local p = lastSignal.position; dropInfo = dropInfo .. "\nLast impact: " .. tostring(p.x) .. ", " .. tostring(p.y) .. ", " .. tostring(p.z) .. " (world hint " .. tostring(lastSignal.singletonWorldHint or "?") .. ")" end
            local delta = v.lastDelta; local deltaText = ""
            if delta then local d = {}; for name, value in pairs(delta.stats or {}) do d[#d + 1] = tostring(name) .. " " .. tostring(value) end; deltaText = "\nLast observed deltas: " .. table.concat(d, ", ") .. "; pets +" .. tostring(#(delta.petsAdded or {})) .. " / -" .. tostring(#(delta.petsRemoved or {})) end
            refs.live.Text = statLine(v) .. "\nposition: " .. posText .. "  •  shop: " .. shopText .. "  •  drops: " .. dropText .. "  •  players: " .. tostring(#(v.players or {})) .. "\n" .. dropInfo .. "\ntrial: " .. active .. "  •  selected result: " .. resultText(v) .. "\nevents " .. tostring(s.events or 0) .. "  records " .. tostring(s.records or 0) .. "  dropped " .. tostring(s.dropped or 0) .. "  truncations " .. tostring(s.truncations or 0) .. "  saved parts " .. tostring(s.segments or 0) .. err .. deltaText .. "\nmessage: " .. tostring(v.message or "ready")
            preserve.Text = "Preserve cleared lanes: " .. (v.preserveLanes and "ON (protected)" or "OFF")
            if v.message and v.message ~= "" then refs.status.Text = tostring(v.message) end
        end
    end)
    return gui
end

buildUI(Lab)

return Lab
