(() => {
  'use strict';

  const token = document.body.dataset.token || '';
  const ITEM_DICT_URL = 'https://arzhub.top/api/public/marketplace/items/all';
  const ITEM_DICT_CACHE = 'arzmarket-item-dict-v1';
  const itemIdsByName = new Map();

  const state = {
    page: 'buy',
    revision: 0,
    data: null,
    selectedKey: null,
    selectedItem: null,
    search: '',
    pickerSearch: '',
    requestBusy: false,
    pollTimer: 0,
    toastTimer: 0
  };

  const el = id => document.getElementById(id);
  const refs = {
    app: el('app'), runtimeText: el('runtimeText'), pageHeaderIcon: el('pageHeaderIcon'),
    pageTitle: el('pageTitle'), pageSubtitle: el('pageSubtitle'), configSelect: el('configSelect'),
    automationBadge: el('automationBadge'), saveBadge: el('saveBadge'), searchInput: el('searchInput'),
    addButton: el('addButton'), averageButton: el('averageButton'), startButton: el('startButton'),
    tableHead: el('tableHead'), tableRows: el('tableRows'), emptyState: el('emptyState'),
    detailEmpty: el('detailEmpty'), detailContent: el('detailContent'), detailIcon: el('detailIcon'),
    detailName: el('detailName'), detailStatus: el('detailStatus'), detailFields: el('detailFields'),
    pickerBackdrop: el('pickerBackdrop'), pickerTitle: el('pickerTitle'), pickerSearch: el('pickerSearch'),
    pickerRows: el('pickerRows'), toast: el('toast')
  };

  const text = value => String(value == null ? '' : value);
  const normalizeName = value => text(value).replace(/\{[0-9a-fA-F]{6}\}/g, '').replace(/\s+/g, ' ').trim().toLocaleLowerCase('ru-RU');
  const money = value => {
    const n = Number(value);
    return Number.isFinite(n) ? Math.trunc(n).toLocaleString('ru-RU').replace(/\u00a0/g, ' ') : '0';
  };

  function indexDictionary(items) {
    if (!items || typeof items !== 'object') return false;
    let added = 0;
    for (const [key, raw] of Object.entries(items)) {
      let id = key;
      let name = raw;
      if (raw && typeof raw === 'object') {
        id = raw.id ?? raw.item_id ?? key;
        name = raw.name ?? raw.title ?? raw.item_name ?? '';
      }
      if (typeof name !== 'string' || name.trim() === '') continue;
      const normalized = normalizeName(name);
      if (!normalized || id == null || String(id) === '') continue;
      itemIdsByName.set(normalized, String(id));
      added++;
    }
    return added > 0;
  }

  function loadCachedDictionary() {
    try {
      const cached = JSON.parse(localStorage.getItem(ITEM_DICT_CACHE) || 'null');
      if (cached && cached.items) indexDictionary(cached.items);
      return cached;
    } catch (_) {
      return null;
    }
  }

  async function loadItemDictionary() {
    const cached = loadCachedDictionary();
    const headers = {};
    if (cached?.etag) headers['If-None-Match'] = cached.etag;
    try {
      const response = await fetch(ITEM_DICT_URL, {cache: 'no-store', headers});
      if (response.status === 304) return;
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const payload = await response.json();
      const items = payload?.items;
      if (!indexDictionary(items)) throw new Error('empty_items');
      try {
        localStorage.setItem(ITEM_DICT_CACHE, JSON.stringify({etag: response.headers.get('ETag') || '', items}));
      } catch (_) {}
      if (state.data) render();
    } catch (err) {
      if (!cached) console.warn('[ArzMarket HTML] item dictionary unavailable:', err);
    }
  }

  const getItemId = item => {
    const direct = item && (item.item_id ?? item.identity?.item_id);
    if (direct != null && String(direct) !== '') return String(direct);
    return item ? itemIdsByName.get(normalizeName(item.name)) || null : null;
  };

  const placeholder = () => 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><rect width="64" height="64" rx="10" fill="#101b24"/><path d="M20 23h24v20H20zM25 18h14" fill="none" stroke="#405461" stroke-width="2"/><path d="m25 37 5-6 5 5 4-4 5 5" fill="none" stroke="#536b78" stroke-width="2"/></svg>');

  function setIcon(img, item, size) {
    const id = getItemId(item);
    if (!id) {
      img.onerror = null;
      img.src = placeholder();
      return;
    }
    img.dataset.stage = '0';
    img.onerror = () => {
      const stage = Number(img.dataset.stage || 0);
      if (stage === 0) {
        img.dataset.stage = '1';
        img.src = `/api/icon/${size}/${encodeURIComponent(id)}.webp`;
      } else {
        img.dataset.stage = '2';
        img.onerror = null;
        img.src = placeholder();
      }
    };
    img.src = `file:///arizona/items.zip/${encodeURIComponent(id)}.webp`;
  }

  function showToast(message, type = '') {
    clearTimeout(state.toastTimer);
    refs.toast.textContent = text(message);
    refs.toast.className = `toast ${type}`.trim();
    state.toastTimer = setTimeout(() => refs.toast.classList.add('hidden'), 2600);
  }

  async function api(path, options = {}) {
    const headers = Object.assign({}, options.headers || {}, {'X-ArzMarket-Token': token});
    if (options.body && !headers['Content-Type']) headers['Content-Type'] = 'application/json';
    const response = await fetch(path, Object.assign({}, options, {headers, cache: 'no-store'}));
    if (response.status === 204) return {unchanged: true};
    const raw = await response.text();
    let data;
    try { data = raw ? JSON.parse(raw) : {}; }
    catch (_) { data = {ok: false, error: raw || `HTTP ${response.status}`}; }
    if (!response.ok) {
      const err = new Error(data?.error || `HTTP ${response.status}`);
      err.status = response.status;
      throw err;
    }
    return data;
  }

  const action = (name, payload = {}) => api('/api/action', {
    method: 'POST',
    body: JSON.stringify({action: name, payload, revision: state.revision})
  });

  const keyOf = item => item?.identity ? [item.identity.index, item.identity.name, item.identity.slot_id ?? '', item.identity.item_id ?? ''].join('|') : '';

  function syncSelected() {
    const items = state.data?.data?.items || [];
    let item = items.find(x => keyOf(x) === state.selectedKey);
    if (!item && state.selectedItem) item = items.find(x => x.name === state.selectedItem.name);
    state.selectedItem = item || null;
    state.selectedKey = item ? keyOf(item) : null;
  }

  async function refresh(force = false) {
    if (state.requestBusy) return;
    state.requestBusy = true;
    try {
      const result = await api(`/api/state?page=${encodeURIComponent(state.page)}&since=${force ? 0 : state.revision}`);
      if (!result.unchanged) {
        state.data = result;
        state.revision = Number(result.revision || 0);
        syncSelected();
        render();
      }
      refs.runtimeText.textContent = 'Система готова';
    } catch (err) {
      refs.runtimeText.textContent = 'Нет связи с Lua';
      if (force) showToast(`Bridge: ${err.message}`, 'error');
    } finally {
      state.requestBusy = false;
    }
  }

  function div(value, className = '') {
    const node = document.createElement('div');
    if (className) node.className = className;
    node.textContent = text(value);
    return node;
  }

  function renderHeader() {
    const buy = state.page === 'buy';
    refs.app.dataset.page = state.page;
    refs.pageTitle.textContent = buy ? 'Скупка' : 'Продажа';
    refs.pageSubtitle.textContent = buy ? 'Автоматический выкуп товаров с Arizona RP' : 'Управление товарами для продажи на Arizona RP';
    refs.pageHeaderIcon.textContent = buy ? '⌑' : '↥';
    document.querySelectorAll('.nav-item[data-page]').forEach(n => n.classList.toggle('active', n.dataset.page === state.page));
    refs.configSelect.innerHTML = '';
    const option = document.createElement('option');
    option.textContent = state.data?.common?.activeConfig || 'Не выбран';
    refs.configSelect.append(option);

    const active = state.data?.common?.automation === true;
    const score = Number(state.data?.common?.automationScore || 0);
    const total = Number(state.data?.common?.automationTotal || 0);
    refs.automationBadge.textContent = active && total > 0 ? `Активен ${Math.min(score, total)}/${total}` : (active ? 'Активен' : 'Готов');
    refs.automationBadge.className = active ? 'badge badge-success' : 'badge badge-muted';
    refs.startButton.textContent = active ? 'Отмена' : (buy ? 'Старт скупки' : 'Начать продажу');
    refs.averageButton.classList.toggle('hidden', !buy);
  }

  function renderTable() {
    const buy = state.page === 'buy';
    refs.tableHead.className = `table-head ${state.page}`;
    refs.tableHead.innerHTML = '';
    (buy ? ['Товар', 'Цена', 'Кол-во', 'Остаток', 'Статус', ''] : ['Товар', 'Цена', 'Кол-во', 'Доступно', 'Статус', ''])
      .forEach(x => refs.tableHead.append(div(x)));

    const all = state.data?.data?.items || [];
    const q = normalizeName(state.search);
    const items = q ? all.filter(x => normalizeName(x.name).includes(q)) : all;
    refs.tableRows.innerHTML = '';
    refs.emptyState.classList.toggle('hidden', items.length !== 0);
    const fragment = document.createDocumentFragment();

    for (const item of items) {
      const row = document.createElement('div');
      row.className = `trade-row ${state.page}`;
      if (item.enabled === false) row.classList.add('disabled-row');
      if (keyOf(item) === state.selectedKey) row.classList.add('selected');
      row.addEventListener('click', () => {
        state.selectedItem = item;
        state.selectedKey = keyOf(item);
        renderTable();
        renderDetails();
      });

      const itemCell = div('', 'item-cell');
      const box = div('', 'item-thumb-box');
      const img = document.createElement('img');
      img.className = 'item-thumb';
      img.alt = '';
      img.loading = 'lazy';
      setIcon(img, item, 48);
      box.append(img);
      const wrap = div('', 'item-name-wrap');
      const itemId = getItemId(item);
      wrap.append(div(item.name, 'item-name'), div(itemId ? `ID ${itemId}` : (buy ? 'Скупка' : 'Инвентарь'), 'item-meta'));
      itemCell.append(box, wrap);
      row.append(itemCell);
      row.append(div(`${money(item.price)} SA$`, 'money'));
      row.append(div(item.maximum && !buy ? 'Макс.' : money(item.count), 'count'));
      row.append(div(buy ? money(item.continue) : money(item.all_count), 'count'));

      const status = div('', 'row-status');
      const toggle = document.createElement('button');
      toggle.type = 'button';
      toggle.className = `toggle ${item.enabled !== false ? 'on' : ''}`;
      toggle.addEventListener('click', async event => {
        event.stopPropagation();
        await patchItem(item, {enabled: item.enabled === false});
      });
      status.append(toggle);
      row.append(status);

      const trash = document.createElement('button');
      trash.type = 'button';
      trash.className = 'trash';
      trash.textContent = '×';
      trash.title = 'Удалить товар';
      trash.addEventListener('click', async event => {
        event.stopPropagation();
        await removeItem(item);
      });
      row.append(trash);
      fragment.append(row);
    }

    refs.tableRows.append(fragment);
  }

  function numberField(label, value, key, disabled = false) {
    const wrap = document.createElement('label');
    wrap.className = 'field';
    wrap.append(div(label, 'field-label'));
    const input = document.createElement('input');
    input.className = 'field-input';
    input.type = 'number';
    input.min = '0';
    input.step = '1';
    input.value = String(value ?? 0);
    input.disabled = disabled;
    if (!disabled) {
      let timer = 0;
      const commit = async () => {
        clearTimeout(timer);
        const n = Number(input.value);
        if (Number.isFinite(n) && n >= 0) await patchItem(state.selectedItem, {[key]: n});
      };
      input.addEventListener('input', () => {
        clearTimeout(timer);
        timer = setTimeout(commit, 380);
      });
      input.addEventListener('change', commit);
      input.addEventListener('blur', commit);
      input.addEventListener('keydown', event => {
        if (event.key === 'Enter') input.blur();
      });
    }
    wrap.append(input);
    return wrap;
  }

  function toggleField(label, enabled, key) {
    const wrap = div('', 'field-toggle-row');
    wrap.append(div(label));
    const button = document.createElement('button');
    button.type = 'button';
    button.className = `toggle ${enabled ? 'on' : ''}`;
    button.addEventListener('click', () => patchItem(state.selectedItem, {[key]: !enabled}));
    wrap.append(button);
    return wrap;
  }

  function renderDetails() {
    const item = state.selectedItem;
    refs.detailEmpty.classList.toggle('hidden', !!item);
    refs.detailContent.classList.toggle('hidden', !item);
    if (!item) return;

    refs.detailName.textContent = item.name || 'Предмет';
    refs.detailStatus.textContent = item.enabled !== false ? 'Активен' : 'Отключен';
    refs.detailStatus.className = item.enabled !== false ? 'badge badge-success' : 'badge badge-muted';
    setIcon(refs.detailIcon, item, 256);
    refs.detailFields.innerHTML = '';

    const price = div('', 'field-row');
    price.append(numberField('Цена SA$', item.price, 'price'), numberField('Цена VC$', item.price_vc, 'price_vc'));
    refs.detailFields.append(price);

    const count = div('', 'field-row');
    count.append(
      numberField('Количество', item.count, 'count'),
      state.page === 'buy' ? numberField('Осталось', item.continue, 'continue') : numberField('Доступно', item.all_count, 'all_count', true)
    );
    refs.detailFields.append(count);
    if (state.page === 'sell') refs.detailFields.append(toggleField('Выставлять максимум', item.maximum === true, 'maximum'));
    refs.detailFields.append(toggleField('Статус товара', item.enabled !== false, 'enabled'));
  }

  function render() {
    renderHeader();
    renderTable();
    renderDetails();
  }

  async function patchItem(item, patch) {
    if (!item) return;
    try {
      refs.saveBadge.lastChild.textContent = 'Сохранение...';
      await action('trade.item.update', {side: state.page, identity: item.identity, patch});
      refs.saveBadge.lastChild.textContent = 'Сохранено';
      await refresh(true);
      setTimeout(() => { refs.saveBadge.lastChild.textContent = 'Автосохранение'; }, 900);
    } catch (err) {
      refs.saveBadge.lastChild.textContent = 'Не сохранено';
      showToast(err.status === 409 ? 'Список изменился. Обновляю данные.' : `Не удалось сохранить: ${err.message}`, 'error');
      await refresh(true);
    }
  }

  async function removeItem(item) {
    try {
      await action('trade.item.remove', {side: state.page, identity: item.identity});
      state.selectedItem = null;
      state.selectedKey = null;
      showToast('Товар удален', 'success');
      await refresh(true);
    } catch (err) {
      showToast(`Не удалось удалить: ${err.message}`, 'error');
      await refresh(true);
    }
  }

  function openPicker() {
    refs.pickerTitle.textContent = state.page === 'buy' ? 'Добавить в скупку' : 'Добавить в продажу';
    state.pickerSearch = '';
    refs.pickerSearch.value = '';
    refs.pickerBackdrop.classList.remove('hidden');
    renderPicker();
    setTimeout(() => refs.pickerSearch.focus(), 30);
  }

  function closePicker() {
    refs.pickerBackdrop.classList.add('hidden');
  }

  function renderPicker() {
    const source = state.data?.data?.source || [];
    const existing = new Set((state.data?.data?.items || []).map(x => normalizeName(x.name)));
    const q = normalizeName(state.pickerSearch);
    const filtered = source
      .filter(x => !existing.has(normalizeName(x.name)) && (!q || normalizeName(x.name).includes(q)))
      .slice(0, 400);

    refs.pickerRows.innerHTML = '';
    const fragment = document.createDocumentFragment();
    for (const item of filtered) {
      const row = div('', 'picker-row');
      row.append(div(item.name), div(state.page === 'sell' && item.all_count ? `${money(item.all_count)} шт.` : '+', 'picker-count'));
      row.addEventListener('click', async () => {
        try {
          await action('trade.item.add', {side: state.page, source_index: item.index});
          showToast('Товар добавлен', 'success');
          await refresh(true);
          renderPicker();
        } catch (err) {
          showToast(`Не удалось добавить: ${err.message}`, 'error');
        }
      });
      fragment.append(row);
    }
    refs.pickerRows.append(fragment);
  }

  async function switchPage(page) {
    if (page !== 'buy' && page !== 'sell') return;
    state.page = page;
    state.revision = 0;
    state.selectedItem = null;
    state.selectedKey = null;
    state.search = '';
    refs.searchInput.value = '';
    await action('ui.navigate', {side: page}).catch(() => {});
    await refresh(true);
  }

  document.addEventListener('click', async event => {
    const pageButton = event.target.closest('.nav-item[data-page]');
    if (pageButton) return switchPage(pageButton.dataset.page);
    const button = event.target.closest('[data-action]');
    if (!button) return;
    const name = button.dataset.action;
    if (name === 'close' || name === 'mode-lua') {
      try {
        await action(name === 'close' ? 'ui.close' : 'ui.switch_mode', {side: state.page});
      } catch (_) {}
      return;
    }
    if (name === 'picker-close') closePicker();
  });

  refs.searchInput.addEventListener('input', () => {
    state.search = refs.searchInput.value;
    renderTable();
  });
  refs.addButton.addEventListener('click', openPicker);
  refs.pickerSearch.addEventListener('input', () => {
    state.pickerSearch = refs.pickerSearch.value;
    renderPicker();
  });
  refs.pickerBackdrop.addEventListener('click', event => {
    if (event.target === refs.pickerBackdrop) closePicker();
  });
  refs.averageButton.addEventListener('click', async () => {
    try {
      await action('buy.average.apply');
      showToast('Средние цены применены', 'success');
      await refresh(true);
    } catch (err) {
      showToast(`Средние цены: ${err.message}`, 'error');
    }
  });
  refs.startButton.addEventListener('click', async () => {
    try {
      await action('trade.start', {side: state.page});
      await refresh(true);
    } catch (err) {
      showToast(`Запуск: ${err.message}`, 'error');
    }
  });

  document.addEventListener('keydown', event => {
    if (event.key === 'Escape' && !refs.pickerBackdrop.classList.contains('hidden')) closePicker();
    if (event.ctrlKey && String(event.key).toLowerCase() === 'f') {
      event.preventDefault();
      refs.searchInput.focus();
      refs.searchInput.select();
    }
  });

  window.addEventListener('error', event => {
    refs.runtimeText.textContent = 'Ошибка интерфейса';
    console.error('[ArzMarket HTML]', event.error || event.message);
  });
  window.addEventListener('unhandledrejection', event => console.error('[ArzMarket HTML]', event.reason));

  loadItemDictionary();
  refresh(true);
  state.pollTimer = window.setInterval(() => refresh(false), 450);
})();
