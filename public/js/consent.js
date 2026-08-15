/**
 * Çerez / depolama izni — KVKK & GDPR / ePrivacy tarzı.
 * Zorunlu kayıt dışında analitik ve reklam üçüncü tarafı onaydan önce yüklenmez.
 * iOS native uygulamada gösterilmez (App Store gizlilik etiketleri).
 */
const Consent = (() => {
  const VERSION = 1;
  const LS_KEY = "etubu_consent";
  const COOKIE = "etubu_consent";
  const GA_ID = "G-9FQ0VVHGYC";
  const MAX_AGE = 60 * 60 * 24 * 180; // 6 ay — yeniden onay

  let state = null;
  let ui = null;
  const listeners = [];
  let analyticsLoaded = false;

  const COPY = {
    tr: {
      title: "Çerezler ve gizlilik",
      body: "Zorunlu çerezler sitenin çalışması içindir. Analitik (Google) ve reklam (Yandex) çerezleri yalnızca siz izin verirseniz kullanılır. Tercih çerezleri dil, tema ve tanıtım turunu hatırlar.",
      privacy: "Gizlilik politikası",
      reject: "Yalnızca zorunlu",
      settings: "Ayarlar",
      accept: "Tümünü kabul et",
      save: "Seçimi kaydet",
      nec: "Zorunlu",
      necH: "Güvenlik, oturum ve bu izin kaydı. Kapatılamaz.",
      pref: "Tercihler",
      prefH: "Dil, ses/tema, tanıtım turunun tekrar gösterilmemesi.",
      ana: "Analitik",
      anaH: "Google Analytics — ziyaret ölçümü, IP kısmi maskeleme.",
      mkt: "Reklam",
      mktH: "Yandex RTB / Google reklamları — kişiselleştirilmiş veya bağlamsal reklam.",
      reopen: "Çerez ayarları",
    },
    en: {
      title: "Cookies and privacy",
      body: "Necessary cookies make the site work. Analytics (Google) and ads (Yandex) run only with your permission. Preference cookies remember language, theme and the intro tour.",
      privacy: "Privacy policy",
      reject: "Necessary only",
      settings: "Settings",
      accept: "Accept all",
      save: "Save choices",
      nec: "Necessary",
      necH: "Security, session and this consent record. Always on.",
      pref: "Preferences",
      prefH: "Language, sound/theme, hiding the intro tour.",
      ana: "Analytics",
      anaH: "Google Analytics — visit measurement with IP anonymization.",
      mkt: "Advertising",
      mktH: "Yandex RTB / Google ads — contextual or personalized ads.",
      reopen: "Cookie settings",
    },
  };

  function str(key) {
    if (typeof I18n !== "undefined" && I18n.t) {
      const k = "consent" + key.charAt(0).toUpperCase() + key.slice(1);
      const v = I18n.t(k);
      if (v && v !== k) return v;
    }
    const lang = (typeof I18n !== "undefined" && I18n.lang) || document.documentElement.lang || "tr";
    const pack = COPY[lang] || COPY.tr;
    return pack[key] || COPY.en[key] || key;
  }

  function isNativeApp() {
    try {
      if (window.__ETUBU_NATIVE_CLUSTER__) return true;
      if (window.Capacitor?.isNativePlatform?.()) return true;
    } catch (_) {}
    return false;
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
      document.cookie = `${name}=${encodeURIComponent(value)}; Path=/; Max-Age=${MAX_AGE}; SameSite=Lax${secure}`;
    } catch (_) {}
  }

  function parse(raw) {
    if (!raw) return null;
    try {
      const o = JSON.parse(raw);
      if (!o || o.v !== VERSION) return null;
      if (!o.ts || Date.now() - o.ts > MAX_AGE * 1000) return null;
      return {
        v: VERSION,
        ts: o.ts,
        necessary: true,
        preferences: !!o.preferences,
        analytics: !!o.analytics,
        marketing: !!o.marketing,
      };
    } catch (_) {
      return null;
    }
  }

  function load() {
    try {
      const fromLs = parse(localStorage.getItem(LS_KEY));
      if (fromLs) return fromLs;
    } catch (_) {}
    return parse(readCookie(COOKIE));
  }

  function persist(next) {
    state = { ...next, v: VERSION, ts: Date.now(), necessary: true };
    const raw = JSON.stringify(state);
    try {
      localStorage.setItem(LS_KEY, raw);
    } catch (_) {}
    writeCookie(COOKIE, raw);
    return state;
  }

  function hasChoice() {
    return !!state;
  }

  function allows(kind) {
    if (kind === "necessary") return true;
    if (!state) return false;
    return !!state[kind];
  }

  function emit() {
    listeners.forEach((fn) => {
      try {
        fn(state);
      } catch (_) {}
    });
    try {
      window.dispatchEvent(new CustomEvent("etubu:consent", { detail: state }));
    } catch (_) {}
  }

  function onChange(fn) {
    if (typeof fn === "function") listeners.push(fn);
  }

  function applyThirdParties() {
    if (allows("analytics")) loadAnalytics();
    else denyAnalytics();
  }

  function gtagFn() {
    window.dataLayer = window.dataLayer || [];
    window.gtag =
      window.gtag ||
      function gtag() {
        window.dataLayer.push(arguments);
      };
    return window.gtag;
  }

  function loadAnalytics() {
    const gtag = gtagFn();
    gtag("consent", "update", {
      analytics_storage: "granted",
      ad_storage: allows("marketing") ? "granted" : "denied",
      ad_user_data: allows("marketing") ? "granted" : "denied",
      ad_personalization: allows("marketing") ? "granted" : "denied",
      functionality_storage: allows("preferences") ? "granted" : "denied",
      personalization_storage: allows("preferences") ? "granted" : "denied",
      security_storage: "granted",
    });
    if (analyticsLoaded) {
      gtag("event", "consent_update");
      return;
    }
    analyticsLoaded = true;
    const s = document.createElement("script");
    s.async = true;
    s.src = `https://www.googletagmanager.com/gtag/js?id=${GA_ID}`;
    document.head.appendChild(s);
    gtag("js", new Date());
    gtag("config", GA_ID, { anonymize_ip: true });
  }

  function denyAnalytics() {
    const gtag = gtagFn();
    gtag("consent", "update", {
      analytics_storage: "denied",
      ad_storage: "denied",
      ad_user_data: "denied",
      ad_personalization: "denied",
      functionality_storage: allows("preferences") ? "granted" : "denied",
      personalization_storage: "denied",
      security_storage: "granted",
    });
  }

  function expireCookie(name) {
    try {
      const secure = location.protocol === "https:" ? "; Secure" : "";
      document.cookie = `${name}=; Path=/; Max-Age=0; SameSite=Lax${secure}`;
    } catch (_) {}
  }

  function clearPreferenceStores() {
    [
      "etubu_intro_seen",
      "etubu_voice",
      "etubu_visual",
      "etubu_volume",
      "etubu_sensitivity",
      "etubu_gauge_screen",
      "etubu_mute",
      "etubu_lang",
    ].forEach((k) => {
      try {
        localStorage.removeItem(k);
      } catch (_) {}
    });
    ["etubu_intro_seen", "etubu_v", "etubu_t", "etubu_vol", "etubu_s", "etubu_g", "etubu_m", "etubu_lang"].forEach(
      expireCookie
    );
  }

  function save(partial) {
    persist({
      preferences: !!partial.preferences,
      analytics: !!partial.analytics,
      marketing: !!partial.marketing,
    });
    if (!partial.preferences) clearPreferenceStores();
    applyThirdParties();
    hideBanner();
    emit();
  }

  function acceptAll() {
    save({ preferences: true, analytics: true, marketing: true });
  }

  function rejectOptional() {
    save({ preferences: false, analytics: false, marketing: false });
  }

  function injectCss() {
    if (document.getElementById("etubuConsentCss")) return;
    const css = document.createElement("style");
    css.id = "etubuConsentCss";
    css.textContent = `
#etubuConsent{position:fixed;inset:0;z-index:13000;display:flex;align-items:center;justify-content:center;padding:12px;background:rgba(2,4,10,.55);font-family:"DM Sans",Inter,system-ui,sans-serif}
#etubuConsent[hidden]{display:none!important}
.etubu-consent-card{width:min(560px,100%);max-height:min(72dvh,72vh,560px);overflow:auto;background:#0c1422;color:#e8f4ff;border:1px solid rgba(255,255,255,.14);border-radius:16px;padding:16px 16px 14px;box-shadow:0 16px 48px rgba(0,0,0,.45)}
.etubu-consent-card h2{margin:0 0 8px;font-size:18px}
.etubu-consent-card p{margin:0 0 12px;font-size:13px;line-height:1.45;color:#9bb4c8}
.etubu-consent-card a{color:#5ce1ff}
.etubu-consent-actions{display:flex;flex-wrap:wrap;gap:8px;justify-content:flex-end}
.etubu-consent-actions button{min-height:44px;padding:0 14px;border-radius:12px;border:1px solid rgba(255,255,255,.16);background:rgba(255,255,255,.06);color:#e8f4ff;font-weight:700;cursor:pointer;font-size:13px}
.etubu-consent-actions .is-primary{background:linear-gradient(135deg,#00e8ff,#7b5cff);color:#021018;border:0}
.etubu-consent-panel{margin:8px 0 12px;display:flex;flex-direction:column;gap:8px}
.etubu-consent-row{display:flex;gap:10px;align-items:flex-start;padding:8px;border-radius:10px;background:rgba(255,255,255,.04)}
.etubu-consent-row input{margin-top:3px;width:18px;height:18px}
.etubu-consent-row strong{display:block;font-size:13px}
.etubu-consent-row span{display:block;font-size:11px;color:#8aa3b8;line-height:1.35}
@media(max-width:560px){.etubu-consent-actions{flex-direction:column}.etubu-consent-actions button{width:100%}}
`;
    document.head.appendChild(css);
  }

  function ensureUi() {
    if (ui) return ui;
    injectCss();
    const wrap = document.createElement("div");
    wrap.id = "etubuConsent";
    wrap.hidden = true;
    wrap.setAttribute("role", "dialog");
    wrap.setAttribute("aria-modal", "true");
    wrap.setAttribute("aria-labelledby", "etubuConsentTitle");
    wrap.innerHTML = `
      <div class="etubu-consent-card">
        <h2 id="etubuConsentTitle"></h2>
        <p id="etubuConsentBody"></p>
        <p><a id="etubuConsentPrivacy" href="privacy.html"></a></p>
        <div class="etubu-consent-panel" id="etubuConsentPanel" hidden>
          <label class="etubu-consent-row"><input type="checkbox" checked disabled /><div><strong data-k="nec"></strong><span data-k="necH"></span></div></label>
          <label class="etubu-consent-row"><input type="checkbox" id="consentPref" /><div><strong data-k="pref"></strong><span data-k="prefH"></span></div></label>
          <label class="etubu-consent-row"><input type="checkbox" id="consentAna" /><div><strong data-k="ana"></strong><span data-k="anaH"></span></div></label>
          <label class="etubu-consent-row"><input type="checkbox" id="consentMkt" /><div><strong data-k="mkt"></strong><span data-k="mktH"></span></div></label>
        </div>
        <div class="etubu-consent-actions">
          <button type="button" id="consentReject"></button>
          <button type="button" id="consentSettings"></button>
          <button type="button" class="is-primary" id="consentAccept"></button>
          <button type="button" class="is-primary" id="consentSave" hidden></button>
        </div>
      </div>`;
    document.body.appendChild(wrap);
    ui = wrap;
    wrap.querySelector("#consentReject").addEventListener("click", rejectOptional);
    wrap.querySelector("#consentAccept").addEventListener("click", acceptAll);
    wrap.querySelector("#consentSettings").addEventListener("click", () => showPanel(true));
    wrap.querySelector("#consentSave").addEventListener("click", () => {
      save({
        preferences: wrap.querySelector("#consentPref").checked,
        analytics: wrap.querySelector("#consentAna").checked,
        marketing: wrap.querySelector("#consentMkt").checked,
      });
    });
    return wrap;
  }

  function fillCopy() {
    const wrap = ensureUi();
    wrap.querySelector("#etubuConsentTitle").textContent = str("title");
    wrap.querySelector("#etubuConsentBody").textContent = str("body");
    const priv = wrap.querySelector("#etubuConsentPrivacy");
    priv.textContent = str("privacy");
    priv.setAttribute("href", "privacy.html");
    wrap.querySelector("#consentReject").textContent = str("reject");
    wrap.querySelector("#consentSettings").textContent = str("settings");
    wrap.querySelector("#consentAccept").textContent = str("accept");
    wrap.querySelector("#consentSave").textContent = str("save");
    wrap.querySelectorAll("[data-k]").forEach((el) => {
      el.textContent = str(el.getAttribute("data-k"));
    });
  }

  function showPanel(open) {
    const wrap = ensureUi();
    const panel = wrap.querySelector("#etubuConsentPanel");
    panel.hidden = !open;
    wrap.querySelector("#consentSave").hidden = !open;
    wrap.querySelector("#consentAccept").hidden = open;
    wrap.querySelector("#consentSettings").hidden = open;
    if (open && state) {
      wrap.querySelector("#consentPref").checked = !!state.preferences;
      wrap.querySelector("#consentAna").checked = !!state.analytics;
      wrap.querySelector("#consentMkt").checked = !!state.marketing;
    }
  }

  function showBanner() {
    fillCopy();
    const wrap = ensureUi();
    showPanel(false);
    wrap.hidden = false;
  }

  function hideBanner() {
    if (ui) ui.hidden = true;
  }

  function open() {
    fillCopy();
    const wrap = ensureUi();
    if (state) {
      wrap.querySelector("#consentPref").checked = !!state.preferences;
      wrap.querySelector("#consentAna").checked = !!state.analytics;
      wrap.querySelector("#consentMkt").checked = !!state.marketing;
    }
    showPanel(true);
    wrap.hidden = false;
  }

  function init() {
    if (isNativeApp()) {
      state = {
        v: VERSION,
        ts: Date.now(),
        necessary: true,
        preferences: true,
        analytics: false,
        marketing: false,
      };
      return;
    }
    gtagFn()("consent", "default", {
      analytics_storage: "denied",
      ad_storage: "denied",
      ad_user_data: "denied",
      ad_personalization: "denied",
      functionality_storage: "denied",
      personalization_storage: "denied",
      security_storage: "granted",
      wait_for_update: 500,
    });
    state = load();
    if (state) applyThirdParties();
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", () => {
        bindReopen();
        if (!state) showBanner();
      });
    } else {
      bindReopen();
      if (!state) showBanner();
    }
  }

  function bindReopen() {
    document.querySelectorAll("[data-consent-open]").forEach((btn) => {
      if (btn.dataset.consentBound) return;
      btn.dataset.consentBound = "1";
      btn.addEventListener("click", (e) => {
        e.preventDefault();
        open();
      });
    });
  }

  init();

  try {
    document.addEventListener("etubu:lang-change", () => {
      if (ui && !ui.hidden) fillCopy();
    });
  } catch (_) {}

  return {
    hasChoice,
    allows,
    onChange,
    open,
    acceptAll,
    rejectOptional,
    get: () => state,
  };
})();
window.Consent = Consent;
