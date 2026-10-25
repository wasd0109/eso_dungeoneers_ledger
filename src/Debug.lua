-- /dledger debug: a dump of how the addon matched dungeons and quests. Developer output, not localised.
local DL = DungeoneersLedger

local function PrintMatches()
    DL.ClearMatchCache()
    local index = DL.GetLibSetsIndex()
    DL.Print("LibSets dungeon data: %s", index and string.format("%d dungeon zones", index.count) or "NOT AVAILABLE (name matching only)")
    local counts = {}
    for _, activityType in ipairs(DL.ACTIVITY_TYPES) do
        for _, location in ipairs(DL.GetLocations(activityType)) do
            if DL.IsSpecificLocation(location) then
                local match = DL.ResolveMatch(location)
                counts[match.source] = (counts[match.source] or 0) + 1
                local tiers = DL.GetLocationTiers(location)
                DL.Print("%s %s (activity %d) [%s] %s%s", DL.IsVeteranLocation(location) and "VET" or "NRM",
                    location:GetRawName(), location:GetId(), match.source,
                    match.id and string.format("%d \"%s\"", match.id, GetAchievementName(match.id)) or "no achievement",
                    tiers and string.format(" (+%d tiers)", #tiers) or "")
            end
        end
    end
    local summary = {}
    for _, source in ipairs(DL.SOURCES) do
        summary[#summary + 1] = string.format("%s=%d", source, counts[source] or 0)
    end
    DL.Print("rows by source: %s", table.concat(summary, " "))
end

local function PrintQuests()
    DL.InvalidateQuests()
    local quests = DL.GetActiveQuests()
    DL.Print("active journal quests: %d", #quests)
    for _, quest in ipairs(quests) do
        local zones = {}
        for index, zoneId in ipairs(quest.zones) do
            zones[index] = tostring(zoneId)
        end
        DL.Print("  %s%s zones: %s", quest.isPledge and "[pledge] " or "", quest.name, table.concat(zones, ","))
    end
    for _, activityType in ipairs(DL.ACTIVITY_TYPES) do
        for _, location in ipairs(DL.GetLocations(activityType)) do
            local quest = DL.IsSpecificLocation(location) and DL.FindRelatedQuest(location)
            if quest then
                DL.Print("  quest dungeon: %s (zone %s) <- %s", location:GetRawName(), tostring(location.zoneId), quest.name)
            end
        end
    end
end

local function PrintCharacters()
    local recorded = 0
    for characterId, record in pairs(DL.settings.characterQuests or {}) do
        recorded = recorded + 1
        DL.Print("  recorded character %s (%s): %d quests", tostring(record.name), tostring(characterId), type(record.quests) == "table" and #record.quests or 0)
    end
    DL.Print("characters with recorded quests: %d", recorded)
end

function DL.PrintDebug()
    PrintMatches()
    PrintQuests()
    PrintCharacters()
end
