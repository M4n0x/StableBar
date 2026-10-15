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

private func workspace(_ json: String) throws -> WorkspaceConfiguration {
    try JSONDecoder().decode(WorkspaceConfiguration.self, from: Data(json.utf8))
}

@Test func workspaceCellsTakeOneStateInTodaysPriority() {
    let apps = [WorkspaceApp(workspace: "1", name: "Finder", bundleID: "com.apple.finder")]
    #expect(WorkspaceState(Workspace(name: "1", isFocused: true, isVisible: true, monitor: 1)) == .focused)
    #expect(WorkspaceState(Workspace(name: "1", isFocused: false, isVisible: true, monitor: 1)) == .visible)
    #expect(WorkspaceState(Workspace(name: "1", isFocused: false, isVisible: false, monitor: 1)) == .empty)
    #expect(WorkspaceState(Workspace(name: "1", isFocused: false, isVisible: false, monitor: 1, apps: apps)) == nil)
}

@Test func workspaceShorthandStylesResolveLikeBefore() throws {
    let configuration = try workspace(##"""
    {"style":{"foreground":"#111111","hoverForeground":"#222222","paddingHorizontal":5},
     "focusedStyle":{"foreground":"#333333","background":"#444444"},
     "visibleStyle":{"borderColor":"#555555","hoverForeground":"#666666"},
     "emptyStyle":{"foreground":"#777777"},
     "indicatorStyle":{"height":3,"background":"#888888"},
     "appStyle":{"foreground":"#999999","width":12},"focusedAppStyle":{"foreground":"#aaaaaa"},"visibleAppStyle":{"fontSize":10}}
    """##)
    let focused = configuration.cellStyle(.focused)
    #expect(focused.resting.foreground == HexColor(0x333333ff))
    #expect(focused.resting.background == HexColor(0x444444ff))
    #expect(focused.resting.paddingHorizontal == 5)
    #expect(focused.label(hovered: true).foreground == HexColor(0x222222ff))
    #expect(focused.label(hovered: true).background == HexColor(0x444444ff))
    let visible = configuration.cellStyle(.visible)
    #expect(visible.resting.borderColor == HexColor(0x555555ff))
    #expect(visible.resting.foreground == HexColor(0x111111ff))
    #expect(visible.label(hovered: true).foreground == HexColor(0x666666ff))
    #expect(configuration.cellStyle(.empty).resting.foreground == HexColor(0x777777ff))
    #expect(configuration.cellStyle(nil).resting.foreground == HexColor(0x111111ff))
    #expect(configuration.cellStyle(nil).label(hovered: true).foreground == HexColor(0x222222ff))
    #expect(focused.underline.height == 3)
    #expect(focused.underline.background == HexColor(0x888888ff))
    #expect(focused.glyph(hovered: false).foreground == HexColor(0xaaaaaaff))
    #expect(focused.glyph(hovered: false).width == 12)
    #expect(visible.glyph(hovered: false).fontSize == 10)
    #expect(visible.glyph(hovered: false).foreground == HexColor(0x999999ff))
    #expect(configuration.cellStyle(.empty).glyph(hovered: false).foreground == HexColor(0x999999ff))
}

@Test func blocksInheritTextStylesButKeepTheirOwnBox() throws {
    let block = try JSONDecoder().decode(PopupBlock.self, from: Data(##"""
    {"type":"field","field":"text","styleField":"tone","style":{"background":"#111111","paddingHorizontal":4}}
    """##.utf8))
    let inherited = try style(##"{"foreground":"#222222","hoverForeground":"#333333","hoverBackground":"#444444","fontSize":13}"##)
    let named = ["warm": try style(##"{"foreground":"#555555"}"##)]
    let resting = block.resolvedStyle(inherited: inherited, styles: named, fields: ["tone": "warm"], states: StyleStates())
    #expect(resting.text.foreground == HexColor(0x555555ff))
    #expect(resting.text.fontSize == 13)
    #expect(resting.box.background == HexColor(0x111111ff))
    #expect(resting.box.paddingHorizontal == 4)
    #expect(resting.box.fontSize == nil)
    #expect(resting.inherited == resting.text)
    let hovered = block.resolvedStyle(inherited: inherited, styles: named, fields: ["tone": "warm"], states: StyleStates(hover: true))
    #expect(hovered.text.foreground == HexColor(0x333333ff))
    #expect(hovered.box.background == HexColor(0x111111ff))
    #expect(hovered.inherited == resting.inherited)
    let ownHover = try JSONDecoder().decode(PopupBlock.self, from: Data(##"{"type":"divider","style":{"hoverBackground":"#666666"}}"##.utf8))
    #expect(ownHover.resolvedStyle(inherited: inherited, styles: [:], fields: [:], states: StyleStates(hover: true)).box.background
        == HexColor(0x666666ff))
    #expect(block.resolvedStyle(inherited: inherited, styles: named, fields: [:], states: StyleStates()).text.foreground
        == HexColor(0x222222ff))
}

@Test func namedOutputStylesWinOverTheBlocksOwnStyle() throws {
    let block = try JSONDecoder().decode(PopupBlock.self, from: Data(##"""
    {"type":"divider","styleSource":"warm","style":{"foreground":"#111111","background":"#222222","paddingHorizontal":4}}
    """##.utf8))
    let named = ["warm": try style(##"{"foreground":"#555555","background":"#666666"}"##)]
    let resolved = block.resolvedStyle(inherited: WidgetStyle(), styles: named, fields: [:], states: StyleStates())
    #expect(resolved.text.foreground == HexColor(0x555555ff))
    #expect(resolved.box.background == HexColor(0x666666ff))
    #expect(resolved.box.paddingHorizontal == 4)
    #expect(block.resolvedStyle(inherited: WidgetStyle(), styles: [:], fields: [:], states: StyleStates()).box.background
        == HexColor(0x222222ff))
}

@Test func hoveringACellRestylesItsAppGlyphsButNotItsIndicators() throws {
    let configuration = try workspace(##"""
    {"focusedStyle":{"background":"#444444","hoverBackground":"#555555"},
     "indicatorStyle":{"background":"#888888","hoverBackground":"#777777"},
     "appStyle":{"foreground":"#999999","hoverForeground":"#aaaaaa"},"focusedAppStyle":{"fontSize":10,"hoverForeground":"#bbbbbb"}}
    """##)
    let focused = configuration.cellStyle(.focused)
    let visible = configuration.cellStyle(.visible)
    #expect(focused.glyph(hovered: false).foreground == HexColor(0x999999ff))
    #expect(focused.glyph(hovered: true).foreground == HexColor(0xbbbbbbff))
    #expect(focused.glyph(hovered: true).fontSize == 10)
    #expect(visible.glyph(hovered: false).foreground == HexColor(0x999999ff))
    #expect(visible.glyph(hovered: true).foreground == HexColor(0xaaaaaaff))
    #expect(focused.resting.background == HexColor(0x444444ff))
    #expect(focused.underline.background == HexColor(0x888888ff))
}
