import Foundation
import IOKit.ps

/// Decides when transcription should wait so it never competes with what the user is doing.
/// Recording is never paused: only transcription, which catches up later from where it stopped.
public enum ResourceGovernor {
    public struct Reading: Sendable {
        public var thermal: ProcessInfo.ThermalState
        public var lowPowerMode: Bool
        /// 0…1, nil on Macs without a battery.
        public var batteryLevel: Double?
        public var isCharging: Bool
        /// One-minute load average.
        public var loadAverage: Double
        public var cores: Int
    }

    static let lowBattery = 0.2
    private static let overrideLock = NSLock()
    nonisolated(unsafe) private static var override = false

    /// Set when the user chooses "Continue Anyway": battery, Low Power Mode and load no longer
    /// pause transcription until the app quits. Heat still does, to protect the Mac.
    public static var continuesAnyway: Bool {
        get { overrideLock.withLock { override } }
        set { overrideLock.withLock { override = newValue } }
    }
    /// Other work keeping more than this share of the cores busy counts as "the Mac is busy".
    static let busyLoadPerCore = 1.2

    /// A short user-facing reason to wait, or nil to go ahead.
    public static func pauseReason(for reading: Reading, continuingAnyway: Bool = ResourceGovernor.continuesAnyway) -> String? {
        if reading.thermal == .serious || reading.thermal == .critical { return "Your Mac is running hot" }
        if continuingAnyway { return nil }
        if reading.lowPowerMode { return "Low Power Mode is on" }
        if let level = reading.batteryLevel, level < lowBattery, !reading.isCharging { return "Battery is low" }
        if reading.loadAverage > Double(reading.cores) * busyLoadPerCore { return "Your Mac is busy" }
        return nil
    }

    public static func currentPauseReason() -> String? {
        pauseReason(for: currentReading())
    }

    public static func currentReading() -> Reading {
        var load = [Double](repeating: 0, count: 3)
        let gotLoad = getloadavg(&load, 3) > 0
        let battery = batteryStatus()
        return Reading(
            thermal: ProcessInfo.processInfo.thermalState,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            batteryLevel: battery?.level,
            isCharging: battery?.charging ?? true,
            loadAverage: gotLoad ? load[0] : 0,
            cores: ProcessInfo.processInfo.activeProcessorCount
        )
    }

    private static func batteryStatus() -> (level: Double, charging: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let onAC = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            return (Double(current) / Double(maximum), onAC)
        }
        return nil
    }
}
