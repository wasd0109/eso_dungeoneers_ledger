-- Quest detection and the per-character quest records in SavedVariables.
local function chars(...)
    local list = {}
    for i, c in ipairs({ ... }) do list[i] = { name = c[1], id = c[2] } end
    return list
end

local function store(w) return w.DL.settings.characterQuests end

test("quests: related quest by zone, by dungeon name in title or objectives; pledge wins over other quests", function()
    local w = Boot()
    local fg1 = Data.byName(w, "Fungal Grotto I", false)
    local dFG1 = Data.dungeonByName(w, "Fungal Grotto I")
    w:addQuest({ name = "Some dungeon quest", kind = "dungeon", zoneId = dFG1.zoneId })
    w.DL.InvalidateQuests()
    eq(w.DL.FindRelatedQuest(fg1).name, "Some dungeon quest")
    w:addQuest({ name = "Pledge: Fungal Grotto I", kind = "pledge" })
    w.DL.InvalidateQuests()
    local q = w.DL.FindRelatedQuest(fg1)
    ok(q.isPledge, "pledge must win over a zone-matched quest")
    -- title/objective text only applies to pledge and dungeon quests, and is whole-word
    local w2 = Boot()
    w2:addQuest({ name = "Hunt", kind = "other", conditions = { "Kill things in Fungal Grotto I" } })
    w2:addQuest({ name = "Bits", kind = "pledge", conditions = { "Defeat bosses in Fungal Grotto II" } })
    w2.DL.InvalidateQuests()
    eq(w2.DL.FindRelatedQuest(Data.byName(w2, "Fungal Grotto I", false)), nil, "'other' quests are matched by zone only; II must not match I")
    ok(w2.DL.FindRelatedQuest(Data.byName(w2, "Fungal Grotto II", true)), "pledge text names Fungal Grotto II")
end)

test("quests: the quest cache is re-read after InvalidateQuests", function()
    local w = Boot()
    local loc = Data.byName(w, "Volenfell", false)
    eq(w.DL.FindRelatedQuest(loc), nil)
    w:addQuest({ name = "Volenfell pledge", kind = "pledge" })
    eq(w.DL.FindRelatedQuest(loc), nil, "cached until invalidated")
    w.DL.InvalidateQuests()
    ok(w.DL.FindRelatedQuest(loc))
end)

test("records: journal-derived - only dungeon related quests are recorded, under the current character", function()
    local w = Boot({ characters = chars({ "Tester", "100" }) })
    local d = Data.dungeonByName(w, "Bal Sunnar")
    w:addQuest({ name = "Bal quest", kind = "dungeon", zoneId = d.zoneId })
    w:addQuest({ name = "Zone-only dungeon quest", kind = "other", zoneId = Data.dungeonByName(w, "Volenfell").zoneId })
    w:addQuest({ name = "Pledge", kind = "pledge", conditions = { "Defeat the boss in Arx Corinium" } })
    w:addQuest({ name = "Story", kind = "story", zoneId = 41 })
    w:addQuest({ name = "Errand", kind = "other", zoneId = 3 })
    w.DL.RecordCurrentCharacter()
    local rec = store(w)["100"]
    ok(rec, "no record")
    eq(rec.name, "Tester", "grammar marker must be stripped")
    local names = {}
    for _, q in ipairs(rec.quests) do names[#names + 1] = q.name end
    table.sort(names)
    same(names, { "Bal quest", "Pledge", "Zone-only dungeon quest" })
end)

test("records: an empty journal never deletes or replaces existing records", function()
    local w = Boot({ characters = chars({ "Tester", "100" }, { "Alt", "200" }) })
    store(w)["100"] = { name = "Tester", quests = { { name = "Old", zones = { 283 } } } }
    store(w)["200"] = { name = "Alt", quests = { { name = "AltQ", zones = { 63 } } } }
    w.DL.RecordCurrentCharacter() -- journal empty (not loaded yet)
    eq(#store(w)["100"].quests, 1); eq(store(w)["100"].quests[1].name, "Old")
    eq(store(w)["200"].quests[1].name, "AltQ")
end)

test("records: deleted characters are pruned, existing ones kept; no pruning when the character list is unavailable", function()
    local w = Boot({ characters = chars({ "Tester", "100" }, { "Alt", "200" }) })
    store(w)["200"] = { name = "Alt", quests = {} }
    store(w)["300"] = { name = "Deleted", quests = {} }
    store(w)["400"] = { name = "Deleted too", quests = {} }
    w.DL.RecordCurrentCharacter()
    ok(store(w)["200"] and not store(w)["300"] and not store(w)["400"])
    local w2 = Boot({ characters = {} })
    store(w2)["300"] = { name = "X", quests = {} }
    w2.DL.RecordCurrentCharacter()
    ok(store(w2)["300"], "GetNumCharacters() == 0 must not prune")
end)

test("records: pruning also happens when the journal is empty, and bad store contents are repaired", function()
    local w = Boot({ characters = chars({ "Tester", "100" }) })
    store(w)["999"] = { name = "Ghost", quests = {} }
    w.DL.RecordCurrentCharacter()
    ok(not store(w)["999"])
    w.DL.settings.characterQuests = "garbage"
    w.DL.RecordCurrentCharacter()
    eq(type(w.DL.settings.characterQuests), "table")
end)

test("records: a changed journal replaces the character's record; other characters are untouched", function()
    local w = Boot({ characters = chars({ "Tester", "100" }, { "Alt", "200" }) })
    store(w)["200"] = { name = "Alt", quests = { { name = "AltQ", zones = { 63 } } } }
    w:addQuest({ name = "Pledge: Volenfell", kind = "pledge" })
    w.DL.RecordCurrentCharacter()
    eq(#store(w)["100"].quests, 1)
    w.journal = {}
    w:addQuest({ name = "Pledge: Arx Corinium", kind = "pledge" })
    w.DL.RecordCurrentCharacter()
    eq(#store(w)["100"].quests, 1); eq(store(w)["100"].quests[1].name, "Pledge: Arx Corinium")
    eq(store(w)["200"].quests[1].name, "AltQ")
end)

test("records: quest events record after the debounce, not before", function()
    local w = Boot({ characters = chars({ "Tester", "100" }) })
    w:addQuest({ name = "Pledge: Volenfell", kind = "pledge" })
    w:fire(w.store.EVENT_QUEST_ADDED)
    eq(store(w)["100"], nil, "recording must wait for the burst of events to end")
    w:advance(149); eq(store(w)["100"], nil)
    w:advance(1)
    ok(store(w)["100"], "recorded after 150 ms")
end)

test("alts: other characters with a quest for the dungeon are listed sorted, current character excluded", function()
    local w = Boot()
    local d = Data.dungeonByName(w, "Volenfell")
    w.DL.settings.characterQuests = {
        ["100"] = { name = "Me", quests = { { name = "q", zones = { d.zoneId } } } },
        ["200"] = { name = "Zed", quests = { { name = "q", zones = { d.zoneId } } } },
        ["300"] = { name = "Alpha", quests = { { name = "q", zones = {}, text = " pledge volenfell run " } } },
        ["400"] = { name = "Nope", quests = { { name = "q", zones = { 1 } } } },
        ["500"] = "corrupt",
        ["600"] = { name = "NoQuests" },
    }
    same(w.DL.GetOtherCharactersWithQuest(Data.byName(w, "Volenfell", true)), { "Alpha", "Zed" })
    eq(w.DL.GetOtherCharactersWithQuest(Data.byName(w, "Arx Corinium", false)), nil)
    w.DL.settings.characterQuests = nil
    eq(w.DL.GetOtherCharactersWithQuest(Data.byName(w, "Volenfell", true)), nil)
end)

test("test_BUG_stale_alt_record_when_the_last_quest_disappears", function()
    -- RecordCurrentCharacter treats an empty journal as 'not loaded yet' and returns early. A character that
    -- completes/abandons its very last quest therefore keeps its old record, and other characters keep showing
    -- 'Also active on: <that character>' for a quest it no longer has. (Low risk: needs a completely empty journal.)
    -- Suggested fix: distinguish 'journal not ready' (e.g. only skip while GetNumJournalQuests()==0 on EVENT_PLAYER_ACTIVATED)
    -- from a real removal (EVENT_QUEST_REMOVED / COMPLETE -> record even when empty).
    local w = Boot({ characters = chars({ "Tester", "100" }) })
    store(w)["100"] = { name = "Tester", quests = { { name = "Old", zones = { 283 } } } }
    w:fire(w.store.EVENT_QUEST_REMOVED) -- the player just turned in the last quest: journal now empty
    w:advance(200)
    eq(#store(w)["100"].quests, 0, "record should be emptied after the last quest was removed")
end)
