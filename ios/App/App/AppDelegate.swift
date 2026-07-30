import UIKit
import Capacitor
import AVFoundation

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    /// When true, lifecycle must not drop back to ambient (kills EV / alert audio).
    static var driveAudioActive = false

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Do not wipe entire UserDefaults — that breaks Cap plugins and pairing recovery.
        // VIN lives in Keychain; ephemeral prefs are cleared from web storage in cluster onAppear.
        configureAudioSession(quality: true)
        if #available(iOS 16.2, *) {
            Task { await EtubuLiveActivityController.end() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            EtubuClusterPresenter.shared.installOverCapacitor()
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
        // Keep drive session if EV sound is on — only duck via mixWithOthers.
        if !Self.driveAudioActive {
            Self.activateSilentSafeSession()
        }
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        if !Self.driveAudioActive {
            Self.activateSilentSafeSession()
        }
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        configureAudioSession(quality: true)
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        configureAudioSession(quality: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            EtubuTeslaBleSession.shared.bootstrapIfPossible()
        }
    }

    func applicationWillTerminate(_ application: UIApplication) {
        if #available(iOS 16.2, *) {
            Task { await EtubuLiveActivityController.end() }
        }
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        return ApplicationDelegateProxy.shared.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }
}
