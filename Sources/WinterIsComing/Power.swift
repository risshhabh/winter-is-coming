import Foundation
import IOKit.ps

/// The machine's power situation, read on demand (each call is cheap; callers poll every few seconds)
enum Power {
    static var onBattery: Bool {
        guard let source = IOPSGetProvidingPowerSourceType(nil)?.takeUnretainedValue() else { return false }
        return (source as String) == kIOPSBatteryPowerValue
    }
    static var lowPower: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }
    static var thermalPressure: Bool {
        let s = ProcessInfo.processInfo.thermalState
        return s == .serious || s == .critical
    }
}
