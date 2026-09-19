(() => {
  'use strict';

  const token = document.body.dataset.token || '';
  const urlParams = new URLSearchParams(window.location.search);
  const previewMode = urlParams.get('preview') === '1';
  const temporaryMode = urlParams.get('temporary') === '1';
  const requestedInitialPage = urlParams.get('page');
  const initialPage = ['sell','settings','logs','marketplace','mods','storage'].includes(requestedInitialPage) ? requestedInitialPage : 'buy';
  const requestedSettingsSection = urlParams.get('section');
  const initialSettingsSection = ['general','trade','automation','telegram','appearance','configs'].includes(requestedSettingsSection) ? requestedSettingsSection : 'general';
  if (previewMode) document.documentElement.classList.add('preview-mode');
  const state = {
    page: initialPage,
    revision: 0,
    data: null,
    selectedKey: null,
    selectedItem: null,
    search: '',
    pickerSearch: '',
    requestBusy: false,
    pageCache: Object.create(null),
    pageRevision: {buy:0, sell:0, settings:0, logs:0, marketplace:0, mods:0, storage:0},
    pageRequests: Object.create(null),
    toastTimer: 0,
    clearArmedUntil: 0,
    budgetPreviewTimer: 0,
    readyNotified: false,
    sortKey: null,
    sortDirection: 0,
    searchFocused: false,
    sellInventorySearch: '',
    sellStatusFilter: 'all',
    sellMarketStats: new Map(),
    sellMarketPending: new Set(),
    averagePrices: {cache:new Map(),pending:new Map(),tooltip:null,hoverTimer:0,hideTimer:0,activeKey:null,storageKey:null},
    logs: {
      search: '', category: 'all', status: 'all', period: 'today', date: 'all',
      page: 1, perPage: 10, selectedId: null
    },
    storage: {search:'', type:'all', place:'all', selectedKey:null, tab:'distribution'},
    settings: {section:initialSettingsSection, mergeSelected:new Set(), pendingScale:null, paletteDragging:false},
    modsSection: 'scripts',
    marketplace: {search:'', selectedShopKey:null},
    interfaceScalePercent: 100,
    minimalMode: false,
    minimalModeHydrated: false
  };

  // Non-native presets keep the ArzMarket layer hierarchy: neutral dark base,
  // clearly separated panels/surfaces, and theme identity mainly in accents.
  const HTML_THEME_PRESETS = {
    arzmarket_default:{bg:'#0b1721',panel:'#10202c',surface:'#0d1c27',accent:'#42dca0',accent2:'#67efb4',text:'#e7f0f6',muted:'#8195a7',border:'#324b5d'},
    classic_blue:{bg:'#0b1621',panel:'#122131',surface:'#0e1c28',accent:'#4b8dff',accent2:'#7cb7ff',text:'#f3f7ff',muted:'#9fb4d0',border:'#3e5c77'},
    midnight_blue:{bg:'#0b1620',panel:'#121e2c',surface:'#0e1a27',accent:'#7a78ff',accent2:'#a795ff',text:'#f2f2ff',muted:'#a7aac7',border:'#455777'},
    deep_ocean:{bg:'#0a1720',panel:'#0f222d',surface:'#0c1c27',accent:'#22b8f0',accent2:'#4dd8c4',text:'#eefbff',muted:'#90b9c1',border:'#36626d'},
    cyberpunk_neon:{bg:'#0b1620',panel:'#131f2d',surface:'#0e1a27',accent:'#2bd9fe',accent2:'#b65cff',text:'#f5f7ff',muted:'#9eade0',border:'#474e77'},
    sunset_vibes:{bg:'#0d1620',panel:'#181d29',surface:'#121a25',accent:'#ff7a59',accent2:'#f7b955',text:'#fff7f2',muted:'#d9b7b0',border:'#525d5c'},
    dark_forest:{bg:'#0a161e',panel:'#0f2025',surface:'#0d1c22',accent:'#45c987',accent2:'#9ed66f',text:'#eff8f2',muted:'#a5c5ae',border:'#436160'},
    high_contrast:{bg:'#050608',panel:'#14171d',surface:'#0e1217',accent:'#ffd84d',accent2:'#6cd6ff',text:'#ffffff',muted:'#c4d7e3',border:'#747b84'},
    premium_luxury:{bg:'#0b161f',panel:'#141d25',surface:'#0f1a23',accent:'#d2a85e',accent2:'#f0d394',text:'#faf7f0',muted:'#bdb6aa',border:'#506166'}
  };

  function themeHexRgb(hex) {
    const clean = String(hex || '').replace('#','').trim();
    if (!/^[0-9a-fA-F]{6}$/.test(clean)) return {r:0,g:0,b:0};
    return {r:parseInt(clean.slice(0,2),16),g:parseInt(clean.slice(2,4),16),b:parseInt(clean.slice(4,6),16)};
  }

  function themeRgbHex(rgb) {
    const channel = value => Math.max(0,Math.min(255,Math.round(Number(value) || 0))).toString(16).padStart(2,'0');
    return `#${channel(rgb.r)}${channel(rgb.g)}${channel(rgb.b)}`;
  }

  function themeMix(first, second, amount) {
    const a=themeHexRgb(first), b=themeHexRgb(second), t=Math.max(0,Math.min(1,Number(amount)||0));
    return themeRgbHex({r:a.r+(b.r-a.r)*t,g:a.g+(b.g-a.g)*t,b:a.b+(b.b-a.b)*t});
  }

  function themeRgba(hex, alpha) {
    const rgb=themeHexRgb(hex);
    return `rgba(${rgb.r},${rgb.g},${rgb.b},${Math.max(0,Math.min(1,Number(alpha)||0)).toFixed(3)})`;
  }

  function themeClamp01(value) {
    return Math.max(0, Math.min(1, Number(value) || 0));
  }

  function themeNormalizeHex(value, fallback = '#4B8DFF') {
    const raw = String(value || '').trim().toUpperCase();
    return /^#[0-9A-F]{6}$/.test(raw) ? raw : fallback;
  }

  function themeRgbToHsv(rgb) {
    const r=themeClamp01((Number(rgb?.r)||0)/255), g=themeClamp01((Number(rgb?.g)||0)/255), b=themeClamp01((Number(rgb?.b)||0)/255);
    const max=Math.max(r,g,b), min=Math.min(r,g,b), delta=max-min;
    let h=0;
    if (delta > 0.00001) {
      if (max === r) h=((g-b)/delta)%6;
      else if (max === g) h=((b-r)/delta)+2;
      else h=((r-g)/delta)+4;
      h/=6;
      if (h < 0) h+=1;
    }
    return {h:themeClamp01(h),s:max>0?themeClamp01(delta/max):0,v:themeClamp01(max)};
  }

  function themeHsvToRgb(h, s, v) {
    h=themeClamp01(h); s=themeClamp01(s); v=themeClamp01(v);
    if (s <= 0.00001) {
      const mono=Math.round(v*255);
      return {r:mono,g:mono,b:mono};
    }
    const hh=(h%1)*6, i=Math.floor(hh), f=hh-i;
    const p=v*(1-s), q=v*(1-s*f), t=v*(1-s*(1-f));
    let r=v,g=t,b=p;
    if (i===1) {r=q;g=v;b=p;}
    else if (i===2) {r=p;g=v;b=t;}
    else if (i===3) {r=p;g=q;b=v;}
    else if (i===4) {r=t;g=p;b=v;}
    else if (i>=5) {r=v;g=p;b=q;}
    return {r:Math.round(r*255),g:Math.round(g*255),b:Math.round(b*255)};
  }

  function buildGlobalPaletteTokens(profile) {
    const safe=Object.assign({base:'#4B8DFF',depth:72,saturation:82,contrast:72,glow:80},profile||{});
    const baseHex=themeNormalizeHex(safe.base);
    const base=themeHexRgb(baseHex);
    const hsv=themeRgbToHsv(base);
    const saturationFactor=Math.max(0,Math.min(100,Number(safe.saturation)||0))/100;
    const contrastFactor=Math.max(0,Math.min(100,Number(safe.contrast)||0))/100;
    const depthFactor=Math.max(0,Math.min(100,Number(safe.depth)||0))/100;
    const grayscaleSource=hsv.s<=0.02;
    const sourceValue=grayscaleSource ? themeClamp01(.20+hsv.v*.74) : themeClamp01(Math.max(hsv.v,.72+contrastFactor*.24));
    const targetSaturation=grayscaleSource ? 0 : themeClamp01(hsv.s*(.45+saturationFactor*.95)+saturationFactor*.12);
    const accent=themeRgbHex(themeHsvToRgb(hsv.h,targetSaturation,sourceValue));
    const secondaryHue=(hsv.h+.055+contrastFactor*.018)%1;
    const accent2=grayscaleSource
      ? themeRgbHex(themeHsvToRgb(hsv.h,0,themeClamp01(Math.min(1,sourceValue+.14))))
      : themeRgbHex(themeHsvToRgb(secondaryHue,themeClamp01(targetSaturation*.76),Math.min(1,sourceValue+.09)));

    // Сохраняем разделение фона и панелей как в стандартной теме ArzMarket.
    // Выбранный цвет лишь слегка тонирует тёмные поверхности и остаётся ярким на активных элементах.
    const neutral=HTML_THEME_PRESETS.arzmarket_default;
    const tintStrength=grayscaleSource ? .012 : (.022+saturationFactor*.038);
    let bg=themeMix(neutral.bg,accent,tintStrength*.50);
    let panel=themeMix(neutral.panel,accent,tintStrength*.70);
    let surface=themeMix(neutral.surface,accent,tintStrength*.60);

    const depthDelta=depthFactor-.72;
    const applyDepth=color=>{
      if (depthDelta>0) return themeMix(color,'#000000',Math.min(.18,depthDelta*.34));
      if (depthDelta<0) return themeMix(color,'#FFFFFF',Math.min(.12,(-depthDelta)*.16));
      return color;
    };
    bg=applyDepth(bg);
    panel=applyDepth(panel);
    surface=applyDepth(surface);

    const contrastDelta=contrastFactor-.72;
    if (contrastDelta>0) {
      bg=themeMix(bg,'#000000',Math.min(.08,contrastDelta*.10));
      panel=themeMix(panel,'#FFFFFF',Math.min(.045,contrastDelta*.055));
      surface=themeMix(surface,'#FFFFFF',Math.min(.03,contrastDelta*.035));
    } else if (contrastDelta<0) {
      const low=-contrastDelta;
      panel=themeMix(panel,bg,Math.min(.20,low*.18));
      surface=themeMix(surface,bg,Math.min(.15,low*.14));
    }

    const text=themeMix('#FFFFFF',accent2,grayscaleSource?0.045:(.025+saturationFactor*.020));
    const muted=themeMix(text,panel,.44+depthFactor*.12);
    const border=themeMix(neutral.border,accent2,grayscaleSource?(.06+contrastFactor*.10):(.08+contrastFactor*.16));
    return {bg,panel,surface,accent,accent2,text,muted,border};
  }

  function applyThemeVariables(app, theme, glowPercent = 80) {
    const safe = Object.assign({}, HTML_THEME_PRESETS.arzmarket_default, theme || {});
    for (const [name,value] of Object.entries(safe)) {
      app.style.setProperty(`--html-theme-${name}`, value);
      document.body?.style.setProperty(`--html-theme-${name}`, value);
    }
    const glow=Math.max(0,Math.min(100,Number(glowPercent)||0))/100;
    const vars={
      '--am-bg':safe.bg,
      '--am-bg-deep':themeMix(safe.bg,'#000000',.20),
      '--am-panel':safe.panel,
      '--am-panel-soft':themeMix(safe.panel,safe.bg,.34),
      '--am-surface':safe.surface,
      '--am-surface-2':themeMix(safe.surface,safe.panel,.34),
      '--am-surface-hover':themeMix(safe.surface,safe.accent,.10),
      '--am-surface-active':themeMix(safe.surface,safe.accent,.20),
      '--am-text':safe.text,
      '--am-text-soft':themeMix(safe.text,safe.muted,.30),
      '--am-muted':safe.muted,
      '--am-border':safe.border,
      '--am-border-soft':themeRgba(safe.border,.48),
      '--am-border-faint':themeRgba(safe.border,.24),
      '--am-border-strong':themeMix(safe.border,safe.accent2,.18),
      '--am-accent':safe.accent,
      '--am-accent-dark':themeMix(safe.accent,'#000000',.22),
      '--am-accent-2':safe.accent2,
      '--am-accent-soft':themeRgba(safe.accent,.105),
      '--am-accent-medium':themeRgba(safe.accent,.235),
      '--am-accent-strong':themeRgba(safe.accent,.56),
      '--am-accent-glow':themeRgba(safe.accent,glow*.58),
      '--am-accent-alpha-35':themeRgba(safe.accent,glow*.35),
      '--am-accent2-soft':themeRgba(safe.accent2,.12),
      '--am-accent2-medium':themeRgba(safe.accent2,.30),
      '--am-shadow':`rgba(0,0,0,${(.24+glow*.16).toFixed(3)})`,
      '--am-white-faint':'rgba(255,255,255,.028)',
      '--am-white-soft':'rgba(255,255,255,.055)',
      '--am-success':'#4de5a2',
      '--am-success-soft':'rgba(77,229,162,.13)',
      '--am-danger':'#ef6072',
      '--am-danger-soft':'rgba(239,96,114,.13)',
      '--am-warning':'#f0bd65',
      '--am-warning-soft':'rgba(240,189,101,.13)'
    };
    for (const [name,value] of Object.entries(vars)) {
      app.style.setProperty(name,value);
      document.body?.style.setProperty(name,value);
    }
  }

  function readStoredGlobalTheme() {
    try {
      const parsed=JSON.parse(localStorage.getItem('arzmarket-html-global-palette') || 'null');
      return parsed && typeof parsed === 'object' ? parsed : null;
    } catch (_) { return null; }
  }

  function applyHtmlTheme(themeKey, globalProfile = null) {
    const app = document.getElementById('app');
    if (!app) return;
    const profile = globalProfile && typeof globalProfile === 'object' ? globalProfile : (themeKey === 'global_palette' ? readStoredGlobalTheme() : null);
    const globalEnabled = themeKey === 'global_palette' && profile?.enabled === true;
    const key = globalEnabled ? 'global_palette' : (HTML_THEME_PRESETS[themeKey] ? themeKey : 'arzmarket_default');
    const hasPaletteSource=globalEnabled && /^#[0-9A-Fa-f]{6}$/.test(String(profile?.base||''));
    const savedTokens=profile?.tokens && typeof profile.tokens === 'object' ? profile.tokens : null;
    const rebuiltTokens=globalEnabled ? (hasPaletteSource ? buildGlobalPaletteTokens(profile) : (savedTokens || buildGlobalPaletteTokens(profile))) : null;
    const theme = globalEnabled ? Object.assign({}, HTML_THEME_PRESETS.arzmarket_default, rebuiltTokens) : HTML_THEME_PRESETS[key];
    app.dataset.htmlTheme = key;
    const profileGlow=Number(profile?.glow);
    applyThemeVariables(app, theme, Number.isFinite(profileGlow) ? profileGlow : 80);
    try {
      localStorage.setItem('arzmarket-html-theme', key);
      if (globalEnabled) localStorage.setItem('arzmarket-html-global-palette', JSON.stringify(Object.assign({},profile,{tokens:rebuiltTokens,palette_model:2})));
    } catch (_) {}
  }

  const el = id => document.getElementById(id);
  const asArray = value => Array.isArray(value) ? value : [];
  const refs = {
    app: el('app'), runtimeText: el('runtimeText'), minimalModeButton: el('minimalModeButton'), minimalModeFullButton: el('minimalModeFullButton'), pageHeaderIcon: el('pageHeaderIcon'),
    pageTitle: el('pageTitle'), pageSubtitle: el('pageSubtitle'), configSelect: el('configSelect'),
    automationBadge: el('automationBadge'), saveBadge: el('saveBadge'), searchInput: el('searchInput'),
    globalSearchResults: el('globalSearchResults'), tradeFilterButton: el('tradeFilterButton'),
    tradeFilterPanel: el('tradeFilterPanel'), tradeFilterCategories: el('tradeFilterCategories'), tradeFilterClose: el('tradeFilterClose'),
    addButton: el('addButton'), undoButton: el('undoButton'), clearButton: el('clearButton'), scanButton: el('scanButton'),
    continueButton: el('continueButton'), budgetButton: el('budgetButton'), currencyButton: el('currencyButton'), refreshButton: el('refreshButton'),
    pricesButton: el('pricesButton'), averageButton: el('averageButton'), startButton: el('startButton'), sellScanMainButton: el('sellScanMainButton'), sellCurrencyQuickButton: el('sellCurrencyQuickButton'),
    tableHead: el('tableHead'), tableRows: el('tableRows'), emptyState: el('emptyState'),
    mainWorkspace: document.querySelector('.workspace'),
    detailEmpty: el('detailEmpty'), detailContent: el('detailContent'), detailIcon: el('detailIcon'),
    detailName: el('detailName'), detailFields: el('detailFields'),
    pickerBackdrop: el('pickerBackdrop'), pickerTitle: el('pickerTitle'), pickerSearch: el('pickerSearch'),
    pickerRows: el('pickerRows'), budgetBackdrop: el('budgetBackdrop'), budgetInput: el('budgetInput'),
    budgetEligible: el('budgetEligible'), budgetSpent: el('budgetSpent'), budgetRemaining: el('budgetRemaining'),
    budgetCancel: el('budgetCancel'), budgetApply: el('budgetApply'), toast: el('toast'),
    sellWorkspace: el('sellWorkspace'), sellInventoryCount: el('sellInventoryCount'), sellInventorySearch: el('sellInventorySearch'),
    sellInventoryRows: el('sellInventoryRows'), sellInventoryEmpty: el('sellInventoryEmpty'), sellScanButton: el('sellScanButton'),
    sellActiveCount: el('sellActiveCount'), sellToolsButton: el('sellToolsButton'), sellToolsPanel: el('sellToolsPanel'),
    sellConfigButton: el('sellConfigButton'), sellConfigName: el('sellConfigName'), sellScanState: el('sellScanState'), sellCurrencyState: el('sellCurrencyState'),
    sellSaleRows: el('sellSaleRows'), sellSaleEmpty: el('sellSaleEmpty'), sellTotalItems: el('sellTotalItems'),
    sellEnabledItems: el('sellEnabledItems'), sellDisabledItems: el('sellDisabledItems'), sellExpectedIncome: el('sellExpectedIncome'), sellInfoEmpty: el('sellInfoEmpty'),
    sellInfoContent: el('sellInfoContent'), sellInfoIcon: el('sellInfoIcon'), sellInfoName: el('sellInfoName'), sellInfoKind: el('sellInfoKind'),
    sellStockInventory: el('sellStockInventory'), sellStockSelling: el('sellStockSelling'), sellStockFree: el('sellStockFree'),
    sellInfoPrice: el('sellInfoPrice'), sellPricePrefix: el('sellPricePrefix'), sellInfoCount: el('sellInfoCount'), sellInfoMax: el('sellInfoMax'),
    sellInfoIncome: el('sellInfoIncome'), sellMarketAverage: el('sellMarketAverage'), sellMarketMin: el('sellMarketMin'),
    sellMarketMax: el('sellMarketMax'), sellStartButton: el('sellStartButton'), sellStartButtonText: el('sellStartButtonText'),
    tradeHeaderMeta: document.querySelector('.page-header-meta'), pageHeaderHint: document.querySelector('.page-header-hint'),
    logsHeaderMeta: el('logsHeaderMeta'), logsPeriodButton: el('logsPeriodButton'), logsToolbar: el('logsToolbar'), logsSearchInput: el('logsSearchInput'),
    logsCategoryButton: el('logsCategoryButton'), logsStatusButton: el('logsStatusButton'), logsDateButton: el('logsDateButton'), logsRefreshButton: el('logsRefreshButton'),
    logsWorkspace: el('logsWorkspace'), logsRows: el('logsRows'), logsEmpty: el('logsEmpty'), logsTotalRecords: el('logsTotalRecords'), logsShownRecords: el('logsShownRecords'), logsPagination: el('logsPagination'),
    logsDetailEmpty: el('logsDetailEmpty'), logsDetailContent: el('logsDetailContent'), logsDetailDate: el('logsDetailDate'), logsDetailTime: el('logsDetailTime'),
    logsDetailCategory: el('logsDetailCategory'), logsDetailDescription: el('logsDetailDescription'), logsDetailSubtext: el('logsDetailSubtext'), logsDetailAmount: el('logsDetailAmount'),
    logsDetailStatus: el('logsDetailStatus'), logsDetailId: el('logsDetailId'), logsActivityChart: el('logsActivityChart'), logsActivityTotal: el('logsActivityTotal'),
    logsStatTotal: el('logsStatTotal'), logsStatSuccess: el('logsStatSuccess'), logsStatWarnings: el('logsStatWarnings'),
    storageHeaderMeta: el('storageHeaderMeta'), storageToolbar: el('storageToolbar'), storageSearchInput: el('storageSearchInput'), storageTypeButton: el('storageTypeButton'),
    storageScanButton: el('storageScanButton'), storageFindButton: el('storageFindButton'), storagePlaceTabs: el('storagePlaceTabs'), storageWorkspace: el('storageWorkspace'), storageRows: el('storageRows'),
    storageEmpty: el('storageEmpty'), storageFoundCount: el('storageFoundCount'), storageTotalCount: el('storageTotalCount'), storagePlacesCount: el('storagePlacesCount'), storageDetailEmpty: el('storageDetailEmpty'),
    storageDetailContent: el('storageDetailContent'), storageDetailIcon: el('storageDetailIcon'), storageDetailName: el('storageDetailName'), storageDetailType: el('storageDetailType'), storageDetailTotal: el('storageDetailTotal'),
    storageLocationRows: el('storageLocationRows'), storageDistributionTab: el('storageDistributionTab'), storageInfoTab: el('storageInfoTab'), storageDistributionPanel: el('storageDistributionPanel'), storageInfoPanel: el('storageInfoPanel'),
    storageInfoType: el('storageInfoType'), storageInfoId: el('storageInfoId'), storageInfoUpdated: el('storageInfoUpdated'), storageAveragePrices: el('storageAveragePrices'),
    settingsHeaderMeta: el('settingsHeaderMeta'), settingsToolbar: el('settingsToolbar'), settingsWorkspace: el('settingsWorkspace'), settingsContent: el('settingsContent'),
    modsHeaderMeta: el('modsHeaderMeta'), modsWorkspace: el('modsWorkspace'),
    marketplaceHeaderMeta: el('marketplaceHeaderMeta'), marketplaceToolbar: el('marketplaceToolbar'), marketplaceRefreshButton: el('marketplaceRefreshButton'),
    marketplaceShopCount: el('marketplaceShopCount'), marketplaceSearchInput: el('marketplaceSearchInput'), marketplaceServerButton: el('marketplaceServerButton'), marketplaceSortButton: el('marketplaceSortButton'),
    marketplaceWorkspace: el('marketplaceWorkspace'), marketplaceStatus: el('marketplaceStatus'), marketplaceBrowse: el('marketplaceBrowse'), marketplaceCards: el('marketplaceCards'), marketplaceBrowseEmpty: el('marketplaceBrowseEmpty'),
    marketplaceSearchView: el('marketplaceSearchView'), marketplaceBuyCount: el('marketplaceBuyCount'), marketplaceSellCount: el('marketplaceSellCount'), marketplaceBuyResults: el('marketplaceBuyResults'), marketplaceSellResults: el('marketplaceSellResults'), marketplaceBuyEmpty: el('marketplaceBuyEmpty'), marketplaceSellEmpty: el('marketplaceSellEmpty'),
    marketplaceShopView: el('marketplaceShopView'), marketplaceBackButton: el('marketplaceBackButton'), marketplaceShopOwner: el('marketplaceShopOwner'), marketplaceShopUid: el('marketplaceShopUid'), marketplaceShopServer: el('marketplaceShopServer'), marketplaceShopItemsTotal: el('marketplaceShopItemsTotal'), marketplaceFindShopButton: el('marketplaceFindShopButton'), marketplaceShopBuyCount: el('marketplaceShopBuyCount'), marketplaceShopSellCount: el('marketplaceShopSellCount'), marketplaceShopBuyRows: el('marketplaceShopBuyRows'), marketplaceShopSellRows: el('marketplaceShopSellRows')
  };

  try { const storedKey=localStorage.getItem('arzmarket-html-theme') || 'arzmarket_default'; applyHtmlTheme(storedKey, storedKey === 'global_palette' ? readStoredGlobalTheme() : null); } catch (_) { applyHtmlTheme('arzmarket_default'); }

  let activePopupSelect = null;

  function closePopupSelect() {
    const active = activePopupSelect;
    if (!active) return;
    activePopupSelect = null;
    try { active.menu.remove(); } catch (_) {}
    if (active.anchor && active.anchor.isConnected) {
      active.anchor.classList.remove('open');
      active.anchor.setAttribute('aria-expanded', 'false');
    }
  }

  function positionPopupSelect(active) {
    if (!active || !active.anchor?.isConnected || !active.menu?.isConnected) return;
    const rect = active.anchor.getBoundingClientRect();
    const margin = 8;
    const preferredWidth = Math.max(rect.width, active.minWidth || 0);
    active.menu.style.width = `${Math.min(preferredWidth, window.innerWidth - margin * 2)}px`;
    active.menu.style.left = `${Math.max(margin, Math.min(rect.left, window.innerWidth - preferredWidth - margin))}px`;
    active.menu.style.visibility = 'hidden';
    active.menu.style.top = '0px';
    const menuHeight = Math.min(active.menu.scrollHeight || 280, Math.max(120, window.innerHeight - margin * 2));
    const below = window.innerHeight - rect.bottom - margin;
    const above = rect.top - margin;
    const top = below >= Math.min(menuHeight, 260) || below >= above
      ? rect.bottom + 5
      : Math.max(margin, rect.top - Math.min(menuHeight, above) - 5);
    active.menu.style.top = `${Math.max(margin, Math.min(top, window.innerHeight - menuHeight - margin))}px`;
    active.menu.style.maxHeight = `${Math.max(120, Math.min(320, window.innerHeight - parseFloat(active.menu.style.top) - margin))}px`;
    active.menu.style.visibility = '';
  }

  function openPopupSelect(anchor, options, currentValue, onSelect, kind = 'generic') {
    if (!anchor || anchor.disabled) return;
    if (activePopupSelect?.anchor === anchor) {
      closePopupSelect();
      return;
    }
    closePopupSelect();
    const menu = document.createElement('div');
    menu.className = 'custom-select-menu';
    menu.setAttribute('role', 'listbox');
    for (const option of options || []) {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = `custom-select-option ${String(option.value) === String(currentValue) ? 'selected' : ''}`;
      button.dataset.value = String(option.value ?? '');
      button.setAttribute('role', 'option');
      button.setAttribute('aria-selected', String(option.value) === String(currentValue) ? 'true' : 'false');
      const label = document.createElement('span');
      label.className = 'custom-select-option-label';
      label.textContent = text(option.label);
      button.append(label);
      button.addEventListener('click', async event => {
        event.preventDefault();
        event.stopPropagation();
        if (button.classList.contains('busy')) return;
        const value = button.dataset.value || '';
        closePopupSelect();
        await onSelect(value);
      });
      menu.append(button);
    }
    if (!menu.children.length) {
      const empty = document.createElement('div');
      empty.className = 'custom-select-empty';
      empty.textContent = 'Нет вариантов';
      menu.append(empty);
    }
    document.body.append(menu);
    anchor.classList.add('open');
    anchor.setAttribute('aria-expanded', 'true');
    activePopupSelect = {anchor, menu, kind, minWidth: Math.max(anchor.getBoundingClientRect().width, 180)};
    positionPopupSelect(activePopupSelect);
  }

  document.addEventListener('pointerdown', event => {
    if (!activePopupSelect) return;
    if (activePopupSelect.anchor?.contains(event.target) || activePopupSelect.menu?.contains(event.target)) return;
    closePopupSelect();
  }, true);
  // SA-MP cursor compatibility. When a native SA-MP dialog owns the visible
  // cursor, MoonLoader forwards only events that happen over the ArzMarket
  // window. Native browser input remains the default path in every other case.
  const hostInputState = {
    downTarget:null,
    lastTrusted:null,
    lastSynthetic:null,
    buttonsMask:0,
    lastTrustedKey:null,
    lastSyntheticKey:null,
    lastTrustedText:null,
    lastSyntheticText:null
  };
  function hostInputButtonMask(button) { return button === 0 ? 1 : button === 1 ? 4 : 2; }
  function hostInputNear(a, b) { return a && b && Math.abs(Number(a.x)-Number(b.x)) <= 3 && Math.abs(Number(a.y)-Number(b.y)) <= 3 && Number(a.button ?? 0) === Number(b.button ?? 0); }
  function hostInputStamp(type, event) { return {type,x:Number(event?.clientX)||0,y:Number(event?.clientY)||0,button:Number(event?.button)||0,at:performance.now()}; }
  function hostInputTrustedRecently(type, x, y, button) {
    const last = hostInputState.lastTrusted;
    return !!(last && last.type === type && performance.now() - last.at < 80 && hostInputNear(last,{x,y,button}));
  }
  ['mousedown','mouseup','click','wheel'].forEach(type => document.addEventListener(type, event => {
    if (!event.isTrusted) return;
    const current = hostInputStamp(type,event);
    const bit = hostInputButtonMask(Number(event.button) || 0);
    if (type === 'mousedown') hostInputState.buttonsMask |= bit;
    else if (type === 'mouseup') hostInputState.buttonsMask &= ~bit;
    const synthetic = hostInputState.lastSynthetic;
    if (synthetic && synthetic.type === type && performance.now() - synthetic.at < 80 && hostInputNear(synthetic,current)) {
      event.preventDefault();
      event.stopImmediatePropagation();
      return;
    }
    hostInputState.lastTrusted = current;
  }, true));
  function hostInputKeyCode(event) { return Number(event?.keyCode || event?.which || 0); }
  function hostInputTrustedKeyRecently(type, code) {
    const last = hostInputState.lastTrustedKey;
    return !!(last && last.type === type && Number(last.code) === Number(code) && performance.now() - last.at < 80);
  }
  ['keydown','keyup'].forEach(type => document.addEventListener(type, event => {
    if (!event.isTrusted) return;
    const current = {type,code:hostInputKeyCode(event),at:performance.now()};
    const synthetic = hostInputState.lastSyntheticKey;
    if (synthetic && synthetic.type === type && synthetic.code === current.code && performance.now() - synthetic.at < 80) {
      event.preventDefault();
      event.stopImmediatePropagation();
      return;
    }
    hostInputState.lastTrustedKey = current;
  }, true));
  document.addEventListener('beforeinput', event => {
    if (!event.isTrusted) return;
    const text = typeof event.data === 'string' ? event.data : '';
    const synthetic = hostInputState.lastSyntheticText;
    if (synthetic && synthetic.text === text && performance.now() - synthetic.at < 80) {
      if (event.cancelable) event.preventDefault();
      event.stopImmediatePropagation();
      return;
    }
    hostInputState.lastTrustedText = {text,at:performance.now()};
  }, true);
  function hostInputKeyName(code) {
    const names = {8:'Backspace',9:'Tab',13:'Enter',16:'Shift',17:'Control',18:'Alt',27:'Escape',32:' ',33:'PageUp',34:'PageDown',35:'End',36:'Home',37:'ArrowLeft',38:'ArrowUp',39:'ArrowRight',40:'ArrowDown',45:'Insert',46:'Delete'};
    if (names[code]) return names[code];
    if (code >= 48 && code <= 57) return String.fromCharCode(code);
    if (code >= 65 && code <= 90) return String.fromCharCode(code);
    return '';
  }
  function hostInputFocusable(node) {
    if (!node || node === document.body || node === document.documentElement) return false;
    const tag = String(node.tagName || '').toLowerCase();
    return tag === 'input' || tag === 'textarea' || tag === 'select' || tag === 'button' || tag === 'a' || node.isContentEditable || Number(node.tabIndex) >= 0;
  }
  function hostInputFocus(node) {
    let target = node;
    while (target && target !== document.body && !hostInputFocusable(target)) target = target.parentElement;
    try { (target || node)?.focus?.({preventScroll:true}); } catch (_) { try { (target || node)?.focus?.(); } catch (_) {} }
    try { window.focus(); } catch (_) {}
    return target || node;
  }
  function hostInputDispatchMouse(data) {
    const x = Number(data.x), y = Number(data.y);
    if (!Number.isFinite(x) || !Number.isFinite(y)) return;
    const hit = document.elementFromPoint(x, y);
    if (!hit) return;
    const button = Number.isFinite(Number(data.button)) ? Number(data.button) : 0;
    const bit = hostInputButtonMask(button);
    let buttons = hostInputState.buttonsMask;
    if (data.event === 'down') buttons |= bit;
    else if (data.event === 'up') buttons &= ~bit;
    const common = {bubbles:true,cancelable:true,view:window,clientX:x,clientY:y,screenX:x,screenY:y,button,buttons};
    if (data.event === 'move') {
      try { hit.dispatchEvent(new MouseEvent('mousemove', common)); } catch (_) {}
      try { hit.dispatchEvent(new PointerEvent('pointermove', Object.assign({pointerId:1,pointerType:'mouse',isPrimary:true}, common))); } catch (_) {}
      return;
    }
    if (data.event === 'wheel') {
      const delta = Number(data.delta) || 0;
      if (hostInputTrustedRecently('wheel',x,y,button)) return;
      hostInputState.lastSynthetic = {type:'wheel',x,y,button,at:performance.now()};
      try { hit.dispatchEvent(new WheelEvent('wheel', Object.assign({deltaMode:WheelEvent.DOM_DELTA_LINE,deltaY:-delta}, common))); } catch (_) {}
      return;
    }
    if (data.event === 'down') {
      hostInputState.buttonsMask = buttons;
      if (hostInputTrustedRecently('mousedown',x,y,button)) return;
      const target = hostInputFocus(hit);
      hostInputState.downTarget = target || hit;
      hostInputState.lastSynthetic = {type:'mousedown',x,y,button,at:performance.now()};
      try { (target || hit).dispatchEvent(new PointerEvent('pointerdown', Object.assign({pointerId:1,pointerType:'mouse',isPrimary:true}, common))); } catch (_) {}
      try { (target || hit).dispatchEvent(new MouseEvent('mousedown', common)); } catch (_) {}
      return;
    }
    if (data.event === 'up') {
      hostInputState.buttonsMask = buttons;
      if (hostInputTrustedRecently('mouseup',x,y,button)) { hostInputState.downTarget = null; return; }
      const target = hit || hostInputState.downTarget;
      hostInputState.lastSynthetic = {type:'mouseup',x,y,button,at:performance.now()};
      try { target.dispatchEvent(new PointerEvent('pointerup', Object.assign({pointerId:1,pointerType:'mouse',isPrimary:true}, common))); } catch (_) {}
      try { target.dispatchEvent(new MouseEvent('mouseup', common)); } catch (_) {}
      const down = hostInputState.downTarget;
      hostInputState.downTarget = null;
      if (button === 0 && down && (down === target || down.contains?.(target) || target.contains?.(down))) {
        if (!hostInputTrustedRecently('click',x,y,button)) {
          hostInputState.lastSynthetic = {type:'click',x,y,button,at:performance.now()};
          try { target.dispatchEvent(new MouseEvent('click', Object.assign({}, common, {buttons:0}))); } catch (_) { try { target.click?.(); } catch (_) {} }
        }
      }
    }
  }
  function hostInputEditCharacter(target, charCode) {
    if (!target || !Number.isFinite(charCode) || charCode <= 0) return false;
    const text = String.fromCharCode(charCode);
    const trusted = hostInputState.lastTrustedText;
    if (trusted && trusted.text === text && performance.now() - trusted.at < 80) return true;
    hostInputState.lastSyntheticText = {text,at:performance.now()};
    const tag = String(target.tagName || '').toLowerCase();
    if (tag === 'input' || tag === 'textarea') {
      if (target.disabled || target.readOnly) return false;
      const start = Number.isFinite(target.selectionStart) ? target.selectionStart : String(target.value || '').length;
      const end = Number.isFinite(target.selectionEnd) ? target.selectionEnd : start;
      try { target.setRangeText(text, start, end, 'end'); }
      catch (_) { target.value = String(target.value || '').slice(0,start) + text + String(target.value || '').slice(end); }
      try { target.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:text})); } catch (_) { target.dispatchEvent(new Event('input',{bubbles:true})); }
      return true;
    }
    if (target.isContentEditable) {
      try { document.execCommand('insertText', false, text); return true; } catch (_) {}
    }
    return false;
  }
  function hostInputEditControl(target, code) {
    const tag = String(target?.tagName || '').toLowerCase();
    if ((tag !== 'input' && tag !== 'textarea') || target.disabled || target.readOnly) return false;
    const value = String(target.value || '');
    let start = Number.isFinite(target.selectionStart) ? target.selectionStart : value.length;
    let end = Number.isFinite(target.selectionEnd) ? target.selectionEnd : start;
    if (code === 8 && start === end && start > 0) start -= 1;
    else if (code === 46 && start === end && end < value.length) end += 1;
    else if (code !== 8 && code !== 46) return false;
    try { target.setRangeText('', start, end, 'end'); }
    catch (_) { target.value = value.slice(0,start) + value.slice(end); }
    try { target.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:code===8?'deleteContentBackward':'deleteContentForward',data:null})); } catch (_) { target.dispatchEvent(new Event('input',{bubbles:true})); }
    return true;
  }
  function hostInputDispatchKeyboard(data) {
    const target = document.activeElement || document.body;
    const code = Number(data.keyCode) || 0;
    if (data.event === 'char') {
      const explicitText = typeof data.text === 'string' ? data.text : '';
      if (explicitText) {
        const trusted = hostInputState.lastTrustedText;
        if (trusted && trusted.text === explicitText && performance.now() - trusted.at < 80) return;
        hostInputState.lastSyntheticText = {text:explicitText,at:performance.now()};
        const tag = String(target?.tagName || '').toLowerCase();
        if (tag === 'input' || tag === 'textarea') {
          if (!target.disabled && !target.readOnly) {
            const start = Number.isFinite(target.selectionStart) ? target.selectionStart : String(target.value || '').length;
            const end = Number.isFinite(target.selectionEnd) ? target.selectionEnd : start;
            try { target.setRangeText(explicitText, start, end, 'end'); }
            catch (_) { target.value = String(target.value || '').slice(0,start) + explicitText + String(target.value || '').slice(end); }
            try { target.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:explicitText})); } catch (_) { target.dispatchEvent(new Event('input',{bubbles:true})); }
          }
        } else if (target?.isContentEditable) {
          try { document.execCommand('insertText', false, explicitText); } catch (_) {}
        }
        return;
      }
      hostInputEditCharacter(target, Number(data.charCode) || code);
      return;
    }
    const type = data.event === 'up' ? 'keyup' : 'keydown';
    if (hostInputTrustedKeyRecently(type,code)) return;
    hostInputState.lastSyntheticKey = {type,code,at:performance.now()};
    if (data.event === 'down') hostInputEditControl(target, code);
    const key = hostInputKeyName(code);
    try {
      target.dispatchEvent(new KeyboardEvent(type,{bubbles:true,cancelable:true,key,code:key,which:code,keyCode:code,ctrlKey:data.ctrl===true,shiftKey:data.shift===true,altKey:data.alt===true}));
    } catch (_) {}
  }
  window.addEventListener('message', event => {
    const data = event?.data;
    if (!data || data.channel !== 'arzmarket-host-input') return;
    if (event.source && event.source !== window.parent) return;
    if (data.kind === 'mouse') hostInputDispatchMouse(data);
    else if (data.kind === 'keyboard') hostInputDispatchKeyboard(data);
  }, false);

  document.addEventListener('keydown', event => {
    if (event.key === 'Escape' && activePopupSelect) {
      closePopupSelect();
      event.stopPropagation();
    }
  }, true);
  window.addEventListener('resize', () => activePopupSelect && positionPopupSelect(activePopupSelect));

  const configSelectButton = document.createElement('button');
  configSelectButton.type = 'button';
  configSelectButton.className = 'select custom-select-trigger config-select-trigger';
  configSelectButton.setAttribute('aria-haspopup', 'listbox');
  configSelectButton.setAttribute('aria-expanded', 'false');
  configSelectButton.setAttribute('data-baron-anchor', 'sell_config');
  const configSelectText = document.createElement('span');
  configSelectText.className = 'custom-select-value';
  const configSelectChevron = document.createElement('span');
  configSelectChevron.className = 'custom-select-chevron';
  configSelectButton.append(configSelectText, configSelectChevron);
  refs.configSelect.classList.add('native-select-hidden');
  refs.configSelect.removeAttribute('data-baron-anchor');
  refs.configSelect.setAttribute('aria-hidden', 'true');
  refs.configSelect.tabIndex = -1;
  refs.configSelect.insertAdjacentElement('afterend', configSelectButton);
  refs.configSelectButton = configSelectButton;
  refs.configSelectText = configSelectText;

  const toolbar = document.querySelector('.toolbar');
  const secondaryActions = document.querySelector('.more-actions');
  if (toolbar && secondaryActions) {
    toolbar.addEventListener('contextmenu', event => {
      if (state.page !== 'buy') return;
      event.preventDefault();
      secondaryActions.open = !secondaryActions.open;
    });
    document.addEventListener('pointerdown', event => {
      if (!secondaryActions.open || secondaryActions.contains(event.target)) return;
      secondaryActions.open = false;
    });
    document.addEventListener('keydown', event => {
      if (event.key === 'Escape' && secondaryActions.open) {
        secondaryActions.open = false;
        event.stopPropagation();
      }
    }, true);
  }

  function applyPreviewScale() {

    if (!previewMode) return;
    const win = document.querySelector('.window');
    const shell = document.querySelector('.app-shell');
    const dim = document.querySelector('.game-dim');
    if (!win || !shell) return;

    // Preview is embedded into a much smaller CEF iframe. Render the same live
    // interface responsively inside that iframe instead of drawing a desktop-sized
    // window and then scaling the already-small CSS window a second time.
    const vw = Math.max(1, window.innerWidth);
    const vh = Math.max(1, window.innerHeight);
    const referenceScale = Math.min(vw / 1600, vh / 900);
    const scale = Math.max(0.38, Math.min(0.78, referenceScale * 1.16));

    shell.style.display = 'block';
    shell.style.padding = '0';
    if (dim) dim.style.background = '#071018';
    win.style.setProperty('--ui-scale', scale.toFixed(3));
    win.style.setProperty('position', 'absolute', 'important');
    win.style.setProperty('left', '0px', 'important');
    win.style.setProperty('top', '0px', 'important');
    win.style.setProperty('width', '100vw', 'important');
    win.style.setProperty('height', '100vh', 'important');
    win.style.setProperty('min-width', '0px', 'important');
    win.style.setProperty('min-height', '0px', 'important');
    win.style.setProperty('max-width', 'none', 'important');
    win.style.setProperty('max-height', 'none', 'important');
    win.style.setProperty('transform', 'none', 'important');
    win.style.setProperty('transform-origin', 'top left', 'important');
    win.style.setProperty('border-radius', '8px', 'important');
    win.dataset.uiDensity = 'compact';
  }

  if (previewMode) {
    window.addEventListener('resize', applyPreviewScale);
    window.setTimeout(applyPreviewScale, 0);
  }

  const text = value => String(value == null ? '' : value);
  const normalizeName = value => text(value).replace(/\{[0-9a-fA-F]{6}\}/g, '').replace(/\s+/g, ' ').trim().toLocaleLowerCase('ru-RU');
  const catalogName = value => normalizeName(value).replace(/\s*\(\+\d+\)\s*$/, '');
  const money = value => {
    const n = Number(value);
    return Number.isFinite(n) ? Math.trunc(n).toLocaleString('ru-RU').replace(/\u00a0/g, ' ') : '0';
  };
  const moneyRef = value => {
    const n = Number(value);
    if (!Number.isFinite(n)) return '0';
    return Math.trunc(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, '.');
  };
  const parseMoneyInput = value => {
    const digits = String(value == null ? '' : value).replace(/[^0-9]/g, '');
    if (!digits) return 0;
    const n = Number(digits);
    return Number.isFinite(n) ? Math.trunc(n) : 0;
  };
  const ITEM_KIND_LABELS = Object.freeze({
    cases: 'Контейнер', accessories: 'Аксессуар', skins: 'Одежда', weapons: 'Оружие',
    certificates: 'Сертификат', tuning: 'Тюнинг', upgrades: 'Улучшение', resources: 'Ресурс',
    objects: 'Предмет', shards: 'Осколок', other: 'Предмет'
  });
  const itemKind = item => ITEM_KIND_LABELS[String(item?.category || 'other')] || 'Предмет';
  const FALLBACK_CATEGORY_FILTERS = Object.freeze([
    {id:'cases',label:'Ларцы'},{id:'accessories',label:'Аксессуары'},{id:'skins',label:'Скины'},
    {id:'weapons',label:'Оружие'},{id:'certificates',label:'Сертификаты'},{id:'tuning',label:'Тюнинг'},
    {id:'upgrades',label:'Улучшения'},{id:'resources',label:'Ресурсы/крафт'},{id:'objects',label:'Объекты'},
    {id:'shards',label:'Осколки'},{id:'other',label:'Прочее'}
  ]);
  const categoryFilters = () => {
    const rows = state.data?.common?.itemCategories;
    return Array.isArray(rows) && rows.length ? rows : FALLBACK_CATEGORY_FILTERS;
  };
  const categoryLabel = id => categoryFilters().find(row => String(row.id) === String(id))?.label || ITEM_KIND_LABELS[String(id || 'other')] || 'Прочее';
  const categoryOrderIds = () => categoryFilters().map(row => String(row.id));
  const categoryRank = id => { const index = categoryOrderIds().indexOf(String(id || 'other')); return index >= 0 ? index : 999; };

  const getItemId = item => {
    const value = item && (item.item_id ?? item.identity?.item_id);
    return value == null || String(value) === '' ? null : String(value);
  };
  const placeholder = () => 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><rect width="64" height="64" rx="10" fill="#101b24"/><path d="M20 23h24v20H20zM25 18h14" fill="none" stroke="#405461" stroke-width="2"/><path d="m25 37 5-6 5 5 4-4 5 5" fill="none" stroke="#536b78" stroke-width="2"/></svg>');
  const iconSvg = name => {
    const attrs = 'viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\"';
    const paths = {
      buy: '<circle cx=\"9\" cy=\"20\" r=\"1\"/><circle cx=\"19\" cy=\"20\" r=\"1\"/><path d=\"M3 4h2l2.7 10.2a2 2 0 0 0 1.9 1.5h7.8a2 2 0 0 0 1.9-1.4L21 8H7\"/>',
      sell: '<path d=\"M20.5 13.5 12 22l-9-9V3h10z\"/><circle cx=\"8.5\" cy=\"8.5\" r=\"1.2\"/>',
      settings: '<circle cx=\"12\" cy=\"12\" r=\"3\"/><path d=\"M19.4 15a1.7 1.7 0 0 0 .3 1.9l.1.1-2.8 2.8-.1-.1a1.7 1.7 0 0 0-1.9-.3 1.7 1.7 0 0 0-1 1.5V21h-4v-.1a1.7 1.7 0 0 0-1-1.5 1.7 1.7 0 0 0-1.9.3l-.1.1L4.2 17l.1-.1a1.7 1.7 0 0 0 .3-1.9 1.7 1.7 0 0 0-1.5-1H3v-4h.1a1.7 1.7 0 0 0 1.5-1 1.7 1.7 0 0 0-.3-1.9L4.2 7 7 4.2l.1.1A1.7 1.7 0 0 0 9 4.6a1.7 1.7 0 0 0 1-1.5V3h4v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.9-.3l.1-.1L19.8 7l-.1.1a1.7 1.7 0 0 0-.3 1.9 1.7 1.7 0 0 0 1.5 1h.1v4h-.1a1.7 1.7 0 0 0-1.5 1z\"/>',
      logs: '<path d=\"M6 2h9l4 4v16H6z\"/><path d=\"M14 2v5h5M9 12h6M9 16h6\"/>',
      market: '<path d=\"M4 10h16l-1-5H5zM5 10v9h14v-9\"/><path d=\"M8 19v-5h4v5M3 10c0 1.3 1 2.3 2.3 2.3S7.7 11.3 7.7 10c0 1.3 1 2.3 2.3 2.3s2.3-1 2.3-2.3c0 1.3 1 2.3 2.3 2.3s2.4-1 2.4-2.3c0 1.3 1 2.3 2.3 2.3S21.7 11.3 21.7 10\"/>',
      mods: '<path d=\"M14.7 6.3a4 4 0 0 0-5 5L4 17l3 3 5.7-5.7a4 4 0 0 0 5-5l-2.5 2.5-3-3z\"/><path d=\"m5 19 2-2\"/>',
      storage: '<path d=\"M3 6h18v4H3zM5 10h14v10H5zM9 14h6\"/>'
    };
    return `<svg ${attrs}>${paths[name] || paths.buy}</svg>`;
  };

  function hydrateSidebarIcons() {
    const map={sell:'sell',buy:'buy',settings:'settings',logs:'logs',marketplace:'market',mods:'mods',storage:'storage'};
    document.querySelectorAll('.nav-item[data-page]').forEach(button=>{
      const host=button.querySelector('.nav-icon');
      const key=map[String(button.dataset.page||'')];
      if (host && key) host.innerHTML=iconSvg(key);
    });
  }
  hydrateSidebarIcons();


  function setIcon(img, item, size) {
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

  function showToast(message, type = '') {
    clearTimeout(state.toastTimer);
    refs.toast.textContent = text(message);
    refs.toast.className = `toast ${type}`.trim();
    state.toastTimer = setTimeout(() => refs.toast.classList.add('hidden'), 2600);
  }

  async function api(path, options = {}) {
    const headers = Object.assign({}, options.headers || {}, {'X-ArzMarket-Token': token});
    if (options.body && !headers['Content-Type']) headers['Content-Type'] = 'application/json';
    const timeoutMs = Math.max(1000, Number(options.timeoutMs || 5000));
    const fetchOptions = Object.assign({}, options);
    delete fetchOptions.timeoutMs;
    const controller = typeof AbortController === 'function' ? new AbortController() : null;
    const timeoutId = controller ? window.setTimeout(() => controller.abort(), timeoutMs) : null;
    let response;
    try {
      response = await fetch(path, Object.assign({}, fetchOptions, {headers, cache: 'no-store', signal: controller ? controller.signal : options.signal}));
    } finally {
      if (timeoutId !== null) window.clearTimeout(timeoutId);
    }
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

  let baronAssistantUi = null;

  const averagePriceKey = name => catalogName(name || '');

  async function requestAveragePrices(itemOrName) {
    const name = typeof itemOrName === 'string' ? itemOrName : itemOrName?.name;
    const key = averagePriceKey(name);
    if (!key) return {available:false,name:text(name)};
    if (state.averagePrices.cache.has(key)) return state.averagePrices.cache.get(key);
    if (state.averagePrices.pending.has(key)) return state.averagePrices.pending.get(key);
    const promise = action('prices.lookup', {page:state.page,name:text(name)})
      .then(result => result?.data || {available:false,name:text(name)})
      .catch(() => ({available:false,name:text(name)}))
      .then(data => {
        state.averagePrices.cache.set(key, data);
        state.averagePrices.pending.delete(key);
        return data;
      });
    state.averagePrices.pending.set(key, promise);
    return promise;
  }

  function averagePriceLine(entry, currency) {
    const line = div('', 'avg-price-history-line');
    if (!entry) return line;
    const value = document.createElement('strong');
    value.textContent = `${currency} ${moneyRef(entry.unit || 0)}`;
    const count = document.createElement('span');
    count.textContent = `(${money(entry.count || 0)} шт.)`;
    line.append(value, count);
    return line;
  }

  function averagePriceHistoryColumn(title, rows) {
    const column = div('', 'avg-price-history-column');
    column.append(div(title, 'avg-price-column-title'));
    const body = div('', 'avg-price-history-body');
    const list = Array.isArray(rows) ? rows : [];
    if (!list.length) {
      body.append(div('Нет данных', 'avg-price-empty'));
    } else {
      for (const row of list) {
        const item = div('', 'avg-price-history-item');
        item.append(div(row.date || '-', 'avg-price-date'));
        if (row.sa) item.append(averagePriceLine(row.sa, 'SA$'));
        if (row.sa_to_vc != null) item.append(div(`VC$ ${moneyRef(row.sa_to_vc)}`, 'avg-price-converted'));
        if (row.vc) item.append(averagePriceLine(row.vc, 'VC$'));
        if (row.vc_to_sa != null) item.append(div(`SA$ ${moneyRef(row.vc_to_sa)}`, 'avg-price-converted'));
        body.append(item);
      }
    }
    column.append(body);
    return column;
  }

  function renderAveragePricesInto(target, data, options = {}) {
    if (!target) return;
    target.innerHTML = '';
    const name = data?.name || options.name || 'Предмет';
    const root = div('', `avg-price-panel ${options.compact ? 'compact' : ''}`.trim());
    if (!data?.available) {
      root.append(div(name, 'avg-price-panel-title'));
      root.append(div('Средние цены для этого предмета не найдены. Загрузите цены в ArzMarket.', 'avg-price-empty-message'));
      target.append(root);
      return;
    }
    const header = div('', 'avg-price-panel-header');
    const titleWrap = div('', 'avg-price-panel-heading');
    titleWrap.append(div(name, 'avg-price-panel-title'), div('Средние цены ArzMarket', 'avg-price-panel-subtitle'));
    const rates = div('', 'avg-price-rates');
    rates.append(div(`Покупка VC$ за ${moneyRef(data.buy_vc_rate || 1)} $`, ''), div(`Продажа VC$ за ${moneyRef(data.sell_vc_rate || 1)} $`, ''));
    header.append(titleWrap, rates);
    root.append(header);

    const configured = div('', 'avg-price-configured');
    configured.append(div(`$ ${moneyRef(data.configured_buy || 0)} скупаю`, ''), div(`$ ${moneyRef(data.configured_sell || 0)} продаю`, ''));
    root.append(configured);

    const grid = div('', 'avg-price-history-grid');
    grid.append(averagePriceHistoryColumn('Статистика покупок', data.buy), averagePriceHistoryColumn('Статистика продаж', data.sell));
    root.append(grid);
    target.append(root);
  }

  function ensureAveragePriceTooltip() {
    if (state.averagePrices.tooltip?.isConnected) return state.averagePrices.tooltip;
    const tooltip = document.createElement('div');
    tooltip.id = 'averagePriceTooltip';
    tooltip.className = 'avg-price-tooltip hidden';
    tooltip.addEventListener('mouseenter', () => clearTimeout(state.averagePrices.hideTimer));
    tooltip.addEventListener('mouseleave', () => scheduleHideAveragePriceTooltip(60));
    document.body.append(tooltip);
    state.averagePrices.tooltip = tooltip;
    return tooltip;
  }

  function positionAveragePriceTooltip(event) {
    const tooltip = state.averagePrices.tooltip;
    if (!tooltip || tooltip.classList.contains('hidden')) return;
    const margin = 14;
    const vw = window.innerWidth || document.documentElement.clientWidth;
    const vh = window.innerHeight || document.documentElement.clientHeight;
    const rect = tooltip.getBoundingClientRect();
    let x = Number(event?.clientX || 0) + 18;
    let y = Number(event?.clientY || 0) + 16;
    if (x + rect.width + margin > vw) x = Math.max(margin, Number(event?.clientX || 0) - rect.width - 18);
    if (y + rect.height + margin > vh) y = Math.max(margin, vh - rect.height - margin);
    tooltip.style.left = `${Math.max(margin, x)}px`;
    tooltip.style.top = `${Math.max(margin, y)}px`;
  }

  function scheduleHideAveragePriceTooltip(delay = 90) {
    clearTimeout(state.averagePrices.hoverTimer);
    clearTimeout(state.averagePrices.hideTimer);
    state.averagePrices.hideTimer = window.setTimeout(() => {
      const tooltip = state.averagePrices.tooltip;
      if (tooltip) tooltip.classList.add('hidden');
      state.averagePrices.activeKey = null;
    }, delay);
  }

  function bindAveragePriceHover(node, itemOrName) {
    if (!node || state.minimalMode === true) return;
    const name = typeof itemOrName === 'string' ? itemOrName : itemOrName?.name;
    const key = averagePriceKey(name);
    if (!key) return;
    node.classList.add('avg-price-hover-target');
    let lastEvent = null;
    node.addEventListener('mouseenter', event => {
      clearTimeout(state.averagePrices.hideTimer);
      clearTimeout(state.averagePrices.hoverTimer);
      lastEvent = event;
      state.averagePrices.activeKey = key;
      state.averagePrices.hoverTimer = window.setTimeout(async () => {
        if (state.averagePrices.activeKey !== key) return;
        const tooltip = ensureAveragePriceTooltip();
        tooltip.innerHTML = '';
        tooltip.append(div('Загрузка средних цен...', 'avg-price-loading'));
        tooltip.classList.remove('hidden');
        positionAveragePriceTooltip(lastEvent);
        const data = await requestAveragePrices(name);
        if (state.averagePrices.activeKey !== key) return;
        renderAveragePricesInto(tooltip, data, {name});
        positionAveragePriceTooltip(lastEvent);
      }, 130);
    });
    node.addEventListener('mousemove', event => {
      lastEvent = event;
      positionAveragePriceTooltip(event);
    });
    node.addEventListener('mouseleave', () => scheduleHideAveragePriceTooltip(110));
  }

  function renderStorageAveragePrices(item) {
    if (!refs.storageAveragePrices) return;
    const name = item?.name || '';
    const key = averagePriceKey(name);
    if (!key) {
      refs.storageAveragePrices.innerHTML = '<span class="avg-price-muted">Нет предмета.</span>';
      return;
    }
    state.averagePrices.storageKey = key;
    const cached = state.averagePrices.cache.get(key);
    if (cached) {
      renderAveragePricesInto(refs.storageAveragePrices, cached, {name,compact:true});
      return;
    }
    refs.storageAveragePrices.innerHTML = '<span class="avg-price-muted">Загрузка средних цен...</span>';
    requestAveragePrices(name).then(data => {
      if (state.averagePrices.storageKey !== key || state.storage.tab !== 'info') return;
      renderAveragePricesInto(refs.storageAveragePrices, data, {name,compact:true});
    });
  }


  function normalizeInterfaceScalePercent(value) {
    const number = Number(value);
    return Number.isFinite(number) ? Math.max(100, Math.min(150, Math.round(number))) : 100;
  }

  function interfaceScaleFactor() {
    return normalizeInterfaceScalePercent(state.interfaceScalePercent) / 100;
  }

  function updateInterfaceDensity(win, rect, factor, baseScale) {
    // Match the Lua behavior: the percentage enlarges widgets/fonts, while the
    // outer window keeps its own manually-resized rectangle. Responsive mode is
    // selected from the amount of authored-space that remains after that growth.
    const effectiveScale = Math.max(0.001, baseScale * factor);
    const logicalWidth = rect.width / effectiveScale;
    const logicalHeight = rect.height / effectiveScale;
    if (logicalWidth < 1180 || logicalHeight < 650) win.dataset.uiDensity = 'tiny';
    else if (logicalWidth < 1450 || logicalHeight < 780) win.dataset.uiDensity = 'compact';
    else if (logicalWidth >= 1750 && logicalHeight >= 980) win.dataset.uiDensity = 'large';
    else win.dataset.uiDensity = 'normal';
  }

  function applyInterfaceContentScale(win, rect, baseScale) {
    const layer = win?.querySelector('.window-scale-layer');
    if (!layer) return;
    const factor = interfaceScaleFactor();
    const effectiveScale = Math.max(0.56, Math.min(1.80, baseScale * factor));

    // Do not scale the whole page as a transformed bitmap. That shrinks the
    // layout viewport itself and makes grids/columns overlap. Instead the same
    // sizing variable used by the UI components is increased, so text, controls,
    // paddings and icons grow while CSS Grid/Flex still receive the full window
    // perimeter and can reflow into it.
    layer.style.width = '100%';
    layer.style.height = '100%';
    layer.style.transform = 'none';
    layer.style.transformOrigin = '0 0';
    win.style.setProperty('--interface-content-scale', factor.toFixed(4));
    win.style.setProperty('--ui-scale', effectiveScale.toFixed(3));
    const percent = normalizeInterfaceScalePercent(state.interfaceScalePercent);
    win.dataset.interfaceScale = String(percent);
    win.dataset.interfaceScaleLevel = percent >= 135 ? 'high' : percent > 100 ? 'scaled' : 'normal';
    updateInterfaceDensity(win, rect, factor, baseScale);
  }

  function updateVisualScale() {
    const win = document.querySelector('.window');
    if (!win || previewMode) return;
    const rect = win.getBoundingClientRect();

    // The perimeter scale and Settings -> Appearance scale are intentionally
    // separate. Manual resize changes baseScale. menu_scale_percent multiplies
    // only the inner controls/fonts, exactly like getMenuUiScale() in Lua.
    const raw = Math.min(rect.width / 1600, rect.height / 900);
    const baseScale = Math.max(0.56, Math.min(1.20, raw));
    applyInterfaceContentScale(win, rect, baseScale);
  }

  function notifyHostReady() {
    if (state.readyNotified) return;
    state.readyNotified = true;
    document.documentElement.classList.add('bridge-ready');
    try {
      window.parent.postMessage({channel: 'arzmarket-html', action: 'ready', token}, '*');
    } catch (_) {}
    try { window.focus(); } catch (_) {}
    try {
      document.body.tabIndex = -1;
      document.body.focus({preventScroll: true});
    } catch (_) {}
  }

  function createWindowManager() {
    if (previewMode) return null;
    const win = document.querySelector('.window');
    const topbar = document.querySelector('.topbar');
    if (!win || !topbar) return null;

    const EDGE = 12;
    const MIN_WIDTH = 760;
    const MIN_HEIGHT = 500;
    const SAFE_MARGIN = 12;
    let initialized = false;
    let remoteApplied = false;
    let operation = null;
    let saveTimer = 0;
    let restoreRect = null;
    let minimized = false;
    let maximized = false;

    const handles = {};
    for (const dir of ['n','ne','e','se','s','sw','w','nw']) {
      const handle = document.createElement('div');
      handle.className = `window-resize-handle resize-${dir}`;
      handle.dataset.resize = dir;
      if (dir === 'se') handle.dataset.baronAnchor = 'resize_handle';
      handle.setAttribute('aria-hidden', 'true');
      win.append(handle);
      handles[dir] = handle;
    }

    function viewportBounds() {
      return {width: Math.max(1, window.innerWidth), height: Math.max(1, window.innerHeight)};
    }

    function readRect() {
      const rect = win.getBoundingClientRect();
      return {x: rect.left, y: rect.top, width: rect.width, height: rect.height};
    }

    function sanitize(layout) {
      if (!layout) return null;
      const vp = viewportBounds();
      let width = Number(layout.width);
      let height = Number(layout.height);
      let x = Number(layout.x);
      let y = Number(layout.y);
      if (![width,height,x,y].every(Number.isFinite)) return null;
      const minW = Math.min(MIN_WIDTH, Math.max(560, vp.width - SAFE_MARGIN * 2));
      const minH = Math.min(MIN_HEIGHT, Math.max(380, vp.height - SAFE_MARGIN * 2));
      width = Math.max(minW, Math.min(width, vp.width - SAFE_MARGIN * 2));
      height = Math.max(minH, Math.min(height, vp.height - SAFE_MARGIN * 2));
      x = Math.max(SAFE_MARGIN, Math.min(x, vp.width - width - SAFE_MARGIN));
      y = Math.max(SAFE_MARGIN, Math.min(y, vp.height - height - SAFE_MARGIN));
      return {x, y, width, height};
    }

    function apply(layout) {
      const clean = sanitize(layout);
      if (!clean) return false;
      win.style.left = `${Math.round(clean.x)}px`;
      win.style.top = `${Math.round(clean.y)}px`;
      win.style.setProperty('width', `${Math.round(clean.width)}px`, 'important');
      win.style.setProperty('height', `${Math.round(clean.height)}px`, 'important');
      updateVisualScale();
      return true;
    }

    function initialize() {
      if (initialized) return;
      const vp = viewportBounds();
      const width = temporaryMode
        ? Math.min(1380, vp.width - SAFE_MARGIN * 2)
        : Math.min(1600, vp.width - SAFE_MARGIN * 2, Math.max(MIN_WIDTH, vp.width * 0.88));
      const height = temporaryMode
        ? Math.min(820, vp.height - SAFE_MARGIN * 2)
        : Math.min(900, vp.height - SAFE_MARGIN * 2, Math.max(MIN_HEIGHT, vp.height * 0.84));
      const defaultRect = {
        x: Math.max(SAFE_MARGIN, (vp.width - width) / 2),
        y: Math.max(SAFE_MARGIN, (vp.height - height) / 2),
        width,
        height
      };
      document.documentElement.classList.add('window-management-enabled');
      refs.app.classList.add('window-management-enabled');
      apply(defaultRect);
      initialized = true;
    }

    function scheduleSave() {
      if (temporaryMode) return;
      clearTimeout(saveTimer);
      saveTimer = window.setTimeout(() => {
        const rect = sanitize(readRect());
        if (!rect) return;
        action('ui.window.save', Object.assign({}, rect, {
          viewportWidth: window.innerWidth,
          viewportHeight: window.innerHeight,
          minimalMode: state.minimalMode === true
        })).catch(() => {});
      }, 120);
    }

    function finishOperation() {
      if (!operation) return;
      const finished = operation;
      operation = null;
      document.documentElement.classList.remove('window-is-moving');
      document.documentElement.classList.remove('window-is-resizing');
      scheduleSave();
      if (finished.type === 'resize' && baronAssistantUi) baronAssistantUi.resized();
    }

    function beginDrag(event) {
      if (event.button !== 0) return;
      if (event.target.closest('button,input,select,textarea,a,.topbar-actions')) return;
      initialize();
      const rect = readRect();
      operation = {
        type: 'drag',
        startX: event.clientX,
        startY: event.clientY,
        startRect: rect
      };
      event.preventDefault();
      document.documentElement.classList.add('window-is-moving');
    }

    function beginResize(event, direction) {
      if (event.button !== 0) return;
      initialize();
      if (maximized) {
        maximized = false;
        win.classList.remove('window-maximized');
      }
      operation = {
        type: 'resize',
        direction,
        startX: event.clientX,
        startY: event.clientY,
        startRect: readRect()
      };
      event.preventDefault();
      event.stopPropagation();
      document.documentElement.classList.add('window-is-moving');
      document.documentElement.classList.add('window-is-resizing');
    }

    function onMouseMove(event) {
      if (!operation) return;
      if ((event.buttons & 1) === 0) {
        finishOperation();
        return;
      }
      const dx = event.clientX - operation.startX;
      const dy = event.clientY - operation.startY;
      const start = operation.startRect;
      const vp = viewportBounds();
      const minW = Math.min(MIN_WIDTH, Math.max(560, vp.width - SAFE_MARGIN * 2));
      const minH = Math.min(MIN_HEIGHT, Math.max(380, vp.height - SAFE_MARGIN * 2));

      if (operation.type === 'drag') {
        apply({
          x: start.x + dx,
          y: start.y + dy,
          width: start.width,
          height: start.height
        });
        return;
      }

      const dir = operation.direction;
      let left = start.x;
      let top = start.y;
      let right = start.x + start.width;
      let bottom = start.y + start.height;

      if (dir.includes('e')) right = Math.min(vp.width - SAFE_MARGIN, right + dx);
      if (dir.includes('s')) bottom = Math.min(vp.height - SAFE_MARGIN, bottom + dy);
      if (dir.includes('w')) left = Math.max(SAFE_MARGIN, left + dx);
      if (dir.includes('n')) top = Math.max(SAFE_MARGIN, top + dy);

      if (right - left < minW) {
        if (dir.includes('w')) left = right - minW;
        else right = left + minW;
      }
      if (bottom - top < minH) {
        if (dir.includes('n')) top = bottom - minH;
        else bottom = top + minH;
      }

      apply({x: left, y: top, width: right - left, height: bottom - top});
    }

    function toggleMaximize() {
      initialize();
      const vp = viewportBounds();
      if (!maximized) {
        restoreRect = sanitize(readRect());
        minimized = false;
        win.classList.remove('window-minimized');
        apply({x: SAFE_MARGIN, y: SAFE_MARGIN, width: vp.width - SAFE_MARGIN * 2, height: vp.height - SAFE_MARGIN * 2});
        maximized = true;
        win.classList.add('window-maximized');
      } else {
        if (restoreRect) apply(restoreRect);
        maximized = false;
        win.classList.remove('window-maximized');
      }
      scheduleSave();
    }

    function toggleMinimize() {
      initialize();
      if (!minimized) {
        restoreRect = sanitize(readRect());
        minimized = true;
        maximized = false;
        win.classList.remove('window-maximized');
        win.classList.add('window-minimized');
        const topbarHeight = Math.max(48, topbar.getBoundingClientRect().height);
        win.style.setProperty('height', `${Math.round(topbarHeight)}px`, 'important');
      } else {
        minimized = false;
        win.classList.remove('window-minimized');
        if (restoreRect) apply(restoreRect);
      }
    }

    // Arizona CEF is more reliable with classic mouse events than with
    // Pointer Capture. Pointer capture can silently fail inside the in-game CEF,
    // leaving the resize grip visible but non-functional.
    topbar.addEventListener('mousedown', beginDrag);
    topbar.addEventListener('dblclick', event => {
      if (event.target.closest('button,input,select,textarea,a,.topbar-actions')) return;
      event.preventDefault();
      toggleMaximize();
    });
    window.addEventListener('mousemove', onMouseMove, true);
    window.addEventListener('mouseup', finishOperation, true);
    window.addEventListener('blur', finishOperation);

    for (const [dir, handle] of Object.entries(handles)) {
      handle.addEventListener('mousedown', event => beginResize(event, dir));
    }

    window.addEventListener('resize', () => {
      if (!initialized) return;
      apply(readRect());
      updateVisualScale();
      scheduleSave();
    });

    initialize();
    updateVisualScale();
    if (typeof ResizeObserver === 'function') {
      const observer = new ResizeObserver(() => window.requestAnimationFrame(updateVisualScale));
      observer.observe(win);
    }

    return {
      applyRemote(layout) {
        if (temporaryMode) return;
        if (remoteApplied) return;
        remoteApplied = true;
        if (!layout || Number(layout.version) !== 16 || !(Number(layout.width) > 0) || !(Number(layout.height) > 0)) return;

        const vp = viewportBounds();
        const savedVpW = Number(layout.viewportWidth);
        const savedVpH = Number(layout.viewportHeight);
        // v64 temporarily stored a second "base" rectangle and enlarged the
        // OUTER window for menu_scale_percent. Restore that base rectangle once
        // so users do not keep the accidental perimeter enlargement after update.
        const hasV64Base = Number(layout.scalePercent) > 100
          && [layout.baseX, layout.baseY, layout.baseWidth, layout.baseHeight]
            .every(value => Number.isFinite(Number(value)));
        let adapted = hasV64Base ? {
          x: Number(layout.baseX),
          y: Number(layout.baseY),
          width: Number(layout.baseWidth),
          height: Number(layout.baseHeight)
        } : {
          x: Number(layout.x),
          y: Number(layout.y),
          width: Number(layout.width),
          height: Number(layout.height)
        };

        // If the same config is used on another monitor/resolution, preserve the
        // window's proportional size and position instead of replaying stale pixels.
        if (savedVpW > 0 && savedVpH > 0 && (Math.abs(savedVpW - vp.width) > 2 || Math.abs(savedVpH - vp.height) > 2)) {
          const sx = vp.width / savedVpW;
          const sy = vp.height / savedVpH;
          adapted = {
            x: adapted.x * sx,
            y: adapted.y * sy,
            width: adapted.width * sx,
            height: adapted.height * sy
          };
        }
        apply(adapted);
        if (hasV64Base) scheduleSave();
      },
      getLayout() { return sanitize(readRect()); },
      toggleMaximize,
      toggleMinimize
    };
  }

  const windowManager = createWindowManager();
  if (!previewMode && window.ArzBaronAssistantUI?.create) {
    baronAssistantUi = window.ArzBaronAssistantUI.create({
      action,
      refresh: force => refresh(force === true, state.page),
      openPage: async page => {
        if (!page) return;
        if (page === state.page) {
          await baronAssistantUi?.event('page', {page});
          return;
        }
        await switchPage(page);
      },
      openFilter: async () => {
        setTradeFilterOpen(true);
        await baronAssistantUi?.event('filter_opened', {side: state.page});
      },
      ensureFilterOpen: () => {
        setTradeFilterOpen(true);
      },
      openSettingsSection: async (section, notify = true) => {
        const requested = String(section || 'general');
        if (!['general','trade','automation','telegram','appearance','configs'].includes(requested)) return false;
        if (state.page !== 'settings') await switchPage('settings');
        if (state.settings.section !== requested) {
          state.settings.section = requested;
          renderSettings();
        }
        if (notify) await baronAssistantUi?.event('settings_section_changed', {section: requested});
        return true;
      }
    });
  }

  function hideAveragePriceTooltipNow() {
    clearTimeout(state.averagePrices.hoverTimer);
    clearTimeout(state.averagePrices.hideTimer);
    state.averagePrices.activeKey = null;
    const tooltip = state.averagePrices.tooltip;
    if (tooltip) tooltip.classList.add('hidden');
  }

  function updateMinimalModeUi() {
    const enabled = state.minimalMode === true;
    refs.app?.classList.toggle('minimal-mode', enabled);
    if (refs.app) refs.app.dataset.minimal = enabled ? 'true' : 'false';
    if (refs.minimalModeButton) {
      refs.minimalModeButton.classList.toggle('active', enabled);
      refs.minimalModeButton.setAttribute('aria-pressed', enabled ? 'true' : 'false');
      refs.minimalModeButton.title = enabled
        ? 'Минимализм включен'
        : 'Показывать только необходимое для текущего раздела';
    }
    if (refs.minimalModeFullButton) {
      refs.minimalModeFullButton.classList.toggle('active', !enabled);
      refs.minimalModeFullButton.setAttribute('aria-pressed', enabled ? 'false' : 'true');
      refs.minimalModeFullButton.title = enabled
        ? 'Вернуть полный HTML-интерфейс'
        : 'Полный HTML-интерфейс включен';
    }
    if (enabled) {
      hideAveragePriceTooltipNow();
      if (state.page === 'storage') state.storage.tab = 'distribution';
      if (secondaryActions) secondaryActions.open = false;
    }
  }

  function setMinimalMode(enabled, rerender = true) {
    state.minimalModeHydrated = true;
    state.minimalMode = enabled === true;
    updateMinimalModeUi();
    if (rerender && state.data) render();
  }

  async function persistMinimalMode() {
    const rect = windowManager?.getLayout();
    if (!rect) return false;
    await action('ui.window.save', Object.assign({}, rect, {
      viewportWidth: window.innerWidth,
      viewportHeight: window.innerHeight,
      minimalMode: state.minimalMode === true
    }));
    return true;
  }

  function hostFrameAction(actionName) {
    try {
      window.parent.postMessage({channel: 'arzmarket-html', action: actionName, token}, '*');
    } catch (_) {}
  }

  function detachHostFrame() { hostFrameAction('detach'); }
  function hideHostFrame() { hostFrameAction('hide'); }
  function showHostFrame() { hostFrameAction('show'); }

  let closeRequested = false;
  function closeHtmlInterface() {
    if (closeRequested) return;
    closeRequested = true;

    // Give Lua enough time to receive ui.close and release the SA-MP/CEF cursor.
    // Detaching the iframe immediately can abort the local HTTP request in some
    // Arizona CEF builds and leaves the mouse captured in the middle of screen.
    action('ui.close', {page: state.page, side: state.page === 'sell' ? 'sell' : state.page === 'buy' ? 'buy' : undefined})
      .catch(() => {})
      .finally(() => window.setTimeout(detachHostFrame, 20));

    // Fallback only. Normally Lua removes the iframe itself after handling ui.close.
    window.setTimeout(detachHostFrame, 350);
    window.setTimeout(() => { closeRequested = false; }, 650);
  }

  const keyOf = item => item?.identity
    ? [item.identity.index, item.identity.name, item.identity.slot_id ?? '', item.identity.item_id ?? ''].join('|')
    : '';

  const tradeActive = () => state.data?.common?.automation === true;
  const tradeBusy = () => state.data?.common?.tradeBusy === true;

  function syncSelected() {
    // Trade selection belongs only to buy/sell. Logs and Storage keep their
    // own selection state and may receive an empty Lua table encoded as {}.
    if (state.page === 'settings' || state.page === 'logs' || state.page === 'marketplace' || state.page === 'mods' || state.page === 'storage') {
      state.selectedItem = null;
      state.selectedKey = null;
      return;
    }
    const rawItems = state.data?.data?.items;
    const items = Array.isArray(rawItems) ? rawItems : [];
    let item = items.find(x => keyOf(x) === state.selectedKey);
    if (!item && state.selectedItem) item = items.find(x => x.name === state.selectedItem.name);
    // Reference behavior: when a config has items, the first row is selected
    // immediately so the right-side editor is useful without an extra click.
    if (!item && items.length) item = items[0];
    state.selectedItem = item || null;
    state.selectedKey = item ? keyOf(item) : null;
  }

  function revealHydratedInterface() {
    if (!refs.app || refs.app.dataset.hydrated === '1') return;
    refs.app.dataset.hydrated = '1';
    refs.app.style.opacity = '';
    refs.app.style.visibility = '';
    refs.app.style.pointerEvents = '';
    document.documentElement.classList.add('arzmarket-hydrated');
  }

  function rememberPageState(page, result) {
    if (!page || !result || result.unchanged) return;
    state.pageCache[page] = result;
    state.pageRevision[page] = Number(result.revision || 0);
  }

  function applyPageState(page, result, force = false) {
    if (!result || result.unchanged) return;
    rememberPageState(page, result);
    if (state.page !== page) return;
    state.data = result;
    state.revision = state.pageRevision[page] || 0;
    const selectedTheme = result?.common?.htmlThemeKey || result?.data?.appearance?.palette_key;
    const selectedThemeProfile = result?.common?.htmlThemeProfile || result?.data?.appearance?.global_palette || null;
    if (selectedThemeProfile?.enabled === true) applyHtmlTheme('global_palette', selectedThemeProfile);
    else if (selectedTheme) applyHtmlTheme(selectedTheme, selectedThemeProfile);
    state.interfaceScalePercent = normalizeInterfaceScalePercent(result?.common?.menuScalePercent ?? state.interfaceScalePercent);
    if (!state.minimalModeHydrated) {
      state.minimalModeHydrated = true;
      state.minimalMode = result?.common?.htmlWindow?.minimalMode === true;
      updateMinimalModeUi();
    }
    if (windowManager) windowManager.applyRemote(result?.common?.htmlWindow);
    updateVisualScale();
    syncSelected();
    if (baronAssistantUi) baronAssistantUi.render(result?.assistant || {active:false});
    try {
      render();
    } catch (renderError) {
      console.error('[ArzMarket HTML] render failed:', renderError);
      refs.runtimeText.textContent = 'Ошибка интерфейса';
      if (force) showToast(`UI: ${renderError?.message || renderError}`, 'error');
      window.requestAnimationFrame(() => window.requestAnimationFrame(notifyHostReady));
      return;
    }
    refs.runtimeText.textContent = 'Система готова';
    revealHydratedInterface();
    window.requestAnimationFrame(() => window.requestAnimationFrame(notifyHostReady));
  }

  async function refresh(force = false, requestedPage = state.page) {
    const page = ['buy','sell','settings','logs','marketplace','mods','storage'].includes(requestedPage) ? requestedPage : state.page;
    if (!force && page === 'settings' && state.settings.paletteDragging === true) return {unchanged:true};
    const active = state.pageRequests[page];
    if (active) {
      if (!force) return active;
      try { await active; } catch (_) {}
    }

    const task = (async () => {
      try {
        const since = force ? 0 : Number(state.pageRevision[page] || 0);
        const result = await api(`/api/state?page=${encodeURIComponent(page)}&since=${since}`, page === 'marketplace' ? {timeoutMs: 15000} : {});
        if (!result.unchanged) applyPageState(page, result, force);
        else if (state.page === page) {
          refs.runtimeText.textContent = 'Система готова';
          if (state.pageCache[page]) revealHydratedInterface();
          window.requestAnimationFrame(() => window.requestAnimationFrame(notifyHostReady));
        }
        return result;
      } catch (err) {
        if (state.page === page) {
          refs.runtimeText.textContent = 'Нет связи с Lua';
          if (force) showToast(`Bridge: ${err.message}`, 'error');
        }
        throw err;
      } finally {
        if (state.pageRequests[page] === task) delete state.pageRequests[page];
      }
    })();

    state.pageRequests[page] = task;
    return task;
  }

  function div(value, className = '') {
    const node = document.createElement('div');
    if (className) node.className = className;
    node.textContent = text(value);
    return node;
  }

  function isBaronSellFilterTutorialStep() {
    return /^sell_filter_[1-5]$/.test(String(refs.app?.dataset?.baronStep || ''));
  }

  function setTradeFilterOpen(open) {
    if (!refs.tradeFilterPanel || !refs.tradeFilterButton) return;
    // While Baron explains the filter panel, keep the panel visible.
    // Clicking Baron's Skip button happens outside the panel and used to close it.
    if (!open && isBaronSellFilterTutorialStep()) open = true;
    refs.tradeFilterPanel.classList.toggle('hidden', !open);
    refs.tradeFilterButton.classList.toggle('active', open);
    refs.tradeFilterButton.setAttribute('aria-expanded', open ? 'true' : 'false');
    if (open) {
      const x = refs.tradeFilterButton.offsetLeft;
      const y = refs.tradeFilterButton.offsetTop + refs.tradeFilterButton.offsetHeight + 7;
      refs.tradeFilterPanel.style.left = `${Math.max(0, x)}px`;
      refs.tradeFilterPanel.style.top = `${Math.max(0, y)}px`;
      renderTradeFilterPanel();
    }
  }

  function applyLocalCategoryOrder(order) {
    if (!state.data?.common) return;
    const current = categoryFilters();
    const byId = new Map(current.map(row => [String(row.id), row]));
    const normalized = [];
    for (const id of order) {
      const row = byId.get(String(id));
      if (row && !normalized.some(x => x.id === String(id))) {
        normalized.push({id: String(id), label: text(row.label), order: normalized.length + 1});
      }
    }
    for (const row of current) {
      const id = String(row.id);
      if (!normalized.some(x => x.id === id)) normalized.push({id, label: text(row.label), order: normalized.length + 1});
    }
    state.data.common.itemCategories = normalized;
  }

  async function saveCategoryOrder(order) {
    const previous = categoryOrderIds();
    applyLocalCategoryOrder(order);
    renderTradeFilterPanel();
    if (state.page === 'sell') renderSellItems(); else renderTable();
    try {
      await action('trade.filter.category_order', {side: state.page, order});
      await refresh(true);
    } catch (err) {
      applyLocalCategoryOrder(previous);
      renderTradeFilterPanel();
      if (state.page === 'sell') renderSellItems(); else renderTable();
      showToast(`Фильтр: ${err.message}`, 'error');
    }
  }

  function scrollToCategory(id) {
    const scroller = state.page === 'sell' ? refs.sellSaleRows : refs.tableRows;
    const wanted = String(id || '');
    if (!scroller || !wanted) return;
    const node = Array.from(scroller.querySelectorAll('.category-group-header')).find(row => row.dataset.category === wanted);
    if (!node) return;

    // Do not use scrollIntoView here. In the older Chromium used by Arizona CEF,
    // smooth scroll + sticky category headers can reliably move down but fail
    // when jumping back to a category located above the current scroll position.
    // Compute the category's real position inside the table scroller and assign
    // scrollTop directly so jumps work in both directions.
    let top = 0;
    let found = false;
    for (const child of Array.from(scroller.children)) {
      if (child === node) {
        found = true;
        break;
      }
      top += Number(child.offsetHeight) || 0;
    }
    if (!found) {
      const nodeRect = node.getBoundingClientRect();
      const scrollerRect = scroller.getBoundingClientRect();
      top = scroller.scrollTop + (nodeRect.top - scrollerRect.top);
    }
    const maxTop = Math.max(0, scroller.scrollHeight - scroller.clientHeight);
    const targetTop = Math.max(0, Math.min(maxTop, Math.round(top)));
    scroller.scrollTop = targetTop;
    // One extra assignment on the next frame neutralizes a pending old smooth
    // scroll animation in CEF if the user clicks another category immediately.
    requestAnimationFrame(() => {
      scroller.scrollTop = targetTop;
    });
  }

  function renderTradeFilterPanel() {
    if (!refs.tradeFilterCategories) return;
    const rows = categoryFilters();
    refs.tradeFilterCategories.innerHTML = '';
    const fragment = document.createDocumentFragment();

    const cleanupGlobalDragClasses = () => {
      document.documentElement.classList.remove('trade-filter-drag-active');
      document.body.classList.remove('trade-filter-drag-active');
      refs.tradeFilterCategories?.querySelectorAll('.reordering,.reorder-target').forEach(node => {
        node.classList.remove('reordering', 'reorder-target');
      });
    };

    rows.forEach((row, index) => {
      const id = String(row.id);
      const item = document.createElement('div');
      item.className = 'trade-filter-category';
      item.dataset.category = id;
      item.draggable = false;

      const drag = document.createElement('span');
      drag.className = 'trade-filter-drag';
      drag.textContent = '⋮⋮';
      drag.title = 'Зажмите и перемещайте вверх или вниз';

      const number = document.createElement('span');
      number.className = 'trade-filter-number';
      number.textContent = `${index + 1}.`;

      // Deliberately use a span instead of a button here. In Arizona CEF a native
      // button can enter its pressed/selection state and steal the mouse sequence
      // before our reorder code sees mousemove. Lua treats the whole row as one
      // draggable hit area, so HTML does the same.
      const label = document.createElement('span');
      label.className = 'trade-filter-label';
      label.textContent = text(row.label);
      label.title = 'Клик: перейти к группе. Зажать: изменить порядок.';

      item.append(drag, number, label);

      // Mirror the Lua filter interaction:
      // 1. press a category -> start holding it;
      // 2. while LMB is held, crossing another row moves the category there;
      // 3. release without moving -> jump to that category in the item list;
      // 4. release after moving -> persist the new category order.
      item.addEventListener('mousedown', event => {
        if (tradeBusy() || event.button !== 0) return;

        const container = refs.tradeFilterCategories;
        if (!container) return;

        event.preventDefault();
        event.stopPropagation();
        try { window.getSelection?.()?.removeAllRanges?.(); } catch (_) {}

        const initialOrder = Array.from(container.querySelectorAll('.trade-filter-category'))
          .map(node => String(node.dataset.category || ''));
        const startX = event.clientX;
        const startY = event.clientY;
        let finished = false;

        item.classList.add('reordering');
        drag.classList.add('grabbing');
        document.documentElement.classList.add('trade-filter-drag-active');
        document.body.classList.add('trade-filter-drag-active');

        const renumber = () => {
          Array.from(container.querySelectorAll('.trade-filter-category')).forEach((node, rowIndex) => {
            const numberNode = node.querySelector('.trade-filter-number');
            if (numberNode) numberNode.textContent = `${rowIndex + 1}.`;
          });
        };

        let dragStarted = false;
        let orderChanged = false;

        const onMove = moveEvent => {
          if (finished) return;
          moveEvent.preventDefault();
          moveEvent.stopPropagation();

          const dx = Number(moveEvent.clientX || 0) - startX;
          const dy = Number(moveEvent.clientY || 0) - startY;
          if (!dragStarted) {
            if ((dx * dx) + (dy * dy) < 9) return;
            dragStarted = true;
          }

          const panelRect = container.getBoundingClientRect();
          const scale = Number.parseFloat(getComputedStyle(document.querySelector('.window')).getPropertyValue('--ui-scale')) || 1;
          const edge = Math.max(22, 30 * scale);
          if (moveEvent.clientY < panelRect.top + edge) container.scrollTop -= Math.max(8, 12 * scale);
          else if (moveEvent.clientY > panelRect.bottom - edge) container.scrollTop += Math.max(8, 12 * scale);

          // Do not depend on MouseEvent.buttons or elementFromPoint here.
          // Arizona CEF can report buttons=0 while LMB is still held, and the
          // Baron overlay can become the top element under the cursor. Instead,
          // calculate the insertion point only from row geometry.
          const siblings = Array.from(container.querySelectorAll('.trade-filter-category'))
            .filter(node => node !== item);
          let before = null;
          for (const node of siblings) {
            const rect = node.getBoundingClientRect();
            if (moveEvent.clientY < rect.top + rect.height / 2) {
              before = node;
              break;
            }
          }

          const currentChildren = Array.from(container.querySelectorAll('.trade-filter-category'));
          const oldIndex = currentChildren.indexOf(item);
          container.insertBefore(item, before);
          const nextChildren = Array.from(container.querySelectorAll('.trade-filter-category'));
          const newIndex = nextChildren.indexOf(item);
          if (oldIndex !== newIndex) {
            orderChanged = true;
            renumber();
          }
        };

        const cleanup = () => {
          document.removeEventListener('mousemove', onMove, true);
          document.removeEventListener('mouseup', finish, true);
          window.removeEventListener('blur', cancel, true);
          drag.classList.remove('grabbing');
          cleanupGlobalDragClasses();
        };

        const finish = async finishEvent => {
          if (finished) return;
          finished = true;
          finishEvent?.preventDefault?.();
          finishEvent?.stopPropagation?.();
          cleanup();

          if (!dragStarted) {
            scrollToCategory(id);
            return;
          }

          const nextOrder = Array.from(container.querySelectorAll('.trade-filter-category'))
            .map(node => String(node.dataset.category || ''));
          if (!orderChanged || nextOrder.join('|') === initialOrder.join('|')) {
            renderTradeFilterPanel();
            return;
          }
          await saveCategoryOrder(nextOrder);
        };

        const cancel = () => {
          if (finished) return;
          finished = true;
          cleanup();
          applyLocalCategoryOrder(initialOrder);
          renderTradeFilterPanel();
          if (state.page === 'sell') renderSellItems(); else renderTable();
        };

        document.addEventListener('mousemove', onMove, true);
        document.addEventListener('mouseup', finish, true);
        window.addEventListener('blur', cancel, true);
      });

      fragment.append(item);
    });
    refs.tradeFilterCategories.append(fragment);
  }

  let buySearchBlurTimer = 0;

  function configItemByName(name) {
    const wanted = catalogName(name);
    return asArray(state.data?.data?.items).find(item => catalogName(item.name) === wanted) || null;
  }

  function closeBuySearchAfterPick() {
    window.clearTimeout(buySearchBlurTimer);
    buySearchBlurTimer = 0;
    state.search = '';
    refs.searchInput.value = '';
    state.searchFocused = false;
    refs.globalSearchResults.classList.add('hidden');
    refs.globalSearchResults.innerHTML = '';
    if (document.activeElement === refs.searchInput) refs.searchInput.blur();
  }

  function renderGlobalSearchResults() {
    if (!refs.globalSearchResults) return;
    const source = asArray(state.data?.data?.source);
    const query = normalizeName(state.search);
    if (!state.searchFocused || !source.length) {
      refs.globalSearchResults.classList.add('hidden');
      refs.globalSearchResults.innerHTML = '';
      return;
    }
    const matches = source
      .filter(item => !query || normalizeName(item.name).includes(query))
      .slice(0, 120);
    refs.globalSearchResults.innerHTML = '';
    if (!matches.length) {
      const empty = div('Ничего не найдено', 'global-search-empty');
      refs.globalSearchResults.append(empty);
      refs.globalSearchResults.classList.remove('hidden');
      return;
    }
    const fragment = document.createDocumentFragment();
    for (const item of matches) {
      const configured = configItemByName(item.name);
      const row = document.createElement('button');
      row.type = 'button';
      row.className = `global-search-row ${configured ? 'configured' : 'missing'}`;
      const left = div('', 'global-search-item');
      const box = div('', 'global-search-thumb');
      const img = document.createElement('img');
      img.alt = '';
      setIcon(img, item, 48);
      box.append(img);
      const copy = div('', 'global-search-copy');
      copy.append(div(item.name, 'global-search-name'), div(categoryLabel(item.category), 'global-search-meta'));
      left.append(box, copy);
      row.append(left);
      if (!configured) {
        const missing = div('×', 'global-search-missing');
        missing.title = 'Предмет не добавлен в текущий конфиг';
        row.append(missing);
      }
      row.addEventListener('mousedown', event => event.preventDefault());
      row.addEventListener('click', async () => {
        if (configured) {
          state.selectedItem = configured;
          state.selectedKey = keyOf(configured);
          closeBuySearchAfterPick();
          renderTable();
          renderDetails();
          requestAnimationFrame(() => document.querySelector('.trade-row.selected')?.scrollIntoView({block:'nearest'}));
        } else if (state.page === 'buy') {
          closeBuySearchAfterPick();
          try {
            await action('trade.item.add', {side: 'buy', source_index: item.index});
            showToast('Товар добавлен в скупку', 'success');
            await refresh(true);
            const added = configItemByName(item.name);
            if (added) {
              state.selectedItem = added;
              state.selectedKey = keyOf(added);
              renderTable();
              renderDetails();
              requestAnimationFrame(() => document.querySelector('.trade-row.selected')?.scrollIntoView({block:'nearest'}));
            }
          } catch (err) {
            showToast(`Не удалось добавить: ${err.message}`, 'error');
          }
        } else {
          state.searchFocused = false;
          refs.globalSearchResults.classList.add('hidden');
          openPicker(item.name);
        }
      });
      fragment.append(row);
    }
    refs.globalSearchResults.append(fragment);
    refs.globalSearchResults.classList.remove('hidden');
  }

  function cycleSort(key) {
    if (state.sortKey !== key) {
      state.sortKey = key;
      state.sortDirection = -1; // first click: high -> low / Z -> A
    } else if (state.sortDirection === -1) {
      state.sortDirection = 1;  // second click: low -> high / A -> Z
    } else {
      state.sortKey = null;     // third click: original config order
      state.sortDirection = 0;
    }
    if (state.page === 'sell') renderSellItems();
    else renderTable();
  }

  const smoothScrollStates = new WeakMap();

  function installWheelScroller(node) {
    if (!node || node.dataset.wheelScrollBound === '1') return;
    node.dataset.wheelScrollBound = '1';

    const scrollState = {target: node.scrollTop, raf: 0, lastTime: 0, internal: false};
    smoothScrollStates.set(node, scrollState);

    const clampTarget = value => Math.max(0, Math.min(Math.max(0, node.scrollHeight - node.clientHeight), value));
    const stopAnimation = () => {
      if (scrollState.raf) cancelAnimationFrame(scrollState.raf);
      scrollState.raf = 0;
      scrollState.lastTime = 0;
      scrollState.target = clampTarget(node.scrollTop);
    };

    const step = now => {
      if (!node.isConnected) return stopAnimation();
      const max = Math.max(0, node.scrollHeight - node.clientHeight);
      scrollState.target = Math.max(0, Math.min(max, scrollState.target));
      const current = node.scrollTop;
      const diff = scrollState.target - current;
      if (Math.abs(diff) < 0.45) {
        scrollState.internal = true;
        node.scrollTop = scrollState.target;
        scrollState.internal = false;
        scrollState.raf = 0;
        scrollState.lastTime = 0;
        return;
      }

      const dt = Math.min(48, Math.max(1, scrollState.lastTime ? now - scrollState.lastTime : 16.67));
      scrollState.lastTime = now;
      // Time-based exponential interpolation. It feels the same at 60/120/144 Hz
      // and automatically uses every frame Arizona CEF can actually render.
      const alpha = 1 - Math.exp(-dt / 72);
      const next = current + diff * alpha;
      scrollState.internal = true;
      node.scrollTop = next;
      scrollState.internal = false;
      scrollState.raf = requestAnimationFrame(step);
    };

    node.addEventListener('wheel', event => {
      if (!event.deltaY) return;
      const max = Math.max(0, node.scrollHeight - node.clientHeight);
      if (max <= 0) return;
      const unit = event.deltaMode === 1 ? 34 : event.deltaMode === 2 ? Math.max(120, node.clientHeight * 0.86) : 1;
      const delta = event.deltaY * unit;
      const base = Math.abs(scrollState.target - node.scrollTop) < 1 ? node.scrollTop : scrollState.target;
      const target = Math.max(0, Math.min(max, base + delta));
      if (Math.abs(target - node.scrollTop) < 0.25 && Math.abs(scrollState.target - node.scrollTop) < 0.25) return;
      scrollState.target = target;
      event.preventDefault();
      event.stopPropagation();
      if (!scrollState.raf) {
        scrollState.lastTime = 0;
        scrollState.raf = requestAnimationFrame(step);
      }
    }, {passive:false, capture:true});

    // If the user drags the native scrollbar or code performs a direct jump,
    // continue from that position instead of pulling the list back.
    node.addEventListener('scroll', () => {
      if (scrollState.internal || scrollState.raf) return;
      scrollState.target = clampTarget(node.scrollTop);
    }, {passive:true});
    node.addEventListener('pointerdown', () => {
      // A direct mouse interaction should immediately take control from inertia.
      stopAnimation();
    }, {passive:true});
  }

  async function loadConfigByName(name) {
    name = String(name || '');
    if (!name || tradeBusy()) return;
    refs.configSelect.disabled = true;
    refs.configSelectButton.disabled = true;
    try {
      await action('trade.config.load', {side: state.page, name});
      state.selectedItem = null;
      state.selectedKey = null;
      showToast(`Конфиг «${name.replace(/\.json$/i, '')}» загружен`, 'success');
      await refresh(true);
    } catch (err) {
      showToast(`Конфиг: ${err.message}`, 'error');
      await refresh(true);
    }
  }

  function openConfigDropdown(anchor = refs.configSelectButton) {
    const activeConfig = state.data?.common?.activeConfig || '';
    const configs = Array.isArray(state.data?.common?.configs) ? state.data.common.configs : [];
    const options = configs.map(name => ({value:name, label:String(name).replace(/\.json$/i, '')}));
    const activeBase = String(activeConfig).replace(/\.json$/i, '');
    const currentValue = configs.find(name => String(name).replace(/\.json$/i, '') === activeBase) || activeConfig;
    openPopupSelect(anchor, options, currentValue, loadConfigByName, 'config');
  }

  refs.configSelectButton.addEventListener('click', event => {
    event.preventDefault();
    event.stopPropagation();
    openConfigDropdown(refs.configSelectButton);
  });

  function renderHeader() {
    const settings = state.page === 'settings';
    const logs = state.page === 'logs';
    const storage = state.page === 'storage';
    const marketplace = state.page === 'marketplace';
    const mods = state.page === 'mods';
    const buy = state.page === 'buy';
    const active = !settings && !logs && !storage && !marketplace && !mods && tradeActive();
    const busy = !settings && !logs && !storage && !marketplace && !mods && tradeBusy();
    refs.app.dataset.page = state.page;

    refs.pageTitle.textContent = settings ? 'Настройки' : marketplace ? 'Маркетплейс' : mods ? 'Модификации' : storage ? 'Хранилище' : logs ? 'Логи' : buy ? 'Скупка' : 'Продажа';
    refs.pageSubtitle.textContent = settings ? 'Управление поведением, автоматизацией и оформлением ArzMarket' : marketplace ? 'Поиск лавок и товаров по серверам Arizona RP' : mods ? '' : storage ? 'Единый поиск предметов во всех хранилищах Arizona RP' : logs
      ? 'Журнал событий и история работы ArzMarket'
      : buy ? 'Автоматический выкуп товаров с Arizona RP' : 'Автоматическая продажа товаров с Arizona RP';
    if (toolbar) toolbar.title = buy ? 'ПКМ: дополнительные действия' : '';
    const secondarySummary = secondaryActions?.querySelector('summary');
    if (secondarySummary) secondarySummary.textContent = state.minimalMode && buy ? 'Действия' : 'Доп. действия';
    if ((!buy || settings || logs || storage || marketplace || mods) && secondaryActions) secondaryActions.open = false;
    refs.pageHeaderIcon.innerHTML = iconSvg(settings ? 'settings' : marketplace ? 'market' : mods ? 'mods' : storage ? 'storage' : logs ? 'logs' : buy ? 'buy' : 'sell');

    document.querySelectorAll('.nav-item[data-page]').forEach(node => node.classList.toggle('active', node.dataset.page === state.page));
    document.querySelectorAll('.nav-item').forEach(node => {
      const icon = node.querySelector('.nav-icon');
      if (!icon || icon.dataset.svgReady === '1') return;
      const label = normalizeName(node.textContent);
      const key = node.dataset.page === 'buy' ? 'buy' : node.dataset.page === 'sell' ? 'sell' : node.dataset.page === 'logs' ? 'logs' : node.dataset.page === 'mods' ? 'mods' : label.includes('настрой') ? 'settings' : label.includes('лог') ? 'logs' : label.includes('маркет') ? 'market' : 'storage';
      icon.innerHTML = iconSvg(key);
      icon.dataset.svgReady = '1';
    });

    if (refs.pageHeaderHint) {
      const hints = settings ? ['Гибкая настройка', 'Один интерфейс', 'Arizona RP'] : marketplace ? ['Все лавки', 'в одном месте', 'Arizona RP'] : mods ? ['', '', ''] : storage ? ['Все ваши предметы', 'в одном месте', 'Arizona RP'] : logs
        ? ['Прозрачность', 'Контроль', 'Arizona RP']
        : buy ? ['Выгодные закупки', 'Стабильная прибыль', 'Arizona RP'] : ['Выгодные сделки', 'Стабильный доход', 'Arizona RP'];
      [...refs.pageHeaderHint.children].forEach((node, index) => { node.textContent = hints[index] || ''; });
    }

    if (settings) {
      refs.logsHeaderMeta?.classList.add('hidden');
      refs.storageHeaderMeta?.classList.add('hidden');
      refs.marketplaceHeaderMeta?.classList.add('hidden');
      refs.modsHeaderMeta?.classList.add('hidden');
      refs.settingsHeaderMeta?.classList.remove('hidden');
      if (refs.tradeHeaderMeta) refs.tradeHeaderMeta.classList.add('hidden');
      return;
    }
    refs.settingsHeaderMeta?.classList.add('hidden');
    if (mods) {
      refs.logsHeaderMeta?.classList.add('hidden');
      refs.storageHeaderMeta?.classList.add('hidden');
      refs.marketplaceHeaderMeta?.classList.add('hidden');
      refs.modsHeaderMeta?.classList.remove('hidden');
      if (refs.tradeHeaderMeta) refs.tradeHeaderMeta.classList.add('hidden');
      return;
    }
    refs.modsHeaderMeta?.classList.add('hidden');
    if (marketplace) {
      refs.logsHeaderMeta?.classList.add('hidden');
      refs.storageHeaderMeta?.classList.add('hidden');
      refs.marketplaceHeaderMeta?.classList.remove('hidden');
      if (refs.tradeHeaderMeta) refs.tradeHeaderMeta.classList.add('hidden');
      return;
    }
    refs.marketplaceHeaderMeta?.classList.add('hidden');
    if (storage) {
      refs.logsHeaderMeta?.classList.add('hidden');
      refs.storageHeaderMeta?.classList.remove('hidden');
      if (refs.tradeHeaderMeta) refs.tradeHeaderMeta.classList.add('hidden');
      return;
    }
    refs.storageHeaderMeta?.classList.add('hidden');
    if (logs) {
      refs.logsHeaderMeta?.classList.remove('hidden');
      if (refs.tradeHeaderMeta) refs.tradeHeaderMeta.classList.add('hidden');
      const periodLabels = {today:'Сегодня', week:'7 дней', month:'30 дней', all:'Всё время'};
      refs.logsPeriodButton.textContent = periodLabels[state.logs.period] || 'Сегодня';
      return;
    }

    refs.logsHeaderMeta?.classList.add('hidden');
    if (refs.tradeHeaderMeta) refs.tradeHeaderMeta.classList.remove('hidden');

    const activeConfig = state.data?.common?.activeConfig || '';
    const configs = Array.isArray(state.data?.common?.configs) ? state.data.common.configs : [];
    refs.configSelect.innerHTML = '';
    if (!configs.length) {
      const option = document.createElement('option');
      option.value = '';
      option.textContent = activeConfig || 'Не выбран';
      refs.configSelect.append(option);
    } else {
      if (!activeConfig) {
        const none = document.createElement('option');
        none.value = '';
        none.textContent = 'Не выбран';
        refs.configSelect.append(none);
      }
      for (const name of configs) {
        const option = document.createElement('option');
        option.value = name;
        option.textContent = name;
        option.selected = name === activeConfig;
        refs.configSelect.append(option);
      }
    }
    refs.configSelect.disabled = busy || configs.length === 0;
    refs.configSelectButton.disabled = refs.configSelect.disabled;
    refs.configSelectText.textContent = (activeConfig || 'Не выбран').replace(/\.json$/i, '');
    refs.configSelectButton.title = refs.configSelect.disabled ? (busy ? 'Остановите торговлю для смены конфига' : 'Конфиги не найдены') : 'Выбрать конфиг';

    refs.automationBadge.textContent = 'Активен';
    refs.automationBadge.className = 'badge badge-success';
    const currency = state.data?.common?.currencyMode === 'VC' ? 'VC' : 'SA';
    const scanActive = buy ? state.data?.common?.buyScan === true : state.data?.common?.sellScan === true;
    refs.startButton.textContent = active ? 'Отмена' : 'Старт';
    refs.startButton.disabled = busy && !active;
    refs.currencyButton.textContent = `${currency}$`;
    refs.currencyButton.disabled = busy;
    if (refs.sellCurrencyQuickButton) {
      refs.sellCurrencyQuickButton.classList.remove('hidden');
      refs.sellCurrencyQuickButton.textContent = `${currency}$`;
      refs.sellCurrencyQuickButton.disabled = busy;
      refs.sellCurrencyQuickButton.title = currency === 'VC' ? 'Сейчас VC$. Нажмите для SA$' : 'Сейчас SA$. Нажмите для VC$';
    }
    refs.scanButton.textContent = scanActive ? 'Стоп скан' : 'Скан';
    refs.scanButton.classList.toggle('active-action', scanActive);
    refs.scanButton.disabled = busy;
    const undoCount = Number(state.data?.common?.undoCount || 0);
    const itemCount = Array.isArray(state.data?.data?.items) ? state.data.data.items.length : 0;
    refs.undoButton.disabled = busy || undoCount < 1;
    refs.clearButton.disabled = busy || itemCount < 1;
    const clearArmed = Date.now() < state.clearArmedUntil;
    refs.clearButton.textContent = clearArmed ? 'Точно?' : 'Очистить';
    refs.clearButton.classList.toggle('confirming', clearArmed);
    const buyContinue = state.data?.common?.buyContinue === true;
    refs.continueButton.classList.toggle('hidden', !buy);
    refs.continueButton.classList.toggle('active-action', buyContinue);
    refs.continueButton.textContent = buyContinue ? 'Продолжение: Вкл' : 'Продолжить';
    refs.continueButton.disabled = busy;
    refs.budgetButton.classList.toggle('hidden', !buy);
    refs.budgetButton.disabled = busy || !asArray(state.data?.data?.items).length;
    refs.refreshButton.classList.toggle('hidden', !buy);
    refs.refreshButton.disabled = busy;
    refs.pricesButton.disabled = busy;
    refs.averageButton.classList.toggle('hidden', !buy);
    refs.averageButton.disabled = busy;
    if (refs.sellScanMainButton) {
      refs.sellScanMainButton.classList.toggle('hidden', buy);
      refs.sellScanMainButton.textContent = scanActive ? 'Стоп скан' : 'Скан инвентаря';
      refs.sellScanMainButton.classList.toggle('active-action', scanActive);
      refs.sellScanMainButton.disabled = busy;
    }
    refs.addButton.classList.add('hidden');
    refs.addButton.disabled = true;
    if (refs.tradeFilterPanel && !refs.tradeFilterPanel.classList.contains('hidden')) renderTradeFilterPanel();
  }

  function renderTable() {
    const buy = state.page === 'buy';
    const locked = tradeBusy();
    refs.tableHead.className = `table-head ${state.page}`;
    refs.tableHead.innerHTML = '';
    const currency = state.data?.common?.currencyMode === 'VC' ? 'VC' : 'SA';
    if (state.sortKey === 'remaining') {
      state.sortKey = null;
      state.sortDirection = 1;
    }

    const columns = [['name','Товар'],['price','Цена'],['count','Кол-во'],['status','Статус']];
    for (const [key, label] of columns) {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = `table-sort-btn ${state.sortKey === key ? 'active' : ''}`;
      button.dataset.sortKey = key;
      button.append(document.createTextNode(label));
      const arrow = document.createElement('span');
      arrow.className = `sort-arrow ${key === 'price' && !state.sortKey ? 'reference-cue' : ''}`;
      arrow.textContent = state.sortKey === key ? (state.sortDirection < 0 ? '↓' : '↑') : '↕';
      button.append(arrow);
      button.title = state.sortKey !== key ? 'Сначала высокие значения' : state.sortDirection < 0 ? 'Сначала низкие значения' : 'Обычный порядок';
      button.addEventListener('click', event => {
        event.preventDefault();
        event.stopPropagation();
        cycleSort(key);
      });
      if (buy) refs.tableHead.append(button);
      else {
        const cell = div('', 'table-head-cell');
        cell.append(button);
        refs.tableHead.append(cell);
      }
    }
    if (buy) refs.tableHead.append(document.createElement('span'));
    else refs.tableHead.append(div('', 'table-head-cell table-head-actions'));

    const all = asArray(state.data?.data?.items);
    const q = normalizeName(state.search);
    const filtered = q ? all.filter(item => normalizeName(item.name).includes(q)) : all.slice();
    const direction = state.sortDirection < 0 ? -1 : 1;
    const sortValue = item => {
      if (state.sortKey === 'price') return Number(currency === 'VC' ? item.price_vc : item.price) || 0;
      if (state.sortKey === 'count') return Number(item.maximum ? item.count_maximum : item.count) || 0;
      if (state.sortKey === 'status') return item.enabled === false ? 0 : 1;
      return normalizeName(item.name || '');
    };
    const compareItems = (a, b) => {
      if (!state.sortKey) return 0;
      const av = sortValue(a), bv = sortValue(b);
      if (typeof av === 'string' || typeof bv === 'string') return String(av).localeCompare(String(bv), 'ru') * direction;
      return (av - bv) * direction;
    };

    const categoryRows = categoryFilters();
    const known = new Set(categoryRows.map(row => String(row.id)));
    const grouped = new Map();
    for (const row of categoryRows) grouped.set(String(row.id), []);
    const fallback = [];
    for (const item of filtered) {
      const category = String(item?.category || 'other');
      if (known.has(category)) grouped.get(category).push(item);
      else fallback.push(item);
    }
    for (const [categoryId, list] of grouped.entries()) {
      list.sort((a, b) => {
        if (categoryId === 'cases') {
          const ar = Number(a.category_subtype_rank) || 0;
          const br = Number(b.category_subtype_rank) || 0;
          if (ar !== br) return ar - br;
        }
        return state.sortKey ? compareItems(a, b) : 0;
      });
    }
    if (state.sortKey) fallback.sort(compareItems);

    refs.tableRows.innerHTML = '';
    refs.emptyState.classList.toggle('hidden', filtered.length !== 0);
    const fragment = document.createDocumentFragment();

    const appendRow = item => {
      const row = document.createElement('div');
      row.className = 'trade-row buy buy-sell-row';
      row.dataset.category = String(item?.category || 'other');
      if (item.enabled === false) row.classList.add('disabled-row');
      if (keyOf(item) === state.selectedKey) row.classList.add('selected');
      row.addEventListener('click', () => {
        state.selectedItem = item;
        state.selectedKey = keyOf(item);
        renderTable();
        renderDetails();
      });

      const itemCell = div('', 'sell-sale-item buy-sell-item');
      {
        const box = div('', 'sell-sale-thumb-box');
        const img = document.createElement('img');
        img.className = 'sell-sale-thumb';
        img.alt = '';
        img.loading = 'lazy';
        setIcon(img, item, 48);
        box.append(img);
        itemCell.append(box);
      }
      const copy = div('', 'sell-sale-copy');
      copy.append(div(item.name, 'sell-sale-name'), div(itemKind(item), 'sell-sale-kind'));
      bindAveragePriceHover(copy, item);
      itemCell.append(copy);
      row.append(itemCell);

      const priceCell = div('', 'sell-sale-input-cell sell-price-cell');
      const priceKey = currency === 'VC' ? 'price_vc' : 'price';
      const priceValue = currency === 'VC' ? item.price_vc : item.price;
      priceCell.append(div(currency === 'VC' ? 'VC$' : '$', 'sell-inline-prefix'), makeSellInlineNumber(item, priceValue, priceKey, {formatMoney:true}));
      row.append(priceCell);

      const countCell = div('', 'sell-count-cell');
      const configuredCount = item.maximum === true ? (Number(item.count_maximum) || Number(item.count) || 0) : (Number(item.count) || 0);
      countCell.append(makeSellInlineNumber(item, configuredCount, 'count', {className:'sell-count-input'}));
      row.append(countCell);

      const status = div('', 'sell-sale-status');
      const toggle = document.createElement('button');
      toggle.type = 'button';
      toggle.className = `toggle ${item.enabled !== false ? 'on' : ''}`;
      toggle.disabled = locked;
      toggle.title = item.enabled !== false ? 'Выключить' : 'Включить';
      toggle.addEventListener('click', async event => {
        event.stopPropagation();
        if (!locked) await patchItem(item, {enabled: item.enabled === false});
      });
      status.append(toggle);
      row.append(status);

      const trash = document.createElement('button');
      trash.type = 'button';
      trash.className = 'trash sell-sale-trash';
      trash.textContent = '';
      trash.title = locked ? 'Остановите торговлю для редактирования' : 'Удалить товар';
      trash.disabled = locked;
      trash.addEventListener('click', async event => {
        event.stopPropagation();
        if (!locked) await removeItem(item);
      });
      row.append(trash);
      fragment.append(row);
    };

    if (state.minimalMode) {
      const items = filtered.slice();
      if (state.sortKey) items.sort(compareItems);
      for (const item of items) appendRow(item);
      refs.tableRows.append(fragment);
      return;
    }

    let lastOrderNumber = 0;
    for (let categoryIndex = 0; categoryIndex < categoryRows.length; categoryIndex += 1) {
      const category = categoryRows[categoryIndex];
      const id = String(category.id);
      const items = grouped.get(id) || [];
      if (!items.length) continue;
      const orderNumber = Number(category.order) > 0 ? Number(category.order) : categoryIndex + 1;
      lastOrderNumber = Math.max(lastOrderNumber, orderNumber);
      const header = document.createElement('div');
      header.className = 'category-group-header';
      header.dataset.category = id;
      header.innerHTML = `<span class="category-group-number">${orderNumber}.</span><span class="category-group-label"></span><span class="category-group-count">${items.length}</span>`;
      header.querySelector('.category-group-label').textContent = text(category.label || categoryLabel(id));
      fragment.append(header);
      for (const item of items) appendRow(item);
    }
    if (fallback.length) {
      const header = document.createElement('div');
      header.className = 'category-group-header';
      header.dataset.category = 'other';
      header.innerHTML = `<span class="category-group-number">${lastOrderNumber + 1}.</span><span class="category-group-label">Прочее</span><span class="category-group-count">${fallback.length}</span>`;
      fragment.append(header);
      for (const item of fallback) appendRow(item);
    }

    refs.tableRows.append(fragment);
  }

  function numberField(label, value, key, readOnly = false) {
    const wrap = document.createElement('label');
    wrap.className = 'field';
    wrap.append(div(label, 'field-label'));
    const input = document.createElement('input');
    input.className = 'field-input';
    input.type = 'number';
    input.min = '0';
    input.step = '1';
    input.value = String(value ?? 0);
    input.disabled = readOnly || tradeBusy();
    if (!input.disabled) {
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
      input.addEventListener('keydown', event => { if (event.key === 'Enter') input.blur(); });
    }
    wrap.append(input);
    return wrap;
  }

  function toggleField(label, enabled, key) {
    const wrap = div('', 'field-toggle-row');
    wrap.append(div(label));
    const controls = div('', 'toggle-control');
    const button = document.createElement('button');
    button.type = 'button';
    button.className = `toggle ${enabled ? 'on' : ''}`;
    button.disabled = tradeBusy();
    button.title = button.disabled ? 'Остановите торговлю для редактирования' : (enabled ? 'Выключить' : 'Включить');
    button.addEventListener('click', () => { if (!tradeBusy()) patchItem(state.selectedItem, {[key]: !enabled}); });
    controls.append(button);
    if (key === 'enabled') controls.append(div(enabled ? 'Включен' : 'Выключен', 'toggle-value-label'));
    wrap.append(controls);
    return wrap;
  }

  function categoryField(item) {
    const wrap = document.createElement('label');
    wrap.className = 'field trade-category-field';
    const label = document.createElement('span');
    label.className = 'field-label';
    label.textContent = 'Тип предмета';

    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'field-input custom-select-trigger trade-category-select';
    button.setAttribute('aria-haspopup', 'listbox');
    button.setAttribute('aria-expanded', 'false');
    button.disabled = tradeBusy();
    const valueSpan = document.createElement('span');
    valueSpan.className = 'custom-select-value';
    const chevron = document.createElement('span');
    chevron.className = 'custom-select-chevron';
    button.append(valueSpan, chevron);

    const current = item.manual_category || 'auto';
    const automatic = categoryLabel(item.category);
    const currentRow = categoryFilters().find(row => String(row.id) === String(current));
    valueSpan.textContent = current === 'auto' ? `Авто (${automatic})` : text(currentRow?.label || current);

    button.addEventListener('click', event => {
      event.preventDefault();
      event.stopPropagation();
      if (button.disabled) return;
      const options = [{value:'auto', label:`Авто (${automatic})`}];
      for (const row of categoryFilters()) options.push({value:String(row.id), label:text(row.label)});
      openPopupSelect(button, options, current, async value => {
        if (tradeBusy()) return;
        try {
          refs.saveBadge.textContent = 'Сохранение...';
          await action('trade.item.category', {side: state.page, identity: item.identity, category: value});
          refs.saveBadge.textContent = 'Сохранено';
          await refresh(true);
          window.setTimeout(() => { refs.saveBadge.textContent = 'Автосохранение'; }, 900);
        } catch (err) {
          refs.saveBadge.textContent = 'Не сохранено';
          showToast(`Тип предмета: ${err.message}`, 'error');
          await refresh(true);
        }
      }, 'item-category');
    });

    wrap.append(label, button);
    return wrap;
  }

  function renderDetails() {
    const item = state.selectedItem;
    if (activePopupSelect?.kind === 'item-category' && activePopupSelect.anchor?.isConnected && item) return;
    refs.detailEmpty.classList.toggle('hidden', !!item);
    refs.detailContent.classList.toggle('hidden', !item);
    if (!item) return;

    refs.detailName.textContent = item.name || 'Предмет';
    setIcon(refs.detailIcon, item, 256);
    refs.detailFields.innerHTML = '';

    const currency = state.data?.common?.currencyMode === 'VC' ? 'VC' : 'SA';
    if (state.page === 'buy') {
      if (currency === 'VC') refs.detailFields.append(numberField('Цена VC$', item.price_vc, 'price_vc'));
      else refs.detailFields.append(numberField('Цена SA$', item.price, 'price'));
    } else {
      const price = div('', 'field-row');
      price.append(numberField('Цена', item.price, 'price'), numberField('Цена VC$', item.price_vc, 'price_vc'));
      refs.detailFields.append(price);
    }

    if (state.page === 'buy') {
      refs.detailFields.append(numberField('Кол-во', item.count, 'count'));
    } else {
      const count = div('', 'field-row');
      count.append(
        numberField('Кол-во', item.count, 'count'),
        numberField('Доступно', item.all_count, 'all_count', true)
      );
      refs.detailFields.append(count);
    }
    if (state.page === 'sell') {
      refs.detailFields.append(toggleField('Выставлять максимум', item.maximum === true, 'maximum'));
    }
    refs.detailFields.append(toggleField('Статус', item.enabled !== false, 'enabled'));
    if (state.page === 'buy' && !state.minimalMode) refs.detailFields.append(categoryField(item));
  }

  const sellCurrency = () => state.data?.common?.currencyMode === 'VC' ? 'VC' : 'SA';

  function sellConfiguredCount(item) {
    const available = Math.max(0, Math.trunc(Number(item?.all_count) || 0));
    if (item?.maximum === true) return available;
    return Math.max(0, Math.trunc(Number(item?.count) || 0));
  }

  function sellEffectiveCount(item) {
    const available = Math.max(0, Math.trunc(Number(item?.all_count) || 0));
    const configured = sellConfiguredCount(item);
    return Math.max(0, Math.min(configured, available));
  }

  function sellItemPrice(item) {
    return Math.max(0, Number(sellCurrency() === 'VC' ? item?.price_vc : item?.price) || 0);
  }

  function sellMoney(value) {
    const prefix = sellCurrency() === 'VC' ? 'VC$ ' : '$ ';
    return `${prefix}${moneyRef(value)}`;
  }

  function selectSellItem(item) {
    if (!item) return;
    state.selectedItem = item;
    state.selectedKey = keyOf(item);
    renderSellItems();
    renderSellDetails();
  }

  function sellSortedItems() {
    const all = asArray(state.data?.data?.items).slice();
    if (!state.sortKey) return all;
    const direction = state.sortDirection < 0 ? -1 : 1;
    const valueOf = item => {
      if (state.sortKey === 'price') return sellItemPrice(item);
      if (state.sortKey === 'count') return sellConfiguredCount(item);
      if (state.sortKey === 'status') return item?.enabled === false ? 0 : 1;
      return normalizeName(item?.name || '');
    };
    return all
      .map((item, index) => ({item, index}))
      .sort((a, b) => {
        const av = valueOf(a.item), bv = valueOf(b.item);
        let result;
        if (typeof av === 'string' || typeof bv === 'string') result = String(av).localeCompare(String(bv), 'ru');
        else result = av - bv;
        return result === 0 ? a.index - b.index : result * direction;
      })
      .map(entry => entry.item);
  }

  function updateSellSortHeaders() {
    document.querySelectorAll('[data-sell-sort]').forEach(button => {
      const key = button.dataset.sellSort;
      const arrow = button.querySelector('span');
      const active = state.sortKey === key;
      button.classList.toggle('active', active);
      if (arrow) arrow.textContent = active ? (state.sortDirection < 0 ? '↓' : '↑') : '↕';
      button.title = !active ? 'Сначала высокие значения' : state.sortDirection < 0 ? 'Сначала низкие значения' : 'Обычный порядок';
    });
  }

  function makeSellInlineNumber(item, value, key, options = {}) {
    const input = document.createElement('input');
    input.className = `sell-inline-input ${options.className || ''}`.trim();
    const formatMoney = options.formatMoney === true;
    input.type = formatMoney ? 'text' : 'number';
    input.inputMode = formatMoney ? 'numeric' : '';
    if (!formatMoney) {
      input.min = '0';
      input.step = '1';
    }
    const initialValue = Math.max(0, Math.trunc(Number(value) || 0));
    input.value = formatMoney ? moneyRef(initialValue) : String(initialValue);
    input.disabled = tradeBusy();
    let timer = 0;
    const commit = async () => {
      clearTimeout(timer);
      if (input.disabled) return;
      let n = formatMoney ? parseMoneyInput(input.value) : Number(input.value);
      if (!Number.isFinite(n) || n < 0) return;
      n = Math.trunc(n);
      const available = Math.max(0, Math.trunc(Number(item?.all_count) || 0));
      if (options.clampAvailable && available > 0) n = Math.min(n, available);
      input.value = formatMoney ? moneyRef(n) : String(n);
      const patch = key === 'count' ? {count: n, maximum: false} : {[key]: n};
      await patchItem(item, patch);
    };
    input.addEventListener('click', event => event.stopPropagation());
    input.addEventListener('pointerdown', event => event.stopPropagation());
    if (formatMoney) {
      input.addEventListener('focus', () => {
        input.value = String(parseMoneyInput(input.value));
      });
    }
    input.addEventListener('input', () => {
      clearTimeout(timer);
      timer = window.setTimeout(commit, 430);
    });
    input.addEventListener('change', commit);
    input.addEventListener('blur', commit);
    input.addEventListener('keydown', event => {
      event.stopPropagation();
      if (event.key === 'Enter') input.blur();
    });
    return input;
  }

  function renderSellInventory() {
    if (!refs.sellInventoryRows) return;
    const source = Array.isArray(state.data?.data?.source) ? state.data.data.source : [];
    const q = normalizeName(state.search);
    const items = q ? source.filter(item => normalizeName(item.name).includes(q)) : source;
    const existing = new Map(asArray(state.data?.data?.items).map(item => [normalizeName(item.name), item]));
    refs.sellInventoryRows.innerHTML = '';
    refs.sellInventoryEmpty.classList.toggle('hidden', items.length !== 0);

    const fragment = document.createDocumentFragment();
    for (const sourceItem of items) {
      const row = document.createElement('div');
      row.className = 'sell-inventory-row';
      const configured = existing.get(normalizeName(sourceItem.name));
      if (configured) row.classList.add('configured');
      if (configured && keyOf(configured) === state.selectedKey) row.classList.add('selected');

      const thumbBox = div('', 'sell-inventory-thumb-box');
      {
        const img = document.createElement('img');
        img.className = 'sell-inventory-thumb';
        img.alt = '';
        img.loading = 'lazy';
        setIcon(img, sourceItem, 48);
        thumbBox.append(img);
      }

      const copy = div('', 'sell-inventory-copy');
      copy.append(div(sourceItem.name, 'sell-inventory-name'));
      const count = div(money(sourceItem.all_count || 0), 'sell-inventory-count');
      const add = document.createElement('button');
      add.type = 'button';
      add.className = `sell-inventory-add ${configured ? 'added' : ''}`;
      add.disabled = tradeBusy();
      add.title = configured ? 'Товар уже добавлен. Перейти к нему' : 'Добавить на продажу';
      add.setAttribute('aria-label', add.title);
      add.addEventListener('click', async event => {
        event.stopPropagation();
        if (tradeBusy()) return;
        if (configured) {
          selectSellItem(configured);
          await baronAssistantUi?.event('sell_item_selected', {itemName: sourceItem.name});
          requestAnimationFrame(() => refs.sellSaleRows?.querySelector('.sell-sale-row.selected')?.scrollIntoView({block:'nearest'}));
          return;
        }
        try {
          state.selectedItem = {name: sourceItem.name};
          state.selectedKey = null;
          await action('trade.item.add', {side:'sell', source_index:sourceItem.index});
          await baronAssistantUi?.event('sell_item_selected', {itemName: sourceItem.name});
          showToast('Товар добавлен на продажу', 'success');
          await refresh(true);
        } catch (err) {
          const message = err.message === 'not_enough_items' ? 'Недостаточно предметов для добавления' : err.message;
          showToast(`Не удалось добавить: ${message}`, 'error');
        }
      });
      row.addEventListener('click', () => {
        if (configured) {
          selectSellItem(configured);
          void baronAssistantUi?.event('sell_item_selected', {itemName: sourceItem.name});
          requestAnimationFrame(() => refs.sellSaleRows?.querySelector('.sell-sale-row.selected')?.scrollIntoView({block:'nearest'}));
          return;
        }
        if (!tradeBusy()) add.click();
      });
      if (thumbBox) row.append(thumbBox);
      row.append(copy, count, add);
      fragment.append(row);
    }
    refs.sellInventoryRows.append(fragment);
  }

  function renderSellItems() {
    if (!refs.sellSaleRows) return;
    updateSellSortHeaders();
    const locked = tradeBusy();
    if (state.sortKey === 'remaining') {
      state.sortKey = null;
      state.sortDirection = 1;
    }
    const all = Array.isArray(state.data?.data?.items) ? state.data.data.items : [];
    const q = normalizeName(state.search);
    const statusFiltered = state.sellStatusFilter === 'enabled'
      ? all.filter(item => item.enabled !== false)
      : state.sellStatusFilter === 'disabled'
        ? all.filter(item => item.enabled === false)
        : all.slice();
    const filtered = q ? statusFiltered.filter(item => normalizeName(item.name).includes(q)) : statusFiltered;
    const direction = state.sortDirection < 0 ? -1 : 1;
    const valueOf = item => {
      if (state.sortKey === 'price') return sellItemPrice(item);
      if (state.sortKey === 'count') return sellConfiguredCount(item);
      if (state.sortKey === 'status') return item?.enabled === false ? 0 : 1;
      return normalizeName(item?.name || '');
    };
    const compareItems = (a, b) => {
      if (!state.sortKey) return 0;
      const av = valueOf(a), bv = valueOf(b);
      if (typeof av === 'string' || typeof bv === 'string') return String(av).localeCompare(String(bv), 'ru') * direction;
      return (av - bv) * direction;
    };

    const categories = categoryFilters();
    const known = new Set(categories.map(row => String(row.id)));
    const grouped = new Map(categories.map(row => [String(row.id), []]));
    const fallback = [];
    for (const item of filtered) {
      const category = String(item?.category || 'other');
      if (known.has(category)) grouped.get(category).push(item);
      else fallback.push(item);
    }
    for (const [categoryId, list] of grouped.entries()) {
      list.sort((a, b) => {
        if (categoryId === 'cases') {
          const ar = Number(a.category_subtype_rank) || 0;
          const br = Number(b.category_subtype_rank) || 0;
          if (ar !== br) return ar - br;
        }
        return state.sortKey ? compareItems(a, b) : 0;
      });
    }
    if (state.sortKey) fallback.sort(compareItems);

    refs.sellSaleRows.innerHTML = '';
    if (refs.sellSaleEmpty) {
      const filterEmptyText = state.sellStatusFilter === 'enabled'
        ? 'Включённых товаров нет.'
        : state.sellStatusFilter === 'disabled'
          ? 'Отключённых товаров нет.'
          : 'Добавьте предметы из инвентаря слева.';
      refs.sellSaleEmpty.textContent = filterEmptyText;
      refs.sellSaleEmpty.classList.toggle('hidden', filtered.length !== 0);
    }
    const fragment = document.createDocumentFragment();

    const appendRow = item => {
      const row = document.createElement('div');
      row.className = 'sell-sale-row';
      row.dataset.category = String(item?.category || 'other');
      if (item.enabled === false) row.classList.add('disabled-row');
      if (keyOf(item) === state.selectedKey) row.classList.add('selected');
      row.addEventListener('click', () => selectSellItem(item));

      const itemCell = div('', 'sell-sale-item');
      {
        const box = div('', 'sell-sale-thumb-box');
        const img = document.createElement('img');
        img.className = 'sell-sale-thumb';
        img.alt = '';
        img.loading = 'lazy';
        setIcon(img, item, 48);
        box.append(img);
        itemCell.append(box);
      }
      const copy = div('', 'sell-sale-copy');
      copy.append(div(item.name, 'sell-sale-name'), div(itemKind(item), 'sell-sale-kind'));
      bindAveragePriceHover(copy, item);
      itemCell.append(copy);
      row.append(itemCell);

      const priceCell = div('', 'sell-sale-input-cell sell-price-cell');
      const prefix = div(sellCurrency() === 'VC' ? 'VC$' : '$', 'sell-inline-prefix');
      priceCell.append(prefix, makeSellInlineNumber(item, sellItemPrice(item), sellCurrency() === 'VC' ? 'price_vc' : 'price', {formatMoney:true}));
      row.append(priceCell);

      const countCell = div('', 'sell-count-cell');
      countCell.append(makeSellInlineNumber(item, sellConfiguredCount(item), 'count', {className:'sell-count-input', clampAvailable:true}));
      row.append(countCell);
      const status = div('', 'sell-sale-status');
      const toggle = document.createElement('button');
      toggle.type = 'button';
      toggle.className = `toggle ${item.enabled !== false ? 'on' : ''}`;
      toggle.disabled = locked;
      toggle.title = item.enabled !== false ? 'Выключить' : 'Включить';
      if (keyOf(item) === state.selectedKey) {
        toggle.dataset.baronAnchor = 'sell_status_toggle';
      }
      toggle.addEventListener('click', async event => {
        event.stopPropagation();
        if (locked) return;
        const previousEnabled = item.enabled !== false;
        const nextEnabled = !previousEnabled;

        item.enabled = nextEnabled;
        toggle.classList.toggle('on', nextEnabled);
        toggle.title = nextEnabled ? 'Выключить' : 'Включить';
        row.classList.toggle('disabled-row', !nextEnabled);

        const saved = await patchItem(item, {enabled:nextEnabled});
        if (saved) {
          void baronAssistantUi?.event('sell_status_toggled', {
            itemName: item.name,
            enabled: nextEnabled
          });
        } else {
          item.enabled = previousEnabled;
          toggle.classList.toggle('on', previousEnabled);
          toggle.title = previousEnabled ? 'Выключить' : 'Включить';
          row.classList.toggle('disabled-row', !previousEnabled);
        }
      });
      status.append(toggle);
      row.append(status);

      const trash = document.createElement('button');
      trash.type = 'button';
      trash.className = 'trash sell-sale-trash';
      trash.disabled = locked;
      trash.title = locked ? 'Остановите торговлю для редактирования' : 'Удалить товар';
      trash.addEventListener('click', async event => {
        event.stopPropagation();
        if (!locked) await removeItem(item);
      });
      row.append(trash);
      fragment.append(row);
    };

    if (state.minimalMode) {
      const items = filtered.slice();
      if (state.sortKey) items.sort(compareItems);
      for (const item of items) appendRow(item);
      refs.sellSaleRows.append(fragment);
    } else {
    let lastOrderNumber = 0;
    for (let categoryIndex = 0; categoryIndex < categories.length; categoryIndex += 1) {
      const category = categories[categoryIndex];
      const id = String(category.id);
      const items = grouped.get(id) || [];
      if (!items.length) continue;
      const orderNumber = Number(category.order) > 0 ? Number(category.order) : categoryIndex + 1;
      lastOrderNumber = Math.max(lastOrderNumber, orderNumber);
      const header = document.createElement('div');
      header.className = 'category-group-header';
      header.dataset.category = id;
      header.innerHTML = `<span class="category-group-number">${orderNumber}.</span><span class="category-group-label"></span><span class="category-group-count">${items.length}</span>`;
      header.querySelector('.category-group-label').textContent = text(category.label || categoryLabel(id));
      fragment.append(header);
      for (const item of items) appendRow(item);
    }
    if (fallback.length) {
      const header = document.createElement('div');
      header.className = 'category-group-header';
      header.dataset.category = 'other';
      header.innerHTML = `<span class="category-group-number">${lastOrderNumber + 1}.</span><span class="category-group-label">Прочее</span><span class="category-group-count">${fallback.length}</span>`;
      fragment.append(header);
      for (const item of fallback) appendRow(item);
    }
    refs.sellSaleRows.append(fragment);
    }

    const enabled = all.filter(item => item.enabled !== false);
    if (refs.sellTotalItems) refs.sellTotalItems.textContent = String(all.length);
    if (refs.sellEnabledItems) refs.sellEnabledItems.textContent = String(enabled.length);
    if (refs.sellDisabledItems) refs.sellDisabledItems.textContent = String(Math.max(0, all.length - enabled.length));
    document.querySelectorAll('[data-sell-status-filter]').forEach(button => {
      const active = String(button.dataset.sellStatusFilter || 'all') === state.sellStatusFilter;
      button.classList.toggle('active', active);
      button.setAttribute('aria-pressed', active ? 'true' : 'false');
    });
  }

  function sellMarketCacheKey(item) {
    return `${sellCurrency()}|${catalogName(item?.name || '')}`;
  }

  async function requestSellMarketStats(item, force = false) {
    if (!item || state.page !== 'sell') return;
    const key = sellMarketCacheKey(item);
    if (!force && (state.sellMarketStats.has(key) || state.sellMarketPending.has(key))) return;
    state.sellMarketPending.add(key);
    if (force) state.sellMarketStats.delete(key);
    try {
      const result = await action('prices.stats', {side:'sell', identity:item.identity, currency:sellCurrency()});
      state.sellMarketStats.set(key, result?.data || {available:false});
    } catch (_) {
      state.sellMarketStats.set(key, {available:false});
    } finally {
      state.sellMarketPending.delete(key);
      if (state.page === 'sell' && state.selectedItem && sellMarketCacheKey(state.selectedItem) === key) renderSellDetails();
    }
  }

  function renderSellMarket(item) {
    const key = sellMarketCacheKey(item);
    const stats = state.sellMarketStats.get(key);
    const loading = state.sellMarketPending.has(key);
    const emptyText = loading ? 'Загрузка...' : 'Нет данных';
    if (!stats?.available) {
      refs.sellMarketAverage.textContent = emptyText;
      refs.sellMarketMin.textContent = emptyText;
      refs.sellMarketMax.textContent = emptyText;
      if (!stats && !loading) requestSellMarketStats(item);
      return;
    }
    refs.sellMarketAverage.textContent = sellMoney(stats.average || 0);
    refs.sellMarketMin.textContent = sellMoney(stats.min || 0);
    refs.sellMarketMax.textContent = sellMoney(stats.max || 0);
  }

  function renderSellDetails() {
    if (refs.sellStartButton) {
      refs.sellStartButton.disabled = tradeBusy() && !tradeActive();
      refs.sellStartButton.classList.toggle('cancel', tradeActive());
      if (refs.sellStartButtonText) refs.sellStartButtonText.textContent = tradeActive() ? 'Остановить продажу' : 'Начать продажу';
    }
    if (!refs.sellInfoContent) return;
    const item = state.selectedItem;
    refs.sellInfoEmpty.classList.toggle('hidden', !!item);
    refs.sellInfoContent.classList.toggle('hidden', !item);
    if (!item) return;

    const available = Math.max(0, Math.trunc(Number(item.all_count) || 0));
    const configured = sellConfiguredCount(item);
    const selling = sellEffectiveCount(item);
    const free = Math.max(0, available - selling);
    const price = sellItemPrice(item);
    const locked = tradeBusy();

    refs.sellInfoName.textContent = item.name || 'Предмет';
    refs.sellInfoKind.textContent = itemKind(item);
    setIcon(refs.sellInfoIcon, item, 256);
    refs.sellStockInventory.textContent = `${money(available)} шт.`;
    refs.sellStockSelling.textContent = `${money(selling)} шт.`;
    refs.sellStockFree.textContent = `${money(free)} шт.`;
    refs.sellInfoPrice.value = moneyRef(Math.max(0, Math.trunc(price)));
    refs.sellInfoCount.value = String(configured);
    refs.sellInfoPrice.disabled = locked;
    refs.sellInfoCount.disabled = locked;
    refs.sellInfoMax.disabled = locked;
    refs.sellInfoMax.classList.toggle('active', item.maximum === true);
    refs.sellPricePrefix.textContent = sellCurrency() === 'VC' ? 'VC$' : '$';
    refs.sellInfoIncome.textContent = sellMoney(price * selling);
    renderSellMarket(item);
  }

  function renderSellWorkspace() {
    renderSellInventory();
    renderSellItems();
  }


  function logsDateValue(dateText) {
    const match = String(dateText || '').match(/^(\d{2})\.(\d{2})\.(\d{4})$/);
    if (!match) return 0;
    return Date.UTC(Number(match[3]), Number(match[2]) - 1, Number(match[1]));
  }

  function logsBaseRecords() {
    const all = Array.isArray(state.data?.data?.records) ? state.data.data.records : [];
    const todayText = state.data?.common?.today || '';
    const todayValue = logsDateValue(todayText);
    const days = state.logs.period === 'week' ? 7 : state.logs.period === 'month' ? 30 : 0;
    const cutoff = days && todayValue ? todayValue - (days - 1) * 86400000 : 0;
    return all.filter(record => {
      if (state.logs.period === 'today' && todayText && record.date !== todayText) return false;
      if (days && cutoff && logsDateValue(record.date) < cutoff) return false;
      if (state.logs.date !== 'all' && record.date !== state.logs.date) return false;
      if (state.logs.category !== 'all' && record.category !== state.logs.category) return false;
      if (state.logs.status !== 'all' && record.status !== state.logs.status) return false;
      const q = normalizeName(state.logs.search);
      if (q) {
        const hay = normalizeName([record.date, record.time, record.category_label, record.description, record.detail, record.raw].join(' '));
        if (!hay.includes(q)) return false;
      }
      return true;
    });
  }

  function logsCategoryOptions() {
    const all = Array.isArray(state.data?.data?.records) ? state.data.data.records : [];
    const map = new Map();
    for (const record of all) {
      if (record?.category && !map.has(record.category)) map.set(record.category, record.category_label || record.category);
    }
    return [{value:'all', label:'Все категории'}, ...[...map.entries()].map(([value,label]) => ({value,label}))];
  }

  function logAmount(record) {
    const value = Number(record?.amount);
    if (record?.amount == null || !Number.isFinite(value)) return '-';
    if (value === 0) return '-';
    const prefix = value > 0 ? '+ ' : '- ';
    const currency = record.currency === 'VC' ? 'VC$' : '$';
    return `${prefix}${currency} ${moneyRef(Math.abs(value))}`;
  }

  function logStatusLabel(status) {
    if (status === 'warning') return 'Внимание';
    if (status === 'info') return 'Информация';
    return 'Успешно';
  }

  function logDisplayId(record) {
    const source = String(record?.id || record?.raw || '');
    let hash = 2166136261;
    for (let i = 0; i < source.length; i++) {
      hash ^= source.charCodeAt(i);
      hash = Math.imul(hash, 16777619);
    }
    return `#${String(hash >>> 0).padStart(8, '0').slice(-8)}`;
  }

  function renderLogsToolbar() {
    if (!refs.logsToolbar) return;
    const periodLabels = {today:'Сегодня', week:'7 дней', month:'30 дней', all:'Всё время'};
    refs.logsPeriodButton.textContent = periodLabels[state.logs.period] || 'Сегодня';
    const category = logsCategoryOptions().find(row => row.value === state.logs.category);
    refs.logsCategoryButton.textContent = category?.label || 'Все категории';
    const statusLabels = {all:'Все статусы', success:'Успешно', info:'Информация', warning:'Внимание'};
    refs.logsStatusButton.textContent = statusLabels[state.logs.status] || 'Все статусы';
    const dateLabelNode = refs.logsDateButton?.querySelector('span:last-child');
    if (dateLabelNode) {
      dateLabelNode.textContent = state.logs.date !== 'all'
        ? state.logs.date
        : state.logs.period === 'today' ? 'Сегодня' : 'Все даты';
    }
    if (refs.logsSearchInput && refs.logsSearchInput.value !== state.logs.search) refs.logsSearchInput.value = state.logs.search;
  }

  function renderLogsPagination(total, page, pages) {
    refs.logsPagination.innerHTML = '';
    if (pages <= 1) return;
    const add = (label, value, active = false, disabled = false) => {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = `logs-page-btn ${active ? 'active' : ''}`.trim();
      button.textContent = label;
      button.disabled = disabled;
      button.addEventListener('click', () => {
        if (disabled || value === state.logs.page) return;
        state.logs.page = value;
        renderLogs();
      });
      refs.logsPagination.append(button);
    };
    add('‹', Math.max(1, page - 1), false, page <= 1);
    const values = [];
    if (pages <= 7) {
      for (let i = 1; i <= pages; i++) values.push(i);
    } else {
      values.push(1);
      const start = Math.max(2, page - 2);
      const end = Math.min(pages - 1, page + 2);
      if (start > 2) values.push('…');
      for (let i = start; i <= end; i++) values.push(i);
      if (end < pages - 1) values.push('…');
      values.push(pages);
    }
    for (const value of values) {
      if (value === '…') {
        const span = document.createElement('span');
        span.className = 'logs-page-btn';
        span.textContent = '…';
        refs.logsPagination.append(span);
      } else add(String(value), value, value === page);
    }
    add('›', Math.min(pages, page + 1), false, page >= pages);
  }

  function renderLogsDetail(record) {
    if (!record) {
      refs.logsDetailEmpty.classList.remove('hidden');
      refs.logsDetailContent.classList.add('hidden');
      return;
    }
    refs.logsDetailEmpty.classList.add('hidden');
    refs.logsDetailContent.classList.remove('hidden');
    refs.logsDetailDate.textContent = record.date || '-';
    refs.logsDetailTime.textContent = record.time || '-';
    refs.logsDetailCategory.textContent = record.category_label || '-';
    refs.logsDetailDescription.textContent = record.description || '-';
    refs.logsDetailSubtext.textContent = record.detail || '';
    refs.logsDetailAmount.textContent = logAmount(record);
    refs.logsDetailAmount.className = Number(record.amount) > 0 ? 'positive' : Number(record.amount) < 0 ? 'negative' : '';
    refs.logsDetailStatus.textContent = logStatusLabel(record.status);
    refs.logsDetailId.textContent = logDisplayId(record);
  }

  function renderLogsActivity(records) {
    const today = state.data?.common?.today || '';
    const targetDate = state.logs.date !== 'all'
      ? state.logs.date
      : records.some(record => record.date === today) ? today : records[0]?.date || '';
    const buckets = Array(24).fill(0);
    for (const record of records) {
      if (targetDate && record.date !== targetDate) continue;
      const hour = Number(String(record.time || '').slice(0, 2));
      if (Number.isInteger(hour) && hour >= 0 && hour < 24) buckets[hour] += 1;
    }
    const max = Math.max(1, ...buckets);
    refs.logsActivityChart.innerHTML = '';
    for (const value of buckets) {
      const bar = document.createElement('div');
      bar.className = 'logs-activity-bar';
      bar.style.height = `${Math.max(3, (value / max) * 100)}%`;
      bar.title = String(value);
      refs.logsActivityChart.append(bar);
    }
    refs.logsActivityTotal.textContent = `Всего: ${buckets.reduce((a,b) => a + b, 0)}`;
  }

  function renderLogs() {
    refs.logsToolbar?.classList.remove('hidden');
    refs.logsWorkspace?.classList.remove('hidden');
    renderLogsToolbar();

    const records = logsBaseRecords();
    const pages = Math.max(1, Math.ceil(records.length / state.logs.perPage));
    state.logs.page = Math.min(Math.max(1, state.logs.page), pages);
    const start = (state.logs.page - 1) * state.logs.perPage;
    const visible = records.slice(start, start + state.logs.perPage);
    if (state.minimalMode) state.logs.selectedId = null;
    else if (!records.some(record => record.id === state.logs.selectedId)) state.logs.selectedId = records[0]?.id || null;
    const selected = state.minimalMode ? null : (records.find(record => record.id === state.logs.selectedId) || null);

    refs.logsRows.innerHTML = '';
    for (const record of visible) {
      const row = document.createElement('div');
      row.className = `logs-row ${record.id === state.logs.selectedId ? 'selected' : ''}`.trim();
      row.append(div(record.date || '-', 'logs-date-cell'));
      row.append(div(record.time || '-', 'logs-time-cell'));
      const category = document.createElement('div');
      const badge = document.createElement('span');
      badge.className = 'logs-category-badge';
      badge.dataset.category = record.category || 'info';
      badge.textContent = record.category_label || 'Информация';
      category.append(badge);
      row.append(category);
      const description = div('', 'logs-description');
      const title = document.createElement('strong');
      title.textContent = record.description || 'Событие';
      const detail = document.createElement('small');
      detail.textContent = record.detail || '';
      description.append(title, detail);
      row.append(description);
      const amount = div(logAmount(record), `logs-amount ${Number(record.amount) > 0 ? 'positive' : Number(record.amount) < 0 ? 'negative' : ''}`.trim());
      row.append(amount);
      const status = div(logStatusLabel(record.status), `logs-status ${record.status === 'info' ? 'info' : record.status === 'warning' ? 'warning' : ''}`.trim());
      row.append(status);
      if (!state.minimalMode) row.addEventListener('click', () => {
        state.logs.selectedId = record.id;
        renderLogs();
      });
      refs.logsRows.append(row);
    }
    refs.logsEmpty.classList.toggle('hidden', records.length > 0);
    refs.logsTotalRecords.textContent = money(records.length);
    refs.logsShownRecords.textContent = records.length ? `${start + 1}-${Math.min(start + visible.length, records.length)} из ${records.length}` : '0 из 0';
    renderLogsPagination(records.length, state.logs.page, pages);
    if (!state.minimalMode) {
      renderLogsDetail(selected);
      renderLogsActivity(records);
      refs.logsStatTotal.textContent = money(records.length);
      const success = records.filter(record => record.status === 'success').length;
      const warnings = records.filter(record => record.status === 'warning').length;
      refs.logsStatSuccess.textContent = records.length ? `${Math.round(success / records.length * 100)}%` : '0%';
      refs.logsStatWarnings.textContent = money(warnings);
    }
    installWheelScroller(refs.logsRows);
  }

  const storagePlaceMatches = (location, place) => {
    if (place === 'all') return true;
    if (place === 'garage') return normalizeName(`${location?.label || ''} ${location?.object_label || ''}`).includes('гараж');
    return String(location?.kind || '') === place;
  };
  const formatStorageTime = value => {
    const n = Number(value || 0); if (!n) return '-';
    const d = new Date(n * 1000), now = new Date();
    const hh = String(d.getHours()).padStart(2,'0'), mm = String(d.getMinutes()).padStart(2,'0');
    if (d.toDateString() === now.toDateString()) return `Сегодня, ${hh}:${mm}`;
    return `${String(d.getDate()).padStart(2,'0')}.${String(d.getMonth()+1).padStart(2,'0')}.${d.getFullYear()}, ${hh}:${mm}`;
  };
  function storageFilteredItems() {
    const q = normalizeName(state.storage.search);
    const raw = Array.isArray(state.data?.data?.items) ? state.data.data.items : [];
    return raw.map(item => {
      const locations = (Array.isArray(item.locations) ? item.locations : []).filter(loc => storagePlaceMatches(loc, state.storage.place));
      const count = locations.reduce((sum, loc) => sum + Number(loc.count || 0), 0);
      const updated = locations.reduce((max, loc) => Math.max(max, Number(loc.updated || 0)), 0);
      return Object.assign({}, item, {viewLocations: locations, viewCount: count, viewUpdated: updated});
    }).filter(item => item.viewLocations.length && (state.storage.type === 'all' || String(item.category) === state.storage.type)
      && (!q || normalizeName(item.name).includes(q) || normalizeName(item.type_label).includes(q)));
  }
  function storageTypeOptions() {
    const seen = new Map();
    const rawItems = state.data?.data?.items;
    const items = Array.isArray(rawItems) ? rawItems : [];
    for (const item of items) if (item.category) seen.set(String(item.category), String(item.type_label || item.category));
    return [{value:'all',label:'Все типы'}, ...[...seen.entries()].sort((a,b)=>a[1].localeCompare(b[1],'ru')).map(([value,label])=>({value,label}))];
  }
  function storagePlaceSummary(item) {
    const locs=item.viewLocations || [];
    if (locs.length !== 1) return {place:'Разные места', object:'-'};
    return {place:locs[0].kind_label || 'Неизвестно', object:locs[0].object_label || '-'};
  }
  function renderStorageDetail(item) {
    if (!item) { state.averagePrices.storageKey=null; refs.storageDetailEmpty.classList.remove('hidden'); refs.storageDetailContent.classList.add('hidden'); return; }
    refs.storageDetailEmpty.classList.add('hidden'); refs.storageDetailContent.classList.remove('hidden');
    refs.storageDetailName.textContent=item.name || '-'; refs.storageDetailType.textContent=item.type_label || 'Прочее'; refs.storageDetailTotal.textContent=money(item.viewCount || 0);
    setIcon(refs.storageDetailIcon,item,256);
    refs.storageLocationRows.innerHTML='';
    for (const loc of item.viewLocations || []) {
      const row=div('', 'storage-location-row');
      const icon=div('', 'storage-location-icon'); icon.innerHTML=iconSvg('storage');
      const copy=div('', 'storage-location-copy'); copy.append(div(loc.kind_label || 'Хранилище',''), div(loc.object_label && loc.object_label !== '-' ? loc.object_label : (loc.label || ''),'storage-location-sub'));
      row.append(icon,copy,div(`${money(loc.count || 0)} шт.`,'storage-location-count')); refs.storageLocationRows.append(row);
    }
    refs.storageInfoType.textContent=item.type_label || 'Прочее'; refs.storageInfoId.textContent=item.item_id || '-'; refs.storageInfoUpdated.textContent=formatStorageTime(item.viewUpdated || item.updated);
    const info=!state.minimalMode && state.storage.tab==='info'; refs.storageDistributionTab.classList.toggle('active',!info); refs.storageInfoTab.classList.toggle('active',info);
    refs.storageDistributionPanel.classList.toggle('hidden',info); refs.storageInfoPanel.classList.toggle('hidden',!info);
    if (info) renderStorageAveragePrices(item);
  }
  function renderStorage() {
    const items=storageFilteredItems();
    if (!items.some(item=>item.key===state.storage.selectedKey)) state.storage.selectedKey=items[0]?.key || null;
    refs.storageRows.innerHTML='';
    const uniquePlaces=new Set(); let total=0;
    for (const item of items) {
      total += Number(item.viewCount || 0); for (const loc of item.viewLocations || []) uniquePlaces.add(loc.key);
      const place=storagePlaceSummary(item), row=div('',`storage-row ${item.key===state.storage.selectedKey?'selected':''}`.trim());
      const itemCell=div('','storage-item-cell');
      { const img=document.createElement('img'); img.alt=''; setIcon(img,item,48); itemCell.append(img); }
      const copy=div('','storage-item-copy'); copy.append(div(item.name || '-','storage-item-name'),div(item.type_label || 'Прочее','storage-item-sub')); bindAveragePriceHover(copy,item); itemCell.append(copy);
      row.append(itemCell,div(item.type_label || 'Прочее'),div(money(item.viewCount || 0),'storage-count-cell'),div(place.place),div(place.object),div(formatStorageTime(item.viewUpdated),'storage-updated-cell'));
      row.addEventListener('click',()=>{state.storage.selectedKey=item.key;renderStorage();}); refs.storageRows.append(row);
    }
    refs.storageEmpty.classList.toggle('hidden',items.length>0); refs.storageFoundCount.textContent=money(items.length); refs.storageTotalCount.textContent=money(total); refs.storagePlacesCount.textContent=money(uniquePlaces.size);
    renderStorageDetail(items.find(item=>item.key===state.storage.selectedKey) || null); installWheelScroller(refs.storageRows);
    refs.storageTypeButton.textContent=storageTypeOptions().find(x=>x.value===state.storage.type)?.label || 'Все типы';
    refs.storagePlaceTabs?.querySelectorAll('[data-storage-place]').forEach(btn=>btn.classList.toggle('active',btn.dataset.storagePlace===state.storage.place));
  }

  function marketplaceData() { return state.data?.data || {}; }
  function marketplaceShops() { const shops=marketplaceData().shops; return Array.isArray(shops) ? shops : []; }
  function marketplaceCurrency(serverId) { return Number(serverId) === 0 ? 'VC$' : 'SA$'; }
  function marketplaceAge(updatedAt) {
    const stamp=Number(updatedAt || 0); if (!stamp) return 'неизвестно';
    const sec=Math.max(0,Math.floor(Date.now()/1000-stamp));
    if (sec<60) return `${sec} сек назад`;
    if (sec<3600) return `${Math.floor(sec/60)} мин назад`;
    if (sec<86400) return `${Math.floor(sec/3600)} ч назад`;
    return `${Math.floor(sec/86400)} дн назад`;
  }
  function marketplaceSelectedShop() {
    const key=state.marketplace.selectedShopKey;
    return key ? marketplaceShops().find(shop=>String(shop.key)===String(key)) || null : null;
  }
  async function marketplaceFindShop(shop) {
    if (!shop) return;
    try {
      await action('marketplace.find',{page:'marketplace',uid:shop.uid,serverId:shop.serverId});
      showToast(`Маршрут к лавке №${shop.uid} установлен`,'success');
    } catch (err) {
      showToast(err.message==='wrong_server'?'Лавка находится на другом сервере':`Не удалось найти лавку: ${err.message}`,'error');
    }
  }
  function marketplaceOfferCard(shop, offer, side) {
    const row=div('', 'marketplace-offer-row');
    const main=div('', 'marketplace-offer-main');
    let iconBox=null;
    { iconBox=div('', 'marketplace-offer-icon'); const img=document.createElement('img'); img.alt=''; setIcon(img,offer,48); iconBox.append(img); }
    const copy=div('', 'marketplace-offer-copy'); copy.append(div(offer.name || 'Неизвестный предмет','marketplace-offer-name')); bindAveragePriceHover(copy,offer);
    const sub=div('', 'marketplace-offer-sub'); sub.textContent=`Лавка №${shop.uid} · ${shop.username || 'Незнакомец'} · ${shop.serverName || `Server ${shop.serverId}`}`; copy.append(sub);
    if (iconBox) main.append(iconBox);
    main.append(copy);
    const price=div('', 'marketplace-offer-price'); price.append(div(`${money(offer.price || 0)} ${marketplaceCurrency(shop.serverId)}`,'marketplace-offer-money'),div(`${money(offer.count || 0)} шт.`,'marketplace-offer-count'));
    const actionBtn=document.createElement('button'); actionBtn.type='button'; actionBtn.className='marketplace-offer-action';
    const same=Number(shop.serverId)===Number(marketplaceData().currentServerId);
    actionBtn.textContent=same?'Найти':'Открыть';
    actionBtn.addEventListener('click',event=>{event.stopPropagation(); if(same) marketplaceFindShop(shop); else {state.marketplace.selectedShopKey=shop.key; renderMarketplace();}});
    row.append(main,price,actionBtn);
    row.addEventListener('click',()=>{state.marketplace.selectedShopKey=shop.key; renderMarketplace();});
    return row;
  }
  function marketplaceSearchResults() {
    const q=normalizeName(state.marketplace.search);
    const buy=[],sell=[];
    if (!q) return {buy,sell};
    for (const shop of marketplaceShops()) {
      for (const offer of Array.isArray(shop.itemsBuy)?shop.itemsBuy:[]) if(normalizeName(offer.name).includes(q)) buy.push({shop,offer});
      for (const offer of Array.isArray(shop.itemsSell)?shop.itemsSell:[]) if(normalizeName(offer.name).includes(q)) sell.push({shop,offer});
    }
    const mode=Number(marketplaceData().sortMode || 0);
    if (mode===1 || mode===2) {
      const sign=mode===1?1:-1;
      const sorter=(a,b)=>(Number(a.offer.price||0)-Number(b.offer.price||0))*sign;
      buy.sort(sorter); sell.sort(sorter);
    }
    return {buy,sell};
  }
  function renderMarketplaceStatus(status) {
    refs.marketplaceStatus.innerHTML='';
    refs.marketplaceStatus.classList.toggle('hidden',status==='ready');
    if(status==='ready') return;
    const box=div('',`marketplace-status-card ${status}`);
    const icon=div('', 'marketplace-status-icon'); icon.innerHTML=iconSvg('market');
    const copy=div('', 'marketplace-status-copy');
    const title=document.createElement('h2'); const textNode=document.createElement('p');
    if(status==='auth') {
      title.textContent='Нужна авторизация';
      textNode.textContent='Привяжите Telegram или ВКонтакте через ArzMarket, затем обновите Маркетплейс.';
      const actions=div('', 'marketplace-status-actions');
      const tg=document.createElement('button'); tg.type='button'; tg.textContent='Привязать Telegram'; tg.addEventListener('click',()=>action('marketplace.auth.open',{page:'marketplace',provider:'telegram'}).catch(err=>showToast(err.message,'error')));
      const vk=document.createElement('button'); vk.type='button'; vk.textContent='Привязать ВКонтакте'; vk.addEventListener('click',()=>action('marketplace.auth.open',{page:'marketplace',provider:'vk'}).catch(err=>showToast(err.message,'error')));
      const lua=document.createElement('button'); lua.type='button'; lua.textContent='Ввести ключ в Lua'; lua.addEventListener('click',async()=>{ try { await action('ui.switch_mode',{page:'marketplace'}); } catch (err) { showToast(`Переключение на Lua: ${err.message}`,'error'); } });
      actions.append(tg,vk,lua); copy.append(title,textNode,actions);
    } else if(status==='blocked') {
      title.textContent='Доступ к Маркетплейсу ограничен';
      textNode.textContent='Проверьте уровень аккаунта, авторизацию и то, что вы находитесь на сервере Arizona RP.';
      copy.append(title,textNode);
    } else if(status==='setup_required') {
      title.textContent='Нужно подготовить список предметов';
      textNode.textContent='Откройте раздел «Скупка» и выполните сканирование списка предметов, затем вернитесь сюда.';
      const actions=div('', 'marketplace-status-actions'); const go=document.createElement('button'); go.type='button'; go.textContent='Перейти в Скупку'; go.addEventListener('click',()=>switchPage('buy')); actions.append(go); copy.append(title,textNode,actions);
    } else {
      title.textContent='Загрузка Маркетплейса';
      textNode.textContent='Получаю список лавок с сервера ArzMarket...';
      copy.append(title,textNode);
      box.classList.add('loading');
    }
    box.append(icon,copy); refs.marketplaceStatus.append(box);
  }
  function renderMarketplaceBrowse() {
    const shops=marketplaceShops(); refs.marketplaceCards.innerHTML='';
    const frag=document.createDocumentFragment();
    for (const shop of shops) {
      const card=div('',`marketplace-shop-card ${Number(shop.userStatus)>1?'premium':''}`.trim());
      const avatar=div('', 'marketplace-card-avatar'); avatar.innerHTML='<span class="marketplace-avatar-mark"></span>';
      const body=div('', 'marketplace-card-body');
      const top=div('', 'marketplace-card-top');
      const uid=document.createElement('button'); uid.type='button'; uid.className='marketplace-card-uid'; uid.textContent=`Лавка №${shop.uid}`;
      const same=Number(shop.serverId)===Number(marketplaceData().currentServerId); uid.disabled=!same; uid.title=same?'Поставить маршрут к лавке':'Лавка находится на другом сервере'; uid.addEventListener('click',event=>{event.stopPropagation(); marketplaceFindShop(shop);});
      top.append(uid); if(Number(shop.userStatus)>1) top.append(div('Premium','marketplace-premium-badge'));
      const owner=div(shop.username || 'Незнакомец','marketplace-card-owner');
      const stats=div('', 'marketplace-card-stats'); stats.innerHTML=`<span>Скупка: <strong>${(shop.itemsBuy||[]).length}</strong></span><span>Продажа: <strong>${(shop.itemsSell||[]).length}</strong></span>`;
      const meta=div('', 'marketplace-card-meta'); meta.append(div(`Сервер: ${shop.serverName || shop.serverId}`),div(`Обновлено: ${marketplaceAge(shop.updatedAt)}`));
      const openShop=()=>{state.marketplace.selectedShopKey=shop.key; renderMarketplace();};
      const view=document.createElement('button'); view.type='button'; view.className='marketplace-card-view'; view.textContent='Просмотреть лавку игрока'; view.addEventListener('click',openShop);
      body.append(top,owner,stats,meta,view); card.append(avatar,body);
      if (state.minimalMode) {
        card.classList.add('minimal-card-action');
        card.tabIndex=0;
        card.setAttribute('role','button');
        card.setAttribute('aria-label',`Открыть лавку №${shop.uid}`);
        card.addEventListener('click',event=>{if(!event.target.closest('button')) openShop();});
        card.addEventListener('keydown',event=>{if(event.key==='Enter'||event.key===' '){event.preventDefault();openShop();}});
      }
      frag.append(card);
    }
    refs.marketplaceCards.append(frag); refs.marketplaceBrowseEmpty.classList.toggle('hidden',shops.length>0); installWheelScroller(refs.marketplaceCards);
  }
  function renderMarketplaceSearch() {
    const results=marketplaceSearchResults();
    refs.marketplaceBuyResults.innerHTML=''; refs.marketplaceSellResults.innerHTML='';
    for (const row of results.buy) refs.marketplaceBuyResults.append(marketplaceOfferCard(row.shop,row.offer,'buy'));
    for (const row of results.sell) refs.marketplaceSellResults.append(marketplaceOfferCard(row.shop,row.offer,'sell'));
    refs.marketplaceBuyCount.textContent=money(results.buy.length); refs.marketplaceSellCount.textContent=money(results.sell.length);
    refs.marketplaceBuyEmpty.classList.toggle('hidden',results.buy.length>0); refs.marketplaceSellEmpty.classList.toggle('hidden',results.sell.length>0);
    installWheelScroller(refs.marketplaceBuyResults); installWheelScroller(refs.marketplaceSellResults);
  }
  function renderMarketplaceShopItems(node,items,shop) {
    node.innerHTML='';
    if(!items.length){node.append(div('Список пуст.','marketplace-shop-items-empty'));return;}
    for(const offer of items){
      const row=div('', 'marketplace-shop-item'); const left=div('', 'marketplace-shop-item-main');
      { const box=div('', 'marketplace-shop-item-icon'); const img=document.createElement('img'); img.alt=''; setIcon(img,offer,48); box.append(img); left.append(box); }
      const copy=div('', 'marketplace-shop-item-copy'); copy.append(div(offer.name || 'Неизвестный предмет','marketplace-shop-item-name'),div(`${money(offer.count||0)} шт.`,'marketplace-shop-item-count')); bindAveragePriceHover(copy,offer);
      left.append(copy); row.append(left,div(`${money(offer.price||0)} ${marketplaceCurrency(shop.serverId)}`,'marketplace-shop-item-price')); node.append(row);
    }
    installWheelScroller(node);
  }
  function renderMarketplaceShop(shop) {
    if(!shop) return;
    refs.marketplaceShopOwner.textContent=shop.username || 'Незнакомец'; refs.marketplaceShopUid.textContent=String(shop.uid||0); refs.marketplaceShopServer.textContent=shop.serverName || `Server ${shop.serverId}`;
    const buy=Array.isArray(shop.itemsBuy)?shop.itemsBuy:[], sell=Array.isArray(shop.itemsSell)?shop.itemsSell:[];
    refs.marketplaceShopItemsTotal.textContent=money(buy.length+sell.length); refs.marketplaceShopBuyCount.textContent=money(buy.length); refs.marketplaceShopSellCount.textContent=money(sell.length);
    const same=Number(shop.serverId)===Number(marketplaceData().currentServerId); refs.marketplaceFindShopButton.disabled=!same; refs.marketplaceFindShopButton.textContent=same?'Найти лавку':'Другой сервер'; refs.marketplaceFindShopButton.onclick=()=>marketplaceFindShop(shop);
    renderMarketplaceShopItems(refs.marketplaceShopBuyRows,buy,shop); renderMarketplaceShopItems(refs.marketplaceShopSellRows,sell,shop);
  }
  function renderMarketplace() {
    const data=marketplaceData(); const status=String(data.status || 'loading');
    refs.marketplaceShopCount.textContent=money(Number(data.shopCount ?? marketplaceShops().length));
    refs.marketplaceServerButton.textContent=data.selectedName || 'Все сервера';
    const sort=Number(data.sortMode||0); const sortLabels=['По умолчанию','Цена ↑','Цена ↓']; refs.marketplaceSortButton.querySelector('span:last-child').textContent=sortLabels[sort] || 'По умолчанию';
    renderMarketplaceStatus(status);
    const selected=marketplaceSelectedShop(); if(state.marketplace.selectedShopKey && !selected) state.marketplace.selectedShopKey=null;
    const searching=normalizeName(state.marketplace.search).length>0;
    refs.marketplaceBrowse.classList.toggle('hidden',status!=='ready' || searching || !!selected);
    refs.marketplaceSearchView.classList.toggle('hidden',status!=='ready' || !searching || !!selected);
    refs.marketplaceShopView.classList.toggle('hidden',status!=='ready' || !selected);
    if(status!=='ready') return;
    if(selected) renderMarketplaceShop(selected); else if(searching) renderMarketplaceSearch(); else renderMarketplaceBrowse();
  }

  const settingsValues = () => state.data?.data?.values || {};
  const settingsSnapshot = () => state.data?.data || {};

  async function saveSetting(key, value, successText = 'Настройка сохранена') {
    const values = settingsValues();
    const previous = values[key];
    values[key] = value;
    try {
      renderSettings();
      await action('settings.set', {page:'settings', key, value});
      showToast(successText, 'success');
      await refresh(true, 'settings');
      return true;
    } catch (err) {
      values[key] = previous;
      renderSettings();
      showToast(`Настройки: ${err.message}`, 'error');
      await refresh(true, 'settings').catch(() => {});
      return false;
    }
  }

  function settingsCard(title, subtitle = '') {
    const card = document.createElement('section');
    card.className = 'settings-card';
    const head = document.createElement('header');
    head.className = 'settings-card-head';
    const copy = document.createElement('div');
    const h = document.createElement('h2'); h.textContent = title; copy.append(h);
    head.append(copy); card.append(head);
    const body = document.createElement('div'); body.className = 'settings-card-body'; card.append(body);
    return {card, body, head};
  }

  function settingsToggle(body, key, label, description = '', options = {}) {
    const values = settingsValues();
    const row = document.createElement('div'); row.className = `settings-row ${options.indent ? 'settings-row-indent' : ''}`.trim();
    const copy = document.createElement('div'); copy.className = 'settings-row-copy';
    const title = document.createElement('strong'); title.textContent = label; copy.append(title);
    const toggle = document.createElement('button'); toggle.type = 'button'; toggle.className = `settings-toggle ${values[key] === true ? 'on' : ''}`; toggle.disabled = options.disabled === true;
    toggle.setAttribute('aria-pressed', values[key] === true ? 'true' : 'false'); toggle.innerHTML = '<span></span>';
    toggle.addEventListener('click', () => saveSetting(key, values[key] !== true));
    row.append(copy, toggle); body.append(row); return row;
  }

  function settingsInput(body, key, label, description = '', options = {}) {
    const values = settingsValues();
    const row = document.createElement('label'); row.className = `settings-row settings-input-row ${options.indent ? 'settings-row-indent' : ''}`.trim();
    const copy = document.createElement('div'); copy.className = 'settings-row-copy';
    const title = document.createElement('strong'); title.textContent = label; copy.append(title);
    const input = document.createElement('input'); input.className = 'settings-input'; input.type = options.type || 'text'; input.value = values[key] == null ? '' : String(values[key]);
    if (options.min != null) input.min = String(options.min); if (options.max != null) input.max = String(options.max); if (options.step != null) input.step = String(options.step);
    if (options.placeholder) input.placeholder = options.placeholder; if (options.password) input.type = 'password';
    input.addEventListener('change', () => saveSetting(key, options.number ? Number(input.value) : input.value));
    row.append(copy, input); body.append(row); return input;
  }

  function settingsRange(body, key, label, description, min, max, step = 1, suffix = '') {
    const values = settingsValues();
    const row = document.createElement('div'); row.className = 'settings-row settings-range-row';
    const copy = document.createElement('div'); copy.className = 'settings-row-copy';
    const title = document.createElement('strong'); title.textContent = label; copy.append(title);
    const control = document.createElement('div'); control.className = 'settings-range-control';
    const input = document.createElement('input'); input.type = 'range'; input.min = min; input.max = max; input.step = step; input.value = Number(values[key] ?? min);
    const value = document.createElement('span'); value.className = 'settings-range-value'; value.textContent = `${input.value}${suffix}`;
    input.addEventListener('input', () => { value.textContent = `${input.value}${suffix}`; });
    input.addEventListener('change', () => saveSetting(key, Number(input.value)));
    control.append(input, value); row.append(copy, control); body.append(row); return input;
  }

  function settingsActionButton(label, className = '') {
    const button = document.createElement('button'); button.type = 'button'; button.className = `settings-action ${className}`.trim(); button.textContent = label; return button;
  }

  function settingsModsData() {
    const mods = settingsSnapshot()?.mods;
    return mods && typeof mods === 'object' ? mods : {};
  }

  async function saveSettingsMod(key, value) {
    try {
      await action('mods.set', {page:'settings', key, value});
      await refresh(true, 'settings');
      return true;
    } catch (err) {
      showToast(`Основные: ${err.message}`, 'error');
      await refresh(true, 'settings').catch(() => {});
      return false;
    }
  }

  function settingsModToggle(body, key, label) {
    const row = document.createElement('div'); row.className = 'settings-row';
    const copy = document.createElement('div'); copy.className = 'settings-row-copy';
    const title = document.createElement('strong'); title.textContent = label; copy.append(title);
    const enabled = settingsModsData()[key] === true;
    const toggle = document.createElement('button'); toggle.type = 'button'; toggle.className = `settings-toggle ${enabled ? 'on' : ''}`;
    toggle.setAttribute('aria-pressed', enabled ? 'true' : 'false'); toggle.innerHTML = '<span></span>';
    toggle.addEventListener('click', () => saveSettingsMod(key, !enabled));
    row.append(copy, toggle); body.append(row); return row;
  }

  function renderSettingsGeneral(root) {
    const common = settingsCard('Общие функции');
    settingsToggle(common.body, 'buy_sell_history', 'Показывать процесс выставки товаров');
    settingsToggle(common.body, 'id_mode', 'Режим просмотра игроков через /id');
    if (settingsValues().premium_available) settingsToggle(common.body, 'premium_dialog', 'Премиум табличка с ценами');
    settingsToggle(common.body, 'auto_piar', 'Авто-пиар в чаты в игре');
    settingsToggle(common.body, 'lavka_helper', 'Помощник установки лавки');
    if (settingsValues().lavka_helper) {
      settingsToggle(common.body, 'lavka_helper_auto_disable', 'Автоматически отключать помощник после отхода', '', {indent:true});
      settingsRange(common.body, 'lavka_helper_radius', 'Радиус зоны установки', '', 5, 50, 1, '');
    }
    root.append(common.card);

    const display = settingsCard('Отображение');
    settingsModToggle(display.body, 'remove_players', 'Удалять других игроков');
    settingsModToggle(display.body, 'remove_vehicles', 'Удалять транспорт');
    root.append(display.card);

    const cycle = settingsCard('Автоцикл');
    settingsModToggle(cycle.body, 'auto_cycle', 'Автоцикл');
    const mods = settingsModsData();
    const manual = settingsActionButton(mods.manual_purchased_running === true ? 'Остановить ручное выставление' : 'Выставить скупленные товары', mods.manual_purchased_running === true ? 'danger' : 'primary');
    manual.disabled = mods.trade_busy === true && mods.manual_purchased_running !== true;
    manual.addEventListener('click', async () => {
      try {
        manual.disabled = true;
        const result = await action('mods.manual_purchased', {page:'settings'});
        showToast(result.state === 'stopped' ? 'Ручное выставление остановлено' : 'Ручное выставление запущено', 'success');
        await refresh(true, 'settings');
      } catch (err) {
        showToast(`Автоцикл: ${err.message}`, 'error');
        await refresh(true, 'settings').catch(() => {});
      }
    });
    cycle.body.append(manual);
    root.append(cycle.card);

    const community = settingsCard('Канал разработки ArzMarket');
    const telegram = settingsActionButton('Открыть Telegram');
    telegram.addEventListener('click', () => action('mods.telegram', {page:'settings'}).catch(err => showToast(`Telegram: ${err.message}`, 'error')));
    community.body.append(telegram);
    root.append(community.card);
  }

  function renderSettingsTrade(root) {
    const finance = settingsCard('Финансы');
    settingsInput(finance.body, 'buy_vc', 'Курс покупки VC$', '', {type:'number', min:1, step:1, number:true});
    settingsInput(finance.body, 'sell_vc', 'Курс продажи VC$', '', {type:'number', min:1, step:1, number:true});
    settingsInput(finance.body, 'sell_percent', 'Ваша комиссия в %', '', {type:'number', min:0, step:1, number:true});
    root.append(finance.card);

    const currency = settingsCard('Валюта');
    settingsToggle(currency.body, 'always_convert', 'Всегда конвертировать VC$/SA$', 'Автоматически переводит цены между валютами');
    if (settingsValues().always_convert) settingsToggle(currency.body, 'always_convert_once', 'Конвертировать только 1 раз', 'После первой конвертации режим автоматически отключается', {indent:true});
    root.append(currency.card);

    const trade = settingsCard('Трейды и лавка');
    settingsToggle(trade.body, 'trader_chat', 'Чат с трейдером', 'Показывает интерфейс общения во время трейда');
    settingsToggle(trade.body, 'trade_auto_accept', 'Авто принятие трейда', 'Автоматически принимает подходящие предложения торговли');
    settingsToggle(trade.body, 'auto_lavka_name', 'Автоматически называть лавку', 'Подставляет сохраненное название при установке лавки');
    if (settingsValues().auto_lavka_name) settingsInput(trade.body, 'lavka_name', 'Название лавки', 'Название применяется при следующей установке', {indent:true, placeholder:'Название лавки'});
    root.append(trade.card);

    const prices = settingsCard('Цены и производительность');
    settingsToggle(prices.body, 'avg_price', 'Отображение средних цен', 'Включает подсказки со средними ценами предметов');
    if (settingsValues().avg_price) settingsToggle(prices.body, 'avg_price_new_window', 'Новое окно цен', 'Использует новый интерфейс информации о средних ценах', {indent:true});
    settingsToggle(prices.body, 'fps_up_sell', 'FPS Up при выставлении товаров', 'Уменьшает лишнюю отрисовку во время автоматической торговли');
    root.append(prices.card);
  }

  function renderSettingsAutomation(root) {
    const mascot = settingsCard('Спутники');
    settingsToggle(mascot.body, 'satellites', 'Система спутников');
    root.append(mascot.card);
  }

  function renderSettingsTelegram(root) {
    const master = settingsCard('Telegram уведомления', 'Уведомления отправляются через текущую Lua-систему ArzMarket');
    settingsToggle(master.body, 'telegram_notifications', 'Телеграмм уведомления', 'Главный переключатель отправки уведомлений');
    if (settingsValues().telegram_notifications) {
      settingsInput(master.body, 'tg_token', 'Token', 'Токен Telegram-бота', {indent:true, password:true, placeholder:'Bot token'});
      settingsInput(master.body, 'tg_chat_id', 'ChatID', 'ID чата, куда отправляются уведомления', {indent:true, placeholder:'Chat ID'});
      settingsToggle(master.body, 'telegram_reserve', 'Резервная ссылка Telegram', 'Используется при блокировке основного Telegram API', {indent:true});
      const buttons = document.createElement('div'); buttons.className = 'settings-inline-actions';
      const test = settingsActionButton('Проверить соединение');
      test.addEventListener('click', async () => { try { await action('settings.telegram.test', {page:'settings'}); showToast('Тестовое уведомление отправлено', 'success'); } catch (err) { showToast(`Telegram: ${err.message}`, 'error'); } });
      buttons.append(test); master.body.append(buttons);
    }
    root.append(master.card);

    if (settingsValues().telegram_notifications) {
      const notices = settingsCard('Какие события отправлять', 'Каждый пункт использует существующую Lua-логику уведомлений');
      const rows = [
        ['tg_lavka_destroy','Лавку удалили'],['tg_lavka_build','Лавка установлена или арендована'],['tg_developers','Уведомления разработчиков'],
        ['tg_buy_sell','Покупка и продажа'],['tg_stats','Статистика за день'],['tg_lavka_status','Слетевшая лавка'],['tg_death','Смерть персонажа'],
        ['tg_pm','Сообщения в /pm'],['tg_connect','Кик и вход'],['tg_wrong_password','Неверный пароль'],['tg_full_spawn','Полный спавн после авторизации'],
        ['tg_taxes','Оплата налогов'],['tg_payday','PayDay'],['tg_bank','Банковские переводы']
      ];
      for (const [key,label] of rows) {
        if (key === 'tg_stats' && !settingsValues().tg_buy_sell) continue;
        if ((key === 'tg_wrong_password' || key === 'tg_full_spawn') && !settingsValues().tg_connect) continue;
        settingsToggle(notices.body, key, label, '', {indent:key==='tg_stats' || key==='tg_wrong_password' || key==='tg_full_spawn'});
      }
      root.append(notices.card);
    }

    const ad = settingsCard('Telegram реклама', 'Отдельный Node.js бот для автоматической рекламы');
    settingsToggle(ad.body, 'telegram_ads', 'Телеграмм реклама', 'Включает существующую систему ArzMarket_TgBot');
    const values = settingsValues();
    const status = document.createElement('div'); status.className = `settings-status-line ${values.tg_ad_config_exists ? 'ok' : 'warn'}`;
    status.textContent = values.tg_ad_config_exists ? 'Конфиг Telegram-бота найден' : values.tg_ad_script_exists ? 'Скрипт найден, но config.json еще не создан' : 'ArzMarket_TgBot еще не установлен'; ad.body.append(status);
    if (values.tg_ad_config_exists) {
      settingsInput(ad.body, 'tg_ad_api_id', 'API_ID', 'App ID с my.telegram.org', {type:'number', min:0, number:true});
      settingsInput(ad.body, 'tg_ad_api_hash', 'API_HASH', 'ApiHash Telegram приложения');
      settingsInput(ad.body, 'tg_ad_interval', 'Задержка рекламы', 'Интервал между рекламными сообщениями в секундах', {type:'number', min:1, step:1, number:true});
      settingsToggle(ad.body, 'tg_ad_save_session', 'Сохранение Telegram-сессии', 'После первого входа повторная авторизация не потребуется');
    }
    root.append(ad.card);
  }

  function renderSettingsAppearance(root) {
    const appearance = settingsSnapshot().appearance || {};
    const global = Object.assign({enabled:false,base:'#4B8DFF',depth:72,saturation:82,contrast:72,glow:80,picker_hue:null,picker_saturation:null,picker_value:null,tokens:null}, appearance.global_palette || {});
    global.base=themeNormalizeHex(global.base);

    const globalCard = settingsCard('Единая палитра всего скрипта', 'Настоящая цветовая палитра. Один выбранный цвет автоматически перестраивает Lua и HTML');
    globalCard.card.classList.add('settings-global-palette-card','settings-appearance-global');
    const paletteTop = document.createElement('div'); paletteTop.className='settings-palette-top settings-global-palette-top';
    const paletteTitle=document.createElement('div'); paletteTitle.className='settings-row-copy'; paletteTitle.innerHTML='<strong>Использовать единую палитру</strong><small>Квадрат меняет насыщенность и яркость, полоса справа меняет оттенок. Изменения сразу видны на всём HTML-интерфейсе.</small>';
    const paletteToggle=document.createElement('button'); paletteToggle.type='button'; paletteToggle.className=`settings-toggle ${global.enabled?'on':''}`; paletteToggle.innerHTML='<span></span>'; paletteToggle.setAttribute('aria-pressed',global.enabled?'true':'false');
    paletteTop.append(paletteTitle,paletteToggle); globalCard.body.append(paletteTop);

    let saveTimer=0;
    const payloadFor = next => ({page:'settings',enabled:next.enabled===true,base:themeNormalizeHex(next.base),depth:Number(next.depth),saturation:Number(next.saturation),contrast:Number(next.contrast),glow:Number(next.glow),picker_hue:themeClamp01(next.picker_hue),picker_saturation:themeClamp01(next.picker_saturation),picker_value:themeClamp01(next.picker_value),reset:next.reset===true});
    const applyLiveGlobal = () => {
      global.base=themeNormalizeHex(global.base);
      global.tokens=buildGlobalPaletteTokens(global);
      if (global.enabled) {
        applyHtmlTheme('global_palette',Object.assign({},global,{enabled:true,tokens:global.tokens,glow:Number(global.glow)||0}));
      } else {
        const datasetKey=String(refs.app?.dataset?.htmlTheme || '');
        const liveThemeKey=(datasetKey && datasetKey!=='global_palette') ? datasetKey : String(appearance.palette_key || 'arzmarket_default');
        applyHtmlTheme(liveThemeKey,{enabled:false,glow:Number(global.glow)||0});
      }
    };
    const sendGlobal = async (patch, refreshAfter=true) => {
      Object.assign(global,patch||{});
      global.base=themeNormalizeHex(global.base);
      applyLiveGlobal();
      try {
        await action('settings.global_palette.update',payloadFor(global));
        if (refreshAfter) await refresh(true,'settings');
      } catch(err) { showToast(`Палитра: ${err.message}`,'error'); }
    };
    const scheduleGlobalSave = patch => {
      Object.assign(global,patch||{});
      global.base=themeNormalizeHex(global.base);
      applyLiveGlobal();
      clearTimeout(saveTimer);
      saveTimer=window.setTimeout(()=>{ void sendGlobal({},false); },180);
    };
    paletteToggle.addEventListener('click',()=>sendGlobal({enabled:!global.enabled},true));

    const pickerShell=document.createElement('div');pickerShell.className='settings-global-picker-shell';
    const pickerMain=document.createElement('div');pickerMain.className='settings-global-picker-main';
    const sv=document.createElement('div');sv.className='settings-global-sv';sv.setAttribute('role','slider');sv.setAttribute('aria-label','Насыщенность и яркость');
    const svMarker=document.createElement('i');svMarker.className='settings-global-sv-marker';sv.append(svMarker);
    const hue=document.createElement('div');hue.className='settings-global-hue';hue.setAttribute('role','slider');hue.setAttribute('aria-label','Оттенок');
    const hueMarker=document.createElement('i');hueMarker.className='settings-global-hue-marker';hue.append(hueMarker);
    pickerMain.append(sv,hue);

    const pickerInfo=document.createElement('div');pickerInfo.className='settings-global-picker-info';
    const currentLabel=document.createElement('strong');currentLabel.textContent='Текущий цвет';
    const currentSwatch=document.createElement('div');currentSwatch.className='settings-global-current-swatch';
    const hexLabel=document.createElement('label');hexLabel.className='settings-global-hex-label';hexLabel.textContent='HEX';
    const colorHex=document.createElement('input');colorHex.type='text';colorHex.className='settings-input settings-global-color-hex';colorHex.maxLength=7;colorHex.spellcheck=false;colorHex.value=global.base;
    hexLabel.append(colorHex);
    const rgbText=document.createElement('div');rgbText.className='settings-global-rgb';
    const pickerHint=document.createElement('p');pickerHint.className='settings-global-picker-hint';pickerHint.textContent='Выбери цвет мышкой. Оттенок задаётся вертикальной радугой, а квадратом регулируются насыщенность и яркость.';
    pickerInfo.append(currentLabel,currentSwatch,hexLabel,rgbText,pickerHint);
    pickerShell.append(pickerMain,pickerInfo);globalCard.body.append(pickerShell);

    const baseHsv=themeRgbToHsv(themeHexRgb(global.base));
    let pickerHsv={
      h:Number.isFinite(Number(global.picker_hue))?themeClamp01(global.picker_hue):baseHsv.h,
      s:Number.isFinite(Number(global.picker_saturation))?themeClamp01(global.picker_saturation):baseHsv.s,
      v:Number.isFinite(Number(global.picker_value))?themeClamp01(global.picker_value):baseHsv.v
    };
    global.picker_hue=pickerHsv.h; global.picker_saturation=pickerHsv.s; global.picker_value=pickerHsv.v;
    const getPickerHsv = () => ({h:pickerHsv.h,s:pickerHsv.s,v:pickerHsv.v});
    const updatePickerUi = () => {
      const hsv=getPickerHsv();
      const hueRgb=themeRgbHex(themeHsvToRgb(hsv.h,1,1));
      sv.style.setProperty('--picker-hue',hueRgb);
      svMarker.style.left=`${(hsv.s*100).toFixed(2)}%`;
      svMarker.style.top=`${((1-hsv.v)*100).toFixed(2)}%`;
      hueMarker.style.top=`${(hsv.h*100).toFixed(2)}%`;
      currentSwatch.style.background=global.base;
      colorHex.value=global.base;
      const rgb=themeHexRgb(global.base);
      rgbText.textContent=`RGB: ${rgb.r}, ${rgb.g}, ${rgb.b}`;
    };
    const setBaseFromHsv = hsv => {
      pickerHsv={h:themeClamp01(hsv.h),s:themeClamp01(hsv.s),v:themeClamp01(hsv.v)};
      global.picker_hue=pickerHsv.h;
      global.picker_saturation=pickerHsv.s;
      global.picker_value=pickerHsv.v;
      global.base=themeRgbHex(themeHsvToRgb(pickerHsv.h,pickerHsv.s,pickerHsv.v)).toUpperCase();
      updatePickerUi();
      applyLiveGlobal();
    };
    const pointerValue=(event,node)=>{
      const rect=node.getBoundingClientRect();
      return {x:themeClamp01((event.clientX-rect.left)/Math.max(1,rect.width)),y:themeClamp01((event.clientY-rect.top)/Math.max(1,rect.height))};
    };
    const bindDrag=(node,onMove)=>{
      node.addEventListener('mousedown',event=>{
        if (event.button!==0) return;
        event.preventDefault();
        state.settings.paletteDragging=true;
        clearTimeout(saveTimer);
        const move=e=>{e.preventDefault();onMove(e);};
        const up=e=>{
          if(e) e.preventDefault();
          window.removeEventListener('mousemove',move);
          window.removeEventListener('mouseup',up);
          state.settings.paletteDragging=false;
          clearTimeout(saveTimer);
          void sendGlobal({base:global.base,picker_hue:pickerHsv.h,picker_saturation:pickerHsv.s,picker_value:pickerHsv.v},false);
        };
        onMove(event);
        window.addEventListener('mousemove',move);
        window.addEventListener('mouseup',up);
      });
    };
    bindDrag(sv,event=>{const pos=pointerValue(event,sv),hsv=getPickerHsv();setBaseFromHsv({h:hsv.h,s:pos.x,v:1-pos.y});});
    bindDrag(hue,event=>{const pos=pointerValue(event,hue),hsv=getPickerHsv();setBaseFromHsv({h:pos.y,s:hsv.s,v:hsv.v});});
    colorHex.addEventListener('change',()=>{
      const value=String(colorHex.value||'').trim().toUpperCase();
      if(!/^#[0-9A-F]{6}$/.test(value)){colorHex.value=global.base;showToast('Цвет должен быть в формате #RRGGBB','error');return;}
      global.base=value;
      pickerHsv=themeRgbToHsv(themeHexRgb(value));
      global.picker_hue=pickerHsv.h;global.picker_saturation=pickerHsv.s;global.picker_value=pickerHsv.v;
      updatePickerUi();void sendGlobal({base:value,picker_hue:pickerHsv.h,picker_saturation:pickerHsv.s,picker_value:pickerHsv.v},false);
    });
    colorHex.addEventListener('keydown',event=>{if(event.key==='Enter'){event.preventDefault();colorHex.blur();}});
    updatePickerUi();

    const modifiersTitle=document.createElement('div');modifiersTitle.className='settings-global-modifiers-title';modifiersTitle.innerHTML='<strong>Дополнительная обработка цвета</strong><small>Эти параметры не заменяют палитру. Они меняют то, как выбранный цвет раскладывается на фон, панели, границы и активные элементы.</small>';globalCard.body.append(modifiersTitle);
    const addGlobalRange=(key,label,description,min,max,suffix='%')=>{
      const row=document.createElement('div');row.className='settings-row settings-range-row settings-global-range-row';
      const copy=document.createElement('div');copy.className='settings-row-copy';const title=document.createElement('strong');title.textContent=label;const hint=document.createElement('small');hint.textContent=description;copy.append(title,hint);
      const control=document.createElement('div');control.className='settings-range-control';
      const input=document.createElement('input');input.type='range';input.min=String(min);input.max=String(max);input.step='1';input.value=String(Number(global[key]??min));
      const value=document.createElement('span');value.className='settings-range-value';value.textContent=`${input.value}${suffix}`;
      let manualDrag=false;
      const setRangeValue = rawValue => {
        const step=Math.max(0.000001,Number(input.step)||1);
        const low=Number(input.min)||0, high=Number(input.max)||100;
        const clamped=Math.max(low,Math.min(high,Number(rawValue)||0));
        const next=Math.round((clamped-low)/step)*step+low;
        input.value=String(Math.max(low,Math.min(high,next)));
        const numeric=Number(input.value);
        value.textContent=`${input.value}${suffix}`;
        global[key]=numeric;
        applyLiveGlobal();
      };
      const setRangeFromPointer = event => {
        const rect=input.getBoundingClientRect();
        const ratio=themeClamp01((Number(event.clientX)-rect.left)/Math.max(1,rect.width));
        setRangeValue((Number(input.min)||0)+ratio*((Number(input.max)||100)-(Number(input.min)||0)));
      };
      input.addEventListener('mousedown',event=>{
        if(event.button!==0) return;
        event.preventDefault();
        input.focus({preventScroll:true});
        manualDrag=true;
        state.settings.paletteDragging=true;
        clearTimeout(saveTimer);
        setRangeFromPointer(event);
        const move=e=>{if(!manualDrag)return;e.preventDefault();setRangeFromPointer(e);};
        const up=e=>{
          if(!manualDrag)return;
          if(e)e.preventDefault();
          manualDrag=false;
          window.removeEventListener('mousemove',move,true);
          window.removeEventListener('mouseup',up,true);
          state.settings.paletteDragging=false;
          clearTimeout(saveTimer);
          void sendGlobal({[key]:Number(input.value)},false);
        };
        window.addEventListener('mousemove',move,true);
        window.addEventListener('mouseup',up,true);
      });
      input.addEventListener('input',()=>{
        if(manualDrag)return;
        value.textContent=`${input.value}${suffix}`;
        global[key]=Number(input.value);
        applyLiveGlobal();
        scheduleGlobalSave({[key]:Number(input.value)});
      });
      input.addEventListener('change',()=>{if(manualDrag)return;clearTimeout(saveTimer);void sendGlobal({[key]:Number(input.value)},false);});
      control.append(input,value);row.append(copy,control);
      if (key === 'glow') row.dataset.baronAnchor = 'settings_glow';
      globalCard.body.append(row);
    };
    addGlobalRange('depth','Глубина','Насколько тёмными будут фон и панели.',0,100);
    addGlobalRange('saturation','Интенсивность цвета','Насколько сильно выбранный цвет влияет на весь интерфейс.',0,100);
    addGlobalRange('contrast','Контраст','Насколько заметно разделяются фон, панели, рамки и активные элементы.',0,100);
    addGlobalRange('glow','Свечение','Сила подсветки кнопок, рамок и активных состояний.',0,100);

    const resetGlobal=settingsActionButton('Сбросить единую палитру');resetGlobal.addEventListener('click',()=>sendGlobal({reset:true,base:'#4B8DFF',depth:72,saturation:82,contrast:72,glow:80},true));globalCard.body.append(resetGlobal);
    root.append(globalCard.card);

    const themes = Array.isArray(appearance.themes) ? appearance.themes : [];
    const themeCard = settingsCard('Готовые темы', 'Готовые темы меняют и Lua, и HTML');
    themeCard.card.dataset.baronAnchor = 'settings_themes';
    themeCard.card.classList.add('settings-appearance-themes');
    const themeGrid = document.createElement('div'); themeGrid.className = 'settings-theme-grid';
    for (const theme of themes) {
      const button = document.createElement('button'); button.type='button'; button.className=`settings-theme ${theme.selected&&!global.enabled?'active':''}`;
      button.style.setProperty('--theme-accent', theme.accent || '#42d69b');
      button.innerHTML = `<span class="settings-theme-dot"></span><span><strong>${text(theme.label)}</strong></span>`;
      button.addEventListener('click', async () => { const previous=refs.app?.dataset.htmlTheme || 'arzmarket_default'; const previousProfile=state.data?.common?.htmlThemeProfile || appearance.global_palette || null; applyHtmlTheme(theme.key,{enabled:false,glow:Number(global.glow)||0}); try { await action('settings.theme.select',{page:'settings',key:theme.key}); showToast(`Тема: ${theme.label}`,'success'); await refresh(true,'settings'); } catch(err){ applyHtmlTheme(previous,previousProfile); showToast(`Тема: ${err.message}`,'error'); } });
      themeGrid.append(button);
    }
    themeCard.body.append(themeGrid); root.append(themeCard.card);

    const ui = settingsCard('Интерфейс Lua', 'Параметры старого mimgui-интерфейса сохраняются в тех же конфигурациях');
    ui.card.classList.add('settings-appearance-lua');
    settingsToggle(ui.body,'background_blur','Размытие фона за меню','Размывает игровую сцену за Lua-окном ArzMarket');
    settingsToggle(ui.body,'button_style','Стиль переключателей','Альтернативное оформление ToggleButton');
    settingsToggle(ui.body,'border_side','Включить обводку элементов','Показывает границы полей и контролов');
    settingsToggle(ui.body,'rgb_window','RGB обводка меню','Динамическая радужная обводка окна');
    settingsToggle(ui.body,'smooth_open','Плавное открытие меню','Анимация прозрачности при открытии');
    settingsRange(ui.body,'menu_opacity_percent','Прозрачность меню','',20,100,1,'%');
    settingsRange(ui.body,'rainbow_speed','Скорость RGB','',0.1,10,0.1,'');
    settingsRange(ui.body,'blur_strength','Сила размытия','',0,10,0.1,'');
    const scaleRow=document.createElement('div');scaleRow.className='settings-row settings-scale-row';const copy=document.createElement('div');copy.className='settings-row-copy';copy.innerHTML='<strong>Размер интерфейса</strong>';
    const control=document.createElement('div');control.className='settings-scale-control';const range=document.createElement('input');range.type='range';range.min='100';range.max='150';range.step='1';range.value=String(state.settings.pendingScale ?? settingsValues().menu_scale_percent ?? 120);const val=document.createElement('span');val.className='settings-range-value';val.textContent=`${range.value}%`;const apply=settingsActionButton('Применить','small');range.addEventListener('input',()=>{state.settings.pendingScale=Number(range.value);val.textContent=`${range.value}%`;});apply.addEventListener('click',async()=>{try{await action('settings.scale.apply',{page:'settings',value:Number(range.value)});showToast('Размер сохранён. Интерфейс перезагружается.','success');}catch(err){showToast(`Размер: ${err.message}`,'error');}});control.append(range,val,apply);scaleRow.append(copy,control);ui.body.append(scaleRow);
    root.append(ui.card);

    const custom = settingsCard('Точная палитра Lua', 'Ручная настройка отдельных цветов старого Lua-интерфейса');
    custom.card.classList.add('settings-appearance-custom');
    const enabled = appearance.custom_enabled === true;
    const top = document.createElement('div'); top.className='settings-palette-top';
    const customToggle=document.createElement('button');customToggle.type='button';customToggle.className=`settings-toggle ${enabled?'on':''}`;customToggle.innerHTML='<span></span>';customToggle.addEventListener('click',async()=>{try{await action('settings.palette.enable',{page:'settings',value:!enabled});await refresh(true,'settings');}catch(err){showToast(`Палитра: ${err.message}`,'error');}});
    const titleWrap=document.createElement('div');titleWrap.className='settings-row-copy';titleWrap.innerHTML='<strong>Включить точную палитру Lua</strong>';top.append(titleWrap,customToggle);custom.body.append(top);
    const groups = Array.isArray(appearance.custom_groups) ? appearance.custom_groups : [];
    for (const group of groups) {
      const groupBox=document.createElement('div');groupBox.className='settings-color-group';
      const head=document.createElement('div');head.className='settings-color-group-head';const h=document.createElement('strong');h.textContent=group.label;const reset=settingsActionButton('Сбросить группу','small');reset.addEventListener('click',async()=>{await action('settings.palette.reset',{page:'settings',scope:'group',key:group.key}).catch(err=>showToast(`Палитра: ${err.message}`,'error'));await refresh(true,'settings');});head.append(h,reset);groupBox.append(head);
      for (const target of (group.targets || [])) {
        const row=document.createElement('label');row.className='settings-color-row';const label=document.createElement('span');label.textContent=target.label;
        const swatch=document.createElement('span');swatch.className='settings-color-swatch';swatch.style.background=(target.hex || '#000000').slice(0,7);
        const input=document.createElement('input');input.className='settings-color-input';input.value=target.hex || '#000000';input.addEventListener('change',async()=>{try{await action('settings.palette.color',{page:'settings',key:target.key,hex:input.value});await refresh(true,'settings');}catch(err){showToast(`Цвет: ${err.message}`,'error');}});
        const resetOne=settingsActionButton('↺','icon');resetOne.type='button';resetOne.addEventListener('click',async e=>{e.preventDefault();await action('settings.palette.reset',{page:'settings',scope:'target',key:target.key}).catch(err=>showToast(`Цвет: ${err.message}`,'error'));await refresh(true,'settings');});
        row.append(label,swatch,input,resetOne);groupBox.append(row);
      }
      custom.body.append(groupBox);
    }
    const resetAll=settingsActionButton('Сбросить всё к теме');resetAll.addEventListener('click',async()=>{await action('settings.palette.reset',{page:'settings',scope:'all'}).catch(err=>showToast(`Палитра: ${err.message}`,'error'));await refresh(true,'settings');});custom.body.append(resetAll);
    root.append(custom.card);
  }

  function renderSettingsConfigs(root) {
    const configs = settingsSnapshot().configs || {};
    const grid = document.createElement('div'); grid.className='settings-config-grid';
    const renderSide = side => {
      const data = configs[side] || {items:[],loaded:''};
      const card = settingsCard(side==='sell'?'Продажа':'Скупка', side==='sell'?'Конфиги автоматической продажи':'Конфиги автоматической скупки');
      const list=document.createElement('div');list.className='settings-config-list';
      for (const item of (Array.isArray(data.items)?data.items:[])) {
        const row=document.createElement('div');row.className=`settings-config-row ${item.loaded?'loaded':''}`;
        const copy=document.createElement('div');copy.className='settings-config-copy';const name=document.createElement('strong');name.textContent=item.base || item.name;const meta=document.createElement('small');meta.textContent=item.format==='json'?`${item.item_count||0} товаров${item.loaded?' • загружен':''}`:'Старый формат .cfg';copy.append(name,meta);
        const actions=document.createElement('div');actions.className='settings-config-actions';
        if (item.format==='json') {
          const load=settingsActionButton(item.loaded?'Загружен':'Загрузить','small');load.disabled=!!item.loaded;load.addEventListener('click',async()=>{try{await action('trade.config.load',{side,name:item.name});showToast(`Конфиг ${item.base} загружен`,'success');await refresh(true,'settings');}catch(err){showToast(`Конфиг: ${err.message}`,'error');}});actions.append(load);
          const del=settingsActionButton('Удалить','small danger');let armed=false;del.addEventListener('click',async()=>{if(!armed){armed=true;del.textContent='Точно?';setTimeout(()=>{armed=false;if(del.isConnected)del.textContent='Удалить';},2200);return;}try{await action('settings.config.delete',{page:'settings',side,name:item.name});showToast('Конфиг удален','success');await refresh(true,'settings');}catch(err){showToast(`Удаление: ${err.message}`,'error');}});actions.append(del);
          if (side==='buy') {const select=settingsActionButton(state.settings.mergeSelected.has(item.name)?'Выбран':'В объединение','small');select.classList.toggle('selected',state.settings.mergeSelected.has(item.name));select.addEventListener('click',()=>{state.settings.mergeSelected.has(item.name)?state.settings.mergeSelected.delete(item.name):state.settings.mergeSelected.add(item.name);renderSettings();});actions.prepend(select);}
        } else {
          const convert=settingsActionButton('Конвертировать','small');convert.addEventListener('click',async()=>{try{await action('settings.config.convert',{page:'settings',side,name:item.name});showToast('Старый конфиг конвертирован','success');await refresh(true,'settings');}catch(err){showToast(`Конвертация: ${err.message}`,'error');}});actions.append(convert);
        }
        row.append(copy,actions);list.append(row);
      }
      if (!list.children.length) list.append(div('Конфиги не найдены','settings-config-empty'));
      card.body.append(list);
      const create=document.createElement('div');create.className='settings-config-create';const input=document.createElement('input');input.className='settings-input';input.placeholder='Название конфига';const btn=settingsActionButton('Создать','primary');btn.addEventListener('click',async()=>{if(!input.value.trim())return;try{await action('settings.config.create',{page:'settings',side,name:input.value});input.value='';showToast('Конфиг создан','success');await refresh(true,'settings');}catch(err){showToast(`Создание: ${err.message}`,'error');}});create.append(input,btn);card.body.append(create);
      if (side==='buy') {
        const merge=document.createElement('div');merge.className='settings-config-merge';const title=document.createElement('strong');title.textContent=`Объединение конфигов. Выбрано: ${state.settings.mergeSelected.size}`;const inputM=document.createElement('input');inputM.className='settings-input';inputM.placeholder='Название объединенного конфига';const actionsM=document.createElement('div');actionsM.className='settings-inline-actions';const createM=settingsActionButton('Создать из выбранных','primary');createM.disabled=state.settings.mergeSelected.size<2;createM.addEventListener('click',async()=>{if(!inputM.value.trim())return;try{await action('settings.config.merge',{page:'settings',name:inputM.value,files:[...state.settings.mergeSelected]});state.settings.mergeSelected.clear();showToast('Объединенный конфиг создан','success');await refresh(true,'settings');}catch(err){showToast(`Объединение: ${err.message}`,'error');}});const clear=settingsActionButton('Сбросить выбор');clear.disabled=!state.settings.mergeSelected.size;clear.addEventListener('click',()=>{state.settings.mergeSelected.clear();renderSettings();});actionsM.append(createM,clear);merge.append(title,inputM,actionsM);card.body.append(merge);
      }
      grid.append(card.card);
    };
    renderSide('sell'); renderSide('buy'); root.append(grid);
  }

  function renderSettings() {
    if (!refs.settingsContent) return;
    refs.settingsContent.dataset.section = state.settings.section || 'general';
    refs.settingsContent.innerHTML='';
    refs.settingsToolbar?.querySelectorAll('[data-settings-section]').forEach(btn=>btn.classList.toggle('active',btn.dataset.settingsSection===state.settings.section));
    const root=document.createDocumentFragment();
    if (state.settings.section==='trade') renderSettingsTrade(root);
    else if (state.settings.section==='automation') renderSettingsAutomation(root);
    else if (state.settings.section==='telegram') renderSettingsTelegram(root);
    else if (state.settings.section==='appearance') renderSettingsAppearance(root);
    else if (state.settings.section==='configs') renderSettingsConfigs(root);
    else renderSettingsGeneral(root);
    refs.settingsContent.append(root);
    installWheelScroller(refs.settingsContent);
  }

  function renderMods() {
    if (!refs.modsWorkspace) return;
    refs.modsWorkspace.querySelectorAll('[data-mods-section]').forEach(button => {
      const active = button.dataset.modsSection === state.modsSection;
      button.classList.toggle('active', active);
      button.setAttribute('aria-selected', active ? 'true' : 'false');
    });
    // Content intentionally stays empty for both sections until their functionality is implemented.
  }

  function render() {
    renderHeader();
    const settings = state.page === 'settings';
    const logs = state.page === 'logs';
    const marketplace = state.page === 'marketplace';
    const mods = state.page === 'mods';
    const storage = state.page === 'storage';
    const buy = state.page === 'buy';
    const sell = state.page === 'sell';
    refs.settingsToolbar?.classList.toggle('hidden', !settings);
    refs.settingsWorkspace?.classList.toggle('hidden', !settings);
    refs.logsToolbar?.classList.toggle('hidden', !logs);
    refs.logsWorkspace?.classList.toggle('hidden', !logs);
    refs.marketplaceToolbar?.classList.toggle('hidden', !marketplace);
    refs.marketplaceWorkspace?.classList.toggle('hidden', !marketplace);
    refs.modsWorkspace?.classList.toggle('hidden', !mods);
    refs.storageToolbar?.classList.toggle('hidden', !storage);
    refs.storageWorkspace?.classList.toggle('hidden', !storage);
    refs.mainWorkspace?.classList.toggle('hidden', !buy);
    refs.sellWorkspace?.classList.toggle('hidden', !sell);
    if (toolbar) toolbar.classList.toggle('hidden', settings || logs || marketplace || mods || storage);
    if (settings) {
      setTradeFilterOpen(false);
      refs.globalSearchResults.classList.add('hidden');
      renderSettings();
      return;
    }
    if (mods) {
      setTradeFilterOpen(false);
      refs.globalSearchResults.classList.add('hidden');
      renderMods();
      return;
    }
    if (marketplace) {
      setTradeFilterOpen(false);
      refs.globalSearchResults.classList.add('hidden');
      renderMarketplace();
      return;
    }
    if (storage) {
      setTradeFilterOpen(false);
      refs.globalSearchResults.classList.add('hidden');
      renderStorage();
      return;
    }
    if (logs) {
      setTradeFilterOpen(false);
      refs.globalSearchResults.classList.add('hidden');
      renderLogs();
      return;
    }
    if (state.page === 'sell') {
      renderSellWorkspace();
      refs.globalSearchResults.classList.add('hidden');
    } else {
      renderTable();
      renderDetails();
      renderGlobalSearchResults();
    }
  }

  async function patchItem(item, patch) {
    if (!item || tradeBusy()) return false;
    try {
      refs.saveBadge.textContent = 'Сохранение...';
      await action('trade.item.update', {side: state.page, identity: item.identity, patch});
      refs.saveBadge.textContent = 'Сохранено';
      await refresh(true);
      setTimeout(() => { refs.saveBadge.textContent = 'Автосохранение'; }, 900);
      return true;
    } catch (err) {
      refs.saveBadge.textContent = 'Не сохранено';
      if (err.status === 409 && err.message === 'trade_active') {
        showToast('Сначала остановите активную торговлю.', 'error');
      } else if (err.status === 409 && err.message === 'stale_state') {
        showToast('Список обновился. Повтори изменение состояния.', 'error');
      } else {
        showToast(`Не удалось сохранить: ${err.message}`, 'error');
      }
      await refresh(true);
      return false;
    }
  }

  async function removeItem(item) {
    if (!item || tradeBusy()) return;
    try {
      await action('trade.item.remove', {side: state.page, identity: item.identity});
      state.selectedItem = null;
      state.selectedKey = null;
      showToast('Товар удален. Ctrl+Z вернет его', 'success');
      await refresh(true);
    } catch (err) {
      showToast(`Не удалось удалить: ${err.message}`, 'error');
      await refresh(true);
    }
  }

  function openPicker(initialQuery = '') {
    if (tradeBusy()) return;
    state.searchFocused = false;
    refs.globalSearchResults?.classList.add('hidden');
    setTradeFilterOpen(false);
    refs.pickerTitle.textContent = state.page === 'buy' ? 'Добавить в скупку' : 'Добавить в продажу';
    state.pickerSearch = text(initialQuery);
    refs.pickerSearch.value = state.pickerSearch;
    refs.pickerBackdrop.classList.remove('hidden');
    renderPicker();
    setTimeout(() => refs.pickerSearch.focus(), 30);
  }

  function closePicker() {
    refs.pickerBackdrop.classList.add('hidden');
  }

  function closeBudget() {
    refs.budgetBackdrop.classList.add('hidden');
    clearTimeout(state.budgetPreviewTimer);
  }

  async function refreshBudgetPreview() {
    const budget = Number(refs.budgetInput.value);
    if (!Number.isFinite(budget) || budget < 0) {
      refs.budgetEligible.textContent = '0';
      refs.budgetSpent.textContent = '0';
      refs.budgetRemaining.textContent = '0';
      refs.budgetApply.disabled = true;
      return;
    }
    try {
      const result = await action('buy.budget.preview', {side: 'buy', budget});
      const data = result.data || {};
      refs.budgetEligible.textContent = money(data.eligible || 0);
      refs.budgetSpent.textContent = `${money(data.spent || 0)} ${state.data?.common?.currencyMode === 'VC' ? 'VC$' : 'SA$'}`;
      refs.budgetRemaining.textContent = money(data.remaining || 0);
      refs.budgetApply.disabled = false;
    } catch (err) {
      refs.budgetEligible.textContent = '0';
      refs.budgetSpent.textContent = '0';
      refs.budgetRemaining.textContent = '0';
      refs.budgetApply.disabled = true;
    }
  }

  function openBudget() {
    if (tradeBusy() || state.page !== 'buy') return;
    refs.budgetInput.value = '';
    refs.budgetEligible.textContent = '0';
    refs.budgetSpent.textContent = '0';
    refs.budgetRemaining.textContent = '0';
    refs.budgetApply.disabled = true;
    refs.budgetBackdrop.classList.remove('hidden');
    setTimeout(() => refs.budgetInput.focus(), 30);
  }

  function renderPicker() {
    const source = asArray(state.data?.data?.source);
    const existing = new Set(asArray(state.data?.data?.items).map(item => normalizeName(item.name)));
    const q = normalizeName(state.pickerSearch);
    const filtered = source
      .filter(item => !existing.has(normalizeName(item.name)) && (!q || normalizeName(item.name).includes(q)))
      .slice(0, 400);

    refs.pickerRows.innerHTML = '';
    const fragment = document.createDocumentFragment();
    for (const item of filtered) {
      const row = div('', 'picker-row');
      const left = div('', 'item-cell');
      const box = div('', 'item-thumb-box');
      const img = document.createElement('img');
      img.className = 'item-thumb';
      img.alt = '';
      setIcon(img, item, 48);
      box.append(img);
      const pickerName = div(item.name, 'picker-item-name');
      bindAveragePriceHover(pickerName, item);
      left.append(box, pickerName);
      row.append(left, div(state.page === 'sell' && item.all_count ? `${money(item.all_count)} шт.` : '+', 'picker-count'));
      row.addEventListener('click', async () => {
        if (tradeBusy()) return;
        try {
          await action('trade.item.add', {side: state.page, source_index: item.index});
          showToast('Товар добавлен', 'success');
          await refresh(true);
          renderPicker();
        } catch (err) {
          const message = err.message === 'not_enough_items' ? 'Недостаточно предметов для значения по умолчанию' : err.message;
          showToast(`Не удалось добавить: ${message}`, 'error');
        }
      });
      fragment.append(row);
    }
    refs.pickerRows.append(fragment);
  }

  function emptyPageState(page, previousWindow) {
    const common = {htmlWindow: previousWindow};
    if (page === 'storage') Object.assign(common, {storageReady:false, scanning:false, lastScan:0});
    if (page === 'logs') Object.assign(common, {today:''});
    if (page === 'buy' || page === 'sell') Object.assign(common, {configs:[], activeConfig:'', currencyMode:'SA'});
    let data;
    if (page === 'logs') data = {records:[]};
    else if (page === 'settings') data = {values:{}, appearance:{themes:[], global_palette:{enabled:false,base:'#4B8DFF',depth:72,saturation:82,contrast:72,glow:80}, custom_groups:[]}, configs:{sell:{items:[]}, buy:{items:[]}}, mods:{remove_players:false,remove_vehicles:false,auto_cycle:false,manual_purchased_running:false,trade_busy:false}};
    else if (page === 'marketplace') data = {status:'loading', shops:[], servers:[], selectedIndex:0, selectedName:'Все сервера', currentServerId:null, queue:0, shopCount:0, sortMode:0, lastUpdated:0};
    else if (page === 'mods') data = {remove_players:false, remove_vehicles:false, auto_fps:false, auto_fps_active:false, auto_fps_reason:'none', fps:0, players:null, players_threshold:80, fps_threshold:45, auto_cycle:false, manual_purchased_count:0, manual_purchased_running:false, cycle_active:false, cycle_pending_sell:0, cycle_pending_rebuy:0, trade_busy:false};
    else data = {items:[], source:[], locationCount:0};
    return {revision:0, page, common, data};
  }

  async function switchPage(page) {
    if (!['buy','sell','settings','logs','marketplace','mods','storage'].includes(page) || page === state.page) return;
    closePopupSelect();
    if (secondaryActions) secondaryActions.open = false;

    const previousWindow = state.data?.common?.htmlWindow;
    const cached = state.pageCache[page];
    state.page = page;
    state.revision = Number(state.pageRevision[page] || cached?.revision || 0);
    state.selectedItem = null;
    state.selectedKey = null;
    state.search = '';
    state.sellInventorySearch = '';
    state.sortKey = null;
    state.sortDirection = 0;
    refs.searchInput.value = '';
    if (refs.sellInventorySearch) refs.sellInventorySearch.value = '';
    if (page === 'logs') state.logs.page = 1;
    if (page === 'storage') { state.storage.selectedKey = null; if (state.minimalMode) state.storage.tab = 'distribution'; }
    if (page === 'marketplace') { state.marketplace.search=''; state.marketplace.selectedShopKey=null; if(refs.marketplaceSearchInput) refs.marketplaceSearchInput.value=''; }
    if (page === 'settings') state.settings.pendingScale = null;

    // Paint immediately from the last known snapshot. Network work starts only
    // after the new page is already visible, so repeat navigation feels native.
    state.data = cached || emptyPageState(page, previousWindow);
    if (cached) syncSelected();
    try {
      render();
      refs.runtimeText.textContent = cached ? 'Система готова' : 'Загрузка...';
    } catch (err) {
      console.error('[ArzMarket HTML] instant page render failed:', err);
    }

    // Give CEF one frame to present the page before doing Lua/HTTP work.
    await new Promise(resolve => requestAnimationFrame(resolve));
    const payload = {page, side: page === 'sell' ? 'sell' : page === 'buy' ? 'buy' : undefined, preview: previewMode === true};
    await action('ui.navigate', payload).catch(() => null);
    await refresh(true, page).catch(() => null);
  }

  document.addEventListener('click', async event => {
    const pageButton = event.target.closest('.nav-item[data-page]');
    if (pageButton) {
      const requestedPage = pageButton.dataset.page;
      if (requestedPage === state.page) {
        await baronAssistantUi?.event('page', {page: requestedPage});
        return;
      }
      return switchPage(requestedPage);
    }
    const button = event.target.closest('[data-action]');
    if (!button) return;
    const name = button.dataset.action;
    if (name === 'close') {
      closeHtmlInterface();
      return;
    }
    if (name === 'window-maximize') {
      windowManager?.toggleMaximize();
      return;
    }
    if (name === 'window-minimize') {
      windowManager?.toggleMinimize();
      return;
    }
    if (name === 'minimal-full' || name === 'minimal-on') {
      const enabled = name === 'minimal-on';
      if (state.minimalMode !== enabled) {
        setMinimalMode(enabled, true);
        try {
          await persistMinimalMode();
        } catch (err) {
          showToast(`Минимализм: не удалось сохранить режим (${err.message})`, 'error');
        }
      }
      return;
    }
    if (name === 'mode-lua') {
      button.disabled = true;

      // Hide the CEF iframe immediately but keep it alive long enough for the
      // bridge request to finish. This removes the 3-5 second HTML/Lua overlap.
      hideHostFrame();
      try {
        await action('ui.switch_mode', {page: state.page, side: state.page === 'sell' ? 'sell' : state.page === 'buy' ? 'buy' : undefined});
      } catch (err) {
        showHostFrame();
        button.disabled = false;
        showToast(`Переключение на Lua: ${err.message}`, 'error');
      }
      return;
    }
    if (name === 'picker-close') closePicker();
    if (name === 'budget-close') closeBudget();
  });

  refs.modsWorkspace?.addEventListener('click', event => {
    const button = event.target.closest('[data-mods-section]');
    if (!button || state.page !== 'mods') return;
    const section = String(button.dataset.modsSection || 'scripts');
    if (!['scripts','mine'].includes(section)) return;
    state.modsSection = section;
    renderMods();
  });

  refs.marketplaceSearchInput?.addEventListener('input',()=>{
    state.marketplace.search=refs.marketplaceSearchInput.value;
    state.marketplace.selectedShopKey=null;
    renderMarketplace();
  });
  refs.marketplaceRefreshButton?.addEventListener('click',async()=>{
    try{refs.marketplaceRefreshButton.disabled=true; await action('marketplace.refresh',{page:'marketplace'}); showToast('Обновляю список лавок','success'); setTimeout(()=>refresh(true,'marketplace'),250);}catch(err){showToast(`Маркетплейс: ${err.message}`,'error');}finally{refs.marketplaceRefreshButton.disabled=false;}
  });
  refs.marketplaceServerButton?.addEventListener('click',event=>{
    event.preventDefault();
    const data=marketplaceData(); const servers=Array.isArray(data.servers)?data.servers:[];
    openPopupSelect(refs.marketplaceServerButton,servers.map(row=>({value:String(row.index),label:row.name})),String(data.selectedIndex ?? 0),async value=>{
      try{await action('marketplace.server.select',{page:'marketplace',index:Number(value)}); state.marketplace.selectedShopKey=null; showToast('Сервер переключен','success'); await refresh(true,'marketplace');}catch(err){showToast(`Сервер: ${err.message}`,'error');}
    },'marketplace-server');
  });
  refs.marketplaceSortButton?.addEventListener('click',async()=>{
    const data=marketplaceData(); const next=(Number(data.sortMode||0)+1)%3; data.sortMode=next; renderMarketplace();
    try{await action('marketplace.sort',{page:'marketplace',mode:next}); await refresh(true,'marketplace');}catch(err){showToast(`Сортировка: ${err.message}`,'error');}
  });
  refs.marketplaceBackButton?.addEventListener('click',()=>{state.marketplace.selectedShopKey=null;renderMarketplace();});

  refs.settingsToolbar?.addEventListener('click', event => {
    const button = event.target.closest('[data-settings-section]');
    if (!button || state.page !== 'settings') return;
    const section = String(button.dataset.settingsSection || 'general');
    if (!['general','trade','automation','telegram','appearance','configs'].includes(section)) return;
    state.settings.section = section;
    renderSettings();
    baronAssistantUi?.event('settings_section_changed', {section});
  });

  refs.storageSearchInput?.addEventListener('input',()=>{state.storage.search=refs.storageSearchInput.value;renderStorage();});
  refs.storageFindButton?.addEventListener('click',()=>{state.storage.search=refs.storageSearchInput.value;renderStorage();});
  refs.storageTypeButton?.addEventListener('click',event=>{event.preventDefault();openPopupSelect(refs.storageTypeButton,storageTypeOptions(),state.storage.type,value=>{state.storage.type=value||'all';renderStorage();},'storage-type');});
  refs.storagePlaceTabs?.addEventListener('click',event=>{const btn=event.target.closest('[data-storage-place]');if(!btn)return;state.storage.place=btn.dataset.storagePlace||'all';state.storage.selectedKey=null;renderStorage();});
  refs.storageDistributionTab?.addEventListener('click',()=>{state.storage.tab='distribution';renderStorage();});
  refs.storageInfoTab?.addEventListener('click',()=>{state.storage.tab='info';renderStorage();});
  refs.storageScanButton?.addEventListener('click',async()=>{try{refs.storageScanButton.disabled=true;await action('storage.scan',{page:'storage',kind:state.storage.place});showToast('Сканирование запущено','success');setTimeout(()=>refresh(true),900);}catch(err){showToast(err.message==='open_storage_first'?'Откройте нужное хранилище или инвентарь, затем нажмите «Сканировать»':`Сканирование недоступно: ${err.message}`,'error');}finally{refs.storageScanButton.disabled=false;}});

  refs.sellInventorySearch?.addEventListener('input', () => {
    state.sellInventorySearch = refs.sellInventorySearch.value;
    renderSellInventory();
  });

  refs.sellScanButton?.addEventListener('click', () => {
    if (!tradeBusy()) refs.scanButton.click();
  });

  refs.sellScanMainButton?.addEventListener('click', () => {
    if (state.page === 'sell' && !tradeBusy()) refs.scanButton.click();
  });


  document.querySelectorAll('[data-sell-status-filter]').forEach(button => {
    button.addEventListener('click', event => {
      event.preventDefault();
      const next = String(button.dataset.sellStatusFilter || 'all');
      state.sellStatusFilter = ['enabled','disabled'].includes(next) ? next : 'all';
      renderSellItems();

      const baronEvent = state.sellStatusFilter === 'enabled'
        ? 'sell_stats_enabled_clicked'
        : state.sellStatusFilter === 'disabled'
          ? 'sell_stats_disabled_clicked'
          : 'sell_stats_total_clicked';
      void baronAssistantUi?.event(baronEvent, {filter: state.sellStatusFilter});
    });
  });

  document.querySelectorAll('[data-sell-sort]').forEach(button => {
    button.addEventListener('click', event => {
      event.preventDefault();
      cycleSort(button.dataset.sellSort);
    });
  });

  function bindSellDetailNumber(input, kind) {
    if (!input) return;
    let timer = 0;
    const commit = async () => {
      clearTimeout(timer);
      const item = state.selectedItem;
      if (!item || state.page !== 'sell' || tradeBusy()) return;
      let value = kind === 'price' ? parseMoneyInput(input.value) : Number(input.value);
      if (!Number.isFinite(value) || value < 0) return;
      value = Math.trunc(value);
      if (kind === 'count') {
        const available = Math.max(0, Math.trunc(Number(item.all_count) || 0));
        if (available > 0) value = Math.min(value, available);
        input.value = String(value);
        await patchItem(item, {count:value, maximum:false});
      } else {
        await patchItem(item, {[sellCurrency() === 'VC' ? 'price_vc' : 'price']:value});
      }
    };
    if (kind === 'price') {
      input.addEventListener('focus', () => {
        input.value = String(parseMoneyInput(input.value));
      });
    }
    input.addEventListener('input', () => {
      clearTimeout(timer);
      timer = window.setTimeout(commit, 430);
    });
    input.addEventListener('change', commit);
    input.addEventListener('blur', commit);
    input.addEventListener('keydown', event => {
      if (event.key === 'Enter') input.blur();
    });
  }

  bindSellDetailNumber(refs.sellInfoPrice, 'price');
  bindSellDetailNumber(refs.sellInfoCount, 'count');

  refs.sellInfoMax?.addEventListener('click', async () => {
    const item = state.selectedItem;
    if (!item || state.page !== 'sell' || tradeBusy()) return;
    const enable = item.maximum !== true;
    const patch = enable ? {maximum:true} : {maximum:false, count:sellEffectiveCount(item)};
    await patchItem(item, patch);
  });

  refs.sellStartButton?.addEventListener('click', () => refs.startButton.click());

  refs.logsSearchInput?.addEventListener('input', () => {
    state.logs.search = refs.logsSearchInput.value;
    state.logs.page = 1;
    renderLogs();
  });
  refs.logsPeriodButton?.addEventListener('click', event => {
    event.preventDefault();
    event.stopPropagation();
    const options = [
      {value:'today',label:'Сегодня'}, {value:'week',label:'7 дней'},
      {value:'month',label:'30 дней'}, {value:'all',label:'Всё время'}
    ];
    openPopupSelect(refs.logsPeriodButton, options, state.logs.period, value => {
      state.logs.period = value || 'today';
      state.logs.date = 'all';
      state.logs.page = 1;
      renderHeader();
      renderLogs();
    }, 'logs-period');
  });
  refs.logsCategoryButton?.addEventListener('click', event => {
    event.preventDefault();
    event.stopPropagation();
    openPopupSelect(refs.logsCategoryButton, logsCategoryOptions(), state.logs.category, value => {
      state.logs.category = value || 'all';
      state.logs.page = 1;
      renderLogs();
    }, 'logs-category');
  });
  refs.logsStatusButton?.addEventListener('click', event => {
    event.preventDefault();
    event.stopPropagation();
    const options = [
      {value:'all',label:'Все статусы'}, {value:'success',label:'Успешно'},
      {value:'info',label:'Информация'}, {value:'warning',label:'Внимание'}
    ];
    openPopupSelect(refs.logsStatusButton, options, state.logs.status, value => {
      state.logs.status = value || 'all';
      state.logs.page = 1;
      renderLogs();
    }, 'logs-status');
  });
  refs.logsDateButton?.addEventListener('click', event => {
    event.preventDefault();
    event.stopPropagation();
    const today = state.data?.common?.today || '';
    const dates = [...new Set(asArray(state.data?.data?.records).map(record => record.date).filter(Boolean))]
      .sort((a,b) => logsDateValue(b) - logsDateValue(a));
    const options = [{value:'all', label:state.logs.period === 'today' ? 'Сегодня' : 'Все даты'}]
      .concat(dates.map(value => ({value, label:value === today ? `Сегодня · ${value}` : value})));
    openPopupSelect(refs.logsDateButton, options, state.logs.date, value => {
      state.logs.date = value || 'all';
      state.logs.page = 1;
      renderLogs();
    }, 'logs-date');
  });
  refs.logsRefreshButton?.addEventListener('click', async () => {
    try {
      await refresh(true);
      showToast('Логи обновлены', 'success');
    } catch (_) {}
  });

  refs.searchInput.addEventListener('focus', () => {
    window.clearTimeout(buySearchBlurTimer);
    buySearchBlurTimer = 0;
    state.searchFocused = state.page === 'buy';
    if (state.page === 'buy') renderGlobalSearchResults();
  });
  refs.searchInput.addEventListener('click', () => {
    if (state.page !== 'buy') return;
    window.clearTimeout(buySearchBlurTimer);
    buySearchBlurTimer = 0;
    state.searchFocused = true;
    renderGlobalSearchResults();
  });
  refs.searchInput.addEventListener('input', () => {
    state.search = refs.searchInput.value;
    if (state.page === 'sell') {
      state.sellInventorySearch = state.search;
      renderSellWorkspace();
      refs.globalSearchResults.classList.add('hidden');
    } else {
      renderTable();
      renderGlobalSearchResults();
    }
  });
  refs.searchInput.addEventListener('blur', () => {
    window.clearTimeout(buySearchBlurTimer);
    buySearchBlurTimer = window.setTimeout(() => {
      buySearchBlurTimer = 0;
      state.searchFocused = false;
      if (state.page === 'buy') renderGlobalSearchResults();
      else refs.globalSearchResults.classList.add('hidden');
    }, 120);
  });
  refs.tradeFilterButton?.addEventListener('click', event => {
    event.preventDefault();
    event.stopPropagation();
    const opening = refs.tradeFilterPanel?.classList.contains('hidden') !== false;
    setTradeFilterOpen(opening);
    if (opening) baronAssistantUi?.event('filter_opened', {side: state.page});
  });
  refs.tradeFilterClose?.addEventListener('click', event => {
    event.preventDefault();
    event.stopPropagation();
    setTradeFilterOpen(false);
  });
  document.addEventListener('pointerdown', event => {
    if (refs.tradeFilterPanel && !refs.tradeFilterPanel.classList.contains('hidden')
        && !refs.tradeFilterPanel.contains(event.target) && !refs.tradeFilterButton?.contains(event.target)) {
      setTradeFilterOpen(false);
    }
  });
  refs.configSelect.addEventListener('change', () => loadConfigByName(refs.configSelect.value));
  refs.addButton.addEventListener('click', () => openPicker());
  refs.undoButton.addEventListener('click', async () => {
    if (tradeBusy() || Number(state.data?.common?.undoCount || 0) < 1) return;
    try {
      await action('trade.item.undo', {side: state.page});
      showToast('Удаленный товар возвращен', 'success');
      await refresh(true);
    } catch (err) { showToast(`Возврат: ${err.message}`, 'error'); }
  });
  refs.clearButton.addEventListener('click', async () => {
    if (tradeBusy() || !asArray(state.data?.data?.items).length) return;
    if (Date.now() >= state.clearArmedUntil) {
      state.clearArmedUntil = Date.now() + 2400;
      renderHeader();
      setTimeout(() => { if (Date.now() >= state.clearArmedUntil) renderHeader(); }, 2500);
      return;
    }
    state.clearArmedUntil = 0;
    try {
      await action('trade.list.clear', {side: state.page});
      state.selectedItem = null;
      state.selectedKey = null;
      showToast('Список очищен', 'success');
      await refresh(true);
    } catch (err) { showToast(`Очистка: ${err.message}`, 'error'); }
  });
  refs.budgetButton.addEventListener('click', openBudget);
  refs.budgetCancel.addEventListener('click', closeBudget);
  refs.budgetBackdrop.addEventListener('click', event => { if (event.target === refs.budgetBackdrop) closeBudget(); });
  refs.budgetInput.addEventListener('input', () => {
    clearTimeout(state.budgetPreviewTimer);
    state.budgetPreviewTimer = setTimeout(refreshBudgetPreview, 180);
  });
  refs.budgetApply.addEventListener('click', async () => {
    if (tradeBusy()) return;
    const budget = Number(refs.budgetInput.value);
    if (!Number.isFinite(budget) || budget < 0) return;
    refs.budgetApply.disabled = true;
    try {
      const result = await action('buy.budget.apply', {side: 'buy', budget});
      const data = result.data || {};
      closeBudget();
      showToast(`Распределение завершено. Остаток: ${money(data.remaining || 0)}`, 'success');
      await refresh(true);
    } catch (err) {
      const labels = {invalid_budget:'Введите корректный бюджет',no_eligible_items:'Нет активных товаров для распределения',config_not_loaded:'Сначала загрузите конфиг'};
      showToast(labels[err.message] || `Бюджет: ${err.message}`, 'error');
      refs.budgetApply.disabled = false;
    }
  });
  refs.continueButton.addEventListener('click', async () => {
    if (tradeBusy() || state.page !== 'buy') return;
    try {
      await action('buy.continue.toggle', {side: 'buy'});
      await refresh(true);
    } catch (err) { showToast(`Продолжение скупки: ${err.message}`, 'error'); }
  });
  refs.scanButton.addEventListener('click', async () => {
    if (tradeBusy()) return;
    try {
      await action('trade.scan.toggle', {side: state.page});
      await refresh(true);
    } catch (err) { showToast(`Сканирование: ${err.message}`, 'error'); }
  });
  refs.currencyButton.addEventListener('click', async () => {
    if (tradeBusy()) return;
    try {
      await action('trade.currency.toggle', {side: state.page});
      await refresh(true);
    } catch (err) { showToast(`Валюта: ${err.message}`, 'error'); }
  });
  if (refs.sellCurrencyQuickButton) refs.sellCurrencyQuickButton.addEventListener('click', async () => {
    if (tradeBusy() || (state.page !== 'buy' && state.page !== 'sell')) return;
    try {
      await action('trade.currency.toggle', {side: state.page});
      await refresh(true);
    } catch (err) { showToast(`Валюта: ${err.message}`, 'error'); }
  });
  refs.refreshButton.addEventListener('click', async () => {
    if (tradeBusy() || state.page !== 'buy') return;
    try {
      await action('buy.source.refresh', {side: 'buy'});
      showToast('Обновление списка запущено', 'success');
      await refresh(true);
    } catch (err) { showToast(`Список: ${err.message}`, 'error'); }
  });
  refs.pricesButton.addEventListener('click', async () => {
    if (tradeBusy()) return;
    try {
      await action('prices.download', {side: state.page});
      state.averagePrices.cache.clear();
      state.averagePrices.pending.clear();
      showToast('Загрузка средних цен запущена', 'success');
    } catch (err) { showToast(`Цены: ${err.message}`, 'error'); }
  });
  refs.pickerSearch.addEventListener('input', () => {
    state.pickerSearch = refs.pickerSearch.value;
    renderPicker();
  });
  refs.pickerBackdrop.addEventListener('click', event => { if (event.target === refs.pickerBackdrop) closePicker(); });
  refs.averageButton.addEventListener('click', async () => {
    if (tradeBusy()) return;
    try {
      await action('buy.average.apply', {side: 'buy'});
      showToast('Автоматические цены применены', 'success');
      await refresh(true);
    } catch (err) {
      showToast(`Автоматические цены: ${err.message}`, 'error');
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

  installWheelScroller(refs.tableRows);
  installWheelScroller(refs.pickerRows);
  installWheelScroller(refs.globalSearchResults);
  installWheelScroller(refs.tradeFilterCategories);
  installWheelScroller(refs.sellInventoryRows);
  installWheelScroller(refs.sellSaleRows);
  installWheelScroller(refs.sellInfoContent);

  window.addEventListener('keydown', event => {
    if (event.key !== 'Escape' || event.repeat) return;
    if (activePopupSelect) {
      event.preventDefault();
      event.stopPropagation();
      closePopupSelect();
      return;
    }
    if (refs.sellToolsPanel && !refs.sellToolsPanel.classList.contains('hidden')) {
      event.preventDefault();
      event.stopPropagation();
      refs.sellToolsPanel.classList.add('hidden');
      refs.sellToolsButton?.setAttribute('aria-expanded', 'false');
      return;
    }
    if (refs.tradeFilterPanel && !refs.tradeFilterPanel.classList.contains('hidden')) {
      event.preventDefault();
      event.stopPropagation();
      setTradeFilterOpen(false);
      return;
    }
    if (secondaryActions?.open) {
      event.preventDefault();
      event.stopPropagation();
      secondaryActions.open = false;
      return;
    }
    if (refs.budgetBackdrop.classList.contains('hidden') && refs.pickerBackdrop.classList.contains('hidden')) {
      event.preventDefault();
      event.stopPropagation();
      closeHtmlInterface();
    }
  }, true);

  const closeButton = document.querySelector('[data-action="close"]');
  if (closeButton) {
    closeButton.addEventListener('pointerdown', event => {
      event.preventDefault();
      event.stopPropagation();
      closeHtmlInterface();
    }, true);
  }

  document.addEventListener('keydown', event => {
    const tag = String(event.target?.tagName || '').toLowerCase();
    const textInput = tag === 'input' || tag === 'textarea' || tag === 'select' || event.target?.isContentEditable === true;
    if (event.ctrlKey && !event.shiftKey && String(event.key).toLowerCase() === 'z' && !textInput) {
      event.preventDefault();
      if (!tradeBusy() && Number(state.data?.common?.undoCount || 0) > 0) refs.undoButton.click();
      return;
    }
    if (event.key === 'Escape') {
      if (!refs.budgetBackdrop.classList.contains('hidden')) {
        closeBudget();
      } else if (!refs.pickerBackdrop.classList.contains('hidden')) {
        closePicker();
      } else if (!event.repeat) {
        event.preventDefault();
        event.stopPropagation();
        closeHtmlInterface();
      }
      return;
    }
    if (event.ctrlKey && String(event.key).toLowerCase() === 'f') {
      event.preventDefault();
      const target = state.page === 'logs' ? refs.logsSearchInput : state.page === 'marketplace' ? refs.marketplaceSearchInput : state.page === 'storage' ? refs.storageSearchInput : state.page === 'settings' || state.page === 'mods' ? null : refs.searchInput;
      target?.focus();
      target?.select();
    }
  });

  window.addEventListener('error', event => {
    refs.runtimeText.textContent = 'Ошибка интерфейса';
    console.error('[ArzMarket HTML]', event.error || event.message);
  });
  window.addEventListener('unhandledrejection', event => console.error('[ArzMarket HTML]', event.reason));
  window.addEventListener('load', () => {
    window.requestAnimationFrame(() => {
      try { window.focus(); } catch (_) {}
      updateVisualScale();
    });
  }, {once: true});

  if (previewMode) applyPreviewScale();
  if (state.page === 'marketplace') {
    state.data = emptyPageState('marketplace');
    try { render(); refs.runtimeText.textContent = 'Загрузка маркетплейса...'; } catch (err) { console.error('[ArzMarket HTML] initial marketplace shell failed:', err); }
  } else if (state.page === 'mods') {
    state.data = emptyPageState('mods');
    try { render(); refs.runtimeText.textContent = 'Загрузка модификаций...'; } catch (err) { console.error('[ArzMarket HTML] initial mods shell failed:', err); }
  } else if (state.page === 'storage') {
    state.data = {revision: 0, page: 'storage', common: {storageReady: false, scanning: false, lastScan: 0}, data: {items: [], locationCount: 0}};
    try { render(); refs.runtimeText.textContent = 'Загрузка хранилища...'; } catch (err) { console.error('[ArzMarket HTML] initial storage shell failed:', err); }
  } else if (state.page === 'settings') {
    state.data = emptyPageState('settings');
    try { render(); refs.runtimeText.textContent = 'Загрузка настроек...'; } catch (err) { console.error('[ArzMarket HTML] initial settings shell failed:', err); }
  }
  // Do not paint a temporary buy/sell shell on boot. The interface stays hidden
  // until the first real Lua state arrives, which prevents the foreign first window.
  refresh(true).catch(() => null);
  (async function pollBridge() {
    while (true) {
      await new Promise(resolve => window.setTimeout(resolve, 2000));
      try { await refresh(false); } catch (_) {}
    }
  })();
})();
