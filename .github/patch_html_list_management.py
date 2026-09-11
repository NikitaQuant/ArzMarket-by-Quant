from pathlib import Path

main_path = Path('by_Quant_ArzMarket[3_56].lua')
main = main_path.read_text(encoding='utf-8')

anchor = '\tctx.listTradeConfigs = function(side)'
insert = '''\tctx.getTradeUndoCount = function(side)\n\t\tside = side == "sell" and "sell" or "buy"\n\t\tlocal stack = modificationState and modificationState.itemDeleteUndo and modificationState.itemDeleteUndo[side]\n\t\treturn type(stack) == "table" and #stack or 0\n\tend\n\tctx.deleteTradeItem = function(side, index)\n\t\tside = side == "sell" and "sell" or "buy"\n\t\tlocal list = side == "buy" and buyList or sellList\n\t\tindex = math.floor(tonumber(index) or 0)\n\t\tif type(list) ~= "table" or index < 1 or index > #list then return false, "invalid_index" end\n\t\tif type(deleteListItemWithUndo) ~= "function" then return false, "delete_unavailable" end\n\t\tlocal ok, result = pcall(deleteListItemWithUndo, side, list, index)\n\t\tif not ok then return false, tostring(result) end\n\t\treturn result ~= false, result == false and "delete_failed" or nil\n\tend\n\tctx.clearTradeList = function(side)\n\t\tside = side == "sell" and "sell" or "buy"\n\t\tif type(clearTradeListAndPersist) ~= "function" then return false, "clear_unavailable" end\n\t\tlocal ok, result = pcall(clearTradeListAndPersist, side)\n\t\tif not ok then return false, tostring(result) end\n\t\treturn result ~= false, result == false and "clear_failed" or nil\n\tend\n\tctx.undoTradeDelete = function(side)\n\t\tside = side == "sell" and "sell" or "buy"\n\t\tif type(undoLastDeletedListItem) ~= "function" then return false, "undo_unavailable" end\n\t\tlocal ok, result = pcall(undoLastDeletedListItem, side)\n\t\tif not ok then return false, tostring(result) end\n\t\treturn result ~= false, result == false and "nothing_to_undo" or nil\n\tend\n\tctx.getBuyContinueMode = function()\n\t\treturn buyContinueMode == true\n\tend\n\tctx.setBuyContinueMode = function(value)\n\t\tbuyContinueMode = value == true\n\t\treturn buyContinueMode\n\tend\n''' + anchor
if 'ctx.getTradeUndoCount = function(side)' not in main:
    if anchor not in main:
        raise SystemExit('core context anchor missing')
    main = main.replace(anchor, insert, 1)
main_path.write_text(main, encoding='utf-8')

module_path = Path('modules/arz_html_ui.lua')
module = module_path.read_text(encoding='utf-8')
if '    module_version = 10,' in module:
    module = module.replace('    module_version = 10,', '    module_version = 11,', 1)
elif '    module_version = 11,' not in module:
    raise SystemExit('unexpected module version')

old_fingerprint = '''            tostring(x.count or ""),tostring(x.continue or ""),tostring(x.enabled~=false),\n            tostring(x.maximum==true),tostring(x.all_count or ""),tostring(x.slot_id or "")'''
new_fingerprint = '''            tostring(x.count or ""),tostring(x.continue or ""),tostring(x.enabled~=false),\n            tostring(x.maximum==true),tostring(x.count_maximum or ""),tostring(x.all_count or ""),tostring(x.slot_id or "")'''
if old_fingerprint in module:
    module = module.replace(old_fingerprint, new_fingerprint, 1)

old_state = '''    local currency=uiState.currency=="VC" and "VC" or "SA"\n    local buyScan=uiState.buy_scan==true\n    local sellScan=uiState.sell_scan==true\n    local runtimeKey=table.concat({\n        tostring(active),tostring(busy),tostring(snapshot.buy==true),tostring(snapshot.sell==true),\n        tostring(score),tostring(total),tostring(cfg),table.concat(configs,"\\29"),currency,tostring(buyScan),tostring(sellScan),sourceFingerprint(source)\n    },"\\30")'''
new_state = '''    local currency=uiState.currency=="VC" and "VC" or "SA"\n    local buyScan=uiState.buy_scan==true\n    local sellScan=uiState.sell_scan==true\n    local undoCount=0\n    if ctx and type(ctx.getTradeUndoCount)=="function" then\n        local ok,value=pcall(ctx.getTradeUndoCount,page)\n        if ok then undoCount=math.max(0,math.floor(tonumber(value) or 0)) end\n    end\n    local buyContinue=false\n    if ctx and type(ctx.getBuyContinueMode)=="function" then\n        local ok,value=pcall(ctx.getBuyContinueMode)\n        if ok then buyContinue=value==true end\n    end\n    local runtimeKey=table.concat({\n        tostring(active),tostring(busy),tostring(snapshot.buy==true),tostring(snapshot.sell==true),\n        tostring(score),tostring(total),tostring(cfg),table.concat(configs,"\\29"),currency,tostring(buyScan),tostring(sellScan),\n        tostring(undoCount),tostring(buyContinue),sourceFingerprint(source)\n    },"\\30")'''
if old_state not in module:
    raise SystemExit('state anchor missing')
module = module.replace(old_state, new_state, 1)

old_common = '''            currencyMode=currency,buyScan=buyScan,sellScan=sellScan,\n            automation=active,tradeBusy=busy,automationBuy=snapshot.buy==true,automationSell=snapshot.sell==true,'''
new_common = '''            currencyMode=currency,buyScan=buyScan,sellScan=sellScan,undoCount=undoCount,buyContinue=buyContinue,\n            automation=active,tradeBusy=busy,automationBuy=snapshot.buy==true,automationSell=snapshot.sell==true,'''
if old_common not in module:
    raise SystemExit('common state anchor missing')
module = module.replace(old_common, new_common, 1)

old_remove = '''local function removeItem(side,payload)\n    local _,index,err=findItem(side,payload.identity)\n    if not index then return false,err end\n    local buy,sell=lists()\n    local list=side=="buy" and buy or sell\n    local removed=table.remove(list,index)\n    local ok,saveErr=persist(side)\n    if not ok then\n        table.insert(list,index,removed)\n    end\n    if type(tradeFilterInvalidate)=="function" then pcall(tradeFilterInvalidate,side) end\n    fingerprints[side]=""\n    return ok,saveErr\nend'''
new_remove = '''local function removeItem(side,payload)\n    local _,index,err=findItem(side,payload.identity)\n    if not index then return false,err end\n    if not ctx or type(ctx.deleteTradeItem)~="function" then return false,"delete_unavailable" end\n    local ok,result,coreErr=pcall(ctx.deleteTradeItem,side,index)\n    local success=ok and result~=false\n    fingerprints[side]=""\n    return success,success and nil or (ok and coreErr or tostring(result))\nend'''
if old_remove not in module:
    raise SystemExit('removeItem anchor missing')
module = module.replace(old_remove, new_remove, 1)

action_anchor = '''    elseif action=="trade.item.update" then\n        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end'''
action_insert = '''    elseif action=="trade.list.clear" then\n        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end\n        if not ctx or type(ctx.clearTradeList)~="function" then return jsonResponse(400,{ok=false,error="clear_unavailable"}) end\n        local ok,result,coreErr=pcall(ctx.clearTradeList,side)\n        local success=ok and result~=false\n        fingerprints[side]=""\n        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})\n    elseif action=="trade.item.undo" then\n        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end\n        if not ctx or type(ctx.undoTradeDelete)~="function" then return jsonResponse(400,{ok=false,error="undo_unavailable"}) end\n        local ok,result,coreErr=pcall(ctx.undoTradeDelete,side)\n        local success=ok and result~=false\n        fingerprints[side]=""\n        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and coreErr or tostring(result))})\n    elseif action=="buy.continue.toggle" then\n        if side~="buy" then return jsonResponse(400,{ok=false,error="buy_only"}) end\n        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end\n        if not ctx or type(ctx.setBuyContinueMode)~="function" or type(ctx.getBuyContinueMode)~="function" then return jsonResponse(400,{ok=false,error="continue_unavailable"}) end\n        local current=false\n        local readOk,readValue=pcall(ctx.getBuyContinueMode)\n        if readOk then current=readValue==true end\n        local ok,result=pcall(ctx.setBuyContinueMode,not current)\n        fingerprints.buy=""\n        return jsonResponse(ok and 200 or 400,{ok=ok,active=ok and result==true or false,error=ok and nil or tostring(result)})\n    elseif action=="trade.item.update" then\n        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end'''
if action_anchor not in module:
    raise SystemExit('action anchor missing')
module = module.replace(action_anchor, action_insert, 1)
module_path.write_text(module, encoding='utf-8')

html_path = Path('ArzMarket/html/index.html')
html = html_path.read_text(encoding='utf-8')
old_toolbar = '''            <button id="addButton" class="btn btn-secondary" type="button">+ Добавить</button>\n            <button id="scanButton" class="btn btn-secondary btn-compact" type="button" title="Сканировать источник товаров">Скан</button>'''
new_toolbar = '''            <button id="addButton" class="btn btn-secondary" type="button">+ Добавить</button>\n            <button id="undoButton" class="btn btn-secondary btn-icon" type="button" title="Вернуть последний удаленный товар, Ctrl+Z">↶</button>\n            <button id="clearButton" class="btn btn-secondary btn-compact btn-destructive" type="button" title="Очистить активный список">Очистить</button>\n            <button id="scanButton" class="btn btn-secondary btn-compact" type="button" title="Сканировать источник товаров">Скан</button>\n            <button id="continueButton" class="btn btn-secondary btn-compact" type="button" title="Продолжить скупку с оставшегося количества">Продолжить</button>'''
if old_toolbar not in html:
    raise SystemExit('toolbar anchor missing')
html = html.replace(old_toolbar, new_toolbar, 1)
html_path.write_text(html, encoding='utf-8')

css_path = Path('ArzMarket/html/css/style.css')
css = css_path.read_text(encoding='utf-8')
css_anchor = '.btn-compact { min-width:58px; padding:0 10px; }'
css_extra = '''.btn-compact { min-width:58px; padding:0 10px; }\n.btn-icon { width:38px; min-width:38px; padding:0; font-size:17px; }\n.btn-destructive { color:#b97580; }\n.btn-destructive:hover:not(:disabled), .btn-destructive.confirming { color:#ff7c91; border-color:rgba(239,80,104,.34); background:rgba(239,80,104,.07); }'''
if css_anchor not in css:
    raise SystemExit('css anchor missing')
css = css.replace(css_anchor, css_extra, 1)
css_path.write_text(css, encoding='utf-8')

js_path = Path('ArzMarket/html/js/app.js')
js = js_path.read_text(encoding='utf-8')

old_state_js = '''    requestBusy: false,\n    toastTimer: 0'''
new_state_js = '''    requestBusy: false,\n    toastTimer: 0,\n    clearArmedUntil: 0'''
if old_state_js not in js:
    raise SystemExit('JS state anchor missing')
js = js.replace(old_state_js, new_state_js, 1)

old_refs = '''    addButton: el('addButton'), scanButton: el('scanButton'), currencyButton: el('currencyButton'),\n    refreshButton: el('refreshButton'), pricesButton: el('pricesButton'), averageButton: el('averageButton'), startButton: el('startButton'),'''
new_refs = '''    addButton: el('addButton'), undoButton: el('undoButton'), clearButton: el('clearButton'), scanButton: el('scanButton'),\n    continueButton: el('continueButton'), currencyButton: el('currencyButton'), refreshButton: el('refreshButton'),\n    pricesButton: el('pricesButton'), averageButton: el('averageButton'), startButton: el('startButton'),'''
if old_refs not in js:
    raise SystemExit('JS refs anchor missing')
js = js.replace(old_refs, new_refs, 1)

old_header = '''    refs.scanButton.textContent = scanActive ? 'Стоп скан' : 'Скан';\n    refs.scanButton.classList.toggle('active-action', scanActive);\n    refs.scanButton.disabled = busy;\n    refs.refreshButton.classList.toggle('hidden', !buy);'''
new_header = '''    refs.scanButton.textContent = scanActive ? 'Стоп скан' : 'Скан';\n    refs.scanButton.classList.toggle('active-action', scanActive);\n    refs.scanButton.disabled = busy;\n    const undoCount = Number(state.data?.common?.undoCount || 0);\n    const itemCount = Array.isArray(state.data?.data?.items) ? state.data.data.items.length : 0;\n    refs.undoButton.disabled = busy || undoCount < 1;\n    refs.clearButton.disabled = busy || itemCount < 1;\n    const clearArmed = Date.now() < state.clearArmedUntil;\n    refs.clearButton.textContent = clearArmed ? 'Точно?' : 'Очистить';\n    refs.clearButton.classList.toggle('confirming', clearArmed);\n    const buyContinue = state.data?.common?.buyContinue === true;\n    refs.continueButton.classList.toggle('hidden', !buy);\n    refs.continueButton.classList.toggle('active-action', buyContinue);\n    refs.continueButton.textContent = buyContinue ? 'Продолжение: Вкл' : 'Продолжить';\n    refs.continueButton.disabled = busy;\n    refs.refreshButton.classList.toggle('hidden', !buy);'''
if old_header not in js:
    raise SystemExit('JS header anchor missing')
js = js.replace(old_header, new_header, 1)

old_table_count = '''      row.append(div(item.maximum && !buy ? 'Макс.' : money(item.count), 'count'));'''
new_table_count = '''      row.append(div(item.maximum ? (buy ? `Макс. ${money(item.count_maximum)}` : 'Макс.') : money(item.count), 'count'));'''
if old_table_count not in js:
    raise SystemExit('JS table count anchor missing')
js = js.replace(old_table_count, new_table_count, 1)

old_details = '''    const count = div('', 'field-row');\n    count.append(\n      numberField('Количество', item.count, 'count'),\n      state.page === 'buy' ? numberField('Осталось', item.continue, 'continue') : numberField('Доступно', item.all_count, 'all_count', true)\n    );\n    refs.detailFields.append(count);\n    if (state.page === 'sell') refs.detailFields.append(toggleField('Выставлять максимум', item.maximum === true, 'maximum'));\n    refs.detailFields.append(toggleField('Статус товара', item.enabled !== false, 'enabled'));'''
new_details = '''    const count = div('', 'field-row');\n    count.append(\n      numberField('Количество', item.count, 'count'),\n      state.page === 'buy' ? numberField('Осталось', item.continue, 'continue', true) : numberField('Доступно', item.all_count, 'all_count', true)\n    );\n    refs.detailFields.append(count);\n    if (state.page === 'buy') {\n      refs.detailFields.append(toggleField('Режим максимального количества', item.maximum === true, 'maximum'));\n      if (item.maximum === true) {\n        const maximum = div('', 'field-row');\n        maximum.append(numberField('Рассчитано максимум', item.count_maximum, 'count_maximum', true));\n        refs.detailFields.append(maximum);\n      }\n    } else {\n      refs.detailFields.append(toggleField('Выставлять максимум', item.maximum === true, 'maximum'));\n    }\n    refs.detailFields.append(toggleField('Статус товара', item.enabled !== false, 'enabled'));'''
if old_details not in js:
    raise SystemExit('JS details anchor missing')
js = js.replace(old_details, new_details, 1)

old_remove_toast = "      showToast('Товар удален', 'success');"
new_remove_toast = "      showToast('Товар удален. Ctrl+Z вернет его', 'success');"
if old_remove_toast in js:
    js = js.replace(old_remove_toast, new_remove_toast, 1)

listener_anchor = '''  refs.addButton.addEventListener('click', openPicker);\n  refs.scanButton.addEventListener('click', async () => {'''
listener_insert = '''  refs.addButton.addEventListener('click', openPicker);\n  refs.undoButton.addEventListener('click', async () => {\n    if (tradeBusy() || Number(state.data?.common?.undoCount || 0) < 1) return;\n    try {\n      await action('trade.item.undo', {side: state.page});\n      showToast('Удаленный товар возвращен', 'success');\n      await refresh(true);\n    } catch (err) { showToast(`Возврат: ${err.message}`, 'error'); }\n  });\n  refs.clearButton.addEventListener('click', async () => {\n    if (tradeBusy() || !(state.data?.data?.items || []).length) return;\n    if (Date.now() >= state.clearArmedUntil) {\n      state.clearArmedUntil = Date.now() + 2400;\n      renderHeader();\n      setTimeout(() => { if (Date.now() >= state.clearArmedUntil) renderHeader(); }, 2500);\n      return;\n    }\n    state.clearArmedUntil = 0;\n    try {\n      await action('trade.list.clear', {side: state.page});\n      state.selectedItem = null;\n      state.selectedKey = null;\n      showToast('Список очищен', 'success');\n      await refresh(true);\n    } catch (err) { showToast(`Очистка: ${err.message}`, 'error'); }\n  });\n  refs.continueButton.addEventListener('click', async () => {\n    if (tradeBusy() || state.page !== 'buy') return;\n    try {\n      await action('buy.continue.toggle', {side: 'buy'});\n      await refresh(true);\n    } catch (err) { showToast(`Продолжение скупки: ${err.message}`, 'error'); }\n  });\n  refs.scanButton.addEventListener('click', async () => {'''
if listener_anchor not in js:
    raise SystemExit('JS listener anchor missing')
js = js.replace(listener_anchor, listener_insert, 1)

keydown_anchor = '''  document.addEventListener('keydown', event => {\n    if (event.key === 'Escape') {'''
keydown_new = '''  document.addEventListener('keydown', event => {\n    const tag = String(event.target?.tagName || '').toLowerCase();\n    const textInput = tag === 'input' || tag === 'textarea' || tag === 'select' || event.target?.isContentEditable === true;\n    if (event.ctrlKey && !event.shiftKey && String(event.key).toLowerCase() === 'z' && !textInput) {\n      event.preventDefault();\n      if (!tradeBusy() && Number(state.data?.common?.undoCount || 0) > 0) refs.undoButton.click();\n      return;\n    }\n    if (event.key === 'Escape') {'''
if keydown_anchor not in js:
    raise SystemExit('JS keydown anchor missing')
js = js.replace(keydown_anchor, keydown_new, 1)

js_path.write_text(js, encoding='utf-8')
print('patched list management, undo and buy continuation')
