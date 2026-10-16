import AppKit
import Foundation
import Observation
import Testing
import os
@testable import StableBar

private let threeWidgets = ##"""
{"bar":{"style":{"background":"#000000"}},"widgets":[
  {"id":"a","type":"script","command":"true","position":"left"},
  {"id":"b","type":"script","command":"true","position":"left"},
  {"id":"c","type":"text","text":"C","position":"right"}]}
"""##

@MainActor private func makeStore(_ json: String) throws -> BarStore {
    let store = BarStore(configurationURL: FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json"))
    store.configuration = try JSONDecoder().decode(Configuration.self, from: Data(json.utf8))
    for widget in store.configuration?.widgets ?? [] {
        if case .script = widget.content { store.scripts[widget.id] = ScriptWidget() }
    }
    store.preparePresentations()
    return store
}

private func output(_ json: String) throws -> ScriptOutput {
    try ScriptOutput.read(Data(json.utf8))
}

@Test @MainActor func outputUpdatesInvalidateOnlyTheWidgetsTheyRestyle() async throws {
    let store = try makeStore(threeWidgets)
    let a = try #require(store.scripts["a"])
    let first = try #require(store.presentations["a"])
    let second = try #require(store.presentations["b"])
    let third = try #require(store.presentations["c"])
    try await confirmation("a is restyled", expectedCount: 1) { restyled in
        try await confirmation("b, c and the bar stay valid", expectedCount: 0) { invalidated in
            withObservationTracking { _ = first.style } onChange: { restyled() }
            withObservationTracking { _ = second.style; _ = second.hidden; _ = second.display } onChange: { invalidated() }
            withObservationTracking { _ = third.style } onChange: { invalidated() }
            withObservationTracking { _ = store.barStyle; _ = store.presentations } onChange: { invalidated() }
            try a.accept(output(##"{"text":"1","style":{"foreground":"#ff0000"}}"##))
        }
    }
    #expect(first.style.style(hovered: false).foreground == HexColor(0xff0000ff))
    try await confirmation("Output that keeps a's style leaves it valid", expectedCount: 0) { invalidated in
        withObservationTracking { _ = first.style; _ = first.hidden; _ = first.display } onChange: { invalidated() }
        try a.accept(output(##"{"text":"2","style":{"foreground":"#ff0000"}}"##))
    }
    try await confirmation("widgetStyles restyle their target", expectedCount: 1) { restyled in
        try await confirmation("b stays valid", expectedCount: 0) { invalidated in
            withObservationTracking { _ = third.style } onChange: { restyled() }
            withObservationTracking { _ = second.style } onChange: { invalidated() }
            try a.accept(output(##"{"text":"3","style":{"foreground":"#ff0000"},"widgetStyles":{"c":{"background":"#00ff00"}}}"##))
        }
    }
    #expect(third.style.base.background == HexColor(0x00ff00ff))
    try await confirmation("barStyle restyles the bar", expectedCount: 1) { restyled in
        try await confirmation("widgets stay valid", expectedCount: 0) { invalidated in
            withObservationTracking { _ = store.barStyle } onChange: { restyled() }
            withObservationTracking { _ = second.style; _ = third.style } onChange: { invalidated() }
            try a.accept(output(##"{"text":"4","style":{"foreground":"#ff0000"},"widgetStyles":{"c":{"background":"#00ff00"}},"barStyle":{"background":"#0000ff"}}"##))
        }
    }
    #expect(store.barStyle.background == HexColor(0x0000ffff))
}

@Test @MainActor func hiddenAndDisplayOutputChangeOnlyTheirWidgetsPresence() async throws {
    let store = try makeStore(threeWidgets)
    let a = try #require(store.scripts["a"])
    let first = try #require(store.presentations["a"])
    let second = try #require(store.presentations["b"])
    try await confirmation("a's presence changes", expectedCount: 1) { changed in
        try await confirmation("b stays valid", expectedCount: 0) { invalidated in
            withObservationTracking { _ = first.hidden; _ = first.display } onChange: { changed() }
            withObservationTracking { _ = second.hidden; _ = second.display; _ = second.style } onChange: { invalidated() }
            try a.accept(output(#"{"text":"","hidden":true,"display":"main"}"#))
        }
    }
    #expect(first.hidden)
    #expect(first.display == .main)
    a.error = "Offline"
    store.updatePresentations()
    #expect(!first.hidden)
}

@Test @MainActor func successfulActionsLeaveActionErrorsUntouched() async throws {
    let store = try makeStore(threeWidgets)
    let text = try #require(store.configuration?.widgets.first { $0.id == "c" })
    await confirmation("No widget re-reads an action error", expectedCount: 0) { invalidated in
        withObservationTracking { _ = store.actionErrors["a"] } onChange: { invalidated() }
        await store.runAction("true", widget: text).value
    }
    #expect(store.actionErrors.isEmpty)
}

@Test @MainActor func reloadingResolvesScriptStylesInTheStore() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "config.json")
    try Data(##"""
    {"widgets":[{"id":"status","type":"script","position":"right","interval":null,
      "command":"printf '{\"text\":\"Ready\",\"style\":{\"foreground\":\"#ff0000\"},\"barStyle\":{\"background\":\"#00ff00\"}}'"}]}
    """##.utf8).write(to: url)
    let store = BarStore(configurationURL: url)
    defer { store.stop() }
    store.reloadConfiguration()
    for _ in 0..<100 {
        if store.barStyle.background == HexColor(0x00ff00ff) { break }
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(store.barStyle.background == HexColor(0x00ff00ff))
    #expect(store.presentations["status"]?.style.base.foreground == HexColor(0xff0000ff))
}

@Test @MainActor func aStoreThatOnlyShowsAnotherStoresScriptsLeavesThemReportingToIt() throws {
    let bar = try makeStore(threeWidgets)
    let a = try #require(bar.scripts["a"])
    try a.accept(output(##"{"text":"1","style":{"foreground":"#ff0000"}}"##))
    let preview = BarStore(configurationURL: FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json"))
    preview.configuration = bar.configuration
    preview.scripts = bar.scripts
    preview.preparePresentations()
    #expect(preview.presentations["a"]?.style.base.foreground == HexColor(0xff0000ff))
    try a.accept(output(##"{"text":"2","style":{"foreground":"#00ff00"}}"##))
    #expect(bar.presentations["a"]?.style.base.foreground == HexColor(0x00ff00ff))
}

@Test @MainActor func scriptUpdatesInvalidateOnlyTheViewsTheyAffect() throws {
    let store = try makeStore(threeWidgets)
    let configuration = try #require(store.configuration)
    let a = try #require(store.scripts["a"])
    let bar = BarView(store: store, display: BarDisplay(id: 1, isBuiltIn: true, isMain: true, notch: nil))
    let widgets = Dictionary(uniqueKeysWithValues: configuration.widgets.map {
        ($0.id, WidgetView(widget: $0, defaults: configuration.defaults, popupDefaults: configuration.popupDefaults, store: store,
                           monitor: 1, animationDuration: 0.2))
    })
    var updates = 0
    func invalidated(by extra: String) throws -> [String] {
        let views = OSAllocatedUnfairLock(initialState: [String]())
        withObservationTracking { _ = bar.body } onChange: { views.withLock { $0.append("bar") } }
        for (id, view) in widgets {
            withObservationTracking { _ = view.body } onChange: { views.withLock { $0.append(id) } }
        }
        updates += 1
        try a.accept(output(#"{"text":"\#(updates)"\#(extra)}"#))
        return views.withLock { $0 }.sorted()
    }
    let style = ##","style":{"foreground":"#ff0000"}"##
    let widgetStyles = ##","widgetStyles":{"c":{"background":"#00ff00"}}"##
    let barStyle = ##","barStyle":{"background":"#0000ff"}"##
    #expect(try invalidated(by: "") == ["a"])
    #expect(try invalidated(by: style) == ["a"])
    #expect(try invalidated(by: style + widgetStyles) == ["a", "c"])
    #expect(try invalidated(by: style + widgetStyles + barStyle) == ["a", "bar"])
    #expect(try invalidated(by: style + widgetStyles + barStyle + #","hidden":true"#) == ["a", "bar"])
    #expect(try invalidated(by: style + widgetStyles + barStyle + #","display":"main""#) == ["a", "bar"])
}

@Test @MainActor func aFailureBringsAHiddenWidgetBack() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "config.json")
    let failure = directory.appending(path: "failure")
    try JSONSerialization.data(withJSONObject: ["widgets": [[
        "id": "status", "type": "script", "position": "right", "interval": NSNull(),
        "command": #"if [ -f "$FAILURE" ]; then printf Offline >&2; exit 1; fi; printf '{"text":"","hidden":true}'"#,
        "environment": ["FAILURE": failure.path]
    ]]]).write(to: url, options: .atomic)
    let store = BarStore(configurationURL: url)
    defer { store.stop() }
    store.reloadConfiguration()
    let script = try #require(store.scripts["status"])
    let presentation = try #require(store.presentations["status"])
    for _ in 0..<100 {
        if presentation.hidden { break }
        try await Task.sleep(for: .milliseconds(20))
    }
    try #require(presentation.hidden)
    try Data().write(to: failure)
    script.refresh(ScriptEvent(sender: "check"))
    for _ in 0..<100 {
        if !presentation.hidden { break }
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(!presentation.hidden)
    #expect(script.error == "Offline")
}

@Test @MainActor func openingAPopupMarksOnlyTheInstanceThatAnchorsIt() async throws {
    let store = try makeStore(threeWidgets)
    let first = try #require(store.presentations["a"])
    let second = try #require(store.presentations["b"])
    let anchor = NSView()
    let elsewhere = NSView()
    await confirmation("a's popup opens", expectedCount: 1) { opened in
        await confirmation("b stays valid", expectedCount: 0) { invalidated in
            withObservationTracking { _ = first.popupAnchor } onChange: { opened() }
            withObservationTracking { _ = second.popupAnchor; _ = second.style } onChange: { invalidated() }
            store.setPopupVisibleWidget("a", anchor: anchor)
        }
    }
    #expect(first.popupAnchor == ObjectIdentifier(anchor))
    #expect(first.popupAnchor != ObjectIdentifier(elsewhere))
    store.setPopupVisibleWidget("b", anchor: elsewhere)
    #expect(first.popupAnchor == nil)
    #expect(second.popupAnchor == ObjectIdentifier(elsewhere))
    store.setPopupVisibleWidget(nil)
    #expect(second.popupAnchor == nil)
}

@Test @MainActor func openingAPopupInvalidatesOnlyTheViewsOfTheWidgetThatOpenedIt() throws {
    let store = try makeStore(threeWidgets)
    let configuration = try #require(store.configuration)
    let widgets = Dictionary(uniqueKeysWithValues: configuration.widgets.map {
        ($0.id, WidgetView(widget: $0, defaults: configuration.defaults, popupDefaults: configuration.popupDefaults, store: store,
                           monitor: 1, animationDuration: 0.2))
    })
    func invalidated(by change: () -> Void) -> [String] {
        let views = OSAllocatedUnfairLock(initialState: [String]())
        for (id, view) in widgets {
            withObservationTracking { _ = view.body } onChange: { views.withLock { $0.append(id) } }
        }
        change()
        return views.withLock { $0 }.sorted()
    }
    let aAnchor = NSView()
    let bAnchor = NSView()
    #expect(invalidated { store.setPopupVisibleWidget("a", anchor: aAnchor) } == ["a"])
    #expect(invalidated { store.setPopupVisibleWidget("b", anchor: bAnchor) } == ["a", "b"])
    #expect(invalidated { store.setPopupVisibleWidget(nil) } == ["b"])
}

@Test @MainActor func outputStateRestylesOnlyItsWidget() async throws {
    let store = try makeStore(##"""
    {"defaults":{"states":{"warning":{"foreground":"#ff0000"}}},"widgets":[
      {"id":"a","type":"script","command":"true","position":"left"},
      {"id":"b","type":"script","command":"true","position":"left"}]}
    """##)
    let a = try #require(store.scripts["a"])
    let first = try #require(store.presentations["a"])
    let second = try #require(store.presentations["b"])
    try await confirmation("a enters warning", expectedCount: 1) { restyled in
        try await confirmation("b stays valid", expectedCount: 0) { invalidated in
            withObservationTracking { _ = first.style } onChange: { restyled() }
            withObservationTracking { _ = second.style } onChange: { invalidated() }
            try a.accept(output(#"{"text":"12%","state":"warning"}"#))
        }
    }
    #expect(first.style.state == "warning")
    #expect(first.style.style(hovered: false).foreground == HexColor(0xff0000ff))
    try a.accept(output(#"{"text":"40%"}"#))
    #expect(first.style.state == nil)
}

@Test @MainActor func snapshotsReportTheDataState() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "config.json")
    try Data(#"""
    {"widgets":[{"id":"power","type":"script","position":"right","interval":null,
      "command":"printf '{\"text\":\"Low\",\"state\":\"warning\"}'"}]}
    """#.utf8).write(to: url)
    let store = BarStore(configurationURL: url)
    defer { store.stop() }
    store.reloadConfiguration()
    for _ in 0..<100 {
        if store.presentations["power"]?.style.state == "warning" { break }
        try await Task.sleep(for: .milliseconds(20))
    }
    guard case let .object(snapshot) = try store.snapshot(id: "power") else {
        Issue.record("Expected an object snapshot")
        return
    }
    #expect(snapshot["state"] == .string("warning"))
}

@Test @MainActor func snapshotsReportNoStateForAnEmptyOutputState() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "config.json")
    try Data(#"""
    {"widgets":[{"id":"power","type":"script","position":"right","interval":null,
      "command":"printf '{\"text\":\"Idle\",\"state\":\"\"}'"}]}
    """#.utf8).write(to: url)
    let store = BarStore(configurationURL: url)
    defer { store.stop() }
    store.reloadConfiguration()
    for _ in 0..<100 {
        if store.scripts["power"]?.output.text == "Idle" { break }
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(store.scripts["power"]?.output.text == "Idle")
    #expect(store.presentations["power"]?.style.state == nil)
    guard case let .object(snapshot) = try store.snapshot(id: "power") else {
        Issue.record("Expected an object snapshot")
        return
    }
    #expect(snapshot["state"] == .null)
}

@Test @MainActor func rulesRunWhenOutputArrivesForEachWidgetOfASharedProvider() async throws {
    let store = BarStore(configurationURL: FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json"))
    store.configuration = try JSONDecoder().decode(Configuration.self, from: Data(#"""
    {"widgets":[
      {"id":"compact","type":"battery","position":"right","rules":[{"when":{"value":"percent","below":0.2},"state":"warning"}]},
      {"id":"detail","type":"battery","position":"right","rules":[{"when":{"value":"percent","below":0.5},"state":"muted"}]},
      {"id":"clock","type":"clock","position":"right"}]}
    """#.utf8))
    let battery = ScriptWidget()
    store.scripts = ["compact": battery, "detail": battery]
    store.preparePresentations()
    let compact = try #require(store.presentations["compact"])
    let detail = try #require(store.presentations["detail"])
    let clock = try #require(store.presentations["clock"])
    try battery.accept(output(#"{"text":"40%","values":{"percent":0.4}}"#))
    #expect(compact.style.state == nil)
    #expect(detail.style.state == "muted")
    try await confirmation("compact enters warning", expectedCount: 1) { changed in
        try await confirmation("the others stay valid", expectedCount: 0) { invalidated in
            withObservationTracking { _ = compact.style } onChange: { changed() }
            withObservationTracking { _ = detail.style; _ = clock.style } onChange: { invalidated() }
            try battery.accept(output(#"{"text":"15%","values":{"percent":0.15}}"#))
        }
    }
    #expect(compact.style.state == "warning")
    #expect(detail.style.state == "muted")
}
