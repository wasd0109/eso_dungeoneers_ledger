-- Runs last: every game API name the addon actually touched (globals read at run time by all previous tests, plus
-- control method names called in the code) must exist in the game's own documentation/source. Needs ESO_UI_SRC.
local cache

local function gameText()
    if cache then return cache end
    local docs = host.read(World.joinPath(CFG.esoSrc, "ESOUIDocumentation.txt")) or host.read(World.joinPath(CFG.esoSrc, "../ESOUIDocumentation.txt")) or ""
    local parts = {}
    for _, full in ipairs(host.walk_files(CFG.esoSrc, { ".lua", ".xml" })) do parts[#parts + 1] = host.read(full) or "" end
    cache = { docs = docs, source = table.concat(parts, "\n") }
    return cache
end

local function hasWord(text, name)
    local from = 1
    while true do
        local s, e = text:find(name, from, true)
        if not s then return false end
        local before, after = text:sub(s - 1, s - 1), text:sub(e + 1, e + 1)
        if not before:match("[%w_]") and not after:match("[%w_]") then return true end
        from = e + 1
    end
end

local LUA_STD = {}
for _, n in ipairs({ "assert", "error", "ipairs", "pairs", "next", "pcall", "xpcall", "select", "tonumber", "tostring", "type", "unpack",
    "setmetatable", "getmetatable", "rawget", "rawset", "rawequal", "loadstring", "collectgarbage", "string", "table", "math", "os", "_G" }) do LUA_STD[n] = true end

local OWN = { DungeoneersLedger = true, DungeonCompletion = true, DungeoneersLedger_SavedVariables = true,
    DungeonCompletion_SavedVariables = true, LibSets = true, LibAddonMenu2 = true }

test("API: every global the addon read while the suite ran exists in the game's documentation or source", function()
    if not CFG.esoSrc then skip("ESO_UI_SRC (extracted esoui source) not set; API-name checks skipped") end
    local names = {}
    for _, w in ipairs(AllWorlds) do for k in pairs(w.reads) do names[k] = true end end
    local checked, missing = 0, {}
    local text = gameText()
    for name in pairs(names) do
        if not LUA_STD[name] and not OWN[name] and not name:match("^SI_DUNGEONEERSLEDGER_") and not name:match("^LIBSETS_") then
            checked = checked + 1
            if not hasWord(text.docs, name) and not hasWord(text.source, name) then missing[#missing + 1] = name end
        end
    end
    table.sort(missing)
    ok(checked > 60, "suspiciously few globals recorded: " .. checked)
    eq(#missing, 0, "not found in the game API/source (typo or missing stub?): " .. table.concat(missing, ", "))
end)

test("API: every control/object method the addon calls with :Name() exists in the game docs/source or is the addon's own", function()
    if not CFG.esoSrc then skip("ESO_UI_SRC (extracted esoui source) not set; API-name checks skipped") end
    local own, used = {}, {}
    local files = {}
    for _, full in ipairs(host.walk_files(CFG.addonRoot, { ".lua" })) do
        local rel = full:gsub("\\", "/")
        if rel:find("/src/", 1, true) then files[#files + 1] = host.read(full) end
    end
    for _, src in ipairs(files) do
        src = src:gsub("%-%-[^\n]*", "")
        for name in src:gmatch("function%s+[%w_%.]+[:%.]([%a_][%w_]*)") do own[name] = true end
        for name in src:gmatch(":(%u[%w_]*)%s*%(") do used[name] = true end
    end
    local text = gameText()
    local missing = {}
    -- LibAddonMenu-2.0 methods (a third-party library, not part of the game)
    own.RegisterAddonPanel, own.RegisterOptionControls, own.OpenToPanel = true, true, true
    for name in pairs(used) do
        if not own[name] and not hasWord(text.docs, name) and not hasWord(text.source, name) then missing[#missing + 1] = name end
    end
    table.sort(missing)
    eq(#missing, 0, "methods not found in the game API: " .. table.concat(missing, ", "))
    -- control methods the stub did not implement (called as no-ops) must also be real
    local unknown = {}
    for _, w in ipairs(AllWorlds) do for name in pairs(w.unknownMethods) do unknown[name] = true end end
    for name in pairs(unknown) do
        ok(hasWord(text.docs, name) or hasWord(text.source, name), "stub no-op for a method that does not exist in the game: " .. name)
    end
end)

test("API: summary of what the stub layer left as no-ops (informational, must stay small)", function()
    local unknown = {}
    for _, w in ipairs(AllWorlds) do for name in pairs(w.unknownMethods) do unknown[name] = true end end
    local list = {}
    for name in pairs(unknown) do list[#list + 1] = name end
    table.sort(list)
    ok(#list < 20, "many unstubbed control methods: " .. table.concat(list, ", "))
end)
