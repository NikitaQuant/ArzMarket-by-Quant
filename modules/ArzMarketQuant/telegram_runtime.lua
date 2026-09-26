local M = { api_version = 1, module_version = 1 }

function M.init(ctx)
local context = type(ctx) == "table" and ctx or {}
local u8 = context.u8
local decodeJsonSafe = context.decodeJsonSafe
local ffi = context.ffi
local zzlibLoaded = context.zzlibLoaded
local effilLoaded, effil = context.effilLoaded, context.effil
local marketState = context.marketState
local telegramUi = context.telegramUi
local telegramNotifyEnabled = context.telegramNotifyEnabled

TELEGRAM_LAST_ERROR_NOTICE_AT = 0
TELEGRAM_ORIGINAL_THREADS = {}
TELEGRAM_SEND_QUEUE = {}
TELEGRAM_SEND_ACTIVE = false
TELEGRAM_SHUTTING_DOWN = false
TELEGRAM_REQUEST_SERIAL = 0
TELEGRAM_MAX_QUEUE = 50
TELEGRAM_LAST_RESULT = {
	ok = nil,
	host = "",
	error = "",
	status = 0,
	at = 0
}
TELEGRAM_OFFICIAL_TIMEOUT = 25
TELEGRAM_RESERVE_TIMEOUT = 10

function telegramOriginalCleanup()
	TELEGRAM_SHUTTING_DOWN = true
	TELEGRAM_SEND_ACTIVE = false
	TELEGRAM_SEND_QUEUE = {}

	for requestId, requestThread in pairs(TELEGRAM_ORIGINAL_THREADS or {}) do
		if requestThread ~= nil then
			-- Never block MoonLoader/AutoReboot while a network worker is stuck in C code.
			pcall(function()
				if requestThread.cancel then requestThread:cancel(0) end
			end)
		end
		TELEGRAM_ORIGINAL_THREADS[requestId] = nil
	end
end

function telegramOriginalAsyncHttpRequest(method, url, requestOptions, onSuccess, onError, timeoutSeconds)
	if ARZ_FIRST_BOOTSTRAP_ACTIVE then
		if type(onError) == "function" then pcall(onError, "first_bootstrap_offline") end
		return nil, "first_bootstrap_offline"
	end
	requestOptions = requestOptions or {}
	requestOptions.headers = requestOptions.headers or {}
	requestOptions.headers["Accept-Encoding"] = ini.cfg.bannedByRkn == true and zzlibLoaded == true and "gzip, deflate" or nil

	onSuccess = onSuccess or function() end
	onError = onError or function() end
	timeoutSeconds = math.max(3, tonumber(timeoutSeconds) or 25)

	if TELEGRAM_SHUTTING_DOWN then
		return nil, "script_terminating"
	end

	if not effilLoaded or effil == nil or type(effil.thread) ~= "function" then
		return nil, "effil_unavailable"
	end

	local createOk, requestThread = pcall(function()
		return effil.thread(function(method, url, requestOptions)
			local requests = require("requests")
			local workerEffil = require("effil")
			local workerPcall = type(workerEffil.pcall) == "function" and workerEffil.pcall or pcall
			local requestSucceeded, response = workerPcall(requests.request, method, url, requestOptions)

			if not requestSucceeded then
				return false, response
			end

			if type(response) ~= "table" then
				return false, "invalid_response_object"
			end

			local isGzipEncoded = response.headers and response.headers["content-encoding"] and response.headers["content-encoding"]:find("gzip")
			local zzlibAvailable
			local zzlib

			if isGzipEncoded then
				zzlibAvailable, zzlib = pcall(require, "zzlib")
			end

			if not zzlibAvailable and isGzipEncoded then
				return false, "gzip_without_zzlib"
			end

			if isGzipEncoded and response.text and type(response.text) == "string" and #response.text > 2 then
				local decompressedText = response.text
				local wasDecompressed = false

				if response.text:byte(1) == 31 and response.text:byte(2) == 139 then
					local unzipOk, unzipResult = pcall(zzlib.gunzip, response.text)
					if not unzipOk then return false, tostring(unzipResult) end
					decompressedText = unzipResult
					wasDecompressed = true
				end

				if wasDecompressed and decompressedText then
					response.text = decompressedText
					response.original_size = #response.text
					response.decompressed = true
				end
			end

			response.json, response.xml = nil
			return true, response
		end)(method, url, requestOptions)
	end)
	if not createOk or not requestThread then
		pcall(onError, "effil_start_failed: " .. tostring(requestThread))
		return nil, tostring(requestThread)
	end

	TELEGRAM_REQUEST_SERIAL = (tonumber(TELEGRAM_REQUEST_SERIAL) or 0) + 1
	local requestId = tostring(os.clock()) .. ":tg:" .. tostring(TELEGRAM_REQUEST_SERIAL)
	TELEGRAM_ORIGINAL_THREADS[requestId] = requestThread

	local function cleanupRequest()
		TELEGRAM_ORIGINAL_THREADS[requestId] = nil
	end

	lua_thread.create(function()
		local startedAt = os.time()

		while true do
			if TELEGRAM_SHUTTING_DOWN then
				pcall(function()
					if requestThread.cancel then requestThread:cancel(0) end
				end)
				cleanupRequest()
				return
			end

			if startedAt + timeoutSeconds < os.time() then
				pcall(function()
					if requestThread.cancel then requestThread:cancel(0) end
				end)
				cleanupRequest()
				pcall(onError, "timeout")
				return
			end

			local statusOk, threadStatus, threadError = pcall(function()
				return requestThread:status()
			end)

			if not statusOk then
				cleanupRequest()
				pcall(onError, tostring(threadStatus))
				return
			end

			if threadError then
				cleanupRequest()
				pcall(onError, tostring(threadError))
				return
			end

			if threadStatus == "completed" then
				local getOk, requestSucceeded, response = pcall(function()
					return requestThread:get(0)
				end)
				cleanupRequest()

				if getOk and requestSucceeded then
					pcall(onSuccess, response)
				else
					pcall(onError, tostring(getOk and response or requestSucceeded))
				end
				return
			elseif threadStatus == "cancelled" then
				cleanupRequest()
				pcall(onError, "cancelled")
				return
			elseif threadStatus == "failed" then
				cleanupRequest()
				pcall(onError, tostring(threadError or "thread_failed"))
				return
			end

			wait(0)
		end
	end)

	return requestThread
end

function telegramUrlEncode(value)
	value = tostring(value or "")
	local encoded = string.gsub(value, "([^%w-_ %.~=])", function(character)
		return string.format("%%%02X", string.byte(character))
	end)
	return string.gsub(encoded, " ", "+")
end

function telegramResponseSucceeded(response)
	if type(response) ~= "table" then
		return false, "invalid_response", 0
	end

	local status = tonumber(response.status_code or response.status or 0) or 0
	local body = type(response.text) == "string" and response.text or ""
	local decoded = nil

	if body ~= "" then
		local decodeOk, decodeResult = pcall(decodeJsonSafe, body)
		if decodeOk and type(decodeResult) == "table" then
			decoded = decodeResult
		end
	end

	if decoded and decoded.ok == true and (status == 0 or (status >= 200 and status < 300)) then
		return true, "", status
	end

	if decoded and decoded.ok == false then
		return false, tostring(decoded.description or ("telegram_api_error_" .. tostring(status))), status
	end

	if status < 200 or status >= 300 then
		return false, "http_" .. tostring(status), status
	end

	-- Telegram Bot API always returns a JSON object with the boolean field "ok".
	return false, "invalid_telegram_json", status
end

function telegramBuildTargets()
	local targets = {}

	if ini.cfg.telegram_reserve == true then
		targets[#targets + 1] = {
			host = "api-telegram.arz.market",
			timeout = TELEGRAM_RESERVE_TIMEOUT
		}
	end

	targets[#targets + 1] = {
		host = "api.telegram.org",
		timeout = TELEGRAM_OFFICIAL_TIMEOUT
	}

	return targets
end

function telegramCompleteJob(job, ok, host, errorMessage, status)
	TELEGRAM_SEND_ACTIVE = false

	TELEGRAM_LAST_RESULT.ok = ok == true
	TELEGRAM_LAST_RESULT.host = tostring(host or "")
	TELEGRAM_LAST_RESULT.error = tostring(errorMessage or "")
	TELEGRAM_LAST_RESULT.status = tonumber(status) or 0
	TELEGRAM_LAST_RESULT.at = os.time()

	if ok then
		print("[ArzMarket][Telegram] sent via " .. tostring(host))
		if job and job.diagnostic then
			sendNotify("Telegram: OK (" .. tostring(host) .. ")")
		end
	else
		local message = "[ArzMarket][Telegram] send failed: " .. tostring(errorMessage)
		print(message)

		if job and job.diagnostic then
			sendNotify("Telegram error: " .. tostring(errorMessage))
		end
	end

	if not TELEGRAM_SHUTTING_DOWN then
		telegramProcessSendQueue()
	end
end

function telegramHandleJobFailure(job, target, errorMessage, status)
	job.targetIndex = (tonumber(job.targetIndex) or 1) + 1

	if job.targets and job.targets[job.targetIndex] then
		print(
			"[ArzMarket][Telegram] " .. tostring(target and target.host or "?")
			.. " failed (" .. tostring(errorMessage) .. "), fallback -> "
			.. tostring(job.targets[job.targetIndex].host)
		)
		return telegramStartJob(job)
	end

	return telegramCompleteJob(
		job,
		false,
		target and target.host or "",
		errorMessage or "request_failed",
		status or 0
	)
end

function telegramStartJob(job)
	if TELEGRAM_SHUTTING_DOWN then
		TELEGRAM_SEND_ACTIVE = false
		return
	end

	if type(job) ~= "table" or type(job.targets) ~= "table" then
		return telegramCompleteJob(job, false, "", "invalid_job", 0)
	end

	job.targetIndex = tonumber(job.targetIndex) or 1
	local target = job.targets[job.targetIndex]
	if type(target) ~= "table" or type(target.host) ~= "string" or target.host == "" then
		return telegramCompleteJob(job, false, "", "invalid_target", 0)
	end

	-- Keep Telegram request shape identical to the original ArzMarket.
	-- The original script sends chat_id/text in the query string and uses an empty request body.
	local url = "https://" .. target.host
		.. "/bot" .. tostring(job.token)
		.. "/sendMessage?chat_id=" .. telegramUrlEncode(job.chatId)
		.. "&text=" .. telegramUrlEncode(job.message)

	local requestThread, requestError = telegramOriginalAsyncHttpRequest(
		"POST",
		url,
		{},
		function(response)
			local ok, errorMessage, status = telegramResponseSucceeded(response)
			if ok then
				return telegramCompleteJob(job, true, target.host, "", status)
			end
			return telegramHandleJobFailure(job, target, errorMessage, status)
		end,
		function(errorMessage)
			return telegramHandleJobFailure(job, target, tostring(errorMessage or "request_failed"), 0)
		end,
		target.timeout
	)

	if requestThread == nil then
		return telegramHandleJobFailure(job, target, requestError or "request_not_started", 0)
	end

	return requestThread
end

function telegramProcessSendQueue()
	if TELEGRAM_SHUTTING_DOWN or TELEGRAM_SEND_ACTIVE then
		return
	end

	if type(TELEGRAM_SEND_QUEUE) ~= "table" or #TELEGRAM_SEND_QUEUE == 0 then
		return
	end

	local job = table.remove(TELEGRAM_SEND_QUEUE, 1)
	if type(job) ~= "table" then
		return telegramProcessSendQueue()
	end

	TELEGRAM_SEND_ACTIVE = true
	return telegramStartJob(job)
end

function telegramWorkingOriginalAsyncHttpRequest(method, url, requestOptions, onSuccess, onError, saveSelfInfo)
	if ARZ_FIRST_BOOTSTRAP_ACTIVE then
		if type(onError) == "function" then pcall(onError, "first_bootstrap_offline") end
		return nil, "first_bootstrap_offline"
	end
	marketState.asyncRequestSerial = (tonumber(marketState.asyncRequestSerial) or 0) + 1
	local requestId = tostring(os.clock()) .. ":tg:" .. tostring(marketState.asyncRequestSerial)
	marketState.asyncData[requestId] = os.time()
	requestOptions = requestOptions or {}
	requestOptions.headers = requestOptions.headers or {}
	requestOptions.headers["Accept-Encoding"] = ini.cfg.bannedByRkn == true and zzlibLoaded == true and "gzip, deflate" or nil
	onSuccess = type(onSuccess) == "function" and onSuccess or function() end
	onError = type(onError) == "function" and onError or function() end

	local createOk, requestThread = pcall(function()
		return effil.thread(function(method, url, requestOptions)
			local requests = require("requests")
			local workerEffil = require("effil")
			local workerPcall = type(workerEffil.pcall) == "function" and workerEffil.pcall or pcall
			local requestSucceeded, response = workerPcall(requests.request, method, url, requestOptions)
			if not requestSucceeded then return false, response end
			if type(response) ~= "table" then return false, "invalid_response" end

			local isGzipEncoded = response.headers
				and response.headers["content-encoding"]
				and response.headers["content-encoding"]:find("gzip")
			local zzlibAvailable, zzlib
			if isGzipEncoded then zzlibAvailable, zzlib = pcall(require, "zzlib") end
			if not zzlibAvailable and isGzipEncoded then return false, response end
			if isGzipEncoded and type(response.text) == "string" and #response.text > 2 then
				local decompressedText, wasDecompressed
				if response.text:byte(1) == 31 and response.text:byte(2) == 139 then
					local unzipOk, unzipResult = pcall(zzlib.gunzip, response.text)
					decompressedText, wasDecompressed = unzipOk and unzipResult or nil, unzipOk
				else
					decompressedText, wasDecompressed = response.text, false
				end
				if wasDecompressed and decompressedText then
					response.text = decompressedText
					response.original_size = #decompressedText
					response.decompressed = true
				end
			end
			response.json, response.xml = nil, nil
			return true, response
		end)(method, url, requestOptions)
	end)

	if not createOk or not requestThread then
		marketState.asyncData[requestId] = nil
		lua_thread.create(function()
			wait(0)
			pcall(onError, "effil_start_failed: " .. tostring(requestThread))
		end)
		return nil, tostring(requestThread)
	end

	lua_thread.create(function(currentRequestId)
		while marketState.asyncData[currentRequestId] ~= nil do
			local statusOk, threadStatus, threadError = pcall(function() return requestThread:status() end)
			if not statusOk then
				marketState.asyncData[currentRequestId] = nil
				pcall(onError, "effil_status_failed: " .. tostring(threadStatus))
				return
			end

			local requestStartedAt = marketState.asyncData[currentRequestId]
			if requestStartedAt == nil then return end
			if requestStartedAt + 45 < os.time() then
				pcall(function() if requestThread.cancel then requestThread:cancel(0) end end)
				marketState.asyncData[currentRequestId] = nil
				pcall(onError, "timeout")
				return
			end

			if threadStatus == "completed" then
				local getOk, requestSucceeded, response = pcall(function() return requestThread:get(0) end)
				marketState.asyncData[currentRequestId] = nil
				if not getOk then pcall(onError, "effil_get_failed: " .. tostring(requestSucceeded)); return end
				if requestSucceeded then
					if saveSelfInfo == 1 and type(response) == "table" and type(response.text) == "string"
						and response.text:find("username") and response.text:find("exp") and response.text:find("osTime") then
						pcall(function()
							local selfInfoFile = io.open("moonloader/ArzMarket/UsersInfo/info_users_SelfInfo.json", "w")
							if selfInfoFile then selfInfoFile:write(response.text); selfInfoFile:close() end
						end)
					end
					pcall(onSuccess, response)
				else
					pcall(onError, response)
				end
				return
			elseif threadStatus == "cancelled" then
				marketState.asyncData[currentRequestId] = nil
				pcall(onError, "cancelled")
				return
			elseif threadStatus == "failed" or threadError then
				marketState.asyncData[currentRequestId] = nil
				pcall(onError, threadError or "effil_failed")
				return
			end
			wait(0)
		end
	end, requestId)
	return requestId
end

function sendTelegramNotification(message)
	local utf8Message = u8(message)

	if telegramNotifyEnabled[0] == false then
		return
	end

	local plainMessage = utf8Message:gsub("{......}", "")
	local urlEncodedMessage = string.gsub(plainMessage, "([^%w-_ %.~=])", function(character)
		return string.format("%%%02X", string.byte(character))
	end)
	local telegramMessage = string.gsub(urlEncodedMessage, " ", "+")

	telegramWorkingOriginalAsyncHttpRequest(
		"POST",
		"https://"
			.. (ini.cfg.telegram_reserve and "api-telegram.arz.market" or "api.telegram.org")
			.. "/bot"
			.. ffi.string(telegramUi.token)
			.. "/sendMessage?chat_id="
			.. ffi.string(telegramUi.chat_id)
			.. "&text="
			.. telegramMessage
	)
end


-- ============================================================
return true
end

return M
