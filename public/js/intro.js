/**
 * Açılış turu — yalnızca web (Tesla tarayıcısı dahil).
 * iOS native cluster / Capacitor uygulamasında gösterilmez.
 */
const SiteIntro = (() => {
  const SEEN_KEY = "etubu_intro_seen";
  const SLIDE_COUNT = 4;
  let index = 0;
  let startX = 0;
  let bound = false;

  function t(key) {
    return typeof I18n !== "undefined" ? I18n.t(key) : key;
  }

  function isNativeApp() {
    try {
      if (window.__ETUBU_NATIVE_CLUSTER__) return true;
      if (window.Capacitor?.isNativePlatform?.()) return true;
    } catch (_) {}
    return false;
  }

  function shouldSkipAuto() {
    try {
      if (isNativeApp()) return true;
      const q = new URLSearchParams(window.location.search);
      if (q.get("skipIntro") === "1" || q.get("intro") === "0") return true;
    } catch (_) {}
    return false;
  }

  function hasSeen() {
    try {
      if (sessionStorage.getItem(SEEN_KEY) === "1") return true;
    } catch (_) {}
    const persist = typeof Consent === "undefined" || Consent.allows("preferences");
    if (!persist) return false;
    try {
      if (localStorage.getItem(SEEN_KEY) === "1") return true;
    } catch (_) {}
    try {
      return document.cookie.split(";").some((c) => c.trim().startsWith(SEEN_KEY + "=1"));
    } catch (_) {}
    return false;
  }

  function markSeen() {
    try {
      sessionStorage.setItem(SEEN_KEY, "1");
    } catch (_) {}
    const persist = typeof Consent === "undefined" || Consent.allows("preferences");
    if (!persist) return;
    try {
      localStorage.setItem(SEEN_KEY, "1");
    } catch (_) {}
    try {
      document.cookie = SEEN_KEY + "=1;max-age=31536000;path=/;SameSite=Lax";
    } catch (_) {}
  }

  function el() {
    return document.getElementById("siteIntro");
  }

  function isOpen() {
    return document.documentElement.classList.contains("etubu-intro");
  }

  function setSlide(i) {
    index = ((i % SLIDE_COUNT) + SLIDE_COUNT) % SLIDE_COUNT;
    const root = el();
    if (!root) return;
    root.querySelectorAll(".intro-slide").forEach((slide, n) => {
      slide.classList.toggle("is-active", n === index);
      slide.toggleAttribute("hidden", n !== index);
    });
    root.querySelectorAll(".intro-dot").forEach((dot, n) => {
      dot.classList.toggle("is-active", n === index);
      dot.setAttribute("aria-current", n === index ? "true" : "false");
    });
    const nextBtn = root.querySelector("#introNextBtn");
    const backBtn = root.querySelector("#introBackBtn");
    if (backBtn) backBtn.hidden = index === 0;
    if (nextBtn) {
      nextBtn.textContent = index === SLIDE_COUNT - 1 ? t("introStart") : t("introNext");
    }
    const kicker = root.querySelector("#introStepLabel");
    if (kicker) kicker.textContent = `${index + 1} / ${SLIDE_COUNT}`;
  }

  function close() {
    markSeen();
    document.documentElement.classList.remove("etubu-intro");
    document.body.classList.remove("intro-open");
    const root = el();
    if (!root) return;
    root.classList.add("is-leaving");
    root.setAttribute("aria-hidden", "true");
    setTimeout(() => {
      root.hidden = true;
      root.classList.remove("is-leaving");
    }, 280);
  }

  function open() {
    const root = el();
    if (!root) return;
    index = 0;
    root.hidden = false;
    root.setAttribute("aria-hidden", "false");
    document.documentElement.classList.add("etubu-intro");
    document.body.classList.add("intro-open");
    setSlide(0);
    typeof Ads !== "undefined" && Ads.renderIntroSlots?.();
  }

  function onKey(e) {
    if (!isOpen()) return;
    if (e.key === "Escape") {
      e.preventDefault();
      close();
    } else if (e.key === "ArrowRight" || e.key === "Enter") {
      e.preventDefault();
      if (index >= SLIDE_COUNT - 1) close();
      else setSlide(index + 1);
    } else if (e.key === "ArrowLeft") {
      e.preventDefault();
      setSlide(index - 1);
    }
  }

  function bind() {
    if (bound) return;
    bound = true;
    const root = el();
    if (!root) return;

    root.querySelector("#introSkipBtn")?.addEventListener("click", close);
    root.querySelector("#introStartSkipBtn")?.addEventListener("click", close);
    root.querySelector("#introNextBtn")?.addEventListener("click", () => {
      if (index >= SLIDE_COUNT - 1) close();
      else setSlide(index + 1);
    });
    root.querySelector("#introBackBtn")?.addEventListener("click", () => setSlide(index - 1));
    root.querySelectorAll(".intro-dot").forEach((dot) => {
      dot.addEventListener("click", () => {
        const n = parseInt(dot.getAttribute("data-intro-dot"), 10);
        if (Number.isFinite(n)) setSlide(n);
      });
    });

    const stage = root.querySelector(".intro-stage");
    stage?.addEventListener("pointerdown", (e) => {
      startX = e.clientX;
    });
    stage?.addEventListener("pointerup", (e) => {
      const dx = e.clientX - startX;
      if (dx < -48) {
        if (index >= SLIDE_COUNT - 1) close();
        else setSlide(index + 1);
      } else if (dx > 48) setSlide(index - 1);
    });

    document.addEventListener("keydown", onKey);
    document.getElementById("introReopenBtn")?.addEventListener("click", (e) => {
      e.preventDefault();
      open();
    });
  }

  function hideShell() {
    document.documentElement.classList.remove("etubu-intro");
    document.body.classList.remove("intro-open");
    const root = el();
    if (root) {
      root.hidden = true;
      root.setAttribute("aria-hidden", "true");
    }
  }

  function init() {
    bind();
    if (shouldSkipAuto()) {
      hideShell();
      return;
    }
    if (typeof Consent !== "undefined" && !Consent.hasChoice()) {
      hideShell();
      Consent.onChange(() => {
        if (shouldSkipAuto() || hasSeen() || isOpen()) return;
        open();
      });
      return;
    }
    if (hasSeen()) {
      hideShell();
      return;
    }
    open();
  }

  return { init, open, close };
})();
