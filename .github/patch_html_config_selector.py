from pathlib import Path

main_path = Path('by_Quant_ArzMarket[3_56].lua')
main = main_path.read_text(encoding='utf-8')
anchor = '''\tctx.cancelTrade = function()\n\t\tif type(off_sell_buy) ~= "function" then return false end\n\t\toff_sell_buy()\n\t\treturn true\n\tend\n\treturn ctx\nend'''
replacement = '''\tctx.cancelTrade = function()\n\t\tif type(off_sell_buy) ~= "function" then return false end\n\t\toff_sell_buy()\n\t\treturn true\n\tend\n\tctx.listTradeConfigs = function(side)\n\t\tside = side == "sell" and "sell" or "buy"\n\t\tlocal directory = "moonloader/ArzMarket/" .. side .. "-cfg"\n\t\tlocal out = {}\n\t\tif type(lfs) ~= "table" or type(lfs.dir) ~= "function" or not doesDirectoryExist(directory) then\n\t\t\treturn out\n\t\tend\n\t\tlocal ok = pcall(function()\n\t\t\tfor fileName in lfs.dir(directory) do\n\t\t\t\tif type(fileName) == "string" and fileName:match("%.json$") then\n\t\t\t\t\tout[#out + 1] = fileName\n\t\t\t\tend\n\t\t\tend\n\t\tend)\n\t\tif not ok then return {} end\n\t\ttable.sort(out, function(a, b) return string.lower(a) < string.lower(b) end)\n\t\treturn out\n\tend\n\tctx.loadTradeConfig = function(side, fileName)\n\t\tside = side == "sell" and "sell" or "buy"\n\t\tfileName = tostring(fileName or ""):gsub("^%s+", ""):gsub("%s+$", "")\n\t\tif fileName == "" or fileName:find("[/\\\\]") or fileName:find("..", 1, true) or not fileName:match("^[^%c]+%.json$") then\n\t\t\treturn false, "invalid_config_name"\n\t\tend\n\t\tlocal path = "moonloader/ArzMarket/" .. side .. "-cfg/" .. fileName\n\t\tif not doesFileExist(path) or type(loadConfig) ~= "function" then return false, "config_missing" end\n\t\tlocal ok, loaded = pcall(loadConfig, path)\n\t\tif not ok or type(loaded) ~= "table" then return false, "config_invalid" end\n\t\tif side == "buy" then\n\t\t\tbuyList = loaded\n\t\t\tloadedBuyConfig = fileName\n\t\t\tini.cfg.load_config_buy = fileName\n\t\t\tconfigFileNames.buy = fileName\n\t\telse\n\t\t\tsellList = loaded\n\t\t\tloadedSellConfig = fileName\n\t\t\tini.cfg.load_config_sell = fileName\n\t\t\tconfigFileNames.sell = fileName\n\t\tend\n\t\tif type(tradeFilterInvalidate) == "function" then pcall(tradeFilterInvalidate, side) end\n\t\tif type(save_all) == "function" then save_all() end\n\t\treturn true\n\tend\n\treturn ctx\nend'''
if anchor not in main:
    raise SystemExit('main context anchor not found')
main = main.replace(anchor, replacement, 1)
main_path.write_text(main, encoding='utf-8')

module_path = Path('modules/arz_html_ui.lua')
module = module_path.read_text(encoding='utf-8')
if '    module_version = 8,' not in module:
    raise SystemExit('module version 8 anchor not found')
module = module.replace('    module_version = 8,', '    module_version = 9,', 1)

anchor_cfg = '''local function configName(side)\n    if not ctx or type(ctx.getLoadedConfigs)~="function" then return "" end\n    local sell,buy=ctx.getLoadedConfigs()\n    return normalizeConfig(side=="buy" and buy or sell)\nend'''
replacement_cfg = anchor_cfg + '''\nlocal function configList(side)\n    if not ctx or type(ctx.listTradeConfigs)~="function" then return {} end\n    local ok,value=pcall(ctx.listTradeConfigs,side)\n    if not ok or type(value)~="table" then return {} end\n    local out={}\n    for i=1,#value do\n        local name=normalizeConfig(value[i])\n        if name~="" then out[#out+1]=name:gsub("%.json$","") end\n    end\n    return out\nend'''
if anchor_cfg not in module:
    raise SystemExit('configName anchor not found')
module = module.replace(anchor_cfg, replacement_cfg, 1)

old_state = '''    local cfg=configName(page)\n    local source=sources(page)\n    local runtimeKey=table.concat({\n        tostring(active),tostring(busy),tostring(snapshot.buy==true),tostring(snapshot.sell==true),\n        tostring(score),tostring(total),tostring(cfg),sourceFingerprint(source)\n    },"\\30")'''
new_state = '''    local cfg=configName(page)\n    local configs=configList(page)\n    local source=sources(page)\n    local runtimeKey=table.concat({\n        tostring(active),tostring(busy),tostring(snapshot.buy==true),tostring(snapshot.sell==true),\n        tostring(score),tostring(total),tostring(cfg),table.concat(configs,"\\29"),sourceFingerprint(source)\n    },"\\30")'''
if old_state not in module:
    raise SystemExit('state runtime anchor not found')
module = module.replace(old_state, new_state, 1)

old_common = '''        common={uiMode="html",activeConfig=cfg~="" and cfg:gsub("%.json$","") or "",\n            automation=active,tradeBusy=busy,automationBuy=snapshot.buy==true,automationSell=snapshot.sell==true,'''
new_common = '''        common={uiMode="html",activeConfig=cfg~="" and cfg:gsub("%.json$","") or "",configs=configs,\n            automation=active,tradeBusy=busy,automationBuy=snapshot.buy==true,automationSell=snapshot.sell==true,'''
if old_common not in module:
    raise SystemExit('common state anchor not found')
module = module.replace(old_common, new_common, 1)

old_action = '''    elseif action=="ui.navigate" then\n        currentPage=side\n        return jsonResponse(200,{ok=true,page=side})\n    elseif action=="trade.item.update" then'''
new_action = '''    elseif action=="ui.navigate" then\n        currentPage=side\n        return jsonResponse(200,{ok=true,page=side})\n    elseif action=="trade.config.load" then\n        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end\n        if not ctx or type(ctx.loadTradeConfig)~="function" then return jsonResponse(400,{ok=false,error="config_loader_unavailable"}) end\n        local ok,result,err=pcall(ctx.loadTradeConfig,side,data.name)\n        local success=ok and result~=false\n        sourceCache[side].at=0\n        fingerprints[side]=""\n        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or (ok and err or tostring(result))})\n    elseif action=="trade.item.update" then'''
if old_action not in module:
    raise SystemExit('action anchor not found')
module = module.replace(old_action, new_action, 1)
module_path.write_text(module, encoding='utf-8')

index_path = Path('ArzMarket/html/index.html')
index = index_path.read_text(encoding='utf-8')
old_select = '<label class="config-label">Конфиг<select id="configSelect" class="select" disabled><option>Не выбран</option></select></label>'
new_select = '<label class="config-label">Конфиг<select id="configSelect" class="select"><option>Не выбран</option></select></label>'
if old_select not in index:
    raise SystemExit('config select anchor not found')
index = index.replace(old_select, new_select, 1)
index_path.write_text(index, encoding='utf-8')

app_path = Path('ArzMarket/html/js/app.js')
js = app_path.read_text(encoding='utf-8')
old_render = '''    refs.configSelect.innerHTML = '';\n    const option = document.createElement('option');\n    option.textContent = state.data?.common?.activeConfig || 'Не выбран';\n    refs.configSelect.append(option);'''
new_render = '''    const activeConfig = state.data?.common?.activeConfig || '';\n    const configs = Array.isArray(state.data?.common?.configs) ? state.data.common.configs : [];\n    refs.configSelect.innerHTML = '';\n    if (!configs.length) {\n      const option = document.createElement('option');\n      option.value = '';\n      option.textContent = activeConfig || 'Не выбран';\n      refs.configSelect.append(option);\n    } else {\n      if (!activeConfig) {\n        const none = document.createElement('option');\n        none.value = '';\n        none.textContent = 'Не выбран';\n        refs.configSelect.append(none);\n      }\n      for (const name of configs) {\n        const option = document.createElement('option');\n        option.value = name;\n        option.textContent = name;\n        option.selected = name === activeConfig;\n        refs.configSelect.append(option);\n      }\n    }\n    refs.configSelect.disabled = busy || configs.length === 0;'''
if old_render not in js:
    raise SystemExit('JS config render anchor not found')
js = js.replace(old_render, new_render, 1)

listener_anchor = '''  refs.searchInput.addEventListener('input', () => {\n    state.search = refs.searchInput.value;\n    renderTable();\n  });\n  refs.addButton.addEventListener('click', openPicker);'''
listener_replacement = '''  refs.searchInput.addEventListener('input', () => {\n    state.search = refs.searchInput.value;\n    renderTable();\n  });\n  refs.configSelect.addEventListener('change', async () => {\n    const name = refs.configSelect.value;\n    if (!name || tradeBusy()) return;\n    refs.configSelect.disabled = true;\n    try {\n      await action('trade.config.load', {side: state.page, name});\n      state.selectedItem = null;\n      state.selectedKey = null;\n      showToast(`Конфиг «${name}» загружен`, 'success');\n      await refresh(true);\n    } catch (err) {\n      showToast(`Конфиг: ${err.message}`, 'error');\n      await refresh(true);\n    }\n  });\n  refs.addButton.addEventListener('click', openPicker);'''
if listener_anchor not in js:
    raise SystemExit('JS listener anchor not found')
js = js.replace(listener_anchor, listener_replacement, 1)
app_path.write_text(js, encoding='utf-8')

print('patched config selector and bridge')
