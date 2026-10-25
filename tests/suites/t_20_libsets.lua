-- Real LibSets dungeon data: id resolution, achievement matching, tiers.
local function expectedId(d, veteran) return veteran and d.vetAch or d.normalAch end
local function zoneOf(w, loc)
    for _, d in ipairs(w.dungeons) do if d.zoneId == loc.zoneId then return d end end
end

test("LibSets data sanity: every listed dungeon has normal AND veteran finder ids and achievements, all unique", function()
    local dungeons = Data.dungeons()
    ok(#dungeons >= 40, "unexpectedly few dungeons: " .. #dungeons)
    local finder, ach = {}, {}
    for _, d in ipairs(dungeons) do
        ok(d.normalFinder and d.normalFinder ~= 0, d.name .. ": no normal finder id")
        ok(d.vetFinder and d.vetFinder ~= 0, d.name .. ": no veteran finder id")
        ok(d.normalAch and d.normalAch ~= 0, d.name .. ": no normal achievement")
        ok(d.vetAch and d.vetAch ~= 0, d.name .. ": no veteran achievement")
        ok(d.normalFinder ~= d.vetFinder and d.normalAch ~= d.vetAch, d.name .. ": normal and veteran ids equal")
        for _, id in ipairs({ d.normalFinder, d.vetFinder }) do
            ok(not finder[id], string.format("finder id %d used by %s and %s", id, d.name, tostring(finder[id])))
            finder[id] = d.name
        end
        for _, id in ipairs({ d.normalAch, d.vetAch, d.tiers.hardMode, d.tiers.speedRun, d.tiers.noDeath, d.tiers.trifecta }) do
            if id then
                ok(not ach[id], string.format("achievement id %d used by %s and %s", id, d.name, tostring(ach[id])))
                ach[id] = d.name
            end
        end
    end
end)

test("LibSets index: one entry per dungeon zone, ids and tiers equal the data", function()
    local w = Boot()
    local index = w.DL.GetLibSetsIndex()
    ok(index, "index not built although LibSets.fullyLoaded")
    eq(index.count, #w.dungeons)
    for _, d in ipairs(w.dungeons) do
        local n, v = index.byActivity[d.normalFinder], index.byActivity[d.vetFinder]
        ok(n and v, d.name .. ": finder ids not indexed")
        eq(n.id, d.normalAch, d.name .. " normal"); eq(v.id, d.vetAch, d.name .. " vet")
        eq(n.zoneId, d.zoneId); eq(v.zoneId, d.zoneId)
        eq(#n.tiers, 0, d.name .. ": normal entry must not carry tiers")
        local want = {}
        for _, key in ipairs({ "hardMode", "speedRun", "noDeath", "trifecta" }) do if d.tiers[key] then want[#want + 1] = d.tiers[key] end end
        eq(#v.tiers, #want, d.name .. " tier count")
        for i, t in ipairs(v.tiers) do eq(t.id, want[i], d.name .. " tier " .. i) end
        ok(index.zones[d.zoneId], d.name .. " zone not marked as dungeon zone")
        ok(w.DL.IsDungeonZone(d.zoneId))
    end
    -- trials / zones without finder data are not dungeon zones
    for zoneId, data in pairs(LibSetsReal.mapping()) do
        if not data.dungeonFinderId then ok(not w.DL.IsDungeonZone(zoneId), "zone " .. zoneId .. " has no finder data") end
    end
end)

test("achievement match (LibSets path): the right achievement for the right row, never cross-mixed", function()
    local w = Boot()
    local seenIds = {}
    for _, loc in ipairs(w:allSpecific()) do
        local zone = zoneOf(w, loc)
        local veteran = loc:GetActivityType() == 3
        local match = w.DL.ResolveMatch(loc)
        eq(match.source, "libsets", zone.name)
        eq(match.id, expectedId(zone, veteran), zone.name .. (veteran and " VET" or " NRM"))
        seenIds[match.id] = (seenIds[match.id] or 0) + 1
    end
    for id, n in pairs(seenIds) do eq(n, 1, "achievement " .. id .. " matched by several rows") end
end)

test("achievement match: I vs II dungeons (Fungal Grotto, Spindleclutch, Crypt of Hearts, City of Ash, ...) are not mixed", function()
    local w = Boot()
    local DL = w.DL
    local pairsFound = 0
    for _, d in ipairs(w.dungeons) do
        local base = d.name:match("^(.-) II$")
        if base then
            local d1 = Data.dungeonByName(w, base .. " I")
            ok(d1, "no '" .. base .. " I' for " .. d.name)
            pairsFound = pairsFound + 1
            for _, veteran in ipairs({ false, true }) do
                local l1, l2 = Data.byName(w, d1.name, veteran), Data.byName(w, d.name, veteran)
                ok(l1 and l2, "rows missing for " .. base)
                eq(DL.FindAchievementId(l1), expectedId(d1, veteran), d1.name)
                eq(DL.FindAchievementId(l2), expectedId(d, veteran), d.name)
                ok(DL.FindAchievementId(l1) ~= DL.FindAchievementId(l2))
            end
        end
    end
    ok(pairsFound >= 8, "expected at least 8 I/II pairs, found " .. pairsFound)
end)

test("achievement match (name fallback, no LibSets): same answers; I/II never mixed; grammar markers tolerated", function()
    for _, markers in ipairs({ false, true }) do
        local w = Boot({ libsets = "none", useData = true, markers = markers })
        for _, loc in ipairs(w:allSpecific()) do
            local zone = zoneOf(w, loc)
            local veteran = loc:GetActivityType() == 3
            local match = w.DL.ResolveMatch(loc)
            eq(match.source, "name", zone.name)
            eq(match.id, expectedId(zone, veteran), zone.name .. (veteran and " VET" or " NRM") .. (markers and " (^n)" or ""))
        end
    end
end)

test("achievement match: rows with grammar markers resolve identically through LibSets", function()
    local w = Boot({ markers = true })
    for _, loc in ipairs(w:allSpecific()) do
        eq(w.DL.FindAchievementId(loc), expectedId(zoneOf(w, loc), loc:GetActivityType() == 3))
    end
end)

test("zone fallback: a row whose activity id LibSets does not know is found by zone id and difficulty", function()
    local d1 = Data.dungeons()[1]
    local w = Boot({ locations = {
        { id = 90001, activityType = 2, name = "Whatever", zoneId = d1.zoneId },
        { id = 90002, activityType = 3, name = "Whatever", zoneId = d1.zoneId },
    } })
    eq(w.DL.FindAchievementId(w:locations(2)[1]), d1.normalAch)
    eq(w.DL.FindAchievementId(w:locations(3)[1]), d1.vetAch)
end)

test("LibSets not fully loaded yet: name fallback, nothing cached, switches to LibSets once ready", function()
    local w = Boot({ libsets = "notloaded" })
    local loc = Data.byName(w, w.dungeons[1].name, true)
    local first = w.DL.ResolveMatch(loc)
    eq(first.source, "name")
    eq(w.DL.GetLibSetsIndex(), nil)
    w.store.LibSets.fullyLoaded = true
    local second = w.DL.ResolveMatch(loc)
    eq(second.source, "libsets", "must not keep serving the cached name result")
    eq(second.id, w.dungeons[1].vetAch)
end)

test("LibSets getter robustness: missing, throwing or garbage GetDungeonZoneData falls back to the raw preloaded table", function()
    for _, mode in ipairs({ "missing", "throws", "garbage" }) do
        local w = Boot({ start = false, setup = function(world)
            local lib = world.store.LibSets
            if mode == "missing" then lib.GetDungeonZoneData = nil
            elseif mode == "throws" then lib.GetDungeonZoneData = function() error("boom") end
            else lib.GetDungeonZoneData = function() return "nope" end end
        end })
        local index = w.store.DungeoneersLedger.GetLibSetsIndex()
        ok(index and index.count == #w.dungeons, mode .. ": expected full index")
    end
end)

test("LibSets with unusable data: no index, no crash, name matching continues", function()
    for _, mode in ipairs({ "nodata", "emptymapping" }) do
        local w = Boot({ useData = true, libsets = "none", setup = function(world)
            local lib = { fullyLoaded = true }
            if mode == "emptymapping" then lib.setDataPreloaded = { dungeonZoneMapping = {} } end
            if mode == "nodata" then lib.setDataPreloaded = {} end
            world.store.LibSets = lib
            world.store.LIBSETS_TABLEKEY_DUNGEON_ZONE_MAPPING = "dungeonZoneMapping"
        end })
        eq(w.DL.GetLibSetsIndex(), nil, mode)
        local loc = w:locations(2)[1]
        eq(w.DL.ResolveMatch(loc).source, "name")
        ok(w.DL.IsLocationComplete(loc) ~= nil)
    end
end)

test("tiers: veteran rows get hardMode/speedRun/noDeath/trifecta ids in that order, normal rows none", function()
    local w = Boot()
    local DL = w.DL
    local order = { "hardMode", "speedRun", "noDeath", "trifecta" }
    local withTrifecta, without = 0, 0
    for _, d in ipairs(w.dungeons) do
        eq(DL.GetLocationTiers(Data.byName(w, d.name, false)), nil, d.name .. " normal row must have no tiers")
        local tiers = DL.GetLocationTiers(Data.byName(w, d.name, true))
        local want = {}
        for _, key in ipairs(order) do if d.tiers[key] then want[#want + 1] = { key, d.tiers[key] } end end
        if #want == 0 then
            eq(tiers, nil)
        else
            eq(#tiers, #want, d.name)
            for i, t in ipairs(tiers) do eq(t.id, want[i][2], d.name .. " " .. want[i][1]); eq(t.tier.key, want[i][1]) end
        end
        if d.tiers.trifecta then withTrifecta = withTrifecta + 1 else without = without + 1 end
    end
    ok(withTrifecta > 10 and without > 10, "data should contain dungeons both with and without trifecta")
end)

test("tiers: settings toggles remove exactly their tier; showTiers off or all off gives nothing", function()
    local w = Boot()
    local DL = w.DL
    local loc = Data.byName(w, "Bal Sunnar", true)
    eq(#DL.GetLocationTiers(loc), 4)
    for _, pair in ipairs({ { "tierHardMode", "hardMode" }, { "tierSpeedRun", "speedRun" }, { "tierNoDeath", "noDeath" }, { "tierTrifecta", "trifecta" } }) do
        DL.settings[pair[1]] = false
        local tiers = DL.GetLocationTiers(loc)
        eq(#tiers, 3, pair[1])
        for _, t in ipairs(tiers) do ok(t.tier.key ~= pair[2], pair[2] .. " still present") end
        DL.settings[pair[1]] = true
    end
    DL.settings.showTiers = false
    eq(DL.GetLocationTiers(loc), nil)
    DL.settings.showTiers = true
    for _, k in ipairs({ "tierHardMode", "tierSpeedRun", "tierNoDeath", "tierTrifecta" }) do DL.settings[k] = false end
    eq(DL.GetLocationTiers(loc), nil)
end)

test("tiers: lower-case LibSets keys (hardmode/speedrun/nodeath) are read as well", function()
    local w = Boot({ start = false, setup = function(world)
        world.store.LibSets.setDataPreloaded.dungeonZoneMapping = { [5] = { dungeonFinderId = { [false] = 1, [true] = 2 },
            achievementId = { [false] = 10, [true] = 11 }, hardmode = 21, speedrun = 22, nodeath = 23 } }
    end })
    eq(#w.store.DungeoneersLedger.GetLibSetsIndex().byActivity[2].tiers, 3)
end)

test("zero ids in LibSets data (0 = no achievement) are ignored", function()
    local w = Boot({ start = false, setup = function(world)
        world.store.LibSets.setDataPreloaded.dungeonZoneMapping = { [5] = { dungeonFinderId = { [false] = 1, [true] = 0 },
            achievementId = { [false] = 10, [true] = 0 }, hardMode = 0, speedRun = 22 } }
    end })
    local index = w.store.DungeoneersLedger.GetLibSetsIndex()
    ok(index.byActivity[1] and not index.byActivity[0])
    eq(index.byActivity[1].id, 10)
    eq(index.byZone["5:true"], nil)
end)
