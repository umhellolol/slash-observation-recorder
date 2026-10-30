# Slash modifier experiment (v2)

This is a separate diagnostic Lua script. It is not part of Slash and it does not claim that a client-side value changes server rewards.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/umhellolol/slash-observation-recorder/main/modifier-recorder.lua"))()
```

## Controls

The in-game panel offers FriendPowerPercent and known aura/pet/power/win/sword fields, showing missing fields as unavailable. Only existing numeric fields can be changed. It prioritizes `NumericStats` for observations, then `PlayerStats`; display strings are never used for arithmetic. Existing numeric attributes such as a pet's `Multiplier`, `StrengthFactor`, `PowerMultiplier`, `WinsMultiplier`, `DropPercent` or `DropChance` are listed with their folder/item path when discovered (up to 100 item fields). Hidden drop tables and server-only charm traits are not exposed or invented. Close and relaunch to rescan newly replaced item objects.

Every row shows original/current values and has `Set` and `Undo`. Set accepts any finite number, writes only the existing numeric attribute or NumberValue/IntValue, and records the requested value. Undo is compare-and-swap: if the field was externally changed or its instance was replaced/detached, it refuses to overwrite it. Restore all applies the same rule. No StringValue, BoolValue, remote, reward request or server mutation is used.

The trial controls are four explicit captures: `Baseline start`, `Baseline end`, `Modified start`, and `Modified end`. First press Baseline start, perform one repeatable action, then Baseline end. Change one factor using Set, press Modified start, repeat that same action, then Modified end. Each end shows the observed Power/Wins delta; the export includes start/end snapshots, elapsed time and both window results. Starting a new baseline clears the previous comparison. This is an observation, not proof of causality or server acceptance. Large numbers retain `%.17g` text and are marked precision-limited where subtraction can lose binary64 precision. Avoid rebirths, purchases, equipment changes and unrelated awards within a measurement window. Fractional writes to IntValue fields may be rounded by Roblox; the log separates requested from observed values.

`Export` writes `Slash-Modifier-Experiment-<timestamp>.json` to the executor workspace and verifies it byte-for-byte when `writefile` and `readfile` exist. A write without readback is labelled unverified. Clipboard copying is attempted when available. `Show JSON` exposes selectable text as a fallback; it does not upload the report. Events, write records and trial history are bounded and report dropped counts. Do not share exports containing account/item data publicly. `Hide modifier panel` leaves a small button to reopen it while you perform the action.

Closing, the fifteen-minute bound or a runtime error stops sampling, best-effort restores active writes, disconnects sampling signals and clears the active environment slot so a later launch can reopen cleanly. The last report remains in `getgenv().SlashModifierRecorderV2Last`. Character replacement attempts restoration and clears the current comparison while keeping the panel open. An external overwrite is logged and never automatically reapplied. Restoration cannot be guaranteed after a client crash, destroyed field, or disconnect; no server rollback is promised.

No remote traffic is intercepted, fired, replayed or inspected. A changed local value or changed reward counter is not evidence that Roblox accepted an arbitrary multiplier. Live target-PC gameplay and server-side reward acceptance remain unverified.

Validation: the actual script and GUI callbacks passed syntax checks and isolated Lua runtime tests for numeric observation, input rejection, Apply/Undo, external overwrite, replaced-instance protection, four-stage reward deltas, verified/failed exports, text fallback, hide/show, character restoration, close and reopen. These tests do not establish that the Roblox client renders identically or accepts modified rewards.
