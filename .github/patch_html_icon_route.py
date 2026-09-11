from pathlib import Path

module = Path('modules/arz_html_ui.lua')
text = module.read_text(encoding='utf-8')

old_version = '    module_version = 7,'
new_version = '    module_version = 8,'
if old_version not in text:
    raise SystemExit('module version anchor not found')
text = text.replace(old_version, new_version, 1)

old_health = '    if req.path=="/health" then return jsonResponse(200,{ok=true,port=port,htmlOpen=htmlOpen,page=currentPage}) end'
new_health = '''    if req.path=="/health" then
        local iconStatus=itemIcons and itemIcons.getStatus and itemIcons.getStatus() or {}
        return jsonResponse(200,{ok=true,port=port,htmlOpen=htmlOpen,page=currentPage,tradeBusy=tradeBusy(),icons=iconStatus})
    end'''
if old_health not in text:
    raise SystemExit('health anchor not found')
text = text.replace(old_health, new_health, 1)

old_route = '''    local size,id=req.path:match("^/api/icon/(24|48|256)/(%d+)%.webp$")
    if size and id then
        if req.method~="GET" then return response(405,"method_not_allowed") end
        if not validToken(req) and tostring(req.query.token or "")~=token then return response(403,"forbidden") end
        if not itemIcons or type(itemIcons.getIcon)~="function" then return response(404,"icon_unavailable") end
        local ok,dataOrErr,extra=pcall(itemIcons.getIcon,size,id)
        if not ok or not dataOrErr then return response(404,tostring(ok and extra or dataOrErr)) end
        return response(200,dataOrErr,"image/webp","public, max-age=86400")
    end'''
new_route = '''    local size,id=req.path:match("^/api/icon/(%d+)/(%d+)%.webp$")
    if size and id then
        if size~="24" and size~="48" and size~="256" then return response(404,"not_found") end
        if req.method~="GET" then return response(405,"method_not_allowed") end
        if not validToken(req) and tostring(req.query.token or "")~=token then return response(403,"forbidden") end
        if not itemIcons or type(itemIcons.getIcon)~="function" then return response(404,"icon_unavailable") end
        local ok,dataOrErr,extra=pcall(itemIcons.getIcon,size,id)
        if not ok or not dataOrErr then return response(404,tostring(ok and extra or dataOrErr)) end
        return response(200,dataOrErr,"image/webp","private, max-age=86400")
    end'''
if old_route not in text:
    raise SystemExit('icon route anchor not found')
text = text.replace(old_route, new_route, 1)
module.write_text(text, encoding='utf-8')

app = Path('ArzMarket/html/js/app.js')
js = app.read_text(encoding='utf-8')
old_key = '''  document.addEventListener('keydown', event => {
    if (event.key === 'Escape' && !refs.pickerBackdrop.classList.contains('hidden')) closePicker();
    if (event.ctrlKey && String(event.key).toLowerCase() === 'f') {'''
new_key = '''  document.addEventListener('keydown', event => {
    if (event.key === 'Escape') {
      if (!refs.pickerBackdrop.classList.contains('hidden')) {
        closePicker();
      } else if (!event.repeat) {
        action('ui.close', {side: state.page}).catch(() => {});
      }
      return;
    }
    if (event.ctrlKey && String(event.key).toLowerCase() === 'f') {'''
if old_key not in js:
    raise SystemExit('keydown anchor not found')
js = js.replace(old_key, new_key, 1)
app.write_text(js, encoding='utf-8')

print('patched icon route, diagnostics and Escape handling')
