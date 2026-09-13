local M = {
    api_version = 1,
    module_version = 55,
    id = "arz_html_ui",
    title = "HTML",
    section = "Интерфейс",
    order = 999,
    no_scroll = true
}

local ctx, acef, server, port, itemIcons
local running, htmlOpen, suppressAutoOpen = false, false, false
local previewOpen, previewSignature = false, ""
local clients, token, htmlRoot, currentPage, currentSettingsSection = {}, "", "", "buy", nil
local htmlWindowStatePath, htmlWindowState = nil, {}
local HTML_LAYOUT_VERSION = 16
local revision, fingerprints = { buy = 1, sell = 1, settings = 1, logs = 1, marketplace = 1, storage = 1, mods = 1 }, { buy = "", sell = "", settings = "", logs = "", marketplace = "", storage = "", mods = "" }
local lastInjectCheck = 0
local lastMenuAutoOpenAttempt = 0
local sourceCache = { buy = {at=0,data={}}, sell = {at=0,data={}} }
local settingsSnapshotCache = { at = 0, data = nil }
local globalDecodeJson, globalEncodeJson = decodeJson, encodeJson

local function log(v) print("[ArzMarket HTML] " .. tostring(v)) end
local function nowMs()
    if type(getGameTimer) == "function" then
        local ok,v = pcall(getGameTimer)
        if ok and tonumber(v) then return tonumber(v) end
    end
    return math.floor(os.clock()*1000)
end
local function encode(v)
    if type(globalEncodeJson)=="function" then
        local ok,out=pcall(globalEncodeJson,v)
        if ok and type(out)=="string" then return out end
    end
    return "{}"
end
local function decode(v)
    if type(globalDecodeJson)=="function" then
        local ok,out=pcall(globalDecodeJson,v)
        if ok then return out end
    end
end
local function toUtf8(v)
    v=tostring(v or "")
    if ctx and ctx.u8 and type(ctx.u8.encode)=="function" then
        local ok,out=pcall(function() return ctx.u8:encode(v) end)
        if ok and type(out)=="string" then return out end
    end
    return v
end
local function fromUtf8(v)
    v=tostring(v or "")
    if ctx and ctx.u8 and type(ctx.u8.decode)=="function" then
        local ok,out=pcall(function() return ctx.u8:decode(v) end)
        if ok and type(out)=="string" then return out end
    end
    return v
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
        local ok,value=pcall(ctx.getMenuScalePercent)
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
    local ok,value=pcall(ctx.listTradeConfigs,side)
    if not ok or type(value)~="table" then return {} end
    local out={}
    for i=1,#value do
        local name=normalizeConfig(value[i])
        if name~="" then out[#out+1]=name:gsub("%.json$","") end
    end
    return out
end
local autoConfigAttempted={buy=false,sell=false}
local function ensureLoadedConfig(side)
    side=side=="sell" and "sell" or "buy"
    local current=configName(side)
    if current~="" then return current end
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
    local ok,result=pcall(ctx.loadTradeConfig,side,selected)
    if not ok or result==false then return "" end
    return configName(side)
end
local function persist(side)
    local buy,sell=lists()
    local list=side=="buy" and buy or sell
    local name=configName(side)
    if name=="" then return false,"config_not_loaded" end
    if type(createConfig)~="function" then return false,"save_unavailable" end
    local ok,result=pcall(createConfig,side.."-cfg/"..name,list,side.."-cfg",name)
    return ok and result~=false, ok and result~=false and nil or "save_failed"
end
local function resolvedItemId(item)
    local id=item.item_id or item.foreign_item_id or item.id
    if id~=nil and tostring(id)~="" then return tostring(id) end
    if itemIcons and type(itemIcons.resolveItemId)=="function" then
        local ok,value=pcall(itemIcons.resolveItemId,item.name or item.item or "")
        if ok and value~=nil and tostring(value)~="" then return tostring(value) end
    end
end
local function itemCategory(item)
    if ctx and type(ctx.getTradeItemCategory)=="function" then
        local ok,category=pcall(ctx.getTradeItemCategory,item)
        if ok and type(category)=="string" and category~="" then return category end
    end
    return "other"
end
local function itemCategorySubtypeRank(item)
    if ctx and type(ctx.getTradeFilterSubtypeRank)=="function" then
        local ok,rank=pcall(ctx.getTradeFilterSubtypeRank,item)
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
        local ok,value=pcall(ctx.getTradeFilterCategories,side)
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
local function sources(side)
    local cached=sourceCache[side]
    local now=nowMs()
    if cached and now-cached.at<1000 then return cached.data end
    if not ctx or type(ctx.readJsonFile)~="function" then return {} end
    local path=side=="buy" and "moonloader/ArzMarket/buy.json" or "moonloader/ArzMarket/sell.json"
    local ok,raw=pcall(ctx.readJsonFile,path)
    local out={}
    if ok and type(raw)=="table" then
        for i=1,#raw do
            local x=raw[i]
            if side=="buy" and type(x)=="string" then
                local id=itemIcons and itemIcons.resolveItemId and itemIcons.resolveItemId(x) or nil
                local sourceItem={name=x,item_id=id}
                out[#out+1]={index=i,name=toUtf8(x),item_id=id,category=itemCategory(sourceItem)}
            elseif side=="sell" and type(x)=="table" then
                local name=x.item or x.name or ("Item #"..tostring(i))
                local id=x.item_id or x.foreign_item_id or x.id
                if id==nil and itemIcons and itemIcons.resolveItemId then id=itemIcons.resolveItemId(name) end
                out[#out+1]={index=i,name=toUtf8(name),all_count=saneNumber(x.all_count,saneNumber(x.count,0)),
                    slot_count=saneNumber(x.count,0),slot_id=x.slot_id,item_id=id,category=itemCategory(x)}
            end
        end
    end
    sourceCache[side]={at=now,data=out}
    return out
end

local function sourceFingerprint(source)
    local out={tostring(type(source)=="table" and #source or 0)}
    for i=1,#source do
        local x=source[i]
        out[#out+1]=table.concat({
            tostring(x.name or ""),tostring(x.item_id or ""),tostring(x.all_count or ""),
            tostring(x.slot_count or ""),tostring(x.slot_id or ""),tostring(x.category or "")
        },"\30")
    end
    return table.concat(out,"\31")
end

local function automationSnapshot()
    if not ctx or type(ctx.getTradeAutomationState)~="function" then return {sell=false,buy=false,score=0,score_from=0} end
    local ok,state=pcall(ctx.getTradeAutomationState)
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
    local ok,result=pcall(ctx.setCoreMenuVisible,value==true)
    return ok and result~=false
end
local function selectLuaPage(page)
    if ctx and type(ctx.selectCorePage)=="function" then
        local pageId=page=="sell" and 1 or page=="settings" and 3 or page=="logs" and 4 or page=="marketplace" and 5 or page=="mods" and 7 or page=="storage" and 8 or 2
        local ok,result=pcall(ctx.selectCorePage,pageId)
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
    local ok,value=pcall(ctx.getLogsData)
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
local storageRefreshRequested=true

local function safeStorageFinder()
    if not ctx or type(ctx.getStorageFinder)~="function" then return nil end
    local ok,finder=pcall(ctx.getStorageFinder)
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

    local okRows,rows=pcall(finder.getVisibleRows,"",{storage_type="all",category="all"})
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
        local okState,coreState=pcall(finder.getState)
        if okState and type(coreState)=="table" then
            scanning=coreState.player_scan_active==true or (type(coreState.manual_scan)=="table" and coreState.manual_scan.requested==true)
            local coreLast=type(coreState.last_scan)=="table" and saneNumber(coreState.last_scan.time,0) or 0
            newest=math.max(newest,saneNumber(coreLast,0) or 0)
        end
    end

    return {items=items,locationCount=locationCount,ready=true,scanning=scanning,lastScan=newest,error=nil}
end

local function refreshStorageSnapshotCache()
    local ok,snapshotOrErr,maybeErr=pcall(buildStorageSnapshotFromFinder)
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

local function startStorageSnapshotWorker()
    if storageWorkerRunning then return true end
    if not ctx or not ctx.lua_thread or type(ctx.lua_thread.create)~="function" or type(ctx.wait)~="function" then return false end
    storageWorkerRunning=true
    ctx.lua_thread.create(function()
        ctx.wait(0)
        while storageWorkerRunning do
            local ok,err=pcall(refreshStorageSnapshotCache)
            if not ok then
                storageSnapshotCache.error=tostring(err)
                log("storage snapshot worker failed: "..tostring(err))
            end
            storageRefreshRequested=false
            local waited=0
            while storageWorkerRunning and waited<1200 and not storageRefreshRequested do
                ctx.wait(100)
                waited=waited+100
            end
        end
    end)
    return true
end

local function storageState()
    currentPage="storage"
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
            local ok,value=pcall(itemIcons.resolveItemId,rawName)
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
        local ok,value=pcall(ctx.getMarketplaceSnapshot)
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
        lastUpdated=math.floor(saneNumber(raw.lastUpdated,0) or 0),publishing=raw.publishing==true,publishedShopId=saneNumber(raw.publishedShopId,nil)
    }
    local fp=encode(data)
    if fp~=fingerprints.marketplace then fingerprints.marketplace=fp; revision.marketplace=revision.marketplace+1 end
    return {revision=revision.marketplace,page="marketplace",common={uiMode="html",htmlWindow=htmlWindowState,menuScalePercent=currentMenuScalePercent()},data=data}
end

local function modsState()
    currentPage="mods"
    local data={}
    if ctx and type(ctx.getModsSnapshot)=="function" then
        local ok,value=pcall(ctx.getModsSnapshot)
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

local function settingsState()
    currentPage="settings"
    local now=nowMs()
    local dirty=fingerprints.settings==""
    if dirty or type(settingsSnapshotCache.data)~="table" or now-(settingsSnapshotCache.at or 0)>=1500 then
        local snapshot={}
        if ctx and type(ctx.getSettingsSnapshot)=="function" then
            local ok,value=pcall(ctx.getSettingsSnapshot)
            if ok and type(value)=="table" then snapshot=value end
        end
        settingsSnapshotCache.data=utf8Tree(snapshot,0) or {}
        settingsSnapshotCache.at=now
    end
    local data=settingsSnapshotCache.data or {}
    local fp=encode(data)
    if fp~=fingerprints.settings then
        fingerprints.settings=fp
        revision.settings=revision.settings+1
    end
    return {
        revision=revision.settings,page="settings",
        common={uiMode="html",htmlWindow=htmlWindowState,menuScalePercent=currentMenuScalePercent()},
        data=data
    }
end

local function stateFor(page)
    if page=="settings" then return settingsState() end
    if page=="mods" then return modsState() end
    if page=="logs" then return logsState() end
    if page=="marketplace" then return marketplaceState() end
    if page=="storage" then return storageState() end
    page=page=="sell" and "sell" or "buy"
    currentPage=page
    ensureLoadedConfig(page)
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
        local ok,value=pcall(ctx.getTradeUiState)
        if ok and type(value)=="table" then uiState=value end
    end
    -- HTML Buy uses SA$ as its primary table currency, matching the reference UI.
    -- If Lua is idle and still left in VC mode, switch only the mode flag and then
    -- read the state again. Do not do this during an active trade.
    if page=="buy" and not busy and uiState.currency=="VC" and ctx and type(ctx.ensureHtmlTradeCurrency)=="function" then
        pcall(ctx.ensureHtmlTradeCurrency,"SA")
        if type(ctx.getTradeUiState)=="function" then
            local ok,value=pcall(ctx.getTradeUiState)
            if ok and type(value)=="table" then uiState=value end
        end
    end
    local currency=uiState.currency=="VC" and "VC" or "SA"
    local buyScan=uiState.buy_scan==true
    local sellScan=uiState.sell_scan==true
    local undoCount=0
    if ctx and type(ctx.getTradeUndoCount)=="function" then
        local ok,value=pcall(ctx.getTradeUndoCount,page)
        if ok then undoCount=math.max(0,math.floor(tonumber(value) or 0)) end
    end
    local buyContinue=false
    if ctx and type(ctx.getBuyContinueMode)=="function" then
        local ok,value=pcall(ctx.getBuyContinueMode)
        if ok then buyContinue=value==true end
    end
    local runtimeKey=table.concat({
        tostring(active),tostring(busy),tostring(snapshot.buy==true),tostring(snapshot.sell==true),
        tostring(score),tostring(total),tostring(cfg),table.concat(configs,"\29"),currency,tostring(buyScan),tostring(sellScan),
        tostring(undoCount),tostring(buyContinue),sourceFingerprint(source),encode(categories)
    },"\30")
    touchRevision(page,list,runtimeKey)
    local items={}
    for i=1,#list do items[i]=itemDto(list[i],i,page) end
    local address,serverPort="",0
    if type(sampGetCurrentServerAddress)=="function" then
        local ok,a,p=pcall(sampGetCurrentServerAddress)
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
    local index=math.floor(saneNumber(identity.index,0) or 0)
    if index<1 or index>#list then return nil,nil,"stale_state" end
    local item=list[index]
    if tostring(identity.name or "")~="" and toUtf8(item.name or item.item or "")~=tostring(identity.name) then return nil,nil,"stale_state" end
    if identity.slot_id~=nil and item.slot_id~=nil and tostring(identity.slot_id)~=tostring(item.slot_id) then return nil,nil,"stale_state" end
    return item,index
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
    local ok,result,coreErr=pcall(ctx.deleteTradeItem,side,index)
    local success=ok and result~=false
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
        local ok,value=pcall(ctx.getTradeAddDefaults,side)
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

local function setCefCursor(value)
    pcall(function()
        local bs=raknetNewBitStream()
        raknetBitStreamWriteInt8(bs,25); raknetBitStreamWriteInt32(bs,0)
        raknetBitStreamWriteInt8(bs,value and 128 or 0); raknetBitStreamWriteInt16(bs,0)
        raknetEmulPacketReceiveBitStream(220,bs); raknetDeleteBitStream(bs)
    end)
    pcall(function() if sampSetCursorMode then if value then sampSetCursorMode(2); sampSetCursorMode(1) else sampSetCursorMode(0) end end end)
    pcall(function() if sampToggleCursor then sampToggleCursor(value) end end)
    pcall(function() if sampShowCursor then sampShowCursor(value) end end)
    pcall(function() if showCursor then showCursor(value) end end)
end
local function quoteJs(v) return string.format("%q",tostring(v or "")):gsub("\r","\\r"):gsub("\n","\\n") end
local function parentFrameBootstrap(url,replaceExisting)
    local replaceCode=replaceExisting and "var old=document.getElementById('arzmarket-html-frame');if(old)old.remove();" or ""
    return "window.__arzMarketFrameToken="..quoteJs(token)..";"..
        "window.__arzMarketFocusFrame=function(f,activate){if(!f)return;if(activate!==false)f.style.pointerEvents='auto';f.style.visibility='visible';try{f.focus();}catch(e){}try{if(f.contentWindow)f.contentWindow.focus();}catch(e){}};"..
        "if(!window.__arzMarketFrameMessageBound){window.addEventListener('message',function(e){var d=e&&e.data;if(!d||d.channel!=='arzmarket-html'||d.token!==window.__arzMarketFrameToken)return;var f=document.getElementById('arzmarket-html-frame');if(d.action==='detach'){if(f)f.remove();return;}if(d.action==='hide'){if(f){f.style.visibility='hidden';f.style.pointerEvents='none';}return;}if(d.action==='show'){if(f){f.style.visibility='visible';window.__arzMarketFocusFrame(f);}return;}if(d.action==='ready'&&f){f.setAttribute('data-ready','1');window.__arzMarketFocusFrame(f);}},false);window.__arzMarketFrameMessageBound=true;}"..
        replaceCode..
        "if(!document.getElementById('arzmarket-html-frame')){var f=document.createElement('iframe');f.id='arzmarket-html-frame';f.src="..quoteJs(url)..";"..
        "f.style.position='fixed';f.style.left='0';f.style.top='0';f.style.width='100vw';f.style.height='100vh';"..
        "f.style.border='0';f.style.background='transparent';f.style.zIndex='2147483000';f.style.pointerEvents='none';f.style.visibility='visible';"..
        "f.onload=function(){var self=this;setTimeout(function(){if(self&&self.parentNode){window.__arzMarketFocusFrame(self,false);}},80);};"..
        "document.body.appendChild(f);}else{var f=document.getElementById('arzmarket-html-frame');if(f&&f.getAttribute('data-ready')==='1')window.__arzMarketFocusFrame(f);}"
end
local function previewFrameBootstrap(url,bounds)
    local left=math.max(0,math.floor(tonumber(bounds and bounds.x) or 0))
    local top=math.max(0,math.floor(tonumber(bounds and bounds.y) or 0))
    local width=math.max(180,math.floor(tonumber(bounds and bounds.w) or 320))
    local height=math.max(120,math.floor(tonumber(bounds and bounds.h) or 240))
    return "var p=document.getElementById('arzmarket-html-preview-frame');"..
        "if(!p){p=document.createElement('iframe');p.id='arzmarket-html-preview-frame';document.body.appendChild(p);}"..
        "if(p.getAttribute('data-arz-src')!=="..quoteJs(url).."){p.src="..quoteJs(url)..";p.setAttribute('data-arz-src',"..quoteJs(url)..");}"..
        "p.style.position='fixed';p.style.left='"..tostring(left).."px';p.style.top='"..tostring(top).."px';"..
        "p.style.width='"..tostring(width).."px';p.style.height='"..tostring(height).."px';"..
        "p.style.border='1px solid rgba(55,82,105,.95)';p.style.borderRadius='10px';p.style.background='#071018';p.style.zIndex='2147482998';p.style.pointerEvents='none';"..
        "p.style.boxShadow='0 0 0 rgba(0,0,0,0)';p.style.opacity='1';"
end
local function buildUiUrl(preview)
    local url="http://127.0.0.1:"..tostring(port).."/ui?"..(preview and "preview=1&" or "").."page="..tostring(currentPage or "buy")
    if currentPage=="settings" and currentSettingsSection=="appearance" then
        url=url.."&section=appearance"
    end
    return url
end
local function removePreviewIframe()
    previewOpen=false
    previewSignature=""
    if acef and type(acef.eval)=="function" then pcall(acef.eval,"var p=document.getElementById('arzmarket-html-preview-frame');if(p)p.remove();") end
end
local function injectPreviewIframe(bounds)
    if not acef or type(acef.eval)~="function" or not port then return false end
    local url=buildUiUrl(true)
    local signature=table.concat({tostring(math.floor(tonumber(bounds and bounds.x) or 0)),tostring(math.floor(tonumber(bounds and bounds.y) or 0)),tostring(math.floor(tonumber(bounds and bounds.w) or 0)),tostring(math.floor(tonumber(bounds and bounds.h) or 0)),tostring(currentPage or "buy")},":")
    if previewOpen and previewSignature==signature then return true end
    previewSignature=signature
    local ok,result=pcall(acef.eval,previewFrameBootstrap(url,bounds))
    ok=ok and result~=false
    if ok then previewOpen=true else previewSignature="" end
    return ok
end
local function removeIframe()
    htmlOpen=false
    if acef and type(acef.eval)=="function" then pcall(acef.eval,"var f=document.getElementById('arzmarket-html-frame');if(f)f.remove();") end
    setCefCursor(false)
end
local function injectIframe()
    if not acef or type(acef.eval)~="function" or not port then return false end
    local url=buildUiUrl(false)
    local ok,result=pcall(acef.eval,parentFrameBootstrap(url,true))
    ok=ok and result~=false
    if ok then
        htmlOpen=true
        lastInjectCheck=nowMs()
        setCefCursor(true)
        if ctx and ctx.lua_thread and type(ctx.lua_thread.create)=="function" then
            ctx.lua_thread.create(function()
                wait(120)
                if htmlOpen then
                    setCefCursor(true)
                    pcall(acef.eval,"var f=document.getElementById('arzmarket-html-frame');if(f&&window.__arzMarketFocusFrame)window.__arzMarketFocusFrame(f);")
                end
                wait(260)
                if htmlOpen then
                    setCefCursor(true)
                    pcall(acef.eval,"var f=document.getElementById('arzmarket-html-frame');if(f&&window.__arzMarketFocusFrame)window.__arzMarketFocusFrame(f);")
                end
            end)
        end
    end
    return ok
end
local function ensureIframe()
    if not htmlOpen or not acef or nowMs()-lastInjectCheck<1500 then return end
    lastInjectCheck=nowMs()
    local url=buildUiUrl(false)
    pcall(acef.eval,parentFrameBootstrap(url,false))
end

local function readFile(path,binary)
    local f=io.open(path,binary and "rb" or "r")
    if not f then return nil end
    local data=f:read("*a"); f:close(); return data
end
local mime={html="text/html; charset=utf-8",css="text/css; charset=utf-8",js="application/javascript; charset=utf-8",svg="image/svg+xml",webp="image/webp"}
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
    local ok,data=pcall(ctx.getPriceData)
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
    local ok,data=pcall(ctx.getPriceData)
    if not ok or type(data)~="table" then return {available=false,name=toUtf8(itemName)} end
    local meta={}
    if type(ctx.getAveragePriceMeta)=="function" then
        local okMeta,value=pcall(ctx.getAveragePriceMeta,itemName)
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
            local ok,result=pcall(ctx.activateLuaPage,pageId)
            switched=ok and result~=false
        else
            switched=selectLuaPage(requestedPage)
            if switched then
                if ctx and type(ctx.setPreferredInterfaceMode)=="function" then pcall(ctx.setPreferredInterfaceMode,"lua") end
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
        if requestedPage=="marketplace" and ctx and type(ctx.ensureMarketplaceLoaded)=="function" then pcall(ctx.ensureMarketplaceLoaded) end
        return jsonResponse(200,{ok=true,page=requestedPage})
    elseif action=="marketplace.refresh" then
        if not ctx or type(ctx.refreshMarketplace)~="function" then return jsonResponse(400,{ok=false,error="marketplace_unavailable"}) end
        local ok,result,coreErr=pcall(ctx.refreshMarketplace,data.serverIndex)
        local success=ok and result~=false
        fingerprints.marketplace=""
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="marketplace.server.select" then
        if not ctx or type(ctx.refreshMarketplace)~="function" then return jsonResponse(400,{ok=false,error="marketplace_unavailable"}) end
        local ok,result,coreErr=pcall(ctx.refreshMarketplace,data.index)
        local success=ok and result~=false
        fingerprints.marketplace=""
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="marketplace.sort" then
        if not ctx or type(ctx.setMarketplaceSortMode)~="function" then return jsonResponse(400,{ok=false,error="marketplace_unavailable"}) end
        local ok,value=pcall(ctx.setMarketplaceSortMode,data.mode)
        fingerprints.marketplace=""
        return jsonResponse(ok and 200 or 400,{ok=ok,mode=ok and value or nil,error=ok and nil or tostring(value)})
    elseif action=="marketplace.find" then
        if not ctx or type(ctx.findMarketplaceStall)~="function" then return jsonResponse(400,{ok=false,error="marketplace_unavailable"}) end
        local ok,result,coreErr=pcall(ctx.findMarketplaceStall,data.uid,data.serverId)
        local success=ok and result~=false
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="marketplace.auth.open" then
        if not ctx or type(ctx.openMarketplaceAuthProvider)~="function" then return jsonResponse(400,{ok=false,error="marketplace_unavailable"}) end
        local ok,result,coreErr=pcall(ctx.openMarketplaceAuthProvider,tostring(data.provider or "telegram"))
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
        local ok,result,coreErr=pcall(ctx.setModsValue,tostring(data.key or ""),data.value)
        local success=ok and result~=false
        fingerprints.mods=""
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="mods.manual_purchased" then
        if not ctx or type(ctx.toggleManualPurchasedListing)~="function" then return jsonResponse(400,{ok=false,error="manual_purchased_unavailable"}) end
        local ok,result,detail=pcall(ctx.toggleManualPurchasedListing)
        local success=ok and result~=false
        fingerprints.mods=""
        return jsonResponse(success and 200 or 400,{ok=success,state=success and detail or nil,error=success and nil or (ok and detail or tostring(result))})
    elseif action=="mods.telegram" then
        if not ctx or type(ctx.openModsTelegram)~="function" then return jsonResponse(400,{ok=false,error="open_url_unavailable"}) end
        local ok,result,coreErr=pcall(ctx.openModsTelegram)
        local success=ok and result~=false
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="settings.set" then
        if not ctx or type(ctx.setSettingsValue)~="function" then return jsonResponse(400,{ok=false,error="settings_unavailable"}) end
        local value=data.value
        if type(value)=="string" then value=fromUtf8(value) end
        local ok,result,coreErr=pcall(ctx.setSettingsValue,tostring(data.key or ""),value)
        local success=ok and result~=false
        fingerprints.settings=""; settingsSnapshotCache.at=0
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="settings.theme.select" then
        if not ctx or type(ctx.selectSettingsTheme)~="function" then return jsonResponse(400,{ok=false,error="theme_unavailable"}) end
        local ok,result,coreErr=pcall(ctx.selectSettingsTheme,tostring(data.key or ""))
        local success=ok and result~=false
        fingerprints.settings=""; settingsSnapshotCache.at=0
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="settings.palette.enable" then
        if not ctx or type(ctx.setSettingsPaletteEnabled)~="function" then return jsonResponse(400,{ok=false,error="palette_unavailable"}) end
        local ok,result,coreErr=pcall(ctx.setSettingsPaletteEnabled,data.value==true)
        local success=ok and result~=false
        fingerprints.settings=""; settingsSnapshotCache.at=0
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="settings.palette.color" then
        if not ctx or type(ctx.setSettingsPaletteColor)~="function" then return jsonResponse(400,{ok=false,error="palette_unavailable"}) end
        local ok,result,coreErr=pcall(ctx.setSettingsPaletteColor,tostring(data.key or ""),tostring(data.hex or ""))
        local success=ok and result~=false
        fingerprints.settings=""; settingsSnapshotCache.at=0
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="settings.palette.reset" then
        if not ctx or type(ctx.resetSettingsPalette)~="function" then return jsonResponse(400,{ok=false,error="palette_unavailable"}) end
        local ok,result,coreErr=pcall(ctx.resetSettingsPalette,tostring(data.scope or "all"),tostring(data.key or ""))
        local success=ok and result~=false
        fingerprints.settings=""; settingsSnapshotCache.at=0
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="settings.scale.apply" then
        if not ctx or type(ctx.applySettingsMenuScale)~="function" then return jsonResponse(400,{ok=false,error="scale_unavailable"}) end
        local ok,result,coreErr=pcall(ctx.applySettingsMenuScale,data.value)
        local success=ok and result~=false
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="settings.config.create" then
        if not ctx or type(ctx.createSettingsTradeConfig)~="function" then return jsonResponse(400,{ok=false,error="config_unavailable"}) end
        local sideValue=data.side=="sell" and "sell" or "buy"
        local ok,result,coreErr=pcall(ctx.createSettingsTradeConfig,sideValue,fromUtf8(data.name or ""))
        local success=ok and result~=false
        fingerprints.settings=""; settingsSnapshotCache.at=0; fingerprints[sideValue]=""
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="settings.config.delete" then
        if not ctx or type(ctx.deleteSettingsTradeConfig)~="function" then return jsonResponse(400,{ok=false,error="config_unavailable"}) end
        local sideValue=data.side=="sell" and "sell" or "buy"
        local ok,result,coreErr=pcall(ctx.deleteSettingsTradeConfig,sideValue,fromUtf8(data.name or ""))
        local success=ok and result~=false
        fingerprints.settings=""; settingsSnapshotCache.at=0; fingerprints[sideValue]=""
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="settings.config.merge" then
        if not ctx or type(ctx.mergeSettingsBuyConfigs)~="function" then return jsonResponse(400,{ok=false,error="merge_unavailable"}) end
        local files={}
        if type(data.files)=="table" then for i=1,#data.files do files[i]=fromUtf8(data.files[i]) end end
        local ok,result,coreErr=pcall(ctx.mergeSettingsBuyConfigs,fromUtf8(data.name or ""),files)
        local success=ok and result~=false
        fingerprints.settings=""; settingsSnapshotCache.at=0; fingerprints.buy=""
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="settings.config.convert" then
        if not ctx or type(ctx.convertSettingsLegacyConfig)~="function" then return jsonResponse(400,{ok=false,error="convert_unavailable"}) end
        local sideValue=data.side=="sell" and "sell" or "buy"
        local ok,result,coreErr=pcall(ctx.convertSettingsLegacyConfig,sideValue,fromUtf8(data.name or ""))
        local success=ok and result~=false
        fingerprints.settings=""; settingsSnapshotCache.at=0; fingerprints[sideValue]=""
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="settings.telegram.test" then
        if not ctx or type(ctx.testTelegramSettings)~="function" then return jsonResponse(400,{ok=false,error="telegram_unavailable"}) end
        local ok,result,coreErr=pcall(ctx.testTelegramSettings)
        local success=ok and result~=false
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="storage.scan" then
        local finder=safeStorageFinder()
        if not finder then return jsonResponse(400,{ok=false,error="storage_unavailable"}) end
        local stateValue={}
        if type(finder.getState)=="function" then
            local ok,value=pcall(finder.getState)
            if ok and type(value)=="table" then stateValue=value end
        end
        if stateValue.player_inventory_visible==true then
            storageRefreshRequested=true
            return jsonResponse(200,{ok=true,mode="inventory_auto"})
        end
        if type(finder.requestExternalScan)~="function" then return jsonResponse(400,{ok=false,error="storage_scan_unavailable"}) end
        local kind=tostring(data.kind or "")
        if kind=="all" or kind=="player_inventory" then kind="" end
        local ok,result=pcall(finder.requestExternalScan,kind~="" and kind or nil)
        storageRefreshRequested=true
        local success=ok and result~=false
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or "open_storage_first"})
    elseif action=="trade.currency.toggle" then
        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end
        if not ctx or type(ctx.toggleTradeCurrency)~="function" then return jsonResponse(400,{ok=false,error="currency_unavailable"}) end
        local ok,result=pcall(ctx.toggleTradeCurrency)
        fingerprints.buy=""; fingerprints.sell=""
        return jsonResponse(ok and result~=false and 200 or 400,{ok=ok and result~=false,currency=ok and result or nil,error=ok and result~=false and nil or tostring(result)})
    elseif action=="trade.scan.toggle" then
        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end
        if not ctx or type(ctx.toggleTradeScan)~="function" then return jsonResponse(400,{ok=false,error="scan_unavailable"}) end
        local ok,result=pcall(ctx.toggleTradeScan,side)
        sourceCache[side].at=0; fingerprints[side]=""
        return jsonResponse(ok and 200 or 400,{ok=ok,active=ok and result==true or false,error=ok and nil or tostring(result)})
    elseif action=="buy.source.refresh" then
        if side~="buy" then return jsonResponse(400,{ok=false,error="buy_only"}) end
        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end
        if not ctx or type(ctx.refreshBuySource)~="function" then return jsonResponse(400,{ok=false,error="refresh_unavailable"}) end
        local ok,result=pcall(ctx.refreshBuySource)
        sourceCache.buy.at=0; fingerprints.buy=""
        return jsonResponse(ok and result~=false and 200 or 400,{ok=ok and result~=false,error=ok and result~=false and nil or tostring(result)})
    elseif action=="prices.lookup" then
        local rawName=fromUtf8(tostring(data.name or ""))
        if rawName=="" then return jsonResponse(400,{ok=false,error="item_name_missing"}) end
        local ok,result=pcall(getAveragePriceDetails,rawName)
        if not ok then return jsonResponse(500,{ok=false,error=tostring(result)}) end
        return jsonResponse(200,{ok=true,data=result})
    elseif action=="prices.download" then
        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end
        if not ctx or type(ctx.downloadAveragePrices)~="function" then return jsonResponse(400,{ok=false,error="prices_unavailable"}) end
        local ok,result=pcall(ctx.downloadAveragePrices)
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
        local ok,result,err=pcall(ctx.loadTradeConfig,side,requestedName)
        local success=ok and result~=false
        sourceCache[side].at=0
        fingerprints[side]=""
        fingerprints.settings=""; settingsSnapshotCache.at=0
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and err or tostring(result))})
    elseif action=="trade.list.clear" then
        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end
        if not ctx or type(ctx.clearTradeList)~="function" then return jsonResponse(400,{ok=false,error="clear_unavailable"}) end
        local ok,result,coreErr=pcall(ctx.clearTradeList,side)
        local success=ok and result~=false
        fingerprints[side]=""
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="trade.item.undo" then
        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end
        if not ctx or type(ctx.undoTradeDelete)~="function" then return jsonResponse(400,{ok=false,error="undo_unavailable"}) end
        local ok,result,coreErr=pcall(ctx.undoTradeDelete,side)
        local success=ok and result~=false
        fingerprints[side]=""
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="buy.budget.preview" then
        if side~="buy" then return jsonResponse(400,{ok=false,error="buy_only"}) end
        if not ctx or type(ctx.previewBuyBudget)~="function" then return jsonResponse(400,{ok=false,error="budget_unavailable"}) end
        local ok,result,dataOrErr=pcall(ctx.previewBuyBudget,data.budget)
        local success=ok and result~=false
        return jsonResponse(success and 200 or 400,{ok=success,data=success and dataOrErr or nil,error=success and nil or (ok and dataOrErr or tostring(result))})
    elseif action=="buy.budget.apply" then
        if side~="buy" then return jsonResponse(400,{ok=false,error="buy_only"}) end
        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end
        if not ctx or type(ctx.distributeBuyBudget)~="function" then return jsonResponse(400,{ok=false,error="budget_unavailable"}) end
        local ok,result,dataOrErr=pcall(ctx.distributeBuyBudget,data.budget)
        local success=ok and result~=false
        fingerprints.buy=""
        return jsonResponse(success and 200 or 400,{ok=success,data=success and dataOrErr or nil,error=success and nil or (ok and dataOrErr or tostring(result))})
    elseif action=="buy.continue.toggle" then
        if side~="buy" then return jsonResponse(400,{ok=false,error="buy_only"}) end
        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end
        if not ctx or type(ctx.setBuyContinueMode)~="function" or type(ctx.getBuyContinueMode)~="function" then return jsonResponse(400,{ok=false,error="continue_unavailable"}) end
        local current=false
        local readOk,readValue=pcall(ctx.getBuyContinueMode)
        if readOk then current=readValue==true end
        local ok,result=pcall(ctx.setBuyContinueMode,not current)
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
        local ok,result,coreErr=pcall(ctx.setTradeFilterCategoryOrder,side,order)
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
        local ok,result,coreErr=pcall(ctx.setTradeItemCategory,side,item,category)
        local success=ok and result~=false
        fingerprints[side]=""
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})
    elseif action=="buy.average.apply" then
        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end
        if type(applyAveragePricesToBuyList)~="function" then return jsonResponse(400,{ok=false,error="average_unavailable"}) end
        local ok,result=pcall(applyAveragePricesToBuyList)
        fingerprints.buy=""
        return jsonResponse(ok and result~=false and 200 or 400,{ok=ok and result~=false,error=not ok and tostring(result) or (result==false and "average_failed" or nil)})
    elseif action=="trade.start" then
        local active=select(1,automationState(side))
        if active then
            if not ctx or type(ctx.cancelTrade)~="function" then return jsonResponse(400,{ok=false,error="cancel_unavailable"}) end
            local ok,result=pcall(ctx.cancelTrade); fingerprints[side]=""
            local success=ok and result~=false
            return jsonResponse(success and 200 or 400,{ok=success,cancelled=success,error=success and nil or tostring(result)})
        end
        if tradeBusy() then return jsonResponse(409,{ok=false,error="other_trade_active"}) end
        if not ctx or type(ctx.startTrade)~="function" then return jsonResponse(400,{ok=false,error="start_unavailable"}) end
        local ok,result=pcall(ctx.startTrade,side)
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
        local requested=req.query.page=="settings" and "settings" or req.query.page=="logs" and "logs" or req.query.page=="marketplace" and "marketplace" or req.query.page=="mods" and "mods" or req.query.page=="storage" and "storage" or req.query.page=="sell" and "sell" or "buy"
        local value=stateFor(requested)
        if tonumber(req.query.since)==tonumber(value.revision) then return response(204,"","application/json; charset=utf-8") end
        return jsonResponse(200,value)
    end
    if req.path=="/api/action" then return doAction(req) end
    local size,id=req.path:match("^/api/icon/(%d+)/(%d+)%.webp$")
    if size and id then
        if size~="24" and size~="48" and size~="256" then return response(404,"not_found") end
        if req.method~="GET" then return response(405,"method_not_allowed") end
        if not validToken(req) and tostring(req.query.token or "")~=token then return response(403,"forbidden") end
        if not itemIcons or type(itemIcons.getIcon)~="function" then return response(404,"icon_unavailable") end
        local ok,dataOrErr,extra=pcall(itemIcons.getIcon,size,id)
        if not ok or not dataOrErr then return response(404,tostring(ok and extra or dataOrErr)) end
        return response(200,dataOrErr,"image/webp","private, max-age=86400")
    end
    return response(404,"not_found")
end

local function closeClient(entry) pcall(function() entry.socket:close() end); clients[entry]=nil end
local function queueResponse(entry,out) entry.out,entry.outPos,entry.deadline=out,1,nowMs()+10000 end
local function flushClient(entry)
    if not entry.out then return false end
    local sent,err,last=entry.socket:send(entry.out,entry.outPos)
    local endPos=sent or last
    if endPos and endPos>=entry.outPos then entry.outPos=endPos+1 end
    if entry.outPos>#entry.out then closeClient(entry); return true end
    if err and err~="timeout" then closeClient(entry); return true end
    return false
end
local function service()
    if not server then return end
    local count=0; for _ in pairs(clients) do count=count+1 end
    while count<12 do
        local client=server:accept(); if not client then break end
        client:settimeout(0)
        local entry={socket=client,buffer="",deadline=nowMs()+5000}
        clients[entry]=true; count=count+1
    end
    local entries={}; for entry in pairs(clients) do entries[#entries+1]=entry end
    for _,entry in ipairs(entries) do
        if clients[entry] then
            if entry.out then
                flushClient(entry)
            else
                local chunk,err,partial=entry.socket:receive(4096)
                local data=chunk or partial
                if data and #data>0 then entry.buffer=entry.buffer..data end
                if #entry.buffer>81920 then
                    queueResponse(entry,response(413,"too_large"))
                else
                    local req,parseErr=parseRequest(entry.buffer)
                    if req then
                        local ok,out=pcall(handle,req)
                        if not ok then log("request failed: "..tostring(out)); out=response(500,"internal_error") end
                        queueResponse(entry,out)
                    elseif parseErr~="incomplete" then
                        queueResponse(entry,response(parseErr=="body_too_large" and 413 or 400,parseErr))
                    elseif nowMs()>entry.deadline or err=="closed" then closeClient(entry) end
                end
            end
            if clients[entry] and nowMs()>entry.deadline then closeClient(entry) end
        end
    end
end
local function startServer()
    if running then return true end
    local ok,socket=pcall(require,"socket")
    if not ok or type(socket)~="table" then return false,"luasocket_missing" end
    local ports={0}; for p=38460,38489 do ports[#ports+1]=p end
    for _,p in ipairs(ports) do
        local srv=socket.bind("127.0.0.1",p)
        if srv then
            srv:settimeout(0)
            local _,actual=srv:getsockname()
            server,port=srv,tonumber(actual) or p
            break
        end
    end
    if not server then return false,"port_unavailable" end
    if not ctx or not ctx.lua_thread or type(ctx.lua_thread.create)~="function" then server:close(); server=nil; return false,"thread_unavailable" end
    running=true
    ctx.lua_thread.create(function()
        while running do service(); ensureIframe(); ctx.wait(0) end
    end)
    log("bridge listening on 127.0.0.1:"..tostring(port))
    return true
end
local function stopServer()
    running=false
    local entries={}; for entry in pairs(clients) do entries[#entries+1]=entry end
    for _,entry in ipairs(entries) do closeClient(entry) end
    if server then pcall(function() server:close() end) end
    server,port=nil,nil
end
local function loadCefAdapter()
    local ok,module=pcall(require,"arizona-events")
    if ok and type(module)=="table" and type(module.eval)=="function" then
        return module
    end
    if type(raknetNewBitStream)~="function" or type(raknetBitStreamWriteInt8)~="function"
        or type(raknetBitStreamWriteInt16)~="function" or type(raknetBitStreamWriteInt32)~="function"
        or type(raknetBitStreamWriteString)~="function" or type(raknetEmulPacketReceiveBitStream)~="function"
        or type(raknetDeleteBitStream)~="function" then
        return nil
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
    }
end

local function loadItemIcons()
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

function M.open_html(page,settingsSection)
    if page=="buy" or page=="sell" or page=="settings" or page=="logs" or page=="marketplace" or page=="mods" or page=="storage" then currentPage=page end
    if currentPage=="settings" and settingsSection=="appearance" then currentSettingsSection="appearance" else currentSettingsSection=nil end
    suppressAutoOpen=false
    if currentPage=="marketplace" and ctx and type(ctx.ensureMarketplaceLoaded)=="function" then pcall(ctx.ensureMarketplaceLoaded) end
    if currentPage=="buy" and ctx and type(ctx.ensureHtmlTradeCurrency)=="function" then
        pcall(ctx.ensureHtmlTradeCurrency,"SA")
        fingerprints.buy=""
    end
    if not running then
        local ok,err=startServer()
        if not ok then if ctx and ctx.notify then pcall(ctx.notify,"HTML интерфейс недоступен: "..tostring(err)) end; return false end
    end
    if not acef or type(acef.eval)~="function" then
        if ctx and ctx.notify then pcall(ctx.notify,"CEF API недоступен. Lua интерфейс продолжает работать.") end
        return false
    end
    local menuWasVisible=ctx and type(ctx.getCoreMenuVisible)=="function" and ctx.getCoreMenuVisible()==true
    if menuWasVisible then setMenuVisible(false) end
    local ok=injectIframe()
    if ok then
        if ctx and type(ctx.setPreferredInterfaceMode)=="function" then pcall(ctx.setPreferredInterfaceMode,"html") end
    elseif menuWasVisible then
        setMenuVisible(true)
    end
    if not ok and ctx and ctx.notify then pcall(ctx.notify,"Не удалось открыть CEF интерфейс. Используйте Lua режим.") end
    return ok
end
function M.is_open()
    return htmlOpen==true
end
function M.open_preview(bounds,page)
    if page=="buy" or page=="sell" or page=="settings" or page=="logs" or page=="marketplace" or page=="mods" or page=="storage" then currentPage=page end
    if not running then
        local ok,err=startServer()
        if not ok then return false,err end
    end
    if not acef or type(acef.eval)~="function" then return false,"cef_unavailable" end
    return injectPreviewIframe(bounds)
end
function M.close_preview()
    removePreviewIframe()
    return true
end
function M.close_html()
    suppressAutoOpen=true
    removeIframe()
    removePreviewIframe()
    return true
end
function M.init(context)
    ctx=context
    token=makeToken()
    htmlRoot=ctx.getWorkingDirectory().."\\ArzMarket\\html"
    htmlWindowStatePath=ctx.getWorkingDirectory().."\\ArzMarket\\html_window_state.json"
    loadWindowState()
    loadItemIcons()
    acef=loadCefAdapter()
    local started,err=startServer()
    if not started then log("bridge disabled: "..tostring(err)) end
    startStorageSnapshotWorker()
    return true
end
function M.render(context)
    ctx=context or ctx
    local imgui=ctx.imgui

    -- The Lua menu item "HTML" is an action, not a real page.
    -- As soon as the user selects it, immediately hand control to CEF.
    -- close_html() deliberately sets suppressAutoOpen=true when returning to Lua,
    -- so selecting this menu item explicitly clears that guard again.
    if acef and running and not htmlOpen then
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
        if imgui.Button("Повторить запуск",imgui.ImVec2(220,34)) then startServer() end
        return
    end
    if not htmlOpen then
        imgui.Text("Не удалось автоматически открыть HTML интерфейс.")
        imgui.TextWrapped("Повторная попытка выполняется автоматически.")
    end
end
function M.shutdown()
    storageWorkerRunning=false
    removeIframe()
    removePreviewIframe()
    stopServer()
    if itemIcons and type(itemIcons.shutdown)=="function" then pcall(itemIcons.shutdown) end
    return true
end

return M
