local M = {
    api_version = 1,
    module_version = 1
}

local ctx
local catalog = {}
local catalogMeta = {}
local itemsZipPath
local zipIndex
local aliases
local iconCache = {}
local iconCacheOrder = {}
local ICON_CACHE_LIMIT = 64

local function log(message)
    print("[ArzMarket HTML] icons: " .. tostring(message))
end

local function u16(data, pos)
    local a, b = data:byte(pos, pos + 1)
    if not a or not b then return nil end
    return a + b * 256
end

local function u32(data, pos)
    local a, b, c, d = data:byte(pos, pos + 3)
    if not a or not b or not c or not d then return nil end
    return a + b * 256 + c * 65536 + d * 16777216
end

local function fileExists(path)
    if type(path) ~= "string" or path == "" then return false end
    local f = io.open(path, "rb")
    if not f then return false end
    f:close()
    return true
end

local function readAll(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

local function toUtf8(value)
    value = tostring(value or "")
    if ctx and ctx.u8 and type(ctx.u8.encode) == "function" then
        local ok, result = pcall(function() return ctx.u8:encode(value) end)
        if ok and type(result) == "string" then return result end
    end
    return value
end

local function normalizeName(value)
    local raw = tostring(value or "")
    if type(string.nlower) == "function" then
        local ok, lowered = pcall(string.nlower, raw)
        if ok and type(lowered) == "string" then raw = lowered else raw = raw:lower() end
    else
        raw = raw:lower()
    end
    raw = toUtf8(raw)
    raw = raw:gsub("{[%x][%x][%x][%x][%x][%x]}", "")
    raw = raw:gsub("%s+", " ")
    raw = raw:gsub("^%s+", ""):gsub("%s+$", "")
    return raw
end

local function loadCatalog()
    catalog = {}
    catalogMeta = {}

    local root = ctx and type(ctx.getWorkingDirectory) == "function" and ctx.getWorkingDirectory() or "."
    local path = root .. "\\ArzMarket\\data\\item_catalog.json"
    local raw = readAll(path)
    if not raw then
        log("item_catalog.json not found")
        return false
    end

    if type(decodeJson) ~= "function" then
        log("decodeJson unavailable")
        return false
    end

    local ok, parsed = pcall(decodeJson, raw)
    if not ok or type(parsed) ~= "table" or type(parsed.by_name) ~= "table" then
        log("item_catalog.json decode failed")
        return false
    end

    catalog = parsed.by_name
    catalogMeta = {
        version = parsed.version,
        frontend_sha256 = parsed.frontend_sha256,
        items_count = parsed.items_count
    }

    return true
end

local function detectItemsZip()
    local candidates = {}
    if type(getGameDirectory) == "function" then
        local ok, gameDir = pcall(getGameDirectory)
        if ok and type(gameDir) == "string" and gameDir ~= "" then
            candidates[#candidates + 1] = gameDir .. "\\arizona\\items.zip"
            candidates[#candidates + 1] = gameDir .. "\\items.zip"
        end
    end

    local working = ctx and type(ctx.getWorkingDirectory) == "function" and ctx.getWorkingDirectory() or nil
    if type(working) == "string" and working ~= "" then
        local gameDir = working:gsub("[\\/]+moonloader[\\/]?$", "")
        candidates[#candidates + 1] = gameDir .. "\\arizona\\items.zip"
        candidates[#candidates + 1] = gameDir .. "\\items.zip"
    end

    for _, path in ipairs(candidates) do
        if fileExists(path) then
            itemsZipPath = path
            return true
        end
    end

    itemsZipPath = nil
    return false
end

local function findEocd(tail)
    if type(tail) ~= "string" then return nil end
    for pos = #tail - 21, 1, -1 do
        if tail:byte(pos) == 0x50
            and tail:byte(pos + 1) == 0x4B
            and tail:byte(pos + 2) == 0x05
            and tail:byte(pos + 3) == 0x06 then
            return pos
        end
    end
    return nil
end

local function readStoredEntry(file, entry)
    if not file or type(entry) ~= "table" then return nil, "entry_missing" end
    if tonumber(entry.method) ~= 0 then return nil, "compressed_unsupported" end

    file:seek("set", tonumber(entry.local_offset) or 0)
    local localHeader = file:read(30)
    if not localHeader or #localHeader < 30 or u32(localHeader, 1) ~= 0x04034B50 then
        return nil, "bad_local_header"
    end

    local nameLen = u16(localHeader, 27)
    local extraLen = u16(localHeader, 29)
    if not nameLen or not extraLen then return nil, "bad_local_lengths" end

    local dataOffset = (tonumber(entry.local_offset) or 0) + 30 + nameLen + extraLen
    file:seek("set", dataOffset)

    local size = tonumber(entry.comp_size) or 0
    if size < 0 or size > 8 * 1024 * 1024 then return nil, "entry_too_large" end

    local data = file:read(size)
    if not data or #data ~= size then return nil, "short_read" end
    return data
end

local function buildZipIndex()
    if zipIndex then return true end
    if not itemsZipPath and not detectItemsZip() then return false, "items_zip_missing" end

    local f = io.open(itemsZipPath, "rb")
    if not f then return false, "items_zip_open_failed" end

    local totalSize = f:seek("end")
    if not totalSize or totalSize < 22 then
        f:close()
        return false, "items_zip_invalid"
    end

    local tailSize = math.min(totalSize, 65557)
    f:seek("set", totalSize - tailSize)
    local tail = f:read(tailSize)
    local eocdPos = findEocd(tail)
    if not eocdPos then
        f:close()
        return false, "eocd_missing"
    end

    local centralSize = u32(tail, eocdPos + 12)
    local centralOffset = u32(tail, eocdPos + 16)
    if not centralSize or not centralOffset or centralSize <= 0 or centralOffset < 0 then
        f:close()
        return false, "central_directory_invalid"
    end

    f:seek("set", centralOffset)
    local central = f:read(centralSize)
    if not central or #central ~= centralSize then
        f:close()
        return false, "central_directory_short"
    end

    local index = {
        ["24"] = {},
        ["48"] = {},
        ["256"] = {},
        aliases_entry = nil
    }

    local pos = 1
    local parsed = 0
    while pos + 45 <= #central do
        if u32(central, pos) ~= 0x02014B50 then break end

        local method = u16(central, pos + 10)
        local compSize = u32(central, pos + 20)
        local uncompSize = u32(central, pos + 24)
        local nameLen = u16(central, pos + 28)
        local extraLen = u16(central, pos + 30)
        local commentLen = u16(central, pos + 32)
        local localOffset = u32(central, pos + 42)

        if not method or not compSize or not uncompSize or not nameLen or not extraLen or not commentLen or not localOffset then
            break
        end

        local nameStart = pos + 46
        local nameEnd = nameStart + nameLen - 1
        if nameEnd > #central then break end
        local name = central:sub(nameStart, nameEnd)

        local size, id = name:match("^icons/(24)/(%d+)%.webp$")
        if not size then size, id = name:match("^icons/(48)/(%d+)%.webp$") end
        if not size then size, id = name:match("^icons/(256)/(%d+)%.webp$") end

        local entry = {
            method = method,
            comp_size = compSize,
            uncomp_size = uncompSize,
            local_offset = localOffset
        }

        if size and id then
            index[size][id] = entry
        elseif name == "icons/aliases.json" then
            index.aliases_entry = entry
        end

        parsed = parsed + 1
        pos = nameEnd + 1 + extraLen + commentLen
    end

    zipIndex = index

    if index.aliases_entry then
        local rawAliases = readStoredEntry(f, index.aliases_entry)
        if rawAliases then
            aliases = {}
            for sourceId, targetId in rawAliases:gmatch('"(%d+)"%s*:%s*(%d+)') do
                aliases[sourceId] = targetId
            end
        end
    end

    f:close()
    if parsed == 0 then
        zipIndex = nil
        return false, "central_directory_empty"
    end

    return true
end

local function cacheGet(key)
    return iconCache[key]
end

local function cachePut(key, value)
    if iconCache[key] ~= nil then
        iconCache[key] = value
        return
    end

    iconCache[key] = value
    iconCacheOrder[#iconCacheOrder + 1] = key

    while #iconCacheOrder > ICON_CACHE_LIMIT do
        local oldest = table.remove(iconCacheOrder, 1)
        iconCache[oldest] = nil
    end
end

local function resolveAlias(id)
    id = tostring(id or "")
    if id == "" then return nil end
    if not aliases then return id end

    local current = id
    local seen = {}
    for _ = 1, 6 do
        if seen[current] then break end
        seen[current] = true
        local nextId = aliases[current]
        if not nextId then break end
        current = tostring(nextId)
    end
    return current
end

function M.resolveItemId(name)
    local key = normalizeName(name)
    if key == "" then return nil end
    local ids = catalog[key]
    if type(ids) == "number" or type(ids) == "string" then
        return tostring(ids)
    end
    if type(ids) ~= "table" or #ids == 0 then return nil end

    if buildZipIndex() then
        for _, candidate in ipairs(ids) do
            local id = tostring(candidate)
            local resolved = resolveAlias(id)
            if zipIndex["48"][id] or zipIndex["48"][resolved] then
                return id
            end
        end
    end

    return tostring(ids[1])
end

function M.getIcon(size, id)
    size = tostring(size or "")
    if size ~= "24" and size ~= "48" and size ~= "256" then
        return nil, "invalid_size"
    end

    id = tostring(id or ""):match("^(%d+)$")
    if not id then return nil, "invalid_id" end

    local cacheKey = size .. ":" .. id
    local cached = cacheGet(cacheKey)
    if cached then return cached end

    local ok, err = buildZipIndex()
    if not ok then return nil, err end

    local resolved = resolveAlias(id)
    local entry = zipIndex[size][id] or zipIndex[size][resolved]
    if not entry then return nil, "icon_missing" end

    local f = io.open(itemsZipPath, "rb")
    if not f then return nil, "items_zip_open_failed" end
    local data, readErr = readStoredEntry(f, entry)
    f:close()

    if not data then return nil, readErr end
    cachePut(cacheKey, data)
    return data
end

function M.getStatus()
    return {
        catalog_loaded = next(catalog) ~= nil,
        catalog_version = catalogMeta.version,
        catalog_items = catalogMeta.items_count,
        frontend_sha256 = catalogMeta.frontend_sha256,
        items_zip = itemsZipPath ~= nil,
        zip_indexed = zipIndex ~= nil
    }
end

function M.init(context)
    ctx = context
    loadCatalog()
    detectItemsZip()
    return true
end

function M.shutdown()
    catalog = {}
    catalogMeta = {}
    zipIndex = nil
    aliases = nil
    iconCache = {}
    iconCacheOrder = {}
end

return M
