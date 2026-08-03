/**
 * WebGL 3D road / speed-sense scene — drop-in replacement for js/scene.js
 *
 * Same public API as the canvas2D Scene module (DEFAULT_MODE, getModes,
 * getThemeHue, init, setMode, setSpeed, destroy), so wiring this in is a
 * one-line swap in index.html:
 *
 *   <script src="js/scene.js?v=..."></script>
 *   → <script src="js/scene-webgl.js?v=..."></script>
 *
 * Renders a real perspective 3D road rushing toward the camera (dashed
 * center line, glowing edge lines, roadside marker posts) plus a
 * screen-space radial speed-streak overlay whose intensity scales with
 * uSpeed — this is what sells "hız hissi" (speed sensation) at the top
 * of the range. All 21 existing theme keys are kept so the picker UI in
 * app.js needs no changes; each theme tints the same 3D scene (road/sky/
 * streak hue + a per-group intensity profile) instead of being a totally
 * separate renderer, so new themes are just new hue/style entries below.
 *
 * No external deps (no three.js) — the project has no bundler, everything
 * ships as a plain <script> tag, so this file is self-contained raw WebGL2
 * with a tiny inline mat4 helper.
 *
 * Falls back to a static gradient fill if WebGL2 isn't available.
 */
const Scene = (() => {
  let canvas, gl, w, h, dpr = 1;
  let mode = "aurora";
  let baseHue = 185;
  let speedNorm = 0;
  let targetNorm = 0;
  let shake = 0;
  let raf = null;
  let tStart = performance.now();
  let lost = false;

  // ---------------------------------------------------------------------
  // Theme table — identical keys/labels to js/scene.js so the visual
  // picker and paywall copy don't need to change.
  // ---------------------------------------------------------------------
  const MODE_HUE = {
    aurora: 185, tesla: 0, midnight: 210, "plaid-boost": 28,
    particles: 200, vortex: 275, horizon: 205, pulse: 345,
    plasma: 295, warp: 255, streak: 18, chrome: 210, tunnel: 165,
    grid: 145, circuit: 132, telemetry: 175, neon: 318, matrix: 118,
    "night-city": 305, "solar-flare": 36, "deep-ocean": 204,
    "electric-ice": 188, redline: 358, "violet-storm": 268, "cyber-lime": 92,
  };

  const MODES = [
    { key: "aurora", labelKey: "visualAurora", group: "ambient" },
    { key: "particles", labelKey: "visualParticles", group: "ambient" },
    { key: "vortex", labelKey: "visualVortex", group: "ambient" },
    { key: "horizon", labelKey: "visualHorizon", group: "ambient" },
    { key: "pulse", labelKey: "visualPulse", group: "sport" },
    { key: "plasma", labelKey: "visualPlasma", group: "sport" },
    { key: "warp", labelKey: "visualWarp", group: "sport" },
    { key: "streak", labelKey: "visualStreak", group: "sport" },
    { key: "chrome", labelKey: "visualChrome", group: "sport" },
    { key: "tunnel", labelKey: "visualTunnel", group: "race" },
    { key: "grid", labelKey: "visualGrid", group: "race" },
    { key: "circuit", labelKey: "visualCircuit", group: "race" },
    { key: "telemetry", labelKey: "visualTelemetry", group: "race" },
    { key: "neon", labelKey: "visualNeon", group: "neon" },
    { key: "matrix", labelKey: "visualMatrix", group: "neon" },
    { key: "night-city", labelKey: "visualNightCity", group: "neon" },
    { key: "deep-ocean", labelKey: "visualDeepOcean", label: "Derin Okyanus", group: "ambient" },
    { key: "electric-ice", labelKey: "visualElectricIce", label: "Elektrik Buzu", group: "ambient" },
    { key: "solar-flare", labelKey: "visualSolarFlare", label: "Güneş Patlaması", group: "sport" },
    { key: "redline", labelKey: "visualRedline", label: "Redline", group: "race" },
    { key: "violet-storm", labelKey: "visualVioletStorm", label: "Mor Fırtına", group: "neon" },
    { key: "cyber-lime", labelKey: "visualCyberLime", label: "Cyber Lime", group: "neon" },
  ];

  // Per-group style profile — cheap way to make each theme *feel*
  // different while sharing one 3D engine: how dense the roadside posts
  // are, how aggressive the speed streaks get, how tight the lane dashes
  // run.
  const GROUP_STYLE = {
    ambient: { postDensity: 0.55, streakBoost: 0.65, dashDensity: 0.45 },
    sport: { postDensity: 0.85, streakBoost: 1.05, dashDensity: 0.6 },
    race: { postDensity: 1.25, streakBoost: 1.35, dashDensity: 0.85 },
    neon: { postDensity: 1.0, streakBoost: 1.2, dashDensity: 0.7 },
  };

  // ---------------------------------------------------------------------
  // mat4 helpers (column-major Float32Array(16), gl-matrix-compatible)
  // ---------------------------------------------------------------------
  function mat4Perspective(fovy, aspect, near, far) {
    const f = 1 / Math.tan(fovy / 2);
    const nf = 1 / (near - far);
    const out = new Float32Array(16);
    out[0] = f / aspect;
    out[5] = f;
    out[10] = (far + near) * nf;
    out[11] = -1;
    out[14] = 2 * far * near * nf;
    return out;
  }

  function mat4LookAt(eye, center, up) {
    let z0 = eye[0] - center[0], z1 = eye[1] - center[1], z2 = eye[2] - center[2];
    let len = Math.hypot(z0, z1, z2) || 1;
    z0 /= len; z1 /= len; z2 /= len;
    let x0 = up[1] * z2 - up[2] * z1, x1 = up[2] * z0 - up[0] * z2, x2 = up[0] * z1 - up[1] * z0;
    len = Math.hypot(x0, x1, x2) || 1;
    x0 /= len; x1 /= len; x2 /= len;
    const y0 = z1 * x2 - z2 * x1, y1 = z2 * x0 - z0 * x2, y2 = z0 * x1 - z1 * x0;
    const out = new Float32Array(16);
    out[0] = x0; out[1] = y0; out[2] = z0; out[3] = 0;
    out[4] = x1; out[5] = y1; out[6] = z1; out[7] = 0;
    out[8] = x2; out[9] = y2; out[10] = z2; out[11] = 0;
    out[12] = -(x0 * eye[0] + x1 * eye[1] + x2 * eye[2]);
    out[13] = -(y0 * eye[0] + y1 * eye[1] + y2 * eye[2]);
    out[14] = -(z0 * eye[0] + z1 * eye[1] + z2 * eye[2]);
    out[15] = 1;
    return out;
  }

  function hslToRgb(h, s, l) {
    h = ((h % 360) + 360) % 360 / 360;
    const c = (1 - Math.abs(2 * l - 1)) * s;
    const x = c * (1 - Math.abs(((h * 6) % 2) - 1));
    const m = l - c / 2;
    let r, g, b;
    if (h < 1 / 6) [r, g, b] = [c, x, 0];
    else if (h < 2 / 6) [r, g, b] = [x, c, 0];
    else if (h < 3 / 6) [r, g, b] = [0, c, x];
    else if (h < 4 / 6) [r, g, b] = [0, x, c];
    else if (h < 5 / 6) [r, g, b] = [x, 0, c];
    else [r, g, b] = [c, 0, x];
    return [r + m, g + m, b + m];
  }

  // ---------------------------------------------------------------------
  // Shaders
  // ---------------------------------------------------------------------
  const HSL_GLSL = `
    vec3 hsl2rgb(float h, float s, float l) {
      h = mod(h, 360.0) / 360.0;
      float c = (1.0 - abs(2.0 * l - 1.0)) * s;
      float x = c * (1.0 - abs(mod(h * 6.0, 2.0) - 1.0));
      float m = l - c / 2.0;
      vec3 rgb;
      if (h < 1.0/6.0) rgb = vec3(c, x, 0.0);
      else if (h < 2.0/6.0) rgb = vec3(x, c, 0.0);
      else if (h < 3.0/6.0) rgb = vec3(0.0, c, x);
      else if (h < 4.0/6.0) rgb = vec3(0.0, x, c);
      else if (h < 5.0/6.0) rgb = vec3(x, 0.0, c);
      else rgb = vec3(c, 0.0, x);
      return rgb + m;
    }
  `;

  // Full-screen triangle, no vertex buffer needed (uses gl_VertexID).
  const FULLSCREEN_VERT = `#version 300 es
    out vec2 vUv;
    void main() {
      vec2 pos = vec2(
        (gl_VertexID == 2) ? 3.0 : -1.0,
        (gl_VertexID == 1) ? 3.0 : -1.0
      );
      vUv = pos * 0.5 + 0.5;
      gl_Position = vec4(pos, 0.0, 1.0);
    }
  `;

  const SKY_FRAG = `#version 300 es
    precision highp float;
    ${HSL_GLSL}
    uniform float uHue, uSpeed;
    uniform vec2 uCenter, uResolution;
    in vec2 vUv;
    out vec4 outColor;
    void main() {
      vec2 d = vUv - uCenter;
      d.x *= uResolution.x / uResolution.y;
      float dist = length(d);
      vec3 innerCol = hsl2rgb(uHue, 0.85, 0.08 + uSpeed * 0.10);
      vec3 midCol = hsl2rgb(uHue + 50.0, 0.70, 0.05);
      vec3 outCol = vec3(0.004, 0.008, 0.03);
      float t1 = smoothstep(0.0, 0.5, dist);
      float t2 = smoothstep(0.5, 1.05, dist);
      vec3 col = mix(innerCol, midCol, t1);
      col = mix(col, outCol, t2);
      float horizonY = uCenter.y + 0.02 - uSpeed * 0.03;
      float band = 1.0 - smoothstep(0.0, 0.10, abs(vUv.y - horizonY));
      vec3 glow = hsl2rgb(uHue, 1.0, 0.6);
      col += glow * band * (0.15 + uSpeed * 0.30);
      outColor = vec4(col, 1.0);
    }
  `;

  const ROAD_VERT = `#version 300 es
    layout(location = 0) in vec3 aPosition;
    uniform mat4 uProjection, uView;
    uniform vec2 uCenterOffset;
    out vec3 vWorldPos;
    void main() {
      vec4 clip = uProjection * uView * vec4(aPosition, 1.0);
      clip.xy += uCenterOffset * clip.w;
      vWorldPos = aPosition;
      gl_Position = clip;
    }
  `;

  const ROAD_FRAG = `#version 300 es
    precision highp float;
    ${HSL_GLSL}
    uniform float uHue, uSpeed, uTime, uHalfWidth, uFar, uDashDensity;
    uniform vec3 uFogColor;
    in vec3 vWorldPos;
    out vec4 outColor;
    void main() {
      float ax = abs(vWorldPos.x);
      float edgeDist = uHalfWidth - ax;
      if (edgeDist < 0.0) discard;
      vec3 asphalt = mix(vec3(0.045, 0.05, 0.065), vec3(0.07, 0.08, 0.10), 1.0 - ax / uHalfWidth);
      float dashPhase = fract(vWorldPos.z * (0.35 + uDashDensity * 0.5) - uTime * (0.6 + uSpeed * 4.4));
      float centerLine = step(abs(vWorldPos.x), 0.07) * step(0.5, dashPhase);
      float edgeLine = smoothstep(0.12, 0.0, abs(ax - uHalfWidth + 0.06));
      vec3 lineColor = hsl2rgb(uHue, 0.95, 0.6 + uSpeed * 0.15);
      vec3 col = asphalt;
      col = mix(col, lineColor, centerLine * 0.9);
      col = mix(col, lineColor, edgeLine * 0.75);
      float depth = clamp(-vWorldPos.z / uFar, 0.0, 1.0);
      col = mix(col, uFogColor, pow(depth, 1.35));
      float alpha = smoothstep(0.0, 0.3, edgeDist);
      outColor = vec4(col, alpha);
    }
  `;

  const POST_VERT = `#version 300 es
    layout(location = 0) in vec2 aLocal;
    layout(location = 1) in float aSide;
    layout(location = 2) in float aSlot;
    uniform mat4 uProjection, uView;
    uniform float uTime, uSpeed, uFar, uHalfWidth, uSpacing;
    uniform vec2 uCenterOffset;
    out float vGlow;
    out float vDepth;
    void main() {
      float t = mod(aSlot * uSpacing - uTime * (2.0 + uSpeed * 15.0), uFar);
      float z = -t;
      float hash = fract(sin(aSlot * 12.9898 + 4.1414) * 43758.5453);
      float height = 1.0 + hash * 0.8;
      float wx = aSide * (uHalfWidth + 0.5) + aLocal.x * 0.16;
      float wy = aLocal.y * height;
      vec4 clip = uProjection * uView * vec4(wx, wy, z, 1.0);
      clip.xy += uCenterOffset * clip.w;
      gl_Position = clip;
      vDepth = clamp(t / uFar, 0.0, 1.0);
      vGlow = 0.6 + hash * 0.4;
    }
  `;

  const POST_FRAG = `#version 300 es
    precision highp float;
    ${HSL_GLSL}
    uniform float uHue;
    uniform vec3 uFogColor;
    in float vGlow;
    in float vDepth;
    out vec4 outColor;
    void main() {
      vec3 col = hsl2rgb(uHue + 20.0, 0.9, 0.6) * vGlow;
      col = mix(col, uFogColor, pow(vDepth, 1.6));
      float alpha = (1.0 - pow(vDepth, 2.0)) * 0.9;
      outColor = vec4(col, alpha);
    }
  `;

  const STREAK_FRAG = `#version 300 es
    precision highp float;
    ${HSL_GLSL}
    uniform float uSpeed, uTime, uHue, uStreakBoost;
    uniform vec2 uCenter, uResolution;
    in vec2 vUv;
    out vec4 outColor;
    void main() {
      vec2 d = vUv - uCenter;
      d.x *= uResolution.x / uResolution.y;
      float dist = length(d);
      float ang = atan(d.y, d.x);
      float spokes = 28.0;
      float jitter = fract(sin(floor(ang / 6.2831853 * spokes) * 91.345) * 43758.5453);
      float pattern = fract(ang / 6.2831853 * spokes + uTime * (0.1 + jitter * 0.1));
      float width = mix(0.34, 0.44, jitter);
      float spoke = smoothstep(0.5 - width, 0.5, pattern) - smoothstep(0.5, 0.5 + width, pattern);
      float speedAmt = uSpeed * uSpeed * uStreakBoost;
      float falloff = smoothstep(0.02, 0.75, dist) * (1.0 - smoothstep(0.75, 1.3, dist));
      float intensity = spoke * falloff * speedAmt * 2.2;
      vec3 col = hsl2rgb(uHue + dist * 40.0, 0.85, 0.68);
      outColor = vec4(col * intensity, intensity * 0.9);
    }
  `;

  // ---------------------------------------------------------------------
  // GL plumbing
  // ---------------------------------------------------------------------
  function compileShader(type, src) {
    const sh = gl.createShader(type);
    gl.shaderSource(sh, src);
    gl.compileShader(sh);
    if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) {
      console.error("[scene-webgl] shader compile error:", gl.getShaderInfoLog(sh));
      gl.deleteShader(sh);
      return null;
    }
    return sh;
  }

  function linkProgram(vsSrc, fsSrc) {
    const vs = compileShader(gl.VERTEX_SHADER, vsSrc);
    const fs = compileShader(gl.FRAGMENT_SHADER, fsSrc);
    if (!vs || !fs) return null;
    const prog = gl.createProgram();
    gl.attachShader(prog, vs);
    gl.attachShader(prog, fs);
    gl.linkProgram(prog);
    if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) {
      console.error("[scene-webgl] program link error:", gl.getProgramInfoLog(prog));
      return null;
    }
    return prog;
  }

  function uniforms(prog, names) {
    const u = {};
    for (const n of names) u[n] = gl.getUniformLocation(prog, n);
    return u;
  }

  // World scale constants
  const ROAD_HALF_WIDTH = 3.4;
  const FAR = 55;
  const POST_BASE = 36; // nominal count at style.postDensity === 1
  const POST_CAPACITY = 64; // instance buffer size — must cover max postDensity * POST_BASE
  const POST_SPACING = FAR / (POST_CAPACITY / 2);
  const CAM_HEIGHT = 1.35;

  let prog = {}; // { sky, road, post, streak }
  let uni = {};
  let vao = {}; // per-program vertex array objects
  let emptyVAO;

  function setupGL() {
    gl.getExtension("EXT_color_buffer_float");

    prog.sky = linkProgram(FULLSCREEN_VERT, SKY_FRAG);
    prog.road = linkProgram(ROAD_VERT, ROAD_FRAG);
    prog.post = linkProgram(POST_VERT, POST_FRAG);
    prog.streak = linkProgram(FULLSCREEN_VERT, STREAK_FRAG);

    uni.sky = uniforms(prog.sky, ["uHue", "uSpeed", "uCenter", "uResolution"]);
    uni.road = uniforms(prog.road, [
      "uProjection", "uView", "uCenterOffset", "uHue", "uSpeed", "uTime",
      "uHalfWidth", "uFar", "uDashDensity", "uFogColor",
    ]);
    uni.post = uniforms(prog.post, [
      "uProjection", "uView", "uCenterOffset", "uTime", "uSpeed", "uFar",
      "uHalfWidth", "uSpacing", "uHue", "uFogColor",
    ]);
    uni.streak = uniforms(prog.streak, [
      "uSpeed", "uTime", "uHue", "uStreakBoost", "uCenter", "uResolution",
    ]);

    emptyVAO = gl.createVertexArray();

    // Road plane geometry
    const roadVerts = new Float32Array([
      -ROAD_HALF_WIDTH, 0, 0, ROAD_HALF_WIDTH, 0, 0, ROAD_HALF_WIDTH, 0, -FAR,
      -ROAD_HALF_WIDTH, 0, 0, ROAD_HALF_WIDTH, 0, -FAR, -ROAD_HALF_WIDTH, 0, -FAR,
    ]);
    vao.road = gl.createVertexArray();
    gl.bindVertexArray(vao.road);
    const roadBuf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, roadBuf);
    gl.bufferData(gl.ARRAY_BUFFER, roadVerts, gl.STATIC_DRAW);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 0, 0);

    // Roadside post template quad + instance data
    const postLocal = new Float32Array([
      -0.5, 0, 0.5, 0, 0.5, 1, -0.5, 0, 0.5, 1, -0.5, 1,
    ]);
    const sides = new Float32Array(POST_CAPACITY);
    const slots = new Float32Array(POST_CAPACITY);
    for (let i = 0; i < POST_CAPACITY; i++) {
      sides[i] = i % 2 === 0 ? -1 : 1;
      slots[i] = Math.floor(i / 2);
    }
    vao.post = gl.createVertexArray();
    gl.bindVertexArray(vao.post);
    const localBuf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, localBuf);
    gl.bufferData(gl.ARRAY_BUFFER, postLocal, gl.STATIC_DRAW);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);

    const sideBuf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, sideBuf);
    gl.bufferData(gl.ARRAY_BUFFER, sides, gl.STATIC_DRAW);
    gl.enableVertexAttribArray(1);
    gl.vertexAttribPointer(1, 1, gl.FLOAT, false, 0, 0);
    gl.vertexAttribDivisor(1, 1);

    const slotBuf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, slotBuf);
    gl.bufferData(gl.ARRAY_BUFFER, slots, gl.STATIC_DRAW);
    gl.enableVertexAttribArray(2);
    gl.vertexAttribPointer(2, 1, gl.FLOAT, false, 0, 0);
    gl.vertexAttribDivisor(2, 1);

    gl.bindVertexArray(null);
  }

  // ---------------------------------------------------------------------
  // View / resize
  // ---------------------------------------------------------------------
  function resize() {
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    w = window.innerWidth;
    h = window.innerHeight;
    canvas.width = Math.floor(w * dpr);
    canvas.height = Math.floor(h * dpr);
    canvas.style.width = w + "px";
    canvas.style.height = h + "px";
    if (gl) gl.viewport(0, 0, canvas.width, canvas.height);
  }

  /** Mirrors js/scene.js viewCenter() — HUD-aware focal point, as a 0..1 uv. */
  function viewCenterUv() {
    const root = getComputedStyle(document.documentElement);
    let panelPx = parseFloat(root.getPropertyValue("--panel-offset"));
    if (!Number.isFinite(panelPx) || panelPx < 0) panelPx = 0;
    if (panelPx > w * 0.45) panelPx = 0;
    const adTop = parseFloat(root.getPropertyValue("--ad-top-h")) || 0;
    const adBottom = parseFloat(root.getPropertyValue("--ad-bottom-h")) || 0;
    const safeTop = parseFloat(root.getPropertyValue("--safe-top")) || 0;
    const safeBottom = parseFloat(root.getPropertyValue("--safe-bottom")) || 0;
    const topPad = adTop + safeTop + 60;
    const bottomPad = adBottom + safeBottom + 20;
    const cx = w / 2 + panelPx / 2;
    const cy = topPad + (h - topPad - bottomPad) / 2;
    return { x: cx / w, y: cy / h };
  }

  // ---------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------
  function init(canvasEl) {
    canvas = canvasEl;
    gl = canvas.getContext("webgl2", {
      antialias: true,
      alpha: false,
      powerPreference: "high-performance",
    });

    if (!gl) {
      console.warn("[scene-webgl] WebGL2 unavailable — falling back to static gradient.");
      fallbackInit(canvasEl);
      return;
    }

    canvas.addEventListener("webglcontextlost", (e) => {
      e.preventDefault();
      lost = true;
      if (raf) cancelAnimationFrame(raf);
    });
    canvas.addEventListener("webglcontextrestored", () => {
      lost = false;
      setupGL();
      loop();
    });

    resize();
    window.addEventListener("resize", resize);
    setupGL();
    gl.clearColor(0.01, 0.02, 0.05, 1);
    loop();
  }

  function fallbackInit(canvasEl) {
    // Canvas can only have one context type — if WebGL was already bound,
    // getContext("2d") returns null. Stay crash-free and paint via CSS.
    const ctx = canvasEl.getContext("2d");
    const paintCss = () => {
      const [r, gg, b] = hslToRgb(baseHue, 0.6, 0.08);
      canvasEl.style.background =
        `radial-gradient(ellipse at center, rgb(${Math.round(r * 255)}, ${Math.round(gg * 255)}, ${Math.round(b * 255)}) 0%, #010208 80%)`;
    };
    if (!ctx) {
      console.warn("[scene-webgl] 2D context unavailable — using CSS gradient fallback.");
      paintCss();
      return;
    }
    const draw = () => {
      const ww = window.innerWidth, hh = window.innerHeight;
      canvasEl.width = ww;
      canvasEl.height = hh;
      const g = ctx.createRadialGradient(ww / 2, hh / 2, 0, ww / 2, hh / 2, Math.max(ww, hh) * 0.8);
      const [r, gg, b] = hslToRgb(baseHue, 0.6, 0.08);
      g.addColorStop(0, `rgb(${r * 255}, ${gg * 255}, ${b * 255})`);
      g.addColorStop(1, "#010208");
      ctx.fillStyle = g;
      ctx.fillRect(0, 0, ww, hh);
    };
    draw();
    window.addEventListener("resize", draw);
  }

  function setMode(m) {
    mode = m;
    baseHue = MODE_HUE[m] ?? 185;
  }

  function setSpeed(kmh, maxKmh) {
    const raw = Math.min(1, Math.max(0, kmh / maxKmh));
    targetNorm = raw < 0.015 ? 0 : raw;
    shake = Math.max(shake, targetNorm > 0.88 ? (targetNorm - 0.88) * 1.0 : 0);
  }

  function getThemeHue() {
    return baseHue;
  }

  function currentGroupStyle() {
    const entry = MODES.find((m) => m.key === mode);
    return GROUP_STYLE[entry && entry.group] || GROUP_STYLE.ambient;
  }

  function frame() {
    if (lost || !gl) return;

    const follow = targetNorm < speedNorm ? 0.14 : 0.065;
    speedNorm += (targetNorm - speedNorm) * follow;
    if (targetNorm < 0.01 && speedNorm < 0.025) speedNorm = 0;
    shake *= 0.92;

    const time = (performance.now() - tStart) / 1000;
    const style = currentGroupStyle();
    const center = viewCenterUv();
    // Modest NDC nudge so the road vanishing point follows the HUD focal
    // point (panel/ad insets), without a full asymmetric-frustum rebuild.
    const centerOffset = [
      (center.x - 0.5) * 0.9,
      -(center.y - 0.5) * 0.9,
    ];

    const shakeAmt = speedNorm < 0.04 ? 0 : shake * 0.35;
    const shakeX = (Math.random() - 0.5) * shakeAmt;
    const shakeY = (Math.random() - 0.5) * shakeAmt * 0.4;

    const projection = mat4Perspective((60 * Math.PI) / 180, w / h, 0.1, FAR + 15);
    const view = mat4LookAt(
      [shakeX, CAM_HEIGHT + shakeY, 2.4],
      [shakeX * 0.5, 0.85, -40],
      [0, 1, 0]
    );

    const fog = hslToRgb(baseHue + 50, 0.55, 0.05);

    gl.disable(gl.DEPTH_TEST);
    gl.disable(gl.BLEND);

    // Sky
    gl.useProgram(prog.sky);
    gl.bindVertexArray(emptyVAO);
    gl.uniform1f(uni.sky.uHue, baseHue);
    gl.uniform1f(uni.sky.uSpeed, speedNorm);
    gl.uniform2f(uni.sky.uCenter, center.x, center.y);
    gl.uniform2f(uni.sky.uResolution, w, h);
    gl.drawArrays(gl.TRIANGLES, 0, 3);

    // Road + posts (real depth, alpha-blended edges)
    gl.clear(gl.DEPTH_BUFFER_BIT);
    gl.enable(gl.DEPTH_TEST);
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

    gl.useProgram(prog.road);
    gl.bindVertexArray(vao.road);
    gl.uniformMatrix4fv(uni.road.uProjection, false, projection);
    gl.uniformMatrix4fv(uni.road.uView, false, view);
    gl.uniform2f(uni.road.uCenterOffset, centerOffset[0], centerOffset[1]);
    gl.uniform1f(uni.road.uHue, baseHue);
    gl.uniform1f(uni.road.uSpeed, speedNorm);
    gl.uniform1f(uni.road.uTime, time);
    gl.uniform1f(uni.road.uHalfWidth, ROAD_HALF_WIDTH);
    gl.uniform1f(uni.road.uFar, FAR);
    gl.uniform1f(uni.road.uDashDensity, style.dashDensity);
    gl.uniform3f(uni.road.uFogColor, fog[0], fog[1], fog[2]);
    gl.drawArrays(gl.TRIANGLES, 0, 6);

    const postCount = Math.min(POST_CAPACITY, Math.max(8, Math.round(POST_BASE * style.postDensity)));
    gl.useProgram(prog.post);
    gl.bindVertexArray(vao.post);
    gl.uniformMatrix4fv(uni.post.uProjection, false, projection);
    gl.uniformMatrix4fv(uni.post.uView, false, view);
    gl.uniform2f(uni.post.uCenterOffset, centerOffset[0], centerOffset[1]);
    gl.uniform1f(uni.post.uTime, time);
    gl.uniform1f(uni.post.uSpeed, speedNorm);
    gl.uniform1f(uni.post.uFar, FAR);
    gl.uniform1f(uni.post.uHalfWidth, ROAD_HALF_WIDTH);
    gl.uniform1f(uni.post.uSpacing, POST_SPACING);
    gl.uniform1f(uni.post.uHue, baseHue);
    gl.uniform3f(uni.post.uFogColor, fog[0], fog[1], fog[2]);
    gl.drawArraysInstanced(gl.TRIANGLES, 0, 6, postCount);

    // Screen-space speed streaks — additive, on top, no depth
    gl.disable(gl.DEPTH_TEST);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE);
    gl.useProgram(prog.streak);
    gl.bindVertexArray(emptyVAO);
    gl.uniform1f(uni.streak.uSpeed, speedNorm);
    gl.uniform1f(uni.streak.uTime, time);
    gl.uniform1f(uni.streak.uHue, baseHue);
    gl.uniform1f(uni.streak.uStreakBoost, style.streakBoost);
    gl.uniform2f(uni.streak.uCenter, center.x, center.y);
    gl.uniform2f(uni.streak.uResolution, w, h);
    gl.drawArrays(gl.TRIANGLES, 0, 3);

    gl.bindVertexArray(null);
  }

  function loop() {
    frame();
    raf = requestAnimationFrame(loop);
  }

  function destroy() {
    if (raf) cancelAnimationFrame(raf);
    window.removeEventListener("resize", resize);
  }

  return {
    DEFAULT_MODE: "aurora",
    getModes: () => MODES,
    getThemeHue,
    init,
    setMode,
    setSpeed,
    destroy,
  };
})();
