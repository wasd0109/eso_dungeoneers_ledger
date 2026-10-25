-- Dungeon related quests: the current character's active ones, and a small record of every character's.
local DL = DungeoneersLedger

-- quest = { name, isPledge, zones = list of zone ids, zoneSet = { [zoneId] = true } (active only),
--           text = padded normalised title and objectives (pledge / dungeon quests only) }
local activeQuests = nil

local function AddQuestZone(quest, zoneId)
    if zoneId and zoneId > 0 and not quest.zoneSet[zoneId] then
        quest.zoneSet[zoneId] = true
        quest.zones[#quest.zones + 1] = zoneId
    end
end

-- The dungeon name may appear only in the objectives rather than the quest title.
local function BuildQuestText(questIndex, name)
    local parts = { DL.Normalize(name) }
    for stepIndex = QUEST_MAIN_STEP_INDEX, GetJournalQuestNumSteps(questIndex) do
        for conditionIndex = 1, GetJournalQuestNumConditions(questIndex, stepIndex) do
            parts[#parts + 1] = DL.Normalize(GetJournalQuestConditionInfo(questIndex, stepIndex, conditionIndex))
        end
    end
    return " " .. table.concat(parts, " ") .. " "
end

local function ReadJournalQuest(questIndex)
    local questType = GetJournalQuestType(questIndex)
    local isPledge = questType == QUEST_TYPE_UNDAUNTED_PLEDGE
    local quest = { name = GetJournalQuestName(questIndex), isPledge = isPledge, zones = {}, zoneSet = {} }

    local _, _, zoneIndex = GetJournalQuestLocationInfo(questIndex)
    if zoneIndex and zoneIndex > 0 then
        AddQuestZone(quest, GetZoneId(zoneIndex))
    end
    AddQuestZone(quest, GetJournalQuestZoneStoryZoneId(questIndex))

    if isPledge or questType == QUEST_TYPE_DUNGEON then
        quest.text = BuildQuestText(questIndex, quest.name)
    end
    return quest
end

-- Forces the next lookup to read the journal again.
function DL.InvalidateQuests()
    activeQuests = nil
end

-- All active journal quests of the current character.
function DL.GetActiveQuests()
    if not activeQuests then
        local quests = {}
        for questIndex = 1, GetNumJournalQuests() do
            quests[#quests + 1] = ReadJournalQuest(questIndex)
        end
        activeQuests = quests
    end
    return activeQuests
end

-- A quest is related to a dungeon when one of its zones is the dungeon's zone, or, for pledge and dungeon
-- type quests, when the dungeon name appears in the quest title or objectives.
local function QuestMatches(quest, zoneId, normalizedName)
    if zoneId then
        for _, questZoneId in ipairs(quest.zones) do
            if questZoneId == zoneId then
                return true
            end
        end
    end
    return quest.text ~= nil and DL.Contains(quest.text, normalizedName)
end

-- The active quest related to the dungeon (a pledge quest wins over other quests), or nil.
function DL.FindRelatedQuest(location)
    local name = DL.GetNormalizedName(location)
    local zoneId = location.zoneId
    local found = nil
    for _, quest in ipairs(DL.GetActiveQuests()) do
        if QuestMatches(quest, zoneId, name) then
            if quest.isPledge then
                return quest
            end
            found = found or quest
        end
    end
    return found
end

-----------------------------
-- Quests of all characters --
-----------------------------

-- settings.characterQuests = { [characterId] = { name = characterName, quests = { { name, zones, text } } } }
-- Only dungeon related quests are kept, and records of deleted characters are dropped.

local function IsDungeonRelated(quest)
    if quest.isPledge or quest.text then
        return true
    end
    for _, zoneId in ipairs(quest.zones) do
        if DL.IsDungeonZone(zoneId) then
            return true
        end
    end
    return false
end

local function PruneDeletedCharacters(store)
    local numCharacters = GetNumCharacters()
    if numCharacters <= 0 then
        return
    end
    local existing = {}
    for index = 1, numCharacters do
        local _, _, _, _, _, _, characterId = GetCharacterInfo(index)
        existing[characterId] = true
    end
    for characterId in pairs(store) do
        if not existing[characterId] then
            store[characterId] = nil
        end
    end
end

-- Records the current character's dungeon quests from the quest journal alone (no finder data needed).
-- An empty journal is treated as "not loaded yet" and leaves the existing record untouched.
function DL.RecordCurrentCharacter()
    local store = DL.settings.characterQuests
    if type(store) ~= "table" then
        store = {}
        DL.settings.characterQuests = store
    end
    PruneDeletedCharacters(store)

    DL.InvalidateQuests()
    local active = DL.GetActiveQuests()
    if #active == 0 then
        return
    end
    local quests = {}
    for _, quest in ipairs(active) do
        if IsDungeonRelated(quest) then
            quests[#quests + 1] = { name = quest.name, isPledge = quest.isPledge or nil, zones = quest.zones, text = quest.text }
        end
    end
    store[GetCurrentCharacterId()] = { name = zo_strformat(SI_UNIT_NAME, GetUnitName("player")), quests = quests }
end

-- Names of the other characters with an active quest for the dungeon, sorted; nil when there are none.
function DL.GetOtherCharactersWithQuest(location)
    local store = DL.settings.characterQuests
    if type(store) ~= "table" then
        return nil
    end
    local zoneId = location.zoneId
    local normalizedName = DL.GetNormalizedName(location)
    local currentId = GetCurrentCharacterId()
    local names = {}
    for characterId, record in pairs(store) do
        if characterId ~= currentId and type(record) == "table" and record.name and type(record.quests) == "table" then
            for _, quest in ipairs(record.quests) do
                if type(quest.zones) == "table" and QuestMatches(quest, zoneId, normalizedName) then
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
