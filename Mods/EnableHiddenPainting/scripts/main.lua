local MOD_NAME = "EnableHiddenPainting"
local DEBUG_LOG = false

local MANAGERS_OFFICE_CLASS = "R_ArtGallery_ManagersOffice_C"
local PAINTING_ENTITY_PATH = "/Game/Prototype/Maps/ArtGallery/ArtGallery/G_ArtGallery/G_ArtGallery_Scripting.G_ArtGallery_Scripting:PersistentLevel.BP_InteractablePainting_Special"

local DEFENSE_DURATION = 60 * 10 * 3 --30 minutes in seconds
local CHECK_INTERVAL = 1000

local BOX_FORWARD_OFFSET = 10
local BOX_DEPTH = 1100
local BOX_HALF_WIDTH = 800
local BOX_HALF_HEIGHT = 100

local function Log(Msg)
    if not DEBUG_LOG then return end
    print(string.format("[%s] %s\n", MOD_NAME, Msg))
end

local function LogFmt(Fmt, ...)
    if not DEBUG_LOG then return end
    print(string.format("[%s] " .. Fmt .. "\n", MOD_NAME, ...))
end

local function SendChatMessage(Msg)
    pcall(function()
        local chatInGame = FindFirstOf("SBZChatInGame")
        if not chatInGame or not chatInGame:IsValid() then return end

        local controller = FindFirstOf("PlayerController")
        if not controller or not controller:IsValid() then return end

        local playerState = controller.PlayerState
        if not playerState or not playerState:IsValid() then return end

        chatInGame:SendChatMessageToServer({PlayerState = playerState, Message = Msg})
    end)
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
    pcall(function()
        local office = FindFirstOf(MANAGERS_OFFICE_CLASS)
        if office and office:IsValid() then
            LogFmt("Found managers office: %s", office:GetFullName())
            office:RemoteDeploy()
            Log("RemoteDeploy called successfully")
        else
            Log("Managers office not found")
        end
    end)
end

local function OnDefenseComplete()
    DefenseState.defenseComplete = true
    LogFmt("Defense complete! (%.1f/%.1fs)", DefenseState.accumulatedTime, DEFENSE_DURATION)
    SendChatMessage("And... we're in. Security grid is down. That Latrell is ours. Now get back to the manager's office -- there's a hidden release mechanism on the wall. Look for the buttons. I'll guide you through.")
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
        SendChatMessage("You're in range. Starting sensor loop now. Keep your position -- I need you steady.")
    elseif not DefenseState.isInZone and wasInZone then
        LogFmt("Left defense zone (%.1f/%.1fs)", DefenseState.accumulatedTime, DEFENSE_DURATION)
        SendChatMessage("You moved out of range! System's resetting. Get back to the painting -- fast!")
    end

    if DefenseState.isInZone then
        local deltaSec = GetWorldDeltaSeconds and GetWorldDeltaSeconds() or 1.0
        local prevTime = DefenseState.accumulatedTime
        DefenseState.accumulatedTime = DefenseState.accumulatedTime + deltaSec

        local prevPct = math.floor(prevTime / DEFENSE_DURATION * 100)
        local currPct = math.floor(DefenseState.accumulatedTime / DEFENSE_DURATION * 100)
        if currPct >= 25 and prevPct < 25 then
            SendChatMessage("Quarter cycle complete. Sensors are buying it so far. Keep holding.")
        elseif currPct >= 50 and prevPct < 50 then
            SendChatMessage("Halfway there. You're doing great. Almost got it.")
        elseif currPct >= 75 and prevPct < 75 then
            SendChatMessage("Three quarters. Hang tight -- we're in the home stretch.")
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
        pcall(CheckDefenseZone)
    end)
    Log("Defense timer started")
end

local function OnHackComplete()
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

    pcall(function()
        ExecuteWithDelay(2000, function()
            ExecuteInGameThread(function()
                SendChatMessage("Hold on -- I'm seeing something else in the building inventory. There's a Shanda Latrell original on the floor below, near Exhibition Room E2. Nine figures easy. But it's got a proximity security grid -- you'll need to stay close for about ten minutes while I loop the sensors. I'll mark the location.")
                StartDefenseTimer()
            end)
        end)
    end)
    Log("Hack detected, starting defense sequence")
end

RegisterHook("/Script/Starbreeze.SBZMissionState:RewardCompleteExperienceObjective", function(Context, ObjectiveName)
    local objective = ObjectiveName:get():ToString()
    LogFmt("Objective completed: %s", objective)
    if objective == "search_manifest" then
        OnHackComplete()
    end
end)
