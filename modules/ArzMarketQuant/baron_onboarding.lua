local M = {}

M.ID = "onboarding"
M.START_STEP = "welcome"

local function segments(...)
    local out = {}
    local values = {...}
    for i = 1, #values, 2 do
        out[#out + 1] = {
            text = tostring(values[i] or ""),
            color = tostring(values[i + 1] or "normal")
        }
    end
    return out
end

M.STEPS = {
    welcome = {
        pose = "waving",
        position = "base",
        bubble_asset = "welcome",
        bubble_text_align = "center",
        segments = segments(
            "Привет, меня зовут ", "normal",
            "Барон дю Валлон де Брасье де Пьерфон", "blue",
            ". Я твой личный помощник по торговле.", "normal"
        ),
        start_tutorial = "html",
        auto_advance_ms = 350
    }
}

local function clone(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = clone(v) end
    return out
end

function M.getStep(stepId)
    local step = M.STEPS[stepId]
    return step and clone(step) or nil
end

return M
