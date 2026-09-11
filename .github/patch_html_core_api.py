from pathlib import Path
import re

main_path = Path("by_Quant_ArzMarket[3_56].lua")
bridge_path = Path("modules/arz_html_ui.lua")

main_text = main_path.read_text(encoding="utf-8")
bridge_text = bridge_path.read_text(encoding="utf-8")

main_marker = "\treturn ctx\nend\n\nfunction arzUiExtensionsEnsureDirectory()"
core_api = """\tctx.getTradeAutomationState = function()
\t\treturn {
\t\t\tsell = tradeAutomation.sell == true,
\t\t\tbuy = tradeAutomation.buy == true,
\t\t\tscore = tonumber(tradeAutomation.score) or 0,
\t\t\tscore_from = tonumber(tradeAutomation.score_from) or 0
\t\t}
\tend
\tctx.getCoreMenuVisible = function()
\t\treturn menuVisible and menuVisible[0] == true or false
\tend
\tctx.setCoreMenuVisible = function(value)
\t\tlocal nextValue = value == true
\t\tmenuOpen = nextValue
\t\tif menuVisible then
\t\t\tmenuVisible[0] = nextValue
\t\tend
\t\tif nextValue then
\t\t\tkifir = 1
\t\t\tonOpenMenu = true
\t\t\tzzztime = os.clock()
\t\telseif type(resetIO) == "function" then
\t\t\tpcall(resetIO)
\t\tend
\t\treturn true
\tend
\tctx.startTrade = function(side)
\t\tif type(sampProcessChatInput) ~= "function" then return false end
\t\tside = side == "sell" and "sell" or "buy"
\t\tsampProcessChatInput(side == "sell" and "/crsell" or "/crbuy")
\t\treturn true
\tend
\tctx.cancelTrade = function()
\t\tif type(off_sell_buy) ~= "function" then return false end
\t\toff_sell_buy()
\t\treturn true
\tend
"""

if "ctx.getTradeAutomationState = function()" not in main_text:
    if main_text.count(main_marker) != 1:
        raise SystemExit("core context marker not found exactly once")
    main_text = main_text.replace(main_marker, core_api + main_marker, 1)

bridge_debug_pattern = re.compile(
    r"local function findUpvalue\(fn,wanted\)\n.*?(?=local function selectLuaPage\(side\)\n)",
    re.S,
)
new_bridge_state = """local function automationState(side)
    if not ctx or type(ctx.getTradeAutomationState)~="function" then return false,0,0 end
    local ok,state=pcall(ctx.getTradeAutomationState)
    if not ok or type(state)~="table" then return false,0,0 end
    return state[side]==true,saneNumber(state.score,0) or 0,saneNumber(state.score_from,0) or 0
end
local function setMenuVisible(value)
    if not ctx or type(ctx.setCoreMenuVisible)~="function" then return false end
    local ok,result=pcall(ctx.setCoreMenuVisible,value==true)
    return ok and result~=false
end
"""

if "findUpvalue" in bridge_text or "debug.getupvalue" in bridge_text:
    bridge_text, replacements = bridge_debug_pattern.subn(new_bridge_state, bridge_text, count=1)
    if replacements != 1:
        raise SystemExit("legacy debug bridge block was not replaced")

bridge_text = bridge_text.replace("module_version = 3,", "module_version = 4,", 1)

trade_start_pattern = re.compile(
    r'    elseif action=="trade\.start" then\n.*?(?=    end\n    return jsonResponse\(400,\{ok=false,error="unknown_action"\}\)\nend)',
    re.S,
)
new_trade_start = """    elseif action=="trade.start" then
        local active=select(1,automationState(side))
        if active then
            if not ctx or type(ctx.cancelTrade)~="function" then return jsonResponse(400,{ok=false,error="cancel_unavailable"}) end
            local ok,result=pcall(ctx.cancelTrade); fingerprints[side]=""
            local success=ok and result~=false
            return jsonResponse(success and 200 or 400,{ok=success,cancelled=success,error=success and nil or tostring(result)})
        end
        if not ctx or type(ctx.startTrade)~="function" then return jsonResponse(400,{ok=false,error="start_unavailable"}) end
        local ok,result=pcall(ctx.startTrade,side)
        local success=ok and result~=false
        return jsonResponse(success and 200 or 400,{ok=success,error=success and nil or tostring(result)})
"""

bridge_text, replacements = trade_start_pattern.subn(new_trade_start, bridge_text, count=1)
if replacements != 1:
    raise SystemExit("trade.start bridge block was not replaced")

if "debug.getupvalue" in bridge_text or "findUpvalue" in bridge_text:
    raise SystemExit("debug upvalue access still present in HTML bridge")

required_core = (
    "ctx.getTradeAutomationState = function()",
    "ctx.setCoreMenuVisible = function(value)",
    "ctx.startTrade = function(side)",
    "ctx.cancelTrade = function()",
)
for marker in required_core:
    if marker not in main_text:
        raise SystemExit("missing core API: " + marker)

main_path.write_text(main_text, encoding="utf-8", newline="\n")
bridge_path.write_text(bridge_text, encoding="utf-8", newline="\n")
