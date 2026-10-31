# Slash modifier recorder v3

Close the previous recorder panel with × before loading this version. Then run:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/umhellolol/slash-observation-recorder/main/modifier-recorder.lua"))()
```

Press **Start test**, have the friend join, wait several seconds and play normally, have the friend leave, wait several seconds, then press **Stop test**. The file is saved in the executor workspace as `Slash-Modifier-Experiment-<timestamp>-run<number>.json`; verified saving is shown in the panel. Send that export for analysis. There are no baseline/modified stages to manage. Optional edits are allowed only while a test is running, and are separately labelled as local writes.

The recorder opens idle. Start test begins a new run, resets the baseline and event timeline, binds bounded listeners to existing client-visible RemoteEvents, and records the initial raw snapshot. Stop test records the final snapshot before restoration, disconnects test listeners, restores only this run's active local edits using compare-and-swap, and exports the run. A later Start creates a new run ID; closing the panel cleans up the recorder.

The timeline records incoming OnClientEvent payloads as server-to-client-observed with bounded sanitized arguments, player roster additions/removals, the local player's FriendPowerPercent at join/leave and its subsequent observed transitions, non-zero NumericStats changes, other modifier/equipment/inventory transitions, character replacement and five-second heartbeats. Initial/final rosters and snapshots are preserved separately. A join is not asserted to be a friend; it is only a PlayerAdded/PlayerRemoving observation. Event absence is not proof of server absence. No remotes are intercepted, hooked, fired, replayed, or assigned new callbacks outside the recorder's own connections.

Numeric modifier rows remain available as optional local experiments. They list only fields that already exist and are numeric, including discovered pet multiplier/StrengthFactor and related aura/sword fields. Set accepts finite values only. Undo/Restore all uses compare-and-swap and refuses to overwrite an external update or replaced instance. These local edits are marked client-observed with authority unknown; they are not server grants.

Export produces schema 3 with separate baseline/final snapshots, run ID, sequenced event timeline, dropped/truncation counts, writes and restore results. File readback is verified when available; otherwise the UI provides a selectable JSON view and clipboard fallback. Large values retain %.17g text and precision limits. Known routes are checked first, followed by up to 200 visible RemoteEvents, including late-arriving events until that limit. Subscribed routes are distinct from delivered events; unavailable known routes are reported. Event payload depth, string lengths, fields and total nodes are capped; the retained event timeline is limited to 10,000 records and four million encoded bytes. Limits/loss are reported. Sensitive field names are redacted; review exports before sharing, as game/user identifiers and arbitrary game-event text can still be included.

This captures incoming client-visible notifications and replicated state, not outgoing calls, private server scripts or hidden server decisions. A received event is not necessarily the client request used to cause it. Merely finding an event name does not prove that it can be replayed to gain a reward. The recorder is diagnostic only; live Roblox/server authority and reward acceptance remain unverified.

Validation: actual script/GUI callbacks passed isolated tests for idle/start/stop/restart, joins/leaves with the correct local boost, stat/modifier changes, incoming and late event delivery, payload redaction/truncation, retention loss reporting, restoration, listener cleanup and distinct export files. This does not establish live event coverage in the published game.
