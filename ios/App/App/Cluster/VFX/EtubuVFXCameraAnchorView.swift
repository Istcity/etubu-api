import SwiftUI
import RealityKit
import Combine

/// SwiftUI host that anchors RealityKit particle FX to the Dynamic Island / notch pill.
@available(iOS 18.0, *)
struct EtubuVFXCameraAnchorView: View {
    @ObservedObject var manager: EtubuVFXManager
    let kmh: Int
    let theme: ClusterTheme
    let cutout: EtubuCameraCutout.Geometry

    var body: some View {
        EtubuVFXRealityRepresentable(manager: manager)
            .frame(width: cutout.aura.width, height: cutout.aura.height)
            .allowsHitTesting(false)
            .opacity(Double(0.4 + manager.intensity * 0.6))
            .mask {
                let dx = (cutout.pill.midX - cutout.aura.minX) - cutout.aura.width * 0.5
                let dy = (cutout.pill.midY - cutout.aura.minY) - cutout.aura.height * 0.5
                let pw = cutout.pill.width
                let ph = cutout.pill.height
                ZStack {
                    Capsule().fill(Color.white).frame(width: pw * 1.8, height: ph * 1.8).blur(radius: 8)
                    Capsule().fill(Color.white.opacity(0.7)).frame(width: pw * 2.3, height: ph * 2.3).blur(radius: 16)
                }
                .frame(width: cutout.aura.width, height: cutout.aura.height)
                .offset(x: dx, y: dy)
                .blur(radius: 18)
            }
            .onAppear {
                manager.sync(theme: theme, cutout: cutout, kmh: kmh)
            }
            .onChange(of: theme) { _, t in
                manager.sync(theme: t, cutout: cutout, kmh: kmh)
            }
            .onChange(of: kmh) { _, v in
                manager.sync(theme: theme, cutout: cutout, kmh: v)
            }
            .onChange(of: cutout) { _, c in
                manager.sync(theme: theme, cutout: c, kmh: kmh)
            }
            .accessibilityLabel(manager.effect.title)
    }
}

@available(iOS 18.0, *)
private struct EtubuVFXRealityRepresentable: UIViewRepresentable {
    @ObservedObject var manager: EtubuVFXManager

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(.clear)
        view.renderOptions.insert(.disableGroundingShadows)
        view.renderOptions.insert(.disableMotionBlur)
        view.isMultipleTouchEnabled = false

        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 45
        let camEntity = Entity()
        camEntity.addChild(camera)
        // Look at origin from +Z; overlay plane is XY.
        camEntity.position = [0, 0, 0.55]
        camEntity.look(at: .zero, from: camEntity.position, relativeTo: nil)

        let anchor = AnchorEntity(world: .zero)
        anchor.name = "CameraCutoutAnchor"
        anchor.addChild(camEntity)

        let root = Entity()
        root.name = "VFXRoot"
        anchor.addChild(root)

        view.scene.addAnchor(anchor)
        context.coordinator.arView = view
        context.coordinator.vfxRoot = root
        context.coordinator.rebuild(manager: manager)
        context.coordinator.bind(manager: manager)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.rebuild(manager: manager)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        weak var arView: ARView?
        var vfxRoot: Entity?
        private var effectEntity: Entity?
        private var lastKey: String = ""
        private var cancellables = Set<AnyCancellable>()

        func bind(manager: EtubuVFXManager) {
            cancellables.removeAll()
            manager.$effect
                .combineLatest(manager.$intensity, manager.$pillLocal, manager.$isActive)
                .debounce(for: .milliseconds(40), scheduler: RunLoop.main)
                .sink { [weak self] _, _, _, _ in
                    self?.rebuild(manager: manager)
                }
                .store(in: &cancellables)
        }

        func rebuild(manager: EtubuVFXManager) {
            guard let root = vfxRoot else { return }
            let key = "\(manager.effect.rawValue)|\(manager.isActive)|\(Int(manager.intensity * 100))|\(Int(manager.pillLocal.width))x\(Int(manager.pillLocal.height))"
            // Soft rebuild when only intensity drifts slightly — still refresh emitters.
            if key == lastKey, effectEntity != nil { return }
            lastKey = key

            effectEntity?.removeFromParent()
            effectEntity = nil
            guard manager.isActive, manager.pillLocal.width > 1 else { return }

            let entity = EtubuVFXParticleFactory.makeEffectEntity(
                type: manager.effect,
                shapeSize: manager.emitterShapeSizeMeters(),
                intensity: max(0.12, manager.intensity),
                budget: manager.budgetScale
            )
            entity.position = manager.emitterPositionMeters()
            root.addChild(entity)
            effectEntity = entity

            // Burst-style effects: trigger once after attach.
            if manager.effect == .patlama || manager.effect == .havaFisek {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    entity.children.forEach { child in
                        if var emitter = child.components[ParticleEmitterComponent.self] {
                            emitter.burst()
                            child.components.set(emitter)
                        }
                    }
                }
            }

            // Heat / volcano / blast: Metal SwiftUI heat on Canvas + light particle pulse
            if manager.effect == .ates || manager.effect == .yanardag || manager.effect == .patlama {
                EtubuVFXHeatDistortion.attachPulse(to: entity, intensity: manager.intensity)
            }
        }
    }
}

/// Lightweight heat shimmer without a full CustomMaterial pipeline (stable across devices).
@available(iOS 18.0, *)
enum EtubuVFXHeatDistortion {
    static func attachPulse(to entity: Entity, intensity: Float) {
        let base = entity.scale
        let amp = 1 + 0.015 * intensity
        var t = entity.transform
        t.scale = base * amp
        entity.move(to: t, relativeTo: entity.parent, duration: 0.18, timingFunction: .easeInOut)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            var back = entity.transform
            back.scale = base
            entity.move(to: back, relativeTo: entity.parent, duration: 0.22, timingFunction: .easeInOut)
        }
    }
}
