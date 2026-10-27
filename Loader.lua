local Env=type(getgenv)=="function"and getgenv()or _G
if Env.A0_AETHER_LOADER_BUSY then print("[Aether] Startup is already in progress; the existing run is waiting or loading");return end
local Base=Env.A0_AETHER_BASE_URL or "https://raw.githubusercontent.com/MeneSkidButBetterThanYou/AetherZero/refs/heads/main/"
assert(type(Base)=="string"and Base:match("^https://"),"[Aether] Base URL must use HTTPS")
if Base:sub(-1)~="/"then Base..="/"end
local function A0ResolveIdentity(PlaceId,UniverseId,Allowed)
local Places={
[6137321701]="Blair",[893973440]="FTF",[73956553001240]="VBL",[93978595733734]="VD",
[1730877806]="GPO",[3978370137]="GPO",[7465136166]="GPO",[6360478118]="GPO",[6811831486]="GPO",[10218387007]="GPO",[11424731604]="GPO",[116480749200627]="GPO",
[17625359962]="Rivals",[18126510175]="Rivals",[71874690745115]="Rivals",[117398147513099]="Rivals",[129604661913557]="Rivals",[133215910299950]="Rivals",
}
local Universes={[2239430935]="Blair",[372226183]="FTF",[6931042565]="VBL",[6739698191]="VD",[648454481]="GPO",[6035872082]="Rivals"}
local ByPlace=Places[PlaceId]
local HasUniverse=type(UniverseId)=="number"and UniverseId>0
local ByUniverse=HasUniverse and Universes[UniverseId]or nil
if ByPlace and HasUniverse and ByPlace~=ByUniverse then
return nil,"PlaceId/universe mismatch: "..tostring(PlaceId).." / "..tostring(UniverseId),"conflict"
end
local Key=ByUniverse or(not HasUniverse and ByPlace)or nil
if not Key then return nil,"Unsupported experience: PlaceId "..tostring(PlaceId)..", universe "..tostring(UniverseId),"unknown"end
if Allowed and not Allowed[Key]then return nil,"This entry does not support "..Key,"wrong_entry"end
return Key,ByUniverse and "Roblox universe confirmed"or"Known PlaceId confirmed (universe unavailable)","confirmed"
end
local function A0WaitForClient(Deps)
local Game,Root,Clock,Pause=Deps.game,Deps.workspace,Deps.clock,Deps.pause
local Options=type(Deps.options)=="table"and Deps.options or{}
local Timeout=tonumber(Options.ReadinessTimeout)or 120
if Timeout~=Timeout or math.abs(Timeout)==math.huge then Timeout=120 end
local Deadline=Clock()+math.clamp(Timeout,0,600)
local Announced=false
while true do
if Deps.cancelled and Deps.cancelled()then return nil,"Startup canceled","canceled"end
local Stage="Roblox initial loading"
if Game:IsLoaded()then
local Players=Game:GetService("Players")
local Player=Players.LocalPlayer
Stage="LocalPlayer"
if Player then
local Gui=Player:FindFirstChildOfClass("PlayerGui")or Player:FindFirstChild("PlayerGui")
Stage="PlayerGui"
if Gui then
local Camera=Root.CurrentCamera
local Viewport=Camera and Camera.ViewportSize
Stage="client camera/viewport"
if Viewport and Viewport.X>0 and Viewport.Y>0 then
Stage="place identity"
if type(Game.PlaceId)=="number"and Game.PlaceId>0 then
return {Player=Player,PlayerGui=Gui,Camera=Camera,PlaceId=Game.PlaceId,UniverseId=Game.GameId}
end
end
end
end
end
if Clock()>=Deadline then
return nil,"Startup timed out waiting for "..Stage..". No game payload started; rerun to retry.","timeout"
end
if not Announced then
Announced=true
if Deps.onWaiting then Deps.onWaiting(Stage)end
end
Pause(0.1)
end
end

local function Run()
local Ready,Reason=A0WaitForClient({game=game,workspace=workspace,clock=os.clock,pause=task.wait,options=Env.A0_LOADER_OPTIONS,onWaiting=function(Stage)print("[Aether] Waiting for "..Stage.."; startup will continue automatically")end})
if not Ready then warn("[Aether] "..tostring(Reason));return end
local Key,IdentityReason=A0ResolveIdentity(Ready.PlaceId,Ready.UniverseId)
if not Key then warn("[Aether] "..tostring(IdentityReason));return end
local File=Key=="GPO"and"GPO.lua"or Key=="Rivals"and"Rivals.lua"or"4Games.lua"
local Ok,Source=pcall(function()return game:HttpGet(Base..File)end)
if not Ok or type(Source)~="string"or #Source==0 then warn("[Aether] Download failed: "..File);return end
local Entry,CompileError=loadstring(Source)
if not Entry then warn("[Aether] Compile failed for "..File..": "..tostring(CompileError));return end
Env.A0_AETHER_LAST_ENTRY=File
return Entry()
end
Env.A0_AETHER_LOADER_BUSY=true
local Ok,Result=pcall(Run)
Env.A0_AETHER_LOADER_BUSY=nil
if not Ok then error("[Aether] "..tostring(Result),0)end
return Result
