import UIKit
import Capacitor
import AVFoundation

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    /// When true, lifecycle must not drop back to ambient (kills EV / alert audio).
    static var driveAudioActive = false
    /// Avoid racing Live Activity end/start across launch + becomeActive.
    private static var liveActivityBootstrapped = false

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        configureAudioSession(quality: true)
        Self.installAudioRouteObservers()
        // Paint every known window immediately — Cap shell is near-black by default.
        let canvas = EtubuRuntimeProfile.canvasUIColor
        if let window {
            window.backgroundColor = canvas
            window.rootViewController?.view.backgroundColor = canvas
        }
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for w in scene.windows {
                w.backgroundColor = canvas
                w.rootViewController?.view.backgroundColor = canvas
            }
        }
        // Overlay cluster ASAP (separate UIWindow — never trapped under Cap/WKWebView).
        EtubuClusterPresenter.shared.installOverCapacitor()
        DispatchQueue.main.async {
            EtubuRuntimeProfile.hideLingeringSplashOverlays()
            EtubuClusterPresenter.shared.installOverCapacitor()
        }
        for delay in [0.1, 0.3, 0.7, 1.4, 2.5] as [Double] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                EtubuRuntimeProfile.hideLingeringSplashOverlays()
                EtubuClusterPresenter.shared.installOverCapacitor()
            }
        }
        if #available(iOS 16.2, *) {
            Task { @MainActor in
                await EtubuLiveActivityController.end()
                Self.liveActivityBootstrapped = true
            }
        } else {
            Self.liveActivityBootstrapped = true
        }
        // Bildirim merkezi yalnızca kullanıcı “Araça binince bildir” açınca kurulur —
        // erken UNUserNotificationCenter erişimi iOS’ta izin diyaloğunu tetikleyebiliyor.
        // EtubuVehicleLaunchNotifier.shared.configure() — ertelendi
        return true
    }

    /// Alert duck must not be overwritten by Live Activity / mix-mode reasserts.
    private static var alertDuckActive = false
    private static var audioObserversInstalled = false

    static var storedMixMode: String {
        (UserDefaults.standard.string(forKey: "etubu.cluster.mixMode") ?? "blend").lowercased()
    }

    /// Car Bluetooth / CarPlay / AirPlay — A2DP will not mix a second stream unless we duck.
    static func isCarMediaRoute(_ session: AVAudioSession = .sharedInstance()) -> Bool {
        session.currentRoute.outputs.contains { port in
            switch port.portType {
            case .bluetoothA2DP, .bluetoothHFP, .carAudio, .airPlay:
                return true
            default:
                return false
            }
        }
    }

    private func configureAudioSession(quality: Bool = false) {
        _ = quality
        if Self.driveAudioActive {
            Self.activateDriveAudioSession()
            return
        }
        Self.activateSilentSafeSession()
    }

    /// EV / cabin mix: Music/YouTube stays on the same Bluetooth route; we duck slightly so
    /// A2DP actually carries Etubu (mix-only leaves us on the phone speaker).
    static func activateDriveAudioSession() {
        if alertDuckActive { return }
        driveAudioActive = true
        let mix = storedMixMode
        if mix == "solo" {
            applyPlayback(
                mode: .default,
                options: [.allowBluetoothA2DP, .allowAirPlay],
                quality: true
            )
        } else {
            applyPlayback(
                mode: .default,
                options: [.mixWithOthers, .duckOthers, .allowBluetoothA2DP, .allowAirPlay],
                quality: true
            )
        }
        EtubuNativeDriveAudio.shared.resumeIfNeeded()
    }

    /// Warn TTS / beeps over car Bluetooth while Music/YouTube plays.
    /// `voicePrompt` follows the now-playing route (A2DP / CarPlay). Do not deactivate after.
    static func activateAlertDuckSession() {
        driveAudioActive = true
        alertDuckActive = true
        let overMusic = UserDefaults.standard.object(forKey: "etubu.cluster.alertOverMusic") as? Bool ?? true
        if overMusic {
            applyPlayback(
                mode: .voicePrompt,
                options: [.duckOthers, .mixWithOthers, .allowBluetoothA2DP, .allowAirPlay],
                quality: false
            )
        } else {
            applyPlayback(
                mode: .voicePrompt,
                options: [.mixWithOthers, .allowBluetoothA2DP, .allowAirPlay],
                quality: false
            )
        }
    }

    /// Restore EV mix without yielding the Bluetooth route (`setActive(false)` drops A2DP).
    static func deactivateAlertDuckSession() {
        alertDuckActive = false
        guard driveAudioActive else {
            activateSilentSafeSession()
            return
        }
        activateDriveAudioSession()
    }

    @discardableResult
    private static func applyPlayback(
        mode: AVAudioSession.Mode,
        options: AVAudioSession.CategoryOptions,
        quality: Bool
    ) -> Bool {
        let session = AVAudioSession.sharedInstance()
        let attempts: [AVAudioSession.CategoryOptions] = [
            options,
            options.union([.mixWithOthers, .duckOthers]),
            [.mixWithOthers, .duckOthers, .allowBluetoothA2DP],
            [.duckOthers, .allowBluetoothA2DP, .allowAirPlay],
            [.mixWithOthers, .allowBluetoothA2DP, .allowAirPlay],
        ]
        var lastError: Error?
        for opts in attempts {
            do {
                try session.setCategory(.playback, mode: mode, options: opts)
                if quality {
                    try session.setPreferredSampleRate(48_000)
                    try session.setPreferredIOBufferDuration(0.01)
                }
                try session.setActive(true, options: [])
                return true
            } catch {
                lastError = error
            }
        }
        if let lastError {
            print("ETUBU audio session:", lastError)
        }
        return false
    }

    private static func installAudioRouteObservers() {
        guard !audioObserversInstalled else { return }
        audioObserversInstalled = true
        let nc = NotificationCenter.default
        nc.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            reassertAfterRouteOrInterruption()
        }
        nc.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { note in
            handleAudioInterruption(note)
        }
        nc.addObserver(
            forName: AVAudioSession.silenceSecondaryAudioHintNotification,
            object: nil,
            queue: .main
        ) { _ in
            // Music wants secondary apps silent — rejoin with duck instead of going quiet.
            reassertAfterRouteOrInterruption()
        }
    }

    private static func handleAudioInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            // Music/YouTube took A2DP. Rejoin on the same route after a beat.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                reassertAfterRouteOrInterruption()
            }
        case .ended:
            reassertAfterRouteOrInterruption()
        @unknown default:
            break
        }
    }

    private static var lastReassertAt = Date.distantPast

    private static func reassertAfterRouteOrInterruption() {
        guard driveAudioActive else { return }
        let now = Date()
        if now.timeIntervalSince(lastReassertAt) < 0.15 { return }
        lastReassertAt = now
        if alertDuckActive {
            activateAlertDuckSession()
        } else {
            activateDriveAudioSession()
        }
    }

    /// Legacy aliases — prefer activateAlertDuckSession / deactivateAlertDuckSession.
    static func activateWarnAudioSession() { activateAlertDuckSession() }
    static func restoreDriveAudioAfterWarn() { deactivateAlertDuckSession() }

    static func activateSilentSafeSession() {
        guard !driveAudioActive else {
            activateDriveAudioSession()
            return
        }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .ambient,
                mode: .default,
                options: [.mixWithOthers, .allowBluetoothA2DP, .allowAirPlay]
            )
            try session.setActive(true)
        } catch {
            print("ETUBU audio session ambient:", error)
        }
    }

    static func endDriveAudioSession() {
        driveAudioActive = false
        activateSilentSafeSession()
    }

    func applicationWillResignActive(_ application: UIApplication) {
        if !Self.driveAudioActive {
            Self.activateSilentSafeSession()
        }
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        if Self.driveAudioActive {
            Self.activateDriveAudioSession()
        } else {
            Self.activateSilentSafeSession()
        }
        // Dynamic Island: hareket VEYA aktif app rotası — park+rota yoksa kapat.
        // Aligns with EtubuLiveActivityController.isDriveSessionAllowed.
        if #available(iOS 16.2, *) {
            let t = EtubuVehicleTelemetry.shared
            let keepIsland = EtubuDemoDrive.isActive || t.kmh >= 3 || t.routeActive
            if keepIsland {
                EtubuLiveActivityController.ensureAudioSession(mixWithOthers: true)
                EtubuLiveActivityController.startSilentKeepalive()
                Task { await EtubuLiveActivityController.publishCurrent() }
            } else {
                EtubuLiveActivityController.stopSilentKeepalive()
                EtubuLiveActivityController.endAllNow()
            }
        }
        var taskId: UIBackgroundTaskIdentifier = .invalid
        taskId = application.beginBackgroundTask(withName: "etubu.keepDriveAlive") {
            if taskId != .invalid {
                application.endBackgroundTask(taskId)
                taskId = .invalid
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
            if taskId != .invalid {
                application.endBackgroundTask(taskId)
                taskId = .invalid
            }
            // BG task bitince: yalnızca gerçek park + rota yoksa Island’ı kapat.
            if #available(iOS 16.2, *) {
                let t = EtubuVehicleTelemetry.shared
                let keepIsland = EtubuDemoDrive.isActive || t.kmh >= 3 || t.routeActive
                if !keepIsland {
                    EtubuLiveActivityController.endAllNow()
                }
            }
        }
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        configureAudioSession(quality: true)
        if #available(iOS 16.2, *) {
            // Keepalive arka plan audio’sunu bırak; LA sürüşte devam edebilir.
            EtubuLiveActivityController.stopSilentKeepalive()
            Task { await EtubuLiveActivityController.publishCurrent() }
        }
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        configureAudioSession(quality: true)
        EtubuRuntimeProfile.hideLingeringSplashOverlays()
        EtubuClusterPresenter.shared.installOverCapacitor()
        // Premium köprüsünü taze tut — Cap “kilitli” yanılmasın.
        Task { @MainActor in
            EtubuClusterAudioBridge.setPremium(EtubuPremiumManager.shared.isPremium)
            await EtubuPremiumManager.shared.refreshEntitlementQuietly()
        }
        // Araç bağlantısı yalnızca uygulama açılışında (startCore → bootstrap).
        // becomeActive’de yeniden bağlanma / koparma yok.
        if #available(iOS 16.2, *) {
            Task { await EtubuLiveActivityController.publishCurrent() }
        }
    }

    func applicationWillTerminate(_ application: UIApplication) {
        if #available(iOS 16.2, *) {
            EtubuLiveActivityController.endAllNow()
        }
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        // Cluster + Cap: all four edges so the UI always faces the user.
        .all
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if connectingSceneSession.role == .carTemplateApplication {
            let config = UISceneConfiguration(name: "EtubuCarPlay", sessionRole: connectingSceneSession.role)
            config.delegateClass = EtubuCarPlaySceneDelegate.self
            return config
        }
        return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        return ApplicationDelegateProxy.shared.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }
}
