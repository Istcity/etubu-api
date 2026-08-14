import UIKit
import AVFoundation

/// Orderly app shutdown: Live Activity → audio/warn → best-effort BLE → `exit(0)`.
///
/// Çıkış means **leave the app** (process quit), not “disconnect vehicle”.
/// Vehicle disconnect remains a separate Settings control (`disconnectTesla`).
///
/// Note: `exit(0)` can appear in Analytics / .ips as an abrupt termination.
/// That is intentional UX here — suspend-only felt broken and did not quit.
@MainActor
enum EtubuAppExit {
    private static var quitting = false

    static func quitFully() {
        guard !quitting else { return }
        quitting = true

        UIApplication.shared.isIdleTimerDisabled = false
        EtubuDemoDrive.shared.stop()
        EtubuWarnVoice.stopAll()
        EtubuClusterAudioBridge.setSoundEnabled(false, voice: "silent-mode")
        EtubuNativeDriveAudio.shared.stop()
        AppDelegate.driveAudioActive = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        if #available(iOS 16.2, *) {
            EtubuLiveActivityController.endAllNow()
        }

        // Fire-and-forget BLE pause — never block process quit on disconnect hang.
        Task { await EtubuTeslaBleSession.shared.disconnect() }

        Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            exit(0)
        }
    }
}
