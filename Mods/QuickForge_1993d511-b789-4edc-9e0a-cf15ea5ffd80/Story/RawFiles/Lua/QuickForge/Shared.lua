---------------------------------------------
-- QuickForge: opens the Greatforge from the equipment right-click
-- context menu, with the item benched and an option pre-selected ("Jump").
-- A pure shortcut: costs, confirmations and rules are unchanged;
-- the player confirms or backs out inside the Greatforge as normal.
---------------------------------------------

local MOD_PREFIX = "QuickForge_1993d511-b789-4edc-9e0a-cf15ea5ffd80"

---@class Features.QuickForge : Feature
local QuickForge = {
    MOD_PREFIX = MOD_PREFIX,
    NETMSG_JUMP = "QuickForge.NetMsgs.Jump",

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
    },
}
Epip.RegisterFeature("QuickForge", "QuickForge", QuickForge)

QuickForge.Core = Ext.Require(MOD_PREFIX, "QuickForge/Core.lua")

---------------------------------------------
-- NET MESSAGES
---------------------------------------------

---Client request to Jump: open the character's Greatforge with the item
---benched and the option's page opened, without committing.
---@class QuickForge.NetMsgs.Jump : NetLib_Message_Character, NetLib_Message_Item
---@field Option string Greatforge option ID.
