import Foundation
import Testing
@testable import TranskribeCore

@Suite struct ResourceGovernorTests {
    private func reading(thermal: ProcessInfo.ThermalState = .nominal, lowPower: Bool = false,
                         battery: Double? = nil, charging: Bool = false, load: Double = 1, cores: Int = 10) -> ResourceGovernor.Reading {
        .init(thermal: thermal, lowPowerMode: lowPower, batteryLevel: battery, isCharging: charging, loadAverage: load, cores: cores)
    }

    @Test func idleMacRunsNow() {
        #expect(ResourceGovernor.pauseReason(for: reading()) == nil)
        #expect(ResourceGovernor.pauseReason(for: reading(battery: 0.8)) == nil)
    }

    @Test func hotMacWaits() {
        #expect(ResourceGovernor.pauseReason(for: reading(thermal: .serious)) != nil)
        #expect(ResourceGovernor.pauseReason(for: reading(thermal: .fair)) == nil)
    }

    @Test func lowPowerModeAndLowBatteryWait() {
        #expect(ResourceGovernor.pauseReason(for: reading(lowPower: true)) != nil)
        #expect(ResourceGovernor.pauseReason(for: reading(battery: 0.15)) != nil)
        #expect(ResourceGovernor.pauseReason(for: reading(battery: 0.15, charging: true)) == nil)
    }

    @Test func busyCPUWaits() {
        #expect(ResourceGovernor.pauseReason(for: reading(load: 14, cores: 10)) != nil)
        #expect(ResourceGovernor.pauseReason(for: reading(load: 6, cores: 10)) == nil)
    }
}

@Suite struct ResourceGovernorOverrideTests {
    @Test func continuingAnywayIgnoresPowerAndLoadButNotHeat() {
        let lowPower = ResourceGovernor.Reading(thermal: .nominal, lowPowerMode: true, batteryLevel: 0.1, isCharging: false, loadAverage: 50, cores: 10)
        #expect(ResourceGovernor.pauseReason(for: lowPower, continuingAnyway: false) != nil)
        #expect(ResourceGovernor.pauseReason(for: lowPower, continuingAnyway: true) == nil)
        let hot = ResourceGovernor.Reading(thermal: .critical, lowPowerMode: false, batteryLevel: nil, isCharging: true, loadAverage: 1, cores: 10)
        #expect(ResourceGovernor.pauseReason(for: hot, continuingAnyway: true) != nil)
    }
}
