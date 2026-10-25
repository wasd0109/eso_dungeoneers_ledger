-- Builders shared by the suites: real-LibSets-derived finder data, a booted world, snapshots, a seeded RNG.
Data = {}
AllWorlds = {}

function Data.rng(seed)
    local s = seed % 2147483647
    if s <= 0 then s = s + 2147483646 end
    return function(n) -- 1..n
        s = (s * 16807) % 2147483647
        return (s % n) + 1
    end
end

-- Dungeons that have finder ids and achievements, in the order of their normal finder id (game order).
function Data.dungeons()
    local real, reason = LibSetsReal.load()
    if not real then skip(reason) end
    local mapping = LibSetsReal.mapping()
    local list = {}
    for zoneId, d in pairs(mapping) do
        if type(d.dungeonFinderId) == "table" and type(d.achievementId) == "table" then
            list[#list + 1] = {
                zoneId = zoneId, name = real.names[zoneId] or ("Zone " .. zoneId), raw = d,
                normalFinder = d.dungeonFinderId[false], vetFinder = d.dungeonFinderId[true],
                normalAch = d.achievementId[false], vetAch = d.achievementId[true],
                tiers = { hardMode = d.hardMode, speedRun = d.speedRun, noDeath = d.noDeath, trifecta = d.trifecta },
            }
        end
    end
    table.sort(list, function(a, b) return (a.normalFinder or 0) < (b.normalFinder or 0) end)
    return list
end

-- Synthetic DLC assignment (the real one comes from the game): base game for the original zones.
function Data.collectibleFor(dungeon)
    local id = dungeon.normalFinder or 0
    if id <= 22 or (id >= 300 and id <= 326) then return 0 end
    return 1000 + math.floor(id / 60)
end

-- opts.markers: append the grammar marker "^n" to every raw name, as the game's raw names may carry one.
function Data.locationSpecs(dungeons, opts)
    opts = opts or {}
    local specs = {}
    for _, d in ipairs(dungeons) do
        local name = d.name .. (opts.markers and "^n" or "")
        if d.normalFinder then
            specs[#specs + 1] = { id = d.normalFinder, activityType = 2, name = name, zoneId = d.zoneId, sortOrder = d.normalFinder }
        end
        if d.vetFinder then
            specs[#specs + 1] = { id = d.vetFinder, activityType = 3, name = name, zoneId = d.zoneId, sortOrder = d.normalFinder or d.vetFinder }
        end
    end
    return specs
end

-- Synthetic achievement names (real ids): "<dungeon>", "Veteran <dungeon>", "<dungeon> Hard Mode", ...
function Data.achievementCategories(dungeons, opts)
    opts = opts or {}
    local dungeonList, vetSub, seen, dupes = {}, {}, {}, {}
    local function add(list, id, name)
        if not id or id == 0 then return end
        if seen[id] then dupes[#dupes + 1] = id return end
        seen[id] = true
        list[#list + 1] = { id = id, name = name, complete = false }
    end
    for _, d in ipairs(dungeons) do
        add(dungeonList, d.normalAch, d.name)
        add(vetSub, d.vetAch, "Veteran " .. d.name)
        add(vetSub, d.tiers.hardMode, d.name .. " Hard Mode")
        add(vetSub, d.tiers.speedRun, d.name .. " Speed Run")
        add(vetSub, d.tiers.noDeath, d.name .. " No Death")
        add(vetSub, d.tiers.trifecta, "Trifecta: " .. d.name)
    end
    local general = { { id = 900001, name = "Explorer", complete = false }, { id = 900002, name = "Lorekeeper", complete = false } }
    return { { name = "Dungeons", list = dungeonList, subs = { { name = "Veteran", list = vetSub } } },
             { name = "General", list = general, subs = {} } }, dupes
end

function Data.installLAM(world)
    local lam = { panels = {}, options = {}, opened = {} }
    local api = {}
    function api:RegisterAddonPanel(id, data) local panel = { id = id, data = data }; lam.panels[id] = panel; return panel end
    function api:RegisterOptionControls(id, options) lam.options[id] = options end
    function api:OpenToPanel(panel) lam.opened[#lam.opened + 1] = panel end
    world.store.LibAddonMenu2 = api
    world.lam = lam
end

-- Boots a world. opts: libsets = "real" (default) | "none" | "notloaded"; locations = specs | false | nil (real dungeons,
-- or a small synthetic list without LibSets); achievements = true|false; lam = false to omit; savedVars / oldSavedVars
-- tables; oldAddon = true defines the old addon's global; start = false to skip EVENT_ADD_ON_LOADED; markers.
function Boot(opts)
    opts = opts or {}
    local w = World.new(opts)
    AllWorlds[#AllWorlds + 1] = w
    local mode = opts.libsets or "real"
    local dungeons
    if mode ~= "none" or opts.useData then dungeons = Data.dungeons() end
    if mode ~= "none" then LibSetsReal.install(w, LibSetsReal.mapping(), mode ~= "notloaded") end
    w.dungeons = dungeons
    if opts.locations then
        w:setLocations(opts.locations)
    elseif opts.locations ~= false and dungeons then
        w:setLocations(Data.locationSpecs(dungeons, opts))
        for _, d in ipairs(dungeons) do
            local c = Data.collectibleFor(d)
            if d.normalFinder then w.collectibleByActivity[d.normalFinder] = c end
            if d.vetFinder then w.collectibleByActivity[d.vetFinder] = c end
        end
    end
    if opts.achievements ~= false and dungeons then
        local cats = Data.achievementCategories(dungeons)
        w:setAchievements(cats)
    end
    if opts.lam ~= false then Data.installLAM(w) end
    if opts.savedVars then w.store.DungeoneersLedger_SavedVariables = opts.savedVars end
    if opts.oldSavedVars then w.store.DungeonCompletion_SavedVariables = opts.oldSavedVars end
    if opts.oldAddon then w.store.DungeonCompletion = { name = "DungeonCompletion" } end
    if opts.characters then w.characters = opts.characters end
    if opts.setup then opts.setup(w) end
    w:load()
    if opts.start ~= false then w:start() end
    w.DL = w.store.DungeoneersLedger
    return w
end

-- Marks a random subset of the dungeon achievements complete (seeded); returns the set of completed ids.
function Data.randomCompletion(w, rng, percent)
    local done = {}
    for id, a in pairs(w.achInfo) do
        if a.id < 900000 then
            a.complete = rng(100) <= percent
            if a.complete then done[id] = true end
        end
    end
    return done
end

function Data.byName(w, name, veteran)
    for _, l in ipairs(w:locations(veteran and 3 or 2)) do
        if l:GetRawName():gsub("%^%a+", "") == name then return l end
    end
end

function Data.dungeonByName(w, name)
    for _, d in ipairs(w.dungeons) do if d.name == name then return d end end
end

-- The list the finder currently shows: { { title, entries = {loc}, groups = { {title, key, entries} } } }
function World:snapshot()
    local out = {}
    for _, header in ipairs(self.tree.rootNode.children or {}) do
        local h = { title = header.control.text:GetText(), entries = {}, groups = {}, node = header }
        for _, child in ipairs(header.children or {}) do
            if type(child.data) == "string" then
                local g = { key = child.data, title = child.control.text:GetText(), entries = {}, node = child }
                for _, e in ipairs(child.children or {}) do g.entries[#g.entries + 1] = e.data end
                h.groups[#h.groups + 1] = g
            else
                h.entries[#h.entries + 1] = child.data
            end
        end
        out[#out + 1] = h
    end
    return out
end

-- All locations shown under a header, flattened in display order.
function Data.flatten(header)
    local list = {}
    for _, e in ipairs(header.entries) do list[#list + 1] = e end
    for _, g in ipairs(header.groups) do
        for _, e in ipairs(g.entries) do list[#list + 1] = e end
    end
    return list
end

function World:refresh() self.DL.RefreshFinder() end
function World:set(key, value) self.DL.settings[key] = value end
function World:chatText() return table.concat(self.chat, "\n") end

function World:setAchievementState(id, complete)
    if self.achInfo[id] then self.achInfo[id].complete = complete end
end
