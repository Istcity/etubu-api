/**
 * Banner reklamlar — web: Yandex RTB (+ isteğe bağlı AdSense)
 * Normal: üst / sağ / alt (orta)
 * Tam ekran (drive-focus): üst + sağ + sol, ~2 dk’da bir en fazla 10 sn pulse
 */
const Ads = (() => {
  const PULSE_INTERVAL_MS = 2 * 60 * 1000; // 2 dk
  const PULSE_RAILS = [".ad-rail--top", ".ad-rail--right"];

  let pulseTimer = null;
  let pulseHideTimer = null;
  let driveFocus = false;
  let rendered = false;

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
    s.onerror = () => {
      const s2 = document.createElement("script");
      s2.async = true;
      s2.src = "https://yandex.com/ads/system/context.js";
      document.head.appendChild(s2);
    };
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

  /** Yandex RTB — blockId + benzersiz renderTo (yenilemede id çakışmasın) */
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

    const renderTo = `yandex_rtb_${blockId}_${containerId}_${Date.now().toString(36)}`;
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

  function canShowAds() {
    if (typeof Paywall !== "undefined" && Paywall.isAdFree()) return false;
    const cfg = window.ETUBU_CONFIG || {};
    if (cfg.ADS_ENABLED === false) return false;
    try {
      if (window.__ETUBU_NATIVE_CLUSTER__ || window.Capacitor?.isNativePlatform?.()) {
        return false;
      }
    } catch (_) {}
    return true;
  }

  function setRailsVisible(visible) {
    document.body.classList.toggle("ads-hidden", !visible);
    document.querySelectorAll(".ad-rail").forEach((el) => {
      el.hidden = !visible;
    });
  }

  function hideAll() {
    stopPulse();
    document.body.classList.remove("ads-ready", "ads-pulse");
    setRailsVisible(false);
    document.querySelectorAll(".intro-ad").forEach((el) => {
      el.hidden = true;
    });
    if (window.EtubuNative?.hideAds) window.EtubuNative.hideAds();
  }

  function showRails() {
    if (!canShowAds()) return;
    document.body.classList.remove("ads-hidden");
    document.body.classList.add("ads-ready");
    setRailsVisible(true);
    document.querySelectorAll(".intro-ad").forEach((el) => {
      el.hidden = false;
    });
    const leftRail = document.querySelector(".ad-rail--left");
    if (leftRail) leftRail.hidden = true;
    if (!rendered) {
      rendered = true;
      renderMainSlots();
    }
    if (window.EtubuNative?.showBannerAds) window.EtubuNative.showBannerAds();
  }

  function renderMainSlots() {
    const cfg = window.ETUBU_CONFIG || {};
    const useYandex =
      cfg.YANDEX_RTB_ENABLED !== false &&
      (cfg.YANDEX_RTB_BLOCK_TOP ||
        cfg.YANDEX_RTB_BLOCK_MIDDLE ||
        cfg.YANDEX_RTB_BLOCK_RIGHT ||
        cfg.YANDEX_RTB_BLOCK_LEFT);

    if (useYandex) {
      ensureYandexLoader();
      renderYandexSlot("adTopInner", cfg.YANDEX_RTB_BLOCK_TOP);
      renderYandexSlot("adMiddleInner", cfg.YANDEX_RTB_BLOCK_MIDDLE);
      renderYandexSlot("adRightInner", cfg.YANDEX_RTB_BLOCK_RIGHT);
      renderYandexSlot(
        "adLeftInner",
        cfg.YANDEX_RTB_BLOCK_LEFT || cfg.YANDEX_RTB_BLOCK_RIGHT || cfg.YANDEX_RTB_BLOCK_TOP
      );
      return;
    }

    if (!cfg.ADSENSE_CLIENT) return;
    const c = cfg.ADSENSE_CLIENT;
    renderAdSenseSlot("adTopInner", c, cfg.ADSENSE_SLOT_TOP, "horizontal");
    renderAdSenseSlot("adRightInner", c, cfg.ADSENSE_SLOT_RIGHT, "vertical");
    renderAdSenseSlot("adMiddleInner", c, cfg.ADSENSE_SLOT_MIDDLE, "horizontal");
    renderAdSenseSlot(
      "adLeftInner",
      c,
      cfg.ADSENSE_SLOT_LEFT || cfg.ADSENSE_SLOT_RIGHT,
      "vertical"
    );
  }

  function endPulseShow() {
    if (pulseHideTimer) {
      clearTimeout(pulseHideTimer);
      pulseHideTimer = null;
    }
    document.body.classList.remove("ads-pulse");
    const leftRail = document.querySelector(".ad-rail--left");
    if (leftRail) leftRail.hidden = true;
    // drive-focus’ta CSS zaten .ad-rail’i gizler; sınıfı bırakmak yeterli
  }

  function runPulseShow() {
    if (!canShowAds() || !driveFocus) return;
    if (document.documentElement.classList.contains("etubu-intro")) return;
    if (document.getElementById("etubuConsent") && !document.getElementById("etubuConsent").hidden) {
      return;
    }

    document.body.classList.add("ads-pulse", "ads-ready");
    PULSE_RAILS.forEach((sel) => {
      const el = document.querySelector(sel);
      if (el) el.hidden = false;
    });
    // Orta şerit pulse’ta yok
    const mid = document.querySelector(".ad-rail--middle");
    if (mid) mid.hidden = true;

    try {
      renderMainSlots();
    } catch (e) {
      console.warn("Ad pulse render", e);
    }

    if (pulseHideTimer) clearTimeout(pulseHideTimer);
    pulseHideTimer = setTimeout(endPulseShow, PULSE_SHOW_MS);
  }

  function stopPulse() {
    if (pulseTimer) {
      clearInterval(pulseTimer);
      pulseTimer = null;
    }
    endPulseShow();
  }

  function startPulse() {
    stopPulse();
    if (!canShowAds() || !driveFocus) return;
    // İlk gösterim ~45 sn sonra, sonra her 2 dk
    pulseTimer = setInterval(runPulseShow, PULSE_INTERVAL_MS);
    setTimeout(() => {
      if (driveFocus && canShowAds()) runPulseShow();
    }, 45 * 1000);
  }

  /** Panel kapalı / tam ekran — pulse döngüsünü aç/kapat */
  function setDriveFocus(on) {
    driveFocus = !!on;
    if (driveFocus) {
      if (canShowAds()) startPulse();
      else stopPulse();
    } else {
      stopPulse();
      if (canShowAds()) {
        showRails();
        if (!rendered) {
          rendered = true;
          renderMainSlots();
        }
      }
    }
  }

  async function init() {
    if (!canShowAds()) {
      hideAll();
      if (typeof Consent !== "undefined" && !init._consentBound) {
        init._consentBound = true;
        Consent.onChange(() => {
          if (Consent.allows("marketing")) init();
          else hideAll();
        });
      }
      return;
    }

    if (typeof Consent !== "undefined" && !init._consentBound) {
      init._consentBound = true;
      Consent.onChange(() => {
        if (Consent.allows("marketing")) init();
        else hideAll();
      });
    }

    const cfg = window.ETUBU_CONFIG || {};

    if (driveFocus) {
      document.body.classList.add("ads-ready");
      startPulse();
      return;
    }

    showRails();

    const leftRail = document.querySelector(".ad-rail--left");
    if (leftRail) leftRail.hidden = true;

    try {
      if (cfg.YANDEX_RTB_ENABLED !== false) {
        ensureYandexLoader();
      } else if (cfg.ADSENSE_CLIENT) {
        await loadAdSenseScript(cfg.ADSENSE_CLIENT);
      }
      renderMainSlots();
      rendered = true;
      renderIntroSlots();
    } catch (e) {
      console.warn("Reklam yüklenemedi", e);
    }
  }

  function renderIntroSlots() {
    if (!canShowAds()) return;
    const cfg = window.ETUBU_CONFIG || {};
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

  return {
    init,
    hideAll,
    showRails,
    renderIntroSlots,
    setDriveFocus,
    /** test / debug */
    _pulseNow: runPulseShow,
  };
})();
window.Ads = Ads;
