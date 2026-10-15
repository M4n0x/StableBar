import Foundation
import Observation
import Testing
@testable import StableBar

@Test func scriptOutputSupportsTextAndRichUpdates() throws {
    let plain = try ScriptOutput.read(Data("  1.42\n".utf8))
    #expect(plain.text == "1.42")
    let rich = try ScriptOutput.read(Data(##"{"text":"Building","icon":"hammer","color":"#f7821b80","tooltip":"App build"}"##.utf8))
    #expect(rich.text == "Building")
    #expect(rich.icon == "hammer")
    #expect(rich.color?.rgba == 0xf7821b80)
    #expect(rich.tooltip == "App build")
    let popup = try ScriptOutput.read(Data(#"{"text":"30%","value":0.3,"fields":{"usage":"30%"},"lists":{"processes":[{"name":"Window Server","cpu":"90.1%","memory":"108 MB"}]}}"#.utf8))
    #expect(popup.fields?["usage"] == "30%")
    #expect(popup.lists?["processes"]?.first?["name"] == "Window Server")
    #expect(popup.value == 0.3)
}

@Test func brokenRichOutputIsNotRenderedAsText() {
    #expect(throws: DecodingError.self) {
        try ScriptOutput.read(Data(#"{"text":"Building","color":"orange"}"#.utf8))
    }
    #expect(throws: DecodingError.self) {
        try ScriptOutput.read(Data(#"{"text":"30%","lists":{"processes":[{"cpu":30}]}}"#.utf8))
    }
}

@Test func popupStylesInheritWidgetOverridesAndGlobalTheme() {
    let defaults = WidgetStyle(foreground: HexColor(0xeeeeeeff), background: HexColor(0x222222ff),
                               fontName: "Helvetica", fontSize: 12, paddingHorizontal: 7, width: 80)
    let widget = WidgetStyle(background: HexColor(0x333333ff), fontWeight: "bold", width: 85)
    let popup = WidgetStyle(fontSize: 18, paddingHorizontal: 16, width: 380)
    let style = popup.inheriting(widget.inheriting(defaults))
    #expect(style.foreground == defaults.foreground)
    #expect(style.background == widget.background)
    #expect(style.fontName == "Helvetica")
    #expect(style.fontWeight == "bold")
    #expect(style.fontSize == 18)
    #expect(style.paddingHorizontal == 16)
    #expect(style.width == 380)
}

@Test @MainActor func popupObservesScriptFieldsAndHistory() async throws {
    let widget = try JSONDecoder().decode(WidgetConfiguration.self, from: Data(#"{"id":"cpu","type":"script","command":"echo","position":"right","popup":{"height":200,"style":{},"layout":{"type":"field","field":"usage"}}}"#.utf8))
    let store = BarStore()
    let script = ScriptWidget()
    store.scripts[widget.id] = script
    let view = PopupView(popup: widget.popup!, style: WidgetStyle(), store: store, widget: widget)
    await confirmation("Popup observes new fields") { changed in
        withObservationTracking { _ = view.body } onChange: { changed() }
        script.output = ScriptOutput(text: "30%", fields: ["usage": "30%"])
    }
    await confirmation("Popup observes new graph samples") { changed in
        withObservationTracking { _ = view.body } onChange: { changed() }
        script.samples.append(0.3)
    }
}

@Test func duplicateIdsCannotBreakWidgetIdentity() {
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(Configuration.self, from: Data(#"{"widgets":[{"id":"clock","type":"clock","position":"left"},{"id":"clock","type":"clock","position":"right"}]}"#.utf8))
    }
}

@Test func zeroIntervalCannotStartABusyLoop() {
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(Configuration.self, from: Data(#"{"widgets":[{"id":"test","type":"script","position":"left","command":"date","interval":0}]}"#.utf8))
    }
}

@Test func commandOutputLargerThanAPipeBufferCompletes() async throws {
    let data = try await runCommand("/usr/bin/head", arguments: ["-c", "131072", "/dev/zero"])
    #expect(data.count == 131072)
}

@Test func commandFailureIncludesStderr() async {
    do {
        _ = try await runCommand("/bin/zsh", arguments: ["-c", "printf 'widget failed' >&2; exit 3"])
        Issue.record("The failed command was accepted.")
    } catch {
        #expect(error.localizedDescription == "widget failed")
    }
}

@Test func cancellingAWidgetStopsItsRunningCommand() async throws {
    let start = ContinuousClock.now
    let task = Task { try await runCommand("/bin/sleep", arguments: ["5"]) }
    try await Task.sleep(for: .milliseconds(100))
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(start.duration(to: .now) < .seconds(2))
}

@Test func workspaceSnapshotKeepsMonitorFocusAndDeduplicatesAppWindows() throws {
    let spaces = Data(#"[{"workspace":"10","workspace-is-focused":false,"workspace-is-visible":false,"monitor-appkit-nsscreen-screens-id":2},{"workspace":"2","workspace-is-focused":false,"workspace-is-visible":true,"monitor-appkit-nsscreen-screens-id":2},{"workspace":"1","workspace-is-focused":true,"workspace-is-visible":true,"monitor-appkit-nsscreen-screens-id":1}]"#.utf8)
    let windows = Data(#"[{"workspace":"1","app-name":"Finder","app-bundle-id":"com.apple.finder"},{"workspace":"1","app-name":"Finder","app-bundle-id":"com.apple.finder"},{"workspace":"2","app-name":"Finder","app-bundle-id":"com.apple.finder"}]"#.utf8)
    let snapshot = try workspaceSnapshot(workspaces: spaces, windows: windows)
    #expect(snapshot.map(\.name) == ["1", "2", "10"])
    #expect(snapshot[0].isFocused)
    #expect(!snapshot[1].isFocused)
    #expect(snapshot[1].isVisible)
    #expect(snapshot[1].monitor == 2)
    #expect(snapshot[0].apps.count == 1)
    #expect(snapshot[1].apps.count == 1)
    #expect(snapshot[2].apps.isEmpty)
}

@Test func notchGroupsStayOutsideAnOffCenterNotch() {
    let layout = BarLayout(inset: 12, spacing: 8, notchSpacing: 16, notch: 720...940)
    let x = layout.origins(width: 1728, sizes: [180, 260, 0, 200, 340])
    #expect(x[0] == 12)
    #expect(x[1] + 260 == 704)
    #expect(x[3] == 956)
    #expect(x[4] + 340 == 1716)
}

@Test func externalDisplayCentersTheCombinedGroupWithoutPhantomGaps() {
    let layout = BarLayout(inset: 12, spacing: 8, notchSpacing: 16, notch: nil)
    let x = layout.origins(width: 1920, sizes: [180, 260, 0, 100, 340])
    #expect(x[1] == 776)
    #expect(x[3] == 1044)
    #expect(x[1] == 1920 - (x[3] + 100))
    let musicOnly = layout.origins(width: 1920, sizes: [180, 260, 0, 0, 340])
    #expect(musicOnly[1] == 830)
    let center = layout.origins(width: 1920, sizes: [180, 0, 100, 0, 340])
    #expect(center[2] == 910)
}

@Test func displayFilteringTracksFocusAndScreenSelectors() {
    let laptop = BarDisplay(id: 2, isBuiltIn: true, isMain: false, notch: 650...870)
    let monitor = BarDisplay(id: 1, isBuiltIn: false, isMain: true, notch: nil)
    #expect(DisplaySelection.active.includes(laptop, activeID: 2))
    #expect(!DisplaySelection.active.includes(laptop, activeID: 1))
    #expect(DisplaySelection.ids([1]).includes(monitor, activeID: 2))
    #expect(!DisplaySelection.ids([2]).includes(monitor, activeID: 2))
    #expect(DisplaySelection.notched.includes(laptop, activeID: 1))
    #expect(DisplaySelection.unnotched.includes(monitor, activeID: 1))
    #expect(DisplaySelection.external.includes(monitor, activeID: 2))
}

@Test @MainActor func scriptRecoversAfterACommandFailure() async throws {
    let marker = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let script = ScriptWidget()
    defer {
        script.stop()
        try? FileManager.default.removeItem(at: marker)
    }
    script.start(command: "if [ -f '\(marker.path)' ]; then echo Ready; else touch '\(marker.path)'; echo Offline >&2; exit 1; fi", interval: 0.02)
    for _ in 0..<100 {
        if script.output.text == "Ready" { break }
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(script.output.text == "Ready")
    #expect(script.error == nil)
}

@Test @MainActor func invalidRuntimeIntervalKeepsTheLastGoodOutput() async throws {
    let script = ScriptWidget()
    script.output = ScriptOutput(text: "Ready")
    defer { script.stop() }
    script.start(command: "echo '{\"text\":\"Broken\",\"interval\":0}'", interval: 30)
    for _ in 0..<100 {
        if script.error != nil { break }
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(script.output.text == "Ready")
    #expect(script.error == "A script interval must be greater than zero.")
}
