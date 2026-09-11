from pathlib import Path

main_path = Path('by_Quant_ArzMarket[3_56].lua')
main = main_path.read_text(encoding='utf-8')
anchor = '\tctx.getTradeAddDefaults = function(side)'
insert = '''\tctx.previewBuyBudget = function(totalBudget)\n\t\ttotalBudget = tonumber(totalBudget)\n\t\tif not totalBudget or totalBudget < 0 then return false, "invalid_budget" end\n\t\tlocal eligible = {}\n\t\tfor _, itemData in pairs(buyList or {}) do\n\t\t\tif type(itemData) == "table" and itemData.enabled and not itemData.maximum then\n\t\t\t\teligible[#eligible + 1] = itemData\n\t\t\tend\n\t\tend\n\t\tif #eligible == 0 then return false, "no_eligible_items" end\n\t\tlocal budgetPerItem = math.floor(totalBudget) / #eligible\n\t\tlocal spent = 0\n\t\tfor _, itemData in ipairs(eligible) do\n\t\t\tlocal itemPrice = tonumber(viceCityMode and itemData.price or itemData.price_vc) or 0\n\t\t\tif itemPrice > 0 then\n\t\t\t\tlocal itemCount = math.floor(budgetPerItem / itemPrice)\n\t\t\t\tspent = spent + itemCount * itemPrice\n\t\t\tend\n\t\tend\n\t\tlocal moneyNow = tonumber(ini.cfg.realMoneyNow) or 0\n\t\treturn true, { eligible = #eligible, spent = spent, remaining = moneyNow - spent, budget = math.floor(totalBudget) }\n\tend\n\tctx.distributeBuyBudget = function(totalBudget)\n\t\ttotalBudget = tonumber(totalBudget)\n\t\tif not totalBudget or totalBudget < 0 then return false, "invalid_budget" end\n\t\tif loadedBuyConfig == "" then return false, "config_not_loaded" end\n\t\tlocal eligible = {}\n\t\tfor _, itemData in pairs(buyList or {}) do\n\t\t\tif type(itemData) == "table" and itemData.enabled and not itemData.maximum then\n\t\t\t\teligible[#eligible + 1] = itemData\n\t\t\tend\n\t\tend\n\t\tif #eligible == 0 then return false, "no_eligible_items" end\n\t\tlocal budgetPerItem = math.floor(totalBudget) / #eligible\n\t\tlocal backups = {}\n\t\tlocal spent = 0\n\t\tfor _, itemData in ipairs(eligible) do\n\t\t\tbackups[#backups + 1] = { item = itemData, count = itemData.count }\n\t\t\tlocal itemPrice = tonumber(viceCityMode and itemData.price or itemData.price_vc) or 0\n\t\t\tif itemPrice > 0 then\n\t\t\t\tlocal itemCount = math.floor(budgetPerItem / itemPrice)\n\t\t\t\titemData.count = math.floor(itemCount)\n\t\t\t\tspent = spent + itemData.count * itemPrice\n\t\t\tend\n\t\tend\n\t\tlocal fileName = loadedBuyConfig:match("%.json$") and loadedBuyConfig or loadedBuyConfig .. ".json"\n\t\tlocal saveOk = type(createConfig) == "function" and createConfig("buy-cfg/" .. fileName, buyList, "buy-cfg", fileName) ~= false\n\t\tif not saveOk then\n\t\t\tfor _, backup in ipairs(backups) do backup.item.count = backup.count end\n\t\t\treturn false, "save_failed"\n\t\tend\n\t\tif type(tradeFilterInvalidate) == "function" then pcall(tradeFilterInvalidate, "buy") end\n\t\tlocal moneyNow = tonumber(ini.cfg.realMoneyNow) or 0\n\t\treturn true, { eligible = #eligible, spent = spent, remaining = moneyNow - spent, budget = math.floor(totalBudget) }\n\tend\n''' + anchor
if 'ctx.previewBuyBudget = function(totalBudget)' not in main:
    if anchor not in main:
        raise SystemExit('core budget anchor missing')
    main = main.replace(anchor, insert, 1)
main_path.write_text(main, encoding='utf-8')

module_path = Path('modules/arz_html_ui.lua')
module = module_path.read_text(encoding='utf-8')
if '    module_version = 12,' in module:
    module = module.replace('    module_version = 12,', '    module_version = 13,', 1)
elif '    module_version = 13,' not in module:
    raise SystemExit('unexpected bridge module version')

action_anchor = '''    elseif action=="buy.continue.toggle" then\n        if side~="buy" then return jsonResponse(400,{ok=false,error="buy_only"}) end'''
action_insert = '''    elseif action=="buy.budget.preview" then\n        if side~="buy" then return jsonResponse(400,{ok=false,error="buy_only"}) end\n        if not ctx or type(ctx.previewBuyBudget)~="function" then return jsonResponse(400,{ok=false,error="budget_unavailable"}) end\n        local ok,result,dataOrErr=pcall(ctx.previewBuyBudget,data.budget)\n        local success=ok and result~=false\n        return jsonResponse(success and 200 or 400,{ok=success,data=success and dataOrErr or nil,error=success and nil or (ok and dataOrErr or tostring(result))})\n    elseif action=="buy.budget.apply" then\n        if side~="buy" then return jsonResponse(400,{ok=false,error="buy_only"}) end\n        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end\n        if not ctx or type(ctx.distributeBuyBudget)~="function" then return jsonResponse(400,{ok=false,error="budget_unavailable"}) end\n        local ok,result,dataOrErr=pcall(ctx.distributeBuyBudget,data.budget)\n        local success=ok and result~=false\n        fingerprints.buy=""\n        return jsonResponse(success and 200 or 400,{ok=success,data=success and dataOrErr or nil,error=success and nil or (ok and dataOrErr or tostring(result))})\n    elseif action=="buy.continue.toggle" then\n        if side~="buy" then return jsonResponse(400,{ok=false,error="buy_only"}) end'''
if action_anchor not in module:
    raise SystemExit('budget action anchor missing')
module = module.replace(action_anchor, action_insert, 1)
module_path.write_text(module, encoding='utf-8')

html_path = Path('ArzMarket/html/index.html')
html = html_path.read_text(encoding='utf-8')
old_toolbar = '''            <button id="continueButton" class="btn btn-secondary btn-compact" type="button" title="Продолжить скупку с оставшегося количества">Продолжить</button>\n            <button id="currencyButton" class="btn btn-secondary btn-compact" type="button" title="Переключить валюту">SA$</button>'''
new_toolbar = '''            <button id="continueButton" class="btn btn-secondary btn-compact" type="button" title="Продолжить скупку с оставшегося количества">Продолжить</button>\n            <button id="budgetButton" class="btn btn-secondary btn-compact" type="button" title="Распределить бюджет между товарами">Бюджет</button>\n            <button id="currencyButton" class="btn btn-secondary btn-compact" type="button" title="Переключить валюту">SA$</button>'''
if old_toolbar not in html:
    raise SystemExit('budget toolbar anchor missing')
html = html.replace(old_toolbar, new_toolbar, 1)

modal_anchor = '''    <div id="toast" class="toast hidden"></div>'''
budget_modal = '''    <div id="budgetBackdrop" class="modal-backdrop hidden">\n      <div class="modal budget-modal">\n        <div class="modal-head"><div><h2>Распределить бюджет</h2><p>Бюджет делится поровну между активными товарами без режима максимума</p></div><button class="window-btn" type="button" data-action="budget-close">×</button></div>\n        <label class="field budget-field"><span class="field-label">Количество вирт на скупку</span><input id="budgetInput" class="field-input" type="number" min="0" step="1" autocomplete="off" placeholder="0"></label>\n        <div class="budget-summary">\n          <div><span>Подходящих товаров</span><strong id="budgetEligible">0</strong></div>\n          <div><span>Будет потрачено</span><strong id="budgetSpent">0</strong></div>\n          <div><span>Примерный остаток</span><strong id="budgetRemaining">0</strong></div>\n        </div>\n        <div class="modal-actions"><button id="budgetCancel" class="btn btn-secondary" type="button">Отмена</button><button id="budgetApply" class="btn btn-primary" type="button">Распределить</button></div>\n      </div>\n    </div>\n''' + modal_anchor
if 'id="budgetBackdrop"' not in html:
    if modal_anchor not in html:
        raise SystemExit('budget modal anchor missing')
    html = html.replace(modal_anchor, budget_modal, 1)
html_path.write_text(html, encoding='utf-8')

css_path = Path('ArzMarket/html/css/style.css')
css = css_path.read_text(encoding='utf-8')
css += '''\n.budget-modal { width:min(520px,calc(100vw - 48px)); }\n.budget-field { margin-top:16px; }\n.budget-summary { margin-top:14px; display:grid; grid-template-columns:repeat(3,1fr); gap:8px; }\n.budget-summary > div { min-width:0; padding:12px; border:1px solid var(--border); border-radius:8px; background:#0b151d; }\n.budget-summary span { display:block; color:var(--text-muted); font-size:9px; margin-bottom:6px; }\n.budget-summary strong { display:block; overflow:hidden; text-overflow:ellipsis; color:#dce7ed; font-size:13px; font-weight:650; }\n.modal-actions { display:flex; justify-content:flex-end; gap:9px; margin-top:16px; }\n.modal-actions .btn-primary { margin-left:0; }\n'''
css_path.write_text(css, encoding='utf-8')

js_path = Path('ArzMarket/html/js/app.js')
js = js_path.read_text(encoding='utf-8')
old_state = '''    toastTimer: 0,\n    clearArmedUntil: 0'''
new_state = '''    toastTimer: 0,\n    clearArmedUntil: 0,\n    budgetPreviewTimer: 0'''
if old_state not in js:
    raise SystemExit('budget JS state anchor missing')
js = js.replace(old_state, new_state, 1)

old_refs = '''    continueButton: el('continueButton'), currencyButton: el('currencyButton'), refreshButton: el('refreshButton'),\n    pricesButton: el('pricesButton'), averageButton: el('averageButton'), startButton: el('startButton'),'''
new_refs = '''    continueButton: el('continueButton'), budgetButton: el('budgetButton'), currencyButton: el('currencyButton'), refreshButton: el('refreshButton'),\n    pricesButton: el('pricesButton'), averageButton: el('averageButton'), startButton: el('startButton'),'''
if old_refs not in js:
    raise SystemExit('budget JS refs anchor missing')
js = js.replace(old_refs, new_refs, 1)
old_refs2 = '''    pickerRows: el('pickerRows'), toast: el('toast')'''
new_refs2 = '''    pickerRows: el('pickerRows'), budgetBackdrop: el('budgetBackdrop'), budgetInput: el('budgetInput'),\n    budgetEligible: el('budgetEligible'), budgetSpent: el('budgetSpent'), budgetRemaining: el('budgetRemaining'),\n    budgetCancel: el('budgetCancel'), budgetApply: el('budgetApply'), toast: el('toast')'''
if old_refs2 not in js:
    raise SystemExit('budget modal refs anchor missing')
js = js.replace(old_refs2, new_refs2, 1)

header_anchor = '''    refs.continueButton.disabled = busy;\n    refs.refreshButton.classList.toggle('hidden', !buy);'''
header_new = '''    refs.continueButton.disabled = busy;\n    refs.budgetButton.classList.toggle('hidden', !buy);\n    refs.budgetButton.disabled = busy || !(state.data?.data?.items || []).length;\n    refs.refreshButton.classList.toggle('hidden', !buy);'''
if header_anchor not in js:
    raise SystemExit('budget header anchor missing')
js = js.replace(header_anchor, header_new, 1)

function_anchor = '''  function closePicker() {\n    refs.pickerBackdrop.classList.add('hidden');\n  }'''
budget_functions = function_anchor + '''\n\n  function closeBudget() {\n    refs.budgetBackdrop.classList.add('hidden');\n    clearTimeout(state.budgetPreviewTimer);\n  }\n\n  async function refreshBudgetPreview() {\n    const budget = Number(refs.budgetInput.value);\n    if (!Number.isFinite(budget) || budget < 0) {\n      refs.budgetEligible.textContent = '0';\n      refs.budgetSpent.textContent = '0';\n      refs.budgetRemaining.textContent = '0';\n      refs.budgetApply.disabled = true;\n      return;\n    }\n    try {\n      const result = await action('buy.budget.preview', {side: 'buy', budget});\n      const data = result.data || {};\n      refs.budgetEligible.textContent = money(data.eligible || 0);\n      refs.budgetSpent.textContent = `${money(data.spent || 0)} ${state.data?.common?.currencyMode === 'VC' ? 'VC$' : 'SA$'}`;\n      refs.budgetRemaining.textContent = money(data.remaining || 0);\n      refs.budgetApply.disabled = false;\n    } catch (err) {\n      refs.budgetEligible.textContent = '0';\n      refs.budgetSpent.textContent = '0';\n      refs.budgetRemaining.textContent = '0';\n      refs.budgetApply.disabled = true;\n    }\n  }\n\n  function openBudget() {\n    if (tradeBusy() || state.page !== 'buy') return;\n    refs.budgetInput.value = '';\n    refs.budgetEligible.textContent = '0';\n    refs.budgetSpent.textContent = '0';\n    refs.budgetRemaining.textContent = '0';\n    refs.budgetApply.disabled = true;\n    refs.budgetBackdrop.classList.remove('hidden');\n    setTimeout(() => refs.budgetInput.focus(), 30);\n  }'''
if function_anchor not in js:
    raise SystemExit('budget function anchor missing')
js = js.replace(function_anchor, budget_functions, 1)

click_anchor = '''    if (name === 'picker-close') closePicker();'''
click_new = '''    if (name === 'picker-close') closePicker();\n    if (name === 'budget-close') closeBudget();'''
if click_anchor not in js:
    raise SystemExit('budget close action anchor missing')
js = js.replace(click_anchor, click_new, 1)

listener_anchor = '''  refs.continueButton.addEventListener('click', async () => {\n    if (tradeBusy() || state.page !== 'buy') return;'''
listener_new = '''  refs.budgetButton.addEventListener('click', openBudget);\n  refs.budgetCancel.addEventListener('click', closeBudget);\n  refs.budgetBackdrop.addEventListener('click', event => { if (event.target === refs.budgetBackdrop) closeBudget(); });\n  refs.budgetInput.addEventListener('input', () => {\n    clearTimeout(state.budgetPreviewTimer);\n    state.budgetPreviewTimer = setTimeout(refreshBudgetPreview, 180);\n  });\n  refs.budgetApply.addEventListener('click', async () => {\n    if (tradeBusy()) return;\n    const budget = Number(refs.budgetInput.value);\n    if (!Number.isFinite(budget) || budget < 0) return;\n    refs.budgetApply.disabled = true;\n    try {\n      const result = await action('buy.budget.apply', {side: 'buy', budget});\n      const data = result.data || {};\n      closeBudget();\n      showToast(`Распределение завершено. Остаток: ${money(data.remaining || 0)}`, 'success');\n      await refresh(true);\n    } catch (err) {\n      const labels = {invalid_budget:'Введите корректный бюджет',no_eligible_items:'Нет активных товаров для распределения',config_not_loaded:'Сначала загрузите конфиг'};\n      showToast(labels[err.message] || `Бюджет: ${err.message}`, 'error');\n      refs.budgetApply.disabled = false;\n    }\n  });\n  refs.continueButton.addEventListener('click', async () => {\n    if (tradeBusy() || state.page !== 'buy') return;'''
if listener_anchor not in js:
    raise SystemExit('budget listener anchor missing')
js = js.replace(listener_anchor, listener_new, 1)

esc_anchor = '''    if (event.key === 'Escape') {\n      if (!refs.pickerBackdrop.classList.contains('hidden')) {\n        closePicker();\n      } else if (!event.repeat) {'''
esc_new = '''    if (event.key === 'Escape') {\n      if (!refs.budgetBackdrop.classList.contains('hidden')) {\n        closeBudget();\n      } else if (!refs.pickerBackdrop.classList.contains('hidden')) {\n        closePicker();\n      } else if (!event.repeat) {'''
if esc_anchor not in js:
    raise SystemExit('budget Escape anchor missing')
js = js.replace(esc_anchor, esc_new, 1)
js_path.write_text(js, encoding='utf-8')

print('patched HTML buy budget distribution')
