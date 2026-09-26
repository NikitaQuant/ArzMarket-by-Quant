local M = {
    api_version = 1,
    module_version = 79,
    id = "arz_html_ui",
    title = "HTML",
    section = "Интерфейс",
    order = 999,
    no_scroll = true
}
M._cefNativeInputOwned = false
M._lastGameUiInputBlocked = false

local ctx, acef, server, port, itemIcons
local socketApi = nil
M._socketBackend = "none"
M._cefBackend = "none"
M._cefBackendError = nil
local running, htmlOpen, suppressAutoOpen = false, false, false
local previewOpen, previewSignature = false, ""
local htmlTemporaryMode = false
local cefCursorOwned = false
local cursorWasActiveBeforeHtml = false
local clients, token, htmlRoot, currentPage, currentSettingsSection = {}, "", "", "buy", nil
local requestQueue = {}
local requestWorkerRunning = false
local serverGeneration = 0
local serviceBusy = false
local lastServiceErrorAt = 0
local htmlWindowStatePath, htmlWindowState = nil, {}
local HTML_LAYOUT_VERSION = 16
local revision, fingerprints = { buy = 1, sell = 1, settings = 1, logs = 1, marketplace = 1, storage = 1, mods = 1 }, { buy = "", sell = "", settings = "", logs = "", marketplace = "", storage = "", mods = "" }
local lastInjectCheck = 0
local htmlSessionGeneration = 0
local lastHtmlInputReclaim = 0
local htmlCompatFocused = false
local htmlCompatLastMouseInside = false
local htmlCompatLastX, htmlCompatLastY = nil, nil
local htmlCompatButtons = {false,false,false}
local htmlCompatLastWheelEventAt = 0
local htmlCompatLastMoveAt = 0
local lastMenuAutoOpenAttempt = 0
local sourceCache = { buy = {at=0,data={},fingerprint="0"}, sell = {at=0,data={},fingerprint="0"} }
local utf8ValueCache = {}
local stateResponseCache = {}
local lastForegroundState = nil
local foregroundStableSince = 0
local FOCUS_STABILIZE_MS = 1500
local settingsSnapshotCache = { at = 0, data = nil }
local tradeDraftHydrated = { buy = false, sell = false }
local tradeDraftPaths = {
    buy = "moonloader/ArzMarket/html_draft_buy.json",
    sell = "moonloader/ArzMarket/html_draft_sell.json"
}
local globalDecodeJson, globalEncodeJson = decodeJson, encodeJson
local lastServiceAt = 0

local function log(v) print("[ArzMarket HTML] " .. tostring(v)) end

-- The HTML bridge runs inside a MoonLoader lua_thread. In this runtime an
-- xpcall frame around a request that later yields can leave the scheduler
-- trying to resume a coroutine that is no longer suspended. Keep traceback
-- formatting for ordinary errors, but use pcall on the yield-capable request
-- path. xpcall is only used below for init-only code that never yields.
local function bridgeTraceback(err)
    local message=tostring(err or "unknown_error")
    if debug and type(debug.traceback)=="function" then return debug.traceback(message,2) end
    return message
end
local function callCore(fn, ...)
    if type(fn) ~= "function" then return false, "function_unavailable" end
    return pcall(fn,...)
end
local function nowMs()
    if type(getGameTimer) == "function" then
        local ok,v = pcall(getGameTimer)
        if ok and tonumber(v) then return tonumber(v) end
    end
    return math.floor(os.clock()*1000)
end
local function gameWindowForeground()
    if type(isGameWindowForeground) ~= "function" then return true end
    local ok,value = pcall(isGameWindowForeground)
    if not ok then return true end
    return value == true
end
local function focusIsStable()
    local now = nowMs()
    local foreground = gameWindowForeground()
    if lastForegroundState == nil then
        lastForegroundState = foreground
        foregroundStableSince = now
    elseif foreground ~= lastForegroundState then
        lastForegroundState = foreground
        foregroundStableSince = now
    end
    if not foreground then return false end
    return now - foregroundStableSince >= FOCUS_STABILIZE_MS
end
local bridgePerf = {
    startedAt=nowMs(), luaToHtmlRequests=0, luaToHtmlResponses=0,
    htmlToLuaMessages=0, jsonEncode=0, jsonDecode=0,
    stateBuilds=0, totalStateBuildMs=0, maxStateBuildMs=0
}
local function encode(v)
    bridgePerf.jsonEncode=bridgePerf.jsonEncode+1
    if type(globalEncodeJson)=="function" then
        local ok,out=pcall(globalEncodeJson,v)
        if ok and type(out)=="string" then return out end
    end
    return "{}"
end
local function decode(v)
    bridgePerf.jsonDecode=bridgePerf.jsonDecode+1
    if type(globalDecodeJson)=="function" then
        local ok,out=pcall(globalDecodeJson,v)
        if ok then return out end
    end
end
local CP1251_TO_UNICODE = {
    [0x80] = 0x0402,
    [0x81] = 0x0403,
    [0x82] = 0x201A,
    [0x83] = 0x0453,
    [0x84] = 0x201E,
    [0x85] = 0x2026,
    [0x86] = 0x2020,
    [0x87] = 0x2021,
    [0x88] = 0x20AC,
    [0x89] = 0x2030,
    [0x8A] = 0x0409,
    [0x8B] = 0x2039,
    [0x8C] = 0x040A,
    [0x8D] = 0x040C,
    [0x8E] = 0x040B,
    [0x8F] = 0x040F,
    [0x90] = 0x0452,
    [0x91] = 0x2018,
    [0x92] = 0x2019,
    [0x93] = 0x201C,
    [0x94] = 0x201D,
    [0x95] = 0x2022,
    [0x96] = 0x2013,
    [0x97] = 0x2014,
    [0x99] = 0x2122,
    [0x9A] = 0x0459,
    [0x9B] = 0x203A,
    [0x9C] = 0x045A,
    [0x9D] = 0x045C,
    [0x9E] = 0x045B,
    [0x9F] = 0x045F,
    [0xA0] = 0x00A0,
    [0xA1] = 0x040E,
    [0xA2] = 0x045E,
    [0xA3] = 0x0408,
    [0xA4] = 0x00A4,
    [0xA5] = 0x0490,
    [0xA6] = 0x00A6,
    [0xA7] = 0x00A7,
    [0xA8] = 0x0401,
    [0xA9] = 0x00A9,
    [0xAA] = 0x0404,
    [0xAB] = 0x00AB,
    [0xAC] = 0x00AC,
    [0xAD] = 0x00AD,
    [0xAE] = 0x00AE,
    [0xAF] = 0x0407,
    [0xB0] = 0x00B0,
    [0xB1] = 0x00B1,
    [0xB2] = 0x0406,
    [0xB3] = 0x0456,
    [0xB4] = 0x0491,
    [0xB5] = 0x00B5,
    [0xB6] = 0x00B6,
    [0xB7] = 0x00B7,
    [0xB8] = 0x0451,
    [0xB9] = 0x2116,
    [0xBA] = 0x0454,
    [0xBB] = 0x00BB,
    [0xBC] = 0x0458,
    [0xBD] = 0x0405,
    [0xBE] = 0x0455,
    [0xBF] = 0x0457,
    [0xC0] = 0x0410,
    [0xC1] = 0x0411,
    [0xC2] = 0x0412,
    [0xC3] = 0x0413,
    [0xC4] = 0x0414,
    [0xC5] = 0x0415,
    [0xC6] = 0x0416,
    [0xC7] = 0x0417,
    [0xC8] = 0x0418,
    [0xC9] = 0x0419,
    [0xCA] = 0x041A,
    [0xCB] = 0x041B,
    [0xCC] = 0x041C,
    [0xCD] = 0x041D,
    [0xCE] = 0x041E,
    [0xCF] = 0x041F,
    [0xD0] = 0x0420,
    [0xD1] = 0x0421,
    [0xD2] = 0x0422,
    [0xD3] = 0x0423,
    [0xD4] = 0x0424,
    [0xD5] = 0x0425,
    [0xD6] = 0x0426,
    [0xD7] = 0x0427,
    [0xD8] = 0x0428,
    [0xD9] = 0x0429,
    [0xDA] = 0x042A,
    [0xDB] = 0x042B,
    [0xDC] = 0x042C,
    [0xDD] = 0x042D,
    [0xDE] = 0x042E,
    [0xDF] = 0x042F,
    [0xE0] = 0x0430,
    [0xE1] = 0x0431,
    [0xE2] = 0x0432,
    [0xE3] = 0x0433,
    [0xE4] = 0x0434,
    [0xE5] = 0x0435,
    [0xE6] = 0x0436,
    [0xE7] = 0x0437,
    [0xE8] = 0x0438,
    [0xE9] = 0x0439,
    [0xEA] = 0x043A,
    [0xEB] = 0x043B,
    [0xEC] = 0x043C,
    [0xED] = 0x043D,
    [0xEE] = 0x043E,
    [0xEF] = 0x043F,
    [0xF0] = 0x0440,
    [0xF1] = 0x0441,
    [0xF2] = 0x0442,
    [0xF3] = 0x0443,
    [0xF4] = 0x0444,
    [0xF5] = 0x0445,
    [0xF6] = 0x0446,
    [0xF7] = 0x0447,
    [0xF8] = 0x0448,
    [0xF9] = 0x0449,
    [0xFA] = 0x044A,
    [0xFB] = 0x044B,
    [0xFC] = 0x044C,
    [0xFD] = 0x044D,
    [0xFE] = 0x044E,
    [0xFF] = 0x044F,
}
local UNICODE_TO_CP1251 = {}
for byteValue, codepoint in pairs(CP1251_TO_UNICODE) do
    UNICODE_TO_CP1251[codepoint] = byteValue
end

local function utf8FromCodepoint(cp)
    cp = tonumber(cp) or 0x3F
    if cp <= 0x7F then
        return string.char(cp)
    elseif cp <= 0x7FF then
        return string.char(
            0xC0 + math.floor(cp / 0x40),
            0x80 + (cp % 0x40)
        )
    elseif cp <= 0xFFFF then
        return string.char(
            0xE0 + math.floor(cp / 0x1000),
            0x80 + (math.floor(cp / 0x40) % 0x40),
            0x80 + (cp % 0x40)
        )
    elseif cp <= 0x10FFFF then
        return string.char(
            0xF0 + math.floor(cp / 0x40000),
            0x80 + (math.floor(cp / 0x1000) % 0x40),
            0x80 + (math.floor(cp / 0x40) % 0x40),
            0x80 + (cp % 0x40)
        )
    end
    return "?"
end

local function utf8CodepointAt(value, index)
    local b1 = value:byte(index)
    if not b1 then return nil, index + 1 end
    if b1 < 0x80 then return b1, index + 1 end

    local b2 = value:byte(index + 1)
    if b1 >= 0xC2 and b1 <= 0xDF and b2 and b2 >= 0x80 and b2 <= 0xBF then
        return (b1 - 0xC0) * 0x40 + (b2 - 0x80), index + 2
    end

    local b3 = value:byte(index + 2)
    if b1 >= 0xE0 and b1 <= 0xEF and b2 and b3 and b2 >= 0x80 and b2 <= 0xBF and b3 >= 0x80 and b3 <= 0xBF then
        if (b1 ~= 0xE0 or b2 >= 0xA0) and (b1 ~= 0xED or b2 <= 0x9F) then
            return (b1 - 0xE0) * 0x1000 + (b2 - 0x80) * 0x40 + (b3 - 0x80), index + 3
        end
    end

    local b4 = value:byte(index + 3)
    if b1 >= 0xF0 and b1 <= 0xF4 and b2 and b3 and b4
        and b2 >= 0x80 and b2 <= 0xBF
        and b3 >= 0x80 and b3 <= 0xBF
        and b4 >= 0x80 and b4 <= 0xBF then
        if (b1 ~= 0xF0 or b2 >= 0x90) and (b1 ~= 0xF4 or b2 <= 0x8F) then
            return (b1 - 0xF0) * 0x40000 + (b2 - 0x80) * 0x1000 + (b3 - 0x80) * 0x40 + (b4 - 0x80), index + 4
        end
    end

    return nil, index + 1
end

local function toUtf8(v)
    local valueType = type(v)
    local value
    if valueType == "string" then
        value = v
    elseif valueType == "number" or valueType == "boolean" then
        value = tostring(v)
    elseif v == nil then
        value = ""
    else
        -- Never invoke __tostring on userdata/cdata/thread values from the HTTP worker.
        return ""
    end
    if value == "" then return value end
    local cached = utf8ValueCache[value]
    if cached ~= nil then return cached end
    local out = {}
    for i = 1, #value do
        local byteValue = string.byte(value, i)
        if byteValue < 0x80 then
            out[#out + 1] = string.char(byteValue)
        else
            local codepoint = CP1251_TO_UNICODE[byteValue]
            out[#out + 1] = codepoint and utf8FromCodepoint(codepoint) or "?"
        end
    end
    local converted = table.concat(out)
    if #utf8ValueCache < 4096 then utf8ValueCache[value] = converted end
    return converted
end

local function fromUtf8(v)
    local value = tostring(v or "")
    if value == "" then return value end
    local out = {}
    local index = 1
    while index <= #value do
        local first = value:byte(index)
        if first and first < 0x80 then
            out[#out + 1] = string.char(first)
            index = index + 1
        else
            local codepoint, nextIndex = utf8CodepointAt(value, index)
            if codepoint then
                local byteValue = UNICODE_TO_CP1251[codepoint]
                out[#out + 1] = byteValue and string.char(byteValue) or "?"
                index = nextIndex
            else
                out[#out + 1] = "?"
                index = index + 1
            end
        end
    end
    return table.concat(out)
end
local function utf8Tree(value,depth)
    depth=(tonumber(depth) or 0)+1
    if depth>8 then return nil end
    local valueType=type(value)
    if valueType=="string" then return toUtf8(value) end
    if valueType~="table" then return value end
    local out={}
    for key,item in pairs(value) do
        local outKey=type(key)=="string" and toUtf8(key) or key
        out[outKey]=utf8Tree(item,depth)
    end
    return out
end
local function saneNumber(v,fallback)
    local n=tonumber(v)
    if not n or n~=n or n==math.huge or n==-math.huge then return fallback end
    return n
end
local function makeToken()
    local out={}
    for i=1,8 do out[i]=string.format("%08x",math.random(0,0x7fffffff)) end
    return table.concat(out)
end
local function currentMenuScalePercent()
    if ctx and type(ctx.getMenuScalePercent)=="function" then
        local ok,value=callCore(ctx.getMenuScalePercent)
        if ok then
            local number=saneNumber(value,100) or 100
            return math.max(100,math.min(150,math.floor(number+0.5)))
        end
    end
    return 100
end

local function sanitizeWindowState(value)
    if type(value)~="table" then return nil end
    local x=saneNumber(value.x)
    local y=saneNumber(value.y)
    local width=saneNumber(value.width)
    local height=saneNumber(value.height)
    local viewportWidth=saneNumber(value.viewportWidth)
    local viewportHeight=saneNumber(value.viewportHeight)
    local baseX=saneNumber(value.baseX)
    local baseY=saneNumber(value.baseY)
    local baseWidth=saneNumber(value.baseWidth)
    local baseHeight=saneNumber(value.baseHeight)
    local scalePercent=saneNumber(value.scalePercent)
    local minimalMode=value.minimalMode==true
    if value.minimalMode==nil and type(htmlWindowState)=="table" then minimalMode=htmlWindowState.minimalMode==true end
    if not x or not y or not width or not height then return nil end
    x=math.floor(x+0.5); y=math.floor(y+0.5)
    width=math.floor(width+0.5); height=math.floor(height+0.5)
    if x < -20000 or x > 20000 or y < -20000 or y > 20000 then return nil end
    if width < 640 or width > 10000 or height < 420 or height > 10000 then return nil end
    local out={x=x,y=y,width=width,height=height,version=HTML_LAYOUT_VERSION,minimalMode=minimalMode}
    if viewportWidth and viewportHeight and viewportWidth>=320 and viewportWidth<=20000 and viewportHeight>=240 and viewportHeight<=20000 then
        out.viewportWidth=math.floor(viewportWidth+0.5)
        out.viewportHeight=math.floor(viewportHeight+0.5)
    end
    if baseX and baseY and baseWidth and baseHeight
        and baseX>=-20000 and baseX<=20000 and baseY>=-20000 and baseY<=20000
        and baseWidth>=320 and baseWidth<=10000 and baseHeight>=240 and baseHeight<=10000 then
        out.baseX=baseX
        out.baseY=baseY
        out.baseWidth=baseWidth
        out.baseHeight=baseHeight
    end
    if scalePercent then
        out.scalePercent=math.max(100,math.min(150,math.floor(scalePercent+0.5)))
    end
    return out
end
local function loadWindowState()
    htmlWindowState={}
    if not htmlWindowStatePath then return end
    local f=io.open(htmlWindowStatePath,"r")
    if not f then return end
    local raw=f:read("*a"); f:close()
    local decoded=decode(raw or "")
    if type(decoded)~="table" or tonumber(decoded.version)~=HTML_LAYOUT_VERSION then
        pcall(os.remove,htmlWindowStatePath)
        return
    end
    local clean=sanitizeWindowState(decoded)
    if clean then htmlWindowState=clean end
end
local function saveWindowState(value)
    local clean=sanitizeWindowState(value)
    if not clean then return false,"invalid_window_state" end
    if not htmlWindowStatePath then return false,"window_state_path_missing" end
    local f,err=io.open(htmlWindowStatePath,"w")
    if not f then return false,tostring(err or "open_failed") end
    local ok,writeErr=pcall(function() f:write(encode(clean)); f:flush() end)
    f:close()
    if not ok then return false,tostring(writeErr) end
    htmlWindowState=clean
    return true,clean
end

local function lists()
    local buy=ctx and type(ctx.getBuyList)=="function" and ctx.getBuyList() or {}
    local sell=ctx and type(ctx.getSellList)=="function" and ctx.getSellList() or {}
    if type(buy)~="table" then buy={} end
    if type(sell)~="table" then sell={} end
    return buy,sell
end
local function normalizeConfig(name)
    name=tostring(name or ""):gsub("^%s+",""):gsub("%s+$","")
    if name=="" or name:find("[/\\]") or name:find("..",1,true) then return "" end
    return name:match("%.json$") and name or name..".json"
end
local function configName(side)
    if not ctx or type(ctx.getLoadedConfigs)~="function" then return "" end
    local sell,buy=ctx.getLoadedConfigs()
    return normalizeConfig(side=="buy" and buy or sell)
end
local function configList(side)
    if not ctx or type(ctx.listTradeConfigs)~="function" then return {} end
    local ok,value=callCore(ctx.listTradeConfigs,side)
    if not ok or type(value)~="table" then return {} end
    local out={}
    for i=1,#value do
        local name=normalizeConfig(value[i])
        if name~="" then out[#out+1]=name:gsub("%.json$","") end
    end
    return out
end
local function draftPath(side)
    return tradeDraftPaths[side=="sell" and "sell" or "buy"]
end
local function clearTradeDraft(side)
    side=side=="sell" and "sell" or "buy"
    local path=draftPath(side)
    if path and doesFileExist(path) then pcall(os.remove,path) end
    tradeDraftHydrated[side]=true
    return true
end
local function saveTradeDraft(side,list)
    side=side=="sell" and "sell" or "buy"
    if configName(side)~="" then
        clearTradeDraft(side)
        return true
    end
    if not ctx or type(ctx.writeJsonFile)~="function" then return false,"draft_save_unavailable" end
    list=type(list)=="table" and list or {}
    local ok,result=callCore(ctx.writeJsonFile,list,draftPath(side))
    if not ok or result==false then return false,"draft_save_failed" end
    tradeDraftHydrated[side]=true
    return true
end
local function restoreTradeDraft(side)
    side=side=="sell" and "sell" or "buy"
    if tradeDraftHydrated[side] then return true end
    tradeDraftHydrated[side]=true
    if configName(side)~="" then
        clearTradeDraft(side)
        return true
    end
    local buy,sell=lists()
    local list=side=="buy" and buy or sell
    if #list>0 then
        local ok=saveTradeDraft(side,list)
        return ok~=false
    end
    if not ctx or type(ctx.readJsonFile)~="function" then return true end
    local path=draftPath(side)
    if not path or not doesFileExist(path) then return true end
    local ok,raw=callCore(ctx.readJsonFile,path)
    if not ok or type(raw)~="table" then return true end
    local restored=0
    for i=1,#raw do
        if type(raw[i])=="table" then
            list[#list+1]=raw[i]
            restored=restored+1
        end
    end
    if restored>0 then
        if type(tradeFilterInvalidate)=="function" then pcall(tradeFilterInvalidate,side) end
        fingerprints[side]=""
    end
    return true
end

local autoConfigAttempted={buy=false,sell=false}
local function ensureLoadedConfig(side)
    side=side=="sell" and "sell" or "buy"
    local current=configName(side)
    if current~="" then
        clearTradeDraft(side)
        return current
    end
    -- Never replace an unsaved/draft list by auto-loading some config.
    -- This keeps tutorial-selected items alive across CEF/script reloads.
    local buy,sell=lists()
    local liveList=side=="buy" and buy or sell
    if #liveList>0 then return "" end
    if autoConfigAttempted[side] then return "" end
    autoConfigAttempted[side]=true
    if not ctx or type(ctx.loadTradeConfig)~="function" then return "" end
    local configs=configList(side)
    if #configs==0 then return "" end
    local selected=configs[1]
    for i=1,#configs do
        local normalized=toUtf8(configs[i] or ""):lower()
        if normalized=="основной" or normalized=="main" or normalized=="default" then
            selected=configs[i]
            break
        end
    end
    local ok,result=callCore(ctx.loadTradeConfig,side,selected)
    if not ok or result==false then return "" end
    clearTradeDraft(side)
    return configName(side)
end
local function persist(side)
    local buy,sell=lists()
    local list=side=="buy" and buy or sell
    local name=configName(side)
    -- Without a selected config keep a durable draft instead of RAM-only state.
    -- Baron tutorial progress survives script reloads, so the edited item list must
    -- survive too; otherwise the next tutorial step has no status toggle to point at.
    if name=="" then return saveTradeDraft(side,list) end
    clearTradeDraft(side)
    if type(createConfig)~="function" then return false,"save_unavailable" end
    local ok,result=pcall(createConfig,side.."-cfg/"..name,list,side.."-cfg",name)
    return ok and result~=false, ok and result~=false and nil or "save_failed"
end
local function resolvedItemId(item)
    local id=item.item_id or item.foreign_item_id or item.id
    if id~=nil and tostring(id)~="" then return tostring(id) end
    if itemIcons and type(itemIcons.resolveItemId)=="function" then
        local ok,value=callCore(itemIcons.resolveItemId,item.name or item.item or "")
        if ok and value~=nil and tostring(value)~="" then return tostring(value) end
    end
end
local function itemCategory(item)
    if ctx and type(ctx.getTradeItemCategory)=="function" then
        local ok,category=callCore(ctx.getTradeItemCategory,item)
        if ok and type(category)=="string" and category~="" then return category end
    end
    return "other"
end
local function itemCategorySubtypeRank(item)
    if ctx and type(ctx.getTradeFilterSubtypeRank)=="function" then
        local ok,rank=callCore(ctx.getTradeFilterSubtypeRank,item)
        if ok then return math.max(0,math.floor(saneNumber(rank,0) or 0)) end
    end
    return 0
end
local FALLBACK_CATEGORIES={
    {id="cases",label="Ларцы"},{id="accessories",label="Аксессуары"},{id="skins",label="Скины"},
    {id="weapons",label="Оружие"},{id="certificates",label="Сертификаты"},{id="tuning",label="Тюнинг"},
    {id="upgrades",label="Улучшения"},{id="resources",label="Ресурсы/крафт"},{id="objects",label="Объекты"},
    {id="shards",label="Осколки"},{id="other",label="Прочее"}
}
local function categoryOptions(side)
    local raw=nil
    if ctx and type(ctx.getTradeFilterCategories)=="function" then
        local ok,value=callCore(ctx.getTradeFilterCategories,side)
        if ok and type(value)=="table" then raw=value end
    end
    if type(raw)~="table" or #raw==0 then return FALLBACK_CATEGORIES end
    local out={}
    local seen={}
    for i=1,#raw do
        local row=raw[i]
        if type(row)=="table" then
            local id=tostring(row.id or "")
            if id~="" and not seen[id] then
                seen[id]=true
                out[#out+1]={id=id,label=toUtf8(row.label or id),order=math.floor(saneNumber(row.order,i) or i)}
            end
        end
    end
    return #out>0 and out or FALLBACK_CATEGORIES
end
local function itemDto(item,index,side)
    local id=resolvedItemId(item)
    return {
        identity={index=index,name=toUtf8(item.name or item.item or ""),item_id=id,slot_id=item.slot_id},
        name=toUtf8(item.name or item.item or ("Item #"..tostring(index))),
        item_id=id,
        category=itemCategory(item), category_subtype_rank=itemCategorySubtypeRank(item), manual_category=tostring(item.trade_filter_category or ""),
        price=saneNumber(item.price,0), price_vc=saneNumber(item.price_vc,0),
        count=saneNumber(item.count,0), continue=saneNumber(item.continue,0),
        enabled=item.enabled~=false, maximum=item.maximum==true,
        count_maximum=saneNumber(item.count_maximum,0), all_count=saneNumber(item.all_count,0),
        slot_count=saneNumber(item.slot_count,0), slot_id=item.slot_id, side=side
    }
end
local function fingerprint(side,list,runtimeKey)
    local out={side,tostring(#list),tostring(runtimeKey or "")}
    for i=1,#list do
        local x=list[i]
        out[#out+1]=table.concat({
            tostring(x.name or x.item or ""),tostring(x.price or ""),tostring(x.price_vc or ""),
            tostring(x.count or ""),tostring(x.continue or ""),tostring(x.enabled~=false),
            tostring(x.maximum==true),tostring(x.count_maximum or ""),tostring(x.all_count or ""),tostring(x.slot_id or ""),
            tostring(x.trade_filter_category or "")
        },"\30")
    end
    return table.concat(out,"\31")
end
local function touchRevision(side,list,runtimeKey)
    local value=fingerprint(side,list,runtimeKey)
    if value~=fingerprints[side] then
        fingerprints[side]=value
        revision[side]=revision[side]+1
    end
end
local function fingerprintScalar(value)
    local valueType=type(value)
    if value==nil then return "" end
    if valueType=="string" then return value end
    if valueType=="number" then return string.format("%.17g",value) end
    if valueType=="boolean" then return value and "1" or "0" end
    if valueType=="table" then
        local parts={}
        local count=0
        for index=1,#value do
            count=count+1
            parts[count]=fingerprintScalar(rawget(value,index))
        end
        if count>0 then return table.concat(parts,"\28") end
        return "<table>"
    end
    -- Never call tostring() for userdata/thread/function/cdata here. Some host
    -- objects expose metamethods that can cross MoonLoader coroutine boundaries.
    return "<"..valueType..">"
end

local function sourceFingerprint(source)
    if type(source)~="table" then return "0" end
    local out={}
    local count=0
    for i=1,#source do
        local x=rawget(source,i)
        if type(x)=="table" then
            count=count+1
            out[count+1]=table.concat({
                fingerprintScalar(rawget(x,"name")),fingerprintScalar(rawget(x,"item_id")),fingerprintScalar(rawget(x,"all_count")),
                fingerprintScalar(rawget(x,"slot_count")),fingerprintScalar(rawget(x,"slot_id")),fingerprintScalar(rawget(x,"category"))
            },"\30")
        end
    end
    out[1]=fingerprintScalar(count)
    return table.concat(out,"\31")
end

local function buildSourceCache(side, raw)
    side = side == "sell" and "sell" or "buy"
    local out = {}
    if type(raw) == "table" then
        for i = 1, #raw do
            local x = raw[i]
            if side == "buy" and type(x) == "string" then
                local id = itemIcons and itemIcons.resolveItemId and itemIcons.resolveItemId(x) or nil
                local sourceItem = {name=x,item_id=id}
                out[#out+1] = {index=i,name=toUtf8(x),item_id=id,category=itemCategory(sourceItem)}
            elseif side == "sell" and type(x) == "table" then
                local rawName = rawget(x,"item") or rawget(x,"name")
                local name = type(rawName) == "string" and rawName or ("Item #"..tostring(i))
                local id = rawget(x,"item_id") or rawget(x,"foreign_item_id") or rawget(x,"id")
                if id == nil and itemIcons and itemIcons.resolveItemId then id = itemIcons.resolveItemId(name) end
                out[#out+1] = {index=i,name=toUtf8(name),all_count=saneNumber(rawget(x,"all_count"),saneNumber(rawget(x,"count"),0)),
                    slot_count=saneNumber(rawget(x,"count"),0),slot_id=rawget(x,"slot_id"),item_id=id,category=itemCategory(x)}
            end
        end
    end
    sourceCache[side] = {at=nowMs(),data=out,fingerprint=sourceFingerprint(out)}
    return out
end

local function refreshSourceCache(side, allowDisk)
    side = side == "sell" and "sell" or "buy"
    local raw = nil
    if ctx and type(ctx.getTradeSource) == "function" then
        local ok,value = callCore(ctx.getTradeSource,side)
        if ok and type(value) == "table" then raw = value end
    end
    if raw == nil and allowDisk == true and ctx and type(ctx.readJsonFile) == "function" then
        local path = side == "buy" and "moonloader/ArzMarket/buy.json" or "moonloader/ArzMarket/sell.json"
        local ok,value = callCore(ctx.readJsonFile,path)
        if ok and type(value) == "table" then raw = value end
    end
    if type(raw) == "table" then return buildSourceCache(side,raw) end
    return sourceCache[side] and sourceCache[side].data or {}
end

local function sources(side)
    side = side == "sell" and "sell" or "buy"
    local cached = sourceCache[side]
    local now = nowMs()
    if cached and now - cached.at < 1000 then return cached.data end
    -- HTTP requests must never perform file I/O. Use the live in-memory source
    -- when available; otherwise keep the last safe cache until the producer
    -- refreshes it from init/invalidation.
    return refreshSourceCache(side,false)
end

local function automationSnapshot()
    if not ctx or type(ctx.getTradeAutomationState)~="function" then return {sell=false,buy=false,score=0,score_from=0} end
    local ok,state=callCore(ctx.getTradeAutomationState)
    if not ok or type(state)~="table" then return {sell=false,buy=false,score=0,score_from=0} end
    return state
end
local function automationState(side)
    local state=automationSnapshot()
    return state[side]==true,saneNumber(state.score,0) or 0,saneNumber(state.score_from,0) or 0
end
local function tradeBusy()
    local state=automationSnapshot()
    return state.sell==true or state.buy==true
end
local function setMenuVisible(value)
    if not ctx or type(ctx.setCoreMenuVisible)~="function" then return false end
    local ok,result=callCore(ctx.setCoreMenuVisible,value==true)
    return ok and result~=false
end
local function selectLuaPage(page)
    if ctx and type(ctx.selectCorePage)=="function" then
        local pageId=page=="sell" and 1 or page=="settings" and 3 or page=="logs" and 4 or page=="marketplace" and 5 or page=="mods" and 7 or page=="storage" and 8 or 2
        local ok,result=callCore(ctx.selectCorePage,pageId)
        if ok and result~=false then return true end
    end
    return false
end


local function logNumber(value)
    local digits=tostring(value or ""):gsub("[^0-9]","")
    return tonumber(digits) or 0
end
local function logSortKey(dateText,timeText)
    local d,m,y=tostring(dateText or ""):match("^(%d%d)%.(%d%d)%.(%d%d%d%d)$")
    local h,mi,se=tostring(timeText or ""):match("^(%d%d):(%d%d):(%d%d)$")
    if not d then return 0 end
    return (tonumber(y) or 0)*10000000000+(tonumber(m) or 0)*100000000+(tonumber(d) or 0)*1000000
        +(tonumber(h) or 0)*10000+(tonumber(mi) or 0)*100+(tonumber(se) or 0)
end
local function logTime(line)
    return tostring(line or ""):match("^%[(%d%d:%d%d:%d%d)%]") or ""
end
local function cleanLoggedItem(value)
    local name=tostring(value or "")
    local count=tonumber(name:match("%((%d+)%s*шт%.%)%s*$")) or 1
    name=name:gsub("%s*%(%d+%s*шт%.%)%s*$","")
    return name,count
end
local function newLogRecord(out,dateText,source,index,line,category,label,description,detail,amount,currency,status)
    local timeText=logTime(line)
    out[#out+1]={
        id=table.concat({tostring(dateText),tostring(source),tostring(index),tostring(line)},"|"),
        date=tostring(dateText or ""),time=timeText,sort_key=logSortKey(dateText,timeText),
        source=tostring(source or ""),category=tostring(category or "info"),category_label=tostring(label or "Информация"),
        description=tostring(description or ""),detail=tostring(detail or ""),raw=tostring(line or ""),
        amount=amount~=nil and saneNumber(amount,0) or nil,currency=tostring(currency or "SA"),status=tostring(status or "success")
    }
end
local function parseBusinessLog(out,dateText,index,rawLine)
    local line=toUtf8(rawLine)
    local category,label,description
    if line:find(" купил ",1,true) then
        category,label,description="sell","Продажа","Успешная продажа товара"
    elseif line:find(" продал ",1,true) then
        category,label,description="buy","Покупка","Успешная покупка товара"
    else
        newLogRecord(out,dateText,"business",index,line,"info","Информация","Событие ArzMarket",line,nil,"SA","info")
        return
    end
    local itemText=line:match('"([^"]+)"') or ""
    local itemName,count=cleanLoggedItem(itemText)
    local currency=line:find("VC$",1,true) and "VC" or "SA"
    local amountText=line:match("за%s*VC%$([%d%.,%s]+)") or line:match("за%s*%$([%d%.,%s]+)") or "0"
    local amount=logNumber(amountText)
    if category=="buy" then amount=-amount end
    local detail=itemName
    if detail~="" then detail=detail.." (x"..tostring(count)..")" end
    newLogRecord(out,dateText,"business",index,line,category,label,description,detail,amount,currency,"success")
end
local function parseTradeLog(out,dateText,index,rawLine)
    local line=toUtf8(rawLine)
    local player=line:match("Трейд с ([^|]+)") or ""
    player=player:gsub("^%s+",""):gsub("%s+$","")
    local received=logNumber(line:match("получили%s+%$([%d%.,%s]+)") or "0")
    local spent=logNumber(line:match("потратили%s+%$([%d%.,%s]+)") or "0")
    local detail="Получено $"..tostring(received)..", потрачено $"..tostring(spent)
    newLogRecord(out,dateText,"trade",index,line,"trade","Трейд","Трейд с "..(player~="" and player or "игроком"),detail,received-spent,"SA","success")
end
local function parseBankLog(out,dateText,index,rawLine)
    local line=toUtf8(rawLine)
    local incoming=line:find("Поступление на банк",1,true)~=nil
    local amount=logNumber(line:match("получили%s+%$([%d%.,%s]+)") or line:match("потратили%s+%$([%d%.,%s]+)") or "0")
    if not incoming then amount=-amount end
    local description=incoming and "Поступление на банк" or "Банковский перевод"
    local detail=line:gsub("^%[%d%d:%d%d:%d%d%]%s*","")
    newLogRecord(out,dateText,"bank",index,line,"bank","Банк",description,detail,amount,"SA","success")
end
local function parseRentalLog(out,dateText,index,rawLine)
    local line=toUtf8(rawLine)
    local currency=line:find("VC$",1,true) and "VC" or "SA"
    local amount=logNumber(line:match("За%s+VC%$([%d%.,%s]+)") or line:match("За%s+%$([%d%.,%s]+)") or "0")
    local detail=line:gsub("^%[%d%d:%d%d:%d%d%]%s*","")
    newLogRecord(out,dateText,"rent",index,line,"rent","Аренда","Аренда имущества",detail,amount,currency,"success")
end
local function logsRaw()
    if not ctx or type(ctx.getLogsData)~="function" then return {} end
    local ok,value=callCore(ctx.getLogsData)
    if not ok or type(value)~="table" then return {} end
    return value
end
local function logsFingerprint(raw)
    local dates={}
    for dateText,day in pairs(raw) do
        if type(dateText)=="string" and dateText:match("^%d%d%.%d%d%.%d%d%d%d$") and type(day)=="table" then dates[#dates+1]=dateText end
    end
    table.sort(dates,function(a,b) return logSortKey(a,"00:00:00")<logSortKey(b,"00:00:00") end)
    local parts={tostring(#dates)}
    for _,dateText in ipairs(dates) do
        local day=raw[dateText]
        local one=type(day[1])=="table" and day[1] or {}
        local trades=type(day[11])=="table" and day[11] or {}
        local bank=type(day[12])=="table" and day[12] or {}
        local rent=type(day[15])=="table" and day[15] or {}
        parts[#parts+1]=table.concat({dateText,#one,#trades,#bank,#rent,tostring(day[2] or 0),tostring(day[3] or 0),tostring(day[4] or 0),tostring(day[5] or 0),tostring(one[#one] or ""),tostring(trades[1] or ""),tostring(bank[1] or ""),tostring(rent[1] or "")},"\30")
    end
    return table.concat(parts,"\31")
end
local function logsState()
    currentPage="logs"
    local raw=logsRaw()
    local fp=logsFingerprint(raw)
    if fp~=fingerprints.logs then fingerprints.logs=fp; revision.logs=revision.logs+1 end
    local records={}
    for dateText,day in pairs(raw) do
        if type(dateText)=="string" and dateText:match("^%d%d%.%d%d%.%d%d%d%d$") and type(day)=="table" then
            local business=type(day[1])=="table" and day[1] or {}
            for i=1,#business do parseBusinessLog(records,dateText,i,business[i]) end
            local trades=type(day[11])=="table" and day[11] or {}
            for i=1,#trades do parseTradeLog(records,dateText,i,trades[i]) end
            local bank=type(day[12])=="table" and day[12] or {}
            for i=1,#bank do parseBankLog(records,dateText,i,bank[i]) end
            local rent=type(day[15])=="table" and day[15] or {}
            for i=1,#rent do parseRentalLog(records,dateText,i,rent[i]) end
        end
    end
    table.sort(records,function(a,b)
        if a.sort_key~=b.sort_key then return a.sort_key>b.sort_key end
        return tostring(a.id)>tostring(b.id)
    end)
    if #records>5000 then
        local trimmed={}
        for i=1,5000 do trimmed[i]=records[i] end
        records=trimmed
    end
    return {
        revision=revision.logs,page="logs",
        common={uiMode="html",htmlWindow=htmlWindowState,menuScalePercent=currentMenuScalePercent(),today=os.date("%d.%m.%Y"),tradeBusy=tradeBusy()},
        data={records=records}
    }
end

local STORAGE_CATEGORY_LABELS={
    accessories="Аксессуары",cases="Ларцы",skins="Скины",weapons="Оружие",certificates="Сертификаты",
    tuning="Тюнинг",upgrades="Улучшения",resources="Ресурсы/крафт",objects="Объекты",shards="Осколки",other="Прочее"
}
local STORAGE_KIND_LABELS={
    player_inventory="Инвентарь",house_closet="Шкаф",house_object="Дом",warehouse="Склад",vehicle_trunk="Багажник",unknown="Неизвестно"
}
local storageSnapshotCache={items={},locationCount=0,ready=false,scanning=false,lastScan=0,error="loading",fingerprint=""}
local storageWorkerRunning=false
local storageWorkerGeneration=0
local storageRefreshRequested=true

local function safeStorageFinder()
    if not ctx or type(ctx.getStorageFinder)~="function" then return nil end
    local ok,finder=callCore(ctx.getStorageFinder)
    if ok and type(finder)=="table" then return finder end
    return nil
end
local function storageObjectLabel(kind,identity,label)
    identity=type(identity)=="table" and identity or {}
    if kind=="house_closet" or kind=="house_object" then
        local n=tostring(identity.house_number or "")
        return n~="" and ("Дом №"..n) or tostring(label or "-")
    elseif kind=="warehouse" then
        local n=tostring(identity.warehouse_number or "")
        return n~="" and ("Склад №"..n) or tostring(label or "-")
    elseif kind=="vehicle_trunk" then
        local n=tostring(identity.vehicle_name or "")
        if n=="" then n=tostring(label or ""):gsub("%s*%-%>%s*Багажник%s*$","") end
        return n~="" and n or "Автомобиль"
    end
    return "-"
end

local function storageSnapshotFingerprint(items,locationCount,scanning,lastScan)
    local parts={tostring(locationCount or 0),tostring(scanning==true),tostring(lastScan or 0),tostring(#items)}
    for i=1,#items do
        local item=items[i]
        local locParts={}
        for j=1,#(item.locations or {}) do
            local loc=item.locations[j]
            locParts[#locParts+1]=table.concat({tostring(loc.key or ""),tostring(loc.count or 0),tostring(loc.updated or 0)},"\29")
        end
        parts[#parts+1]=table.concat({
            tostring(item.key or ""),tostring(item.count or 0),tostring(item.category or ""),tostring(item.updated or 0),table.concat(locParts,"\28")
        },"\30")
    end
    return table.concat(parts,"\31")
end

local function buildStorageSnapshotFromFinder()
    local finder=safeStorageFinder()
    if not finder then return nil,"storage_unavailable" end
    if finder.ready~=true then return nil,"storage_not_ready" end
    if type(finder.getVisibleRows)~="function" then return nil,"storage_rows_unavailable" end

    local okRows,rows=callCore(finder.getVisibleRows,"",{storage_type="all",category="all"})
    if not okRows or type(rows)~="table" then return nil,okRows and "storage_rows_invalid" or tostring(rows) end

    local groups,items,locationKeys={}, {}, {}
    local newest=0
    for i=1,#rows do
        local row=rows[i]
        if type(row)=="table" then
            local name=tostring(row.name or "Неизвестный предмет")
            local groupKey=name
            local group=groups[groupKey]
            if not group then
                local itemId=row.item_id~=nil and tostring(row.item_id) or resolvedItemId({name=name,item_id=row.item_id,model_id=row.model_id})
                group={
                    key=groupKey,name=name,count=0,item_id=itemId,
                    category=tostring(row.category or "other"),locations={},locations_by_key={},updated=0
                }
                groups[groupKey]=group
                items[#items+1]=group
            end

            local count=math.max(0,math.floor(saneNumber(row.count,1) or 1))
            local updated=math.max(0,math.floor(saneNumber(row.last_scan,0) or 0))
            group.count=group.count+count
            group.updated=math.max(group.updated,updated)
            newest=math.max(newest,updated)
            if group.category=="other" and row.category and tostring(row.category)~="" then group.category=tostring(row.category) end

            local kind=tostring(row.storage_kind or "unknown")
            local kindLabel=STORAGE_KIND_LABELS[kind] or "Неизвестно"
            local storageLabel=tostring(row.storage_label or kindLabel)
            local storageKey=tostring(row.storage_key or (kind..":"..storageLabel))
            locationKeys[storageKey]=true
            local loc=group.locations_by_key[storageKey]
            if not loc then
                loc={
                    key=storageKey,kind=kind,kind_label=kindLabel,
                    object_label=storageObjectLabel(kind,row.storage_identity,storageLabel),
                    label=storageLabel,count=0,updated=updated
                }
                group.locations_by_key[storageKey]=loc
                group.locations[#group.locations+1]=loc
            end
            loc.count=loc.count+count
            loc.updated=math.max(loc.updated,updated)
        end
    end

    table.sort(items,function(a,b)return tostring(a.name)<tostring(b.name) end)
    for i=1,#items do
        local item=items[i]
        item.type_label=STORAGE_CATEGORY_LABELS[item.category] or "Прочее"
        item.locations_by_key=nil
        table.sort(item.locations,function(a,b)
            local ak=tostring(a.label or "")
            local bk=tostring(b.label or "")
            if ak==bk then return tostring(a.key or "")<tostring(b.key or "") end
            return ak<bk
        end)
    end

    local locationCount=0
    for _ in pairs(locationKeys) do locationCount=locationCount+1 end

    local scanning=false
    if type(finder.getState)=="function" then
        local okState,coreState=callCore(finder.getState)
        if okState and type(coreState)=="table" then
            scanning=coreState.player_scan_active==true or (type(coreState.manual_scan)=="table" and coreState.manual_scan.requested==true)
            local coreLast=type(coreState.last_scan)=="table" and saneNumber(coreState.last_scan.time,0) or 0
            newest=math.max(newest,saneNumber(coreLast,0) or 0)
        end
    end

    return {items=items,locationCount=locationCount,ready=true,scanning=scanning,lastScan=newest,error=nil}
end

local function refreshStorageSnapshotCache()
    local ok,snapshotOrErr,maybeErr=callCore(buildStorageSnapshotFromFinder)
    local snapshot=nil
    local err=nil
    if ok then snapshot=snapshotOrErr; err=maybeErr else err=snapshotOrErr end
    if type(snapshot)~="table" then
        if storageSnapshotCache.ready~=true then
            storageSnapshotCache.error=tostring(err or "storage_snapshot_failed")
        end
        return false,err
    end

    local fp=storageSnapshotFingerprint(snapshot.items,snapshot.locationCount,snapshot.scanning,snapshot.lastScan)
    if fp~=storageSnapshotCache.fingerprint then
        snapshot.fingerprint=fp
        storageSnapshotCache=snapshot
        revision.storage=revision.storage+1
    else
        storageSnapshotCache.ready=true
        storageSnapshotCache.scanning=snapshot.scanning
        storageSnapshotCache.lastScan=snapshot.lastScan
        storageSnapshotCache.error=nil
    end
    return true
end

local function stopStorageSnapshotWorker()
    storageWorkerGeneration=storageWorkerGeneration+1
    storageWorkerRunning=false
end

local function startStorageSnapshotWorker()
    if storageWorkerRunning then return true end
    if not ctx or not ctx.lua_thread or type(ctx.lua_thread.create)~="function" or type(ctx.wait)~="function" then return false end
    storageWorkerGeneration=storageWorkerGeneration+1
    local generation=storageWorkerGeneration
    storageWorkerRunning=true
    local workerOk,workerOrErr=pcall(ctx.lua_thread.create,function()
        ctx.wait(0)
        while storageWorkerRunning and generation==storageWorkerGeneration do
            local ok,err=callCore(refreshStorageSnapshotCache)
            if not ok then
                storageSnapshotCache.error=tostring(err)
                log("storage snapshot worker failed: "..tostring(err))
            end
            storageRefreshRequested=false
            local waited=0
            while storageWorkerRunning and generation==storageWorkerGeneration and waited<1200 and not storageRefreshRequested do
                ctx.wait(100)
                waited=waited+100
            end
        end
    end)
    if not workerOk or not workerOrErr then
        if generation==storageWorkerGeneration then storageWorkerRunning=false end
        storageSnapshotCache.error="storage_worker_start_failed"
        log("storage snapshot worker start failed: "..tostring(workerOrErr))
        return false
    end
    return true
end

local function storageState()
    currentPage="storage"
    startStorageSnapshotWorker()
    local cache=storageSnapshotCache
    return {
        revision=revision.storage,page="storage",
        common={
            uiMode="html",htmlWindow=htmlWindowState,menuScalePercent=currentMenuScalePercent(),
            storageReady=cache.ready==true,scanning=cache.scanning==true,
            lastScan=saneNumber(cache.lastScan,0) or 0,storageError=cache.error
        },
        data={items=type(cache.items)=="table" and cache.items or {},locationCount=saneNumber(cache.locationCount,0) or 0}
    }
end

local function marketplaceUtf8Valid(value)
    value=tostring(value or "")
    local i,n=1,#value
    while i<=n do
        local b=value:byte(i)
        if b<0x80 then i=i+1
        elseif b>=0xC2 and b<=0xDF then
            local b2=value:byte(i+1); if not b2 or b2<0x80 or b2>0xBF then return false end; i=i+2
        elseif b>=0xE0 and b<=0xEF then
            local b2,b3=value:byte(i+1),value:byte(i+2)
            if not b2 or not b3 or b2<0x80 or b2>0xBF or b3<0x80 or b3>0xBF then return false end
            if b==0xE0 and b2<0xA0 then return false end
            if b==0xED and b2>=0xA0 then return false end
            i=i+3
        elseif b>=0xF0 and b<=0xF4 then
            local b2,b3,b4=value:byte(i+1),value:byte(i+2),value:byte(i+3)
            if not b2 or not b3 or not b4 or b2<0x80 or b2>0xBF or b3<0x80 or b3>0xBF or b4<0x80 or b4>0xBF then return false end
            if b==0xF0 and b2<0x90 then return false end
            if b==0xF4 and b2>=0x90 then return false end
            i=i+4
        else return false end
    end
    return true
end
local function marketplaceText(value)
    value=tostring(value or "")
    if value=="" then return "" end
    if marketplaceUtf8Valid(value) then return value end
    return toUtf8(value)
end
local function marketplaceOffers(names,counts,prices)
    local out={}
    names=type(names)=="table" and names or {}
    counts=type(counts)=="table" and counts or {}
    prices=type(prices)=="table" and prices or {}
    for i=1,#names do
        local rawName=tostring(names[i] or "")
        local itemId=nil
        if itemIcons and type(itemIcons.resolveItemId)=="function" then
            local ok,value=callCore(itemIcons.resolveItemId,rawName)
            if ok and value~=nil and tostring(value)~="" then itemId=tostring(value) end
        end
        out[#out+1]={name=marketplaceText(rawName),count=saneNumber(counts[i],0) or 0,price=saneNumber(prices[i],0) or 0,item_id=itemId}
    end
    return out
end
local function marketplaceState()
    currentPage="marketplace"
    local raw={}
    if ctx and type(ctx.getMarketplaceSnapshot)=="function" then
        local ok,value=callCore(ctx.getMarketplaceSnapshot)
        if ok and type(value)=="table" then raw=value end
    end
    local servers={}
    if type(raw.servers)=="table" then
        for i=1,#raw.servers do
            local row=raw.servers[i]
            if type(row)=="table" then
                local index=math.floor(saneNumber(row.index,i-1) or (i-1))
                servers[#servers+1]={index=index,apiId=math.floor(saneNumber(row.apiId,index-1) or (index-1)),name=index==0 and "Все сервера" or marketplaceText(row.name)}
            end
        end
    end
    local serverNames={}
    for _,row in ipairs(servers) do serverNames[tonumber(row.apiId) or -999]=row.name end
    local shops={}
    local rawShops=type(raw.shops)=="table" and raw.shops or {}
    for i=1,#rawShops do
        local shop=rawShops[i]
        if type(shop)=="table" then
            local serverId=math.floor(saneNumber(shop.serverId,-1) or -1)
            shops[#shops+1]={
                key=tostring(serverId)..":"..tostring(shop.LavkaUid or i),
                uid=math.floor(saneNumber(shop.LavkaUid,i) or i),
                username=marketplaceText(shop.username),
                serverId=serverId,
                serverName=serverNames[serverId] or ("Server "..tostring(serverId)),
                userStatus=math.floor(saneNumber(shop.userStatus,0) or 0),
                updatedAt=math.floor(saneNumber(shop.ostime,0) or 0),
                itemsBuy=marketplaceOffers(shop.items_buy,shop.count_buy,shop.price_buy),
                itemsSell=marketplaceOffers(shop.items_sell,shop.count_sell,shop.price_sell)
            }
        end
    end
    local data={
        status=tostring(raw.status or "loading"),shops=shops,servers=servers,
        selectedIndex=math.floor(saneNumber(raw.selectedIndex,0) or 0),selectedName=marketplaceText(raw.selectedName or "Все сервера"),
        currentServerId=saneNumber(raw.currentServerId,nil),queue=math.floor(saneNumber(raw.queue,0) or 0),
        shopCount=math.floor(saneNumber(raw.shopCount,#shops) or #shops),sortMode=math.floor(saneNumber(raw.sortMode,0) or 0),
        lastUpdated=math.floor(saneNumber(raw.lastUpdated,0) or 0),publishing=raw.publishing==true,publishedShopId=saneNumber(raw.publishedShopId,nil),
        unbanAvailable=raw.unbanAvailable==true
    }
    local fp=encode(data)
    if fp~=fingerprints.marketplace then fingerprints.marketplace=fp; revision.marketplace=revision.marketplace+1 end
    return {revision=revision.marketplace,page="marketplace",common={uiMode="html",htmlWindow=htmlWindowState,menuScalePercent=currentMenuScalePercent()},data=data}
end

local function modsState()
    currentPage="mods"
    local data={}
    if ctx and type(ctx.getModsSnapshot)=="function" then
        local ok,value=callCore(ctx.getModsSnapshot)
        if ok and type(value)=="table" then data=utf8Tree(value,0) or {} end
    end
    local fp=encode(data)
    if fp~=fingerprints.mods then
        fingerprints.mods=fp
        revision.mods=revision.mods+1
    end
    return {
        revision=revision.mods,page="mods",
        common={uiMode="html",htmlWindow=htmlWindowState,menuScalePercent=currentMenuScalePercent()},
        data=data
    }
end

local function settingsSnapshotData(force)
    local now=nowMs()
    if force==true or type(settingsSnapshotCache.data)~="table" or now-(settingsSnapshotCache.at or 0)>=1500 then
        local snapshot={}
        if ctx and type(ctx.getSettingsSnapshot)=="function" then
            local ok,value=callCore(ctx.getSettingsSnapshot)
            if ok and type(value)=="table" then snapshot=value end
        end
        settingsSnapshotCache.data=utf8Tree(snapshot,0) or {}
        settingsSnapshotCache.at=now
    end
    return settingsSnapshotCache.data or {}
end

local function currentHtmlThemeKey()
    local data=settingsSnapshotData(false)
    local appearance=type(data.appearance)=="table" and data.appearance or {}
    local globalPalette=type(appearance.global_palette)=="table" and appearance.global_palette or {}
    if globalPalette.enabled==true then return "global_palette" end
    local key=tostring(appearance.palette_key or "")
    if key=="" then key="arzmarket_default" end
    return key
end

local function currentHtmlThemeProfile()
    local data=settingsSnapshotData(false)
    local appearance=type(data.appearance)=="table" and data.appearance or {}
    local profile=type(appearance.global_palette)=="table" and appearance.global_palette or {}
    return profile
end

local function settingsState()
    currentPage="settings"
    local dirty=fingerprints.settings==""
    local base=settingsSnapshotData(dirty)
    local data={}
    if type(base)=="table" then
        for k,v in pairs(base) do data[k]=v end
    end
    local mods={}
    if ctx and type(ctx.getModsSnapshot)=="function" then
        local ok,value=callCore(ctx.getModsSnapshot)
        if ok and type(value)=="table" then mods=utf8Tree(value,0) or {} end
    end
    data.mods=mods
    local fp=encode(data)
    if fp~=fingerprints.settings then
        fingerprints.settings=fp
        revision.settings=revision.settings+1
    end
    return {
        revision=revision.settings,page="settings",
        common={uiMode="html",htmlWindow=htmlWindowState,menuScalePercent=currentMenuScalePercent(),htmlThemeKey=currentHtmlThemeKey(),htmlThemeProfile=currentHtmlThemeProfile()},
        data=data
    }
end

local function stateFor(page)
    if page~="storage" and storageWorkerRunning then stopStorageSnapshotWorker() end
    if page=="settings" then return settingsState() end
    if page=="mods" then return modsState() end
    if page=="logs" then return logsState() end
    if page=="marketplace" then return marketplaceState() end
    if page=="storage" then return storageState() end
    page=page=="sell" and "sell" or "buy"
    currentPage=page
    ensureLoadedConfig(page)
    restoreTradeDraft(page)
    local buy,sell=lists()
    local list=page=="buy" and buy or sell
    local snapshot=automationSnapshot()
    local active=snapshot[page]==true
    local score=saneNumber(snapshot.score,0) or 0
    local total=saneNumber(snapshot.score_from,0) or 0
    local busy=snapshot.sell==true or snapshot.buy==true
    local cfg=configName(page)
    local configs=configList(page)
    local configsDisplay={}
    for i=1,#configs do configsDisplay[i]=toUtf8(configs[i]) end
    local source=sources(page)
    local categories=categoryOptions(page)
    local uiState={currency="SA",buy_scan=false,sell_scan=false}
    if ctx and type(ctx.getTradeUiState)=="function" then
        local ok,value=callCore(ctx.getTradeUiState)
        if ok and type(value)=="table" then uiState=value end
    end
    local currency=uiState.currency=="VC" and "VC" or "SA"
    local buyScan=uiState.buy_scan==true
    local sellScan=uiState.sell_scan==true
    local undoCount=0
    if ctx and type(ctx.getTradeUndoCount)=="function" then
        local ok,value=callCore(ctx.getTradeUndoCount,page)
        if ok then undoCount=math.max(0,math.floor(tonumber(value) or 0)) end
    end
    local buyContinue=false
    if ctx and type(ctx.getBuyContinueMode)=="function" then
        local ok,value=callCore(ctx.getBuyContinueMode)
        if ok then buyContinue=value==true end
    end
    local runtimeKey=table.concat({
        tostring(active),tostring(busy),tostring(snapshot.buy==true),tostring(snapshot.sell==true),
        tostring(score),tostring(total),tostring(cfg),table.concat(configs,"\29"),currency,tostring(buyScan),tostring(sellScan),
        tostring(undoCount),tostring(buyContinue),(sourceCache[page] and sourceCache[page].fingerprint) or "0",encode(categories)
    },"\30")
    touchRevision(page,list,runtimeKey)
    local items={}
    for i=1,#list do items[i]=itemDto(list[i],i,page) end
    local address,serverPort="",0
    if type(sampGetCurrentServerAddress)=="function" then
        local ok,a,p=callCore(sampGetCurrentServerAddress)
        if ok then address,serverPort=tostring(a or ""),tonumber(p) or 0 end
    end
    local iconStatus=itemIcons and itemIcons.getStatus and itemIcons.getStatus() or {}
    return {
        revision=revision[page], page=page,
        common={uiMode="html",menuScalePercent=currentMenuScalePercent(),activeConfig=cfg~="" and toUtf8(cfg:gsub("%.json$","")) or "",configs=configsDisplay,
            currencyMode=currency,buyScan=buyScan,sellScan=sellScan,undoCount=undoCount,buyContinue=buyContinue,
            automation=active,tradeBusy=busy,automationBuy=snapshot.buy==true,automationSell=snapshot.sell==true,
            automationScore=score,automationTotal=total,
            serverAddress=address,serverPort=serverPort,icons=iconStatus,htmlWindow=htmlWindowState,itemCategories=categories},
        data={items=items,source=source}
    }
end
local function findItem(side,identity)
    if type(identity)~="table" then return nil,nil,"identity_missing" end
    local buy,sell=lists()
    local list=side=="buy" and buy or sell
    local wantedName=tostring(identity.name or "")
    local wantedId=identity.item_id~=nil and tostring(identity.item_id) or ""

    -- Scanned sell items can have several inventory slots. In that case slot_id
    -- is a Lua array, for example {"17", "28"}. JSON round-trips create a new
    -- table object, so tostring(table) compares memory addresses and is never a
    -- stable identity. Build a deterministic key from the table contents instead.
    local function slotKey(value)
        if value==nil then return "" end
        if type(value)~="table" then return tostring(value) end
        local count=#value
        if count>0 then
            local parts={}
            for i=1,count do parts[i]=tostring(value[i] or "") end
            return table.concat(parts,"\31")
        end
        local entries={}
        for key,itemValue in pairs(value) do
            entries[#entries+1]=tostring(key).."="..tostring(itemValue or "")
        end
        table.sort(entries)
        return table.concat(entries,"\31")
    end
    local wantedSlot=slotKey(identity.slot_id)

    local function itemName(item)
        return toUtf8(item and (item.name or item.item) or "")
    end
    local function itemSlot(item)
        return item and slotKey(item.slot_id) or ""
    end
    local function itemId(item)
        if type(item)~="table" then return "" end
        local value=item.item_id or item.foreign_item_id or item.id
        return value~=nil and tostring(value) or ""
    end
    local function matches(item)
        if type(item)~="table" then return false end
        local actualSlot=itemSlot(item)
        local actualId=itemId(item)
        local actualName=itemName(item)
        -- slot_id is the strongest identity for scanned inventory rows, but do
        -- not reject immediately when slots changed after a rescan. In that case
        -- item_id/name can still safely resolve the row below.
        if wantedSlot~="" and actualSlot~="" and actualSlot==wantedSlot then
            if wantedName~="" and actualName~=wantedName then return false end
            if wantedId~="" and actualId~="" and actualId~=wantedId then return false end
            return true
        end
        -- item_id stays stable when rows are reordered or the draft is restored.
        if wantedId~="" and actualId~="" then
            if actualId~=wantedId then return false end
            return wantedName=="" or actualName==wantedName
        end
        if wantedName~="" then return actualName==wantedName end
        return false
    end

    -- Fast path: keep using the original index when it still points to the same item.
    local index=math.floor(saneNumber(identity.index,0) or 0)
    if index>=1 and index<=#list and matches(list[index]) then return list[index],index end

    -- The list may be sorted/rebuilt between render and click. Resolve the same
    -- item again by stable identity instead of rejecting a valid edit as stale.
    local foundIndex=nil
    for i=1,#list do
        if matches(list[i]) then
            if foundIndex~=nil then
                -- Ambiguous name-only matches are unsafe to edit.
                if wantedSlot=="" and wantedId=="" then return nil,nil,"stale_state" end
            else
                foundIndex=i
            end
        end
    end
    if foundIndex then return list[foundIndex],foundIndex end
    return nil,nil,"stale_state"
end
local numeric={price=true,price_vc=true,count=true,continue=true,count_maximum=true}
local boolean={enabled=true,maximum=true}
local function updateItem(side,payload)
    local item,_,err=findItem(side,payload.identity)
    if not item then return false,err end
    local patch=type(payload.patch)=="table" and payload.patch or {}
    local updates={}
    for key,value in pairs(patch) do
        if numeric[key] then
            local n=saneNumber(value)
            if not n or n<0 or n>2147483647 then return false,"invalid_"..key end
            if key=="count" or key=="continue" or key=="count_maximum" then n=math.floor(n) end
            updates[key]=n
        elseif boolean[key] then
            if type(value)~="boolean" then return false,"invalid_"..key end
            updates[key]=value
        else
            return false,"field_not_allowed"
        end
    end
    local backup={}
    for key,value in pairs(updates) do backup[key]=item[key]; item[key]=value end
    local ok,saveErr=persist(side)
    if not ok then
        for key,value in pairs(backup) do item[key]=value end
    end
    fingerprints[side]=""
    return ok,saveErr
end
local function removeItem(side,payload)
    local _,index,err=findItem(side,payload.identity)
    if not index then return false,err end
    if not ctx or type(ctx.deleteTradeItem)~="function" then return false,"delete_unavailable" end
    local ok,result,coreErr=callCore(ctx.deleteTradeItem,side,index)
    local success=ok and result~=false
    if success and configName(side)=="" then
        local buy,sell=lists()
        local list=side=="buy" and buy or sell
        local saved,saveErr=saveTradeDraft(side,list)
        if not saved then return false,saveErr end
    end
    fingerprints[side]=""
    return success,success and nil or (ok and coreErr or tostring(result))
end
local function addItem(side,payload)
    local wanted=math.floor(saneNumber(payload.source_index,0) or 0)
    local src
    for _,x in ipairs(sources(side)) do if tonumber(x.index)==wanted then src=x break end end
    if not src then return false,"source_not_found" end
    local buy,sell=lists()
    local list=side=="buy" and buy or sell
    local luaName=fromUtf8(src.name)
    for i=1,#list do if tostring(list[i].name or list[i].item or "")==luaName then return false,"already_exists" end end
    local defaults={price=side=="sell" and 9 or 10,count=1,sort_mode=false}
    if ctx and type(ctx.getTradeAddDefaults)=="function" then
        local ok,value=callCore(ctx.getTradeAddDefaults,side)
        if ok and type(value)=="table" then defaults=value end
    end
    local defaultPrice=saneNumber(defaults.price,side=="sell" and 9 or 10) or (side=="sell" and 9 or 10)
    local defaultCount=math.max(1,math.floor(saneNumber(defaults.count,1) or 1))
    local item
    if side=="buy" then
        item={continue=1,enabled=true,maximum=false,count_maximum=0,price_vc=10,name=luaName,price=defaultPrice,count=defaultCount,item_id=src.item_id}
    else
        local available=math.max(0,math.floor(saneNumber(src.all_count,0) or 0))
        if available<defaultCount then return false,"not_enough_items" end
        item={enabled=true,price_vc=9,maximum=true,name=luaName,price=defaultPrice,count=defaultCount,
            slot_count=src.slot_count,slot_id=src.slot_id,all_count=src.all_count,item_id=src.item_id}
    end
    if type(addToData)=="function" then
        local addOk=pcall(addToData,item,list,defaults.sort_mode and 1 or nil)
        if not addOk then return false,"add_failed" end
    else
        table.insert(list,item)
    end
    local insertedIndex
    for i=#list,1,-1 do
        local candidate=list[i]
        if candidate==item or tostring(candidate.name or candidate.item or "")==luaName then insertedIndex=i; break end
    end
    if not insertedIndex then return false,"add_failed" end
    local ok,saveErr=persist(side)
    if not ok then
        table.remove(list,insertedIndex)
        if type(tradeFilterInvalidate)=="function" then pcall(tradeFilterInvalidate,side) end
        fingerprints[side]=""
        return false,saveErr
    end
    if type(tradeFilterMarkNewItem)=="function" then pcall(tradeFilterMarkNewItem,side,list[insertedIndex] or item) end
    if type(tradeFilterInvalidate)=="function" then pcall(tradeFilterInvalidate,side) end
    sourceCache[side].at=0
    fingerprints[side]=""
    return true
end

local function gameUiNeedsCursor()
    if type(isPauseMenuActive)=="function" then
        local ok,v=pcall(isPauseMenuActive)
        if ok and v==true then return true end
    end
    if type(sampIsChatInputActive)=="function" then
        local ok,v=pcall(sampIsChatInputActive)
        if ok and v==true then return true end
    end
    if type(sampIsDialogActive)=="function" then
        local ok,v=pcall(sampIsDialogActive)
        if ok and v==true then return true end
    end
    return false
end

local function externalSampCursorActive()
    if type(sampIsCursorActive)~="function" then return false end
    local ok,active=pcall(sampIsCursorActive)
    return ok and active==true
end

function M._setArizonaCefNativeInput(enabled)
    enabled=enabled==true
    if M._cefNativeInputOwned==enabled then return true end
    if type(raknetNewBitStream)~="function"
        or type(raknetBitStreamWriteInt8)~="function"
        or type(raknetBitStreamWriteInt32)~="function"
        or type(raknetBitStreamWriteInt16)~="function"
        or type(raknetEmulPacketReceiveBitStream)~="function"
        or type(raknetDeleteBitStream)~="function" then
        return false
    end
    local bs=nil
    local ok=pcall(function()
        bs=raknetNewBitStream()
        -- Arizona packet 220 / sub-id 25 is the CEF cursor/input toggle.
        -- Keep the byte layout used by the original working ArzMarket code.
        raknetBitStreamWriteInt8(bs,25)
        raknetBitStreamWriteInt32(bs,0)
        raknetBitStreamWriteInt8(bs,enabled and 128 or 0)
        raknetBitStreamWriteInt16(bs,0)
        raknetEmulPacketReceiveBitStream(220,bs)
    end)
    if bs then pcall(raknetDeleteBitStream,bs) end
    if ok then M._cefNativeInputOwned=enabled end
    return ok
end

local function setCefCursor(value)
    value=value==true
    if value then
        -- Enable Arizona CEF's own input state. Merely showing a MoonLoader
        -- cursor does not make the embedded browser receive mouse/key events.
        M._setArizonaCefNativeInput(true)

        -- Never manufacture a SA-MP cursor. If the game already owns one, keep
        -- it untouched; otherwise display only MoonLoader's unlocked cursor.
        if externalSampCursorActive() then
            cefCursorOwned=false
            return
        end
        pcall(function() if showCursor then showCursor(true,false) end end)
        cefCursorOwned=true
        return
    end

    -- Do not turn off a CEF/game cursor while a real game UI is active. In that
    -- case relinquish ownership and let the game close its own input state.
    if M._cefNativeInputOwned and not gameUiNeedsCursor() then
        M._setArizonaCefNativeInput(false)
    elseif gameUiNeedsCursor() then
        M._cefNativeInputOwned=false
    end
    if cefCursorOwned then
        pcall(function() if showCursor then showCursor(false,false) end end)
        cefCursorOwned=false
    end
end

local function forceDisableCefCursor()
    if M._cefNativeInputOwned and not gameUiNeedsCursor() then M._setArizonaCefNativeInput(false) end
    if cefCursorOwned then pcall(function() if showCursor then showCursor(false,false) end end) end
    cefCursorOwned=false
    if gameUiNeedsCursor() then M._cefNativeInputOwned=false end
end

local function refocusHtmlFrame(nativePointerEvents)
    if not htmlOpen or not acef or type(acef.eval)~="function" then return end
    local pointerMode=nativePointerEvents==true and "auto" or "none"
    pcall(acef.eval, "var f=document.getElementById('arzmarket-html-frame');if(f){f.style.visibility='visible';f.style.pointerEvents='"..pointerMode.."';try{f.focus();}catch(e){}try{if(f.contentWindow)f.contentWindow.focus();}catch(e){}}")
end


local function backgroundGameUiStealsCursor()
    if type(sampIsDialogActive)=="function" then
        local ok,v=pcall(sampIsDialogActive)
        if ok and v==true then return true end
    end
    if ctx and type(ctx.getMainState)=="function" then
        local ok,state=pcall(ctx.getMainState)
        if ok and type(state)=="table" and state.isEnableCursor==true then return true end
    end
    return false
end

local function htmlInputBounds()
    local sw,sh=1366,768
    if type(getScreenResolution)=="function" then
        local ok,w,h=pcall(getScreenResolution)
        if ok and tonumber(w) and tonumber(h) then sw,sh=tonumber(w),tonumber(h) end
    end
    local state=type(htmlWindowState)=="table" and htmlWindowState or {}
    local x,y,w,h=tonumber(state.x),tonumber(state.y),tonumber(state.width),tonumber(state.height)
    local margin=12
    if x and y and w and h and w>0 and h>0 then
        local savedW,savedH=tonumber(state.viewportWidth),tonumber(state.viewportHeight)
        if savedW and savedH and savedW>0 and savedH>0 and (math.abs(savedW-sw)>2 or math.abs(savedH-sh)>2) then
            local sx,sy=sw/savedW,sh/savedH
            x,y,w,h=x*sx,y*sy,w*sx,h*sy
        end
        local minW=math.min(760,math.max(560,sw-margin*2))
        local minH=math.min(500,math.max(380,sh-margin*2))
        w=math.max(minW,math.min(w,sw-margin*2))
        h=math.max(minH,math.min(h,sh-margin*2))
        x=math.max(margin,math.min(x,sw-w-margin))
        y=math.max(margin,math.min(y,sh-h-margin))
    else
        if htmlTemporaryMode then
            w=math.min(1380,math.max(320,sw-margin*2))
            h=math.min(820,math.max(240,sh-margin*2))
        else
            w=math.min(1600,math.max(320,sw-margin*2),math.max(760,sw*0.88))
            h=math.min(900,math.max(240,sh-margin*2),math.max(500,sh*0.84))
        end
        x=math.max(margin,(sw-w)*0.5)
        y=math.max(margin,(sh-h)*0.5)
    end
    return x,y,w,h
end

local function cursorInsideHtmlWindow()
    if not htmlOpen or type(getCursorPos)~="function" then return false,nil,nil end
    local ok,x,y=pcall(getCursorPos)
    if not ok or not tonumber(x) or not tonumber(y) then return false,nil,nil end
    x,y=tonumber(x),tonumber(y)
    local wx,wy,ww,wh=htmlInputBounds()
    return x>=wx and x<=wx+ww and y>=wy and y<=wy+wh,x,y
end

local function compatInputNeeded()
    -- Universal HTML input path. A visible MoonLoader cursor does not guarantee
    -- that Arizona's root CEF is focused, so native browser mouse events can be
    -- completely absent even though the pointer is moving. Route HTML input
    -- through the same deterministic bridge in both cases:
    --   1) ArzMarket's normal MoonLoader cursor;
    --   2) a standard SA-MP/game cursor owned by another UI.
    -- Lua/mimgui pages keep their own native input path.
    return htmlOpen==true
end

function M._compatFallbackMode()
    if not htmlOpen then return false end
    if gameUiNeedsCursor() then return true end
    -- If SA-MP already owned the cursor before HTML was opened, leave native
    -- game input alone and use the hit-tested compatibility bridge instead.
    return externalSampCursorActive() and not cefCursorOwned and not M._cefNativeInputOwned
end

local function postCompatInput(payload)
    if not htmlOpen or not acef or type(acef.eval)~="function" or type(payload)~="table" then return false end
    payload.channel="arzmarket-host-input"
    -- getCursorPos() is in GTA/screen coordinates, while elementFromPoint()
    -- inside the iframe expects coordinates relative to the iframe viewport.
    -- Convert in the parent CEF using the real iframe rectangle instead of
    -- assuming our saved geometry is pixel-perfect.
    local js="(function(){var f=document.getElementById('arzmarket-html-frame');if(f&&f.contentWindow){try{var p="..encode(payload)..";if(p&&p.kind==='mouse'){var r=f.getBoundingClientRect();p.x=(Number(p.x)||0)-r.left;p.y=(Number(p.y)||0)-r.top;}f.contentWindow.postMessage(p,'*');}catch(e){}}})();"
    local ok,result=pcall(acef.eval,js)
    return ok and result~=false
end

local function classifyWindowMessage(message)
    message=tonumber(message) or -1
    if message>=512 and message<=526 then return "mouse" end
    if message==256 or message==257 or message==258 or message==260 or message==261 then return "keyboard" end
    return nil
end

local function pumpCompatPointer()
    if not compatInputNeeded() then
        htmlCompatLastX,htmlCompatLastY=nil,nil
        htmlCompatLastMoveAt=0
        htmlCompatButtons[1],htmlCompatButtons[2],htmlCompatButtons[3]=false,false,false
        return
    end
    local inside,x,y=cursorInsideHtmlWindow()
    htmlCompatLastMouseInside=inside==true
    if not inside then
        if type(isKeyDown)=="function" then
            local okL,l=pcall(isKeyDown,0x01)
            local okR,r=pcall(isKeyDown,0x02)
            local okM,m=pcall(isKeyDown,0x04)
            if (okL and l==true and not htmlCompatButtons[1]) or (okR and r==true and not htmlCompatButtons[2]) or (okM and m==true and not htmlCompatButtons[3]) then htmlCompatFocused=false end
            if okL then htmlCompatButtons[1]=l==true end
            if okR then htmlCompatButtons[2]=r==true end
            if okM then htmlCompatButtons[3]=m==true end
        end
        htmlCompatLastX,htmlCompatLastY=x,y
        return
    end
    if x~=htmlCompatLastX or y~=htmlCompatLastY then
        -- acef.eval is a real Arizona CEF packet, so do not send one for every
        -- rendered frame. Clicks carry their own coordinates; movement is only
        -- needed for hover/drag and is capped to avoid CEF packet spam.
        local moveNow=nowMs()
        local dragging=htmlCompatButtons[1] or htmlCompatButtons[2] or htmlCompatButtons[3]
        local minMoveInterval=dragging and 24 or 60
        if moveNow-htmlCompatLastMoveAt>=minMoveInterval then
            postCompatInput({kind="mouse",event="move",x=x,y=y})
            htmlCompatLastMoveAt=moveNow
        end
        htmlCompatLastX,htmlCompatLastY=x,y
    end
    if type(isKeyDown)=="function" then
        local keys={0x01,0x02,0x04}
        local buttons={0,2,1}
        for i=1,3 do
            local ok,down=pcall(isKeyDown,keys[i])
            if ok then
                down=down==true
                if down~=htmlCompatButtons[i] then
                    htmlCompatButtons[i]=down
                    if down then htmlCompatFocused=true end
                    postCompatInput({kind="mouse",event=down and "down" or "up",x=x,y=y,button=buttons[i]})
                end
            end
        end
    end
    if type(getMousewheelDelta)=="function" then
        local ok,delta=pcall(getMousewheelDelta)
        delta=ok and tonumber(delta) or 0
        -- WM_MOUSEWHEEL is preferred when available. Skip the polling copy for
        -- a short window so one physical wheel step cannot be delivered twice.
        if delta and delta~=0 and nowMs()-htmlCompatLastWheelEventAt>80 then
            postCompatInput({kind="mouse",event="wheel",x=x,y=y,button=0,delta=delta})
        end
    end
end

local function reclaimHtmlInputIfNeeded()
    if not htmlOpen or not acef then return end
    local now=nowMs()
    if now-lastHtmlInputReclaim<50 then return end
    lastHtmlInputReclaim=now

    local blocked=gameUiNeedsCursor()
    local inside=cursorInsideHtmlWindow()
    htmlCompatLastMouseInside=inside==true

    if not blocked then
        -- Re-assert native Arizona CEF input after a game dialog/chat/pause menu
        -- releases control. This is event-transition based, not packet spam.
        if M._lastGameUiInputBlocked or not M._cefNativeInputOwned then M._setArizonaCefNativeInput(true) end
        if not externalSampCursorActive() then
            pcall(function() if showCursor then showCursor(true,false) end end)
            cefCursorOwned=true
        end
    end

    -- The iframe is full-screen only as a transport surface. Make it natively
    -- interactive strictly while the real cursor is over the visible ArzMarket
    -- window. Outside that rectangle clicks fall through to SA-MP/game dialogs.
    local nativeAllowed=not M._compatFallbackMode()
    local dragging=htmlCompatButtons[1] or htmlCompatButtons[2] or htmlCompatButtons[3]
    refocusHtmlFrame(nativeAllowed and (inside==true or (dragging and htmlCompatFocused)))
    M._lastGameUiInputBlocked=blocked
end

local function releaseCursorAfterHtmlClose()
    if htmlOpen or previewOpen then return end
    if gameUiNeedsCursor() or backgroundGameUiStealsCursor() then
        cefCursorOwned=false
        return
    end
    forceDisableCefCursor()
end

local function removeStaleCefFrames()
    htmlSessionGeneration=htmlSessionGeneration+1
    htmlOpen=false
    previewOpen=false
    previewSignature=""
    htmlTemporaryMode=false
    htmlCompatFocused=false
    htmlCompatLastMouseInside=false
    htmlCompatLastX,htmlCompatLastY=nil,nil
    htmlCompatLastMoveAt=0
    htmlCompatButtons[1],htmlCompatButtons[2],htmlCompatButtons[3]=false,false,false
    if acef and type(acef.eval)=="function" then
        pcall(acef.eval, [[
            (function(){
                var ids=['arzmarket-html-frame','arzmarket-html-preview-frame'];
                for(var i=0;i<ids.length;i++){
                    var f=document.getElementById(ids[i]);
                    if(f){
                        try{f.style.pointerEvents='none';}catch(e){}
                        try{f.blur();}catch(e){}
                        try{if(f.contentWindow)f.contentWindow.blur();}catch(e){}
                        try{f.remove();}catch(e){try{if(f.parentNode)f.parentNode.removeChild(f);}catch(_){} }
                    }
                }
                try{if(document.activeElement&&document.activeElement.blur)document.activeElement.blur();}catch(e){}
            })();
        ]])
    end
end

local function recoverGameInputAfterReload()
    -- A Lua reload may leave our iframe in Arizona CEF, but it must not reset a
    -- cursor owned by another game window or another script.
    removeStaleCefFrames()
    cursorWasActiveBeforeHtml=false
    cefCursorOwned=false
    M._cefNativeInputOwned=false
    M._lastGameUiInputBlocked=false
end

local function quoteJs(v) return string.format("%q",tostring(v or "")):gsub("\r","\\r"):gsub("\n","\\n") end
local function parentFrameBootstrap(url,replaceExisting)
    local replaceCode=replaceExisting and "var old=document.getElementById('arzmarket-html-frame');if(old)old.remove();" or ""
    return "window.__arzMarketFrameToken="..quoteJs(token)..";"..
        "window.__arzMarketFocusFrame=function(f,activate){if(!f)return;f.style.visibility='visible';f.style.pointerEvents=(activate===true?'auto':'none');try{f.focus();}catch(e){}try{if(f.contentWindow)f.contentWindow.focus();}catch(e){}};"..
        "if(!window.__arzMarketFrameMessageBound){window.addEventListener('message',function(e){var d=e&&e.data;if(!d||d.channel!=='arzmarket-html'||d.token!==window.__arzMarketFrameToken)return;var f=document.getElementById('arzmarket-html-frame');if(d.action==='detach'){if(f)f.remove();return;}if(d.action==='hide'){if(f){f.style.visibility='hidden';f.style.pointerEvents='none';}return;}if(d.action==='show'){if(f){f.style.visibility='visible';window.__arzMarketFocusFrame(f,false);}return;}if(d.action==='ready'&&f){f.setAttribute('data-ready','1');window.__arzMarketFocusFrame(f,false);}},false);window.__arzMarketFrameMessageBound=true;}"..
        replaceCode..
        "if(!document.getElementById('arzmarket-html-frame')){var f=document.createElement('iframe');f.id='arzmarket-html-frame';f.src="..quoteJs(url)..";"..
        "f.style.position='fixed';f.style.left='0';f.style.top='0';f.style.width='100vw';f.style.height='100vh';"..
        "f.style.border='0';f.style.background='transparent';f.style.zIndex='2147483000';f.style.pointerEvents='none';f.style.visibility='hidden';"..
        "f.onload=function(){var self=this;if(self&&self.parentNode){self.style.visibility='hidden';self.style.pointerEvents='none';}};"..
        "document.body.appendChild(f);}else{var f=document.getElementById('arzmarket-html-frame');if(f&&f.getAttribute('data-ready')==='1')window.__arzMarketFocusFrame(f,false);}"
end
local function previewFrameBootstrap(url,bounds,options)
    local left=math.max(0,math.floor(tonumber(bounds and bounds.x) or 0))
    local top=math.max(0,math.floor(tonumber(bounds and bounds.y) or 0))
    local width=math.max(180,math.floor(tonumber(bounds and bounds.w) or 320))
    local height=math.max(120,math.floor(tonumber(bounds and bounds.h) or 240))
    local alpha=math.max(0,math.min(1,tonumber(options and options.alpha) or 1))
    local interactive=options and options.interactive==true
    return "var p=document.getElementById('arzmarket-html-preview-frame');var pc=false;"..
        "if(!p){p=document.createElement('iframe');p.id='arzmarket-html-preview-frame';document.body.appendChild(p);pc=true;}"..
        "if(pc||!p.getAttribute('data-arz-src')){p.src="..quoteJs(url)..";p.setAttribute('data-arz-src',"..quoteJs(url)..");}"..
        "p.style.position='fixed';p.style.left='"..tostring(left).."px';p.style.top='"..tostring(top).."px';"..
        "p.style.width='"..tostring(width).."px';p.style.height='"..tostring(height).."px';"..
        "p.style.border='1px solid rgba(55,82,105,.95)';p.style.borderRadius='10px';p.style.background='#071018';p.style.zIndex='2147482998';"..
        "p.style.pointerEvents='"..(interactive and "auto" or "none").."';p.style.transition='opacity .32s ease';"..
        "p.style.boxShadow='0 0 0 rgba(0,0,0,0)';p.style.opacity='"..string.format("%.3f",alpha).."';p.onload=function(){var self=this;setTimeout(function(){if(!self)return;try{self.focus();}catch(e){}try{if(self.contentWindow)self.contentWindow.focus();}catch(e){}},80);};"
end

local function buildUiUrl(preview)
    local url="http://127.0.0.1:"..tostring(port).."/ui?"..(preview and "preview=1&" or "").."page="..tostring(currentPage or "buy").."&ui_rev=268&session="..tostring(token or "")
    if (not preview) and htmlTemporaryMode then url=url.."&temporary=1" end
    if currentPage=="settings" and type(currentSettingsSection)=="string" and currentSettingsSection~="" then
        url=url.."&section="..tostring(currentSettingsSection)
    end
    return url
end
local function removePreviewIframe()
    local wasPreviewOpen=previewOpen==true
    previewOpen=false
    previewSignature=""
    if acef and type(acef.eval)=="function" then pcall(acef.eval,"var p=document.getElementById('arzmarket-html-preview-frame');if(p)p.remove();") end
    if wasPreviewOpen and not htmlOpen then setCefCursor(false) end
end
local function injectPreviewIframe(bounds,options)
    if not acef or type(acef.eval)~="function" or not port then return false end
    local url=buildUiUrl(true)
    local alpha=math.max(0,math.min(1,tonumber(options and options.alpha) or 1))
    local interactive=options and options.interactive==true
    local signature=table.concat({tostring(math.floor(tonumber(bounds and bounds.x) or 0)),tostring(math.floor(tonumber(bounds and bounds.y) or 0)),tostring(math.floor(tonumber(bounds and bounds.w) or 0)),tostring(math.floor(tonumber(bounds and bounds.h) or 0)),tostring(currentPage or "buy"),string.format("%.3f",alpha),interactive and "1" or "0"},":")
    if previewOpen and previewSignature==signature then
        if not htmlOpen then setCefCursor(interactive) end
        return true
    end
    previewSignature=signature
    local ok,result=pcall(acef.eval,previewFrameBootstrap(url,bounds,options))
    ok=ok and result~=false
    if ok then
        previewOpen=true
        if not htmlOpen then setCefCursor(interactive) end
    else
        previewSignature=""
        if not htmlOpen then setCefCursor(false) end
    end
    return ok
end
local function removeIframe()
    htmlSessionGeneration=htmlSessionGeneration+1
    local wasHtmlOpen=htmlOpen==true
    htmlOpen=false
    htmlTemporaryMode=false
    htmlCompatFocused=false
    htmlCompatLastMouseInside=false
    htmlCompatLastX,htmlCompatLastY=nil,nil
    htmlCompatLastMoveAt=0
    htmlCompatButtons[1],htmlCompatButtons[2],htmlCompatButtons[3]=false,false,false
    if acef and type(acef.eval)=="function" then pcall(acef.eval,"var f=document.getElementById('arzmarket-html-frame');if(f){f.style.pointerEvents='none';try{f.blur();}catch(e){}try{if(f.contentWindow)f.contentWindow.blur();}catch(e){}f.remove();}") end
    if wasHtmlOpen then
        -- Preserve the cursor only while a real game UI still needs it. A cursor
        -- left active by the ArzMarket Lua window is not considered external.
        if not (cursorWasActiveBeforeHtml and gameUiNeedsCursor()) then
            releaseCursorAfterHtmlClose()
        end
    end
    cursorWasActiveBeforeHtml=false
end
local function injectIframe(inheritLuaCursor)
    if not acef or type(acef.eval)~="function" or not port then return false end
    local activeBefore=false
    if type(sampIsCursorActive)=="function" then
        local activeOk,activeValue=pcall(sampIsCursorActive)
        activeBefore=activeOk and activeValue==true
    end
    -- Capture ownership before injecting CEF, because focusing the iframe may
    -- change the input state that sampIsCursorActive/game UI functions report.
    local protectedCursorBefore=activeBefore and gameUiNeedsCursor()
    local url=buildUiUrl(false)
    local ok,result=pcall(acef.eval,parentFrameBootstrap(url,true))
    ok=ok and result~=false
    if ok then
        -- sampIsCursorActive() can stay true for one frame after the Lua
        -- ArzMarket window was hidden. Only protect a pre-existing cursor when
        -- an actual game UI (pause/chat/dialog) owned it before CEF opened.
        cursorWasActiveBeforeHtml=protectedCursorBefore
        htmlSessionGeneration=htmlSessionGeneration+1
        htmlOpen=true
        lastInjectCheck=nowMs()
        setCefCursor(true)
        -- When HTML was opened directly from the ArzMarket Lua window, the
        -- cursor can still report active for one frame. Treat that cursor as
        -- ours so closing HTML back to the game cannot leave it stuck.
        if inheritLuaCursor==true and not protectedCursorBefore then cefCursorOwned=true end
        -- No temporary focus coroutine is needed here. M.pump() already checks
        -- the iframe and cursor every frame while HTML is open, which avoids
        -- creating another short-lived MoonLoader coroutine during UI startup.
    end
    return ok
end
local function ensureIframe()
    if not htmlOpen or not acef or nowMs()-lastInjectCheck<650 then return end
    lastInjectCheck=nowMs()
    local url=buildUiUrl(false)
    pcall(acef.eval,parentFrameBootstrap(url,false))
    refocusHtmlFrame(false)
end

local function readFile(path,binary)
    local f=io.open(path,binary and "rb" or "r")
    if not f then return nil end
    local data=f:read("*a"); f:close(); return data
end
local mime={html="text/html; charset=utf-8",css="text/css; charset=utf-8",js="application/javascript; charset=utf-8",svg="image/svg+xml",webp="image/webp",png="image/png",jpg="image/jpeg",jpeg="image/jpeg"}
local reasons={[200]="OK",[204]="No Content",[400]="Bad Request",[403]="Forbidden",[404]="Not Found",[405]="Method Not Allowed",[409]="Conflict",[413]="Payload Too Large",[500]="Internal Server Error"}
local function response(status,body,contentType,cacheControl)
    body=body or ""
    local headers={
        "HTTP/1.1 "..tostring(status).." "..(reasons[status] or "Error"),
        "Content-Type: "..(contentType or "text/plain; charset=utf-8"),
        "Content-Length: "..tostring(#body),
        "Connection: close",
        "Cache-Control: "..(cacheControl or "no-store"),
        "X-Content-Type-Options: nosniff",
        "Referrer-Policy: no-referrer",
        "Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; object-src 'none'"
    }
    return table.concat(headers,"\r\n").."\r\n\r\n"..body
end
local function jsonResponse(status,value) return response(status,encode(value),"application/json; charset=utf-8") end
local function queryString(v)
    local out={}
    for pair in tostring(v or ""):gmatch("[^&]+") do local k,x=pair:match("^([^=]+)=?(.*)$"); if k then out[k]=x end end
    return out
end
local function parseRequest(buffer)
    local split=buffer:find("\r\n\r\n",1,true)
    if not split then return nil,#buffer>16384 and "headers_too_large" or "incomplete" end
    local lines={}
    for line in (buffer:sub(1,split-1).."\r\n"):gmatch("(.-)\r\n") do lines[#lines+1]=line end
    if #lines>80 then return nil,"too_many_headers" end
    local method,target=tostring(lines[1] or ""):match("^(%u+)%s+([^%s]+)%s+HTTP/%d%.%d$")
    if not method then return nil,"bad_request_line" end
    local headers={}
    for i=2,#lines do local k,v=lines[i]:match("^([^:]+):%s*(.*)$"); if not k then return nil,"bad_header" end; headers[k:lower()]=v end
    if headers["transfer-encoding"] then return nil,"transfer_encoding_not_allowed" end
    local size=tonumber(headers["content-length"] or "0") or 0
    if size<0 or size>65536 then return nil,"body_too_large" end
    local start=split+4
    if #buffer-start+1<size then return nil,"incomplete" end
    local path,query=target:match("^([^?]*)%??(.*)$")
    return {method=method,path=path or "/",query=queryString(query),headers=headers,body=buffer:sub(start,start+size-1)}
end
local function validHost(req)
    local h=tostring(req.headers.host or "")
    return h=="127.0.0.1:"..tostring(port) or h=="localhost:"..tostring(port)
end
local function validToken(req) return tostring(req.headers["x-arzmarket-token"] or "")==token end
local function validOrigin(req)
    local o=tostring(req.headers.origin or "")
    -- Arizona CEF/Chromium can report an empty or null Origin for injected frames.
    -- The bridge is bound to loopback and still requires the per-session secret token.
    if o=="" or o=="null" then return true end
    return o=="http://127.0.0.1:"..tostring(port) or o=="http://localhost:"..tostring(port)
end
local function safeStatic(path)
    if path:find("..",1,true) or path:find("\\",1,true) or path:find("%%00") or path:sub(1,1)=="/" then return nil end
    return path:match("^[%w%._%-%/]+$") and path or nil
end

local function normalizePriceItemName(name)
    name=tostring(name or ""):gsub("{......}",""):gsub("^%s+",""):gsub("%s+$","")
    return name:gsub("%s+"," ")
end
local function findPriceHistory(source,itemName)
    if type(source)~="table" then return nil end
    local exact=normalizePriceItemName(itemName)
    if exact~="" and type(source[exact])=="table" then return source[exact] end
    local base=normalizePriceItemName(exact:gsub("%(%+%d+%)",""))
    if base~=exact and type(source[base])=="table" then return source[base] end
    local wanted=base:gsub("%s+","")
    if wanted=="" then return nil end
    for key,value in pairs(source) do
        local normalized=normalizePriceItemName(key):gsub("%(%+%d+%)",""):gsub("%s+","")
        if normalized==wanted and type(value)=="table" then return value end
    end
end
local function getPriceStats(side,item,currency)
    if not ctx or type(ctx.getPriceData)~="function" or type(item)~="table" then
        return {available=false}
    end
    local ok,data=callCore(ctx.getPriceData)
    if not ok or type(data)~="table" then return {available=false} end
    local sourceKey
    if side=="sell" then sourceKey=currency=="VC" and "sell_vc" or "sell_"
    else sourceKey=currency=="VC" and "buy_vc" or "buy_" end
    local history=findPriceHistory(data[sourceKey],item.name or item.item or "")
    if type(history)~="table" or type(history.list)~="table" then return {available=false} end
    local totalValue,totalCount,minPrice,maxPrice,samples=0,0,nil,nil,0
    for _,row in pairs(history.list) do
        if type(row)=="table" then
            local count=tonumber(row[2])
            local total=tonumber(row[3])
            if count and count>0 and total and total>0 then
                local unit=total/count
                totalValue=totalValue+total
                totalCount=totalCount+count
                samples=samples+1
                if not minPrice or unit<minPrice then minPrice=unit end
                if not maxPrice or unit>maxPrice then maxPrice=unit end
            end
        end
    end
    if totalCount<=0 or samples<=0 then return {available=false} end
    return {
        available=true,
        average=math.floor(totalValue/totalCount),
        min=math.floor(minPrice or 0),
        max=math.floor(maxPrice or 0),
        samples=samples,
        currency=currency=="VC" and "VC" or "SA"
    }
end

local function averagePriceEntryMap(history)
    local out={}
    if type(history)~="table" or type(history.list)~="table" then return out end
    for _,row in pairs(history.list) do
        if type(row)=="table" then
            local date=tostring(row[1] or "")
            local count=tonumber(row[2])
            local total=tonumber(row[3])
            if date~="" and count and count>0 and total and total>0 then
                out[date]={date=date,count=math.floor(count),total=math.floor(total),unit=math.floor(total/count)}
            end
        end
    end
    return out
end
local function averagePriceHistoryRows(saHistory,vcHistory,averageRate)
    local sa=averagePriceEntryMap(saHistory)
    local vc=averagePriceEntryMap(vcHistory)
    local dates={}
    local seen={}
    for date in pairs(sa) do if not seen[date] then dates[#dates+1]=date; seen[date]=true end end
    for date in pairs(vc) do if not seen[date] then dates[#dates+1]=date; seen[date]=true end end
    table.sort(dates,function(a,b) return tostring(a)>tostring(b) end)
    local out={}
    local maxRows=80
    for i=1,math.min(#dates,maxRows) do
        local date=dates[i]
        local saRow=sa[date]
        local vcRow=vc[date]
        local row={date=date,sa=saRow,vc=vcRow}
        if vcRow and averageRate>1 then row.vc_to_sa=math.floor((vcRow.unit or 0)*averageRate) end
        if saRow and averageRate>1 then row.sa_to_vc=math.floor((saRow.unit or 0)/averageRate) end
        out[#out+1]=row
    end
    return out
end
local function getAveragePriceDetails(itemName)
    if not ctx or type(ctx.getPriceData)~="function" then return {available=false,name=toUtf8(itemName or "")} end
    itemName=normalizePriceItemName(itemName):gsub("%(%+%d+%)",""):gsub("^%s+",""):gsub("%s+$","")
    local ok,data=callCore(ctx.getPriceData)
    if not ok or type(data)~="table" then return {available=false,name=toUtf8(itemName)} end
    local meta={}
    if type(ctx.getAveragePriceMeta)=="function" then
        local okMeta,value=callCore(ctx.getAveragePriceMeta,itemName)
        if okMeta and type(value)=="table" then meta=value end
    end
    local buyRate=math.max(1,tonumber(meta.buy_vc_rate) or 1)
    local sellRate=math.max(1,tonumber(meta.sell_vc_rate) or 1)
    local averageRate=math.max(1,(buyRate+sellRate)/2)
    local buySa=findPriceHistory(data.buy_,itemName)
    local buyVc=findPriceHistory(data.buy_vc,itemName)
    local sellSa=findPriceHistory(data.sell_,itemName)
    local sellVc=findPriceHistory(data.sell_vc,itemName)
    local buyRows=averagePriceHistoryRows(buySa,buyVc,averageRate)
    local sellRows=averagePriceHistoryRows(sellSa,sellVc,averageRate)
    return {
        available=#buyRows>0 or #sellRows>0,
        name=toUtf8(itemName),
        configured_buy=math.floor(tonumber(meta.configured_buy) or 0),
        configured_sell=math.floor(tonumber(meta.configured_sell) or 0),
        buy_vc_rate=buyRate,
        sell_vc_rate=sellRate,
        average_rate=averageRate,
        buy=buyRows,
        sell=sellRows
    }
end

local function doAction(req)
    if req.method~="POST" then return response(405,"method_not_allowed") end
    if not validToken(req) or not validOrigin(req) then return response(403,"forbidden") end
    bridgePerf.htmlToLuaMessages=bridgePerf.htmlToLuaMessages+1
    local request=decode(req.body)
    if type(request)~="table" or type(request.action)~="string" then return jsonResponse(400,{ok=false,error="invalid_json"}) end
    local action=request.action
    local data=type(request.payload)=="table" and request.payload or {}
    local side=data.side=="sell" and "sell" or "buy"
    local requestedPage=data.page=="settings" and "settings" or data.page=="logs" and "logs" or data.page=="marketplace" and "marketplace" or data.page=="mods" and "mods" or data.page=="storage" and "storage" or data.side=="sell" and "sell" or data.side=="buy" and "buy" or currentPage
    if requestedPage~="buy" and requestedPage~="sell" and requestedPage~="settings" and requestedPage~="logs" and requestedPage~="marketplace" and requestedPage~="mods" and requestedPage~="storage" then requestedPage="buy" end
    if action=="ui.close" then
        currentPage=requestedPage
        suppressAutoOpen=true
        -- Do not destroy the iframe from inside the request that originated in it.
        -- Schedule removal for the next MoonLoader frame so the HTTP response can finish.
        if ctx and ctx.lua_thread and type(ctx.lua_thread.create)=="function" then
            ctx.lua_thread.create(function()
                wait(0)
                removeIframe()
                setMenuVisible(false)
            end)
        else
            removeIframe()
            setMenuVisible(false)
        end
        return jsonResponse(200,{ok=true})
    elseif action=="ui.switch_mode" then
        currentPage=requestedPage
        suppressAutoOpen=true

        local pageId=requestedPage=="sell" and 1 or requestedPage=="settings" and 3 or requestedPage=="logs" and 4
            or requestedPage=="marketplace" and 5 or requestedPage=="mods" and 7 or requestedPage=="storage" and 8 or 2
        local switched=false

        -- Change Lua state synchronously while the HTTP request is still alive.
        -- Only iframe destruction is delayed until after the response.
        if ctx and type(ctx.activateLuaPage)=="function" then
            local ok,result=callCore(ctx.activateLuaPage,pageId)
            switched=ok and result~=false
        else
            switched=selectLuaPage(requestedPage)
            if switched then
                if ctx and type(ctx.setPreferredInterfaceMode)=="function" then callCore(ctx.setPreferredInterfaceMode,"lua") end
                setMenuVisible(true)
            end
        end

        if not switched then
            suppressAutoOpen=false
            return jsonResponse(500,{ok=false,mode="html",page=requestedPage,error="lua_page_unavailable"})
        end

        if ctx and ctx.lua_thread and type(ctx.lua_thread.create)=="function" then
            ctx.lua_thread.create(function()
                -- Yield exactly one MoonLoader frame. The HTML child has already
                -- hidden itself via postMessage, so there is no visible overlap,
                -- while the current HTTP response still gets a chance to flush.
                wait(0)
                removeIframe()
            end)
        else
            removeIframe()
        end
        return jsonResponse(200,{ok=true,mode="lua",page=requestedPage})
    elseif action=="ui.navigate" then
        currentPage=requestedPage
        local previewRequest=data.preview==true
        if not previewRequest and ctx and type(ctx.assistantPageChanged)=="function" then callCore(ctx.assistantPageChanged,requestedPage) end
        if not previewRequest and revision[requestedPage] then revision[requestedPage]=revision[requestedPage]+1 end
        if not previewRequest and requestedPage=="marketplace" and ctx and type(ctx.ensureMarketplaceLoaded)=="function" then callCore(ctx.ensureMarketplaceLoaded) end
        return jsonResponse(200,{ok=true,page=requestedPage,preview=previewRequest})
    elseif action=="assistant.action" then
        if not ctx or type(ctx.assistantAction)~="function" then return jsonResponse(400,{ok=false,error="assistant_unavailable"}) end
        local assistantAction=tostring(data.assistantAction or "")
        local ok,result,assistantErr=callCore(ctx.assistantAction,assistantAction,data)
        local success=ok and result~=false
        if success then
            for key,value in pairs(revision) do revision[key]=(tonumber(value) or 0)+1 end
        end
        local snapshot=nil
        if type(ctx.getAssistantSnapshot)=="function" then
            local snapOk,snap=callCore(ctx.getAssistantSnapshot,requestedPage,"html")
            if snapOk and type(snap)=="table" then snapshot=snap end
        end
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and assistantErr or tostring(result)),assistant=snapshot})
    elseif action=="marketplace.unban" then
        if not ctx or type(ctx.requestMarketplaceUnban)~="function" then return jsonResponse(400,{ok=false,error="unban_unavailable"}) end
        local ok,result,coreErr=callCore(ctx.requestMarketplaceUnban)
        local success=ok and result~=false
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="marketplace.refresh" then
        if not ctx or type(ctx.refreshMarketplace)~="function" then return jsonResponse(400,{ok=false,error="marketplace_unavailable"}) end
        local ok,result,coreErr=callCore(ctx.refreshMarketplace,data.serverIndex)
        local success=ok and result~=false
        fingerprints.marketplace=""
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="marketplace.server.select" then
        if not ctx or type(ctx.refreshMarketplace)~="function" then return jsonResponse(400,{ok=false,error="marketplace_unavailable"}) end
        local ok,result,coreErr=callCore(ctx.refreshMarketplace,data.index)
        local success=ok and result~=false
        fingerprints.marketplace=""
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="marketplace.sort" then
        if not ctx or type(ctx.setMarketplaceSortMode)~="function" then return jsonResponse(400,{ok=false,error="marketplace_unavailable"}) end
        local ok,value=callCore(ctx.setMarketplaceSortMode,data.mode)
        fingerprints.marketplace=""
        return jsonResponse(ok and 200 or 400,{ok=ok,mode=ok and value or nil,error=ok and nil or tostring(value)})
    elseif action=="marketplace.find" then
        if not ctx or type(ctx.findMarketplaceStall)~="function" then return jsonResponse(400,{ok=false,error="marketplace_unavailable"}) end
        local ok,result,coreErr=callCore(ctx.findMarketplaceStall,data.uid,data.serverId)
        local success=ok and result~=false
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="marketplace.auth.open" then
        if not ctx or type(ctx.openMarketplaceAuthProvider)~="function" then return jsonResponse(400,{ok=false,error="marketplace_unavailable"}) end
        local ok,result,coreErr=callCore(ctx.openMarketplaceAuthProvider,tostring(data.provider or "telegram"))
        local success=ok and result~=false
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="ui.window.save" then
        local ok,result=saveWindowState(data)
        return jsonResponse(ok and 200 or 400,{ok=ok,window=ok and result or nil,error=ok and nil or result})
    elseif action=="ui.window.reset" then
        htmlWindowState={}
        if htmlWindowStatePath then pcall(os.remove,htmlWindowStatePath) end
        return jsonResponse(200,{ok=true,window=htmlWindowState})
    elseif action=="mods.set" then
        if not ctx or type(ctx.setModsValue)~="function" then return jsonResponse(400,{ok=false,error="mods_unavailable"}) end
        local ok,result,coreErr=callCore(ctx.setModsValue,tostring(data.key or ""),data.value)
        local success=ok and result~=false
        fingerprints.mods=""; fingerprints.settings=""; settingsSnapshotCache.at=0
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="mods.manual_purchased" then
        if not ctx or type(ctx.toggleManualPurchasedListing)~="function" then return jsonResponse(400,{ok=false,error="manual_purchased_unavailable"}) end
        local ok,result,detail=callCore(ctx.toggleManualPurchasedListing)
        local success=ok and result~=false
        fingerprints.mods=""; fingerprints.settings=""; settingsSnapshotCache.at=0
        return jsonResponse(success and 200 or 400,{ok=success,state=success and detail or nil,error=success and nil or (ok and detail or tostring(result))})
    elseif action=="mods.telegram" then
        if not ctx or type(ctx.openModsTelegram)~="function" then return jsonResponse(400,{ok=false,error="open_url_unavailable"}) end
        local ok,result,coreErr=callCore(ctx.openModsTelegram)
        local success=ok and result~=false
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="mods.launcher.download" then
        if not ctx or type(ctx.downloadMainDonorLauncher)~="function" then return jsonResponse(400,{ok=false,error="launcher_download_unavailable"}) end
        local ok,result,coreErr=callCore(ctx.downloadMainDonorLauncher)
        local success=ok and result~=false
        fingerprints.mods=""
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="settings.set" then
        if not ctx or type(ctx.setSettingsValue)~="function" then return jsonResponse(400,{ok=false,error="settings_unavailable"}) end
        local value=data.value
        if type(value)=="string" then value=fromUtf8(value) end
        local ok,result,coreErr=callCore(ctx.setSettingsValue,tostring(data.key or ""),value)
        local success=ok and result~=false
        fingerprints.settings=""; settingsSnapshotCache.at=0
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="settings.theme.select" then
        if not ctx or type(ctx.selectSettingsTheme)~="function" then return jsonResponse(400,{ok=false,error="theme_unavailable"}) end
        local ok,result,coreErr=callCore(ctx.selectSettingsTheme,tostring(data.key or ""))
        local success=ok and result~=false
        fingerprints.settings=""; settingsSnapshotCache.at=0
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="settings.global_palette.update" then
        if not ctx or type(ctx.setSettingsGlobalPalette)~="function" then return jsonResponse(400,{ok=false,error="palette_unavailable"}) end
        local payload={
            enabled=data.enabled==true,
            base=tostring(data.base or ""),
            depth=tonumber(data.depth),
            saturation=tonumber(data.saturation),
            contrast=tonumber(data.contrast),
            glow=tonumber(data.glow),
            picker_hue=tonumber(data.picker_hue),
            picker_saturation=tonumber(data.picker_saturation),
            picker_value=tonumber(data.picker_value),
            reset=data.reset==true
        }
        local ok,result,coreErr=callCore(ctx.setSettingsGlobalPalette,payload)
        local success=ok and result~=false
        fingerprints.settings=""; settingsSnapshotCache.at=0
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="settings.palette.enable" then
        if not ctx or type(ctx.setSettingsPaletteEnabled)~="function" then return jsonResponse(400,{ok=false,error="palette_unavailable"}) end
        local ok,result,coreErr=callCore(ctx.setSettingsPaletteEnabled,data.value==true)
        local success=ok and result~=false
        fingerprints.settings=""; settingsSnapshotCache.at=0
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="settings.palette.color" then
        if not ctx or type(ctx.setSettingsPaletteColor)~="function" then return jsonResponse(400,{ok=false,error="palette_unavailable"}) end
        local ok,result,coreErr=callCore(ctx.setSettingsPaletteColor,tostring(data.key or ""),tostring(data.hex or ""))
        local success=ok and result~=false
        fingerprints.settings=""; settingsSnapshotCache.at=0
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="settings.palette.reset" then
        if not ctx or type(ctx.resetSettingsPalette)~="function" then return jsonResponse(400,{ok=false,error="palette_unavailable"}) end
        local ok,result,coreErr=callCore(ctx.resetSettingsPalette,tostring(data.scope or "all"),tostring(data.key or ""))
        local success=ok and result~=false
        fingerprints.settings=""; settingsSnapshotCache.at=0
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="settings.scale.apply" then
        if not ctx or type(ctx.applySettingsMenuScale)~="function" then return jsonResponse(400,{ok=false,error="scale_unavailable"}) end
        local ok,result,coreErr=callCore(ctx.applySettingsMenuScale,data.value)
        local success=ok and result~=false
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="settings.config.create" then
        if not ctx or type(ctx.createSettingsTradeConfig)~="function" then return jsonResponse(400,{ok=false,error="config_unavailable"}) end
        local sideValue=data.side=="sell" and "sell" or "buy"
        local ok,result,coreErr=callCore(ctx.createSettingsTradeConfig,sideValue,fromUtf8(data.name or ""))
        local success=ok and result~=false
        fingerprints.settings=""; settingsSnapshotCache.at=0; fingerprints[sideValue]=""
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="settings.config.delete" then
        if not ctx or type(ctx.deleteSettingsTradeConfig)~="function" then return jsonResponse(400,{ok=false,error="config_unavailable"}) end
        local sideValue=data.side=="sell" and "sell" or "buy"
        local ok,result,coreErr=callCore(ctx.deleteSettingsTradeConfig,sideValue,fromUtf8(data.name or ""))
        local success=ok and result~=false
        fingerprints.settings=""; settingsSnapshotCache.at=0; fingerprints[sideValue]=""
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="settings.config.merge" then
        if not ctx or type(ctx.mergeSettingsBuyConfigs)~="function" then return jsonResponse(400,{ok=false,error="merge_unavailable"}) end
        local files={}
        if type(data.files)=="table" then for i=1,#data.files do files[i]=fromUtf8(data.files[i]) end end
        local ok,result,coreErr=callCore(ctx.mergeSettingsBuyConfigs,fromUtf8(data.name or ""),files)
        local success=ok and result~=false
        fingerprints.settings=""; settingsSnapshotCache.at=0; fingerprints.buy=""
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="settings.config.convert" then
        if not ctx or type(ctx.convertSettingsLegacyConfig)~="function" then return jsonResponse(400,{ok=false,error="convert_unavailable"}) end
        local sideValue=data.side=="sell" and "sell" or "buy"
        local ok,result,coreErr=callCore(ctx.convertSettingsLegacyConfig,sideValue,fromUtf8(data.name or ""))
        local success=ok and result~=false
        fingerprints.settings=""; settingsSnapshotCache.at=0; fingerprints[sideValue]=""
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="settings.telegram.test" then
        if not ctx or type(ctx.testTelegramSettings)~="function" then return jsonResponse(400,{ok=false,error="telegram_unavailable"}) end
        local ok,result,coreErr=callCore(ctx.testTelegramSettings)
        local success=ok and result~=false
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="storage.scan" then
        local finder=safeStorageFinder()
        if not finder then return jsonResponse(400,{ok=false,error="storage_unavailable"}) end
        local stateValue={}
        if type(finder.getState)=="function" then
            local ok,value=callCore(finder.getState)
            if ok and type(value)=="table" then stateValue=value end
        end
        if stateValue.player_inventory_visible==true then
            storageRefreshRequested=true
            return jsonResponse(200,{ok=true,mode="inventory_auto"})
        end
        if type(finder.requestExternalScan)~="function" then return jsonResponse(400,{ok=false,error="storage_scan_unavailable"}) end
        local kind=tostring(data.kind or "")
        if kind=="all" or kind=="player_inventory" then kind="" end
        local ok,result=callCore(finder.requestExternalScan,kind~="" and kind or nil)
        storageRefreshRequested=true
        local success=ok and result~=false
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or "open_storage_first"})
    elseif action=="trade.currency.toggle" then
        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end
        if not ctx or type(ctx.toggleTradeCurrency)~="function" then return jsonResponse(400,{ok=false,error="currency_unavailable"}) end
        local ok,result=callCore(ctx.toggleTradeCurrency)
        fingerprints.buy=""; fingerprints.sell=""
        return jsonResponse(ok and result~=false and 200 or 400,{ok=ok and result~=false,currency=ok and result or nil,error=ok and result~=false and nil or tostring(result)})
    elseif action=="trade.scan.toggle" then
        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end
        if not ctx or type(ctx.toggleTradeScan)~="function" then return jsonResponse(400,{ok=false,error="scan_unavailable"}) end
        local ok,result=callCore(ctx.toggleTradeScan,side)
        sourceCache[side].at=0; fingerprints[side]=""
        return jsonResponse(ok and 200 or 400,{ok=ok,active=ok and result==true or false,error=ok and nil or tostring(result)})
    elseif action=="buy.source.refresh" then
        if side~="buy" then return jsonResponse(400,{ok=false,error="buy_only"}) end
        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end
        if not ctx or type(ctx.refreshBuySource)~="function" then return jsonResponse(400,{ok=false,error="refresh_unavailable"}) end
        local ok,result=callCore(ctx.refreshBuySource)
        sourceCache.buy.at=0; fingerprints.buy=""
        return jsonResponse(ok and result~=false and 200 or 400,{ok=ok and result~=false,error=ok and result~=false and nil or tostring(result)})
    elseif action=="prices.lookup" then
        local rawName=fromUtf8(tostring(data.name or ""))
        if rawName=="" then return jsonResponse(400,{ok=false,error="item_name_missing"}) end
        local ok,result=callCore(getAveragePriceDetails,rawName)
        if not ok then return jsonResponse(500,{ok=false,error=tostring(result)}) end
        return jsonResponse(200,{ok=true,data=result})
    elseif action=="prices.download" then
        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end
        if not ctx or type(ctx.downloadAveragePrices)~="function" then return jsonResponse(400,{ok=false,error="prices_unavailable"}) end
        local ok,result=callCore(ctx.downloadAveragePrices)
        return jsonResponse(ok and result~=false and 200 or 400,{ok=ok and result~=false,error=ok and result~=false and nil or tostring(result)})
    elseif action=="prices.stats" then
        local item,_,findErr=findItem(side,data.identity)
        if not item then return jsonResponse(findErr=="stale_state" and 409 or 400,{ok=false,error=findErr}) end
        local currency=data.currency=="VC" and "VC" or "SA"
        return jsonResponse(200,{ok=true,data=getPriceStats(side,item,currency)})
    elseif action=="trade.config.load" then
        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end
        if not ctx or type(ctx.loadTradeConfig)~="function" then return jsonResponse(400,{ok=false,error="config_loader_unavailable"}) end
        local requestedName=fromUtf8(data.name or "")
        local ok,result,err=callCore(ctx.loadTradeConfig,side,requestedName)
        local success=ok and result~=false
        if success then clearTradeDraft(side) end
        sourceCache[side].at=0
        fingerprints[side]=""
        fingerprints.settings=""; settingsSnapshotCache.at=0
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and err or tostring(result))})
    elseif action=="trade.list.clear" then
        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end
        if not ctx or type(ctx.clearTradeList)~="function" then return jsonResponse(400,{ok=false,error="clear_unavailable"}) end
        local ok,result,coreErr=callCore(ctx.clearTradeList,side)
        local success=ok and result~=false
        if success and configName(side)=="" then
            local buy,sell=lists()
            local list=side=="buy" and buy or sell
            local saved,saveErr=saveTradeDraft(side,list)
            if not saved then return jsonResponse(500,{ok=false,error=saveErr}) end
        end
        fingerprints[side]=""
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="trade.item.undo" then
        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end
        if not ctx or type(ctx.undoTradeDelete)~="function" then return jsonResponse(400,{ok=false,error="undo_unavailable"}) end
        local ok,result,coreErr=callCore(ctx.undoTradeDelete,side)
        local success=ok and result~=false
        if success and configName(side)=="" then
            local buy,sell=lists()
            local list=side=="buy" and buy or sell
            local saved,saveErr=saveTradeDraft(side,list)
            if not saved then return jsonResponse(500,{ok=false,error=saveErr}) end
        end
        fingerprints[side]=""
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="buy.budget.preview" then
        if side~="buy" then return jsonResponse(400,{ok=false,error="buy_only"}) end
        if not ctx or type(ctx.previewBuyBudget)~="function" then return jsonResponse(400,{ok=false,error="budget_unavailable"}) end
        local ok,result,dataOrErr=callCore(ctx.previewBuyBudget,data.budget)
        local success=ok and result~=false
        return jsonResponse(success and 200 or 400,{ok=success,data=success and dataOrErr or nil,error=success and nil or (ok and dataOrErr or tostring(result))})
    elseif action=="buy.budget.apply" then
        if side~="buy" then return jsonResponse(400,{ok=false,error="buy_only"}) end
        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end
        if not ctx or type(ctx.distributeBuyBudget)~="function" then return jsonResponse(400,{ok=false,error="budget_unavailable"}) end
        local ok,result,dataOrErr=callCore(ctx.distributeBuyBudget,data.budget)
        local success=ok and result~=false
        fingerprints.buy=""
        return jsonResponse(success and 200 or 400,{ok=success,data=success and dataOrErr or nil,error=success and nil or (ok and dataOrErr or tostring(result))})
    elseif action=="buy.continue.toggle" then
        if side~="buy" then return jsonResponse(400,{ok=false,error="buy_only"}) end
        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end
        if not ctx or type(ctx.setBuyContinueMode)~="function" or type(ctx.getBuyContinueMode)~="function" then return jsonResponse(400,{ok=false,error="continue_unavailable"}) end
        local current=false
        local readOk,readValue=callCore(ctx.getBuyContinueMode)
        if readOk then current=readValue==true end
        local ok,result=callCore(ctx.setBuyContinueMode,not current)
        fingerprints.buy=""
        return jsonResponse(ok and 200 or 400,{ok=ok,active=ok and result==true or false,error=ok and nil or tostring(result)})
    elseif action=="trade.item.update" then
        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end
        local ok,err=updateItem(side,data)
        return jsonResponse(ok and 200 or (err=="stale_state" and 409 or 400),{ok=ok,error=err})
    elseif action=="trade.item.remove" then
        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end
        local ok,err=removeItem(side,data)
        return jsonResponse(ok and 200 or (err=="stale_state" and 409 or 400),{ok=ok,error=err})
    elseif action=="trade.item.add" then
        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end
        local ok,err=addItem(side,data)
        return jsonResponse(ok and 200 or 400,{ok=ok,error=err})
    elseif action=="trade.filter.category_order" then
        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end
        if not ctx or type(ctx.setTradeFilterCategoryOrder)~="function" then
            return jsonResponse(400,{ok=false,error="filter_order_unavailable"})
        end
        local order=type(data.order)=="table" and data.order or nil
        local ok,result,coreErr=callCore(ctx.setTradeFilterCategoryOrder,side,order)
        local success=ok and result~=false
        fingerprints[side]=""
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="trade.item.category" then
        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end
        if not ctx or type(ctx.setTradeItemCategory)~="function" then
            return jsonResponse(400,{ok=false,error="item_category_unavailable"})
        end
        local item,_,findErr=findItem(side,data.identity)
        if not item then return jsonResponse(findErr=="stale_state" and 409 or 400,{ok=false,error=findErr}) end
        local category=tostring(data.category or "auto")
        local ok,result,coreErr=callCore(ctx.setTradeItemCategory,side,item,category)
        local success=ok and result~=false
        fingerprints[side]=""
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="buy.average.apply" then
        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end
        if type(applyAveragePricesToBuyList)~="function" then return jsonResponse(400,{ok=false,error="average_unavailable"}) end
        local ok,result=callCore(applyAveragePricesToBuyList)
        fingerprints.buy=""
        return jsonResponse(ok and result~=false and 200 or 400,{ok=ok and result~=false,error=not ok and tostring(result) or (result==false and "average_failed" or nil)})
    elseif action=="trade.start" then
        local active=select(1,automationState(side))
        if active then
            if not ctx or type(ctx.cancelTrade)~="function" then return jsonResponse(400,{ok=false,error="cancel_unavailable"}) end
            local ok,result=callCore(ctx.cancelTrade); fingerprints[side]=""
            local success=ok and result~=false
            return jsonResponse(success and 200 or 400,{ok=success,cancelled=success,error=success and nil or tostring(result)})
        end
        if tradeBusy() then return jsonResponse(409,{ok=false,error="other_trade_active"}) end
        if not ctx or type(ctx.startTrade)~="function" then return jsonResponse(400,{ok=false,error="start_unavailable"}) end
        local ok,result=callCore(ctx.startTrade,side)
        local success=ok and result~=false
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or tostring(result)})
    end
    return jsonResponse(400,{ok=false,error="unknown_action"})
end
local function handle(req)
    if not validHost(req) then return response(403,"forbidden") end
    if req.path=="/health" then
        local iconStatus=itemIcons and itemIcons.getStatus and itemIcons.getStatus() or {}
        return jsonResponse(200,{ok=true,port=port,htmlOpen=htmlOpen,page=currentPage,tradeBusy=tradeBusy(),icons=iconStatus})
    end
    if req.path=="/api/perf" then
        if req.method~="GET" then return response(405,"method_not_allowed") end
        if not validToken(req) then return response(403,"forbidden") end
        local snapshot={}
        for key,value in pairs(bridgePerf) do snapshot[key]=value end
        snapshot.elapsedMs=math.max(0,nowMs()-bridgePerf.startedAt)
        snapshot.averageStateBuildMs=bridgePerf.stateBuilds>0 and bridgePerf.totalStateBuildMs/bridgePerf.stateBuilds or 0
        snapshot.activeWorkers=(requestWorkerRunning and 1 or 0)+(storageWorkerRunning and 1 or 0)
        snapshot.pendingRequests=#requestQueue
        local clientCount=0; for _ in pairs(clients) do clientCount=clientCount+1 end
        snapshot.activeClients=clientCount
        return jsonResponse(200,{ok=true,performance=snapshot})
    end
    if req.path=="/ui" then
        if req.method~="GET" then return response(405,"method_not_allowed") end
        local html=readFile(htmlRoot.."\\index.html")
        return html and response(200,html:gsub("__ARZMARKET_TOKEN__",token),mime.html) or response(404,"ui_missing")
    end
    if req.path:sub(1,8)=="/static/" then
        if req.method~="GET" then return response(405,"method_not_allowed") end
        local rel=safeStatic(req.path:sub(9)); if not rel then return response(403,"forbidden") end
        local body=readFile(htmlRoot.."\\"..rel:gsub("/","\\"),true); if not body then return response(404,"not_found") end
        return response(200,body,mime[rel:match("%.([%w]+)$") or ""] or "application/octet-stream","no-store")
    end
    if req.path=="/api/state" then
        if req.method~="GET" then return response(405,"method_not_allowed") end
        if not validToken(req) then return response(403,"forbidden") end
        bridgePerf.luaToHtmlRequests=bridgePerf.luaToHtmlRequests+1
        local requested=req.query.page=="settings" and "settings" or req.query.page=="logs" and "logs" or req.query.page=="marketplace" and "marketplace" or req.query.page=="mods" and "mods" or req.query.page=="storage" and "storage" or req.query.page=="sell" and "sell" or "buy"
        local marketplaceCacheKey=nil
        if requested=="marketplace" then
            if ctx and type(ctx.pumpMarketplaceHtml)=="function" then callCore(ctx.pumpMarketplaceHtml) end
            if ctx and type(ctx.getMarketplaceRevisionKey)=="function" then
                local keyOk,keyValue=callCore(ctx.getMarketplaceRevisionKey)
                if keyOk then marketplaceCacheKey=tostring(keyValue or "") end
            end
            if marketplaceCacheKey~=nil then
                local assistantKey=""
                if ctx and type(ctx.getAssistantSnapshot)=="function" then
                    local assistantOk,assistantValue=callCore(ctx.getAssistantSnapshot,requested,"html")
                    if assistantOk and type(assistantValue)=="table" then assistantKey=encode(assistantValue) end
                end
                marketplaceCacheKey=table.concat({
                    marketplaceCacheKey,
                    tostring(currentHtmlThemeKey() or ""),
                    encode(currentHtmlThemeProfile() or {}),
                    tostring(currentMenuScalePercent() or 100),
                    encode(htmlWindowState or {}),
                    assistantKey
                },"\30")
            end
        end
        local cachedState=stateResponseCache[requested]
        if requested=="marketplace" and cachedState and marketplaceCacheKey~=nil and cachedState.sourceKey==marketplaceCacheKey then
            if tonumber(req.query.since)==tonumber(cachedState.revision) then return response(204,"","application/json; charset=utf-8") end
            return response(200,cachedState.body,"application/json; charset=utf-8","no-store")
        end
        if not focusIsStable() then
            if cachedState then
                if tonumber(req.query.since)==tonumber(cachedState.revision) then return response(204,"","application/json; charset=utf-8") end
                return response(200,cachedState.body,"application/json; charset=utf-8","no-store")
            end
            return response(204,"","application/json; charset=utf-8")
        end
        local stateBuildStarted=nowMs()
        local value=stateFor(requested)
        local stateBuildElapsed=math.max(0,nowMs()-stateBuildStarted)
        bridgePerf.stateBuilds=bridgePerf.stateBuilds+1
        bridgePerf.totalStateBuildMs=bridgePerf.totalStateBuildMs+stateBuildElapsed
        bridgePerf.maxStateBuildMs=math.max(bridgePerf.maxStateBuildMs,stateBuildElapsed)
        value.common=type(value.common)=="table" and value.common or {}
        value.common.htmlThemeKey=currentHtmlThemeKey()
        value.common.htmlThemeProfile=currentHtmlThemeProfile()
        if ctx and type(ctx.getAssistantSnapshot)=="function" then
            local okAssistant,assistant=callCore(ctx.getAssistantSnapshot,requested,"html")
            if okAssistant and type(assistant)=="table" then value.assistant=assistant end
        end
        local body=encode(value)
        stateResponseCache[requested]={revision=tonumber(value.revision) or 0,body=body,sourceKey=marketplaceCacheKey}
        if tonumber(req.query.since)==tonumber(value.revision) then return response(204,"","application/json; charset=utf-8") end
        bridgePerf.luaToHtmlResponses=bridgePerf.luaToHtmlResponses+1
        return response(200,body,"application/json; charset=utf-8","no-store")
    end
    if req.path=="/api/action" then return doAction(req) end
    local size,id=req.path:match("^/api/icon/(%d+)/(%d+)%.webp$")
    if size and id then
        if size~="24" and size~="48" and size~="256" then return response(404,"not_found") end
        if req.method~="GET" then return response(405,"method_not_allowed") end
        if not validToken(req) and tostring(req.query.token or "")~=token then return response(403,"forbidden") end
        if not itemIcons or type(itemIcons.getIcon)~="function" then return response(404,"icon_unavailable") end
        local ok,dataOrErr,extra=callCore(itemIcons.getIcon,size,id)
        if not ok or not dataOrErr then return response(404,tostring(ok and extra or dataOrErr)) end
        return response(200,dataOrErr,"image/webp","private, max-age=86400")
    end
    return response(404,"not_found")
end

local function closeClient(entry)
    if not entry then return end
    if entry.socket then pcall(function() entry.socket:close() end) end
    clients[entry]=nil
end

local function queueResponse(entry,out)
    if not entry or not clients[entry] then return false end
    entry.processing=false
    entry.out=out
    entry.outPos=1
    entry.deadline=nowMs()+10000
    return true
end

local function flushClient(entry)
    if not entry or not entry.out then return false end
    local sent,err,last=entry.socket:send(entry.out,entry.outPos)
    local endPos=sent or last
    if endPos and endPos>=entry.outPos then entry.outPos=endPos+1 end
    if entry.outPos>#entry.out then closeClient(entry); return true end
    if err and err~="timeout" then closeClient(entry); return true end
    return false
end

-- Network I/O and yieldable ArzMarket callbacks must not share the same
-- MoonLoader coroutine. The network thread only accepts/reads/writes sockets.
-- Requests are executed serially by a separate worker, where handle() is free
-- to call callbacks that may yield to the MoonLoader scheduler.
local function enqueueRequest(entry,req)
    if not entry or not clients[entry] or entry.processing then return false end
    entry.processing=true
    entry.deadline=nowMs()+30000
    requestQueue[#requestQueue+1]={entry=entry,req=req}
    return true
end

local function requestWorker(generation)
    while requestWorkerRunning and generation==serverGeneration do
        local job=table.remove(requestQueue,1)
        if job then
            local entry=job.entry
            if entry and clients[entry] then
                -- Do not use xpcall here. Some request callbacks legitimately
                -- pass through MoonLoader code that may yield; resuming such a
                -- request through xpcall caused "cannot resume non-suspended
                -- coroutine" and killed the whole ArzMarket script.
                local okHandle,out=pcall(handle,job.req)
                if not okHandle then
                    local detail=bridgeTraceback(out)
                    log("request handler failed: "..tostring(detail))
                    out=response(500,"internal_error")
                elseif type(out)~="string" then
                    out=response(500,"invalid_handler_response")
                end
                if clients[entry] then queueResponse(entry,out) end
            end
            ctx.wait(0)
        else
            -- The old idle wait(0) woke this coroutine every rendered game
            -- frame even when HTML had sent no request. Keep response latency
            -- low without burning a MoonLoader timeslice while idle.
            ctx.wait(16)
        end
    end
end

local function service()
    if not server then return end

    local count=0
    for _ in pairs(clients) do count=count+1 end

    -- All sockets are configured with settimeout(0). LuaSocket then reports
    -- "timeout" instead of blocking. Avoid socket.select entirely because the
    -- LuaSocket documentation notes WinSock problems with non-blocking TCP and
    -- states that select(server) does not guarantee accept() will not block.
    if count<12 then
        local client,acceptErr=server:accept()
        if client then
            client:settimeout(0)
            local entry={socket=client,buffer="",deadline=nowMs()+5000,processing=false}
            clients[entry]=true
            count=count+1
        elseif acceptErr and acceptErr~="timeout" then
            error("accept_failed: "..tostring(acceptErr))
        end
    end

    local entries={}
    for entry in pairs(clients) do entries[#entries+1]=entry end
    for _,entry in ipairs(entries) do
        if clients[entry] then
            local sock=entry.socket
            if entry.out then
                flushClient(entry)
            elseif not entry.processing and sock then
                local chunk,err,partial=sock:receive(4096)
                local data=chunk or partial
                if data and #data>0 then entry.buffer=entry.buffer..data end
                if #entry.buffer>81920 then
                    queueResponse(entry,response(413,"too_large"))
                else
                    local req,parseErr=parseRequest(entry.buffer)
                    if req then
                        enqueueRequest(entry,req)
                    elseif parseErr~="incomplete" then
                        queueResponse(entry,response(parseErr=="body_too_large" and 413 or 400,parseErr))
                    elseif err=="closed" then
                        closeClient(entry)
                    elseif err and err~="timeout" then
                        closeClient(entry)
                    end
                end
            end
            if clients[entry] and nowMs()>entry.deadline then closeClient(entry) end
        end
    end
end

function __arzHtmlRecoverServiceClients()
    local entries={}
    for entry in pairs(clients) do entries[#entries+1]=entry end
    for _,entry in ipairs(entries) do closeClient(entry) end
    requestQueue={}
end

function __arzHtmlSafeService(generation)
    if generation~=serverGeneration or not running then return false,"stale_generation" end
    if serviceBusy then return true end
    serviceBusy=true
    -- service() must never yield. The pcall boundary is safe here because all
    -- yield-capable ArzMarket callbacks are executed by requestWorker instead.
    local ok,err=pcall(service)
    serviceBusy=false
    if ok then return true end

    __arzHtmlRecoverServiceClients()
    local now=nowMs()
    if now-lastServiceErrorAt>=1000 then
        lastServiceErrorAt=now
        log("socket service recovered after error: "..tostring(err))
    end
    return false,tostring(err)
end

M._winsockApiCache = nil
M._winsockInitError = nil

function __arzHtmlBuildWinsockApi()
    if M._winsockApiCache then return M._winsockApiCache end
    if M._winsockInitError then return nil,M._winsockInitError end

    local okFfi,ffiLib=pcall(require,"ffi")
    if not okFfi or type(ffiLib)~="table" then
        M._winsockInitError="ffi_unavailable"
        return nil,M._winsockInitError
    end
    local ffi=ffiLib
    local cdefOk,cdefErr=pcall(ffi.cdef,[=[
        typedef unsigned int ARZ_SOCKET;
        typedef struct {
            short sin_family;
            unsigned short sin_port;
            unsigned long sin_addr;
            char sin_zero[8];
        } ARZ_SOCKADDR_IN;
        int WSAStartup(unsigned short wVersionRequested, void *lpWSAData);
        int WSAGetLastError(void);
        ARZ_SOCKET socket(int af, int type, int protocol);
        int closesocket(ARZ_SOCKET s);
        int bind(ARZ_SOCKET s, const void *name, int namelen);
        int listen(ARZ_SOCKET s, int backlog);
        ARZ_SOCKET accept(ARZ_SOCKET s, void *addr, int *addrlen);
        int ioctlsocket(ARZ_SOCKET s, unsigned long cmd, unsigned long *argp);
        int recv(ARZ_SOCKET s, char *buf, int len, int flags);
        int send(ARZ_SOCKET s, const char *buf, int len, int flags);
        int getsockname(ARZ_SOCKET s, void *name, int *namelen);
        unsigned long inet_addr(const char *cp);
        unsigned short htons(unsigned short hostshort);
        unsigned short ntohs(unsigned short netshort);
    ]=])
    if not cdefOk then
        M._winsockInitError="ffi_cdef_failed:"..tostring(cdefErr)
        return nil,M._winsockInitError
    end

    local loadOk,ws=pcall(ffi.load,"ws2_32")
    if not loadOk or not ws then
        M._winsockInitError="ws2_32_unavailable"
        return nil,M._winsockInitError
    end

    local wsaData=ffi.new("unsigned char[512]")
    if tonumber(ws.WSAStartup(0x0202,wsaData))~=0 then
        M._winsockInitError="wsa_startup_failed"
        return nil,M._winsockInitError
    end

    local INVALID_SOCKET=4294967295
    local WSAEWOULDBLOCK=10035
    local FIONBIO=0x8004667E
    local AF_INET=2
    local SOCK_STREAM=1
    local IPPROTO_TCP=6

    local function socketInvalid(handle)
        return handle==nil or tonumber(handle)==INVALID_SOCKET
    end
    local function lastError()
        local value=tonumber(ws.WSAGetLastError()) or -1
        if value==WSAEWOULDBLOCK then return "timeout" end
        return "winsock_"..tostring(value)
    end
    local function setNonBlocking(handle)
        local arg=ffi.new("unsigned long[1]",1)
        return tonumber(ws.ioctlsocket(handle,FIONBIO,arg))==0
    end

    local clientMethods={}
    clientMethods.__index=clientMethods
    function clientMethods:settimeout(_)
        return true
    end
    function clientMethods:close()
        if not self.closed and not socketInvalid(self.handle) then pcall(ws.closesocket,self.handle) end
        self.closed=true
        return true
    end
    function clientMethods:receive(maxBytes)
        if self.closed or socketInvalid(self.handle) then return nil,"closed","" end
        local requested=math.max(1,math.min(65536,tonumber(maxBytes) or 4096))
        local buffer=ffi.new("char[?]",requested)
        local received=tonumber(ws.recv(self.handle,buffer,requested,0)) or -1
        if received>0 then return ffi.string(buffer,received) end
        if received==0 then return nil,"closed","" end
        local err=lastError()
        return nil,err,""
    end
    function clientMethods:send(data,startPos)
        if self.closed or socketInvalid(self.handle) then return nil,"closed",(tonumber(startPos) or 1)-1 end
        data=tostring(data or "")
        local pos=math.max(1,math.floor(tonumber(startPos) or 1))
        if pos>#data then return #data end
        local chunk=data:sub(pos)
        local sent=tonumber(ws.send(self.handle,chunk,#chunk,0)) or -1
        if sent>0 then return pos+sent-1 end
        if sent==0 then return nil,"closed",pos-1 end
        local err=lastError()
        return nil,err,pos-1
    end

    local serverMethods={}
    serverMethods.__index=serverMethods
    function serverMethods:settimeout(_)
        return true
    end
    function serverMethods:close()
        if not self.closed and not socketInvalid(self.handle) then pcall(ws.closesocket,self.handle) end
        self.closed=true
        return true
    end
    function serverMethods:getsockname()
        return "127.0.0.1",self.port
    end
    function serverMethods:accept()
        if self.closed or socketInvalid(self.handle) then return nil,"closed" end
        local accepted=ws.accept(self.handle,nil,nil)
        if socketInvalid(accepted) then return nil,lastError() end
        if not setNonBlocking(accepted) then
            pcall(ws.closesocket,accepted)
            return nil,"nonblocking_failed"
        end
        return setmetatable({handle=accepted,closed=false},clientMethods)
    end

    local api={}
    function api.bind(host,requestedPort)
        if tostring(host)~="127.0.0.1" then return nil,"host_not_allowed" end
        local handle=ws.socket(AF_INET,SOCK_STREAM,IPPROTO_TCP)
        if socketInvalid(handle) then return nil,lastError() end
        local addr=ffi.new("ARZ_SOCKADDR_IN")
        addr.sin_family=AF_INET
        addr.sin_port=ws.htons(math.max(0,math.min(65535,tonumber(requestedPort) or 0)))
        addr.sin_addr=ws.inet_addr("127.0.0.1")
        local bindResult=tonumber(ws.bind(handle,addr,ffi.sizeof(addr))) or -1
        if bindResult~=0 then
            local err=lastError()
            pcall(ws.closesocket,handle)
            return nil,err
        end
        if tonumber(ws.listen(handle,16))~=0 then
            local err=lastError()
            pcall(ws.closesocket,handle)
            return nil,err
        end
        if not setNonBlocking(handle) then
            pcall(ws.closesocket,handle)
            return nil,"nonblocking_failed"
        end
        local actual=ffi.new("ARZ_SOCKADDR_IN")
        local actualLen=ffi.new("int[1]",ffi.sizeof(actual))
        local portValue=tonumber(requestedPort) or 0
        if tonumber(ws.getsockname(handle,actual,actualLen))==0 then
            portValue=tonumber(ws.ntohs(actual.sin_port)) or portValue
        end
        return setmetatable({handle=handle,port=portValue,closed=false},serverMethods)
    end

    M._winsockApiCache=api
    return api
end

function __arzHtmlStartServer()
    if running then return true end

    local socket=nil
    local luaSocketOk,luaSocket=pcall(require,"socket")
    if luaSocketOk and type(luaSocket)=="table" and type(luaSocket.bind)=="function" then
        socket=luaSocket
        M._socketBackend="luasocket"
    else
        local fallback,fallbackError=__arzHtmlBuildWinsockApi()
        if not fallback then
            M._socketBackend="none"
            return false,"network_backend_unavailable:luasocket="..tostring(luaSocket)..";winsock="..tostring(fallbackError)
        end
        socket=fallback
        M._socketBackend="winsock_ffi"
    end

    local ports={0}; for p=38460,38489 do ports[#ports+1]=p end
    local lastBindError=nil
    for _,p in ipairs(ports) do
        local bindOk,srv,bindError=pcall(socket.bind,"127.0.0.1",p)
        if bindOk and srv then
            local timeoutOk=pcall(function() return srv:settimeout(0) end)
            local nameOk,_,actual=pcall(function() return srv:getsockname() end)
            if timeoutOk and nameOk then
                server,port=srv,tonumber(actual) or p
                break
            end
            pcall(function() srv:close() end)
            lastBindError=bindError or "socket_setup_failed"
        else
            lastBindError=bindOk and bindError or srv
        end
    end
    if not server then return false,"port_unavailable:"..tostring(lastBindError or "unknown") end
    if not ctx or not ctx.lua_thread or type(ctx.lua_thread.create)~="function" or type(ctx.wait)~="function" then
        server:close(); server=nil; return false,"thread_unavailable"
    end

    socketApi=socket
    requestQueue={}
    stateResponseCache={}
    lastForegroundState=nil
    foregroundStableSince=nowMs()
    serverGeneration=serverGeneration+1
    local generation=serverGeneration
    running=true
    requestWorkerRunning=true
    serviceBusy=false

    local workerOk,workerOrError=pcall(ctx.lua_thread.create,function()
        requestWorker(generation)
    end)
    if not workerOk or not workerOrError then
        running=false
        requestWorkerRunning=false
        if server then pcall(function() server:close() end) end
        server,port=nil,nil
        socketApi=nil
        M._socketBackend="none"
        return false,"request_worker_start_failed: "..tostring(workerOrError)
    end
    log("bridge listening on 127.0.0.1:"..tostring(port).." backend="..tostring(M._socketBackend))
    return true
end

function __arzHtmlStopServer()
    serverGeneration=serverGeneration+1
    running=false
    requestWorkerRunning=false
    stopStorageSnapshotWorker()
    serviceBusy=false
    requestQueue={}
    local entries={}; for entry in pairs(clients) do entries[#entries+1]=entry end
    for _,entry in ipairs(entries) do closeClient(entry) end
    if server then pcall(function() server:close() end) end
    server,port=nil,nil
    socketApi=nil
    M._socketBackend="none"
end
function __arzHtmlLoadCefAdapter()
    local ok,module=pcall(require,"arizona-events")
    if ok and type(module)=="table" and type(module.eval)=="function" then
        return module,"arizona-events"
    end
    if type(raknetNewBitStream)~="function" or type(raknetBitStreamWriteInt8)~="function"
        or type(raknetBitStreamWriteInt16)~="function" or type(raknetBitStreamWriteInt32)~="function"
        or type(raknetBitStreamWriteString)~="function" or type(raknetEmulPacketReceiveBitStream)~="function"
        or type(raknetDeleteBitStream)~="function" then
        return nil,"raknet_api_unavailable"
    end
    return {
        eval=function(code,serverId)
            code=tostring(code or "")
            local text="(() => {"..code.."})();"
            local bs=raknetNewBitStream()
            if not bs then return false end
            local sent=false
            local callOk=pcall(function()
                raknetBitStreamWriteInt8(bs,17)
                raknetBitStreamWriteInt32(bs,tonumber(serverId) or 0)
                raknetBitStreamWriteInt16(bs,#text)
                raknetBitStreamWriteInt8(bs,0)
                raknetBitStreamWriteString(bs,text)
                raknetEmulPacketReceiveBitStream(220,bs)
                sent=true
            end)
            pcall(raknetDeleteBitStream,bs)
            return callOk and sent
        end
    },"raknet_fallback"
end

function __arzHtmlLoadItemIcons()
    local path=ctx.getWorkingDirectory().."\\ArzMarket\\lua\\arz_item_icons.lua"
    local loader,err=loadfile(path)
    if not loader then log("item icon module missing: "..tostring(err)); return end
    local ok,module=pcall(loader)
    if not ok or type(module)~="table" then log("item icon module failed: "..tostring(module)); return end
    itemIcons=module
    if type(itemIcons.init)=="function" then
        local initOk,initErr=pcall(itemIcons.init,ctx)
        if not initOk then log("item icon init failed: "..tostring(initErr)); itemIcons=nil end
    end
end

function M.open_html(page,settingsSection,options)
    if page=="buy" or page=="sell" or page=="settings" or page=="logs" or page=="marketplace" or page=="mods" or page=="storage" then currentPage=page end
    local validSettingsSection = settingsSection=="general" or settingsSection=="trade" or settingsSection=="automation"
        or settingsSection=="telegram" or settingsSection=="appearance" or settingsSection=="configs"
    if currentPage=="settings" and validSettingsSection then currentSettingsSection=settingsSection else currentSettingsSection=nil end
    local temporary=type(options)=="table" and options.temporary==true
    htmlTemporaryMode=temporary
    suppressAutoOpen=false
    if currentPage=="marketplace" and ctx and type(ctx.ensureMarketplaceLoaded)=="function" then pcall(ctx.ensureMarketplaceLoaded) end
    if not running then
        local ok,err=__arzHtmlStartServer()
        if not ok then
            M._lastOpenError=tostring(err or "bridge_start_failed")
            if ctx and ctx.notify then pcall(ctx.notify,"HTML интерфейс недоступен: "..M._lastOpenError) end
            return false,M._lastOpenError
        end
    end
    if not acef or type(acef.eval)~="function" then
        if not previewOpen then __arzHtmlStopServer() end
        M._lastOpenError="cef_unavailable:"..tostring(M._cefBackendError or M._cefBackend or "unknown")
        if ctx and ctx.notify then pcall(ctx.notify,"CEF API недоступен. Lua интерфейс продолжает работать.") end
        return false,M._lastOpenError
    end
    local menuWasVisible=ctx and type(ctx.getCoreMenuVisible)=="function" and ctx.getCoreMenuVisible()==true
    if menuWasVisible then setMenuVisible(false) end
    local ok=injectIframe(menuWasVisible)
    if ok then
        M._lastOpenError=nil
        if not temporary and ctx and type(ctx.setPreferredInterfaceMode)=="function" then pcall(ctx.setPreferredInterfaceMode,"html") end
    elseif menuWasVisible then
        setMenuVisible(true)
    end
    if not ok then
        htmlTemporaryMode=false
        M._lastOpenError="cef_inject_failed"
        if not previewOpen then __arzHtmlStopServer() end
    end
    if not ok and ctx and ctx.notify then pcall(ctx.notify,"Не удалось открыть CEF интерфейс. Используйте Lua режим.") end
    return ok,M._lastOpenError
end

function M.is_open()
    return htmlOpen==true
end
function M.invalidate_trade_source(side)
    side=side=="sell" and "sell" or "buy"
    refreshSourceCache(side,true)
    fingerprints[side]=""
    stateResponseCache[side]=nil
    revision[side]=(tonumber(revision[side]) or 0)+1
    return true
end

function M.get_window_state()
    local out={temporary=htmlTemporaryMode==true}
    if type(htmlWindowState)=="table" then
        for k,v in pairs(htmlWindowState) do out[k]=v end
    end
    return out
end

function M.should_capture_window_message(message)
    if not compatInputNeeded() then
        htmlCompatFocused=false
        htmlCompatLastMouseInside=false
        return false
    end
    -- In the normal HTML mode Windows messages must reach Arizona CEF itself.
    -- Consuming them here was one of the reasons the iframe was visible but
    -- unclickable. Only intercept while another SA-MP/game UI owns input.
    if not M._compatFallbackMode() then return false end
    local kind=classifyWindowMessage(message)
    if kind=="mouse" then
        local inside=cursorInsideHtmlWindow()
        htmlCompatLastMouseInside=inside==true
        local m=tonumber(message) or -1
        if m==513 or m==516 or m==519 then
            htmlCompatFocused=inside==true
        end
        return inside==true
    end
    if kind=="keyboard" then return htmlCompatFocused==true end
    return false
end

function M.forward_window_message(message,wparam,lparam)
    if not compatInputNeeded() or not M._compatFallbackMode() then return false end
    local kind=classifyWindowMessage(message)
    if not kind then return false end
    local inside,x,y=cursorInsideHtmlWindow()
    if kind=="mouse" then
        local m=tonumber(message) or -1
        if not inside then
            if m==513 or m==516 or m==519 then htmlCompatFocused=false end
            return false
        end
        local eventType="move"
        local button=nil
        if m==512 then
            local moveNow=nowMs()
            local dragging=htmlCompatButtons[1] or htmlCompatButtons[2] or htmlCompatButtons[3]
            local minMoveInterval=dragging and 24 or 60
            if moveNow-htmlCompatLastMoveAt<minMoveInterval then
                htmlCompatLastX,htmlCompatLastY=x,y
                return true
            end
            htmlCompatLastMoveAt=moveNow
        end
        if m==513 or m==515 then eventType="down"; button=0; htmlCompatFocused=true
        elseif m==514 then eventType="up"; button=0
        elseif m==516 or m==518 then eventType="down"; button=2; htmlCompatFocused=true
        elseif m==517 then eventType="up"; button=2
        elseif m==519 or m==521 then eventType="down"; button=1; htmlCompatFocused=true
        elseif m==520 then eventType="up"; button=1
        elseif m==522 then eventType="wheel"
        end
        -- Keep the polling fallback in sync with the event-driven path.
        -- Otherwise one physical click can be emitted once here and once more
        -- from isKeyDown() on the next D3D frame.
        htmlCompatLastX,htmlCompatLastY=x,y
        if m==513 or m==515 then htmlCompatButtons[1]=true
        elseif m==514 then htmlCompatButtons[1]=false
        elseif m==516 or m==518 then htmlCompatButtons[2]=true
        elseif m==517 then htmlCompatButtons[2]=false
        elseif m==519 or m==521 then htmlCompatButtons[3]=true
        elseif m==520 then htmlCompatButtons[3]=false
        elseif m==522 then htmlCompatLastWheelEventAt=nowMs() end

        local payload={kind="mouse",event=eventType,x=x,y=y,button=button,wparam=tonumber(wparam) or 0}
        if m==522 then
            local wp=tonumber(wparam) or 0
            local high=math.floor(wp/65536)%65536
            if high>=32768 then high=high-65536 end
            payload.delta=high/120
        end
        refocusHtmlFrame(false)
        return postCompatInput(payload)
    end
    if not htmlCompatFocused then return false end
    local m=tonumber(message) or -1
    local eventType=(m==257 or m==261) and "up" or (m==258 and "char" or "down")
    local keyCode=tonumber(wparam) or 0
    local payload={kind="keyboard",event=eventType,keyCode=keyCode,charCode=m==258 and keyCode or nil}
    if m==258 and keyCode>0 then
        -- GTA/SA-MP commonly uses an ANSI window. WM_CHAR may therefore carry
        -- a CP1251 byte for Cyrillic text instead of a Unicode code point.
        -- Send an explicit UTF-8 character to CEF so Russian input is not
        -- turned into Latin-1 glyphs while the compatibility bridge is active.
        if keyCode>=0x80 and keyCode<=0xFF then
            payload.text=toUtf8(string.char(keyCode))
        else
            payload.text=utf8FromCodepoint(keyCode)
        end
    end
    if type(isKeyDown)=="function" then
        local okCtrl,vCtrl=pcall(isKeyDown,0x11); payload.ctrl=okCtrl and vCtrl==true or false
        local okShift,vShift=pcall(isKeyDown,0x10); payload.shift=okShift and vShift==true or false
        local okAlt,vAlt=pcall(isKeyDown,0x12); payload.alt=okAlt and vAlt==true or false
    end
    refocusHtmlFrame(false)
    return postCompatInput(payload)
end

function M.open_preview(bounds,page,options)
    if not previewOpen and (page=="buy" or page=="sell" or page=="settings" or page=="logs" or page=="marketplace" or page=="mods" or page=="storage") then currentPage=page end
    if not running then
        local ok,err=__arzHtmlStartServer()
        if not ok then return false,err end
    end
    if not acef or type(acef.eval)~="function" then
        if not htmlOpen then __arzHtmlStopServer() end
        return false,"cef_unavailable"
    end
    local ok,err=injectPreviewIframe(bounds,options)
    if not ok and not htmlOpen then __arzHtmlStopServer() end
    return ok,err
end
function M.close_preview()
    removePreviewIframe()
    if not htmlOpen and not previewOpen then __arzHtmlStopServer() end
    return true
end
function M.close_html()
    suppressAutoOpen=true
    removeIframe()
    removePreviewIframe()
    if not htmlOpen and not previewOpen then __arzHtmlStopServer() end
    return true
end
function M.init(context)
    ctx=context
    token=makeToken()
    htmlRoot=ctx.getWorkingDirectory().."\\ArzMarket\\html"
    htmlWindowStatePath=ctx.getWorkingDirectory().."\\ArzMarket\\html_window_state.json"

    local indexPath=htmlRoot.."\\index.html"
    if not doesFileExist(indexPath) then
        M._lastInitError="html_index_missing:"..tostring(indexPath)
        log(M._lastInitError)
        return false
    end

    local function initStep(name,fn)
        local ok,err=xpcall(fn,bridgeTraceback)
        if not ok then log("init step "..tostring(name).." failed: "..tostring(err)) end
        return ok
    end

    initStep("restore_buy_draft",function() restoreTradeDraft("buy") end)
    initStep("restore_sell_draft",function() restoreTradeDraft("sell") end)
    initStep("window_state",loadWindowState)
    initStep("item_icons",__arzHtmlLoadItemIcons)
    initStep("buy_cache",function() refreshSourceCache("buy",true) end)
    initStep("sell_cache",function() refreshSourceCache("sell",true) end)

    local cefOk,adapter,backend=xpcall(function()
        return __arzHtmlLoadCefAdapter()
    end,bridgeTraceback)
    if cefOk then
        acef=adapter
        M._cefBackend=adapter and tostring(backend or "unknown") or "none"
        M._cefBackendError=adapter and nil or tostring(backend or "cef_unavailable")
    else
        acef=nil
        M._cefBackend="none"
        M._cefBackendError=tostring(adapter)
    end
    if not acef then log("CEF adapter unavailable: "..tostring(M._cefBackendError)) end

    initStep("input_recovery",recoverGameInputAfterReload)
    M._lastInitError=nil
    log("initialized htmlRoot="..tostring(htmlRoot).." cef="..tostring(M._cefBackend))
    return true
end

function M.render(context)
    ctx=context or ctx
    local imgui=ctx.imgui
    if ctx.preview==true then
        imgui.Text("HTML интерфейс открыт в правом окне предпросмотра.")
        return
    end

    -- The Lua menu item "HTML" is an action, not a real page.
    -- As soon as the user selects it, immediately hand control to CEF.
    -- close_html() deliberately sets suppressAutoOpen=true when returning to Lua,
    -- so selecting this menu item explicitly clears that guard again.
    if acef and not htmlOpen then
        local now=nowMs()
        if now-lastMenuAutoOpenAttempt >= 750 then
            lastMenuAutoOpenAttempt=now
            suppressAutoOpen=false
            local ok=M.open_html(currentPage)
            if ok then return end
        end
    end

    -- These messages are only a fallback for a real CEF/bridge failure.
    -- Under normal conditions the page is never visible to the user.
    if not acef then
        imgui.Text("HTML интерфейс ArzMarket")
        imgui.Spacing()
        imgui.TextWrapped("CEF API недоступен. Lua интерфейс продолжает работать.")
        return
    end
    if not running then
        imgui.Text("Local bridge не запущен.")
        if imgui.Button("Повторить запуск",imgui.ImVec2(220,34)) then __arzHtmlStartServer() end
        return
    end
    if not htmlOpen then
        imgui.Text("Не удалось автоматически открыть HTML интерфейс.")
        imgui.TextWrapped("Повторная попытка выполняется автоматически.")
    end
end
function M.get_diagnostics()
    return {
        running=running==true,
        htmlOpen=htmlOpen==true,
        port=port,
        socketBackend=M._socketBackend,
        cefBackend=M._cefBackend,
        cefError=M._cefBackendError,
        htmlRoot=htmlRoot,
        indexExists=htmlRoot and doesFileExist(htmlRoot.."\\index.html") or false,
        lastInitError=M._lastInitError,
        lastOpenError=M._lastOpenError
    }
end

function M.pump()
    if not running then return true end
    local now=nowMs()
    local ok,err=true,nil
    if now-lastServiceAt>=8 then
        lastServiceAt=now
        ok,err=__arzHtmlSafeService(serverGeneration)
    end
    if htmlOpen then
        ensureIframe()
        reclaimHtmlInputIfNeeded()
        pumpCompatPointer()
    end
    return ok,err
end

function M.shutdown(context, quitGame)
    stopStorageSnapshotWorker()
    removeIframe()
    removePreviewIframe()
    removeStaleCefFrames()
    if quitGame ~= true and not gameUiNeedsCursor() then
        forceDisableCefCursor()
    end
    __arzHtmlStopServer()
    if itemIcons and type(itemIcons.shutdown)=="function" then pcall(itemIcons.shutdown) end
    return true
end

return M
