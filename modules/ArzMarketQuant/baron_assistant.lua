local M = {}

M.VERSION = 60
M.REQUIRED_TUTORIAL_VERSION = 1
M.NAME = "Барон дю Валлон де Брасье де Пьерфон"

local MASCOT_SIZE = 440
local BARON_TEXT_SCALE = 1.50
local BARON_BASE_SCREEN_W = 1920
local BARON_BASE_SCREEN_H = 1080
local BARON_MIN_SCREEN_SCALE = 0.68
local BARON_MAX_SCREEN_SCALE = 1.50
local BUBBLE_IMAGE_WIDTH_SCALE = 1.06
local BUBBLE_IMAGE_HEIGHT_SCALE = 1.20
local BUBBLE_TARGET_X_LEFT = 0.74
local BUBBLE_TARGET_X_RIGHT = 0.26
local BUBBLE_TARGET_Y = 0.20

local ctx = nil
local state = nil
local modules = {}
local moduleLoadWarnings = {}
local typed = {
    key = nil,
    segmentChars = {},
    total = 0,
    count = 0,
    lastAt = 0
}
local skipCooldownRuntime = {
    key = nil,
    started_at = 0
}
local choiceCooldownRuntime = {
    key = nil,
    started_at = 0
}

local motion = {
    initialized = false,
    key = nil,
    startAt = 0,
    duration = 240,
    fromMascotX = 0,
    fromMascotY = 0,
    fromBubbleX = 0,
    fromBubbleY = 0,
    mascotX = 0,
    mascotY = 0,
    bubbleX = 0,
    bubbleY = 0
}
local missingAnchorWatch = {
    key = nil,
    since = 0,
    logged = false
}

local displayGate = {
    readySince = nil
}

local commandsRegistered = false

local DISPLAY_DELAY_MS = 90000

-- Lua tutorial is preserved in baron_tutorial_lua.lua, but temporarily disabled.
local LUA_TUTORIAL_ENABLED = false

local MODULE_FILES = {
    onboarding = "baron_onboarding.lua",
    tutorial_lua = "baron_tutorial_lua.lua",
    tutorial_html = "baron_tutorial_html.lua"
}

local PAGE_BY_ID = {
    [1] = "sell", [2] = "buy", [3] = "settings", [4] = "logs",
    [5] = "marketplace", [7] = "mods", [8] = "storage"
}

local OLD_ONBOARDING_STEPS = {
    welcome = true,
    interfaces_intro = true,
    interface_lua = true,
    interface_html = true,
    lua_intro_1 = true,
    lua_intro_2 = true,
    lua_look = true,
    html_intro_1 = true,
    html_intro_2 = true,
    html_intro_3 = true,
    html_look = true,
    free_try = true,
    interface_choose = true,
    interface_loading = true,
    tutorial_offer = true,
    lua_disabled_1 = true,
    lua_disabled_1_more = true,
    lua_disabled_2 = true,
    lua_disabled_3 = true,
    lua_redirect_offer = true
}

local function nowMs()
    if ctx and type(ctx.nowMs) == "function" then
        local ok, value = pcall(ctx.nowMs)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return math.floor(os.clock() * 1000)
end

local function clone(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = clone(v) end
    return out
end

local function splitUtf8(text)
    local chars = {}
    text = tostring(text or "")
    for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        chars[#chars + 1] = ch
    end
    if #chars == 0 and text ~= "" then chars[1] = text end
    return chars
end

local function normalizeSegments(step)
    if type(step) ~= "table" then return {} end
    if type(step.segments) == "table" and #step.segments > 0 then
        local out = {}
        for _, segment in ipairs(step.segments) do
            if type(segment) == "table" then
                out[#out + 1] = {
                    text = tostring(segment.text or ""),
                    color = tostring(segment.color or "normal")
                }
            end
        end
        if #out > 0 then return out end
    end
    return {{ text = tostring(step.text or ""), color = "normal" }}
end

local function plainText(segments)
    local parts = {}
    for _, segment in ipairs(segments or {}) do
        parts[#parts + 1] = tostring(segment.text or "")
    end
    return table.concat(parts)
end

local function modulePath(id)
    local fileName = MODULE_FILES[id]
    if not fileName then return nil end
    local base = ctx and ctx.moduleBasePath or nil
    if type(base) ~= "string" or base == "" then return nil end
    local tail = base:sub(-1)
    local sep = (tail == "\\" or tail == "/") and "" or "\\"
    return base .. sep .. fileName
end

local function warnModuleLoadOnce(key, message)
    key = tostring(key or "unknown")
    if moduleLoadWarnings[key] then return end
    moduleLoadWarnings[key] = true
    print(message)
end

local function loadModule(id)
    if type(id) ~= "string" or MODULE_FILES[id] == nil then
        return nil
    end
    if modules[id] then return modules[id] end
    local path = modulePath(id)
    if not path then
        warnModuleLoadOnce("path:" .. id, "[ArzMarket][Baron] module path missing: " .. id)
        return nil
    end
    local loader, loadError = loadfile(path)
    if not loader then
        warnModuleLoadOnce("load:" .. id .. ":" .. tostring(loadError), "[ArzMarket][Baron] module load failed: " .. id .. " | " .. tostring(loadError))
        return nil
    end
    local ok, value = pcall(loader)
    if not ok or type(value) ~= "table" then
        warnModuleLoadOnce("init:" .. id .. ":" .. tostring(value), "[ArzMarket][Baron] module init failed: " .. id .. " | " .. tostring(value))
        return nil
    end
    moduleLoadWarnings["path:" .. id] = nil
    modules[id] = value
    return value
end

local function activeModule()
    if type(state) ~= "table" then return nil end
    return loadModule(state.current_module)
end

local function tutorialFacts(stepId)
    if not ctx or type(ctx.getTutorialFacts) ~= "function" then return {} end
    local requestedStep = stepId or (state and state.current_step or nil)
    local ok, value = pcall(ctx.getTutorialFacts, state and state.interface or nil, requestedStep)
    return ok and type(value) == "table" and value or {}
end

local function resolveConditionalStepId(stepId)
    local resolved = tostring(stepId or "")
    -- The tutorial must always require a fresh inventory scan, even when
    -- cached/scanned items are already visible in the Sell inventory list.
    -- Advancing from sell_scan_prompt is allowed only by sell_scan_completed.
    if resolved == "sell_selected_1" or resolved == "sell_selected_2" or resolved == "sell_selected_3" then
        local facts = tutorialFacts(resolved)
        -- Never leave Baron pointing at a non-existent status control. If the
        -- selected list was lost/cleared, return to the item-selection step.
        if facts.sell_items_empty == true then return "sell_inventory" end
    end
    return resolved
end

local function currentStep()
    local module = activeModule()
    if not module then return nil end
    local facts = tutorialFacts()
    if type(module.getStep) == "function" then
        local ok, step = pcall(module.getStep, state.current_step, state, facts)
        if ok and type(step) == "table" then return step end
    end
    if type(module.STEPS) == "table" then
        return module.STEPS[state.current_step]
    end
    return nil
end

local function resetTyping()
    typed.key = nil
    typed.segmentChars = {}
    typed.total = 0
    typed.count = 0
    typed.lastAt = 0
end

local function save()
    if not ctx or type(ctx.saveState) ~= "function" or type(state) ~= "table" then return false end
    state.version = M.VERSION
    state.updated_at = os.time()
    local ok, result = pcall(ctx.saveState, clone(state))
    if not ok or result == false then
        print("[ArzMarket][Baron] state save failed: " .. tostring(result))
        return false
    end
    return true
end

local function touch()
    state.revision = (tonumber(state.revision) or 0) + 1
    state.current_message = tonumber(state.current_message) or 0
    resetTyping()
    save()
end

local function moduleContainsStep(module, stepId)
    if type(module) ~= "table" or type(stepId) ~= "string" or stepId == "" then return false end
    if type(module.STEPS) == "table" and type(module.STEPS[stepId]) == "table" then return true end
    if type(module.getStep) == "function" then
        local ok, value = pcall(module.getStep, stepId, state, {})
        return ok and type(value) == "table"
    end
    return false
end

local function repairActiveState()
    if type(state) ~= "table" or state.active ~= true then return true end

    local stepId = tostring(state.current_step or state.step or "")
    if stepId == "" or stepId == "dormant" then
        state.active = false
        state.current_module = nil
        state.current_step = "dormant"
        state.step = "dormant"
        state.current_message = 0
        state.pending_interface = nil
        state.choice_locked = false
        state.dismissed_step = nil
        state.revision = (tonumber(state.revision) or 0) + 1
        save()
        return false
    end

    local currentId = state.current_module
    if type(currentId) == "string" and MODULE_FILES[currentId] ~= nil then
        local currentModule = loadModule(currentId)
        if currentModule and moduleContainsStep(currentModule, stepId) then
            return true
        end
        -- A known module that temporarily cannot be loaded is not treated as
        -- corrupt progress. Keep the saved position for a later reload.
        if currentModule == nil then return false end
    end

    local candidates = {}
    local seen = {}
    local function addCandidate(id)
        if type(id) == "string" and MODULE_FILES[id] and not seen[id] then
            seen[id] = true
            candidates[#candidates + 1] = id
        end
    end

    if OLD_ONBOARDING_STEPS[stepId] then addCandidate("onboarding") end
    if state.interface == "html" then
        addCandidate("tutorial_html")
    elseif state.interface == "lua" then
        addCandidate("tutorial_lua")
    end
    addCandidate("onboarding")
    addCandidate("tutorial_html")
    addCandidate("tutorial_lua")

    for _, candidateId in ipairs(candidates) do
        local candidate = loadModule(candidateId)
        if candidate and moduleContainsStep(candidate, stepId) then
            local previous = tostring(state.current_module)
            state.current_module = candidateId
            state.step = stepId
            state.current_step = stepId
            state.current_message = tonumber(state.current_message) or 0
            state.dismissed_step = nil
            state.revision = (tonumber(state.revision) or 0) + 1
            save()
            print("[ArzMarket][Baron] recovered tutorial module: " .. previous .. " -> " .. candidateId .. " at " .. stepId)
            return true
        end
    end

    print("[ArzMarket][Baron] invalid active state disabled safely: module=" .. tostring(state.current_module) .. ", step=" .. stepId)
    state.active = false
    state.current_module = nil
    state.current_step = "dormant"
    state.step = "dormant"
    state.current_message = 0
    state.pending_interface = nil
    state.choice_locked = false
    state.dismissed_step = nil
    state.revision = (tonumber(state.revision) or 0) + 1
    save()
    return false
end

local function notifyStepChanged()
    if not ctx or type(ctx.onStepChanged) ~= "function" or type(state) ~= "table" then return end
    -- This callback is intentionally not protected by pcall. HTML actions can
    -- arrive from the HTTP MoonLoader thread, and a pcall boundary here makes
    -- scheduler-aware callbacks unsafe. The callback itself only queues work.
    ctx.onStepChanged(state.current_module, state.current_step)
end

local function setStep(stepId)
    stepId = resolveConditionalStepId(stepId)
    local module = activeModule()
    if not module then return false end
    local exists = false
    if type(module.getStep) == "function" then
        local ok, value = pcall(module.getStep, stepId, state)
        exists = ok and type(value) == "table"
    elseif type(module.STEPS) == "table" then
        exists = type(module.STEPS[stepId]) == "table"
    end
    if not exists then
        print("[ArzMarket][Baron] invalid step transition: " .. tostring(state and state.current_step or "nil") .. " -> " .. tostring(stepId))
        return false
    end
    state.current_step = stepId
    state.step = stepId
    state.dismissed_step = nil
    state.active = true
    state.current_message = 0
    touch()
    notifyStepChanged()
    return true
end

local function tutorialModuleId(mode)
    return mode == "html" and "tutorial_html" or "tutorial_lua"
end

local function newState(firstLaunch, preferredInterface)
    if firstLaunch == true then
        return {
            version = M.VERSION,
            required_tutorial_version = 0,
            active = true,
            onboarding_complete = false,
            tutorial_complete = false,
            lua_tutorial_complete = false,
            html_tutorial_complete = false,
            interface = nil,
            current_module = "onboarding",
            current_step = "welcome",
            step = "welcome",
            current_message = 0,
            pending_interface = nil,
            dismissed_step = nil,
            revision = 1,
            session_generation = 1,
            display_delay_done = false
        }
    end
    local mode = preferredInterface == "html" and "html" or "lua"
    return {
        version = M.VERSION,
        required_tutorial_version = 0,
        active = false,
        onboarding_complete = true,
        tutorial_complete = false,
        lua_tutorial_complete = false,
        html_tutorial_complete = false,
        interface = mode,
        current_module = nil,
        current_step = "dormant",
        step = "dormant",
        current_message = 0,
        pending_interface = nil,
        dismissed_step = nil,
        revision = 1,
        session_generation = 1,
        display_delay_done = true
    }
end

local function migrateState(loaded, firstLaunch, preferredInterface)
    if type(loaded) ~= "table" then
        return newState(firstLaunch, preferredInterface)
    end

    if tonumber(loaded.version) == M.VERSION and loaded.current_step then
        local out = clone(loaded)
        out.revision = tonumber(out.revision) or 1
        out.session_generation = tonumber(out.session_generation) or 1
        out.current_message = tonumber(out.current_message) or 0
        out.lua_tutorial_complete = out.lua_tutorial_complete == true
        out.html_tutorial_complete = out.html_tutorial_complete == true
        out.onboarding_complete = out.onboarding_complete == true
        out.tutorial_complete = out.tutorial_complete == true
        out.required_tutorial_version = tonumber(out.required_tutorial_version) or 0
        out.step = out.current_step
        -- dismissed_step is only a transient visual state. Persisting it across
        -- a script/CEF reload can make an unfinished tutorial look completed.
        if out.active == true and tostring(out.current_step or "") ~= "dormant" then
            out.dismissed_step = nil
            out.display_delay_done = true
        else
            out.display_delay_done = out.display_delay_done == true
        end
        return out
    end

    local oldStep = tostring(loaded.current_step or loaded.step or "dormant")
    local oldInterface = loaded.interface == "html" and "html" or loaded.interface == "lua" and "lua" or (preferredInterface == "html" and "html" or "lua")
    local onboardingComplete = loaded.onboarding_complete == true or loaded.onboardingComplete == true
    local tutorialComplete = loaded.tutorial_complete == true or loaded.tutorialComplete == true
    local out = newState(false, oldInterface)
    out.revision = (tonumber(loaded.revision) or 0) + 1
    out.session_generation = (tonumber(loaded.session_generation) or 0) + 1
    out.interface = oldInterface
    out.onboarding_complete = onboardingComplete
    out.tutorial_complete = tutorialComplete
    out.lua_tutorial_complete = loaded.lua_tutorial_complete == true or (tutorialComplete and oldInterface == "lua")
    out.html_tutorial_complete = loaded.html_tutorial_complete == true or (tutorialComplete and oldInterface == "html")
    out.required_tutorial_version = tonumber(loaded.required_tutorial_version) or 0

    if oldStep == "dormant" then
        out.active = false
        out.current_module = nil
        out.current_step = "dormant"
    elseif OLD_ONBOARDING_STEPS[oldStep] then
        out.active = true
        out.current_module = "onboarding"
        local onboardingStepMap = {
            interface_lua = "lua_intro_1",
            interface_html = "html_intro_1",
            lua_intro_2 = "lua_look",
            html_intro_2 = "html_intro_1",
            html_intro_3 = "html_look",
            free_try = "interface_choose"
        }
        out.current_step = onboardingStepMap[oldStep] or oldStep
    else
        local tutorialStepMap = {
            sell_intro = "sell_scan_prompt",
            sell_scan = "sell_scan_prompt",
            sell_inventory = "sell_scan_prompt",
            sell_start = "sell_selected_1",
            buy_intro = "buy_search",
            buy_add = "buy_search",
            buy_start = "buy_auto_prices",
            go_logs = "logs_intro",
            logs_intro = "logs_intro",
            go_marketplace = "marketplace_intro",
            marketplace_intro = "marketplace_intro",
            go_mods = "mods_intro",
            mods_intro = "mods_intro",
            go_storage = "storage_intro_1",
            storage_intro = "storage_intro_1",
            finish = "finish_1"
        }
        out.active = true
        out.current_module = tutorialModuleId(oldInterface)
        out.current_step = tutorialStepMap[oldStep] or oldStep
    end
    out.step = out.current_step
    out.display_delay_done = true
    return out
end

local function visibleSegments(step)
    local segments = normalizeSegments(step)
    local key = tostring(state.current_module or "") .. ":" .. tostring(state.current_step or "") .. ":" .. tostring(state.current_message or 0)
    if typed.key ~= key then
        typed.key = key
        typed.segmentChars = {}
        typed.total = 0
        typed.count = 0
        typed.lastAt = nowMs()
        for index, segment in ipairs(segments) do
            typed.segmentChars[index] = splitUtf8(segment.text)
            typed.total = typed.total + #typed.segmentChars[index]
        end
    end

    local now = nowMs()
    local elapsed = math.max(0, now - typed.lastAt)
    local add = math.floor(elapsed / 12)
    if add > 0 then
        typed.count = math.min(typed.total, typed.count + add)
        typed.lastAt = typed.lastAt + add * 12
    end

    local remain = typed.count
    local out = {}
    for index, segment in ipairs(segments) do
        local chars = typed.segmentChars[index] or {}
        local count = math.min(#chars, math.max(0, remain))
        if count > 0 then
            out[#out + 1] = {
                text = table.concat(chars, "", 1, count),
                color = segment.color
            }
        end
        remain = remain - count
        if remain <= 0 then break end
    end
    return out, typed.count >= typed.total
end

local function isPlayerReady()
    if ctx and type(ctx.isPlayerReady) == "function" then
        local ok, value = pcall(ctx.isPlayerReady)
        if ok then return value == true end
    end
    return true
end

local function isDisplayReady()
    if not isPlayerReady() then
        displayGate.readySince = nil
        return false
    end
    if type(state) == "table" and state.display_delay_done == true then
        return true
    end
    local now = nowMs()
    if not tonumber(displayGate.readySince) then
        displayGate.readySince = now
    end
    if (now - displayGate.readySince) < DISPLAY_DELAY_MS then
        return false
    end
    if type(state) == "table" and state.display_delay_done ~= true then
        state.display_delay_done = true
        state.revision = (tonumber(state.revision) or 0) + 1
        save()
    end
    return true
end

function M.init(context)
    ctx = context or {}
    local loaded = nil
    local loadStatus = "missing"
    if type(ctx.loadState) == "function" then
        local ok, value, status = pcall(ctx.loadState)
        if ok then
            if type(value) == "table" then loaded = value end
            if type(status) == "string" and status ~= "" then loadStatus = status end
        else
            loadStatus = "error"
            print("[ArzMarket][Baron] state load failed: " .. tostring(value))
        end
    end

    -- Never overwrite a broken/unreadable state with a fresh dormant state.
    -- The next reload may be able to recover it from the persistent .bak file.
    if loaded == nil and loadStatus ~= "missing" then
        print("[ArzMarket][Baron] state recovery failed, preserving files: " .. tostring(loadStatus))
        return false
    end

    if not loadModule("onboarding") then return false end
    state = migrateState(loaded, ctx.firstLaunch == true, ctx.interface)

    -- Release gate: every user must enter the current tutorial wave once, including
    -- users who already completed an older ArzMarket onboarding. This field is
    -- independent from state schema VERSION so normal module migrations do not
    -- accidentally retrigger training. Increment REQUIRED_TUTORIAL_VERSION only
    -- when a future release must force onboarding for all users again.
    if (tonumber(state.required_tutorial_version) or 0) < M.REQUIRED_TUTORIAL_VERSION then
        local hasSavedProgress = state.active == true
            and tostring(state.current_step or state.step or "") ~= ""
            and tostring(state.current_step or state.step or "") ~= "dormant"

        if hasSavedProgress then
            -- The current tutorial wave has already started. Mark the release as
            -- entered now and keep the exact saved module/step across reloads.
            state.required_tutorial_version = M.REQUIRED_TUTORIAL_VERSION
            state.release_tutorial_required = true
            state.display_delay_done = true
        else
            -- Start the required tutorial only once. Mark its version immediately,
            -- otherwise every MoonLoader reload resets progress back to welcome.
            state = newState(true, ctx.interface)
            state.required_tutorial_version = M.REQUIRED_TUTORIAL_VERSION
            state.release_tutorial_required = true
            state.display_delay_done = false
        end
    else
        state.release_tutorial_required = false
    end

    -- Lua tutorial files and logic stay intact, but while the feature flag is off
    -- any saved/running Lua tutorial is redirected to the temporary support notice.
    if LUA_TUTORIAL_ENABLED ~= true and state.active == true and (
        state.current_module == "tutorial_lua" or
        (state.current_module == "onboarding" and state.current_step == "tutorial_offer" and state.interface == "lua")
    ) then
        state.interface = "lua"
        state.pending_interface = nil
        state.current_module = "onboarding"
        state.current_step = "lua_disabled_1"
        state.step = state.current_step
        state.current_message = 0
        state.dismissed_step = nil
        state.onboarding_complete = true
        state.tutorial_complete = false
        state.lua_tutorial_complete = false
    end
    -- Every Lua/CEF reload starts a new assistant session. Late events from the
    -- previous CEF instance are rejected by session_generation.
    state.session_generation = (tonumber(state.session_generation) or 0) + 1

    -- A hidden message is a transient UI state, not tutorial progress. Resume
    -- unfinished training visibly and immediately after a script/CEF reload.
    if loaded ~= nil and state.active == true and tostring(state.current_step or "") ~= "dormant" then
        state.dismissed_step = nil
        state.display_delay_done = true
    end

    -- Repair old/corrupted states where a visible tutorial step was saved with
    -- current_module=nil. This restores progress instead of entering a render loop.
    if state.active == true and not repairActiveState() then
        if state.active == true then
            print("[ArzMarket][Baron] resume module unavailable; saved progress preserved: " .. tostring(state.current_module))
            return false
        end
    end

    -- Module errors must never destroy a valid saved tutorial position.
    if state.current_module and not loadModule(state.current_module) then
        print("[ArzMarket][Baron] resume module load failed; saved progress preserved: " .. tostring(state.current_module))
        return false
    end

    -- Do not resolve item-dependent tutorial fallbacks here. At this point the
    -- HTML trade-draft module has not restored its list yet. Snapshot() runs
    -- after UI modules are initialized and can safely validate those steps.
    state.version = M.VERSION
    state.step = state.current_step
    displayGate.readySince = nil
    save()
    return true
end

function M.isActive()
    if type(state) ~= "table" or state.active ~= true or state.current_step == "dormant" then return false end
    if not repairActiveState() then return false end
    return isDisplayReady()
end

function M.isOnboarding()
    return M.isActive() and state.current_module == "onboarding"
end

function M.needsChooser()
    if not M.isOnboarding() then return false end
    return state.current_step == "interface_choose" or state.current_step == "interface_loading"
end

function M.isPreviewInteractive()
    return false
end

function M.getStep()
    return state and state.current_step or "dormant"
end

function M.getModule()
    return state and state.current_module or nil
end

function M.getInterface()
    return state and state.interface or nil
end

function M.getState()
    return clone(state or {})
end

local function stepAllowsSkip(step)
    if type(step) ~= "table" then return false end
    if step.choice then return false end
    -- Promo windows are intentionally silent because they replace the normal
    -- Baron bubble, but their own close button must still be allowed to advance.
    if step.silent and step.promo_window ~= true then return false end
    local waitMode = tostring(step.wait or "")
    if waitMode == "page" or waitMode == "event" or waitMode == "event_or_skip" or waitMode == "interface_loading" then
        return false
    end
    return true
end

local function getSkipCooldownMs(step)
    if type(step) ~= "table" then return 0 end
    local delay = tonumber(step.skip_delay_ms) or 0
    if delay <= 0 then return 0 end

    local key = tostring(state and state.current_module or "") .. ":" .. tostring(state and state.current_step or "")
    local now = nowMs()
    if skipCooldownRuntime.key ~= key then
        skipCooldownRuntime.key = key
        skipCooldownRuntime.started_at = now
    end

    return math.max(0, delay - (now - (tonumber(skipCooldownRuntime.started_at) or now)))
end

local MYSTERY_COOLDOWN_GLYPHS = { "¤", "§", "∆", "⊗", "※", "↯", "◊", "Ψ", "₪", "☼", "⌘", "▓", "¿", "✶", "☍", "⟡" }

local function buildMysteryCooldownGlyphs(seed)
    local tick = math.max(0, tonumber(seed) or os.time())
    local total = #MYSTERY_COOLDOWN_GLYPHS
    local a = MYSTERY_COOLDOWN_GLYPHS[(tick % total) + 1] or "?"
    local b = MYSTERY_COOLDOWN_GLYPHS[((tick * 3 + 1) % total) + 1] or "?"
    local c = MYSTERY_COOLDOWN_GLYPHS[((tick * 5 + 2) % total) + 1] or "?"
    return a .. b .. c
end

local function getChoiceNoCooldownLabel(step, remainingMs)
    if type(step) == "table" and step.choice == "future_details" then
        return "Нет (осталось сек: " .. buildMysteryCooldownGlyphs(os.time()) .. ")"
    end
    local remaining = tonumber(remainingMs) or getChoiceNoCooldownMs(step)
    if remaining <= 0 then return "Нет" end
    return string.format("Нет (%d)", math.ceil(remaining / 1000))
end

local function getChoiceNoCooldownMs(step)
    if type(step) ~= "table" then return 0 end
    local delay = tonumber(step.choice_no_delay_ms) or 0
    if delay <= 0 then return 0 end

    local key = tostring(state and state.current_module or "") .. ":" .. tostring(state and state.current_step or "") .. ":no"
    local now = nowMs()
    if choiceCooldownRuntime.key ~= key then
        choiceCooldownRuntime.key = key
        choiceCooldownRuntime.started_at = now
    end

    return math.max(0, delay - (now - (tonumber(choiceCooldownRuntime.started_at) or now)))
end

function M.snapshot(page, mode)
    if type(state) == "table" and state.active == true then
        repairActiveState()
        if state.active == true then
            local resolvedStep = resolveConditionalStepId(state.current_step)
            if resolvedStep ~= tostring(state.current_step or "") then
                setStep(resolvedStep)
            end
        end
    end
    if not M.isActive() then
        return {
            active = false,
            revision = tonumber(state and state.revision) or 0,
            name = M.NAME,
            module = state and state.current_module or nil
        }
    end
    local step = currentStep()
    if not step then
        return {
            active = false,
            revision = tonumber(state and state.revision) or 0,
            name = M.NAME,
            module = state and state.current_module or nil
        }
    end
    local segments = normalizeSegments(step)
    return {
        active = true,
        revision = tonumber(state.revision) or 0,
        sessionGeneration = tonumber(state.session_generation) or 1,
        name = M.NAME,
        module = state.current_module,
        step = state.current_step,
        text = plainText(segments),
        segments = segments,
        pose = step.pose or "neutral",
        position = step.position or "anchor",
        target = step.target,
        wait = step.wait,
        expectedEvent = step.expected_event,
        expectedPage = step.page or step.required_page,
        requiredPage = step.required_page,
        requiredSettingsSection = step.required_settings_section,
        expectedSection = step.expected_section,
        skipAction = step.skip_action,
        canSkip = stepAllowsSkip(step),
        optionalAnchor = step.optional_anchor == true,
        pointerHotspot = type(step.pointer_hotspot) == "table" and {
            x = tonumber(step.pointer_hotspot.x),
            y = tonumber(step.pointer_hotspot.y),
            anchorX = tonumber(step.pointer_hotspot.anchor_x),
            anchorY = tonumber(step.pointer_hotspot.anchor_y),
            offsetX = tonumber(step.pointer_hotspot.offset_x) or 0,
            offsetY = tonumber(step.pointer_hotspot.offset_y) or 0
        } or nil,
        mascotScale = tonumber(step.mascot_scale) or nil,
        allowMascotOffscreenLeft = step.allow_mascot_offscreen_left == true,
        choice = step.choice,
        choiceType = step.choice,
        finish = step.finish == true,
        chooser = M.needsChooser(),
        previewInteractive = step.preview_interactive == true,
        followAnchor = step.follow_anchor == true,
        bubbleAsset = step.bubble_asset,
        bubbleTextAlign = step.bubble_text_align,
        bubbleScale = tonumber(step.bubble_scale) or nil,
        bubbleShiftX = tonumber(step.bubble_shift_x) or nil,
        bubbleShiftY = tonumber(step.bubble_shift_y) or nil,
        bubbleTargetXLeft = tonumber(step.bubble_target_x_left) or nil,
        bubbleTargetXRight = tonumber(step.bubble_target_x_right) or nil,
        bubbleTargetY = tonumber(step.bubble_target_y) or nil,
        promoWindow = step.promo_window == true,
        promoLines = type(step.promo_lines) == "table" and clone(step.promo_lines) or nil,
        promoRedFrom = tonumber(step.promo_red_from) or nil,
        promoButtonText = tostring(step.promo_button_text or "Понятно"),
        promoLinkLabel = tostring(step.promo_link_label or ""),
        promoLinkIntro = tostring(step.promo_link_intro or "Нажми на эту ссылку:"),
        promoLinkUrl = tostring(step.promo_link_url or ""),
        messageLinkLabel = tostring(step.message_link_label or ""),
        messageLinkUrl = tostring(step.message_link_url or ""),
        hideMascot = step.hide_mascot == true,
        skipDelayMs = tonumber(step.skip_delay_ms) or 0,
        skipCooldownMs = getSkipCooldownMs(step),
        choiceNoDelayMs = tonumber(step.choice_no_delay_ms) or 0,
        choiceNoCooldownMs = getChoiceNoCooldownMs(step),
        messageVisible = step.silent ~= true and state.dismissed_step ~= state.current_step,
        silent = step.silent == true,
        page = page,
        mode = mode or state.interface or "lua",
        interface = state.interface,
        pendingInterface = state.pending_interface
    }
end

local function completeTutorial(forceAll)
    local mode = state.interface == "html" and "html" or "lua"
    if forceAll == true then
        state.html_tutorial_complete = true
        state.lua_tutorial_complete = true
    elseif mode == "html" then
        state.html_tutorial_complete = true
    else
        state.lua_tutorial_complete = true
    end
    state.tutorial_complete = true
    state.onboarding_complete = true
    state.required_tutorial_version = M.REQUIRED_TUTORIAL_VERSION
    state.release_tutorial_required = false
    state.active = false
    state.current_module = nil
    state.current_step = "dormant"
    state.step = "dormant"
    state.dismissed_step = nil
    touch()
    if ctx and type(ctx.onTutorialComplete) == "function" then
        local okComplete, completeError = pcall(ctx.onTutorialComplete, mode)
        if not okComplete then
            print("[ArzMarket][Baron] tutorial completion hook failed: " .. tostring(completeError))
        end
    end
    return true
end

function M.next()
    local step = currentStep()
    if not step then return false end
    if step.finish then return completeTutorial() end
    if step.next then return setStep(step.next) end
    return false
end

function M.skipIntro()
    return M.skip()
end

function M.selectInterface(mode)
    if state.current_module ~= "onboarding" or state.current_step ~= "interface_choose" then return false end
    mode = mode == "html" and "html" or "lua"
    state.pending_interface = mode
    state.dismissed_step = nil
    state.choice_locked = true
    if not setStep("interface_loading") then return false end

    if ctx and type(ctx.beginInterfaceSelection) == "function" then
        local ok, result = pcall(ctx.beginInterfaceSelection, mode)
        if not ok or result == false then
            state.pending_interface = nil
            state.choice_locked = false
            setStep("interface_choose")
            return false
        end
    end
    return mode
end

function M.completeInterfaceLoading(mode)
    if state.current_module ~= "onboarding" or state.current_step ~= "interface_loading" then return false end
    mode = mode == "html" and "html" or "lua"
    state.interface = mode
    state.pending_interface = nil
    state.choice_locked = false
    state.onboarding_complete = false
    if mode == "lua" and LUA_TUTORIAL_ENABLED ~= true then
        state.onboarding_complete = true
        state.tutorial_complete = false
        state.lua_tutorial_complete = false
        return setStep("lua_disabled_1")
    end

    local selectedTutorialId = tutorialModuleId(mode)
    if not loadModule(selectedTutorialId) then
        print("[ArzMarket][Baron] selected tutorial preload failed: " .. tostring(selectedTutorialId))
    end
    return setStep("tutorial_offer")
end

function M.chooseTutorial(accept)
    if state.current_module ~= "onboarding" or state.current_step ~= "tutorial_offer" then return false end
    local mode = state.interface == "html" and "html" or "lua"
    state.onboarding_complete = true
    if accept == true and mode == "lua" and LUA_TUTORIAL_ENABLED ~= true then
        state.current_module = "onboarding"
        state.tutorial_complete = false
        state.lua_tutorial_complete = false
        return setStep("lua_disabled_1")
    end
    if accept == true then
        local moduleId = tutorialModuleId(mode)
        local module = loadModule(moduleId)
        if not module then return false end
        state.current_module = moduleId
        state.current_step = module.START_STEP or "resize"
        state.step = state.current_step
        state.active = true
        state.dismissed_step = nil
        state.tutorial_complete = false
        state.session_generation = (tonumber(state.session_generation) or 0) + 1
        touch()
        return true
    end

    state.active = false
    state.current_module = nil
    state.current_step = "dormant"
    state.step = "dormant"
    state.dismissed_step = nil
    touch()
    return true
end

function M.chooseFutureDetails(accept)
    if state.current_module ~= "tutorial_html" or state.current_step ~= "future_details_offer" then return false end
    if accept == true then
        return setStep("future_ai_1")
    end
    if getChoiceNoCooldownMs(currentStep()) > 0 then return false, "choice_cooldown" end
    return setStep("finish_6")
end

function M.chooseLuaRedirect(accept)
    if state.current_module ~= "onboarding" or state.current_step ~= "lua_redirect_offer" then return false end

    if accept == true then
        state.pending_interface = "html"
        state.dismissed_step = nil
        state.choice_locked = true
        if not setStep("interface_loading") then return false end

        -- The chooser is normally hidden after Lua was already selected. Re-enable
        -- it before starting the existing fade/finalize selection path.
        if ctx and type(ctx.runtime) == "table" and type(ctx.runtime.setChooserVisible) == "function" then
            pcall(ctx.runtime.setChooserVisible, true)
        end

        if ctx and type(ctx.beginInterfaceSelection) == "function" then
            local ok, result = pcall(ctx.beginInterfaceSelection, "html")
            if not ok or result == false then
                state.pending_interface = nil
                state.choice_locked = false
                setStep("lua_redirect_offer")
                return false
            end
        end
        return true
    end

    if getChoiceNoCooldownMs(currentStep()) > 0 then return false, "choice_cooldown" end

    state.interface = "lua"
    state.pending_interface = nil
    state.choice_locked = false
    state.onboarding_complete = true
    state.tutorial_complete = false
    state.lua_tutorial_complete = false
    state.active = false
    state.current_module = nil
    state.current_step = "dormant"
    state.step = "dormant"
    state.dismissed_step = nil
    touch()
    return true
end

function M.skip()
    local step = currentStep()
    if not step then return false end
    if not stepAllowsSkip(step) then return false end
    if getSkipCooldownMs(step) > 0 then return false end
    if step.finish then return M.next() end

    if step.skip_action and ctx and type(ctx.performTutorialAction) == "function" then
        local okAction, actionResult = pcall(ctx.performTutorialAction, step.skip_action, {
            page = step.page or step.required_page,
            target = step.target,
            section = step.required_settings_section or step.expected_section,
            module = state.current_module,
            step = state.current_step,
            interface = state.interface
        })
        if not okAction then
            print("[ArzMarket][Baron] tutorial skip action failed: " .. tostring(actionResult))
        elseif actionResult ~= false and step.next then
            return setStep(step.next)
        end
    end

    if step.wait == "page" then
        state.dismissed_step = state.current_step
        touch()
        return true
    end

    if step.next then return setStep(step.next) end
    state.dismissed_step = state.current_step
    touch()
    return true
end

function M.startOnboardingAt(stepId)
    local module = loadModule("onboarding")
    if not module then return false end

    stepId = tostring(stepId or module.START_STEP or "welcome")
    local exists = false
    if type(module.getStep) == "function" then
        local ok, value = pcall(module.getStep, stepId, state)
        exists = ok and type(value) == "table"
    elseif type(module.STEPS) == "table" then
        exists = type(module.STEPS[stepId]) == "table"
    end
    if not exists then return false end

    state.active = true
    state.onboarding_complete = false
    state.tutorial_complete = false
    state.pending_interface = nil
    state.interface = nil
    state.current_module = "onboarding"
    state.current_step = stepId
    state.step = stepId
    state.current_message = 0
    state.dismissed_step = nil
    state.choice_locked = false
    state.display_delay_done = true
    state.session_generation = (tonumber(state.session_generation) or 0) + 1
    touch()
    notifyStepChanged()
    return true
end

function M.restartTutorial(mode)
    mode = mode == "html" and "html" or "lua"

    if mode == "lua" and LUA_TUTORIAL_ENABLED ~= true then
        local onboarding = loadModule("onboarding")
        if not onboarding then return false end
        state.interface = "lua"
        state.pending_interface = nil
        state.active = true
        state.onboarding_complete = true
        state.tutorial_complete = false
        state.lua_tutorial_complete = false
        state.current_module = "onboarding"
        state.current_step = "lua_disabled_1"
        state.step = state.current_step
        state.current_message = 0
        state.dismissed_step = nil
        state.choice_locked = false
        state.display_delay_done = true
        state.session_generation = (tonumber(state.session_generation) or 0) + 1
        touch()
        notifyStepChanged()
        return true
    end

    local moduleId = tutorialModuleId(mode)
    local module = loadModule(moduleId)
    if not module then return false end
    state.interface = mode
    state.pending_interface = nil
    state.active = true
    state.onboarding_complete = true
    state.tutorial_complete = false
    if mode == "html" then
        state.html_tutorial_complete = false
    else
        state.lua_tutorial_complete = false
    end
    state.current_module = moduleId
    state.current_step = module.START_STEP or "resize"
    state.step = state.current_step
    state.current_message = 0
    state.dismissed_step = nil
    state.display_delay_done = true
    state.session_generation = (tonumber(state.session_generation) or 0) + 1
    touch()
    return true
end

function M.resetOnboarding()
    if not loadModule("onboarding") then return false end
    state.active = true
    state.onboarding_complete = false
    state.tutorial_complete = false
    state.lua_tutorial_complete = false
    state.html_tutorial_complete = false
    state.pending_interface = nil
    state.interface = nil
    state.current_module = "onboarding"
    state.current_step = "welcome"
    state.step = "welcome"
    state.current_message = 0
    state.dismissed_step = nil
    state.choice_locked = false
    state.display_delay_done = true
    state.session_generation = (tonumber(state.session_generation) or 0) + 1
    touch()
    notifyStepChanged()
    return true
end


local function notifyUser(message)
    if ctx and type(ctx.notify) == "function" then
        ctx.notify(tostring(message or ""))
    end
end

local function runtimeCall(name, ...)
    local runtime = ctx and ctx.runtime or nil
    local fn = type(runtime) == "table" and runtime[name] or nil
    if type(fn) ~= "function" then return true end
    return fn(...) ~= false
end

local function syncTrainingRuntime(kind, mode)
    kind = tostring(kind or "")
    mode = mode == "html" and "html" or (mode == "lua" and "lua" or nil)

    runtimeCall("resetTransientUi", kind == "tutorial" or kind == "tutorial_future")
    runtimeCall("setChooserVisible", kind == "interface_choice")

    if kind == "onboarding" or kind == "interface_choice" then
        runtimeCall("setInterfaceConfig", nil, false)
        runtimeCall("showLuaInterface", false)
        runtimeCall("showHtmlInterface", false)
    elseif (kind == "tutorial" or kind == "tutorial_future") and mode ~= nil then
        runtimeCall("setInterfaceConfig", mode, true)
        runtimeCall("resetTutorialPanels")
        if mode == "html" then
            runtimeCall("showLuaInterface", false)
            runtimeCall("showHtmlInterface", true, kind == "tutorial_future" and "settings" or nil)
        else
            runtimeCall("showHtmlInterface", false)
            runtimeCall("showLuaInterface", true)
        end
    elseif kind == "complete" then
        runtimeCall("setChooserVisible", false)
    else
        return false
    end

    return runtimeCall("saveInterfaceConfig")
end

local function bypassCurrentStepSkipCooldown()
    local key = tostring(state and state.current_module or "") .. ":" .. tostring(state and state.current_step or "")
    skipCooldownRuntime.key = key
    skipCooldownRuntime.started_at = nowMs() - 86400000
end

function M.handleFaqCommand(argument)
    local level = tostring(argument or ""):match("^%s*(.-)%s*$") or ""
    local ok = false
    local kind = nil
    local mode = nil

    if level == "" then
        ok = M.resetOnboarding()
        kind = "onboarding"
    elseif level == "1" then
        ok = M.startOnboardingAt("interface_choose")
        kind = "interface_choice"
    elseif level == "2" then
        mode = "lua"
        ok = M.restartTutorial(mode)
        kind = "tutorial"
    elseif level == "3" then
        mode = "html"
        ok = M.restartTutorial(mode)
        kind = "tutorial"
    elseif level == "4" then
        mode = "html"
        ok = M.restartTutorial(mode)
        if ok ~= false then ok = setStep("future_details_offer") end
        kind = "tutorial_future"
    elseif level == "5" then
        if state.interface ~= "lua" and state.interface ~= "html" then state.interface = "html" end
        ok = completeTutorial(true)
        kind = "complete"
        mode = state.interface
    elseif level == "6" then
        mode = state.interface == "lua" and "lua" or "html"
        ok = M.restartTutorial(mode)
        if ok ~= false then ok = setStep("future_features") end
        if ok ~= false then bypassCurrentStepSkipCooldown() end
        kind = "tutorial_future"
    else
        notifyUser("[ArzMarket] /faqq | /faqq 1 | /faqq 2 | /faqq 3 | /faqq 4 | /faqq 5 | /faqq 6")
        return false, "invalid_level"
    end

    if ok == false then
        notifyUser("[ArzMarket] Не удалось запустить обучение Барона.")
        return false, "restart_failed"
    end

    if not syncTrainingRuntime(kind, mode) then
        notifyUser("[ArzMarket] Обучение запущено, но интерфейс не удалось синхронизировать.")
        return false, "host_sync_failed"
    end

    return true
end

function M.handleOutgoingCommand(command)
    command = tostring(command or "")
    if command == "/faqq" then
        M.handleFaqCommand("")
        return true
    end

    local args = command:match("^/faqq%s+(.+)$")
    if args ~= nil then
        M.handleFaqCommand(args)
        return true
    end
    return false
end

function M.registerCommands()
    if commandsRegistered then return true end
    if not ctx or type(ctx.registerCommand) ~= "function" then return false end

    local ok = ctx.registerCommand("faqq", function(arguments)
        M.handleFaqCommand(arguments)
    end)
    if ok == false then return false end
    commandsRegistered = true
    return true
end


function M.setInterface(mode)
    mode = mode == "html" and "html" or "lua"
    if state.current_module == "onboarding" and state.current_step ~= "tutorial_offer" then
        return false
    end
    if state.interface == mode then return true end
    state.interface = mode
    touch()
    return true
end

function M.onPageChanged(page)
    local pageName = tostring(page or "")
    if type(state) == "table" and state.active == true and pageName ~= "" and state.last_page ~= pageName then
        state.last_page = pageName
        state.revision = (tonumber(state.revision) or 0) + 1
        save()
    end

    local step = currentStep()
    if not step or step.wait ~= "page" then return false end
    local expectedPage = step.page or step.required_page
    if not expectedPage or pageName ~= tostring(expectedPage) then return false end
    if step.next then return setStep(step.next) end
    return false
end

function M.event(name, payload)
    name = tostring(name or "")
    payload = type(payload) == "table" and payload or {}
    local payloadGeneration = tonumber(payload.sessionGeneration or payload.session_generation)
    if payloadGeneration and payloadGeneration ~= tonumber(state and state.session_generation or 0) then
        return false
    end

    if name == "page" then
        return M.onPageChanged(payload.page)
    elseif name == "next" then
        return M.next()
    elseif name == "skip" then
        return M.skip()
    end

    -- Keep enough UI context to reopen the tutorial at the exact same place
    -- after a MoonLoader/CEF reload. The step itself is already persisted by
    -- setStep(); this stores the Settings subsection that was open on that step.
    if name == "settings_section_changed" and type(state) == "table" and state.active == true then
        local section = tostring(payload.section or "")
        local validSection = section == "general" or section == "trade" or section == "automation"
            or section == "telegram" or section == "appearance" or section == "configs"
        if validSection and state.last_settings_section ~= section then
            state.last_settings_section = section
            state.revision = (tonumber(state.revision) or 0) + 1
            save()
        end
    end

    local step = currentStep()
    if not step then return false end
    if step.expected_event and tostring(step.expected_event) == name then
        if step.expected_section and tostring(payload.section or "") ~= tostring(step.expected_section) then
            return false
        end
        if name == "resize_changed" then state.resize_interacted = true end
        if step.next then return setStep(step.next) end
        return true
    end
    return false
end

local function rgba(imgui, r, g, b, a)
    return imgui.GetColorU32Vec4(imgui.ImVec4(r, g, b, a))
end

local MASCOT_FILES = {
    neutral = "neutral.png",
    talking = "talking.png",
    waving = "waving.png",
    presenting = "presenting.png",
    point_left = "point_left.png",
    point_right = "point_right.png",
    point_down_right = "point_down_right.png",
    point_up_left = "point_up_left.png",
    point_up_right = "point_up_right.png",
    thinking = "thinking.png",
    thinking_question = "thinking_question.png",
    approval = "approval.png",
    question = "question.png",
    caution = "caution.png",
    celebration = "celebration.png",
    sad = "sad.png"
}

local BUBBLE_FILES = {
    -- "welcome" remains a semantic step name, but it must never load the
    -- center-tail PNG. Fallback uses the right-edge-tail bubble instead.
    welcome = "bubble_welcome_upper_left.png",
    welcome_upper_left = "bubble_welcome_upper_left.png",
    welcome_upper_right = "bubble_welcome_upper_right.png",
    promo_panel = "promo_panel.png"
}

local mascotTextures = {}
local mascotTextureFailed = {}
local bubbleTextures = {}
local bubbleTextureFailed = {}

local function mascotPath(pose)
    local base = ctx and ctx.assetBasePath or nil
    if type(base) ~= "string" or base == "" then return nil end
    local fileName = MASCOT_FILES[pose] or MASCOT_FILES.neutral
    local tail = base:sub(-1)
    local sep = (tail == "\\" or tail == "/") and "" or "\\"
    return base .. sep .. fileName
end

local function getMascotTexture(imgui, pose)
    pose = MASCOT_FILES[pose] and pose or "neutral"
    if mascotTextures[pose] then return mascotTextures[pose] end
    if mascotTextureFailed[pose] then return nil end
    if type(imgui.CreateTextureFromFile) ~= "function" then
        mascotTextureFailed[pose] = true
        return nil
    end
    local path = mascotPath(pose)
    if not path then
        mascotTextureFailed[pose] = true
        return nil
    end
    local ok, texture = pcall(imgui.CreateTextureFromFile, path)
    if ok and texture then
        mascotTextures[pose] = texture
        return texture
    end
    mascotTextureFailed[pose] = true
    print("[ArzMarket][Baron] texture load failed: " .. tostring(path) .. " | " .. tostring(texture))
    return nil
end

local function bubblePath(name)
    local base = ctx and ctx.assetBasePath or nil
    if type(base) ~= "string" or base == "" then return nil end
    local fileName = BUBBLE_FILES[name]
    if not fileName then return nil end
    local tail = base:sub(-1)
    local sep = (tail == "\\" or tail == "/") and "" or "\\"
    return base .. sep .. fileName
end

local function getBubbleTexture(imgui, name)
    name = BUBBLE_FILES[name] and name or nil
    if not name then return nil end
    if bubbleTextures[name] then return bubbleTextures[name] end
    if bubbleTextureFailed[name] then return nil end
    if type(imgui.CreateTextureFromFile) ~= "function" then
        bubbleTextureFailed[name] = true
        return nil
    end
    local path = bubblePath(name)
    if not path then
        bubbleTextureFailed[name] = true
        return nil
    end
    local ok, texture = pcall(imgui.CreateTextureFromFile, path)
    if ok and texture then
        bubbleTextures[name] = texture
        return texture
    end
    bubbleTextureFailed[name] = true
    print("[ArzMarket][Baron] bubble texture load failed: " .. tostring(path) .. " | " .. tostring(texture))
    return nil
end

local function drawMascotFallback(imgui, drawList, x, y, scale)
    scale = scale or 1
    local cx = x + 47 * scale
    local cy = y + 59 * scale
    local white = rgba(imgui, 0.95, 0.98, 1.0, 1)
    local blue = rgba(imgui, 0.20, 0.63, 0.95, 1)
    local pale = rgba(imgui, 0.75, 0.91, 1.0, 1)
    local dark = rgba(imgui, 0.05, 0.12, 0.18, 1)
    drawList:AddTriangleFilled(imgui.ImVec2(cx, y + 2 * scale), imgui.ImVec2(cx - 25 * scale, cy - 16 * scale), imgui.ImVec2(cx + 25 * scale, cy - 16 * scale), blue)
    drawList:AddCircleFilled(imgui.ImVec2(cx, cy), 35 * scale, white, 32)
    drawList:AddRectFilled(imgui.ImVec2(cx - 29 * scale, cy - 17 * scale), imgui.ImVec2(cx + 29 * scale, cy - 9 * scale), blue, 4 * scale)
    drawList:AddRectFilled(imgui.ImVec2(cx - 33 * scale, cy + 1 * scale), imgui.ImVec2(cx + 33 * scale, cy + 9 * scale), blue, 4 * scale)
    drawList:AddRectFilled(imgui.ImVec2(cx - 27 * scale, cy + 19 * scale), imgui.ImVec2(cx + 27 * scale, cy + 27 * scale), blue, 4 * scale)
    drawList:AddCircleFilled(imgui.ImVec2(cx, cy + 2 * scale), 18 * scale, pale, 24)
    drawList:AddCircleFilled(imgui.ImVec2(cx - 6 * scale, cy), 2.1 * scale, dark, 12)
    drawList:AddCircleFilled(imgui.ImVec2(cx + 6 * scale, cy), 2.1 * scale, dark, 12)
    drawList:AddLine(imgui.ImVec2(cx - 5 * scale, cy + 9 * scale), imgui.ImVec2(cx, cy + 12 * scale), dark, 1.5 * scale)
    drawList:AddLine(imgui.ImVec2(cx, cy + 12 * scale), imgui.ImVec2(cx + 6 * scale, cy + 9 * scale), dark, 1.5 * scale)
end

local function drawMascot(imgui, drawList, x, y, pose, size)
    local texture = getMascotTexture(imgui, pose)
    if not texture then
        drawMascotFallback(imgui, drawList, x + 10, y + 10, math.max(1, (size or 104) / 104))
        return
    end
    size = tonumber(size) or 104
    drawList:AddImage(texture, imgui.ImVec2(x, y), imgui.ImVec2(x + size, y + size), imgui.ImVec2(0, 0), imgui.ImVec2(1, 1), 4294967295)
end

local function targetPoint(anchor)
    if type(anchor) ~= "table" then return nil, nil end
    local x = tonumber(anchor.x)
    local y = tonumber(anchor.y)
    if not x or not y then return nil, nil end
    return x + (tonumber(anchor.w) or 0) * 0.5, y + (tonumber(anchor.h) or 0) * 0.5
end

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function baronScreenScale(screenW, screenH)
    local sx = math.max(1, tonumber(screenW) or BARON_BASE_SCREEN_W) / BARON_BASE_SCREEN_W
    local sy = math.max(1, tonumber(screenH) or BARON_BASE_SCREEN_H) / BARON_BASE_SCREEN_H
    return clamp(math.min(sx, sy), BARON_MIN_SCREEN_SCALE, BARON_MAX_SCREEN_SCALE)
end

local function baronTextScreenScale(screenScale)
    screenScale = tonumber(screenScale) or 1.0
    return clamp(1.0 + (screenScale - 1.0) * 0.40, 0.86, 1.10)
end

local function baronBubbleScreenScale(screenScale)
    screenScale = tonumber(screenScale) or 1.0
    return clamp(1.0 + (screenScale - 1.0) * 0.25, 0.88, 1.08)
end

local function wrappedLineCount(imgui, text, maxWidth, scale)
    text = tostring(text or "")
    scale = tonumber(scale) or 1
    local spaceWidth = imgui.CalcTextSize(" ").x * scale
    local lineWidth = 0
    local lines = 1
    local hasWord = false
    for word in text:gmatch("%S+") do
        hasWord = true
        local wordWidth = imgui.CalcTextSize(word).x * scale
        local needed = lineWidth > 0 and (spaceWidth + wordWidth) or wordWidth
        if lineWidth > 0 and lineWidth + needed > maxWidth then
            lines = lines + 1
            lineWidth = wordWidth
        else
            lineWidth = lineWidth + needed
        end
    end
    return hasWord and lines or 1
end

local function bubbleMetrics(imgui, text, choice, hasActions)
    -- All Baron messages use the same wide PNG bubble. Keep the calculated
    -- dimensions close to the source aspect ratio so the PNG is not distorted
    -- into the old procedural circle/oval shape.
    text = tostring(text or "")
    local longText = #text >= 95
    -- v225: one font size for every Baron reply. Long text changes bubble
    -- geometry only and never changes the text scale.
    local textScale = BARON_TEXT_SCALE
    local lineHeight = math.max(24, imgui.CalcTextSize("Ag").y * textScale * 1.18)
    local candidates
    if choice then
        candidates = longText and {560, 600, 640} or {520, 560, 600}
    elseif hasActions then
        candidates = longText and {500, 540, 580, 620} or {450, 490, 530}
    else
        candidates = longText and {520, 560, 600, 640} or {480, 520, 560}
    end
    local best = nil
    for _, width in ipairs(candidates) do
        local insetX = math.max(longText and 40 or 44, width * (longText and 0.085 or 0.10))
        local wrapWidth = width - insetX * 2
        local lines = wrappedLineCount(imgui, text, wrapWidth, textScale)
        local textHeight = lines * lineHeight
        local actionHeight = choice and 54 or (hasActions and 42 or 0)
        local actionGap = actionHeight > 0 and 12 or 0
        local verticalPadding = (not choice and not hasActions) and 58 or 46
        local contentHeight = 32 + textHeight + actionGap + actionHeight + verticalPadding
        local bodyHeight = math.max(contentHeight, width / 1.80)
        local ratio = width / bodyHeight
        local penalty = math.abs(ratio - 1.80) * 9000 + math.max(0, bodyHeight - 320) * 700
        local score = width * bodyHeight + penalty
        if not best or score < best.score then
            best = {
                width = width,
                bodyHeight = bodyHeight,
                totalHeight = bodyHeight,
                insetX = insetX,
                lineHeight = lineHeight,
                textScale = textScale,
                score = score
            }
        end
    end
    return best
end

local function targetLayout(imgui, screenW, screenH, params, step, text)
    local screenScale = baronScreenScale(screenW, screenH)
    local textScreenScale = baronTextScreenScale(screenScale)
    local bubbleScreenScale = baronBubbleScreenScale(screenScale)
    local choice = step.choice ~= nil
    local hasActions = choice or stepAllowsSkip(step)
    local metrics = bubbleMetrics(imgui, text, choice, hasActions)
    if step.bubble_asset == "welcome" then
        metrics = {
            width = 440,
            bodyHeight = 244,
            totalHeight = 244,
            insetX = 44,
            lineHeight = math.max(24, imgui.CalcTextSize("Ag").y * BARON_TEXT_SCALE * 1.18),
            textScale = BARON_TEXT_SCALE
        }
    end
    -- Scale the whole PNG bubble, not only the text area. This preserves the
    -- artwork proportions and gives long messages a little more breathing room.
    local bubbleScale = tonumber(step.bubble_scale) or 1.0
    local bubbleShiftX = (tonumber(step.bubble_shift_x) or 0) * screenScale
    local bubbleShiftY = (tonumber(step.bubble_shift_y) or 0) * screenScale
    local bubbleTargetXLeft = tonumber(step.bubble_target_x_left) or BUBBLE_TARGET_X_LEFT
    local bubbleTargetXRight = tonumber(step.bubble_target_x_right) or BUBBLE_TARGET_X_RIGHT
    local bubbleTargetY = tonumber(step.bubble_target_y) or BUBBLE_TARGET_Y
    local bubbleBodyW = metrics.width * BUBBLE_IMAGE_WIDTH_SCALE * bubbleScale * bubbleScreenScale
    local bubbleW = bubbleBodyW
    local bubbleAssetResolved = step.bubble_asset
    local bubbleBodyH = metrics.bodyHeight * BUBBLE_IMAGE_HEIGHT_SCALE * bubbleScale * bubbleScreenScale
    local bubbleH = metrics.totalHeight * BUBBLE_IMAGE_HEIGHT_SCALE * bubbleScale * bubbleScreenScale
    local bubbleSide = "top"
    local bubbleBodyOffsetX = 0
    local bubbleBodyOffsetY = 0
    local position = step.position or "anchor"
    local baseMascotSize = MASCOT_SIZE * screenScale
    local mascotSize = baseMascotSize * math.max(0.55, math.min(1.25, tonumber(step.mascot_scale) or 1.0))
    local mascotX = screenW - mascotSize - 18 * screenScale
    local mascotY = screenH - mascotSize - 14 * screenScale
    local bubbleX = mascotX + mascotSize * 0.50 - bubbleW * 0.72
    local bubbleY = mascotY - bubbleBodyH + 4 * screenScale

    if position == "lua_preview" and type(params.luaPreviewBounds) == "table" then
        local b = params.luaPreviewBounds
        mascotSize = baseMascotSize
        mascotX = (tonumber(b.x) or 0) - mascotSize - 10 * screenScale
        mascotY = (tonumber(b.y) or 0) + (tonumber(b.h) or 0) * 0.46 - mascotSize * 0.5
        bubbleX = mascotX + mascotSize * 0.72
        bubbleY = mascotY - bubbleBodyH * 0.72
        if step.bubble_asset == "welcome" then
            bubbleAssetResolved = "welcome_upper_right"
            bubbleX = mascotX + mascotSize - 28 * screenScale
            bubbleY = mascotY - bubbleBodyH + 18 * screenScale
        end
    elseif position == "html_preview" and type(params.htmlPreviewBounds) == "table" then
        local b = params.htmlPreviewBounds
        mascotSize = baseMascotSize
        mascotX = (tonumber(b.x) or 0) + (tonumber(b.w) or 0) + 10 * screenScale
        mascotY = (tonumber(b.y) or 0) + (tonumber(b.h) or 0) * 0.46 - mascotSize * 0.5
        bubbleX = mascotX + mascotSize * 0.48 - bubbleW * 0.72
        bubbleY = mascotY - bubbleBodyH - 4 * screenScale
        if step.bubble_asset == "welcome" then
            bubbleAssetResolved = "welcome_upper_left"
            bubbleX = mascotX - bubbleW + 36 * screenScale
            bubbleY = mascotY - bubbleBodyH + 18 * screenScale
        end
    elseif position == "base" then
        mascotSize = baseMascotSize
        mascotX = screenW - mascotSize - 18 * screenScale
        mascotY = screenH - mascotSize - 14 * screenScale
        if step.bubble_asset == "welcome" then
            bubbleAssetResolved = "welcome_upper_left"
            bubbleX = mascotX - bubbleW + 36 * screenScale
            bubbleY = mascotY - bubbleBodyH + 18 * screenScale
        else
            bubbleX = mascotX + mascotSize * 0.48 - bubbleW * 0.72
            bubbleY = mascotY - bubbleBodyH + 2 * screenScale
        end
    elseif position == "script_left" then
        local b = type(params.scriptBounds) == "table" and params.scriptBounds or nil
        if b then
            local bx = tonumber(b.x) or 0
            local by = tonumber(b.y) or 0
            local bw = tonumber(b.w) or screenW
            local bh = tonumber(b.h) or screenH
            mascotX = bx - 8 * screenScale
            mascotY = by + bh - mascotSize - 20 * screenScale
            local maxInsideX = bx + math.max(6 * screenScale, bw * 0.24 - mascotSize * 0.62)
            mascotX = math.min(mascotX, maxInsideX)
        else
            mascotX = 18 * screenScale
            mascotY = screenH - mascotSize - 20 * screenScale
        end
        bubbleX = mascotX
        bubbleY = math.max(12 * screenScale, mascotY - bubbleBodyH + mascotSize * 0.10)
    elseif position == "screen_left" then
        mascotX = 18 * screenScale
        mascotY = screenH * 0.55 - mascotSize * 0.45
        bubbleX = 18 * screenScale
        bubbleY = math.max(12 * screenScale, mascotY - bubbleBodyH + mascotSize * 0.10)
    else
        local tx, ty = targetPoint(params.anchor)
        if tx and ty then
            mascotSize = baseMascotSize
            local pose = tostring(step.pose or "")
            local pointerHotspot = type(step.pointer_hotspot) == "table" and step.pointer_hotspot or nil
            if pointerHotspot then
                local hotspotX = tonumber(pointerHotspot.x) or 0.5
                local hotspotY = tonumber(pointerHotspot.y) or 0.5
                if type(params.anchor) == "table" then
                    local anchorXFrac = tonumber(pointerHotspot.anchor_x)
                    local anchorYFrac = tonumber(pointerHotspot.anchor_y)
                    if anchorXFrac ~= nil then
                        tx = (tonumber(params.anchor.x) or tx) + (tonumber(params.anchor.w) or 0) * anchorXFrac
                    end
                    if anchorYFrac ~= nil then
                        ty = (tonumber(params.anchor.y) or ty) + (tonumber(params.anchor.h) or 0) * anchorYFrac
                    end
                end
                mascotX = tx - mascotSize * hotspotX + (tonumber(pointerHotspot.offset_x) or 0) * screenScale
                mascotY = ty - mascotSize * hotspotY + (tonumber(pointerHotspot.offset_y) or 0) * screenScale
            elseif pose == "point_right" or pose == "point_up_right" then
                mascotX = tx - mascotSize - 24 * screenScale
                mascotY = ty - mascotSize * 0.48
            elseif pose == "point_left" or pose == "point_up_left" then
                mascotX = tx + 24 * screenScale
                mascotY = ty - mascotSize * 0.48
            elseif pose == "point_down_right" then
                -- Привязываем к якорю именно кончик пальца point_down_right.png.
                -- Тело Барона больше не перекрывает resize-ручку.
                local fingerX = 0.906
                local fingerY = 0.855
                mascotX = tx - mascotSize * fingerX - 8 * screenScale
                mascotY = ty - mascotSize * fingerY - 6 * screenScale
            else
                if tx < screenW * 0.5 then mascotX = tx + 24 * screenScale else mascotX = tx - mascotSize - 24 * screenScale end
                mascotY = ty - mascotSize * 0.48
            end
            bubbleX = mascotX + mascotSize * 0.48 - bubbleW * 0.72
            bubbleY = mascotY - bubbleBodyH + 2 * screenScale
        end
    end

    local edgeInset = 8 * screenScale
    local mascotMinX = step.allow_mascot_offscreen_left == true and (-mascotSize * 0.34) or edgeInset
    mascotX = clamp(mascotX, mascotMinX, math.max(edgeInset, screenW - mascotSize - edgeInset))
    mascotY = clamp(mascotY, edgeInset, math.max(edgeInset, screenH - mascotSize - edgeInset))

    if position == "anchor" and type(params.anchor) == "table" then
        local margin = 10 * screenScale
        local tailSpace = 24 * screenScale
        local mascotCenterX = mascotX + mascotSize * 0.5
        local mascotCenterY = mascotY + mascotSize * 0.48
        local ax = tonumber(params.anchor.x) or 0
        local ay = tonumber(params.anchor.y) or 0
        local aw = tonumber(params.anchor.w) or 0
        local ah = tonumber(params.anchor.h) or 0
        local targetLeft, targetTop = ax, ay
        local targetRight, targetBottom = ax + aw, ay + ah
        local candidates = {
            { side = "top", x = mascotCenterX - bubbleBodyW * 0.5, y = mascotY - bubbleBodyH - tailSpace - 10 * screenScale, w = bubbleBodyW, h = bubbleBodyH + tailSpace, ox = 0, preference = 0 },
            { side = "left", x = mascotX - bubbleBodyW - tailSpace - 12 * screenScale, y = mascotCenterY - bubbleBodyH * 0.5, w = bubbleBodyW + tailSpace, h = bubbleBodyH, ox = 0, preference = 150 },
            { side = "right", x = mascotX + mascotSize + 12 * screenScale, y = mascotCenterY - bubbleBodyH * 0.5, w = bubbleBodyW + tailSpace, h = bubbleBodyH, ox = tailSpace, preference = 180 }
        }
        local best = nil
        for _, candidate in ipairs(candidates) do
            local rawRight = candidate.x + candidate.w
            local rawBottom = candidate.y + candidate.h
            local overflow = math.max(0, margin - candidate.x) + math.max(0, rawRight - (screenW - margin)) +
                math.max(0, margin - candidate.y) + math.max(0, rawBottom - (screenH - margin))
            local x = clamp(candidate.x, margin, math.max(margin, screenW - candidate.w - margin))
            local y = clamp(candidate.y, margin, math.max(margin, screenH - candidate.h - margin))
            local overlapW = math.max(0, math.min(x + candidate.w, targetRight) - math.max(x, targetLeft))
            local overlapH = math.max(0, math.min(y + candidate.h, targetBottom) - math.max(y, targetTop))
            local score = overflow * 100000 + overlapW * overlapH * 100 + candidate.preference
            if not best or score < best.score then
                best = { side = candidate.side, x = x, y = y, w = candidate.w, h = candidate.h, ox = candidate.ox, score = score }
            end
        end
        if best then
            bubbleSide = best.side
            bubbleX, bubbleY = best.x, best.y
            bubbleW, bubbleH = best.w, best.h
            bubbleBodyOffsetX = best.ox or 0
        end
    else
        bubbleX = clamp(bubbleX, 10 * screenScale, math.max(10 * screenScale, screenW - bubbleW - 10 * screenScale))
        bubbleY = clamp(bubbleY, 10 * screenScale, math.max(10 * screenScale, screenH - bubbleH - 10 * screenScale))
    end

    -- Bind the bubble to a visible point on Baron instead of the transparent
    -- outer square of the PNG. This keeps the bubble close to the visible head.
    local diagonalCenterX = mascotX + mascotSize * 0.5
    local baronOnRight = diagonalCenterX >= screenW * 0.5
    bubbleW = bubbleBodyW
    bubbleH = metrics.totalHeight * BUBBLE_IMAGE_HEIGHT_SCALE * bubbleScale * bubbleScreenScale
    bubbleBodyOffsetX = 0
    bubbleBodyOffsetY = 0
    bubbleSide = "top"

    if position == "script_left" then
        -- In the settings tutorial Baron is moved to the left side of the
        -- ArzMarket window, but the speech bubble must travel with him and stay
        -- above-right. Use the PNG whose tail is on the left edge of the bubble.
        bubbleAssetResolved = "welcome_upper_right"
        local bubbleTailX = bubbleW * 0.0572
        local bubbleTailY = bubbleH * 0.9859
        local targetBaronX = mascotX + mascotSize * 0.82
        local targetBaronY = mascotY + mascotSize * 0.18
        bubbleX = targetBaronX - bubbleTailX + bubbleShiftX
        bubbleY = targetBaronY - bubbleTailY + bubbleShiftY
    else
        -- Place the tail like the approved reference: the bubble sits above and
        -- to the side of Baron, while the tail aims at the upper inner part of him.
        local bubbleTailXFrac = baronOnRight and 0.9532 or 0.0572
        local bubbleTailYFrac = baronOnRight and 0.9707 or 0.9859
        local bubbleTailX = bubbleW * bubbleTailXFrac
        local bubbleTailY = bubbleH * bubbleTailYFrac
        local targetBaronX = mascotX + mascotSize * (baronOnRight and bubbleTargetXRight or bubbleTargetXLeft)
        local targetBaronY = mascotY + mascotSize * bubbleTargetY
        bubbleX = targetBaronX - bubbleTailX + bubbleShiftX
        bubbleY = targetBaronY - bubbleTailY + bubbleShiftY
        -- Every visible Baron message uses a PNG bubble. Choose the mirrored
        -- version from Baron's final on-screen side, including dynamic anchors.
        bubbleAssetResolved = baronOnRight and "welcome_upper_left" or "welcome_upper_right"
    end

    bubbleX = clamp(bubbleX, 10 * screenScale, math.max(10 * screenScale, screenW - bubbleW - 10 * screenScale))
    bubbleY = clamp(bubbleY, 10 * screenScale, math.max(10 * screenScale, screenH - bubbleH - 10 * screenScale))

    return {
        mascotSize = mascotSize,
        bubbleW = bubbleW,
        bubbleBodyW = bubbleBodyW,
        bubbleBodyH = bubbleBodyH,
        bubbleH = bubbleH,
        bubbleSide = bubbleSide,
        bubbleBodyOffsetX = bubbleBodyOffsetX,
        bubbleBodyOffsetY = bubbleBodyOffsetY,
        bubbleInsetX = metrics.insetX * 1.04 * bubbleScreenScale,
        bubbleLineHeight = metrics.lineHeight * textScreenScale,
        bubbleTextScale = metrics.textScale * textScreenScale,
        bubbleAssetResolved = bubbleAssetResolved,
        mascotX = mascotX,
        mascotY = mascotY,
        bubbleX = bubbleX,
        bubbleY = bubbleY,
        screenScale = screenScale
    }
end

local function smoothstep(t)
    t = clamp(t, 0, 1)
    return t * t * (3 - 2 * t)
end

local function applyMotion(layout, step, hardFollow)
    local key = tostring(state.current_module or "") .. ":" .. tostring(state.current_step or "")
    local now = nowMs()
    if hardFollow then
        motion.initialized = true
        motion.key = key
        motion.mascotX = layout.mascotX
        motion.mascotY = layout.mascotY
        motion.bubbleX = layout.bubbleX
        motion.bubbleY = layout.bubbleY
        motion.startAt = now
        return layout
    end

    if not motion.initialized then
        motion.initialized = true
        motion.key = key
        motion.mascotX = layout.mascotX
        motion.mascotY = layout.mascotY
        motion.bubbleX = layout.bubbleX
        motion.bubbleY = layout.bubbleY
        motion.fromMascotX = layout.mascotX
        motion.fromMascotY = layout.mascotY
        motion.fromBubbleX = layout.bubbleX
        motion.fromBubbleY = layout.bubbleY
        motion.startAt = now
    elseif motion.key ~= key then
        motion.key = key
        motion.fromMascotX = motion.mascotX
        motion.fromMascotY = motion.mascotY
        motion.fromBubbleX = motion.bubbleX
        motion.fromBubbleY = motion.bubbleY
        motion.startAt = now
    end

    local t = smoothstep((now - motion.startAt) / motion.duration)
    motion.mascotX = motion.fromMascotX + (layout.mascotX - motion.fromMascotX) * t
    motion.mascotY = motion.fromMascotY + (layout.mascotY - motion.fromMascotY) * t
    motion.bubbleX = motion.fromBubbleX + (layout.bubbleX - motion.fromBubbleX) * t
    motion.bubbleY = motion.fromBubbleY + (layout.bubbleY - motion.fromBubbleY) * t
    layout.mascotX = motion.mascotX
    layout.mascotY = motion.mascotY
    layout.bubbleX = motion.bubbleX
    layout.bubbleY = motion.bubbleY
    return layout
end

local COLOR_VALUES = {
    normal = {0.07, 0.10, 0.14, 1.0},
    blue = {0.16, 0.72, 1.0, 1.0},
    red = {0.91, 0.31, 0.27, 1.0},
    green = {0.13, 0.68, 0.39, 1.0}
}

local function colorVec(imgui, name)
    local value = COLOR_VALUES[name] or COLOR_VALUES.normal
    return imgui.ImVec4(value[1], value[2], value[3], value[4])
end

local function textTokens(text)
    local chars = splitUtf8(text)
    local out = {}
    local buffer = ""
    local bufferSpace = nil
    local function flush()
        if buffer ~= "" then
            out[#out + 1] = {text = buffer, space = bufferSpace == true}
            buffer = ""
        end
    end
    for _, ch in ipairs(chars) do
        local isSpace = ch == " " or ch == "\t"
        local isNewline = ch == "\n" or ch == "\r"
        if isNewline then
            flush()
            out[#out + 1] = {newline = true}
            bufferSpace = nil
        elseif bufferSpace == nil or bufferSpace == isSpace then
            bufferSpace = isSpace
            buffer = buffer .. ch
        else
            flush()
            bufferSpace = isSpace
            buffer = ch
        end
    end
    flush()
    return out
end

local function drawSegmentedText(imgui, segments, startX, startY, maxWidth, scale)
    if imgui.SetWindowFontScale then imgui.SetWindowFontScale(scale or 1) end
    local x = startX
    local y = startY
    local lineHeight = math.max(22, imgui.CalcTextSize("Ag").y * 1.18)
    local maxX = startX + maxWidth

    for _, segment in ipairs(segments or {}) do
        local color = colorVec(imgui, segment.color)
        for _, token in ipairs(textTokens(segment.text)) do
            if token.newline then
                x = startX
                y = y + lineHeight
            else
                local width = imgui.CalcTextSize(token.text).x
                if not token.space and x > startX and x + width > maxX then
                    x = startX
                    y = y + lineHeight
                end
                if not (token.space and x == startX) then
                    imgui.SetCursorPos(imgui.ImVec2(x, y))
                    imgui.TextColored(color, token.text)
                    x = x + width
                end
            end
        end
    end
    if imgui.SetWindowFontScale then imgui.SetWindowFontScale(1.0) end
end

local function drawSegmentedTextCentered(imgui, segments, regionX, regionY, regionW, regionH, scale)
    if imgui.SetWindowFontScale then imgui.SetWindowFontScale(scale or 1) end
    local lineHeight = math.max(22, imgui.CalcTextSize("Ag").y * 1.18)
    local lines = { { runs = {}, width = 0 } }
    local current = lines[1]

    local function newLine()
        current = { runs = {}, width = 0 }
        lines[#lines + 1] = current
    end

    for _, segment in ipairs(segments or {}) do
        for _, token in ipairs(textTokens(segment.text)) do
            if token.newline then
                newLine()
            else
                local width = imgui.CalcTextSize(token.text).x
                if not token.space and current.width > 0 and current.width + width > regionW then
                    newLine()
                end
                if not (token.space and current.width == 0) then
                    current.runs[#current.runs + 1] = {
                        text = token.text,
                        color = segment.color,
                        width = width
                    }
                    current.width = current.width + width
                end
            end
        end
    end

    while #lines > 1 and #lines[#lines].runs == 0 do
        table.remove(lines)
    end

    local totalHeight = #lines * lineHeight
    local y = regionY + math.max(0, (regionH - totalHeight) * 0.5)
    for _, line in ipairs(lines) do
        local x = regionX + math.max(0, (regionW - line.width) * 0.5)
        for _, run in ipairs(line.runs) do
            imgui.SetCursorPos(imgui.ImVec2(x, y))
            imgui.TextColored(colorVec(imgui, run.color), run.text)
            x = x + run.width
        end
        y = y + lineHeight
    end
    if imgui.SetWindowFontScale then imgui.SetWindowFontScale(1.0) end
end

local function openBaronPromoLink(url)
    url = tostring(url or "")
    if url == "" then return false end
    if ctx and type(ctx.openUrl) == "function" then
        local ok, result = pcall(ctx.openUrl, url)
        if ok and result ~= false then return true end
    end
    if type(openUrl) == "function" then
        local ok, result = pcall(openUrl, url)
        if ok and result ~= false then return true end
    end
    return false
end

local function drawPromoWindowHtmlLike(imgui, step, screenW, screenH)
    local panelRatio = 948 / 1376
    local height = math.min(960, math.max(760, screenH * 0.95))
    local width = height * panelRatio
    if width > screenW - 20 then
        width = math.max(440, screenW - 20)
        height = width / panelRatio
    end
    local x = (screenW - width) * 0.5
    local y = (screenH - height) * 0.5
    local bgdl = imgui.GetBackgroundDrawList and imgui.GetBackgroundDrawList() or nil
    if bgdl then
        bgdl:AddRectFilled(imgui.ImVec2(0, 0), imgui.ImVec2(screenW, screenH), rgba(imgui, 0.04, 0.08, 0.14, 0.78))
    end
    local panelTexture = getBubbleTexture(imgui, "promo_panel")
    local useFallbackPanel = panelTexture == nil

    imgui.SetNextWindowPos(imgui.ImVec2(x, y), imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(width, height), imgui.Cond.Always)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(70, 72))
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, useFallbackPanel and 30 or 0)
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 0)
    imgui.PushStyleColor(imgui.Col.WindowBg, useFallbackPanel and imgui.ImVec4(0.96, 0.97, 0.99, 0.98) or imgui.ImVec4(0.0, 0.0, 0.0, 0.0))
    imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0.0, 0.0, 0.0, 0.0))
    imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.0, 0.0, 0.0, 0.0))
    if imgui.SetNextWindowFocus then imgui.SetNextWindowFocus() end
    imgui.Begin("##ArzMarketBaronPromoWindow", nil,
        imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoTitleBar +
        imgui.WindowFlags.NoMove + imgui.WindowFlags.NoSavedSettings)

    if panelTexture and imgui.GetWindowDrawList then
        local wp = imgui.GetWindowPos()
        local dl = imgui.GetWindowDrawList()
        dl:AddImage(panelTexture, imgui.ImVec2(wp.x, wp.y), imgui.ImVec2(wp.x + width, wp.y + height))
    elseif imgui.GetWindowDrawList then
        local wp = imgui.GetWindowPos()
        local dl = imgui.GetWindowDrawList()
        local shadow = rgba(imgui, 0.08, 0.14, 0.22, 0.18)
        dl:AddRectFilled(imgui.ImVec2(wp.x + 8, wp.y + 12), imgui.ImVec2(wp.x + width + 8, wp.y + height + 12), shadow, 30)
    end

    local lines = type(step.promo_lines) == "table" and step.promo_lines or {}
    local buttonLabel = tostring(step.promo_button_text or "Понятно")
    local linkLabel = tostring(step.promo_link_label or "")
    local linkIntro = tostring(step.promo_link_intro or "Нажми на эту ссылку:")
    local linkUrl = tostring(step.promo_link_url or "")
    local availableW = math.max(120, imgui.GetContentRegionAvail().x)
    local buttonH = 38
    local buttonAreaH = buttonH + 12
    local textAreaH = math.max(120, imgui.GetContentRegionAvail().y - buttonAreaH)

    imgui.BeginChild("##ArzMarketBaronPromoWindowText", imgui.ImVec2(availableW, textAreaH), false)
    local promoRedFrom = tonumber(step.promo_red_from) or (#lines + 1)
    if imgui.SetWindowFontScale then imgui.SetWindowFontScale(1.00) end
    for index, line in ipairs(lines) do
        local trimmed = tostring(line or "")
        if trimmed == "" then
            imgui.Dummy(imgui.ImVec2(1, 8))
        else
            local isRed = index >= promoRedFrom
            local isHeading = index == 1
            if isRed then
                imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.88, 0.08, 0.08, 1.0))
            else
                imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.08, 0.12, 0.18, 1.0))
            end
            if imgui.SetWindowFontScale then
                imgui.SetWindowFontScale(isHeading and 1.15 or (isRed and 1.06 or 1.00))
            end
            imgui.TextWrapped(trimmed)
            imgui.PopStyleColor(1)
            if index < #lines or linkLabel ~= "" then imgui.Dummy(imgui.ImVec2(1, isRed and 16 or 14)) end
        end
    end
    if linkLabel ~= "" and linkUrl ~= "" then
        if linkIntro ~= "" then
            imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.49, 0.12, 0.10, 1.0))
            if imgui.SetWindowFontScale then imgui.SetWindowFontScale(1.00) end
            local introSize = imgui.CalcTextSize(linkIntro)
            imgui.SetCursorPosX(math.max(0, (availableW - introSize.x) * 0.5))
            imgui.Text(linkIntro)
            imgui.PopStyleColor(1)
            imgui.Dummy(imgui.ImVec2(1, 10))
        end
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.0, 0.0, 0.0, 0.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.0, 0.0, 0.0, 0.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.0, 0.0, 0.0, 0.0))
        local rainbowPhase = ((nowMs() % 4200) / 4200) * math.pi * 2
        local rainbowR = 0.62 + 0.38 * math.sin(rainbowPhase)
        local rainbowG = 0.62 + 0.38 * math.sin(rainbowPhase + 2.09439510239)
        local rainbowB = 0.62 + 0.38 * math.sin(rainbowPhase + 4.18879020479)
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(rainbowR, rainbowG, rainbowB, 1.0))
        if imgui.SetWindowFontScale then imgui.SetWindowFontScale(1.08) end
        local linkSize = imgui.CalcTextSize(linkLabel)
        local linkX = math.max(0, (availableW - linkSize.x) * 0.5)
        imgui.SetCursorPosX(linkX)
        if imgui.SmallButton(linkLabel .. "##baron_promo_link") then
            openBaronPromoLink(linkUrl)
        end
        imgui.PopStyleColor(4)
    end
    if imgui.SetWindowFontScale then imgui.SetWindowFontScale(1.0) end
    imgui.EndChild()

    local remain = getSkipCooldownMs(step)
    local ready = remain <= 0
    local label = buttonLabel
    if not ready then
        label = string.format("%s (%d)", buttonLabel, math.ceil(remain / 1000))
    end

    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 20)
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameBorderSize, 0)
    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.90, 0.94, 0.98, 1))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.84, 0.91, 0.97, 1))
    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.80, 0.88, 0.95, 1))
    imgui.PushStyleColor(imgui.Col.Text, ready and imgui.ImVec4(0.29, 0.43, 0.60, 1) or imgui.ImVec4(0.55, 0.64, 0.75, 1))
    local cursorX = math.max(0, (availableW - 190) * 0.5)
    imgui.SetCursorPosX(cursorX)
    local clicked = imgui.Button(label .. "##baron_promo_close", imgui.ImVec2(190, buttonH))
    if ready and clicked then M.skip() end
    imgui.PopStyleColor(4)
    imgui.PopStyleVar(2)

    imgui.End()
    imgui.PopStyleColor(3)
    imgui.PopStyleVar(3)
    return true
end

function M.render(imgui, params)
    params = params or {}
    if not M.isActive() then return false end
    local step = currentStep()
    if not step then return false end

    local screenW = tonumber(params.screenWidth) or 1920
    local screenH = tonumber(params.screenHeight) or 1080
    local segments = normalizeSegments(step)
    local text = plainText(segments)

    local position = tostring(step.position or "anchor")
    local requiresAnchor = step.target ~= nil and position == "anchor" and step.optional_anchor ~= true
    local hasAnchor = type(params.anchor) == "table" and tonumber(params.anchor.x) ~= nil and tonumber(params.anchor.y) ~= nil
    if requiresAnchor and not hasAnchor then
        local watchKey = tostring(state.current_module or "") .. ":" .. tostring(state.current_step or "") .. ":" .. tostring(step.target or "")
        local now = nowMs()
        if missingAnchorWatch.key ~= watchKey then
            missingAnchorWatch.key = watchKey
            missingAnchorWatch.since = now
            missingAnchorWatch.logged = false
        elseif not missingAnchorWatch.logged and now - missingAnchorWatch.since >= 900 then
            print("[ArzMarket][Baron] anchor missing: " .. tostring(step.target))
            missingAnchorWatch.logged = true
        end
    else
        missingAnchorWatch.key = nil
        missingAnchorWatch.since = 0
        missingAnchorWatch.logged = false
    end

    local layout = targetLayout(imgui, screenW, screenH, params, step, text)
    layout = applyMotion(layout, step, step.follow_anchor == true)
    local showBubble = step.silent ~= true and state.dismissed_step ~= state.current_step
    local showPromoWindow = step.promo_window == true
    local hideMascot = step.hide_mascot == true

    if not hideMascot then
        imgui.SetNextWindowPos(imgui.ImVec2(layout.mascotX, layout.mascotY), imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(layout.mascotSize, layout.mascotSize), imgui.Cond.Always)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(0, 0))
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 0)
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 0)
    imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0, 0, 0, 0))
    if imgui.SetNextWindowFocus then imgui.SetNextWindowFocus() end
    imgui.Begin("##ArzMarketBaronMascot", nil,
        imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoTitleBar +
        imgui.WindowFlags.NoMove + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoSavedSettings +
        imgui.WindowFlags.NoBackground + imgui.WindowFlags.NoInputs)
    local mascotDrawList = imgui.GetWindowDrawList()
    local mascotWindowPos = imgui.GetWindowPos()
    drawMascot(imgui, mascotDrawList, mascotWindowPos.x, mascotWindowPos.y, step.pose or "neutral", layout.mascotSize)
        imgui.End()
        imgui.PopStyleColor(2)
        imgui.PopStyleVar(3)
    end

    if showPromoWindow then
        return drawPromoWindowHtmlLike(imgui, step, screenW, screenH)
    end

    if not showBubble then return true end

    imgui.SetNextWindowPos(imgui.ImVec2(layout.bubbleX, layout.bubbleY), imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(layout.bubbleW, layout.bubbleH), imgui.Cond.Always)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(0, 0))
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 0)
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 0)
    imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0, 0, 0, 0))
    if imgui.SetNextWindowFocus then imgui.SetNextWindowFocus() end
    imgui.Begin("##ArzMarketBaronAssistant", nil,
        imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoTitleBar +
        imgui.WindowFlags.NoMove + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoSavedSettings +
        imgui.WindowFlags.NoBackground)

    local dl = imgui.GetWindowDrawList()
    local wp = imgui.GetWindowPos()
    local uiScale = tonumber(layout.screenScale) or 1
    local bodyOffsetX = tonumber(layout.bubbleBodyOffsetX) or 0
    local bodyOffsetY = tonumber(layout.bubbleBodyOffsetY) or 0
    local bodyWidth = tonumber(layout.bubbleBodyW) or layout.bubbleW
    local bodyTop = wp.y + bodyOffsetY + 2 * uiScale
    local bodyHeight = layout.bubbleBodyH
    local bodyLeft = wp.x + bodyOffsetX + 2 * uiScale
    local bodyRight = wp.x + bodyOffsetX + bodyWidth - 2 * uiScale
    local bodyBottom = bodyTop + bodyHeight
    local radius = bodyHeight * 0.5
    local leftCenterX = bodyLeft + radius
    local rightCenterX = bodyRight - radius
    if rightCenterX < leftCenterX then
        local center = (bodyLeft + bodyRight) * 0.5
        leftCenterX = center
        rightCenterX = center
    end
    local centerY = bodyTop + radius
    local mascotCenterX = layout.mascotX + layout.mascotSize * 0.5
    local bubbleIsLeftOfBaron = layout.bubbleX < mascotCenterX
    local mascotCenterY = layout.mascotY + layout.mascotSize * 0.48
    local visualBaronX = layout.mascotX + layout.mascotSize * (bubbleIsLeftOfBaron and 0.48 or 0.52)
    local visualBaronY = layout.mascotY + layout.mascotSize * 0.18
    local tailHalf = 13 * uiScale
    local shadow = rgba(imgui, 0, 0, 0, 0.13)
    local bubbleFill = rgba(imgui, 0.99, 0.995, 1.0, 0.995)
    local photoBubbleKey = tostring(layout.bubbleAssetResolved or step.bubble_asset or "")
    local usingPhotoBubble = photoBubbleKey ~= "" and getBubbleTexture(imgui, photoBubbleKey) ~= nil

    if usingPhotoBubble then
        local bubbleTexture = getBubbleTexture(imgui, photoBubbleKey)
        if bubbleTexture and dl.AddImage then
            dl:AddImage(bubbleTexture, imgui.ImVec2(wp.x, wp.y), imgui.ImVec2(wp.x + layout.bubbleW, wp.y + layout.bubbleH))
        else
            usingPhotoBubble = false
        end
    end

    if not usingPhotoBubble then
        local sx = 4 * uiScale
        local sy = 6 * uiScale
        dl:AddCircleFilled(imgui.ImVec2(leftCenterX + sx, centerY + sy), radius, shadow, 64)
        if rightCenterX > leftCenterX + 1 then
            dl:AddCircleFilled(imgui.ImVec2(rightCenterX + sx, centerY + sy), radius, shadow, 64)
            dl:AddRectFilled(imgui.ImVec2(leftCenterX + sx, bodyTop + sy), imgui.ImVec2(rightCenterX + sx, bodyBottom + sy), shadow, 0)
        end

        local side = tostring(layout.bubbleSide or "top")
        if side == "left" then
            local tailY = clamp(visualBaronY, bodyTop + 44 * uiScale, bodyBottom - 44 * uiScale)
            local tailTipX = wp.x + layout.bubbleW - 2 * uiScale
            dl:AddTriangleFilled(imgui.ImVec2(bodyRight - 5 * uiScale + sx, tailY - tailHalf + sy), imgui.ImVec2(bodyRight - 5 * uiScale + sx, tailY + tailHalf + sy), imgui.ImVec2(tailTipX + sx, tailY + sy), shadow)
        elseif side == "right" then
            local tailY = clamp(visualBaronY, bodyTop + 44 * uiScale, bodyBottom - 44 * uiScale)
            local tailTipX = wp.x + 2 * uiScale
            dl:AddTriangleFilled(imgui.ImVec2(bodyLeft + 5 * uiScale + sx, tailY - tailHalf + sy), imgui.ImVec2(bodyLeft + 5 * uiScale + sx, tailY + tailHalf + sy), imgui.ImVec2(tailTipX + sx, tailY + sy), shadow)
        else
            local tailTipX = clamp(visualBaronX, bodyLeft + 44 * uiScale, bodyRight - 44 * uiScale)
            local tailTipY = wp.y + layout.bubbleH - 2 * uiScale
            dl:AddTriangleFilled(imgui.ImVec2(tailTipX - tailHalf + sx, bodyBottom - 5 + sy), imgui.ImVec2(tailTipX + tailHalf + sx, bodyBottom - 5 + sy), imgui.ImVec2(tailTipX + sx, tailTipY + sy), shadow)
        end

        dl:AddCircleFilled(imgui.ImVec2(leftCenterX, centerY), radius, bubbleFill, 64)
        if rightCenterX > leftCenterX + 1 then
            dl:AddCircleFilled(imgui.ImVec2(rightCenterX, centerY), radius, bubbleFill, 64)
            dl:AddRectFilled(imgui.ImVec2(leftCenterX, bodyTop), imgui.ImVec2(rightCenterX, bodyBottom), bubbleFill, 0)
        end
        local side = tostring(layout.bubbleSide or "top")
        if side == "left" then
            local tailY = clamp(visualBaronY, bodyTop + 44 * uiScale, bodyBottom - 44 * uiScale)
            local tailTipX = wp.x + layout.bubbleW - 2 * uiScale
            dl:AddTriangleFilled(imgui.ImVec2(bodyRight - 6 * uiScale, tailY - tailHalf), imgui.ImVec2(bodyRight - 6 * uiScale, tailY + tailHalf), imgui.ImVec2(tailTipX, tailY), bubbleFill)
        elseif side == "right" then
            local tailY = clamp(visualBaronY, bodyTop + 44 * uiScale, bodyBottom - 44 * uiScale)
            local tailTipX = wp.x + 2 * uiScale
            dl:AddTriangleFilled(imgui.ImVec2(bodyLeft + 6 * uiScale, tailY - tailHalf), imgui.ImVec2(bodyLeft + 6 * uiScale, tailY + tailHalf), imgui.ImVec2(tailTipX, tailY), bubbleFill)
        else
            local tailTipX = clamp(visualBaronX, bodyLeft + 44 * uiScale, bodyRight - 44 * uiScale)
            local tailTipY = wp.y + layout.bubbleH - 2 * uiScale
            dl:AddTriangleFilled(imgui.ImVec2(tailTipX - tailHalf, bodyBottom - 6), imgui.ImVec2(tailTipX + tailHalf, bodyBottom - 6), imgui.ImVec2(tailTipX, tailTipY), bubbleFill)
        end
    end

    local visible = visibleSegments(step)
    local insetX = layout.bubbleInsetX
    local bodyLocalX = bodyLeft - wp.x
    local actionRegionX, actionRegionW = bodyLocalX, bodyWidth
    if usingPhotoBubble then
        local textRegionX = math.max(42 * uiScale, insetX)
        local textRegionY = 24 * uiScale
        local textRegionW = math.max(120 * uiScale, layout.bubbleW - textRegionX * 2)
        local hasMessageLink = tostring(step.message_link_label or "") ~= "" and tostring(step.message_link_url or "") ~= ""
        local hasBubbleActions = step.choice ~= nil or stepAllowsSkip(step) or hasMessageLink
        local reservedBottom = (hasMessageLink and 126 or (hasBubbleActions and 104 or 74)) * uiScale
        local textRegionH = math.max(90 * uiScale, layout.bubbleH - textRegionY - reservedBottom)
        actionRegionX = textRegionX + 4 * uiScale
        actionRegionW = math.max(170 * uiScale, textRegionW - 18 * uiScale)
        -- Keep all text inside the opaque white part of the PNG.
        drawSegmentedTextCentered(imgui, visible, textRegionX, textRegionY, textRegionW, textRegionH, layout.bubbleTextScale or BARON_TEXT_SCALE)
    elseif step.choice ~= nil then
        -- Choice bubbles use two completely separate safe areas: text above,
        -- buttons below. This prevents text and controls from ever overlapping.
        local textRegionX = bodyLocalX + insetX
        local textRegionY = (bodyTop - wp.y) + 18 * uiScale
        local textRegionW = math.max(180 * uiScale, bodyWidth - insetX * 2)
        local textRegionH = math.max(96 * uiScale, bodyHeight - 116 * uiScale)
        actionRegionX = bodyLocalX + insetX
        actionRegionW = math.max(200 * uiScale, bodyWidth - insetX * 2)
        drawSegmentedTextCentered(imgui, visible, textRegionX, textRegionY, textRegionW, textRegionH, layout.bubbleTextScale or BARON_TEXT_SCALE)
    else
        local textY = bodyTop + math.max(22 * uiScale, bodyHeight * 0.11)
        local textWidth = bodyWidth - insetX * 2
        local textX = bodyLocalX + (bodyWidth - textWidth) * 0.5
        drawSegmentedText(imgui, visible, textX, textY - wp.y, textWidth, layout.bubbleTextScale or BARON_TEXT_SCALE)
    end

    local actionY
    if usingPhotoBubble then
        actionY = wp.y + layout.bubbleH - 72 * uiScale
    elseif step.choice ~= nil then
        actionY = bodyTop + bodyHeight - 64 * uiScale
    else
        actionY = bodyTop + bodyHeight - 48 * uiScale
    end
    if imgui.SetWindowFontScale then imgui.SetWindowFontScale(uiScale) end
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 18 * uiScale)
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameBorderSize, 0)

    if step.choice == "interface" then
        local oldW, newW, gap = 132 * uiScale, 132 * uiScale, 12 * uiScale
        local totalW = oldW + newW + gap
        imgui.SetCursorPos(imgui.ImVec2(actionRegionX + (actionRegionW - totalW) * 0.5, actionY - wp.y))
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.90, 0.33, 0.27, 1))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.96, 0.39, 0.32, 1))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.82, 0.27, 0.22, 1))
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1, 1, 1, 1))
        if imgui.Button("Старый##baron_interface_lua", imgui.ImVec2(oldW, 38 * uiScale)) then M.selectInterface("lua") end
        imgui.PopStyleColor(4)
        imgui.SameLine(0, gap)
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.13, 0.68, 0.39, 1))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.17, 0.76, 0.45, 1))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.10, 0.59, 0.33, 1))
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1, 1, 1, 1))
        if imgui.Button("Новый##baron_interface_html", imgui.ImVec2(newW, 38 * uiScale)) then M.selectInterface("html") end
        imgui.PopStyleColor(4)
    elseif step.choice == "lua_redirect" then
        local yesW, noW, gap = 132 * uiScale, 132 * uiScale, 12 * uiScale
        local totalW = yesW + noW + gap
        local remainingNoMs = getChoiceNoCooldownMs(step)
        local noReady = remainingNoMs <= 0
        local noLabel = getChoiceNoCooldownLabel(step, remainingNoMs)
        imgui.SetCursorPos(imgui.ImVec2(actionRegionX + (actionRegionW - totalW) * 0.5, actionY - wp.y))
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.13, 0.68, 0.39, 1))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.17, 0.76, 0.45, 1))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.10, 0.59, 0.33, 1))
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1, 1, 1, 1))
        if imgui.Button("Да##baron_lua_redirect_yes", imgui.ImVec2(yesW, 38 * uiScale)) then M.chooseLuaRedirect(true) end
        imgui.PopStyleColor(4)
        imgui.SameLine(0, gap)
        imgui.PushStyleColor(imgui.Col.Button, noReady and imgui.ImVec4(0.90, 0.94, 0.98, 1) or imgui.ImVec4(0.78, 0.84, 0.90, 1))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, noReady and imgui.ImVec4(0.84, 0.91, 0.97, 1) or imgui.ImVec4(0.78, 0.84, 0.90, 1))
        imgui.PushStyleColor(imgui.Col.ButtonActive, noReady and imgui.ImVec4(0.80, 0.88, 0.95, 1) or imgui.ImVec4(0.78, 0.84, 0.90, 1))
        imgui.PushStyleColor(imgui.Col.Text, noReady and imgui.ImVec4(0.29, 0.43, 0.60, 1) or imgui.ImVec4(0.45, 0.53, 0.62, 1))
        local clickedNo = imgui.Button(noLabel .. "##baron_lua_redirect_no", imgui.ImVec2(noW, 38 * uiScale))
        imgui.PopStyleColor(4)
        if noReady and clickedNo then M.chooseLuaRedirect(false) end
    elseif step.choice == "future_details" then
        local yesW, noW, gap = 132 * uiScale, 286 * uiScale, 12 * uiScale
        local totalW = yesW + noW + gap
        local remainingNoMs = getChoiceNoCooldownMs(step)
        local noReady = false
        local noLabel = getChoiceNoCooldownLabel(step, remainingNoMs)
        imgui.SetCursorPos(imgui.ImVec2(actionRegionX + (actionRegionW - totalW) * 0.5, actionY - wp.y))
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.13, 0.68, 0.39, 1))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.17, 0.76, 0.45, 1))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.10, 0.59, 0.33, 1))
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1, 1, 1, 1))
        if imgui.Button("Да##baron_future_details_yes", imgui.ImVec2(yesW, 38 * uiScale)) then M.chooseFutureDetails(true) end
        imgui.PopStyleColor(4)
        imgui.SameLine(0, gap)
        imgui.PushStyleColor(imgui.Col.Button, noReady and imgui.ImVec4(0.90, 0.94, 0.98, 1) or imgui.ImVec4(0.78, 0.84, 0.90, 1))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, noReady and imgui.ImVec4(0.84, 0.91, 0.97, 1) or imgui.ImVec4(0.78, 0.84, 0.90, 1))
        imgui.PushStyleColor(imgui.Col.ButtonActive, noReady and imgui.ImVec4(0.80, 0.88, 0.95, 1) or imgui.ImVec4(0.78, 0.84, 0.90, 1))
        imgui.PushStyleColor(imgui.Col.Text, noReady and imgui.ImVec4(0.29, 0.43, 0.60, 1) or imgui.ImVec4(0.45, 0.53, 0.62, 1))
        local clickedNo = imgui.Button(noLabel .. "##baron_future_details_no", imgui.ImVec2(noW, 38 * uiScale))
        imgui.PopStyleColor(4)
        if noReady and clickedNo then M.chooseFutureDetails(false) end
    elseif step.choice == "tutorial" then
        local gap = 10 * uiScale
        local buttonH = 42 * uiScale
        local totalAvailableW = math.max(310 * uiScale, actionRegionW - 16 * uiScale)
        local acceptW = math.min(200 * uiScale, math.max(180 * uiScale, totalAvailableW * 0.62))
        local laterW = math.min(112 * uiScale, math.max(100 * uiScale, totalAvailableW - acceptW - gap))
        local totalW = acceptW + laterW + gap
        if totalW > totalAvailableW then
            acceptW = math.max(170 * uiScale, totalAvailableW - laterW - gap)
            totalW = acceptW + laterW + gap
        end
        local actionX = actionRegionX + math.max(0, (actionRegionW - totalW) * 0.5)
        imgui.SetCursorPos(imgui.ImVec2(actionX, actionY - wp.y))
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.13, 0.52, 0.82, 1))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.17, 0.59, 0.90, 1))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.11, 0.47, 0.75, 1))
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1, 1, 1, 1))
        local acceptClicked = imgui.Button("Пройти обучение##baron_accept", imgui.ImVec2(acceptW, buttonH))
        imgui.PopStyleColor(4)
        if acceptClicked then M.chooseTutorial(true) end

        imgui.SameLine(0, gap)
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.90, 0.94, 0.98, 1))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.84, 0.91, 0.97, 1))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.80, 0.88, 0.95, 1))
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.29, 0.43, 0.60, 1))
        local laterClicked = imgui.Button("Позже##baron_decline", imgui.ImVec2(laterW, buttonH))
        imgui.PopStyleColor(4)
        if laterClicked then M.chooseTutorial(false) end
    elseif tostring(step.message_link_label or "") ~= "" and tostring(step.message_link_url or "") ~= "" then
        local linkLabel = tostring(step.message_link_label)
        local linkUrl = tostring(step.message_link_url)
        local linkW = math.min(250 * uiScale, math.max(190 * uiScale, imgui.CalcTextSize(linkLabel).x + 34 * uiScale))
        local linkY = actionY - wp.y - 40 * uiScale
        imgui.SetCursorPos(imgui.ImVec2(bodyLocalX + (bodyWidth - linkW) * 0.5, linkY))
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.90, 0.94, 0.98, 1))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.84, 0.91, 0.97, 1))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.80, 0.88, 0.95, 1))
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.10, 0.45, 0.82, 1))
        if imgui.Button(linkLabel .. "##baron_message_link", imgui.ImVec2(linkW, 34 * uiScale)) then
            openBaronPromoLink(linkUrl)
        end
        imgui.PopStyleColor(4)
        if stepAllowsSkip(step) then
            local skipW = 146 * uiScale
            imgui.SetCursorPos(imgui.ImVec2(bodyLocalX + (bodyWidth - skipW) * 0.5, actionY - wp.y + 2 * uiScale))
            local remainingSkipMs = getSkipCooldownMs(step)
            local skipReady = remainingSkipMs <= 0
            local skipLabel = "Завершить##baron_skip_current"
            if not skipReady then
                skipLabel = string.format("Завершить (%d)##baron_skip_current", math.ceil(remainingSkipMs / 1000))
            end
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.90, 0.94, 0.98, 1))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.84, 0.91, 0.97, 1))
            imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.80, 0.88, 0.95, 1))
            imgui.PushStyleColor(imgui.Col.Text, skipReady and imgui.ImVec4(0.29, 0.43, 0.60, 1) or imgui.ImVec4(0.55, 0.64, 0.75, 1))
            local clickedSkip = imgui.Button(skipLabel, imgui.ImVec2(skipW, 38 * uiScale))
            if skipReady and clickedSkip then M.skip() end
            imgui.PopStyleColor(4)
        end
    elseif stepAllowsSkip(step) then
        local skipW = 146 * uiScale
        imgui.SetCursorPos(imgui.ImVec2(bodyLocalX + (bodyWidth - skipW) * 0.5, actionY - wp.y))
        local remainingSkipMs = getSkipCooldownMs(step)
        local skipReady = remainingSkipMs <= 0
        local skipLabel = "Пропустить##baron_skip_current"
        if not skipReady then
            skipLabel = string.format("Пропустить (%d)##baron_skip_current", math.ceil(remainingSkipMs / 1000))
        end
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.90, 0.94, 0.98, 1))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.84, 0.91, 0.97, 1))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.80, 0.88, 0.95, 1))
        imgui.PushStyleColor(imgui.Col.Text, skipReady and imgui.ImVec4(0.29, 0.43, 0.60, 1) or imgui.ImVec4(0.55, 0.64, 0.75, 1))
        local clickedSkip = imgui.Button(skipLabel, imgui.ImVec2(skipW, 38 * uiScale))
        if skipReady and clickedSkip then M.skip() end
        imgui.PopStyleColor(4)
    end

    imgui.PopStyleVar(2)
    if imgui.SetWindowFontScale then imgui.SetWindowFontScale(1.0) end
    imgui.End()
    imgui.PopStyleColor(2)
    imgui.PopStyleVar(3)
    return true
end

function M.pageFromId(id)
    return PAGE_BY_ID[tonumber(id)]
end

return M
