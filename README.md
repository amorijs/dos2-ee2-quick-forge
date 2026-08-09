# QuickForge

## Preview

<img width="1771" height="774" alt="combined-image (1)" src="https://github.com/user-attachments/assets/4f3a888e-e459-44ae-a937-be00b41809f9" />


<img width="2123" height="1471" alt="combined-image" src="https://github.com/user-attachments/assets/481b5785-4f2e-41a5-a075-6402f28e663d" />


## What it does


Use the Greatforge straight from your inventory.

Right-click any piece of equipment and you'll find a new Greatforge submenu
listing every option available for that item. Pick one and a confirmation
window opens, showing the item, what the operation does, and what it costs
next to what you can afford. Click Confirm and it's done.

Same rules, same costs, same results as the real Greatforge. QuickForge just
saves you the walk.

## Installation

QuickForge is an add-on, not a standalone mod, so you'll need these first:

- [Norbyte's Script Extender](https://github.com/Norbyte/ositools) (v60 or newer)
- [Epic Encounters 2](https://docs.google.com/document/d/1du5jE2dyDE4B4-Za0wolfe50ReeKXqkqdgG5FvAwKTo/edit?tab=t.0), both EE2 Core and EE2
- [Epip Encounters](https://github.com/PinewoodPip/EpipEncounters)

Then:

1. Download `QuickForge.pak` from the
   [latest release](https://github.com/amorijs/dos2-ee2-quick-forge/releases/latest).
2. Drop it into your mods folder:
   `Documents\Larian Studios\Divinity Original Sin 2 Definitive Edition\Mods`
3. Launch the game and open the Mods menu from the main menu.
4. Enable QuickForge and make sure it sits last in the load order:

   > EE2 Core → EE2 → Epip → QuickForge

That's it. Start or load a save and right-click a piece of gear.

One catch: keyboard and mouse only. Epip's right-click menu doesn't run on
controller, so QuickForge can't either.

---

*The sections below are for developers. See `CONTEXT.md` for the glossary
and design decisions.*

## Layout

- `Mods/QuickForge_<UUID>/` is the mod, laid out as a pak root.
  - `Story/RawFiles/Lua/QuickForge/Core.lua`: pure logic (option registry,
    applicability rules, commit routing, menu building, gating plans). No
    game API access; runs under plain Lua for tests.
  - `Story/RawFiles/Lua/QuickForge/{Shared,Client,Server}.lua`: Epip feature
    registration, context-menu integration, and the server-side Jump sequence.
  - `Story/RawFiles/Lua/QuickForge/DirectOps.lua`: server-side Direct
    Operations, previewing and committing through EE2's request pipeline.
  - `Story/RawFiles/Lua/QuickForge/ForgeWindow.lua`: the client confirm
    window (Epip Generic UI).
- `docs/` holds ADRs and research notes.
- `tests/` holds the test suite for the pure core.
- `references/` (untracked) holds unpacked EE2 + Epip sources used for research.

## Development

Run the tests (requires a Lua 5.x interpreter on PATH):

```
lua tests/run.lua
```

To play-test, build and deploy the pak. This needs
[LSLib](https://github.com/Norbyte/lslib)'s divine.exe; pass `-DivinePath` or
set `LSLIB_PATH` if it isn't in a common location.

```
tools\pack.ps1
```

This writes `QuickForge.pak` at the repo root and copies it into the game's
`Documents\Larian Studios\...\Mods` folder (skip the copy with `-NoDeploy`).
Prerequisites and load order are in [Installation](#installation) above.
