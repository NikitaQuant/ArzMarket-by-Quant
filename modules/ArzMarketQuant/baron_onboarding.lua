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
        next = "interfaces_intro"
    },
    interfaces_intro = {
        pose = "presenting",
        position = "base",
        text = "Для начала давай выберем интерфейс ArzMarket. Я покажу тебе оба варианта по очереди.",
        next = "lua_intro_1"
    },
    lua_intro_1 = {
        pose = "point_up_left",
        position = "base",
        text = "Сначала старый Lua-интерфейс ArzMarket. Это оригинальный интерфейс, созданный Ыреймом, разработчиком ArzMarket.",
        next = "lua_look"
    },
    lua_look = {
        pose = "talking",
        position = "base",
        text = "Теперь посмотри сам Lua-интерфейс. Можешь переключать разделы и нажимать кнопки, я подожду.",
        skip_delay_ms = 30000,
        next = "html_intro_1"
    },
    html_intro_1 = {
        pose = "point_left",
        position = "base",
        text = "А теперь новый HTML-интерфейс. Он современнее, удобнее и практичнее. Это переработанная визуальная версия ArzMarket.",
        next = "html_look"
    },
    html_look = {
        pose = "talking",
        position = "base",
        text = "Теперь посмотри сам HTML-интерфейс. Можешь переключать разделы и нажимать кнопки, я подожду.",
        skip_delay_ms = 30000,
        next = "interface_choose"
    },
    interface_choose = {
        pose = "thinking_question",
        position = "base",
        text = "Теперь ты увидел оба интерфейса. Какой тебе нравится больше? В любой момент ты сможешь изменить его в Настройках.",
        choice = "interface"
    },
    interface_loading = {
        pose = "neutral",
        position = "base",
        silent = true,
        wait = "interface_loading"
    },
    tutorial_offer = {
        pose = "question",
        position = "base",
        choice = "tutorial",
        dynamic = true
    },
    lua_disabled_1 = {
        pose = "approval",
        position = "base",
        text = "Ебись с этим интерфейсом как хочешь.",
        next = "lua_disabled_1_more"
    },
    lua_disabled_1_more = {
        pose = "approval",
        position = "base",
        text = "На этот интерфейс пока что нет ни обучения, ни поддержки от разработчика.",
        next = "lua_disabled_2"
    },
    lua_disabled_2 = {
        pose = "question",
        position = "base",
        text = "Может ты хочешь перейти на новый интерфейс?",
        next = "lua_disabled_3"
    },
    lua_disabled_3 = {
        pose = "talking",
        position = "base",
        text = "Если тебе не понравилось, что новый интерфейс зеленый, то знай, что во время обучения я тебе помогу настроить цвета интерфейса.",
        next = "lua_redirect_offer"
    },
    lua_redirect_offer = {
        pose = "thinking_question",
        position = "base",
        text = "Хочешь перейти к новому интерфейсу?",
        choice = "lua_redirect",
        choice_no_delay_ms = 60000
    }
}
local function clone(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = clone(v) end
    return out
end

function M.getStep(stepId, state)
    local step = M.STEPS[stepId]
    if not step then return nil end
    local out = clone(step)
    if stepId == "tutorial_offer" then
        local mode = state and state.interface == "html" and "html" or "lua"
        if mode == "html" then
            out.segments = segments(
                "Ты хочешь пройти обучение по ", "normal",
                "новому", "green",
                " интерфейсу?", "normal"
            )
        else
            out.segments = segments(
                "Ты хочешь пройти обучение по ", "normal",
                "старому", "red",
                " интерфейсу?", "normal"
            )
        end
    end
    return out
end

return M
