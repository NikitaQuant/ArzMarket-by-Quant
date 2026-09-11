from pathlib import Path

main_path = Path('by_Quant_ArzMarket[3_56].lua')
main = main_path.read_text(encoding='utf-8')
anchor = '''\tctx.listTradeConfigs = function(side)'''
insert = '''\tctx.getTradeUiState = function()\n\t\treturn {\n\t\t\tcurrency = viceCityMode and "SA" or "VC",\n\t\t\tbuy_scan = buyScanMode == true,\n\t\t\tsell_scan = sellScanMode == true\n\t\t}\n\tend\n\tctx.toggleTradeCurrency = function()\n\t\tviceCityMode = not viceCityMode\n\t\tini.cfg.vice_city_mode = viceCityMode\n\t\tif type(save_all) == "function" then save_all() end\n\t\tif type(vc_converter) == "function" then vc_converter() end\n\t\treturn viceCityMode and "SA" or "VC"\n\tend\n\tctx.toggleTradeScan = function(side)\n\t\tside = side == "sell" and "sell" or "buy"\n\t\tif side == "buy" then\n\t\t\tbuyScanMode = not buyScanMode\n\t\t\tif buyScanMode then\n\t\t\t\tif type(setGameKeyState) == "function" then pcall(setGameKeyState, 21, 255) end\n\t\t\t\tif type(sampForceOnfootSync) == "function" then pcall(sampForceOnfootSync) end\n\t\t\t\tif type(AFKMessage) == "function" then AFKMessage(u8:decode("Откройте меню лавки [ALT], если скрипт автоматически не открыл и скрипт автоматически начнет сканирование")) end\n\t\t\telse\n\t\t\t\tif type(AFKMessage) == "function" then AFKMessage(u8:decode("Сканирование было отменено.")) end\n\t\t\tend\n\t\t\treturn buyScanMode\n\t\tend\n\t\tsellScanMode = not sellScanMode\n\t\tif sellScanMode then\n\t\t\tsellScanResults = {}\n\t\t\tif type(SendToServer) == "function" then SendToServer("/stats") end\n\t\t\tif type(AFKMessage) == "function" then AFKMessage(u8:decode("Проходит сканирование инвентаря. Подождите...")) end\n\t\telse\n\t\t\tif type(AFKMessage) == "function" then AFKMessage(u8:decode("Сканирование было отменено.")) end\n\t\tend\n\t\treturn sellScanMode\n\tend\n\tctx.refreshBuySource = function()\n\t\tif type(get_buyList) ~= "function" then return false end\n\t\tif type(sendNotify) == "function" then sendNotify(u8:decode("Обновление списков скупки...")) end\n\t\tget_buyList()\n\t\treturn true\n\tend\n\tctx.downloadAveragePrices = function()\n\t\tif type(get_prices) ~= "function" then return false end\n\t\tget_prices()\n\t\treturn true\n\tend\n''' + anchor
if anchor not in main:
    raise SystemExit('context insertion anchor not found')
main = main.replace(anchor, insert, 1)
main_path.write_text(main, encoding='utf-8')

module_path = Path('modules/arz_html_ui.lua')
module = module_path.read_text(encoding='utf-8')
if '    module_version = 9,' not in module:
    raise SystemExit('module version anchor not found')
module = module.replace('    module_version = 9,', '    module_version = 10,', 1)

state_anchor = '''    local cfg=configName(page)\n    local configs=configList(page)\n    local source=sources(page)\n    local runtimeKey=table.concat({\n        tostring(active),tostring(busy),tostring(snapshot.buy==true),tostring(snapshot.sell==true),\n        tostring(score),tostring(total),tostring(cfg),table.concat(configs,"\\29"),sourceFingerprint(source)\n    },"\\30")'''
state_repl = '''    local cfg=configName(page)\n    local configs=configList(page)\n    local source=sources(page)\n    local uiState={currency="SA",buy_scan=false,sell_scan=false}\n    if ctx and type(ctx.getTradeUiState)=="function" then\n        local ok,value=pcall(ctx.getTradeUiState)\n        if ok and type(value)=="table" then uiState=value end\n    end\n    local currency=uiState.currency=="VC" and "VC" or "SA"\n    local buyScan=uiState.buy_scan==true\n    local sellScan=uiState.sell_scan==true\n    local runtimeKey=table.concat({\n        tostring(active),tostring(busy),tostring(snapshot.buy==true),tostring(snapshot.sell==true),\n        tostring(score),tostring(total),tostring(cfg),table.concat(configs,"\\29"),currency,tostring(buyScan),tostring(sellScan),sourceFingerprint(source)\n    },"\\30")'''
if state_anchor not in module:
    raise SystemExit('state anchor not found')
module = module.replace(state_anchor, state_repl, 1)

common_anchor = '''        common={uiMode="html",activeConfig=cfg~="" and cfg:gsub("%.json$","") or "",configs=configs,\n            automation=active,tradeBusy=busy,automationBuy=snapshot.buy==true,automationSell=snapshot.sell==true,'''
common_repl = '''        common={uiMode="html",activeConfig=cfg~="" and cfg:gsub("%.json$","") or "",configs=configs,\n            currencyMode=currency,buyScan=buyScan,sellScan=sellScan,\n            automation=active,tradeBusy=busy,automationBuy=snapshot.buy==true,automationSell=snapshot.sell==true,'''
if common_anchor not in module:
    raise SystemExit('common anchor not found')
module = module.replace(common_anchor, common_repl, 1)

action_anchor = '''    elseif action=="trade.config.load" then\n        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end'''
action_insert = '''    elseif action=="trade.currency.toggle" then\n        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end\n        if not ctx or type(ctx.toggleTradeCurrency)~="function" then return jsonResponse(400,{ok=false,error="currency_unavailable"}) end\n        local ok,result=pcall(ctx.toggleTradeCurrency)\n        fingerprints.buy=""; fingerprints.sell=""\n        return jsonResponse(ok and result~=false and 200 or 400,{ok=ok and result~=false,currency=ok and result or nil,error=ok and result~=false and nil or tostring(result)})\n    elseif action=="trade.scan.toggle" then\n        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end\n        if not ctx or type(ctx.toggleTradeScan)~="function" then return jsonResponse(400,{ok=false,error="scan_unavailable"}) end\n        local ok,result=pcall(ctx.toggleTradeScan,side)\n        sourceCache[side].at=0; fingerprints[side]=""\n        return jsonResponse(ok and 200 or 400,{ok=ok,active=ok and result==true or false,error=ok and nil or tostring(result)})\n    elseif action=="buy.source.refresh" then\n        if side~="buy" then return jsonResponse(400,{ok=false,error="buy_only"}) end\n        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end\n        if not ctx or type(ctx.refreshBuySource)~="function" then return jsonResponse(400,{ok=false,error="refresh_unavailable"}) end\n        local ok,result=pcall(ctx.refreshBuySource)\n        sourceCache.buy.at=0; fingerprints.buy=""\n        return jsonResponse(ok and result~=false and 200 or 400,{ok=ok and result~=false,error=ok and result~=false and nil or tostring(result)})\n    elseif action=="prices.download" then\n        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end\n        if not ctx or type(ctx.downloadAveragePrices)~="function" then return jsonResponse(400,{ok=false,error="prices_unavailable"}) end\n        local ok,result=pcall(ctx.downloadAveragePrices)\n        return jsonResponse(ok and result~=false and 200 or 400,{ok=ok and result~=false,error=ok and result~=false and nil or tostring(result)})\n    elseif action=="trade.config.load" then\n        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end'''
if action_anchor not in module:
    raise SystemExit('action anchor not found')
module = module.replace(action_anchor, action_insert, 1)
module_path.write_text(module, encoding='utf-8')

html_path = Path('ArzMarket/html/index.html')
html = html_path.read_text(encoding='utf-8')
old_toolbar = '''            <button id="addButton" class="btn btn-secondary" type="button">+ Добавить</button>\n            <button id="averageButton" class="btn btn-secondary" type="button">Средние цены</button>\n            <button id="startButton" class="btn btn-primary" type="button">Старт</button>'''
new_toolbar = '''            <button id="addButton" class="btn btn-secondary" type="button">+ Добавить</button>\n            <button id="scanButton" class="btn btn-secondary btn-compact" type="button" title="Сканировать источник товаров">Скан</button>\n            <button id="currencyButton" class="btn btn-secondary btn-compact" type="button" title="Переключить валюту">SA$</button>\n            <button id="refreshButton" class="btn btn-secondary btn-compact" type="button" title="Обновить список скупки">Список</button>\n            <button id="pricesButton" class="btn btn-secondary btn-compact" type="button" title="Загрузить средние цены">Цены</button>\n            <button id="averageButton" class="btn btn-secondary" type="button">Средние цены</button>\n            <button id="startButton" class="btn btn-primary" type="button">Старт</button>'''
if old_toolbar not in html:
    raise SystemExit('toolbar anchor not found')
html = html.replace(old_toolbar, new_toolbar, 1)
html_path.write_text(html, encoding='utf-8')

css_path = Path('ArzMarket/html/css/style.css')
css = css_path.read_text(encoding='utf-8')
css_anchor = '''.btn-secondary:hover { background:#14222d; border-color:#385064; }'''
css_repl = css_anchor + '''\n.btn-compact { min-width:58px; padding:0 10px; }\n.btn-secondary.active-action { color:#92f5c9; border-color:rgba(41,213,143,.34); background:var(--green-dim); box-shadow:0 0 14px rgba(41,213,143,.07); }'''
if css_anchor not in css:
    raise SystemExit('css button anchor not found')
css = css.replace(css_anchor, css_repl, 1)
css_path.write_text(css, encoding='utf-8')

js_path = Path('ArzMarket/html/js/app.js')
js = js_path.read_text(encoding='utf-8')
refs_old = '''    addButton: el('addButton'), averageButton: el('averageButton'), startButton: el('startButton'),'''
refs_new = '''    addButton: el('addButton'), scanButton: el('scanButton'), currencyButton: el('currencyButton'),\n    refreshButton: el('refreshButton'), pricesButton: el('pricesButton'), averageButton: el('averageButton'), startButton: el('startButton'),'''
if refs_old not in js:
    raise SystemExit('refs anchor not found')
js = js.replace(refs_old, refs_new, 1)

header_old = '''    refs.startButton.textContent = active ? 'Отмена' : (buy ? 'Старт скупки' : 'Начать продажу');\n    refs.startButton.disabled = busy && !active;\n    refs.averageButton.classList.toggle('hidden', !buy);\n    refs.averageButton.disabled = busy;\n    refs.addButton.disabled = busy;'''
header_new = '''    const currency = state.data?.common?.currencyMode === 'VC' ? 'VC' : 'SA';\n    const scanActive = buy ? state.data?.common?.buyScan === true : state.data?.common?.sellScan === true;\n    refs.startButton.textContent = active ? 'Отмена' : (buy ? 'Старт скупки' : 'Начать продажу');\n    refs.startButton.disabled = busy && !active;\n    refs.currencyButton.textContent = `${currency}$`;\n    refs.currencyButton.disabled = busy;\n    refs.scanButton.textContent = scanActive ? 'Стоп скан' : 'Скан';\n    refs.scanButton.classList.toggle('active-action', scanActive);\n    refs.scanButton.disabled = busy;\n    refs.refreshButton.classList.toggle('hidden', !buy);\n    refs.refreshButton.disabled = busy;\n    refs.pricesButton.disabled = busy;\n    refs.averageButton.classList.toggle('hidden', !buy);\n    refs.averageButton.disabled = busy;\n    refs.addButton.disabled = busy;'''
if header_old not in js:
    raise SystemExit('render header anchor not found')
js = js.replace(header_old, header_new, 1)

head_old = '''    (buy ? ['Товар','Цена','Кол-во','Остаток','Статус',''] : ['Товар','Цена','Кол-во','Доступно','Статус',''])\n      .forEach(value => refs.tableHead.append(div(value)));'''
head_new = '''    const currency = state.data?.common?.currencyMode === 'VC' ? 'VC' : 'SA';\n    (buy ? ['Товар',`Цена ${currency}$`,'Кол-во','Остаток','Статус',''] : ['Товар',`Цена ${currency}$`,'Кол-во','Доступно','Статус',''])\n      .forEach(value => refs.tableHead.append(div(value)));'''
if head_old not in js:
    raise SystemExit('table head anchor not found')
js = js.replace(head_old, head_new, 1)

price_old = '''      row.append(div(`${money(item.price)} SA$`, 'money'));'''
price_new = '''      const currentPrice = currency === 'VC' ? item.price_vc : item.price;\n      row.append(div(`${money(currentPrice)} ${currency}$`, 'money'));'''
if price_old not in js:
    raise SystemExit('row price anchor not found')
js = js.replace(price_old, price_new, 1)

listeners_anchor = '''  refs.addButton.addEventListener('click', openPicker);\n  refs.pickerSearch.addEventListener('input', () => {'''
listeners_new = '''  refs.addButton.addEventListener('click', openPicker);\n  refs.scanButton.addEventListener('click', async () => {\n    if (tradeBusy()) return;\n    try {\n      await action('trade.scan.toggle', {side: state.page});\n      await refresh(true);\n    } catch (err) { showToast(`Сканирование: ${err.message}`, 'error'); }\n  });\n  refs.currencyButton.addEventListener('click', async () => {\n    if (tradeBusy()) return;\n    try {\n      await action('trade.currency.toggle', {side: state.page});\n      await refresh(true);\n    } catch (err) { showToast(`Валюта: ${err.message}`, 'error'); }\n  });\n  refs.refreshButton.addEventListener('click', async () => {\n    if (tradeBusy() || state.page !== 'buy') return;\n    try {\n      await action('buy.source.refresh', {side: 'buy'});\n      showToast('Обновление списка запущено', 'success');\n      await refresh(true);\n    } catch (err) { showToast(`Список: ${err.message}`, 'error'); }\n  });\n  refs.pricesButton.addEventListener('click', async () => {\n    if (tradeBusy()) return;\n    try {\n      await action('prices.download', {side: state.page});\n      showToast('Загрузка средних цен запущена', 'success');\n    } catch (err) { showToast(`Цены: ${err.message}`, 'error'); }\n  });\n  refs.pickerSearch.addEventListener('input', () => {'''
if listeners_anchor not in js:
    raise SystemExit('listeners anchor not found')
js = js.replace(listeners_anchor, listeners_new, 1)
js_path.write_text(js, encoding='utf-8')

print('patched HTML trade tools')
