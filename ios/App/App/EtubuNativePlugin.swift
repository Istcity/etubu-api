import Foundation
import Capacitor
import StoreKit
import AVFoundation
import AVKit
import UIKit
import ActivityKit
import AuthenticationServices

/**
 * ETUBU native köprü — StoreKit, ses karışımı, Live Activity / Dynamic Island, Sign in with Apple, OBD BLE
 */
@objc(EtubuNativePlugin)
public class EtubuNativePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "EtubuNativePlugin"
    public let jsName = "EtubuNative"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "purchase", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "restore", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "showBannerAds", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "hideAds", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setAudioMixMode", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "showAudioRoutePicker", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "startDriveSession", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "updateDriveSession", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "endDriveSession", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "signInWithApple", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "obdBleConnect", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "obdBleDisconnect", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "obdBleState", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "trafikGet", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "trafikPost", returnType: CAPPluginReturnPromise),
    ]

    private let unlockLifetimeId = "etubu.unlock.lifetime"
    private let unlockYearlyId = "etubu.catalog.yearly"
    private let unlockYearlyAltId = "etubu.unlock.yearly"
    private let adfreeId = "etubu.ads.remove"
    private var routePicker: AVRoutePickerView?
    private var lastLiveUpdateMs: Double = 0
    private var appleSignInSession: AppleSignInSession?
    private let obdBle = EtubuObdBleManager.shared

    public override func load() {
        super.load()
        obdBle.setEmit { [weak self] payload in
            self?.notifyListeners("obdBleEvent", data: payload)
        }
    }

    @objc func purchase(_ call: CAPPluginCall) {
        guard let productId = call.getString("productId") else {
            call.reject("productId required")
            return
        }
        guard #available(iOS 15.0, *) else {
            call.resolve(["ok": false, "error": "iOS 15+ required"])
            return
        }
        Task {
            do {
                let products = try await Product.products(for: [productId])
                guard let product = products.first else {
                    call.resolve(["ok": false, "error": "Product not found: \(productId)"])
                    return
                }
                let result = try await product.purchase()
                switch result {
                case .success(let verification):
                    let transaction = try checkVerified(verification)
                    await transaction.finish()
                    call.resolve(["ok": true, "productId": productId])
                case .userCancelled:
                    call.resolve(["ok": false, "error": "cancelled"])
                case .pending:
                    call.resolve(["ok": false, "error": "pending"])
                @unknown default:
                    call.resolve(["ok": false, "error": "unknown"])
                }
            } catch {
                call.resolve(["ok": false, "error": error.localizedDescription])
            }
        }
    }

    @objc func restore(_ call: CAPPluginCall) {
        guard #available(iOS 15.0, *) else {
            call.resolve(["unlock": false, "yearly": false, "adfree": false])
            return
        }
        Task {
            var unlock = false
            var yearly = false
            var adfree = false
            do {
                try await AppStore.sync()
                for await result in Transaction.currentEntitlements {
                    if let tx = try? checkVerified(result) {
                        if tx.productID == unlockLifetimeId { unlock = true }
                        if tx.productID == unlockYearlyId || tx.productID == unlockYearlyAltId {
                            yearly = true
                            unlock = true
                        }
                        if tx.productID == adfreeId { adfree = true }
                    }
                }
                call.resolve(["unlock": unlock, "yearly": yearly, "adfree": adfree])
            } catch {
                call.reject(error.localizedDescription)
            }
        }
    }

    @objc func showBannerAds(_ call: CAPPluginCall) {
        call.resolve(["shown": false, "reason": "AdMob not wired yet"])
    }

    @objc func hideAds(_ call: CAPPluginCall) {
        call.resolve(["hidden": true])
    }

    @objc func setAudioMixMode(_ call: CAPPluginCall) {
        let mode = (call.getString("mode") ?? "blend").lowercased()
        if #available(iOS 16.2, *) {
            EtubuLiveActivityController.ensureAudioSession(mixWithOthers: mode != "solo")
            call.resolve(["ok": true, "mode": mode])
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            if mode == "solo" {
                try session.setCategory(.playback, mode: .default, options: [])
            } else {
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .allowBluetoothA2DP, .allowAirPlay])
            }
            try session.setActive(true, options: [])
            call.resolve(["ok": true, "mode": mode])
        } catch {
            call.resolve(["ok": false, "error": error.localizedDescription])
        }
    }

    @objc func showAudioRoutePicker(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard let host = self.bridge?.viewController else {
                call.resolve(["ok": false, "error": "no view controller"])
                return
            }
            self.routePicker?.removeFromSuperview()
            let picker = AVRoutePickerView(frame: CGRect(x: -100, y: -100, width: 44, height: 44))
            picker.prioritizesVideoDevices = false
            picker.isHidden = true
            host.view.addSubview(picker)
            self.routePicker = picker
            var tapped = false
            func tryTap(_ view: UIView) -> Bool {
                if let button = view as? UIButton {
                    button.sendActions(for: .touchUpInside)
                    return true
                }
                for child in view.subviews {
                    if tryTap(child) { return true }
                }
                return false
            }
            tapped = tryTap(picker)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                picker.removeFromSuperview()
                if self.routePicker === picker { self.routePicker = nil }
            }
            call.resolve(tapped ? ["ok": true] : ["ok": false, "error": "route button not found"])
        }
    }

    /// Sürüş başladı — arka plan ses + Live Activity / Dynamic Island
    @objc func startDriveSession(_ call: CAPPluginCall) {
        let voice = call.getString("voice") ?? "ETUBU"
        let kmh = call.getInt("kmh") ?? 0
        let gear = call.getString("gear") ?? "N"
        let rpm = call.getInt("rpm") ?? 0
        let source = call.getString("source") ?? "gps"
        let mix = (call.getString("mixMode") ?? "blend") != "solo"

        if #available(iOS 16.2, *) {
            EtubuLiveActivityController.ensureAudioSession(mixWithOthers: mix)
            // Keepalive + LA yalnızca arka planda (AppDelegate); burada başlatma.
            Task {
                let ok = await EtubuLiveActivityController.start(
                    voice: voice, kmh: kmh, gear: gear, rpm: rpm, source: source
                )
                call.resolve(["ok": true, "liveActivity": ok])
            }
        } else {
            do {
                let session = AVAudioSession.sharedInstance()
                var opts: AVAudioSession.CategoryOptions = [.allowBluetoothA2DP]
                if mix { opts.insert(.mixWithOthers) }
                try session.setCategory(.playback, mode: .default, options: opts)
                try session.setActive(true)
                call.resolve(["ok": true, "liveActivity": false, "reason": "iOS 16.2+ required for Live Activity"])
            } catch {
                call.resolve(["ok": false, "error": error.localizedDescription])
            }
        }
    }

    @objc func updateDriveSession(_ call: CAPPluginCall) {
        let now = Date().timeIntervalSince1970 * 1000
        // Dynamic Island spam önleme (~4 Hz)
        if now - lastLiveUpdateMs < 250 {
            call.resolve(["ok": true, "throttled": true])
            return
        }
        lastLiveUpdateMs = now

        let voice = call.getString("voice") ?? "ETUBU"
        let kmh = call.getInt("kmh") ?? 0
        let gear = call.getString("gear") ?? "N"
        let rpm = call.getInt("rpm") ?? 0
        let source = call.getString("source") ?? "gps"

        if #available(iOS 16.2, *) {
            Task {
                await EtubuLiveActivityController.update(
                    kmh: kmh, gear: gear, rpm: rpm, voice: voice, source: source
                )
                call.resolve(["ok": true])
            }
        } else {
            call.resolve(["ok": true, "liveActivity": false])
        }
    }

    @objc func endDriveSession(_ call: CAPPluginCall) {
        if #available(iOS 16.2, *) {
            EtubuLiveActivityController.stopSilentKeepalive()
            Task {
                await EtubuLiveActivityController.end()
                call.resolve(["ok": true])
            }
        } else {
            call.resolve(["ok": true])
        }
    }

    @objc func signInWithApple(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard let anchor = self.bridge?.viewController?.view.window else {
                call.resolve(["ok": false, "error": "no window"])
                return
            }
            let session = AppleSignInSession(anchor: anchor) { [weak self] payload in
                self?.appleSignInSession = nil
                call.resolve(payload)
            }
            self.appleSignInSession = session
            session.start()
        }
    }

    @objc func obdBleConnect(_ call: CAPPluginCall) {
        obdBle.connect { ok, message in
            call.resolve(["ok": ok, "message": message])
        }
    }

    @objc func obdBleDisconnect(_ call: CAPPluginCall) {
        obdBle.disconnect()
        call.resolve(["ok": true])
    }

    /// Cap RouteGuard proxy — bypasses WKWebView CORS for etubu.com/api/trafik.php
    @objc func trafikGet(_ call: CAPPluginCall) {
        var params: [String: String] = [:]
        if let action = call.getString("action") { params["action"] = action }
        if let cityId = call.getString("cityId") { params["cityId"] = cityId }
        // Also accept arbitrary string map under "params"
        if let extra = call.getObject("params") {
            for (k, v) in extra {
                if let s = v as? String { params[k] = s }
                else if let n = v as? NSNumber { params[k] = n.stringValue }
            }
        }
        guard !params.isEmpty else {
            call.reject("action required")
            return
        }
        Task {
            do {
                let json = try await EtubuTrafikAPI.get(params: params)
                call.resolve(json)
            } catch {
                call.reject(error.localizedDescription)
            }
        }
    }

    @objc func trafikPost(_ call: CAPPluginCall) {
        var body: [String: Any] = [:]
        if let obj = call.getObject("body") {
            body = obj
        } else {
            for (k, v) in call.options {
                let key = String(describing: k)
                if key == "action" { continue }
                body[key] = v
            }
            if let action = call.getString("action") { body["action"] = action }
        }
        if body["action"] == nil { body["action"] = "createRoute" }
        Task {
            do {
                let json = try await EtubuTrafikAPI.postCreateRoute(body: body)
                call.resolve(json)
            } catch {
                call.reject(error.localizedDescription)
            }
        }
    }

    @objc func obdBleState(_ call: CAPPluginCall) {
        call.resolve(obdBle.statePayload())
    }

    @available(iOS 15.0, *)
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    enum StoreError: Error {
        case failedVerification
    }
}

private final class AppleSignInSession: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let anchor: ASPresentationAnchor
    private let completion: ([String: Any]) -> Void
    private var controller: ASAuthorizationController?

    init(anchor: ASPresentationAnchor, completion: @escaping ([String: Any]) -> Void) {
        self.anchor = anchor
        self.completion = completion
    }

    func start() {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        controller.performRequests()
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        anchor
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            completion(["ok": false, "error": "invalid credential"])
            return
        }
        var payload: [String: Any] = [
            "ok": true,
            "user": credential.user,
        ]
        if let email = credential.email, !email.isEmpty {
            payload["email"] = email
        }
        if let token = credential.identityToken, let tokenStr = String(data: token, encoding: .utf8) {
            payload["identityToken"] = tokenStr
        }
        completion(payload)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let ns = error as NSError
        if ns.code == ASAuthorizationError.canceled.rawValue {
            completion(["ok": false, "error": "cancelled"])
        } else {
            completion(["ok": false, "error": error.localizedDescription])
        }
    }
}
