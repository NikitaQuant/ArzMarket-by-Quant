local M = {
    api_version = 1,
    id = "arz_html_ui",
    title = "HTML",
    section = "Интерфейс",
    order = 999,
    no_scroll = true
}

local ctx
local acef
local server
local port
local running = false
local htmlOpen = false
local clients = {}
local token = ""
local htmlRoot = ""
local revision = { buy = 1, sell = 1 }
local fingerprints = { buy = "", sell = "" }
local lastInjectCheck = 0
local globalDecodeJson = decodeJson
local globalEncodeJson = encodeJson

local function log(text)
    print("[ArzMarket HTML] " .. tostring(text))
end

local function gameTime()
    if type(getGameTimer) == "function" then
        local ok, value = pcall(getGameTimer)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return math.floor(os.clock() * 1000)
end

local function makeToken()
    local out = {}
    for i = 1, 8 do out[i] = string.format("%08x", math.random(0, 0x7fffffff)) end
    return table.concat(out)
end

local function encode(value)
    if type(globalEncodeJson) == "function" then
        local ok, result = pcall(globalEncodeJson, value)
        if ok and type(result) == "string" then return result end
    end
    return "{}"
end

local function decode(value)
    if type(globalDecodeJson) == "function" then
        local ok, result = pcall(globalDecodeJson, value)
        if ok then return result end
    end
end

local function toUtf8(value)
    value = tostring(value or "")
    if ctx and ctx.u8 and type(ctx.u8.encode) == "function" then
        local ok, result = pcall(function() return ctx.u8:encode(value) end)
        if ok and type(result) == "string" then return result end
    end
    return value
end

local function fromUtf8(value)
    value = tostring(value or "")
    if ctx and ctx.u8 and type(ctx.u8.decode) == "function" then
        local ok, result = pcall(function() return ctx.u8:decode(value) end)
        if ok and type(result) == "string" then return result end
    end
    return value
end

local function number(value, fallback)
    local n = tonumber(value)
    if not n or n ~= n or n == math.huge or n == -math.huge then return fallback end
    return n
end

local function normalizeConfig(name)
    name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" or name:find("[/\\]") or name:find("..", 1, true) then return "" end
    if not name:match("%.json$") then name = name .. ".json" end
    return name
end

local function lists()
    local buy = ctx and type(ctx.getBuyList) == "function" and ctx.getBuyList() or {}
    local sell = ctx and type(ctx.getSellList) == "function" and ctx.getSellList() or {}
    if type(buy) ~= "table" then buy = {} end
    if type(sell) ~= "table" then sell = {} end
    return buy, sell
end

local function configName(side)
    if not ctx or type(ctx.getLoadedConfigs) ~= "function" then return "" end
    local sell, buy = ctx.getLoadedConfigs()
    return normalizeConfig(side == "buy" and buy or sell)
end

local function persist(side)
    local buy, sell = lists()
    local list = side == "buy" and buy or sell
    local name = configName(side)
    if name == "" then return false, "config_not_loaded" end
    if type(createConfig) == "function" then
        local ok, result = pcall(createConfig, side .. "-cfg/" .. name, list, side .. "-cfg", name)
        if ok and result ~= false then return true end
    end
    return false, "save_failed"
end

local function itemDto(item, index, side)
    local id = item.item_id or item.foreign_item_id or item.id
    return {
        identity = { index = index, name = toUtf8(item.name or item.item or ""), item_id = id, slot_id = item.slot_id },
        name = toUtf8(item.name or item.item or ("Item #" .. tostring(index))),
        item_id = id,
        price = number(item.price, 0),
        price_vc = number(item.price_vc, 0),
        count = number(item.count, 0),
        continue = number(item.continue, 0),
        enabled = item.enabled ~= false,
        maximum = item.maximum == true,
        count_maximum = number(item.count_maximum, 0),
        all_count = number(item.all_count, 0),
        slot_count = number(item.slot_count, 0),
        slot_id = item.slot_id,
        side = side
    }
end

local function fingerprint(side, list)
    local out = { side, tostring(#list) }
    for i = 1, #list do
        local item = list[i]
        out[#out + 1] = table.concat({
            tostring(item.name or item.item or ""), tostring(item.price or ""), tostring(item.price_vc or ""),
            tostring(item.count or ""), tostring(item.continue or ""), tostring(item.enabled ~= false),
            tostring(item.maximum == true), tostring(item.all_count or ""), tostring(item.slot_id or "")
        }, "\30")
    end
    return table.concat(out, "\31")
end

local function updateRevision(side, list)
    local value = fingerprint(side, list)
    if value ~= fingerprints[side] then
        fingerprints[side] = value
        revision[side] = revision[side] + 1
    end
end

local function sources(side)
    if not ctx or type(ctx.readJsonFile) ~= "function" then return {} end
    local path = side == "buy" and "moonloader/ArzMarket/buy.json" or "moonloader/ArzMarket/sell.json"
    local ok, raw = pcall(ctx.readJsonFile, path)
    if not ok or type(raw) ~= "table" then return {} end
    local out = {}
    for i = 1, #raw do
        local item = raw[i]
        if side == "buy" and type(item) == "string" then
            out[#out + 1] = { index = i, name = toUtf8(item) }
        elseif side == "sell" and type(item) == "table" then
            out[#out + 1] = {
                index = i,
                name = toUtf8(item.item or item.name or ("Item #" .. tostring(i))),
                all_count = number(item.all_count, number(item.count, 0)),
                slot_count = number(item.count, 0),
                slot_id = item.slot_id,
                item_id = item.item_id or item.foreign_item_id or item.id
            }
        end
    end
    return out
end

local function automation(side)
    if type(tradeAutomation) == "table" then return tradeAutomation[side] == true end
    return false
end

local function stateFor(page)
    page = page == "sell" and "sell" or "buy"
    local buy, sell = lists()
    local list = page == "buy" and buy or sell
    updateRevision(page, list)
    local items = {}
    for i = 1, #list do items[i] = itemDto(list[i], i, page) end
    local address, serverPort = "", 0
    if type(sampGetCurrentServerAddress) == "function" then
        local ok, a, p = pcall(sampGetCurrentServerAddress)
        if ok then address, serverPort = tostring(a or ""), tonumber(p) or 0 end
    end
    local cfg = configName(page)
    return {
        revision = revision[page],
        page = page,
        common = {
            uiMode = "html",
            activeConfig = cfg ~= "" and cfg:gsub("%.json$", "") or "",
            automation = automation(page),
            serverAddress = address,
            serverPort = serverPort
        },
        data = { items = items, source = sources(page) }
    }
end

local function findItem(side, identity)
    if type(identity) ~= "table" then return nil, nil, "identity_missing" end
    local buy, sell = lists()
    local list = side == "buy" and buy or sell
    local index = math.floor(number(identity.index, 0) or 0)
    if index < 1 or index > #list then return nil, nil, "stale_state" end
    local item = list[index]
    if tostring(identity.name or "") ~= "" and toUtf8(item.name or item.item or "") ~= tostring(identity.name) then
        return nil, nil, "stale_state"
    end
    if identity.slot_id ~= nil and item.slot_id ~= nil and tostring(identity.slot_id) ~= tostring(item.slot_id) then
        return nil, nil, "stale_state"
    end
    return item, index
end

local numeric = { price=true, price_vc=true, count=true, continue=true, count_maximum=true }
local boolean = { enabled=true, maximum=true }

local function updateItem(side, payload)
    local item, _, err = findItem(side, payload.identity)
    if not item then return false, err end
    local patch = type(payload.patch) == "table" and payload.patch or {}
    for key, value in pairs(patch) do
        if numeric[key] then
            local n = number(value)
            if not n or n < 0 or n > 2147483647 then return false, "invalid_" .. key end
            if key == "count" or key == "continue" or key == "count_maximum" then n = math.floor(n) end
            item[key] = n
        elseif boolean[key] then
            if type(value) ~= "boolean" then return false, "invalid_" .. key end
            item[key] = value
        else
            return false, "field_not_allowed"
        end
    end
    local ok, saveErr = persist(side)
    fingerprints[side] = ""
    return ok, saveErr
end

local function removeItem(side, payload)
    local _, index, err = findItem(side, payload.identity)
    if not index then return false, err end
    local buy, sell = lists()
    table.remove(side == "buy" and buy or sell, index)
    if type(tradeFilterInvalidate) == "function" then pcall(tradeFilterInvalidate, side) end
    local ok, saveErr = persist(side)
    fingerprints[side] = ""
    return ok, saveErr
end

local function addItem(side, payload)
    local source = sources(side)
    local sourceIndex = math.floor(number(payload.source_index, 0) or 0)
    local src
    for i = 1, #source do if tonumber(source[i].index) == sourceIndex then src = source[i] break end end
    if not src then return false, "source_not_found" end
    local buy, sell = lists()
    local list = side == "buy" and buy or sell
    local luaName = fromUtf8(src.name)
    for i = 1, #list do
        if tostring(list[i].name or list[i].item or "") == luaName then return false, "already_exists" end
    end
    local item
    if side == "buy" then
        item = { continue=1, enabled=true, maximum=false, count_maximum=0, price_vc=10, name=luaName, price=10, count=1 }
    else
        item = {
            enabled=true, price_vc=9, maximum=true, name=luaName, price=9, count=1,
            slot_count=src.slot_count, slot_id=src.slot_id, all_count=src.all_count, item_id=src.item_id
        }
    end
    if type(addToData) == "function" then pcall(addToData, item, list, nil) else table.insert(list, item) end
    if type(tradeFilterMarkNewItem) == "function" then pcall(tradeFilterMarkNewItem, side, item) end
    if type(tradeFilterInvalidate) == "function" then pcall(tradeFilterInvalidate, side) end
    local ok, saveErr = persist(side)
    fingerprints[side] = ""
    return ok, saveErr
end

local function setCefCursor(toggle)
    pcall(function()
        local bs = raknetNewBitStream()
        raknetBitStreamWriteInt8(bs, 25)
        raknetBitStreamWriteInt32(bs, 0)
        raknetBitStreamWriteInt8(bs, toggle and 128 or 0)
        raknetBitStreamWriteInt16(bs, 0)
        raknetEmulPacketReceiveBitStream(220, bs)
        raknetDeleteBitStream(bs)
    end)
    pcall(function()
        if sampSetCursorMode then
            if toggle then sampSetCursorMode(2); sampSetCursorMode(1) else sampSetCursorMode(0) end
        end
    end)
    pcall(function() if sampToggleCursor then sampToggleCursor(toggle) end end)
    pcall(function() if sampShowCursor then sampShowCursor(toggle) end end)
    pcall(function() if showCursor then showCursor(toggle) end end)
end

local function quoteJs(value)
    return string.format("%q", tostring(value or "")):gsub("\r", "\\r"):gsub("\n", "\\n")
end

local function removeIframe()
    if acef and type(acef.eval) == "function" then
        pcall(acef.eval, "var f=document.getElementById('arzmarket-html-frame');if(f)f.remove();")
    end
    htmlOpen = false
    setCefCursor(false)
end

local function injectIframe()
    if not acef or type(acef.eval) ~= "function" or not port then return false end
    local url = "http://127.0.0.1:" .. tostring(port) .. "/ui"
    local code = "var o=document.getElementById('arzmarket-html-frame');if(o)o.remove();"
        .. "var f=document.createElement('iframe');f.id='arzmarket-html-frame';f.src=" .. quoteJs(url) .. ";"
        .. "f.style.position='fixed';f.style.left='0';f.style.top='0';f.style.width='100vw';f.style.height='100vh';"
        .. "f.style.border='0';f.style.background='transparent';f.style.zIndex='2147483000';document.body.appendChild(f);"
    local ok = pcall(acef.eval, code)
    if ok then htmlOpen = true; setCefCursor(true); lastInjectCheck = gameTime() end
    return ok
end

local function ensureIframe()
    if not htmlOpen or not acef or gameTime() - lastInjectCheck < 1500 then return end
    lastInjectCheck = gameTime()
    local url = "http://127.0.0.1:" .. tostring(port) .. "/ui"
    pcall(acef.eval, "if(!document.getElementById('arzmarket-html-frame')){var f=document.createElement('iframe');f.id='arzmarket-html-frame';f.src=" .. quoteJs(url) .. ";f.style.position='fixed';f.style.left='0';f.style.top='0';f.style.width='100vw';f.style.height='100vh';f.style.border='0';f.style.zIndex='2147483000';document.body.appendChild(f);}")
end

local function readFile(path, binary)
    local f = io.open(path, binary and "rb" or "r")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

local mime = { html="text/html; charset=utf-8", css="text/css; charset=utf-8", js="application/javascript; charset=utf-8", svg="image/svg+xml", webp="image/webp" }

local function response(status, body, contentType)
    local reasons = {[200]="OK",[204]="No Content",[400]="Bad Request",[403]="Forbidden",[404]="Not Found",[405]="Method Not Allowed",[409]="Conflict",[413]="Payload Too Large",[500]="Internal Server Error"}
    body = body or ""
    return table.concat({
        "HTTP/1.1 " .. tostring(status) .. " " .. (reasons[status] or "Error"),
        "Content-Type: " .. (contentType or "text/plain; charset=utf-8"),
        "Content-Length: " .. tostring(#body),
        "Connection: close",
        "Cache-Control: no-store",
        "X-Content-Type-Options: nosniff",
        "Referrer-Policy: no-referrer",
        "Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data: file:; connect-src 'self'; object-src 'none'; frame-ancestors *"
    }, "\r\n") .. "\r\n\r\n" .. body
end

local function jsonResponse(status, value)
    return response(status, encode(value), "application/json; charset=utf-8")
end

local function queryString(value)
    local result = {}
    for pair in tostring(value or ""):gmatch("[^&]+") do
        local key, item = pair:match("^([^=]+)=?(.*)$")
        if key then result[key] = item end
    end
    return result
end

local function parseRequest(buffer)
    local split = buffer:find("\r\n\r\n", 1, true)
    if not split then return nil, #buffer > 16384 and "headers_too_large" or "incomplete" end
    local head = buffer:sub(1, split - 1)
    local lines = {}
    for line in (head .. "\r\n"):gmatch("(.-)\r\n") do lines[#lines + 1] = line end
    local method, target = tostring(lines[1] or ""):match("^(%u+)%s+([^%s]+)%s+HTTP/%d%.%d$")
    if not method then return nil, "bad_request_line" end
    local headers = {}
    for i = 2, #lines do
        local key, value = lines[i]:match("^([^:]+):%s*(.*)$")
        if not key then return nil, "bad_header" end
        headers[key:lower()] = value
    end
    if headers["transfer-encoding"] then return nil, "transfer_encoding_not_allowed" end
    local size = tonumber(headers["content-length"] or "0") or 0
    if size < 0 or size > 65536 then return nil, "body_too_large" end
    local bodyStart = split + 4
    if #buffer - bodyStart + 1 < size then return nil, "incomplete" end
    local path, query = target:match("^([^?]*)%??(.*)$")
    return { method=method, path=path or "/", query=queryString(query), headers=headers, body=buffer:sub(bodyStart, bodyStart + size - 1) }
end

local function validHost(req)
    local host = tostring(req.headers.host or "")
    return host == "127.0.0.1:" .. tostring(port) or host == "localhost:" .. tostring(port)
end

local function validToken(req)
    return tostring(req.headers["x-arzmarket-token"] or "") == token
end

local function validOrigin(req)
    local origin = tostring(req.headers.origin or "")
    return origin == "http://127.0.0.1:" .. tostring(port) or origin == "http://localhost:" .. tostring(port)
end

local function safeStatic(path)
    if path:find("..", 1, true) or path:find("\\", 1, true) or path:find("%%00") or path:sub(1,1) == "/" then return nil end
    if not path:match("^[%w%._%-%/]+$") then return nil end
    return path
end

local function doAction(req)
    if req.method ~= "POST" then return response(405, "method_not_allowed") end
    if not validToken(req) or not validOrigin(req) then return response(403, "forbidden") end
    local request = decode(req.body)
    if type(request) ~= "table" or type(request.action) ~= "string" then return jsonResponse(400, {ok=false,error="invalid_json"}) end
    local action = request.action
    local data = type(request.payload) == "table" and request.payload or {}
    local side = data.side == "sell" and "sell" or "buy"
    if action == "ui.close" or action == "ui.switch_mode" then removeIframe(); return jsonResponse(200, {ok=true,mode="lua"}) end
    if action == "ui.navigate" then return jsonResponse(200, {ok=true,page=side}) end
    if action == "trade.item.update" then
        local ok, err = updateItem(side, data)
        return jsonResponse(ok and 200 or (err == "stale_state" and 409 or 400), {ok=ok,error=err})
    end
    if action == "trade.item.remove" then
        local ok, err = removeItem(side, data)
        return jsonResponse(ok and 200 or (err == "stale_state" and 409 or 400), {ok=ok,error=err})
    end
    if action == "trade.item.add" then
        local ok, err = addItem(side, data)
        return jsonResponse(ok and 200 or 400, {ok=ok,error=err})
    end
    if action == "buy.average.apply" then
        if type(applyAveragePricesToBuyList) ~= "function" then return jsonResponse(400, {ok=false,error="average_unavailable"}) end
        local ok, result = pcall(applyAveragePricesToBuyList)
        fingerprints.buy = ""
        return jsonResponse(ok and result ~= false and 200 or 400, {ok=ok and result ~= false,error=not ok and tostring(result) or (result == false and "average_failed" or nil)})
    end
    if action == "trade.start" then
        if type(sampProcessChatInput) ~= "function" then return jsonResponse(400, {ok=false,error="chat_input_unavailable"}) end
        local ok, err = pcall(sampProcessChatInput, side == "sell" and "/crsell" or "/crbuy")
        return jsonResponse(ok and 200 or 400, {ok=ok,error=ok and nil or tostring(err)})
    end
    return jsonResponse(400, {ok=false,error="unknown_action"})
end

local function handle(req)
    if not validHost(req) then return response(403, "forbidden") end
    if req.path == "/health" then return jsonResponse(200, {ok=true,port=port,htmlOpen=htmlOpen}) end
    if req.path == "/ui" then
        if req.method ~= "GET" then return response(405, "method_not_allowed") end
        local html = readFile(htmlRoot .. "\\index.html", false)
        if not html then return response(404, "ui_missing") end
        return response(200, html:gsub("__ARZMARKET_TOKEN__", token), mime.html)
    end
    if req.path:sub(1,8) == "/static/" then
        if req.method ~= "GET" then return response(405, "method_not_allowed") end
        local rel = safeStatic(req.path:sub(9))
        if not rel then return response(403, "forbidden") end
        local body = readFile(htmlRoot .. "\\" .. rel:gsub("/", "\\"), true)
        if not body then return response(404, "not_found") end
        return response(200, body, mime[rel:match("%.([%w]+)$") or ""] or "application/octet-stream")
    end
    if req.path == "/api/state" then
        if req.method ~= "GET" then return response(405, "method_not_allowed") end
        if not validToken(req) then return response(403, "forbidden") end
        local page = req.query.page == "sell" and "sell" or "buy"
        local value = stateFor(page)
        if tonumber(req.query.since) == tonumber(value.revision) then return response(204, "", "application/json; charset=utf-8") end
        return jsonResponse(200, value)
    end
    if req.path == "/api/action" then return doAction(req) end
    if req.path:sub(1,10) == "/api/icon/" then return response(404, "icon_fallback_not_ready") end
    return response(404, "not_found")
end

local function closeClient(entry)
    pcall(function() entry.socket:close() end)
    clients[entry] = nil
end

local function service()
    if not server then return end
    local count = 0
    for _ in pairs(clients) do count = count + 1 end
    while count < 4 do
        local client = server:accept()
        if not client then break end
        client:settimeout(0)
        local entry = {socket=client,buffer="",deadline=gameTime()+2000}
        clients[entry] = true
        count = count + 1
    end
    for entry in pairs(clients) do
        local chunk, err, partial = entry.socket:receive(4096)
        local data = chunk or partial
        if data and #data > 0 then entry.buffer = entry.buffer .. data end
        if #entry.buffer > 81920 then
            pcall(function() entry.socket:send(response(413, "too_large")) end)
            closeClient(entry)
        else
            local req, parseErr = parseRequest(entry.buffer)
            if req then
                local ok, result = pcall(handle, req)
                if not ok then log("request failed: " .. tostring(result)); result = response(500, "internal_error") end
                entry.socket:settimeout(0.15)
                pcall(function() entry.socket:send(result) end)
                closeClient(entry)
            elseif parseErr ~= "incomplete" then
                pcall(function() entry.socket:send(response(parseErr == "body_too_large" and 413 or 400, parseErr)) end)
                closeClient(entry)
            elseif gameTime() > entry.deadline or err == "closed" then closeClient(entry) end
        end
    end
end

local function startServer()
    if running then return true end
    local ok, socket = pcall(require, "socket")
    if not ok or type(socket) ~= "table" then return false, "luasocket_missing" end
    local candidates = {0}
    for p = 38460, 38489 do candidates[#candidates + 1] = p end
    for i = 1, #candidates do
        local srv = socket.bind("127.0.0.1", candidates[i])
        if srv then
            srv:settimeout(0)
            local _, actual = srv:getsockname()
            server, port = srv, tonumber(actual) or candidates[i]
            break
        end
    end
    if not server then return false, "port_unavailable" end
    if not ctx or not ctx.lua_thread or type(ctx.lua_thread.create) ~= "function" then server:close(); server=nil; return false, "thread_unavailable" end
    running = true
    ctx.lua_thread.create(function()
        while running do service(); ensureIframe(); ctx.wait(0) end
    end)
    log("bridge listening on 127.0.0.1:" .. tostring(port))
    return true
end

local function stopServer()
    running = false
    for entry in pairs(clients) do closeClient(entry) end
    if server then pcall(function() server:close() end) end
    server, port = nil, nil
end

function M.open_html()
    if not running then
        local ok, err = startServer()
        if not ok then if ctx and ctx.notify then pcall(ctx.notify, "HTML интерфейс недоступен: " .. tostring(err)) end; return false end
    end
    if not acef or type(acef.eval) ~= "function" then
        if ctx and ctx.notify then pcall(ctx.notify, "Не найдена библиотека arizona-events. Lua интерфейс продолжает работать.") end
        return false
    end
    local ok = injectIframe()
    if not ok and ctx and ctx.notify then pcall(ctx.notify, "Не удалось открыть CEF интерфейс. Используйте Lua режим.") end
    return ok
end

function M.init(context)
    ctx = context
    token = makeToken()
    htmlRoot = ctx.getWorkingDirectory() .. "\\ArzMarket\\html"
    local ok, module = pcall(require, "arizona-events")
    if ok and type(module) == "table" and type(module.eval) == "function" then acef = module end
    local started, err = startServer()
    if not started then log("bridge disabled: " .. tostring(err)) end
    return true
end

function M.render(context)
    ctx = context or ctx
    local imgui = ctx.imgui
    local fonts = type(ctx.getFonts) == "function" and ctx.getFonts() or {}
    if fonts[20] then imgui.PushFont(fonts[20]) end
    imgui.Text("HTML интерфейс ArzMarket")
    if fonts[20] then imgui.PopFont() end
    imgui.Spacing()
    imgui.TextWrapped("Скупка и Продажа используют текущий Lua core. Старый интерфейс остается доступен.")
    imgui.Spacing()
    if not acef then
        imgui.TextColored(imgui.ImVec4(1,0.35,0.35,1), "arizona-events не найден. Доступен Lua режим.")
        return
    end
    if not running then
        imgui.TextColored(imgui.ImVec4(1,0.35,0.35,1), "Local bridge не запущен.")
        if imgui.Button("Повторить запуск", imgui.ImVec2(220,34)) then startServer() end
        return
    end
    imgui.Text("Bridge: 127.0.0.1:" .. tostring(port or 0))
    imgui.Spacing()
    if imgui.Button(htmlOpen and "HTML уже открыт" or "Открыть HTML", imgui.ImVec2(260,38)) and not htmlOpen then M.open_html() end
    if htmlOpen then imgui.SameLine(); if imgui.Button("Вернуться в Lua", imgui.ImVec2(180,38)) then removeIframe() end end
end

function M.shutdown()
    removeIframe()
    stopServer()
    return true
end

return M
