# Slash in-game evidence suite coverage

## Version 1.2 focused screen

The user-facing UI now contains only the guided lane-persistence experiment. The 22-case catalog below remains exported evidence metadata and an engineering coverage map; it is not a request to repeat all those cases. Manual review/action controls from versions 1.0–1.1 are no longer shown. Existing engine APIs remain for regression checks and future development.

The guide starts a T01 trial, disables Auto Win/AutoRebirth, requires a living character outside training and two unlocked worlds, reads fresh PersonalWallsInit data, and verifies all stages in the current world's client configuration are cleared. It records a new baseline, travels to another unlocked world and back, and requires another fresh lane response. A scoped PASS requires the same JobId, unchanged invalidation generation, confirmed destination/return, automation still off, and all prepared stages still cleared. FAIL means fresh returned data lost prepared stages. Claims, local rebirths, respawns, new personal wall breaks/clears, failed travel and missing responses cannot silently become PASS. Freshness means a response observed in a request window; the protocol has no request correlation ID.

Repeated baseline markers now replace the delta baseline. Historical unfinished trials remain INCOMPLETE. Command status/reason, observed evidence, the guided mechanic result and saving status are separate fields. Travel, respawn, local rebirth and reward claims invalidate cached wall freshness. Complete JSON includes `guidedLane`, detailed departure/return snapshots and the raw event stream.

The 25 October capture review established remote shop reads, distance-gated purchases, three quantity-confirmed sword pickups, travel, AFK/settings, pets, Lucky Blocks and local rebirth activity. It is documented locally in Slash Test Capture Review.md. The user need not reproduce those observations. Future shop policy targets only `PrismaticCosmos` (Rainbow, configured at 3,000 Crystals), highest regular-gameplay priority across instances including Main, separate from Admin Abuse. No shop automation is implemented by this guided test.

Version 1.2 validation uses the actual assembled Lua with a simulated Roblox API: core engine with/without file storage, baseline/status regressions, drag/resize/restore, guided success/reset, claim/respawn interruptions, fresh-response timeouts before and after travel, partial travel failure, save failure and actual UI button dispatch. This does not claim an actual Roblox renderer or live lane result.

## Retained contract coverage

This suite is an evidence collector for one local account. The intended main test account is **mxssyo**; the suite resolves its numeric UserId at runtime and does not require a second agent. A willing player may be used later for a manual trade, but that player does not need to run the suite.

The suite is not the desktop platform and does not recover hidden server code. Every result is an operator review (`OBSERVED`, `PASS`, `FAIL`, `BLOCKED`, or `NOT_RUN`). A notification, request, UI change, or disappearing object is not authoritative success by itself. Live observations, source replay, and event-contract replay stay separate.

## Case IDs and scope

The suite cases are `T01–T22`. Their `requirements` arrays map back to the master specification's `LT01–LT20`, `AC01–AC29`, and `U01–U08` where applicable. The `LTxx` labels in the master specification are not suite IDs; for example, suite `T10` maps to master `LT12` (Charm Shop), while master `LT10` is the trade test mapped by suite `T18`.

The **Now** cases are the useful one-account run on mxssyo, preferably in World 9:

- `T01–T06` map to master `LT01–LT06`: lane preparation/claim scope, death and respawn, observer restart, leave/rejoin, and world travel. `T01` preserves the user-confirmed same-session rule that a cleared lane survives world travel until its Wins are claimed; it does not generalize that rule to reconnects.
- `T07` maps to master `LT07`: ordinary sword-drop visibility, world/position/identity/expiry, pickup, and quantity reconciliation. A vanished object without an inventory delta is unresolved; a streamed-out world is `UNKNOWN`, not zero drops.
- `T10` maps to master `LT12`: remote Charm Shop request while away from the shop, followed only by an explicitly bounded purchase.
- `T11–T15` map to master `LT03/LT12–LT16` and cover AFK/speed/automation guards, pets, Lucky Blocks, rebirth, and preserve-mode navigation.
- `T21` and `T22` cover normal slash/wall cadence and fist upgrades, plus free/offline/group rewards from the master feature list. They support normal UI observations, an optional bounded recorded punch sample, and the discovered free reward requests.

State-changing actions require a trial, scope/budget checks, and UI confirmation. Available actions are `shop_get`, `wall_sync`, `drop_sync`, `travel`, `disable_auto`, `afk_exit`, `equip_best`, `shop_buy`, `lucky_open`, `merge`, `cleanup`, `rebirth`, `speed`, `trade_cancel`, `punch_probe`, `offline_claim`, and `group_claim`. There is no raw remote/code input, automatic trade acceptance, automatic reset, or default spending. The explicit Preserve lanes toggle is a local tool guard and can send disable requests for game automation; it cannot prevent manual pad touches outside the tool.

## Event-contract replay (implemented preparation)

`T08`, `T09`, `T16`, `T17`, and `T20` are isolated event-contract checks. They cover the behaviors needed to prepare the next Admin Abuse event: target and timing fields; `Spawn`/`Sync`/`Remove` lifecycle; multiworld identity; server-key isolation; quantity deltas including duplicate swords; Blade availability/owned transitions; streaming unknowns; wall-init/reset records; and targeted Charm Shower scope. They never emit live remotes.

This replay does not simulate world unlock semantics, shop semantics, fleet scheduling, Main/lease arbitration, launcher behavior, or the architecture acceptance rows. Those are mappings to future platform software tests, not claims that the Lua suite implements a platform simulator.

The prior **“all 500 copies have already been claimed”** response is a post-event shrine observation, not a universal allocation rule. The suite never edits counters, grants a Blade, bypasses the shrine, or treats a client prompt as ownership.

## Later and optional validation

`T18` and `T19` map to master `LT10/LT11` and are optional manual trade tests with a willing player: local offer state, cancellation, duplicate quantities, and interrupted/ambiguous commit. The counterpart need not run the suite. Capturing the local protocol and local inventory change is useful on its own. Full bilateral confirmation needs additional evidence, but that is not a prerequisite for gathering this account's protocol evidence. A closed window alone does not establish a local inventory outcome.

Live Admin Abuse observation is optional later validation (`T08/T09/T20`), not a prerequisite for preparing or building the core platform. A future event can validate start/end signals, live timing, targeted delivery, concurrent multiworld visibility, expiry, pickup entitlement, Blade eligibility/cadence, and ownership persistence. Until then those facts remain explicitly unresolved while the event contract and conservative handling are ready.

## Evidence already available

The supplied captures show that the recorder can preserve a startup baseline and live event stream. The later capture retained 2,484 records with zero dropped/truncated records and reconciled:

- Lucky Block opening with pet IDs and a Wins change (`53 → 23` in that session).
- Azure Zephyr purchase with quantity `0 → 1` and Crystals `100 → 50`.
- Reward claims accompanied by wall initialization and an empty cleared-stage list.
- An Admin Blade attempt rejected with “All 500 copies have already been claimed.”
- Off-world sword/drop notifications and replicated state fields.

These are session capture values and useful fixtures, not universal costs or proof of server acceptance outside the observed scope.

## Requirement boundaries

The catalog references all master live tests `LT01–LT20`, architecture acceptance rows `AC01–AC29`, and open items `U01–U08`. Architecture rows (`AC01–AC10`, scheduler/lease/recovery rows, and multi-server portions of `AC18–AC25`) remain platform software tests. The Lua suite can provide Slash game evidence; it cannot establish the production launch adapter, authentication, hidden server handlers, or durable controller behavior.

Every enabled capability still needs a binding, preconditions, observed outcome, and recovery rule. Anything `UNKNOWN` or event-dependent remains visibly `BLOCKED` for that capability; this does not block building the core platform around the replay contract.
