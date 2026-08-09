-- Tests for QuickForge/Core.lua — picker logic (phase 2).
-- Row facts mirror what the server derives from EE2's data
-- (Masterwork_ValidatedMods, CountedMods, the donor checks); expected
-- outcomes mirror EE2's own selection gates.

return function(t)
    local Core = t.Core

    ----------------------------------------
    -- GetPicker
    ----------------------------------------

    t.test("Masterwork uses the property-uptier picker", function()
        t.assertEquals(Core.GetPicker("Masterwork"), "property_uptier", "picker")
    end)

    t.test("Cull Properties uses the property-keep picker", function()
        t.assertEquals(Core.GetPicker("RemoveMods"), "property_keep", "picker")
    end)

    t.test("Combine uses the donor picker", function()
        t.assertEquals(Core.GetPicker("Combine"), "donor", "picker")
    end)

    ----------------------------------------
    -- EvaluateDonor: QuickForge's orchestration of EE2's individually
    -- callable donor checks, in EE2's own order (the page-driven wrapper
    -- opens message boxes, so the list filter calls the underlying queries
    -- and re-composes their verdicts here). Reasons are the suffixes of
    -- EE2's own "AMER_UI_Greatforge_Combine_*" message TSKs.
    ----------------------------------------

    ---A donor that passes every check; tests override one fact each.
    local function makeDonorFacts(overrides)
        local facts = {
            isTargetItem = false,
            modCount = 1,
            hasSamePrefix = false,
            hasExcludedPrefix = false,
            rollFailReason = nil,
        }
        for k, v in pairs(overrides or {}) do
            facts[k] = v
        end
        return facts
    end

    t.test("a donor passing every check is valid", function()
        local verdict = Core.EvaluateDonor(makeDonorFacts())
        t.assertEquals(verdict.valid, true, "valid")
        t.assertEquals(verdict.reason, nil, "reason")
    end)

    t.test("the target item itself cannot be its own donor", function()
        local verdict = Core.EvaluateDonor(makeDonorFacts({isTargetItem = true}))
        t.assertEquals(verdict.valid, false, "valid")
        t.assertEquals(verdict.reason, "ItemAddedIsTheSame", "reason")
    end)

    t.test("a donor with more than one property is refused", function()
        local verdict = Core.EvaluateDonor(makeDonorFacts({modCount = 2}))
        t.assertEquals(verdict.valid, false, "valid")
        t.assertEquals(verdict.reason, "ItemAddedHasTooManyMods", "reason")
    end)

    t.test("a donor with no properties is refused", function()
        local verdict = Core.EvaluateDonor(makeDonorFacts({modCount = 0}))
        t.assertEquals(verdict.valid, false, "valid")
        t.assertEquals(verdict.reason, "ItemAddedHasNoMods", "reason")
    end)

    t.test("a donor whose prefix the target already has is refused", function()
        local verdict = Core.EvaluateDonor(makeDonorFacts({hasSamePrefix = true}))
        t.assertEquals(verdict.valid, false, "valid")
        t.assertEquals(verdict.reason, "ItemAddedHasSamePrefix", "reason")
    end)

    t.test("a donor whose prefix the target's mods exclude is refused", function()
        local verdict = Core.EvaluateDonor(makeDonorFacts({hasExcludedPrefix = true}))
        t.assertEquals(verdict.valid, false, "valid")
        t.assertEquals(verdict.reason, "ItemAddedHasExcludedPrefix", "reason")
    end)

    t.test("a donor whose property the target cannot roll is refused with EE2's reason", function()
        local verdict = Core.EvaluateDonor(makeDonorFacts({rollFailReason = "ItemTypes"}))
        t.assertEquals(verdict.valid, false, "valid")
        t.assertEquals(verdict.reason, "Fail_ItemTypes", "reason")
    end)

    t.test("a rarity-only roll failure passes (EE2's own exception)", function()
        -- Mirrors AMER_GLO_UI_Greatforge_Internal.txt:2062-2067: the rarity
        -- rule is deliberately not enforced for Combine.
        local verdict = Core.EvaluateDonor(makeDonorFacts({rollFailReason = "Rarity"}))
        t.assertEquals(verdict.valid, true, "valid")
    end)

    t.test("donor checks refuse in EE2's own order", function()
        -- Same-item wins over everything; mod count over prefix checks.
        t.assertEquals(Core.EvaluateDonor(makeDonorFacts({
            isTargetItem = true, modCount = 5, hasSamePrefix = true,
        })).reason, "ItemAddedIsTheSame", "same item first")
        t.assertEquals(Core.EvaluateDonor(makeDonorFacts({
            modCount = 2, hasSamePrefix = true, rollFailReason = "ItemTypes",
        })).reason, "ItemAddedHasTooManyMods", "mod count before prefix checks")
        t.assertEquals(Core.EvaluateDonor(makeDonorFacts({
            hasSamePrefix = true, hasExcludedPrefix = true,
        })).reason, "ItemAddedHasSamePrefix", "same prefix before excluded prefix")
    end)

    t.test("non-picker options have no picker", function()
        for _, id in ipairs({"ExtractRunes", "Reduce", "LevelUp", "Focalize",
                             "Transmute", "AddSockets", "PIP_Engrave"}) do
            t.assertEquals(Core.GetPicker(id), nil, id)
        end
    end)

    t.test("GetPicker returns nil for unknown options", function()
        t.assertEquals(Core.GetPicker("DoCraft"), nil, "unknown option")
    end)

    ----------------------------------------
    -- ClassifyMasterworkRow: mirrors EE2's selection gates
    -- (PropertyMaxed checked before PropertyLevelTooHigh, as in
    -- AMER_GLO_UI_Greatforge_Internal.txt:1473-1475).
    ----------------------------------------

    t.test("a row with a real uptier at or below item level is eligible", function()
        local row = Core.ClassifyMasterworkRow({
            uptierDeltamod = "Boost_Weapon_Damage_Fire_2",
            uptierLevel = 5,
            itemLevel = 5,
        })
        t.assertEquals(row.eligible, true, "eligible")
        t.assertEquals(row.reason, nil, "reason")
    end)

    t.test("a row with no higher tier is maxed", function()
        local row = Core.ClassifyMasterworkRow({
            uptierDeltamod = "NONE",
            uptierLevel = -1,
            itemLevel = 5,
        })
        t.assertEquals(row.eligible, false, "eligible")
        t.assertEquals(row.reason, "maxed", "reason")
    end)

    t.test("a row whose uptier level exceeds the item level is level-capped", function()
        local row = Core.ClassifyMasterworkRow({
            uptierDeltamod = "Boost_Weapon_Damage_Fire_3",
            uptierLevel = 9,
            itemLevel = 5,
        })
        t.assertEquals(row.eligible, false, "eligible")
        t.assertEquals(row.reason, "level_too_high", "reason")
    end)

    t.test("maxed wins over level-capped when both would apply", function()
        local row = Core.ClassifyMasterworkRow({
            uptierDeltamod = "NONE",
            uptierLevel = 99,
            itemLevel = 5,
        })
        t.assertEquals(row.reason, "maxed", "reason")
    end)

    ----------------------------------------
    -- Picker selection model: no pre-selection, Confirm gated on a
    -- deliberate pick, unaffordable rows selectable but not confirmable.
    ----------------------------------------

    t.test("only eligible rows are selectable", function()
        t.assertEquals(Core.IsPickerRowSelectable({Eligible = true}), true, "eligible row")
        t.assertEquals(Core.IsPickerRowSelectable({Eligible = false}), false, "ineligible row")
    end)

    t.test("a row's own cost overrides the window's flat cost", function()
        t.assertEquals(Core.GetPickerSelectionCost({Eligible = true, Cost = 12}, 3), 12, "per-row cost")
        t.assertEquals(Core.GetPickerSelectionCost({Eligible = true}, 3), 3, "flat cost")
    end)

    t.test("Confirm is disabled with no selection", function()
        t.assertEquals(Core.CanConfirmPicker(nil, 3, 100), false, "no selection")
    end)

    t.test("Confirm is disabled for an ineligible selection", function()
        t.assertEquals(Core.CanConfirmPicker({Eligible = false}, 3, 100), false, "ineligible")
    end)

    t.test("Confirm is disabled while the selection is unaffordable", function()
        t.assertEquals(Core.CanConfirmPicker({Eligible = true, Cost = 12}, nil, 11), false, "unaffordable")
        t.assertEquals(Core.CanConfirmPicker({Eligible = true, Cost = 12}, nil, 12), true, "exactly affordable")
    end)

    t.test("Confirm uses the flat cost for rows without their own", function()
        t.assertEquals(Core.CanConfirmPicker({Eligible = true}, 5, 4), false, "unaffordable flat")
        t.assertEquals(Core.CanConfirmPicker({Eligible = true}, 5, 5), true, "affordable flat")
    end)

    t.test("Confirm is disabled when no cost is known", function()
        -- A missing cost means EE2 gave us no number; never guess.
        t.assertEquals(Core.CanConfirmPicker({Eligible = true}, nil, 100), false, "no cost")
    end)

    ----------------------------------------
    -- FindPickerRow: stale-selection matching between preview and commit.
    ----------------------------------------

    t.test("FindPickerRow matches rows by key", function()
        local rows = {
            {Key = "Damage_Fire", Index = 0},
            {Key = "CritChance", Index = 1},
        }
        t.assertEquals(Core.FindPickerRow(rows, "CritChance").Index, 1, "found row")
        t.assertEquals(Core.FindPickerRow(rows, "Vitality"), nil, "missing row")
        t.assertEquals(Core.FindPickerRow(rows, nil), nil, "nil key")
    end)
end
