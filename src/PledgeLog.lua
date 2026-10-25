-- "Pledge done today": the game never shows today's Undaunted pledges before they are accepted, so
-- completions are recorded instead, per character, and shown until the next daily reset.
local DL = DungeoneersLedger

local MAX_AGE_SECONDS = 8 * 24 * 60 * 60 -- older entries are dropped
local DUPLICATE_WINDOW_SECONDS = 60      -- quest complete and quest removed both report one turn-in

-- settings.pledgeHistory = { [characterId] = { name = characterName, entries = { { quest, zones, at } } } }
local function GetStore()
    if type(DL.settings.pledgeHistory) ~= "table" then
        DL.settings.pledgeHistory = {}
    end
    return DL.settings.pledgeHistory
end

local function ZonesContain(zones, zoneId)
    for _, zone in ipairs(zones) do
        if zone == zoneId then
            return true
        end
    end
    return false
end

-- Drops entries older than MAX_AGE_SECONDS, and characters left with none.
function DL.PrunePledgeHistory(now)
    local store = GetStore()
    for characterId, record in pairs(store) do
        local kept = {}
        for _, entry in ipairs(type(record) == "table" and type(record.entries) == "table" and record.entries or {}) do
            if type(entry.at) == "number" and now - entry.at <= MAX_AGE_SECONDS then
                kept[#kept + 1] = entry
            end
        end
        if #kept == 0 then
            store[characterId] = nil
        else
            record.entries = kept
        end
    end
end

local function FindPledgeByName(questName)
    for _, pledge in ipairs(DL.GetLastKnownPledges()) do
        if pledge.name == questName then
            return pledge
        end
    end
    return nil
end

local function IsDuplicate(record, questName, now)
    for _, entry in ipairs(record.entries) do
        if entry.quest == questName and now - entry.at < DUPLICATE_WINDOW_SECONDS then
            return true
        end
    end
    return false
end

-- Called when a quest was turned in. Does nothing unless it was one of the pledges seen in the journal.
-- Returns true when an entry was added.
function DL.RecordPledgeCompletion(questName, now)
    now = tonumber(now or GetTimeStamp())
    local pledge = FindPledgeByName(questName)
    if not pledge then
        return false
    end
    local zones = DL.FindQuestDungeonZones(pledge)
    if #zones == 0 then
        return false
    end

    local store = GetStore()
    local characterId = GetCurrentCharacterId()
    local record = store[characterId] or { entries = {} }
    if IsDuplicate(record, questName, now) then
        return false
    end
    record.name = zo_strformat(SI_UNIT_NAME, GetUnitName("player"))
    record.entries[#record.entries + 1] = { quest = questName, zones = zones, at = now }
    store[characterId] = record
    DL.PrunePledgeHistory(now)
    return true
end

-- Names of the characters that completed a pledge for the dungeon since the last daily reset, sorted;
-- nil when none. Older entries are ignored, so a dungeon with only an old record shows nothing.
function DL.GetPledgesDoneToday(location, now)
    local store = DL.settings.pledgeHistory
    local zoneId = location.zoneId
    if type(store) ~= "table" or not zoneId then
        return nil
    end
    local resetAt = DL.GetLastDailyReset(now and tonumber(now) or nil)
    local names = {}
    for _, record in pairs(store) do
        if type(record) == "table" and record.name and type(record.entries) == "table" then
            for _, entry in ipairs(record.entries) do
                if type(entry.at) == "number" and entry.at >= resetAt and type(entry.zones) == "table"
                    and ZonesContain(entry.zones, zoneId) then
                    names[#names + 1] = record.name
                    break
                end
            end
        end
    end
    if #names == 0 then
        return nil
    end
    table.sort(names)
    return names
end
