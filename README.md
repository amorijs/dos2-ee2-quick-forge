# QuickForge

## Preview

<img width="1771" height="774" alt="combined-image (1)" src="https://github.com/user-attachments/assets/4f3a888e-e459-44ae-a937-be00b41809f9" />


<img width="2123" height="1471" alt="combined-image" src="https://github.com/user-attachments/assets/481b5785-4f2e-41a5-a075-6402f28e663d" />


## What it does


Use the Greatforge straight from your inventory.

Right-click any piece of equipment and you'll find a new **Greatforge**
submenu with every option available for that item. Clicking any option opens a confirmation window 
showing the item, what the operation does, and what it will cost you next to what you can afford —
click Confirm and it's done.

Everything works exactly as it does at the real Greatforge — same rules,
same costs, same results. QuickForge just saves you the walk.

## Installation

**You'll need these first** (QuickForge is an add-on for them, not a
standalone mod):

- [Norbyte's Script Extender](https://github.com/Norbyte/ositools) (v60 or newer)
- [Epic Encounters 2](https://docs.google.com/document/d/1du5jE2dyDE4B4-Za0wolfe50ReeKXqkqdgG5FvAwKTo/edit?tab=t.0) — both **EE2 Core** and **EE2**
- [Epip Encounters](https://github.com/PinewoodPip/EpipEncounters)

**Then:**

1. Download `QuickForge.pak` from the
   [latest release](https://github.com/amorijs/dos2-ee2-quick-forge/releases/latest).
2. Drop it into your mods folder:
   `Documents\Larian Studios\Divinity Original Sin 2 Definitive Edition\Mods`
3. Launch the game and open the **Mods** menu from the main menu.
4. Enable QuickForge and make sure it sits **last** in the load order:

   > EE2 Core → EE2 → Epip → QuickForge

That's it — start or load a save and right-click a piece of gear.

**Note:** keyboard & mouse only. Epip's right-click menu doesn't run on
controller, so QuickForge can't either.

---

*The sections below are for developers. See `CONTEXT.md` for the glossary
and design decisions.*

## Layout

- `Mods/QuickForge_<UUID>/` — the mod, laid out as a pak root.
  - `Story/RawFiles/Lua/QuickForge/Core.lua` — pure logic (option registry,
    applicability rules, commit routing, menu building, gating plans). No
    game API access; runs under plain Lua for tests.
  - `Story/RawFiles/Lua/QuickForge/{Shared,Client,Server}.lua` — Epip feature
    registration, context-menu integration, and the server-side Jump sequence.
  - `Story/RawFiles/Lua/QuickForge/DirectOps.lua` — server-side Direct
    Operations: preview and commit through EE2's request pipeline.
  - `Story/RawFiles/Lua/QuickForge/ForgeWindow.lua` — the client confirm
    window (Epip Generic UI).
- `docs/` — ADRs and research notes.
- `tests/` — test suite for the pure core.
- `references/` (untracked) — unpacked EE2 + Epip sources used for research.

## Development

Run the tests (requires a Lua 5.x interpreter on PATH):

```
lua tests/run.lua
```

To play-test, build and deploy the pak (requires
[LSLib](https://github.com/Norbyte/lslib)'s divine.exe; pass `-DivinePath` or
set `LSLIB_PATH` if it isn't in a common location):

```
tools\pack.ps1
```

This writes `QuickForge.pak` at the repo root and copies it into the game's
`Documents\Larian Studios\...\Mods` folder (skip the copy with `-NoDeploy`).
Prerequisites and load order are in [Installation](#installation) above.
