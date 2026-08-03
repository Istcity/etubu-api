import SwiftUI
import UIKit
import CoreLocation

extension Notification.Name {
    static let etubuSimFinished = Notification.Name("etubu.sim.finished")
}

/// Klasik swipe onboarding — 4 ekran, altta dots, Atla + son ekranda Başla.
/// İzinler (konum + Bluetooth) ilk ekranda istenir.
struct EtubuClusterSimView: View {
    var theme: ClusterTheme
    var onFinished: () -> Void

    @State private var page = 0
    @ObservedObject private var permissions = EtubuSimPermissionState.shared

    private var pages: [OnboardPage] {
        [
            OnboardPage(
                icon: "sparkles",
                title: EtubuClusterL10n.t("simPage1Title"),
                body: EtubuClusterL10n.t("simPage1Body")
            ),
            OnboardPage(
                icon: "antenna.radiowaves.left.and.right",
                title: EtubuClusterL10n.t("simPage2Title"),
                body: EtubuClusterL10n.t("simPage2Body")
            ),
            OnboardPage(
                icon: "point.topleft.down.to.point.bottomright.curvepath",
                title: EtubuClusterL10n.t("simPage3Title"),
                body: EtubuClusterL10n.t("simPage3Body")
            ),
            OnboardPage(
                icon: "waveform",
                title: EtubuClusterL10n.t("simPage4Title"),
                body: EtubuClusterL10n.t("simPage4Body")
            ),
        ]
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: theme.canvasGradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text(EtubuClusterL10n.t("simSkip"))
                        .font(EtubuClusterFonts.ui(15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .frame(minWidth: 72, minHeight: 44)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            finish(requestRemainder: false)
                        }
                        .accessibilityLabel(EtubuClusterL10n.t("simSkip"))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("etubu.sim.skip")
                        .accessibilityAction {
                            finish(requestRemainder: false)
                        }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .safeAreaPadding(.top, 8)
                .zIndex(20)

                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        pageContent(item, index: index)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.25), value: page)
                .clipped()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                progressDots
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .zIndex(20)

                bottomCTA
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity)
                    .background(theme.canvas.opacity(0.97))
                    .zIndex(40)
            }
        }
        .onAppear {
            // Konum/Bluetooth izinlerini otomatik isteme — legal/onboarding üstüne
            // sistem diyaloğu biner ve “siyah ekran / takılı” gibi görünür.
        }
    }

    private func pageContent(_ item: OnboardPage, index: Int) -> some View {
        let shot = EtubuOnboardShot.forPage(index)
        return ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                Spacer(minLength: 8)

                VStack(spacing: 10) {
                    if index == 0 {
                        EtubuBrandMark(size: 44, showGlow: true)
                    } else {
                        Image(systemName: item.icon)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(theme.accent)
                            .frame(width: 52, height: 52)
                            .background(Circle().fill(theme.accent.opacity(0.14)))
                    }

                    Text(item.title)
                        .font(EtubuClusterFonts.ui(24, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text(item.body)
                        .font(EtubuClusterFonts.ui(14, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }

                // Tanıtım metninin altında gerçek ekran görüntüleri + işaretlemeler
                VStack(spacing: 10) {
                    EtubuOnboardScreenshotCard(
                        shot: shot,
                        theme: theme,
                        emphasized: true,
                        width: index == 2 ? 260 : 168,
                        height: index == 2 ? 148 : 280
                    )

                    EtubuOnboardScreenshotStrip(theme: theme, highlight: shot)
                }
                .padding(.top, 2)

                if index == 0 {
                    permissionHints
                        .padding(.top, 4)
                }

                if index == 2 {
                    Text(EtubuClusterL10n.t("premiumFreeNote"))
                        .font(EtubuClusterFonts.ui(12, weight: .semibold))
                        .foregroundStyle(theme.accent)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(theme.accent.opacity(0.12))
                        )
                        .accessibilityIdentifier("etubu.sim.premium.note")
                }

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
        }
    }

    private var permissionHints: some View {
        VStack(alignment: .leading, spacing: 8) {
            permRow(
                ok: permissions.locationReady,
                title: EtubuClusterL10n.t("simPermLocation"),
                detail: EtubuClusterL10n.t("simPermLocationDetail")
            )
            permRow(
                ok: permissions.bluetoothAsked,
                title: EtubuClusterL10n.t("simPermBluetooth"),
                detail: EtubuClusterL10n.t("simPermBluetoothDetail")
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
    }

    private func permRow(ok: Bool, title: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ok ? Color.green : theme.mutedText)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(EtubuClusterFonts.ui(13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(EtubuClusterFonts.ui(11, weight: .medium))
                    .foregroundStyle(theme.mutedText)
            }
            Spacer(minLength: 0)
        }
    }

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<pages.count, id: \.self) { i in
                Capsule()
                    .fill(i == page ? theme.accent : Color.white.opacity(0.25))
                    .frame(width: i == page ? 22 : 8, height: 8)
                    .animation(.easeOut(duration: 0.2), value: page)
            }
        }
    }

    private var bottomCTA: some View {
        let isLast = page >= pages.count - 1
        return EtubuSimUIKitButton(
            title: isLast ? EtubuClusterL10n.t("simStart") : EtubuClusterL10n.t("simContinue"),
            accessibilityId: isLast ? "etubu.sim.start" : "etubu.sim.continue",
            accent: UIColor(theme.accent)
        ) {
            if isLast {
                finish(requestRemainder: false)
            } else {
                withAnimation { page += 1 }
            }
        }
        .frame(height: 52)
    }

    private func finish(requestRemainder: Bool) {
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        UserDefaults.standard.synchronize()
        NotificationCenter.default.post(name: .etubuSimFinished, object: nil)
        if requestRemainder {
            if !permissions.locationReady {
                permissions.requestLocation(completion: nil)
            }
            if !permissions.bluetoothAsked {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    permissions.requestBluetooth(completion: nil)
                }
            }
        }
        onFinished()
    }

    /// v4 — gerçek ekran görüntüleri + işaretlemeler
    static let doneKey = "etubu.cluster.simDone.v4"
    static var isDone: Bool { UserDefaults.standard.bool(forKey: doneKey) }
}

/// Maestro/XCTest güvenilir hit — `accessibilityActivate` (touchUpInside değil) kullanır.
private struct EtubuSimUIKitButton: UIViewRepresentable {
    var title: String
    var accessibilityId: String
    var accent: UIColor
    var action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeUIView(context: Context) -> EtubuA11yButton {
        let b = EtubuA11yButton(type: .system)
        b.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        b.setTitleColor(.black, for: .normal)
        b.backgroundColor = accent
        b.layer.cornerRadius = 26
        b.clipsToBounds = true
        b.addTarget(context.coordinator, action: #selector(Coordinator.tap), for: .touchUpInside)
        b.onActivate = { [weak coordinator = context.coordinator] in
            coordinator?.tap()
        }
        b.accessibilityTraits = .button
        b.isAccessibilityElement = true
        return b
    }

    func updateUIView(_ uiView: EtubuA11yButton, context: Context) {
        uiView.setTitle(title, for: .normal)
        uiView.accessibilityIdentifier = accessibilityId
        uiView.accessibilityLabel = title
        uiView.backgroundColor = accent
        context.coordinator.action = action
        uiView.onActivate = { [weak coordinator = context.coordinator] in
            coordinator?.tap()
        }
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tap() { action() }
    }
}

private final class EtubuA11yButton: UIButton {
    var onActivate: (() -> Void)?
    override func accessibilityActivate() -> Bool {
        onActivate?()
        return true
    }
}

private struct OnboardPage {
    let icon: String
    let title: String
    let body: String
}

@MainActor
final class EtubuSimPermissionState: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = EtubuSimPermissionState()

    @Published var locationReady = false
    @Published var bluetoothAsked = false

    private let locationManager = CLLocationManager()
    private var locationCompletion: (() -> Void)?

    private override init() {
        super.init()
        locationManager.delegate = self
        refreshLocation()
    }

    func refreshLocation() {
        let s = locationManager.authorizationStatus
        locationReady = s == .authorizedWhenInUse || s == .authorizedAlways
    }

    func requestLocation(completion: (() -> Void)?) {
        locationCompletion = completion
        let s = locationManager.authorizationStatus
        if s == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else {
            locationReady = s == .authorizedWhenInUse || s == .authorizedAlways
            completion?()
            locationCompletion = nil
        }
    }

    func requestBluetooth(completion: (() -> Void)?) {
        bluetoothAsked = true
        Task {
            _ = await EtubuBluetoothGate.shared.waitUntilReady(timeoutSeconds: 6)
            completion?()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            refreshLocation()
            locationCompletion?()
            locationCompletion = nil
        }
    }
}
