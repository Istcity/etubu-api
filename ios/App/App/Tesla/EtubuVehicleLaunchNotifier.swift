import Foundation
import UIKit
import UserNotifications

/// Araç BLE bağlanınca (arka planda) yerel bildirim — dokununca Etubu açılır.
/// Ayrılınca günde bir kez sürüş özeti (SoC, sıcaklık, TPMS, hava).
@MainActor
final class EtubuVehicleLaunchNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = EtubuVehicleLaunchNotifier()

    static let enabledKey = "etubu.vehicle.launchNotify"
    static let categoryId = "etubu.vehicle.connected"
    static let openActionId = "etubu.vehicle.open"
    private static let notifId = "etubu.vehicle.connected.once"
    private static let leaveNotifId = "etubu.vehicle.leave.once"
    private static let leaveDayKey = "etubu.vehicle.leave.day"

    private var lastPostedAt: Date?
    private var lastLeavePostedAt: Date?
    private let minInterval: TimeInterval = 120
    private var leaveWork: DispatchWorkItem?
    private var didNotifyThisSession = false

    private override init() {
        super.init()
    }

    /// Varsayılan açık; izin yalnızca yasal onay / ayarlar sonrası istenir.
    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    private func registerCategoriesIfNeeded() {
        let open = UNNotificationAction(
            identifier: Self.openActionId,
            title: EtubuClusterL10n.t("vehicleNotifyOpen"),
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryId,
            actions: [open],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func requestAuthorizationIfNeeded() {
        guard Self.isEnabled else { return }
        configure()
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    if granted {
                        DispatchQueue.main.async { self.registerCategoriesIfNeeded() }
                    }
                }
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async { self.registerCategoriesIfNeeded() }
            default:
                break
            }
        }
    }

    /// Tesla / OBD bağlandığında — oturumda 1 kez; ön plandaysa banner yok.
    func notifyVehicleConnected(source: String) {
        leaveWork?.cancel()
        leaveWork = nil
        guard Self.isEnabled else { return }
        guard !EtubuDemoDrive.isActive else { return }
        guard !didNotifyThisSession else { return }

        let state = UIApplication.shared.applicationState
        guard state != .active else { return }

        if let last = lastPostedAt, Date().timeIntervalSince(last) < minInterval { return }

        configure()
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            guard let self else { return }
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                Task { @MainActor in
                    self.registerCategoriesIfNeeded()
                    self.postConnectedNotification(source: source)
                }
            default:
                break
            }
        }
    }

    private func postConnectedNotification(source: String) {
        if let last = lastPostedAt, Date().timeIntervalSince(last) < minInterval { return }
        lastPostedAt = Date()
        didNotifyThisSession = true

        let content = UNMutableNotificationContent()
        content.title = EtubuClusterL10n.t("vehicleNotifyTitle")
        content.body = EtubuClusterL10n.t("vehicleNotifyBody")
        content.sound = .default
        content.categoryIdentifier = Self.categoryId
        content.userInfo = [
            "etubu": "vehicle",
            "source": source,
            "url": "com.etubu.app://cluster",
        ]
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.4, repeats: false)
        let req = UNNotificationRequest(identifier: Self.notifId, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    /// Park / kopma — 35 sn debounce; yeniden bağlanırsa iptal; takvim gününde 1 kez.
    func scheduleLeaveCarSummary() {
        guard !EtubuDemoDrive.isActive else { return }
        if alreadyPostedLeaveToday() { return }
        leaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                await self?.postLeaveCarSummary()
            }
        }
        leaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 35, execute: work)
    }

    private func alreadyPostedLeaveToday() -> Bool {
        let day = Self.dayStamp(Date())
        if UserDefaults.standard.string(forKey: Self.leaveDayKey) == day { return true }
        if let last = lastLeavePostedAt, Calendar.current.isDateInToday(last) { return true }
        return false
    }

    private func postLeaveCarSummary() async {
        leaveWork = nil
        guard !alreadyPostedLeaveToday() else { return }
        let t = EtubuVehicleTelemetry.shared
        if t.connectionState == .connected, (t.userPresent ?? false) { return }

        configure()
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        default:
            return
        }

        let soc = t.displaySocPercent ?? t.socPercent
        let socTxt = soc.map { "\($0)" } ?? "—"
        let inn = t.insideC.map { String(format: "%.0f", $0) } ?? "—"
        let out = t.outsideC.map { String(format: "%.0f", $0) } ?? "—"
        let tires = Self.tpmsLine(t)
        var wx = EtubuWeatherMonitor.shared.dayBriefLine
        if wx.isEmpty {
            let pin = EtubuRoadFix.shared.predictedCoordinate
            wx = await EtubuWeatherMonitor.fetchDayBrief(
                lat: pin?.lat ?? t.latitude,
                lng: pin?.lng ?? t.longitude
            )
        }
        if wx.isEmpty { wx = "—" }

        let content = UNMutableNotificationContent()
        content.title = EtubuClusterL10n.t("leaveCarNotifyTitle")
        content.body = String(
            format: EtubuClusterL10n.t("leaveCarNotifyBodyFmt"),
            socTxt, inn, out, tires, wx
        )
        content.sound = .default
        content.categoryIdentifier = Self.categoryId
        content.userInfo = ["etubu": "leave", "url": "com.etubu.app://cluster"]
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .passive
        }

        lastLeavePostedAt = Date()
        UserDefaults.standard.set(Self.dayStamp(Date()), forKey: Self.leaveDayKey)
        didNotifyThisSession = false

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let req = UNNotificationRequest(identifier: Self.leaveNotifId, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    private static func tpmsLine(_ t: EtubuVehicleTelemetry) -> String {
        let bars = [t.tpmsFL.bar, t.tpmsFR.bar, t.tpmsRL.bar, t.tpmsRR.bar]
        if bars.allSatisfy({ $0 != nil }) {
            return bars.map { String(format: "%.1f", $0 ?? 0) }.joined(separator: "/")
        }
        let psi = [t.tpmsFL.psi, t.tpmsFR.psi, t.tpmsRL.psi, t.tpmsRR.psi]
        if psi.contains(where: { $0 != nil }) {
            return psi.map { $0.map { "\(Int($0.rounded()))" } ?? "—" }.joined(separator: "/")
        }
        return "—"
    }

    private static func dayStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            EtubuClusterPresenter.shared.installOverCapacitor()
            completionHandler()
        }
    }
}
