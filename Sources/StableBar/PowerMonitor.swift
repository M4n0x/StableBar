import Foundation
import IOKit.ps

/// The internal battery's charge and state from IOKit. Its run loop source fires when the power
/// source, the charge or the time remaining changes.
final class PowerMonitor: ChangeMonitor, @unchecked Sendable {
    // `start` and `stop` run on the main actor, and the run loop source calls back on the main run
    // loop, so `source` and `changed` are only touched on the main thread.
    private var source: CFRunLoopSource?
    private var changed: (@Sendable () -> Void)?

    deinit { stop() }

    func read() throws -> ScriptOutput {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            throw CommandFailure(message: "Could not read power sources.")
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Double,
                  let maximum = description[kIOPSMaxCapacityKey] as? Double, maximum > 0 else { continue }
            let percent = current / maximum
            let charging = description[kIOPSIsChargingKey] as? Bool == true
            let onAC = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let minutes = description[charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey] as? Int
            let state = charging ? "charging" : (onAC ? "charged" : "battery")
            var fields = ["state": state, "present": "true", "percent": String(Int(percent * 100))]
            if let minutes, minutes >= 0 { fields["timeRemaining"] = String(minutes) }
            return ScriptOutput(text: "\(Int(percent * 100))%", icon: charging ? "battery.100percent.bolt" : "battery.100percent",
                                value: percent, fields: fields, values: ["percent": percent])
        }
        return ScriptOutput(text: "AC", icon: "powerplug", fields: ["state": "ac", "present": "false"])
    }

    func start(changed: @escaping @Sendable () -> Void) throws {
        stop()
        self.changed = changed
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue().changed?()
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue() else {
            self.changed = nil
            throw CommandFailure(message: "Could not watch power sources.")
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.source = source
    }

    /// Removes and invalidates the run loop source. Stopping a monitor that isn't listening does
    /// nothing, and `start` listens again with a new source.
    func stop() {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        source = nil
        changed = nil
    }
}
