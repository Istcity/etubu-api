import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// App Group snapshot — ana uygulama yazar, widget okur.
enum EtubuSharedDriveSnapshot {
    static let suiteName = "group.com.etubu.app"
    private static let kmhKey = "kmh"
    private static let socKey = "soc"
    private static let gearKey = "gear"
    private static let rangeKey = "rangeKm"
    private static let updatedKey = "updatedAt"
    private static let warnKey = "primaryWarn"

    private static var suite: UserDefaults? { UserDefaults(suiteName: suiteName) }

    private static var lastWriteAt: Date = .distantPast

    static func publish(
        kmh: Int,
        soc: Int?,
        gear: String,
        rangeKm: Int?,
        primaryWarn: String?,
        clearWarnIfNil: Bool = false
    ) {
        guard let suite else { return }
        let now = Date()
        // Widget thrash'ini önle — en fazla ~1.5s.
        guard now.timeIntervalSince(lastWriteAt) >= 1.5 else { return }
        lastWriteAt = now
        suite.set(kmh, forKey: kmhKey)
        if let soc { suite.set(soc, forKey: socKey) }
        suite.set(gear, forKey: gearKey)
        if let rangeKm { suite.set(rangeKm, forKey: rangeKey) }
        suite.set(now.timeIntervalSince1970, forKey: updatedKey)
        if let primaryWarn {
            suite.set(primaryWarn, forKey: warnKey)
        } else if clearWarnIfNil {
            suite.set("", forKey: warnKey)
        }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: "EtubuStatusWidget")
        #endif
    }

    struct Values {
        var kmh: Int
        var soc: Int?
        var gear: String
        var rangeKm: Int?
        var updatedAt: Date?
        var primaryWarn: String
        var isStale: Bool {
            guard let updatedAt else { return true }
            return Date().timeIntervalSince(updatedAt) > 180
        }
    }

    static func read() -> Values {
        guard let suite else {
            return Values(kmh: 0, soc: nil, gear: "P", rangeKm: nil, updatedAt: nil, primaryWarn: "")
        }
        let ts = suite.double(forKey: updatedKey)
        return Values(
            kmh: suite.integer(forKey: kmhKey),
            soc: suite.object(forKey: socKey) as? Int,
            gear: suite.string(forKey: gearKey) ?? "P",
            rangeKm: suite.object(forKey: rangeKey) as? Int,
            updatedAt: ts > 0 ? Date(timeIntervalSince1970: ts) : nil,
            primaryWarn: suite.string(forKey: warnKey) ?? ""
        )
    }
}
