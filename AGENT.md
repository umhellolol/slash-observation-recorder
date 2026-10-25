# Slash Control agent 0.1

This generic Lua agent connects a Slash client to the local Slash Control desktop app. It reports local state and performs explicitly enabled, read-only Prismatic Cosmos shop monitoring. It does not buy, move, trade, launch accounts or automate progression.

Use **Copy connection script** in the desktop app. That script supplies your private local pairing key and loopback address before loading agent.lua. Do not post the copied pairing script or runtime data to GitHub.

Start/Pause/Stop are controlled from the app. Controller lease loss holds new shop reads. An explicit reload replaces the old agent loop and requires Start again. Runtime support for local HTTP requests depends on the execution environment.

Captured data, pairing keys and session tokens remain local. The source repository contains no user credentials.