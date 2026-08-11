import UIKit
import AVFoundation

/// Orderly app shutdown: Live Activity → BLE → audio → process exit.
@MainActor
enum EtubuAppExit {
    static func quitFully() {
        UIApplication.shared.isIdleTimerDisabled = false
        EtubuDemoDrive.shared.stop()
        EtubuClusterAudioBridge.setSoundEnabled(false, voice: "silent-mode")
        EtubuNativeDriveAudio.shared.stop()
        AppDelegate.driveAudioActive = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        if #available(iOS 16.2, *) {
            EtubuLiveActivityController.endAllNow()
        }
        Task {
            await EtubuTeslaBleSession.shared.disconnect()
            // Brief settle so LA/BLE teardown can flush before kill.
            try? await Task.sleep(nanoseconds: 350_000_000)
            await MainActor.run {
                exit(0)
            }
        }
    }
}
