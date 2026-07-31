import Foundation
import Combine
import CoreGraphics
import SwiftUI

/// Owns the active cutout VFX selection and camera-anchor frame (points → meters).
@MainActor
final class EtubuVFXManager: ObservableObject {
    static let shared = EtubuVFXManager()

    @Published var effect: EtubuVFXType = .elektrik
    @Published var intensity: Float = 0.5
    @Published var isActive: Bool = true
    /// Exact cutout capsule in **aura-local** points (same space as Canvas island).
    @Published private(set) var pillLocal: CGRect = .zero
    @Published private(set) var auraSize: CGSize = .zero
    @Published private(set) var performanceTier: EtubuVFXType.PerformanceTier = .standard

    /// 1 pt → meters in the RealityKit overlay (1 mm / pt keeps Island ~0.13 m wide).
    let metersPerPoint: Float = 0.001

    private init() {
        performanceTier = Self.detectTier()
    }

    func sync(theme: ClusterTheme, cutout: EtubuCameraCutout.Geometry, kmh: Int) {
        effect = .forTheme(theme)
        auraSize = cutout.aura.size
        pillLocal = CGRect(
            x: cutout.pill.minX - cutout.aura.minX,
            y: cutout.pill.minY - cutout.aura.minY,
            width: cutout.pill.width,
            height: cutout.pill.height
        )
        let drive = min(1, max(0, Float(kmh) / 130))
        intensity = 0.18 + drive * 0.82
        isActive = true
    }

    func deactivate() {
        isActive = false
        intensity = 0
    }

    /// Pill expanded by ≤ 0.5 cm rim buffer, converted to RealityKit meters (XY plane, Z forward).
    func emitterShapeSizeMeters() -> SIMD3<Float> {
        let buf = EtubuVFXType.rimBufferPoints
        let w = Float(max(1, pillLocal.width + buf * 2)) * metersPerPoint
        let h = Float(max(1, pillLocal.height + buf * 2)) * metersPerPoint
        let d = max(0.004, min(w, h) * 0.35)
        return [w, h, d]
    }

    /// Center of pill in aura-local meters, Y flipped for RealityKit (Y-up).
    func emitterPositionMeters() -> SIMD3<Float> {
        let ax = Float(auraSize.width) * metersPerPoint
        let ay = Float(auraSize.height) * metersPerPoint
        let cx = Float(pillLocal.midX) * metersPerPoint - ax * 0.5
        let cy = ay * 0.5 - Float(pillLocal.midY) * metersPerPoint
        return [cx, cy, 0]
    }

    var budgetScale: Float {
        performanceTier.rawValue
    }

    private static func detectTier() -> EtubuVFXType.PerformanceTier {
        #if targetEnvironment(simulator)
        return .standard
        #else
        let cores = ProcessInfo.processInfo.processorCount
        let mem = ProcessInfo.processInfo.physicalMemory
        if mem >= 8_000_000_000 && cores >= 6 { return .proMax }
        if mem >= 6_000_000_000 { return .pro }
        if mem >= 4_000_000_000 { return .standard }
        return .base
        #endif
    }
}
