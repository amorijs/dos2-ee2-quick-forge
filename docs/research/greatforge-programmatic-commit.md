# Research: executing Greatforge options programmatically

Researched 2026-08-08 against the unpacked sources in `references/` (untracked).
Question: can QuickForge's own UI be the confirm layer, committing Greatforge
operations without EE2's physical UI?

**Verdict: yes, for all ten options.** Epip has already validated every
individual technique required. Nothing is genuinely UI-locked except the
Masterwork cost number (recoverable via EE2's own `GetCostInt` query) and
post-craft item delivery (recoverable via a helper container + timer).

Path shorthand:

- `EE2:` = `references\ee2\unpacked\Core\Mods\Epic_Encounters_Core_63bb9b65-2964-4c10-be5b-55a63ec02fa0\Story\RawFiles\Goals\`
- `EPIP:` = `references\epip\Mods\EpipEncounters_7d32cb52-1cfd-4526-9b84-db4867bf9356\Story\RawFiles\`

The two files that matter most: `EE2:AMER_GLO_UI_Greatforge.txt` (222 lines,
INITSECTION only — all option/cost/table data) and
`EE2:AMER_GLO_UI_Greatforge_Internal.txt` (2403 lines — all behaviour).

## 1. The commit path

### The chain, exactly

```
CharacterItemEvent(_Char, _, "AMER_UI_Greatforge_Confirm")            EE2:AMER_GLO_UI_Greatforge_Internal.txt:667
  requires DB_AMER_UI_UsersInUI(_Instance,"AMER_UI_Greatforge",_Char) :670
  requires DB_AMER_UI_Greatforge_SelectedOption(_Instance, _Name)     :672
  requires NOT QRY_AMER_UI_Greatforge_InvalidSelection(_Char, _Name)  :674   <-- ALL validation lives here
    -> PROC_AMER_UI_Greatforge_OptionRequested(_Instance,_Char,_Name) :676

PROC_AMER_UI_Greatforge_OptionRequested((INTEGER)_Instance,(CHARACTERGUID)_Char,(STRING)_Name)  :683
  reads DB_AMER_UI_Greatforge_SelectedOption_Cost(_Instance,_MatType,_Root,_Cost)  :685
  QRY_AMER_UI_Greatforge_OptionRequested_GetFinalCost(...)                          :687
  -> DB_AMER_UI_Funds_Required(_Char, _Name, _Root, _CostFinal, 1)                  :691
  -> PROC_AMER_UI_Funds_RequestOption(_Instance,"AMER_UI_Greatforge",_Char,_Name)   :695   <-- cost check + deduction

PROC_AMER_UI_Funds_RequestSuccess((INTEGER)_Instance,"AMER_UI_Greatforge",(CHARACTERGUID)_Char,(STRING)_RequestID)  :828
  requires DB_AMER_UI_Greatforge_BenchedItem(_Instance,_Char,_Item,_Level,_ItemType,_Slot,_SubType,_Handedness,_Value)  :830
  requires DB_AMER_UI_Greatforge_CraftObject_Reserved(_Instance,_CraftObject)                                          :832
  -> PROC_AMER_UI_Greatforge_DoCraft(_Instance,_Char,_CraftObject,_Item,_Level,_ItemType,_Slot,_SubType,_Handedness,_Value,_RequestID)  :834
```

### The execute proc

```
PROC PROC_AMER_UI_Greatforge_DoCraft(
    (INTEGER)_Instance, (CHARACTERGUID)_Char, (ITEMGUID)_Cont, (ITEMGUID)_Item,
    (REAL)_Level, (STRING)_ItemType, (STRING)_Slot, (STRING)_SubType,
    (INTEGER)_Handedness, (REAL)_Value, (STRING)_OptionName)
```

Per-option rule bodies: Reduce `:877`, ExtractRunes `:1112`, LevelUp `:1155`,
Masterwork `:1533` and `:1542`, Focalize `:1583`, RemoveMods `:1703`, Combine
`:2072`, Transmute `:2159`+`:2163`, plus two generic completion rules `:2229`
(anvil FX) and `:2236` (`MoveAllItemsTo(_Cont,_Char)` + return to
Page_MainHub).

### Where cost and validation live relative to the confirm — the key answer

**Neither is inside `DoCraft`. Both are strictly upstream of it, in the UI
layer.**

- **Validation** is `QRY_AMER_UI_Greatforge_InvalidSelection((CHARACTERGUID)_Char, (STRING)_Option)`
  (`:839, :1100, :1145, :1204, :1574, :1609, :1876, :2150`). Every single rule
  of it reads `DB_AMER_UI_Greatforge_BenchedItem(_Instance, _Char, _Item, ...)`
  to find the item — it takes no item parameter. Evaluated twice: on
  option-chosen (`:618`) and again on confirm (`:674`). Never runs from
  `DoCraft`.
- **Cost** is `DB_AMER_UI_Greatforge_SelectedOption_Cost(_Instance,...)`,
  only ever written by `PROC_AMER_UI_Greatforge_GenerateCostList` (`:523-552`)
  — i.e. as a side effect of drawing the cost list on the option wheel.
  `DoCraft` never sees a cost.
- **Deduction** is generic: `PROC_AMER_UI_Funds_RequestOption` →
  `PROC_AMER_UI_Funds_CheckFunds` → `PROC_AMER_UI_Funds_ExecRemoveList` →
  `PROC_AMER_UI_Funds_RemoveFunds` (`EE2:AMER_GLO_UI.txt:2495-2645`). Gold
  uses `UserGetGold`/`UserAddGold` (`:2523, :2640`), item currencies use
  user-inventory count/remove (`:2545-2570`).

**Consequence:** calling `Osi.PROC_AMER_UI_Greatforge_DoCraft(...)` directly
gets the effect for free and the cost/validation not at all.

**The recommended middle route:** populate the three instance DBs and call
`PROC_AMER_UI_Greatforge_OptionRequested` instead of `DoCraft`. From Lua,
insert `DB_AMER_UI_Greatforge_BenchedItem(...)`,
`DB_AMER_UI_Greatforge_SelectedOption_Cost(instance, matType, root, cost)`
and `DB_AMER_UI_Greatforge_CraftObject_Reserved(instance, craftObj)` — then
EE2's own funds check, insufficient-funds message box (`:824`), deduction, and
`DoCraft` dispatch all come along for free. You still supply the cost number
(which you must compute anyway to display it), and you still must call
`QRY_AMER_UI_Greatforge_InvalidSelection` yourself after seeding
`BenchedItem`.

### The hard blocker on all of the above

`AMER_GLO_UI_Greatforge_Internal` is registered as an **internal-logic goal**
(`EE2:AMER_GLO_UI.txt:110`) and is activated only while `DB_AMER_UI_UsersInUI`
is non-empty (`references\ee2\unpacked\Main\...\Story\goals.raw:112362-112365`),
deactivated when it empties (`goals.raw:127396-127400`,
`AMER_GLO_UI.txt:3482-3492`). **While nobody is in a physical UI, `DoCraft`,
`OptionRequested`, `InvalidSelection`, `GenerateCost` and every picker query
simply do not exist.** Epip's workaround is
`PROC_AMER_GEN_Goal_Activate("AMER_GLO_UI_Greatforge_Internal")`, completing it
later only when `NOT DB_AMER_UI_UsersInUI(_,_,_)` — see §2. This is the single
most important structural fact for the whole redesign.

## 2. Precedent — how Epip does instant Dismantle / Extract Runes

Everything is in **`EPIP:Goals\PIP_GLO_QuickReduce.txt`** (316 lines), driven
from `EPIP:Lua\Epip\ContextMenus\Greatforge\Server.lua:12-25`, which just does
`Osi.PROC_PIP_QuickReduce(char, item)` /
`Osi.PROC_PIP_QuickExtractRunes(char, item)`.

**Verdict: Epip does NOT call EE2's commit path at all. It reimplements the
whole thing** — cost derivation, affordability, payment, and effect — calling
only always-active low-level EE2 procs.

### Extract Runes (`PIP_GLO_QuickReduce.txt:24-67`)

1. `:28` `PROC_AMER_GEN_Goal_Activate("AMER_GLO_UI_Greatforge_Internal")` +
   `:29` records `DB_PIP_Greatforge_QuickExtractRunes_Item(_Char,_Item)` as a
   re-entrancy guard.
2. `:37` `NRD_ModQuery2("EpipEncounters","GreatforgeGetItemData", ...)` — a
   Lua-backed Osiris query (`EPIP:Lua\BootstrapServer.lua:382-394`) returning
   item level / `ItemTypeReal` / `ItemSlot`, replacing EE2's async
   behaviour-hook item-level/type fetch.
3. `:39-43` `QRY_AMER_Deltamods_GenerateOnItem_GetItemSpecs_GetSubType` for
   subtype + handedness.
4. `:47` its own `QRY_PIP_Greatforge_GetCost(_Item, "ExtractRunes",
   "GreatforgeFrags", ...)`, which at `:83-91` reads EE2's
   `DB_AMER_UI_Greatforge_Option_Cost` and calls **EE2's real
   `QRY_AMER_UI_Greatforge_GenerateCost(0, ...)` with instance `0`**.
5. `:53` `QRY_PIP_Greatforge_Pay(...)` → `:96-101`
   `QRY_PIP_Greatforge_CanAfford` (own party-scoped check, `:119-125`
   `ItemTemplateIsInPartyInventory` of the Splinter template) →
   `PROC_PIP_Greatforge_Pay_Internal` (`:127-135`).
6. `:55` effect: `PROC_AMER_GEN_ItemRemoveRunes(_Char,_Item,0,2,1)` — EE2's
   generic proc, not `DoCraft`.
7. `:62-67` completes the goal again **only if `NOT DB_AMER_UI_UsersInUI(_,_,_)`**.

**Hack #1 (explicitly commented):** `:10-22` re-declares
`QRY_AMER_UI_Greatforge_GenerateCost_GetCustomMult(... "ExtractRunes" ...)` —
*"Necessary copy-paste as GF script relies on BenchedItem"* (`:9`). EE2's own
version (`EE2:...Internal.txt:1118-1130`) reads
`DB_AMER_UI_Greatforge_BenchedItem`; Epip's reads its own DB instead. The
canonical example of bench-DB coupling in the cost layer — and the canonical
way around it (seeding `BenchedItem` makes the copy-paste unnecessary).

### Dismantle (`PIP_GLO_QuickReduce.txt:140-231`)

Three-stage, driven by EE2's async behaviour-script hooks:
`PROC_AMER_GEN_ItemGetItemLevel` (`:140-149`) → `PROC_AMER_GEN_ItemGetItemType`
(`:151-167`) → activate the internal goal (`:170-172`); `:174-231` is a
line-by-line clone of EE2's `DoCraft` "Reduce" body
(`EE2:...Internal.txt:877-898`), plus its own cost block (`:206-220`),
`QRY_PIP_CanAffordQuickReduce` (`:241-247`, `UserGetGold`) and
`PartyAddGold(_Char,_GoldToRemove)` (`:229`).

**Hack #2 — the container.** `DoCraft` generates treasure into `_Cont` (the
reserved craft object) and the generic completion rule
`MoveAllItemsTo(_Cont,_Char)` (`EE2:...Internal.txt:2242`) only fires if
`DB_AMER_UI_ElementsOfInstance(_Instance,...,"CenterFrame","Frame",_Frame)`
exists (`:2238`) — i.e. only with a live UI instance. Epip substitutes
`QRY_AMER_GEN_GetHelperObjectAtPosition(1.0,1.0,1.0,1)` (`:190-192`), stashes
it in `DB_PIP_QuickReduce_ReservedContainer` (`:228`), and drains it on a
200 ms timer (`:227`, `:256-263`) with `MoveAllItemsTo` +
`PROC_AMER_GEN_UnreserveHelperObject`.

**Hack #3 — query only active in Ascension.** `:265-282` re-declares
`QRY_AMER_UI_Greatforge_Reduce_GetTableRarity_Pip` — *"Needed because the
original query is only active within Ascension"* (copy of
`EE2:...Internal.txt:902-918`). So even with the goal activated, Epip did not
trust intra-tick availability of internal-goal queries for at least this one.
Treat "internal-goal query availability in the same tick as activation" as an
empirical question to test, not an assumption.

**Hack #4 — failure cleanup.** `:293-309` clears `DB_PIP_QuickDismantling` on
`PROC_AMER_Hook_EventFailed` and on `SavegameLoaded`, because the behaviour
hooks can silently drop.

### Cull (RemoveMods) in the context menu — abandoned by Epip

`EPIP:Lua\Epip\ContextMenus\Greatforge\Client.lua:103` has the entry commented
out (`-- TODO finish`), and `Server.lua:41` calls
`Osi.PROC_PIP_QuickGreatforge_RemoveMods(...)` which is defined nowhere in
Epip's Osiris. The client-side picker (`Client.lua:136-184`) and the deltamod
table broadcast (`Server.lua:48-54`,
`Net.Broadcast("EPIPENCOUNTERS_QuickGreatforge_ModList", ...)`) do exist and
work. This is precisely the piece we would be finishing — and it tells you
Ameranth/Pip stopped at the picker options.

### Two more precedents worth copying

- **Benching from Lua without clicking:**
  `EPIP:Lua\Epip\GreatforgeDragDrop\Server.lua:11-24` — sets
  `Osi.DB_AMER_GEN_OUTPUT_Item:Delete(nil)` then
  `Osi.DB_AMER_GEN_OUTPUT_Item(item.MyGuid)` and calls
  `Osi.PROC_AMER_UI_Greatforge_ProcessCombine(char.MyGuid, 1)`. Direct proof
  that Lua can write EE2's Osiris output/state DBs and drive its procs.
- **Options implemented purely as `DoCraft` listeners:**
  `EPIP:Lua\Epip\Greatforge\DrillSockets\Server.lua:9-21`,
  `Engrave\Server.lua:9-21`, `Empower\Server.lua:10-16` all use
  `Osiris.RegisterSymbolListener('PROC_AMER_UI_Greatforge_DoCraft', 11,
  "after", ...)`. **If we call `DoCraft` ourselves, these fire** — AddSockets,
  Engrave, and the Empower `Generation.Level` fix keep working for free. If we
  instead reimplement effects à la QuickReduce, they silently don't.

## 3. Picker options

### The universal property source

`QRY_AMER_Deltamods_IterateMods_NotImplicit((ITEMGUID)_Item)`
(`EE2:AMER_GLO_Deltamods.txt:1738`; 4-arg form with `_Slot,_SubType,_Handedness`
at `:1754`) fills:

```
DB_AMER_Detamods_OUTPUT_CountedMods((INTEGER)_Index, (INTEGER)_ModIndex, (STRING)_Prefix, (STRING)_Deltamod, (INTEGER)_Value)
```

(note EE2's own typo: **Detamods**). Populated at `:1811`; de-duplicated per
prefix keeping the highest value at `:1814-1821`. This query lives in
`AMER_GLO_Deltamods` — an **always-active** goal, callable with no Greatforge
session.

Supporting always-active registries:
`DB_AMER_Deltamods_Mod_UniqueMod(_Prefix,_Deltamod,_Value)` (the one Epip
broadcasts to clients) and `DB_AMER_Deltamods_Mod(...)` (14 cols: index,
category, rarityMin, slot, subType, handednessFlag, parentPrefix, mod,
levelMin, value, decayChance, …).

Display name for a property = TSK key `"AMER_Deltamod_" .. _Prefix`
(`EE2:...Internal.txt:1296`, `:1660`).

### Masterwork — pass an index into a per-instance DB

- `QRY_AMER_UI_Greatforge_CustomOptionConfirm(_Instance,_Char,"Masterwork")`
  `:1270` → `PROC_AMER_UI_Greatforge_Masterwork_InitConfirmPage` `:1280`.
- `QRY_AMER_UI_Greatforge_Masterwork_InitConfirmPage_ValidateMods((INTEGER)_Instance,(STRING)_Slot,(STRING)_SubType,(INTEGER)_Handedness)`
  `:1379` consumes `CountedMods` and finds each mod's next tier up
  (`:1405-1438`), writing
  `DB_AMER_UI_Greatforge_Masterwork_ValidatedMods(_Instance,_Index,_Prefix,_Deltamod,_Value,_UptieredLevel,_BenchedModLevel,_DeltamodRarity,_BenchedRarity,_DecayChance)`
  (10 cols). `"NONE"` in `_Deltamod` = already max tier (`:1400`, rejected
  `:1491`). Needs no UI element — only `_Instance,_Slot,_SubType,_Handedness`
  and a pre-populated `CountedMods`.
- Selection = `DB_AMER_UI_Greatforge_Masterwork_SelectedMod(_Instance,_Index)`
  `:1486`, gated by `QRY_..._PropertyMaxed` `:1491` and
  `QRY_..._PropertyLevelTooHigh` `:1495`.
- `DoCraft` `:1533` reads SelectedMod → ValidatedMods →
  `ItemAddDeltaModifier(_Item, _Deltamod)`, plus `:1542` stamps the
  once-per-item marker (`Boost_Weapon_Masterwork` / `Boost_Armor_Masterwork` /
  `Boost_Shield_Masterwork`, `EE2:AMER_GLO_UI_Greatforge.txt:75-84`).

**The Masterwork cost is read back out of the UI's rendered text**
(`:1251-1265` binds `DB_AMER_UI_ElementText_TextureText_Stored(...)` through
`QRY_AMER_GEN_StringtoInteger`, whose only effect is writing
`DB_AMER_GEN_OUTPUT_Integer` — `EE2:_AMER_GEN_QrysProcs.txt:7886-7898`). The
wheel cost is forced negative so it renders `"?"` (`:1243-1248`, `:577-581`).
A custom UI must compute it via
`QRY_AMER_UI_Greatforge_Masterwork_InitConfirmPage_GetCostInt(_UptieredLevel,_BenchedModLevel,_DeltamodRarity,_BenchedRarity,_DecayChance)`
(`:1336-1372`) — all five args come straight out of `ValidatedMods`. Formula:
`((5 + benchedModLevel×0.5) + (uptierLevel − benchedModLevel)×2.25) × (1 + rarityDiff) × (1 + decayChance×3)`.

### RemoveMods (Cull) — pass an index into `ModsOfItem`

- `PROC_AMER_UI_Greatforge_RemoveMods_InitConfirmPage` `:1648` writes
  `DB_AMER_UI_Greatforge_RemoveMods_ModsOfItem(_Instance,_Index,_DeltaMod)`
  `:1664` from `CountedMods`; selection =
  `DB_AMER_UI_Greatforge_RemoveMods_SelectedMod(_Instance,_Index)` `:1684`.
  Both can be written from Lua directly, skipping `InitConfirmPage`.
- `DoCraft` `:1703` builds a treasure table from slot/rarity
  (`QRY_..._BuildTreasureTable` `:1742-1835`), records
  `DB_AMER_UI_Greatforge_RemoveMods_NewItemRequest(...)` `:1718`, fires
  `PROC_AMER_GEN_GenerateTreasure(...)`, destroys the old item, and the
  **async** return rule `:1725-1737` re-rolls mods on the new item,
  re-applies the kept deltamod, then `ItemToInventory(_Item,_Char,-1,0,1)`.
  Cull is a replace-the-item operation with async completion **inside the
  internal goal** — keep the goal active across the round-trip (Epip's timer
  pattern). Container required.

### Combine — pass a donor ITEMGUID + deltamod

`DB_AMER_UI_Greatforge_Combine_ItemToAdd(_Instance,_ItemToAdd,_Deltamod)`
(`:1968`). `DoCraft` `:2072` rebuilds the deltamod string for the target's
slot via `QRY_AMER_Deltamods_Gen_AddMod_Group_BuildDeltamodStr` `:2078`,
destroys the donor, `ItemAddDeltaModifier`, then
`PROC_AMER_UI_Greatforge_Combine_TryEquipDeltamod` `:2084-2093` (handles
`Ring`→`Ring2`, `:2108`).

Combine's donor validation is embedded in
`PROC_AMER_UI_Greatforge_ItemAlreadyBenched_Override` `:1946-1971` (page-driven)
but the individual checks are normal, individually callable queries:
`Combine_ItemAddedIsTheSame` `:1977`, `ItemAddedHasTooManyMods` `:1985`,
`ItemAddedHasNoMods` `:1997`, `ItemAddedHasSamePrefix` `:2007` (needs
`DB_AMER_UI_Greatforge_Combine_BenchedMods` seeded, populated `:1934-1938`),
`ItemAddedHasExcludedPrefix` `:2015`, `Combine_UnsupportedMod` `:2025-2067`,
plus the `Combine_MaxMods` rarity cap
(`EE2:AMER_GLO_UI_Greatforge.txt:175-181`, checked `:1884-1894`).

## 4. State coupling

| Coupling | Verdict |
|---|---|
| Character in Ascension/meditation scene | **No.** `DB_AMER_UI_Instances(_Map,_Instance)` is populated from level-template objects on every map (`EE2:AMER_GLO_UI.txt:334-344`). Nothing in `DoCraft` or its callees checks position, status, or level. |
| Character in a UI session (`DB_AMER_UI_UsersInUI`) | **Only structurally.** No `DoCraft` rule reads it — but the internal goal is gated on it (see §1). Defeated by `PROC_AMER_GEN_Goal_Activate` / `PROC_AMER_GEN_Goal_Complete`; **the complete side must be conditional on `NOT DB_AMER_UI_UsersInUI(_,_,_)`** or you kill a real Greatforge session in multiplayer. |
| Item physically in the Greatforge socket | **No.** Benching only writes a DB row and kicks two async behaviour-hook fetches, finalized by `PROC_AMER_UI_Greatforge_FinalizeBenchedItem(...9 args)` `:350`. `DoCraft` handles equipped items itself via `PROC_AMER_GEN_UnequipAndRemoveItem` (`EE2:_AMER_GEN_QrysProcs.txt:4214-4239`). |
| `DB_AMER_UI_Greatforge_BenchedItem` | **Required for validation and cost, not execution.** Every `InvalidSelection` rule and the ExtractRunes cost multiplier (`:1118-1130`) read it. Seed the 9-tuple (instance, char, item, levelReal, itemTypeReal, slot, subType, handednessFlag, goldValueReal) and reuse `InvalidSelection` wholesale. Note `EPIP:Lua\EpipEncountersServer.lua:13-33` (`ItemHasMaxSockets`) reads `Osi.DB_AMER_UI_Greatforge_BenchedItem:Get(...)[1][3]` — the first tuple **globally**: bench-coupled and multiplayer-unsafe. |
| `DB_AMER_UI_Greatforge_CraftObject_Reserved` | Required for the `Funds_RequestSuccess`→`DoCraft` hop (`:832`) and as `_Cont` for item-generating options (Reduce, Transmute, RemoveMods). UI-free equivalent: `QRY_AMER_GEN_GetHelperObjectAtPosition(1.0,1.0,1.0,1)` + `PROC_AMER_GEN_UnreserveHelperObject`. |
| Item delivery after craft | **UI-coupled.** `MoveAllItemsTo(_Cont,_Char)` lives in generic completion rule `:2236-2245`, guarded on `DB_AMER_UI_ElementsOfInstance(...)`. With no live instance it never fires — loot strands in the container. Must be replicated (Epip's 200 ms timer drain). |
| Cleanup | `PROC_AMER_UI_Greatforge_Cleanup` / `ClearBench` (`:2345-2389`) wipe `BenchedItem`, `SelectedOption`, `SelectedOption_Cost` and release the craft object on UI exit. Seed those DBs outside a session and **you own the cleanup**; also handle `SavegameLoaded` (`PIP_GLO_QuickReduce.txt:307-309`). |
| Combat | Only the Meditate skill gates it (`EE2:AMER_GLO_UI_Ascension.txt:277-279`). Programmatic execution has no combat gate — QuickForge must enforce its own gating. |

## 5. Costs

All in `EE2:AMER_GLO_UI_Greatforge.txt` INITSECTION — plain Osiris DBs,
readable from Lua at any time, no goal activation needed:

`DB_AMER_UI_Greatforge_Option_Cost((STRING)_Option, (STRING)_MatType, (STRING)_RootTemplateOrGold, (REAL)_MatValue)`

| Option | MatType | Base `_MatValue` | line |
|---|---|---|---|
| Reduce | Gold | 0.15 (× item gold value) | `:47` |
| ExtractRunes | GreatforgeFrags | 0.0 → floored to 1, ×5 per rune | `:49` |
| LevelUp | GreatforgeFrags | 1.0 | `:52` |
| Masterwork | GreatforgeFrags | 10.0 (but see §3) | `:54` |
| Focalize | GreatforgeFrags | 2.5 | `:58` |
| Transmute | GreatforgeFrags | 3.25 | `:60` |
| RemoveMods | GreatforgeFrags | 1.5 | `:61` |
| Combine | GreatforgeFrags | 6.0 | `:62` |
| AddSockets | GreatforgeFrags | 8.0 | `EPIP:Goals\PIP_Greatforge_AddSockets.txt:6` |
| PIP_Engrave | GreatforgeFrags | 0.2 | `EPIP:Goals\PIP_Greatforge_Engrave.txt:6` |

Splinter template:
`AMER_LOOT_GreatforgeFragment_A_a41f2a71-6ff1-4c60-a74a-20c96fb9c487`.

**The formula** — `QRY_AMER_UI_Greatforge_GenerateCost((INTEGER)_Instance,(STRING)_Option,(STRING)_MatType,(REAL)_Level,(STRING)_Rarity,(STRING)_Slot,(STRING)_SubType,(INTEGER)_Handedness,(REAL)_ItemGoldValue,(REAL)_MatValue)`
→ `DB_AMER_UI_Greatforge_OUTPUT_Cost` (`EE2:...Internal.txt:726-790`):

- Gold branch `:733`: `max(itemGoldValue × MatValue, 1.0)`.
- GreatforgeFrags branch `:761`: `ceil(max(MatValue,1.0) × rarityMult)`,
  rarityMult = `DB_AMER_UI_Greatforge_ItemRarityCostMult`
  (`AMER_GLO_UI_Greatforge.txt:12-18`: Common/Uncommon 1, Rare 2, Epic 4,
  Legendary 8, Divine/Unique 16).
- Universal custom-multiplier rule `:779-790` ×
  `QRY_AMER_UI_Greatforge_GenerateCost_GetCustomMult(...)`. Known overrides:
  ExtractRunes = `runeCount × 5.0` (`:1118`, reads BenchedItem), ExtractRunes
  rarity mult forced 1.0 (`:1133`); LevelUp weapon-1H ×4, weapon-2H ×8,
  Shield ×3, Breast ×2 (`:1183-1197`).
- Masterwork forces rarity mult −1.0 → wheel renders `"?"` (`:1243-1248`,
  `:577-581`); real cost via `GetCostInt` (§3).

Reference implementation for a cost-display API:
`EPIP:Goals\PIP_GLO_QuickReduce.txt:71-91` (`QRY_PIP_Greatforge_GetCost(...)`
→ `DB_AMER_GEN_OUTPUT_Integer`) — passes instance `0`, works UI-free given the
goal is active.

Reduce's reward:
`QRY_AMER_UI_Greatforge_Reduce_GetFragmentsAwarded(_Item,_ItemLevel,_ItemRarityInt,_Slot,_SubType,_Handedness)`
(`:922-1033`); loot tables `DB_AMER_UI_Greatforge_ReduceTable(...)`
(`AMER_GLO_UI_Greatforge.txt:66-72`).

Option display strings: TSK keys `"AMER_UI_Greatforge_Title_" .. optionID` and
`"AMER_UI_Greatforge_Desc_" .. optionID` (`EE2:...Internal.txt:455-457`; Epip
registers PIP_Engrave's at `EPIP:Lua\Epip\Greatforge\Engrave\Shared.lua:12,18`).

## Feasibility verdict per option

Legend: **[A]** executable as-is (effect self-contained; only cost/validation
must be added) · **[B]** executable with extra plumbing (container/async/picker
DB seeding) · **[C]** hard-coupled to UI.

Every entry presumes the shared prerequisite: activate
`AMER_GLO_UI_Greatforge_Internal`, seed `DB_AMER_UI_Greatforge_BenchedItem`,
complete the goal afterwards only when `NOT DB_AMER_UI_UsersInUI(_,_,_)`.

| Option | Verdict | Notes |
|---|---|---|
| Reduce | **[B]** — proven | Epip ships it. Helper container + deferred `MoveAllItemsTo`; gold cost; two async behaviour hooks with failure cleanup. |
| ExtractRunes | **[A]** — proven, easiest | `DoCraft` body is one always-active proc call (`:1112-1114`). Cost multiplier bench-coupled (`:1118`) — seed `BenchedItem` and it works verbatim. |
| LevelUp | **[A]** | `DoCraft:1155` → `PROC_AMER_UI_Greatforge_LevelUp` `:1164-1178`, fully self-contained. Validation one line (`:1145-1153`). **Call `DoCraft`, not `LevelUp` directly**, so Epip's `Generation.Level` fix fires. Best first target. |
| Masterwork | **[B]** | Picker data UI-free (`IterateMods` → `ValidateMods`). Effect = `ItemAddDeltaModifier` ×2. Must compute cost via `GetCostInt` (EE2 reads it from rendered texture text). |
| Focalize | **[A]** | `DoCraft:1583-1592`, always-active artifact DBs, no container, no async. Trivial. |
| Transmute | **[B]** | Generates into `_Cont` — helper container + manual `MoveAllItemsTo`. Validation one rule (`:2150`, no Uniques). |
| RemoveMods | **[B]** | Seed `ModsOfItem` + `SelectedMod` from Lua. Effect is async item regeneration inside the internal goal — keep goal active across the round-trip. Container required. The piece Epip started and abandoned. |
| Combine | **[B]**, highest effort | Seed `Combine_ItemToAdd`; re-orchestrate six donor-validation sub-queries after seeding `Combine_BenchedMods`. Needs a donor-item picker UI. |
| AddSockets | **[A]** effect / **[C]** EE2's validity check | Effect is Epip's `DoCraft` listener. Epip's `ItemHasMaxSockets` reads the first global BenchedItem tuple (multiplayer-unsafe) — prefer our own socket-limit check (`Core.GetSocketLimit`). |
| PIP_Engrave | **[C]** as-is / **[A]** reimplemented | `DoCraft` merely posts `NETMSG_ENGRAVE_START`; Epip's client opens its name-entry box. Calling `DoCraft` chains our UI into Epip's prompt; self-contained alternative = collect name ourselves + `item.CustomDisplayName` + charge cost ourselves. |

## Recommended architecture (lowest risk)

Seed `BenchedItem` + `SelectedOption_Cost` + a reserved craft/helper container,
reuse `QRY_AMER_UI_Greatforge_InvalidSelection` and
`QRY_AMER_UI_Greatforge_GenerateCost` verbatim for validation and cost display,
then commit through **`PROC_AMER_UI_Greatforge_OptionRequested`** rather than
`DoCraft` — that keeps EE2's funds check, its insufficient-funds message, its
deduction, and all third-party `DoCraft` listeners (Epip's AddSockets /
Engrave / Empower fix) intact, leaving only container drainage and goal
lifecycle as our responsibility.
