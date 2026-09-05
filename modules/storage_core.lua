local M = { api_version = 1, module_version = 3 }
local context = {}
local u8 = { decode = function(_, value) if type(context.fromUtf8) == "function" then return context.fromUtf8(value) end return value end }
local function storageWorkingDirectory() if type(context.getWorkingDirectory) == "function" then return context.getWorkingDirectory() end return "." end
local function sendNotify(text) if type(context.notify) == "function" then return context.notify(text) end end
local function get_cef(source) if type(context.executeCef) == "function" then return context.executeCef(source) end end

local acef_ok, acef = pcall(require, "arizona-events")
local DATA_DIR_NAME = "InventoryFinder"
local SETTINGS_FILE = "settings.json"
local DATABASE_FILE = "inventory_index.json"
local DATABASE_BACKUP_FILE = "inventory_index.json.bak"
local DEBUG_FILE = "debug_cef.log"
local CATEGORY_FILE = "item_categories.json"
local CATEGORY_BACKUP_FILE = "item_categories.json.bak"

local STORAGE_KIND = {
    PLAYER_INVENTORY = "player_inventory",
    HOUSE_CLOSET = "house_closet",
    HOUSE_OBJECT = "house_object",
    WAREHOUSE = "warehouse",
    VEHICLE_TRUNK = "vehicle_trunk",
    UNKNOWN = "unknown"
}

local STORAGE_CAPTURE_KIND_OPTIONS = {
    { value = STORAGE_KIND.VEHICLE_TRUNK, label = "Машина: багажник" },
    { value = STORAGE_KIND.HOUSE_CLOSET, label = "Дом: шкаф" },
    { value = STORAGE_KIND.HOUSE_OBJECT, label = "Дом: объект возле дома" },
    { value = STORAGE_KIND.WAREHOUSE, label = "Складское помещение" }
}

local STORAGE_CAPTURE_KIND_SET = {
    [STORAGE_KIND.VEHICLE_TRUNK] = true,
    [STORAGE_KIND.HOUSE_CLOSET] = true,
    [STORAGE_KIND.HOUSE_OBJECT] = true,
    [STORAGE_KIND.WAREHOUSE] = true
}

-- Character/equipment/shop inventory types that must not be mixed into external storage.
local NON_STORAGE_INVENTORY_TYPES = {
    [1] = true, [2] = true, [10] = true, [13] = true, [17] = true,
    [18] = true, [19] = true, [22] = true, [28] = true, [36] = true
}

local DEFAULT_SETTINGS = {
    schema_version = 2,
    debug = {
        enabled = true,
        max_log_bytes = 2 * 1024 * 1024,
        max_payload_chars = 16000
    },
    scan = {
        player_inventory_type = 1,
        debounce_ms = 450,
        snapshot_timeout_ms = 5000
    },
    houses = {},
    warehouses = {},
    vehicles = {},
    category_overrides = {},
    bindings = {
        fingerprints = {}
    },
    pending_binding = nil
}

local DEFAULT_DATABASE = {
    schema_version = 2,
    storages = {}
}

local CATEGORY = {
    ACCESSORIES = "accessories",
    CASES = "cases",
    SKINS = "skins",
    WEAPONS = "weapons",
    CERTIFICATES = "certificates",
    TUNING = "tuning",
    UPGRADES = "upgrades",
    RESOURCES = "resources",
    OBJECTS = "objects",
    SHARDS = "shards",
    OTHER = "other"
}

local VALID_CATEGORIES = {
    [CATEGORY.ACCESSORIES] = true,
    [CATEGORY.CASES] = true,
    [CATEGORY.SKINS] = true,
    [CATEGORY.WEAPONS] = true,
    [CATEGORY.CERTIFICATES] = true,
    [CATEGORY.TUNING] = true,
    [CATEGORY.UPGRADES] = true,
    [CATEGORY.RESOURCES] = true,
    [CATEGORY.OBJECTS] = true,
    [CATEGORY.SHARDS] = true,
    [CATEGORY.OTHER] = true
}

local DEFAULT_CATEGORY_MAP = {
    schema_version = 1,
    item_ids = {},
    model_ids = {},
    server_types = {},
    name_rules = {
        { pattern = "ларец", category = CATEGORY.CASES },
        { pattern = "сундук", category = CATEGORY.CASES },
        { pattern = "аксессуар", category = CATEGORY.ACCESSORIES },
        { pattern = "скин", category = CATEGORY.SKINS },
        { pattern = "оруж", category = CATEGORY.WEAPONS },
        { pattern = "сертификат", category = CATEGORY.CERTIFICATES },
        { pattern = "тюнинг", category = CATEGORY.TUNING },
        { pattern = "улучшен", category = CATEGORY.UPGRADES },
        { pattern = "осколок", category = CATEGORY.SHARDS },
        { pattern = "объект", category = CATEGORY.OBJECTS },
        { pattern = "компонент", category = CATEGORY.RESOURCES },
        { pattern = "ресурс", category = CATEGORY.RESOURCES },
        { pattern = "материя", category = CATEGORY.RESOURCES },
        { pattern = "сплав", category = CATEGORY.RESOURCES },
        { pattern = "ткань", category = CATEGORY.RESOURCES },
        { pattern = "камень", category = CATEGORY.RESOURCES },
        { pattern = "руда", category = CATEGORY.RESOURCES }
    }
}

local app = {
    ready = false,
    settings = nil,
    database = nil,
    data_dir = nil,
    settings_path = nil,
    database_path = nil,
    database_backup_path = nil,
    debug_path = nil,
    category_path = nil,
    category_backup_path = nil,
    category_map = nil,
    item_names_path = nil,
    item_names_backup_path = nil,
    item_names = {},
    search_index = {},
    search_index_dirty = true,
    session_id = tostring(os.time()) .. ":" .. tostring(math.random(100000, 999999)),
    player_inventory_visible = false,
    active_view = nil,
    character_tab = nil,
    snapshot = nil,
    last_event = nil,
    last_routed_event_key = nil,
    last_routed_event_ms = 0,
    last_scan = nil,
    last_error = nil,
    debug_event_count = 0,
    player_scan_active = false,
    visible_rows = {},
    visible_rows_dirty = true,
    external_candidate = nil,
    external_recent_groups = {},
    external_ui_visible = false,
    external_kind_hint = nil,
    external_visible_ms = 0,
    external_last_payload = nil,
    manual_scan = {
        requested = false,
        started_ms = 0,
        finish_after_ms = 0,
        dialog_open = false,
        snapshot = nil,
        selected_kind = STORAGE_KIND.UNKNOWN,
        suggested_name = "",
        name_initialized = false,
        error = nil
    }
}

local function nowMs()
    local ok, value = pcall(context.getGameTimer or getGameTimer)
    if ok and type(value) == "number" then
        return value
    end
    return math.floor(os.clock() * 1000)
end

local function unixTime()
    return os.time()
end


local function safeString(value, default)
    if value == nil then
        return default or ""
    end
    if type(value) == "string" then
        return value
    end
    local ok, result = pcall(tostring, value)
    if ok and result then
        return result
    end
    return default or ""
end

local CYRILLIC_LOWER_MAP = {
    ["А"] = "а", ["Б"] = "б", ["В"] = "в", ["Г"] = "г", ["Д"] = "д",
    ["Е"] = "е", ["Ё"] = "ё", ["Ж"] = "ж", ["З"] = "з", ["И"] = "и",
    ["Й"] = "й", ["К"] = "к", ["Л"] = "л", ["М"] = "м", ["Н"] = "н",
    ["О"] = "о", ["П"] = "п", ["Р"] = "р", ["С"] = "с", ["Т"] = "т",
    ["У"] = "у", ["Ф"] = "ф", ["Х"] = "х", ["Ц"] = "ц", ["Ч"] = "ч",
    ["Ш"] = "ш", ["Щ"] = "щ", ["Ъ"] = "ъ", ["Ы"] = "ы", ["Ь"] = "ь",
    ["Э"] = "э", ["Ю"] = "ю", ["Я"] = "я"
}

local function lowerUtf8(text)
    text = string.lower(safeString(text))
    for upper, lower in pairs(CYRILLIC_LOWER_MAP) do
        text = string.gsub(text, upper, lower)
    end
    return text
end

local function trim(text)
    return safeString(text):match("^%s*(.-)%s*$") or ""
end

local function normalizeSearchText(text)
    text = lowerUtf8(trim(text))
    text = string.gsub(text, "%s+", " ")
    return text
end

local function safeNumber(value, default)
    local n = tonumber(value)
    if not n or n ~= n or n == math.huge or n == -math.huge then
        return default
    end
    return n
end

local function isArrayLike(t)
    if type(t) ~= "table" then
        return false
    end

    local numeric = 0
    local other = 0

    for k, _ in pairs(t) do
        if type(k) == "number" then
            numeric = numeric + 1
        else
            other = other + 1
        end
    end

    return numeric > 0 and other == 0
end

local function deepCopy(value, seen)
    if type(value) ~= "table" then
        return value
    end

    seen = seen or {}
    if seen[value] then
        return nil
    end

    local result = {}
    seen[value] = result

    for k, v in pairs(value) do
        local kt = type(k)
        local vt = type(v)

        if (kt == "string" or kt == "number") and
           (vt == "string" or vt == "number" or vt == "boolean" or vt == "table" or vt == "nil") then
            result[k] = deepCopy(v, seen)
        end
    end

    seen[value] = nil
    return result
end

local function mergeDefaults(target, defaults)
    if type(target) ~= "table" then
        target = {}
    end

    for k, v in pairs(defaults) do
        if target[k] == nil then
            target[k] = deepCopy(v)
        elseif type(v) == "table" and type(target[k]) == "table" then
            target[k] = mergeDefaults(target[k], v)
        end
    end

    return target
end

local function getDataDir()
    return storageWorkingDirectory() .. "\\config\\" .. DATA_DIR_NAME
end

local function ensureDataDirectory()
    local configDir = storageWorkingDirectory() .. "\\config"
    if not doesDirectoryExist(configDir) then
        createDirectory(configDir)
    end

    local dataDir = getDataDir()
    if not doesDirectoryExist(dataDir) then
        createDirectory(dataDir)
    end

    app.data_dir = dataDir
    app.settings_path = dataDir .. "\\" .. SETTINGS_FILE
    app.database_path = dataDir .. "\\" .. DATABASE_FILE
    app.database_backup_path = dataDir .. "\\" .. DATABASE_BACKUP_FILE
    app.debug_path = dataDir .. "\\" .. DEBUG_FILE
    app.category_path = dataDir .. "\\" .. CATEGORY_FILE
    app.category_backup_path = dataDir .. "\\" .. CATEGORY_BACKUP_FILE
    app.item_names_path = dataDir .. "\\item_names.json"
    app.item_names_backup_path = dataDir .. "\\item_names.json.bak"
end

local function readWholeFile(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end

    local data = file:read("*a")
    file:close()
    return data
end

local function writeWholeFile(path, data)
    local file, err = io.open(path, "wb")
    if not file then
        return false, err or "io.open failed"
    end

    local ok, writeErr = file:write(data)
    file:flush()
    file:close()

    if not ok then
        return false, writeErr or "write failed"
    end

    return true
end

local function decodeJsonSafe(text)
    if type(text) ~= "string" or text == "" then
        return nil, "empty json"
    end

    local ok, result = pcall(context.decodeJson, text)
    if not ok or type(result) ~= "table" then
        return nil, ok and "decoded value is not a table" or safeString(result, "decodeJson failed")
    end

    return result
end

local function encodeJsonSafe(value)
    local ok, result = pcall(context.encodeJson, value)
    if not ok or type(result) ~= "string" then
        return nil, ok and "encodeJson returned invalid value" or safeString(result, "encodeJson failed")
    end
    return result
end

local function copyFile(src, dst)
    local data = readWholeFile(src)
    if not data then
        return false
    end
    local ok = writeWholeFile(dst, data)
    return ok == true
end

local function atomicWriteJson(path, backupPath, value)
    local json, encodeErr = encodeJsonSafe(value)
    if not json then
        return false, "encode: " .. safeString(encodeErr)
    end

    local tmpPath = path .. ".tmp"
    local ok, writeErr = writeWholeFile(tmpPath, json)
    if not ok then
        return false, "tmp write: " .. safeString(writeErr)
    end

    local verifyText = readWholeFile(tmpPath)
    local verified, verifyErr = decodeJsonSafe(verifyText)
    if not verified then
        os.remove(tmpPath)
        return false, "tmp verify: " .. safeString(verifyErr)
    end

    if backupPath and doesFileExist(path) then
        os.remove(backupPath)
        copyFile(path, backupPath)
    end

    os.remove(path)
    local renamed, renameErr = os.rename(tmpPath, path)
    if not renamed then
        if backupPath and doesFileExist(backupPath) then
            copyFile(backupPath, path)
        end
        os.remove(tmpPath)
        return false, "rename: " .. safeString(renameErr)
    end

    return true
end

local function loadJsonSafe(path, defaults)
    if not doesFileExist(path) then
        return deepCopy(defaults), nil
    end

    local text = readWholeFile(path)
    local decoded, err = decodeJsonSafe(text)
    if not decoded then
        return nil, err
    end

    return mergeDefaults(decoded, defaults), nil
end

local function normalizeCategory(category)
    category = safeString(category)
    if VALID_CATEGORIES[category] then
        return category
    end
    return CATEGORY.OTHER
end

local function migrateSettings(settings)
    settings = mergeDefaults(settings, DEFAULT_SETTINGS)
    settings.schema_version = 2
    settings.houses = type(settings.houses) == "table" and settings.houses or {}
    settings.warehouses = type(settings.warehouses) == "table" and settings.warehouses or {}
    settings.vehicles = type(settings.vehicles) == "table" and settings.vehicles or {}
    settings.category_overrides = type(settings.category_overrides) == "table" and settings.category_overrides or {}
    settings.bindings = type(settings.bindings) == "table" and settings.bindings or { fingerprints = {} }
    settings.bindings.fingerprints = type(settings.bindings.fingerprints) == "table" and settings.bindings.fingerprints or {}
    settings.debug = type(settings.debug) == "table" and settings.debug or {}
    settings.debug.enabled = true
    return settings
end

local function migrateDatabase(database)
    database = mergeDefaults(database, DEFAULT_DATABASE)
    database.schema_version = 2
    database.storages = type(database.storages) == "table" and database.storages or {}

    for storageKey, storage in pairs(database.storages) do
        if type(storage) ~= "table" then
            database.storages[storageKey] = nil
        else
            storage.storage_key = storage.storage_key or storageKey
            storage.identity = type(storage.identity) == "table" and storage.identity or {}
            storage.items = type(storage.items) == "table" and storage.items or {}
        end
    end

    return database
end

local function loadCategoryMap()
    local categoryMap, err = loadJsonSafe(app.category_path, DEFAULT_CATEGORY_MAP)
    if not categoryMap then
        app.last_error = "category map load: " .. safeString(err)
        categoryMap = deepCopy(DEFAULT_CATEGORY_MAP)
    end

    categoryMap = mergeDefaults(categoryMap, DEFAULT_CATEGORY_MAP)
    categoryMap.item_ids = type(categoryMap.item_ids) == "table" and categoryMap.item_ids or {}
    categoryMap.model_ids = type(categoryMap.model_ids) == "table" and categoryMap.model_ids or {}
    categoryMap.server_types = type(categoryMap.server_types) == "table" and categoryMap.server_types or {}
    categoryMap.name_rules = type(categoryMap.name_rules) == "table" and categoryMap.name_rules or deepCopy(DEFAULT_CATEGORY_MAP.name_rules)
    app.category_map = categoryMap
end

local function saveCategoryMap()
    local ok, err = atomicWriteJson(app.category_path, app.category_backup_path, app.category_map)
    if not ok then
        app.last_error = "category map save: " .. safeString(err)
        return false
    end
    return true
end

local function recoverDatabase()
    if not doesFileExist(app.database_backup_path) then
        return false, "backup not found"
    end

    local text = readWholeFile(app.database_backup_path)
    local decoded, err = decodeJsonSafe(text)
    if not decoded then
        return false, "backup invalid: " .. safeString(err)
    end

    decoded = migrateDatabase(decoded)
    app.database = decoded

    local ok, saveErr = atomicWriteJson(app.database_path, nil, app.database)
    if not ok then
        return false, saveErr
    end

    return true
end

local function loadSettings()
    local settings, err = loadJsonSafe(app.settings_path, DEFAULT_SETTINGS)
    if not settings then
        app.last_error = "settings.json: " .. safeString(err)
        settings = deepCopy(DEFAULT_SETTINGS)
    end
    app.settings = migrateSettings(settings)
end

local function saveSettings()
    app.settings = type(app.settings) == "table" and app.settings or deepCopy(DEFAULT_SETTINGS)
    app.settings.debug = type(app.settings.debug) == "table" and app.settings.debug or {}
    app.settings.debug.enabled = true
    local ok, err = atomicWriteJson(app.settings_path, nil, app.settings)
    if not ok then
        app.last_error = "settings save: " .. safeString(err)
        return false
    end
    return true
end

local function loadDatabase()
    local database, err = loadJsonSafe(app.database_path, DEFAULT_DATABASE)
    if database then
        app.database = migrateDatabase(database)
        return true
    end

    app.last_error = "database load: " .. safeString(err)

    local recovered, recoverErr = recoverDatabase()
    if recovered then
        return true
    end

    app.database = deepCopy(DEFAULT_DATABASE)
    app.last_error = app.last_error .. "; recovery: " .. safeString(recoverErr)
    return false
end

local function saveDatabaseAtomic()
    local ok, err = atomicWriteJson(app.database_path, app.database_backup_path, app.database)
    if not ok then
        app.last_error = "database save: " .. safeString(err)
        return false
    end
    return true
end

local SENSITIVE_KEYWORDS = {
    "token",
    "auth",
    "authorization",
    "cookie",
    "session",
    "password",
    "passwd",
    "secret",
    "premiumkey",
    "marketkey",
    "jwt"
}

local function isSensitiveKey(key)
    local s = string.lower(safeString(key))
    for i = 1, #SENSITIVE_KEYWORDS do
        if string.find(s, SENSITIVE_KEYWORDS[i], 1, true) then
            return true
        end
    end
    return false
end

local function sanitizeForLog(value, depth, seen)
    depth = depth or 0
    seen = seen or {}

    local t = type(value)

    if t == "nil" or t == "boolean" or t == "number" then
        return value
    end

    if t == "string" then
        if #value > 1024 then
            return string.sub(value, 1, 1024) .. "...[truncated]"
        end
        return value
    end

    if t ~= "table" then
        return "<" .. t .. ">"
    end

    if depth >= 8 then
        return "<max-depth>"
    end

    if seen[value] then
        return "<cycle>"
    end

    seen[value] = true
    local result = {}
    local count = 0

    for k, v in pairs(value) do
        count = count + 1
        if count > 300 then
            result["__truncated"] = true
            break
        end

        if isSensitiveKey(k) then
            result[k] = "<redacted>"
        else
            result[k] = sanitizeForLog(v, depth + 1, seen)
        end
    end

    seen[value] = nil
    return result
end

local function rotateDebugLogIfNeeded()
    if not doesFileExist(app.debug_path) then
        return
    end

    local file = io.open(app.debug_path, "rb")
    if not file then
        return
    end

    local size = file:seek("end") or 0
    file:close()

    local maxBytes = safeNumber(app.settings.debug.max_log_bytes, 2 * 1024 * 1024)
    if size <= maxBytes then
        return
    end

    local oldPath = app.debug_path .. ".old"
    os.remove(oldPath)
    os.rename(app.debug_path, oldPath)
end

local function appendDebugLine(line)
    if not app.settings or not app.settings.debug.enabled then
        return
    end

    rotateDebugLogIfNeeded()

    local file = io.open(app.debug_path, "ab")
    if not file then
        return
    end

    file:write(line)
    file:write("\r\n")
    file:close()
end

local function isInventoryRelatedEvent(eventName)
    local s = string.lower(safeString(eventName))
    return string.find(s, "inventory", 1, true) ~= nil
        or string.find(s, "storage", 1, true) ~= nil
        or string.find(s, "trunk", 1, true) ~= nil
        or string.find(s, "warehouse", 1, true) ~= nil
        or string.find(s, "closet", 1, true) ~= nil
        or string.find(s, "container", 1, true) ~= nil
end

local function logInventoryEvent(eventName, payload)
    local diagnosticEvent = isInventoryRelatedEvent(eventName)
        or eventName == "event.setActiveView"

    if not app.settings.debug.enabled or not diagnosticEvent then
        return
    end

    local sanitized = sanitizeForLog(payload)
    local json = encodeJsonSafe(sanitized)
    json = json or "<encode failed>"

    local limit = safeNumber(app.settings.debug.max_payload_chars, 16000)
    if #json > limit then
        json = string.sub(json, 1, limit) .. "...[truncated]"
    end

    local stamp = os.date("%Y-%m-%d %H:%M:%S")
    appendDebugLine(stamp .. " EVENT=" .. safeString(eventName) .. " JSON=" .. json)
    app.debug_event_count = app.debug_event_count + 1
end

local function normalizeCount(value)
    local n = safeNumber(value, 1)
    if n < 0 then
        n = 0
    end
    return math.floor(n)
end

local function normalizeName(rawItem, itemId)
    rawItem = type(rawItem) == "table" and rawItem or {}
    local candidates = {
        rawItem.name,
        rawItem.itemName,
        rawItem.item_name,
        rawItem.title,
        rawItem.label
    }

    for i = 1, #candidates do
        if type(candidates[i]) == "string" and candidates[i] ~= "" then
            return candidates[i]
        end
    end

    if itemId ~= nil then
        local itemKey = safeString(itemId)
        if type(app.item_names) == "table" then
            local cachedName = app.item_names[itemKey]
            if type(cachedName) == "string" and cachedName ~= "" then
                return cachedName
            end
        end

        local resolver = rawget(_G, "ARZ_STORAGE_ITEM_NAME_RESOLVER")
        if type(resolver) == "function" then
            local ok, resolvedName = pcall(resolver, itemId, rawItem)
            if ok and type(resolvedName) == "string" and resolvedName ~= "" then
                return resolvedName
            end
        end

        return "Item #" .. itemKey
    end

    return "Unknown item"
end

local function copyRelevantMetadata(rawItem)
    local keys = {
        "text",
        "enchant",
        "color",
        "background",
        "available",
        "time",
        "quality",
        "durability",
        "serial",
        "uid",
        "extra",
        "params"
    }

    local metadata = {}
    local hasAny = false

    for i = 1, #keys do
        local key = keys[i]
        local value = rawItem[key]
        if value ~= nil then
            metadata[key] = sanitizeForLog(value)
            hasAny = true
        end
    end

    return hasAny and metadata or nil
end

local function isEmptySlot(rawItem)
    if type(rawItem) ~= "table" then
        return true
    end

    local itemId = rawItem.item or rawItem.item_id or rawItem.itemId or rawItem.id
    local name = rawItem.name or rawItem.itemName or rawItem.item_name or rawItem.title or rawItem.label

    if itemId == nil and (name == nil or name == "") then
        return true
    end

    if safeNumber(itemId, nil) == 0 and (name == nil or name == "") then
        return true
    end

    return false
end

local function extractItemServerType(rawItem)
    if type(rawItem) ~= "table" then
        return nil
    end

    local value = rawItem.itemType
    if value == nil then value = rawItem.item_type end
    if value == nil then value = rawItem.category end
    if value == nil then value = rawItem.categoryId end
    if value == nil then value = rawItem.category_id end
    if value == nil then value = rawItem.kind end
    if value == nil then value = rawItem.type end
    return value
end

local BUILTIN_CATEGORY_BY_ITEM_ID = {
    ["9322"] = CATEGORY.UPGRADES,
    ["9742"] = CATEGORY.UPGRADES,
    ["9516"] = CATEGORY.SHARDS,
    ["8659"] = CATEGORY.SHARDS,
    ["8005"] = CATEGORY.ACCESSORIES,
    ["9231"] = CATEGORY.ACCESSORIES,
    ["9440"] = CATEGORY.ACCESSORIES,
    ["9441"] = CATEGORY.ACCESSORIES,
    ["9479"] = CATEGORY.ACCESSORIES,
    ["9574"] = CATEGORY.ACCESSORIES,
    ["9842"] = CATEGORY.ACCESSORIES,
    ["9878"] = CATEGORY.ACCESSORIES
}

local function categoryFromBuiltinName(name)
    local normalized = normalizeSearchText(name)
    if normalized == "" then
        return nil
    end

    if normalized == "virgin moon" or normalized == "shadow moon" then
        return CATEGORY.SKINS
    end

    if string.find(normalized, u8:decode("РѕСЃРєРѕР»РѕРє"), 1, true) == 1
        or string.find(normalized, u8:decode("РѕСЃРєРѕР»РєРё"), 1, true) == 1 then
        return CATEGORY.SHARDS
    end

    if string.find(normalized, u8:decode("РЅР°Р±РѕСЂ СЂРµСЃС‚Р°РІСЂР°С†РёРё"), 1, true)
        or string.find(normalized, u8:decode("РёРЅСЃС‚СЂСѓРєС†РёСЏ РґР»СЏ СЂР°Р·Р±РѕСЂР°"), 1, true) then
        return CATEGORY.UPGRADES
    end

    if string.find(normalized, u8:decode("СЃРєРёРЅ:"), 1, true)
        or string.find(normalized, u8:decode("Р»РµРіРµРЅРґР°СЂРЅР°СЏ РѕРґРµР¶РґР°:"), 1, true) == 1
        or string.find(normalized, u8:decode("РѕРґРµР¶РґР°:"), 1, true) == 1 then
        return CATEGORY.SKINS
    end

    if string.find(normalized, u8:decode("РѕР±СЉРµРєС‚:"), 1, true) == 1 then
        return CATEGORY.OBJECTS
    end

    if string.find(normalized, u8:decode("Р°РєСЃРµСЃСЃСѓР°СЂ:"), 1, true) == 1
        or string.find(normalized, u8:decode("Р»РµРіРµРЅРґР°СЂРЅС‹Р№ Р°РєСЃРµСЃСЃСѓР°СЂ:"), 1, true) == 1
        or string.find(normalized, u8:decode("РєРѕР»Р»РµРєС†РёРѕРЅРЅС‹Р№ Р°РєСЃРµСЃСЃСѓР°СЂ:"), 1, true) == 1 then
        return CATEGORY.ACCESSORIES
    end

    if string.find(normalized, u8:decode("Р»Р°СЂРµС†"), 1, true)
        or string.find(normalized, u8:decode("СЃСѓРЅРґСѓРє"), 1, true)
        or string.find(normalized, u8:decode("РєРµР№СЃ"), 1, true)
        or string.find(normalized, u8:decode("С‚Р°Р№РЅРёРє"), 1, true)
        or string.find(normalized, u8:decode("СЂСѓР»РµС‚РєР°"), 1, true)
        or string.find(normalized, u8:decode("СЏС‰РёРє"), 1, true) then
        return CATEGORY.CASES
    end

    if string.find(normalized, u8:decode("РєСЂС‹Р»СЊСЏ"), 1, true)
        or string.find(normalized, u8:decode("РЅРёРјР±"), 1, true)
        or string.find(normalized, u8:decode("СЂСЋРєР·Р°Рє"), 1, true)
        or string.find(normalized, u8:decode("РјР°СЃРєР°"), 1, true)
        or string.find(normalized, u8:decode("С€Р»СЏРїР°"), 1, true)
        or string.find(normalized, u8:decode("С‡РµРјРѕРґР°РЅ"), 1, true)
        or string.find(normalized, u8:decode("РјРѕРЅРѕРєРѕР»РµСЃРѕ"), 1, true)
        or string.find(normalized, u8:decode("РІРѕР·РґСѓС€РЅС‹Р№ С€Р°СЂ"), 1, true)
        or string.find(normalized, u8:decode("СЌРЅРµСЂРіРµС‚РёС‡РµСЃРєРёРµ С‡Р°СЃС‹"), 1, true)
        or string.find(normalized, u8:decode("СЌРЅРµСЂРіРµС‚РёС‡РµСЃРєРёР№ С‰РёС‚"), 1, true)
        or string.find(normalized, u8:decode("РїСЏС‚РёР·СѓР±РµС†"), 1, true)
        or string.find(normalized, u8:decode("РїРѕСЃРѕС…"), 1, true)
        or string.find(normalized, u8:decode("РјРѕР»РѕС‚ С‚РѕСЂР°"), 1, true)
        or string.find(normalized, u8:decode("СЂСѓРєР° Р±РµСЃРєРѕРЅРµС‡РЅРѕСЃС‚Рё"), 1, true)
        or string.find(normalized, u8:decode("РіРѕР»РѕРІР° СЂРѕР±РѕРєРѕРї"), 1, true)
        or string.find(normalized, u8:decode("РіРѕР»РѕРІР° С„СЂРµРґРґРё"), 1, true)
        or string.find(normalized, u8:decode("РєСѓРєР»Р° РІСѓРґСѓ"), 1, true)
        or string.find(normalized, u8:decode("РґСЂРѕРЅ-Р·Р°С‰РёС‚РЅРёРє"), 1, true)
        or string.find(normalized, u8:decode("СЃСѓРјРєР° СЃ РґРµРЅСЊРіР°РјРё"), 1, true) then
        return CATEGORY.ACCESSORIES
    end

    return nil
end

local function categoryFromServerType(serverType)
    if serverType == nil then
        return nil
    end

    if app.category_map then
        local value = app.category_map.server_types[safeString(serverType)]
        if value and VALID_CATEGORIES[value] then
            return value
        end
    end

    if type(serverType) == "string" then
        local normalized = normalizeSearchText(serverType)
        if normalized == "accessory" or normalized == "accessories"
            or normalized == u8:decode("Р°РєСЃРµСЃСЃСѓР°СЂ") or normalized == u8:decode("Р°РєСЃРµСЃСЃСѓР°СЂС‹") then
            return CATEGORY.ACCESSORIES
        elseif normalized == "skin" or normalized == "skins" or normalized == "clothes" or normalized == "clothing"
            or normalized == u8:decode("СЃРєРёРЅ") or normalized == u8:decode("СЃРєРёРЅС‹") or normalized == u8:decode("РѕРґРµР¶РґР°") then
            return CATEGORY.SKINS
        elseif normalized == "case" or normalized == "cases" or normalized == "crate" or normalized == "container"
            or normalized == u8:decode("Р»Р°СЂРµС†") or normalized == u8:decode("Р»Р°СЂС†С‹") then
            return CATEGORY.CASES
        elseif normalized == "shard" or normalized == "shards"
            or normalized == u8:decode("РѕСЃРєРѕР»РѕРє") or normalized == u8:decode("РѕСЃРєРѕР»РєРё") then
            return CATEGORY.SHARDS
        elseif normalized == "weapon" or normalized == "weapons" or normalized == u8:decode("РѕСЂСѓР¶РёРµ") then
            return CATEGORY.WEAPONS
        elseif normalized == "certificate" or normalized == "certificates" or normalized == u8:decode("СЃРµСЂС‚РёС„РёРєР°С‚С‹") then
            return CATEGORY.CERTIFICATES
        elseif normalized == "tuning" or normalized == u8:decode("С‚СЋРЅРёРЅРі") then
            return CATEGORY.TUNING
        elseif normalized == "upgrade" or normalized == "upgrades" or normalized == u8:decode("СѓР»СѓС‡С€РµРЅРёСЏ") then
            return CATEGORY.UPGRADES
        elseif normalized == "resource" or normalized == "resources" or normalized == "craft"
            or normalized == u8:decode("СЂРµСЃСѓСЂСЃС‹") or normalized == u8:decode("РєСЂР°С„С‚") then
            return CATEGORY.RESOURCES
        elseif normalized == "object" or normalized == "objects" or normalized == u8:decode("РѕР±СЉРµРєС‚С‹") then
            return CATEGORY.OBJECTS
        end
    end

    return nil
end

local function categoryFromItemId(itemId)
    if itemId == nil then
        return nil
    end

    local key = safeString(itemId)
    local builtin = BUILTIN_CATEGORY_BY_ITEM_ID[key]
    if builtin then
        return builtin
    end

    if app.category_map then
        local value = app.category_map.item_ids[key]
        if value and VALID_CATEGORIES[value] then
            return value
        end
    end

    return nil
end

local function categoryFromModel(modelId)
    if not app.category_map or modelId == nil then
        return nil
    end
    local value = app.category_map.model_ids[safeString(modelId)]
    if value and VALID_CATEGORIES[value] then
        return value
    end
    return nil
end

local function categoryFromName(name)
    if not app.category_map then
        return nil
    end

    local normalized = normalizeSearchText(name)
    if normalized == "" then
        return nil
    end

    for i = 1, #app.category_map.name_rules do
        local rule = app.category_map.name_rules[i]
        if type(rule) == "table" then
            local pattern = normalizeSearchText(rule.pattern)
            local category = normalizeCategory(rule.category)
            if pattern ~= "" and string.find(normalized, pattern, 1, true) then
                return category
            end
        end
    end

    return nil
end

local function resolveCategory(item)
    if type(item) ~= "table" then
        return CATEGORY.OTHER
    end

    if app.settings and type(app.settings.category_overrides) == "table" and item.item_id ~= nil then
        local override = app.settings.category_overrides[safeString(item.item_id)]
        if override and VALID_CATEGORIES[override] then
            return override
        end
    end

    return categoryFromServerType(item.server_type)
        or categoryFromItemId(item.item_id)
        or categoryFromModel(item.model_id)
        or categoryFromBuiltinName(item.name)
        or categoryFromName(item.name)
        or CATEGORY.OTHER
end

local function stableSerialize(value, depth)
    depth = depth or 0
    if depth > 6 then
        return "<depth>"
    end

    local t = type(value)
    if t == "nil" then return "nil" end
    if t == "boolean" or t == "number" then return tostring(value) end
    if t == "string" then return string.format("%q", value) end
    if t ~= "table" then return "<" .. t .. ">" end

    local keys = {}
    for k, _ in pairs(value) do
        if type(k) == "string" or type(k) == "number" then
            keys[#keys + 1] = k
        end
    end

    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)

    local parts = {}
    for i = 1, #keys do
        local key = keys[i]
        parts[#parts + 1] = tostring(key) .. "=" .. stableSerialize(value[key], depth + 1)
    end
    return "{" .. table.concat(parts, ";") .. "}"
end

local function stableMetadataSubset(metadata)
    if type(metadata) ~= "table" then
        return nil
    end

    local important = {
        "enchant", "quality", "durability", "serial", "uid", "extra", "params", "text"
    }
    local result = {}
    local hasAny = false

    for i = 1, #important do
        local key = important[i]
        if metadata[key] ~= nil then
            result[key] = deepCopy(metadata[key])
            hasAny = true
        end
    end

    return hasAny and result or nil
end

local function buildItemSignature(item)
    if type(item) ~= "table" then
        return "invalid"
    end

    return table.concat({
        safeString(item.item_id, "nil"),
        safeString(item.model_id, "nil"),
        safeString(item.server_type, "nil"),
        stableSerialize(stableMetadataSubset(item.metadata))
    }, "|")
end

local function normalizeItem(rawItem, sourceType)
    if isEmptySlot(rawItem) then
        return nil
    end

    local itemId = rawItem.item or rawItem.item_id or rawItem.itemId or rawItem.id
    local modelId = rawItem.model or rawItem.model_id or rawItem.modelId

    local countValue = rawItem.amount
    if countValue == nil then countValue = rawItem.count end
    if countValue == nil then countValue = rawItem.quantity end
    if countValue == nil then countValue = 1 end

    local item = {
        item_id = itemId,
        model_id = safeNumber(modelId, nil),
        name = normalizeName(rawItem, itemId),
        count = normalizeCount(countValue),
        slot = safeNumber(rawItem.slot, nil),
        inventory_type = sourceType,
        server_type = extractItemServerType(rawItem),
        metadata = copyRelevantMetadata(rawItem)
    }

    item.category = resolveCategory(item)
    item.signature = buildItemSignature(item)
    return item
end

local function normalizeItemList(rawItems, sourceType)
    local result = {}
    if type(rawItems) ~= "table" then
        return result
    end

    for _, rawItem in pairs(rawItems) do
        local item = normalizeItem(rawItem, sourceType)
        if item then
            result[#result + 1] = item
        end
    end

    table.sort(result, function(a, b)
        local sa = a.slot or 999999
        local sb = b.slot or 999999
        if sa == sb then
            return safeString(a.item_id) < safeString(b.item_id)
        end
        return sa < sb
    end)

    return result
end

local function invalidateSearchIndex()
    app.search_index_dirty = true
    app.visible_rows_dirty = true
end

local function sanitizeStoredItem(item)
    if type(item) ~= "table" then
        return nil
    end

    local storedName = safeString(item.name, "Unknown item")
    if storedName == "Unknown item" or storedName:match("^Item #%d+$") then
        local resolvedName = normalizeName({}, item.item_id)
        if resolvedName ~= "Unknown item" and not resolvedName:match("^Item #%d+$") then
            storedName = resolvedName
        end
    end

    local result = {
        item_id = item.item_id,
        model_id = safeNumber(item.model_id, nil),
        name = storedName,
        count = normalizeCount(item.count),
        slot = safeNumber(item.slot, nil),
        inventory_type = item.inventory_type,
        server_type = item.server_type,
        category = normalizeCategory(item.category),
        metadata = type(item.metadata) == "table" and deepCopy(item.metadata) or nil
    }
    result.signature = buildItemSignature(result)
    result.category = resolveCategory(result)
    return result
end

local function upgradeStoredItems()
    if not app.database or type(app.database.storages) ~= "table" then
        return
    end

    for _, storage in pairs(app.database.storages) do
        if type(storage) == "table" and type(storage.items) == "table" then
            local upgraded = {}
            for _, item in pairs(storage.items) do
                local normalized = sanitizeStoredItem(item)
                if normalized then
                    upgraded[#upgraded + 1] = normalized
                end
            end
            storage.items = upgraded
        end
    end
    invalidateSearchIndex()
end

local function rebuildSearchIndex()
    local index = {}
    if app.database and type(app.database.storages) == "table" then
        for storageKey, storage in pairs(app.database.storages) do
            if type(storage) == "table" and type(storage.items) == "table" then
                for _, item in pairs(storage.items) do
                    if type(item) == "table" then
                        local row = {
                            storage_key = storageKey,
                            storage_kind = storage.kind,
                            storage_label = storage.label,
                            storage_identity = storage.identity,
                            last_scan = storage.last_scan,
                            item_id = item.item_id,
                            model_id = item.model_id,
                            name = safeString(item.name),
                            count = normalizeCount(item.count),
                            slot = item.slot,
                            category = normalizeCategory(item.category or resolveCategory(item)),
                            signature = item.signature or buildItemSignature(item),
                            metadata = item.metadata
                        }
                        row.search_text = normalizeSearchText(row.name)
                        index[#index + 1] = row
                    end
                end
            end
        end
    end

    table.sort(index, function(a, b)
        if a.search_text == b.search_text then
            if safeString(a.storage_label) == safeString(b.storage_label) then
                return safeNumber(a.slot, 999999) < safeNumber(b.slot, 999999)
            end
            return safeString(a.storage_label) < safeString(b.storage_label)
        end
        return a.search_text < b.search_text
    end)

    app.search_index = index
    app.search_index_dirty = false
    return index
end

local function getIndexedItems()
    if app.search_index_dirty then
        rebuildSearchIndex()
    end
    return app.search_index
end

local function addCategoryOverride(itemId, category)
    category = normalizeCategory(category)
    local key = safeString(itemId)
    if key == "" then
        return false
    end
    app.settings.category_overrides[key] = category
    saveSettings()
    upgradeStoredItems()
    saveDatabaseAtomic()
    return true
end

local function removeStorage(storageKey)
    storageKey = safeString(storageKey)
    if app.database.storages[storageKey] == nil then
        return false
    end
    app.database.storages[storageKey] = nil
    invalidateSearchIndex()
    return saveDatabaseAtomic()
end

local function makeStorageKey(kind, identity)
    if kind == STORAGE_KIND.PLAYER_INVENTORY then
        return "inventory:self"
    end

    if kind == STORAGE_KIND.HOUSE_CLOSET then
        return "house:" .. safeString(identity.house_number) .. ":closet"
    end

    if kind == STORAGE_KIND.HOUSE_OBJECT then
        return "house:" .. safeString(identity.house_number) .. ":object"
    end

    if kind == STORAGE_KIND.WAREHOUSE then
        return "warehouse:" .. safeString(identity.warehouse_number)
    end

    if kind == STORAGE_KIND.VEHICLE_TRUNK then
        return "vehicle:" .. safeString(identity.vehicle_key or identity.fingerprint or "unknown")
    end

    return "unknown:" .. safeString(identity.fingerprint or unixTime())
end

local function buildStorageLabel(kind, identity)
    if kind == STORAGE_KIND.PLAYER_INVENTORY then
        return "Инвентарь"
    end

    if kind == STORAGE_KIND.HOUSE_CLOSET then
        return "Дом №" .. safeString(identity.house_number) .. " -> Шкаф"
    end

    if kind == STORAGE_KIND.HOUSE_OBJECT then
        return "Дом №" .. safeString(identity.house_number) .. " -> Объект возле дома"
    end

    if kind == STORAGE_KIND.WAREHOUSE then
        return "Склад №" .. safeString(identity.warehouse_number)
    end

    if kind == STORAGE_KIND.VEHICLE_TRUNK then
        return safeString(identity.vehicle_name, "Автомобиль") .. " -> Багажник"
    end

    return "Неизвестное хранилище"
end

local function beginStorageSnapshot(kind, identity, reason)
    app.snapshot = {
        kind = kind,
        identity = deepCopy(identity or {}),
        key = makeStorageKey(kind, identity or {}),
        label = buildStorageLabel(kind, identity or {}),
        started_at = unixTime(),
        started_ms = nowMs(),
        last_update_ms = nowMs(),
        commit_after_ms = nil,
        reason = reason or "",
        items_by_slot = {},
        items_no_slot = {},
        packet_count = 0
    }
    return app.snapshot
end

local function ensureSnapshot(kind, identity, reason)
    local key = makeStorageKey(kind, identity or {})
    if not app.snapshot or app.snapshot.key ~= key then
        return beginStorageSnapshot(kind, identity, reason)
    end
    return app.snapshot
end

local function putSnapshotItem(snapshot, item)
    if not snapshot or not item then
        return
    end

    if item.slot ~= nil then
        snapshot.items_by_slot[tostring(item.slot)] = item
    else
        snapshot.items_no_slot[#snapshot.items_no_slot + 1] = item
    end
end

local function appendSnapshotItems(snapshot, items)
    if not snapshot or type(items) ~= "table" then
        return
    end

    for i = 1, #items do
        putSnapshotItem(snapshot, items[i])
    end

    snapshot.packet_count = snapshot.packet_count + 1
    snapshot.last_update_ms = nowMs()
    snapshot.commit_after_ms = snapshot.last_update_ms + safeNumber(app.settings.scan.debounce_ms, 450)
end

local function snapshotToItems(snapshot)
    local items = {}

    for _, item in pairs(snapshot.items_by_slot or {}) do
        if type(item) == "table" then items[#items + 1] = item end
    end
    for _, item in pairs(snapshot.items_no_slot or {}) do
        if type(item) == "table" then items[#items + 1] = item end
    end

    table.sort(items, function(a, b)
        local typeA = safeNumber(a.inventory_type, -1)
        local typeB = safeNumber(b.inventory_type, -1)
        if typeA ~= typeB then return typeA < typeB end
        local slotA = safeNumber(a.slot, 999999)
        local slotB = safeNumber(b.slot, 999999)
        if slotA ~= slotB then return slotA < slotB end
        return safeString(a.item_id) < safeString(b.item_id)
    end)

    return items
end

local getVehicleLabel
local bindFingerprint

local function commitStorageSnapshot(snapshot)
    if not snapshot or not app.database then
        return false
    end

    local rawItems = snapshotToItems(snapshot)
    local items = {}
    for i = 1, #rawItems do
        local item = sanitizeStoredItem(rawItems[i])
        if item then
            items[#items + 1] = item
        end
    end

    if snapshot.kind == STORAGE_KIND.VEHICLE_TRUNK and snapshot.identity.vehicle_key then
        local vehicle = app.settings.vehicles[snapshot.identity.vehicle_key]
        if type(vehicle) == "table" then
            snapshot.identity.vehicle_name = getVehicleLabel(vehicle)
            snapshot.label = buildStorageLabel(snapshot.kind, snapshot.identity)
        end
    end

    app.database.storages[snapshot.key] = {
        storage_key = snapshot.key,
        kind = snapshot.kind,
        label = snapshot.label,
        identity = deepCopy(snapshot.identity),
        last_scan = unixTime(),
        packet_count = snapshot.packet_count,
        items = items
    }

    if snapshot.fingerprint and snapshot.kind ~= STORAGE_KIND.PLAYER_INVENTORY then
        bindFingerprint(snapshot.fingerprint, snapshot.kind, snapshot.identity)
    end

    invalidateSearchIndex()
    local ok = saveDatabaseAtomic()
    if ok then
        app.last_scan = {
            key = snapshot.key,
            kind = snapshot.kind,
            label = snapshot.label,
            count = #items,
            time = unixTime()
        }
    end

    if snapshot.kind == STORAGE_KIND.PLAYER_INVENTORY then
        app.player_scan_active = false
    elseif type(app.settings.pending_binding) == "table" and
           app.settings.pending_binding.kind == snapshot.kind then
        app.settings.pending_binding = nil
        saveSettings()
    end

    if app.snapshot == snapshot then
        app.snapshot = nil
    end

    return ok
end

local function cancelStorageSnapshot(reason)
    if app.snapshot then
        app.last_error = "snapshot cancelled: " .. safeString(reason)
        app.snapshot = nil
    end
end

local function processSnapshotTimer()
    local snapshot = app.snapshot
    if not snapshot then
        return
    end

    local now = nowMs()
    local timeout = safeNumber(app.settings.scan.snapshot_timeout_ms, 5000)

    if snapshot.commit_after_ms and now >= snapshot.commit_after_ms then
        commitStorageSnapshot(snapshot)
        return
    end

    if now - snapshot.last_update_ms >= timeout then
        if snapshot.packet_count > 0 then
            commitStorageSnapshot(snapshot)
        else
            cancelStorageSnapshot("timeout without item packets")
        end
    end
end

local function getPlayerInventoryPayload(payload)
    if type(payload) ~= "table" then
        return nil
    end

    local first = payload[1]
    if type(first) ~= "table" then
        return nil
    end

    if safeNumber(first.action, -1) ~= 0 then
        return nil
    end

    local data = first.data
    if type(data) ~= "table" then
        return nil
    end

    if type(data.items) ~= "table" then
        return nil
    end

    return data
end

local function handlePlayerInventory(payload)
    if not app.player_scan_active then
        return false
    end

    local data = getPlayerInventoryPayload(payload)
    if not data then
        return false
    end

    local inventoryType = safeNumber(data.type, nil)
    local wantedType = safeNumber(app.settings.scan.player_inventory_type, 1)

    if inventoryType ~= wantedType then
        return false
    end

    local snapshot = ensureSnapshot(
        STORAGE_KIND.PLAYER_INVENTORY,
        {},
        "event.inventory.playerInventory"
    )

    local items = normalizeItemList(data.items, inventoryType)

    if #data.items == 0 then
        snapshot.items_by_slot = {}
        snapshot.items_no_slot = {}
    end

    appendSnapshotItems(snapshot, items)
    return true
end

local function payloadBoolean(payload)
    if type(payload) ~= "table" then
        return nil
    end

    local value = payload[1]
    if type(value) == "boolean" then
        return value
    end

    if type(value) == "string" then
        local s = string.lower(value)
        if s == "true" then return true end
        if s == "false" then return false end
    end

    if type(value) == "number" then
        return value ~= 0
    end

    return nil
end

local function containsAny(text, words)
    text = string.lower(safeString(text))
    for i = 1, #words do
        if string.find(text, words[i], 1, true) then
            return true
        end
    end
    return false
end

local function detectExternalKind(eventName, payload)
    local joined = string.lower(safeString(eventName))

    local function scanKeys(value, depth)
        if type(value) ~= "table" or depth > 4 then
            return
        end

        for k, v in pairs(value) do
            joined = joined .. " " .. string.lower(safeString(k))
            if type(v) == "string" and #v < 128 then
                joined = joined .. " " .. string.lower(v)
            elseif type(v) == "table" then
                scanKeys(v, depth + 1)
            end
        end
    end

    scanKeys(payload, 0)

    if containsAny(joined, {"trunk", "багаж"}) then
        return STORAGE_KIND.VEHICLE_TRUNK
    end

    if containsAny(joined, {"warehouse", "склад"}) then
        return STORAGE_KIND.WAREHOUSE
    end

    if containsAny(joined, {"closet", "wardrobe", "шкаф"}) then
        return STORAGE_KIND.HOUSE_CLOSET
    end

    if containsAny(joined, {"houseobject", "homeobject", "домашний склад", "объект возле дома"}) then
        return STORAGE_KIND.HOUSE_OBJECT
    end

    return STORAGE_KIND.UNKNOWN
end

local function looksLikeItemRecord(value)
    if type(value) ~= "table" then
        return false
    end

    return value.slot ~= nil
        or value.item ~= nil
        or value.item_id ~= nil
        or value.itemId ~= nil
        or value.amount ~= nil
end

local function collectItemArrayCandidates(value, path, depth, out)
    if type(value) ~= "table" or depth > 7 then
        return
    end

    local itemLike = 0
    local total = 0

    for _, child in pairs(value) do
        total = total + 1
        if looksLikeItemRecord(child) then
            itemLike = itemLike + 1
        end
    end

    local lowerPath = string.lower(path)
    local explicitItemsPath = string.find(lowerPath, "items", 1, true) ~= nil

    if (total > 0 and itemLike > 0 and itemLike >= math.max(1, math.floor(total * 0.5)))
       or (total == 0 and explicitItemsPath) then
        out[#out + 1] = {
            path = path,
            items = value,
            score = itemLike
        }
    end

    for k, child in pairs(value) do
        if type(child) == "table" then
            collectItemArrayCandidates(child, path .. "." .. safeString(k), depth + 1, out)
        end
    end
end

local function extractExternalItems(payload)
    local candidates = {}
    collectItemArrayCandidates(payload, "$", 0, candidates)

    if #candidates == 0 then
        return nil, nil
    end

    table.sort(candidates, function(a, b)
        local ap = string.lower(a.path)
        local bp = string.lower(b.path)

        local function pathScore(path, base)
            local score = base
            if string.find(path, "left", 1, true) then score = score + 100 end
            if string.find(path, "storage", 1, true) then score = score + 80 end
            if string.find(path, "warehouse", 1, true) then score = score + 80 end
            if string.find(path, "trunk", 1, true) then score = score + 80 end
            if string.find(path, "container", 1, true) then score = score + 60 end
            if string.find(path, "right", 1, true) then score = score - 100 end
            if string.find(path, "player", 1, true) then score = score - 80 end
            return score
        end

        return pathScore(ap, a.score) > pathScore(bp, b.score)
    end)

    return candidates[1].items, candidates[1].path
end

local extractStorageFingerprint

local function findFirstFieldRecursive(value, keys, depth)
    if type(value) ~= "table" or depth > 6 then
        return nil, nil
    end

    for i = 1, #keys do
        local key = keys[i]
        if value[key] ~= nil and type(value[key]) ~= "table" then
            return value[key], key
        end
    end

    for _, child in pairs(value) do
        if type(child) == "table" then
            local found, key = findFirstFieldRecursive(child, keys, depth + 1)
            if found ~= nil then
                return found, key
            end
        end
    end

    return nil, nil
end

local function extractVehicleMetaFromPayload(payload)
    local meta = {}

    local uid = findFirstFieldRecursive(payload, {
        "vehicle_uid", "vehicleUid", "car_uid", "carUid", "transport_uid", "transportUid"
    }, 0)
    local vehicleId = findFirstFieldRecursive(payload, {
        "vehicle_id", "vehicleId", "car_id", "carId"
    }, 0)
    local modelId = findFirstFieldRecursive(payload, {
        "vehicle_model", "vehicleModel", "car_model", "carModel", "transport_model", "transportModel"
    }, 0)
    local plate = findFirstFieldRecursive(payload, {
        "plate", "plateText", "numberPlate", "number_plate", "gosNumber", "gos_number"
    }, 0)
    local slot = findFirstFieldRecursive(payload, {
        "vehicle_slot", "vehicleSlot", "car_slot", "carSlot", "transport_slot", "transportSlot"
    }, 0)
    local name = findFirstFieldRecursive(payload, {
        "vehicle_name", "vehicleName", "car_name", "carName", "transport_name", "transportName"
    }, 0)

    if uid ~= nil then meta.uid = safeString(uid) end
    if vehicleId ~= nil then meta.server_vehicle_id = safeString(vehicleId) end
    if modelId ~= nil then meta.model_id = safeNumber(modelId, nil) end
    if plate ~= nil then meta.plate = trim(plate) end
    if slot ~= nil then meta.owner_slot = safeString(slot) end
    if name ~= nil then meta.server_name = trim(name) end

    return meta
end

local function getStableVehicleIdFromPayload(meta)
    if type(meta) ~= "table" then
        return nil
    end
    if meta.uid and meta.uid ~= "" then
        return "uid:" .. meta.uid
    end
    if meta.plate and meta.plate ~= "" then
        return "plate:" .. normalizeSearchText(meta.plate)
    end
    if meta.owner_slot and meta.owner_slot ~= "" then
        return "slot:" .. meta.owner_slot
    end
    return nil
end

local function safeDoesVehicleExist(vehicle)
    if vehicle == nil then
        return false
    end
    local ok, exists = pcall(doesVehicleExist, vehicle)
    return ok and exists == true
end

local function getLocalVehicleMeta(vehicle)
    if not safeDoesVehicleExist(vehicle) then
        return nil
    end

    local meta = { handle = vehicle }

    local okModel, modelId = pcall(getCarModel, vehicle)
    if okModel then
        meta.model_id = safeNumber(modelId, nil)
    end

    local okPos, x, y, z = pcall(getCarCoordinates, vehicle)
    if okPos then
        meta.x, meta.y, meta.z = x, y, z
    end

    if meta.model_id then
        local okGxt, gxt = pcall(getNameOfVehicleModel, meta.model_id)
        if okGxt and gxt then
            meta.gxt_key = safeString(gxt)
            local okText, modelName = pcall(getGxtText, meta.gxt_key)
            if okText and type(modelName) == "string" and modelName ~= "" then
                meta.gxt_name = modelName
            end
        end
    end

    if type(sampGetVehicleIdByCarHandle) == "function" then
        local okSamp, found, sampId = pcall(sampGetVehicleIdByCarHandle, vehicle)
        if okSamp and found then
            meta.samp_vehicle_id = safeNumber(sampId, nil)
        end
    end

    return meta
end

local function distance3d(ax, ay, az, bx, by, bz)
    if type(getDistanceBetweenCoords3d) == "function" then
        local ok, dist = pcall(getDistanceBetweenCoords3d, ax, ay, az, bx, by, bz)
        if ok and type(dist) == "number" then
            return dist
        end
    end
    local dx = ax - bx
    local dy = ay - by
    local dz = az - bz
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function collectNearbyVehicles(maxDistance)
    local result = {}
    local px, py, pz = getCharCoordinates(PLAYER_PED)

    if type(getAllVehicles) == "function" then
        local ok, vehicles = pcall(getAllVehicles)
        if ok and type(vehicles) == "table" then
            for _, vehicle in pairs(vehicles) do
                local meta = getLocalVehicleMeta(vehicle)
                if meta and meta.x then
                    meta.distance = distance3d(px, py, pz, meta.x, meta.y, meta.z)
                    if meta.distance <= maxDistance then
                        result[#result + 1] = meta
                    end
                end
            end
        end
    end

    if #result == 0 and type(storeClosestEntities) == "function" then
        local ok, vehicle = pcall(function()
            local car = storeClosestEntities(PLAYER_PED)
            return car
        end)
        if ok and vehicle then
            local meta = getLocalVehicleMeta(vehicle)
            if meta and meta.x then
                meta.distance = distance3d(px, py, pz, meta.x, meta.y, meta.z)
                if meta.distance <= maxDistance then
                    result[#result + 1] = meta
                end
            end
        end
    end

    return result
end

local function scoreVehicleCandidate(localMeta, cefMeta)
    local score = 0
    local distance = safeNumber(localMeta.distance, 999)
    score = score - distance * 10

    if cefMeta and cefMeta.model_id and localMeta.model_id == cefMeta.model_id then
        score = score + 1000
    end

    if cefMeta and cefMeta.server_vehicle_id and localMeta.samp_vehicle_id and
       safeString(localMeta.samp_vehicle_id) == safeString(cefMeta.server_vehicle_id) then
        score = score + 2000
    end

    return score
end

local function findNearestVehicle(maxDistance, cefMeta)
    local candidates = collectNearbyVehicles(maxDistance or 8.0)
    if #candidates == 0 then
        return nil
    end

    table.sort(candidates, function(a, b)
        return scoreVehicleCandidate(a, cefMeta) > scoreVehicleCandidate(b, cefMeta)
    end)

    return candidates[1]
end

getVehicleLabel = function(record)
    if type(record) ~= "table" then
        return "Неизвестный автомобиль"
    end
    if record.manual_name and record.manual_name ~= "" then
        return record.manual_name
    end
    if record.server_name and record.server_name ~= "" then
        return record.server_name
    end
    if record.gxt_name and record.gxt_name ~= "" then
        return record.gxt_name
    end
    if record.model_id then
        return "Модель " .. safeString(record.model_id)
    end
    return "Неизвестный автомобиль"
end

local transientVehicleCounter = 0

local function makeTransientVehicleKey(meta)
    if type(app.snapshot) == "table"
       and app.snapshot.kind == STORAGE_KIND.VEHICLE_TRUNK
       and type(app.snapshot.identity) == "table"
       and app.snapshot.identity.unstable == true
       and safeString(app.snapshot.identity.vehicle_key) ~= "" then
        return app.snapshot.identity.vehicle_key
    end

    local modelId = safeString(meta.model_id, "unknown")
    local sampId = safeString(meta.samp_vehicle_id, "unknown")
    if modelId == "unknown" and sampId == "unknown" then
        transientVehicleCounter = transientVehicleCounter + 1
        return table.concat({
            "session", app.session_id, "unknown", safeString(transientVehicleCounter)
        }, ":")
    end

    return table.concat({
        "session",
        app.session_id,
        "model",
        modelId,
        "samp",
        sampId
    }, ":")
end

local function registerDetectedVehicle(meta)
    if type(meta) ~= "table" then
        return nil
    end

    local key = meta.vehicle_key or getStableVehicleIdFromPayload(meta) or makeTransientVehicleKey(meta)
    local current = app.settings.vehicles[key]
    if type(current) ~= "table" then
        current = {}
    end

    local fields = {
        "uid", "server_vehicle_id", "model_id", "plate", "owner_slot",
        "server_name", "gxt_name", "gxt_key", "samp_vehicle_id", "unstable"
    }
    for i = 1, #fields do
        local field = fields[i]
        if meta[field] ~= nil then
            current[field] = meta[field]
        end
    end

    current.vehicle_key = key
    current.last_seen = unixTime()
    current.label = getVehicleLabel(current)
    app.settings.vehicles[key] = current
    saveSettings()
    return current
end

local function setVehicleManualName(vehicleKey, name)
    vehicleKey = safeString(vehicleKey)
    name = trim(name)
    if vehicleKey == "" or type(app.settings.vehicles[vehicleKey]) ~= "table" then
        return false
    end

    local record = app.settings.vehicles[vehicleKey]
    record.manual_name = name
    record.label = getVehicleLabel(record)

    local storageKey = "vehicle:" .. vehicleKey
    local storage = app.database and app.database.storages and app.database.storages[storageKey]
    if type(storage) == "table" then
        storage.identity = type(storage.identity) == "table" and storage.identity or {}
        storage.identity.vehicle_name = record.label
        storage.label = record.label .. " -> Багажник"
        invalidateSearchIndex()
        saveDatabaseAtomic()
    end

    return saveSettings()
end

local function mergeVehicleIdentity(oldKey, newKey)
    oldKey = safeString(oldKey)
    newKey = safeString(newKey)
    if oldKey == "" or newKey == "" or oldKey == newKey then
        return false
    end

    local oldRecord = app.settings.vehicles[oldKey]
    if type(oldRecord) ~= "table" then
        return false
    end

    local newRecord = app.settings.vehicles[newKey]
    if type(newRecord) ~= "table" then
        newRecord = {}
    end

    for k, v in pairs(oldRecord) do
        if newRecord[k] == nil then
            newRecord[k] = deepCopy(v)
        end
    end
    newRecord.vehicle_key = newKey
    newRecord.label = getVehicleLabel(newRecord)
    app.settings.vehicles[newKey] = newRecord
    app.settings.vehicles[oldKey] = nil

    local oldStorageKey = "vehicle:" .. oldKey
    local newStorageKey = "vehicle:" .. newKey
    if app.database.storages[oldStorageKey] and not app.database.storages[newStorageKey] then
        local storage = app.database.storages[oldStorageKey]
        app.database.storages[oldStorageKey] = nil
        storage.storage_key = newStorageKey
        storage.identity = type(storage.identity) == "table" and storage.identity or {}
        storage.identity.vehicle_key = newKey
        app.database.storages[newStorageKey] = storage
    end

    saveSettings()
    invalidateSearchIndex()
    saveDatabaseAtomic()
    return true
end

local function setVehicleManualIdentity(vehicleKey, value)
    vehicleKey = safeString(vehicleKey)
    value = trim(value)
    local record = app.settings.vehicles[vehicleKey]
    if vehicleKey == "" or type(record) ~= "table" then
        return false, vehicleKey
    end

    if value == "" then
        record.manual_identity = nil
        saveSettings()
        return true, vehicleKey
    end

    local newKey = "manual-id:" .. normalizeSearchText(value)
    if newKey == "manual-id:" then
        return false, vehicleKey
    end

    if newKey ~= vehicleKey and type(app.settings.vehicles[newKey]) == "table" then
        app.last_error = "manual vehicle identity already exists: " .. value
        return false, vehicleKey
    end

    record.manual_identity = value
    record.unstable = false
    app.settings.vehicles[vehicleKey] = record
    saveSettings()

    if newKey ~= vehicleKey then
        if not mergeVehicleIdentity(vehicleKey, newKey) then
            return false, vehicleKey
        end
        vehicleKey = newKey
        record = app.settings.vehicles[vehicleKey]
    end

    if type(record) == "table" then
        record.manual_identity = value
        record.unstable = false
        record.label = getVehicleLabel(record)
        saveSettings()
    end

    return true, vehicleKey
end

local function resolveVehicleCandidate(payload, manualName)
    local cefMeta = extractVehicleMetaFromPayload(payload)
    local localMeta = findNearestVehicle(8.0, cefMeta)
    local meta = {}

    for k, v in pairs(cefMeta) do
        meta[k] = v
    end
    if localMeta then
        for k, v in pairs(localMeta) do
            if meta[k] == nil then
                meta[k] = v
            end
        end
    end

    if manualName and manualName ~= "" then
        meta.manual_name = manualName
        meta.vehicle_key = "manual:" .. normalizeSearchText(manualName)
        meta.unstable = false
    else
        local stable = getStableVehicleIdFromPayload(meta)
        if stable then
            meta.vehicle_key = stable
            meta.unstable = false
        else
            meta.vehicle_key = makeTransientVehicleKey(meta)
            meta.unstable = true
        end
    end

    local record = registerDetectedVehicle(meta)
    if record then
        if manualName and manualName ~= "" then
            record.manual_name = manualName
            record.label = getVehicleLabel(record)
            app.settings.vehicles[record.vehicle_key] = record
            saveSettings()
        end
        return {
            vehicle_key = record.vehicle_key,
            vehicle_name = getVehicleLabel(record),
            model_id = record.model_id,
            plate = record.plate,
            samp_vehicle_id = record.samp_vehicle_id,
            unstable = record.unstable
        }
    end

    return nil
end

bindFingerprint = function(fingerprint, kind, identity)
    fingerprint = safeString(fingerprint)
    if fingerprint == "" then
        return false
    end
    app.settings.bindings.fingerprints[fingerprint] = {
        kind = kind,
        identity = deepCopy(identity or {}),
        updated_at = unixTime()
    }
    return saveSettings()
end

local function resolveFingerprintBinding(fingerprint)
    fingerprint = safeString(fingerprint)
    if fingerprint == "" then
        return nil
    end
    local binding = app.settings.bindings.fingerprints[fingerprint]
    if type(binding) ~= "table" or not binding.kind or type(binding.identity) ~= "table" then
        return nil
    end
    return binding
end

local function createPendingIdentity(kind, value)
    if kind == STORAGE_KIND.HOUSE_CLOSET or kind == STORAGE_KIND.HOUSE_OBJECT then
        return { house_number = value }
    end

    if kind == STORAGE_KIND.WAREHOUSE then
        return { warehouse_number = value }
    end

    if kind == STORAGE_KIND.VEHICLE_TRUNK then
        return {
            vehicle_key = "manual:" .. normalizeSearchText(value),
            vehicle_name = value,
            manual_name = value,
            unstable = false
        }
    end

    return {}
end

local function isStorageCaptureKind(kind)
    return STORAGE_CAPTURE_KIND_SET[kind] == true
end

local function normalizeCaptureKind(kind)
    return isStorageCaptureKind(kind) and kind or STORAGE_KIND.UNKNOWN
end

local function beginExternalCandidate(kind, identity, reason, fingerprint)
    local candidate = {
        kind = normalizeCaptureKind(kind),
        identity = deepCopy(identity or {}),
        reason = safeString(reason),
        fingerprint = fingerprint,
        started_ms = nowMs(),
        last_update_ms = nowMs(),
        packet_count = 0,
        items_by_slot = {},
        items_no_slot = {},
        no_slot_map = {}
    }
    app.external_candidate = candidate
    return candidate
end

local function ensureExternalCandidate(kind, identity, reason, fingerprint)
    kind = normalizeCaptureKind(kind)
    local candidate = app.external_candidate
    local now = nowMs()
    local stale = candidate and now - safeNumber(candidate.last_update_ms, now) > 10000
    local fingerprintChanged = candidate and fingerprint and candidate.fingerprint and candidate.fingerprint ~= fingerprint
    local kindChanged = candidate and isStorageCaptureKind(candidate.kind) and isStorageCaptureKind(kind) and candidate.kind ~= kind

    if not candidate or stale or fingerprintChanged or kindChanged then
        candidate = beginExternalCandidate(kind, identity, reason, fingerprint)
    else
        if candidate.kind == STORAGE_KIND.UNKNOWN and isStorageCaptureKind(kind) then candidate.kind = kind end
        if type(identity) == "table" then
            candidate.identity = type(candidate.identity) == "table" and candidate.identity or {}
            for key, value in pairs(identity) do
                if value ~= nil and safeString(value) ~= "" then candidate.identity[key] = deepCopy(value) end
            end
        end
        if fingerprint and not candidate.fingerprint then candidate.fingerprint = fingerprint end
    end
    return candidate
end

local function appendExternalCandidateItems(candidate, items, groupKey)
    if type(candidate) ~= "table" or type(items) ~= "table" then return false end
    groupKey = safeString(groupKey, "external")
    for i = 1, #items do
        local item = items[i]
        if type(item) == "table" then
            if item.slot ~= nil then
                local sourceKey = item.inventory_type ~= nil and safeString(item.inventory_type) or groupKey
                candidate.items_by_slot[sourceKey .. ":" .. safeString(item.slot)] = item
            else
                local signature = safeString(item.signature, buildItemSignature(item))
                candidate.no_slot_map[groupKey .. ":" .. signature] = item
            end
        end
    end
    candidate.items_no_slot = {}
    for _, item in pairs(candidate.no_slot_map) do candidate.items_no_slot[#candidate.items_no_slot + 1] = item end
    candidate.packet_count = safeNumber(candidate.packet_count, 0) + 1
    candidate.last_update_ms = nowMs()
    if app.manual_scan.requested then app.manual_scan.finish_after_ms = candidate.last_update_ms + 450 end
    return true
end

local function pruneExternalRecentGroups()
    local now = nowMs()
    local kept = {}
    for i = 1, #(app.external_recent_groups or {}) do
        local row = app.external_recent_groups[i]
        if type(row) == "table" and now - safeNumber(row.time_ms, 0) <= 4000 then kept[#kept + 1] = row end
    end
    while #kept > 24 do table.remove(kept, 1) end
    app.external_recent_groups = kept
end

local function rememberExternalRecentGroup(inventoryType, items)
    pruneExternalRecentGroups()
    app.external_recent_groups[#app.external_recent_groups + 1] = {
        time_ms = nowMs(),
        inventory_type = inventoryType,
        items = deepCopy(items or {})
    }
end

local function captureExternalPlayerInventory(payload)
    local data = getPlayerInventoryPayload(payload)
    if not data then return false end
    local inventoryType = safeNumber(data.type, nil)
    if inventoryType == nil or NON_STORAGE_INVENTORY_TYPES[inventoryType] then return false end

    local items = normalizeItemList(data.items, inventoryType)
    rememberExternalRecentGroup(inventoryType, items)
    app.external_last_payload = payload
    if not app.external_ui_visible and not app.manual_scan.requested then return false end

    local candidate = ensureExternalCandidate(app.external_kind_hint, {}, "event.inventory.playerInventory", nil)
    appendExternalCandidateItems(candidate, items, "type:" .. safeString(inventoryType))
    return true
end

local function markExternalUiVisible(kindHint)
    kindHint = normalizeCaptureKind(kindHint)
    local now = nowMs()
    app.external_ui_visible = true
    app.external_visible_ms = now
    if isStorageCaptureKind(kindHint) then app.external_kind_hint = kindHint end

    -- A trunk/house window also shows the player's inventory on the right.
    -- Do not persist that right-side inventory as a separate scan while external storage is open.
    app.player_scan_active = false
    if app.snapshot and app.snapshot.kind == STORAGE_KIND.PLAYER_INVENTORY then
        cancelStorageSnapshot("external storage opened")
    end

    local candidate = app.external_candidate
    if candidate and now - safeNumber(candidate.last_update_ms, now) > 4000 then
        candidate = nil
        app.external_candidate = nil
    end
    candidate = candidate or beginExternalCandidate(app.external_kind_hint, {}, "storage ui visible", nil)
    if candidate.kind == STORAGE_KIND.UNKNOWN and isStorageCaptureKind(app.external_kind_hint) then candidate.kind = app.external_kind_hint end

    pruneExternalRecentGroups()
    for i = 1, #app.external_recent_groups do
        local row = app.external_recent_groups[i]
        if now - safeNumber(row.time_ms, 0) <= 2500 then
            appendExternalCandidateItems(candidate, row.items or {}, "type:" .. safeString(row.inventory_type))
        end
    end
    return true
end

local function markExternalUiClosed(reason)
    app.external_ui_visible = false
    app.external_kind_hint = nil
    app.external_visible_ms = 0
    app.external_last_payload = nil
    app.external_candidate = nil
    app.manual_scan.requested = false
    app.manual_scan.finish_after_ms = 0
    if not app.manual_scan.dialog_open then app.manual_scan.snapshot = nil end
    saveLog("[ArzMarket][StorageFinder] external UI closed: " .. safeString(reason, "unknown"))
    return true
end

local function tryCaptureExternal(eventName, payload)
    if eventName == "event.inventory.playerInventory" then return false end

    local detectedKind = detectExternalKind(eventName, payload)
    if not isStorageCaptureKind(detectedKind) and isStorageCaptureKind(app.external_kind_hint) then detectedKind = app.external_kind_hint end

    local fingerprint = extractStorageFingerprint and extractStorageFingerprint(payload) or nil
    local binding = fingerprint and resolveFingerprintBinding(fingerprint) or nil
    local identity = {}
    local kind = normalizeCaptureKind(detectedKind)

    if binding and isStorageCaptureKind(binding.kind) then
        kind = binding.kind
        identity = deepCopy(binding.identity or {})
    elseif kind == STORAGE_KIND.VEHICLE_TRUNK then
        identity = resolveVehicleCandidate(payload, nil) or {}
    end

    local rawItems, path = extractExternalItems(payload)
    if not rawItems then return false end
    if kind == STORAGE_KIND.UNKNOWN and not app.external_ui_visible then return false end

    app.external_last_payload = payload
    local candidate = ensureExternalCandidate(kind, identity, eventName .. " " .. safeString(path), fingerprint)
    appendExternalCandidateItems(candidate, normalizeItemList(rawItems, nil), eventName .. ":" .. safeString(path))
    return true
end

extractStorageFingerprint = function(payload)
    if type(payload) ~= "table" then
        return nil
    end

    local preferred = {
        "storage_uid",
        "storageUid",
        "storage_id",
        "storageId",
        "warehouse_id",
        "warehouseId",
        "house_id",
        "houseId",
        "vehicle_uid",
        "vehicleUid"
    }

    local found = nil

    local function walk(value, depth)
        if found or type(value) ~= "table" or depth > 5 then
            return
        end

        for i = 1, #preferred do
            local key = preferred[i]
            if value[key] ~= nil then
                local v = safeString(value[key])
                if v ~= "" then
                    found = key .. ":" .. v
                    return
                end
            end
        end

        for _, child in pairs(value) do
            if type(child) == "table" then
                walk(child, depth + 1)
                if found then
                    return
                end
            end
        end
    end

    walk(payload, 0)
    return found
end

local function routeArizonaEvent(eventName, payload)
    app.last_event = eventName
    logInventoryEvent(eventName, payload)

    if eventName == "event.setActiveView" and type(payload) == "table" then
        app.active_view = safeString(payload[1], "")
        return
    end

    if eventName == "event.inventory.updateCharacterTab" and type(payload) == "table" then
        app.character_tab = safeString(payload[1], "")
        return
    end

    if eventName == "event.inventory.setPlayerInventoryVisible" then
        local visible = payloadBoolean(payload)
        if visible ~= nil then
            app.player_inventory_visible = visible
            if visible then
                if type(app.settings.pending_binding) == "table" then
                    app.player_scan_active = false
                    if app.snapshot and app.snapshot.kind == STORAGE_KIND.PLAYER_INVENTORY then
                        app.snapshot = nil
                    end
                else
                    if app.snapshot and app.snapshot.kind == STORAGE_KIND.PLAYER_INVENTORY then
                        app.snapshot = nil
                    end
                    app.player_scan_active = true
                    beginStorageSnapshot(STORAGE_KIND.PLAYER_INVENTORY, {}, "inventory visible")
                end
            elseif app.snapshot and app.snapshot.kind == STORAGE_KIND.PLAYER_INVENTORY then
                if app.snapshot.packet_count > 0 then
                    commitStorageSnapshot(app.snapshot)
                else
                    cancelStorageSnapshot("inventory closed before item data")
                    app.player_scan_active = false
                end
            else
                app.player_scan_active = false
            end
        end
        return
    end

    if eventName == "event.inventory.playerInventory" then
        handlePlayerInventory(payload)
        captureExternalPlayerInventory(payload)
        return
    end

    local fingerprint = extractStorageFingerprint(payload)
    if fingerprint and isInventoryRelatedEvent(eventName) then
        appendDebugLine(os.date("%Y-%m-%d %H:%M:%S") .. " FINGERPRINT=" .. fingerprint .. " EVENT=" .. safeString(eventName))
    end

    tryCaptureExternal(eventName, payload)
end

local function decodeArizonaPacket(packet)
    if not acef_ok or type(acef) ~= "table" then
        return false
    end

    local ok, decoded = pcall(function()
        return acef.decode(packet)
    end)

    if not ok or not decoded then
        return false
    end

    if type(packet.event) ~= "string" or packet.event == "" then
        return false
    end

    if type(packet.json) ~= "table" then
        return false
    end

    return true
end

local function routeArizonaEventOnce(eventName, payload)
    local eventKey = safeString(eventName) .. "|" .. stableSerialize(payload)
    local currentMs = nowMs()
    local previousMs = tonumber(app.last_routed_event_ms) or 0

    if app.last_routed_event_key == eventKey
        and currentMs >= previousMs
        and currentMs - previousMs <= 150 then
        return true
    end

    app.last_routed_event_key = eventKey
    app.last_routed_event_ms = currentMs
    routeArizonaEvent(eventName, payload)
    return true
end

if acef_ok and type(acef) == "table" then
    function acef.onArizonaDisplay(packet)
        local ok, err = pcall(function()
            if decodeArizonaPacket(packet) then
                routeArizonaEventOnce(packet.event, packet.json)
            end
        end)

        if not ok then
            app.last_error = "CEF callback: " .. safeString(err)
            appendDebugLine(os.date("%Y-%m-%d %H:%M:%S") .. " ERROR=" .. safeString(err))
        end

        -- The incoming Arizona CEF packet is not changed or blocked.
    end
end

local function removeValue(list, value)
    if type(list) ~= "table" then
        return false
    end
    value = safeString(value)
    for i = #list, 1, -1 do
        if safeString(list[i]) == value then
            table.remove(list, i)
            return true
        end
    end
    return false
end

local function addHouseNumber(number)
    number = trim(number)
    if number == "" then return false end
    for i = 1, #app.settings.houses do
        if safeString(app.settings.houses[i]) == number then return true end
    end
    app.settings.houses[#app.settings.houses + 1] = number
    return saveSettings()
end

local function editHouseNumber(oldNumber, newNumber)
    oldNumber = trim(oldNumber)
    newNumber = trim(newNumber)
    if oldNumber == "" or newNumber == "" then return false end
    if oldNumber == newNumber then return true end

    for i = 1, #app.settings.houses do
        if safeString(app.settings.houses[i]) == newNumber then
            app.last_error = "Дом №" .. newNumber .. " уже существует."
            return false
        end
    end

    local variants = {
        { suffix = ":closet", kind = STORAGE_KIND.HOUSE_CLOSET },
        { suffix = ":object", kind = STORAGE_KIND.HOUSE_OBJECT }
    }

    for i = 1, #variants do
        local oldKey = "house:" .. oldNumber .. variants[i].suffix
        local newKey = "house:" .. newNumber .. variants[i].suffix
        if app.database.storages[oldKey] and app.database.storages[newKey] then
            app.last_error = "Нельзя переименовать дом: целевое хранилище уже существует."
            return false
        end
    end

    local found = false
    for i = 1, #app.settings.houses do
        if safeString(app.settings.houses[i]) == oldNumber then
            app.settings.houses[i] = newNumber
            found = true
            break
        end
    end
    if not found then return false end

    for i = 1, #variants do
        local oldKey = "house:" .. oldNumber .. variants[i].suffix
        local newKey = "house:" .. newNumber .. variants[i].suffix
        local storage = app.database.storages[oldKey]

        if storage then
            app.database.storages[oldKey] = nil
            storage.storage_key = newKey
            storage.identity = type(storage.identity) == "table" and storage.identity or {}
            storage.identity.house_number = newNumber
            storage.label = buildStorageLabel(variants[i].kind, storage.identity)
            app.database.storages[newKey] = storage
        end
    end

    for _, binding in pairs(app.settings.bindings.fingerprints) do
        if type(binding) == "table" and type(binding.identity) == "table" and
           safeString(binding.identity.house_number) == oldNumber then
            binding.identity.house_number = newNumber
        end
    end

    invalidateSearchIndex()
    saveDatabaseAtomic()
    return saveSettings()
end

local function removeHouseNumber(number)
    local changed = removeValue(app.settings.houses, trim(number))
    if changed then return saveSettings() end
    return false
end

local function addWarehouseNumber(number)
    number = trim(number)
    if number == "" then return false end
    for i = 1, #app.settings.warehouses do
        if safeString(app.settings.warehouses[i]) == number then return true end
    end
    app.settings.warehouses[#app.settings.warehouses + 1] = number
    return saveSettings()
end

local function editWarehouseNumber(oldNumber, newNumber)
    oldNumber = trim(oldNumber)
    newNumber = trim(newNumber)
    if oldNumber == "" or newNumber == "" then return false end
    if oldNumber == newNumber then return true end

    for i = 1, #app.settings.warehouses do
        if safeString(app.settings.warehouses[i]) == newNumber then
            app.last_error = "Склад №" .. newNumber .. " уже существует."
            return false
        end
    end

    local oldKey = "warehouse:" .. oldNumber
    local newKey = "warehouse:" .. newNumber

    if app.database.storages[oldKey] and app.database.storages[newKey] then
        app.last_error = "Нельзя переименовать склад: целевое хранилище уже существует."
        return false
    end

    local found = false
    for i = 1, #app.settings.warehouses do
        if safeString(app.settings.warehouses[i]) == oldNumber then
            app.settings.warehouses[i] = newNumber
            found = true
            break
        end
    end
    if not found then return false end

    local storage = app.database.storages[oldKey]

    if storage then
        app.database.storages[oldKey] = nil
        storage.storage_key = newKey
        storage.identity = type(storage.identity) == "table" and storage.identity or {}
        storage.identity.warehouse_number = newNumber
        storage.label = buildStorageLabel(STORAGE_KIND.WAREHOUSE, storage.identity)
        app.database.storages[newKey] = storage
    end

    for _, binding in pairs(app.settings.bindings.fingerprints) do
        if type(binding) == "table" and type(binding.identity) == "table" and
           safeString(binding.identity.warehouse_number) == oldNumber then
            binding.identity.warehouse_number = newNumber
        end
    end

    invalidateSearchIndex()
    saveDatabaseAtomic()
    return saveSettings()
end

local function removeWarehouseNumber(number)
    local changed = removeValue(app.settings.warehouses, trim(number))
    if changed then return saveSettings() end
    return false
end

local function appendUnique(list, value)
    if type(list) ~= "table" then
        return
    end

    value = safeString(value)
    for i = 1, #list do
        if safeString(list[i]) == value then
            return
        end
    end

    list[#list + 1] = value
end

local function setPendingBinding(kind, value)
    value = safeString(value)
    if value == "" then
        return false
    end

    if kind == STORAGE_KIND.HOUSE_CLOSET or kind == STORAGE_KIND.HOUSE_OBJECT then
        addHouseNumber(value)
    elseif kind == STORAGE_KIND.WAREHOUSE then
        addWarehouseNumber(value)
    end

    app.settings.pending_binding = {
        kind = kind,
        value = value,
        created_at = unixTime()
    }

    saveSettings()
    return true
end


local STORAGE_FILTERS = {
    { value = "all", label = "Все места" },
    { value = STORAGE_KIND.PLAYER_INVENTORY, label = "Инвентарь" },
    { value = STORAGE_KIND.HOUSE_CLOSET, label = "Дом" },
    { value = STORAGE_KIND.HOUSE_OBJECT, label = "Объект возле дома" },
    { value = STORAGE_KIND.VEHICLE_TRUNK, label = "Багажники" },
    { value = STORAGE_KIND.WAREHOUSE, label = "Склады" }
}

local CATEGORY_FILTERS = {
    { value = "all", label = "Все предметы" },
    { value = CATEGORY.ACCESSORIES, label = "Аксессуары" },
    { value = CATEGORY.CASES, label = "Ларцы" },
    { value = CATEGORY.SKINS, label = "Скины" },
    { value = CATEGORY.WEAPONS, label = "Оружие" },
    { value = CATEGORY.CERTIFICATES, label = "Сертификаты" },
    { value = CATEGORY.TUNING, label = "Тюнинг" },
    { value = CATEGORY.UPGRADES, label = "Улучшения" },
    { value = CATEGORY.RESOURCES, label = "Ресурсы/крафт" },
    { value = CATEGORY.OBJECTS, label = "Объекты" },
    { value = CATEGORY.SHARDS, label = "Осколки" },
    { value = CATEGORY.OTHER, label = "Прочее" }
}

local CATEGORY_LABELS = {
    [CATEGORY.ACCESSORIES] = "Аксессуары",
    [CATEGORY.CASES] = "Ларцы",
    [CATEGORY.SKINS] = "Скины",
    [CATEGORY.WEAPONS] = "Оружие",
    [CATEGORY.CERTIFICATES] = "Сертификаты",
    [CATEGORY.TUNING] = "Тюнинг",
    [CATEGORY.UPGRADES] = "Улучшения",
    [CATEGORY.RESOURCES] = "Ресурсы/крафт",
    [CATEGORY.OBJECTS] = "Объекты",
    [CATEGORY.SHARDS] = "Осколки",
    [CATEGORY.OTHER] = "Прочее"
}


local function invalidateVisibleRows()
    app.visible_rows_dirty = true
end

local function getOptionLabel(options, value)
    for i = 1, #options do
        if options[i].value == value then
            return options[i].label
        end
    end
    return "Неизвестно"
end

local function getCategoryLabel(category)
    return CATEGORY_LABELS[normalizeCategory(category)] or "Прочее"
end

local function formatLastScan(timestamp)
    local value = safeNumber(timestamp, 0)
    if value <= 0 then
        return "неизвестно"
    end
    local ok, result = pcall(os.date, "%d.%m.%Y %H:%M", value)
    return ok and result or "неизвестно"
end

local STALE_AFTER_SECONDS = 24 * 60 * 60

local function getStorageAge(timestamp)
    local value = safeNumber(timestamp, 0)
    if value <= 0 then
        return math.huge
    end
    return math.max(0, unixTime() - value)
end

local function isStorageStale(timestamp)
    return getStorageAge(timestamp) >= STALE_AFTER_SECONDS
end

local function formatFreshness(timestamp)
    local text = formatLastScan(timestamp)
    if isStorageStale(timestamp) then
        return text .. " [устарело]"
    end
    return text
end


local function externalCandidateToSnapshot(candidate, kind)
    candidate = type(candidate) == "table" and candidate or beginExternalCandidate(kind, {}, "manual empty scan", nil)
    return {
        kind = normalizeCaptureKind(kind),
        identity = deepCopy(candidate.identity or {}),
        key = "pending:manual",
        label = "Ожидает подтверждения",
        started_at = unixTime(),
        started_ms = nowMs(),
        last_update_ms = safeNumber(candidate.last_update_ms, nowMs()),
        commit_after_ms = nil,
        reason = "manual storage scan",
        items_by_slot = deepCopy(candidate.items_by_slot or {}),
        items_no_slot = deepCopy(candidate.items_no_slot or {}),
        packet_count = safeNumber(candidate.packet_count, 0),
        fingerprint = candidate.fingerprint
    }
end

local function getManualScanSuggestedName(kind, snapshot)
    local identity = type(snapshot) == "table" and type(snapshot.identity) == "table" and snapshot.identity or {}
    if kind == STORAGE_KIND.VEHICLE_TRUNK then
        local name = trim(identity.manual_name or identity.vehicle_name or "")
        if name ~= "" and name ~= "Автомобиль" then return name end
        local nearest = findNearestVehicle(8.0, {})
        if type(nearest) == "table" then return trim(nearest.gxt_name or nearest.server_name or nearest.gxt_key or "") end
    elseif kind == STORAGE_KIND.HOUSE_CLOSET or kind == STORAGE_KIND.HOUSE_OBJECT then
        return trim(identity.house_number or "")
    elseif kind == STORAGE_KIND.WAREHOUSE then
        return trim(identity.warehouse_number or "")
    end
    return ""
end

local function updateStorageScanCefButton(state)
    if type(get_cef) ~= "function" then return end
    local text = state == "scanning" and "\\u0421\\u041a\\u0410\\u041d\\u0418\\u0420\\u041e\\u0412\\u0410\\u041d\\u0418\\u0415..."
        or "\\u0421\\u041a\\u0410\\u041d\\u0418\\u0420\\u041e\\u0412\\u0410\\u0422\\u042c"
    pcall(get_cef, "(function(){var b=document.getElementById('arzmarket_storage_scan_button');if(b){b.textContent='" .. text .. "';b.style.pointerEvents='" .. (state == "scanning" and "none" or "auto") .. "';b.style.opacity='" .. (state == "scanning" and "0.72" or "1") .. "';}})();")
end

local function requestManualExternalScan(kindHint)
    kindHint = normalizeCaptureKind(kindHint)
    if isStorageCaptureKind(kindHint) then
        markExternalUiVisible(kindHint)
    elseif not app.external_ui_visible then
        app.last_error = "Не удалось определить открытое хранилище. Закрой и открой его заново."
        if type(sendNotify) == "function" then
            local okEncoding, cpText = pcall(function() return u8:decode(app.last_error) end)
            pcall(sendNotify, okEncoding and cpText or app.last_error)
        end
        return false
    end

    app.manual_scan.requested = true
    app.manual_scan.started_ms = nowMs()
    app.manual_scan.finish_after_ms = nowMs() + 700
    app.manual_scan.error = nil
    updateStorageScanCefButton("scanning")
    return true
end

local function processManualExternalScanTimer()
    if not app.manual_scan.requested then return end
    local now = nowMs()
    local candidate = app.external_candidate
    if candidate and safeNumber(candidate.last_update_ms, 0) > app.manual_scan.started_ms then
        app.manual_scan.finish_after_ms = math.max(app.manual_scan.finish_after_ms, safeNumber(candidate.last_update_ms, now) + 450)
    end
    if now < safeNumber(app.manual_scan.finish_after_ms, now + 1) then return end

    app.manual_scan.requested = false
    local selectedKind = normalizeCaptureKind(app.external_kind_hint)
    if selectedKind == STORAGE_KIND.UNKNOWN and type(candidate) == "table" then selectedKind = normalizeCaptureKind(candidate.kind) end
    if selectedKind == STORAGE_KIND.UNKNOWN then selectedKind = STORAGE_KIND.VEHICLE_TRUNK end

    local snapshot = externalCandidateToSnapshot(candidate, selectedKind)
    snapshot.kind = selectedKind
    app.manual_scan.snapshot = snapshot
    app.manual_scan.selected_kind = selectedKind
    app.manual_scan.suggested_name = getManualScanSuggestedName(selectedKind, snapshot)
    app.manual_scan.name_initialized = false
    app.manual_scan.error = nil
    app.manual_scan.dialog_open = true
    updateStorageScanCefButton("ready")
end

local function buildManualStorageIdentity(kind, name, snapshot)
    local sourceIdentity = type(snapshot.identity) == "table" and snapshot.identity or {}
    if kind == STORAGE_KIND.VEHICLE_TRUNK then
        local vehicleKey = "manual:" .. normalizeSearchText(name)
        local record = type(app.settings.vehicles[vehicleKey]) == "table" and app.settings.vehicles[vehicleKey] or {}
        record.vehicle_key = vehicleKey
        record.manual_name = name
        record.manual_identity = record.manual_identity or name
        record.label = name
        record.unstable = false
        record.last_seen = unixTime()
        for _, key in ipairs({ "model_id", "plate", "samp_vehicle_id", "server_vehicle_id", "owner_slot", "uid" }) do
            if record[key] == nil and sourceIdentity[key] ~= nil then record[key] = sourceIdentity[key] end
        end
        app.settings.vehicles[vehicleKey] = record
        saveSettings()
        return {
            vehicle_key = vehicleKey, vehicle_name = name, manual_name = name, manual_identity = name,
            model_id = record.model_id, plate = record.plate, samp_vehicle_id = record.samp_vehicle_id, unstable = false
        }
    elseif kind == STORAGE_KIND.HOUSE_CLOSET or kind == STORAGE_KIND.HOUSE_OBJECT then
        addHouseNumber(name)
        return { house_number = name }
    elseif kind == STORAGE_KIND.WAREHOUSE then
        addWarehouseNumber(name)
        return { warehouse_number = name }
    end
    return nil
end

local function saveManualExternalScan(kind, name)
    local state = app.manual_scan
    local snapshot = state.snapshot
    kind = normalizeCaptureKind(kind)
    name = trim(name)

    if not isStorageCaptureKind(kind) then state.error = "Выбери тип хранилища." return false end
    if name == "" then
        if kind == STORAGE_KIND.VEHICLE_TRUNK then state.error = "Укажи название автомобиля."
        elseif kind == STORAGE_KIND.WAREHOUSE then state.error = "Укажи номер или название склада."
        else state.error = "Укажи номер дома или название хранилища." end
        return false
    end
    if type(snapshot) ~= "table" then state.error = "Данные сканирования потеряны. Выполни сканирование заново." return false end

    local identity = buildManualStorageIdentity(kind, name, snapshot)
    if type(identity) ~= "table" then state.error = "Не удалось подготовить данные хранилища." return false end

    snapshot.kind = kind
    snapshot.identity = identity
    snapshot.key = makeStorageKey(kind, identity)
    snapshot.label = buildStorageLabel(kind, identity)
    snapshot.reason = "manual confirmed storage scan"

    local ok = commitStorageSnapshot(snapshot)
    if not ok then state.error = safeString(app.last_error, "Не удалось сохранить хранилище.") return false end

    state.dialog_open = false
    state.snapshot = nil
    state.error = nil
    state.name_initialized = false
    invalidateVisibleRows()
    if type(sendNotify) == "function" then
        local utf8Notice = "Хранилище сохранено: " .. snapshot.label .. ". Предметов: " .. safeString(app.last_scan and app.last_scan.count or 0)
        local okEncoding, cpNotice = pcall(function() return u8:decode(utf8Notice) end)
        pcall(sendNotify, okEncoding and cpNotice or utf8Notice)
    end
    return true
end


local function cleanupBindings(predicate)
    local bindings = app.settings.bindings and app.settings.bindings.fingerprints
    if type(bindings) ~= "table" then
        return
    end

    for fingerprint, binding in pairs(bindings) do
        if type(binding) == "table" and predicate(binding) then
            bindings[fingerprint] = nil
        end
    end
end

local function deleteHouse(number, removeHistory)
    number = safeString(number)
    removeHouseNumber(number)

    cleanupBindings(function(binding)
        return type(binding.identity) == "table"
            and safeString(binding.identity.house_number) == number
    end)

    if removeHistory then
        app.database.storages["house:" .. number .. ":closet"] = nil
        app.database.storages["house:" .. number .. ":object"] = nil
        invalidateSearchIndex()
        saveDatabaseAtomic()
    end

    saveSettings()
end

local function deleteWarehouse(number, removeHistory)
    number = safeString(number)
    removeWarehouseNumber(number)

    cleanupBindings(function(binding)
        return type(binding.identity) == "table"
            and safeString(binding.identity.warehouse_number) == number
    end)

    if removeHistory then
        app.database.storages["warehouse:" .. number] = nil
        invalidateSearchIndex()
        saveDatabaseAtomic()
    end

    saveSettings()
end

local function forgetVehicle(vehicleKey, removeHistory)
    vehicleKey = safeString(vehicleKey)
    if vehicleKey == "" then
        return
    end

    app.settings.vehicles[vehicleKey] = nil

    cleanupBindings(function(binding)
        return type(binding.identity) == "table"
            and safeString(binding.identity.vehicle_key) == vehicleKey
    end)

    if removeHistory then
        app.database.storages["vehicle:" .. vehicleKey] = nil
        invalidateSearchIndex()
        saveDatabaseAtomic()
    end

    saveSettings()
end


local function initApp()
    ensureDataDirectory()
    loadSettings()
    loadCategoryMap()
    local learnedNames = select(1, loadJsonSafe(app.item_names_path, {}))
    app.item_names = type(learnedNames) == "table" and learnedNames or {}
    loadDatabase()
    upgradeStoredItems()

    if not doesFileExist(app.settings_path) then
        saveSettings()
    end

    if not doesFileExist(app.database_path) then
        saveDatabaseAtomic()
    else
        saveDatabaseAtomic()
    end

    if not doesFileExist(app.category_path) then
        saveCategoryMap()
    end

    app.settings.debug.enabled = true
    saveSettings()


    invalidateSearchIndex()
    app.ready = true
end


local function matchesStorageType(row, filter)
    return filter == "all" or row.storage_kind == filter
end

local function matchesSearch(row, query)
    return query == "" or string.find(row.search_text or "", query, 1, true) ~= nil
end

local function getVisibleRows(query, filters)
    filters = type(filters) == "table" and filters or {}
    query = normalizeSearchText(query)
    local storageFilter, specificStorageKey, categoryFilter = filters.storage_type or "all", safeString(filters.storage_key), filters.category or "all"
    local index, grouped, order = getIndexedItems(), {}, {}
    for i = 1, #index do
        local row = index[i]
        if matchesStorageType(row, storageFilter) and (specificStorageKey == "" or row.storage_key == specificStorageKey)
            and (categoryFilter == "all" or normalizeCategory(row.category) == categoryFilter) and matchesSearch(row, query) then
            local signature = safeString(row.signature, safeString(row.item_id) .. "|" .. safeString(row.name))
            local groupKey = table.concat({row.storage_key, signature, normalizeSearchText(row.name)}, string.char(31))
            local current = grouped[groupKey]
            if not current then current=deepCopy(row);current.count=0;current.stack_count=0;grouped[groupKey]=current;order[#order+1]=current end
            current.count=current.count+normalizeCount(row.count);current.stack_count=current.stack_count+1
        end
    end
    table.sort(order,function(a,b)local an,bn=normalizeSearchText(a.name),normalizeSearchText(b.name);if an==bn then return safeString(a.storage_label)<safeString(b.storage_label) end return an<bn end)
    app.visible_rows=order;app.visible_rows_dirty=false;return order
end
local function getSpecificStorageOptions(storageFilter)
    local options,seen={},{}
    if storageFilter=="all" or storageFilter==STORAGE_KIND.PLAYER_INVENTORY then return options end
    if app.database and type(app.database.storages)=="table" then
        for storageKey,storage in pairs(app.database.storages) do
            if type(storage)=="table" and storage.kind==storageFilter then
                local label=safeString(storage.label,storageKey)
                if storageFilter==STORAGE_KIND.VEHICLE_TRUNK then
                    local vehicleKey=type(storage.identity)=="table" and storage.identity.vehicle_key or nil
                    local vehicle=vehicleKey and app.settings.vehicles[vehicleKey] or nil
                    if type(vehicle)=="table" then label=getVehicleLabel(vehicle).." -> Багажник" end
                end
                if not seen[storageKey] then seen[storageKey]=true;options[#options+1]={value=storageKey,label=label} end
            end
        end
    end
    table.sort(options,function(a,b)return normalizeSearchText(a.label)<normalizeSearchText(b.label) end);return options
end
local function isSpecificStorageStillValid(options,storageKey)
    if safeString(storageKey)=="" then return true end
    for i=1,#options do if options[i].value==storageKey then return true end end
    return false
end
local function buildCatalog(query)
    query=normalizeSearchText(query);local catalogByName,catalog={},{};local index=getIndexedItems()
    for i=1,#index do
        local row=index[i];local itemName=safeString(row.name,"Неизвестный предмет");local itemKey=normalizeSearchText(itemName)
        if itemKey~="" and (query=="" or string.find(itemKey,query,1,true)~=nil) then
            local itemEntry=catalogByName[itemKey]
            if not itemEntry then itemEntry={key=itemKey,name=itemName,count=0,locations_by_key={},locations={}};catalogByName[itemKey]=itemEntry;catalog[#catalog+1]=itemEntry end
            itemEntry.count=itemEntry.count+normalizeCount(row.count)
            local storageKey=safeString(row.storage_key,"unknown:"..safeString(i));local location=itemEntry.locations_by_key[storageKey]
            if not location then location={key=storageKey,kind=row.storage_kind,label=row.storage_label,identity=type(row.storage_identity)=="table" and deepCopy(row.storage_identity) or {}};itemEntry.locations_by_key[storageKey]=location;itemEntry.locations[#itemEntry.locations+1]=location end
        end
    end
    table.sort(catalog,function(a,b)return normalizeSearchText(a.name)<normalizeSearchText(b.name) end)
    for i=1,#catalog do table.sort(catalog[i].locations,function(a,b)local ak,bk=safeString(a.kind),safeString(b.kind);if ak==bk then return safeString(a.label)<safeString(b.label) end return ak<bk end) end
    return catalog
end
local function formatStorageLocation(location)
    local identity=type(location.identity)=="table" and location.identity or {}
    if location.kind==STORAGE_KIND.VEHICLE_TRUNK then local v=trim(safeString(identity.vehicle_name,safeString(location.label,"Автомобиль"):gsub("%s*%-%>%s*Багажник%s*$","")));if v=="" then v="Автомобиль" end;return "Машина №"..v
    elseif location.kind==STORAGE_KIND.HOUSE_CLOSET then local n=trim(safeString(identity.house_number));if n=="" then n=safeString(location.label):match("Дом №(.+)%s+%-%>") or safeString(location.label) end;return "Дом №"..n
    elseif location.kind==STORAGE_KIND.HOUSE_OBJECT then local n=trim(safeString(identity.house_number));if n=="" then n=safeString(location.label):match("Дом №(.+)%s+%-%>") or safeString(location.label) end;return "Дом №"..n..", объект возле дома"
    elseif location.kind==STORAGE_KIND.WAREHOUSE then local n=trim(safeString(identity.warehouse_number));if n=="" then n=safeString(location.label):match("Склад №(.+)$") or safeString(location.label) end;return "Склад №"..n
    elseif location.kind==STORAGE_KIND.PLAYER_INVENTORY then return "Инвентарь" end
    return safeString(location.label,"Неизвестное хранилище")
end
local function getSortedVehicleKeys()
    local keys={};for key,_ in pairs(app.settings.vehicles) do keys[#keys+1]=key end
    table.sort(keys,function(a,b)local av,bv=app.settings.vehicles[a],app.settings.vehicles[b];local al=type(av)=="table" and getVehicleLabel(av) or a;local bl=type(bv)=="table" and getVehicleLabel(bv) or b;return normalizeSearchText(al)<normalizeSearchText(bl) end);return keys
end

function M.init(ctx)
    context=type(ctx)=="table" and ctx or {}
    if type(context.decodeJson)~="function" or type(context.encodeJson)~="function" then return false,"json_context_missing" end
    if app.ready then return true end
    app.shutting_down=false;local ok,err=pcall(initApp);if not ok then app.last_error="init: "..safeString(err);return false,app.last_error end;return app.ready==true
end
function M.start()
    if app.thread_started then return true end
    if type(context.createThread)~="function" or type(context.wait)~="function" then return false,"thread_context_missing" end
    app.thread_started=true;app.shutting_down=false
    context.createThread(function() while not app.shutting_down do context.wait(50);if app.ready then local ok,err=pcall(processSnapshotTimer);if not ok then app.last_error="snapshot timer: "..safeString(err) end;local mok,merr=pcall(processManualExternalScanTimer);if not mok then app.last_error="manual storage scan timer: "..safeString(merr) end end end;app.thread_started=false end)
    return true
end
function M.shutdown() app.shutting_down=true;if app.snapshot and app.snapshot.packet_count>0 then pcall(commitStorageSnapshot,app.snapshot) end;if app.settings then pcall(saveSettings) end;if app.database then pcall(saveDatabaseAtomic) end;if app.category_map then pcall(saveCategoryMap) end;return true end
function M.resetSession(reason)
    if app.snapshot then pcall(cancelStorageSnapshot,reason or "reconnect") end
    app.snapshot=nil;app.player_inventory_visible=false;app.active_view=nil;app.character_tab=nil;app.player_scan_active=false;app.external_candidate=nil;app.external_recent_groups={};app.external_ui_visible=false;app.external_kind_hint=nil;app.external_visible_ms=0;app.external_last_payload=nil;app.last_routed_event_key=nil;app.last_routed_event_ms=0
    if app.manual_scan then app.manual_scan.requested=false;app.manual_scan.dialog_open=false;app.manual_scan.snapshot=nil;app.manual_scan.error=nil;app.manual_scan.name_initialized=false end
    app.session_id=tostring(os.time())..":"..tostring(math.random(100000,999999));return true
end
function M.captureLegacyCef(eventName,payload)
    if not app.ready then local ok=M.init(context);if not ok then return false end end
    if type(eventName)~="string" or type(payload)~="table" then return false end
    local ok,err=pcall(routeArizonaEventOnce,eventName,payload);if not ok then app.last_error="legacy CEF fallback: "..safeString(err);return false end;return true
end
function M.markExternalVisible(kindHint)return markExternalUiVisible(kindHint)end
function M.markExternalClosed(reason)return markExternalUiClosed(reason)end
function M.requestExternalScan(kindHint)return requestManualExternalScan(kindHint)end
function M.getCaptureState()return app.manual_scan end
function M.saveManualExternalScan(kind,name)return saveManualExternalScan(kind,name)end
function M.cancelManualExternalScan()app.manual_scan.requested=false;app.manual_scan.dialog_open=false;app.manual_scan.snapshot=nil;app.manual_scan.error=nil;app.manual_scan.name_initialized=false;updateStorageScanCefButton("ready");return true end
function M.classifyItem(item)local ok,category=pcall(resolveCategory,item);if ok and category and VALID_CATEGORIES[category] then return category end;return CATEGORY.OTHER end
function M.rememberItemName(itemId,utf8Name)
    if not app.ready then local ok=M.init(context);if not ok then return false end end
    local itemKey,name=safeString(itemId),trim(utf8Name);if itemKey=="" or name=="" or name=="Unknown item" or name:match("^Item #%d+$") then return false end
    app.item_names=type(app.item_names)=="table" and app.item_names or {};if app.item_names[itemKey]==name then return true end
    app.item_names[itemKey]=name;atomicWriteJson(app.item_names_path,app.item_names_backup_path,app.item_names);local changed=false
    if app.database and type(app.database.storages)=="table" then for _,storage in pairs(app.database.storages) do if type(storage)=="table" and type(storage.items)=="table" then for _,item in pairs(storage.items) do if type(item)=="table" and safeString(item.item_id)==itemKey then local oldName=safeString(item.name);if oldName=="Unknown item" or oldName:match("^Item #%d+$") then item.name=name;item.category=resolveCategory(item);changed=true end end end end end end
    if changed then saveDatabaseAtomic();invalidateSearchIndex() end;return true
end
function M.getState()return app end
function M.getVisibleRows(query,filters)return getVisibleRows(query,filters)end
function M.updateSettings(patch)if type(patch)~="table" then return false end;app.settings=mergeDefaults(patch,app.settings or DEFAULT_SETTINGS);return saveSettings()end
function M.addHouse(n)return addHouseNumber(n)end
function M.editHouse(a,b)return editHouseNumber(a,b)end
function M.deleteHouse(n,h)return deleteHouse(n,h)end
function M.addWarehouse(n)return addWarehouseNumber(n)end
function M.editWarehouse(a,b)return editWarehouseNumber(a,b)end
function M.deleteWarehouse(n,h)return deleteWarehouse(n,h)end
function M.renameVehicle(k,n)return setVehicleManualName(k,n)end
function M.setVehicleIdentity(k,v)return setVehicleManualIdentity(k,v)end
function M.forgetVehicle(k,h)return forgetVehicle(k,h)end
function M.setCategoryOverride(i,c)return addCategoryOverride(i,c)end
function M.removeStorage(k)return removeStorage(k)end
function M.clearPendingBinding()app.settings.pending_binding=nil;return saveSettings()end
function M.clearDebugLog()os.remove(app.debug_path);app.debug_event_count=0;return true end
M.KIND=STORAGE_KIND;M.CATEGORY=CATEGORY;M.STORAGE_CAPTURE_KIND_OPTIONS=STORAGE_CAPTURE_KIND_OPTIONS;M.STORAGE_FILTERS=STORAGE_FILTERS;M.CATEGORY_FILTERS=CATEGORY_FILTERS;M.CATEGORY_LABELS=CATEGORY_LABELS;M.has_arizona_events=acef_ok==true
M._bridge={safeString=safeString,trim=trim,normalizeSearchText=normalizeSearchText,deepCopy=deepCopy,normalizeCount=normalizeCount,snapshotToItems=snapshotToItems,getIndexedItems=getIndexedItems,invalidateSearchIndex=invalidateSearchIndex,invalidateVisibleRows=invalidateVisibleRows,getOptionLabel=getOptionLabel,getCategoryLabel=getCategoryLabel,formatLastScan=formatLastScan,getSpecificStorageOptions=getSpecificStorageOptions,isSpecificStorageStillValid=isSpecificStorageStillValid,buildCatalog=buildCatalog,formatStorageLocation=formatStorageLocation,getManualScanSuggestedName=getManualScanSuggestedName,getSortedVehicleKeys=getSortedVehicleKeys,saveSettings=saveSettings,saveDatabaseAtomic=saveDatabaseAtomic,addHouseNumber=addHouseNumber,editHouseNumber=editHouseNumber,removeHouseNumber=removeHouseNumber,addWarehouseNumber=addWarehouseNumber,editWarehouseNumber=editWarehouseNumber,removeWarehouseNumber=removeWarehouseNumber,setPendingBinding=setPendingBinding,setVehicleManualName=setVehicleManualName,setVehicleManualIdentity=setVehicleManualIdentity,getVehicleLabel=getVehicleLabel,addCategoryOverride=addCategoryOverride,deleteHouse=deleteHouse,deleteWarehouse=deleteWarehouse,forgetVehicle=forgetVehicle}
return M
