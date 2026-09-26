local M = { api_version = 1, module_version = 1 }

function M.init(ctx)
local context = type(ctx) == "table" and ctx or {}
local u8, ffi = context.u8, context.ffi
local menuVisible = context.menuVisible
local lavkaHelperEnabled = context.lavkaHelperEnabled
local lavkaHelperAutoDisable = context.lavkaHelperAutoDisable
local modificationState = context.modificationState

LAVKA_HELPER_OWN_SHOP_LEAVE_DISTANCE = 12.0
LAVKA_HELPER_OWN_SHOP_LEAVE_CONFIRM = 0.8

-- The placement helper renders a LOCAL player-centered area. Red means
-- placement is allowed. The original 5/25 m forbidden circles are subtracted
-- from that local area, so the red surface appears BETWEEN the circles near
-- the player instead of being pushed away from the player.
local updateAndRenderLavkaHelper, invalidateLavkaHelperGrid, lavkaHelperOnCreate3DText, lavkaHelperOnRemove3DText = (function()
local LAVKA_HELPER_SCAN_INTERVAL = 1.00
local LAVKA_HELPER_GRID_INTERVAL = 0.70
local LAVKA_HELPER_BUILD_COLUMNS_PER_FRAME = 2
local LAVKA_HELPER_MIN_MOVE_THRESHOLD = 1.75
local LAVKA_HELPER_DIAGNOSTIC_INTERVAL = 5.0
local LAVKA_HELPER_Z_THRESHOLD = 8.0
local LAVKA_HELPER_BUCKET_SIZE = 20.0
local LAVKA_HELPER_GROUND_OFFSET = 0.035
local LAVKA_HELPER_RAY_UP = 2.50
local LAVKA_HELPER_RAY_DOWN = 2.25
local LAVKA_HELPER_MAX_TRIANGLE_HEIGHT_DELTA = 1.50

-- Direct3D9 world-space renderer. Geometry is generated in GTA world XYZ,
-- while Direct3D performs the view/projection/clipping. Rendering is done in
-- MoonLoader's onD3DPresent event, not from the gameplay logic loop.
local D3DPT_TRIANGLELIST = 4
local D3DFMT_INDEX16 = 101
local D3DFVF_XYZ = 0x002
local D3DFVF_DIFFUSE = 0x040
local LAVKA_HELPER_FVF = D3DFVF_XYZ + D3DFVF_DIFFUSE
local D3DSBT_ALL = 1

local D3DTS_WORLD = 256
local D3DRS_ZENABLE = 7
local D3DRS_ZWRITEENABLE = 14
local D3DRS_ALPHATESTENABLE = 15
local D3DRS_SRCBLEND = 19
local D3DRS_DESTBLEND = 20
local D3DRS_CULLMODE = 22
local D3DRS_ALPHABLENDENABLE = 27
local D3DRS_FOGENABLE = 28
local D3DRS_CLIPPING = 136
local D3DRS_LIGHTING = 137
local D3DRS_COLORWRITEENABLE = 168
local D3DRS_SCISSORTESTENABLE = 174
local D3DRS_SEPARATEALPHABLENDENABLE = 206
local D3DBLEND_SRCALPHA = 5
local D3DBLEND_INVSRCALPHA = 6
local D3DCULL_NONE = 1
local D3DTSS_COLOROP = 1
local D3DTSS_COLORARG1 = 2
local D3DTSS_ALPHAOP = 4
local D3DTSS_ALPHAARG1 = 5
local D3DTOP_DISABLE = 1
local D3DTOP_SELECTARG1 = 2
local D3DTA_DIFFUSE = 0

local D3D_VTBL_CREATE_STATE_BLOCK = 59
local D3D_VTBL_SET_TRANSFORM = 44
local D3D_VTBL_SET_RENDER_STATE = 57
local D3D_VTBL_SET_TEXTURE = 65
local D3D_VTBL_SET_TEXTURE_STAGE_STATE = 67
local D3D_VTBL_DRAW_INDEXED_PRIMITIVE_UP = 84
local D3D_VTBL_SET_FVF = 89
local D3D_VTBL_SET_VERTEX_SHADER = 92
local D3D_VTBL_SET_PIXEL_SHADER = 107
local STATEBLOCK_VTBL_RELEASE = 2
local STATEBLOCK_VTBL_APPLY = 5

local LAVKA_HELPER_MAX_BATCH_VERTICES = 6000
local LAVKA_HELPER_MAX_BATCH_INDICES = 12000

local d3d = {
	cdefReady = false,
	initTried = false,
	available = false,
	error = nil,
	device = nil,
	createStateBlock = nil,
	setTransform = nil,
	setRenderState = nil,
	setTexture = nil,
	setTextureStageState = nil,
	drawIndexedPrimitiveUP = nil,
	setFVF = nil,
	setVertexShader = nil,
	setPixelShader = nil
}

local cache = {
	zones = {},
	vertices = {},
	triangles = {},
	batches = {},
	nextScan = 0,
	nextGridBuild = 0,
	zonesRevision = 0,
	builtRevision = -1,
	lastPlayerX = nil,
	lastPlayerY = nil,
	lastPlayerZ = nil,
	lastRenderRadius = nil,
	lastCellSize = nil,
	groundCache = {},
	groundSourceCache = {},
	groundCacheContext = nil,
	groundCacheCount = 0,
	groundRayMode = nil,
	lastBuildMs = 0,
	gridBuildThread = nil,
	buildSerial = 0,
	buildErrorReported = false,
	enabled = false,
	nextDiagnosticLog = 0,
	renderErrorReported = false,
	d3dUnavailableReported = false,
	allowedCells = 0,
	forbiddenCells = 0,
	groundResolved = 0,
	groundFallback = 0,
	groundFailed = 0,
	relevantZoneCount = 0,
	renderedTriangles = 0,
	drawFailedBatches = 0,
	lastInterior = nil,
	fastRescanUntil = 0
}

local function clearCache()
	cache.buildSerial = (cache.buildSerial or 0) + 1
	cache.gridBuildThread = nil
	cache.zones = {}
	cache.vertices = {}
	cache.triangles = {}
	cache.batches = {}
	cache.nextScan = 0
	cache.nextGridBuild = 0
	cache.zonesRevision = 0
	cache.builtRevision = -1
	cache.lastPlayerX = nil
	cache.lastPlayerY = nil
	cache.lastPlayerZ = nil
	cache.lastRenderRadius = nil
	cache.lastCellSize = nil
	cache.groundCache = {}
	cache.groundSourceCache = {}
	cache.groundCacheContext = nil
	cache.groundCacheCount = 0
	cache.groundRayMode = nil
	cache.lastBuildMs = 0
	cache.buildErrorReported = false
	cache.nextDiagnosticLog = 0
	cache.renderErrorReported = false
	cache.d3dUnavailableReported = false
	cache.allowedCells = 0
	cache.forbiddenCells = 0
	cache.groundResolved = 0
	cache.groundFallback = 0
	cache.groundFailed = 0
	cache.relevantZoneCount = 0
	cache.renderedTriangles = 0
	cache.drawFailedBatches = 0
	cache.lastInterior = nil
	cache.fastRescanUntil = 0
end

local function getCellSize(radius)
	-- Keep the rounded clipped border, but build far fewer cells while walking.
	-- The helper is a placement guide, so sub-meter terrain sampling is not worth
	-- the CPU and native-call cost on every movement rebuild.
	if radius <= 12 then
		return 0.70
	elseif radius <= 22 then
		return 0.95
	elseif radius <= 35 then
		return 1.20
	end
	return 1.50
end

local function zoneSort(a, b)
	if a.x ~= b.x then return a.x < b.x end
	if a.y ~= b.y then return a.y < b.y end
	if a.z ~= b.z then return a.z < b.z end
	if a.radius ~= b.radius then return a.radius < b.radius end
	return a.type < b.type
end

local function zonesEqual(a, b)
	if #a ~= #b then return false end
	for i = 1, #a do
		local x, y = a[i], b[i]
		if x.x ~= y.x or x.y ~= y.y or x.z ~= y.z or x.radius ~= y.radius or x.type ~= y.type then
			return false
		end
	end
	return true
end

-- Server 3D labels are streamed while the player moves. Keep the create/remove
-- events as an authoritative live source and use the SA-MP pool scan as a
-- fallback. This fixes the case where the helper is enabled before any shop
-- labels are streamed and the player later runs into a shop area.
local streamedZoneLabels = {}

lavkaHelperFindNearestStreamedShopZone = function(px, py, pz, maxDistance)
	px, py, pz = tonumber(px), tonumber(py), tonumber(pz)
	maxDistance = tonumber(maxDistance) or 18.0
	if not px or not py or not pz then return nil end
	local best, bestDistance = nil, maxDistance
	for _, zone in pairs(streamedZoneLabels) do
		if type(zone) == "table" and zone.type == "shop" then
			local dx = (tonumber(zone.x) or 0) - px
			local dy = (tonumber(zone.y) or 0) - py
			local dz = (tonumber(zone.z) or 0) - pz
			local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
			if distance <= bestDistance then
				bestDistance = distance
				best = zone
			end
		end
	end
	if best then
		return tonumber(best.x), tonumber(best.y), tonumber(best.z), bestDistance
	end
	return nil
end

local function classifyLavkaZone(text3d, x, y, z)
	if type(text3d) ~= "string" or type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
		return nil
	end
	if text3d:find(u8:decode("Управления товарами.")) then
		return {x = x, y = y, z = z, radius = 5.0, type = "shop"}
	elseif text3d:find(u8:decode("Номер бизнеса")) then
		return {x = x, y = y, z = z - 1.0, radius = 25.0, type = "business"}
	end
	return nil
end

local function onStreamedZoneCreate(textId, text3d, position)
	local id = tonumber(textId)
	if id == nil or type(position) ~= "table" then return end
	local zone = classifyLavkaZone(text3d, tonumber(position.x), tonumber(position.y), tonumber(position.z))
	if zone then
		streamedZoneLabels[id] = zone
		cache.nextScan = 0
		cache.nextGridBuild = 0
		cache.builtRevision = -1
	end
end

local function onStreamedZoneRemove(textId)
	local id = tonumber(textId)
	if id ~= nil and streamedZoneLabels[id] ~= nil then
		streamedZoneLabels[id] = nil
		cache.nextScan = 0
		cache.nextGridBuild = 0
		cache.builtRevision = -1
	end
end

local function scanZones(now)
	local zonesById = {}
	for textId, zone in pairs(streamedZoneLabels) do
		zonesById[textId] = {
			x = zone.x,
			y = zone.y,
			z = zone.z,
			radius = zone.radius,
			type = zone.type
		}
	end

	-- Scan the whole SA-MP 3D-text pool in one pass so a streamed shop/business
	-- label cannot be missed between chunks or reconnect/interior transitions.
	for textId = 0, 2048 do
		if sampIs3dTextDefined(textId) then
			local ok, text3d, _, x, y, z = pcall(sampGet3dTextInfoById, textId)
			if ok then
				local zone = classifyLavkaZone(text3d, x, y, z)
				if zone then
					zonesById[textId] = zone
				end
			end
		end
	end

	local zones = {}
	for _, zone in pairs(zonesById) do
		zones[#zones + 1] = zone
	end

	table.sort(zones, zoneSort)
	if not zonesEqual(cache.zones, zones) then
		cache.zones = zones
		cache.zonesRevision = cache.zonesRevision + 1
		cache.nextGridBuild = 0
	end

	local scanDelay = now < (cache.fastRescanUntil or 0) and 0.35 or LAVKA_HELPER_SCAN_INTERVAL
	cache.nextScan = now + scanDelay
end

local function addZoneToBuckets(buckets, zone)
	local r = zone.radius
	local minX = math.floor((zone.x - r) / LAVKA_HELPER_BUCKET_SIZE)
	local maxX = math.floor((zone.x + r) / LAVKA_HELPER_BUCKET_SIZE)
	local minY = math.floor((zone.y - r) / LAVKA_HELPER_BUCKET_SIZE)
	local maxY = math.floor((zone.y + r) / LAVKA_HELPER_BUCKET_SIZE)
	for bx = minX, maxX do
		local column = buckets[bx]
		if not column then
			column = {}
			buckets[bx] = column
		end
		for by = minY, maxY do
			local bucket = column[by]
			if not bucket then
				bucket = {}
				column[by] = bucket
			end
			bucket[#bucket + 1] = zone
		end
	end
end

local function getBucket(buckets, wx, wy)
	local bx = math.floor(wx / LAVKA_HELPER_BUCKET_SIZE)
	local column = buckets[bx]
	if not column then return nil end
	return column[math.floor(wy / LAVKA_HELPER_BUCKET_SIZE)]
end

local function insideForbidden(x, y, zones)
	if not zones then return false end
	for i = 1, #zones do
		local zone = zones[i]
		local dx = x - zone.x
		local dy = y - zone.y
		if dx * dx + dy * dy <= zone.radius * zone.radius then
			return true
		end
	end
	return false
end

local groundRayCall = nil

local function groundRay7(wx, wy, topZ, bottomZ, includeObjects)
	return processLineOfSight(
		wx, wy, topZ,
		wx, wy, bottomZ,
		true, false, false, includeObjects == true, false, false, false
	)
end

local function groundRay8(wx, wy, topZ, bottomZ, includeObjects)
	return processLineOfSight(
		wx, wy, topZ,
		wx, wy, bottomZ,
		true, false, false, includeObjects == true, false, false, false, false
	)
end

local function extractGroundHit(hit, colPoint)
	if hit == true and type(colPoint) == "table" and type(colPoint.pos) == "table" then
		local z = tonumber(colPoint.pos[3])
		if z and z == z then return z end
	end
	return nil
end

local function castGroundRay(wx, wy, topZ, bottomZ, includeObjects)
	-- MoonLoader 0.26.x documents the 7-flag 0BFF signature. Detect the actual
	-- runtime signature only once. The old code deliberately tried an 8-flag call
	-- inside pcall for EVERY vertex and then retried with 7 flags, multiplying the
	-- cost of thousands of ground tests during movement.
	if groundRayCall then
		local hit, colPoint = groundRayCall(wx, wy, topZ, bottomZ, includeObjects)
		return extractGroundHit(hit, colPoint)
	end

	local ok7, hit7, col7 = pcall(groundRay7, wx, wy, topZ, bottomZ, includeObjects)
	if ok7 then
		groundRayCall = groundRay7
		cache.groundRayMode = 7
		return extractGroundHit(hit7, col7)
	end

	local ok8, hit8, col8 = pcall(groundRay8, wx, wy, topZ, bottomZ, includeObjects)
	if ok8 then
		groundRayCall = groundRay8
		cache.groundRayMode = 8
		return extractGroundHit(hit8, col8)
	end

	cache.groundRayMode = -1
	return nil
end

local function resolveGround(wx, wy, referenceZ, level, cellSize)
	local qx = math.floor(wx * 100 + 0.5)
	local qy = math.floor(wy * 100 + 0.5)
	local row = cache.groundCache[qx]
	if row then
		local z = row[qy]
		if z ~= nil then
			local sourceRow = cache.groundSourceCache[qx]
			return z, sourceRow and sourceRow[qy] == true
		end
	end

	local topZ = referenceZ + LAVKA_HELPER_RAY_UP
	local bottomZ = referenceZ - LAVKA_HELPER_RAY_DOWN
	local z = castGroundRay(wx, wy, topZ, bottomZ, false)
	local fromWorld = true

	if z == nil then
		z = castGroundRay(wx, wy, topZ, bottomZ, true)
		fromWorld = false
	end

	if z == nil then return nil, false end

	z = z + LAVKA_HELPER_GROUND_OFFSET
	if not row then
		row = {}
		cache.groundCache[qx] = row
	end
	row[qy] = z
	local sourceRow = cache.groundSourceCache[qx]
	if not sourceRow then
		sourceRow = {}
		cache.groundSourceCache[qx] = sourceRow
	end
	sourceRow[qy] = fromWorld
	cache.groundCacheCount = cache.groundCacheCount + 1
	return z, fromWorld
end

local function initD3D()
	if d3d.initTried then return d3d.available end
	d3d.initTried = true

	if not d3d.cdefReady then
		local ok, err = pcall(ffi.cdef, [[
			typedef struct { float m[4][4]; } ArzLavkaD3DMatrix;
			typedef struct { float x; float y; float z; unsigned int color; } ArzLavkaD3DVertex;
			typedef int (__stdcall * ArzLavkaCreateStateBlockFn)(void*, int, void**);
			typedef int (__stdcall * ArzLavkaSetTransformFn)(void*, int, const ArzLavkaD3DMatrix*);
			typedef int (__stdcall * ArzLavkaSetRenderStateFn)(void*, int, unsigned int);
			typedef int (__stdcall * ArzLavkaSetTextureFn)(void*, unsigned int, void*);
			typedef int (__stdcall * ArzLavkaSetTextureStageStateFn)(void*, unsigned int, int, unsigned int);
			typedef int (__stdcall * ArzLavkaDrawIndexedPrimitiveUPFn)(void*, int, unsigned int, unsigned int, unsigned int, const void*, int, const void*, unsigned int);
			typedef int (__stdcall * ArzLavkaSetFVFFn)(void*, unsigned int);
			typedef int (__stdcall * ArzLavkaSetVertexShaderFn)(void*, void*);
			typedef int (__stdcall * ArzLavkaSetPixelShaderFn)(void*, void*);
			typedef unsigned long (__stdcall * ArzLavkaComReleaseFn)(void*);
			typedef int (__stdcall * ArzLavkaStateBlockApplyFn)(void*);
		]])
		if not ok then
			d3d.error = "ffi.cdef failed: " .. tostring(err)
			return false
		end
		d3d.cdefReady = true
	end

	local deviceAddress = tonumber(getD3DDevicePtr()) or 0
	if deviceAddress < 0x10000 then
		d3d.error = "getD3DDevicePtr returned invalid pointer"
		return false
	end

	local initOk, initErr = pcall(function()
		d3d.device = ffi.cast("void*", deviceAddress)
		local vtbl = ffi.cast("void***", d3d.device)[0]
		if vtbl == nil or vtbl == ffi.NULL then error("IDirect3DDevice9 vtable is null") end
		d3d.createStateBlock = ffi.cast("ArzLavkaCreateStateBlockFn", vtbl[D3D_VTBL_CREATE_STATE_BLOCK])
		d3d.setTransform = ffi.cast("ArzLavkaSetTransformFn", vtbl[D3D_VTBL_SET_TRANSFORM])
		d3d.setRenderState = ffi.cast("ArzLavkaSetRenderStateFn", vtbl[D3D_VTBL_SET_RENDER_STATE])
		d3d.setTexture = ffi.cast("ArzLavkaSetTextureFn", vtbl[D3D_VTBL_SET_TEXTURE])
		d3d.setTextureStageState = ffi.cast("ArzLavkaSetTextureStageStateFn", vtbl[D3D_VTBL_SET_TEXTURE_STAGE_STATE])
		d3d.drawIndexedPrimitiveUP = ffi.cast("ArzLavkaDrawIndexedPrimitiveUPFn", vtbl[D3D_VTBL_DRAW_INDEXED_PRIMITIVE_UP])
		d3d.setFVF = ffi.cast("ArzLavkaSetFVFFn", vtbl[D3D_VTBL_SET_FVF])
		d3d.setVertexShader = ffi.cast("ArzLavkaSetVertexShaderFn", vtbl[D3D_VTBL_SET_VERTEX_SHADER])
		d3d.setPixelShader = ffi.cast("ArzLavkaSetPixelShaderFn", vtbl[D3D_VTBL_SET_PIXEL_SHADER])
	end)
	if not initOk then
		d3d.error = tostring(initErr)
		return false
	end
	d3d.available = true
	return true
end

local function makeIdentityMatrix()
	local matrix = ffi.new("ArzLavkaD3DMatrix[1]")
	matrix[0].m[0][0] = 1
	matrix[0].m[1][1] = 1
	matrix[0].m[2][2] = 1
	matrix[0].m[3][3] = 1
	return matrix
end

local identityMatrix = nil

function d3d.resetBindings()
	d3d.initTried = false
	d3d.available = false
	d3d.error = nil
	d3d.device = nil
	d3d.createStateBlock = nil
	d3d.setTransform = nil
	d3d.setRenderState = nil
	d3d.setTexture = nil
	d3d.setTextureStageState = nil
	d3d.drawIndexedPrimitiveUP = nil
	d3d.setFVF = nil
	d3d.setVertexShader = nil
	d3d.setPixelShader = nil
	identityMatrix = nil
	cache.d3dUnavailableReported = false
	cache.renderErrorReported = false
end

local function getLavkaHelperColorU32()
	local r = math.max(0, math.min(255, math.floor(tonumber(ini.cfg.lavka_helper_color_r) or 255)))
	local g = math.max(0, math.min(255, math.floor(tonumber(ini.cfg.lavka_helper_color_g) or 45)))
	local b = math.max(0, math.min(255, math.floor(tonumber(ini.cfg.lavka_helper_color_b) or 45)))
	local alphaPercent = math.max(0, math.min(100, tonumber(ini.cfg.lavka_helper_alpha) or 38))
	local a = math.max(0, math.min(255, math.floor(alphaPercent * 255 / 100 + 0.5)))
	return a * 0x1000000 + r * 0x10000 + g * 0x100 + b
end

local function buildBatches(vertices, triangles)
	if #triangles == 0 or not initD3D() then return {} end
	local batches = {}
	local helperColor = getLavkaHelperColorU32()
	local map = {}
	local offsets = {}
	local indices = {}

	local function flush()
		if #indices == 0 then return end
		local vertexCount = #offsets
		local indexCount = #indices
		local v = ffi.new("ArzLavkaD3DVertex[?]", vertexCount)
		local ix = ffi.new("unsigned short[?]", indexCount)
		for i = 1, vertexCount do
			local source = offsets[i]
			v[i - 1].x = vertices[source]
			v[i - 1].y = vertices[source + 1]
			v[i - 1].z = vertices[source + 2]
			v[i - 1].color = helperColor
		end
		for i = 1, indexCount do ix[i - 1] = indices[i] end
		batches[#batches + 1] = {vertices = v, indices = ix, vertexCount = vertexCount, indexCount = indexCount}
	end

	local function reset()
		map = {}
		offsets = {}
		indices = {}
	end

	local function add(source)
		local idx = map[source]
		if idx == nil then
			idx = #offsets
			map[source] = idx
			offsets[#offsets + 1] = source
		end
		indices[#indices + 1] = idx
	end

	for p = 1, #triangles, 3 do
		local a, b, c = triangles[p], triangles[p + 1], triangles[p + 2]
		local need = 0
		if map[a] == nil then need = need + 1 end
		if map[b] == nil and b ~= a then need = need + 1 end
		if map[c] == nil and c ~= a and c ~= b then need = need + 1 end
		if #indices > 0 and (#indices + 3 > LAVKA_HELPER_MAX_BATCH_INDICES or #offsets + need > LAVKA_HELPER_MAX_BATCH_VERTICES) then
			flush()
			reset()
		end
		add(a); add(b); add(c)
	end
	flush()
	return batches
end

local function applyColorToBatches()
	local helperColor = getLavkaHelperColorU32()
	for i = 1, #cache.batches do
		local batch = cache.batches[i]
		if batch and batch.vertices and tonumber(batch.vertexCount) then
			for vertexIndex = 0, batch.vertexCount - 1 do
				batch.vertices[vertexIndex].color = helperColor
			end
		end
	end
end

local function rebuildGrid(playerX, playerY, playerZ, radius, now, buildSerial)
	local buildStarted = os.clock()
	local zonesSnapshot = cache.zones
	local zonesRevisionAtStart = cache.zonesRevision
	local cellSize = getCellSize(radius)
	local minGX = math.floor((playerX - radius) / cellSize) - 1
	local maxGX = math.ceil((playerX + radius) / cellSize) + 1
	local minGY = math.floor((playerY - radius) / cellSize) - 1
	local maxGY = math.ceil((playerY + radius) / cellSize) + 1
	local buckets = {}
	local level = math.floor(playerZ / 5)
	local surfaceBand = math.floor(playerZ / 2.0)
	local groundContext = tostring(level) .. ":" .. tostring(surfaceBand) .. ":" .. string.format("%.2f", cellSize)
	if cache.groundCacheContext ~= groundContext then
		cache.groundCache = {}
		cache.groundSourceCache = {}
		cache.groundCacheCount = 0
		cache.groundCacheContext = groundContext
	end
	local vertices = {}
	local triangles = {}
	local vertexMap = {}
	local fieldCache = {}
	local allowed, forbidden, exactGround, fallbackGround, failedGround, relevant = 0, 0, 0, 0, 0, 0

	-- Use one stable ground level for the local placement overlay.
	-- The old implementation called processLineOfSight for the player and then
	-- again for large numbers of grid vertices while walking. That native-call
	-- burst caused freezes and could provoke native C++ exceptions in the client.
	local referenceZ = playerZ
	local okH, h = pcall(getCharHeightAboveGround, PLAYER_PED)
	if okH and type(h) == "number" and h == h and h >= 0 and h < 10 then
		referenceZ = playerZ - h
	end

	-- Keep a rolling cache large enough to survive normal movement. The previous
	-- 45k hard clear caused a full burst of fresh LOS calls after a few minutes.
	if cache.groundCacheCount > 120000 then
		cache.groundCache = {}
		cache.groundSourceCache = {}
		cache.groundCacheCount = 0
	end

	for i = 1, #zonesSnapshot do
		local zone = zonesSnapshot[i]
		local dx, dy = zone.x - playerX, zone.y - playerY
		local maxDistance = radius + zone.radius + cellSize * 2
		if math.abs(zone.z - playerZ) < LAVKA_HELPER_Z_THRESHOLD and dx * dx + dy * dy <= maxDistance * maxDistance then
			addZoneToBuckets(buckets, zone)
			relevant = relevant + 1
		end
	end

	if relevant == 0 then
		cache.vertices, cache.triangles, cache.batches = {}, {}, {}
		cache.allowedCells, cache.forbiddenCells = 0, 0
		cache.groundResolved, cache.groundFallback, cache.groundFailed = 0, 0, 0
		cache.relevantZoneCount = 0
		cache.builtRevision = zonesRevisionAtStart
		cache.lastPlayerX, cache.lastPlayerY, cache.lastPlayerZ = playerX, playerY, playerZ
		cache.lastRenderRadius, cache.lastCellSize = radius, cellSize
		cache.nextGridBuild = now + LAVKA_HELPER_GRID_INTERVAL
		cache.lastBuildMs = (os.clock() - buildStarted) * 1000.0
		return
	end

	-- Signed field used for a marching-squares style smooth boundary.
	-- field <= 0 means visible red area:
	--   inside player's N-radius AND outside every original 5/25 m forbidden circle.
	local function sampleField(gx, gy)
		local row = fieldCache[gx]
		if row then
			local got = row[gy]
			if got ~= nil then return gx * cellSize, gy * cellSize, got end
		else
			row = {}
			fieldCache[gx] = row
		end

		local wx, wy = gx * cellSize, gy * cellSize
		local pdx, pdy = wx - playerX, wy - playerY
		-- Squared-distance early path avoids sqrt for the overwhelmingly common
		-- samples that are clearly outside the player's radius. We still calculate
		-- the signed distance where clipping/interpolation needs it.
		local field = math.sqrt(pdx * pdx + pdy * pdy) - radius
		local zones = getBucket(buckets, wx, wy)

		if zones then
			for i = 1, #zones do
				local zone = zones[i]
				local zx, zy = wx - zone.x, wy - zone.y
				local blockedField = zone.radius - math.sqrt(zx * zx + zy * zy)
				if blockedField > field then field = blockedField end
			end
		end

		row[gy] = field
		return wx, wy, field
	end

	local function vertexOffsetXY(wx, wy)
		local qx = math.floor(wx * 100 + 0.5)
		local qy = math.floor(wy * 100 + 0.5)
		local row = vertexMap[qx]
		if row then
			local got = row[qy]
			if got then return got end
		else
			row = {}
			vertexMap[qx] = row
		end

		local z = referenceZ + LAVKA_HELPER_GROUND_OFFSET
		fallbackGround = fallbackGround + 1

		local off = #vertices + 1
		vertices[off], vertices[off + 1], vertices[off + 2] = wx, wy, z
		row[qy] = off
		return off
	end

	local function addTriangleXY(ax, ay, bx, by, cx, cy)
		local a = vertexOffsetXY(ax, ay)
		local b = vertexOffsetXY(bx, by)
		local c = vertexOffsetXY(cx, cy)
		if not a or not b or not c then return false end

		local za, zb, zc = vertices[a + 2], vertices[b + 2], vertices[c + 2]
		local minZ = math.min(za, zb, zc)
		local maxZ = math.max(za, zb, zc)
		if maxZ - minZ > LAVKA_HELPER_MAX_TRIANGLE_HEIGHT_DELTA then
			failedGround = failedGround + 1
			return false
		end

		triangles[#triangles + 1] = a
		triangles[#triangles + 1] = b
		triangles[#triangles + 1] = c
		return true
	end

	local function intersect(x1, y1, f1, x2, y2, f2)
		local denom = f1 - f2
		local t = 0.5
		if math.abs(denom) > 0.000001 then t = f1 / denom end
		if t < 0 then t = 0 elseif t > 1 then t = 1 end
		return x1 + (x2 - x1) * t, y1 + (y2 - y1) * t
	end

	-- Clip one triangle against the interpolated field <= 0. This is effectively
	-- marching triangles: boundary points are placed between samples instead of
	-- snapping to whole grid cells, so circles become visibly rounded/smooth.
	local function emitClippedTriangle(ax, ay, af, bx, by, bf, cx, cy, cf)
		local ai, bi, ci = af <= 0, bf <= 0, cf <= 0
		local count = (ai and 1 or 0) + (bi and 1 or 0) + (ci and 1 or 0)
		if count == 0 then return 0 end
		if count == 3 then
			return addTriangleXY(ax, ay, bx, by, cx, cy) and 1 or 0
		end

		if count == 1 then
			if ai then
				local abx, aby = intersect(ax, ay, af, bx, by, bf)
				local acx, acy = intersect(ax, ay, af, cx, cy, cf)
				return addTriangleXY(ax, ay, abx, aby, acx, acy) and 1 or 0
			elseif bi then
				local bcx, bcy = intersect(bx, by, bf, cx, cy, cf)
				local bax, bay = intersect(bx, by, bf, ax, ay, af)
				return addTriangleXY(bx, by, bcx, bcy, bax, bay) and 1 or 0
			else
				local cax, cay = intersect(cx, cy, cf, ax, ay, af)
				local cbx, cby = intersect(cx, cy, cf, bx, by, bf)
				return addTriangleXY(cx, cy, cax, cay, cbx, cby) and 1 or 0
			end
		end

		-- Two inside, one outside -> clipped quad, triangulated as a fan.
		local made = 0
		if ai and bi then
			local bcx, bcy = intersect(bx, by, bf, cx, cy, cf)
			local cax, cay = intersect(cx, cy, cf, ax, ay, af)
			if addTriangleXY(ax, ay, bx, by, bcx, bcy) then made = made + 1 end
			if addTriangleXY(ax, ay, bcx, bcy, cax, cay) then made = made + 1 end
		elseif bi and ci then
			local cax, cay = intersect(cx, cy, cf, ax, ay, af)
			local abx, aby = intersect(ax, ay, af, bx, by, bf)
			if addTriangleXY(bx, by, cx, cy, cax, cay) then made = made + 1 end
			if addTriangleXY(bx, by, cax, cay, abx, aby) then made = made + 1 end
		else
			local abx, aby = intersect(ax, ay, af, bx, by, bf)
			local bcx, bcy = intersect(bx, by, bf, cx, cy, cf)
			if addTriangleXY(cx, cy, ax, ay, abx, aby) then made = made + 1 end
			if addTriangleXY(cx, cy, abx, aby, bcx, bcy) then made = made + 1 end
		end
		return made
	end

	for gx = minGX, maxGX - 1 do
		if buildSerial ~= cache.buildSerial or not lavkaHelperEnabled[0] or menuVisible[0] then
			return false
		end
		if (gx - minGX) > 0 and ((gx - minGX) % LAVKA_HELPER_BUILD_COLUMNS_PER_FRAME) == 0 then
			wait(0)
			if buildSerial ~= cache.buildSerial or not lavkaHelperEnabled[0] or menuVisible[0] then
				return false
			end
		end

		for gy = minGY, maxGY - 1 do
			local ax, ay, af = sampleField(gx, gy)
			local bx, by, bf = sampleField(gx + 1, gy)
			local cx, cy, cf = sampleField(gx + 1, gy + 1)
			local dx, dy, df = sampleField(gx, gy + 1)

			local cellMade = 0
			cellMade = cellMade + emitClippedTriangle(ax, ay, af, bx, by, bf, cx, cy, cf)
			cellMade = cellMade + emitClippedTriangle(ax, ay, af, cx, cy, cf, dx, dy, df)

			if cellMade > 0 then
				allowed = allowed + 1
			else
				local centerX = (ax + cx) * 0.5
				local centerY = (ay + cy) * 0.5
				local pdx, pdy = centerX - playerX, centerY - playerY
				if pdx * pdx + pdy * pdy <= radius * radius then
					if insideForbidden(centerX, centerY, getBucket(buckets, centerX, centerY)) then forbidden = forbidden + 1 end
				end
			end
		end
	end

	if buildSerial ~= cache.buildSerial or not lavkaHelperEnabled[0] or menuVisible[0] then
		return false
	end

	cache.vertices, cache.triangles = vertices, triangles
	cache.batches = buildBatches(vertices, triangles)
	cache.allowedCells, cache.forbiddenCells = allowed, forbidden
	cache.groundResolved, cache.groundFallback, cache.groundFailed = exactGround, fallbackGround, failedGround
	cache.relevantZoneCount = relevant
	cache.builtRevision = zonesRevisionAtStart
	cache.lastPlayerX, cache.lastPlayerY, cache.lastPlayerZ = playerX, playerY, playerZ
	cache.lastRenderRadius, cache.lastCellSize = radius, cellSize
	cache.nextGridBuild = now + LAVKA_HELPER_GRID_INTERVAL
	cache.lastBuildMs = (os.clock() - buildStarted) * 1000.0
	return true
end

local function stateBlockApplyAndRelease(block)
	if block == nil or block == ffi.NULL then return end
	local vtbl = ffi.cast("void***", block)[0]
	if vtbl ~= nil and vtbl ~= ffi.NULL then
		pcall(ffi.cast("ArzLavkaStateBlockApplyFn", vtbl[STATEBLOCK_VTBL_APPLY]), block)
		pcall(ffi.cast("ArzLavkaComReleaseFn", vtbl[STATEBLOCK_VTBL_RELEASE]), block)
	end
end

local function renderD3D()
	if not cache.enabled or not lavkaHelperEnabled[0] or #cache.batches == 0 then
		cache.renderedTriangles = 0
		cache.drawFailedBatches = 0
		return
	end
	if not initD3D() then
		cache.renderedTriangles = 0
		if not cache.d3dUnavailableReported then
			cache.d3dUnavailableReported = true
			print("[ArzMarket][LavkaHelper] Direct3D renderer disabled: " .. tostring(d3d.error))
		end
		return
	end
	if identityMatrix == nil then identityMatrix = makeIdentityMatrix() end

	local stateBlockOut = ffi.new("void*[1]")
	local stateBlock = nil
	local rendered, failed = 0, 0
	local ok, err = xpcall(function()
		local hrState = d3d.createStateBlock(d3d.device, D3DSBT_ALL, stateBlockOut)
		if hrState >= 0 and stateBlockOut[0] ~= nil and stateBlockOut[0] ~= ffi.NULL then stateBlock = stateBlockOut[0] end

		d3d.setVertexShader(d3d.device, nil)
		d3d.setPixelShader(d3d.device, nil)
		d3d.setFVF(d3d.device, LAVKA_HELPER_FVF)
		d3d.setTransform(d3d.device, D3DTS_WORLD, identityMatrix)
		d3d.setTexture(d3d.device, 0, nil)
		d3d.setRenderState(d3d.device, D3DRS_ZENABLE, 1)
		d3d.setRenderState(d3d.device, D3DRS_ZWRITEENABLE, 0)
		d3d.setRenderState(d3d.device, D3DRS_ALPHATESTENABLE, 0)
		d3d.setRenderState(d3d.device, D3DRS_ALPHABLENDENABLE, 1)
		d3d.setRenderState(d3d.device, D3DRS_SRCBLEND, D3DBLEND_SRCALPHA)
		d3d.setRenderState(d3d.device, D3DRS_DESTBLEND, D3DBLEND_INVSRCALPHA)
		d3d.setRenderState(d3d.device, D3DRS_CULLMODE, D3DCULL_NONE)
		d3d.setRenderState(d3d.device, D3DRS_FOGENABLE, 0)
		d3d.setRenderState(d3d.device, D3DRS_CLIPPING, 1)
		d3d.setRenderState(d3d.device, D3DRS_LIGHTING, 0)
		d3d.setRenderState(d3d.device, D3DRS_COLORWRITEENABLE, 0x0F)
		d3d.setRenderState(d3d.device, D3DRS_SCISSORTESTENABLE, 0)
		d3d.setRenderState(d3d.device, D3DRS_SEPARATEALPHABLENDENABLE, 0)
		d3d.setTextureStageState(d3d.device, 0, D3DTSS_COLOROP, D3DTOP_SELECTARG1)
		d3d.setTextureStageState(d3d.device, 0, D3DTSS_COLORARG1, D3DTA_DIFFUSE)
		d3d.setTextureStageState(d3d.device, 0, D3DTSS_ALPHAOP, D3DTOP_SELECTARG1)
		d3d.setTextureStageState(d3d.device, 0, D3DTSS_ALPHAARG1, D3DTA_DIFFUSE)
		d3d.setTextureStageState(d3d.device, 1, D3DTSS_COLOROP, D3DTOP_DISABLE)

		for i = 1, #cache.batches do
			local batch = cache.batches[i]
			local hr = d3d.drawIndexedPrimitiveUP(
				d3d.device,
				D3DPT_TRIANGLELIST,
				0,
				batch.vertexCount,
				math.floor(batch.indexCount / 3),
				batch.indices,
				D3DFMT_INDEX16,
				batch.vertices,
				ffi.sizeof("ArzLavkaD3DVertex")
			)
			if hr >= 0 then rendered = rendered + math.floor(batch.indexCount / 3) else failed = failed + 1 end
		end
	end, debug.traceback)

	stateBlockApplyAndRelease(stateBlock)
	cache.renderedTriangles = rendered
	cache.drawFailedBatches = failed
	if not ok and not cache.renderErrorReported then
		cache.renderErrorReported = true
		print("[ArzMarket][LavkaHelper] Direct3D render error: " .. tostring(err))
	end
end

local function logDiagnostics(now)
	if now >= cache.nextDiagnosticLog then
		cache.nextDiagnosticLog = now + LAVKA_HELPER_DIAGNOSTIC_INTERVAL
		print(string.format(
			"[LavkaHelper] renderer=D3D9-SMOOTH-PERF d3d=%s zones=%d relevant=%d radius=%.2f cells=%d forbidden=%d vertices=%d triangles=%d batches=%d rendered=%d drawFailed=%d groundExact=%d groundFallback=%d groundFailed=%d groundCache=%d rayMode=%s buildMs=%.2f",
			d3d.available and "ok" or (d3d.initTried and "off" or "pending"),
			#cache.zones,
			cache.relevantZoneCount,
			tonumber(cache.lastRenderRadius) or 0,
			cache.allowedCells,
			cache.forbiddenCells,
			math.floor(#cache.vertices / 3),
			math.floor(#cache.triangles / 3),
			#cache.batches,
			cache.renderedTriangles,
			cache.drawFailedBatches,
			cache.groundResolved,
			cache.groundFallback,
			cache.groundFailed,
			cache.groundCacheCount,
			tostring(cache.groundRayMode or "pending"),
			tonumber(cache.lastBuildMs) or 0
		))
	end
end

local function isLavkaHelperPlayerReady()
	if not isSampAvailable() or not doesCharExist(PLAYER_PED) then
		return false
	end
	if type(sampGetGamestate) == "function" then
		local okState, gameState = pcall(sampGetGamestate)
		if okState and tonumber(gameState) and tonumber(gameState) ~= 3 then
			return false
		end
	end
	if type(sampIsLocalPlayerSpawned) == "function" then
		local okSpawned, spawned = pcall(sampIsLocalPlayerSpawned)
		if okSpawned then
			return spawned == true
		end
	end
	return true
end

local function updateImpl()
	if not lavkaHelperEnabled[0] then
		if cache.enabled or #cache.vertices > 0 or #cache.triangles > 0 or #cache.batches > 0 then
			clearCache()
			cache.enabled = false
		end
		LAVKA_HELPER_RECONNECT.pending = false
		return
	end

	if LAVKA_HELPER_RECONNECT.awaitingAccept then
		return
	end

	-- The world-space helper is hidden while a Lua window is active.
	-- Pausing scan/mesh rebuild here removes expensive LOS/grid work while the
	-- user is resizing or interacting with it. Cache is preserved.
	if menuVisible[0] or ARZ_SPECIAL_UI.visible[0] then
		return
	end

	if not isSampAvailable() or not doesCharExist(PLAYER_PED) then
		if cache.enabled then
			clearCache()
			cache.enabled = false
		end
		return
	end

	if LAVKA_HELPER_RECONNECT.pending and not isLavkaHelperPlayerReady() then
		return
	end

	local now = getGameTimer() * 0.001

	if LAVKA_HELPER_RECONNECT.pending then
		clearCache()
		d3d.resetBindings()
		cache.enabled = true
		cache.fastRescanUntil = now + 8.0
		cache.nextScan = 0
		cache.nextGridBuild = 0
		cache.builtRevision = -1
		initD3D()
		LAVKA_HELPER_RECONNECT.pending = false
	end

	local currentInterior = 0
	local interiorOk, interiorValue = pcall(getCharActiveInterior, PLAYER_PED)
	if interiorOk and tonumber(interiorValue) then
		currentInterior = tonumber(interiorValue)
	end

	if cache.lastInterior == nil then
		cache.lastInterior = currentInterior
	elseif currentInterior ~= cache.lastInterior then
		local previousInterior = cache.lastInterior
		cache.lastInterior = currentInterior
		cache.buildSerial = (cache.buildSerial or 0) + 1
		cache.gridBuildThread = nil
		cache.vertices, cache.triangles, cache.batches = {}, {}, {}
		cache.lastPlayerX, cache.lastPlayerY, cache.lastPlayerZ = nil, nil, nil
		cache.builtRevision = -1
		cache.nextScan = 0
		cache.nextGridBuild = 0

		if previousInterior ~= 0 and currentInterior == 0 then
			-- Exterior 3D labels can arrive a little later than the player itself.
			-- Retry pool scans quickly and rebind D3D after the interior transition.
			cache.fastRescanUntil = now + 8.0
			d3d.resetBindings()
		else
			cache.fastRescanUntil = 0
		end
	end

	if not cache.enabled then
		clearCache()
		cache.enabled = true
		initD3D()
	end
	local playerX, playerY, playerZ = getCharCoordinates(PLAYER_PED)
	if now >= cache.nextScan then scanZones(now) end
	local radius = math.max(5, math.min(50, tonumber(ini.cfg.renderLavkaRadius) or 20))
	local cellSize = getCellSize(radius)
	local moveThreshold = math.max(LAVKA_HELPER_MIN_MOVE_THRESHOLD, cellSize * 1.75)
	local moved = cache.lastPlayerX == nil
	if not moved then
		local dx, dy, dz = playerX - cache.lastPlayerX, playerY - cache.lastPlayerY, playerZ - cache.lastPlayerZ
		moved = dx * dx + dy * dy >= moveThreshold * moveThreshold or math.abs(dz) >= 0.85
	end
	local stale = cache.builtRevision ~= cache.zonesRevision or cache.lastRenderRadius ~= radius or cache.lastCellSize ~= cellSize or moved
	if stale and now >= cache.nextGridBuild and cache.gridBuildThread == nil then
		cache.buildSerial = (cache.buildSerial or 0) + 1
		local buildSerial = cache.buildSerial
		local buildX, buildY, buildZ, buildRadius, buildNow = playerX, playerY, playerZ, radius, now
		cache.nextGridBuild = now + LAVKA_HELPER_GRID_INTERVAL
		cache.gridBuildThread = lua_thread.create(function()
			local ok, err = xpcall(function()
				rebuildGrid(buildX, buildY, buildZ, buildRadius, buildNow, buildSerial)
			end, debug.traceback)
			if buildSerial == cache.buildSerial then
				cache.gridBuildThread = nil
			end
			if not ok and not cache.buildErrorReported then
				cache.buildErrorReported = true
				print("[ArzMarket][LavkaHelper] async grid build error: " .. tostring(err))
			end
		end)
	end
	logDiagnostics(now)
end

local function invalidateImpl(fullReset)
	if fullReset then
		streamedZoneLabels = {}
		clearCache()
		cache.enabled = false
		groundRayCall = nil
		d3d.resetBindings()
		return
	end

	cache.lastRenderRadius = nil
	cache.lastCellSize = nil
	cache.nextGridBuild = 0
end

lavkaHelperApplyVisualSettings = function()
	applyColorToBatches()
end

lavkaHelperHandleNetworkPacket = function(packetId)
	packetId = tonumber(packetId) or -1
	if packetId == 32 or packetId == 33 then
		LAVKA_HELPER_RECONNECT.lastPacket = packetId
		LAVKA_HELPER_RECONNECT.awaitingAccept = lavkaHelperEnabled[0] == true
		LAVKA_HELPER_RECONNECT.pending = false
		invalidateImpl(true)
	elseif packetId == 34 then
		LAVKA_HELPER_RECONNECT.lastPacket = packetId
		LAVKA_HELPER_RECONNECT.awaitingAccept = false
		LAVKA_HELPER_RECONNECT.pending = lavkaHelperEnabled[0] == true
		invalidateImpl(true)
	end
end

-- Direct drawing belongs in the D3D Present hook. MoonLoader explicitly exposes
-- this event for DirectX drawing, while the main loop is kept for scanning and
-- mesh rebuilding only.
addEventHandler("onD3DPresent", function()
	if cache.enabled and lavkaHelperEnabled[0] and not menuVisible[0] then
		renderD3D()
	elseif menuVisible[0] then
		cache.renderedTriangles = 0
		cache.drawFailedBatches = 0
	end
end)

return updateImpl, invalidateImpl, onStreamedZoneCreate, onStreamedZoneRemove
end)()

function setLavkaHelperEnabled(enabled, reason, persist)
	enabled = enabled == true
	local changed = lavkaHelperEnabled[0] ~= enabled
	lavkaHelperEnabled[0] = enabled
	ini.cfg.lavka_helper = enabled
	LAVKA_HELPER_RECONNECT.pending = false
	LAVKA_HELPER_RECONNECT.awaitingAccept = false

	if invalidateLavkaHelperGrid then
		invalidateLavkaHelperGrid(true)
	end

	if not enabled then
		LAVKA_HELPER_UI.settingsOpen = false
	end

	if persist ~= false then
		save_all()
	end

	return changed
end

function lavkaHelperResetOwnShopAutoDisable(reason)
	local state = LAVKA_HELPER_OWN_SHOP
	state.active = false
	state.armed = false
	state.x = nil
	state.y = nil
	state.z = nil
	state.placedAt = 0
	state.leaveSince = 0
	state.anchorRefined = false
	state.serial = (tonumber(state.serial) or 0) + 1
	state.lastReason = tostring(reason or "reset")
end

function lavkaHelperArmOwnShopAutoDisable()
	local state = LAVKA_HELPER_OWN_SHOP
	local ok, x, y, z = pcall(getCharCoordinates, PLAYER_PED)
	if not ok or tonumber(x) == nil or tonumber(y) == nil or tonumber(z) == nil then
		lavkaHelperResetOwnShopAutoDisable("place_no_coords")
		return false
	end
	state.active = true
	state.armed = lavkaHelperAutoDisable[0] == true and lavkaHelperEnabled[0] == true
	state.x = tonumber(x)
	state.y = tonumber(y)
	state.z = tonumber(z)
	state.placedAt = os.clock()
	state.leaveSince = 0
	state.anchorRefined = false
	state.serial = (tonumber(state.serial) or 0) + 1
	state.lastReason = "placed"
	return true
end

function lavkaHelperUpdateOwnShopAutoDisable()
	local state = LAVKA_HELPER_OWN_SHOP
	if not state.active or not state.armed or not lavkaHelperEnabled[0] then
		return
	end
	if context.getActiveLavkaId() == -1 then
		lavkaHelperResetOwnShopAutoDisable("shop_not_active")
		return
	end
	if os.clock() - (tonumber(state.placedAt) or 0) < 2.0 then
		return
	end
	local ok, x, y, z = pcall(getCharCoordinates, PLAYER_PED)
	if not ok then return end
	x, y, z = tonumber(x), tonumber(y), tonumber(z)
	if not x or not y or not z or not state.x or not state.y or not state.z then return end
	if not state.anchorRefined and type(lavkaHelperFindNearestStreamedShopZone) == "function" then
		local shopX, shopY, shopZ = lavkaHelperFindNearestStreamedShopZone(state.x, state.y, state.z, 18.0)
		if shopX and shopY and shopZ then
			state.x, state.y, state.z = shopX, shopY, shopZ
			state.anchorRefined = true
		end
	end
	local dx, dy, dz = x - state.x, y - state.y, z - state.z
	local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
	if distance >= LAVKA_HELPER_OWN_SHOP_LEAVE_DISTANCE then
		if state.leaveSince == 0 then
			state.leaveSince = os.clock()
			return
		end
		if os.clock() - state.leaveSince >= LAVKA_HELPER_OWN_SHOP_LEAVE_CONFIRM then
			state.armed = false
			setLavkaHelperEnabled(false, "auto_leave_own_shop", true)
			sendNotify(u8:decode("Помощник установки лавки выключен: вы отошли от своей лавки."))
		end
	else
		state.leaveSince = 0
	end
end



-- Entity visibility helpers. Player removal is visual-only: the SA-MP player
-- pool, WORLDPLAYERADD/WORLDPLAYERREMOVE and sync packets are never blocked.
-- Vehicles keep the legacy local stream removal implementation.
function modificationState.hideCurrentPlayersVisual()
	if type(getAllChars) ~= "function" or type(setCharVisible) ~= "function" or type(sampGetPlayerIdByCharHandle) ~= "function" then
		return 0
	end

	local okList, chars = pcall(getAllChars)
	if not okList or type(chars) ~= "table" then
		return 0
	end

	local hidden = 0
	for _, ped in pairs(chars) do
		if ped ~= PLAYER_PED and doesCharExist(ped) then
			local okId, found, playerId = pcall(sampGetPlayerIdByCharHandle, ped)
			playerId = tonumber(playerId)
			if okId and found and playerId ~= nil then
				local okVisible = pcall(setCharVisible, ped, false)
				if okVisible then
					modificationState.playerVisualHidden[playerId] = true
					hidden = hidden + 1
				end
			end
		end
	end

	return hidden
end

function modificationState.restoreHiddenPlayersVisual()
	if type(setCharVisible) ~= "function" or type(sampGetCharHandleBySampPlayerId) ~= "function" then
		modificationState.playerVisualHidden = {}
		return 0
	end

	local restored = 0
	for playerId in pairs(modificationState.playerVisualHidden) do
		local okHandle, found, ped = pcall(sampGetCharHandleBySampPlayerId, playerId)
		if okHandle and found and ped and doesCharExist(ped) then
			if pcall(setCharVisible, ped, true) then
				restored = restored + 1
			end
		end
		modificationState.playerVisualHidden[playerId] = nil
	end

	return restored
end

function modificationState.updatePlayerVisibility(force)
	if not modificationState.isRemovePlayersActive() then
		if next(modificationState.playerVisualHidden) ~= nil then
			modificationState.restoreHiddenPlayersVisual()
		end
		return
	end

	local now = getGameTimer()
	if force ~= true and now < (tonumber(modificationState.playerVisibilityNextUpdate) or 0) then
		return
	end

	-- Re-apply periodically so newly streamed players are hidden without
	-- suppressing their WORLDPLAYERADD or synchronization packets.
	modificationState.playerVisibilityNextUpdate = now + 100
	modificationState.hideCurrentPlayersVisual()
end

-- Legacy cache helpers below are retained for vehicle removal compatibility.
-- Player-side RPC emulation is intentionally no longer called.
function modificationState.cachePlayerStreamIn(playerId, team, model, position, rotation, color, fightingStyle)
	if type(playerId) ~= "number" or position == nil then
		return
	end

	local okX, px = pcall(function() return tonumber(position.x) end)
	local okY, py = pcall(function() return tonumber(position.y) end)
	local okZ, pz = pcall(function() return tonumber(position.z) end)

	if not okX or not okY or not okZ or px == nil or py == nil or pz == nil then
		return
	end

	modificationState.playerStreamCache[playerId] = {
		team = tonumber(team) or 0,
		model = tonumber(model) or 0,
		x = px,
		y = py,
		z = pz,
		rotation = tonumber(rotation) or 0,
		color = tonumber(color) or -1,
		fightingStyle = tonumber(fightingStyle) or 0
	}
end

function modificationState.cacheVehicleStreamIn(vehicleId, data)
	if type(vehicleId) ~= "number" or type(data) ~= "table" or data.position == nil then
		return
	end

	local okX, px = pcall(function() return tonumber(data.position.x) end)
	local okY, py = pcall(function() return tonumber(data.position.y) end)
	local okZ, pz = pcall(function() return tonumber(data.position.z) end)

	if not okX or not okY or not okZ or px == nil or py == nil or pz == nil then
		return
	end

	local mods = {}
	for i = 1, 14 do
		mods[i] = tonumber(data.modSlots and data.modSlots[i]) or 0
	end

	modificationState.vehicleStreamCache[vehicleId] = {
		type = tonumber(data.type) or 400,
		x = px,
		y = py,
		z = pz,
		rotation = tonumber(data.rotation) or 0,
		bodyColor1 = tonumber(data.bodyColor1) or 0,
		bodyColor2 = tonumber(data.bodyColor2) or 0,
		health = tonumber(data.health) or 1000,
		interiorId = tonumber(data.interiorId) or 0,
		doorDamageStatus = tonumber(data.doorDamageStatus) or 0,
		panelDamageStatus = tonumber(data.panelDamageStatus) or 0,
		lightDamageStatus = tonumber(data.lightDamageStatus) or 0,
		tireDamageStatus = tonumber(data.tireDamageStatus) or 0,
		addSiren = tonumber(data.addSiren) or 0,
		modSlots = mods,
		paintJob = tonumber(data.paintJob) or 0,
		interiorColor1 = tonumber(data.interiorColor1) or 0,
		interiorColor2 = tonumber(data.interiorColor2) or 0
	}
end

function modificationState.snapshotExistingPlayers()
	if type(getAllChars) ~= "function" or type(sampGetPlayerIdByCharHandle) ~= "function" then
		return 0
	end

	local okList, chars = pcall(getAllChars)
	if not okList or type(chars) ~= "table" then
		return 0
	end

	local captured = 0
	for _, ped in pairs(chars) do
		if ped ~= PLAYER_PED and doesCharExist(ped) then
			local okId, found, playerId = pcall(sampGetPlayerIdByCharHandle, ped)
			playerId = tonumber(playerId)
			if okId and found and playerId and modificationState.playerStreamCache[playerId] == nil then
				local okPos, x, y, z = pcall(getCharCoordinates, ped)
				if okPos and tonumber(x) and tonumber(y) and tonumber(z) then
					local okModel, model = pcall(getCharModel, ped)
					local okHeading, heading = pcall(getCharHeading, ped)
					local okColor, color = pcall(sampGetPlayerColor, playerId)

					modificationState.playerStreamCache[playerId] = {
						team = 0,
						model = okModel and tonumber(model) or 0,
						x = tonumber(x),
						y = tonumber(y),
						z = tonumber(z),
						rotation = okHeading and tonumber(heading) or 0,
						color = okColor and tonumber(color) or -1,
						fightingStyle = 0,
						bootstrap = true
					}
					captured = captured + 1
				end
			end
		end
	end

	return captured
end

function modificationState.getCurrentPlayerVehicleId()
    if type(isCharInAnyCar) ~= "function"
        or type(getCarCharIsUsing) ~= "function"
        or type(sampGetVehicleIdByCarHandle) ~= "function" then
        return nil
    end

    local okInCar, inCar = pcall(isCharInAnyCar, PLAYER_PED)
    if not okInCar or not inCar then
        return nil
    end

    local okCar, car = pcall(getCarCharIsUsing, PLAYER_PED)
    if not okCar or not car then
        return nil
    end

    local okId, found, vehicleId = pcall(sampGetVehicleIdByCarHandle, car)
    vehicleId = tonumber(vehicleId)

    if not okId or not found or vehicleId == nil then
        return nil
    end

    return vehicleId
end

function modificationState.protectCurrentPlayerVehicle()
    local vehicleId = modificationState.getCurrentPlayerVehicleId()

    if vehicleId ~= nil then
        modificationState.vehicleStreamCache[vehicleId] = nil
    end

    return vehicleId
end

function modificationState.snapshotExistingVehicles()
	if type(getAllVehicles) ~= "function" or type(sampGetVehicleIdByCarHandle) ~= "function" then
		return 0
	end

	modificationState.protectCurrentPlayerVehicle()

	local ownVehicle = nil
	if type(isCharInAnyCar) == "function" and isCharInAnyCar(PLAYER_PED) and type(getCarCharIsUsing) == "function" then
		local ownOk, own = pcall(getCarCharIsUsing, PLAYER_PED)
		if ownOk then ownVehicle = own end
	end

	local okList, vehicles = pcall(getAllVehicles)
	if not okList or type(vehicles) ~= "table" then
		return 0
	end

	local currentInterior = 0
	local interiorOk, interiorValue = pcall(getCharActiveInterior, PLAYER_PED)
	if interiorOk and tonumber(interiorValue) then currentInterior = tonumber(interiorValue) end

	local captured = 0
	for _, vehicle in pairs(vehicles) do
		if vehicle ~= ownVehicle and doesVehicleExist(vehicle) then
			local okId, found, vehicleId = pcall(sampGetVehicleIdByCarHandle, vehicle)
			vehicleId = tonumber(vehicleId)
			if okId and found and vehicleId and modificationState.vehicleStreamCache[vehicleId] == nil then
				local okPos, x, y, z = pcall(getCarCoordinates, vehicle)
				if okPos and tonumber(x) and tonumber(y) and tonumber(z) then
					local okModel, model = pcall(getCarModel, vehicle)
					local okHeading, heading = pcall(getCarHeading, vehicle)
					local okColors, color1, color2 = pcall(getCarColours, vehicle)
					local okHealth, health = pcall(getCarHealth, vehicle)
					local mods = {}

					for slot = 0, 13 do
						local okMod, modModel = pcall(getCurrentCarMod, vehicle, slot)
						modModel = okMod and tonumber(modModel) or 0
						mods[slot + 1] = modModel and modModel >= 1000 and modModel <= 1255 and (modModel - 1000) or 0
					end

					local okPaint, paintJob = pcall(getCurrentVehiclePaintjob, vehicle)
					paintJob = okPaint and tonumber(paintJob) or 0
					if paintJob < 0 then paintJob = 0 end

					modificationState.vehicleStreamCache[vehicleId] = {
						type = okModel and tonumber(model) or 400,
						x = tonumber(x),
						y = tonumber(y),
						z = tonumber(z),
						rotation = okHeading and tonumber(heading) or 0,
						bodyColor1 = okColors and tonumber(color1) or 0,
						bodyColor2 = okColors and tonumber(color2) or 0,
						health = okHealth and tonumber(health) or 1000,
						interiorId = currentInterior,
						doorDamageStatus = 0,
						panelDamageStatus = 0,
						lightDamageStatus = 0,
						tireDamageStatus = 0,
						addSiren = 0,
						modSlots = mods,
						paintJob = paintJob,
						interiorColor1 = 0,
						interiorColor2 = 0,
						bootstrap = true
					}
					captured = captured + 1
				end
			end
		end
	end

	return captured
end

function modificationState.emulatePlayerStreamOut(playerId)
	local bs = raknetNewBitStream()
	if not bs then
		return false
	end

	raknetBitStreamWriteInt16(bs, playerId)
	modificationState.emulatingPlayerRemove = true
	local ok, err = pcall(raknetEmulRpcReceiveBitStream, 163, bs)
	modificationState.emulatingPlayerRemove = false
	pcall(raknetDeleteBitStream, bs)

	if not ok then
		print("[ArzMarket][EntityRemoval] player remove RPC failed: " .. tostring(err))
	end

	return ok
end

function modificationState.emulateVehicleStreamOut(vehicleId)
	local bs = raknetNewBitStream()
	if not bs then
		return false
	end

	raknetBitStreamWriteInt16(bs, vehicleId)
	modificationState.emulatingVehicleRemove = true
	local ok, err = pcall(raknetEmulRpcReceiveBitStream, 165, bs)
	modificationState.emulatingVehicleRemove = false
	pcall(raknetDeleteBitStream, bs)

	if not ok then
		print("[ArzMarket][EntityRemoval] vehicle remove RPC failed: " .. tostring(err))
	end

	return ok
end

function modificationState.emulatePlayerStreamIn(playerId, data)
	if type(data) ~= "table" then
		return false
	end

	local bs = raknetNewBitStream()
	if not bs then
		return false
	end

	raknetBitStreamWriteInt16(bs, playerId)
	raknetBitStreamWriteInt8(bs, data.team)
	raknetBitStreamWriteInt32(bs, data.model)
	raknetBitStreamWriteFloat(bs, data.x)
	raknetBitStreamWriteFloat(bs, data.y)
	raknetBitStreamWriteFloat(bs, data.z)
	raknetBitStreamWriteFloat(bs, data.rotation)
	raknetBitStreamWriteInt32(bs, data.color)
	raknetBitStreamWriteInt8(bs, data.fightingStyle)

	modificationState.emulatingPlayerAdd = true
	local ok, err = pcall(raknetEmulRpcReceiveBitStream, 32, bs)
	modificationState.emulatingPlayerAdd = false
	pcall(raknetDeleteBitStream, bs)

	if not ok then
		print("[ArzMarket][EntityRemoval] player add RPC failed: " .. tostring(err))
	end

	return ok
end

function modificationState.emulateVehicleStreamIn(vehicleId, data)
	if type(data) ~= "table" then
		return false
	end

	local bs = raknetNewBitStream()
	if not bs then
		return false
	end

	raknetBitStreamWriteInt16(bs, vehicleId)
	raknetBitStreamWriteInt32(bs, data.type)
	raknetBitStreamWriteFloat(bs, data.x)
	raknetBitStreamWriteFloat(bs, data.y)
	raknetBitStreamWriteFloat(bs, data.z)
	raknetBitStreamWriteFloat(bs, data.rotation)
	raknetBitStreamWriteInt8(bs, data.bodyColor1)
	raknetBitStreamWriteInt8(bs, data.bodyColor2)
	raknetBitStreamWriteFloat(bs, data.health)
	raknetBitStreamWriteInt8(bs, data.interiorId)
	raknetBitStreamWriteInt32(bs, data.doorDamageStatus)
	raknetBitStreamWriteInt32(bs, data.panelDamageStatus)
	raknetBitStreamWriteInt8(bs, data.lightDamageStatus)
	raknetBitStreamWriteInt8(bs, data.tireDamageStatus)
	raknetBitStreamWriteInt8(bs, data.addSiren)

	for i = 1, 14 do
		raknetBitStreamWriteInt8(bs, tonumber(data.modSlots and data.modSlots[i]) or 0)
	end

	raknetBitStreamWriteInt8(bs, data.paintJob)
	raknetBitStreamWriteInt32(bs, data.interiorColor1)
	raknetBitStreamWriteInt32(bs, data.interiorColor2)

	modificationState.emulatingVehicleAdd = true
	local ok, err = pcall(raknetEmulRpcReceiveBitStream, 164, bs)
	modificationState.emulatingVehicleAdd = false
	pcall(raknetDeleteBitStream, bs)

	if not ok then
		print("[ArzMarket][EntityRemoval] vehicle add RPC failed: " .. tostring(err))
	end

	return ok
end

function modificationState.removeCachedPlayersNow()
	local removed = 0
	for playerId in pairs(modificationState.playerStreamCache) do
		if modificationState.emulatePlayerStreamOut(playerId) then
			removed = removed + 1
		end
	end
	print("[ArzMarket][EntityRemoval] players removed locally: " .. tostring(removed))
end

function modificationState.removeCachedVehiclesNow()
	local currentVehicleId = modificationState.protectCurrentPlayerVehicle()
	local removed = 0

	for vehicleId in pairs(modificationState.vehicleStreamCache) do
		if vehicleId ~= currentVehicleId and modificationState.emulateVehicleStreamOut(vehicleId) then
			removed = removed + 1
		end
	end

	print("[ArzMarket][EntityRemoval] vehicles removed locally: " .. tostring(removed))
end

function modificationState.restoreCachedPlayersNow()
	local restored = 0
	for playerId, data in pairs(modificationState.playerStreamCache) do
		if modificationState.emulatePlayerStreamIn(playerId, data) then
			restored = restored + 1
		end
	end
	print("[ArzMarket][EntityRemoval] players restored locally: " .. tostring(restored))
end

function modificationState.restoreCachedVehiclesNow()
	local currentVehicleId = modificationState.protectCurrentPlayerVehicle()
	local restored = 0

	for vehicleId, data in pairs(modificationState.vehicleStreamCache) do
		if vehicleId ~= currentVehicleId and modificationState.emulateVehicleStreamIn(vehicleId, data) then
			restored = restored + 1
		end
	end

	print("[ArzMarket][EntityRemoval] vehicles restored locally: " .. tostring(restored))
end

function modificationState.saveEntityReloadCache()
	if not isSampAvailable() then
		return false
	end

	modificationState.protectCurrentPlayerVehicle()

	-- Player removal is visual-only, so no player RPC reconstruction data is persisted.
	local players = {}
	local vehicles = {}
	for vehicleId, data in pairs(modificationState.vehicleStreamCache) do
		vehicles[tostring(vehicleId)] = data
	end

	local serverIp = select(1, sampGetCurrentServerAddress())
	return writeJsonFile({
		timestamp = os.time(),
		serverIp = tostring(serverIp or ""),
		players = players,
		vehicles = vehicles
	}, modificationState.entityReloadCachePath)
end

function modificationState.clearEntityReloadCache()
	if doesFileExist(modificationState.entityReloadCachePath) then
		pcall(os.remove, modificationState.entityReloadCachePath)
	end
end

function modificationState.loadEntityReloadCache()
	if not doesFileExist(modificationState.entityReloadCachePath) or not isSampAvailable() then
		return false
	end

	local saved = readJsonFile(modificationState.entityReloadCachePath, {})
	modificationState.clearEntityReloadCache()

	if type(saved) ~= "table" or type(saved.timestamp) ~= "number" or os.time() - saved.timestamp > 12 then
		return false
	end

	local serverIp = select(1, sampGetCurrentServerAddress())
	if tostring(saved.serverIp or "") ~= tostring(serverIp or "") then
		return false
	end

	-- Ignore player cache written by old entity-removal builds. Players now stay
	-- in the real SA-MP player pool and are only made invisible locally.
	modificationState.playerStreamCache = {}

	if type(saved.vehicles) == "table" then
		for vehicleId, data in pairs(saved.vehicles) do
			local id = tonumber(vehicleId)
			if id and type(data) == "table" then
				modificationState.vehicleStreamCache[id] = data
			end
		end
	end

	modificationState.protectCurrentPlayerVehicle()

	return next(modificationState.playerStreamCache) ~= nil or next(modificationState.vehicleStreamCache) ~= nil
end

function modificationState.prepareEntityRemovalForTerminate(quitGame)
	if quitGame then
		modificationState.clearEntityReloadCache()
		return
	end

	modificationState.protectCurrentPlayerVehicle()

	-- AutoFPS uses the same classic one-shot remover semantics as players:
	-- it never reconstructs entities on recovery/reload. Keep the old cache/restore
	-- behaviour only for the explicit manual remove-vehicles mode.
	local manualVehiclesActive = modificationState.removeVehicles[0] == true

	if manualVehiclesActive then
		pcall(modificationState.saveEntityReloadCache)
	else
		pcall(modificationState.clearEntityReloadCache)
	end

	-- Players and AutoFPS-owned vehicles return only after a natural SA-MP restream.
	if manualVehiclesActive then
		modificationState.restoreCachedVehiclesNow()
	end
end

function modificationState.isRemovePlayersActive()
	return modificationState.removePlayers[0] or modificationState.autoFpsActive
end

function modificationState.isRemoveVehiclesActive()
	return modificationState.removeVehicles[0] or modificationState.autoFpsActive
end

function modificationState.setRemovePlayers(enabled, showNotification)
	local newState = enabled == true
	if modificationState.removePlayers[0] == newState then
		return
	end

	local effectiveBefore = modificationState.isRemovePlayersActive()
	modificationState.removePlayers[0] = newState
	ini.cfg.mod_remove_players = newState
	save_all()

	local effectiveAfter = modificationState.isRemovePlayersActive()
	if effectiveBefore ~= effectiveAfter and effectiveAfter then
		-- Classic Player Remover behaviour: remove currently streamed players once.
		-- Future WORLDPLAYERADD events are blocked by onPlayerStreamIn below.
		-- Disabling the mode does NOT reconstruct players; they return naturally
		-- after an interior change, respawn, leaving/re-entering stream range or reconnect.
		modificationState.playerStreamCache = {}
		modificationState.snapshotExistingPlayers()
		modificationState.removeCachedPlayersNow()
	end

	if showNotification then
		sendNotify(newState and u8:decode("Полное удаление других игроков включено.") or u8:decode("Полное удаление других игроков выключено."))
	end
end

function modificationState.setRemoveVehicles(enabled, showNotification)
	local newState = enabled == true
	if modificationState.removeVehicles[0] == newState then
		return
	end

	local effectiveBefore = modificationState.isRemoveVehiclesActive()
	modificationState.removeVehicles[0] = newState
	ini.cfg.mod_remove_vehicles = newState
	save_all()

	local effectiveAfter = modificationState.isRemoveVehiclesActive()
	if effectiveBefore ~= effectiveAfter then
		if effectiveAfter then
			modificationState.snapshotExistingVehicles()
			modificationState.removeCachedVehiclesNow()
		else
			modificationState.restoreCachedVehiclesNow()
		end
	end

	if showNotification then
		sendNotify(newState and u8:decode("Полное удаление транспорта включено.") or u8:decode("Полное удаление транспорта выключено."))
	end
end

function modificationState.getAutoFpsPlayerCount()
	if isSampAvailable() and type(sampGetPlayerCount) == "function" then
		local ok, count = pcall(sampGetPlayerCount, false)
		count = ok and tonumber(count) or nil
		if count and count >= 0 then
			return count
		end
	end

	return nil
end

function modificationState.logAutoFps(eventName, reason)
	print(string.format(
		"[AutoFPS]\nevent=%s\nplayers=%s\nplayersThreshold=%d\nfps=%.1f\nfpsThreshold=%d\nreason=%s\nactive=%s",
		tostring(eventName or "state"),
		modificationState.autoFpsPlayerCountValid and tostring(modificationState.autoFpsLastPlayerCount) or "unavailable",
		math.max(1, tonumber(modificationState.autoFpsPlayersThreshold[0]) or 80),
		tonumber(modificationState.autoFpsCurrent) or 0,
		math.max(15, tonumber(modificationState.autoFpsThreshold[0]) or 45),
		tostring(reason or modificationState.autoFpsReason or "none"),
		tostring(modificationState.autoFpsActive == true)
	))
end

function modificationState.setAutoFpsActive(enabled, reason)
	local newState = enabled == true
	if modificationState.autoFpsActive == newState then
		return
	end

	modificationState.autoFpsActive = newState
	modificationState.autoFpsReason = newState and (reason or modificationState.autoFpsReason or "unknown") or (reason or "none")
	modificationState.autoFpsTriggerSince = nil
	modificationState.autoFpsRecoverSince = nil

	if newState then
		-- Classic one-shot AutoFPS remover. Existing entities are removed once;
		-- future WORLDPLAYERADD/WORLDVEHICLEADD are consumed by stream-in handlers.
		-- High-frequency sync packets are NOT blocked by AutoFPS.
		if not modificationState.removePlayers[0] then
			modificationState.playerStreamCache = {}
			modificationState.snapshotExistingPlayers()
			modificationState.removeCachedPlayersNow()
		end
		if not modificationState.removeVehicles[0] then
			modificationState.vehicleStreamCache = {}
			modificationState.snapshotExistingVehicles()
			modificationState.removeCachedVehiclesNow()
		end
		sendNotify(u8:decode("Авто FPS активирован (") .. tostring(modificationState.autoFpsReason) .. ").")
	else
		-- No synthetic stream-in on AutoFPS recovery. New stream-in RPCs are simply
		-- allowed again; removed entities return after a natural restream.
		if not modificationState.removePlayers[0] then
			modificationState.playerStreamCache = {}
		end
		if not modificationState.removeVehicles[0] then
			modificationState.vehicleStreamCache = {}
		end
		sendNotify(u8:decode("Авто FPS отключен: нагрузка нормализовалась."))
	end

	modificationState.logAutoFps(newState and "activation" or "recovery", reason)
end

function modificationState.setAutoFpsEnabled(enabled, showNotification)
	local newState = enabled == true
	if modificationState.autoFpsEnabled[0] == newState then
		return
	end

	modificationState.autoFpsEnabled[0] = newState
	ini.cfg.mod_auto_fps = newState
	modificationState.autoFpsTriggerSince = nil
	modificationState.autoFpsRecoverSince = nil
	modificationState.autoFpsNextCheck = 0
	save_all()

	if not newState and modificationState.autoFpsActive then
		modificationState.setAutoFpsActive(false, "disabled")
	end
	modificationState.autoFpsReason = newState and "monitoring" or "disabled"

	if showNotification then
		sendNotify(newState and u8:decode("Авто FPS включен.") or u8:decode("Авто FPS выключен."))
	end

	modificationState.logAutoFps(newState and "enable" or "disable", newState and "monitoring" or "disabled")
end

function modificationState.setAutoCycleEnabled(enabled, showNotification)
	local newState = enabled == true
	if modificationState.autoCycleEnabled[0] == newState then
		return
	end

	modificationState.autoCycleEnabled[0] = newState
	ini.cfg.mod_auto_cycle = newState
	save_all()

	if showNotification then
		sendNotify(newState and u8:decode("Автоцикл торговли включен.") or u8:decode("Автоцикл торговли выключен."))
	end
end

function modificationState.setAutoEatEnabled(enabled, showNotification)
	local newState = enabled == true
	if modificationState.autoEatEnabled[0] == newState then
		return
	end

	modificationState.autoEatEnabled[0] = newState
	ini.cfg.mod_autoeat = newState
	save_all()

	if showNotification then
		sendNotify(newState and u8:decode("Автоеда включена.") or u8:decode("Автоеда выключена."))
	end
end

function modificationState.sendAutoEatSyncKey(key, isDown)
	local syncOk = pcall(require, "samp.synchronization")
	local raknetOk, raknetModule = pcall(require, "samp.raknet")

	if not syncOk or not raknetOk or not raknetModule then
		return false
	end

	local dataType = "struct PlayerSyncData"
	local data = ffi.new(dataType, {})
	local rawDataPtr = tonumber(ffi.cast("uintptr_t", ffi.new(dataType .. "*", data)))
	local playerFound, playerId = sampGetPlayerIdByCharHandle(PLAYER_PED)

	if not playerFound then
		return false
	end

	sampStorePlayerOnfootData(playerId, rawDataPtr)

	if isDown then
		data.keysData = tonumber(key) or 0
	end

	local bitStream = raknetNewBitStream()

	raknetBitStreamWriteInt8(bitStream, raknetModule.PACKET.PLAYER_SYNC)
	raknetBitStreamWriteBuffer(bitStream, rawDataPtr, ffi.sizeof(data))
	raknetSendBitStreamEx(bitStream, 1, 7, 1)
	raknetDeleteBitStream(bitStream)

	return true
end

function modificationState.autoEatRespondExpected(dialogId, button, listIndex, inputText)
	if type(sampIsDialogActive) ~= "function" or not sampIsDialogActive() then
		return false
	end
	if type(sampGetCurrentDialogId) ~= "function" then
		return false
	end
	local ok, currentDialogId = pcall(sampGetCurrentDialogId)
	if not ok or tonumber(currentDialogId) ~= tonumber(dialogId) then
		return false
	end
	sampSendDialogResponse(dialogId, button, listIndex, inputText)
	return true
end

function modificationState.updateAutoEat()
	if not modificationState.autoEatEnabled[0] or modificationState.autoEatBusy then
		return
	end

	if modificationState.autoEatSatiety == nil then
		return
	end

	local threshold = math.max(1, math.min(99, tonumber(modificationState.autoEatPercent[0]) or 1))

	if tonumber(modificationState.autoEatSatiety) > threshold then
		return
	end

	local now = getGameTimer()

	if now < (tonumber(modificationState.autoEatNextAction) or 0) then
		return
	end

	if sampIsDialogActive() then
		return
	end

	modificationState.autoEatBusy = true
	modificationState.autoEatNextAction = now + 3500

	lua_thread.create(function()
		local method = math.max(0, math.min(5, tonumber(modificationState.autoEatMethod[0]) or 0))
		local function finish()
			modificationState.autoEatBusy = false
			modificationState.autoEatNextAction = getGameTimer() + 3500
		end

		if method == 0 then
			wait(500)
			sampSendChat("/cheeps")
			wait(3500)
		elseif method == 1 then
			wait(500)
			sampSendChat("/jfish")
			wait(3500)
		elseif method == 2 then
			wait(500)
			sampSendChat("/jmeat")
			wait(3500)
		elseif method == 3 then
			wait(500)
			sampSendChat("/meatbag")
			wait(3500)
		elseif method == 4 then
			wait(100)
			sampSendChat("/home")
			wait(900)
			if not modificationState.autoEatRespondExpected(7238, 1, 0, false) then finish() return end
			wait(900)
			if not modificationState.autoEatRespondExpected(174, 1, 1, false) then finish() return end
			wait(900)
			if not modificationState.autoEatRespondExpected(2431, 1, 2, false) then finish() return end
			wait(900)
			if not modificationState.autoEatRespondExpected(185, 1, 6, false) then finish() return end
			sampCloseCurrentDialogWithButton(0)
		elseif method == 5 then
			wait(100)
			modificationState.sendAutoEatSyncKey(1024, false)
			wait(100)
			modificationState.sendAutoEatSyncKey(1024, true)
			wait(900)
			if not modificationState.autoEatRespondExpected(1825, 1, 6, false) then finish() return end
		end

		finish()
	end)
end

function modificationState.updateAutoFps()
	if not modificationState.autoFpsEnabled[0] then
		return
	end

	local paused = type(isPauseMenuActive) == "function" and isPauseMenuActive()
	local unfocused = type(isGameWindowForeground) == "function" and not isGameWindowForeground()
	if paused or unfocused then
		modificationState.autoFpsTriggerSince = nil
		modificationState.autoFpsRecoverSince = nil
		return
	end

	local now = getGameTimer()
	if now < modificationState.autoFpsNextCheck then
		return
	end
	modificationState.autoFpsNextCheck = now + 250

	local fps = tonumber(modificationState.autoFpsCurrent) or 0
	local playerCount = modificationState.getAutoFpsPlayerCount()
	modificationState.autoFpsPlayerCountValid = playerCount ~= nil
	if playerCount ~= nil then
		modificationState.autoFpsLastPlayerCount = playerCount
	end

	if fps <= 0 or playerCount == nil then
		modificationState.autoFpsTriggerSince = nil
		modificationState.autoFpsRecoverSince = nil
		modificationState.autoFpsReason = playerCount == nil and "players-unavailable" or "fps-unavailable"
		return
	end

	local playersThreshold = math.max(1, tonumber(modificationState.autoFpsPlayersThreshold[0]) or 80)
	local fpsThreshold = math.max(15, tonumber(modificationState.autoFpsThreshold[0]) or 45)
	-- Auto FPS activates when EITHER threshold is crossed:
	-- FPS below the configured value OR server player count above the configured value.
	local playersHigh = playerCount > playersThreshold
	local fpsLow = fps < fpsThreshold
	local shouldBoost = fpsLow or playersHigh
	local reason = playersHigh and fpsLow and "players+fps" or playersHigh and "players" or fpsLow and "fps" or "none"
	if shouldBoost or not modificationState.autoFpsActive then
		modificationState.autoFpsReason = reason
	end

	if shouldBoost then
		modificationState.autoFpsRecoverSince = nil
		modificationState.autoFpsTriggerSince = nil
		if not modificationState.autoFpsActive then
			modificationState.setAutoFpsActive(true, reason)
		end
	else
		modificationState.autoFpsTriggerSince = nil
		if modificationState.autoFpsActive then
			local recovered = playerCount <= math.max(0, playersThreshold - 5) and fps >= fpsThreshold + 5
			if recovered then
				if modificationState.autoFpsRecoverSince == nil then
					modificationState.autoFpsRecoverSince = now
				elseif now - modificationState.autoFpsRecoverSince >= 4000 then
					modificationState.setAutoFpsActive(false, "recovered")
				end
			else
				modificationState.autoFpsRecoverSince = nil
			end
		end
	end
end

addEventHandler("onD3DPresent", function()
	local now = getGameTimer()
	local paused = type(isPauseMenuActive) == "function" and isPauseMenuActive()
	local unfocused = type(isGameWindowForeground) == "function" and not isGameWindowForeground()
	if paused or unfocused then
		modificationState.autoFpsFrameCounter = 0
		modificationState.autoFpsWindowStartedAt = now
		modificationState.autoFpsCurrent = 0
		return
	end
	if modificationState.autoFpsWindowStartedAt == 0 then
		modificationState.autoFpsWindowStartedAt = now
	end

	modificationState.autoFpsFrameCounter = modificationState.autoFpsFrameCounter + 1
	local elapsed = now - modificationState.autoFpsWindowStartedAt

	if elapsed > 3000 then
		modificationState.autoFpsFrameCounter = 0
		modificationState.autoFpsWindowStartedAt = now
		modificationState.autoFpsCurrent = 0
	elseif elapsed >= 1000 then
		modificationState.autoFpsCurrent = modificationState.autoFpsFrameCounter * 1000 / math.max(1, elapsed)
		modificationState.autoFpsFrameCounter = 0
		modificationState.autoFpsWindowStartedAt = now
	end
end)

M.updateAndRenderLavkaHelper = updateAndRenderLavkaHelper
M.invalidateLavkaHelperGrid = invalidateLavkaHelperGrid
M.lavkaHelperOnCreate3DText = lavkaHelperOnCreate3DText
M.lavkaHelperOnRemove3DText = lavkaHelperOnRemove3DText
return true
end

return M
