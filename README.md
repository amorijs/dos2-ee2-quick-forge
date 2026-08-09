# QuickForge

## Preview

<img width="536" height="420" alt="image" src="https://github.com/user-attachments/assets/25239975-8606-44ae-b020-ec8e94b5f600" />

<img width="407" height="420" alt="image" src="https://github.com/user-attachments/assets/975ed535-bc53-41c2-b0d9-cf4294c735f8" />

<img width="400" height="728" alt="image" src="https://github.com/user-attachments/assets/ca5bc1d7-00d5-4aa0-8b00-0a87f9f4112e" />

<img width="599" height="727" alt="image" src="https://github.com/user-attachments/assets/56c9259a-0012-4c2c-a08e-36276ec5f34c" />

## What it does

Use the Greatforge straight from your inventory.

Right-click any piece of equipment and you'll find a new **Greatforge**
submenu with every option available for that item. Clicking any option opens a confirmation window 
showing the item, what the operation does, and what it will cost you next to what you can afford —
click Confirm and it's done.

Everything works exactly as it does at the real Greatforge — same rules,
same costs, same results. QuickForge just saves you the walk.

**Requires:** Epic Encounters Core, Epip Encounters, and Norbyte's Script
Extender (v60+). Keyboard & mouse only. Load order: EE2 Core → EE2 → Epip →
QuickForge.

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
Load order: EE2 Core → EE2 → Epip → QuickForge.

Requires: Epic Encounters Core, Epip Encounters, Norbyte's Script Extender
(v60+). Keyboard & mouse only — Epip's context-menu system is disabled on
controller.
