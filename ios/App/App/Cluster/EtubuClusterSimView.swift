import SwiftUI
import UIKit
import CoreLocation

extension Notification.Name {
    static let etubuSimFinished = Notification.Name("etubu.sim.finished")
}

/// İlk açılış öğreticisi — 4 sayfa, nokta göstergesi, Atla / İlerle / Başla.
struct EtubuClusterSimView: View {
    var theme: ClusterTheme
    var onFinished: () -> Void

    @State private var page = 0
    @State private var dismissing = false

    private var pages: [EtubuOnboardPage] {
        [
            EtubuOnboardPage(
                symbol: "speedometer",
                title: EtubuClusterL10n.t("simPage1Title"),
                body: EtubuClusterL10n.t("simPage1Body"),
                card: nil
            ),
            EtubuOnboardPage(
                symbol: "car.side.front.open",
                title: EtubuClusterL10n.t("simPage2Title"),
                body: EtubuClusterL10n.t("simPage2Body"),
                card: nil
            ),
            EtubuOnboardPage(
                symbol: "point.topleft.down.to.point.bottomright.curvepath",
                title: EtubuClusterL10n.t("simPage3Title"),
                body: EtubuClusterL10n.t("simPage3Body"),
                card: nil
            ),
            EtubuOnboardPage(
                symbol: "speaker.wave.2.fill",
                title: EtubuClusterL10n.t("simPage4Title"),
                body: EtubuClusterL10n.t("simPage4Body"),
                card: EtubuClusterL10n.t("simAudioCard")
            ),
        ]
    }

    private var isLast: Bool { page >= pages.count - 1 }

    var body: some View {
        ZStack {
            EtubuSheetBackdrop(theme: theme)

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .safeAreaPadding(.top, 6)

                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        EtubuOnboardPageView(page: item, index: index, theme: theme)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.28), value: page)

                progressDots
                    .padding(.top, 10)
                    .padding(.bottom, 14)

                bottomCTA
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                    .padding(.top, 4)
            }
        }
        .opacity(dismissing ? 0 : 1)
        .offset(x: dismissing ? -36 : 0)
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("etubu.sim.root")
    }

    private var topBar: some View {
        HStack {
            EtubuBrandMark(size: 28, showGlow: true)
            Spacer(minLength: 0)
            if !isLast {
                Button(EtubuClusterL10n.t("simSkip")) {
                    complete()
                }
                .font(EtubuClusterFonts.ui(15, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(theme.stroke.opacity(0.7), lineWidth: 1)
                )
                .accessibilityLabel(EtubuClusterL10n.t("simSkip"))
                .accessibilityIdentifier("etubu.sim.skip")
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .frame(minHeight: 44)
        .animation(.easeInOut(duration: 0.22), value: isLast)
    }

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<pages.count, id: \.self) { i in
                Capsule()
                    .fill(i == page ? theme.accent : theme.stroke.opacity(0.55))
                    .frame(width: i == page ? 22 : 8, height: 8)
                    .shadow(color: i == page ? theme.glow.opacity(0.55) : .clear, radius: 6)
            }
        }
        .animation(.easeOut(duration: 0.22), value: page)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(page + 1) / \(pages.count)")
    }

    private var bottomCTA: some View {
        EtubuSimUIKitButton(
            title: isLast ? EtubuClusterL10n.t("simStart") : EtubuClusterL10n.t("simContinue"),
            accessibilityId: isLast ? "etubu.sim.start" : "etubu.sim.continue",
            accent: UIColor(theme.accent)
        ) {
            if isLast {
                complete()
            } else {
                withAnimation(.easeInOut(duration: 0.28)) { page += 1 }
            }
        }
        .frame(height: 54)
    }

    private func complete() {
        guard !dismissing else { return }
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        UserDefaults.standard.synchronize()
        NotificationCenter.default.post(name: .etubuSimFinished, object: nil)
        withAnimation(.easeInOut(duration: 0.45)) {
            dismissing = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            onFinished()
        }
    }

    static let doneKey = "etubu.cluster.simDone.v5"
    private static let legacyDoneKeys = [
        "etubu.cluster.simDone.v4",
        "etubu.cluster.simDone.v3",
        "etubu.cluster.simDone",
    ]

    static var isDone: Bool {
        if UserDefaults.standard.bool(forKey: doneKey) { return true }
        return legacyDoneKeys.contains { UserDefaults.standard.bool(forKey: $0) }
    }
}

private struct EtubuOnboardPage {
    let symbol: String
    let title: String
    let body: String
    let card: String?
}

private struct EtubuOnboardPageView: View {
    let page: EtubuOnboardPage
    let index: Int
    var theme: ClusterTheme

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                Spacer(minLength: 12)
                EtubuOnboardHero(symbol: page.symbol, theme: theme, brand: index == 0)
                VStack(spacing: 10) {
                    Text(page.title)
                        .font(EtubuClusterFonts.ui(26, weight: .bold))
                        .foregroundStyle(theme.primaryText)
                        .multilineTextAlignment(.center)
                    Text(page.body)
                        .font(EtubuClusterFonts.ui(16, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 8)

                if let card = page.card, !card.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(theme.accent)
                            .padding(.top, 1)
                        Text(card)
                            .font(EtubuClusterFonts.ui(14, weight: .medium))
                            .foregroundStyle(theme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(theme.stroke.opacity(0.85), lineWidth: 1.1)
                    )
                    .accessibilityIdentifier("etubu.sim.audio.card")
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct EtubuOnboardHero: View {
    let symbol: String
    var theme: ClusterTheme
    var brand: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [theme.accent.opacity(0.28), theme.accent.opacity(0.04), .clear],
                        center: .center,
                        startRadius: 8,
                        endRadius: 88
                    )
                )
                .frame(width: 176, height: 176)

            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 112, height: 112)
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [theme.accent.opacity(0.85), theme.stroke.opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.4
                        )
                )
                .shadow(color: theme.glow.opacity(0.45), radius: 16, y: 4)

            if brand {
                EtubuBrandMark(size: 48, showGlow: true)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .shadow(color: theme.glow.opacity(0.55), radius: 8)
            }
        }
        .frame(height: 176)
        .accessibilityHidden(true)
    }
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
        b.layer.cornerRadius = 27
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
