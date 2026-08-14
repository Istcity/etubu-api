import SwiftUI
import TeslaBLE

/// Ayarlardan seçilen 3 hızlı uzaktan komut (yalnız sembol).
enum EtubuRemoteQuickAction: String, CaseIterable, Identifiable {
    case climateOn
    case climateOff
    case lock
    case unlock
    case flash
    case chargeStart
    case chargeStop
    case frunk
    case trunk
    case chargePort
    case ventWindows
    case closeWindows

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .climateOn: return "snowflake"
        case .climateOff: return "snowflake.slash"
        case .lock: return "lock.fill"
        case .unlock: return "lock.open.fill"
        case .flash: return "headlight.high.beam"
        case .chargeStart: return "bolt.fill"
        case .chargeStop: return "bolt.slash.fill"
        case .frunk: return "shippingbox"
        case .trunk: return "car.rear"
        case .chargePort: return "bolt.car"
        case .ventWindows: return "window.vertical.open"
        case .closeWindows: return "window.vertical.closed"
        }
    }

    var titleKey: String {
        switch self {
        case .climateOn: return "cmdClimateOn"
        case .climateOff: return "cmdClimateOff"
        case .lock: return "cmdLock"
        case .unlock: return "cmdUnlock"
        case .flash: return "cmdFlash"
        case .chargeStart: return "cmdChargeStart"
        case .chargeStop: return "cmdChargeStop"
        case .frunk: return "cmdFrunk"
        case .trunk: return "cmdTrunk"
        case .chargePort: return "cmdChargePort"
        case .ventWindows: return "cmdVentWindows"
        case .closeWindows: return "cmdCloseWindows"
        }
    }

    var title: String { EtubuClusterL10n.t(titleKey) }

    /// Hareket halinde kilitlenen komutlar.
    var parkOnly: Bool {
        switch self {
        case .frunk, .trunk, .chargePort, .ventWindows, .closeWindows: return true
        default: return false
        }
    }

    func isActive(telemetry: EtubuVehicleTelemetry) -> Bool {
        switch self {
        case .climateOn: return telemetry.climateOn == true
        case .climateOff: return telemetry.climateOn == false
        case .lock: return telemetry.locked == true
        case .unlock: return telemetry.locked == false
        case .chargeStart: return telemetry.isCharging
        case .chargeStop: return !telemetry.isCharging
        case .frunk: return telemetry.frunkOpen == true
        case .trunk: return telemetry.trunkOpen == true
        case .chargePort: return telemetry.chargePortOpen == true
        default: return false
        }
    }

    @MainActor
    func run(tesla: EtubuTeslaBleSession) async {
        switch self {
        case .climateOn: await tesla.setClimate(on: true)
        case .climateOff: await tesla.setClimate(on: false)
        case .lock: await tesla.setLocked(true)
        case .unlock: await tesla.setLocked(false)
        case .flash: await tesla.flashLights()
        case .chargeStart: await tesla.setCharging(start: true)
        case .chargeStop: await tesla.setCharging(start: false)
        case .frunk: await tesla.toggleFrunk()
        case .trunk: await tesla.toggleTrunk()
        case .chargePort: await tesla.toggleChargePort()
        case .ventWindows: await tesla.ventWindows()
        case .closeWindows: await tesla.closeWindows()
        }
    }
}

enum EtubuRemotePinStore {
    static let enabledKey = "etubu.cluster.remotePinUnderWarn"
    static let slotKeys = [
        "etubu.cluster.remotePin.0",
        "etubu.cluster.remotePin.1",
        "etubu.cluster.remotePin.2",
    ]
    static let defaults: [EtubuRemoteQuickAction] = [.climateOn, .lock, .flash]

    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil { return false }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static func action(at index: Int) -> EtubuRemoteQuickAction {
        let fallback = defaults[min(index, defaults.count - 1)]
        guard index >= 0, index < slotKeys.count else { return fallback }
        guard let raw = UserDefaults.standard.string(forKey: slotKeys[index]),
              let action = EtubuRemoteQuickAction(rawValue: raw) else {
            return fallback
        }
        return action
    }

    static func setAction(_ action: EtubuRemoteQuickAction, at index: Int) {
        guard index >= 0, index < slotKeys.count else { return }
        UserDefaults.standard.set(action.rawValue, forKey: slotKeys[index])
    }

    static var slots: [EtubuRemoteQuickAction] {
        (0..<3).map { action(at: $0) }
    }
}

/// Yol uyarı çerçevesinin altında 3 sembol — genişlik uyarı kutusunu geçmez.
struct EtubuRemotePinnedBar: View {
    let width: CGFloat
    var theme: ClusterTheme
    @ObservedObject var tesla: EtubuTeslaBleSession
    @ObservedObject private var telemetry = EtubuVehicleTelemetry.shared

    private var moving: Bool { telemetry.isVehicleMoving }
    private var actions: [EtubuRemoteQuickAction] { EtubuRemotePinStore.slots }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(actions.enumerated()), id: \.offset) { idx, action in
                pinButton(action, index: idx)
            }
        }
        .frame(width: width)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("etubu.remote.pinnedBar")
    }

    private func pinButton(_ action: EtubuRemoteQuickAction, index: Int) -> some View {
        let blocked = action.parkOnly && moving
        let active = action.isActive(telemetry: telemetry)
        let tint: Color = {
            if blocked { return Color.red.opacity(0.95) }
            if active { return Color(red: 0.25, green: 0.82, blue: 0.45) }
            return theme.secondaryText
        }()
        let fill: Color = {
            if blocked { return Color.red.opacity(0.18) }
            if active { return Color.green.opacity(0.16) }
            return theme.surface.opacity(0.95)
        }()
        return Button {
            guard !blocked else {
                tesla.lastCommandMessage = EtubuClusterL10n.t("cmdParkToUse")
                return
            }
            Task { await action.run(tesla: tesla) }
        } label: {
            Image(systemName: action.symbol)
                .font(.system(size: max(11, min(15, width / 12)), weight: .semibold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .frame(height: max(28, min(36, width * 0.22)))
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(fill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            blocked ? Color.red.opacity(0.5)
                                : (active ? Color.green.opacity(0.5) : theme.stroke.opacity(0.5)),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(blocked)
        .accessibilityLabel(action.title)
        .accessibilityHint(blocked ? EtubuClusterL10n.t("cmdParkToUse") : "")
        .accessibilityIdentifier("etubu.remote.pin.\(index)")
    }
}

/// Ayarlar: uyarı altına sabitle + 3 slot seçimi.
struct EtubuRemotePinSettingsSection: View {
    @AppStorage(EtubuRemotePinStore.enabledKey) private var pinEnabled = false
    @AppStorage(EtubuRemotePinStore.slotKeys[0]) private var slot0 = EtubuRemoteQuickAction.climateOn.rawValue
    @AppStorage(EtubuRemotePinStore.slotKeys[1]) private var slot1 = EtubuRemoteQuickAction.lock.rawValue
    @AppStorage(EtubuRemotePinStore.slotKeys[2]) private var slot2 = EtubuRemoteQuickAction.flash.rawValue

    var body: some View {
        Toggle(isOn: $pinEnabled) {
            Text(EtubuClusterL10n.t("remotePinUnderWarn"))
        }
        .toggleStyle(.switch)
        .accessibilityIdentifier("etubu.settings.remotePin.toggle")
        .accessibilityValue(pinEnabled ? "1" : "0")
        if pinEnabled {
            slotPicker(EtubuClusterL10n.t("remotePinSlot1"), selection: $slot0)
                .accessibilityIdentifier("etubu.settings.remotePin.slot0")
            slotPicker(EtubuClusterL10n.t("remotePinSlot2"), selection: $slot1)
                .accessibilityIdentifier("etubu.settings.remotePin.slot1")
            slotPicker(EtubuClusterL10n.t("remotePinSlot3"), selection: $slot2)
                .accessibilityIdentifier("etubu.settings.remotePin.slot2")
            Text(EtubuClusterL10n.t("remotePinHint"))
                .font(EtubuClusterFonts.ui(12, weight: .medium))
                .foregroundStyle(ClusterTheme.stored.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func slotPicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(EtubuRemoteQuickAction.allCases) { action in
                Label(action.title, systemImage: action.symbol)
                    .tag(action.rawValue)
            }
        }
    }
}
