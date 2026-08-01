import Foundation
import UIKit
#if canImport(Metal)
import Metal
#endif

/// Simulator / memory / Low Power–aware budgets so cluster never paints a dead black frame
/// and cutout FX stay within a sustainable density.
enum EtubuRuntimeProfile {
    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    /// Stitchable Metal on Simulator (and missing metallib) often paints the layer solid black.
    static var allowMetalCutoutShaders: Bool {
        guard !isSimulator else { return false }
        #if canImport(Metal)
        return MTLCreateSystemDefaultDevice() != nil
        #else
        return false
        #endif
    }

    /// RealityKit / ARView particle overlay — black or stalled on Simulator.
    static var allowRealityKitCutout: Bool { !isSimulator }

    /// Canvas particle / field density (0.35…1).
    static var fxDensity: CGFloat {
        if isSimulator { return 0.40 }
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return 0.55 }
        let mem = ProcessInfo.processInfo.physicalMemory
        if mem < 3_500_000_000 { return 0.50 }
        if mem < 5_500_000_000 { return 0.72 }
        if mem < 7_500_000_000 { return 0.88 }
        return 1.0
    }

    static func fxFrameInterval(idle: Bool) -> Double {
        if isSimulator { return idle ? 1.0 / 8.0 : 1.0 / 12.0 }
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            return idle ? 1.0 / 10.0 : 1.0 / 14.0
        }
        return idle ? 1.0 / 12.0 : 1.0 / 24.0
    }

    /// Prefer themed navy over pure black so empty shells never look “crashed”.
    static let canvasUIColor = UIColor(red: 0.04, green: 0.09, blue: 0.16, alpha: 1)

    /// Tear down leftover Cap splash overlays that can sit above the SwiftUI cluster.
    static func hideLingeringSplashOverlays() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for window in scenes.flatMap(\.windows) {
            hideSplash(in: window)
        }
    }

    private static func hideSplash(in view: UIView) {
        let name = NSStringFromClass(type(of: view))
        if name.localizedCaseInsensitiveContains("splash") {
            view.isHidden = true
            view.alpha = 0
            view.removeFromSuperview()
            return
        }
        for sub in view.subviews {
            hideSplash(in: sub)
        }
    }
}
