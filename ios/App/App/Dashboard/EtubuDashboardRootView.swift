import SwiftUI
import Combine

struct EtubuDashboardRootView: View {
    @ObservedObject private var telemetry = EtubuObdTelemetry.shared
    @State private var showPicker = false
    var onClose: () -> Void = {}

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.06, blue: 0.10),
                    Color(red: 0.02, green: 0.03, blue: 0.06),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    EtubuBrandMark(size: 22, showGlow: true)
                    Text("Dashboard")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
                .padding(.horizontal, 4)

                EtubuConnectionBar(
                    telemetry: telemetry,
                    onConnect: {
                        EtubuObdBleManager.shared.connect { _, _ in }
                    },
                    onDisconnect: {
                        EtubuObdBleManager.shared.disconnect()
                    },
                    onPickDevice: { showPicker = true }
                )

                Spacer(minLength: 8)

                EtubuGaugeClusterView(telemetry: telemetry)

                Spacer(minLength: 8)

                Text("Native BLE OBD · Live Activity sync")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.28))
            }
            .padding(20)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPicker) {
            EtubuObdDevicePickerView(
                telemetry: telemetry,
                onSelect: { id in
                    showPicker = false
                    EtubuObdBleManager.shared.connect(to: id) { _, _ in }
                },
                onClose: { showPicker = false }
            )
        }
        .onAppear { startLiveActivityIfNeeded() }
        .onReceive(telemetry.$kmh) { _ in pushLiveActivity() }
        .onReceive(telemetry.$rpm) { _ in pushLiveActivity() }
        .onReceive(telemetry.$connectionState) { state in
            if state == .connected { startLiveActivityIfNeeded() }
        }
    }

    private func startLiveActivityIfNeeded() {
        // LA yalnızca arka planda (AppDelegate) — ön planda başlatma.
    }

    private func pushLiveActivity() {
        guard #available(iOS 16.2, *) else { return }
        guard telemetry.isConnected else { return }
        let tires = EtubuVehicleTelemetry.shared
        Task {
            await EtubuLiveActivityController.update(
                kmh: telemetry.kmh,
                gear: "D",
                rpm: telemetry.rpm,
                voice: "OBD",
                source: "obd",
                tpmsFL: tires.tpmsFL.psi.map { Int($0.rounded()) },
                tpmsFR: tires.tpmsFR.psi.map { Int($0.rounded()) },
                tpmsRL: tires.tpmsRL.psi.map { Int($0.rounded()) },
                tpmsRR: tires.tpmsRR.psi.map { Int($0.rounded()) }
            )
        }
    }
}
