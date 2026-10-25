-- Daily reset helper, "pledge done today" log, set collection progress.
local function rowFor(w, loc)
    for _, h in ipairs(w:snapshot()) do
        for _, child in ipairs(h.node.children or {}) do
            if child.data == loc then return child.control end
        end
        for _, g in ipairs(h.groups) do
            for _, child in ipairs(g.node.children or {}) do if child.data == loc then return child.control end end
        end
    end
end

local function icons(w, row)
    local n = row:GetName()
    local c = w.controlsByName
    return { status = c[n .. "DLStatus"], quest = c[n .. "DLQuest"] }
end

local DAY = 86400
local PLEDGE = "Pledge: Volenfell"

-- Accepts the pledge (so the journal read remembers it), then turns it in.
local function completePledge(w, event)
    w:addQuest({ name = PLEDGE, kind = "pledge" })
    w.DL.InvalidateQuests()
    w.DL.GetActiveQuests()
    w.journal = {}
    w.DL.InvalidateQuests()
    if event == "removed" then
        w:fire(w.store.EVENT_QUEST_REMOVED, true, 1, PLEDGE, 0, 0, 1)
    else
        w:fire(w.store.EVENT_QUEST_COMPLETE, PLEDGE, 50, 0, 0, 0, w.store.QUEST_TYPE_UNDAUNTED_PLEDGE)
    end
end

local function history(w) return w.DL.settings.pledgeHistory end

---------------------------------------------------------------- daily reset
test("daily reset: last reset is the most recent 10:00 UTC (19:00 JST) at or before now", function()
    local w = Boot({ libsets = "none", locations = false, achievements = false })
    local DL = w.DL
    local reset = 1699956000 -- 2023-11-14 10:00:00 UTC
    eq(DL.GetLastDailyReset(1700000000), reset)
    eq(DL.GetLastDailyReset(reset), reset, "exactly at the reset")
    eq(DL.GetLastDailyReset(reset - 1), reset - DAY, "one second before the reset")
    eq(DL.GetLastDailyReset(reset + DAY - 1), reset)
    eq(DL.GetLastDailyReset(reset + DAY), reset + DAY)
    w.now = reset + 100
    eq(DL.GetLastDailyReset(), reset, "defaults to the game clock")
end)

---------------------------------------------------------------- pledge log
test("pledges: a turned-in pledge is recorded once with its dungeon zones, whichever event comes first", function()
    for _, event in ipairs({ "complete", "removed" }) do
        local w = Boot({ characters = { { name = "Tester", id = "100" } } })
        completePledge(w, event)
        local record = history(w)["100"]
        ok(record, "no record after " .. event)
        eq(#record.entries, 1)
        eq(record.entries[1].quest, PLEDGE)
        ok(record.entries[1].zones[1] == Data.dungeonByName(w, "Volenfell").zoneId, "zone of the matched dungeon")
        eq(record.entries[1].at, 1700000000)
        w:fire(w.store.EVENT_QUEST_REMOVED, true, 1, PLEDGE, 0, 0, 1) -- the second event of the same turn-in
        w:fire(w.store.EVENT_QUEST_COMPLETE, PLEDGE, 50, 0, 0, 0, w.store.QUEST_TYPE_UNDAUNTED_PLEDGE)
        eq(#history(w)["100"].entries, 1, "duplicate events within a minute are ignored")
    end
end)

test("pledges: quests that are not known pledges, or abandoned ones, are not recorded; the setting turns it off", function()
    local w = Boot()
    w:addQuest({ name = "Some errand", kind = "other" })
    w.DL.InvalidateQuests(); w.DL.GetActiveQuests()
    w:fire(w.store.EVENT_QUEST_COMPLETE, "Some errand", 1, 0, 0, 0, 0)
    w:fire(w.store.EVENT_QUEST_REMOVED, false, 1, "Some errand", 0, 0, 1)
    eq(next(history(w) or {}), nil, "nothing recorded")
    local w2 = Boot()
    w2:addQuest({ name = PLEDGE, kind = "pledge" })
    w2.DL.InvalidateQuests(); w2.DL.GetActiveQuests()
    w2:fire(w2.store.EVENT_QUEST_REMOVED, false, 1, PLEDGE, 0, 0, 1) -- abandoned
    eq(next(history(w2) or {}), nil, "abandoned pledge is not a completion")
    local w3 = Boot()
    w3:set("rememberPledges", false)
    completePledge(w3)
    eq(next(history(w3) or {}), nil, "setting off records nothing")
end)

test("pledges: the quest marker says 'Pledge completed today' until the next daily reset", function()
    local w = Boot({ characters = { { name = "Tester", id = "100" } } })
    w.now = 1700000000
    completePledge(w)
    w:refresh()
    local loc = Data.byName(w, "Volenfell", false)
    local q = icons(w, rowFor(w, loc)).quest
    ok(not q:IsHidden(), "marker shown for today's completion")
    eq(q.tooltipText, "Pledge completed today (" .. history(w)["100"].name .. ")")
    -- with an active quest the lines combine
    w:addQuest({ name = "Volenfell trouble", kind = "dungeon", zoneId = Data.dungeonByName(w, "Volenfell").zoneId })
    w.DL.InvalidateQuests(); w.DL.RefreshVisibleRows()
    ok(q.tooltipText:find("Quest: Volenfell trouble", 1, true) and q.tooltipText:find("Pledge completed today", 1, true))
    w.journal = {}; w.DL.InvalidateQuests()
    -- the next reset passes: the old record no longer marks the dungeon
    w.now = w.DL.GetLastDailyReset(1700000000) + DAY + 1
    w.DL.RefreshVisibleRows()
    ok(q:IsHidden(), "an old record must not show the marker")
    w.now = 1700000000
    w:set("rememberPledges", false); w.DL.RefreshVisibleRows()
    ok(q:IsHidden(), "setting off hides it")
    w:set("rememberPledges", true); w:set("showQuest", false); w.DL.RefreshVisibleRows()
    ok(q:IsHidden(), "quest marker setting off hides it")
end)

test("pledges: another character's completion today is listed, other dungeons are untouched", function()
    local w = Boot({ characters = { { name = "Tester", id = "100" }, { name = "Alt", id = "200" } } })
    w.now = 1700000000
    local d = Data.dungeonByName(w, "Volenfell")
    w.DL.settings.pledgeHistory = { ["200"] = { name = "Alt", entries = { { quest = PLEDGE, zones = { d.zoneId }, at = w.now - 60 } } } }
    eq(table.concat(w.DL.GetPledgesDoneToday(Data.byName(w, "Volenfell", true)), ","), "Alt")
    eq(w.DL.GetPledgesDoneToday(Data.byName(w, "Arx Corinium", false)), nil)
end)

test("pledges: entries older than 8 days are pruned, along with characters left empty; bad data is repaired", function()
    local w = Boot()
    local now = 1700000000
    w.DL.settings.pledgeHistory = {
        ["100"] = { name = "Tester", entries = { { quest = "old", zones = { 1 }, at = now - 9 * DAY }, { quest = "new", zones = { 1 }, at = now - DAY } } },
        ["200"] = { name = "Alt", entries = { { quest = "old", zones = { 1 }, at = now - 30 * DAY } } },
        ["300"] = "garbage",
    }
    w.DL.PrunePledgeHistory(now)
    local store = history(w)
    eq(#store["100"].entries, 1); eq(store["100"].entries[1].quest, "new")
    eq(store["200"], nil); eq(store["300"], nil)
    w.DL.settings.pledgeHistory = "broken"
    w.DL.PrunePledgeHistory(now)
    eq(type(history(w)), "table")
    eq(w.DL.GetPledgesDoneToday(Data.byName(w, "Volenfell", false)), nil)
end)

---------------------------------------------------------------- set collection progress
local function installProgress(w, fn)
    w.store.LibSets.GetNumItemSetCollectionZoneUnlockedPieces = fn
end

test("set progress: LibSets result is cached per zone and dropped on collection update events", function()
    local w = Boot()
    local calls = 0
    installProgress(w, function(zoneId) calls = calls + 1; return 12, 30 end)
    local u, t = w.DL.GetSetCollectionProgress(148)
    eq(u, 12); eq(t, 30)
    w.DL.GetSetCollectionProgress(148)
    eq(calls, 1, "second lookup comes from the cache")
    installProgress(w, function() calls = calls + 1; return 13, 30 end)
    w:fire(w.store.EVENT_ITEM_SET_COLLECTION_UPDATED, 1, 0)
    eq(select(1, w.DL.GetSetCollectionProgress(148)), 13, "cache dropped by the update event")
    w:fire(w.store.EVENT_ITEM_SET_COLLECTIONS_UPDATED)
    eq(calls, 2)
    eq(w.DL.GetSetCollectionProgress(nil), nil)
end)

test("set progress: zones without sets, nil results, errors and a not-ready LibSets give no line and never raise", function()
    local w = Boot()
    installProgress(w, function() return nil, nil end)
    eq(w.DL.GetSetCollectionProgress(148), nil)
    installProgress(w, function() return 0, 0 end)
    eq(w.DL.GetSetCollectionProgress(149), nil)
    installProgress(w, function() error("collections not ready") end)
    eq(w.DL.GetSetCollectionProgress(150), nil)
    w.store.LibSets.GetNumItemSetCollectionZoneUnlockedPieces = nil
    eq(w.DL.GetSetCollectionProgress(151), nil, "older LibSets without the function")
    local w2 = Boot()
    installProgress(w2, function() return 5, 10 end)
    w2.store.LibSets.fullyLoaded = false
    eq(w2.DL.GetSetCollectionProgress(148), nil, "LibSets not loaded")
    w2.store.LibSets.fullyLoaded = true
    eq(w2.DL.GetSetCollectionProgress(148), 5, "and it is not cached as 'no sets'")
end)

test("set progress: shown as a line in the completion tooltip, switchable", function()
    local w = Boot()
    local d = Data.dungeonByName(w, "Volenfell")
    installProgress(w, function(zoneId) if zoneId == d.zoneId then return 12, 30 end end)
    w:refresh()
    local st = icons(w, rowFor(w, Data.byName(w, "Volenfell", false))).status
    ok(st.tooltipText:find("Set pieces collected: 12 / 30", 1, true), st.tooltipText)
    local other = icons(w, rowFor(w, Data.byName(w, "Arx Corinium", false))).status
    ok(not other.tooltipText:find("Set pieces", 1, true), "no line for a zone without sets")
    w:set("showSetProgress", false); w.DL.RefreshVisibleRows()
    ok(not st.tooltipText:find("Set pieces", 1, true), "setting off")
end)
