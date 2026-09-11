from pathlib import Path

path = Path("modules/arz_html_ui.lua")
text = path.read_text(encoding="utf-8")

text = text.replace("module_version = 6,", "module_version = 7,", 1)

source_marker = '''local function automationSnapshot()
'''
source_helper = '''local function sourceFingerprint(source)
    local out={tostring(type(source)=="table" and #source or 0)}
    for i=1,#source do
        local x=source[i]
        out[#out+1]=table.concat({
            tostring(x.name or ""),tostring(x.item_id or ""),tostring(x.all_count or ""),
            tostring(x.slot_count or ""),tostring(x.slot_id or "")
        },"\\30")
    end
    return table.concat(out,"\\31")
end

'''
if text.count(source_marker) != 1:
    raise SystemExit("automationSnapshot marker not found exactly once")
text = text.replace(source_marker, source_helper + source_marker, 1)

old_state = '''    local cfg=configName(page)
    local runtimeKey=table.concat({
        tostring(active),tostring(busy),tostring(snapshot.buy==true),tostring(snapshot.sell==true),
        tostring(score),tostring(total),tostring(cfg)
    },"\\30")
    touchRevision(page,list,runtimeKey)
    local items={}
'''
new_state = '''    local cfg=configName(page)
    local source=sources(page)
    local runtimeKey=table.concat({
        tostring(active),tostring(busy),tostring(snapshot.buy==true),tostring(snapshot.sell==true),
        tostring(score),tostring(total),tostring(cfg),sourceFingerprint(source)
    },"\\30")
    touchRevision(page,list,runtimeKey)
    local items={}
'''
if text.count(old_state) != 1:
    raise SystemExit("state runtime key block not found exactly once")
text = text.replace(old_state, new_state, 1)

old_data = '''        data={items=items,source=sources(page)}
'''
new_data = '''        data={items=items,source=source}
'''
if text.count(old_data) != 1:
    raise SystemExit("state source return not found exactly once")
text = text.replace(old_data, new_data, 1)

old_mutations = '''local numeric={price=true,price_vc=true,count=true,continue=true,count_maximum=true}
local boolean={enabled=true,maximum=true}
local function updateItem(side,payload)
    local item,_,err=findItem(side,payload.identity)
    if not item then return false,err end
    for key,value in pairs(type(payload.patch)=="table" and payload.patch or {}) do
        if numeric[key] then
            local n=saneNumber(value)
            if not n or n<0 or n>2147483647 then return false,"invalid_"..key end
            if key=="count" or key=="continue" or key=="count_maximum" then n=math.floor(n) end
            item[key]=n
        elseif boolean[key] then
            if type(value)~="boolean" then return false,"invalid_"..key end
            item[key]=value
        else
            return false,"field_not_allowed"
        end
    end
    local ok,saveErr=persist(side)
    fingerprints[side]=""
    return ok,saveErr
end
local function removeItem(side,payload)
    local _,index,err=findItem(side,payload.identity)
    if not index then return false,err end
    local buy,sell=lists()
    table.remove(side=="buy" and buy or sell,index)
    if type(tradeFilterInvalidate)=="function" then pcall(tradeFilterInvalidate,side) end
    local ok,saveErr=persist(side)
    fingerprints[side]=""
    return ok,saveErr
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
    local item
    if side=="buy" then
        item={continue=1,enabled=true,maximum=false,count_maximum=0,price_vc=10,name=luaName,price=10,count=1,item_id=src.item_id}
    else
        item={enabled=true,price_vc=9,maximum=true,name=luaName,price=9,count=1,
            slot_count=src.slot_count,slot_id=src.slot_id,all_count=src.all_count,item_id=src.item_id}
    end
    if type(addToData)=="function" then pcall(addToData,item,list,nil) else table.insert(list,item) end
    if type(tradeFilterMarkNewItem)=="function" then pcall(tradeFilterMarkNewItem,side,item) end
    if type(tradeFilterInvalidate)=="function" then pcall(tradeFilterInvalidate,side) end
    sourceCache[side].at=0
    local ok,saveErr=persist(side)
    fingerprints[side]=""
    return ok,saveErr
end
'''
new_mutations = '''local numeric={price=true,price_vc=true,count=true,continue=true,count_maximum=true}
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
    local buy,sell=lists()
    local list=side=="buy" and buy or sell
    local removed=table.remove(list,index)
    local ok,saveErr=persist(side)
    if not ok then
        table.insert(list,index,removed)
    end
    if type(tradeFilterInvalidate)=="function" then pcall(tradeFilterInvalidate,side) end
    fingerprints[side]=""
    return ok,saveErr
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
    local item
    if side=="buy" then
        item={continue=1,enabled=true,maximum=false,count_maximum=0,price_vc=10,name=luaName,price=10,count=1,item_id=src.item_id}
    else
        item={enabled=true,price_vc=9,maximum=true,name=luaName,price=9,count=1,
            slot_count=src.slot_count,slot_id=src.slot_id,all_count=src.all_count,item_id=src.item_id}
    end
    if type(addToData)=="function" then
        local addOk=pcall(addToData,item,list,nil)
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
'''
if text.count(old_mutations) != 1:
    raise SystemExit("mutation block not found exactly once")
text = text.replace(old_mutations, new_mutations, 1)

for marker in (
    "local function sourceFingerprint(source)",
    "sourceFingerprint(source)",
    "local updates={}",
    "table.insert(list,index,removed)",
    "return false,saveErr",
):
    if marker not in text:
        raise SystemExit("missing safety marker: " + marker)

path.write_text(text, encoding="utf-8", newline="\n")
