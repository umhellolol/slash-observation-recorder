# Friend Boost Observer 2.0.0

Investigates what the client sends and receives when a friend joins or leaves, alongside observed Power gains. This replaces the old three-phase local-value editor. It does not edit any game values, send or replay gameplay requests, move the character, or grant a boost. The main Slash application and the general modifier recorder are unchanged.

## Run

Close the older probe/modifier recorder with **×** first. Join the game and run:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/umhellolol/slash-observation-recorder/main/friend-boost-probe.lua"))()
```

For a reproducible capture use the commit-pinned URL supplied with the release. The `main` URL follows updates.

1. Use normal training with observable Power gains and keep equipment, world and training mode unchanged. Plain Train Power avoids rebirth resets obscuring the comparison; the observer itself does not change AutoRebirth.
2. Press **Start**. Record about 10 seconds before the friend joins, at least 10 seconds with them present, and another 10 seconds after they leave. Keep the same activity running throughout. These are recording windows, not automatic phases or timed edits.
3. Press **Stop + save**. The panel reports the outgoing capability and observed call count. `installed` is a hook-installation result, not proof that calls were seen. Zero calls with `unsupported_executor` means coverage was unavailable.
4. Use the exported `Slash-Friend-Boost-Observer-<timestamp>-run<N>.json`. File contents are read back and compared when `readfile` is available. Otherwise the panel explicitly reports an unverified write, clipboard export, or **Show JSON** fallback. Files are in the executor's workspace, not automatically in Downloads.

Friend joins/leaves continue the recording. **Show JSON** is available after Stop. Hide/show leaves capture running. Closing an active panel stops and exports first. Reopening reuses a dormant pass-through observer instead of stacking another hook. It does not replace other tools' hooks on Stop; another tool replacing/bypassing the hook can silently reduce coverage.

## Evidence collected

- One timestamped, sequenced timeline of outgoing requests, incoming RemoteEvents, friend joins/leaves, boost changes, character replacement, stat changes and context changes.
- Initial/final raw Power, Wins, Rebirths and Crystals with stat paths, missing counters and binary64 precision warnings. Stat Changed signals capture changes between polls; replacement/context polling runs every 250ms.
- Context includes observed world, training pad, AutoRebirth, sword, aura, equipped pets/charms, visible multipliers and roster. A joining player is not automatically classified as a friend.
- Descriptive gain segments split on observed roster/boost/loadout/training/character changes. Positive gains, negative changes/reset counts and rates are separate. Deltas crossing a changed context are excluded from segment totals and counted as ambiguous; whole-run totals retain them. Rates do not establish causation.
- Per-route class, payload policy, subscription success/error and late-discovered remotes. Prioritizes PunchPowerFeedback and Effects; subscriptions are distinct from message delivery.

Only exact known gameplay routes directly under `ReplicatedStorage.PunchEscapeRemotes` retain bounded argument details: PunchRequest, PunchPowerFeedback, Effects, SlashSoundRequest, AFKExitRequest, AutoWinRequest, SettingsPreferenceRequest, RebirthRequest and MovementSpeedRequest. Vector3 components and argument counts (including nil positions) are retained. Other visible ReplicatedStorage routes retain timing/name/class/method/count metadata only, including chat/trade/admin routes. Their payloads are not retained. Common credential keys within retained tables are redacted; review identity and game text before sharing. Captures are not uploaded automatically.

Outgoing observation uses feature-detected `hookmetamethod` and `getnamecallmethod`, based on [Potassium's documented hook interface](https://docs.potassium.pro/api-reference/Metatable%20Library/hookmetamethod). Installation can be `installed`, `installed_reused`, `unsupported_executor` or `install_error`. Serialization is queued outside the hook; observation errors do not intentionally suppress, repeat or alter the original request/returns/errors. No diagnostic calls are sent to test the hook.

## Limits and interpretation

This is client evidence, not access to private server code, variables, friendship checks or award calculations. It cannot promise to discover a spoof. Incoming callbacks and locally visible stats can be manipulated; their correlation is not authenticated proof of server acceptance or persistence.

The namecall hook cannot guarantee all outgoing traffic: direct function calls, replaced hooks, other runtimes, calls outside the recording and executor incompatibilities can bypass it. InvokeServer return values and incoming RemoteFunction callbacks are not intercepted. Missing subscriptions/calls do not establish that no event happened.

Retention is bounded to 12,000 events/four million encoded event bytes, a 512-entry pending queue, 200 routes, 256 comparison segments, and 200 items scanned per context inventory. Changed-stat/setting listeners cap at 128 bindings per run; polling continues if that limit is reached. Payloads cap at 24 positional arguments, depth four, 128 visited nodes, 32 table fields and 160-character strings. Drops, limits and truncations are reported; initial/final snapshots are retained separately. Polling may miss brief context transitions, resets and batched updates can obscure gains, and large counters have rounding limits.

## Verification

Actual production Lua and GUI callbacks pass isolated tests for Start/Stop, join/leave continuation, gain signals/segments, late subscriptions, unsupported capture, pass-through multiple returns/original errors, observation-error isolation, Stop queue draining, restart fencing, reload without hook stacking, credential redaction, metadata-only payload exclusion, overflow reporting, verified export and failed file/clipboard fallback. Source checks exclude local value writes and gameplay remote calls. These fixtures remain outside the shipped application.

**Live Roblox/Potassium capture and real reward behavior remain unverified:** the target PC is not connected to this session. Installation status and subsequent live captures must be assessed as evidence, not assumed success. No arbitrary friend boost has been established.
