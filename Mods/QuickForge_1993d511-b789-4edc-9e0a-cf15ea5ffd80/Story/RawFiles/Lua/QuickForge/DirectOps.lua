---------------------------------------------
-- QuickForge server: Direct Operations (ADR-0001).
--
-- Commits a Greatforge option in place through EE2's own request pipeline,
-- with no physical-UI session. The route (per the ADR amendment):
--
--   1. Activate the internal-logic goal AMER_GLO_UI_Greatforge_Internal
--      (its procs/queries do not exist while nobody is in a physical UI),
--      and probe that it responds before relying on it — Epip treated
--      same-tick availability as empirical, so we verify at runtime.
--   2. Seed the instance DBs EE2's pipeline reads, under synthetic
--      instance 0: BenchedItem (validation + cost multipliers),
--      SelectedOption_Cost (what the funds check charges), and
--      CraftObject_Reserved (a reserved helper container standing in for
--      the forge's craft object).
--   3. Validate via EE2's own QRY_AMER_UI_Greatforge_InvalidSelection and
--      cost via QRY_AMER_UI_Greatforge_GenerateCost — never our own math.
--      (One documented exception: AddSockets validity uses Core's socket
--      rule, because Epip's ItemHasMaxSockets reads the first BenchedItem
--      row globally; see ADR-0001.)
--   4. Commit via PROC_AMER_UI_Greatforge_OptionRequested — NOT DoCraft —
--      so EE2's funds check, insufficient-funds message, payment, and all
--      third-party DoCraft listeners (Epip's Drill Sockets, Engrave,
--      Empower fix) run unchanged. The whole chain is synchronous; DoCraft
--      / Funds_RequestFailed listeners tell us which way it went.
--   5. Own what EE2's UI would have done afterwards: drain the helper
--      container to the character (the UI-coupled MoveAllItemsTo
--      completion rule never fires with no live instance), release it,
--      delete our seeded rows, and complete the internal goal — the latter
--      only while no player is inside a physical UI.
--
-- Direct Operations refuse outright while ANY player is inside a real
-- Greatforge session (offering the Jump instead), so the
-- shared-internal-goal concurrent case is structurally unreachable.
---------------------------------------------

local QuickForge = Epip.GetFeature("QuickForge", "QuickForge", true) ---@type Features.QuickForge
local Core = QuickForge.Core

local GREATFORGE_UI = "AMER_UI_Greatforge"
local INTERNAL_GOAL = "AMER_GLO_UI_Greatforge_Internal"
-- Synthetic instance for the seeded DBs. Real sessions use level-template
-- instances, and Direct Operations refuse while any Greatforge session
-- exists, so this never collides; Epip's QuickReduce uses instance 0 for
-- cost queries too.
local INSTANCE = 0
-- Drain delay for loot generated into the helper container; Epip's
-- QuickReduce drains its container after 200 ms.
local CONTAINER_DRAIN_DELAY = 0.25
-- How long to wait for Cull's async item regeneration before giving up.
-- EE2's own treasure dispatcher abandons requests after 200 ms
-- (_AMER_GEN_QrysProcs_GenerateTreasure.txt); by 2 s the request is
-- certainly either delivered or dropped.
local REBUILD_TIMEOUT = 2.0

---@class QuickForge.ItemSpecs Item facts in EE2's BenchedItem vocabulary.
---@field Level number
---@field ItemType string Rarity per `ItemTypeReal`.
---@field Slot string
---@field SubType string
---@field Handedness integer
---@field GoldValue number

---@class QuickForge.OperationCost What EE2 charges for an option.
---@field Amount integer
---@field MatType string "GreatforgeFrags" or "Gold".
---@field Root string Root template of the material, or "Gold".

---Reads the single value EE2's output-DB protocol left behind (each query
---deletes its previous output row before writing).
---@param outputDB any One of the single-column DB_AMER_*_OUTPUT_* databases.
---@return any?
local function GetOutputValue(outputDB)
    local rows = outputDB:Get(nil)
    return rows and rows[1] and rows[1][1]
end

---Osiris's own REAL->INTEGER conversion, exactly as EE2's scripts convert
---(Integer(_Real, _Int)) — no drift from Lua rounding.
---@param real number
---@return integer
local function ToOsirisInteger(real)
    local converted, value = pcall(Osi.Integer, real)
    if not converted or not value then
        value = math.floor(real)
    end
    return value
end

---@return QuickForge.DirectOpState
function QuickForge._GetDirectOpState()
    local sessions = Osi.DB_AMER_UI_UsersInUI:Get(nil, GREATFORGE_UI, nil)
    return {
        partyInCombat = Osi.QRY_AMER_GEN_IsPartyInCombat() == true,
        anyPlayerInGreatforge = sessions ~= nil and sessions[1] ~= nil,
    }
end

---Whether the internal goal's queries actually respond after activation.
---Same-tick availability after PROC_AMER_GEN_Goal_Activate is empirically
---shaky (Epip re-declared one internal query over it), so probe with a
---side-effect-free internal query instead of assuming.
---@return boolean
function QuickForge._IsInternalGoalResponsive()
    local ok, responsive = pcall(function()
        return Osi.QRY_AMER_UI_Greatforge_OptionRequested_GetFinalCost(
            INSTANCE, "QuickForge_Probe", "GreatforgeFrags", 1) == true
    end)
    return ok and responsive
end

---Gathers the BenchedItem 9-tuple's item columns through EE2's own
---always-active queries (the same ones Epip's QuickReduce chains).
---@param item EsvItem
---@return QuickForge.ItemSpecs?
function QuickForge._GetItemSpecs(item)
    local guid = item.MyGuid

    if not Osi.QRY_AMER_GEN_GetItemSlot(guid) then return nil end
    local slot = GetOutputValue(Osi.DB_AMER_GEN_OUTPUT_String)
    if not slot then return nil end

    if not Osi.QRY_AMER_Deltamods_GenerateOnItem_GetItemSpecs_GetSubType(guid, slot) then return nil end
    local subType = GetOutputValue(Osi.DB_AMER_GEN_OUTPUT_String)
    local handedness = GetOutputValue(Osi.DB_AMER_GEN_OUTPUT_Integer)
    if not subType or not handedness then return nil end

    local goldValue = Osi.ItemGetGoldValue(guid)
    if not goldValue then return nil end

    return {
        Level = item.Stats.Level * 1.0,
        ItemType = item.Stats.ItemTypeReal,
        Slot = slot,
        SubType = subType,
        Handedness = handedness,
        GoldValue = goldValue * 1.0,
    }
end

---@param char EsvCharacter
---@param item EsvItem
---@param specs QuickForge.ItemSpecs
function QuickForge._SeedBench(char, item, specs)
    Osi.DB_AMER_UI_Greatforge_BenchedItem(INSTANCE, char.MyGuid, item.MyGuid,
        specs.Level, specs.ItemType, specs.Slot, specs.SubType, specs.Handedness, specs.GoldValue)
end

function QuickForge._ClearSeededRows()
    Osi.DB_AMER_UI_Greatforge_BenchedItem:Delete(INSTANCE, nil, nil, nil, nil, nil, nil, nil, nil)
    Osi.DB_AMER_UI_Greatforge_SelectedOption_Cost:Delete(INSTANCE, nil, nil, nil)
    -- Masterwork picker rows/selection. EE2's DoCraft deletes the selection
    -- on success; the validated rows (and both, on a refused commit) are
    -- page-leave cleanup in EE2's UI, so here they are ours.
    Osi.DB_AMER_UI_Greatforge_Masterwork_ValidatedMods:Delete(INSTANCE,
        nil, nil, nil, nil, nil, nil, nil, nil, nil)
    Osi.DB_AMER_UI_Greatforge_Masterwork_SelectedMod:Delete(INSTANCE, nil)
    -- Cull rows/selection: EE2's DoCraft runs RemoveMods_Cleanup itself on
    -- success, but a refused commit (e.g. funds) leaves our seeds behind.
    Osi.DB_AMER_UI_Greatforge_RemoveMods_ModsOfItem:Delete(INSTANCE, nil, nil)
    Osi.DB_AMER_UI_Greatforge_RemoveMods_SelectedMod:Delete(INSTANCE, nil)
    -- Combine's Donor row: EE2 clears it on page-leave, never in DoCraft.
    Osi.DB_AMER_UI_Greatforge_Combine_ItemToAdd:Delete(INSTANCE, nil, nil)
end

---Whether EE2 (or, for AddSockets, Core's own socket rule) rejects the
---option for the benched item. EE2's rules open their own reason message
---box on the character's client as a side effect; the AddSockets rule shows
---none (the client covers that case, see ForgeWindow.lua).
---Requires the bench seeded and the internal goal active.
---@param char EsvCharacter
---@param item EsvItem
---@param option string
---@return boolean
function QuickForge._IsInvalidSelection(char, item, option)
    if option == "AddSockets" then
        -- ADR-0001's documented exception: Epip's InvalidSelection rule for
        -- AddSockets delegates to ItemHasMaxSockets, which reads the first
        -- BenchedItem row globally — bench-coupled and multiplayer-unsafe.
        local facts = {
            isWeapon = Item.IsWeapon(item),
            isTwoHanded = item.Stats.IsTwoHanded == true,
        }
        return Item.GetRuneSlots(item) >= Core.GetSocketLimit(facts)
    end
    return Osi.QRY_AMER_UI_Greatforge_InvalidSelection(char.MyGuid, option) == true
end

---EE2's live cost for the option on the benched item.
---Requires the bench seeded and the internal goal active.
---@param option string
---@param specs QuickForge.ItemSpecs
---@return QuickForge.OperationCost? Nil when EE2 has no cost row or the query fails.
function QuickForge._GenerateCost(option, specs)
    local costRows = Osi.DB_AMER_UI_Greatforge_Option_Cost:Get(option, nil, nil, nil)
    local costRow = costRows and costRows[1]
    if not costRow then return nil end
    local matType, root, matValue = costRow[2], costRow[3], costRow[4]

    if not Osi.QRY_AMER_UI_Greatforge_GenerateCost(INSTANCE, option, matType, specs.Level,
        specs.ItemType, specs.Slot, specs.SubType, specs.Handedness, specs.GoldValue, matValue) then
        return nil
    end
    local cost = GetOutputValue(Osi.DB_AMER_UI_Greatforge_OUTPUT_Cost)
    if not cost then return nil end

    -- Osiris's own REAL->INTEGER conversion, exactly as EE2's cost list does
    -- (Integer(_MatCost, _MatCostInt)) — no drift from Lua rounding.
    local converted, amount = pcall(Osi.Integer, cost)
    if not converted or not amount then
        amount = math.floor(cost)
    end

    return {Amount = amount, MatType = matType, Root = root}
end

---The player's funds matching a cost's material, measured exactly as EE2's
---funds check measures them (user-scoped, bags excluded).
---@param char EsvCharacter
---@param cost {MatType: string, Root: string}
---@return integer
function QuickForge._GetFunds(char, cost)
    if cost.MatType == "Gold" then
        return Osi.UserGetGold(char.MyGuid) or 0
    end
    if not Osi.QRY_AMER_UI_Funds_CheckFunds_GetUserFunds(char.MyGuid, cost.Root) then
        return 0
    end
    return GetOutputValue(Osi.DB_AMER_GEN_OUTPUT_Integer) or 0
end

---The material an option charges, from EE2's static cost list — without
---computing an amount (Masterwork's amounts are per-Property).
---@param option string
---@return {MatType: string, Root: string}?
function QuickForge._GetOptionMaterial(option)
    local costRows = Osi.DB_AMER_UI_Greatforge_Option_Cost:Get(option, nil, nil, nil)
    local costRow = costRows and costRows[1]
    if not costRow then return nil end
    return {MatType = costRow[2], Root = costRow[3]}
end

---------------------------------------------
-- PICKER ROWS
---------------------------------------------

---Builds the Masterwork picker rows from EE2's own uptier derivation:
---QRY_..._ValidateMods consumes the CountedMods left behind by EE2's
---InvalidSelection("Masterwork") run (which _RunBenched just performed) and
---writes Masterwork_ValidatedMods; each row's cost comes from EE2's own
---GetCostInt query (the number EE2's runtime reads back out of rendered UI
---text — unreadable here, so computed via the same query EE2's page uses).
---Requires the bench seeded, the internal goal active, and EE2's
---InvalidSelection("Masterwork") to have just run for this item.
---@param specs QuickForge.ItemSpecs
---@return QuickForge.PickerRow[]?, table<string, {Index: integer, Deltamod: string, UptierLevel: number}>?
function QuickForge._BuildMasterworkRows(specs)
    -- The item's current value per property, from the CountedMods snapshot
    -- (EE2 de-duplicates per prefix keeping the highest value).
    local currentByPrefix = {}
    local counted = Osi.DB_AMER_Detamods_OUTPUT_CountedMods:Get(nil, nil, nil, nil, nil)
    for _, row in ipairs(counted or {}) do
        currentByPrefix[row[3]] = row[5]
    end

    Osi.QRY_AMER_UI_Greatforge_Masterwork_InitConfirmPage_ValidateMods(
        INSTANCE, specs.Slot, specs.SubType, specs.Handedness)
    local validated = Osi.DB_AMER_UI_Greatforge_Masterwork_ValidatedMods:Get(
        INSTANCE, nil, nil, nil, nil, nil, nil, nil, nil, nil)
    if not validated or not validated[1] then return nil end

    local itemLevel = ToOsirisInteger(specs.Level)
    local rows, seeds = {}, {}
    for _, v in ipairs(validated) do
        local index, prefix, deltamod, value = v[2], v[3], v[4], v[5]
        local uptierLevel, benchedModLevel = v[6], v[7]
        local deltamodRarity, benchedRarity, decayChance = v[8], v[9], v[10]

        local class = Core.ClassifyMasterworkRow({
            uptierDeltamod = deltamod,
            uptierLevel = ToOsirisInteger(uptierLevel),
            itemLevel = itemLevel,
        })

        local cost = nil
        if deltamod ~= "NONE"
            and Osi.QRY_AMER_UI_Greatforge_Masterwork_InitConfirmPage_GetCostInt(
                uptierLevel, benchedModLevel, deltamodRarity, benchedRarity, decayChance) then
            cost = GetOutputValue(Osi.DB_AMER_GEN_OUTPUT_Integer)
        end

        table.insert(rows, {
            Key = prefix,
            Prefix = prefix,
            Current = currentByPrefix[prefix],
            Uptiered = deltamod ~= "NONE" and value or nil,
            UptierLevel = ToOsirisInteger(uptierLevel),
            Cost = cost,
            Eligible = class.eligible,
            Reason = class.reason,
        })
        seeds[prefix] = {Index = index, Deltamod = deltamod, UptierLevel = uptierLevel}
    end
    table.sort(rows, function(a, b) return (seeds[a.Key].Index) < (seeds[b.Key].Index) end)
    return rows, seeds
end

---Builds the Cull picker rows: the item's Properties as EE2 counted them.
---Reads the CountedMods snapshot left behind by EE2's
---InvalidSelection("RemoveMods") run (which _RunBenched just performed);
---EE2 de-duplicates per prefix keeping the highest value, so the prefix is
---a stable row key. Every row is selectable — Cull keeps any one Property.
---@return QuickForge.PickerRow[]?, table<string, {Index: integer, Deltamod: string}>?
function QuickForge._BuildKeepRows()
    local counted = Osi.DB_AMER_Detamods_OUTPUT_CountedMods:Get(nil, nil, nil, nil, nil)
    if not counted or not counted[1] then return nil end

    local rows, seeds = {}, {}
    for _, row in ipairs(counted) do
        local index, prefix, deltamod, value = row[1], row[3], row[4], row[5]
        table.insert(rows, {
            Key = prefix,
            Prefix = prefix,
            Current = value,
            Eligible = true,
        })
        seeds[prefix] = {Index = index, Deltamod = deltamod}
    end
    return rows, seeds
end

---------------------------------------------
-- COMBINE DONORS
---------------------------------------------

---The benched-side context Combine's donor checks compare against: the
---target's mods (from the CountedMods snapshot EE2's
---InvalidSelection("Combine") run left behind — the same snapshot EE2's
---own page stashes into Combine_BenchedMods) and the target's rarity as a
---REAL, converted through EE2's own DB_AMER_GEN_ItemRarity mapping.
---Must be captured before any donor iteration clobbers CountedMods.
---@param specs QuickForge.ItemSpecs
---@return {BenchedMods: {Prefix: string, Deltamod: string, Value: integer}[], RarityReal: number}
function QuickForge._GetCombineContext(specs)
    local benchedMods = {}
    local counted = Osi.DB_AMER_Detamods_OUTPUT_CountedMods:Get(nil, nil, nil, nil, nil)
    for _, row in ipairs(counted or {}) do
        table.insert(benchedMods, {Prefix = row[3], Deltamod = row[4], Value = row[5]})
    end

    local rarityRows = Osi.DB_AMER_GEN_ItemRarity:Get(nil, specs.ItemType)
    local rarityInt = rarityRows and rarityRows[1] and rarityRows[1][1] or -1
    return {BenchedMods = benchedMods, RarityReal = rarityInt * 1.0}
end

---Runs EE2's donor checks for one candidate, silently: the page-driven
---wrapper queries open message boxes, so this calls the underlying
---always-active Deltamods queries and composes their verdicts through
---Core.EvaluateDonor (which owns the ordering and the rarity exception).
---Clobbers the CountedMods output DB.
---@param item EsvItem The target (benched) item.
---@param specs QuickForge.ItemSpecs
---@param context {BenchedMods: {Prefix: string, Deltamod: string, Value: integer}[], RarityReal: number}
---@param candidate EsvItem
---@return {valid: boolean, reason: string?}, string? donorPrefix, string? donorDeltamod
function QuickForge._EvaluateDonorCandidate(item, specs, context, candidate)
    local facts = {
        isTargetItem = candidate.MyGuid == item.MyGuid,
        modCount = 0,
        hasSamePrefix = false,
        hasExcludedPrefix = false,
        rollFailReason = nil,
    }
    local donorPrefix, donorDeltamod, donorValue

    if not facts.isTargetItem then
        Osi.QRY_AMER_Deltamods_IterateMods_NotImplicit(candidate.MyGuid)
        local counted = Osi.DB_AMER_Detamods_OUTPUT_CountedMods:Get(nil, nil, nil, nil, nil) or {}
        facts.modCount = #counted
        if facts.modCount == 1 then
            donorPrefix, donorDeltamod, donorValue = counted[1][3], counted[1][4], counted[1][5]

            for _, benched in ipairs(context.BenchedMods) do
                if benched.Prefix == donorPrefix then
                    facts.hasSamePrefix = true
                    break
                end
            end

            if not facts.hasSamePrefix then
                for _, benched in ipairs(context.BenchedMods) do
                    if Osi.QRY_AMER_Deltamods_PrefixesExclusive(donorPrefix, donorValue,
                        benched.Prefix, benched.Value, specs.Slot, specs.SubType, specs.Handedness) == true then
                        facts.hasExcludedPrefix = true
                        break
                    end
                end
            end

            if not facts.hasSamePrefix and not facts.hasExcludedPrefix
                and Osi.QRY_AMER_Deltamods_CanItemRollPrefixValue(context.RarityReal, specs.Level,
                    donorPrefix, donorValue, specs.Slot, specs.SubType, specs.Handedness) ~= true then
                local reasonRows = Osi.DB_AMER_Deltamods_CanItemRollPrefixValue_FailReason:Get(nil)
                facts.rollFailReason = reasonRows and reasonRows[1] and reasonRows[1][1] or "Unknown"
                if facts.rollFailReason == "Rarity" then
                    -- EE2's own exception pops the row so it cannot leak
                    -- into a later check (:2067); mirror that.
                    Osi.DB_AMER_Deltamods_CanItemRollPrefixValue_FailReason:Delete("Rarity")
                end
            end
        end
    end

    return Core.EvaluateDonor(facts), donorPrefix, donorDeltamod
end

---Builds the Combine donor rows: every item across the whole party's
---inventories (equipped items excluded) that passes EE2's donor checks.
---An empty result is a legitimate state — the window shows it explicitly.
---Also reports the refused candidates with their reasons (the suffixes of
---EE2's own message TSKs, or "QuickForge_Equipped"), keyed by NetID string,
---so a refused drop on the Donor slot can name its reason.
---@param char EsvCharacter
---@param item EsvItem
---@param specs QuickForge.ItemSpecs
---@return QuickForge.PickerRow[], table<string, {Guid: string, Deltamod: string}>, table<string, string>
function QuickForge._BuildDonorRows(char, item, specs)
    local context = QuickForge._GetCombineContext(specs)

    local rows, seeds, invalid = {}, {}, {}
    local candidates = Item.GetItemsInPartyInventory(char, function(candidate)
        return candidate.Stats ~= nil and Item.IsEquipment(candidate)
    end, true)
    for _, candidate in ipairs(candidates) do
        if Osi.IsEquipped(candidate.MyGuid) == true then
            invalid[tostring(candidate.NetID)] = "QuickForge_Equipped"
        else
            local verdict, donorPrefix, donorDeltamod =
                QuickForge._EvaluateDonorCandidate(item, specs, context, candidate)
            if verdict.valid then
                table.insert(rows, {
                    Key = candidate.MyGuid,
                    ItemNetID = candidate.NetID,
                    Prefix = donorPrefix,
                    Eligible = true,
                })
                seeds[candidate.MyGuid] = {Guid = candidate.MyGuid, Deltamod = donorDeltamod}
            else
                invalid[tostring(candidate.NetID)] = verdict.reason
            end
        end
    end
    return rows, seeds, invalid
end

---Reserves an invisible helper container to stand in for the forge's craft
---object: required for the Funds_RequestSuccess -> DoCraft hop, and the
---target of item-generating options (Dismantle, Transmute).
---@return string? containerGuid
function QuickForge._ReserveCraftContainer()
    if not Osi.QRY_AMER_GEN_GetHelperObjectAtPosition(1.0, 1.0, 1.0, 1) then return nil end
    local container = GetOutputValue(Osi.DB_AMER_GEN_OUTPUT_Item)
    if not container then return nil end
    Osi.DB_AMER_UI_Greatforge_CraftObject_Reserved(INSTANCE, container)
    return container
end

---Drains the container to the character, releases it, and completes the
---internal goal if no player is inside a physical UI.
---@param containerGuid string
---@param charGuid string
function QuickForge._ReleaseCraftContainer(containerGuid, charGuid)
    Osi.MoveAllItemsTo(containerGuid, charGuid)
    Osi.DB_AMER_UI_Greatforge_CraftObject_Reserved:Delete(INSTANCE, nil)
    Osi.PROC_AMER_GEN_UnreserveHelperObject(containerGuid)
    QuickForge._TryCompleteInternalGoal()
end

function QuickForge._TryCompleteInternalGoal()
    -- Cull's regeneration return rule lives inside the internal goal; while
    -- a rebuilt item is still in flight, completing the goal would strand it.
    if QuickForge._PendingRebuilds[1] then
        return
    end
    local users = Osi.DB_AMER_UI_UsersInUI:Get(nil, nil, nil)
    if not users or not users[1] then
        -- Guarded on SysIsActive internally; safe if already complete.
        Osi.PROC_AMER_GEN_Goal_Complete(INTERNAL_GOAL)
    end
end

---------------------------------------------
-- CULL (RemoveMods) ASYNC REBUILD
---------------------------------------------

-- Cull's DoCraft destroys the item and requests a regenerated replacement
-- through EE2's treasure system; the return rule (delivery to the
-- character) runs inside the internal goal, asynchronously, up to ~200 ms
-- later. Each watch token keeps the goal alive across one such round-trip.
---@type {Done: boolean}[]
QuickForge._PendingRebuilds = {}
-- A dropped round-trip left a request row behind that could not be swept
-- yet because another rebuild was still in flight.
QuickForge._RebuildSweepDeferred = false

---Starts watching one pending regeneration round-trip. The goal is held
---active until EE2's return rule fires — or until the timeout, after which
---the request is certainly dropped (EE2's own dispatcher abandons requests
---after 200 ms) and only the leftover request row remains to sweep.
function QuickForge._BeginRebuildWatch()
    local token = {Done = false}
    table.insert(QuickForge._PendingRebuilds, token)

    Timer.Start(REBUILD_TIMEOUT, function(_)
        QuickForge._FinishRebuildWatch(token, true)
    end)
end

---Sweeps every leftover Cull regeneration request row of ours. The rows
---are only distinguishable by EE2's global request counter, so this may
---run only while no rebuild of ours is still in flight.
function QuickForge._SweepRebuildRequests()
    Osi.DB_AMER_UI_Greatforge_RemoveMods_NewItemRequest:Delete(
        nil, INSTANCE, nil, nil, nil, nil, nil, nil, nil)
end

---@param token {Done: boolean}
---@param dropped boolean True when the round-trip timed out instead of returning.
function QuickForge._FinishRebuildWatch(token, dropped)
    if token.Done then return end
    token.Done = true

    for i, pending in ipairs(QuickForge._PendingRebuilds) do
        if pending == token then
            table.remove(QuickForge._PendingRebuilds, i)
            break
        end
    end
    -- Sweep only once nothing else is in flight: request rows are not
    -- per-watch distinguishable, and a broad sweep here would wipe a
    -- concurrent rebuild's live request, stranding its item. A drop that
    -- cannot sweep yet defers to whichever finish empties the list.
    if dropped then
        QuickForge._RebuildSweepDeferred = true
    end
    if QuickForge._RebuildSweepDeferred and not QuickForge._PendingRebuilds[1] then
        QuickForge._SweepRebuildRequests()
        QuickForge._RebuildSweepDeferred = false
    end
    QuickForge._TryCompleteInternalGoal()
end

-- The rebuilt item was delivered (EE2's own return rule has already
-- regenerated its mods, re-applied the kept Property, and moved it to the
-- character): release the oldest watch.
Ext.Osiris.RegisterListener("PROC_AMER_GEN_GenerateTreasure_Returned", 4, "after",
    function(_, _, returnEvent, _)
        if returnEvent ~= "AMER_UI_Greatforge_RemoveMods_NewItemMade" then return end
        local token = QuickForge._PendingRebuilds[1]
        if token then
            QuickForge._FinishRebuildWatch(token, false)
        end
    end)

---------------------------------------------
-- COMMIT OUTCOME LISTENERS
---------------------------------------------

-- Set for the duration of the (synchronous) OptionRequested call; the
-- listeners record which way EE2's pipeline went.
---@type {Crafted: boolean?, FundsFailed: boolean?}?
QuickForge._CraftWatch = nil

Ext.Osiris.RegisterListener("PROC_AMER_UI_Greatforge_DoCraft", 11, "after",
    function(instance, _, _, _, _, _, _, _, _, _, _)
        if QuickForge._CraftWatch and tonumber(instance) == INSTANCE then
            QuickForge._CraftWatch.Crafted = true
        end
    end)

Ext.Osiris.RegisterListener("PROC_AMER_UI_Funds_RequestFailed", 4, "after",
    function(instance, ui, _, _)
        if QuickForge._CraftWatch and tonumber(instance) == INSTANCE and ui == GREATFORGE_UI then
            QuickForge._CraftWatch.FundsFailed = true
        end
    end)

---------------------------------------------
-- REQUEST HANDLERS
---------------------------------------------

---Validates a preview/commit payload.
---@param payload table
---@return EsvCharacter?, EsvItem?, string?
local function GetRequestArgs(payload)
    local char, item = payload:GetCharacter(), payload:GetItem()
    local option = payload.Option
    if not char or not item or type(option) ~= "string" or Core.GetRoute(option) ~= "direct" then
        return nil
    end
    return char, item, option
end

---Runs a Direct Operation stage with the full shared envelope: gating, goal
---activation (probed), item specs, bench seeding, and validation before it;
---seeded-row cleanup and conditional goal completion after it. The stage
---runs with the bench seeded and the selection validated, and returns the
---outcome plus any extra reply fields; on "success" the goal is left active
---for the stage's own deferred cleanup (the container-drain timer).
---@param char EsvCharacter
---@param item EsvItem
---@param option string
---@param stage fun(specs: QuickForge.ItemSpecs): QuickForge.OperationOutcome, table?
---@return QuickForge.OperationOutcome, table?
function QuickForge._RunBenched(char, item, option, stage)
    local plan = Core.PlanDirectOperation(QuickForge._GetDirectOpState())
    if plan == "blocked_combat" then
        -- Same message the Meditate skill shows.
        Osi.OpenMessageBox(char.MyGuid, "AMER_UI_GEN_MeditateBlocked_PartyInCombat")
        return "blocked_combat"
    elseif plan == "blocked_session" then
        return "blocked_session"
    end

    Osi.PROC_AMER_GEN_Goal_Activate(INTERNAL_GOAL)

    local outcome, extra
    if not QuickForge._IsInternalGoalResponsive() then
        outcome = "error"
    else
        local specs = QuickForge._GetItemSpecs(item)
        if not specs then
            outcome = "error"
        else
            QuickForge._SeedBench(char, item, specs)
            if QuickForge._IsInvalidSelection(char, item, option) then
                outcome = "invalid" -- EE2 (or the client, for AddSockets) shows the reason.
            else
                outcome, extra = stage(specs)
            end
        end
    end

    QuickForge._ClearSeededRows()
    if outcome ~= "success" then
        QuickForge._TryCompleteInternalGoal()
    end
    return outcome, extra
end

---Builds the preview reply's cost/picker fields for an option.
---@param char EsvCharacter
---@param item EsvItem
---@param option string
---@param specs QuickForge.ItemSpecs
---@return QuickForge.OperationOutcome, table?
function QuickForge._BuildPreview(char, item, option, specs)
    local picker = Core.GetPicker(option)

    if picker == "property_uptier" then
        -- Per-row costs; the window has no flat cost line until a pick.
        local rows = QuickForge._BuildMasterworkRows(specs)
        local mat = QuickForge._GetOptionMaterial(option)
        if not rows or not mat then return "error" end
        return "ok", {
            MatType = mat.MatType,
            Funds = QuickForge._GetFunds(char, mat),
            Rows = rows,
        }
    end

    local cost = QuickForge._GenerateCost(option, specs)
    if not cost then return "error" end

    local rows, invalidDonors = nil, nil
    if picker == "property_keep" then
        rows = QuickForge._BuildKeepRows()
        if not rows then return "error" end
    elseif picker == "donor" then
        -- A donorless party is a legitimate preview: the window opens with
        -- an explicit empty state, not a refusal dialog.
        rows, _, invalidDonors = QuickForge._BuildDonorRows(char, item, specs)
    end
    return "ok", {
        MatType = cost.MatType,
        Cost = cost.Amount,
        Funds = QuickForge._GetFunds(char, cost),
        Rows = rows,
        InvalidDonors = invalidDonors,
    }
end

---What a commit charges and seeds. Charged amounts always come from EE2's
---queries run now, never from the client's preview.
---@class QuickForge.CommitPlan
---@field Cost integer
---@field MatType string
---@field Root string
---@field Seed fun()? Seeds the option's selection DBs just before OptionRequested.
---@field OnCrafted fun()? Runs right after EE2's DoCraft accepted the commit.

---Resolves a commit's plan, re-deriving and re-validating any picker
---selection against EE2's current data. Returns a refusal outcome instead
---when the commit may not proceed.
---@param char EsvCharacter
---@param item EsvItem
---@param option string
---@param specs QuickForge.ItemSpecs
---@param selectionKey string?
---@return QuickForge.OperationOutcome? refusal
---@return QuickForge.CommitPlan?
function QuickForge._PrepareCommit(char, item, option, specs, selectionKey)
    local picker = Core.GetPicker(option)

    if picker == "property_uptier" then
        local rows, seeds = QuickForge._BuildMasterworkRows(specs)
        if not rows then return "error" end
        local row = Core.FindPickerRow(rows, selectionKey)
        if not row then return "stale_selection" end
        local seed = seeds[row.Key]
        -- EE2's own selection gates, re-run at commit time; each opens its
        -- reason box on the character's client when it refuses (the same
        -- boxes the Greatforge page shows).
        if Osi.QRY_AMER_UI_Greatforge_Masterwork_PropertyMaxed(char.MyGuid, seed.Deltamod) == true then
            return "invalid"
        end
        if Osi.QRY_AMER_UI_Greatforge_Masterwork_PropertyLevelTooHigh(
            char.MyGuid, specs.Level, seed.UptierLevel) == true then
            return "invalid"
        end
        local mat = QuickForge._GetOptionMaterial(option)
        if not row.Cost or not mat then return "error" end
        return nil, {
            Cost = row.Cost,
            MatType = mat.MatType,
            Root = mat.Root,
            Seed = function()
                Osi.DB_AMER_UI_Greatforge_Masterwork_SelectedMod(INSTANCE, seed.Index)
            end,
        }
    end

    if picker == "property_keep" then
        local rows, seeds = QuickForge._BuildKeepRows()
        if not rows then return "error" end
        local row = Core.FindPickerRow(rows, selectionKey)
        if not row then return "stale_selection" end
        local cost = QuickForge._GenerateCost(option, specs)
        if not cost then return "error" end
        return nil, {
            Cost = cost.Amount,
            MatType = cost.MatType,
            Root = cost.Root,
            Seed = function()
                -- The full row list plus the kept row's index, exactly what
                -- EE2's confirm page would have seeded; DoCraft joins
                -- SelectedMod -> ModsOfItem and runs its own cleanup.
                for _, seeded in pairs(seeds) do
                    Osi.DB_AMER_UI_Greatforge_RemoveMods_ModsOfItem(
                        INSTANCE, seeded.Index, seeded.Deltamod)
                end
                Osi.DB_AMER_UI_Greatforge_RemoveMods_SelectedMod(INSTANCE, seeds[row.Key].Index)
            end,
            OnCrafted = function()
                -- The old item is gone and the regenerated one is in
                -- flight; hold the internal goal open across the
                -- round-trip so EE2's return rule can deliver it.
                QuickForge._BeginRebuildWatch()
            end,
        }
    end

    if picker == "donor" then
        -- Re-validate the chosen Donor against EE2's checks right now: it
        -- must still exist, sit unequipped in the party's inventories, and
        -- pass every donor rule against the target's current mods. The
        -- server-computed valid-Donor set stays authoritative; anything
        -- less refuses as stale through the failure dialog.
        local context = QuickForge._GetCombineContext(specs)
        local resolved, donor = pcall(Item.Get, selectionKey)
        if not resolved or not donor then return "stale_selection" end
        local inParty = Osi.ItemIsInPartyInventory(donor.MyGuid, char.MyGuid, 0)
        if inParty ~= 1 and inParty ~= true then return "stale_selection" end
        if Osi.IsEquipped(donor.MyGuid) == true then return "stale_selection" end
        local verdict, _, donorDeltamod = QuickForge._EvaluateDonorCandidate(item, specs, context, donor)
        if not verdict.valid or not donorDeltamod then return "stale_selection" end

        local cost = QuickForge._GenerateCost(option, specs)
        if not cost then return "error" end
        return nil, {
            Cost = cost.Amount,
            MatType = cost.MatType,
            Root = cost.Root,
            Seed = function()
                -- What EE2's page stores when a Donor is dropped on the
                -- bench; DoCraft consumes the Donor and grants its
                -- Property from this row.
                Osi.DB_AMER_UI_Greatforge_Combine_ItemToAdd(INSTANCE, donor.MyGuid, donorDeltamod)
            end,
        }
    end

    local cost = QuickForge._GenerateCost(option, specs)
    if not cost then return "error" end
    return nil, {Cost = cost.Amount, MatType = cost.MatType, Root = cost.Root}
end

Net.RegisterListener(QuickForge.NETMSG_PREVIEW_REQUEST, function(payload)
    local char, item, option = GetRequestArgs(payload)
    if not char then return end

    local outcome, costFields = QuickForge._RunBenched(char, item, option, function(specs)
        return QuickForge._BuildPreview(char, item, option, specs)
    end)

    local reply = {
        ItemNetID = item.NetID,
        Option = option,
        Outcome = outcome,
    }
    for field, value in pairs(costFields or {}) do
        reply[field] = value
    end
    Net.PostToCharacter(char, QuickForge.NETMSG_PREVIEW, reply)
end)

Net.RegisterListener(QuickForge.NETMSG_COMMIT, function(payload)
    local char, item, option = GetRequestArgs(payload)
    if not char then return end
    -- Captured up front: Dismantle/Transmute destroy the item entity during
    -- the commit, invalidating it before the reply is built.
    local itemNetID = item.NetID

    -- A picker commit without a well-formed selection cannot proceed, but
    -- must still reply (never-silent): the client is waiting on this to
    -- re-enable its window.
    local selectionKey = payload.SelectionKey
    if (selectionKey ~= nil and type(selectionKey) ~= "string")
        or (Core.GetPicker(option) ~= nil and selectionKey == nil) then
        Net.PostToCharacter(char, QuickForge.NETMSG_COMMIT_RESULT, {
            ItemNetID = itemNetID,
            Option = option,
            Outcome = "error",
        })
        return
    end

    local outcome = QuickForge._RunBenched(char, item, option, function(specs)
        local refusal, plan = QuickForge._PrepareCommit(char, item, option, specs, selectionKey)
        if refusal then return refusal end

        local container = QuickForge._ReserveCraftContainer()
        if not container then return "error" end

        Osi.DB_AMER_UI_Greatforge_SelectedOption_Cost(INSTANCE, plan.MatType, plan.Root, plan.Cost)
        if plan.Seed then plan.Seed() end

        QuickForge._CraftWatch = {}
        Osi.PROC_AMER_UI_Greatforge_OptionRequested(INSTANCE, char.MyGuid, option)
        local watch = QuickForge._CraftWatch
        QuickForge._CraftWatch = nil

        if watch.Crafted then
            if plan.OnCrafted then plan.OnCrafted() end
            -- Loot lands in the reserved container (the UI-coupled completion
            -- rule that would hand it over never fires). Drain now and once
            -- more shortly after, then release and complete the goal.
            local containerGuid, charGuid = container, char.MyGuid
            Osi.MoveAllItemsTo(containerGuid, charGuid)
            Timer.Start(CONTAINER_DRAIN_DELAY, function(_)
                QuickForge._ReleaseCraftContainer(containerGuid, charGuid)
            end)
            return "success"
        end

        QuickForge._ReleaseCraftContainer(container, char.MyGuid)
        if watch.FundsFailed then
            return "insufficient_funds" -- EE2 has shown its box.
        end
        return "error"
    end)

    Net.PostToCharacter(char, QuickForge.NETMSG_COMMIT_RESULT, {
        ItemNetID = itemNetID,
        Option = option,
        Outcome = outcome,
    })
end)

---------------------------------------------
-- CLEANUP
---------------------------------------------

-- A crash/save between seeding and cleanup can persist instance-0 rows into
-- the savegame; sweep them on load (Epip's QuickReduce does the same).
-- A Cull rebuild pending at save time cannot resume (the treasure system's
-- async hop does not survive a reload): drop its request row too, so no
-- seeded rows linger and the goal can complete. The in-memory watch list is
-- fresh after a load, so nothing holds the goal open either.
Ext.Osiris.RegisterListener("SavegameLoaded", 4, "after", function(_, _, _, _)
    local reserved = Osi.DB_AMER_UI_Greatforge_CraftObject_Reserved:Get(INSTANCE, nil)
    if reserved then
        for _, row in ipairs(reserved) do
            Osi.PROC_AMER_GEN_UnreserveHelperObject(row[2])
        end
        Osi.DB_AMER_UI_Greatforge_CraftObject_Reserved:Delete(INSTANCE, nil)
    end
    QuickForge._ClearSeededRows()
    QuickForge._SweepRebuildRequests()
    QuickForge._TryCompleteInternalGoal()
end)
