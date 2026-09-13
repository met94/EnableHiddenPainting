local MOD_NAME = "EnableHiddenPainting"
local DEBUG_LOG = false

local MANAGERS_OFFICE_CLASS = "R_ArtGallery_ManagersOffice_C"
local PAINTING_ENTITY_PATH = "/Game/Prototype/Maps/ArtGallery/ArtGallery/G_ArtGallery/G_ArtGallery_Scripting.G_ArtGallery_Scripting:PersistentLevel.BP_InteractablePainting_Special"

local DEFENSE_DURATION = 60 * 10 --10 minutes in seconds
local CHECK_INTERVAL = 1000

local BOX_FORWARD_OFFSET = 10
local BOX_DEPTH = 1100
local BOX_HALF_WIDTH = 800
local BOX_HALF_HEIGHT = 200

local OnHackComplete

local function Log(Msg)
    if not DEBUG_LOG then return end
    print(string.format("[%s] %s\n", MOD_NAME, Msg))
end

local function LogFmt(Fmt, ...)
    if not DEBUG_LOG then return end
    print(string.format("[%s] " .. Fmt .. "\n", MOD_NAME, ...))
end

local function GetLevelName()
    local UEHelpers = require("UEHelpers")
    local World = UEHelpers.GetWorld()
    if not World:IsValid() then return nil end

    local GameplayStatics = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    if not GameplayStatics:IsValid() then return nil end

    -- Parameters: WorldContextObject, bRemovePrefixString
    local LevelName = GameplayStatics:GetCurrentLevelName(World, true)
    return LevelName:ToString()
end

local function SendChatMessage(Msg)
    local chatInGame = FindFirstOf("SBZChatInGame")
    if not chatInGame or not chatInGame:IsValid() then return end

    local controller = FindFirstOf("PlayerController")
    if not controller or not controller:IsValid() then return end

    local playerState = controller.PlayerState
    if not playerState or not playerState:IsValid() then return end

    chatInGame:SendChatMessageToServer({PlayerState = playerState, Message = Msg})
end

Log("Loading mod")
LogFmt("Config: duration=%ds, interval=%dms", DEFENSE_DURATION, CHECK_INTERVAL)
LogFmt("Config: box offset=%d, depth=%d, half extents=(%d, %d)", BOX_FORWARD_OFFSET, BOX_DEPTH, BOX_HALF_WIDTH, BOX_HALF_HEIGHT)

local DefenseState = {
    paintingEntity = nil,
    accumulatedTime = 0,
    isInZone = false,
    defenseActive = false,
    defenseComplete = false,
    timerHandle = nil
}

local ObjectiveHookIds = { preId = nil, postId = nil }

local function ResetDefenseState()
    if DefenseState.timerHandle then
        CancelDelayedAction(DefenseState.timerHandle)
    end
    DefenseState.paintingEntity = nil
    DefenseState.accumulatedTime = 0
    DefenseState.isInZone = false
    DefenseState.defenseActive = false
    DefenseState.defenseComplete = false
    DefenseState.timerHandle = nil
    Log("DefenseState reset")
end

local function RegisterObjectiveHook()
    if ObjectiveHookIds.preId then return end
    ObjectiveHookIds.preId, ObjectiveHookIds.postId = RegisterHook(
        "/Script/Starbreeze.SBZMissionState:RewardCompleteExperienceObjective",
        function(Context, ObjectiveName)
            local objective = ObjectiveName:get():ToString()
            LogFmt("Objective completed: %s", objective)
            if objective == "search_manifest" then
                OnHackComplete()
            end
        end
    )
    Log("Objective hook registered")
end

local function UnregisterObjectiveHook()
    if not ObjectiveHookIds.preId then return end
    UnregisterHook(
        "/Script/Starbreeze.SBZMissionState:RewardCompleteExperienceObjective",
        ObjectiveHookIds.preId,
        ObjectiveHookIds.postId
    )
    ObjectiveHookIds.preId = nil
    ObjectiveHookIds.postId = nil
    Log("Objective hook unregistered")
end

local function IsInDefenseBox(playerLoc, entityLoc, forwardVec, rightVec)
    local dx = playerLoc.X - entityLoc.X
    local dy = playerLoc.Y - entityLoc.Y
    local dz = playerLoc.Z - entityLoc.Z

    local fwdX = rightVec.X
    local fwdY = rightVec.Y
    local rgtX = -forwardVec.X
    local rgtY = -forwardVec.Y

    local forwardDist = dx * fwdX + dy * fwdY
    local rightDist = dx * rgtX + dy * rgtY
    local upDist = dz

    return forwardDist >= BOX_FORWARD_OFFSET and forwardDist <= BOX_FORWARD_OFFSET + BOX_DEPTH
        and math.abs(rightDist) <= BOX_HALF_WIDTH
        and math.abs(upDist) <= BOX_HALF_HEIGHT
end

local function TriggerRemoteDeploy()
    local office = FindFirstOf(MANAGERS_OFFICE_CLASS)
    if office and office:IsValid() then
        LogFmt("Found managers office: %s", office:GetFullName())
        office:RemoteDeploy()
        Log("RemoteDeploy called successfully")
    else
        Log("Managers office not found")
    end
end

local function OnDefenseComplete()
    DefenseState.defenseComplete = true
    LogFmt("Defense complete! (%.1f/%.1fs)", DefenseState.accumulatedTime, DEFENSE_DURATION)
    SendChatMessage("<Good>And... we're in.</> <Hud_01>Security grid is down.</> <Skills1>That Latrell is ours.</> <Notation>Now get back to the manager's office -- there's a hidden release mechanism on the wall. Look for the buttons. I'll guide you through.</>")
    TriggerRemoteDeploy()
end

local function CheckDefenseZone()
    if not DefenseState.defenseActive then return end
    if DefenseState.defenseComplete then return end
    if not DefenseState.paintingEntity or not DefenseState.paintingEntity:IsValid() then return end

    local pawn = FindFirstOf("SBZPlayerCharacter")
    if not pawn or not pawn:IsValid() then return end

    local playerLoc = pawn:K2_GetActorLocation()
    local entityLoc = DefenseState.paintingEntity:K2_GetActorLocation()
    local forwardVec = DefenseState.paintingEntity:GetActorForwardVector()
    local rightVec = DefenseState.paintingEntity:GetActorRightVector()

    local wasInZone = DefenseState.isInZone
    DefenseState.isInZone = IsInDefenseBox(playerLoc, entityLoc, forwardVec, rightVec)

    if DefenseState.isInZone and not wasInZone then
        LogFmt("Entered defense zone (%.1f/%.1fs)", DefenseState.accumulatedTime, DEFENSE_DURATION)
        SendChatMessage("<Good>You're in range.</> <Notation>Starting sensor loop now. Keep your position -- I need you steady.</>")
    elseif not DefenseState.isInZone and wasInZone then
        LogFmt("Left defense zone (%.1f/%.1fs)", DefenseState.accumulatedTime, DEFENSE_DURATION)
        SendChatMessage("<Bad>You moved out of range!</> <Hostile>System's resetting. Get back to the painting -- fast!</>")
    end

    if DefenseState.isInZone then
        local deltaSec = GetWorldDeltaSeconds and GetWorldDeltaSeconds() or 1.0
        local prevTime = DefenseState.accumulatedTime
        DefenseState.accumulatedTime = DefenseState.accumulatedTime + deltaSec

        local prevPct = math.floor(prevTime / DEFENSE_DURATION * 100)
        local currPct = math.floor(DefenseState.accumulatedTime / DEFENSE_DURATION * 100)
        if currPct >= 25 and prevPct < 25 then
            SendChatMessage("<Hud_01>Quarter cycle complete.</> <Notation>Sensors are buying it so far. Keep holding.</>")
        elseif currPct >= 50 and prevPct < 50 then
            SendChatMessage("<Hud_01>Halfway there.</> <Skills1>You're doing great. Almost got it.</>")
        elseif currPct >= 75 and prevPct < 75 then
            SendChatMessage("<Hud_01>Three quarters.</> <Notation>Hang tight -- we're in the home stretch.</>")
        end

        if DefenseState.accumulatedTime >= DEFENSE_DURATION then
            OnDefenseComplete()
        end
    end
end

local function FindPaintingEntity()
    local entities = FindAllOf("BP_InteractablePainting_MediumValue_C")
    if entities then
        for _, entity in ipairs(entities) do
            if entity:IsValid() then
                local fullName = entity:GetFullName()
                if string.find(fullName, "BP_InteractablePainting_Special") then
                    return entity
                end
            end
        end
    end

    local entity = StaticFindObject(PAINTING_ENTITY_PATH)
    if entity and entity:IsValid() then
        return entity
    end

    return nil
end

local function StartDefenseTimer()
    if DefenseState.timerHandle then return end
    DefenseState.timerHandle = LoopInGameThreadWithDelay(CHECK_INTERVAL, function()
        CheckDefenseZone()
    end)
    Log("Defense timer started")
end

OnHackComplete = function()
    if DefenseState.defenseActive then
        Log("OnHackComplete: already active, skipping")
        return
    end

    Log("OnHackComplete: finding painting entity")
    local entity = FindPaintingEntity()
    if not entity then
        Log("Painting entity not found yet, retrying in 1s")
        ExecuteWithDelay(1000, function()
            ExecuteInGameThread(function()
                OnHackComplete()
            end)
        end)
        return
    end

    DefenseState.paintingEntity = entity
    DefenseState.defenseActive = true
    LogFmt("Found painting entity: %s", entity:GetFullName())

    ExecuteWithDelay(2000, function()
        ExecuteInGameThread(function()
            SendChatMessage("<Notation>Hold on -- I'm seeing something else in the building inventory. There's a </><Skills1>Shanda Latrell</><Notation> original on the floor below, near </><Object>Exhibition Room E2</><Notation>. Nine figures easy. But it's got a </><Bad>proximity security grid</><Notation> -- you'll need to stay close for about </><Skills1>ten minutes</><Notation> while I loop the sensors. I'll mark the location.</>")
            StartDefenseTimer()
        end)
    end)
    Log("Hack detected, starting defense sequence")
end

RegisterHook("/Script/Starbreeze.SBZGameplayManager:OnPlayableLevelInitialized", function(Context)
    Log("OnPlayableLevelInitialized fired")
    ResetDefenseState()
    local levelName = GetLevelName()
    LogFmt("Level name: %s", tostring(levelName))
    if levelName == "ArtGallery" then
        RegisterObjectiveHook()
    else
        UnregisterObjectiveHook()
    end
end)

RegisterHook("/Script/Starbreeze.SBZGameplayManager:OnRestartLevelStarted", function(Context)
    Log("OnRestartLevelStarted fired")
    ResetDefenseState()
end)

RegisterHook("/Script/Starbreeze.SBZGameStateMachine:RequestReturnToMainMenu", function(Context, Reason)
    Log("RequestReturnToMainMenu fired")
    --pcall(function()
        --LogFmt("RequestReturnToMainMenu fired, Reason: %s", tostring(Reason:get()))
    --end)
    ResetDefenseState()
    UnregisterObjectiveHook()
end)

RegisterHook("/Script/Starbreeze.SBZGameStateMachine:RequestMissionEnd", function(Context, RequestData)
    Log("RequestMissionEnd fired")
    --pcall(function()
        --local data = RequestData:get()
        --LogFmt("RequestMissionEnd fired, MissionResult: %s, OutroVariation: %s", tostring(data.MissionResult), tostring(data.OutroVariation))
    --end)
    ResetDefenseState()
    UnregisterObjectiveHook()
end)
