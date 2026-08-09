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
    },
}
Epip.RegisterFeature("QuickForge", "QuickForge", QuickForge)

QuickForge.Core = Ext.Require(MOD_PREFIX, "QuickForge/Core.lua")

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

---Client request to commit a previewed Direct Operation.
---@class QuickForge.NetMsgs.Commit : NetLib_Message_Character, NetLib_Message_Item
---@field Option string Greatforge option ID.
---@field SelectionKey string? The selected picker row's Key (required for picker options).

---Server reply: what the commit did.
---@class QuickForge.NetMsgs.CommitResult : NetLib_Message_Item
---@field Option string
---@field Outcome QuickForge.OperationOutcome "success" or a refusal.
