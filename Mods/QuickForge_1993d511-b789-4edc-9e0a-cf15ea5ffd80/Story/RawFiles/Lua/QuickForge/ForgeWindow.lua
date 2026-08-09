---------------------------------------------
-- QuickForge client: the Forge Window — the confirm layer for a Direct
-- Operation. Item icon with native tooltip, EE2's own option description,
-- EE2-computed cost next to the player's matching funds, Confirm/Cancel.
-- Everything shown is read live from EE2's data via the server preview;
-- the window is only a preview — the server re-validates at commit time.
---------------------------------------------

local QuickForge = Epip.GetFeature("QuickForge", "QuickForge", true) ---@type Features.QuickForge
local Generic = Client.UI.Generic
local MessageBox = Client.UI.MessageBox
local Notification = Client.UI.Notification
local TooltipPanelPrefab = Generic.GetPrefab("GenericUI_Prefab_TooltipPanel")
local TextPrefab = Generic.GetPrefab("GenericUI_Prefab_Text")
local ButtonPrefab = Generic.GetPrefab("GenericUI_Prefab_Button")
local HotbarSlotPrefab = Generic.GetPrefab("GenericUI_Prefab_HotbarSlot")
local CloseButtonPrefab = Generic.GetPrefab("GenericUI_Prefab_CloseButton")
local Input = Client.Input
local V = Vector.Create

local FAILURE_MSGBOX_ID = "QuickForge_OperationRefused"
local MSGBOX_BUTTON_JUMP = 1
local MSGBOX_BUTTON_DISMISS = 2

local UI = Generic.Create("QuickForge_ForgeWindow", {Visible = false})
UI.PANEL_SIZE = V(400, 400)
UI.HEADER_SIZE = V(380, 50)
UI.DESC_SIZE = V(340, 120)
UI.LINE_SIZE = V(340, 30)
UI._Initialized = false
---The previewed operation awaiting confirmation, if the window is open.
---@type {ItemNetID: NetId, Option: string}?
UI._Current = nil
QuickForge.ForgeWindow = UI

---@param option string Greatforge option ID.
---@return string
local function GetOptionLabel(option)
    local tsk = QuickForge.TranslatedStrings["Label_" .. option]
    return tsk and tsk:GetString() or option
end

function UI._Initialize()
    if UI._Initialized then return end

    local panel = TooltipPanelPrefab.Create(UI, "Panel", nil, UI.PANEL_SIZE, "", UI.HEADER_SIZE)
    UI.Panel = panel
    local bg = panel.Background
    bg:SetAsDraggableArea()

    CloseButtonPrefab.Create(UI, "Close", bg):SetPositionRelativeToParent("TopRight", -20, 20)

    local slot = HotbarSlotPrefab.Create(UI, "ItemSlot", bg)
    slot:SetUpdateDelay(-1)
    slot:SetUsable(false)
    slot.SlotElement:SetPositionRelativeToParent("Top", 0, 75)
    UI.ItemSlot = slot

    local desc = TextPrefab.Create(UI, "Description", bg, "", "Center", UI.DESC_SIZE)
    desc:SetPositionRelativeToParent("Top", 0, 155)
    desc:GetMainElement():SetWordWrap(true)
    UI.DescriptionText = desc

    local cost = TextPrefab.Create(UI, "CostLine", bg, "", "Center", UI.LINE_SIZE)
    cost:SetPositionRelativeToParent("Bottom", 0, -105)
    UI.CostText = cost

    local funds = TextPrefab.Create(UI, "FundsLine", bg, "", "Center", UI.LINE_SIZE)
    funds:SetPositionRelativeToParent("Bottom", 0, -75)
    UI.FundsText = funds

    local confirm = ButtonPrefab.Create(UI, "Confirm", bg, ButtonPrefab.STYLES.GreenMedium)
    confirm:SetLabel(Text.CommonStrings.Confirm)
    confirm:SetPositionRelativeToParent("Bottom", -80, -25)
    confirm.Events.Pressed:Subscribe(function(_)
        UI._ConfirmPressed()
    end)
    UI.ConfirmButton = confirm

    local cancel = ButtonPrefab.Create(UI, "Cancel", bg, ButtonPrefab.STYLES.MediumRed)
    cancel:SetLabel(Text.CommonStrings.Cancel)
    cancel:SetPositionRelativeToParent("Bottom", 80, -25)
    cancel.Events.Pressed:Subscribe(function(_)
        UI.Close()
    end)

    UI:SetPanelSize(UI.PANEL_SIZE)
    UI._Initialized = true
end

---Opens the window for a previewed operation.
---@param item EclItem
---@param option string
---@param matType string
---@param cost integer
---@param funds integer
function UI.Open(item, option, matType, cost, funds)
    UI._Initialize()

    UI.Panel.HeaderText:SetText(GetOptionLabel(option))
    UI.ItemSlot:SetItem(item)
    UI.DescriptionText:SetText(Text.GetTranslatedString("AMER_UI_Greatforge_Desc_" .. option, ""))

    local costTSK = matType == "Gold"
        and QuickForge.TranslatedStrings.ForgeWindow_CostGold
        or QuickForge.TranslatedStrings.ForgeWindow_CostSplinters
    UI.CostText:SetText(costTSK:GetString():format(cost))
    UI.FundsText:SetText(QuickForge.TranslatedStrings.ForgeWindow_CurrentFunds:GetString():format(funds))

    -- Visual gate only; EE2's funds check re-runs at commit time.
    UI.ConfirmButton:SetEnabled(funds >= cost)

    UI._Current = {ItemNetID = item.NetID, Option = option}
    UI:SetPositionRelativeToViewport("center", "center")
    UI:Show()
end

function UI.Close()
    UI._Current = nil
    if UI._Initialized then
        UI:Hide()
    end
end

function UI._ConfirmPressed()
    local current = UI._Current
    if not current then return end

    -- Await the result; re-enabled on the next Open().
    UI.ConfirmButton:SetEnabled(false)
    Net.PostToServer(QuickForge.NETMSG_COMMIT, {
        CharacterNetID = Client.GetCharacter().NetID,
        ItemNetID = current.ItemNetID,
        Option = current.Option,
    })
end

-- Close on escape.
Input.Events.KeyStateChanged:Subscribe(function(ev)
    if ev.InputID == "escape" and UI._Initialized and UI:IsVisible() then
        UI.Close()
        ev:Prevent()
    end
end)

---------------------------------------------
-- NET LISTENERS: preview replies and commit results.
---------------------------------------------

---Shows the reason dialog for a refusal outcome, offering the Jump when
---EE2's UI could resolve it. Silent for the outcomes EE2 has already shown
---its own reason box for (never-silent rule, CONTEXT.md).
---@param outcome QuickForge.OperationOutcome
---@param itemNetID NetId
---@param option string
local function ShowFailureDialog(outcome, itemNetID, option)
    local header, body, offerJump
    if outcome == "blocked_session" then
        header = QuickForge.TranslatedStrings.MsgBox_SessionBusy_Title:GetString()
        body = QuickForge.TranslatedStrings.MsgBox_SessionBusy_Body:GetString()
        offerJump = true
    elseif outcome == "error" then
        header = QuickForge.TranslatedStrings.Label_Greatforge:GetString()
        body = QuickForge.TranslatedStrings.Error_Generic:GetString()
        offerJump = true -- EE2's own UI needs none of QuickForge's plumbing.
    elseif outcome == "invalid" and option == "AddSockets" then
        -- The one validity check that is QuickForge's own (ADR-0001), so no
        -- EE2 box appeared; the socket limit cannot be resolved by Jumping.
        header = GetOptionLabel(option)
        body = QuickForge.TranslatedStrings.Error_MaxSockets:GetString()
        offerJump = false
    else
        -- "invalid" (EE2's rules), "insufficient_funds", "blocked_combat":
        -- EE2 has already shown its reason box.
        return
    end

    local buttons = {
        {ID = MSGBOX_BUTTON_DISMISS, Text = Text.CommonStrings.Close:GetString()},
    }
    if offerJump then
        buttons = {
            {ID = MSGBOX_BUTTON_JUMP, Text = QuickForge.TranslatedStrings.Label_OpenGreatforge:GetString()},
            {ID = MSGBOX_BUTTON_DISMISS, Text = Text.CommonStrings.Cancel:GetString()},
        }
    end

    MessageBox.Open({
        ID = FAILURE_MSGBOX_ID,
        Header = header,
        Message = body,
        Buttons = buttons,
        -- Context smuggled into the ButtonPressed listener.
        QuickForgeItemNetID = itemNetID,
        QuickForgeOption = option,
    })
end

MessageBox.RegisterMessageListener(FAILURE_MSGBOX_ID, MessageBox.Events.ButtonPressed,
    function(buttonID, data)
        if buttonID == MSGBOX_BUTTON_JUMP then
            Net.PostToServer(QuickForge.NETMSG_JUMP, {
                CharacterNetID = Client.GetCharacter().NetID,
                ItemNetID = data.QuickForgeItemNetID,
                Option = data.QuickForgeOption,
            })
        end
    end)

Net.RegisterListener(QuickForge.NETMSG_PREVIEW, function(payload)
    if payload.Outcome == "ok" then
        local item = payload:GetItem()
        if item then
            UI.Open(item, payload.Option, payload.MatType, payload.Cost, payload.Funds)
        end
    else
        ShowFailureDialog(payload.Outcome, payload.ItemNetID, payload.Option)
    end
end)

Net.RegisterListener(QuickForge.NETMSG_COMMIT_RESULT, function(payload)
    local current = UI._Current
    -- Do not resolve the item: a successful Dismantle/Transmute destroyed it.
    if not current or current.ItemNetID ~= payload.ItemNetID or current.Option ~= payload.Option then
        return
    end
    UI.Close() -- The preview is stale either way.

    if payload.Outcome == "success" then
        Notification.ShowNotification(
            QuickForge.TranslatedStrings.Toast_Success:GetString():format(GetOptionLabel(payload.Option)))
    else
        ShowFailureDialog(payload.Outcome, payload.ItemNetID, payload.Option)
    end
end)
