/**
 * Monetization:
 * - Web: ads-supported; full theme/voice catalog free (no IAP UI).
 * - Native Cap shell: StoreKit premium (`com.etubu.premium`) — do not claim free catalog.
 *   Primary paywall is SwiftUI; Cap helpers must stay consistent with native gates.
 */
const Paywall = (() => {
  const cfg = () => window.ETUBU_CONFIG || {};
  const FREE_KM = () => cfg().FREE_KM || GpsTracker.FREE_TRIAL_KM;
  const PRICE_YEARLY = () => cfg().PRICE_YEARLY_TRY || cfg().PRICE_TRY || 300;
  const PRICE_MONTHLY = () => cfg().PRICE_MONTHLY_USD || 3;
  const PRICE_ADFREE = () =>
    cfg().PRICE_LIFETIME_USD || cfg().PRICE_ADFREE_TRY || 30;
  const YEAR_MS = 365 * 24 * 60 * 60 * 1000;
  const MONTH_MS = 31 * 24 * 60 * 60 * 1000;

  const STORAGE_PAID = "etubu_paid_v1"; // legacy + API uyumu
  const STORAGE_YEARLY_UNTIL = "etubu_yearly_until";
  const STORAGE_ADFREE = "etubu_adfree_v1";
  const STORAGE_INVITE = "etubu_invite_v1";
  const STORAGE_EMAIL = "etubu_user_email";
  const STORAGE_TOKEN = "etubu_google_sub";
  const STORAGE_GOOGLE_SIGNED = "etubu_google_signed";
  const STORAGE_APPLE_SUB = "etubu_apple_sub";
  const STORAGE_UPSELL_DISMISS = "etubu_upsell_dismissed";

  const overlay = () => document.getElementById("paywallOverlay");
  const statusEl = () => document.getElementById("paywallStatus");
  const trialPill = () => document.getElementById("trialPill");
  const paywallKm = () => document.getElementById("paywallKm");
  const removeAdsBtn = () => document.getElementById("removeAdsBtn");
  const premiumDock = () => document.getElementById("premiumDock");
  const premiumBtn = () => document.getElementById("premiumBtn");
  const dockMonthlyBtn = () => document.getElementById("dockMonthlyBtn");
  const dockLifetimeBtn = () => document.getElementById("dockLifetimeBtn");

  let onUnlocked = null;
  let onAdFree = null;
  let onAccessChange = null;
  let lastTrialOpen = true;

  function t(key, vars) {
    return typeof I18n !== "undefined" ? I18n.t(key, vars) : key;
  }

  function isEphemeral() {
    return typeof CarBrowser !== "undefined" && CarBrowser.isEphemeral();
  }

  function isInTrial(totalKm) {
    // Tesla vb.: bellek yok → km sayacı güvenilir değil; oturumda tam katalog
    if (isEphemeral()) return true;
    const km = totalKm != null ? totalKm : GpsTracker.loadTotalKm();
    return km < FREE_KM();
  }

  function yearlyUntil() {
    try {
      const raw = localStorage.getItem(STORAGE_YEARLY_UNTIL);
      const n = raw ? parseInt(raw, 10) : 0;
      return Number.isFinite(n) ? n : 0;
    } catch (_) {
      return 0;
    }
  }

  function hasYearly() {
    try {
      const until = yearlyUntil();
      if (until > Date.now()) return true;
      return localStorage.getItem(STORAGE_PAID) === "1" && until === 0;
    } catch (_) {
      return false;
    }
  }

  function isPaid() {
    return hasYearly();
  }

  function isNativeApp() {
    try {
      return !!(
        window.Capacitor?.isNativePlatform?.() ||
        (window.EtubuNative && typeof window.EtubuNative.purchase === "function")
      );
    } catch (_) {
      return false;
    }
  }

  /** Web: her zaman reklam. Native: IAP ad-free bayrağı. */
  function isAdFree() {
    if (!isNativeApp()) return false;
    try {
      return localStorage.getItem(STORAGE_ADFREE) === "1";
    } catch (_) {
      return false;
    }
  }

  function hasInvite() {
    try {
      if (localStorage.getItem(STORAGE_INVITE)) return true;
    } catch (_) {}
    return typeof CarBrowser !== "undefined" && CarBrowser.hasUrlInvite();
  }

  /** Web: ads-supported free catalog. Native: StoreKit entitlement only. */
  function hasCatalogAccess(totalKm) {
    if (isNativeApp()) {
      return isPaid() || isAdFree() || hasInvite();
    }
    return true;
  }

  /** Geriye uyum: full access = katalog */
  function hasFullAccess() {
    return hasCatalogAccess();
  }

  function setYearly(email, untilMs) {
    const until =
      untilMs && untilMs > Date.now() ? untilMs : Date.now() + YEAR_MS;
    localStorage.setItem(STORAGE_YEARLY_UNTIL, String(until));
    localStorage.setItem(STORAGE_PAID, "1");
    if (email) localStorage.setItem(STORAGE_EMAIL, email);
    localStorage.removeItem(STORAGE_UPSELL_DISMISS);
    hide();
    updateTrialPill(GpsTracker.loadTotalKm());
    refreshAdFreeUi();
    Identity?.syncToServer?.(GpsTracker.loadTotalKm());
    Identity?.refreshAccountUi?.();
    if (onUnlocked) onUnlocked();
    if (onAccessChange) onAccessChange();
  }

  /** Paddle aylık abonelik — katalog ~1 ay */
  function setMonthly(email, untilMs) {
    const until =
      untilMs && untilMs > Date.now() ? untilMs : Date.now() + MONTH_MS;
    setYearly(email, until);
  }

  /** Paddle ömür boyu erişim — katalog + reklamsız */
  function setLifetime(email) {
    setYearly(email, Date.now() + 100 * YEAR_MS);
    setAdFree(email);
  }

  function untilFromApi(iso) {
    if (!iso) return null;
    const ms = Date.parse(iso);
    return Number.isFinite(ms) ? ms : null;
  }

  function setPaid(email) {
    setYearly(email);
  }

  function setAdFree(email) {
    localStorage.setItem(STORAGE_ADFREE, "1");
    if (email) localStorage.setItem(STORAGE_EMAIL, email);
    refreshAdFreeUi();
    if (typeof Ads !== "undefined") Ads.hideAll?.();
    if (onAdFree) onAdFree();
    if (onAccessChange) onAccessChange();
  }

  function getSignedEmail() {
    try {
      return (localStorage.getItem(STORAGE_EMAIL) || "").trim().toLowerCase();
    } catch (_) {
      return "";
    }
  }

  function persistGoogleSession(email, sub) {
    const normalized = String(email || "").trim().toLowerCase();
    if (normalized) localStorage.setItem(STORAGE_EMAIL, normalized);
    if (sub) localStorage.setItem(STORAGE_TOKEN, String(sub));
    if (normalized) localStorage.setItem(STORAGE_GOOGLE_SIGNED, "1");
  }

  function isGoogleSignedIn() {
    try {
      const email = getSignedEmail();
      if (!email || !email.includes("@")) return false;
      if (localStorage.getItem(STORAGE_GOOGLE_SIGNED) === "1") return true;
      return !!(localStorage.getItem(STORAGE_TOKEN) || "").trim();
    } catch (_) {
      return false;
    }
  }

  function signOutGoogle() {
    try {
      localStorage.removeItem(STORAGE_EMAIL);
      localStorage.removeItem(STORAGE_TOKEN);
      localStorage.removeItem(STORAGE_GOOGLE_SIGNED);
      localStorage.removeItem(STORAGE_APPLE_SUB);
    } catch (_) {}
    setStatusMsg(t("googleSignOutOk"));
    refreshAuthUi();
    refreshAdFreeUi();
    Identity?.refreshAccountUi?.();
    if (onAccessChange) onAccessChange();
  }

  function refreshAuthUi() {
    const signedIn = canPurchasePremium();
    const googleBtns = [
      "googleSignBtn",
      "dockGoogleSignBtn",
    ];
    googleBtns.forEach((id) => {
      const el = document.getElementById(id);
      if (el) el.hidden = signedIn || id === "googleSignBtn";
    });

    const signOutBtn = document.getElementById("googleSignOutBtn");
    if (signOutBtn) signOutBtn.hidden = !signedIn;

    const premiumHint = document.getElementById("premiumSignInHint");
    const dockHint = document.getElementById("dockPremiumSignInHint");
    if (premiumHint) premiumHint.hidden = true;
    if (dockHint) dockHint.hidden = signedIn;

    Identity?.refreshAccountUi?.();
  }

  /** Web: Google zorunlu. Native iOS: Apple girişi de yeterli. */
  function canPurchasePremium() {
    if (isGoogleSignedIn()) return true;
    if (window.EtubuNative?.signInWithApple) {
      try {
        const apple = (localStorage.getItem(STORAGE_APPLE_SUB) || "").trim();
        const email = (localStorage.getItem(STORAGE_EMAIL) || "").trim();
        return !!(apple || email);
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  function setStatusMsg(msg) {
    const status = statusEl();
    const dockStatus = document.getElementById("dockInviteStatus");
    if (status && msg) status.textContent = msg;
    if (dockStatus && msg) dockStatus.textContent = msg;
  }

  function refreshAdFreeUi() {
    const dock = premiumDock();
    const monthly = dockMonthlyBtn();
    const lifetime = dockLifetimeBtn();
    const goPremium = premiumBtn();
    const planRow = document.getElementById("premiumPlanRow");
    const dockGoogle = document.getElementById("dockGoogleSignBtn");
    const dockHint = document.getElementById("dockPremiumSignInHint");
    const paywallGoogle = document.getElementById("googleSignBtn");
    const premiumHint = document.getElementById("premiumSignInHint");
    const adFreeHint = document.getElementById("adFreeHintEl");
    const inviteDockEl = document.getElementById("inviteDock");
    const signedIn = canPurchasePremium();
    const webFree = !isNativeApp();

    // Web: satın alma / davet UI kapalı
    if (dock) dock.hidden = true;
    if (inviteDockEl) inviteDockEl.hidden = true;
    if (goPremium) goPremium.hidden = true;
    if (planRow) planRow.hidden = true;
    if (monthly) monthly.hidden = true;
    if (lifetime) lifetime.hidden = true;
    if (dockGoogle) dockGoogle.hidden = signedIn;
    if (dockHint) dockHint.hidden = signedIn;
    if (paywallGoogle) paywallGoogle.hidden = true;
    if (premiumHint) premiumHint.hidden = true;

    const legacy = removeAdsBtn();
    if (legacy) legacy.hidden = true;

    const adFreePayBtn = document.getElementById("adFreeBtn");
    if (adFreePayBtn) adFreePayBtn.hidden = true;
    const payBtn = document.getElementById("payBtn");
    if (payBtn) payBtn.hidden = true;
    if (adFreeHint) adFreeHint.hidden = true;
    const upgradeBtn = document.getElementById("upgradeBtn");
    if (upgradeBtn) upgradeBtn.hidden = true;
    const restoreBtn = document.getElementById("restoreBtn");
    if (restoreBtn) restoreBtn.hidden = webFree;
    const continueFree = document.getElementById("continueFreeBtn");
    if (continueFree) continueFree.hidden = true;

    document.querySelectorAll(".payment-badges").forEach((el) => {
      el.hidden = true;
    });

    refreshAuthUi();
  }

  function updateTrialPill(_totalKm) {
    const pill = trialPill();
    if (!pill) return;
    if (isEphemeral()) {
      pill.textContent = t("teslaSessionFull");
      pill.title = t("googleSettingsHint");
      pill.style.borderColor = "rgba(0,240,255,.35)";
      pill.style.color = "var(--cyan)";
      Identity?.refreshAccountUi?.();
      return;
    }
    // Native: SwiftUI IAP messaging — Cap pill must not claim “ads-supported free catalog”
    if (isNativeApp()) {
      pill.textContent = t("premiumFreeNote") || t("trialFree");
      pill.title = t("premiumFreeNote") || t("trialAdHint");
      pill.style.borderColor = "rgba(0,240,255,.35)";
      pill.style.color = "var(--cyan)";
      Identity?.refreshAccountUi?.();
      return;
    }
    // Web: reklam desteği yönlendirmesi (deneme / üyelik yok)
    pill.textContent = t("trialFree");
    pill.title = t("trialAdHint");
    pill.style.borderColor = "rgba(255,200,100,.4)";
    pill.style.color = "#ffc864";
    Identity?.refreshAccountUi?.();
  }

  /** Hard block yok — sürüşe devam edilir */
  function shouldBlock() {
    return false;
  }

  function upsellDismissed() {
    return localStorage.getItem(STORAGE_UPSELL_DISMISS) === "1";
  }

  function dismissUpsell() {
    localStorage.setItem(STORAGE_UPSELL_DISMISS, "1");
    hide();
  }

  function redeemInvite(rawCode, opts = {}) {
    const normalize = (s) =>
      String(s || "")
        .toUpperCase()
        .normalize("NFKD")
        .replace(/[\u0300-\u036f]/g, "")
        .replace(/[^A-Z0-9]/g, "");
    const code = normalize(rawCode);
    const list = [
      ...(cfg().INVITE_CODES || []),
      cfg().INVITE_CODE,
    ]
      .filter(Boolean)
      .map(normalize);

    if (!code || code.length < 6 || !list.includes(code)) {
      return { ok: false, message: t("inviteInvalid") };
    }
    try {
      localStorage.setItem(STORAGE_INVITE, code);
      localStorage.removeItem(STORAGE_UPSELL_DISMISS);
    } catch (_) {}

    // Tesla: yer iminde kalsın diye ?c= URL’de tut
    if (opts.persistUrl || isEphemeral()) {
      try {
        const url = new URL(window.location.href);
        url.searchParams.set("c", code);
        history.replaceState({}, "", url.pathname + "?" + url.searchParams.toString() + url.hash);
      } catch (_) {}
    }

    hide();
    updateTrialPill(GpsTracker.loadTotalKm());
    refreshAdFreeUi();
    if (!isAdFree() && typeof Ads !== "undefined") Ads.showRails?.();
    Identity?.refreshAccountUi?.();
    if (onUnlocked) onUnlocked();
    if (onAccessChange) onAccessChange();
    try {
      document.dispatchEvent(new CustomEvent("etubu:access-change"));
    } catch (_) {}
    CarBrowser?.refreshTeslaHint?.();
    return {
      ok: true,
      message: isEphemeral() ? t("inviteOkTesla", { url: CarBrowser.bookmarkUrl(code) }) : t("inviteOk"),
    };
  }

  function show(_totalKm) {
    // Web: paywall yok — reklam destekli ücretsiz model
    if (!isNativeApp()) {
      hide();
      return;
    }
    const el = overlay();
    if (!el) return;
    el.hidden = false;
    if (paywallKm() && _totalKm != null) {
      paywallKm().textContent = t("paywallKm", { n: Number(_totalKm).toFixed(1) });
    }
    refreshAdFreeUi();
    if (typeof I18n !== "undefined") I18n.applyDom();
  }

  function hide() {
    const el = overlay();
    if (el) el.hidden = true;
  }

  /**
   * Deneme bitince katalog kilidi + soft upsell.
   * Sürüşü durdurmaz. true = katalog yeni kilitlendi (UI yenilenmeli).
   */
  function checkAndMaybeBlock(totalKm) {
    updateTrialPill(totalKm);
    refreshAdFreeUi();
    lastTrialOpen = true;
    hide();
    return false;
  }

  /**
   * product: "monthly" | "lifetime" | legacy "yearly" | "adfree"
   * Web: Paddle Checkout overlay (sandbox/production)
   * Native: EtubuNative.purchase (IAP)
   */
  async function startPayment(product) {
    const status = statusEl();
    const planType =
      product === "adfree" || product === "lifetime" ? "lifetime" : "monthly";

    if (!canPurchasePremium()) {
      setStatusMsg(t("premiumRequiresGoogle"));
      refreshAdFreeUi();
      // Web: Google ile giriş; native: Apple
      const signed =
        window.EtubuNative?.signInWithApple && !cfg().GOOGLE_CLIENT_ID
          ? await signInWithApple()
          : await signInWithGoogle();
      if (!signed?.ok || !canPurchasePremium()) {
        setStatusMsg(t("premiumRequiresGoogle"));
        refreshAdFreeUi();
        return;
      }
      refreshAdFreeUi();
    }

    const email = localStorage.getItem(STORAGE_EMAIL) || "";
    const productId =
      planType === "lifetime"
        ? cfg().IAP_ADFREE_ID || "etubu.ads.remove"
        : cfg().IAP_UNLOCK_ID || "com.etubu.premium";

    if (status) status.textContent = t("paymentStarting");

    if (window.EtubuNative?.purchase) {
      try {
        const result = await window.EtubuNative.purchase(productId);
        if (result?.ok) {
          if (planType === "lifetime") setLifetime(email || result.email);
          else setMonthly(email || result.email);
          return;
        }
        if (status) status.textContent = result?.error || t("paymentFail");
        return;
      } catch (e) {
        if (status) status.textContent = e.message || t("paymentFail");
        return;
      }
    }

    // Paddle Billing (öncelikli)
    if (typeof PaddleCheckout !== "undefined") {
      try {
        await PaddleCheckout.openCheckout(planType);
        if (status) status.textContent = t("paymentFormLoaded");
        return;
      } catch (e) {
        if (status) {
          status.textContent = e?.message || t("paymentNotConfigured");
        }
        if (cfg().DEV_UNLOCK) {
          setTimeout(() => {
            if (planType === "lifetime") setLifetime("dev@etubu.com");
            else setMonthly("dev@etubu.com");
          }, 800);
        }
        return;
      }
    }

    if (status) status.textContent = t("paymentNotConfigured");
  }

  async function restoreAccess() {
    if (window.EtubuNative?.restore) {
      const status = statusEl();
      if (status) status.textContent = t("checking");
      try {
        const result = await window.EtubuNative.restore();
        if (result?.unlock || result?.yearly) setYearly(result.email);
        if (result?.adfree) setAdFree(result.email);
        if (status) {
          status.textContent =
            result?.unlock || result?.yearly || result?.adfree
              ? t("accessRestored")
              : t("noPayment");
        }
        return;
      } catch (_) {
        if (status) status.textContent = t("verifyFail");
        return;
      }
    }

    const email =
      localStorage.getItem(STORAGE_EMAIL) ||
      prompt(t("restore"));
    if (!email) return;
    const status = statusEl();
    if (status) status.textContent = t("checking");

    try {
      const res = await fetch("/api/verify-payment.php", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email }),
      });
      const data = await res.json();
      if (data.paid || data.yearly) {
        setYearly(email, untilFromApi(data.yearlyUntil));
      }
      if (data.adfree) setAdFree(email);
      if (status) {
        status.textContent =
          data.paid || data.yearly || data.adfree
            ? t("accessRestored")
            : data.message || t("noPayment");
      }
    } catch (_) {
      if (status) status.textContent = t("verifyFail");
    }
  }

  async function signInWithApple() {
    const status = statusEl();
    const dockStatus = document.getElementById("dockInviteStatus");
    const setMsg = (msg) => {
      if (status) status.textContent = msg;
      if (dockStatus) dockStatus.textContent = msg;
    };

    if (!window.EtubuNative?.signInWithApple) {
      setMsg(t("appleSignInIosOnly"));
      return { ok: false };
    }

    setMsg(t("appleSignInPending"));
    try {
      const res = await window.EtubuNative.signInWithApple();
      if (!res?.ok) {
        setMsg(res?.error === "cancelled" ? t("appleSignInCancelled") : t("appleSignInFail"));
        return { ok: false };
      }
      const email = (res.email || "").trim();
      const user = res.user || "";
      if (email) localStorage.setItem(STORAGE_EMAIL, email.toLowerCase());
      if (user) localStorage.setItem(STORAGE_APPLE_SUB, user);
      if (email) localStorage.setItem(STORAGE_GOOGLE_SIGNED, "1");
      Identity?.pullFromServer?.();
      Identity?.refreshAccountUi?.();
      Identity?.syncToServer?.(GpsTracker.loadTotalKm());

      try {
        const restored = await window.EtubuNative.restore?.();
        if (restored?.unlock) setYearly(email || "apple");
        if (restored?.adfree) setAdFree(email || "apple");
      } catch (_) {}

      setMsg(email ? t("appleSignInOk", { email }) : t("appleSignInOkNoEmail"));
      refreshAdFreeUi();
      if (onAccessChange) onAccessChange();
      return { ok: true, email, user };
    } catch (e) {
      setMsg(t("appleSignInFail"));
      return { ok: false };
    }
  }

  let gsiScriptPromise = null;
  function loadGsiScript() {
    if (window.google?.accounts?.oauth2) return Promise.resolve();
    if (gsiScriptPromise) return gsiScriptPromise;
    gsiScriptPromise = new Promise((resolve, reject) => {
      const s = document.createElement("script");
      s.src = "https://accounts.google.com/gsi/client";
      s.async = true;
      s.onload = () => resolve();
      s.onerror = () => {
        gsiScriptPromise = null;
        reject(new Error("gsi load failed"));
      };
      document.head.appendChild(s);
    });
    return gsiScriptPromise;
  }

  async function signInWithGoogle() {
    const status = statusEl();
    const dockStatus = document.getElementById("dockInviteStatus");
    const setMsg = (msg) => {
      if (status) status.textContent = msg;
      if (dockStatus) dockStatus.textContent = msg;
    };

    const clientId = cfg().GOOGLE_CLIENT_ID || "";
    if (!clientId) {
      setMsg(t("googleClientMissing"));
      return { ok: false };
    }

    setMsg(t("googleSignInPending"));
    try {
      await loadGsiScript();
    } catch (_) {
      setMsg(t("googleSignInFail"));
      return { ok: false };
    }

    return new Promise((resolve) => {
      const tokenClient = window.google.accounts.oauth2.initTokenClient({
        client_id: clientId,
        scope: "openid email profile",
        callback: async (resp) => {
          if (!resp?.access_token) {
            setMsg(t("googleSignInFail"));
            resolve({ ok: false });
            return;
          }
          try {
            const r = await fetch("https://www.googleapis.com/oauth2/v3/userinfo", {
              headers: { Authorization: `Bearer ${resp.access_token}` },
            });
            const info = await r.json();
            const email = (info?.email || "").trim();
            const sub = info?.sub || "";
            persistGoogleSession(email, sub);
            Identity?.pullFromServer?.();
            Identity?.refreshAccountUi?.();
            Identity?.syncToServer?.(GpsTracker.loadTotalKm());
            if (email) {
              try {
                const vr = await fetch("/api/verify-payment.php", {
                  method: "POST",
                  headers: { "Content-Type": "application/json" },
                  body: JSON.stringify({ email }),
                });
                const data = await vr.json();
                if (data.paid || data.yearly) setYearly(email, untilFromApi(data.yearlyUntil));
                if (data.lifetime || data.adfree) setAdFree(email);
              } catch (_) {}
            }
            setMsg(email ? t("googleSignInOk", { email }) : t("googleSignInFail"));
            refreshAuthUi();
            refreshAdFreeUi();
            if (onAccessChange) onAccessChange();
            resolve({ ok: !!email && isGoogleSignedIn(), email, sub });
          } catch (_) {
            setMsg(t("googleSignInFail"));
            resolve({ ok: false });
          }
        },
        error_callback: (err) => {
          setMsg(
            err?.type === "popup_closed"
              ? t("googleSignInCancelled")
              : t("googleSignInFail")
          );
          resolve({ ok: false });
        },
      });
      tokenClient.requestAccessToken();
    });
  }

  function initAppleSignIn() {
    const handler = (e) => {
      e?.preventDefault?.();
      // iOS uygulamasında yerel Apple girişi, web'de Google girişi
      if (window.EtubuNative?.signInWithApple) signInWithApple();
      else signInWithGoogle();
    };
    [
      "appleSignBtn",
      "dockAppleSignBtn",
      "googleSignBtn",
      "dockGoogleSignBtn",
    ].forEach((id) => {
      document.getElementById(id)?.addEventListener("click", handler);
    });
  }

  function checkUrlReturn() {
    const params = new URLSearchParams(window.location.search);
    if (params.get("payment") === "success") {
      const email = params.get("email") || localStorage.getItem(STORAGE_EMAIL);
      const product = params.get("product");
      if (product === "lifetime" || product === "adfree") {
        setLifetime(email || "");
      } else if (product === "monthly" || product === "yearly" || product === "unlock") {
        setMonthly(email || "");
      } else if (email) {
        fetch("/api/verify-payment.php", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ email, token: params.get("token") }),
        })
          .then((r) => r.json())
          .then((d) => {
            if (d.lifetime || d.adfree) setLifetime(email);
            else if (d.paid || d.yearly || d.monthly) {
              setMonthly(email, untilFromApi(d.yearlyUntil || d.monthlyUntil));
            }
          });
      }
      history.replaceState({}, "", "/");
    }
  }

  function bindInviteUi() {
    const applyFrom = (inputId, statusId) => {
      const input = document.getElementById(inputId);
      const status = document.getElementById(statusId) || statusEl();
      const result = redeemInvite(input?.value);
      if (status) status.textContent = result.message;
      if (result.ok && input) input.value = "";
      return result;
    };

    document.getElementById("inviteSubmitBtn")?.addEventListener("click", () => {
      applyFrom("inviteCodeInput", "paywallStatus");
    });
    document.getElementById("inviteCodeInput")?.addEventListener("keydown", (e) => {
      if (e.key === "Enter") {
        e.preventDefault();
        applyFrom("inviteCodeInput", "paywallStatus");
      }
    });
    document.getElementById("dockInviteBtn")?.addEventListener("click", () => {
      applyFrom("dockInviteInput", "dockInviteStatus");
    });
    document.getElementById("dockInviteInput")?.addEventListener("keydown", (e) => {
      if (e.key === "Enter") {
        e.preventDefault();
        applyFrom("dockInviteInput", "dockInviteStatus");
      }
    });
  }

  function init(callbacks = {}) {
    onUnlocked = callbacks.onUnlocked;
    onAdFree = callbacks.onAdFree;
    onAccessChange = callbacks.onAccessChange;
    CarBrowser?.bootstrapFromUrl?.();
    const totalKm = GpsTracker.loadTotalKm();
    lastTrialOpen = true;
    updateTrialPill(totalKm);
    refreshAdFreeUi();
    hide();

    document
      .getElementById("payBtn")
      ?.addEventListener("click", () => startPayment("monthly"));
    document
      .getElementById("adFreeBtn")
      ?.addEventListener("click", () => startPayment("lifetime"));
    document
      .getElementById("premiumBtn")
      ?.addEventListener("click", () => show(GpsTracker.loadTotalKm()));
    document
      .getElementById("dockMonthlyBtn")
      ?.addEventListener("click", () => startPayment("monthly"));
    document
      .getElementById("dockLifetimeBtn")
      ?.addEventListener("click", () => startPayment("lifetime"));
    document.getElementById("restoreBtn")?.addEventListener("click", restoreAccess);
    document.getElementById("continueFreeBtn")?.addEventListener("click", dismissUpsell);
    document.getElementById("paywallCloseBtn")?.addEventListener("click", hide);
    document.getElementById("upgradeBtn")?.addEventListener("click", () => {
      show(GpsTracker.loadTotalKm());
    });
    bindInviteUi();
    initAppleSignIn();
    document.getElementById("googleSignOutBtn")?.addEventListener("click", signOutGoogle);
    checkUrlReturn();

    if (typeof I18n !== "undefined") {
      I18n.init(() => {
        updateTrialPill(GpsTracker.loadTotalKm());
        refreshAdFreeUi();
      });
    }
  }

  return {
    get FREE_KM() {
      return FREE_KM();
    },
    get PRICE_TRY() {
      return PRICE_YEARLY();
    },
    get PRICE_YEARLY() {
      return PRICE_YEARLY();
    },
    get PRICE_ADFREE() {
      return PRICE_ADFREE();
    },
    init,
    checkAndMaybeBlock,
    shouldBlock,
    isPaid,
    isAdFree,
    hasInvite,
    hasFullAccess,
    hasCatalogAccess,
    isInTrial,
    hasYearly,
    isEphemeral,
    hasMusicStreaming: () => {
      if (typeof MusicHub !== "undefined") return MusicHub.hasStreamingAccess();
      return hasYearly() || isAdFree() || isInTrial();
    },
    redeemInvite,
    signInWithApple,
    signInWithGoogle,
    signOutGoogle,
    isGoogleSignedIn,
    canPurchasePremium,
    setPaid,
    setYearly,
    setMonthly,
    setLifetime,
    setAdFree,
    dismissUpsell,
    updateTrialPill,
    refreshAdFreeUi,
    refreshAuthUi,
    show,
    hide,
  };
})();
