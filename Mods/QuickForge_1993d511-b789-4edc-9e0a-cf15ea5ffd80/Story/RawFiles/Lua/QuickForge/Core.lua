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
---@field Option string Greatforge option ID.
---@field Label string Player-facing name.

---@class QuickForge.SessionState
---@field partyInCombat boolean
---@field currentUI string? EE2 physical-UI ID the character is in, if any.

---@alias QuickForge.JumpPlan "blocked_combat"|"request_instance"|"swap_ui"|"bench"

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
---"already Masterworked") are deliberately not replicated: the Greatforge
---itself re-validates on option selection and shows its own message box.
---@type {ID: string, IsApplicable: fun(facts: QuickForge.ItemFacts): boolean}[]
Core.OPTIONS = {
    {
        ID = "ExtractRunes",
        IsApplicable = function(facts) return facts.socketedRuneCount > 0 end,
    },
    {
        ID = "Reduce",
        IsApplicable = function(facts) return facts.rarity ~= "Common" end,
    },
    {
        ID = "LevelUp",
        IsApplicable = function(facts) return facts.itemLevel < facts.characterLevel end,
    },
    {
        ID = "Masterwork",
        IsApplicable = function(facts)
            return facts.rarity ~= "Common" and not facts.hasGreatforgeBlockedTag
        end,
    },
    {
        ID = "Focalize",
        IsApplicable = function(facts) return facts.isArtifact end,
    },
    {
        ID = "Transmute",
        IsApplicable = function(facts) return facts.rarity ~= "Unique" end,
    },
    {
        ID = "RemoveMods",
        IsApplicable = function(facts)
            return facts.rarity ~= "Unique" and not facts.hasGreatforgeBlockedTag
        end,
    },
    {
        ID = "Combine",
        IsApplicable = function(facts)
            return facts.rarity ~= "Common"
                and (facts.rarity ~= "Unique" or facts.isArtifact)
                and not facts.hasGreatforgeBlockedTag
        end,
    },
    {
        ID = "AddSockets",
        IsApplicable = function(facts)
            return facts.runeSlotCount < Core.GetSocketLimit(facts)
        end,
    },
    {
        ID = "PIP_Engrave",
        IsApplicable = function(_) return true end,
    },
}

---Whether an option ID is in the registry.
---@param optionID string
---@return boolean
function Core.IsKnownOption(optionID)
    for _, option in ipairs(Core.OPTIONS) do
        if option.ID == optionID then
            return true
        end
    end
    return false
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

---Builds context menu entry descriptors for a set of options.
---@param optionIDs string[]
---@param labels table<string, string> Option ID → player-facing label.
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

return Core
