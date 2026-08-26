/**
 * ETUBU AudioEngine — GPS live synthesis (Drive.app-style)
 *
 * Speed (GPS km/h)  → Pitch / RPM / playbackRate
 * Accel / Load (dv/dt, optional powerKw) → Volume / intensity
 * Cruise (constant speed) → quiet background hum; throttle lifts volume
 * ICE packs: virtual gearbox drops pitch on shift; EV packs: single-ratio ramp
 */
class EtubuAudioEngine {
  constructor() {
    this.DEFAULT_VOICE = "tesla";
    this.VOICE_GROUP_ORDER = ["ev", "exhaust", "race", "fx"];
    /** ClusterTheme.rawValue / webKey → base pack */
    this.THEME_PACK_MAP = {
      tesla: "tesla",
      "calm-ev": "tesla",
      "sport-ev": "sport-ev",
      "ion-whisper": "ion-whisper",
      "boost-launch": "sport-ev",
      "exhaust-v8": "exhaust-v8",
      "exhaust-turbo": "exhaust-turbo",
      "asphalt-roar": "exhaust-v8",
      "cruiser-vtwin": "cruiser-vtwin",
      "exhaust-diesel": "exhaust-diesel",
      "formula-scream": "formula-scream",
      "sportbike-rr": "sportbike-rr",
      "jet-hum": "jet-hum",
      "pulse-drive": "sport-ev",
      "grain-stage": "jet-hum",
      "silent-mode": "silent-mode",
      aurora: "tesla",
      plasma: "sport-ev",
      redline: "exhaust-v8",
      neon: "sport-ev",
      warp: "jet-hum",
      tunnel: "formula-scream",
      cyberLime: "ion-whisper",
      electricIce: "tesla",
      solarFlare: "sport-ev",
      violetStorm: "sport-ev",
      deepOcean: "tesla",
      midnight: "exhaust-diesel",
      plaidBoost: "tesla",
    };
    this.BASE_PACKS = [
      "tesla",
      "sport-ev",
      "ion-whisper",
      "exhaust-v8",
      "formula-scream",
      "sportbike-rr",
      "exhaust-turbo",
      "cruiser-vtwin",
      "exhaust-diesel",
      "jet-hum",
    ];
    this.VOICES = [
      // Elektrikli Araçlar (EV)
      { key: "tesla", label: "⚡ Tesla Model S Plaid", theme: "glow", group: "ev" },
      { key: "sport-ev", label: "🔋 Porsche Taycan Sport", theme: "plasma", group: "ev" },
      { key: "ion-whisper", label: "✨ İyon Fısıltısı (Yumuşak EV)", theme: "glow", group: "ev" },

      // Kaslı & Klasik Egzoz (Muscle & Exhaust)
      { key: "exhaust-v8", label: "🔥 American V8 Muscle", theme: "redline", group: "exhaust" },
      { key: "exhaust-turbo", label: "💨 Twin-Turbo Boxer", theme: "redline", group: "exhaust" },
      { key: "cruiser-vtwin", label: "🦅 V-Twin Chopper", theme: "redline", group: "exhaust" },
      { key: "exhaust-diesel", label: "🚛 Heavy Torque Diesel", theme: "midnight", group: "exhaust" },

      // Yarış & Yüksek Devir (Race & Motorsport)
      { key: "formula-scream", label: "🏁 Formula 1 V10", theme: "plasma", group: "race" },
      { key: "sportbike-rr", label: "🏍️ Superbike 1200 RR", theme: "plasma", group: "race" },

      // Fütüristik & Warp (Sci-Fi)
      { key: "jet-hum", label: "🛸 Sci-Fi Warp Drive", theme: "warp", group: "fx" },

      // Sessiz Mod
      { key: "silent-mode", label: "🔇 Sessiz Mod (Yalnızca Gösterge)", theme: "glow", group: "ev" },
    ];

    /**
     * Karakter profili — WAV baskın (gerçekçi loop), prosedürel destek.
     */
    this.PROFILES = {
      tesla: {
        idleHz: 40, midHz: 85, midSpan: 140, idleGain: 0.04, midGain: 0.22,
        windGain: 0, filterHz: 900, filterQ: 0.55, master: 1.35,
        drive: "ev_modely_body_loop.wav", driveGain: 0.76,
        drive2: "ev_hum_soft_loop.wav", drive2Gain: 0.28,
        regen: "ev_modely_rev_body_loop.wav", regenGain: 0.65,
        loops: {
          idle: "bands/ev_idle_v2.wav",
          mid: "bands/ev_mid_v2.wav",
          high: "bands/ev_high_v2.wav",
        },
        bandEdges: { midStart: 12, highStart: 70 },
        gears: 1, waveIdle: "sine", waveMid: "sine", bodyMul: 0.3,
        harmMul: 0.04, subMul: 0.12, sampleLed: true,
      },
      /* EV — body-EQ’lu Chalmers + yumuşak hum (ıslık bandı kesik) */
      "calm-ev": {
        idleHz: 40, midHz: 85, midSpan: 140, idleGain: 0.04, midGain: 0.22,
        windGain: 0, filterHz: 900, filterQ: 0.55, master: 1.3,
        drive: "ev_id3_body_loop.wav", driveGain: 0.72,
        drive2: "ev_hum_soft_loop.wav", drive2Gain: 0.28,
        regen: "ev_modely_rev_body_loop.wav", regenGain: 0.62,
        loops: {
          idle: "bands/ev_idle_v2.wav",
          mid: "bands/ev_mid_v2.wav",
          high: "bands/ev_high_v2.wav",
        },
        bandEdges: { midStart: 12, highStart: 68 },
        gears: 1, waveIdle: "sine", waveMid: "sine", bodyMul: 0.32,
        harmMul: 0.04, subMul: 0.14, sampleLed: true,
      },
      "sport-ev": {
        idleHz: 52, midHz: 110, midSpan: 200, idleGain: 0.032, midGain: 0.24,
        windGain: 0, filterHz: 1200, filterQ: 0.65, master: 1.38,
        drive: "ev_modely_body_loop.wav", driveGain: 0.74,
        drive2: "ev_hum_sport_loop.wav", drive2Gain: 0.3,
        regen: "ev_modely_rev_body_loop.wav", regenGain: 0.68,
        loops: {
          idle: "bands/ev_idle_v2.wav",
          mid: "bands/ev_mid_v2.wav",
          high: "bands/ev_high_v2.wav",
        },
        bandEdges: { midStart: 14, highStart: 75 },
        gears: 1, waveIdle: "sine", waveMid: "sine", bodyMul: 0.24,
        harmMul: 0.05, subMul: 0.1, sampleLed: true,
      },
      "ion-whisper": {
        idleHz: 60, midHz: 130, midSpan: 240, idleGain: 0.028, midGain: 0.2,
        windGain: 0, filterHz: 1400, filterQ: 0.7, master: 1.32,
        drive: "ev_hum_sport_loop.wav", driveGain: 0.7,
        drive2: "ev_modely_body_loop.wav", drive2Gain: 0.22,
        regen: "ev_modely_rev_body_loop.wav", regenGain: 0.58,
        loops: {
          idle: "bands/ev_idle_alt.wav",
          mid: "bands/ev_mid_v2.wav",
          high: "bands/ev_high_v2.wav",
        },
        bandEdges: { midStart: 10, highStart: 70 },
        gears: 1, waveIdle: "sine", waveMid: "sine", bodyMul: 0.16,
        harmMul: 0.05, subMul: 0.08, sampleLed: true,
      },
      "volt-shift": {
        idleHz: 48, midHz: 105, midSpan: 190, idleGain: 0.035, midGain: 0.24,
        windGain: 0, filterHz: 1150, filterQ: 0.65, master: 1.36,
        drive: "ev_modely_body_loop.wav", driveGain: 0.7,
        drive2: "ev_hum_soft_loop.wav", drive2Gain: 0.26,
        regen: "ev_modely_rev_body_loop.wav", regenGain: 0.64,
        loops: {
          idle: "bands/ev_idle_v2.wav",
          mid: "bands/ev_mid_v2.wav",
          high: "bands/ev_high_v2.wav",
        },
        bandEdges: { midStart: 12, highStart: 72 },
        gears: 1, waveIdle: "sine", waveMid: "sine", bodyMul: 0.22,
        harmMul: 0.05, subMul: 0.1, sampleLed: true,
      },
      "boost-launch": {
        idleHz: 58, midHz: 125, midSpan: 260, idleGain: 0.03, midGain: 0.26,
        windGain: 0, filterHz: 1500, filterQ: 0.7, master: 1.44,
        drive: "ev_modely_rev_body_loop.wav", driveGain: 0.78,
        drive2: "ev_hum_sport_loop.wav", drive2Gain: 0.24,
        regen: "ev_modely_rev_body_loop.wav", regenGain: 0.72,
        loops: {
          idle: "bands/ev_idle_v2.wav",
          mid: "bands/ev_mid_v2.wav",
          high: "bands/ev_high_v2.wav",
        },
        bandEdges: { midStart: 16, highStart: 80 },
        gears: 1, waveIdle: "sine", waveMid: "triangle", bodyMul: 0.18,
        harmMul: 0.06, subMul: 0.09, sampleLed: true,
      },

      /* ICE */
      "exhaust-v8": {
        idleHz: 40, midHz: 88, midSpan: 200, idleGain: 0.05, midGain: 0.28,
        windGain: 0, filterHz: 900, filterQ: 0.7, master: 1.52,
        drive: "v8_exhaust_loop.wav", driveGain: 0.82,
        drive2: "v8_exhaust_loop.wav", drive2Gain: 0.22,
        loops: {
          idle: "bands/ice_idle_v8_v2.wav",
          mid: "bands/ice_mid_v2.wav",
          high: "bands/ice_high_v2.wav",
        },
        bandEdges: { midStart: 14, highStart: 95 },
        gears: 6, ice: true, waveIdle: "triangle", waveMid: "sawtooth", bodyMul: 0.28,
        harmMul: 0.12, subMul: 0.2, sampleLed: true,
      },
      "exhaust-turbo": {
        idleHz: 48, midHz: 115, midSpan: 260, idleGain: 0.04, midGain: 0.26,
        windGain: 0, filterHz: 1200, filterQ: 0.75, master: 1.46,
        drive: "combustion_rich_loop.wav", driveGain: 0.84,
        drive2: "ref_sim_load_throttle.wav", drive2Gain: 0.22,
        loops: {
          idle: "bands/turbo_idle_v2.wav",
          mid: "bands/turbo_mid_v2.wav",
          high: "bands/turbo_high_v2.wav",
        },
        bandEdges: { midStart: 16, highStart: 100 },
        gears: 6, ice: true, waveIdle: "triangle", waveMid: "sawtooth", bodyMul: 0.22,
        harmMul: 0.1, subMul: 0.12, sampleLed: true,
      },
      "exhaust-diesel": {
        idleHz: 28, midHz: 60, midSpan: 120, idleGain: 0.07, midGain: 0.24,
        windGain: 0, filterHz: 650, filterQ: 0.5, master: 1.44,
        drive: "diesel_thump_loop.wav", driveGain: 0.84,
        drive2: "diesel_thump_loop.wav", drive2Gain: 0.12,
        loops: {
          idle: "bands/diesel_idle_v2.wav",
          mid: "bands/diesel_mid_v2.wav",
          high: "bands/diesel_high_v2.wav",
        },
        bandEdges: { midStart: 12, highStart: 85 },
        gears: 6, ice: true, waveIdle: "triangle", waveMid: "triangle", bodyMul: 0.36,
        harmMul: 0.08, subMul: 0.26, sampleLed: true,
      },
      "asphalt-roar": {
        idleHz: 36, midHz: 82, midSpan: 190, idleGain: 0.05, midGain: 0.28,
        windGain: 0, filterHz: 850, filterQ: 0.65, master: 1.5,
        drive: "v8_exhaust_loop.wav", driveGain: 0.78,
        drive2: "v8_exhaust_loop.wav", drive2Gain: 0.22,
        loops: {
          idle: "bands/ice_idle_v2.wav",
          mid: "bands/ice_mid_v2.wav",
          high: "bands/ice_high_v2.wav",
        },
        bandEdges: { midStart: 14, highStart: 88 },
        gears: 5, ice: true, waveIdle: "triangle", waveMid: "sawtooth", bodyMul: 0.26,
        harmMul: 0.12, subMul: 0.16, sampleLed: true,
      },
      "thunder-bass": {
        idleHz: 22, midHz: 44, midSpan: 100, idleGain: 0.075, midGain: 0.22,
        windGain: 0, filterHz: 480, filterQ: 0.4, master: 1.54,
        drive: "diesel_thump_loop.wav", driveGain: 0.7,
        drive2: "v8_exhaust_loop.wav", drive2Gain: 0.28,
        loops: {
          idle: "bands/diesel_idle_v2.wav",
          mid: "bands/ice_mid_v2.wav",
          high: "bands/ice_high_v2.wav",
        },
        bandEdges: { midStart: 10, highStart: 80 },
        gears: 4, ice: true, waveIdle: "sine", waveMid: "triangle", bodyMul: 0.42,
        harmMul: 0.08, subMul: 0.32, sampleLed: true,
      },
      "cruiser-vtwin": {
        idleHz: 24, midHz: 50, midSpan: 85, idleGain: 0.06, midGain: 0.26,
        windGain: 0, filterHz: 520, filterQ: 0.45, master: 1.62,
        drive: "vtwin_cruiser_loop.wav", driveGain: 0.88,
        drive2: "vtwin_cruiser_loop.wav", drive2Gain: 0.14,
        loops: {
          idle: "bands/ice_idle_v2.wav",
          mid: "bands/ice_mid_v2.wav",
          high: "bands/ice_high_v2.wav",
        },
        bandEdges: { midStart: 12, highStart: 70 },
        gears: 5, ice: true, waveIdle: "triangle", waveMid: "sawtooth", bodyMul: 0.3,
        harmMul: 0.14, subMul: 0.24, sampleLed: true,
      },

      /* Formula 1 / 1200 RR — özel yüksek devir loop’lar */
      "formula-scream": {
        idleHz: 110, midHz: 220, midSpan: 520, idleGain: 0.03, midGain: 0.22,
        windGain: 0, filterHz: 2400, filterQ: 0.75, master: 1.55,
        drive: "f1_v10_loop.wav", driveGain: 0.92,
        drive2: "f1_v10_loop.wav", drive2Gain: 0.12,
        loops: {
          idle: "bands/formula_idle_v2.wav",
          mid: "bands/formula_mid_v2.wav",
          high: "bands/formula_high_v2.wav",
        },
        bandEdges: { midStart: 20, highStart: 110 },
        gears: 8, ice: true, waveIdle: "sawtooth", waveMid: "sawtooth", bodyMul: 0.14,
        harmMul: 0.1, subMul: 0.08, sampleLed: true,
      },
      "sportbike-rr": {
        idleHz: 120, midHz: 250, midSpan: 480, idleGain: 0.028, midGain: 0.22,
        windGain: 0, filterHz: 2600, filterQ: 0.8, master: 1.5,
        drive: "superbike_rr_loop.wav", driveGain: 0.9,
        drive2: "superbike_rr_loop.wav", drive2Gain: 0.12,
        loops: {
          idle: "bands/sportbike_idle_v2.wav",
          mid: "bands/sportbike_mid_v2.wav",
          high: "bands/sportbike_high_v2.wav",
        },
        bandEdges: { midStart: 22, highStart: 115 },
        gears: 6, ice: true, waveIdle: "triangle", waveMid: "sawtooth", bodyMul: 0.12,
        harmMul: 0.1, subMul: 0.07, sampleLed: true,
      },

      "jet-hum": {
        idleHz: 80, midHz: 180, midSpan: 320, idleGain: 0.028, midGain: 0.22,
        windGain: 0, filterHz: 2000, filterQ: 0.8, master: 1.34,
        drive: "ev_hum_sport_loop.wav", driveGain: 0.62,
        drive2: "ev_modely_rev_body_loop.wav", drive2Gain: 0.28,
        gears: 1, waveIdle: "sine", waveMid: "triangle", bodyMul: 0.12,
        harmMul: 0.06, subMul: 0.08, sampleLed: true,
      },
      "pulse-drive": {
        idleHz: 58, midHz: 140, midSpan: 260, idleGain: 0.03, midGain: 0.24,
        windGain: 0, filterHz: 1600, filterQ: 0.85, master: 1.32,
        drive: "ev_hum_soft_loop.wav", driveGain: 0.66,
        drive2: "ev_id3_body_loop.wav", drive2Gain: 0.3,
        gears: 1, waveIdle: "sine", waveMid: "triangle", bodyMul: 0.14,
        harmMul: 0.05, subMul: 0.08, sampleLed: true,
      },

      /* Simülasyon (RevHeadz UX: load + gear) */
      "load-throttle": {
        idleHz: 38, midHz: 78, midSpan: 210, idleGain: 0.055, midGain: 0.3,
        windGain: 0, filterHz: 980, filterQ: 0.65, master: 1.55,
        drive: "ref_sim_load_throttle.wav", driveGain: 0.86,
        drive2: "v8_exhaust_loop.wav", drive2Gain: 0.14,
        gears: 6, ice: true, waveIdle: "triangle", waveMid: "sawtooth", bodyMul: 0.3,
        harmMul: 0.12, subMul: 0.22, sampleLed: true,
      },
      "shift-cage": {
        idleHz: 48, midHz: 100, midSpan: 280, idleGain: 0.045, midGain: 0.28,
        windGain: 0, filterHz: 1400, filterQ: 0.75, master: 1.52,
        drive: "ref_sim_shift_cage.wav", driveGain: 0.84,
        drive2: "v8_exhaust_loop.wav", drive2Gain: 0.2,
        gears: 7, ice: true, waveIdle: "triangle", waveMid: "sawtooth", bodyMul: 0.24,
        harmMul: 0.14, subMul: 0.14, sampleLed: true,
      },

      /* Prosedürel (WebAudio matematiksel karakter) */
      "piston-sigma": {
        idleHz: 44, midHz: 96, midSpan: 220, idleGain: 0.05, midGain: 0.26,
        windGain: 0, filterHz: 1600, filterQ: 0.7, master: 1.48,
        drive: "ref_proc_piston_sigma.wav", driveGain: 0.8,
        drive2: "ref_proc_intake_eq.wav", drive2Gain: 0.18,
        gears: 5, ice: true, waveIdle: "triangle", waveMid: "triangle", bodyMul: 0.22,
        harmMul: 0.16, subMul: 0.12, sampleLed: true,
      },
      "intake-eq": {
        idleHz: 52, midHz: 118, midSpan: 260, idleGain: 0.04, midGain: 0.24,
        windGain: 0, filterHz: 1900, filterQ: 0.8, master: 1.42,
        drive: "ref_proc_intake_eq.wav", driveGain: 0.78,
        drive2: "ref_proc_piston_sigma.wav", drive2Gain: 0.2,
        gears: 1, waveIdle: "sine", waveMid: "triangle", bodyMul: 0.2,
        harmMul: 0.1, subMul: 0.1, sampleLed: true,
      },

      /* Studio bank (REV / Igniter yoğunluk) */
      "ramp-forge": {
        idleHz: 40, midHz: 88, midSpan: 240, idleGain: 0.048, midGain: 0.3,
        windGain: 0, filterHz: 1200, filterQ: 0.7, master: 1.56,
        drive: "ref_grain_ramp_forge.wav", driveGain: 0.88,
        drive2: "ref_sim_load_throttle.wav", drive2Gain: 0.16,
        gears: 6, ice: true, waveIdle: "triangle", waveMid: "sawtooth", bodyMul: 0.26,
        harmMul: 0.12, subMul: 0.18, sampleLed: true,
      },
      "grain-stage": {
        idleHz: 70, midHz: 160, midSpan: 360, idleGain: 0.035, midGain: 0.26,
        windGain: 0, filterHz: 2200, filterQ: 0.85, master: 1.54,
        drive: "ref_grain_stage_cut.wav", driveGain: 0.9,
        drive2: "ref_grain_ramp_forge.wav", drive2Gain: 0.14,
        gears: 8, ice: true, waveIdle: "sawtooth", waveMid: "sawtooth", bodyMul: 0.14,
        harmMul: 0.12, subMul: 0.08, sampleLed: true,
      },
    };

    this.SAMPLE_BASE = "assets/audio/loops/";
    this.SAMPLE_VER = "20260825a";
    /** Continuous feel — Speed drives pitch; Load drives volume (Drive.app) */
    this.RATE_MIN = 0.72;
    this.RATE_MAX = 1.55;
    /** Pitch follows GPS speed closely; load is volume-only */
    this.LERP_UP = 0.48;
    this.LERP_DOWN = 0.28;
    this.TAU_UP = 0.02;
    this.TAU_DOWN = 0.085;
    this.TAU = 0.04;
    this.LERP = 0.5;
    this.ENABLE_WIND = false;
    this.ENABLE_ROAD = false;
    /** Cruise hum floor — constant-speed background (Load≈0) */
    this.AUDIBLE_FLOOR = 0.08;
    this.CRUISE_DUCK = 0.32;
    this.EV_UNDER_MUSIC_MIN = 0.35;
    this.EV_UNDER_MUSIC_MAX = 0.55;

    this._ctx = null;
    this._master = null;
    this._evMix = null;
    this._musicGain = null;
    this._musicSource = null;
    this._musicEl = null;
    this._comp = null;
    this._safety = null;

    this._voiceGraph = null;
    this._voiceKey = null;
    this._packKey = null;
    this._running = false;
    this._muted = false;
    this._unlocked = false;
    this._startLock = null;
    /** start/stop nesilleri — eski stop zamanlayıcısı yeni oturumu susturmasın */
    this._audioGen = 0;
    this._stopRestoreTimer = null;
    this._disposeTimers = new Set();
    this._resumePoll = null;
    this._musicListenBound = false;
    /** Safari/WebKit: Web Audio askıdaysa HTMLAudio loop yedek */
    this._htmlAudio = null;
    this._htmlFallbackActive = false;
    this._pendingUnlockStart = null;

    this._maxKmh = 130;
    this._volume = 0.55;
    /** Müzik yokken EV tam güç — blend yalnızca gerçek müzik/under tercihiyle */
    this._mixMode = "solo";
    this._mixIntensity = 0.55;

    this._targetKmh = 0;
    this._smoothKmh = 0;
    this._raf = null;
    this._gearInfo = { gear: 0, rpm: 0.12 };
    /** Sadece ICE: son vites + geçiş blip’i */
    this._lastGear = 0;
    this._shiftKick = 0;
    this._shiftCutUntil = 0;
    /** 0..1 gaz yükü — powerKw birincil */
    this._throttleLoad = 0;
    /** 0..1 regen yükü — negatif powerKw */
    this._regenLoad = 0;
    /** 0..1 fren/yavaşlama (lift secondary) */
    this._brakeLoad = 0;
    this._extTrend = 0;
    this._extAccel = 0;
    this._lastApplyMs = 0;
    /** Son Tesla/OBD güç (kW) — RevHeadz throttle/regen kaynağı */
    this._lastPowerKw = 0;
    /** Sürekli motor RPM (0..1) — kesintisiz flywheel; vites basamağı yok */
    this._engineRpm = 0.12;
    this._lastKmhSample = 0;
    this._accelMs = 0;

    this._bufferCache = new Map();
    this._noiseBuffer = null;
    this._visBound = false;

    this._bindUnlockUi();
  }

  /* ---------- public API (app.js uyumu) ---------- */

  getVoices() {
    return this.VOICES;
  }

  getVoiceGroupOrder() {
    return this.VOICE_GROUP_ORDER;
  }

  /** Theme rawValue / webKey / base pack → PROFILES key */
  _resolvePackKey(key) {
    if (!key || key === "silent-mode") return this.DEFAULT_VOICE;
    if (this.PROFILES[key]) return key;
    if (this.THEME_PACK_MAP[key]) return this.THEME_PACK_MAP[key];
    if (this.BASE_PACKS.includes(key)) return key;
    const camel = String(key).replace(/-([a-z])/g, (_, c) => c.toUpperCase());
    if (this.THEME_PACK_MAP[camel]) return this.THEME_PACK_MAP[camel];
    if (this.PROFILES[camel]) return camel;
    return this.DEFAULT_VOICE;
  }

  /** Accept theme key, base pack, or silent; unknown → calm-ev */
  _resolveVoiceKey(key) {
    if (key === "silent-mode") return "silent-mode";
    if (!key) return this.DEFAULT_VOICE;
    if (this.VOICES.some((v) => v.key === key)) return key;
    if (this.THEME_PACK_MAP[key] || this.PROFILES[key]) return key;
    const camel = String(key).replace(/-([a-z])/g, (_, c) => c.toUpperCase());
    if (this.THEME_PACK_MAP[camel] || this.VOICES.some((v) => v.key === camel)) return camel;
    return this.DEFAULT_VOICE;
  }

  /**
   * Tema değişince paket çöz + graph’ı yeniden kur (çalışıyorsa).
   * @param {string} themeKey ClusterTheme.rawValue veya webKey
   */
  setThemePack(themeKey) {
    const safe = this._resolveVoiceKey(themeKey);
    if (safe === "silent-mode") {
      if (this._running) this.start("silent-mode");
      return this._packKey || this.DEFAULT_VOICE;
    }
    const pack = this._resolvePackKey(safe);
    if (this._running) {
      if (this._packKey === pack && this._voiceKey === safe) return pack;
      this.start(safe);
    } else {
      this._voiceKey = safe;
      this._packKey = pack;
    }
    return pack;
  }

  setLocaleLabels(map) {
    if (!map) return;
    this.VOICES.forEach((v) => {
      if (map[v.key]) v.label = map[v.key];
    });
    const sel = document.getElementById("voiceSelect");
    if (sel) {
      Array.from(sel.options).forEach((opt) => {
        const meta = this.VOICES.find((x) => x.key === opt.value);
        if (meta) opt.textContent = meta.label;
      });
    }
  }

  getGearInfo() {
    const p = this._currentProfile() || this._voiceGraph?.profile;
    const gears = this._effectiveGears(p);
    return {
      ...this._gearInfo,
      gears,
      ice: !!p?.ice,
      load: Math.max(0, Math.min(1, this._throttleLoad || 0)),
      regen: Math.max(0, Math.min(1, this._regenLoad || 0)),
    };
  }

  /** 0..1 motor yükü — GPS ivmesi (Drive.app Load %) */
  getLoad() {
    return Math.max(0, Math.min(1, this._throttleLoad || 0));
  }

  /** Gösterge ile aynı kaynak — GPS–ses–HUD tek hat */
  getSmoothKmh() {
    return this._smoothKmh;
  }

  getMixMode() {
    return this._mixMode;
  }

  getMixIntensity() {
    return this._mixIntensity;
  }

  /** İlk jest — AudioContext oluştur + resume */
  async unlock() {
    this.kickUnlock();
    await this.ensureCtx();
    if (this._ctx?.state === "running") {
      this._unlocked = true;
      this._hideUnlockOverlay();
      const pending = this._pendingUnlockStart;
      this._pendingUnlockStart = null;
      if (pending) {
        try {
          await this.start(pending);
        } catch (_) {}
      }
    } else {
      this._unlocked = false;
      this._showUnlockOverlay(true);
      console.warn("[etubu-audio] unlock: context still", this._ctx?.state);
    }
    return this._ctx;
  }

  /**
   * Jest içinde senkron tetik — await / Promise.then ÖNCESİ çağrılmalı.
   * Safari/WebKit: create + resume + audible prime aynı tık yığınında olmalı.
   */
  kickUnlock() {
    try {
      this._ensureCtxSync();
      this._primeOutputSync();
      this._primeHtmlSync();
      if (this._ctx?.state === "suspended") {
        this._ctx.resume().catch(() => {});
      }
      if (this._ctx?.state === "running") {
        this._unlocked = true;
        this._hideUnlockOverlay();
      }
      console.info(
        "[etubu-audio] kickUnlock",
        this._ctx?.state,
        "html=",
        !!this._htmlAudio
      );
    } catch (e) {
      console.warn("[etubu-audio] kickUnlock failed", e);
    }
    return this._ctx;
  }

  _ensureCtxSync() {
    if (this._ctx) return this._ctx;
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) throw new Error("AudioContext unsupported");
    try {
      this._ctx = new AC({ latencyHint: "interactive" });
    } catch (_) {
      this._ctx = new AC();
    }
    this._buildMasterChain();
    this._bindVisibility();
    this._makeNoiseBuffer();
    // Tüm WAV’ları önceden decode etme — Tesla/düşük bellek + ana iş parçacığı kilitlenmesi
    return this._ctx;
  }

  /**
   * WebKit / Qt / Tesla: kısa buffer çalmadan context “unlocked” sayılmayabilir.
   * Safari sessiz buffer’ı yok sayabilir — kısa ama ölçülebilir tık şart.
   * Jest içinde senkron çağrılmalı.
   */
  _primeOutputSync() {
    const ctx = this._ctx;
    if (!ctx || !this._safety) return;
    try {
      if (ctx.state === "suspended") ctx.resume().catch(() => {});
      const n = Math.max(1, Math.floor(ctx.sampleRate * 0.05));
      const buf = ctx.createBuffer(1, n, ctx.sampleRate);
      const data = buf.getChannelData(0);
      for (let i = 0; i < n; i++) {
        // Kısa tık (~40ms) — WebKit autoplay kilidini kırar
        const env = i < 64 ? 1 - i / 64 : 0;
        data[i] = Math.sin((i / ctx.sampleRate) * 880 * Math.PI * 2) * 0.08 * env;
      }
      const src = ctx.createBufferSource();
      src.buffer = buf;
      const g = ctx.createGain();
      g.gain.value = 0.35;
      src.connect(g);
      g.connect(this._safety);
      src.start(0);
    } catch (_) {}
  }

  /** Safari yedek: HTMLAudioElement.play() jest içinde */
  _primeHtmlSync() {
    try {
      const a = this._ensureHtmlAudio();
      a.muted = false;
      a.volume = 0.001;
      const p = a.play();
      if (p && typeof p.then === "function") {
        p.then(() => {
          if (!this._htmlFallbackActive) {
            try {
              a.pause();
              a.currentTime = 0;
            } catch (_) {}
          }
        }).catch(() => {});
      }
    } catch (_) {}
  }

  _ensureHtmlAudio() {
    if (this._htmlAudio) return this._htmlAudio;
    const a = new Audio();
    a.preload = "auto";
    a.loop = true;
    a.playsInline = true;
    a.setAttribute("playsinline", "");
    a.setAttribute("webkit-playsinline", "");
    // Motor-only yedek — combustion_rich / kabin rüzgarı YOK
    a.src = this.SAMPLE_BASE + "v8_exhaust_loop.wav?v=" + this.SAMPLE_VER;
    a.volume = 0.01;
    this._htmlAudio = a;
    return a;
  }

  async _engageHtmlFallback(active) {
    if (!active) {
      this._htmlFallbackActive = false;
      try {
        this._htmlAudio?.pause();
      } catch (_) {}
      return false;
    }
    // WebAudio zaten çalışıyorsa HTML bed/rüzgar katmanı ekleme — sadece motor graph
    if (this._ctx?.state === "running") {
      this._htmlFallbackActive = false;
      try {
        this._htmlAudio?.pause();
      } catch (_) {}
      return false;
    }
    try {
      const a = this._ensureHtmlAudio();
      a.muted = false;
      const vol = Math.min(1, Math.max(0.2, (this._volume || 0.55) * 0.55));
      a.volume = vol;
      a.playbackRate = Math.max(0.85, Math.min(1.3, 0.92 + Math.min(1, (this._smoothKmh || 40) / this._maxKmh) * 0.38));
      await a.play();
      this._htmlFallbackActive = true;
      console.warn("[etubu-audio] HTMLAudio fallback engaged");
      return true;
    } catch (e) {
      console.warn("[etubu-audio] HTMLAudio fallback failed", e);
      this._htmlFallbackActive = false;
      return false;
    }
  }

  _syncHtmlFallbackGain() {
    if (!this._htmlFallbackActive || !this._htmlAudio) return;
    // WebAudio açıldıysa HTML bed'i tamamen kapat (ortak rüzgar hissi yok)
    if (this._ctx?.state === "running") {
      this._engageHtmlFallback(false);
      return;
    }
    try {
      const n = Math.min(1, Math.max(0, (this._smoothKmh || 0) / this._maxKmh));
      const vol = Math.min(1, Math.max(0.18, (this._volume || 0.55) * (0.35 + n * 0.5)));
      this._htmlAudio.volume = this._muted ? 0 : vol;
      this._htmlAudio.playbackRate = Math.max(0.85, Math.min(1.3, 0.88 + n * 0.4));
    } catch (_) {}
  }

  async ensureCtx() {
    this._ensureCtxSync();
    if (this._ctx.state === "suspended") {
      try {
        await this._ctx.resume();
      } catch (_) {}
    }
    return this._ctx;
  }

  _setMasterOpen(open) {
    if (!this._master || !this._ctx) return;
    const level = open ? 1 : 0.0001;
    const t = this._ctx.currentTime;
    try {
      this._master.gain.cancelScheduledValues(t);
      this._master.gain.setValueAtTime(level, t);
      // .value de yaz — bazı gömülü Chromium’larda automation gecikir
      this._master.gain.value = level;
    } catch (_) {
      try {
        this._master.gain.value = level;
      } catch (__) {
        this._targetParam(this._master.gain, level, 0.05, true);
      }
    }
  }

  _startResumePoll() {
    if (this._resumePoll != null) return;
    this._resumePoll = setInterval(() => {
      if (!this._running || !this._ctx) {
        this._stopResumePoll();
        return;
      }
      if (this._ctx.state === "suspended") {
        this._ctx.resume().catch(() => {});
        this._primeOutputSync();
        if (!this._htmlFallbackActive) {
          this._engageHtmlFallback(true).catch(() => {});
        }
      } else if (this._htmlFallbackActive && this._ctx.state === "running") {
        this._engageHtmlFallback(false);
        this._hideUnlockOverlay();
      }
    }, 500);
  }

  _stopResumePoll() {
    if (this._resumePoll != null) {
      clearInterval(this._resumePoll);
      this._resumePoll = null;
    }
  }

  /** Sürüş başında: context + master + mute doğrula */
  async ensureAudible(voiceKey) {
    this.kickUnlock();
    await this.ensureCtx();
    const silent = voiceKey === "silent-mode";
    if (!silent) this._muted = false;
    this._setMasterOpen(!silent && !this._muted);
    if (this._evMix) {
      try {
        this._evMix.gain.value = silent ? 0.0001 : 1;
      } catch (_) {}
    }
    if (this._ctx?.state === "suspended") {
      try {
        await this._ctx.resume();
      } catch (_) {}
      this._primeOutputSync();
    }
    if (this._ctx?.state === "suspended") {
      this._unlocked = false;
      if (!silent) {
        this._pendingUnlockStart = voiceKey || this._voiceKey || this.DEFAULT_VOICE;
        this._showUnlockOverlay(true);
        await this._engageHtmlFallback(true);
      }
      console.warn("[etubu-audio] ensureAudible: still suspended");
    } else {
      this._unlocked = true;
      this._hideUnlockOverlay();
      // WebAudio ayaktayken HTML bed katmanını kapat — sadece motor graph
      await this._engageHtmlFallback(false);
    }
    this._applyEvMix();
    if (this._running) this._applyParams(this._smoothKmh, true);
    return this._ctx?.state === "running" || this._htmlFallbackActive;
  }

  async start(key) {
    // KRİTİK: tüm jest-duyarlı iş buranın sync kısmında (await/.then yok)
    this.kickUnlock();
    this._primeOutputSync();
    this._primeHtmlSync();

    const gen = ++this._audioGen;
    if (this._stopRestoreTimer) {
      clearTimeout(this._stopRestoreTimer);
      this._stopRestoreTimer = null;
    }

    const resolved = this._resolveVoiceKey(key);

    if (resolved !== "silent-mode") {
      this._muted = false;
    }

    const packKey =
      resolved === "silent-mode" ? null : this._resolvePackKey(resolved);

    // Oscillator start — hâlâ kullanıcı jest yığınında (caller await etmeden çağırdıysa)
    const next =
      resolved === "silent-mode"
        ? this._buildSilentGraph()
        : this._buildVoiceGraph(packKey || this.DEFAULT_VOICE);

    const old = this._voiceGraph;
    this._voiceGraph = next;
    this._voiceKey = resolved;
    this._packKey = packKey;
    this._running = true;
    this._lastGear = 0;
    this._shiftKick = 0;

    this._setMasterOpen(resolved !== "silent-mode" && !this._muted);
    if (resolved !== "silent-mode") {
      if (!this._isMusicAudible()) {
        this._targetParam(this._evMix.gain, 1, 0.05, true);
        try {
          this._evMix.gain.value = 1;
        } catch (_) {}
      } else {
        this._applyEvMix();
      }
    } else {
      this._applyEvMix();
    }
    this._startRaf();
    this._startResumePoll();
    if (resolved !== "silent-mode") this._engageHtmlFallback(true).catch(() => {});
    else this._engageHtmlFallback(false).catch(() => {});
    this._applyParams(Math.max(this._smoothKmh, 0), true);
    // Kısa gecikmeli ikinci force — ctx resume / sample attach yarışına karşı
    setTimeout(() => {
      if (gen !== this._audioGen || !this._running) return;
      this._setMasterOpen(resolved !== "silent-mode" && !this._muted);
      this._applyParams(this._smoothKmh, false);
    }, 80);

    const finish = async () => {
      if (gen !== this._audioGen) {
        this._disposeGraph(next);
        return false;
      }

      if (this._ctx?.state === "suspended") {
        try {
          await this._ctx.resume();
        } catch (_) {}
        this._primeOutputSync();
      }

      if (this._ctx?.state === "running") {
        this._unlocked = true;
        this._hideUnlockOverlay();
        if (resolved !== "silent-mode") await this._engageHtmlFallback(true);
        else await this._engageHtmlFallback(false);
      } else if (resolved !== "silent-mode") {
        console.warn("[etubu-audio] start: ctx=", this._ctx?.state, "voice=", resolved);
        this._pendingUnlockStart = resolved;
        this._showUnlockOverlay(true);
        await this._engageHtmlFallback(true);
      }

      if (old) this._disposeGraph(old);
      return (
        resolved === "silent-mode" ||
        this._ctx?.state === "running" ||
        this._htmlFallbackActive
      );
    };

    this._startLock = (this._startLock || Promise.resolve())
      .catch(() => {})
      .then(finish);
    return this._startLock;
  }

  stop() {
    this._audioGen += 1;
    const gen = this._audioGen;
    this._running = false;
    this._pendingUnlockStart = null;
    this._stopRaf();
    this._stopResumePoll();
    this._engageHtmlFallback(false);
    this._targetKmh = 0;
    this._smoothKmh = 0;
    if (this._stopRestoreTimer) {
      clearTimeout(this._stopRestoreTimer);
      this._stopRestoreTimer = null;
    }
    if (this._master && this._ctx) {
      this._targetParam(this._master.gain, 0.0001, 0.08);
    }
    const g = this._voiceGraph;
    this._voiceGraph = null;
    if (g) {
      const tid = setTimeout(() => {
        this._disposeTimers.delete(tid);
        this._disposeGraph(g);
      }, 100);
      this._disposeTimers.add(tid);
    }
    // Eski oturumun master=1 restore’u yeni start’ı ezmesin
    this._stopRestoreTimer = setTimeout(() => {
      this._stopRestoreTimer = null;
      if (gen !== this._audioGen || this._running) return;
      try {
        this._setMasterOpen(!this._muted);
      } catch (_) {}
    }, 120);
  }

  /**
   * GPS dv/dt → Load % (volume / effort). Drive.app: Accel = Volume.
   * ~0.15 km/h/s audible; ~1.5 climb; 3.5+ full load.
   */
  _throttleFromAccel(a) {
    const x = Number(a) || 0;
    const dead = 0.1;
    if (x <= dead) return 0;
    return Math.max(0, Math.min(1, Math.pow((x - dead) / 3.5, 0.78)));
  }

  _regenFromAccel(a) {
    const x = Number(a) || 0;
    const dead = 0.14;
    if (x >= -dead) return 0;
    return Math.max(0, Math.min(1, (-x - dead) / 4.6));
  }

  _driveLoadsFromMeta(meta) {
    const powerKw = Number(meta?.powerKw);
    const accelIn = Number(meta?.accelKmhS);
    const trendIn = Number(meta?.trend);
    const accel = Number.isFinite(accelIn)
      ? accelIn
      : Number.isFinite(trendIn)
        ? trendIn
        : this._extAccel;
    this._extAccel = Number.isFinite(accel) ? accel : 0;
    this._extTrend = this._extAccel;

    let targetThrottle = this._throttleFromAccel(this._extAccel);
    let targetRegen = this._regenFromAccel(this._extAccel);

    if (Number.isFinite(powerKw)) {
      this._lastPowerKw = powerKw;
      if (Math.abs(powerKw) > 8) {
        const pThr = powerKw > 0 ? Math.max(0, Math.min(1, powerKw / 220)) : 0;
        const pReg = powerKw < 0 ? Math.max(0, Math.min(1, -powerKw / 80)) : 0;
        // Pedal + GPS mikro-ivme: küçük gaz değişimi integer kW'da kaybolmasın
        targetThrottle = Math.max(pThr, targetThrottle * 0.72);
        targetRegen = Math.max(pReg, targetRegen * 0.65);
      } else if (Math.abs(powerKw) > 1) {
        if (powerKw > 0) {
          targetThrottle = Math.max(targetThrottle, Math.min(1, powerKw / 220));
        } else {
          targetRegen = Math.max(targetRegen, Math.min(1, -powerKw / 80));
        }
      }
    }
    return { targetThrottle, targetRegen };
  }

  /** GPS/OBD/Tesla — Speed→pitch, Accel→load/volume */
  setSpeed(kmh, meta) {
    this._targetKmh = Math.max(0, Number(kmh) || 0);
    if (meta?.source === "obd") this.setSpeedSource("obd");
    else if (meta?.source === "tesla") this.setSpeedSource("tesla");
    else if (meta?.source === "demo") this.setSpeedSource("gps");
    else if (meta?.source) this.setSpeedSource("gps");
    const lag = this._targetKmh - this._smoothKmh;
    const { targetThrottle, targetRegen } = this._driveLoadsFromMeta(meta || {});

    // Load rises fast (gas), falls slower (coast → hum)
    const thrRise = targetThrottle >= this._throttleLoad - 0.01;
    this._throttleLoad +=
      (targetThrottle - this._throttleLoad) * (thrRise ? 0.78 : 0.12);
    const regRise = targetRegen >= this._regenLoad - 0.01;
    this._regenLoad +=
      (targetRegen - this._regenLoad) * (regRise ? 0.58 : 0.2);
    this._brakeLoad = Math.max(this._regenFromAccel(this._extAccel) * 0.7, this._regenLoad * 0.85);

    // Pitch tracks GPS speed tightly (Drive.app: Speed = Pitch)
    if (Math.abs(lag) > 0.05) {
      const catchUp = meta?.source === "demo" ? 0.9 : 0.72;
      this._smoothKmh += lag * catchUp;
    } else {
      this._smoothKmh = this._targetKmh;
    }
    const feelKmh = this._smoothKmh;
    const norm = this._norm(feelKmh);
    // Gear / RPM from speed only — load does not fake pitch
    this._gearInfo = this._gearFromNorm(norm, this._currentProfile());
    if (this._throttleLoad > 0.08) {
      // Slight revs under load without owning pitch
      this._gearInfo = {
        ...this._gearInfo,
        rpm: Math.min(1, this._gearInfo.rpm + this._throttleLoad * 0.12),
      };
    } else if (this._regenLoad > 0.08) {
      this._gearInfo = {
        ...this._gearInfo,
        rpm: Math.max(0.1, this._gearInfo.rpm * (1 - this._regenLoad * 0.08) + this._regenLoad * 0.22),
      };
    }
    const now = performance.now();
    const busy =
      Math.abs(this._extAccel) > 0.1 ||
      Math.abs(lag) > 0.1 ||
      this._throttleLoad > 0.03 ||
      this._regenLoad > 0.03 ||
      this._brakeLoad > 0.03;
    if (this._running && now - (this._lastApplyMs || 0) >= 24 && busy) {
      this._applyParams(this._smoothKmh, false);
      this._lastApplyMs = now;
    } else if (this._running && now - (this._lastApplyMs || 0) >= 80) {
      this._applyParams(this._smoothKmh, false);
      this._lastApplyMs = now;
    }
    return this.getGearInfo();
  }

  /** Cap / native: AudioContext resume */
  resume() {
    try {
      const ctx = this.ensureCtx?.() || this._ctx;
      if (ctx && ctx.state === "suspended" && ctx.resume) return ctx.resume();
    } catch (_) {}
    return Promise.resolve();
  }

  /** Cap: 'high' | 'low' — yüksek kalitede daha sıkı τ */
  setQuality(q) {
    this._quality = q === "high" ? "high" : "normal";
    if (this._quality === "high") {
      this.TAU_UP = Math.min(this.TAU_UP || 0.05, 0.04);
    }
  }

  /** Demo: lerp beklemeden hemen duyulabilir hız */
  snapSpeed(kmh) {
    const v = Math.max(0, Number(kmh) || 0);
    this._targetKmh = v;
    this._smoothKmh = v;
    if (this._running) this._applyParams(v, true);
    this._syncHtmlFallbackGain();
    return this._gearInfo;
  }

  hasMusicSource() {
    return !!this._musicSource;
  }

  /** Bağlı müzik elementi gerçekten çalıyor mu? */
  _isMusicAudible() {
    const el = this._musicEl;
    if (!this._musicSource || !el) return false;
    try {
      if (el.paused || el.ended) return false;
      if (el.muted) return false;
      if ((el.volume || 0) <= 0.001) return false;
      return true;
    } catch (_) {
      return !!this._musicSource;
    }
  }

  isMusicPlaying() {
    return this._isMusicAudible();
  }

  setSpeedSource(_source) {
    /* GPS/OBD ayrımı şu an aynı lerp; API uyumu için no-op tutuluyor */
  }

  setMaxKmh(v) {
    this._maxKmh = Math.max(40, Number(v) || 130);
  }

  setVolume(v) {
    let x = Math.max(0, Math.min(3.2, Number(v) || 0));
    // Tesla kabin: ılımlı boost — eski 1.65× clip/cızırtı yapıyordu
    if (this._cabinSmooth()) {
      x = Math.min(2.4, x * 1.22);
    }
    this._volume = x;
    if (this._running) this._applyParams(this._smoothKmh, true);
    this._syncHtmlFallbackGain();
  }

  setMuted(muted) {
    this._muted = !!muted;
    this._setMasterOpen(!this._muted);
    this._syncHtmlFallbackGain();
  }

  isMuted() {
    return !!this._muted;
  }

  setMixMode(mode) {
    if (mode === "solo") this.setMixUnderMusic(false, 1);
    else if (mode === "under") this.setMixUnderMusic(true, this._cabinSmooth() ? 0.72 : 0.45);
    else this.setMixUnderMusic(true, this._mixIntensity || 0.45);
  }

  setMixUnderMusic(under, intensity) {
    this._mixMode = under ? "blend" : "solo";
    if (intensity != null) this._mixIntensity = intensity;
    this._applyEvMix();
  }

  setMixIntensity(v) {
    this._mixIntensity = Math.max(0.1, Math.min(1, Number(v) || 0.4));
    this._applyEvMix();
  }

  async connectMusicElement(el) {
    await this.ensureCtx();
    this.disconnectMusic();
    if (!el || !this._musicGain) return null;
    try {
      this._musicEl = el;
      this._musicSource = this._ctx.createMediaElementSource(el);
      this._musicSource.connect(this._musicGain);
      this._bindMusicElementEvents(el);
      this._applyEvMix();
      return () => this.disconnectMusic();
    } catch (e) {
      console.warn("Music element connect failed", e);
      this._musicEl = null;
      return null;
    }
  }

  _bindMusicElementEvents(el) {
    if (!el || this._musicListenBound) return;
    this._musicListenBound = true;
    const sync = () => this._applyEvMix();
    ["play", "playing", "pause", "ended", "volumechange"].forEach((evt) => {
      el.addEventListener(evt, sync);
    });
  }

  disconnectMusic() {
    try {
      this._musicSource?.disconnect();
    } catch (_) {}
    this._musicSource = null;
    this._musicEl = null;
    this._applyEvMix();
  }

  setMusicVolume(v) {
    if (this._musicGain && this._ctx) {
      this._targetParam(
        this._musicGain.gain,
        Math.max(0, Math.min(1.5, Number(v) || 0)),
        0.08
      );
    }
  }

  getContext() {
    return this._ctx;
  }

  /* ---------- master chain ---------- */

  /** Tesla / araç hoparlörü: tiz cızırtı + clip hassas */
  _cabinSmooth() {
    try {
      return !!(typeof CarBrowser !== "undefined" && CarBrowser.isTesla?.());
    } catch (_) {
      return false;
    }
  }

  _buildMasterChain() {
    const ctx = this._ctx;
    const cabin = this._cabinSmooth();
    this._master = ctx.createGain();
    this._master.gain.value = cabin ? 1.0 : 1;
    this._evMix = ctx.createGain();
    this._evMix.gain.value = 1;
    this._musicGain = ctx.createGain();
    this._musicGain.gain.value = 0.85;

    const hp = ctx.createBiquadFilter();
    hp.type = "highpass";
    hp.frequency.value = cabin ? 48 : 32;
    hp.Q.value = 0.7;

    // Kabin: tiz/alias cızırtısını kesin
    const lp = ctx.createBiquadFilter();
    lp.type = "lowpass";
    lp.frequency.value = cabin ? 3000 : 4200;
    lp.Q.value = 0.65;
    this._airLp = lp;

    // Yumuşak limiter hissi — pump yok, clip yok
    this._comp = ctx.createDynamicsCompressor();
    this._comp.threshold.value = cabin ? -24 : -20;
    this._comp.knee.value = cabin ? 30 : 24;
    this._comp.ratio.value = cabin ? 3.2 : 2.0;
    this._comp.attack.value = cabin ? 0.012 : 0.008;
    this._comp.release.value = cabin ? 0.28 : 0.22;

    this._safety = ctx.createGain();
    this._safety.gain.value = cabin ? 0.86 : 0.92;

    this._evMix.connect(this._master);
    this._musicGain.connect(this._master);
    this._master.connect(hp);
    hp.connect(lp);
    lp.connect(this._comp);
    this._comp.connect(this._safety);
    this._safety.connect(ctx.destination);
    this._applyEvMix();
  }

  _applyEvMix() {
    if (!this._evMix || !this._ctx) return;
    // Müzik yok / çalmıyor / solo → tam EV
    const musicOn = this._isMusicAudible();
    const under = this._mixMode !== "solo";
    if (!musicOn || !under) {
      this._targetParam(this._evMix.gain, 1, 0.08, true);
      try {
        this._evMix.gain.value = 1;
      } catch (_) {}
      return;
    }
    // Müzik çalarken duyulabilir duck: 0.35–0.55
    const t = Math.min(1, Math.max(0, this._mixIntensity ?? 0.55));
    const cabin = this._cabinSmooth();
    const min = cabin ? 0.58 : this.EV_UNDER_MUSIC_MIN;
    const max = cabin ? 0.82 : this.EV_UNDER_MUSIC_MAX;
    const level = min + t * (max - min);
    this._targetParam(this._evMix.gain, level, 0.12, true);
    try {
      this._evMix.gain.value = level;
    } catch (_) {}
  }

  /* ---------- unlock overlay + visibility ---------- */

  _bindUnlockUi() {
    if (typeof document === "undefined") return;
    const ready = () => {
      const overlay = document.getElementById("audioUnlockOverlay");
      const btn = document.getElementById("audioUnlockBtn");
      const dismiss = (e) => {
        try {
          e?.preventDefault?.();
        } catch (_) {}
        // Senkron unlock — overlay kapanmaz ta ki running
        this.kickUnlock();
        this._primeHtmlSync();
        this.unlock().catch(() => {});
      };
      btn?.addEventListener("pointerdown", dismiss, { passive: false });
      btn?.addEventListener("click", dismiss);
      overlay?.addEventListener("pointerdown", (e) => {
        if (e.target === overlay || e.target === btn) dismiss(e);
      });
      // START / demo — jest anında senkron unlock
      document.getElementById("startBtn")?.addEventListener(
        "pointerdown",
        () => {
          this.kickUnlock();
        },
        { once: false, passive: true }
      );
      document.getElementById("demoBtn")?.addEventListener(
        "pointerdown",
        () => {
          this.kickUnlock();
        },
        { once: false, passive: true }
      );
      // Sayfa yükünde overlay GÖSTERME — yalnızca start başarısız olunca
    };
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", ready);
    } else {
      ready();
    }
  }

  _showUnlockOverlay(force = false) {
    const overlay = document.getElementById("audioUnlockOverlay");
    if (!overlay) return;
    const need =
      force ||
      !this._unlocked ||
      !this._ctx ||
      this._ctx.state === "suspended";
    if (need) overlay.hidden = false;
  }

  _showUnlockOverlayIfNeeded() {
    this._showUnlockOverlay(false);
  }

  _hideUnlockOverlay() {
    // Çalışmıyorsa gizleme — Safari’de yanlış “unlocked” kaçmasın
    if (this._ctx && this._ctx.state !== "running" && !this._htmlFallbackActive) {
      return;
    }
    const overlay = document.getElementById("audioUnlockOverlay");
    if (overlay) overlay.hidden = true;
  }

  _bindVisibility() {
    if (this._visBound) return;
    this._visBound = true;
    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState !== "visible") return;
      if (!this._ctx) return;
      if (this._ctx.state === "suspended") {
        this._ctx.resume().catch(() => {});
      }
    });
    window.addEventListener("pageshow", () => {
      if (this._ctx?.state === "suspended") {
        this._ctx.resume().catch(() => {});
      }
    });
  }

  /* ---------- buffers ---------- */

  _makeNoiseBuffer() {
    const ctx = this._ctx;
    const len = Math.floor(ctx.sampleRate * 2);
    const buf = ctx.createBuffer(1, len, ctx.sampleRate);
    const data = buf.getChannelData(0);
    for (let i = 0; i < len; i++) data[i] = Math.random() * 2 - 1;
    this._noiseBuffer = buf;
  }

  async _loadBuffer(file) {
    if (!file || !this._ctx) return null;
    const url = this.SAMPLE_BASE + file;
    if (this._bufferCache.has(url)) return this._bufferCache.get(url);
    const pending = (async () => {
      const ctrl = typeof AbortController !== "undefined" ? new AbortController() : null;
      const timer = ctrl ? setTimeout(() => ctrl.abort(), 8000) : null;
      try {
        const res = await fetch(url + "?v=" + this.SAMPLE_VER, ctrl ? { signal: ctrl.signal } : undefined);
        if (!res.ok) throw new Error("sample " + file);
        const raw = await res.arrayBuffer();
        return await this._ctx.decodeAudioData(raw.slice(0));
      } finally {
        if (timer) clearTimeout(timer);
      }
    })();
    this._bufferCache.set(url, pending);
    try {
      const buf = await pending;
      this._bufferCache.set(url, buf);
      return buf;
    } catch (e) {
      this._bufferCache.delete(url);
      console.warn("Sample load failed", file, e);
      return null;
    }
  }

  async _preloadFx() {
    await this.ensureCtx();
    const files = new Set();
    Object.values(this.PROFILES).forEach((p) => {
      if (this.ENABLE_ROAD && p.road) files.add(p.road);
      if (p.drive) files.add(p.drive);
      if (p.drive2) files.add(p.drive2);
      if (p.regen) files.add(p.regen);
      if (p.loops) {
        if (p.loops.idle) files.add(p.loops.idle);
        if (p.loops.mid) files.add(p.loops.mid);
        if (p.loops.high) files.add(p.loops.high);
      }
    });
    await Promise.all([...files].map((f) => this._loadBuffer(f)));
  }

  /* ---------- voice graphs ---------- */

  _currentProfile() {
    const pack = this._packKey || this._resolvePackKey(this._voiceKey);
    return this.PROFILES[pack] || this.PROFILES[this.DEFAULT_VOICE];
  }

  _buildSilentGraph() {
    return { nodes: [], sources: [], profile: null, silent: true };
  }

  _buildVoiceGraph(key) {
    const ctx = this._ctx;
    const pack = this._resolvePackKey(key);
    const profile = this.PROFILES[pack] || this.PROFILES[this.DEFAULT_VOICE];
    const cabin = this._cabinSmooth();
    const bus = ctx.createGain();
    bus.gain.value = cabin ? 0.88 : 1;
    bus.connect(this._evMix);

    const nodes = {};
    const sources = [];
    // Kabin: sawtooth cızırtı yapar → sine/triangle
    const waveIdle = cabin ? "sine" : profile.waveIdle || (profile.ice ? "triangle" : "sine");
    const waveMid = cabin
      ? "triangle"
      : profile.waveMid || (profile.ice ? "sawtooth" : "triangle");
    const fq = cabin ? Math.min(0.55, profile.filterQ || 0.6) : profile.filterQ;
    const fBase = cabin ? Math.min(1600, profile.filterHz || 1200) : profile.filterHz;

    // --- Idle katmanı (düşük hız) ---
    const idleOsc = ctx.createOscillator();
    idleOsc.type = waveIdle;
    idleOsc.frequency.value = profile.idleHz;
    const idleFilter = ctx.createBiquadFilter();
    idleFilter.type = "lowpass";
    idleFilter.frequency.value = fBase * 0.5;
    idleFilter.Q.value = fq;
    const idleGain = ctx.createGain();
    idleGain.gain.value = 0.0001;
    idleOsc.connect(idleFilter);
    idleFilter.connect(idleGain);
    idleGain.connect(bus);
    sources.push(idleOsc);
    nodes.idle = { osc: idleOsc, filter: idleFilter, gain: idleGain };

    // --- Mid katmanı (crossfade ile girer) ---
    const midOsc = ctx.createOscillator();
    midOsc.type = waveMid;
    midOsc.frequency.value = profile.midHz;
    const midFilter = ctx.createBiquadFilter();
    midFilter.type = "lowpass";
    midFilter.frequency.value = fBase;
    midFilter.Q.value = fq;
    const midGain = ctx.createGain();
    midGain.gain.value = 0.0001;
    midOsc.connect(midFilter);
    midFilter.connect(midGain);
    midGain.connect(bus);
    sources.push(midOsc);
    nodes.mid = { osc: midOsc, filter: midFilter, gain: midGain };

    // Harmonic / gövde — lowpass only (ıslık yok)
    const bodyOsc = ctx.createOscillator();
    bodyOsc.type = "sine";
    bodyOsc.frequency.value = profile.idleHz * 2;
    const bodyGain = ctx.createGain();
    bodyGain.gain.value = 0.0001;
    bodyOsc.connect(bodyGain);
    bodyGain.connect(bus);
    sources.push(bodyOsc);
    nodes.body = { osc: bodyOsc, gain: bodyGain };

    const harmOsc = ctx.createOscillator();
    harmOsc.type = "sine";
    harmOsc.frequency.value = profile.midHz * 1.5;
    const harmFilter = ctx.createBiquadFilter();
    harmFilter.type = "lowpass";
    harmFilter.frequency.value = Math.min(cabin ? 1800 : 2400, fBase * 1.1);
    harmFilter.Q.value = 0.45;
    const harmGain = ctx.createGain();
    harmGain.gain.value = 0.0001;
    harmOsc.connect(harmFilter);
    harmFilter.connect(harmGain);
    harmGain.connect(bus);
    sources.push(harmOsc);
    nodes.harm = { osc: harmOsc, filter: harmFilter, gain: harmGain };

    const subOsc = ctx.createOscillator();
    subOsc.type = "sine";
    subOsc.frequency.value = Math.max(28, profile.idleHz * 0.5);
    const subGain = ctx.createGain();
    subGain.gain.value = 0.0001;
    subOsc.connect(subGain);
    subGain.connect(bus);
    sources.push(subOsc);
    nodes.sub = { osc: subOsc, gain: subGain };

    // Rüzgar / ıslık / EMF — bilinçli olarak kapalı (ıslık şikayeti)
    if (this.ENABLE_WIND) {
      const windSrc = ctx.createBufferSource();
      windSrc.buffer = this._noiseBuffer;
      windSrc.loop = true;
      windSrc.loopStart = 0;
      windSrc.loopEnd = this._noiseBuffer.duration;
      const windHp = ctx.createBiquadFilter();
      windHp.type = "highpass";
      windHp.frequency.value = 900;
      const windLp = ctx.createBiquadFilter();
      windLp.type = "lowpass";
      windLp.frequency.value = 4500;
      const windGain = ctx.createGain();
      windGain.gain.value = 0.0001;
      windSrc.connect(windHp);
      windHp.connect(windLp);
      windLp.connect(windGain);
      windGain.connect(bus);
      sources.push(windSrc);
      nodes.wind = { src: windSrc, hp: windHp, lp: windLp, gain: windGain };
    }

    // Prosedürel kaynakları HEMEN başlat — WAV beklerken sessizlik olmasın
    const t0 = ctx.currentTime;
    for (const s of sources) {
      try {
        s.start(t0);
      } catch (_) {}
    }

    const graph = { nodes, sources, bus, profile, silent: false, bands: null };

    // WAV katmanları — idle/mid/high crossfade (tercih) veya legacy drive/drive2
    if (this.ENABLE_ROAD && profile.road) {
      this._attachSampleLayer(graph, "road", profile.road, {
        filterHz: 1800,
        fadeScale: 0.02,
        minLoop: 0.2,
      }).catch(() => {});
    }
    const bands = this._resolveLoopBands(profile);
    if (bands) {
      graph.bands = bands;
      const filtHz = Math.min(cabin ? 2000 : 2400, (profile.filterHz || 1200) * (cabin ? 1.0 : 1.15));
      this._attachSampleLayer(graph, "loopIdle", bands.idle, {
        filterHz: filtHz * 0.8,
        filterQ: cabin ? 0.35 : 0.45,
        fadeScale: 0.02,
        minLoop: 0.3,
      }).catch(() => {});
      this._attachSampleLayer(graph, "loopMid", bands.mid, {
        filterHz: filtHz,
        filterQ: cabin ? 0.35 : 0.5,
        fadeScale: 0.02,
        minLoop: 0.3,
      }).catch(() => {});
      this._attachSampleLayer(graph, "loopHigh", bands.high, {
        filterHz: filtHz * 1.05,
        filterQ: cabin ? 0.35 : 0.5,
        fadeScale: 0.02,
        minLoop: 0.3,
      }).catch(() => {});
    } else {
      if (profile.drive) {
        this._attachSampleLayer(graph, "drive", profile.drive, {
          filterHz: Math.min(cabin ? 2000 : 2400, (profile.filterHz || 1200) * (cabin ? 1.0 : 1.15)),
          filterQ: cabin ? 0.35 : 0.5,
          fadeScale: 0.02,
          minLoop: 0.3,
        }).catch(() => {});
      }
      if (profile.drive2) {
        this._attachSampleLayer(graph, "drive2", profile.drive2, {
          filterHz: Math.min(cabin ? 1800 : 2200, (profile.filterHz || 1200) * (cabin ? 0.95 : 1.05)),
          filterQ: cabin ? 0.35 : 0.45,
          fadeScale: 0.02,
          minLoop: 0.3,
        }).catch(() => {});
      }
    }
    // Regen body — throttle lift / negative kW
    const regenFile = profile.regen || "ev_modely_rev_body_loop.wav";
    this._attachSampleLayer(graph, "regen", regenFile, {
      filterHz: Math.min(cabin ? 1900 : 2300, (profile.filterHz || 1200) * 1.1),
      filterQ: cabin ? 0.35 : 0.5,
      fadeScale: 0.02,
      minLoop: 0.3,
    }).catch(() => {});

    return graph;
  }

  /**
   * idle / mid / high loop bankası — yoksa drive+drive2’den türetilir.
   * Drop-in: profile.loops = { idle, mid, high } (CC0 WAV önerilir).
   */
  _resolveLoopBands(p) {
    if (!p || p.sampleLed === false) return null;
    const gains = {
      idle: p.loopGains?.idle ?? p.drive2Gain ?? 0.4,
      mid: p.loopGains?.mid ?? p.driveGain ?? 0.72,
      high: p.loopGains?.high ?? p.driveGain ?? 0.7,
    };
    const edges = {
      midStart: p.bandEdges?.midStart ?? (p.ice ? 14 : 12),
      highStart: p.bandEdges?.highStart ?? (p.ice ? 95 : 72),
    };
    if (p.loops && (p.loops.idle || p.loops.mid || p.loops.high)) {
      return {
        idle: p.loops.idle || p.loops.mid || p.drive2 || p.drive,
        mid: p.loops.mid || p.drive || p.loops.idle,
        high: p.loops.high || p.loops.mid || p.drive,
        gains,
        edges,
      };
    }
    if (p.drive) {
      return {
        idle: p.drive2 || p.drive,
        mid: p.drive,
        high: p.drive,
        gains,
        edges,
      };
    }
    return null;
  }

  /** Smoothstep 0..1 */
  _smoothstep(x) {
    const t = Math.max(0, Math.min(1, x));
    return t * t * (3 - 2 * t);
  }

  /**
   * Band position: Speed primary (pitch bands), Load secondary for edge push.
   * Drive.app: bands follow speed; load does not own the spectrum.
   */
  _bandWeights(kmh, edges, loadPos) {
    const mid0 = edges?.midStart ?? 12;
    const high0 = edges?.highStart ?? 72;
    const speedPos = Math.max(0, Math.min(1, kmh / Math.max(40, this._maxKmh)));
    const pos =
      loadPos != null && Number.isFinite(loadPos)
        ? Math.max(0, Math.min(1, speedPos * 0.78 + loadPos * 0.22))
        : speedPos;
    // Map 0..1 → pseudo-kmh along profile edges for smoothstep reuse
    const feel = mid0 + pos * Math.max(20, high0 + 40 - mid0);
    const fade = 42;
    let idle = 1 - this._smoothstep((feel - (mid0 - fade)) / fade);
    let high = this._smoothstep((feel - (high0 - fade * 0.85)) / (fade * 1.35));
    let mid = this._smoothstep((feel - (mid0 - fade * 0.55)) / fade);
    mid = Math.min(mid, 1 - high * 0.88);
    mid = Math.max(0, mid);
    idle = Math.max(0, idle);
    high = Math.max(0, high);
    const sum = idle + mid + high || 1;
    const i = idle / sum;
    const m = mid / sum;
    const h = high / sum;
    const e = i * i + m * m + h * h || 1;
    return { idle: (i * i) / e, mid: (m * m) / e, high: (h * h) / e };
  }

  async _attachSampleLayer(graph, kind, file, opts = {}) {
    if (!graph || graph.silent || !file || !this._ctx) return;
    const buf = await this._loadBuffer(file);
    if (!buf || graph.silent || this._voiceGraph !== graph) return;
    try {
      const ctx = this._ctx;
      // Eski katman varsa yumuşak kapat
      const prev = graph.nodes?.[kind];
      if (prev?.src) {
        try {
          const t = ctx.currentTime;
          prev.gain.gain.cancelScheduledValues(t);
          prev.gain.gain.setValueAtTime(Math.max(0.0001, prev.gain.gain.value), t);
          prev.gain.gain.linearRampToValueAtTime(0.0001, t + 0.22);
          setTimeout(() => {
            try {
              prev.src.stop();
            } catch (_) {}
            try {
              prev.src.disconnect();
            } catch (_) {}
          }, 260);
        } catch (_) {}
      }

      const src = ctx.createBufferSource();
      src.buffer = buf;
      src.loop = true;
      // Tam buffer loop — kenar kesme tıklama/kesilme yapar
      src.loopStart = 0;
      src.loopEnd = Math.max(0.05, buf.duration);
      const filter = ctx.createBiquadFilter();
      filter.type = "lowpass";
      filter.frequency.value = opts.filterHz || 1800;
      if (opts.filterQ != null) filter.Q.value = opts.filterQ;
      const gain = ctx.createGain();
      const t0 = ctx.currentTime;
      gain.gain.setValueAtTime(0.0001, t0);
      src.connect(filter);
      filter.connect(gain);
      gain.connect(graph.bus);
      src.start(t0);
      graph.sources.push(src);
      graph.nodes[kind] = { src, filter, gain };
      // Soft apply — click/gap üretmeden katmanı devreye al
      if (this._voiceGraph === graph && this._running) {
        this._applyParams(this._smoothKmh, false);
      }
    } catch (e) {
      console.warn("Sample layer attach failed", kind, e);
    }
  }

  _disposeGraph(graph) {
    if (!graph || graph.silent) return;
    graph.silent = true; // async WAV attach’i iptal et
    for (const s of graph.sources || []) {
      try {
        s.stop();
      } catch (_) {}
      try {
        s.disconnect();
      } catch (_) {}
    }
    try {
      graph.bus?.disconnect();
    } catch (_) {}
  }

  /* ---------- rAF lerp + AudioParam ---------- */

  _startRaf() {
    if (this._raf != null) return;
    const tick = (ts) => {
      if (!this._running) {
        this._raf = null;
        return;
      }
      const rising = this._targetKmh >= this._smoothKmh - 0.05;
      const lerp = rising ? this.LERP_UP : this.LERP_DOWN;
      this._smoothKmh += (this._targetKmh - this._smoothKmh) * lerp;
      if (Math.abs(this._targetKmh - this._smoothKmh) < 0.05) {
        this._smoothKmh = this._targetKmh;
      }
      if (this._targetKmh < 0.35 && this._smoothKmh < 0.6) this._smoothKmh = 0;

      const lag = this._targetKmh - this._smoothKmh;
      const powerKw = this._lastPowerKw;
      let targetThrottle = this._throttleFromAccel(this._extAccel);
      let targetRegen = this._regenFromAccel(this._extAccel);
      if (Number.isFinite(powerKw) && Math.abs(powerKw) > 8) {
        if (powerKw > 0) {
          targetThrottle = Math.max(targetThrottle * 0.72, Math.min(1, powerKw / 220));
        } else {
          targetRegen = Math.max(targetRegen * 0.65, Math.min(1, -powerKw / 80));
        }
      } else if (Number.isFinite(powerKw) && Math.abs(powerKw) > 1) {
        if (powerKw > 0) targetThrottle = Math.max(targetThrottle, Math.min(1, powerKw / 220));
        else targetRegen = Math.max(targetRegen, Math.min(1, -powerKw / 80));
      }
      // Gaz hızlı; lift / regen yavaş (coast → cruise hum)
      this._throttleLoad +=
        (targetThrottle - this._throttleLoad) *
        (targetThrottle > this._throttleLoad ? 0.72 : 0.1);
      this._regenLoad +=
        (targetRegen - this._regenLoad) *
        (targetRegen > this._regenLoad ? 0.52 : 0.18);
      this._brakeLoad = Math.max(this._regenLoad * 0.9, this._regenFromAccel(this._extAccel) * 0.55);

      // Drive.app: Speed = Pitch (primary); Load only nudges revs
      const speedRpm = this._norm(this._smoothKmh);
      const targetRpm = Math.max(
        0.08,
        Math.min(
          1,
          speedRpm * 0.82 +
            this._throttleLoad * 0.14 +
            this._regenLoad * 0.28
        )
      );
      const rpmRise = targetRpm >= this._engineRpm - 0.01;
      const rpmLerp = rpmRise ? 0.28 : 0.08;
      this._engineRpm += (targetRpm - this._engineRpm) * rpmLerp;

      const now = typeof ts === "number" ? ts : performance.now();
      const cabin = this._cabinSmooth();
      const busy =
        this._throttleLoad > 0.04 ||
        this._regenLoad > 0.04 ||
        this._brakeLoad > 0.04 ||
        Math.abs(this._extAccel) > 0.12 ||
        Math.abs(lag) > 0.2;
      const gap = cabin ? (busy ? 20 : 34) : busy ? 14 : 26;
      if (now - (this._lastApplyMs || 0) >= gap) {
        this._lastApplyMs = now;
        this._applyParams(this._smoothKmh, false);
      }
      this._raf = requestAnimationFrame(tick);
    };
    this._raf = requestAnimationFrame(tick);
  }

  _stopRaf() {
    if (this._raf != null) {
      cancelAnimationFrame(this._raf);
      this._raf = null;
    }
  }

  /**
   * AudioParam güncelle — kesintisiz akış.
   * Not: force dışı her tick cancelScheduledValues yapmak micro-gap üretebilir.
   */
  _targetParam(param, value, tau = this.TAU, force = false, { isRate = false } = {}) {
    if (!param || !this._ctx) return;
    const v = Number(value);
    if (!Number.isFinite(v)) return;
    const cabin = this._cabinSmooth();
    const rateMin = this.RATE_MIN || 0.85;
    const rateMax = this.RATE_MAX || 1.3;
    const safe = isRate
      ? Math.max(rateMin, Math.min(rateMax, v))
      : Math.max(0.0001, v);
    const t = this._ctx.currentTime;
    const minTau = cabin ? 0.028 : 0.016;
    try {
      let cur = safe;
      try {
        cur = param.value;
      } catch (_) {}
      if (!Number.isFinite(cur)) cur = safe;
      const delta = Math.abs(safe - cur);
      if (!force && delta < (isRate ? 0.006 : 0.0005)) return;

      if (force) {
        param.cancelScheduledValues(t);
        param.setValueAtTime(cur, t);
      }
      if (force || delta > Math.max(safe, cur) * 1.8 + (isRate ? 0.1 : 0.05)) {
        const dur = force
          ? cabin
            ? 0.04
            : 0.022
          : Math.min(cabin ? 0.14 : 0.1, Math.max(minTau, (tau || 0.05) * 2.2));
        if (force) {
          param.linearRampToValueAtTime(safe, t + dur);
        } else {
          // force dışı: geçmiş planı bozma; hedefe yumuşak yaklaş
          param.setTargetAtTime(safe, t, Math.max(minTau, (tau || 0.05) * 0.9));
        }
        if (force && !cabin) {
          try {
            param.value = safe;
          } catch (_) {}
        }
        return;
      }
      param.setTargetAtTime(safe, t, Math.max(minTau, tau || 0.05));
    } catch (_) {
      try {
        param.value = safe;
      } catch (__) {}
    }
  }

  _targetRate(param, value, tau, force = false) {
    this._targetParam(param, value, tau, force, { isRate: true });
  }

  _norm(kmh) {
    return Math.min(1, Math.max(0, kmh / Math.max(40, this._maxKmh)));
  }

  /** Vites yalnızca gerçek motor (ice) seslerinde; EV/fx tek sürekli yükseliş */
  _effectiveGears(p) {
    if (!p?.ice) return 1;
    return Math.max(1, p.gears || 1);
  }

  _gearFromNorm(norm, profileOrGears) {
    const p =
      profileOrGears && typeof profileOrGears === "object"
        ? profileOrGears
        : { gears: profileOrGears, ice: (profileOrGears || 1) > 1 };
    const g = this._effectiveGears(p);
    const n = Math.max(0, Math.min(1, Number(norm) || 0));

    if (g <= 1) {
      // EV: Tek oran - logaritmik hızlanma eğrisi (Porsche Taycan / Tesla Plaid)
      // İlk kalkışta (0-50 km/s) hissedilir tırmanış, yüksek hızda oturan aerodinamik ton
      const evCurve = Math.pow(n, 0.82);
      return { gear: 1, rpm: 0.1 + evCurve * 0.9 };
    }

    // Hyundai Ioniq 5 N e-Shift Aşamalı Vites Dağılımı (Progressive Dual-Clutch):
    // Alt vitesler (1 ve 2) şehir içi seri kalkış için dar; üst vitesler uzun oranlıdır
    let splits;
    if (g === 7) {
      splits = [0.18, 0.33, 0.49, 0.67, 0.83, 0.94, 1.0];
    } else if (g === 6) {
      splits = [0.20, 0.37, 0.55, 0.73, 0.88, 1.0];
    } else if (g === 8) {
      splits = [0.15, 0.28, 0.42, 0.57, 0.72, 0.84, 0.94, 1.0];
    } else {
      splits = Array.from({ length: g }, (_, i) => (i + 1) / g);
    }

    let slot = 0;
    while (slot < g - 1 && n > splits[slot]) {
      slot++;
    }

    const prevSplit = slot === 0 ? 0 : splits[slot - 1];
    const nextSplit = splits[slot];
    const range = Math.max(0.01, nextSplit - prevSplit);
    const local = Math.max(0, Math.min(1, (n - prevSplit) / range));

    // Her viteste 2000 RPM tabanından 7800 RPM kesiciye doğru devir tırmanışı
    const rpm = 0.24 + local * 0.74;
    return { gear: slot + 1, rpm };
  }

  _applyParams(kmh, force) {
    const graph = this._voiceGraph;
    if (!graph || graph.silent || !this._ctx) {
      this._gearInfo = { gear: 0, rpm: 0.12 };
      this._lastGear = 0;
      this._shiftKick = 0;
      this._shiftCutUntil = 0;
      return;
    }
    const p = graph.profile;
    const n = graph.nodes;
    if (!p || !n?.idle || !n?.mid || !n?.body) {
      console.warn("[etubu-audio] applyParams: incomplete graph");
      return;
    }
    const load = Math.max(0, Math.min(1, this._throttleLoad || 0));
    const regen = Math.max(0, Math.min(1, this._regenLoad || 0));
    const brake = Math.max(0, Math.min(1, this._brakeLoad || 0));
    const rising =
      this._targetKmh >= kmh - 0.1 || load > regen + 0.05 || load > brake + 0.05;
    const cabin = this._cabinSmooth();
    const tauBase = rising ? this.TAU_UP : this.TAU_DOWN;
    const tau = force ? (cabin ? 0.032 : 0.02) : cabin ? Math.max(0.032, tauBase) : tauBase;
    const rateTau = force ? tau : rising ? tau : tau * 1.25;
    const norm = this._norm(kmh);
    const feelNorm = Math.max(0, Math.min(1, norm));

    // Vites ve Devir Hesabı (Hyundai Ioniq 5 N e-Shift DCT Mantığı)
    const gearInfo = this._gearFromNorm(feelNorm, p);
    let rpm = gearInfo.rpm;

    if (p.ice) {
      if (this._lastGear > 0 && gearInfo.gear !== this._lastGear) {
        if (gearInfo.gear > this._lastGear) {
          // Vites Yükseltme (Up-shift): 75ms mikro tork kesintisi (shift cut) + egzoz patırtısı
          this._shiftKick = cabin ? 0.24 : 0.35;
          this._shiftCutUntil = performance.now() + 75;
        } else {
          // Vites Düşürme (Down-shift): Ara gazı (rev-match)
          this._shiftKick = cabin ? 0.18 : 0.26;
        }
      }
      this._lastGear = gearInfo.gear;
      this._shiftKick = Math.max(0, (this._shiftKick || 0) * (force ? 0 : 0.86));
      if (this._shiftKick > 0.02) {
        rpm = Math.max(0.12, rpm - this._shiftKick * 0.24);
      }
    } else {
      this._lastGear = 0;
      this._shiftKick = 0;
    }

    this._gearInfo = { gear: p.ice ? gearInfo.gear : 1, rpm };

    const vol = Math.max(0.16, this._volume) * (p.master || 1) * (cabin ? 1.05 : 1.2);
    const floor = this.AUDIBLE_FLOOR * vol;

    // —— SÜRÜŞ YÜKÜ VE SABİT HIZ UĞULTU ÖNLEME (HYUNDAI & PORSCHE MODELİ) ——
    // 1. Sabit Hızda Süzülme (Cruising):
    // Araç hareket halindeyse (feelNorm > 0.06) ve ne sert gaz ne sert fren varsa
    const isCruising = feelNorm > 0.06 && load < 0.18 && regen < 0.18;
    
    // Sabit hızda ses seviyesi %35-40 geri çekilir (uğultu / drone engelleme)
    const cruiseAttenuation = isCruising ? Math.max(0.60, 0.62 + load * 2.1) : 1.0;

    // 2. Hızlanırken Gaz Yükü (Throttle Acceleration Boost):
    // Gaza basıldığında motor anında yırtıcılaşır (+20% - +40%)
    const accelBoost = 1.0 + load * (cabin ? 0.28 : 0.42);

    // 3. Vites Atma Anında Mikro Tork Kesintisi (DCT Shift Cut):
    const isShiftCut = this._shiftCutUntil && performance.now() < this._shiftCutUntil;
    const shiftCutDuck = isShiftCut ? 0.45 : 1.0;

    // 4. Logaritmik Hız Hacmi (0-50 km/s kalkış doygunluğu):
    const speedCurve = Math.pow(feelNorm, 0.74);
    const speedVol = 0.20 + speedCurve * 0.80;

    // Toplam dinamik ses gücü (Punch):
    const punch = speedVol * accelBoost * cruiseAttenuation * shiftCutDuck;

    const hasSample = !!(n.drive || n.drive2 || n.loopIdle || n.loopMid || n.loopHigh || n.regen);
    const sampleLed = !!p.sampleLed && hasSample;
    const oscScale = sampleLed ? (cabin ? (feelNorm < 0.08 ? 0.35 : 0.22) : feelNorm < 0.08 ? 0.85 : 0.55) : 1;

    // Rölanti dururken etkin, hızlandıkça yerini sürüş sesine bırakır
    const idleW = Math.max(0, 1 - feelNorm * 2.5);
    const midW = Math.min(1, Math.max(0, feelNorm * 2.2));

    const idleHz = p.idleHz * (0.9 + rpm * 0.45 + load * 0.06);
    const midHz = p.midHz + rpm * p.midSpan;
    const bodyHz = idleHz * 2.05;
    const bodyMul = (p.bodyMul != null ? p.bodyMul : 0.2) * oscScale;
    const harmMul = (p.harmMul != null ? p.harmMul : 0.08) * oscScale * (cabin ? 0.45 : 1);
    const subMul = (p.subMul != null ? p.subMul : 0.1) * (cabin ? 0.85 : 1);

    this._targetParam(n.idle.osc.frequency, idleHz, tau, force);
    this._targetParam(n.mid.osc.frequency, midHz, tau, force);
    this._targetParam(n.body.osc.frequency, bodyHz, tau, force);

    // —— DİNAMİK ALÇAK GEÇİREN FİLTRE (PORSCHE TAYCAN PESS MODELİ) ——
    // Hızlanırken boğaz 2800-3400 Hz'e açılır (yırtıcı kükreme)
    // Sabit hızda ve süzülmede 950-1200 Hz'e kapanır (uğultusuz kadife ton)
    const baseFilt = p.filterHz || 1200;
    const dynFilterCutoff = isCruising
      ? Math.min(cabin ? 1600 : 2000, baseFilt * (0.65 + feelNorm * 0.35))
      : Math.min(cabin ? 2800 : 3600, baseFilt * (0.75 + feelNorm * 0.65 + load * 0.75));

    this._targetParam(
      n.idle.filter.frequency,
      Math.min(dynFilterCutoff, baseFilt * (0.35 + feelNorm * 0.3)),
      tau,
      force
    );
    this._targetParam(
      n.mid.filter.frequency,
      Math.min(dynFilterCutoff, baseFilt * (0.55 + rpm * 0.55 + load * 0.2)),
      tau,
      force
    );

    let idleGain = Math.max(floor * 0.55, idleW * (p.idleGain || 0.08) * vol * 1.25 * oscScale);
    let midGain = Math.max(
      midW > 0.02 ? floor * 0.35 : 0.0001,
      midW * (p.midGain || 0.22) * vol * punch * oscScale
    );
    if (feelNorm < 0.05 && load < 0.05 && regen < 0.05) {
      idleGain = Math.max(idleGain, floor * 0.95, 0.1 * vol);
    }

    this._targetParam(n.idle.gain.gain, idleGain, tau, force);
    this._targetParam(n.mid.gain.gain, midGain, tau, force);
    this._targetParam(
      n.body.gain.gain,
      Math.max(0.0001, (0.03 + midW * 0.08 + load * 0.05 + regen * 0.04) * vol * bodyMul * (isCruising ? 0.75 : 1)),
      tau,
      force
    );

    if (n.harm) {
      this._targetParam(n.harm.osc.frequency, midHz * 1.4 + load * 20, tau, force);
      this._targetParam(
        n.harm.filter.frequency,
        Math.min(dynFilterCutoff, baseFilt * (0.85 + rpm * 0.25)),
        tau,
        force
      );
      this._targetParam(
        n.harm.gain.gain,
        Math.max(0.0001, midW * harmMul * vol * punch),
        tau,
        force
      );
    }

    if (n.sub) {
      this._targetParam(
        n.sub.osc.frequency,
        Math.max(28, idleHz * 0.48 + load * 6 + regen * 4),
        tau,
        force
      );
      this._targetParam(
        n.sub.gain.gain,
        Math.max(0.0001, (0.04 + midW * 0.1 + load * 0.12 + regen * 0.08) * vol * subMul),
        tau,
        force
      );
    }

    if (n.wind) {
      this._targetParam(n.wind.gain.gain, 0.0001, tau, force);
    }
    if (n.whistle) this._targetParam(n.whistle.gain.gain, 0.0001, 0.05, true);
    if (n.emf) this._targetParam(n.emf.gain.gain, 0.0001, 0.05, true);

    if (n.road) this._targetParam(n.road.gain.gain, 0.0001, tau, force);

    // Playback rate — Vitesli motorlarda devirle birebir senkron düşüş/tırmanış, EV'de kesintisiz logaritmik
    const rateRaw = p.ice
      ? (0.64 + rpm * 0.86 + load * 0.06)
      : (0.72 + Math.pow(feelNorm, 0.78) * 0.92 + load * 0.06);
    const rate = Math.max(this.RATE_MIN || 0.70, Math.min(this.RATE_MAX || 1.80, rateRaw));

    const bands = graph.bands || this._resolveLoopBands(p);
    const driveDuck = 1 - regen * 0.45;
    const loadPos = Math.max(0, Math.min(1, load * 0.9 + regen * 0.45 + feelNorm * 0.12));
    if (bands && (n.loopIdle || n.loopMid || n.loopHigh)) {
      const w = this._bandWeights(kmh, bands.edges, loadPos);
      const applyBand = (node, weight, baseGain, rateMul) => {
        if (!node?.src) return;
        const level = Math.max(
          weight > 0.02 ? floor * 0.25 : 0.0001,
          weight * baseGain * vol * punch * driveDuck * (cabin ? 1 : 1.05)
        );
        this._targetParam(node.gain.gain, level, tau, force);
        this._targetRate(node.src.playbackRate, rate * rateMul, rateTau, force);
        this._targetParam(
          node.filter.frequency,
          Math.min(dynFilterCutoff, (p.filterHz || 1200) * (0.65 + feelNorm * 0.55 + load * 0.04)),
          tau,
          force
        );
      };
      applyBand(n.loopIdle, w.idle, bands.gains.idle, 0.97);
      applyBand(n.loopMid, w.mid, bands.gains.mid, 1.0);
      applyBand(n.loopHigh, w.high, bands.gains.high, 1.03);
      if (n.drive) this._targetParam(n.drive.gain.gain, 0.0001, tau, force);
      if (n.drive2) this._targetParam(n.drive2.gain.gain, 0.0001, tau, force);
    } else {
      if (n.drive) {
        const driveLevel = Math.max(
          floor * 0.25,
          (idleW * 0.15 + midW * 0.95 + feelNorm * 0.35) *
            (p.driveGain || 0.5) *
            vol *
            punch *
            driveDuck *
            (cabin ? 1.0 : 1.05)
        );
        this._targetParam(n.drive.gain.gain, driveLevel, tau, force);
        this._targetRate(n.drive.src.playbackRate, rate, rateTau, force);
        this._targetParam(
          n.drive.filter.frequency,
          Math.min(dynFilterCutoff, (p.filterHz || 1200) * (0.7 + feelNorm * 0.55 + load * 0.04)),
          tau,
          force
        );
      }

      if (n.drive2) {
        const d2 = Math.max(
          floor * 0.15,
          (idleW * 0.1 + midW * 0.8 + feelNorm * 0.3) *
            (p.drive2Gain || 0.25) *
            vol *
            punch *
            driveDuck *
            (cabin ? 0.95 : 1.02)
        );
        this._targetParam(n.drive2.gain.gain, d2, tau, force);
        this._targetRate(n.drive2.src.playbackRate, rate * 0.98 + 0.01, rateTau, force);
        this._targetParam(
          n.drive2.filter.frequency,
          Math.min(dynFilterCutoff, (p.filterHz || 1200) * (0.65 + feelNorm * 0.5)),
          tau,
          force
        );
      }
    }

    // Regen layer — crossfade in with negative power
    if (n.regen?.src) {
      const regenLevel = Math.max(
        regen > 0.04 ? floor * 0.4 : 0.0001,
        regen * (p.regenGain || 0.62) * vol * (1 + regen * 0.35) * (cabin ? 0.95 : 1.05)
      );
      this._targetParam(n.regen.gain.gain, regenLevel, tau, force);
      this._targetRate(
        n.regen.src.playbackRate,
        Math.max(this.RATE_MIN || 0.72, Math.min(this.RATE_MAX || 1.55, rate * 0.96 + regen * 0.08)),
        rateTau,
        force
      );
      this._targetParam(
        n.regen.filter.frequency,
        Math.min(cabin ? 2000 : 2400, (p.filterHz || 1200) * (0.7 + rpm * 0.3 + regen * 0.15)),
        tau,
        force
      );
    }

    this._syncHtmlFallbackGain();
  }
}

const AudioEngine = new EtubuAudioEngine();

if (typeof module !== "undefined") module.exports = AudioEngine;
