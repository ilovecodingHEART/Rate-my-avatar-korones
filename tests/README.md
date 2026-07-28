# Tests

```bash
python -m venv .venv && .venv/bin/pip install lupa pillow
.venv/bin/python tests/test_features.py     # 45
.venv/bin/python tests/test_admin.py        # 33
.venv/bin/python tests/test_rateava3.py     # 8
.venv/bin/python tests/render_previews.py   # regenerate docs images
```

`roblox_mock.lua` is a small Roblox stand-in (Instances, signals,
MarketplaceService, DataStoreService) so the real server script can be executed
and asserted against.

- **test_features.py** passes, permanent images, inheritance, cache isolation,
  fail-closed ownership, DataStore outage, boombox, self-healing.
- **test_admin.py** admin access control, creating / editing / deleting
  gamepasses, input validation, builtin protection, purchase routing for new
  passes, and persistence across a restart.
- **test_rateava3.py** loads the real `rateava3.rbxl` Workspace and proves the
  server adopts the 18 loose booths and makes them claimable.
