# QuickForge's own UI replaces the Greatforge confirm layer

Status: accepted (2026-08-08)

QuickForge began as a pure shortcut: a Jump benches an item and opens EE2's
physical Greatforge UI, which remained the authority on validation, costs, and
confirmation. Visiting that UI just to confirm turned out to be the residual
friction the mod existed to remove, so QuickForge's own confirm window (the
Forge Window) becomes the final confirm layer and options execute in place
(Direct Operations), with no Ascension visit.

The revoked "pure shortcut" principle is replaced by a narrower guardrail:
**QuickForge never reimplements Greatforge rules** — it may only invoke EE2's
own execution path, and may only display costs/validity it reads live from
EE2's data. If a number can't be read from EE2 at runtime, we don't show a
guess. This keeps drift between our UI and EE2's rules structurally
impossible rather than merely tested-for.

Consequences: QuickForge owns correctness at commit time; the Jump is demoted
to a fallback entry ("Open in Greatforge…", and the automatic fallback when a
Direct Operation can't run); and Meditate-mirroring availability gating is now
enforced by QuickForge itself, because the programmatic execution path has no
combat/availability gate of its own (see
`docs/research/greatforge-programmatic-commit.md`).

Considered alternatives: keeping EE2's UI as the confirm layer (the status
quo — rejected: it is the annoyance being solved), and reimplementing option
effects the way Epip's QuickReduce does (rejected: cost/effect drift risk, and
third-party `DoCraft` listeners would silently not fire).

## Amendment (2026-08-08): the commit route

Direct Operations commit by seeding EE2's own instance DBs (`BenchedItem`,
`SelectedOption_Cost`, `CraftObject_Reserved`) and calling
`PROC_AMER_UI_Greatforge_OptionRequested` — not by calling the execute proc
(`DoCraft`) directly, and not by reimplementing effects. This keeps EE2's
funds check, insufficient-funds message, payment deduction, effect dispatch,
and all third-party `DoCraft` listeners intact; QuickForge owns only the
internal-goal lifecycle, loot-container drainage, and DB cleanup. Validation
reuses `QRY_AMER_UI_Greatforge_InvalidSelection`; costs reuse
`QRY_AMER_UI_Greatforge_GenerateCost` (Masterwork's via EE2's own
`GetCostInt` query, since EE2's runtime path reads that number back out of
rendered UI text). Details: `docs/research/greatforge-programmatic-commit.md`.

**One documented exception to the never-reimplement guardrail:** Drill
Sockets validity uses QuickForge's own socket-limit rule (`Core.lua`) instead
of EE2/Epip's `ItemHasMaxSockets`, because that check reads the first row of
the bench DB *globally* — bench-coupled and multiplayer-unsafe. The guardrail
exists to stop our UI lying at commit time; here EE2's own implementation is
the unsafe one.

As a structural safety measure, Direct Operations refuse (offering the Jump)
while any player is inside a real Greatforge session, so the
shared-internal-goal concurrent case cannot arise.
