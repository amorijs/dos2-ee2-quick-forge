# Research: Epip's Generic UI framework (for the Forge Window)

Researched 2026-08-08 against the unpacked sources in `references/` (untracked).
Question: what UI machinery does Epip provide for a custom window (options,
costs, pickers, confirm)?

**Verdict: everything the Forge Window needs exists off the shelf.** Epip
ships a retained-mode Lua UI framework ("Generic") needing zero Flash
authoring, drawn with ripped Larian textures and the game's own tooltip
system — visually indistinguishable from vanilla DOS2 UI. QuickForge already
imports Epip globals (`BootstrapClient.lua:14`), so `Client.UI.Generic` is
directly reachable.

Path shorthand:
`L:` = `references\epip\Mods\EpipEncounters_7d32cb52-1cfd-4526-9b84-db4867bf9356\Story\RawFiles\Lua`

## 1. The Generic framework

### Entry points — `L:\UI\Generic\Main.lua`

- `Client.UI.Generic` (alias `Generic`), `Main.lua:3-12`. `SWF_PATH =
  "Public/EpipEncounters_.../GUI/generic.swf"`, `DEFAULT_LAYER = 15`.
- `Generic.Create(id, config) -> GenericUI_Instance` — `Main.lua:27`;
  config `{Layer:integer?, Visible:boolean?}`. Internally
  `Ext.UI.Create(id, SWF_PATH, layer)` (`Main.lua:46`), hidden unless
  `Visible` (`Main.lua:109-111`).
- `Generic.GetPrefab(className)` — `Main.lua:119`; `Generic.RegisterPrefab` —
  `Main.lua:182`.

`L:\UI\Generic\Instance.lua` — `GenericUI_Instance` inherits Epip's `UI` base
class (`Instance.lua:30`), so instances also have
`Show/Hide/IsVisible/SetPositionRelativeToViewport/SetPanelSize/PlaySound/…`
(§5). Key methods: `ui:CreateElement(id, type, parent?)` (`Instance.lua:123`),
`ui:GetElementByID` (`:63`), `ui:DestroyElement` (`:76`), `ui:Destroy`
(`:103`), `ui:SetIggyEventCapture(eventID, capture)` (`:70`),
`ui:GetMousePosition()` (`:168`).

### Element types (primitives)

Canonical list at `L:\UI\Generic\Elements\Element.lua:11` (usable as
`"GenericUI_Element_X"` or `"X"`, prefix stripped at `Instance.lua:124`):

`Empty`, `TiledBackground`, `Text`, `IggyIcon`, `Button`, `VerticalList`,
`HorizontalList`, `ScrollList`, `StateButton`, `Divider`, `Slot`, `ComboBox`,
`Slider`, `Grid`, `Color`, `Texture`

Highlights (files under `L:\UI\Generic\Elements\`):

- **TiledBackground** — `SetBackground("RedPrompt"|"Black"|"FormattedTooltip"|"Note", w, h)`
  (`TiledBackground.lua:8-14`): native DOS2 tiled panel skins.
- **Text** — `SetText`, `SetType(align)`, **`SetEditable(bool)` (text input)**,
  `SetMaxCharacters`, `SetRestrictedCharacters`, `SetWordWrap`, `FitSize()`,
  `SetStroke`, `SetTextFormat`; events `Changed{Text}`, `Focused`, `Unfocused`
  (`Text.lua:64-152`).
- **ScrollList** — VerticalList + scrollbar; `SetFrame(w,h)`,
  `SetMouseWheelEnabled`, `SetScrollbarSpacing` (`ScrollList.lua:15-17`).
- **Slot** — vanilla hotbar-slot graphic (frame, cooldown, highlight, label);
  events `Clicked`, `DragStarted` (`Slot.lua:33-39`).
- **IggyIcon** — `SetIcon(icon, w, h, materialGUID?)` (`IggyIcon.lua:30`).
- **ComboBox** — `SetOptions({{ID,Label},…})`, `SelectOption(id)`; event
  `OptionSelected{Index, Option}` (`Main.lua:324-334`).
- Base Element API (`Elements\Element.lua`): `AddChild` (`:100`),
  `SetPositionRelativeToParent(pos, xOff?, yOff?)` (9 anchors, alias `:13`),
  `SetSize/SetSizeOverride`, `SetVisible`, `SetAlpha`, `SetMouseEnabled`,
  **`SetAsDraggableArea()`** (`:172`),
  **`SetTooltip("Simple"|"Skill"|"Custom", data)`** (`:395`),
  `Tween(...)` (`:286`); events `MouseUp/MouseDown/MouseOver/MouseOut/RightClick/…`
  (`:32-41`).

### Prefabs (composite widgets) — `L:\UI\Generic\Prefabs\`

Fetched with `Generic.GetPrefab("<ID>")`; all have `.Create(ui, id, parent, …)`.

Windows/chrome:

| Prefab | What it is | File:line |
|---|---|---|
| `GenericUI_Prefab_TooltipPanel` | **The standard Epip window**: FormattedTooltip background + centered stroked header. `Create(ui, id, parent, size, header, headerSize)`. | `TooltipPanel.lua:31` |
| `GenericUI_Prefab_CloseButton` | X button that hides the UI; `Hooks.CanClose`. | `CloseButton.lua:28` |
| `GenericUI_Prefab_DraggingArea` | Invisible drag handle rect. | `DraggingArea.lua:27` |
| `GenericUI.Prefabs.SlicedTexture` | 9-slice resizable frame; styles incl. `SimpleTooltip`, `ContextMenu`. | `SlicedTexture\Prefab.lua:72`, `Styles.lua:26` |

Controls:

| Prefab | Notes | File |
|---|---|---|
| `GenericUI_Prefab_Button` | Texture-styled button: `SetLabel`, `SetIcon`, `SetEnabled`, `SetTooltip`; events `Pressed`, `RightClicked`. **~110 named styles** (`LargeRed`, `LargeBrown`, `GreenSmallTextured`, `TransparentLong`, checkbox pairs, …). | `Button\Prefab.lua:56`, `Button\Styles.lua:24-497` |
| `GenericUI_Prefab_Text` | Text + align + size. | `Text.lua:34` |
| `GenericUI_Prefab_LabelledCheckbox` / `LabelledDropdown` / `LabelledSlider` / `LabelledTextField` / `Spinner` / `SearchBar` | Labelled form rows; `FormElement` base auto-creates a controller-nav component (`FormElement.lua:202`). | `Prefabs\*` |
| `GenericUI_Prefab_Selector` | "◄ Label: Value ►" chooser **with per-option sub-element containers** — natural fit for "pick option, show its controls beneath". `GetSubElementContainer(i)`, `Events.Updated{Index}`. | `Selector.lua:46,71,99` |
| `GenericUI.Prefabs.PooledContainer` | Object pool over any container (`GetItem(i)`, `Clear()`); used by QuickLoot's grid. | `Containers\PooledContainer.lua:31` |

## 2. Real examples (ranked by relevance)

- **QuickLoot** — `L:\Epip\QuickLoot\Client_UI.lua` (696 lines; + 88-line
  controller nav). `UI._Initialize()` at `:393-493` is the recipe: panel +
  drag + close + styled action button + ScrollList/Grid of pooled slots +
  escape handling (`SetIggyEventCapture("ToggleInGameMenu", true)`, `:472-478`)
  + `UILayout.RestorePosition` (`:489`).
- **QuickInventory** — `L:\Epip\QuickInventory\UI.lua` (372 lines). Already
  Greatforge-integrated (closes on `Feature_GreatforgeDragDrop.Events.ItemDropped`,
  `:365-373`) and opened from an item context menu (`:331-351`).
- **RadialMenus MenuCreator** — `L:\Epip\RadialMenus\UI\MenuCreator.lua`
  (571 lines): modal editor with pickers, confirm MessageBox, `OF_PlayerModal1`.
- **IconPicker** — `L:\Epip\IconPicker\UI.lua` (**134 lines**) — the minimal
  end-to-end "choose one from a grid" window. Read first.
- **Annotated tutorial (81 lines):** `L:\Epip\Examples\GenericUI.lua` —
  background, close, header, list, ComboBox, Spinner, accept button.

## 3. Item display: icon + rarity frame + native tooltip — YES

**`GenericUI_Prefab_HotbarSlot`** — `L:\UI\Generic\Prefabs\HotbarSlot.lua`
(601 lines). Exactly the widget for "the benched item" / "pick a donor item":

```lua
local HotbarSlot = Generic.GetPrefab("GenericUI_Prefab_HotbarSlot")
local slot = HotbarSlot.Create(UI, "ItemSlot", parent, {TextLabel = true}) -- :123
slot:SetItem(item)       -- :212 — real icon + rarity frame + rune overlay
slot:SetUpdateDelay(-1)  -- disable 0.1s auto-refresh
slot:SetCanDrop(true)    -- accept item drag-in (donor picker)
slot:SetUsable(false)    -- clicking won't use the item
slot.Events.ObjectDraggedIn:Subscribe(function (ev) ... end)
```

`SetItem` (`:212-239`) uses `Item.GetIcon` (`Utilities\Item\Shared.lua:387`),
`Item.GetRarityIcon` (`:1219` via `HotbarSlot.lua:274-291`), and
`Item.GetRuneSlotsIcon` (`:1169`). **Native item tooltip on hover** is built
in: `_ShowTooltip()` (`HotbarSlot.lua:411-429`) calls
`Tooltip.ShowItemTooltip(entity, position)`; placement hookable via
`slot.Hooks.GetTooltipData` (example `QuickInventory\UI.lua:138-140`).
Labelled-row wrapper: `GenericUI.Prefab.Form.Slot` (`LabelledSlot.lua:29`).

## 4. Tooltips, fonts, styling

- **TooltipLib** (`L:\Utilities\Client\Tooltip\Main.lua`):
  `Tooltip.ShowItemTooltip(item, pos?)` `:464`, `ShowSkillTooltip` `:448`,
  `ShowSimpleTooltip(data)` `:368` (`{Label, MouseStickMode, TooltipStyle}`,
  `:193-200`), `ShowCustomFormattedTooltip` `:425` (element arrays incl.
  `{Type="ItemName"|"ItemDescription"|"ItemRarity"}` — see
  `SettingWidgets\Client.lua:456-479`; the right pattern for a cost-breakdown
  tooltip in native chrome), `HideTooltip()` `:501`. Shortcut:
  `element:SetTooltip(type, data)`.
- **TextLib** (`L:\Utilities\Text\Library.lua`): `Text.FONTS` `:14-20`,
  `Text.Format(str, {FontType?, Size?, Color?, Align?, FormatArgs?})` `:413`,
  and **`Text.CommonStrings`** (`CommonStrings.lua`, 1176 lines) —
  pre-translated `Confirm`, `Cancel`, `Close`, … (free localization).
- **Textures**: `Epip.GetFeature("Feature_GenericUITextures").TEXTURES`
  (`L:\Epip\GenericUITextures\Client.lua`, 2328 lines): `BACKGROUNDS`,
  `BUTTONS`, `FRAMES`, `PANELS` (~50 authentic DOS2 panels incl.
  `MESSAGE_BOX`, `MESSAGE_BOX_INPUT`, `LIST`, `TALL_PAGE*`, `:1546-1682`),
  `SLICED`, `INPUT`, `ICONS` (`:2152`).

## 5. Interaction model

From the `UI` base class (`L:\Tables\_UI.lua`): `Show/TryShow/Hide/TryHide`
(`:129-216`), `SetPositionRelativeToViewport(anchor, position)` (`:164`),
`SetPanelSize(Vector2)` (`:197`, needed for sane dragging/centering),
`PlaySound` (`:224`), `SetFlag/TogglePlayerInput` (`:289,:245`).

Input focus/blocking, all used in the wild:

1. `OF_PlayerInput1` — whether the UI captures input at all
   (`_UI.lua:240-254`).
2. `OF_PlayerModal1` — modal, blocks game input beneath:
   `ui:GetUI().OF_PlayerModal1 = true`. Epip sets it always for RadialMenus
   (`RadialMenus\UI\Main.lua:90`) and the settings menu, controller-only for
   QuickInventory/QuickLoot (`QuickInventory\UI.lua:156-158`). Epip's Input
   library treats any `OF_PlayerModal*` UI as modal
   (`Utilities\Client\Input\Main.lua:882`).
3. Iggy event capture — `ui:SetIggyEventCapture("UICancel"|"ToggleInGameMenu", true)`
   + `ui.Events.IggyEventDownCaptured` (`Main.lua:341-350`).

KBM idioms: escape-to-close via `Client.Input.Events.KeyStateChanged`
(`QuickInventory\UI.lua:316-321`); close-on-click-outside via
`Client.IsCursorOverUI()` (`:324-328`). Position persistence:
`UILayout.RegisterTrackedUI(ui)` + `UILayout.RestorePosition(ui)`
(`L:\Epip\UILayout\Client.lua:46,85`).

Controller: fully supported via opt-in navigation layer
(`L:\UI\Generic\Navigation\`, `Controller.lua:24,112-140`; worked example
`QuickLoot\Client_UI_Navigation.lua`, 88 lines). Generic UI itself has no KBM
limitation — only Epip's *context menu* does; omitting a nav layer just means
mouse-only.

## 6. Client → server: net messages

`Net` (global via `Epip.ImportGlobals`): `Net.PostToServer(channel, msg?)`
(`L:\Utilities\Net\Client.lua:6`, auto-JSON), `Net.RegisterListener(channel, fn)`
(`Shared.lua:159`), server→client `PostToCharacter/PostToUser/PostToOwner/Broadcast`
(`Shared.lua:106-141`). Payload mix-ins `NetLib_Message_Character` /
`NetLib_Message_Item` give `payload:GetCharacter()` / `:GetItem()`
(`Shared.lua:60,72`) — the idiom is sending
`{CharacterNetID = char.NetID, ItemNetID = item.NetID}`.

Canonical Greatforge-adjacent example (~140 lines across 3 files):
`L:\Epip\GreatforgeDragDrop\Shared.lua:8,42`, `Client.lua:47-50`,
`Server.lua:11-35`. Round-trip example (server → client dialog → server):
`L:\Epip\Greatforge\Engrave\Client.lua:11-36`. QuickForge's
`Client.lua:133` already uses this pattern.

Related: `Game.AMERUI` (`L:\Game\AMERUI\Shared.lua:11-18`) models EE physical-UI
state (`INTERFACES.GREATFORGE`, `NETMSG_STATE_CHANGED`,
`ClientIsInSocketScreen()`).

## 7. Simpler alternatives

### MessageBox — one-call native dialog ✅

`L:\UI\MessageBox.lua` (`Client.UI.MessageBox`), hooks vanilla `msgBox.swf`.
`MessageBox.Open(data)` (`:119`; data class `:68-84`):
`{Type: "Message"|"Input", ID, Header, Message, Buttons: {{ID?, Text, Type?}},
AcceptEmpty?}`. Listeners (`:169`):
`MessageBox.RegisterMessageListener(id, MessageBox.Events.ButtonPressed, fn)` /
`InputSubmitted` / `MessageShown`. Extra fields set on `data` survive into the
listener (context smuggling). Two-button confirm verbatim:
`L:\Epip\UnlearnSkills\Client.lua:74-83,101-105`. Text-input prompt:
`Type = "Input"`, `AcceptEmpty = false` — the Engrave rename
(`L:\Epip\Greatforge\Engrave\Client.lua:16-25`). Limitation: 4 button types,
no lists — confirm/notice/single-line-input only.

### ContextMenu — ready-made selection list

`L:\UI\ContextMenu.lua`: `Setup` `:353`, `Open` `:381`, `AddSubMenu` `:332`,
`RegisterElementListener` `:462`; entry fields `:116-152` (`subMenu`, `button`,
`checkbox`, `header`, `greyedOut`, `icon`, `params`). Already used by
QuickForge (`QuickForge\Client.lua:92-138`). No cost columns/item icons;
disabled on controller.

### Other lightweight paths

- Picker features with `Request(requestID)` → `Events.RequestCompleted`
  contract: `Features.SkillPicker` (`L:\Epip\SkillPicker\Client.lua:40,57`),
  `IconPicker`, `ColorPicker` — the shape to copy for a
  "GreatforgePropertyPicker"; consumption example
  `SettingWidgets\Client.lua:372-375,556-570`.
- `Features.SettingWidgets.RenderSetting(ui, parent, setting, size?, callback?, updateSettingValue?)`
  (`L:\Epip\SettingWidgets\Client.lua:95`) — declare a SettingsLib setting,
  get a fully styled, tooltip'd, controller-navigable form row;
  `updateSettingValue = false` for transient use.
- **Feedback toasts**: `Client.UI.Notification.ShowNotification(text, duration?, isWarning?, sound?)`
  / `ShowWarning` / `ShowIconNotification(text, icon, subTitle?, title?, hint?, sound?)`
  — `L:\UI\Notification.lua:56,103,73`.
- World-space hint text: `Client.UI.TextDisplay.ShowText(text, position)`
  (`L:\Epip\GreatforgeDragDrop\Client.lua:31-36`).

## 8. Recommended shape for the Forge Window

~150–250 lines modelled on `IconPicker\UI.lua` + `QuickLoot\Client_UI.lua:393-493`:

1. `Generic.Create("QuickForge.UI", {Layer = 13, Visible = false})`;
   `UILayout.RegisterTrackedUI(UI)`.
2. `TooltipPanel.Create(UI, "Background", nil, V(480, 520), header, V(460, 50))`.
3. `DraggingArea` + `CloseButton` (`"TopRight", -10, 10`).
4. A `HotbarSlot` showing the item (icon + rarity + native tooltip); a second
   with `SetCanDrop(true)` for the Combine donor (phase 2).
5. `ScrollList` of option rows — `ButtonPrefab` with
   `STYLES.TransparentLong`/`LargeBrown`, `SetEnabled(affordable)`,
   `SetTooltip("Custom", costTooltip)`.
6. Property picker: `LabelledDropdown` / `Selector`, or a second `ScrollList`
   (phase 2).
7. Confirm: `ButtonPrefab` `STYLES.GreenSmallTextured`,
   `SetPositionRelativeToParent("Bottom", 0, -13)`; `Pressed` →
   `Net.PostToServer(...)` → `UI:Hide()`.
8. `SetPanelSize`, `SetPositionRelativeToViewport("center","center")`,
   `UILayout.RestorePosition`, escape-to-close via `KeyStateChanged`.
