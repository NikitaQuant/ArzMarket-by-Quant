local M = { api_version = 1, module_version = 1 }
local context = {}
local ROUTE_PATH = nil
local CONFIG_DIR = nil
local LAST_EXIT_FLAG_PATH = nil
local u8 = {
    decode = function(_, value)
        if type(context.fromUtf8) == "function" then
            return context.fromUtf8(value)
        end
        return value
    end,
    encode = function(_, value)
        if type(context.toUtf8) == "function" then
            return context.toUtf8(value)
        end
        return value
    end
}

local function buyRouteWorkingDirectory()
    return type(context.getWorkingDirectory) == "function"
        and context.getWorkingDirectory()
        or getWorkingDirectory()
end

local function refreshPaths()
    local workingDirectory = buyRouteWorkingDirectory()
    ROUTE_PATH = workingDirectory .. "\\BuyRoute\\route_points.lua"
    CONFIG_DIR = workingDirectory .. "\\config"
    LAST_EXIT_FLAG_PATH = CONFIG_DIR .. "\\BuyRoute_last_exit.flag"
end
    local vkeys = require("vkeys")
    local cp1251 = require("encoding").CP1251

-- После полного маршрута этот ЖЕ скрипт:
-- 1. отправляет финальный on-foot sync;
-- 2. ставит одноразовый флаг выбора "Последнее место выхода";
-- 3. выполняет /reconnect;
-- 4. сам перехватывает окно выбора спавна и выбирает last-exit.
local AUTO_RECONNECT_AFTER_FINISH = true
local FINAL_SYNC_WAIT_MS = 700
local RECONNECT_WAIT_MS = 700

local lastExitWarned = false
local cefSelectionScheduled = false
local firstSpawnSelectionScheduled = false
local spawnDialogSelectionScheduled = false
local spawnEnterScheduled = false

-- После появления CEF-меню специально ждём, пока интерфейс и авторизация
-- полностью стабилизируются. Мгновенный authSpawn/Enter больше не отправляется.
local SPAWN_SELECT_DELAY_MS = 3000
local RECONNECT_FALLBACK_DELAY_MS = 12000

local running = false
local runnerThread = nil

local routeRecorder = {
    active = false,
    points = {},
    loaded = false,
    thread = nil
}

-- 05D8 taskFollowPointRoute:
-- speed 6 = Run, flag 0.
local ROUTE_SPEED = 6
local ROUTE_FLAG = 0

-- GTA point route supports at most 8 points.
local MAX_ROUTE_POINTS = 8

-- Координаты больше НЕ сглаживаются.
-- Значения оставлены только для совместимости вызовов buildContinuousRoute.
local INDOOR_CORNER_CUT = 0
local OUTDOOR_CORNER_CUT = 0

-- Конечную точку сегмента считаем достигнутой здесь.
local FINISH_RADIUS = 0.25

-- На улице GTA может сама завершить taskFollowPointRoute чуть раньше,
-- чем контроллер попадёт в FINISH_RADIUS. Если персонаж уже остановился
-- рядом с конечной точкой, считаем это успешным финишем, а не застреванием.
local OUTDOOR_NEAR_FINISH_RADIUS = 1.10
local OUTDOOR_NEAR_FINISH_STALL_MS = 800

-- Последнюю точку слегка продлеваем вперёд по направлению предпоследняя -> последняя.
-- Применяется и к внешнему route_points.lua.
local FINAL_POINT_FORWARD_OFFSET = 0.30

-- Застревание.
local STUCK_WARN_MS = 3500
local HARD_STUCK_MS = 9000
local MOVE_EPSILON = 0.08

-- Локальное распознавание препятствий.
-- ВАЖНО: транспорт намеренно НЕ учитывается.
-- isLineOfSightClear flags:
-- buildings=true, vehicles=false, actors=false, objects=true, particles=false.
-- actors=false нужен специально, чтобы водитель/пассажиры внутри ТС не провоцировали обход.
local OBSTACLE_AVOIDANCE_ENABLED = true
local LOS_HEIGHT = 0.72
local BODY_CLEARANCE = 0.28
local DETOUR_OFFSETS = { 0.85, 1.20, 1.60, 2.10, 2.80, 3.60 }
local MAX_DETOUR_POINTS_PER_SEGMENT = 2

-- ALT для выхода.
local EXIT_RETRY_DELAY = 1800
local EXIT_MAX_ATTEMPTS = 6

-- GTA AI сам реагирует на приближающийся/стоящий транспорт даже если
-- наша LOS-проверка его не учитывает. На время маршрута отключаем
-- только две реакции ped AI, связанные с транспортом:
-- 12 = EVENT_POTENTIAL_GET_RUN_OVER
-- 56 = EVENT_POTENTIAL_WALK_INTO_VEHICLE
local originalDecisionMakerCopy = nil
local routeDecisionMakerCopy = nil
local vehicleEventsIgnored = false


local function msg(text, color)
    if color == 0xFF5555 and isSampAvailable() then
        sampAddChatMessage(u8:decode("[BuyRoute] " .. text), color)
    end
end

local function clonePoint(p)
    return {
        id = p.id,
        x = p.x,
        y = p.y,
        z = p.z,
        interior = p.interior,
        vw = p.vw
    }
end

local function distance3dPoints(a, b)
    local dx = b.x - a.x
    local dy = b.y - a.y
    local dz = b.z - a.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function distanceToPoint(x, y, z, p)
    local dx = p.x - x
    local dy = p.y - y
    local dz = p.z - z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function pointLerp(a, b, t)
    return {
        x = lerp(a.x, b.x, t),
        y = lerp(a.y, b.y, t),
        z = lerp(a.z, b.z, t),
        interior = a.interior,
        vw = a.vw
    }
end

local function validateRoute(route)
    if type(route) ~= "table" or #route < 2 then
        return false
    end

    for _, p in ipairs(route) do
        if type(p) ~= "table"
            or tonumber(p.x) == nil
            or tonumber(p.y) == nil
            or tonumber(p.z) == nil then
            return false
        end
    end

    return true
end

local function copyRoute(src)
    local result = {}

    for i, p in ipairs(src) do
        result[i] = {
            id = tonumber(p.id) or i,
            x = tonumber(p.x),
            y = tonumber(p.y),
            z = tonumber(p.z),
            interior = tonumber(p.interior) or -1,
            vw = tonumber(p.vw) or -1
        }
    end

    return result
end

local function loadRoute()
    if doesFileExist(ROUTE_PATH) then
        local loader = loadfile(ROUTE_PATH)

        if loader then
            local ok, data = pcall(loader)

            if ok and validateRoute(data) then
                return copyRoute(data), "file"
            end
        end
    end

    return nil, "missing"
end

local function sliceRoute(route, firstIndex, lastIndex)
    local out = {}

    for i = firstIndex, lastIndex do
        out[#out + 1] = clonePoint(route[i])
    end

    return out
end

-- Chaikin corner cutting.
-- Сохраняет общий ход траектории, но убирает резкие вершины.
local function smoothRoute(points, cut)
    if #points <= 2 then
        return copyRoute(points)
    end

    local out = { clonePoint(points[1]) }

    for i = 1, #points - 1 do
        local a = points[i]
        local b = points[i + 1]

        out[#out + 1] = pointLerp(a, b, cut)
        out[#out + 1] = pointLerp(a, b, 1.0 - cut)
    end

    out[#out + 1] = clonePoint(points[#points])
    return out
end

local function polylineLength(points)
    local total = 0.0

    for i = 1, #points - 1 do
        total = total + distance3dPoints(points[i], points[i + 1])
    end

    return total
end

local function sampleAtDistance(points, wanted)
    local passed = 0.0

    for i = 1, #points - 1 do
        local a = points[i]
        local b = points[i + 1]
        local length = distance3dPoints(a, b)

        if length > 0.0001 and passed + length >= wanted then
            local t = (wanted - passed) / length
            return pointLerp(a, b, t)
        end

        passed = passed + length
    end

    return clonePoint(points[#points])
end

-- Сжимаем сглаженную линию до максимум 8 точек,
-- потому что GTA point route имеет лимит 8.
local function resampleToLimit(points, limit)
    if #points <= limit then
        return points
    end

    local length = polylineLength(points)

    if length <= 0.001 then
        return { clonePoint(points[1]), clonePoint(points[#points]) }
    end

    local out = {}

    for i = 0, limit - 1 do
        local t = i / (limit - 1)
        out[#out + 1] = sampleAtDistance(points, length * t)
    end

    out[1] = clonePoint(points[1])
    out[#out] = clonePoint(points[#points])

    return out
end

local function losClearPointToPoint(a, b)
    if not OBSTACLE_AVOIDANCE_ENABLED then
        return true
    end

    if type(isLineOfSightClear) ~= "function" then
        return true
    end

    local ok, clear = pcall(
        isLineOfSightClear,
        a.x, a.y, a.z + LOS_HEIGHT,
        b.x, b.y, b.z + LOS_HEIGHT,
        true,   -- buildings
        false,  -- vehicles: ИГНОРИРУЕМ ТС
        false,  -- actors: тоже false, чтобы водитель/пассажиры ТС не считались препятствием
        true,   -- objects
        false   -- particles
    )

    if not ok then
        return true
    end

    return clear == true
end

local function offsetPointSide(a, b, point, sideOffset)
    local dx = b.x - a.x
    local dy = b.y - a.y
    local len = math.sqrt(dx * dx + dy * dy)

    if len < 0.001 then
        return clonePoint(point)
    end

    local px = -dy / len
    local py = dx / len

    return {
        x = point.x + px * sideOffset,
        y = point.y + py * sideOffset,
        z = point.z,
        interior = point.interior,
        vw = point.vw
    }
end

local function corridorClear(a, b)
    if not losClearPointToPoint(a, b) then
        return false
    end

    local leftA = offsetPointSide(a, b, a, BODY_CLEARANCE)
    local leftB = offsetPointSide(a, b, b, BODY_CLEARANCE)

    if not losClearPointToPoint(leftA, leftB) then
        return false
    end

    local rightA = offsetPointSide(a, b, a, -BODY_CLEARANCE)
    local rightB = offsetPointSide(a, b, b, -BODY_CLEARANCE)

    return losClearPointToPoint(rightA, rightB)
end

local function pointAtFraction(a, b, t)
    return {
        x = a.x + (b.x - a.x) * t,
        y = a.y + (b.y - a.y) * t,
        z = a.z + (b.z - a.z) * t,
        interior = a.interior,
        vw = a.vw
    }
end

local function pathLength3(points)
    local total = 0.0

    for i = 1, #points - 1 do
        total = total + distance3dPoints(points[i], points[i + 1])
    end

    return total
end

local function findStaticDetour(a, b)
    if corridorClear(a, b) then
        return {}
    end

    local best = nil
    local bestLength = math.huge

    for _, offset in ipairs(DETOUR_OFFSETS) do
        for _, side in ipairs({ 1, -1 }) do
            local signedOffset = offset * side

            -- Сначала пробуем один боковой пункт около середины препятствия.
            local middle = pointAtFraction(a, b, 0.50)
            local c = offsetPointSide(a, b, middle, signedOffset)

            if corridorClear(a, c) and corridorClear(c, b) then
                local candidate = { a, c, b }
                local length = pathLength3(candidate)

                if length < bestLength then
                    bestLength = length
                    best = { clonePoint(c) }
                end
            end

            -- Если одного пункта мало, строим короткий параллельный обход.
            local nearA = pointAtFraction(a, b, 0.28)
            local nearB = pointAtFraction(a, b, 0.72)
            local c1 = offsetPointSide(a, b, nearA, signedOffset)
            local c2 = offsetPointSide(a, b, nearB, signedOffset)

            if corridorClear(a, c1)
                and corridorClear(c1, c2)
                and corridorClear(c2, b) then

                local candidate = { a, c1, c2, b }
                local length = pathLength3(candidate)

                if length < bestLength then
                    bestLength = length
                    best = { clonePoint(c1), clonePoint(c2) }
                end
            end
        end
    end

    return best
end

local function simplifyObstacleRoute(points, limit)
    if #points <= limit then
        return points
    end

    local result = { clonePoint(points[1]) }
    local index = 1

    while index < #points do
        local chosen = index + 1

        -- Берём самую дальнюю точку, до которой реально свободен коридор.
        for candidate = #points, index + 1, -1 do
            if corridorClear(points[index], points[candidate]) then
                chosen = candidate
                break
            end
        end

        result[#result + 1] = clonePoint(points[chosen])
        index = chosen

        if #result > limit then
            return nil
        end
    end

    return result
end

local function buildContinuousRoute(rawPoints, cornerCut)
    -- Основой остаются ровно записанные координаты.
    -- Дополнительные точки появляются только если между двумя соседними
    -- координатами реально есть статическое препятствие.
    --
    -- Транспорт не может создать препятствие, потому что vehicles=false.
    local exact = {}

    for i, p in ipairs(rawPoints) do
        exact[i] = clonePoint(p)
    end

    if not OBSTACLE_AVOIDANCE_ENABLED or #exact < 2 then
        return exact
    end

    local expanded = { clonePoint(exact[1]) }
    local detourCount = 0

    for i = 1, #exact - 1 do
        local a = exact[i]
        local b = exact[i + 1]

        if corridorClear(a, b) then
            expanded[#expanded + 1] = clonePoint(b)
        else
            local detour = findStaticDetour(a, b)

            if detour and #detour > 0 then
                for n = 1, math.min(#detour, MAX_DETOUR_POINTS_PER_SEGMENT) do
                    expanded[#expanded + 1] = clonePoint(detour[n])
                    detourCount = detourCount + 1
                end

                expanded[#expanded + 1] = clonePoint(b)
            else
                -- Если автоматический обход не найден, сохраняем исходную точку.
                -- Так бот не начинает придумывать далёкий маршрут.
                expanded[#expanded + 1] = clonePoint(b)
            end
        end
    end

    if #expanded > MAX_ROUTE_POINTS then
        local simplified = simplifyObstacleRoute(expanded, MAX_ROUTE_POINTS)

        if simplified then
            expanded = simplified
        else
            -- Безопасный fallback: исходные координаты всегда помещаются
            -- в текущие сегменты (4 внутри и 7 снаружи).
            expanded = resampleToLimit(exact, MAX_ROUTE_POINTS)
            detourCount = 0
        end
    end

    if detourCount > 0 then
        msg(
            string.format(
                "Навигация: добавлено %d точек обхода. Транспорт игнорируется.",
                detourCount
            ),
            0xAAAAFF
        )
    end

    return expanded
end

local function extendFinalRoutePoint(route)
    if type(route) ~= "table" or #route < 2 then
        return
    end

    local prev = route[#route - 1]
    local last = route[#route]

    local dx = last.x - prev.x
    local dy = last.y - prev.y
    local dz = last.z - prev.z
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)

    if len < 0.001 then
        return
    end

    last.x = last.x + (dx / len) * FINAL_POINT_FORWARD_OFFSET
    last.y = last.y + (dy / len) * FINAL_POINT_FORWARD_OFFSET
    last.z = last.z + (dz / len) * FINAL_POINT_FORWARD_OFFSET
end

local function getInteriorSafe()
    if type(getActiveInterior) == "function" then
        local ok, value = pcall(getActiveInterior)

        if ok and value ~= nil then
            return tonumber(value) or -1
        end
    end

    return -1
end

routeRecorder.notify = function(text, color)
    if isSampAvailable() then
        sampAddChatMessage(u8:decode("[BuyRoute] " .. text), color or 0x55CCFF)
    end
end

routeRecorder.numberText = function(value)
    local text = string.format("%.6f", tonumber(value) or 0)
    return text:gsub(",", ".")
end

routeRecorder.ensureLoaded = function()
    if routeRecorder.loaded then
        return
    end

    local data = select(1, loadRoute())
    routeRecorder.points = type(data) == "table" and data or {}
    routeRecorder.loaded = true
end

routeRecorder.save = function()
    if not doesDirectoryExist(buyRouteWorkingDirectory() .. "\\BuyRoute") then
        createDirectory(buyRouteWorkingDirectory() .. "\\BuyRoute")
    end

    if #routeRecorder.points == 0 then
        if doesFileExist(ROUTE_PATH) then
            os.remove(ROUTE_PATH)
        end
        return true
    end

    local file, err = io.open(ROUTE_PATH, "w")

    if not file then
        routeRecorder.notify(u8:decode("Не удалось сохранить точки: ") .. tostring(err), 0xFF5555)
        return false
    end

    file:write("return {\n")

    for index, point in ipairs(routeRecorder.points) do
        point.id = index
        file:write(
            "    { id = " .. tostring(index)
                .. ", x = " .. routeRecorder.numberText(point.x)
                .. ", y = " .. routeRecorder.numberText(point.y)
                .. ", z = " .. routeRecorder.numberText(point.z)
                .. ", interior = " .. tostring(math.floor(tonumber(point.interior) or -1))
                .. ", vw = " .. tostring(math.floor(tonumber(point.vw) or -1))
                .. " },\n"
        )
    end

    file:write("}\n")
    file:close()
    return true
end

routeRecorder.addPoint = function()
    routeRecorder.ensureLoaded()

    local x, y, z = getCharCoordinates(PLAYER_PED)
    local point = {
        id = #routeRecorder.points + 1,
        x = x,
        y = y,
        z = z,
        interior = getInteriorSafe(),
        vw = -1
    }

    routeRecorder.points[#routeRecorder.points + 1] = point

    if routeRecorder.save() then
        routeRecorder.notify(
            u8:decode("Точка ") .. tostring(#routeRecorder.points)
                .. u8:decode(" добавлена. Интерьер: ") .. tostring(point.interior) .. ".",
            0x55FF55
        )
    end
end

routeRecorder.removeLastPoint = function()
    routeRecorder.ensureLoaded()

    if #routeRecorder.points == 0 then
        routeRecorder.notify(u8:decode("Точек пока нет."), 0xFFFFAA)
        return
    end

    local removedIndex = #routeRecorder.points
    table.remove(routeRecorder.points)
    routeRecorder.save()
    routeRecorder.notify(u8:decode("Точка ") .. tostring(removedIndex) .. u8:decode(" удалена."), 0xFFAA55)
end

routeRecorder.stop = function(silent)
    if not routeRecorder.active then
        return false
    end

    routeRecorder.active = false
    routeRecorder.save()

    if not silent then
        routeRecorder.notify(
            u8:decode("Запись завершена. Сохранено точек: ") .. tostring(#routeRecorder.points) .. ".",
            #routeRecorder.points >= 2 and 0x55FF55 or 0xFFFFAA
        )
    end

    return true
end

routeRecorder.start = function()
    if running then
        routeRecorder.notify(u8:decode("Сначала остановите запущенный маршрут."), 0xFF5555)
        return false
    end

    if routeRecorder.active then
        return true
    end

    routeRecorder.ensureLoaded()
    routeRecorder.active = true
    routeRecorder.notify(u8:decode("Выбор точек включён. F5 добавить, F6 удалить последнюю, F7 завершить."), 0x55CCFF)

    routeRecorder.thread = lua_thread.create(function()
        while routeRecorder.active do
            wait(0)

            local inputBlocked = isPauseMenuActive()
                or (type(sampIsChatInputActive) == "function" and sampIsChatInputActive())
                or (type(sampIsDialogActive) == "function" and sampIsDialogActive())
                or (type(context.getMenuVisible) == "function" and context.getMenuVisible())

            if not inputBlocked then
                if isKeyJustPressed(vkeys.VK_F5) then
                    routeRecorder.addPoint()
                elseif isKeyJustPressed(vkeys.VK_F6) then
                    routeRecorder.removeLastPoint()
                elseif isKeyJustPressed(vkeys.VK_F7) then
                    routeRecorder.stop(false)
                end
            end
        end

        routeRecorder.thread = nil
    end)

    return true
end

routeRecorder.clear = function()
    if running then
        routeRecorder.notify(u8:decode("Нельзя очищать точки во время движения по маршруту."), 0xFF5555)
        return false
    end

    routeRecorder.ensureLoaded()
    routeRecorder.points = {}
    routeRecorder.save()
    routeRecorder.notify(u8:decode("Все точки маршрута удалены."), 0xFFAA55)
    return true
end

routeRecorder.getCount = function()
    routeRecorder.ensureLoaded()
    return #routeRecorder.points
end

routeRecorder.findExitPointIndex = function(route)
    if type(route) ~= "table" then
        return nil
    end

    for index = 1, #route - 1 do
        local currentInterior = tonumber(route[index].interior) or -1
        local nextInterior = tonumber(route[index + 1].interior) or -1

        if currentInterior ~= 0 and nextInterior == 0 then
            return index
        end
    end

    return nil
end

local function enableVehicleEventIgnore()
    if vehicleEventsIgnored then
        return true
    end

    if type(copyCharDecisionMaker) ~= "function"
        or type(clearCharDecisionMakerEventResponse) ~= "function"
        or type(setCharDecisionMaker) ~= "function" then

        msg("Не удалось отключить GTA-обход транспорта: нет DecisionMaker API.", 0xFF5555)
        return false
    end

    -- Сохраняем копию исходного поведения игрока, чтобы потом вернуть его.
    local okOriginal, originalCopy = pcall(copyCharDecisionMaker, PLAYER_PED)

    if not okOriginal or originalCopy == nil then
        msg("Не удалось сохранить исходный DecisionMaker персонажа.", 0xFF5555)
        return false
    end

    -- Отдельная копия используется только для маршрута.
    local okRoute, routeCopy = pcall(copyCharDecisionMaker, PLAYER_PED)

    if not okRoute or routeCopy == nil then
        msg("Не удалось создать маршрутный DecisionMaker.", 0xFF5555)
        return false
    end

    -- Полностью убираем реакцию AI на транспорт.
    pcall(clearCharDecisionMakerEventResponse, routeCopy, 12)
    pcall(clearCharDecisionMakerEventResponse, routeCopy, 56)

    local okSet = pcall(setCharDecisionMaker, PLAYER_PED, routeCopy)

    if not okSet then
        msg("Не удалось включить режим полного игнора транспорта.", 0xFF5555)
        return false
    end

    originalDecisionMakerCopy = originalCopy
    routeDecisionMakerCopy = routeCopy
    vehicleEventsIgnored = true

    msg("GTA AI: транспорт полностью исключён из реакций движения.", 0xAAAAFF)
    return true
end

local function restoreVehicleEvents()
    if not vehicleEventsIgnored then
        return
    end

    if originalDecisionMakerCopy ~= nil and type(setCharDecisionMaker) == "function" then
        pcall(setCharDecisionMaker, PLAYER_PED, originalDecisionMakerCopy)
    end

    vehicleEventsIgnored = false
    originalDecisionMakerCopy = nil
    routeDecisionMakerCopy = nil
end

local function clearMovement(preserveVehicle)
    local playerInVehicle = false

    if preserveVehicle == true and type(isCharInAnyCar) == "function" then
        local ok, result = pcall(isCharInAnyCar, PLAYER_PED)
        playerInVehicle = ok and result == true
    end

    -- clearCharTasksImmediately resets the current ped task. During script
    -- termination that may also break the active in-vehicle task, so never
    -- call it for a seated player when cleanup explicitly preserves transport.
    if not playerInVehicle then
        pcall(clearCharTasksImmediately, PLAYER_PED)
    end

    pcall(flushRoute)
    setGameKeyState(16, 0)
    setGameKeyState(21, 0)
end

local function restorePlayer(preserveVehicle)
    clearMovement(preserveVehicle)
    restoreVehicleEvents()
end

local function startContinuousRoute(points)
    clearMovement()

    -- Важно: taskFollowPointRoute сам умеет реагировать на автомобили.
    -- Поэтому отключаем vehicle events ДО назначения AI-задачи.
    enableVehicleEventIgnore()

    wait(80)

    flushRoute()

    if #points > MAX_ROUTE_POINTS then
        error("BuyRoute: point-route contains more than 8 points")
    end

    for _, p in ipairs(points) do
        extendRoute(p.x, p.y, p.z)
    end

    -- ОДНА задача на весь список координат.
    -- Никаких новых task на промежуточных точках.
    taskFollowPointRoute(PLAYER_PED, ROUTE_SPEED, ROUTE_FLAG)
end

local function forceSprint()
    -- Оставляем его, но маршрут теперь один непрерывный.
    setGameKeyState(16, 256)
end

local function waitForContinuousRoute(points, label)
    local finish = points[#points]

    local lastX, lastY, lastZ = getCharCoordinates(PLAYER_PED)
    local lastMoveAt = getGameTimer()
    local warned = false

    while running do
        wait(0)

        if isCharInAnyCar(PLAYER_PED) then
            setGameKeyState(16, 0)
            msg("Персонаж оказался в транспорте. Маршрут остановлен.", 0xFF5555)
            return false
        end

        forceSprint()

        local x, y, z = getCharCoordinates(PLAYER_PED)
        local finishDistance = distanceToPoint(x, y, z, finish)

        if finishDistance <= FINISH_RADIUS then
            setGameKeyState(16, 0)
            return true
        end

        local dx = x - lastX
        local dy = y - lastY
        local dz = z - lastZ
        local moved = math.sqrt(dx * dx + dy * dy + dz * dz)

        if moved >= MOVE_EPSILON then
            lastX, lastY, lastZ = x, y, z
            lastMoveAt = getGameTimer()
            warned = false
        else
            local stuckFor = getGameTimer() - lastMoveAt

            -- Специально для последнего уличного сегмента:
            -- если GTA уже остановила ped рядом с конечной координатой,
            -- не ждём 9 секунд и не объявляем ложное застревание.
            if label == "Улица"
                and finishDistance <= OUTDOOR_NEAR_FINISH_RADIUS
                and stuckFor >= OUTDOOR_NEAR_FINISH_STALL_MS then

                setGameKeyState(16, 0)
                msg(
                    string.format(
                        "Улица: конечная достигнута, расстояние %.2f м.",
                        finishDistance
                    ),
                    0x55FF55
                )
                return true
            end

            if stuckFor >= STUCK_WARN_MS and not warned then
                warned = true
                msg(label .. ": почти не двигаюсь, но маршрут не перезапускаю.", 0xFFFFAA)
            end

            if stuckFor >= HARD_STUCK_MS then
                setGameKeyState(16, 0)
                msg(label .. ": застрял более чем на 9 секунд.", 0xFF5555)
                return false
            end
        end
    end

    setGameKeyState(16, 0)
    return false
end

local function pressAltOnce()
    -- После AI-маршрута сначала полностью возвращаем обычное
    -- поведение PLAYER_PED. Иначе task/DecisionMaker может съесть ALT.
    clearMovement()
    restoreVehicleEvents()

    setGameKeyState(16, 0)
    setGameKeyState(21, 0)

    wait(250)

    -- Нажимаем сразу двумя способами:
    -- 1) настоящий Windows ALT;
    -- 2) GTA control WALK (key 21), к которому обычно привязан ALT.
    local altVk = vkeys.VK_LMENU or vkeys.VK_MENU

    if altVk then
        setVirtualKeyDown(altVk, true)
    end

    setGameKeyState(21, 255)

    wait(320)

    setGameKeyState(21, 0)

    if altVk then
        setVirtualKeyDown(altVk, false)
    end

    wait(180)
end

local function waitForExterior(nextPoint)
    local startX, startY, startZ = getCharCoordinates(PLAYER_PED)

    for attempt = 1, EXIT_MAX_ATTEMPTS do
        if not running then
            return false
        end

        msg(
            string.format(
                "Нажимаю ALT для выхода. Попытка %d/%d.",
                attempt,
                EXIT_MAX_ATTEMPTS
            ),
            0xFFFFAA
        )

        pressAltOnce()

        local deadline = getGameTimer() + EXIT_RETRY_DELAY

        while running and getGameTimer() < deadline do
            wait(50)

            local x, y, z = getCharCoordinates(PLAYER_PED)
            local interior = getInteriorSafe()

            local dx = x - startX
            local dy = y - startY
            local dz = z - startZ
            local movedFar = math.sqrt(dx * dx + dy * dy + dz * dz) > 40.0
            local nearExterior = distanceToPoint(x, y, z, nextPoint) < 70.0

            if interior == 0 or movedFar or nearExterior then
                wait(650)
                msg("Выход из интерьера обнаружен.", 0x55FF55)
                return true
            end
        end
    end

    msg("Не удалось выйти из интерьера.", 0xFF5555)
    return false
end

local function ensureConfigDir()
    if not doesDirectoryExist(CONFIG_DIR) then
        createDirectory(CONFIG_DIR)
    end
end

local function hasLastExitFlag()
    return doesFileExist(LAST_EXIT_FLAG_PATH)
end

local function clearLastExitFlag()
    if doesFileExist(LAST_EXIT_FLAG_PATH) then
        os.remove(LAST_EXIT_FLAG_PATH)
    end
    lastExitWarned = false
    cefSelectionScheduled = false
    firstSpawnSelectionScheduled = false
    spawnDialogSelectionScheduled = false
    spawnEnterScheduled = false
end

local function armLastExitSpawnOnce()
    ensureConfigDir()

    local file, err = io.open(LAST_EXIT_FLAG_PATH, "w")

    if not file then
        msg("Не удалось подготовить выбор последнего места выхода: " .. tostring(err), 0xFF5555)
        return false
    end

    file:write(tostring(os.time()))
    file:close()
    lastExitWarned = false
    cefSelectionScheduled = false
    firstSpawnSelectionScheduled = false
    spawnDialogSelectionScheduled = false
    spawnEnterScheduled = false

    return true
end

local function cleanSpawnName(name)
    name = tostring(name or "")
    name = name:gsub("{%x%x%x%x%x%x}", "")
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    return name
end

local function isLastExitSpawn(name)
    local s = cleanSpawnName(name)

    return s:find("Последнее место выхода", 1, true) ~= nil
        or s:find("Место последнего выхода", 1, true) ~= nil
        or s:find("Последнее место выхода из игры", 1, true) ~= nil
end

local function arizonaSendSelectSpawn(spawnId)
    local payload = "authSpawn|" .. tostring(spawnId)
    local bs = raknetNewBitStream()

    raknetBitStreamWriteInt8(bs, 220)
    raknetBitStreamWriteInt8(bs, 18)
    raknetBitStreamWriteInt32(bs, #payload)
    raknetBitStreamWriteString(bs, payload)
    raknetBitStreamWriteInt32(bs, 0)
    raknetSendBitStreamEx(bs, 1, 7, 1)
    raknetDeleteBitStream(bs)
end

local function bitStreamToRawString(bs)
    local out = {}

    raknetBitStreamResetReadPointer(bs)

    local count = raknetBitStreamGetNumberOfBytesUsed(bs)

    for i = 1, count do
        local byte = raknetBitStreamReadInt8(bs)

        -- На некоторых сборках ReadInt8 возвращает signed int8.
        if byte < 0 then
            byte = byte + 256
        end

        out[#out + 1] = string.char(byte)
    end

    raknetBitStreamResetReadPointer(bs)

    return table.concat(out)
end

local function normalizeSpawnText(raw)
    local s = tostring(raw or "")

    -- Сначала пробуем CP1251 -> UTF-8.
    local ok, decoded = pcall(function()
        return cp1251:decode(s)
    end)

    if ok and decoded and decoded ~= "" then
        s = decoded
    end

    s = cleanSpawnName(s)
    s = s:gsub("%s+", " ")

    return s
end

local function isLastExitLoose(name)
    local s = normalizeSpawnText(name)
    local lower = s:lower()

    return lower:find("последнее место выхода", 1, true) ~= nil
        or lower:find("место последнего выхода", 1, true) ~= nil
        or lower:find("место выхода", 1, true) ~= nil
end

local function findLastExitInActiveDialog()
    if not hasLastExitFlag() then
        return false
    end

    if type(sampIsDialogActive) ~= "function"
        or not sampIsDialogActive() then
        return false
    end

    if type(sampGetListboxItemsCount) ~= "function"
        or type(sampGetListboxItemText) ~= "function"
        or type(sampGetCurrentDialogId) ~= "function" then
        return false
    end

    local count = sampGetListboxItemsCount()

    if not count or count <= 0 then
        return false
    end

    local dialogId = sampGetCurrentDialogId()

    for index = 0, count - 1 do
        local ok, itemText = pcall(sampGetListboxItemText, index)

        if ok and itemText and isLastExitLoose(itemText) then
            msg(
                string.format(
                    'Диалог: найдено "Последнее место выхода", строка %d.',
                    index + 1
                ),
                0x55FF55
            )

            sampSendDialogResponse(dialogId, 1, index, "")
            clearLastExitFlag()
            return true
        end
    end

    return false
end

local function scheduleDialogSearch()
    if cefSelectionScheduled or not hasLastExitFlag() then
        return
    end

    cefSelectionScheduled = true

    lua_thread.create(function()
        msg(
            string.format(
                'Жду %.1f сек. и ищу "Последнее место выхода" в диалоге.',
                SPAWN_SELECT_DELAY_MS / 1000
            ),
            0xFFFFAA
        )

        wait(SPAWN_SELECT_DELAY_MS)

        if hasLastExitFlag() then
            -- Старый SA-MP диалог проверяем молча.
            -- При новой авторизации нужное окно является CEF и будет обработано packet 220.
            findLastExitInActiveDialog()
        end

        cefSelectionScheduled = false
    end)
end

-- Реальный входящий CEF-формат Arizona.
-- Packet 220 -> subId 17 -> skip 32 bits -> int16 len -> int8 encoding flag -> JS string.
local function readArizonaCef220(bs)
    raknetBitStreamResetReadPointer(bs)

    -- Packet ID находится первым байтом самого BitStream.
    raknetBitStreamIgnoreBits(bs, 8)

    local subId = raknetBitStreamReadInt8(bs)
    if subId ~= 17 then
        raknetBitStreamResetReadPointer(bs)
        return nil
    end

    raknetBitStreamIgnoreBits(bs, 32)

    local len = raknetBitStreamReadInt16(bs)
    local flag = raknetBitStreamReadInt8(bs)

    if not len or len <= 0 or len > 32767 then
        raknetBitStreamResetReadPointer(bs)
        return nil
    end

    local cefText

    if flag ~= 0 then
        cefText = raknetBitStreamDecodeString(bs, len + flag)
    else
        cefText = raknetBitStreamReadString(bs, len)
    end

    raknetBitStreamResetReadPointer(bs)
    return cefText
end

-- Старый канал AutoSelectSpawnV4, оставляем как дополнительный fallback.
local function readPrintablePacket(bs)
    local out = ""

    raknetBitStreamResetReadPointer(bs)

    for i = 1, raknetBitStreamGetNumberOfBytesUsed(bs) do
        local byte = raknetBitStreamReadInt8(bs)

        if byte < 0 then
            byte = byte + 256
        end

        if byte >= 32 and byte <= 255 and byte ~= 37 then
            out = out .. string.char(byte)
        end
    end

    raknetBitStreamResetReadPointer(bs)
    return out
end

local function decodeSpawnName(raw)
    local value = tostring(raw or "")

    -- В зависимости от версии CEF строка может уже быть UTF-8
    -- либо содержать CP1251. Проверяем оба варианта.
    if isLastExitLoose(value) then
        return value
    end

    local ok, decoded = pcall(function()
        return cp1251:decode(value)
    end)

    if ok and decoded then
        return decoded
    end

    return value
end

local function findLastExitSpawnId(points)
    if type(points) ~= "table" then
        return nil, nil
    end

    for index, p in ipairs(points) do
        if type(p) == "table" then
            local spawnName = decodeSpawnName(p.spawn)

            if isLastExitLoose(spawnName) then
                return p.id, spawnName
            end
        end
    end

    return nil, nil
end

local function scheduleCefSpawnId(spawnId, spawnName)
    if cefSelectionScheduled or not hasLastExitFlag() then
        return
    end

    cefSelectionScheduled = true

    lua_thread.create(function()
        msg(
            string.format(
                'CEF: найден пункт "%s". Жду %.1f сек.',
                tostring(spawnName or "Последнее место выхода"),
                SPAWN_SELECT_DELAY_MS / 1000
            ),
            0xFFFFAA
        )

        wait(SPAWN_SELECT_DELAY_MS)

        if hasLastExitFlag() and spawnId ~= nil then
            arizonaSendSelectSpawn(spawnId)
            clearLastExitFlag()
            msg('CEF: выбрано "Последнее место выхода".', 0x55FF55)
        end

        cefSelectionScheduled = false
    end)
end

local function parseInitializeSpawnPoints(cefText)
    if type(cefText) ~= "string" then
        return false
    end

    if not cefText:find("event.auth.initializeSpawnPoints", 1, true) then
        return false
    end

    local event, jsonData =
        cefText:match("window%.executeEvent%(%s*'([^']+)'%s*,%s*`([^`]*)`%s*%)")

    if not event then
        event, jsonData =
            cefText:match('window%.executeEvent%(%s*"([^"]+)"%s*,%s*`([^`]*)`%s*%)')
    end

    if not event then
        event, jsonData =
            cefText:match("window%.executeEvent%(%s*'([^']+)'%s*,%s*'(.+)'%s*%)")
    end

    if event ~= "event.auth.initializeSpawnPoints" or not jsonData then
        return false
    end

    local ok, decoded = pcall(decodeJson, jsonData)

    if not ok or type(decoded) ~= "table" then
        return false
    end

    local points = decoded[1]

    if type(points) ~= "table" then
        points = decoded
    end

    local first = points[1]

    if type(first) == "table" and first.id ~= nil then
        msg(
            string.format(
                "CEF: первый пункт найден, spawnId=%s.",
                tostring(first.id)
            ),
            0x55FF55
        )

        scheduleFirstCefSpawn(first.id)
        return true
    end

    return false
end

local function trySelectLastExitFromPacket(packetId, bs)
    if packetId == 220 then
        local ok, cefText = pcall(readArizonaCef220, bs)

        if ok and cefText then
            return parseInitializeSpawnPoints(cefText)
        end
    elseif packetId == 239 then
        local ok, raw = pcall(readPrintablePacket, bs)

        if ok and raw then
            return parseInitializeSpawnPoints(raw)
        end
    end

    return false
end

local function scheduleFirstDialogItem(dialogId)
    if firstSpawnSelectionScheduled or not hasLastExitFlag() then
        return
    end

    firstSpawnSelectionScheduled = true

    lua_thread.create(function(id)
        msg(
            string.format(
                "Меню спавна открыто. Жду %.1f сек. и выбираю первый пункт.",
                SPAWN_SELECT_DELAY_MS / 1000
            ),
            0xFFFFAA
        )

        wait(SPAWN_SELECT_DELAY_MS)

        if hasLastExitFlag() then
            -- Первая строка SA-MP listbox имеет индекс 0.
            sampSendDialogResponse(id, 1, 0, "")
            clearLastExitFlag()
            msg("Выбран первый пункт меню спавна.", 0x55FF55)
        end

        firstSpawnSelectionScheduled = false
    end, dialogId)
end

local function scheduleFirstCefSpawn(spawnId)
    if firstSpawnSelectionScheduled or not hasLastExitFlag() then
        return
    end

    firstSpawnSelectionScheduled = true

    lua_thread.create(function(id)
        msg(
            string.format(
                "CEF-меню спавна открыто. Жду %.1f сек. и выбираю первый пункт.",
                SPAWN_SELECT_DELAY_MS / 1000
            ),
            0xFFFFAA
        )

        wait(SPAWN_SELECT_DELAY_MS)

        if hasLastExitFlag() and id ~= nil then
            arizonaSendSelectSpawn(id)
            clearLastExitFlag()
            msg("CEF: выбран первый пункт меню спавна.", 0x55FF55)
        end

        firstSpawnSelectionScheduled = false
    end, spawnId)
end

local function reconnectFromFinalPoint()
    restorePlayer()

    if type(sampForceOnfootSync) == "function" then
        pcall(sampForceOnfootSync)
    end

    wait(FINAL_SYNC_WAIT_MS)

    if not armLastExitSpawnOnce() then
        msg("Перезаход отменён, чтобы не потерять конечную точку.", 0xFF5555)
        return false
    end

    msg("Конечная достигнута. Перезахожу на последнее место выхода.", 0x55CCFF)
    wait(RECONNECT_WAIT_MS)

    sampProcessChatInput("/rec")

    -- Аварийный резерв: если CEF packet hook не сработал,
    -- через несколько секунд проверяем, остался ли одноразовый флаг.
    -- Никакого резервного CEF/клавиатурного выбора.
    -- Ждём только подтверждённый SA-MP dialog "Выбор места спавна".

    return true
end

local function runRoute()
    local route, source = loadRoute()

    if not validateRoute(route) then
        running = false
        restorePlayer()
        routeRecorder.notify(u8:decode("Маршрут не настроен. Запишите минимум две точки через раздел Модификации."), 0xFF5555)
        return
    end

    extendFinalRoutePoint(route)

    local currentInterior = getInteriorSafe()
    local firstInterior = tonumber(route[1].interior) or -1

    if firstInterior >= 0 and currentInterior >= 0 and firstInterior ~= currentInterior then
        running = false
        restorePlayer()
        routeRecorder.notify(
            u8:decode("Старт отменён: первая точка записана в другом интерьере. Текущий: ")
                .. tostring(currentInterior) .. u8:decode(", первая точка: ") .. tostring(firstInterior) .. ".",
            0xFF5555
        )
        return
    end

    local exitPointIndex = routeRecorder.findExitPointIndex(route)

    if exitPointIndex ~= nil then
        if currentInterior == 0 then
            running = false
            restorePlayer()
            routeRecorder.notify(u8:decode("Старт отменён: этот маршрут начинается в интерьере."), 0xFF5555)
            return
        end

        local indoorRaw = sliceRoute(route, 1, exitPointIndex)
        local indoorRoute = buildContinuousRoute(indoorRaw, INDOOR_CORNER_CUT)

        startContinuousRoute(indoorRoute)

        if not waitForContinuousRoute(indoorRoute, u8:decode("Интерьер")) then
            running = false
            restorePlayer()
            return
        end

        clearMovement()
        restoreVehicleEvents()
        wait(250)

        if not waitForExterior(route[exitPointIndex + 1]) then
            running = false
            restorePlayer()
            return
        end

        if not running then
            restorePlayer()
            return
        end

        local outdoorRaw = sliceRoute(route, exitPointIndex + 1, #route)
        local outdoorRoute = buildContinuousRoute(outdoorRaw, OUTDOOR_CORNER_CUT)

        startContinuousRoute(outdoorRoute)

        if not waitForContinuousRoute(outdoorRoute, u8:decode("Улица")) then
            running = false
            restorePlayer()
            return
        end
    else
        local continuousRoute = buildContinuousRoute(route, currentInterior == 0 and OUTDOOR_CORNER_CUT or INDOOR_CORNER_CUT)
        local routeLabel = currentInterior == 0 and u8:decode("Улица") or u8:decode("Маршрут")

        startContinuousRoute(continuousRoute)

        if not waitForContinuousRoute(continuousRoute, routeLabel) then
            running = false
            restorePlayer()
            return
        end
    end

    running = false
    restorePlayer()
    routeRecorder.notify(u8:decode("Маршрут полностью завершён."), 0x55FF55)

    if AUTO_RECONNECT_AFTER_FINISH then
        reconnectFromFinalPoint()
    end
end

local function startRoute()
    if running then
        routeRecorder.notify(u8:decode("Маршрут уже запущен."), 0xFFFFAA)
        return
    end

    if routeRecorder.active then
        routeRecorder.stop(true)
    end

    routeRecorder.ensureLoaded()

    if #routeRecorder.points < 2 then
        routeRecorder.notify(u8:decode("Нужно записать минимум две точки."), 0xFF5555)
        return
    end

    running = true
    runnerThread = lua_thread.create(function()
        local ok, routeError = xpcall(runRoute, debug.traceback)
        if not ok then
            running = false
            pcall(restorePlayer)
            pcall(routeRecorder.notify, "BuyRoute runtime error: " .. tostring(routeError), 0xFF5555)
        end
        runnerThread = nil
    end)
end

local function stopRoute()
    running = false
    restorePlayer()
    routeRecorder.notify(u8:decode("Маршрут остановлен."), 0xFFAA55)
end
local function buyRouteHandleSpawnDialog(id, style, title, button1, button2, dialogText)
    if not hasLastExitFlag() then
        return
    end

    -- В этом скрипте encoding.default = CP1251.
    -- Поэтому входящую SA-MP CP1251 строку переводим в UTF-8 через
    -- UTF8:encode(), а НЕ через CP1251:decode().
    local decodedTitle = title
    local decodedText = dialogText

    local okTitle, utfTitle = pcall(function()
        return u8:encode(title)
    end)

    if okTitle and utfTitle then
        decodedTitle = utfTitle
    end

    local okText, utfText = pcall(function()
        return u8:encode(dialogText)
    end)

    if okText and utfText then
        decodedText = utfText
    end

    if style ~= 2 then
        return
    end

    if not tostring(decodedTitle):find("Выбор места спавна", 1, true) then
        return
    end

    if spawnDialogSelectionScheduled then
        return
    end

    spawnDialogSelectionScheduled = true

    lua_thread.create(function(dialogId)
        msg("Меню спавна найдено. Жду 3 секунды.", 0xFFFFAA)

        wait(SPAWN_SELECT_DELAY_MS)

        if not hasLastExitFlag() then
            spawnDialogSelectionScheduled = false
            return
        end

        -- Не отправляем ответ, если уже открыт другой диалог.
        if type(sampIsDialogActive) == "function" and not sampIsDialogActive() then
            spawnDialogSelectionScheduled = false
            return
        end

        if type(sampGetCurrentDialogId) == "function" then
            local currentId = sampGetCurrentDialogId()

            if currentId ~= dialogId then
                spawnDialogSelectionScheduled = false
                return
            end
        end

        -- РОВНО тот способ, которым работает AutoSelectSpawnV4:
        -- первая строка listbox = индекс 0.
        sampSendDialogResponse(dialogId, 1, 0, "")

        clearLastExitFlag()
        spawnDialogSelectionScheduled = false

        msg("Первый пункт спавна выбран через sampSendDialogResponse.", 0x55FF55)
    end, id)
end


function M.init(ctx)
    context = type(ctx) == "table" and ctx or {}
    refreshPaths()
    return true
end

function M.start()
    return startRoute()
end

function M.stop(silent)
    return stopRoute(silent)
end

function M.isRunning()
    return running == true
end

function M.isRecording()
    return routeRecorder.active == true
end

function M.startRecording()
    return routeRecorder.start()
end

function M.stopRecording(silent)
    return routeRecorder.stop(silent == true)
end

function M.clearPoints()
    return routeRecorder.clear()
end

function M.getPointCount()
    return routeRecorder.getCount()
end

function M.handleDialog(dialogId, style, title, button1, button2, dialogText)
    return buyRouteHandleSpawnDialog(dialogId, style, title, button1, button2, dialogText)
end

function M.cleanup()
    local routeHadControl = running == true or runnerThread ~= nil or vehicleEventsIgnored == true
    running = false
    routeRecorder.stop(true)
    if routeHadControl then
        restorePlayer(true)
    end
    return true
end

return M
