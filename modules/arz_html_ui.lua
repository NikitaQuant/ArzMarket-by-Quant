local M = {
    api_version = 1,
    module_version = 12,
    id = "arz_html_ui",
    title = "HTML",
    section = "Интерфейс",
    order = 999,
    no_scroll = true
}

local ctx, acef, server, port, itemIcons
local running, htmlOpen, suppressAutoOpen = false, false, false
local clients, token, htmlRoot, currentPage = {}, "", "", "buy"
local revision, fingerprints = { buy = 1, sell = 1 }, { buy = "", sell = "" }
local lastInjectCheck = 0
local sourceCache = { buy = {at=0,data={}}, sell = {at=0,data={}} }
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
local function itemDto(item,index,side)
    local id=resolvedItemId(item)
    return {
        identity={index=index,name=toUtf8(item.name or item.item or ""),item_id=id,slot_id=item.slot_id},
        name=toUtf8(item.name or item.item or ("Item #"..tostring(index))),
        item_id=id,
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
            tostring(x.maximum==true),tostring(x.count_maximum or ""),tostring(x.all_count or ""),tostring(x.slot_id or "")
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
                out[#out+1]={index=i,name=toUtf8(x),item_id=id}
            elseif side=="sell" and type(x)=="table" then
                local name=x.item or x.name or ("Item #"..tostring(i))
                local id=x.item_id or x.foreign_item_id or x.id
                if id==nil and itemIcons and itemIcons.resolveItemId then id=itemIcons.resolveItemId(name) end
                out[#out+1]={index=i,name=toUtf8(name),all_count=saneNumber(x.all_count,saneNumber(x.count,0)),
                    slot_count=saneNumber(x.count,0),slot_id=x.slot_id,item_id=id}
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
            tostring(x.slot_count or ""),tostring(x.slot_id or "")
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
local function selectLuaPage(side)
    if ctx and type(ctx.selectCorePage)=="function" then
        local ok,result=pcall(ctx.selectCorePage,side=="sell" and 1 or 2)
        if ok and result~=false then return true end
    end
    return false
end

local function stateFor(page)
    page=page=="sell" and "sell" or "buy"
    currentPage=page
    local buy,sell=lists()
    local list=page=="buy" and buy or sell
    local snapshot=automationSnapshot()
    local active=snapshot[page]==true
    local score=saneNumber(snapshot.score,0) or 0
    local total=saneNumber(snapshot.score_from,0) or 0
    local busy=snapshot.sell==true or snapshot.buy==true
    local cfg=configName(page)
    local configs=configList(page)
    local source=sources(page)
    local uiState={currency="SA",buy_scan=false,sell_scan=false}
    if ctx and type(ctx.getTradeUiState)=="function" then
        local ok,value=pcall(ctx.getTradeUiState)
        if ok and type(value)=="table" then uiState=value end
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
        tostring(undoCount),tostring(buyContinue),sourceFingerprint(source)
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
        common={uiMode="html",activeConfig=cfg~="" and cfg:gsub("%.json$","") or "",configs=configs,
            currencyMode=currency,buyScan=buyScan,sellScan=sellScan,undoCount=undoCount,buyContinue=buyContinue,
            automation=active,tradeBusy=busy,automationBuy=snapshot.buy==true,automationSell=snapshot.sell==true,
            automationScore=score,automationTotal=total,
            serverAddress=address,serverPort=serverPort,icons=iconStatus},
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
local function removeIframe()
    if acef and type(acef.eval)=="function" then pcall(acef.eval,"var f=document.getElementById('arzmarket-html-frame');if(f)f.remove();") end
    htmlOpen=false
    setCefCursor(false)
end
local function injectIframe()
    if not acef or type(acef.eval)~="function" or not port then return false end
    local url="http://127.0.0.1:"..tostring(port).."/ui"
    local code="var o=document.getElementById('arzmarket-html-frame');if(o)o.remove();"..
        "var f=document.createElement('iframe');f.id='arzmarket-html-frame';f.src="..quoteJs(url)..";"..
        "f.style.position='fixed';f.style.left='0';f.style.top='0';f.style.width='100vw';f.style.height='100vh';"..
        "f.style.border='0';f.style.background='transparent';f.style.zIndex='2147483000';document.body.appendChild(f);"
    local ok=pcall(acef.eval,code)
    if ok then htmlOpen=true; lastInjectCheck=nowMs(); setCefCursor(true) end
    return ok
end
local function ensureIframe()
    if not htmlOpen or not acef or nowMs()-lastInjectCheck<1500 then return end
    lastInjectCheck=nowMs()
    local url="http://127.0.0.1:"..tostring(port).."/ui"
    pcall(acef.eval,"if(!document.getElementById('arzmarket-html-frame')){var f=document.createElement('iframe');f.id='arzmarket-html-frame';f.src="..quoteJs(url)..";f.style.position='fixed';f.style.left='0';f.style.top='0';f.style.width='100vw';f.style.height='100vh';f.style.border='0';f.style.zIndex='2147483000';document.body.appendChild(f);}")
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
    return o=="http://127.0.0.1:"..tostring(port) or o=="http://localhost:"..tostring(port)
end
local function safeStatic(path)
    if path:find("..",1,true) or path:find("\\",1,true) or path:find("%%00") or path:sub(1,1)=="/" then return nil end
    return path:match("^[%w%._%-%/]+$") and path or nil
end

local function doAction(req)
    if req.method~="POST" then return response(405,"method_not_allowed") end
    if not validToken(req) or not validOrigin(req) then return response(403,"forbidden") end
    local request=decode(req.body)
    if type(request)~="table" or type(request.action)~="string" then return jsonResponse(400,{ok=false,error="invalid_json"}) end
    local action=request.action
    local data=type(request.payload)=="table" and request.payload or {}
    local side=data.side=="sell" and "sell" or "buy"
    if action=="ui.close" then
        currentPage=side; suppressAutoOpen=true; removeIframe(); setMenuVisible(false)
        return jsonResponse(200,{ok=true})
    elseif action=="ui.switch_mode" then
        currentPage=side
        local switched=selectLuaPage(side)
        suppressAutoOpen=true
        removeIframe()
        return jsonResponse(switched and 200 or 500,{ok=switched,mode="lua",page=side,error=switched and nil or "lua_page_unavailable"})
    elseif action=="ui.navigate" then
        currentPage=side
        return jsonResponse(200,{ok=true,page=side})
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
    elseif action=="prices.download" then
        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end
        if not ctx or type(ctx.downloadAveragePrices)~="function" then return jsonResponse(400,{ok=false,error="prices_unavailable"}) end
        local ok,result=pcall(ctx.downloadAveragePrices)
        return jsonResponse(ok and result~=false and 200 or 400,{ok=ok and result~=false,error=ok and result~=false and nil or tostring(result)})
    elseif action=="trade.config.load" then
        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end
        if not ctx or type(ctx.loadTradeConfig)~="function" then return jsonResponse(400,{ok=false,error="config_loader_unavailable"}) end
        local ok,result,err=pcall(ctx.loadTradeConfig,side,data.name)
        local success=ok and result~=false
        sourceCache[side].at=0
        fingerprints[side]=""
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
        return response(200,body,mime[rel:match("%.([%w]+)$") or ""] or "application/octet-stream","public, max-age=3600")
    end
    if req.path=="/api/state" then
        if req.method~="GET" then return response(405,"method_not_allowed") end
        if not validToken(req) then return response(403,"forbidden") end
        local value=stateFor(req.query.page=="sell" and "sell" or "buy")
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
local function queueResponse(entry,out) entry.out,entry.outPos,entry.deadline=out,1,nowMs()+4000 end
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
    while count<6 do
        local client=server:accept(); if not client then break end
        client:settimeout(0)
        local entry={socket=client,buffer="",deadline=nowMs()+2500}
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

function M.open_html(page)
    if page=="buy" or page=="sell" then currentPage=page end
    suppressAutoOpen=false
    if not running then
        local ok,err=startServer()
        if not ok then if ctx and ctx.notify then pcall(ctx.notify,"HTML интерфейс недоступен: "..tostring(err)) end; return false end
    end
    if not acef or type(acef.eval)~="function" then
        if ctx and ctx.notify then pcall(ctx.notify,"Не найдена библиотека arizona-events. Lua интерфейс продолжает работать.") end
        return false
    end
    local ok=injectIframe()
    if not ok and ctx and ctx.notify then pcall(ctx.notify,"Не удалось открыть CEF интерфейс. Используйте Lua режим.") end
    return ok
end
function M.init(context)
    ctx=context
    token=makeToken()
    htmlRoot=ctx.getWorkingDirectory().."\\ArzMarket\\html"
    loadItemIcons()
    local ok,module=pcall(require,"arizona-events")
    if ok and type(module)=="table" and type(module.eval)=="function" then acef=module end
    local started,err=startServer()
    if not started then log("bridge disabled: "..tostring(err)) end
    return true
end
function M.render(context)
    ctx=context or ctx
    local imgui=ctx.imgui
    if not acef then
        imgui.Text("HTML интерфейс ArzMarket")
        imgui.Spacing()
        imgui.TextWrapped("Не найдена библиотека arizona-events. Lua интерфейс продолжает работать.")
        return
    end
    if not running then
        imgui.Text("Local bridge не запущен.")
        if imgui.Button("Повторить запуск",imgui.ImVec2(220,34)) then startServer() end
        return
    end
    if not htmlOpen and not suppressAutoOpen then M.open_html(currentPage) end
    if not htmlOpen then
        imgui.Text("HTML интерфейс закрыт.")
        if imgui.Button("Открыть HTML",imgui.ImVec2(220,34)) then suppressAutoOpen=false; M.open_html(currentPage) end
    end
end
function M.shutdown()
    removeIframe()
    stopServer()
    if itemIcons and type(itemIcons.shutdown)=="function" then pcall(itemIcons.shutdown) end
    return true
end

return M
