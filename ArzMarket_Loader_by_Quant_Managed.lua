require 'moonloader'

local LOADER_VERSION = '0.52'
script_name('ArzMarket Loader by Quant')
script_author('NikitaQuant')
script_version(LOADER_VERSION)

local moonloader = require 'moonloader'
local dlstatus = moonloader.download_status
local encoding = require 'encoding'
local bit = require 'bit'
encoding.default = 'CP1251'
local u8 = encoding.UTF8

local CUSTOM_MANIFEST_URL = 'https://raw.githubusercontent.com/NikitaQuant/ArzMarket-by-Quant/main/updateArzMarket.js'
local REPOSITORY_RAW_PREFIX = 'https://raw.githubusercontent.com/NikitaQuant/ArzMarket-by-Quant/main/'
local MANAGED_LOADER_URL = REPOSITORY_RAW_PREFIX .. 'ArzMarket_Loader_by_Quant_Managed.lua'
local BOOTSTRAP_LOADER_FILENAME = 'ArzMarket_Loader_by_Quant.lua'
local MANAGED_LOADER_FILENAME = 'ArzMarket_Loader_by_Quant_Managed.lua'
local TARGET_ARZMARKET_FILENAME = 'by_Quant_ArzMarket[3_57].lua'

local SCRIPT_DIR = getWorkingDirectory() .. '\\'
local CONFIG_DIR = SCRIPT_DIR .. 'config\\ArzMarket\\'
local INSTALL_VERSION_MARKER_PATH = SCRIPT_DIR .. '.arzmarket_loader_version'
local DOWNLOAD_NOTICE_MARKER_PATH = SCRIPT_DIR .. '.arzmarket_loader_downloaded'
local FIRST_BOOTSTRAP_PENDING_PATH = CONFIG_DIR .. 'first_bootstrap_pending.ini'
local FIRST_BOOTSTRAP_COMPLETED_PATH = CONFIG_DIR .. 'first_bootstrap_completed.flag'
local FIRST_BOOTSTRAP_VERIFIED_PATH = CONFIG_DIR .. 'managed_loader_verified.ini'
local FIRST_BOOTSTRAP_FAILED_PATH = CONFIG_DIR .. 'managed_loader_failed.ini'
local OFFLINE_FLAG_PATH = CONFIG_DIR .. 'offline_mode.flag'
local COMPONENT_STATE_PATH = SCRIPT_DIR .. 'ArzMarket\\component_state.json'
local ARZMARKET_INI_PATH = CONFIG_DIR .. 'ArzMarket.ini'
local LOG_PREFIX = '[ArzMarket Loader by Quant] '

local CURRENT_FILENAME = tostring(thisScript().filename or '')
local IS_MANAGED_LOADER = CURRENT_FILENAME == MANAGED_LOADER_FILENAME

local myVersion = nil
local myUpdateUrl = nil

local function log(text)
    print(LOG_PREFIX .. tostring(text))
end

local function chatMessage(text, color)
    log(text)
    if isSampAvailable() then
        pcall(sampAddChatMessage, u8:decode(tostring(text)), color or 0xFF70C8FF)
    end
end

local function waitForSamp()
    while not isSampLoaded() do
        wait(100)
    end
    while not isSampAvailable() do
        wait(100)
    end
end

local function fileSize(path)
    local file = io.open(path, 'rb')
    if not file then return 0 end
    local size = file:seek('end') or 0
    file:close()
    return tonumber(size) or 0
end

local function readFile(path)
    local file = io.open(path, 'rb')
    if not file then return nil end
    local data = file:read('*a')
    file:close()
    return data
end

local function removeFile(path)
    if path and doesFileExist(path) then
        pcall(os.remove, path)
    end
end

local function ensureConfigDirectory()
    local configRoot = SCRIPT_DIR .. 'config'
    local arzRoot = SCRIPT_DIR .. 'config\\ArzMarket'
    if not doesDirectoryExist(configRoot) then pcall(createDirectory, configRoot) end
    if not doesDirectoryExist(arzRoot) then pcall(createDirectory, arzRoot) end
    return doesDirectoryExist(arzRoot)
end

local function atomicWrite(path, content)
    local parent = tostring(path or ''):match('^(.*)[\\/][^\\/]+$')
    if parent and parent ~= '' and not doesDirectoryExist(parent) then
        pcall(createDirectory, parent)
    end
    local tempPath = tostring(path) .. '.tmp'
    removeFile(tempPath)
    local file = io.open(tempPath, 'wb')
    if not file then return false end
    local ok = pcall(function()
        file:write(tostring(content or ''))
        file:flush()
    end)
    pcall(file.close, file)
    if not ok then
        removeFile(tempPath)
        return false
    end
    removeFile(path)
    local renamed = os.rename(tempPath, path)
    if not renamed then
        removeFile(tempPath)
        return false
    end
    return true
end

local function readKeyValue(path)
    local result = {}
    local raw = readFile(path)
    if type(raw) ~= 'string' then return result end
    for line in (raw .. '\n'):gmatch('([^\n]*)\n') do
        line = tostring(line or ''):gsub('\r$', '')
        local key, value = line:match('^([%w_]+)=(.*)$')
        if key then result[key] = value end
    end
    return result
end

local function writeInstallVersionMarker(version)
    return atomicWrite(INSTALL_VERSION_MARKER_PATH, tostring(version or ''))
end

local function writeDownloadNoticeMarker(version)
    return atomicWrite(DOWNLOAD_NOTICE_MARKER_PATH, tostring(version or ''))
end

local function addCacheBuster(url)
    local separator = tostring(url):find('?', 1, true) and '&' or '?'
    return tostring(url)
        .. separator
        .. '_arzmarket_loader='
        .. tostring(os.time())
        .. '_'
        .. tostring(math.random(100000, 999999))
end

local function downloadAndWait(url, destination, timeoutSeconds)
    timeoutSeconds = timeoutSeconds or 20
    removeFile(destination)

    local finished = false
    local success = false
    local startedAt = os.time()

    local ok, errorText = pcall(function()
        downloadUrlToFile(addCacheBuster(url), destination, function(_, status)
            if status == dlstatus.STATUSEX_ENDDOWNLOAD then
                success = doesFileExist(destination) and fileSize(destination) > 0
                finished = true
            elseif tonumber(status) and tonumber(status) < 0 then
                finished = true
            end
        end)
    end)

    if not ok then
        log('downloadUrlToFile error: ' .. tostring(errorText))
        removeFile(destination)
        return false
    end

    while not finished and os.difftime(os.time(), startedAt) < timeoutSeconds do
        wait(50)
    end

    if not success then
        removeFile(destination)
        return false
    end
    return true
end

local CRC32_TABLE = nil
local function getCrc32Table()
    if CRC32_TABLE then return CRC32_TABLE end
    local result = {}
    for index = 0, 255 do
        local value = index
        for _ = 1, 8 do
            if bit.band(value, 1) ~= 0 then
                value = bit.bxor(bit.rshift(value, 1), 0xEDB88320)
            else
                value = bit.rshift(value, 1)
            end
        end
        result[index] = value
    end
    CRC32_TABLE = result
    return result
end

local function fileCrc32(path)
    local file = io.open(path, 'rb')
    if not file then return nil end
    local tableCrc = getCrc32Table()
    local crc = 0xFFFFFFFF
    while true do
        local chunk = file:read(65536)
        if not chunk or #chunk == 0 then break end
        for index = 1, #chunk do
            local byte = chunk:byte(index)
            local tableIndex = bit.band(bit.bxor(crc, byte), 0xFF)
            crc = bit.bxor(bit.rshift(crc, 8), tableCrc[tableIndex])
        end
    end
    file:close()
    crc = bit.bxor(crc, 0xFFFFFFFF)
    if type(bit.tohex) == 'function' then
        return tostring(bit.tohex(crc, 8)):upper()
    end
    if crc < 0 then crc = crc + 4294967296 end
    return string.format('%08X', crc)
end

local function validateLua(path)
    local chunk, errorText = loadfile(path)
    if not chunk then return false, errorText end
    return true
end

local function validateArzMarketFile(path, manifest)
    if not doesFileExist(path) then return false, 'file_missing' end
    if fileSize(path) <= 0 then return false, 'file_empty' end

    local expectedSize = tonumber(manifest and manifest.size)
    if expectedSize and expectedSize > 0 and fileSize(path) ~= expectedSize then
        return false, 'size_mismatch:' .. tostring(fileSize(path)) .. '!=' .. tostring(expectedSize)
    end

    local expectedCrc = tostring(manifest and manifest.crc32 or ''):upper()
    if expectedCrc ~= '' then
        local actualCrc = fileCrc32(path)
        if not actualCrc or actualCrc ~= expectedCrc then
            return false, 'crc32_mismatch:' .. tostring(actualCrc) .. '!=' .. expectedCrc
        end
    end

    local valid, validationError = validateLua(path)
    if not valid then return false, 'lua_invalid:' .. tostring(validationError) end
    return true
end

local function isAllowedRepositoryUrl(url)
    return type(url) == 'string' and url:find(REPOSITORY_RAW_PREFIX, 1, true) == 1
end

local function decodeManifest(path)
    local raw = readFile(path)
    if not raw or raw == '' then return nil end
    local ok, data = pcall(decodeJson, raw)
    if not ok or type(data) ~= 'table' then return nil end
    if data.latest == nil then return nil end
    if type(data.updateurl) ~= 'string' or data.updateurl == '' then return nil end
    if not isAllowedRepositoryUrl(data.updateurl) then
        log('manifest rejected: update URL is outside the project GitHub repository')
        return nil
    end

    return {
        latest = tostring(data.latest),
        updateurl = data.updateurl,
        size = tonumber(data.size),
        crc32 = tostring(data.crc32 or ''):upper()
    }
end

local function downloadManifest(url, tempFileName, label)
    local tempPath = SCRIPT_DIR .. tempFileName
    for attempt = 1, 3 do
        log(label .. ': download manifest attempt ' .. tostring(attempt))
        if downloadAndWait(url, tempPath, 20) then
            local manifest = decodeManifest(tempPath)
            removeFile(tempPath)
            if manifest then return manifest end
            log(label .. ': manifest JSON is invalid')
        else
            log(label .. ': manifest download failed')
        end
        wait(500)
    end
    removeFile(tempPath)
    return nil
end

local function parseVersionParts(version)
    local parts = {}
    for value in tostring(version or ''):gmatch('%d+') do
        parts[#parts + 1] = tonumber(value) or 0
    end
    return parts
end

local function compareVersionStrings(left, right)
    local a = parseVersionParts(left)
    local b = parseVersionParts(right)
    if #a == 0 or #b == 0 then return nil end
    local count = math.max(#a, #b)
    for index = 1, count do
        local av = a[index] or 0
        local bv = b[index] or 0
        if av > bv then return 1 end
        if av < bv then return -1 end
    end
    return 0
end

local function extractLoaderVersion(path)
    local raw = readFile(path)
    if type(raw) ~= 'string' then return nil end
    return raw:match("LOADER_VERSION%s*=%s*['\"]([^'\"]+)['\"]")
        or raw:match("script_version%s*%(%s*['\"]([^'\"]+)['\"]%s*%)")
end

local function validateLoaderFile(path)
    local valid, validationError = validateLua(path)
    if not valid then return false, 'lua_invalid:' .. tostring(validationError) end

    local raw = readFile(path)
    if type(raw) ~= 'string' or #raw < 8000 then
        return false, 'loader_too_small'
    end
    for _, marker in ipairs({
        'managedBootstrapVerification',
        'selfUpdateManagedLoader',
        'MANAGED_LOADER_URL',
        'FIRST_BOOTSTRAP_PENDING_PATH',
        'validateArzMarketFile'
    }) do
        if not raw:find(marker, 1, true) then
            return false, 'loader_structure_missing:' .. marker
        end
    end

    local version = extractLoaderVersion(path)
    if not version or version == '' then return false, 'loader_version_missing' end
    return true, version
end

local function basename(path)
    return tostring(path or ''):match('([^\\/]+)$') or tostring(path or '')
end

local function findLoadedScript(filename)
    for _, scriptObject in ipairs(script.list()) do
        local currentName = scriptObject.filename or basename(scriptObject.path)
        if currentName == filename then return scriptObject end
    end
    return nil
end

local function isArzMarketFilename(filename)
    if type(filename) ~= 'string' then return false end
    if filename:match('^#ArzMarket%[.+%]%.lua$') then return true end
    if filename:match('^by_Quant_ArzMarket%[.+%]%.lua$') then return true end
    return false
end

local function parseFilenameVersion(filename)
    local inside = tostring(filename or ''):match('%[([^%]]+)%]')
    if not inside then return {} end
    return parseVersionParts(inside)
end

local function compareVersionParts(left, right)
    local count = math.max(#left, #right)
    for index = 1, count do
        local a = left[index] or 0
        local b = right[index] or 0
        if a > b then return 1 end
        if a < b then return -1 end
    end
    return 0
end

local function cleanupDuplicateLoadedArzMarket()
    local loaded = {}
    for _, scriptObject in ipairs(script.list()) do
        local currentName = scriptObject.filename or basename(scriptObject.path)
        if currentName ~= thisScript().filename and isArzMarketFilename(currentName) then
            loaded[#loaded + 1] = {
                object = scriptObject,
                path = scriptObject.path,
                name = currentName,
                version = parseFilenameVersion(currentName)
            }
        end
    end
    if #loaded <= 1 then return end

    local keep = loaded[1]
    for index = 2, #loaded do
        if compareVersionParts(loaded[index].version, keep.version) > 0 then keep = loaded[index] end
    end

    log('duplicate guard: found ' .. tostring(#loaded) .. ' loaded ArzMarket scripts, keeping ' .. tostring(keep.name))
    for _, entry in ipairs(loaded) do
        if entry.object ~= keep.object then
            pcall(function() entry.object:unload() end)
        end
    end
    wait(50)
end

local function collectOtherLoadedArzMarket(keepFilename)
    local result = {}
    for _, scriptObject in ipairs(script.list()) do
        local currentName = scriptObject.filename or basename(scriptObject.path)
        if currentName ~= thisScript().filename
            and currentName ~= keepFilename
            and isArzMarketFilename(currentName) then
            result[#result + 1] = { object = scriptObject, path = scriptObject.path }
        end
    end
    return result
end

local function unloadScripts(entries)
    for _, entry in ipairs(entries) do
        pcall(function() entry.object:unload() end)
    end
end

local function restoreScripts(entries)
    for _, entry in ipairs(entries) do
        if entry.path and doesFileExist(entry.path) then pcall(script.load, entry.path) end
    end
end

local function cleanupMask(mask, keepFilename)
    local searchHandle, filename = findFirstFile(SCRIPT_DIR .. mask)
    if not searchHandle or not filename then return end
    while filename do
        if filename ~= keepFilename and isArzMarketFilename(filename) then
            removeFile(SCRIPT_DIR .. filename)
        end
        filename = findNextFile(searchHandle)
    end
    findClose(searchHandle)
end

local function cleanupOldArzMarketFiles(keepFilename)
    cleanupMask('#ArzMarket*.lua', keepFilename)
    cleanupMask('by_Quant_ArzMarket*.lua', keepFilename)
end

local function deleteStartupFile(filename)
    if type(filename) ~= 'string' or filename == '' then return true end
    local path = SCRIPT_DIR .. filename
    local currentScript = thisScript()
    local loaded = findLoadedScript(filename)
    if loaded and loaded ~= currentScript then
        pcall(function() loaded:unload() end)
        wait(100)
    end
    if doesFileExist(path) then
        local removed, removeError = os.remove(path)
        if not removed and doesFileExist(path) then
            log('startup cleanup failed for ' .. filename .. ': ' .. tostring(removeError))
            return false
        end
    end
    return true
end

local function cleanupStartupLegacyFiles()
    local files = { 'ArzMarket_Loader.lua', '#ArzMarket[3_56].lua' }
    for _, filename in ipairs(files) do
        if filename ~= thisScript().filename then deleteStartupFile(filename) end
    end
end

local function hasAnyArzMarketFile()
    local masks = { '#ArzMarket*.lua', 'by_Quant_ArzMarket*.lua' }
    for _, mask in ipairs(masks) do
        local searchHandle, filename = findFirstFile(SCRIPT_DIR .. mask)
        if searchHandle and filename then
            findClose(searchHandle)
            return true
        end
    end
    return false
end

local function isFreshInstallationBeforeDownload(targetPath)
    if doesFileExist(FIRST_BOOTSTRAP_COMPLETED_PATH) then return false end
    if doesFileExist(FIRST_BOOTSTRAP_PENDING_PATH) then return false end
    if doesFileExist(ARZMARKET_INI_PATH) then return false end
    if doesFileExist(COMPONENT_STATE_PATH) then return false end
    if targetPath and doesFileExist(targetPath) then return false end
    if hasAnyArzMarketFile() then return false end
    return true
end

local function ensureOfflineFlag()
    if not ensureConfigDirectory() then return false end
    if doesFileExist(OFFLINE_FLAG_PATH) then return true end
    return atomicWrite(OFFLINE_FLAG_PATH, '1')
end

local function beginFirstBootstrap(version)
    if not ensureConfigDirectory() then return false, 'config_directory_unavailable' end

    local existing = readKeyValue(FIRST_BOOTSTRAP_PENDING_PATH)
    if tostring(existing.session or '') ~= '' then
        if not ensureOfflineFlag() then return false, 'offline_flag_unavailable' end
        return true, tostring(existing.session)
    end

    local offlineBefore = doesFileExist(OFFLINE_FLAG_PATH) and '1' or '0'
    local session = tostring(os.time()) .. '_' .. tostring(math.random(100000, 999999))
    removeFile(FIRST_BOOTSTRAP_VERIFIED_PATH)
    removeFile(FIRST_BOOTSTRAP_FAILED_PATH)

    local content = table.concat({
        'protocol=1',
        'session=' .. session,
        'created_at=' .. tostring(os.time()),
        'offline_before=' .. offlineBefore,
        'arz_version=' .. tostring(version or ''),
        'bootstrap_loader=' .. BOOTSTRAP_LOADER_FILENAME,
        'managed_loader=' .. MANAGED_LOADER_FILENAME,
        ''
    }, '\r\n')

    if not atomicWrite(FIRST_BOOTSTRAP_PENDING_PATH, content) then
        return false, 'pending_write_failed'
    end
    if not ensureOfflineFlag() then
        removeFile(FIRST_BOOTSTRAP_PENDING_PATH)
        return false, 'offline_flag_unavailable'
    end
    log('first bootstrap isolation enabled, session=' .. session)
    return true, session
end

local function writeBootstrapVerification(path, session, success, reason, version)
    if not ensureConfigDirectory() then return false end
    local content = table.concat({
        'protocol=1',
        'session=' .. tostring(session or ''),
        'success=' .. (success and '1' or '0'),
        'loader_version=' .. tostring(LOADER_VERSION),
        'arz_version=' .. tostring(version or ''),
        'timestamp=' .. tostring(os.time()),
        'reason=' .. tostring(reason or ''):gsub('[\r\n]', ' '),
        ''
    }, '\r\n')
    return atomicWrite(path, content)
end

local function managedBootstrapVerification()
    if not IS_MANAGED_LOADER or not doesFileExist(FIRST_BOOTSTRAP_PENDING_PATH) then return false end

    local pending = readKeyValue(FIRST_BOOTSTRAP_PENDING_PATH)
    local session = tostring(pending.session or '')
    if session == '' then
        writeBootstrapVerification(FIRST_BOOTSTRAP_FAILED_PATH, '', false, 'pending_session_missing', '')
        return true
    end

    log('managed bootstrap verification started, session=' .. session)
    cleanupStartupLegacyFiles()
    cleanupDuplicateLoadedArzMarket()

    local manifest = downloadManifest(CUSTOM_MANIFEST_URL, '.arzmarket_managed_verify_manifest.json', 'MANAGED VERIFY')
    if not manifest then
        writeBootstrapVerification(FIRST_BOOTSTRAP_FAILED_PATH, session, false, 'custom_manifest_unavailable', '')
        return true
    end

    local targetPath = SCRIPT_DIR .. TARGET_ARZMARKET_FILENAME
    local valid, validationError = validateArzMarketFile(targetPath, manifest)
    if not valid then
        writeBootstrapVerification(FIRST_BOOTSTRAP_FAILED_PATH, session, false, validationError, manifest.latest)
        return true
    end

    writeInstallVersionMarker(manifest.latest)
    cleanupOldArzMarketFiles(TARGET_ARZMARKET_FILENAME)
    removeFile(FIRST_BOOTSTRAP_FAILED_PATH)
    if not writeBootstrapVerification(FIRST_BOOTSTRAP_VERIFIED_PATH, session, true, 'ok', manifest.latest) then
        writeBootstrapVerification(FIRST_BOOTSTRAP_FAILED_PATH, session, false, 'verified_write_failed', manifest.latest)
        return true
    end

    log('managed bootstrap verification passed, ArzMarket=' .. tostring(manifest.latest))
    return true
end

local function selfUpdateManagedLoader()
    if not IS_MANAGED_LOADER then return false end

    local currentPath = tostring(thisScript().path or (SCRIPT_DIR .. CURRENT_FILENAME))
    local tempPath = currentPath .. '.selfupdate.download'
    if not downloadAndWait(MANAGED_LOADER_URL, tempPath, 30) then
        log('managed self-update check skipped: GitHub unavailable')
        return false
    end

    local valid, validationErrorOrVersion = validateLoaderFile(tempPath)
    if not valid then
        log('managed self-update rejected: ' .. tostring(validationErrorOrVersion))
        removeFile(tempPath)
        return false
    end

    local remoteVersion = validationErrorOrVersion
    local comparison = compareVersionStrings(remoteVersion, LOADER_VERSION)
    if comparison == nil then
        log('managed self-update rejected: remote version invalid')
        removeFile(tempPath)
        return false
    end
    if comparison <= 0 then
        removeFile(tempPath)
        return false
    end

    local backupPath = currentPath .. '.previous'
    removeFile(backupPath)
    if doesFileExist(currentPath) then
        local movedOld, moveOldError = os.rename(currentPath, backupPath)
        if not movedOld then
            log('managed self-update could not backup current loader: ' .. tostring(moveOldError))
            removeFile(tempPath)
            return false
        end
    end

    local installed, installError = os.rename(tempPath, currentPath)
    if not installed then
        if doesFileExist(backupPath) then pcall(os.rename, backupPath, currentPath) end
        removeFile(tempPath)
        log('managed self-update install failed: ' .. tostring(installError))
        return false
    end

    log('managed loader updated: ' .. tostring(LOADER_VERSION) .. ' -> ' .. tostring(remoteVersion))
    lua_thread.create(function()
        wait(100)
        thisScript():reload()
    end)
    return true
end

local function installSelectedVersion(manifest)
    local targetFilename = TARGET_ARZMARKET_FILENAME
    local targetPath = SCRIPT_DIR .. targetFilename
    local freshInstall = isFreshInstallationBeforeDownload(targetPath)

    myVersion = manifest.latest
    myUpdateUrl = manifest.updateurl

    log('FINAL source = CUSTOM')
    log('FINAL version = ' .. tostring(myVersion))
    log('FINAL url = ' .. tostring(myUpdateUrl))
    log('FINAL filename = ' .. tostring(targetFilename))

    local validExisting, existingError = validateArzMarketFile(targetPath, manifest)
    if validExisting then
        writeInstallVersionMarker(myVersion)
        if not findLoadedScript(targetFilename) then
            if not script.load(targetPath) then
                log('existing selected script could not be loaded')
                return false
            end
        end
        local otherScripts = collectOtherLoadedArzMarket(targetFilename)
        unloadScripts(otherScripts)
        cleanupOldArzMarketFiles(targetFilename)
        log('selected script is already current and verified')
        return true
    end

    if doesFileExist(targetPath) then
        log('local ArzMarket needs replacement: ' .. tostring(existingError))
    end

    chatMessage('Загрузчик ArzMarket успешно загружен.')
    chatMessage('Начинаю скачивание ArzMarket...')

    local tempPath = targetPath .. '.download'
    if not downloadAndWait(myUpdateUrl, tempPath, 90) then
        log('selected script download failed')
        return false
    end

    local valid, validationError = validateArzMarketFile(tempPath, manifest)
    if not valid then
        log('downloaded ArzMarket validation failed: ' .. tostring(validationError))
        removeFile(tempPath)
        return false
    end

    local firstBootstrapSession = nil
    if freshInstall or doesFileExist(FIRST_BOOTSTRAP_PENDING_PATH) then
        local bootstrapOk, bootstrapResult = beginFirstBootstrap(myVersion)
        if not bootstrapOk then
            log('first bootstrap isolation failed: ' .. tostring(bootstrapResult))
            removeFile(tempPath)
            return false
        end
        firstBootstrapSession = bootstrapResult
    end

    local currentTargetScript = findLoadedScript(targetFilename)
    local otherScripts = collectOtherLoadedArzMarket(targetFilename)
    if currentTargetScript then
        pcall(function() currentTargetScript:unload() end)
        wait(50)
    end
    unloadScripts(otherScripts)
    wait(50)

    local backupPath = targetPath .. '.loader_previous'
    removeFile(backupPath)
    if doesFileExist(targetPath) then
        local backedUp, backupError = os.rename(targetPath, backupPath)
        if not backedUp then
            log('target backup failed: ' .. tostring(backupError))
            removeFile(tempPath)
            restoreScripts(otherScripts)
            return false
        end
    end

    local renamed, renameError = os.rename(tempPath, targetPath)
    if not renamed then
        log('rename failed: ' .. tostring(renameError))
        if doesFileExist(backupPath) then pcall(os.rename, backupPath, targetPath) end
        removeFile(tempPath)
        restoreScripts(otherScripts)
        return false
    end

    writeInstallVersionMarker(myVersion)
    writeDownloadNoticeMarker(myVersion)

    if not script.load(targetPath) then
        log('new script failed to load')
        removeFile(targetPath)
        if doesFileExist(backupPath) then pcall(os.rename, backupPath, targetPath) end
        restoreScripts(otherScripts)
        return false
    end

    removeFile(backupPath)
    cleanupOldArzMarketFiles(targetFilename)
    if firstBootstrapSession then
        log('first bootstrap pending, session=' .. tostring(firstBootstrapSession))
    end
    log('installed successfully')
    return true
end

function main()
    math.randomseed(os.time() + math.floor(os.clock() * 100000))

    -- Fail closed on every machine that has not completed the two-stage bootstrap yet.
    -- This is done before the first yield so ArzMarket can see the pending/offline state
    -- even when an older main Lua file is already present in moonloader.
    if not IS_MANAGED_LOADER and not doesFileExist(FIRST_BOOTSTRAP_COMPLETED_PATH) then
        local bootstrapOk, bootstrapResult = beginFirstBootstrap('')
        if not bootstrapOk then
            log('cannot enable first bootstrap isolation: ' .. tostring(bootstrapResult))
            return
        end
        log('first bootstrap gate is active, session=' .. tostring(bootstrapResult))
    end

    wait(0)

    if not IS_MANAGED_LOADER and doesFileExist(FIRST_BOOTSTRAP_COMPLETED_PATH) then
        local managedPath = SCRIPT_DIR .. MANAGED_LOADER_FILENAME
        if doesFileExist(managedPath) then
            local managedValid, managedVersionOrError = validateLoaderFile(managedPath)
            local managedVersion = managedValid and managedVersionOrError or nil
            if managedValid and managedVersion then
                log('verified managed loader already exists, deleting obsolete bootstrap loader')
                pcall(os.remove, SCRIPT_DIR .. CURRENT_FILENAME)
                return
            end
            log('managed loader is invalid, keeping bootstrap loader for recovery: ' .. tostring(managedVersionOrError or 'version_missing'))
            removeFile(managedPath)
        else
            log('managed loader is missing, keeping bootstrap loader for recovery')
        end

        removeFile(FIRST_BOOTSTRAP_COMPLETED_PATH)
        local recoveryOk, recoveryResult = beginFirstBootstrap('')
        if not recoveryOk then
            log('managed loader recovery isolation failed: ' .. tostring(recoveryResult))
            return
        end
    end

    if IS_MANAGED_LOADER and doesFileExist(FIRST_BOOTSTRAP_PENDING_PATH) then
        managedBootstrapVerification()
        return
    end

    if IS_MANAGED_LOADER and selfUpdateManagedLoader() then
        return
    end

    cleanupDuplicateLoadedArzMarket()
    wait(500)
    waitForSamp()

    log('STEP 1: deleting legacy loader and old original ArzMarket file')
    cleanupStartupLegacyFiles()
    wait(150)

    log('STEP 2: checking CUSTOM GitHub')
    local customManifest = downloadManifest(
        CUSTOM_MANIFEST_URL,
        '.arzmarket_custom_manifest.json',
        'CUSTOM'
    )

    if not customManifest then
        log('STOP: CUSTOM manifest unavailable')
        return
    end

    log('VARIABLE myVersion = ' .. tostring(customManifest.latest))
    log('VARIABLE myUpdateUrl = ' .. tostring(customManifest.updateurl))
    log('STEP 3: verifying or installing CUSTOM ArzMarket')
    installSelectedVersion(customManifest)
end
