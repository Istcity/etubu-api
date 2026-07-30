/**
 * HUD haritası — sabit Türkiye navigasyon görünümü (dark tiles).
 * Harita pan/zoom yapmaz; yalnızca rota / ilerleme / hazard overlay değişir.
 */
const MiniMap = (() => {
  const TILE_CSS = 256;
  const FALLBACK_LOCATION = { lat: 41.0082, lng: 28.9784 };
  const LAST_LOCATION_KEY = "etubu_last_map_location";
  // Carto Dark Matter — uygulamadaki koyu navigasyon zemini
  const TILE_URL = "https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png";
  const TURKEY_BOUNDS = {
    minLat: 35.8,
    maxLat: 42.4,
    minLng: 25.6,
    maxLng: 44.9,
  };

  let el = null;
  let tilesEl = null;
  let overlayEl = null;
  let routePathEl = null;
  let progressPathEl = null;
  let progressDotEl = null;
  let startDotEl = null;
  let endDotEl = null;
  let hazardsGroupEl = null;
  let navBarEl = null;
  let navFillEl = null;
  let navLabelEl = null;
  let lastLat = null;
  let lastLng = null;
  let routeCoords = []; // [lng, lat][]
  let routeCum = [];
  let routeTotalM = 0;
  let progressIdx = 0;
  let progressFrac = 0;
  let zoom = 6;
  let fitCenter = { lat: 39.0, lng: 35.2 };
  let routeHazards = [];
  let tilesSignature = "";
  const SVG_NS = "http://www.w3.org/2000/svg";
  const MAX_HAZARD_MARKS = 48;

  function latLngToWorld(lat, lng, z) {
    const n = Math.pow(2, z);
    const x = ((lng + 180) / 360) * n;
    const latRad = (lat * Math.PI) / 180;
    const y =
      ((1 - Math.log(Math.tan(latRad) + 1 / Math.cos(latRad)) / Math.PI) / 2) * n;
    return { x, y };
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

  function buildCumulative(coords) {
    const cum = [0];
    let total = 0;
    for (let i = 1; i < coords.length; i++) {
      const [lng0, lat0] = coords[i - 1];
      const [lng1, lat1] = coords[i];
      total += haversineM(lat0, lng0, lat1, lng1);
      cum.push(total);
    }
    return { cum, total };
  }

  function ensureOverlay() {
    if (!el || overlayEl) return;
    overlayEl = el.querySelector(".hud-map-overlay");
    if (!overlayEl) {
      overlayEl = document.createElementNS(SVG_NS, "svg");
      overlayEl.setAttribute("class", "hud-map-overlay");
      overlayEl.setAttribute("aria-hidden", "true");
      el.appendChild(overlayEl);
    }

    let glow = overlayEl.querySelector(".hud-map-route-glow");
    if (!glow) {
      glow = document.createElementNS(SVG_NS, "path");
      glow.setAttribute("class", "hud-map-route-glow");
      overlayEl.appendChild(glow);
    }

    routePathEl = overlayEl.querySelector(".hud-map-route");
    if (!routePathEl) {
      routePathEl = document.createElementNS(SVG_NS, "path");
      routePathEl.setAttribute("class", "hud-map-route");
      overlayEl.appendChild(routePathEl);
    }

    progressPathEl = overlayEl.querySelector(".hud-map-route-progress");
    if (!progressPathEl) {
      progressPathEl = document.createElementNS(SVG_NS, "path");
      progressPathEl.setAttribute("class", "hud-map-route-progress");
      overlayEl.appendChild(progressPathEl);
    }

    progressDotEl = overlayEl.querySelector(".hud-map-route-dot");
    if (!progressDotEl) {
      progressDotEl = document.createElementNS(SVG_NS, "circle");
      progressDotEl.setAttribute("class", "hud-map-route-dot");
      progressDotEl.setAttribute("r", "6");
      overlayEl.appendChild(progressDotEl);
    }

    startDotEl = overlayEl.querySelector(".hud-map-route-start");
    if (!startDotEl) {
      startDotEl = document.createElementNS(SVG_NS, "circle");
      startDotEl.setAttribute("class", "hud-map-route-start");
      startDotEl.setAttribute("r", "8");
      overlayEl.appendChild(startDotEl);
    }

    endDotEl = overlayEl.querySelector(".hud-map-route-end");
    if (!endDotEl) {
      endDotEl = document.createElementNS(SVG_NS, "circle");
      endDotEl.setAttribute("class", "hud-map-route-end");
      endDotEl.setAttribute("r", "8");
      overlayEl.appendChild(endDotEl);
    }

    hazardsGroupEl = overlayEl.querySelector(".hud-map-hazards");
    if (!hazardsGroupEl) {
      hazardsGroupEl = document.createElementNS(SVG_NS, "g");
      hazardsGroupEl.setAttribute("class", "hud-map-hazards");
    }
    overlayEl.appendChild(hazardsGroupEl);

    navBarEl = el.querySelector(".hud-nav-bar");
    if (!navBarEl) {
      navBarEl = document.createElement("div");
      navBarEl.className = "hud-nav-bar";
      navBarEl.innerHTML =
        '<div class="hud-nav-track"><div class="hud-nav-fill"></div></div>' +
        '<span class="hud-nav-label">0%</span>';
      el.appendChild(navBarEl);
    }
    navFillEl = navBarEl.querySelector(".hud-nav-fill");
    navLabelEl = navBarEl.querySelector(".hud-nav-label");
  }

  function mapSize() {
    const mapW = Math.max(120, el?.clientWidth || 680);
    const mapH = Math.max(120, el?.clientHeight || 360);
    return { mapW, mapH };
  }

  function worldToPx(lat, lng, centerLat, centerLng, z, mapW, mapH) {
    const c = latLngToWorld(centerLat, centerLng, z);
    const p = latLngToWorld(lat, lng, z);
    return {
      x: mapW / 2 + (p.x - c.x) * TILE_CSS,
      y: mapH / 2 + (p.y - c.y) * TILE_CSS,
    };
  }

  function zoomToFitTurkey(mapW, mapH, pad = 0.9) {
    const cLat = (TURKEY_BOUNDS.minLat + TURKEY_BOUNDS.maxLat) / 2;
    const cLng = (TURKEY_BOUNDS.minLng + TURKEY_BOUNDS.maxLng) / 2;
    for (let z = 8; z >= 5; z--) {
      const a = worldToPx(
        TURKEY_BOUNDS.maxLat,
        TURKEY_BOUNDS.minLng,
        cLat,
        cLng,
        z,
        mapW,
        mapH
      );
      const b = worldToPx(
        TURKEY_BOUNDS.minLat,
        TURKEY_BOUNDS.maxLng,
        cLat,
        cLng,
        z,
        mapW,
        mapH
      );
      const w = Math.abs(b.x - a.x);
      const h = Math.abs(b.y - a.y);
      if (w <= mapW * pad && h <= mapH * pad) {
        return { zoom: z, lat: cLat, lng: cLng };
      }
    }
    return { zoom: 5, lat: cLat, lng: cLng };
  }

  function applyFixedTurkeyView() {
    const { mapW, mapH } = mapSize();
    const fit = zoomToFitTurkey(mapW, mapH, 0.92);
    zoom = fit.zoom;
    fitCenter = { lat: fit.lat, lng: fit.lng };
  }

  function tileUrl(z, x, y) {
    return TILE_URL.replace("{z}", String(z))
      .replace("{x}", String(x))
      .replace("{y}", String(y));
  }

  function renderTiles() {
    if (!tilesEl || !fitCenter) return;
    const { mapW, mapH } = mapSize();
    const z = zoom;
    const c = latLngToWorld(fitCenter.lat, fitCenter.lng, z);
    const centerPxX = (c.x - Math.floor(c.x)) * TILE_CSS;
    const centerPxY = (c.y - Math.floor(c.y)) * TILE_CSS;
    const tilesX = Math.ceil(mapW / TILE_CSS) + 2;
    const tilesY = Math.ceil(mapH / TILE_CSS) + 2;
    const startX = Math.floor(c.x) - Math.floor(tilesX / 2);
    const startY = Math.floor(c.y) - Math.floor(tilesY / 2);
    const n = Math.pow(2, z);
    const sig = `${z}:${startX}:${startY}:${tilesX}:${tilesY}:${mapW}x${mapH}`;
    if (sig === tilesSignature && tilesEl.childElementCount > 0) return;
    tilesSignature = sig;

    const frag = document.createDocumentFragment();
    for (let iy = 0; iy < tilesY; iy++) {
      for (let ix = 0; ix < tilesX; ix++) {
        const tx = ((startX + ix) % n + n) % n;
        const ty = startY + iy;
        if (ty < 0 || ty >= n) continue;
        const img = document.createElement("img");
        img.className = "hud-map-tile";
        img.alt = "";
        img.decoding = "async";
        img.draggable = false;
        img.src = tileUrl(z, tx, ty);
        const left =
          mapW / 2 -
          centerPxX -
          (Math.floor(tilesX / 2) - ix) * TILE_CSS;
        const top =
          mapH / 2 -
          centerPxY -
          (Math.floor(tilesY / 2) - iy) * TILE_CSS;
        img.style.left = `${left}px`;
        img.style.top = `${top}px`;
        frag.appendChild(img);
      }
    }
    tilesEl.innerHTML = "";
    tilesEl.appendChild(frag);
  }

  function nearestProgress(lat, lng) {
    if (routeCoords.length < 2) return { idx: 0, frac: 0, distM: 0 };
    let best = { d: Infinity, idx: 0 };
    const step = Math.max(1, Math.floor(routeCoords.length / 600));
    for (let i = 0; i < routeCoords.length; i += step) {
      const [x, y] = routeCoords[i];
      const d = haversineM(lat, lng, y, x);
      if (d < best.d) best = { d, idx: i };
    }
    const lo = Math.max(0, best.idx - step);
    const hi = Math.min(routeCoords.length - 1, best.idx + step);
    for (let i = lo; i <= hi; i++) {
      const [x, y] = routeCoords[i];
      const d = haversineM(lat, lng, y, x);
      if (d < best.d) best = { d, idx: i };
    }
    const traveled = routeCum[best.idx] || 0;
    const frac = routeTotalM > 0 ? Math.min(1, traveled / routeTotalM) : 0;
    return { idx: best.idx, frac, distM: traveled };
  }

  function formatRemain(m) {
    if (!Number.isFinite(m) || m <= 0) return "0 km";
    if (m < 1000) return `${Math.round(m)} m`;
    return `${(m / 1000).toFixed(m < 10000 ? 1 : 0)} km`;
  }

  function buildPathD(coords, fromIdx, toIdx, centerLat, centerLng, z, mapW, mapH) {
    if (!coords.length || toIdx < fromIdx) return "";
    const span = Math.max(1, toIdx - fromIdx);
    const step = Math.max(1, Math.floor(span / 220));
    const parts = [];
    for (let i = fromIdx; i <= toIdx; i += step) {
      const [lng, lat] = coords[i];
      const pt = worldToPx(lat, lng, centerLat, centerLng, z, mapW, mapH);
      parts.push(`${parts.length ? "L" : "M"}${pt.x.toFixed(1)},${pt.y.toFixed(1)}`);
    }
    const [lngE, latE] = coords[toIdx];
    const end = worldToPx(latE, lngE, centerLat, centerLng, z, mapW, mapH);
    parts.push(`L${end.x.toFixed(1)},${end.y.toFixed(1)}`);
    return parts.join(" ");
  }

  function markKindClass(kind) {
    if (kind === "charge") return "charge";
    if (kind === "weather") return "weather";
    if (kind === "corridor") return "corridor";
    if (kind === "control") return "control";
    return "radar";
  }

  function appendMarkSymbol(g, kind) {
    const k = markKindClass(kind);
    const halo = document.createElementNS(SVG_NS, "circle");
    halo.setAttribute("r", "11");
    halo.setAttribute("class", "hud-map-mark-halo");
    g.appendChild(halo);

    if (k === "charge") {
      const p = document.createElementNS(SVG_NS, "path");
      p.setAttribute("d", "M1.4,-8.2 L-3.6,-0.2 H0.5 L-1.4,8.2 L3.6,0.2 H-0.5 Z");
      g.appendChild(p);
      return;
    }
    if (k === "weather") {
      const cloud = document.createElementNS(SVG_NS, "path");
      cloud.setAttribute(
        "d",
        "M-6.8,1.2 C-7.5,-1.8 -5,-4.2 -2.4,-3.4 C-1.3,-5.8 1.9,-6.3 3.7,-4.4 C6.1,-5.5 8.6,-3.7 7.8,-1.1 C9.6,-0.5 9.9,2.6 7.5,3.4 H-5.7 C-7.8,3.4 -8.1,1 -6.8,1.2 Z"
      );
      g.appendChild(cloud);
      const rain = document.createElementNS(SVG_NS, "path");
      rain.setAttribute("d", "M-3.2,4.8 L-4.2,7.4 M0.4,4.8 L-0.6,7.4 M4,4.8 L3,7.4");
      rain.setAttribute("fill", "none");
      rain.setAttribute("stroke", "#041018");
      rain.setAttribute("stroke-width", "1.6");
      rain.setAttribute("stroke-linecap", "round");
      g.appendChild(rain);
      return;
    }
    if (k === "corridor" || k === "control") {
      const p = document.createElementNS(SVG_NS, "path");
      p.setAttribute("d", "M0,-8.2 L7,-4.5 V1.4 C7,5.2 3,8.1 0,9.2 C-3,8.1 -7,5.2 -7,1.4 V-4.5 Z");
      g.appendChild(p);
      const bar = document.createElementNS(SVG_NS, "rect");
      bar.setAttribute("x", "-3.4");
      bar.setAttribute("y", "-1.3");
      bar.setAttribute("width", "6.8");
      bar.setAttribute("height", "2.4");
      bar.setAttribute("rx", "0.7");
      bar.setAttribute("class", "hud-map-mark-inset");
      g.appendChild(bar);
      return;
    }
    const tri = document.createElementNS(SVG_NS, "path");
    tri.setAttribute("d", "M0,-8.5 L7.8,6.8 H-7.8 Z");
    g.appendChild(tri);
    const lens = document.createElementNS(SVG_NS, "circle");
    lens.setAttribute("cx", "0");
    lens.setAttribute("cy", "1.8");
    lens.setAttribute("r", "2.3");
    lens.setAttribute("class", "hud-map-mark-inset");
    g.appendChild(lens);
  }

  function clearHazardMarks() {
    if (hazardsGroupEl) hazardsGroupEl.innerHTML = "";
  }

  function ensureHazardsOnTop() {
    if (!overlayEl || !hazardsGroupEl) return;
    if (hazardsGroupEl.parentNode !== overlayEl || overlayEl.lastChild !== hazardsGroupEl) {
      overlayEl.appendChild(hazardsGroupEl);
    }
  }

  function snapHazardToRoute(lat, lng) {
    if (routeCoords.length < 2) return { lat, lng };
    let best = { d: Infinity, idx: 0 };
    const step = Math.max(1, Math.floor(routeCoords.length / 500));
    for (let i = 0; i < routeCoords.length; i += step) {
      const [x, y] = routeCoords[i];
      const d = haversineM(lat, lng, y, x);
      if (d < best.d) best = { d, idx: i };
    }
    const lo = Math.max(0, best.idx - step);
    const hi = Math.min(routeCoords.length - 1, best.idx + step);
    for (let i = lo; i <= hi; i++) {
      const [x, y] = routeCoords[i];
      const d = haversineM(lat, lng, y, x);
      if (d < best.d) best = { d, idx: i };
    }
    if (best.d > 6000) return { lat, lng };
    const [lngR, latR] = routeCoords[best.idx];
    return { lat: latR, lng: lngR };
  }

  function drawHazardMarks(centerLat, centerLng, z, mapW, mapH) {
    ensureOverlay();
    if (!hazardsGroupEl) return;
    ensureHazardsOnTop();
    clearHazardMarks();
    if (!routeHazards.length || routeCoords.length < 2) return;

    const list =
      routeHazards.length > MAX_HAZARD_MARKS
        ? routeHazards.slice(0, MAX_HAZARD_MARKS)
        : routeHazards;

    for (const h of list) {
      let lat = Number(h.lat);
      let lng = Number(h.lng);
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue;
      const snapped = snapHazardToRoute(lat, lng);
      lat = snapped.lat;
      lng = snapped.lng;
      const pt = worldToPx(lat, lng, centerLat, centerLng, z, mapW, mapH);
      if (pt.x < -40 || pt.y < -40 || pt.x > mapW + 40 || pt.y > mapH + 40) continue;
      const g = document.createElementNS(SVG_NS, "g");
      const kind = markKindClass(h.kind);
      g.setAttribute("class", `hud-map-mark hud-map-mark--${kind}`);
      g.setAttribute(
        "transform",
        `translate(${pt.x.toFixed(1)},${pt.y.toFixed(1)}) scale(1.15)`
      );
      if (h.id) g.setAttribute("data-id", String(h.id));
      appendMarkSymbol(g, kind);
      hazardsGroupEl.appendChild(g);
    }
  }

  function updateOverlay() {
    ensureOverlay();
    if (!overlayEl || !el || !fitCenter) {
      clearHazardMarks();
      return;
    }
    const { mapW, mapH } = mapSize();
    overlayEl.setAttribute("viewBox", `0 0 ${mapW} ${mapH}`);
    overlayEl.setAttribute("width", String(mapW));
    overlayEl.setAttribute("height", String(mapH));

    const glow = overlayEl.querySelector(".hud-map-route-glow");
    const cLat = fitCenter.lat;
    const cLng = fitCenter.lng;

    if (routeCoords.length >= 2) {
      const fullD = buildPathD(
        routeCoords,
        0,
        routeCoords.length - 1,
        cLat,
        cLng,
        zoom,
        mapW,
        mapH
      );
      routePathEl.setAttribute("d", fullD);
      routePathEl.style.display = "";
      if (glow) {
        glow.setAttribute("d", fullD);
        glow.style.display = "";
      }

      const endIdx = Math.max(0, Math.min(routeCoords.length - 1, progressIdx));
      if (endIdx >= 1) {
        const progD = buildPathD(routeCoords, 0, endIdx, cLat, cLng, zoom, mapW, mapH);
        progressPathEl.setAttribute("d", progD);
        progressPathEl.style.display = "";
      } else {
        progressPathEl.setAttribute("d", "");
        progressPathEl.style.display = "none";
      }

      const [lng, lat] = routeCoords[endIdx];
      const pt = worldToPx(lat, lng, cLat, cLng, zoom, mapW, mapH);
      progressDotEl.setAttribute("cx", pt.x.toFixed(1));
      progressDotEl.setAttribute("cy", pt.y.toFixed(1));
      progressDotEl.style.display = "";

      const [startLng, startLat] = routeCoords[0];
      const [endLng, endLat] = routeCoords[routeCoords.length - 1];
      const startPt = worldToPx(startLat, startLng, cLat, cLng, zoom, mapW, mapH);
      const endPt = worldToPx(endLat, endLng, cLat, cLng, zoom, mapW, mapH);
      startDotEl.setAttribute("cx", startPt.x.toFixed(1));
      startDotEl.setAttribute("cy", startPt.y.toFixed(1));
      endDotEl.setAttribute("cx", endPt.x.toFixed(1));
      endDotEl.setAttribute("cy", endPt.y.toFixed(1));
      startDotEl.style.display = "";
      endDotEl.style.display = "";

      drawHazardMarks(cLat, cLng, zoom, mapW, mapH);

      const pct = Math.round(progressFrac * 100);
      const remain = Math.max(0, routeTotalM - (routeCum[endIdx] || 0));
      if (navFillEl) navFillEl.style.width = `${pct}%`;
      if (navLabelEl) navLabelEl.textContent = `${pct}% · ${formatRemain(remain)}`;
      if (navBarEl) navBarEl.hidden = false;
    } else {
      routePathEl.setAttribute("d", "");
      routePathEl.style.display = "none";
      if (glow) {
        glow.setAttribute("d", "");
        glow.style.display = "none";
      }
      progressPathEl.setAttribute("d", "");
      progressPathEl.style.display = "none";
      progressDotEl.style.display = "none";
      if (startDotEl) startDotEl.style.display = "none";
      if (endDotEl) endDotEl.style.display = "none";
      clearHazardMarks();
      if (navBarEl) navBarEl.hidden = true;
    }
  }

  function init(root) {
    el = typeof root === "string" ? document.getElementById(root) : root;
    if (!el) return;
    tilesEl = el.querySelector(".hud-map-tiles");
    if (!tilesEl) {
      tilesEl = document.createElement("div");
      tilesEl.className = "hud-map-tiles";
      el.prepend(tilesEl);
    }
    ensureOverlay();
    let initial = FALLBACK_LOCATION;
    try {
      const saved = JSON.parse(localStorage.getItem(LAST_LOCATION_KEY) || "null");
      if (Number.isFinite(saved?.lat) && Number.isFinite(saved?.lng)) initial = saved;
    } catch (_) {}
    lastLat = initial.lat;
    lastLng = initial.lng;
    el.classList.remove("hud-map--empty");
    el.classList.add("hud-map--nav");
    applyFixedTurkeyView();
    renderTiles();
    updateOverlay();
    if (navBarEl) navBarEl.hidden = true;

    if (typeof ResizeObserver !== "undefined") {
      const ro = new ResizeObserver(() => {
        tilesSignature = "";
        applyFixedTurkeyView();
        renderTiles();
        updateOverlay();
      });
      ro.observe(el);
    }
  }

  function render() {
    if (!el) return;
    applyFixedTurkeyView();
    renderTiles();
    if (routeCoords.length >= 2) {
      el.classList.remove("hud-map--empty");
      el.classList.add("hud-map--has-route", "hud-map--fit", "hud-map--nav");
    } else {
      el.classList.remove("hud-map--has-route", "hud-map--fit");
      el.classList.add("hud-map--nav");
    }
    updateOverlay();
  }

  function update(lat, lng) {
    if (lat == null || lng == null || !Number.isFinite(lat) || !Number.isFinite(lng)) return;
    lastLat = lat;
    lastLng = lng;
    try {
      localStorage.setItem(LAST_LOCATION_KEY, JSON.stringify({ lat, lng }));
    } catch (_) {}

    // Harita sabittir — sadece ilerleme güncellenir
    if (routeCoords.length < 2) return;

    const prog = nearestProgress(lat, lng);
    if (prog.frac + 0.002 >= progressFrac || prog.idx >= progressIdx - 3) {
      progressIdx = Math.max(progressIdx, prog.idx);
      progressFrac = Math.max(progressFrac, prog.frac);
    }
    updateOverlay();
  }

  function setRoute(coords, hazards) {
    routeCoords = Array.isArray(coords) ? coords : [];
    if (arguments.length > 1) {
      routeHazards = Array.isArray(hazards) ? hazards : [];
    }
    progressIdx = 0;
    progressFrac = 0;
    if (routeCoords.length >= 2) {
      const built = buildCumulative(routeCoords);
      routeCum = built.cum;
      routeTotalM = built.total;
      if (lastLat != null && lastLng != null) {
        const prog = nearestProgress(lastLat, lastLng);
        progressIdx = prog.idx;
        progressFrac = prog.frac;
      }
      render();
      requestAnimationFrame(() => {
        if (routeCoords.length < 2) return;
        applyFixedTurkeyView();
        renderTiles();
        updateOverlay();
      });
    } else {
      routeCum = [];
      routeTotalM = 0;
      routeHazards = [];
      render();
    }
  }

  function setHazards(hazards) {
    routeHazards = Array.isArray(hazards) ? hazards : [];
    if (routeCoords.length < 2) return;
    updateOverlay();
  }

  function clearRoute() {
    routeHazards = [];
    setRoute([]);
  }

  function clear() {
    clearRoute();
  }

  return { init, update, clear, render, setRoute, setHazards, clearRoute };
})();

try {
  window.MiniMap = MiniMap;
} catch (_) {}
