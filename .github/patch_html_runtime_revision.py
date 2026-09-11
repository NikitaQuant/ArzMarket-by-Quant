from pathlib import Path

path = Path("modules/arz_html_ui.lua")
text = path.read_text(encoding="utf-8")

old_fp = '''local function fingerprint(side,list)
    local out={side,tostring(#list)}
    for i=1,#list do
        local x=list[i]
        out[#out+1]=table.concat({
            tostring(x.name or x.item or ""),tostring(x.price or ""),tostring(x.price_vc or ""),
            tostring(x.count or ""),tostring(x.continue or ""),tostring(x.enabled~=false),
            tostring(x.maximum==true),tostring(x.all_count or ""),tostring(x.slot_id or "")
        },"\\30")
    end
    return table.concat(out,"\\31")
end
local function touchRevision(side,list)
    local value=fingerprint(side,list)
    if value~=fingerprints[side] then
        fingerprints[side]=value
        revision[side]=revision[side]+1
    end
end
'''
new_fp = '''local function fingerprint(side,list,runtimeKey)
    local out={side,tostring(#list),tostring(runtimeKey or "")}
    for i=1,#list do
        local x=list[i]
        out[#out+1]=table.concat({
            tostring(x.name or x.item or ""),tostring(x.price or ""),tostring(x.price_vc or ""),
            tostring(x.count or ""),tostring(x.continue or ""),tostring(x.enabled~=false),
            tostring(x.maximum==true),tostring(x.all_count or ""),tostring(x.slot_id or "")
        },"\\30")
    end
    return table.concat(out,"\\31")
end
local function touchRevision(side,list,runtimeKey)
    local value=fingerprint(side,list,runtimeKey)
    if value~=fingerprints[side] then
        fingerprints[side]=value
        revision[side]=revision[side]+1
    end
end
'''
if text.count(old_fp) != 1:
    raise SystemExit("fingerprint block not found exactly once")
text = text.replace(old_fp, new_fp, 1)

old_state = '''    local buy,sell=lists()
    local list=page=="buy" and buy or sell
    touchRevision(page,list)
    local items={}
    for i=1,#list do items[i]=itemDto(list[i],i,page) end
    local address,serverPort="",0
    if type(sampGetCurrentServerAddress)=="function" then
        local ok,a,p=pcall(sampGetCurrentServerAddress)
        if ok then address,serverPort=tostring(a or ""),tonumber(p) or 0 end
    end
    local snapshot=automationSnapshot()
    local active=snapshot[page]==true
    local score=saneNumber(snapshot.score,0) or 0
    local total=saneNumber(snapshot.score_from,0) or 0
    local busy=snapshot.sell==true or snapshot.buy==true
    local cfg=configName(page)
'''
new_state = '''    local buy,sell=lists()
    local list=page=="buy" and buy or sell
    local snapshot=automationSnapshot()
    local active=snapshot[page]==true
    local score=saneNumber(snapshot.score,0) or 0
    local total=saneNumber(snapshot.score_from,0) or 0
    local busy=snapshot.sell==true or snapshot.buy==true
    local cfg=configName(page)
    local runtimeKey=table.concat({
        tostring(active),tostring(busy),tostring(snapshot.buy==true),tostring(snapshot.sell==true),
        tostring(score),tostring(total),tostring(cfg)
    },"\\30")
    touchRevision(page,list,runtimeKey)
    local items={}
    for i=1,#list do items[i]=itemDto(list[i],i,page) end
    local address,serverPort="",0
    if type(sampGetCurrentServerAddress)=="function" then
        local ok,a,p=pcall(sampGetCurrentServerAddress)
        if ok then address,serverPort=tostring(a or ""),tonumber(p) or 0 end
    end
'''
if text.count(old_state) != 1:
    raise SystemExit("stateFor block not found exactly once")
text = text.replace(old_state, new_state, 1)

text = text.replace("module_version = 5,", "module_version = 6,", 1)

if "touchRevision(page,list,runtimeKey)" not in text:
    raise SystemExit("runtime revision patch missing")

path.write_text(text, encoding="utf-8", newline="\n")
