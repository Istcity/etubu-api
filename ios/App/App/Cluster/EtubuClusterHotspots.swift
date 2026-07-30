import SwiftUI

/// Named UI regions for onboarding coach-marks / spotlights.
enum EtubuClusterHotspotID: String, Hashable, CaseIterable {
    case pair
    case dial
    case route
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

/// Pair / connection control with living glow while pairing, solid green when linked.
struct EtubuPairConnectionBadge: View {
    let connectionState: EtubuVehicleConnectionState
    let theme: ClusterTheme
    var label: String? = nil
    var compact: Bool = false

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
        .onAppear {
            guard isPairing else { return }
            withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
        .onChange(of: isPairing) { _, pairing in
            if pairing {
                pulse = false
                withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            } else {
                pulse = false
            }
        }
        .animation(.easeInOut(duration: 0.35), value: connectionState)
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
    }

    private var iconOnlyBadge: some View {
        ZStack {
            if isPairing {
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
            if isPairing {
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
