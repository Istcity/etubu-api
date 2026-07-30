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
    return /Tesla|QtCarBrowser|TeslaBrowser/i.test(ua);
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
    normalizeCode,
    getPref,
    setPref,
    snapshotPrefs,
    PREF_META,
  };
})();
