/**
 * Araç / Bluetooth müziğinin altında EV sesi.
 * Kaydırıcı 0–100 (yüzde); AudioEngine’e 0–1 olarak gider.
 */
const MusicHub = (() => {
  const STORAGE_UNDER = "etubu_mix_under";
  const STORAGE_INTENSITY = "etubu_mix_intensity";

  function loadUnder() {
    try {
      const v = localStorage.getItem(STORAGE_UNDER);
      // Varsayılan: kapalı — müzik yokken EV’yi duck etme
      if (v === null) return false;
      return v === "1";
    } catch (_) {
      return false;
    }
  }

  function saveUnder(on) {
    try {
      localStorage.setItem(STORAGE_UNDER, on ? "1" : "0");
    } catch (_) {}
  }

  /** 0–1 arası oran */
  function loadIntensity() {
    try {
      const v = parseFloat(localStorage.getItem(STORAGE_INTENSITY));
      return Number.isFinite(v) ? Math.min(1, Math.max(0, v)) : 0.55;
    } catch (_) {
      return 0.55;
    }
  }

  function saveIntensity(ratio) {
    try {
      localStorage.setItem(STORAGE_INTENSITY, String(ratio));
    } catch (_) {}
  }

  function sliderEl() {
    return document.getElementById("mixIntensitySlider");
  }

  function labelEl() {
    return document.getElementById("mixIntensityLabel");
  }

  function fieldEl() {
    return document.getElementById("mixIntensityField");
  }

  /** Kaydırıcı değeri → yüzde (0–100) */
  function sliderToPct(raw) {
    const n = parseFloat(raw);
    if (!Number.isFinite(n)) return 40;
    if (n > 0 && n <= 1) return Math.round(n * 100);
    return Math.round(Math.min(100, Math.max(0, n)));
  }

  function pctToRatio(pct) {
    return Math.min(1, Math.max(0, pct / 100));
  }

  function setLabelPct(pct) {
    const el = labelEl();
    if (!el) return;
    el.textContent = `${pct}%`;
    el.value = pct;
  }

  function readPctFromSlider() {
    const s = sliderEl();
    return s ? sliderToPct(s.value) : Math.round(loadIntensity() * 100);
  }

  function syncFieldEnabled(under) {
    const field = fieldEl();
    const slider = sliderEl();
    if (field) field.classList.toggle("field--disabled", !under);
    if (slider) {
      slider.disabled = false; // her zaman aktif — güç her zaman ayarlanabilsin
      slider.setAttribute("aria-disabled", under ? "false" : "false");
    }
  }

  function applyMix() {
    const toggle = document.getElementById("mixUnderMusic");
    const under = toggle ? !!toggle.checked : loadUnder();
    const pct = readPctFromSlider();
    const ratio = pctToRatio(pct);
    setLabelPct(pct);
    syncFieldEnabled(under);
    try {
      if (typeof AudioEngine !== "undefined") {
        // Müzik çalmıyorsa AudioEngine tam EV tutar; under yalnızca çalarken duck eder
        AudioEngine.setMixUnderMusic?.(under, ratio);
      }
    } catch (_) {}
  }

  /** Kaydırıcı hareketi — app.js ve inline de çağırabilir */
  function onIntensityInput(source) {
    const s = source || sliderEl();
    if (!s) return;
    const pct = sliderToPct(s.value);
    if (String(s.value) !== String(pct)) s.value = String(pct);
    saveIntensity(pctToRatio(pct));
    setLabelPct(pct);
    applyMix();
  }

  function bind() {
    const toggle = document.getElementById("mixUnderMusic");
    const slider = sliderEl();
    if (!slider) return;

    const pct = Math.round(loadIntensity() * 100);
    slider.min = "0";
    slider.max = "100";
    slider.step = "1";
    slider.value = String(Math.min(100, Math.max(0, pct)));
    setLabelPct(sliderToPct(slider.value));

    if (toggle) {
      toggle.checked = loadUnder();
      toggle.addEventListener("change", () => {
        saveUnder(toggle.checked);
        applyMix();
      });
    }

    ["input", "change", "pointerup", "touchend", "keyup"].forEach((evt) => {
      slider.addEventListener(evt, () => onIntensityInput(slider));
    });

    window.__etubuMixPct = () => onIntensityInput(slider);

    applyMix();
  }

  function init() {
    bind();
  }

  function refreshUi() {
    setLabelPct(readPctFromSlider());
    const toggle = document.getElementById("mixUnderMusic");
    syncFieldEnabled(toggle ? !!toggle.checked : loadUnder());
  }

  function hasStreamingAccess() {
    return false;
  }

  function refreshLockUi() {}

  return {
    init,
    refreshUi,
    applyMix,
    onIntensityInput,
    hasStreamingAccess,
    refreshLockUi,
  };
})();
