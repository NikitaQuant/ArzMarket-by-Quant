require 'moonloader'

script_name('ArzMarket Loader by Quant')
script_author('NikitaQuant')
script_version('0.47')

local moonloader = require 'moonloader'
local dlstatus = moonloader.download_status
local encoding = require 'encoding'
encoding.default = 'CP1251'
local u8 = encoding.UTF8

local OFFICIAL_MANIFEST_URL = 'https://raw.githubusercontent.com/FREYM1337/forumnick/main/ArzMarketV3/updateArzMarket.js'
local CUSTOM_MANIFEST_URL = 'https://raw.githubusercontent.com/NikitaQuant/ArzMarket-by-Quant/main/updateArzMarket.js'

local SCRIPT_DIR = getWorkingDirectory() .. '\\'
local INSTALL_MARKER_PATH = SCRIPT_DIR .. '.arzmarket_loader_downloaded'
local LOG_PREFIX = '[ArzMarket Loader by Quant] '

local originalVersion = nil
local originalUpdateUrl = nil

local myVersion = nil
local myUpdateUrl = nil

local selectedSource = nil
local selectedVersion = nil
local selectedUpdateUrl = nil

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

local function writeInstallMarker(version)
    local file = io.open(INSTALL_MARKER_PATH, 'wb')
    if not file then
        return false
    end

    file:write(tostring(version or ''))
    file:close()
    return true
end

local function fileSize(path)
    local file = io.open(path, 'rb')
    if not file then
        return 0
    end

    local size = file:seek('end') or 0
    file:close()

    return size
end

local function removeFile(path)
    if path and doesFileExist(path) then
        pcall(os.remove, path)
    end
end

local function readFile(path)
    local file = io.open(path, 'rb')
    if not file then
        return nil
    end

    local data = file:read('*a')
    file:close()

    return data
end


local function readInstallMarker()
    local data = readFile(INSTALL_MARKER_PATH)
    if not data then
        return ''
    end
    return tostring(data):gsub('^%s+', ''):gsub('%s+$', '')
end

local function addCacheBuster(url)
    local separator = url:find('?', 1, true) and '&' or '?'

    return url
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

local function decodeManifest(path)
    local raw = readFile(path)
    if not raw or raw == '' then
        return nil
    end

    local ok, data = pcall(decodeJson, raw)
    if not ok or type(data) ~= 'table' then
        return nil
    end

    if data.latest == nil then
        return nil
    end

    if type(data.updateurl) ~= 'string' or data.updateurl == '' then
        return nil
    end

    return {
        latest = tostring(data.latest),
        updateurl = data.updateurl
    }
end

local function downloadManifest(url, tempFileName, label)
    local tempPath = SCRIPT_DIR .. tempFileName

    for attempt = 1, 3 do
        log(label .. ': download manifest attempt ' .. tostring(attempt))

        if downloadAndWait(url, tempPath, 20) then
            local manifest = decodeManifest(tempPath)
            removeFile(tempPath)

            if manifest then
                return manifest
            end

            log(label .. ': manifest JSON is invalid')
        else
            log(label .. ': manifest download failed')
        end

        wait(500)
    end

    removeFile(tempPath)

    return nil
end

local function parseBaseVersion(version)
    local major, minor = tostring(version or ''):match('^(%d+)%.(%d+)')

    if not major or not minor then
        return nil, nil
    end

    return tonumber(major), tonumber(minor)
end

local function compareBaseVersions(original, custom)
    local originalMajor, originalMinor = parseBaseVersion(original)
    local customMajor, customMinor = parseBaseVersion(custom)

    if not originalMajor or not originalMinor or not customMajor or not customMinor then
        return nil
    end

    if originalMajor > customMajor then
        return 1
    elseif originalMajor < customMajor then
        return -1
    end

    if originalMinor > customMinor then
        return 1
    elseif originalMinor < customMinor then
        return -1
    end

    return 0
end

local function selectVersion()
    local comparison = compareBaseVersions(originalVersion, myVersion)

    if comparison == nil then
        return false, 'invalid version format'
    end

    if comparison > 0 then
        selectedSource = 'ORIGINAL'
        selectedVersion = originalVersion
        selectedUpdateUrl = originalUpdateUrl

        return true
    end

    if comparison < 0 then
        selectedSource = 'CUSTOM'
        selectedVersion = myVersion
        selectedUpdateUrl = myUpdateUrl

        return true
    end

    selectedSource = 'CUSTOM'
    selectedVersion = myVersion
    selectedUpdateUrl = myUpdateUrl

    return true
end

local function versionForFilename(version)
    return tostring(version)
        :gsub('%.', '_')
        :gsub('[^%d_]', '')
end

local function getTargetFilename()
    local versionPart = versionForFilename(selectedVersion)

    if selectedSource == 'CUSTOM' then
        return 'by_Quant_ArzMarket[3_57_123].lua'
    end

    return '#ArzMarket[' .. versionPart .. '].lua'
end

local function basename(path)
    return tostring(path or ''):match('([^\\/]+)$') or tostring(path or '')
end

local function isArzMarketFilename(filename)
    if type(filename) ~= 'string' then
        return false
    end

    if filename:match('^#ArzMarket%[.+%]%.lua$') then
        return true
    end

    if filename:match('^by_Quant_ArzMarket%[.+%]%.lua$') then
        return true
    end

    return false
end

local function findLoadedScript(filename)
    for _, scriptObject in ipairs(script.list()) do
        local currentName = scriptObject.filename or basename(scriptObject.path)

        if currentName == filename then
            return scriptObject
        end
    end

    return nil
end

local function collectOtherLoadedArzMarket(keepFilename)
    local result = {}

    for _, scriptObject in ipairs(script.list()) do
        local currentName = scriptObject.filename or basename(scriptObject.path)

        if currentName ~= thisScript().filename
            and currentName ~= keepFilename
            and isArzMarketFilename(currentName) then

            result[#result + 1] = {
                object = scriptObject,
                path = scriptObject.path
            }
        end
    end

    return result
end

local function unloadScripts(entries)
    for _, entry in ipairs(entries) do
        pcall(function()
            entry.object:unload()
        end)
    end
end

local function parseFilenameVersion(filename)
    local inside = tostring(filename or ''):match('%[([^%]]+)%]')
    if not inside then return {} end
    local parts = {}
    for value in inside:gmatch('%d+') do
        parts[#parts + 1] = tonumber(value) or 0
    end
    return parts
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

    if #loaded <= 1 then
        return
    end

    local keep = loaded[1]
    for index = 2, #loaded do
        if compareVersionParts(loaded[index].version, keep.version) > 0 then
            keep = loaded[index]
        end
    end

    log('duplicate guard: found ' .. tostring(#loaded) .. ' loaded ArzMarket scripts, keeping ' .. tostring(keep.name))

    for _, entry in ipairs(loaded) do
        if entry.object ~= keep.object then
            log('duplicate guard: unloading ' .. tostring(entry.name))
            pcall(function() entry.object:unload() end)
        end
    end

    wait(50)
end

local function restoreScripts(entries)
    for _, entry in ipairs(entries) do
        if entry.path and doesFileExist(entry.path) then
            pcall(script.load, entry.path)
        end
    end
end

local function cleanupMask(mask, keepFilename)
    local searchHandle, filename = findFirstFile(SCRIPT_DIR .. mask)

    if not searchHandle or not filename then
        return
    end

    while filename do
        if filename ~= keepFilename and isArzMarketFilename(filename) then
            removeFile(SCRIPT_DIR .. filename)
        end

        filename = findNextFile(searchHandle)
    end

    findClose(searchHandle)
end

local function cleanupOldFiles(keepFilename)
    cleanupMask('#ArzMarket*.lua', keepFilename)
    cleanupMask('by_Quant_ArzMarket*.lua', keepFilename)
end

local function validateLua(path)
    local chunk, errorText = loadfile(path)

    if not chunk then
        return false, errorText
    end

    return true
end

local function deleteStartupFile(filename)
    if type(filename) ~= 'string' or filename == '' then
        return
    end

    local path = SCRIPT_DIR .. filename
    local currentScript = thisScript()
    local loaded = findLoadedScript(filename)

    if loaded and loaded ~= currentScript then
        log('startup cleanup: unloading ' .. filename)
        pcall(function()
            loaded:unload()
        end)
        wait(100)
    end

    if doesFileExist(path) then
        log('startup cleanup: deleting ' .. filename)

        local removed, removeError = os.remove(path)
        if not removed and doesFileExist(path) then
            log('startup cleanup: failed to delete ' .. filename .. ': ' .. tostring(removeError))
            return false
        end
    end

    return true
end

local function cleanupStartupLegacyFiles()
    local files = {
        'ArzMarket_Loader.lua',
        '#ArzMarket[3_56].lua'
    }

    for _, filename in ipairs(files) do
        if filename ~= thisScript().filename then
            deleteStartupFile(filename)
        else
            log('startup cleanup: skipped current loader file ' .. filename)
        end
    end
end

local function installSelectedVersion()
    local targetFilename = getTargetFilename()
    local targetPath = SCRIPT_DIR .. targetFilename

    log('FINAL source = ' .. tostring(selectedSource))
    log('FINAL version = ' .. tostring(selectedVersion))
    log('FINAL url = ' .. tostring(selectedUpdateUrl))
    log('FINAL filename = ' .. tostring(targetFilename))

    local installedMarker = readInstallMarker()
    if doesFileExist(targetPath)
        and fileSize(targetPath) > 0
        and installedMarker == tostring(selectedVersion or '') then

        if not findLoadedScript(targetFilename) then
            if not script.load(targetPath) then
                log('existing selected script could not be loaded')
                return false
            end
        end

        local otherScripts = collectOtherLoadedArzMarket(targetFilename)
        unloadScripts(otherScripts)
        cleanupOldFiles(targetFilename)

        log('selected script is already installed')
        return true
    end

    if doesFileExist(targetPath) and fileSize(targetPath) > 0 then
        log('selected filename exists, but installed marker is old: '
            .. tostring(installedMarker) .. ' -> ' .. tostring(selectedVersion))
    end

    chatMessage('Загрузчик ArzMarket успешно загружен.')
    chatMessage('Начинаю скачивание ArzMarket...')

    local tempPath = targetPath .. '.download'

    if not downloadAndWait(selectedUpdateUrl, tempPath, 90) then
        log('selected script download failed')
        return false
    end

    local valid, validationError = validateLua(tempPath)
    if not valid then
        log('downloaded Lua is invalid: ' .. tostring(validationError))
        removeFile(tempPath)
        return false
    end

    local currentTargetScript = findLoadedScript(targetFilename)
    local otherScripts = collectOtherLoadedArzMarket(targetFilename)

    if currentTargetScript then
        pcall(function()
            currentTargetScript:unload()
        end)
        wait(50)
    end

    unloadScripts(otherScripts)
    wait(50)

    removeFile(targetPath)

    local renamed, renameError = os.rename(tempPath, targetPath)
    if not renamed then
        log('rename failed: ' .. tostring(renameError))
        removeFile(tempPath)
        restoreScripts(otherScripts)
        return false
    end

    writeInstallMarker(selectedVersion)

    if not script.load(targetPath) then
        log('new script failed to load')
        removeFile(INSTALL_MARKER_PATH)
        removeFile(targetPath)
        restoreScripts(otherScripts)
        return false
    end

    cleanupOldFiles(targetFilename)

    log('installed successfully')

    return true
end

function main()
    math.randomseed(os.time() + math.floor(os.clock() * 100000))

    -- MoonLoader загружает все *.lua из папки ещё до запуска main().
    -- Если пользователь оставил несколько старых ArzMarket, они не должны
    -- одновременно работать и патчить один и тот же Lua/mimgui/sampev runtime.
    wait(0)
    cleanupDuplicateLoadedArzMarket()

    wait(500)
    waitForSamp()

    log('STEP 1: deleting old loader and original ArzMarket file')
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

    myVersion = customManifest.latest
    myUpdateUrl = customManifest.updateurl

    selectedSource = 'CUSTOM'
    selectedVersion = myVersion
    selectedUpdateUrl = myUpdateUrl

    log('VARIABLE myVersion = ' .. tostring(myVersion))
    log('VARIABLE myUpdateUrl = ' .. tostring(myUpdateUrl))
    log('STEP 3: installing CUSTOM ArzMarket update')

    installSelectedVersion()
end
