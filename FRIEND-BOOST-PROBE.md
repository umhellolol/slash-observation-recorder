# Friend boost probe

Sole purpose: investigate whether an existing local FriendPowerPercent edit changes observed gameplay gains, while collecting nearby incoming events and confounds. It does not grant a server-side boost or claim that this route can spoof one. Generic recorder v3 and Slash are unchanged.

Close the old recorder panel with × first. Launch:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/umhellolol/slash-observation-recorder/main/friend-boost-probe.lua"))()
```

Keep one normal training/action running consistently. Enter the requested boost (default 100000) and seconds per phase (default 10), then press **Start test**. It automatically measures normal → locally edited → restored, then stops and exports after about 30 seconds. **Stop test** cancels early, attempts restoration and exports an incomplete comparison. Hide/show leaves the test running. **Show JSON** provides selectable export text if local file/clipboard APIs fail.

During this controlled comparison, keep friends, equipment, world and activity unchanged. A player joining/leaving, a character change, observed world/loadout/training-setting change, reversion or failed restoration invalidates the comparison. Friend join/leave events are still captured for diagnosis; they are not asserted to prove friendship or server authority.

The report includes raw NumericStats values, positive gains, negative changes/reset counts, actual phase durations/sample counts, gain rates, boost write/restoration, incoming client-visible RemoteEvent payloads (up to 100 subscribed routes), truncations and missing-event counts. Context is observed through known fields, not all hidden game state. No outgoing requests, remote hooks/replay, guessed server calls or private server scripts are used.

Interpretation is deliberately limited:

- INCONCLUSIVE: no usable repeated gains, unfinished phases, invalidation, unstable controls or insufficient numeric precision.
- NO_OBSERVABLE_EFFECT_IN_THIS_RUN: at least one measured non-resetting, non-precision-limited counter had positive rates in all phases; normal/restored rates agreed within 10%, and the edited rate was within 10% of their mean. This threshold is a screening heuristic, not statistical proof or proof that every spoof route is impossible.
- OBSERVED_CHANGE_UNVERIFIED: an eligible edited rate differed by more than 10%, upward or downward. Repeat with matched actions; this is not a confirmed server-side effect.

Power resets are recorded separately from positive gains. Metrics with resets or exposed values beyond exact binary64 integer precision are excluded from the automatic verdict; raw observations remain in the export. Gameplay action counts and private award calculations are not verified. A completed report cannot certify persistence across rejoining.

Exports are `Slash-Friend-Boost-Probe-<timestamp>-run<number>.json` in the executor workspace. Readback is verified when available; otherwise the panel states that the write is unverified or offers clipboard/Show JSON. Baseline/final snapshots and phases are retained separately from a timeline capped at 3000 events/two million encoded bytes. Incoming payloads are bounded and common sensitive keys redacted; review user/server identifiers and game-event text before sharing.

Edits use only an already existing numeric field. There is no repeated forcing after an external overwrite. Stop/close uses compare-and-swap restoration; a changed or replaced field is left untouched. A client crash/disconnect can prevent restoration; no server rollback is promised.

Validation: actual Lua and GUI callbacks pass isolated tests for phase timing/gain aggregation, unchanged/changed/inconclusive classifications, finite input, early Stop, restart-generation isolation, external overwrite protection, roster/loadout invalidation, incoming payload redaction, listener cleanup, verified export and export-failure text fallback. These tests are isolated fixtures; live reward effects remain unverified.
