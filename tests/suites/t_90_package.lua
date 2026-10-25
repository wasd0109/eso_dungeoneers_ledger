-- Packaging: tools\package.ps1 is run on a staged copy (with decoy tests/, .git, .bak files) and the zip is inspected.
local staged

local function stage()
    if staged then return staged end
    if not CFG.packageScript then
        skip("tools\\package.ps1 not found (set ESO_PACKAGE_SCRIPT); packaging tests skipped")
    end
    staged = host.stage_and_package()
    return staged
end

local function entrySet(result)
    local set, list = {}, {}
    for _, name in ipairs(result.entries or {}) do set[name] = true; list[#list + 1] = name end
    return set, list
end

test("package: script runs and produces DungeoneersLedger-<version>.zip", function()
    local r = stage()
    eq(r.exit, 0, "package.ps1 failed:\n" .. tostring(r.output))
    local _, m = World.readManifest()
    eq(r.zipname, "DungeoneersLedger-" .. m.Version .. ".zip")
end)

test("package: the zip holds every manifest file plus README/CHANGELOG/LICENSE, under one top-level folder, and nothing else", function()
    local r = stage()
    local set, list = entrySet(r)
    local files = World.readManifest("en")
    local expected = { ["DungeoneersLedger.addon"] = true, ["README.md"] = true, ["CHANGELOG.md"] = true, ["LICENSE"] = true }
    for _, rel in ipairs(files) do expected[rel] = true end
    for rel in pairs(expected) do ok(set["DungeoneersLedger/" .. rel], "missing from zip: " .. rel) end
    -- other translation files listed by the manifest only via $(language) must be shipped too
    for _, lang in ipairs({ "de", "es", "fr", "jp", "ru", "zh" }) do ok(set["DungeoneersLedger/lang/" .. lang .. ".lua"], "lang/" .. lang .. ".lua missing") end
    for _, name in ipairs(list) do
        ok(name:sub(1, 18) == "DungeoneersLedger/", "entry outside the top-level folder: " .. name)
        ok(not name:find("\\", 1, true), "backslash in entry name: " .. name)
        local rel = name:sub(19)
        local ok_ = expected[rel] or rel:match("^lang/%a+%.lua$") or rel:match("^src/[%w_]+%.lua$")
        ok(ok_, "unexpected file in the zip: " .. name)
    end
end)

test("package: nothing from tests/, .git, .bak, .venv or scratch files is shipped", function()
    local _, list = entrySet(stage())
    for _, name in ipairs(list) do
        ok(not name:find("/tests/", 1, true) and not name:find("^tests/") and not name:find("tests/", 1, true), "tests entry in zip: " .. name)
        ok(not name:find(".git", 1, true), ".git entry in zip: " .. name)
        ok(not name:find("%.bak"), ".bak in zip: " .. name)
        ok(not name:find(".venv", 1, true) and not name:find("__pycache__", 1, true), "venv/cache in zip: " .. name)
        ok(not name:find("notes.txt", 1, true) and not name:find("Scratch.txt", 1, true), "scratch file in zip: " .. name)
        ok(not name:find("dist/", 1, true), "dist inside zip: " .. name)
    end
end)

test("package: script expects the addon at <script folder>\\..\\DungeoneersLedger, which is where the tests found it", function()
    if not CFG.packageScript then skip("tools\\package.ps1 not found; packaging tests skipped") end
    local text = host.read(CFG.packageScript)
    ok(text:find("Join-Path $root 'DungeoneersLedger'", 1, true), "package.ps1 layout assumption changed")
    local scriptDir = CFG.packageScript:gsub("\\", "/"):match("^(.*)/[^/]+$")
    local parent = scriptDir:match("^(.*)/[^/]+$")
    local source = (parent .. "/DungeoneersLedger"):gsub("\\", "/")
    local root = CFG.addonRoot:gsub("\\", "/"):gsub("/+$", "")
    eq(source:lower(), root:lower(), "package.ps1 would package a different folder than the one under test")
end)

test("package: the script's file list is explicit (no wildcard over the addon root that could pick up tests/ or .git)", function()
    if not CFG.packageScript then skip("tools\\package.ps1 not found; packaging tests skipped") end
    local text = host.read(CFG.packageScript)
    for line in text:gmatch("[^\n]+") do
        if line:find("Get-ChildItem", 1, true) then
            ok(line:find("'src'", 1, true) or line:find("'lang'", 1, true), "Get-ChildItem outside src/lang: " .. line)
            ok(line:find("-Filter *.lua", 1, true), "Get-ChildItem without a *.lua filter: " .. line)
        end
    end
    ok(not text:find("-Recurse", 1, true), "-Recurse would pick up tests/ and .git")
end)
