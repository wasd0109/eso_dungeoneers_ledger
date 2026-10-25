-- Start-up, old-addon warning, hook failure, saved-variable migration, slash command, LibAddonMenu settings.
local function deepcopy(t)
    if type(t) ~= "table" then return t end
    local r = {}
    for k, v in pairs(t) do r[deepcopy(k)] = deepcopy(v) end
    return r
end

-- A realistic DungeonCompletion_SavedVariables as the old addon wrote it.
local function oldSavedVars()
    return {
        Default = {
            ["@Tester"] = {
                ["$AccountWide"] = {
                    version = 1,
                    showCompletion = false, showTiers = true, tierHardMode = true, tierSpeedRun = false, tierNoDeath = true, tierTrifecta = false,
                    showQuest = true, showAltQuests = false, pinQuest = true, skipCompletedOnSelect = true,
                    iconSize = 24, hideCompleted = true, groupBy = "dlc", sortBy = "name",
                    characterQuests = {
                        ["111"] = { name = "Alt One", dungeons = { [283] = "Fungal Grotto quest", [63] = "Darkshade quest" } },
                        ["222"] = { name = "Alt Two", dungeons = {} },
                        ["333"] = { dungeons = { [22] = "nameless record is dropped" } },
                        ["444"] = "corrupt",
                    },
                },
            },
            ["@OtherAccount"] = { ["$AccountWide"] = { iconSize = 31, groupBy = "completion" } },
        },
    }
end

test("migration: old settings are imported once into DungeoneersLedger_SavedVariables", function()
    local old = oldSavedVars()
    local w = Boot({ oldSavedVars = old })
    local s = w.DL.settings
    eq(s.showCompletion, false); eq(s.tierSpeedRun, false); eq(s.tierTrifecta, false); eq(s.showAltQuests, false)
    eq(s.pinQuest, true); eq(s.skipCompletedOnSelect, true); eq(s.iconSize, 24); eq(s.hideCompleted, true)
    eq(s.groupBy, "dlc"); eq(s.sortBy, "name")
    eq(s.selectVeteran, false, "new setting keeps its default")
    eq(s.importedFromDungeonCompletion, true)
    -- character records converted from { dungeons = { [zoneId] = questName } } to { quests = { { name, zones } } }
    local rec = s.characterQuests["111"]
    eq(rec.name, "Alt One")
    eq(#rec.quests, 2)
    local zones = {}
    for _, q in ipairs(rec.quests) do eq(#q.zones, 1); zones[q.zones[1]] = q.name end
    same(zones, { [283] = "Fungal Grotto quest", [63] = "Darkshade quest" })
    eq(#s.characterQuests["222"].quests, 0)
    eq(s.characterQuests["333"], nil, "records without a name are dropped")
    eq(s.characterQuests["444"], nil)
    -- the migrated record drives the alt tooltip
    same(w.DL.GetOtherCharactersWithQuest(Data.byName(w, "Fungal Grotto I", false)), { "Alt One" })
    same(w.DL.GetOtherCharactersWithQuest(Data.byName(w, "Darkshade Caverns I", true)), { "Alt One" })
    -- another account's data is not used
    ok(s.iconSize ~= 31)
end)

test("migration: runs once - later changes to the old table are ignored on the next load", function()
    local old = oldSavedVars()
    local w = Boot({ oldSavedVars = old })
    w.DL.settings.iconSize = 20
    local newSv = w.store.DungeoneersLedger_SavedVariables
    old.Default["@Tester"]["$AccountWide"].iconSize = 30
    old.Default["@Tester"]["$AccountWide"].groupBy = "completion"
    local w2 = Boot({ oldSavedVars = old, savedVars = newSv })
    eq(w2.DL.settings.iconSize, 20)
    eq(w2.DL.settings.groupBy, "dlc")
end)

test("migration: never mutates the old table (import, normal use, recording, events)", function()
    local old = oldSavedVars()
    local snapshot = deepcopy(old)
    local w = Boot({ oldSavedVars = old, characters = { { name = "Tester", id = "100" }, { name = "Alt One", id = "111" } } })
    w:addQuest({ name = "Pledge: Volenfell", kind = "pledge" })
    w.DL.RecordCurrentCharacter()
    w:fire(w.store.EVENT_QUEST_ADDED); w:advance(500)
    w.DL.settings.groupBy = "completion"
    w.DL.settings.characterQuests["111"].quests = nil
    same(old, snapshot, "old DungeonCompletion_SavedVariables changed")
    -- converted records are new tables, not aliases of the old ones
    ok(w.DL.settings.characterQuests["111"] ~= old.Default["@Tester"]["$AccountWide"].characterQuests["111"])
end)

test("migration: no old data / foreign data - defaults, flag set, nothing created in the old table", function()
    local w = Boot()
    eq(w.DL.settings.importedFromDungeonCompletion, true)
    for k, v in pairs(w.DL.DEFAULTS) do eq(w.DL.settings[k], v, k) end
    eq(w.store.DungeonCompletion_SavedVariables, nil, "must not create the old table")
    for _, garbage in ipairs({ "text", { Default = "x" }, { Default = { ["@Tester"] = "x" } }, { Default = { ["@Tester"] = { ["$AccountWide"] = "x" } } }, {} }) do
        local w2 = Boot({ oldSavedVars = garbage })
        eq(w2.DL.settings.iconSize, 18)
        eq(w2.DL.settings.importedFromDungeonCompletion, true)
    end
end)

test("migration: invalid imported values are repaired (groupBy/sortBy/characterQuests)", function()
    local old = oldSavedVars()
    local acc = old.Default["@Tester"]["$AccountWide"]
    acc.groupBy, acc.sortBy, acc.characterQuests = "bogus", "bogus", "bogus"
    local w = Boot({ oldSavedVars = old })
    eq(w.DL.settings.groupBy, "none"); eq(w.DL.settings.sortBy, "game"); eq(type(w.DL.settings.characterQuests), "table")
    -- and in the new saved variables on a later load
    w.DL.settings.groupBy = "x"; w.DL.settings.sortBy = "y"; w.DL.settings.characterQuests = 5
    local w2 = Boot({ savedVars = w.store.DungeoneersLedger_SavedVariables })
    eq(w2.DL.settings.groupBy, "none"); eq(w2.DL.settings.sortBy, "game"); eq(type(w2.DL.settings.characterQuests), "table")
end)

test("test_BUG_migration_old_groupBy_pledge_is_not_turned_into_pinQuest", function()
    -- The old addon (DungeonCompletion.lua:1194) converted its former groupBy == "pledge" into pinQuest = true on load.
    -- DL.LoadSettings/ImportOldSettings (src/Core.lua ImportOldSettings, ValidateSettings) copies "pledge" and then
    -- resets it to "none" without setting pinQuest, so a user whose old file still said "pledge" loses the pin.
    -- Suggested fix in ImportOldSettings: if saved.groupBy == "pledge" then saved.groupBy = DL.GROUP_NONE; saved.pinQuest = true end.
    local old = oldSavedVars()
    local acc = old.Default["@Tester"]["$AccountWide"]
    acc.groupBy, acc.pinQuest = "pledge", false
    local w = Boot({ oldSavedVars = old })
    eq(w.DL.settings.groupBy, "none")
    eq(w.DL.settings.pinQuest, true)
end)

test("old addon loaded: warns, installs NO hooks, creates no controls, events, slash commands or saved variables", function()
    local original = {}
    local old = oldSavedVars()
    local snapshot = deepcopy(old)
    local w = Boot({ oldAddon = true, oldSavedVars = old, setup = function(world)
        local tree, finder = world.finder.navigationTree, world.finder
        original = { AddNode = tree.AddNode, Commit = tree.Commit, Reset = tree.Reset, RefreshButtons = finder.RefreshButtons,
            entrySetup = tree.templateInfo["ZO_ActivityFinderTemplateNavigationEntry_Keyboard"].setupFunction,
            controls = world.stats.controlsCreated }
    end })
    local tree, finder = w.finder.navigationTree, w.finder
    ok(w:chatText():find("old DungeonCompletion addon is still enabled", 1, true), w:chatText())
    ok(tree.AddNode == original.AddNode and tree.Commit == original.Commit and tree.Reset == original.Reset, "tree hooked")
    eq(rawget(tree, "AddNode"), nil); eq(rawget(finder, "RefreshButtons"), nil)
    eq(tree.templateInfo["ZO_ActivityFinderTemplateNavigationEntry_Keyboard"].setupFunction, original.entrySetup)
    eq(w.stats.controlsCreated, original.controls, "controls created")
    eq(next(w.store.SLASH_COMMANDS), nil, "slash commands registered")
    for event, byNs in pairs(w.handlers) do eq(next(byNs), nil, "event " .. event .. " still registered") end
    eq(w.store.DungeoneersLedger_SavedVariables, nil)
    eq(w.DL.settings.iconSize, 18, "defaults only")
    same(old, snapshot)
    -- the finder keeps working unmodified
    w:refresh()
    eq(#w:snapshot()[1].entries, #w:locations(2))
    eq(#w.calls.QueueClick, 0)
end)

test("hook failure: finder or templates missing -> message, no events, no slash commands, no half-installed hooks", function()
    local w = Boot({ setup = function(world) world.store.DUNGEON_FINDER_KEYBOARD = nil end })
    ok(w:chatText():find("could not hook the Dungeon Finder", 1, true), w:chatText())
    eq(next(w.store.SLASH_COMMANDS), nil)
    for _, byNs in pairs(w.handlers) do eq(next(byNs), nil) end
    local w2 = Boot({ setup = function(world)
        world.finder.navigationTree.templateInfo["ZO_ActivityFinderTemplateNavigationEntry_Keyboard"] = nil
    end })
    ok(w2:chatText():find("could not hook", 1, true))
    eq(next(w2.store.SLASH_COMMANDS), nil)
    for _, byNs in pairs(w2.handlers) do eq(next(byNs), nil) end
end)

test("start-up: ignores other addons' EVENT_ADD_ON_LOADED, registers its events once, unregisters the load event", function()
    local w = Boot({ start = false })
    w:fire(w.store.EVENT_ADD_ON_LOADED, "SomeOtherAddon")
    eq(w.DL.settings.importedFromDungeonCompletion, nil, "must not start for another addon")
    w:fire(w.store.EVENT_ADD_ON_LOADED, "DungeoneersLedger")
    eq(w.handlers[w.store.EVENT_ADD_ON_LOADED].DungeoneersLedger, nil, "load event unregistered")
    for _, ev in ipairs({ "EVENT_ACHIEVEMENT_UPDATED", "EVENT_ACHIEVEMENTS_UPDATED", "EVENT_QUEST_ADDED", "EVENT_QUEST_REMOVED",
        "EVENT_QUEST_COMPLETE", "EVENT_QUEST_ADVANCED", "EVENT_PLAYER_ACTIVATED" }) do
        ok(w.handlers[w.store[ev]] and w.handlers[w.store[ev]].DungeoneersLedger, ev .. " not registered")
    end
    w:fire(w.store.EVENT_ADD_ON_LOADED, "DungeoneersLedger") -- a second load event must do nothing
    eq(#w.chat, 0)
end)

test("slash command: usage, debug on/off, debug dump, settings (LAM present and absent)", function()
    local w = Boot()
    local cmd = w.store.SLASH_COMMANDS["/dledger"]
    cmd("")
    ok(w:chatText():find("usage: /dledger settings | debug [on|off]", 1, true))
    cmd("DEBUG ON"); eq(w.DL.debugEnabled, true)
    cmd("debug off"); eq(w.DL.debugEnabled, false)
    local before = #w.chat
    cmd("debug")
    ok(#w.chat > before + 3)
    local text = w:chatText()
    ok(text:find("LibSets dungeon data: %d+ dungeon zones"), text)
    ok(text:find("rows by source: override=0 libsets=%d+ name=0 NONE=0"), text)
    cmd("settings"); eq(#w.lam.opened, 1); eq(w.lam.opened[1], w.DL.panel)
    local w2 = Boot({ lam = false })
    w2.store.SLASH_COMMANDS["/dungeoneersledger"]("settings")
    ok(w2:chatText():find("LibAddonMenu-2.0 addon, which is not loaded", 1, true), w2:chatText())
end)

test("debug: reported errors are kept and printed once when debug turns on", function()
    local w = Boot()
    w.DL.SafeCall("custom", function() error("kaboom") end)
    eq(#w.chat, 0, "nothing printed while debug is off")
    w.DL.SetDebug(true)
    ok(w:chatText():find("error in custom:", 1, true))
    local n = #w.chat
    w.DL.SafeCall("custom", function() error("again") end)
    eq(#w.chat, n, "same kind printed only once")
end)

-------------------------------------------------------------- LibAddonMenu settings
local function options(w)
    local list = w.lam.options["DungeoneersLedgerSettings"]
    ok(list, "options not registered")
    return list
end

test("settings menu: panel registered, every option has name/getFunc/setFunc/default consistent with DEFAULTS", function()
    local w = Boot()
    eq(w.lam.panels["DungeoneersLedgerSettings"].data.type, "panel")
    eq(w.lam.panels["DungeoneersLedgerSettings"].data.version, w.DL.version)
    local keys = {}
    for _, opt in ipairs(options(w)) do
        ok(({ checkbox = 1, dropdown = 1, slider = 1 })[opt.type], "unexpected option type " .. tostring(opt.type))
        ok(opt.name and opt.name ~= "", "option without a name")
        ok(type(opt.getFunc) == "function" and type(opt.setFunc) == "function")
        local current = opt.getFunc()
        eq(current, opt.default, opt.name .. ": default equals initial value")
        local found
        local before = {}
        for key in pairs(w.DL.DEFAULTS) do before[key] = w.DL.settings[key] end
        local probe = current
        if type(current) == "boolean" then probe = not current
        elseif type(current) == "number" then probe = current + 1
        elseif opt.choicesValues then probe = opt.choicesValues[2] end
        opt.setFunc(probe)
        for key in pairs(w.DL.DEFAULTS) do if w.DL.settings[key] ~= before[key] then found = key end end
        opt.setFunc(current)
        for key in pairs(w.DL.DEFAULTS) do eq(w.DL.settings[key], before[key], "setFunc(original) must restore " .. key) end
        if opt.tooltip ~= nil then ok(opt.tooltip ~= "") end
        if opt.type == "dropdown" then
            eq(#opt.choices, #opt.choicesValues)
            for i, v in ipairs(opt.choicesValues) do ok(opt.choices[i] ~= "", "choice text"); opt.setFunc(v); eq(opt.getFunc(), v) end
            opt.setFunc(opt.default)
        elseif opt.type == "slider" then
            ok(opt.min < opt.max and opt.default >= opt.min and opt.default <= opt.max and opt.step >= 1)
        end
        keys[#keys + 1] = found or "?"
    end
    -- the known settings each have an option
    local have = {}
    for _, k in ipairs(keys) do have[k] = true end
    for _, k in ipairs({ "showCompletion", "showTiers", "showQuest", "showAltQuests", "pinQuest", "skipCompletedOnSelect",
        "selectVeteran", "iconSize", "hideCompleted", "groupBy", "sortBy" }) do
        ok(have[k], "no settings option changes " .. k)
    end
end)

test("settings menu: option callbacks write the setting, persist it in the SavedVariables table and refresh the finder", function()
    local w = Boot()
    w:refresh()
    local raw = w.store.DungeoneersLedger_SavedVariables.Default["@Tester"]["$AccountWide"]
    for _, opt in ipairs(options(w)) do
        if opt.type == "checkbox" and opt.name:find("Hide completed", 1, true) then
            local before = w.stats.refreshViews
            opt.setFunc(true)
            eq(w.DL.settings.hideCompleted, true); eq(raw.hideCompleted, true, "not persisted in the raw saved table")
            ok(w.stats.refreshViews > before, "finder not refreshed")
            opt.setFunc(false)
        elseif opt.type == "dropdown" and opt.name:find("Group", 1, true) then
            opt.setFunc("dlc"); eq(raw.groupBy, "dlc")
            opt.setFunc("none")
        end
    end
end)

test("settings menu: tier marker toggles are greyed out while 'extra markers' is off", function()
    local w = Boot()
    local tier
    for _, opt in ipairs(options(w)) do
        if opt.disabled then
            tier = opt
            w.DL.settings.showTiers = true; eq(opt.disabled(), false)
            w.DL.settings.showTiers = false; eq(opt.disabled(), true)
        end
    end
    ok(tier, "no disabled-able option found")
end)

test("settings menu: Select/queue-related options exist and the veteran toggle does not trigger a list rebuild", function()
    local w = Boot()
    w:refresh()
    for _, opt in ipairs(options(w)) do
        if opt.name:find("veteran dungeons instead of normal", 1, true) then
            local before = w.stats.refreshViews
            opt.setFunc(true)
            eq(w.DL.settings.selectVeteran, true)
            eq(w.stats.refreshViews, before)
            return
        end
    end
    error("veteran toggle option not found")
end)
