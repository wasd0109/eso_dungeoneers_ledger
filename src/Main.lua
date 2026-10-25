-- Startup, event handling and the slash command.
local DL = DungeoneersLedger

-------------
-- Events  --
-------------

local function NeedsFullRebuildOnAchievement()
    local settings = DL.settings
    return settings.hideCompleted or settings.groupBy == DL.GROUP_COMPLETION or settings.sortBy == DL.SORT_COMPLETION
        or settings.sortBy == DL.SORT_DATE_NEWEST or settings.sortBy == DL.SORT_DATE_OLDEST
end

local function RefreshAfterAchievementChange()
    if NeedsFullRebuildOnAchievement() then
        DL.RefreshFinder()
    else
        DL.RefreshVisibleRows()
        DL.UpdateSummary()
    end
end

-- Set by quest events: the journal is loaded, so an empty one is real. Not set by PLAYER_ACTIVATED alone.
local journalChanged = false

local function RefreshAfterQuestChange()
    local allowEmpty = journalChanged
    journalChanged = false
    DL.RecordCurrentCharacter(allowEmpty)
    if not DL.IsFinderShowing() then
        return
    end
    if DL.settings.pinQuest then
        DL.RefreshFinder()
    else
        DL.RefreshVisibleRows()
    end
end

local function OnAchievementChanged()
    if DL.IsFinderShowing() then
        DL.Debounce("achievement", RefreshAfterAchievementChange)
    end
end

-- The journal is re-read on the next lookup; recording and refreshing wait for the burst of events to end.
local function OnQuestChanged()
    DL.InvalidateQuests()
    DL.Debounce("quest", RefreshAfterQuestChange)
end

local function OnQuestEvent()
    journalChanged = true
    OnQuestChanged()
end

local function RegisterEvents()
    local events = DL.name
    EVENT_MANAGER:RegisterForEvent(events, EVENT_ACHIEVEMENT_UPDATED, OnAchievementChanged)
    EVENT_MANAGER:RegisterForEvent(events, EVENT_ACHIEVEMENTS_UPDATED, OnAchievementChanged)
    EVENT_MANAGER:RegisterForEvent(events, EVENT_QUEST_ADDED, OnQuestEvent)
    EVENT_MANAGER:RegisterForEvent(events, EVENT_QUEST_REMOVED, OnQuestEvent)
    EVENT_MANAGER:RegisterForEvent(events, EVENT_QUEST_COMPLETE, OnQuestEvent)
    EVENT_MANAGER:RegisterForEvent(events, EVENT_QUEST_ADVANCED, OnQuestEvent)
    EVENT_MANAGER:RegisterForEvent(events, EVENT_PLAYER_ACTIVATED, OnQuestChanged)
end

-------------------
-- Slash command --
-------------------

local function OnSlashCommand(argument)
    local command, option = zo_strlower(argument or ""):match("^(%S*)%s*(%S*)")
    if command == "debug" and option == "on" then
        DL.SetDebug(true)
        DL.Print("debug logging on: the first error of each kind is printed once.")
    elseif command == "debug" and option == "off" then
        DL.SetDebug(false)
        DL.Print("debug logging off.")
    elseif command == "debug" then
        DL.PrintDebug()
    elseif command == "settings" then
        DL.OpenSettings()
    else
        DL.Print(DL.L(SI_DUNGEONEERSLEDGER_MSG_USAGE))
    end
end

---------------
-- Start up  --
---------------

local function InstallFinderHooks()
    local tree = DUNGEON_FINDER_KEYBOARD and DUNGEON_FINDER_KEYBOARD.navigationTree
    return tree ~= nil and DL.InstallTreeHooks(tree) and DL.InstallRowHook(tree) and DL.InstallFinderPanel()
end

local function OnAddOnLoaded(_, addonName)
    if addonName ~= DL.name then
        return
    end
    EVENT_MANAGER:UnregisterForEvent(DL.name, EVENT_ADD_ON_LOADED)

    -- The old addon already hooked the finder; installing a second set of hooks would double everything.
    if _G[DL.oldAddonName] ~= nil then
        DL.Print(DL.L(SI_DUNGEONEERSLEDGER_MSG_OLD_ADDON))
        return
    end

    DL.LoadSettings()
    if not InstallFinderHooks() then
        DL.Print(DL.L(SI_DUNGEONEERSLEDGER_MSG_HOOK_FAILED))
        return
    end
    RegisterEvents()
    DL.CreateSettingsMenu()

    SLASH_COMMANDS["/dledger"] = OnSlashCommand
    SLASH_COMMANDS["/dungeoneersledger"] = OnSlashCommand
end

EVENT_MANAGER:RegisterForEvent(DL.name, EVENT_ADD_ON_LOADED, OnAddOnLoaded)
