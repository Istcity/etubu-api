/**
 * YolSafe / rota koruması — global (OSM hız, OCM şarj, Open-Meteo hava; EGM radar TR).
 * TTS uyarı klipleri yalnızca UI Türkçe iken.
 * Tek kutu autocomplete (il/ilçe eşleştirme), üst özet kartı,
 * ekran uyarısı + bip + kısa TTS (kritik yaklaşma).
 */
const RouteGuard = (() => {
  // Cap / local bundle has no PHP — use production proxy off-site.
  const PROXY = (() => {
    try {
      const host = String(window.location.hostname || "");
      if (host === "etubu.com" || host.endsWith(".etubu.com")) return "api/trafik.php";
    } catch (_) {}
    return "https://etubu.com/api/trafik.php";
  })();
  const CHARGERS_PROXY = (() => {
    try {
      const host = String(window.location.hostname || "");
      if (host === "etubu.com" || host.endsWith(".etubu.com")) return "api/chargers.php";
    } catch (_) {}
    return "https://etubu.com/api/chargers.php";
  })();
  const INDEX_KEY = "etubu_place_index_v4";
  const INDEX_KEY_LEGACY = "etubu_place_index_v3";
  const INDEX_TTL_MS = 7 * 24 * 3600 * 1000;
  /** TR büyükşehirler — merkez ilçe yok; il adı tek başına ilçe seçimi gerektirir */
  const METROPOLITAN_FOLDS = new Set([
    "adana", "ankara", "antalya", "aydin", "balikesir", "bursa", "denizli",
    "diyarbakir", "erzurum", "eskisehir", "gaziantep", "hatay", "mersin",
    "istanbul", "izmir", "kayseri", "kocaeli", "konya", "malatya", "manisa",
    "kahramanmaras", "mardin", "mugla", "ordu", "sakarya", "samsun",
    "tekirdag", "trabzon", "van", "sanliurfa",
  ]);
  const OVERPASS_URLS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
  ];
  const STAGES = [
    { max: 300, key: "critical", beeps: 3 },
    { max: 1000, key: "near", beeps: 1 },
    { max: 2000, key: "mid", beeps: 0 },
    { max: 5000, key: "far", beeps: 0 },
  ];
  const WEATHER_SEVERE = new Set([
    65, 66, 67, 75, 77, 82, 85, 86, 95, 96, 97, 98, 99,
  ]);

  let root = null;
  let fromInput = null;
  let toInput = null;
  let fromSuggest = null;
  let toSuggest = null;
  let goBtn = null;
  let clearBtn = null;
  let statusEl = null;
  let briefEl = null;
  let pulseEl = null;
  let pulseText = null;
  let formEl = null;

  let placeIndex = [];
  let fromPlace = null;
  let toPlace = null;
  let routeCoords = [];
  let hazards = [];
  let briefing = null;
  let active = false;
  let collapsed = false;
  let lastAlertKey = "";
  let lastAlertAt = 0;
  let lastPos = null;
  let overpassIdx = 0;
  let beepCtx = null;
  let indexLoading = null;
  let lastPulse = null;
  let briefPeek = null;
  let formPeek = null;
  let motionHideTimer = null;
  let detailsCloseTimer = null;
  let panelsAutoHidden = false;
  let briefEnrich = null;
  let touchedCritical = new Set();
  const MOTION_KMH = 6;
  const MOTION_HIDE_MS = 5000;
  const DETAILS_AUTO_CLOSE_MS = 5000;
  const PASS_TOUCH_M = 220;
  const PASS_CLEAR_M = 280;

  function t(key, vars) {
    return typeof I18n !== "undefined" ? I18n.t(key, vars) : key;
  }

  function fold(s) {
    // NFC + combining diacritics — iOS keyboard sometimes emits NFD (C + ̧)
    let t = String(s || "")
      .normalize("NFC")
      .toLocaleLowerCase("tr-TR")
      .replace(/[\u0300-\u036f]/g, "");
    return t
      .replace(/ğ/g, "g")
      .replace(/ü/g, "u")
      .replace(/ş/g, "s")
      .replace(/ı/g, "i")
      .replace(/İ/g, "i")
      .replace(/ö/g, "o")
      .replace(/ç/g, "c")
      .replace(/[^a-z0-9\s]/g, " ")
      .replace(/\s+/g, " ")
      .trim();
  }

  function isMetropolitan(cityName) {
    return METROPOLITAN_FOLDS.has(fold(cityName));
  }

  /** Native ile aynı: ilçe zorunlu değil — şehir merkezi / OSM resolve yeterli. */
  function needsDistrictPick(_text) {
    return false;
  }

  /** Rota UI + yol üstü bilgi — dil bağımsız; EGM radar yalnızca TR rotasında. */
  function isTurkeyTurkish() {
    return true;
  }

  /** Kalkış+varış TR kutusu içindeyse EGM + TR seed; aksi halde OSM/OSRM. */
  function isDomesticRoute(from, to) {
    const fl = Number(from?.lat);
    const fn = Number(from?.lng);
    const tl = Number(to?.lat);
    const tn = Number(to?.lng);
    if (![fl, fn, tl, tn].every(Number.isFinite)) return EtubuRegionHint.inTurkey();
    return inTurkeyBounds(fl, fn) && inTurkeyBounds(tl, tn);
  }

  const EtubuRegionHint = {
    /** Kayıt / force yoksa false — yurt dışı cold start EGM/TR seed’e düşmez. */
    inTurkey() {
      try {
        if (typeof window.__etubuForceTrRoute !== "undefined") {
          return !!Number(window.__etubuForceTrRoute);
        }
        const v =
          (window.sessionStorage && sessionStorage.getItem("etubu_force_tr_route")) ||
          (window.localStorage && localStorage.getItem("etubu_force_tr_route"));
        if (v != null) return v === "1" || v === "true";
      } catch (_) {}
      return false;
    },
  };

  /** TTS klip sesleri yalnızca UI Türkçe iken. */
  function isTurkishSpeechLang() {
    try {
      const lang = typeof I18n !== "undefined" ? I18n.lang : "tr";
      return String(lang || "").toLowerCase().startsWith("tr");
    } catch (_) {
      return false;
    }
  }

  function inTurkeyBounds(lat, lng) {
    return lat >= 35.8 && lat <= 42.35 && lng >= 25.6 && lng <= 45.0;
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

  function formatDist(m) {
    if (!Number.isFinite(m) || m < 0) return "";
    // Basamaklı mesafe (yol uyarıları tablosu):
    // >5 km → 10 km; <5 km → 1 km; <2 km → 100 m; <300 m → 50 m; <100 m → 10 m
    let stepped;
    if (m >= 5000) {
      stepped = Math.max(10000, Math.floor(m / 10000) * 10000);
    } else if (m >= 2000) {
      stepped = Math.max(1000, Math.floor(m / 1000) * 1000);
    } else if (m >= 300) {
      stepped = Math.max(100, Math.floor(m / 100) * 100);
    } else if (m >= 100) {
      stepped = Math.max(50, Math.floor(m / 50) * 50);
    } else {
      stepped = Math.max(10, Math.floor(m / 10) * 10);
    }
    if (stepped >= 1000) {
      const km = stepped / 1000;
      return `${Number.isInteger(km) ? km : km.toFixed(1)} km`;
    }
    return `${Math.round(stepped)} m`;
  }

  function setStatus(msg) {
    if (statusEl) statusEl.textContent = msg || "";
  }

  function ensureBeepCtx() {
    if (!beepCtx) {
      beepCtx = new (window.AudioContext || window.webkitAudioContext)();
    }
    if (beepCtx.state === "suspended") beepCtx.resume().catch(() => {});
    return beepCtx;
  }

  /** Sesli bip + kısa TTS (gözler yolda) */
  function playBeeps(count, urgent = false) {
    if (!count || count < 1) return;
    try {
      const ctx = ensureBeepCtx();
      const now = ctx.currentTime;
      const freq = urgent ? 1180 : 880;
      for (let i = 0; i < count; i++) {
        const o = ctx.createOscillator();
        const g = ctx.createGain();
        o.type = "sine";
        o.frequency.value = freq;
        const t0 = now + i * (urgent ? 0.16 : 0.2);
        g.gain.setValueAtTime(0.0001, t0);
        g.gain.exponentialRampToValueAtTime(urgent ? 0.22 : 0.16, t0 + 0.02);
        g.gain.exponentialRampToValueAtTime(0.0001, t0 + 0.11);
        o.connect(g);
        g.connect(ctx.destination);
        o.start(t0);
        o.stop(t0 + 0.13);
      }
    } catch (_) {}
  }

  function speakCue(key, text, urgent = false) {
    if (!isTurkishSpeechLang()) return;
    if (typeof I18n !== "undefined" && I18n.speak) {
      I18n.speak(text, { key, urgent });
      return;
    }
    try {
      const synth = window.speechSynthesis;
      if (!synth || typeof SpeechSynthesisUtterance === "undefined") return;
      synth.cancel();
      const u = new SpeechSynthesisUtterance(String(text || ""));
      u.lang = "tr-TR";
      u.rate = urgent ? 1.08 : 1.02;
      synth.speak(u);
    } catch (_) {}
  }

  function alertPhrase(h, stage, distLabel) {
    if (h.kind === "charge") {
      return `${t("hudChargeWarn")} ${distLabel}`;
    }
    if (h.kind === "weather") {
      return `${h.label || t("routeWeatherSevere")} ${distLabel}`;
    }
    if (h.kind === "corridor") {
      if (stage.key === "critical" || stage.key === "near") {
        return `${t("radarCorridor")} ${distLabel}`;
      }
      return `${t("radarCorridor")} ${distLabel}`;
    }
    if (stage.key === "critical") return `${t("radarAhead")} ${distLabel}`;
    if (stage.key === "near") return `${t("radarAhead")} 1 ${t("radarKm")}`;
    if (stage.key === "mid") return `${t("radarAhead")} 2 ${t("radarKm")}`;
    return `${t("radarAhead")} ${distLabel}`;
  }

  function alertBeep(key, stage, phrase) {
    const now = Date.now();
    if (key === lastAlertKey && now - lastAlertAt < 28000) return;
    lastAlertKey = key;
    lastAlertAt = now;
    const urgent = stage.key === "critical" || stage.key === "near";
    // Always prefer audio over reading the HUD
    const beeps =
      stage.beeps > 0
        ? stage.beeps
        : stage.key === "mid"
          ? 1
          : stage.key === "far"
            ? 1
            : 0;
    playBeeps(beeps || (urgent ? 2 : 1), urgent);
    if (phrase) speakCue(key, phrase, urgent);
  }

  async function proxyGet(params) {
    // Cap WKWebView → etubu.com is cross-origin; native URLSession has no CORS.
    try {
      if (window.EtubuNative && typeof window.EtubuNative.trafikGet === "function") {
        const native = await window.EtubuNative.trafikGet(params || {});
        if (native && typeof native === "object") return native;
      }
    } catch (_) {}
    const qs = new URLSearchParams(params).toString();
    const res = await fetch(`${PROXY}?${qs}`, { headers: { Accept: "application/json" } });
    if (!res.ok) throw new Error("proxy " + res.status);
    return res.json();
  }

  async function proxyPost(body) {
    try {
      if (window.EtubuNative && typeof window.EtubuNative.trafikPost === "function") {
        const native = await window.EtubuNative.trafikPost(body || {});
        if (native && typeof native === "object") return native;
      }
    } catch (_) {}
    const res = await fetch(`${PROXY}?action=createRoute`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify(body),
    });
    if (!res.ok) throw new Error("proxy " + res.status);
    return res.json();
  }

  /** Tarayıcıdan OSRM — sunucu EGM/OSRM'ye ulaşamazsa yedek */
  async function fetchOsrmRoute(from, to) {
    const url =
      `https://router.project-osrm.org/route/v1/driving/` +
      `${encodeURIComponent(from.lng)},${encodeURIComponent(from.lat)};` +
      `${encodeURIComponent(to.lng)},${encodeURIComponent(to.lat)}` +
      `?overview=full&geometries=geojson`;
    const res = await fetch(url, { headers: { Accept: "application/json" } });
    if (!res.ok) throw new Error("osrm " + res.status);
    const json = await res.json();
    const route = json?.routes?.[0];
    const pairs = route?.geometry?.coordinates;
    if (json?.code !== "Ok" || !Array.isArray(pairs) || pairs.length < 2) {
      throw new Error("osrm_empty");
    }
    return {
      FromDistrict: from.label || t("routeFrom"),
      ToDistrict: to.label || t("routeTo"),
      FromCity: placeCityName(from),
      ToCity: placeCityName(to),
      RadarCount: 0,
      ControlPointCount: 0,
      CorridorCount: 0,
      Cities: [],
      Radars: [],
      SpeedTunnels: [],
      Coordinates: pairs.map(([x, y]) => ({ x, y })),
      source: "osrm",
    };
  }

  function placeCityName(place) {
    if (!place) return "";
    if (place.cityName) return String(place.cityName).trim();
    if (place.nearLabel) {
      const near = String(place.nearLabel).split(/[/(]/)[0].trim();
      if (near) return near;
    }
    const label = String(place.label || "").trim();
    if (!label) return "";
    // "Konumum" / my-location token alone is not a province
    if (place.isMyLocation) {
      const myTok = fold(t("routeMyLocation"));
      if (fold(label) === myTok || fold(label) === "konumum") return "";
    }
    return label.split(/[/(]/)[0].trim();
  }

  function stripPlaceLabel(raw) {
    const s = String(raw || "").trim();
    if (!s) return "";
    const myTok = fold(t("routeMyLocation"));
    if (fold(s) === myTok || fold(s) === "konumum" || fold(s) === "my location") {
      return "";
    }
    return s.split(/[/(]/)[0].trim();
  }

  function escapeBriefText(s) {
    return String(s || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  /** Province label for brief card — never leave blank when route UI has a place */
  function resolveBriefCity(side, dataOverride) {
    const place = side === "from" ? fromPlace : toPlace;
    const input = side === "from" ? fromInput : toInput;
    const data = dataOverride || briefing;
    const apiCity =
      side === "from"
        ? data?.FromCity || data?.fromCity
        : data?.ToCity || data?.toCity;
    const apiDistrict =
      side === "from"
        ? data?.FromDistrict || data?.fromDistrict
        : data?.ToDistrict || data?.toDistrict;

    const candidates = [
      placeCityName(place),
      place?.cityName && String(place.cityName).trim(),
      place?.nearLabel && stripPlaceLabel(place.nearLabel),
      stripPlaceLabel(apiCity),
      stripPlaceLabel(place?.label),
      stripPlaceLabel(input?.value),
      stripPlaceLabel(apiDistrict),
    ];
    for (const c of candidates) {
      const v = String(c || "").trim();
      if (v) return v;
    }
    // Last resort: show whatever is in the input (incl. Konumum) rather than blank
    const raw = String(input?.value || place?.label || apiDistrict || "").trim();
    if (raw) return raw;
    // Never render blank city boxes in brief
    return side === "from" ? t("routeFrom") : t("routeTo");
  }

  function attachRouteCities(data) {
    if (!data) return data;
    const from = resolveBriefCity("from", data);
    const to = resolveBriefCity("to", data);
    data.FromCity = from;
    data.ToCity = to;
    return data;
  }

  function loadCachedIndex() {
    try {
      const raw = JSON.parse(
        sessionStorage.getItem(INDEX_KEY) ||
          localStorage.getItem(INDEX_KEY) ||
          sessionStorage.getItem(INDEX_KEY_LEGACY) ||
          localStorage.getItem(INDEX_KEY_LEGACY) ||
          "null"
      );
      if (raw?.at && Date.now() - raw.at < INDEX_TTL_MS && Array.isArray(raw.items) && raw.items.length > 100) {
        // Skip legacy caches that were corrupted by atob UTF-8 mojibake (e.g. Ã‡orum)
        const sample = String(raw.items[0]?.cityName || raw.items[0]?.label || "");
        if (/Ã.|Â.|â€/.test(sample)) {
          try {
            sessionStorage.removeItem(INDEX_KEY_LEGACY);
            localStorage.removeItem(INDEX_KEY_LEGACY);
          } catch (_) {}
          return false;
        }
        placeIndex = raw.items;
        return true;
      }
    } catch (_) {}
    return false;
  }

  function saveCachedIndex() {
    try {
      const payload = JSON.stringify({ at: Date.now(), items: placeIndex });
      sessionStorage.setItem(INDEX_KEY, payload);
      try { localStorage.setItem(INDEX_KEY, payload); } catch (_) {}
    } catch (_) {}
  }

  async function buildPlaceIndex() {
    if (placeIndex.length > 100) return placeIndex;
    if (indexLoading) return indexLoading;
    indexLoading = (async () => {
      if (loadCachedIndex()) return placeIndex;
      try {
        sessionStorage.removeItem("etubu_place_index_v2");
      } catch (_) {}
      setStatus(t("routeIndexLoading"));
      const citiesJson = await proxyGet({ action: "cities" });
      if (!citiesJson?.ok) throw new Error("cities");
      const cities = citiesJson.cities || [];
      const items = [];
      // Paralel ama sınırlı
      const chunk = 8;
      for (let i = 0; i < cities.length; i += chunk) {
        const slice = cities.slice(i, i + chunk);
        const parts = await Promise.all(
          slice.map(async (c) => {
            try {
              const d = await proxyGet({ action: "districts", cityId: String(c.Id) });
              return { city: c, districts: d.districts || [] };
            } catch (_) {
              return { city: c, districts: [] };
            }
          })
        );
        for (const { city, districts } of parts) {
          const cityFold = fold(city.Name);
          const metro = isMetropolitan(city.Name);
          for (const d of districts) {
            // Büyükşehirlerde merkez ilçe yok — asla (Merkez) etiketi üretme
            const isMerkez =
              !metro &&
              (/merkez/i.test(d.Name) ||
                fold(d.Name) === cityFold ||
                fold(d.Name) === "merkez");
            const label = isMerkez
              ? `${city.Name} (Merkez)`
              : `${city.Name} / ${d.Name}`;
            items.push({
              cityId: String(city.Id),
              cityName: city.Name,
              districtId: String(d.Id),
              districtName: d.Name,
              lat: d.Latitude,
              lng: d.Longitude,
              label,
              isMerkez: !!isMerkez,
              isMetropolitan: metro,
              search: fold(`${city.Name} ${d.Name} ${label}`),
            });
          }
        }
      }
      placeIndex = items;
      saveCachedIndex();
      setStatus("");
      return placeIndex;
    })();
    try {
      return await indexLoading;
    } finally {
      indexLoading = null;
    }
  }

  function searchPlaces(q, limit = 8) {
    const query = fold(q);
    if (!query || query.length < 2) return [];
    const tokens = query.split(" ").filter(Boolean);
    const maxN = limit || 8;

    // İlçe adı tek başına yazıldıysa (ör. Çankaya) ilçe eşleşmelerini önce getir.
    const districtExact = placeIndex.filter((p) => fold(p.districtName) === query);
    if (districtExact.length) {
      districtExact.sort((a, b) => String(a.label || "").localeCompare(String(b.label || ""), "tr"));
      return districtExact.slice(0, Math.max(maxN, 12));
    }

    // Tek il adı → o ile bağlı tüm ilçeler (büyükşehir + normal il)
    const cityExact = placeIndex.filter((p) => fold(p.cityName) === query);
    if (cityExact.length >= 2 && tokens.length === 1) {
      cityExact.sort((a, b) => {
        if (!isMetropolitan(a.cityName) && !!b.isMerkez !== !!a.isMerkez) {
          return a.isMerkez ? -1 : 1;
        }
        return String(a.districtName || "").localeCompare(String(b.districtName || ""), "tr");
      });
      return cityExact;
    }

    // "Ankara Çankaya" / "ankara cankaya"
    if (tokens.length >= 2) {
      const cityTok = tokens[0];
      const distTok = tokens.slice(1).join(" ");
      const compound = [];
      for (const cp of placeIndex) {
        const cCity = fold(cp.cityName);
        const cDist = fold(cp.districtName);
        if (cCity !== cityTok && !cCity.startsWith(cityTok)) continue;
        let distScore = 0;
        if (cDist === distTok) distScore = 100;
        else if (cDist.startsWith(distTok)) distScore = 85;
        else if (distTok.startsWith(cDist) && cDist.length >= 3) distScore = 70;
        else if ((cp.search || "").includes(distTok)) distScore = 50;
        else continue;
        compound.push({ p: cp, score: distScore + (cp.isMerkez ? 2 : 0) });
      }
      if (compound.length) {
        compound.sort(
          (a, b) =>
            b.score - a.score ||
            String(a.p.label || "").localeCompare(String(b.p.label || ""), "tr")
        );
        return compound.slice(0, Math.max(maxN, 12)).map((x) => x.p);
      }
    }

    const scored = [];
    for (const p of placeIndex) {
      const search =
        p.search || fold(`${p.cityName || ""} ${p.districtName || ""} ${p.label || ""}`);
      let score = 0;
      if (search === query) score = 100;
      else if (fold(p.districtName) === query) score = 90;
      else if (fold(p.cityName) === query && p.isMerkez) score = 88;
      else if (search.startsWith(query)) score = 70;
      else if (fold(p.districtName).startsWith(query)) score = 65;
      else if (tokens.every((tok) => search.includes(tok))) score = 55;
      else if (search.includes(query)) score = 40;
      else continue;
      if (p.isMerkez) score += 3;
      scored.push({ p, score });
    }
    scored.sort(
      (a, b) =>
        b.score - a.score ||
        String(a.p.label || "").localeCompare(String(b.p.label || ""), "tr")
    );
    return scored.slice(0, maxN).map((x) => x.p);
  }

  function resolvePlace(text) {
    const q = fold(text);
    if (!q) return null;
    if (
      q === fold(t("routeMyLocation")) ||
      q === "konumum" ||
      q === "konum" ||
      q === "my location" ||
      q === "location"
    ) {
      return myLocationPlace();
    }

    const tokens = q.split(" ").filter(Boolean);

    // Büyükşehir / il adı tek başına → Merkez veya ilk eşleşme (ilçe şartı yok)
    if (tokens.length === 1 && isMetropolitan(tokens[0])) {
      const cityHits = placeIndex.filter((p) => fold(p.cityName) === q);
      if (cityHits.length) {
        return cityHits.find((h) => h.isMerkez) || cityHits[0];
      }
    }

    if (tokens.length >= 2) {
      const compound = searchPlaces(text, 8);
      if (compound.length) return compound[0];
    }

    const hits = searchPlaces(text, 5);
    if (!hits.length) return null;

    // Normal il: tek il adı → Merkez (Çorum → Çorum (Merkez))
    const cityOnly = hits.find((h) => fold(h.cityName) === q && h.isMerkez);
    if (cityOnly) return cityOnly;

    const distExact = hits.find((h) => fold(h.districtName) === q);
    if (distExact) return distExact;

    return hits[0];
  }

  function getLiveCoords() {
    if (lastPos?.lat != null && lastPos?.lng != null) {
      return { lat: lastPos.lat, lng: lastPos.lng };
    }
    const fix =
      typeof GpsTracker !== "undefined" ? GpsTracker.getLastPosition?.() : null;
    if (fix?.lat != null && fix?.lng != null) {
      lastPos = { lat: fix.lat, lng: fix.lng };
      return lastPos;
    }
    // Native SwiftUI cluster writes phone GPS here before Cap geolocation arms.
    try {
      const loc = JSON.parse(
        localStorage.getItem("etubu_last_map_location") || "{}"
      );
      if (Number.isFinite(loc.lat) && Number.isFinite(loc.lng)) {
        lastPos = { lat: loc.lat, lng: loc.lng };
        return lastPos;
      }
    } catch (_) {}
    return null;
  }

  function nearestDistrict(lat, lng) {
    let best = null;
    let bestD = Infinity;
    for (const p of placeIndex) {
      if (p.lat == null || p.lng == null) continue;
      const d = haversineM(lat, lng, Number(p.lat), Number(p.lng));
      if (d < bestD) {
        bestD = d;
        best = p;
      }
    }
    return best;
  }

  function myLocationPlace() {
    const pos = getLiveCoords();
    if (!pos) return null;
    const near = nearestDistrict(pos.lat, pos.lng);
    return {
      cityId: near?.cityId || "0",
      cityName: near?.cityName || "",
      districtId: near?.districtId || "0",
      districtName: near?.districtName || "",
      lat: pos.lat,
      lng: pos.lng,
      label: t("routeMyLocation"),
      isMerkez: false,
      search: fold(`${t("routeMyLocation")} konumum my location`),
      isMyLocation: true,
      nearLabel: near?.label || "",
    };
  }

  function applyMyLocationAsFrom() {
    const place = myLocationPlace();
    if (!place || !fromInput) return false;
    fromPlace = place;
    fromInput.value = place.label;
    syncGo();
    return true;
  }

  function requestMyLocationOnce() {
    return new Promise((resolve) => {
      const existing = getLiveCoords();
      if (existing) {
        resolve(existing);
        return;
      }
      // Native SwiftUI cluster owns GPS — Cap shell must not prompt during legal/onboarding.
      if (window.__ETUBU_NATIVE_CLUSTER__ && window.__ETUBU_GPS_ARMED__ !== true) {
        resolve(null);
        return;
      }
      if (!navigator.geolocation) {
        resolve(null);
        return;
      }
      navigator.geolocation.getCurrentPosition(
        (pos) => {
          lastPos = {
            lat: pos.coords.latitude,
            lng: pos.coords.longitude,
          };
          resolve(lastPos);
        },
        () => resolve(null),
        { enableHighAccuracy: true, timeout: 10000, maximumAge: 120000 }
      );
    });
  }

  function fromSuggestList(query) {
    const mine = myLocationPlace();
    const q = fold(query);
    const hits =
      q.length >= 2
        ? searchPlaces(query, 8).filter((p) => !p.isMyLocation)
        : [];
    // İl adı → tam ilçe listesi (büyükşehir dahil); kısaltma yok
    const cityDistrictList =
      hits.length >= 2 && hits.every((p) => fold(p.cityName) === q);
    const wantMine =
      !!mine &&
      (q.length < 2 ||
        fold(t("routeMyLocation")).startsWith(q) ||
        "konumum".startsWith(q) ||
        q.includes("konum") ||
        "mylocation".startsWith(q.replace(/\s/g, "")));
    if (wantMine) {
      const out = [mine, ...hits];
      return cityDistrictList ? out : out.slice(0, 8);
    }
    return cityDistrictList ? hits : hits.slice(0, 8);
  }

  /** Native / Cap bridge: serialize place for Swift */
  function mapPlaceForBridge(p) {
    if (!p) return null;
    return {
      label: p.label || "",
      cityName: p.cityName || "",
      districtName: p.districtName || "",
      isMyLocation: !!p.isMyLocation,
      isMerkez: !!p.isMerkez,
      isMetropolitan: !!p.isMetropolitan || isMetropolitan(p.cityName),
      nearLabel: p.nearLabel || "",
      lat: p.lat != null ? Number(p.lat) : null,
      lng: p.lng != null ? Number(p.lng) : null,
      districtId: p.districtId != null ? String(p.districtId) : "",
    };
  }

  async function nominatimSearchPlaces(query, limit = 12) {
    const t = String(query || "").trim();
    if (t.length < 2) return [];
    try {
      const lang =
        (typeof window.__etubuLang === "string" && window.__etubuLang) ||
        (typeof I18n !== "undefined" ? I18n.lang : "en") ||
        "en";
      const url =
        "https://nominatim.openstreetmap.org/search?format=json&limit=" +
        encodeURIComponent(String(limit)) +
        "&q=" +
        encodeURIComponent(t);
      const res = await fetch(url, {
        headers: {
          "Accept-Language": lang,
          "User-Agent": "Etubu/1.0 (com.etubu.app)",
        },
      });
      if (!res.ok) return [];
      const arr = await res.json();
      return (arr || []).map((hit) => ({
        cityId: "",
        cityName: "",
        districtId: "",
        districtName: "",
        lat: Number(hit.lat),
        lng: Number(hit.lon),
        label: hit.display_name || t,
        isMerkez: false,
        search: fold(hit.display_name || t),
        isMyLocation: false,
      }));
    } catch (_) {
      return [];
    }
  }

  async function suggestForBridge(query, forFrom) {
    if (!EtubuRegionHint.inTurkey()) {
      const hits = await nominatimSearchPlaces(query, 12);
      if (forFrom) {
        const mine = myLocationPlace();
        if (mine) return [mapPlaceForBridge(mine), ...hits.map(mapPlaceForBridge)].filter(Boolean);
      }
      return hits.map(mapPlaceForBridge);
    }
    await buildPlaceIndex().catch(() => {});
    const q = fold(query);
    // Cap / native: higher limit so city → full districts, district → city+district
    const hits = forFrom
      ? fromSuggestList(query || "")
      : q.length >= 2
        ? searchPlaces(query, 40)
        : [];
    return hits.map(mapPlaceForBridge);
  }

  async function resolveForBridge(text) {
    if (!EtubuRegionHint.inTurkey()) {
      const hits = await nominatimSearchPlaces(text, 1);
      return mapPlaceForBridge(hits[0] || null);
    }
    await buildPlaceIndex().catch(() => {});
    return mapPlaceForBridge(resolvePlace(text));
  }

  function showSuggest(el, items, onPick) {
    if (!el) return;
    if (!items.length) {
      el.hidden = true;
      el.innerHTML = "";
      return;
    }
    el.hidden = false;
    el.innerHTML = items
      .map(
        (p, i) =>
          `<button type="button" class="route-suggest-item${p.isMyLocation ? " route-suggest-item--here" : ""}" data-i="${i}">${p.label}${
            p.isMyLocation && p.nearLabel
              ? ` <small>${p.nearLabel}</small>`
              : ""
          }</button>`
      )
      .join("");
    el.querySelectorAll(".route-suggest-item").forEach((btn) => {
      btn.addEventListener("mousedown", (e) => {
        e.preventDefault();
        onPick(items[Number(btn.dataset.i)]);
      });
    });
  }

  function bindAutocomplete(input, suggestEl, setPlace) {
    let timer = null;
    const isFrom = () => input === fromInput;
    const pick = (p) => {
      input.value = p.label;
      setPlace(p);
      suggestEl.hidden = true;
      syncGo();
    };
    input?.addEventListener("input", () => {
      setPlace(null);
      clearTimeout(timer);
      timer = setTimeout(async () => {
        await buildPlaceIndex().catch(() => {});
        const hits = isFrom()
          ? fromSuggestList(input.value)
          : searchPlaces(input.value, 8);
        showSuggest(suggestEl, hits, pick);
      }, 120);
    });
    input?.addEventListener("focus", () => {
      expandUi();
      const hits = isFrom()
        ? fromSuggestList(input.value)
        : fold(input.value).length >= 2
          ? searchPlaces(input.value, 8)
          : [];
      if (hits.length) showSuggest(suggestEl, hits, pick);
    });
    input?.addEventListener("blur", () => {
      setTimeout(() => {
        if (suggestEl) suggestEl.hidden = true;
        if (!getPlaceForInput(input)) {
          if (isFrom() && (!fold(input.value) || fold(input.value) === fold(t("routeMyLocation")))) {
            applyMyLocationAsFrom();
            return;
          }
          if (fold(input.value).length >= 2) {
            const p = resolvePlace(input.value);
            if (p) {
              input.value = p.label;
              setPlace(p);
              syncGo();
            }
          }
        }
      }, 150);
    });
    input?.addEventListener("keydown", (e) => {
      if (e.key === "Enter") {
        e.preventDefault();
        const p = isFrom() && !fold(input.value)
          ? myLocationPlace()
          : resolvePlace(input.value);
        if (p) {
          input.value = p.label;
          setPlace(p);
          suggestEl.hidden = true;
          syncGo();
          if (fromPlace && toPlace) buildRoute();
        }
      }
    });
  }

  function getPlaceForInput(input) {
    if (input === fromInput) return fromPlace;
    if (input === toInput) return toPlace;
    return null;
  }

  function syncGo() {
    if (!goBtn) return;
    const toNeeds = toInput?.value ? needsDistrictPick(toInput.value) : false;
    const fromNeeds = fromInput?.value ? needsDistrictPick(fromInput.value) : false;
    goBtn.disabled = !(fromPlace && toPlace) || toNeeds || fromNeeds;
  }

  function setPeeks({ brief, form }) {
    if (briefPeek) briefPeek.hidden = !brief;
    if (formPeek) formPeek.hidden = !form;
  }

  function clearMotionTimer() {
    if (motionHideTimer) {
      clearTimeout(motionHideTimer);
      motionHideTimer = null;
    }
  }

  function clearDetailsCloseTimer() {
    if (detailsCloseTimer) {
      clearTimeout(detailsCloseTimer);
      detailsCloseTimer = null;
    }
  }

  function armDetailsAutoClose() {
    clearDetailsCloseTimer();
    detailsCloseTimer = setTimeout(() => {
      detailsCloseTimer = null;
      const det = briefEl?.querySelector("#routeBriefDetails");
      if (det) det.open = false;
    }, DETAILS_AUTO_CLOSE_MS);
  }

  function enrichFromHazards() {
    const charges = hazards.filter((h) => h.kind === "charge");
    const weather = hazards.filter((h) => h.kind === "weather");
    return {
      chargeCount: charges.length,
      weatherCount: weather.length,
      chargeNames: charges.map((c) => c.name || c.label).filter(Boolean),
      weatherLabels: weather.map((w) => w.label).filter(Boolean),
    };
  }

  function isCriticalPassed(userIdx, lat, lng, heading, h) {
    const d = haversineM(lat, lng, h.lat, h.lng);
    if (d <= PASS_TOUCH_M) touchedCritical.add(h.id);

    if (touchedCritical.has(h.id) && d > PASS_CLEAR_M) return true;

    if (userIdx <= h.routeIdx) return false;

    if (heading != null && Number.isFinite(heading)) {
      const b = bearingDeg(lat, lng, h.lat, h.lng);
      // Nokta araçın arkasında ve rota indeksini geçtik
      if (angleDiff(b, heading) > 100 && userIdx > h.routeIdx) return true;
    } else if (userIdx > h.routeIdx + 8 && d > 150) {
      return true;
    }
    return false;
  }

  function prunePassedCritical(lat, lng, heading) {
    if (!hazards.length || !routeCoords.length) return false;
    const userNear = nearestRouteIdx(routeCoords, lat, lng);
    let removed = false;
    const next = [];
    for (const h of hazards) {
      if (h.kind !== "charge" && h.kind !== "weather") {
        next.push(h);
        continue;
      }
      if (isCriticalPassed(userNear.idx, lat, lng, heading, h)) {
        removed = true;
        touchedCritical.delete(h.id);
        continue;
      }
      next.push(h);
    }
    if (removed) hazards = next;
    return removed;
  }

  function hidePanelsAfterMotion() {
    panelsAutoHidden = true;
    collapsed = true;
    clearDetailsCloseTimer();
    fromSuggest && (fromSuggest.hidden = true);
    toSuggest && (toSuggest.hidden = true);
    if (briefEl) briefEl.hidden = true;
    if (formEl) formEl.hidden = true;
    if (root) {
      root.classList.add("is-collapsed", "is-drive-hidden");
      // Form kapalıyken kökü de gizle — peek buton yeterli
      root.hidden = true;
    }
    setPeeks({
      brief: !!briefing,
      form: isTurkeyTurkish(),
    });
  }

  function armMotionHide() {
    if (panelsAutoHidden || motionHideTimer) return;
    motionHideTimer = setTimeout(() => {
      motionHideTimer = null;
      hidePanelsAfterMotion();
    }, MOTION_HIDE_MS);
  }

  function noteMotion(kmh) {
    if (panelsAutoHidden) return;
    if ((kmh || 0) < MOTION_KMH) return;
    const briefOpen = briefEl && !briefEl.hidden;
    const formOpen = root && !root.hidden && formEl && !formEl.hidden;
    if (!briefOpen && !formOpen) return;
    armMotionHide();
  }

  function openBriefPanel() {
    if (!briefing || !isTurkeyTurkish()) return;
    clearMotionTimer();
    panelsAutoHidden = false;
    renderBrief(briefing, briefEnrich || enrichFromHazards(), {
      forceShow: true,
      openDetails: true,
    });
    if (briefPeek) briefPeek.hidden = true;
  }

  function openFormPanel() {
    if (!isTurkeyTurkish()) return;
    clearMotionTimer();
    panelsAutoHidden = false;
    collapsed = false;
    if (root) {
      root.hidden = false;
      root.classList.remove("is-collapsed", "is-drive-hidden");
    }
    if (formEl) formEl.hidden = false;
    if (formPeek) formPeek.hidden = true;
  }

  function expandUi() {
    openFormPanel();
  }

  function collapseUi() {
    hidePanelsAfterMotion();
  }

  function renderBrief(data, enrich, opts = {}) {
    if (!briefEl) return;
    if (!data) {
      clearDetailsCloseTimer();
      briefEnrich = null;
      briefEl.hidden = true;
      briefEl.innerHTML = "";
      return;
    }
    if (enrich) briefEnrich = enrich;
    const e = briefEnrich || {
      chargeCount: 0,
      weatherCount: 0,
      chargeNames: [],
      weatherLabels: [],
    };
    const chargeN = e.chargeCount ?? 0;
    const weatherN = e.weatherCount ?? 0;
    const names = (e.chargeNames || []).slice(0, 4);
    const wxLabels = (e.weatherLabels || []).slice(0, 4);
    const keepHidden = panelsAutoHidden && !opts.forceShow;
    const prevDetails = briefEl.querySelector("#routeBriefDetails");
    const detailsOpen =
      opts.openDetails === true ||
      (opts.openDetails !== false && prevDetails != null && prevDetails.open);

    const chargeBlock = chargeN
      ? `<div class="route-brief-charge">
          <strong>${t("routeChargeCount", { n: chargeN })}</strong>
          ${names.length ? `<span>${names.join(" · ")}</span>` : `<span>${t("routeChargeHint")}</span>`}
        </div>`
      : `<div class="route-brief-charge route-brief-charge--empty"><strong>${t("routeChargeNone")}</strong></div>`;
    const weatherBlock =
      weatherN > 0
        ? `<div class="route-brief-weather">
            <strong>${t("routeWeatherCount", { n: weatherN })}</strong>
            ${wxLabels.length ? `<span>${wxLabels.join(" · ")}</span>` : ""}
          </div>`
        : "";

    briefEl.hidden = keepHidden;
    briefEl.innerHTML = `
      <button type="button" class="route-brief-close" id="routeBriefClose" aria-label="${t("paywallClose")}">×</button>
      <div class="route-brief-cards">
        <div><em>${data.RadarCount ?? 0}</em><span>${t("routeRadar")}</span></div>
        <div><em>${data.ControlPointCount ?? 0}</em><span>${t("routeControl")}</span></div>
        <div><em>${data.CorridorCount ?? 0}</em><span>${t("radarCorridor")}</span></div>
        <div class="route-brief-card--charge"><em>${chargeN}</em><span>${t("routeCharge")}</span></div>
        <div><em>${weatherN}</em><span>${t("routeWeatherShort")}</span></div>
      </div>
      <details class="route-brief-details" id="routeBriefDetails"${detailsOpen ? " open" : ""}>
        <summary>${t("routeBriefDetails")}</summary>
        <div class="route-brief-details-body">
          ${chargeBlock}
          ${weatherBlock}
        </div>
      </details>
      <p class="route-brief-note">${t("routeBriefHint")}</p>`;
    briefEl.querySelector("#routeBriefClose")?.addEventListener("click", () => {
      clearDetailsCloseTimer();
      briefEl.hidden = true;
      if (briefPeek) briefPeek.hidden = false;
    });
    const detailsEl = briefEl.querySelector("#routeBriefDetails");
    detailsEl?.addEventListener("toggle", () => {
      if (detailsEl.open) armDetailsAutoClose();
      else clearDetailsCloseTimer();
    });
    if (!keepHidden && detailsOpen) armDetailsAutoClose();
  }

  function setPulse(text, kind) {
    if (!text) {
      lastPulse = null;
      return;
    }
    lastPulse = { text, kind: kind || "warn" };
  }

  function nearestRouteIdx(coords, lat, lng) {
    let best = { d: Infinity, idx: 0 };
    const step = Math.max(1, Math.floor(coords.length / 500));
    for (let i = 0; i < coords.length; i += step) {
      const [x, y] = coords[i];
      const d = haversineM(lat, lng, y, x);
      if (d < best.d) best = { d, idx: i };
    }
    return best;
  }

  function sampleAlongRoute(coords, everyM = 28000) {
    if (!coords.length) return [];
    const out = [{ lat: coords[0][1], lng: coords[0][0], idx: 0 }];
    let acc = 0;
    for (let i = 1; i < coords.length; i++) {
      const [lng0, lat0] = coords[i - 1];
      const [lng1, lat1] = coords[i];
      acc += haversineM(lat0, lng0, lat1, lng1);
      if (acc >= everyM) {
        out.push({ lat: lat1, lng: lng1, idx: i });
        acc = 0;
      }
    }
    const last = coords[coords.length - 1];
    out.push({ lat: last[1], lng: last[0], idx: coords.length - 1 });
    return out;
  }

  function parseOfficialHazards(data, coords) {
    const list = [];
    (data.Radars || []).forEach((r) => {
      if (r.activity != null && r.activity !== 3) return;
      const lat = r.y ?? r.lat;
      const lng = r.x ?? r.lng;
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) return;
      const near = nearestRouteIdx(coords, lat, lng);
      if (near.d > 2500) return;
      list.push({
        id: `radar-${r.id || `${lat}-${lng}`}`,
        kind: "radar",
        lat,
        lng,
        label: r.name || t("routeRadar"),
        maxspeed: r.speedLimit || null,
        routeIdx: near.idx,
      });
    });
    (data.SpeedTunnels || []).forEach((tun) => {
      if (tun.activity != null && tun.activity !== 3) return;
      const lat = tun.startLatY;
      const lng = tun.startLonX;
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) return;
      const near = nearestRouteIdx(coords, lat, lng);
      if (near.d > 3500) return;
      list.push({
        id: `corridor-${tun.id || `${lat}-${lng}`}`,
        kind: "corridor",
        lat,
        lng,
        label: tun.name || t("radarCorridor"),
        maxspeed: tun.speedLimit || null,
        lengthKm: tun.length || null,
        routeIdx: near.idx,
      });
    });
    return list;
  }

  function parseSeedHazards(coords) {
    // Caller already gated on domestic route coords — don't require forceTr
    // (Cap flag can lag first GPS fix after overseas cold start).
    const seeds =
      typeof RadarAlert !== "undefined" && RadarAlert.getCameras
        ? RadarAlert.getCameras()
        : [];
    const list = [];
    for (const cam of seeds) {
      const near = nearestRouteIdx(coords, cam.lat, cam.lng);
      // Highway geometry can sit 1–3 km off seed pins — keep generous match
      const maxD = cam.type === "corridor" ? 3500 : 2800;
      if (near.d > maxD) continue;
      list.push({
        id: cam.id || `seed-${cam.lat}-${cam.lng}`,
        kind: cam.type === "corridor" ? "corridor" : "radar",
        lat: cam.lat,
        lng: cam.lng,
        label: cam.label || t("routeRadar"),
        maxspeed: cam.maxspeed,
        routeIdx: near.idx,
      });
    }
    return list;
  }

  /** OSM Overpass — uluslararası rota uyarıları (speed_camera / average_speed). */
  async function fetchOverpassCamerasAlong(coords) {
    const samples = sampleAlongRoute(coords, 45000).slice(0, 8);
    if (!samples.length) return [];
    const endpoints = [
      "https://overpass-api.de/api/interpreter",
      "https://overpass.kumi.systems/api/interpreter",
    ];
    const radiusM = 12000;
    const out = [];
    await Promise.all(
      samples.map(async (s) => {
        const q =
          `[out:json][timeout:15];(` +
          `node["highway"="speed_camera"](around:${radiusM},${s.lat},${s.lng});` +
          `node["enforcement"="maxspeed"](around:${radiusM},${s.lat},${s.lng});` +
          `node["enforcement"="average_speed"](around:${radiusM},${s.lat},${s.lng});` +
          `node["camera:type"="section"](around:${radiusM},${s.lat},${s.lng});` +
          `);out body;`;
        for (const url of endpoints) {
          try {
            const ctrl = new AbortController();
            const timer = setTimeout(() => ctrl.abort(), 14000);
            const res = await fetch(url, {
              method: "POST",
              headers: { "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8" },
              body: "data=" + encodeURIComponent(q),
              signal: ctrl.signal,
            });
            clearTimeout(timer);
            if (!res.ok) continue;
            const json = await res.json();
            for (const el of json?.elements || []) {
              const lat = Number(el.lat);
              const lng = Number(el.lon);
              if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue;
              const tags = el.tags || {};
              const isCorridor =
                tags.enforcement === "average_speed" ||
                tags["camera:type"] === "section" ||
                tags.traffic_sign === "average_speed";
              const near = nearestRouteIdx(coords, lat, lng);
              const maxD = isCorridor ? 3500 : 2800;
              if (near.d > maxD) continue;
              out.push({
                id: `osm-${el.id || `${lat}-${lng}`}`,
                kind: isCorridor ? "corridor" : "radar",
                lat,
                lng,
                label: isCorridor ? t("radarCorridor") : t("routeRadar"),
                maxspeed: tags.maxspeed ? parseInt(tags.maxspeed, 10) : null,
                routeIdx: near.idx,
              });
            }
            return;
          } catch (_) {
            /* try next endpoint */
          }
        }
      })
    );
    return out;
  }

  async function fetchOverpassCharging(coords) {
    // Artık sunucu proxy (api/chargers.php) kullanılıyor — istemci Overpass yok
    return [];
  }

  async function fetchOcmCharging(coords) {
    const samples = sampleAlongRoute(coords, 70000).slice(0, 5);
    if (!samples.length) return [];
    try {
      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(), 12000);
      const res = await fetch(CHARGERS_PROXY, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          distance: 40,
          points: samples.map((s) => ({ lat: s.lat, lng: s.lng })),
        }),
        signal: ctrl.signal,
      });
      clearTimeout(timer);
      if (!res.ok) return [];
      const json = await res.json();
      if (!json?.ok || !Array.isArray(json.chargers)) return [];
      const list = [];
      for (const c of json.chargers) {
        const lat = Number(c.lat);
        const lng = Number(c.lng);
        if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue;
        const near = nearestRouteIdx(coords, lat, lng);
        if (near.d > 5000) continue;
        list.push({
          id: c.id || `ocm-${lat}-${lng}`,
          kind: "charge",
          lat,
          lng,
          label: c.label || c.name || t("routeCharge"),
          name: c.name || t("routeCharge"),
          routeIdx: near.idx,
          distOffRoute: near.d,
          source: c.source || "ocm",
          kw: c.kw || 0,
        });
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  async function fetchChargingAlong(coords) {
    return fetchOcmCharging(coords);
  }

  function weatherLabel(code, wind) {
    if ([95, 96, 97, 98, 99].includes(code)) return t("routeWeatherStorm");
    if ([65, 66, 67, 82].includes(code)) return t("routeWeatherRain");
    if ([75, 77, 85, 86].includes(code)) return t("routeWeatherSnow");
    if ([45, 48].includes(code)) return t("routeWeatherFog");
    if (wind >= 70) return t("routeWeatherWind");
    return t("routeWeatherSevere");
  }

  async function fetchWeatherAlong(coords) {
    const samples = sampleAlongRoute(coords, 90000).slice(0, 3);
    if (!samples.length) return [];
    const list = [];
    await Promise.all(
      samples.map(async (s) => {
        try {
          const ctrl = new AbortController();
          const timer = setTimeout(() => ctrl.abort(), 5000);
          const url =
            `https://api.open-meteo.com/v1/forecast?latitude=${s.lat}&longitude=${s.lng}` +
            `&current=weather_code,precipitation,wind_speed_10m&timezone=Europe%2FIstanbul`;
          const res = await fetch(url, { signal: ctrl.signal });
          clearTimeout(timer);
          if (!res.ok) return;
          const j = await res.json();
          const cur = j.current || {};
          const code = Number(cur.weather_code);
          const wind = Number(cur.wind_speed_10m) || 0;
          const precip = Number(cur.precipitation) || 0;
          const severe =
            WEATHER_SEVERE.has(code) || wind >= 70 || precip >= 8 || code === 45 || code === 48;
          if (!severe) return;
          list.push({
            id: `wx-${s.idx}-${code}`,
            kind: "weather",
            lat: s.lat,
            lng: s.lng,
            label: weatherLabel(code, wind),
            routeIdx: s.idx,
          });
        } catch (_) {}
      })
    );
    return list;
  }

  function mergeHazards(...groups) {
    const byId = new Map();
    for (const g of groups) {
      for (const h of g) {
        if (!byId.has(h.id)) byId.set(h.id, h);
      }
    }
    return [...byId.values()].sort((a, b) => a.routeIdx - b.routeIdx);
  }

  async function enrichRouteAsync(data, coords, baseHazards) {
    try {
      const [charging, weather] = await Promise.all([
        fetchChargingAlong(coords),
        fetchWeatherAlong(coords),
      ]);
      // Eski / temizlenmiş rota için güncelleme yapma
      if (!active || briefing !== data) return;
      hazards = mergeHazards(baseHazards, charging, weather);
      renderBrief(data, enrichFromHazards());
      if (typeof MiniMap !== "undefined") {
        if (MiniMap.setHazards) MiniMap.setHazards(hazards);
        else if (MiniMap.setRoute) MiniMap.setRoute(coords, hazards);
      }
    } catch (_) {}
  }

  async function buildRoute() {
    const fromIsMine =
      fromPlace?.isMyLocation ||
      fold(fromInput?.value || "") === fold(t("routeMyLocation")) ||
      fold(fromInput?.value || "") === "konumum";
    if (fromIsMine) {
      await requestMyLocationOnce();
      applyMyLocationAsFrom();
    }
    if (!fromPlace) {
      fromPlace = resolvePlace(fromInput?.value || "");
    }
    if (!toPlace) {
      toPlace = resolvePlace(toInput?.value || "");
    }
    if (!fromPlace || !toPlace) {
      const typed =
        fold(fromInput?.value || "").length >= 2 || fold(toInput?.value || "").length >= 2;
      setStatus(
        fromIsMine && !fromPlace ? t("gpsNeeded") + t("routeMyLocation") : typed ? t("routeFail") : t("routeNeedBoth")
      );
      return;
    }
    if (fromInput) fromInput.value = fromPlace.label;
    if (toInput) toInput.value = toPlace.label;
    goBtn.disabled = true;
    setStatus(t("routeBuilding"));
    expandUi();
    try {
      ensureBeepCtx();
      const domestic = isDomesticRoute(fromPlace, toPlace);
      let json = null;
      if (domestic) {
        try {
          json = await proxyPost({
            action: "createRoute",
            fromLatitude: String(fromPlace.lat),
            fromLongitude: String(fromPlace.lng),
            toLatitude: String(toPlace.lat),
            toLongitude: String(toPlace.lng),
            fromDistrictId: String(fromPlace.districtId),
            toDistrictId: String(toPlace.districtId),
            fromLabel: fromPlace.label || "",
            toLabel: toPlace.label || "",
          });
        } catch (_) {
          json = null;
        }
      }
      let data = json?.ok && json.data ? json.data : null;
      if (!data?.Coordinates?.length) {
        // Yurt dışı veya EGM düşerse — OSRM (OSM routing)
        data = await fetchOsrmRoute(fromPlace, toPlace);
      }
      attachRouteCities(data);
      briefing = data;
      const coords = (data.Coordinates || []).map((c) => [c.x, c.y]);
      if (!coords.length) throw new Error("noroute");
      routeCoords = coords;

      // TR: resmi + seed; yurt dışı: OSM Overpass kameraları
      const official = domestic ? parseOfficialHazards(data, coords) : [];
      const seeds = domestic ? parseSeedHazards(coords) : [];
      let baseHazards = mergeHazards(official, seeds);
      if (!domestic || !baseHazards.length) {
        try {
          const osmCams = await fetchOverpassCamerasAlong(coords);
          baseHazards = mergeHazards(baseHazards, osmCams);
        } catch (_) {}
      }
      hazards = baseHazards;
      active = true;
      lastAlertKey = "";
      touchedCritical = new Set();
      briefEnrich = {
        chargeCount: 0,
        weatherCount: 0,
        chargeNames: [],
        weatherLabels: [],
      };
      clearMotionTimer();
      clearDetailsCloseTimer();
      panelsAutoHidden = false;
      if (root) {
        root.hidden = !isTurkeyTurkish();
        root.classList.remove("is-collapsed", "is-drive-hidden");
      }
      if (formEl) formEl.hidden = false;
      setPeeks({ brief: false, form: false });
      renderBrief(data, briefEnrich, { forceShow: true, openDetails: true });
      if (typeof MiniMap !== "undefined" && MiniMap.setRoute) {
        MiniMap.setRoute(coords, hazards);
      }
      // Ensure markers paint even if setRoute raced before layout
      if (typeof MiniMap !== "undefined" && MiniMap.setHazards) {
        MiniMap.setHazards(hazards);
      }
      setStatus("");
      playBeeps(2, false);

      try {
        sessionStorage.setItem(
          "etubu_route_last",
          JSON.stringify({
            fromLabel: fromPlace.label,
            toLabel: toPlace.label,
            from: fromPlace,
            to: toPlace,
          })
        );
      } catch (_) {}

      // Şarj + hava arka planda (UI'yi bekletmez)
      enrichRouteAsync(data, coords, baseHazards);
    } catch (e) {
      console.warn("RouteGuard", e);
      setStatus(t("routeServiceFail"));
      active = false;
      hazards = [];
      routeCoords = [];
      briefing = null;
      renderBrief(null);
      setPulse("", null);
      if (typeof MiniMap !== "undefined") MiniMap.clearRoute?.();
    } finally {
      syncGo();
    }
  }

  function clearRoute(persist = true) {
    active = false;
    routeCoords = [];
    hazards = [];
    briefing = null;
    briefEnrich = null;
    touchedCritical = new Set();
    lastAlertKey = "";
    toPlace = null;
    clearMotionTimer();
    clearDetailsCloseTimer();
    panelsAutoHidden = false;
    if (toInput) toInput.value = "";
    // Nereden varsayılanı: Konumum
    if (!applyMyLocationAsFrom()) {
      fromPlace = null;
      if (fromInput) fromInput.value = t("routeMyLocation");
    }
    renderBrief(null);
    setPulse("", null);
    setStatus("");
    setPeeks({ brief: false, form: false });
    if (typeof MiniMap !== "undefined") MiniMap.clearRoute?.();
    if (root) {
      root.hidden = !isTurkeyTurkish();
      root.classList.remove("is-collapsed", "is-drive-hidden");
    }
    if (formEl) formEl.hidden = false;
    syncGo();
    if (persist) {
      try {
        sessionStorage.removeItem("etubu_route_last");
      } catch (_) {}
    }
  }

  function hazardPriority(kind) {
    // Düşük sayı = daha kritik (radar/koridor her zaman şarj ve havadan önce)
    if (kind === "corridor" || kind === "radar") return 0;
    if (kind === "charge") return 1;
    if (kind === "weather") return 2;
    return 3;
  }

  function nearestAhead(lat, lng, heading) {
    let best = null;
    for (const h of hazards) {
      const d = haversineM(lat, lng, h.lat, h.lng);
      // Şarj: 5 km kala HUD uyarısı; radar/koridor ~5.5 km; hava daha geniş
      const maxD =
        h.kind === "weather" ? 12000 : h.kind === "charge" ? 5000 : 5500;
      if (d > maxD) continue;
      if (heading != null && Number.isFinite(heading) && h.kind !== "weather") {
        const b = bearingDeg(lat, lng, h.lat, h.lng);
        // Şarj için biraz daha geniş açı — yan yoldaki istasyon kaçmasın
        const tol = h.kind === "charge" ? 75 : 58;
        if (angleDiff(b, heading) > tol) continue;
      }
      const pri = hazardPriority(h.kind);
      if (
        !best ||
        pri < best.pri ||
        (pri === best.pri && d < best.d)
      ) {
        best = { h, d, pri };
      }
    }
    return best;
  }

  /** Sıradaki kritik noktalar (makara / reel) — öncelik + mesafe */
  function listAhead(lat, lng, heading, limit = 4) {
    const list = [];
    for (const h of hazards) {
      const d = haversineM(lat, lng, h.lat, h.lng);
      // Radar/koridor: uzak mesafede de tabloda görünsün (basamaklı km)
      const maxD =
        h.kind === "weather" ? 12000 : h.kind === "charge" ? 5000 : 80000;
      if (d > maxD) continue;
      if (heading != null && Number.isFinite(heading) && h.kind !== "weather") {
        const b = bearingDeg(lat, lng, h.lat, h.lng);
        const tol = h.kind === "charge" ? 75 : 58;
        // Uzak radar/koridor (>5.5 km): açı filtresi gevşek — ilk uyarı kaçmasın
        if (d <= 5500 && angleDiff(b, heading) > tol) continue;
      }
      const stage =
        STAGES.find((s) => d <= s.max)?.key ||
        (d <= 80000 ? "far" : null);
      if (!stage) continue;
      list.push({
        id: h.id || `${h.kind}-${h.lat},${h.lng}`,
        kind: pulseKind(h),
        title:
          h.kind === "charge"
            ? t("hudChargeWarn")
            : h.kind === "weather"
              ? h.label || t("hudRoadWarn")
              : h.kind === "corridor"
                ? t("radarCorridor")
                : t("routeRadar"),
        dist: formatDist(d),
        distM: d,
        meta: h.label || h.name || "",
        stage,
        pri: hazardPriority(h.kind),
      });
    }
    // Radar + hız koridoru her zaman önce
    list.sort((a, b) => a.pri - b.pri || a.distM - b.distM);
    return list.slice(0, limit);
  }

  function pulseKind(h) {
    if (h.kind === "charge") return "charge";
    if (h.kind === "weather") return "weather";
    if (h.kind === "corridor") return "corridor";
    return "radar";
  }

  function update(lat, lng, heading, kmh) {
    if (lat != null && lng != null && Number.isFinite(lat)) {
      lastPos = { lat, lng };
      // Konumum seçiliyse koordinatı canlı tut
      if (fromPlace?.isMyLocation) {
        const refreshed = myLocationPlace();
        if (refreshed) fromPlace = refreshed;
      } else if (
        !fromPlace &&
        fromInput &&
        fold(fromInput.value) === fold(t("routeMyLocation"))
      ) {
        applyMyLocationAsFrom();
      }
    }
    noteMotion(kmh);

    if (!active || !hazards.length) {
      if (!active) setPulse("", null);
      return { pulse: lastPulse, queue: [] };
    }
    if (lat == null || lng == null || !Number.isFinite(lat)) {
      return { pulse: lastPulse, queue: [] };
    }

    if (prunePassedCritical(lat, lng, heading)) {
      renderBrief(briefing, enrichFromHazards());
      if (typeof MiniMap !== "undefined" && MiniMap.setHazards) {
        MiniMap.setHazards(hazards);
      }
    }

    const ahead = nearestAhead(lat, lng, heading);
    if (!ahead) {
      setPulse("", null);
      return { pulse: null, queue: [] };
    }
    const stage =
      STAGES.find((s) => ahead.d <= s.max) ||
      (ahead.h.kind === "weather" && ahead.d <= 12000 ? { key: "far", beeps: 0 } : null);
    if (!stage) {
      setPulse("", null);
      return { pulse: null, queue: [] };
    }

    const label =
      ahead.h.kind === "charge"
        ? t("routeChargePulse", {
            name: ahead.h.name || ahead.h.label || t("routeCharge"),
            dist: formatDist(ahead.d),
          })
        : ahead.h.kind === "weather"
          ? `${ahead.h.label} · ${formatDist(ahead.d)}`
          : ahead.h.kind === "corridor"
            ? `${t("radarCorridor")} · ${formatDist(ahead.d)}`
            : `${t("routeRadar")} · ${formatDist(ahead.d)}`;
    setPulse(label, pulseKind(ahead.h));
    const phrase = alertPhrase(ahead.h, stage, formatDist(ahead.d));
    // Radar/corridor TTS lives in RadarAlert; RouteGuard speaks charge + severe weather
    const shouldSpeak =
      (ahead.h.kind === "weather" &&
        (stage.key === "far" ||
          stage.key === "mid" ||
          stage.key === "near" ||
          stage.key === "critical")) ||
      (ahead.h.kind === "charge" &&
        (stage.key === "mid" || stage.key === "near" || stage.key === "critical")) ||
      // If RadarAlert missing, still speak radar/corridor from route guard
      ((ahead.h.kind === "radar" || ahead.h.kind === "corridor") &&
        typeof RadarAlert === "undefined");
    alertBeep(`${ahead.h.id}-${stage.key}`, stage, shouldSpeak ? phrase : "");

    let chargeMeta = "";
    if (ahead.h.kind === "charge") {
      const bits = [];
      if (ahead.h.name) bits.push(ahead.h.name);
      if (ahead.h.kw > 0) bits.push(`${Math.round(ahead.h.kw)} kW`);
      if (ahead.h.label && ahead.h.label !== ahead.h.name && !ahead.h.name) {
        bits.push(ahead.h.label);
      }
      chargeMeta = bits.join(" · ") || ahead.h.label || "";
    }

    return {
      pulse: lastPulse,
      hazard: ahead.h,
      distM: ahead.d,
      stage: stage.key,
      title:
        ahead.h.kind === "charge"
          ? t("hudChargeWarn")
          : ahead.h.kind === "weather"
            ? ahead.h.label
            : ahead.h.kind === "corridor"
              ? t("radarCorridor")
              : t("routeRadar"),
      dist: formatDist(ahead.d),
      meta:
        ahead.h.kind === "charge"
          ? chargeMeta
          : ahead.h.label || ahead.h.name || "",
      kind: pulseKind(ahead.h),
      queue: listAhead(lat, lng, heading, 4),
    };
  }

  function syncVisibility() {
    if (!root) return;
    const show = isTurkeyTurkish();
    if (!show) {
      root.hidden = true;
      if (briefEl) briefEl.hidden = true;
      setPeeks({ brief: false, form: false });
      clearRoute(false);
      return;
    }
    if (!panelsAutoHidden) {
      root.hidden = false;
      setPeeks({ brief: false, form: false });
    } else {
      root.hidden = true;
      if (briefEl) briefEl.hidden = true;
      setPeeks({ brief: !!briefing, form: true });
    }
    buildPlaceIndex().catch(() => setStatus(t("routeCitiesFail")));
  }

  /** Re-apply route UI copy after language change */
  function refreshLocale() {
    if (fromInput) {
      fromInput.placeholder = t("routeFromPh");
      if (fromPlace?.isMyLocation) fromInput.value = t("routeMyLocation");
    }
    if (toInput) toInput.placeholder = t("routeToPh");
    if (briefing) renderBrief(briefing, briefEnrich);
    syncVisibility();
  }

  function restoreSaved() {
    try {
      const saved = JSON.parse(sessionStorage.getItem("etubu_route_last") || "null");
      if (saved?.to?.label && toInput) {
        toPlace = saved.to;
        toInput.value = saved.toLabel || saved.to.label;
      }
    } catch (_) {}
    // Nereden her zaman Konumum (varsayılan)
    if (!applyMyLocationAsFrom() && fromInput) {
      fromInput.value = t("routeMyLocation");
      fromInput.placeholder = t("routeFromPh");
    }
    syncGo();
  }

  function init() {
    root = document.getElementById("routeGuard");
    formEl = document.getElementById("routeForm");
    fromInput = document.getElementById("routeFromInput");
    toInput = document.getElementById("routeToInput");
    fromSuggest = document.getElementById("routeFromSuggest");
    toSuggest = document.getElementById("routeToSuggest");
    goBtn = document.getElementById("routeGoBtn");
    clearBtn = document.getElementById("routeClearBtn");
    statusEl = document.getElementById("routeStatus");
    briefEl = document.getElementById("routeBriefTop");
    briefPeek = document.getElementById("routeBriefPeek");
    formPeek = document.getElementById("routeFormPeek");
    pulseEl = null;
    pulseText = null;
    if (!root) return;

    bindAutocomplete(fromInput, fromSuggest, (p) => {
      fromPlace = p;
    });
    bindAutocomplete(toInput, toSuggest, (p) => {
      toPlace = p;
    });
    goBtn?.addEventListener("click", () => buildRoute());
    clearBtn?.addEventListener("click", () => clearRoute(true));
    briefPeek?.addEventListener("click", () => openBriefPanel());
    formPeek?.addEventListener("click", () => openFormPanel());
    bindKeyboardLift();

    if (fromInput) {
      fromInput.value = t("routeMyLocation");
      fromInput.placeholder = t("routeFromPh");
    }

    syncVisibility();
    document.addEventListener("etubu:lang-change", () => refreshLocale());
    if (isTurkeyTurkish()) {
      buildPlaceIndex()
        .then(async () => {
          restoreSaved();
          await requestMyLocationOnce();
          applyMyLocationAsFrom();
        })
        .catch(() => setStatus(t("routeCitiesFail")));
    }
  }

  /**
   * Yazımda rotayı kur kartını üste al.
   * Tesla/QtCarBrowser klavyeyi visualViewport ile bildirmez — odak = üstte sabitle.
   */
  function bindKeyboardLift() {
    if (!root || !fromInput || !toInput) return;
    let focused = false;
    let raf = 0;

    const clearLift = () => {
      root.classList.remove("is-keyboard");
      root.style.removeProperty("--kb-inset");
      root.style.removeProperty("top");
      root.style.removeProperty("bottom");
    };

    const ensureTop = () => {
      root.classList.add("is-keyboard");
      // Inline top: CSS class yetmezse (eski cache) yine üste çıksın
      const topBar = document.querySelector(".top-bar");
      const barH = topBar?.getBoundingClientRect?.().bottom || 52;
      const isCar =
        typeof CarBrowser !== "undefined" &&
        (CarBrowser.isTesla?.() || CarBrowser.isEphemeral?.());
      const topPx = isCar ? Math.max(8, Math.round(barH * 0.15)) : Math.round(barH + 6);
      root.style.top = `${topPx}px`;
      root.style.bottom = "auto";
    };

    const apply = () => {
      raf = 0;
      if (!focused) {
        clearLift();
        return;
      }
      ensureTop();
      const active = document.activeElement;
      if (active === fromInput || active === toInput) {
        try {
          active.scrollIntoView({ block: "nearest", inline: "nearest" });
        } catch (_) {}
      }
    };

    const schedule = () => {
      if (raf) return;
      raf = requestAnimationFrame(apply);
    };

    const onFocus = () => {
      focused = true;
      ensureTop();
      schedule();
      // Tesla / iOS: odak sonrası layout gecikmeli oturur
      setTimeout(schedule, 50);
      setTimeout(schedule, 180);
      setTimeout(schedule, 400);
    };
    const onBlur = () => {
      focused = false;
      setTimeout(() => {
        const a = document.activeElement;
        if (a === fromInput || a === toInput) {
          focused = true;
          ensureTop();
          schedule();
          return;
        }
        clearLift();
      }, 120);
    };

    fromInput.addEventListener("focus", onFocus);
    toInput.addEventListener("focus", onFocus);
    fromInput.addEventListener("blur", onBlur);
    toInput.addEventListener("blur", onBlur);
    // Tesla: odak bazen geç gelir — dokununca kartı şimdiden üste al
    const preemptTop = () => {
      ensureTop();
    };
    fromInput.addEventListener("pointerdown", preemptTop, { passive: true });
    toInput.addEventListener("pointerdown", preemptTop, { passive: true });

    if (window.visualViewport) {
      window.visualViewport.addEventListener("resize", schedule);
      window.visualViewport.addEventListener("scroll", schedule);
    }
    window.addEventListener("resize", schedule);
  }

  /** Cap / native: resolve labels then run the same buildRoute() as the web Go button. */
  async function buildRouteForBridge(fromLabel, toLabel) {
    await buildPlaceIndex().catch(() => {});
    const fromRaw = String(fromLabel || "").trim() || t("routeMyLocation");
    const toRaw = String(toLabel || "").trim();
    if (!toRaw || toRaw.length < 2) {
      return { ok: false, message: t("routeNeedBoth") };
    }
    const fromIsMine =
      fold(fromRaw) === fold(t("routeMyLocation")) ||
      fold(fromRaw) === "konumum" ||
      fold(fromRaw) === "my location";
    if (fromIsMine) {
      await requestMyLocationOnce();
      applyMyLocationAsFrom();
    } else {
      fromPlace = resolvePlace(fromRaw);
    }
    toPlace = resolvePlace(toRaw);
    if (!fromPlace) {
      return {
        ok: false,
        message: fromIsMine ? t("gpsNeeded") + t("routeMyLocation") : t("routeFail"),
      };
    }
    if (!toPlace) {
      return { ok: false, message: `${toRaw} — listeden seçin` };
    }
    if (fromInput) fromInput.value = fromPlace.label;
    if (toInput) toInput.value = toPlace.label;
    syncGo();
    try {
      await buildRoute();
      const activeNow = !!active;
      return {
        ok: activeNow,
        message: activeNow
          ? `${fromPlace.label} → ${toPlace.label}`
          : (statusEl?.textContent || t("routeFail") || "Rota kurulamadı"),
        from: fromPlace.label,
        to: toPlace.label,
        hazardCount: (hazards || []).length,
      };
    } catch (e) {
      return { ok: false, message: String(e && e.message ? e.message : e) || t("routeFail") };
    }
  }

  /**
   * Native planNative inject — stash + MiniMap yetmez; Cap listAhead/update aynı hazards’ı görsün.
   * payload: { from, to, coords:[{lat,lng}], hazards:[], brief?, navOnly? }
   */
  function applyNativeRoute(payload) {
    try {
      const p = payload || {};
      const coordsIn = Array.isArray(p.coords) ? p.coords : [];
      const hazIn = Array.isArray(p.hazards) ? p.hazards : [];
      routeCoords = coordsIn
        .map((c) => {
          const lat = Number(c.lat ?? c.y);
          const lng = Number(c.lng ?? c.x);
          if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
          return [lng, lat];
        })
        .filter(Boolean);
      hazards = hazIn
        .map((h) => {
          const lat = Number(h.lat);
          const lng = Number(h.lng);
          if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
          return {
            id: h.id || `${h.kind || "radar"}-${lat}-${lng}`,
            kind: h.kind || "radar",
            lat,
            lng,
            label: h.label || h.name || "",
            maxspeed: h.maxspeed != null ? Number(h.maxspeed) : null,
            kw: h.kw != null ? Number(h.kw) : null,
            routeIdx: h.routeIdx != null ? Number(h.routeIdx) : null,
            alongKm: h.alongKm != null ? Number(h.alongKm) : null,
          };
        })
        .filter(Boolean);
      active = routeCoords.length >= 2;
      touchedCritical = new Set();
      lastAlertKey = "";
      const b = p.brief || {};
      briefing = {
        Coordinates: routeCoords.map(([x, y]) => ({ x, y })),
        RadarCount: Number(b.radar) || hazards.filter((h) => h.kind === "radar").length,
        CorridorCount: Number(b.corridor) || hazards.filter((h) => h.kind === "corridor").length,
        ChargeCount: Number(b.charge) || hazards.filter((h) => h.kind === "charge").length,
        WeatherCount: Number(b.weather) || hazards.filter((h) => h.kind === "weather").length,
        ControlPointCount: Number(b.control) || 0,
        FromLabel: p.from || "",
        ToLabel: p.to || "",
      };
      briefEnrich = enrichFromHazards();
      renderBrief(briefing, briefEnrich);
      if (typeof MiniMap !== "undefined") {
        if (MiniMap.setRoute) MiniMap.setRoute(routeCoords, hazards);
        else if (MiniMap.setHazards) MiniMap.setHazards(hazards);
      }
      if (fromInput && p.from) fromInput.value = String(p.from);
      if (toInput && p.to) toInput.value = String(p.to);
      setStatus(
        active
          ? `${p.from || ""} → ${p.to || ""}`.replace(/^\s*→\s*/, "").trim()
          : ""
      );
      syncGo();
      return { ok: active, hazardCount: hazards.length };
    } catch (e) {
      console.warn("RouteGuard.applyNativeRoute", e);
      return { ok: false };
    }
  }

  return {
    init,
    syncVisibility,
    refreshLocale,
    update,
    listAhead,
    clear: () => clearRoute(true),
    isActive: () => active,
    isVisible: () => isTurkeyTurkish(),
    /** Cap / native cluster — same autocomplete & resolve as web UI */
    suggest: suggestForBridge,
    resolve: resolveForBridge,
    needsDistrictPick,
    searchPlaces,
    fromSuggestList,
    resolvePlace,
    buildPlaceIndex,
    buildRoute: buildRouteForBridge,
    applyNativeRoute,
  };
})();

// Cap / native eval uses window.RouteGuard — `const` is not a window property.
try {
  window.RouteGuard = RouteGuard;
} catch (_) {}
