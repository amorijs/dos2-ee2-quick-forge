local MOD_PREFIX = "QuickForge_1993d511-b789-4edc-9e0a-cf15ea5ffd80"
local EPIP_UUID = "7d32cb52-1cfd-4526-9b84-db4867bf9356"
local EE_CORE_UUID = "63bb9b65-2964-4c10-be5b-55a63ec02fa0"

if not Ext.Mod.IsModLoaded(EPIP_UUID) or not Ext.Mod.IsModLoaded(EE_CORE_UUID) then
    Ext.Utils.PrintWarning("[QuickForge] Requires Epip Encounters and Epic Encounters Core; not loading.")
    return
end

-- The Script Extender sandboxes each ModTable mod into its own Lua
-- environment; Epip's globals (Epip, _Feature, Client, Item, Net, ...) live
-- in Mods.EpipEncounters. ImportGlobals is Epip's sanctioned way to expose
-- them to an addon's environment.
Mods.EpipEncounters.Epip.ImportGlobals(Mods.QuickForge)

Ext.Require(MOD_PREFIX, "QuickForge/Shared.lua")
Ext.Require(MOD_PREFIX, "QuickForge/Server.lua")
