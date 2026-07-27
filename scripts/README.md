# ReplaceBooths.commandbar.lua

Swaps the 18 old map booths for the `boothgood` template, in `rateava2.rbxl`.

## Why the first version did nothing

The Command Bar collapses pasted multi-line text into **one line**. The old
script started with a `--[[ ]]` comment block and used `--` comments
throughout, so once collapsed the very first `--` commented out the entire
rest of the line. It "ran" with no error and did nothing.

This version is **one single line with zero comments**, so pasting cannot
break it. Keep it that way when editing.

## Use

1. Open `rateava2.rbxl`. `boothgood` is already in Workspace, so there is
   nothing to insert.
2. Paste the whole line into the **Command Bar** and press Enter.
3. It is a **dry run**: it only prints a report. Read it.
4. Change `DRY_RUN = true` to `false` at the very start of the line, paste
   again, press Enter.

`Ctrl+Z` undoes the whole run.

## Settings

They are the first few assignments on the line.

| Setting | Default | Purpose |
|---|---|---|
| `DRY_RUN` | `true` | Report only, change nothing |
| `FLIP_180` | `true` | Set `false` if booths end up facing backwards |
| `DELETE_OLD` | `true` | `false` moves old booths to `OldBooths_Backup` |
| `HEIGHT_OFFSET` | `0` | Raise / lower every booth |
| `FORWARD_OFFSET` | `0` | Push every booth forward / back |

## What it handles

The two booth types are unrelated, so this places new booths and deletes the
old, rather than editing properties:

| | old booth | boothgood |
|---|---|---|
| Parts | Pole, Banner, Tabletop, Carpet, Table | Base, Display, PartNamePlayer, strokes |
| Display face | Banner, **Front** | Display, **Back** |
| PrimaryPart | none | none |
| Height | 10.4 studs | 10.5 studs |

- **No `SetPrimaryPartCFrame`** — neither model has a PrimaryPart, so it would
  throw. Each part is moved by a transform instead.
- **180° flip**, because Front and Back point opposite ways. Without it all 18
  booths face backwards into their own tables.
- **Ground alignment, not centre** — the two models differ in height, so
  matching centres would sink or float them. Verified exact to 0.00000 studs.
- Rotation-aware bounding boxes; the booths sit at yaws of 76°, -14° and -104°.
- Skips the `boothgood` template itself, and refuses to run if the template has
  been moved inside the `Booths` folder.
- Results go to `Workspace.Booths`, which the server script scans.
- Safe to re-run: already-converted booths are ignored.

## Tests

```bash
python tests/test_replace_in_place.py   # runs the script against rateava2.rbxl (17 checks)
python tests/test_replace_geometry.py   # placement math vs the rbxm map
python tests/test_replace_booths.py     # the rbxm map in a mock Studio
```
