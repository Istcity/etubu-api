import SwiftUI

/// Applies Metal stitchable shaders to cutout / Island FX by theme.
enum EtubuVFXMetalEffects {
    enum Kind {
        case heat, electric, water, speed, smoke, sparkle
    }

    static func kind(for fx: EtubuCutoutFX) -> Kind {
        switch fx {
        case .ates, .patlama, .solarCorona: return .heat
        case .elektrik, .plazma, .yildirimMor, .buzKristali: return .electric
        case .okyanusDalga: return .water
        case .tunelCizgi, .warpHalka, .isikHuzmesi: return .speed
        case .duman: return .smoke
        default: return .sparkle
        }
    }
}

private struct EtubuCutoutMetalModifier: ViewModifier {
    let kind: EtubuVFXMetalEffects.Kind
    let time: Float
    let intensity: Float

    @ViewBuilder
    func body(content: Content) -> some View {
        let i = max(0.15, min(1.6, intensity))
        switch kind {
        case .heat:
            content
                .layerEffect(
                    ShaderLibrary.etubu_heat_layer(.float(time), .float(i)),
                    maxSampleOffset: CGSize(width: 10, height: 10)
                )
                .distortionEffect(
                    ShaderLibrary.etubu_heat_distortion(.float(time), .float(i * 0.85), .boundingRect),
                    maxSampleOffset: CGSize(width: 8, height: 8)
                )
        case .electric:
            content
                .colorEffect(
                    ShaderLibrary.etubu_electric_tint(.float(time), .float(i))
                )
                .distortionEffect(
                    ShaderLibrary.etubu_electric_jitter(.float(time), .float(i * 0.7), .boundingRect),
                    maxSampleOffset: CGSize(width: 5, height: 5)
                )
        case .water:
            content
                .colorEffect(
                    ShaderLibrary.etubu_water_tint(.float(time), .float(i))
                )
                .distortionEffect(
                    ShaderLibrary.etubu_water_ripple(.float(time), .float(i), .boundingRect),
                    maxSampleOffset: CGSize(width: 10, height: 10)
                )
        case .speed:
            content
                .layerEffect(
                    ShaderLibrary.etubu_speed_layer(.float(time), .float(i)),
                    maxSampleOffset: CGSize(width: 12, height: 2)
                )
        case .smoke:
            content
                .colorEffect(
                    ShaderLibrary.etubu_smoke_tint(.float(time), .float(i))
                )
        case .sparkle:
            content
                .colorEffect(
                    ShaderLibrary.etubu_sparkle_tint(.float(time), .float(i * 0.75))
                )
        }
    }
}

extension View {
    /// Theme-aware Metal post on cutout Canvas (iOS 17+ stitchable library).
    /// Simulator: no-op — stitchable Metal often paints the layer black / stalls UI.
    @ViewBuilder
    func etubuCutoutMetal(
        fx: EtubuCutoutFX,
        time: Double,
        intensity: CGFloat
    ) -> some View {
        #if targetEnvironment(simulator)
        self
        #else
        if EtubuRuntimeProfile.allowMetalCutoutShaders {
            modifier(
                EtubuCutoutMetalModifier(
                    kind: EtubuVFXMetalEffects.kind(for: fx),
                    time: Float(time),
                    intensity: Float(min(1.35, intensity))
                )
            )
        } else {
            self
        }
        #endif
    }
}
