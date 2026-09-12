local MOD_NAME = "EnableHiddenPainting"

local MANAGERS_OFFICE_CLASS = "R_ArtGallery_ManagersOffice_C"
local MANAGERS_OFFICE_PATH = "/Game/Prototype/Maps/ArtGallery/ArtGallery/Random_ArtGallery/RandomizedRoom_1.R_ArtGallery_ManagersOffice_C"

local PAINTING_ENTITY_PATH = "/Game/Prototype/Maps/ArtGallery/ArtGallery/G_ArtGallery/G_ArtGallery_Scripting.G_ArtGallery_Scripting:PersistentLevel.BP_InteractablePainting_Special"

local DEFENSE_DURATION = 600
local CHECK_INTERVAL = 1000

local BOX_FORWARD_OFFSET = 10
local BOX_DEPTH = 1100
local BOX_HALF_WIDTH = 800
local BOX_HALF_HEIGHT = 100

local function Log(Msg)
    print(string.format("[%s] %s\n", MOD_NAME, Msg))
end

local function LogFmt(Fmt, ...)
    print(string.format("[%s] " .. Fmt .. "\n", MOD_NAME, ...))
end

Log("Loading mod")
LogFmt("Config: duration=%ds, interval=%dms", DEFENSE_DURATION, CHECK_INTERVAL)
LogFmt("Config: box offset=%d, depth=%d, half extents=(%d, %d)", BOX_FORWARD_OFFSET, BOX_DEPTH, BOX_HALF_WIDTH, BOX_HALF_HEIGHT)

local DefenseState = {
    paintingEntity = nil,
    accumulatedTime = 0,
    isInZone = false,
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

local function OnDefenseComplete()
    DefenseState.defenseComplete = true
    LogFmt("Defense complete! Unlocking painting... (%.1f/%.1fs)", DefenseState.accumulatedTime, DEFENSE_DURATION)
end

local function CheckDefenseZone()
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
    elseif not DefenseState.isInZone and wasInZone then
        LogFmt("Left defense zone (%.1f/%.1fs)", DefenseState.accumulatedTime, DEFENSE_DURATION)
    end

    if DefenseState.isInZone then
        local deltaSec = GetWorldDeltaSeconds and GetWorldDeltaSeconds() or 1.0
        DefenseState.accumulatedTime = DefenseState.accumulatedTime + deltaSec

        if DefenseState.accumulatedTime >= DEFENSE_DURATION then
            OnDefenseComplete()
        end
    end
end

local function FindPaintingEntity()
    local entity = FindFirstOf("BP_InteractablePainting_MediumValue_C")
    if entity and entity:IsValid() then
        local fullName = entity:GetFullName()
        if string.find(fullName, "BP_InteractablePainting_Special") then
            return entity
        end
    end

    entity = StaticFindObject(PAINTING_ENTITY_PATH)
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

local Hooked = false
local PaintingFound = false

local function HookManagersOffice()
    if Hooked then return end
    Hooked = true

    RegisterHook(MANAGERS_OFFICE_PATH .. ":ExecuteUbergraph_R_ArtGallery_ManagersOffice", function(self, EntryPoint)
        local EntryPointValue = EntryPoint:get()
        LogFmt("Intercepted ExecuteUbergraph from: , EntryPoint: %d", EntryPointValue)

        if DefenseState.defenseComplete then
            if EntryPointValue == 1202 then
                Log("EntryPoint 1202 detected, triggering 1898")
                pcall(function()
                    self:RemoteDeploy()
                end)
            end
        else
            LogFmt("Defense not complete (%.1f/%.1fs), blocking interaction", DefenseState.accumulatedTime, DEFENSE_DURATION)
        end
    end)

    Log("Successfully registered hook for R_ArtGallery_ManagersOffice!")
end

local function TryFindPainting()
    if PaintingFound then return end

    local entity = FindPaintingEntity()
    if entity then
        PaintingFound = true
        DefenseState.paintingEntity = entity
        LogFmt("Found painting entity: %s", entity:GetFullName())
        StartDefenseTimer()
    end
end

local Existing = FindFirstOf(MANAGERS_OFFICE_CLASS)
if Existing and Existing:IsValid() then
    LogFmt("Found existing instance: %s", Existing:GetFullName())
    HookManagersOffice()
    TryFindPainting()
else
    Log("No existing instance found, waiting for NotifyOnNewObject")
end

NotifyOnNewObject(MANAGERS_OFFICE_PATH, function(ConstructedObject)
    LogFmt("ConstructedObject: %s", ConstructedObject:GetFullName())
    HookManagersOffice()
    TryFindPainting()
end)
