from pathlib import Path

main_path = Path('by_Quant_ArzMarket[3_56].lua')
main = main_path.read_text(encoding='utf-8')
anchor = '\tctx.getTradeUndoCount = function(side)'
insert = '''\tctx.getTradeAddDefaults = function(side)\n\t\tside = side == "sell" and "sell" or "buy"\n\t\tlocal defaults = side == "sell" and sellDefaults or buyDefaults\n\t\treturn {\n\t\t\tprice = tonumber(defaults and defaults.price) or (side == "sell" and 9 or 10),\n\t\t\tcount = math.max(1, math.floor(tonumber(defaults and defaults.count) or 1)),\n\t\t\tsort_mode = sortMode and true or false\n\t\t}\n\tend\n''' + anchor
if 'ctx.getTradeAddDefaults = function(side)' not in main:
    if anchor not in main:
        raise SystemExit('core defaults anchor missing')
    main = main.replace(anchor, insert, 1)
main_path.write_text(main, encoding='utf-8')

module_path = Path('modules/arz_html_ui.lua')
module = module_path.read_text(encoding='utf-8')
if '    module_version = 11,' in module:
    module = module.replace('    module_version = 11,', '    module_version = 12,', 1)
elif '    module_version = 12,' not in module:
    raise SystemExit('unexpected bridge module version')

old_add = '''    local item\n    if side=="buy" then\n        item={continue=1,enabled=true,maximum=false,count_maximum=0,price_vc=10,name=luaName,price=10,count=1,item_id=src.item_id}\n    else\n        item={enabled=true,price_vc=9,maximum=true,name=luaName,price=9,count=1,\n            slot_count=src.slot_count,slot_id=src.slot_id,all_count=src.all_count,item_id=src.item_id}\n    end\n    if type(addToData)=="function" then\n        local addOk=pcall(addToData,item,list,nil)\n        if not addOk then return false,"add_failed" end\n    else\n        table.insert(list,item)\n    end'''
new_add = '''    local defaults={price=side=="sell" and 9 or 10,count=1,sort_mode=false}\n    if ctx and type(ctx.getTradeAddDefaults)=="function" then\n        local ok,value=pcall(ctx.getTradeAddDefaults,side)\n        if ok and type(value)=="table" then defaults=value end\n    end\n    local defaultPrice=saneNumber(defaults.price,side=="sell" and 9 or 10) or (side=="sell" and 9 or 10)\n    local defaultCount=math.max(1,math.floor(saneNumber(defaults.count,1) or 1))\n    local item\n    if side=="buy" then\n        item={continue=1,enabled=true,maximum=false,count_maximum=0,price_vc=10,name=luaName,price=defaultPrice,count=defaultCount,item_id=src.item_id}\n    else\n        local available=math.max(0,math.floor(saneNumber(src.all_count,0) or 0))\n        if available<defaultCount then return false,"not_enough_items" end\n        item={enabled=true,price_vc=9,maximum=true,name=luaName,price=defaultPrice,count=defaultCount,\n            slot_count=src.slot_count,slot_id=src.slot_id,all_count=src.all_count,item_id=src.item_id}\n    end\n    if type(addToData)=="function" then\n        local addOk=pcall(addToData,item,list,defaults.sort_mode and 1 or nil)\n        if not addOk then return false,"add_failed" end\n    else\n        table.insert(list,item)\n    end'''
if old_add not in module:
    raise SystemExit('bridge add item anchor missing')
module = module.replace(old_add, new_add, 1)
module_path.write_text(module, encoding='utf-8')

js_path = Path('ArzMarket/html/js/app.js')
js = js_path.read_text(encoding='utf-8')
old_catch = '''        } catch (err) {\n          showToast(`Не удалось добавить: ${err.message}`, 'error');\n        }'''
new_catch = '''        } catch (err) {\n          const message = err.message === 'not_enough_items' ? 'Недостаточно предметов для значения по умолчанию' : err.message;\n          showToast(`Не удалось добавить: ${message}`, 'error');\n        }'''
if old_catch not in js:
    raise SystemExit('JS picker error anchor missing')
js = js.replace(old_catch, new_catch, 1)
js_path.write_text(js, encoding='utf-8')

print('patched HTML add defaults and sell inventory validation')
