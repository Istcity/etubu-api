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
        // Install cluster ASAP — do NOT block RunLoop or fire-and-forget end that races start.
        DispatchQueue.main.async {
            EtubuClusterPresenter.shared.installOverCapacitor()
        }
        for delay in [0.2, 0.5, 1.0] as [Double] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                EtubuClusterPresenter.shared.installOverCapacitor()
            }
        }
        // Clean leftover LA from prior process, then allow cluster to start one.
        if #available(iOS 16.2, *) {
            Task { @MainActor in
                await EtubuLiveActivityController.end()
                Self.liveActivityBootstrapped = true
            }
        } else {
            Self.liveActivityBootstrapped = true
        }
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
            // Ön plana dönünce Island + LA hemen bitsin
            EtubuLiveActivityController.stopSilentKeepalive()
            EtubuLiveActivityController.endAllNow()
        }
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        configureAudioSession(quality: true)
        EtubuClusterPresenter.shared.installOverCapacitor()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            Task { @MainActor in
                EtubuTeslaBleSession.shared.bootstrapIfPossible()
            }
        }
        // Foreground’da LA yok — publish/start yok
        if #available(iOS 16.2, *) {
            EtubuLiveActivityController.endAllNow()
        }
    }

    func applicationWillTerminate(_ application: UIApplication) {
        if #available(iOS 16.2, *) {
            EtubuLiveActivityController.endAllNow()
        }
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        return ApplicationDelegateProxy.shared.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }
}
