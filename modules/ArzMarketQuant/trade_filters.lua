local M = { api_version = 1, module_version = 1 }

function M.init(ctx)
local context = type(ctx) == "table" and ctx or {}
local u8 = context.u8
local storageFinder = context.storageFinder
local configFileNames = context.configFileNames

-- Trade list filters and priority sorting.
TRADE_FILTER_FILE = "moonloader/ArzMarket/trade_filters.json"
TRADE_FILTER_VERSION = 1
TRADE_FILTER_PANEL_WIDTH = 340
TRADE_FILTER_STATE_VERSION = 0
tradeFilterState = nil
tradeFilterCache = {
	sell = { signature = nil, query = nil, version = -1, rows = {} },
	buy = { signature = nil, query = nil, version = -1, rows = {} }
}

TRADE_FILTER_CATEGORY_ORDER_DEFAULT = {
	"cases",
	"accessories",
	"skins",
	"weapons",
	"certificates",
	"tuning",
	"upgrades",
	"resources",
	"objects",
	"shards",
	"other"
}

TRADE_FILTER_CATEGORY_LABELS = {
	cases = u8:decode("Ларцы"),
	accessories = u8:decode("Аксессуары"),
	skins = u8:decode("Скины"),
	weapons = u8:decode("Оружие"),
	certificates = u8:decode("Сертификаты"),
	tuning = u8:decode("Тюнинг"),
	upgrades = u8:decode("Улучшения"),
	resources = u8:decode("Ресурсы/крафт"),
	objects = u8:decode("Объекты"),
	shards = u8:decode("Осколки"),
	other = u8:decode("Прочее")
}

TRADE_FILTER_SORT_LABELS = {
	enabled = u8:decode("Включенные выше"),
	inventory = u8:decode("Есть в инвентаре выше"),
	category = u8:decode("По типу предмета"),
	price_asc = u8:decode("Цена: сначала дешевые"),
	price_desc = u8:decode("Цена: сначала дорогие")
}

function tradeFilterDefaultSide(side)
	return {
		filters = {
			only_enabled = false,
			only_inventory = false,
			hide_unavailable = false,
			hide_untransferable = false
		},
		sorts = {
			{ id = "enabled", enabled = false },
			{ id = "inventory", enabled = false },
			{ id = "category", enabled = false },
			{ id = "price_asc", enabled = false },
			{ id = "price_desc", enabled = false }
		},
		-- Item types are always enabled. Their order is used only as priority.
		categories = {
			cases = true,
			accessories = true,
			skins = true,
			weapons = true,
			certificates = true,
			tuning = true,
			upgrades = true,
			resources = true,
			objects = true,
			shards = true,
			other = true
		},
		category_order = {
			"cases", "accessories", "skins", "weapons", "certificates",
			"tuning", "upgrades", "resources", "objects", "shards", "other"
		}
	}
end

function tradeFilterMergeSide(value, side)
	local result = tradeFilterDefaultSide(side)
	if type(value) ~= "table" then
		return result
	end

	if type(value.filters) == "table" then
		for key, defaultValue in pairs(result.filters) do
			if type(value.filters[key]) == "boolean" then
				result.filters[key] = value.filters[key]
			else
				result.filters[key] = defaultValue
			end
		end
	end

	-- Category visibility is no longer configurable.
	-- Every type is permanently enabled; only category_order is persisted.
	for _, key in ipairs(TRADE_FILTER_CATEGORY_ORDER_DEFAULT) do
		result.categories[key] = true
	end

	if type(value.sorts) == "table" then
		local known = {}
		local normalized = {}
		for _, row in ipairs(value.sorts) do
			if type(row) == "table" and TRADE_FILTER_SORT_LABELS[row.id] and not known[row.id] then
				normalized[#normalized + 1] = { id = row.id, enabled = row.enabled == true }
				known[row.id] = true
			end
		end
		for _, row in ipairs(result.sorts) do
			if not known[row.id] then
				normalized[#normalized + 1] = row
			end
		end
		result.sorts = normalized
	end

	if type(value.category_order) == "table" then
		local known = {}
		local normalized = {}
		for _, id in ipairs(value.category_order) do
			if TRADE_FILTER_CATEGORY_LABELS[id] and not known[id] then
				normalized[#normalized + 1] = id
				known[id] = true
			end
		end
		for _, id in ipairs(TRADE_FILTER_CATEGORY_ORDER_DEFAULT) do
			if not known[id] then
				normalized[#normalized + 1] = id
			end
		end
		result.category_order = normalized
	end

	return result
end

function tradeFilterEnsureLoaded()
	if type(tradeFilterState) == "table" then
		return
	end

	local loaded = {}
	local ok, value = pcall(readJsonFile, TRADE_FILTER_FILE, {})
	if ok and type(value) == "table" then
		loaded = value
	end

	tradeFilterState = {
		version = TRADE_FILTER_VERSION,
		sell = tradeFilterMergeSide(loaded.sell, "sell"),
		buy = tradeFilterMergeSide(loaded.buy, "buy")
	}

	-- The simplified panel is identical for BUY and SELL.
	-- Legacy hidden filters must never affect the list, all item types are
	-- permanently enabled, and only the two price sorts may be enabled.
	for _, side in ipairs({ "sell", "buy" }) do
		local sideState = tradeFilterState[side]
		if type(sideState) == "table" then
			if type(sideState.filters) == "table" then
				sideState.filters.only_enabled = false
				sideState.filters.only_inventory = false
				sideState.filters.hide_unavailable = false
				sideState.filters.hide_untransferable = false
			end

			if type(sideState.sorts) == "table" then
				for _, row in ipairs(sideState.sorts) do
					if row.id ~= "price_asc" and row.id ~= "price_desc" then
						row.enabled = false
					end
				end
			end

			sideState.categories = sideState.categories or {}
			for _, category in ipairs(TRADE_FILTER_CATEGORY_ORDER_DEFAULT) do
				sideState.categories[category] = true
			end
		end
	end
end

function tradeFilterSave()
	tradeFilterEnsureLoaded()
	tradeFilterState.version = TRADE_FILTER_VERSION
	local ok = writeJsonFile(tradeFilterState, TRADE_FILTER_FILE)
	if not ok then
		print("[ArzMarket][TradeFilter] failed to save " .. TRADE_FILTER_FILE)
	end
	TRADE_FILTER_STATE_VERSION = TRADE_FILTER_STATE_VERSION + 1
end

function tradeFilterInvalidate(side)
	if side and tradeFilterCache[side] then
		tradeFilterCache[side].signature = nil
	else
		tradeFilterCache.sell.signature = nil
		tradeFilterCache.buy.signature = nil
	end
	TRADE_FILTER_STATE_VERSION = TRADE_FILTER_STATE_VERSION + 1
end

function tradeFilterNormalizeName(name)
	local value = tostring(name or ""):gsub("{......}", ""):gsub("^%s+", ""):gsub("%s+$", "")
	if type(string.nlower) == "function" then
		local ok, lowered = pcall(string.nlower, value)
		if ok and type(lowered) == "string" then
			return lowered
		end
	end
	return string.lower(value)
end


-- Learned exact item categories from manual BUY filter assignments.
-- Manual dropdown assignment still has higher priority, so future corrections remain possible.
TRADE_FILTER_LEARNED_NAME_CATEGORY = {
	[u8:decode("doggo")] = "accessories",
	[u8:decode("бензопила на спину")] = "accessories",
	[u8:decode("запечатанный: бронежилет devil company")] = "accessories",
	[u8:decode("запечатанный: кошелек devil company")] = "accessories",
	[u8:decode("запечатанный: наплечник devil company")] = "accessories",
	[u8:decode("золотая гангстерская цепь")] = "accessories",
	[u8:decode("лавка чубрика")] = "accessories",
	[u8:decode("мешок с мясом")] = "accessories",
	[u8:decode("переносной ларек (1)")] = "accessories",
	[u8:decode("секретный аксессуар")] = "accessories",
	[u8:decode("складная магическая лавка")] = "accessories",
	[u8:decode("современная карта кладов (уровень: 0)")] = "accessories",
	[u8:decode("цепь swag")] = "accessories",
	[u8:decode("цепь свага")] = "accessories",
	[u8:decode("case capture")] = "cases",
	[u8:decode("concept car luxury")] = "cases",
	[u8:decode("rare box blue")] = "cases",
	[u8:decode("rare box red")] = "cases",
	[u8:decode("rare box yellow")] = "cases",
	[u8:decode("super car box")] = "cases",
	[u8:decode("одежда из секонд-хенда")] = "cases",
	[u8:decode("грядка всякой всячины")] = "objects",
	[u8:decode("грядка льна")] = "objects",
	[u8:decode("грядка с укропом")] = "objects",
	[u8:decode("грядка хлопка")] = "objects",
	[u8:decode("алюминий")] = "resources",
	[u8:decode("древесина высшего качества")] = "resources",
	[u8:decode("жареное мясо оленины")] = "resources",
	[u8:decode("зловещая монета")] = "resources",
	[u8:decode("металл")] = "resources",
	[u8:decode("монета миража")] = "resources",
	[u8:decode("опыт депозита")] = "resources",
	[u8:decode("охлаждающая жидкость для видеокарты")] = "resources",
	[u8:decode("печать нефтяника")] = "resources",
	[u8:decode("подарок")] = "resources",
	[u8:decode("редкие материалы")] = "resources",
	[u8:decode("рыбная монета")] = "resources",
	[u8:decode("сироп майнера")] = "resources",
	[u8:decode("сироп фермера")] = "resources",
	[u8:decode("сироп характеристик актера")] = "resources",
	[u8:decode("смазка для разгона видеокарты")] = "resources",
	[u8:decode("сырое мясо оленины")] = "resources",
	[u8:decode("талон на смену никнейма")] = "resources",
	[u8:decode("точильный амулет")] = "resources",
	[u8:decode("тушка оленя")] = "resources",
	[u8:decode("уголь")] = "resources",
	[u8:decode("черная жемчужина")] = "resources",
	[u8:decode("[pubg] мужчина 1")] = "skins",
	[u8:decode("the notorious b.i.g")] = "skins",
	[u8:decode("асап роки")] = "skins",
	[u8:decode("бамблби")] = "skins",
	[u8:decode("думгай")] = "skins",
	[u8:decode("мидас")] = "skins",
	[u8:decode("оптимус прайм")] = "skins",
	[u8:decode("фрирен")] = "skins",
	[u8:decode("фродо")] = "skins",
	[u8:decode("gg регистратор")] = "tuning",
	[u8:decode("twin turbo")] = "tuning",
	[u8:decode("twin turbo (2 уровня)")] = "tuning",
	[u8:decode("багажник")] = "tuning",
	[u8:decode("багажник double-gang")] = "tuning",
	[u8:decode("багажник таноса")] = "tuning",
	[u8:decode("дифференциал (sport+)")] = "tuning",
	[u8:decode("золотой vin номер")] = "tuning",
	[u8:decode("коленвал (sport+)")] = "tuning",
	[u8:decode("кпп (sport)")] = "tuning",
	[u8:decode("кпп (sport+)")] = "tuning",
	[u8:decode("нагнетатель (sport)")] = "tuning",
	[u8:decode("нагнетатель (sport+)")] = "tuning",
	[u8:decode("новый vin номер")] = "tuning",
	[u8:decode("подвеска (sport)")] = "tuning",
	[u8:decode("подвеска (sport+)")] = "tuning",
	[u8:decode("полицейская мигалка (активная)")] = "tuning",
	[u8:decode("протокол взвешивания")] = "tuning",
	[u8:decode("разрешение на получение номера")] = "tuning",
	[u8:decode("распредвал (sport)")] = "tuning",
	[u8:decode("распредвал (sport+)")] = "tuning",
	[u8:decode("сцепление (sport+)")] = "tuning",
	[u8:decode("тормоза (sport+)")] = "tuning",
	[u8:decode("турбокомпрессор (sport)")] = "tuning",
	[u8:decode("турбокомпрессор (sport+)")] = "tuning",
	[u8:decode("увеличенный бак (160 литров)")] = "tuning",
	[u8:decode("+1 уровень premium vip")] = "upgrades",
	[u8:decode("бонус тракториста +300 процентов")] = "upgrades",
	[u8:decode("вечная рабочая виза")] = "upgrades",
	[u8:decode("обнуление глобальных достижений")] = "upgrades",
	[u8:decode("премиум vip (30 дней)")] = "upgrades",
	[u8:decode("продажа фишек без комиссии")] = "upgrades",
	[u8:decode("талон на 12 x4 payday (передаваемый)")] = "upgrades",
	[u8:decode("талон снятия предупреждений")] = "upgrades",
}

function tradeFilterItemCategory(item)
	if type(item) ~= "table" then
		return "other"
	end

	-- Manual assignment from the buy-list dropdown has highest priority.
	local manualCategory = item.trade_filter_category
	if type(manualCategory) == "string" and TRADE_FILTER_CATEGORY_LABELS[manualCategory] then
		return manualCategory
	end

	-- Exact learned mapping is checked before broad keyword rules.
	-- This prevents known items such as boxes, tuning parts and special resources
	-- from falling into "Прочее" or a wrong broad category.
	local learnedName = tradeFilterNormalizeName(item.name)
	local learnedCategory = TRADE_FILTER_LEARNED_NAME_CATEGORY
		and TRADE_FILTER_LEARNED_NAME_CATEGORY[learnedName]
	if type(learnedCategory) == "string" and TRADE_FILTER_CATEGORY_LABELS[learnedCategory] then
		return learnedCategory
	end

	local explicit = item.category or item.server_category or item.item_category
	if type(explicit) == "string" and TRADE_FILTER_CATEGORY_LABELS[explicit] and explicit ~= "other" then
		return explicit
	end

	local itemId = item.item_id or item.foreign_item_id or item.itemId or item.id
	local modelId = item.model_id or item.foreign_model_id or item.modelId or item.model
	local serverType = item.server_type or item.serverType or item.item_type or item.itemType
	if type(storageFinder) == "table" and type(storageFinder.classifyItem) == "function"
		and (itemId ~= nil or modelId ~= nil or serverType ~= nil) then
		local ok, category = pcall(storageFinder.classifyItem, {
			item_id = itemId,
			model_id = modelId,
			server_type = serverType,
			name = ""
		})
		if ok and category and category ~= "other" and TRADE_FILTER_CATEGORY_LABELS[category] then
			return category
		end
	end

	local name = tradeFilterNormalizeName(item.name)
	if name == "virgin moon" or name == "shadow moon" then
		return "skins"
	end

	if name:find(u8:decode("осколок"), 1, true) == 1 or name:find(u8:decode("осколки"), 1, true) == 1 then
		return "shards"
	end

	if name:find(u8:decode("набор реставрации"), 1, true)
		or name:find(u8:decode("инструкция для разбора"), 1, true) then
		return "upgrades"
	end

	if name:find(u8:decode("скин:"), 1, true)
		or name:find(u8:decode("легендарная одежда:"), 1, true) == 1
		or name:find(u8:decode("одежда:"), 1, true) == 1 then
		return "skins"
	end

	if name:find(u8:decode("объект:"), 1, true) == 1 then
		return "objects"
	end

	if name:find(u8:decode("аксессуар:"), 1, true) == 1
		or name:find(u8:decode("легендарный аксессуар:"), 1, true) == 1
		or name:find(u8:decode("коллекционный аксессуар:"), 1, true) == 1 then
		return "accessories"
	end

	if name:find(u8:decode("сертификат"), 1, true) then
		return "certificates"
	end

	if name:find(u8:decode("ларец"), 1, true) or name:find(u8:decode("сундук"), 1, true) or name:find(u8:decode("кейс"), 1, true)
		or name:find(u8:decode("тайник"), 1, true) or name:find(u8:decode("рулетка"), 1, true) or name:find(u8:decode("ящик"), 1, true) then
		return "cases"
	end

	if name:find(u8:decode("крылья"), 1, true) or name:find(u8:decode("нимб"), 1, true)
		or name:find(u8:decode("рюкзак"), 1, true) or name:find(u8:decode("маска"), 1, true)
		or name:find(u8:decode("шляпа"), 1, true) or name:find(u8:decode("чемодан"), 1, true)
		or name:find(u8:decode("моноколесо"), 1, true) or name:find(u8:decode("воздушный шар"), 1, true)
		or name:find(u8:decode("энергетические часы"), 1, true) or name:find(u8:decode("энергетический щит"), 1, true)
		or name:find(u8:decode("пятизубец"), 1, true) or name:find(u8:decode("посох"), 1, true)
		or name:find(u8:decode("молот тора"), 1, true) or name:find(u8:decode("рука бесконечности"), 1, true)
		or name:find(u8:decode("голова робокоп"), 1, true) or name:find(u8:decode("голова фредди"), 1, true)
		or name:find(u8:decode("кукла вуду"), 1, true) or name:find(u8:decode("дрон-защитник"), 1, true)
		or name:find(u8:decode("сумка с деньгами"), 1, true) then
		return "accessories"
	end

	if name:find(u8:decode("тюнинг"), 1, true) or name:find(u8:decode("винил"), 1, true) or name:find(u8:decode("спойлер"), 1, true)
		or name:find(u8:decode("бампер"), 1, true) or name:find(u8:decode("капот"), 1, true) or name:find(u8:decode("выхлоп"), 1, true) then
		return "tuning"
	end
	if name:find(u8:decode("улучшен"), 1, true) or name:find(u8:decode("заточка"), 1, true) then
		return "upgrades"
	end
	if name:find(u8:decode("оруж"), 1, true) or name:find(u8:decode("пистолет"), 1, true) or name:find(u8:decode("винтов"), 1, true)
		or name:find(u8:decode("автомат"), 1, true) then
		return "weapons"
	end
	if name:find(u8:decode("компонент"), 1, true) or name:find(u8:decode("ресурс"), 1, true) or name:find(u8:decode("крафт"), 1, true)
		or name:find(u8:decode("материя"), 1, true) or name:find(u8:decode("сплав"), 1, true) or name:find(u8:decode("ткань"), 1, true)
		or name:find(u8:decode("камень"), 1, true) or name:find(u8:decode("руда"), 1, true) then
		return "resources"
	end

	return "other"
end

function tradeFilterIsTransferable(item, side)
	if type(item) ~= "table" then
		return nil
	end

	for _, key in ipairs({ "transferable", "can_trade", "canTrade", "can_transfer", "canTransfer" }) do
		if type(item[key]) == "boolean" then
			return item[key]
		end
	end

	if side == "sell" and type(json_vlad) == "table" and next(json_vlad) ~= nil and type(containsItem) == "function" then
		local cleanName = tostring(item.name or ""):gsub("%(%+%d+%)", "")
		local ok, found = pcall(containsItem, json_vlad, cleanName, 1)
		if ok then
			return found and true or false
		end
	end

	local name = tradeFilterNormalizeName(item.name)
	if name:find(u8:decode("непередаваем"), 1, true) or name:find(u8:decode("не передаваем"), 1, true) then
		return false
	end

	return nil
end

function tradeFilterHasInventory(item)
	if type(item) ~= "table" then
		return nil
	end
	local value = tonumber(item.all_count)
	if value ~= nil then
		return value > 0
	end
	if type(item.in_inventory) == "boolean" then
		return item.in_inventory
	end
	return nil
end

function tradeFilterIsUnavailable(item, side)
	if type(item) ~= "table" then
		return false
	end
	if type(item.available) == "boolean" then
		return not item.available
	end
	if side == "sell" then
		local inInventory = tradeFilterHasInventory(item)
		if inInventory ~= nil then
			return not inInventory
		end
	end
	return false
end

function tradeFilterGetPrice(item)
	if type(item) ~= "table" then
		return 0
	end
	return tonumber(context.getViceCityMode() and item.price or item.price_vc) or 0
end

function tradeFilterCategoryRank(sideState, category)
	for index, value in ipairs(sideState.category_order or {}) do
		if value == category then
			return index
		end
	end
	return 999
end

function tradeFilterListSignature(list)
	if type(list) ~= "table" then
		return "nil"
	end
	local acc1 = #list * 131
	local acc2 = 17
	for index, item in ipairs(list) do
		if type(item) == "table" then
			local name = tostring(item.name or "")
			local manualCategory = tostring(item.trade_filter_category or "")
			local price = tonumber(context.getViceCityMode() and item.price or item.price_vc) or 0
			local count = tonumber(item.count) or 0
			local allCount = tonumber(item.all_count) or -1
			acc1 = (acc1 + #name * 31 + #manualCategory * 53 + index * 17 + math.floor(price % 1000003)) % 2147483000
			acc2 = (acc2 + math.floor(count * 13 + allCount * 7) + (item.enabled == false and 97 or 19)) % 2147483000
		else
			acc1 = (acc1 + index * 43) % 2147483000
		end
	end
	return tostring(#list) .. ":" .. tostring(acc1) .. ":" .. tostring(acc2)
end

function tradeFilterHasSelectedCategory(sideState)
	for category, enabled in pairs(sideState.categories or {}) do
		if enabled == true and TRADE_FILTER_CATEGORY_LABELS[category] then
			return true
		end
	end
	return false
end

function tradeFilterMatches(item, side, sideState, query)
	if type(item) ~= "table" then
		return false
	end

	local filters = sideState.filters or {}
	if filters.only_enabled and item.enabled == false then
		return false
	end

	if filters.only_inventory then
		local hasInventory = tradeFilterHasInventory(item)
		if hasInventory == false then
			return false
		end
	end

	if filters.hide_unavailable and tradeFilterIsUnavailable(item, side) then
		return false
	end

	if filters.hide_untransferable and tradeFilterIsTransferable(item, side) == false then
		return false
	end

	local category = tradeFilterItemCategory(item)
	if tradeFilterHasSelectedCategory(sideState) and sideState.categories[category] ~= true then
		return false
	end

	if query and query ~= "" then
		local name = tradeFilterNormalizeName(item.name)
		local wanted = tradeFilterNormalizeName(query)
		if not name:find(wanted, 1, true) then
			return false
		end
	end

	return true
end

function tradeFilterCaseSubtypeRank(item)
	local name = tradeFilterNormalizeName(type(item) == "table" and item.name or "")
	-- Inside the "cases" category keep actual Larcy together first,
	-- then boxes, then every other case-like item.
	if name:find(u8:decode("ларец"), 1, true) then
		return 1
	end
	if name:find(u8:decode("ящик"), 1, true) then
		return 2
	end
	return 3
end

function tradeFilterCompare(a, b, side, sideState)
	-- Selected item-type priorities are absolute groups.
	-- Example: Accessories = 1, Skins = 2 means every accessory is shown before every skin.
	local categoryA = tradeFilterItemCategory(a)
	local categoryB = tradeFilterItemCategory(b)
	local hasCategoryPriority = tradeFilterHasSelectedCategory(sideState)
	if hasCategoryPriority and categoryA ~= categoryB then
		local rankA = tradeFilterCategoryRank(sideState, categoryA)
		local rankB = tradeFilterCategoryRank(sideState, categoryB)
		if rankA ~= rankB then
			return rankA < rankB
		end
	end

	-- The Cases category has its own fixed suborder:
	-- Larcy first, boxes second, then roulette/stash/case/chest/etc.
	-- This is intentionally checked before enabled/inventory/price sorts,
	-- so case-like items never split actual Larcy into several blocks.
	if categoryA == "cases" and categoryB == "cases" then
		local subtypeA = tradeFilterCaseSubtypeRank(a)
		local subtypeB = tradeFilterCaseSubtypeRank(b)
		if subtypeA ~= subtypeB then
			return subtypeA < subtypeB
		end
	end

	-- General sorting rules work only inside the same selected category group.
	for _, criterion in ipairs(sideState.sorts or {}) do
		if criterion.enabled then
			if criterion.id == "enabled" then
				local av = a.enabled ~= false and 1 or 0
				local bv = b.enabled ~= false and 1 or 0
				if av ~= bv then return av > bv end
			elseif criterion.id == "inventory" then
				local av = tradeFilterHasInventory(a)
				local bv = tradeFilterHasInventory(b)
				av = av == true and 1 or (av == false and 0 or -1)
				bv = bv == true and 1 or (bv == false and 0 or -1)
				if av ~= bv then return av > bv end
			elseif criterion.id == "category" and not hasCategoryPriority then
				local av = tradeFilterCategoryRank(sideState, tradeFilterItemCategory(a))
				local bv = tradeFilterCategoryRank(sideState, tradeFilterItemCategory(b))
				if av ~= bv then return av < bv end
			elseif criterion.id == "price_asc" then
				local av = tradeFilterGetPrice(a)
				local bv = tradeFilterGetPrice(b)
				if av ~= bv then return av < bv end
			elseif criterion.id == "price_desc" then
				local av = tradeFilterGetPrice(a)
				local bv = tradeFilterGetPrice(b)
				if av ~= bv then return av > bv end
			end
		end
	end

	return (tonumber(a.position_tab) or 0) < (tonumber(b.position_tab) or 0)
end

function tradeFilterBuildView(list, side, query)
	tradeFilterEnsureLoaded()
	if type(list) ~= "table" then
		return {}
	end

	local sideState = tradeFilterState[side] or tradeFilterDefaultSide(side)
	local cache = tradeFilterCache[side]
	local newOnly = tradeFilterIsNewOnly(side)
	local normalizedQuery = newOnly and "" or tradeFilterNormalizeName(query or "")
	local cacheQuery = newOnly and "__new_items_only__" or normalizedQuery

	if marketSidePriceEditorActive(side) and cache.query == cacheQuery and cache.version == TRADE_FILTER_STATE_VERSION and type(cache.rows) == "table" and #cache.rows > 0 then
		return cache.rows
	end

	local signature = tradeFilterListSignature(list)
	if cache.signature == signature and cache.query == cacheQuery and cache.version == TRADE_FILTER_STATE_VERSION then
		return cache.rows
	end

	local rows = {}
	for index, item in ipairs(list) do
		if type(item) == "table" then
			item.position_tab = index
			if newOnly then
				if tradeFilterIsNewItem(side, item) then
					rows[#rows + 1] = item
				end
			elseif tradeFilterMatches(item, side, sideState, normalizedQuery) then
				rows[#rows + 1] = item
			end
		end
	end

	if not newOnly then
		local hasSort = tradeFilterHasSelectedCategory(sideState)
		for _, criterion in ipairs(sideState.sorts or {}) do
			if criterion.enabled then
				hasSort = true
				break
			end
		end
		if hasSort and #rows > 1 then
			table.sort(rows, function(a, b)
				return tradeFilterCompare(a, b, side, sideState)
			end)
		end
	end

	cache.signature = signature
	cache.query = cacheQuery
	cache.version = TRADE_FILTER_STATE_VERSION
	cache.rows = rows
	return rows
end

function tradeFilterApplyExecutionOrder(list, side)
	tradeFilterEnsureLoaded()
	if type(list) ~= "table" or #list <= 1 then
		return false
	end

	local sideState = tradeFilterState[side] or tradeFilterDefaultSide(side)
	for index, item in ipairs(list) do
		if type(item) == "table" then
			item.position_tab = index
		end
	end

	local hasSort = tradeFilterHasSelectedCategory(sideState)
	for _, criterion in ipairs(sideState.sorts or {}) do
		if criterion.enabled then
			hasSort = true
			break
		end
	end
	if not hasSort then
		return false
	end

	table.sort(list, function(a, b)
		if type(a) ~= "table" then
			return false
		end
		if type(b) ~= "table" then
			return true
		end
		return tradeFilterCompare(a, b, side, sideState)
	end)

	for index, item in ipairs(list) do
		if type(item) == "table" then
			item.position_tab = index
		end
	end

	tradeFilterInvalidate(side)
	return true
end

function tradeFilterToggleValue(side, section, key, value)
	tradeFilterEnsureLoaded()
	local sideState = tradeFilterState[side]
	if section == "filters" then
		-- Legacy boolean filters are intentionally disabled for both panels.
		sideState.filters[key] = false
	elseif section == "categories" then
		-- All item types are permanently enabled.
		sideState.categories[key] = true
	end
	tradeFilterSave()
	tradeFilterInvalidate(side)
end

function tradeFilterSetSortEnabled(side, index, enabled)
	tradeFilterEnsureLoaded()
	local sideState = tradeFilterState[side]
	local row = sideState.sorts[index]
	if not row then return end
	row.enabled = enabled == true
	if row.enabled and (row.id == "price_asc" or row.id == "price_desc") then
		local opposite = row.id == "price_asc" and "price_desc" or "price_asc"
		for _, other in ipairs(sideState.sorts) do
			if other.id == opposite then
				other.enabled = false
			end
		end
	end
	tradeFilterSave()
	tradeFilterInvalidate(side)
end

function tradeFilterMoveSort(side, index, delta)
	tradeFilterEnsureLoaded()
	local list = tradeFilterState[side].sorts
	local target = index + delta
	if target < 1 or target > #list then return end
	list[index], list[target] = list[target], list[index]
	tradeFilterSave()
	tradeFilterInvalidate(side)
end

function tradeFilterMoveCategory(side, index, delta)
	tradeFilterEnsureLoaded()
	local list = tradeFilterState[side].category_order
	local target = index + delta
	if target < 1 or target > #list then return end
	list[index], list[target] = list[target], list[index]
	tradeFilterSave()
	tradeFilterInvalidate(side)
end


TRADE_FILTER_CATEGORY_DRAG_STATE = TRADE_FILTER_CATEGORY_DRAG_STATE or {
	sell = { active = false, category = nil, moved = false },
	buy = { active = false, category = nil, moved = false }
}

TRADE_FILTER_CATEGORY_JUMP_REQUEST = TRADE_FILTER_CATEGORY_JUMP_REQUEST or {
	sell = nil,
	buy = nil
}

TRADE_FILTER_NEW_ONLY = TRADE_FILTER_NEW_ONLY or {
	sell = false,
	buy = false
}

TRADE_FILTER_NEW_ITEMS = TRADE_FILTER_NEW_ITEMS or {
	sell = setmetatable({}, { __mode = "k" }),
	buy = setmetatable({}, { __mode = "k" })
}

TRADE_FILTER_NEW_ITEM_SERIAL = tonumber(TRADE_FILTER_NEW_ITEM_SERIAL) or 0

function tradeFilterGetNewItemSet(side)
	if side ~= "sell" and side ~= "buy" then
		return nil
	end
	if type(TRADE_FILTER_NEW_ITEMS[side]) ~= "table" then
		TRADE_FILTER_NEW_ITEMS[side] = setmetatable({}, { __mode = "k" })
	end
	return TRADE_FILTER_NEW_ITEMS[side]
end

function tradeFilterMarkNewItem(side, item)
	if type(item) ~= "table" then
		return false
	end
	local newItems = tradeFilterGetNewItemSet(side)
	if not newItems then
		return false
	end
	TRADE_FILTER_NEW_ITEM_SERIAL = TRADE_FILTER_NEW_ITEM_SERIAL + 1
	newItems[item] = TRADE_FILTER_NEW_ITEM_SERIAL
	tradeFilterInvalidate(side)
	return true
end

function tradeFilterIsNewItem(side, item)
	local newItems = tradeFilterGetNewItemSet(side)
	return type(item) == "table" and newItems ~= nil and newItems[item] ~= nil
end

function tradeFilterCountNewItems(side, list)
	if type(list) ~= "table" then
		return 0
	end
	local count = 0
	for _, item in ipairs(list) do
		if tradeFilterIsNewItem(side, item) then
			count = count + 1
		end
	end
	return count
end

function tradeFilterIsNewOnly(side)
	return (side == "sell" or side == "buy") and TRADE_FILTER_NEW_ONLY[side] == true
end

function tradeFilterSetNewOnly(side, enabled)
	if side ~= "sell" and side ~= "buy" then
		return false
	end
	local newState = enabled == true
	if TRADE_FILTER_NEW_ONLY[side] == newState then
		return false
	end
	TRADE_FILTER_NEW_ONLY[side] = newState
	if newState then
		tradeFilterClearCategoryJump(side)
	end
	tradeFilterInvalidate(side)
	return true
end

function tradeFilterGetCategoryDragState(side)
	if type(TRADE_FILTER_CATEGORY_DRAG_STATE[side]) ~= "table" then
		TRADE_FILTER_CATEGORY_DRAG_STATE[side] = { active = false, category = nil, moved = false }
	end
	return TRADE_FILTER_CATEGORY_DRAG_STATE[side]
end

function tradeFilterRequestCategoryJump(side, category)
	if side ~= "sell" and side ~= "buy" then
		return false
	end
	if type(category) ~= "string" or not TRADE_FILTER_CATEGORY_LABELS[category] then
		return false
	end
	TRADE_FILTER_CATEGORY_JUMP_REQUEST[side] = category
	return true
end

function tradeFilterConsumeCategoryJump(side, category)
	if TRADE_FILTER_CATEGORY_JUMP_REQUEST[side] ~= category then
		return false
	end
	TRADE_FILTER_CATEGORY_JUMP_REQUEST[side] = nil
	return true
end

function tradeFilterClearCategoryJump(side)
	if side == "sell" or side == "buy" then
		TRADE_FILTER_CATEGORY_JUMP_REQUEST[side] = nil
	end
end

function tradeFilterFindCategoryIndex(side, category)
	tradeFilterEnsureLoaded()
	local list = tradeFilterState[side] and tradeFilterState[side].category_order or nil
	if type(list) ~= "table" then return nil end
	for i, value in ipairs(list) do
		if value == category then return i end
	end
	return nil
end

function tradeFilterMoveCategoryTo(side, fromIndex, toIndex)
	tradeFilterEnsureLoaded()
	local list = tradeFilterState[side] and tradeFilterState[side].category_order or nil
	if type(list) ~= "table" then return false end
	fromIndex = tonumber(fromIndex)
	toIndex = tonumber(toIndex)
	if not fromIndex or not toIndex then return false end
	fromIndex = math.floor(fromIndex)
	toIndex = math.floor(toIndex)
	if fromIndex < 1 or fromIndex > #list or toIndex < 1 or toIndex > #list or fromIndex == toIndex then
		return false
	end
	local value = table.remove(list, fromIndex)
	if not value then return false end
	table.insert(list, toIndex, value)
	tradeFilterSave()
	tradeFilterInvalidate(side)
	return true
end

TRADE_FILTER_TRAINING_JSON_PATHS = {
	buy = "moonloader/ArzMarket/buy_filter_training.json",
	sell = "moonloader/ArzMarket/sell_filter_training.json"
}
TRADE_FILTER_TRAINING_LOG_PATHS = {
	buy = getWorkingDirectory() .. "/ArzMarket/buy_filter_training.log",
	sell = getWorkingDirectory() .. "/ArzMarket/sell_filter_training.log"
}
TRADE_FILTER_TRAINING_MAX_CHANGES = 2000

function tradeFilterTrainingUtf8(value)
	local text = tostring(value or "")
	local ok, converted = pcall(function()
		return u8(text)
	end)
	if ok and converted ~= nil then
		return tostring(converted)
	end
	return text
end

function tradeFilterTrainingCleanText(value)
	return tradeFilterTrainingUtf8(value):gsub("[\r\n\t]", " ")
end

function tradeFilterGetAutomaticItemCategory(item)
	if type(item) ~= "table" then
		return "other"
	end

	local previousManual = item.trade_filter_category
	item.trade_filter_category = nil
	local ok, automaticCategory = pcall(tradeFilterItemCategory, item)
	item.trade_filter_category = previousManual

	if ok and type(automaticCategory) == "string" and TRADE_FILTER_CATEGORY_LABELS[automaticCategory] then
		return automaticCategory
	end
	return "other"
end

function tradeFilterTrainingLoad(side)
	side = side == "sell" and "sell" or "buy"
	local data = nil
	local trainingPath = TRADE_FILTER_TRAINING_JSON_PATHS[side]
	local ok, loaded = pcall(readJsonFile, trainingPath)
	if ok and type(loaded) == "table" then
		data = loaded
	end
	if type(data) ~= "table" then
		data = {}
	end
	if type(data.items) ~= "table" then
		data.items = {}
	end
	if type(data.changes) ~= "table" then
		data.changes = {}
	end
	data.version = 1
	return data
end

function tradeFilterTrainingItemKey(item)
	local itemId = item and (item.item_id or item.foreign_item_id or item.itemId) or nil
	if itemId ~= nil and tostring(itemId) ~= "" then
		return "id:" .. tostring(itemId)
	end

	local normalizedName = tradeFilterNormalizeName(item and item.name or "")
	return "name:" .. tradeFilterTrainingUtf8(normalizedName)
end

function tradeFilterTrainingRecord(side, item, oldManualCategory, newManualCategory, automaticCategory, configSaveAttempted, configSaved)
	if type(item) ~= "table" then
		return false
	end

	side = side == "sell" and "sell" or "buy"
	local data = tradeFilterTrainingLoad(side)
	local timestamp = os.time()
	local itemName = tradeFilterTrainingCleanText(item.name)
	local key = tradeFilterTrainingItemKey(item)
	local finalCategory = newManualCategory or automaticCategory or "other"
	local activeConfigName = side == "sell" and context.getLoadedSellConfig() or context.getLoadedBuyConfig()
	local configName = tradeFilterTrainingCleanText(activeConfigName or "")

	local record = {
		time = timestamp,
		time_text = os.date("%Y-%m-%d %H:%M:%S", timestamp),
		source = side .. "_dropdown",
		config = configName,
		item_name = itemName,
		item_id = item.item_id or item.foreign_item_id or item.itemId,
		model_id = item.model_id or item.foreign_model_id or item.modelId or item.model,
		server_type = item.server_type or item.serverType or item.item_type or item.itemType,
		explicit_category = item.category or item.server_category or item.item_category,
		auto_category = automaticCategory or "other",
		auto_category_label = tradeFilterTrainingUtf8(TRADE_FILTER_CATEGORY_LABELS[automaticCategory or "other"] or automaticCategory or "other"),
		old_manual_category = oldManualCategory or "auto",
		new_manual_category = newManualCategory or "auto",
		final_category = finalCategory,
		final_category_label = tradeFilterTrainingUtf8(TRADE_FILTER_CATEGORY_LABELS[finalCategory] or finalCategory),
		config_save_attempted = configSaveAttempted == true,
		config_saved = configSaveAttempted ~= true or configSaved == true
	}

	data.updated_at = timestamp
	data.updated_at_text = record.time_text
	data.items[key] = record
	data.changes[#data.changes + 1] = record
	while #data.changes > TRADE_FILTER_TRAINING_MAX_CHANGES do
		table.remove(data.changes, 1)
	end

	local jsonSaved = false
	local trainingJsonPath = TRADE_FILTER_TRAINING_JSON_PATHS[side]
	local trainingLogPath = TRADE_FILTER_TRAINING_LOG_PATHS[side]
	local okJson, jsonResult = pcall(writeJsonFile, data, trainingJsonPath)
	if okJson and jsonResult == true then
		jsonSaved = true
	end

	local logLine = string.format(
		"[%s] item=\"%s\" id=%s model=%s server_type=%s config=\"%s\" auto=%s old_manual=%s new_manual=%s final=%s config_saved=%s",
		record.time_text,
		itemName:gsub('"', "'"),
		tostring(record.item_id or ""),
		tostring(record.model_id or ""),
		tostring(record.server_type or ""),
		configName:gsub('"', "'"),
		tostring(record.auto_category),
		tostring(record.old_manual_category),
		tostring(record.new_manual_category),
		tostring(record.final_category),
		tostring(record.config_saved)
	)

	local logOk = false
	local file = io.open(trainingLogPath, "ab")
	if file then
		file:write(logLine .. "\r\n")
		file:flush()
		file:close()
		logOk = true
	end

	local trainingTag = side == "sell" and "SellFilterTraining" or "BuyFilterTraining"
	pcall(saveLog, "[ArzMarket][" .. trainingTag .. "] " .. tostring(item.name or "")
		.. " | auto=" .. tostring(record.auto_category)
		.. " | manual=" .. tostring(record.new_manual_category)
		.. " | final=" .. tostring(record.final_category))

	return jsonSaved or logOk
end

function tradeFilterSetItemCategory(side, item, category)
	if type(item) ~= "table" then
		return false
	end

	local oldManualCategory = nil
	if type(item.trade_filter_category) == "string" and TRADE_FILTER_CATEGORY_LABELS[item.trade_filter_category] then
		oldManualCategory = item.trade_filter_category
	end
	local automaticCategory = tradeFilterGetAutomaticItemCategory(item)
	local newManualCategory = nil

	if category == nil or category == "" or category == "auto" then
		newManualCategory = nil
	elseif TRADE_FILTER_CATEGORY_LABELS[category] then
		newManualCategory = category
	else
		return false
	end

	if oldManualCategory == newManualCategory then
		return true
	end

	item.trade_filter_category = newManualCategory
	tradeFilterInvalidate(side)

	local configSaveAttempted = false
	local configSaved = true

	-- Save the active config immediately so the assignment survives restart.
	if side == "buy" and type(context.getBuyList()) == "table" and context.getLoadedBuyConfig() and context.getLoadedBuyConfig() ~= "" then
		configSaveAttempted = true
		configFileNames.buy = context.getLoadedBuyConfig():match("(.+)%.json") and context.getLoadedBuyConfig() or context.getLoadedBuyConfig() .. ".json"
		configSaved = createConfig("buy-cfg/" .. configFileNames.buy, context.getBuyList(), "buy-cfg", configFileNames.buy) == true
	elseif side == "sell" and type(context.getSellList()) == "table" and context.getLoadedSellConfig() and context.getLoadedSellConfig() ~= "" then
		configSaveAttempted = true
		configFileNames.sell = context.getLoadedSellConfig():match("(.+)%.json") and context.getLoadedSellConfig() or context.getLoadedSellConfig() .. ".json"
		configSaved = createConfig("sell-cfg/" .. configFileNames.sell, context.getSellList(), "sell-cfg", configFileNames.sell) == true
	end

	if side == "buy" or side == "sell" then
		pcall(tradeFilterTrainingRecord, side, item, oldManualCategory, newManualCategory, automaticCategory, configSaveAttempted, configSaved)
	end

	return true
end

function tradeFilterCancelCategoryDrag(side)
	local state = tradeFilterGetCategoryDragState(side)
	state.active = false
	state.category = nil
	state.moved = false
end

function tradeFilterResetSide(side)
	tradeFilterEnsureLoaded()
	tradeFilterState[side] = tradeFilterDefaultSide(side)
	tradeFilterSave()
	tradeFilterInvalidate(side)
end

return true
end

return M
