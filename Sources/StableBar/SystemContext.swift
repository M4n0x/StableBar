import AppKit
import IOKit.ps

@MainActor
final class SystemContext {
    private var powerSource: CFRunLoopSource?
    private var appearanceObserver: NSObjectProtocol?
    let changed: () -> Void

    init(changed: @escaping () -> Void) { self.changed = changed }

    static func current() -> ConfigurationContext {
        let power = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        return ConfigurationContext(
            appearance: NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark" : "light",
            onBattery: IOPSGetProvidingPowerSourceType(power).takeUnretainedValue() as String == kIOPSBatteryPowerValue,
            displayCount: NSScreen.screens.count,
            externalDisplay: NSScreen.screens.contains { !BarDisplay(screen: $0).isBuiltIn },
            app: NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "")
    }

    func start() {
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.changed() }
            }
        powerSource = IOPSNotificationCreateRunLoopSource({ context in
            MainActor.assumeIsolated {
                Unmanaged<SystemContext>.fromOpaque(context!).takeUnretainedValue().changed()
            }
        }, Unmanaged.passUnretained(self).toOpaque()).takeRetainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .commonModes)
    }

    func stop() {
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        if let appearanceObserver { DistributedNotificationCenter.default().removeObserver(appearanceObserver) }
        powerSource = nil
        appearanceObserver = nil
    }
}
