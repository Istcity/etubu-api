import SwiftUI
import Combine

/// Monitors device thermal state (especially when mounted on vehicle dashboard under direct sunlight)
/// and dynamically reduces GPU shadow passes, heavy blur filters, and particle effects to prevent
/// thermal throttling, device shutdown, and frame drops.
final class EtubuThermalGuard: ObservableObject {
    static let shared = EtubuThermalGuard()

    @Published private(set) var state: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState

    private var cancellables = Set<AnyCancellable>()

    var isThrottled: Bool {
        state == .serious || state == .critical
    }

    var isFairOrHigher: Bool {
        state == .fair || state == .serious || state == .critical
    }

    private init() {
        NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                let next = ProcessInfo.processInfo.thermalState
                if self?.state != next {
                    self?.state = next
                }
            }
            .store(in: &cancellables)
    }

    /// Dynamically scales shadow radius to reduce GPU fill rate and composition passes under heat.
    func adaptiveShadow(_ base: CGFloat) -> CGFloat {
        if isThrottled { return 0 }
        if state == .fair { return base * 0.5 }
        return base
    }
}

enum EtubuGaugeScreen: String, CaseIterable {
    case digital, cyber, minimal, mapHud

    static var stored: EtubuGaugeScreen {
        let raw = UserDefaults.standard.string(forKey: "etubu.cluster.gaugeMode") ?? "digital"
        if raw == "analog" { return .digital }
        return EtubuGaugeScreen(rawValue: raw) ?? .digital
    }

    func next() -> EtubuGaugeScreen {
        let all = Self.allCases
        guard let idx = all.firstIndex(of: self) else { return .digital }
        return all[(idx + 1) % all.count]
    }
}

struct EtubuSpeedDialView: View, Equatable {
    let kmh: Int
    var kmhFine: Double? = nil
    let gear: String
    let theme: ClusterTheme
    var compact: Bool = false
    /// Optional override — landscape Dynamic Island uses smaller dial to avoid overflow.
    var diameter: CGFloat? = nil
    /// Gear / km/h / kW sizing; defaults to diameter. Use base size when dial is enlarged.
    var chromeDiameter: CGFloat? = nil
    var powerKw: Int? = nil
    /// Son güç örnekleri — kadran altı sparkline (regen/drive).
    var powerHistory: [Int] = []
    /// SoC ince halka (0–100).
    var socPercent: Int? = nil

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.kmh == rhs.kmh
            && Self.quantizeFine(lhs.kmhFine) == Self.quantizeFine(rhs.kmhFine)
            && lhs.gear == rhs.gear
            && lhs.theme == rhs.theme
            && lhs.compact == rhs.compact
            && lhs.diameter == rhs.diameter
            && lhs.chromeDiameter == rhs.chromeDiameter
            && lhs.powerKw == rhs.powerKw
            && lhs.socPercent == rhs.socPercent
            && lhs.powerHistory.last == rhs.powerHistory.last
            && lhs.powerHistory.count == rhs.powerHistory.count
    }

    private static func quantizeFine(_ value: Double?) -> Int {
        guard let value, value.isFinite else { return .min }
        return Int((value * 5).rounded())
    }
    @ObservedObject private var warnings = EtubuDriveWarnings.shared
    @ObservedObject private var osmLimit = EtubuOsmSpeedLimit.shared
    @ObservedObject private var thermal = EtubuThermalGuard.shared
    /// Smooth chase toward vehicle speed — critically damped physics smoothing.
    @State private var displayKmh: Double = 0
    @State private var displayPower: Double = 0
    @State private var boostPulse: CGFloat = 0
    @State private var gaugeScreen: EtubuGaugeScreen = EtubuGaugeScreen.stored
    @State private var lastTickAt: Double = 0
    private let dialPulse = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    private var rawKmh: Int { warnings.demoActive ? warnings.demoKmh : kmh }
    private var shownGear: String {
        if warnings.demoActive {
            let g = warnings.demoGear
            if (g.isEmpty || g == "P"), warnings.demoKmh >= 5 { return "D" }
            return g.isEmpty ? "D" : g
        }
        return gear
    }
    /// P/N veya duruş → kadran kilitli 0.
    private var isStationary: Bool {
        let g = shownGear.uppercased()
        if g.hasPrefix("P") || g.hasPrefix("N") { return true }
        if warnings.demoActive { return warnings.demoKmh < 2 }
        if let kmhFine, kmhFine.isFinite, kmhFine < SpeedFusion.lockKmh { return true }
        return rawKmh < 2
    }
    private var targetFine: Double {
        if isStationary { return 0 }
        if let kmhFine, kmhFine.isFinite, kmhFine >= 0 { return min(280, kmhFine) }
        return Double(rawKmh)
    }
    private var speedUnit: EtubuSpeedUnit { EtubuSpeedUnit.stored }
    private var isMph: Bool { speedUnit.isMph }
    private var shownKmh: Int { speedUnit.format(kmh: displayKmh) }
    private var shownPowerKw: Int? {
        let raw = warnings.demoActive ? warnings.demoPowerKw : powerKw
        guard let raw else { return nil }
        if isStationary { return abs(raw) < 6 ? 0 : raw }
        if abs(raw) < 4 { return 0 }
        return raw
    }

    private var dialSize: CGFloat { diameter ?? (compact ? 200 : 280) }
    private var chromeSize: CGFloat { chromeDiameter ?? dialSize }
    private var tripleDigitFactor: CGFloat { shownKmh >= 100 ? 0.85 : (shownKmh >= 10 ? 0.95 : 1.0) }

    private var speedFont: CGFloat {
        let base: CGFloat = compact
            ? min(dialSize * 0.38, 86)
            : min(dialSize * 0.40, 110)
        return base * min(theme.gaugeScale, 1.0) * tripleDigitFactor
    }

    private var gearFont: CGFloat {
        compact
            ? max(12, min(chromeSize * 0.065, 16))
            : max(14, min(chromeSize * 0.075, 20))
    }

    private var unitFont: CGFloat {
        let base: CGFloat = compact
            ? max(9, min(chromeSize * 0.038, 12))
            : max(11, min(chromeSize * 0.042, 14))
        return base * (shownKmh >= 100 ? 0.9 : 1.0)
    }

    private var kwFont: CGFloat {
        compact ? max(9, min(chromeSize * 0.034, 11)) : max(10, min(chromeSize * 0.038, 13))
    }

    private var maxScaleSpeed: Double { isMph ? 180 : 280 }
    private var speedProgress: CGFloat { min(1, CGFloat(max(0, displayKmh)) / (isMph ? 112 : 180)) }
    private var power: Int { Int(displayPower.rounded()) }
    private var powerFill: CGFloat { min(1, CGFloat(abs(displayPower)) / 160) }
    private var boostStrength: CGFloat {
        guard !isStationary else { return 0 }
        if power > 40 { return min(1, CGFloat(power) / 220) }
        return 0
    }
    private var sparkSamples: [Int] {
        let src = powerHistory.isEmpty ? [power] : powerHistory
        return Array(src.suffix(28))
    }
    private var socProgress: CGFloat {
        guard let soc = socPercent else { return 0 }
        return min(1, max(0, CGFloat(soc) / 100))
    }

    private var ringClearance: CGFloat {
        return theme.ringLineWidth(for: dialSize) * 1.8 + dialSize * 0.03
    }

    private var ringInnerSize: CGFloat {
        dialSize * 0.92
    }

    private var effectiveSpeedLimit: Int? {
        if warnings.corridorActive, let clim = warnings.corridorLimit, clim > 0 {
            return clim
        }
        if let p = warnings.primary, p.kind == "radar" {
            let numStr = p.meta.replacingOccurrences(of: "lim ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let rlim = Int(numStr), rlim > 0 {
                return rlim
            }
        }
        return osmLimit.limitKmh
    }

    private var overLimit: Bool {
        guard let lim = effectiveSpeedLimit, lim > 0, !isStationary else { return false }
        return displayKmh > Double(lim) + 3
    }

    var body: some View {
        ZStack {
            switch gaugeScreen {
            case .digital:
                digitalScreen
            case .cyber:
                cyberScreen
            case .minimal:
                minimalScreen
            case .mapHud:
                mapHudScreen
            }

            if overLimit { isaOverspeedRing }

            // Gidilen yolun anlık hız limiti tabelası (Kadranın sağ-üst köşesinde)
            VStack {
                HStack {
                    Spacer()
                    EtubuRoadSpeedLimitSign(size: compact ? max(26, dialSize * 0.16) : max(32, dialSize * 0.17))
                        .padding(.trailing, dialSize * 0.08)
                        .padding(.top, dialSize * 0.06)
                }
                Spacer()
            }
            .frame(width: dialSize, height: dialSize)
            .allowsHitTesting(false)

            // Soft boost wash (omitted when thermally throttled)
            if boostStrength > 0.05, !thermal.isThrottled {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                theme.accent.opacity(0.22 * boostStrength + 0.06 * boostPulse),
                                theme.accent.opacity(0.06 * boostStrength),
                                .clear,
                            ],
                            center: .center,
                            startRadius: dialSize * 0.12,
                            endRadius: dialSize * 0.52
                        )
                    )
                    .frame(width: dialSize * 0.92, height: dialSize * 0.92)
                    .allowsHitTesting(false)
                    .animation(.easeOut(duration: 0.35), value: boostStrength)
            }
        }
        .frame(width: dialSize, height: dialSize)
        .contentShape(Circle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.25)) {
                gaugeScreen = gaugeScreen.next()
                UserDefaults.standard.set(gaugeScreen.rawValue, forKey: "etubu.cluster.gaugeMode")
            }
        }
        .transaction { txn in
            if isStationary { txn.animation = nil }
        }
        .onAppear {
            displayKmh = targetFine
            displayPower = Double(shownPowerKw ?? 0)
            gaugeScreen = EtubuGaugeScreen.stored
        }
        .onReceive(dialPulse) { _ in
            tickDisplaySpeed()
        }
        .onChange(of: shownPowerKw) { _, new in
            let v = Double(new ?? 0)
            withAnimation(.easeInOut(duration: 0.22)) {
                displayPower = v
            }
            guard v > 55, !thermal.isThrottled else {
                withAnimation(.easeOut(duration: 0.4)) { boostPulse = 0 }
                return
            }
            withAnimation(.easeOut(duration: 0.25)) { boostPulse = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                withAnimation(.easeOut(duration: 0.55)) { boostPulse = 0.35 }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: displayPower)
    }

    /// Continuous physical fluid digit step rate with delta-time exponential smoothing.
    private func tickDisplaySpeed() {
        let target = targetFine
        let now = CACurrentMediaTime()
        let dt = lastTickAt == 0 ? (1.0 / 60.0) : min(0.08, max(0.001, now - lastTickAt))
        lastTickAt = now

        if isStationary {
            if displayKmh > 0 {
                let alpha = 1.0 - exp(-dt / 0.12)
                displayKmh += (0 - displayKmh) * alpha
                if displayKmh < 0.10 { displayKmh = 0 }
            }
            return
        }

        if target <= 0.6 {
            if displayKmh <= 0.05 {
                if displayKmh != 0 { displayKmh = 0 }
                return
            }
            let alpha = 1.0 - exp(-dt / 0.14)
            displayKmh += (0 - displayKmh) * alpha
            if displayKmh < 0.12 { displayKmh = 0 }
            return
        }

        let diff = target - displayKmh
        let absDiff = abs(diff)
        if absDiff < 0.03 {
            if displayKmh != target { displayKmh = target }
            return
        }

        // Asymmetric time constant: fast, responsive acceleration; smooth, natural deceleration
        let tau: Double = diff > 0 ? 0.16 : 0.20
        let alpha = 1.0 - exp(-dt / tau)
        displayKmh += diff * alpha
    }

    // MARK: - Symmetrical Dial Bezel Chrome

    private var dialRingChrome: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            theme.surface.opacity(0.70),
                            Color.black.opacity(0.40)
                        ],
                        center: .center,
                        startRadius: dialSize * 0.1,
                        endRadius: dialSize * 0.5
                    )
                )
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    theme.accent.opacity(0.50),
                                    theme.stroke.opacity(0.65),
                                    Color.white.opacity(0.18)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                )
                .shadow(color: theme.accent.opacity(0.15), radius: thermal.adaptiveShadow(6), x: 0, y: 0)
        }
        .frame(width: dialSize, height: dialSize)
    }

    // MARK: - Digital Screen

    private var digitalScreen: some View {
        ZStack {
            dialRingChrome
            dialRings

            VStack(spacing: compact ? 0 : 2) {
                gearRow
                Text("\(shownKmh)")
                    .font(EtubuClusterFonts.gauge(speedFont))
                    .monospacedDigit()
                    .tracking(shownKmh >= 100 ? 0 : min(theme.gaugeTracking, 0.6) * 0.04)
                    .foregroundStyle(overLimit ? Color.orange : theme.primaryText)
                    .shadow(
                        color: overLimit
                            ? Color.orange.opacity(0.7)
                            : (isStationary ? .clear : theme.accent.opacity(0.4)),
                        radius: thermal.adaptiveShadow(compact ? 4 : 6)
                    )
                    .minimumScaleFactor(0.35)
                    .lineLimit(1)
                    .frame(maxWidth: dialSize * 0.80)
                    .accessibilityIdentifier("etubu.speed")
                    .contentTransition(.identity)
                Text(speedUnit.label)
                    .font(EtubuClusterFonts.ui(unitFont, weight: .semibold))
                    .foregroundStyle(theme.mutedText)
                    .tracking(min(theme.gaugeTracking, 0.6) * 0.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if warnings.demoActive {
                    demoStopButton
                }

                Text(shownPowerKw.map { "\($0) kW" } ?? "— kW")
                    .font(EtubuClusterFonts.gauge(kwFont))
                    .monospacedDigit()
                    .foregroundStyle(
                        power < -1
                        ? Color(red: 0.35, green: 0.92, blue: 0.55)
                        : (power > 1 ? theme.accent : theme.mutedText)
                    )
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
            }
            .frame(maxWidth: dialSize * 0.82, maxHeight: dialSize * 0.82)
        }
    }

    // MARK: - Map HUD Screen

    private var mapHudScreen: some View {
        let side = dialSize
        return ZStack {
            Circle()
                .fill(Color.black.opacity(0.45))
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [theme.accent.opacity(0.8), theme.accent.opacity(0.2), Color.white.opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2.0
                        )
                )
                .frame(width: side * 0.92, height: side * 0.92)
                .shadow(color: theme.accent.opacity(0.45), radius: 12)

            Circle()
                .trim(from: 0, to: speedProgress)
                .stroke(
                    AngularGradient(
                        colors: [theme.accent.opacity(0.3), theme.accent, Color.white],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: side * 0.92, height: side * 0.92)

            VStack(spacing: compact ? 0 : 2) {
                gearRow
                Text("\(shownKmh)")
                    .font(EtubuClusterFonts.gauge(speedFont))
                    .monospacedDigit()
                    .foregroundStyle(overLimit ? Color.orange : Color.white)
                    .shadow(color: theme.accent.opacity(0.7), radius: 8)
                    .minimumScaleFactor(0.35)
                    .lineLimit(1)
                    .frame(maxWidth: side * 0.80)
                Text(speedUnit.label)
                    .font(EtubuClusterFonts.ui(unitFont, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(theme.accent)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                if warnings.demoActive {
                    demoStopButton
                }

                Text(shownPowerKw.map { "\($0) kW" } ?? "— kW")
                    .font(EtubuClusterFonts.gauge(kwFont))
                    .monospacedDigit()
                    .foregroundStyle(
                        power < -1
                        ? Color(red: 0.35, green: 0.92, blue: 0.55)
                        : (power > 1 ? theme.accent : theme.mutedText)
                    )
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
            }
            .frame(maxWidth: side * 0.82, maxHeight: side * 0.82)
        }
    }

    // MARK: - Cyber Screen

    private var cyberScreen: some View {
        let side = dialSize
        return ZStack {
            dialRingChrome

            // Cyber HUD corner brackets
            Group {
                Path { p in
                    p.move(to: CGPoint(x: side * 0.18, y: side * 0.08))
                    p.addLine(to: CGPoint(x: side * 0.08, y: side * 0.08))
                    p.addLine(to: CGPoint(x: side * 0.08, y: side * 0.18))
                }
                .stroke(theme.accent, lineWidth: 2.5)

                Path { p in
                    p.move(to: CGPoint(x: side * 0.82, y: side * 0.08))
                    p.addLine(to: CGPoint(x: side * 0.92, y: side * 0.08))
                    p.addLine(to: CGPoint(x: side * 0.92, y: side * 0.18))
                }
                .stroke(theme.accent, lineWidth: 2.5)

                Path { p in
                    p.move(to: CGPoint(x: side * 0.08, y: side * 0.82))
                    p.addLine(to: CGPoint(x: side * 0.08, y: side * 0.92))
                    p.addLine(to: CGPoint(x: side * 0.18, y: side * 0.92))
                }
                .stroke(theme.accent, lineWidth: 2.5)

                Path { p in
                    p.move(to: CGPoint(x: side * 0.92, y: side * 0.82))
                    p.addLine(to: CGPoint(x: side * 0.92, y: side * 0.92))
                    p.addLine(to: CGPoint(x: side * 0.82, y: side * 0.92))
                }
                .stroke(theme.accent, lineWidth: 2.5)
            }
            .shadow(color: theme.accent.opacity(0.8), radius: 6)

            // Segmented cyber tachometer arc
            Circle()
                .trim(from: 0.15, to: 0.85)
                .stroke(theme.stroke.opacity(0.35), style: StrokeStyle(lineWidth: 6, dash: [4, 4]))
                .rotationEffect(.degrees(90))
                .frame(width: side * 0.92, height: side * 0.92)

            Circle()
                .trim(from: 0.15, to: 0.15 + 0.70 * speedProgress)
                .stroke(
                    AngularGradient(
                        colors: [theme.accent.opacity(0.3), theme.accent, Color.white],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(90))
                .frame(width: side * 0.92, height: side * 0.92)
                .shadow(color: theme.accent.opacity(0.9), radius: 10)

            VStack(spacing: compact ? 0 : 2) {
                gearRow
                Text("\(shownKmh)")
                    .font(EtubuClusterFonts.gauge(speedFont))
                    .monospacedDigit()
                    .foregroundStyle(overLimit ? Color.orange : Color.white)
                    .shadow(color: theme.accent.opacity(0.7), radius: 10)
                    .minimumScaleFactor(0.35)
                    .lineLimit(1)
                    .frame(maxWidth: side * 0.80)
                Text(speedUnit.label)
                    .font(EtubuClusterFonts.ui(unitFont, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(theme.accent)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                if warnings.demoActive {
                    demoStopButton
                }

                Text(shownPowerKw.map { "PWR \($0) kW" } ?? "PWR — kW")
                    .font(EtubuClusterFonts.gauge(kwFont * 0.95))
                    .monospacedDigit()
                    .foregroundStyle(theme.mutedText)
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
            }
            .frame(maxWidth: side * 0.82, maxHeight: side * 0.82)
        }
    }

    // MARK: - Minimal Screen

    private var minimalScreen: some View {
        ZStack {
            dialRingChrome

            Circle()
                .stroke(theme.stroke.opacity(0.2), lineWidth: 1.5)
                .frame(width: dialSize * 0.92, height: dialSize * 0.92)

            Circle()
                .trim(from: 0, to: speedProgress)
                .stroke(theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: dialSize * 0.92, height: dialSize * 0.92)
                .shadow(color: theme.accent.opacity(0.6), radius: 6)

            VStack(spacing: compact ? 0 : 2) {
                gearRow
                Text("\(shownKmh)")
                    .font(EtubuClusterFonts.gauge(speedFont))
                    .monospacedDigit()
                    .foregroundStyle(overLimit ? Color.orange : Color.white)
                    .minimumScaleFactor(0.35)
                    .lineLimit(1)
                    .frame(maxWidth: dialSize * 0.80)
                Text(speedUnit.label)
                    .font(EtubuClusterFonts.ui(unitFont, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(theme.mutedText)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                if warnings.demoActive {
                    demoStopButton
                }
            }
            .frame(maxWidth: dialSize * 0.82, maxHeight: dialSize * 0.82)
        }
    }

    private var demoStopButton: some View {
        Button {
            EtubuDemoDrive.shared.stop()
        } label: {
            Text(EtubuClusterL10n.t("demoStop"))
                .font(EtubuClusterFonts.ui(compact ? 8 : 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, compact ? 6 : 8)
                .padding(.vertical, compact ? 2 : 3)
                .background(Capsule().fill(Color.red.opacity(0.92)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(EtubuClusterL10n.t("demoStop"))
        .accessibilityIdentifier("etubu.demo.stop")
    }

    private func analogPoint(center: CGPoint, radius: CGFloat, angleDeg: Double) -> CGPoint {
        let rad = angleDeg * .pi / 180.0
        return CGPoint(
            x: center.x + radius * CGFloat(cos(rad)),
            y: center.y + radius * CGFloat(sin(rad))
        )
    }

    @ViewBuilder
    private var dialRings: some View {
        let lw = theme.ringLineWidth(for: dialSize)
        let moving = !isStationary
        ZStack {
            Circle()
                .strokeBorder(theme.stroke.opacity(0.40), lineWidth: lw)

            // SoC ince halka — hız halkasının dışında.
            if socProgress > 0 {
                Circle()
                    .trim(from: 0, to: max(0.02, socProgress))
                    .stroke(
                        theme.accent.opacity(0.55),
                        style: StrokeStyle(lineWidth: max(2, lw * 0.45), lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(lw * 0.15)
                    .opacity(0.85)
            }

            if moving {
                movingRingFill(lineWidth: lw)
                bipolarPowerRing(lineWidth: lw)
            } else {
                Circle()
                    .strokeBorder(theme.accent.opacity(0.28), lineWidth: lw * 1.05)
            }
        }
        .frame(width: ringInnerSize, height: ringInnerSize)
        .allowsHitTesting(false)
        // Don't animate every ±1 km/h tick — that stuttered the ring against digit steps.
        .animation(.easeOut(duration: 0.28), value: socProgress)
        .animation(.easeInOut(duration: 0.22), value: displayPower)
    }

    private var isaOverspeedRing: some View {
        let lw = theme.ringLineWidth(for: dialSize)
        return Circle()
            .strokeBorder(Color.orange.opacity(0.92), lineWidth: lw * 1.15)
            .shadow(color: Color.orange.opacity(0.65), radius: 10)
            .frame(width: ringInnerSize, height: ringInnerSize)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func movingRingFill(lineWidth lw: CGFloat) -> some View {
        switch theme.dialRingStyle {
        case .neonSweep:
            Circle()
                .trim(from: 0, to: max(0.02, speedProgress))
                .stroke(
                    AngularGradient(
                        colors: [
                            theme.accent.opacity(0.15),
                            theme.accent,
                            Color.white.opacity(0.95),
                            theme.accent,
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lw * 1.55, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: theme.accent.opacity(0.85), radius: 10)

        case .dualGlow:
            Circle()
                .strokeBorder(theme.accent.opacity(0.28), lineWidth: lw * 2.1)
            Circle()
                .trim(from: 0, to: max(0.02, speedProgress))
                .stroke(theme.accent, style: StrokeStyle(lineWidth: lw * 1.45, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: theme.accent.opacity(0.75), radius: 12)

        case .dashed:
            Circle()
                .strokeBorder(theme.accent.opacity(0.7), style: StrokeStyle(lineWidth: lw * 1.2, dash: [7, 5]))
            Circle()
                .trim(from: 0, to: max(0.02, speedProgress))
                .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: lw * 0.85, lineCap: .round))
                .rotationEffect(.degrees(-90))

        case .plasmaRibbon:
            Circle()
                .trim(from: 0, to: max(0.02, speedProgress))
                .stroke(
                    AngularGradient(
                        colors: [
                            theme.accent.opacity(0.2),
                            Color(hue: theme.hue / 360, saturation: 0.9, brightness: 1),
                            Color(hue: ((theme.hue + 40).truncatingRemainder(dividingBy: 360)) / 360, saturation: 0.85, brightness: 1),
                            theme.accent.opacity(0.2),
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lw * 1.75, lineCap: .round)
                )
                .rotationEffect(.degrees(-90 + Double(shownKmh) * 0.15))
                .shadow(color: theme.glow.opacity(1), radius: 12)

        case .plaidHeat:
            Circle()
                .trim(from: 0, to: max(0.02, speedProgress))
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(red: 1.0, green: 0.92, blue: 0.25),
                            Color(red: 1.0, green: 0.55, blue: 0.08),
                            Color(red: 0.95, green: 0.12, blue: 0.08),
                            Color(red: 0.75, green: 0.02, blue: 0.05),
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lw * 1.85, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: Color.orange.opacity(0.9), radius: 14)

        case .thin:
            Circle()
                .strokeBorder(theme.accent.opacity(0.55 + 0.25 * speedProgress), lineWidth: lw * 1.15)
                .shadow(color: theme.glow.opacity(1), radius: 8)
        }
    }

    private func bipolarPowerRing(lineWidth: CGFloat) -> some View {
        let regen = power < -1
        let drive = power > 1
        let fill = powerFill
        let track = lineWidth * 1.35
        return ZStack {
            Circle()
                .trim(from: 0.12, to: 0.88)
                .stroke(Color.white.opacity(0.10), style: StrokeStyle(lineWidth: track, lineCap: .round))
                .rotationEffect(.degrees(90))

            if regen {
                Circle()
                    .trim(from: 0.50 - 0.38 * fill, to: 0.50)
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color(red: 0.2, green: 0.9, blue: 0.5).opacity(0.35),
                                Color(red: 0.35, green: 0.95, blue: 0.65),
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: track * 1.15, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .shadow(color: Color.green.opacity(0.6), radius: 8)
            }

            if drive {
                Circle()
                    .trim(from: 0.50, to: 0.50 + 0.38 * fill)
                    .stroke(
                        AngularGradient(
                            colors: [
                                theme.accent.opacity(0.4),
                                Color.orange,
                                Color.yellow.opacity(0.9),
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: track * 1.15, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .shadow(color: Color.orange.opacity(0.55), radius: 8)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: displayPower)
    }

    private var gearRow: some View {
        Text(shownGear.isEmpty ? "P" : String(shownGear.prefix(1)))
            .font(EtubuClusterFonts.gauge(gearFont, weight: .bold))
            .foregroundStyle(theme.accent)
            .minimumScaleFactor(0.7)
            .lineLimit(1)
            .frame(height: gearFont * 1.15)
            .accessibilityIdentifier("etubu.gear")
    }
}

enum EtubuHazardChrome {
    static func icon(_ kind: String) -> String {
        switch kind {
        case "corridor": return "gauge.with.dots.needle.67percent"
        case "charge": return "bolt.fill"
        case "weather": return "cloud.rain.fill"
        case "control": return "shield.fill"
        case "railway": return "tram.fill"
        case "traffic_light": return "trafficlight.fill"
        case "stop": return "octagon.fill"
        case "give_way": return "exclamationmark.triangle.fill"
        case "crossing": return "figure.walk"
        case "bump": return "arrow.up.and.down"
        case "tunnel": return "rectangle.split.1x2"
        case "underpass": return "arrow.down.to.line"
        case "overpass": return "arrow.up.to.line"
        case "winding": return "arrow.uturn.right"
        case "climb": return "triangle.fill"
        case "road_condition": return "exclamationmark.triangle.fill"
        case "animal": return "hare.fill"
        default: return "camera.metering.spot"
        }
    }

    static func kicker(_ kind: String, urgent: Bool) -> String {
        switch kind {
        case "corridor": return EtubuClusterL10n.t("warnKickerCorridor")
        case "charge": return EtubuClusterL10n.t("warnKickerCharge")
        case "weather": return EtubuClusterL10n.t("warnKickerWeather")
        case "control": return EtubuClusterL10n.t("warnKickerControl")
        case "railway": return EtubuClusterL10n.t("warnKindRailway")
        case "traffic_light": return EtubuClusterL10n.t("warnKindTrafficLight")
        case "stop": return EtubuClusterL10n.t("warnKindStop")
        case "give_way": return EtubuClusterL10n.t("warnKindGiveWay")
        case "crossing": return EtubuClusterL10n.t("warnKindCrossing")
        case "bump": return EtubuClusterL10n.t("warnKindBump")
        case "tunnel": return EtubuClusterL10n.t("warnKindTunnel")
        case "underpass": return EtubuClusterL10n.t("warnKindUnderpass")
        case "overpass": return EtubuClusterL10n.t("warnKindOverpass")
        case "winding": return EtubuClusterL10n.t("warnKindWinding")
        case "climb": return EtubuClusterL10n.t("warnKindClimb")
        case "road_condition": return EtubuClusterL10n.t("warnKindRoadCondition")
        case "animal": return EtubuClusterL10n.t("warnKindAnimal")
        default: return urgent ? EtubuClusterL10n.t("warnKickerCritical") : EtubuClusterL10n.t("warnKickerRadar")
        }
    }

    /// TTS için TR kök — EtubuWarnVoice composeKeys ile uyumlu.
    static func speakRootTR(_ kind: String) -> String {
        switch kind {
        case "corridor": return "hız koridoru"
        case "charge": return "şarj istasyonu"
        case "weather": return "hava olayı"
        case "control": return "kontrol"
        case "railway": return "demiryolu geçidi"
        case "traffic_light": return "trafik lambası"
        case "stop": return "dur"
        case "give_way": return "yol ver"
        case "crossing": return "yaya geçidi"
        case "bump": return "tümsek"
        case "tunnel": return "karayolu tüneli"
        case "underpass": return "alt geçit"
        case "overpass": return "üst geçit"
        case "winding": return "virajlı yol"
        case "climb": return "tırmanış"
        case "road_condition": return "yol şartı"
        case "animal": return "hayvan geçişi"
        default: return "radar"
        }
    }

    /// Web `.hud-map-mark--*` palette — cluster themes use accent for default radar when not urgent.
    static func tint(_ kind: String, urgent: Bool, theme: ClusterTheme) -> Color {
        switch kind {
        case "corridor": return Color(red: 1.0, green: 0.76, blue: 0.30) // #ffc14d
        case "charge": return Color(red: 0.18, green: 1.0, blue: 0.60) // #2dff9a
        case "weather": return Color(red: 0.56, green: 0.78, blue: 1.0) // #8ec8ff
        case "control": return Color(red: 1.0, green: 0.54, blue: 0.30) // #ff8a4d
        case "railway": return Color(red: 0.75, green: 0.55, blue: 1.0)
        case "traffic_light", "stop", "give_way": return Color(red: 1.0, green: 0.62, blue: 0.28)
        case "crossing", "bump": return Color(red: 0.95, green: 0.72, blue: 0.35)
        case "tunnel", "underpass", "overpass": return Color(red: 0.55, green: 0.72, blue: 0.95)
        case "winding", "climb": return Color(red: 0.95, green: 0.55, blue: 0.28)
        case "road_condition", "animal": return Color(red: 1.0, green: 0.45, blue: 0.22)
        default: return urgent ? Color(red: 1.0, green: 0.35, blue: 0.35) : theme.accent
        }
    }

    /// Fixed HUD fills for map pins (independent of theme accent).
    static func mapFill(_ kind: String) -> Color {
        switch kind {
        case "corridor": return Color(red: 1.0, green: 0.76, blue: 0.30)
        case "charge": return Color(red: 0.18, green: 1.0, blue: 0.60)
        case "weather": return Color(red: 0.56, green: 0.78, blue: 1.0)
        case "control": return Color(red: 1.0, green: 0.54, blue: 0.30)
        case "railway": return Color(red: 0.75, green: 0.55, blue: 1.0)
        case "traffic_light", "stop", "give_way": return Color(red: 1.0, green: 0.62, blue: 0.28)
        case "crossing", "bump": return Color(red: 0.95, green: 0.72, blue: 0.35)
        case "tunnel", "underpass", "overpass": return Color(red: 0.55, green: 0.72, blue: 0.95)
        case "winding", "climb": return Color(red: 0.95, green: 0.55, blue: 0.28)
        case "road_condition", "animal": return Color(red: 1.0, green: 0.45, blue: 0.22)
        default: return Color(red: 1.0, green: 0.35, blue: 0.35) // #ff5a5a
        }
    }
}

/// Harita hazard marker — web HUD mark (halo + tinted disc + dark glyph).
struct EtubuMapHazardMark: View {
    let kind: String
    let theme: ClusterTheme
    var compact: Bool = true

    private var fill: Color { EtubuHazardChrome.mapFill(kind) }
    private var core: CGFloat { compact ? 18 : 22 }

    var body: some View {
        ZStack {
            // Halo — web .hud-map-mark-halo
            Circle()
                .fill(Color(red: 0.02, green: 0.05, blue: 0.09).opacity(0.88))
                .frame(width: core + 8, height: core + 8)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.55), lineWidth: 1.2)
                )

            // Core disc
            Circle()
                .fill(fill)
                .frame(width: core, height: core)
                .overlay(
                    Circle()
                        .strokeBorder(Color(red: 0.02, green: 0.06, blue: 0.09), lineWidth: 1.4)
                )

            Image(systemName: EtubuHazardChrome.icon(kind))
                .font(.system(size: compact ? 9 : 11, weight: .bold))
                .foregroundStyle(Color(red: 0.02, green: 0.06, blue: 0.09))
        }
        .shadow(color: fill.opacity(0.85), radius: 5, y: 0)
        .accessibilityLabel(EtubuHazardChrome.kicker(kind, urgent: false))
    }
}

/// Araç konumu — Navigasyon oku boyutunda, içi dolu üstten araç silüeti ve 3D ön yol huzmesi (Canlı Kırmızı).
struct EtubuMapVehicleMark: View {
    var headingDeg: Double?
    var is3D: Bool = false

    var body: some View {
        let redPrimary = Color(red: 0.95, green: 0.10, blue: 0.15)
        let redDark = Color(red: 0.72, green: 0.04, blue: 0.08)
        let redBright = Color(red: 1.0, green: 0.22, blue: 0.25)

        ZStack {
            if is3D {
                // 3D Cockpit forward headlights / navigation road beam (Canlı kırmızı huzme)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [redPrimary.opacity(0.50), redPrimary.opacity(0.12), .clear],
                            center: .center,
                            startRadius: 2,
                            endRadius: 28
                        )
                    )
                    .frame(width: 56, height: 56)
                    .allowsHitTesting(false)
            } else {
                Circle()
                    .fill(redPrimary.opacity(0.22))
                    .frame(width: 44, height: 44)
                    .allowsHitTesting(false)
            }

            // Top-down filled car silhouette sized to navigation marker (~20x38pt)
            ZStack {
                // Dark background shadow for sharp contrast over maps
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(0.85))
                    .frame(width: 22, height: 38)
                    .blur(radius: 1.2)

                // Navigation Arrow / Forward Direction Pointer
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(redBright)
                    .offset(y: -19)
                    .shadow(color: redPrimary.opacity(0.9), radius: 3)

                // Filled Vehicle Silhouette in vibrant automotive red
                Image("EtubuCarTopUp")
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(width: 18, height: 34)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [redBright, redPrimary, redDark],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: redPrimary.opacity(0.95), radius: 6)
            }
            .rotationEffect(.degrees(is3D ? 0 : (headingDeg ?? 0)))
        }
    }
}

struct EtubuWarnBannerView: View {
    let item: EtubuWarnItem
    let theme: ClusterTheme

    private var urgent: Bool {
        item.stage == .critical || item.stage == .near
    }

    private var tint: Color {
        EtubuHazardChrome.tint(item.kind, urgent: urgent, theme: theme)
    }

    var body: some View {
        // Yazı sabit; yalnızca renk nabız atar (ölçek/opacity blink yok)
        TimelineView(.animation(minimumInterval: urgent ? 1.0 / 8.0 : 1.0, paused: !urgent)) { timeline in
            let pulse = urgent
                ? (0.55 + 0.45 * abs(sin(timeline.date.timeIntervalSinceReferenceDate * 3.2)))
                : 1.0
            let liveTint = tint.opacity(pulse)
            HStack(spacing: 12) {
                Image(systemName: EtubuHazardChrome.icon(item.kind))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(liveTint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(EtubuHazardChrome.kicker(item.kind, urgent: urgent))
                        .font(EtubuClusterFonts.ui(10, weight: .heavy))
                        .tracking(1)
                        .foregroundStyle(liveTint)
                    Text(item.title)
                        .font(EtubuClusterFonts.ui(15, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(2)
                    if !item.meta.isEmpty {
                        Text(item.meta)
                            .font(EtubuClusterFonts.ui(11, weight: .medium))
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if !item.distanceLabel.isEmpty {
                    Text(item.distanceLabel)
                        .font(EtubuClusterFonts.gauge(20))
                        .monospacedDigit()
                        .foregroundStyle(theme.primaryText)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(liveTint.opacity(0.75), lineWidth: 1.2)
                    )
            )
            .shadow(color: liveTint.opacity(urgent ? 0.45 : 0.25), radius: urgent ? 12 : 6)
        }
    }
}

/// Web `#hudWarnSide` — title + distance (primary road warning under avg column).
struct EtubuHudWarnSideView: View {
    let item: EtubuWarnItem
    let theme: ClusterTheme
    var compact: Bool = false
    /// When true, no fill / stroke chrome around the warning.
    var frameless: Bool = true
    /// Scale labels / distance numerals (portrait ~1.1, landscape ~1.3).
    var contentScale: CGFloat = 1

    private var urgent: Bool {
        item.stage == .critical || item.stage == .near
    }

    private var tint: Color {
        EtubuHazardChrome.tint(item.kind, urgent: urgent, theme: theme)
    }

    private var stageOpacity: Double {
        switch item.stage {
        case .critical: return 1
        case .near: return 0.95
        case .mid: return 0.78
        case .far: return 0.55
        case .idle: return 0.35
        }
    }

    var body: some View {
        // Mesafe/başlık sabit; kritikte yalnızca renk nabız atar
        TimelineView(.animation(minimumInterval: urgent ? 1.0 / 8.0 : 1.0, paused: !urgent)) { timeline in
            let pulse = urgent
                ? (0.55 + 0.45 * abs(sin(timeline.date.timeIntervalSinceReferenceDate * 3.2)))
                : 1.0
            let liveTint = tint.opacity(pulse)
            VStack(spacing: 4) {
                Text(item.title.isEmpty ? EtubuHazardChrome.kicker(item.kind, urgent: urgent) : item.title)
                    .font(EtubuClusterFonts.ui((compact ? 11 : 12) * contentScale, weight: .bold))
                    .foregroundStyle(liveTint)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(item.distanceLabel.isEmpty ? "—" : item.distanceLabel)
                    .font(EtubuClusterFonts.gauge((compact ? 22 : 28) * contentScale))
                    .monospacedDigit()
                    .foregroundStyle(theme.primaryText)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                if !item.meta.isEmpty {
                    Text(item.meta)
                        .font(EtubuClusterFonts.ui(10 * contentScale, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, compact ? 8 : 10)
            .background {
                if !frameless {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.28))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(liveTint.opacity(urgent ? 0.7 : 0.35), lineWidth: 1)
                        )
                }
            }
            .shadow(color: frameless ? .clear : liveTint.opacity(urgent ? 0.4 : 0.12), radius: urgent ? 10 : 4)
            .opacity(stageOpacity)
        }
    }
}

/// Secondary ahead items (web warn-reel queue) — same kinds as RouteGuard / RadarAlert.
struct EtubuWarnReelView: View {
    let items: [EtubuWarnItem]
    let theme: ClusterTheme
    var vertical: Bool = false

    var body: some View {
        let secondary = Array(items.dropFirst().prefix(vertical ? 2 : 3))
        if !secondary.isEmpty {
            if vertical {
                // Web warn-reel: vertical slots under primary
                VStack(spacing: 4) {
                    ForEach(Array(secondary.enumerated()), id: \.element.id) { idx, item in
                        HStack(spacing: 6) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(EtubuClusterFonts.ui(11, weight: .semibold))
                                    .foregroundStyle(theme.primaryText.opacity(idx == 0 ? 0.9 : 0.55))
                                    .lineLimit(1)
                                if !item.distanceLabel.isEmpty {
                                    Text(item.distanceLabel)
                                        .font(EtubuClusterFonts.ui(11, weight: .medium))
                                        .monospacedDigit()
                                        .foregroundStyle(theme.mutedText)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(idx == 0 ? 0.08 : 0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(theme.stroke.opacity(0.8), lineWidth: 1)
                                )
                        )
                        .opacity(idx == 0 ? 0.85 : 0.45)
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(secondary) { item in
                            HStack(spacing: 6) {
                                Image(systemName: EtubuHazardChrome.icon(item.kind))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(EtubuHazardChrome.tint(item.kind, urgent: false, theme: theme))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title)
                                        .font(EtubuClusterFonts.ui(11, weight: .semibold))
                                        .foregroundStyle(theme.primaryText.opacity(0.9))
                                        .lineLimit(1)
                                    if !item.distanceLabel.isEmpty {
                                        Text(item.distanceLabel)
                                            .font(EtubuClusterFonts.ui(11, weight: .medium))
                                            .monospacedDigit()
                                            .foregroundStyle(theme.mutedText)
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(theme.surface)
                                    .overlay(Capsule().strokeBorder(theme.stroke, lineWidth: 1))
                            )
                        }
                    }
                }
            }
        }
    }
}

struct EtubuRouteBriefChipsView: View {
    let brief: EtubuRouteBriefSummary
    var compact: Bool = false

    private var chips: [(String, Int, String, Color)] {
        [
            ("camera.metering.spot", brief.radarCount, EtubuClusterL10n.t("routeRadar"), .orange),
            ("exclamationmark.triangle.fill", brief.osmCriticalCount, EtubuClusterL10n.t("routeOsmCritical"), .yellow),
            ("mappin.and.ellipse", brief.controlCount, EtubuClusterL10n.t("routeControl"), .purple),
            ("gauge.with.dots.needle.67percent", brief.corridorCount, EtubuClusterL10n.t("radarCorridor"), .orange),
            ("bolt.car.fill", brief.chargeCount, EtubuClusterL10n.t("routeCharge"), .cyan),
        ]
    }

    var body: some View {
        if brief.hasAny {
            VStack(alignment: .leading, spacing: compact ? 6 : 8) {
                FlowChips(items: chips.filter { $0.1 > 0 }, compact: compact)
                if !brief.chargeNames.isEmpty {
                    Text(brief.chargeNames.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(2)
                }
                if brief.weatherCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "cloud.bolt.rain.fill")
                            .font(.system(size: compact ? 9 : 10, weight: .bold))
                        Text("\(brief.weatherCount)")
                            .font(EtubuClusterFonts.ui(compact ? 11 : 12, weight: .bold))
                            .monospacedDigit()
                        if !compact {
                            Text(EtubuClusterL10n.t("routeWeatherEvents"))
                                .font(EtubuClusterFonts.ui(10, weight: .semibold))
                        }
                    }
                    .foregroundStyle(Color.blue)
                    .padding(.horizontal, compact ? 8 : 10)
                    .padding(.vertical, compact ? 5 : 6)
                    .background(Capsule().fill(Color.blue.opacity(0.14)))
                }
                if !brief.weatherLabels.isEmpty {
                    Text(brief.weatherLabels.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.blue.opacity(0.75))
                        .lineLimit(2)
                }
            }
        }
    }
}

private struct FlowChips: View {
    let items: [(String, Int, String, Color)]
    var compact: Bool

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 4) {
                    Image(systemName: item.0)
                        .font(.system(size: compact ? 9 : 10, weight: .bold))
                    Text("\(item.1)")
                        .font(EtubuClusterFonts.ui(compact ? 11 : 12, weight: .bold))
                        .monospacedDigit()
                    if !compact {
                        Text(item.2)
                            .font(EtubuClusterFonts.ui(10, weight: .semibold))
                    }
                }
                .foregroundStyle(item.3)
                .padding(.horizontal, compact ? 8 : 10)
                .padding(.vertical, compact ? 5 : 6)
                .background(Capsule().fill(item.3.opacity(0.14)))
            }
        }
    }
}

/// Web `avg-speed-panel` — twin of road-warning card (Jul 29 equal panels).
struct EtubuCorridorChipView: View {
    @ObservedObject var warnings: EtubuDriveWarnings
    var theme: ClusterTheme = .aurora
    var compact: Bool = false
    var contentScale: CGFloat = 1

    private var isCorridor: Bool { warnings.corridorActive }
    private var isOver: Bool { warnings.corridorOver }
    private var avg: Int { warnings.corridorAvgKmh }

    private var titleSize: CGFloat { (isCorridor ? 11 : 10) * contentScale }
    private var avgSize: CGFloat {
        // Landscape (compact) +15% on average speed digits
        let base = (isCorridor ? (compact ? 26 : 30) : (compact ? 20 : 24)) * contentScale
        return compact ? base * 1.15 : base
    }
    private var metaSize: CGFloat { 10 * contentScale }

    var body: some View {
        VStack(spacing: compact ? 3 : 5) {
            if isCorridor {
                Text(warnings.corridorLabel.isEmpty
                     ? EtubuClusterL10n.radarCorridor.uppercased()
                     : warnings.corridorLabel.uppercased())
                    .font(EtubuClusterFonts.ui(8 * contentScale, weight: .heavy))
                    .tracking(0.3)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [Color(red: 1, green: 0.82, blue: 0.48), Color(red: 1, green: 0.69, blue: 0.13)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    )
                    .foregroundStyle(Color(red: 0.1, green: 0.07, blue: 0.02))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .allowsTightening(true)
                    .frame(maxWidth: .infinity)

                Text(EtubuClusterL10n.corridorAvg)
                    .font(EtubuClusterFonts.ui(titleSize, weight: .semibold))
                    .foregroundStyle(Color(red: 1, green: 0.9, blue: 0.67).opacity(0.9))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .allowsTightening(true)
                    .frame(maxWidth: .infinity)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    if isOver {
                        TimelineView(.animation(minimumInterval: 1.0 / 8.0, paused: false)) { timeline in
                            let pulse = 0.55 + 0.45 * abs(sin(timeline.date.timeIntervalSinceReferenceDate * 3.2))
                            Text("\(avg)")
                                .font(EtubuClusterFonts.gauge(avgSize))
                                .monospacedDigit()
                                .foregroundStyle(Color(red: 1, green: 0.35, blue: 0.35).opacity(pulse))
                                .minimumScaleFactor(0.55)
                                .lineLimit(1)
                        }
                    } else {
                        Text("\(avg)")
                            .font(EtubuClusterFonts.gauge(avgSize))
                            .monospacedDigit()
                            .foregroundStyle(Color(red: 1, green: 0.88, blue: 0.54))
                            .minimumScaleFactor(0.55)
                            .lineLimit(1)
                    }
                    Text(EtubuClusterL10n.t("corridorAvgUnit"))
                        .font(EtubuClusterFonts.ui(9 * contentScale, weight: .medium))
                        .foregroundStyle(theme.mutedText.opacity(0.8))
                }

                HStack(spacing: 8) {
                    if warnings.corridorInstantKmh > 0 {
                        Text("\(EtubuClusterL10n.t("corridorInstant")) \(warnings.corridorInstantKmh)")
                            .font(EtubuClusterFonts.ui(metaSize, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    if let limit = warnings.corridorLimit {
                        Text("\(EtubuClusterL10n.t("corridorLimitShort")) \(limit)")
                            .font(EtubuClusterFonts.ui(metaSize, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                .frame(maxWidth: .infinity)
                .clipped()

                if !warnings.corridorRemainLabel.isEmpty {
                    Text(warnings.corridorRemainLabel)
                        .font(EtubuClusterFonts.ui(metaSize + 1, weight: .heavy))
                        .foregroundStyle(Color(red: 1, green: 0.88, blue: 0.54))
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .allowsTightening(true)
                        .frame(maxWidth: .infinity)
                }
                if isOver {
                    TimelineView(.animation(minimumInterval: 1.0 / 8.0, paused: false)) { timeline in
                        let pulse = 0.55 + 0.45 * abs(sin(timeline.date.timeIntervalSinceReferenceDate * 3.2))
                        Text(EtubuClusterL10n.slowDown)
                            .font(EtubuClusterFonts.ui(10 * contentScale, weight: .black))
                            .foregroundStyle(Color.red.opacity(pulse))
                            .lineLimit(1)
                    }
                }
            } else {
                // Ortalama hız yalnız hız koridoru içinde — dışında idle.
                Text(EtubuClusterL10n.corridorAvg)
                    .font(EtubuClusterFonts.ui(titleSize, weight: .semibold))
                    .foregroundStyle(theme.mutedText)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .allowsTightening(true)
                    .frame(maxWidth: .infinity)
                Text("—")
                    .font(EtubuClusterFonts.gauge(avgSize))
                    .foregroundStyle(theme.mutedText.opacity(0.55))
                Text(EtubuClusterL10n.t("corridorIdleHint"))
                    .font(EtubuClusterFonts.ui(metaSize, weight: .medium))
                    .foregroundStyle(theme.mutedText.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .modifier(EtubuTwinCardChrome(
            theme: theme,
            stroke: isOver ? Color.red.opacity(0.75) : (isCorridor ? Color.orange.opacity(0.65) : theme.accent.opacity(0.35)),
            warmFill: isCorridor,
            shadowColor: isOver ? Color.red.opacity(0.35) : (isCorridor ? Color.orange.opacity(0.2) : Color.black.opacity(0.32))
        ))
    }
}

/// Twin of avg card — same frame size; kind icon + distance; extras clipped to fit.
struct EtubuRoadWarnTwinView: View {
    @ObservedObject var warnings: EtubuDriveWarnings
    var theme: ClusterTheme
    var compact: Bool = false
    var contentScale: CGFloat = 1

    private var urgent: Bool {
        guard let p = warnings.primary else { return false }
        return p.stage == .critical || p.stage == .near
    }

    private var titleSize: CGFloat { (compact ? 9 : 10) * contentScale }
    private var valueSize: CGFloat { (compact ? 18 : 22) * contentScale }
    private var metaSize: CGFloat { (compact ? 8 : 9) * contentScale }

    var body: some View {
        let tint = EtubuHazardChrome.tint(warnings.primary?.kind ?? "radar", urgent: urgent, theme: theme)
        VStack(alignment: .center, spacing: compact ? 2 : 3) {
            Text(EtubuClusterL10n.roadWarnings.uppercased())
                .font(EtubuClusterFonts.ui(titleSize, weight: .heavy))
                .tracking(0.25)
                .foregroundStyle(theme.mutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .allowsTightening(true)
                .frame(maxWidth: .infinity)

            if let item = warnings.primary {
                HStack(spacing: 5) {
                    Image(systemName: EtubuHazardChrome.icon(item.kind))
                        .font(.system(size: (compact ? 11 : 13) * contentScale, weight: .bold))
                        .foregroundStyle(tint)
                    Text(EtubuHazardChrome.kicker(item.kind, urgent: urgent))
                        .font(EtubuClusterFonts.ui((compact ? 8 : 9) * contentScale, weight: .heavy))
                        .foregroundStyle(tint.opacity(0.95))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }

                Text(item.distanceLabel.isEmpty ? "—" : item.distanceLabel)
                    .font(EtubuClusterFonts.gauge(valueSize))
                    .monospacedDigit()
                    .foregroundStyle(urgent ? tint : theme.primaryText)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .layoutPriority(3)

                // Alta sığan ek bilgi
                Text(item.title.isEmpty ? "—" : item.title)
                    .font(EtubuClusterFonts.ui(metaSize, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(compact ? 1 : 2)
                    .minimumScaleFactor(0.6)

                if !compact, !item.meta.isEmpty {
                    Text(item.meta)
                        .font(EtubuClusterFonts.ui(metaSize, weight: .medium))
                        .foregroundStyle(theme.mutedText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            } else {
                Text("—")
                    .font(EtubuClusterFonts.gauge(valueSize))
                    .foregroundStyle(theme.mutedText.opacity(0.4))
                Text(EtubuClusterL10n.t("roadClear"))
                    .font(EtubuClusterFonts.ui(metaSize, weight: .medium))
                    .foregroundStyle(theme.mutedText.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .modifier(EtubuTwinCardChrome(
            theme: theme,
            stroke: urgent ? tint.opacity(0.8) : theme.accent.opacity(0.55),
            warmFill: false,
            shadowColor: urgent ? tint.opacity(0.22) : Color.black.opacity(0.32)
        ))
    }
}

/// Shared Jul 29 twin-panel chrome — completely transparent HUD background without border or box.
private struct EtubuTwinCardChrome: ViewModifier {
    var theme: ClusterTheme
    var stroke: Color
    var warmFill: Bool
    var shadowColor: Color

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
            .background(Color.clear)
    }
}

/// Regen-only meter (tüketim barı yok).
struct EtubuPowerRegenBarView: View {
    let powerKw: Int?
    var compact: Bool = false
    var theme: ClusterTheme = .aurora
    @State private var displayKw: Double = 0

    private var targetPower: Int {
        let raw = powerKw ?? 0
        return abs(raw) < 4 ? 0 : raw
    }
    private var regenerating: Bool { displayKw < -1 }
    private var fill: CGFloat {
        min(1, CGFloat(abs(displayKw)) / 160.0)
    }
    private var labelColor: Color {
        regenerating ? Color(red: 0.35, green: 0.92, blue: 0.55) : theme.mutedText
    }

    var body: some View {
        // Tüketim (POWER) gösterilmez — yalnızca regen.
        Group {
            if regenerating {
                VStack(alignment: .leading, spacing: compact ? 4 : 6) {
                    HStack {
                        Text("REGEN")
                            .font(EtubuClusterFonts.ui(10, weight: .heavy))
                            .tracking(1)
                            .foregroundStyle(labelColor)
                        Spacer()
                        Text("\(Int(displayKw.rounded())) kW")
                            .font(EtubuClusterFonts.gauge(compact ? 13 : 15))
                            .monospacedDigit()
                            .foregroundStyle(labelColor)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(theme.surface.opacity(0.55))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.2, green: 0.85, blue: 0.45).opacity(0.95),
                                            Color(red: 0.35, green: 0.95, blue: 0.65).opacity(0.55),
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(4, geo.size.width * fill))
                        }
                    }
                    .frame(height: compact ? 8 : 10)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Regen \(Int(displayKw.rounded())) kilowatt")
            }
        }
        .onAppear { displayKw = Double(targetPower) }
        .onChange(of: targetPower) { _, new in
            withAnimation(.easeInOut(duration: 0.32)) {
                displayKw = Double(new)
            }
        }
    }
}
