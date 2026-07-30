/**
 * Çok kaynaklı hız füzyonu:
 * 1) GPS speed  2) Haversine türevi  3) İvmeölçer  4) Trend tahmini
 * Hızlanma anında sesin gecikmemesi için ivme öncelikli.
 */
const GpsTracker = (() => {
  const MPS_TO_KMH = 3.6;
  const FREE_TRIAL_KM = 5;

  let watchId = null;
  let watchIdB = null;
  let onUpdate = null;
  let onKmAccumulated = null;
  let motionHandler = null;

  let displayKmh = 0;
  let fusedKmh = 0;
  let gpsKmh = 0;
  let deriveKmh = 0;
  let accelBoostKmh = 0;
  let trendKmhPerSec = 0;
  let lastFixMs = null;
  let lastEmitMs = 0;
  let sensitivity = 1.24; // UI %20 → SENS_MIN + 0.2*(SENS_MAX-SENS_MIN)
  let totalKm = 0;
  let lastKmSampleMs = null;
  let predictionTimer = null;
  let lastLat = null;
  let lastLng = null;
  let headingDeg = null;
  let accuracyM = null;
  let lastBearingLat = null;
  let lastBearingLng = null;

  // İvme kalibrasyonu
  let forwardAxis = null; // 'x' | 'y' | 'z'
  let forwardSign = 1;
  let smoothAx = 0, smoothAy = 0, smoothAz = 0;
  let lastMotionMs = 0;

  // Simetrik yumuşatma: hızlanma = yavaşlama (ses anında takip)
  const EMA_UP = 0.05;
  const EMA_DOWN = 0.05;
  const TREND_ALPHA = 0.28;
  const PREDICT_MAX_SEC = 1.25;
  const ACCEL_TO_KMH = 3.6;
  const ACCEL_DECAY = 0.7;
  /** Durma eşiği (histerezis: gir / çık ayrı) */
  const STOP_ENTER_KMH = 2.4;
  const STOP_EXIT_KMH = 4.0;
  const MOTION_GATE_KMH = 3.2;
  const MAX_RISE_KMH_S = 70;
  const MAX_FALL_KMH_S = 70;
  /** Kısa GPS sıçraması durmayı bozmasın */
  const EXIT_HOLD_MS = 520;
  /** Bu altında gösterge ve ses 0 */
  const HARD_ZERO_KMH = 2.4;

  let speedSource = "gps"; // gps | obd
  let obdRpm = null;
  let obdKmh = 0;
  let obdLastMs = 0;
  let stationaryLatch = true;
  let exitHoldUntil = 0;
  let lastBlendMs = 0;

  function loadTotalKm() {
    try {
      const stored = localStorage.getItem("etubu_total_km");
      totalKm = stored ? parseFloat(stored) : 0;
    } catch (_) {
      totalKm = totalKm || 0;
    }
    if (!Number.isFinite(totalKm) || totalKm < 0) totalKm = 0;
    return totalKm;
  }

  function saveTotalKm() {
    try {
      localStorage.setItem("etubu_total_km", String(totalKm.toFixed(3)));
    } catch (_) {}
    // Ephemeral (Tesla): sunucuya yazma — cihaz id de kalıcı değil
    if (typeof CarBrowser !== "undefined" && CarBrowser.isEphemeral()) {
      return;
    }
    if (typeof Identity !== "undefined") {
      Identity.scheduleSync?.(totalKm);
      Identity.refreshAccountUi?.();
    }
  }

  function setTotalKm(km) {
    totalKm = Math.max(0, Number(km) || 0);
    saveTotalKm();
    return totalKm;
  }

  function resetTotalKm() {
    return setTotalKm(0);
  }

  function setSensitivity(v) {
    sensitivity = Math.max(1, Math.min(2.2, v));
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
    const φ1 = (lat1 * Math.PI) / 180;
    const φ2 = (lat2 * Math.PI) / 180;
    const Δλ = ((lon2 - lon1) * Math.PI) / 180;
    const y = Math.sin(Δλ) * Math.cos(φ2);
    const x = Math.cos(φ1) * Math.sin(φ2) - Math.sin(φ1) * Math.cos(φ2) * Math.cos(Δλ);
    return ((Math.atan2(y, x) * 180) / Math.PI + 360) % 360;
  }

  function updateHeadingFromFix(lat, lng, reportedHeading, speedKmh) {
    if (reportedHeading != null && Number.isFinite(reportedHeading) && reportedHeading >= 0 && speedKmh > 2) {
      headingDeg = reportedHeading;
      lastBearingLat = lat;
      lastBearingLng = lng;
      return;
    }
    if (lastBearingLat != null && lastBearingLng != null) {
      const dist = haversineM(lastBearingLat, lastBearingLng, lat, lng);
      if (dist > 4) {
        headingDeg = bearingDeg(lastBearingLat, lastBearingLng, lat, lng);
        lastBearingLat = lat;
        lastBearingLng = lng;
      }
    } else {
      lastBearingLat = lat;
      lastBearingLng = lng;
    }
  }

  function isLikelyStationary() {
    if (speedSource === "obd") return false;
    const now = Date.now();
    const signal = Math.max(gpsKmh, deriveKmh * 0.85);
    if (stationaryLatch) {
      if (signal >= STOP_EXIT_KMH || trendKmhPerSec > 2.2) {
        if (!exitHoldUntil) exitHoldUntil = now + EXIT_HOLD_MS;
        if (now >= exitHoldUntil) {
          stationaryLatch = false;
          exitHoldUntil = 0;
        }
      } else {
        exitHoldUntil = 0;
      }
    } else if (signal < STOP_ENTER_KMH && Math.abs(trendKmhPerSec) < 1.0) {
      stationaryLatch = true;
      exitHoldUntil = 0;
    }
    return stationaryLatch;
  }

  function smoothToward(current, target, dtSec) {
    const rising = target > current;
    const alpha = rising ? EMA_UP : EMA_DOWN;
    let next = alpha * current + (1 - alpha) * target;
    const maxStep = (rising ? MAX_RISE_KMH_S : MAX_FALL_KMH_S) * Math.max(0.016, dtSec);
    const delta = next - current;
    if (Math.abs(delta) > maxStep) next = current + Math.sign(delta) * maxStep;
    return Math.max(0, next);
  }

  function clampStationaryDisplay() {
    if (!isLikelyStationary()) return;
    accelBoostKmh *= 0.35;
    if (accelBoostKmh < 0.2) accelBoostKmh = 0;
    trendKmhPerSec *= 0.4;
    // Hızlı sönüm + sert sıfır — düşük hızda titreme / crawl yok
    displayKmh *= 0.48;
    if (displayKmh < HARD_ZERO_KMH) displayKmh = 0;
    fusedKmh = displayKmh;
    gpsKmh = Math.min(gpsKmh, displayKmh);
    deriveKmh = Math.min(deriveKmh, displayKmh);
  }

  function fuseAndEmit(now) {
    const dtSec = lastBlendMs ? Math.min(0.25, (now - lastBlendMs) / 1000) : 0.05;
    lastBlendMs = now;
    const obdFresh = speedSource === "obd" && now - obdLastMs < 1800;

    // OBD + GPS hibrit: OBD anlık, GPS doğrulama/stabilite.
    if (obdFresh) {
      const gpsRef = Math.max(0, Math.max(gpsKmh, deriveKmh * 0.92));
      const gap = Math.abs(obdKmh - gpsRef);
      const obdW = gap > 22 ? 0.84 : 0.72;
      fusedKmh = Math.max(0, obdKmh * obdW + gpsRef * (1 - obdW));
      displayKmh = smoothToward(displayKmh, fusedKmh, dtSec);
      if (fusedKmh < HARD_ZERO_KMH && displayKmh < HARD_ZERO_KMH + 0.5) displayKmh = 0;
      accumulateKm(now);
      emit();
      return;
    }

    if (isLikelyStationary()) {
      clampStationaryDisplay();
      accumulateKm(now);
      emit();
      return;
    }

    // Ağırlıklı füzyon: ivme boost hızlanmada öne çıkar
    const accelAbs = Math.abs(accelBoostKmh);
    const wGps = 0.34;
    const wDer = deriveKmh > 1 ? 0.28 : 0.16;
    const wAcc = Math.min(0.55, 0.22 + accelAbs / 28);
    const wSum = wGps + wDer + wAcc;

    let blend =
      (gpsKmh * wGps + deriveKmh * wDer + Math.max(0, gpsKmh + accelBoostKmh) * wAcc) /
      wSum;

    // Hızlanırken üst değeri tercih et — gaz ile ses/gösterge aynı anda
    if (trendKmhPerSec > 0.8 || accelBoostKmh > 0.5) {
      blend = Math.max(
        blend,
        gpsKmh,
        deriveKmh,
        gpsKmh + accelBoostKmh * 1.05
      );
    }

    blend = Math.max(0, blend * sensitivity);
    fusedKmh = blend;
    displayKmh = smoothToward(displayKmh, fusedKmh, dtSec);
    // Crawl bölgesi: göstergeyi 0'a kilitle
    if (fusedKmh < HARD_ZERO_KMH && displayKmh < HARD_ZERO_KMH + 0.8) {
      displayKmh = 0;
      fusedKmh = 0;
    }

    accumulateKm(now);
    emit();
  }

  /** OBD / harici hız — GPS yerine birincil kaynak */
  function setExternalSpeed(kmh, meta = {}) {
    const now = Date.now();
    const next = Math.max(0, Number(kmh) || 0);
    if (obdLastMs) {
      const dt = Math.max(0.02, (now - obdLastMs) / 1000);
      const trend = (next - obdKmh) / dt;
      trendKmhPerSec = TREND_ALPHA * trendKmhPerSec + (1 - TREND_ALPHA) * trend;
    } else if (lastFixMs) {
      const dt = Math.max(0.02, (now - lastFixMs) / 1000);
      const trend = (next - gpsKmh) / dt;
      trendKmhPerSec = TREND_ALPHA * trendKmhPerSec + (1 - TREND_ALPHA) * trend;
    }
    obdKmh = next;
    obdLastMs = now;
    accelBoostKmh = 0;
    speedSource = meta.source || "obd";
    if (meta.rpm != null) obdRpm = meta.rpm;
    if (!lastFixMs) lastFixMs = now;
    fuseAndEmit(now);
  }

  function clearExternalSpeed() {
    speedSource = "gps";
    obdRpm = null;
    obdKmh = 0;
    obdLastMs = 0;
  }

  function getSpeedSource() {
    return speedSource;
  }

  function applyGpsReading(speedMps, coords, timestamp, source) {
    const now = timestamp || Date.now();
    let reported = Math.max(0, (speedMps == null || speedMps < 0 ? 0 : speedMps) * MPS_TO_KMH);
    let derived = 0;

    if (coords && coords.prevLat != null && lastFixMs) {
      const dt = (now - lastFixMs) / 1000;
      if (dt > 0.04 && dt < 6) {
        const dist = haversineM(
          coords.lat,
          coords.lng,
          coords.prevLat,
          coords.prevLng
        );
        derived = (dist / dt) * MPS_TO_KMH;
        // Anlık türevi kaydet
        if (derived > 0.3) deriveKmh = derived;
      }
    }

    // Düşük hız + kötü fix: GPS raporunu bastır (park/trafikte hayalet hız)
    const accuracy = coords?.accuracy != null ? Number(coords.accuracy) : 25;
    const poorFix = accuracy > 28;
    if (poorFix && reported < 4.5) {
      reported *= Math.max(0.15, 1 - (accuracy - 28) / 80);
    }

    // İki GPS kaynağını birleştir
    let instant = reported;
    if (derived > 0.5) {
      if (reported < 1) instant = derived;
      else instant = reported * 0.55 + derived * 0.45;
    }
    if (reported < 2.2 && derived < 2.8) {
      instant = Math.min(instant, Math.max(derived * 0.9, reported * 0.55));
    }
    if (reported < 1.2 && derived < 2.2 && poorFix) {
      instant = Math.max(reported * 0.4, derived * 0.3);
    }
    if (instant < STOP_ENTER_KMH && derived < STOP_EXIT_KMH) {
      deriveKmh = deriveKmh * 0.78 + instant * 0.22;
    } else if (derived > 0.3) {
      deriveKmh = deriveKmh * 0.4 + derived * 0.6;
    }

    if (lastFixMs && instant >= 0) {
      const dt = Math.max(0.04, (now - lastFixMs) / 1000);
      const trend = (instant - gpsKmh) / dt;
      trendKmhPerSec = TREND_ALPHA * trendKmhPerSec + (1 - TREND_ALPHA) * trend;

      // GPS ile doğrulanmış hızlanma → ileri ekseni kalibre et
      if (trend > 2.5 && !forwardAxis) {
        calibrateForwardFromTrend();
      }
    }

    gpsKmh = instant;
    if (source !== "watchB" || now - (lastFixMs || 0) > 80) {
      lastFixMs = now;
    }

    fuseAndEmit(now);
  }

  function calibrateForwardFromTrend() {
    const mags = [
      { a: "x", v: Math.abs(smoothAx) },
      { a: "y", v: Math.abs(smoothAy) },
      { a: "z", v: Math.abs(smoothAz) },
    ].sort((p, q) => q.v - p.v);
    if (mags[0].v < 0.4) return;
    forwardAxis = mags[0].a;
    const raw =
      forwardAxis === "x" ? smoothAx : forwardAxis === "y" ? smoothAy : smoothAz;
    forwardSign = raw >= 0 ? 1 : -1;
  }

  function onMotion(ev) {
    const now = Date.now();
    const dt = lastMotionMs ? Math.min(0.05, (now - lastMotionMs) / 1000) : 0.016;
    lastMotionMs = now;

    const acc = ev.accelerationIncludingGravity || ev.acceleration;
    if (!acc) return;

    const ax = acc.x || 0;
    const ay = acc.y || 0;
    const az = acc.z || 0;
    const a = 0.35;
    smoothAx = a * ax + (1 - a) * smoothAx;
    smoothAy = a * ay + (1 - a) * smoothAy;
    smoothAz = a * az + (1 - a) * smoothAz;

    // İleri eksen yoksa genlikten geçici sinyal
    let forward = 0;
    if (forwardAxis) {
      const raw =
        forwardAxis === "x" ? smoothAx : forwardAxis === "y" ? smoothAy : smoothAz;
      forward = raw * forwardSign;
    } else {
      // Gravity-ish z'yi çıkar, yatay genlik
      const horiz = Math.sqrt(smoothAx * smoothAx + smoothAy * smoothAy);
      forward = horiz - 0.15;
    }

    // m/s² → anlık hız boost (hızlanma anında GPS'ten önce)
    if (speedSource === "obd") return;
    // Dururken ivmeölçer hayalet hız üretmesin
    if (gpsKmh < MOTION_GATE_KMH && deriveKmh < MOTION_GATE_KMH) {
      accelBoostKmh *= 0.55;
      if (accelBoostKmh < 0.4) accelBoostKmh = 0;
      return;
    }
    if (forward > 0.28) {
      accelBoostKmh += forward * ACCEL_TO_KMH * dt * 3.6;
      accelBoostKmh = Math.min(55, accelBoostKmh);
      if (trendKmhPerSec < forward * 4) {
        trendKmhPerSec = trendKmhPerSec * 0.4 + forward * 2.8 * 0.6;
      }
      fuseAndEmit(now);
    } else if (forward < -0.5) {
      // Fren — boost'u hızlı düşür
      accelBoostKmh *= 0.65;
      fuseAndEmit(now);
    }
  }

  function predictStep() {
    const now = Date.now();
    accelBoostKmh *= ACCEL_DECAY;

    if (!lastFixMs) {
      accelBoostKmh = 0;
      if (displayKmh > 0) {
        displayKmh = 0;
        fusedKmh = 0;
        emit();
      }
      return;
    }

    if (isLikelyStationary()) {
      clampStationaryDisplay();
      accumulateKm(now);
      emit();
      return;
    }

    // İvme gürültüsüyle hayalet hız üretme — GPS yoksa tahmin yapma
    if (accelBoostKmh < 1.2 && gpsKmh < HARD_ZERO_KMH) {
      clampStationaryDisplay();
      emit();
      return;
    }

    const elapsed = (now - lastFixMs) / 1000;
    if (elapsed > PREDICT_MAX_SEC && accelBoostKmh < 0.5) return;

    const predicted = Math.max(
      0,
      gpsKmh + trendKmhPerSec * Math.min(elapsed, PREDICT_MAX_SEC) * 0.95 + accelBoostKmh * 0.5
    );
    const dtPred = 0.02;
    displayKmh = smoothToward(displayKmh, predicted * sensitivity, dtPred);
    if (displayKmh < HARD_ZERO_KMH) displayKmh = 0;
    accumulateKm(now);
    emit();
  }

  function accumulateKm(now) {
    if (!lastKmSampleMs) {
      lastKmSampleMs = now;
      return;
    }
    const dtH = (now - lastKmSampleMs) / 3600000;
    if (dtH > 0 && displayKmh > 0.5) {
      const delta = displayKmh * dtH;
      totalKm += delta;
      saveTotalKm();
      if (onKmAccumulated) onKmAccumulated(totalKm, delta);
    }
    lastKmSampleMs = now;
  }

  function emit() {
    const now = Date.now();
    // Hız değişirken ~80 Hz (gaz + fren); sabit ~45 Hz
    const changing =
      Math.abs(trendKmhPerSec) > 0.7 || Math.abs(accelBoostKmh) > 0.6;
    if (now - lastEmitMs < (changing ? 12 : 22)) return;
    lastEmitMs = now;
    if (onUpdate) {
      // Ses: ivme yönünde kısa öngörü (hızlanma + yavaşlama simetrik)
      const pred =
        trendKmhPerSec * 0.15 +
        (accelBoostKmh > 0 ? accelBoostKmh * 0.18 : accelBoostKmh * 0.12);
      let audioKmh = displayKmh < HARD_ZERO_KMH ? 0 : Math.max(0, displayKmh + pred);
      onUpdate({
        kmh: displayKmh,
        audioKmh,
        rawKmh: gpsKmh,
        deriveKmh,
        accelBoost: accelBoostKmh,
        trend: trendKmhPerSec,
        totalKm,
        trialRemaining: Math.max(0, FREE_TRIAL_KM - totalKm),
        source: speedSource === "obd" && now - obdLastMs < 1800 ? "hybrid" : speedSource,
        rpm: obdRpm,
        lat: lastLat,
        lng: lastLng,
        heading: headingDeg,
        accuracy: accuracyM,
      });
    }
  }

  async function startMotion() {
    const DM = window.DeviceMotionEvent;
    if (!DM) return;

    try {
      if (typeof DM.requestPermission === "function") {
        const perm = await DM.requestPermission();
        if (perm !== "granted") return;
      }
    } catch (_) {
      return;
    }

    motionHandler = onMotion;
    window.addEventListener("devicemotion", motionHandler, { passive: true });
  }

  let simTimer = null;

  function start(callbacks = {}) {
    // Önceki GPS / demo izlemeyi temizle — çift watch birikmesin
    stop({ silent: true });
    onUpdate = callbacks.onUpdate;
    onKmAccumulated = callbacks.onKmAccumulated;
    loadTotalKm();

    if (!navigator.geolocation) {
      callbacks.onError?.("GPS desteklenmiyor");
      return false;
    }

    let prevLat = null;
    let prevLng = null;

    const onPos = (pos, source) => {
      const c = pos.coords;
      const coords =
        prevLat != null
          ? {
              lat: c.latitude,
              lng: c.longitude,
              prevLat,
              prevLng,
              accuracy: c.accuracy,
            }
          : {
              lat: c.latitude,
              lng: c.longitude,
              prevLat: null,
              prevLng: null,
              accuracy: c.accuracy,
            };
      lastLat = c.latitude;
      lastLng = c.longitude;
      accuracyM = c.accuracy != null ? Number(c.accuracy) : accuracyM;
      const reported =
        c.speed == null || c.speed < 0 ? 0 : c.speed * MPS_TO_KMH;
      updateHeadingFromFix(c.latitude, c.longitude, c.heading, reported);
      prevLat = c.latitude;
      prevLng = c.longitude;
      applyGpsReading(c.speed, coords, pos.timestamp || Date.now(), source);
    };

    watchId = navigator.geolocation.watchPosition(
      (pos) => onPos(pos, "watchA"),
      (err) => callbacks.onError?.(err.message),
      { enableHighAccuracy: true, maximumAge: 0, timeout: 12000 }
    );

    watchIdB = navigator.geolocation.watchPosition(
      (pos) => onPos(pos, "watchB"),
      () => {},
      { enableHighAccuracy: true, maximumAge: 250, timeout: 8000 }
    );

    startMotion();
    predictionTimer = setInterval(predictStep, 33);
    return true;
  }

  function stop(opts = {}) {
    if (watchId != null) {
      navigator.geolocation.clearWatch(watchId);
      watchId = null;
    }
    if (watchIdB != null) {
      navigator.geolocation.clearWatch(watchIdB);
      watchIdB = null;
    }
    if (predictionTimer) {
      clearInterval(predictionTimer);
      predictionTimer = null;
    }
    if (simTimer) {
      clearInterval(simTimer);
      simTimer = null;
    }
    if (motionHandler) {
      window.removeEventListener("devicemotion", motionHandler);
      motionHandler = null;
    }
    onUpdate = null;
    onKmAccumulated = null;
    accelBoostKmh = 0;
    trendKmhPerSec = 0;
    gpsKmh = 0;
    deriveKmh = 0;
    fusedKmh = 0;
    displayKmh = 0;
    lastFixMs = null;
    lastBlendMs = 0;
    stationaryLatch = true;
    exitHoldUntil = 0;
    clearExternalSpeed();
    if (!opts.silent && typeof opts.onStopped === "function") opts.onStopped();
  }

  function simulateForPreview(callbacks = {}) {
    stop({ silent: true });
    onUpdate = callbacks.onUpdate || null;
    // Özellik turu: radar (far→critical) + hız koridoru (giriş/ort/çıkış)
    if (typeof RadarAlert !== "undefined" && RadarAlert.beginDemoTour) {
      RadarAlert.beginDemoTour();
    }
    const LAT = 41.12;
    const mPerDegLng = 111320 * Math.cos((LAT * Math.PI) / 180);
    // Demo kameralarla hizalı (radar-alert DEMO_CAMERAS)
    const CAM_A = 29.05;
    const CAM_B = 29.015;
    const CAM_C = 28.975;
    let t = 0;
    let lng = CAM_A + 4800 / mPerDegLng;
    let lat = LAT;
    headingDeg = 270;
    stationaryLatch = false;
    exitHoldUntil = 0;
    lastFixMs = Date.now();
    accuracyM = 8;

    const id = setInterval(() => {
      if (simTimer !== id) return;
      t += 0.05;
      const cycle = t % 72;
      let kmh = 100;
      let trend = 0;

      if (cycle < 0.08) {
        if (typeof RadarAlert !== "undefined") RadarAlert.resetCorridor?.();
      }

      if (cycle < 16) {
        // Radar A: 4.8 km → 220 m (far→critical)
        const u = cycle / 16;
        const d = 4800 * (1 - u) + 220 * u;
        lng = CAM_A + d / mPerDegLng;
        kmh = 88 + u * 28;
        trend = 10;
      } else if (cycle < 26) {
        // Radar B yaklaşımı
        const u = (cycle - 16) / 10;
        const d = 2400 * (1 - u) + 180 * u;
        lng = CAM_B + d / mPerDegLng;
        kmh = 108;
        trend = -3;
      } else if (cycle < 34) {
        // Koridor girişine yaklaş (900→180 m) — giriş tetiklensin
        const u = (cycle - 26) / 8;
        const d = 900 * (1 - u) + 180 * u;
        lng = CAM_C + d / mPerDegLng;
        kmh = 102;
        trend = -2;
      } else if (cycle < 58) {
        // Koridor içi: girişten itibaren 2.4 km ilerle, ort. takip + limit salınımı
        const u = (cycle - 34) / 24;
        const traveled = Math.min(2350, u * 2350);
        lng = CAM_C - traveled / mPerDegLng;
        kmh = 108 + Math.sin(u * Math.PI * 3) * 16; // ~92–124 (aşım da)
        trend = Math.cos(u * Math.PI * 3) * 8;
      } else {
        // Çıkış sonrası kısa sakin
        const u = (cycle - 58) / 14;
        lng = CAM_C - (2400 + u * 400) / mPerDegLng;
        kmh = 88 - u * 10;
        trend = -4;
      }

      lat = LAT + Math.sin(t * 0.12) * 0.00006;
      gpsKmh = kmh;
      deriveKmh = kmh;
      fusedKmh = kmh;
      displayKmh = kmh;
      trendKmhPerSec = trend;
      accelBoostKmh = Math.max(0, trend);
      lastLat = lat;
      lastLng = lng;
      lastFixMs = Date.now();
      accuracyM = 8;
      emit();
    }, 50);
    simTimer = id;
    return () => {
      if (simTimer === id) {
        clearInterval(id);
        simTimer = null;
      }
      if (typeof RadarAlert !== "undefined") {
        RadarAlert.endDemoTour?.();
      }
    };
  }

  return {
    FREE_TRIAL_KM,
    start,
    stop,
    setSensitivity,
    loadTotalKm,
    getTotalKm: () => totalKm,
    setTotalKm,
    resetTotalKm,
    setExternalSpeed,
    clearExternalSpeed,
    getSpeedSource,
    getLastPosition: () =>
      lastLat != null && lastLng != null
        ? { lat: lastLat, lng: lastLng, accuracy: accuracyM }
        : null,
    simulateForPreview,
  };
})();

try {
  window.GpsTracker = GpsTracker;
} catch (_) {}
if (typeof module !== "undefined") module.exports = GpsTracker;
