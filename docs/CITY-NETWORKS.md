# City surveys and navigation data

A normal route is one observed walk. A city network joins multiple walked legs at
explicitly named junctions. Both remain useful after offline navigation extraction.

For example, walk **Gate → Market → Merchant → Market → Mail → Market → Gate**.
Mark each named place when you reach it. Market becomes a shared junction with
three branches. Returning to Gate preserves the loop. Stand at the same marked
spot when reusing a name; another floor or nearby doorway needs another name.

Use Quick marks for **Quest, Merchant, Mail, Door, Stairs, Ramp, Ladder, Blocked,
One-way drop, Bridge, Ferry** and any useful observation. Junction marks define
connections; quick marks describe places. For a blocked passage, note which side
failed and how you got around it. Record upstairs and downstairs separately and
walk the connecting stairs. Only walking both ways establishes both directions.

Pause before teleporting or taking an unrecorded shortcut. Resume at the next
start and mark it. The exporter separates pauses, disconnects, world/instance
changes, implausible jumps and long gaps. It never draws an edge across them.
The name list belongs to one survey. Keep independent survey ZIPs separate for
review; matching text alone is not proof that two surveys share a junction.

## Files in the ZIP

- `route.json`: the existing `playerbots-route-v1` normalized walk and observations.
- `network.json`: `playerbots-route-network-v1`, only for city/area mode. Contains
  explicit junctions, unmarked leg endpoints, observed directed edges with full
  sampled geometry, timestamps, sample references and break reasons. Node IDs
  are scoped to the network/recording ID. A return walk is a separate edge.
- `navigation-prior-w<world>-i<instance>.json`: extractor-compatible
  `edges[].points` in AAEmu server world XYZ coordinates, metres, one context per
  file. Original world and instance IDs are preserved; no map offset is guessed.
- `manifest.json` and `SHA256SUMS.txt`: file fingerprints. The ZIP also has an
  external `.sha256` file. Existing outputs are never overwritten.

Declared client build, recording identity and raw-recording SHA-256 travel with
the output. Do not silently mix different client builds, worlds or instances.
Raw working files stay local under Documents/ArcheAge Routes/working-recordings.

## Navigation Extractor

Pass the appropriate extracted `navigation-prior` file to the existing
**`--road-prior`** option, together with its matching **`--world-id`**, world
name and bounded region. `--trace` can use the same file for comparison. Keep all
the extractor's required game_pak, start, end, output and route-id arguments.

The current extractor treats this as a centreline preference or comparison
trace. It uses native BAI connectivity and does not import the recorded edges as
new topology or enforce their direction. It checks world IDs, not instance IDs;
the maintainer must choose a matching instance/context. Do not install these
files directly into the bot runtime or treat them as an extracted navmesh.

The extractor reads navigation connections from game data. Your recordings add
local details: entrances, junctions, useful destinations, blocked passages, floors
and alternative routes. Walk both directions and mark those details as you go.
