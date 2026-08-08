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
- **Jump** — this mod's core action: opening the Greatforge with a chosen item already benched, navigated to a chosen option, without committing to it. The player confirms (or backs out) inside the Greatforge as normal.
- **Instant Operation** — executing a Greatforge option immediately from the context menu with no UI visit. Epip's existing Dismantle and Extract Runes entries behave this way.
- **Applicable Option** — a Greatforge option that is valid for a given item (e.g. Focalize is applicable only to Artifacts). The context menu shows only applicable options.

## Settled decisions (summary)

- Built as an **Epip addon** (requires EE2, Script Extender, Epip Encounters).
- Context menu surfaces: own inventory, equipped items, opened containers. Not trade windows or world items.
- The mod is a **pure shortcut**: normal costs, confirmations, and rules unchanged. No gameplay alteration.
- Personal-first, but structured so publishing later is possible.
- Entries live in a single **"Greatforge" submenu** of the item context menu.
- A Jump lands as deep as possible while uncommitted: the option's confirm page, or its picker page (Masterwork/Cull/Combine).
- The submenu shows the complete option set, including Epip's Drill Sockets and Engrave, and including Dismantle/Extract Runes as Jumps even though Epip's instant entries also exist (Epip's entries are left untouched).
- Server logic is per-character (multiplayer-correct by construction), but only solo play is tested.
- The submenu is hidden entirely during combat; availability otherwise mirrors the Meditate skill's own gating.
- Equipped items are handled automatically (silent unequip only if the engine requires it) — no shift-click friction, since a Jump commits nothing.
- Companions' items show the submenu; a Jump benches the item into the *controlled character's* Greatforge. Fallback if cross-owner benching proves broken: owner-only.
- Submenu entries are names only — no cost preview in v1.
- Zero configuration in v1.
- Keyboard & mouse only (hard constraint: Epip's context-menu system is disabled on controller).
