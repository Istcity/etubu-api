/**
 * Paddle.js overlay checkout (sandbox / production)
 * customData: { userId, planType: "monthly" | "lifetime" }
 */
const PaddleCheckout = (() => {
  let ready = false;
  let initPromise = null;
  let lastError = "";

  function cfg() {
    return window.ETUBU_CONFIG || {};
  }

  function t(key, vars) {
    return typeof I18n !== "undefined" ? I18n.t(key, vars) : key;
  }

  function setStatus(msg) {
    lastError = msg || "";
    const el = document.getElementById("paywallStatus");
    if (el && msg) el.textContent = msg;
  }

  /**
   * Kullanıcı ID bağlama noktası:
   * 1) Identity.getDeviceId() — misafir cihaz UUID
   * 2) Identity.getEmail() — Google/Apple giriş e-postası
   * 3) Fallback: test_user_<random>
   */
  function resolveUserId() {
    try {
      const email =
        typeof Identity !== "undefined" ? Identity.getEmail?.() : "";
      if (email) return email;
      if (typeof Identity !== "undefined" && Identity.getDeviceId) {
        return Identity.getDeviceId();
      }
    } catch (_) {}
    const key = "etubu_test_user_id";
    try {
      let id = localStorage.getItem(key);
      if (!id) {
        id = `test_user_${Date.now().toString(36)}`;
        localStorage.setItem(key, id);
      }
      return id;
    } catch (_) {
      return `test_user_${Date.now()}`;
    }
  }

  function loadScript() {
    return new Promise((resolve, reject) => {
      if (window.Paddle) {
        resolve(window.Paddle);
        return;
      }
      const existing = document.querySelector("script[data-paddle-js]");
      if (existing) {
        existing.addEventListener("load", () => resolve(window.Paddle));
        existing.addEventListener("error", () =>
          reject(new Error("Paddle.js load failed"))
        );
        return;
      }
      const s = document.createElement("script");
      s.src = "https://cdn.paddle.com/paddle/v2/paddle.js";
      s.async = true;
      s.dataset.paddleJs = "1";
      s.onload = () => resolve(window.Paddle);
      s.onerror = () => reject(new Error("Paddle.js load failed"));
      document.head.appendChild(s);
    });
  }

  function describeEventError(event) {
    const data = event?.data || {};
    const err = data.error || data;
    const code = err.code || err.error_code || data.code || "";
    const detail =
      err.detail ||
      err.message ||
      data.message ||
      event?.name ||
      "Checkout error";
    return code ? `${detail} (${code})` : String(detail);
  }

  async function ensureInit() {
    if (ready && window.Paddle) return window.Paddle;
    if (initPromise) return initPromise;

    initPromise = (async () => {
      const token = cfg().PADDLE_CLIENT_TOKEN || "";
      const env = cfg().PADDLE_ENV === "production" ? "production" : "sandbox";
      if (!token || token.startsWith("BURAYA_")) {
        throw new Error(t("paymentNotConfigured"));
      }
      const Paddle = await loadScript();
      if (env === "sandbox") {
        Paddle.Environment.set("sandbox");
      }
      Paddle.Initialize({
        token,
        eventCallback(event) {
          const name = event?.name || "";
          if (name === "checkout.error" || name === "checkout.warning") {
            const msg = describeEventError(event);
            console.error("[Paddle]", name, event?.data || event);
            setStatus(msg);
            return;
          }
          if (name === "checkout.completed") {
            const plan =
              event?.data?.custom_data?.planType ||
              event?.data?.customData?.planType;
            const email =
              event?.data?.customer?.email ||
              (typeof Identity !== "undefined" ? Identity.getEmail?.() : "") ||
              "";
            if (typeof Paywall !== "undefined") {
              if (plan === "lifetime") Paywall.setLifetime?.(email);
              else if (plan === "monthly") Paywall.setMonthly?.(email);
            }
          }
        },
      });
      ready = true;
      return Paddle;
    })();

    try {
      return await initPromise;
    } catch (e) {
      initPromise = null;
      throw e;
    }
  }

  /**
   * @param {"monthly"|"lifetime"} planType
   */
  async function openCheckout(planType) {
    const priceId =
      planType === "lifetime"
        ? cfg().PADDLE_PRICE_LIFETIME
        : cfg().PADDLE_PRICE_MONTHLY;

    if (!priceId || String(priceId).startsWith("BURAYA_")) {
      throw new Error(t("paymentNotConfigured"));
    }

    const Paddle = await ensureInit();
    const userId = resolveUserId();
    const email =
      typeof Identity !== "undefined" ? Identity.getEmail?.() : "";

    const openOpts = {
      items: [{ priceId, quantity: 1 }],
      customData: {
        userId: String(userId),
        planType: planType === "lifetime" ? "lifetime" : "monthly",
      },
      settings: {
        displayMode: "overlay",
        theme: "dark",
        locale: (typeof I18n !== "undefined" && I18n.lang) || "tr",
        successUrl: `${cfg().SITE_URL || "https://etubu.com"}/?payment=success&product=${planType}`,
      },
    };

    if (email) openOpts.customer = { email };

    lastError = "";
    try {
      Paddle.Checkout.open(openOpts);
    } catch (e) {
      const msg = e?.message || String(e);
      setStatus(msg);
      throw e;
    }
  }

  return {
    openCheckout,
    resolveUserId,
    ensureInit,
    getLastError: () => lastError,
  };
})();
