import SwiftUI

struct EtubuConnectionBar: View {
    @ObservedObject var telemetry: EtubuObdTelemetry
    var onConnect: () -> Void
    var onDisconnect: () -> Void
    var onPickDevice: () -> Void

    private var statusColor: Color {
        switch telemetry.connectionState {
        case .connected: return .green
        case .connecting, .scanning, .reconnecting: return .orange
        case .bluetoothUnavailable, .scanTimeout, .connectFailed: return .red
        default: return .secondary
        }
    }

    private var statusLabel: String {
        switch telemetry.connectionState {
        case .idle: return "Idle"
        case .scanning: return "Scanning…"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .reconnecting: return "Reconnecting…"
        case .disconnected: return "Disconnected"
        case .bluetoothUnavailable: return "Bluetooth off"
        case .scanTimeout: return "Scan timeout"
        case .connectFailed: return "Connect failed"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .shadow(color: statusColor.opacity(0.7), radius: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(telemetry.deviceName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(statusLabel)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()

            Button("Devices") { onPickDevice() }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.cyan)

            if telemetry.isConnected || telemetry.connectionState == .reconnecting {
                Button("Disconnect") { onDisconnect() }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                Button(telemetry.isBusy ? "…" : "Connect") { onConnect() }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.cyan, in: Capsule())
                    .disabled(telemetry.isBusy)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
