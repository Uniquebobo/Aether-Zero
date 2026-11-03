 
local env = type(getgenv) == "function" and getgenv() or _G
if env.A0_AETHER_LOADER_BUSY then
    print("[Aether] Startup is already in progress")
    return
end

local base = env.A0_AETHER_BASE_URL or "https://raw.githubusercontent.com/MeneSkidButBetterThanYou/AetherZero/refs/heads/main/"
assert(type(base) == "string" and base:match("^https://"), "[Aether] Base URL must use HTTPS")
if base:sub(-1) ~= "/" then base ..= "/" end

 
local games = {
    Blair  = {universe=2239430935, file="Blair.lua", places={6137321701}},
    FTF    = {universe=372226183, file="FTF.lua", places={893973440}},
    VBL    = {universe=6931042565, file="VBL.lua", places={73956553001240}},
    VD     = {universe=6739698191, file="VD.lua", places={93978595733734}},
    GPO    = {universe=648454481, file="GPO.lua", places={1730877806,3978370137,7465136166,6360478118,6811831486,10218387007,11424731604,116480749200627}},
    Rivals = {universe=6035872082, file="Rivals.lua", places={17625359962,18126510175,71874690745115,117398147513099,129604661913557,133215910299950}},
    BB     = {universe=4777817887, file="BladeBall.lua", places={13772394625}},
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
        return nil, "PlaceId/universe mismatch: " .. tostring(placeId) .. " / " .. tostring(universeId)
    end
    local name = byUniverse or (not hasUniverse and byPlace) or nil
    if not name then return nil, "Unsupported experience: PlaceId " .. tostring(placeId) .. ", universe " .. tostring(universeId) end
    return name, games[name].file
end

local function waitForClient()
    local opts = type(env.A0_LOADER_OPTIONS) == "table" and env.A0_LOADER_OPTIONS or {}
    local timeout = tonumber(opts.ReadinessTimeout) or 120
    if timeout ~= timeout or math.abs(timeout) == math.huge then timeout = 120 end
    local deadline = os.clock() + math.clamp(timeout, 0, 600)
    local announced = false
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
                            return game.PlaceId, game.GameId
                        end
                    end
                end
            end
        end
        if os.clock() >= deadline then return nil, "Startup timed out waiting for " .. stage .. ". No payload started; rerun to retry." end
        if not announced then announced = true; print("[Aether] Waiting for " .. stage .. "; startup will continue automatically") end
        task.wait(0.1)
    end
end

 
 
local function queueLoader()
    local opts = type(env.A0_LOADER_OPTIONS) == "table" and env.A0_LOADER_OPTIONS or {}
    if opts.AutoExecute == false then return false, "disabled" end
    local synEnv = type(syn) == "table" and syn or {}
    local fluxEnv = type(fluxus) == "table" and fluxus or {}
    local deltaEnv = type(env.Delta) == "table" and env.Delta or {}
    local queue = queue_on_teleport or queueonteleport or synEnv.queue_on_teleport
        or fluxEnv.queue_on_teleport or deltaEnv.queue_on_teleport or deltaEnv.queueonteleport
    if type(queue) ~= "function" then return false, "executor queue unavailable" end
    local code = "local e=type(getgenv)=='function' and getgenv() or _G; e.A0_AETHER_BASE_URL="
        .. string.format("%q", base) .. "; local s=game:HttpGet("
        .. string.format("%q", base .. "Loader.lua") .. "); local f=assert(loadstring(s)); return f()"
    local ok, reason = pcall(queue, code)
    if not ok then return false, tostring(reason) end
    return true, "queued for teleport"
end

local function run()
    local placeId, universeId = waitForClient()
    if not placeId then warn("[Aether] " .. tostring(universeId)); return end
    local name, file = resolve(placeId, universeId)
    if not name then warn("[Aether] " .. tostring(file)); return end
    local ok, source = pcall(function() return game:HttpGet(base .. file) end)
    if not ok or type(source) ~= "string" or #source == 0 then warn("[Aether] Download failed: " .. file); return end
    local entry, err = loadstring(source)
    if not entry then warn("[Aether] Compile failed for " .. file .. ": " .. tostring(err)); return end
    env.A0_AETHER_LAST_ENTRY = file
    local queued, queueStatus = queueLoader()
    env.A0_AETHER_AUTOEXEC_STATUS = queueStatus
    if not queued and queueStatus ~= "disabled" then warn("[Aether] Auto-execute: " .. queueStatus) end
    return entry()
end

env.A0_AETHER_LOADER_BUSY = true
local ok, result = pcall(run)
env.A0_AETHER_LOADER_BUSY = nil
if not ok then error("[Aether] " .. tostring(result), 0) end
return result
