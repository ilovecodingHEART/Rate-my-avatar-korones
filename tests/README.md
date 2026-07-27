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
