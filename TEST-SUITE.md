# Slash lane test

Version **1.2.0** · testing account: **mxssyo**.

This version opens one simple guided test. You do not need to repeat the other tests or select technical pass/fail labels.

## Open it

Save and close any older recorder or suite. Join Slash on **mxssyo**, leave training, and choose the world whose lane you want to check. Then run:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/umhellolol/slash-observation-recorder/main/test-suite.lua"))()
```

## Follow the five steps

1. **Start test.** The tool turns off Auto Win and Auto Rebirth. Keep this game server open.
2. Clear the whole lane normally. **Do not touch the Wins reward pad.** Press **I've cleared the lane**. The tool checks fresh wall information before continuing.
3. Press **Travel away and back**. The tool chooses another unlocked world and handles the round trip.
4. Press **Check my lane** after returning. The tool compares fresh lane information with the recorded cleared lane.
5. Press **Save result** and send the displayed JSON file back in this chat. The file is written into your execution environment's workspace, as with the previous captures.

If the lane changes, the trip is interrupted or something cannot be verified, save that result too. You do not have to force a pass. Avoid rebirth, claims and extra wall clearing during the round trip/check.

## Window controls

Drag the title bar to move the window. Drag the bottom-right corner to resize. The top buttons minimize/restore, maximize/restore and close. Recording continues while minimized. The window sits above ordinary game labels.

**Save progress** is available throughout. Closing offers **Save & close**, **Close**, or **Cancel**; a failed save keeps the window open. Save before leaving the game. Progress does not resume automatically after rejoining.

## What happens in the background

The recorder keeps the detailed events and snapshots needed for review. The result file includes the prior 22-case evidence catalog, the guided lane comparison and separate command/observation/save status. The screen only shows what you need for this test.

Only the selected lane and observed round trip can pass. Cached state, a button press or successful saving cannot establish persistence. The test requests fresh wall responses before and after travel and refuses to pass when relevant state changes or responses are missing. The protocol has no request correlation ID; the export records that limitation.

The test issues no purchases, trades, rebirths or wall attacks. You clear the lane yourself. Start disables the game's Auto Win/Auto Rebirth settings; physical reward-pad touches and changes made through the game UI remain possible.

This remains information gathering. The desktop platform and Prismatic Cosmos purchasing automation are not running yet. The recorded future policy targets only `PrismaticCosmos` as the highest regular-gameplay priority outside Admin Abuse.

## Verification

Lua syntax and simulated Roblox checks cover baseline replacement, unfinished trials, separate command outcomes, stale wall data, lane success/reset, claims/respawn interruptions, missing fresh responses, failed travel, save failure, the primary UI action and window controls. Actual rendering and the live lane experiment still need your in-game run.