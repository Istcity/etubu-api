import SwiftUI

/// Named UI regions for onboarding coach-marks / spotlights.
enum EtubuClusterHotspotID: String, Hashable, CaseIterable {
    case pair
    case dial
    case route
    case remote
    case settings
    case sound
}

struct EtubuHotspotFramesKey: PreferenceKey {
    static var defaultValue: [EtubuClusterHotspotID: CGRect] = [:]
    static func reduce(value: inout [EtubuClusterHotspotID: CGRect], nextValue: () -> [EtubuClusterHotspotID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    /// Report this view’s frame in the named cluster coordinate space.
    func clusterHotspot(_ id: EtubuClusterHotspotID) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: EtubuHotspotFramesKey.self,
                    value: [id: geo.frame(in: .named("etubuCluster"))]
                )
            }
        )
    }
}

/// Soft spotlight hole over a target rect + modern coach card.
struct EtubuSpotlightHole: Shape {
    var hole: CGRect
    var cornerRadius: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        let r = hole.insetBy(dx: -6, dy: -6)
        path.addRoundedRect(in: r, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
        return path
    }
}

/// Pair rozeti çevresinde dönen / genişleyen pulse — dikey ve yatayda hotspot’a kilitli.
struct EtubuPairSpotlightPulse: View {
    var hole: CGRect
    var color: Color
    @State private var phase = false

    var body: some View {
        let w = hole.width + 18
        let h = hole.height + 18
        let radius = min(22, h * 0.45)
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: radius + CGFloat(i) * 2, style: .continuous)
                    .stroke(color.opacity(0.7 - Double(i) * 0.18), lineWidth: 2.2 - CGFloat(i) * 0.3)
                    .frame(width: w + CGFloat(i) * 10, height: h + CGFloat(i) * 10)
                    .scaleEffect(phase ? 1.12 + CGFloat(i) * 0.08 : 1.0)
                    .opacity(phase ? 0.08 : 0.85)
            }
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(
                    AngularGradient(
                        colors: [
                            color.opacity(0.25),
                            color,
                            Color.white.opacity(0.95),
                            color.opacity(0.25)
                        ],
                        center: .center
                    ),
                    lineWidth: 2.6
                )
                .frame(width: w, height: h)
                .shadow(color: color.opacity(0.55), radius: 14)
        }
        .position(x: hole.midX, y: hole.midY)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: false)) {
                phase = true
            }
        }
    }
}

/// Pair / connection control with living glow while pairing, solid green when linked.
struct EtubuPairConnectionBadge: View {
    let connectionState: EtubuVehicleConnectionState
    let theme: ClusterTheme
    var label: String? = nil
    var compact: Bool = false
    /// Rehber kartındaki kopyada pulse kapalı — asıl rozette kalsın.
    var showPulse: Bool = true

    @State private var pulse = false

    private var isPairing: Bool {
        switch connectionState {
        case .pairing, .waitingForCard, .connecting, .reconnecting: return true
        default: return false
        }
    }

    private var isConnected: Bool { connectionState == .connected }

    private var glow: Color {
        if isConnected { return .green }
        if isPairing { return theme.accent }
        return .red.opacity(0.9)
    }

    private var iconName: String {
        isConnected ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash"
    }

    var body: some View {
        Group {
            if let label, !label.isEmpty {
                labeledBadge(label)
            } else {
                iconOnlyBadge
            }
        }
        .onAppear { startPulseIfNeeded() }
        .onChange(of: isPairing) { _, pairing in
            if pairing { startPulseIfNeeded() }
            else { pulse = false }
        }
        .animation(.easeInOut(duration: 0.35), value: connectionState)
    }

    private func startPulseIfNeeded() {
        guard showPulse, isPairing else {
            pulse = false
            return
        }
        pulse = false
        withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: false)) {
            pulse = true
        }
    }

    private func labeledBadge(_ label: String) -> some View {
        HStack(spacing: compact ? 6 : 8) {
            pulseDot
            Text(label)
                .font(EtubuClusterFonts.ui(compact ? 12 : 13, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(isConnected ? Color.white : theme.primaryText)
        .padding(.horizontal, compact ? 10 : 12)
        .padding(.vertical, compact ? 6 : 7)
        .background(capsuleChrome)
        .overlay {
            if showPulse, isPairing {
                Capsule()
                    .stroke(glow.opacity(pulse ? 0.15 : 0.85), lineWidth: 2)
                    .scaleEffect(pulse ? 1.18 : 1.0)
                    .opacity(pulse ? 0.05 : 0.9)
                Capsule()
                    .stroke(glow.opacity(0.45), lineWidth: 1.4)
                    .scaleEffect(pulse ? 1.32 : 1.0)
                    .opacity(pulse ? 0.05 : 0.7)
            }
        }
    }

    private var iconOnlyBadge: some View {
        ZStack {
            if showPulse, isPairing {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(glow.opacity(0.55 - Double(i) * 0.15), lineWidth: 1.6)
                        .frame(width: 34, height: 34)
                        .scaleEffect(pulse ? 1.55 + CGFloat(i) * 0.28 : 1.0)
                        .opacity(pulse ? 0.05 : 0.85)
                }
            }
            Circle()
                .fill(isConnected ? Color.green.opacity(0.9) : (isPairing ? theme.accent.opacity(0.9) : Color.red.opacity(0.85)))
                .frame(width: 34, height: 34)
                .shadow(color: glow.opacity(isPairing || isConnected ? 0.75 : 0), radius: isPairing ? 14 : 6)
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 44, height: 44)
    }

    private var pulseDot: some View {
        ZStack {
            if showPulse, isPairing {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(glow.opacity(0.55 - Double(i) * 0.15), lineWidth: 1.5)
                        .frame(width: compact ? 14 : 16, height: compact ? 14 : 16)
                        .scaleEffect(pulse ? 1.55 + CGFloat(i) * 0.35 : 1.0)
                        .opacity(pulse ? 0.05 : 0.9)
                }
            }
            Circle()
                .fill(glow)
                .frame(width: compact ? 8 : 9, height: compact ? 8 : 9)
                .shadow(color: glow.opacity(isPairing || isConnected ? 0.85 : 0), radius: isPairing ? 8 : 4)
        }
        .frame(width: compact ? 22 : 26, height: compact ? 22 : 26)
    }

    private var capsuleChrome: some View {
        Capsule()
            .fill(isConnected ? Color.green.opacity(0.28) : theme.surface)
            .overlay(
                Capsule()
                    .strokeBorder(
                        isConnected ? Color.green.opacity(0.9) : (isPairing ? theme.accent.opacity(0.85) : theme.stroke),
                        lineWidth: isPairing || isConnected ? 1.4 : 1
                    )
            )
            .shadow(color: glow.opacity(isPairing ? 0.55 : (isConnected ? 0.35 : 0)), radius: isPairing ? 12 : 6)
    }
}
