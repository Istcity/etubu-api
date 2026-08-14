import UIKit
import SwiftUI
import Capacitor
import WebKit
import AVFoundation

/// Bridges cluster sound controls + JS eval to the hidden Capacitor layer.
enum EtubuClusterAudioBridge {
    static func setMixMode(_ mode: String) {
        let safe = mode.replacingOccurrences(of: "'", with: "").lowercased()
        UserDefaults.standard.set(safe, forKey: "etubu.cluster.mixMode")
        DispatchQueue.main.async {
            AppDelegate.activateDriveAudioSession()
        }
        evalJS("""
        (function(){
          try {
            if (window.EtubuNative && window.EtubuNative.setAudioMixMode) {
              window.EtubuNative.setAudioMixMode({ mode: '\(safe)' });
            }
            if (window.AudioEngine && window.AudioEngine.setMixMode) {
              window.AudioEngine.setMixMode('\(safe)');
            }
          } catch (e) {}
        })();
        """)
    }

    /// Uyarı/EV seviyesini müzik üstünde ayarlar (0…1) — müziği kesmez.
    static func setAlertVolume(_ level: Double) {
        let v = max(0.05, min(1.0, level))
        UserDefaults.standard.set(v, forKey: "etubu.cluster.alertVolume")
        evalJS("""
        (function(){
          try {
            var v = \(String(format: "%.3f", v));
            if (window.AudioEngine) {
              if (window.AudioEngine.setMixIntensity) window.AudioEngine.setMixIntensity(v);
              if (window.AudioEngine.setVolume) window.AudioEngine.setVolume(v);
              if (window.AudioEngine._mixIntensity != null) window.AudioEngine._mixIntensity = v;
            }
            if (window.RadarAlert && window.RadarAlert.setVolume) window.RadarAlert.setVolume(v);
            localStorage.setItem('etubu_alert_volume', String(v));
          } catch (e) {}
        })();
        """)
    }

    /// Jul-29 web voice list — `AudioEngine.start(key)`.
    static func setVoice(_ key: String) {
        let safe = key
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\n", with: "")
        UserDefaults.standard.set(safe, forKey: "etubu.cluster.voice")
        if safe != "silent-mode", isSoundWanted {
            EtubuNativeDriveAudio.shared.start(voice: safe)
            EtubuNativeDriveAudio.shared.setMuted(false)
        }
        evalJS("""
        (function(){
          try {
            if (window.AudioEngine) {
              if (window.AudioEngine.setQuality) window.AudioEngine.setQuality('high');
              if (window.AudioEngine.resume) window.AudioEngine.resume();
              if (window.AudioEngine.start) window.AudioEngine.start('\(safe)');
              if (window.AudioEngine.setMuted) window.AudioEngine.setMuted('\(safe)' === 'silent-mode');
            }
            var sel = document.getElementById('voiceSelect');
            if (sel) {
              sel.value = '\(safe)';
              sel.dispatchEvent(new Event('change', { bubbles: true }));
            }
            localStorage.setItem('etubu_voice', '\(safe)');
          } catch (e) {}
        })();
        """)
    }

    static var storedVoice: String {
        UserDefaults.standard.string(forKey: "etubu.cluster.voice") ?? "silent-mode"
    }

    /// Fast on/off — prefers `AudioEngine.setMuted` so the icon responds immediately.
    private static let soundOnKey = "etubu.cluster.evSoundOn"
    /// Tema = ses paketi; sessizden çıkınca mevcut temanın driveVoiceKey.
    static var defaultDriveVoice: String {
        ClusterTheme.stored.driveVoiceKey
    }

    static var isSoundWanted: Bool {
        get { UserDefaults.standard.object(forKey: soundOnKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: soundOnKey) }
    }

    /// Bumped on endDrive so late Cap retries / demo asyncAfter no-op.
    private static var driveGeneration: UInt64 = 0
    /// Demo/cold-start: native owns until Cap is proven warm (never both muted).
    private static var preferNativeOwner = false
    private static var capWarmStreak = 0
    private static var ownershipHeartbeat: DispatchWorkItem?

    static func setSoundEnabled(_ on: Bool, voice: String? = nil) {
        let key = (voice ?? storedVoice)
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\n", with: "")
        let resolved = (key.isEmpty || key == "silent-mode") ? defaultDriveVoice : key
        isSoundWanted = on
        if on {
            UserDefaults.standard.set(resolved, forKey: "etubu.cluster.voice")
            AppDelegate.activateDriveAudioSession()
            if #available(iOS 16.2, *) {
                EtubuLiveActivityController.ensureAudioSession(mixWithOthers: true)
            }
            armPowerRegenHook()
            // Native primary until Cap warm — cold Cap must never leave silence.
            EtubuNativeDriveAudio.shared.start(voice: resolved)
            EtubuNativeDriveAudio.shared.setMuted(false)
            capWarmStreak = 0
            evalJS("""
            (function(){
              try {
                // EV ses — uyarı beep/TTS ayarlarına dokunma (yalnızca ayarlar)
                if (window.RadarAlert && window.RadarAlert.primeAudio) window.RadarAlert.primeAudio();
                var Ctx = window.AudioContext || window.webkitAudioContext;
                if (Ctx) {
                  if (!window.__etubuBeepCtx) window.__etubuBeepCtx = new Ctx();
                  if (window.__etubuBeepCtx.state === 'suspended') window.__etubuBeepCtx.resume();
                }
                if (!window.AudioEngine) return;
                var key = '\(resolved)';
                if (window.AudioEngine.setQuality) window.AudioEngine.setQuality('high');
                if (window.AudioEngine.resume) window.AudioEngine.resume();
                var running = !!window.AudioEngine._running;
                var same = window.AudioEngine._voiceKey === key;
                if (running && same && window.AudioEngine.setMuted) {
                  window.AudioEngine.setMuted(false);
                  return;
                }
                if (window.AudioEngine.start) window.AudioEngine.start(key);
                if (window.AudioEngine.setMuted) window.AudioEngine.setMuted(false);
                localStorage.setItem('etubu_voice', key);
              } catch (e) {}
            })();
            """)
            startOwnershipHeartbeat()
        } else {
            liveDriveSoundArmed = false
            preferNativeOwner = false
            capWarmStreak = 0
            stopOwnershipHeartbeat()
            EtubuNativeDriveAudio.shared.setMuted(true)
            evalJS("""
            (function(){
              try {
                if (!window.AudioEngine) return;
                // Mute keeps graph warm for instant re-open; avoid full stop lag.
                if (window.AudioEngine.setMuted) window.AudioEngine.setMuted(true);
                else if (window.AudioEngine.stop) window.AudioEngine.stop();
              } catch (e) {}
            })();
            """)
        }
    }

    static func startDrive(kmh: Int, gear: String, source: String, powerKw: Int? = nil) {
        let voice = storedVoice == "silent-mode" ? defaultDriveVoice : storedVoice
        // Demo: native stays primary (Cap often cold under opaque cluster).
        preferNativeOwner = (source == "demo")
        setSoundEnabled(true, voice: voice)
        EtubuNativeDriveAudio.shared.start(voice: voice)
        EtubuNativeDriveAudio.shared.setMuted(false)
        EtubuNativeDriveAudio.shared.setSpeed(kmh: kmh, powerKw: powerKw)
        // Cap stub → index-app geçişi bitmeden AudioEngine yok; demoda agresif yeniden dene.
        ensureDriveEngine(voice: voice, retriesLeft: source == "demo" ? 18 : 12)
        pushDrive(kmh: kmh, powerKw: powerKw, source: source, forceImmediate: source == "demo" || source == "tesla")
        startOwnershipHeartbeat()
        if #available(iOS 16.2, *) {
            Task {
                let t = EtubuVehicleTelemetry.shared
                _ = await EtubuLiveActivityController.start(
                    voice: "ETUBU", kmh: kmh, gear: gear, rpm: 0, source: source,
                    tpmsFL: t.tpmsFL.psi.map { Int($0.rounded()) },
                    tpmsFR: t.tpmsFR.psi.map { Int($0.rounded()) },
                    tpmsRL: t.tpmsRL.psi.map { Int($0.rounded()) },
                    tpmsRR: t.tpmsRR.psi.map { Int($0.rounded()) }
                )
            }
        }
    }

    private static var liveDriveSoundArmed = false

    /// Tesla bağlıyken kullanıcı ses açtıysa Cap/native motorunu ayakta tut (demo parity).
    static func ensureLiveDriveSound(kmh: Int, powerKw: Int?, gear: String) {
        let t = EtubuVehicleTelemetry.shared
        let gpsFresh = t.lastGpsSampleFresh
        let fine = gpsFresh && t.gpsKmhFine > 0.4 ? t.gpsKmhFine : (t.kmhFine > 0.4 ? t.kmhFine : Double(kmh))
        let accel = t.accelKmhS
        guard isSoundWanted else {
            liveDriveSoundArmed = false
            pushDrive(kmh: kmh, powerKw: powerKw, source: "tesla", accelKmhS: accel, kmhFine: fine)
            return
        }
        if !liveDriveSoundArmed {
            liveDriveSoundArmed = true
            startDrive(kmh: kmh, gear: gear, source: "tesla", powerKw: powerKw)
        } else {
            pushDrive(kmh: kmh, powerKw: powerKw, source: "tesla", accelKmhS: accel, kmhFine: fine)
            EtubuNativeDriveAudio.shared.setSpeed(kmh: fine, powerKw: powerKw.map { Double($0) }, accelKmhS: accel)
        }
    }

    /// Feed live speed + Tesla power (negative = regen) into Cap AudioEngine.
    /// Coalesced ~120ms to avoid audible flutter from BLE poll; demo ~50ms + snap.
    private static var pendingDrive: (kmh: Int, kmhFine: Double, powerKw: Int?, accelKmhS: Double, source: String)?
    private static var driveFlushWork: DispatchWorkItem?
    private static let driveThrottleSec: Double = 0.12
    private static var engineRetryWork: DispatchWorkItem?

    static func pushDrive(kmh: Int, powerKw: Int?, source: String, forceImmediate: Bool = false, accelKmhS: Double? = nil, kmhFine: Double? = nil) {
        let t = EtubuVehicleTelemetry.shared
        let fine = (t.lastGpsSampleFresh && t.gpsKmhFine > 0.4)
            ? t.gpsKmhFine
            : (kmhFine ?? (t.kmhFine > 0.4 ? t.kmhFine : Double(kmh)))
        let accel = accelKmhS ?? t.accelKmhS
        pendingDrive = (kmh, fine, powerKw, accel, source)
        if forceImmediate || source == "demo" {
            driveFlushWork?.cancel()
            driveFlushWork = nil
            flushDrive()
            return
        }
        if driveFlushWork != nil { return }
        let work = DispatchWorkItem {
            driveFlushWork = nil
            flushDrive()
        }
        driveFlushWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + driveThrottleSec, execute: work)
    }

    private static func ensureDriveEngine(voice: String, retriesLeft: Int) {
        let gen = driveGeneration
        guard isSoundWanted else { return }
        let safe = voice
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\n", with: "")
        let key = (safe.isEmpty || safe == "silent-mode") ? defaultDriveVoice : safe
        AppDelegate.activateDriveAudioSession()
        EtubuCapBridgeViewController.armWebContent()
        // Keep native audible while Cap boots.
        if !EtubuNativeDriveAudio.shared.isEngineAlive {
            EtubuNativeDriveAudio.shared.start(voice: key)
        }
        if preferNativeOwner || !EtubuNativeDriveAudio.shared.isAudible {
            EtubuNativeDriveAudio.shared.setMuted(false)
        }
        evalJSReturning("""
        (function(){
          try {
            var Ctx = window.AudioContext || window.webkitAudioContext;
            if (Ctx) {
              if (!window.__etubuBeepCtx) window.__etubuBeepCtx = new Ctx();
              if (window.__etubuBeepCtx.state === 'suspended') window.__etubuBeepCtx.resume();
            }
            var AE = window.AudioEngine;
            if (!AE) return 'missing';
            if (AE.setQuality) AE.setQuality('high');
            if (AE.resume) AE.resume();
            var want = '\(key)';
            if (AE.start && (!AE._running || AE._voiceKey !== want)) {
              AE.start(want);
            }
            if (AE.setMuted) AE.setMuted(false);
            var ctx = AE._ctx || AE.ctx || AE._audioContext || AE.audioContext;
            var ctxOk = !ctx || !ctx.state || ctx.state === 'running';
            if (AE._running && !AE._muted && ctxOk) return 'ok';
            return AE._running ? 'started' : 'cold';
          } catch (e) { return 'err'; }
        })();
        """, timeout: 4) { result in
            guard gen == driveGeneration, isSoundWanted else { return }
            let s = result ?? ""
            if s == "ok" {
                reconcileAudioOwnership()
                return
            }
            // Cap not proven warm — native must stay audible.
            EtubuNativeDriveAudio.shared.setMuted(false)
            guard retriesLeft > 0 else { return }
            scheduleEngineRetry(voice: key, retriesLeft: retriesLeft - 1, delay: 0.35)
        }
    }

    private static func scheduleEngineRetry(voice: String, retriesLeft: Int, delay: Double) {
        let gen = driveGeneration
        engineRetryWork?.cancel()
        let work = DispatchWorkItem {
            guard gen == driveGeneration, isSoundWanted else { return }
            ensureDriveEngine(voice: voice, retriesLeft: retriesLeft)
        }
        engineRetryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private static func flushDrive() {
        guard let d = pendingDrive else { return }
        pendingDrive = nil
        let soundOn = isSoundWanted
        let p = d.powerKw.map(String.init) ?? "null"
        let src = d.source
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\n", with: "")
        let voice = storedVoice
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\n", with: "")
        let voiceKey = (voice.isEmpty || voice == "silent-mode") ? defaultDriveVoice : voice
        let isDemo = src == "demo"
        let gen = driveGeneration

        // Native: keep engine alive for speed params, but never unmute while UI mute is on.
        if soundOn {
            if !EtubuNativeDriveAudio.shared.isEngineAlive {
                EtubuNativeDriveAudio.shared.start(voice: voiceKey)
            }
            // Demo / Cap-cold: native must stay audible (never both muted).
            if preferNativeOwner || !EtubuNativeDriveAudio.shared.isAudible {
                EtubuNativeDriveAudio.shared.setMuted(false)
            }
            EtubuNativeDriveAudio.shared.setSpeed(kmh: d.kmhFine, powerKw: d.powerKw.map { Double($0) }, accelKmhS: d.accelKmhS)
        } else if EtubuNativeDriveAudio.shared.isEngineAlive {
            EtubuNativeDriveAudio.shared.setMuted(true)
        }

        let muteJS = soundOn ? "false" : "true"
        let fine = String(format: "%.3f", d.kmhFine)
        let accel = String(format: "%.3f", d.accelKmhS)
        evalJS("""
        (function(){
          try {
            window.__etubuDrivePowerKw = \(p);
            window.__etubuDriveKmh = \(fine);
            var AE = window.AudioEngine;
            if (!AE) {
              window.__etubuDrivePending = { kmh: \(fine), powerKw: \(p), accelKmhS: \(accel), source: '\(src)' };
              return;
            }
            if (!\(soundOn ? "true" : "false")) {
              if (AE.setMuted) AE.setMuted(true);
              return;
            }
            if (AE.setQuality) { try { AE.setQuality('high'); } catch (e0) {} }
            if (AE.resume) { try { AE.resume(); } catch (e1) {} }
            var want = '\(voiceKey)';
            if (want && AE.start && (!AE._running || (AE._voiceKey && AE._voiceKey !== want))) {
              try { AE.start(want); } catch (e2) {}
            }
            if (AE.setMuted) AE.setMuted(\(muteJS));
            if (\(isDemo ? "true" : "false") && AE.snapSpeed) {
              try { AE.setSpeed(\(fine), { source: 'demo', powerKw: \(p), trend: \(accel), accelKmhS: \(accel) }); } catch (eS) {}
            } else if (AE.setSpeed) {
              AE.setSpeed(\(fine), {
                source: '\(src)',
                powerKw: \(p),
                trend: \(accel),
                accelKmhS: \(accel)
              });
            }
            if (AE._running && AE._applyParams) {
              try { AE._applyParams(AE._smoothKmh != null ? AE._smoothKmh : \(fine), false); } catch (e3) {}
            }
            window.__etubuPrevKmh = \(fine);
          } catch (e) {}
        })();
        """)
        if soundOn {
            reconcileAudioOwnership()
        }
        if isDemo, soundOn {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                guard gen == driveGeneration, isSoundWanted else { return }
                // Demo: keep native unmuted even if Cap also runs.
                EtubuNativeDriveAudio.shared.setMuted(false)
                evalJS("""
                (function(){
                  try {
                    var AE = window.AudioEngine;
                    if (!AE || AE._running) return;
                    if (AE.start) AE.start('\(voiceKey)');
                    if (AE.setMuted) AE.setMuted(false);
                    if (AE.snapSpeed) AE.snapSpeed(\(d.kmh));
                    if (AE.setSpeed) AE.setSpeed(\(d.kmh), { source: 'demo', powerKw: \(p), trend: 4 });
                  } catch (e) {}
                })();
                """)
            }
        }
    }

    private static func startOwnershipHeartbeat() {
        stopOwnershipHeartbeat()
        guard isSoundWanted else { return }
        let gen = driveGeneration
        let work = DispatchWorkItem {
            guard gen == driveGeneration, isSoundWanted else { return }
            reconcileAudioOwnership()
            // Reschedule
            ownershipHeartbeat = nil
            startOwnershipHeartbeat()
        }
        ownershipHeartbeat = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: work)
    }

    private static func stopOwnershipHeartbeat() {
        ownershipHeartbeat?.cancel()
        ownershipHeartbeat = nil
    }

    /// Cap WebAudio often stays on the phone speaker while Music owns car A2DP.
    /// Native AVAudioPlayer follows the ducked Bluetooth route.
    private static var carMixForcesNative: Bool {
        let session = AVAudioSession.sharedInstance()
        return session.isOtherAudioPlaying || AppDelegate.isCarMediaRoute(session)
    }

    /// Cap preferred when proven warm; native fallback otherwise. Never leave both muted.
    /// Car + Music: native always owns (WKWebView does not ride A2DP).
    private static func reconcileAudioOwnership() {
        guard isSoundWanted else { return }
        let gen = driveGeneration
        if preferNativeOwner || carMixForcesNative {
            if !EtubuNativeDriveAudio.shared.isEngineAlive {
                let voice = storedVoice == "silent-mode" ? defaultDriveVoice : storedVoice
                EtubuNativeDriveAudio.shared.start(voice: voice)
            }
            EtubuNativeDriveAudio.shared.setMuted(false)
            if carMixForcesNative {
                evalJS("""
                (function(){
                  try {
                    if (window.AudioEngine && window.AudioEngine.setMuted) window.AudioEngine.setMuted(true);
                  } catch (e) {}
                })();
                """)
            }
            return
        }
        evalJSReturning("""
        (function(){
          try {
            var AE = window.AudioEngine;
            if (!AE || !AE._running || AE._muted) return 'cold';
            var ctx = AE._ctx || AE.ctx || AE._audioContext || AE.audioContext;
            if (ctx && ctx.state && ctx.state !== 'running') return 'cold';
            // Master closed / silent graph counts as cold
            if (typeof AE.isMuted === 'function' && AE.isMuted()) return 'cold';
            return 'warm';
          } catch (e) { return 'cold'; }
        })();
        """, timeout: 2) { result in
            guard gen == driveGeneration, isSoundWanted else { return }
            if result == "warm" {
                capWarmStreak += 1
                // Require two consecutive warms before muting native (avoids false warm → silence).
                if capWarmStreak >= 2 {
                    EtubuNativeDriveAudio.shared.setMuted(true)
                } else {
                    EtubuNativeDriveAudio.shared.setMuted(false)
                }
            } else {
                capWarmStreak = 0
                // Cap suspended/soğuk → native yedek (handoff boşluğu = duyulan kesilme)
                if !EtubuNativeDriveAudio.shared.isEngineAlive {
                    let voice = storedVoice == "silent-mode" ? defaultDriveVoice : storedVoice
                    EtubuNativeDriveAudio.shared.start(voice: voice)
                }
                EtubuNativeDriveAudio.shared.setMuted(false)
            }
        }
    }

    /// Kept for older Cap sessions — AudioEngine.setSpeed now handles powerKw natively.
    static func armPowerRegenHook() {
        evalJS("""
        (function(){
          try {
            if (window.AudioEngine) window.AudioEngine.__etubuRegenHook = true;
          } catch (e) {}
        })();
        """)
    }

    /// Mirror native premium unlock state into the web layer.
    /// Idempotent: Cap WebView may not be ready on first call — callers re-inject on appear / onChange.
    static func setPremium(_ unlocked: Bool) {
        let flag = unlocked ? "true" : "false"
        evalJS("""
        (function(){
          try {
            window.__etubuPremium = \(flag);
            if (window.EtubuNative) { window.EtubuNative.premium = \(flag); }
            try { window.dispatchEvent(new CustomEvent('etubuPremium', { detail: { unlocked: \(flag) } })); } catch (e1) {}
          } catch (e) {}
        })();
        """)
    }

    /// Web `I18n.setLang` — rota/uyarı özellikleri dil bağımsız (OSM/OCM global).
    static func setLanguage(_ code: String) {
        let safe = code.replacingOccurrences(of: "'", with: "")
        evalJS("""
        (function(){
          try {
            if (window.I18n && window.I18n.setLang) window.I18n.setLang('\(safe)');
            window.__etubuLang = '\(safe)';
            if (window.sessionStorage) {
              sessionStorage.setItem('etubu_lang', '\(safe)');
              var forceTr = \(EtubuRegion.lastKnownInTurkey ? "1" : "0");
              sessionStorage.setItem('etubu_force_tr_route', forceTr);
              window.__etubuForceTrRoute = +forceTr;
              try { localStorage.setItem('etubu_force_tr_route', forceTr); } catch(e0) {}
            }
            if (window.RouteGuard && window.RouteGuard.syncVisibility) {
              window.RouteGuard.syncVisibility();
            }
            if (window.RouteGuard && window.RouteGuard.refreshLocale) {
              window.RouteGuard.refreshLocale();
            }
          } catch (e) {}
        })();
        """)
    }

    /// Uyarı bip — native (TTS yok). Her olay türü ayrı ton; aynı nokta tekrar etmez (DriveWarnings).
    private static var lastWarnCueKey = ""
    private static var lastWarnCueAt = Date.distantPast

    static func playWarnCue(id: String, kind: String, stage: String, phrase: String) {
        let beepsOn = UserDefaults.standard.object(forKey: "etubu_radar_beeps") as? Bool ?? true
        guard beepsOn else { return }
        _ = phrase
        UserDefaults.standard.set(false, forKey: "etubu_radar_tts")

        let now = Date()
        if id == lastWarnCueKey, now.timeIntervalSince(lastWarnCueAt) < 1.6 { return }
        lastWarnCueKey = id
        lastWarnCueAt = now

        let urgent = (stage == "critical" || stage == "near") && (kind == "corridor" || kind == "control" || kind == "radar")
        EtubuWarnVoice.playKindCue(kind: kind, urgent: urgent || stage == "critical")
    }

    private static func fireBeeps(count: Int, urgent: Bool) {
        EtubuWarnVoice.playBeeps(count: count, urgent: urgent)
    }

    /// "Radar 250 m" / "1.2 km" gibi mesafe parçalarını TTS’ten çıkar.
    private static func sanitizeWarnPhrase(_ phrase: String) -> String {
        var s = phrase
        // Drop speed-ratio fragments ("95 / 80") — keep distance for countdown TTS.
        if let re = try? NSRegularExpression(pattern: #"\b\d+\s*/\s*\d+\b"#, options: []) {
            let range = NSRange(s.startIndex..<s.endIndex, in: s)
            s = re.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "")
        }
        return s
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Legacy helper — distance kept for warn TTS; ratios stripped.
    private static func stripDistanceFromPhrase(_ phrase: String) -> String {
        sanitizeWarnPhrase(phrase)
    }

    static func endDrive() {
        driveGeneration &+= 1
        // Stop playback only — do not clear isSoundWanted (demo stop must not erase mute/on).
        preferNativeOwner = false
        capWarmStreak = 0
        liveDriveSoundArmed = false
        stopOwnershipHeartbeat()
        engineRetryWork?.cancel()
        engineRetryWork = nil
        driveFlushWork?.cancel()
        driveFlushWork = nil
        pendingDrive = nil
        EtubuNativeDriveAudio.shared.stop()
        EtubuWarnVoice.stopAll()
        // Cluster owns Live Activity — don't tear Island when Cap/web stops EV loop.
        evalJS("""
        (function(){
          try {
            if (window.AudioEngine && window.AudioEngine.stop) window.AudioEngine.stop();
            if (window.RadarAlert && window.RadarAlert.clear) window.RadarAlert.clear();
            try { if (window.speechSynthesis) window.speechSynthesis.cancel(); } catch (e0) {}
          } catch (e) {}
        })();
        """)
    }

    static func setTheme(_ key: String) {
        // Visual scene + drive pack (tema = ses)
        let themeVoice: String = {
            if let t = ClusterTheme.allCases.first(where: { $0.webKey == key || $0.rawValue == key }) {
                return t.driveVoiceKey
            }
            return ClusterTheme.stored.driveVoiceKey
        }()
        if isSoundWanted {
            UserDefaults.standard.set(themeVoice, forKey: "etubu.cluster.voice")
            EtubuNativeDriveAudio.shared.start(voice: themeVoice)
        }
        evalJS("""
        (function(){
          try {
            if (window.Scene && window.Scene.setMode) window.Scene.setMode('\(key)');
            localStorage.setItem('etubu_visual', '\(key)');
            var pack = '\(themeVoice)';
            if (window.AudioEngine) {
              if (window.AudioEngine.setThemePack) window.AudioEngine.setThemePack(pack);
              else if (window.AudioEngine.start && window.AudioEngine._running) {
                window.AudioEngine.start(pack);
              }
            }
          } catch (e) {}
        })();
        """)
    }

    static func evalJS(_ js: String) {
        DispatchQueue.main.async {
            guard let bridge = findBridge() else { return }
            bridge.eval(js: js)
        }
    }

    static func evalJSReturning(_ js: String, timeout: TimeInterval = 22, completion: @escaping (String?) -> Void) {
        DispatchQueue.main.async {
            var finished = false
            let finish: (String?) -> Void = { value in
                guard !finished else { return }
                finished = true
                completion(value)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                finish(nil)
            }
            guard let webView = findWebView() else {
                finish(nil)
                return
            }
            // Keep Cap engine warm under the opaque cluster overlay.
            EtubuClusterPresenter.shared.hideCapacitorChrome()
            // Async IIFEs return a Promise — evaluateJavaScript often yields nil.
            // callAsyncJavaScript awaits the promise and returns the resolved value.
            let wrapped = """
            var __etubuEval = (function(){ return \(js); })();
            if (__etubuEval && typeof __etubuEval.then === 'function') {
              return __etubuEval.then(function(v){
                if (v == null) return null;
                if (typeof v === 'string') return v;
                try { return JSON.stringify(v); } catch (e) { return String(v); }
              });
            }
            if (typeof __etubuEval === 'string') return __etubuEval;
            try { return JSON.stringify(__etubuEval); } catch (e2) { return String(__etubuEval); }
            """
            if #available(iOS 14.0, *) {
                webView.callAsyncJavaScript(wrapped, arguments: [:], in: nil, in: .page) { result in
                    switch result {
                    case .success(let value):
                        finish(stringifyEvalResult(value))
                    case .failure:
                        // Fallback for older WebKit edge cases
                        webView.evaluateJavaScript(js) { value, _ in
                            finish(stringifyEvalResult(value))
                        }
                    }
                }
            } else {
                webView.evaluateJavaScript(js) { result, _ in
                    finish(stringifyEvalResult(result))
                }
            }
        }
    }

    private static func stringifyEvalResult(_ result: Any?) -> String? {
        if result == nil || result is NSNull { return nil }
        if let s = result as? String { return s }
        if let s = result as? NSString { return s as String }
        if let n = result as? NSNumber { return n.stringValue }
        if JSONSerialization.isValidJSONObject(result!) {
            if let data = try? JSONSerialization.data(withJSONObject: result!),
               let s = String(data: data, encoding: .utf8) {
                return s
            }
        }
        return nil
    }

    private static func findBridge() -> CAPBridgeProtocol? {
        findCapVC()?.bridge
    }

    private static func findWebView() -> WKWebView? {
        guard let cap = findCapVC() else { return nil }
        if let wv = cap.webView { return wv }
        return findWKWebView(in: cap.view)
    }

    private static func findCapVC() -> CAPBridgeViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for window in scenes.flatMap(\.windows) {
            var vc: UIViewController? = window.rootViewController
            while let current = vc {
                if let cap = current as? CAPBridgeViewController { return cap }
                if let cap = current.children.compactMap({ $0 as? CAPBridgeViewController }).first {
                    return cap
                }
                for child in current.children {
                    if let cap = child as? CAPBridgeViewController { return cap }
                }
                vc = current.presentedViewController
            }
        }
        return nil
    }

    private static func findWKWebView(in view: UIView?) -> WKWebView? {
        guard let view else { return nil }
        if let wv = view as? WKWebView { return wv }
        for sub in view.subviews {
            if let found = findWKWebView(in: sub) { return found }
        }
        return nil
    }
}
