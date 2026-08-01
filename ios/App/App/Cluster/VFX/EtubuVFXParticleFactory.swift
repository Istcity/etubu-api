import Foundation
import RealityKit
import UIKit
import simd

/// Builds RealityKit `ParticleEmitterComponent` stacks for each `EtubuVFXType`.
/// Requires iOS 18+ (`ParticleEmitterComponent`).
@available(iOS 18.0, *)
enum EtubuVFXParticleFactory {

    /// Root camera-anchor entity: invisible capsule emitter + optional lights / debris.
    static func makeEffectEntity(
        type: EtubuVFXType,
        shapeSize: SIMD3<Float>,
        intensity: Float,
        budget: Float
    ) -> Entity {
        let root = Entity()
        root.name = "EtubuVFX.\(type.rawValue)"

        // Global soft cap — keeps Island FX vivid without thrashing GPU / thermal.
        let i = min(1.0, intensity) * 0.72
        let b = budget * 0.82

        let primary = Entity()
        primary.name = "primary"
        primary.components.set(configure(type: type, shapeSize: shapeSize, intensity: i, budget: b))
        root.addChild(primary)

        if let secondary = secondaryEmitter(type: type, shapeSize: shapeSize, intensity: i, budget: b) {
            let child = Entity()
            child.name = "secondary"
            child.components.set(secondary)
            root.addChild(child)
        }

        if let light = emissionLight(for: type, intensity: i) {
            root.addChild(light)
        }

        if type == .patlama || type == .yanardag || type == .havaFisek {
            let debris = Entity()
            debris.name = "debris"
            debris.components.set(debrisEmitter(type: type, shapeSize: shapeSize, intensity: i, budget: b))
            root.addChild(debris)
        }

        return root
    }

    // MARK: - Per-effect configuration

    static func configure(
        type: EtubuVFXType,
        shapeSize: SIMD3<Float>,
        intensity: Float,
        budget: Float
    ) -> ParticleEmitterComponent {
        switch type {
        case .elektrik: return elektrik(shapeSize: shapeSize, intensity: intensity, budget: budget)
        case .ates: return ates(shapeSize: shapeSize, intensity: intensity, budget: budget)
        case .duman: return duman(shapeSize: shapeSize, intensity: intensity, budget: budget)
        case .patlama: return patlama(shapeSize: shapeSize, intensity: intensity, budget: budget)
        case .dalga: return dalga(shapeSize: shapeSize, intensity: intensity, budget: budget)
        case .su: return su(shapeSize: shapeSize, intensity: intensity, budget: budget)
        case .ruzgar: return ruzgar(shapeSize: shapeSize, intensity: intensity, budget: budget)
        case .hiz: return hiz(shapeSize: shapeSize, intensity: intensity, budget: budget)
        case .havaFisek: return havaFisek(shapeSize: shapeSize, intensity: intensity, budget: budget)
        case .yildizKaymasi: return yildizKaymasi(shapeSize: shapeSize, intensity: intensity, budget: budget)
        case .yanardag: return yanardag(shapeSize: shapeSize, intensity: intensity, budget: budget)
        }
    }

    // MARK: 1 — ELEKTRİK

    private static func elektrik(shapeSize: SIMD3<Float>, intensity: Float, budget: Float) -> ParticleEmitterComponent {
        var p = baseRimEmitter(shapeSize: shapeSize)
        p.birthDirection = .normal
        p.speed = 0.55 + intensity * 0.9
        p.speedVariation = 0.35
        p.mainEmitter.birthRate = 90 * intensity * budget
        p.mainEmitter.lifeSpan = 0.18
        p.mainEmitter.lifeSpanVariation = 0.08
        p.mainEmitter.size = 0.0022
        p.mainEmitter.sizeVariation = 0.0012
        p.mainEmitter.spreadingAngle = 0.55
        p.mainEmitter.acceleration = [0, 0, 0]
        p.mainEmitter.color = .evolving(
            start: .single(UIColor(red: 0.55, green: 0.75, blue: 1, alpha: 1)),
            end: .single(UIColor(red: 0.35, green: 0.15, blue: 0.95, alpha: 0))
        )
        p.mainEmitter.isLightingEnabled = true
        return p
    }

    // MARK: 2 — ATEŞ

    private static func ates(shapeSize: SIMD3<Float>, intensity: Float, budget: Float) -> ParticleEmitterComponent {
        var p = baseRimEmitter(shapeSize: shapeSize)
        p.birthDirection = .normal
        p.speed = 0.12 + intensity * 0.18
        p.speedVariation = 0.08
        p.mainEmitter.birthRate = 140 * intensity * budget
        p.mainEmitter.lifeSpan = 0.85
        p.mainEmitter.lifeSpanVariation = 0.35
        p.mainEmitter.size = 0.008
        p.mainEmitter.sizeVariation = 0.004
        p.mainEmitter.spreadingAngle = 0.7
        p.mainEmitter.acceleration = [0, 0.22, 0]
        p.mainEmitter.dampingFactor = 0.35
        p.mainEmitter.color = .evolving(
            start: .single(UIColor(red: 1, green: 0.95, blue: 0.55, alpha: 1)),
            end: .single(UIColor(red: 1, green: 0.15, blue: 0.02, alpha: 0))
        )
        p.mainEmitter.isLightingEnabled = true
        return p
    }

    // MARK: 3 — DUMAN

    private static func duman(shapeSize: SIMD3<Float>, intensity: Float, budget: Float) -> ParticleEmitterComponent {
        var p = baseRimEmitter(shapeSize: shapeSize)
        p.birthDirection = .normal
        p.speed = 0.04 + intensity * 0.06
        p.speedVariation = 0.03
        p.mainEmitter.birthRate = 55 * intensity * budget
        p.mainEmitter.lifeSpan = 2.4
        p.mainEmitter.lifeSpanVariation = 0.8
        p.mainEmitter.size = 0.018
        p.mainEmitter.sizeVariation = 0.01
        p.mainEmitter.spreadingAngle = 1.1
        p.mainEmitter.acceleration = [0, 0.06, 0]
        p.mainEmitter.dampingFactor = 0.55
        p.mainEmitter.color = .evolving(
            start: .single(UIColor(white: 0.55, alpha: 0.55)),
            end: .single(UIColor(white: 0.2, alpha: 0))
        )
        return p
    }

    // MARK: 4 — PATLAMA

    private static func patlama(shapeSize: SIMD3<Float>, intensity: Float, budget: Float) -> ParticleEmitterComponent {
        var p = baseRimEmitter(shapeSize: shapeSize)
        p.birthDirection = .normal
        p.burstCount = Int(48 + 40 * intensity * budget)
        p.burstCountVariation = 12
        p.speed = 0.9 + intensity * 1.2
        p.speedVariation = 0.5
        p.mainEmitter.birthRate = 12 * intensity * budget
        p.mainEmitter.lifeSpan = 0.55
        p.mainEmitter.lifeSpanVariation = 0.2
        p.mainEmitter.size = 0.01
        p.mainEmitter.sizeVariation = 0.006
        p.mainEmitter.spreadingAngle = .pi
        p.mainEmitter.acceleration = [0, -0.15, 0]
        p.mainEmitter.color = .evolving(
            start: .single(UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1)),
            end: .single(UIColor(red: 0.6, green: 0.05, blue: 0, alpha: 0))
        )
        p.mainEmitter.isLightingEnabled = true
        return p
    }

    // MARK: 5 — DALGA

    private static func dalga(shapeSize: SIMD3<Float>, intensity: Float, budget: Float) -> ParticleEmitterComponent {
        var p = baseRimEmitter(shapeSize: shapeSize)
        p.birthDirection = .normal
        p.speed = 0.08 + intensity * 0.12
        p.speedVariation = 0.04
        p.mainEmitter.birthRate = 100 * intensity * budget
        p.mainEmitter.lifeSpan = 1.1
        p.mainEmitter.lifeSpanVariation = 0.35
        p.mainEmitter.size = 0.007
        p.mainEmitter.sizeVariation = 0.003
        p.mainEmitter.spreadingAngle = 0.85
        p.mainEmitter.acceleration = [0, -0.04, 0]
        p.mainEmitter.color = .evolving(
            start: .single(UIColor(red: 0.75, green: 0.92, blue: 1, alpha: 0.9)),
            end: .single(UIColor(red: 0.1, green: 0.35, blue: 0.7, alpha: 0))
        )
        return p
    }

    // MARK: 6 — SU

    private static func su(shapeSize: SIMD3<Float>, intensity: Float, budget: Float) -> ParticleEmitterComponent {
        var p = baseRimEmitter(shapeSize: shapeSize)
        p.birthDirection = .normal
        p.speed = 0.2 + intensity * 0.35
        p.speedVariation = 0.15
        p.mainEmitter.birthRate = 120 * intensity * budget
        p.mainEmitter.lifeSpan = 0.7
        p.mainEmitter.lifeSpanVariation = 0.25
        p.mainEmitter.size = 0.0035
        p.mainEmitter.sizeVariation = 0.002
        p.mainEmitter.spreadingAngle = 0.95
        p.mainEmitter.acceleration = [0, -0.55, 0]
        p.mainEmitter.dampingFactor = 0.15
        p.mainEmitter.color = .evolving(
            start: .single(UIColor(red: 0.85, green: 0.95, blue: 1, alpha: 0.95)),
            end: .single(UIColor(red: 0.3, green: 0.55, blue: 0.9, alpha: 0))
        )
        p.mainEmitter.isLightingEnabled = true
        return p
    }

    // MARK: 7 — RÜZGAR

    private static func ruzgar(shapeSize: SIMD3<Float>, intensity: Float, budget: Float) -> ParticleEmitterComponent {
        var p = baseRimEmitter(shapeSize: shapeSize)
        p.birthDirection = .normal
        p.emissionDirection = [1, 0.15, 0]
        p.speed = 0.25 + intensity * 0.45
        p.speedVariation = 0.2
        p.mainEmitter.birthRate = 70 * intensity * budget
        p.mainEmitter.lifeSpan = 1.0
        p.mainEmitter.lifeSpanVariation = 0.4
        p.mainEmitter.size = 0.004
        p.mainEmitter.sizeVariation = 0.0025
        p.mainEmitter.spreadingAngle = 0.4
        p.mainEmitter.acceleration = [0.08, 0.02, 0]
        p.mainEmitter.dampingFactor = 0.25
        p.mainEmitter.color = .evolving(
            start: .single(UIColor(white: 0.92, alpha: 0.45)),
            end: .single(UIColor(white: 0.7, alpha: 0))
        )
        return p
    }

    // MARK: 8 — HIZ

    private static func hiz(shapeSize: SIMD3<Float>, intensity: Float, budget: Float) -> ParticleEmitterComponent {
        var p = baseRimEmitter(shapeSize: shapeSize)
        p.birthDirection = .normal
        p.speed = 1.4 + intensity * 2.2
        p.speedVariation = 0.6
        p.mainEmitter.birthRate = 160 * intensity * budget
        p.mainEmitter.lifeSpan = 0.22
        p.mainEmitter.lifeSpanVariation = 0.08
        p.mainEmitter.size = 0.002
        p.mainEmitter.sizeVariation = 0.001
        p.mainEmitter.spreadingAngle = 0.18
        p.mainEmitter.acceleration = [0, 0, 0]
        p.mainEmitter.stretchFactor = 8
        p.mainEmitter.blendMode = .additive
        p.mainEmitter.color = .evolving(
            start: .single(UIColor(red: 0.7, green: 0.95, blue: 1, alpha: 1)),
            end: .single(UIColor(red: 0.2, green: 0.4, blue: 1, alpha: 0))
        )
        p.mainEmitter.isLightingEnabled = true
        return p
    }

    // MARK: 9 — HAVA FİŞEK

    private static func havaFisek(shapeSize: SIMD3<Float>, intensity: Float, budget: Float) -> ParticleEmitterComponent {
        var p = baseRimEmitter(shapeSize: shapeSize)
        p.birthDirection = .normal
        p.burstCount = Int(36 + 28 * intensity * budget)
        p.burstCountVariation = 10
        p.speed = 0.35 + intensity * 0.55
        p.speedVariation = 0.2
        p.mainEmitter.birthRate = 18 * intensity * budget
        p.mainEmitter.lifeSpan = 0.9
        p.mainEmitter.lifeSpanVariation = 0.3
        p.mainEmitter.size = 0.005
        p.mainEmitter.sizeVariation = 0.003
        p.mainEmitter.spreadingAngle = .pi
        p.mainEmitter.acceleration = [0, -0.25, 0]
        p.mainEmitter.color = .evolving(
            start: .single(UIColor.systemPink),
            end: .single(UIColor.systemYellow.withAlphaComponent(0))
        )
        p.spawnOccasion = .onDeath
        p.spawnedEmitter = fireworkShellSparks()
        p.mainEmitter.isLightingEnabled = true
        return p
    }

    // MARK: 10 — YILDIZ KAYMASI

    private static func yildizKaymasi(shapeSize: SIMD3<Float>, intensity: Float, budget: Float) -> ParticleEmitterComponent {
        var p = baseRimEmitter(shapeSize: shapeSize)
        p.birthDirection = .normal
        p.emissionDirection = normalize([0.85, -0.35, 0.1])
        p.speed = 0.7 + intensity * 1.1
        p.speedVariation = 0.15
        p.mainEmitter.birthRate = 45 * intensity * budget
        p.mainEmitter.lifeSpan = 0.55
        p.mainEmitter.lifeSpanVariation = 0.15
        p.mainEmitter.size = 0.0045
        p.mainEmitter.sizeVariation = 0.002
        p.mainEmitter.spreadingAngle = 0.12
        p.mainEmitter.stretchFactor = 6
        p.mainEmitter.blendMode = .additive
        p.mainEmitter.acceleration = [0, -0.05, 0]
        p.mainEmitter.color = .evolving(
            start: .single(UIColor(red: 1, green: 0.98, blue: 0.85, alpha: 1)),
            end: .single(UIColor(red: 1, green: 0.45, blue: 0.1, alpha: 0))
        )
        p.mainEmitter.isLightingEnabled = true
        return p
    }

    // MARK: 11 — YANARDAĞ

    private static func yanardag(shapeSize: SIMD3<Float>, intensity: Float, budget: Float) -> ParticleEmitterComponent {
        var p = baseRimEmitter(shapeSize: shapeSize)
        p.birthDirection = .normal
        p.speed = 0.35 + intensity * 0.55
        p.speedVariation = 0.25
        p.mainEmitter.birthRate = 110 * intensity * budget
        p.mainEmitter.lifeSpan = 1.2
        p.mainEmitter.lifeSpanVariation = 0.4
        p.mainEmitter.size = 0.009
        p.mainEmitter.sizeVariation = 0.005
        p.mainEmitter.spreadingAngle = 0.9
        p.mainEmitter.acceleration = [0, 0.35, 0]
        p.mainEmitter.dampingFactor = 0.2
        p.mainEmitter.color = .evolving(
            start: .single(UIColor(red: 1, green: 0.55, blue: 0.08, alpha: 1)),
            end: .single(UIColor(red: 0.15, green: 0.05, blue: 0.02, alpha: 0))
        )
        p.mainEmitter.isLightingEnabled = true
        return p
    }

    // MARK: - Secondary layers

    private static func secondaryEmitter(
        type: EtubuVFXType,
        shapeSize: SIMD3<Float>,
        intensity: Float,
        budget: Float
    ) -> ParticleEmitterComponent? {
        switch type {
        case .ates:
            var sparks = baseRimEmitter(shapeSize: shapeSize * 0.92)
            sparks.speed = 0.3
            sparks.speedVariation = 0.2
            sparks.mainEmitter.birthRate = 40 * intensity * budget
            sparks.mainEmitter.lifeSpan = 0.55
            sparks.mainEmitter.size = 0.002
            sparks.mainEmitter.acceleration = [0, 0.4, 0]
            sparks.mainEmitter.color = .evolving(
                start: .single(UIColor(red: 1, green: 0.9, blue: 0.4, alpha: 1)),
                end: .single(UIColor(red: 1, green: 0.3, blue: 0, alpha: 0))
            )
            return sparks
        case .duman:
            var ash = baseRimEmitter(shapeSize: shapeSize * 1.05)
            ash.speed = 0.03
            ash.mainEmitter.birthRate = 25 * intensity * budget
            ash.mainEmitter.lifeSpan = 3.0
            ash.mainEmitter.size = 0.025
            ash.mainEmitter.acceleration = [0, 0.04, 0]
            ash.mainEmitter.color = .evolving(
                start: .single(UIColor(white: 0.35, alpha: 0.35)),
                end: .single(UIColor(white: 0.1, alpha: 0))
            )
            return ash
        case .dalga:
            var foam = baseRimEmitter(shapeSize: shapeSize * 1.02)
            foam.speed = 0.05
            foam.mainEmitter.birthRate = 50 * intensity * budget
            foam.mainEmitter.lifeSpan = 0.8
            foam.mainEmitter.size = 0.005
            foam.mainEmitter.color = .evolving(
                start: .single(UIColor.white.withAlphaComponent(0.85)),
                end: .single(UIColor.white.withAlphaComponent(0))
            )
            return foam
        case .yanardag:
            var ash = baseRimEmitter(shapeSize: shapeSize * 1.1)
            ash.speed = 0.08
            ash.mainEmitter.birthRate = 60 * intensity * budget
            ash.mainEmitter.lifeSpan = 2.2
            ash.mainEmitter.size = 0.02
            ash.mainEmitter.acceleration = [0, 0.12, 0]
            ash.mainEmitter.color = .evolving(
                start: .single(UIColor(white: 0.12, alpha: 0.7)),
                end: .single(UIColor(white: 0.05, alpha: 0))
            )
            return ash
        case .yildizKaymasi:
            var tail = baseRimEmitter(shapeSize: shapeSize * 0.85)
            tail.emissionDirection = normalize([0.85, -0.35, 0.1])
            tail.speed = 0.5
            tail.mainEmitter.birthRate = 80 * intensity * budget
            tail.mainEmitter.lifeSpan = 0.35
            tail.mainEmitter.size = 0.002
            tail.mainEmitter.stretchFactor = 4
            tail.mainEmitter.blendMode = .additive
            tail.mainEmitter.color = .evolving(
                start: .single(UIColor(red: 1, green: 0.7, blue: 0.3, alpha: 0.8)),
                end: .single(UIColor(red: 0.4, green: 0.1, blue: 0, alpha: 0))
            )
            return tail
        case .elektrik:
            var corona = baseRimEmitter(shapeSize: shapeSize * 1.08)
            corona.speed = 0.15
            corona.mainEmitter.birthRate = 35 * intensity * budget
            corona.mainEmitter.lifeSpan = 0.25
            corona.mainEmitter.size = 0.006
            corona.mainEmitter.color = .evolving(
                start: .single(UIColor(red: 0.7, green: 0.5, blue: 1, alpha: 0.6)),
                end: .single(UIColor(red: 0.2, green: 0.05, blue: 0.6, alpha: 0))
            )
            return corona
        case .su:
            var mist = baseRimEmitter(shapeSize: shapeSize * 1.05)
            mist.speed = 0.06
            mist.mainEmitter.birthRate = 40 * intensity * budget
            mist.mainEmitter.lifeSpan = 1.0
            mist.mainEmitter.size = 0.01
            mist.mainEmitter.color = .evolving(
                start: .single(UIColor(red: 0.7, green: 0.85, blue: 1, alpha: 0.35)),
                end: .single(UIColor(white: 1, alpha: 0))
            )
            return mist
        default:
            return nil
        }
    }

    private static func debrisEmitter(
        type: EtubuVFXType,
        shapeSize: SIMD3<Float>,
        intensity: Float,
        budget: Float
    ) -> ParticleEmitterComponent {
        var p = baseRimEmitter(shapeSize: shapeSize * 0.9)
        p.birthDirection = .normal
        p.speed = 0.55 + intensity * 0.7
        p.speedVariation = 0.35
        p.mainEmitter.birthRate = (type == .patlama ? 35 : 22) * intensity * budget
        p.mainEmitter.lifeSpan = 1.1
        p.mainEmitter.size = 0.004
        p.mainEmitter.sizeVariation = 0.003
        p.mainEmitter.acceleration = [0, -0.8, 0]
        p.mainEmitter.spreadingAngle = 1.2
        p.mainEmitter.color = .evolving(
            start: .single(UIColor(red: 1, green: 0.4, blue: 0.05, alpha: 1)),
            end: .single(UIColor(red: 0.2, green: 0.05, blue: 0, alpha: 0))
        )
        if type == .patlama {
            p.burstCount = Int(24 * intensity * budget)
        }
        return p
    }

    private static func fireworkShellSparks() -> ParticleEmitterComponent.ParticleEmitter {
        var e = ParticleEmitterComponent.ParticleEmitter()
        e.birthRate = 80
        e.lifeSpan = 0.55
        e.lifeSpanVariation = 0.2
        e.size = 0.003
        e.sizeVariation = 0.0015
        e.spreadingAngle = .pi
        e.acceleration = [0, -0.4, 0]
        e.color = .evolving(
            start: .single(UIColor.systemCyan),
            end: .single(UIColor.systemOrange.withAlphaComponent(0))
        )
        return e
    }

    // MARK: - Shared helpers

    private static func baseRimEmitter(shapeSize: SIMD3<Float>) -> ParticleEmitterComponent {
        var p = ParticleEmitterComponent()
        // Torus hugs the Island / notch perimeter (no capsule shape in RealityKit).
        p.emitterShape = .torus
        p.emitterShapeSize = shapeSize
        p.torusInnerRadius = max(0.002, min(shapeSize.x, shapeSize.y) * 0.28)
        p.birthLocation = .surface
        p.birthDirection = .normal
        p.isEmitting = true
        return p
    }

    private static func emissionLight(for type: EtubuVFXType, intensity: Float) -> Entity? {
        let colors: [EtubuVFXType: UIColor] = [
            .elektrik: UIColor(red: 0.4, green: 0.6, blue: 1, alpha: 1),
            .ates: UIColor(red: 1, green: 0.45, blue: 0.1, alpha: 1),
            .patlama: UIColor(red: 1, green: 0.7, blue: 0.3, alpha: 1),
            .havaFisek: UIColor(red: 1, green: 0.5, blue: 0.8, alpha: 1),
            .yildizKaymasi: UIColor(red: 1, green: 0.9, blue: 0.6, alpha: 1),
            .yanardag: UIColor(red: 1, green: 0.35, blue: 0.05, alpha: 1),
            .su: UIColor(red: 0.5, green: 0.75, blue: 1, alpha: 1),
            .hiz: UIColor(red: 0.5, green: 0.85, blue: 1, alpha: 1),
        ]
        guard let ui = colors[type] else { return nil }
        let light = PointLight()
        light.light.color = ui
        light.light.intensity = 8_000 + intensity * 28_000
        light.light.attenuationRadius = 0.45
        light.position = [0, 0, 0.02]
        return light
    }

    private static func normalize(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let len = simd_length(v)
        guard len > 1e-5 else { return [0, 1, 0] }
        return v / len
    }
}
