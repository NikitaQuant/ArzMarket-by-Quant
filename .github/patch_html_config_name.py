from pathlib import Path

path = Path('by_Quant_ArzMarket[3_56].lua')
text = path.read_text(encoding='utf-8')
old = '''\t\tfileName = tostring(fileName or ""):gsub("^%s+", ""):gsub("%s+$", "")\n\t\tif fileName == "" or fileName:find("[/\\\\]") or fileName:find("..", 1, true) or not fileName:match("^[^%c]+%.json$") then'''
new = '''\t\tfileName = tostring(fileName or ""):gsub("^%s+", ""):gsub("%s+$", "")\n\t\tif fileName ~= "" and not fileName:match("%.json$") then fileName = fileName .. ".json" end\n\t\tif fileName == "" or fileName:find("[/\\\\]") or fileName:find("..", 1, true) or not fileName:match("^[^%c]+%.json$") then'''
if old not in text:
    raise SystemExit('config filename anchor not found')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
print('config name normalization fixed')
