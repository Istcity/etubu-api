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
    alev: 8, gokkusagi: 200, yildiz: 220, bayrak: 142, sis: 198,
    meteor: 32, lav: 14, kuzey: 155,
    "mini-timeless": 0, "mini-vibrant": 340, "mini-gokart": 8,
    "mini-personal": 32, "mini-green": 118, "mini-balance": 40,
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
    const hud = document.getElementById("speedHud");
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
    advanceMotion();
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
  }

  function drawRedline() {
    const { cx, cy, motion: v } = softBg();
    const t = animT;

    // 1. Derin kadife kırmızı yarış kokpiti zemini (Gözü yormayan yumuşak akkor)
    const rlineR = Math.max(w, h) * (0.42 + v * 0.28);
    const g = ctx.createRadialGradient(cx, cy, 60, cx, cy, rlineR);
    g.addColorStop(0, `hsla(355, 85%, 42%, ${0.24 + v * 0.26})`);
    g.addColorStop(0.40, `hsla(12, 80%, 28%, ${0.14 + v * 0.18})`);
    g.addColorStop(0.80, `hsla(355, 70%, 10%, ${0.06 + v * 0.08})`);
    g.addColorStop(1, "transparent");
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, w, h);

    // 2. Yumuşak akıcı aerodinamik kırmızı şeritler (Gözü yormayan yumuşak dalgalar)
    const ribbons = skipHeavyFx ? 3 : 5;
    for (let r = 0; r < ribbons; r++) {
      const yBase = cy + (r - (ribbons - 1) / 2) * (h * 0.22);
      ctx.beginPath();
      const steps = skipHeavyFx ? 16 : 28;
      for (let s = 0; s <= steps; s++) {
        const p = s / steps;
        const x = p * w;
        const wave = Math.sin(p * 4.2 - t * (0.8 + v * 2.2) + r * 1.4) * (18 + v * 25);
        const y = yBase + wave;
        if (s === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
      }
      ctx.strokeStyle = `hsla(${352 + r * 4}, 90%, 62%, ${0.12 + v * 0.28})`;
      ctx.lineWidth = 2.5 + v * 2.5;
      ctx.stroke();
    }

    // 3. Yavaşça süzülen yumuşak yakut kor parçacıkları (Silky Ruby Embers)
    const sparkCount = Math.min(particles.length, skipHeavyFx ? 25 : 50);
    for (let i = 0; i < sparkCount; i++) {
      const p = particles[i];
      p.y -= (0.0012 + v * 0.016) * (0.6 + p.size * 0.15);
      p.x += Math.sin(t * 1.2 + p.hueOff) * 0.0008;
      if (p.y < -0.05) { p.y = 1.05; p.x = Math.random(); }

      const px = p.x * w;
      const py = p.y * h;
      const sz = (1.8 + p.size * 1.4) * (0.8 + v * 0.4);
      const alpha = 0.22 + v * 0.45;

      ctx.beginPath();
      ctx.arc(px, py, sz, 0, Math.PI * 2);
      ctx.fillStyle = `hsla(356, 92%, 70%, ${alpha})`;
      ctx.fill();
    }

    // 4. Kadran çevresinde yumuşak nefes alan kızıl halka
    const breath = 0.5 + 0.5 * Math.sin(t * 1.8);
    const arcR = Math.max(160, Math.min(w, h) * 0.22) + v * 40 + breath * 6;
    ctx.beginPath();
    ctx.arc(cx, cy, arcR, -Math.PI * 0.85, Math.PI * 0.85);
    ctx.strokeStyle = `hsla(355, 92%, 65%, ${0.20 + v * 0.40})`;
    ctx.lineWidth = 2.5 + v * 2.5;
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
    if (!warpStars.length) seedWarpStars(skipHeavyFx ? 90 : 180);

    const speedZ = 0.004 + v * 0.065;
    const maxRadius = Math.max(w, h);

    // 1. Merkezden Ufka Yayılan Işık Hızı Parçacıkları (Relativistic Hyperspace)
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

      // 3D Perspektif İzdüşümü (Tüm ekrana yayılır)
      const pz = Math.max(0.015, s.z);
      const px = cx + (s.x / pz) * (w * 0.55);
      const py = cy + (s.y / pz) * (h * 0.55);

      const oldPz = Math.max(0.015, prevZ + (v > 0.04 ? speedZ * (2 + v * 7) : speedZ * 1.5));
      const oldPx = cx + (s.x / oldPz) * (w * 0.55);
      const oldPy = cy + (s.y / oldPz) * (h * 0.55);

      const alpha = Math.min(1, (1 - s.z) * (0.45 + v * 0.55));
      const thickness = Math.max(1.2, (1 - s.z) * (2 + v * 4.5));

      const g = ctx.createLinearGradient(oldPx, oldPy, px, py);
      g.addColorStop(0, "transparent");
      g.addColorStop(0.3, `hsla(${s.hue}, 95%, 65%, ${alpha * 0.5})`);
      g.addColorStop(1, `hsla(${s.hue + 25}, 100%, 88%, ${alpha})`);
      ctx.beginPath();
      ctx.moveTo(oldPx, oldPy);
      ctx.lineTo(px, py);
      ctx.strokeStyle = g;
      ctx.lineWidth = thickness;
      ctx.stroke();
    }

    // 2. Genişleyen Warp Şok Dalgası Halkaları (Expansion Shockwave Rings)
    const ringCount = 4;
    for (let r = 0; r < ringCount; r++) {
      const prog = ((t * (0.5 + v * 1.5) + r / ringCount) % 1);
      const radius = 80 + prog * maxRadius * 0.75;
      const alpha = (1 - prog) * (0.15 + v * 0.55);
      ctx.beginPath();
      ctx.arc(cx, cy, radius, 0, Math.PI * 2);
      ctx.strokeStyle = `hsla(${themeHue + prog * 45}, 100%, 75%, ${alpha})`;
      ctx.lineWidth = 2.0 + (1 - prog) * 4;
      ctx.stroke();
    }
  }

  function drawNeon() {
    const { cx, cy, motion: v } = softBg();
    const t = animT;
    const pulse = 0.5 + 0.5 * Math.sin(t * 1.5);
    softBlob(cx, cy, 110 + v * 160 + pulse * 18, themeHue, 0.16 + v * 0.25 + pulse * 0.06);
    softBlob(cx - w * 0.2, cy + h * 0.08, 85 + v * 70, themeHue + 35, 0.09 + v * 0.15);
    softBlob(cx + w * 0.18, cy - h * 0.06, 75 + v * 60, themeHue - 25, 0.08 + v * 0.14);
    // Yumuşak anamorfik ufuk ışığı
    const flareH = 8 + v * 16;
    const flare = ctx.createLinearGradient(0, cy - flareH, 0, cy + flareH);
    flare.addColorStop(0, "transparent");
    flare.addColorStop(0.5, `hsla(${themeHue}, 100%, 75%, ${0.08 + v * 0.22})`);
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

    // 1. Dinamik Dönen Plazma Küreleri
    const orbs = skipHeavyFx ? 5 : 8;
    for (let i = 0; i < orbs; i++) {
      const ang = t * (0.5 + i * 0.12) + i * 1.1;
      const dist = 110 + v * 160 + Math.sin(t * 1.6 + i) * 40;
      const ox = cx + Math.cos(ang) * dist;
      const oy = cy + Math.sin(ang) * dist * 0.75;
      const size = 80 + i * 25 + v * 110;
      softBlob(ox, oy, size, themeHue + i * 28, 0.22 + v * 0.38);
    }

    // 2. Kadran Çevresinde Çakan Canlı Elektrik Şimşek Arkları (Electric Arcs)
    const arcSegments = skipHeavyFx ? 10 : 20;
    const ringR = Math.max(160, Math.min(w, h) * 0.22) + v * 70;
    ctx.beginPath();
    for (let i = 0; i <= arcSegments; i++) {
      const ang = (i / arcSegments) * Math.PI * 2;
      const jitter = (Math.random() - 0.5) * (12 + v * 35);
      const r = ringR + jitter;
      const x = cx + Math.cos(ang) * r;
      const y = cy + Math.sin(ang) * r;
      if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
    }
    ctx.closePath();
    ctx.strokeStyle = `hsla(${themeHue + 25}, 100%, 82%, ${0.40 + v * 0.60})`;
    ctx.lineWidth = 2.5 + v * 3.0;
    ctx.stroke();

    // Hızlandıkça merkezden dışarı fırlayan yüksek voltaj şimşekleri
    const bolts = Math.floor(2 + v * 7);
    for (let b = 0; b < bolts; b++) {
      const ang = Math.random() * Math.PI * 2;
      let lx = cx + Math.cos(ang) * 60;
      let ly = cy + Math.sin(ang) * 60;
      ctx.beginPath();
      ctx.moveTo(lx, ly);
      const steps = 5;
      for (let s = 1; s <= steps; s++) {
        const r = 60 + (s / steps) * (ringR + 100 + v * 150);
        const dev = (Math.random() - 0.5) * 35;
        lx = cx + Math.cos(ang + dev * 0.06) * r;
        ly = cy + Math.sin(ang + dev * 0.06) * r;
        ctx.lineTo(lx, ly);
      }
      ctx.strokeStyle = `hsla(${themeHue + 40}, 100%, 90%, ${0.40 + v * 0.60})`;
      ctx.lineWidth = 1.8 + v * 2.0;
      ctx.stroke();
    }
  }

  function drawNightCity() {
    const { cx, cy, motion: v } = softBg();
    const t = animT;
    const horizon = cy + 40;

    // 1. Synthwave Mor & Neon Gece Gökyüzü
    const sky = ctx.createLinearGradient(0, 0, 0, horizon);
    sky.addColorStop(0, "#080318");
    sky.addColorStop(0.55, `hsla(285, 85%, 22%, ${0.45 + v * 0.25})`);
    sky.addColorStop(1, `hsla(325, 100%, 50%, ${0.55 + v * 0.35})`);
    ctx.fillStyle = sky;
    ctx.fillRect(0, 0, w, horizon);

    // 2. Neon Siber Güneş (Segmented Synthwave Sun)
    const sunR = Math.min(w, h) * 0.24;
    const sunGrad = ctx.createLinearGradient(cx, horizon - sunR * 1.4, cx, horizon);
    sunGrad.addColorStop(0, "hsla(50, 100%, 75%, 0.95)");
    sunGrad.addColorStop(0.5, "hsla(330, 100%, 65%, 0.85)");
    sunGrad.addColorStop(1, "hsla(280, 90%, 45%, 0.55)");
    ctx.fillStyle = sunGrad;
    ctx.beginPath();
    ctx.arc(cx, horizon, sunR, Math.PI, 0);
    ctx.fill();

    // 3. 3D Perspektif Izgara Yolu (Scrolling Synthwave Retro Grid across full screen)
    const gridSpeed = (t * (0.6 + v * 3.5)) % 1;
    const gridLines = skipHeavyFx ? 10 : 16;
    for (let i = 0; i < gridLines; i++) {
      const p = (i / gridLines + gridSpeed) % 1;
      const y = horizon + Math.pow(p, 1.6) * (h - horizon);
      const alpha = p * (0.25 + v * 0.65);
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(w, y);
      ctx.strokeStyle = `hsla(315, 100%, 68%, ${alpha})`;
      ctx.lineWidth = 1.5 + p * 3;
      ctx.stroke();
    }

    // Izgaranın ufuktan aşağı inen dikey perspektif çizgileri
    const lanes = 16;
    for (let l = -lanes; l <= lanes; l++) {
      const spreadBottom = cx + l * (w / (lanes * 1.3));
      ctx.beginPath();
      ctx.moveTo(cx + l * 6, horizon);
      ctx.lineTo(spreadBottom, h);
      ctx.strokeStyle = `hsla(195, 95%, 65%, ${0.20 + v * 0.50})`;
      ctx.lineWidth = 1.5;
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

    // 1. Derin sıcak akkor plazma zemin aurası
    const glowR = Math.max(w, h) * (0.42 + v * 0.35);
    const core = ctx.createRadialGradient(cx, cy, 50, cx, cy, glowR);
    core.addColorStop(0, `hsla(20, 100%, 55%, ${0.35 + v * 0.40})`);
    core.addColorStop(0.28, `hsla(10, 95%, 45%, ${0.22 + v * 0.28})`);
    core.addColorStop(0.65, `hsla(350, 90%, 20%, ${0.10 + v * 0.15})`);
    core.addColorStop(1, "transparent");
    ctx.fillStyle = core;
    ctx.fillRect(0, 0, w, h);

    // 2. Canlı Dans Eden Prosedürel Alev Dilleri (Procedural Fire Tongues)
    // Kadran çevresinden dışarıya ve yukarıya doğru yükselen belirgin alevler
    const flameLangs = skipHeavyFx ? 12 : 24;
    const baseR = Math.max(160, Math.min(w, h) * 0.22);
    for (let i = 0; i < flameLangs; i++) {
      const p = i / flameLangs;
      const ang = Math.PI * 0.05 + p * Math.PI * 0.9;
      const wave = Math.sin(t * 3.6 + i * 1.7) * 26 + Math.cos(t * 5.4 + i * 2.5) * 16;
      const height = 90 + v * 220 + Math.sin(t * 4.2 + i) * 35;
      
      const x0 = cx + Math.cos(ang) * baseR;
      const y0 = cy + Math.sin(ang) * baseR * 0.85;
      const xTip = cx + Math.cos(ang) * (baseR + height) + wave * 0.5;
      const yTip = cy + Math.sin(ang) * (baseR + height) - Math.abs(wave) * 1.2 - height * 0.35;
      
      const fg = ctx.createLinearGradient(x0, y0, xTip, yTip);
      fg.addColorStop(0, `hsla(10, 100%, 50%, ${0.45 + v * 0.45})`);
      fg.addColorStop(0.40, `hsla(28, 100%, 55%, ${0.40 + v * 0.50})`);
      fg.addColorStop(0.80, `hsla(52, 100%, 75%, ${0.30 + v * 0.55})`);
      fg.addColorStop(1, "transparent");
      
      ctx.beginPath();
      ctx.moveTo(x0 - 24, y0);
      ctx.quadraticCurveTo(x0 + wave, (y0 + yTip) * 0.5, xTip, yTip);
      ctx.quadraticCurveTo(x0 - wave, (y0 + yTip) * 0.5, x0 + 24, y0);
      ctx.fillStyle = fg;
      ctx.fill();
    }

    // 3. Yukarı Doğru Fırlayan Akkor Kıvılcım Parçacıkları (Rising Ember Sparks)
    const sparkCount = Math.min(particles.length, skipHeavyFx ? 40 : 90);
    const driftY = 0.003 + v * 0.035;
    for (let i = 0; i < sparkCount; i++) {
      const p = particles[i];
      p.y -= driftY * (0.6 + p.size * 0.25);
      p.x += Math.sin(t * 2.5 + p.hueOff) * 0.002 * (1 + v * 3.5);
      if (p.y < -0.05) { p.y = 1.05; p.x = Math.random(); }
      const px = p.x * w;
      const py = p.y * h;
      const sz = 2.0 + p.size * 2.2 * (1 + v * 0.8);
      const alpha = 0.40 + v * 0.60;

      const len = (20 + v * 70) * (0.6 + p.size * 0.2);
      ctx.beginPath();
      ctx.moveTo(px, py);
      ctx.lineTo(px + Math.sin(t * 2 + i) * 6, py + len);
      ctx.strokeStyle = `hsla(30 + p.hueOff * 0.25, 100%, 75%, ${alpha})`;
      ctx.lineWidth = Math.max(1.5, sz * 0.8);
      ctx.stroke();
    }

    // 4. Kadran Çevresinde Afterburner / Türbin Halka Parlaması
    const ringR = baseR + 15 + v * 80 + Math.sin(t * 2.5) * 8;
    ctx.beginPath();
    ctx.arc(cx, cy, ringR, 0, Math.PI * 2);
    ctx.strokeStyle = `hsla(24, 100%, 65%, ${0.25 + v * 0.55})`;
    ctx.lineWidth = 2.5 + v * 3.5;
    ctx.stroke();
    
    // Yüksek hızda 2. alevli şok dalgası halkası
    if (v > 0.25) {
      ctx.beginPath();
      ctx.arc(cx, cy, ringR * 1.25 + Math.sin(t * 4.0) * 10, 0, Math.PI * 2);
      ctx.strokeStyle = `hsla(45, 100%, 80%, ${(v - 0.25) * 0.65})`;
      ctx.lineWidth = 2.0 + v * 2.5;
      ctx.stroke();
    }
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
    const ribbons = skipHeavyFx ? 5 : 9;
    const ribbonSpeed = t * (2.2 + v * 6.0);

    for (let r = 0; r < ribbons; r++) {
      const spreadY = (r - (ribbons - 1) / 2) * (h / (ribbons * 1.05));
      const yBase = cy + spreadY;
      const isRed = (r % 2) === 0;

      ctx.beginPath();
      const steps = skipHeavyFx ? 24 : 40;
      for (let i = 0; i <= steps; i++) {
        const p = i / steps;
        const x = p * w;
        const wave = Math.sin(p * 5.0 - ribbonSpeed + r * 1.1) * (20 + v * 45) +
                     Math.cos(p * 8.5 + t * 2.2) * (8 + v * 16);
        const y = yBase + wave;
        if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
      }

      const g = ctx.createLinearGradient(0, yBase - 40, 0, yBase + 40);
      g.addColorStop(0, "transparent");
      if (isRed) {
        g.addColorStop(0.5, `hsla(355, 100%, 55%, ${0.25 + v * 0.55})`);
      } else {
        g.addColorStop(0.5, `rgba(255, 255, 255, ${0.22 + v * 0.50})`);
      }
      g.addColorStop(1, "transparent");

      ctx.strokeStyle = g;
      ctx.lineWidth = 3.0 + v * 5.0;
      ctx.stroke();
    }

    // Aerodinamik girdap spirali
    const spiralR = Math.max(160, Math.min(w, h) * 0.22) + v * 70;
    ctx.beginPath();
    ctx.arc(cx, cy, spiralR, -Math.PI * 0.85, Math.PI * 0.85);
    ctx.strokeStyle = `hsla(355, 100%, 65%, ${0.20 + v * 0.45})`;
    ctx.lineWidth = 2.5 + v * 3.5;
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

    // 1. Derin lüks siyah-karbon kadife zemin
    ctx.fillStyle = "#080306";
    ctx.fillRect(0, 0, w, h);

    const sky = ctx.createRadialGradient(cx, cy, 50, cx, cy, Math.max(w, h) * 0.65);
    sky.addColorStop(0, `hsla(352, 80%, 28%, ${0.28 + v * 0.25})`);
    sky.addColorStop(0.45, `hsla(345, 65%, 14%, ${0.18 + v * 0.16})`);
    sky.addColorStop(1, "#040103");
    ctx.fillStyle = sky;
    ctx.fillRect(0, 0, w, h);

    // 2. Yumuşak nefes alan konsantrik kızıl su dalgaları (Concentric Crimson Ripples)
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

    // 3. Kadran arkasında yavaşça dalgalanan yumuşak kızıl sis aurası
    softBlob(cx + Math.sin(t * 0.4) * 25, cy + Math.cos(t * 0.35) * 15, Math.min(w, h) * (0.26 + v * 0.18), 352, 0.18 + v * 0.18);
    softBlob(cx - Math.sin(t * 0.3) * 20, cy - Math.cos(t * 0.4) * 12, Math.min(w, h) * (0.22 + v * 0.14), 10, 0.12 + v * 0.14);
  }

  function drawMiniVibrant() {
    const { cx, cy } = softBg();
    const v = renderMotion;
    const t = animT;

    // 1. Derin gece fuşya/mor zemin
    ctx.fillStyle = "#0c040d";
    ctx.fillRect(0, 0, w, h);

    // 2. Yumuşak harmonik sıvı ışık küreleri (Floating Luminescent Spheres)
    const discs = [
      { x: -0.16, y: -0.10, r: 0.44, hue: 335, a: 0.35 },
      { x: 0.18, y: -0.06, r: 0.38, hue: 15, a: 0.32 },
      { x: -0.06, y: 0.18, r: 0.46, hue: 310, a: 0.30 },
      { x: 0.14, y: 0.22, r: 0.35, hue: 350, a: 0.28 },
    ];
    for (let i = 0; i < discs.length; i++) {
      const d = discs[i];
      const px = cx + w * d.x + Math.sin(t * 0.6 + i * 1.5) * 24;
      const py = cy + h * d.y + Math.cos(t * 0.5 + i * 1.2) * 20;
      const rr = Math.min(w, h) * (d.r + v * 0.12);
      const g = ctx.createRadialGradient(px, py, 0, px, py, rr);
      g.addColorStop(0, `hsla(${d.hue}, 90%, 62%, ${d.a + v * 0.22})`);
      g.addColorStop(0.50, `hsla(${d.hue - 15}, 80%, 38%, ${(d.a + v * 0.22) * 0.45})`);
      g.addColorStop(1, "transparent");
      ctx.fillStyle = g;
      ctx.beginPath();
      ctx.arc(px, py, rr, 0, Math.PI * 2);
      ctx.fill();
    }

    // 3. İpeksi akıcı renkli aurora dalgaları (Silky Aurora Waves)
    const waveCount = skipHeavyFx ? 3 : 5;
    for (let i = 0; i < waveCount; i++) {
      const yBase = cy + (i - (waveCount - 1) / 2) * (h * 0.20);
      ctx.beginPath();
      const steps = skipHeavyFx ? 18 : 32;
      for (let s = 0; s <= steps; s++) {
        const p = s / steps;
        const x = p * w;
        const wave = Math.sin(p * 3.8 + t * (0.8 + v * 1.8) + i * 1.2) * (20 + v * 28);
        const y = yBase + wave;
        if (s === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
      }
      ctx.strokeStyle = `hsla(${330 + i * 15}, 95%, 68%, ${0.16 + v * 0.26})`;
      ctx.lineWidth = 3.0 + v * 3.0;
      ctx.stroke();
    }

    // 4. Kadran arkasında yumuşak parlayan fuşya aurası
    miniAmbientRing(cx, cy, 335, { r: 0.38, sat: 90, a: 0.25 });
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
    for (let i = 0; i < 3; i++) {
      const rr = Math.min(w, h) * (0.22 + i * 0.08) + Math.sin(t * 0.4 + i) * 4;
      ctx.beginPath(); ctx.arc(cx, cy, rr, 0, Math.PI * 2);
      ctx.strokeStyle = `rgba(120, 90, 55, ${0.16 - i * 0.03 + v * 0.08})`;
      ctx.lineWidth = 2 - i * 0.3; ctx.stroke();
    }
    softBlob(cx + Math.sin(t * 0.35) * 18, cy - 20 + Math.cos(t * 0.28) * 10, 70 + v * 40, 38, 0.14 + v * 0.1);
    miniAmbientRing(cx, cy, 32, { r: 0.36, sat: 45, a: 0.18, lw: 2 });
    softBlob(cx, cy + 100, 130 + v * 70, 35, 0.18 + v * 0.18);
  }

  function drawMiniGreen() {
    const { cx, cy } = softBg();
    const v = renderMotion;
    const t = animT;

    // 1. Dinlendirici zümrüt yeşili derin gece zemini (Gözü dinlendiren ton)
    ctx.fillStyle = "#020c05";
    ctx.fillRect(0, 0, w, h);

    const aura = ctx.createRadialGradient(cx, cy, 50, cx, cy, Math.max(w, h) * 0.65);
    aura.addColorStop(0, `hsla(135, 85%, 28%, ${0.28 + v * 0.24})`);
    aura.addColorStop(0.42, `hsla(145, 75%, 15%, ${0.16 + v * 0.16})`);
    aura.addColorStop(1, "#010502");
    ctx.fillStyle = aura;
    ctx.fillRect(0, 0, w, h);

    // 2. Yumuşak sakin zen su dalgaları (Soft Concentric Zen Ripples)
    const ripples = skipHeavyFx ? 4 : 7;
    for (let i = 0; i < ripples; i++) {
      const phase = (t * 0.22 + i / ripples) % 1;
      const r = Math.min(w, h) * (0.12 + phase * 0.44);
      const a = (1 - phase) * (0.22 + v * 0.26);
      ctx.beginPath();
      ctx.arc(cx, cy, r, 0, Math.PI * 2);
      ctx.strokeStyle = `hsla(${128 + i * 4}, 90%, 65%, ${a})`;
      ctx.lineWidth = 2.0 - phase * 0.7;
      ctx.stroke();
    }

    // 3. Yavaşça yükselen zümrüt ışık tozları / ateş böcekleri (Bioluminescent Emerald Dust)
    const fireflyCount = skipHeavyFx ? 25 : 55;
    for (let i = 0; i < fireflyCount; i++) {
      const p = particles[i % particles.length];
      p.y -= (0.0015 + v * 0.018) * (0.5 + (i % 3) * 0.2);
      p.x += Math.sin(t * 1.4 + i) * 0.0007;
      if (p.y < -0.05) { p.y = 1.05; p.x = Math.random(); }

      const px = p.x * w;
      const py = p.y * h;
      const sz = 1.8 + (i % 3) * 1.2;
      const pulse = 0.5 + 0.5 * Math.sin(t * 2.2 + i * 1.5);
      const alpha = (0.25 + pulse * 0.45) * (0.6 + v * 0.4);

      ctx.beginPath();
      ctx.arc(px, py, sz, 0, Math.PI * 2);
      ctx.fillStyle = `hsla(132, 95%, 72%, ${alpha})`;
      ctx.fill();
    }

    // 4. Kadran arkasında dinlendirici nane yeşili aurası
    softBlob(cx, cy, Math.min(w, h) * (0.24 + v * 0.16), 130, 0.16 + v * 0.16);
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
  };

  const MODES = [
    { key: "glow", labelKey: "visualGlow", group: "ambient", gauge: "analog" },
    { key: "alev", labelKey: "visualAlev", group: "sport", gauge: "digital" },
    { key: "yildiz", labelKey: "visualYildiz", group: "ambient", gauge: "analog" },
    { key: "bayrak", labelKey: "visualBayrak", group: "sport", gauge: "digital" },
    { key: "plasma", labelKey: "visualPlasma", group: "sport", gauge: "digital" },
    { key: "warp", labelKey: "visualWarp", group: "sport", gauge: "digital" },
    { key: "tunnel", labelKey: "visualTunnel", group: "race", gauge: "analog" },
    { key: "neon", labelKey: "visualNeon", group: "neon", gauge: "digital" },
    { key: "night-city", labelKey: "visualNightCity", group: "neon", gauge: "digital" },
    { key: "deep-ocean", labelKey: "visualDeepOcean", group: "ambient", gauge: "analog" },
    { key: "redline", labelKey: "visualRedline", group: "race", gauge: "analog" },
    { key: "mini-timeless", labelKey: "visualMiniTimeless", group: "mini", gauge: "analog" },
    { key: "mini-vibrant", labelKey: "visualMiniVibrant", group: "mini", gauge: "digital" },
    { key: "mini-personal", labelKey: "visualMiniPersonal", group: "mini", gauge: "digital" },
    { key: "mini-green", labelKey: "visualMiniGreen", group: "mini", gauge: "digital" },
  ];

  function loop() {
    const now = performance.now();
    const dt = lastFrameAt ? Math.min(0.05, (now - lastFrameAt) / 1000) : 0.016;
    lastFrameAt = now;
    frameN++;
    animT += dt * (0.04 + renderMotion * 2.4);
    skipHeavyFx = dt > 0.028;
    try {
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
