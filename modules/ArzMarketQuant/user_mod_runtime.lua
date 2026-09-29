local M = { api_version = 1, module_version = 2 }

local host = {}
local registry = {}
local order = {}
local modsRoot = nil
local lfs = nil
local lastTickMs = nil

local REQUIRED_METHODS = {
    "init",
    "tick",
    "shutdown",
    "getState",
    "handleAction"
}

local OPTIONAL_EVENTS = {
    onServerMessage = true,
    onShowDialog = true,
    onCreate3DText = true,
    onRemove3DText = true,
    onNetworkPacket = true,
    onSendDialogResponse = true
}

local function nowMs()
    if type(host.nowMs) == "function" then
        local ok, value = pcall(host.nowMs)
        if ok and tonumber(value) then return tonumber(value) end
    end
    if type(getGameTimer) == "function" then
        local ok, value = pcall(getGameTimer)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return math.floor(os.clock() * 1000)
end

local function logRaw(level, message)
    local text = "[ArzMarket][UserModRuntime][" .. tostring(level or "INFO") .. "] " .. tostring(message or "")
    print(text)
end

local function deepCopy(value, depth, seen)
    local valueType = type(value)
    if valueType ~= "table" then
        if valueType == "nil" or valueType == "string" or valueType == "number" or valueType == "boolean" then return value end
        return nil
    end
    depth = tonumber(depth) or 0
    if depth > 24 then return nil end
    seen = seen or {}
    if seen[value] then return nil end
    seen[value] = true
    local out = {}
    for key, item in pairs(value) do
        local copiedKey = type(key) == "table" and nil or key
        if copiedKey ~= nil then out[copiedKey] = deepCopy(item, depth + 1, seen) end
    end
    seen[value] = nil
    return out
end

local function decodeJsonValue(raw)
    if type(raw) ~= "string" or raw == "" then return nil, "empty_json" end
    if type(host.decodeJsonSafe) == "function" then
        local ok, value, err = pcall(host.decodeJsonSafe, raw)
        if not ok then return nil, tostring(value) end
        if value == nil then return nil, tostring(err or "invalid_json") end
        return value
    end
    if type(decodeJson) == "function" then
        local ok, value = pcall(decodeJson, raw)
        if ok then return value end
        return nil, tostring(value)
    end
    return nil, "json_decoder_unavailable"
end

local function encodeJsonValue(value)
    if type(host.encodeJsonSafe) == "function" then
        local ok, encoded, err = pcall(host.encodeJsonSafe, value)
        if not ok then return nil, tostring(encoded) end
        if type(encoded) ~= "string" then return nil, tostring(err or "json_encode_failed") end
        return encoded
    end
    if type(encodeJson) == "function" then
        local ok, encoded = pcall(encodeJson, value)
        if ok and type(encoded) == "string" then return encoded end
        return nil, tostring(encoded or "json_encode_failed")
    end
    return nil, "json_encoder_unavailable"
end

local function readFile(path, binary)
    local file, err = io.open(path, binary and "rb" or "r")
    if not file then return nil, tostring(err or "open_failed") end
    local data = file:read("*a")
    file:close()
    if data == nil then return nil, "read_failed" end
    return data
end

local function writeFileAtomic(path, data)
    if type(path) ~= "string" or path == "" or type(data) ~= "string" then
        return false, "invalid_write_arguments"
    end
    local tempPath = path .. ".tmp"
    local file, err = io.open(tempPath, "wb")
    if not file then return false, tostring(err or "open_failed") end
    local okWrite, writeErr = pcall(function()
        file:write(data)
        file:flush()
    end)
    file:close()
    if not okWrite then
        pcall(os.remove, tempPath)
        return false, tostring(writeErr)
    end
    pcall(os.remove, path)
    local okRename, renameErr = os.rename(tempPath, path)
    if not okRename then
        pcall(os.remove, tempPath)
        return false, tostring(renameErr or "rename_failed")
    end
    return true
end

local function isDirectory(path)
    if type(lfs) == "table" and type(lfs.attributes) == "function" then
        local ok, mode = pcall(lfs.attributes, path, "mode")
        return ok and mode == "directory"
    end
    if type(host.doesDirectoryExist) == "function" then
        local ok, value = pcall(host.doesDirectoryExist, path)
        return ok and value == true
    end
    return false
end

local function fileExists(path)
    if type(host.doesFileExist) == "function" then
        local ok, value = pcall(host.doesFileExist, path)
        if ok then return value == true end
    end
    local file = io.open(path, "rb")
    if file then file:close(); return true end
    return false
end

local function createDirectory(path)
    if isDirectory(path) then return true end
    if type(host.createDirectory) == "function" then
        local ok = pcall(host.createDirectory, path)
        if ok and isDirectory(path) then return true end
    end
    if type(lfs) == "table" and type(lfs.mkdir) == "function" then
        local ok = pcall(lfs.mkdir, path)
        if ok and isDirectory(path) then return true end
    end
    return isDirectory(path)
end

local function joinPath(root, rel)
    if rel == nil or rel == "" then return root end
    return tostring(root) .. "\\" .. tostring(rel):gsub("/", "\\")
end

local function validModuleId(value)
    local id = tostring(value or "")
    if id == "" or #id > 96 then return nil end
    if id:find("..", 1, true) or id:find("/", 1, true) or id:find("\\", 1, true) or id:find(":", 1, true) then return nil end
    if not id:match("^[a-z0-9_.%-]+$") then return nil end
    return id
end

local function safeRelativePath(value, requiredExtension)
    local path = tostring(value or "")
    if path == "" or #path > 240 then return nil end
    if path:find("%z") or path:find(":", 1, true) then return nil end
    path = path:gsub("\\", "/")
    if path:sub(1, 1) == "/" or path:find("//", 1, true) then return nil end
    if not path:match("^[%w%._%-%/]+$") then return nil end
    for segment in path:gmatch("[^/]+") do
        if segment == "." or segment == ".." or segment == "" then return nil end
    end
    if path:find("..", 1, true) then return nil end
    if requiredExtension and path:sub(-#requiredExtension):lower() ~= requiredExtension:lower() then return nil end
    return path
end

local function parentRelativePath(rel)
    local parent = tostring(rel or ""):match("^(.*)/[^/]+$")
    return parent or ""
end

local function ensureRelativeDirectories(root, rel)
    local current = root
    local parent = parentRelativePath(rel)
    if parent == "" then return createDirectory(root) end
    if not createDirectory(root) then return false end
    for segment in parent:gmatch("[^/]+") do
        current = current .. "\\" .. segment
        if not createDirectory(current) then return false end
    end
    return true
end

local function readJsonPath(path, defaults)
    if not fileExists(path) then return deepCopy(defaults) end
    local raw, readErr = readFile(path, false)
    if raw == nil then return deepCopy(defaults), readErr end
    local value, decodeErr = decodeJsonValue(raw)
    if type(value) ~= "table" then return deepCopy(defaults), decodeErr or "invalid_json" end
    return value
end

local function writeJsonPath(path, value)
    local encoded, encodeErr = encodeJsonValue(value)
    if type(encoded) ~= "string" then return false, encodeErr or "json_encode_failed" end
    return writeFileAtomic(path, encoded)
end

local function moduleLog(record, level, message)
    local prefix = record and record.id or "unknown"
    logRaw(level, "[" .. tostring(prefix) .. "] " .. tostring(message or ""))
end

local function runtimeStatePath(record)
    return record.data_root .. "\\runtime.json"
end

local function readEnabledOverride(record)
    if not isDirectory(record.data_root) then return nil end
    local state = readJsonPath(runtimeStatePath(record), nil)
    if type(state) == "table" and type(state.enabled) == "boolean" then return state.enabled end
    return nil
end

local function persistEnabled(record, enabled)
    if not createDirectory(record.data_root) then return false, "data_directory_failed" end
    local path = runtimeStatePath(record)
    local state = readJsonPath(path, {})
    if type(state) ~= "table" then state = {} end
    state.enabled = enabled == true
    return writeJsonPath(path, state)
end

local function recordIsCurrent(record, generation)
    return record ~= nil
        and registry[record.id] == record
        and tonumber(record.generation) == tonumber(generation)
        and record.enabled == true
        and record.status ~= "disabled"
        and record.status ~= "shutdown"
end

local function protectedHostCall(record, generation, fn, ...)
    if not recordIsCurrent(record, generation) then return false, "stale_generation" end
    if type(fn) ~= "function" then return false, "service_unavailable" end
    local ok, a, b, c, d, e = pcall(fn, ...)
    if not ok then return false, tostring(a) end
    return a, b, c, d, e
end

local function makeService(record, generation, source)
    local out = {}
    if type(source) ~= "table" then return out end
    for name, fn in pairs(source) do
        if type(fn) == "function" then
            out[name] = function(...)
                return protectedHostCall(record, generation, fn, ...)
            end
        end
    end
    return out
end

local function makeModuleContext(record)
    local generation = record.generation
    local ctx = {
        api_version = 1,
        mod_id = record.id,
        mod_root = record.root,
        data_root = record.data_root
    }

    ctx.host = makeService(record, generation, host.host)
    ctx.game = makeService(record, generation, host.game)
    ctx.lavka = makeService(record, generation, host.lavka)
    ctx.trade = makeService(record, generation, host.trade)
    ctx.ads = makeService(record, generation, host.ads)
    ctx.telegram = makeService(record, generation, host.telegram)

    local function dataPath(relativePath)
        local rel = safeRelativePath(relativePath, ".json")
        if not rel then return nil, "invalid_json_path" end
        return joinPath(record.data_root, rel), rel
    end

    ctx.data = {}
    ctx.data.readJson = function(relativePath, defaults)
        if not recordIsCurrent(record, generation) then return nil, "stale_generation" end
        local path = dataPath(relativePath)
        if not path then return nil, "invalid_json_path" end
        local value, err = readJsonPath(path, defaults)
        return deepCopy(value), err
    end
    ctx.data.writeJson = function(relativePath, value)
        if not recordIsCurrent(record, generation) then return false, "stale_generation" end
        local path, rel = dataPath(relativePath)
        if not path then return false, "invalid_json_path" end
        if not ensureRelativeDirectories(record.data_root, rel) then return false, "data_directory_failed" end
        return writeJsonPath(path, value)
    end
    ctx.readJson = ctx.data.readJson
    ctx.writeJson = ctx.data.writeJson

    ctx.logger = {}
    local function writeLog(level, message)
        if not recordIsCurrent(record, generation) then return false, "stale_generation" end
        moduleLog(record, level, message)
        return true
    end
    ctx.logger.info = function(message) return writeLog("INFO", message) end
    ctx.logger.warn = function(message) return writeLog("WARN", message) end
    ctx.logger.error = function(message) return writeLog("ERROR", message) end
    ctx.log = function(message) return writeLog("INFO", message) end
    ctx.isCurrentGeneration = function() return recordIsCurrent(record, generation) end

    return ctx
end

local function validateInstance(record, instance)
    if type(instance) ~= "table" then return false, "entry_returned_" .. type(instance) end
    if tonumber(instance.api_version) ~= 1 then return false, "unsupported_module_api_version" end
    for _, name in ipairs(REQUIRED_METHODS) do
        if type(instance[name]) ~= "function" then return false, "missing_method:" .. name end
    end
    return true
end

local function shutdownRecord(record, reason)
    local instance = record and record.instance or nil
    if type(instance) == "table" and type(instance.shutdown) == "function" then
        local ok, err = pcall(instance.shutdown, tostring(reason or "shutdown"))
        if not ok then moduleLog(record, "ERROR", "shutdown failed: " .. tostring(err)) end
    end
    if record then record.instance = nil end
end

local function invalidateRecord(record)
    if record then record.generation = (tonumber(record.generation) or 0) + 1 end
end

local function faultRecord(record, stage, err)
    local detail = tostring(err or "unknown_error")
    if not detail:find("stack traceback", 1, true) and debug and type(debug.traceback) == "function" then
        detail = debug.traceback(detail, 2)
    end
    local errorText = tostring(stage or "runtime") .. ": " .. detail
    shutdownRecord(record, "runtime_error")
    invalidateRecord(record)
    record.status = "error"
    record.last_error = errorText
    moduleLog(record, "ERROR", errorText)
    return false, errorText
end

local function loadRecord(record)
    if not record or record.enabled ~= true then
        if record then record.status = "disabled" end
        return true
    end
    local chunk, loadErr = loadfile(record.entry_path)
    if not chunk then return faultRecord(record, "loadfile", loadErr) end
    local okChunk, instance = pcall(chunk)
    if not okChunk then return faultRecord(record, "entry", instance) end
    local valid, validationErr = validateInstance(record, instance)
    if not valid then return faultRecord(record, "contract", validationErr) end

    record.status = "initializing"
    record.last_error = nil
    record.instance = instance
    record.context = makeModuleContext(record)
    local okInit, initResult = pcall(instance.init, record.context)
    if not okInit or initResult == false then
        return faultRecord(record, "init", okInit and "returned_false" or initResult)
    end
    record.status = "loaded"
    record.last_error = nil
    moduleLog(record, "INFO", "loaded version " .. tostring(record.version))
    return true
end

local function manifestRecord(folderName)
    local id = validModuleId(folderName)
    if not id then return nil end
    local root = joinPath(modsRoot, id)
    local manifestPath = root .. "\\manifest.json"
    if not fileExists(manifestPath) then return nil end

    local base = {
        id = id,
        name = id,
        version = "?",
        author = "",
        description = "",
        root = root,
        data_root = root .. "\\data",
        manifest_path = manifestPath,
        enabled = false,
        has_ui = false,
        ui_rel = nil,
        ui_root_rel = nil,
        entry_rel = nil,
        entry_path = nil,
        status = "error",
        last_error = nil,
        instance = nil,
        context = nil,
        generation = 1,
        manifest_valid = false
    }

    local raw, readErr = readFile(manifestPath, false)
    if raw == nil then base.last_error = "manifest_read_failed:" .. tostring(readErr); return base end
    local manifest, decodeErr = decodeJsonValue(raw)
    if type(manifest) ~= "table" then base.last_error = "manifest_invalid_json:" .. tostring(decodeErr); return base end

    base.name = tostring(manifest.name or id):sub(1, 160)
    base.version = tostring(manifest.version or "?"):sub(1, 64)
    base.author = tostring(manifest.author or ""):sub(1, 160)
    base.description = tostring(manifest.description or ""):sub(1, 1200)
    base.manifest = manifest

    if tonumber(manifest.manifest_version) ~= 1 then base.last_error = "unsupported_manifest_version"; return base end
    if tonumber(manifest.api_version) ~= 1 then base.last_error = "unsupported_api_version"; return base end
    local manifestId = validModuleId(manifest.id)
    if not manifestId or manifestId ~= id then base.last_error = "manifest_id_mismatch"; return base end
    if base.name == "" or base.version == "" then base.last_error = "manifest_metadata_invalid"; return base end

    local entryRel = safeRelativePath(manifest.entry, ".lua")
    if not entryRel then base.last_error = "manifest_entry_invalid"; return base end
    local entryPath = joinPath(root, entryRel)
    if not fileExists(entryPath) then base.last_error = "entry_missing"; return base end
    base.entry_rel = entryRel
    base.entry_path = entryPath

    local uiValue = tostring(manifest.ui or "")
    if uiValue ~= "" then
        local uiRel = safeRelativePath(uiValue, ".html")
        if not uiRel then base.last_error = "manifest_ui_invalid"; return base end
        local uiPath = joinPath(root, uiRel)
        if not fileExists(uiPath) then base.last_error = "ui_missing"; return base end
        base.ui_rel = uiRel
        base.ui_root_rel = parentRelativePath(uiRel)
        base.has_ui = true
    end

    local override = readEnabledOverride(base)
    if type(override) == "boolean" then
        base.enabled = override
    else
        base.enabled = manifest.enabled ~= false
    end
    base.manifest_valid = true
    base.status = base.enabled and "discovered" or "disabled"
    base.last_error = nil
    return base
end

local function scanDirectoryNames()
    local names = {}
    if type(lfs) ~= "table" or type(lfs.dir) ~= "function" then return names, "lfs_unavailable" end
    local ok, err = pcall(function()
        for name in lfs.dir(modsRoot) do
            if name ~= "." and name ~= ".." and validModuleId(name) then
                local full = joinPath(modsRoot, name)
                if isDirectory(full) then names[#names + 1] = name end
            end
        end
    end)
    if not ok then return {}, tostring(err) end
    table.sort(names)
    return names
end

function M.rescan()
    for _, id in ipairs(order) do
        local old = registry[id]
        if old then
            shutdownRecord(old, "rescan")
            invalidateRecord(old)
        end
    end
    registry = {}
    order = {}

    if not createDirectory(modsRoot) then return false, "mods_root_unavailable" end
    local names, scanErr = scanDirectoryNames()
    if scanErr then logRaw("ERROR", "scan failed: " .. tostring(scanErr)); return false, scanErr end

    for _, folderName in ipairs(names) do
        local record = manifestRecord(folderName)
        if record then
            registry[record.id] = record
            order[#order + 1] = record.id
            if record.last_error then
                moduleLog(record, "ERROR", record.last_error)
            elseif record.enabled then
                loadRecord(record)
            end
        end
    end
    return true
end

local function publicRecord(record)
    return {
        id = tostring(record.id or ""),
        name = tostring(record.name or record.id or ""),
        version = tostring(record.version or ""),
        author = tostring(record.author or ""),
        description = tostring(record.description or ""),
        enabled = record.enabled == true,
        has_ui = record.has_ui == true,
        status = tostring(record.status or "unknown"),
        last_error = record.last_error and tostring(record.last_error) or nil,
        ui_path = record.has_ui and tostring(record.ui_rel or "") or nil,
        toggle_supported = record.manifest_valid == true
    }
end

function M.getPublicList()
    local out = {}
    for _, id in ipairs(order) do
        local record = registry[id]
        if record then out[#out + 1] = publicRecord(record) end
    end
    table.sort(out, function(a, b)
        local an, bn = string.lower(a.name), string.lower(b.name)
        if an == bn then return a.id < b.id end
        return an < bn
    end)
    return out
end

function M.getPublic(id)
    id = validModuleId(id)
    local record = id and registry[id] or nil
    return record and publicRecord(record) or nil
end

function M.getState(id)
    id = validModuleId(id)
    local record = id and registry[id] or nil
    if not record then return false, "module_not_found" end
    if record.enabled ~= true then return false, "module_disabled" end
    if record.status ~= "loaded" or type(record.instance) ~= "table" then
        return false, record.last_error or "module_not_loaded"
    end
    local ok, value = pcall(record.instance.getState)
    if not ok then return faultRecord(record, "getState", value) end
    return true, deepCopy(type(value) == "table" and value or { value = value }), publicRecord(record)
end

function M.handleAction(id, action, payload)
    id = validModuleId(id)
    local record = id and registry[id] or nil
    if not record then return false, "module_not_found" end
    if record.enabled ~= true then return false, "module_disabled" end
    if record.status ~= "loaded" or type(record.instance) ~= "table" then
        return false, record.last_error or "module_not_loaded"
    end
    action = tostring(action or "")
    if action == "" or #action > 128 or not action:match("^[%w%._%-]+$") then return false, "invalid_action" end
    local safePayload = type(payload) == "table" and deepCopy(payload) or {}
    local ok, a, b, c = pcall(record.instance.handleAction, action, safePayload)
    if not ok then return faultRecord(record, "handleAction", a) end
    return a, deepCopy(b), deepCopy(c)
end

function M.setEnabled(id, enabled)
    id = validModuleId(id)
    local record = id and registry[id] or nil
    if not record then return false, "module_not_found" end
    if record.manifest_valid ~= true then return false, record.last_error or "manifest_invalid" end
    enabled = enabled == true
    if record.enabled == enabled then return true, publicRecord(record) end

    local persisted, persistErr = persistEnabled(record, enabled)
    if not persisted then return false, persistErr or "persist_failed" end

    if not enabled then
        shutdownRecord(record, "disable")
        invalidateRecord(record)
        record.enabled = false
        record.status = "disabled"
        record.last_error = nil
        return true, publicRecord(record)
    end

    record.enabled = true
    invalidateRecord(record)
    record.status = "discovered"
    record.last_error = nil
    local ok, err = loadRecord(record)
    if not ok then return false, err end
    return true, publicRecord(record)
end

function M.reload(id)
    id = validModuleId(id)
    local old = id and registry[id] or nil
    if not old then return false, "module_not_found" end

    shutdownRecord(old, "reload")
    invalidateRecord(old)

    local refreshed = manifestRecord(id)
    if not refreshed then
        old.status = "error"
        old.last_error = "manifest_missing"
        registry[id] = old
        return false, old.last_error
    end
    refreshed.generation = old.generation
    registry[id] = refreshed

    if refreshed.last_error then return false, refreshed.last_error end
    if refreshed.enabled then
        local ok, err = loadRecord(refreshed)
        if not ok then return false, err end
    end
    return true, publicRecord(refreshed)
end

function M.resolveAsset(id, relativePath)
    id = validModuleId(id)
    local record = id and registry[id] or nil
    if not record then return false, "module_not_found" end
    if record.enabled ~= true or record.status ~= "loaded" then return false, "module_not_loaded" end
    if not record.has_ui or not record.ui_rel then return false, "module_ui_unavailable" end
    local rel = safeRelativePath(relativePath)
    if not rel then return false, "invalid_asset_path" end

    local uiRoot = tostring(record.ui_root_rel or "")
    if uiRoot ~= "" then
        if rel ~= record.ui_rel and rel:sub(1, #uiRoot + 1) ~= uiRoot .. "/" then
            return false, "asset_outside_ui_root"
        end
    end

    local fullPath = joinPath(record.root, rel)
    if not fileExists(fullPath) then return false, "asset_not_found" end
    return true, fullPath, rel
end

function M.dispatch(eventName, ...)
    eventName = tostring(eventName or "")
    if not OPTIONAL_EVENTS[eventName] then return false, "unknown_event" end
    for _, id in ipairs(order) do
        local record = registry[id]
        local instance = record and record.instance or nil
        local handler = type(instance) == "table" and instance[eventName] or nil
        if record and record.enabled and record.status == "loaded" and type(handler) == "function" then
            local ok, err = pcall(handler, ...)
            if not ok then faultRecord(record, eventName, err) end
        end
    end
    return true
end

function M.tick()
    local current = nowMs()
    local dt = 0
    if lastTickMs ~= nil then dt = math.max(0, math.min(1, (current - lastTickMs) / 1000)) end
    lastTickMs = current

    for _, id in ipairs(order) do
        local record = registry[id]
        local instance = record and record.instance or nil
        if record and record.enabled and record.status == "loaded" and type(instance) == "table" then
            local ok, err = pcall(instance.tick, dt)
            if not ok then faultRecord(record, "tick", err) end
        end
    end
    return true
end

function M.shutdown(reason)
    for _, id in ipairs(order) do
        local record = registry[id]
        if record then
            shutdownRecord(record, reason or "arzmarket_terminate")
            invalidateRecord(record)
            record.status = "shutdown"
        end
    end
    lastTickMs = nil
    return true
end

function M.init(context)
    host = type(context) == "table" and context or {}
    lfs = host.lfs
    local workingDirectory = type(host.getWorkingDirectory) == "function" and host.getWorkingDirectory() or getWorkingDirectory()
    modsRoot = tostring(workingDirectory) .. "\\ArzMarket\\mods"
    if not createDirectory(modsRoot) then
        logRaw("ERROR", "cannot create mods root: " .. tostring(modsRoot))
        return false
    end
    local ok, err = M.rescan()
    if not ok then return false, err end
    logRaw("INFO", "initialized, modules=" .. tostring(#order))
    return true
end

return M
