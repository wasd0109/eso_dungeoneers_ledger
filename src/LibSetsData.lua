-- Dungeon data from the LibSets library: finder activity id -> achievement ids (plain and extra tiers).
local DL = DungeoneersLedger

-- Extra veteran achievements LibSets knows per dungeon. `key` is the field name in its zone data (some of
-- its comments spell them in lower case, so `altKey` is read as well); `setting` is our toggle for it.
DL.TIERS =
{
    { key = "hardMode", altKey = "hardmode", setting = "tierHardMode" },
    { key = "speedRun", altKey = "speedrun", setting = "tierSpeedRun" },
    { key = "noDeath", altKey = "nodeath", setting = "tierNoDeath" },
    { key = "trifecta", altKey = "trifecta", setting = "tierTrifecta" },
}

local libSetsIndex = nil -- { byActivity, byZone, zones, count }; entry = { id, zoneId, tiers = { { tier, id } } }

local function ReadTiers(data)
    local tiers = {}
    for _, tier in ipairs(DL.TIERS) do
        local achievementId = data[tier.key] or data[tier.altKey]
        if type(achievementId) == "number" and achievementId ~= 0 then
            tiers[#tiers + 1] = { tier = tier, id = achievementId }
        end
    end
    return tiers
end

-- Reads one zone through the public LibSets getter, falling back to the raw preloaded entry.
local function ReadZoneData(lib, zoneId, rawData)
    if lib.GetDungeonZoneData then
        local ok, result = DL.SafeCall("LibSets.GetDungeonZoneData", lib.GetDungeonZoneData, zoneId)
        if ok and type(result) == "table" then
            return result
        end
    end
    return rawData
end

local function AddZoneEntries(index, zoneId, data)
    local finderIds = type(data) == "table" and data.dungeonFinderId
    local achievementIds = type(data) == "table" and data.achievementId
    if type(finderIds) ~= "table" or type(achievementIds) ~= "table" then
        return
    end
    for _, isVeteran in ipairs({ false, true }) do
        local achievementId = achievementIds[isVeteran]
        if achievementId and achievementId ~= 0 then
            local entry = { id = achievementId, zoneId = zoneId }
            -- The extra achievements are veteran ones, so only the veteran row carries them.
            entry.tiers = isVeteran and ReadTiers(data) or {}
            index.byZone[zoneId .. ":" .. tostring(isVeteran)] = entry
            local activityId = finderIds[isVeteran]
            if activityId and activityId ~= 0 then
                index.byActivity[activityId] = entry
            end
        end
    end
    index.zones[zoneId] = true
    index.count = index.count + 1
end

-- LibSets has no public call that lists its dungeons, only per-zone getters, so the zone ids come from
-- its preloaded table (read defensively). The index is only kept once LibSets reports fullyLoaded.
function DL.GetLibSetsIndex()
    if libSetsIndex then
        return libSetsIndex
    end
    local lib = LibSets
    if not lib or lib.fullyLoaded ~= true then
        return nil
    end
    local preloaded = type(lib.setDataPreloaded) == "table" and lib.setDataPreloaded
    local rawZones = preloaded and preloaded[LIBSETS_TABLEKEY_DUNGEON_ZONE_MAPPING or "dungeonZoneMapping"]
    if type(rawZones) ~= "table" then
        return nil
    end

    local index = { byActivity = {}, byZone = {}, zones = {}, count = 0 }
    for zoneId, rawData in pairs(rawZones) do
        AddZoneEntries(index, zoneId, ReadZoneData(lib, zoneId, rawData))
    end
    if index.count == 0 then
        return nil
    end
    libSetsIndex = index
    return index
end

function DL.FindLibSetsEntry(location, isVeteran)
    local index = DL.GetLibSetsIndex()
    if not index then
        return nil
    end
    local entry = index.byActivity[location:GetId()]
    if not entry and location.zoneId then
        entry = index.byZone[location.zoneId .. ":" .. tostring(isVeteran)]
    end
    return entry
end

function DL.IsDungeonZone(zoneId)
    local index = DL.GetLibSetsIndex()
    return index ~= nil and index.zones[zoneId] == true
end

----------------------------
-- Set collection progress --
----------------------------

local setProgressCache = {} -- [zoneId] = { unlocked, total } or false (zone has no collection data)

-- Forgets the cached progress; called when the game reports a change in the item set collections.
function DL.InvalidateSetProgress()
    setProgressCache = {}
end

-- Unlocked and total set collection pieces of a dungeon zone, through LibSets (which maps zones to the
-- game's collection categories), or nil when LibSets is not ready or the zone has no sets. Cached per
-- zone, so a list rebuild costs one lookup per dungeon at most.
function DL.GetSetCollectionProgress(zoneId)
    if not zoneId then
        return nil
    end
    local cached = setProgressCache[zoneId]
    if cached ~= nil then
        if cached then
            return cached[1], cached[2]
        end
        return nil
    end
    local lib = LibSets
    if not lib or lib.fullyLoaded ~= true or not lib.GetNumItemSetCollectionZoneUnlockedPieces then
        return nil -- not cached: LibSets may become ready later
    end
    local ok, unlocked, total = DL.SafeCall("LibSets.GetNumItemSetCollectionZoneUnlockedPieces",
        lib.GetNumItemSetCollectionZoneUnlockedPieces, zoneId)
    if ok and type(unlocked) == "number" and type(total) == "number" and total > 0 then
        setProgressCache[zoneId] = { unlocked, total }
        return unlocked, total
    end
    setProgressCache[zoneId] = false
    return nil
end
