local env = type(getgenv) == "function" and getgenv() or _G
assert(type(env) == "table", "[Aether] Executor environment unavailable")

if env.A0_AETHER_LOADER_BUSY then
    print("[Aether] Startup is already in progress")
    return
end

env.A0_AETHER_LOADER_BUSY = true

local state = {
    Stage = "setup",
    Status = "starting",
    Started = os.clock(),
}
env.A0_AETHER_LOADER_DIAGNOSTIC = state

local function fail(message)
    error(message, 0)
end

local function run()
    assert(type(loadstring) == "function", "Executor loadstring is unavailable")

    local options = type(env.A0_LOADER_OPTIONS) == "table" and env.A0_LOADER_OPTIONS or {}
    local defaultBase = "https://raw.githubusercontent.com/MeneSkidButBetterThanYou/AetherZero/refs/heads/main/"
    local dispatcherBase = "https://raw.githubusercontent.com/Uniquebobo/Aether-Zero/refs/heads/main/"
    local legacyBase = env.A0_AETHER_BASE_URL
    if legacyBase == dispatcherBase then legacyBase = nil end

    local base = env.A0_AETHER_GAMES_BASE_URL or legacyBase or defaultBase
    assert(type(base) == "string" and base:match("^https://"), "Games base URL must use HTTPS")
    if base:sub(-1) ~= "/" then base ..= "/" end
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

    local places, universes = {}, {}
    for name, info in pairs(games) do
        universes[info.universe] = name
        for _, id in ipairs(info.places) do
            places[id] = name
        end
    end

    if type(options.PlaceIds) == "table" then
        for id, name in pairs(options.PlaceIds) do
            if type(id) == "number" and id > 0 and games[name] then
                places[id] = name
            end
        end
    end

    local function timeout(value, fallback, limit)
        local number = tonumber(value) or fallback
        if number ~= number or math.abs(number) == math.huge then number = fallback end
        return math.clamp(number, 0, limit)
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

    local function candidates(player)
        local storage = game:GetService("ReplicatedStorage")
        local found = {}
        local function add(name, condition)
            if condition then found[#found + 1] = name end
        end

        local blairRemotes = child(storage, "Remotes")
        local ghostSignals = 0
        for _, name in ipairs({ "PlayerDiscoveredGhostOrbs", "PlayerDiscoveredSLSAnomaly", "FreezingTempatureObjective" }) do
            if remote(child(blairRemotes, name)) then ghostSignals += 1 end
        end
        add("Blair", ghostSignals >= 2)

        add("FTF", child(storage, "GameStatus") ~= nil
            and child(storage, "IsGameActive") ~= nil
            and remote(child(storage, "RemoteEvent"))
            and child(player, "TempPlayerStatsModule") ~= nil)

        add("VBL", isA(child(storage, "Content", "Style"), "ModuleScript")
            and isA(child(storage, "Content", "Special"), "ModuleScript"))

        local scourge = child(storage, "Remotes", "KillerPerks", "kingscourge")
        local vdShop = child(storage, "ShopKillers")
        add("VD", (currency(player, "Screws") and currency(player, "Gears"))
            or (vdShop ~= nil and remote(child(scourge, "KingScourgeStart"))
                and remote(child(scourge, "KingScourgeEnd"))))

        local events = child(storage, "Events")
        add("GPO", remote(child(storage, "Crab_Strangler"))
            and (remote(child(events, "Skill")) or remote(child(events, "takestam"))))

        local controllers = child(storage, "Controllers")
        local swordController = false
        if controllers then
            for _, controller in ipairs(controllers:GetChildren()) do
                if isA(controller, "ModuleScript") and controller.Name:match("^SwordsController[%s%c]*$")
                    and isA(child(controller, "PRY"), "ModuleScript") then
                    swordController = true
                    break
                end
            end
        end
        local ballRemotes = child(storage, "Remotes")
        local ballSignals = remote(child(ballRemotes, "ParrySuccess"))
            and remote(child(ballRemotes, "NoobParryHappened"))
        add("BB", ballSignals or (isA(child(storage, "Shared", "UseBall2"), "ModuleScript")
            and swordController))

        return found
    end

    local function selectGame(player, placeId, universeId)
        local byPlace = places[placeId]
        local byUniverse = universes[universeId]
        if byPlace and byUniverse and byPlace ~= byUniverse then
            fail("Place and universe identify different games: " .. tostring(placeId) .. " / " .. tostring(universeId))
        end

        local selected = byUniverse or byPlace
        if selected then
            state.SelectionReason = byUniverse and "universe ID" or "place ID"
            return selected
        end

        state.Stage = "game detection"
        local deadline = os.clock() + timeout(options.DetectionTimeout, 8, 30)
        local firstMatch, matchedAt
        repeat
            local found = candidates(player)
            if #found > 1 then
                fail("Ambiguous game signatures: " .. table.concat(found, ", "))
            end
            if #found == 1 then
                if firstMatch and firstMatch ~= found[1] then
                    fail("Conflicting game signatures: " .. firstMatch .. ", " .. found[1])
                end
                if not firstMatch then firstMatch, matchedAt = found[1], os.clock() end
                if os.clock() - matchedAt >= 1.5 or os.clock() >= deadline then
                    state.SelectionReason = "replicated signature"
                    return firstMatch
                end
            elseif firstMatch then
                firstMatch, matchedAt = nil, nil
            end
            if os.clock() >= deadline then break end
            task.wait(0.1)
        until false

        fail("Unsupported or unrecognized game. PlaceId: " .. tostring(placeId) .. ", GameId: " .. tostring(universeId))
    end

    local function download(url, label)
        local ok, source = pcall(function() return game:HttpGet(url) end)
        if not ok then fail("Download failed for " .. label .. ": " .. tostring(source) .. "\nURL: " .. url) end
        if type(source) ~= "string" or not source:find("%S") then fail("Empty response for " .. label .. "\nURL: " .. url) end
        local head = source:sub(1, 256):lower()
        if head:match("^%s*<!doctype%s+html") or head:match("^%s*<html") or source:match("^%s*404:%s*Not Found%s*$") then
            fail("Server returned an error page for " .. label .. "\nURL: " .. url)
        end
        return source
    end

    state.Stage = "client readiness"
    local deadline = os.clock() + timeout(options.ReadinessTimeout, 120, 600)
    local player
    repeat
        local waiting = "Roblox"
        if game:IsLoaded() then
            player = game:GetService("Players").LocalPlayer
            waiting = "LocalPlayer"
            if player then
                local gui = player:FindFirstChildOfClass("PlayerGui") or player:FindFirstChild("PlayerGui")
                waiting = "PlayerGui"
                if gui then
                    local camera = workspace.CurrentCamera
                    local viewport = camera and camera.ViewportSize
                    waiting = "camera"
                    if viewport and viewport.X > 0 and viewport.Y > 0 and type(game.PlaceId) == "number" and game.PlaceId > 0 then
                        break
                    end
                end
            end
        end
        state.Stage = "waiting for " .. waiting
        if os.clock() >= deadline then fail("Startup timed out waiting for " .. waiting) end
        task.wait(0.1)
    until false

    state.PlaceId, state.UniverseId = game.PlaceId, game.GameId
    state.Stage = "game selection"
    local selected = selectGame(player, game.PlaceId, game.GameId)
    local file = games[selected].file
    state.Game, state.File, state.URL = selected, file, base .. file
    state.Stage = "download " .. file
    local source = download(state.URL, file)
    state.WrapperBytes = #source
    state.Chunk = "@Aether/" .. file

    if options.NamedLuaProtChunks == true then
        local endpoint = source:match('^%s*loadstring%s*%(%s*game%s*:%s*HttpGet%s*%(%s*"(https://luaprot%.net/api/v3/loaders/get/%d+)"%s*%)%s*%)%s*%(%s*%)%s*;?%s*$')
            or source:match("^%s*loadstring%s*%(%s*game%s*:%s*HttpGet%s*%(%s*'(https://luaprot%.net/api/v3/loaders/get/%d+)'%s*%)%s*%)%s*%(%s*%)%s*;?%s*$")
        if endpoint then
            state.Stage = "download protected payload"
            state.PayloadURL = endpoint
            source = download(endpoint, file .. " protected payload")
            state.Chunk = "@Aether/" .. file .. "/LuaProt"
        end
    end

    state.SourceBytes = #source
    state.Stage = "compile " .. file
    local ok, entry, reason = pcall(loadstring, source, state.Chunk)
    if not ok then fail("Compiler failed for " .. file .. ": " .. tostring(entry)) end
    if type(entry) ~= "function" then fail("Compile failed for " .. file .. ": " .. tostring(reason)) end

    env.A0_AETHER_LAST_ENTRY = file
    state.Stage = "execute " .. file
    print("[Aether] Starting " .. file .. " (" .. state.SelectionReason .. ")")
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

env.A0_AETHER_LOADER_BUSY = nil
state.Finished = os.clock()

if not results[1] then
    state.Status, state.Error = "error", tostring(results[2])
    error(state.Error, 0)
end

state.Status, state.Stage = "returned", "entry returned"
return table.unpack(results, 2, results.n)
