/**
 * RadarYol / YolRadar tarzı uyarı motoru:
 * - Gidiş yönüne göre filtre
 * - 5 km / 2 km / 1 km / 300 m yaklaşma aşamaları
 * - Sabit radar + hız koridoru (giriş/çıkış + ortalama hız)
 * - OSM Overpass + Türkiye ana güzergah tohumları
 */
const RadarAlert = (() => {
  const FETCH_RADIUS_M = 12000;
  const REFETCH_DIST_M = 4500;
  const REFETCH_AGE_MS = 10 * 60 * 1000;
  const AHEAD_MAX_M = 5500;
  const HEADING_TOLERANCE = 48;
  const BEHIND_IGNORE_M = 180;
  const STAGES = [
    { max: 300, key: "critical" },
    { max: 1000, key: "near" },
    { max: 2000, key: "mid" },
    { max: 5000, key: "far" },
  ];
  const OVERPASS_URLS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
  ];

  /** Türkiye ana yollar — RadarYol benzeri sabit + koridor tohumları */
  const SEED = [
    // İstanbul – Ankara (TEM / O-4)
    { id: "tem-gebze", type: "fixed", lat: 40.802, lng: 29.438, maxspeed: 120, label: "Gebze TEM" },
    { id: "tem-izmit", type: "fixed", lat: 40.765, lng: 29.94, maxspeed: 120, label: "İzmit TEM" },
    { id: "kor-sakarya", type: "corridor", lat: 40.74, lng: 30.35, maxspeed: 120, lengthKm: 12, label: "Sakarya koridor" },
    { id: "kor-ankara-bati", type: "corridor", lat: 39.95, lng: 32.45, maxspeed: 120, lengthKm: 18, label: "Ankara batı koridor" },
    // İstanbul – İzmir (O-5)
    { id: "o5-kemalpasa", type: "fixed", lat: 38.45, lng: 27.45, maxspeed: 130, label: "Kemalpaşa O-5" },
    { id: "kor-o5-balikesir", type: "corridor", lat: 39.55, lng: 27.95, maxspeed: 130, lengthKm: 22, label: "Balıkesir O-5 koridor" },
    { id: "kor-o5-manisa", type: "corridor", lat: 38.72, lng: 27.35, maxspeed: 130, lengthKm: 15, label: "Manisa O-5 koridor" },
    // Ankara – Antalya / Konya
    { id: "kor-konya", type: "corridor", lat: 38.0, lng: 32.55, maxspeed: 110, lengthKm: 16, label: "Konya koridor" },
    { id: "fixed-aksaray", type: "fixed", lat: 38.37, lng: 34.03, maxspeed: 110, label: "Aksaray" },
    // İstanbul Avrupa / TEM
    { id: "fixed-hadimkoy", type: "fixed", lat: 41.14, lng: 28.6, maxspeed: 120, label: "Hadımköy" },
    { id: "kor-catalca", type: "corridor", lat: 41.15, lng: 28.35, maxspeed: 120, lengthKm: 14, label: "Çatalca koridor" },
    { id: "fixed-silivri", type: "fixed", lat: 41.08, lng: 28.25, maxspeed: 120, label: "Silivri" },
    // Ege / Akdeniz
    { id: "fixed-aydin", type: "fixed", lat: 37.84, lng: 27.84, maxspeed: 120, label: "Aydın O-31" },
    { id: "kor-antalya", type: "corridor", lat: 37.05, lng: 30.65, maxspeed: 110, lengthKm: 10, label: "Antalya koridor" },
  ];

  let el = null;
  let cameras = [];
  let fetchCenter = null;
  let fetchedAt = 0;
  let fetching = false;
  let lastUiUpdate = 0;
  let urlIndex = 0;
  let lastSpokenKey = "";
  let lastSpokenAt = 0;
  let corridorState = null; // { id, enteredAt, enterLat, enterLng, limit, lengthM, lostTicks }
  let lastAlert = null;
  let demoTour = false;

  const DEMO_CAMERAS = [
    {
      id: "demo-radar-a",
      type: "fixed",
      lat: 41.12,
      lng: 29.05,
      maxspeed: 120,
      label: "Demo Radar A",
    },
    {
      id: "demo-radar-b",
      type: "fixed",
      lat: 41.12,
      lng: 29.015,
      maxspeed: 100,
      label: "Demo Radar B",
    },
    {
      id: "demo-corridor",
      type: "corridor",
      lat: 41.12,
      lng: 28.975,
      maxspeed: 110,
      lengthKm: 2.4,
      label: "Demo Hız Koridoru",
    },
  ];

  const t = (key, vars) => (typeof I18n !== "undefined" ? I18n.t(key, vars) : key);

  function init(rootId) {
    el = document.getElementById(rootId);
    cameras = SEED.map((s) => ({ ...s }));
  }

  function beginDemoTour() {
    demoTour = true;
    corridorState = null;
    lastSpokenKey = "";
    lastAlert = null;
    lastUiUpdate = 0;
    cameras = DEMO_CAMERAS.map((c) => ({ ...c }));
  }

  function endDemoTour() {
    demoTour = false;
    corridorState = null;
    lastSpokenKey = "";
    lastAlert = null;
    cameras = SEED.map((s) => ({ ...s }));
  }

  function isDemoTour() {
    return !!demoTour;
  }

  function haversineM(lat1, lon1, lat2, lon2) {
    const R = 6371000;
    const dLat = ((lat2 - lat1) * Math.PI) / 180;
    const dLon = ((lon2 - lon1) * Math.PI) / 180;
    const a =
      Math.sin(dLat / 2) ** 2 +
      Math.cos((lat1 * Math.PI) / 180) *
        Math.cos((lat2 * Math.PI) / 180) *
        Math.sin(dLon / 2) ** 2;
    return 2 * R * Math.asin(Math.sqrt(a));
  }

  function bearingDeg(lat1, lon1, lat2, lon2) {
    const p1 = (lat1 * Math.PI) / 180;
    const p2 = (lat2 * Math.PI) / 180;
    const dl = ((lon2 - lon1) * Math.PI) / 180;
    const y = Math.sin(dl) * Math.cos(p2);
    const x = Math.cos(p1) * Math.sin(p2) - Math.sin(p1) * Math.cos(p2) * Math.cos(dl);
    return ((Math.atan2(y, x) * 180) / Math.PI + 360) % 360;
  }

  function angleDiff(a, b) {
    const d = Math.abs(a - b) % 360;
    return d > 180 ? 360 - d : d;
  }

  function stageFor(distM) {
    return STAGES.find((s) => distM <= s.max) || null;
  }

  function formatDist(m) {
    if (!Number.isFinite(m) || m <= 0) return "—";
    if (m >= 1000) return `${(m / 1000).toFixed(m >= 2000 ? 0 : 1)} km`;
    if (m > 100) {
      // 500 mt öncesinde ve 100 mt'ye kadar: 100 mt 100 mt azalsın
      const hundreds = Math.min(900, Math.max(100, Math.round(m / 100) * 100));
      return `${hundreds} m`;
    }
    // 100 mt den sonra: 10 mt 10 mt azalsın
    const tens = Math.max(10, Math.round(m / 10) * 10);
    return `${tens} m`;
  }

  function isTurkishSpeech() {
    try {
      return (typeof I18n !== "undefined" && String(I18n.lang || "").startsWith("tr"));
    } catch (_) {
      return false;
    }
  }

  function trNumWords(n) {
    const x = Math.max(0, Math.min(9999, Math.round(Number(n) || 0)));
    if (x === 0) return "sıfır";
    const ones = ["", "bir", "iki", "üç", "dört", "beş", "altı", "yedi", "sekiz", "dokuz"];
    const tens = ["", "on", "yirmi", "otuz", "kırk", "elli", "altmış", "yetmiş", "seksen", "doksan"];
    const thousand = Math.floor(x / 1000);
    const hundred = Math.floor((x % 1000) / 100);
    const ten = Math.floor((x % 100) / 10);
    const one = x % 10;
    const out = [];
    if (thousand > 0) out.push(thousand === 1 ? "bin" : `${ones[thousand]} bin`);
    if (hundred > 0) out.push(hundred === 1 ? "yüz" : `${ones[hundred]} yüz`);
    if (ten > 0) out.push(tens[ten]);
    if (one > 0) out.push(ones[one]);
    return out.join(" ");
  }

  function speechDist(m) {
    const d = Math.max(0, Number(m) || 0);
    if (!isTurkishSpeech()) return formatDist(d);
    // TTS için net okunuş: "üç yüz metre" / "iki kilometre"
    if (d >= 1000) {
      const km = d >= 2000 ? Math.round(d / 1000) : 1;
      return `${trNumWords(km)} kilometre`;
    }
    const meters = Math.max(50, Math.round(d / 50) * 50);
    return `${trNumWords(meters)} metre`;
  }

  function speechLimit(limit) {
    const v = Math.round(Number(limit) || 0);
    if (v <= 0) return "";
    if (!isTurkishSpeech()) return `${v}`;
    // Kullanıcı isteği: "hız sınır 110" — km yok
    return `hız sınır ${v}`;
  }

  function mergeCameras(list) {
    const map = new Map();
    [...SEED, ...list].forEach((c) => {
      const key = c.id || `${c.type}:${c.lat.toFixed(3)},${c.lng.toFixed(3)}`;
      if (!map.has(key)) map.set(key, { ...c, id: key });
    });
    cameras = [...map.values()];
  }

  async function fetchCameras(lat, lng) {
    if (demoTour) return;
    if (fetching) return;
    fetching = true;
    const query = `[out:json][timeout:15];(
      node["highway"="speed_camera"](around:${FETCH_RADIUS_M},${lat},${lng});
      node["enforcement"="maxspeed"](around:${FETCH_RADIUS_M},${lat},${lng});
      node["enforcement"="average_speed"](around:${FETCH_RADIUS_M},${lat},${lng});
      node["camera:type"="section"](around:${FETCH_RADIUS_M},${lat},${lng});
    );out body;`;
    try {
      const url = OVERPASS_URLS[urlIndex % OVERPASS_URLS.length];
      const res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: "data=" + encodeURIComponent(query),
      });
      if (!res.ok) throw new Error("overpass " + res.status);
      const data = await res.json();
      const remote = (data.elements || [])
        .filter((n) => n.lat != null && n.lon != null)
        .map((n) => {
          const tags = n.tags || {};
          const isCorridor =
            tags.enforcement === "average_speed" ||
            tags["camera:type"] === "section" ||
            tags["traffic_sign"] === "average_speed";
          return {
            id: `osm-${n.id}`,
            type: isCorridor ? "corridor" : "fixed",
            lat: n.lat,
            lng: n.lon,
            maxspeed: parseInt(tags.maxspeed, 10) || null,
            lengthKm: parseFloat(tags.length) || (isCorridor ? 8 : null),
            label: tags.name || tags.ref || null,
          };
        });
      mergeCameras(remote);
      fetchCenter = { lat, lng };
      fetchedAt = Date.now();
    } catch (_) {
      urlIndex += 1;
      fetchedAt = Date.now() - REFETCH_AGE_MS + 90 * 1000;
      mergeCameras([]);
    } finally {
      fetching = false;
    }
  }

  function speak(key, text) {
    const now = Date.now();
    if (key === lastSpokenKey && now - lastSpokenAt < 28000) return;
    lastSpokenKey = key;
    lastSpokenAt = now;
    const urgent = /critical|slow/i.test(String(key));

    // Native SwiftUI cluster owns warn voice (EtubuWarnVoice / playWarnCue).
    // Cap only primes beeps for web-only sessions.
    if (window.__ETUBU_NATIVE_CLUSTER__) {
      try {
        window.__etubuPendingWarnSpeak = {
          key: String(key || ""),
          text: String(text || ""),
          urgent: !!urgent,
          at: now,
        };
      } catch (_) {}
      // Soft beep only — phrase is spoken natively from DriveWarnings poll.
      try {
        const Ctx = window.AudioContext || window.webkitAudioContext;
        if (!Ctx) return;
        if (!window.__etubuBeepCtx) window.__etubuBeepCtx = new Ctx();
        const ctx = window.__etubuBeepCtx;
        if (ctx.state === "suspended") ctx.resume();
        // Skip Cap beeps too when native handles playWarnCue (avoids double beep).
      } catch (_) {}
      return;
    }

    try {
      const Ctx = window.AudioContext || window.webkitAudioContext;
      if (Ctx) {
        if (!window.__etubuBeepCtx) window.__etubuBeepCtx = new Ctx();
        const ctx = window.__etubuBeepCtx;
        if (ctx.state === "suspended") ctx.resume();
        const n = urgent ? 4 : 2;
        const freq = urgent ? 1180 : 880;
        const peakGain = urgent ? 0.85 : 0.65;
        const t0 = ctx.currentTime;
        for (let i = 0; i < n; i++) {
          const o = ctx.createOscillator();
          const g = ctx.createGain();
          o.type = urgent ? "square" : "sine";
          o.frequency.value = freq;
          const start = t0 + i * 0.16;
          g.gain.setValueAtTime(0.0001, start);
          g.gain.exponentialRampToValueAtTime(peakGain, start + 0.01);
          g.gain.exponentialRampToValueAtTime(0.0001, start + 0.13);
          o.connect(g);
          g.connect(ctx.destination);
          o.start(start);
          o.stop(start + 0.15);
        }
      }
    } catch (_) {}

    if (typeof I18n !== "undefined" && I18n.speak) {
      I18n.speak(text, { key, urgent });
    } else {
      try {
        const synth = window.speechSynthesis;
        if (!synth || typeof SpeechSynthesisUtterance === "undefined") return;
        synth.cancel();
        const u = new SpeechSynthesisUtterance(String(text || ""));
        u.lang = (typeof I18n !== "undefined" && I18n.speechLocale?.()) || "tr-TR";
        u.rate = urgent ? 1.08 : 1.02;
        u.volume = 1;
        synth.speak(u);
      } catch (_) {}
    }
  }

  /** Start jestinde çağrılır: uyarı beep context'i her zaman hazır olsun. */
  function primeAudio() {
    try {
      const Ctx = window.AudioContext || window.webkitAudioContext;
      if (!Ctx) return false;
      if (!window.__etubuBeepCtx) window.__etubuBeepCtx = new Ctx();
      const ctx = window.__etubuBeepCtx;
      if (ctx.state === "suspended") {
        ctx.resume().catch(() => {});
      }
      try {
        if (window.WarnVoice && window.WarnVoice.prime) window.WarnVoice.prime();
      } catch (_) {}
      return true;
    } catch (_) {
      return false;
    }
  }

  function hide() {
    if (!el) return;
    el.hidden = true;
    el.className = "radar-alert";
    el.innerHTML = "";
  }

  function buildAlert(opts) {
    if (!opts) return null;
    const {
      kind,
      stage,
      distM,
      limit,
      over,
      avg,
      remainM,
      label,
    } = opts;
    const title =
      kind === "corridor-in"
        ? t("radarCorridorIn")
        : kind === "corridor"
          ? t("radarCorridor")
          : t("radarAhead");
    const distLabel =
      kind === "corridor-in" && remainM != null
        ? formatDist(remainM)
        : formatDist(distM);
    const metaBits = [];
    if (limit) metaBits.push(`${limit} km/h`);
    if (kind === "corridor-in" && avg != null) metaBits.push(`${t("radarAvg")} ${Math.round(avg)}`);
    if (label) metaBits.push(label);
    if (over) metaBits.push(t("radarSlow"));
    return {
      kind,
      stage: stage || "far",
      over: !!over,
      title,
      dist: distLabel,
      meta: metaBits.join(" · "),
      limit: limit || null,
    };
  }

  function renderCard(opts) {
    // Eski yüzen kart artık kullanılmıyor — sol HUD app.js üzerinden boyanır
    void opts;
    hide();
  }

  const passedCameras = new Set();
  const cameraMinDist = new Map();

  function findAhead(lat, lng, heading) {
    const ahead = [];
    const hasHeading = heading != null && Number.isFinite(heading);

    for (const cam of cameras) {
      const d = haversineM(lat, lng, cam.lat, cam.lng);
      if (d > AHEAD_MAX_M) {
        if (d > 3500) {
          passedCameras.delete(cam.id);
          cameraMinDist.delete(cam.id);
        }
        continue;
      }

      if (passedCameras.has(cam.id)) continue;

      const lastMin = cameraMinDist.get(cam.id) ?? Infinity;
      if (d < lastMin) {
        cameraMinDist.set(cam.id, d);
      }

      const b = bearingDeg(lat, lng, cam.lat, cam.lng);
      const diff = hasHeading ? angleDiff(b, heading) : 0;

      // Nokta geçilme tespiti:
      // Açı 85°'den fazla sapmışsa (nokta arkada kalmışsa) veya
      // nokta çok yaklaştıktan (<60m) sonra mesafe artmaya başlamışsa geçilmiştir.
      const passedByAngle = hasHeading && diff > 85;
      const passedByReceding = lastMin < 60 && d > lastMin + 10;

      if (passedByAngle || passedByReceding) {
        passedCameras.add(cam.id);
        continue;
      }

      if (hasHeading && diff > HEADING_TOLERANCE) {
        continue;
      }

      ahead.push({ cam, d, bearing: b });
    }
    ahead.sort((a, b) => a.d - b.d);
    return ahead;
  }

  /** True distance/time corridor avg (camera measurement). 0 until ≥35 m & ~4.3 s. */
  function corridorTrueAvgNow() {
    if (!corridorState) return 0;
    const traveled = corridorState.traveledM || 0;
    const elapsedH = (Date.now() - corridorState.enteredAt) / 3600000;
    if (traveled < 35 || elapsedH < 0.0012) return 0;
    const avg = traveled / 1000 / elapsedH;
    if (!Number.isFinite(avg) || avg < 0) return 0;
    return Math.min(220, avg);
  }

  /**
   * Display avg: on entry show vehicle speed; as progress grows blend toward true avg
   * (start ~50% hist + 50% instant → end ~90% / 10%). YAVAŞLA uses corridorTrueAvgNow.
   */
  function corridorAvgNow(kmh) {
    if (!corridorState) return 0;
    const instant = Math.max(0, Math.min(220, Number(kmh) || 0));
    const trueAvg = corridorTrueAvgNow();
    if (!(trueAvg > 0)) return instant;
    const lengthM = corridorState.lengthM || 1;
    const progress = Math.min(1, Math.max(0, (corridorState.traveledM || 0) / lengthM));
    const histW = 0.5 + 0.4 * progress;
    const blended = histW * trueAvg + (1 - histW) * instant;
    return Math.min(220, Math.max(0, blended));
  }

  function tickCorridorTravel(lat, lng, kmh) {
    if (!corridorState) return;
    const now = Date.now();
    const lastMs = corridorState.lastMs || corridorState.enteredAt;
    const dt = Math.max(0, Math.min(2.5, (now - lastMs) / 1000));
    corridorState.lastMs = now;

    if (!(dt > 0.05 && dt < 2.2)) {
      corridorState.lastLat = lat;
      corridorState.lastLng = lng;
      return;
    }

    let addM = kmh >= 2 ? (kmh / 3.6) * dt : 0;
    if (corridorState.lastLat != null) {
      const step = haversineM(
        corridorState.lastLat,
        corridorState.lastLng,
        lat,
        lng
      );
      const impliedKmh = dt > 0 ? (step / dt) * 3.6 : 0;
      const plausibleStep =
        step > 0.4 &&
        step < 120 &&
        impliedKmh <= 260 &&
        (kmh < 2 || Math.abs(impliedKmh - kmh) <= 55);
      if (plausibleStep) {
        if (addM > 0) {
          // Koridor ortalaması hız verisini takip etsin; GPS sadece düzeltme katsayısı.
          addM = addM * 0.7 + step * 0.3;
        } else {
          addM = step;
        }
      }
    }
    if (addM > 0) corridorState.traveledM += addM;
    corridorState.lastLat = lat;
    corridorState.lastLng = lng;
  }

  function updateCorridor(lat, lng, kmh, nearestCorridor) {
    // Aktif koridorda kal — ahead listesinden düşse bile ortalamayı sürdür
    if (corridorState) {
      tickCorridorTravel(lat, lng, kmh);
      const traveled = corridorState.traveledM || 0;
      const remain = Math.max(0, corridorState.lengthM - traveled);
      const dToStart =
        corridorState.enterLat != null
          ? haversineM(lat, lng, corridorState.enterLat, corridorState.enterLng)
          : traveled;
      const sameCorridorAhead =
        !!nearestCorridor && nearestCorridor.cam?.id === corridorState.id;
      corridorState.lostTicks = sameCorridorAhead ? 0 : (corridorState.lostTicks || 0) + 1;

      // Çıkış: kalan bitti veya başlangıçtan koridor boyunu geçtik
      const pastEnd = traveled >= corridorState.lengthM - 60 || dToStart > corridorState.lengthM + 350;
      const lostTrack =
        (corridorState.lostTicks || 0) >= 6 &&
        (!nearestCorridor || nearestCorridor.d > 700) &&
        dToStart > 450;
      if (remain < 60 || pastEnd || lostTrack) {
        speak(
          "exit-" + corridorState.id,
          isTurkishSpeech() ? "Koridor bitti" : t("radarCorridorExit")
        );
        corridorState = null;
        return null;
      }

      const avg = corridorAvgNow(kmh);
      const trueAvg = corridorTrueAvgNow();
      return {
        kind: "corridor-in",
        stage: remain < 400 ? "near" : "mid",
        distM: Math.max(0, nearestCorridor?.d ?? remain),
        remainM: remain,
        limit: corridorState.limit,
        avg,
        trueAvg,
        over: trueAvg > 0 && trueAvg > corridorState.limit + 2,
        label: corridorState.label,
        id: corridorState.id,
        active: true,
        entered: false,
      };
    }

    if (!nearestCorridor) return null;
    const { cam, d } = nearestCorridor;
    const lengthM = (cam.lengthKm || 10) * 1000;

    // Giriş: koridor başlangıcına ~280 m — ortalama sıfırdan başlar
    if (d < 280) {
      corridorState = {
        id: cam.id,
        enteredAt: Date.now(),
        lastMs: Date.now(),
        enterLat: lat,
        enterLng: lng,
        limit: cam.maxspeed || 120,
        lengthM,
        label: cam.label,
        traveledM: 0,
        lastLat: lat,
        lastLng: lng,
        lostTicks: 0,
      };
      if (isTurkishSpeech()) {
        const lim = speechLimit(cam.maxspeed);
        speak(
          "enter-" + cam.id,
          lim ? `Koridor giriş. ${lim}` : "Koridor giriş"
        );
      } else {
        speak("enter-" + cam.id, `${t("radarCorridorIn")}. ${cam.maxspeed || ""}`);
      }
      return {
        kind: "corridor-in",
        stage: "near",
        distM: d,
        remainM: lengthM,
        limit: corridorState.limit,
        // Entry: show vehicle speed immediately (no blank waiting for 35 m).
        avg: Math.max(0, Math.min(220, Number(kmh) || 0)),
        trueAvg: 0,
        over: false,
        label: corridorState.label,
        id: corridorState.id,
        active: true,
        entered: true,
      };
    }
    return null;
  }

  function update(lat, lng, heading, kmh) {
    if (lat == null || lng == null || !Number.isFinite(lat)) {
      return { alert: lastAlert, corridor: getCorridorSnapshot(kmh), queue: [] };
    }

    const stale =
      !demoTour &&
      (!fetchCenter ||
        Date.now() - fetchedAt > REFETCH_AGE_MS ||
        haversineM(fetchCenter.lat, fetchCenter.lng, lat, lng) > REFETCH_DIST_M);
    if (stale) fetchCameras(lat, lng);

    const now = Date.now();
    const ahead = heading != null && Number.isFinite(heading) ? findAhead(lat, lng, heading) : [];
    const nearestCorridor = ahead.find((x) => x.cam.type === "corridor") || null;
    const inCorridor = updateCorridor(lat, lng, kmh, nearestCorridor);

    // Corridor over-speed: beep + speak immediately (not throttled with HUD)
    if (inCorridor?.over) {
      speak("corridor-over", t("radarSlow"));
    }

    // UI throttle — demoda daha sık (aşamalar görünsün)
    let alert = null;
    const uiGap = demoTour ? 160 : 400;
    if (now - lastUiUpdate >= uiGap) {
      lastUiUpdate = now;
      if (inCorridor) {
        alert = buildAlert(inCorridor);
      } else {
        const nearest = ahead[0];
        const stage = nearest ? stageFor(nearest.d) : null;
        if (nearest && stage) {
          const limit = nearest.cam.maxspeed;
          const over = limit != null && kmh > limit + 3;
          const kind = nearest.cam.type === "corridor" ? "corridor" : "fixed";
          const opts = {
            kind,
            stage: stage.key,
            distM: nearest.d,
            limit,
            over,
            label: nearest.cam.label,
          };
          alert = buildAlert(opts);
          // 500 mt öncesinde TEK sesli uyarı (5 km, 2 km, 1 km tekrarları kaldırıldı)
          const speak500Key = `cam-500-${nearest.cam.id}`;
          if (nearest.d <= 550 && nearest.d >= 60 && lastSpokenKey !== speak500Key) {
            lastSpokenKey = speak500Key;
            const phrase = isTurkishSpeech()
              ? (kind === "corridor"
                  ? "Hız koridoru. 500 metre."
                  : `Radar. 500 metre.${limit ? ` ${speechLimit(limit)}.` : ""}`)
              : `${t("radarAhead")} 500 m`;
            speak(speak500Key, phrase);
          } else if (nearest.d <= 300 && over) {
            speak(`slow-${nearest.cam.id}`, t("radarSlow"));
          }
        }
      }
      lastAlert = alert;
    } else {
      alert = lastAlert;
    }

    const queueBase = ahead.slice(0, 4).map(({ cam, d }) => {
      const kind = cam.type === "corridor" ? "corridor" : "radar";
      const stage =
        STAGES.find((s) => d <= s.max)?.key || (d <= AHEAD_MAX_M ? "far" : "far");
      return {
        id: cam.id || `${cam.lat},${cam.lng}`,
        kind,
        title:
          kind === "corridor" ? t("radarCorridor") : t("radarAhead"),
        dist: formatDist(d),
        distM: d,
        meta: [cam.maxspeed ? `${cam.maxspeed} km/h` : "", cam.label || ""]
          .filter(Boolean)
          .join(" · "),
        stage,
        label: cam.label || "",
      };
    });
    const queue = inCorridor
      ? [
          {
            id: `in-${inCorridor.id}`,
            kind: "corridor",
            title: t("radarCorridorIn"),
            dist: formatDist(inCorridor.remainM),
            distM: inCorridor.remainM,
            meta: [
              inCorridor.limit ? `${inCorridor.limit} km/h` : "",
              inCorridor.label || "",
              `${t("radarAvg")} ${Math.round(inCorridor.avg || 0)}`,
            ]
              .filter(Boolean)
              .join(" · "),
            stage: inCorridor.stage || "near",
            label: inCorridor.label || "",
          },
          ...queueBase.filter((q) => q.id !== inCorridor.id),
        ].slice(0, 4)
      : queueBase;

    return {
      alert,
      corridor: inCorridor
        ? {
            active: true,
            id: inCorridor.id,
            avg: inCorridor.avg,
            limit: inCorridor.limit,
            remainM: inCorridor.remainM,
            over: inCorridor.over,
            label: inCorridor.label,
            entered: !!inCorridor.entered,
          }
        : null,
      queue,
    };
  }

  function getCorridorSnapshot(kmh) {
    if (!corridorState) return null;
    const traveled = corridorState.traveledM || 0;
    const remain = Math.max(0, corridorState.lengthM - traveled);
    const avg = corridorAvgNow(kmh);
    const trueAvg = corridorTrueAvgNow();
    return {
      active: true,
      id: corridorState.id,
      avg,
      trueAvg,
      limit: corridorState.limit,
      remainM: remain,
      over: trueAvg > 0 && trueAvg > corridorState.limit + 2,
      label: corridorState.label,
      entered: false,
    };
  }

  function resetCorridor() {
    corridorState = null;
  }

  function clear() {
    corridorState = null;
    lastSpokenKey = "";
    lastAlert = null;
    if (demoTour) endDemoTour();
    hide();
    try {
      window.speechSynthesis?.cancel();
    } catch (_) {}
  }

  function getCameras() {
    return cameras.length ? cameras.slice() : SEED.map((s) => ({ ...s }));
  }

  return {
    init,
    update,
    clear,
    resetCorridor,
    getCorridorSnapshot,
    getCameras,
    primeAudio,
    beginDemoTour,
    endDemoTour,
    isDemoTour,
  };
})();

try {
  window.RadarAlert = RadarAlert;
} catch (_) {}
