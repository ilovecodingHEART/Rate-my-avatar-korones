# ReplaceBooths.commandbar.lua

Swaps all 18 old map booths for the `boothgood` template.

## Use

1. Insert `boothgood.rbxm` into the place (anywhere — it auto-detects).
2. Open the map so it's in `Workspace`.
3. Paste the whole script into the **Command Bar** and press Enter.
4. It runs a **dry run** first and only prints a report. Read it.
5. Set `DRY_RUN = false` at the top and run again to apply.

`Ctrl+Z` undoes the entire run.

## What it handles

The two booth types are structurally unrelated, so this is a place-and-delete,
not a property copy:

| | old map booth | boothgood |
|---|---|---|
| Parts | Pole, Banner, Tabletop, Carpet, Table | Base, Display, PartNamePlayer, strokes |
| Display face | Banner, **Front** | Display, **Back** |
| PrimaryPart | **none** | none |

Because of those differences the script:

- **Never calls `SetPrimaryPartCFrame`** — the map booths have no PrimaryPart,
  so it would throw. It moves each part by a transform instead.
- **Rotates 180°** (`FLIP_180`), since Front and Back point opposite ways.
  Without it every booth faces backwards.
- **Aligns by ground, not centre.** The old booth is 10.4 studs tall and the
  new one 10.5, so matching centres would sink/float them. It matches the
  bounding-box *bottom*, verified to land within 1e-6 studs.
- Computes bounding boxes with rotation-aware half-extents; the booths sit at
  yaws of -104°, 166° and 76°, so an axis-aligned box would be wrong.
- Collects results into `Workspace.Booths`, which is what the server script
  scans, and is safe to re-run (it won't touch already-converted booths).

## Knobs

| Setting | Default | Purpose |
|---|---|---|
| `DRY_RUN` | `true` | Report only |
| `FLIP_180` | `true` | Set `false` if booths face backwards |
| `HEIGHT_OFFSET` | `0` | Raise/lower all booths |
| `FORWARD_OFFSET` | `0` | Push booths forward/back |
| `DELETE_OLD` | `true` | `false` moves old booths to a backup folder |

## Tests

```bash
python tests/test_replace_geometry.py   # placement math vs real coordinates
python tests/test_replace_booths.py     # runs the Lua script in a mock Studio
```
