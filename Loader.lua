local env = type(getgenv) == "function" and getgenv() or _G
assert(type(env) == "table", "[Aether] Executor environment unavailable")

local active = env.A0_AETHER_LOADER_BUSY
if type(active) == "table" and type(active.Expires) == "number" and os.clock() < active.Expires then
    print("[Aether] Startup is already in progress (" .. tostring(active.Stage) .. ")")
    return
end

local options = type(env.A0_LOADER_OPTIONS) == "table" and env.A0_LOADER_OPTIONS or {}

local function limit(value, fallback, maximum)
    local number = tonumber(value) or fallback
    if number ~= number or math.abs(number) == math.huge then number = fallback end
    return math.clamp(number, 0, maximum)
end

local readinessLimit = limit(options.ReadinessTimeout, 120, 600)
local detectionLimit = limit(options.DetectionTimeout, 8, 30)

local state = {
    Stage = "setup",
    Status = "starting",
    Started = os.clock(),
}
state.Expires = state.Started + 10
env.A0_AETHER_LOADER_BUSY = state
env.A0_AETHER_LOADER_DIAGNOSTIC = state

local function fail(message)
    error(message, 0)
end

local function stage(name, seconds)
    state.Stage = name
    state.Expires = os.clock() + seconds
end

local function run()
    if type(loadstring) ~= "function" then fail("Executor loadstring is unavailable") end

    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")

    local defaultBase = "https://raw.githubusercontent.com/MeneSkidButBetterThanYou/AetherZero/refs/heads/main/"
    local dispatcherBase = "https://raw.githubusercontent.com/Uniquebobo/Aether-Zero/refs/heads/main/"
    local luaProtWrapper = [[^%s*loadstring%s*%(%s*game%s*:%s*HttpGet%s*%(%s*(["'])(https://luaprot%.net/api/v3/loaders/get/%d+)%1%s*%)%s*%)%s*%(%s*%)%s*;?%s*$]]

    local function slash(url)
        return url:sub(-1) == "/" and url or url .. "/"
    end

    local legacyBase = env.A0_AETHER_BASE_URL
    if type(legacyBase) == "string" and slash(legacyBase) == dispatcherBase then legacyBase = nil end
    local base = env.A0_AETHER_GAMES_BASE_URL or legacyBase or defaultBase
    if type(base) ~= "string" or not base:match("^https://[%w%-%.]+") then
        fail("Games base URL must be an HTTPS URL")
    end
    base = slash(base)
    state.GamesBaseURL = base

    local games = {
        Blair = { universe = 2239430935, file = "Blair.lua", places = { 6137321701 } },
        FTF = { universe = 372226183, file = "FTF.lua", places = { 893973440 } },
        VBL = { universe = 6931042565, file = "VBL.lua", places = { 73956553001240 } },
        VD = { universe = 6739698191, file = "VD.lua", places = { 93978595733734 } },
        GPO = {
            universe = 648454481,
            file = "GPO.lua",
            places = { 1730877806, 3978370137, 7465136166, 6360478118, 6811831486, 10218387007, 11424731604, 116480749200627 },
        },
        Rivals = {
            universe = 6035872082,
            file = "Rivals.lua",
            places = { 17625359962, 18126510175, 71874690745115, 117398147513099, 129604661913557, 133215910299950 },
        },
        BB = { universe = 4777817887, file = "BladeBall.lua", places = { 13772394625 } },
    }

    local placeGame, universeGame = {}, {}
    for name, info in pairs(games) do
        universeGame[info.universe] = name
        for _, id in ipairs(info.places) do
            placeGame[id] = name
        end
    end

    if type(options.PlaceIds) == "table" then
        for id, name in pairs(options.PlaceIds) do
            if type(id) == "number" and id > 0 and games[name] then
                placeGame[id] = name
            end
        end
    end

    local function child(root, ...)
        for _, name in ipairs({ ... }) do
            root = root and root:FindFirstChild(name)
            if not root then return nil end
        end
        return root
    end

    local function isA(object, class)
        return object ~= nil and object:IsA(class)
    end

    local function remote(object)
        return isA(object, "RemoteEvent") or isA(object, "RemoteFunction")
    end

    local function currency(player, name)
        local ok, value = pcall(player.GetAttribute, player, name)
        if ok and type(value) == "number" then return true end

        for _, container in ipairs({ "leaderstats", "Data" }) do
            local object = child(player, container, name)
            if object then
                local valid, amount = pcall(function() return object.Value end)
                if valid and type(amount) == "number" then return true end
            end
        end
        return false
    end

    local function swordController()
        local controllers = child(ReplicatedStorage, "Controllers")
        if not controllers then return false end
        for _, controller in ipairs(controllers:GetChildren()) do
            if isA(controller, "ModuleScript") and controller.Name:match("^SwordsController[%s%c]*$")
                and isA(child(controller, "PRY"), "ModuleScript") then
                return true
            end
        end
        return false
    end

    local function signatures(player)
        local found = {}
        local function add(name, matched)
            if matched then found[#found + 1] = name end
        end

        local remotes = child(ReplicatedStorage, "Remotes")

        local ghostSignals = 0
        for _, name in ipairs({ "PlayerDiscoveredGhostOrbs", "PlayerDiscoveredSLSAnomaly", "FreezingTempatureObjective" }) do
            if remote(child(remotes, name)) then ghostSignals += 1 end
        end
        add("Blair", ghostSignals >= 2)

        add("FTF", child(ReplicatedStorage, "GameStatus") ~= nil
            and child(ReplicatedStorage, "IsGameActive") ~= nil
            and remote(child(ReplicatedStorage, "RemoteEvent"))
            and child(player, "TempPlayerStatsModule") ~= nil)

        add("VBL", isA(child(ReplicatedStorage, "Content", "Style"), "ModuleScript")
            and isA(child(ReplicatedStorage, "Content", "Special"), "ModuleScript"))

        local scourge = child(remotes, "KillerPerks", "kingscourge")
        add("VD", (currency(player, "Screws") and currency(player, "Gears"))
            or (child(ReplicatedStorage, "ShopKillers") ~= nil
                and remote(child(scourge, "KingScourgeStart"))
                and remote(child(scourge, "KingScourgeEnd"))))

        local events = child(ReplicatedStorage, "Events")
        add("GPO", remote(child(ReplicatedStorage, "Crab_Strangler"))
            and (remote(child(events, "Skill")) or remote(child(events, "takestam"))))

        add("BB", (remote(child(remotes, "ParrySuccess")) and remote(child(remotes, "NoobParryHappened")))
            or (isA(child(ReplicatedStorage, "Shared", "UseBall2"), "ModuleScript") and swordController()))

        return found
    end

    local function selectGame(player)
        local forced = options.Game
        if forced ~= nil then
            if not games[forced] then fail("Unknown game override: " .. tostring(forced)) end
            return forced, "override"
        end

        local byPlace, byUniverse = placeGame[game.PlaceId], universeGame[game.GameId]
        if byPlace and byUniverse and byPlace ~= byUniverse then
            fail("Place and universe identify different games: " .. tostring(game.PlaceId) .. " / " .. tostring(game.GameId))
        end
        if byUniverse then return byUniverse, "universe ID" end
        if byPlace then return byPlace, "place ID" end

        stage("game detection", detectionLimit + 5)
        local deadline = os.clock() + detectionLimit
        local candidate, since
        while true do
            local found = signatures(player)
            if #found > 1 then fail("Ambiguous game signatures: " .. table.concat(found, ", ")) end

            local now = os.clock()
            if found[1] then
                if candidate and candidate ~= found[1] then
                    fail("Conflicting game signatures: " .. candidate .. ", " .. found[1])
                end
                if not candidate then candidate, since = found[1], now end
                if now - since >= 1.5 or now >= deadline then
                    return candidate, "replicated signature"
                end
            else
                candidate, since = nil, nil
            end

            if now >= deadline then break end
            task.wait(0.1)
        end

        fail("Unsupported or unrecognized game. PlaceId: " .. tostring(game.PlaceId) .. ", GameId: " .. tostring(game.GameId))
    end

    local function download(url, label)
        local problem = "no response"
        for attempt = 1, 3 do
            local ok, body = pcall(function() return game:HttpGet(url) end)
            if ok and type(body) == "string" then
                body = body:gsub("^\239\187\191", "")
                local code, reason
                if #body < 256 then code, reason = body:match("^%s*([1-5]%d%d):%s*(.-)%s*$") end
                local head = body:sub(1, 256):lower()

                if code == "404" then
                    fail(label .. " was not found (HTTP 404)\nURL: " .. url)
                elseif code then
                    problem = "HTTP " .. code .. " " .. reason
                elseif head:match("^%s*<!doctype%s+html") or head:match("^%s*<html") then
                    problem = "server returned an HTML page"
                elseif not body:find("%S") then
                    problem = "empty response"
                else
                    return body
                end
            elseif ok then
                problem = "invalid response type " .. type(body)
            else
                problem = tostring(body)
            end

            if attempt < 3 then task.wait(attempt) end
        end
        fail("Download failed for " .. label .. " after 3 attempts: " .. problem .. "\nURL: " .. url)
    end

    local function readiness()
        if not game:IsLoaded() then return nil, "Roblox" end
        local player = Players.LocalPlayer
        if not player then return nil, "LocalPlayer" end
        if not player:FindFirstChildOfClass("PlayerGui") then return nil, "PlayerGui" end
        local camera = workspace.CurrentCamera
        local viewport = camera and camera.ViewportSize
        if not viewport or viewport.X <= 0 or viewport.Y <= 0 then return nil, "camera" end
        if game.PlaceId <= 0 then return nil, "place ID" end
        return player
    end

    stage("client readiness", readinessLimit + 5)
    local deadline = os.clock() + readinessLimit
    local player, waiting = readiness()
    while not player do
        state.Stage = "waiting for " .. waiting
        if os.clock() >= deadline then fail("Startup timed out waiting for " .. waiting) end
        task.wait(0.1)
        player, waiting = readiness()
    end

    state.PlaceId, state.UniverseId = game.PlaceId, game.GameId
    stage("game selection", 5)
    local selected, reason = selectGame(player)
    local file = games[selected].file
    state.Game, state.File, state.URL, state.SelectionReason = selected, file, base .. file, reason
    state.Chunk = "@Aether/" .. file

    stage("download " .. file, 120)
    local source = download(state.URL, file)
    state.WrapperBytes = #source

    if options.NamedLuaProtChunks == true then
        local _, endpoint = source:match(luaProtWrapper)
        if endpoint then
            stage("download protected payload", 120)
            state.PayloadURL = endpoint
            source = download(endpoint, file .. " protected payload")
            state.Chunk = "@Aether/" .. file .. "/LuaProt"
        end
    end

    state.SourceBytes = #source
    stage("compile " .. file, 30)
    local ok, entry, err = pcall(loadstring, source, state.Chunk)
    if not ok then fail("Compiler failed for " .. file .. ": " .. tostring(entry)) end
    if type(entry) ~= "function" then fail("Compile failed for " .. file .. ": " .. tostring(err)) end

    env.A0_AETHER_LAST_ENTRY = file
    stage("execute " .. file, 30)
    print("[Aether] Starting " .. file .. " (" .. reason .. ")")
    return entry()
end

local results = table.pack(xpcall(run, function(err)
    local message = "[Aether / " .. tostring(state.Stage) .. "] " .. tostring(err)
    if type(debug) == "table" and type(debug.traceback) == "function" then
        local ok, trace = pcall(debug.traceback, message, 2)
        if ok and type(trace) == "string" then return trace end
    end
    return message
end))

if env.A0_AETHER_LOADER_BUSY == state then env.A0_AETHER_LOADER_BUSY = nil end
state.Finished = os.clock()

if not results[1] then
    state.Status, state.Error = "error", tostring(results[2])
    error(state.Error, 0)
end

state.Status, state.Stage = "returned", "entry returned"
return table.unpack(results, 2, results.n)
