/**
 * Araç tarayıcıları (özellikle Tesla): localStorage/çerez kalıcı değil.
 * Yer imi URL’si (?c=DAVET + ayarlar) ile giriş/davet ve tercihleri korur.
 *
 * DurablePrefs: URL → cookie → localStorage (okuma önceliği).
 * Yazma: her zaman localStorage; ephemeral’da ayrıca cookie + URL.
 */
const CarBrowser = (() => {
  const cfg = () => window.ETUBU_CONFIG || {};
  const COOKIE_MAX_AGE = 60 * 60 * 24 * 400; // ~400 gün
  const URL_SYNC_KEYS = ["voice", "theme", "vol", "sens", "gauge", "mute", "lang"];

  /** @type {Record<string, { url: string, ls: string, cookie: string }>} */
  const PREF_META = {
    voice: { url: "voice", ls: "etubu_voice", cookie: "etubu_v" },
    visual: { url: "theme", ls: "etubu_visual", cookie: "etubu_t" },
    volume: { url: "vol", ls: "etubu_volume", cookie: "etubu_vol" },
    sensitivity: { url: "sens", ls: "etubu_sensitivity", cookie: "etubu_s" },
    gauge: { url: "gauge", ls: "etubu_gauge_screen", cookie: "etubu_g" },
    mute: { url: "mute", ls: "etubu_mute", cookie: "etubu_m" },
    lang: { url: "lang", ls: "etubu_lang", cookie: "etubu_lang" },
  };

  let urlSyncTimer = null;
  /** @type {Record<string, string>} */
  let pendingUrl = {};

  function isTesla() {
    const ua = navigator.userAgent || "";
    if (/Tesla|QtCarBrowser|TeslaBrowser/i.test(ua)) return true;
    // Bazı sürümlerde UA sade Chromium; araç ekranı + ephemeral depo ipucu
    try {
      const touch = navigator.maxTouchPoints > 0;
      const wide = Math.max(window.screen?.width || 0, window.innerWidth || 0) >= 1100;
      const shortish =
        Math.min(window.screen?.height || 9999, window.innerHeight || 9999) <= 1200;
      const noHover = window.matchMedia?.("(hover: none)")?.matches;
      if (touch && wide && shortish && noHover && !storageWorks()) return true;
    } catch (_) {}
    return false;
  }

  function storageWorks() {
    try {
      const k = "__etubu_ls_probe";
      localStorage.setItem(k, "1");
      const ok = localStorage.getItem(k) === "1";
      localStorage.removeItem(k);
      return ok;
    } catch (_) {
      return false;
    }
  }

  /** Bellek yok / güvenilmez → km ve üyelik localStorage’a yazılamaz */
  function isEphemeral() {
    return isTesla() || !storageWorks();
  }

  function normalizeCode(s) {
    return String(s || "")
      .toUpperCase()
      .normalize("NFKD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/[^A-Z0-9]/g, "");
  }

  function inviteCodes() {
    return [
      ...(cfg().INVITE_CODES || []),
      cfg().INVITE_CODE,
    ]
      .filter(Boolean)
      .map(normalizeCode);
  }

  /** Yer imi: etubu.com/?c=KOD veya ?invite=KOD */
  function inviteFromUrl() {
    try {
      const p = new URLSearchParams(window.location.search);
      return normalizeCode(p.get("c") || p.get("invite") || "");
    } catch (_) {
      return "";
    }
  }

  function isValidInvite(raw) {
    const code = normalizeCode(raw);
    return code.length >= 6 && inviteCodes().includes(code);
  }

  function hasUrlInvite() {
    return isValidInvite(inviteFromUrl());
  }

  function readCookie(name) {
    try {
      const parts = (`; ${document.cookie}`).split(`; ${name}=`);
      if (parts.length < 2) return null;
      return decodeURIComponent(parts.pop().split(";").shift() || "") || null;
    } catch (_) {
      return null;
    }
  }

  function writeCookie(name, value) {
    try {
      if (typeof Consent !== "undefined" && !Consent.allows("preferences")) return;
      const secure = location.protocol === "https:" ? "; Secure" : "";
      document.cookie = `${name}=${encodeURIComponent(value)}; Path=/; Max-Age=${COOKIE_MAX_AGE}; SameSite=Lax${secure}`;
    } catch (_) {}
  }

  function readLs(key) {
    try {
      return localStorage.getItem(key);
    } catch (_) {
      return null;
    }
  }

  function writeLs(key, value) {
    try {
      if (typeof Consent !== "undefined" && !Consent.allows("preferences")) return;
      localStorage.setItem(key, value);
    } catch (_) {}
  }

  function readUrlParam(name) {
    try {
      const v = new URLSearchParams(window.location.search).get(name);
      return v == null || v === "" ? null : v;
    } catch (_) {
      return null;
    }
  }

  /**
   * Okuma: URL → cookie → localStorage
   * (Tesla oturumlarını kurtarmak için URL öncelikli)
   */
  function getPref(name) {
    const meta = PREF_META[name];
    if (!meta) return null;
    const fromUrl = readUrlParam(meta.url);
    if (fromUrl != null) return fromUrl;
    try {
      if (typeof Consent !== "undefined" && !Consent.allows("preferences")) return null;
    } catch (_) {}
    const fromCookie = readCookie(meta.cookie);
    if (fromCookie != null) return fromCookie;
    return readLs(meta.ls);
  }

  function flushUrlSync() {
    urlSyncTimer = null;
    if (!Object.keys(pendingUrl).length) return;
    try {
      const url = new URL(window.location.href);
      Object.entries(pendingUrl).forEach(([k, v]) => {
        if (v == null || v === "") url.searchParams.delete(k);
        else url.searchParams.set(k, v);
      });
      pendingUrl = {};
      const qs = url.searchParams.toString();
      history.replaceState({}, "", url.pathname + (qs ? `?${qs}` : "") + url.hash);
    } catch (_) {
      pendingUrl = {};
    }
  }

  function scheduleUrlSync(urlKey, value) {
    pendingUrl[urlKey] = value;
    if (urlSyncTimer) clearTimeout(urlSyncTimer);
    urlSyncTimer = setTimeout(flushUrlSync, 280);
  }

  /**
   * Yazma: her zaman localStorage + cookie (küçük ayarlar).
   * Ephemeral (Tesla): ayrıca URL (yer imi ile geri gelir).
   * opts.forceUrl — masaüstünde de URL’e yaz (nadir).
   */
  function setPref(name, value, opts = {}) {
    const meta = PREF_META[name];
    if (!meta) return;
    const str = value == null ? "" : String(value);
    if (!str) return;
    writeLs(meta.ls, str);
    writeCookie(meta.cookie, str);
    if (opts.forceUrl || isEphemeral()) {
      // mute=0 → URL’den sil (getPref URL öncelikli; “0” kalırsa kafa karıştırır)
      if (name === "mute" && str === "0") scheduleUrlSync(meta.url, "");
      else scheduleUrlSync(meta.url, str);
    }
  }

  /** Anlık snapshot (yer imi URL’si için) */
  function snapshotPrefs() {
    /** @type {Record<string, string>} */
    const out = {};
    Object.keys(PREF_META).forEach((name) => {
      const v = getPref(name);
      if (v != null && v !== "") out[name] = v;
    });
    return out;
  }

  /** Bookmark URL for Tesla users — davet + güncel ayarlar */
  function bookmarkUrl(inviteCode) {
    const base = (cfg().SITE_URL || window.location.origin || "https://etubu.com").replace(
      /\/$/,
      ""
    );
    const params = new URLSearchParams();
    const code = normalizeCode(inviteCode || inviteFromUrl());
    if (code && isValidInvite(code)) params.set("c", code);

    const snap = snapshotPrefs();
    if (snap.voice) params.set("voice", snap.voice);
    if (snap.visual) params.set("theme", snap.visual);
    if (snap.volume) params.set("vol", snap.volume);
    if (snap.sensitivity) params.set("sens", snap.sensitivity);
    if (snap.gauge) params.set("gauge", snap.gauge);
    if (snap.mute) params.set("mute", snap.mute);
    if (snap.lang) params.set("lang", snap.lang);

    // Canlı URL’de varsa onları tercih et (henüz flush edilmemiş olabilir)
    try {
      const live = new URLSearchParams(window.location.search);
      URL_SYNC_KEYS.forEach((k) => {
        const v = live.get(k);
        if (v) params.set(k, v);
      });
      Object.entries(pendingUrl).forEach(([k, v]) => {
        if (v) params.set(k, v);
      });
    } catch (_) {}

    const qs = params.toString();
    return qs ? `${base}/?${qs}` : `${base}/`;
  }

  function applyDomFlags() {
    if (isTesla()) document.body.classList.add("tesla-browser");
    if (isEphemeral()) document.body.classList.add("ephemeral-browser");
  }

  function readViewportSize() {
    const vv = window.visualViewport;
    const w = Math.round(
      (vv && vv.width) || window.innerWidth || document.documentElement.clientWidth || 0
    );
    const h = Math.round(
      (vv && vv.height) || window.innerHeight || document.documentElement.clientHeight || 0
    );
    return { w, h };
  }

  /** Tüm Tesla ekranları: ölçü + yoğunluk + ölçek */
  function syncViewportHeight() {
    try {
      if (!isTesla() && !isEphemeral()) return;
      const { w, h } = readViewportSize();
      if (!w || !h) return;

      const root = document.documentElement;
      const body = document.body;
      root.style.setProperty("--vvw", `${w}px`);
      root.style.setProperty("--vvh", `${h}px`);
      body.style.setProperty("--vvw", `${w}px`);
      body.style.setProperty("--vvh", `${h}px`);

      // --tesla-scale CSS’te density/layout ile ayarlanır; inline override taşmaya yol açıyordu.
      // Yalnızca ince yükseklik düzeltmesi (CSS çarpanı).
      const vhFit = Math.max(0.85, Math.min(1.05, h / 820));
      root.style.setProperty("--tesla-vh-fit", vhFit.toFixed(3));
      body.style.setProperty("--tesla-vh-fit", vhFit.toFixed(3));
      root.style.removeProperty("--tesla-scale");
      body.style.removeProperty("--tesla-scale");

      let density = "normal";
      if (h < 680) density = "compact";
      else if (h >= 920) density = "roomy";
      body.setAttribute("data-tesla-density", density);
      body.setAttribute("data-tesla-aspect", w / h >= 1.7 ? "wide" : "standard");
      // Yarım ekran / bölünmüş nav: dar veya düşük en-boy
      body.setAttribute("data-tesla-layout", w < 980 || w / h < 1.25 ? "half" : "full");
    } catch (_) {}
  }

  function bindViewportSync() {
    if (!isTesla() && !isEphemeral()) return;
    syncViewportHeight();
    const bump = () => {
      syncViewportHeight();
      setTimeout(syncViewportHeight, 160);
      setTimeout(syncViewportHeight, 500);
    };
    window.addEventListener("resize", bump, { passive: true });
    window.addEventListener("orientationchange", bump, { passive: true });
    window.addEventListener("pageshow", bump, { passive: true });
    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "visible") bump();
    });
    if (window.visualViewport) {
      window.visualViewport.addEventListener("resize", bump, { passive: true });
      window.visualViewport.addEventListener("scroll", syncViewportHeight, {
        passive: true,
      });
    }
  }

  /** Tesla tarayıcısı: sol paneli gizle, reklamları aktif tut (ücretsiz model) */
  function forceCompactChrome() {
    if (!isTesla() && !isEphemeral()) return;
    document.body.classList.add("panel-hidden");
    const editorial = document.getElementById("siteEditorial");
    if (editorial) editorial.hidden = true;
    if (typeof Paywall !== "undefined" && Paywall.isAdFree()) {
      document.body.classList.add("ads-hidden");
      try {
        typeof Ads !== "undefined" && Ads.hideAll?.();
      } catch (_) {}
    } else {
      document.body.classList.remove("ads-hidden", "drive-focus");
      try {
        typeof Ads !== "undefined" && Ads.showRails?.();
      } catch (_) {}
    }
    syncViewportHeight();
  }

  /**
   * URL’deki daveti uygula (yazmaya gerek yok).
   * Tesla’da ?c= URL’de kalsın — yenilemede tekrar çalışır.
   */
  function bootstrapFromUrl() {
    const code = inviteFromUrl();
    if (!code || !isValidInvite(code)) return false;
    if (typeof Paywall !== "undefined" && Paywall.redeemInvite) {
      const result = Paywall.redeemInvite(code, { persistUrl: true });
      return !!result?.ok;
    }
    return true;
  }

  function refreshTeslaHint() {
    const el = document.getElementById("teslaBookmarkHint");
    if (!el) return;
    const show = isEphemeral();
    el.hidden = !show;
    if (!show) return;
    const url = bookmarkUrl();
    const t =
      typeof I18n !== "undefined"
        ? I18n.t("teslaBookmarkHint", { url })
        : `Bookmark this page: ${url}`;
    el.textContent = t;
  }

  function init() {
    applyDomFlags();
    bindViewportSync();
    forceCompactChrome();
    // Paywall.init URL davetini uygular (callback’ler hazır olduktan sonra)
    refreshTeslaHint();
  }

  return {
    init,
    isTesla,
    isEphemeral,
    storageWorks,
    inviteFromUrl,
    hasUrlInvite,
    isValidInvite,
    bookmarkUrl,
    bootstrapFromUrl,
    refreshTeslaHint,
    syncViewportHeight,
    forceCompactChrome,
    normalizeCode,
    getPref,
    setPref,
    snapshotPrefs,
    PREF_META,
  };
})();
