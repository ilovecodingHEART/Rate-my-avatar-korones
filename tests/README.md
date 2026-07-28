# Tests

```bash
python -m venv .venv && .venv/bin/pip install lupa
.venv/bin/python tests/test_features.py
.venv/bin/python tests/test_rateava3.py
```

`roblox_mock.lua` is a small Roblox stand-in (Instances, signals,
MarketplaceService, DataStoreService) so the real server script can be executed
and asserted against.

- **test_features.py** (39) passes, permanent images, inheritance, cache
  isolation, fail-closed ownership, DataStore outage, boombox, self-healing.
- **test_rateava3.py** (8) loads the real `rateava3.rbxl` Workspace and proves
  the server adopts the 18 loose booths and makes them claimable.
