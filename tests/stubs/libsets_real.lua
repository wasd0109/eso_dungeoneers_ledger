-- Reads the REAL LibSets dungeon table from the installed LibSets addon at test time (never copied into this
-- project: LibSets is CC BY-NC-ND). Only the dungeonZoneMapping block of Data/LibSets_Data_Zones.lua is evaluated.
LibSetsReal = {}

local cached, cachedReason

function LibSetsReal.load()
    if cached or cachedReason then return cached, cachedReason end
    local base = CFG.libsetsPath
    local path = World.joinPath(base, "Data/LibSets_Data_Zones.lua")
    local src = host.read(path)
    if not src then
        cachedReason = "LibSets not found at " .. tostring(base) .. " (set ESO_LIBSETS_PATH); real-data tests skipped"
        return nil, cachedReason
    end
    local lines, names, order = {}, {}, {}
    local inBlock = false
    for line in (src .. "\n"):gmatch("(.-)\r?\n") do
        if not inBlock then
            if line:find("setDataPreloaded[LIBSETS_TABLEKEY_DUNGEON_ZONE_MAPPING]", 1, true) and line:find("= {", 1, true) then
                inBlock = true
            end
        elseif line:match("^%s*}%s*$") then
            break
        else
            lines[#lines + 1] = line
            local zone, name = line:match("^%s*%[(%d+)%]=.-%-%-%s*(.-)%s*$")
            if zone then names[tonumber(zone)] = name; order[#order + 1] = tonumber(zone) end
        end
    end
    if #lines == 0 then
        cachedReason = "dungeonZoneMapping block not found in " .. path .. "; real-data tests skipped"
        return nil, cachedReason
    end
    local code = "return {\n" .. table.concat(lines, "\n") .. "\n}"
    local chunk, err = loadstring(code, "=LibSets dungeonZoneMapping")
    if not chunk then
        cachedReason = "could not parse LibSets dungeon table: " .. tostring(err)
        return nil, cachedReason
    end
    local version = (host.read(World.joinPath(base, "LibSets.addon")) or ""):match("##%s*Version:%s*(%S+)")
    cached = { code = code, names = names, order = order, chunk = chunk, version = version or "?" }
    return cached
end

-- A fresh copy of the table per world (tests may not leak mutations into each other).
function LibSetsReal.mapping()
    local data = assert(LibSetsReal.load())
    local mapping = loadstring(data.code)()
    return mapping
end

-- Stubbed `LibSets` object as the addon reads it: fullyLoaded, setDataPreloaded[...] and GetDungeonZoneData.
function LibSetsReal.install(world, mapping, fullyLoaded)
    local S = world.store
    S.LIBSETS_TABLEKEY_DUNGEON_ZONE_MAPPING = "dungeonZoneMapping"
    local lib = { fullyLoaded = fullyLoaded ~= false, setDataPreloaded = { dungeonZoneMapping = mapping } }
    -- Same semantics as LibSets.GetDungeonZoneData: nil for unknown zones, otherwise a shallow copy.
    function lib.GetDungeonZoneData(zoneId)
        local data = zoneId ~= nil and mapping[zoneId] or nil
        if data == nil then return nil end
        local copy = {}
        for k, v in pairs(data) do copy[k] = v end
        return copy
    end
    function lib.IsDungeonZoneId(zoneId) return mapping[zoneId] ~= nil end
    S.LibSets = lib
    return lib
end
