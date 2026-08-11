/**
 * OSM Overpass — canlı sürüş kritik noktaları + yol hız limiti.
 * EGM/official birincil; OSM led (yurt dışı / EGM boş) veya supplement (TR gap fill).
 * RadarAlert kameralarından ayrı: daha sık yenileme, daha geniş tehlike türleri.
 */
const OsmHazards = (() => {
  const FETCH_RADIUS_M = 900;
  const REFETCH_DIST_M = 150;
  const REFETCH_AGE_MS = 60 * 1000;
  const DEDUPE_M = 70;
  const OVERPASS_URLS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
  ];

  /** Mesafe eşikleri (m) — normal / acil */
  const RULES = {
    radar: { warn: 350, critical: 120, label: "Radar", icon: "📸", kind: "radar" },
    corridor: { warn: 350, critical: 120, label: "Hız koridoru", icon: "🛣️", kind: "corridor" },
    railway: { warn: 250, critical: 80, label: "Demiryolu geçidi", icon: "🚂", kind: "railway" },
    traffic_light: { warn: 100, critical: 35, label: "Trafik lambası", icon: "🚦", kind: "traffic_light" },
    stop: { warn: 80, critical: 25, label: "Dur", icon: "🛑", kind: "stop" },
    give_way: { warn: 80, critical: 25, label: "Yol ver", icon: "⚠️", kind: "give_way" },
    crossing: { warn: 60, critical: 20, label: "Yaya geçidi", icon: "🚶", kind: "crossing" },
    bump: { warn: 60, critical: 20, label: "Tümsek", icon: "🔴", kind: "bump" },
  };

  let points = [];
  /** Official / EGM / route points — OSM bunları kesmez. */
  let officialPoints = [];
  let inTurkey = true;
  let roadMaxspeed = null;
  let fetchCenter = null;
  let fetchedAt = 0;
  let fetching = false;
  let urlIndex = 0;
  let lastSpokenId = "";
  let lastSpokenAt = 0;
  let lastFetchFailed = false;

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
    const φ1 = (lat1 * Math.PI) / 180;
    const φ2 = (lat2 * Math.PI) / 180;
    const Δλ = ((lon2 - lon1) * Math.PI) / 180;
    const y = Math.sin(Δλ) * Math.cos(φ2);
    const x =
      Math.cos(φ1) * Math.sin(φ2) -
      Math.sin(φ1) * Math.cos(φ2) * Math.cos(Δλ);
    return ((Math.atan2(y, x) * 180) / Math.PI + 360) % 360;
  }

  function angleDiff(a, b) {
    let d = Math.abs(a - b) % 360;
    return d > 180 ? 360 - d : d;
  }

  function isOsmId(id) {
    return typeof id === "string" && (id.startsWith("osm-") || id.startsWith("osmhz-"));
  }

  function isEnforcement(kind) {
    return kind === "radar" || kind === "corridor" || kind === "control";
  }

  function sameTypeFamily(a, b) {
    if (a === b) return true;
    const stop = { stop: 1, give_way: 1 };
    return !!(stop[a] && stop[b]);
  }

  function osmMode() {
    const officialEnforcement = (officialPoints || []).some(
      (p) => !isOsmId(p.id) && isEnforcement(p.kind || p.type)
    );
    if (!inTurkey) return "led";
    if (!officialEnforcement) return "led";
    return "supplement";
  }

  /**
   * Official wins on same-type proximity; OSM only fills gaps in supplement mode.
   */
  function mergeOfficialPrimary(official, osm, mode) {
    const out = (official || []).slice();
    for (const cand of osm || []) {
      const kind = cand.kind || cand.type;
      if (mode === "supplement" && isEnforcement(kind)) {
        const clash = out.some((o) => {
          const ok = o.kind || o.type;
          return (
            isEnforcement(ok) &&
            haversineM(o.lat, o.lng, cand.lat, cand.lng) <= DEDUPE_M
          );
        });
        if (clash) continue;
      }
      const dup = out.some(
        (o) =>
          sameTypeFamily(o.kind || o.type, kind) &&
          haversineM(o.lat, o.lng, cand.lat, cand.lng) <= DEDUPE_M
      );
      if (dup) continue;
      out.push(cand);
    }
    return out;
  }

  function setOfficialPoints(list, opts = {}) {
    officialPoints = Array.isArray(list) ? list.filter((p) => p && p.lat != null && p.lng != null) : [];
    if (typeof opts.inTurkey === "boolean") inTurkey = opts.inTurkey;
  }

  function setInTurkey(v) {
    inTurkey = !!v;
  }

  function classifyNode(tags) {
    if (!tags) return null;
    if (
      tags.highway === "speed_camera" ||
      tags.enforcement === "maxspeed" ||
      tags["camera:type"] === "speed"
    ) {
      return "radar";
    }
    if (
      tags.enforcement === "average_speed" ||
      tags["camera:type"] === "section" ||
      tags.traffic_sign === "average_speed"
    ) {
      return "corridor";
    }
    if (
      tags.railway === "level_crossing" ||
      tags.railway === "crossing" ||
      tags["crossing:barrier"] ||
      (tags.highway === "crossing" && tags.railway)
    ) {
      return "railway";
    }
    if (tags.highway === "traffic_signals" || tags.traffic_signals) {
      return "traffic_light";
    }
    if (tags.highway === "stop" || tags.traffic_sign === "stop") return "stop";
    if (
      tags.highway === "give_way" ||
      tags.traffic_sign === "give_way" ||
      tags.traffic_sign === "yield"
    ) {
      return "give_way";
    }
    if (
      tags.highway === "crossing" ||
      tags.crossing === "uncontrolled" ||
      tags.crossing === "zebra" ||
      tags.footway === "crossing"
    ) {
      return "crossing";
    }
    if (
      tags.traffic_calming === "bump" ||
      tags.traffic_calming === "hump" ||
      tags.traffic_calming === "table"
    ) {
      return "bump";
    }
    return null;
  }

  function parseMaxspeed(raw) {
    if (raw == null || raw === "") return null;
    const s = String(raw).toLowerCase().trim();
    if (s === "none" || s === "signals" || s === "walk") return null;
    const mph = /mph/.test(s);
    const n = parseInt(s.replace(/[^0-9]/g, ""), 10);
    if (!Number.isFinite(n) || n <= 0 || n > 200) return null;
    return mph ? Math.round(n * 1.609) : n;
  }

  function needsFetch(lat, lng) {
    const now = Date.now();
    if (!fetchCenter) return true;
    if (now - fetchedAt > REFETCH_AGE_MS) return true;
    const d = haversineM(lat, lng, fetchCenter.lat, fetchCenter.lng);
    return d >= REFETCH_DIST_M;
  }

  async function fetchAround(lat, lng) {
    if (fetching) return;
    if (!needsFetch(lat, lng)) return;
    fetching = true;
    const r = FETCH_RADIUS_M;
    const query = `[out:json][timeout:18];(
      node["highway"="speed_camera"](around:${r},${lat},${lng});
      node["enforcement"="maxspeed"](around:${r},${lat},${lng});
      node["enforcement"="average_speed"](around:${r},${lat},${lng});
      node["railway"="level_crossing"](around:${r},${lat},${lng});
      node["railway"="crossing"](around:${r},${lat},${lng});
      node["highway"="traffic_signals"](around:${r},${lat},${lng});
      node["highway"="stop"](around:${r},${lat},${lng});
      node["highway"="give_way"](around:${r},${lat},${lng});
      node["highway"="crossing"](around:${r},${lat},${lng});
      node["traffic_calming"="bump"](around:${r},${lat},${lng});
      node["traffic_calming"="hump"](around:${r},${lat},${lng});
      way["maxspeed"](around:${Math.min(120, r)},${lat},${lng});
    );out tags center;`;
    try {
      const url = OVERPASS_URLS[urlIndex % OVERPASS_URLS.length];
      const res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: "data=" + encodeURIComponent(query),
      });
      if (!res.ok) throw new Error("overpass " + res.status);
      const data = await res.json();
      const next = [];
      let nearestWayLimit = null;
      let nearestWayDist = Infinity;

      for (const el of data.elements || []) {
        const tags = el.tags || {};
        if (el.type === "way" && tags.maxspeed) {
          const plat = el.center?.lat ?? el.lat;
          const plng = el.center?.lon ?? el.lon;
          if (plat == null || plng == null) continue;
          const lim = parseMaxspeed(tags.maxspeed);
          if (!lim) continue;
          const d = haversineM(lat, lng, plat, plng);
          if (d < nearestWayDist) {
            nearestWayDist = d;
            nearestWayLimit = lim;
          }
          continue;
        }
        const nlat = el.lat ?? el.center?.lat;
        const nlng = el.lon ?? el.center?.lon;
        if (nlat == null || nlng == null) continue;
        const type = classifyNode(tags);
        if (!type || !RULES[type]) continue;
        next.push({
          id: `osmhz-${el.id}`,
          type,
          kind: type,
          lat: nlat,
          lng: nlng,
          maxspeed: parseMaxspeed(tags.maxspeed),
          label: tags.name || RULES[type].label,
        });
      }

      const mode = osmMode();
      points = mergeOfficialPrimary([], next, mode);
      lastFetchFailed = false;
      if (nearestWayLimit != null && nearestWayDist < 90) {
        roadMaxspeed = nearestWayLimit;
      }
      fetchCenter = { lat, lng };
      fetchedAt = Date.now();
    } catch (_) {
      urlIndex += 1;
      lastFetchFailed = true;
      fetchedAt = Date.now() - REFETCH_AGE_MS + 20 * 1000;
    } finally {
      fetching = false;
    }
  }

  function formatDist(m) {
    if (!Number.isFinite(m)) return "—";
    if (m < 1000) return `${Math.round(m)} m`;
    return `${(m / 1000).toFixed(m < 10000 ? 1 : 0)} km`;
  }

  function activePoints() {
    const mode = osmMode();
    return mergeOfficialPrimary(officialPoints, points, mode);
  }

  function listNearby(lat, lng, heading, limit = 4) {
    const headingOk = Number.isFinite(heading);
    const scored = [];
    for (const p of activePoints()) {
      const type = p.type || p.kind;
      const distM = haversineM(lat, lng, p.lat, p.lng);
      const rule = RULES[type];
      if (!rule || distM > rule.warn * 1.4) continue;
      const brg = bearingDeg(lat, lng, p.lat, p.lng);
      const ahead = !headingOk || angleDiff(heading, brg) <= 75;
      if (!ahead && distM > 40) continue;
      scored.push({
        ...p,
        type,
        distM,
        dist: formatDist(distM),
        icon: rule.icon,
        title: p.label || rule.label,
        kind: rule.kind,
        stage: distM <= rule.critical ? "critical" : distM <= rule.warn * 0.55 ? "near" : "mid",
        critical: distM <= rule.critical,
        source: isOsmId(p.id) ? "osm" : "official",
      });
    }
    scored.sort((a, b) => a.distM - b.distM);
    return scored.slice(0, limit);
  }

  function nearestAlert(lat, lng, heading, kmh) {
    const list = listNearby(lat, lng, heading, 8);
    if (!list.length) return null;
    const top = list[0];
    const rule = RULES[top.type || top.kind];
    if (!rule || top.distM > rule.warn) return null;

    const now = Date.now();
    if (
      top.critical &&
      top.id !== lastSpokenId &&
      now - lastSpokenAt > 14000 &&
      typeof I18n !== "undefined" &&
      I18n.speak &&
      !window.__ETUBU_NATIVE_CLUSTER__
    ) {
      lastSpokenId = top.id;
      lastSpokenAt = now;
      I18n.speak(`${rule.label}. ${formatDist(top.distM)}.`, {
        key: `osm-${top.id}`,
        urgent: true,
      });
    }

    return {
      title: `${top.icon} ${top.title}`,
      dist: top.dist,
      distM: top.distM,
      meta: roadMaxspeed ? `Limit ${roadMaxspeed}` : "",
      kind: top.kind,
      stage: top.stage,
      over: false,
      id: top.id,
      list,
      source: top.source,
    };
  }

  function getRoadMaxspeed() {
    return roadMaxspeed;
  }

  function setRoadMaxspeed(n) {
    const v = parseInt(n, 10);
    roadMaxspeed = Number.isFinite(v) && v > 0 ? v : null;
  }

  /**
   * @returns {{ alert: object|null, list: array, maxspeed: number|null, overLimit: boolean, mode: string }}
   */
  function update(lat, lng, heading, kmh) {
    if (lat == null || lng == null) {
      return {
        alert: null,
        list: [],
        maxspeed: roadMaxspeed,
        overLimit: false,
        mode: osmMode(),
      };
    }
    if (typeof window.__etubuForceTrRoute !== "undefined") {
      inTurkey = !!Number(window.__etubuForceTrRoute);
    }
    fetchAround(lat, lng);
    const list = listNearby(lat, lng, heading, 4);
    const alert = nearestAlert(lat, lng, heading, kmh);
    const limit = roadMaxspeed;
    let effective = limit;
    if (alert?.kind === "radar") {
      const p = activePoints().find((x) => x.id === alert.id);
      if (p?.maxspeed) effective = p.maxspeed;
    }
    const overLimit =
      effective != null && Number.isFinite(kmh) && kmh > effective + 3;
    return {
      alert,
      list,
      maxspeed: effective ?? limit,
      overLimit,
      overBy: overLimit && effective != null ? Math.round(kmh - effective) : 0,
      mode: osmMode(),
    };
  }

  function clear() {
    points = [];
    officialPoints = [];
    roadMaxspeed = null;
    fetchCenter = null;
    fetchedAt = 0;
    lastFetchFailed = false;
  }

  return {
    update,
    fetchAround,
    listNearby,
    getRoadMaxspeed,
    setRoadMaxspeed,
    setOfficialPoints,
    setInTurkey,
    mergeOfficialPrimary,
    clear,
    RULES,
    DEDUPE_M,
  };
})();
