---------------------------------------------
-- QuickForge pure-logic core.
-- No game API access: takes plain fact tables, returns plain data.
-- Runs both inside the Script Extender and under a standalone Lua
-- interpreter for the test suite (tests/run.lua).
---------------------------------------------

local Core = {}

---@class QuickForge.ItemFacts
---@field rarity string Item rarity per `ItemTypeReal` ("Common".."Divine", "Unique").
---@field isArtifact boolean
---@field socketedRuneCount integer
---@field itemLevel integer
---@field characterLevel integer
---@field hasGreatforgeBlockedTag boolean `AMER_GREATFORGEBLOCKED` tag.
---@field runeSlotCount integer
---@field isWeapon boolean
---@field isTwoHanded boolean

---@class QuickForge.MenuEntry
---@field ID string Context menu element ID.
---@field Option string? Greatforge option ID; nil for the open-Greatforge fallback entry.
---@field Label string Player-facing name.

---@class QuickForge.SessionState
---@field partyInCombat boolean
---@field currentUI string? EE2 physical-UI ID the character is in, if any.

---@class QuickForge.DirectOpState
---@field partyInCombat boolean
---@field anyPlayerInGreatforge boolean Any character in a real Greatforge session (`DB_AMER_UI_UsersInUI`).

---@alias QuickForge.JumpPlan "blocked_combat"|"request_instance"|"swap_ui"|"bench"
---@alias QuickForge.DirectOpPlan "blocked_combat"|"blocked_session"|"proceed"
---@alias QuickForge.CommitRoute "direct"|"jump"
---@alias QuickForge.PickerKind "property_uptier"|"property_keep"|"donor"

---One selectable row of a Forge Window picker, as previewed by the server.
---Everything shown is read live from EE2's data; a nil Cost means EE2 gave
---us no number for the row (never guess one).
---@class QuickForge.PickerRow
---@field Key string Stable identity between preview and commit (property prefix, or donor GUID).
---@field Eligible boolean
---@field Cost integer? Per-row cost; nil for options with a flat window cost.

---Weapons hold up to 2 runes when one-handed; everything else up to 3.
---@param facts QuickForge.ItemFacts
---@return integer
function Core.GetSocketLimit(facts)
    if facts.isWeapon and not facts.isTwoHanded then
        return 2
    end
    return 3
end

---Options in Greatforge wheel order, Epip-added options last.
---Predicates mirror EE2's `QRY_AMER_UI_Greatforge_InvalidSelection` rules,
---restricted to what is reliably computable client-side. Conditions EE2 can
---only evaluate on the bench (e.g. deltamod counts for Masterwork/Cull/Combine,
---"already Masterworked") are deliberately not replicated: both the Greatforge
---and the Direct Operation preview re-validate server-side and show their own
---message box.
---Route: "direct" options execute in place through the Forge Window; "jump"
---options open EE2's physical UI on their picker page (phase 2 flips the
---picker options to "direct" one at a time as they land).
---Picker: the selection step the option's Forge Window carries, if any.
---@type {ID: string, Route: QuickForge.CommitRoute, Picker: QuickForge.PickerKind?, IsApplicable: fun(facts: QuickForge.ItemFacts): boolean}[]
Core.OPTIONS = {
    {
        ID = "ExtractRunes",
        Route = "direct",
        IsApplicable = function(facts) return facts.socketedRuneCount > 0 end,
    },
    {
        ID = "Reduce",
        Route = "direct",
        IsApplicable = function(facts) return facts.rarity ~= "Common" end,
    },
    {
        ID = "LevelUp",
        Route = "direct",
        IsApplicable = function(facts) return facts.itemLevel < facts.characterLevel end,
    },
    {
        ID = "Masterwork",
        Route = "direct",
        Picker = "property_uptier",
        IsApplicable = function(facts)
            return facts.rarity ~= "Common" and not facts.hasGreatforgeBlockedTag
        end,
    },
    {
        ID = "Focalize",
        Route = "direct",
        IsApplicable = function(facts) return facts.isArtifact end,
    },
    {
        ID = "Transmute",
        Route = "direct",
        IsApplicable = function(facts) return facts.rarity ~= "Unique" end,
    },
    {
        ID = "RemoveMods",
        Route = "direct",
        Picker = "property_keep",
        IsApplicable = function(facts)
            return facts.rarity ~= "Unique" and not facts.hasGreatforgeBlockedTag
        end,
    },
    {
        ID = "Combine",
        Route = "direct",
        Picker = "donor",
        IsApplicable = function(facts)
            return facts.rarity ~= "Common"
                and (facts.rarity ~= "Unique" or facts.isArtifact)
                and not facts.hasGreatforgeBlockedTag
        end,
    },
    {
        ID = "AddSockets",
        Route = "direct",
        IsApplicable = function(facts)
            return facts.runeSlotCount < Core.GetSocketLimit(facts)
        end,
    },
    {
        ID = "PIP_Engrave",
        Route = "direct",
        IsApplicable = function(_) return true end,
    },
}

---Context menu element ID of the "Open in Greatforge..." fallback entry.
Core.OPEN_GREATFORGE_ENTRY_ID = "QuickForge_OpenGreatforge"

---Whether an option ID is in the registry.
---@param optionID string
---@return boolean
function Core.IsKnownOption(optionID)
    return Core.GetRoute(optionID) ~= nil
end

---How an option commits: in place through the Forge Window ("direct"),
---or by Jumping into EE2's physical UI ("jump"). Nil for unknown options.
---@param optionID string
---@return QuickForge.CommitRoute?
function Core.GetRoute(optionID)
    for _, option in ipairs(Core.OPTIONS) do
        if option.ID == optionID then
            return option.Route
        end
    end
    return nil
end

---The selection step an option's Forge Window carries, if any.
---@param optionID string
---@return QuickForge.PickerKind?
function Core.GetPicker(optionID)
    for _, option in ipairs(Core.OPTIONS) do
        if option.ID == optionID then
            return option.Picker
        end
    end
    return nil
end

---------------------------------------------
-- PICKERS
---------------------------------------------

---Classifies one Masterwork picker row, mirroring EE2's own selection gates
---in order: PropertyMaxed (uptier deltamod "NONE") before
---PropertyLevelTooHigh (uptier level above the item's), as in
---AMER_GLO_UI_Greatforge_Internal.txt:1473-1475. The inputs come straight
---from EE2's Masterwork_ValidatedMods row and the benched item.
---@param facts {uptierDeltamod: string, uptierLevel: integer, itemLevel: integer}
---@return {eligible: boolean, reason: ("maxed"|"level_too_high")?}
function Core.ClassifyMasterworkRow(facts)
    if facts.uptierDeltamod == "NONE" then
        return {eligible = false, reason = "maxed"}
    elseif facts.uptierLevel > facts.itemLevel then
        return {eligible = false, reason = "level_too_high"}
    end
    return {eligible = true}
end

---Only eligible rows respond to clicks; ineligible rows stay greyed with
---their reason. Affordability is deliberately not considered here —
---eligible-but-unaffordable rows stay selectable with Confirm greyed.
---@param row QuickForge.PickerRow
---@return boolean
function Core.IsPickerRowSelectable(row)
    return row.Eligible
end

---The cost a selection puts on the window's cost line: the row's own cost
---(Masterwork prices per Property) or the option's flat cost.
---@param row QuickForge.PickerRow
---@param flatCost integer?
---@return integer?
function Core.GetPickerSelectionCost(row, flatCost)
    if row.Cost ~= nil then
        return row.Cost
    end
    return flatCost
end

---Whether Confirm may be enabled for a picker selection: a deliberate pick
---of an eligible row, with a known, affordable cost. A visual gate only —
---the server re-validates everything at commit time.
---@param row QuickForge.PickerRow? Nil when nothing is selected.
---@param flatCost integer?
---@param funds integer
---@return boolean
function Core.CanConfirmPicker(row, flatCost, funds)
    if not row or not row.Eligible then
        return false
    end
    local cost = Core.GetPickerSelectionCost(row, flatCost)
    return cost ~= nil and funds >= cost
end

---Verdict for one Combine donor candidate, composing EE2's individually
---callable donor checks in EE2's own order
---(AMER_GLO_UI_Greatforge_Internal.txt:1946-1964). The page-driven wrapper
---queries open message boxes as side effects, so the server calls the
---underlying always-active queries and feeds their results here; this
---function owns only the composition, including EE2's own exception that a
---rarity-only roll failure is allowed (:2062-2067). Reasons are the
---suffixes of EE2's "AMER_UI_Greatforge_Combine_*" message TSKs.
---@param facts {isTargetItem: boolean, modCount: integer, hasSamePrefix: boolean, hasExcludedPrefix: boolean, rollFailReason: string?}
---@return {valid: boolean, reason: string?}
function Core.EvaluateDonor(facts)
    if facts.isTargetItem then
        return {valid = false, reason = "ItemAddedIsTheSame"}
    elseif facts.modCount > 1 then
        return {valid = false, reason = "ItemAddedHasTooManyMods"}
    elseif facts.modCount < 1 then
        return {valid = false, reason = "ItemAddedHasNoMods"}
    elseif facts.hasSamePrefix then
        return {valid = false, reason = "ItemAddedHasSamePrefix"}
    elseif facts.hasExcludedPrefix then
        return {valid = false, reason = "ItemAddedHasExcludedPrefix"}
    elseif facts.rollFailReason ~= nil and facts.rollFailReason ~= "Rarity" then
        return {valid = false, reason = "Fail_" .. facts.rollFailReason}
    end
    return {valid = true}
end

---Finds a previewed row again by its stable key. Used at commit time to
---re-match the player's selection against freshly re-derived rows: a
---selection whose key no longer matches refuses as stale.
---@param rows QuickForge.PickerRow[]
---@param key string?
---@return QuickForge.PickerRow?
function Core.FindPickerRow(rows, key)
    if key == nil then
        return nil
    end
    for _, row in ipairs(rows) do
        if row.Key == key then
            return row
        end
    end
    return nil
end

---Returns the IDs of the options applicable to an item, in registry order.
---@param facts QuickForge.ItemFacts
---@return string[]
function Core.GetApplicableOptions(facts)
    local applicable = {}
    for _, option in ipairs(Core.OPTIONS) do
        if option.IsApplicable(facts) then
            table.insert(applicable, option.ID)
        end
    end
    return applicable
end

---Builds context menu entry descriptors for a set of options, followed by
---the "Open in Greatforge..." fallback entry (an option-less Jump).
---@param optionIDs string[]
---@param labels table<string, string> Option ID (or "OpenGreatforge") → player-facing label.
---@return QuickForge.MenuEntry[]
function Core.BuildMenuEntries(optionIDs, labels)
    local entries = {}
    for _, optionID in ipairs(optionIDs) do
        table.insert(entries, {
            ID = "QuickForge_Option_" .. optionID,
            Option = optionID,
            Label = labels[optionID] or optionID,
        })
    end
    table.insert(entries, {
        ID = Core.OPEN_GREATFORGE_ENTRY_ID,
        Label = labels.OpenGreatforge or "Open in Greatforge...",
    })
    return entries
end

---Decides how to get a character's Greatforge session ready for benching.
---Mirrors the Meditate skill's own gating: blocked while the party fights.
---@param state QuickForge.SessionState
---@return QuickForge.JumpPlan
function Core.PlanJump(state)
    if state.partyInCombat then
        return "blocked_combat"
    elseif state.currentUI == "AMER_UI_Greatforge" then
        return "bench"
    elseif state.currentUI then
        return "swap_ui"
    end
    return "request_instance"
end

---Decides whether a Direct Operation may run at all.
---Combat mirrors the Meditate skill's gating; a player inside a real
---Greatforge session refuses structurally (the internal-goal state would be
---shared with the live session), with the Jump offered instead.
---@param state QuickForge.DirectOpState
---@return QuickForge.DirectOpPlan
function Core.PlanDirectOperation(state)
    if state.partyInCombat then
        return "blocked_combat"
    elseif state.anyPlayerInGreatforge then
        return "blocked_session"
    end
    return "proceed"
end

return Core
