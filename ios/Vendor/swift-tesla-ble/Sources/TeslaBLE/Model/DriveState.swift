import Foundation

/// Gear, speed, power, odometer, and active-route status reported by the vehicle.
public struct DriveState: Sendable, Equatable {
    /// Current transmission position (P/R/N/D). Nil if the vehicle did not report this field.
    public var shiftState: ShiftState?
    /// Current ground speed in miles per hour. Nil if the vehicle did not report this field.
    public var speedMph: Double?
    /// Instantaneous drivetrain power in kilowatts (negative while regenerating). Nil if the vehicle did not report this field.
    public var powerKW: Int?
    /// Odometer reading in hundredths of a mile (divide by 100 to get miles). Nil if the vehicle did not report this field.
    public var odometerHundredthsMile: Int?
    /// Active navigation destination name, if any. Nil if the vehicle did not report this field.
    public var activeRouteDestination: String?
    /// Estimated minutes remaining on the active route. Nil if the vehicle did not report this field.
    public var activeRouteMinutesToArrival: Double?
    /// Remaining distance on the active route in miles. Nil if the vehicle did not report this field.
    public var activeRouteMilesToArrival: Double?
    /// Vehicle-estimated state of charge at arrival (percent). Nil if unset.
    public var activeRouteEnergyAtArrival: Double?
    /// Active route destination latitude. Nil if unset.
    public var activeRouteLatitude: Double?
    /// Active route destination longitude. Nil if unset.
    public var activeRouteLongitude: Double?

    /// Transmission gear position.
    public enum ShiftState: Sendable, Equatable {
        /// Park.
        case park
        /// Reverse.
        case reverse
        /// Neutral.
        case neutral
        /// Drive.
        case drive
    }

    public init(
        shiftState: ShiftState? = nil,
        speedMph: Double? = nil,
        powerKW: Int? = nil,
        odometerHundredthsMile: Int? = nil,
        activeRouteDestination: String? = nil,
        activeRouteMinutesToArrival: Double? = nil,
        activeRouteMilesToArrival: Double? = nil,
        activeRouteEnergyAtArrival: Double? = nil,
        activeRouteLatitude: Double? = nil,
        activeRouteLongitude: Double? = nil,
    ) {
        self.shiftState = shiftState
        self.speedMph = speedMph
        self.powerKW = powerKW
        self.odometerHundredthsMile = odometerHundredthsMile
        self.activeRouteDestination = activeRouteDestination
        self.activeRouteMinutesToArrival = activeRouteMinutesToArrival
        self.activeRouteMilesToArrival = activeRouteMilesToArrival
        self.activeRouteEnergyAtArrival = activeRouteEnergyAtArrival
        self.activeRouteLatitude = activeRouteLatitude
        self.activeRouteLongitude = activeRouteLongitude
    }
}
