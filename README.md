# ArcheAge Route Recorder

[Download this preview](https://github.com/NulightJens/ArcheAge-PlayerBots-Route-Recorder/releases/tag/v1.6.0) · [Tool family](FAMILY.md)

Record the streets you walk and mark useful places. **1.6.0 candidate · Windows**

Extract the complete ZIP and open **PlayerRouteRecorder.exe**. Follow
[START-HERE.html](START-HERE.html) for one-time setup. You need a working local
AAEmu Game server and an online GM character; the PlayerBots mod is not required.

## Connect

1. In **Server setup**, select the **AAEmu.Game.exe** you actually run. Install
   the extension while Game is stopped, then start Game normally.
2. Enter your in-game **Character name** and **Client build**, for example
   `ArcheAge 1.2 r208088`, then click **Check connection**.
3. If connection fails, follow the specific message beside the character field.
   The local API address can be changed in Server setup. Keep it on loopback.

AAEmu 1.2 r208022 is the tested baseline. Other revisions are experimental and
may be used when the position command works. A successful check proves a valid
position sample, not full client/server compatibility. Your build label is saved
as declared; the tool does not guess it. If problems persist, use a matching
r208022 server/client setup. Do not rebuild your installation solely because the
old recorder showed a generic connection error.

Already connected with an older recorder? The position extension is unchanged.
Extract this version and check connection; no extension reinstall is needed for
these tool changes. Existing files and saved quick marks are preserved.

## Record a road

Choose **Landmark-to-landmark route**, fill **From / to**, then **Start recording**.
Walk normally and finish with **Stop & export → Show export**. Route settings
keeps frequency, road type and direction. Only select bidirectional after walking
both directions. Quick marks save Quest, Fork, Merchant, Mail or your own labels.

## Map a city

Choose **City / area network** and enter the area name in **Area name**. From/to
are unnecessary. Start recording. At each junction, enter a unique name such as
`Market square` and click **Mark junction**. Walk a branch, mark its far end,
then return to the same junction and select its existing name. Explore the next
branch. Loops and repeated visits are kept.

Reusing a name confirms the same place and floor: within 1.5 metres horizontally
and 0.75 metres vertically in the same world/instance. Different floors need
different names. Nearby streets and map crossings never join automatically.
Pause before an unrecorded move, then resume and mark your new start. Only the
directions actually walked become edges. Names are reused within the current
survey; combining independent surveys requires review.

## Share

Send the exported ZIP and `.sha256` file. It contains the existing `route.json`,
checksummed navigation-prior files, and `network.json` for city surveys. Read
[the network guide](docs/CITY-NETWORKS.md) for examples and extractor usage.
These are collection evidence, not a ready-to-install bot navigation database.
Review notes before sharing; nothing uploads automatically.

Optional photo controls remain documented in [the photo guide](docs/STREET-VIEW.md).

## Build from source

From a committed checkout, run
`scripts/New-StandaloneRouteRecorder.ps1 -OutputDirectory <new-folder>`.
The Windows ZIP needs no separately installed PowerShell module or full bot mod.
See [CHANGELOG.md](CHANGELOG.md) and [LICENSE.md](LICENSE.md).
