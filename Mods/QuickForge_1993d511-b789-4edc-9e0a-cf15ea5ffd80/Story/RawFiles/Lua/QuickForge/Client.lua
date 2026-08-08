---------------------------------------------
-- QuickForge client: "Greatforge" submenu in the item context menu.
-- Keyboard & mouse only by construction: Epip's context menu system
-- does not initialize on controller UIs.
---------------------------------------------

local QuickForge = Epip.GetFeature("QuickForge", "QuickForge", true) ---@type Features.QuickForge
local Core = QuickForge.Core
local ContextMenu = Client.UI.ContextMenu

local ROOT_ENTRY_ID = "QuickForge_Root"
local SUBMENU_ID = "QuickForge_Menu"
local JUMP_EVENT_ID = "QuickForge_Jump"

---Gathers the pure-logic facts Core.GetApplicableOptions() needs.
---@param item EclItem
---@param char EclCharacter
---@return QuickForge.ItemFacts
function QuickForge._GatherItemFacts(item, char)
    local socketedRuneCount = 0
    for _ in pairs(Item.GetRunes(item)) do
        socketedRuneCount = socketedRuneCount + 1
    end

    return {
        rarity = item.Stats.ItemTypeReal,
        isArtifact = Artifact.IsArtifact(item),
        socketedRuneCount = socketedRuneCount,
        itemLevel = item.Stats.Level,
        characterLevel = char.Stats.Level,
        hasGreatforgeBlockedTag = item:HasTag("AMER_GREATFORGEBLOCKED"),
        runeSlotCount = Item.GetRuneSlots(item),
        isWeapon = Item.IsWeapon(item),
        isTwoHanded = item.Stats.IsTwoHanded == true,
    }
end

---Whether any member of the client character's party is in combat —
---the same scope the Meditate skill's own gating uses.
---@return boolean
function QuickForge._IsPartyInCombat()
    for _, member in ipairs(Character.GetPartyMembers(Client.GetCharacter())) do
        if Character.IsInCombat(member) then
            return true
        end
    end
    return false
end

---Whether the Greatforge submenu should appear for an item at all.
---Surfaces covered: own inventory, equipped items, opened containers —
---all of which give the item an inventory root. World items (no root) and
---items rooted in non-player character inventories (e.g. pickpocketing)
---are excluded; the submenu is hidden entirely during combat.
---@param item EclItem?
---@return boolean
function QuickForge._ShouldShowSubmenu(item)
    if not QuickForge:IsEnabled() or not EpicEncounters.IsEnabled() then
        return false
    end
    if not item or not item.Stats or not Item.IsEquipment(item) then
        return false
    end
    if QuickForge._IsPartyInCombat() then
        return false
    end

    local inventoryRoot = Item.GetInventoryRoot(item)
    if not inventoryRoot then
        return false
    end
    if Entity.IsCharacter(inventoryRoot) and not Character.IsPlayer(inventoryRoot) then
        return false
    end

    return true
end

---Player-facing labels for all options, keyed by option ID.
---@return table<string, string>
function QuickForge._GetOptionLabels()
    local labels = {}
    for _, option in ipairs(Core.OPTIONS) do
        local tsk = QuickForge.TranslatedStrings["Label_" .. option.ID]
        if tsk then
            labels[option.ID] = tsk:GetString()
        end
    end
    return labels
end

ContextMenu.RegisterVanillaMenuHandler("Item", function(item)
    if not QuickForge._ShouldShowSubmenu(item) then return end

    ContextMenu.AddElement({
        {
            id = ROOT_ENTRY_ID,
            type = "subMenu",
            text = QuickForge.TranslatedStrings.Label_Greatforge:GetString() .. "...",
            subMenu = SUBMENU_ID,
        },
    })
end)

ContextMenu.RegisterMenuHandler(SUBMENU_ID, function(item)
    if not item or not Entity.IsItem(item) then return end

    local facts = QuickForge._GatherItemFacts(item, Client.GetCharacter())
    local menuEntries = Core.BuildMenuEntries(Core.GetApplicableOptions(facts), QuickForge._GetOptionLabels())

    local entries = {}
    for _, menuEntry in ipairs(menuEntries) do
        table.insert(entries, {
            id = menuEntry.ID,
            type = "button",
            text = menuEntry.Label,
            eventIDOverride = JUMP_EVENT_ID,
            params = {Option = menuEntry.Option},
        })
    end

    ContextMenu.AddSubMenu({
        menu = {
            id = SUBMENU_ID,
            entries = entries,
        },
    })
end)

ContextMenu.RegisterElementListener(JUMP_EVENT_ID, "buttonPressed", function(item, params)
    if not item or not Entity.IsItem(item) then return end

    Net.PostToServer(QuickForge.NETMSG_JUMP, {
        CharacterNetID = Client.GetCharacter().NetID,
        ItemNetID = item.NetID,
        Option = params.Option,
    })
end)
