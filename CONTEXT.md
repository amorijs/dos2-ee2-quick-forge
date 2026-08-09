# Context: QuickForge (working name)

An addon for Divinity: Original Sin 2 (Definitive Edition) + Epic Encounters 2 (EE2) + Epip Encounters. Adds Greatforge access to the equipment right-click context menu.

## Glossary

- **Greatforge** — EE2's equipment-crafting interface, normally reached via the Meditate skill → Ascension nexus. Built from Ameranth's Osiris-driven "physical UI" system, not Flash.
- **Greatforge Option** (aka **path**) — one distinct operation the Greatforge can perform on an item. Base EE2 ships eight; Epip adds two. Internal ID ↔ player-facing name:
  - `Reduce` = **Dismantle** (destroy item → Artificer's Splinters + ingredients)
  - `ExtractRunes` = **Extract Runes** (recover socketed runes, item preserved)
  - `LevelUp` = **Empower** (raise item level toward character level)
  - `Masterwork` = **Masterwork** (once-per-item upgrade of one chosen property)
  - `Focalize` = **Focalize** (Artifact → Artifact Focus rune; Artifacts only)
  - `Transmute` = **Transmute** (reroll into random same-rarity item)
  - `RemoveMods` = **Cull Properties** (keep one chosen property, drop the rest)
  - `Combine` = **Combine** (absorb the single property of a donor item)
  - `AddSockets` = **Drill Sockets** (Epip-added option)
  - `PIP_Engrave` = **Engrave** (Epip-added cosmetic rename)
- **Benched Item** — the item currently placed in the Greatforge to be worked on.
- **Artificer's Splinters** — the Greatforge currency (aka Greatforge Fragments), obtained by Dismantling; most options cost Splinters, Dismantle costs gold.
- **Jump** — opening the Greatforge with a chosen item already benched, navigated to a chosen option, without committing to it. The player confirms (or backs out) inside the Greatforge as normal. Formerly the mod's core action; retained as a fallback ("Open in Greatforge…" entry, and the automatic fallback when a Direct Operation can't run).
- **Direct Operation** — executing a Greatforge option in place through QuickForge's own confirm layer (the Forge Window), with no Ascension visit. Contrast: a *Jump* defers to EE2's UI; an *Instant Operation* skips confirmation entirely.
- **Forge Window** — QuickForge's confirm window for a Direct Operation: item icon with native tooltip, option description, cost alongside the player's current Splinters, Confirm/Cancel.
- **Instant Operation** — executing a Greatforge option immediately from the context menu with no UI visit. Epip's existing Dismantle and Extract Runes entries behave this way.
- **Applicable Option** — a Greatforge option that is valid for a given item (e.g. Focalize is applicable only to Artifacts). The context menu shows only applicable options.
- **Property** — a non-implicit, deltamod-backed bonus on an item. The unit the picker options operate on: Masterwork uptiers one, Cull Properties keeps one and drops the rest, Combine transfers a Donor's single one.
- **Picker** — the selection step a picker option requires before confirming: choosing a Property (Masterwork, Cull Properties) or a Donor (Combine). In QuickForge, pickers live inside the Forge Window as a selectable list.
- **Donor** — the item Combine consumes to transfer its single Property onto the target item.

## Settled decisions (summary)

- Built as an **Epip addon** (requires EE2, Script Extender, Epip Encounters).
- Context menu surfaces: own inventory, equipped items, opened containers. Not trade windows or world items.
- ~~The mod is a pure shortcut: normal costs, confirmations, and rules unchanged.~~ **Superseded (2026-08-08):** QuickForge's own UI is becoming the confirm layer. Replacement principle: **QuickForge never reimplements Greatforge rules** — it may only invoke EE2's own execution path, and may only display costs/validity it reads live from EE2's data (never hardcoded guesses).
- End state: **total replacement** — right-click → submenu → QuickForge UI (costs, pickers, confirm) → operation executes in place; no Ascension visit. Staged: **phase 1** = the seven non-picker options (Empower, Focalize, Extract Runes, Drill Sockets, Transmute, Dismantle, Engrave — Engrave reuses Epip's existing name prompt); **phase 2** = the picker options (Masterwork, Cull Properties, Combine). Until phase 2 ships, picker options remain Jumps. Phase-2 picker UX is deliberately undesigned until phase 1 has play-time.
- Direct Operations commit through **EE2's own request pipeline** (its funds check, payment, and effect dispatch), never through reimplemented effects. One documented exception: Drill Sockets validity uses QuickForge's own socket-limit rule, because EE2/Epip's check is bench-coupled and multiplayer-unsafe (see ADR-0001).
- While **any** player is inside a real Greatforge session, Direct Operations refuse and offer the Jump instead — the concurrent case is structurally unreachable rather than handled.
- On success: a small toast + the window closes. On failure: never silent — an error dialog with the reason, offering the Jump when EE2's UI could resolve it. The Forge Window is a preview; the server re-validates everything at commit time.
- The confirm UI is a **small custom window**: item icon with native tooltip, option description, cost alongside the player's current Splinters, Confirm/Cancel. Not a bare message box; no attempt to mimic EE2's physical scene.
- The Jump survives as an explicit **"Open in Greatforge…" fallback entry** in the submenu (and as the automatic fallback for anything the custom UI can't handle).
- Personal-first, but structured so publishing later is possible.
- Entries live in a single **"Greatforge" submenu** of the item context menu.
- A Jump lands as deep as possible while uncommitted: the option's confirm page, or its picker page (Masterwork/Cull/Combine).
- The submenu shows the complete option set, including Epip's Drill Sockets and Engrave, and including Dismantle/Extract Runes as Jumps even though Epip's instant entries also exist (Epip's entries are left untouched).
- Server logic is per-character (multiplayer-correct by construction), but only solo play is tested.
- The submenu is hidden entirely during combat; availability otherwise mirrors the Meditate skill's own gating. This holds even now that operations execute in place with no meditation — anywhere you could meditate-and-forge you can QuickForge, and nowhere else.
- Equipped items are handled automatically (silent unequip only if the engine requires it) — no shift-click friction, since a Jump commits nothing.
- Companions' items show the submenu; a Jump benches the item into the *controlled character's* Greatforge. Fallback if cross-owner benching proves broken: owner-only.
- Submenu entries are names only — no cost preview in v1.
- Zero configuration in v1.
- Keyboard & mouse only (hard constraint: Epip's context-menu system is disabled on controller).

## Phase 2 decisions (in design, 2026-08-08)

- Phase 2 is **strictly** the three picker options (Masterwork, Cull Properties, Combine) becoming Direct Operations. All other deferred items stay deferred.
- Built and play-tested **incrementally**, in order Masterwork → Cull Properties → Combine; each option flips from Jump to Direct Operation independently as it lands.
- Pickers live **inside the Forge Window** — one window with a selectable list; choosing a row updates the displayed cost, Confirm commits. No second window, no context-menu picker.
- Property pickers (Masterwork, Cull Properties) show ineligible rows **greyed with the reason**; the Combine donor picker shows **only valid Donors**.
- Masterwork picker rows show the Property's name, current → uptiered value, and that Property's own per-row cost (read live from EE2's data, per the never-reimplement guardrail).
- Combine Donors are drawn from the **whole party's inventories, excluding equipped items**.
- **No pre-selection**: the picker opens with nothing chosen and Confirm disabled until the player picks a row; no double-click-to-commit. Eligible-but-unaffordable rows stay selectable with Confirm greyed (visual gate only — the server re-validates at commit, as in phase 1).
- **Empty pickers still open the window**: all-ineligible property lists show every row greyed with its reason; a donorless Combine shows an explicit "no valid donors" state. No refusal dialog for emptiness.
- The Combine donor selector is a **list plus drop slot**: scrollable rows (item icon, name, the transferred Property) beside an empty donor slot next to the target item; dragging an item onto the slot also selects it. The server-computed valid-donor set is authoritative for both paths — an invalid drop is refused with its reason.
- Cull Properties adds **no warning beyond EE2's own description** of the rebuild; the success toast fires at commit acceptance (matching the other async options), not at item delivery.
