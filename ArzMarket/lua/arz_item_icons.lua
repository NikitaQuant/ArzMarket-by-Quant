local M = { api_version = 1, module_version = 3 }

local ctx
local catalog = {}
local catalogMeta = {}
local itemsZipPath
local frontendZipPath
local zipIndex
local aliases
local iconCache = {}
local iconCacheOrder = {}
local ICON_CACHE_LIMIT = 64

local function log(message)
    print("[ArzMarket HTML] icons: " .. tostring(message))
end

local function u16(data, pos)
    local a,b = data:byte(pos,pos+1)
    if not a or not b then return nil end
    return a + b * 256
end

local function u32(data, pos)
    local a,b,c,d = data:byte(pos,pos+3)
    if not a or not b or not c or not d then return nil end
    return a + b*256 + c*65536 + d*16777216
end

local function fileExists(path)
    local f = type(path) == "string" and io.open(path,"rb") or nil
    if not f then return false end
    f:close()
    return true
end

local function readAll(path)
    local f = io.open(path,"rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

local function writeAll(path, data)
    local f = io.open(path,"wb")
    if not f then return false end
    f:write(data)
    f:close()
    return true
end

local function gameDir()
    if type(getGameDirectory) == "function" then
        local ok, value = pcall(getGameDirectory)
        if ok and type(value) == "string" and value ~= "" then return value end
    end
    local wd = ctx and type(ctx.getWorkingDirectory) == "function" and ctx.getWorkingDirectory() or ""
    return wd:gsub("[\\/]+moonloader[\\/]?$","")
end

local function ensureDir(path)
    if ctx and type(ctx.doesDirectoryExist) == "function" and ctx.doesDirectoryExist(path) then return true end
    if ctx and type(ctx.createDirectory) == "function" then
        local ok = pcall(ctx.createDirectory, path)
        if ok then return true end
    end
    return false
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

local function lowerLocal(value)
    value=tostring(value or "")
    if type(string.nlower)=="function" then
        local ok,result=pcall(string.nlower,value)
        if ok and type(result)=="string" then return result end
    end
    return value:lower()
end

local function cleanUtf8(value)
    value=tostring(value or "")
    value=value:gsub("{[%x][%x][%x][%x][%x][%x]}","")
    return value:gsub("%s+"," "):gsub("^%s+",""):gsub("%s+$","")
end

local function normalizeLuaName(value)
    return cleanUtf8(toUtf8(lowerLocal(value)))
end

local function normalizeUtf8Name(value)
    return cleanUtf8(toUtf8(lowerLocal(fromUtf8(value))))
end

local function locateFiles()
    local root = gameDir()
    local itemCandidates = { root .. "\\arizona\\items.zip", root .. "\\items.zip" }
    local frontCandidates = { root .. "\\frontend.zip", root .. "\\arizona\\frontend.zip" }
    for _,p in ipairs(itemCandidates) do if fileExists(p) then itemsZipPath = p break end end
    for _,p in ipairs(frontCandidates) do if fileExists(p) then frontendZipPath = p break end end
end

local function fileStamp(path)
    if not path then return nil end
    if ctx and ctx.lfs and type(ctx.lfs.attributes)=="function" then
        local ok,attr=pcall(ctx.lfs.attributes,path)
        if ok and type(attr)=="table" then return tostring(attr.size or "")..":"..tostring(attr.modification or "") end
    end
    local f=io.open(path,"rb")
    if not f then return nil end
    local size=f:seek("end")
    f:close()
    return tostring(size or "")
end

local function findEocd(tail)
    for pos = #tail-21,1,-1 do
        if tail:byte(pos)==0x50 and tail:byte(pos+1)==0x4B and tail:byte(pos+2)==0x05 and tail:byte(pos+3)==0x06 then return pos end
    end
end

local function readCentralDirectory(path)
    local f = io.open(path,"rb")
    if not f then return nil,nil,"open_failed" end
    local total = f:seek("end")
    if not total or total < 22 then f:close(); return nil,nil,"invalid_zip" end
    local tailSize = math.min(total,65557)
    f:seek("set",total-tailSize)
    local tail = f:read(tailSize)
    local eocd = tail and findEocd(tail)
    if not eocd then f:close(); return nil,nil,"eocd_missing" end
    local size,offset = u32(tail,eocd+12),u32(tail,eocd+16)
    if not size or not offset then f:close(); return nil,nil,"central_invalid" end
    f:seek("set",offset)
    local central = f:read(size)
    if not central or #central ~= size then f:close(); return nil,nil,"central_short" end
    return f,central
end

local function parseEntries(central,wanted)
    local result={}
    local pos=1
    while pos+45<=#central do
        if u32(central,pos)~=0x02014B50 then break end
        local method=u16(central,pos+10)
        local compSize=u32(central,pos+20)
        local uncompSize=u32(central,pos+24)
        local nameLen=u16(central,pos+28)
        local extraLen=u16(central,pos+30)
        local commentLen=u16(central,pos+32)
        local localOffset=u32(central,pos+42)
        if not method or not compSize or not nameLen or not extraLen or not commentLen or not localOffset then break end
        local nameStart=pos+46
        local nameEnd=nameStart+nameLen-1
        if nameEnd>#central then break end
        local name=central:sub(nameStart,nameEnd)
        if not wanted or wanted(name) then
            result[name]={method=method,comp_size=compSize,uncomp_size=uncompSize,local_offset=localOffset}
        end
        pos=nameEnd+1+extraLen+commentLen
    end
    return result
end

local function readStoredEntry(file,entry)
    if not file or type(entry)~="table" then return nil,"entry_missing" end
    if tonumber(entry.method)~=0 then return nil,"compressed_unsupported" end
    file:seek("set",tonumber(entry.local_offset) or 0)
    local h=file:read(30)
    if not h or #h<30 or u32(h,1)~=0x04034B50 then return nil,"bad_local_header" end
    local nameLen,extraLen=u16(h,27),u16(h,29)
    if not nameLen or not extraLen then return nil,"bad_local_lengths" end
    file:seek("set",(tonumber(entry.local_offset) or 0)+30+nameLen+extraLen)
    local size=tonumber(entry.comp_size) or 0
    if size<0 or size>32*1024*1024 then return nil,"entry_too_large" end
    local data=file:read(size)
    if not data or #data~=size then return nil,"short_read" end
    return data
end

local function cachePath()
    local wd=ctx and ctx.getWorkingDirectory and ctx.getWorkingDirectory() or "."
    return wd.."\\ArzMarket\\cache\\item_catalog.json"
end

local function loadCatalogFile()
    local raw=readAll(cachePath())
    if not raw or type(decodeJson)~="function" then return false end
    local ok,parsed=pcall(decodeJson,raw)
    if not ok or type(parsed)~="table" or type(parsed.by_name)~="table" then return false end
    local meta=type(parsed.meta)=="table" and parsed.meta or {}
    if frontendZipPath and meta.frontend_stamp and meta.frontend_stamp~=fileStamp(frontendZipPath) then return false end
    catalog=parsed.by_name
    catalogMeta=meta
    return next(catalog)~=nil
end

local function extractJsonArray(text,startPos)
    local depth,inString,escaped=0,false,false
    local beginPos
    for i=startPos,#text do
        local ch=text:sub(i,i)
        if inString then
            if escaped then escaped=false elseif ch=="\\" then escaped=true elseif ch=='"' then inString=false end
        else
            if ch=='"' then inString=true
            elseif ch=="[" then depth=depth+1; if not beginPos then beginPos=i end
            elseif ch=="]" then depth=depth-1; if beginPos and depth==0 then return text:sub(beginPos,i) end end
        end
    end
end

local function buildCatalogFromFrontend()
    if not frontendZipPath or type(decodeJson)~="function" or type(encodeJson)~="function" then return false,"frontend_missing" end
    local f,central,err=readCentralDirectory(frontendZipPath)
    if not f then return false,err end
    local entries=parseEntries(central,function(name) return name=="frontend/svelte_js/main.bundle.js" end)
    local bundle,readErr=readStoredEntry(f,entries["frontend/svelte_js/main.bundle.js"])
    f:close()
    if not bundle then return false,readErr end
    local marker="var ITEMS_CONST="
    local p=bundle:find(marker,1,true)
    if not p then return false,"items_const_missing" end
    local jsonText=extractJsonArray(bundle,p+#marker)
    bundle=nil
    if not jsonText then return false,"items_const_parse_failed" end
    local ok,items=pcall(decodeJson,jsonText)
    jsonText=nil
    if not ok or type(items)~="table" then return false,"items_const_decode_failed" end

    local byName={}
    local count=0
    for _,item in ipairs(items) do
        if type(item)=="table" and item.id~=nil then
            local key=normalizeUtf8Name(item.name)
            if key~="" then
                if byName[key]==nil then byName[key]=tostring(item.id) end
                count=count+1
            end
        end
    end
    items=nil
    if next(byName)==nil then return false,"catalog_empty" end
    catalog=byName
    catalogMeta={version=1,items_count=count,source="frontend.zip",frontend_stamp=fileStamp(frontendZipPath)}

    local wd=ctx and ctx.getWorkingDirectory and ctx.getWorkingDirectory() or "."
    local arzDir=wd.."\\ArzMarket"
    local cacheDir=arzDir.."\\cache"
    ensureDir(arzDir); ensureDir(cacheDir)
    local encOk,serialized=pcall(encodeJson,{version=1,meta=catalogMeta,by_name=byName})
    if encOk and type(serialized)=="string" then writeAll(cachePath(),serialized) end
    return true
end

local function ensureCatalog()
    if next(catalog)~=nil then return true end
    if loadCatalogFile() then return true end
    local ok,err=buildCatalogFromFrontend()
    if not ok then log("catalog unavailable: "..tostring(err)) end
    return ok,err
end

local function buildZipIndex()
    if zipIndex then return true end
    if not itemsZipPath then locateFiles() end
    if not itemsZipPath then return false,"items_zip_missing" end
    local f,central,err=readCentralDirectory(itemsZipPath)
    if not f then return false,err end
    local entries=parseEntries(central,function(name)
        if name=="icons/aliases.json" then return true end
        return name:match("^icons/24/%d+%.webp$") or name:match("^icons/48/%d+%.webp$") or name:match("^icons/256/%d+%.webp$")
    end)
    local index={["24"]={},["48"]={},["256"]={}}
    for name,entry in pairs(entries) do
        local size,id=name:match("^icons/(24)/(%d+)%.webp$")
        if not size then size,id=name:match("^icons/(48)/(%d+)%.webp$") end
        if not size then size,id=name:match("^icons/(256)/(%d+)%.webp$") end
        if size and id then index[size][id]=entry end
    end
    local aliasEntry=entries["icons/aliases.json"]
    if aliasEntry then
        local raw=readStoredEntry(f,aliasEntry)
        if raw then
            aliases={}
            for sourceId,targetId in raw:gmatch('"(%d+)"%s*:%s*(%d+)') do aliases[sourceId]=targetId end
        end
    end
    f:close()
    zipIndex=index
    return true
end

local function resolveAlias(id)
    local current=tostring(id or "")
    if current=="" then return nil end
    if not aliases then return current end
    local seen={}
    for _=1,6 do
        if seen[current] then break end
        seen[current]=true
        local nextId=aliases[current]
        if not nextId then break end
        current=tostring(nextId)
    end
    return current
end

local function cachePut(key,value)
    if iconCache[key]==nil then iconCacheOrder[#iconCacheOrder+1]=key end
    iconCache[key]=value
    while #iconCacheOrder>ICON_CACHE_LIMIT do local old=table.remove(iconCacheOrder,1); iconCache[old]=nil end
end

function M.resolveItemId(name)
    ensureCatalog()
    local id=catalog[normalizeLuaName(name)]
    return id~=nil and tostring(id) or nil
end

function M.getIcon(size,id)
    size=tostring(size or "")
    if size~="24" and size~="48" and size~="256" then return nil,"invalid_size" end
    id=tostring(id or ""):match("^(%d+)$")
    if not id then return nil,"invalid_id" end
    local key=size..":"..id
    if iconCache[key] then return iconCache[key] end
    local ok,err=buildZipIndex()
    if not ok then return nil,err end
    local resolved=resolveAlias(id)
    local entry=zipIndex[size][id] or zipIndex[size][resolved]
    if not entry then return nil,"icon_missing" end
    local f=io.open(itemsZipPath,"rb")
    if not f then return nil,"items_zip_open_failed" end
    local data,readErr=readStoredEntry(f,entry)
    f:close()
    if not data then return nil,readErr end
    cachePut(key,data)
    return data
end

function M.getStatus()
    return {
        catalog_loaded=next(catalog)~=nil,
        catalog_items=catalogMeta.items_count,
        items_zip=itemsZipPath~=nil,
        frontend_zip=frontendZipPath~=nil,
        zip_indexed=zipIndex~=nil
    }
end

function M.init(context)
    ctx=context
    locateFiles()
    loadCatalogFile()
    return true
end

function M.shutdown()
    catalog={}; catalogMeta={}; zipIndex=nil; aliases=nil; iconCache={}; iconCacheOrder={}
end

return M
