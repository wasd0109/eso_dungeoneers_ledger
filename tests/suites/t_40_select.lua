-- "Select quest dungeons" / "Select and queue": which entries are picked, never mixing difficulties, never queueing
-- from anywhere but the button click.
local QUEST_DUNGEONS = { "Fungal Grotto I", "Spindleclutch II", "Bal Sunnar", "Imperial City Prison", "Wayrest Sewers I" }

local function setup(opts)
    opts = opts or {}
    local w = Boot(opts)
    for _, name in ipairs(opts.questDungeons or QUEST_DUNGEONS) do
        w:addQuest({ name = "Quest for " .. name, kind = "dungeon", zoneId = Data.dungeonByName(w, name).zoneId })
    end
    w.DL.InvalidateQuests()
    w:refresh() -- builds the rows like opening the finder
    w.selectBtn = w.controlsByName["DungeoneersLedgerSelectButton"]
    w.queueBtn = w.controlsByName["DungeoneersLedgerQueueButton"]
    return w
end

local function selectedIds(w)
    local ids = {}
    for _, loc in ipairs(w:allSpecific()) do if loc:IsSelected() then ids[#ids + 1] = loc:GetId() end end
    table.sort(ids)
    return ids
end

local function idsFor(w, names, veteran)
    local ids = {}
    for _, n in ipairs(names) do
        local d = Data.dungeonByName(w, n)
        ids[#ids + 1] = veteran and d.vetFinder or d.normalFinder
    end
    table.sort(ids)
    return ids
end

test("select: normal difficulty picks exactly the quest dungeons' NORMAL entries", function()
    local w = setup()
    w.selectBtn:Click()
    same(selectedIds(w), idsFor(w, QUEST_DUNGEONS, false))
    eq(w.manager.numSelected, #QUEST_DUNGEONS)
    ok(w:chatText():find("selected 5 Normal dungeon(s) with a quest.", 1, true), w:chatText())
    eq(#w.calls.QueueClick, 0)
end)

test("select: the veteran toggle picks only VETERAN entries, whatever difficulty the finder shows", function()
    for _, finderDifficulty in ipairs({ 1, 2 }) do
        local w = setup()
        w.DL.settings.selectVeteran = true
        w.state.difficulty = finderDifficulty
        w.selectBtn:Click()
        same(selectedIds(w), idsFor(w, QUEST_DUNGEONS, true), "finder difficulty " .. finderDifficulty)
        for _, loc in ipairs(w:allSpecific()) do if loc:IsSelected() then eq(loc:GetActivityType(), 3) end end
    end
end)

test("select: toggle off follows the finder's current difficulty (veteran finder -> veteran entries, normal -> normal)", function()
    local w = setup()
    w.state.difficulty = 2
    w.selectBtn:Click()
    same(selectedIds(w), idsFor(w, QUEST_DUNGEONS, true))
    local w2 = setup()
    w2.state.difficulty = 1
    w2.selectBtn:Click()
    same(selectedIds(w2), idsFor(w2, QUEST_DUNGEONS, false))
end)

test("select: difficulties are never mixed - a previous selection of the other difficulty is replaced, not extended", function()
    local w = setup()
    -- the user had ticked two veteran dungeons and one normal one by hand
    w.manager:SetLocationSelected(Data.byName(w, "Arx Corinium", true), true)
    w.manager:SetLocationSelected(Data.byName(w, "Volenfell", true), true)
    w.manager:SetLocationSelected(Data.byName(w, "Volenfell", false), true)
    w.selectBtn:Click() -- normal
    same(selectedIds(w), idsFor(w, QUEST_DUNGEONS, false))
    w.DL.settings.selectVeteran = true
    w.selectBtn:Click()
    same(selectedIds(w), idsFor(w, QUEST_DUNGEONS, true))
    eq(w.manager.numSelected, #QUEST_DUNGEONS, "manager's selection count must match")
end)

test("select: quest in another dungeon's pledge text selects it too (pledge detection by name)", function()
    local w = setup({ questDungeons = {} })
    w:addQuest({ name = "Undaunted pledge", kind = "pledge", conditions = { "Defeat the boss in Fungal Grotto II" } })
    w.DL.InvalidateQuests()
    w.selectBtn:Click()
    same(selectedIds(w), idsFor(w, { "Fungal Grotto II" }, false))
end)

test("select: locked and inactive quest dungeons are skipped and reported, others still selected", function()
    local w = setup()
    Data.byName(w, "Bal Sunnar", false):SetLocked(true)
    Data.byName(w, "Wayrest Sewers I", false):SetActive(false)
    w:refresh()
    w.selectBtn:Click()
    same(selectedIds(w), idsFor(w, { "Fungal Grotto I", "Spindleclutch II", "Imperial City Prison" }, false))
    local chat = w:chatText()
    ok(chat:find("skipped quest dungeons that are locked or unavailable as Normal: ", 1, true), chat)
    ok(chat:find("Bal Sunnar", 1, true), "locked dungeon not named")
    ok(not chat:find("Fungal Grotto I,", 1, true))
end)

test("select: veteran mode reports quest dungeons that have no veteran version, never selects a normal entry for them", function()
    local d = Data.dungeons()
    local specs = Data.locationSpecs({ d[1], d[2] })
    -- d[3] exists as a NORMAL entry only
    specs[#specs + 1] = { id = 4001, activityType = 2, name = "Normal Only Dungeon", zoneId = 424242, sortOrder = 99 }
    local w = Boot({ locations = specs })
    for _, dd in ipairs({ d[1], d[2] }) do w:addQuest({ name = "Q " .. dd.name, kind = "dungeon", zoneId = dd.zoneId }) end
    w:addQuest({ name = "Q normal only", kind = "dungeon", zoneId = 424242 })
    w.DL.InvalidateQuests()
    w:refresh()
    w.DL.settings.selectVeteran = true
    w.controlsByName["DungeoneersLedgerSelectButton"]:Click()
    local ids = selectedIds(w)
    same(ids, (function() local t = { d[1].vetFinder, d[2].vetFinder } table.sort(t) return t end)())
    ok(w:chatText():find("skipped quest dungeons that are locked or unavailable as Veteran: Normal Only Dungeon", 1, true), w:chatText())
    ok(not Data.byName(w, "Normal Only Dungeon", false):IsSelected())
end)

test("select: never selects dungeons hidden by the search box or hide-completed", function()
    local w = setup()
    w.DL.SetSearchText("grotto") -- only Fungal Grotto I of the quest dungeons is visible
    w:refresh()
    w.selectBtn:Click()
    same(selectedIds(w), idsFor(w, { "Fungal Grotto I" }, false))
    local w2 = setup()
    -- complete the NORMAL achievements of two quest dungeons and hide completed
    for _, n in ipairs({ "Bal Sunnar", "Spindleclutch II" }) do w2:setAchievementState(Data.dungeonByName(w2, n).normalAch, true) end
    w2.DL.settings.hideCompleted = true
    w2:refresh()
    w2.selectBtn:Click()
    same(selectedIds(w2), idsFor(w2, { "Fungal Grotto I", "Imperial City Prison", "Wayrest Sewers I" }, false))
end)

test("select: skipCompletedOnSelect leaves completed dungeons out (difficulty-specific achievement)", function()
    local w = setup()
    w.DL.settings.skipCompletedOnSelect = true
    w:setAchievementState(Data.dungeonByName(w, "Bal Sunnar").normalAch, true)
    w:setAchievementState(Data.dungeonByName(w, "Volenfell").normalAch, true)
    w.selectBtn:Click()
    same(selectedIds(w), idsFor(w, { "Fungal Grotto I", "Spindleclutch II", "Imperial City Prison", "Wayrest Sewers I" }, false))
    -- a completed VETERAN achievement does not exclude the normal entry, and vice versa
    local w2 = setup()
    w2.DL.settings.skipCompletedOnSelect = true
    w2:setAchievementState(Data.dungeonByName(w2, "Bal Sunnar").vetAch, true)
    w2.selectBtn:Click()
    same(selectedIds(w2), idsFor(w2, QUEST_DUNGEONS, false))
end)

test("select: with nothing to select the user's own selection is kept (no quests / all filtered / all locked)", function()
    local scenarios = {
        function(w) end, -- no quests at all handled by questDungeons = {} below
    }
    local function userTicks(w)
        w.manager:SetLocationSelected(Data.byName(w, "Arx Corinium", false), true)
        w.manager:SetLocationSelected(Data.byName(w, "Volenfell", true), true)
    end
    -- 1. no quests
    local w = setup({ questDungeons = {} })
    userTicks(w)
    local before = selectedIds(w)
    w.selectBtn:Click(); w.queueBtn:Click()
    same(selectedIds(w), before, "no quests")
    ok(w:chatText():find("no available Normal dungeons with a quest", 1, true), w:chatText())
    eq(#w.calls.QueueClick, 0, "Select and queue with nothing selected must not queue")
    -- 2. all quest dungeons filtered by search
    local w2 = setup()
    userTicks(w2)
    local before2 = selectedIds(w2)
    w2.DL.SetSearchText("arx corinium")
    -- the search hides everything but Arx Corinium: user ticks of hidden ones are dropped by the rebuild, Arx stays
    w2:refresh()
    local keep = selectedIds(w2)
    w2.selectBtn:Click()
    same(selectedIds(w2), keep, "filtered")
    -- 3. all locked
    local w3 = setup()
    for _, n in ipairs(QUEST_DUNGEONS) do Data.byName(w3, n, false):SetLocked(true) end
    w3:refresh()
    userTicks(w3)
    local before3 = selectedIds(w3)
    w3.selectBtn:Click()
    same(selectedIds(w3), before3, "all locked")
    eq(#w3.calls.QueueClick + #w2.calls.QueueClick + #w3.calls.StartSearch, 0)
end)

test("select-and-queue: queue handler is called exactly once, only from the button click, after ticking the quest dungeons", function()
    local w = setup()
    w.queueBtn:Click()
    eq(#w.calls.QueueClick, 1)
    eq(w.calls.QueueClick[1].context, "DungeoneersLedgerQueueButton")
    eq(#w.calls.StartSearch, 1)
    same((function() local t = {} for _, l in ipairs(w.calls.StartSearch[1].selected) do t[#t + 1] = l:GetId() end table.sort(t) return t end)(),
        idsFor(w, QUEST_DUNGEONS, false), "queued set")
    for _, l in ipairs(w.calls.StartSearch[1].selected) do eq(l:GetActivityType(), 2, "queue must not contain veteran entries") end
end)

test("select-and-queue with the veteran toggle queues only veteran entries", function()
    local w = setup()
    w.DL.settings.selectVeteran = true
    w.queueBtn:Click()
    eq(#w.calls.StartSearch, 1)
    for _, l in ipairs(w.calls.StartSearch[1].selected) do eq(l:GetActivityType(), 3) end
    eq(#w.calls.StartSearch[1].selected, #QUEST_DUNGEONS)
end)

test("select only: pressing 'Select quest dungeons' never queues", function()
    local w = setup()
    w.selectBtn:Click()
    eq(#w.calls.QueueClick, 0); eq(#w.calls.StartSearch, 0)
end)

test("queue safety (dynamic): no code path other than the Select-and-queue click ever reaches the queue handler", function()
    local w = setup()
    local DL = w.DL
    local S = w.store
    -- quest + achievement events, debounce timers, refreshes
    for _, ev in ipairs({ "EVENT_QUEST_ADDED", "EVENT_QUEST_REMOVED", "EVENT_QUEST_COMPLETE", "EVENT_QUEST_ADVANCED", "EVENT_PLAYER_ACTIVATED",
        "EVENT_ACHIEVEMENT_UPDATED", "EVENT_ACHIEVEMENTS_UPDATED" }) do
        w:fire(S[ev], 1, 2, 3)
    end
    w:advance(1000)
    -- all settings through the real LAM option callbacks, with the finder showing
    for _, options in pairs(w.lam.options) do
        for _, opt in ipairs(options) do
            if opt.setFunc then
                local current = opt.getFunc()
                if type(current) == "boolean" then opt.setFunc(not current); opt.setFunc(current)
                elseif opt.choicesValues then for _, v in ipairs(opt.choicesValues) do opt.setFunc(v) end opt.setFunc(current)
                elseif type(current) == "number" then opt.setFunc(opt.min); opt.setFunc(opt.max); opt.setFunc(current) end
            end
        end
    end
    -- search box typing, slash commands, row clicks, queue-state changes, finder button refreshes
    local box = w.controlsByName["DungeoneersLedgerSearchBox"]
    box:SetText("grotto"); box:Fire("OnTextChanged"); w:advance(500)
    box:SetText(""); box:Fire("OnTextChanged"); w:advance(500)
    for _, cmd in ipairs({ "", "settings", "debug", "debug on", "debug off", "nonsense" }) do S.SLASH_COMMANDS["/dledger"](cmd) end
    for _, h in ipairs(w:snapshot()) do
        local row = h.entries[1] and w.tree.rootNode.children[1].children[1].control
        if row then row:Fire("OnMouseUp", 1, true) end
    end
    for _, ctl in pairs(w.controlsByName) do
        if ctl.__handlers.OnMouseUp then ctl:Fire("OnMouseUp", 1, true) end
        if ctl.__handlers.OnMouseEnter then ctl:Fire("OnMouseEnter") end
        if ctl.__handlers.OnMouseExit then ctl:Fire("OnMouseExit") end
    end
    w.manager.activityFinderStatus = 1; w.finder:RefreshButtons(); w.manager.activityFinderStatus = 0; w.finder:RefreshButtons()
    w.DL.PrintDebug()
    w:refresh()
    w.selectBtn:Click()
    eq(#w.calls.QueueClick, 0, "queue handler reached from a non-queue path")
    eq(#w.calls.StartSearch, 0)
    -- and the one legitimate path still works
    w.queueBtn:Click()
    eq(#w.calls.QueueClick, 1)
    eq(w.calls.QueueClick[1].context, "DungeoneersLedgerQueueButton")
end)

test("select: blocked states leave everything alone and explain why (queued, searching, group finder, not leader)", function()
    local cases = {
        { "already queued or searching", function(w) w.manager.activityFinderStatus = 1 end },
        { "already queued or searching", function(w) w.state.searching = true end },
        { "Group Finder is in use", function(w) w.state.groupFinderInUse = true end },
        { "only the group leader", function(w) w.manager.playerIsGrouped = true; w.manager.playerIsLeader = false end },
    }
    for _, case in ipairs(cases) do
        local w = setup()
        w.manager:SetLocationSelected(Data.byName(w, "Arx Corinium", false), true)
        local before = selectedIds(w)
        case[2](w)
        w.selectBtn:Click(); w.queueBtn:Click()
        same(selectedIds(w), before, case[1])
        ok(w:chatText():find(case[1], 1, true), case[1] .. " message missing: " .. w:chatText())
        eq(#w.calls.QueueClick, 0)
    end
end)

test("select: buttons follow the join-queue button (hidden with the list, disabled while queued), tooltip names the target difficulty", function()
    local w = setup()
    w.finder.joinQueueButton:SetHidden(false)
    w.finder:RefreshButtons()
    ok(not w.selectBtn:IsHidden() and not w.queueBtn:IsHidden())
    ok(w.selectBtn:IsEnabled() and w.queueBtn:IsEnabled())
    w.manager.activityFinderStatus = 1
    w.finder:RefreshButtons()
    ok(not w.selectBtn:IsEnabled() and not w.queueBtn:IsEnabled(), "disabled while queued")
    eq(w.selectBtn:Click(), false)
    w.manager.activityFinderStatus = 0
    w.finder.listSection:SetHidden(true)
    w.finder:RefreshButtons()
    ok(w.selectBtn:IsHidden() and w.queueBtn:IsHidden(), "hidden when the list is not shown")
    w.finder.listSection:SetHidden(false)
    w.finder:RefreshButtons()
    w.selectBtn:Fire("OnMouseEnter")
    eq(w.tooltip, "Targets: Normal dungeons")
    w.DL.settings.selectVeteran = true
    w.selectBtn:Fire("OnMouseEnter")
    eq(w.tooltip, "Targets: Veteran dungeons")
    w.selectBtn:Fire("OnMouseExit")
    eq(w.tooltip, nil)
end)

test("select: rows' checkboxes are synchronised with the code-made selection", function()
    local w = setup()
    w.selectBtn:Click()
    local checked = 0
    for _, h in ipairs(w:snapshot()) do
        for _, child in ipairs(h.node.children or {}) do
            local loc = child.data
            eq(child.control.check.__checked == true, loc:IsSelected() == true, loc:GetRawName())
            if child.control.check.__checked then checked = checked + 1 end
        end
    end
    eq(checked, #QUEST_DUNGEONS)
end)

test("select: a dungeon hidden by search/hide-completed loses its tick on rebuild (so Join Queue cannot queue it) and says so", function()
    local w = setup()
    w.manager:SetLocationSelected(Data.byName(w, "Arx Corinium", false), true)
    w.manager:SetLocationSelected(Data.byName(w, "Volenfell", false), true)
    w.DL.SetSearchText("volenfell")
    w:refresh()
    ok(not Data.byName(w, "Arx Corinium", false):IsSelected(), "hidden dungeon must be deselected")
    ok(Data.byName(w, "Volenfell", false):IsSelected(), "visible dungeon stays ticked")
    eq(w.manager.numSelected, 1)
    ok(w:chatText():find("deselected 1 dungeon(s) hidden by the list filter", 1, true), w:chatText())
end)

test("select: errors inside the select code are caught, reported, and do not wipe the user's selection", function()
    local w = setup()
    w.manager:SetLocationSelected(Data.byName(w, "Arx Corinium", false), true)
    local before = selectedIds(w)
    w.store.GetJournalQuestNumSteps = function() error("journal exploded") end
    w.DL.InvalidateQuests()
    w.selectBtn:Click()
    same(selectedIds(w), before)
    ok(w:chatText():find("could not select quest dungeons", 1, true), w:chatText())
end)
