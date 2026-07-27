# Paywall tests

Runs the real `BoothServer.server.lua` inside a Lua interpreter against a small
Roblox mock (`roblox_mock.lua`), covering both the asset and game-pass paths.

```bash
python -m venv .venv && .venv/bin/pip install lupa
.venv/bin/python tests/test_paywall.py
```

Covers: locked users refused, purchase prompt uses the correct API for the
configured type, purchase unlocks without a rejoin, unrelated/cancelled
purchases do not unlock, API errors fail closed, non-owners cannot edit another
player's booth, malformed asset IDs rejected, and ownership caching.

## Booth replacement

`test_replace_geometry.py` checks the placement math against coordinates parsed
from the real `.rbxm` files. `test_replace_booths.py` executes
`scripts/ReplaceBooths.commandbar.lua` inside a mock Studio (`studio_mock.lua`)
built from those same coordinates, covering the dry run, the real run, booth
structure, position/facing accuracy and idempotency.
