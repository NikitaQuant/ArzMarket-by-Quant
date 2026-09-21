(() => {
  'use strict';

  const BARON_BASE_VIEWPORT_W = 1920;
  const BARON_BASE_VIEWPORT_H = 1080;
  const BARON_MIN_SCREEN_SCALE = 0.68;
  const BARON_MAX_SCREEN_SCALE = 1.50;

  function getScreenScale() {
    const sx = Math.max(1, window.innerWidth) / BARON_BASE_VIEWPORT_W;
    const sy = Math.max(1, window.innerHeight) / BARON_BASE_VIEWPORT_H;
    return Math.max(BARON_MIN_SCREEN_SCALE, Math.min(BARON_MAX_SCREEN_SCALE, Math.min(sx, sy)));
  }

  // v224: keep screen-dependent sizing, but scale text more softly so
  // medium and long tutorial messages do not become overly narrow on 1440p.
  function getBaronTextScale(screenScale) {
    return Math.max(0.86, Math.min(1.10, 1 + (screenScale - 1) * 0.40));
  }

  function getBaronBubbleScale(screenScale) {
    return Math.max(0.88, Math.min(1.08, 1 + (screenScale - 1) * 0.25));
  }

  const poseAssets = {
    neutral: '/static/assets/baron/neutral.png?v=101',
    talking: '/static/assets/baron/talking.png?v=101',
    waving: '/static/assets/baron/waving.png?v=101',
    presenting: '/static/assets/baron/presenting.png?v=101',
    point_left: '/static/assets/baron/point_left.png?v=101',
    point_right: '/static/assets/baron/point_right.png?v=101',
    point_down_right: '/static/assets/baron/point_down_right.png?v=101',
    point_up_left: '/static/assets/baron/point_up_left.png?v=101',
    point_up_right: '/static/assets/baron/point_up_right.png?v=101',
    thinking: '/static/assets/baron/thinking.png?v=101',
    thinking_question: '/static/assets/baron/thinking_question.png?v=101',
    approval: '/static/assets/baron/approval.png?v=101',
    question: '/static/assets/baron/question.png?v=101',
    caution: '/static/assets/baron/caution.png?v=101',
    celebration: '/static/assets/baron/celebration.png?v=101',
    sad: '/static/assets/baron/sad.png?v=101'
  };

  const bubbleAssets = {
    welcome_upper_left: '/static/assets/baron/bubble_welcome_upper_left.png?v=108',
    welcome_upper_right: '/static/assets/baron/bubble_welcome_upper_right.png?v=108'
  };

  // Only side-tail bubbles are allowed. The center-tail asset is intentionally
  // excluded so every visible bubble points to Baron from a left or right edge.
  const bubbleGeometry = {
    welcome_upper_left: { tailXFrac: 0.9532, tailYFrac: 0.9707, preference: 0 },
    welcome_upper_right: { tailXFrac: 0.0572, tailYFrac: 0.9859, preference: 0 }
  };

  const mascotSvg = `
    <svg viewBox="0 0 90 126" aria-hidden="true">
      <defs><clipPath id="baronDropClip"><path d="M45 2 C40 16 11 39 11 70 C11 99 25 119 45 119 C65 119 79 99 79 70 C79 39 50 16 45 2Z"/></clipPath></defs>
      <path d="M45 2 C40 16 11 39 11 70 C11 99 25 119 45 119 C65 119 79 99 79 70 C79 39 50 16 45 2Z" fill="#f7fbff"/>
      <g clip-path="url(#baronDropClip)">
        <rect x="6" y="30" width="78" height="10" rx="5" fill="#3aa9ef"/>
        <rect x="6" y="53" width="78" height="10" rx="5" fill="#3aa9ef"/>
        <rect x="6" y="76" width="78" height="10" rx="5" fill="#3aa9ef"/>
      </g>
      <circle cx="45" cy="64" r="20" fill="#c7eaff"/>
      <circle cx="38" cy="61" r="2.4" fill="#0b2234"/><circle cx="52" cy="61" r="2.4" fill="#0b2234"/>
      <path d="M39 72 Q45 77 52 72" fill="none" stroke="#0b2234" stroke-width="2" stroke-linecap="round"/>
      <path d="M14 70 Q3 66 1 55" fill="none" stroke="#f7fbff" stroke-width="7" stroke-linecap="round"/>
      <circle cx="1" cy="53" r="4.3" fill="#f7fbff"/>
      <path d="M76 72 Q87 67 89 56" fill="none" stroke="#f7fbff" stroke-width="7" stroke-linecap="round"/>
      <circle cx="89" cy="54" r="4.3" fill="#f7fbff"/>
    </svg>`;

  const targetSelectors = {
    window_drag: '[data-baron-anchor="window_drag"], .topbar',
    resize_handle: '[data-baron-anchor="resize_handle"], .window-resize-handle.resize-se',
    nav_sell: '[data-baron-anchor="nav_sell"], .nav-item[data-page="sell"]',
    nav_buy: '[data-baron-anchor="nav_buy"], .nav-item[data-page="buy"]',
    nav_settings: '[data-baron-anchor="nav_settings"], .nav-item[data-page="settings"]',
    nav_logs: '[data-baron-anchor="nav_logs"], .nav-item[data-page="logs"]',
    nav_marketplace: '[data-baron-anchor="nav_marketplace"], .nav-item[data-page="marketplace"]',
    nav_mods: '[data-baron-anchor="nav_mods"], .nav-item[data-page="mods"]',
    nav_storage: '[data-baron-anchor="nav_storage"], .nav-item[data-page="storage"]',
    page_content: '[data-baron-anchor="page_content"], .content',
    sell_scan: '[data-baron-anchor="sell_scan"], #sellScanMainButton:not(.hidden), #scanButton',
    add_button: '[data-baron-anchor="add_button"], #addButton',
    start_button: '[data-baron-anchor="start_button"], #startButton',
    sell_inventory: '[data-baron-anchor="sell_inventory"]',
    sell_selected_items: '[data-baron-anchor="sell_selected_items"]',
    sell_status_toggle: '[data-baron-anchor="sell_status_toggle"]',
    sell_stats_total: '[data-sell-status-filter="all"]',
    sell_stats_enabled: '[data-sell-status-filter="enabled"]',
    sell_stats_disabled: '[data-sell-status-filter="disabled"]',
    sell_filter_button: '[data-baron-anchor="sell_filter_button"], #tradeFilterButton',
    sell_filter_panel: '[data-baron-anchor="sell_filter_panel"], #tradeFilterPanel:not(.hidden)',
    sell_currency: '[data-baron-anchor="sell_currency"], #sellCurrencyQuickButton:not(.hidden)',
    sell_config: '[data-baron-anchor="sell_config"], .config-select-trigger',
    buy_search: '[data-baron-anchor="buy_search"], #searchInput',
    buy_auto_prices: '[data-baron-anchor="buy_auto_prices"], #averageButton:not(.hidden)',
    settings_main: '[data-baron-anchor="settings_main"]',
    settings_appearance_tab: '[data-baron-anchor="settings_appearance_tab"]',
    settings_appearance_panel: '[data-baron-anchor="settings_appearance_panel"][data-section="appearance"]',
    settings_glow: '[data-baron-anchor="settings_glow"]',
    settings_themes: '[data-baron-anchor="settings_themes"]'
  };

  const colorClasses = {
    normal: '',
    blue: 'baron-text-blue',
    red: 'baron-text-red',
    green: 'baron-text-green'
  };

  function create(options = {}) {
    const callAction = options.action;
    const refresh = options.refresh;
    const openPage = options.openPage;
    const openFilter = options.openFilter;
    const ensureFilterOpen = options.ensureFilterOpen;
    const openSettingsSection = options.openSettingsSection;
    let snapshot = null;
    let snapshotReceivedAt = 0;
    let skipButtonEl = null;
    let choiceNoButtonEl = null;
    let promoButtonEl = null;
    let lastMessageKey = '';
    let lastPose = '';
    let typedSegments = [];
    let totalChars = 0;
    let shown = 0;
    let lastTypeAt = 0;
    let raf = 0;
    let target = null;
    let targetKey = '';
    let targetResolveAfter = 0;
    let missingTargetSince = 0;
    let missingTargetLoggedKey = '';
    let restoredSettingsKey = '';
    let motionReady = false;
    let motionKey = '';
    let motionStartedAt = 0;
    let motionFrom = null;
    let motionTarget = null;
    let motionCurrent = null;

    const mascot = document.createElement('div');
    mascot.className = 'baron-mascot-layer hidden';
    mascot.innerHTML = `<img class="baron-mascot-image" alt="" draggable="false"><div class="baron-mascot-fallback">${mascotSvg}</div>`;
    document.body.append(mascot);

    const root = document.createElement('section');
    root.className = 'baron-assistant bubble-top hidden';
    root.setAttribute('aria-live', 'polite');
    root.innerHTML = `
      <div class="baron-assistant-text"></div>
      <div class="baron-assistant-actions"></div>`;
    document.body.append(root);

    const promoStyle = document.createElement('style');
    promoStyle.textContent = `
      .baron-promo-backdrop { position:fixed; inset:0; z-index:2147483600; display:flex; align-items:center; justify-content:center; background:rgba(4, 8, 14, .86); }
      .baron-promo-backdrop.hidden { display:none; }
      .baron-promo-card { width:min(740px, calc(100vw - 16px)); height:min(960px, calc(100vh - 16px)); background:transparent url('/static/assets/baron/promo_panel.png?v=103') center/100% 100% no-repeat; border:0; border-radius:0; box-shadow:none; padding:72px 70px 58px; box-sizing:border-box; display:flex; flex-direction:column; }
      .baron-promo-body { flex:1 1 auto; min-height:0; overflow:auto; padding:2px 10px 0 4px; scrollbar-width:thin; }
      .baron-promo-line { margin:0 0 16px; color:#172235; font:600 17.5px/1.38 "Segoe UI", Tahoma, Arial, sans-serif; letter-spacing:.005em; white-space:pre-wrap; }
      .baron-promo-heading { margin-bottom:22px; font-weight:800; font-size:21px; line-height:1.28; }
      .baron-promo-alert { color:#dd2a20; font-weight:800; text-transform:uppercase; line-height:1.36; margin-top:10px; }
      .baron-promo-link-call { display:block; margin:6px 0 8px; color:#7e1f19; font:700 17.5px/1.28 "Segoe UI", Tahoma, Arial, sans-serif; text-align:center; }
      .baron-promo-link { display:block; margin:0 0 14px; color:transparent; font:800 19px/1.24 "Segoe UI", Tahoma, Arial, sans-serif; text-transform:uppercase; text-decoration:none; text-align:center; cursor:pointer; background:linear-gradient(90deg,#ff334d,#ff9a2f,#ffe14a,#48d66f,#2ccde4,#4f7cff,#a95cff,#ff4bc1,#ff334d); background-size:320% 100%; -webkit-background-clip:text; background-clip:text; -webkit-text-fill-color:transparent; animation:baronPromoRainbow 3.2s linear infinite; }
      .baron-promo-actions { flex:0 0 auto; padding-top:10px; display:flex; justify-content:center; }
      .baron-promo-button { min-width:190px; height:38px; border:0; border-radius:999px; background:#e8eef6; color:#4a6688; font:700 17px/1 "Segoe UI", Tahoma, Arial, sans-serif; cursor:pointer; }
      .baron-promo-button:disabled { cursor:default; color:#90a0b3; }
      @keyframes baronPromoRainbow { from { background-position:0% 50%; } to { background-position:320% 50%; } }
    `;
    document.head.append(promoStyle);

    const promoBackdrop = document.createElement('div');
    promoBackdrop.className = 'baron-promo-backdrop hidden';
    promoBackdrop.innerHTML = `
      <div class="baron-promo-card" role="dialog" aria-modal="true" aria-label="Будущие возможности ArzMarket">
        <div class="baron-promo-body"></div>
        <div class="baron-promo-actions"><button type="button" class="baron-promo-button">Понятно</button></div>
      </div>`;
    document.body.append(promoBackdrop);
    const promoBodyEl = promoBackdrop.querySelector('.baron-promo-body');
    promoButtonEl = promoBackdrop.querySelector('.baron-promo-button');
    promoButtonEl.addEventListener('click', async () => {
      if (getSkipCooldownMs(performance.now()) > 0) return;
      await runAction('skip');
    });

    const mascotImg = mascot.querySelector('.baron-mascot-image');
    const mascotFallback = mascot.querySelector('.baron-mascot-fallback');
    const textEl = root.querySelector('.baron-assistant-text');
    const actionsEl = root.querySelector('.baron-assistant-actions');

    mascotImg.addEventListener('load', () => {
      mascotImg.classList.remove('failed');
      mascotFallback.classList.remove('visible');
    });
    mascotImg.addEventListener('error', () => {
      mascotImg.classList.add('failed');
      mascotFallback.classList.add('visible');
      console.error('[ArzMarket][Baron] texture load failed:', mascotImg.src);
    });

    function setPose(pose) {
      const resolved = poseAssets[pose] ? pose : 'neutral';
      if (lastPose === resolved) return;
      lastPose = resolved;
      mascotImg.classList.remove('failed');
      mascotFallback.classList.remove('visible');
      mascotImg.src = poseAssets[resolved];
    }

    function clearTarget(resetKey = false) {
      if (target) target.classList.remove('baron-target-highlight');
      target = null;
      if (resetKey) targetKey = '';
    }

    function resolveTarget(key) {
      const selector = targetSelectors[key];
      if (!selector) return null;
      const nodes = [...document.querySelectorAll(selector)];
      return nodes.find(node => {
        const rect = node.getBoundingClientRect();
        const style = getComputedStyle(node);
        return rect.width > 0 && rect.height > 0 && style.display !== 'none' && style.visibility !== 'hidden';
      }) || null;
    }

    const measureCanvas = document.createElement('canvas');
    const measureCtx = measureCanvas.getContext('2d');

    function countWrappedLines(text, maxWidth, textScale = 1) {
      if (!measureCtx) return Math.max(1, Math.ceil(Array.from(String(text || '')).length / 24));
      measureCtx.font = `700 ${27 * textScale}px Arial, sans-serif`;
      const words = String(text || '').trim().split(/\s+/).filter(Boolean);
      if (!words.length) return 1;
      let lines = 1;
      let line = '';
      for (const word of words) {
        const candidate = line ? `${line} ${word}` : word;
        if (line && measureCtx.measureText(candidate).width > maxWidth) {
          lines += 1;
          line = word;
        } else {
          line = candidate;
        }
      }
      return lines;
    }

    function bubbleMetrics(text, choice, hasActions, textScale = 1) {
      let best = null;
      const longText = String(text || '').length >= 95;
      const widths = choice
        ? (longText ? [480, 520, 560] : [440, 480, 520])
        : (longText ? [500, 540, 580, 620] : [400, 440, 480, 520]);
      for (const width of widths) {
        const inset = Math.max(longText ? 36 : 40, width * (longText ? .085 : .10));
        const lines = countWrappedLines(text, width - inset * 2, textScale);
        const textHeight = lines * 31 * textScale;
        const actionHeight = choice ? 44 : (hasActions ? 40 : 0);
        const actionGap = actionHeight > 0 ? 10 : 0;
        const contentHeight = 28 + textHeight + actionGap + actionHeight + 28;
        const height = Math.max(contentHeight, width / 1.80);
        const ratio = width / height;
        const penalty = Math.abs(ratio - 1.80) * 9000 + Math.max(0, height - 320) * 700;
        const score = width * height + penalty;
        if (!best || score < best.score) best = {width, height, inset, score};
      }
      return best;
    }

    function applyBubbleMetrics() {
      const bubbleKey = typeof snapshot?.bubbleAsset === 'string' ? snapshot.bubbleAsset : '';
      const centered = snapshot?.bubbleTextAlign === 'center';
      const isWelcome = bubbleKey === 'welcome';
      const screenScale = getScreenScale();
      const textScale = getBaronTextScale(screenScale);
      const bubbleScreenScale = getBaronBubbleScale(screenScale);

      // v225: every normal Baron reply uses exactly the same text scale on the
      // same screen. Long messages grow the bubble instead of shrinking text.
      root.style.setProperty('--baron-screen-scale', String(textScale));
      promoBackdrop.style.setProperty('--baron-screen-scale', String(textScale));

      // All visible Baron messages use PNG bubbles. The actual left/right PNG
      // is selected later from Baron's final on-screen position.
      root.classList.add('photo-bubble');
      root.style.backgroundImage = `url("${bubbleAssets.welcome_upper_left}")`;
      textEl.style.textAlign = centered ? 'center' : 'center';
      textEl.style.fontFamily = 'Arial, sans-serif';
      textEl.style.fontSize = `${27 * textScale}px`;
      textEl.style.fontWeight = '700';
      textEl.style.lineHeight = '1.16';

      if (isWelcome) {
        const width = Math.round(466 * bubbleScreenScale);
        const height = Math.round(293 * bubbleScreenScale);
        const inset = Math.round(50 * bubbleScreenScale);
        root.style.width = `${width}px`;
        root.style.height = `${height}px`;
        root.style.minHeight = `${height}px`;
        root.style.paddingLeft = `${inset}px`;
        root.style.paddingRight = `${inset}px`;
        root.style.paddingTop = `${Math.round(28 * bubbleScreenScale)}px`;
        root.style.paddingBottom = `${Math.round(54 * bubbleScreenScale)}px`;
        return {width, height, inset, screenScale, textScale, bubbleScreenScale};
      }

      const metrics = bubbleMetrics(snapshot?.text || '', !!snapshot?.choice, !!snapshot?.choice || snapshot?.canSkip === true, textScale);
      const bubbleScale = Number(snapshot?.bubbleScale || 1) || 1;
      const width = Math.round(metrics.width * bubbleScale * bubbleScreenScale);
      const height = Math.round(metrics.height * bubbleScale * bubbleScreenScale);
      const inset = Math.round(metrics.inset * Math.max(1, bubbleScale * 0.98) * bubbleScreenScale);
      root.style.width = `${width}px`;
      root.style.height = `${height}px`;
      root.style.minHeight = `${height}px`;
      root.style.paddingLeft = `${inset}px`;
      root.style.paddingRight = `${inset}px`;
      root.style.paddingTop = `${Math.round(26 * bubbleScreenScale)}px`;
      root.style.paddingBottom = `${Math.round(30 * bubbleScreenScale)}px`;
      return {...metrics, width, height, inset, screenScale, textScale, bubbleScreenScale};
    }

    function normalizedSegments(next) {
      if (Array.isArray(next?.segments) && next.segments.length) {
        return next.segments.map(segment => ({
          color: colorClasses[segment?.color] !== undefined ? segment.color : 'normal',
          chars: Array.from(String(segment?.text || ''))
        }));
      }
      return [{color: 'normal', chars: Array.from(String(next?.text || ''))}];
    }

    function resetTyping(next) {
      typedSegments = normalizedSegments(next);
      totalChars = typedSegments.reduce((sum, segment) => sum + segment.chars.length, 0);
      shown = 0;
      lastTypeAt = 0;
      textEl.textContent = '';
    }

    function renderTypedText() {
      textEl.textContent = '';
      const flow = document.createElement('span');
      flow.className = 'baron-assistant-text-flow';
      let remaining = shown;
      for (const segment of typedSegments) {
        if (remaining <= 0) break;
        const count = Math.min(remaining, segment.chars.length);
        if (count > 0) {
          const span = document.createElement('span');
          const className = colorClasses[segment.color] || '';
          if (className) span.className = className;
          span.textContent = segment.chars.slice(0, count).join('');
          flow.append(span);
        }
        remaining -= count;
      }
      textEl.append(flow);
    }

    function clamp(value, min, max) {
      return Math.max(min, Math.min(max, value));
    }

    function computeTargetLayout() {
      const screenScale = getScreenScale();
      const margin = 14 * screenScale;
      const boxW = parseFloat(root.style.width) || root.offsetWidth || 364 * screenScale;
      const boxH = parseFloat(root.style.height) || root.offsetHeight || 278 * screenScale;
      let mascotSize = 440 * screenScale * Math.max(0.55, Math.min(1.25, Number(snapshot?.mascotScale || 1) || 1));
      let mascotLeft = Math.max(margin, window.innerWidth - mascotSize - 18 * screenScale);
      let mascotTop = Math.max(margin, window.innerHeight - mascotSize - 14 * screenScale);
      let targetRect = null;

      const requestedTargetKey = String(snapshot?.target || '');
      const now = performance.now();
      const targetInvalid = target && (!target.isConnected || target.getClientRects().length === 0);
      const targetChanged = targetKey !== requestedTargetKey;
      const retryMissing = !target && requestedTargetKey && now >= targetResolveAfter;
      if (targetChanged || targetInvalid || retryMissing) {
        clearTarget();
        targetKey = requestedTargetKey;
        targetResolveAfter = now + 300;
        target = resolveTarget(requestedTargetKey);
        if (target) {
          target.classList.add('baron-target-highlight');
          missingTargetSince = 0;
          missingTargetLoggedKey = '';
        } else if (requestedTargetKey && snapshot?.optionalAnchor !== true) {
          if (!missingTargetSince || targetChanged) missingTargetSince = now;
          if (now - missingTargetSince >= 900 && missingTargetLoggedKey !== requestedTargetKey) {
            missingTargetLoggedKey = requestedTargetKey;
            console.error(`[ArzMarket][Baron] anchor missing: ${requestedTargetKey}`);
          }
        }
      }

      if (target) targetRect = target.getBoundingClientRect();
      if (snapshot?.position === 'script_left') {
        const appWindow = document.querySelector('#app .window');
        const wr = appWindow?.getBoundingClientRect?.();
        if (wr && wr.width > 0 && wr.height > 0) {
          mascotLeft = wr.left - 8 * screenScale;
          mascotTop = wr.bottom - mascotSize - 20 * screenScale;
          const maxInsideX = wr.left + Math.max(6 * screenScale, wr.width * .24 - mascotSize * .62);
          mascotLeft = Math.min(mascotLeft, maxInsideX);
        } else {
          mascotLeft = 18 * screenScale;
          mascotTop = window.innerHeight - mascotSize - 20 * screenScale;
        }
      } else if (snapshot?.position === 'screen_left') {
        mascotLeft = 18 * screenScale;
        mascotTop = window.innerHeight * .55 - mascotSize * .45;
      } else if (snapshot?.position === 'anchor' && targetRect) {
        const tr = targetRect;
        let tx = tr.left + tr.width * .5;
        let ty = tr.top + tr.height * .5;
        const pose = String(snapshot?.pose || '');
        const pointerHotspot = snapshot?.pointerHotspot;
        if (pointerHotspot && Number.isFinite(Number(pointerHotspot.x)) && Number.isFinite(Number(pointerHotspot.y))) {
          if (Number.isFinite(Number(pointerHotspot.anchorX))) tx = tr.left + tr.width * Number(pointerHotspot.anchorX);
          if (Number.isFinite(Number(pointerHotspot.anchorY))) ty = tr.top + tr.height * Number(pointerHotspot.anchorY);
          mascotLeft = tx - mascotSize * Number(pointerHotspot.x) + Number(pointerHotspot.offsetX || 0) * screenScale;
          mascotTop = ty - mascotSize * Number(pointerHotspot.y) + Number(pointerHotspot.offsetY || 0) * screenScale;
        } else if (pose === 'point_right' || pose === 'point_up_right') {
          mascotLeft = tx - mascotSize - 24 * screenScale;
          mascotTop = ty - mascotSize * .48;
        } else if (pose === 'point_left' || pose === 'point_up_left') {
          mascotLeft = tx + 24 * screenScale;
          mascotTop = ty - mascotSize * .48;
        } else if (pose === 'point_down_right') {
          // Привязываем к цели именно кончик пальца point_down_right.png.
          // Старый расчёт привязывал квадрат PNG, поэтому Барон перекрывал resize-ручку.
          const fingerX = .906;
          const fingerY = .855;
          mascotLeft = tx - mascotSize * fingerX - 8 * screenScale;
          mascotTop = ty - mascotSize * fingerY - 6 * screenScale;
        } else {
          if (tx < window.innerWidth * .5) mascotLeft = tx + 24 * screenScale;
          else mascotLeft = tx - mascotSize - 24 * screenScale;
          mascotTop = ty - mascotSize * .48;
        }
      }

      const mascotMinLeft = snapshot?.allowMascotOffscreenLeft === true ? -mascotSize * .34 : margin;
      mascotLeft = clamp(mascotLeft, mascotMinLeft, Math.max(margin, window.innerWidth - mascotSize - margin));
      mascotTop = clamp(mascotTop, margin, Math.max(margin, window.innerHeight - mascotSize - margin));

      const mascotCenterX = mascotLeft + mascotSize * .5;
      const baronHeadX = mascotLeft + mascotSize * .52;
      const baronHeadY = mascotTop + mascotSize * .18;
      const maxLeft = Math.max(margin, window.innerWidth - boxW - margin);
      const maxTop = Math.max(margin, window.innerHeight - boxH - margin);
      const overlapArea = (a, b) => {
        if (!b) return 0;
        const x = Math.max(0, Math.min(a.right, b.right) - Math.max(a.left, b.left));
        const y = Math.max(0, Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top));
        return x * y;
      };
      const mascotOnRight = mascotCenterX >= window.innerWidth * .5;
      const bubbleShiftX = (Number(snapshot?.bubbleShiftX || 0) || 0) * screenScale;
      const bubbleShiftY = (Number(snapshot?.bubbleShiftY || 0) || 0) * screenScale;
      const bubbleTargetXLeft = Number(snapshot?.bubbleTargetXLeft ?? 0.74);
      const bubbleTargetXRight = Number(snapshot?.bubbleTargetXRight ?? 0.26);
      const bubbleTargetY = Number(snapshot?.bubbleTargetY ?? 0.20);

      let variant;
      let targetBaronX;
      let targetBaronY;
      if (snapshot?.position === 'script_left') {
        // Baron is moved to the left side of the ArzMarket window, while the
        // bubble remains attached above-right and moves together with him.
        variant = { name: 'welcome_upper_right', ...bubbleGeometry.welcome_upper_right };
        targetBaronX = mascotLeft + mascotSize * .82;
        targetBaronY = mascotTop + mascotSize * .18;
      } else {
        variant = mascotOnRight
          ? { name: 'welcome_upper_left', ...bubbleGeometry.welcome_upper_left }
          : { name: 'welcome_upper_right', ...bubbleGeometry.welcome_upper_right };
        targetBaronX = mascotLeft + mascotSize * (mascotOnRight ? bubbleTargetXRight : bubbleTargetXLeft);
        targetBaronY = mascotTop + mascotSize * bubbleTargetY;
      }

      const tailX = boxW * variant.tailXFrac;
      const tailY = boxH * variant.tailYFrac;
      const rawLeft = targetBaronX - tailX + bubbleShiftX;
      const rawTop = targetBaronY - tailY + bubbleShiftY;
      const bubbleLeft = clamp(rawLeft, margin, maxLeft);
      const bubbleTop = clamp(rawTop, margin, maxTop);
      const best = {
        bubbleLeft,
        bubbleTop,
        bubbleSide: 'top',
        bubbleVariant: variant.name,
        boxW,
        boxH
      };
      return {
        mascotLeft, mascotTop, mascotSize,
        bubbleLeft: best.bubbleLeft, bubbleTop: best.bubbleTop, bubbleSide: best.bubbleSide,
        bubbleVariant: best.bubbleVariant,
        boxW, boxH
      };
    }

    function applyPosition(pos) {
      if (!pos) return;
      mascot.style.left = `${Math.round(pos.mascotLeft)}px`;
      mascot.style.top = `${Math.round(pos.mascotTop)}px`;
      mascot.style.width = `${Math.round(pos.mascotSize)}px`;
      mascot.style.height = `${Math.round(pos.mascotSize)}px`;
      root.style.left = `${Math.round(pos.bubbleLeft)}px`;
      root.style.top = `${Math.round(pos.bubbleTop)}px`;
      root.classList.remove('bubble-top', 'bubble-left', 'bubble-right');
      root.classList.add(`bubble-${pos.bubbleSide || 'top'}`);
      const bubbleCenterX = pos.bubbleLeft + (pos.boxW || root.offsetWidth || 0) * .5;
      const baronCenterX = pos.mascotLeft + pos.mascotSize * .52;
      let resolvedBubbleVariant = pos.bubbleVariant;
      if (!resolvedBubbleVariant || !bubbleAssets[resolvedBubbleVariant]) {
        const dx = baronCenterX - bubbleCenterX;
        resolvedBubbleVariant = dx >= 0 ? 'welcome_upper_left' : 'welcome_upper_right';
      }
      if (bubbleAssets[resolvedBubbleVariant]) {
        root.style.backgroundImage = `url("${bubbleAssets[resolvedBubbleVariant]}")`;
      }
      const bubbleIsLeftOfBaron = pos.bubbleLeft < pos.mascotLeft + pos.mascotSize * .5;
      const visualBaronX = pos.mascotLeft + pos.mascotSize * (bubbleIsLeftOfBaron ? .48 : .52);
      const visualBaronY = pos.mascotTop + pos.mascotSize * .18;
      const tailInset = 48 * getScreenScale();
      const tailLeft = clamp(visualBaronX - pos.bubbleLeft, tailInset, Math.max(tailInset, pos.boxW - tailInset));
      const tailTop = clamp(visualBaronY - pos.bubbleTop, tailInset, Math.max(tailInset, (pos.boxH || root.offsetHeight || 260 * getScreenScale()) - tailInset));
      root.style.setProperty('--baron-tail-left', `${Math.round(tailLeft)}px`);
      root.style.setProperty('--baron-tail-top', `${Math.round(tailTop)}px`);
    }

    function updateMotionTarget(ts) {
      if (!snapshot?.active) return;
      const next = computeTargetLayout();
      const key = `${snapshot.module || ''}:${snapshot.step || ''}`;
      if (!motionReady) {
        motionReady = true;
        motionKey = key;
        motionTarget = next;
        motionCurrent = {...next};
        motionFrom = {...next};
        motionStartedAt = ts || performance.now();
        applyPosition(motionCurrent);
        return;
      }
      if (snapshot.followAnchor) {
        motionKey = key;
        motionTarget = next;
        motionCurrent = {...next};
        motionFrom = {...next};
        motionStartedAt = ts || performance.now();
        applyPosition(motionCurrent);
        return;
      }
      if (motionKey !== key) {
        motionKey = key;
        motionFrom = {...motionCurrent};
        motionTarget = next;
        motionStartedAt = ts || performance.now();
      } else {
        motionTarget = next;
      }
    }

    function animateMotion(ts) {
      if (!motionReady || !motionTarget || !motionCurrent) return;
      if (snapshot?.followAnchor) {
        motionCurrent = {...motionTarget};
        applyPosition(motionCurrent);
        return;
      }
      const duration = 240;
      const t0 = clamp((ts - motionStartedAt) / duration, 0, 1);
      const t = t0 * t0 * (3 - 2 * t0);
      const from = motionFrom || motionCurrent;
      motionCurrent = {
        mascotLeft: from.mascotLeft + (motionTarget.mascotLeft - from.mascotLeft) * t,
        mascotTop: from.mascotTop + (motionTarget.mascotTop - from.mascotTop) * t,
        mascotSize: from.mascotSize + (motionTarget.mascotSize - from.mascotSize) * t,
        bubbleLeft: from.bubbleLeft + (motionTarget.bubbleLeft - from.bubbleLeft) * t,
        bubbleTop: from.bubbleTop + (motionTarget.bubbleTop - from.bubbleTop) * t,
        bubbleSide: motionTarget.bubbleSide,
        bubbleVariant: motionTarget.bubbleVariant,
        boxW: motionTarget.boxW,
        boxH: motionTarget.boxH
      };
      applyPosition(motionCurrent);
    }

    async function runAction(name, payload = {}) {
      if (typeof callAction !== 'function') return;
      try {
        await callAction('assistant.action', {...payload, assistantAction: name, sessionGeneration: snapshot?.sessionGeneration});
        if (typeof refresh === 'function') await refresh(true);
      } catch (err) {
        console.error('[ArzMarket][Baron] action failed:', err);
      }
    }

    function button(label, className, handler) {
      const b = document.createElement('button');
      b.type = 'button';
      b.textContent = label;
      if (className) b.className = className;
      b.addEventListener('click', handler);
      return b;
    }

    function getSkipCooldownMs(now = performance.now()) {
      const base = Number(snapshot?.skipCooldownMs || 0);
      if (!(base > 0)) return 0;
      return Math.max(0, base - (now - snapshotReceivedAt));
    }

    function updateSkipButtonState(now = performance.now()) {
      const remain = getSkipCooldownMs(now);
      if (skipButtonEl) {
        if (remain > 0) {
          skipButtonEl.disabled = true;
          skipButtonEl.textContent = `Пропустить (${Math.ceil(remain / 1000)})`;
        } else {
          skipButtonEl.disabled = false;
          skipButtonEl.textContent = 'Пропустить';
        }
      }
      if (promoButtonEl) {
        const baseLabel = String(snapshot?.promoButtonText || 'Понятно');
        if (remain > 0) {
          promoButtonEl.disabled = true;
          promoButtonEl.textContent = `${baseLabel} (${Math.ceil(remain / 1000)})`;
        } else {
          promoButtonEl.disabled = false;
          promoButtonEl.textContent = baseLabel;
        }
      }
    }

    const MYSTERY_COOLDOWN_GLYPHS = ['¤', '§', '∆', '⊗', '※', '↯', '◊', 'Ψ', '₪', '☼', '⌘', '▓', '¿', '✶', '☍', '⟡'];

    function buildMysteryCooldownGlyphs(seed = Math.floor(Date.now() / 1000)) {
      const tick = Math.max(0, Math.floor(Number(seed) || 0));
      const total = MYSTERY_COOLDOWN_GLYPHS.length;
      const a = MYSTERY_COOLDOWN_GLYPHS[tick % total] || '?';
      const b = MYSTERY_COOLDOWN_GLYPHS[(tick * 3 + 1) % total] || '?';
      const c = MYSTERY_COOLDOWN_GLYPHS[(tick * 5 + 2) % total] || '?';
      return `${a}${b}${c}`;
    }

    function getChoiceNoCooldownLabel(remain) {
      if (snapshot?.choiceType === 'future_details') {
        return `Нет (осталось сек: ${buildMysteryCooldownGlyphs()})`;
      }
      if (!(remain > 0)) return 'Нет';
      return `Нет (${Math.ceil(remain / 1000)})`;
    }

    function getChoiceNoCooldownMs(now = performance.now()) {
      const base = Number(snapshot?.choiceNoCooldownMs || 0);
      if (!(base > 0)) return 0;
      return Math.max(0, base - (now - snapshotReceivedAt));
    }

    function updateChoiceNoButtonState(now = performance.now()) {
      if (!choiceNoButtonEl) return;
      if (snapshot?.choiceType === 'future_details') {
        choiceNoButtonEl.disabled = true;
        choiceNoButtonEl.textContent = getChoiceNoCooldownLabel(0);
        return;
      }
      const remain = getChoiceNoCooldownMs(now);
      if (remain > 0) {
        choiceNoButtonEl.disabled = true;
        choiceNoButtonEl.textContent = getChoiceNoCooldownLabel(remain);
      } else {
        choiceNoButtonEl.disabled = false;
        choiceNoButtonEl.textContent = 'Нет';
      }
    }

    function renderPromoWindow() {
      if (!promoButtonEl) return;
      const active = Boolean(snapshot?.active && snapshot?.promoWindow === true);
      promoBackdrop.classList.toggle('hidden', !active);
      if (!active) return;
      promoBodyEl.textContent = '';
      const lines = Array.isArray(snapshot?.promoLines) ? snapshot.promoLines : [];
      const promoRedFrom = Number(snapshot?.promoRedFrom || (lines.length + 1));
      lines.forEach((line, index) => {
        const div = document.createElement('div');
        div.className = 'baron-promo-line';
        if (index === 0) div.classList.add('baron-promo-heading');
        if ((index + 1) >= promoRedFrom) div.classList.add('baron-promo-alert');
        div.textContent = String(line || '');
        promoBodyEl.append(div);
      });
      const linkLabel = String(snapshot?.promoLinkLabel || '').trim();
      const linkUrl = String(snapshot?.promoLinkUrl || '').trim();
      const linkIntro = String(snapshot?.promoLinkIntro || 'Нажми на эту ссылку:').trim();
      if (linkLabel && linkUrl) {
        if (linkIntro) {
          const intro = document.createElement('div');
          intro.className = 'baron-promo-link-call';
          intro.textContent = linkIntro;
          promoBodyEl.append(intro);
        }
        const link = document.createElement('a');
        link.className = 'baron-promo-link';
        link.href = linkUrl;
        link.textContent = linkLabel;
        link.target = '_blank';
        link.rel = 'noopener noreferrer';
        link.addEventListener('click', async (event) => {
          event.preventDefault();
          try {
            await runAction('open_url', {url: linkUrl});
          } catch (err) {
            try { window.open(linkUrl, '_blank', 'noopener'); } catch (_) {}
          }
        });
        promoBodyEl.append(link);
      }
      updateSkipButtonState(performance.now());
    }

    function renderActions() {
      actionsEl.textContent = '';
      actionsEl.style.display = '';
      actionsEl.classList.remove('baron-link-actions');
      skipButtonEl = null;
      choiceNoButtonEl = null;
      if (!snapshot?.active || snapshot.messageVisible === false) {
        actionsEl.style.display = 'none';
        return;
      }
      if (snapshot.choiceType === 'interface') {
        actionsEl.append(
          button('Старый', 'interface-old', () => runAction('interface_select', {mode:'lua'})),
          button('Новый', 'interface-new', () => runAction('interface_select', {mode:'html'}))
        );
        return;
      }
      if (snapshot.choiceType === 'tutorial') {
        actionsEl.append(
          button('Пройти обучение', 'primary tutorial-accept', () => runAction('tutorial_accept'))
        );
        return;
      }
      if (snapshot.choiceType === 'lua_redirect') {
        const yesButton = button('Да', 'primary lua-redirect-yes', () => runAction('lua_redirect_yes'));
        choiceNoButtonEl = button('Нет', 'lua-redirect-no', async () => {
          if (getChoiceNoCooldownMs(performance.now()) > 0) return;
          await runAction('lua_redirect_no');
        });
        actionsEl.append(yesButton, choiceNoButtonEl);
        updateChoiceNoButtonState(performance.now());
        return;
      }
      if (snapshot.choiceType === 'future_details') {
        actionsEl.classList.add('future-details-actions');
        const yesButton = button('Да', 'primary future-details-yes', () => runAction('future_details_yes'));
        choiceNoButtonEl = button('Нет', 'future-details-no', () => {});
        actionsEl.append(yesButton, choiceNoButtonEl);
        updateChoiceNoButtonState(performance.now());
        return;
      }
      const messageLinkLabel = String(snapshot?.messageLinkLabel || '').trim();
      const messageLinkUrl = String(snapshot?.messageLinkUrl || '').trim();
      if (messageLinkLabel && messageLinkUrl) {
        actionsEl.classList.add('baron-link-actions');
        const linkButton = button(messageLinkLabel, 'baron-message-link', async () => {
          await runAction('open_url', {url: messageLinkUrl});
        });
        actionsEl.append(linkButton);
        if (snapshot?.canSkip === true) {
          skipButtonEl = button('Завершить', '', async () => {
            if (getSkipCooldownMs(performance.now()) > 0) return;
            await runAction('skip');
          });
          actionsEl.append(skipButtonEl);
          updateSkipButtonState(performance.now());
          if (skipButtonEl && getSkipCooldownMs(performance.now()) <= 0) skipButtonEl.textContent = 'Завершить';
        }
        return;
      }
      actionsEl.classList.remove('baron-link-actions');
      if (snapshot?.canSkip !== true) {
        actionsEl.style.display = 'none';
        return;
      }
      skipButtonEl = button('Пропустить', '', async () => {
        if (getSkipCooldownMs(performance.now()) > 0) return;
        if (snapshot?.skipAction === 'open_page' && typeof openPage === 'function') {
          await openPage(snapshot.expectedPage || snapshot.requiredPage);
          return;
        }
        if (snapshot?.skipAction === 'open_filter' && typeof openFilter === 'function') {
          await openFilter();
          return;
        }
        if (snapshot?.skipAction === 'open_settings_appearance' && typeof openSettingsSection === 'function') {
          await openSettingsSection('appearance', true);
          return;
        }
        await runAction('skip');
      });
      actionsEl.append(skipButtonEl);
      updateSkipButtonState(performance.now());
    }

    function tick(ts) {
      raf = 0;
      if (!snapshot?.active || document.visibilityState === 'hidden') return;

      if (snapshot.messageVisible !== false) {
        if (!lastTypeAt) lastTypeAt = ts;
        const elapsed = Math.max(0, ts - lastTypeAt);
        const add = Math.floor(elapsed / 12);
        if (add > 0 && shown < totalChars) {
          shown = Math.min(totalChars, shown + add);
          lastTypeAt += add * 12;
          renderTypedText();
        }
      }

      updateSkipButtonState(ts);
      updateChoiceNoButtonState(ts);
      updateMotionTarget(ts);
      animateMotion(ts);
      raf = requestAnimationFrame(tick);
    }

    function startTicking() {
      if (!raf && snapshot?.active && document.visibilityState !== 'hidden') {
        raf = requestAnimationFrame(tick);
      }
    }

    function stopTicking() {
      if (raf) cancelAnimationFrame(raf);
      raf = 0;
    }

    function render(next) {
      snapshot = next || {active:false};
      snapshotReceivedAt = performance.now();
      const app = document.getElementById('app');
      app?.classList.toggle('baron-tutorial-active', Boolean(snapshot.active && String(snapshot.module || '').startsWith('tutorial_')));
      if (snapshot.step) app?.setAttribute('data-baron-step', String(snapshot.step));
      else app?.removeAttribute('data-baron-step');
      if (!snapshot.active) {
        stopTicking();
        root.classList.add('hidden');
        mascot.classList.add('hidden');
        promoBackdrop.classList.add('hidden');
        clearTarget(true);
        targetResolveAfter = 0;
        missingTargetSince = 0;
        missingTargetLoggedKey = '';
        restoredSettingsKey = '';
        motionReady = false;
        return;
      }

      if (snapshot.hideMascot === true || snapshot.promoWindow === true) mascot.classList.add('hidden');
      else mascot.classList.remove('hidden');
      if (snapshot.messageVisible === false) root.classList.add('hidden');
      else root.classList.remove('hidden');
      setPose(snapshot.pose || 'neutral');

      // The filter panel is the anchor for sell_filter_1..5. Keep it open not only
      // after the initial click, but also after Skip and after restoring a saved step.
      if (/^sell_filter_[1-5]$/.test(String(snapshot.step || '')) && typeof ensureFilterOpen === 'function') {
        try { ensureFilterOpen(); } catch (err) {
          console.error('[ArzMarket][Baron] failed to keep filter panel open:', err);
        }
      }
      const settingsRestoreKey = snapshot.requiredSettingsSection
        ? `${snapshot.module || ''}:${snapshot.step || ''}:${snapshot.requiredSettingsSection}`
        : '';
      if (settingsRestoreKey && settingsRestoreKey !== restoredSettingsKey && typeof openSettingsSection === 'function') {
        restoredSettingsKey = settingsRestoreKey;
        Promise.resolve(openSettingsSection(snapshot.requiredSettingsSection, false)).catch(err => {
          restoredSettingsKey = '';
          console.error('[ArzMarket][Baron] settings restore failed:', err);
        });
      } else if (!settingsRestoreKey) {
        restoredSettingsKey = '';
      }

      if (snapshot.step === 'settings_glow' || snapshot.step === 'settings_theme_try') {
        const targetNode = resolveTarget(snapshot.target || snapshot.anchor);
        const settingsScroller = document.getElementById('settingsContent');
        if (targetNode && settingsScroller && settingsScroller.contains(targetNode)) {
          const tr = targetNode.getBoundingClientRect();
          const sr = settingsScroller.getBoundingClientRect();
          if (tr.top < sr.top + 18 || tr.bottom > sr.bottom - 18) {
            settingsScroller.scrollTop += (tr.top + tr.height * 0.5) - (sr.top + sr.height * 0.5);
          }
        }
      }

      const messageKey = `${snapshot.module || ''}:${snapshot.step || ''}:${snapshot.text || ''}`;
      if (lastMessageKey !== messageKey) {
        lastMessageKey = messageKey;
        if (snapshot.step === 'sell_filter_prompt' || snapshot.step === 'sell_currency' || snapshot.step === 'sell_config' || snapshot.step === 'go_buy') {
          const panel = document.getElementById('tradeFilterPanel');
          const button = document.getElementById('tradeFilterButton');
          panel?.classList.add('hidden');
          button?.classList.remove('active');
          button?.setAttribute('aria-expanded', 'false');
        }
        resetTyping(snapshot);
        root.classList.add('entering');
        requestAnimationFrame(() => root.classList.remove('entering'));
      }

      renderPromoWindow();
      if (snapshot.messageVisible !== false) applyBubbleMetrics();
      renderActions();
      updateMotionTarget(performance.now());
      startTicking();
    }

    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'hidden') stopTicking();
      else startTicking();
    });
    window.addEventListener('resize', () => {
      if (snapshot?.active && snapshot.messageVisible !== false) applyBubbleMetrics();
      updateMotionTarget(performance.now());
    });

    return {
      render,
      event(name, payload = {}) { return runAction('event', {...payload, name}); },
      resized() { runAction('event', {name:'resize_changed'}); },
      isAnimating() { return raf !== 0; },
      destroy() {
        stopTicking();
        clearTarget();
        mascot.remove();
        root.remove();
        promoBackdrop.remove();
        promoStyle.remove();
      }
    };
  }

  window.ArzBaronAssistantUI = { create };
})();
