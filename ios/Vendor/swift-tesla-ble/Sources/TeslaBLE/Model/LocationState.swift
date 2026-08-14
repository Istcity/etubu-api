import Foundation

/// Vehicle GPS position and heading from Infotainment `LocationState`.
public struct LocationState: Sendable, Equatable {
    public var latitude: Double?
    public var longitude: Double?
    public var headingDeg: Double?

    public init(
        latitude: Double? = nil,
        longitude: Double? = nil,
        headingDeg: Double? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.headingDeg = headingDeg
    }
}
