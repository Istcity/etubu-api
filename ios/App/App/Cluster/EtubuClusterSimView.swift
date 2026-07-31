import SwiftUI
import CoreLocation

/// Klasik swipe onboarding — 4 ekran, altta dots, Atla + son ekranda Başla.
/// İzinler (konum + Bluetooth) ilk ekranda istenir.
struct EtubuClusterSimView: View {
    var theme: ClusterTheme
    /// Kept for call-site compatibility (spotlight removed).
    var hotspots: [EtubuClusterHotspotID: CGRect] = [:]
    var canvasSize: CGSize = .zero
    var onFinished: () -> Void

    @State private var page = 0
    @ObservedObject private var permissions = EtubuSimPermissionState.shared

    private let pages: [OnboardPage] = [
        OnboardPage(
            icon: "sparkles",
            title: "ETUBU Cluster",
            body: "Tesla’nızın hız, vites, menzil ve yol uyarılarını tek ekranda, araç içi kadran gibi gösterir. Kaydırarak kısa tura başlayın."
        ),
        OnboardPage(
            icon: "antenna.radiowaves.left.and.right",
            title: "Araç bağlantısı",
            body: "Bluetooth ile VIN üzerinden Tesla’ya bağlanır. Pair rozetinden eşleştirin; bir kez tanımlandıktan sonra otomatik yeniden bağlanır."
        ),
        OnboardPage(
            icon: "point.topleft.down.to.point.bottomright.curvepath",
            title: "Rota & kritik uyarılar",
            body: "Türkiye’de il/ilçe arayıp rota çizin. Radar, hız koridoru, şarj, hava ve kontrol noktaları haritada ve Dynamic Island’da görünür; sesli uyarılar müzik üstünde çalar."
        ),
        OnboardPage(
            icon: "waveform",
            title: "Ses, tema & hazır",
            body: "EV Sound hızlanma/yavaşlamaya duyarlıdır. Temaları kadrandan kaydırın; çentik efektleri temaya özeldir. Ayarlardan her şeyi yönetebilirsiniz."
        ),
    ]

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
                    Button("Atla") { finish(requestRemainder: true) }
                        .font(EtubuClusterFonts.ui(15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)

                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        pageContent(item, index: index)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.25), value: page)

                progressDots
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                bottomCTA
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
            }
        }
        .onAppear {
            // İzinleri en başta al
            permissions.requestLocation(completion: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                permissions.requestBluetooth(completion: nil)
            }
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
                title: "Konum",
                detail: "Rota, harita ve koridor ortalaması"
            )
            permRow(
                ok: permissions.bluetoothAsked,
                title: "Bluetooth",
                detail: "Tesla BLE bağlantısı"
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
        return Button {
            if isLast {
                finish(requestRemainder: false)
            } else {
                withAnimation { page += 1 }
            }
        } label: {
            Text(isLast ? "Başla" : "Devam")
                .font(EtubuClusterFonts.ui(17, weight: .bold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(theme.accent, in: Capsule())
        }
    }

    private func finish(requestRemainder: Bool) {
        UserDefaults.standard.set(true, forKey: Self.doneKey)
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
