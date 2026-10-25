-- The Specific Dungeons list: filtering, sorting and grouping, done by wrapping the finder tree's
-- AddNode / Commit / Reset so the game's own list building and templates stay in use.
local DL = DungeoneersLedger

local FINDER_ENTRY_TEMPLATE = "ZO_ActivityFinderTemplateNavigationEntry_Keyboard"
local FINDER_HEADER_TEMPLATE = "ZO_ActivityFinderTemplateNavigationHeader_Keyboard"
local GROUP_INDENT = 30 -- group headers sit this far in; their entries add the tree's default indent on top

-- Sort ranks (lower first) of the groups.
local RANK_QUEST = -1
local RANK_BASE_GAME = 0
local RANK_NOT_COMPLETED, RANK_COMPLETED, RANK_NO_DATA = 1, 2, 3
local RANK_OTHER = 1000

local searchText = ""    -- normalised text of the search box
local pendingEntries = nil -- { order = { headerNode }, byHeader = { [headerNode] = { location } } } while the list builds
local groupTitles = {}   -- [group node key] = header text of the latest build
local deselectedCount = 0

function DL.SetSearchText(text)
    searchText = text
end

function DL.GetSearchText()
    return searchText
end

---------------
-- Filtering --
---------------

-- True when the location is hidden by "hide completed" or the search box.
function DL.IsFilteredOut(location)
    if DL.settings.hideCompleted and DL.IsLocationComplete(location) == true then
        return true
    end
    return searchText ~= "" and not DL.GetNormalizedName(location):find(searchText, 1, true)
end

local function NeedsListRewrite()
    local settings = DL.settings
    return settings.hideCompleted or settings.pinQuest or settings.groupBy ~= DL.GROUP_NONE
        or settings.sortBy ~= DL.SORT_GAME or searchText ~= ""
end

-- A dungeon the user can no longer see must not stay ticked, or Join Queue would still queue it.
-- The game's own SetLocationSelected is used so its selection count and callbacks stay right.
local function DeselectHidden(location)
    if location:IsSelected() then
        ZO_ACTIVITY_FINDER_ROOT_MANAGER:SetLocationSelected(location, false)
        if not location:IsSelected() then
            deselectedCount = deselectedCount + 1
        end
    end
end

--------------
-- Sorting  --
--------------

-- Stable sort of one header's locations by the chosen mode; the game's order breaks ties.
local function SortLocations(locations)
    local mode = DL.settings.sortBy
    if mode == DL.SORT_GAME or #locations < 2 then
        return locations
    end
    local decorated = {}
    for index, location in ipairs(locations) do
        local key
        if mode == DL.SORT_NAME then
            key = DL.GetNormalizedName(location)
        elseif mode == DL.SORT_DLC then
            key = GetRequiredActivityCollectibleId(location:GetId())
        elseif mode == DL.SORT_DATE_NEWEST or mode == DL.SORT_DATE_OLDEST then
            -- Undated (not earned, or no date) dungeons sort last in both directions.
            local timestamp = DL.GetLocationCompletionTimestamp(location)
            key = timestamp and (mode == DL.SORT_DATE_NEWEST and -timestamp or timestamp) or math.huge
        else
            local complete = DL.IsLocationComplete(location)
            key = complete == nil and 2 or (complete and 1 or 0)
        end
        decorated[index] = { location = location, key = key, index = index }
    end
    table.sort(decorated, function(a, b)
        if a.key ~= b.key then
            return a.key < b.key
        end
        return a.index < b.index
    end)
    local sorted = {}
    for index, item in ipairs(decorated) do
        sorted[index] = item.location
    end
    return sorted
end

---------------
-- Grouping  --
---------------

local function GetDlcGroup(location)
    local collectibleId = GetRequiredActivityCollectibleId(location:GetId())
    if collectibleId == 0 then
        return "base", DL.L(SI_DUNGEONEERSLEDGER_GROUP_BASE), RANK_BASE_GAME, true
    end
    return "collectible" .. collectibleId, zo_strformat(SI_COLLECTIBLE_NAME_FORMATTER, GetCollectibleName(collectibleId)), collectibleId, true
end

local function GetCompletionGroup(location)
    local complete = DL.IsLocationComplete(location)
    if complete == nil then
        return "unknown", DL.L(SI_DUNGEONEERSLEDGER_GROUP_UNKNOWN), RANK_NO_DATA, false
    end
    if complete then
        return "done", DL.CompletedWord(), RANK_COMPLETED, false
    end
    return "todo", DL.L(SI_DUNGEONEERSLEDGER_GROUP_INCOMPLETE), RANK_NOT_COMPLETED, false
end

-- Returns group key, title, sort rank and whether the title shows done/total, for a location.
local function GetGroup(location)
    if DL.settings.pinQuest and DL.FindRelatedQuest(location) then
        return "quest", DL.L(SI_DUNGEONEERSLEDGER_GROUP_QUEST), RANK_QUEST, false
    end
    local mode = DL.settings.groupBy
    if mode == DL.GROUP_COMPLETION then
        return GetCompletionGroup(location)
    elseif mode == DL.GROUP_DLC then
        return GetDlcGroup(location)
    end
    return "other", DL.L(SI_DUNGEONEERSLEDGER_GROUP_OTHER), RANK_OTHER, false -- quest pinning is the only grouping
end

local function SetGroupTitles(groups)
    for _, group in ipairs(groups) do
        if group.showProgress then
            group.displayTitle = DL.L(SI_DUNGEONEERSLEDGER_GROUP_PROGRESS, group.title, group.done, #group.entries)
        else
            group.displayTitle = DL.L(SI_DUNGEONEERSLEDGER_GROUP_COUNT, group.title, #group.entries)
        end
    end
end

-- Splits one header's locations into ordered groups, keeping the incoming order inside each group.
-- Returns nil when no grouping applies (nothing enabled, or everything falls into a single group).
local function BuildGroups(locations)
    local settings = DL.settings
    if settings.groupBy == DL.GROUP_NONE and not settings.pinQuest then
        return nil
    end
    local byKey, groups = {}, {}
    for _, location in ipairs(locations) do
        local key, title, rank, showProgress = GetGroup(location)
        local group = byKey[key]
        if not group then
            group = { key = key, title = title, rank = rank, first = #groups, showProgress = showProgress, done = 0, entries = {} }
            byKey[key] = group
            groups[#groups + 1] = group
        end
        group.entries[#group.entries + 1] = location
        if DL.IsLocationComplete(location) == true then
            group.done = group.done + 1
        end
    end
    if #groups < 2 then
        return nil
    end
    table.sort(groups, function(a, b)
        if a.rank ~= b.rank then
            return a.rank < b.rank
        end
        return a.first < b.first
    end)
    SetGroupTitles(groups)
    return groups
end

---------------
-- Tree hook  --
---------------

-- Adds one group as a header node under the NORMAL / VETERAN header. The node's data is a stable key
-- (so the tree's own comparison keeps the collapsed state across rebuilds) and its setup function
-- turns that key into the current title.
local function AddGroupNode(tree, baseAddNode, headerSetup, header, group)
    local nodeKey = "DL:" .. tostring(header.data) .. ":" .. group.key
    groupTitles[nodeKey] = group.displayTitle
    local groupNode = baseAddNode(tree, FINDER_HEADER_TEMPLATE, nodeKey, header, nil, true)
    groupNode.childIndent = GROUP_INDENT
    groupNode.setupFunction = function(node, control, data, ...)
        return headerSetup(node, control, groupTitles[data] or data, ...)
    end
    groupNode:RefreshControl()
    for _, location in ipairs(group.entries) do
        baseAddNode(tree, FINDER_ENTRY_TEMPLATE, location, groupNode)
    end
end

local function CommitPendingEntries(tree, baseAddNode, headerSetup)
    local queued = pendingEntries
    pendingEntries = nil
    if not queued then
        return
    end
    for _, header in ipairs(queued.order) do
        local locations = queued.byHeader[header]
        local sortOk, sorted = DL.SafeCall("sort", SortLocations, locations)
        if sortOk and sorted then
            locations = sorted
        end
        local ok, groups = DL.SafeCall("group", BuildGroups, locations)
        if ok and groups then
            header.childIndent = GROUP_INDENT
            for _, group in ipairs(groups) do
                AddGroupNode(tree, baseAddNode, headerSetup, header, group)
            end
        else
            for _, location in ipairs(locations) do
                baseAddNode(tree, FINDER_ENTRY_TEMPLATE, location, header)
            end
        end
    end
end

-- Holds back a list entry for CommitPendingEntries, or drops it when it is filtered out.
local function QueueEntry(tree, location, header)
    local ok, hidden = DL.SafeCall("filter", DL.IsFilteredOut, location)
    if ok and hidden then
        DL.SafeCall("deselect", DeselectHidden, location)
        return
    end
    pendingEntries = pendingEntries or { order = {}, byHeader = {} }
    local list = pendingEntries.byHeader[header]
    if not list then
        list = {}
        pendingEntries.byHeader[header] = list
        pendingEntries.order[#pendingEntries.order + 1] = header
    end
    list[#list + 1] = location
end

-- The finder builds its list in RefreshView with tree:AddNode for every row and tree:Commit at the end.
-- Anything unexpected falls back to adding the entries in the game's order.
function DL.InstallTreeHooks(tree)
    local baseAddNode = tree.AddNode
    local baseCommit = tree.Commit
    local baseReset = tree.Reset
    local headerInfo = tree.templateInfo and tree.templateInfo[FINDER_HEADER_TEMPLATE]
    if not (headerInfo and headerInfo.setupFunction and baseAddNode and baseCommit and baseReset) then
        return false
    end
    local headerSetup = headerInfo.setupFunction

    tree.Reset = function(self, ...)
        pendingEntries = nil
        deselectedCount = 0
        return baseReset(self, ...)
    end

    tree.AddNode = function(self, template, data, parentNode, ...)
        local isListEntry = template == FINDER_ENTRY_TEMPLATE and parentNode and parentNode.parentNode == self.rootNode
        if isListEntry and NeedsListRewrite() then
            QueueEntry(self, data, parentNode)
            return nil -- the finder ignores the node it gets back for list entries
        end
        return baseAddNode(self, template, data, parentNode, ...)
    end

    tree.Commit = function(self, ...)
        CommitPendingEntries(self, baseAddNode, headerSetup)
        if deselectedCount > 0 then
            DL.Print(DL.L(SI_DUNGEONEERSLEDGER_MSG_DESELECTED, deselectedCount))
            deselectedCount = 0
        end
        return baseCommit(self, ...)
    end
    return true
end

-- Rebuilds the list; does nothing while the finder is hidden (it rebuilds when shown).
function DL.RefreshFinder()
    local finder = DUNGEON_FINDER_KEYBOARD
    if finder and finder.RefreshView then
        finder:RefreshView()
    end
end
