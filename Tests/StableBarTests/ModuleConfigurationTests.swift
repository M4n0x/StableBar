import Foundation
import Testing
@testable import StableBar

private func writeConfiguration(_ json: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(json.utf8).write(to: url, options: .atomic)
}

@Test func modulesComposeRelativeToEachFileWithRootOverrides() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let root = directory.appending(path: "bar/config.json")
    let module = directory.appending(path: "bar/modules/system.json")
    let theme = directory.appending(path: "bar/themes/dark.json")
    let shared = directory.appending(path: "shared/clock.json")
    try writeConfiguration(##"""
    {"bar":{"height":36,"style":{"foreground":"#eeeeee","fontSize":11}},
     "defaults":{"fontSize":12,"background":"#111111"},
     "environment":{"SHARED":"theme","THEME":"dark"},
     "popups":{"details":{"height":180,"style":{"fontSize":12},"layout":{"type":"text","text":"Details"}}}}
    """##, to: theme)
    try writeConfiguration(#"""
    {"includes":["../themes/dark.json"],"bar":{"height":38},
     "widgets":[{"id":"system","type":"text","position":"left","text":"System","popupName":"details"}]}
    """#, to: module)
    try writeConfiguration(#"""
    {"defaults":{"fontSize":13},"widgets":[{"id":"clock","type":"clock","position":"right"}]}
    """#, to: shared)
    try writeConfiguration(##"""
    {"includes":["modules/system.json","../shared/clock.json"],
     "bar":{"height":44,"style":{"fontSize":15}},"defaults":{"foreground":"#abcdef"},
     "environment":{"SHARED":"root"},"popups":{"details":{"style":{"foreground":"#abcdef"}}},
     "widgets":[{"id":"local","type":"text","position":"right","text":"Local"}]}
    """##, to: root)
    var loader = ConfigurationLoader()
    let configuration = try loader.load(root)
    #expect(configuration.widgets.map(\.id) == ["system", "clock", "local"])
    #expect(configuration.bar.height == 44)
    #expect(configuration.bar.style.fontSize == 15)
    #expect(configuration.bar.style.foreground == HexColor(0xeeeeeeff))
    #expect(configuration.defaults.fontSize == 13)
    #expect(configuration.defaults.background == HexColor(0x111111ff))
    #expect(configuration.defaults.foreground == HexColor(0xabcdefff))
    #expect(configuration.environment == ["SHARED": "root", "THEME": "dark"])
    #expect(configuration.popups["details"]?.height == 180)
    #expect(configuration.popups["details"]?.style.fontSize == 12)
    #expect(configuration.popups["details"]?.style.foreground == HexColor(0xabcdefff))
    #expect(loader.dependencies == [root, module, theme, shared])
}

@Test func widgetTemplatesInheritRecursivelyAndReplaceArrays() throws {
    let data = Data(##"""
    {"templates":{
       "base":{"type":"script","position":"right","interval":30,"events":["base"],
               "environment":{"BASE":"yes","SHARED":"base"},
               "style":{"foreground":"#eeeeee","fontSize":12},
               "layout":{"type":"row","style":{"spacing":6},"children":[{"type":"text","text":"base"}]}},
       "metric":{"template":"base","style":{"fontSize":14,"background":"#111111"},
                 "layout":{"style":{"paddingHorizontal":8}}}
     },"widgets":[{"id":"cpu","template":"metric","command":"echo 10%","interval":null,
                   "events":["refresh"],"environment":{"SHARED":"widget"},
                   "style":{"foreground":"#abcdef"},
                   "layout":{"children":[{"type":"field","field":"text"}]}}]}
    """##.utf8)
    let configuration = try JSONDecoder().decode(Configuration.self, from: data)
    let widget = configuration.widgets[0]
    #expect(widget.position == .right)
    #expect(widget.content == .script(command: "echo 10%", interval: nil))
    #expect(widget.events == ["refresh"])
    #expect(widget.environment == ["BASE": "yes", "SHARED": "widget"])
    #expect(widget.style.fontSize == 14)
    #expect(widget.style.foreground == HexColor(0xabcdefff))
    #expect(widget.style.background == HexColor(0x111111ff))
    #expect(widget.layout?.style.spacing == 6)
    #expect(widget.layout?.style.paddingHorizontal == 8)
    guard case let .row(children) = widget.layout?.content,
          case let .field(field) = children[0].content else {
        Issue.record("The template layout was not preserved.")
        return
    }
    #expect(children.count == 1)
    #expect(field == "text")
}

@Test func moduleTemplatesCanBeOverriddenByTheRootWithoutDefiningRootWidgets() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let root = directory.appending(path: "config.json")
    try writeConfiguration(##"""
    {"templates":{"label":{"type":"text","position":"left","style":{"fontSize":12,"foreground":"#eeeeee"}}},
     "widgets":[{"id":"label","template":"label","text":"Ready"}]}
    """##, to: directory.appending(path: "module.json"))
    try writeConfiguration(#"""
    {"includes":["module.json"],"templates":{"label":{"style":{"fontSize":16}}}}
    """#, to: root)
    var loader = ConfigurationLoader()
    let configuration = try loader.load(root)
    #expect(configuration.widgets[0].style.fontSize == 16)
    #expect(configuration.widgets[0].style.foreground == HexColor(0xeeeeeeff))
    #expect(configuration.widgets[0].content == .text("Ready"))
}

@Test func moduleCompositionRejectsDuplicateIDsAndIncludeCycles() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let root = directory.appending(path: "config.json")
    let module = directory.appending(path: "module.json")
    try writeConfiguration(#"{"widgets":[{"id":"clock","type":"clock","position":"right"}]}"#, to: module)
    try writeConfiguration(#"{"includes":["module.json"],"widgets":[{"id":"clock","type":"clock","position":"left"}]}"#, to: root)
    var loader = ConfigurationLoader()
    #expect(throws: DecodingError.self) { try loader.load(root) }
    try writeConfiguration(#"{"includes":["config.json"]}"#, to: module)
    #expect(throws: ConfigurationCompositionError.self) { try loader.load(root) }
    #expect(loader.dependencies == [root, module])
    let alias = directory.appending(path: "alias.json")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
    try writeConfiguration(#"{"includes":["alias.json"]}"#, to: module)
    #expect(throws: ConfigurationCompositionError.self) { try loader.load(root) }
}

@Test func unknownAndCyclicWidgetTemplatesFailBeforeReplacingWidgets() {
    #expect(throws: ConfigurationCompositionError.self) {
        try JSONDecoder().decode(Configuration.self, from: Data(#"{"widgets":[{"id":"label","template":"missing"}]}"#.utf8))
    }
    #expect(throws: ConfigurationCompositionError.self) {
        try JSONDecoder().decode(Configuration.self, from: Data(#"""
        {"templates":{"a":{"template":"b"},"b":{"template":"a"}},"widgets":[{"id":"label","template":"a"}]}
        """#.utf8))
    }
}

@Test func configurationEditsValidateIncludesUsingTheOriginalDirectory() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let root = directory.appending(path: "config.json")
    let module = directory.appending(path: "module.json")
    try writeConfiguration(#"{"widgets":[{"id":"clock","type":"clock","position":"right"}]}"#, to: module)
    var loader = ConfigurationLoader()
    let configuration = try loader.load(root, data: Data(#"{"includes":["module.json"],"bar":{"height":48}}"#.utf8))
    #expect(configuration.bar.height == 48)
    #expect(configuration.widgets.map(\.id) == ["clock"])
    #expect(loader.dependencies == [root, module])
}

@Test @MainActor func dependencyWatcherDetectsAtomicSavesAndMissingDirectoryRepairs() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let root = directory.appending(path: "bar/config.json")
    let module = directory.appending(path: "shared/nested/widgets.json")
    try writeConfiguration(#"{"includes":["../shared/nested/widgets.json"]}"#, to: root)
    var loader = ConfigurationLoader()
    #expect(throws: (any Error).self) { try loader.load(root) }
    #expect(loader.dependencies == [root, module])
    let watcher = ConfigurationWatcher()
    defer { watcher.stop() }
    var changed = false
    watcher.onChange = { changed = true }
    watcher.watch(loader.dependencies)
    try writeConfiguration(#"{"widgets":[{"id":"label","type":"text","position":"left","text":"First"}]}"#, to: module)
    for _ in 0..<100 {
        if changed { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(changed)
    #expect(try loader.load(root).widgets[0].content == .text("First"))
    watcher.watch(loader.dependencies)
    changed = false
    try writeConfiguration(#"{"widgets":[{"id":"label","type":"text","position":"left","text":"Second"}]}"#, to: module)
    for _ in 0..<100 {
        if changed { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(changed)
    #expect(try loader.load(root).widgets[0].content == .text("Second"))
}

@Test func widgetOverridesCustomizeImportedTemplatesWithoutReplacingModules() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let root = directory.appending(path: "config.json")
    try writeConfiguration(##"""
    {"templates":{"metric":{"type":"script","position":"right","interval":15,"enabled":false,
       "style":{"fontSize":12,"foreground":"#eeeeee"},"events":["workspace","wake"]}},
     "widgets":[{"id":"cpu","template":"metric","command":"echo 10%"},
                {"id":"clock","type":"clock","position":"right","format":"HH:mm"}],
     "widgetOverrides":{"cpu":{"style":{"background":"#111111"}}}}
    """##, to: directory.appending(path: "module.json"))
    try writeConfiguration(##"""
    {"includes":["module.json"],"widgetOverrides":{
      "cpu":{"enabled":true,"interval":null,"events":["refresh"],"style":{"fontSize":16}},
      "clock":{"enabled":false,"format":"h:mm a"}}}
    """##, to: root)
    var loader = ConfigurationLoader()
    let configuration = try loader.load(root)
    #expect(configuration.widgets.map(\.id) == ["cpu", "clock"])
    let cpu = configuration.widgets[0]
    #expect(cpu.enabled)
    #expect(cpu.content == .script(command: "echo 10%", interval: nil))
    #expect(cpu.events == ["refresh"])
    #expect(cpu.style.fontSize == 16)
    #expect(cpu.style.foreground == HexColor(0xeeeeeeff))
    #expect(cpu.style.background == HexColor(0x111111ff))
    #expect(!configuration.widgets[1].enabled)
    #expect(configuration.widgets[1].content == .clock(format: "h:mm a"))
}

@Test func widgetOverridesRejectUnknownTargetsAndIdentityChanges() {
    #expect(throws: ConfigurationCompositionError.self) {
        try JSONDecoder().decode(Configuration.self, from: Data(#"""
        {"widgets":[{"id":"clock","type":"clock","position":"right"}],"widgetOverrides":{"missing":{"format":"HH:mm"}}}
        """#.utf8))
    }
    for id in ["changed", "clock"] {
        #expect(throws: ConfigurationCompositionError.self) {
            try JSONDecoder().decode(Configuration.self, from: Data("""
            {"widgets":[{"id":"clock","type":"clock","position":"right"}],"widgetOverrides":{"clock":{"id":"\(id)"}}}
            """.utf8))
        }
    }
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(Configuration.self, from: Data(#"""
        {"widgets":[{"id":"clock","type":"clock","position":"left"},{"id":"clock","type":"clock","position":"right"}],
         "widgetOverrides":{"clock":{"enabled":false}}}
        """#.utf8))
    }
}

@Test func modulesRejectExplicitNullWidgetListsInsteadOfClearingInheritedWidgets() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let root = directory.appending(path: "config.json")
    try writeConfiguration(#"{"widgets":[{"id":"clock","type":"clock","position":"right"}]}"#,
                           to: directory.appending(path: "module.json"))
    try writeConfiguration(#"{"includes":["module.json"],"widgets":null}"#, to: root)
    var loader = ConfigurationLoader()
    #expect(throws: DecodingError.self) { try loader.load(root) }
}

@Test @MainActor func liveModuleReloadPreservesWorkingScriptsAndRecoversAfterRepair() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let root = directory.appending(path: "bar/config.json")
    let module = directory.appending(path: "shared/status.json")
    let document = #"""
    {"bar":{"height":37},"widgets":[{"id":"status","type":"script","position":"right",
      "command":"printf '%s' \"$SENDER\"","interval":null}]}
    """#
    try writeConfiguration(document, to: module)
    try writeConfiguration(#"{"includes":["../shared/status.json"]}"#, to: root)
    let store = BarStore(configurationURL: root)
    defer { store.stop() }
    store.start()
    let previous = try #require(store.configuration)
    let script = try #require(store.scripts["status"])
    for _ in 0..<100 {
        if script.output.text == "startup" { break }
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(script.output.text == "startup")
    try writeConfiguration("{", to: module)
    for _ in 0..<100 {
        if store.configurationError != nil { break }
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(store.configurationError != nil)
    #expect(store.configuration?.bar.height == previous.bar.height)
    #expect(store.configuration?.widgets.map(\.id) == previous.widgets.map(\.id))
    #expect(store.configuration?.widgets[0].content == previous.widgets[0].content)
    #expect(store.scripts["status"] === script)
    #expect(script.output.text == "startup")
    try writeConfiguration(document.replacingOccurrences(of: "37", with: "49"), to: module)
    for _ in 0..<100 {
        if store.configuration?.bar.height == 49 { break }
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(store.configuration?.bar.height == 49)
    #expect(store.configurationError == nil)
    #expect(store.scripts["status"] === script)
    #expect(script.output.text == "startup")
    try writeConfiguration(#"""
    {"includes":["../shared/status.json"],"widgetOverrides":{"status":{"enabled":false}}}
    """#, to: root)
    for _ in 0..<100 {
        if store.scripts["status"] == nil { break }
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(store.configuration?.widgets[0].enabled == false)
    #expect(store.scripts["status"] == nil)
    script.refresh(ScriptEvent(sender: "disabled"))
    try await Task.sleep(for: .milliseconds(100))
    #expect(script.output.text == "startup")
    try writeConfiguration(#"""
    {"includes":["../shared/status.json"],"widgetOverrides":{"status":{"enabled":true}}}
    """#, to: root)
    for _ in 0..<100 {
        if store.scripts["status"]?.output.text == "startup" { break }
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(store.configuration?.widgets[0].enabled == true)
    #expect(store.scripts["status"]?.output.text == "startup")
    #expect(store.scripts["status"] !== script)
    #expect(store.configurationError == nil)
}

@Test func unknownPropertiesFailWithTheirPath() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "strict.json")
    var loader = ConfigurationLoader()
    for (json, message) in [
        (#"{"widgets":[{"id":"clock","type":"clock","position":"right","style":{"fontsize":14}}]}"#, "widgets.clock: style.fontsize: Unknown property."),
        (#"{"widgets":[],"bar":{"heigth":30}}"#, "bar.heigth: Unknown property."),
        (#"{"widgets":[],"profiles":[{"name":"dark","when":{"apperance":"dark"},"configuration":{}}]}"#, "profiles.0.when.apperance: Unknown property."),
        (#"{"widgets":[}"#, "The given data was not valid JSON. Unexpected character '}' around line 1, column 13.")
    ] {
        let error = #expect(throws: (any Error).self) { try loader.load(url, data: Data(json.utf8)) }
        #expect(error.map(errorMessage) == message)
    }
    #expect(try loader.load(url, data: Data(#"{"$schema":"stablebar.schema.json","widgets":[]}"#.utf8)).widgets.isEmpty)
}

@Test func schemaListsTheSamePropertiesAsTheDecoders() throws {
    let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "stablebar.schema.json")
    let schema = try JSONDecoder().decode([String: ConfigurationValue].self, from: Data(contentsOf: url))
    func properties(_ definition: ConfigurationValue?) throws -> Set<String> {
        Set(try (definition?.decoded([String: ConfigurationValue].self)["properties"] ?? .object([:])).decoded([String: ConfigurationValue].self).keys)
    }
    let definitions = try schema["definitions"]!.decoded([String: ConfigurationValue].self)
    let decoders: [String: [CodingKey]] = [
        "style": WidgetStyle.CodingKeys.allCases, "widget": WidgetConfiguration.CodingKeys.allCases, "bar": BarSettings.CodingKeys.allCases,
        "block": PopupBlock.CodingKeys.allCases, "popup": PopupConfiguration.CodingKeys.allCases, "option": PopupControlOption.CodingKeys.allCases,
        "animation": WidgetAnimation.CodingKeys.allCases, "workspace": WorkspaceConfiguration.CodingKeys.allCases,
        "actions": WidgetActions.CodingKeys.allCases, "menuItem": WidgetMenuItem.CodingKeys.allCases,
        "provider": ProviderConfiguration.CodingKeys.allCases, "group": WidgetGroupConfiguration.CodingKeys.allCases,
        "profile": ConfigurationProfile.CodingKeys.allCases, "conditions": ProfileConditions.CodingKeys.allCases,
        "packageSelection": WidgetPackageSelection.CodingKeys.allCases
    ]
    for (name, keys) in decoders {
        #expect(try properties(definitions[name]) == Set(keys.map(\.stringValue) + (name == "widget" ? ["template"] : [])), "\(name)")
    }
    #expect(try properties(.object(schema)) == Set(Configuration.CodingKeys.allCases.map(\.stringValue)
        + ["$schema", "tokens", "packages", "includes", "profiles", "profile", "widgetOrder"]))
}
