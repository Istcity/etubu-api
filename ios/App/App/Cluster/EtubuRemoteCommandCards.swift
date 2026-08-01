import SwiftUI
import TeslaBLE

/// Chinese-dash style one-tap BLE command cards + nearby Superchargers.
struct EtubuRemoteCommandCards: View {
    @ObservedObject var tesla: EtubuTeslaBleSession
    @State private var driverHeat: Int = 0
    @State private var passengerHeat: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(EtubuClusterL10n.t("remoteCmdHint"))
                .font(.caption2)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                cmd("snowflake", EtubuClusterL10n.t("cmdClimateOn")) {
                    await tesla.setClimate(on: true)
                }
                cmd("snowflake.slash", EtubuClusterL10n.t("cmdClimateOff")) {
                    await tesla.setClimate(on: false)
                }
                cmd("bolt.fill", EtubuClusterL10n.t("cmdChargeStart")) {
                    await tesla.setCharging(start: true)
                }
                cmd("bolt.slash.fill", EtubuClusterL10n.t("cmdChargeStop")) {
                    await tesla.setCharging(start: false)
                }
                cmd("lock.fill", EtubuClusterL10n.t("cmdLock")) {
                    await tesla.setLocked(true)
                }
                cmd("lock.open.fill", EtubuClusterL10n.t("cmdUnlock")) {
                    await tesla.setLocked(false)
                }
                cmd("shippingbox", EtubuClusterL10n.t("cmdFrunk")) {
                    await tesla.openFrunk()
                }
                cmd("car.rear", EtubuClusterL10n.t("cmdTrunk")) {
                    await tesla.openTrunk()
                }
                cmd("window.vertical.open", EtubuClusterL10n.t("cmdVentWindows")) {
                    await tesla.ventWindows()
                }
                cmd("window.vertical.closed", EtubuClusterL10n.t("cmdCloseWindows")) {
                    await tesla.closeWindows()
                }
                cmd("bolt.car", EtubuClusterL10n.t("cmdChargePort")) {
                    await tesla.openChargePort()
                }
                cmd("headlight.high.beam", EtubuClusterL10n.t("cmdFlash")) {
                    await tesla.flashLights()
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(EtubuClusterL10n.t("cmdSeatHeat"))
                    .font(.caption.weight(.semibold))
                seatRow(EtubuClusterL10n.t("cmdSeatDriver"), level: $driverHeat, seat: .frontLeft)
                seatRow(EtubuClusterL10n.t("cmdSeatPassenger"), level: $passengerHeat, seat: .frontRight)
            }
            .padding(.top, 4)

            Button {
                Task { await tesla.refreshNearbyChargers() }
            } label: {
                Label(EtubuClusterL10n.t("cmdNearbyCharge"), systemImage: "bolt.car")
            }
            .buttonStyle(.bordered)

            if !tesla.nearbyChargers.isEmpty {
                ForEach(tesla.nearbyChargers.prefix(5)) { site in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "bolt.car.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(site.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Text(site.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }

            if !tesla.lastCommandMessage.isEmpty {
                Text(tesla.lastCommandMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func cmd(_ symbol: String, _ title: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.caption2.weight(.medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
            )
        }
        .buttonStyle(.plain)
    }

    private func seatRow(_ title: String, level: Binding<Int>, seat: Command.Climate.SeatPosition) -> some View {
        HStack {
            Text(title)
                .font(.caption)
            Spacer()
            Picker(title, selection: level) {
                Text("0").tag(0)
                Text("1").tag(1)
                Text("2").tag(2)
                Text("3").tag(3)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 160)
            .onChange(of: level.wrappedValue) { _, newValue in
                Task {
                    await tesla.setSeatHeater(level: Self.heaterLevel(newValue), seat: seat)
                }
            }
        }
    }

    private static func heaterLevel(_ raw: Int) -> Command.Climate.SeatHeaterLevel {
        switch raw {
        case 1: return .low
        case 2: return .medium
        case 3: return .high
        default: return .off
        }
    }
}
