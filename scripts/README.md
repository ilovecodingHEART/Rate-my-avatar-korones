# Command Bar scripts

All are **one line with no `--` comments** — the Command Bar collapses pasted
text to a single line, so a `--` would comment out everything after it. Keep
them that way when editing.

Each is **dry-run by default**. Read the output, then change `DRY_RUN = true`
to `false` at the very start of the line and paste again. `Ctrl+Z` undoes.

| Script | Purpose |
|---|---|
| `1_FixBooths.commandbar.lua` | Moves the 18 loose booths into `Workspace.Booths` and renames them `Booth` |
| `2_BuildBoombox.commandbar.lua` | Creates `ServerStorage.Boombox` (Tool + Handle + Sound + RemoteEvent + 2 scripts) |
| `ReplaceBooths.commandbar.lua` | Older: swaps old Banner-style booths for boothgood |

## Why booths broke in rateava3

The 18 booths were sitting **loose in Workspace, still named `boothgood`**,
while `Workspace.Booths` was **empty**. The server only ever scans that folder:

```lua
local Booths = Workspace:WaitForChild("Booths")
```

So no prompts were ever connected and nothing was claimable. The models
themselves were fine — all 18 structurally complete, correctly positioned,
no overlaps. `1_FixBooths` moves them in and resets them to a clean state.
