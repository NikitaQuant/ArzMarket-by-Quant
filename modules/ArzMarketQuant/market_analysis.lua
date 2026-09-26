local M = { api_version = 1, module_version = 1 }

function M.init(ctx)
local context = type(ctx) == "table" and ctx or {}
local u8 = context.u8
local serverSlugById, priceData = context.serverSlugById, context.priceData
local decodeJsonSafe, encodeJsonSafe = context.decodeJsonSafe, context.encodeJsonSafe
local writeEncodedFile, lfs = context.writeEncodedFile, context.lfs
local storageFinder, marketState = context.storageFinder, context.marketState

-- Low price guard. Uses the same priceData history as the built-in average-price window.
LOW_PRICE_GUARD_RATIO = 0.50
HIGH_PRICE_GUARD_RATIO = 2.00
LOW_PRICE_GUARD_DIALOG_ID = 31984
LOW_PRICE_GUARD_HISTORY_DAYS = 200
lowPriceGuardLastRefreshAt = 0
LOW_PRICE_GUARD_FORCE_ONCE_SIDE = nil
LOW_PRICE_GUARD_FORCE_ONCE_EXPIRES = 0
LOW_PRICE_GUARD_PENDING_FORCE = { side = nil, command = nil }

function lowPriceGuardNormalizeName(name)
	return tostring(name or ""):gsub("{......}", ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function lowPriceGuardRefreshPriceData()
	local serverName = sampGetCurrentServerName()
	if type(serverName) ~= "string" or not serverName:find("Arizona") then
		return false
	end

	local nickname = ""
	local playerIdOk, playerId = sampGetPlayerIdByCharHandle(PLAYER_PED)
	if playerIdOk then
		local okNick, value = pcall(sampGetPlayerNickname, playerId)
		if okNick and value then
			nickname = tostring(value)
		end
	end

	local viceCityServerId = nickname:match("%[(%-?%d+)%]")
	local detectedServerSlug = viceCityServerId ~= nil and serverSlugById[viceCityServerId]
		or (serverName:match("|%s*(.+)% |"))
		or serverName:match("|%s*(.+)")

	if detectedServerSlug == nil or detectedServerSlug == "" then
		return false
	end

	local lowercaseServerSlug = string.lower(detectedServerSlug):gsub(" ", "-")

	-- Server-specific SA$ tables are invalid only when the player changes server.
	if lowPriceGuardLoadedServerSlug ~= lowercaseServerSlug then
		priceData.sell_ = {}
		priceData.buy_ = {}
		lowPriceGuardLoadedServerSlug = lowercaseServerSlug
	end

	local filesByType = {
		sell_ = "moonloader/ArzMarket/UsersInfo/info_users_sell_" .. lowercaseServerSlug .. ".json",
		buy_ = "moonloader/ArzMarket/UsersInfo/info_users_buy_" .. lowercaseServerSlug .. ".json",
		sell_vc = "moonloader/ArzMarket/UsersInfo/info_users_sell_vc.json",
		buy_vc = "moonloader/ArzMarket/UsersInfo/info_users_buy_vc.json"
	}

	-- Keep already decoded data in memory only for explicitly enabled sources.
	-- Disabled tables remain nil and therefore do not occupy the LuaJIT heap.
	for priceType, path in pairs(filesByType) do
		if avgPriceSourceIsEnabled(priceType) then
			local current = priceData[priceType]
			if type(current) ~= "table" or next(current) == nil then
				local okLoad, loaded = pcall(readJsonFile, path, {})
				if okLoad and type(loaded) == "table" and next(loaded) ~= nil then
					priceData[priceType] = loaded
				else
					priceData[priceType] = nil
				end
			end
		else
			priceData[priceType] = nil
		end
	end

	lowPriceGuardLastRefreshAt = os.clock()
	return true
end

function lowPriceGuardFindPriceEntry(source, itemName)
	if type(source) ~= "table" then
		return nil
	end

	local exactName = lowPriceGuardNormalizeName(itemName)
	local baseName = lowPriceGuardNormalizeName(exactName:gsub("%(%+%d+%)", ""))
	if source[exactName] ~= nil then
		return source[exactName], exactName
	end
	if baseName ~= exactName and source[baseName] ~= nil then
		return source[baseName], baseName
	end

	local wanted = baseName:gsub("%s+", "")
	for key, value in pairs(source) do
		local normalizedKey = lowPriceGuardNormalizeName(key):gsub("%(%+%d+%)", ""):gsub("%s+", "")
		if normalizedKey == wanted then
			return value, key
		end
	end

	return nil
end

function lowPriceGuardGetLatestAverage(itemName, side)
	if not lowPriceGuardRefreshPriceData() then
		return nil
	end

	local sourceKey
	-- context.getViceCityMode() == true means the active editor/runtime currency is SA$.
	-- Keep the guard source in the same currency as lowPriceGuardGetConfiguredPrice().
	if side == "buy" then
		sourceKey = context.getViceCityMode() and "buy_" or "buy_vc"
	else
		sourceKey = context.getViceCityMode() and "sell_" or "sell_vc"
	end

	local itemHistory = lowPriceGuardFindPriceEntry(priceData[sourceKey], itemName)
	if type(itemHistory) ~= "table" or type(itemHistory.list) ~= "table" then
		return nil
	end

	-- Same order as the built-in window: newest date first.
	for dayOffset = 0, LOW_PRICE_GUARD_HISTORY_DAYS - 1 do
		local date = os.date("%Y-%m-%d", os.time() - 86400 * dayOffset)
		for _, row in pairs(itemHistory.list) do
			if type(row) == "table" and row[1] == date then
				local count = tonumber(row[2])
				local total = tonumber(row[3])
				if count and count > 0 and total and total > 0 then
					return math.floor(total / count), date, count
				end
			end
		end
	end

	return nil
end

function lowPriceGuardGetConfiguredPrice(itemData)
	if type(itemData) ~= "table" then
		return 0
	end
	return tonumber(context.getViceCityMode() and itemData.price or itemData.price_vc) or 0
end

-- Storage total value. The storage module owns inventory aggregation; this adapter
-- only resolves trade prices from the active sell config and the script's sell averages.
STORAGE_VALUE_CACHE = STORAGE_VALUE_CACHE or {
	total = 0,
	config_items = 0,
	average_items = 0,
	missing_items = 0,
	currency = "$",
	next_refresh = 0
}
STORAGE_VALUE_AVERAGE_CACHE = STORAGE_VALUE_AVERAGE_CACHE or {
	source_key = nil,
	path = nil,
	modified = nil,
	data = nil
}
STORAGE_VALUE_CONFIG_CACHE = STORAGE_VALUE_CONFIG_CACHE or {
	name = nil,
	path = nil,
	modified = nil,
	data = nil
}

function storageValueNormalizeName(name)
	if type(lowPriceGuardNormalizeName) == "function" then
		return lowPriceGuardNormalizeName(name)
	end
	return tostring(name or ""):gsub("{......}", ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function storageValueGetSellListSnapshot()
	-- Storage valuation must use only the sell config that is actually applied.
	-- Do not trust context.getSellList() here because trade flows may temporarily replace or
	-- mutate that in-memory table. context.getLoadedSellConfig() is the authoritative active config.
	local configName = tostring(context.getLoadedSellConfig() or "")
	if configName == "" then
		STORAGE_VALUE_CONFIG_CACHE.name = nil
		STORAGE_VALUE_CONFIG_CACHE.path = nil
		STORAGE_VALUE_CONFIG_CACHE.modified = nil
		STORAGE_VALUE_CONFIG_CACHE.data = nil
		return {}
	end

	local fileName = configName:match("%.json$") and configName or (configName .. ".json")
	local path = "moonloader/ArzMarket/sell-cfg/" .. fileName
	if not doesFileExist(path) then
		STORAGE_VALUE_CONFIG_CACHE.name = configName
		STORAGE_VALUE_CONFIG_CACHE.path = path
		STORAGE_VALUE_CONFIG_CACHE.modified = nil
		STORAGE_VALUE_CONFIG_CACHE.data = nil
		return {}
	end

	local modified = nil
	if lfs and type(lfs.attributes) == "function" then
		local okModified, value = pcall(lfs.attributes, path, "modification")
		if okModified then
			modified = tonumber(value)
		end
	end

	local cache = STORAGE_VALUE_CONFIG_CACHE
	if cache.name == configName
		and cache.path == path
		and cache.modified == modified
		and type(cache.data) == "table"
	then
		return cache.data
	end

	local okLoad, loaded = pcall(readJsonFile, path, {})
	if not okLoad or type(loaded) ~= "table" then
		loaded = {}
	end

	cache.name = configName
	cache.path = path
	cache.modified = modified
	cache.data = loaded
	return loaded
end

function storageValueBuildConfiguredPrices()
	local exact = {}
	local plainBase = {}
	local list = storageValueGetSellListSnapshot()

	for _, item in ipairs(list) do
		if type(item) == "table" then
			local normalizedName = storageValueNormalizeName(item.name)
			local configuredPrice = type(lowPriceGuardGetConfiguredPrice) == "function"
				and lowPriceGuardGetConfiguredPrice(item)
				or tonumber(context.getViceCityMode() and item.price or item.price_vc)

			configuredPrice = tonumber(configuredPrice)
			if normalizedName ~= "" and configuredPrice and configuredPrice > 0 then
				exact[normalizedName] = configuredPrice
				if not normalizedName:find("%(%+%d+%)") then
					plainBase[normalizedName] = configuredPrice
				end
			end
		end
	end

	return exact, plainBase
end

function storageValueResolveConfiguredPrice(itemName, exact, plainBase)
	local normalizedName = storageValueNormalizeName(itemName)
	if normalizedName == "" then return nil end

	local price = exact[normalizedName]
	if price then return price end

	-- An enchanted storage item may use the price of an explicitly configured
	-- plain base item. Do not do the reverse for a plain item.
	if normalizedName:find("%(%+%d+%)") then
		local baseName = storageValueNormalizeName(normalizedName:gsub("%(%+%d+%)", ""))
		return plainBase[baseName]
	end

	return nil
end

function storageValueGetAverageSource(sourceKey)
	local active = priceData and priceData[sourceKey] or nil
	if type(active) == "table" and next(active) ~= nil then
		STORAGE_VALUE_AVERAGE_CACHE.source_key = sourceKey
		STORAGE_VALUE_AVERAGE_CACHE.path = nil
		STORAGE_VALUE_AVERAGE_CACHE.modified = nil
		STORAGE_VALUE_AVERAGE_CACHE.data = nil
		return active
	end

	if type(avgPriceGetSourcePath) ~= "function" then return nil end
	local path = avgPriceGetSourcePath(sourceKey)
	if type(path) ~= "string" or path == "" or not doesFileExist(path) then return nil end

	local modified = nil
	if lfs and type(lfs.attributes) == "function" then
		local okModified, value = pcall(lfs.attributes, path, "modification")
		if okModified then modified = tonumber(value) end
	end

	local cache = STORAGE_VALUE_AVERAGE_CACHE
	if cache.source_key == sourceKey
		and cache.path == path
		and cache.modified == modified
		and type(cache.data) == "table"
	then
		return cache.data
	end

	local okLoad, loaded = pcall(readJsonFile, path, {})
	if not okLoad or type(loaded) ~= "table" or next(loaded) == nil then
		return nil
	end

	cache.source_key = sourceKey
	cache.path = path
	cache.modified = modified
	cache.data = loaded
	return loaded
end

function storageValueGetLatestAverage(itemName, source)
	if type(source) ~= "table" then return nil end

	local itemHistory = nil
	if type(lowPriceGuardFindPriceEntry) == "function" then
		itemHistory = lowPriceGuardFindPriceEntry(source, itemName)
	else
		itemHistory = source[storageValueNormalizeName(itemName)]
	end

	if type(itemHistory) ~= "table" or type(itemHistory.list) ~= "table" then
		return nil
	end

	local latestDate = nil
	local latestPrice = nil
	for _, row in pairs(itemHistory.list) do
		if type(row) == "table" then
			local date = tostring(row[1] or "")
			local count = tonumber(row[2])
			local total = tonumber(row[3])
			if count and count > 0 and total and total > 0 then
				local unitPrice = math.floor(total / count)
				if unitPrice > 0 and (latestDate == nil or date > latestDate) then
					latestDate = date
					latestPrice = unitPrice
				end
			end
		end
	end

	return latestPrice
end

function storageValueRecalculate()
	local cache = STORAGE_VALUE_CACHE
	local now = os.clock()
	if now < (tonumber(cache.next_refresh) or 0) then
		return cache
	end
	cache.next_refresh = now + 1.0

	local catalog = {}
	if storageFinder and type(storageFinder.getCatalog) == "function" then
		local okCatalog, result = pcall(storageFinder.getCatalog, "")
		if okCatalog and type(result) == "table" then catalog = result end
	end

	local exactPrices, plainBasePrices = storageValueBuildConfiguredPrices()
	local sourceKey = context.getViceCityMode() and "sell_" or "sell_vc"

	if type(lowPriceGuardRefreshPriceData) == "function" then
		pcall(lowPriceGuardRefreshPriceData)
	end
	local averageSource = storageValueGetAverageSource(sourceKey)

	local total = 0
	local configItems = 0
	local averageItems = 0
	local missingItems = 0

	for _, item in ipairs(catalog) do
		if type(item) == "table" then
			local count = math.max(0, math.floor(tonumber(item.count) or 0))
			if count > 0 then
				local price = storageValueResolveConfiguredPrice(item.name, exactPrices, plainBasePrices)
				if price then
					configItems = configItems + 1
				else
					price = storageValueGetLatestAverage(item.name, averageSource)
					if price then averageItems = averageItems + 1 end
				end

				if price and tonumber(price) and tonumber(price) > 0 then
					total = total + count * tonumber(price)
				else
					missingItems = missingItems + 1
				end
			end
		end
	end

	cache.total = math.max(0, math.floor(total))
	cache.config_items = configItems
	cache.average_items = averageItems
	cache.missing_items = missingItems
	cache.currency = context.getViceCityMode() and "$" or "VC$ "
	return cache
end

function storageValueGetSummary()
	return storageValueRecalculate()
end

function lowPriceGuardShowDialog(warnings, side, forceCommand)
	if type(warnings) ~= "table" or #warnings == 0 then
		return
	end

	local canForce = type(forceCommand) == "string" and forceCommand ~= ""
	LOW_PRICE_GUARD_PENDING_FORCE.side = canForce and side or nil
	LOW_PRICE_GUARD_PENDING_FORCE.command = canForce and forceCommand or nil

	local actionName = side == "buy" and u8:decode("скупки") or u8:decode("продажи")
	local lines = {
		u8:decode("Обнаружена подозрительная цена перед запуском ") .. actionName .. ".",
		canForce and u8:decode("Исправьте цену или нажмите принудительный запуск.") or u8:decode("Выставление остановлено. Исправьте цену и запустите снова."),
		"",
	}

	local maxRows = math.min(#warnings, 10)
	for i = 1, maxRows do
		local warning = warnings[i]
		local kindLabel = warning.kind == "too_high" and u8:decode("Слишком высокая") or u8:decode("Слишком низкая")
		lines[#lines + 1] = tostring(i) .. ". " .. tostring(warning.name)
		lines[#lines + 1] = kindLabel .. ": " .. moneySeparator(warning.price)
		lines[#lines + 1] = u8:decode("Средняя: ") .. moneySeparator(warning.average) .. " | " .. tostring(warning.percent) .. "% | " .. tostring(warning.date)
		lines[#lines + 1] = ""
	end

	if #warnings > maxRows then
		lines[#lines + 1] = u8:decode("Ещё проблемных позиций: ") .. tostring(#warnings - maxRows)
	end

	local ok, err = pcall(
		sampShowDialog,
		LOW_PRICE_GUARD_DIALOG_ID,
		u8:decode("Предупреждение о цене"),
		table.concat(lines, "\n"),
		canForce and u8:decode("Запустить принудительно") or u8:decode("Закрыть"),
		canForce and u8:decode("Закрыть") or "",
		0
	)
	if not ok then
		print("[ArzMarket][PriceGuard] sampShowDialog failed: " .. tostring(err))
		AFKMessage(u8:decode("ВНИМАНИЕ! Найдена цена, сильно отличающаяся от средней. Выставление остановлено."))
	end
end

function lowPriceGuardPreflight(list, side, forceCommand)
	if LOW_PRICE_GUARD_FORCE_ONCE_SIDE == side and getGameTimer() <= (tonumber(LOW_PRICE_GUARD_FORCE_ONCE_EXPIRES) or 0) then
		LOW_PRICE_GUARD_FORCE_ONCE_SIDE = nil
		LOW_PRICE_GUARD_FORCE_ONCE_EXPIRES = 0
		return true
	elseif LOW_PRICE_GUARD_FORCE_ONCE_SIDE ~= nil then
		LOW_PRICE_GUARD_FORCE_ONCE_SIDE = nil
		LOW_PRICE_GUARD_FORCE_ONCE_EXPIRES = 0
	end

	if type(list) ~= "table" or #list == 0 then
		return true
	end

	local warnings = {}
	local lowRatio = tonumber(LOW_PRICE_GUARD_RATIO) or 0.50
	local highRatio = tonumber(HIGH_PRICE_GUARD_RATIO) or 2.00

	for _, itemData in ipairs(list) do
		if type(itemData) == "table" and itemData.enabled ~= false then
			local configuredPrice = lowPriceGuardGetConfiguredPrice(itemData)
			if configuredPrice > 0 then
				local averagePrice, averageDate = lowPriceGuardGetLatestAverage(itemData.name, side)
				if averagePrice and averagePrice > 0 then
					local kind = nil
					-- On buy orders a low price is intentional and must never block placement.
					-- Keep the low-price guard only for sell orders, where it protects against accidental cheap sales.
					if side ~= "buy" and configuredPrice < averagePrice * lowRatio then
						kind = "too_low"
					elseif configuredPrice > averagePrice * highRatio then
						kind = "too_high"
					end

					if kind then
						warnings[#warnings + 1] = {
							kind = kind,
							name = tostring(itemData.name or "?"),
							price = configuredPrice,
							average = averagePrice,
							date = averageDate or "?",
							percent = math.floor(configuredPrice * 100 / averagePrice + 0.5)
						}
					end
				end
			end
		end
	end

	if #warnings > 0 then
		lowPriceGuardShowDialog(warnings, side, forceCommand)
		return false, warnings
	end

	return true
end


-- Block 3: foreign shop copy, quantity preservation and average-price tools.
function resetForeignShopRuntime(reason)
	local state = marketState and marketState.copyLavkaFunc
	if type(state) == "table" then
		state.slotId = 0
		state.activeSlot = -1
		state.status = false
		state.finishing = false
		state.finishAt = 0
		state.maxSlotId = -1
		state.askServer = true
		state.sell_buy = -1
		state.mode = "copy"
		state.timer = os.clock()
		state.rawBySide = { sell = {}, buy = {} }
		state.summary = { added = 0, updated = 0, existed = 0, skipped = 0 }
	end
	marketState.available_items_customCopyConfig_sell = {}
	marketState.available_items_customCopyConfig_buy = {}
	saveLog("[ArzMarket][ForeignShop] runtime reset: " .. tostring(reason or "unknown"))
end

function foreignShopNormalizeName(name)
	return tostring(name or ""):gsub("{......}", ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
end

function foreignShopPickField(raw, keys, depth)
	if type(raw) ~= "table" then
		return nil
	end
	depth = tonumber(depth) or 0
	for _, key in ipairs(keys) do
		if raw[key] ~= nil and type(raw[key]) ~= "table" then
			return raw[key]
		end
	end
	if depth >= 2 then
		return nil
	end
	for _, containerKey in ipairs({ "data", "item", "info", "details", "meta", "metadata" }) do
		local child = raw[containerKey]
		if type(child) == "table" then
			local value = foreignShopPickField(child, keys, depth + 1)
			if value ~= nil then
				return value
			end
		end
	end
	return nil
end

function foreignShopExtractCount(raw)
	local value = foreignShopPickField(raw, {
		"count", "quantity", "amount", "number", "stackCount", "stack_count",
		"itemCount", "item_count", "availableCount", "available_count", "maxCount", "max_count"
	})
	local count = tonumber(value)
	if count and count == count and count > 0 and count < math.huge then
		return math.floor(count)
	end
	return nil
end

function foreignShopExtractPrice(raw)
	local value = foreignShopPickField(raw, {
		"price", "cost", "itemPrice", "item_price", "buyPrice", "buy_price", "sellPrice", "sell_price"
	})
	local price = tonumber(value)
	if price and price == price and price > 0 and price < math.huge then
		return math.floor(price)
	end
	return nil
end

function foreignShopNormalizeRawItem(raw, fallbackSlot)
	if type(raw) ~= "table" then
		return nil
	end
	local name = foreignShopPickField(raw, { "name", "itemName", "item_name", "title" })
	if name == nil and type(raw.item) == "string" then
		name = raw.item
	end
	name = foreignShopNormalizeName(name)
	local slot = tonumber(foreignShopPickField(raw, { "slot", "slotId", "slot_id", "index" }))
	if slot == nil then
		slot = tonumber(fallbackSlot)
		if slot and slot >= 1 then
			slot = slot - 1
		end
	end
	return {
		name = name,
		slot = slot and math.floor(slot) or nil,
		count = foreignShopExtractCount(raw),
		price = foreignShopExtractPrice(raw),
		item_id = foreignShopPickField(raw, { "item_id", "itemId", "id", "uid" }),
		model_id = foreignShopPickField(raw, { "model_id", "modelId", "model" }),
		available = tonumber(foreignShopPickField(raw, { "available", "enabled", "active" }))
	}
end

function foreignShopCaptureRawGroup(side, items)
	if side ~= "sell" and side ~= "buy" then
		return
	end
	if getTradeContextState then
		local context = getTradeContextState()
		if context.owner == "other" and markForeignShopContext then
			markForeignShopContext(side, context.shopIdentity, "cef_items")
		end
	end
	if type(items) ~= "table" then
		return
	end
	marketState.copyLavkaFunc.rawBySide = marketState.copyLavkaFunc.rawBySide or { sell = {}, buy = {} }
	marketState.copyLavkaFunc.rawBySide[side] = marketState.copyLavkaFunc.rawBySide[side] or {}
	for key, raw in pairs(items) do
		if type(raw) == "table" then
			local item = foreignShopNormalizeRawItem(raw, key)
			if item and item.slot ~= nil then
				marketState.copyLavkaFunc.rawBySide[side][item.slot] = item
			end
		end
	end
end

function foreignShopRebuildRawCache(side)
	marketState.copyLavkaFunc.rawBySide = marketState.copyLavkaFunc.rawBySide or { sell = {}, buy = {} }
	marketState.copyLavkaFunc.rawBySide[side] = {}
	local source = side == "sell" and marketState.available_items_customCopyConfig_sell or marketState.available_items_customCopyConfig_buy
	if type(source) == "table" then
		for _, group in pairs(source) do
			foreignShopCaptureRawGroup(side, group)
		end
	end
	return marketState.copyLavkaFunc.rawBySide[side]
end

function foreignShopGetRawItem(side, slot)
	local cache = marketState.copyLavkaFunc.rawBySide and marketState.copyLavkaFunc.rawBySide[side]
	if type(cache) ~= "table" or next(cache) == nil then
		cache = foreignShopRebuildRawCache(side)
	end
	return type(cache) == "table" and cache[tonumber(slot)] or nil
end

function foreignShopExtractDialogCount(text)
	if type(text) ~= "string" or text == "" then
		return nil
	end
	local clean = text:gsub("{......}", ""):gsub("%.", "")
	local labels = {
		u8:decode("Количество"),
		u8:decode("Кол%-во"),
		u8:decode("Доступно"),
		u8:decode("В наличии"),
		u8:decode("Осталось"),
		u8:decode("На скупке"),
		u8:decode("Скупается"),
		u8:decode("Максимум")
	}
	for _, label in ipairs(labels) do
		local value = clean:match(label .. "%s*:?%s*(%d+)")
		local count = tonumber(value)
		if count and count > 0 then
			return math.floor(count)
		end
	end
	local byUnits = clean:match(u8:decode("(%d+)%s*шт%.?")) or clean:match(u8:decode("(%d+)%s*штук"))
	local count = tonumber(byUnits)
	if count and count > 0 then
		return math.floor(count)
	end
	return nil
end

function foreignShopFindBuyConfigItem(name, itemId, modelId)
	local normalized = foreignShopNormalizeName(name)
	for index, item in ipairs(context.getBuyList()) do
		if type(item) == "table" then
			if itemId ~= nil and item.foreign_item_id ~= nil and tostring(item.foreign_item_id) == tostring(itemId) then
				return item, index
			end
			if modelId ~= nil and item.foreign_model_id ~= nil and tostring(item.foreign_model_id) == tostring(modelId)
				and foreignShopNormalizeName(item.name) == normalized then
				return item, index
			end
			if foreignShopNormalizeName(item.name) == normalized then
				return item, index
			end
		end
	end
	return nil
end

function foreignShopSetBuyPrice(item, price)
	price = tonumber(price)
	if type(item) ~= "table" or not price or price <= 0 then
		return false
	end
	if context.getViceCityMode() then
		item.price = math.floor(price)
	else
		item.price_vc = math.floor(price)
	end
	return true
end

function foreignShopApplyBuyItem(sourceItem, mode)
	if type(sourceItem) ~= "table" then
		return false, "invalid"
	end
	local name = foreignShopNormalizeName(sourceItem.name)
	local price = tonumber(sourceItem.price)
	local count = tonumber(sourceItem.count)
	if name == "" or not price or price <= 0 then
		return false, "invalid"
	end
	if count and count > 0 then
		count = math.floor(count)
	else
		count = nil
	end

	local existing = foreignShopFindBuyConfigItem(name, sourceItem.item_id, sourceItem.model_id)
	if existing then
		if mode == "add_missing" then
			return true, "existed"
		end
		foreignShopSetBuyPrice(existing, price)
		if count then
			existing.count = count
			existing.continue = count
			existing.maximum = false
			existing.count_maximum = 0
		end
		if sourceItem.item_id ~= nil then existing.foreign_item_id = sourceItem.item_id end
		if sourceItem.model_id ~= nil then existing.foreign_model_id = sourceItem.model_id end
		return true, "updated"
	end

	if not count then
		return false, "count_unknown"
	end

	local item = {
		continue = count,
		enabled = true,
		maximum = false,
		count_maximum = 0,
		name = name,
		count = count,
		price = ini.cfg.myServerId == "201" and 9 or price,
		price_vc = ini.cfg.myServerId ~= "201" and 9 or price,
		foreign_item_id = sourceItem.item_id,
		foreign_model_id = sourceItem.model_id
	}
	addToData(item, context.getBuyList(), context.getSortMode() and 1 or nil)
	tradeFilterMarkNewItem("buy", item)
	return true, "added"
end

function foreignShopResetSummary()
	marketState.copyLavkaFunc.summary = { added = 0, updated = 0, existed = 0, skipped = 0 }
end

function foreignShopRegisterSummary(result)
	local summary = marketState.copyLavkaFunc.summary or {}
	if result == "added" then
		summary.added = (summary.added or 0) + 1
	elseif result == "updated" then
		summary.updated = (summary.updated or 0) + 1
	elseif result == "existed" then
		summary.existed = (summary.existed or 0) + 1
	else
		summary.skipped = (summary.skipped or 0) + 1
	end
	marketState.copyLavkaFunc.summary = summary
end

function foreignShopCreatePreChangeBackup(side)
	local list, loaded, configType
	if side == "buy" then
		list, loaded, configType = context.getBuyList(), context.getLoadedBuyConfig(), "buy-cfg"
	elseif side == "sell" then
		list, loaded, configType = context.getSellList(), context.getLoadedSellConfig(), "sell-cfg"
	else
		return false
	end
	if loaded == "" or type(list) ~= "table" then
		return false
	end
	local fileName = loaded:match("(.+)%.json") and loaded or loaded .. ".json"
	local backupDir = getWorkingDirectory() .. "\\ArzMarket\\" .. configType .. "\\backups\\" .. os.date("%d.%m.%Y")
	if not doesDirectoryExist(backupDir) then
		createDirectory(backupDir)
	end
	local encoded = encodeJsonSafe(list, encodeJson)
	if type(encoded) ~= "string" then
		return false
	end
	local safeName = fileName:gsub('[\\/:*?"<>|]', "_")
	local millis = math.floor((os.clock() % 1) * 1000)
	local backupPath = backupDir .. "\\pre_change_" .. os.date("%H%M%S") .. "_" .. string.format("%03d", millis) .. "_" .. safeName
	return writeEncodedFile(backupPath, encoded) == true
end

function foreignShopPersistActiveConfig(side)
	if side == "buy" then
		if context.getLoadedBuyConfig() == "" then
			return false
		end
		local fileName = context.getLoadedBuyConfig():match("(.+)%.json") and context.getLoadedBuyConfig() or context.getLoadedBuyConfig() .. ".json"
		return createConfig("buy-cfg/" .. fileName, context.getBuyList(), "buy-cfg", fileName) ~= false
	elseif side == "sell" then
		if context.getLoadedSellConfig() == "" then
			return false
		end
		local fileName = context.getLoadedSellConfig():match("(.+)%.json") and context.getLoadedSellConfig() or context.getLoadedSellConfig() .. ".json"
		return createConfig("sell-cfg/" .. fileName, context.getSellList(), "sell-cfg", fileName) ~= false
	end
	return false
end

function foreignShopFinishScan()
	local state = marketState.copyLavkaFunc
	local side = state.sell_buy == "1" and "buy" or "sell"
	state.status = false
	state.finishing = false
	state.activeSlot = -1
	foreignShopPersistActiveConfig(side)
	if type(tradeFilterInvalidate) == "function" then
		pcall(tradeFilterInvalidate, side)
	end
	local summary = state.summary or {}
	if side == "buy" then
		local text = u8:decode("Копирование завершено. ")
			.. u8:decode("Добавлено: ") .. tostring(summary.added or 0)
			.. u8:decode(", обновлено: ") .. tostring(summary.updated or 0)
			.. u8:decode(", уже было: ") .. tostring(summary.existed or 0)
			.. u8:decode(", пропущено: ") .. tostring(summary.skipped or 0)
		AFKMessage(text)
		sendNotify(text)
	else
		AFKMessage(u8:decode("Копирование конфига завершено."))
		sendNotify(u8:decode("Копирование конфига завершено."))
	end
end

function foreignShopStartScan(mode, skipServerQuestion)
	local state = marketState.copyLavkaFunc
	mode = mode == "add_missing" and "add_missing" or "copy"
	if state.sell_buy == -1 then
		AFKMessage(u8:decode("Нужно переоткрыть меню лавки, чтобы сканировать."))
		return false
	end
	if mode == "add_missing" and state.sell_buy ~= "1" then
		sendNotify(u8:decode("Кнопка добавления товаров работает для чужой скупки."))
		return false
	end
	if mode == "add_missing" and context.getLoadedBuyConfig() == "" then
		sendNotify(u8:decode("Сначала загрузите конфиг скупки."))
		return false
	end
	state.mode = mode
	if state.askServer and not skipServerQuestion then
		marketState.askServer = true
		return true
	end

	state.maxSlotId = -1
	local maxSlot = -1
	local groups = marketState[state.sell_buy == "0" and "available_items_customCopyConfig_sell" or "available_items_customCopyConfig_buy"]
	for _, group in pairs(type(groups) == "table" and groups or {}) do
		for _, inventoryItem in pairs(type(group) == "table" and group or {}) do
			local slot = tonumber(inventoryItem.slot)
			if slot and slot > maxSlot and (inventoryItem.available == 1 or inventoryItem.available == true or tostring(inventoryItem.available) == "1") then
				maxSlot = slot
			end
		end
	end
	if maxSlot < 0 then
		sendNotify(u8:decode("Товары в чужой лавке не найдены."))
		return false
	end
	state.maxSlotId = maxSlot
	foreignShopCreatePreChangeBackup(state.sell_buy == "1" and "buy" or "sell")
	state.slotId = 0
	state.activeSlot = -1
	state.finishing = false
	state.finishAt = 0
	state.timer = os.clock() - 1
	state.status = true
	foreignShopResetSummary()
	foreignShopRebuildRawCache(state.sell_buy == "1" and "buy" or "sell")
	return true
end

function foreignShopCopyUpdate()
	local state = marketState.copyLavkaFunc
	if not state.status then
		return
	end
	if state.finishing then
		if os.clock() >= (tonumber(state.finishAt) or 0) then
			foreignShopFinishScan()
		end
		return
	end
	if state.timer + 0.6 >= os.clock() then
		return
	end
	state.timer = os.clock()
	if state.slotId <= state.maxSlotId + 1 then
		state.activeSlot = state.slotId
		send_cef("rightClickOnBlock|{\"slot\": " .. tostring(state.slotId) .. ", \"type\": " .. (state.sell_buy == "0" and "13" or "28") .. "}")
		state.slotId = state.slotId + 1
		sendNotify(u8:decode("Скопировано: ") .. tostring(math.min(state.slotId, state.maxSlotId + 2)) .. u8:decode(" из ") .. tostring(state.maxSlotId + 2))
	else
		state.finishing = true
		state.finishAt = os.clock() + 1.2
	end
end

function foreignShopHandleBuyDialog(name, price, enchantment, text)
	local state = marketState.copyLavkaFunc
	local enchantSuffix = (enchantment == "0" or enchantment == "" or enchantment == nil) and "" or "(+" .. tostring(enchantment) .. ")"
	local raw = foreignShopGetRawItem("buy", state.activeSlot)
	local item = {
		name = foreignShopNormalizeName(tostring(name or "") .. enchantSuffix),
		price = tonumber(price) or (raw and raw.price),
		count = foreignShopExtractDialogCount(text) or (raw and raw.count),
		item_id = raw and raw.item_id or nil,
		model_id = raw and raw.model_id or nil
	}
	if raw and raw.item_id ~= nil and storageFinder and type(storageFinder.rememberItemName) == "function" then
		pcall(storageFinder.rememberItemName, raw.item_id, u8(item.name))
	end
	local ok, result = foreignShopApplyBuyItem(item, state.mode)
	foreignShopRegisterSummary(result)
	if not ok and result == "count_unknown" then
		deAFKMessage("[ForeignShop] skip new buy item without exact count: " .. tostring(item.name))
	end
	return ok
end

function averagePriceGetLatestFromSource(source, itemName)
	local itemHistory = lowPriceGuardFindPriceEntry(source, itemName)
	if type(itemHistory) ~= "table" or type(itemHistory.list) ~= "table" then
		return nil
	end
	for dayOffset = 0, LOW_PRICE_GUARD_HISTORY_DAYS - 1 do
		local date = os.date("%Y-%m-%d", os.time() - 86400 * dayOffset)
		for _, row in pairs(itemHistory.list) do
			if type(row) == "table" and row[1] == date then
				local count = tonumber(row[2])
				local total = tonumber(row[3])
				if count and count > 0 and total and total > 0 then
					return math.floor(total / count), date
				end
			end
		end
	end
	return nil
end

function getAveragePriceForBuyItem(item, fallbackSource)
	local average, date = lowPriceGuardGetLatestAverage(item and item.name, "buy")
	if average and average > 0 then
		return average, date
	end
	if type(fallbackSource) == "table" then
		return averagePriceGetLatestFromSource(fallbackSource, item and item.name)
	end
	return nil
end

function applyAveragePricesToBuyList()
	if context.getLoadedBuyConfig() == "" then
		sendNotify(u8:decode("Сначала загрузите конфиг скупки."))
		return false
	end
	if type(context.getBuyList()) ~= "table" or #context.getBuyList() == 0 then
		sendNotify(u8:decode("Список скупки пуст."))
		return false
	end

	local beforeEncoded = encodeJsonSafe(context.getBuyList(), encodeJson)
	local beforeList = type(beforeEncoded) == "string" and decodeJsonSafe(beforeEncoded) or nil
	if type(beforeList) ~= "table" then
		sendNotify("Не удалось подготовить безопасную копию конфига перед изменением цен.")
		return false
	end
	if not foreignShopCreatePreChangeBackup("buy") then
		sendNotify("Не удалось создать резервную копию. Изменение средних цен отменено.")
		return false
	end
	local sourceKey = context.getViceCityMode() and "buy_" or "buy_vc"
	local fallbackSource = priceData[sourceKey]
	if type(fallbackSource) ~= "table" or next(fallbackSource) == nil then
		local path = type(avgPriceGetSourcePath) == "function" and avgPriceGetSourcePath(sourceKey) or nil
		if path and doesFileExist(path) then
			local okLoad, loaded = pcall(readJsonFile, path, {})
			if okLoad and type(loaded) == "table" and next(loaded) ~= nil then
				fallbackSource = loaded
			end
		end
	end

	local updated, missing, errors = 0, 0, 0
	for _, item in ipairs(context.getBuyList()) do
		if type(item) == "table" and item.enabled ~= false then
			local okCall, average = pcall(function()
				return select(1, getAveragePriceForBuyItem(item, fallbackSource))
			end)
			if not okCall then
				errors = errors + 1
			elseif average and tonumber(average) and tonumber(average) > 0 then
				foreignShopSetBuyPrice(item, tonumber(average))
				updated = updated + 1
			else
				missing = missing + 1
			end
		end
	end

	local saved = foreignShopPersistActiveConfig("buy")
	if not saved then
		context.setBuyList(beforeList)
		if type(tradeFilterInvalidate) == "function" then
			pcall(tradeFilterInvalidate, "buy")
		end
		sendNotify("Не удалось сохранить конфиг со средними ценами. Изменения отменены в памяти.")
		return false
	end
	if type(tradeFilterInvalidate) == "function" then
		pcall(tradeFilterInvalidate, "buy")
	end
	local message = u8:decode("Средние цены: обновлено ") .. tostring(updated)
		.. u8:decode(", нет цены ") .. tostring(missing)
		.. u8:decode(", ошибок ") .. tostring(errors) .. "."
	AFKMessage(message)
	sendNotify(message)
	return saved
end

return true
end

return M
