import SwiftUI
import CoreLocation

/// First-launch interactive walkthrough — short actions, skip anytime.
struct EtubuClusterSimView: View {
    var theme: ClusterTheme
    var onFinished: () -> Void

    @State private var step: Step = .welcome
    @State private var themeHintPulse = false
    @ObservedObject private var permissions = EtubuSimPermissionState.shared

    enum Step: Int, CaseIterable {
        case welcome, theme, location, bluetooth, dial
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Atla") {
                        finish(requestRemainder: true)
                    }
                    .font(EtubuClusterFonts.ui(15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Spacer(minLength: 8)

                card
                    .padding(.horizontal, 20)

                Spacer(minLength: 8)

                progressDots
                    .padding(.bottom, 28)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                themeHintPulse = true
            }
        }
    }

    @ViewBuilder
    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(EtubuClusterFonts.ui(22, weight: .bold))
                .foregroundStyle(.white)

            content

            Button(action: primaryAction) {
                Text(primaryLabel)
                    .font(EtubuClusterFonts.ui(16, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.top, 4)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(theme.stroke, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            Text("Cluster · rota · EV ses")
                .font(EtubuClusterFonts.ui(15, weight: .medium))
                .foregroundStyle(theme.secondaryText)
        case .theme:
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(theme.accent)
                    .opacity(themeHintPulse ? 1 : 0.35)
                Text("Kadranda kaydır")
                    .font(EtubuClusterFonts.ui(15, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onEnded { v in
                        if abs(v.translation.height) > 10 {
                            advance()
                        }
                    }
            )
        case .location:
            Label("Konum", systemImage: "location.fill")
                .font(EtubuClusterFonts.ui(15, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
        case .bluetooth:
            Label("Bluetooth", systemImage: "antenna.radiowaves.left.and.right")
                .font(EtubuClusterFonts.ui(15, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
        case .dial:
            Label("EV Sound · Rota · VIN", systemImage: "speedometer")
                .font(EtubuClusterFonts.ui(15, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var title: String {
        switch step {
        case .welcome: return "ETUBU"
        case .theme: return "Tema"
        case .location: return "GPS"
        case .bluetooth: return "Araç"
        case .dial: return "Hazır"
        }
    }

    private var primaryLabel: String {
        switch step {
        case .welcome: return "Başla"
        case .theme: return "Devam"
        case .location: return permissions.locationReady ? "Devam" : "İzin ver"
        case .bluetooth: return permissions.bluetoothAsked ? "Devam" : "İzin ver"
        case .dial: return "Tamam"
        }
    }

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(Step.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(s == step ? theme.accent : Color.white.opacity(0.22))
                    .frame(width: s == step ? 22 : 8, height: 8)
            }
        }
    }

    private func primaryAction() {
        switch step {
        case .welcome:
            advance()
        case .theme:
            advance()
        case .location:
            if permissions.locationReady {
                advance()
            } else {
                permissions.requestLocation {
                    advance()
                }
            }
        case .bluetooth:
            if permissions.bluetoothAsked {
                advance()
            } else {
                permissions.requestBluetooth {
                    advance()
                }
            }
        case .dial:
            finish(requestRemainder: false)
        }
    }

    private func advance() {
        withAnimation(.easeInOut(duration: 0.22)) {
            if let next = Step(rawValue: step.rawValue + 1) {
                step = next
            } else {
                finish(requestRemainder: false)
            }
        }
    }

    private func finish(requestRemainder: Bool) {
        UserDefaults.standard.set(true, forKey: EtubuClusterSimView.doneKey)
        if requestRemainder {
            permissions.requestLocation(completion: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                permissions.requestBluetooth(completion: nil)
            }
        }
        onFinished()
    }

    static let doneKey = "etubu.cluster.simDone.v1"
    static var isDone: Bool { UserDefaults.standard.bool(forKey: doneKey) }
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
