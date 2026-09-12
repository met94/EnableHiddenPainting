local MOD_NAME = "EnableHiddenPainting"

local PAINTING_CLASS = "BP_HiddenPainting_C"
local PAINTING_CLASS_PATH = "/Game/Prototype/Maps/ArtGallery/BP_HiddenPainting.BP_HiddenPainting_C"

local BUTTON_CLASS = "BP_One_Step_Animated_Button_C"
local BUTTON_CLASS_PATH = "/Game/Environment/_Common/Interactable/RedButtonSmall_01/BP_One_Step_Animated_Button.BP_One_Step_Animated_Button_C"

local LEVEL_BP_CLASS = "R_ArtGallery_ManagersOffice_C"
local LEVEL_BP_PATH = "/Game/Prototype/Maps/ArtGallery/R_ArtGallery_ManagersOffice.R_ArtGallery_ManagersOffice_C"

local function Log(Msg)
    print(string.format("[%s] %s\n", MOD_NAME, Msg))
end

local function LogFmt(Fmt, ...)
    print(string.format("[%s] " .. Fmt .. "\n", MOD_NAME, ...))
end

local function FindActor(Class, Path)
    local Obj = FindFirstOf(Class)
    if Obj and Obj:IsValid() then
        return Obj
    end

    if Path then
        LogFmt("WARN: %s not found via FindFirstOf, trying StaticFindObject", Class)
        Obj = StaticFindObject(Path)
        if Obj and Obj:IsValid() then
            return Obj
        end
        LogFmt("WARN: %s not found via StaticFindObject either", Class)
    end

    return nil
end

local function EnablePainting()
    local Painting = FindActor(PAINTING_CLASS, PAINTING_CLASS_PATH)
    if not Painting then
        Log("ERROR: painting not found")
        return false
    end

    LogFmt("Found painting: %s", Painting:GetFullName())

    local Ok, Err = pcall(function()
        Painting:SetInteractionEnabled(true)
    end)
    if Ok then
        Log("Painting:SetInteractionEnabled(true)")
    else
        LogFmt("FAILED: Painting:SetInteractionEnabled(true) — %s", tostring(Err))
    end

    return Ok
end

local function EnableButton()
    local Button = FindActor(BUTTON_CLASS, BUTTON_CLASS_PATH)
    if not Button then
        Log("WARN: button not found, skipping")
        return false
    end

    LogFmt("Found button: %s", Button:GetFullName())

    local Outline = Button.SBZOutline
    if Outline and Outline:IsValid() then
        local Ok, Err = pcall(function()
            Outline:SetReplicatedHidden(false)
        end)
        if Ok then
            Log("Button.SBZOutline:SetReplicatedHidden(false)")
        else
            LogFmt("FAILED: SBZOutline:SetReplicatedHidden(false) — %s", tostring(Err))
        end
    else
        Log("WARN: Button.SBZOutline not found or invalid")
    end

    local Interactable = Button.Interactable
    if Interactable and Interactable:IsValid() then
        local Ok, Err = pcall(function()
            Interactable:SetInteractionEnabled(true)
        end)
        if Ok then
            Log("Button.Interactable:SetInteractionEnabled(true)")
        else
            LogFmt("FAILED: Interactable:SetInteractionEnabled(true) — %s", tostring(Err))
        end
    else
        Log("WARN: Button.Interactable not found or invalid")
    end

    return true
end

local function FireRemoteEvent(EventName)
    local LevelBP = FindActor(LEVEL_BP_CLASS, LEVEL_BP_PATH)
    if not LevelBP then
        Log("WARN: level blueprint not found, trying FindAllOf")

        local AllActors = FindAllOf("LevelScriptActor")
        if AllActors then
            for _, Actor in pairs(AllActors) do
                local FullName = Actor:GetFullName()
                if string.find(FullName, "R_ArtGallery_ManagersOffice") then
                    LevelBP = Actor
                    LogFmt("Found level blueprint via ALevelScriptActor: %s", FullName)
                    break
                end
            end
        end
    end

    if not LevelBP then
        Log("WARN: could not find level blueprint, skipping RemoteEvent")
        return false
    end

    LogFmt("Found level blueprint: %s", LevelBP:GetFullName())

    local Ok, Err = pcall(function()
        LevelBP:RemoteEvent(EventName)
    end)
    if Ok then
        LogFmt("RemoteEvent(\"%s\")", EventName)
    else
        LogFmt("FAILED: RemoteEvent(\"%s\") — %s", EventName, tostring(Err))
    end

    return Ok
end

local function GrantFullReward()
    Log("--- Granting full reward ---")
    EnablePainting()
    EnableButton()
    --FireRemoteEvent("EnableYellowBrickRoad")
    Log("--- Done ---")
end

local function DumpClassFunctions(ClassPath, FilterPattern)
    local Class = StaticFindObject(ClassPath)
    if not Class or not Class:IsValid() then
        LogFmt("ERROR: class not found at %s", ClassPath)
        return
    end

    LogFmt("Class: %s", Class:GetFullName())

    local Count = 0
    local MatchCount = 0
    Class:ForEachFunction(function(Func)
        Count = Count + 1
        local Name = Func:GetFName():ToString()
        if FilterPattern and string.find(string.lower(Name), string.lower(FilterPattern)) then
            MatchCount = MatchCount + 1
            LogFmt("  MATCH [%d]: %s -> %s", MatchCount, Name, Func:GetFullName())
        end
    end)

    LogFmt("Total functions: %d, matches for '%s': %d", Count, FilterPattern or "", MatchCount)
end

local function RunDiagnostics()
    Log("=== Diagnostics ===")
    DumpClassFunctions(PAINTING_CLASS_PATH, "nteract")
    DumpClassFunctions(BUTTON_CLASS_PATH, "nteract")
    DumpClassFunctions(LEVEL_BP_PATH, "vent")
    Log("=== End diagnostics ===")
end

Log("Loading mod")
Log("Ctrl+F6 = grant full reward (painting + button + RemoteEvent)")
Log("Ctrl+F5 = run diagnostics (dump function names)")

RegisterKeyBind(Key.F6, {ModifierKey.CONTROL}, function()
    ExecuteInGameThread(function()
        GrantFullReward()
    end)
end)

RegisterKeyBind(Key.F5, {ModifierKey.CONTROL}, function()
    ExecuteInGameThread(function()
        RunDiagnostics()
    end)
end)
