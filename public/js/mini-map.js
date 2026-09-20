/**
 * MiniMap — Global Mini Cooper OEM-style instrument navigation backdrop.
 * Heading-Up live dynamic forward flow: static vehicle icon pointing forward,
 * map rotates and translates downwards as vehicle moves ahead.
 * High-contrast dark OpenStreetMap / Canvas tiles and global road hazard overlay.
 */
const MiniMap = (() => {
  const TILE_CSS = 256;
  const LAST_LOCATION_KEY = "etubu_last_map_location";
  // Global clean dark tiles (no watermarks, fast worldwide CDN)
  const TILE_URL = "https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}";

  let el = null;
  let tilesEl = null;
  let overlayEl = null;
  let routePathEl = null;
  let progressPathEl = null;
  let startDotEl = null;
  let endDotEl = null;
  let hazardsGroupEl = null;
  let navBarEl = null;
  let navFillEl = null;
  let navLabelEl = null;
  let lastLat = null;
  let lastLng = null;
  let lastHeading = 0;
  let lastSpeedKmh = 0;
  let routeCoords = []; // [lng, lat][]
  let routeCum = [];
  let routeTotalM = 0;
  let progressIdx = 0;
  let progressFrac = 0;
  let zoom = 15;
  let fitCenter = { lat: 48.8566, lng: 2.3522 }; // Sensible global initial fallback (Paris/Europe)
  let routeHazards = [];
  let tilesSignature = "";
  let hasSetInitialLocation = false;
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

    // Clean up any legacy route dot if present in DOM
    const oldDot = overlayEl.querySelector(".hud-map-route-dot");
    if (oldDot) oldDot.remove();

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

  function getAnchor(mapW, mapH) {
    return {
      anchorX: Math.round(mapW / 2),
      anchorY: Math.round(mapH * 0.58),
    };
  }

  function worldToPx(lat, lng, centerLat, centerLng, z, anchorX, anchorY) {
    const c = latLngToWorld(centerLat, centerLng, z);
    const p = latLngToWorld(lat, lng, z);
    return {
      x: anchorX + (p.x - c.x) * TILE_CSS,
      y: anchorY + (p.y - c.y) * TILE_CSS,
    };
  }

  function tileUrl(z, x, y) {
    return TILE_URL.replace("{z}", String(z))
      .replace("{y}", String(y))
      .replace("{x}", String(x));
  }

  function renderTiles() {
    if (!tilesEl || !fitCenter) return;
    const { mapW, mapH } = mapSize();
    const { anchorX, anchorY } = getAnchor(mapW, mapH);
    const z = zoom;
    const c = latLngToWorld(fitCenter.lat, fitCenter.lng, z);

    // Diagonal radius to guarantee full coverage when map is rotated
    const diag = Math.hypot(mapW, mapH);
    const span = diag + 256;
    const tilesX = Math.ceil(span / TILE_CSS) + 2;
    const tilesY = Math.ceil(span / TILE_CSS) + 2;
    const startX = Math.floor(c.x) - Math.floor(tilesX / 2);
    const startY = Math.floor(c.y) - Math.floor(tilesY / 2);
    const n = Math.pow(2, z);
    const sig = `${z}:${startX}:${startY}:${tilesX}:${tilesY}:${mapW}x${mapH}:${fitCenter.lat.toFixed(4)},${fitCenter.lng.toFixed(4)}`;
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
        const left = (startX + ix - c.x) * TILE_CSS + anchorX;
        const top = (startY + iy - c.y) * TILE_CSS + anchorY;
        img.style.left = `${left.toFixed(1)}px`;
        img.style.top = `${top.toFixed(1)}px`;
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

  function buildPathD(coords, fromIdx, toIdx, centerLat, centerLng, z, anchorX, anchorY) {
    if (!coords.length || toIdx < fromIdx) return "";
    const span = Math.max(1, toIdx - fromIdx);
    const step = Math.max(1, Math.floor(span / 220));
    const parts = [];
    for (let i = fromIdx; i <= toIdx; i += step) {
      const [lng, lat] = coords[i];
      const pt = worldToPx(lat, lng, centerLat, centerLng, z, anchorX, anchorY);
      parts.push(`${parts.length ? "L" : "M"}${pt.x.toFixed(1)},${pt.y.toFixed(1)}`);
    }
    const [lngE, latE] = coords[toIdx];
    const end = worldToPx(latE, lngE, centerLat, centerLng, z, anchorX, anchorY);
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
      return;
    }
    if (k === "corridor" || k === "control") {
      const p = document.createElementNS(SVG_NS, "path");
      p.setAttribute("d", "M0,-8.2 L7,-4.5 V1.4 C7,5.2 3,8.1 0,9.2 C-3,8.1 -7,5.2 -7,1.4 V-4.5 Z");
      g.appendChild(p);
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

  function renderHazardMarks(centerLat, centerLng, z, anchorX, anchorY) {
    ensureOverlay();
    if (!hazardsGroupEl) return;
    hazardsGroupEl.innerHTML = "";
    if (!routeHazards.length) return;

    const list = routeHazards.slice(0, MAX_HAZARD_MARKS);
    for (const h of list) {
      const lat = Number(h.lat);
      const lng = Number(h.lng);
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue;

      const pt = worldToPx(lat, lng, centerLat, centerLng, z, anchorX, anchorY);
      const g = document.createElementNS(SVG_NS, "g");
      const kindCls = markKindClass(h.type || h.kind);
      g.setAttribute("class", `hud-map-mark hud-map-mark--${kindCls}`);
      g.setAttribute("transform", `translate(${pt.x.toFixed(1)},${pt.y.toFixed(1)})`);
      g.setAttribute("tabindex", "-1");
      appendMarkSymbol(g, h.type || h.kind);
      hazardsGroupEl.appendChild(g);
    }
    ensureHazardsOnTop();
  }

  function calculateDynamicZoom(speedKmh) {
    const s = Math.max(0, Number(speedKmh) || 0);
    if (s > 100) return 13;
    if (s > 60) return 14;
    return 15; // City / slow / stopped
  }

  function render() {
    if (!el || !tilesEl) return;
    const { mapW, mapH } = mapSize();
    const { anchorX, anchorY } = getAnchor(mapW, mapH);

    // Mini Cooper OEM Navigation Follow Mode
    if (lastLat != null && lastLng != null) {
      fitCenter = { lat: lastLat, lng: lastLng };
      zoom = calculateDynamicZoom(lastSpeedKmh);
    } else if (routeCoords.length >= 2) {
      let minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
      for (const [lng, lat] of routeCoords) {
        if (lat < minLat) minLat = lat;
        if (lat > maxLat) maxLat = lat;
        if (lng < minLng) minLng = lng;
        if (lng > maxLng) maxLng = lng;
      }
      fitCenter = { lat: (minLat + maxLat) / 2, lng: (minLng + maxLng) / 2 };
    }

    renderTiles();
    ensureOverlay();
    if (!overlayEl) return;

    // Apply Heading-Up rotation: map rotates so vehicle forward heading always points straight UP
    const headingDeg = Number.isFinite(lastHeading) ? lastHeading : 0;
    const rot = -headingDeg;
    tilesEl.style.transformOrigin = `${anchorX}px ${anchorY}px`;
    tilesEl.style.transform = `rotate(${rot}deg)`;
    overlayEl.style.transformOrigin = `${anchorX}px ${anchorY}px`;
    overlayEl.style.transform = `rotate(${rot}deg)`;

    if (routeCoords.length >= 2) {
      const dAll = buildPathD(routeCoords, 0, routeCoords.length - 1, fitCenter.lat, fitCenter.lng, zoom, anchorX, anchorY);
      const glow = overlayEl.querySelector(".hud-map-route-glow");
      if (glow) glow.setAttribute("d", dAll);
      if (routePathEl) routePathEl.setAttribute("d", dAll);

      const toIdx = Math.max(0, Math.min(routeCoords.length - 1, progressIdx));
      const dProg = buildPathD(routeCoords, 0, toIdx, fitCenter.lat, fitCenter.lng, zoom, anchorX, anchorY);
      if (progressPathEl) progressPathEl.setAttribute("d", dProg);

      const [sLng, sLat] = routeCoords[0];
      const [eLng, eLat] = routeCoords[routeCoords.length - 1];
      const sPt = worldToPx(sLat, sLng, fitCenter.lat, fitCenter.lng, zoom, anchorX, anchorY);
      const ePt = worldToPx(eLat, eLng, fitCenter.lat, fitCenter.lng, zoom, anchorX, anchorY);

      if (startDotEl) {
        startDotEl.setAttribute("cx", sPt.x.toFixed(1));
        startDotEl.setAttribute("cy", sPt.y.toFixed(1));
        startDotEl.setAttribute("display", "inline");
      }
      if (endDotEl) {
        endDotEl.setAttribute("cx", ePt.x.toFixed(1));
        endDotEl.setAttribute("cy", ePt.y.toFixed(1));
        endDotEl.setAttribute("display", "inline");
      }
    } else {
      if (routePathEl) routePathEl.setAttribute("d", "");
      if (progressPathEl) progressPathEl.setAttribute("d", "");
      const glow = overlayEl.querySelector(".hud-map-route-glow");
      if (glow) glow.setAttribute("d", "");
      if (startDotEl) startDotEl.setAttribute("display", "none");
      if (endDotEl) endDotEl.setAttribute("display", "none");
    }

    // Vehicle pin sits statically in the HUD anchor, pointing straight UP forward
    const pin = el.querySelector(".hud-map-pin");
    if (pin) {
      if (lastLat != null && lastLng != null) {
        pin.style.left = `${anchorX}px`;
        pin.style.top = `${anchorY}px`;
        pin.style.display = "block";
        pin.style.transform = "translate(-50%, -70%)";
      } else {
        pin.style.display = "none";
      }
    }

    renderHazardMarks(fitCenter.lat, fitCenter.lng, zoom, anchorX, anchorY);
  }

  function init(containerId = "hudMap") {
    el = typeof containerId === "string" ? document.getElementById(containerId) : containerId;
    if (!el) return;

    tilesEl = el.querySelector(".hud-map-tiles");
    if (!tilesEl) {
      tilesEl = document.createElement("div");
      tilesEl.className = "hud-map-tiles";
      el.insertBefore(tilesEl, el.firstChild);
    }

    try {
      const stored = localStorage.getItem(LAST_LOCATION_KEY);
      if (stored) {
        const p = JSON.parse(stored);
        if (p?.lat && p?.lng) {
          lastLat = Number(p.lat);
          lastLng = Number(p.lng);
          fitCenter = { lat: lastLat, lng: lastLng };
          hasSetInitialLocation = true;
        }
      }
    } catch (_) {}

    window.addEventListener("resize", () => {
      tilesSignature = "";
      render();
    });

    render();
  }

  function setRoute(geojsonLineString, hazards = []) {
    routeHazards = Array.isArray(hazards) ? hazards : [];
    if (!geojsonLineString || !Array.isArray(geojsonLineString.coordinates) || geojsonLineString.coordinates.length < 2) {
      routeCoords = [];
      routeCum = [];
      routeTotalM = 0;
      progressIdx = 0;
      progressFrac = 0;
      clearHazardMarks();
      render();
      return;
    }
    routeCoords = geojsonLineString.coordinates;
    const { cum, total } = buildCumulative(routeCoords);
    routeCum = cum;
    routeTotalM = total;
    tilesSignature = "";
    render();
  }

  function clearRoute() {
    setRoute(null, []);
  }

  function setProgress(lat, lng) {
    if (lat == null || lng == null) return;
    lastLat = Number(lat);
    lastLng = Number(lng);
    try {
      localStorage.setItem(LAST_LOCATION_KEY, JSON.stringify({ lat: lastLat, lng: lastLng }));
    } catch (_) {}

    if (routeCoords.length >= 2) {
      const prog = nearestProgress(lastLat, lastLng);
      progressIdx = prog.idx;
      progressFrac = prog.frac;
      if (navFillEl) navFillEl.style.width = `${(progressFrac * 100).toFixed(1)}%`;
      if (navLabelEl) navLabelEl.textContent = `${Math.round(progressFrac * 100)}%`;
    }
    render();
  }

  function setVehiclePosition(lat, lng, heading = 0, speedKmh = 0) {
    if (lat == null || lng == null) return;
    lastLat = Number(lat);
    lastLng = Number(lng);
    lastHeading = Number(heading) || 0;
    lastSpeedKmh = Number(speedKmh) || 0;
    hasSetInitialLocation = true;

    try {
      localStorage.setItem(LAST_LOCATION_KEY, JSON.stringify({ lat: lastLat, lng: lastLng }));
    } catch (_) {}

    const emptyMsg = el?.querySelector(".hud-map-empty");
    if (emptyMsg) emptyMsg.style.display = "none";

    setProgress(lat, lng);
  }

  return {
    init,
    setRoute,
    clearRoute,
    clear: clearRoute,
    setProgress,
    setVehiclePosition,
    update: (lat, lng, speedKmh = 0, heading = 0) => setVehiclePosition(lat, lng, heading, speedKmh),
    render,
  };
})();

try {
  window.MiniMap = MiniMap;
} catch (_) {}
