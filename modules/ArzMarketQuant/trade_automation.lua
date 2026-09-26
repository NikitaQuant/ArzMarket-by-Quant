local M = { api_version = 1, module_version = 1 }

function M.init(ctx)
local context = type(ctx) == "table" and ctx or {}
local u8 = context.u8
local serverIdByAddress = context.serverIdByAddress
local tradeAutomationVisible = context.tradeAutomationVisible
local modificationState = context.modificationState
local marketState = context.marketState
local scanWorkerState = context.scanWorkerState
local clearWorkerState = context.clearWorkerState

-- Persistent manual listing of items bought by the player's own buy booth.
-- The ledger stores only quantities that have not yet been successfully listed
-- through the manual action. Prices are always taken from the CURRENT sell config.
manualPurchasedState = {
	path = "moonloader/ArzMarket/manual_purchased.json",
	version = 1,
	items = {},
	running = false,
	sellListBackup = nil,
	attemptQueue = {},
	startedAt = 0,
	lastSavedAt = 0
}

function manualPurchasedNormalizeName(name)
	if type(cycleNormalizeName) == "function" then
		return cycleNormalizeName(name)
	end
	local value = tostring(name or ""):gsub("{......}", ""):gsub("%s+", "")
	if string.nlower then
		return string.nlower(value)
	end
	return string.lower(value)
end

function manualPurchasedLoad()
	local raw = readJsonFile(manualPurchasedState.path, { version = 1, items = {} })
	local sourceItems = type(raw) == "table" and type(raw.items) == "table" and raw.items or {}
	local normalized = {}
	for _, row in pairs(sourceItems) do
		if type(row) == "table" then
			local name = tostring(row.name or "")
			local count = math.max(0, math.floor(tonumber(row.count) or 0))
			local key = manualPurchasedNormalizeName(name)
			if key ~= "" and count > 0 then
				normalized[key] = {
					name = name,
					count = count,
					updated_at = tonumber(row.updated_at) or os.time()
				}
			end
		end
	end
	manualPurchasedState.items = normalized
	return normalized
end

function manualPurchasedSave()
	local payload = {
		version = manualPurchasedState.version,
		updated_at = os.time(),
		items = manualPurchasedState.items
	}
	local okEncode, encoded = pcall(encodeJson, payload)
	if not okEncode or type(encoded) ~= "string" or encoded == "" then
		return false
	end
	local tempPath = manualPurchasedState.path .. ".tmp"
	local file = io.open(tempPath, "wb")
	if not file then
		return false
	end
	local okWrite = pcall(function()
		file:write(encoded)
		file:flush()
	end)
	pcall(file.close, file)
	if not okWrite then
		pcall(os.remove, tempPath)
		return false
	end
	if doesFileExist(manualPurchasedState.path) then
		pcall(os.remove, manualPurchasedState.path)
	end
	local renamed = os.rename(tempPath, manualPurchasedState.path)
	if not renamed then
		pcall(os.remove, tempPath)
		return false
	end
	manualPurchasedState.lastSavedAt = os.time()
	return true
end

function manualPurchasedRemember(itemName, count)
	local key = manualPurchasedNormalizeName(itemName)
	if key == "" then
		return false
	end
	local qty = math.max(1, math.floor(tonumber(count) or 1))
	local row = manualPurchasedState.items[key]
	if type(row) ~= "table" then
		row = { name = tostring(itemName or ""), count = 0, updated_at = os.time() }
		manualPurchasedState.items[key] = row
	end
	row.name = tostring(itemName or row.name or "")
	row.count = math.max(0, math.floor(tonumber(row.count) or 0)) + qty
	row.updated_at = os.time()
	manualPurchasedSave()
	return true
end

function manualPurchasedConsume(itemName, count)
	local key = manualPurchasedNormalizeName(itemName)
	local row = manualPurchasedState.items[key]
	if type(row) ~= "table" then
		return false
	end
	local qty = math.max(1, math.floor(tonumber(count) or 1))
	row.count = math.max(0, math.floor(tonumber(row.count) or 0) - qty)
	row.updated_at = os.time()
	if row.count <= 0 then
		manualPurchasedState.items[key] = nil
	end
	manualPurchasedSave()
	return true
end

function manualPurchasedGetTotalCount()
	local total = 0
	for _, row in pairs(manualPurchasedState.items or {}) do
		if type(row) == "table" then
			total = total + math.max(0, math.floor(tonumber(row.count) or 0))
		end
	end
	return total
end

function manualPurchasedRestoreSellList()
	if manualPurchasedState.sellListBackup then
		context.setSellList(manualPurchasedState.sellListBackup)
		manualPurchasedState.sellListBackup = nil
	end
end

function manualPurchasedTrackAttempt(itemName, itemCount)
	if not manualPurchasedState.running then
		return
	end
	local key = manualPurchasedNormalizeName(itemName)
	if key == "" then
		return
	end
	manualPurchasedState.attemptQueue[#manualPurchasedState.attemptQueue + 1] = {
		key = key,
		name = tostring(itemName or ""),
		count = math.max(1, math.floor(tonumber(itemCount) or 1))
	}
end

function manualPurchasedRejectAttempt()
	if not manualPurchasedState.running then
		return
	end
	if #manualPurchasedState.attemptQueue > 0 then
		table.remove(manualPurchasedState.attemptQueue, 1)
	end
end

function manualPurchasedConfirmListed(message)
	if not manualPurchasedState.running or #manualPurchasedState.attemptQueue == 0 then
		return false
	end
	local listedName = tostring(message or ""):match(u8:decode("Товар%s+(.+)%s+успешно"))
	local wantedKey = listedName and manualPurchasedNormalizeName(listedName) or nil
	local attemptIndex = nil
	if wantedKey and wantedKey ~= "" then
		for index, attempt in ipairs(manualPurchasedState.attemptQueue) do
			if attempt.key == wantedKey then
				attemptIndex = index
				break
			end
		end
	end
	attemptIndex = attemptIndex or 1
	local attempt = table.remove(manualPurchasedState.attemptQueue, attemptIndex)
	if type(attempt) ~= "table" then
		return false
	end
	manualPurchasedConsume(attempt.name, attempt.count)
	return true
end

function manualPurchasedBuildSellList()
	local filtered = {}
	local matchedKeys = {}
	for _, item in ipairs(context.getSellList() or {}) do
		if type(item) == "table" then
			local key = manualPurchasedNormalizeName(item.name)
			local row = manualPurchasedState.items[key]
			local pendingCount = type(row) == "table" and math.max(0, math.floor(tonumber(row.count) or 0)) or 0
			if pendingCount > 0 then
				local clone = cycleClone(item)
				clone.enabled = true
				clone.maximum = false
				clone.count = pendingCount
				clone.all_count = tonumber(clone.all_count) or 0
				filtered[#filtered + 1] = clone
				matchedKeys[key] = true
			end
		end
	end
	return filtered, matchedKeys
end

function manualPurchasedStart()
	if manualPurchasedState.running then
		AFKMessage(u8:decode("Ручное выставление уже запущено."))
		return false
	end
	if cycleTradeState and cycleTradeState.active or context.getTradeAutomation().sell or context.getTradeAutomation().buy then
		AFKMessage(u8:decode("Сейчас выполняется другая торговая операция."))
		return false
	end
	if manualPurchasedGetTotalCount() <= 0 then
		AFKMessage(u8:decode("Нет скупленных товаров для выставления."))
		return false
	end
	if context.getLoadedSellConfig() == "" or type(context.getSellList()) ~= "table" or #context.getSellList() == 0 then
		AFKMessage(u8:decode("Сначала загрузите конфиг продажи."))
		return false
	end
	if is_invent_open ~= nil or marketState.custom_is_invent_open[1] ~= nil then
		if is_invent_open ~= nil then
			pcall(sampSendClickTextdraw, 65535)
		end
		AFKMessage(u8:decode("С открытым инвентарем функция не работает. Закройте инвентарь и повторите."))
		return false
	end

	local serverAddress = select(1, sampGetCurrentServerAddress())
	if serverIdByAddress[serverAddress] == 0 and context.getViceCityMode() or serverIdByAddress[serverAddress] ~= 0 and not context.getViceCityMode() then
		AFKMessage(u8:decode("ВНИМАНИЕ! У вас установлен не тот режим продажи. Проверьте валюту."))
		return false
	end

	local filtered = manualPurchasedBuildSellList()
	if type(filtered) ~= "table" or #filtered == 0 then
		AFKMessage(u8:decode("В текущем конфиге продажи нет скупленных товаров."))
		return false
	end

	if not lowPriceGuardPreflight(filtered, "sell", "/crpurchased") then
		return false
	end

	tradeFilterApplyExecutionOrder(filtered, "sell")

	manualPurchasedState.sellListBackup = context.getSellList()
	manualPurchasedState.running = true
	manualPurchasedState.attemptQueue = {}
	manualPurchasedState.startedAt = getGameTimer()
	context.setSellList(filtered)

	marketState.available_items_custom = {}
	marketState.custom_is_invent_open = {
		marketState.custom_is_invent_open[1],
		os.clock(),
		false,
		-1,
		1
	}
	context.setSellStatusMessages({})
	context.setSellScanMode(true)
	context.setSellScanResults({})
	SendToServer("/stats")
	AFKMessage(u8:decode("Подготовка к ручному выставлению скупленных товаров..."))

	sell_check = true
	tradeAutomationVisible[0] = true
	context.setTradeAutomation({
		sell = true,
		buy = false,
		score = 0,
		score_from = #filtered
	})
	AFKMessage(u8:decode("Ручное выставление запущено. Товаров: ") .. tostring(#filtered))
	return true
end

function manualPurchasedCancel()
	if not manualPurchasedState.running then
		return false
	end
	if context.getTradeAutomation().sell then
		off_sell_buy()
	end
	manualPurchasedRestoreSellList()
	manualPurchasedState.running = false
	manualPurchasedState.attemptQueue = {}
	AFKMessage(u8:decode("Ручное выставление отменено."))
	return true
end

function manualPurchasedUpdate()
	if not manualPurchasedState.running then
		return
	end
	if not context.getTradeAutomation().sell then
		manualPurchasedRestoreSellList()
		manualPurchasedState.running = false
		manualPurchasedState.attemptQueue = {}
		AFKMessage(u8:decode("Ручное выставление завершено."))
	end
end

manualPurchasedLoad()

cycleTradeState = {
	pending = {},
	listedOutstanding = {},
	active = nil,
	sellListBackup = nil,
	buyListBackup = nil,
	nextActionAt = 0,
	lastMissingNotice = {},
	operationTimeoutMs = 30000
}

function cycleClone(value, seen)
	if type(value) ~= "table" then
		return value
	end
	seen = seen or {}
	if seen[value] then
		return seen[value]
	end
	local out = {}
	seen[value] = out
	for k, v in pairs(value) do
		out[cycleClone(k, seen)] = cycleClone(v, seen)
	end
	return out
end

function cycleNormalizeName(name)
	local value = tostring(name or ""):gsub("{......}", ""):gsub("%s+", "")
	if string.nlower then
		value = string.nlower(value)
	else
		value = string.lower(value)
	end
	return value
end

function cycleFindItem(list, itemName)
	local wanted = cycleNormalizeName(itemName)
	if type(list) ~= "table" or wanted == "" then
		return nil, nil
	end
	for index, item in ipairs(list) do
		if type(item) == "table" and cycleNormalizeName(item.name) == wanted then
			return item, index
		end
	end
	return nil, nil
end

function cycleGetConfigSellList()
	return cycleTradeState.sellListBackup or context.getSellList()
end

function cycleGetConfigBuyList()
	return cycleTradeState.buyListBackup or context.getBuyList()
end

function cycleGetMarketBuyCount(itemName)
	local wanted = cycleNormalizeName(itemName)
	for index, marketName in ipairs(context.getMarketplacePayload().items_buy or {}) do
		if cycleNormalizeName(marketName) == wanted then
			return tonumber(context.getMarketplacePayload().count_buy[index]) or 0, index
		end
	end
	return nil, nil
end

function cycleEntry(itemName)
	local key = cycleNormalizeName(itemName)
	if key == "" then
		return nil, nil
	end
	local entry = cycleTradeState.pending[key]
	if not entry then
		entry = {
			key = key,
			name = tostring(itemName),
			pendingSell = 0,
			pendingRebuy = 0,
			rebuildTarget = nil
		}
		cycleTradeState.pending[key] = entry
	end
	return entry, key
end

function cycleNotifyMissing(key, textValue)
	local now = getGameTimer()
	if not cycleTradeState.lastMissingNotice[key] or now - cycleTradeState.lastMissingNotice[key] > 10000 then
		cycleTradeState.lastMissingNotice[key] = now
		sendNotify(textValue)
	end
end

function cycleRestoreTemporaryLists()
	if cycleTradeState.sellListBackup then
		context.setSellList(cycleTradeState.sellListBackup)
		cycleTradeState.sellListBackup = nil
	end
	if cycleTradeState.buyListBackup then
		context.setBuyList(cycleTradeState.buyListBackup)
		cycleTradeState.buyListBackup = nil
	end
end

function cycleAbortActive(keepQueue)
	local active = cycleTradeState.active
	if not active then
		cycleRestoreTemporaryLists()
		return
	end

	if active.kind == "sell" then
		sell_check = false
		context.setSellScanMode(false)
		sell_busy = false
		need_to_sell = 0
		if sell_alitems_d ~= nil then
			lets_gooo = false
		end
	elseif active.kind == "readd_buy" then
		-- Отдельного воркера здесь нет, общая торговая автоматика сбрасывается ниже.
	end

	tradeAutomationVisible[0] = false
	context.setTradeAutomation({ sell = false, buy = false, score = 1, score_from = 1 })
	cycleRestoreTemporaryLists()
	cycleTradeState.active = nil
	cycleTradeState.nextActionAt = getGameTimer() + 800

	if not keepQueue then
		cycleTradeState.pending = {}
		cycleTradeState.listedOutstanding = {}
	end
end

function cycleCanStartAutomation()
	if cycleTradeState.active then
		return false
	end
	if context.getTradeAutomation().sell or context.getTradeAutomation().buy then
		return false
	end
	if scanWorkerState[2] or clearWorkerState[2] then
		return false
	end
	if context.getBuyScanMode() or context.getSellScanMode() then
		return false
	end
	if is_invent_open ~= nil or marketState.custom_is_invent_open[1] ~= nil then
		return false
	end
	if getGameTimer() < cycleTradeState.nextActionAt then
		return false
	end
	return true
end

function cycleStartSell(entry)
	local sourceList = cycleGetConfigSellList()
	local template = cycleFindItem(sourceList, entry.name)
	if not template then
		cycleNotifyMissing(entry.key .. ":sell", u8:decode("Автоцикл: предмет есть в скупке, но отсутствует в списке продажи: ") .. entry.name)
		return false
	end

	local qty = math.max(1, math.floor(tonumber(entry.pendingSell) or 0))
	if qty <= 0 then
		return false
	end

	if not lowPriceGuardPreflight({ template }, "sell", false) then
		if modificationState.setAutoCycleEnabled then
			modificationState.setAutoCycleEnabled(false, false)
		end
		AFKMessage(u8:decode("Автоцикл отключён: цена продажи слишком низкая относительно средней."))
		return false
	end

	local temporary = cycleClone(template)
	temporary.enabled = true
	temporary.maximum = false
	temporary.count = qty
	temporary.all_count = math.max(qty, tonumber(temporary.all_count) or qty)
	temporary.slot_count = temporary.slot_count or { tostring(qty) }
	temporary.slot_id = temporary.slot_id or { "0" }

	cycleTradeState.sellListBackup = context.getSellList()
	context.setSellList({ temporary })
	cycleTradeState.active = {
		kind = "sell",
		key = entry.key,
		name = entry.name,
		qty = qty,
		startedAt = getGameTimer(),
		accounted = false,
		failed = false
	}

	context.setSellStatusMessages({})
	context.setSellScanMode(true)
	context.setSellScanResults({})
	SendToServer("/stats")
	sell_check = true
	tradeAutomationVisible[0] = true
	context.setTradeAutomation({ sell = true, buy = false, score = 0, score_from = 1 })
	sendNotify(u8:decode("Автоцикл: скуплено, ставлю на продажу: ") .. entry.name .. " x" .. tostring(qty))
	return true
end

function cycleStartReaddBuy(active)
	local template = active.buyTemplate or cycleFindItem(cycleGetConfigBuyList(), active.name)
	if not template then
		cycleNotifyMissing(active.key .. ":buy", u8:decode("Автоцикл: не найден шаблон скупки для: ") .. active.name)
		cycleAbortActive(true)
		return false
	end

	local temporary = cycleClone(template)
	temporary.enabled = true
	temporary.maximum = false
	temporary.count_maximum = 0
	temporary.count = math.max(1, math.floor(tonumber(active.targetCount) or 1))
	temporary.continue = temporary.count

	cycleTradeState.buyListBackup = context.getBuyList()
	context.setBuyList({ temporary })
	active.kind = "readd_buy"
	active.startedAt = getGameTimer()
	active.success = false
	active.failed = false
	tradeAutomationVisible[0] = true
	context.setTradeAutomation({ sell = false, buy = true, score = 1, score_from = 1 })
	setGameKeyState(21, 255)
	sampForceOnfootSync()
	return true
end

function cycleStartRebuild(entry)
	local buyTemplate = cycleFindItem(cycleGetConfigBuyList(), entry.name)
	if not buyTemplate then
		cycleNotifyMissing(entry.key .. ":buy", u8:decode("Автоцикл: не найден шаблон скупки для: ") .. entry.name)
		return false
	end

	if not lowPriceGuardPreflight({ buyTemplate }, "buy", false) then
		if modificationState.setAutoCycleEnabled then
			modificationState.setAutoCycleEnabled(false, false)
		end
		AFKMessage(u8:decode("Автоцикл отключён: цена скупки слишком низкая относительно средней."))
		return false
	end

	local pendingQty = math.max(1, math.floor(tonumber(entry.pendingRebuy) or 0))
	if pendingQty <= 0 then
		return false
	end

	local currentCount = cycleGetMarketBuyCount(entry.name)
	local targetCount = tonumber(entry.rebuildTarget)
	if not targetCount then
		targetCount = math.max(1, (tonumber(currentCount) or 0) + pendingQty)
		entry.rebuildTarget = targetCount
	end

	local active = {
		kind = currentCount and currentCount > 0 and "remove_buy" or "readd_wait",
		key = entry.key,
		name = entry.name,
		pendingQty = pendingQty,
		targetCount = targetCount,
		buyTemplate = cycleClone(buyTemplate),
		startedAt = getGameTimer(),
		selectionSent = false,
		failed = false,
		nextActionAt = getGameTimer() + 250
	}
	cycleTradeState.active = active

	if active.kind == "remove_buy" then
		setGameKeyState(21, 255)
		sampForceOnfootSync()
	else
		sendNotify(u8:decode("Автоцикл: продано, восстанавливаю скупку: ") .. entry.name .. " x" .. tostring(pendingQty))
	end
	return true
end

function cycleTradeOnBought(itemName, itemCount)
	if not modificationState.autoCycleEnabled[0] and cycleTradeState.active == nil then
		return
	end
	local count = math.max(1, math.floor(tonumber(itemCount) or 1))
	local marketCount = cycleGetMarketBuyCount(itemName)
	if marketCount == nil then
		return
	end
	local entry = cycleEntry(itemName)
	if not entry then
		return
	end
	local sellTemplate = cycleFindItem(cycleGetConfigSellList(), itemName)
	if not sellTemplate then
		cycleNotifyMissing(entry.key .. ":sell", u8:decode("Автоцикл: предмет есть в скупке, но отсутствует в списке продажи: ") .. tostring(itemName))
		return
	end
	entry.pendingSell = (tonumber(entry.pendingSell) or 0) + count

	local active = cycleTradeState.active
	if active and active.key == entry.key and (active.kind == "remove_buy" or active.kind == "readd_wait" or active.kind == "readd_buy") then
		active.targetCount = math.max(1, (tonumber(active.targetCount) or 1) - count)
		entry.rebuildTarget = active.targetCount
	end
end

function cycleTradeOnSold(itemName, itemCount)
	if not modificationState.autoCycleEnabled[0] then
		return
	end
	local entry, key = cycleEntry(itemName)
	if not entry then
		return
	end
	local outstanding = tonumber(cycleTradeState.listedOutstanding[key]) or 0
	if outstanding <= 0 then
		return
	end
	local soldCount = math.max(1, math.floor(tonumber(itemCount) or 1))
	local cycleSold = math.min(outstanding, soldCount)
	cycleTradeState.listedOutstanding[key] = outstanding - cycleSold
	entry.pendingRebuy = (tonumber(entry.pendingRebuy) or 0) + cycleSold

	local active = cycleTradeState.active
	if active and active.key == entry.key and (active.kind == "remove_buy" or active.kind == "readd_wait") then
		active.targetCount = math.max(1, (tonumber(active.targetCount) or 0) + cycleSold)
		active.pendingQty = (tonumber(active.pendingQty) or 0) + cycleSold
		entry.rebuildTarget = active.targetCount
	else
		entry.rebuildTarget = nil
	end
	sendNotify(u8:decode("Автоцикл: продано, восстанавливаю скупку: ") .. entry.name .. " x" .. tostring(cycleSold))
end

function cycleTradeOnSellListed(message)
	local active = cycleTradeState.active
	if not active or active.kind ~= "sell" or active.accounted then
		return
	end
	local itemName = tostring(message or ""):match(u8:decode("Товар%s+(.+)%s+успешно"))
	if itemName and cycleNormalizeName(itemName) ~= active.key then
		return
	end
	active.accounted = true
	if type(manualPurchasedConsume) == "function" and not (manualPurchasedState and manualPurchasedState.running) then
		manualPurchasedConsume(active.name, active.qty)
	end
	local entry = cycleTradeState.pending[active.key]
	if entry then
		entry.pendingSell = math.max(0, (tonumber(entry.pendingSell) or 0) - active.qty)
	end
	cycleTradeState.listedOutstanding[active.key] = (tonumber(cycleTradeState.listedOutstanding[active.key]) or 0) + active.qty
	sendNotify(u8:decode("Автоцикл: выставлено на продажу: ") .. active.name .. " x" .. tostring(active.qty))
end

function cycleTradeOnBuyRemoved(itemName)
	local active = cycleTradeState.active
	if not active or active.kind ~= "remove_buy" then
		return
	end
	if cycleNormalizeName(itemName) ~= active.key then
		return
	end
	active.kind = "readd_wait"
	active.startedAt = getGameTimer()
	active.nextActionAt = getGameTimer() + 350
	sendNotify(u8:decode("Автоцикл: продано, восстанавливаю скупку: ") .. active.name .. " x" .. tostring(active.pendingQty))
end

function cycleTradeOnBuyStarted(message)
	local active = cycleTradeState.active
	if not active or active.kind ~= "readd_buy" then
		return
	end
	local itemName = tostring(message or ""):match(u8:decode("товара%s+(.-)%s+в%s+количестве"))
	if itemName and cycleNormalizeName(itemName) ~= active.key then
		return
	end
	active.success = true
end

function cycleTradeHandleDialog(dialogId, style, title, button1, button2, text)
	local active = cycleTradeState.active
	if not active or active.kind ~= "remove_buy" or active.selectionSent then
		return false
	end

	if text:find(u8:decode("Прекратить аренду прилавка")) and text:find(u8:decode("Прекратить покупку товара")) then
		sampSendDialogResponsed(dialogId, 1, 3)
		return true
	end

	if title:find(u8:decode("Страница")) then
		local counter = 0
		local nextIndex = nil
		local targetIndex = nil
		local currentPage, totalPages = title:match("(%d+)/(%d+)")
		for line in text:gmatch("[^\r\n]+") do
			local listedName = line:match("{......}(.+)%s%{......}.+{......}")
			if listedName and cycleNormalizeName(listedName) == active.key then
				targetIndex = counter - 1
				break
			end
			if line:find(">>>") then
				nextIndex = counter - 1
			end
			counter = counter + 1
		end

		if targetIndex ~= nil then
			active.selectionSent = true
			sampSendDialogResponsed(dialogId, 1, math.max(0, targetIndex))
			return true
		end
		if nextIndex ~= nil and (not currentPage or not totalPages or tonumber(currentPage) < tonumber(totalPages)) then
			sampSendDialogResponsed(dialogId, 1, math.max(0, nextIndex))
			return true
		end

		cycleNotifyMissing(active.key .. ":remove", u8:decode("Автоцикл: нужный слот скупки не найден в лавке: ") .. active.name)
		local entry = cycleTradeState.pending[active.key]
		if entry then
			entry.rebuildTarget = nil
		end
		cycleAbortActive(true)
		return true
	end

	return false
end

function cycleFinishReadd(active)
	local entry = cycleTradeState.pending[active.key]
	cycleRestoreTemporaryLists()
	if entry and active.success then
		entry.pendingRebuy = math.max(0, (tonumber(entry.pendingRebuy) or 0) - active.pendingQty)
		entry.rebuildTarget = nil
		local configItem = cycleFindItem(context.getBuyList(), active.name)
		if configItem then
			configItem.continue = active.targetCount
		end
		if context.getLoadedBuyConfig() ~= "" and #context.getBuyList() > 0 then
			local fileName = context.getLoadedBuyConfig():match("(.+)%.json") and context.getLoadedBuyConfig() or context.getLoadedBuyConfig() .. ".json"
			pcall(createConfig, "buy-cfg/" .. fileName, context.getBuyList(), "buy-cfg", fileName)
		end
		sendNotify(u8:decode("Автоцикл: скупка восстановлена: ") .. active.name .. " -> " .. tostring(active.targetCount))
	end
	cycleTradeState.active = nil
	cycleTradeState.nextActionAt = getGameTimer() + 650
end

function cycleTradeUpdate()
	local cycleEnabled = modificationState.autoCycleEnabled[0] == true
	local active = cycleTradeState.active
	if active then
		local now = getGameTimer()
		if now - (active.startedAt or now) > cycleTradeState.operationTimeoutMs then
			sendNotify(u8:decode("Автоцикл: таймаут операции, повторю позже."))
			cycleAbortActive(true)
			return
		end

		if active.kind == "sell" then
			if active.accounted and not context.getTradeAutomation().sell then
				cycleRestoreTemporaryLists()
				cycleTradeState.active = nil
				cycleTradeState.nextActionAt = now + 650
			elseif not context.getTradeAutomation().sell and not active.accounted then
				cycleAbortActive(true)
			end
		elseif active.kind == "readd_wait" and now >= (active.nextActionAt or 0) then
			cycleStartReaddBuy(active)
		elseif active.kind == "readd_buy" then
			if active.success and not context.getTradeAutomation().buy then
				cycleFinishReadd(active)
			elseif not context.getTradeAutomation().buy and not active.success then
				cycleAbortActive(true)
			end
		end
		return
	end

	if not cycleEnabled then
		cycleTradeState.pending = {}
		cycleTradeState.listedOutstanding = {}
		return
	end

	if not cycleCanStartAutomation() then
		return
	end
	if ini.cfg.active_lavka_number == -1 and context.getActiveLavkaId() == -1 then
		return
	end

	for _, entry in pairs(cycleTradeState.pending) do
		if (tonumber(entry.pendingRebuy) or 0) > 0 then
			if cycleStartRebuild(entry) then
				return
			end
		end
	end
	for _, entry in pairs(cycleTradeState.pending) do
		if (tonumber(entry.pendingSell) or 0) > 0 then
			if cycleStartSell(entry) then
				return
			end
		end
	end
end

return true
end

return M
