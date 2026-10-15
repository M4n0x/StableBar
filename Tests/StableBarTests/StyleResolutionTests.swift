import Foundation
import Testing
@testable import StableBar

private func style(_ json: String) throws -> WidgetStyle {
    try JSONDecoder().decode(WidgetStyle.self, from: Data(json.utf8))
}

private func output(_ json: String) throws -> ScriptOutput {
    try ScriptOutput.read(Data(json.utf8))
}

@Test func hoverShorthandBecomesTheHoverStateOfItsOwnStyle() throws {
    let decoded = try style(##"{"foreground":"#333333","hoverForeground":"#222222","hoverBackground":"#111111"}"##)
    #expect(decoded.foreground == HexColor(0x333333ff))
    #expect(decoded.states == ["hover": WidgetStyle(foreground: HexColor(0x222222ff), background: HexColor(0x111111ff))])
    #expect(decoded.hoverForeground == HexColor(0x222222ff))
    #expect(decoded.hoverBackground == HexColor(0x111111ff))
    #expect(try style(##"{"foreground":"#333333"}"##).states == nil)
    var loader = ConfigurationLoader()
    loader.themesDirectory = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Resources/themes")
    let builtIn = try loader.load(FileManager.default.temporaryDirectory.appending(path: "built-in.json"), data: Data(#"{"widgets":[]}"#.utf8))
    #expect(builtIn.defaults.hoverBackground == HexColor(light: 0xffffffff, dark: 0x36383cff))
}

@Test func aHoverWithoutABackgroundKeepsTheBackground() throws {
    let plain = try style(##"{"background":"#111111","foreground":"#444444"}"##)
    let hover = StyleStates(hover: true)
    #expect(resolveStyle([plain]).background == HexColor(0x111111ff))
    #expect(resolveStyle([plain], states: hover).background == HexColor(0x111111ff))
    #expect(resolveStyle([plain], states: hover).foreground == HexColor(0x444444ff))
    #expect(ResolvedWidgetStyle(base: plain).style(hovered: true).background == HexColor(0x111111ff))
    let theme = try style(##"{"hoverBackground":"#222222"}"##)
    let own = try style(##"{"background":"#111111","hoverBackground":"#333333","hoverForeground":"#555555"}"##)
    #expect(resolveStyle([theme, plain], states: hover).background == HexColor(0x222222ff))
    #expect(resolveStyle([theme, own], states: hover).background == HexColor(0x333333ff))
    #expect(resolveStyle([theme, own], states: hover).foreground == HexColor(0x555555ff))
    #expect(resolveStyle([theme, own]).foreground == nil)
    let resolution = ResolvedWidgetStyle(base: resolveStyle([theme, plain]))
    #expect(resolution.style(hovered: false).background == HexColor(0x111111ff))
    #expect(resolution.style(hovered: true).background == HexColor(0x222222ff))
    #expect(resolution.base.hoverBackground == HexColor(0x222222ff))
}

@Test func widgetStylesApplyInConfigurationOrderBelowTheWidgetsOwnOutput() throws {
    let configuration = try JSONDecoder().decode(Configuration.self, from: Data(##"""
    {"defaults":{"fontSize":12},"bar":{"style":{"background":"#000000","cornerRadius":2}},"widgets":[
      {"id":"a","type":"script","command":"true","position":"left"},
      {"id":"b","type":"script","command":"true","position":"left"},
      {"id":"c","type":"script","command":"true","position":"right","style":{"foreground":"#999999"}}]}
    """##.utf8))
    var outputs = try [
        "a": output(##"{"text":"A","widgetStyles":{"c":{"foreground":"#ff0000","background":"#ff0000"}},"barStyle":{"background":"#111111","cornerRadius":4}}"##),
        "b": output(##"{"text":"B","widgetStyles":{"c":{"foreground":"#00ff00"}},"barStyle":{"background":"#222222"}}"##)
    ]
    let c = configuration.widgets[2]
    func resolved() -> WidgetStyle {
        resolveStyle(widgetStyleLayers(c, defaults: configuration.defaults, widgets: configuration.widgets, output: { outputs[$0] }))
    }
    #expect(resolved().foreground == HexColor(0x00ff00ff))
    #expect(resolved().background == HexColor(0xff0000ff))
    #expect(resolved().fontSize == 12)
    outputs["c"] = try output(##"{"text":"C","style":{"background":"#0000ff"},"color":"#ffff00"}"##)
    #expect(resolved().background == HexColor(0x0000ffff))
    #expect(resolved().foreground == HexColor(0xffff00ff))
    let bar = resolveStyle(barStyleLayers(configuration.bar.style, widgets: configuration.widgets, output: { outputs[$0] }))
    #expect(bar.background == HexColor(0x222222ff))
    #expect(bar.cornerRadius == 4)
    outputs = [:]
    #expect(resolved().foreground == HexColor(0x999999ff))
}
