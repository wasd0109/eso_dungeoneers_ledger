-- The icons next to each dungeon name in the finder list: completion box, tier markers, quest marker.
local DL = DungeoneersLedger

local FINDER_ENTRY_TEMPLATE = "ZO_ActivityFinderTemplateNavigationEntry_Keyboard"
local ICON_SPACING = 4
local TEXT_SPACING = 8
local ICON_DRAW_LEVEL_OFFSET = 10 -- keeps the icons above the row's own controls so they receive the mouse

local CHECKED_TEXTURE = "EsoUI/Art/Buttons/checkbox_white_checked.dds"
local UNCHECKED_TEXTURE = "EsoUI/Art/Buttons/checkbox_white_unchecked.dds"
local PLEDGE_TEXTURE = "EsoUI/Art/Compass/repeatableQuest_icon.dds"

local COMPLETE_COLOR = { 0.3, 0.9, 0.3, 1 }
local INCOMPLETE_COLOR = { 0.6, 0.6, 0.6, 0.7 }
local TIER_INCOMPLETE_ALPHA = 0.45

local rows = setmetatable({}, { __mode = "k" }) -- [row control] = { status, pledge, pips, location }

---------------
-- Controls  --
---------------

local function CreateIcon(row, suffix)
    local icon = CreateControl(row:GetName() .. suffix, row, CT_TEXTURE)
    -- Mouse hit-testing picks the highest layer, so keep the icons above the row's own controls.
    icon:SetDrawLayer(DL_OVERLAY)
    icon:SetDrawLevel(row:GetDrawLevel() + ICON_DRAW_LEVEL_OFFSET)
    icon:SetMouseEnabled(true)
    icon:SetHandler("OnMouseEnter", function(self)
        if self.tooltipText and self.tooltipText ~= "" then
            ZO_Tooltips_ShowTextTooltip(self, RIGHT, self.tooltipText)
        end
    end)
    icon:SetHandler("OnMouseExit", function()
        ZO_Tooltips_HideTextTooltip()
    end)
    -- The icons sit on top of the row, so pass clicks through to the row's own handler.
    icon:SetHandler("OnMouseUp", function(_, button, upInside)
        if upInside then
            ZO_ActivityFinderTemplateNavigationEntryKeyboard_OnClicked(row, button)
        end
    end)
    return icon
end

local function GetRowState(row)
    local state = rows[row]
    if not state then
        state = { status = CreateIcon(row, "DLStatus"), pledge = CreateIcon(row, "DLQuest"), pips = {} }
        state.pledge:SetTexture(PLEDGE_TEXTURE)
        rows[row] = state
    end
    return state
end

-----------------
-- Tooltips    --
-----------------

-- Lines for the completion icon and the tier markers: the dungeon achievement, each extra tier, then the
-- set collection progress of the dungeon.
local function BuildCompletionTooltip(location, achievementId, complete, tiers)
    local lines = {}
    local showDates = DL.settings.showDates
    if achievementId then
        local date = complete and showDates and DL.GetCompletionDate(achievementId) or nil
        if date then
            lines[#lines + 1] = DL.L(SI_DUNGEONEERSLEDGER_TT_COMPLETE_DATED, GetAchievementName(achievementId), date)
        else
            lines[#lines + 1] = DL.L(complete and SI_DUNGEONEERSLEDGER_TT_COMPLETE or SI_DUNGEONEERSLEDGER_TT_INCOMPLETE, GetAchievementName(achievementId))
        end
    end
    for _, tierEntry in ipairs(tiers or {}) do
        local name, _, _, _, tierComplete = GetAchievementInfo(tierEntry.id)
        local state = DL.L(SI_DUNGEONEERSLEDGER_GROUP_INCOMPLETE)
        if tierComplete then
            local date = showDates and DL.GetCompletionDate(tierEntry.id) or nil
            state = date and DL.L(SI_DUNGEONEERSLEDGER_TT_STATE_DATED, DL.CompletedWord(), date) or DL.CompletedWord()
        end
        lines[#lines + 1] = DL.L(SI_DUNGEONEERSLEDGER_TT_TIER, name, state)
    end
    if DL.settings.showSetProgress then
        local unlocked, total = DL.GetSetCollectionProgress(location.zoneId)
        if unlocked then
            lines[#lines + 1] = DL.L(SI_DUNGEONEERSLEDGER_TT_SET_PROGRESS, unlocked, total)
        end
    end
    return table.concat(lines, "\n")
end

-- Lines for the quest marker: the active quest (if any), the other characters with one, and the
-- characters that completed a pledge for the dungeon since the daily reset.
local function BuildQuestTooltip(location, quest, pledgeDoneNames)
    local lines = {}
    if quest then
        lines[#lines + 1] = quest.isPledge and DL.L(SI_DUNGEONEERSLEDGER_TT_PLEDGE) or DL.L(SI_DUNGEONEERSLEDGER_TT_QUEST, quest.name)
        if DL.settings.showAltQuests then
            local names = DL.GetOtherCharactersWithQuest(location)
            if names then
                lines[#lines + 1] = DL.L(SI_DUNGEONEERSLEDGER_TT_ALSO_ACTIVE, table.concat(names, ", "))
            end
        end
    end
    if pledgeDoneNames then
        lines[#lines + 1] = DL.L(SI_DUNGEONEERSLEDGER_TT_PLEDGE_DONE, table.concat(pledgeDoneNames, ", "))
    end
    return table.concat(lines, "\n")
end

------------------
-- Row updating --
------------------

-- Icons are laid out left to right after the dungeon name; each one is anchored to the previous one.
local function CreateLayout(row)
    local layout = { anchorTo = row.text, offsetX = TEXT_SPACING }
    function layout:Place(icon)
        icon:ClearAnchors()
        icon:SetAnchor(LEFT, self.anchorTo, RIGHT, self.offsetX, 0)
        self.anchorTo, self.offsetX = icon, ICON_SPACING
    end
    return layout
end

local function UpdateStatusIcon(state, layout, achievementId, complete, tooltip)
    local icon = state.status
    if not achievementId then
        icon.tooltipText = nil
        icon:SetHidden(true)
        return
    end
    local color = complete and COMPLETE_COLOR or INCOMPLETE_COLOR
    layout:Place(icon)
    icon:SetTexture(complete and CHECKED_TEXTURE or UNCHECKED_TEXTURE)
    icon:SetColor(color[1], color[2], color[3], color[4])
    icon.tooltipText = tooltip
    icon:SetHidden(false)
end

-- One pip per enabled tier, using the achievement's own icon: lit when earned, greyed when not.
local function UpdateTierPips(row, state, layout, tiers, tooltip)
    local size = DL.settings.iconSize
    for index = 1, #DL.TIERS do
        local tierEntry = tiers and tiers[index]
        local pip = state.pips[index]
        if tierEntry and not pip then
            pip = CreateIcon(row, "DLTier" .. index)
            state.pips[index] = pip
        end
        if pip then
            if tierEntry then
                local _, _, _, texture, tierComplete = GetAchievementInfo(tierEntry.id)
                layout:Place(pip)
                pip:SetDimensions(size, size)
                pip:SetTexture(texture)
                pip:SetDesaturation(tierComplete and 0 or 1)
                pip:SetColor(1, 1, 1, tierComplete and 1 or TIER_INCOMPLETE_ALPHA)
                pip.tooltipText = tooltip
                pip:SetHidden(false)
            else
                pip.tooltipText = nil
                pip:SetHidden(true)
            end
        end
    end
end

local function UpdateQuestMarker(state, layout, location)
    local show = DL.settings.showQuest
    local quest = show and DL.FindRelatedQuest(location) or nil
    local doneNames = show and DL.settings.rememberPledges and DL.GetPledgesDoneToday(location) or nil
    local visible = quest ~= nil or doneNames ~= nil
    if visible then
        layout:Place(state.pledge)
    end
    state.pledge.tooltipText = visible and BuildQuestTooltip(location, quest, doneNames) or nil
    state.pledge:SetHidden(not visible)
end

function DL.UpdateRow(row, location)
    if not location or not location.GetRawName or not row.text then
        return
    end
    local state = GetRowState(row)
    state.location = location

    local size = DL.settings.iconSize
    state.status:SetDimensions(size, size)
    state.pledge:SetDimensions(size, size)

    local layout = CreateLayout(row)
    local achievementId = DL.settings.showCompletion and DL.FindAchievementId(location) or nil
    local tiers = DL.GetLocationTiers(location)
    local complete = achievementId and IsAchievementComplete(achievementId) or false
    local tooltip = BuildCompletionTooltip(location, achievementId, complete, tiers)

    UpdateStatusIcon(state, layout, achievementId, complete, tooltip)
    UpdateTierPips(row, state, layout, tiers, tooltip)
    UpdateQuestMarker(state, layout, location)
end

function DL.RefreshVisibleRows()
    for row, state in pairs(rows) do
        if not row:IsHidden() and state.location then
            DL.UpdateRow(row, state.location)
        end
    end
end

-- Re-reads the checkbox state of the visible rows after selections were changed from code.
function DL.SyncRowChecks()
    for row, state in pairs(rows) do
        if not row:IsHidden() and state.location and row.check and not state.location:IsLocked() then
            ZO_CheckButton_SetCheckState(row.check, state.location:IsSelected())
        end
    end
end

-- The tree copies templateInfo.setupFunction when it creates a node, so wrapping it before the finder
-- first builds its list leaves the base setup untouched and runs ours right after it.
function DL.InstallRowHook(tree)
    local templateInfo = tree.templateInfo and tree.templateInfo[FINDER_ENTRY_TEMPLATE]
    if not templateInfo or not templateInfo.setupFunction then
        return false
    end
    local baseSetup = templateInfo.setupFunction
    templateInfo.setupFunction = function(node, control, data, ...)
        baseSetup(node, control, data, ...)
        DL.UpdateRow(control, data)
    end
    return true
end
