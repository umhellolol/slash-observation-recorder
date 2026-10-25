-- Slash Control agent 0.1.0. Local connection + read-only Prismatic monitoring.
local env = type(getgenv) == "function" and getgenv() or _G
local old = env.__SlashControlAgent
-- An explicit reload reconnects cleanly, while fencing the previous loop first.
if type(old) == "table" and not old.closed and type(old.stop) == "function" then pcall(old.stop, "Reconnecting…") end
if type(old) == "table" and old.gui then pcall(function() old.gui:Destroy() end) end
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Http = game:GetService("HttpService")
local Run = game:GetService("RunService")
assert(Run:IsClient() and game.PlaceId == 101558013317432, "Join Slash before connecting this agent.")
local player = assert(Players.LocalPlayer, "Wait for your character to load, then reconnect.")
local config = env.SlashController or {}
local url = tostring(config.url or ""):gsub("/$", "")
assert(url:match("^http://127%.0%.0%.1:%d+$") or url:match("^http://localhost:%d+$"), "Copy a fresh connection script from Slash Control.")
assert(type(config.pairingKey) == "string" and #config.pairingKey >= 32, "Copy a fresh connection script from Slash Control.")
local request = type(request) == "function" and request or type(http_request) == "function" and http_request
    or type(syn) == "table" and type(syn.request) == "function" and syn.request
    or type(http) == "table" and type(http.request) == "function" and http.request
assert(type(request) == "function", "This environment has no supported HTTP request function.")
local Agent = { version = "0.1.0", closed = false, mode = "stopped", revision = 0, connected = false,
    status = "Connecting to Slash Control…", lastResult = "", id = Http:GenerateGUID(false), sequence = 1 }
env.__SlashControlAgent = Agent
local credential, epoch, generation, pending
local leaseUntil, retryAt, nextProbeAt = 0, 0, 0
local settings = { monitorPrismatic = true }
local shopRemote, shopConnection, shop, receivedShopAt
local targetPrice, lastProbeAt = nil, -math.huge
local badge, badgeLabel
local function stamp() return DateTime.now():ToIsoDate() end
local function serverNow() local ok, v = pcall(function() return workspace:GetServerTimeNow() end); return ok and v or nil end
local function child(root, name) return root and root:FindFirstChild(name) end
local function value(root, name) local v = child(root, name); return v and v:IsA("ValueBase") and v.Value or nil end
local function finite(n) return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge and n or nil end
local function currentWorld()
    return finite(player:GetAttribute("CurrentWorld")) or finite(value(child(player, "PlayerStats"), "CurrentWorld"))
end
local function shopFacts()
    local now = serverNow()
    local fresh = shop and receivedShopAt and os.clock() - receivedShopAt <= 40
    if fresh and finite(shop.EndsAt) and now and now >= shop.EndsAt then fresh = false end
    local available
    if fresh and type(shop.Offers) == "table" then
        available = false
        for slot, id in pairs(shop.Offers) do
            local purchased = type(shop.Purchased) == "table" and (shop.Purchased[slot] or shop.Purchased[tostring(slot)] or shop.Purchased[tonumber(slot)])
            if id == "PrismaticCosmos" and not purchased then available = true end
        end
    end
    return { available = available, price = targetPrice, window = fresh and finite(shop.Window) or nil, endsAt = fresh and finite(shop.EndsAt) or nil }
end
local function effectiveMode()
    if Agent.closed or os.clock() >= leaseUntil then return "stopped" end
    return Agent.mode
end
function Agent.snapshot()
    local stats, pstats = child(player, "NumericStats"), child(player, "PlayerStats")
    local mode, facts = effectiveMode(), shopFacts()
    local task = mode == "running" and (settings.monitorPrismatic and "Watching Prismatic Cosmos" or "Monitoring is switched off")
        or mode == "paused" and "Paused" or "Stopped"
    if mode == "running" and facts.available then task = "Prismatic Cosmos is available — buy in game" end
    return { world = currentWorld(), maxWorldUnlocked = finite(player:GetAttribute("MaxWorldUnlocked")) or finite(value(pstats, "MaxWorldUnlocked")),
        stats = { Crystals = finite(value(stats, "Crystals")), Wins = finite(value(stats, "Wins")), Power = finite(value(stats, "Power")), Rebirths = finite(value(stats, "Rebirths")) },
        charmOwned = finite(value(child(player, "OwnedCharms"), "PrismaticCosmos")), shop = facts,
        currentTask = task, lastResult = Agent.lastResult, effectiveMode = mode, observedAt = stamp(), bindings = { shopRead = shopRemote ~= nil } }
end
local function bindShop()
    local remote = child(child(RS, "PunchEscapeRemotes"), "CharmShopRequest")
    if remote and not remote:IsA("RemoteEvent") then remote = nil end
    if remote ~= shopRemote then
        if shopConnection then shopConnection:Disconnect(); shopConnection = nil end
        shopRemote = remote
        if remote then
            shopConnection = remote.OnClientEvent:Connect(function(state)
                if Agent.closed or type(state) ~= "table" then return end
                shop = state; receivedShopAt = os.clock()
                if shopFacts().available then Agent.lastResult = "Prismatic Cosmos found. Automatic purchasing is not enabled." end
            end)
        end
    end
    if not targetPrice then
        local module = child(RS, "PunchEscapeCharmConfig")
        if module then
            local ok, c = pcall(require, module)
            if ok and type(c) == "table" and c.ById and c.ById.PrismaticCosmos then targetPrice = finite(c.ById.PrismaticCosmos.Price) end
        end
    end
end
local function badgeText()
    if badgeLabel then badgeLabel.Text = Agent.status end
end
function Agent.stop(reason)
    Agent.closed = true; Agent.connected = false; Agent.mode = "stopped"; leaseUntil = 0
    if shopConnection then shopConnection:Disconnect(); shopConnection = nil end
    Agent.status = reason or "Stopped. Run the connection script to reconnect."
    badgeText()
end
local function post(route, body, token)
    local headers = { ["Content-Type"] = "application/json" }
    if token then headers.Authorization = "Bearer " .. token end
    local ok, response = pcall(request, { Url = url .. route, Method = "POST", Headers = headers, Body = body, Timeout = 4 })
    if not ok or type(response) ~= "table" then return nil, 0 end
    local status = tonumber(response.StatusCode or response.Status) or 0
    local decodedOK, decoded = pcall(function() return Http:JSONDecode(response.Body or "") end)
    if not decodedOK or type(decoded) ~= "table" then return nil, status end
    return decoded, status
end
local function hello()
    local body = Http:JSONEncode({ protocol = 1, pairingKey = config.pairingKey, agentInstanceId = Agent.id,
        identity = { userId = player.UserId, username = player.Name, placeId = game.PlaceId, placeVersion = game.PlaceVersion, jobId = game.JobId },
        capabilities = { http = true, shopRead = shopRemote ~= nil, agentVersion = Agent.version }, snapshot = Agent.snapshot() })
    local reply, status = post("/agent/hello", body)
    if reply and status == 200 and type(reply.sessionToken) == "string" and reply.epoch and reply.controllerGeneration then
        credential, epoch, generation = reply.sessionToken, reply.epoch, reply.controllerGeneration
        Agent.connected = true; Agent.status = "Connected • stopped"; retryAt = 0
        return true
    end
    if status == 400 or status == 401 or status == 403 or status == 409 then Agent.stop("Connection rejected. Copy a fresh script from the app."); return false end
    Agent.status = "Waiting for Slash Control…"; retryAt = os.clock() + 4
    return false
end
local function probeShop()
    if effectiveMode() ~= "running" or not settings.monitorPrismatic or os.clock() < nextProbeAt or os.clock() - lastProbeAt < 2 then return end
    if not shopRemote then Agent.lastResult = "Waiting for the game's shop connection."; nextProbeAt = os.clock() + 10; return end
    lastProbeAt = os.clock(); nextProbeAt = lastProbeAt + 10
    local ok = pcall(function() shopRemote:FireServer("Get") end)
    if not ok then Agent.lastResult = "Couldn't read the shop yet. Will try again."; return end
    local now = serverNow()
    local delay = shop and finite(shop.EndsAt) and now and math.min(30, math.max(2, shop.EndsAt - now + 0.5)) or 10
    nextProbeAt = lastProbeAt + delay
end
function Agent.tick()
    if Agent.closed then return end
    bindShop()
    if os.clock() < retryAt then badgeText(); return end
    if not credential and not hello() then badgeText(); return end
    if not pending then
        pending = { seq = Agent.sequence, body = Http:JSONEncode({ agentInstanceId = Agent.id, epoch = epoch, controllerGeneration = generation,
            seq = Agent.sequence, snapshot = Agent.snapshot(), controlAck = { revision = Agent.revision, mode = effectiveMode(),
                outcome = effectiveMode() == Agent.mode and "APPLIED" or "UNKNOWN", message = "Local monitoring state observed." } }) }
    end
    local sentAt = os.clock()
    local reply, status = post("/agent/exchange", pending.body, credential)
    if status == 401 or status == 403 or status == 409 then Agent.stop("Connection changed. Copy and run a fresh script from the app."); return end
    if not reply or status ~= 200 then
        Agent.connected = false; Agent.status = "Controller unavailable • monitoring held"; retryAt = os.clock() + 2; badgeText(); return
    end
    if reply.epoch ~= epoch or reply.controllerGeneration ~= generation or reply.ackSeq ~= pending.seq then
        Agent.stop("Connection changed. Run a fresh script from the app."); return
    end
    if type(reply.control) ~= "table" or type(reply.control.revision) ~= "number" or not ({running=true,paused=true,stopped=true})[reply.control.mode] then
        Agent.stop("Unexpected controller response. Reconnect from the app."); return
    end
    Agent.sequence = pending.seq + 1; pending = nil; retryAt = 0; Agent.connected = true
    leaseUntil = sentAt + math.min(6, math.max(0, tonumber(reply.leaseMs) or 0) / 1000)
    if reply.control.revision < Agent.revision then Agent.stop("Outdated control response. Reconnect from the app."); return end
    if reply.control.revision ~= Agent.revision or reply.control.mode ~= Agent.mode then nextProbeAt = 0 end
    Agent.revision = reply.control.revision; Agent.mode = reply.control.mode
    settings.monitorPrismatic = type(reply.settings) == "table" and reply.settings.monitorPrismatic == true
    Agent.status = effectiveMode() == "running" and (settings.monitorPrismatic and "Connected • watching Prismatic" or "Connected • watch switched off")
        or effectiveMode() == "paused" and "Connected • paused" or "Connected • stopped"
    probeShop(); badgeText()
end
-- Tiny optional status panel; the desktop app holds the actual controls.
local function createBadge()
    local gui = Instance.new("ScreenGui"); gui.Name = "SlashControlAgent"; gui.ResetOnSpawn = false
    gui.DisplayOrder = 2147483647; gui.IgnoreGuiInset = true; Agent.gui = gui
    local hosts = {}
    pcall(function() if type(gethui) == "function" then hosts[#hosts + 1] = gethui() end end)
    pcall(function() hosts[#hosts + 1] = game:GetService("CoreGui") end)
    hosts[#hosts + 1] = player:WaitForChild("PlayerGui")
    for _, host in ipairs(hosts) do local ok = pcall(function() gui.Parent = host end); if ok and gui.Parent == host then break end end
    local frame = Instance.new("Frame"); frame.Name = "AgentStatus"; frame.Size = UDim2.fromOffset(280, 66); frame.Position = UDim2.fromOffset(18, 70)
    frame.BackgroundColor3 = Color3.fromRGB(15, 25, 32); frame.BorderSizePixel = 0; frame.Parent = gui; badge = frame
    local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 8); corner.Parent = frame
    local label = Instance.new("TextLabel"); label.BackgroundTransparency = 1; label.Position = UDim2.fromOffset(10, 7); label.Size = UDim2.new(1, -20, 0, 28)
    label.Font = Enum.Font.Gotham; label.TextSize = 11; label.TextWrapped = true; label.TextColor3 = Color3.fromRGB(224, 239, 236); label.Parent = frame; badgeLabel = label
    local hide = Instance.new("TextButton"); hide.Text = "Hide"; hide.Size = UDim2.fromOffset(80, 23); hide.Position = UDim2.fromOffset(10, 37); hide.Parent = frame
    local stop = Instance.new("TextButton"); stop.Text = "Disconnect"; stop.Size = UDim2.fromOffset(100, 23); stop.Position = UDim2.fromOffset(100, 37); stop.Parent = frame
    for _, b in ipairs({hide, stop}) do b.Font = Enum.Font.Gotham; b.TextSize = 11; b.BackgroundColor3 = Color3.fromRGB(29, 47, 55); b.TextColor3 = Color3.fromRGB(224, 239, 236); b.BorderSizePixel = 0 end
    hide.Activated:Connect(function() frame.Visible = false end)
    stop.Activated:Connect(function() Agent.stop() end)
    gui.Destroying:Connect(function() Agent.stop() end)
    badgeText()
end
pcall(createBadge)
function Agent.getState() return { mode = effectiveMode(), connected = Agent.connected, closed = Agent.closed, status = Agent.status, revision = Agent.revision } end
task.spawn(function()
    while not Agent.closed do
        local ok = pcall(Agent.tick)
        if not ok then Agent.connected = false; leaseUntil = 0; Agent.status = "Connection paused. Check Slash Control."; badgeText() end
        task.wait(2)
    end
end)
return Agent
