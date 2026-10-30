# Modifier investigation

Launch the separate recorder:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/umhellolol/slash-observation-recorder/main/modifier-recorder.lua"))()
```

The file referenced below as Slash Modifier Recorder.lua is published here as `modifier-recorder.lua`. Re-run the same launcher to stop/export an active recording. This script has syntax validation only; live capture remains unverified.

Source audit, 30 October 2026. No target-PC experiment has been performed. rc.9 is unchanged.

The current agent reads FriendPowerPercent, AuraMultiplier, SwordPowerMultiplier, SwordWinsMultiplier, SwordAttackSpeedMultiplier, AdminPowerMultiplier, AdminWinsMultiplier, PetMultiplier, PowerMultiplier and WinsMultiplier. Reading a replicated value does not establish that changing the client's copy changes awards. Charm inventory and pet attributes are observable; the complete award formula remains unverified. No arbitrary effective multiplier setter is implemented or verified.

## Read-only capture

Run Slash Modifier Recorder.lua in a connected client. It does not modify stats, equip items, buy anything, intercept remotes or replay requests. It samples known factors, bounded inventory and Power/Wins/Rebirths changes every 250ms. Run it again to stop and export, or wait up to 10 minutes. If executor file writing is available, it writes Slash-Modifier-Observations-<timestamp>.json to the executor's workspace. Otherwise the JSON remains in getgenv().SlashModifierRecorder.json. No cookies, passwords or bearer tokens are collected; game instance and item IDs are included.

For interpretable evidence, hold other conditions constant. Capture a baseline award, then change one legitimate equipment/boost condition and repeat the same action. Note action times separately. Compare one versus another owned charm, pet, aura or sword. Compare friend-boost conditions only when the game actually reports the change. Avoid rebirths or simultaneous equipment changes during each pair. A missing field is unknown, not zero. Multiple awards can occur between samples; large numbers retain only the precision exposed by Roblox.

“+200%” may mean a factor of three relative to baseline, whereas “200% of” means twice baseline. This game's wording, stacking and underlying award calculation must be measured; no formula is assumed here. Sword drop percentages and sword reward multipliers are separate questions; this recorder does not observe the hidden drop table.

The recorder is a diagnostic artifact, not an added production feature and not proof that arbitrary multipliers are possible. Syntax validation cannot establish live capture or a successful server-side reward change. A remote traffic log could show normal client requests and responses but cannot reveal private server code or by itself establish arbitrary-value acceptance.
