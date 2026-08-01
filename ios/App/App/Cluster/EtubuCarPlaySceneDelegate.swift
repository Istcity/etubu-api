import CarPlay
import Combine
import UIKit

/// CarPlay EV-charging foundation: live speed / SoC / range + nearby Superchargers.
///
/// Apple must grant `com.apple.developer.carplay-charging` on the App ID before the
/// app appears on CarPlay. Request via https://developer.apple.com/contact/carplay/
/// then add the boolean entitlement to `App.entitlements`.
final class EtubuCarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?
    private var lastFingerprint = ""

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        lastFingerprint = ""
        interfaceController.setRootTemplate(makeTabBar(), animated: false) { _, _ in }
        startLiveUpdates()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController
    ) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        cancellables.removeAll()
        lastFingerprint = ""
        self.interfaceController = nil
    }

    private func startLiveUpdates() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pushStatusIfNeeded()
        }
        if let timer = refreshTimer {
            RunLoop.main.add(timer, forMode: .common)
        }

        NotificationCenter.default.publisher(for: .etubuCarPlayNeedsRefresh)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.lastFingerprint = ""
                self?.pushStatusIfNeeded()
            }
            .store(in: &cancellables)
    }

    private func pushStatusIfNeeded() {
        guard let interfaceController else { return }
        let fp = statusFingerprint()
        guard fp != lastFingerprint else { return }
        lastFingerprint = fp
        interfaceController.setRootTemplate(makeTabBar(), animated: false) { _, _ in }
    }

    private func statusFingerprint() -> String {
        let t = EtubuVehicleTelemetry.shared
        let soc = t.displaySocPercent.map(String.init) ?? "-"
        let range = t.displayRangeKm.map(String.init) ?? "-"
        let power = t.powerKw.map(String.init) ?? "-"
        let n = EtubuTeslaBleSession.shared.nearbyChargers.count
        return "\(t.kmh)|\(soc)|\(range)|\(t.gear)|\(power)|\(n)"
    }

    private func makeTabBar() -> CPTabBarTemplate {
        let status = makeStatusTemplate()
        status.tabImage = UIImage(systemName: "gauge.with.dots.needle.67percent")
        let nearby = makeNearbyTemplate()
        nearby.tabImage = UIImage(systemName: "bolt.car")
        return CPTabBarTemplate(templates: [status, nearby])
    }

    private func makeStatusTemplate() -> CPInformationTemplate {
        let t = EtubuVehicleTelemetry.shared
        let speed = "\(max(0, t.kmh)) km/h"
        let soc: String = {
            if let p = t.displaySocPercent { return "\(p)%" }
            return "—"
        }()
        let range: String = {
            if let km = t.displayRangeKm { return "\(km) km" }
            return "—"
        }()
        let gear = t.gear.isEmpty ? "—" : t.gear
        let power: String = {
            if let kw = t.powerKw { return "\(kw) kW" }
            return "—"
        }()

        let items = [
            CPInformationItem(title: EtubuClusterL10n.t("carplaySpeed"), detail: speed),
            CPInformationItem(title: EtubuClusterL10n.t("carplaySoc"), detail: soc),
            CPInformationItem(title: EtubuClusterL10n.t("carplayRange"), detail: range),
            CPInformationItem(title: EtubuClusterL10n.t("carplayGear"), detail: gear),
            CPInformationItem(title: EtubuClusterL10n.t("carplayPower"), detail: power),
        ]

        let open = CPTextButton(title: EtubuClusterL10n.t("carplayOpenApp"), textStyle: .confirm) { _ in
            NotificationCenter.default.post(name: .etubuCarPlayOpenPhone, object: nil)
        }

        return CPInformationTemplate(
            title: EtubuClusterL10n.t("carplayStatus"),
            layout: .leading,
            items: items,
            actions: [open]
        )
    }

    private func makeNearbyTemplate() -> CPListTemplate {
        let sites = EtubuTeslaBleSession.shared.nearbyChargers
        let items: [CPListItem]
        if sites.isEmpty {
            let empty = CPListItem(
                text: EtubuClusterL10n.t("carplayNoChargers"),
                detailText: nil
            )
            empty.handler = { _, completion in
                Task { @MainActor in
                    await EtubuTeslaBleSession.shared.refreshNearbyChargers()
                    NotificationCenter.default.post(name: .etubuCarPlayNeedsRefresh, object: nil)
                    completion()
                }
            }
            items = [empty]
        } else {
            items = sites.prefix(8).map { site in
                let item = CPListItem(text: site.name, detailText: site.subtitle)
                item.handler = { _, completion in
                    completion()
                }
                return item
            }
        }
        let section = CPListSection(items: items)
        return CPListTemplate(title: EtubuClusterL10n.t("carplayNearby"), sections: [section])
    }
}

extension Notification.Name {
    static let etubuCarPlayNeedsRefresh = Notification.Name("etubu.carplay.needsRefresh")
    static let etubuCarPlayOpenPhone = Notification.Name("etubu.carplay.openPhone")
}
