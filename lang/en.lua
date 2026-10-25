-- English defaults. Every user-visible string of the addon is defined here; the other lang/<code>.lua
-- files override single entries with SafeAddString, so a missing translation falls back to English.
-- The file is listed twice in effect for English clients (lang/en.lua and lang/$(language).lua), hence the guard.
DungeoneersLedger = DungeoneersLedger or {}
if DungeoneersLedger.stringsLoaded then
    return
end
DungeoneersLedger.stringsLoaded = true

local strings =
{
    -- Settings menu
    SI_DUNGEONEERSLEDGER_SETTING_SHOW_COMPLETION = "Show completion icon",
    SI_DUNGEONEERSLEDGER_SETTING_SHOW_COMPLETION_TT = "Show whether each dungeon's achievement is completed next to its name in the Dungeon Finder.",
    SI_DUNGEONEERSLEDGER_SETTING_SHOW_TIERS = "Show extra achievement markers",
    SI_DUNGEONEERSLEDGER_SETTING_SHOW_TIERS_TT = "Show small markers for the extra veteran achievements of a dungeon (hard mode, speed run, no death, trifecta), lit once earned. Uses the dungeon data from LibSets.",
    SI_DUNGEONEERSLEDGER_SETTING_TIER_HARDMODE = "Hard mode marker",
    SI_DUNGEONEERSLEDGER_SETTING_TIER_SPEEDRUN = "Speed run marker",
    SI_DUNGEONEERSLEDGER_SETTING_TIER_NODEATH = "No death marker",
    SI_DUNGEONEERSLEDGER_SETTING_TIER_TRIFECTA = "Trifecta marker",
    SI_DUNGEONEERSLEDGER_SETTING_SHOW_QUEST = "Show dungeons I have a quest for",
    SI_DUNGEONEERSLEDGER_SETTING_SHOW_QUEST_TT = "Mark dungeons that match one of your active quests: Undaunted pledges and other dungeon quests.",
    SI_DUNGEONEERSLEDGER_SETTING_SHOW_ALTS = "Show which characters have quests for a dungeon",
    SI_DUNGEONEERSLEDGER_SETTING_SHOW_ALTS_TT = "The quest marker's tooltip also lists your other characters that have an active quest for the dungeon. Each character's quests are recorded when you log in and when your quests change.",
    SI_DUNGEONEERSLEDGER_SETTING_PIN_QUEST = "Pin dungeons with a quest to the top",
    SI_DUNGEONEERSLEDGER_SETTING_PIN_QUEST_TT = "Put dungeons you have an active quest for in their own group at the top of the NORMAL and VETERAN lists. Works together with the grouping below.",
    SI_DUNGEONEERSLEDGER_SETTING_SELECT_VETERAN = "Select and queue veteran dungeons instead of normal",
    SI_DUNGEONEERSLEDGER_SETTING_SELECT_VETERAN_TT = "The Select quest dungeons and Select and queue buttons pick the veteran version of each dungeon, whichever difficulty the finder is showing. Off: they follow your current dungeon difficulty.",
    SI_DUNGEONEERSLEDGER_SETTING_SKIP_COMPLETED = "Skip completed when selecting quest dungeons",
    SI_DUNGEONEERSLEDGER_SETTING_SKIP_COMPLETED_TT = "The Select quest dungeons and Select and queue buttons leave out dungeons whose achievement is already completed.",
    SI_DUNGEONEERSLEDGER_SETTING_ICON_SIZE = "Icon size",
    SI_DUNGEONEERSLEDGER_SETTING_HIDE_COMPLETED = "Hide completed dungeons",
    SI_DUNGEONEERSLEDGER_SETTING_HIDE_COMPLETED_TT = "Remove dungeons whose achievement is completed from the Dungeon Finder list.",
    SI_DUNGEONEERSLEDGER_SETTING_GROUP_BY = "Group dungeons by",
    SI_DUNGEONEERSLEDGER_SETTING_GROUP_BY_TT = "Splits the NORMAL and VETERAN lists of the Dungeon Finder into sub-groups.",
    SI_DUNGEONEERSLEDGER_SETTING_SORT_BY = "Sort dungeons by",
    SI_DUNGEONEERSLEDGER_SETTING_SORT_BY_TT = "Orders the dungeons inside each list or group of the Dungeon Finder.",
    SI_DUNGEONEERSLEDGER_CHOICE_GAME_ORDER = "Game order",
    SI_DUNGEONEERSLEDGER_CHOICE_NONE = "None (game order)",
    SI_DUNGEONEERSLEDGER_CHOICE_COMPLETION = "Completion",
    SI_DUNGEONEERSLEDGER_CHOICE_DLC = "DLC / chapter",
    SI_DUNGEONEERSLEDGER_CHOICE_NAME = "Name (A-Z)",

    -- Group headers
    SI_DUNGEONEERSLEDGER_GROUP_INCOMPLETE = "Not completed",
    SI_DUNGEONEERSLEDGER_GROUP_UNKNOWN = "No achievement data",
    SI_DUNGEONEERSLEDGER_GROUP_QUEST = "Dungeons with a quest",
    SI_DUNGEONEERSLEDGER_GROUP_OTHER = "Other dungeons",
    SI_DUNGEONEERSLEDGER_GROUP_BASE = "Base game",
    SI_DUNGEONEERSLEDGER_GROUP_COUNT = "%s (%d)",
    SI_DUNGEONEERSLEDGER_GROUP_PROGRESS = "%s (%d/%d)",

    -- Tooltips
    SI_DUNGEONEERSLEDGER_TT_COMPLETE = "Completed (achievement: %s)",
    SI_DUNGEONEERSLEDGER_TT_INCOMPLETE = "Not completed (achievement: %s)",
    SI_DUNGEONEERSLEDGER_TT_TIER = "%s - %s",
    SI_DUNGEONEERSLEDGER_TT_PLEDGE = "Current Undaunted pledge",
    SI_DUNGEONEERSLEDGER_TT_QUEST = "Quest: %s",
    SI_DUNGEONEERSLEDGER_TT_ALSO_ACTIVE = "Also active on: %s",
    SI_DUNGEONEERSLEDGER_TT_BUTTON_TARGET = "Targets: %s dungeons",

    -- Dungeon Finder panel
    SI_DUNGEONEERSLEDGER_BUTTON_SELECT = "Select quest dungeons",
    SI_DUNGEONEERSLEDGER_BUTTON_SELECT_QUEUE = "Select and queue",
    SI_DUNGEONEERSLEDGER_SUMMARY = "%s: %s",
    SI_DUNGEONEERSLEDGER_SUMMARY_PART = "%s %d/%d",

    -- Chat messages
    SI_DUNGEONEERSLEDGER_MSG_ALREADY_QUEUED = "already queued or searching; leave the queue first.",
    SI_DUNGEONEERSLEDGER_MSG_GROUP_FINDER = "the Group Finder is in use; the Dungeon Finder queue is unavailable.",
    SI_DUNGEONEERSLEDGER_MSG_NOT_LEADER = "only the group leader can select dungeons.",
    SI_DUNGEONEERSLEDGER_MSG_NONE_AVAILABLE = "no available %s dungeons with a quest.",
    SI_DUNGEONEERSLEDGER_MSG_SELECTED = "selected %d %s dungeon(s) with a quest.",
    SI_DUNGEONEERSLEDGER_MSG_SKIPPED = "skipped quest dungeons that are locked or unavailable as %s: %s",
    SI_DUNGEONEERSLEDGER_MSG_DESELECTED = "deselected %d dungeon(s) hidden by the list filter so they are not queued.",
    SI_DUNGEONEERSLEDGER_MSG_SELECT_FAILED = "could not select quest dungeons: %s",
    SI_DUNGEONEERSLEDGER_MSG_HOOK_FAILED = "could not hook the Dungeon Finder; addon disabled.",
    SI_DUNGEONEERSLEDGER_MSG_OLD_ADDON = "the old DungeonCompletion addon is still enabled. Disable or delete it and reload the UI; Dungeoneer's Ledger is inactive until then.",
    SI_DUNGEONEERSLEDGER_MSG_NEED_LAM = "settings need the LibAddonMenu-2.0 addon, which is not loaded.",
    SI_DUNGEONEERSLEDGER_MSG_USAGE = "usage: /dledger settings | debug [on|off]",
}

for stringId, text in pairs(strings) do
    ZO_CreateStringId(stringId, text)
end
