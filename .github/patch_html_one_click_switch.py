from pathlib import Path

path = Path("by_Quant_ArzMarket[3_56].lua")
text = path.read_text(encoding="utf-8")

helper_marker = '''function arzUiExtensionsGetByPage(pageId)
\treturn ARZ_UI_EXTENSIONS.by_page[tonumber(pageId) or -1]
end

'''
helper = '''function arzUiExtensionsGetByPage(pageId)
\treturn ARZ_UI_EXTENSIONS.by_page[tonumber(pageId) or -1]
end

function arzUiExtensionsOpenHtml(page)
\tlocal extensions = ARZ_UI_EXTENSIONS
\tlocal extension = extensions and extensions.by_id and extensions.by_id["arz_html_ui"] or nil
\tif not extension or extension._disabled_runtime or type(extension.open_html) ~= "function" then
\t\tif type(sendNotify) == "function" then
\t\t\tpcall(sendNotify, u8:decode("HTML интерфейс недоступен. Используйте Lua режим."))
\t\tend
\t\treturn false
\tend
\tlocal ok, result = xpcall(function()
\t\treturn extension.open_html(page == "sell" and "sell" or "buy")
\tend, arzUiExtensionTraceback)
\tif not ok then
\t\textension._last_error = tostring(result)
\t\tprint("[ArzMarket][UIExtensions] HTML open failed: " .. tostring(result))
\t\tif type(sendNotify) == "function" then
\t\t\tpcall(sendNotify, u8:decode("Не удалось открыть HTML интерфейс. Lua режим продолжает работать."))
\t\tend
\t\treturn false
\tend
\treturn result ~= false
end

'''
if "function arzUiExtensionsOpenHtml(page)" not in text:
    if text.count(helper_marker) != 1:
        raise SystemExit("extension helper marker not found exactly once")
    text = text.replace(helper_marker, helper, 1)


def patch_trade_function(source, function_name, page, toolbar_y):
    start = source.find(f"function {function_name}(frame)")
    if start < 0:
        raise SystemExit(f"{function_name} function not found")
    next_start = source.find("\nfunction ", start + 20)
    if next_start < 0:
        next_start = len(source)
    segment = source[start:next_start]

    old_pos = f'imgui.SetCursorPos(imgui.ImVec2(imgui.GetWindowWidth() - 230, {toolbar_y}))'
    new_pos = f'imgui.SetCursorPos(imgui.ImVec2(imgui.GetWindowWidth() - 285, {toolbar_y}))'
    if segment.count(old_pos) != 1:
        raise SystemExit(f"{function_name} toolbar position marker count={segment.count(old_pos)}")
    segment = segment.replace(old_pos, new_pos, 1)

    close_marker = '''\timgui.SameLine()
\timgui.SetCursorPosX(imgui.GetWindowWidth() - 40)

\tif imgui.CustomOnlyBorderButton(fa("xmark") .. "##0", imgui.ImVec2(35, 27)) then
'''
    switch_block = f'''\timgui.SameLine()
\tif imgui.CustomOnlyBorderButton("HTML##arz_html_{page}", imgui.ImVec2(48, 27)) then
\t\tarzUiExtensionsOpenHtml("{page}")
\tend
\timgui.Hint("arz_html_{page}", "Открыть HTML интерфейс без перезапуска скрипта.", false)
\timgui.SameLine()
\timgui.SetCursorPosX(imgui.GetWindowWidth() - 40)

\tif imgui.CustomOnlyBorderButton(fa("xmark") .. "##0", imgui.ImVec2(35, 27)) then
'''
    if segment.count(close_marker) != 1:
        raise SystemExit(f"{function_name} close marker count={segment.count(close_marker)}")
    segment = segment.replace(close_marker, switch_block, 1)
    return source[:start] + segment + source[next_start:]

text = patch_trade_function(text, "buy", "buy", 5)
text = patch_trade_function(text, "sell", "sell", 4)

for marker in (
    "function arzUiExtensionsOpenHtml(page)",
    'HTML##arz_html_buy',
    'HTML##arz_html_sell',
    'arzUiExtensionsOpenHtml("buy")',
    'arzUiExtensionsOpenHtml("sell")',
):
    if marker not in text:
        raise SystemExit("missing one-click marker: " + marker)

path.write_text(text, encoding="utf-8", newline="\n")
