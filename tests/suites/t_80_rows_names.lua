-- Row icons / tooltips / summary, completion dates, overrides, text helpers.
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
    return { status = c[n .. "DLStatus"], quest = c[n .. "DLQuest"], pips = { c[n .. "DLTier1"], c[n .. "DLTier2"], c[n .. "DLTier3"], c[n .. "DLTier4"] } }
end

test("text helpers: Normalize / Contains", function()
    local w = Boot({ libsets = "none", locations = false, achievements = false })
    local DL = w.DL
    eq(DL.Normalize("Fungal Grotto I^n"), "fungal grotto i")
    eq(DL.Normalize("  City-of  Ash, II!! "), "city of ash ii")
    eq(DL.Normalize(nil), ""); eq(DL.Normalize(42), "42")
    ok(DL.Contains(" veteran fungal grotto ii ", "fungal grotto ii"))
    ok(not DL.Contains(" veteran fungal grotto ii ", "fungal grotto i"), "whole words only")
    ok(not DL.Contains(" anything ", ""), "empty needle never matches")
    eq(DL.Normalize("Wayrest Sewers I^F"), "wayrest sewers i")
end)

test("rows: completion icon reflects the achievement, tooltip names it; hidden without data or when disabled", function()
    local w = Boot()
    local d = Data.dungeonByName(w, "Volenfell")
    w:setAchievementState(d.normalAch, true)
    w:refresh()
    local nrm, vet = Data.byName(w, "Volenfell", false), Data.byName(w, "Volenfell", true)
    local n, v = icons(w, rowFor(w, nrm)), icons(w, rowFor(w, vet))
    ok(n.status.__texture:find("checked", 1, true) and not n.status.__texture:find("unchecked", 1, true))
    ok(v.status.__texture:find("unchecked", 1, true))
    ok(not n.status:IsHidden() and not v.status:IsHidden())
    eq(n.status.tooltipText, "Completed (achievement: Volenfell)")
    eq(v.status.tooltipText:match("^[^\n]+"), "Not completed (achievement: Veteran Volenfell)")
    eq(n.status.__w, 18)
    w.DL.settings.showCompletion = false; w.DL.settings.iconSize = 24
    w.DL.RefreshVisibleRows()
    ok(n.status:IsHidden()); eq(n.pips[1] == nil or n.pips[1]:IsHidden(), true)
    eq(n.quest.__w, 24)
end)

test("rows: a dungeon with no achievement gets no completion icon and counts as 'No achievement data'", function()
    local specs = { { id = 5001, activityType = 2, name = "Mystery Dungeon", zoneId = 987654 } }
    local w = Boot({ locations = specs })
    w.DL.settings.groupBy = "completion"
    w:refresh()
    local loc = w:locations(2)[1]
    eq(w.DL.IsLocationComplete(loc), nil)
    ok(icons(w, rowFor(w, loc)).status:IsHidden())
    eq(w.DL.ResolveMatch(loc).source, "NONE")
end)

test("rows: tier pips - veteran rows only, lit when earned, one per enabled tier, using the achievement icon", function()
    local w = Boot()
    local d = Data.dungeonByName(w, "Bal Sunnar")
    w:setAchievementState(d.tiers.speedRun, true)
    w:refresh()
    local n, v = icons(w, rowFor(w, Data.byName(w, "Bal Sunnar", false))), icons(w, rowFor(w, Data.byName(w, "Bal Sunnar", true)))
    for i = 1, 4 do ok(not n.pips[i] or n.pips[i]:IsHidden(), "normal row pip " .. i) end
    for i = 1, 4 do ok(v.pips[i] and not v.pips[i]:IsHidden(), "veteran pip " .. i) end
    eq(v.pips[2].__desat, 0); eq(v.pips[1].__desat, 1)
    eq(v.pips[2].__texture, "icon_" .. d.tiers.speedRun .. ".dds")
    local tip = v.status.tooltipText
    ok(tip:find("Bal Sunnar Speed Run - Completed", 1, true), tip)
    ok(tip:find("Bal Sunnar Hard Mode - Not completed", 1, true), tip)
    w.DL.settings.tierSpeedRun = false
    w.DL.RefreshVisibleRows()
    local shown = 0
    for i = 1, 4 do if v.pips[i] and not v.pips[i]:IsHidden() then shown = shown + 1 end end
    eq(shown, 3)
end)

test("rows: quest marker + tooltip (quest name, pledge text, other characters), respects showQuest / showAltQuests", function()
    local w = Boot()
    local d = Data.dungeonByName(w, "Volenfell")
    w:addQuest({ name = "Volenfell trouble", kind = "dungeon", zoneId = d.zoneId })
    w.DL.settings.characterQuests = { ["200"] = { name = "Alt", quests = { { name = "q", zones = { d.zoneId } } } } }
    w.DL.InvalidateQuests()
    w:refresh()
    local loc = Data.byName(w, "Volenfell", true)
    local q = icons(w, rowFor(w, loc)).quest
    ok(not q:IsHidden())
    eq(q.tooltipText, "Quest: Volenfell trouble\nAlso active on: Alt")
    w.DL.settings.showAltQuests = false; w.DL.RefreshVisibleRows()
    eq(q.tooltipText, "Quest: Volenfell trouble")
    w:addQuest({ name = "Pledge: Volenfell", kind = "pledge" }); w.DL.InvalidateQuests(); w.DL.RefreshVisibleRows()
    eq(q.tooltipText, "Current Undaunted pledge")
    w.DL.settings.showQuest = false; w.DL.RefreshVisibleRows()
    ok(q:IsHidden())
    ok(icons(w, rowFor(w, Data.byName(w, "Arx Corinium", false))).quest:IsHidden())
end)

test("summary: 'Completed: Normal x/N - Veteran y/N' counts active dungeons only, current difficulty highlighted", function()
    local w = Boot()
    local rng = Data.rng(5)
    local done = { 0, 0 }
    Data.randomCompletion(w, rng, 50)
    Data.byName(w, "Arx Corinium", false):SetActive(false)
    local totals = { 0, 0 }
    for i, t in ipairs({ 2, 3 }) do
        for _, loc in ipairs(w:locations(t)) do
            if loc:IsActive() then
                totals[i] = totals[i] + 1
                local d = Data.dungeonByName(w, (loc:GetRawName()))
                if w.achInfo[t == 3 and d.vetAch or d.normalAch].complete then done[i] = done[i] + 1 end
            end
        end
    end
    w.state.difficulty = 2
    w.finder:RefreshButtons()
    local text = w.controlsByName["DungeoneersLedgerSummary"]:GetText()
    local plain = text:gsub("|c%x%x%x%x%x%x", ""):gsub("|r", "")
    eq(plain, string.format("Completed: Normal %d/%d - Veteran %d/%d", done[1], totals[1], done[2], totals[2]))
    ok(text:find("|cFFFFFFVeteran", 1, true), "current (veteran) difficulty should be highlighted: " .. text)
end)

-------------------------------------------------------------------- completion dates (new feature)
test("dates: tooltip shows the earned date when showDates is on, never for incomplete ones or empty dates", function()
    local w = Boot()
    local d = Data.dungeonByName(w, "Volenfell")
    w:setAchievementState(d.normalAch, true)
    w.achInfo[d.normalAch].date = "3/14/2026"
    w.achInfo[d.tiers.hardMode].complete = true
    w.achInfo[d.tiers.hardMode].date = "4/1/2026"
    w:refresh()
    local st = icons(w, rowFor(w, Data.byName(w, "Volenfell", false))).status
    local tip = st.tooltipText
    if not w.DL.settings.showDates then skip("showDates setting absent") end
    ok(tip:find("3/14/2026", 1, true), tip)
    local vtip = icons(w, rowFor(w, Data.byName(w, "Volenfell", true))).status.tooltipText
    ok(vtip:find("4/1/2026", 1, true), vtip)
    ok(not vtip:find("3/14/2026", 1, true))
    w.DL.settings.showDates = false; w.DL.RefreshVisibleRows()
    ok(not st.tooltipText:find("3/14/2026", 1, true))
    w.DL.settings.showDates = true
    w.achInfo[d.normalAch].date = ""; w.DL.RefreshVisibleRows()
    eq(st.tooltipText, "Completed (achievement: Volenfell)")
end)

test("dates: sort newest/oldest first, undated last in both directions, stable, nothing lost", function()
    local w = Boot()
    if not w.DL.SORT_DATE_NEWEST then skip("date sorting not present in this addon version") end
    local rng = Data.rng(31)
    local stamp = {}
    for _, d in ipairs(w.dungeons) do
        for _, id in ipairs({ d.normalAch, d.vetAch }) do
            local roll = rng(10)
            if roll <= 6 then
                w.achInfo[id].complete = true
                w.achInfo[id].timestamp = 1700000000 + rng(50) * 1000 -- many ties on purpose
                stamp[id] = w.achInfo[id].timestamp
            elseif roll == 7 then
                w.achInfo[id].complete = true -- complete but timestamp 0
            end
        end
    end
    for _, mode in ipairs({ "dateNewest", "dateOldest" }) do
        w.DL.settings.sortBy = mode
        w:refresh()
        for hi, t in ipairs({ 2, 3 }) do
            local shown = w:snapshot()[hi].entries
            eq(#shown, #w:locations(t))
            local lastKey, lastPos = nil, 0
            local pos = {}
            for i, l in ipairs(w:locations(t)) do pos[l] = i end
            for _, loc in ipairs(shown) do
                local d = Data.dungeonByName(w, (loc:GetRawName()))
                local id = t == 3 and d.vetAch or d.normalAch
                local s = stamp[id]
                local key = s and (mode == "dateNewest" and -s or s) or math.huge
                if lastKey then
                    ok(key >= lastKey, mode .. ": order violated at " .. loc:GetRawName())
                    if key == lastKey then ok(pos[loc] > lastPos, mode .. ": ties must keep game order") end
                end
                lastKey, lastPos = key, pos[loc]
            end
        end
    end
end)

-------------------------------------------------------------------- overrides and fragile spots
local function withOverrides(map, opts)
    opts = opts or {}
    local w = Boot(opts)
    w.DL.overrides = map -- Overrides.lua runs before Core; the lookup is built lazily on first use
    return w
end

test("overrides: an override beats LibSets, per difficulty, key matching ignores case/punctuation", function()
    local w = withOverrides({ ["FUNGAL grotto, I"] = { normal = 555001, veteran = 555002 } })
    w:setAchievements({ { name = "Dungeons", list = { { id = 555001, name = "Custom N" }, { id = 555002, name = "Custom V" } }, subs = {} } })
    eq(w.DL.ResolveMatch(Data.byName(w, "Fungal Grotto I", false)).id, 555001)
    eq(w.DL.ResolveMatch(Data.byName(w, "Fungal Grotto I", false)).source, "override")
    eq(w.DL.ResolveMatch(Data.byName(w, "Fungal Grotto I", true)).id, 555002)
    eq(w.DL.ResolveMatch(Data.byName(w, "Fungal Grotto II", false)).source, "libsets")
end)

test("test_BUG_override_with_only_normal_id_is_used_for_the_veteran_row", function()
    -- src/Achievements.lua FindOverrideId: `return override and (isVeteran and override.veteran or override.normal) or nil`
    -- The and/or idiom falls through to override.normal when isVeteran is true and override.veteran is nil, so an
    -- override { normal = X } (the header of Overrides.lua says each field is optional) also forces X on the VETERAN row.
    -- Suggested fix: if not override then return nil end; if isVeteran then return override.veteran else return override.normal end
    local w = withOverrides({ ["fungal grotto i"] = { normal = 555001 } })
    local vet = Data.byName(w, "Fungal Grotto I", true)
    local match = w.DL.ResolveMatch(vet)
    ok(match.id ~= 555001, "veteran row received the NORMAL override id")
    eq(match.source, "libsets")
end)

test("test_BUG_override_with_zero_id_is_treated_as_an_achievement", function()
    -- Overrides.lua's own example is `{ normal = 0, veteran = 0 }`; 0 is truthy in Lua so FindOverrideId returns 0,
    -- ResolveMatch stops there (source "override", id 0) and IsAchievementComplete(0) is queried; LibSets/name matching
    -- are skipped. Suggested fix: treat 0 like nil in FindOverrideId (`local id = ...; return id ~= 0 and id or nil`).
    local w = withOverrides({ ["fungal grotto i"] = { normal = 0, veteran = 0 } })
    local d = Data.dungeonByName(w, "Fungal Grotto I")
    eq(w.DL.FindAchievementId(Data.byName(w, "Fungal Grotto I", false)), d.normalAch)
end)

test("test_BUG_name_matching_gives_up_forever_if_first_tried_before_achievements_exist", function()
    -- src/Achievements.lua DetermineDungeonTop caches `false` (no category matched) in `dungeonTop`, and `~= nil` then
    -- returns false forever, so name matching never recovers once the achievement list becomes available. Only relevant
    -- when LibSets data is missing (name matching is the fallback). Suggested fix: do not cache a false result.
    local w = Boot({ libsets = "none", useData = true, achievements = false })
    local loc = w:locations(2)[1]
    eq(w.DL.ResolveMatch(loc).source, "NONE")
    w:setAchievements((Data.achievementCategories(w.dungeons)))
    w.DL.ClearMatchCache()
    eq(w.DL.ResolveMatch(loc).source, "name", "achievements are available now")
end)

test("overrides: invalid override tables do not crash matching", function()
    local w = withOverrides({ ["x"] = "garbage", ["fungal grotto i"] = {} })
    eq(w.DL.ResolveMatch(Data.byName(w, "Fungal Grotto I", false)).source, "libsets")
end)

test("match cache: results are cached per activity once LibSets is ready (achievement lookup runs once)", function()
    local w = Boot()
    local loc = w:locations(2)[1]
    local first = w.DL.ResolveMatch(loc)
    eq(w.DL.ResolveMatch(loc), first, "same table returned from the cache")
    w.DL.ClearMatchCache()
    ok(w.DL.ResolveMatch(loc) ~= first)
end)
