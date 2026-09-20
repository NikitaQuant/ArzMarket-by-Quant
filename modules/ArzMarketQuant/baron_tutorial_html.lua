-- v230: post-future ordinary replies use 5s cooldown; Telegram advertisement uses 20s.
local M = {}

M.ID = "tutorial_html"
M.INTERFACE = "html"
M.START_STEP = "resize"

M.STEPS = {
    resize = {
        id = "resize", pose = "point_down_right",
        text = "Это кнопка изменения размера скрипта. Зажми её и потяни. Во время изменения размера игра может немного подлагивать.",
        anchor = "resize_handle", target = "resize_handle",
        wait = "event", expected_event = "resize_changed",
        next = "go_sell", follow_anchor = true
    },
    go_sell = {
        id = "go_sell", pose = "point_left", segments = {
            { text = "Нажми на раздел ", color = "normal" },
            { text = "Продажа", color = "red" },
            { text = ".", color = "normal" }
        },
        anchor = "nav_sell", target = "nav_sell", required_page = "sell", page = "sell",
        pointer_hotspot = { x = 0.060, y = 0.505, offset_x = 88, offset_y = 14 },
        mascot_scale = 0.78,
        bubble_scale = 1.06,
        bubble_target_x_left = 0.82,
        bubble_target_x_right = 0.18,
        bubble_target_y = 0.20,
        wait = "page", next = "sell_scan_prompt"
    },    sell_scan_prompt = {
        id = "sell_scan_prompt", pose = "point_right",
        segments = {
            { text = "Сначала просканируй инвентарь. Нажми ", color = "normal" },
            { text = "Скан инвентаря", color = "red" },
            { text = " и дождись окончания сканирования.", color = "normal" }
        },
        anchor = "sell_scan", target = "sell_scan", required_page = "sell",
        pointer_hotspot = { x = 0.955, y = 0.505, offset_x = -76, offset_y = 10 },
        mascot_scale = 0.76,
        wait = "event", expected_event = "sell_scan_completed", next = "sell_inventory"
    },
    sell_inventory = {
        id = "sell_inventory", pose = "point_right",
        text = "Это список предметов в твоём инвентаре. Нажми на любой предмет, чтобы добавить его на продажу.",
        empty_text = "Это список предметов в твоём инвентаре. Сейчас он пуст, поэтому просто запомни это место. После сканирования здесь появятся предметы.",
        anchor = "sell_inventory", target = "sell_inventory", required_page = "sell",
        pointer_hotspot = { x = 0.955, y = 0.505, anchor_x = 0.0, anchor_y = 0.5, offset_x = -14, offset_y = 8 },
        allow_mascot_offscreen_left = true,
        bubble_scale = 1.12,
        wait = "event", expected_event = "sell_item_selected", next = "sell_selected_1"
    },
    sell_selected_1 = {
        id = "sell_selected_1", pose = "approval",
        text = "Молодец. Выбранные товары появляются в этом списке. Здесь можно указать цену и количество или удалить товар.",
        anchor = "sell_selected_items", target = "sell_selected_items", required_page = "sell",
        wait = "user_skip", next = "sell_selected_2"
    },
    sell_selected_2 = {
        id = "sell_selected_2", pose = "point_right",
        text = "Это кнопка состояния товара. Нажми на неё, чтобы отключить товар.",
        anchor = "sell_status_toggle", target = "sell_status_toggle", required_page = "sell",
        pointer_hotspot = { x = 0.955, y = 0.502, offset_x = -34, offset_y = 8 },
        wait = "event", expected_event = "sell_status_toggled", next = "sell_selected_3"
    },
    sell_stats_total = {
        id = "sell_stats_total", pose = "point_up_right",
        segments = {
            { text = "Нажав на ", color = "normal" },
            { text = "Всего товаров", color = "blue" },
            { text = ", ты сможешь увидеть все товары.", color = "normal" }
        },
        anchor = "sell_stats_total", target = "sell_stats_total", required_page = "sell",
        mascot_scale = 0.64,
        bubble_scale = 0.96,
        bubble_shift_x = -28,
        bubble_shift_y = -20,
        pointer_hotspot = { x = 0.915, y = 0.290, offset_x = -96, offset_y = 68 },
        wait = "user_skip", expected_event = "sell_stats_total_clicked", next = "sell_stats_enabled"
    },
    sell_stats_enabled = {
        id = "sell_stats_enabled", pose = "point_up_right",
        segments = {
            { text = "Нажав на ", color = "normal" },
            { text = "Включено", color = "blue" },
            { text = ", ты сможешь увидеть только включённые товары.", color = "normal" }
        },
        anchor = "sell_stats_enabled", target = "sell_stats_enabled", required_page = "sell",
        mascot_scale = 0.64,
        bubble_scale = 0.96,
        bubble_shift_x = -18,
        bubble_shift_y = -20,
        pointer_hotspot = { x = 0.915, y = 0.290, offset_x = -84, offset_y = 68 },
        wait = "user_skip", expected_event = "sell_stats_enabled_clicked", next = "sell_stats_disabled"
    },
    sell_stats_disabled = {
        id = "sell_stats_disabled", pose = "point_up_right",
        segments = {
            { text = "Нажав на ", color = "normal" },
            { text = "Отключено", color = "blue" },
            { text = ", ты сможешь увидеть только отключённые товары.", color = "normal" }
        },
        anchor = "sell_stats_disabled", target = "sell_stats_disabled", required_page = "sell",
        mascot_scale = 0.64,
        bubble_scale = 0.96,
        bubble_shift_x = -6,
        bubble_shift_y = -20,
        pointer_hotspot = { x = 0.915, y = 0.290, offset_x = -72, offset_y = 68 },
        wait = "user_skip", expected_event = "sell_stats_disabled_clicked", next = "sell_filter_prompt"
    },
    sell_selected_3 = {
        id = "sell_selected_3", pose = "talking",
        text = "Отключённый товар не будет выставлен в лавку.",
        anchor = "sell_selected_items", target = "sell_selected_items", required_page = "sell",
        wait = "user_skip", next = "sell_stats_total"
    },
    sell_filter_prompt = {
        id = "sell_filter_prompt", pose = "point_right", segments = {
            { text = "Нажми на кнопку ", color = "normal" },
            { text = "Фильтр", color = "red" },
            { text = ".", color = "normal" }
        },
        anchor = "sell_filter_button", target = "sell_filter_button", required_page = "sell",
        wait = "event", expected_event = "filter_opened", next = "sell_filter_1"
    },
    sell_filter_1 = {
        id = "sell_filter_1", pose = "talking", text = "Здесь находятся фильтры товаров.",
        anchor = "sell_filter_panel", target = "sell_filter_panel", required_page = "sell",
        wait = "user_skip", next = "sell_filter_2"
    },
    sell_filter_2 = {
        id = "sell_filter_2", pose = "talking",
        text = "Если нажать на фильтр один раз, список перейдёт к нужной категории товаров.",
        anchor = "sell_filter_panel", target = "sell_filter_panel", required_page = "sell",
        wait = "user_skip", next = "sell_filter_3"
    },
    sell_filter_3 = {
        id = "sell_filter_3", pose = "talking",
        text = "Если зажать категорию и перетащить её, можно изменить порядок категорий.",
        anchor = "sell_filter_panel", target = "sell_filter_panel", required_page = "sell",
        wait = "user_skip", next = "sell_filter_4"
    },
    sell_filter_4 = {
        id = "sell_filter_4", pose = "talking",
        segments = {
            { text = "Например, если поменять местами ", color = "normal" },
            { text = "Аксессуары", color = "red" },
            { text = " и ", color = "normal" },
            { text = "Ларцы", color = "red" },
            { text = ", эти категории поменяются местами и в списке.", color = "normal" }
        },
        anchor = "sell_filter_panel", target = "sell_filter_panel", required_page = "sell",
        wait = "user_skip", next = "sell_filter_5"
    },
    sell_filter_5 = {
        id = "sell_filter_5", pose = "approval",
        text = "Так можно изменить порядок выставления товаров в лавке.",
        anchor = "sell_filter_panel", target = "sell_filter_panel", required_page = "sell",
        wait = "user_skip", next = "sell_currency"
    },
    sell_currency = {
        id = "sell_currency", pose = "point_right",
        text = "Здесь можно выбрать валюту, в которой ты хочешь продать товар.",
        anchor = "sell_currency", target = "sell_currency", required_page = "sell",
        wait = "user_skip", next = "sell_config", optional_anchor = true
    },
    sell_config = {
        id = "sell_config", pose = "point_up_right", text = "Здесь можно выбрать другой конфиг продажи.",
        anchor = "sell_config", target = "sell_config", required_page = "sell",
        pointer_hotspot = { x = 0.918, y = 0.283, offset_x = -72, offset_y = 38 },
        wait = "user_skip", next = "sell_window_drag"
    },
    sell_window_drag = {
        id = "sell_window_drag", pose = "point_up_right",
        text = "Зажав верхнюю часть скрипта, ты сможешь его перемещать.",
        anchor = "window_drag", target = "window_drag", required_page = "sell",
        mascot_scale = 0.66,
        pointer_hotspot = { x = 0.918, y = 0.283, anchor_x = 0.52, anchor_y = 0.50, offset_x = -86, offset_y = 92 },
        wait = "user_skip", next = "go_buy"
    },
    go_buy = {
        id = "go_buy", pose = "point_left", segments = {
            { text = "Теперь перейди в раздел ", color = "normal" },
            { text = "Скупка", color = "red" },
            { text = ".", color = "normal" }
        },
        anchor = "nav_buy", target = "nav_buy", required_page = "buy", page = "buy",
        pointer_hotspot = { x = 0.060, y = 0.505, offset_x = 64, offset_y = 0 },
        bubble_scale = 1.06,
        bubble_target_x_left = 0.82,
        bubble_target_x_right = 0.18,
        bubble_target_y = 0.20,
        wait = "page", next = "buy_search"
    },    buy_search = {
        id = "buy_search", pose = "point_right",
        text = "В строке поиска можно найти предмет, который ты хочешь добавить на скупку в лавке.",
        anchor = "buy_search", target = "buy_search", required_page = "buy",
        mascot_scale = 0.78,
        pointer_hotspot = { x = 0.955, y = 0.502, offset_x = -130, offset_y = 0 },
        wait = "user_skip", next = "buy_auto_prices"
    },
    buy_auto_prices = {
        id = "buy_auto_prices", pose = "point_right",
        text = "Нажав эту кнопку, можно выставить средние скупочные цены для всех товаров.",
        anchor = "buy_auto_prices", target = "buy_auto_prices", required_page = "buy",
        mascot_scale = 0.78,
        pointer_hotspot = { x = 0.955, y = 0.502, offset_x = -105, offset_y = 0 },
        wait = "user_skip", next = "go_settings", optional_anchor = true
    },

    -- Kept only for migration from Block 2 saves that stopped on this step.
    block2_finish = {
        id = "block2_finish", pose = "approval",
        text = "Продажу и скупку разобрали. Основные торговые функции тебе уже знакомы.",
        position = "base", wait = "user_skip", next = "go_settings"
    },

    go_settings = {
        id = "go_settings", pose = "point_left", text = "Теперь открой «Настройки».",
        anchor = "nav_settings", target = "nav_settings", required_page = "settings", page = "settings",
        pointer_hotspot = { x = 0.060, y = 0.505, offset_x = 64, offset_y = 0 },
        wait = "page", next = "settings_intro_1"
    },    settings_intro_1 = {
        id = "settings_intro_1", pose = "talking",
        text = "Это настройки скрипта. Их можно изучить самостоятельно примерно за пару минут.",
        anchor = "settings_main", target = "settings_main", required_page = "settings",
        position = "script_left", bubble_scale = 1.04,
        wait = "user_skip", next = "settings_intro_2"
    },
    settings_intro_2 = {
        id = "settings_intro_2", pose = "talking",
        segments = {
            { text = "Самый важный для внешнего вида раздел здесь: ", color = "normal" },
            { text = "Оформление", color = "red" },
            { text = ".", color = "normal" }
        },
        anchor = "settings_main", target = "settings_main", required_page = "settings",
        position = "script_left", bubble_scale = 1.04,
        wait = "user_skip", next = "settings_appearance_prompt"
    },
    settings_appearance_prompt = {
        id = "settings_appearance_prompt", pose = "point_right", segments = {
            { text = "Нажми на ", color = "normal" },
            { text = "Оформление", color = "red" },
            { text = ".", color = "normal" }
        },
        anchor = "settings_appearance_tab", target = "settings_appearance_tab", required_page = "settings",
        mascot_scale = 0.74,
        pointer_hotspot = { x = 0.955, y = 0.502, offset_x = -150, offset_y = 18 },
        wait = "event", expected_event = "settings_section_changed", expected_section = "appearance",
        next = "settings_glow"
    },
    settings_glow = {
        id = "settings_glow", pose = "point_right",
        text = "Здесь настраивается сила свечения кнопок, рамок и активных элементов. Передвигай ползунок и сразу увидишь результат.",
        anchor = "settings_glow", target = "settings_glow", required_page = "settings",
        required_settings_section = "appearance", mascot_scale = 0.70,
        pointer_hotspot = { x = 0.955, y = 0.502, offset_x = -118, offset_y = 4 },
        wait = "user_skip", next = "settings_theme_try"
    },
    settings_theme_try = {
        id = "settings_theme_try", pose = "point_right",
        text = "Попробуй смени темы оформления, я подожду.",
        anchor = "settings_themes", target = "settings_themes", required_page = "settings",
        required_settings_section = "appearance", mascot_scale = 0.70,
        pointer_hotspot = { x = 0.955, y = 0.502, offset_x = -110, offset_y = 0 },
        wait = "user_skip", skip_delay_ms = 20000, next = "settings_resize"
    },
    settings_resize = {
        id = "settings_resize", pose = "point_down_right",
        text = "А здесь меняется размер самого окна ArzMarket. Зажми правый нижний угол и потяни его.",
        anchor = "resize_handle", target = "resize_handle", required_page = "settings",
        required_settings_section = "appearance", follow_anchor = true,
        wait = "event", expected_event = "resize_changed", next = "settings_appearance_1"
    },
    settings_appearance_1 = {
        id = "settings_appearance_1", pose = "talking",
        segments = {
            { text = "В ", color = "normal" },
            { text = "Оформлении", color = "red" },
            { text = " можно настроить размеры текста и кнопок.", color = "normal" }
        },
        anchor = "settings_appearance_panel", target = "settings_appearance_panel", required_page = "settings",
        position = "script_left", mascot_scale = 0.70, bubble_scale = 0.84,
        required_settings_section = "appearance", wait = "user_skip", next = "settings_appearance_2"
    },
    settings_appearance_2 = {
        id = "settings_appearance_2", pose = "talking",
        text = "В этом разделе также можно настроить размеры текста, прозрачность и другие параметры внешнего вида.",
        anchor = "settings_appearance_panel", target = "settings_appearance_panel", required_page = "settings",
        position = "script_left", mascot_scale = 0.70, bubble_scale = 0.84,
        required_settings_section = "appearance", wait = "user_skip", next = "settings_appearance_3"
    },
    settings_appearance_3 = {
        id = "settings_appearance_3", pose = "approval",
        text = "Также здесь находятся другие параметры внешнего вида ArzMarket.",
        anchor = "settings_appearance_panel", target = "settings_appearance_panel", required_page = "settings",
        position = "script_left", mascot_scale = 0.70, bubble_scale = 1.08,
        bubble_shift_y = -24,
        required_settings_section = "appearance", wait = "user_skip", next = "logs_intro"
    },
    logs_intro = {
        id = "logs_intro", pose = "talking",
        segments = {
            { text = "В ", color = "normal" },
            { text = "Логах", color = "red" },
            { text = " можно посмотреть историю взаимодействия аккаунта с лавкой.", color = "normal" }
        },
        target = "nav_logs", position = "base", required_page = "settings",
        wait = "user_skip", next = "marketplace_intro"
    },
    marketplace_intro = {
        id = "marketplace_intro", pose = "talking",
        segments = {
            { text = "В ", color = "normal" },
            { text = "Маркетплейсе", color = "red" },
            { text = " можно посмотреть, какие товары выставлены у других игроков в их лавках.", color = "normal" }
        },
        target = "nav_marketplace", position = "base", required_page = "settings",
        wait = "user_skip", next = "mods_intro"
    },
    mods_intro = {
        id = "mods_intro", pose = "talking",
        segments = {
            { text = "В ", color = "normal" },
            { text = "модификациях", color = "red" },
            { text = " ты сможешь скачать дополнительные скрипты, либо я могу сделать скрипт для тебя.", color = "normal" }
        },
        target = "nav_mods", position = "base", required_page = "settings",
        wait = "user_skip", next = "storage_intro_1"
    },
    storage_intro_1 = {
        id = "storage_intro_1", pose = "talking",
        segments = {
            { text = "В ", color = "normal" },
            { text = "Хранилище", color = "red" },
            { text = " можно узнать, где находятся твои предметы.", color = "normal" }
        },
        target = "nav_storage", position = "base", required_page = "settings",
        wait = "user_skip", next = "storage_intro_2"
    },
    storage_intro_2 = {
        id = "storage_intro_2", pose = "thinking_question",
        text = "Например, ты положил воздушный шар в машину месяц назад, а теперь не можешь вспомнить где он.",
        target = "nav_storage", position = "base", required_page = "settings",
        wait = "user_skip", next = "storage_intro_3"
    },
    storage_intro_3 = {
        id = "storage_intro_3", pose = "approval",
        text = "Хранилище поможет найти, в каком месте остался нужный предмет.",
        target = "nav_storage", position = "base", required_page = "settings",
        wait = "user_skip", next = "finish_1"
    },
    finish_1 = {
        id = "finish_1", pose = "celebration",
        text = "Обучение окончено. Теперь ты знаешь основные возможности ArzMarket.",
        position = "base", required_page = "settings", wait = "user_skip", next = "finish_about_1"
    },
    finish_about_1 = {
        id = "finish_about_1", pose = "talking",
        text = "А теперь я немного расскажу о себе и о будущих разработках.",
        position = "base", required_page = "settings", wait = "user_skip", skip_delay_ms = 5000, next = "finish_about_name"
    },
    finish_about_name = {
        id = "finish_about_name", pose = "talking",
        segments = {
            { text = "Я ", color = "normal" },
            { text = "Барон дю Валлон де Брасье де Пьерфон", color = "blue" },
            { text = ", твой личный помощник.", color = "normal" }
        },
        position = "base", required_page = "settings", wait = "user_skip", skip_delay_ms = 5000, next = "finish_2"
    },
    finish_2 = {
        id = "finish_2", pose = "approval",
        text = "Пока что я создан лишь для обучения, но совсем скоро мне дадут ИИ, и тогда я смогу тебе помогать во всех ситуациях в торговле.",
        position = "base", required_page = "settings", wait = "user_skip", skip_delay_ms = 5000, next = "finish_3"
    },
    finish_3 = {
        id = "finish_3", pose = "talking",
        text = "Я смогу тебе подсказывать, когда ты ставишь слишком высокую цену за товар, и смогу сам автоматически скупать товары через трейд.",
        position = "base", required_page = "settings", wait = "user_skip", skip_delay_ms = 5000, next = "finish_4"
    },
    finish_4 = {
        id = "finish_4", pose = "presenting",
        text = "Я смогу создавать тебе скрипты на заказ. Я смогу делать почти всё, что ты захочешь.",
        position = "base", required_page = "settings", wait = "user_skip", skip_delay_ms = 5000, next = "finish_5"
    },
    finish_5 = {
        id = "finish_5", pose = "thinking_question",
        text = "Хочешь узнать, что будет добавлено в этот скрипт в будущем?",
        position = "base", required_page = "settings", wait = "user_skip", skip_delay_ms = 5000, next = "future_features"
    },
    future_features = {
        id = "future_features", pose = "approval",
        text = "",
        position = "base", required_page = "settings", wait = "user_skip", next = "future_details_offer",
        silent = true, hide_mascot = true, promo_window = true, skip_delay_ms = 60000,
        promo_button_text = "Понятно",
        promo_red_from = 8,
        promo_lines = {
            "В будущем будет добавлено:",
            "1. ИИ для Барона;",
            "2. Бот с ИИ, который сможет вместо вас сам включить ваш ПК, сам обновить и зайти в Аризону в 5 утра, сам сможет занять лавку или место напротив ЦР, сам сможет выставить товары на скупку или продажу, отправит вам в ТГ отчёт и скрин из игры. Бот сможет перезайти в случае краша;",
            "3. Чит на функции Premium VIP (я говорю про донатный Premium VIP в игре, а не про какой-то премиум в моём скрипте. Нет, мой скрипт всегда будет бесплатный);",
            "4. Собственный маркетплейс;",
            "5. Собственные таблицы средних цен;",
            "6. Бот с ИИ, который сможет скупать товары в центре ЦР через трейд, например, на Вайс Сити;",
            "И ВСЁ ЭТО БЕСПЛАТНО, И В МОЁМ СКРИПТЕ НИКОГДА НЕ БУДЕТ БЛОКИРОВОК, КАК В СКРИПТЕ ЫРЕЙМА.",
            "А ЧТОБЫ СЛЕДИТЬ ЗА НОВОСТЯМИ ИЛИ ПРЕДЛОЖИТЬ СВОЮ ИДЕЮ, ЗАХОДИ В МОЙ ТГК:"
        },
        promo_link_label = "HTTPS://T.ME/MOON_ARZ",
        promo_link_intro = "Нажми на эту ссылку:",
        promo_link_url = "https://t.me/moon_arz"
    },
    future_details_offer = {
        id = "future_details_offer", pose = "thinking_question",
        text = "Хочешь, я расскажу чуть подробнее об этих нововведениях?",
        position = "base", required_page = "settings", choice = "future_details",
        choice_no_delay_ms = 60000,
        bubble_scale = 1.18
    },
    future_ai_1 = {
        id = "future_ai_1", pose = "talking",
        segments = {
            { text = "ИИ для меня - ", color = "red" },
            { text = "я смогу понимать твои команды, смогу выполнять действия в скрипте, смогу писать тебе скрипты.", color = "normal" }
        },
        position = "base", required_page = "settings", wait = "user_skip", skip_delay_ms = 5000, next = "future_ai_2"
    },
    future_ai_2 = {
        id = "future_ai_2", pose = "talking",
        text = "Например, ты попросишь меня создать конфиг на 2ккк для скупки, потом в определенное время выставить лавку.",
        position = "base", required_page = "settings", wait = "user_skip", skip_delay_ms = 5000, next = "future_ai_3"
    },
    future_ai_3 = {
        id = "future_ai_3", pose = "approval",
        text = "Я сам подберу конфиг по твоим интересам, по твоему серверу и по твоему бюджету.",
        position = "base", required_page = "settings", wait = "user_skip", skip_delay_ms = 5000, next = "future_ai_4"
    },
    future_ai_4 = {
        id = "future_ai_4", pose = "presenting",
        text = "Я сам зайду на твой аккаунт, сам выставлю лавку напротив ЦР в определенное время.",
        position = "base", required_page = "settings", wait = "user_skip", skip_delay_ms = 5000, next = "future_ai_5"
    },
    future_ai_5 = {
        id = "future_ai_5", pose = "approval",
        text = "Сам отправлю тебе скриншот в телеграмме из игры.",
        position = "base", required_page = "settings", wait = "user_skip", skip_delay_ms = 5000, next = "future_ai_6"
    },
    future_ai_6 = {
        id = "future_ai_6", pose = "celebration",
        text = "Если ты захочешь меня попросить о чем-то другом - я это тоже выполню!",
        position = "base", required_page = "settings", wait = "user_skip", skip_delay_ms = 5000, next = "future_vip_1"
    },
    future_vip_1 = {
        id = "future_vip_1", pose = "talking",
        segments = {
            { text = "Чит на некоторые функции премиум вип - ", color = "red" },
            { text = "игроки без премиум вип смогут использовать некоторые функции, которые доступны только с премиум вип.", color = "normal" }
        },
        position = "base", required_page = "settings", wait = "user_skip", skip_delay_ms = 5000, next = "future_vip_2"
    },
    future_vip_2 = {
        id = "future_vip_2", pose = "approval",
        text = "И это беспалевный чит до тех пор, пока ты сам о нем кому-то не расскажешь.",
        position = "base", required_page = "settings", wait = "user_skip", skip_delay_ms = 5000, next = "future_marketplace_1"
    },
    future_marketplace_1 = {
        id = "future_marketplace_1", pose = "presenting",
        segments = {
            { text = "Собственный маркетплейс - ", color = "red" },
            { text = "это полностью независимый мой личный маркетплейс. В нем не будет ограничений по уровню или по блокировке.", color = "normal" }
        },
        position = "base", required_page = "settings", wait = "user_skip", skip_delay_ms = 5000, next = "future_tables_1"
    },
    future_tables_1 = {
        id = "future_tables_1", pose = "talking",
        segments = {
            { text = "Собственные таблицы - ", color = "red" },
            { text = "сейчас в платной версии арз маркета есть таблицы со средними ценами.", color = "normal" }
        },
        position = "base", required_page = "settings", wait = "user_skip", skip_delay_ms = 5000, next = "future_tables_2"
    },
    future_tables_2 = {
        id = "future_tables_2", pose = "talking",
        text = "Эти таблицы созданы для скупщиков на вайс сити через трейд.",
        position = "base", required_page = "settings", wait = "user_skip", skip_delay_ms = 5000, next = "future_tables_3"
    },
    future_tables_3 = {
        id = "future_tables_3", pose = "presenting",
        text = "Средний заработок у таких скупщиков составляет около 5-15ккк за сутки.",
        position = "base", required_page = "settings", wait = "user_skip", skip_delay_ms = 5000, next = "future_tables_4"
    },
    future_tables_4 = {
        id = "future_tables_4", pose = "celebration",
        text = "А я дам тебе таблицы для скупки совершенно бесплатно!",
        position = "base", required_page = "settings", wait = "user_skip", skip_delay_ms = 5000, next = "future_trade_bot_1"
    },
    future_trade_bot_1 = {
        id = "future_trade_bot_1", pose = "talking",
        segments = {
            { text = "Бот с ИИ для автоматической скупки на вайс сити через трейд - ", color = "red" },
            { text = "это автоматизация этих таблиц со средними ценами.", color = "normal" }
        },
        position = "base", required_page = "settings", wait = "user_skip", skip_delay_ms = 5000, next = "future_trade_bot_2"
    },
    future_trade_bot_2 = {
        id = "future_trade_bot_2", pose = "approval",
        text = "Я сам зайду на вайс сити, сам пойду на ЦР, сам начну скупать товары у других игроков через трейд.",
        position = "base", required_page = "settings", wait = "user_skip", skip_delay_ms = 5000, next = "finish_6"
    },
    finish_6 = {
        id = "finish_6", pose = "approval",
        text = "Подпишись на тгк, чтобы ты помог улучшить скрипт, пожалуйста. Мне важно знать, что именно нужно игрокам, чтобы я добавил это в скрипт. Нажми на ссылку снизу, пожалуйста.",
        message_link_label = "https://t.me/moon_arz",
        message_link_url = "https://t.me/moon_arz",
        position = "base", required_page = "settings", wait = "user_skip",
        skip_delay_ms = 20000, bubble_scale = 1.10, finish = true
    }
}

M.ANCHORS = {
    window_drag = '[data-baron-anchor="window_drag"]',
    resize_handle = '[data-baron-anchor="resize_handle"]',
    nav_sell = '[data-baron-anchor="nav_sell"]',
    nav_buy = '[data-baron-anchor="nav_buy"]',
    sell_scan = '[data-baron-anchor="sell_scan"], #sellScanMainButton:not(.hidden), #scanButton',
    sell_inventory = '[data-baron-anchor="sell_inventory"]',
    sell_selected_items = '[data-baron-anchor="sell_selected_items"]',
    sell_status_toggle = '[data-baron-anchor="sell_status_toggle"]',
    sell_filter_button = '[data-baron-anchor="sell_filter_button"]',
    sell_filter_panel = '[data-baron-anchor="sell_filter_panel"]',
    sell_currency = '[data-baron-anchor="sell_currency"]',
    sell_config = '[data-baron-anchor="sell_config"]',
    buy_search = '[data-baron-anchor="buy_search"]',
    buy_auto_prices = '[data-baron-anchor="buy_auto_prices"]',
    nav_settings = '[data-baron-anchor="nav_settings"]',
    settings_main = '[data-baron-anchor="settings_main"]',
    settings_appearance_tab = '[data-baron-anchor="settings_appearance_tab"]',
    settings_appearance_panel = '[data-baron-anchor="settings_appearance_panel"]',
    settings_glow = '[data-baron-anchor="settings_glow"]',
    settings_themes = '[data-baron-anchor="settings_themes"]',
    nav_logs = '[data-baron-anchor="nav_logs"]',
    nav_marketplace = '[data-baron-anchor="nav_marketplace"]',
    nav_mods = '[data-baron-anchor="nav_mods"]',
    nav_storage = '[data-baron-anchor="nav_storage"]'
}
local function clone(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, child in pairs(value) do out[key] = clone(child) end
    return out
end

function M.getStep(stepId, _, facts)
    local source = M.STEPS[stepId]
    if type(source) ~= "table" then return nil end
    local step = clone(source)
    if type(facts) == "table" and facts.sell_inventory_empty == true then
        if stepId == "sell_inventory" then
            step.text = step.empty_text or step.text
            step.wait = "user_skip"
            step.expected_event = nil
        elseif stepId == "sell_selected_1" or stepId == "sell_selected_2" or stepId == "sell_selected_3" then
            step.anchor = nil
            step.target = nil
            step.position = "base"
        end
    end
    return step
end

return M
