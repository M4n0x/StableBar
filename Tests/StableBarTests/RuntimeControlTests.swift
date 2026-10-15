import Foundation
import Testing
@testable import StableBar

@Test @MainActor func batchesAreAtomicAndPersistenceKeepsImportedFiles() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let root = directory.appending(path: "config.json")
    let module = directory.appending(path: "module.json")
    let moduleData = Data(#"{"widgets":[{"id":"a","type":"text","position":"left","text":"A"},{"id":"b","type":"clock","position":"right"}]}"#.utf8)
    try moduleData.write(to: module)
    let rootData = Data(#"{"includes":["module.json"]}"#.utf8)
    try rootData.write(to: root)
    let store = BarStore(configurationURL: root)
    defer { store.stop() }
    store.reloadConfiguration()
    #expect(throws: (any Error).self) {
        try store.applyEdits([ConfigurationEdit(action: .set, id: "a", properties: ["text": .string("Changed")]),
                              ConfigurationEdit(action: .set, id: "b", properties: ["position": .string("invalid")])], persist: true)
    }
    #expect(store.configuration?.widgets[0].content == .text("A"))
    #expect(store.sessionEdits.isEmpty)
    #expect(try Data(contentsOf: root) == rootData)
    try store.applyEdits([ConfigurationEdit(action: .set, id: "a", properties: ["text": .string("Live")])], persist: false)
    #expect(store.configuration?.widgets[0].content == .text("Live"))
    #expect(try Data(contentsOf: root) == rootData)
    try store.applyEdits([ConfigurationEdit(action: .add, properties: ["id": .string("c"), "type": .string("text"),
        "position": .string("left"), "text": .string("C")]), ConfigurationEdit(action: .remove, id: "b"),
        ConfigurationEdit(action: .reorder, ids: ["c", "a"])], persist: true)
    #expect(store.configuration?.widgets.map(\.id) == ["c", "a"])
    #expect(store.sessionEdits.isEmpty)
    #expect(try Data(contentsOf: module) == moduleData)
    let saved = try JSONDecoder().decode([String: ConfigurationValue].self, from: Data(contentsOf: root))
    #expect(saved["includes"] == .array([.string("module.json")]))
    var loader = ConfigurationLoader()
    #expect(try loader.load(root).widgets[1].content == .text("Live"))
    try store.applyEdits([ConfigurationEdit(action: .remove, id: "a"),
                         ConfigurationEdit(action: .add, properties: ["id": .string("a"), "type": .string("clock"), "position": .string("right")])], persist: false)
    #expect(store.configuration?.widgets.first(where: { $0.id == "a" })?.content == .clock(format: "EEE d MMM  HH:mm"))
}

@Test @MainActor func editorUndoRedoAndSessionReloadKeepExternalEdits() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let root = directory.appending(path: "config.json")
    let original = #"{"widgets":[{"id":"a","type":"text","position":"left","text":"A"}],"bar":{"height":40}}"#
    try Data(original.utf8).write(to: root)
    let store = BarStore(configurationURL: root)
    defer { store.stop() }
    store.reloadConfiguration()
    try store.applyEdits([ConfigurationEdit(action: .set, id: "a", properties: ["text": .string("Session")])], persist: false)
    try Data(original.replacingOccurrences(of: "40", with: "50").utf8).write(to: root)
    store.reloadConfiguration()
    #expect(store.configuration?.bar.height == 50)
    #expect(store.configuration?.widgets[0].content == .text("Session"))
    let editor = ConfigurationEditor(store: store)
    editor.set(["position": .string("right")])
    #expect(editor.preview.configuration?.widgets[0].position == .right)
    #expect(store.configuration?.widgets[0].position == .left)
    editor.undo()
    #expect(editor.preview.configuration?.widgets[0].position == .left)
    editor.redo()
    #expect(editor.preview.configuration?.widgets[0].position == .right)
    editor.change(ConfigurationEdit(action: .add, properties: ["id": .string("new"), "type": .string("text"),
        "position": .string("left"), "text": .string("New")]))
    editor.selectedID = "new"
    editor.undo()
    #expect(editor.selectedID == "a")
    editor.apply()
    #expect(store.configuration?.bar.height == 50)
    #expect(store.configuration?.widgets[0].position == .right)
    #expect(store.sessionEdits.isEmpty)
    try store.applyEdits([ConfigurationEdit(action: .set, id: "a", properties: ["text": .string("Temporary")])], persist: false)
    _ = try store.handle(RuntimeRequest(action: .reset))
    #expect(store.configuration?.widgets[0].content == .text("Session"))
}

@Test func controlCLIParsesAtomicBatchesAndRejectsMissingPackagePaths() throws {
    let command = try LaunchCommand(arguments: ["--config", "/tmp/custom.json", "--batch",
        #"[{"action":"set","id":"clock","properties":{"format":"HH:mm"}},{"action":"reorder","ids":["clock"]}]"#, "--persist"])
    guard case let .control(url, request) = command else { Issue.record("Expected control command"); return }
    #expect(url.path == "/tmp/custom.json")
    #expect(request.persist)
    #expect(request.edits?.count == 2)
    for flag in ["--inspect-package", "--install-package", "--add", "--set", "--enable-package"] {
        #expect(throws: (any Error).self) { try LaunchCommand(arguments: [flag]) }
    }
}

@Test @MainActor func acceptedSessionEditsSurviveAutomaticProfileChanges() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "config.json")
    let original = Data(#"""
        {
          "widgets":[{"id":"base","type":"text","position":"left","text":"Base"}],
          "profiles":[{"name":"light","when":{"appearance":"light"},"configuration":{"widgets":[
            {"id":"a","type":"text","position":"left","text":"A"},
            {"id":"b","type":"text","position":"left","text":"B"},
            {"id":"c","type":"text","position":"left","text":"C"}
          ]}}]
        }
        """#.utf8)
    try original.write(to: url)
    let store = BarStore(configurationURL: url)
    defer { store.stop() }
    store.reloadConfiguration()
    try store.applyEdits([
        ConfigurationEdit(action: .set, id: "a", properties: ["text": .string("Session")]),
        ConfigurationEdit(action: .remove, id: "b"),
        ConfigurationEdit(action: .reorder, ids: ["c", "a"])
    ], persist: false)
    #expect(store.configuration?.widgets.map(\.id) == ["c", "a", "base"])
    store.context.appearance = "dark"
    store.reloadConfiguration()
    #expect(store.configurationError == nil)
    #expect(store.configuration?.widgets.map(\.id) == ["base"])
    #expect(throws: (any Error).self) {
        try store.applyEdits([ConfigurationEdit(action: .set, id: "a", properties: ["text": .string("Invalid")])], persist: false)
    }
    #expect(throws: (any Error).self) {
        try store.applyEdits([ConfigurationEdit(action: .reorder, ids: ["a"])], persist: false)
    }
    #expect(store.sessionEdits.count == 3)
    #expect(try Data(contentsOf: url) == original)
    store.context.appearance = "light"
    store.reloadConfiguration()
    #expect(store.configurationError == nil)
    #expect(store.configuration?.widgets.map(\.id) == ["c", "a", "base"])
    #expect(store.configuration?.widgets[1].content == .text("Session"))
    store.context.appearance = "dark"
    store.reloadConfiguration()
    let editor = ConfigurationEditor(store: store)
    editor.set(["text": .string("Edited base")])
    #expect(editor.error == nil)
    editor.apply()
    #expect(editor.error == nil)
    #expect(store.sessionEdits.isEmpty)
    store.context.appearance = "light"
    store.reloadConfiguration()
    #expect(store.configurationError == nil)
    #expect(store.configuration?.widgets.map(\.id) == ["c", "a", "base"])
    #expect(store.configuration?.widgets[1].content == .text("Session"))
    #expect(store.configuration?.widgets[2].content == .text("Edited base"))
}

@Test @MainActor func repeatedEditorFieldValuesDoNotCreateHistoryOrClearRedo() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let root = directory.appending(path: "config.json")
    try Data(#"""
    {"defaults":{"fontSize":12,"paddingHorizontal":10,"cornerRadius":14},"widgets":[
      {"id":"title","type":"text","position":"left","text":"Ready","style":{"minWidth":80,"maxWidth":100}}
    ]}
    """#.utf8).write(to: root)
    let store = BarStore(configurationURL: root)
    defer { store.stop() }
    store.reloadConfiguration()
    let editor = ConfigurationEditor(store: store)
    for _ in 0..<2 {
        editor.set(["style": .object(["fontSize": .number(12)])])
        editor.set(["style": .object(["paddingHorizontal": .number(10)])])
        editor.set(["style": .object(["cornerRadius": .number(14)])])
    }
    #expect(editor.edits.isEmpty)
    #expect(editor.undoSteps.isEmpty)
    editor.set(["text": .string("Changed")])
    editor.undo()
    editor.set(["text": .string("Ready")])
    #expect(editor.redoSteps.count == 1)
    editor.redo()
    #expect(editor.preview.configuration?.widgets[0].content == .text("Changed"))
    editor.set(["style": .object(["minWidth": .number(200)])])
    #expect(editor.error != nil)
    editor.set(["style": .object(["minWidth": .number(80)])])
    #expect(editor.error == nil)
    editor.discard()
    editor.change(ConfigurationEdit(action: .set, id: "title", properties: ["style": .object(["fontSize": .number(12)])]))
    #expect(editor.edits.count == 1)
    #expect(editor.preview.configuration?.widgets[0].style.fontSize == 12)
}
