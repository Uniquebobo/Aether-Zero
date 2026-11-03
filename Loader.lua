-- Split repositories: dispatcher URL is independent of the game-files base URL.
-- Execute official game wrappers unchanged unless NamedLuaProtChunks=true is explicitly requested.
local env = type(getgenv) == "function" and getgenv() or _G
assert(type(env) == "table", "[Aether] Executor environment is not a table")
if env.A0_AETHER_LOADER_BUSY then
    print("[Aether] Startup is already in progress")
    return
end
env.A0_AETHER_LOADER_BUSY = true
local diagnostic = {Stage = "setup", Started = os.clock(), Status = "starting"}
env.A0_AETHER_LOADER_DIAGNOSTIC = diagnostic

local function traceback(err)
    local message = "[Aether / " .. tostring(diagnostic.Stage) .. "] " .. tostring(err)
    if type(debug) == "table" and type(debug.traceback) == "function" then
        local ok, trace = pcall(debug.traceback, message, 2)
        if ok and type(trace) == "string" then return trace end
    end
    return message
end

local function run()
    assert(type(loadstring) == "function", "Executor loadstring is unavailable")
    -- The game files and the dispatcher intentionally live in different repos.
    local defaultGamesBase = "https://raw.githubusercontent.com/MeneSkidButBetterThanYou/AetherZero/refs/heads/main/"
    local defaultLoaderURL = "https://raw.githubusercontent.com/Uniquebobo/Aether-Zero/refs/heads/main/Loader.lua"
    local legacyBase = env.A0_AETHER_BASE_URL
    if legacyBase == defaultLoaderURL:match("^(.*[/])") then legacyBase = nil end
    local base = env.A0_AETHER_GAMES_BASE_URL or legacyBase or defaultGamesBase
    local loaderScriptURL = env.A0_AETHER_LOADER_URL or defaultLoaderURL
    assert(type(base) == "string" and base:match("^https://"), "Games base URL must use HTTPS")
    assert(type(loaderScriptURL) == "string" and loaderScriptURL:match("^https://"), "Loader URL must use HTTPS")
    if base:sub(-1) ~= "/" then base ..= "/" end
    diagnostic.GamesBaseURL = base
    diagnostic.LoaderURL = loaderScriptURL
    local opts = type(env.A0_LOADER_OPTIONS) == "table" and env.A0_LOADER_OPTIONS or {}
    local timeout = tonumber(opts.ReadinessTimeout) or 120
    if timeout ~= timeout or math.abs(timeout) == math.huge then timeout = 120 end
    timeout = math.clamp(timeout, 0, 600)
    local games = {
        Blair = {universe=2239430935, file="Blair.lua", places={6137321701}},
        FTF = {universe=372226183, file="FTF.lua", places={893973440}},
        VBL = {universe=6931042565, file="VBL.lua", places={73956553001240}},
        VD = {universe=6739698191, file="VD.lua", places={93978595733734}},
        GPO = {universe=648454481, file="GPO.lua", places={1730877806,3978370137,7465136166,6360478118,6811831486,10218387007,11424731604,116480749200627}},
        Rivals = {universe=6035872082, file="Rivals.lua", places={17625359962,18126510175,71874690745115,117398147513099,129604661913557,133215910299950}},
        BB = {universe=4777817887, file="BladeBall.lua", places={13772394625}},
    }
    local places, universes = {}, {}
    for name, info in pairs(games) do
        universes[info.universe] = name
        for _, id in ipairs(info.places) do places[id] = name end
    end
    local function resolve(placeId, universeId)
        local byPlace = places[placeId]
        local hasUniverse = type(universeId) == "number" and universeId > 0
        local byUniverse = hasUniverse and universes[universeId] or nil
        if byPlace and hasUniverse and byPlace ~= byUniverse then
            error("PlaceId/universe mismatch: " .. tostring(placeId) .. " / " .. tostring(universeId), 0)
        end
        local name = byUniverse or (not hasUniverse and byPlace) or nil
        if not name then
            error("Unsupported experience: PlaceId " .. tostring(placeId) .. ", universe " .. tostring(universeId), 0)
        end
        return name, games[name].file
    end
    local function download(url, label)
        local ok, source = pcall(function() return game:HttpGet(url) end)
        if not ok then
            error("Download failed for " .. label .. ": " .. tostring(source) .. "\nURL: " .. url, 0)
        end
        if type(source) ~= "string" or not source:find("%S") then
            error("Empty/non-text response for " .. label .. "\nURL: " .. url, 0)
        end
        local head = source:sub(1, 256):lower()
        if head:match("^%s*<!doctype%s+html") or head:match("^%s*<html") or source:match("^%s*404:%s*Not Found%s*$") then
            error("Server returned an error page, not Lua, for " .. label .. "\nURL: " .. url, 0)
        end
        return source
    end
    local function compile(source, chunkName)
        local ok, entry, reason = pcall(loadstring, source, chunkName)
        if not ok then error("Compiler failed for " .. chunkName .. ": " .. tostring(entry), 0) end
        if type(entry) ~= "function" then
            error("Compile failed for " .. chunkName .. ": " .. tostring(reason), 0)
        end
        return entry
    end
    local function firstFunction(...)
        for i = 1, select("#", ...) do
            local candidate = select(i, ...)
            if type(candidate) == "function" then return candidate end
        end
    end
    local function queueLoader()
        if opts.AutoExecute == false then return false, "disabled" end
        local synEnv = type(syn) == "table" and syn or {}
        local fluxEnv = type(fluxus) == "table" and fluxus or {}
        local deltaEnv = type(env.Delta) == "table" and env.Delta or {}
        local queue = firstFunction(queue_on_teleport, queueonteleport, synEnv.queue_on_teleport,
            fluxEnv.queue_on_teleport, deltaEnv.queue_on_teleport, deltaEnv.queueonteleport)
        if not queue then return false, "executor queue unavailable" end
        local loaderURL = loaderScriptURL
        local signature = loaderURL .. "|" .. base .. "|" .. tostring(timeout) .. "|" .. tostring(opts.NamedLuaProtChunks == true)
        if env.A0_AETHER_QUEUED_LOADER_SIGNATURE == signature then return true, "already queued" end
        -- Don't queue a known-broken URL. This checks syntax, but never executes it here.
        local checked, reason = pcall(function()
            compile(download(loaderURL, "teleport Loader.lua"), "@Aether/Loader.lua")
        end)
        if not checked then return false, "not queued: " .. tostring(reason) end
        local code = "local e=type(getgenv)=='function' and getgenv() or _G; "
            .. "e.A0_AETHER_BASE_URL=" .. string.format("%q", base) .. "; "
            .. "e.A0_AETHER_GAMES_BASE_URL=" .. string.format("%q", base) .. "; "
            .. "e.A0_AETHER_LOADER_URL=" .. string.format("%q", loaderScriptURL) .. "; "
            .. "local o=type(e.A0_LOADER_OPTIONS)=='table' and e.A0_LOADER_OPTIONS or {}; "
            .. "o.ReadinessTimeout=" .. tostring(timeout) .. "; "
            .. "o.NamedLuaProtChunks=" .. tostring(opts.NamedLuaProtChunks == true) .. "; "
            .. "e.A0_LOADER_OPTIONS=o; "
            .. "local s=game:HttpGet(" .. string.format("%q", loaderURL) .. "); "
            .. "local f,err=loadstring(s,'@Aether/Loader.lua'); "
            .. "if type(f)~='function' then error('[Aether] Teleport loader compile failed: '..tostring(err),0) end; return f()"
        local ok, result = pcall(queue, code)
        if not ok or result == false then return false, "queue failed: " .. tostring(result) end
        env.A0_AETHER_QUEUED_LOADER_URL = loaderURL
        env.A0_AETHER_QUEUED_LOADER_SIGNATURE = signature
        return true, "queued for teleport"
    end

    diagnostic.Stage = "client readiness"
    local deadline = os.clock() + timeout
    local announced = false
    local placeId, universeId
    while true do
        local stage = "Roblox initial loading"
        if game:IsLoaded() then
            local player = game:GetService("Players").LocalPlayer
            stage = "LocalPlayer"
            if player then
                local gui = player:FindFirstChildOfClass("PlayerGui") or player:FindFirstChild("PlayerGui")
                stage = "PlayerGui"
                if gui then
                    local camera = workspace.CurrentCamera
                    local viewport = camera and camera.ViewportSize
                    stage = "client camera/viewport"
                    if viewport and viewport.X > 0 and viewport.Y > 0 then
                        stage = "place identity"
                        if type(game.PlaceId) == "number" and game.PlaceId > 0 then
                            placeId, universeId = game.PlaceId, game.GameId
                            break
                        end
                    end
                end
            end
        end
        diagnostic.Stage = "waiting for " .. stage
        if os.clock() >= deadline then error("Startup timed out waiting for " .. stage .. ". No payload started; rerun to retry.", 0) end
        if not announced then
            announced = true
            print("[Aether] Waiting for " .. stage .. "; startup will continue automatically")
        end
        task.wait(0.1)
    end
    diagnostic.Stage = "game selection"
    diagnostic.PlaceId, diagnostic.UniverseId = placeId, universeId
    local name, file = resolve(placeId, universeId)
    diagnostic.Game, diagnostic.File, diagnostic.URL = name, file, base .. file
    diagnostic.Stage = "download " .. file
    local source = download(diagnostic.URL, file)
    diagnostic.WrapperBytes = #source
    diagnostic.Chunk = "@Aether/" .. file
    local endpoint
    if opts.NamedLuaProtChunks == true then
        endpoint = source:match('^%s*loadstring%s*%(%s*game%s*:%s*HttpGet%s*%(%s*"(https://luaprot%.net/api/v3/loaders/get/%d+)"%s*%)%s*%)%s*%(%s*%)%s*;?%s*$')
            or source:match("^%s*loadstring%s*%(%s*game%s*:%s*HttpGet%s*%(%s*'(https://luaprot%.net/api/v3/loaders/get/%d+)'%s*%)%s*%)%s*%(%s*%)%s*;?%s*$")
    end
    if endpoint then
        diagnostic.Stage = "download LuaProt payload for " .. file
        diagnostic.PayloadURL = endpoint
        source = download(endpoint, file .. " LuaProt payload")
        diagnostic.Chunk = "@Aether/" .. file .. "/LuaProt"
    end
    diagnostic.SourceBytes = #source
    diagnostic.Stage = "compile " .. diagnostic.Chunk
    local entry = compile(source, diagnostic.Chunk)
    env.A0_AETHER_LAST_ENTRY = file
    diagnostic.Stage = "teleport queue setup"
    local queued, queueStatus = queueLoader()
    env.A0_AETHER_AUTOEXEC_STATUS = queueStatus
    diagnostic.QueueStatus = queueStatus
    if not queued and queueStatus ~= "disabled" then warn("[Aether] Auto-execute: " .. queueStatus) end
    diagnostic.Stage = "execute " .. diagnostic.Chunk
    print("[Aether] Starting " .. file .. " (" .. tostring(#source) .. " bytes)")
    if endpoint then
        entry()
        return
    end
    return entry()
end

local results = table.pack(xpcall(run, traceback))
env.A0_AETHER_LOADER_BUSY = nil
diagnostic.Finished = os.clock()
if not results[1] then
    diagnostic.Status, diagnostic.Error = "error", tostring(results[2])
    error(diagnostic.Error, 0)
end
diagnostic.Status, diagnostic.Stage = "returned", "entry returned"
return table.unpack(results, 2, results.n)
