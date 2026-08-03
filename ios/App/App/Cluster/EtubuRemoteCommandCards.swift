import SwiftUI
import TeslaBLE

/// Chinese-dash style one-tap BLE command cards + nearby Superchargers.
/// Yeşil = kullanılabilir / açık durum; kırmızı = hareket kilidi veya kapalı/pasif.
struct EtubuRemoteCommandCards: View {
    @ObservedObject var tesla: EtubuTeslaBleSession
    @ObservedObject private var telemetry = EtubuVehicleTelemetry.shared
    @State private var driverHeat: Int = 0
    @State private var passengerHeat: Int = 0

    private var moving: Bool { telemetry.isVehicleMoving }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(EtubuClusterL10n.t("remoteCmdHint"))
                .font(.caption2)
                .foregroundStyle(.secondary)

            if moving {
                Text(EtubuClusterL10n.t("cmdMovingBlocked"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.red.opacity(0.9))
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                cmd(
                    "snowflake",
                    EtubuClusterL10n.t("cmdClimateOn"),
                    parkOnly: false,
                    active: telemetry.climateOn == true,
                    a11yId: "etubu.remote.climate.on"
                ) {
                    await tesla.setClimate(on: true)
                }
                cmd(
                    "snowflake.slash",
                    EtubuClusterL10n.t("cmdClimateOff"),
                    parkOnly: false,
                    active: telemetry.climateOn == false
                ) {
                    await tesla.setClimate(on: false)
                }
                cmd(
                    "bolt.fill",
                    EtubuClusterL10n.t("cmdChargeStart"),
                    parkOnly: false,
                    active: telemetry.isCharging
                ) {
                    await tesla.setCharging(start: true)
                }
                cmd(
                    "bolt.slash.fill",
                    EtubuClusterL10n.t("cmdChargeStop"),
                    parkOnly: false,
                    active: !telemetry.isCharging
                ) {
                    await tesla.setCharging(start: false)
                }
                cmd(
                    "lock.fill",
                    EtubuClusterL10n.t("cmdLock"),
                    parkOnly: false,
                    active: telemetry.locked == true
                ) {
                    await tesla.setLocked(true)
                }
                cmd(
                    "lock.open.fill",
                    EtubuClusterL10n.t("cmdUnlock"),
                    parkOnly: false,
                    active: telemetry.locked == false
                ) {
                    await tesla.setLocked(false)
                }
                cmd(
                    "shippingbox",
                    telemetry.frunkOpen == true
                        ? EtubuClusterL10n.t("cmdFrunkOpen")
                        : EtubuClusterL10n.t("cmdFrunk"),
                    parkOnly: true,
                    active: telemetry.frunkOpen == true
                ) {
                    await tesla.toggleFrunk()
                }
                cmd(
                    "car.rear",
                    telemetry.trunkOpen == true
                        ? EtubuClusterL10n.t("cmdTrunkClose")
                        : EtubuClusterL10n.t("cmdTrunk"),
                    parkOnly: true,
                    active: telemetry.trunkOpen == true
                ) {
                    await tesla.toggleTrunk()
                }
                cmd(
                    "window.vertical.open",
                    EtubuClusterL10n.t("cmdVentWindows"),
                    parkOnly: true,
                    active: false
                ) {
                    await tesla.ventWindows()
                }
                cmd(
                    "window.vertical.closed",
                    EtubuClusterL10n.t("cmdCloseWindows"),
                    parkOnly: true,
                    active: false
                ) {
                    await tesla.closeWindows()
                }
                cmd(
                    "bolt.car",
                    telemetry.chargePortOpen == true
                        ? EtubuClusterL10n.t("cmdChargePortClose")
                        : EtubuClusterL10n.t("cmdChargePort"),
                    parkOnly: true,
                    active: telemetry.chargePortOpen == true
                ) {
                    await tesla.toggleChargePort()
                }
                cmd(
                    "headlight.high.beam",
                    EtubuClusterL10n.t("cmdFlash"),
                    parkOnly: false,
                    active: false
                ) {
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
            .opacity(moving ? 0.45 : 1)
            .disabled(moving)

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

    private func cmd(
        _ symbol: String,
        _ title: String,
        parkOnly: Bool,
        active: Bool,
        a11yId: String? = nil,
        action: @escaping () async -> Void
    ) -> some View {
        let blocked = parkOnly && moving
        let tint: Color = {
            if blocked { return Color.red.opacity(0.95) }
            if active { return Color(red: 0.25, green: 0.82, blue: 0.45) }
            return Color.primary.opacity(0.85)
        }()
        let fill: Color = {
            if blocked { return Color.red.opacity(0.18) }
            if active { return Color.green.opacity(0.16) }
            return Color.primary.opacity(0.07)
        }()
        return Button {
            guard !blocked else {
                tesla.lastCommandMessage = EtubuClusterL10n.t("cmdParkToUse")
                return
            }
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
            .foregroundStyle(tint)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        blocked ? Color.red.opacity(0.55)
                            : (active ? Color.green.opacity(0.55) : Color.clear),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(blocked)
        .accessibilityHint(blocked ? EtubuClusterL10n.t("cmdParkToUse") : "")
        .accessibilityIdentifier(a11yId ?? "etubu.remote.cmd")
        .accessibilityLabel(title)
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
                guard !moving else { return }
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
