# Slash Observation Recorder

A passive client recorder for the unresolved game-contract questions in +1 Slash Per Click (place `101558013317432`). Version **0.2.0**.

The source lives in this repository. Captured account details and gameplay logs stay in local exports; the recorder does not upload them.

## Launch through your existing client Lua environment

Join the actual published game, wait for it to load, then run:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/umhellolol/slash-observation-recorder/main/recorder.lua"))()
```

This requires the existing runtime to provide HTTP fetching and Lua execution. Runtime compatibility still needs a real client check. No GitHub token is required. The source can also run as a client LocalScript in a developer-controlled Studio test place; an incomplete saved place cannot reproduce missing production server behavior.

The `main` URL follows updates. Use a commit hash instead of `main` to pin the exact source used in an experiment. The capture includes a recorder version, but you should also retain the launch URL/commit with the exported evidence.

## First run: verify capture only

**Do not perform a Blade, trade, drop or lane experiment yet.**

1. Launch the recorder. A panel titled **SLASH / PASSIVE OBSERVER** should appear.
2. Click **Capture diagnostic**. It records client identity, place/build, visible state folders, and available incoming-event subscriptions. Subscribed does not mean an event has already arrived.
3. Leave the client open for at least **12 seconds** so the recorder can produce a heartbeat. Normal game background events may also arrive; none are requested by the recorder.
4. Click **Save file**. If the runtime exposes `writefile`, the panel displays the generated filename in the runtime's workspace. When `readfile` is available too, the recorder verifies the written content by reading it back.
5. If file export is unavailable, choose **Copy JSON**, paste into a plain text file and save with a `.json` extension. Clipboard support is also optional. **Export JSON** provides a selectable text fallback.
6. Supply that file for review. It should contain `started`, `initial-snapshot`, `diagnostic`, and `heartbeat` records, the expected place/server/account identity, and explicit coverage information. Missing paths or errors need investigation before experiments.

The first successful capture proves recorder operation only. Live incoming-event delivery must still be observed, and receiving a result message does not prove inventory acceptance or server semantics.

## What it captures

- Incoming Effects, TradeRemote, SwordDropEvent, CharmShopRequest, CharmShowerVisuals, Admin Blade Event, PetInventoryResult and LuckyBlockOpenResult messages when visible.
- Client-visible stats, sword quantities and attributes, charm quantities, pet inventory, relevant account attributes, SwordDropState and AdminBladeState.
- Initial and event-time snapshots, changed state sampled every two seconds, ten-second heartbeats, local prompt-triggered notifications and character replacement.
- Manual **Before**, **Action** and **After** markers; set the experiment label in the panel.

It sends no gameplay remote calls and does not move the character, collect items, trade, purchase, alter inventory or intercept outgoing calls. Fetching this source from GitHub happens in the launcher. File and clipboard exports happen only when their buttons are pressed.

**Stop** disconnects observations; exports remain available. Press **Close panel** afterward to remove the stopped UI before relaunching. The executed file also returns an observation-only API (`health`, `mark`, `exportJSON`, `stop`) for a future transport adapter. There is no external command channel or desktop connection in this build.

## Limits

The source bindings come from a captured client build. They may differ in the current live game. Earlier events are not replayed and no sync requests are sent. Missing or streamed-out information remains unknown. The recorder does not enumerate every drop in every world or inspect hidden server scripts.

A rolling buffer retains at most 1,000 records and approximately four million encoded bytes. `droppedRecords`, sequence gaps and `truncations` expose losses and serialization limits. Long sessions, event bursts or large inventories can lose evidence; keep capture checks and individual experiments short, and export each run.

Snapshots can precede delayed replication and polling can miss brief transitions. Inventory folders may be absent or truncated. Client events, UI messages and object disappearance are observations, not automatic proof of ownership, successful trades or reward collection. Logs are editable JSON, not signed audit records.

File/clipboard capabilities are checked but not assumed. Never put credentials or a GitHub token into the loadstring. Account and server identity are included in exports; review logs before sharing them. Do not commit captures to this source repository.

## Architecture boundary

This Lua script is the **in-game agent/observer**. A future external desktop controller can supervise many agents, accounts, Roblox clients and server fleets in one integrated application. GitHub hosts source; it is not the controller or a live transport. The current recorder exports files for inspection; authenticated agent/controller transport is a later component.

## Validation status

Syntax checks, a no-gameplay-server-call check, and simulated Lua lifecycle checks cover startup, subscriptions, heartbeat, event recording, quantity snapshots, optional export APIs, and stop behavior. The companion evidence workbench has focused logic and browser checks. **No live Roblox/Potassium compatibility or game behavior has yet been verified.**
