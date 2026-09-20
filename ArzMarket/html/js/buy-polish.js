(() => {
  'use strict';

  const app = document.getElementById('app');
  const tableRows = document.getElementById('tableRows');
  const tableCard = document.querySelector('.table-card');
  const detailContent = document.getElementById('detailContent');
  const detailFields = document.getElementById('detailFields');
  const detailName = document.getElementById('detailName');
  const detailTabs = detailContent ? detailContent.querySelector('.detail-tabs') : null;
  const startButton = document.getElementById('startButton');

  if (!app || !tableRows || !tableCard || !detailContent || !detailFields || !detailName || !detailTabs) return;

  let detailTab = 'main';
  let syncQueued = false;

  const text = value => String(value == null ? '' : value);
  const normalizeLabel = value => text(value).replace(/\s+/g, ' ').trim().toLocaleLowerCase('ru-RU');

  function isBuy() {
    return app.dataset.page === 'buy';
  }

  function removeLegacyTableFooter() {
    const footer = document.getElementById('buyTableFooter');
    if (footer) footer.remove();
  }

  function updateRowStatusLabels() {
    if (!isBuy()) return;
    const rows = tableRows.querySelectorAll('.trade-row.buy');
    for (const row of rows) {
      const status = row.querySelector('.row-status');
      if (!status) continue;
      let label = status.querySelector('.row-status-label');
      if (!label) {
        label = document.createElement('span');
        label.className = 'row-status-label';
        status.appendChild(label);
      }
      const value = row.classList.contains('disabled-row') ? 'Выключен' : 'Включен';
      if (label.textContent !== value) label.textContent = value;
    }
  }

  function ensureDetailKind() {
    const wrap = detailName.parentElement;
    if (!wrap) return;
    let kind = wrap.querySelector('.detail-kind');
    if (!kind) {
      kind = document.createElement('div');
      kind.className = 'detail-kind';
      kind.textContent = 'Предмет';
      detailName.insertAdjacentElement('afterend', kind);
    }
    kind.classList.toggle('hidden', !isBuy());
  }

  function ensureDetailTabs() {
    let main = detailTabs.querySelector('[data-buy-tab="main"]');
    let extra = detailTabs.querySelector('[data-buy-tab="extra"]');

    if (!main) {
      main = detailTabs.querySelector('.detail-tab') || document.createElement('button');
      main.type = 'button';
      main.className = 'detail-tab';
      main.dataset.buyTab = 'main';
      main.textContent = 'Основные';
      if (!main.parentElement) detailTabs.appendChild(main);
    }

    if (!extra) {
      extra = document.createElement('button');
      extra.type = 'button';
      extra.className = 'detail-tab';
      extra.dataset.buyTab = 'extra';
      extra.textContent = 'Дополнительно';
      detailTabs.appendChild(extra);
    }

    extra.classList.toggle('hidden', !isBuy());

    for (const button of detailTabs.querySelectorAll('[data-buy-tab]')) {
      button.classList.toggle('active', button.dataset.buyTab === detailTab);
    }
  }

  function createReadonlyNameField() {
    const wrap = document.createElement('label');
    wrap.className = 'field';
    wrap.dataset.buySynthetic = 'name';

    const label = document.createElement('span');
    label.className = 'field-label';
    label.textContent = 'Название';

    const input = document.createElement('input');
    input.className = 'field-input buy-readonly-name';
    input.type = 'text';
    input.readOnly = true;
    input.tabIndex = -1;
    input.value = detailName.textContent || '';

    wrap.append(label, input);
    return wrap;
  }

  function classifyFields() {
    if (!isBuy()) return;
    if (detailFields.querySelector('.buy-main-fields')) {
      const nameInput = detailFields.querySelector('.buy-readonly-name');
      if (nameInput && nameInput.value !== detailName.textContent) nameInput.value = detailName.textContent || '';
      applyDetailTab();
      return;
    }

    const originalChildren = Array.from(detailFields.children);
    if (!originalChildren.length) return;

    const fields = [];
    const toggles = [];

    for (const child of originalChildren) {
      if (child.classList.contains('field-row')) {
        fields.push(...Array.from(child.children).filter(node => node.classList.contains('field')));
      } else if (child.classList.contains('field')) {
        fields.push(child);
      } else if (child.classList.contains('field-toggle-row')) {
        toggles.push(child);
      }
    }

    const byLabel = new Map();
    for (const field of fields) {
      const label = normalizeLabel(field.querySelector('.field-label')?.textContent || '');
      if (label) byLabel.set(label, field);
    }

    const main = document.createElement('div');
    main.className = 'buy-main-fields';
    main.appendChild(createReadonlyNameField());

    const orderedLabels = ['цена', 'цена sa$', 'кол-во', 'количество', 'цена vc$', 'тип предмета'];
    const appended = new Set();
    for (const label of orderedLabels) {
      const field = byLabel.get(label);
      if (field && !appended.has(field)) {
        appended.add(field);
        main.appendChild(field);
      }
    }

    const statusToggle = toggles.find(node => {
      const firstLabel = normalizeLabel(node.firstElementChild?.textContent || '');
      const fullLabel = normalizeLabel(node.textContent || '');
      return firstLabel === 'статус' || firstLabel.includes('статус товара') || fullLabel.startsWith('статус');
    });
    if (statusToggle) main.appendChild(statusToggle);

    const extra = document.createElement('div');
    extra.className = 'buy-extra-fields';

    for (const toggle of toggles) {
      if (toggle !== statusToggle) extra.appendChild(toggle);
    }

    for (const field of fields) {
      if (!main.contains(field)) extra.appendChild(field);
    }

    detailFields.replaceChildren(main, extra);
    applyDetailTab();
  }

  function applyDetailTab() {
    const main = detailFields.querySelector('.buy-main-fields');
    const extra = detailFields.querySelector('.buy-extra-fields');
    if (!main || !extra) return;

    main.classList.toggle('hidden', detailTab !== 'main');
    extra.classList.toggle('hidden', detailTab !== 'extra');

    for (const button of detailTabs.querySelectorAll('[data-buy-tab]')) {
      button.classList.toggle('active', button.dataset.buyTab === detailTab);
    }
  }

  function updateStartButton() {
    if (!isBuy() || !startButton) return;
    if (startButton.textContent.trim() === 'Старт скупки') startButton.textContent = 'Старт';
  }

  function deactivateBuyPolish() {
    removeLegacyTableFooter();

    const kind = detailName.parentElement?.querySelector('.detail-kind');
    if (kind) kind.classList.add('hidden');

    const extra = detailTabs.querySelector('[data-buy-tab="extra"]');
    if (extra) extra.classList.add('hidden');

    const main = detailTabs.querySelector('[data-buy-tab="main"]');
    if (main) main.classList.add('active');
  }

  function sync() {
    syncQueued = false;
    removeLegacyTableFooter();

    if (!isBuy()) {
      deactivateBuyPolish();
      return;
    }

    updateRowStatusLabels();
    ensureDetailKind();
    ensureDetailTabs();
    updateStartButton();

    if (!detailContent.classList.contains('hidden')) classifyFields();
  }

  function scheduleSync() {
    if (syncQueued) return;
    syncQueued = true;
    setTimeout(sync, 0);
  }

  detailTabs.addEventListener('click', event => {
    const button = event.target.closest('[data-buy-tab]');
    if (!button || !isBuy()) return;
    detailTab = button.dataset.buyTab === 'extra' ? 'extra' : 'main';
    applyDetailTab();
  });

  const tableObserver = new MutationObserver(scheduleSync);
  tableObserver.observe(tableRows, {subtree: true, childList: true, attributes: true, attributeFilter: ['class']});

  const detailFieldsObserver = new MutationObserver(scheduleSync);
  detailFieldsObserver.observe(detailFields, {subtree: true, childList: true});

  const detailContentObserver = new MutationObserver(scheduleSync);
  detailContentObserver.observe(detailContent, {attributes: true, attributeFilter: ['class']});

  const detailHeaderObserver = new MutationObserver(scheduleSync);
  detailHeaderObserver.observe(detailName, {childList: true, characterData: true, subtree: true});

  if (startButton) {
    const startObserver = new MutationObserver(scheduleSync);
    startObserver.observe(startButton, {childList: true, characterData: true, subtree: true});
  }

  const pageObserver = new MutationObserver(scheduleSync);
  pageObserver.observe(app, {attributes: true, attributeFilter: ['data-page']});

  scheduleSync();
})();
