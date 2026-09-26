local M = { api_version = 1, module_version = 1 }

function M.init(ctx)
local context = type(ctx) == "table" and ctx or {}
local imgui, imguiNew, u8, ffi = context.imgui, context.imguiNew, context.u8, context.ffi
local menuThemePath, menuThemeConfig = context.menuThemePath, context.menuThemeConfig
local getMenuUiScale = context.getMenuUiScale
local windowColor, separatorColor = context.windowColor, context.separatorColor
local activeToggleColor, inactiveToggleColor = context.activeToggleColor, context.inactiveToggleColor

function arzGlobalPaletteApplyRuntime()
	arzGlobalPaletteApplyConfig()
	if type(arzPaletteSyncRuntime) == "function" then arzPaletteSyncRuntime() end
	if type(imgui.FrameTheme) == "function" then imgui.FrameTheme() end
end

function arzGlobalPaletteSet(payload)
	local palette = arzGlobalPaletteEnsureStorage()
	local data = type(payload) == "table" and payload or {}
	if data.reset == true then
		palette.base = "#4B8DFF"
		palette.depth = 72
		palette.saturation = 82
		palette.contrast = 72
		palette.glow = 80
		local defaultColor = arzPaletteHex(palette.base)
		palette.picker_hue, palette.picker_saturation, palette.picker_value = arzCustomPaletteRgbToHsv(defaultColor[1], defaultColor[2], defaultColor[3])
		if data.enabled ~= nil then palette.enabled = data.enabled == true end
	else
		if data.enabled ~= nil then palette.enabled = data.enabled == true end
		if data.base ~= nil then palette.base = arzGlobalPaletteNormalizeHex(data.base) end
		if data.depth ~= nil then palette.depth = arzGlobalPalettePercent(data.depth, palette.depth) end
		if data.saturation ~= nil then palette.saturation = arzGlobalPalettePercent(data.saturation, palette.saturation) end
		if data.contrast ~= nil then palette.contrast = arzGlobalPalettePercent(data.contrast, palette.contrast) end
		if data.glow ~= nil then palette.glow = arzGlobalPalettePercent(data.glow, palette.glow) end
		if data.picker_hue ~= nil then palette.picker_hue = arzPaletteClamp(tonumber(data.picker_hue) or palette.picker_hue or 0) end
		if data.picker_saturation ~= nil then palette.picker_saturation = arzPaletteClamp(tonumber(data.picker_saturation) or palette.picker_saturation or 0) end
		if data.picker_value ~= nil then palette.picker_value = arzPaletteClamp(tonumber(data.picker_value) or palette.picker_value or 0) end
		if data.base ~= nil and data.picker_hue == nil and data.picker_saturation == nil and data.picker_value == nil then
			local currentColor = arzPaletteHex(palette.base)
			palette.picker_hue, palette.picker_saturation, palette.picker_value = arzCustomPaletteRgbToHsv(currentColor[1], currentColor[2], currentColor[3])
		end
	end
	if palette.enabled == true then
		menuThemeConfig.custom_palette_enabled = false
		arzGlobalPaletteApplyRuntime()
	else
		arzPaletteApplyConfig(menuThemeConfig.palette_key or "arzmarket_default")
		if menuThemeConfig.custom_palette_enabled == true then arzCustomPaletteApplyOverrides() end
		arzCustomPaletteRefreshStyle()
	end
	return writeJsonFile(menuThemeConfig, menuThemePath) == true
end

function arzCustomPaletteU32(r, g, b, alpha)
	return imgui.GetColorU32Vec4(imgui.ImVec4(
		arzCustomPaletteClamp(r),
		arzCustomPaletteClamp(g),
		arzCustomPaletteClamp(b),
		arzCustomPaletteClamp(alpha == nil and 1 or alpha)
	))
end

function arzCustomPalettePicker(idPrefix, color, totalWidth)
	local changed = false
	local c = arzCustomPaletteCopy(color)
	local h, s, v = arzCustomPaletteRgbToHsv(c[1], c[2], c[3])
	local alpha = c[4]
	local gap = 12
	local hueWidth = 18
	local available = tonumber(totalWidth) or 250
	local squareSize = math.floor(math.max(140, math.min(220, available - hueWidth - gap)))
	local drawList = imgui.GetWindowDrawList()
	local squarePos = imgui.GetCursorScreenPos()

	imgui.InvisibleButton(idPrefix .. "##sv", imgui.ImVec2(squareSize, squareSize))
	local squareActive = imgui.IsItemHovered() and imgui.IsMouseDown(0)
	local hueR, hueG, hueB = arzCustomPaletteHsvToRgb(h, 1, 1)
	local white = arzCustomPaletteU32(1, 1, 1, 1)
	local hueColor = arzCustomPaletteU32(hueR, hueG, hueB, 1)
	local black = arzCustomPaletteU32(0, 0, 0, 1)
	local transparent = arzCustomPaletteU32(0, 0, 0, 0)
	local border = arzCustomPaletteU32(1, 1, 1, 0.22)
	local markerDark = arzCustomPaletteU32(0, 0, 0, 0.90)
	local markerLight = arzCustomPaletteU32(1, 1, 1, 0.98)

	drawList:AddRectFilledMultiColor(
		squarePos,
		imgui.ImVec2(squarePos.x + squareSize, squarePos.y + squareSize),
		white, hueColor, hueColor, white
	)
	drawList:AddRectFilledMultiColor(
		squarePos,
		imgui.ImVec2(squarePos.x + squareSize, squarePos.y + squareSize),
		transparent, transparent, black, black
	)
	drawList:AddRect(squarePos, imgui.ImVec2(squarePos.x + squareSize, squarePos.y + squareSize), border, 3, 0, 1.5)

	if squareActive then
		local mouse = imgui.GetMousePos()
		s = arzCustomPaletteClamp((mouse.x - squarePos.x) / math.max(1, squareSize))
		v = arzCustomPaletteClamp(1 - ((mouse.y - squarePos.y) / math.max(1, squareSize)))
		changed = true
	end

	local cursorX = squarePos.x + s * squareSize
	local cursorY = squarePos.y + (1 - v) * squareSize
	drawList:AddCircle(imgui.ImVec2(cursorX, cursorY), 6, markerDark, 16, 2)
	drawList:AddCircle(imgui.ImVec2(cursorX, cursorY), 5, markerLight, 16, 2)

	imgui.SameLine()
	local huePos = imgui.GetCursorScreenPos()
	imgui.InvisibleButton(idPrefix .. "##hue", imgui.ImVec2(hueWidth, squareSize))
	local hueActive = imgui.IsItemHovered() and imgui.IsMouseDown(0)
	local hueStops = {
		{ 1, 0, 0 }, { 1, 1, 0 }, { 0, 1, 0 }, { 0, 1, 1 },
		{ 0, 0, 1 }, { 1, 0, 1 }, { 1, 0, 0 }
	}
	local segmentHeight = squareSize / 6
	for i = 1, 6 do
		local y1 = huePos.y + (i - 1) * segmentHeight
		local y2 = huePos.y + i * segmentHeight
		local first = hueStops[i]
		local second = hueStops[i + 1]
		drawList:AddRectFilledMultiColor(
			imgui.ImVec2(huePos.x, y1), imgui.ImVec2(huePos.x + hueWidth, y2),
			arzCustomPaletteU32(first[1], first[2], first[3], 1),
			arzCustomPaletteU32(first[1], first[2], first[3], 1),
			arzCustomPaletteU32(second[1], second[2], second[3], 1),
			arzCustomPaletteU32(second[1], second[2], second[3], 1)
		)
	end
	drawList:AddRect(huePos, imgui.ImVec2(huePos.x + hueWidth, huePos.y + squareSize), border, 3, 0, 1.5)
	if hueActive then
		local mouse = imgui.GetMousePos()
		h = arzCustomPaletteClamp((mouse.y - huePos.y) / math.max(1, squareSize))
		changed = true
	end
	local hueY = huePos.y + h * squareSize
	drawList:AddRectFilled(imgui.ImVec2(huePos.x - 2, hueY - 2), imgui.ImVec2(huePos.x + hueWidth + 2, hueY + 2), markerDark, 1)
	drawList:AddRectFilled(imgui.ImVec2(huePos.x - 1, hueY - 1), imgui.ImVec2(huePos.x + hueWidth + 1, hueY + 1), markerLight, 1)

	local r, g, b = arzCustomPaletteHsvToRgb(h, s, v)
	c[1], c[2], c[3] = r, g, b
	imgui.Dummy(imgui.ImVec2(0, 10))
	local alphaPos = imgui.GetCursorScreenPos()
	local alphaWidth = squareSize + hueWidth + gap
	imgui.InvisibleButton(idPrefix .. "##alpha", imgui.ImVec2(alphaWidth, 16))
	local alphaActive = imgui.IsItemHovered() and imgui.IsMouseDown(0)
	drawList:AddRectFilledMultiColor(
		alphaPos,
		imgui.ImVec2(alphaPos.x + alphaWidth, alphaPos.y + 16),
		arzCustomPaletteU32(c[1], c[2], c[3], 0),
		arzCustomPaletteU32(c[1], c[2], c[3], 1),
		arzCustomPaletteU32(c[1], c[2], c[3], 1),
		arzCustomPaletteU32(c[1], c[2], c[3], 0)
	)
	drawList:AddRect(alphaPos, imgui.ImVec2(alphaPos.x + alphaWidth, alphaPos.y + 16), border, 3, 0, 1.5)
	if alphaActive then
		local mouse = imgui.GetMousePos()
		alpha = arzCustomPaletteClamp((mouse.x - alphaPos.x) / math.max(1, alphaWidth))
		changed = true
	end
	c[4] = alpha
	local alphaX = alphaPos.x + alpha * alphaWidth
	drawList:AddRectFilled(imgui.ImVec2(alphaX - 2, alphaPos.y - 1), imgui.ImVec2(alphaX + 2, alphaPos.y + 17), markerDark, 1)
	drawList:AddRectFilled(imgui.ImVec2(alphaX - 1, alphaPos.y), imgui.ImVec2(alphaX + 1, alphaPos.y + 16), markerLight, 1)
	return c, changed
end

function arzCustomPaletteSnapshotFields()
	local result = {}
	for _, meta in ipairs(arzCustomPaletteAllTargets()) do
		if result[meta.field] == nil then
			result[meta.field] = arzCustomPaletteCopyForField(meta, menuThemeConfig[meta.field], menuThemeConfig[meta.field])
		end
	end
	return result
end

function arzCustomPalettePresetBaseFor(meta)
	if meta == nil then return { 1, 1, 1, 1 } end
	local snapshot = arzCustomPaletteSnapshotFields()
	local selectedKey = tostring(menuThemeConfig.palette_key or "arzmarket_default")
	arzPaletteApplyConfig(selectedKey)
	local result = arzCustomPaletteCopy(menuThemeConfig[meta.field])
	for field, value in pairs(snapshot) do menuThemeConfig[field] = value end
	menuThemeConfig.palette_key = selectedKey
	return result
end

function arzCustomPaletteResetTarget(meta)
	if meta == nil then return end
	arzCustomPaletteEnsureStorage(false)
	menuThemeConfig.custom_palette[meta.key] = arzCustomPalettePresetBaseFor(meta)
	arzCustomPaletteApplyOverrides()
	arzCustomPaletteRefreshStyle()
	ARZ_CUSTOM_PALETTE_STATE.hexSyncKey = ""
end

function arzCustomPaletteResetGroup(groupKey)
	local group = ARZ_CUSTOM_PALETTE_GROUPS[groupKey]
	if group == nil then return end
	for _, meta in ipairs(group.targets or {}) do
		menuThemeConfig.custom_palette[meta.key] = arzCustomPalettePresetBaseFor(meta)
	end
	arzCustomPaletteApplyOverrides()
	arzCustomPaletteRefreshStyle()
	ARZ_CUSTOM_PALETTE_STATE.hexSyncKey = ""
end

function arzCustomPaletteResetAll()
	arzPaletteApplyConfig(menuThemeConfig.palette_key or "arzmarket_default")
	arzCustomPaletteEnsureStorage(true)
	arzCustomPaletteApplyOverrides()
	arzCustomPaletteRefreshStyle()
	ARZ_CUSTOM_PALETTE_STATE.hexSyncKey = ""
end

function arzCustomPaletteSetEnabled(enabled)
	if enabled then
		arzGlobalPaletteEnsureStorage().enabled = false
		arzPaletteApplyConfig(menuThemeConfig.palette_key or "arzmarket_default")
		arzCustomPaletteEnsureStorage(false)
		menuThemeConfig.custom_palette_enabled = true
		arzCustomPaletteApplyOverrides()
	else
		menuThemeConfig.custom_palette_enabled = false
		arzPaletteApplyConfig(menuThemeConfig.palette_key or "arzmarket_default")
	end
	arzCustomPaletteRefreshStyle()
	writeJsonFile(menuThemeConfig, menuThemePath)
end

function arzCustomPaletteSelectButton(selected, label, id, width)
	if selected then
		imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(menuThemeConfig.active_selector_color[1], menuThemeConfig.active_selector_color[2], menuThemeConfig.active_selector_color[3], 0.90))
		imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(menuThemeConfig.Border[1], menuThemeConfig.Border[2], menuThemeConfig.Border[3], 1))
		imgui.GetStyle().FrameBorderSize = 1
	end
	local clicked = imgui.Button(label .. "##" .. id, imgui.ImVec2(width, 32))
	if selected then
		imgui.GetStyle().FrameBorderSize = 0
		imgui.PopStyleColor(2)
	end
	return clicked
end

function arzCustomPalettePreview(label, color, width)
	local c = arzCustomPaletteCopy(color)
	local luminance = c[1] * 0.299 + c[2] * 0.587 + c[3] * 0.114
	local textColor = luminance > 0.62 and imgui.ImVec4(0.08, 0.10, 0.14, 1) or imgui.ImVec4(0.96, 0.98, 1, 1)
	local value = imgui.ImVec4(c[1], c[2], c[3], c[4])
	imgui.PushStyleColor(imgui.Col.Button, value)
	imgui.PushStyleColor(imgui.Col.ButtonHovered, value)
	imgui.PushStyleColor(imgui.Col.ButtonActive, value)
	imgui.PushStyleColor(imgui.Col.Text, textColor)
	imgui.Button(label, imgui.ImVec2(width, 32))
	imgui.PopStyleColor(4)
end


function arzPaletteSyncRuntime()
	for i = 0, 3 do
		windowColor[i] = menuThemeConfig.window[i + 1] or windowColor[i]
		separatorColor[i] = menuThemeConfig.separator[i + 1] or separatorColor[i]
	end
	for i = 0, 2 do
		activeToggleColor[i] = menuThemeConfig.active_toggle_button[i + 1] or activeToggleColor[i]
		inactiveToggleColor[i] = menuThemeConfig.deactive_toggle_button[i + 1] or inactiveToggleColor[i]
	end
end

function arzPaletteSelect(themeKey)
	-- Selecting a predefined theme leaves both generated and custom palette modes.
	-- Saved palette values remain available and can be enabled again later.
	menuThemeConfig.custom_palette_enabled = false
	arzGlobalPaletteEnsureStorage().enabled = false
	local key = arzPaletteApplyConfig(themeKey)
	arzPaletteSyncRuntime()
	writeJsonFile(menuThemeConfig, menuThemePath)
	if imgui.FrameTheme then
		imgui.FrameTheme()
	end
	return key
end


function renderArzCustomPaletteSettings()
	arzCustomPaletteEnsureStorage(false)
	imgui.SetCursorPosY(imgui.GetCursorPos().y + 4)
	imgui.CenterText("Пользовательская палитра интерфейса")
	imgui.SetCursorPosY(imgui.GetCursorPos().y + 4)

	local enabled = menuThemeConfig.custom_palette_enabled == true
	local toggleLabel = enabled and "Выключить пользовательскую палитру" or "Включить пользовательскую палитру"
	local available = math.max(240, tonumber(imgui.GetContentRegionAvail().x) or 240)
	local uiScale = getMenuUiScale()
	local paletteRainbow = rainbow(0.35, 1.0)
	local oldFrameBorderSize = imgui.GetStyle().FrameBorderSize
	imgui.GetStyle().FrameBorderSize = math.max(2, 2 * uiScale)
	imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(paletteRainbow[1], paletteRainbow[2], paletteRainbow[3], 1.0))
	imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(paletteRainbow[1], paletteRainbow[2], paletteRainbow[3], 1.0))
	imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(paletteRainbow[1], paletteRainbow[2], paletteRainbow[3], 0.12))
	imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(paletteRainbow[1], paletteRainbow[2], paletteRainbow[3], 0.24))
	imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(paletteRainbow[1], paletteRainbow[2], paletteRainbow[3], 0.36))
	imgui.PushFont(fonts[20])
	local paletteToggleClicked = imgui.Button(toggleLabel .. "##arz_custom_palette_toggle", imgui.ImVec2(math.min(available, 460 * uiScale), 40))
	imgui.PopFont()
	imgui.PopStyleColor(5)
	imgui.GetStyle().FrameBorderSize = oldFrameBorderSize
	if paletteToggleClicked then
		arzCustomPaletteSetEnabled(not enabled)
		enabled = menuThemeConfig.custom_palette_enabled == true
	end
	if not enabled then
		imgui.SetCursorPosY(imgui.GetCursorPos().y + 6)
		return
	end

	local groupKey, group, meta = arzCustomPaletteCurrentTarget()
	arzCustomPaletteSyncHex(meta)
	imgui.SetCursorPosY(imgui.GetCursorPos().y + 6)
	imgui.TextDisabled("Что вы хотите изменить:")
	local gap = imgui.GetStyle().ItemSpacing.x
	local contentWidth = math.max(240, tonumber(imgui.GetContentRegionAvail().x) or 240)
	local groupColumns = contentWidth >= 600 and 3 or 2
	local groupWidth = math.max(105, (contentWidth - gap * (groupColumns - 1)) / groupColumns)
	local groupColumn = 0
	for _, key in ipairs(ARZ_CUSTOM_PALETTE_GROUP_ORDER) do
		local groupMeta = ARZ_CUSTOM_PALETTE_GROUPS[key]
		if arzCustomPaletteSelectButton(groupKey == key, groupMeta.label, "arz_custom_group_" .. key, groupWidth) then
			ARZ_CUSTOM_PALETTE_STATE.group = key
			ARZ_CUSTOM_PALETTE_STATE.target = groupMeta.targets[1].key
			groupKey, group, meta = arzCustomPaletteCurrentTarget()
			ARZ_CUSTOM_PALETTE_STATE.hexSyncKey = ""
			arzCustomPaletteSyncHex(meta)
		end
		groupColumn = groupColumn + 1
		if groupColumn < groupColumns and key ~= ARZ_CUSTOM_PALETTE_GROUP_ORDER[#ARZ_CUSTOM_PALETTE_GROUP_ORDER] then
			imgui.SameLine()
		else
			groupColumn = 0
		end
	end

	imgui.SetCursorPosY(imgui.GetCursorPos().y + 6)
	imgui.TextDisabled("Какой именно цвет редактировать:")
	local targetCount = #(group.targets or {})
	local targetColumns = targetCount >= 4 and 2 or math.max(1, math.min(3, targetCount))
	local targetWidth = math.max(105, (contentWidth - gap * (targetColumns - 1)) / targetColumns)
	local targetColumn = 0
	for _, targetMeta in ipairs(group.targets or {}) do
		if arzCustomPaletteSelectButton(meta and meta.key == targetMeta.key, targetMeta.label, "arz_custom_target_" .. targetMeta.key, targetWidth) then
			ARZ_CUSTOM_PALETTE_STATE.target = targetMeta.key
			meta = targetMeta
			ARZ_CUSTOM_PALETTE_STATE.hexSyncKey = ""
			arzCustomPaletteSyncHex(meta)
		end
		targetColumn = targetColumn + 1
		if targetColumn < targetColumns and targetMeta ~= group.targets[#group.targets] then
			imgui.SameLine()
		else
			targetColumn = 0
		end
	end

	imgui.SetCursorPosY(imgui.GetCursorPos().y + 8)
	imgui.TextDisabled("Квадрат меняет насыщенность и яркость. Полоса справа меняет оттенок. Полоса снизу меняет прозрачность.")
	local pickerWidth = math.min(250, math.max(180, contentWidth - 20))
	local cursor = imgui.GetCursorPos()
	imgui.SetCursorPosX(cursor.x + math.max(0, (contentWidth - pickerWidth) / 2))
	local currentColor = arzCustomPaletteCopy(menuThemeConfig.custom_palette[meta.key])
	local newColor, changed = arzCustomPalettePicker("arz_custom_palette_" .. tostring(meta.key), currentColor, pickerWidth)
	if changed then
		menuThemeConfig.custom_palette[meta.key] = newColor
		menuThemeConfig[meta.field] = arzCustomPaletteCopy(newColor)
		arzCustomPaletteRefreshStyle()
		ARZ_CUSTOM_PALETTE_STATE.hexSyncKey = ""
		arzCustomPaletteSyncHex(meta)
		ARZ_CUSTOM_PALETTE_STATE.hexStatus = ""
	end

	imgui.SetCursorPosY(imgui.GetCursorPos().y + 8)
	imgui.TextDisabled("Ввести HEX вручную:")
	imgui.SetNextItemWidth(math.min(contentWidth, 320))
	if imgui.InputText("##arz_custom_palette_hex", ARZ_CUSTOM_PALETTE_STATE.hexBuffer, ffi.sizeof(ARZ_CUSTOM_PALETTE_STATE.hexBuffer)) then
		local rawHex = ffi.string(ARZ_CUSTOM_PALETTE_STATE.hexBuffer)
		local parsed = arzCustomPaletteParseHex(rawHex, currentColor[4])
		if parsed then
			menuThemeConfig.custom_palette[meta.key] = parsed
			menuThemeConfig[meta.field] = arzCustomPaletteCopy(parsed)
			arzCustomPaletteRefreshStyle()
			ARZ_CUSTOM_PALETTE_STATE.hexStatus = "HEX применён"
			ARZ_CUSTOM_PALETTE_STATE.hexSyncKey = tostring(meta.key) .. ":" .. arzCustomPaletteColorToHex(parsed, parsed[4] < 0.999)
		elseif #rawHex >= 7 then
			ARZ_CUSTOM_PALETTE_STATE.hexStatus = "Некорректный HEX"
		else
			ARZ_CUSTOM_PALETTE_STATE.hexStatus = ""
		end
	end
	imgui.SameLine()
	imgui.TextDisabled("Формат: #RRGGBB или #RRGGBBAA.")
	if ARZ_CUSTOM_PALETTE_STATE.hexStatus ~= "" then
		imgui.TextDisabled(ARZ_CUSTOM_PALETTE_STATE.hexStatus)
	end

	local actual = arzCustomPaletteCopy(menuThemeConfig.custom_palette[meta.key])
	local rgbText = string.format("RGB: %d, %d, %d", math.floor(actual[1] * 255 + 0.5), math.floor(actual[2] * 255 + 0.5), math.floor(actual[3] * 255 + 0.5))
	local alphaText = string.format("Alpha: %d%%", math.floor(actual[4] * 100 + 0.5))
	imgui.TextDisabled(arzCustomPaletteColorToHex(actual, actual[4] < 0.999) .. "   " .. rgbText .. "   " .. alphaText)
	arzCustomPalettePreview("Предпросмотр", actual, math.min(contentWidth, 360))

	imgui.SetCursorPosY(imgui.GetCursorPos().y + 8)
	local actionColumns = contentWidth >= 620 and 2 or 1
	local actionWidth = math.max(150, (contentWidth - gap * (actionColumns - 1)) / actionColumns)
	if imgui.Button("Сбросить цвет" .. "##arz_custom_reset_one", imgui.ImVec2(actionWidth, 32)) then
		arzCustomPaletteResetTarget(meta)
		writeJsonFile(menuThemeConfig, menuThemePath)
	end
	if actionColumns == 2 then imgui.SameLine() end
	if imgui.Button("Сбросить группу" .. "##arz_custom_reset_group", imgui.ImVec2(actionWidth, 32)) then
		arzCustomPaletteResetGroup(groupKey)
		writeJsonFile(menuThemeConfig, menuThemePath)
	end
	if imgui.Button("Сбросить всё к теме" .. "##arz_custom_reset_all", imgui.ImVec2(actionWidth, 32)) then
		arzCustomPaletteResetAll()
		writeJsonFile(menuThemeConfig, menuThemePath)
	end
	if actionColumns == 2 then imgui.SameLine() end
	if imgui.Button("Сохранить палитру" .. "##arz_custom_save", imgui.ImVec2(actionWidth, 32)) then
		writeJsonFile(menuThemeConfig, menuThemePath)
		ARZ_CUSTOM_PALETTE_STATE.hexStatus = "Палитра сохранена."
	end
	imgui.SetCursorPosY(imgui.GetCursorPos().y + 6)
end

return true
end

return M
