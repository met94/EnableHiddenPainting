local MOD_NAME = "EnableHiddenPainting"

local MANAGERS_OFFICE_CLASS = "R_ArtGallery_ManagersOffice_C"
local MANAGERS_OFFICE_PATH = "/Game/Prototype/Maps/ArtGallery/ArtGallery/Random_ArtGallery/RandomizedRoom_1.R_ArtGallery_ManagersOffice_C"

local function Log(Msg)
    print(string.format("[%s] %s\n", MOD_NAME, Msg))
end

local function LogFmt(Fmt, ...)
    print(string.format("[%s] " .. Fmt .. "\n", MOD_NAME, ...))
end

Log("Loading mod")

local Hooked = false

local function HookManagersOffice()
    if Hooked then return end
    Hooked = true

    RegisterHook(MANAGERS_OFFICE_PATH .. ":ExecuteUbergraph_R_ArtGallery_ManagersOffice", function(self, EntryPoint)
        local EntryPointValue = EntryPoint:get()
        LogFmt("Intercepted ExecuteUbergraph from: , EntryPoint: %d", EntryPointValue)

        --if EntryPointValue == 1202 then
            Log("EntryPoint 1202 detected, triggering 1898")
            pcall(function()
                self:RemoteDeploy()
            end)
        --end
    end)

    Log("Successfully registered hook for R_ArtGallery_ManagersOffice!")
end

local function PrintAllFunctions(Obj)
    if not Obj or not Obj:IsValid() then
        print("Invalid object")
        return
    end

    local Class = Obj:GetClass()
    print("=== Class: " .. Class:GetFullName() .. " ===")

    print("Functions:")
    Class:ForEachFunction(function(Func)
        print("  " .. Func:GetFullName())
    end)

    print("Properties:")
    Class:ForEachProperty(function(Prop)
        print("  " .. Prop:GetFullName())
    end)
end



local Existing = FindFirstOf(MANAGERS_OFFICE_CLASS)
if Existing and Existing:IsValid() then
    LogFmt("Found existing instance: %s", Existing:GetFullName())
    PrintAllFunctions(Existing)
    Existing:RemoteDeploy()
    HookManagersOffice()
else
    Log("No existing instance found, waiting for NotifyOnNewObject")
end

NotifyOnNewObject(MANAGERS_OFFICE_PATH, function(ConstructedObject)
    LogFmt("ConstructedObject: %s", ConstructedObject:GetFullName())
    HookManagersOffice()
end)
