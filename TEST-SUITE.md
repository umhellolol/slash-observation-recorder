# Slash In-Game Test Suite

Version **1.0.0** · primary testing account: **mxssyo**.

This expands the working Lua recorder into one in-game information-gathering suite. It is **not the external platform**. Only your account needs it. A trade counterpart can use the normal game UI.

## Launch

Stop and close the old **SLASH / PASSIVE OBSERVER** recorder. Join Slash on **mxssyo**, wait for the game to load, then run in Potassium:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/umhellolol/slash-observation-recorder/main/test-suite.lua"))()
```

The main URL follows source updates. Retain the exact commit URL supplied in chat when reproducibility matters. The suite requires your existing Lua/HTTP execution environment; it does not install Potassium or manage logins.

## First useful session

The panel opens on **T10: Charm Shop remote read**. No further idle recorder check is required.

1. Keep the game's shop window closed. Stay where you are, away from the shop if possible.
2. Use an experiment label such as `mxssyo-shop-world9`. Click **START TRIAL**; this captures the baseline automatically.
3. Click **Read Charm Shop here**, or **SURVEY**. Survey reads available client configuration/geometry and attempts observational shop, wall and Charm Shower synchronization requests. No purchase is included.
4. Wait a few seconds and choose **AFTER**. The log includes position, offers/window, responses, inventory and game-window visibility. Add a note if needed. You can mark it **OBSERVED**; the actual evidence will be reviewed.
5. Click **SAVE**. The message displays a `slash-suite-...-complete.json` filename in Potassium's workspace.

Continue through useful cases in the same recording. Start a new trial for each separate experiment. Saving reconstructs history from readable segments and memory into one complete export. The in-game panel scrolls. **MINIMIZE** collapses it so you can play; **OPEN** restores it, and recording continues throughout.

## Suggested run order

| Order | Cases | Action |
| --- | --- | --- |
| 1 | T10 | Read shop offers remotely. A bounded purchase is optional and separate. |
| 2 | T06, T01 | Travel through unlocked worlds; clear a lane without claiming and verify persistence on return. |
| 3 | T07 | Observe an ordinary sword. The live view shows its world state and latest impact coordinates. Travel/walk to an eligible drop and collect through the normal prompt; capture After. |
| 4 | T21, T11, T22 | Record normal punches/fist upgrades, training, speed/automation settings and eligible free rewards. The optional punch sample is bounded and requires visible active-wall geometry in normal range. |
| 5 | T12, T13 | Test pet equipment and an affordable Lucky Block batch. Merge/delete only explicitly reviewed disposable pets. Normal game UI actions are also observed. |
| 6 | T08, T09, T16, T17, T20 | Click **REPLAY (ISOLATED)**. Nine local event-contract checks run without emitting a live Admin event. |
| 7 | T18, T19 — optional | Trade one agreed disposable item with a willing player through the normal UI. The other player does not need the suite. Capture the local protocol and inventory change; pre-confirmation cancellation can be tested separately. |
| 8 | T02–T05, T14, T15 — chosen cases | Claims, respawn, observer restart, rejoining, rebirth and pad navigation. Use state you are willing to reset. Save before leaving; after relaunch start a new trial using the same experiment label and retain both exports. |

No reset, merge, deletion or purchase is mandatory merely to continue to another case. An unavailable or unsuitable case can be recorded **BLOCKED** with a reason.

## What is recorded

- Actual account, UserId, server, build, world, position, policies, stats and inventory.
- Wall/travel, drop, shop, pet, Lucky Block/cinematic, Blade and trade messages.
- Local drop objects and prompt settings, ordinary sword impact coordinates, and Charm Shower ID/target/timing records when supplied.
- Tool-originated outgoing requests with arguments, world and position. Other scripts' outgoing calls are not intercepted.
- Changed state every two seconds; known other-player cosmetic effects are aggregated with examples and counts.
- Test labels, notes, markers, before/after deltas, source configuration/geometry observations and isolated replay results.

Missing or streamed-out objects remain unknown. An enabled prompt, message or object disappearing is not by itself proof of an inventory reward. A tool request being issued is not marked as successful automatically.

## Controls

**START TRIAL** captures a baseline. **BASELINE / ACTION / AFTER / NOTE** record that moment and your notes. AFTER computes observed numeric/quantity differences and pet-ID additions/removals; mixed activity can make causation ambiguous.

**OBSERVED / PASS / FAIL / BLOCKED / NOT_RUN** are your review labels. PASS requires an After marker and remains a review of that case, not universal certification. Synthetic cases retain their separate scope.

**Preserve cleared lanes** blocks suite rebirth requests while on. Explicitly enabling it sends disable requests for Auto Win and AutoRebirth; check the captured flags before preparation. It cannot block a Win pad you physically touch or an action another script performs.

**STOP** stops observations and flushes available segments; exports still work. **SAVE** creates the complete export. **COPY** attempts clipboard export and supplies selectable JSON text as fallback. **CLOSE** attempts Save and then stops/closes; explicitly Save first, especially if the file API reports an error.

## Action boundaries

Tool mutations require an active matching test and confirmation. Shop/Lucky commands check observed configuration, currency and a per-action budget. These are client checks, not a new server-side spending guarantee. Requests use only the mapped Crystals/Wins/free-reward forms; Robux, paid reward doubling, paid Win pads, Auras and administration controls are excluded.

Explicit pet merge/delete commands reject missing, duplicate, equipped or favorited IDs. Merge identity follows the captured name/tier/world/rarity/limited/strength/star fields. Platform inventory reservations are not implemented here. Rebirth additionally needs preservation off and typing **RESET**.

Travel uses Prepare, streaming and Commit, then waits for the destination observation. There is no position warp or blind retry. An open trade holds other tool movement/inventory/reset commands. Cancellation is held when observed state suggests the final confirmation is locked.

Use the normal UI for physical pickups, fist upgrades and trading. Their incoming responses and outcomes remain recorded; use markers to identify your intent. Manual actions outside this suite are outside its guards.

## Admin Abuse preparation now

The client source already defines the interfaces. Current synchronization responses and state can be inspected without an event. Ordinary sword pickups validate live physical interaction and inventory observation. Charm-specific IDs, targets and timing remain in the source-backed contract.

Replay exercises the same pure helpers used for live Charm Shower interpretation and Blade availability projections: targeting, timing boundaries, additive Spawn/Sync, Remove, multiworld/server identity, quantity deltas, unknown expiry, fresh wall initialization and Blade ownership/exhaustion states. Fixtures never alter the game's inventory or event state. These are software-contract checks, not manufactured server evidence.

A post-event depleted shrine says nothing universal about the next event. No Blade grant, counter edit, administrative remote or bypass is provided. Later event observations can validate remaining assumptions without blocking preparation against the current contract.

## Export completeness

The suite writes `slash-suite-<session>-part-N.json` approximately every ten seconds when file writing is available. **SAVE** creates `slash-suite-<session>-complete.json`; send that main file for review. Retain numbered parts until the complete file has been checked.

Memory is bounded to 10,000 records / four million encoded bytes. Readable saved parts are merged back into a complete export. Unsaved losses, memory eviction, truncations and unreadable parts are explicit. Without read access, retain the numbered parts alongside the summary; without writing, keep trials short and Copy frequently. Export before rejoining or restarting. Keep separate before/after session exports under the same experiment label.

All capture data stays in local exports. Nothing is uploaded to GitHub or another service. GitHub hosts the source only.

## Checks and remaining runtime validation

Syntax and simulated client checks cover startup without gameplay requests, all 22 cases, read probes, request logging, budgets, repeat-purchase blocking, protected pets, trade holds, preservation, trial scoping, travel, bounded punches, replay without live calls, ambient aggregation, deltas, segment reconstruction, fallback export, stopping and panel construction/minimize.

This is not an actual Roblox renderer or a live run of suite 1.0.0. The underlying recorder has run successfully in your live Potassium setup; the expanded UI and actions still need this planned run. See **COVERAGE.md** for requirement mappings and limits.
