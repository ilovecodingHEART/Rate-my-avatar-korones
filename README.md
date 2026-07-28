# Rate-my-avatar-korones

Booth system for Pekora: claimable booths, three gamepasses, a shop, a working
boombox and a loading screen. Dark theme throughout.

Original booth system by **ywinfe** and **thugshaker**.

---

## The GUI

> These previews are **rendered from the code**, not screenshotted from a running
> game. `tests/render_previews.py` parses the real `THEME` colours, row heights,
> paddings and pass titles straight out of the scripts and draws them, so they
> cannot drift from what actually ships. Exact in-game fonts and antialiasing
> will differ slightly.

### Loading screen

Counts to 10,000 in ~5 seconds, then fades out. Time-driven, so it always takes
5 seconds regardless of framerate.

![Loading screen](docs/gui-loading.png)

### Booth menu — locked

Without the upload gamepass the button turns amber, the ID box is read-only and
clicking it opens the shop.

![Booth menu locked](docs/gui-booth-locked.png)

### Booth menu — unlocked

![Booth menu unlocked](docs/gui-booth-unlocked.png)

### Shop

One row per gamepass, pulled live from the server's `PASSES` table.

![Shop](docs/gui-shop.png)

Items you already own show a green **Owned** badge instead of **Buy**:

![Shop with owned items](docs/gui-shop-owned.png)

### Boombox

Appears at the bottom of the screen only while the tool is equipped.

![Boombox panel](docs/gui-boombox.png)

---

## Install — three scripts, no Command Bar

| # | Where | What |
|---|---|---|
| 1 | `ServerScriptService.Server` | paste `src/ServerScriptService/BoothServer.server.lua` |
| 2 | `StarterGui.MainUI.Client` | paste `src/StarterGui/MainUI/Client.client.lua` |
| 3 | `ReplicatedFirst` → new **LocalScript** | paste `src/ReplicatedFirst/LoadingScreen.client.lua` |

Nothing else. The server builds the rest on its own at run time.

## Self healing

Booths only work inside `Workspace.Booths`, because that is the only place the
server looks. Duplicating in Studio leaves them loose in Workspace, usually
still called `boothgood` — which is exactly what broke `rateava3.rbxl`.

So the server repairs it itself on every boot:

- creates `Workspace.Booths` if it is missing (never `WaitForChild`, which
  would hang forever and break everything)
- sweeps Workspace, adopts anything shaped like a booth, renames it `Booth`
- ignores models that only *look* similar
- builds `ServerStorage.Boombox` if absent

## Gamepasses

Sold as Pekora catalog shirts, since real game passes do not work there. All
use `PlayerOwnsAsset` / `PromptPurchase`. Players only ever see the word
"Gamepass", never a shirt name.

| Item | Asset ID | Unlocks |
|---|---|---|
| Image uploads | `356360` | Set the image on the booth you claimed |
| Boombox | `353454` | Boombox tool that plays any audio ID |
| Permanent image | `353447` | Your image stays on the booth after you leave |

Ownership is enforced **on the server**; hiding a button is only cosmetic. It
fails closed, so an API error denies the perk rather than giving it away.

## Permanent images

Buying `353447` makes your image belong to the **booth**, not to you:

- saved per booth by index in a DataStore
- survives unclaim, disconnect and server restart
- the next claimer inherits it, and cannot replace it without `356360`
- `ResetBooth` deliberately does **not** wipe it

Without the pass an image is temporary: shown now, gone on unclaim, and it
never overwrites a paid one.

Unclaimed booths and booths with no saved image show `rbxassetid://821176`.

## Boombox

The tool is generated at run time with just a Handle and a Sound — no scripts
inside it. `Script.Source` cannot be written at run time, so a generated tool
can never carry its own code. The logic lives in the two scripts you already
paste: the server drives the sound, the client draws the panel.

It is currently a **plain black brick**. Drop a boombox model in and it will be
used instead.

## Tests

```bash
python -m venv .venv && .venv/bin/pip install lupa pillow
.venv/bin/python tests/test_features.py     # 39 checks
.venv/bin/python tests/test_rateava3.py     # 8 checks, against the real place file
.venv/bin/python tests/render_previews.py   # regenerate the images above
```

Covers passes, permanence, inheritance, per-item cache isolation, fail-closed
ownership, DataStore outages, boombox grants, and self-healing the exact
`rateava3.rbxl` layout.

## Known unknowns

- `rbxassetid://821176` is unverified — pekora.zip is unreachable from the
  build environment. If booths look blank, that ID needs swapping.
- Permanent images need **Studio Access to API Services** enabled to save while
  testing in Studio. They work normally in a live server.
