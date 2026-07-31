import UIKit
import SwiftUI
import Capacitor
import WebKit

/// Bridges cluster sound controls + JS eval to the hidden Capacitor layer.
enum EtubuClusterAudioBridge {
    static func setMixMode(_ mode: String) {
        DispatchQueue.main.async {
            if #available(iOS 16.2, *) {
                EtubuLiveActivityController.ensureAudioSession(mixWithOthers: mode != "solo")
            }
            // Uyarılar müziğin üstüne yazsın — duckOthers kullanma
            AppDelegate.activateDriveAudioSession()
        }
        evalJS("""
        (function(){
          try {
            if (window.EtubuNative && window.EtubuNative.setAudioMixMode) {
              window.EtubuNative.setAudioMixMode({ mode: '\(mode)' });
            }
            if (window.AudioEngine && window.AudioEngine.setMixMode) {
              window.AudioEngine.setMixMode('\(mode)');
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
    static func setSoundEnabled(_ on: Bool, voice: String? = nil) {
        let key = (voice ?? storedVoice)
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\n", with: "")
        let resolved = (key.isEmpty || key == "silent-mode") ? "calm-ev" : key
        if on {
            UserDefaults.standard.set(resolved, forKey: "etubu.cluster.voice")
            AppDelegate.activateDriveAudioSession()
            if #available(iOS 16.2, *) {
                EtubuLiveActivityController.ensureAudioSession(mixWithOthers: true)
            }
            armPowerRegenHook()
            evalJS("""
            (function(){
              try {
                // Web gibi: beep + TTS hazır
                if (window.RadarAlert && window.RadarAlert.primeAudio) window.RadarAlert.primeAudio();
                localStorage.setItem('etubu_radar_beeps', '1');
                localStorage.setItem('etubu_radar_tts', localStorage.getItem('etubu_radar_tts') || '1');
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
        } else {
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
        let voice = storedVoice == "silent-mode" ? "calm-ev" : storedVoice
        setSoundEnabled(true, voice: voice)
        pushDrive(kmh: kmh, powerKw: powerKw, source: source)
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

    /// Feed live speed + Tesla power (negative = regen) into Cap AudioEngine.
    /// Coalesced ~120ms to avoid audible flutter from BLE poll.
    private static var pendingDrive: (kmh: Int, powerKw: Int?, source: String)?
    private static var driveFlushWork: DispatchWorkItem?
    private static let driveThrottleSec: Double = 0.12

    static func pushDrive(kmh: Int, powerKw: Int?, source: String) {
        pendingDrive = (kmh, powerKw, source)
        if driveFlushWork != nil { return }
        let work = DispatchWorkItem {
            driveFlushWork = nil
            flushDrive()
        }
        driveFlushWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + driveThrottleSec, execute: work)
    }

    private static func flushDrive() {
        guard let d = pendingDrive else { return }
        pendingDrive = nil
        let p = d.powerKw.map(String.init) ?? "null"
        let src = d.source
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\n", with: "")
        let voice = storedVoice
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\n", with: "")
        let voiceKey = (voice.isEmpty || voice == "silent-mode") ? "calm-ev" : voice
        evalJS("""
        (function(){
          try {
            window.__etubuDrivePowerKw = \(p);
            window.__etubuDriveKmh = \(d.kmh);
            var AE = window.AudioEngine;
            if (!AE) return;
            if (AE.setQuality) { try { AE.setQuality('high'); } catch (e0) {} }
            if (AE.resume) { try { AE.resume(); } catch (e1) {} }
            var want = '\(voiceKey)';
            if (want && AE.start && (!AE._running || (AE._voiceKey && AE._voiceKey !== want))) {
              try { AE.start(want); } catch (e2) {}
              if (AE.setMuted) AE.setMuted(false);
            }
            if (AE.setSpeed) {
              var prev = (typeof window.__etubuPrevKmh === 'number') ? window.__etubuPrevKmh : \(d.kmh);
              var trend = \(d.kmh) - prev;
              AE.setSpeed(\(d.kmh), {
                source: '\(src)',
                powerKw: \(p),
                trend: trend
              });
              if (AE._running && AE._applyParams) {
                try { AE._applyParams(AE._smoothKmh != null ? AE._smoothKmh : \(d.kmh), false); } catch (e3) {}
              }
            }
            window.__etubuPrevKmh = \(d.kmh);
          } catch (e) {}
        })();
        """)
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
    static func setPremium(_ unlocked: Bool) {
        evalJS("""
        (function(){
          try {
            window.__etubuPremium = \(unlocked ? "true" : "false");
            if (window.EtubuNative) { window.EtubuNative.premium = \(unlocked ? "true" : "false"); }
          } catch (e) {}
        })();
        """)
    }

    /// Web `I18n.setLang` — TR dışı dillerde kritik nokta / RouteGuard kapalı.
    static func setLanguage(_ code: String) {
        let safe = code.replacingOccurrences(of: "'", with: "")
        let forceTr = (safe == "tr")
        evalJS("""
        (function(){
          try {
            if (window.I18n && window.I18n.setLang) window.I18n.setLang('\(safe)');
            window.__etubuLang = '\(safe)';
            if (window.sessionStorage) {
              sessionStorage.setItem('etubu_lang', '\(safe)');
              if (\(forceTr ? "true" : "false")) {
                sessionStorage.setItem('etubu_force_tr_route', '1');
                window.__etubuForceTrRoute = 1;
              } else {
                sessionStorage.removeItem('etubu_force_tr_route');
                window.__etubuForceTrRoute = 0;
                try { localStorage.removeItem('etubu_force_tr_route'); } catch(e0) {}
              }
            }
            if (window.RouteGuard && window.RouteGuard.syncVisibility) {
              window.RouteGuard.syncVisibility();
            }
            if (window.RouteGuard && window.RouteGuard.refreshLocale) {
              window.RouteGuard.refreshLocale();
            }
            if (!\(forceTr ? "true" : "false")) {
              if (window.RadarAlert && window.RadarAlert.clear) window.RadarAlert.clear();
              if (window.__etubuRouteState) {
                window.__etubuRouteState.hazards = [];
              }
            }
          } catch (e) {}
        })();
        """)
    }

    static func endDrive() {
        // Cluster owns Live Activity — don't tear Island when Cap/web stops EV loop.
        evalJS("""
        (function(){
          try {
            if (window.AudioEngine && window.AudioEngine.stop) window.AudioEngine.stop();
            if (window.RadarAlert && window.RadarAlert.clear) window.RadarAlert.clear();
          } catch (e) {}
        })();
        """)
    }

    static func setTheme(_ key: String) {
        evalJS("""
        (function(){
          try {
            if (window.Scene && window.Scene.setMode) window.Scene.setMode('\(key)');
            localStorage.setItem('etubu_visual', '\(key)');
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

    static func evalJSReturning(_ js: String, completion: @escaping (String?) -> Void) {
        DispatchQueue.main.async {
            guard let webView = findWebView() else {
                completion(nil)
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
                        completion(stringifyEvalResult(value))
                    case .failure:
                        // Fallback for older WebKit edge cases
                        webView.evaluateJavaScript(js) { value, _ in
                            completion(stringifyEvalResult(value))
                        }
                    }
                }
            } else {
                webView.evaluateJavaScript(js) { result, _ in
                    completion(stringifyEvalResult(result))
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
