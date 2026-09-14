# Street View photographs

The recorder can take a game photograph every few seconds and pair it with a
fresh position. Stop & export creates a separate Street View ZIP with images,
an offline viewer, observed route trace and checksums. The route-only ZIP keeps
its existing format. No PlayerBots installation or extra server extension is
needed beyond the same standalone position command.

## First walk

1. Press **F9 once in game** and confirm a picture appears under
   `Documents\ArcheAge\ScreenShots`. F9 and this folder are listed in
   [ArcheAge's official 2014 instructions](https://store.steampowered.com/news/posts/?appids=304030&enddate=1408761439).
   Verify your client: if it differs, choose its key/folder in **Photo settings**.
2. On **Record a route**, enable **Take game photos while recording**. The tool
   selects a single open ArcheAge window automatically. If several are open,
   choose yours in Photo settings. This is the game client, separate from the
   Game server used in Server setup.
3. Defaults are ready: a photo every 5 seconds, JPEG copies at most 1600 pixels
   wide, quality 80, and a 512 MB limit. Photo settings keeps all these options.
   Position sampling has its own frequency; each photo requests a fresh position.
4. Start recording and return to the game. Walk for a minute. Photos begin only
   when the selected game is in front; switching away skips captures. Ctrl+Alt+R
   pauses/resumes both route and photos. Photos may contain names, chat and overlays.
5. Stop & export, then click **View photos**. Step forward/back, scrub the walk,
   play the sequence or click a location on the trace. The map uses local X/Y,
   not geographic coordinates or a verified compass bearing. Height is shown.
6. Review the images and share the `-street-view.zip` and its `.sha256` alongside
   the ordinary route ZIP. Recipients extract the entire Street View ZIP and open
   `index.html`. It works offline with no hosting account or network requests.

## Looking around at a landmark

Stop walking but leave recording active. Turn the camera yourself, let it settle,
and press and release **Ctrl+Alt+P** for each extra view (the timer also continues). Take
overlapping views around a bridge, junction or quest interaction. The viewer
counts photos within two meters so you can compare nearby views.

These are separate perspective photographs. The server reports **player heading**,
which can differ from camera heading; camera orientation is recorded as unknown.
We do not label these images a verified 360 panorama or stitch unseen content.
Do not walk while attempting a stationary camera sweep. An orbiting third-person
camera changes viewpoint and can introduce parallax, so a seamless panorama would
need a tested fixed camera position, controlled overlap, orientation and stitching.

## Capture limits and recovery

The default **Game screenshot key** mode sends only the selected function key,
only while the selected client is in front and modifier keys are released. It
waits for one stable, readable JPG, PNG or BMP before requesting another. Existing
unchanged images are ignored. A timeout or multiple new/changed images leaves
them unlinked, with a message. Do not take manual screenshots or run another
automatic screenshot tool during a recording; their files cannot be reliably
distinguished from the requested image. Use Ctrl+Alt+P for extra recorded views.
The tool leaves all game originals untouched. TGA files are not supported; choose
a supported game format if available or use Visible window capture.

**Location timing is approximate.** Metadata distinguishes the key-request time,
the server-position time and when the file was observed. The game does not return
an exact pixel-capture timestamp. The viewer labels native frames “Key requested”;
the displayed offset measures position-to-request time, not capture latency.
Pause/focus loss cancels any pending association, preserving the source image.

Photos stop at 20,000 images or the configured budget for collected JPEGs or
observed native originals. One game-created image can exceed the original-file
budget before the tool can stop further requests. Unmatched/delayed/manual files
are outside this accounting; it is not a hard disk quota. The tool checks free
space before requesting a native screenshot. Route recording keeps running.
Allow space on both drives for game originals, collected JPEGs, an exported
directory and its ZIP (roughly four times the budget, plus unmatched originals).
There is no catch-up burst or image upscaling.

**Visible window capture** remains an optional backend in Photo settings. Use
windowed/borderless mode with the whole game on one monitor. It copies the visible
client area and skips focus loss, minimization, detected covering windows,
near-black images, stale positions and low space. Small/transient overlays may
still appear. Native F9 behavior, exclusive fullscreen and the actual ArcheAge
client remain physical compatibility checks: inspect a two-minute export first.
The tool does not inject into the game, rotate the camera, hide the HUD or use a
whole-desktop capture fallback. Only the screenshot key is sent in native mode.

Unexported collected JPEGs remain beside the raw `.jsonl` in a matching `.photos`
directory. After correcting an export issue, a maintainer can run
`scripts/route-recorder/Export-StreetView.ps1` with `-RecordingPath` and a new
`-OutputDirectory`. Existing exports are never overwritten. A stationary set of
views can still export even when there is no traversable route segment.
