import Foundation
import UIKit
import UserNotifications

/// Araç BLE bağlanınca (arka planda) yerel bildirim — dokununca Etubu açılır.
/// iOS uygulamayı sessizce otomatik açmaz; bildirim + Kısayollar otomasyonu bunun için.
@MainActor
final class EtubuVehicleLaunchNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = EtubuVehicleLaunchNotifier()

    static let enabledKey = "etubu.vehicle.launchNotify"
    static let categoryId = "etubu.vehicle.connected"
    static let openActionId = "etubu.vehicle.open"
    private static let notifId = "etubu.vehicle.connected.once"

    private var lastPostedAt: Date?
    private let minInterval: TimeInterval = 120

    private override init() {
        super.init()
    }

    /// Varsayılan: kapalı — Ayarlar’dan açılınca bildirim izni istenir (açılışta diyalog yok).
    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil { return false }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    func configure() {
        UNUserNotificationCenter.current().delegate = self
        // Kategorileri yalnızca izin sonrası kaydet — iOS 26’da setNotificationCategories
        // ilk açılışta bildirim izni diyaloğunu tetikleyebiliyor.
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

    /// Tesla / OBD bağlandığında çağır — yalnızca arka planda / inactive iken bildir.
    func notifyVehicleConnected(source: String) {
        guard Self.isEnabled else { return }
        guard !EtubuDemoDrive.isActive else { return }

        let state = UIApplication.shared.applicationState
        guard state != .active else { return }

        if let last = lastPostedAt, Date().timeIntervalSince(last) < minInterval { return }

        configure()
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            guard let self else { return }
            switch settings.authorizationStatus {
            case .notDetermined:
                // İzin daha önce istenmediyse (Ayarlar açılmadan) burada iste — ana ekranı engellemez.
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    guard granted else { return }
                    Task { @MainActor in
                        self.registerCategoriesIfNeeded()
                        self.postConnectedNotification(source: source)
                    }
                }
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

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Ön plandayken banner gösterme — zaten cluster açık.
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
