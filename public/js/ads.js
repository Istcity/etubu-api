/**
 * Banner reklamlar — web: Yandex RTB (+ isteğe bağlı AdSense)
 * Üst / sağ / alt (orta) şeritler — sol reklam yok
 * Native ad-free IAP varsa gizlenir; web’de her zaman gösterilir.
 */
const Ads = (() => {
  function loadAdSenseScript(client) {
    return new Promise((resolve, reject) => {
      if (document.querySelector(`script[data-ad-client="${client}"]`)) {
        resolve();
        return;
      }
      const s = document.createElement("script");
      s.async = true;
      s.src = `https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=${client}`;
      s.crossOrigin = "anonymous";
      s.dataset.adClient = client;
      s.onload = resolve;
      s.onerror = reject;
      document.head.appendChild(s);
    });
  }

  function ensureYandexLoader() {
    window.yaContextCb = window.yaContextCb || [];
    if (
      document.querySelector('script[data-yandex-rtb="1"]') ||
      document.querySelector('script[src*="yandex.ru/ads/system/context.js"]') ||
      document.querySelector('script[src*="yandex.com/ads/system/context.js"]')
    ) {
      return;
    }
    const s = document.createElement("script");
    s.async = true;
    s.src = "https://yandex.ru/ads/system/context.js";
    s.dataset.yandexRtb = "1";
    document.head.appendChild(s);
  }

  function renderAdSenseSlot(containerId, client, slot, format = "horizontal") {
    const wrap = document.getElementById(containerId);
    if (!wrap || !client || !slot) {
      if (wrap) {
        wrap.innerHTML = "";
        const ph = document.createElement("div");
        ph.className = "ad-placeholder";
        ph.setAttribute("aria-hidden", "true");
        wrap.appendChild(ph);
      }
      return;
    }
    wrap.innerHTML = "";
    const ins = document.createElement("ins");
    ins.className = "adsbygoogle";
    ins.style.display = "block";
    ins.style.width = "100%";
    ins.style.height = "100%";
    ins.setAttribute("data-ad-client", client);
    ins.setAttribute("data-ad-slot", slot);
    ins.setAttribute("data-ad-format", format);
    if (format === "horizontal" || format === "auto") {
      ins.setAttribute("data-full-width-responsive", "true");
    }
    wrap.appendChild(ins);
    try {
      (window.adsbygoogle = window.adsbygoogle || []).push({});
    } catch (_) {}
  }

  /** Yandex RTB — blockId + benzersiz renderTo konteyneri */
  function renderYandexSlot(containerId, blockId) {
    const wrap = document.getElementById(containerId);
    if (!wrap) return false;
    if (!blockId) {
      wrap.innerHTML = "";
      const ph = document.createElement("div");
      ph.className = "ad-placeholder";
      ph.setAttribute("aria-hidden", "true");
      wrap.appendChild(ph);
      return false;
    }

    const renderTo = `yandex_rtb_${blockId}_${containerId}`;
    wrap.innerHTML = "";
    const box = document.createElement("div");
    box.id = renderTo;
    box.className = "yandex-rtb";
    box.style.width = "100%";
    box.style.height = "100%";
    wrap.appendChild(box);

    window.yaContextCb = window.yaContextCb || [];
    window.yaContextCb.push(() => {
      try {
        Ya.Context.AdvManager.render({
          blockId,
          renderTo,
        });
      } catch (e) {
        console.warn("Yandex RTB render hatası", containerId, e);
      }
    });
    return true;
  }

  function setRailsVisible(visible) {
    document.body.classList.toggle("ads-hidden", !visible);
    document.querySelectorAll(".ad-rail").forEach((el) => {
      el.hidden = !visible;
    });
  }

  function hideAll() {
    document.body.classList.remove("ads-ready");
    setRailsVisible(false);
    document.querySelectorAll(".intro-ad").forEach((el) => {
      el.hidden = true;
    });
    if (window.EtubuNative?.hideAds) window.EtubuNative.hideAds();
  }

  function showRails() {
    document.body.classList.add("ads-ready");
    setRailsVisible(true);
    document.querySelectorAll(".intro-ad").forEach((el) => {
      el.hidden = false;
    });
    if (window.EtubuNative?.showBannerAds) window.EtubuNative.showBannerAds();
  }

  async function init() {
    if (typeof Paywall !== "undefined" && Paywall.isAdFree()) {
      hideAll();
      return;
    }

    const cfg = window.ETUBU_CONFIG || {};
    if (!cfg.ADS_ENABLED) {
      setRailsVisible(false);
      return;
    }

    // Native cluster / Cap: AdMob is not wired — never show stub “ads” or call dead plugin.
    try {
      if (
        window.__ETUBU_NATIVE_CLUSTER__ ||
        window.Capacitor?.isNativePlatform?.()
      ) {
        hideAll();
        return;
      }
    } catch (_) {}

    if (typeof Consent !== "undefined") {
      if (!init._consentBound) {
        init._consentBound = true;
        Consent.onChange(() => {
          if (Consent.allows("marketing")) init();
          else hideAll();
        });
      }
      if (!Consent.hasChoice() || !Consent.allows("marketing")) {
        hideAll();
        return;
      }
    }

    showRails();

    // Sol rail her zaman kapalı
    const leftRail = document.querySelector(".ad-rail--left");
    if (leftRail) leftRail.hidden = true;

    const useYandex = cfg.YANDEX_RTB_ENABLED !== false && (
      cfg.YANDEX_RTB_BLOCK_TOP ||
      cfg.YANDEX_RTB_BLOCK_MIDDLE ||
      cfg.YANDEX_RTB_BLOCK_RIGHT ||
      cfg.YANDEX_RTB_BLOCK_LEFT ||
      cfg.YANDEX_RTB_BLOCK_BOTTOM
    );

    if (useYandex) {
      try {
        ensureYandexLoader();
        renderYandexSlot("adTopInner", cfg.YANDEX_RTB_BLOCK_TOP);
        renderYandexSlot("adMiddleInner", cfg.YANDEX_RTB_BLOCK_MIDDLE);
        renderYandexSlot("adRightInner", cfg.YANDEX_RTB_BLOCK_RIGHT);
        renderIntroSlots();
      } catch (e) {
        console.warn("Yandex RTB yüklenemedi", e);
      }
      return;
    }

    if (!cfg.ADSENSE_CLIENT) return;

    try {
      await loadAdSenseScript(cfg.ADSENSE_CLIENT);
      const c = cfg.ADSENSE_CLIENT;
      renderAdSenseSlot("adTopInner", c, cfg.ADSENSE_SLOT_TOP, "horizontal");
      renderAdSenseSlot("adRightInner", c, cfg.ADSENSE_SLOT_RIGHT, "vertical");
      renderAdSenseSlot("adMiddleInner", c, cfg.ADSENSE_SLOT_MIDDLE, "horizontal");
      renderIntroSlots();
    } catch (e) {
      console.warn("AdSense yüklenemedi", e);
    }
  }

  function renderIntroSlots() {
    if (typeof Paywall !== "undefined" && Paywall.isAdFree()) return;
    if (typeof Consent !== "undefined" && !Consent.allows("marketing")) return;
    const cfg = window.ETUBU_CONFIG || {};
    if (!cfg.ADS_ENABLED) return;
    const top = cfg.YANDEX_RTB_BLOCK_TOP || cfg.YANDEX_RTB_BLOCK_MIDDLE;
    const side = cfg.YANDEX_RTB_BLOCK_RIGHT || cfg.YANDEX_RTB_BLOCK_LEFT || top;
    const bottom = cfg.YANDEX_RTB_BLOCK_BOTTOM || cfg.YANDEX_RTB_BLOCK_MIDDLE || top;
    const left = cfg.YANDEX_RTB_BLOCK_LEFT || side;
    if (cfg.YANDEX_RTB_ENABLED !== false && top) {
      ensureYandexLoader();
      renderYandexSlot("adIntroTopInner", top);
      renderYandexSlot("adIntroBottomInner", bottom);
      renderYandexSlot("adIntroLeftInner", left);
      renderYandexSlot("adIntroRightInner", side);
      return;
    }
    if (cfg.ADSENSE_CLIENT) {
      const c = cfg.ADSENSE_CLIENT;
      renderAdSenseSlot("adIntroTopInner", c, cfg.ADSENSE_SLOT_TOP, "horizontal");
      renderAdSenseSlot("adIntroBottomInner", c, cfg.ADSENSE_SLOT_BOTTOM || cfg.ADSENSE_SLOT_MIDDLE, "horizontal");
      renderAdSenseSlot("adIntroLeftInner", c, cfg.ADSENSE_SLOT_LEFT || cfg.ADSENSE_SLOT_RIGHT, "vertical");
      renderAdSenseSlot("adIntroRightInner", c, cfg.ADSENSE_SLOT_RIGHT, "vertical");
    }
  }

  return { init, hideAll, showRails, renderIntroSlots };
})();
