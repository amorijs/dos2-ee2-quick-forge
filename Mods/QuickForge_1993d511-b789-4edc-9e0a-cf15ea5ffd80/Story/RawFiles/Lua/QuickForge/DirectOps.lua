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
---@param cost QuickForge.OperationCost
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
    local users = Osi.DB_AMER_UI_UsersInUI:Get(nil, nil, nil)
    if not users or not users[1] then
        -- Guarded on SysIsActive internally; safe if already complete.
        Osi.PROC_AMER_GEN_Goal_Complete(INTERNAL_GOAL)
    end
end

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

Net.RegisterListener(QuickForge.NETMSG_PREVIEW_REQUEST, function(payload)
    local char, item, option = GetRequestArgs(payload)
    if not char then return end

    local outcome, costFields = QuickForge._RunBenched(char, item, option, function(specs)
        local cost = QuickForge._GenerateCost(option, specs)
        if not cost then return "error" end
        return "ok", {
            MatType = cost.MatType,
            Cost = cost.Amount,
            Funds = QuickForge._GetFunds(char, cost),
        }
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

    local outcome = QuickForge._RunBenched(char, item, option, function(specs)
        local cost = QuickForge._GenerateCost(option, specs)
        local container = cost and QuickForge._ReserveCraftContainer() or nil
        if not cost or not container then return "error" end

        Osi.DB_AMER_UI_Greatforge_SelectedOption_Cost(INSTANCE, cost.MatType, cost.Root, cost.Amount)

        QuickForge._CraftWatch = {}
        Osi.PROC_AMER_UI_Greatforge_OptionRequested(INSTANCE, char.MyGuid, option)
        local watch = QuickForge._CraftWatch
        QuickForge._CraftWatch = nil

        if watch.Crafted then
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
Ext.Osiris.RegisterListener("SavegameLoaded", 4, "after", function(_, _, _, _)
    local reserved = Osi.DB_AMER_UI_Greatforge_CraftObject_Reserved:Get(INSTANCE, nil)
    if reserved then
        for _, row in ipairs(reserved) do
            Osi.PROC_AMER_GEN_UnreserveHelperObject(row[2])
        end
        Osi.DB_AMER_UI_Greatforge_CraftObject_Reserved:Delete(INSTANCE, nil)
    end
    QuickForge._ClearSeededRows()
    QuickForge._TryCompleteInternalGoal()
end)
