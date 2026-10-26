import Foundation
import Testing
@testable import StableBar

private struct Refusal: Error {}

@MainActor
private func preferences(menuBarHides: Bool, turnedOnByStableBar: Bool) throws -> (UserDefaults, String) {
    let suite = "StableBarTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.set(menuBarHides, forKey: "_HIHideMenuBar")
    MenuBarAutoHide.setTurnedOnByStableBar(turnedOnByStableBar, in: defaults)
    return (defaults, suite)
}

@MainActor
@Test func menuBarAutoHideTurnedOnInSettingsIsStableBars() async throws {
    let (defaults, suite) = try preferences(menuBarHides: false, turnedOnByStableBar: false)
    defer { defaults.removePersistentDomain(forName: suite) }
    var requested: [Bool] = []
    try await MenuBarAutoHide.change(to: true, in: defaults) { requested.append($0) }
    #expect(requested == [true])
    #expect(MenuBarAutoHide.turnedOnByStableBar(in: defaults))
}

@MainActor
@Test func menuBarAutoHideTurnedOffInSettingsIsForgotten() async throws {
    let (defaults, suite) = try preferences(menuBarHides: true, turnedOnByStableBar: true)
    defer { defaults.removePersistentDomain(forName: suite) }
    try await MenuBarAutoHide.change(to: false, in: defaults) { _ in }
    #expect(!MenuBarAutoHide.turnedOnByStableBar(in: defaults))
}

@MainActor
@Test func menuBarAutoHideKeepsItsRecordWhenTheChangeFails() async throws {
    let (defaults, suite) = try preferences(menuBarHides: false, turnedOnByStableBar: false)
    defer { defaults.removePersistentDomain(forName: suite) }
    await #expect(throws: Refusal.self) { try await MenuBarAutoHide.change(to: true, in: defaults) { _ in throw Refusal() } }
    #expect(!MenuBarAutoHide.turnedOnByStableBar(in: defaults))
}

@Test func settingsSearchFindsMenuBarAutoHide() {
    #expect(SettingsSearchResult.allCases.filter { $0.matches("auto-hide menu bar") }.contains(.menuBar))
    #expect(SettingsSearchResult.menuBar.matches("automatically hide"))
}
