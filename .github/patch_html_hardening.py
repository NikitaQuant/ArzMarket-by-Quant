from pathlib import Path
import re

bridge_path = Path("modules/arz_html_ui.lua")
app_path = Path("ArzMarket/html/js/app.js")

bridge = bridge_path.read_text(encoding="utf-8")
app = app_path.read_text(encoding="utf-8")

bridge = bridge.replace("module_version = 4,", "module_version = 5,", 1)

old_state = '''local function automationState(side)
    if not ctx or type(ctx.getTradeAutomationState)~="function" then return false,0,0 end
    local ok,state=pcall(ctx.getTradeAutomationState)
    if not ok or type(state)~="table" then return false,0,0 end
    return state[side]==true,saneNumber(state.score,0) or 0,saneNumber(state.score_from,0) or 0
end
'''
new_state = '''local function automationSnapshot()
    if not ctx or type(ctx.getTradeAutomationState)~="function" then return {sell=false,buy=false,score=0,score_from=0} end
    local ok,state=pcall(ctx.getTradeAutomationState)
    if not ok or type(state)~="table" then return {sell=false,buy=false,score=0,score_from=0} end
    return state
end
local function automationState(side)
    local state=automationSnapshot()
    return state[side]==true,saneNumber(state.score,0) or 0,saneNumber(state.score_from,0) or 0
end
local function tradeBusy()
    local state=automationSnapshot()
    return state.sell==true or state.buy==true
end
'''
if bridge.count(old_state) != 1:
    raise SystemExit("automationState block not found exactly once")
bridge = bridge.replace(old_state, new_state, 1)

old_state_for = '''    local active,score,total=automationState(page)
    local cfg=configName(page)
    local iconStatus=itemIcons and itemIcons.getStatus and itemIcons.getStatus() or {}
    return {
        revision=revision[page], page=page,
        common={uiMode="html",activeConfig=cfg~="" and cfg:gsub("%.json$","") or "",
            automation=active,automationScore=score,automationTotal=total,
            serverAddress=address,serverPort=serverPort,icons=iconStatus},
        data={items=items,source=sources(page)}
    }
'''
new_state_for = '''    local snapshot=automationSnapshot()
    local active=snapshot[page]==true
    local score=saneNumber(snapshot.score,0) or 0
    local total=saneNumber(snapshot.score_from,0) or 0
    local busy=snapshot.sell==true or snapshot.buy==true
    local cfg=configName(page)
    local iconStatus=itemIcons and itemIcons.getStatus and itemIcons.getStatus() or {}
    return {
        revision=revision[page], page=page,
        common={uiMode="html",activeConfig=cfg~="" and cfg:gsub("%.json$","") or "",
            automation=active,tradeBusy=busy,automationBuy=snapshot.buy==true,automationSell=snapshot.sell==true,
            automationScore=score,automationTotal=total,
            serverAddress=address,serverPort=serverPort,icons=iconStatus},
        data={items=items,source=sources(page)}
    }
'''
if bridge.count(old_state_for) != 1:
    raise SystemExit("stateFor automation block not found exactly once")
bridge = bridge.replace(old_state_for, new_state_for, 1)

for action_name in ("trade.item.update", "trade.item.remove", "trade.item.add"):
    old = f'''    elseif action=="{action_name}" then\n        local active=select(1,automationState(side))\n        if active then return jsonResponse(409,{{ok=false,error="trade_active"}}) end\n'''
    new = f'''    elseif action=="{action_name}" then\n        if tradeBusy() then return jsonResponse(409,{{ok=false,error="trade_active"}}) end\n'''
    if bridge.count(old) != 1:
        raise SystemExit(f"{action_name} guard not found exactly once")
    bridge = bridge.replace(old, new, 1)

old_avg = '''    elseif action=="buy.average.apply" then
        local active=select(1,automationState("buy"))
        if active then return jsonResponse(409,{ok=false,error="trade_active"}) end
'''
new_avg = '''    elseif action=="buy.average.apply" then
        if tradeBusy() then return jsonResponse(409,{ok=false,error="trade_active"}) end
'''
if bridge.count(old_avg) != 1:
    raise SystemExit("average guard not found exactly once")
bridge = bridge.replace(old_avg, new_avg, 1)

old_start_tail = '''        if not ctx or type(ctx.startTrade)~="function" then return jsonResponse(400,{ok=false,error="start_unavailable"}) end
        local ok,result=pcall(ctx.startTrade,side)
'''
new_start_tail = '''        if tradeBusy() then return jsonResponse(409,{ok=false,error="other_trade_active"}) end
        if not ctx or type(ctx.startTrade)~="function" then return jsonResponse(400,{ok=false,error="start_unavailable"}) end
        local ok,result=pcall(ctx.startTrade,side)
'''
if bridge.count(old_start_tail) != 1:
    raise SystemExit("trade.start tail not found exactly once")
bridge = bridge.replace(old_start_tail, new_start_tail, 1)

old_csp = '''        "Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data: file:; connect-src 'self'; object-src 'none'; frame-ancestors *"'''
new_csp = '''        "Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; object-src 'none'"'''
if bridge.count(old_csp) != 1:
    raise SystemExit("CSP header not found exactly once")
bridge = bridge.replace(old_csp, new_csp, 1)

icon_pattern = re.compile(r"  function setIcon\(img, item, size\) \{\n.*?\n  \}\n\n  function showToast", re.S)
new_icon = '''  function setIcon(img, item, size) {
    const id = getItemId(item);
    if (!id) {
      img.onerror = null;
      img.src = placeholder();
      return;
    }
    img.onerror = () => {
      img.onerror = null;
      img.src = placeholder();
    };
    img.src = `/api/icon/${size}/${encodeURIComponent(id)}.webp?token=${encodeURIComponent(token)}`;
  }

  function showToast'''
app, count = icon_pattern.subn(new_icon, app, count=1)
if count != 1:
    raise SystemExit("setIcon function not replaced")

old_helpers = '''  const tradeActive = () => state.data?.common?.automation === true;
'''
new_helpers = '''  const tradeActive = () => state.data?.common?.automation === true;
  const tradeBusy = () => state.data?.common?.tradeBusy === true;
'''
if app.count(old_helpers) != 1:
    raise SystemExit("tradeActive helper not found exactly once")
app = app.replace(old_helpers, new_helpers, 1)

old_header = '''    const buy = state.page === 'buy';
    const active = tradeActive();
'''
new_header = '''    const buy = state.page === 'buy';
    const active = tradeActive();
    const busy = tradeBusy();
'''
if app.count(old_header) != 1:
    raise SystemExit("renderHeader head not found")
app = app.replace(old_header, new_header, 1)

old_header_status = '''    refs.automationBadge.textContent = active && total > 0 ? `Активен ${Math.min(score, total)}/${total}` : (active ? 'Активен' : 'Готов');
    refs.automationBadge.className = active ? 'badge badge-success' : 'badge badge-muted';
    refs.startButton.textContent = active ? 'Отмена' : (buy ? 'Старт скупки' : 'Начать продажу');
    refs.averageButton.classList.toggle('hidden', !buy);
    refs.averageButton.disabled = active;
    refs.addButton.disabled = active;
'''
new_header_status = '''    refs.automationBadge.textContent = active && total > 0 ? `Активен ${Math.min(score, total)}/${total}` : (active ? 'Активен' : (busy ? 'Занято' : 'Готов'));
    refs.automationBadge.className = active ? 'badge badge-success' : 'badge badge-muted';
    refs.startButton.textContent = active ? 'Отмена' : (buy ? 'Старт скупки' : 'Начать продажу');
    refs.startButton.disabled = busy && !active;
    refs.averageButton.classList.toggle('hidden', !buy);
    refs.averageButton.disabled = busy;
    refs.addButton.disabled = busy;
'''
if app.count(old_header_status) != 1:
    raise SystemExit("renderHeader status block not found")
app = app.replace(old_header_status, new_header_status, 1)

app = app.replace("    const locked = tradeActive();\n", "    const locked = tradeBusy();\n", 1)
app = app.replace("    input.disabled = readOnly || tradeActive();\n", "    input.disabled = readOnly || tradeBusy();\n", 1)
app = app.replace("    button.disabled = tradeActive();\n", "    button.disabled = tradeBusy();\n", 1)
app = app.replace("    button.addEventListener('click', () => { if (!tradeActive()) patchItem(state.selectedItem, {[key]: !enabled}); });\n", "    button.addEventListener('click', () => { if (!tradeBusy()) patchItem(state.selectedItem, {[key]: !enabled}); });\n", 1)

replacements = {
    "    if (!item || tradeActive()) return;\n": "    if (!item || tradeBusy()) return;\n",
    "    if (tradeActive()) return;\n": "    if (tradeBusy()) return;\n",
    "        if (tradeActive()) return;\n": "        if (tradeBusy()) return;\n",
}
for old, new in replacements.items():
    app = app.replace(old, new)

app = app.replace("  window.setInterval(() => refresh(false), 450);\n", "  window.setInterval(() => refresh(false), 650);\n", 1)

if "file:///arizona/items.zip" in app:
    raise SystemExit("undocumented file ZIP icon path still present")
if "const tradeBusy" not in app or "tradeBusy=busy" not in bridge:
    raise SystemExit("trade busy hardening missing")
if "frame-ancestors" in bridge or "img-src 'self' data: file:" in bridge:
    raise SystemExit("legacy CSP entries remain")

bridge_path.write_text(bridge, encoding="utf-8", newline="\n")
app_path.write_text(app, encoding="utf-8", newline="\n")
