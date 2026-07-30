import Foundation
import ActivityKit

/// App + Widget Extension paylaşır (aynı dosya her iki target’ta).
@available(iOS 16.2, *)
public struct EtubuDriveAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var kmh: Int
        public var gear: String
        public var rpm: Int
        public var voice: String
        public var source: String // gps | obd | tesla
        public var tpmsFL: Int?
        public var tpmsFR: Int?
        public var tpmsRL: Int?
        public var tpmsRR: Int?
        /// Route / YolSafe summary for Island + lock screen
        public var routeActive: Bool
        public var routeFrom: String
        public var routeTo: String
        public var radarCount: Int
        public var corridorCount: Int
        public var chargeCount: Int
        public var controlCount: Int
        public var weatherCount: Int
        public var primaryWarn: String

        public init(
            kmh: Int,
            gear: String,
            rpm: Int,
            voice: String,
            source: String,
            tpmsFL: Int? = nil,
            tpmsFR: Int? = nil,
            tpmsRL: Int? = nil,
            tpmsRR: Int? = nil,
            routeActive: Bool = false,
            routeFrom: String = "",
            routeTo: String = "",
            radarCount: Int = 0,
            corridorCount: Int = 0,
            chargeCount: Int = 0,
            controlCount: Int = 0,
            weatherCount: Int = 0,
            primaryWarn: String = ""
        ) {
            self.kmh = kmh
            self.gear = gear
            self.rpm = rpm
            self.voice = voice
            self.source = source
            self.tpmsFL = tpmsFL
            self.tpmsFR = tpmsFR
            self.tpmsRL = tpmsRL
            self.tpmsRR = tpmsRR
            self.routeActive = routeActive
            self.routeFrom = routeFrom
            self.routeTo = routeTo
            self.radarCount = radarCount
            self.corridorCount = corridorCount
            self.chargeCount = chargeCount
            self.controlCount = controlCount
            self.weatherCount = weatherCount
            self.primaryWarn = primaryWarn
        }

        public var routeSummaryLine: String {
            let to = routeTo.trimmingCharacters(in: .whitespacesAndNewlines)
            guard routeActive, !to.isEmpty else { return "" }
            let from = routeFrom.trimmingCharacters(in: .whitespacesAndNewlines)
            if from.isEmpty || from.lowercased() == "konumum" {
                return "→ \(to)"
            }
            return "\(from) → \(to)"
        }

        public var hasRouteBrief: Bool {
            routeActive && (radarCount + corridorCount + chargeCount + controlCount + weatherCount) > 0
        }
    }

    public var startedAt: Date

    public init(startedAt: Date = Date()) {
        self.startedAt = startedAt
    }
}
