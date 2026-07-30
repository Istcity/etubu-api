import UIKit
import Capacitor
import AVFoundation

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    /// When true, lifecycle must not drop back to ambient (kills EV / alert audio).
    static var driveAudioActive = false

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        configureAudioSession(quality: true)
        // Kill leftover Island/LA from a previous process before cluster can start a new one.
        Self.endLiveActivitySync()
        // Install cluster ASAP and keep retrying until the key window exists.
        DispatchQueue.main.async {
            EtubuClusterPresenter.shared.installOverCapacitor()
        }
        for delay in [0.15, 0.4, 0.8, 1.5] as [Double] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                EtubuClusterPresenter.shared.installOverCapacitor()
            }
        }
        return true
    }

    /// App starts in silent-safe mode (respects hardware mute switch).
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
                try session.setPreferredIOBufferDuration(0.005)
            }
            try session.setActive(true)
        } catch {
            print("ETUBU audio session bootstrap:", error)
        }
    }

    /// User enables drive audio explicitly — high quality playback path.
    static func activateDriveAudioSession() {
        driveAudioActive = true
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers, .duckOthers, .allowBluetoothA2DP, .allowAirPlay]
            )
            try session.setPreferredSampleRate(48_000)
            try session.setPreferredIOBufferDuration(0.005)
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
        if !Self.driveAudioActive {
            Self.activateSilentSafeSession()
        }
        // Leaving the app → dismiss Dynamic Island / Live Activity.
        var taskId: UIBackgroundTaskIdentifier = .invalid
        taskId = application.beginBackgroundTask(withName: "etubu.endLiveActivity") {
            if taskId != .invalid {
                application.endBackgroundTask(taskId)
                taskId = .invalid
            }
        }
        Self.endLiveActivityNow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if taskId != .invalid {
                application.endBackgroundTask(taskId)
                taskId = .invalid
            }
        }
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        configureAudioSession(quality: true)
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        configureAudioSession(quality: true)
        EtubuClusterPresenter.shared.installOverCapacitor()
        // Re-attempt Tesla BLE whenever app returns to foreground.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            Task { @MainActor in
                EtubuTeslaBleSession.shared.bootstrapIfPossible()
            }
        }
        // Restart Island after background end (if cluster already running).
        if #available(iOS 16.2, *) {
            Task { @MainActor in
                let t = EtubuVehicleTelemetry.shared
                _ = await EtubuLiveActivityController.start(
                    voice: "ETUBU",
                    kmh: t.kmh,
                    gear: t.gear,
                    rpm: t.rpm,
                    source: t.source == .none ? "idle" : t.source.rawValue
                )
                EtubuLiveActivityController.startSilentKeepalive()
            }
        }
    }

    func applicationWillTerminate(_ application: UIApplication) {
        Self.endLiveActivityNow()
    }

    /// Ends Island/LA without blocking the main thread (semaphore + Activity.end deadlocks).
    private static func endLiveActivityNow() {
        guard #available(iOS 16.2, *) else { return }
        EtubuLiveActivityController.endAllNow()
    }

    /// Launch-time cleanup of leftover activities from a previous process.
    private static func endLiveActivitySync() {
        endLiveActivityNow()
        // Brief yield so Activity.end can enqueue before UI starts a new LA.
        if Thread.isMainThread {
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        return ApplicationDelegateProxy.shared.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }
}
