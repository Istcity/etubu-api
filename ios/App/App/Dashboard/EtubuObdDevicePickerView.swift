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
                        Text(
                            telemetry.isScanning
                                ? EtubuClusterL10n.t("obdScanning")
                                : EtubuClusterL10n.t("obdEmpty")
                        )
                        .foregroundStyle(.secondary)
                        Text(EtubuClusterL10n.t("obdEmptyHint"))
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
            .navigationTitle(EtubuClusterL10n.t("obdPickTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(EtubuClusterL10n.close) { onClose() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(telemetry.isScanning ? EtubuClusterL10n.t("obdScanning") : EtubuClusterL10n.t("obdRescan")) {
                        EtubuObdBleManager.shared.startScanForPicker()
                    }
                    .disabled(telemetry.isScanning)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(EtubuClusterL10n.t("obdDisconnect"), role: .destructive) {
                        EtubuObdBleManager.shared.disconnect()
                        onClose()
                    }
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
