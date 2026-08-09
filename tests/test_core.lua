-- Tests for QuickForge/Core.lua — the pure-logic seam.
-- Facts tables mirror what the client adapter gathers from the game;
-- expected outcomes mirror EE2's QRY_AMER_UI_Greatforge_InvalidSelection rules.

return function(t)
    local Core = t.Core

    ---Baseline facts: a mundane Rare 2H sword benched by a higher-level character.
    ---Individual tests override single fields to isolate one rule.
    local function makeFacts(overrides)
        local facts = {
            rarity = "Rare",
            isArtifact = false,
            socketedRuneCount = 0,
            itemLevel = 5,
            characterLevel = 10,
            hasGreatforgeBlockedTag = false,
            runeSlotCount = 0,
            isWeapon = true,
            isTwoHanded = true,
        }
        for k, v in pairs(overrides or {}) do
            facts[k] = v
        end
        return facts
    end

    ----------------------------------------
    -- Option registry
    ----------------------------------------

    t.test("registry lists all ten options in Greatforge wheel order, Epip extras last", function()
        local ids = {}
        for _, option in ipairs(Core.OPTIONS) do
            table.insert(ids, option.ID)
        end
        t.assertListEquals(ids, {
            "ExtractRunes", "Reduce", "LevelUp", "Masterwork", "Focalize",
            "Transmute", "RemoveMods", "Combine", "AddSockets", "PIP_Engrave",
        }, "option IDs")
    end)

    ----------------------------------------
    -- GetApplicableOptions: per-option rules
    ----------------------------------------

    t.test("Reduce blocked on Common items, allowed otherwise (incl. Unique)", function()
        t.assertNotContains(Core.GetApplicableOptions(makeFacts({rarity = "Common"})), "Reduce")
        t.assertContains(Core.GetApplicableOptions(makeFacts({rarity = "Rare"})), "Reduce")
        t.assertContains(Core.GetApplicableOptions(makeFacts({rarity = "Unique"})), "Reduce")
    end)

    t.test("ExtractRunes requires at least one socketed rune", function()
        t.assertNotContains(Core.GetApplicableOptions(makeFacts({socketedRuneCount = 0})), "ExtractRunes")
        t.assertContains(Core.GetApplicableOptions(makeFacts({socketedRuneCount = 1})), "ExtractRunes")
    end)

    t.test("LevelUp requires item level below character level", function()
        t.assertContains(Core.GetApplicableOptions(makeFacts({itemLevel = 9, characterLevel = 10})), "LevelUp")
        t.assertNotContains(Core.GetApplicableOptions(makeFacts({itemLevel = 10, characterLevel = 10})), "LevelUp")
        t.assertNotContains(Core.GetApplicableOptions(makeFacts({itemLevel = 11, characterLevel = 10})), "LevelUp")
    end)

    t.test("Masterwork blocked on Common and on Greatforge-blocked items", function()
        t.assertNotContains(Core.GetApplicableOptions(makeFacts({rarity = "Common"})), "Masterwork")
        t.assertNotContains(Core.GetApplicableOptions(makeFacts({hasGreatforgeBlockedTag = true})), "Masterwork")
        t.assertContains(Core.GetApplicableOptions(makeFacts()), "Masterwork")
    end)

    t.test("Focalize requires an Artifact", function()
        t.assertNotContains(Core.GetApplicableOptions(makeFacts()), "Focalize")
        t.assertContains(Core.GetApplicableOptions(makeFacts({isArtifact = true, rarity = "Unique"})), "Focalize")
    end)

    t.test("Transmute blocked on Uniques only", function()
        t.assertContains(Core.GetApplicableOptions(makeFacts({rarity = "Common"})), "Transmute")
        t.assertContains(Core.GetApplicableOptions(makeFacts({rarity = "Divine"})), "Transmute")
        t.assertNotContains(Core.GetApplicableOptions(makeFacts({rarity = "Unique"})), "Transmute")
    end)

    t.test("RemoveMods blocked on Uniques and Greatforge-blocked items", function()
        t.assertContains(Core.GetApplicableOptions(makeFacts()), "RemoveMods")
        t.assertNotContains(Core.GetApplicableOptions(makeFacts({rarity = "Unique"})), "RemoveMods")
        t.assertNotContains(Core.GetApplicableOptions(makeFacts({hasGreatforgeBlockedTag = true})), "RemoveMods")
    end)

    t.test("Combine blocked on Common, non-Artifact Unique, and blocked items", function()
        t.assertContains(Core.GetApplicableOptions(makeFacts()), "Combine")
        t.assertNotContains(Core.GetApplicableOptions(makeFacts({rarity = "Common"})), "Combine")
        t.assertNotContains(Core.GetApplicableOptions(makeFacts({rarity = "Unique"})), "Combine")
        t.assertContains(
            Core.GetApplicableOptions(makeFacts({rarity = "Unique", isArtifact = true})), "Combine")
        t.assertNotContains(Core.GetApplicableOptions(makeFacts({hasGreatforgeBlockedTag = true})), "Combine")
    end)

    t.test("AddSockets: limit 3 in general, 2 for one-handed weapons", function()
        -- 2H weapon: limit 3
        t.assertContains(Core.GetApplicableOptions(makeFacts({runeSlotCount = 2})), "AddSockets")
        t.assertNotContains(Core.GetApplicableOptions(makeFacts({runeSlotCount = 3})), "AddSockets")
        -- 1H weapon: limit 2
        t.assertContains(
            Core.GetApplicableOptions(makeFacts({runeSlotCount = 1, isWeapon = true, isTwoHanded = false})),
            "AddSockets")
        t.assertNotContains(
            Core.GetApplicableOptions(makeFacts({runeSlotCount = 2, isWeapon = true, isTwoHanded = false})),
            "AddSockets")
        -- Armor: limit 3 even though not two-handed
        t.assertContains(
            Core.GetApplicableOptions(makeFacts({runeSlotCount = 2, isWeapon = false, isTwoHanded = false})),
            "AddSockets")
    end)

    t.test("Engrave is always applicable", function()
        t.assertContains(Core.GetApplicableOptions(makeFacts({rarity = "Common"})), "PIP_Engrave")
        t.assertContains(Core.GetApplicableOptions(makeFacts({hasGreatforgeBlockedTag = true})), "PIP_Engrave")
    end)

    t.test("applicable options preserve registry order", function()
        local ids = Core.GetApplicableOptions(makeFacts({socketedRuneCount = 1, runeSlotCount = 1}))
        t.assertListEquals(ids, {
            "ExtractRunes", "Reduce", "LevelUp", "Masterwork",
            "Transmute", "RemoveMods", "Combine", "AddSockets", "PIP_Engrave",
        }, "applicable IDs")
    end)

    ----------------------------------------
    -- Commit routes (phase 2 flips picker options to direct one at a time)
    ----------------------------------------

    t.test("the seven non-picker options route direct", function()
        for _, id in ipairs({"ExtractRunes", "Reduce", "LevelUp", "Focalize",
                             "Transmute", "AddSockets", "PIP_Engrave"}) do
            t.assertEquals(Core.GetRoute(id), "direct", id)
        end
    end)

    t.test("Masterwork routes direct (ticket 01)", function()
        t.assertEquals(Core.GetRoute("Masterwork"), "direct", "Masterwork")
    end)

    t.test("Cull Properties routes direct (ticket 02)", function()
        t.assertEquals(Core.GetRoute("RemoveMods"), "direct", "RemoveMods")
    end)

    t.test("Combine routes direct (ticket 03)", function()
        t.assertEquals(Core.GetRoute("Combine"), "direct", "Combine")
    end)

    t.test("GetRoute returns nil for unknown options", function()
        t.assertEquals(Core.GetRoute("DoCraft"), nil, "unknown option")
    end)

    ----------------------------------------
    -- BuildMenuEntries
    ----------------------------------------

    t.test("BuildMenuEntries maps option IDs to entry descriptors with labels", function()
        local entries = Core.BuildMenuEntries({"Reduce", "Masterwork"}, {
            Reduce = "Dismantle",
            Masterwork = "Masterwork",
        })
        t.assertEquals(entries[1].ID, "QuickForge_Option_Reduce", "entry 1 ID")
        t.assertEquals(entries[1].Option, "Reduce", "entry 1 option")
        t.assertEquals(entries[1].Label, "Dismantle", "entry 1 label")
        t.assertEquals(entries[2].ID, "QuickForge_Option_Masterwork", "entry 2 ID")
        t.assertEquals(entries[2].Option, "Masterwork", "entry 2 option")
    end)

    t.test("BuildMenuEntries appends the Open in Greatforge fallback entry last", function()
        local entries = Core.BuildMenuEntries({"Reduce"}, {
            Reduce = "Dismantle",
            OpenGreatforge = "Open in Greatforge...",
        })
        t.assertEquals(#entries, 2, "entry count")
        local fallback = entries[#entries]
        t.assertEquals(fallback.ID, "QuickForge_OpenGreatforge", "fallback ID")
        t.assertEquals(fallback.Option, nil, "fallback has no option")
        t.assertEquals(fallback.Label, "Open in Greatforge...", "fallback label")
    end)

    t.test("BuildMenuEntries appends the fallback even with no applicable options", function()
        local entries = Core.BuildMenuEntries({}, {})
        t.assertEquals(#entries, 1, "entry count")
        t.assertEquals(entries[1].ID, "QuickForge_OpenGreatforge", "fallback ID")
    end)

    t.test("BuildMenuEntries falls back to the option ID when no label is provided", function()
        local entries = Core.BuildMenuEntries({"Focalize"}, {})
        t.assertEquals(entries[1].Label, "Focalize", "fallback label")
    end)

    ----------------------------------------
    -- PlanDirectOperation
    ----------------------------------------

    t.test("PlanDirectOperation blocks while the party is in combat", function()
        t.assertEquals(Core.PlanDirectOperation({partyInCombat = true, anyPlayerInGreatforge = false}),
            "blocked_combat", "plan")
    end)

    t.test("PlanDirectOperation refuses while any player is in a Greatforge session", function()
        t.assertEquals(Core.PlanDirectOperation({partyInCombat = false, anyPlayerInGreatforge = true}),
            "blocked_session", "plan")
    end)

    t.test("PlanDirectOperation reports combat over session when both apply", function()
        t.assertEquals(Core.PlanDirectOperation({partyInCombat = true, anyPlayerInGreatforge = true}),
            "blocked_combat", "plan")
    end)

    t.test("PlanDirectOperation proceeds otherwise", function()
        t.assertEquals(Core.PlanDirectOperation({partyInCombat = false, anyPlayerInGreatforge = false}),
            "proceed", "plan")
    end)

    ----------------------------------------
    -- PlanJump
    ----------------------------------------

    t.test("PlanJump blocks while the party is in combat", function()
        t.assertEquals(Core.PlanJump({partyInCombat = true, currentUI = nil}),
            "blocked_combat", "plan")
    end)

    t.test("PlanJump requests a fresh instance when not in any UI", function()
        t.assertEquals(Core.PlanJump({partyInCombat = false, currentUI = nil}),
            "request_instance", "plan")
    end)

    t.test("PlanJump benches directly when already in the Greatforge", function()
        t.assertEquals(Core.PlanJump({partyInCombat = false, currentUI = "AMER_UI_Greatforge"}),
            "bench", "plan")
    end)

    t.test("PlanJump swaps UIs when in a different physical UI (e.g. Ascension)", function()
        t.assertEquals(Core.PlanJump({partyInCombat = false, currentUI = "AMER_UI_Ascension"}),
            "swap_ui", "plan")
    end)

    ----------------------------------------
    -- IsKnownOption
    ----------------------------------------

    t.test("IsKnownOption accepts registry options and rejects everything else", function()
        t.assertEquals(Core.IsKnownOption("Reduce"), true, "Reduce")
        t.assertEquals(Core.IsKnownOption("PIP_Engrave"), true, "PIP_Engrave")
        t.assertEquals(Core.IsKnownOption("DoCraft"), false, "unknown option")
        t.assertEquals(Core.IsKnownOption(""), false, "empty string")
    end)
end
