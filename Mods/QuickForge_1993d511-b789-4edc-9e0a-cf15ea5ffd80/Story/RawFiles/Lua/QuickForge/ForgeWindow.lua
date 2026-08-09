---------------------------------------------
-- QuickForge client: the Forge Window — the confirm layer for a Direct
-- Operation. Item icon with native tooltip, EE2's own option description,
-- EE2-computed cost next to the player's matching funds, Confirm/Cancel.
-- Picker options add a selectable list (properties or Donors) between the
-- description and the cost line; nothing is pre-selected and Confirm stays
-- disabled until the player picks an eligible, affordable row.
-- Everything shown is read live from EE2's data via the server preview;
-- the window is only a preview — the server re-validates at commit time.
---------------------------------------------

local QuickForge = Epip.GetFeature("QuickForge", "QuickForge", true) ---@type Features.QuickForge
local Core = QuickForge.Core
local Generic = Client.UI.Generic
local MessageBox = Client.UI.MessageBox
local Notification = Client.UI.Notification
local TooltipPanelPrefab = Generic.GetPrefab("GenericUI_Prefab_TooltipPanel")
local TextPrefab = Generic.GetPrefab("GenericUI_Prefab_Text")
local ButtonPrefab = Generic.GetPrefab("GenericUI_Prefab_Button")
local HotbarSlotPrefab = Generic.GetPrefab("GenericUI_Prefab_HotbarSlot")
local CloseButtonPrefab = Generic.GetPrefab("GenericUI_Prefab_CloseButton")
local Input = Client.Input
local Tooltip = Client.Tooltip
local V = Vector.Create

local FAILURE_MSGBOX_ID = "QuickForge_OperationRefused"
local DONOR_REFUSED_MSGBOX_ID = "QuickForge_DonorRefused"
local MSGBOX_BUTTON_JUMP = 1
local MSGBOX_BUTTON_DISMISS = 2

local ROW_COLOR_NORMAL = Color.LARIAN.LIGHT_GRAY
local ROW_COLOR_SELECTED = Color.LARIAN.GOLD
local ROW_COLOR_INELIGIBLE = Color.LARIAN.DARK_GRAY
local ROW_ALPHA_NORMAL = 0.2
local ROW_ALPHA_HOVER = 0.4
local ROW_ALPHA_SELECTED = 0.5
local ROW_ALPHA_INELIGIBLE = 0.1

local UI = Generic.Create("QuickForge_ForgeWindow", {Visible = false})
UI.PANEL_SIZE = V(400, 400)
UI.PANEL_SIZE_PICKER = V(400, 610)
UI.HEADER_SIZE = V(380, 50)
UI.DESC_SIZE = V(340, 120)
UI.LINE_SIZE = V(340, 30)
UI.PICKER_SIZE = V(340, 230)
UI.PICKER_ROW_SIZE = V(320, 32)
UI.PICKER_ROW_SIZE_DONOR = V(320, 56)
UI._Initialized = false
---The previewed operation awaiting confirmation, if the window is open.
---@type {ItemNetID: NetId, Option: string, PickerKind: QuickForge.PickerKind?, Rows: QuickForge.PickerRow[]?, InvalidDonors: table<string, string>?, FlatCost: integer?, Funds: integer, MatType: string?, SelectedKey: string?}?
UI._Current = nil
---Per-row UI pieces of the open picker, by row key.
---@type table<string, {Background: GenericUI_Element_TiledBackground, Text: GenericUI_Prefab_Text, Row: QuickForge.PickerRow}>
UI._RowElements = {}
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

    -- Combine's Donor slot, beside the target item: dragging an inventory
    -- item onto it drives exactly the same selection the list drives.
    -- Hidden for every other option.
    local donorSlot = HotbarSlotPrefab.Create(UI, "DonorSlot", bg)
    donorSlot:SetUpdateDelay(-1)
    donorSlot:SetUsable(false)
    donorSlot:SetCanDrop(true)
    donorSlot:SetValidObjectTypes({Item = true})
    donorSlot.SlotElement:SetPositionRelativeToParent("Top", 70, 75)
    donorSlot.Events.ObjectDraggedIn:Subscribe(function(ev)
        UI._OnDonorDropped(ev)
    end)
    -- Hint while empty; the prefab's own hover shows the item tooltip (and
    -- hides on mouse-out) once filled.
    donorSlot.SlotElement.Events.MouseOver:Subscribe(function(_)
        if donorSlot:IsEmpty() then
            Tooltip.ShowSimpleTooltip({
                Label = QuickForge.TranslatedStrings.DropSlot_Hint:GetString(),
                TooltipStyle = "Simple",
                MouseStickMode = "None",
                UseDelay = true,
            })
        end
    end)
    UI.DonorSlot = donorSlot

    local desc = TextPrefab.Create(UI, "Description", bg, "", "Center", UI.DESC_SIZE)
    desc:SetPositionRelativeToParent("Top", 0, 155)
    desc:GetMainElement():SetWordWrap(true)
    UI.DescriptionText = desc

    -- Picker list for the options that need a selection; hidden otherwise.
    -- Positioned explicitly: relative-to-parent anchoring reads the list's
    -- width at call time, which is 0 while it has no rows.
    local picker = bg:AddChild("PickerList", "GenericUI_Element_ScrollList")
    picker:SetFrame(UI.PICKER_SIZE:unpack())
    picker:SetMouseWheelEnabled(true)
    picker:SetPosition((UI.PANEL_SIZE[1] - UI.PICKER_ROW_SIZE[1]) / 2, 280)
    UI.PickerList = picker

    local cost = TextPrefab.Create(UI, "CostLine", bg, "", "Center", UI.LINE_SIZE)
    cost:SetPositionRelativeToParent("Bottom", 0, -105)
    UI.CostText = cost

    local funds = TextPrefab.Create(UI, "FundsLine", bg, "", "Center", UI.LINE_SIZE)
    funds:SetPositionRelativeToParent("Bottom", 0, -75)
    UI.FundsText = funds

    -- A horizontal list lays the pair out side by side regardless of the
    -- styles' texture sizes (Epip's InputBinder pattern).
    local buttonList = bg:AddChild("ButtonList", "GenericUI_Element_HorizontalList")
    UI.ButtonList = buttonList

    local confirm = ButtonPrefab.Create(UI, "Confirm", buttonList, ButtonPrefab.STYLES.GreenSmallTextured)
    confirm:SetLabel(Text.CommonStrings.Confirm)
    confirm.Events.Pressed:Subscribe(function(_)
        UI._ConfirmPressed()
    end)
    UI.ConfirmButton = confirm

    local cancel = ButtonPrefab.Create(UI, "Cancel", buttonList, ButtonPrefab.STYLES.SmallRed)
    cancel:SetLabel(Text.CommonStrings.Cancel)
    cancel.Events.Pressed:Subscribe(function(_)
        UI.Close()
    end)

    buttonList:RepositionElements()
    buttonList:SetPositionRelativeToParent("Bottom", 0, -30)

    UI:SetPanelSize(UI.PANEL_SIZE)
    UI._Initialized = true
end

---Sizes the panel for the option at hand and re-anchors the bottom-row
---elements (bottom-relative positions are computed at call time, not live).
---The Donor picker shifts the target item aside to make room for the Donor
---slot next to it.
---@param pickerKind QuickForge.PickerKind?
function UI._Layout(pickerKind)
    local size = pickerKind ~= nil and UI.PANEL_SIZE_PICKER or UI.PANEL_SIZE
    UI.Panel.Background:SetBackground("FormattedTooltip", size:unpack())
    UI:SetPanelSize(size)
    UI.PickerList:SetVisible(pickerKind ~= nil)

    local hasDonorSlot = pickerKind == "donor"
    UI.DonorSlot.SlotElement:SetVisible(hasDonorSlot)
    if hasDonorSlot then
        UI.ItemSlot.SlotElement:SetPositionRelativeToParent("Top", -40, 75)
        UI.DonorSlot.SlotElement:SetPositionRelativeToParent("Top", 40, 75)
    else
        UI.ItemSlot.SlotElement:SetPositionRelativeToParent("Top", 0, 75)
    end

    UI.CostText:SetPositionRelativeToParent("Bottom", 0, -105)
    UI.FundsText:SetPositionRelativeToParent("Bottom", 0, -75)
    UI.ButtonList:SetPositionRelativeToParent("Bottom", 0, -30)
end

---------------------------------------------
-- PICKER
---------------------------------------------

---The reason line shown when hovering a greyed row — EE2's own reason
---strings, the same ones its Greatforge page would box at the player.
---@param row QuickForge.PickerRow
---@return string
function UI._GetRowReason(row)
    if row.Reason == "maxed" then
        return Text.GetTranslatedString("AMER_UI_Greatforge_Masterwork_PropertyMaxed", "")
    elseif row.Reason == "level_too_high" then
        return Text.GetTranslatedString("AMER_UI_Greatforge_Masterwork_LevelTooHigh", "")
            .. tostring(row.UptierLevel)
    end
    return ""
end

---A row's one-line label. Property rows: name, value change, per-row cost.
---Donor rows: the item's name and the Property it would transfer.
---@param row QuickForge.PickerRow
---@param selected boolean
---@return string
function UI._GetRowLabel(row, selected)
    local label
    if row.ItemNetID ~= nil then
        local donorItem = Item.Get(row.ItemNetID)
        local name = donorItem and Item.GetDisplayName(donorItem) or ""
        label = ("%s - %s"):format(name,
            Text.GetTranslatedString("AMER_Deltamod_" .. row.Prefix, row.Prefix))
    else
        label = Text.GetTranslatedString("AMER_Deltamod_" .. row.Prefix, row.Prefix)
        if row.Current ~= nil and row.Uptiered ~= nil then
            label = ("%s  %d -> %d"):format(label, row.Current, row.Uptiered)
        elseif row.Current ~= nil then
            label = ("%s  %d"):format(label, row.Current)
        end
        if row.Cost ~= nil then
            label = ("%s  (%d)"):format(label, row.Cost)
        end
    end

    local color = ROW_COLOR_NORMAL
    if not row.Eligible then
        color = ROW_COLOR_INELIGIBLE
    elseif selected then
        color = ROW_COLOR_SELECTED
    end
    return Text.Format(label, {Color = color})
end

---Rebuilds the picker list for a fresh preview.
---@param rows QuickForge.PickerRow[]
---@param pickerKind QuickForge.PickerKind
function UI._BuildPickerRows(rows, pickerKind)
    local list = UI.PickerList
    list:Clear()
    UI._RowElements = {}

    -- Zero valid Donors is a legitimate window: say so explicitly.
    if not rows[1] and pickerKind == "donor" then
        local empty = TextPrefab.Create(UI, "PickerEmptyState", list,
            Text.Format(QuickForge.TranslatedStrings.Picker_NoDonors:GetString(),
                {Color = ROW_COLOR_INELIGIBLE}),
            "Center", UI.PICKER_ROW_SIZE)
        empty:GetMainElement():SetWordWrap(true)
        list:RepositionElements()
        return
    end

    local isDonorPicker = pickerKind == "donor"
    local rowSize = isDonorPicker and UI.PICKER_ROW_SIZE_DONOR or UI.PICKER_ROW_SIZE

    for i, row in ipairs(rows) do
        local rowBg = list:AddChild("PickerRow_" .. i, "GenericUI_Element_TiledBackground")
        rowBg:SetBackground("Black", rowSize:unpack())

        local text
        if isDonorPicker then
            -- Item icon with rarity frame and native tooltip, name and
            -- transferred Property beside it.
            local slot = HotbarSlotPrefab.Create(UI, "PickerRowSlot_" .. i, rowBg)
            slot:SetUpdateDelay(-1)
            slot:SetUsable(false)
            slot.SlotElement:SetPosition(4, 2)
            local donorItem = Item.Get(row.ItemNetID)
            if donorItem then
                slot:SetItem(donorItem)
            end
            slot.Events.Clicked:Subscribe(function(_)
                UI._SelectRow(row.Key)
            end)

            text = TextPrefab.Create(UI, "PickerRowText_" .. i, rowBg, "", "Left",
                V(rowSize[1] - 64, rowSize[2]))
            text:SetPosition(62, 18)
        else
            text = TextPrefab.Create(UI, "PickerRowText_" .. i, rowBg, "", "Center", rowSize)
        end

        if Core.IsPickerRowSelectable(row) then
            rowBg.Events.MouseUp:Subscribe(function(_)
                UI._SelectRow(row.Key)
            end)
            rowBg.Events.MouseOver:Subscribe(function(_)
                local current = UI._Current
                if current and current.SelectedKey ~= row.Key then
                    rowBg:SetAlpha(ROW_ALPHA_HOVER)
                end
            end)
            rowBg.Events.MouseOut:Subscribe(function(_)
                UI._RefreshRowElement(row.Key)
            end)
        else
            rowBg:SetTooltip("Simple", UI._GetRowReason(row))
        end

        UI._RowElements[row.Key] = {Background = rowBg, Text = text, Row = row}
        UI._RefreshRowElement(row.Key)
    end
    list:RepositionElements()
end

---Restyles one row to match the current selection state.
---@param key string
function UI._RefreshRowElement(key)
    local entry = UI._RowElements[key]
    local current = UI._Current
    if not entry or not current then return end

    local selected = current.SelectedKey == key
    entry.Text:SetText(UI._GetRowLabel(entry.Row, selected))
    if not entry.Row.Eligible then
        entry.Background:SetAlpha(ROW_ALPHA_INELIGIBLE)
    elseif selected then
        entry.Background:SetAlpha(ROW_ALPHA_SELECTED)
    else
        entry.Background:SetAlpha(ROW_ALPHA_NORMAL)
    end
end

---@param key string
function UI._SelectRow(key)
    local current = UI._Current
    if not current then return end

    current.SelectedKey = key
    for rowKey in pairs(UI._RowElements) do
        UI._RefreshRowElement(rowKey)
    end
    if current.PickerKind == "donor" then
        -- List and slot never disagree about the current Donor.
        UI._SyncDonorSlot()
    end
    UI._RefreshCostAndConfirm()
end

---Makes the Donor slot show the current selection (or nothing).
function UI._SyncDonorSlot()
    local current = UI._Current
    local row = current and current.Rows
        and Core.FindPickerRow(current.Rows, current.SelectedKey) or nil
    local donorItem = row and Item.Get(row.ItemNetID) or nil
    if donorItem then
        UI.DonorSlot:SetItem(donorItem)
    else
        UI.DonorSlot:Clear()
    end
end

---Handles a drop on the Donor slot. The prefab has already placed the
---dropped item visually; a drop outside the server-computed valid-Donor
---set is refused with its reason and the slot reverts (never-silent).
---@param ev GenericUI_Prefab_HotbarSlot_Event_ObjectDraggedIn
function UI._OnDonorDropped(ev)
    local current = UI._Current
    local droppedItem = ev.Object and ev.Object.ItemHandle and Item.Get(ev.Object.ItemHandle) or nil
    if not current or current.PickerKind ~= "donor" or not droppedItem then
        UI._SyncDonorSlot()
        return
    end

    for _, row in ipairs(current.Rows or {}) do
        if row.ItemNetID == droppedItem.NetID then
            UI._SelectRow(row.Key)
            return
        end
    end

    UI._SyncDonorSlot()
    UI._ShowDonorRefusal(droppedItem)
end

---Names the reason a dropped item cannot be the Donor: EE2's own message
---for candidates its checks refused, QuickForge's for equipped items and
---for anything outside the scanned set.
---@param droppedItem EclItem
function UI._ShowDonorRefusal(droppedItem)
    local current = UI._Current
    local reason = current and current.InvalidDonors
        and current.InvalidDonors[tostring(droppedItem.NetID)] or nil

    local body
    if reason == "QuickForge_Equipped" then
        body = QuickForge.TranslatedStrings.Error_DonorEquipped:GetString()
    elseif reason then
        body = Text.GetTranslatedString("AMER_UI_Greatforge_Combine_" .. reason,
            QuickForge.TranslatedStrings.Error_DonorInvalid:GetString())
    else
        body = QuickForge.TranslatedStrings.Error_DonorInvalid:GetString()
    end

    MessageBox.Open({
        ID = DONOR_REFUSED_MSGBOX_ID,
        Header = GetOptionLabel("Combine"),
        Message = body,
        Buttons = {
            {ID = MSGBOX_BUTTON_DISMISS, Text = Text.CommonStrings.Close:GetString()},
        },
    })
end

---Updates the cost line and the Confirm gate from the current selection.
---Visual gating only; the server re-validates everything at commit time.
function UI._RefreshCostAndConfirm()
    local current = UI._Current
    if not current then return end

    local costTSK = current.MatType == "Gold"
        and QuickForge.TranslatedStrings.ForgeWindow_CostGold
        or QuickForge.TranslatedStrings.ForgeWindow_CostSplinters

    if current.Rows then
        local row = Core.FindPickerRow(current.Rows, current.SelectedKey)
        local cost = current.FlatCost
        if row then
            cost = Core.GetPickerSelectionCost(row, current.FlatCost)
        end
        if cost ~= nil then
            UI.CostText:SetText(costTSK:GetString():format(cost))
        else
            UI.CostText:SetText(QuickForge.TranslatedStrings.Picker_NoSelectionCost:GetString())
        end
        UI.ConfirmButton:SetEnabled(Core.CanConfirmPicker(row, current.FlatCost, current.Funds))
    else
        UI.CostText:SetText(costTSK:GetString():format(current.FlatCost))
        UI.ConfirmButton:SetEnabled(current.Funds >= current.FlatCost)
    end
end

---------------------------------------------
-- OPEN/CLOSE/CONFIRM
---------------------------------------------

---Opens the window for a previewed operation.
---@param item EclItem
---@param preview QuickForge.NetMsgs.Preview
function UI.Open(item, preview)
    UI._Initialize()

    -- Whether a picker is shown follows the option, not the reply: an empty
    -- Donor list is a legitimate preview and must still open as a picker.
    local pickerKind = Core.GetPicker(preview.Option)
    UI._Current = {
        ItemNetID = item.NetID,
        Option = preview.Option,
        PickerKind = pickerKind,
        Rows = pickerKind ~= nil and (preview.Rows or {}) or nil,
        InvalidDonors = preview.InvalidDonors,
        FlatCost = preview.Cost,
        Funds = preview.Funds,
        MatType = preview.MatType,
        SelectedKey = nil,
    }

    UI.Panel.HeaderText:SetText(GetOptionLabel(preview.Option))
    UI.ItemSlot:SetItem(item)
    UI.DescriptionText:SetText(Text.GetTranslatedString("AMER_UI_Greatforge_Desc_" .. preview.Option, ""))
    UI.FundsText:SetText(QuickForge.TranslatedStrings.ForgeWindow_CurrentFunds:GetString():format(preview.Funds))

    UI._Layout(pickerKind)
    if UI._Current.Rows then
        UI._BuildPickerRows(UI._Current.Rows, pickerKind)
    end
    if pickerKind == "donor" then
        UI._SyncDonorSlot()
    end
    UI._RefreshCostAndConfirm()

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
    -- Picker options commit a deliberate selection; without one the button
    -- is disabled, so this is only a race guard.
    if current.Rows and not current.SelectedKey then return end

    -- Await the result; re-enabled on the next Open().
    UI.ConfirmButton:SetEnabled(false)
    Net.PostToServer(QuickForge.NETMSG_COMMIT, {
        CharacterNetID = Client.GetCharacter().NetID,
        ItemNetID = current.ItemNetID,
        Option = current.Option,
        SelectionKey = current.SelectedKey,
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
    elseif outcome == "stale_selection" then
        -- The previewed selection no longer matches the item's live rows;
        -- no EE2 box exists for this (its UI cannot get here). The
        -- Greatforge can resolve it: the player re-picks there.
        header = GetOptionLabel(option)
        body = QuickForge.TranslatedStrings.Error_StaleSelection:GetString()
        offerJump = true
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
            UI.Open(item, payload)
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
