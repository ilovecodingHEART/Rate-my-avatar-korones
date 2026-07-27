# Rate-my-avatar-korones

Booth system with **Pekora avatar** loading and player-set booth images.

Original booth system by **ywinfe** and **thugshaker**.

## Files

| Path | Goes in |
|---|---|
| `src/ServerScriptService/BoothServer.server.lua` | `ServerScriptService` (a `Script`) |
| `src/StarterGui/MainUI/Client.client.lua` | `StarterGui.MainUI.Client` (a `LocalScript`) |
| `Custom Booth (Pekora).rbxm` | Both scripts already patched in — drag into Studio |
| `Custom Booth.rbxm` | The untouched original model |

## Setup

1. Insert `Custom Booth (Pekora).rbxm` into Studio, then move its folders to the
   matching services (`ReplicatedStorage.RemoteEvent`, `StarterGui.MainUI`,
   `ServerScriptService.Server`, `Workspace.Booths`). Delete the `DELETE ME` part.
2. **Game Settings → Security → Allow HTTP Requests: ON.** The Pekora avatar
   request fails without it.
3. Play. Walk up to a booth, hold the prompt to claim it.

## What the integration adds

**Server (`BoothServer.server.lua`)**

- Fetches the claimer's avatar from `pekora.zip/apisite/thumbnails/v1/users/avatar`
  instead of `GetUserThumbnailAsync`.
- Retries up to 3 times while the thumbnail state is `Pending`, and caches each
  user's URL for 5 minutes so re-claiming does not spam the API.
- Normalises `//host/path` and `/path` responses into absolute URLs.
- `ChangeImage` accepts a bare numeric ID, `rbxassetid://123`, or a link with
  `?id=123` — it is always rebuilt as `rbxassetid://<digits>`, so a player can
  never inject an arbitrary URL.
- `ResetImage` puts the Pekora avatar back.
- Ownership is validated on every remote call, one booth per player, with a
  1-second per-player cooldown.
- A booth whose owner left, or that was unclaimed while an HTTP/filter call was
  still yielding, is never overwritten by the late result.
- Booths added to the folder at run time are wired up automatically.

**Client (`Client.client.lua`)**

The new controls are **built at run time** by cloning the widgets already in
`MainUI`, so the corners, strokes and fonts match and nothing has to be added by
hand in Studio:

| Widget | Type | Purpose |
|---|---|---|
| `ImageBox` | TextBox | "Enter Image / Decal ID.." |
| `ChangeImage` | TextButton | "Set Image" |
| `ResetImage` | TextButton | "Use My Pekora Avatar" |
| `Status` | TextLabel | green/red feedback line |

Enter submits in both text boxes, and the menu rows are re-ordered through
`LayoutOrder` so all eight fit inside the frame.

## Note on raw image URLs

`ImageLabel.Image` only accepts a raw `http(s)` URL on Pekora-style clients.
On live Roblox it must be `rbxassetid://`, so the avatar will fall back to the
placeholder there while the ID-based `ChangeImage` still works.

Compatible with Roblox/Luau from 2021 and earlier — no `task.*`, attributes, or
string interpolation.
