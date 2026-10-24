-- Slash Observation Recorder 0.2.0
-- Run through the user's client Lua environment, or as a Studio LocalScript.
-- Passive Roblox observations only. Optional file/clipboard export is capability-tested.
-- No gameplay remote calls, hooks, movement, purchases, or credential handling.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Http = game:GetService("HttpService")
local Prompts = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
assert(RunService:IsClient(), "Run the recorder in the Roblox client, not a server context.")
assert(game.PlaceId == 101558013317432 or RunService:IsStudio(), "Recorder stopped: this is not the expected Slash place.")
local player = Players.LocalPlayer
assert(player, "LocalPlayer is unavailable. Join the game before launching the recorder.")
local playerGui = player:WaitForChild("PlayerGui", 10)
assert(playerGui, "PlayerGui was not ready within ten seconds. Retry after the game loads.")
if playerGui:FindFirstChild("SlashObservationRecorder") then
    warn("Slash recorder already installed. Stop and close its existing panel before reloading.")
    return
end

local VERSION = "0.2.0"
local MAX_RECORDS, MAX_BYTES = 1000, 4000000
local rows, connections, bindings = {}, {}, {}
local seq, bytes, dropped, truncations = 0, 0, 0, 0
local running, lastState = true, nil
local incomingEvents, lastHeartbeat = 0, os.clock()
-- These optional capabilities belong to the user's runtime. Never assume they exist.
local fileWriter = type(writefile) == "function" and writefile or nil
local fileReader = type(readfile) == "function" and readfile or nil
local clipboardWriter = type(setclipboard) == "function" and setclipboard or (type(toclipboard) == "function" and toclipboard or nil)
local session = {
    id = Http:GenerateGUID(false), account = player.Name, userId = player.UserId,
    jobId = game.JobId, placeId = game.PlaceId, placeVersion = game.PlaceVersion,
    startedAt = DateTime.now():ToIsoDate(), recorderVersion = VERSION,
    mode = "passive-client", provenance = "replicated observations; server acceptance unverified",
    capabilities = { fileWrite = fileWriter ~= nil, fileRead = fileReader ~= nil, clipboard = clipboardWriter ~= nil },
}
local coverage = {}
local statusLabel
local function health()
    local count = 0
    for _, value in pairs(coverage) do if value == "subscribed" then count = count + 1 end end
    return { running = running, incomingEvents = incomingEvents, subscribedRoutes = count, totalRoutes = 8,
        numericStatsVisible = player:FindFirstChild("NumericStats") ~= nil,
        swordInventoryVisible = player:FindFirstChild("SwordUnlocks") ~= nil,
        charmInventoryVisible = player:FindFirstChild("OwnedCharms") ~= nil,
        studio = RunService:IsStudio(), liveServerIdentityVisible = game.JobId ~= "",
        retainedRecords = #rows, droppedRecords = dropped, truncations = truncations,
        deliveryStatus = incomingEvents > 0 and "events received; interpretation unverified" or "subscribed routes do not yet prove event delivery" }
end
local function safe(value)
    local budget, seen = 2000, {}
    local function visit(v, depth)
        budget = budget - 1
        if budget < 0 or depth > 8 then
            truncations = truncations + 1
            return { omitted = "serialization limit" }
        end
        local kind = typeof(v)
        if kind == "nil" then return { type = "nil" } end
        if kind == "string" then
            if #v > 16000 then truncations = truncations + 1; return { text = string.sub(v, 1, 16000), truncated = true } end
            return v
        end
        if kind == "boolean" then return v end
        if kind == "number" then
            if v ~= v or v == math.huge or v == -math.huge then return tostring(v) end
            return v
        end
        if kind == "Instance" then return { type = v.ClassName, path = v:GetFullName() } end
        if kind == "Vector3" then return { type = kind, x = v.X, y = v.Y, z = v.Z } end
        if kind == "CFrame" then return { type = kind, components = { v:GetComponents() } } end
        if kind == "table" then
            if seen[v] then return { omitted = "cycle" } end
            seen[v] = true
            local result, count = {}, 0
            for k, item in pairs(v) do
                count = count + 1
                if count > 300 then result.__truncated = true; truncations = truncations + 1; break end
                result[tostring(k)] = visit(item, depth + 1)
            end
            seen[v] = nil
            return result
        end
        return { type = kind, text = tostring(v) }
    end
    return visit(value, 0)
end
local function clock()
    local ok, value = pcall(function() return workspace:GetServerTimeNow() end)
    return ok and value or nil
end
local function record(kind, data)
    if not running and kind ~= "stopped" then return end
    seq = seq + 1
    local row = { seq = seq, kind = kind, utc = DateTime.now():ToIsoDate(), monotonic = os.clock(), serverTime = clock(), data = safe(data) }
    local encoded = Http:JSONEncode(row)
    if #encoded > MAX_BYTES then dropped = dropped + 1; return end
    table.insert(rows, { value = row, size = #encoded })
    bytes = bytes + #encoded
    while #rows > MAX_RECORDS or bytes > MAX_BYTES do
        bytes = bytes - rows[1].size; table.remove(rows, 1); dropped = dropped + 1
    end
    if statusLabel then statusLabel.Text = #rows .. " records / " .. dropped .. " dropped / " .. truncations .. " truncations" end
end
local function resolve(root, path)
    local item = root
    for _, name in ipairs(path) do item = item and item:FindFirstChild(name); if not item then return nil end end
    return item
end
local folders = { "NumericStats", "PlayerStats", "SwordUnlocks", "OwnedCharms", "EquippedCharms", "PetInventory", "OwnedFists" }
local playerAttrs = { "CurrentWorld", "MaxWorldUnlocked", "EquippedSword", "PetInventoryCapacity", "PunchEscapePolicyReady", "PunchEscapePaidTradingAllowed", "PunchEscapePaidRandomAllowed", "AdminBladeCutsceneActive" }
local function tree(root)
    if not root then return { observed = false, reason = "path missing" } end
    local count = 0
    local function walk(item, depth)
        count = count + 1
        local result = { name = item.Name, class = item.ClassName, attributes = item:GetAttributes() }
        if item:IsA("ValueBase") then result.value = item.Value end
        if depth >= 3 then
            if #item:GetChildren() > 0 then result.childrenOmitted = true; truncations = truncations + 1 end
            return result
        end
        local children = item:GetChildren()
        table.sort(children, function(a, b) return a.Name < b.Name end)
        result.children = {}
        for _, child in ipairs(children) do
            if count >= 600 then result.childrenOmitted = true; truncations = truncations + 1; break end
            table.insert(result.children, walk(child, depth + 1))
        end
        return result
    end
    return { observed = true, tree = walk(root, 0) }
end
local function snapshot()
    local state = { player = {}, folders = {}, replicated = {} }
    for _, name in ipairs(playerAttrs) do
        local value = player:GetAttribute(name)
        state.player[name] = value == nil and { observed = false } or { observed = true, value = value }
    end
    for _, name in ipairs(folders) do state.folders[name] = tree(player:FindFirstChild(name)) end
    for _, name in ipairs({ "SwordDropState", "AdminBladeState" }) do
        local item = RS:FindFirstChild(name)
        state.replicated[name] = item and { observed = true, attributes = item:GetAttributes() } or { observed = false }
    end
    state.characterPresent = player.Character ~= nil
    local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    if humanoid then state.health = humanoid.Health end
    -- Geometry absence is intentionally not used as cleared-lane evidence.
    return safe(state)
end
local routes = {
    { "PunchEscapeRemotes", "Effects" },
    { "PunchEscapeRemotes", "TradeRemote" },
    { "PunchEscapeRemotes", "SwordDropEvent" },
    { "PunchEscapeRemotes", "CharmShopRequest" },
    { "PunchEscapeAdminRemotes", "CharmShowerVisuals" },
    { "PunchEscapeAdminBladeRemotes", "Event" },
    { "PetInventoryResult" }, { "LuckyBlockOpenResult" },
}
local function refreshBindings()
    for _, route in ipairs(routes) do
        local key = "ReplicatedStorage." .. table.concat(route, ".")
        local item = resolve(RS, route)
        if bindings[key] and bindings[key].instance ~= item then
            bindings[key].connection:Disconnect(); bindings[key] = nil
            record("coverage", { path = key, status = "binding removed or replaced" })
        end
        if item and item:IsA("RemoteEvent") then
            coverage[key] = "subscribed"
            if not bindings[key] then
                local connection = item.OnClientEvent:Connect(function(...)
                    incomingEvents = incomingEvents + 1
                    local args = table.pack(...)
                    record("incoming-event", { path = key, args = args })
                    -- Event-time state may precede inventory replication. Poll snapshots provide later evidence.
                    record("event-snapshot", { path = key, state = snapshot() })
                end)
                bindings[key] = { instance = item, connection = connection }
                record("coverage", { path = key, status = "subscribed; earlier events not captured" })
            end
        else
            coverage[key] = item and "wrong class" or "not visible"
        end
    end
end

local gui = Instance.new("ScreenGui")
gui.Name = "SlashObservationRecorder"; gui.ResetOnSpawn = false; gui.Parent = playerGui
local frame = Instance.new("Frame"); frame.Size = UDim2.fromOffset(350, 306); frame.Position = UDim2.new(0, 12, 1, -322)
frame.BackgroundColor3 = Color3.fromRGB(20, 33, 41); frame.Parent = gui
local function text(class, label, x, y, w, h)
    local item = Instance.new(class); item.Position = UDim2.fromOffset(x, y); item.Size = UDim2.fromOffset(w, h)
    item.BackgroundColor3 = Color3.fromRGB(36, 57, 66); item.TextColor3 = Color3.fromRGB(238, 244, 241)
    item.TextSize = 13; item.Font = Enum.Font.Code; item.Text = label; item.Parent = frame
    return item
end
text("TextLabel", "SLASH / PASSIVE OBSERVER", 8, 8, 334, 24)
local label = text("TextBox", "CAPTURE CHECK / run-001", 8, 38, 334, 28); label.ClearTextOnFocus = false
statusLabel = text("TextLabel", "Starting...", 8, 72, 334, 24)
local function marker(kind)
    record(kind, { label = label.Text, state = snapshot() })
end
local before = text("TextButton", "Before", 8, 104, 105, 30)
local action = text("TextButton", "Action", 121, 104, 105, 30)
local after = text("TextButton", "After", 234, 104, 108, 30)
before.Activated:Connect(function() marker("before") end)
action.Activated:Connect(function() marker("action") end)
after.Activated:Connect(function() marker("after") end)
local exportButton = text("TextButton", "Export JSON", 8, 142, 160, 30)
local stopButton = text("TextButton", "Stop", 180, 142, 162, 30)
local saveButton = text("TextButton", "Save file", 8, 180, 160, 30)
local copyButton = text("TextButton", "Copy JSON", 180, 180, 162, 30)
local checkButton = text("TextButton", "Capture diagnostic", 8, 218, 334, 30)
local message = text("TextLabel", "No gameplay requests. First: diagnostic, wait, export.", 8, 256, 334, 42)
message.TextWrapped = true
local exportFrame = Instance.new("Frame"); exportFrame.Size = UDim2.new(0.8, 0, 0.65, 0); exportFrame.Position = UDim2.fromScale(0.1, 0.1)
exportFrame.BackgroundColor3 = frame.BackgroundColor3; exportFrame.Visible = false; exportFrame.Parent = gui
local close = Instance.new("TextButton"); close.Size = UDim2.new(1, 0, 0, 32); close.Text = "Close export (select text below, Ctrl+A, Ctrl+C)"; close.Parent = exportFrame
local output = Instance.new("TextBox"); output.Size = UDim2.new(1, -16, 1, -48); output.Position = UDim2.fromOffset(8, 40)
output.MultiLine = true; output.ClearTextOnFocus = false; output.TextEditable = false
output.TextXAlignment = Enum.TextXAlignment.Left; output.TextYAlignment = Enum.TextYAlignment.Top
output.TextSize = 12; output.Font = Enum.Font.Code; output.TextWrapped = true; output.Parent = exportFrame
close.Activated:Connect(function() exportFrame.Visible = false end)
local function exportJSON()
    local values = {}; for _, row in ipairs(rows) do table.insert(values, row.value) end
    local payload = { schemaVersion = 1, kind = "slash-recorder", session = session, exportedAt = DateTime.now():ToIsoDate(),
        records = values, coverage = coverage, health = health(), droppedRecords = dropped, truncations = truncations,
        limitations = { "No outgoing calls captured", "No earlier events replayed", "Replication is client-visible evidence", "Periodic state sampling is every two seconds", "No complete multi-world drop enumeration" } }
    return Http:JSONEncode(payload)
end
exportButton.Activated:Connect(function() output.Text = exportJSON(); exportFrame.Visible = true end)
saveButton.Activated:Connect(function()
    if not fileWriter then message.Text = "writefile unavailable. Use Copy JSON or Export JSON."; return end
    local json = exportJSON()
    local filename = "slash-capture-" .. session.id .. "-" .. tostring(seq) .. ".json"
    local ok, err = pcall(fileWriter, filename, json)
    if not ok then message.Text = "File write failed: " .. tostring(err); return end
    if fileReader then
        local readOK, contents = pcall(fileReader, filename)
        if not readOK or contents ~= json then message.Text = "Write returned, but read-back verification failed. Use Copy JSON."; return end
        message.Text = "Verified file: " .. filename
    else
        message.Text = "Write returned: " .. filename .. ". Check your runtime workspace."
    end
end)
copyButton.Activated:Connect(function()
    if not clipboardWriter then message.Text = "Clipboard API unavailable. Use Export JSON."; return end
    local ok, err = pcall(clipboardWriter, exportJSON())
    message.Text = ok and "Copy call returned. Paste into a .json file and check it." or ("Copy failed: " .. tostring(err))
end)
checkButton.Activated:Connect(function()
    refreshBindings()
    record("diagnostic", { label = label.Text, health = health(), state = snapshot() })
    local h = health()
    message.Text = tostring(h.subscribedRoutes) .. "/8 routes; stats " .. tostring(h.numericStatsVisible) .. "; events " .. tostring(h.incomingEvents) .. ". Export to inspect."
end)
local function stop()
    if not running then return end
    record("stopped", { reason = "operator stopped" }); running = false
    for key, binding in pairs(bindings) do binding.connection:Disconnect(); coverage[key] = "disconnected: operator stopped" end
    for _, connection in ipairs(connections) do connection:Disconnect() end
    before.Active = false; action.Active = false; after.Active = false
    checkButton.Active = false
    stopButton.Text = "Close panel"
    message.Text = "Stopped. Export is still available. Close panel before reloading."
end
stopButton.Activated:Connect(function()
    if running then stop() else gui:Destroy() end
end)
table.insert(connections, Prompts.PromptTriggered:Connect(function(prompt, who)
    if who == nil or who == player then record("prompt-triggered", { prompt = prompt, holdDuration = prompt.HoldDuration, enabled = prompt.Enabled, maxDistance = prompt.MaxActivationDistance }) end
end))
table.insert(connections, player.CharacterAdded:Connect(function() record("character-added", {}) end))
record("started", session)
refreshBindings()
record("initial-snapshot", { state = snapshot() })
record("diagnostic", { label = "startup", health = health(), state = snapshot() })
task.spawn(function()
    while running and gui.Parent do
        local ok, err = pcall(function()
            refreshBindings()
            local state = snapshot()
            local encoded = Http:JSONEncode(state)
            if encoded ~= lastState then lastState = encoded; record("state-snapshot", { state = state }) end
            if os.clock() - lastHeartbeat >= 10 then
                lastHeartbeat = os.clock()
                record("heartbeat", health())
            end
        end)
        if not ok then record("observer-error", { message = tostring(err) }) end
        task.wait(2)
    end
    for _, binding in pairs(bindings) do binding.connection:Disconnect() end
    for _, connection in ipairs(connections) do connection:Disconnect() end
end)
-- Allows a future external transport adapter to hold a returned, observation-only API.
return { version = VERSION, health = health, mark = function(kind, markerLabel)
    assert(kind == "before" or kind == "action" or kind == "after" or kind == "note", "Unsupported marker kind")
    record(kind, { label = markerLabel or label.Text, state = snapshot() })
end, exportJSON = exportJSON, stop = stop }
