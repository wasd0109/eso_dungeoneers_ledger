-- Thin ESO API stub layer. World.new(opts) builds a sandbox "game" (globals table the addon runs in), World:load
-- loads the real addon files in manifest order, World:start fires EVENT_ADD_ON_LOADED.
-- Shapes follow the game source (esoui): ZO_Tree, ZO_ActivityFinderRoot_Manager, ZO_ActivityFinderLocation_Specific,
-- ZO_SavedVars, the keyboard dungeon finder's RefreshView / RefreshButtons / TreeEntrySetup.
-- This file is test code only; it is never part of the addon.
World = {}
World.__index = World

local function join(a, b) return (a:gsub("[/\\]+$", "")) .. "/" .. b end

---------------------------------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------------------------------
local Control = {}
Control.__index = function(self, key)
    local method = rawget(Control, key)
    if method ~= nil then return method end
    -- Unknown method: record it (suites check the names against the game docs) and behave as a no-op.
    if type(key) == "string" and key:match("^%u") then
        local world = rawget(self, "__world")
        world.unknownMethods[key] = (world.unknownMethods[key] or 0) + 1
        return function() end
    end
    return nil
end

local function newControl(world, name, parent, ctype)
    if world.controlsByName[name] then error("control '" .. name .. "' already exists", 3) end
    local c = setmetatable({ __world = world, __name = name, __parent = parent, __type = ctype, __hidden = false,
        __text = "", __enabled = true, __handlers = {}, __anchors = {}, __drawLevel = 0, __children = {} }, Control)
    world.controlsByName[name] = c
    if parent then parent.__children[#parent.__children + 1] = c end
    world.stats.controlsCreated = world.stats.controlsCreated + 1
    return c
end

function Control:GetName() return self.__name end
function Control:GetParent() return self.__parent end
function Control:GetNamedChild(suffix) return self.__world.controlsByName[self.__name .. suffix] end
function Control:SetHidden(h) self.__hidden = h and true or false end
function Control:IsHidden() return self.__hidden end
function Control:IsControlHidden() return self.__hidden end
function Control:SetText(t) self.__text = t end
function Control:GetText() return self.__text end
function Control:SetEnabled(e) self.__enabled = e and true or false end
function Control:IsEnabled() return self.__enabled end
function Control:SetHandler(name, fn) self.__handlers[name] = fn end
function Control:GetHandler(name) return self.__handlers[name] end
function Control:SetAnchor(point, rel, relPoint, x, y) self.__anchors[#self.__anchors + 1] = { point, rel, relPoint, x, y } end
function Control:ClearAnchors() self.__anchors = {} end
function Control:SetDimensions(w, h) self.__w, self.__h = w, h end
function Control:SetWidth(w) self.__w = w end
function Control:SetTexture(t) self.__texture = t end
function Control:SetColor(r, g, b, a) self.__color = { r, g, b, a } end
function Control:SetDesaturation(d) self.__desat = d end
function Control:SetDrawLevel(l) self.__drawLevel = l end
function Control:GetDrawLevel() return self.__drawLevel end
function Control:SetMouseEnabled(e) self.__mouse = e end
function Control:GetFontHeight() return 16 end
-- Simulates a left click on a button control (runs its OnClicked handler like the game would).
function Control:Click()
    local handler = self.__handlers.OnClicked
    if not handler or not self.__enabled or self.__hidden then return false end
    local world = self.__world
    local previous = world.clickContext
    world.clickContext = self.__name
    local good, err = pcall(handler, self, 1, false, false, false)
    world.clickContext = previous
    if not good then error(err, 0) end
    return true
end
function Control:Fire(handlerName, ...)
    local h = self.__handlers[handlerName]
    if h then return h(self, ...) end
end

---------------------------------------------------------------------------------------------------
-- Real XML template parsing (the addon's own .xml registers virtual templates)
---------------------------------------------------------------------------------------------------
local function parseXml(src)
    local root = { children = {} }
    local stack = { root }
    for closing, tag, attrs, selfClose in src:gmatch("<(/?)([%w_]+)([^>]-)(/?)>") do
        if closing == "/" then
            table.remove(stack)
        else
            local node = { tag = tag, attrs = {}, children = {} }
            for k, v in attrs:gmatch('([%w_]+)%s*=%s*"([^"]*)"') do node.attrs[k] = v end
            local parent = stack[#stack]
            parent.children[#parent.children + 1] = node
            if selfClose ~= "/" then stack[#stack + 1] = node end
        end
    end
    return root
end
World.parseXml = parseXml

local function collectTemplates(node, out)
    for _, child in ipairs(node.children) do
        if child.attrs and child.attrs.name and child.attrs.virtual == "true" then
            out[child.attrs.name] = child
        end
        collectTemplates(child, out)
    end
end

---------------------------------------------------------------------------------------------------
-- World
---------------------------------------------------------------------------------------------------
local function makeLocationClass(world)
    local Loc = {}
    Loc.__index = Loc
    function Loc:GetId() return self.id end
    function Loc:GetRawName() return self.rawName end
    function Loc:GetActivityType() return self.activityType end
    function Loc:GetEntryType() return self.entryType end
    function Loc:GetZoneId() return self.zoneId end
    function Loc:SetSelected(s) self.isSelected = s end
    function Loc:IsSelected() return self.isSelected end
    function Loc:SetLocked(l) self.isLocked = l end
    function Loc:IsLocked() return self.isLocked end
    function Loc:SetActive(a) self.isActive = a end
    function Loc:IsActive() return self.isActive end
    function Loc:ShouldForceFullPanelKeyboard() return false end
    function Loc:GetNameKeyboard()
        local name = world.store.zo_strformat(world.store.SI_LFG_ACTIVITY_NAME, self.rawName)
        if self.activityType == world.store.LFG_ACTIVITY_MASTER_DUNGEON then name = "|tVET|t " .. name end
        return name
    end
    return Loc
end

local function buildLocation(world, spec)
    local loc = { id = spec.id, activityType = spec.activityType, rawName = spec.name, zoneId = spec.zoneId,
        entryType = spec.entryType or world.store.ZO_ACTIVITY_FINDER_LOCATION_ENTRY_TYPE.SPECIFIC,
        isLocked = spec.locked or false, isActive = spec.active ~= false, isSelected = false,
        sortOrder = spec.sortOrder or spec.id }
    return setmetatable(loc, world.LocationClass)
end

function World.new(opts)
    opts = opts or {}
    local world = setmetatable({ opts = opts, store = {}, reads = {}, created = {}, createdOrder = {}, chat = {},
        controlsByName = {}, unknownMethods = {}, calls = { StartSearch = {}, QueueClick = {} }, stats = { controlsCreated = 0 },
        state = { difficulty = 1, searching = false, groupFinderInUse = false, finderShowing = true },
        clock = 0, timers = {}, timerSeq = 0, handlers = {}, journal = {}, zoneIndex = {}, zoneIdByIndex = {},
        achCats = {}, achInfo = {}, collectibleByActivity = {}, characters = {}, strings = {}, nextStringId = 100000,
        enumStrings = {}, virtualTemplates = {}, clickContext = nil, booting = true }, World)
    local S = world.store
    -- ESO-like global environment: a proxy that logs reads of every global and creations of new ones.
    local G = setmetatable({}, {
        __index = function(_, k) world.reads[k] = true; return S[k] end,
        __newindex = function(_, k, v)
            if S[k] == nil and not world.booting and not world.created[k] then
                world.created[k] = true
                world.createdOrder[#world.createdOrder + 1] = k
            end
            S[k] = v
        end,
    })
    world.G = G
    S._G = G
    for _, name in ipairs({ "assert", "error", "ipairs", "pairs", "next", "pcall", "xpcall", "select", "tonumber", "tostring",
        "type", "unpack", "setmetatable", "getmetatable", "rawget", "rawset", "rawequal", "loadstring", "collectgarbage" }) do
        S[name] = _G[name]
    end
    -- Copies of the standard libraries so that stub or addon code cannot damage the test host.
    local function copy(t) local r = {} for k, v in pairs(t) do r[k] = v end return r end
    S.string, S.table, S.math = copy(string), copy(table), copy(math)
    S.os = { time = os.time, date = os.date, clock = os.clock }
    world:installApi()
    world:installFinder()
    world.booting = false
    -- Baseline of globals that exist before the addon is loaded.
    world.baseline = {}
    for k in pairs(S) do world.baseline[k] = true end
    world.reads = {}
    return world
end

---------------------------------------------------------------------------------------------------
-- API installation
---------------------------------------------------------------------------------------------------
function World:installApi()
    local world, S = self, self.store

    -- Constants (values are arbitrary but distinct; the addon must only use the names).
    local consts = {
        LFG_ACTIVITY_DUNGEON = 2, LFG_ACTIVITY_MASTER_DUNGEON = 3, LFG_ACTIVITY_BATTLE_GROUND_CHAMPION = 4,
        DUNGEON_DIFFICULTY_NONE = 0, DUNGEON_DIFFICULTY_NORMAL = 1, DUNGEON_DIFFICULTY_VETERAN = 2,
        QUEST_MAIN_STEP_INDEX = 1, QUEST_TYPE_NONE = 0, QUEST_TYPE_MAIN_STORY = 3, QUEST_TYPE_DUNGEON = 5,
        QUEST_TYPE_UNDAUNTED_PLEDGE = 11, QUEST_TYPE_GUILD = 2,
        CT_CONTROL = 0, CT_LABEL = 1, CT_TEXTURE = 5, CT_BACKDROP = 4, CT_BUTTON = 3, CT_EDITBOX = 6,
        DL_OVERLAY = 3, TOPLEFT = 3, TOPRIGHT = 9, BOTTOMRIGHT = 12, TOP = 1, LEFT = 2, RIGHT = 8,
        TEXT_ALIGN_RIGHT = 2, ACTIVITY_FINDER_STATUS_NONE = 0, ACTIVITY_FINDER_STATUS_QUEUED = 1, ACTIVITY_FINDER_STATUS_READY_CHECK = 2,
        EVENT_ADD_ON_LOADED = 1, EVENT_ACHIEVEMENT_UPDATED = 2, EVENT_ACHIEVEMENTS_UPDATED = 3, EVENT_QUEST_ADDED = 4,
        EVENT_QUEST_REMOVED = 5, EVENT_QUEST_COMPLETE = 6, EVENT_QUEST_ADVANCED = 7, EVENT_PLAYER_ACTIVATED = 8,
        EVENT_ITEM_SET_COLLECTIONS_UPDATED = 9, EVENT_ITEM_SET_COLLECTION_UPDATED = 10,
    }
    for k, v in pairs(consts) do S[k] = v end
    S.ZO_ACTIVITY_FINDER_LOCATION_ENTRY_TYPE = { SPECIFIC = 1, SET = 2 }

    -- Strings
    local function createStringId(name, text)
        world.nextStringId = world.nextStringId + 1
        S[name] = world.nextStringId
        world.strings[world.nextStringId] = text
    end
    S.ZO_CreateStringId = createStringId
    S.SafeAddString = function(id, text, version)
        if type(id) ~= "number" then error("SafeAddString: unknown string id " .. tostring(id), 2) end
        world.strings[id] = text
    end
    S.GetString = function(a, b)
        if type(a) == "string" then
            local e = world.enumStrings[a]
            return e and e[b] or ""
        end
        return world.strings[a] or ""
    end
    createStringId("SI_UNIT_NAME", "<<1>>")
    createStringId("SI_COLLECTIBLE_NAME_FORMATTER", "<<1>>")
    createStringId("SI_LFG_ACTIVITY_NAME", "<<1>>")
    createStringId("SI_SCREEN_NARRATION_ACHIEVEMENT_EARNED_ICON_NARRATION", "Completed")
    createStringId("SI_SCREEN_NARRATION_EDIT_BOX_SEARCH_NAME", "Search")
    world.enumStrings.SI_LFGACTIVITY = { [S.LFG_ACTIVITY_DUNGEON] = "Normal", [S.LFG_ACTIVITY_MASTER_DUNGEON] = "Veteran" }
    world.enumStrings.SI_DUNGEONDIFFICULTY = { [1] = "Normal", [2] = "Veteran" }
    S.zo_strformat = function(fmt, ...)
        if type(fmt) == "number" then fmt = world.strings[fmt] or "" end
        local args = { ... }
        return (fmt:gsub("<<(%a?:?)(%d+)>>", function(_, n)
            local v = args[tonumber(n)]
            v = v == nil and "" or tostring(v)
            return (v:gsub("%^%a+", ""))
        end))
    end
    S.zo_strlower = function(s) return string.lower(s) end
    S.zo_callLater = function(fn, ms)
        world.timerSeq = world.timerSeq + 1
        if world.opts.syncTimers then fn() return world.timerSeq end
        world.timers[#world.timers + 1] = { id = world.timerSeq, due = world.clock + ms, fn = fn, seq = world.timerSeq, ms = ms }
        world.stats.timersScheduled = (world.stats.timersScheduled or 0) + 1
        return world.timerSeq
    end
    S.GetGameTimeMilliseconds = function() return world.clock end
    S.d = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        world.chat[#world.chat + 1] = table.concat(parts, " ")
    end
    S.ZO_ShallowTableCopy = function(t) local r = {} for k, v in pairs(t) do r[k] = v end return r end
    S.ZO_ClearTable = function(t) for k in pairs(t) do t[k] = nil end end
    S.ZO_IsElementInNumericallyIndexedTable = function(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
    S.SLASH_COMMANDS = {}
    S.ZO_NORMAL_TEXT = { UnpackRGBA = function() return 0.8, 0.8, 0.7, 1 end }
    S.ZO_SELECTED_TEXT = { Colorize = function(_, text) return "|cFFFFFF" .. text .. "|r" end, UnpackRGBA = function() return 1, 1, 1, 1 end }

    -- Events
    S.EVENT_MANAGER = {
        RegisterForEvent = function(_, namespace, event, cb)
            world.handlers[event] = world.handlers[event] or {}
            world.handlers[event][namespace] = cb
            return true
        end,
        UnregisterForEvent = function(_, namespace, event)
            if world.handlers[event] then world.handlers[event][namespace] = nil end
            return true
        end,
    }

    -- Account / characters
    S.GetDisplayName = function() return world.displayName or "@Tester" end
    S.GetUnitName = function() return "Tester^M" end
    S.GetCurrentCharacterId = function() return world.currentCharacterId or "100" end
    S.GetTimeStamp = function() return world.now or 1700000000 end
    S.GetNumCharacters = function() return #world.characters end
    S.GetCharacterInfo = function(i)
        local c = world.characters[i]
        return c.name, 1, 50, 1, 1, 1, c.id, 1
    end

    -- Saved variables (same observable behaviour as ZO_SavedVars: a proxy over the raw table, defaults rawset in)
    local function copyDefaults(sv, defaults)
        for k, v in pairs(defaults) do
            if type(v) == "table" then
                if type(rawget(sv, k)) ~= "table" then rawset(sv, k, copyDefaults({}, v)) else copyDefaults(sv[k], v) end
            elseif rawget(sv, k) == nil then
                rawset(sv, k, v)
            end
        end
        return sv
    end
    S.ZO_SavedVars = {
        NewAccountWide = function(_, name, version, namespace, defaults, profile, displayName)
            displayName = displayName or S.GetDisplayName()
            profile = profile or "Default"
            if S[name] == nil then S[name] = {} end
            local t = S[name]
            t[profile] = t[profile] or {}
            t[profile][displayName] = t[profile][displayName] or {}
            local current = t[profile][displayName]["$AccountWide"] or {}
            t[profile][displayName]["$AccountWide"] = current
            if namespace then current[namespace] = current[namespace] or {}; current = current[namespace] end
            if current.version == nil or current.version < version then
                for k in pairs(current) do current[k] = nil end
            end
            current.version = version
            if defaults then copyDefaults(current, defaults) end
            return setmetatable({ default = defaults }, { __index = current, __newindex = function(_, k, v) current[k] = v end })
        end,
    }

    -- Achievements
    S.GetNumAchievementCategories = function() return #world.achCats end
    S.GetAchievementCategoryInfo = function(top)
        local c = world.achCats[top]
        return c.name, #c.subs, #c.ids, 0, 0, false
    end
    S.GetAchievementSubCategoryInfo = function(top, sub)
        local s = world.achCats[top].subs[sub]
        return s.name, #s.ids, 0, 0, false
    end
    S.GetAchievementId = function(top, sub, index)
        local c = world.achCats[top]
        if sub then return c.subs[sub].ids[index] end
        return c.ids[index]
    end
    S.GetAchievementInfo = function(id)
        local a = world.achInfo[id]
        if not a then return "", "", 0, "", false, "", 0 end
        return a.name, a.desc or "", a.points or 10, a.icon or ("icon_" .. id .. ".dds"), a.complete and true or false, a.date or "", 0
    end
    S.GetAchievementTimestamp = function(id) return (world.achInfo[id] and world.achInfo[id].timestamp) or 0 end
    S.GetAchievementName = function(id) return (world.achInfo[id] and world.achInfo[id].name) or "" end
    S.IsAchievementComplete = function(id) return (world.achInfo[id] and world.achInfo[id].complete) and true or false end

    -- Quest journal
    S.GetNumJournalQuests = function() return #world.journal end
    S.GetJournalQuestName = function(i) return world.journal[i].name end
    S.GetJournalQuestType = function(i) return world.journal[i].type end
    S.GetJournalQuestLocationInfo = function(i)
        local q = world.journal[i]
        return "zone", "objective", q.zoneIndex or 0, 0
    end
    S.GetZoneId = function(zoneIndex) return world.zoneIdByIndex[zoneIndex] or 0 end
    S.GetJournalQuestZoneStoryZoneId = function(i) return world.journal[i].storyZoneId or 0 end
    S.GetJournalQuestNumSteps = function(i) return #world.journal[i].steps end
    S.GetJournalQuestNumConditions = function(i, step) return #world.journal[i].steps[step] end
    S.GetJournalQuestConditionInfo = function(i, step, c) return world.journal[i].steps[step][c], 0, 1, false, false, false, false end

    -- Collectibles / group state
    S.GetRequiredActivityCollectibleId = function(activityId) return world.collectibleByActivity[activityId] or 0 end
    S.GetCollectibleName = function(id) return "Collectible " .. id .. "^n" end
    S.IsCurrentlySearchingForGroup = function() return world.state.searching end
    S.ZO_GroupFinder_IsGroupFinderInUse = function() return world.state.groupFinderInUse end
    S.ZO_GetEffectiveDungeonDifficulty = function() return world.state.difficulty end

    -- Controls
    S.CreateControl = function(name, parent, ctype) return newControl(world, name, parent, ctype) end
    S.CreateControlFromVirtual = function(name, parent, template)
        local tmpl = world.virtualTemplates[template]
        if tmpl == nil then error("virtual control '" .. tostring(template) .. "' not found (is its XML loaded?)", 2) end
        local c = newControl(world, name, parent, S.CT_CONTROL)
        local function build(node, ctl)
            for _, child in ipairs(node.children) do
                if child.tag == "Controls" then
                    build(child, ctl)
                elseif child.attrs and child.attrs.name then
                    local childName = child.attrs.name:gsub("%$%(parent%)", ctl.__name)
                    local sub = newControl(world, childName, ctl, child.tag)
                    build(child, sub)
                end
            end
        end
        build(tmpl, c)
        return c
    end
    for _, t in ipairs({ "ZO_DefaultButton", "ZO_SingleLineEditBackdrop_Keyboard", "ZO_DefaultEditForBackdrop" }) do
        world.virtualTemplates[t] = { tag = "template", attrs = { name = t }, children = {} }
    end
    S.ZO_PostHookHandler = function(control, handlerName, hook)
        local existing = control:GetHandler(handlerName)
        control:SetHandler(handlerName, function(...)
            local r = existing and existing(...)
            hook(...)
            return r
        end)
    end
    S.ZO_Tooltips_ShowTextTooltip = function(control, position, text) world.tooltip = text end
    S.ZO_Tooltips_HideTextTooltip = function() world.tooltip = nil end
    S.ZO_CheckButton_SetCheckState = function(control, state) control.__checked = state and true or false end
    S.ZO_CheckButton_OnClicked = function(control) control.__checked = not control.__checked end
    S.ZO_IconHeader_Setup = function() end
end

---------------------------------------------------------------------------------------------------
-- Dungeon finder: manager, tree, finder object
---------------------------------------------------------------------------------------------------
local function newNode(tree, templateInfo, parentNode, data, childIndent, open)
    local node = { tree = tree, parentNode = parentNode, data = data, childIndent = childIndent, open = open, children = nil }
    if templateInfo then
        node.templateInfo = templateInfo
        node.control = tree:acquire(templateInfo)
        node.control.node = node
        node.setupFunction = templateInfo.setupFunction -- copied when the node is created, like ZO_TreeNode:New
    end
    function node:RefreshControl(userRequested)
        if self.setupFunction then self.setupFunction(self, self.control, self.data, self.open, userRequested, true) end
    end
    function node:IsLeaf() return self.children == nil end
    function node:GetChildren() return self.children end
    node:RefreshControl()
    return node
end

function World:installFinder()
    local world, S = self, self.store
    world.LocationClass = makeLocationClass(world)

    -- ZO_Tree
    local Tree = {}
    Tree.__index = Tree
    function Tree:acquire(info)
        local pool = info.pool
        local ctl = table.remove(pool.free)
        if not ctl then
            pool.n = pool.n + 1
            ctl = info.create(info.template .. pool.n)
        end
        ctl:SetHidden(false)
        pool.used[#pool.used + 1] = ctl
        return ctl
    end
    function Tree:Reset()
        self.previousRoot = self.rootNode
        self.rootNode = newNode(self, nil, nil, nil, 0, true)
        for _, info in pairs(self.templateInfo) do
            for i = #info.pool.used, 1, -1 do
                local c = table.remove(info.pool.used, i)
                c:SetHidden(true)
                c.node = nil
                info.pool.free[#info.pool.free + 1] = c
            end
        end
    end
    function Tree:AddTemplate(template, setupFunction, selectionFunction, equalityFunction, childIndent, childSpacing, createControl)
        self.templateInfo[template] = { template = template, childIndent = childIndent, setupFunction = setupFunction,
            equalityFunction = equalityFunction, pool = { free = {}, used = {}, n = 0 }, create = createControl }
    end
    function Tree:AddNode(template, data, parentNode, selectSoundOverride, open)
        parentNode = parentNode or self.rootNode
        local info = self.templateInfo[template]
        if not info then error("no tree template " .. tostring(template), 2) end
        local node = newNode(self, info, parentNode, data, info.childIndent or 60, open == true)
        parentNode.children = parentNode.children or {}
        parentNode.children[#parentNode.children + 1] = node
        return node
    end
    function Tree:Commit() self.commits = (self.commits or 0) + 1 end

    world.finderPanel = newControl(world, "ZO_DungeonFinder_Keyboard", nil, S.CT_CONTROL)
    local tree = setmetatable({ templateInfo = {} }, Tree)
    tree:Reset()
    local function makeRow(name)
        local row = newControl(world, name, world.finderPanel, S.CT_CONTROL)
        row.text = newControl(world, name .. "Text", row, S.CT_LABEL)
        row.check = newControl(world, name .. "Check", row, S.CT_BUTTON)
        row.lockIcon = newControl(world, name .. "LockIcon", row, S.CT_TEXTURE)
        return row
    end
    local function makeHeader(name)
        local h = newControl(world, name, world.finderPanel, S.CT_CONTROL)
        h.text = newControl(world, name .. "Text", h, S.CT_LABEL)
        h.icon = newControl(world, name .. "Icon", h, S.CT_TEXTURE)
        h.iconHighlight = newControl(world, name .. "IconHighlight", h, S.CT_TEXTURE)
        return h
    end
    -- Same structure as ZO_ActivityFinderTemplate_Keyboard:InitializeNavigationList
    local function TreeHeaderSetup(node, control, name, open)
        control.text:SetText(name)
        control.icon:SetTexture(open and "open" or "closed")
        S.ZO_IconHeader_Setup(control, open, true, true)
    end
    local function TreeEntrySetup(node, control, data, open)
        control.text:SetText(data:GetNameKeyboard())
        local isLocked = data:IsLocked()
        control.enabled = not isLocked and not S.IsCurrentlySearchingForGroup()
        control.check:SetHidden(isLocked)
        control.lockIcon:SetHidden(not isLocked)
        control.text:SetEnabled(control.enabled)
        if not isLocked then S.ZO_CheckButton_SetCheckState(control.check, data:IsSelected()) end
    end
    tree:AddTemplate("ZO_ActivityFinderTemplateNavigationHeader_Keyboard", TreeHeaderSetup, nil, nil, nil, 0, makeHeader)
    tree:AddTemplate("ZO_ActivityFinderTemplateNavigationEntry_Keyboard", TreeEntrySetup, nil, function(l, r) return l.name == r.name end, nil, nil, makeRow)

    -- Manager (ZO_ActivityFinderRoot_Manager shape)
    local mgr = { sortedLocationsData = {}, numSelected = 0, callbacks = {}, activityFinderStatus = 0, playerIsGrouped = false, playerIsLeader = true }
    world.manager = mgr
    function mgr:RegisterCallback(name, fn) self.callbacks[name] = self.callbacks[name] or {}; table.insert(self.callbacks[name], fn) end
    function mgr:FireCallbacks(name, ...) for _, fn in ipairs(self.callbacks[name] or {}) do fn(...) end end
    function mgr:GetLocationsData(activityType)
        if activityType then return self.sortedLocationsData[activityType] end
        return self.sortedLocationsData
    end
    function mgr:ClearSelections()
        local previous = self.numSelected
        for _, locs in pairs(self.sortedLocationsData) do
            for _, loc in ipairs(locs) do loc:SetSelected(false) end
        end
        self.numSelected = 0
        if previous > 0 then self:FireCallbacks("OnSelectionsChanged") end
    end
    function mgr:GetIsCurrentlyInQueue()
        return self.activityFinderStatus == S.ACTIVITY_FINDER_STATUS_QUEUED or self.activityFinderStatus == S.ACTIVITY_FINDER_STATUS_READY_CHECK
    end
    function mgr:ToggleLocationSelected(location) self:SetLocationSelected(location, not location:IsSelected()) end
    function mgr:SetLocationSelected(location, selected)
        if S.IsCurrentlySearchingForGroup() or location:IsSelected() == selected or (location:IsLocked() and selected) then return end
        location:SetSelected(selected)
        self.numSelected = self.numSelected + (selected and 1 or -1)
        self:FireCallbacks("OnSelectionsChanged")
    end
    function mgr:IsAnyLocationSelected() return self.numSelected > 0 end
    function mgr:GetNumLocationsByActivity(activityType, visibleEntryTypes)
        local list = self.sortedLocationsData[activityType]
        if not list then return 0 end
        if not visibleEntryTypes then return #list end
        local n = 0
        for _, loc in ipairs(list) do
            for _, et in ipairs(visibleEntryTypes) do
                if loc:GetEntryType() == et and loc:IsActive() then n = n + 1 break end
            end
        end
        return n
    end
    function mgr:IsLockedByNotLeader() return self.playerIsGrouped and not self.playerIsLeader end
    function mgr:StartSearch()
        local picked = {}
        for _, locs in pairs(self.sortedLocationsData) do
            for _, loc in ipairs(locs) do if loc:IsSelected() then picked[#picked + 1] = loc end end
        end
        table.insert(world.calls.StartSearch, { context = world.clickContext, selected = picked })
        self.activityFinderStatus = S.ACTIVITY_FINDER_STATUS_QUEUED
    end
    S.ZO_ACTIVITY_FINDER_ROOT_MANAGER = mgr
    -- The game's Join Queue handler; instrumented so suites can see who pressed it.
    S.ZO_ActivityFinderTemplateQueueButtonKeyboard_OnClicked = function(control)
        table.insert(world.calls.QueueClick, { context = world.clickContext, trace = debug.traceback("", 2) })
        if not S.IsCurrentlySearchingForGroup() then mgr:StartSearch() end
    end
    S.ZO_ActivityFinderTemplateNavigationEntryKeyboard_OnClicked = function(control, button)
        if control.enabled then
            S.ZO_CheckButton_OnClicked(control.check)
            mgr:ToggleLocationSelected(control.node.data)
        end
    end

    -- Finder object (ZO_ActivityFinderTemplate_Keyboard shape)
    local Finder = {}
    Finder.__index = Finder
    local finder = setmetatable({ navigationTree = tree, control = world.finderPanel,
        activityTypes = { S.LFG_ACTIVITY_DUNGEON, S.LFG_ACTIVITY_MASTER_DUNGEON } }, Finder)
    finder.joinQueueButton = newControl(world, "ZO_DungeonFinder_KeyboardQueueButton", world.finderPanel, S.CT_BUTTON)
    finder.listSection = newControl(world, "ZO_DungeonFinder_KeyboardListSection", world.finderPanel, S.CT_CONTROL)
    finder.fragment = { IsShowing = function() return world.state.finderShowing end }
    function Finder:RefreshButtons()
        local enabled = mgr:IsAnyLocationSelected() and not mgr:GetIsCurrentlyInQueue() and not S.ZO_GroupFinder_IsGroupFinderInUse()
        self.joinQueueButton:SetEnabled(enabled)
    end
    -- The list-building part of ZO_ActivityFinderTemplate_Keyboard:RefreshView for the specific-dungeons filter.
    function Finder:RefreshView()
        if not self.fragment:IsShowing() then return end
        world.stats.refreshViews = (world.stats.refreshViews or 0) + 1
        self.navigationTree:Reset()
        local visible = S.ZO_ACTIVITY_FINDER_LOCATION_ENTRY_TYPE.SPECIFIC
        for _, activityType in ipairs(self.activityTypes) do
            if mgr:GetNumLocationsByActivity(activityType, { visible }) > 0 then
                local headerNode = self.navigationTree:AddNode("ZO_ActivityFinderTemplateNavigationHeader_Keyboard",
                    S.GetString("SI_LFGACTIVITY", activityType), nil, nil, true)
                for _, location in ipairs(mgr:GetLocationsData(activityType)) do
                    if location:GetEntryType() == visible and location:IsActive() and not location:ShouldForceFullPanelKeyboard() then
                        self.navigationTree:AddNode("ZO_ActivityFinderTemplateNavigationEntry_Keyboard", location, headerNode)
                    end
                end
            end
        end
        self.navigationTree:Commit()
        self:RefreshButtons()
    end
    mgr:RegisterCallback("OnSelectionsChanged", function(...) finder:RefreshButtons(...) end)
    S.DUNGEON_FINDER_KEYBOARD = finder
    world.finder = finder
    world.tree = tree
end

---------------------------------------------------------------------------------------------------
-- World helpers used by suites
---------------------------------------------------------------------------------------------------
-- list of { id, activityType, name, zoneId, entryType?, locked?, active?, sortOrder? }
function World:setLocations(list)
    local mgr = self.manager
    mgr.sortedLocationsData = { [self.store.LFG_ACTIVITY_DUNGEON] = {}, [self.store.LFG_ACTIVITY_MASTER_DUNGEON] = {} }
    mgr.numSelected = 0
    for _, spec in ipairs(list) do
        local bucket = mgr.sortedLocationsData[spec.activityType]
        bucket[#bucket + 1] = buildLocation(self, spec)
    end
    for _, bucket in pairs(mgr.sortedLocationsData) do
        table.sort(bucket, function(a, b) return a.sortOrder < b.sortOrder end)
    end
end

function World:locations(activityType) return self.manager.sortedLocationsData[activityType] end
function World:allSpecific()
    local out = {}
    for _, t in ipairs({ self.store.LFG_ACTIVITY_DUNGEON, self.store.LFG_ACTIVITY_MASTER_DUNGEON }) do
        for _, l in ipairs(self.manager.sortedLocationsData[t] or {}) do out[#out + 1] = l end
    end
    return out
end

function World:fire(event, ...)
    local list = {}
    for _, cb in pairs(self.handlers[event] or {}) do list[#list + 1] = cb end
    for _, cb in ipairs(list) do cb(event, ...) end
end

function World:advance(ms)
    local target = self.clock + ms
    while true do
        local best, bi
        for i, t in ipairs(self.timers) do
            if t.due <= target and (not best or t.due < best.due or (t.due == best.due and t.seq < best.seq)) then best, bi = t, i end
        end
        if not best then break end
        table.remove(self.timers, bi)
        self.clock = best.due
        best.fn()
    end
    self.clock = target
end
function World:pendingTimers() return #self.timers end

-- cats = list of { name, list = { {id, name, complete}, ... }, subs = { { name, list = {...} } } }
function World:setAchievements(cats)
    self.achCats = cats
    self.achInfo = {}
    local function reg(ids, infos) for _, a in ipairs(infos) do self.achInfo[a.id] = a; ids[#ids + 1] = a.id end end
    for _, c in ipairs(cats) do
        c.ids, c.subs = {}, c.subs or {}
        reg(c.ids, c.list or {})
        for _, s in ipairs(c.subs) do s.ids = {}; reg(s.ids, s.list or {}) end
    end
end

function World:zoneIndexFor(zoneId)
    if not self.zoneIndex[zoneId] then
        local idx = 1
        for _ in pairs(self.zoneIndex) do idx = idx + 1 end
        self.zoneIndex[zoneId] = idx
        self.zoneIdByIndex[idx] = zoneId
    end
    return self.zoneIndex[zoneId]
end

-- q = { name, kind = "pledge"|"dungeon"|"story"|"other", zoneId, storyZoneId, conditions = { text, ... } }
function World:addQuest(q)
    local S = self.store
    local types = { pledge = S.QUEST_TYPE_UNDAUNTED_PLEDGE, dungeon = S.QUEST_TYPE_DUNGEON,
        story = S.QUEST_TYPE_MAIN_STORY, other = S.QUEST_TYPE_NONE }
    self.journal[#self.journal + 1] = { name = q.name, type = types[q.kind or "other"],
        zoneIndex = q.zoneId and self:zoneIndexFor(q.zoneId) or 0, storyZoneId = q.storyZoneId,
        steps = { q.conditions or { "Do something" } } }
    return #self.journal
end

---------------------------------------------------------------------------------------------------
-- Loading the real addon in manifest order
---------------------------------------------------------------------------------------------------
function World.readManifest(lang)
    local text = host.read(join(CFG.addonRoot, "DungeoneersLedger.addon"))
    local files, meta = {}, {}
    for line in (text .. "\n"):gmatch("(.-)\r?\n") do
        local key, value = line:match("^##%s*([%w]+):%s*(.-)%s*$")
        if key then
            meta[key] = value
        elseif line:match("%S") and not line:match("^%s*#") then
            local f = line:gsub("^%s+", ""):gsub("%s+$", "")
            files[#files + 1] = (f:gsub("%$%(language%)", lang or "en"))
        end
    end
    return files, meta, text
end

function World:loadFile(rel)
    local src = host.read(join(CFG.addonRoot, rel))
    if not src then error("addon file missing: " .. rel) end
    if rel:match("%.xml$") then
        local templates = {}
        collectTemplates(parseXml(src), templates)
        for name, node in pairs(templates) do self.virtualTemplates[name] = node end
        return
    end
    local chunk, err = loadstring(src, "@" .. rel)
    if not chunk then error("syntax error: " .. tostring(err)) end
    setfenv(chunk, self.G)
    chunk()
end

function World:load()
    local files = World.readManifest(self.opts.language)
    self.loadedFiles = {}
    for _, rel in ipairs(files) do
        self:loadFile(rel)
        self.loadedFiles[#self.loadedFiles + 1] = rel
    end
    return self
end

function World:start()
    self:fire(self.store.EVENT_ADD_ON_LOADED, "DungeoneersLedger")
    return self
end

World.joinPath = join
