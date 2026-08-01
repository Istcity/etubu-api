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

    private func configureAudioSession(quality: Bool = false) {
        if Self.driveAudioActive {
            Self.activateDriveAudioSession()
            return
        }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .ambient,
                mode: .default,
                options: [.mixWithOthers, .allowBluetoothA2DP, .allowAirPlay]
            )
            if quality {
                try session.setPreferredSampleRate(48_000)
                try session.setPreferredIOBufferDuration(0.01)
            }
            try session.setActive(true)
        } catch {
            print("ETUBU audio session bootstrap:", error)
        }
    }

    static func activateDriveAudioSession() {
        driveAudioActive = true
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers, .allowBluetoothA2DP, .allowAirPlay]
            )
            try session.setPreferredSampleRate(48_000)
            try session.setPreferredIOBufferDuration(0.01)
            try session.setActive(true, options: [])
        } catch {
            print("ETUBU audio session activate:", error)
        }
    }

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
        // Dynamic Island / Live Activity: yalnızca arka planda
        if #available(iOS 16.2, *) {
            EtubuLiveActivityController.ensureAudioSession(mixWithOthers: true)
            EtubuLiveActivityController.startSilentKeepalive()
            Task { await EtubuLiveActivityController.beginBackgroundSession() }
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
