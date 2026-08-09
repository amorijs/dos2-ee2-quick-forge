---------------------------------------------
-- QuickForge server: executes a Jump.
--
-- Sequence (all EE2 physical-UI procs, nothing committed):
--   1. PROC_AMER_UI_RequestInstance / PROC_AMER_UI_SwapActiveUI opens the
--      Greatforge session for the character (synchronous Osiris chain).
--   2. PROC_AMER_UI_Greatforge_BenchedItem_Set benches the item. The item is
--      not moved and equipped items stay equipped — EE2 records the bench in
--      a database and only unequips/consumes at craft-commit time.
--   3. Benching finalizes asynchronously (item-type behaviour hook), signalled
--      by PROC_AMER_UI_Greatforge_FinalizeBenchedItem. Then
--      PROC_AMER_UI_Greatforge_UpdateNavBar_OptionWheel selects the option and
--      the synthesized "AMER_UI_Greatforge_OptionChosen" event opens its
--      confirm/picker page — with EE2 running its own validity checks.
--
-- Committing (the "AMER_UI_Greatforge_Confirm" event) is never fired here;
-- the player confirms or backs out inside the Greatforge as normal.
---------------------------------------------

local QuickForge = Epip.GetFeature("QuickForge", "QuickForge", true) ---@type Features.QuickForge
local Core = QuickForge.Core

local GREATFORGE_UI = "AMER_UI_Greatforge"
local NULL_GUID = "NULL_00000000-0000-0000-0000-000000000000"

---@class QuickForge.PendingJump
---@field ItemGuid string
---@field Option string? Nil for the "Open in Greatforge..." fallback: bench only, land on the option wheel.

---Pending Jumps by character GUID — per-character, so simultaneous Jumps by
---different players cannot interfere. In-memory only: a pending Jump does not
---survive a reload, which is correct (the UI session does not either).
---@type table<string, QuickForge.PendingJump>
QuickForge._PendingJumps = {}

---Osiris passes GUIDs with a name prefix ("Name_uuid"); entity MyGuid may be
---bare. Normalizes both forms to the bare UUID for table keys and comparisons.
---@param guidString string
---@return string
local function GetBareGuid(guidString)
    return string.sub(guidString, -36)
end

---@param char EsvCharacter
---@return QuickForge.SessionState
function QuickForge._GetSessionState(char)
    local currentUI = nil
    local sessions = Osi.DB_AMER_UI_UsersInUI:Get(nil, nil, char.MyGuid)
    if sessions and sessions[1] then
        currentUI = sessions[1][2]
    end

    return {
        partyInCombat = Osi.QRY_AMER_GEN_IsPartyInCombat() == true,
        currentUI = currentUI,
    }
end

---Benches the character's pending item into their active Greatforge session.
---Drops the pending Jump if no session materialized (e.g. no free instance).
---@param charGuid string
function QuickForge._BenchPending(charGuid)
    local charKey = GetBareGuid(charGuid)
    local pending = QuickForge._PendingJumps[charKey]
    if not pending then return end

    local sessions = Osi.DB_AMER_UI_UsersInUI:Get(nil, GREATFORGE_UI, charGuid)
    if not sessions or not sessions[1] then
        QuickForge._PendingJumps[charKey] = nil
        return
    end
    local instance = sessions[1][1]

    -- Reserve the instance's craft object (normally done when the player
    -- clicks the forge socket). Committing silently no-ops without it:
    -- PROC_AMER_UI_Funds_RequestSuccess requires
    -- DB_AMER_UI_Greatforge_CraftObject_Reserved to reach DoCraft.
    -- The query is idempotent; EE2's exit cleanup releases the object.
    local map = Osi.DB_CurrentLevel:Get(nil)[1][1]
    Osi.QRY_AMER_UI_Greatforge_GetCraftObject(instance, charGuid, map)

    -- Reserving teleports the craft object to the character — but at this
    -- point the character has not yet made their timed fade-teleport into the
    -- UI area, so the object would be left at their old world position.
    -- Combine's donor picker opens the vanilla crafting UI on the craft
    -- object, which needs it near the character; park it at the instance's
    -- teleport anchor, where the character is about to arrive.
    local reserved = Osi.DB_AMER_UI_Greatforge_CraftObject_Reserved:Get(instance, nil)
    local anchors = Osi.DB_AMER_UI_TeleportAnchor:Get(map, instance, nil)
    if reserved and reserved[1] and anchors and anchors[1] then
        local craftObject, anchor = reserved[1][2], anchors[1][3]
        local x, y, z = Osi.GetPosition(anchor)
        if x then
            Osi.TeleportToPosition(craftObject, x, y, z, "", 0, 1)
        end
    end

    Osi.PROC_AMER_UI_Greatforge_BenchedItem_Set(instance, charGuid, pending.ItemGuid)
end

Net.RegisterListener(QuickForge.NETMSG_JUMP, function(payload)
    local char, item = payload:GetCharacter(), payload:GetItem()
    local option = payload.Option
    if not char or not item then
        return
    end
    if option ~= nil and (type(option) ~= "string" or not Core.IsKnownOption(option)) then
        return
    end

    local plan = Core.PlanJump(QuickForge._GetSessionState(char))
    if plan == "blocked_combat" then
        -- Same message the Meditate skill shows.
        Osi.OpenMessageBox(char.MyGuid, "AMER_UI_GEN_MeditateBlocked_PartyInCombat")
        return
    end

    QuickForge._PendingJumps[GetBareGuid(char.MyGuid)] = {
        ItemGuid = item.MyGuid,
        Option = option,
    }

    if plan == "request_instance" then
        Osi.PROC_AMER_UI_RequestInstance(char.MyGuid, GREATFORGE_UI)
    elseif plan == "swap_ui" then
        Osi.PROC_AMER_UI_SwapActiveUI(char.MyGuid, GREATFORGE_UI)
    end
    -- The session setup chain is synchronous; by now the character either has
    -- a Greatforge session (fresh, swapped, or pre-existing) or the request
    -- failed and EE2 showed its own message box.
    QuickForge._BenchPending(char.MyGuid)
end)

-- Benching finalized: select the option and open its page.
Ext.Osiris.RegisterListener("PROC_AMER_UI_Greatforge_FinalizeBenchedItem", 9, "after",
    function(instance, charGuid, itemGuid, _, _, _, _, _, _)
        local charKey = GetBareGuid(charGuid)
        local pending = QuickForge._PendingJumps[charKey]
        if not pending then return end

        QuickForge._PendingJumps[charKey] = nil
        if GetBareGuid(itemGuid) ~= GetBareGuid(pending.ItemGuid) then
            -- Something else got benched in the meantime; leave the UI as-is.
            return
        end
        if not pending.Option then
            -- "Open in Greatforge...": benched is all; stay on the option wheel.
            return
        end

        Osi.PROC_AMER_UI_Greatforge_UpdateNavBar_OptionWheel(instance, pending.Option)
        -- Same synthesis EE2 itself uses for wheel-card clicks. If the option
        -- is invalid for the item after all, EE2 shows its message box and
        -- stays on the option wheel.
        Osi.CharacterItemSetEvent(charGuid, NULL_GUID, "AMER_UI_Greatforge_OptionChosen")
    end)

-- Session ended (voluntarily or forced, e.g. combat): drop any pending Jump.
Ext.Osiris.RegisterListener("PROC_AMER_UI_OnExitUI", 3, "after", function(_, charGuid, _)
    QuickForge._PendingJumps[GetBareGuid(charGuid)] = nil
end)
