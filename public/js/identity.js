/**
 * Kullanıcı kimliği + deneme km senkronu.
 * - Misafir: cihaz UUID (localStorage)
 * - Google giriş: email → sunucuda aynı kayıt
 * - Admin sıfırlama: TRIAL_RESET_CODES veya api admin_key
 */
const Identity = (() => {
  const STORAGE_DEVICE = "etubu_device_id";
  const STORAGE_EMAIL = "etubu_user_email";
  const cfg = () => window.ETUBU_CONFIG || {};

  function t(key, vars) {
    return typeof I18n !== "undefined" ? I18n.t(key, vars) : key;
  }

  function uuid() {
    if (crypto?.randomUUID) return crypto.randomUUID();
    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
      const r = (Math.random() * 16) | 0;
      const v = c === "x" ? r : (r & 0x3) | 0x8;
      return v.toString(16);
    });
  }

  function getDeviceId() {
    try {
      let id = localStorage.getItem(STORAGE_DEVICE);
      if (!id) {
        id = uuid();
        localStorage.setItem(STORAGE_DEVICE, id);
      }
      return id;
    } catch (_) {
      return "local-only";
    }
  }

  function getEmail() {
    try {
      return (localStorage.getItem(STORAGE_EMAIL) || "").trim().toLowerCase();
    } catch (_) {
      return "";
    }
  }

  function shortId() {
    const email = getEmail();
    if (email) return email;
    const id = getDeviceId();
    return id.length > 12 ? `misafir-${id.slice(0, 8)}` : id;
  }

  function trialApiUrl() {
    return cfg().TRIAL_KM_API_URL || "https://etubu.com/api/trial-km.php";
  }

  async function syncToServer(totalKm) {
    const body = {
      action: "sync",
      deviceId: getDeviceId(),
      email: getEmail() || undefined,
      totalKm: Number(totalKm) || 0,
    };
    try {
      const res = await fetch(trialApiUrl(), {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      if (!res.ok) return null;
      const data = await res.json();
      if (data?.ok && typeof data.totalKm === "number") {
        // Sunucu daha yüksek km tutuyorsa (başka cihaz) al
        if (data.totalKm > (Number(totalKm) || 0) + 0.01) {
          GpsTracker.setTotalKm?.(data.totalKm);
          Paywall.updateTrialPill?.(data.totalKm);
          refreshAccountUi();
        }
        return data;
      }
    } catch (_) {}
    return null;
  }

  async function pullFromServer() {
    const q = new URLSearchParams({
      deviceId: getDeviceId(),
    });
    const email = getEmail();
    if (email) q.set("email", email);
    try {
      const res = await fetch(`${trialApiUrl()}?${q}`);
      if (!res.ok) return null;
      const data = await res.json();
      if (data?.ok && typeof data.totalKm === "number") {
        const local = GpsTracker.loadTotalKm?.() ?? 0;
        const merged = Math.max(local, data.totalKm);
        if (Math.abs(merged - local) > 0.01) {
          GpsTracker.setTotalKm?.(merged);
        }
        Paywall.updateTrialPill?.(merged);
        refreshAccountUi();
        return data;
      }
    } catch (_) {}
    return null;
  }

  /**
   * Destek sıfırlama kodu (config.TRIAL_RESET_CODES) veya sunucu admin_key.
   * Yerel km'yi 0 yapar; sunucuya da reset gönderir.
   */
  async function resetTrialWithCode(rawCode) {
    const normalize = (s) =>
      String(s || "")
        .toUpperCase()
        .replace(/[^A-Z0-9]/g, "");
    const code = normalize(rawCode);
    const list = (cfg().TRIAL_RESET_CODES || []).map(normalize);
    const localOk = code.length >= 8 && list.includes(code);
    const adminKey = cfg().TRIAL_ADMIN_KEY || "";

    if (!localOk && !adminKey) {
      return { ok: false, message: t("trialResetInvalid") };
    }

    GpsTracker.resetTotalKm?.();
    Paywall.updateTrialPill?.(0);
    refreshAccountUi();

    try {
      await fetch(trialApiUrl(), {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: "reset",
          deviceId: getDeviceId(),
          email: getEmail() || undefined,
          resetCode: localOk ? code : undefined,
          adminKey: !localOk ? adminKey : undefined,
        }),
      });
    } catch (_) {}

    if (typeof Paywall !== "undefined") {
      // Katalog tekrar açılsın
      Paywall.checkAndMaybeBlock?.(0);
      if (Paywall.onAccessChange) {
        /* noop */
      }
    }
    document.dispatchEvent(new CustomEvent("etubu:trial-reset"));
    return { ok: true, message: t("trialResetOk") };
  }

  function freeKm() {
    return cfg().FREE_KM || 5;
  }

  function refreshAccountUi() {
    const idEl = document.getElementById("accountIdLabel");
    const kmEl = document.getElementById("accountKmLabel");
    const email = getEmail();
    if (idEl) {
      if (email) idEl.textContent = email;
      else idEl.textContent = shortId();
    }
    if (kmEl) {
      kmEl.textContent = email
        ? t("googleSettingsHint")
        : t("freeAdsSupported");
    }
  }

  function bindUi() {
    const btn = document.getElementById("trialResetBtn");
    const input = document.getElementById("trialResetInput");
    const note = document.getElementById("trialResetNote");
    btn?.addEventListener("click", async () => {
      const res = await resetTrialWithCode(input?.value || "");
      if (note) note.textContent = res.message;
      if (res.ok && input) input.value = "";
      refreshAccountUi();
      // Katalog UI yenile
      if (typeof window !== "undefined") {
        document.dispatchEvent(new CustomEvent("etubu:access-change"));
      }
    });
    refreshAccountUi();
  }

  let syncTimer = null;
  function scheduleSync(totalKm) {
    clearTimeout(syncTimer);
    syncTimer = setTimeout(() => syncToServer(totalKm), 1200);
  }

  function init() {
    // Bellek yoksa kimlik/sync anlamsız — sessizce çık
    if (typeof CarBrowser !== "undefined" && CarBrowser.isEphemeral()) {
      refreshAccountUi();
      return;
    }
    getDeviceId();
    bindUi();
    pullFromServer().finally(() => refreshAccountUi());
  }

  return {
    init,
    getDeviceId,
    getEmail,
    shortId,
    syncToServer,
    scheduleSync,
    pullFromServer,
    resetTrialWithCode,
    refreshAccountUi,
  };
})();
