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

    static func startDrive(kmh: Int, gear: String, source: String) {
        if #available(iOS 16.2, *) {
            EtubuLiveActivityController.ensureAudioSession(mixWithOthers: true)
            EtubuLiveActivityController.startSilentKeepalive()
            Task {
                _ = await EtubuLiveActivityController.start(
                    voice: "ETUBU", kmh: kmh, gear: gear, rpm: 0, source: source
                )
            }
        }
        evalJS("""
        (function(){
          try {
            if (window.AudioEngine && window.AudioEngine.resume) window.AudioEngine.resume();
            if (window.AudioEngine && window.AudioEngine.start) window.AudioEngine.start();
            document.getElementById('startBtn')?.click?.();
          } catch (e) {}
        })();
        """)
    }

    /// Push a live telemetry tick (kmh/power) into the web audio engine without restarting the drive session.
    static func pushDrive(kmh: Int, powerKw: Int?, source: String) {
        let powerStr = powerKw.map { String($0) } ?? "null"
        evalJS("""
        (function(){
          try {
            if (window.AudioEngine && window.AudioEngine.update) {
              window.AudioEngine.update({ kmh: \(kmh), powerKw: \(powerStr), source: '\(source)' });
            }
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

    static func endDrive() {
        if #available(iOS 16.2, *) {
            EtubuLiveActivityController.stopSilentKeepalive()
            Task { await EtubuLiveActivityController.end() }
        }
        evalJS("""
        (function(){
          try {
            if (window.AudioEngine && window.AudioEngine.stop) window.AudioEngine.stop();
            if (window.EtubuNative && window.EtubuNative.endDriveSession) {
              window.EtubuNative.endDriveSession({});
            }
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
            webView.evaluateJavaScript(js) { result, _ in
                completion(result as? String)
            }
        }
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
