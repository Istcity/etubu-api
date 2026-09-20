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
  let vercelAnalyticsLoaded = false;

  const COPY = {
    tr: {
      title: "Çerezler ve gizlilik",
      body: "Zorunlu çerezler sitenin çalışması içindir. Analitik (Vercel / Google) ve reklam (Yandex) yalnızca siz izin verirseniz kullanılır. Tercih çerezleri dil, tema ve tanıtım turunu hatırlar.",
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
      anaH: "Vercel Analytics ve Google Analytics — ziyaret ve performans ölçümü.",
      mkt: "Reklam",
      mktH: "Yandex RTB / Google reklamları — kişiselleştirilmiş veya bağlamsal reklam.",
      reopen: "Çerez ayarları",
    },
    en: {
      title: "Cookies and privacy",
      body: "Necessary cookies make the site work. Analytics (Vercel / Google) and ads (Yandex) run only with your permission. Preference cookies remember language, theme and the intro tour.",
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
      anaH: "Vercel Analytics and Google Analytics — visit and performance measurement.",
      mkt: "Advertising",
      mktH: "Yandex RTB / Google ads — contextual or personalized ads.",
      reopen: "Cookie settings",
    },
    de: {
      title: "Cookies und Datenschutz",
      body: "Erforderliche Cookies ermöglichen die Grundfunktionen. Analytik (Vercel / Google) und Werbung (Yandex) werden nur mit Ihrer Zustimmung verwendet.",
      privacy: "Datenschutzerklärung",
      reject: "Nur notwendige",
      settings: "Einstellungen",
      accept: "Alle akzeptieren",
      save: "Auswahl speichern",
      nec: "Notwendig",
      necH: "Sicherheit, Sitzung und diese Einwilligung. Immer aktiv.",
      pref: "Präferenzen",
      prefH: "Sprache, Sound/Design und Einführungstour.",
      ana: "Analytik",
      anaH: "Vercel Analytics und Google Analytics — Besuch und Performance.",
      mkt: "Werbung",
      mktH: "Werbung — personalisierte oder kontextbezogene Anzeigen.",
      reopen: "Cookie-Einstellungen",
    },
    fr: {
      title: "Cookies et confidentialité",
      body: "Les cookies nécessaires assurent le bon fonctionnement du site. Les mesures d'audience (Vercel / Google) et publicités ne sont activées qu'avec votre accord.",
      privacy: "Politique de confidentialité",
      reject: "Essentiels uniquement",
      settings: "Paramètres",
      accept: "Tout accepter",
      save: "Enregistrer",
      nec: "Essentiels",
      necH: "Sécurité, session et consentement. Toujours actif.",
      pref: "Préférences",
      prefH: "Langue, thème et visite guidée.",
      ana: "Analytique",
      anaH: "Vercel Analytics et Google Analytics — audience et performance.",
      mkt: "Publicité",
      mktH: "Publicités contextuelles ou personnalisées.",
      reopen: "Paramètres des cookies",
    },
    es: {
      title: "Cookies y privacidad",
      body: "Las cookies necesarias hacen que el sitio funcione. Analítica (Vercel / Google) y publicidad solo se utilizan con su consentimiento.",
      privacy: "Política de privacidad",
      reject: "Solo necesarias",
      settings: "Ajustes",
      accept: "Aceptar todas",
      save: "Guardar opciones",
      nec: "Necesarias",
      necH: "Seguridad, sesión y este registro. Siempre activo.",
      pref: "Preferencias",
      prefH: "Idioma, tema y tour de bienvenida.",
      ana: "Analítica",
      anaH: "Vercel Analytics y Google Analytics — visitas y rendimiento.",
      mkt: "Publicidad",
      mktH: "Anuncios contextuales o personalizados.",
      reopen: "Configuración de cookies",
    },
    ja: {
      title: "Cookieとプライバシー",
      body: "必須Cookieはサイトの基本機能に必要です。アクセス解析（Vercel / Google）および広告は、お客様の同意を得た場合のみ有効になります。",
      privacy: "プライバシーポリシー",
      reject: "必須のみ",
      settings: "設定",
      accept: "すべて同意",
      save: "設定を保存",
      nec: "必須",
      necH: "セキュリティ、セッション、同意記録。常に有効。",
      pref: "設定の保存",
      prefH: "言語、サウンド/テーマ、ガイドの非表示。",
      ana: "アクセス解析",
      anaH: "Vercel Analytics と Google Analytics — 訪問とパフォーマンス測定。",
      mkt: "広告",
      mktH: "関連広告の表示。",
      reopen: "Cookie設定",
    },
    ru: {
      title: "Файлы cookie и конфиденциальность",
      body: "Необходимые файлы cookie обеспечивают работу сайта. Аналитика (Vercel / Google) и реклама используются только с вашего согласия.",
      privacy: "Политика конфиденциальности",
      reject: "Только обязательные",
      settings: "Настройки",
      accept: "Принять все",
      save: "Сохранить выбор",
      nec: "Обязательные",
      necH: "Безопасность, сессия и запись согласия. Всегда включено.",
      pref: "Предпочтения",
      prefH: "Язык, тема звука и скрытие обучающего тура.",
      ana: "Аналитика",
      anaH: "Vercel Analytics и Google Analytics — посещаемость и производительность.",
      mkt: "Реклама",
      mktH: "Контекстная или персонализированная реклама.",
      reopen: "Настройки cookie",
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

  function injectScriptOnce(id, src, attrs = {}) {
    if (document.getElementById(id)) return;
    const s = document.createElement("script");
    s.id = id;
    s.defer = true;
    s.src = src;
    Object.keys(attrs).forEach((k) => {
      s.setAttribute(k, attrs[k]);
    });
    document.head.appendChild(s);
  }

  /** Vercel Web Analytics + Speed Insights (site Vercel'de yayınlandığında aktif olur) */
  function loadVercelAnalytics() {
    if (vercelAnalyticsLoaded) return;
    vercelAnalyticsLoaded = true;
    try {
      window.va =
        window.va ||
        function () {
          (window.vaq = window.vaq || []).push(arguments);
        };
      window.si =
        window.si ||
        function () {
          (window.siq = window.siq || []).push(arguments);
        };
    } catch (_) {}
    injectScriptOnce("etubu-vercel-insights", "/_vercel/insights/script.js");
    injectScriptOnce("etubu-vercel-speed", "/_vercel/speed-insights/script.js");
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
    loadVercelAnalytics();
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
#etubuConsent[hidden]{display:none!important;pointer-events:none!important}
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
    wrap.removeAttribute("hidden");
    wrap.style.removeProperty("display");
    wrap.style.pointerEvents = "";
  }

  function hideBanner() {
    if (!ui) return;
    ui.hidden = true;
    ui.setAttribute("hidden", "");
    ui.style.setProperty("display", "none", "important");
    ui.style.pointerEvents = "none";
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
    wrap.removeAttribute("hidden");
    wrap.style.removeProperty("display");
    wrap.style.pointerEvents = "";
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
    hide: hideBanner,
    acceptAll,
    rejectOptional,
    get: () => state,
  };
})();
window.Consent = Consent;
