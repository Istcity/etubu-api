import SwiftUI

struct EtubuObdDevicePickerView: View {
    @ObservedObject var telemetry: EtubuObdTelemetry
    var onSelect: (UUID) -> Void
    var onClose: () -> Void

    var body: some View {
        NavigationView {
            List {
                if telemetry.discovered.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(telemetry.isScanning ? "Looking for OBD adapters…" : "No devices yet")
                            .foregroundStyle(.secondary)
                        Text("Turn on your ELM327 / OBD BLE adapter and keep the phone nearby.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(telemetry.discovered) { device in
                        Button {
                            onSelect(device.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                        .foregroundStyle(.primary)
                                    Text(device.id.uuidString.prefix(8) + "…")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(device.rssi) dBm")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("OBD Devices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onClose() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(telemetry.isScanning ? "Scanning…" : "Rescan") {
                        EtubuObdBleManager.shared.startScanForPicker()
                    }
                    .disabled(telemetry.isScanning)
                }
            }
            .onAppear {
                EtubuObdBleManager.shared.startScanForPicker()
            }
            .onDisappear {
                EtubuObdBleManager.shared.stopScanForPicker()
            }
        }
    }
}
