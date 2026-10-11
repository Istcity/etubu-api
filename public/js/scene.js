/**
 * Hıza senkron 2D canvas — tema başına ayrı çizim mantığı
 */
const Scene = (() => {
  let canvas, ctx, w, h, mode = "alev";
  const MODE_PROFILE = {
    glow: { particles: 28, shards: 0, speedGain: 0.95, hueShift: 0 },
    aurora: { particles: 28, shards: 0, speedGain: 0.95, hueShift: 0 },
    particles: { particles: 48, shards: 4, speedGain: 1.05, hueShift: 0 },
    vortex: { particles: 24, shards: 3, speedGain: 1.0, hueShift: 0 },
    horizon: { particles: 24, shards: 3, speedGain: 1.1, hueShift: 0 },
    "deep-ocean": { particles: 32, shards: 0, speedGain: 0.7, hueShift: -8 },
    "electric-ice": { particles: 36, shards: 4, speedGain: 0.85, hueShift: 12 },
    pulse: { particles: 26, shards: 2, speedGain: 0.95, hueShift: 0 },
    "solar-flare": { particles: 36, shards: 4, speedGain: 1.2, hueShift: 18 },
    plasma: { particles: 32, shards: 2, speedGain: 1.0, hueShift: 0 },
    warp: { particles: 20, shards: 3, speedGain: 1.25, hueShift: 0 },
    streak: { particles: 28, shards: 4, speedGain: 1.3, hueShift: 0 },
    chrome: { particles: 24, shards: 3, speedGain: 0.9, hueShift: -20 },
    tunnel: { particles: 16, shards: 4, speedGain: 1.15, hueShift: 0 },
    redline: { particles: 20, shards: 6, speedGain: 1.35, hueShift: -12 },
    grid: { particles: 12, shards: 2, speedGain: 1.2, hueShift: 0 },
    circuit: { particles: 18, shards: 4, speedGain: 1.1, hueShift: 0 },
    telemetry: { particles: 10, shards: 2, speedGain: 0.95, hueShift: 0 },
    neon: { particles: 16, shards: 2, speedGain: 1.0, hueShift: 0 },
    matrix: { particles: 8, shards: 0, speedGain: 1.05, hueShift: 0 },
    "night-city": { particles: 18, shards: 2, speedGain: 1.05, hueShift: 0 },
    "violet-storm": { particles: 28, shards: 4, speedGain: 1.15, hueShift: 22 },
    "cyber-lime": { particles: 14, shards: 0, speedGain: 1.2, hueShift: -26 },
    alev: { particles: 14, shards: 0, speedGain: 1.3, hueShift: 0 },
    gokkusagi: { particles: 18, shards: 0, speedGain: 1.0, hueShift: 0 },
    yildiz: { particles: 0, shards: 0, speedGain: 0.95, hueShift: 0 },
    bayrak: { particles: 10, shards: 0, speedGain: 1.1, hueShift: 0 },
    sis: { particles: 20, shards: 0, speedGain: 0.65, hueShift: -6 },
    meteor: { particles: 8, shards: 2, speedGain: 1.35, hueShift: 8 },
    lav: { particles: 22, shards: 3, speedGain: 1.15, hueShift: -4 },
    kuzey: { particles: 16, shards: 0, speedGain: 0.8, hueShift: 14 },
    "mini-timeless": { particles: 8, shards: 0, speedGain: 0.85, hueShift: 0 },
    "mini-vibrant": { particles: 16, shards: 0, speedGain: 1.05, hueShift: 8 },
    "mini-gokart": { particles: 6, shards: 0, speedGain: 1.35, hueShift: -8 },
    "mini-personal": { particles: 8, shards: 0, speedGain: 0.75, hueShift: 4 },
    "mini-green": { particles: 12, shards: 0, speedGain: 0.8, hueShift: -10 },
    "mini-balance": { particles: 4, shards: 0, speedGain: 0.7, hueShift: 0 },
    "weather-sky": { particles: 18, shards: 0, speedGain: 0.85, hueShift: 0 },
    "map-focus": { particles: 12, shards: 0, speedGain: 0.8, hueShift: 0 },
    "map-3d": { particles: 14, shards: 0, speedGain: 1.1, hueShift: 0 },
    "cyber-storm": { particles: 22, shards: 4, speedGain: 1.25, hueShift: 15 },
    "desert-dune": { particles: 16, shards: 2, speedGain: 1.05, hueShift: -8 },
    "telemetry-pro": { particles: 16, shards: 2, speedGain: 1.25, hueShift: 10 },
    "stealth-hud": { particles: 6, shards: 0, speedGain: 0.6, hueShift: -15 },
  };

  let profile = MODE_PROFILE.glow;
  let speedNorm = 0;
  let targetNorm = 0;
  let smoothSpeed = 0;
  let renderMotion = 0;
  let themeHue = 195;
  let baseHue = 195;
  let raf = null;

  const MODE_HUE = {
    glow: 195, aurora: 195, particles: 200, vortex: 275, horizon: 205,
    pulse: 345, plasma: 295, warp: 255, streak: 18, chrome: 210,
    tunnel: 165, grid: 145, circuit: 132, telemetry: 175, neon: 318,
    matrix: 118, "night-city": 305, "solar-flare": 36, "deep-ocean": 204,
    "electric-ice": 188, redline: 358, "violet-storm": 268, "cyber-lime": 92,
    alev: 8, gokkusagi: 200, yildiz: 220, bayrak: 356, sis: 198,
    meteor: 32, lav: 14, kuzey: 155,
    "mini-timeless": 0, "mini-vibrant": 335, "mini-gokart": 8,
    "mini-personal": 32, "mini-green": 118, "mini-balance": 40,
    "weather-sky": 202, "map-focus": 188, "map-3d": 200, "cyber-storm": 275, "desert-dune": 32,
    "telemetry-pro": 150, "stealth-hud": 215,
  };

  let particles = [];
  let shards = [];
  let stars = [];
  let tunnelZ = 0;
  let shake = 0;
  let frameN = 0;
  let lastFrameAt = 0;
  let targetHue = 195;
  let skipHeavyFx = false;
  let animT = 0;
  let worldScroll = 0;
  let frameDt = 0.016;
  let boltFlash = 0;
  let boltCooldown = 0.35;
  let activeBolts = [];
  let swayX = 0;
  let swayY = 0;
  let expandR = 1;
  let expandInnerHue = 195;
  let expandOuterHue = 195;
  let hostEl = null;
  let resizeObserver = null;

  // Nebula noise field for premium effects
  let noiseField = null;
  let nebulaT = 0;

  function resolveMode(m) { return m === "aurora" ? "glow" : m; }

  function init(canvasEl) {
    canvas = canvasEl;
    hostEl = canvas.parentElement;
    ctx = canvas.getContext("2d", { alpha: false, desynchronized: true });
    resize();
    window.addEventListener("resize", resize);
    if (typeof ResizeObserver !== "undefined" && hostEl) {
      resizeObserver = new ResizeObserver(() => resize());
      resizeObserver.observe(hostEl);
    }
    applyProfile(MODE_PROFILE[mode] || MODE_PROFILE.glow, true);
    initNoiseField();
    loop();
  }

  function initNoiseField() {
    noiseField = new Float32Array(64);
    for (let i = 0; i < 64; i++) noiseField[i] = Math.random() * Math.PI * 2;
  }

  function applyProfile(p, hard = false) {
    profile = p;
    if (hard) { seedParticles(p.particles); seedShards(p.shards); }
    else { resizeParticles(p.particles); resizeShards(p.shards); }
    stars = [];
  }

  function seedStars(n) {
    stars = Array.from({ length: n }, () => ({
      x: Math.random(), y: Math.random(),
      phase: Math.random() * Math.PI * 2,
      speed: 0.6 + Math.random() * 2.4,
      size: 0.5 + Math.random() * 2.4,
      life: Math.random(),
    }));
  }

  function applyCtxQuality() {
    if (!ctx) return;
    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = "medium";
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    ctx.miterLimit = 2;
  }

  function resize() {
    const dpr = Math.min(Math.max(window.devicePixelRatio || 1, 1), 2);
    w = Math.max(1, window.innerWidth);
    h = Math.max(1, window.innerHeight);
    canvas.width = Math.round(w * dpr);
    canvas.height = Math.round(h * dpr);
    canvas.style.width = w + "px";
    canvas.style.height = h + "px";
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    applyCtxQuality();
  }

  function viewCenter() {
    const gauge = document.getElementById("speedGaugeWrap");
    const hud = gauge || document.getElementById("speedHud");
    if (hud) {
      const r = hud.getBoundingClientRect();
      if (r.width > 0 && r.height > 0) {
        return { cx: r.left + r.width * 0.5, cy: r.top + r.height * 0.5 };
      }
    }
    return { cx: w * 0.5, cy: h * 0.5 };
  }

  function setMode(m) {
    m = resolveMode(m);
    if (m === mode) {
      baseHue = MODE_HUE[m] ?? 195;
      targetHue = baseHue + (profile.hueShift || 0) + targetNorm * 22;
      return;
    }
    expandOuterHue = themeHue;
    expandInnerHue = MODE_HUE[m] ?? 195;
    expandR = 0;
    mode = m;
    baseHue = MODE_HUE[m] ?? 195;
    targetHue = baseHue + targetNorm * 22;
    applyProfile(MODE_PROFILE[m] || MODE_PROFILE.glow, false);
  }

  function lerpHue(a, b, t) {
    const d = ((b - a + 540) % 360) - 180;
    return (a + d * t + 360) % 360;
  }

  function hueDelta(a, b) { return Math.abs(((b - a + 540) % 360) - 180); }

  function tickColorExpand(motion) {
    if (mode === "gokkusagi") return;
    const target = themeHue;
    if (hueDelta(target, expandInnerHue) > 5 && expandR > 0.82) {
      expandOuterHue = expandInnerHue;
      expandInnerHue = target;
      expandR = 0.04;
    } else {
      expandInnerHue = lerpHue(expandInnerHue, target, 0.12);
    }
    const wantR = 0.14 + motion * 0.86;
    expandR += (wantR - expandR) * (0.045 + motion * 0.1);
    if (expandR > 0.985) expandOuterHue = expandInnerHue;
  }

  function drawSpeedColorExpand(cx, cy, motion) {
    if (mode === "gokkusagi") return;
    tickColorExpand(motion);
    const maxR = Math.hypot(Math.max(cx, w - cx), Math.max(cy, h - cy)) * 1.08;
    const r = Math.max(12, expandR * maxR);
    const hot = expandInnerHue + motion * 18;
    const cool = expandOuterHue;
    const wash = ctx.createRadialGradient(cx, cy, 0, cx, cy, r);
    wash.addColorStop(0, `hsla(${hot}, 88%, ${48 + motion * 12}%, ${0.28 + motion * 0.32})`);
    wash.addColorStop(0.4, `hsla(${expandInnerHue}, 80%, 42%, ${0.16 + motion * 0.22})`);
    wash.addColorStop(0.78, `hsla(${lerpHue(expandInnerHue, cool, 0.55)}, 72%, 34%, ${0.08 + motion * 0.1})`);
    wash.addColorStop(1, "transparent");
    ctx.fillStyle = wash;
    ctx.fillRect(0, 0, w, h);
    const rings = skipHeavyFx ? 2 : 4;
    for (let i = 0; i < rings; i++) {
      const phase = (animT * (0.28 + motion * 0.55) + i / rings) % 1;
      const rr = r * (0.22 + phase * 0.78);
      const a = (1 - phase) * (0.12 + motion * 0.38);
      ctx.beginPath();
      ctx.arc(cx, cy, rr, 0, Math.PI * 2);
      ctx.strokeStyle = `hsla(${hot + i * 8}, 95%, 65%, ${a})`;
      ctx.lineWidth = 2.5 + motion * 8 * (1 - phase);
      ctx.stroke();
    }
    softBlob(cx, cy, 40 + motion * 100, hot, 0.14 + motion * 0.22);
  }

  function drawSkyEffect(cx, horizon, motion, hue) {
    const sky = ctx.createLinearGradient(0, 0, 0, horizon);
    sky.addColorStop(0, `hsla(${hue + 18}, 55%, ${7 + motion * 5}%, 0.92)`);
    sky.addColorStop(0.5, `hsla(${hue}, 48%, ${11 + motion * 7}%, 0.55)`);
    sky.addColorStop(1, `hsla(${hue - 12}, 40%, 9%, 0.08)`);
    ctx.fillStyle = sky;
    ctx.fillRect(0, 0, w, horizon);
    const hazeN = skipHeavyFx ? 2 : 4;
    for (let i = 0; i < hazeN; i++) {
      const y = horizon * (0.25 + i * 0.18);
      const ox = cx + Math.sin(animT * 0.2 + i) * w * 0.12;
      softBlob(ox, y, w * (0.22 + i * 0.06), hue + i * 12, 0.06 + motion * 0.08);
    }
  }

  function drawRoadEffect(cx, horizon, motion, hue) {
    if (motion < 0.02) {
      ctx.beginPath();
      ctx.moveTo(cx - 16, horizon); ctx.lineTo(cx + 16, horizon);
      ctx.lineTo(w * 1.15, h + 2); ctx.lineTo(-w * 0.15, h + 2); ctx.closePath();
      const asphalt = ctx.createLinearGradient(0, horizon, 0, h);
      asphalt.addColorStop(0, `hsla(${hue}, 35%, 14%, 0.18)`);
      asphalt.addColorStop(1, `hsla(${hue}, 25%, 6%, 0.35)`);
      ctx.fillStyle = asphalt; ctx.fill();
      return;
    }
    ctx.beginPath();
    ctx.moveTo(cx - 16, horizon); ctx.lineTo(cx + 16, horizon);
    ctx.lineTo(w * 1.15, h + 2); ctx.lineTo(-w * 0.15, h + 2); ctx.closePath();
    const asphalt = ctx.createLinearGradient(0, horizon, 0, h);
    asphalt.addColorStop(0, `hsla(${hue}, 35%, 14%, ${0.2 + motion * 0.25})`);
    asphalt.addColorStop(0.45, `hsla(${hue}, 30%, 10%, ${0.28 + motion * 0.2})`);
    asphalt.addColorStop(1, `hsla(${hue}, 25%, 6%, ${0.4 + motion * 0.2})`);
    ctx.fillStyle = asphalt; ctx.fill();
    const scroll = (animT * (0.2 + motion * 1.4)) % 1;
    const n = skipHeavyFx ? 9 : 14;
    for (let i = 0; i < n; i++) {
      const p = (i / n + scroll) % 1;
      const y = horizon + Math.pow(p, 1.55) * (h - horizon);
      const half = 6 + p * p * w * 0.4;
      const a = (0.12 + p * 0.5) * (0.35 + motion);
      softBlob(cx - half, y, 3 + p * 9, hue + 35, a);
      softBlob(cx + half, y, 3 + p * 9, hue - 25, a * 0.85);
      if (p > 0.15) softBlob(cx, y, 2 + p * 4, hue + 55, a * 0.35);
    }
  }

  let lastKmh = 0;
  const boostRipples = [];

  function triggerBoostRipple(milestone) {
    const base = viewCenter();
    boostRipples.push({
      cx: base.cx,
      cy: base.cy,
      r: 90,
      maxR: Math.max(w, h) * 0.75,
      alpha: 0.88,
      hue: milestone >= 150 ? 45 : milestone >= 100 ? 355 : 190,
      width: 4
    });
  }

  function drawBoostRipples(dt) {
    if (!boostRipples.length) return;
    for (let i = boostRipples.length - 1; i >= 0; i--) {
      const rip = boostRipples[i];
      rip.r += dt * (rip.maxR * 2.2);
      rip.alpha -= dt * 1.35;
      if (rip.alpha <= 0 || rip.r >= rip.maxR) {
        boostRipples.splice(i, 1);
        continue;
      }
      ctx.beginPath();
      ctx.arc(rip.cx, rip.cy, rip.r, 0, Math.PI * 2);
      ctx.strokeStyle = `hsla(${rip.hue}, 100%, 75%, ${Math.max(0, rip.alpha)})`;
      ctx.lineWidth = Math.max(1, rip.width * rip.alpha);
      ctx.stroke();
    }
  }

  let warpStars = [];
  function seedWarpStars(n) {
    warpStars = Array.from({ length: n }, () => ({
      x: (Math.random() - 0.5) * 2,
      y: (Math.random() - 0.5) * 2,
      z: Math.random(),
      hue: Math.random() < 0.35 ? 280 : 195 + Math.random() * 30
    }));
  }

  let bubbles = [];
  function seedBubbles(n) {
    bubbles = Array.from({ length: n }, () => ({
      x: Math.random(),
      y: Math.random(),
      r: 2.5 + Math.random() * 7.5,
      wobble: Math.random() * Math.PI * 2,
      speed: 0.35 + Math.random() * 0.65,
      hue: 185 + Math.random() * 25
    }));
  }

  function setSpeed(kmh, maxKmh) {
    const raw = Math.min(1, Math.max(0, kmh / maxKmh));
    targetNorm = raw < 0.012 ? 0 : raw;
    targetHue = baseHue + (profile.hueShift || 0) + targetNorm * 22;
    const gain = profile.speedGain || 1;
    shake = Math.max(shake, targetNorm > 0.85 ? (targetNorm - 0.85) * 1.1 * gain : 0);

    // Hız eşikleri kutlaması (50, 100, 150, 200 km/s aşıldığında enerji dalgası)
    const milestones = [50, 100, 150, 200];
    for (const m of milestones) {
      if (lastKmh < m && kmh >= m) {
        triggerBoostRipple(m);
        break;
      }
    }
    lastKmh = kmh;
  }

  function getThemeHue() { return baseHue; }

  function seedParticles(n) {
    particles = Array.from({ length: n }, () => ({
      x: Math.random(), y: Math.random(), z: Math.random(),
      size: 1.5 + Math.random() * 5, alpha: 0.15 + Math.random() * 0.7,
      hueOff: Math.random() * 40,
    }));
  }

  function resizeParticles(n) {
    while (particles.length < n)
      particles.push({ x: Math.random(), y: Math.random(), z: Math.random(),
        size: 1.5 + Math.random() * 5, alpha: 0.15 + Math.random() * 0.7, hueOff: Math.random() * 40 });
    if (particles.length > n) particles.length = n;
  }

  function seedShards(n) {
    shards = Array.from({ length: n }, () => ({
      ang: Math.random() * Math.PI * 2, dist: 0.2 + Math.random() * 0.8,
      len: 20 + Math.random() * 60, thick: 1.6 + Math.random() * 2.4,
      spin: (Math.random() - 0.5) * 0.006,
    }));
  }

  function resizeShards(n) {
    while (shards.length < n)
      shards.push({ ang: Math.random() * Math.PI * 2, dist: 0.2 + Math.random() * 0.8,
        len: 20 + Math.random() * 60, thick: 1.6 + Math.random() * 2.4, spin: (Math.random() - 0.5) * 0.006 });
    if (shards.length > n) shards.length = n;
  }

  function effectiveSpeed() { return Math.min(1, speedNorm * (profile.speedGain || 1)); }

  function advanceMotion() {
    const accel = targetNorm > speedNorm;
    const gap = Math.abs(targetNorm - speedNorm);
    // Hız değişimine anında tepki veren akıcı takip
    const follow = accel ? 0.22 + gap * 0.35 : 0.16 + gap * 0.25;
    speedNorm += (targetNorm - speedNorm) * follow;
    smoothSpeed += (speedNorm - smoothSpeed) * 0.18;
    if (targetNorm < 0.005 && speedNorm < 0.01) { speedNorm = 0; smoothSpeed = 0; }
    themeHue += (targetHue - themeHue) * 0.12;
    renderMotion = effectiveSpeed();
    return renderMotion;
  }

  function softBg() {
    const motion = renderMotion;
    const base = viewCenter();
    const cx = base.cx;
    const cy = base.cy;

    // Sade, derin ve modern zemin
    ctx.fillStyle = "#060812";
    ctx.fillRect(0, 0, w, h);

    // Gösterge arkasında hıza göre genişleyen ve parlayan pürüzsüz ambiyans aurası
    const breath = 0.5 + 0.5 * Math.sin(animT * 0.9);
    const auraR = Math.max(w, h) * (0.34 + motion * 0.28) + breath * 16;
    const auraHue = themeHue || 195;
    const aura = ctx.createRadialGradient(cx, cy, 0, cx, cy, auraR);
    
    const lightness = 22 + motion * 24;
    const alpha = 0.16 + motion * 0.22;
    aura.addColorStop(0, `hsla(${auraHue}, 90%, ${lightness}%, ${alpha})`);
    aura.addColorStop(0.42, `hsla(${auraHue + 15}, 80%, ${lightness * 0.55}%, ${alpha * 0.35})`);
    aura.addColorStop(0.85, `hsla(${auraHue + 30}, 65%, 8%, ${alpha * 0.08})`);
    aura.addColorStop(1, "transparent");
    
    ctx.fillStyle = aura;
    ctx.fillRect(0, 0, w, h);

    renderMotion = motion;
    return { cx, cy, motion };
  }

  function softBlob(x, y, r, hue, alpha) {
    if (r < 1 || alpha < 0.01) return;
    const g = ctx.createRadialGradient(x, y, 0, x, y, r);
    g.addColorStop(0, `hsla(${hue}, 85%, 70%, ${alpha})`);
    g.addColorStop(0.4, `hsla(${hue + 12}, 72%, 52%, ${alpha * 0.32})`);
    g.addColorStop(1, "transparent");
    ctx.fillStyle = g;
    ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fill();
  }

  function drawGlassOverlay(cx, cy) {
    if (skipHeavyFx || (frameN & 1) === 1) return;
    const v = renderMotion;
    const g = ctx.createLinearGradient(0, 0, w, h);
    g.addColorStop(0, "rgba(255,255,255,0)");
    g.addColorStop(0.35, `rgba(255,255,255,${0.02 + v * 0.03})`);
    g.addColorStop(0.5, "rgba(255,255,255,0)");
    g.addColorStop(0.7, `rgba(0,240,255,${0.02 + v * 0.04})`);
    g.addColorStop(1, "rgba(255,255,255,0)");
    ctx.fillStyle = g; ctx.fillRect(0, 0, w, h);
  }

  // ─── PREMIUM NEBULA LAYER ───
  function drawNebulaClouds(cx, cy, motion, hue, intensity) {
    const t = animT;
    const clouds = skipHeavyFx ? 4 : 7;
    for (let i = 0; i < clouds; i++) {
      const phase = t * (0.08 + i * 0.02) + i * 1.7;
      const dist = Math.min(w, h) * (0.15 + i * 0.06);
      const nx = cx + Math.cos(phase) * dist * (0.6 + motion * 0.4);
      const ny = cy + Math.sin(phase * 0.7 + i) * dist * 0.5;
      const size = 60 + i * 25 + motion * 80;
      const a = (0.06 + motion * intensity) * (1 - i * 0.08);
      const g = ctx.createRadialGradient(nx, ny, 0, nx, ny, size);
      g.addColorStop(0, `hsla(${hue + i * 22}, 75%, 55%, ${a})`);
      g.addColorStop(0.35, `hsla(${hue + i * 22 + 15}, 65%, 40%, ${a * 0.45})`);
      g.addColorStop(0.7, `hsla(${hue + i * 22 + 30}, 55%, 28%, ${a * 0.15})`);
      g.addColorStop(1, "transparent");
      ctx.fillStyle = g;
      ctx.beginPath(); ctx.arc(nx, ny, size, 0, Math.PI * 2); ctx.fill();
    }
  }

  // ─── PREMIUM AURORA CURTAINS ───
  function drawAuroraCurtains(cx, cy, motion, hue) {
    const t = animT;
    const curtains = skipHeavyFx ? 3 : 5;
    for (let c = 0; c < curtains; c++) {
      ctx.beginPath();
      const baseY = cy * (0.3 + c * 0.12);
      const steps = skipHeavyFx ? 20 : 40;
      for (let i = 0; i <= steps; i++) {
        const p = i / steps;
        const x = p * w;
        const wave = Math.sin(p * 5 + t * (0.4 + c * 0.15) + c * 2.1) * (20 + motion * 50)
                   + Math.sin(p * 11 + t * 0.8 + c) * (5 + motion * 15);
        const y = baseY + wave;
        if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
      }
      const g = ctx.createLinearGradient(0, baseY - 60, 0, baseY + 80);
      g.addColorStop(0, "transparent");
      g.addColorStop(0.3, `hsla(${hue + c * 35}, 85%, 62%, ${0.06 + motion * 0.18})`);
      g.addColorStop(0.5, `hsla(${hue + c * 35 + 20}, 90%, 68%, ${0.12 + motion * 0.25})`);
      g.addColorStop(0.7, `hsla(${hue + c * 35 + 40}, 80%, 55%, ${0.05 + motion * 0.12})`);
      g.addColorStop(1, "transparent");
      ctx.strokeStyle = g;
      ctx.lineWidth = 16 + motion * 28;
      ctx.stroke();
    }
  }

  // ─── MODERN AERODYNAMIC SPEED STREAKS ───
  function drawWarpStreaks(cx, cy, motion) {
    const n = Math.floor(22 + motion * 38);
    const t = animT;
    for (let i = 0; i < n; i++) {
      const ang = (i / n) * Math.PI * 2 + t * (0.04 + motion * 0.22);
      const innerR = 75 + motion * 35;
      const len = 45 + motion * 280 * (0.4 + (i % 5) / 5);
      const x0 = cx + Math.cos(ang) * innerR;
      const y0 = cy + Math.sin(ang) * innerR;
      const x1 = cx + Math.cos(ang) * (innerR + len);
      const y1 = cy + Math.sin(ang) * (innerR + len);
      const g = ctx.createLinearGradient(x0, y0, x1, y1);
      g.addColorStop(0, `hsla(${themeHue}, 85%, 70%, 0)`);
      g.addColorStop(0.3, `hsla(${themeHue}, 95%, 75%, ${0.06 + motion * 0.38})`);
      g.addColorStop(1, `hsla(${themeHue + 25}, 100%, 85%, ${0.12 + motion * 0.5})`);
      ctx.beginPath();
      ctx.moveTo(x0, y0);
      ctx.lineTo(x1, y1);
      ctx.strokeStyle = g;
      ctx.lineWidth = 1.2 + motion * 2.2;
      ctx.stroke();
    }
  }

  // ─── INDIVIDUAL THEME DRAWERS ───

  function drawTunnel() {
    const { cx, cy, motion: v } = softBg();
    const speed = 0.008 + v * 0.16;
    tunnelZ = (tunnelZ + speed) % 1;
    const rings = skipHeavyFx ? 8 : 12;
    for (let i = 0; i < rings; i++) {
      const t = (i / rings + tunnelZ) % 1;
      const ease = t * t;
      const alpha = (1 - t) * (0.15 + v * 0.5);
      const radius = Math.min(w, h) * (0.08 + ease * 0.75);
      ctx.beginPath();
      ctx.strokeStyle = `hsla(${themeHue + t * 25}, 90%, ${60 + v * 15}%, ${alpha * 0.45})`;
      ctx.lineWidth = 1.5 + v * 3 * (1 - t);
      ctx.arc(cx, cy, radius, 0, Math.PI * 2);
      ctx.stroke();
    }
    const spokes = skipHeavyFx ? 6 : 10;
    for (let i = 0; i < spokes; i++) {
      const ang = (i / spokes) * Math.PI * 2 + tunnelZ * 0.6;
      ctx.beginPath();
      ctx.moveTo(cx + Math.cos(ang) * 36, cy + Math.sin(ang) * 36);
      ctx.lineTo(cx + Math.cos(ang) * Math.min(w, h) * 0.78, cy + Math.sin(ang) * Math.min(w, h) * 0.78);
      ctx.strokeStyle = `hsla(${themeHue}, 85%, 68%, ${0.05 + v * 0.14})`;
      ctx.lineWidth = 1.2;
      ctx.stroke();
    }
  }

  function drawRedline() {
    const { cx, cy, motion: v } = softBg();
    const t = animT;

    // 1. Derin kadife kırmızı yarış kokpiti zemini (Gözü yormayan yumuşak akkor)
    const rlineR = Math.max(w, h) * (0.42 + v * 0.28);
    const g = ctx.createRadialGradient(cx, cy, 60, cx, cy, rlineR);
    g.addColorStop(0, `hsla(355, 85%, 42%, ${0.20 + v * 0.20})`);
    g.addColorStop(0.40, `hsla(12, 80%, 28%, ${0.12 + v * 0.14})`);
    g.addColorStop(0.80, `hsla(355, 70%, 10%, ${0.05 + v * 0.06})`);
    g.addColorStop(1, "transparent");
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, w, h);

    // 2. Çok yavaş, pürüzsüz ve sakin aerodinamik rüzgar tüneli çizgileri (Soft & Silky Redline)
    // Kullanıcı İsteği: "redlinedaki çizgileri daha yavaş daha soft yap çok karmaşık ve hızlı"
    const ribbons = skipHeavyFx ? 2 : 3;
    for (let r = 0; r < ribbons; r++) {
      const yBase = cy + (r - (ribbons - 1) / 2) * (h * 0.26);
      ctx.beginPath();
      const steps = skipHeavyFx ? 20 : 36;
      for (let s = 0; s <= steps; s++) {
        const p = s / steps;
        const x = p * w;
        // Çok yavaş akış (t * 0.28), uzun aerodinamik dalga boyu (p * 1.8), yumuşak kavis
        const wave = Math.sin(p * 1.8 - t * (0.26 + v * 0.50) + r * 1.6) * (8 + v * 10);
        const y = yBase + wave;
        if (s === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
      }
      ctx.strokeStyle = `hsla(${352 + r * 5}, 86%, 62%, ${0.07 + v * 0.12})`;
      ctx.lineWidth = 1.8 + v * 1.4;
      ctx.stroke();
    }

    // 3. Çok yavaşça süzülen sakin akkor parçacıklar
    const sparkCount = Math.min(particles.length, skipHeavyFx ? 12 : 20);
    for (let i = 0; i < sparkCount; i++) {
      const p = particles[i];
      p.y -= (0.0004 + v * 0.004) * (0.6 + p.size * 0.15);
      p.x += Math.sin(t * 0.8 + p.hueOff) * 0.0004;
      if (p.y < -0.05) { p.y = 1.05; p.x = Math.random(); }

      const px = p.x * w;
      const py = p.y * h;
      const sz = (1.4 + p.size * 1.1) * (0.8 + v * 0.3);
      const alpha = 0.12 + v * 0.22;

      ctx.beginPath();
      ctx.arc(px, py, sz, 0, Math.PI * 2);
      ctx.fillStyle = `hsla(356, 90%, 68%, ${alpha})`;
      ctx.fill();
    }

    // 4. Kadran çevresinde yumuşak nefes alan sakin kızıl halka
    const breath = 0.5 + 0.5 * Math.sin(t * 1.2);
    const arcR = Math.max(160, Math.min(w, h) * 0.22) + v * 25 + breath * 4;
    ctx.beginPath();
    ctx.arc(cx, cy, arcR, -Math.PI * 0.85, Math.PI * 0.85);
    ctx.strokeStyle = `hsla(355, 90%, 64%, ${0.14 + v * 0.24})`;
    ctx.lineWidth = 2.0 + v * 1.5;
    ctx.stroke();
  }

  function drawShards(cx, cy) {
    const v = renderMotion;
    for (const s of shards) {
      s.ang += s.spin * (0.35 + v);
      const dist = s.dist * Math.min(w, h) * (0.2 + v * 0.45);
      const x = cx + Math.cos(s.ang) * dist;
      const y = cy + Math.sin(s.ang) * dist;
      softBlob(x, y, 6 + s.thick * 3 + v * 10, themeHue + 25, 0.12 + v * 0.28);
    }
  }

  function drawGlow() {
    const { cx, cy, motion: v } = softBg();
    const t = animT;

    // Sade ve modern hız vektör parçacıkları (Speed stream particles)
    const drift = 0.0012 + v * 0.016;
    const pCount = Math.min(particles.length, skipHeavyFx ? 35 : 70);
    
    for (let i = 0; i < pCount; i++) {
      const p = particles[i];
      p.z -= drift * (0.6 + p.size * 0.1);
      if (p.z <= 0) { 
        p.z = 1; 
        p.x = Math.random(); 
        p.y = Math.random(); 
      }
      
      const depth = 1 - p.z;
      const dx = (p.x - 0.5) * 2;
      const dy = (p.y - 0.5) * 2;
      const px = cx + dx * w * 0.55 * depth;
      const py = cy + dy * h * 0.55 * depth;
      
      const pSize = (1 + p.size * 1.6) * depth;
      const pAlpha = depth * (0.2 + v * 0.7);
      
      if (v > 0.06) {
        const streakLen = v * depth * 40;
        const sx = px - dx * streakLen;
        const sy = py - dy * streakLen;
        ctx.beginPath();
        ctx.moveTo(sx, sy);
        ctx.lineTo(px, py);
        ctx.strokeStyle = `hsla(${themeHue + p.hueOff}, 90%, 75%, ${pAlpha * 0.75})`;
        ctx.lineWidth = Math.max(1, pSize * 0.85);
        ctx.stroke();
      } else {
        ctx.beginPath();
        ctx.arc(px, py, pSize, 0, Math.PI * 2);
        ctx.fillStyle = `hsla(${themeHue + p.hueOff}, 85%, 80%, ${pAlpha})`;
        ctx.fill();
      }
    }

    // Zarif modern hız halkası
    if (v > 0.02) {
      const ringR = 145 + v * 130 + Math.sin(t * 1.4) * 8;
      ctx.beginPath();
      ctx.arc(cx, cy, ringR, 0, Math.PI * 2);
      ctx.strokeStyle = `hsla(${themeHue}, 90%, 65%, ${0.06 + v * 0.2})`;
      ctx.lineWidth = 1.5 + v * 2;
      ctx.stroke();
    }
  }

  function drawAurora() { drawGlow(); }

  function drawDeepOcean() {
    const { cx, cy, motion: v } = softBg();
    const t = animT;
    if (!bubbles.length) seedBubbles(skipHeavyFx ? 35 : 75);

    // 1. Derin Okyanus Abisal Mavisi
    const oceanR = Math.max(w, h) * (0.45 + v * 0.35);
    const g = ctx.createRadialGradient(cx, cy, 60, cx, cy, oceanR);
    g.addColorStop(0, `hsla(195, 100%, 40%, ${0.30 + v * 0.40})`);
    g.addColorStop(0.38, `hsla(215, 92%, 26%, ${0.20 + v * 0.26})`);
    g.addColorStop(0.80, `hsla(230, 85%, 12%, ${0.10 + v * 0.12})`);
    g.addColorStop(1, "transparent");
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, w, h);

    // 2. Sualtı Işık Kırılmaları (Caustic Light Beams across the page)
    const beamCount = 6;
    for (let i = 0; i < beamCount; i++) {
      const bx = cx + Math.sin(t * (0.7 + v * 1.5) + i * 1.2) * w * 0.40;
      const lg = ctx.createLinearGradient(bx, 0, bx, h);
      lg.addColorStop(0, `hsla(188 + i * 8, 95%, 75%, ${0.12 + v * 0.24})`);
      lg.addColorStop(0.70, "transparent");
      ctx.fillStyle = lg;
      ctx.fillRect(bx - 70, 0, 140, h);
    }

    // 3. Yükselen ve Hızla Kaçan Hava Kabarcıkları (Ascending Air Bubbles)
    const riseSpeed = 0.0025 + v * 0.030;
    for (let i = 0; i < bubbles.length; i++) {
      const b = bubbles[i];
      b.y -= riseSpeed * b.speed;
      b.wobble += 0.05 + v * 0.12;
      if (b.y < -0.05) { b.y = 1.05; b.x = Math.random(); }

      const bx = b.x * w + Math.sin(b.wobble) * (10 + v * 20);
      const by = b.y * h;
      const bAlpha = 0.35 + v * 0.65;

      ctx.beginPath();
      ctx.arc(bx, by, b.r * (1 + v * 0.5), 0, Math.PI * 2);
      ctx.strokeStyle = `hsla(${b.hue}, 95%, 85%, ${bAlpha})`;
      ctx.lineWidth = 1.6;
      ctx.stroke();

      // Kabarcık içi parlama
      ctx.beginPath();
      ctx.arc(bx - b.r * 0.3, by - b.r * 0.3, b.r * 0.3, 0, Math.PI * 2);
      ctx.fillStyle = `rgba(255,255,255,${bAlpha * 0.9})`;
      ctx.fill();
    }

    // 4. Hidrodinamik Halka
    const ringR = Math.max(160, Math.min(w, h) * 0.22) + v * 70;
    ctx.beginPath();
    ctx.arc(cx, cy, ringR, 0, Math.PI * 2);
    ctx.strokeStyle = `hsla(190, 100%, 72%, ${0.15 + v * 0.40})`;
    ctx.lineWidth = 2.5 + v * 3.0;
    ctx.stroke();
  }

  function drawElectricIce() {
    const { cx, cy } = softBg();
    const v = renderMotion;
    const t = Date.now() * 0.0012;
    drawNebulaClouds(cx, cy, v, themeHue, 0.15);
    // Crystalline hex grid
    const hexR = 22 + v * 8;
    for (let row = -2; row < Math.ceil(h / (hexR * 1.5)) + 2; row++) {
      for (let col = -2; col < Math.ceil(w / (hexR * 1.73)) + 2; col++) {
        const ox = col * hexR * 1.73 + (row % 2) * hexR * 0.86;
        const oy = row * hexR * 1.5 + Math.sin(t + col * 0.4) * v * 4;
        const pulse = (Math.sin(t * 2 + col * 0.5 + row * 0.3) + 1) / 2;
        softBlob(ox, oy, hexR * (0.85 + pulse * 0.08) * 1.15, themeHue + col * 4, (0.04 + pulse * v * 0.12) * 1.4);
      }
    }
    // Ice crystal particles
    for (const p of particles) {
      const px = p.x * w + Math.sin(t + p.hueOff) * v * 12;
      const py = p.y * h + Math.cos(t * 0.7 + p.hueOff) * v * 8;
      const size = p.size * (0.8 + v);
      ctx.beginPath();
      ctx.moveTo(px, py - size); ctx.lineTo(px + size * 0.6, py);
      ctx.lineTo(px, py + size); ctx.lineTo(px - size * 0.6, py); ctx.closePath();
      ctx.fillStyle = `hsla(${themeHue + p.hueOff}, 95%, 85%, ${0.2 + v * 0.35})`; ctx.fill();
    }
    drawShards(cx, cy);
    drawGlassOverlay(cx, cy);
  }

  function drawGrid() {
    const { cx } = softBg();
    const v = renderMotion;
    const horizon = h * (0.4 - v * 0.03);
    const scroll = (Date.now() * (0.00012 + v * 0.0028)) % 1;
    for (let i = 0; i < 28; i++) {
      const sx = ((i * 97) % w); const sy = ((i * 53) % horizon);
      softBlob(sx, sy, 2 + (i % 3), themeHue + 40, 0.2 + (i % 4) * 0.08);
    }
    for (let i = 0; i < 12; i++) {
      const p = (i / 12 + scroll) % 1;
      const y = horizon + Math.pow(p, 1.55) * (h - horizon);
      const bandH = 8 + p * (18 + v * 40);
      const g = ctx.createLinearGradient(0, y - bandH, 0, y + bandH);
      const a = (0.06 + p * (0.18 + v * 0.28)) * (1 - p * 0.2);
      g.addColorStop(0, "transparent");
      g.addColorStop(0.5, `hsla(${themeHue}, 85%, 55%, ${a})`);
      g.addColorStop(1, "transparent");
      ctx.fillStyle = g; ctx.fillRect(0, y - bandH, w, bandH * 2);
    }
    for (let i = -6; i <= 6; i++) {
      if (i === 0) continue;
      const xEnd = cx + i * (70 + v * 160);
      const midX = (cx + xEnd) / 2; const midY = (horizon + h) / 2;
      const g = ctx.createRadialGradient(midX, midY, 0, midX, midY, 80 + Math.abs(i) * 20);
      g.addColorStop(0, `hsla(${themeHue + 30}, 80%, 55%, ${0.08 + v * 0.14})`);
      g.addColorStop(1, "transparent");
      ctx.fillStyle = g;
      ctx.fillRect(Math.min(cx, xEnd) - 40, horizon, Math.abs(xEnd - cx) + 80, h - horizon);
    }
    softBlob(cx, horizon, 90 + v * 140, themeHue, 0.22 + v * 0.28);
    drawGlassOverlay(cx, horizon);
  }

  function drawGlassParticles() {
    const v = renderMotion;
    const drift = 0.001 + v * 0.01;
    for (const p of particles) {
      p.z -= drift;
      if (p.z <= 0) { p.z = 1; p.x = Math.random(); p.y = Math.random(); }
      const depth = 1 - p.z;
      const px = p.x * w + (p.x - 0.5) * depth * v * 180 + Math.sin(animT * 0.5 + p.hueOff) * 6;
      const py = p.y * h + (0.5 - p.y) * depth * v * 28;
      const size = p.size * (0.45 + depth * 2.4) * (1 + v * 0.55);
      softBlob(px, py, size * 2.2, themeHue + p.hueOff, p.alpha * depth * 0.65);
    }
  }

  function drawParticlesMode() {
    const { cx, cy } = softBg();
    const v = renderMotion;
    drawNebulaClouds(cx, cy, v, themeHue, 0.12);
    for (const p of particles) {
      p.y -= (0.0003 + v * 0.0025) * (0.5 + p.z);
      p.x += Math.sin(Date.now() * 0.001 + p.hueOff) * 0.0004 * v;
      if (p.y < -0.05) { p.y = 1.05; p.x = Math.random(); }
      const px = p.x * w; const py = p.y * h;
      const size = p.size * (2.5 + p.z * 4) * (1 + v * 0.6);
      const g = ctx.createRadialGradient(px, py, 0, px, py, size);
      g.addColorStop(0, `hsla(${themeHue + p.hueOff}, 90%, 80%, ${0.25 + v * 0.3})`);
      g.addColorStop(0.5, `hsla(${themeHue + p.hueOff}, 85%, 60%, ${0.08 + v * 0.15})`);
      g.addColorStop(1, "transparent");
      ctx.fillStyle = g; ctx.beginPath(); ctx.arc(px, py, size, 0, Math.PI * 2); ctx.fill();
    }
    drawShards(cx, cy);
    drawGlassOverlay(cx, cy);
  }

  function drawWarp() {
    const { cx, cy, motion: v } = softBg();
    const t = animT;
    if (!warpStars.length) seedWarpStars(skipHeavyFx ? 45 : 75);

    const speedZ = 0.0012 + v * 0.015;
    const maxRadius = Math.max(w, h);

    // 1. Merkezden Ufka Yavaşça Süzülen Yıldız Tozları (Soft Hyperspace Starlight)
    for (let i = 0; i < warpStars.length; i++) {
      const s = warpStars[i];
      const prevZ = s.z;
      s.z -= speedZ;
      if (s.z <= 0.01) {
        s.z = 1;
        s.x = (Math.random() - 0.5) * 2;
        s.y = (Math.random() - 0.5) * 2;
        continue;
      }

      // 3D Perspektif İzdüşümü (Gözü yormayan yumuşak çizgiler)
      const pz = Math.max(0.02, s.z);
      const px = cx + (s.x / pz) * (w * 0.52);
      const py = cy + (s.y / pz) * (h * 0.52);

      const oldPz = Math.max(0.02, prevZ + speedZ * (1 + v * 2.5));
      const oldPx = cx + (s.x / oldPz) * (w * 0.52);
      const oldPy = cy + (s.y / oldPz) * (h * 0.52);

      const alpha = Math.min(0.65, (1 - s.z) * (0.25 + v * 0.35));
      const thickness = Math.max(1.0, (1 - s.z) * (1.5 + v * 2.0));

      const g = ctx.createLinearGradient(oldPx, oldPy, px, py);
      g.addColorStop(0, "transparent");
      g.addColorStop(0.4, `hsla(${s.hue}, 85%, 65%, ${alpha * 0.4})`);
      g.addColorStop(1, `hsla(${s.hue + 20}, 90%, 85%, ${alpha})`);
      ctx.beginPath();
      ctx.moveTo(oldPx, oldPy);
      ctx.lineTo(px, py);
      ctx.strokeStyle = g;
      ctx.lineWidth = thickness;
      ctx.stroke();
    }

    // 2. Yumuşak Nefes Alan Göksel Işık Halkası (Soft Ambient Star Aura)
    const breath = 0.5 + 0.5 * Math.sin(t * 1.5);
    const ringR = Math.max(160, Math.min(w, h) * 0.22) + v * 35 + breath * 8;
    ctx.beginPath();
    ctx.arc(cx, cy, ringR, 0, Math.PI * 2);
    ctx.strokeStyle = `hsla(${themeHue}, 90%, 75%, ${0.15 + v * 0.25 + breath * 0.08})`;
    ctx.lineWidth = 2.0 + v * 1.5;
    ctx.stroke();
  }

  function drawNeon() {
    const { cx, cy, motion: v } = softBg();
    const t = animT;
    const pulse = 0.5 + 0.5 * Math.sin(t * 1.2);
    
    // 1. Derin kadife gece zemini
    ctx.fillStyle = "#050208";
    ctx.fillRect(0, 0, w, h);

    // 2. Çok katmanlı ipeksi neon auraları (Soft Gaussian Ambient Bloom - Sıfır keskin hat)
    softBlob(cx, cy, Math.min(w, h) * (0.34 + v * 0.16) + pulse * 12, themeHue, 0.22 + v * 0.24 + pulse * 0.05);
    softBlob(cx - w * 0.22, cy + h * 0.06, Math.min(w, h) * (0.26 + v * 0.12), themeHue + 35, 0.14 + v * 0.16);
    softBlob(cx + w * 0.20, cy - h * 0.06, Math.min(w, h) * (0.24 + v * 0.1), themeHue - 30, 0.12 + v * 0.14);

    // 3. İpeksi ufuk geçişi (Soft Horizon Ambient Haze)
    const flareH = Math.min(h * 0.24, 120 + v * 60);
    const flare = ctx.createLinearGradient(0, cy - flareH, 0, cy + flareH);
    flare.addColorStop(0, "transparent");
    flare.addColorStop(0.3, `hsla(${themeHue}, 95%, 65%, ${(0.05 + v * 0.12) * 0.5})`);
    flare.addColorStop(0.5, `hsla(${themeHue}, 100%, 70%, ${0.08 + v * 0.16})`);
    flare.addColorStop(0.7, `hsla(${themeHue}, 95%, 65%, ${(0.05 + v * 0.12) * 0.5})`);
    flare.addColorStop(1, "transparent");
    ctx.fillStyle = flare;
    ctx.fillRect(0, cy - flareH, w, flareH * 2);
  }

  function drawMatrix() {
    const { cx, cy } = softBg();
    const v = renderMotion;
    const cols = Math.floor(w / 16);
    const t = Date.now() * (0.05 + v * 0.2);
    ctx.font = "12px monospace";
    for (let c = 0; c < cols; c++) {
      const x = c * 16;
      const offset = (c * 53 + t * (10 + (c % 7))) % h;
      for (let r = 0; r < 8; r++) {
        const y = (offset + r * 22) % h;
        const ch = String.fromCharCode(0x30a0 + ((c + r + Math.floor(t)) % 96));
        ctx.fillStyle = `hsla(140, 90%, ${40 + r * 6}%, ${0.15 + v * 0.35})`;
        ctx.fillText(ch, x, y);
      }
    }
    drawGlassOverlay(cx, cy);
  }

  function drawCyberLime() {
    const { cx, cy } = softBg();
    const v = renderMotion;
    const cols = Math.floor(w / 14);
    const t = Date.now() * (0.06 + v * 0.25);
    ctx.font = "11px monospace";
    for (let c = 0; c < cols; c++) {
      const x = c * 14;
      const offset = (c * 41 + t * (12 + (c % 5))) % h;
      for (let r = 0; r < 10; r++) {
        const y = (offset + r * 18) % h;
        const ch = String.fromCharCode(0x0030 + ((c * 7 + r + Math.floor(t)) % 10));
        ctx.fillStyle = `hsla(92, 95%, ${45 + r * 5}%, ${0.2 + v * 0.4})`;
        ctx.fillText(ch, x, y);
      }
    }
    const scanY = ((Date.now() * (0.08 + v * 0.3)) % (h + 40)) - 20;
    ctx.fillStyle = `hsla(92, 100%, 60%, ${0.06 + v * 0.12})`;
    ctx.fillRect(0, scanY, w, 3 + v * 6);
    ctx.fillStyle = `hsla(92, 100%, 75%, ${0.03 + v * 0.08})`;
    ctx.fillRect(0, scanY + 8, w, 2);
    drawGlassOverlay(cx, cy);
  }

  function drawPulse() {
    const { cx, cy } = softBg();
    const v = renderMotion;
    const t = Date.now() * 0.004;
    // Concentric pulse rings with nebula backdrop
    drawNebulaClouds(cx, cy, v, themeHue, 0.1);
    for (let i = 0; i < 8; i++) {
      const pulse = (Math.sin(t + i * 0.7) + 1) / 2;
      const r = 30 + i * 35 + pulse * (40 + v * 80);
      ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2);
      ctx.strokeStyle = `hsla(${themeHue + i * 15}, 95%, 60%, ${0.12 + pulse * 0.25})`;
      ctx.lineWidth = 2 + v * 3; ctx.stroke();
    }
    drawGlassParticles();
    drawGlassOverlay(cx, cy);
  }

  function drawSolarFlare() {
    const { cx, cy } = softBg();
    const v = renderMotion;
    const t = Date.now() * 0.002;
    // Solar core with corona
    const core = ctx.createRadialGradient(cx, cy, 0, cx, cy, 90 + v * 70);
    core.addColorStop(0, `hsla(${themeHue}, 100%, 75%, ${0.35 + v * 0.45})`);
    core.addColorStop(0.35, `hsla(${themeHue + 15}, 95%, 55%, ${0.15 + v * 0.25})`);
    core.addColorStop(1, "transparent");
    ctx.fillStyle = core;
    ctx.beginPath(); ctx.arc(cx, cy, 120 + v * 80, 0, Math.PI * 2); ctx.fill();
    for (let i = 0; i < 6; i++) {
      const pulse = (Math.sin(t * 1.5 + i) + 1) / 2;
      const r = 50 + i * 40 + pulse * (30 + v * 60);
      ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2);
      ctx.strokeStyle = `hsla(${themeHue + i * 8}, 100%, 65%, ${0.1 + pulse * 0.3})`;
      ctx.lineWidth = 2 + v * 4; ctx.stroke();
    }
    // Solar flare rays
    for (let i = 0; i < 20; i++) {
      const ang = (i / 20) * Math.PI * 2 + t * (0.5 + v);
      const len = 60 + v * 200 + (i % 4) * 25;
      ctx.beginPath();
      ctx.moveTo(cx + Math.cos(ang) * 25, cy + Math.sin(ang) * 25);
      ctx.lineTo(cx + Math.cos(ang) * len, cy + Math.sin(ang) * len);
      ctx.strokeStyle = `hsla(${themeHue + 20}, 95%, 70%, ${0.12 + v * 0.45})`;
      ctx.lineWidth = 1.5 + v * 2; ctx.stroke();
    }
    drawGlassOverlay(cx, cy);
  }

  function drawHorizon() {
    const { cx, cy } = softBg();
    const v = renderMotion;
    const horizon = h * (0.42 - v * 0.05);
    const scroll = (Date.now() * (0.0002 + v * 0.0045)) % 1;
    drawNebulaClouds(cx, horizon * 0.6, v, themeHue, 0.1);
    for (let i = 0; i < 18; i++) {
      const p = (i / 18 + scroll) % 1;
      const y = horizon + Math.pow(p, 1.5) * (h - horizon);
      const spread = 40 + p * w * 0.55;
      ctx.beginPath(); ctx.moveTo(cx - spread, y); ctx.lineTo(cx + spread, y);
      ctx.strokeStyle = `hsla(${themeHue}, 85%, 55%, ${0.08 + p * (0.2 + v * 0.4)})`;
      ctx.lineWidth = 1 + p * v * 2; ctx.stroke();
    }
    for (let i = 0; i < 10; i++) {
      const p = (i / 10 + scroll * 2) % 1;
      const y = horizon + Math.pow(p, 1.7) * (h - horizon);
      const len = 8 + p * 40;
      ctx.fillStyle = `hsla(${themeHue + 60}, 90%, 65%, ${0.2 + v * 0.5})`;
      ctx.fillRect(cx - 2, y, 4, len * (0.3 + v));
    }
    drawGlassOverlay(cx, cy);
  }

  function drawStreak() {
    const { cx, cy } = softBg();
    const v = renderMotion;
    drawWarpStreaks(cx, cy, v);
    drawShards(cx, cy);
    drawGlassOverlay(cx, cy);
  }

  function drawPlasma() {
    const { cx, cy, motion: v } = softBg();
    const t = animT;

    // 1. Yumuşak Yörüngede Dönen Plazma Işık Küreleri (Soft Orbiting Plasma Orbs)
    const orbs = skipHeavyFx ? 3 : 5;
    for (let i = 0; i < orbs; i++) {
      const ang = t * (0.35 + i * 0.08) + i * 1.25;
      const dist = 90 + v * 95 + Math.sin(t * 0.8 + i) * 25;
      const ox = cx + Math.cos(ang) * dist;
      const oy = cy + Math.sin(ang) * dist * 0.70;
      const size = 70 + i * 18 + v * 60;
      softBlob(ox, oy, size, themeHue + i * 20, 0.16 + v * 0.22);
    }

    // 2. Kadran Çevresinde Yumuşak Nefes Alan Plazma Enerji Halkası (Soft Plasma Halo)
    const breath = 0.5 + 0.5 * Math.sin(t * 1.6);
    const ringR = Math.max(160, Math.min(w, h) * 0.22) + v * 35 + breath * 6;
    ctx.beginPath();
    ctx.arc(cx, cy, ringR, 0, Math.PI * 2);
    ctx.strokeStyle = `hsla(${themeHue + 20}, 85%, 68%, ${0.18 + v * 0.28 + breath * 0.08})`;
    ctx.lineWidth = 2.4 + v * 1.8;
    ctx.stroke();

    // Kadran arkasında sakin mor-mavi sis aurası
    softBlob(cx, cy, ringR * 0.9, themeHue, 0.14 + v * 0.18);
  }

  function drawNightCity() {
    const { cx, cy, motion: v } = softBg();
    const t = animT;
    const horizon = cy + 40;

    // 1. Dinlendirici Synthwave Gece Gökyüzü
    const sky = ctx.createLinearGradient(0, 0, 0, horizon);
    sky.addColorStop(0, "#080314");
    sky.addColorStop(0.65, `hsla(285, 75%, 18%, ${0.30 + v * 0.18})`);
    sky.addColorStop(1, `hsla(320, 80%, 38%, ${0.35 + v * 0.22})`);
    ctx.fillStyle = sky;
    ctx.fillRect(0, 0, w, horizon);

    // 2. Yumuşak Neon Siber Güneş (Soft Ambient Retro Sun)
    const sunR = Math.min(w, h) * 0.20;
    const sunGrad = ctx.createLinearGradient(cx, horizon - sunR * 1.2, cx, horizon);
    sunGrad.addColorStop(0, "hsla(45, 90%, 70%, 0.70)");
    sunGrad.addColorStop(0.5, "hsla(330, 85%, 55%, 0.60)");
    sunGrad.addColorStop(1, "hsla(280, 75%, 35%, 0.35)");
    ctx.fillStyle = sunGrad;
    ctx.beginPath();
    ctx.arc(cx, horizon, sunR, Math.PI, 0);
    ctx.fill();

    // 3. Sakin ve Akıcı 3D Perspektif Izgara Yolu (Smooth Relaxed Retro Cruise Grid)
    const gridSpeed = (t * (0.2 + v * 0.7)) % 1;
    const gridLines = skipHeavyFx ? 7 : 11;
    for (let i = 0; i < gridLines; i++) {
      const p = (i / gridLines + gridSpeed) % 1;
      const y = horizon + Math.pow(p, 1.5) * (h - horizon);
      const alpha = p * (0.16 + v * 0.32);
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(w, y);
      ctx.strokeStyle = `hsla(315, 80%, 62%, ${alpha})`;
      ctx.lineWidth = 1.2 + p * 2.0;
      ctx.stroke();
    }

    // Izgaranın ufuktan aşağı inen sakin perspektif şeritleri
    const lanes = 10;
    for (let l = -lanes; l <= lanes; l++) {
      const spreadBottom = cx + l * (w / (lanes * 1.35));
      ctx.beginPath();
      ctx.moveTo(cx + l * 4, horizon);
      ctx.lineTo(spreadBottom, h);
      ctx.strokeStyle = `hsla(195, 80%, 55%, ${0.12 + v * 0.25})`;
      ctx.lineWidth = 1.2;
      ctx.stroke();
    }
  }

  function drawVortex() {
    const { cx, cy } = softBg();
    const v = renderMotion;
    const t = Date.now() * (0.0004 + v * 0.002);
    const arms = 5;
    for (let a = 0; a < arms; a++) {
      ctx.beginPath();
      for (let i = 0; i < 60; i++) {
        const p = i / 60;
        const ang = t * (1 + v) + a * ((Math.PI * 2) / arms) + p * Math.PI * 3;
        const r = 10 + p * Math.min(w, h) * 0.42 * (0.5 + v);
        const x = cx + Math.cos(ang) * r; const y = cy + Math.sin(ang) * r;
        if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
      }
      ctx.strokeStyle = `hsla(${themeHue + a * 20}, 90%, 60%, ${0.15 + v * 0.4})`;
      ctx.lineWidth = 1.5 + v * 2; ctx.stroke();
    }
    drawGlassOverlay(cx, cy);
  }

  function drawVioletStorm() {
    const { cx, cy } = softBg();
    const v = renderMotion;
    const t = Date.now() * (0.0005 + v * 0.0025);
    drawNebulaClouds(cx, cy, v, themeHue, 0.18);
    const arms = 4;
    for (let a = 0; a < arms; a++) {
      ctx.beginPath();
      for (let i = 0; i < 50; i++) {
        const p = i / 50;
        const ang = t * (1.2 + v) + a * ((Math.PI * 2) / arms) + p * Math.PI * 2.5;
        const wobble = Math.sin(p * 8 + t * 3) * 12 * v;
        const r = 15 + p * Math.min(w, h) * 0.4 * (0.6 + v) + wobble;
        const x = cx + Math.cos(ang) * r; const y = cy + Math.sin(ang) * r;
        if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
      }
      ctx.strokeStyle = `hsla(${themeHue + a * 18}, 85%, 58%, ${0.12 + v * 0.38})`;
      ctx.lineWidth = 2 + v * 2.5; ctx.stroke();
    }
    // Lightning
    const flash = Math.pow((Math.sin(Date.now() * 0.008) + 1) / 2, 6);
    if (flash > 0.3 || v > 0.5) {
      for (let i = 0; i < 3; i++) {
        const bx = cx + (Math.random() - 0.5) * w * 0.6;
        ctx.beginPath(); ctx.moveTo(bx, 0);
        let ly = 0;
        for (let s = 0; s < 6; s++) { ly += h / 6; ctx.lineTo(bx + (Math.random() - 0.5) * 40, ly); }
        ctx.strokeStyle = `hsla(${themeHue + 40}, 95%, 80%, ${flash * (0.2 + v * 0.5)})`;
        ctx.lineWidth = 1.5 + flash * 2; ctx.stroke();
      }
    }
    drawShards(cx, cy);
    drawGlassOverlay(cx, cy);
  }

  function drawCircuit() {
    const { cx, cy } = softBg();
    const v = renderMotion;
    const t = Date.now() * (0.0003 + v * 0.003);
    // Circuit trace paths with data flow dots
    for (let lane = -2; lane <= 2; lane++) {
      ctx.beginPath();
      for (let i = 0; i < 40; i++) {
        const p = i / 40;
        const y = h * 0.25 + p * h * 0.7;
        const x = cx + lane * (18 + p * 40) + Math.sin(t + p * 4) * 6 * v;
        if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
      }
      ctx.strokeStyle = `hsla(${themeHue + Math.abs(lane) * 15}, 90%, 60%, ${0.12 + v * 0.35})`;
      ctx.lineWidth = lane === 0 ? 3 : 1.2; ctx.stroke();
    }
    // Data flow dots
    if (!skipHeavyFx) {
      for (let i = 0; i < 8; i++) {
        const p = ((t * 0.5 + i * 0.12) % 1);
        const lane = (i % 5) - 2;
        const y = h * 0.25 + p * h * 0.7;
        const x = cx + lane * (18 + p * 40) + Math.sin(t + p * 4) * 6 * v;
        softBlob(x, y, 4 + v * 6, themeHue + 30, 0.3 + v * 0.4);
      }
    }
    drawShards(cx, cy);
    drawGlassOverlay(cx, cy);
  }

  function drawTelemetry() {
    const { cx, cy } = softBg();
    const v = renderMotion;
    const rows = 8; const cols = 12;
    for (let r = 0; r < rows; r++) {
      for (let c = 0; c < cols; c++) {
        const x = (c / cols) * w; const y = (r / rows) * h;
        const pulse = (Math.sin(Date.now() * 0.004 + r * 0.7 + c * 0.4) + 1) / 2;
        const a = (0.04 + v * 0.12) * pulse;
        ctx.fillStyle = `hsla(${themeHue + c * 8}, 85%, 55%, ${a})`;
        ctx.fillRect(x + 4, y + 4, w / cols - 8, 3);
        if (v > 0.3 && (c + r) % 4 === 0) {
          ctx.fillStyle = `hsla(${themeHue + 40}, 90%, 70%, ${0.15 + v * 0.3})`;
          ctx.fillRect(x + 4, y + 10, (w / cols - 8) * v * pulse, 6);
        }
      }
    }
    ctx.beginPath(); ctx.arc(cx, cy, 40 + v * 50, 0, Math.PI * 2);
    ctx.strokeStyle = `hsla(${themeHue}, 95%, 65%, ${0.25 + v * 0.4})`;
    ctx.lineWidth = 2; ctx.stroke();
    drawGlassOverlay(cx, cy);
  }

  function drawChrome() {
    const { cx, cy } = softBg();
    const v = renderMotion;
    const t = Date.now() * 0.001;
    for (let i = 0; i < 7; i++) {
      const r = 30 + i * 28 + v * 40;
      ctx.beginPath();
      ctx.arc(cx, cy, r, t + i, t + i + Math.PI * (0.6 + v * 0.8));
      ctx.strokeStyle = `hsla(${themeHue + i * 18}, 40%, ${55 + i * 5}%, ${0.2 + v * 0.35})`;
      ctx.lineWidth = 4 - i * 0.3; ctx.stroke();
    }
    drawGlassParticles();
    drawGlassOverlay(cx, cy);
  }

  function drawAlev() {
    const { cx, cy, motion: v } = softBg();
    const t = animT;

    // 1. Derin sıcak kehribar-akkor zemin aurası (Gözü dinlendiren sıcak ton)
    const glowR = Math.max(w, h) * (0.38 + v * 0.22);
    const core = ctx.createRadialGradient(cx, cy, 60, cx, cy, glowR);
    core.addColorStop(0, `hsla(22, 90%, 50%, ${0.22 + v * 0.25})`);
    core.addColorStop(0.35, `hsla(12, 85%, 38%, ${0.14 + v * 0.18})`);
    core.addColorStop(0.75, `hsla(350, 75%, 15%, ${0.06 + v * 0.08})`);
    core.addColorStop(1, "transparent");
    ctx.fillStyle = core;
    ctx.fillRect(0, 0, w, h);

    // 2. Yumuşak ve Ağır Dans Eden Alev Dilleri (Soft Calming Flame Waves)
    const flameLangs = skipHeavyFx ? 7 : 12;
    const baseR = Math.max(160, Math.min(w, h) * 0.22);
    for (let i = 0; i < flameLangs; i++) {
      const p = i / flameLangs;
      const ang = Math.PI * 0.1 + p * Math.PI * 0.8;
      const wave = Math.sin(t * 1.2 + i * 1.3) * 14 + Math.cos(t * 1.8 + i) * 8;
      const height = 45 + v * 95 + Math.sin(t * 1.5 + i) * 15;
      
      const x0 = cx + Math.cos(ang) * baseR;
      const y0 = cy + Math.sin(ang) * baseR * 0.9;
      const xTip = cx + Math.cos(ang) * (baseR + height) + wave * 0.4;
      const yTip = cy + Math.sin(ang) * (baseR + height) - Math.abs(wave) * 0.7 - height * 0.25;
      
      const fg = ctx.createLinearGradient(x0, y0, xTip, yTip);
      fg.addColorStop(0, `hsla(15, 90%, 48%, ${0.25 + v * 0.30})`);
      fg.addColorStop(0.50, `hsla(28, 92%, 55%, ${0.20 + v * 0.28})`);
      fg.addColorStop(1, "transparent");
      
      ctx.beginPath();
      ctx.moveTo(x0 - 20, y0);
      ctx.quadraticCurveTo(x0 + wave, (y0 + yTip) * 0.5, xTip, yTip);
      ctx.quadraticCurveTo(x0 - wave, (y0 + yTip) * 0.5, x0 + 20, y0);
      ctx.fillStyle = fg;
      ctx.fill();
    }

    // 3. Yavaşça Süzülen Yumuşak Kor Parçacıkları (Soft Floating Embers)
    const sparkCount = Math.min(particles.length, skipHeavyFx ? 20 : 45);
    const driftY = 0.0012 + v * 0.015;
    for (let i = 0; i < sparkCount; i++) {
      const p = particles[i];
      p.y -= driftY * (0.5 + p.size * 0.15);
      p.x += Math.sin(t * 1.1 + p.hueOff) * 0.0008;
      if (p.y < -0.05) { p.y = 1.05; p.x = Math.random(); }
      const px = p.x * w;
      const py = p.y * h;
      const sz = 1.8 + p.size * 1.4;
      const alpha = 0.22 + v * 0.38;

      ctx.beginPath();
      ctx.arc(px, py, sz, 0, Math.PI * 2);
      ctx.fillStyle = `hsla(26, 92%, 70%, ${alpha})`;
      ctx.fill();
    }

    // 4. Kadran Çevresinde Yumuşak Sıcak Nefes Alan Halka (Soft Ambient Ring)
    const breath = 0.5 + 0.5 * Math.sin(t * 1.6);
    const ringR = baseR + 8 + v * 35 + breath * 6;
    ctx.beginPath();
    ctx.arc(cx, cy, ringR, 0, Math.PI * 2);
    ctx.strokeStyle = `hsla(22, 90%, 65%, ${0.16 + v * 0.30})`;
    ctx.lineWidth = 2.2 + v * 1.8;
    ctx.stroke();
  }

  function drawGokkusagi() {
    const { cx, cy } = softBg();
    const v = renderMotion;
    const t = performance.now() * 0.00028;
    const drift = t * (40 + v * 35);
    applyCtxQuality();
    ctx.fillStyle = "#04060f"; ctx.fillRect(0, 0, w, h);
    const hues = [355, 20, 48, 95, 165, 205, 255, 295, 330];
    const bandCount = hues.length;
    const diag = Math.hypot(w, h);
    const bandPitch = diag / (bandCount * 0.72);
    const angle = -0.42 + Math.sin(t * 0.35) * 0.06;
    ctx.save(); ctx.translate(cx, cy); ctx.rotate(angle);
    const aBoost = 0.75 + v * 0.45;
    for (let i = -2; i < bandCount + 2; i++) {
      const hue = hues[((i % bandCount) + bandCount) % bandCount];
      const nextHue = hues[(((i + 1) % bandCount) + bandCount) % bandCount];
      const offset = ((i + drift / bandPitch) % bandCount) - bandCount * 0.5;
      const x0 = offset * bandPitch;
      const half = bandPitch * 0.8;
      const g = ctx.createLinearGradient(x0 - half, 0, x0 + half, 0);
      const aOuter = 0.18 * aBoost; const aCore = 0.62 * aBoost;
      const light = 56 + v * 8;
      g.addColorStop(0, `hsla(${hue}, 0%, 10%, 0)`);
      g.addColorStop(0.18, `hsla(${hue}, 92%, ${light}%, ${aOuter})`);
      g.addColorStop(0.42, `hsla(${hue}, 98%, ${light + 8}%, ${aCore})`);
      g.addColorStop(0.58, `hsla(${nextHue}, 96%, ${light + 6}%, ${aCore * 0.92})`);
      g.addColorStop(0.82, `hsla(${nextHue}, 90%, ${light}%, ${aOuter})`);
      g.addColorStop(1, `hsla(${nextHue}, 0%, 10%, 0)`);
      ctx.fillStyle = g; ctx.fillRect(x0 - half, -diag, half * 2, diag * 2);
    }
    ctx.restore();
    const wash = ctx.createLinearGradient(0, 0, 0, h);
    for (let i = 0; i <= 8; i++) {
      const p = i / 8;
      const hue = hues[Math.min(hues.length - 1, Math.floor(p * (hues.length - 1)))] + Math.sin(t + i) * 8;
      wash.addColorStop(p, `hsla(${hue}, 90%, 54%, ${0.12 + v * 0.12})`);
    }
    ctx.globalCompositeOperation = "screen";
    ctx.fillStyle = wash; ctx.fillRect(0, 0, w, h);
    if (!skipHeavyFx) {
      ctx.globalCompositeOperation = "lighter";
      for (let i = 0; i < 6; i++) {
        const p = (i / 6 + t * (0.18 + v * 0.12)) % 1;
        const y = p * h;
        const g = ctx.createLinearGradient(0, y - 48, 0, y + 48);
        const hue = hues[i % hues.length];
        g.addColorStop(0, "transparent");
        g.addColorStop(0.5, `hsla(${hue}, 100%, 70%, ${0.14 + v * 0.12})`);
        g.addColorStop(1, "transparent");
        ctx.fillStyle = g; ctx.fillRect(0, y - 56, w, 112);
      }
    }
    ctx.globalCompositeOperation = "source-over";
    softBlob(cx, cy, Math.min(w, h) * (0.28 + v * 0.08), 210, 0.12 + v * 0.08);
    drawGlassOverlay(cx, cy);
  }

  function drawYildiz() {
    const { cx, cy, motion: v } = softBg();
    if (!stars.length) seedStars(70);
    const count = Math.min(stars.length, skipHeavyFx ? 35 : 65);
    const speed = 0.0008 + v * 0.02;

    for (let i = 0; i < count; i++) {
      const s = stars[i];
      s.z = (s.z || Math.random()) - speed;
      if (s.z <= 0) { s.z = 1; s.x = Math.random(); s.y = Math.random(); }
      const depth = 1 - s.z;
      const dx = (s.x - 0.5) * 2;
      const dy = (s.y - 0.5) * 2;
      const px = cx + dx * w * 0.58 * depth;
      const py = cy + dy * h * 0.58 * depth;
      const sz = (1 + s.size * 1.5) * depth;
      const alpha = depth * (0.22 + v * 0.65);

      if (v > 0.05) {
        const len = v * depth * 42;
        ctx.beginPath();
        ctx.moveTo(px - dx * len, py - dy * len);
        ctx.lineTo(px, py);
        ctx.strokeStyle = `hsla(215 + s.phase * 20, 85%, 85%, ${alpha * 0.75})`;
        ctx.lineWidth = Math.max(1, sz * 0.85);
        ctx.stroke();
      } else {
        ctx.beginPath();
        ctx.arc(px, py, sz, 0, Math.PI * 2);
        ctx.fillStyle = `hsla(210 + s.phase * 20, 90%, 88%, ${alpha})`;
        ctx.fill();
      }
    }
  }

  function drawSis() {
    const { cx, cy } = softBg();
    const v = renderMotion;
    const t = animT * 0.35;
    applyCtxQuality();
    ctx.fillStyle = `hsla(${themeHue}, 40%, 8%, 0.55)`; ctx.fillRect(0, 0, w, h);
    const bands = skipHeavyFx ? 5 : 8;
    for (let i = 0; i < bands; i++) {
      const phase = t + i * 0.85;
      const y = ((Math.sin(phase * 0.4) * 0.5 + 0.5) * 0.7 + 0.15) * h;
      const amp = 40 + i * 12 + (1 - v) * 50;
      const g = ctx.createRadialGradient(cx + Math.cos(phase) * 80, y, 0, cx, y, w * 0.55);
      g.addColorStop(0, `hsla(${themeHue + i * 4}, 30%, ${55 + v * 20}%, ${0.08 + (1 - v) * 0.14})`);
      g.addColorStop(0.5, `hsla(${themeHue}, 25%, 50%, ${0.04 + (1 - v) * 0.08})`);
      g.addColorStop(1, "transparent");
      ctx.fillStyle = g; ctx.beginPath();
      ctx.ellipse(cx + Math.sin(phase) * 60, y, w * 0.55, amp, 0, 0, Math.PI * 2); ctx.fill();
    }
    softBlob(cx, cy, 60 + v * 80, themeHue, 0.1 + v * 0.2);
    drawGlassOverlay(cx, cy);
  }

  function drawMeteor() {
    const { cx, cy } = softBg();
    const v = renderMotion;
    const t = animT;
    applyCtxQuality();
    softBlob(cx, cy * 0.7, Math.min(w, h) * 0.25, themeHue + 20, 0.08 + v * 0.12);
    const count = skipHeavyFx ? 8 : 14;
    for (let i = 0; i < count; i++) {
      const seed = (i * 17.13 + Math.floor(t * (0.4 + v * 1.8) + i * 0.3) * 0.07) % 1;
      const x0 = ((i * 0.13 + seed) % 1) * w * 1.2 - w * 0.1;
      const y0 = ((i * 0.19 + seed * 0.7) % 1) * h * 0.55;
      const len = 40 + v * 160 + (i % 5) * 18;
      const ang = 0.55 + (i % 3) * 0.08;
      const x1 = x0 + Math.cos(ang) * len; const y1 = y0 + Math.sin(ang) * len;
      const g = ctx.createLinearGradient(x0, y0, x1, y1);
      g.addColorStop(0, "transparent");
      g.addColorStop(0.55, `hsla(${themeHue + 15}, 100%, 70%, ${0.15 + v * 0.45})`);
      g.addColorStop(1, `hsla(${themeHue + 40}, 100%, 85%, ${0.4 + v * 0.4})`);
      ctx.strokeStyle = g; ctx.lineWidth = 1.5 + v * 2.5; ctx.lineCap = "round";
      ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(x1, y1); ctx.stroke();
      softBlob(x1, y1, 4 + v * 8, themeHue + 50, 0.25 + v * 0.4);
    }
    drawGlassOverlay(cx, cy);
  }

  function drawLav() {
    const { cx, cy } = softBg();
    const v = renderMotion;
    const t = animT;
    applyCtxQuality();
    const floor = ctx.createLinearGradient(0, h * (0.45 - v * 0.12), 0, h);
    floor.addColorStop(0, "transparent");
    floor.addColorStop(0.35, `hsla(${themeHue}, 95%, 35%, ${0.12 + v * 0.2})`);
    floor.addColorStop(1, `hsla(${themeHue - 8}, 100%, 22%, ${0.35 + v * 0.35})`);
    ctx.fillStyle = floor; ctx.fillRect(0, 0, w, h);
    const plumes = skipHeavyFx ? 5 : 9;
    for (let i = 0; i < plumes; i++) {
      const px = ((i + 0.5) / plumes) * w;
      const rise = 0.35 + 0.55 * ((Math.sin(t * 1.2 + i * 1.4) + 1) / 2);
      const py = h - rise * h * (0.35 + v * 0.4);
      const r = 28 + v * 55 + (i % 3) * 12;
      softBlob(px, py, r, themeHue + (i % 4) * 6, 0.14 + v * 0.28);
      softBlob(px, py - r * 0.4, r * 0.55, themeHue + 25, 0.1 + v * 0.2);
    }
    softBlob(cx, h * 0.75, Math.min(w, h) * (0.22 + v * 0.15), themeHue, 0.2 + v * 0.3);
    drawGlassOverlay(cx, cy);
  }

  function drawKuzey() {
    const { cx, cy } = softBg();
    const v = renderMotion;
    const t = animT * 0.55;
    applyCtxQuality();
    ctx.fillStyle = "#02060e"; ctx.fillRect(0, 0, w, h);
    if (!stars.length) seedStars(80);
    const starN = Math.floor(20 + v * 40);
    for (let i = 0; i < starN && i < stars.length; i++) {
      const s = stars[i];
      ctx.fillStyle = `rgba(200, 220, 255, ${0.15 + s.size * 0.08})`;
      ctx.beginPath(); ctx.arc(s.x * w, s.y * h * 0.55, s.size * 0.7, 0, Math.PI * 2); ctx.fill();
    }
    drawAuroraCurtains(cx, cy, v, themeHue);
    softBlob(cx, cy * 0.85, Math.min(w, h) * 0.2, themeHue + 40, 0.1 + v * 0.15);
    drawGlassOverlay(cx, cy);
  }

  function drawBayrak() {
    const { cx, cy, motion: v } = softBg();
    const t = animT;

    // 1. Derin lüks kadife obsidyen ve karbon zemin
    ctx.fillStyle = "#080204";
    ctx.fillRect(0, 0, w, h);

    const aura = ctx.createRadialGradient(cx, cy, 40, cx, cy, Math.max(w, h) * 0.65);
    aura.addColorStop(0, `hsla(356, 92%, 36%, ${0.26 + v * 0.22})`);
    aura.addColorStop(0.5, `hsla(350, 80%, 14%, ${0.14 + v * 0.12})`);
    aura.addColorStop(1, "#030001");
    ctx.fillStyle = aura;
    ctx.fillRect(0, 0, w, h);

    // 2. Aerodinamik Rüzgar Tüneli Akış Çizgileri (Aerodynamic Streamlines)
    const streamCount = skipHeavyFx ? 4 : 8;
    const speedFactor = t * (0.9 + v * 2.2);
    for (let s = 0; s < streamCount; s++) {
      const yOffset = (s - (streamCount - 1) / 2) * (h * 0.12);
      const isCrimson = s % 2 === 0;
      ctx.beginPath();
      const segments = skipHeavyFx ? 18 : 36;
      for (let i = 0; i <= segments; i++) {
        const p = i / segments;
        const x = p * w;
        const wave = Math.sin(p * 4.2 - speedFactor + s * 0.8) * (10 + v * 18) +
                     Math.cos(p * 2.4 + t * 0.8) * (4 + v * 6);
        const y = cy + yOffset + wave;
        if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
      }
      const grad = ctx.createLinearGradient(0, 0, w, 0);
      grad.addColorStop(0, "transparent");
      grad.addColorStop(0.2, isCrimson ? `hsla(356, 95%, 58%, ${0.12 + v * 0.24})` : `rgba(255,255,255, ${0.08 + v * 0.18})`);
      grad.addColorStop(0.8, isCrimson ? `hsla(356, 95%, 65%, ${0.18 + v * 0.28})` : `rgba(255,255,255, ${0.12 + v * 0.22})`);
      grad.addColorStop(1, "transparent");
      ctx.strokeStyle = grad;
      ctx.lineWidth = isCrimson ? 2.2 + v * 1.8 : 1.4 + v * 1.2;
      ctx.stroke();
    }

    // 3. Kadran arkasında nefes alan zarif kırmızı-platin halo
    const haloR = Math.min(w, h) * (0.24 + v * 0.08);
    ctx.beginPath();
    ctx.arc(cx, cy, haloR, 0, Math.PI * 2);
    ctx.strokeStyle = `hsla(356, 92%, 60%, ${0.15 + v * 0.2})`;
    ctx.lineWidth = 2.0;
    ctx.stroke();
  }

  function miniAmbientRing(cx, cy, hue, opts = {}) {
    const v = renderMotion;
    const R = Math.min(w, h) * (opts.r ?? 0.36);
    const layers = skipHeavyFx ? 2 : 4;
    for (let i = 0; i < layers; i++) {
      ctx.beginPath(); ctx.arc(cx, cy, R + i * (opts.gap ?? 11), 0, Math.PI * 2);
      ctx.strokeStyle = `hsla(${hue}, ${opts.sat ?? 78}%, ${48 + i * 6}%, ${(opts.a ?? 0.28) - i * 0.05 + v * 0.14})`;
      ctx.lineWidth = (opts.lw ?? 2.6) - i * 0.35; ctx.stroke();
    }
    softBlob(cx, cy, R * 0.85, hue, 0.07 + v * 0.1);
  }

  function drawMiniTimeless() {
    const { cx, cy } = softBg();
    const v = renderMotion;
    const t = animT;

    ctx.fillStyle = "#080306";
    ctx.fillRect(0, 0, w, h);

    const sky = ctx.createRadialGradient(cx, cy, 50, cx, cy, Math.max(w, h) * 0.65);
    sky.addColorStop(0, `hsla(352, 80%, 28%, ${0.28 + v * 0.25})`);
    sky.addColorStop(0.45, `hsla(345, 65%, 14%, ${0.18 + v * 0.16})`);
    sky.addColorStop(1, "#040103");
    ctx.fillStyle = sky;
    ctx.fillRect(0, 0, w, h);

    const ripples = skipHeavyFx ? 3 : 6;
    for (let i = 0; i < ripples; i++) {
      const phase = (t * 0.25 + i / ripples) % 1;
      const r = Math.min(w, h) * (0.15 + phase * 0.45);
      const a = (1 - phase) * (0.18 + v * 0.24);
      ctx.beginPath();
      ctx.arc(cx, cy, r, 0, Math.PI * 2);
      ctx.strokeStyle = `hsla(355, 85%, 62%, ${a})`;
      ctx.lineWidth = 2.0 - phase * 0.8;
      ctx.stroke();
    }

    softBlob(cx + Math.sin(t * 0.4) * 25, cy + Math.cos(t * 0.35) * 15, Math.min(w, h) * (0.26 + v * 0.18), 352, 0.18 + v * 0.18);
    softBlob(cx - Math.sin(t * 0.3) * 20, cy - Math.cos(t * 0.4) * 12, Math.min(w, h) * (0.22 + v * 0.14), 10, 0.12 + v * 0.14);
  }

  function drawMiniVibrant() {
    const { cx, cy } = softBg();
    const v = renderMotion;
    const t = animT;

    // 1. Derin lüks gece fuşya/ametist zemin
    ctx.fillStyle = "#07010a";
    ctx.fillRect(0, 0, w, h);

    // 2. Yumuşak biyolüminesan sıvı ışık küreleri (Luminescent Fluid Blooms - Sıfır keskin hat)
    const blooms = [
      { x: -0.20, y: -0.10, r: 0.46, hue: 335, a: 0.35 },
      { x: 0.18, y: -0.06, r: 0.40, hue: 285, a: 0.30 },
      { x: -0.10, y: 0.18, r: 0.48, hue: 318, a: 0.28 },
      { x: 0.16, y: 0.16, r: 0.38, hue: 15, a: 0.26 },
    ];
    for (let i = 0; i < blooms.length; i++) {
      const b = blooms[i];
      const px = cx + w * b.x + Math.sin(t * 0.4 + i * 1.3) * 24;
      const py = cy + h * b.y + Math.cos(t * 0.35 + i * 1.1) * 20;
      const rr = Math.min(w, h) * (b.r + v * 0.12);
      const g = ctx.createRadialGradient(px, py, 0, px, py, rr);
      g.addColorStop(0, `hsla(${b.hue}, 95%, 62%, ${b.a + v * 0.22})`);
      g.addColorStop(0.45, `hsla(${b.hue - 15}, 85%, 35%, ${(b.a + v * 0.22) * 0.4})`);
      g.addColorStop(1, "transparent");
      ctx.fillStyle = g;
      ctx.beginPath();
      ctx.arc(px, py, rr, 0, Math.PI * 2);
      ctx.fill();
    }

    // 3. İpeksi akıcı siber-aurora tülleri (Geniş difüzyonlu tül geçişi - Çizgisiz)
    const waves = skipHeavyFx ? 2 : 4;
    for (let i = 0; i < waves; i++) {
      const yMid = cy + (i - (waves - 1) / 2) * (h * 0.22);
      const grad = ctx.createLinearGradient(0, yMid - 50, 0, yMid + 50);
      grad.addColorStop(0, "transparent");
      grad.addColorStop(0.5, `hsla(${320 + i * 22}, 95%, 66%, ${0.10 + v * 0.16})`);
      grad.addColorStop(1, "transparent");

      ctx.beginPath();
      const steps = skipHeavyFx ? 18 : 32;
      ctx.moveTo(0, yMid);
      for (let s = 0; s <= steps; s++) {
        const p = s / steps;
        const x = p * w;
        const wave = Math.sin(p * 3.2 + t * (0.6 + v * 1.2) + i * 1.2) * (24 + v * 28);
        ctx.lineTo(x, yMid + wave);
      }
      ctx.strokeStyle = grad;
      ctx.lineWidth = 22 + v * 18;
      ctx.lineCap = "round";
      ctx.stroke();
    }

    // 4. Kadran arkasında yumuşak parlayan ambient halo
    softBlob(cx, cy, Math.min(w, h) * (0.32 + v * 0.15), 335, 0.20 + v * 0.2);
  }

  function drawMiniGokart() {
    const { cx, cy } = softBg();
    const v = renderMotion;
    ctx.fillStyle = "#040404"; ctx.fillRect(0, 0, w, h);
    const R = Math.min(w, h) * 0.4;
    ctx.save(); ctx.translate(cx, cy);
    const face = ctx.createRadialGradient(0, 0, R * 0.1, 0, 0, R);
    face.addColorStop(0, "rgba(40,12,12,0.45)");
    face.addColorStop(0.7, "rgba(8,8,8,0.85)");
    face.addColorStop(1, "rgba(0,0,0,0.95)");
    ctx.fillStyle = face; ctx.beginPath(); ctx.arc(0, 0, R * 0.98, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(0, 0, R * 0.9, -Math.PI * 0.15, Math.PI * 0.75);
    ctx.strokeStyle = "rgba(255, 40, 40, 0.55)"; ctx.lineWidth = 10; ctx.stroke();
    const ticks = 40;
    for (let i = 0; i < ticks; i++) {
      const ang = -Math.PI * 0.75 + (i / (ticks - 1)) * Math.PI * 1.5;
      const major = i % 5 === 0; const red = i / (ticks - 1) > 0.78;
      const r0 = R * (major ? 0.72 : 0.82); const r1 = R * 0.94;
      ctx.beginPath();
      ctx.moveTo(Math.cos(ang) * r0, Math.sin(ang) * r0);
      ctx.lineTo(Math.cos(ang) * r1, Math.sin(ang) * r1);
      ctx.strokeStyle = red ? (major ? "rgba(255,70,70,0.95)" : "rgba(255,80,80,0.55)")
        : (major ? "rgba(255,255,255,0.9)" : "rgba(255,255,255,0.35)");
      ctx.lineWidth = major ? 2.8 : 1.2; ctx.stroke();
      if (major && i % 5 === 0) {
        const label = String(Math.round((i / (ticks - 1)) * 8));
        ctx.fillStyle = red ? "rgba(255,120,100,0.9)" : "rgba(255,255,255,0.75)";
        ctx.font = `700 ${Math.round(R * 0.09)}px system-ui,sans-serif`;
        ctx.textAlign = "center"; ctx.textBaseline = "middle";
        ctx.fillText(label, Math.cos(ang) * R * 0.58, Math.sin(ang) * R * 0.58);
      }
    }
    const needleAng = -Math.PI * 0.75 + v * Math.PI * 1.5;
    ctx.beginPath();
    ctx.moveTo(Math.cos(needleAng + Math.PI) * R * 0.14, Math.sin(needleAng + Math.PI) * R * 0.14);
    ctx.lineTo(Math.cos(needleAng) * R * 0.88, Math.sin(needleAng) * R * 0.88);
    ctx.strokeStyle = "#ff1e1e"; ctx.lineWidth = 3.2; ctx.lineCap = "round";
    ctx.shadowColor = "rgba(255,40,40,0.7)"; ctx.shadowBlur = 10; ctx.stroke(); ctx.shadowBlur = 0;
    ctx.beginPath(); ctx.arc(0, 0, 9, 0, Math.PI * 2); ctx.fillStyle = "#ff2222"; ctx.fill();
    ctx.beginPath(); ctx.arc(0, 0, 4, 0, Math.PI * 2); ctx.fillStyle = "#1a0505"; ctx.fill();
    ctx.restore();
    softBlob(cx, cy + R * 0.55, 80 + v * 60, 8, 0.12 + v * 0.16);
  }

  function drawMiniPersonal() {
    const { cx, cy } = softBg();
    const v = renderMotion;
    const t = animT;
    ctx.fillStyle = "#d6c4aa"; ctx.fillRect(0, 0, w, h);
    const g = ctx.createRadialGradient(cx, cy * 0.85, 0, cx, cy, Math.max(w, h) * 0.7);
    g.addColorStop(0, "#ebe0d0"); g.addColorStop(0.5, "#d8c6ae"); g.addColorStop(1, "#c2ab90");
    ctx.fillStyle = g; ctx.fillRect(0, 0, w, h);
    const panel = ctx.createRadialGradient(cx, cy, 0, cx, cy, Math.min(w, h) * 0.42);
    panel.addColorStop(0, "rgba(255,248,236,0.45)");
    panel.addColorStop(0.65, "rgba(230,210,180,0.12)");
    panel.addColorStop(1, "transparent");
    ctx.fillStyle = panel; ctx.fillRect(0, 0, w, h);
    softBlob(cx + Math.sin(t * 0.35) * 18, cy - 20 + Math.cos(t * 0.28) * 10, 85 + v * 45, 38, 0.16 + v * 0.12);
    miniAmbientRing(cx, cy, 32, { r: 0.36, sat: 45, a: 0.18, lw: 2 });
    softBlob(cx, cy + 100, 130 + v * 70, 35, 0.18 + v * 0.18);
  }

  function drawMiniGreen() {
    const { cx, cy } = softBg();
    const v = renderMotion;
    const t = animT;

    // 1. Derin dinlendirici zümrüt yeşili kadife gece zemini
    ctx.fillStyle = "#010904";
    ctx.fillRect(0, 0, w, h);

    const aura = ctx.createRadialGradient(cx, cy, 40, cx, cy, Math.max(w, h) * 0.7);
    aura.addColorStop(0, `hsla(140, 85%, 28%, ${0.32 + v * 0.26})`);
    aura.addColorStop(0.45, `hsla(150, 75%, 14%, ${0.18 + v * 0.16})`);
    aura.addColorStop(1, "#000502");
    ctx.fillStyle = aura;
    ctx.fillRect(0, 0, w, h);

    // 2. Yumuşak organik zümrüt ışık sisleri (Sıfır keskin halka)
    const clouds = [
      { x: -0.16, y: -0.12, r: 0.44, hue: 135, a: 0.28 },
      { x: 0.18, y: 0.08, r: 0.42, hue: 152, a: 0.26 },
      { x: 0.0, y: 0.18, r: 0.46, hue: 128, a: 0.24 },
    ];
    for (let i = 0; i < clouds.length; i++) {
      const c = clouds[i];
      const px = cx + w * c.x + Math.sin(t * 0.35 + i * 1.5) * 22;
      const py = cy + h * c.y + Math.cos(t * 0.3 + i * 1.2) * 18;
      const rr = Math.min(w, h) * (c.r + v * 0.12);
      const g = ctx.createRadialGradient(px, py, 0, px, py, rr);
      g.addColorStop(0, `hsla(${c.hue}, 90%, 55%, ${c.a + v * 0.22})`);
      g.addColorStop(0.5, `hsla(${c.hue - 10}, 75%, 25%, ${(c.a + v * 0.22) * 0.35})`);
      g.addColorStop(1, "transparent");
      ctx.fillStyle = g;
      ctx.beginPath();
      ctx.arc(px, py, rr, 0, Math.PI * 2);
      ctx.fill();
    }

    // 3. Yavaşça süzülen zümrüt biyolüminesan ışık tozları
    const fireflyCount = skipHeavyFx ? 25 : 50;
    for (let i = 0; i < fireflyCount; i++) {
      const p = particles[i % particles.length];
      p.y -= (0.0012 + v * 0.016) * (0.5 + (i % 3) * 0.2);
      p.x += Math.sin(t * 1.2 + i) * 0.0006;
      if (p.y < -0.05) { p.y = 1.05; p.x = Math.random(); }

      const px = p.x * w;
      const py = p.y * h;
      const sz = 1.6 + (i % 3) * 1.2;
      const pulse = 0.5 + 0.5 * Math.sin(t * 2.0 + i * 1.4);
      const alpha = (0.22 + pulse * 0.42) * (0.55 + v * 0.45);

      ctx.beginPath();
      ctx.arc(px, py, sz, 0, Math.PI * 2);
      ctx.fillStyle = `hsla(135, 95%, 72%, ${alpha})`;
      ctx.fill();
    }

    // 4. Kadran arkasında dinlendirici nane zümrüt aurası
    softBlob(cx, cy, Math.min(w, h) * (0.28 + v * 0.16), 135, 0.18 + v * 0.18);
  }

  function drawMiniBalance() {
    const { cx, cy } = softBg();
    const v = renderMotion;
    ctx.fillStyle = "#f0ede6"; ctx.fillRect(0, 0, w, h);
    const g = ctx.createRadialGradient(cx, cy, 0, cx, cy, Math.max(w, h) * 0.55);
    g.addColorStop(0, "#faf8f3"); g.addColorStop(1, "#e2ded4");
    ctx.fillStyle = g; ctx.fillRect(0, 0, w, h);
    const R = Math.min(w, h) * 0.38;
    ctx.save(); ctx.translate(cx, cy);
    for (let i = 0; i < 12; i++) {
      const ang = (i / 12) * Math.PI * 2 - Math.PI / 2;
      const long = i % 3 === 0;
      ctx.beginPath();
      ctx.moveTo(Math.cos(ang) * R * (long ? 0.82 : 0.9), Math.sin(ang) * R * (long ? 0.82 : 0.9));
      ctx.lineTo(Math.cos(ang) * R, Math.sin(ang) * R);
      ctx.strokeStyle = long ? "rgba(28,26,22,0.5)" : "rgba(28,26,22,0.22)";
      ctx.lineWidth = long ? 2 : 1; ctx.stroke();
    }
    ctx.beginPath(); ctx.arc(0, 0, R * 1.02, 0, Math.PI * 2);
    ctx.strokeStyle = "rgba(30,28,24,0.16)"; ctx.lineWidth = 1; ctx.stroke();
    const ang = -Math.PI / 2 + v * Math.PI * 1.55 - Math.PI * 0.28;
    ctx.beginPath();
    ctx.moveTo(Math.cos(ang + Math.PI) * 10, Math.sin(ang + Math.PI) * 10);
    ctx.lineTo(Math.cos(ang) * R * 0.9, Math.sin(ang) * R * 0.9);
    ctx.strokeStyle = "rgba(18,16,14,0.82)"; ctx.lineWidth = 1.5; ctx.lineCap = "round"; ctx.stroke();
    ctx.beginPath(); ctx.arc(0, 0, 3.5, 0, Math.PI * 2);
    ctx.fillStyle = "rgba(18,16,14,0.85)"; ctx.fill();
    ctx.restore();
  }

  function drawMapFocus() {
    // Haritayı ön plana çıkaran fütüristik navigasyon vizörü sahnesi
    ctx.fillStyle = "rgba(4, 8, 16, 0.40)";
    ctx.fillRect(0, 0, w, h);
    const { cx, cy } = viewCenter();
    const v = renderMotion;

    ctx.save();
    ctx.translate(cx, cy);
    const r = Math.min(w, h) * 0.36;

    // Dönen radar süpürme efekti
    const sweepAng = animT * 0.75;
    const sweepGrad = ctx.createLinearGradient(0, 0, Math.cos(sweepAng) * r, Math.sin(sweepAng) * r);
    sweepGrad.addColorStop(0, "rgba(0, 240, 255, 0)");
    sweepGrad.addColorStop(1, `rgba(0, 240, 255, ${0.09 + v * 0.16})`);
    ctx.beginPath();
    ctx.moveTo(0, 0);
    ctx.arc(0, 0, r, sweepAng - 0.45, sweepAng);
    ctx.closePath();
    ctx.fillStyle = sweepGrad;
    ctx.fill();

    // İnce navigasyon pusula dairesi
    ctx.beginPath();
    ctx.arc(0, 0, r * 0.96, 0, Math.PI * 2);
    ctx.strokeStyle = `rgba(0, 240, 255, ${0.14 + v * 0.24})`;
    ctx.lineWidth = 1.5;
    ctx.setLineDash([4, 10]);
    ctx.stroke();
    ctx.setLineDash([]);

    // 4 yön kerteriz çentiği
    for (let i = 0; i < 4; i++) {
      const a = (i * Math.PI) / 2;
      ctx.beginPath();
      ctx.moveTo(Math.cos(a) * (r * 0.92), Math.sin(a) * (r * 0.92));
      ctx.lineTo(Math.cos(a) * (r * 1.02), Math.sin(a) * (r * 1.02));
      ctx.strokeStyle = "rgba(0, 240, 255, 0.45)";
      ctx.lineWidth = 2;
      ctx.stroke();
    }
    ctx.restore();
  }

  function drawMap3D() {
    // 3D Harita Kokpit — 3D derinlik ızgarası, yol şeritleri ve ufukta 3D binalar
    ctx.fillStyle = "rgba(4, 7, 14, 0.45)";
    ctx.fillRect(0, 0, w, h);
    const { cx, cy } = viewCenter();
    const v = renderMotion;
    const horizonY = h * 0.42;

    ctx.save();
    // 1. 3D Perspektif Yol & Şeritler
    const roadTopW = w * 0.08;
    const roadBottomW = w * 0.72;
    const roadGrad = ctx.createLinearGradient(0, horizonY, 0, h);
    roadGrad.addColorStop(0, "rgba(0, 200, 255, 0.03)");
    roadGrad.addColorStop(1, `rgba(0, 200, 255, ${0.12 + v * 0.14})`);

    ctx.beginPath();
    ctx.moveTo(cx - roadTopW / 2, horizonY);
    ctx.lineTo(cx + roadTopW / 2, horizonY);
    ctx.lineTo(cx + roadBottomW / 2, h);
    ctx.lineTo(cx - roadBottomW / 2, h);
    ctx.closePath();
    ctx.fillStyle = roadGrad;
    ctx.fill();

    // Yol kenar kılavuz çizgileri
    ctx.beginPath();
    ctx.moveTo(cx - roadTopW / 2, horizonY);
    ctx.lineTo(cx - roadBottomW / 2, h);
    ctx.moveTo(cx + roadTopW / 2, horizonY);
    ctx.lineTo(cx + roadBottomW / 2, h);
    ctx.strokeStyle = `rgba(0, 240, 255, ${0.35 + v * 0.4})`;
    ctx.lineWidth = 2;
    ctx.stroke();

    // 3D Akıcı Yol Şeritleri (Hareket eden kesikli çizgiler)
    const offset = (animT * (1.2 + v * 3.5)) % 1;
    ctx.strokeStyle = "rgba(0, 240, 255, 0.55)";
    ctx.lineWidth = 2.5;
    for (let i = 0; i < 8; i++) {
      const p = ((i + offset) / 8);
      const y = horizonY + Math.pow(p, 2.2) * (h - horizonY);
      const segLen = Math.max(3, p * 26);
      ctx.beginPath();
      ctx.moveTo(cx, y);
      ctx.lineTo(cx, Math.min(h, y + segLen));
      ctx.stroke();
    }

    // 2. Sol & Sağ 3D Perspektif Binalar (Wireframe 3D Blocks)
    const bColor = `rgba(0, 200, 255, ${0.15 + v * 0.22})`;
    ctx.strokeStyle = bColor;
    ctx.lineWidth = 1;

    // Sol binalar
    const bLeft = [
      { x: cx - roadBottomW * 0.48, w: w * 0.12, bH: h * 0.28 },
      { x: cx - roadBottomW * 0.32, w: w * 0.08, bH: h * 0.22 },
      { x: cx - roadBottomW * 0.20, w: w * 0.05, bH: h * 0.14 }
    ];
    bLeft.forEach(b => {
      ctx.strokeRect(b.x, horizonY - b.bH * 0.4, b.w, b.bH);
      // Çatı 3D çizgileri
      ctx.beginPath();
      ctx.moveTo(b.x, horizonY - b.bH * 0.4);
      ctx.lineTo(b.x + b.w * 0.25, horizonY - b.bH * 0.4 - 10);
      ctx.lineTo(b.x + b.w * 1.25, horizonY - b.bH * 0.4 - 10);
      ctx.lineTo(b.x + b.w, horizonY - b.bH * 0.4);
      ctx.stroke();
    });

    // Sağ binalar
    const bRight = [
      { x: cx + roadBottomW * 0.16, w: w * 0.05, bH: h * 0.16 },
      { x: cx + roadBottomW * 0.25, w: w * 0.09, bH: h * 0.26 },
      { x: cx + roadBottomW * 0.38, w: w * 0.11, bH: h * 0.32 }
    ];
    bRight.forEach(b => {
      ctx.strokeRect(b.x, horizonY - b.bH * 0.4, b.w, b.bH);
      ctx.beginPath();
      ctx.moveTo(b.x, horizonY - b.bH * 0.4);
      ctx.lineTo(b.x - b.w * 0.25, horizonY - b.bH * 0.4 - 10);
      ctx.lineTo(b.x + b.w * 0.75, horizonY - b.bH * 0.4 - 10);
      ctx.lineTo(b.x + b.w, horizonY - b.bH * 0.4);
      ctx.stroke();
    });

    ctx.restore();
  }

  function horizonAt(cy) {
    return Math.max(h * 0.28, Math.min(cy * 0.62, h * 0.48));
  }

  function perspY(horizon, t) {
    const u = Math.max(0, Math.min(1, t));
    return horizon + (h - horizon) * Math.pow(u, 1.16);
  }

  function spawnBolt(originX) {
    const pts = [];
    let x = originX;
    let y = -0.02;
    pts.push({ x, y });
    while (y < 1.02) {
      y += 0.04 + Math.random() * 0.07;
      x += (Math.random() - 0.5) * 0.11;
      x = Math.max(0.02, Math.min(0.98, x));
      pts.push({ x, y });
    }
    const branches = [];
    if (pts.length > 5) {
      const bi = 2 + Math.floor(Math.random() * (pts.length - 4));
      const branch = [{ x: pts[bi].x, y: pts[bi].y }];
      let bx = pts[bi].x;
      let by = pts[bi].y;
      const dir = Math.random() < 0.5 ? -1 : 1;
      for (let k = 0; k < 4; k++) {
        by += 0.035 + Math.random() * 0.05;
        bx += dir * (0.025 + Math.random() * 0.05);
        branch.push({ x: bx, y: by });
      }
      branches.push(branch);
    }
    return { pts, branches };
  }

  function strokePoly(pts, color, width, alpha) {
    if (!pts || pts.length < 2) return;
    ctx.beginPath();
    ctx.moveTo(pts[0].x * w, pts[0].y * h);
    for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i].x * w, pts[i].y * h);
    ctx.strokeStyle = color;
    ctx.globalAlpha = alpha;
    ctx.lineWidth = width;
    ctx.lineJoin = "round";
    ctx.stroke();
    ctx.globalAlpha = 1;
  }

  function tickLightning(interval) {
    boltCooldown -= frameDt;
    boltFlash *= Math.exp(-frameDt * 3.2);
    if (boltCooldown > 0) return;
    boltCooldown = interval;
    boltFlash = 0.72 + Math.random() * 0.28;
    const n = 1 + (Math.random() > 0.5 ? 1 : 0);
    activeBolts = [];
    for (let i = 0; i < n; i++) activeBolts.push(spawnBolt(0.1 + Math.random() * 0.8));
  }

  function paintBolts(core, glow) {
    if (boltFlash < 0.05) return;
    activeBolts.forEach((bolt) => {
      strokePoly(bolt.pts, glow, 16, Math.min(1, boltFlash * 0.75));
      bolt.branches.forEach((b) => strokePoly(b, glow, 7, Math.min(1, boltFlash * 0.6)));
      strokePoly(bolt.pts, core, 2.6, Math.min(1, boltFlash * 1.35));
      bolt.branches.forEach((b) => strokePoly(b, core, 1.6, Math.min(1, boltFlash)));
    });
  }

  function drawRain(color, count, lean) {
    const n = skipHeavyFx ? Math.floor(count * 0.4) : count;
    ctx.strokeStyle = color;
    ctx.lineWidth = 1.1;
    const speed = 180 + renderMotion * 420;
    for (let i = 0; i < n; i++) {
      const x = ((i * 137.3 + worldScroll * 90) % (w + 60)) - 30;
      const y = ((i * 91.7 + worldScroll * speed) % (h + 40)) - 20;
      const len = 12 + (i % 5) * 4 + renderMotion * 22;
      ctx.globalAlpha = 0.12 + (i % 5) * 0.06;
      ctx.beginPath();
      ctx.moveTo(x, y);
      ctx.lineTo(x - lean, y + len);
      ctx.stroke();
    }
    ctx.globalAlpha = 1;
  }

  function drawTelemetryPro() {
    ctx.fillStyle = "#07110e";
    ctx.fillRect(0, 0, w, h);
    const { cx, cy } = viewCenter();
    const v = renderMotion;
    const horizon = horizonAt(cy);
    const sky = ctx.createLinearGradient(0, 0, 0, horizon);
    sky.addColorStop(0, "#04140f");
    sky.addColorStop(1, "#0c2a20");
    ctx.fillStyle = sky;
    ctx.fillRect(0, 0, w, horizon + 2);

    ctx.beginPath();
    ctx.moveTo(cx, horizon);
    ctx.lineTo(cx - w * 0.46, h + 20);
    ctx.lineTo(0, h + 20);
    ctx.lineTo(0, horizon);
    ctx.closePath();
    ctx.fillStyle = "#06140f";
    ctx.fill();
    ctx.beginPath();
    ctx.moveTo(cx, horizon);
    ctx.lineTo(cx + w * 0.46, h + 20);
    ctx.lineTo(w, h + 20);
    ctx.lineTo(w, horizon);
    ctx.closePath();
    ctx.fill();

    const scroll = worldScroll % 1;
    ctx.strokeStyle = `hsla(${themeHue}, 90%, 58%, ${0.35 + v * 0.4})`;
    ctx.lineWidth = 2;
    for (let i = 0; i < 8; i++) {
      const t = (i / 8 + scroll * 0.35) % 1;
      const y = perspY(horizon, t);
      ctx.beginPath();
      ctx.moveTo(cx - (18 + t * w * 0.22), y);
      ctx.lineTo(cx + (18 + t * w * 0.22), y);
      ctx.stroke();
    }

    ctx.save();
    ctx.translate(cx, cy);
    ctx.beginPath();
    ctx.arc(0, 0, 78 + v * 26, 0, Math.PI * 2);
    ctx.strokeStyle = `hsla(${themeHue}, 85%, 62%, ${0.2 + v * 0.3})`;
    ctx.stroke();
    const gx = Math.sin(animT * 2.2) * (16 + v * 34);
    const gy = Math.cos(animT * 1.7) * (12 + v * 24);
    ctx.beginPath();
    ctx.arc(gx, gy, 4.5, 0, Math.PI * 2);
    ctx.fillStyle = `hsl(${themeHue + 28}, 100%, 64%)`;
    ctx.shadowColor = `hsl(${themeHue + 28}, 100%, 64%)`;
    ctx.shadowBlur = 12;
    ctx.fill();
    ctx.restore();
  }

  function drawStealthHud() {
    ctx.fillStyle = "#000";
    ctx.fillRect(0, 0, w, h);
    const { cx, cy } = viewCenter();
    const v = renderMotion;
    ctx.save();
    ctx.strokeStyle = `rgba(150, 205, 255, ${0.08 + v * 0.08})`;
    ctx.lineWidth = 1;
    const step = skipHeavyFx ? 72 : 48;
    for (let x = 0; x < w; x += step) {
      ctx.beginPath();
      ctx.moveTo(x, 0);
      ctx.lineTo(x, h);
      ctx.stroke();
    }
    for (let y = 0; y < h; y += step) {
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(w, y);
      ctx.stroke();
    }
    const arm = Math.min(w, h) * 0.16;
    ctx.strokeStyle = `rgba(186, 220, 255, ${0.45 + v * 0.3})`;
    ctx.lineWidth = 1.6;
    const corners = [
      [cx - arm, cy - arm, 1, 1],
      [cx + arm, cy - arm, -1, 1],
      [cx - arm, cy + arm, 1, -1],
      [cx + arm, cy + arm, -1, -1],
    ];
    corners.forEach(([x, y, sx, sy]) => {
      ctx.beginPath();
      ctx.moveTo(x, y + sy * 22);
      ctx.lineTo(x, y);
      ctx.lineTo(x + sx * 22, y);
      ctx.stroke();
    });
    const lineW = Math.min(w * 0.38, 260);
    const grad = ctx.createLinearGradient(cx - lineW, 0, cx + lineW, 0);
    grad.addColorStop(0, "rgba(255, 255, 255, 0)");
    grad.addColorStop(0.5, `rgba(140, 200, 255, ${0.28 + v * 0.4})`);
    grad.addColorStop(1, "rgba(255, 255, 255, 0)");
    ctx.beginPath();
    ctx.moveTo(cx - lineW, cy);
    ctx.lineTo(cx + lineW, cy);
    ctx.strokeStyle = grad;
    ctx.stroke();
    ctx.restore();
  }

  function drawWeatherSky() {
    const { cx, cy } = viewCenter();
    const v = renderMotion;
    const grad = ctx.createLinearGradient(0, 0, 0, h);
    grad.addColorStop(0, "#12345f");
    grad.addColorStop(0.45, "#0b2244");
    grad.addColorStop(1, "#07111f");
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, w, h);

    const sunY = cy * 0.42;
    const sunGrad = ctx.createRadialGradient(cx, sunY, 8, cx, sunY, Math.min(w, h) * 0.5);
    sunGrad.addColorStop(0, `rgba(255, 228, 150, ${0.55 + v * 0.2})`);
    sunGrad.addColorStop(0.18, `rgba(255, 190, 90, ${0.22 + v * 0.12})`);
    sunGrad.addColorStop(0.45, "rgba(40, 140, 220, 0.08)");
    sunGrad.addColorStop(1, "rgba(0, 0, 0, 0)");
    ctx.fillStyle = sunGrad;
    ctx.fillRect(0, 0, w, h);

    const clouds = skipHeavyFx ? 4 : 7;
    for (let i = 0; i < clouds; i++) {
      const drift = ((worldScroll * (18 + i * 6) + i * 180) % (w + 280)) - 140;
      const y = h * (0.12 + (i % 4) * 0.08);
      const rw = 90 + (i % 3) * 40;
      ctx.fillStyle = `rgba(230, 242, 255, ${0.08 + (i % 3) * 0.04})`;
      ctx.beginPath();
      ctx.ellipse(drift, y, rw, 22 + (i % 2) * 8, 0, 0, Math.PI * 2);
      ctx.ellipse(drift + rw * 0.45, y + 6, rw * 0.7, 18, 0, 0, Math.PI * 2);
      ctx.fill();
    }

    ctx.save();
    for (let i = 0; i < 5; i++) {
      const lineY = cy * 0.55 + i * (h * 0.07);
      const shift = ((worldScroll * (40 + v * 80) + i * 160) % (w + 240)) - 120;
      ctx.beginPath();
      ctx.moveTo(shift, lineY);
      ctx.lineTo(shift + 120 + v * 90, lineY);
      ctx.strokeStyle = `rgba(160, 220, 255, ${0.1 + v * 0.16})`;
      ctx.lineWidth = 1.6;
      ctx.setLineDash([10, 16]);
      ctx.stroke();
    }
    ctx.setLineDash([]);
    ctx.restore();
  }

  function drawCyberStorm() {
    const { cx, cy } = viewCenter();
    const v = renderMotion;
    const sky = ctx.createLinearGradient(0, 0, 0, h);
    sky.addColorStop(0, "#14081f");
    sky.addColorStop(0.55, "#0a0614");
    sky.addColorStop(1, "#05030a");
    ctx.fillStyle = sky;
    ctx.fillRect(0, 0, w, h);
    tickLightning(v > 0.45 ? 0.28 : 0.7);
    if (boltFlash > 0.08) {
      ctx.fillStyle = `rgba(190, 120, 255, ${boltFlash * 0.22})`;
      ctx.fillRect(0, 0, w, h);
    }
    drawRain("rgba(210, 170, 255, 0.7)", 48, 6);
    paintBolts("#f4e8ff", "#c060ff");
    ctx.beginPath();
    ctx.arc(cx, cy, Math.min(w, h) * 0.32 + Math.sin(animT * 6) * 5, 0, Math.PI * 2);
    ctx.strokeStyle = `hsla(${themeHue}, 90%, 66%, ${0.18 + v * 0.28})`;
    ctx.lineWidth = 2;
    ctx.stroke();
  }

  function drawDesertDune() {
    const { cx, cy } = viewCenter();
    const v = renderMotion;
    const grad = ctx.createLinearGradient(0, 0, 0, h);
    grad.addColorStop(0, "#2a1020");
    grad.addColorStop(0.38, "#c45a18");
    grad.addColorStop(0.55, "#f0a04a");
    grad.addColorStop(1, "#6a3510");
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, w, h);
    const sun = ctx.createRadialGradient(cx, cy * 0.7, 8, cx, cy * 0.7, 90);
    sun.addColorStop(0, "rgba(255, 236, 190, 0.95)");
    sun.addColorStop(1, "rgba(255, 140, 40, 0)");
    ctx.fillStyle = sun;
    ctx.beginPath();
    ctx.arc(cx, cy * 0.7, 46, 0, Math.PI * 2);
    ctx.fill();

    const layers = [
      { y: h * 0.58, amp: 28 + v * 16, color: "#c47a32", speed: 12 },
      { y: h * 0.7, amp: 36 + v * 18, color: "#a85a22", speed: 22 },
      { y: h * 0.84, amp: 22 + v * 10, color: "#7a3c14", speed: 34 },
    ];
    layers.forEach((layer) => {
      ctx.beginPath();
      ctx.moveTo(0, h + 20);
      for (let x = 0; x <= w; x += 16) {
        const dy = Math.sin(x * 0.008 + worldScroll * layer.speed * 0.05) * layer.amp;
        ctx.lineTo(x, layer.y + dy);
      }
      ctx.lineTo(w, h + 20);
      ctx.closePath();
      ctx.fillStyle = layer.color;
      ctx.fill();
    });
  }

  function drawTeslaVision() {
    // Tesla Ön Görünüm: Matrix LED Farlar, DRL Kaşları, Işıklı Tesla Logo
    const grad = ctx.createLinearGradient(0, 0, 0, h);
    grad.addColorStop(0, "rgba(8, 9, 12, 0.95)");
    grad.addColorStop(0.5, "rgba(14, 15, 20, 0.92)");
    grad.addColorStop(1, "rgba(4, 4, 6, 0.98)");
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, w, h);

    const { cx, cy } = viewCenter();
    const v = renderMotion;
    const carW = Math.min(w * 0.88, 560);
    const carH = carW * 0.38;
    const vCenterY = cy * 1.15;

    ctx.save();

    // 1. Far Yol Işık Hüzmesi (Zemine doğru genişleyen konik ışık huzmesi)
    const beamLeftX = cx - carW * 0.32;
    const beamRightX = cx + carW * 0.32;
    const beamY = vCenterY - carH * 0.05;

    const leftBeamGrad = ctx.createRadialGradient(beamLeftX, beamY, 4, beamLeftX, beamY + h * 0.5, h * 0.6);
    leftBeamGrad.addColorStop(0, `rgba(220, 240, 255, ${0.35 + v * 0.35})`);
    leftBeamGrad.addColorStop(0.35, `rgba(230, 45, 45, ${0.12 + v * 0.18})`);
    leftBeamGrad.addColorStop(1, "rgba(0, 0, 0, 0)");

    ctx.fillStyle = leftBeamGrad;
    ctx.beginPath();
    ctx.moveTo(beamLeftX, beamY);
    ctx.lineTo(cx - carW * 0.70, h + 50);
    ctx.lineTo(cx - carW * 0.05, h + 50);
    ctx.closePath();
    ctx.fill();

    const rightBeamGrad = ctx.createRadialGradient(beamRightX, beamY, 4, beamRightX, beamY + h * 0.5, h * 0.6);
    rightBeamGrad.addColorStop(0, `rgba(220, 240, 255, ${0.35 + v * 0.35})`);
    rightBeamGrad.addColorStop(0.35, `rgba(230, 45, 45, ${0.12 + v * 0.18})`);
    rightBeamGrad.addColorStop(1, "rgba(0, 0, 0, 0)");

    ctx.fillStyle = rightBeamGrad;
    ctx.beginPath();
    ctx.moveTo(beamRightX, beamY);
    ctx.lineTo(cx + carW * 0.05, h + 50);
    ctx.lineTo(cx + carW * 0.70, h + 50);
    ctx.closePath();
    ctx.fill();

    // 2. Tesla Kaput & Ön Bumper Hatları
    ctx.strokeStyle = `rgba(255, 255, 255, ${0.20 + v * 0.15})`;
    ctx.lineWidth = 1.8;
    ctx.beginPath();
    ctx.moveTo(cx - carW * 0.16, vCenterY - carH * 0.52);
    ctx.quadraticCurveTo(cx - carW * 0.24, vCenterY - carH * 0.35, cx - carW * 0.28, vCenterY - carH * 0.10);
    ctx.stroke();

    ctx.beginPath();
    ctx.moveTo(cx + carW * 0.16, vCenterY - carH * 0.52);
    ctx.quadraticCurveTo(cx + carW * 0.24, vCenterY - carH * 0.35, cx + carW * 0.28, vCenterY - carH * 0.10);
    ctx.stroke();

    // Ön Burun Kıvrımı
    ctx.strokeStyle = `rgba(255, 255, 255, ${0.30 + v * 0.20})`;
    ctx.lineWidth = 2.0;
    ctx.beginPath();
    ctx.moveTo(cx - carW * 0.36, vCenterY + carH * 0.08);
    ctx.quadraticCurveTo(cx, vCenterY + carH * 0.16, cx + carW * 0.36, vCenterY + carH * 0.08);
    ctx.stroke();

    // Alt Splitter
    ctx.strokeStyle = `rgba(235, 45, 45, ${0.45 + v * 0.40})`;
    ctx.lineWidth = 2.4;
    ctx.beginPath();
    ctx.moveTo(cx - carW * 0.42, vCenterY + carH * 0.38);
    ctx.quadraticCurveTo(cx, vCenterY + carH * 0.44, cx + carW * 0.42, vCenterY + carH * 0.38);
    ctx.stroke();

    // 3. Işıklı Tesla 'T' Logosu
    const logoY = vCenterY - carH * 0.18;
    const logoScale = Math.min(w, h) > 600 ? 1.0 : 0.85;

    const logoGlow = ctx.createRadialGradient(cx, logoY, 2, cx, logoY, 30 * logoScale);
    logoGlow.addColorStop(0, `rgba(240, 50, 50, ${0.65 + v * 0.30})`);
    logoGlow.addColorStop(0.5, "rgba(255, 255, 255, 0.25)");
    logoGlow.addColorStop(1, "rgba(0, 0, 0, 0)");
    ctx.fillStyle = logoGlow;
    ctx.beginPath();
    ctx.arc(cx, logoY, 30 * logoScale, 0, Math.PI * 2);
    ctx.fill();

    ctx.fillStyle = "rgba(255, 255, 255, 0.96)";
    ctx.beginPath();
    ctx.moveTo(cx - 20 * logoScale, logoY - 6 * logoScale);
    ctx.quadraticCurveTo(cx, logoY - 12 * logoScale, cx + 20 * logoScale, logoY - 6 * logoScale);
    ctx.quadraticCurveTo(cx, logoY - 8 * logoScale, cx - 20 * logoScale, logoY - 6 * logoScale);
    ctx.closePath();
    ctx.fill();

    ctx.beginPath();
    ctx.moveTo(cx - 7 * logoScale, logoY - 3 * logoScale);
    ctx.quadraticCurveTo(cx - 2 * logoScale, logoY + 6 * logoScale, cx, logoY + 16 * logoScale);
    ctx.quadraticCurveTo(cx + 2 * logoScale, logoY + 6 * logoScale, cx + 7 * logoScale, logoY - 3 * logoScale);
    ctx.closePath();
    ctx.fill();

    // 4. Matrix LED Farlar (Sol & Sağ)
    const leftHLY = vCenterY - carH * 0.06;
    ctx.shadowColor = "#e62d2d";
    ctx.shadowBlur = 14 + v * 16;
    ctx.strokeStyle = `rgba(255, 255, 255, ${0.92 + v * 0.08})`;
    ctx.lineWidth = 3.2;

    // Sol DRL Kaşı
    ctx.beginPath();
    ctx.moveTo(cx - carW * 0.20, leftHLY);
    ctx.bezierCurveTo(
      cx - carW * 0.28, leftHLY - carH * 0.08,
      cx - carW * 0.38, leftHLY - carH * 0.18,
      cx - carW * 0.44, leftHLY - carH * 0.22
    );
    ctx.stroke();

    for (let i = 0; i < 3; i++) {
      const px = cx - carW * (0.24 + i * 0.06);
      const py = leftHLY - carH * (0.04 + i * 0.04);
      ctx.fillStyle = "#ffffff";
      ctx.beginPath();
      ctx.arc(px, py, 3.5, 0, Math.PI * 2);
      ctx.fill();
    }

    // Sağ DRL Kaşı
    ctx.beginPath();
    ctx.moveTo(cx + carW * 0.20, leftHLY);
    ctx.bezierCurveTo(
      cx + carW * 0.28, leftHLY - carH * 0.08,
      cx + carW * 0.38, leftHLY - carH * 0.18,
      cx + carW * 0.44, leftHLY - carH * 0.22
    );
    ctx.stroke();

    for (let i = 0; i < 3; i++) {
      const px = cx + carW * (0.24 + i * 0.06);
      const py = leftHLY - carH * (0.04 + i * 0.04);
      ctx.fillStyle = "#ffffff";
      ctx.beginPath();
      ctx.arc(px, py, 3.5, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.shadowBlur = 0;

    // 5. Alt Sis Farları
    const fogY = vCenterY + carH * 0.22;
    ctx.strokeStyle = "rgba(255, 255, 255, 0.88)";
    ctx.lineWidth = 2.4;
    ctx.beginPath();
    ctx.moveTo(cx - carW * 0.38, fogY);
    ctx.lineTo(cx - carW * 0.32, fogY);
    ctx.moveTo(cx + carW * 0.32, fogY);
    ctx.lineTo(cx + carW * 0.38, fogY);
    ctx.stroke();

    ctx.restore();
  }

  function drawCyberBlade() {
    // Cybertruck Boydan Boya LED Işık Şeridi
    ctx.fillStyle = "rgba(6, 8, 12, 0.95)";
    ctx.fillRect(0, 0, w, h);

    const { cx, cy } = viewCenter();
    const v = renderMotion;
    const carW = Math.min(w * 0.90, 580);
    const barY = cy * 1.05;

    ctx.save();

    // 1. Zemin Yansıması
    const beamGrad = ctx.createLinearGradient(cx, barY, cx, h);
    beamGrad.addColorStop(0, `rgba(0, 235, 255, ${0.25 + v * 0.30})`);
    beamGrad.addColorStop(1, "rgba(0, 0, 0, 0)");
    ctx.fillStyle = beamGrad;
    ctx.beginPath();
    ctx.moveTo(cx - carW * 0.45, barY);
    ctx.lineTo(cx - carW * 0.70, h + 30);
    ctx.lineTo(cx + carW * 0.70, h + 30);
    ctx.lineTo(cx + carW * 0.45, barY);
    ctx.closePath();
    ctx.fill();

    // 2. Kesintisiz Ufuk LED Işık Şeridi
    ctx.shadowColor = "#00e5ff";
    ctx.shadowBlur = 18 + v * 15;
    ctx.strokeStyle = "rgba(255, 255, 255, 0.98)";
    ctx.lineWidth = 3.5;
    ctx.beginPath();
    ctx.moveTo(cx - carW * 0.45, barY);
    ctx.lineTo(cx + carW * 0.45, barY);
    ctx.stroke();

    // 3. Geometrik Kaput Hatları
    ctx.shadowBlur = 0;
    ctx.strokeStyle = "rgba(255, 255, 255, 0.22)";
    ctx.lineWidth = 1.6;
    ctx.beginPath();
    ctx.moveTo(cx - carW * 0.28, barY - 65);
    ctx.lineTo(cx, barY - 80);
    ctx.lineTo(cx + carW * 0.28, barY - 65);
    ctx.stroke();

    ctx.restore();
  }

  function drawGtAero() {
    // Taycan GT: 4-Noktalı Matrix LED Farlar
    ctx.fillStyle = "rgba(5, 8, 15, 0.95)";
    ctx.fillRect(0, 0, w, h);

    const { cx, cy } = viewCenter();
    const v = renderMotion;
    const carW = Math.min(w * 0.88, 550);
    const hlY = cy * 1.08;

    ctx.save();

    const hlLeftCX = cx - carW * 0.34;
    const hlRightCX = cx + carW * 0.34;

    ctx.shadowColor = "#3b82f6";
    ctx.shadowBlur = 12 + v * 14;

    // Sol 4-Nokta LED
    for (let r = 0; r < 2; r++) {
      for (let c = 0; c < 2; c++) {
        const lx = hlLeftCX + (c * 15 - 7.5);
        const ly = hlY + (r * 13 - 6.5);
        ctx.fillStyle = "#ffffff";
        ctx.fillRect(lx - 4, ly - 3, 8, 6);
      }
    }

    // Sağ 4-Nokta LED
    for (let r = 0; r < 2; r++) {
      for (let c = 0; c < 2; c++) {
        const rx = hlRightCX + (c * 15 - 7.5);
        const ry = hlY + (r * 13 - 6.5);
        ctx.fillStyle = "#ffffff";
        ctx.fillRect(rx - 4, ry - 3, 8, 6);
      }
    }

    ctx.shadowBlur = 0;
    // Çamurluk Kavisleri
    ctx.strokeStyle = "rgba(255, 255, 255, 0.28)";
    ctx.lineWidth = 1.8;
    ctx.beginPath();
    ctx.moveTo(cx - carW * 0.44, hlY + 30);
    ctx.quadraticCurveTo(cx - carW * 0.36, hlY - 32, cx - carW * 0.22, hlY - 20);
    ctx.stroke();

    ctx.beginPath();
    ctx.moveTo(cx + carW * 0.44, hlY + 30);
    ctx.quadraticCurveTo(cx + carW * 0.36, hlY - 32, cx + carW * 0.22, hlY - 20);
    ctx.stroke();

    ctx.restore();
  }

  function drawTree(x, groundY, scale, seed) {
    const trunkH = 78 * scale;
    const trunkW = Math.max(2, 9 * scale);
    ctx.fillStyle = seed % 2 ? "#2a1a10" : "#3a2414";
    ctx.fillRect(x - trunkW / 2, groundY - trunkH, trunkW, trunkH);
    for (let layer = 0; layer < 3; layer++) {
      const cw = (46 - layer * 8) * scale;
      const ch = 34 * scale;
      const top = groundY - trunkH * 0.72 - layer * 18 * scale;
      ctx.beginPath();
      ctx.moveTo(x, top - ch);
      ctx.lineTo(x + cw, top + 6);
      ctx.lineTo(x - cw, top + 6);
      ctx.closePath();
      const g = 70 + layer * 22 + (seed % 4) * 8;
      ctx.fillStyle = `rgb(${12 + layer * 6}, ${g}, ${28 + layer * 8})`;
      ctx.fill();
    }
  }

  const DRAWERS = {
    glow: drawGlow, aurora: drawGlow,
    particles: drawParticlesMode, vortex: drawVortex, horizon: drawHorizon,
    "deep-ocean": drawDeepOcean, "electric-ice": drawElectricIce,
    pulse: drawPulse, "solar-flare": drawSolarFlare, plasma: drawPlasma,
    warp: drawWarp, streak: drawStreak, chrome: drawChrome,
    tunnel: drawTunnel, redline: drawRedline, grid: drawGrid,
    circuit: drawCircuit, telemetry: drawTelemetry, neon: drawNeon,
    matrix: drawMatrix, "night-city": drawNightCity,
    "violet-storm": drawVioletStorm, "cyber-lime": drawCyberLime,
    alev: drawAlev, yildiz: drawYildiz, bayrak: drawBayrak,
    sis: drawSis, meteor: drawMeteor, lav: drawLav, kuzey: drawKuzey,
    "mini-timeless": drawMiniTimeless, "mini-vibrant": drawMiniVibrant,
    "mini-personal": drawMiniPersonal, "mini-green": drawMiniGreen,
    "weather-sky": drawWeatherSky, "map-focus": drawMapFocus,
    "map-3d": drawMap3D,
    "cyber-storm": drawCyberStorm, "desert-dune": drawDesertDune,
    "telemetry-pro": drawTelemetryPro, "stealth-hud": drawStealthHud,
  };

  const MODES = [
    /* ⚡ Çift Kadranlı Temalar (Dual Gauge Cluster: Hız + Güç/kW & Regen) */
    { key: "telemetry-pro", labelKey: "visualTelemetryPro", group: "race", gauge: "dual" },
    { key: "cyber-storm", labelKey: "visualCyberStorm", group: "sport", gauge: "dual" },
    { key: "redline", labelKey: "visualRedline", group: "race", gauge: "dual" },

    /* 📱 Tek Kadran Dijital Göstergeler (Single Digital Dial) */
    { key: "stealth-hud", labelKey: "visualStealthHud", group: "sport", gauge: "digital" },
    { key: "night-city", labelKey: "visualNightCity", group: "neon", gauge: "digital" },
    { key: "warp", labelKey: "visualWarp", group: "sport", gauge: "digital" },
    { key: "weather-sky", labelKey: "visualWeatherSky", group: "ambient", gauge: "digital" },
    { key: "map-3d", labelKey: "visualMap3D", group: "ambient", gauge: "digital" },
    { key: "mini-vibrant", labelKey: "visualMiniVibrant", group: "mini", gauge: "digital" },
    { key: "mini-green", labelKey: "visualMiniGreen", group: "mini", gauge: "digital" },
    { key: "mini-personal", labelKey: "visualMiniPersonal", group: "mini", gauge: "digital" },
    { key: "alev", labelKey: "visualAlev", group: "sport", gauge: "digital" },
    { key: "plasma", labelKey: "visualPlasma", group: "sport", gauge: "digital" },
    { key: "neon", labelKey: "visualNeon", group: "neon", gauge: "digital" },
    { key: "bayrak", labelKey: "visualBayrak", group: "sport", gauge: "digital" },

    /* ⏱️ Tek Kadran Analog Göstergeler (Single Analog Dial) */
    { key: "deep-ocean", labelKey: "visualDeepOcean", group: "ambient", gauge: "analog" },
    { key: "desert-dune", labelKey: "visualDesertDune", group: "sport", gauge: "analog" },
    { key: "mini-timeless", labelKey: "visualMiniTimeless", group: "mini", gauge: "analog" },
    { key: "tunnel", labelKey: "visualTunnel", group: "race", gauge: "analog" },
    { key: "glow", labelKey: "visualGlow", group: "ambient", gauge: "analog" },
    { key: "yildiz", labelKey: "visualYildiz", group: "ambient", gauge: "analog" },
  ];

  function loop() {
    const now = performance.now();
    const dt = lastFrameAt ? Math.min(0.05, (now - lastFrameAt) / 1000) : 0.016;
    lastFrameAt = now;
    frameN++;
    frameDt = dt;
    advanceMotion();
    worldScroll = (worldScroll + dt * (0.55 + renderMotion * 6.4)) % 1000;
    animT += dt * (0.04 + renderMotion * 2.4);
    skipHeavyFx = dt > 0.028;
    try {
      ctx.globalAlpha = 1;
      ctx.shadowBlur = 0;
      ctx.shadowColor = "transparent";
      ctx.globalCompositeOperation = "source-over";
      ctx.setLineDash([]);
      const draw = DRAWERS[mode] || drawGlow;
      draw();
      drawBoostRipples(dt);
    } catch (err) {
      console.warn("Scene draw failed", mode, err);
      try { drawGlow(); drawBoostRipples(dt); } catch (_) {}
    }
    raf = requestAnimationFrame(loop);
  }

  function destroy() {
    if (raf) cancelAnimationFrame(raf);
    window.removeEventListener("resize", resize);
    if (resizeObserver) {
      try { resizeObserver.disconnect(); } catch (_) {}
      resizeObserver = null;
    }
  }

  function getModeMeta(key) { return MODES.find((m) => m.key === key) || null; }

  return {
    DEFAULT_MODE: "alev",
    getModes: () => MODES,
    getModeMeta, getThemeHue, init, setMode, setSpeed, destroy,
  };
})();
