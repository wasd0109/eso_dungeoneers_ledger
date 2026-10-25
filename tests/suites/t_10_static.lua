-- Static / housekeeping tests: syntax, strings, manifest, globals, load order, source greps.
local function path(rel) return World.joinPath(CFG.addonRoot, rel) end
local function read(rel) return assert(host.read(path(rel)), "cannot read " .. rel) end

local function addonLuaFiles()
    local out = {}
    for _, full in ipairs(host.walk_files(CFG.addonRoot, { ".lua" })) do
        local rel = full:gsub("\\", "/"):sub(#CFG.addonRoot:gsub("\\", "/") + 2)
        if not rel:match("^tests/") and not rel:match("^%.") and not rel:match("^dist/") and not rel:match("^tools/") then
            out[#out + 1] = rel
        end
    end
    table.sort(out)
    return out
end

local function srcFiles()
    local out = {}
    for _, rel in ipairs(addonLuaFiles()) do if rel:match("^src/") then out[#out + 1] = rel end end
    return out
end

local function stripComments(src)
    src = src:gsub("%-%-%[%[.-%]%]", "")
    return (src:gsub("%-%-[^\n]*", ""))
end

test("syntax: every addon Lua file compiles on Lua 5.1", function()
    local files = addonLuaFiles()
    ok(#files >= 18, "expected the addon's lua files, found " .. #files)
    for _, rel in ipairs(files) do
        local chunk, err = loadstring(read(rel), "@" .. rel)
        ok(chunk, "syntax error: " .. tostring(err))
    end
end)

test("runtime: tests run on real Lua 5.1 (strict vs LuaJIT-isms)", function()
    eq(_VERSION, "Lua 5.1")
    ok(not jit, "unexpected LuaJIT")
end)

---------------------------------------------------------------- manifest
test("manifest: APIVersion, Version, SavedVariables and dependencies", function()
    local files, meta, text = World.readManifest()
    ok(meta.APIVersion and meta.APIVersion:match("^%d+[%d ]*$"), "APIVersion missing/invalid")
    for v in meta.APIVersion:gmatch("%d+") do ok(#v == 6, "APIVersion should be 6 digits: " .. v) end
    ok(meta.Title and meta.Title ~= "", "Title missing")
    local w = Boot({ libsets = "none", start = false })
    eq(meta.Version, w.store.DungeoneersLedger.version, "manifest ## Version must equal DL.version")
    ok(tonumber(meta.AddOnVersion), "AddOnVersion must be a number")
    ok(meta.SavedVariables:find("DungeoneersLedger_SavedVariables", 1, true), "own SavedVariables not declared")
    ok(meta.SavedVariables:find("DungeonCompletion_SavedVariables", 1, true), "old SavedVariables must be declared so the import can read them")
    -- dependencies: both libraries required, with minimum versions
    local deps = meta.DependsOn or ""
    ok(deps:match("LibSets>=9040"), "DependsOn must contain LibSets>=9040, got: " .. deps)
    ok(deps:match("LibAddonMenu%-2%.0>=43"), "DependsOn must contain LibAddonMenu-2.0>=43, got: " .. deps)
    ok(not (meta.OptionalDependsOn or ""):find("LibAddonMenu", 1, true), "LibAddonMenu-2.0 must not also be optional")
    ok(not text:find("%.bak"), "manifest must not mention .bak files")
end)

test("manifest: every listed file exists, no duplicates, order is valid", function()
    local files = World.readManifest("de") -- $(language) -> a language other than en, so duplicates are real ones
    local index, seen = {}, {}
    for i, rel in ipairs(files) do
        ok(host.exists(path(rel)), "manifest lists a missing file: " .. rel)
        ok(not seen[rel], "listed twice: " .. rel)
        seen[rel] = true
        index[rel] = i
    end
    ok(index["lang/en.lua"], "lang/en.lua missing")
    ok(index["lang/en.lua"] < (index["lang/en.lua"] + 1) and files[2]:match("^lang/"), "language file must follow lang/en.lua")
    for rel, i in pairs(index) do
        if rel:match("^src/") then
            ok(i > index["lang/en.lua"], rel .. " is loaded before the strings")
            ok(index["DungeoneersLedger.xml"] and i > index["DungeoneersLedger.xml"], rel .. " is loaded before the XML templates")
            ok(index["Overrides.lua"] and i > index["Overrides.lua"], rel .. " is loaded before Overrides.lua")
        end
    end
    ok(index["src/Core.lua"] < index["src/LibSetsData.lua"], "Core first")
    -- every src file on disk is listed, and every listed src file exists
    for _, rel in ipairs(srcFiles()) do ok(index[rel], "src file not in manifest: " .. rel) end
    for _, rel in ipairs(files) do ok(rel:match("%.lua$") or rel:match("%.xml$"), "unexpected file type in manifest: " .. rel) end
end)

test("manifest: modules run in order - no module uses a DL member at load time that a later module defines", function()
    local w = World.new({})
    LibSetsReal.install(w, {}, true)
    Data.installLAM(w)
    local files = World.readManifest()
    local bad = {}
    for _, rel in ipairs(files) do
        local DL = w.G.DungeoneersLedger
        local mt
        if DL and rel:match("^src/") then
            mt = { __index = function(_, k) bad[#bad + 1] = rel .. " reads DL." .. tostring(k) end }
            setmetatable(DL, mt)
        end
        w:loadFile(rel)
        if DL and mt then setmetatable(DL, nil) end
    end
    eq(#bad, 0, table.concat(bad, "; "))
end)

test("DL members: every DL.<name> referenced in the code is defined after loading", function()
    local w = Boot({ libsets = "none", start = false })
    local DL = w.store.DungeoneersLedger
    local optional = { panel = true, debugEnabled = true, stringsLoaded = true }
    local missing = {}
    for _, rel in ipairs(srcFiles()) do
        for name in stripComments(read(rel)):gmatch("DL%.([%a_][%w_]*)") do
            if DL[name] == nil and not optional[name] then missing[name .. " (" .. rel .. ")"] = true end
        end
    end
    local list = {}
    for k in pairs(missing) do list[#list + 1] = k end
    table.sort(list)
    eq(#list, 0, "undefined DL members: " .. table.concat(list, ", "))
end)

---------------------------------------------------------------- strings
local function usedStringIds()
    local used = {}
    for _, rel in ipairs(srcFiles()) do
        for id in stripComments(read(rel)):gmatch("SI_DUNGEONEERSLEDGER_[%u%d_]+") do used[id] = used[id] or rel end
    end
    return used
end

local function definedStringIds()
    local defined = {}
    for id, text in read("lang/en.lua"):gmatch("(SI_DUNGEONEERSLEDGER_[%u%d_]+)%s*=%s*(%b\"\")") do defined[id] = text end
    return defined
end

test("strings: every SI_DUNGEONEERSLEDGER_* used in src exists in lang/en.lua", function()
    local used, defined = usedStringIds(), definedStringIds()
    for id, rel in pairs(used) do ok(defined[id], id .. " (used in " .. rel .. ") is not defined in lang/en.lua") end
end)

test("strings: no string id in lang/en.lua is unused", function()
    local used, defined = usedStringIds(), definedStringIds()
    local unused = {}
    for id in pairs(defined) do if not used[id] then unused[#unused + 1] = id end end
    table.sort(unused)
    eq(#unused, 0, "unused strings: " .. table.concat(unused, ", "))
end)

test("strings: format placeholders in en.lua match how the code formats them", function()
    local w = Boot({ libsets = "none", start = false })
    local DL = w.store.DungeoneersLedger
    -- id -> number of arguments the code passes (the %s/%d count of the text must match)
    local expected = {
        SI_DUNGEONEERSLEDGER_GROUP_COUNT = "%s %d", SI_DUNGEONEERSLEDGER_GROUP_PROGRESS = "%s %d %d",
        SI_DUNGEONEERSLEDGER_TT_COMPLETE = "%s", SI_DUNGEONEERSLEDGER_TT_INCOMPLETE = "%s", SI_DUNGEONEERSLEDGER_TT_TIER = "%s %s",
        SI_DUNGEONEERSLEDGER_TT_QUEST = "%s", SI_DUNGEONEERSLEDGER_TT_ALSO_ACTIVE = "%s", SI_DUNGEONEERSLEDGER_TT_BUTTON_TARGET = "%s",
        SI_DUNGEONEERSLEDGER_SUMMARY = "%s %s", SI_DUNGEONEERSLEDGER_SUMMARY_PART = "%s %d %d",
        SI_DUNGEONEERSLEDGER_MSG_NONE_AVAILABLE = "%s", SI_DUNGEONEERSLEDGER_MSG_SELECTED = "%d %s",
        SI_DUNGEONEERSLEDGER_MSG_SKIPPED = "%s %s", SI_DUNGEONEERSLEDGER_MSG_DESELECTED = "%d", SI_DUNGEONEERSLEDGER_MSG_SELECT_FAILED = "%s",
    }
    for id, text in pairs(definedStringIds()) do
        local specs = {}
        for spec in text:gmatch("%%[%a%%]") do if spec ~= "%%" then specs[#specs + 1] = spec end end
        local exp = expected[id]
        if exp == nil then exp = table.concat(specs, " ") end -- a string added later: only check that it formats
        if expected[id] ~= nil or #specs == 0 then eq(table.concat(specs, " "), exp, id .. " placeholders") end
        -- and a real format call must not error
        local args = {}
        for spec in exp:gmatch("%%?[%a]") do args[#args + 1] = (spec == "%d" or spec == "d") and 3 or "x" end
        local good, err = pcall(DL.L, w.store[id], unpack(args))
        ok(good, id .. ": " .. tostring(err))
    end
end)

test("strings: translation files only define known ids and keep placeholders; all load after en", function()
    local en = definedStringIds()
    for _, lang in ipairs({ "de", "es", "fr", "jp", "ru", "zh" }) do
        local src = read("lang/" .. lang .. ".lua")
        for id, text in stripComments(src):gmatch("(SI_DUNGEONEERSLEDGER_[%u%d_]+)%s*=%s*(%b\"\")") do
            ok(en[id], lang .. ": unknown string id " .. id)
            local a, b = {}, {}
            for s in en[id]:gmatch("%%[sd]") do a[#a + 1] = s end
            for s in text:gmatch("%%[sd]") do b[#b + 1] = s end
            eq(table.concat(b, ","), table.concat(a, ","), lang .. " " .. id .. " placeholders")
        end
        local w = Boot({ libsets = "none", language = lang })
        eq(w.store.GetString(w.store.SI_DUNGEONEERSLEDGER_BUTTON_SELECT) ~= "", true, lang .. " boots with strings")
    end
end)

---------------------------------------------------------------- globals
test("globals: only the documented globals are created by loading and starting the addon", function()
    local w = Boot({ libsets = "none" })
    local allowed = { DungeoneersLedger = true, DungeoneersLedger_SavedVariables = true,
        LibSets = true, LibAddonMenu2 = true, LIBSETS_TABLEKEY_DUNGEON_ZONE_MAPPING = true } -- installed by the harness
    local extra = {}
    for k in pairs(w.store) do
        if not w.baseline[k] and not allowed[k] and not k:match("^SI_DUNGEONEERSLEDGER_") then extra[#extra + 1] = k end
    end
    table.sort(extra)
    eq(#extra, 0, "undocumented globals: " .. table.concat(extra, ", "))
    for _, k in ipairs(w.createdOrder) do ok(allowed[k], "global created through assignment: " .. k) end
    ok(w.store.DungeoneersLedger_SavedVariables, "saved variables table not created")
    ok(w.store.SLASH_COMMANDS["/dledger"] and w.store.SLASH_COMMANDS["/dungeoneersledger"], "slash commands")
    eq(w.store.SLASH_COMMANDS["/dledger"], w.store.SLASH_COMMANDS["/dungeoneersledger"])
end)

test("globals: after full exercise still only the documented globals (settings, debug, events)", function()
    local w = Boot()
    w.DL.PrintDebug()
    w.store.SLASH_COMMANDS["/dledger"]("settings")
    w.store.SLASH_COMMANDS["/dledger"]("debug on")
    w:fire(w.store.EVENT_QUEST_ADDED); w:fire(w.store.EVENT_ACHIEVEMENT_UPDATED); w:advance(1000)
    for k in pairs(w.store) do
        if not w.baseline[k] then
            ok(k == "DungeoneersLedger" or k == "DungeoneersLedger_SavedVariables" or k == "LibSets" or k == "LibAddonMenu2"
                or k == "LIBSETS_TABLEKEY_DUNGEON_ZONE_MAPPING" or k:match("^SI_DUNGEONEERSLEDGER_"), "stray global " .. k)
        end
    end
end)

---------------------------------------------------------------- source greps
test("queue safety (static): the game's queue handler is referenced exactly once, inside SelectQuestDungeons", function()
    local hits = {}
    for _, rel in ipairs(addonLuaFiles()) do
        local code = stripComments(read(rel))
        for _, needle in ipairs({ "ZO_ActivityFinderTemplateQueueButtonKeyboard_OnClicked", "StartSearch", "joinQueueButton:Click", "ZO_ActivityFinderTemplateQueueButton" }) do
            local from = 1
            while true do
                local s = code:find(needle, from, true)
                if not s then break end
                hits[#hits + 1] = { rel = rel, needle = needle, pos = s, code = code }
                from = s + 1
            end
        end
    end
    local calls = {}
    for _, h in ipairs(hits) do if h.needle == "ZO_ActivityFinderTemplateQueueButtonKeyboard_OnClicked" then calls[#calls + 1] = h end end
    for _, h in ipairs(hits) do ok(h.needle ~= "StartSearch", "StartSearch must not be called by the addon: " .. h.rel) end
    eq(#calls, 1, "queue handler references")
    eq(calls[1].rel, "src/FinderPanel.lua")
    local code = calls[1].code
    local fnStart = code:find("local function SelectQuestDungeons", 1, true)
    local fnEnd = code:find("local function RunSelect", 1, true)
    ok(fnStart and fnEnd and calls[1].pos > fnStart and calls[1].pos < fnEnd, "queue call must be inside SelectQuestDungeons")
    -- guarded by the andQueue flag
    local segment = code:sub(fnStart, fnEnd)
    ok(segment:find("if andQueue and", 1, true), "queue call must be guarded by andQueue")
    -- SelectQuestDungeons is only reachable from the button handlers
    local callers = 0
    for _ in code:gmatch("RunSelect%(") do callers = callers + 1 end
    eq(callers, 2, "RunSelect: definition + the one button handler created by CreateButton")
    for _, rel in ipairs(srcFiles()) do
        if rel ~= "src/FinderPanel.lua" then ok(not stripComments(read(rel)):find("RunSelect", 1, true), rel .. " must not reach the select code") end
    end
end)

test("housekeeping: no print(), no io/os.execute, no debug library in the addon", function()
    for _, rel in ipairs(addonLuaFiles()) do
        local code = stripComments(read(rel))
        ok(not code:find("%f[%w_]print%s*%("), rel .. " uses print()")
        ok(not code:find("%f[%w_]io%."), rel .. " uses io")
        ok(not code:find("%f[%w_]debug%."), rel .. " uses debug")
        ok(not code:find("%f[%w_]require%s*%("), rel .. " uses require")
        ok(not code:find("%f[%w_]dofile"), rel .. " uses dofile")
    end
end)

test("housekeeping: no stray .bak/.orig/.tmp files in the addon folder", function()
    for _, full in ipairs(host.walk_files(CFG.addonRoot, nil)) do
        local rel = full:gsub("\\", "/")
        if not rel:find("/tests/", 1, true) and not rel:find("/.git/", 1, true) and not rel:find("/dist/", 1, true) then
            ok(not rel:match("%.bak%d*$") and not rel:match("%.orig$") and not rel:match("%.tmp$") and not rel:match("~$"), "stray file: " .. rel)
        end
    end
end)

test("XML: the template the code creates exists with the child the code reads, inheriting real game templates", function()
    local xml = World.parseXml(read("DungeoneersLedger.xml"))
    local templates = {}
    local function walk(n) for _, c in ipairs(n.children) do if c.attrs and c.attrs.name then templates[c.attrs.name] = c end walk(c) end end
    walk(xml)
    local t = templates.DungeoneersLedgerSearchTemplate
    ok(t and t.attrs.virtual == "true", "search template missing or not virtual")
    ok(templates["$(parent)Box"] and templates["$(parent)Box"].tag == "EditBox", "$(parent)Box edit box missing (code uses GetNamedChild('Box'))")
    -- every virtual template the Lua code creates is declared in the XML or is a known game template
    local known = { ZO_DefaultButton = true }
    for _, rel in ipairs(srcFiles()) do
        for tmpl in stripComments(read(rel)):gmatch('CreateControlFromVirtual%b()') do
            local name = tmpl:match('"[^"]+"%s*,%s*[%w_]+%s*,%s*"([^"]+)"') or tmpl:match(',%s*"([^"]+)"%s*%)$')
            if name then ok(templates[name] or known[name], rel .. ": unknown virtual template " .. name) end
        end
    end
    -- game templates referenced by inherits exist in the game source (when available)
    if CFG.esoSrc then
        local pool = {}
        for _, full in ipairs(host.walk_files(CFG.esoSrc, { ".xml" })) do pool[#pool + 1] = host.read(full) end
        local all = table.concat(pool, "\n")
        for _, n in pairs(templates) do
            if n.attrs.inherits then
                for inh in n.attrs.inherits:gmatch("[^,%s]+") do
                    if not templates[inh] then ok(all:find('name="' .. inh .. '"', 1, true), "game template not found: " .. inh) end
                end
            end
        end
        for name in pairs(known) do ok(all:find('name="' .. name .. '"', 1, true), "game template not found: " .. name) end
    end
end)
