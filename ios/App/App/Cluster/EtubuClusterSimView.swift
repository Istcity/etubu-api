import SwiftUI
import CoreLocation

/// First-launch coach-marks — cards point at the real UI hotspot they describe.
struct EtubuClusterSimView: View {
    var theme: ClusterTheme
    var hotspots: [EtubuClusterHotspotID: CGRect]
    var canvasSize: CGSize
    var onFinished: () -> Void

    @State private var step: Step = .welcome
    @State private var hintPulse = false
    @ObservedObject private var permissions = EtubuSimPermissionState.shared

    enum Step: Int, CaseIterable {
        case welcome, pair, theme, location, bluetooth, ready
    }

    private var targetID: EtubuClusterHotspotID? {
        switch step {
        case .welcome: return nil
        case .pair: return .pair
        case .theme: return .dial
        case .location: return hotspots[.route] != nil ? .route : .dial
        case .bluetooth: return .pair
        case .ready: return hotspots[.sound] != nil ? .sound : .settings
        }
    }

    private var holeRect: CGRect? {
        guard let id = targetID, let r = hotspots[id], r.width > 4, r.height > 4 else { return nil }
        return r
    }

    var body: some View {
        ZStack {
            // Dim with spotlight cutout over the live control
            if let hole = holeRect {
                Rectangle()
                    .fill(Color.black.opacity(0.72))
                    .ignoresSafeArea()
                    .reverseMask {
                        RoundedRectangle(cornerRadius: holeCorner(for: hole), style: .continuous)
                            .frame(width: hole.width + 14, height: hole.height + 14)
                            .position(x: hole.midX, y: hole.midY)
                    }
                    .allowsHitTesting(true)

                // Living ring around the pointed control
                RoundedRectangle(cornerRadius: holeCorner(for: hole), style: .continuous)
                    .stroke(
                        AngularGradient(
                            colors: [theme.accent.opacity(0.15), theme.accent, Color.white.opacity(0.9), theme.accent.opacity(0.15)],
                            center: .center
                        ),
                        lineWidth: 2.2
                    )
                    .frame(width: hole.width + 18, height: hole.height + 18)
                    .position(x: hole.midX, y: hole.midY)
                    .scaleEffect(hintPulse ? 1.04 : 0.98)
                    .opacity(hintPulse ? 1 : 0.65)
                    .allowsHitTesting(false)

                connector(from: hole)
                    .stroke(theme.accent.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5, 4]))
                    .allowsHitTesting(false)
            } else {
                Color.black.opacity(0.66).ignoresSafeArea()
            }

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Atla") { finish(requestRemainder: true) }
                        .font(EtubuClusterFonts.ui(14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.78))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                Spacer(minLength: 0)

                card
                    .padding(.horizontal, 18)
                    .padding(.bottom, 10)

                progressDots
                    .padding(.bottom, max(18, canvasSize.height * 0.03))
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                hintPulse = true
            }
        }
    }

    private func holeCorner(for rect: CGRect) -> CGFloat {
        min(18, min(rect.width, rect.height) * 0.35)
    }

    private func connector(from hole: CGRect) -> Path {
        Path { p in
            let start = CGPoint(x: hole.midX, y: hole.maxY + 10)
            let endY = canvasSize.height - 210
            let end = CGPoint(x: canvasSize.width * 0.5, y: max(endY, start.y + 40))
            p.move(to: start)
            p.addQuadCurve(to: end, control: CGPoint(x: start.x, y: (start.y + end.y) / 2))
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: stepIcon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(theme.accent.opacity(0.16)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(EtubuClusterFonts.ui(20, weight: .bold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(EtubuClusterFonts.ui(12, weight: .medium))
                        .foregroundStyle(theme.mutedText)
                        .lineLimit(2)
                }
            }

            Text(detail)
                .font(EtubuClusterFonts.ui(14, weight: .medium))
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: primaryAction) {
                Text(primaryLabel)
                    .font(EtubuClusterFonts.ui(16, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [theme.accent.opacity(0.55), theme.stroke.opacity(0.35)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: theme.accent.opacity(0.22), radius: 18, y: 8)
        )
    }

    private var stepIcon: String {
        switch step {
        case .welcome: return "sparkles"
        case .pair: return "antenna.radiowaves.left.and.right"
        case .theme: return "circle.hexagongrid.fill"
        case .location: return "location.fill"
        case .bluetooth: return "wave.3.right"
        case .ready: return "checkmark.seal.fill"
        }
    }

    private var title: String {
        switch step {
        case .welcome: return "ETUBU Cluster"
        case .pair: return "Araç bağlantısı"
        case .theme: return "Tema & kadran"
        case .location: return "Konum (GPS)"
        case .bluetooth: return "Bluetooth"
        case .ready: return "Hazırsın"
        }
    }

    private var subtitle: String {
        switch step {
        case .welcome: return "Kısa tur — işaretli kontroller gerçek yerler"
        case .pair: return "Üstteki Pair / bağlantı rozeti"
        case .theme: return "Ortadaki hız kadranı"
        case .location: return hotspots[.route] != nil ? "Üstteki rota düğmesi" : "Ortadaki hız kadranı"
        case .bluetooth: return "Tesla BLE anahtarı için"
        case .ready: return "EV Sound · Rota · Ayarlar"
        }
    }

    private var detail: String {
        switch step {
        case .welcome:
            return "Aydınlatılan bölgeler uygulamadaki gerçek düğmeleri gösterir. Pair ile Tesla’ya bağlanır, kadranda temayı kaydırır, rota ve EV sesini buradan yönetirsin."
        case .pair:
            return "Işıklı rozet bağlantı durumunu gösterir. Dokun → VIN gir → Pair. İstek gidince araçta anahtar kartını konsola dokundur; onaydan sonra rozet yeşile döner."
        case .theme:
            return "Kadranı dikey kaydırarak temaları değiştir. Hız, vites ve (yatayda) kW bu dairenin içinde kalır."
        case .location:
            return hotspots[.route] != nil
                ? "Konum izni rota araması, koridor ortalaması ve harita zemini için kullanılır. Rota düğmesine dokunarak hedef seçersin; önce “İzin ver”."
                : "Konum izni rota, koridor ortalaması ve harita zemini için kullanılır. “İzin ver” ile sistem penceresini aç."
        case .bluetooth:
            return "Bluetooth, Tesla BLE oturumu için şart. İzni ver; ardından Pair rozetinden eşleştirmeyi tamamla. Kart beklenirken rozet nabız gibi yanar."
        case .ready:
            return "Sol altta EV Sound, üstte rota / ayarlar. Bağlantı koparsa rozete tekrar dokun. Keyifli sürüş."
        }
    }

    private var primaryLabel: String {
        switch step {
        case .welcome: return "Başla"
        case .pair: return "Anladım"
        case .theme: return "Devam"
        case .location: return permissions.locationReady ? "Devam" : "Konum izni ver"
        case .bluetooth: return permissions.bluetoothAsked ? "Devam" : "Bluetooth izni ver"
        case .ready: return "Cluster’a geç"
        }
    }

    private var progressDots: some View {
        HStack(spacing: 7) {
            ForEach(Step.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(s == step ? theme.accent : Color.white.opacity(0.22))
                    .frame(width: s == step ? 22 : 7, height: 7)
            }
        }
    }

    private func primaryAction() {
        switch step {
        case .welcome, .pair, .theme:
            advance()
        case .location:
            if permissions.locationReady { advance() }
            else { permissions.requestLocation { advance() } }
        case .bluetooth:
            if permissions.bluetoothAsked { advance() }
            else { permissions.requestBluetooth { advance() } }
        case .ready:
            finish(requestRemainder: false)
        }
    }

    private func advance() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
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

private extension View {
    /// Cut a hole in the dim layer (even-odd fill via reverse mask).
    func reverseMask<M: View>(@ViewBuilder _ mask: () -> M) -> some View {
        self.mask(
            ZStack {
                Rectangle().fill(Color.white)
                mask().blendMode(.destinationOut)
            }
            .compositingGroup()
        )
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
