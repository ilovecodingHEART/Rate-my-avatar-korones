# Rate-my-avatar-korones

Booth system for the Rate My Avatar place, plus a staff panel with ranks,
commands and a booth report queue.

Original booth system by ywinfe and thugshaker.

## Where the code lives

The place is `latestratemyavatar.rbxl`. Editing Lua inside a binary `.rbxl` is
miserable, so the two scripts that matter are also kept as plain files:

| File | Where it goes in the place |
| --- | --- |
| `src/Server.server.lua` | `ServerScriptService.Server` |
| `src/Client.client.lua` | `StarterGui.MainUI.Client` |

`src/` is the source of truth. `tools/build.sh` checks it, tests it, and writes
it back into the `.rbxl`, so the two never drift.

```
./tools/build.sh
```

Nothing is packed unless every check and every test passes.

## Staff ranks

Three ranks. Higher can do everything lower can.

| Rank | Who sets it | What it adds |
| --- | --- | --- |
| **Owner** | hard coded in the script | everything |
| **Developer** | hard coded in the script | make Admins, everything below |
| **Admin** | a Developer or Owner | bans, god mode, the shop editor, trolling, make Mods |
| **Mod** | an Admin | kick, mute, freeze, warn, the report queue |

**thugshaker (49603) is the hard coded Owner**, in `OWNERS` at the top of
`src/Server.server.lua`.

**qzc (78857)** and **ywinfe (181869)** are hard coded **Developers**, in
`DEVELOPERS` just below it.

Both tables live in the script rather than the whitelist, which means those
ranks cannot be changed from inside the game by anybody — not by an Admin, not
by each other, not by a tampered DataStore. Nobody can promote themselves out
of a mistake, and nobody can lock the owner or the developers out.

Developer sits between Admin and Owner. Because every rank check is a `>=`
comparison, a Developer inherits every Admin power automatically; what the rank
adds on top is being able to hand out Admin, and being untouchable by one.

Permission is always by UserId, never by name. Somebody renaming themselves
`thugshaker` gets nothing. The UserId is the number in a profile URL:

```
https://www.pekora.zip/users/49603/profile
                             ^^^^^
```

Everyone else is whitelisted from the panel and stored in a DataStore.

### The rules that stop staff fighting each other

* You cannot act on somebody who ranks at or above you. An Admin cannot kick
  another Admin, and nobody but an Owner can touch an Owner.
* You cannot act on yourself.
* You cannot hand out a rank at or above your own, so only an Owner can make
  an Admin.
* Owner cannot be granted in game at all.

All of it is enforced on the server. The panel greys buttons out to match, but
that is only a convenience: firing the remote by hand hits the same checks.

## The panel

Opened with the **Admin** button, which is only visible to staff. Six pages,
and you are only sent the ones your rank can use.

* **Home** — who you are, your headshot, a count of players / open reports /
  claimed booths, and the server wide actions.
* **Players** — everyone here, with their rank, booth and any moderation
  already on them. Pick somebody and every command that takes a target appears
  as a button.
* **Reports** — the queue of reported booths.
* **Staff** — the whitelist and the ban list. Admin and up.
* **Shop** — the gamepass editor that used to be the whole panel. Admin and up.
* **Trolling** — harmless pranks, kept away from the moderation buttons.
  Admin and up.

The header greets you by name with your own avatar headshot: `Hello, <name>.`

## Commands

Every command works two ways, and both go through the same function, so the
button and the chat command can never drift apart.

```
/kick bob being rude
```

The panel builds its buttons from the command list the server sends, and the
server only sends the commands your rank can run. Adding a command on the
server makes a button appear on its own, with no client change.

| | Commands |
| --- | --- |
| **Mod** | `kick` `mute` `unmute` `freeze` `unfreeze` `warn` `bring` `goto` `respawn` `speed` `jump` `heal` `clearbooth` `unclaim` `announce` `time` |
| **Admin** | `ban` `unban` `god` `ungod` `invisible` `visible` `resetbooths` `lock` `unlock` `mod` `unstaff` |
| **Developer** | `admin` |
| **Trolling** (Admin) | `fling` `spin` `fire` `sparkle` `smoke` `ghost` `explode` `jail` `disco` `cleanup` |

`lock` turns away anyone who is not staff. Bans and mutes survive a rejoin;
freeze, god and invisible are per session but survive a respawn, so resetting
is not an escape.

## Staff tags

Staff are visible to everyone two ways: a coloured label above their head, and
a `[Rank]` in front of their chat messages. Both follow the rank they already
have, so a promotion or demotion updates them immediately rather than at the
next rejoin, and the nametag is rebuilt on respawn.

Each rank has its own colour, checked by a test to be distinct, so they are
tellable apart across a room:

| Rank | Colour |
| --- | --- |
| Owner | gold |
| Developer | green |
| Admin | purple |
| Mod | blue |

The nametag deliberately does **not** draw through walls, so a busy server does
not turn into a wall of floating names.

The chat tag needs the default Roblox chat, because that is what exposes a
server side hook for it. If the place uses a custom chat the nametags still
work and the output says the chat tag was skipped, rather than failing quietly.

## Trolling

An Admin-only page of harmless nonsense: `fling`, `spin`, `fire`, `sparkle`,
`smoke`, `ghost`, `explode`, `jail`, `disco`, and `cleanup` to undo all of it.

They are on their own page rather than mixed in with moderation, so a mis-click
sets somebody on fire instead of banning them rather than the other way round.
Every one of them is:

* **reversible** — `cleanup` puts a person fully back to normal
* **unable to end a session** — nothing here kicks, bans, or leaves somebody
  stuck with no way out, and the explosion has zero blast pressure so it cannot
  actually hurt anyone
* **Admin and up** — being flung across the map by a bored Mod stops being
  funny quickly
* **logged** like every other command, so it is never a mystery who did it

`cleanup` deliberately leaves a moderation `invisible` alone, so it cannot be
used to put a hidden mod back on screen. The disco runs for a fixed fifteen
seconds rather than toggling, so it cannot be left on by someone who logs off.

## Reports

Any player can report a booth with the **Report** button: pick the booth, pick
a reason from the fixed list, optionally add a note.

Reasons are fixed rather than free text so staff get something they can triage
at a glance, and so a report cannot itself be used to put abuse in front of a
moderator. The optional note is filtered like any other player text.

A report stores a snapshot of what the booth said and showed, so staff can
still see what was reported after the owner changes it or leaves. Staff can
jump to the booth from the card, then act on the owner from the Players page,
which keeps punishments going through the normal rank checks.

Guarded against: no reporting your own booth, no reporting an unclaimed booth,
one open report per booth per person, a per player cooldown, and a cap on the
queue.

## Avatar images

Headshots come from the thumbnails API. Requesting the site directly from
in-game is blocked, so everything goes through the proxy:

```
https://koroneproxy.onrender.com/apisite/thumbnails/v1/users/avatar-headshot?userIds=49603&size=420x420&format=png
https://koroneproxy.onrender.com/apisite/avatar/v1/users/49603/avatar
```

None of it is load bearing. If HTTP is off, the proxy is asleep, or the reply
is not what was expected, it falls back to the client's own
`GetUserThumbnailAsync`, and then to a plain initial in a circle. The panel
never blocks on a picture and every other feature carries on working. There is
a test for each of those cases.

## Tests

```
python3 tools/runtests.py
```

270 tests. They run the real `Server.server.lua` and `Client.client.lua`
against a mock of the Roblox API (`tools/mock_roblox.lua`, `tools/harness.lua`)
and drive both halves the way a player would, including pressing client buttons
and checking what the server actually did.

Worth knowing: several bugs in this work were found by these tests rather than
by reading, including admin actions being silently swallowed by the booth
cooldown, and opening the report window eating the cooldown that the send then
needed.

The other checks are small and specific:

| Tool | Catches |
| --- | --- |
| `tools/luacheck.py` | syntax, and how close the file is to Lua's 200 local limit |
| `tools/luaorder.py` | calling a `local function` declared further down, which reads as a nil global rather than erroring |
| `tools/luaglobals.py` | calling a name that is never declared, usually a typo or a half finished rename |
| `tools/checklayout.py` | widgets overlapping, overflowing their parent, or too short to render text |

## Checking the layout

The panel is built in code, so nothing in the `.rbxl` says what it looks like
and a bad number just quietly draws one thing on top of another.
`tools/checklayout.py` resolves the Size/Position/AnchorPoint values as
written, composes them down the parent chain, and reports the result in pixels:

```
python3 tools/checklayout.py src/Client.client.lua
```

It runs twice, at a normal window and again at the panel's minimum size, since
scaled-down is where these bugs actually appear. It knows about the square
headshot whose width comes from its height, which is not visible in the numbers
on their own.

`tools/preview.py` draws the same maths as a PNG when you want to look at it:

```
python3 tools/preview.py Home        # or Players, Reports, Staff, Shop
```

It is not a renderer and does not replace opening Studio, but it is enough to
see a collision or a squashed row.

The local limit check matters more than it sounds: the client script sits close
to the ceiling, and going over is a hard compile error rather than a warning.

## Working on the place file

`tools/rbxl_parse.py` reads a binary `.rbxl` and can dump every script in it.
`tools/rbxl_edit.py` writes sources back in, copying every other chunk through
untouched so nothing else in the place can shift. A no-op edit is byte
identical chunk for chunk, which is what makes it safe to run on every build.

```bash
python3 tools/rbxl_parse.py latestratemyavatar.rbxl /tmp/dump   # read
./tools/build.sh                                                # check + write
```
