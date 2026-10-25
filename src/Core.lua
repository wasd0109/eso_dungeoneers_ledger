-- Namespace, defaults, saved variables (with the one-time DungeonCompletion import) and shared helpers.
DungeoneersLedger = DungeoneersLedger or {}
local DL = DungeoneersLedger

DL.name = "DungeoneersLedger"
DL.version = "0.2.0" -- keep in step with the manifest
DL.savedVarsName = "DungeoneersLedger_SavedVariables"
DL.oldAddonName = "DungeonCompletion"
DL.oldSavedVarsName = "DungeonCompletion_SavedVariables"

DL.ACTIVITY_TYPES = { LFG_ACTIVITY_DUNGEON, LFG_ACTIVITY_MASTER_DUNGEON }

DL.GROUP_NONE, DL.GROUP_COMPLETION, DL.GROUP_DLC = "none", "completion", "dlc"
DL.GROUP_CHOICE_VALUES = { DL.GROUP_NONE, DL.GROUP_COMPLETION, DL.GROUP_DLC }
DL.SORT_GAME, DL.SORT_NAME, DL.SORT_DLC, DL.SORT_COMPLETION = "game", "name", "dlc", "completion"
DL.SORT_DATE_NEWEST, DL.SORT_DATE_OLDEST = "dateNewest", "dateOldest"
DL.SORT_CHOICE_VALUES = { DL.SORT_GAME, DL.SORT_NAME, DL.SORT_DLC, DL.SORT_COMPLETION, DL.SORT_DATE_NEWEST, DL.SORT_DATE_OLDEST }

DL.DEFAULTS =
{
    showCompletion = true,
    showTiers = true,
    showDates = true,
    showSetProgress = true,
    rememberPledges = true,
    tierHardMode = true,
    tierSpeedRun = true,
    tierNoDeath = true,
    tierTrifecta = true,
    showQuest = true,
    showAltQuests = true,
    pinQuest = false,
    skipCompletedOnSelect = false,
    selectVeteran = false,
    iconSize = 18,
    hideCompleted = false,
    groupBy = DL.GROUP_NONE,
    sortBy = DL.SORT_GAME,
}
DL.settings = ZO_ShallowTableCopy(DL.DEFAULTS) -- replaced by the saved variables in DL.LoadSettings

local DEBOUNCE_MS = 150

---------------
-- Utilities --
---------------

-- Looks up one of this addon's strings (lang/*.lua); extra arguments are formatted into it.
function DL.L(stringId, ...)
    local text = GetString(stringId)
    if select("#", ...) > 0 then
        return string.format(text, ...)
    end
    return text
end

function DL.Print(text, ...)
    if select("#", ...) > 0 then
        text = string.format(text, ...)
    end
    d("[Dungeoneer's Ledger] " .. text)
end

function DL.Normalize(text)
    text = zo_strlower(tostring(text or ""))
    text = text:gsub("%^%a+", "") -- grammar markers such as ^n
    text = text:gsub("[%p%c]", " ")
    text = text:gsub("%s+", " ")
    text = text:gsub("^ ", "")
    text = text:gsub(" $", "")
    return text
end

function DL.Contains(haystackPadded, needle)
    return needle ~= "" and haystackPadded:find(" " .. needle .. " ", 1, true) ~= nil
end

function DL.IsSpecificLocation(location)
    return location:GetEntryType() == ZO_ACTIVITY_FINDER_LOCATION_ENTRY_TYPE.SPECIFIC
end

function DL.IsVeteranLocation(location)
    return location:GetActivityType() == LFG_ACTIVITY_MASTER_DUNGEON
end

-- The finder's location list for an activity type; an empty table when the manager has none yet.
function DL.GetLocations(activityType)
    local manager = ZO_ACTIVITY_FINDER_ROOT_MANAGER
    return manager and manager:GetLocationsData(activityType) or {}
end

local normalizedNames = setmetatable({}, { __mode = "k" })

-- A location's normalised name, computed once.
function DL.GetNormalizedName(location)
    local name = normalizedNames[location]
    if not name then
        name = DL.Normalize(location:GetRawName())
        normalizedNames[location] = name
    end
    return name
end

-- The game's own localised words for the two difficulties, as used by the finder's list headers.
function DL.GetDifficultyName(isVeteran)
    return GetString("SI_LFGACTIVITY", isVeteran and LFG_ACTIVITY_MASTER_DUNGEON or LFG_ACTIVITY_DUNGEON)
end

function DL.CompletedWord()
    return GetString(SI_SCREEN_NARRATION_ACHIEVEMENT_EARNED_ICON_NARRATION)
end

-- The daily quest reset, in seconds after midnight UTC. The game exposes no API for it (only the daily
-- login reward timers, which are a different clock), so it is a constant: 19:00 JST = 10:00 UTC (confirmed
-- by the user); change it here if it ever moves.
DL.DAILY_RESET_UTC_SECONDS = 10 * 60 * 60
local SECONDS_PER_DAY = 24 * 60 * 60

-- The timestamp (seconds, UTC) of the most recent daily reset at or before `now`. Pure: pass `now` to
-- test it; without it the game's clock is used.
function DL.GetLastDailyReset(now)
    now = now or GetTimeStamp()
    local offset = DL.DAILY_RESET_UTC_SECONDS
    return math.floor((now - offset) / SECONDS_PER_DAY) * SECONDS_PER_DAY + offset
end

function DL.IsFinderShowing()
    local finder = DUNGEON_FINDER_KEYBOARD
    return finder ~= nil and finder.fragment ~= nil and finder.fragment:IsShowing()
end

------------------------------
-- Errors and debounced work --
------------------------------

local errorsSeen = {} -- [kind] = { message, printed }

-- Keeps the first error of each kind; it is printed once, and only while debug logging is on.
function DL.ReportError(kind, err)
    local entry = errorsSeen[kind]
    if not entry then
        entry = { message = tostring(err) }
        errorsSeen[kind] = entry
    end
    if DL.debugEnabled and not entry.printed then
        entry.printed = true
        DL.Print("error in %s: %s", kind, entry.message)
    end
end

function DL.SetDebug(enabled)
    DL.debugEnabled = enabled
    if enabled then
        for kind, entry in pairs(errorsSeen) do
            if not entry.printed then
                entry.printed = true
                DL.Print("error in %s: %s", kind, entry.message)
            end
        end
    end
end

-- pcall that records a failure under `kind` instead of dropping it. Returns ok, then the results.
function DL.SafeCall(kind, func, ...)
    local ok, first, second = pcall(func, ...)
    if not ok then
        DL.ReportError(kind, first)
        return false
    end
    return true, first, second
end

local pendingDebounce = {}

-- Runs func once, DEBOUNCE_MS after the first call, however often it is called meanwhile. Only ever used
-- for rebuilding lists or recording data, never for anything that acts on the game.
function DL.Debounce(key, func)
    if pendingDebounce[key] then
        return
    end
    pendingDebounce[key] = true
    zo_callLater(function()
        pendingDebounce[key] = nil
        DL.SafeCall(key, func)
    end, DEBOUNCE_MS)
end

----------------------
-- Saved variables  --
----------------------

-- The raw account-wide settings table of the old DungeonCompletion addon, if it left one.
-- It is only read, never created or modified.
local function ReadOldSettings()
    local old = _G[DL.oldSavedVarsName]
    local profile = type(old) == "table" and old["Default"]
    local account = type(profile) == "table" and profile[GetDisplayName()]
    local settings = type(account) == "table" and account["$AccountWide"]
    return type(settings) == "table" and settings or nil
end

-- Old character records were { name, dungeons = { [zoneId] = questName } }; the new ones list quests.
local function ConvertOldCharacterRecords(oldRecords)
    local converted = {}
    if type(oldRecords) ~= "table" then
        return converted
    end
    for characterId, record in pairs(oldRecords) do
        if type(record) == "table" and type(record.dungeons) == "table" and record.name then
            local quests = {}
            for zoneId, questName in pairs(record.dungeons) do
                quests[#quests + 1] = { name = questName, zones = { zoneId } }
            end
            converted[characterId] = { name = record.name, quests = quests }
        end
    end
    return converted
end

local function ImportOldSettings(saved)
    local old = ReadOldSettings()
    if old then
        for key in pairs(DL.DEFAULTS) do
            if old[key] ~= nil then
                saved[key] = old[key]
            end
        end
        if old.groupBy == "pledge" then -- the old addon's pledge grouping is this addon's quest pinning
            saved.groupBy = DL.GROUP_NONE
            saved.pinQuest = true
        end
        saved.characterQuests = ConvertOldCharacterRecords(old.characterQuests)
    end
    saved.importedFromDungeonCompletion = true
end

local function ValidateSettings(saved)
    if not ZO_IsElementInNumericallyIndexedTable(DL.GROUP_CHOICE_VALUES, saved.groupBy) then
        saved.groupBy = DL.GROUP_NONE
    end
    if not ZO_IsElementInNumericallyIndexedTable(DL.SORT_CHOICE_VALUES, saved.sortBy) then
        saved.sortBy = DL.SORT_GAME
    end
    if type(saved.characterQuests) ~= "table" then
        saved.characterQuests = {}
    end
end

function DL.LoadSettings()
    local saved = ZO_SavedVars:NewAccountWide(DL.savedVarsName, 1, nil, DL.DEFAULTS)
    if not saved.importedFromDungeonCompletion then
        ImportOldSettings(saved)
    end
    ValidateSettings(saved)
    DL.settings = saved
end
