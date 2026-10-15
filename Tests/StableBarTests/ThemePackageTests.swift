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
    #expect(loader.origins["widgets.status.main.style.fontSize"]?.contains("template base") == true)
    #expect(loader.origins["widgets.status.main.style.background"]?.contains("widget override") == true)
    #expect(loader.origins["widgets.status.main.style.background"]?.contains("token foreground") == true)
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

@Test func customizationOverridesActiveProfilesAndReportsItsSource() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "customization.json")
    let data = Data(#"""
    {"widgets":[{"id":"clock","type":"clock","position":"left"}],
     "profiles":[{"name":"small","when":{"displayCount":1},"configuration":{
       "bar":{"height":30},"defaults":{"fontSize":10},"widgetOverrides":{"clock":{"position":"right"}}}}],
     "customization":{"bar":{"height":48},"defaults":{"fontSize":16},"widgetOverrides":{"clock":{"position":"center"}}}}
    """#.utf8)
    var loader = ConfigurationLoader()
    let configuration = try loader.load(url, data: data)
    #expect(loader.activeProfiles == ["small"])
    #expect(configuration.bar.height == 48)
    #expect(configuration.defaults.fontSize == 16)
    #expect(configuration.widgets[0].position == .center)
    #expect(loader.document["customization"] == nil)
    #expect(loader.origins["widgets.clock.position"]?.contains("customization") == true)
    #expect(loader.origins["bar.height"]?.contains("customization") == true)
}

@Test func customizationForInactiveProfileWidgetsStaysDormant() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "dormant.json")
    let json = #"""
    {"widgets":[{"id":"clock","type":"clock","position":"left"}],
     "profiles":[{"name":"desktop","when":{"externalDisplay":true},"configuration":{
       "widgets":[{"id":"extra","type":"text","position":"right","text":"Desktop"}]}}],
     "customization":{"widgetOverrides":{"extra":{"text":"Customized"}},"widgetOrder":["extra","clock"]}}
    """#
    var loader = ConfigurationLoader()
    let laptop = try loader.load(url, data: Data(json.utf8))
    #expect(laptop.widgets.map(\.id) == ["clock"])
    let desktop = try loader.load(url, data: Data(json.utf8), context: ConfigurationContext(externalDisplay: true))
    #expect(desktop.widgets.map(\.id) == ["extra", "clock"])
    #expect(desktop.widgets[0].content == .text("Customized"))
    #expect(throws: ConfigurationCompositionError.self) {
        try loader.load(url, data: Data(json.replacingOccurrences(of: #""customization":{"widgetOverrides"#,
                                                                 with: #""widgetOverrides":{"missing":{}},"customization":{"widgetOverrides"#).utf8))
    }
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
    #expect(loader.origins["widgets.script.style.fontSize"]?.contains("token style") == true)
}

@Test func removalsAndOrderingPreserveImportedDefinitions() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "order.json")
    var loader = ConfigurationLoader()
    let json = #"""
    {"widgets":[{"id":"a","type":"clock","position":"left"},{"id":"b","type":"clock","position":"left"},
                {"id":"c","type":"clock","position":"right"}],
     "removedWidgets":["b"],"widgetOverrides":{"b":{"id":"ignored"}},"widgetOrder":["c"]}
    """#
    #expect(try loader.load(url, data: Data(json.utf8)).widgets.map(\.id) == ["c", "a"])
    #expect(loader.document["removedWidgets"] == nil)
    #expect(loader.document["widgetOrder"] == nil)
    for order in [#"["c","c"]"#, #"["b"]"#] {
        #expect(throws: ConfigurationCompositionError.self) {
            try loader.load(url, data: Data(json.replacingOccurrences(of: #""widgetOrder":["c"]"#, with: "\"widgetOrder\":\(order)").utf8))
        }
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
