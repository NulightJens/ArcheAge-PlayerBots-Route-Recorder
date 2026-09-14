# Route formats, from a walk to a road the bots use

There are three files on the way from a helper's walk to the bots. Each one is small JSON.

## 1. The raw recording (`*.jsonl`)

Written live while you walk, one line per sample. Stays on the helper's PC under `working-recordings`. Never shared. Schema: `scripts/route-recorder/schemas/player-route-recording-v1.schema.json`.

## 2. The exported route (`route.json`)

Made by **Stop and export**, or by `scripts/route-recorder/Export-PlayerRoute.ps1`. Stationary points are removed, gaps are split into segments, the path is simplified. This is what a helper sends, inside a ZIP with `manifest.json` and checksums. Schema: `player-route-v1.schema.json`.

Shape, shortened:

```json
{
  "schema": "playerbots-route-v1",
  "recordingId": "…uuid…",
  "metadata": { "pathName": "Haranya, village gate to east bridge", "pathType": "main-road", "directionality": "from-to" },
  "segments": [
    { "id": "s0001", "worldId": 1, "instanceId": 1,
      "points": [ { "x": 15574.6, "y": 15385.3, "z": 126.2, "zoneId": 179, "offsetMs": 0 }, … ] }
  ],
  "events": [ { "type": "observation", "detail": "wooden bridge, fine on foot" } ],
  "provenance": { "rawRecordingSha256": "…", "recorderToolVersion": "1.2.0" }
}
```

## 3. The merged graph (`route-data/graphs/*.json`)

Made by a maintainer with `Merge-PlayerRoutes.ps1` from several reviewed `route.json` files. Nearby points from different walks become shared nodes with a confidence value; disagreements stay visible instead of being averaged away. Schema: `player-route-graph-v1.schema.json`.

## 4. What the PlayerBots mod reads

The mod does not read any of the files above. It loads road files from its own `Data/BotNavigation` folder, in this shape (`playerbots.recorded-transfer-road-snapshot.v1`):

```json
{
  "schema_version": "playerbots.recorded-transfer-road-snapshot.v1",
  "revision": 1,
  "route_id": "nuian-spawn-solzreed-primary-v1",
  "roads": [
    {
      "worldId": 0,
      "zoneId": 179,
      "pathName": "recorded/nuian-spawn/solzreed-primary/segment-0",
      "pathType": -1001,
      "cellX": 0,
      "cellY": 0,
      "direction": "ForwardOnly",
      "points": [
        { "x": 15574.6, "y": 15385.3, "z": 126.2, "surfaceId": 0 },
        { "x": 15565.1, "y": 15352.9, "z": 127.6, "surfaceId": 0 }
      ]
    }
  ]
}
```

Rules the mod enforces when loading: `schema_version` must match exactly; every road needs `worldId`, a `pathName`, at least two points and a `direction` of `ForwardOnly`, `BackwardOnly` or `Both`; every coordinate must be a finite number. A bad file stops the load with the file name in the error.

Converting a reviewed graph (step 3) into this file (step 4) is done by a maintainer. Automatic conversion from the merged graph to the PlayerBots road format is not available yet.

## 1.6.0 additive exports

The route-v1 document remains readable by existing importers. ZIP manifests now
include navigation-prior files and, for surveys, network.json. Verify every
listed payload hash. See [CITY-NETWORKS.md](CITY-NETWORKS.md) for schemas, directed
junction semantics, world/instance separation and extractor limitations.
