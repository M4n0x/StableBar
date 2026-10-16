import CryptoKit
import Foundation
import Testing
@testable import StableBar

private func writePackageFile(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url, options: .atomic)
}

@Test func tokensAndProfilesPreserveTypesAndApplyInDeclaredOrder() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let root = directory.appending(path: "config.json")
    try writePackageFile(##"""
    {"tokens":{"size":11,"foreground":"#111111","alias":"@token.size"},
     "templates":{"base":{"type":"text","position":"left","text":"Ready","style":{"fontSize":"@token.alias"}}},
     "widgets":[{"id":"status.main","template":"base"}]}
    """##, to: directory.appending(path: "module.json"))
    try writePackageFile(##"""
    {"includes":["module.json"],"tokens":{"size":12},"defaults":{"foreground":"@token.foreground"},
     "profiles":[
       {"name":"dark","when":{"appearance":"dark"},"configuration":{"tokens":{"foreground":"#eeeeee","size":14}}},
       {"name":"portable","when":{"onBattery":true,"displayCount":1,"externalDisplay":false,"app":"com.test.Editor"},
        "configuration":{"tokens":{"size":16},"bar":{"height":32}}}],
     "widgetOverrides":{"status.main":{"style":{"background":"@token.foreground"}}}}
    """##, to: root)
    var loader = ConfigurationLoader()
    let normal = try loader.load(root)
    #expect(normal.widgets[0].style.fontSize == 12)
    #expect(loader.activeProfiles.isEmpty)
    let dark = try loader.load(root, context: ConfigurationContext(appearance: "dark", onBattery: true,
                                                                  displayCount: 1, externalDisplay: false, app: "com.test.Editor"))
    #expect(loader.activeProfiles == ["dark", "portable"])
    #expect(dark.widgets[0].style.fontSize == 16)
    #expect(dark.defaults.foreground == HexColor(0xeeeeeeff))
    #expect(dark.widgets[0].style.background == HexColor(0xeeeeeeff))
    #expect(dark.bar.height == 32)
    #expect(loader.origins["widgets.status.main.style.fontSize"]?.description.contains("template base") == true)
    #expect(loader.origins["widgets.status.main.style.background"]?.description.contains("widget override") == true)
    #expect(loader.origins["widgets.status.main.style.background"]?.description.contains("token foreground") == true)
    #expect(loader.document["templates"] == nil)
    #expect(loader.document["widgetOverrides"] == nil)
}

@Test func manualProfilesOverrideConditionsAndUnknownProfilesFail() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "profiles.json")
    let json = #"""
    {"profile":"desktop","widgets":[],"profiles":[
      {"name":"mobile","when":{"displayCount":1},"configuration":{"bar":{"height":30}}},
      {"name":"desktop","when":{"displayCount":2},"configuration":{"bar":{"height":50}}}]}
    """#
    var loader = ConfigurationLoader()
    #expect(try loader.load(url, data: Data(json.utf8)).bar.height == 50)
    #expect(loader.activeProfiles == ["desktop"])
    #expect(throws: ThemeConfigurationError.self) {
        try loader.load(url, data: Data(json.replacingOccurrences(of: "\"profile\":\"desktop\"", with: "\"profile\":\"missing\"").utf8))
    }
}

@Test func explicitAutomaticProfileOverridesAnIncludedManualSelection() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try writePackageFile(#"""
    {"profile":"desktop","widgets":[],"profiles":[
      {"name":"laptop","when":{"displayCount":1},"configuration":{"bar":{"height":30}}},
      {"name":"desktop","when":{"displayCount":2},"configuration":{"bar":{"height":50}}}]}
    """#, to: directory.appending(path: "module.json"))
    let root = directory.appending(path: "config.json")
    var loader = ConfigurationLoader()
    #expect(try loader.load(root, data: Data(#"{"includes":["module.json"]}"#.utf8)).bar.height == 50)
    #expect(try loader.load(root, data: Data(#"{"includes":["module.json"],"profile":null}"#.utf8)).bar.height == 30)
    #expect(loader.activeProfiles == ["laptop"])
}

@Test func customizationAndRemovedWidgetsMigrateIntoNormalKeys() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try writePackageFile(#"""
    {"widgets":[{"id":"imported","type":"text","position":"right","text":"Imported"},
                {"id":"gone","type":"text","position":"right","text":"Gone"}]}
    """#, to: directory.appending(path: "module.json"))
    let root = directory.appending(path: "config.json")
    try writePackageFile(#"""
    {"includes":["module.json"],"bar":{"height":40},
     "widgets":[{"id":"clock","type":"clock","position":"left"},{"id":"old","type":"text","position":"left","text":"Old"}],
     "removedWidgets":["old","gone"],
     "customization":{"bar":{"height":48},"defaults":{"fontSize":16},
       "widgetOverrides":{"clock":{"position":"center"},"imported":{"text":"Changed"}},"widgetOrder":["clock","imported"]}}
    """#, to: root)
    try migrateConfigurationFile(root)
    let saved = try JSONDecoder().decode([String: ConfigurationValue].self, from: Data(contentsOf: root))
    #expect(saved["customization"] == nil)
    #expect(saved["removedWidgets"] == nil)
    #expect(saved["bar"] == .object(["height": .number(48)]))
    #expect(saved["defaults"] == .object(["fontSize": .number(16)]))
    #expect(saved["widgets"] == .array([.object(["id": .string("clock"), "type": .string("clock"), "position": .string("center")])]))
    #expect(saved["widgetOverrides"] == .object(["imported": .object(["text": .string("Changed")]),
                                                 "gone": .object(["enabled": .bool(false)])]))
    var loader = ConfigurationLoader()
    let configuration = try loader.load(root)
    #expect(configuration.widgets.map(\.id) == ["clock", "imported", "gone"])
    #expect(configuration.widgets[1].content == .text("Changed"))
    #expect(!configuration.widgets[2].enabled)
}

@Test func tokenCyclesUnknownNamesAndWrongTypesFailWithoutShellInterpolation() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "tokens.json")
    var loader = ConfigurationLoader()
    for tokens in [#"{"a":"@token.b","b":"@token.a"}"#, #"{"a":"@token.missing"}"#] {
        #expect(throws: ThemeConfigurationError.self) {
            try loader.load(url, data: Data("{\"widgets\":[],\"tokens\":\(tokens)}".utf8))
        }
    }
    #expect(throws: DecodingError.self) {
        try loader.load(url, data: Data(#"{"widgets":[],"tokens":{"size":"large"},"bar":{"height":"@token.size"}}"#.utf8))
    }
    let configuration = try loader.load(url, data: Data(#"""
    {"tokens":{"word":"replacement","style":{"fontSize":17}},"widgets":[
      {"id":"script","type":"script","position":"left","style":"@token.style","command":"printf '@token.word'"}]}
    """#.utf8))
    #expect(configuration.widgets[0].content == .script(command: "printf '@token.word'", interval: 30))
    #expect(configuration.widgets[0].style.fontSize == 17)
    #expect(loader.origins["widgets.script.style.fontSize"]?.description.contains("token style") == true)
}

@Test func widgetOrderSkipsAbsentWidgetsAndRejectsDuplicates() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "order.json")
    var loader = ConfigurationLoader()
    let json = #"""
    {"widgets":[{"id":"a","type":"clock","position":"left"},{"id":"b","type":"clock","position":"left"}],
     "profiles":[{"name":"desktop","when":{"externalDisplay":true},"configuration":{
       "widgets":[{"id":"extra","type":"text","position":"right","text":"Desktop"}]}}],
     "widgetOrder":["extra","b"]}
    """#
    #expect(try loader.load(url, data: Data(json.utf8)).widgets.map(\.id) == ["b", "a"])
    #expect(loader.document["widgetOrder"] == nil)
    #expect(try loader.load(url, data: Data(json.utf8), context: ConfigurationContext(externalDisplay: true)).widgets.map(\.id) == ["extra", "b", "a"])
    #expect(throws: ConfigurationCompositionError.self) {
        try loader.load(url, data: Data(json.replacingOccurrences(of: #""widgetOrder":["extra","b"]"#, with: #""widgetOrder":["b","b"]"#).utf8))
    }
    #expect(throws: DecodingError.self) {
        try loader.load(url, data: Data(#"""
        {"widgets":[{"id":"a","type":"clock","position":"left"},{"id":"a","type":"clock","position":"left"}],"widgetOrder":["a"]}
        """#.utf8))
    }
    #expect(throws: DecodingError.self) {
        try loader.load(url, data: Data(#"{"widgets":[{"type":"clock","position":"left"}]}"#.utf8))
    }
}

@Test func packagesInstallWithoutExecutingAndComposePinnedSettingsAndAssets() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appending(path: "source")
    let store = WidgetPackageStore(directory: directory.appending(path: "bar/packages"))
    let marker = directory.appending(path: "executed")
    try writePackageFile(#"""
    {"id":"weather","name":"Weather","version":"1.0.0","entry":"config.json",
     "settings":{"label":{"type":"string","default":"Weather"},"size":{"type":"number","default":13}}}
    """#, to: source.appending(path: "package.json"))
    try writePackageFile("touch '\(marker.path)'", to: source.appending(path: "scripts/weather.sh"))
    try writePackageFile("image", to: source.appending(path: "assets/icon.png"))
    try writePackageFile(#"""
    {"tokens":{"image":"assets/icon.png"},"templates":{"exported":{"type":"script","position":"left","command":"echo exported"}},
     "widgets":[{"id":"weather","type":"text","position":"right","text":"@setting.label",
      "style":{"fontSize":"@setting.size"},"onClick":"sh \"$PACKAGE_DIR/scripts/weather.sh\"",
      "popup":{"height":120,"style":{},"layout":{"type":"image","path":"@token.image"}}}],
     "profiles":[{"name":"night","when":{"appearance":"dark"},"configuration":{
       "widgetOverrides":{"weather":{"onClick":"echo night"}}}}]}
    """#, to: source.appending(path: "config.json"))
    let inspection = try store.inspect(source)
    #expect(inspection.commands == ["echo exported", "echo night", "sh \"$PACKAGE_DIR/scripts/weather.sh\""])
    #expect(!FileManager.default.fileExists(atPath: marker.path))
    let installed = try store.install(source)
    #expect(installed.directory == directory.appending(path: "bar/packages/weather/1.0.0"))
    #expect(!FileManager.default.fileExists(atPath: marker.path))
    #expect(throws: WidgetPackageError.self) { try store.install(source) }
    var loader = ConfigurationLoader()
    let root = directory.appending(path: "bar/config.json")
    let configuration = try loader.load(root, data: Data(#"""
    {"packages":[{"id":"weather","version":"1.0.0","settings":{"label":"Local","size":19}}],
     "widgetOverrides":{"weather":{"position":"left"}}}
    """#.utf8))
    let widget = configuration.widgets[0]
    #expect(widget.content == .text("Local"))
    #expect(widget.style.fontSize == 19)
    #expect(widget.position == .left)
    #expect(widget.environment["PACKAGE_DIR"] == installed.directory.path)
    guard case let .image(path, _, _) = widget.popup?.layout.content else {
        Issue.record("Expected package image")
        return
    }
    #expect(path == installed.directory.appending(path: "assets/icon.png").path)
    #expect(loader.dependencies.contains(installed.directory.appending(path: "package.json")))
}

@Test func packagePinsAllowRollbackAndDisabledPackagesDoNotLoad() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appending(path: "source")
    let store = WidgetPackageStore(directory: directory.appending(path: "packages"))
    for version in ["1", "2"] {
        try writePackageFile("""
        {"id":"clock","name":"Clock","version":"\(version)","entry":"config.json"}
        """, to: source.appending(path: "package.json"))
        try writePackageFile("""
        {"widgets":[{"id":"clock","type":"text","position":"left","text":"Version \(version)"}]}
        """, to: source.appending(path: "config.json"))
        _ = try store.install(source)
    }
    #expect(try store.list().map(\.version) == ["1", "2"])
    var loader = ConfigurationLoader()
    for version in ["2", "1"] {
        let configuration = try loader.load(directory.appending(path: "config.json"), data: Data("""
        {"packages":[{"id":"clock","version":"\(version)"},{"id":"missing","version":"1","enabled":false}]}
        """.utf8))
        #expect(configuration.widgets[0].content == .text("Version \(version)"))
    }
}

@Test func rootPackagePinsOverrideIncludedSelectionsWithoutDuplicatingProviders() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appending(path: "source")
    let packages = WidgetPackageStore(directory: directory.appending(path: "packages"))
    for (id, version) in [("alpha", "1"), ("alpha", "2"), ("beta", "1")] {
        try writePackageFile("""
        {"id":"\(id)","name":"\(id)","version":"\(version)","entry":"config.json"}
        """, to: source.appending(path: "package.json"))
        try writePackageFile(#"""
        {"providers":{"\#(id)":{"type":"command","command":"printf '%s' \"$PACKAGE_DIR\"","interval":60}},
         "widgets":[{"id":"\#(id)","type":"provider","provider":"\#(id)","position":"right"}]}
        """#, to: source.appending(path: "config.json"))
        _ = try packages.install(source)
    }
    try writePackageFile(#"{"packages":[{"id":"alpha","version":"1"},{"id":"beta","version":"1"}]}"#,
                         to: directory.appending(path: "module.json"))
    let root = directory.appending(path: "config.json")
    var loader = ConfigurationLoader()
    let upgraded = try loader.load(root, data: Data(#"""
    {"includes":["module.json"],"packages":[{"id":"alpha","version":"2"}]}
    """#.utf8))
    #expect(upgraded.widgets.map(\.id) == ["alpha", "beta"])
    #expect(upgraded.providers["alpha"]?.environment["PACKAGE_DIR"] == directory.appending(path: "packages/alpha/2").path)
    #expect(upgraded.providers["beta"]?.environment["PACKAGE_DIR"] == directory.appending(path: "packages/beta/1").path)
    let disabled = try loader.load(root, data: Data(#"""
    {"includes":["module.json"],"packages":[{"id":"alpha","version":"2","enabled":false}]}
    """#.utf8))
    #expect(disabled.widgets.map(\.id) == ["beta"])
    #expect(disabled.providers["alpha"] == nil)
    #expect(!loader.dependencies.contains(directory.appending(path: "packages/alpha/1/config.json")))
    #expect(!loader.dependencies.contains(directory.appending(path: "packages/alpha/2/config.json")))
    try writePackageFile(#"{"packages":[{"id":"alpha","version":"2","enabled":false},{"id":"beta","version":"1"}]}"#,
                         to: directory.appending(path: "module.json"))
    let rollback = try loader.load(root, data: Data(#"""
    {"includes":["module.json"],"packages":[{"id":"alpha","version":"1","enabled":true}]}
    """#.utf8))
    #expect(rollback.widgets.map(\.id) == ["alpha", "beta"])
    #expect(rollback.providers["alpha"]?.environment["PACKAGE_DIR"] == directory.appending(path: "packages/alpha/1").path)
}

@Test func packageValidationRejectsTraversalEscapingSymlinksAndUnknownSettings() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appending(path: "source")
    let store = WidgetPackageStore(directory: directory.appending(path: "packages"))
    let manifest = #"{"id":"clock","name":"Clock","version":"1","entry":"config.json"}"#
    try writePackageFile(manifest, to: source.appending(path: "package.json"))
    try writePackageFile(#"{"widgets":[]}"#, to: directory.appending(path: "outside.json"))
    for configuration in [#"{"includes":["../outside.json"]}"#,
                          #"{"widgets":[{"id":"image","type":"text","position":"left","text":"Image","layout":{"type":"image","path":"../outside.json"}}]}"#] {
        try writePackageFile(configuration, to: source.appending(path: "config.json"))
        #expect(throws: WidgetPackageError.self) { try store.install(source) }
    }
    try writePackageFile(#"{"widgets":[]}"#, to: source.appending(path: "config.json"))
    try FileManager.default.createSymbolicLink(at: source.appending(path: "escaped.json"), withDestinationURL: directory.appending(path: "outside.json"))
    #expect(throws: WidgetPackageError.self) { try store.inspect(source) }
    try FileManager.default.removeItem(at: source.appending(path: "escaped.json"))
    for id in ["../clock", ".", "", "/clock"] {
        #expect(throws: WidgetPackageError.self) { try store.directory(id: id, version: "1") }
    }
    for entry in ["../outside.json", "/tmp/outside.json", "missing.json"] {
        try writePackageFile(manifest.replacingOccurrences(of: "config.json", with: entry), to: source.appending(path: "package.json"))
        #expect(throws: WidgetPackageError.self) { try store.inspect(source) }
    }
    try writePackageFile(manifest, to: source.appending(path: "package.json"))
    let installed = try store.install(source)
    var loader = ConfigurationLoader()
    #expect(throws: WidgetPackageError.self) {
        try loader.load(directory.appending(path: "config.json"), data: Data(#"{"packages":[{"id":"clock","version":"1","settings":{"unknown":"x"}}]}"#.utf8))
    }
    #expect(FileManager.default.fileExists(atPath: installed.directory.path))
}

@Test func themePackagesContainOnlyStylesAndAreSelectedOnlyAsTheTheme() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let theme = directory.appending(path: "theme")
    let widget = directory.appending(path: "widget")
    let store = WidgetPackageStore(directory: directory.appending(path: "packages"))
    try writePackageFile(#"{"id":"slate","name":"Slate","version":"1","kind":"theme","entry":"config.json"}"#,
                         to: theme.appending(path: "package.json"))
    for configuration in [#"{"widgets":[{"id":"clock","type":"clock","position":"left"}]}"#,
                          #"{"environment":{"PLAYER":"Music"}}"#,
                          #"{"providers":{"load":{"type":"command","command":"uptime"}}}"#,
                          #"{"templates":{"metric":{"type":"script","position":"left","command":"uptime"}}}"#,
                          #"{"profiles":[{"name":"dark","configuration":{"widgetOverrides":{"clock":{"onClick":"uptime"}}}}]}"#] {
        try writePackageFile(configuration, to: theme.appending(path: "config.json"))
        #expect(throws: WidgetPackageError.self) { try store.inspect(theme) }
    }
    try writePackageFile(##"""
    {"tokens":{"text":"#111111"},"defaults":{"foreground":"@token.text"},"bar":{"height":30},
     "groups":{"session":{"style":{"cornerRadius":4}}},
     "profiles":[{"name":"dark","when":{"appearance":"dark"},"configuration":{"tokens":{"text":"#eeeeee"}}}]}
    """##, to: theme.appending(path: "config.json"))
    #expect(try store.install(theme).commands.isEmpty)
    try writePackageFile(#"{"id":"clock","name":"Clock","version":"1","entry":"config.json"}"#, to: widget.appending(path: "package.json"))
    try writePackageFile(#"{"widgets":[{"id":"clock","type":"clock","position":"left"}]}"#, to: widget.appending(path: "config.json"))
    _ = try store.install(widget)
    var loader = ConfigurationLoader()
    for json in [#"{"theme":{"id":"clock","version":"1"}}"#, #"{"packages":[{"id":"slate","version":"1"}]}"#] {
        #expect(throws: WidgetPackageError.self) { try loader.load(directory.appending(path: "config.json"), data: Data(json.utf8)) }
    }
}

@Test func widgetsPackagesRejectCommandsAtAnyDepthAndLoadThroughPackages() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appending(path: "source")
    let store = WidgetPackageStore(directory: directory.appending(path: "packages"))
    try writePackageFile(#"{"id":"monitor","name":"Monitor","version":"1","kind":"widgets","entry":"config.json"}"#,
                         to: source.appending(path: "package.json"))
    for (configuration, message) in [
        (#"{"environment":{"PLAYER":"Music"}}"#, "A widgets package can contain only tokens, defaults, bar, groups, profiles, widgets, templates, popups and providers, not environment."),
        (#"{"widgetOverrides":{"cpu":{"text":"CPU"}}}"#, "A widgets package can contain only tokens, defaults, bar, groups, profiles, widgets, templates, popups and providers, not widgetOverrides."),
        (#"{"widgets":[{"id":"load","type":"script","position":"left","command":"uptime"}]}"#, "A widgets package cannot contain command."),
        (#"{"providers":{"load":{"type":"stream","command":"uptime"}}}"#, "A widgets package cannot contain command."),
        (#"{"templates":{"cpu":{"type":"system","position":"left","actions":{"scrollUp":"uptime"}}}}"#, "A widgets package cannot contain scrollUp."),
        (#"{"popups":{"agenda":{"style":{},"layout":{"type":"text","text":"Join","onClickField":"joinCommand"}}}}"#, "A widgets package cannot contain onClickField."),
        (#"{"widgets":[{"id":"cpu","type":"system","position":"left","environment":{"A":"B"}}]}"#, "A widgets package cannot contain environment."),
        (#"{"profiles":[{"name":"dark","configuration":{"workspaceSource":"yabai"}}]}"#, "A widgets package can contain only tokens, defaults, bar, groups, profiles, widgets, templates, popups and providers, not workspaceSource."),
        (#"{"profiles":[{"name":"dark","configuration":{"widgets":[{"id":"cpu","type":"system","position":"left","onClick":"uptime"}]}}]}"#, "A widgets package cannot contain onClick.")
    ] {
        try writePackageFile(configuration, to: source.appending(path: "config.json"))
        let error = #expect(throws: WidgetPackageError.self) { try store.inspect(source) }
        #expect(error?.localizedDescription == message)
    }
    try writePackageFile(#"""
    {"tokens":{"surface":"#222222"},"providers":{"system":{"type":"system","interval":2}},
     "popups":{"usage":{"style":{},"layout":{"type":"field","field":"text","open":"com.apple.ActivityMonitor"}}},
     "widgets":[{"id":"cpu","type":"system","position":"right","popupName":"usage","style":{"background":"@token.surface"}}]}
    """#, to: source.appending(path: "config.json"))
    #expect(try store.install(source).commands.isEmpty)
    var loader = ConfigurationLoader()
    let root = directory.appending(path: "config.json")
    let configuration = try loader.load(root, data: Data(#"{"packages":[{"id":"monitor","version":"1"}]}"#.utf8))
    #expect(configuration.widgets.map(\.id) == ["cpu"])
    #expect(throws: WidgetPackageError.self) { try loader.load(root, data: Data(#"{"theme":{"id":"monitor","version":"1"}}"#.utf8)) }
}

@Test func manifestsDeclareWhatAPackageNeedsAndKeepTheirScreenshotInside() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appending(path: "source")
    let store = WidgetPackageStore(directory: directory.appending(path: "packages"))
    let manifest = #"""
    {"id":"weather","name":"Weather","version":"1","entry":"config.json","description":"Current conditions.","author":"StableBar",
     "repository":"https://github.com/Seb-GRAF/stablebar-packages","screenshot":"screenshot.png","minimumVersion":"0.6.0",
     "requires":["jq","gh","brew"],"permissions":["location"],"hosts":["wttr.in"]}
    """#
    try writePackageFile(manifest, to: source.appending(path: "package.json"))
    try writePackageFile(#"{"widgets":[]}"#, to: source.appending(path: "config.json"))
    try writePackageFile("image", to: source.appending(path: "screenshot.png"))
    try writePackageFile("image", to: directory.appending(path: "outside.png"))
    let inspection = try store.inspect(source)
    #expect(inspection.manifest.description == "Current conditions.")
    #expect(inspection.manifest.author == "StableBar")
    #expect(inspection.manifest.repository == URL(string: "https://github.com/Seb-GRAF/stablebar-packages"))
    #expect(inspection.manifest.minimumVersion == "0.6.0")
    #expect(inspection.manifest.permissions == [.location])
    #expect(inspection.manifest.hosts == ["wttr.in"])
    #expect(inspection.screenshot?.path == source.appending(path: "screenshot.png").path)
    let tools = directory.appending(path: "bin")
    try writePackageFile("#!/bin/sh\n", to: tools.appending(path: "jq"))
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tools.appending(path: "jq").path)
    try writePackageFile("", to: tools.appending(path: "gh"))
    #expect(inspection.manifest.missingTools(path: "/missing:\(tools.path)") == ["gh", "brew"])
    for (value, replacement) in [("screenshot.png", "../outside.png"), (#"["location"]"#, #"["camera"]"#), ("https://github.com", "http://github.com")] {
        try writePackageFile(manifest.replacingOccurrences(of: value, with: replacement), to: source.appending(path: "package.json"))
        #expect(throws: (any Error).self) { try store.inspect(source) }
    }
}

@Test func packagesThatNeedANewerStableBarFailReviewAndInstall() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appending(path: "source")
    let store = WidgetPackageStore(directory: directory.appending(path: "packages"), appVersion: "0.9.0")
    try writePackageFile(#"{"id":"clock","name":"Clock","version":"1","entry":"config.json","minimumVersion":"0.10.0"}"#,
                         to: source.appending(path: "package.json"))
    try writePackageFile(#"{"widgets":[]}"#, to: source.appending(path: "config.json"))
    let error = #expect(throws: WidgetPackageError.self) { try store.inspect(source) }
    #expect(error?.localizedDescription == "Package clock needs StableBar 0.10.0 or later.")
    #expect(throws: WidgetPackageError.self) { try store.install(source) }
    _ = try WidgetPackageStore(directory: store.directory, appVersion: nil).inspect(source)
    for version in ["0.9.0", "0.8.12"] {
        try writePackageFile(#"{"id":"clock","name":"Clock","version":"1","entry":"config.json","minimumVersion":"\#(version)"}"#,
                             to: source.appending(path: "package.json"))
        _ = try store.inspect(source)
    }
    _ = try store.install(source)
}

@Test func storePackagesInstallFromTheIndexOnlyWhenTheirArchiveMatches() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appending(path: "source")
    let store = WidgetPackageStore(directory: directory.appending(path: "packages"))
    try writePackageFile(#"{"id":"clock","name":"Clock","version":"1","kind":"widgets","entry":"config.json"}"#,
                         to: source.appending(path: "package.json"))
    try writePackageFile(#"{"widgets":[{"id":"clock","type":"clock","position":"right"}]}"#, to: source.appending(path: "config.json"))
    let archive = directory.appending(path: "store/clock-1.tar.gz")
    try FileManager.default.createDirectory(at: archive.deletingLastPathComponent(), withIntermediateDirectories: true)
    _ = try await runCommand("/usr/bin/tar", arguments: ["-czf", archive.path, "-C", source.path, "."])
    let sha256 = SHA256.hash(data: try Data(contentsOf: archive)).map { String(format: "%02x", $0) }.joined()
    let index = directory.appending(path: "store/index.json")
    for (version, checksum, message) in [
        ("1", String(repeating: "0", count: 64), "The archive of package clock does not match the store's checksum."),
        ("2", sha256, "The archive of package clock 2 contains a different id or version.")
    ] {
        try writePackageFile(#"""
        {"packages":[{"id":"clock","name":"Clock","version":"\#(version)","archive":"clock-1.tar.gz","sha256":"\#(checksum)",
          "source":"https://example.com/packages/clock"}]}
        """#, to: index)
        let entry = try await PackageIndex.load(from: index).packages[0]
        let error = await #expect(throws: WidgetPackageError.self) { try await store.download(entry, from: index) }
        #expect(error?.localizedDescription == message)
    }
    try writePackageFile(#"""
    {"packages":[{"id":"agent","name":"Agent","version":"1","kind":"plugin","archive":"agent-1.tar.gz","sha256":"\#(sha256)"},
      {"id":"clock","name":"Clock","version":"1","kind":"widgets","archive":"clock-1.tar.gz","sha256":"\#(sha256)",
      "source":"https://example.com/packages/clock","rating":5}],"updated":"2026-10-16"}
    """#, to: index)
    let packages = try await PackageIndex.load(from: index).packages
    #expect(packages.map(\.id) == ["clock"])
    let installed = try store.install(try await store.download(packages[0], from: index))
    #expect(installed.directory == directory.appending(path: "packages/clock/1"))
    #expect(installed.manifest.kind == .widgets)
}

@Test func updatesListTheCommandsHostsAndPermissionsTheyAdd() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appending(path: "source")
    let store = WidgetPackageStore(directory: directory.appending(path: "packages"))
    var inspections: [WidgetPackageInspection] = []
    for (version, actions, hosts, permissions) in [("1", "{}", #""a.example""#, #""calendars""#),
                                                    ("2", #"{"scrollUp":"echo two"}"#, #""a.example","b.example""#, #""calendars","location""#)] {
        try writePackageFile(#"{"id":"feed","name":"Feed","version":"\#(version)","entry":"config.json","hosts":[\#(hosts)],"permissions":[\#(permissions)]}"#,
                             to: source.appending(path: "package.json"))
        try writePackageFile(#"{"widgets":[{"id":"feed","type":"text","position":"left","text":"Feed","onClick":"echo one","actions":\#(actions)}]}"#,
                             to: source.appending(path: "config.json"))
        inspections.append(try store.install(source))
    }
    #expect(inspections[1].additions(since: inspections[0]) == ["Command: echo two", "Host: b.example", "Permission: Location"])
    #expect(inspections[0].additions(since: inspections[1]).isEmpty)
}

@Test func themeAppliesAfterWidgetPackagesAndBeforeIncludesAndTheRootFile() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let theme = directory.appending(path: "theme")
    let widget = directory.appending(path: "widget")
    let store = WidgetPackageStore(directory: directory.appending(path: "packages"))
    try writePackageFile(#"{"id":"slate","name":"Slate","version":"1","kind":"theme","entry":"config.json"}"#,
                         to: theme.appending(path: "package.json"))
    try writePackageFile(##"""
    {"tokens":{"text":"#111111","textMuted":"#222222","surface":"#444444"},
     "defaults":{"foreground":"@token.text","background":"@token.surface","fontSize":10},
     "bar":{"height":30},
     "profiles":[{"name":"dark","when":{"appearance":"dark"},"configuration":{"tokens":{"text":"#eeeeee"}}}]}
    """##, to: theme.appending(path: "config.json"))
    _ = try store.install(theme)
    try writePackageFile(#"{"id":"status","name":"Status","version":"1","entry":"config.json"}"#, to: widget.appending(path: "package.json"))
    try writePackageFile(##"""
    {"tokens":{"textMuted":"#555555","badge":"#888888","surface":"#777777"},
     "widgets":[{"id":"status","type":"text","position":"left","text":"Ready",
                 "style":{"foreground":"@token.textMuted","background":"@token.badge"}}]}
    """##, to: widget.appending(path: "config.json"))
    _ = try store.install(widget)
    try writePackageFile(##"{"tokens":{"surface":"#666666"}}"##, to: directory.appending(path: "module.json"))
    let root = directory.appending(path: "config.json")
    let json = ##"""
    {"includes":["module.json"],"theme":{"id":"slate","version":"1"},"packages":[{"id":"status","version":"1"}],
     "defaults":{"fontSize":13},
     "widgets":[{"id":"note","type":"text","position":"right","text":"Note","style":{"foreground":"@token.textMuted"}}]}
    """##
    var loader = ConfigurationLoader()
    let light = try loader.load(root, data: Data(json.utf8))
    #expect(light.defaults.foreground == HexColor(0x111111ff))
    #expect(light.widgets[0].style.foreground == HexColor(0x222222ff))
    #expect(light.widgets[0].style.background == HexColor(0x888888ff))
    #expect(light.defaults.background == HexColor(0x666666ff))
    #expect(light.defaults.fontSize == 13)
    #expect(light.bar.height == 30)
    #expect(light.widgets.map(\.id) == ["status", "note"])
    #expect(light.widgets[1].style.foreground == HexColor(0x222222ff))
    let dark = try loader.load(root, data: Data(json.utf8), context: ConfigurationContext(appearance: "dark"))
    #expect(dark.defaults.foreground == HexColor(0xeeeeeeff))
    #expect(loader.activeProfiles == ["dark"])
    let builtIn = try loader.load(root, data: Data(#"{"widgets":[]}"#.utf8))
    #expect(builtIn.defaults.foreground == nil)
    #expect(builtIn.bar.height == 40)
}

private let bundledThemes = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "Resources/themes")

@Test func colorsTakeOneValueOrALightAndDarkPair() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "colors.json")
    var loader = ConfigurationLoader()
    let configuration = try loader.load(url, data: Data(##"""
    {"tokens":{"text":{"light":"#111111","dark":"#eeeeee"},"line":"#333333"},
     "defaults":{"foreground":"@token.text","background":"#22222280","borderColor":{"light":"@token.line","dark":"#444444"}},
     "widgets":[]}
    """##.utf8))
    #expect(configuration.defaults.foreground == HexColor(light: 0x111111ff, dark: 0xeeeeeeff))
    #expect(configuration.defaults.background == HexColor(0x22222280))
    #expect(configuration.defaults.borderColor == HexColor(light: 0x333333ff, dark: 0x444444ff))
    for (color, message) in [
        (##"{"light":"#111111"}"##, "defaults.foreground: Missing property dark."),
        (##"{"light":"#111111","dark":"#222222","tint":"#333333"}"##, "defaults.foreground.tint: Unknown property."),
        (##"{"light":"blue","dark":"#222222"}"##, "defaults.foreground: Use #RRGGBB or #RRGGBBAA for colors.")
    ] {
        let error = #expect(throws: (any Error).self) {
            try loader.load(url, data: Data(#"{"widgets":[],"defaults":{"foreground":\#(color)}}"#.utf8))
        }
        #expect(error.map(errorMessage) == message)
    }
}

@Test func builtInThemeLoadsUnderEveryThemeAndReplacesPackageFallbacks() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let widget = directory.appending(path: "widget")
    try writePackageFile(#"{"id":"status","name":"Status","version":"1","entry":"config.json"}"#, to: widget.appending(path: "package.json"))
    try writePackageFile(##"""
    {"tokens":{"textMuted":"#555555","badge":"#888888"},
     "widgets":[{"id":"status","type":"text","position":"left","text":"Ready",
                 "style":{"foreground":"@token.textMuted","background":"@token.badge"}}]}
    """##, to: widget.appending(path: "config.json"))
    _ = try WidgetPackageStore(directory: directory.appending(path: "packages")).install(widget)
    let root = directory.appending(path: "config.json")
    let widgets = #""packages":[{"id":"status","version":"1"}],"widgets":[{"id":"note","type":"text","position":"right","text":"Note","style":{"foreground":"@token.textMuted"}}]"#
    var loader = ConfigurationLoader()
    loader.themesDirectory = bundledThemes
    let builtIn = try loader.load(root, data: Data("{\(widgets)}".utf8))
    let textMuted = HexColor(light: 0x6e6e73ff, dark: 0xa1a1a6ff)
    #expect(builtIn.defaults.foreground == HexColor(light: 0x1d1d1fff, dark: 0xf5f5f7ff))
    #expect(builtIn.defaults.background == HexColor(light: 0xf8f8faed, dark: 0x242629ee))
    #expect(builtIn.widgets[0].style.foreground == textMuted)
    #expect(builtIn.widgets[0].style.background == HexColor(0x888888ff))
    #expect(builtIn.widgets[1].style.foreground == textMuted)
    let slate = try loader.load(root, data: Data(#"{"theme":{"id":"slate"},\#(widgets)}"#.utf8))
    #expect(slate.defaults.foreground == HexColor(light: 0x1f2329ff, dark: 0xe6e9efff))
    #expect(slate.defaults.cornerRadius == 8)
    #expect(slate.defaults.shadowColor == HexColor(light: 0x00000014, dark: 0x00000040))
    #expect(slate.widgets[1].style.foreground == HexColor(light: 0x5f6773ff, dark: 0x9aa3b0ff))
    let ownText = Data(##"{"theme":{"id":"slate"},"tokens":{"text":"#c2410c"},"widgets":[]}"##.utf8)
    for appearance in ["light", "dark"] {
        #expect(try loader.load(root, data: ownText, context: ConfigurationContext(appearance: appearance)).defaults.foreground == HexColor(0xc2410cff))
    }
    for json in [#"{"theme":{"id":"missing"},"widgets":[]}"#, #"{"packages":[{"id":"status"}],"widgets":[]}"#] {
        #expect(throws: WidgetPackageError.self) { try loader.load(root, data: Data(json.utf8)) }
    }
    loader.themesDirectory = nil
    #expect(throws: WidgetPackageError.self) { try loader.load(root, data: Data(#"{"theme":{"id":"slate"},"widgets":[]}"#.utf8)) }
}

@Test func bundledThemesDefineEverySharedTokenForLightAndDark() throws {
    let store = WidgetPackageStore(directory: bundledThemes)
    let url = FileManager.default.temporaryDirectory.appending(path: "bundled.json")
    var loader = ConfigurationLoader()
    loader.themesDirectory = bundledThemes
    for directory in try FileManager.default.contentsOfDirectory(at: bundledThemes, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
        let manifest = try store.manifest(at: directory)
        #expect(manifest.kind == .theme)
        #expect(manifest.id == directory.lastPathComponent)
        #expect(try store.inspect(directory).commands.isEmpty)
        _ = try loader.load(url, data: Data(#"{"theme":{"id":"\#(manifest.id)"},"widgets":[]}"#.utf8))
        let tokens = try loader.document["tokens"]!.decoded([String: ConfigurationValue].self)
        for name in ["surface", "surfaceRaised", "text", "textMuted", "accent", "track", "hairline", "warning", "critical"] {
            let color = try #require(try tokens[name]?.decoded(HexColor.self), "\(manifest.id).\(name)")
            #expect(color.light != color.dark, "\(manifest.id).\(name)")
        }
    }
}

@Test func barAppearanceDecidesWhichAppearanceProfilesApply() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "appearance.json")
    var loader = ConfigurationLoader()
    let configuration = try loader.load(url, data: Data(#"""
    {"bar":{"appearance":"dark"},"widgets":[],
     "profiles":[{"name":"night","when":{"appearance":"dark"},"configuration":{"bar":{"height":30}}}]}
    """#.utf8), context: ConfigurationContext(appearance: "light"))
    #expect(configuration.bar.appearance == .dark)
    #expect(configuration.bar.height == 30)
    #expect(loader.activeProfiles == ["night"])
    _ = try loader.load(url, data: Data(#"""
    {"tokens":{"mode":"dark"},"bar":{"appearance":"@token.mode"},"widgets":[],
     "profiles":[{"name":"night","when":{"appearance":"dark"},"configuration":{"bar":{"height":30}}}]}
    """#.utf8), context: ConfigurationContext(appearance: "light"))
    #expect(loader.activeProfiles == ["night"])
    let error = #expect(throws: (any Error).self) {
        try loader.load(url, data: Data(#"{"bar":{"appearance":"auto"},"widgets":[]}"#.utf8))
    }
    #expect(error.map(errorMessage) == "bar.appearance: Cannot initialize BarAppearance from invalid String value auto")
}

@Test func colorsThatSetupAndTheStarterWroteNoLongerHideATheme() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let root = directory.appending(path: "config.json")
    let dark = ##""foreground":"#f5f5f7ff","background":"#242629ee","hoverBackground":"#36383cff","borderColor":"#ffffff1f","shadowColor":"#00000040""##
    let light = ##""foreground":"#1d1d1fff","background":"#f8f8faed","hoverBackground":"#ffffffff","borderColor":"#ffffffb3","shadowColor":"#00000014""##
    let automatic = #""foreground":null,"background":null,"hoverBackground":null,"borderColor":null,"shadowColor":null"#
    let changedAfterAutomatic = ##""foreground":"#ff8800ff","background":null,"hoverBackground":null,"borderColor":null,"shadowColor":null"##
    for (defaults, bar, migrated) in [
        ("{\(dark),\"accent\":\"#007aff\",\"fontSize\":13}", ConfigurationValue.object(["height": .number(40), "appearance": .string("dark")]),
         ConfigurationValue.object(["fontSize": .number(13)])),
        ("{\(light)}", .object(["height": .number(40), "appearance": .string("light")]), nil),
        ("{\(automatic),\"accent\":\"#007aff\"}", .object(["height": .number(40)]), nil),
        ("{\(changedAfterAutomatic)}", .object(["height": .number(40)]), .object(["foreground": .string("#ff8800ff")]))
    ] {
        try writePackageFile(#"{"theme":{"id":"slate"},"bar":{"height":40},"defaults":\#(defaults),"widgets":[]}"#, to: root)
        try migrateEarlierColors(root)
        let saved = try JSONDecoder().decode([String: ConfigurationValue].self, from: Data(contentsOf: root))
        #expect(saved["bar"] == bar)
        #expect(saved["defaults"] == migrated)
        var loader = ConfigurationLoader()
        loader.themesDirectory = bundledThemes
        let configuration = try loader.load(root)
        #expect(configuration.defaults.background == HexColor(light: 0xf4f5f7ed, dark: 0x23272eee))
        #expect(configuration.defaults.accent == HexColor(light: 0x3a6ea5ff, dark: 0x5b8ac4ff))
    }
    let handSet = ##"{"bar":{"height":40},"defaults":{"foreground":"#abcdefff","background":"#242629ee","hoverBackground":"#36383cff","borderColor":"#ffffff1f","shadowColor":"#00000040","accent":"#ff8800"},"widgets":[]}"##
    try writePackageFile(handSet, to: root)
    try migrateEarlierColors(root)
    #expect(try String(contentsOf: root, encoding: .utf8) == handSet)
}
