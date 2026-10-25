-- Grouping / sorting / search / hide-completed / quest pinning over the full real dungeon list, checked against an
-- independent oracle, with seeded random completion and quest states.
local function norm(s)
    s = s:lower()
    s = s:gsub("%^%a+", "")
    s = s:gsub("[%p%c]", " ")
    s = s:gsub("%s+", " ")
    s = s:gsub("^ ", "")
    s = s:gsub(" $", "")
    return s
end

local function cleanName(loc) return (loc:GetRawName():gsub("%^%a+", "")) end

-- Fresh world with seeded completion and quests; returns world, oracle helpers.
local function setup(seed, opts)
    opts = opts or {}
    local w = Boot(opts)
    local rng = Data.rng(seed)
    Data.randomCompletion(w, rng, 45)
    local questZones = {}
    local picks = 0
    for _, d in ipairs(w.dungeons) do
        if rng(100) <= 15 then
            picks = picks + 1
            questZones[d.zoneId] = true
            if picks % 2 == 0 then
                w:addQuest({ name = "Pledge: " .. d.name, kind = "pledge", zoneId = nil, conditions = { "Defeat the boss in " .. d.name } })
            else
                w:addQuest({ name = "Dungeon quest " .. picks, kind = "dungeon", zoneId = d.zoneId })
            end
        end
    end
    -- decoys that must not mark anything: unrelated zones, story quest in a non-dungeon zone
    w:addQuest({ name = "Unrelated story", kind = "story", zoneId = 41, storyZoneId = 41 })
    w:addQuest({ name = "Errand", kind = "other", zoneId = 3 })
    w.DL.InvalidateQuests()
    w.questZones = questZones
    return w
end

local function oracle(w)
    local O = {}
    local byZone = {}
    for _, d in ipairs(w.dungeons) do byZone[d.zoneId] = d end
    function O.complete(loc)
        local d = byZone[loc.zoneId]
        local id = loc:GetActivityType() == 3 and d.vetAch or d.normalAch
        return w.achInfo[id].complete
    end
    function O.hasQuest(loc)
        if w.questZones[loc.zoneId] then return true end
        -- pledge quests mention the dungeon name in their objectives
        for _, q in ipairs(w.journal) do
            if q.type == w.store.QUEST_TYPE_UNDAUNTED_PLEDGE then
                local text = " " .. norm(q.name .. " " .. q.steps[1][1]) .. " "
                if text:find(" " .. norm(loc:GetRawName()) .. " ", 1, true) then return true end
            end
        end
        return false
    end
    function O.collectible(loc) return w.collectibleByActivity[loc:GetId()] or 0 end
    return O
end

local function expectedLayout(w, activityType, S, O, search)
    -- 1. filter
    local list = {}
    for _, loc in ipairs(w:locations(activityType)) do
        local hidden = (S.hideCompleted and O.complete(loc)) or (search ~= "" and not norm(loc:GetRawName()):find(search, 1, true))
        if not hidden then list[#list + 1] = loc end
    end
    -- 2. stable sort
    local pos = {}
    for i, loc in ipairs(list) do pos[loc] = i end
    local key = ({
        game = function() return 0 end,
        name = function(l) return norm(l:GetRawName()) end,
        dlc = function(l) return O.collectible(l) end,
        completion = function(l) return O.complete(l) and 2 or 0 end,
    })[S.sortBy]
    table.sort(list, function(a, b)
        local ka, kb = key(a), key(b)
        if ka ~= kb then return ka < kb end
        return pos[a] < pos[b]
    end)
    -- 3. groups
    if S.groupBy == "none" and not S.pinQuest then return { flat = list } end
    local groups, order = {}, {}
    for _, loc in ipairs(list) do
        local k, title, rank, progress
        if S.pinQuest and O.hasQuest(loc) then
            k, title, rank, progress = "quest", "Dungeons with a quest", -1, false
        elseif S.groupBy == "completion" then
            if O.complete(loc) then k, title, rank = "done", "Completed", 2 else k, title, rank = "todo", "Not completed", 1 end
            progress = false
        elseif S.groupBy == "dlc" then
            local c = O.collectible(loc)
            if c == 0 then k, title, rank = "base", "Base game", 0 else k, title, rank = "collectible" .. c, "Collectible " .. c, c end
            progress = true
        else
            k, title, rank, progress = "other", "Other dungeons", 1000, false
        end
        if not groups[k] then
            groups[k] = { key = k, title = title, rank = rank, progress = progress, entries = {}, done = 0, first = #order }
            order[#order + 1] = groups[k]
        end
        local g = groups[k]
        g.entries[#g.entries + 1] = loc
        if O.complete(loc) then g.done = g.done + 1 end
    end
    if #order < 2 then return { flat = list } end
    table.sort(order, function(a, b) if a.rank ~= b.rank then return a.rank < b.rank end return a.first < b.first end)
    for _, g in ipairs(order) do
        g.display = g.progress and string.format("%s (%d/%d)", g.title, g.done, #g.entries) or string.format("%s (%d)", g.title, #g.entries)
    end
    return { groups = order }
end

local function check(w, S, search, label)
    local O = oracle(w)
    local snap = w:snapshot()
    eq(#snap, 2, label .. ": header count")
    eq(snap[1].title, "Normal"); eq(snap[2].title, "Veteran")
    for hi, activityType in ipairs({ 2, 3 }) do
        local exp = expectedLayout(w, activityType, S, O, search)
        local got = snap[hi]
        if exp.flat then
            eq(#got.groups, 0, label .. ": unexpected groups")
            eq(#got.entries, #exp.flat, label .. ": entry count under " .. got.title)
            for i, loc in ipairs(exp.flat) do
                ok(got.entries[i] == loc, string.format("%s: %s position %d expected %s got %s", label, got.title, i, cleanName(loc), got.entries[i] and cleanName(got.entries[i]) or "nil"))
            end
        else
            eq(#got.entries, 0, label .. ": ungrouped leftovers under " .. got.title)
            eq(#got.groups, #exp.groups, label .. ": group count under " .. got.title)
            for gi, g in ipairs(exp.groups) do
                local gg = got.groups[gi]
                eq(gg.title, g.display, label .. ": group title")
                eq(gg.key, "DL:" .. got.title .. ":" .. g.key, label .. ": group node key")
                eq(#gg.entries, #g.entries, label .. ": " .. g.display)
                for i, loc in ipairs(g.entries) do
                    ok(gg.entries[i] == loc, string.format("%s: %s / %s position %d expected %s got %s", label, got.title, g.display, i, cleanName(loc), gg.entries[i] and cleanName(gg.entries[i]) or "nil"))
                end
            end
        end
        -- nothing lost, nothing duplicated: compare with the filtered set
        local seen, n = {}, 0
        for _, loc in ipairs(Data.flatten(got)) do
            ok(not seen[loc], label .. ": duplicated " .. cleanName(loc)); seen[loc] = true; n = n + 1
        end
        local want = 0
        for _, loc in ipairs(w:locations(activityType)) do
            local hidden = (S.hideCompleted and O.complete(loc)) or (search ~= "" and not norm(loc:GetRawName()):find(search, 1, true))
            if not hidden then want = want + 1; ok(seen[loc], label .. ": lost " .. cleanName(loc)) end
        end
        eq(n, want, label .. ": total shown")
    end
end

test("list: default settings leave the game's list untouched (order, no groups)", function()
    local w = setup(7)
    w:refresh()
    local snap = w:snapshot()
    for hi, t in ipairs({ 2, 3 }) do
        eq(#snap[hi].groups, 0)
        eq(#snap[hi].entries, #w:locations(t))
        for i, loc in ipairs(w:locations(t)) do ok(snap[hi].entries[i] == loc, "order changed at " .. i) end
    end
    ok(#w:locations(2) == #w.dungeons and #w:locations(3) == #w.dungeons)
end)

test("list: every combination of group x sort x hide-completed x pin-quest x search (3 seeds) matches the oracle", function()
    local combos = 0
    for _, seed in ipairs({ 11, 202, 3033 }) do
        local w = setup(seed)
        for _, groupBy in ipairs({ "none", "completion", "dlc" }) do
            for _, sortBy in ipairs({ "game", "name", "dlc", "completion" }) do
                for _, hide in ipairs({ false, true }) do
                    for _, pin in ipairs({ false, true }) do
                        for _, search in ipairs({ "", "of", "fungal grotto", "zzzz-no-match" }) do
                            local S = { groupBy = groupBy, sortBy = sortBy, hideCompleted = hide, pinQuest = pin }
                            for k, v in pairs(S) do w.DL.settings[k] = v end
                            w.DL.SetSearchText(norm(search))
                            w:refresh()
                            check(w, S, norm(search), string.format("seed %d group=%s sort=%s hide=%s pin=%s search='%s'", seed, groupBy, sortBy, tostring(hide), tostring(pin), search))
                            combos = combos + 1
                        end
                    end
                end
            end
        end
    end
    eq(combos, 3 * 3 * 4 * 2 * 2 * 4)
end)

test("list: refreshing repeatedly is stable (same order, same node keys, rows reused not leaked)", function()
    local w = setup(5)
    for k, v in pairs({ groupBy = "dlc", sortBy = "name", pinQuest = true, hideCompleted = true }) do w.DL.settings[k] = v end
    w:refresh()
    local function signature()
        local parts = {}
        for _, h in ipairs(w:snapshot()) do
            parts[#parts + 1] = h.title
            for _, g in ipairs(h.groups) do
                parts[#parts + 1] = g.key .. "|" .. g.title
                for _, e in ipairs(g.entries) do parts[#parts + 1] = e:GetId() end
            end
        end
        return table.concat(parts, ",")
    end
    local first = signature()
    local controlsAfterFirst = w.stats.controlsCreated
    for _ = 1, 5 do w:refresh(); eq(signature(), first) end
    eq(w.stats.controlsCreated, controlsAfterFirst, "controls leaked: rows must come from the pool on refresh")
end)

test("list: hide-completed counts - completed dungeons never shown, incomplete always shown", function()
    local w = setup(99)
    w.DL.settings.hideCompleted = true
    w:refresh()
    local O = oracle(w)
    local snap = w:snapshot()
    for hi, t in ipairs({ 2, 3 }) do
        local shown = {}
        for _, loc in ipairs(Data.flatten(snap[hi])) do ok(not O.complete(loc), cleanName(loc) .. " is complete but shown"); shown[loc] = true end
        for _, loc in ipairs(w:locations(t)) do if not O.complete(loc) then ok(shown[loc], cleanName(loc) .. " incomplete but hidden") end end
    end
end)

test("list: everything completed + hide-completed shows empty headers without errors; grouping by completion shows one group", function()
    local w = setup(1)
    for id, a in pairs(w.achInfo) do a.complete = true end
    w.DL.settings.hideCompleted = true
    w:refresh()
    for _, h in ipairs(w:snapshot()) do eq(#Data.flatten(h), 0) end
    w.DL.settings.hideCompleted = false
    w.DL.settings.groupBy = "completion"
    w:refresh()
    for _, h in ipairs(w:snapshot()) do
        eq(#Data.flatten(h), #w.dungeons)
        eq(#h.groups, 0, "a single group must not be shown")
    end
end)

test("list: pin quest to top - quest dungeons first, in a group of their own, for both difficulties", function()
    local w = setup(42)
    w.DL.settings.pinQuest = true
    w:refresh()
    local O = oracle(w)
    local snap = w:snapshot()
    for hi, t in ipairs({ 2, 3 }) do
        local expectedQuest = 0
        for _, loc in ipairs(w:locations(t)) do if O.hasQuest(loc) then expectedQuest = expectedQuest + 1 end end
        ok(expectedQuest > 0, "seed should produce quest dungeons")
        local first = snap[hi].groups[1]
        eq(first.title, string.format("Dungeons with a quest (%d)", expectedQuest))
        eq(#first.entries, expectedQuest)
        for _, loc in ipairs(first.entries) do ok(O.hasQuest(loc), cleanName(loc) .. " pinned without a quest") end
        eq(snap[hi].groups[2].title:match("^Other dungeons"), "Other dungeons")
    end
end)

test("list: the unrelated decoy quests (story quest in zone 41, errand in zone 3) never pin or mark anything", function()
    local w = Boot()
    w:addQuest({ name = "Unrelated story", kind = "story", zoneId = 41, storyZoneId = 41 })
    w:addQuest({ name = "Errand", kind = "other", zoneId = 3, conditions = { "Fetch 5 mudcrabs from Fungal Grotto I" } })
    w.DL.InvalidateQuests()
    for _, loc in ipairs(w:allSpecific()) do eq(w.DL.FindRelatedQuest(loc), nil, cleanName(loc)) end
    w.DL.settings.pinQuest = true
    w:refresh()
    for _, h in ipairs(w:snapshot()) do eq(#h.groups, 0, "no quest dungeons: no groups") end
end)

test("list: group header counts and done/total in the DLC grouping equal the oracle (explicit)", function()
    local w = setup(77)
    w.DL.settings.groupBy = "dlc"
    w:refresh()
    local O = oracle(w)
    for hi, t in ipairs({ 2, 3 }) do
        local counts, done = {}, {}
        for _, loc in ipairs(w:locations(t)) do
            local c = O.collectible(loc)
            counts[c] = (counts[c] or 0) + 1
            if O.complete(loc) then done[c] = (done[c] or 0) + 1 end
        end
        local snap = w:snapshot()[hi]
        local total = 0
        for _, g in ipairs(snap.groups) do
            local n = #g.entries
            local c = tonumber(g.key:match("collectible(%d+)$")) or 0
            eq(n, counts[c])
            ok(g.title:find(string.format("(%d/%d)", done[c] or 0, n), 1, true), g.title .. " progress wrong")
            total = total + n
        end
        eq(total, #w:locations(t))
    end
end)

test("list: search is case/punctuation/grammar-marker insensitive and matches whole-name substrings", function()
    local w = Boot({ markers = true })
    w.DL.SetSearchText(norm("CITY of Ash"))
    w:refresh()
    for _, h in ipairs(w:snapshot()) do
        local names = {}
        for _, loc in ipairs(Data.flatten(h)) do names[#names + 1] = cleanName(loc) end
        table.sort(names)
        same(names, { "City of Ash I", "City of Ash II" })
    end
    w.DL.SetSearchText(norm("Kyne's  Aegis!!"))
    w:refresh()
    for _, h in ipairs(w:snapshot()) do eq(#Data.flatten(h), 0) end
    w.DL.SetSearchText("")
    w:refresh()
    for _, h in ipairs(w:snapshot()) do eq(#Data.flatten(h), #w.dungeons) end
end)

test("list: SET-type and inactive entries are never listed or altered by the addon", function()
    local d = Data.dungeons()
    local specs = Data.locationSpecs({ d[1], d[2], d[3] })
    specs[#specs + 1] = { id = 777, activityType = 2, name = "Random Normal Dungeon", entryType = 2, sortOrder = 1 }
    specs[#specs + 1] = { id = 778, activityType = 2, name = "Inactive", zoneId = d[4].zoneId, active = false, sortOrder = 2 }
    local w = Boot({ locations = specs, setup = function(world) end })
    w.DL.settings.sortBy = "name"
    w.DL.settings.groupBy = "completion"
    w:refresh()
    for _, h in ipairs(w:snapshot()) do
        for _, loc in ipairs(Data.flatten(h)) do
            ok(loc:GetId() ~= 777 and loc:GetId() ~= 778, "listed " .. cleanName(loc))
        end
    end
end)

test("list: a failing sort/group/filter step falls back to the game's list instead of breaking the finder", function()
    local w = setup(3)
    w.DL.settings.sortBy = "dlc"
    w.DL.settings.groupBy = "dlc"
    w.store.GetRequiredActivityCollectibleId = function() error("collectible API failed") end
    w:refresh()
    local snap = w:snapshot()
    eq(#snap, 2)
    for hi, t in ipairs({ 2, 3 }) do eq(#Data.flatten(snap[hi]), #w:locations(t), "all dungeons must still be listed") end
    w.DL.SetDebug(true)
    ok(w:chatText():find("error in", 1, true), "failure should surface with debug on")
end)

test("list: sorting - name sort is alphabetical by normalised name, ties keep game order", function()
    local w = setup(8)
    w.DL.settings.sortBy = "name"
    w:refresh()
    for hi in ipairs({ 2, 3 }) do
        local names = {}
        for _, loc in ipairs(w:snapshot()[hi].entries) do names[#names + 1] = norm(loc:GetRawName()) end
        for i = 2, #names do ok(names[i - 1] <= names[i], names[i - 1] .. " > " .. names[i]) end
    end
end)
