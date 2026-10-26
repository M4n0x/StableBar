import Foundation

/// The macOS setting **Automatically hide and show the menu bar**, which setup turns on for the top edge.
enum MenuBarAutoHide {
    /// Set while auto-hide is on because StableBar turned it on, so Uninstall knows to turn it off.
    static let turnedOnKey = "turnedOnMenuBarAutoHide"

    static func isOn(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: "_HIHideMenuBar")
    }

    static func turnedOnByStableBar(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: turnedOnKey)
    }

    static func setTurnedOnByStableBar(_ turnedOn: Bool, in defaults: UserDefaults = .standard) {
        if turnedOn { defaults.set(true, forKey: turnedOnKey) } else { defaults.removeObject(forKey: turnedOnKey) }
    }

    /// Forgets that StableBar turned auto-hide on once it's off, so auto-hide the user turns on later stays theirs.
    static func forgetIfShown(in defaults: UserDefaults = .standard) {
        if !isOn(in: defaults) { setTurnedOnByStableBar(false, in: defaults) }
    }

    /// Whether auto-hide is StableBar's doing once it's set to `hidden`, given how it was before.
    /// Auto-hide the user had on stays theirs, even after setup shows the menu bar and hides it again.
    static func turnedOnByStableBar(after hidden: Bool, wasOn: Bool, wasStableBars: Bool) -> Bool {
        hidden && (!wasOn || wasStableBars)
    }

    /// Changes the setting through System Events, which macOS asks the user to allow once.
    static func set(_ hidden: Bool) async throws {
        _ = try await runCommand("/usr/bin/osascript", arguments: [
            "-e", "tell application \"System Events\" to set autohide menu bar of dock preferences to \(hidden)"
        ], timeout: 120)
    }
}
