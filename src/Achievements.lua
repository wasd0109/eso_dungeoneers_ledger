-- Which achievement belongs to a finder row: manual override, then LibSets, then name matching.
local DL = DungeoneersLedger

-- Achievements whose name contains one of these are not the plain "complete the dungeon" achievement.
local HARD_MODE_WORDS = { "hard mode", "flawless", "challenger", "speed", "no death", "untouchable", "last stand" }

DL.SOURCES = { "override", "libsets", "name", "NONE" }

local achievementIndex = nil  -- list of { id, name, normalized, padded, top }
local dungeonTop = nil        -- top level achievement category that holds the dungeon achievements
local localizedVeteran = nil  -- normalised localised word for "veteran"
local overrideLookup = nil    -- [normalised dungeon name] = { normal, veteran }
local matchCache = {}         -- [activityId] = { id = achievementId or nil, source = one of DL.SOURCES }

function DL.ClearMatchCache()
    matchCache = {}
end

---------------------
-- Name matching   --
---------------------

local function IsVeteranAchievement(entry)
    localizedVeteran = localizedVeteran or DL.Normalize(GetString("SI_DUNGEONDIFFICULTY", DUNGEON_DIFFICULTY_VETERAN))
    return DL.Contains(entry.padded, "veteran") or DL.Contains(entry.padded, localizedVeteran)
end

local function IsHardModeAchievement(entry)
    for _, word in ipairs(HARD_MODE_WORDS) do
        if entry.padded:find(word, 1, true) then
            return true
        end
    end
    return false
end

local function AddAchievement(list, achievementId, top)
    if achievementId and achievementId ~= 0 then
        local name = GetAchievementName(achievementId)
        local normalized = DL.Normalize(name)
        if normalized ~= "" then
            list[#list + 1] = { id = achievementId, name = name, normalized = normalized, padded = " " .. normalized .. " ", top = top }
        end
    end
end

local function BuildAchievementIndex()
    if achievementIndex then
        return achievementIndex
    end
    local list = {}
    for top = 1, GetNumAchievementCategories() do
        local _, numSubCategories, numAchievements = GetAchievementCategoryInfo(top)
        for index = 1, numAchievements do
            AddAchievement(list, GetAchievementId(top, nil, index), top)
        end
        for sub = 1, numSubCategories do
            local _, numSubAchievements = GetAchievementSubCategoryInfo(top, sub)
            for index = 1, numSubAchievements do
                AddAchievement(list, GetAchievementId(top, sub, index), top)
            end
        end
    end
    achievementIndex = list
    return list
end

-- Picks the top level category with the most name hits across all finder dungeons, so unrelated
-- achievements elsewhere (lore books, zone achievements mentioning a dungeon) are not matched.
local function DetermineDungeonTop()
    if dungeonTop ~= nil then
        return dungeonTop
    end
    local index = BuildAchievementIndex()
    local counts = {}
    for _, activityType in ipairs(DL.ACTIVITY_TYPES) do
        for _, location in ipairs(DL.GetLocations(activityType)) do
            local name = DL.GetNormalizedName(location)
            for _, entry in ipairs(index) do
                if DL.Contains(entry.padded, name) then
                    counts[entry.top] = (counts[entry.top] or 0) + 1
                end
            end
        end
    end
    local bestTop, bestCount = false, 0
    for top, count in pairs(counts) do
        if count > bestCount then
            bestTop, bestCount = top, count
        end
    end
    dungeonTop = bestTop
    return dungeonTop
end

-- Achievement choice for one dungeon row:
--  NORMAL row:  the non-veteran, non-hard-mode achievement whose name equals the dungeon name, else the
--               shortest name that contains it.
--  VETERAN row: same, but the achievement name must mention "veteran"; no match means no icon.
-- Whole-word matching keeps "Fungal Grotto I" from matching "Fungal Grotto II".
local function FindAchievementIdByName(location, isVeteran)
    local dungeonName = DL.GetNormalizedName(location)
    local top = DetermineDungeonTop()
    if not top then
        return nil
    end
    local best = nil
    for _, entry in ipairs(BuildAchievementIndex()) do
        if entry.top == top and DL.Contains(entry.padded, dungeonName)
            and IsVeteranAchievement(entry) == isVeteran and not IsHardModeAchievement(entry) then
            local isExact = entry.normalized == dungeonName
            if not best
                or (isExact and not best.isExact)
                or (isExact == best.isExact and #entry.normalized < #best.entry.normalized) then
                best = { entry = entry, isExact = isExact }
            end
        end
    end
    return best and best.entry.id or nil
end

---------------
-- Overrides --
---------------

local function FindOverrideId(location, isVeteran)
    if not overrideLookup then
        overrideLookup = {}
        for name, override in pairs(DL.overrides or {}) do
            overrideLookup[DL.Normalize(name)] = override
        end
    end
    local override = overrideLookup[DL.GetNormalizedName(location)]
    return override and (isVeteran and override.veteran or override.normal) or nil
end

-----------------
-- Resolution  --
-----------------

-- Returns { id = achievementId or nil, source = one of DL.SOURCES }.
function DL.ResolveMatch(location)
    local activityId = location:GetId()
    local cached = matchCache[activityId]
    if cached then
        return cached
    end

    local isVeteran = DL.IsVeteranLocation(location)
    local result = { source = "override", id = FindOverrideId(location, isVeteran) }
    if not result.id then
        local entry = DL.FindLibSetsEntry(location, isVeteran)
        result = { source = "libsets", id = entry and entry.id or nil }
    end
    if not result.id then
        result = { source = "name", id = FindAchievementIdByName(location, isVeteran) }
    end
    if not result.id then
        result = { source = "NONE" }
    end

    -- Until LibSets is ready the name fallback may be wrong or missing, so only keep results that cannot improve.
    if DL.GetLibSetsIndex() or result.source == "override" then
        matchCache[activityId] = result
    end
    return result
end

function DL.FindAchievementId(location)
    return DL.ResolveMatch(location).id
end

-- true / false, or nil when the dungeon has no known achievement.
function DL.IsLocationComplete(location)
    local achievementId = DL.FindAchievementId(location)
    if not achievementId then
        return nil
    end
    return IsAchievementComplete(achievementId)
end

-- The enabled extra achievements of a veteran dungeon row: list of { tier, id }, or nil.
function DL.GetLocationTiers(location)
    if not (DL.settings.showTiers and DL.IsVeteranLocation(location)) then
        return nil
    end
    local entry = DL.FindLibSetsEntry(location, true)
    if not entry or #entry.tiers == 0 then
        return nil
    end
    local enabled = {}
    for _, tierEntry in ipairs(entry.tiers) do
        if DL.settings[tierEntry.tier.setting] then
            enabled[#enabled + 1] = tierEntry
        end
    end
    return #enabled > 0 and enabled or nil
end
