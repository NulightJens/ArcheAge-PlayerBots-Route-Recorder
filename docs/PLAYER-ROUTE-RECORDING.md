# Recording player routes

The Windows route recorder turns a normal player walk into a small contribution that can teach PlayerBots main roads, side paths, shortcuts, caves, dungeons, and water routes. Sampling is read-only: the recorder asks AAEmu for the logged-in character's server-owned `Transform` through the existing loopback command API. It does not read or edit client memory.

For a contributor-oriented walkthrough, start with the [README](../README.md). This page documents the formats and maintainer workflow in more detail.

## Contributor workflow

[START-HERE.html](../START-HERE.html) is the installation and capture guide that ships inside the ZIP.
The same-PC Windows GUI provides connection checking, path naming, recording,
location notes and export. Settings holds version information, route type,
direction, notes, capture interval and output folder. The default direction is
from-to; reverse traversability needs its own observation.

`observation` events contain a JSON detail string with note text and a freshly
sampled world/instance/zone/position. If the source is unavailable, the note stays
in its input field and is not attached to stale coordinates. These events survive
normalization. Screenshots and clips remain separate helper attachments.

The tool retries sampling after disconnects and records boundaries. Offline
normalization removes redundant stationary points, splits large discontinuities,
applies 3D simplification and resamples retained segments. These are walks
for a maintainer to review; they are not yet roads the bots use.

Developer entry point: `powershell.exe -NoProfile -ExecutionPolicy Bypass -STA
-File scripts/route-recorder/Start-PlayerRouteRecorder.ps1`. The process-scoped
policy leaves the machine execution policy unchanged. Building the launcher uses
`scripts/route-recorder/Build-PlayerRouteRecorder.ps1`.
## What to contribute

Share the export ZIP and its `.sha256` sidecar, or unpack it and contribute `route.json` plus `manifest.json` under `route-data/contributions/<recording-id>/`. Do not contribute files from `working-recordings`.

An export contains only normalized path metadata and coordinates, a manifest, and checksums. It explicitly excludes the character name, credentials, server logs, the raw working recording, and unrelated files. Review your route name, labels, and notes before sharing them.

To re-run validation and normalization with explicit tolerances:

```powershell
pwsh -NoProfile -File scripts/route-recorder/Export-PlayerRoute.ps1 `
  -RecordingPath 'C:\Routes\working-recordings\my-route.jsonl' `
  -OutputDirectory 'C:\Routes\exports'
```

Exports are immutable by default: the tools refuse to overwrite an existing bundle.

## Merge contributions into a shared graph

Maintainers can merge normalized route JSON files, bundle directories, or bundle ZIPs:

```powershell
pwsh -NoProfile -File scripts/route-recorder/Merge-PlayerRoutes.ps1 `
  -InputPath route-data/contributions/*/route.json `
  -OutputPath route-data/graphs/community-routes-v1.json
```

The merge is deterministic for the same sorted recording set. Nearby observations in the same world and instance form consensus nodes. Each node keeps per-recording observations, zone votes, geometric spread, support count, and confidence. Edges keep recording IDs, path-type votes, and direction votes. Conflicting recordings therefore remain inspectable instead of being silently averaged into false certainty; geometry outside the merge radius remains a separate branch.

The versioned schemas live under `scripts/route-recorder/schemas`. Runtime bot logic does not record, simplify, or merge anything. A reviewed graph can later be compiled into a lightweight navigation input without moving crowdsourcing work into bot ticks.

## Future uploader boundary

The first version intentionally has no hosted database or account system. A future uploader, if community volume warrants it, should accept the exact signed/checksummed bundle format, require explicit authentication and consent, minimize contributor identity, rate-limit and deduplicate submissions, scan notes, support moderation and withdrawal requests, and keep raw working recordings client-side. That service is a separate security and privacy project, not part of this recorder.
