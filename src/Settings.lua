-- The LibAddonMenu-2.0 settings panel (LibAddonMenu-2.0 is a required dependency in the manifest).
local DL = DungeoneersLedger

local ICON_SIZE_MIN, ICON_SIZE_MAX = 12, 32

-- Applies a changed setting to the open finder.
local function OnSettingChanged()
    DL.RefreshFinder()
    DL.RefreshVisibleRows()
end

local function Checkbox(nameId, tooltipId, key, onChange)
    return
    {
        type = "checkbox",
        name = DL.L(nameId),
        tooltip = tooltipId and DL.L(tooltipId) or nil,
        getFunc = function() return DL.settings[key] end,
        setFunc = function(value)
            DL.settings[key] = value
            if onChange then
                onChange()
            end
        end,
        default = DL.DEFAULTS[key],
    }
end

local function Dropdown(nameId, tooltipId, key, choiceIds, choiceValues)
    local choices = {}
    for index, choiceId in ipairs(choiceIds) do
        choices[index] = DL.L(choiceId)
    end
    return
    {
        type = "dropdown",
        name = DL.L(nameId),
        tooltip = DL.L(tooltipId),
        choices = choices,
        choicesValues = choiceValues,
        getFunc = function() return DL.settings[key] end,
        setFunc = function(value)
            DL.settings[key] = value
            OnSettingChanged()
        end,
        default = DL.DEFAULTS[key],
    }
end

-- Tier marker toggles are greyed out while the main tier toggle is off.
local function TierCheckbox(nameId, key)
    local option = Checkbox(nameId, nil, key, OnSettingChanged)
    option.disabled = function() return not DL.settings.showTiers end
    return option
end

local function BuildIconOptions()
    return
    {
        Checkbox(SI_DUNGEONEERSLEDGER_SETTING_SHOW_COMPLETION, SI_DUNGEONEERSLEDGER_SETTING_SHOW_COMPLETION_TT, "showCompletion", OnSettingChanged),
        Checkbox(SI_DUNGEONEERSLEDGER_SETTING_SHOW_TIERS, SI_DUNGEONEERSLEDGER_SETTING_SHOW_TIERS_TT, "showTiers", OnSettingChanged),
        Checkbox(SI_DUNGEONEERSLEDGER_SETTING_SHOW_DATES, SI_DUNGEONEERSLEDGER_SETTING_SHOW_DATES_TT, "showDates", OnSettingChanged),
        Checkbox(SI_DUNGEONEERSLEDGER_SETTING_SHOW_SET_PROGRESS, SI_DUNGEONEERSLEDGER_SETTING_SHOW_SET_PROGRESS_TT, "showSetProgress", OnSettingChanged),
        TierCheckbox(SI_DUNGEONEERSLEDGER_SETTING_TIER_HARDMODE, "tierHardMode"),
        TierCheckbox(SI_DUNGEONEERSLEDGER_SETTING_TIER_SPEEDRUN, "tierSpeedRun"),
        TierCheckbox(SI_DUNGEONEERSLEDGER_SETTING_TIER_NODEATH, "tierNoDeath"),
        TierCheckbox(SI_DUNGEONEERSLEDGER_SETTING_TIER_TRIFECTA, "tierTrifecta"),
        {
            type = "slider",
            name = DL.L(SI_DUNGEONEERSLEDGER_SETTING_ICON_SIZE),
            min = ICON_SIZE_MIN,
            max = ICON_SIZE_MAX,
            step = 1,
            getFunc = function() return DL.settings.iconSize end,
            setFunc = function(value)
                DL.settings.iconSize = value
                OnSettingChanged()
            end,
            default = DL.DEFAULTS.iconSize,
        },
    }
end

local function BuildQuestOptions()
    return
    {
        Checkbox(SI_DUNGEONEERSLEDGER_SETTING_SHOW_QUEST, SI_DUNGEONEERSLEDGER_SETTING_SHOW_QUEST_TT, "showQuest", OnSettingChanged),
        Checkbox(SI_DUNGEONEERSLEDGER_SETTING_SHOW_ALTS, SI_DUNGEONEERSLEDGER_SETTING_SHOW_ALTS_TT, "showAltQuests", OnSettingChanged),
        Checkbox(SI_DUNGEONEERSLEDGER_SETTING_REMEMBER_PLEDGES, SI_DUNGEONEERSLEDGER_SETTING_REMEMBER_PLEDGES_TT, "rememberPledges", OnSettingChanged),
        Checkbox(SI_DUNGEONEERSLEDGER_SETTING_PIN_QUEST, SI_DUNGEONEERSLEDGER_SETTING_PIN_QUEST_TT, "pinQuest", OnSettingChanged),
        Checkbox(SI_DUNGEONEERSLEDGER_SETTING_SELECT_VETERAN, SI_DUNGEONEERSLEDGER_SETTING_SELECT_VETERAN_TT, "selectVeteran"),
        Checkbox(SI_DUNGEONEERSLEDGER_SETTING_SKIP_COMPLETED, SI_DUNGEONEERSLEDGER_SETTING_SKIP_COMPLETED_TT, "skipCompletedOnSelect"),
    }
end

local function BuildListOptions()
    return
    {
        Checkbox(SI_DUNGEONEERSLEDGER_SETTING_HIDE_COMPLETED, SI_DUNGEONEERSLEDGER_SETTING_HIDE_COMPLETED_TT, "hideCompleted", OnSettingChanged),
        Dropdown(SI_DUNGEONEERSLEDGER_SETTING_GROUP_BY, SI_DUNGEONEERSLEDGER_SETTING_GROUP_BY_TT, "groupBy",
            { SI_DUNGEONEERSLEDGER_CHOICE_NONE, SI_DUNGEONEERSLEDGER_CHOICE_COMPLETION, SI_DUNGEONEERSLEDGER_CHOICE_DLC },
            DL.GROUP_CHOICE_VALUES),
        Dropdown(SI_DUNGEONEERSLEDGER_SETTING_SORT_BY, SI_DUNGEONEERSLEDGER_SETTING_SORT_BY_TT, "sortBy",
            { SI_DUNGEONEERSLEDGER_CHOICE_GAME_ORDER, SI_DUNGEONEERSLEDGER_CHOICE_NAME, SI_DUNGEONEERSLEDGER_CHOICE_DLC, SI_DUNGEONEERSLEDGER_CHOICE_COMPLETION,
              SI_DUNGEONEERSLEDGER_CHOICE_DATE_NEWEST, SI_DUNGEONEERSLEDGER_CHOICE_DATE_OLDEST },
            DL.SORT_CHOICE_VALUES),
    }
end

local function Append(target, options)
    for _, option in ipairs(options) do
        target[#target + 1] = option
    end
end

function DL.CreateSettingsMenu()
    local lam = LibAddonMenu2
    if not lam then
        return
    end
    local panelId = DL.name .. "Settings"
    DL.panel = lam:RegisterAddonPanel(panelId,
    {
        type = "panel",
        name = "Dungeoneer's Ledger",
        author = "wasd0109",
        version = DL.version,
    })

    local options = {}
    Append(options, BuildIconOptions())
    Append(options, BuildQuestOptions())
    Append(options, BuildListOptions())
    lam:RegisterOptionControls(panelId, options)
end

function DL.OpenSettings()
    if DL.panel and LibAddonMenu2 then
        LibAddonMenu2:OpenToPanel(DL.panel)
    else
        DL.Print(DL.L(SI_DUNGEONEERSLEDGER_MSG_NEED_LAM))
    end
end
