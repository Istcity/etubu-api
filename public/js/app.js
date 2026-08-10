/**
 * ETUBU — web: tüm katalog ücretsiz, gelir yalnızca reklam; Google = ayar hatırlama
 */
(() => {
  const $ = (id) => document.getElementById(id);
  const t = (key, vars) => (typeof I18n !== "undefined" ? I18n.t(key, vars) : key);

  const DEFAULT_VOICE = () => "silent-mode";
  const DEFAULT_VISUAL = () => Scene.DEFAULT_MODE || "glow";

  const startBtn = $("startBtn");
  const previewBtn = $("previewBtn");
  const lockPortraitBtn = $("lockPortraitBtn");
  const lockLandscapeBtn = $("lockLandscapeBtn");
  const voiceSelect = $("voiceSelect");
  const visualSelect = $("visualSelect");
  const volumeSlider = $("volumeSlider");
  const maxSpeedSlider = $("maxSpeedSlider");
  const sensitivitySlider = $("sensitivitySlider");
  const mapOpacitySlider = $("mapOpacitySlider");
  const speedValue = $("speedValue");
  const hudWarnSide = $("hudWarnSide");
  const hudWarnLabel = $("hudWarnLabel");
  const hudWarn = $("hudWarn");
  const hudWarnMeta = $("hudWarnMeta");
  const warnReel = $("warnReel");
  const warnReelTrack = $("warnReelTrack");
  const hudWarnBand = $("hudWarnBand");
  const hudWarnBandIcon = $("hudWarnBandIcon");
  const hudWarnBandText = $("hudWarnBandText");
  const hudWarnBandDist = $("hudWarnBandDist");
  const speedLimitBadge = $("speedLimitBadge");
  const speedLimitValue = $("speedLimitValue");
  const critNear = $("critNear");
  const critNearList = $("critNearList");
  const speedHudEl = $("speedHud");
  let warnReelKey = "";
  let warnReelIndex = 0;
  const ringFill = $("ringFill");
  const analogNeedle = $("analogNeedle");
  const analogSpeedValue = $("analogSpeedValue");
  const minimalSpeedValue = $("minimalSpeedValue");
  const barsSpeedValue = $("barsSpeedValue");
  const speedBarEqL = $("speedBarEqL");
  const speedBarEqR = $("speedBarEqR");
  const EQ_SEGMENTS = 24;
  let eqSegsL = [];
  let eqSegsR = [];

  function buildEqColumn(track) {
    if (!track) return [];
    track.innerHTML = "";
    const segs = [];
    for (let i = 0; i < EQ_SEGMENTS; i++) {
      const seg = document.createElement("div");
      seg.className = "speed-bar-seg";
      // Alttan üste net yeşil → sarı → kırmızı
      const t = i / Math.max(1, EQ_SEGMENTS - 1);
      let hue;
      if (t < 0.55) hue = Math.round(120 - (t / 0.55) * 60); // 120→60
      else hue = Math.round(60 - ((t - 0.55) / 0.45) * 60); // 60→0
      seg.dataset.hue = String(Math.max(0, Math.min(120, hue)));
      track.appendChild(seg);
      segs.push(seg);
    }
    return segs;
  }

  function initEqBars() {
    eqSegsL = buildEqColumn(speedBarEqL);
    eqSegsR = buildEqColumn(speedBarEqR);
  }

  function paintEqColumn(segs, pct) {
    const onCount = Math.round(Math.min(1, Math.max(0, pct)) * EQ_SEGMENTS);
    segs.forEach((seg, i) => {
      const on = i < onCount;
      seg.classList.toggle("is-on", on);
      if (on) {
        const hue = Number(seg.dataset.hue) || 120;
        const light = hue > 70 ? 48 : hue > 30 ? 50 : 52;
        seg.style.background = `hsl(${hue}, 95%, ${light}%)`;
        seg.style.boxShadow = `0 0 8px hsla(${hue}, 100%, 50%, 0.55)`;
      } else {
        seg.style.background = "";
        seg.style.boxShadow = "";
      }
    });
  }

  function paintEqBars(speedPct) {
    const pct = Math.min(1, Math.max(0, speedPct));
    paintEqColumn(eqSegsL, pct);
    paintEqColumn(eqSegsR, pct);
  }
  const speedGaugeWrap = $("speedGaugeWrap");
  const gaugeDots = $("gaugeDots");
  const avgSpeedPanel = $("avgSpeedPanel");
  const avgSpeedValue = $("avgSpeedValue");
  const avgSpeedLabel = $("avgSpeedLabel");
  const avgSpeedMeta = $("avgSpeedMeta");
  const avgSpeedBadge = $("avgSpeedBadge");
  const avgSpeedReset = $("avgSpeedReset");
  let corridorPulseTimer = null;
  let lastCorridorTrackId = null;
  const modeChip = $("modeChip");
  const maxSpeedLabel = $("maxSpeedLabel");
  const volumeLabel = $("volumeLabel");
  const maxSpeedPctLabel = $("maxSpeedPctLabel");
  const sensitivityLabel = $("sensitivityLabel");
  const mapOpacityLabel = $("mapOpacityLabel");
  const inviteDock = $("inviteDock");
  const voiceLockHint = $("voiceLockHint");
  const panelToggle = $("panelToggle");
  const demoBtn = $("demoBtn");
  const focusLockEl = $("focusLock");

  const ORIENT_KEY = "etubu_orient_lock";
  const PANEL_KEY = "etubu_panel_hidden";
  const MAP_OPACITY_KEY = "etubu_map_opacity";
  let orientLock = "none";

  let running = false;
  let previewStop = null;
  let demoMode = false;
  let wakeLock = null;
  let tapCount = 0;
  let focusLocked = false;
  let focusUnlockTimer = null;
  const RING_CIRC = 868;

  /** Tüm barlar 0–100%; gerçek değere map */
  const MAX_SPEED_MIN = 40;
  const MAX_SPEED_MAX = 200;
  const VOL_MAX = 3.2;
  const SENS_MIN = 1;
  const SENS_MAX = 2.2;

  function clampPct(raw) {
    const n = parseFloat(raw);
    if (!Number.isFinite(n)) return 0;
    return Math.round(Math.min(100, Math.max(0, n)));
  }

  function setPctLabel(el, pct) {
    if (!el) return;
    el.textContent = `${pct}%`;
    el.value = pct;
  }

  function pctToMaxKmh(pct) {
    return Math.round(MAX_SPEED_MIN + (clampPct(pct) / 100) * (MAX_SPEED_MAX - MAX_SPEED_MIN));
  }

  function maxKmhToPct(kmh) {
    return clampPct(((kmh - MAX_SPEED_MIN) / (MAX_SPEED_MAX - MAX_SPEED_MIN)) * 100);
  }

  function pctToVolume(pct) {
    return (clampPct(pct) / 100) * VOL_MAX;
  }

  function pctToSensitivity(pct) {
    return SENS_MIN + (clampPct(pct) / 100) * (SENS_MAX - SENS_MIN);
  }

  function readMaxKmh() {
    return pctToMaxKmh(maxSpeedSlider?.value ?? 56);
  }

  function readVolume() {
    return pctToVolume(volumeSlider?.value ?? defaultVolumePct());
  }

  function readSensitivity() {
    return pctToSensitivity(sensitivitySlider?.value ?? 20);
  }

  function defaultVolumePct() {
    return typeof CarBrowser !== "undefined" && CarBrowser.isTesla?.() ? 70 : 55;
  }

  function prefGet(name) {
    try {
      if (typeof CarBrowser !== "undefined" && CarBrowser.getPref) {
        return CarBrowser.getPref(name);
      }
    } catch (_) {}
    return null;
  }

  function prefSet(name, value) {
    try {
      if (typeof CarBrowser !== "undefined" && CarBrowser.setPref) {
        CarBrowser.setPref(name, value);
        CarBrowser.refreshTeslaHint?.();
        return;
      }
    } catch (_) {}
  }

  function syncVolumeUi() {
    const pct = clampPct(volumeSlider?.value ?? defaultVolumePct());
    if (volumeSlider) volumeSlider.value = String(pct);
    setPctLabel(volumeLabel, pct);
  }

  function ensureTeslaVolumeDefault() {
    if (!(typeof CarBrowser !== "undefined" && CarBrowser.isTesla?.())) return;
    if (!volumeSlider) return;
    const raw = parseFloat(volumeSlider.value);
    // HTML varsayılanı 40 — Tesla kabinde sessiz kalmasın
    if (!Number.isFinite(raw) || raw <= 40) {
      volumeSlider.value = "70";
    }
  }

  function syncMaxSpeedUi() {
    const pct = clampPct(maxSpeedSlider?.value ?? 56);
    if (maxSpeedSlider) maxSpeedSlider.value = String(pct);
    setPctLabel(maxSpeedPctLabel, pct);
    if (maxSpeedLabel) maxSpeedLabel.textContent = `${pctToMaxKmh(pct)} km/h`;
  }

  function syncSensitivityUi() {
    const pct = clampPct(sensitivitySlider?.value ?? 20);
    if (sensitivitySlider) sensitivitySlider.value = String(pct);
    setPctLabel(sensitivityLabel, pct);
  }

  function loadMapOpacityPct() {
    try {
      const v = parseFloat(localStorage.getItem(MAP_OPACITY_KEY));
      // Eski varsayılanlar → yeni 96 (bir kez yükselt)
      if (Number.isFinite(v)) {
        if ((v === 70 || v === 88) && !localStorage.getItem(MAP_OPACITY_KEY + "_v3")) {
          localStorage.setItem(MAP_OPACITY_KEY + "_v3", "1");
          localStorage.setItem(MAP_OPACITY_KEY, "96");
          return 96;
        }
        return clampPct(v);
      }
      return 96;
    } catch (_) {
      return 96;
    }
  }

  function saveMapOpacityPct(pct) {
    try {
      localStorage.setItem(MAP_OPACITY_KEY, String(clampPct(pct)));
    } catch (_) {}
  }

  function applyMapOpacity(pct) {
    const ratio = clampPct(pct) / 100;
    const mapEl = $("hudMap");
    if (mapEl) mapEl.style.setProperty("--map-opacity", String(ratio));
  }

  function syncMapOpacityUi() {
    const pct = clampPct(mapOpacitySlider?.value ?? loadMapOpacityPct());
    if (mapOpacitySlider) mapOpacitySlider.value = String(pct);
    setPctLabel(mapOpacityLabel, pct);
    applyMapOpacity(pct);
  }

  function unlocked() {
    return (
      demoMode ||
      Paywall.hasCatalogAccess(GpsTracker.getTotalKm?.() ?? GpsTracker.loadTotalKm())
    );
  }

  function populateVoices() {
    if (!voiceSelect) return;
    const prev = voiceSelect.value;
    voiceSelect.innerHTML = "";
    const full = unlocked();
    const order =
      AudioEngine.getVoiceGroupOrder?.() || ["theme", "ev"];
    const labelKeys = {
      theme: "voiceGroupTheme",
      ev: "voiceGroupEv",
      exhaust: "voiceGroupExhaust",
      race: "voiceGroupRace",
      fx: "voiceGroupFx",
      sim: "voiceGroupSim",
      proc: "voiceGroupProc",
      grain: "voiceGroupGrain",
    };
    const groups = {};
    order.forEach((id) => {
      const g = document.createElement("optgroup");
      g.label = t(labelKeys[id] || id);
      g.dataset.group = id;
      groups[id] = g;
    });
    AudioEngine.getVoices().forEach((v) => {
      // Sessiz mod herkese açık
      if (!full && v.key !== DEFAULT_VOICE() && v.key !== "silent-mode") return;
      const opt = document.createElement("option");
      opt.value = v.key;
      opt.textContent = v.label;
      const gid = v.group || v.family || "ev";
      (groups[gid] || groups.ev).appendChild(opt);
    });
    order.forEach((id) => {
      if (groups[id]?.children.length) voiceSelect.appendChild(groups[id]);
    });
    // Eski/kaldırılmış ses anahtarlarını yeni kataloga düşür
    const valid = new Set([...voiceSelect.options].map((o) => o.value));
    if (valid.has(prev) && full) {
      voiceSelect.value = prev;
    } else if (prev === "silent-mode" && valid.has("silent-mode")) {
      voiceSelect.value = "silent-mode";
    } else {
      voiceSelect.value = DEFAULT_VOICE();
    }
    voiceSelect.disabled = !full && voiceSelect.options.length <= 1;
    if (voiceLockHint) voiceLockHint.hidden = full;
  }

  function populateVisuals() {
    if (!visualSelect) return;
    const prev = visualSelect.value;
    visualSelect.innerHTML = "";
    const full = unlocked();
    const gaugeGroups = {
      digital: document.createElement("optgroup"),
      analog: document.createElement("optgroup"),
    };
    gaugeGroups.digital.label = t("visualGroupDigital");
    gaugeGroups.analog.label = t("visualGroupAnalog");
    Scene.getModes().forEach((m) => {
      if (!full && m.key !== DEFAULT_VISUAL()) return;
      const opt = document.createElement("option");
      opt.value = m.key;
      const translated = t(m.labelKey);
      opt.textContent = translated === m.labelKey ? (m.label || m.key) : translated;
      const gid = m.gauge === "analog" ? "analog" : "digital";
      gaugeGroups[gid].appendChild(opt);
    });
    if (gaugeGroups.digital.children.length) visualSelect.appendChild(gaugeGroups.digital);
    if (gaugeGroups.analog.children.length) visualSelect.appendChild(gaugeGroups.analog);
    const validVis = new Set([...visualSelect.options].map((o) => o.value));
    const prevResolved = prev === "aurora" ? "glow" : prev;
    if (validVis.has(prevResolved) && full) {
      visualSelect.value = prevResolved;
    } else {
      visualSelect.value = DEFAULT_VISUAL();
    }
    visualSelect.disabled = !full && visualSelect.options.length <= 1;
    applyVisualTheme(visualSelect.value);
  }

  function refreshCatalogUi() {
    populateVoices();
    populateVisuals();
    Picker.refreshAll?.();
    if (inviteDock) inviteDock.hidden = true;
    // Web: her zaman reklam (ücretsiz model) — Tesla’da yer kaplamasın
    const tesla = typeof CarBrowser !== "undefined" && CarBrowser.isTesla?.();
    if (tesla || (typeof CarBrowser !== "undefined" && CarBrowser.isEphemeral?.())) {
      document.body.classList.add("ads-hidden");
      Ads.hideAll?.();
      CarBrowser.forceCompactChrome?.();
    } else {
      document.body.classList.remove("ads-hidden");
      if (!Paywall.isAdFree()) {
        Ads.showRails?.();
      } else {
        document.body.classList.add("ads-hidden");
        Ads.hideAll?.();
      }
    }
    syncDriveFocus(document.body.classList.contains("panel-hidden"));
  }

  async function forceDefaultVoiceIfLocked() {
    if (unlocked()) return;
    const voice = voiceSelect?.value === "silent-mode" ? "silent-mode" : DEFAULT_VOICE();
    const visual = DEFAULT_VISUAL();
    if (visualSelect) visualSelect.value = visual;
    applyVisualTheme(visual);
    if (voiceSelect) voiceSelect.value = voice;
    if (running) {
      await AudioEngine.start(voice);
      AudioEngine.setMaxKmh(readMaxKmh());
      AudioEngine.setVolume(readVolume());
      MusicHub.applyMix?.();
    }
  }

  const GAUGE_SCREENS = ["digital", "analog", "minimal", "bars"];
  const GAUGE_KEY = "etubu_gauge_screen";
  let gaugeScreen = "digital";

  function setGaugeScreen(name, persist = true) {
    if (!GAUGE_SCREENS.includes(name)) name = "digital";
    gaugeScreen = name;
    speedGaugeWrap?.setAttribute("data-gauge", name);
    speedGaugeWrap?.querySelectorAll(".gauge-screen").forEach((el) => {
      const on = el.dataset.screen === name;
      el.hidden = !on;
    });
    gaugeDots?.querySelectorAll(".gauge-dot").forEach((dot) => {
      dot.classList.toggle("active", dot.dataset.gaugeGoto === name);
    });
    if (persist) {
      prefSet("gauge", name);
      try {
        localStorage.setItem(GAUGE_KEY, name);
      } catch (_) {}
    }
  }

  function cycleGaugeScreen() {
    const i = GAUGE_SCREENS.indexOf(gaugeScreen);
    setGaugeScreen(GAUGE_SCREENS[(i + 1) % GAUGE_SCREENS.length]);
  }

  function loadGaugeScreen() {
    let saved = "digital";
    try {
      saved = prefGet("gauge") || localStorage.getItem(GAUGE_KEY) || "digital";
    } catch (_) {}
    setGaugeScreen(saved, false);
  }

  const ANALOG_MAX_KMH = 250;

  function updateAnalogScale() {
    const spans = document.querySelectorAll(".analog-scale span");
    if (!spans.length) return;
    const step = ANALOG_MAX_KMH / (spans.length - 1);
    spans.forEach((span, i) => {
      span.style.setProperty("--i", String(i));
      span.textContent = String(Math.round(step * i));
    });
  }

  function setRing(kmh, maxKmh) {
    const digPct = Math.min(1, Math.max(0, kmh / maxKmh));
    if (ringFill) {
      ringFill.style.strokeDasharray = String(RING_CIRC);
      ringFill.style.strokeDashoffset = String(RING_CIRC * (1 - digPct));
    }
    // Analog kadran sabit 0–250 — açı yuvarlanır, mikro titreme kesilir
    if (analogNeedle) {
      const aPct = Math.min(1, Math.max(0, kmh / ANALOG_MAX_KMH));
      const angle = -120 + aPct * 240;
      const q = Math.round(angle * 2) / 2; // 0.5° adım
      if (
        setRing._lastAngle == null ||
        Math.abs(q - setRing._lastAngle) >= 0.45
      ) {
        setRing._lastAngle = q;
        analogNeedle.style.transform = `rotate(${q}deg)`;
      }
    }
    // Yan equalizer sütunlar: üst üste parçalar, yeşil→kırmızı
    paintEqBars(digPct);
    setSpeedColors(kmh, maxKmh);
  }

  let gaugeTargetKmh = 0;
  let gaugeSmoothKmh = 0;
  let gaugeRaf = null;
  let gaugeLastShown = -1;

  function paintGaugeHud(kmh) {
    hudDisplayKmh = kmh;
    const shown = Math.round(kmh);
    if (shown !== gaugeLastShown) {
      gaugeLastShown = shown;
      const shownStr = String(shown);
      if (speedValue) speedValue.textContent = shownStr;
      if (analogSpeedValue) analogSpeedValue.textContent = shownStr;
      if (minimalSpeedValue) minimalSpeedValue.textContent = shownStr;
      if (barsSpeedValue) barsSpeedValue.textContent = shownStr;
    }
    setRing(kmh, readMaxKmh());
  }

  function startGaugeSmooth() {
    if (gaugeRaf != null) return;
    const tick = () => {
      // Sürüşte gösterge = ses hattı (tek kaynak → GPS–ses–HUD kilitli)
      if (running && typeof AudioEngine.getSmoothKmh === "function") {
        gaugeSmoothKmh = AudioEngine.getSmoothKmh();
        gaugeTargetKmh = gaugeSmoothKmh;
      } else {
        const rising = gaugeTargetKmh >= gaugeSmoothKmh;
        const a = rising ? 0.88 : 0.2;
        gaugeSmoothKmh += (gaugeTargetKmh - gaugeSmoothKmh) * a;
        if (Math.abs(gaugeTargetKmh - gaugeSmoothKmh) < 0.06) {
          gaugeSmoothKmh = gaugeTargetKmh;
        }
        if (gaugeTargetKmh < 0.35 && gaugeSmoothKmh < 0.55) gaugeSmoothKmh = 0;
      }
      paintGaugeHud(gaugeSmoothKmh);
      // Idle: hedef 0 ve sürüş yoksa rAF’ı kes — kendi kendine titreme yok
      if (!running && gaugeTargetKmh < 0.2 && gaugeSmoothKmh < 0.2) {
        gaugeSmoothKmh = 0;
        paintGaugeHud(0);
        stopGaugeSmooth();
        return;
      }
      gaugeRaf = requestAnimationFrame(tick);
    };
    gaugeRaf = requestAnimationFrame(tick);
  }

  function stopGaugeSmooth() {
    if (gaugeRaf != null) {
      cancelAnimationFrame(gaugeRaf);
      gaugeRaf = null;
    }
  }

  function setGaugeTarget(kmh) {
    gaugeTargetKmh = Math.max(0, Number(kmh) || 0);
    if (!running && gaugeTargetKmh < 0.2) {
      gaugeSmoothKmh = 0;
      stopGaugeSmooth();
      paintGaugeHud(0);
      return;
    }
    startGaugeSmooth();
  }

  function resetGaugesIdle() {
    gaugeTargetKmh = 0;
    gaugeSmoothKmh = 0;
    stopGaugeSmooth();
    paintGaugeHud(0);
    setRing(0, readMaxKmh());
    Scene.setSpeed(0, readMaxKmh());
  }

  let driveSession = 0;
  let startInFlight = false;
  let themeCueReady = false;
  let lastCorridorOverKey = "";

  function playThemeChangeSound() {
    if (!themeCueReady) return;
    try {
      const Ctx = window.AudioContext || window.webkitAudioContext;
      if (!Ctx) return;
      if (!window.__etubuBeepCtx) window.__etubuBeepCtx = new Ctx();
      const ctx = window.__etubuBeepCtx;
      if (ctx.state === "suspended") ctx.resume().catch(() => {});
      const t0 = ctx.currentTime;
      // Soft whoosh: brief noise-like filtered sweep via two detuned sines
      const o1 = ctx.createOscillator();
      const o2 = ctx.createOscillator();
      const g = ctx.createGain();
      const f = ctx.createBiquadFilter();
      o1.type = "sine";
      o2.type = "triangle";
      o1.frequency.setValueAtTime(420, t0);
      o1.frequency.exponentialRampToValueAtTime(880, t0 + 0.09);
      o2.frequency.setValueAtTime(640, t0);
      o2.frequency.exponentialRampToValueAtTime(320, t0 + 0.12);
      f.type = "lowpass";
      f.frequency.setValueAtTime(1800, t0);
      f.frequency.exponentialRampToValueAtTime(600, t0 + 0.14);
      g.gain.setValueAtTime(0.0001, t0);
      g.gain.exponentialRampToValueAtTime(0.11, t0 + 0.018);
      g.gain.exponentialRampToValueAtTime(0.0001, t0 + 0.16);
      o1.connect(f);
      o2.connect(f);
      f.connect(g);
      g.connect(ctx.destination);
      o1.start(t0);
      o2.start(t0);
      o1.stop(t0 + 0.18);
      o2.stop(t0 + 0.18);
    } catch (_) {}
  }

  function enterDriveFocus() {
    setPanelHidden(true, true);
  }

  function noteCorridorOverAudio(corridor) {
    if (!corridor?.active || !corridor.over) {
      lastCorridorOverKey = "";
      return;
    }
    // Same debounce key as RadarAlert.speak("corridor-over") — no double TTS
    if (lastCorridorOverKey === "corridor-over") return;
    lastCorridorOverKey = "corridor-over";
    if (typeof I18n !== "undefined" && I18n.speak) {
      I18n.speak(t("radarSlow"), { key: "corridor-over", urgent: true });
    }
  }

  function syncStartStopUi() {
    if (!startBtn) return;
    startBtn.disabled = !!startInFlight;
    startBtn.textContent = running ? t("stop") : t("start");
    startBtn.classList.toggle("running", !!running);
    demoBtn?.classList.toggle("active", !!demoMode);
    document.body.classList.toggle("demo-mode", !!demoMode);
  }

  function applyVisualTheme(key, { silent = false } = {}) {
    let modeKey = key || visualSelect?.value || DEFAULT_VISUAL();
    if (modeKey === "aurora") modeKey = "glow";
    const prev =
      document.documentElement.getAttribute("data-visual") ||
      speedGaugeWrap?.getAttribute("data-visual") ||
      "";
    const meta = Scene.getModeMeta?.(modeKey);
    Scene.setMode(modeKey);
    const hue = Scene.getThemeHue?.() ?? 185;
    document.documentElement.style.setProperty("--theme-hue", String(hue));
    document.documentElement.style.setProperty("--theme-angle", `${hue - 185}deg`);
    document.documentElement.setAttribute("data-visual", modeKey);
    speedGaugeWrap?.setAttribute("data-visual", modeKey);
    if (meta?.gauge && GAUGE_SCREENS.includes(meta.gauge)) {
      setGaugeScreen(meta.gauge, false);
    }
    setSpeedColors(hudDisplayKmh, readMaxKmh());
    syncMapOpacityUi();
    if (!silent && themeCueReady && prev && prev !== modeKey) {
      playThemeChangeSound();
    }
  }

  function setSpeedColors(kmh, maxKmh) {
    const pct = Math.min(1, Math.max(0, kmh / maxKmh));
    const base =
      Scene.getThemeHue?.() ??
      (parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--theme-hue")) || 185);
    const hue = Math.round(base + pct * 48);
    const glow = Math.round(pct * 1000) / 1000;
    if (setSpeedColors._lastHue === hue && setSpeedColors._lastGlow === glow) return;
    setSpeedColors._lastHue = hue;
    setSpeedColors._lastGlow = glow;
    document.documentElement.style.setProperty("--speed-hue", String(hue));
    document.documentElement.style.setProperty("--speed-glow", String(glow));
    if (speedGaugeWrap) {
      speedGaugeWrap.style.setProperty("--gauge-hue", String(hue));
      speedGaugeWrap.style.setProperty("--gauge-accent", `hsl(${hue}, 90%, 58%)`);
      speedGaugeWrap.style.setProperty("--gauge-mid", `hsl(${hue + 28}, 85%, 55%)`);
      speedGaugeWrap.style.setProperty("--gauge-hot", `hsl(${hue + 55}, 90%, 58%)`);
    }
    const stops = document.querySelectorAll("#ringGrad stop");
    if (stops.length >= 3) {
      stops[0].setAttribute("stop-color", `hsl(${hue}, 90%, 58%)`);
      stops[1].setAttribute("stop-color", `hsl(${hue + 28}, 85%, 55%)`);
      stops[2].setAttribute("stop-color", `hsl(${hue + 55}, 90%, 58%)`);
    }
  }

  async function applyOrientLock(mode) {
    orientLock = mode;
    try {
      localStorage.setItem(ORIENT_KEY, mode);
    } catch (_) {}
    lockPortraitBtn?.classList.toggle("active", mode === "portrait");
    lockLandscapeBtn?.classList.toggle("active", mode === "landscape");
    if (!screen.orientation?.lock) return;
    try {
      if (mode === "none") await screen.orientation.unlock();
      else if (mode === "portrait") await screen.orientation.lock("portrait-primary");
      else if (mode === "landscape") await screen.orientation.lock("landscape-primary");
    } catch (_) {}
  }

  function loadOrientLock() {
    try {
      orientLock = localStorage.getItem(ORIENT_KEY) || "none";
    } catch (_) {
      orientLock = "none";
    }
    lockPortraitBtn?.classList.toggle("active", orientLock === "portrait");
    lockLandscapeBtn?.classList.toggle("active", orientLock === "landscape");
    if (orientLock !== "none") applyOrientLock(orientLock);
  }

  function isPremiumUser() {
    // Web ücretsiz: paneli kapatınca immersive sürüş herkese açık
    return true;
  }

  function syncDriveFocus(panelHidden) {
    // Premium + panel kapalı → yalnızca hız + tema (immersive)
    const focus = !!panelHidden && isPremiumUser();
    document.body.classList.toggle("drive-focus", focus);
  }

  function setPanelHidden(hidden, persist = true) {
    document.body.classList.toggle("panel-hidden", hidden);
    syncDriveFocus(hidden);
    const editorial = document.getElementById("siteEditorial");
    if (editorial) editorial.hidden = !!hidden;
    if (panelToggle) {
      const mobile = window.matchMedia("(max-width: 720px)").matches;
      panelToggle.textContent = mobile ? (hidden ? "⌃" : "⌄") : hidden ? "›" : "‹";
      panelToggle.setAttribute("aria-label", hidden ? t("panelShow") : t("panelHide"));
      panelToggle.setAttribute("title", hidden ? t("panelShow") : t("panelHide"));
    }
    if (persist) {
      try {
        localStorage.setItem(PANEL_KEY, hidden ? "1" : "0");
      } catch (_) {}
    }
  }

  function loadPanelState() {
    // Varsayılan: ayarlar açık kalsın — her yüklemede yeniden açılmasın
    let hidden = false;
    try {
      const stored = localStorage.getItem(PANEL_KEY);
      if (stored != null) hidden = stored === "1";
    } catch (_) {
      hidden = false;
    }
    setPanelHidden(hidden, false);
  }

  let hudDisplayKmh = 0;
  let tripAvg = {
    distM: 0,
    ms: 0,
    lastLat: null,
    lastLng: null,
    lastMs: 0,
    avg: 0,
  };
  let lastCorridorInfo = null;
  let avgIdleTimer = null;

  function haversineM(lat1, lon1, lat2, lon2) {
    const R = 6371000;
    const dLat = ((lat2 - lat1) * Math.PI) / 180;
    const dLon = ((lon2 - lon1) * Math.PI) / 180;
    const a =
      Math.sin(dLat / 2) ** 2 +
      Math.cos((lat1 * Math.PI) / 180) *
        Math.cos((lat2 * Math.PI) / 180) *
        Math.sin(dLon / 2) ** 2;
    return 2 * R * Math.asin(Math.sqrt(a));
  }

  function resetTripAvg() {
    tripAvg = {
      distM: 0,
      ms: 0,
      lastLat: null,
      lastLng: null,
      lastMs: 0,
      avg: 0,
    };
    if (typeof RadarAlert !== "undefined") RadarAlert.resetCorridor?.();
    lastCorridorInfo = null;
    renderAvgSpeedPanel(hudDisplayKmh);
  }

  function recomputeTripAvg() {
    const hours = tripAvg.ms / 3600000;
    const avg = hours > 0 ? tripAvg.distM / 1000 / hours : 0;
    // UI güvenlik sınırı: anlık GPS sıçraması ortalamayı uçurmasın
    tripAvg.avg = Math.min(220, Math.max(0, avg || 0));
  }

  /** Mesafe + süre: durunca süre artar, ortalama düşer */
  function updateTripAvg(lat, lng, kmh) {
    if (lat == null || lng == null || !Number.isFinite(lat)) return;
    const now = Date.now();
    if (tripAvg.lastLat != null && tripAvg.lastMs) {
      const d = haversineM(tripAvg.lastLat, tripAvg.lastLng, lat, lng);
      const dt = now - tripAvg.lastMs;
      // Çok kısa aralık: konum güncelle, zaman damgasını koru (dt biriksin)
      if (dt < 80) {
        tripAvg.lastLat = lat;
        tripAvg.lastLng = lng;
        return;
      }
      // Arka plan / uzun boşluk — şişirmeyi atla
      if (dt >= 8000) {
        tripAvg.lastLat = lat;
        tripAvg.lastLng = lng;
        tripAvg.lastMs = now;
        return;
      }
      // GPS sıçramasında 80ms'de büyük mesafe gelebilir; fiziksel hız filtresi uygula
      const impliedKmh = dt > 0 ? (d / dt) * 3.6 * 1000 : 0;
      const plausibleStep =
        d > 0.4 &&
        d < 120 &&
        impliedKmh <= 260 &&
        (!Number.isFinite(kmh) || kmh < 2 || Math.abs(impliedKmh - kmh) <= 55);
      const moving = kmh >= 2 && plausibleStep;
      const tripStarted = tripAvg.distM > 0 || tripAvg.ms > 0 || moving;
      if (tripStarted) {
        tripAvg.ms += dt;
        if (moving) tripAvg.distM += d;
        recomputeTripAvg();
      }
      tripAvg.lastLat = lat;
      tripAvg.lastLng = lng;
      tripAvg.lastMs = now;
      return;
    }
    tripAvg.lastLat = lat;
    tripAvg.lastLng = lng;
    tripAvg.lastMs = now;
  }

  /** Konum yoksa (OBD) hız × zaman ile ortalama — duruşta süre yine sayılır */
  function updateTripAvgFromSpeed(kmh) {
    const now = Date.now();
    if (!tripAvg.lastMs) {
      tripAvg.lastMs = now;
      return;
    }
    const dt = now - tripAvg.lastMs;
    if (dt < 80) return;
    if (dt >= 8000) {
      tripAvg.lastMs = now;
      return;
    }
    const moving = kmh >= 2;
    const tripStarted = tripAvg.distM > 0 || tripAvg.ms > 0 || moving;
    if (tripStarted) {
      tripAvg.ms += dt;
      if (moving) {
        tripAvg.distM += (kmh / 3.6) * (dt / 1000);
      }
      recomputeTripAvg();
    }
    tripAvg.lastMs = now;
  }

  /** GPS sessizken (duruş) paneli canlı tut — süre aksın */
  function tickAvgWhileIdle() {
    if (!running) return;
    const now = Date.now();
    if (tripAvg.lastMs && (tripAvg.ms > 0 || tripAvg.distM > 0)) {
      const dt = now - tripAvg.lastMs;
      if (dt >= 250 && dt < 8000 && hudDisplayKmh < 2) {
        tripAvg.ms += dt;
        tripAvg.lastMs = now;
        recomputeTripAvg();
      }
    }
    if (lastCorridorInfo?.active && typeof RadarAlert !== "undefined") {
      const snap = RadarAlert.getCorridorSnapshot?.(hudDisplayKmh);
      if (snap) {
        lastCorridorInfo = {
          ...lastCorridorInfo,
          avg: snap.avg,
          over: snap.over,
          remainM: snap.remainM,
        };
      }
    }
    renderAvgSpeedPanel(hudDisplayKmh);
  }

  function startAvgIdleTicker() {
    if (avgIdleTimer) return;
    avgIdleTimer = setInterval(tickAvgWhileIdle, 500);
  }

  function stopAvgIdleTicker() {
    if (!avgIdleTimer) return;
    clearInterval(avgIdleTimer);
    avgIdleTimer = null;
  }

  function formatDistShort(m) {
    if (m == null) return "";
    if (m >= 1000) return `${(m / 1000).toFixed(1)} km`;
    return `${Math.round(m / 10) * 10} m`;
  }

  function triggerCorridorEnterPulse() {
    if (!avgSpeedPanel) return;
    avgSpeedPanel.classList.remove("is-corridor-pulse");
    // reflow — animasyonu yeniden başlat
    void avgSpeedPanel.offsetWidth;
    avgSpeedPanel.classList.add("is-corridor-pulse");
    if (corridorPulseTimer) clearTimeout(corridorPulseTimer);
    corridorPulseTimer = setTimeout(() => {
      avgSpeedPanel.classList.remove("is-corridor-pulse");
      corridorPulseTimer = null;
    }, 3200);
  }

  function renderAvgSpeedPanel(kmh) {
    if (!avgSpeedPanel || !avgSpeedValue) return;
    const corridor = lastCorridorInfo;
    if (corridor?.active) {
      const avg = Math.round(corridor.avg || 0);
      avgSpeedValue.textContent = String(avg);
      if (avgSpeedLabel) avgSpeedLabel.textContent = t("avgCorridorLabel");
      if (avgSpeedBadge) {
        avgSpeedBadge.hidden = false;
        avgSpeedBadge.textContent = t("radarCorridor");
      }
      avgSpeedPanel.classList.add("is-corridor");
      avgSpeedPanel.classList.toggle("is-over", !!corridor.over);
      if (avgSpeedMeta) {
        avgSpeedMeta.hidden = false;
        const bits = [];
        if (corridor.label) bits.push(corridor.label);
        if (corridor.limit) bits.push(`${t("avgLimit")} ${corridor.limit}`);
        if (corridor.remainM != null) {
          bits.push(`${t("radarRemain")} ${formatDistShort(corridor.remainM)}`);
        }
        if (corridor.over) bits.push(t("radarSlow"));
        avgSpeedMeta.textContent = bits.join(" · ");
      }
      // Yeni koridora giriş — büyüt + pulse
      const cid = corridor.id || corridor.label || "corridor";
      if (corridor.entered || (cid && cid !== lastCorridorTrackId)) {
        if (cid !== lastCorridorTrackId || corridor.entered) {
          triggerCorridorEnterPulse();
        }
      }
      lastCorridorTrackId = cid;
    } else {
      lastCorridorTrackId = null;
      const avg = Math.round(tripAvg.avg || 0);
      avgSpeedValue.textContent = String(avg);
      if (avgSpeedLabel) avgSpeedLabel.textContent = t("avgSpeedLabel");
      if (avgSpeedBadge) {
        avgSpeedBadge.hidden = true;
        avgSpeedBadge.textContent = "";
      }
      avgSpeedPanel.classList.remove("is-corridor", "is-over", "is-corridor-pulse");
      if (avgSpeedMeta) {
        const km = tripAvg.distM / 1000;
        if (km >= 0.05) {
          avgSpeedMeta.hidden = false;
          avgSpeedMeta.textContent = `${km.toFixed(km >= 10 ? 1 : 2)} km`;
        } else {
          avgSpeedMeta.hidden = true;
          avgSpeedMeta.textContent = "";
        }
      }
    }
  }

  function mergeWarnQueue(radarQueue, routeQueue, primary) {
    const out = [];
    const seen = new Set();
    const push = (item) => {
      if (!item) return;
      const id = String(item.id || `${item.kind}-${item.dist}-${item.title}`);
      if (seen.has(id)) return;
      seen.add(id);
      out.push({ ...item, id });
    };
    if (primary) {
      push({
        id: primary.id || `primary-${primary.kind}-${primary.dist}`,
        kind: primary.kind || "radar",
        title: primary.title || t("hudRoadWarn"),
        dist: primary.dist || "—",
        distM: primary.distM,
        meta: primary.meta || "",
        stage: primary.stage || "far",
      });
    }
    (radarQueue || []).forEach(push);
    (routeQueue || []).forEach(push);
    return out.slice(0, 4);
  }

  function paintWarnReel(queue, stage, kind) {
    if (!warnReel || !warnReelTrack) return;
    const items = Array.isArray(queue) ? queue.filter(Boolean) : [];
    if (!items.length) {
      warnReel.hidden = true;
      warnReel.dataset.stage = "idle";
      warnReelTrack.innerHTML = "";
      warnReelKey = "";
      warnReelIndex = 0;
      hudWarnSide?.classList.remove("has-reel");
      return;
    }
    hudWarnSide?.classList.add("has-reel");
    warnReel.hidden = false;
    const st = stage || items[0].stage || "far";
    warnReel.dataset.stage = st;
    warnReel.className = "warn-reel";
    if (kind) warnReel.classList.add(`is-kind-${kind}`);

    const head = items[0];
    const key = head.id || `${head.title}|${head.dist}`;
    const changed = key !== warnReelKey;
    warnReelKey = key;

    // Makara: aktif + sıradaki gölgeler
    const slotH = 72;
    warnReelTrack.innerHTML = items
      .map((it, i) => {
        const cls =
          i === 0 ? "is-active" : i === 1 ? "is-next" : "";
        const meta = it.meta
          ? `<span class="warn-reel-meta">${escapeHtml(it.meta)}</span>`
          : "";
        return `<div class="warn-reel-item ${cls}" data-i="${i}">
          <span class="warn-reel-kicker">${escapeHtml(it.title || t("hudRoadWarn"))}</span>
          <span class="warn-reel-dist">${escapeHtml(it.dist || "—")}</span>
          ${meta}
        </div>`;
      })
      .join("");

    if (changed) {
      warnReelIndex = 0;
      warnReelTrack.classList.add("is-spinning");
      // Önce bir slot aşağıdan gelsin, sonra yerine otursun
      warnReelTrack.style.transform = `translateY(${slotH * 0.55}px)`;
      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          warnReelTrack.style.transform = `translateY(0)`;
          setTimeout(() => warnReelTrack.classList.remove("is-spinning"), 720);
        });
      });
    } else {
      warnReelTrack.style.transform = `translateY(${-warnReelIndex * slotH}px)`;
    }
  }

  function escapeHtml(s) {
    return String(s || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function paintSpeedLimitBadge(limit, overLimit) {
    if (!speedLimitBadge || !speedLimitValue) return;
    if (limit == null || !Number.isFinite(limit) || limit <= 0) {
      speedLimitBadge.hidden = true;
      speedLimitBadge.classList.remove("is-over");
      speedLimitValue.textContent = "—";
      return;
    }
    speedLimitBadge.hidden = false;
    speedLimitValue.textContent = String(Math.round(limit));
    speedLimitBadge.classList.toggle("is-over", !!overLimit);
    speedHudEl?.classList.toggle("is-over-limit", !!overLimit);
  }

  function paintCritNearList(list) {
    if (!critNear || !critNearList) return;
    const items = Array.isArray(list) ? list.slice(0, 4) : [];
    if (!items.length) {
      critNear.hidden = true;
      critNearList.innerHTML = "";
      return;
    }
    critNear.hidden = false;
    critNearList.innerHTML = items
      .map((it) => {
        const crit = it.critical || it.stage === "critical" ? " is-critical" : "";
        return `<li class="crit-near-item${crit}" data-kind="${escapeHtml(it.kind || it.type || "")}">
          <span class="crit-icon">${escapeHtml(it.icon || "")}</span>
          <span class="crit-title">${escapeHtml(it.title || it.label || "")}</span>
          <span class="crit-dist">${escapeHtml(it.dist || "")}</span>
        </li>`;
      })
      .join("");
  }

  function paintWarnBand(osm, roadWarn) {
    if (!hudWarnBand) return;
    let text = "";
    let dist = "";
    let icon = "⚠️";
    let urgent = false;
    let overspeed = false;

    if (osm?.overLimit) {
      text = `⚡ Hız Aşıldı!`;
      dist = `+${osm.overBy || 0} km/s`;
      icon = "⚡";
      urgent = true;
      overspeed = true;
    } else if (roadWarn && (roadWarn.stage === "critical" || roadWarn.over)) {
      text = roadWarn.title || t("hudRoadWarn");
      dist = roadWarn.dist || "";
      icon = "🚨";
      urgent = true;
    } else if (osm?.alert && (osm.alert.critical || osm.alert.stage === "critical" || osm.alert.stage === "near")) {
      text = osm.alert.title || t("hudRoadWarn");
      dist = osm.alert.dist || "";
      icon = "⚠️";
      urgent = osm.alert.stage === "critical";
    } else if (roadWarn) {
      text = roadWarn.title || t("hudRoadWarn");
      dist = roadWarn.dist || "";
      icon = "⚠️";
      urgent = false;
    } else if (osm?.alert) {
      text = osm.alert.title || t("hudRoadWarn");
      dist = osm.alert.dist || "";
      icon = "⚠️";
    }

    if (!text) {
      hudWarnBand.hidden = true;
      hudWarnBand.classList.remove("is-urgent", "is-overspeed");
      speedHudEl?.classList.remove("has-warn-band");
      return;
    }
    hudWarnBand.hidden = false;
    speedHudEl?.classList.add("has-warn-band");
    hudWarnBand.classList.toggle("is-urgent", urgent);
    hudWarnBand.classList.toggle("is-overspeed", overspeed);
    if (hudWarnBandIcon) hudWarnBandIcon.textContent = icon;
    if (hudWarnBandText) hudWarnBandText.textContent = text;
    if (hudWarnBandDist) hudWarnBandDist.textContent = dist;
  }

  function paintHudWarn(info, queue) {
    if (!hudWarn) return;
    if (!info) {
      if (hudWarnLabel) hudWarnLabel.textContent = t("hudRoadWarn");
      hudWarn.textContent = "—";
      if (hudWarnMeta) {
        hudWarnMeta.hidden = true;
        hudWarnMeta.textContent = "";
      }
      hudWarnSide?.classList.remove(
        "is-active",
        "is-over",
        "has-reel",
        "warn-critical",
        "warn-near",
        "warn-mid",
        "warn-far",
        "warn-radar",
        "warn-corridor",
        "warn-charge",
        "warn-weather"
      );
      paintWarnReel([], "idle", null);
      return;
    }
    if (hudWarnLabel) hudWarnLabel.textContent = info.title || t("hudRoadWarn");
    hudWarn.textContent = info.dist || info.text || "—";
    if (hudWarnMeta) {
      const meta = info.meta || "";
      hudWarnMeta.textContent = meta;
      hudWarnMeta.hidden = !meta;
    }
    const stage = info.stage || "far";
    let kind = info.kind || "radar";
    if (kind === "fixed" || kind === "warn") kind = "radar";
    if (kind === "corridor-in") kind = "corridor";
    hudWarnSide?.classList.remove(
      "warn-critical",
      "warn-near",
      "warn-mid",
      "warn-far",
      "warn-radar",
      "warn-corridor",
      "warn-charge",
      "warn-weather"
    );
    hudWarnSide?.classList.add("is-active", `warn-${stage}`, `warn-${kind}`);
    hudWarnSide?.classList.toggle("is-over", !!info.over);
    const q =
      Array.isArray(queue) && queue.length
        ? queue
        : mergeWarnQueue(null, null, info);
    paintWarnReel(q, stage, kind);
  }

  function updateHud(kmh, gearInfo, meta = {}) {
    // Sayısal hız gösterimi gaugeSmooth rAF’ta; burada yalnızca hedef + yan HUD
    setGaugeTarget(kmh);
    if (meta.lat != null && meta.lng != null) {
      MiniMap.update?.(meta.lat, meta.lng, kmh);
      updateTripAvg(meta.lat, meta.lng, kmh);
      let roadWarn = null;
      let routeInfo = null;
      let radarQueue = [];
      let routeQueue = [];
      let osm = null;
      if (typeof RadarAlert !== "undefined") {
        const radar = RadarAlert.update(meta.lat, meta.lng, meta.heading, kmh);
        lastCorridorInfo = radar?.corridor || null;
        if (radar?.alert) roadWarn = radar.alert;
        radarQueue = radar?.queue || [];
        noteCorridorOverAudio(lastCorridorInfo);
        // Radar/koridor limiti varsa OSM levhasına da yansıt
        const lim =
          radar?.alert?.limit ||
          radar?.corridor?.limit ||
          null;
        if (
          lim != null &&
          typeof OsmHazards !== "undefined" &&
          OsmHazards.setRoadMaxspeed &&
          !OsmHazards.getRoadMaxspeed?.()
        ) {
          OsmHazards.setRoadMaxspeed(lim);
        }
      }
      if (typeof OsmHazards !== "undefined") {
        osm = OsmHazards.update(meta.lat, meta.lng, meta.heading, kmh);
      }
      if (typeof RouteGuard !== "undefined") {
        routeInfo = RouteGuard.update?.(meta.lat, meta.lng, meta.heading, kmh) || null;
        routeQueue = routeInfo?.queue || [];
      }
      // Öncelik: radar/koridor > şarj > hava (uzak radar bile şarjı ezer)
      const isRadarOrCorridor = (w) => {
        if (!w) return false;
        const k = w.kind || "";
        return (
          k === "radar" ||
          k === "fixed" ||
          k === "warn" ||
          k === "corridor" ||
          k === "corridor-in"
        );
      };
      if (!isRadarOrCorridor(roadWarn) && routeInfo?.title && routeInfo?.dist) {
        const rk = routeInfo.kind || "";
        // RadarAlert yoksa RouteGuard radar/koridor’u da HUD’a taşı
        if (rk === "radar" || rk === "corridor") {
          roadWarn = {
            title: routeInfo.title,
            dist: routeInfo.dist,
            meta: routeInfo.meta || routeInfo.hazard?.label || routeInfo.hazard?.name || "",
            kind: rk,
            stage: routeInfo.stage || "far",
            over: false,
            id: routeInfo.hazard?.id,
            distM: routeInfo.distM,
          };
        } else if (
          rk === "charge" &&
          routeInfo.distM != null &&
          routeInfo.distM <= 5000
        ) {
          roadWarn = {
            title: routeInfo.title,
            dist: routeInfo.dist,
            meta: routeInfo.meta || routeInfo.hazard?.name || "",
            kind: "charge",
            stage: routeInfo.stage || "far",
            over: false,
            id: routeInfo.hazard?.id,
            distM: routeInfo.distM,
          };
        } else if (rk === "weather") {
          roadWarn = {
            title: routeInfo.title,
            dist: routeInfo.dist,
            meta: routeInfo.meta || routeInfo.hazard?.label || "",
            kind: "weather",
            stage: routeInfo.stage || "far",
            over: false,
            id: routeInfo.hazard?.id,
            distM: routeInfo.distM,
          };
        }
      }
      // OSM kritik nokta — radar yoksa HUD’a
      if (!roadWarn && osm?.alert) {
        roadWarn = osm.alert;
      } else if (
        osm?.alert &&
        roadWarn &&
        !isRadarOrCorridor(roadWarn) &&
        (osm.alert.distM ?? Infinity) < (roadWarn.distM ?? Infinity)
      ) {
        roadWarn = osm.alert;
      }
      // Hız aşımı en yüksek öncelik (HUD + şerit)
      if (osm?.overLimit) {
        roadWarn = {
          title: "⚡ Hız Aşıldı!",
          dist: `+${osm.overBy || 0} km/s`,
          meta: osm.maxspeed ? `Limit ${osm.maxspeed}` : "",
          kind: "radar",
          stage: "critical",
          over: true,
          id: "overspeed",
          distM: 0,
          limit: osm.maxspeed,
        };
      }
      const osmQueue = (osm?.list || []).map((it) => ({
        id: it.id,
        kind: it.kind || it.type || "radar",
        title: it.title || it.label,
        dist: it.dist,
        distM: it.distM,
        meta: "",
        stage: it.stage || "mid",
      }));
      const queue = mergeWarnQueue(radarQueue, [...routeQueue, ...osmQueue], roadWarn);
      paintHudWarn(roadWarn, queue);
      paintSpeedLimitBadge(osm?.maxspeed ?? null, !!osm?.overLimit);
      paintCritNearList(osm?.list || []);
      paintWarnBand(osm, roadWarn);
    } else if (running) {
      updateTripAvgFromSpeed(kmh);
      paintSpeedLimitBadge(null, false);
      paintCritNearList([]);
      paintWarnBand(null, null);
    }
    renderAvgSpeedPanel(kmh);
    const shownKmh = Math.round(kmh);
    const boost = shownKmh > 80;
    modeChip.textContent = boost
      ? t("modeBoost")
      : shownKmh > 30
        ? t("modeActive")
        : t("modeCalm");
    modeChip.classList.toggle("boost", boost);
    modeChip.title = meta.source === "obd" ? "OBD" : "GPS";
  }

  function formatGearLabel(kmh, gearInfo) {
    if ((kmh || 0) < 2) return "N";
    // EV / tek oran: vites numarası gösterme
    if (!gearInfo?.ice || (gearInfo.gears || 1) <= 1) return "—";
    return String(gearInfo.gear || "N");
  }

  function driveSessionPayload(extra = {}) {
    const voice = voiceSelect?.value || DEFAULT_VOICE();
    const vMeta = AudioEngine.getVoices().find((v) => v.key === voice);
    const gearInfo = AudioEngine.getGearInfo?.() || { gear: 0, rpm: 0.12 };
    const kmh = parseInt(speedValue?.textContent || "0", 10) || 0;
    const mix = document.getElementById("mixUnderMusic")?.checked !== false ? "blend" : "solo";
    return {
      voice: vMeta?.label || voice,
      kmh,
      gear: formatGearLabel(kmh, gearInfo),
      rpm: Math.round((gearInfo.rpm || 0) * 8000),
      source: GpsTracker.getSpeedSource?.() || "gps",
      mixMode: mix,
      ...extra,
    };
  }

  function pushLiveActivity(data, gearInfo) {
    if (!window.EtubuNative?.updateDriveSession || !running) return;
    const voice = voiceSelect?.value || DEFAULT_VOICE();
    const vMeta = AudioEngine.getVoices().find((v) => v.key === voice);
    const rpm =
      data?.source === "obd" && data.rpm != null
        ? Math.round(data.rpm)
        : Math.round((gearInfo?.rpm || 0) * 8000);
    window.EtubuNative.updateDriveSession({
      voice: vMeta?.label || voice,
      kmh: Math.round(data?.kmh || 0),
      gear: formatGearLabel(data?.kmh || 0, gearInfo),
      rpm,
      source: data?.source || "gps",
    }).catch?.(() => {});
  }

  function onSpeedUpdate(data) {
    // Sürüş yokken gösterge/sahne güncelleme — sahte hareket yok
    if (!running) return;
    let kmh = Math.max(0, Number(data.kmh) || 0);
    let audioKmh = Math.max(0, Number(data.audioKmh != null ? data.audioKmh : kmh) || 0);
    // Sadece gerçek duruşta sıfır — ses GPS’i birebir takip eder
    if (kmh < 0.25) {
      kmh = 0;
      audioKmh = 0;
    }
    // Demo dışında düşük gürültüyü göstergede tutma
    if (!demoMode && kmh < 2.2) {
      kmh = 0;
      audioKmh = 0;
    }
    const maxKmh = readMaxKmh();
    let gearInfo = running
      ? AudioEngine.setSpeed(audioKmh, {
          source: data.source || "gps",
          trend: data.trend,
        })
      : { gear: 0, rpm: 0.12 };
    updateHud(kmh, gearInfo, { ...data, kmh });
    Scene.setSpeed(audioKmh, maxKmh);
    pushLiveActivity({ ...data, kmh: Math.round(kmh) }, gearInfo);

    const justLocked = !demoMode && Paywall.checkAndMaybeBlock(data.totalKm);
    if (justLocked) {
      refreshCatalogUi();
      forceDefaultVoiceIfLocked();
    } else if (!demoMode) {
      Paywall.updateTrialPill(data.totalKm);
    }
  }

  async function startDrive() {
    if (startInFlight) return;
    if (running) stopDrive();

    startInFlight = true;
    const session = ++driveSession;
    syncStartStopUi();

    // Jest içinde hemen — await yok
    AudioEngine.kickUnlock?.();
    clearDriveMute();

    const voice =
      unlocked() || voiceSelect?.value === "silent-mode"
        ? voiceSelect.value
        : DEFAULT_VOICE();
    const visual = unlocked() ? visualSelect?.value : DEFAULT_VISUAL();
    applyVisualTheme(visual);
    const vMeta = AudioEngine.getVoices().find((v) => v.key === voice);

    try {
      AudioEngine.kickUnlock?.();
      clearDriveMute();
      if (session !== driveSession) return;
      const started = await AudioEngine.start(voice);
      if (session !== driveSession) {
        AudioEngine.stop();
        return;
      }
      AudioEngine.setMaxKmh(readMaxKmh());
      AudioEngine.setVolume(Math.max(0.35, readVolume()));
      // Müzik yokken / çalmıyorken ducking uygulama
      if (!AudioEngine.isMusicPlaying?.()) {
        AudioEngine.setMixUnderMusic?.(false, 1);
      } else {
        MusicHub.applyMix?.();
      }
      const ok = await AudioEngine.ensureAudible?.(voice);
      if (!ok && voice !== "silent-mode") {
        console.warn("[etubu-audio] startDrive: context not running", started);
      }
      if (session !== driveSession) {
        AudioEngine.stop();
        return;
      }
      AudioEngine.setSpeed(0, { source: "gps" });
    } catch (err) {
      console.warn("Audio start failed", err);
      alert(t("audioStartFail"));
      running = false;
      return;
    } finally {
      startInFlight = false;
      syncStartStopUi();
    }

    if (session !== driveSession) return;

    resetGaugesIdle();
    tapCount = 0;
    unlockFocus();

    running = true;
    demoMode = false;
    syncStartStopUi();
    enterDriveFocus();
    startAvgIdleTicker();

    GpsTracker.setSensitivity(readSensitivity());
    const gpsOk = GpsTracker.start({
      onUpdate: onSpeedUpdate,
      onError: (msg) => {
        if (session !== driveSession || !running) return;
        const el = $("gpsState");
        if (el) el.textContent = msg;
        alert(t("gpsNeeded") + msg);
      },
    });
    if (gpsOk === false) {
      stopDrive();
      return;
    }

    try {
      if ("wakeLock" in navigator) wakeLock = await navigator.wakeLock.request("screen");
    } catch (_) {}

    if (session !== driveSession || !running) {
      if (wakeLock) {
        wakeLock.release().catch(() => {});
        wakeLock = null;
      }
      return;
    }

    window.EtubuNative?.startDriveSession?.(
      driveSessionPayload({
        voice: vMeta?.label || voice,
        kmh: 0,
        gear: "N",
        rpm: 0,
      })
    )?.catch?.(() => {});
  }

  function stopDrive() {
    driveSession += 1;
    startInFlight = false;
    running = false;
    stopAvgIdleTicker();

    if (previewStop) {
      try {
        previewStop();
      } catch (_) {}
      previewStop = null;
    }
    GpsTracker.stop();
    AudioEngine.stop();
    MiniMap.clear?.();
    if (typeof RadarAlert !== "undefined") RadarAlert.clear();
    if (typeof OsmHazards !== "undefined") OsmHazards.clear?.();
    paintHudWarn(null);
    paintSpeedLimitBadge(null, false);
    paintCritNearList([]);
    paintWarnBand(null, null);
    resetTripAvg();

    if (wakeLock) {
      wakeLock.release().catch(() => {});
      wakeLock = null;
    }
    window.EtubuNative?.endDriveSession?.()?.catch?.(() => {});
    tapCount = 0;
    unlockFocus();

    if (demoMode) {
      demoMode = false;
      refreshCatalogUi();
    }
    syncStartStopUi();
    resetGaugesIdle();
    if (modeChip) {
      modeChip.textContent = t("modeCalm");
      modeChip.classList.remove("boost");
    }
    renderAvgSpeedPanel?.(0);
  }

  async function startDemoMode() {
    // Jest token — herhangi bir await’den ÖNCE
    AudioEngine.kickUnlock?.();

    if (startInFlight) return;
    if (demoMode && running) {
      stopDrive();
      return;
    }
    if (running) stopDrive();

    startInFlight = true;
    const session = ++driveSession;
    demoMode = true;
    syncStartStopUi();
    refreshCatalogUi();

    AudioEngine.kickUnlock?.();
    clearDriveMute();

    // Deneme = duyulabilir ses; sessiz profili yok say
    let voice = voiceSelect?.value || DEFAULT_VOICE();
    if (!voice || voice === "silent-mode") {
      voice = DEFAULT_VOICE();
      if (voiceSelect) voiceSelect.value = voice;
    }
    const visual = visualSelect?.value || DEFAULT_VISUAL();
    applyVisualTheme(visual);

    try {
      AudioEngine.kickUnlock?.();
      clearDriveMute();
      if (session !== driveSession) return;
      const started = await AudioEngine.start(voice);
      if (session !== driveSession) {
        AudioEngine.stop();
        return;
      }
      AudioEngine.setMaxKmh(readMaxKmh());
      AudioEngine.setVolume(Math.max(0.55, readVolume()));
      // Demo: müzik yoksa / çalmıyorsa tam EV
      if (!AudioEngine.isMusicPlaying?.()) {
        AudioEngine.setMixUnderMusic?.(false, 1);
      } else {
        MusicHub.applyMix?.();
      }
      const ok = await AudioEngine.ensureAudible?.(voice);
      if (!ok) {
        console.warn("[etubu-audio] demo: context not running", started, voice);
      }
      if (session !== driveSession) {
        AudioEngine.stop();
        return;
      }
      // İlk 1 sn içinde net duyulsun — sim tick beklemeden hız ver
      AudioEngine.snapSpeed?.(62) || AudioEngine.setSpeed(62, { source: "gps" });
    } catch (err) {
      console.warn("Demo audio start failed", err);
      alert(t("audioStartFail"));
      demoMode = false;
      running = false;
      return;
    } finally {
      startInFlight = false;
      syncStartStopUi();
    }

    if (session !== driveSession) return;

    resetGaugesIdle();
    running = true;
    syncStartStopUi();
    enterDriveFocus();
    startAvgIdleTicker();

    previewStop = GpsTracker.simulateForPreview({ onUpdate: onSpeedUpdate });
    showGestureToast?.(t("demoTourHint"));
  }

  function unlockFocus() {
    focusLocked = false;
    if (focusUnlockTimer) {
      clearTimeout(focusUnlockTimer);
      focusUnlockTimer = null;
    }
    if (focusLockEl) {
      focusLockEl.hidden = true;
      const bar = focusLockEl.querySelector(".focus-lock-bar > i");
      if (bar) {
        bar.style.animation = "none";
        void bar.offsetWidth;
        bar.style.animation = "";
      }
    }
  }

  function triggerFocusLock() {
    if (focusLocked || !running || demoMode) return;
    const kmh = hudDisplayKmh || 0;
    if (kmh < 8) return; // dururken / parkta uyarma
    focusLocked = true;
    tapCount = 0;
    if (focusLockEl) {
      focusLockEl.hidden = false;
      const bar = focusLockEl.querySelector(".focus-lock-bar > i");
      if (bar) {
        bar.style.animation = "none";
        void bar.offsetWidth;
        bar.style.animation = "";
      }
    }
    focusUnlockTimer = setTimeout(() => unlockFocus(), 3000);
  }

  function onDriveTap(e) {
    if (!running || demoMode || focusLocked) return;
    // Panel / seçiciler / butonlar sayılmaz — sadece sürüş yüzeyi
    const target = e.target;
    if (!(target instanceof Element)) return;
      if (target.closest("#controlDock, #panelToggle, #routeBriefTop, #routeBriefPeek, #routeFormPeek, .picker-sheet, .paywall, button, select, input, a, label, .gauge-dots, .avg-speed-panel, .route-guard")) {
      return;
    }
    tapCount += 1;
    if (tapCount >= 10) triggerFocusLock();
  }

  function refreshAfterLang() {
    if (typeof I18n !== "undefined") I18n.applyDom();
    refreshCatalogUi();
    Picker.refreshAll?.();
    if (!running) startBtn.textContent = t("start");
    else startBtn.textContent = t("stop");
    syncStartStopUi?.();
    syncMaxSpeedUi();
    syncVolumeUi();
    syncSensitivityUi();
    syncMapOpacityUi?.();
    MusicHub.refreshUi?.();
    Paywall.updateTrialPill(GpsTracker.loadTotalKm());
    Paywall.refreshAdFreeUi();
    Identity.refreshAccountUi?.();
    CarBrowser.refreshTeslaHint?.();
    RouteGuard.refreshLocale?.();
    ObdLink.refreshLocale?.();
    if (panelToggle) {
      const hidden = document.body.classList.contains("panel-hidden");
      panelToggle.setAttribute("aria-label", hidden ? t("panelShow") : t("panelHide"));
    }
    if (!Paywall.isAdFree() && !CarBrowser.isEphemeral?.()) {
      const dock = $("premiumDock");
      if (dock) dock.hidden = false;
    }
    if (running) {
      updateHud(
        parseFloat(speedValue?.textContent) || 0,
        AudioEngine.getGearInfo?.() || { gear: 0, rpm: 0.12 }
      );
    } else if (modeChip) {
      modeChip.textContent = t("modeCalm");
      modeChip.classList.remove("boost");
    }
    loadPanelState();
  }

  /* —— Hız kartı kaydırma: ↑↓ tema, ←→ ses; kadran dokunuşu: gösterge; 3 sn basılı: sessiz —— */
  const speedHud = $("speedHud") || document.querySelector(".speed-hud");
  const gestureToast = $("gestureToast");
  const SWIPE_MIN = 28;
  const HOLD_MS = 3000;
  const HOLD_SLOP = 24;
  const HUD_IGNORE_SEL = ".gauge-dots, .avg-speed-panel, button, a, input, select, label";
  let hudGesture = null;
  let hudGestureSkipClick = false;
  let holdState = null;
  let holdTimer = null;
  let toastHideTimer = null;
  /** Tesla/eski Chromium: Pointer Events eksik veya cancel; touch yolunu tercih et */
  let hudTouchActive = false;

  speedGaugeWrap?.addEventListener("click", (e) => {
    if (e.target.closest(".gauge-dots")) return;
    if (hudGestureSkipClick) {
      hudGestureSkipClick = false;
      return;
    }
    cycleGaugeScreen();
  });
  speedGaugeWrap?.addEventListener("keydown", (e) => {
    if (e.key === "Enter" || e.key === " ") {
      e.preventDefault();
      cycleGaugeScreen();
    }
  });
  gaugeDots?.addEventListener("click", (e) => {
    const btn = e.target.closest("[data-gauge-goto]");
    if (!btn) return;
    e.stopPropagation();
    setGaugeScreen(btn.dataset.gaugeGoto);
  });

  const UI_CHROME_SEL =
    "#controlDock, #panelToggle, #routeBriefTop, #routeBriefPeek, #routeFormPeek, .picker-sheet, .paywall, button, select, input, a, label, .gauge-dots, .avg-speed-panel, .route-guard, #focusLock, #audioUnlockOverlay";

  function isUiChrome(el) {
    return el instanceof Element && !!el.closest(UI_CHROME_SEL);
  }

  function showGestureToast(msg) {
    if (!gestureToast || !msg) return;
    gestureToast.hidden = false;
    gestureToast.textContent = msg;
    gestureToast.classList.add("is-visible");
    if (toastHideTimer) clearTimeout(toastHideTimer);
    toastHideTimer = setTimeout(() => {
      gestureToast.classList.remove("is-visible");
      toastHideTimer = setTimeout(() => {
        gestureToast.hidden = true;
      }, 220);
    }, 1600);
  }

  function selectCycleOptions(select) {
    if (!select) return [];
    return [...select.options].filter((o) => o.value);
  }

  function cycleSelectOption(select, dir, { skipValues } = {}) {
    const skip = skipValues instanceof Set ? skipValues : null;
    const opts = selectCycleOptions(select).filter((o) => !skip || !skip.has(o.value));
    if (!opts.length) return null;
    let i = opts.findIndex((o) => o.value === select.value);
    if (i < 0) i = 0;
    const next = opts[(i + dir + opts.length * 10) % opts.length];
    if (!next) return null;
    if (next.value === select.value) return next;
    select.value = next.value;
    select.dispatchEvent(new Event("change", { bubbles: true }));
    Picker.refreshAll?.();
    return next;
  }

  function cycleThemeBySwipe(dir) {
    const opts = selectCycleOptions(visualSelect);
    if (!opts.length || (!unlocked() && opts.length <= 1)) {
      showGestureToast(t("catalogLocked"));
      return;
    }
    const opt = cycleSelectOption(visualSelect, dir);
    if (!opt) {
      showGestureToast(t("catalogLocked"));
      return;
    }
    const name = opt.textContent?.trim() || opt.value;
    showGestureToast(t("gestureTheme", { name }));
  }

  function cycleVoiceBySwipe(dir) {
    // Sessiz moda kaydırma ile düşülmesin — menüden seçilir
    const opts = selectCycleOptions(voiceSelect).filter((o) => o.value !== "silent-mode");
    if (!opts.length || (!unlocked() && opts.length <= 1)) {
      showGestureToast(t("catalogLocked"));
      return;
    }
    const opt = cycleSelectOption(voiceSelect, dir, {
      skipValues: new Set(["silent-mode"]),
    });
    if (!opt) {
      showGestureToast(t("catalogLocked"));
      return;
    }
    const name = opt.textContent?.trim() || opt.value;
    showGestureToast(t("gestureVoice", { name }));
  }

  /** Başlat = ses açık; mute tercihi sürüş başında temizlenir (URL dahil) */
  function clearDriveMute() {
    AudioEngine.setMuted?.(false);
    document.body.classList.remove("audio-muted");
    try {
      if (typeof CarBrowser !== "undefined" && CarBrowser.setPref) {
        CarBrowser.setPref("mute", "0", { forceUrl: true });
        CarBrowser.refreshTeslaHint?.();
        return;
      }
    } catch (_) {}
    try {
      localStorage.setItem("etubu_mute", "0");
    } catch (_) {}
    prefSet("mute", "0");
  }

  function toggleDriveMute() {
    const next = !(AudioEngine.isMuted?.() ?? false);
    AudioEngine.setMuted(next);
    document.body.classList.toggle("audio-muted", next);
    prefSet("mute", next ? "1" : "0");
    showGestureToast(t(next ? "gestureMuted" : "gestureUnmuted"));
  }

  function clearHoldWatch() {
    if (holdTimer) {
      clearTimeout(holdTimer);
      holdTimer = null;
    }
    holdState = null;
  }

  function startHoldWatch(id, x, y) {
    if (focusLocked) return;
    clearHoldWatch();
    holdState = { id, x, y };
    holdTimer = setTimeout(() => {
      holdTimer = null;
      holdState = null;
      toggleDriveMute();
    }, HOLD_MS);
  }

  function moveHoldWatch(id, x, y) {
    if (!holdState || holdState.id !== id) return;
    if (Math.hypot(x - holdState.x, y - holdState.y) > HOLD_SLOP) clearHoldWatch();
  }

  function beginHudGesture(target, id, x, y) {
    if (!(target instanceof Element)) return false;
    if (target.closest(HUD_IGNORE_SEL)) return false;
    hudGesture = {
      id,
      x,
      y,
      lastX: x,
      lastY: y,
      onGauge: !!target.closest("#speedGaugeWrap"),
    };
    return true;
  }

  function updateHudGesture(id, x, y) {
    if (!hudGesture || hudGesture.id !== id) return;
    hudGesture.lastX = x;
    hudGesture.lastY = y;
    moveHoldWatch(id, x, y);
  }

  function endHudGesture(id, x, y, target) {
    if (!hudGesture || hudGesture.id !== id) return;
    const startX = hudGesture.x;
    const startY = hudGesture.y;
    const endX = x != null ? x : hudGesture.lastX;
    const endY = y != null ? y : hudGesture.lastY;
    const onGauge = hudGesture.onGauge;
    const ptrId = hudGesture.id;
    hudGesture = null;
    try {
      if (typeof ptrId === "number" && speedHud?.hasPointerCapture?.(ptrId)) {
        speedHud.releasePointerCapture(ptrId);
      }
    } catch (_) {}

    const dx = endX - startX;
    const dy = endY - startY;
    const adx = Math.abs(dx);
    const ady = Math.abs(dy);

    // Büyük eksen kazanır (ölü bölge yok); eşik yalnızca hareket büyüklüğü
    if (adx >= SWIPE_MIN || ady >= SWIPE_MIN) {
      clearHoldWatch();
      hudGestureSkipClick = true;
      if (ady > adx) {
        cycleThemeBySwipe(dy < 0 ? 1 : -1);
      } else {
        cycleVoiceBySwipe(dx < 0 ? 1 : -1);
      }
      return;
    }

    if (onGauge && !(target instanceof Element && target.closest(".gauge-dots"))) {
      hudGestureSkipClick = true;
      cycleGaugeScreen();
    }
  }

  function onHoldPointerDown(e) {
    if (hudTouchActive) return;
    if (focusLocked) return;
    if (!(e.target instanceof Element) || isUiChrome(e.target)) return;
    startHoldWatch(e.pointerId, e.clientX, e.clientY);
  }

  function onHoldPointerMove(e) {
    if (hudTouchActive) return;
    moveHoldWatch(e.pointerId, e.clientX, e.clientY);
  }

  function onHudPointerDown(e) {
    if (hudTouchActive) return;
    if (!beginHudGesture(e.target, e.pointerId, e.clientX, e.clientY)) return;
    try {
      speedHud.setPointerCapture?.(e.pointerId);
    } catch (_) {}
  }

  function onHudPointerMove(e) {
    if (hudTouchActive) return;
    updateHudGesture(e.pointerId, e.clientX, e.clientY);
  }

  function onHudPointerEnd(e) {
    if (hudTouchActive) return;
    if (!hudGesture || e.pointerId !== hudGesture.id) return;
    // cancel / lostcapture: son tracked nokta (Tesla scroll iptali sık)
    const useEventXY = e.type === "pointerup";
    endHudGesture(
      e.pointerId,
      useEventXY ? e.clientX : hudGesture.lastX,
      useEventXY ? e.clientY : hudGesture.lastY,
      e.target
    );
  }

  function onHudTouchStart(e) {
    if (!e.changedTouches?.length) return;
    const touch = e.changedTouches[0];
    const target = document.elementFromPoint(touch.clientX, touch.clientY) || e.target;
    if (!beginHudGesture(target, `t${touch.identifier}`, touch.clientX, touch.clientY)) return;
    hudTouchActive = true;
    if (!focusLocked && target instanceof Element && !isUiChrome(target)) {
      startHoldWatch(`t${touch.identifier}`, touch.clientX, touch.clientY);
    }
    // Sayfa kaydırmasını / pointercancel’ı engelle (Tesla)
    if (e.cancelable) e.preventDefault();
  }

  function onHudTouchMove(e) {
    if (!hudTouchActive || !hudGesture || !e.touches?.length) return;
    const touch = [...e.touches].find((t) => `t${t.identifier}` === hudGesture.id) || e.touches[0];
    updateHudGesture(hudGesture.id, touch.clientX, touch.clientY);
    if (e.cancelable) e.preventDefault();
  }

  function onHudTouchEnd(e) {
    if (!hudTouchActive || !hudGesture || !e.changedTouches?.length) return;
    const touch =
      [...e.changedTouches].find((t) => `t${t.identifier}` === hudGesture.id) || e.changedTouches[0];
    const id = `t${touch.identifier}`;
    if (id !== hudGesture.id) return;
    const target = document.elementFromPoint(touch.clientX, touch.clientY) || e.target;
    endHudGesture(id, touch.clientX, touch.clientY, target);
    clearHoldWatch();
    hudTouchActive = false;
    if (e.cancelable) e.preventDefault();
  }

  // Pointer + Touch (Tesla Qt/Chromium Pointer Events güvenilmez)
  speedHud?.addEventListener("pointerdown", onHudPointerDown, { passive: true });
  speedHud?.addEventListener("pointermove", onHudPointerMove, { passive: true });
  speedHud?.addEventListener("pointerup", onHudPointerEnd, { passive: true });
  speedHud?.addEventListener("pointercancel", onHudPointerEnd, { passive: true });
  speedHud?.addEventListener("lostpointercapture", onHudPointerEnd, { passive: true });
  document.addEventListener(
    "pointerup",
    (e) => {
      if (!hudTouchActive && hudGesture && e.pointerId === hudGesture.id) onHudPointerEnd(e);
    },
    { capture: true, passive: true }
  );
  document.addEventListener(
    "pointercancel",
    (e) => {
      if (!hudTouchActive && hudGesture && e.pointerId === hudGesture.id) onHudPointerEnd(e);
    },
    { capture: true, passive: true }
  );

  speedHud?.addEventListener("touchstart", onHudTouchStart, { passive: false });
  speedHud?.addEventListener("touchmove", onHudTouchMove, { passive: false });
  speedHud?.addEventListener("touchend", onHudTouchEnd, { passive: false });
  speedHud?.addEventListener("touchcancel", onHudTouchEnd, { passive: false });

  document.addEventListener("pointerdown", onHoldPointerDown, { capture: true, passive: true });
  document.addEventListener("pointermove", onHoldPointerMove, { capture: true, passive: true });
  document.addEventListener(
    "pointerup",
    () => {
      if (!hudTouchActive) clearHoldWatch();
    },
    { capture: true, passive: true }
  );
  document.addEventListener(
    "pointercancel",
    () => {
      if (!hudTouchActive) clearHoldWatch();
    },
    { capture: true, passive: true }
  );

  avgSpeedReset?.addEventListener("click", (e) => {
    e.stopPropagation();
    resetTripAvg();
  });

  startBtn?.addEventListener("pointerdown", () => {
    AudioEngine.kickUnlock?.();
    RadarAlert.primeAudio?.();
  }, { passive: true });

  startBtn?.addEventListener("click", () => {
    AudioEngine.kickUnlock?.();
    if (startInFlight) return;
    if (running) stopDrive();
    else startDrive().catch((err) => console.error("Start failed", err));
  });

  demoBtn?.addEventListener("pointerdown", () => {
    AudioEngine.kickUnlock?.();
    RadarAlert.primeAudio?.();
  }, { passive: true });

  demoBtn?.addEventListener("click", () => {
    AudioEngine.kickUnlock?.();
    startDemoMode().catch((err) => console.error("Demo start failed", err));
  });

  document.addEventListener("pointerdown", onDriveTap, { capture: true, passive: true });
  focusLockEl?.addEventListener(
    "pointerdown",
    (e) => {
      e.preventDefault();
      e.stopPropagation();
    },
    { capture: true }
  );

  previewBtn?.addEventListener("click", async () => {
    // Kısa önizleme yok — kendi kendine hareket yalnızca Deneme Sürüşü’nde
    startDemoMode().catch((err) => console.error("Demo start failed", err));
  });

  lockPortraitBtn?.addEventListener("click", () => {
    applyOrientLock(orientLock === "portrait" ? "none" : "portrait");
  });

  lockLandscapeBtn?.addEventListener("click", () => {
    applyOrientLock(orientLock === "landscape" ? "none" : "landscape");
  });

  panelToggle?.addEventListener("click", () => {
    setPanelHidden(!document.body.classList.contains("panel-hidden"));
  });

  volumeSlider?.addEventListener("input", () => {
    syncVolumeUi();
    AudioEngine.setVolume(readVolume());
    MusicHub.applyMix?.();
    prefSet("volume", String(clampPct(volumeSlider.value)));
  });

  // EV ses gücü yüzdesi — müziğin altında aktif
  const mixIntensitySlider = $("mixIntensitySlider");
  const syncMixPct = () => MusicHub.onIntensityInput?.(mixIntensitySlider);
  mixIntensitySlider?.addEventListener("input", syncMixPct);
  mixIntensitySlider?.addEventListener("change", syncMixPct);

  maxSpeedSlider?.addEventListener("input", () => {
    syncMaxSpeedUi();
    const max = readMaxKmh();
    AudioEngine.setMaxKmh(max);
    updateAnalogScale();
    setRing(hudDisplayKmh, max);
  });
  sensitivitySlider?.addEventListener("input", () => {
    syncSensitivityUi();
    GpsTracker.setSensitivity(readSensitivity());
    prefSet("sensitivity", String(clampPct(sensitivitySlider.value)));
  });
  mapOpacitySlider?.addEventListener("input", () => {
    saveMapOpacityPct(mapOpacitySlider.value);
    syncMapOpacityUi();
  });

  voiceSelect?.addEventListener("change", () => {
    if (!unlocked() && voiceSelect.value !== "silent-mode") {
      voiceSelect.value = DEFAULT_VOICE();
      return;
    }
    const v = AudioEngine.getVoices().find((x) => x.key === voiceSelect.value);
    void v;
    prefSet("voice", voiceSelect.value);
    if (running) {
      AudioEngine.start(voiceSelect.value).then(() => {
        AudioEngine.setMaxKmh(readMaxKmh());
        AudioEngine.setVolume(readVolume());
        MusicHub.applyMix?.();
      });
    }
  });

  visualSelect?.addEventListener("change", () => {
    if (!unlocked()) {
      visualSelect.value = DEFAULT_VISUAL();
      applyVisualTheme(DEFAULT_VISUAL());
      return;
    }
    prefSet("visual", visualSelect.value);
    applyVisualTheme(visualSelect.value);
  });

  /** URL → cookie → localStorage (CarBrowser.getPref) */
  function loadUserPrefs() {
    // Volume
    const volRaw = prefGet("volume");
    if (volRaw != null && volumeSlider) {
      const pct = clampPct(volRaw);
      if (Number.isFinite(pct)) volumeSlider.value = String(pct);
    } else {
      ensureTeslaVolumeDefault();
    }
    syncVolumeUi();

    // Sensitivity — varsayılan %20
    const sensRaw = prefGet("sensitivity");
    if (sensRaw != null && sensitivitySlider) {
      sensitivitySlider.value = String(clampPct(sensRaw));
    } else if (sensitivitySlider) {
      const htmlVal = parseFloat(sensitivitySlider.value);
      if (!Number.isFinite(htmlVal) || htmlVal === 46) {
        sensitivitySlider.value = "20";
      }
    }
    syncSensitivityUi();
    try {
      GpsTracker.setSensitivity?.(readSensitivity());
    } catch (_) {}

    // Voice
    const voiceRaw = prefGet("voice");
    if (voiceRaw && voiceSelect) {
      const valid = new Set([...voiceSelect.options].map((o) => o.value));
      if (valid.has(voiceRaw)) {
        if (unlocked() || voiceRaw === "silent-mode" || voiceRaw === DEFAULT_VOICE()) {
          voiceSelect.value = voiceRaw;
        }
      }
    }

    // Visual theme
    const visualRaw = prefGet("visual");
    if (visualRaw && visualSelect) {
      const validVis = new Set([...visualSelect.options].map((o) => o.value));
      const key = visualRaw === "aurora" ? "glow" : visualRaw;
      if (validVis.has(key) && (unlocked() || key === DEFAULT_VISUAL())) {
        visualSelect.value = key;
        applyVisualTheme(key);
      }
    }

    // Mute
    const muteRaw = prefGet("mute");
    if (muteRaw === "1") {
      AudioEngine.setMuted?.(true);
      document.body.classList.add("audio-muted");
    }

    // Gauge — loadGaugeScreen ayrıca çağrılır; burada URL/cookie üstün gelsin
    const gaugeRaw = prefGet("gauge");
    if (gaugeRaw && GAUGE_SCREENS.includes(gaugeRaw)) {
      setGaugeScreen(gaugeRaw, false);
    }

    // Tesla: cookie/LS’ten gelen ayarları URL’e yaz — yer imi tam olsun
    if (typeof CarBrowser !== "undefined" && CarBrowser.isEphemeral?.()) {
      if (voiceSelect?.value) CarBrowser.setPref("voice", voiceSelect.value);
      if (visualSelect?.value) CarBrowser.setPref("visual", visualSelect.value);
      if (volumeSlider) CarBrowser.setPref("volume", String(clampPct(volumeSlider.value)));
      if (sensitivitySlider) {
        CarBrowser.setPref("sensitivity", String(clampPct(sensitivitySlider.value)));
      }
      CarBrowser.setPref("gauge", gaugeScreen);
      if (AudioEngine.isMuted?.()) CarBrowser.setPref("mute", "1");
      if (typeof I18n !== "undefined" && I18n.lang) CarBrowser.setPref("lang", I18n.lang);
    }

    CarBrowser.refreshTeslaHint?.();
  }

  function boot() {
    const step = (name, fn) => {
      try {
        fn();
      } catch (err) {
        console.error("ETUBU boot step failed:", name, err);
      }
    };

    step("scene", () => Scene.init($("sceneCanvas")));
    step("car", () => CarBrowser.init());
    step("identity", () => Identity.init());
    step("obd", () => ObdLink.init());
    step("paywall", () =>
      Paywall.init({
        onUnlocked: () => {
          refreshCatalogUi();
          CarBrowser.refreshTeslaHint?.();
        },
        onAdFree: () => Ads.hideAll(),
        onAccessChange: () => {
          refreshCatalogUi();
          Identity.refreshAccountUi?.();
          CarBrowser.refreshTeslaHint?.();
        },
      })
    );
    step("i18n", () => {
      if (typeof I18n === "undefined") return;
      I18n.init(() => {
        Paywall.updateTrialPill?.(GpsTracker.loadTotalKm());
        Paywall.refreshAdFreeUi?.();
      });
      I18n.fillLangSelect?.();
      $("langSelect")?.addEventListener("change", () => setTimeout(refreshAfterLang, 0));
    });
    step("panel", () => {
      if (CarBrowser.isTesla?.() || CarBrowser.isEphemeral?.()) {
        setPanelHidden(true, false);
        document.body.classList.add("ads-hidden", "drive-focus");
        CarBrowser.forceCompactChrome?.();
        CarBrowser.syncViewportHeight?.();
      } else {
        loadPanelState();
      }
    });
    step("events", () => {
      document.addEventListener("etubu:trial-reset", () => {
        refreshCatalogUi();
        Identity.refreshAccountUi?.();
      });
      document.addEventListener("etubu:access-change", () => refreshCatalogUi());
      document.addEventListener("visibilitychange", () => {
        if (!running) return;
        AudioEngine.ensureCtx?.();
        if (document.visibilityState === "visible") {
          window.EtubuNative?.setAudioMixMode?.(
            document.getElementById("mixUnderMusic")?.checked !== false ? "blend" : "solo"
          );
        }
      });
      window.addEventListener("pageshow", () => {
        if (running) AudioEngine.ensureCtx?.();
      });
    });
    step("catalog", () => refreshCatalogUi());
    step("ads", () => Ads.init());
    step("music", () => MusicHub.init());
    step("orient", () => loadOrientLock());
    step("hud", () => {
      MiniMap.init?.("hudMap");
      if (typeof RadarAlert !== "undefined") RadarAlert.init("radarAlert");
      if (typeof RouteGuard !== "undefined") RouteGuard.init?.();
      loadGaugeScreen();
      initEqBars();
      paintEqBars(0);
      // Volume/sensitivity: prefs adımı tam yüklemeden önce kaba sync
      ensureTeslaVolumeDefault();
      syncVolumeUi();
      syncMaxSpeedUi();
      syncSensitivityUi();
      if (mapOpacitySlider) mapOpacitySlider.value = String(loadMapOpacityPct());
      syncMapOpacityUi();
      updateAnalogScale();
      setRing(0, readMaxKmh());
      updateHud(0, { gear: 0, rpm: 0 });
    });
    step("uiFlags", () => {
      const dock = $("premiumDock");
      if (dock) dock.hidden = true;
      if (inviteDock) inviteDock.hidden = true;
    });
    step("langUi", () => {
      refreshAfterLang();
      I18n.fillLangSelect?.();
      CarBrowser.refreshTeslaHint?.();
    });
    step("picker", () => {
      if (typeof Picker === "undefined") {
        console.error("Picker missing — script order?");
        return;
      }
      Picker.init(["#voiceSelect", "#visualSelect", "#langSelect"]);
      I18n.fillLangSelect?.();
      Picker.refreshAll?.();
    });
    step("prefs", () => loadUserPrefs());
    step("paymentQuery", () => {
      const params = new URLSearchParams(location.search);
      if (params.get("payment") === "error") {
        const st = $("paywallStatus");
        if (st) st.textContent = t("paymentFail");
      }
    });
    // After prefs/catalog settle — theme swipe/select may play cue
    themeCueReady = true;
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
