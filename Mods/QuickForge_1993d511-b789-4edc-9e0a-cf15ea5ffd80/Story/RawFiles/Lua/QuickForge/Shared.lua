---------------------------------------------
-- QuickForge: executes Greatforge options from the equipment right-click
-- context menu. Direct options confirm in QuickForge's own Forge Window and
-- commit in place through EE2's request pipeline; picker options (and the
-- "Open in Greatforge..." fallback) Jump into EE2's physical UI instead.
-- QuickForge never reimplements Greatforge rules: it only invokes EE2's own
-- execution path, and only displays costs/validity read live from EE2's data.
---------------------------------------------

local MOD_PREFIX = "QuickForge_1993d511-b789-4edc-9e0a-cf15ea5ffd80"

---@class Features.QuickForge : Feature
local QuickForge = {
    MOD_PREFIX = MOD_PREFIX,
    NETMSG_JUMP = "QuickForge.NetMsgs.Jump",
    NETMSG_PREVIEW_REQUEST = "QuickForge.NetMsgs.PreviewRequest",
    NETMSG_PREVIEW = "QuickForge.NetMsgs.Preview",
    NETMSG_COMMIT = "QuickForge.NetMsgs.Commit",
    NETMSG_COMMIT_RESULT = "QuickForge.NetMsgs.CommitResult",

    USE_LEGACY_EVENTS = false,
    USE_LEGACY_HOOKS = false,
    SupportedGameStates = _Feature.GAME_STATES.RUNNING_SESSION,

    -- Player-facing option names keyed as "Label_" .. Greatforge option ID.
    TranslatedStrings = {
        Label_Greatforge = {
            Handle = "hfc65be0bg8381g4a7bgb11cg6311bdf9f4de",
            Text = "Greatforge",
            ContextDescription = "Context menu submenu name",
        },
        Label_ExtractRunes = {
            Handle = "h4efd5be7g8f47g4f72g8557g4724c5beffba",
            Text = "Extract Runes",
            ContextDescription = "Greatforge option name",
        },
        Label_Reduce = {
            Handle = "hf0d31fc1g8f10g4db4g9ed3gd0c7eb660996",
            Text = "Dismantle",
            ContextDescription = "Greatforge option name",
        },
        Label_LevelUp = {
            Handle = "h1936d5fcga54dg408bg99e1g21ab71c7d8ab",
            Text = "Empower",
            ContextDescription = "Greatforge option name",
        },
        Label_Masterwork = {
            Handle = "h64f69993g9728g4aa8ga043g3e557ce6a551",
            Text = "Masterwork",
            ContextDescription = "Greatforge option name",
        },
        Label_Focalize = {
            Handle = "hf5bafb18gf447g4b69gbb34gd4e3d4456bae",
            Text = "Focalize",
            ContextDescription = "Greatforge option name",
        },
        Label_Transmute = {
            Handle = "h58bfc8d9g8893g456aga9adgd15821756b80",
            Text = "Transmute",
            ContextDescription = "Greatforge option name",
        },
        Label_RemoveMods = {
            Handle = "h9333c7dfgb0efg4676gb2d9gdf2a582f1604",
            Text = "Cull Properties",
            ContextDescription = "Greatforge option name",
        },
        Label_Combine = {
            Handle = "h7cf67cebgc714g429egb0b3gb514e9a21333",
            Text = "Combine",
            ContextDescription = "Greatforge option name",
        },
        Label_AddSockets = {
            Handle = "h9e7b54bag62c0g4fe7g8102gab0d32f8c123",
            Text = "Drill Sockets",
            ContextDescription = "Greatforge option name (Epip-added option)",
        },
        Label_PIP_Engrave = {
            Handle = "h1a2791a9g9769g45e2gbff2g14e8e43ac552",
            Text = "Engrave",
            ContextDescription = "Greatforge option name (Epip-added option)",
        },
        Label_OpenGreatforge = {
            Handle = "h7478be74gb1e2g4c62g996eg19d9a40567cf",
            Text = "Open in Greatforge...",
            ContextDescription = "Context menu fallback entry: Jump into EE2's physical UI",
        },
        ForgeWindow_CostSplinters = {
            Handle = "he34127e1g95d9g49ecga8cegb2918e5b8c9f",
            Text = "Cost: %d Artificer's Splinters",
            ContextDescription = "Forge Window cost line (Splinter-priced options)",
        },
        ForgeWindow_CostGold = {
            Handle = "he05985bdg103fg4b5fgb368gdb720efb3438",
            Text = "Cost: %d Gold",
            ContextDescription = "Forge Window cost line (Dismantle)",
        },
        ForgeWindow_CurrentFunds = {
            Handle = "hdf44cb23g6e58g44f8ga53fgffe7e14d77ca",
            Text = "You have: %d",
            ContextDescription = "Forge Window line showing the player's matching funds",
        },
        MsgBox_SessionBusy_Title = {
            Handle = "h08b7b1a9gfff5g45d1g84cag1f5c4b59d6f4",
            Text = "Greatforge in use",
            ContextDescription = "Dialog title when a Direct Operation is refused because a player is inside a physical UI",
        },
        MsgBox_SessionBusy_Body = {
            Handle = "ha8c47535g1449g4203g8b93g34fd7409d579",
            Text = "The Greatforge cannot work on this item while someone is using it. Open the Greatforge instead?",
            ContextDescription = "Dialog body offering the Jump fallback",
        },
        Toast_Success = {
            Handle = "h5b3ac1baga6a4g4995g8633g218cdb4b55f7",
            Text = "%s complete.",
            ContextDescription = "Success toast; %s is the option name",
        },
        Error_Generic = {
            Handle = "hb31e0eeag16feg466bga927gd8f6e0e23a64",
            Text = "The Greatforge could not complete this operation. Open the Greatforge instead?",
            ContextDescription = "Dialog body for unexpected Direct Operation failures, offering the Jump fallback",
        },
        Error_MaxSockets = {
            Handle = "h9f2f566eg6731g4260g87a4gebb32cfa1f60",
            Text = "This item cannot hold any more rune sockets.",
            ContextDescription = "Dialog body when Drill Sockets is invalid (QuickForge's own check; EE2 shows no box for it)",
        },
        Error_StaleSelection = {
            Handle = "h2ba1c4d7g5c19g4e00g9d2fg7c8fa93d61b5",
            Text = "That choice is no longer valid for this item. Open the Greatforge instead?",
            ContextDescription = "Dialog body when a picker selection was invalidated between preview and commit, offering the Jump fallback",
        },
        Picker_NoSelectionCost = {
            Handle = "hc7f2d09ag34b5g4c81gb6e2g0d81c5a7f244",
            Text = "Select a property to see its cost.",
            ContextDescription = "Forge Window cost line before a per-Property-priced picker (Masterwork) has a selection",
        },
        Picker_NoDonors = {
            Handle = "h1d9e83f2g7a06g4b3cg8f51g92c4e07ba6d3",
            Text = "No item in the party can be combined into this one.",
            ContextDescription = "Forge Window empty state for a donorless Combine picker",
        },
        Output_Yields = {
            Handle = "hb4c1e70fg9d38g4a26g8f14g3e0721cba95d",
            Text = "Yields:",
            ContextDescription = "Forge Window label above the previewed output items",
        },
        Output_AddSockets = {
            Handle = "h6f8a2d13gc504g4e71gb9a8g27de5104f83c",
            Text = "Adds one rune socket.",
            ContextDescription = "Forge Window output line for Drill Sockets",
        },
        Output_UpgradesProperty = {
            Handle = "h29e7b346g0af1g4c88ga75dg8b41ce20d967",
            Text = "Upgrades: %s",
            ContextDescription = "Forge Window output line for Masterwork; %s is the property and its value change",
        },
        Output_KeepsProperty = {
            Handle = "hd15c9e82g4b73g40feg9c26ga7e83f14b60d",
            Text = "Keeps: %s",
            ContextDescription = "Forge Window output line for Cull Properties; %s is the kept property",
        },
        Output_AddsProperty = {
            Handle = "h7a30f5c9ge618g4d2bgb84fg1c05d97ea236",
            Text = "Adds: %s",
            ContextDescription = "Forge Window output line for Combine; %s is the transferred property",
        },
        DropSlot_Hint = {
            Handle = "h5e02c8b1gf6d4g49a7gb305g6a1db2c94e78",
            Text = "Drag an item here to consume it, or pick one from the list.",
            ContextDescription = "Tooltip on the Combine window's empty Donor slot",
        },
        Error_DonorEquipped = {
            Handle = "h83f61a05g2c47g4d92g8be0gf5709d3c1a26",
            Text = "Equipped items cannot be consumed. Unequip it first.",
            ContextDescription = "Refusal reason when an equipped item is dropped on the Donor slot",
        },
        Error_DonorInvalid = {
            Handle = "h0b94d7e6g815cg4f3ag97d2g4ce8a1f06b53",
            Text = "This item cannot serve as a donor.",
            ContextDescription = "Generic refusal reason for a Donor-slot drop the server did not list",
        },
    },
}
Epip.RegisterFeature("QuickForge", "QuickForge", QuickForge)

QuickForge.Core = Ext.Require(MOD_PREFIX, "QuickForge/Core.lua")

---EE2 strings the Forge Window shows. Their keys exist only in EE2's
---`Localization/*.lsb` key banks, which the extender's key lookup has been
---observed not to resolve, and the handles (extracted from
---`Localization/AMER_UI_Greatforge.lsb`) can drift across EE2 releases —
---so each entry bundles a verbatim fallback copy of EE2's text.
---`ResolveEE2String` prefers the live handle, then the live key, then the
---bundled copy: EE2's current text wins whenever it is reachable, and the
---window is never blank when it is not.
---Epip's own options (AddSockets, PIP_Engrave) register their keys at
---runtime and resolve by key, so they are absent here.
---@type table<string, {Key: string?, Handle: TranslatedStringHandle?, Fallback: string}>
QuickForge.EE2_STRINGS = {
    Desc_Reduce = {
        Key = "AMER_UI_Greatforge_Desc_Reduce",
        Handle = "h8a8b6c8bgd119g49e6gba99g4bb18ba073fd",
        Fallback = [[<p align="left">Destroy this item to recover Artificer's Splinters and some of its basic materials. Higher-quality items will yield better results.<br><br>Any socketed runes will be recovered.<br><br>Splinters granted:</p>]],
    },
    Desc_LevelUp = {
        Key = "AMER_UI_Greatforge_Desc_LevelUp",
        Handle = "hc7c66553g79f8g4079g9a65gb73e8cbd8452",
        Fallback = [[<p align="left">Raise this item's level by one, or to your level minus two, whichever is higher. This increases its damage or armor values, and can support Masterworking its properties.<br><font color="a8a8a8" size="21" face="Averia Serif">Items with very low armor may not see any increase from this. Choose wisely.<br><br>The item's requirements may increase, but this change will not be displayed until you save and reload your game.</font></p>]],
    },
    Desc_ExtractRunes = {
        Key = "AMER_UI_Greatforge_Desc_ExtractRunes",
        Handle = "h330f2b00gcf60g46e7gaa4dgb5c0b715520f",
        Fallback = [[<p align="left">Recover all socketed runes carefully enough to preserve the host item.</p>]],
    },
    Desc_Transmute = {
        Key = "AMER_UI_Greatforge_Desc_Transmute",
        Handle = "hebc3cf53g9421g4ec1ga783ga4389b0f57f7",
        Fallback = [[<p align="left">Transmute a non-unique item into a random item of the same rarity.</p>]],
    },
    Desc_Masterwork = {
        Key = "AMER_UI_Greatforge_Desc_Masterwork",
        Handle = "he1b10f66g87f7g4522ga363g21e00f87e25a",
        Fallback = [[<p align="left">Enchance a mundane non-implicit item property.<br><br>Masterworking has a variable cost, based on the property chosen; how much the property will be improved, as well as how rare the improved property usually is.<br><br><font color="a8a8a8" size="21" face="Averia Serif">You may only Masterwork an item once.</font></p>]],
    },
    Desc_Focalize = {
        Key = "AMER_UI_Greatforge_Desc_Focalize",
        Handle = "h0f37796ag94b5g4174gbca4g2bc90c94ad9c",
        Fallback = [[<p align="left">Focus an Artifact into a rune, so that its unique power may be added to another item.<br><br>Artifact Runes may only be placed in an item of the same equipment slot as the original Artifact<br>(Axe to Bow works, but Axe to Ring does not).</p>]],
    },
    Desc_RemoveMods = {
        Key = "AMER_UI_Greatforge_Desc_RemoveMods",
        Handle = "h0d0d4435g1428g45cag9494g90ad9fb1cf10",
        Fallback = [[<p align="left">Replaces your item with a new one of the same type and rarity with only the selected property, in addition to rerandomized item-implicit properties and sockets.<br><br>Any socketed runes will be recovered</p>]],
    },
    Desc_Combine = {
        Key = "AMER_UI_Greatforge_Desc_Combine",
        Handle = "h8eddba67g5ff9g4ba5g84dag165775111b92",
        Fallback = [[<p align="left">Choose an item with one non-implicit property,<br>it will be destroyed to add that property to your item.<br><br>The property must be one that can normally appear on your item.<br><br>Items have a maximum number of non-implicit properties, based on their rarity: Uncommon: 2,<br>Rare: 3, Epic: 4, Legendary: 5, Divine: 6, Artifact: 5</p>]],
    },
    Masterwork_PropertyMaxed = {
        Key = "AMER_UI_Greatforge_Masterwork_PropertyMaxed",
        Handle = "h397742e2ga2c6g4b86gacadgac1019297f51",
        Fallback = "This property cannot be improved any further.",
    },
    -- Not an engine key: EE2 builds this message from its own Osiris
    -- string cache (DB_AMER_GEN_TSK_Cache) and appends the required level.
    -- The server does the same; this fallback covers a missing cache row.
    Masterwork_LevelTooHigh = {
        Fallback = "Masterworking this property requires at least item level ",
    },
    Combine_ItemAddedIsTheSame = {
        Key = "AMER_UI_Greatforge_Combine_ItemAddedIsTheSame",
        Handle = "h9fd682d1g42ffg427bgb20cgbcc07cf3fcf0",
        Fallback = "This is the item I'm already working on, choose another!",
    },
    Combine_ItemAddedHasTooManyMods = {
        Key = "AMER_UI_Greatforge_Combine_ItemAddedHasTooManyMods",
        Handle = "ha646e8b5g512bg48d8gbe62g266cf5bdd602",
        Fallback = "I can only combine an item that has one non-implicit property.<br>This item has too many.",
    },
    Combine_ItemAddedHasNoMods = {
        Key = "AMER_UI_Greatforge_Combine_ItemAddedHasNoMods",
        Handle = "he6e156f7g8632g426eg92a6gc430a92fad05",
        Fallback = "I can only combine an item that has one non-implicit property.<br>This item has none.",
    },
    Combine_ItemAddedHasSamePrefix = {
        Key = "AMER_UI_Greatforge_Combine_ItemAddedHasSamePrefix",
        Handle = "ha00a2258gb96bg48deg8c17ga426b6b34839",
        Fallback = "My item already has this property, I cannot add it again.",
    },
    Combine_ItemAddedHasExcludedPrefix = {
        Key = "AMER_UI_Greatforge_Combine_ItemAddedHasExcludedPrefix",
        Handle = "h5a12fac9g25b1g4d6cg8ca4g928be17629d2",
        Fallback = "My item already has a property that prevents adding this one.",
    },
    -- The Fail_* keys have no handles even in EE2's own bank.
    Combine_Fail_Level = {
        Key = "AMER_UI_Greatforge_Combine_Fail_Level",
        Fallback = "My item needs to be a higher level to combine this property.",
    },
    Combine_Fail_ItemTypes = {
        Key = "AMER_UI_Greatforge_Combine_Fail_ItemTypes",
        Fallback = "I cannot combine this because my item's type does not normally appear with this property.",
    },
    Combine_Fail_Value = {
        Key = "AMER_UI_Greatforge_Combine_Fail_Value",
        Fallback = "I cannot combine this because my item's type does not support such a large amount of this property.",
    },
}

---Resolves one of EE2's strings: the live handle first, then the live key,
---then the bundled fallback copy.
---@param name string A QuickForge.EE2_STRINGS key.
---@return string
function QuickForge.ResolveEE2String(name)
    local entry = QuickForge.EE2_STRINGS[name]
    if not entry then return "" end

    if entry.Handle then
        local text = Ext.L10N.GetTranslatedString(entry.Handle)
        if text and text ~= "" and text ~= entry.Handle then
            return text
        end
    end
    if entry.Key then
        local text = Ext.L10N.GetTranslatedStringFromKey(entry.Key)
        if text and text ~= "" and text ~= entry.Key then
            return text
        end
    end
    return entry.Fallback
end

---------------------------------------------
-- NET MESSAGES
---------------------------------------------

---Client request to Jump: open the character's Greatforge with the item
---benched and the option's page opened, without committing. With no Option,
---lands on the option wheel (the "Open in Greatforge..." fallback entry).
---@class QuickForge.NetMsgs.Jump : NetLib_Message_Character, NetLib_Message_Item
---@field Option string? Greatforge option ID.

---Preview/commit outcome. "ok"/"success" aside, every value is a refusal:
---blocked_combat/blocked_session from gating (the latter offers the Jump),
---invalid from EE2's own validation (EE2 has already shown its reason box),
---insufficient_funds from EE2's funds check (likewise),
---stale_selection when a picker selection no longer matches the re-derived
---rows at commit time (QuickForge shows its own dialog, offering the Jump),
---error for anything unexpected (e.g. no helper container available).
---@alias QuickForge.OperationOutcome "ok"|"success"|"blocked_combat"|"blocked_session"|"invalid"|"insufficient_funds"|"stale_selection"|"error"

---Client request to preview a Direct Operation (opens the Forge Window).
---@class QuickForge.NetMsgs.PreviewRequest : NetLib_Message_Character, NetLib_Message_Item
---@field Option string Greatforge option ID.

---Server reply: live cost/validity for the Forge Window.
---For picker options, Rows carries the picker list; Cost is the option's
---flat cost, absent for per-row-priced pickers (Masterwork).
---@class QuickForge.NetMsgs.Preview : NetLib_Message_Item
---@field Option string
---@field Outcome QuickForge.OperationOutcome "ok" or a refusal.
---@field MatType string? "GreatforgeFrags" or "Gold" (present when Outcome == "ok").
---@field Cost integer? EE2-computed flat cost (absent for per-row-priced pickers).
---@field Funds integer? The player's matching funds (present when Outcome == "ok").
---@field Rows QuickForge.PickerRow[]? Picker rows (present for picker options).
---@field InvalidDonors table<string, string>? Refused Combine candidates: NetID string -> reason (EE2 message TSK suffix, or "QuickForge_Equipped").
---@field DescriptionSuffix string? EE2-computed text appended to the option description (Dismantle's Splinters-granted number).
---@field Outputs QuickForge.OutputItem[]? Items the operation will hand over, where EE2's data names them exactly.

---One previewed output item, shown as a hoverable slot in the Forge Window.
---Only outputs EE2 names exactly appear; its random elements (Transmute's
---reroll, Dismantle's ingredient tables, Cull's regenerated implicits) are
---never guessed at.
---@class QuickForge.OutputItem
---@field TemplateID string Root template of the item granted.
---@field Amount integer? Stack size, when more than one.

---Client request to commit a previewed Direct Operation.
---@class QuickForge.NetMsgs.Commit : NetLib_Message_Character, NetLib_Message_Item
---@field Option string Greatforge option ID.
---@field SelectionKey string? The selected picker row's Key (required for picker options).

---Server reply: what the commit did.
---@class QuickForge.NetMsgs.CommitResult : NetLib_Message_Item
---@field Option string
---@field Outcome QuickForge.OperationOutcome "success" or a refusal.
