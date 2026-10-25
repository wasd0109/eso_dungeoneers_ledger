# Dungeoneer's Ledger - automated tests

Runs the REAL addon files (loaded in the manifest's order) on a real Lua 5.1 interpreter (python package `lupa`,
module `lupa.lua51`) against a thin ESO API stub layer. No game needed.

    run_tests.bat            (creates .venv with lupa on first run, then runs everything)
    run_tests.bat debounce   (optional: only tests whose name contains the text)

Exit code: 0 all pass, 2 only `test_BUG_*` tests fail (documented real addon bugs/risks), 1 real failures.

Location independent: the addon root is found relative to this folder (this folder's parent when it holds
`DungeoneersLedger.addon`, or `<parent>\DungeoneersLedger`). Optional environment variables:

- `ESO_ADDON_ROOT`      folder with `DungeoneersLedger.addon`
- `ESO_LIBSETS_PATH`    installed LibSets (default `Documents\Elder Scrolls Online\live\AddOns\LibSets`); its dungeon table
                        is read at test time and never copied here (CC BY-NC-ND). Real-data tests skip if absent.
- `ESO_UI_SRC`          extracted esoui source; enables "API names exist in the game" checks (skipped if absent)
- `ESO_PACKAGE_SCRIPT`  `tools\package.ps1` (default: searched upwards); packaging is tested on a temp copy

Layout: `stubs/` (ESO API, finder/tree/manager, real LibSets loader), `data_helpers.lua` (Boot, oracles),
`suites/` (tests), `framework.lua`, `run_tests.py`. Not covered: UI layout, real tooltips/hover, real finder behaviour,
real achievement names and DLC ids - test those in game.
