-- Controls added to the keyboard Dungeon Finder panel: search box, completion summary, and the
-- "Select quest dungeons" / "Select and queue" buttons.
local DL = DungeoneersLedger

local SEARCH_ROW_HEIGHT = 34   -- height of the search / summary row above the list
local SEARCH_WIDTH = 200
local SEARCH_OFFSET_X, SEARCH_OFFSET_Y = 4, 2
local SUMMARY_OFFSET_X, SUMMARY_OFFSET_Y = 12, 4
local SUMMARY_MARGIN_RIGHT = 10
local ACTION_AREA_HEIGHT = 100 -- the game keeps this much room below the list for its Join Queue button
local BUTTON_WIDTH = 190
local BUTTON_SPACING = 10

local summaryLabel = nil

---------------------------------
-- Select / queue quest dungeons --
---------------------------------

-- With the setting on the veteran entries are always targeted, whatever the finder currently shows.
-- Normal and veteran dungeons are separate location entries (different activity ids), so choosing the
-- activity type is enough; the group's difficulty setting is neither read for the search nor changed.
local function IsTargetVeteran()
    return DL.settings.selectVeteran or ZO_GetEffectiveDungeonDifficulty() == DUNGEON_DIFFICULTY_VETERAN
end

local function GetDungeonName(location)
    return zo_strformat("<<1>>", location:GetRawName())
end

-- Zones that have a veteran entry in the finder, to spot dungeons that have no veteran version.
local function GetVeteranZones()
    local zones = {}
    for _, location in ipairs(DL.GetLocations(LFG_ACTIVITY_MASTER_DUNGEON)) do
        if location.zoneId then
            zones[location.zoneId] = true
        end
    end
    return zones
end

-- Quest dungeons of the target type that can be ticked, and the names of those that cannot
-- (locked, inactive, or without a veteran version).
local function CollectQuestDungeons(activityType, isVeteran)
    local candidates, skipped = {}, {}
    for _, location in ipairs(DL.GetLocations(activityType)) do
        if DL.IsSpecificLocation(location) and DL.FindRelatedQuest(location) then
            if location:IsLocked() or not location:IsActive() then
                skipped[#skipped + 1] = GetDungeonName(location)
            elseif not (DL.settings.skipCompletedOnSelect and DL.IsLocationComplete(location) == true)
                and not DL.IsFilteredOut(location) then
                candidates[#candidates + 1] = location
            end
        end
    end
    if isVeteran then
        local veteranZones = GetVeteranZones()
        for _, location in ipairs(DL.GetLocations(LFG_ACTIVITY_DUNGEON)) do
            if DL.IsSpecificLocation(location) and location:IsActive() and DL.FindRelatedQuest(location)
                and not (location.zoneId and veteranZones[location.zoneId]) then
                skipped[#skipped + 1] = GetDungeonName(location)
            end
        end
    end
    return candidates, skipped
end

-- Returns an error message id when the game would not allow selecting or queueing right now.
local function GetBlockingMessage(manager)
    if IsCurrentlySearchingForGroup() or manager:GetIsCurrentlyInQueue() then
        return SI_DUNGEONEERSLEDGER_MSG_ALREADY_QUEUED
    end
    if ZO_GroupFinder_IsGroupFinderInUse() then
        return SI_DUNGEONEERSLEDGER_MSG_GROUP_FINDER
    end
    if manager:IsLockedByNotLeader() then
        return SI_DUNGEONEERSLEDGER_MSG_NOT_LEADER
    end
    return nil
end

-- Ticks the quest dungeons of the target difficulty exactly as if their checkboxes had been clicked
-- (the game's SetLocationSelected refuses locked ones). With andQueue it then presses the game's own
-- Join Queue handler. Runs only from a button click; the game's checks and alert text decide the rest.
local function SelectQuestDungeons(andQueue)
    local manager = ZO_ACTIVITY_FINDER_ROOT_MANAGER
    local blocking = GetBlockingMessage(manager)
    if blocking then
        DL.Print(DL.L(blocking))
        return
    end

    DL.InvalidateQuests()
    local isVeteran = IsTargetVeteran()
    local difficultyName = DL.GetDifficultyName(isVeteran)
    local candidates, skipped = CollectQuestDungeons(isVeteran and LFG_ACTIVITY_MASTER_DUNGEON or LFG_ACTIVITY_DUNGEON, isVeteran)
    if #skipped > 0 then
        DL.Print(DL.L(SI_DUNGEONEERSLEDGER_MSG_SKIPPED, difficultyName, table.concat(skipped, ", ")))
    end
    if #candidates == 0 then
        DL.Print(DL.L(SI_DUNGEONEERSLEDGER_MSG_NONE_AVAILABLE, difficultyName))
        return
    end

    manager:ClearSelections() -- only now, so a failed attempt never wipes the user's own ticks
    local selected = 0
    for _, location in ipairs(candidates) do
        manager:SetLocationSelected(location, true)
        if location:IsSelected() then
            selected = selected + 1
        end
    end
    DL.SyncRowChecks()
    if selected == 0 then
        DL.Print(DL.L(SI_DUNGEONEERSLEDGER_MSG_NONE_AVAILABLE, difficultyName))
        return
    end
    DL.Print(DL.L(SI_DUNGEONEERSLEDGER_MSG_SELECTED, selected, difficultyName))

    if andQueue and manager:IsAnyLocationSelected() then
        ZO_ActivityFinderTemplateQueueButtonKeyboard_OnClicked(DUNGEON_FINDER_KEYBOARD.joinQueueButton)
    end
end

local function RunSelect(andQueue)
    local ok, err = pcall(SelectQuestDungeons, andQueue)
    if not ok then
        DL.Print(DL.L(SI_DUNGEONEERSLEDGER_MSG_SELECT_FAILED, tostring(err)))
        DL.ReportError("select", err)
    end
end

-------------
-- Summary --
-------------

-- "Completed: Normal 27/41 - Veteran 18/41", the current difficulty highlighted.
local function UpdateSummary()
    if not summaryLabel then
        return
    end
    local currentIsVeteran = ZO_GetEffectiveDungeonDifficulty() == DUNGEON_DIFFICULTY_VETERAN
    local parts = {}
    for _, isVeteran in ipairs({ false, true }) do
        local done, total = 0, 0
        for _, location in ipairs(DL.GetLocations(isVeteran and LFG_ACTIVITY_MASTER_DUNGEON or LFG_ACTIVITY_DUNGEON)) do
            if DL.IsSpecificLocation(location) and location:IsActive() then
                total = total + 1
                if DL.IsLocationComplete(location) == true then
                    done = done + 1
                end
            end
        end
        local part = DL.L(SI_DUNGEONEERSLEDGER_SUMMARY_PART, DL.GetDifficultyName(isVeteran), done, total)
        parts[#parts + 1] = isVeteran == currentIsVeteran and ZO_SELECTED_TEXT:Colorize(part) or part
    end
    summaryLabel:SetText(DL.L(SI_DUNGEONEERSLEDGER_SUMMARY, DL.CompletedWord(), table.concat(parts, " - ")))
end

function DL.UpdateSummary()
    DL.SafeCall("summary", UpdateSummary)
end

---------------
-- Controls  --
---------------

local function CreateButton(panel, anchorButton, name, text, anchorPoint, relativePoint, offsetX, andQueue)
    local button = CreateControlFromVirtual(name, panel, "ZO_DefaultButton")
    button:SetText(text)
    button:SetWidth(BUTTON_WIDTH)
    button:SetAnchor(anchorPoint, anchorButton, relativePoint, offsetX, 0)
    button:SetHandler("OnClicked", function() RunSelect(andQueue) end)
    ZO_PostHookHandler(button, "OnMouseEnter", function(self)
        ZO_Tooltips_ShowTextTooltip(self, TOP, DL.L(SI_DUNGEONEERSLEDGER_TT_BUTTON_TARGET, DL.GetDifficultyName(IsTargetVeteran())))
    end)
    ZO_PostHookHandler(button, "OnMouseExit", function()
        ZO_Tooltips_HideTextTooltip()
    end)
    return button
end

-- Same structure as the game's own search boxes (see achievements.xml); the template is in DungeoneersLedger.xml.
local function CreateSearchBox(panel)
    local backdrop = CreateControlFromVirtual("DungeoneersLedgerSearch", panel, "DungeoneersLedgerSearchTemplate")
    backdrop:ClearAnchors()
    backdrop:SetAnchor(TOPLEFT, panel, TOPLEFT, SEARCH_OFFSET_X, SEARCH_OFFSET_Y)
    backdrop:SetWidth(SEARCH_WIDTH)
    local edit = backdrop:GetNamedChild("Box")
    edit:SetDefaultText(GetString(SI_SCREEN_NARRATION_EDIT_BOX_SEARCH_NAME))
    edit:SetHandler("OnTextChanged", function(control)
        local text = DL.Normalize(control:GetText())
        if text ~= DL.GetSearchText() then
            DL.SetSearchText(text)
            DL.Debounce("search", DL.RefreshFinder) -- only rebuilds the list
        end
    end)
    return backdrop
end

local function CreateSummaryLabel(panel, searchBox)
    local label = CreateControl("DungeoneersLedgerSummary", panel, CT_LABEL)
    label:SetFont("ZoFontWinH4")
    label:SetColor(ZO_NORMAL_TEXT:UnpackRGBA())
    label:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
    label:SetAnchor(TOPLEFT, searchBox, TOPRIGHT, SUMMARY_OFFSET_X, SUMMARY_OFFSET_Y)
    label:SetAnchor(TOPRIGHT, panel, TOPRIGHT, -SUMMARY_MARGIN_RIGHT, SUMMARY_OFFSET_Y)
    return label
end

-- The list starts below our search / summary row instead of at the panel's top edge.
local function MakeRoomForSearchRow(finder, panel)
    finder.listSection:ClearAnchors()
    finder.listSection:SetAnchor(TOPLEFT, panel, TOPLEFT, 0, SEARCH_ROW_HEIGHT)
    finder.listSection:SetAnchor(BOTTOMRIGHT, panel, BOTTOMRIGHT, 0, -ACTION_AREA_HEIGHT)
end

local function CreateFinderUI(finder)
    local panel, queueButton = finder.control, finder.joinQueueButton
    if not panel or not queueButton or not finder.listSection then
        return nil
    end
    local searchBox = CreateSearchBox(panel)
    summaryLabel = CreateSummaryLabel(panel, searchBox)
    MakeRoomForSearchRow(finder, panel)
    return
    {
        buttons =
        {
            CreateButton(panel, queueButton, "DungeoneersLedgerSelectButton", DL.L(SI_DUNGEONEERSLEDGER_BUTTON_SELECT), TOPRIGHT, TOPLEFT, -BUTTON_SPACING, false),
            CreateButton(panel, queueButton, "DungeoneersLedgerQueueButton", DL.L(SI_DUNGEONEERSLEDGER_BUTTON_SELECT_QUEUE), TOPLEFT, TOPRIGHT, BUTTON_SPACING, true),
        },
        listControls = { searchBox, summaryLabel },
    }
end

-- Our controls follow the game's Join Queue button: shown with it in list view; the buttons are
-- disabled while queued.
function DL.InstallFinderPanel()
    local finder = DUNGEON_FINDER_KEYBOARD
    local ui = finder and CreateFinderUI(finder)
    if not ui then
        return false
    end
    local baseRefreshButtons = finder.RefreshButtons
    finder.RefreshButtons = function(self, ...)
        baseRefreshButtons(self, ...)
        local hidden = self.joinQueueButton:IsControlHidden() or self.listSection:IsControlHidden()
        local enabled = not ZO_ACTIVITY_FINDER_ROOT_MANAGER:GetIsCurrentlyInQueue()
        for _, button in ipairs(ui.buttons) do
            button:SetHidden(hidden)
            button:SetEnabled(enabled)
        end
        for _, control in ipairs(ui.listControls) do
            control:SetHidden(hidden)
        end
        if not hidden then
            DL.UpdateSummary()
        end
    end
    return true
end
