/**
 * ETUBU WarnVoice — ElevenLabs modular clips (assets/audio/warn/).
 * Prefers composed MP3 over speechSynthesis for TR alerts.
 */
const WarnVoice = (() => {
  const BASE = "assets/audio/warn/";
  const MANIFEST_URL = `${BASE}manifest.json?v=20260801a`;

  /** Available distance clip meters / km */
  const DIST_M = [
    50, 100, 150, 200, 250, 300, 350, 400, 500, 550, 600, 650, 700, 750, 800, 850, 900, 950,
  ];
  const DIST_KM = [1, 2, 3, 4, 5, 10];
  const LIMITS = [50, 70, 82, 90, 100, 110, 120, 130, 140];

  let manifest = null;
  let loadPromise = null;
  /** @type {Map<string, AudioBuffer>} */
  const buffers = new Map();
  let audioCtx = null;
  let playGen = 0;
  let lastKey = "";
  let lastAt = 0;

  function ttsEnabled() {
    try {
      const v = localStorage.getItem("etubu_radar_tts");
      if (v === "0" || v === "false") return false;
    } catch (_) {}
    return true;
  }

  function alertVolume() {
    try {
      const v = Number(localStorage.getItem("etubu_alert_volume"));
      if (Number.isFinite(v) && v > 0) return Math.min(1, Math.max(0.15, v));
    } catch (_) {}
    return 0.9;
  }

  function isTurkish() {
    try {
      if (typeof I18n !== "undefined" && I18n.lang) {
        return String(I18n.lang).toLowerCase().startsWith("tr");
      }
    } catch (_) {}
    return true;
  }

  function ensureCtx() {
    const Ctx = window.AudioContext || window.webkitAudioContext;
    if (!Ctx) return null;
    if (!audioCtx) audioCtx = new Ctx();
    if (audioCtx.state === "suspended") audioCtx.resume().catch(() => {});
    return audioCtx;
  }

  async function loadManifest() {
    if (manifest) return manifest;
    if (loadPromise) return loadPromise;
    loadPromise = fetch(MANIFEST_URL, { cache: "force-cache" })
      .then((r) => (r.ok ? r.json() : null))
      .then((j) => {
        manifest = j && j.clips ? j : null;
        return manifest;
      })
      .catch(() => {
        manifest = null;
        return null;
      });
    return loadPromise;
  }

  async function loadBuffer(key) {
    if (buffers.has(key)) return buffers.get(key);
    const ctx = ensureCtx();
    if (!ctx || !manifest?.clips?.[key]) return null;
    const file = manifest.clips[key].file;
    try {
      const res = await fetch(`${BASE}${file}`, { cache: "force-cache" });
      if (!res.ok) return null;
      const raw = await res.arrayBuffer();
      const buf = await ctx.decodeAudioData(raw.slice(0));
      buffers.set(key, buf);
      return buf;
    } catch (_) {
      return null;
    }
  }

  function nearestDistMeters(m) {
    const n = Math.max(0, Number(m) || 0);
    if (n >= 1000) {
      const km = n >= 2000 ? Math.round(n / 1000) : 1;
      return distKmKey(km);
    }
    let best = DIST_M[0];
    let bestD = Math.abs(n - best);
    for (const d of DIST_M) {
      const dd = Math.abs(n - d);
      if (dd < bestD) {
        best = d;
        bestD = dd;
      }
    }
    return `d_${best}m`;
  }

  function distKmKey(km) {
    const k = Math.max(1, Math.round(Number(km) || 1));
    let best = DIST_KM[0];
    let bestD = Math.abs(k - best);
    for (const d of DIST_KM) {
      const dd = Math.abs(k - d);
      if (dd < bestD) {
        best = d;
        bestD = dd;
      }
    }
    return `d_${best}km`;
  }

  function limitKey(n) {
    const v = Math.round(Number(n) || 0);
    if (!v) return null;
    let best = LIMITS[0];
    let bestD = Math.abs(v - best);
    for (const d of LIMITS) {
      const dd = Math.abs(v - d);
      if (dd < bestD) {
        best = d;
        bestD = dd;
      }
    }
    return `n${best}`;
  }

  function wordNumKey(n) {
    const map = {
      1: "w_bir",
      2: "w_iki",
      3: "w_uc",
      4: "w_dort",
      5: "w_bes",
      6: "w_alti",
      7: "w_yedi",
      8: "w_sekiz",
      9: "w_dokuz",
    };
    return map[Math.round(Number(n))] || null;
  }

  /** Parse TR / mixed HUD phrases → clip keys */
  function composeKeys(text) {
    const raw = String(text || "").trim();
    if (!raw) return null;
    let s = raw
      .toLocaleLowerCase("tr-TR")
      .replace(/[.,;:!?"']/g, " ")
      .replace(/\s+/g, " ")
      .trim();

    // normalize digits-with-units early
    s = s
      .replace(/\b(\d+)\s*km\b/gi, " $1 kilometre ")
      .replace(/\b(\d+)\s*m\b/gi, " $1 metre ")
      .replace(/\s+/g, " ")
      .trim();

    if (s === "yavaşla" || s === "yavasla") return ["yavasla"];
    if (s === "koridor bitti") return ["koridor_bitti"];

    // Rota hazır…
    if (s.startsWith("rota hazır") || s.startsWith("rota hazir")) {
      const keys = ["rota_hazir"];
      const m = s.match(/\b(bir|iki|üç|uc|dört|dort|beş|bes|altı|alti|yedi|sekiz|dokuz|on|\d+)\b/);
      if (m) {
        const w = m[1];
        const numMap = {
          bir: 1,
          iki: 2,
          üç: 3,
          uc: 3,
          dört: 4,
          dort: 4,
          beş: 5,
          bes: 5,
          altı: 6,
          alti: 6,
          yedi: 7,
          sekiz: 8,
          dokuz: 9,
          on: 10,
        };
        const n = numMap[w] ?? parseInt(w, 10);
        if (n === 10) {
          /* no w_on clip — skip count or use d_10km awkwardly; skip */
        } else {
          const wk = wordNumKey(n);
          if (wk) keys.push(wk);
        }
      }
      keys.push("guzergahta_kritik_nokta_var");
      return keys;
    }

    const keys = [];

    // Prefix kind
    if (s.startsWith("radar yakın") || s.startsWith("radar yakin")) {
      keys.push("radar_yakin");
      s = s.replace(/^radar\s+yak[iı]n\s*/, "");
    } else if (s.startsWith("koridor giriş") || s.startsWith("koridor giris")) {
      keys.push("koridor_giris");
      s = s.replace(/^koridor\s+giri[sş]\s*/, "");
    } else if (s.startsWith("hız koridoru") || s.startsWith("hiz koridoru")) {
      keys.push("hiz_koridoru");
      s = s.replace(/^h[iı]z\s+koridoru\s*/, "");
    } else if (s.startsWith("şarj istasyonu") || s.startsWith("sarj istasyonu")) {
      keys.push("sarj_istasyonu");
      s = s.replace(/^[sş]arj\s+istasyonu\s*/, "");
    } else if (s.startsWith("şiddetli hava") || s.startsWith("siddetli hava")) {
      keys.push("siddetli_hava");
      s = s.replace(/^[sş]iddetli\s+hava\s*/, "");
    } else if (s.startsWith("hava olayı") || s.startsWith("hava olayi")) {
      keys.push("hava_olayi");
      s = s.replace(/^hava\s+olay[iı]\s*/, "");
    } else if (s.startsWith("kontrol")) {
      keys.push("kontrol");
      s = s.replace(/^kontrol\s*/, "");
    } else if (s.startsWith("koridor")) {
      keys.push("koridor");
      s = s.replace(/^koridor\s*/, "");
    } else if (s.startsWith("radar")) {
      keys.push("radar");
      s = s.replace(/^radar\s*/, "");
    } else {
      return null;
    }

    s = s.trim();
    if (!s && keys.length) return keys;

    // Optional: hız sınır / hız sınırı + number
    const limMatch = s.match(/h[iı]z\s+s[iı]n[iı]r[iı]?\s*(\d{2,3})/);
    const limOnly = s.match(/^h[iı]z\s+s[iı]n[iı]r[iı]?\s*(\d{2,3})$/);
    let limit = null;
    if (limMatch) {
      limit = parseInt(limMatch[1], 10);
      s = s.replace(limMatch[0], " ").replace(/\s+/g, " ").trim();
    }

    // Distance: numeric or TR words
    let distKey = null;
    const kmNum = s.match(/\b(\d+(?:[.,]\d+)?)\s*kilometre\b/);
    const mNum = s.match(/\b(\d+)\s*metre\b/);
    if (kmNum) {
      distKey = distKmKey(parseFloat(kmNum[1].replace(",", ".")));
    } else if (mNum) {
      distKey = nearestDistMeters(parseInt(mNum[1], 10));
    } else {
      // word distances used by RadarAlert.speechDist
      const wordKm = s.match(
        /\b(bir|iki|üç|uc|dört|dort|beş|bes|altı|alti|yedi|sekiz|dokuz|on)\s+kilometre\b/
      );
      if (wordKm) {
        const map = {
          bir: 1,
          iki: 2,
          üç: 3,
          uc: 3,
          dört: 4,
          dort: 4,
          beş: 5,
          bes: 5,
          altı: 6,
          alti: 6,
          yedi: 7,
          sekiz: 8,
          dokuz: 9,
          on: 10,
        };
        distKey = distKmKey(map[wordKm[1]] || 1);
      } else {
        // "elli metre" / "üç yüz elli metre" etc.
        const wordM = parseTurkishMeters(s);
        if (wordM != null) distKey = nearestDistMeters(wordM);
      }
    }

    if (distKey) keys.push(distKey);
    if (limit != null) {
      keys.push("hiz_siniri");
      const lk = limitKey(limit);
      if (lk) keys.push(lk);
    } else if (limOnly) {
      keys.push("hiz_siniri");
      const lk = limitKey(parseInt(limOnly[1], 10));
      if (lk) keys.push(lk);
    }

    // koridor giriş with only limit (no distance)
    if (keys.length >= 1) return keys;
    return null;
  }

  function parseTurkishMeters(s) {
    // strip leftover words
    let t = s
      .replace(/h[iı]z\s+s[iı]n[iı]r[iı]?\s*\d*/g, "")
      .replace(/\bmetre\b/g, "")
      .trim();
    if (!t) return null;

    const ones = {
      bir: 1,
      iki: 2,
      üç: 3,
      uc: 3,
      dört: 4,
      dort: 4,
      beş: 5,
      bes: 5,
      altı: 6,
      alti: 6,
      yedi: 7,
      sekiz: 8,
      dokuz: 9,
    };
    const tens = {
      on: 10,
      yirmi: 20,
      otuz: 30,
      kırk: 40,
      kirk: 40,
      elli: 50,
      altmış: 60,
      altmis: 60,
      yetmiş: 70,
      yetmis: 70,
      seksen: 80,
      doksan: 90,
    };

    if (t === "yüz" || t === "yuz") return 100;
    if (t === "elli") return 50;

    let total = 0;
    // N yüz [elli]
    const yuz = t.match(/^(bir\s+)?(yüz|yuz)\b(.*)$/);
    const nYuz = t.match(
      /^(iki|üç|uc|dört|dort|beş|bes|altı|alti|yedi|sekiz|dokuz)\s+(yüz|yuz)\b(.*)$/
    );
    if (nYuz) {
      total += (ones[nYuz[1]] || 0) * 100;
      t = nYuz[3].trim();
    } else if (yuz) {
      total += 100;
      t = yuz[3].trim();
    }

    const parts = t.split(/\s+/).filter(Boolean);
    for (const p of parts) {
      if (tens[p] != null) total += tens[p];
      else if (ones[p] != null) total += ones[p];
    }
    return total > 0 ? total : null;
  }

  async function playKeys(keys, opts = {}) {
    if (!keys || !keys.length) return false;
    if (!ttsEnabled()) return false;
    await loadManifest();
    if (!manifest) return false;
    const ctx = ensureCtx();
    if (!ctx) return false;

    const gen = ++playGen;
    const vol = alertVolume() * (opts.urgent ? 1 : 0.92);
    const gap = opts.urgent ? 0.05 : 0.08;

    // Prefetch
    const bufs = [];
    for (const k of keys) {
      const b = await loadBuffer(k);
      if (!b) return false;
      bufs.push(b);
    }
    if (gen !== playGen) return false;

    let t = ctx.currentTime + 0.02;
    for (const buf of bufs) {
      if (gen !== playGen) return false;
      const src = ctx.createBufferSource();
      const g = ctx.createGain();
      src.buffer = buf;
      g.gain.value = vol;
      src.connect(g);
      g.connect(ctx.destination);
      src.start(t);
      t += buf.duration + gap;
    }
    return true;
  }

  /**
   * @param {string} text
   * @param {{ key?: string, urgent?: boolean, forceTts?: boolean }} [opts]
   * @returns {Promise<boolean>|boolean}
   */
  function speak(text, opts = {}) {
    if (opts.forceTts) return false;
    if (!ttsEnabled()) return false;
    if (!isTurkish()) return false;

    const msg = String(text || "").trim();
    if (!msg) return false;

    const key = opts.key || msg;
    const now = Date.now();
    const gap = opts.urgent ? 12000 : 26000;
    if (key === lastKey && now - lastAt < gap) return true; // consumed debounce
    lastKey = key;
    lastAt = now;

    const keys = composeKeys(msg);
    if (!keys || !keys.length) return false;

    // Cancel system TTS if any
    try {
      window.speechSynthesis?.cancel();
    } catch (_) {}

    playKeys(keys, opts).then((ok) => {
      if (!ok && opts.fallback !== false) fallbackTts(msg, opts);
    });
    return true;
  }

  function fallbackTts(msg, opts = {}) {
    try {
      const synth = window.speechSynthesis;
      if (!synth || typeof SpeechSynthesisUtterance === "undefined") return;
      synth.cancel();
      const u = new SpeechSynthesisUtterance(String(msg || ""));
      u.lang =
        (typeof I18n !== "undefined" && I18n.speechLocale?.()) || "tr-TR";
      u.rate = opts.urgent ? 1.05 : 1.0;
      u.volume = 1;
      synth.speak(u);
    } catch (_) {}
  }

  function prime() {
    ensureCtx();
    loadManifest().then(() => {
      // warm a few common clips
      ["yavasla", "radar", "radar_yakin", "koridor", "hiz_siniri", "d_300m", "d_1km"].forEach(
        (k) => loadBuffer(k)
      );
    });
    return true;
  }

  return {
    speak,
    playKeys,
    composeKeys,
    prime,
    nearestDistMeters,
    limitKey,
  };
})();

window.WarnVoice = WarnVoice;
