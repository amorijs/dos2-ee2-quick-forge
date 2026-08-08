# QuickForge

Adds Greatforge access to the equipment right-click context menu, for
Divinity: Original Sin 2 (DE) + Epic Encounters 2 + Epip Encounters.

A right-click on any equipment shows a **Greatforge** submenu listing the
applicable Greatforge options. Choosing one *Jumps*: the Greatforge opens with
the item already benched and that option's confirm (or picker) page open. The
Jump commits nothing — costs, confirmations and rules are unchanged; confirm
or back out inside the Greatforge as normal.

See `CONTEXT.md` for the glossary and settled design decisions.

## Layout

- `Mods/QuickForge_<UUID>/` — the mod, laid out as a pak root.
  - `Story/RawFiles/Lua/QuickForge/Core.lua` — pure logic (option registry,
    applicability rules, menu building, jump planning). No game API access;
    runs under plain Lua for tests.
  - `Story/RawFiles/Lua/QuickForge/{Shared,Client,Server}.lua` — Epip feature
    registration, context-menu integration, and the server-side Jump sequence.
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
Load order: EE2 Core → EE2 → Epip → QuickForge.

Requires: Epic Encounters Core, Epip Encounters, Norbyte's Script Extender
(v60+). Keyboard & mouse only — Epip's context-menu system is disabled on
controller.
