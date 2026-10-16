import AppKit
import Foundation
import Observation
import SwiftUI
import Testing
@testable import StableBar

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(json.utf8))
}

/// `content` inside the box a bar widget draws around it.
@MainActor private func boxed(_ content: some View, _ appearance: WidgetAppearance) -> some View {
    content
        .font(appearance.font)
        .foregroundStyle(appearance.foreground)
        .padding(.horizontal, appearance.paddingHorizontal)
        .padding(.vertical, appearance.paddingVertical)
        .background(appearance.background, in: RoundedRectangle(cornerRadius: appearance.cornerRadius))
}

/// A view drawn at 2× in 8-bit sRGB.
private struct Drawing {
    let width: Int
    let height: Int
    let rgba: [UInt8]

    /// The largest difference of one color channel between this drawing and `other`. Drawings of
    /// different sizes differ completely.
    func difference(from other: Drawing) -> Int {
        guard width == other.width, height == other.height else { return 255 }
        return zip(rgba, other.rgba).reduce(0) { max($0, abs(Int($1.0) - Int($1.1))) }
    }
}

/// How far a color channel may differ between two drawings that should match. A process draws its
/// first few images one step differently on some antialiased pixels than later ones, and under load
/// that change can come between any two drawings. Real differences are far larger.
private let tolerance = 1

/// `content` drawn at 2×, after one drawing that is discarded to warm up the renderer. A renderer
/// keeps the image it drew, so each drawing has its own.
@MainActor private func draw(_ content: some View) throws -> Drawing {
    func render() -> CGImage? {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        return renderer.cgImage
    }
    _ = render()
    let image = try #require(render())
    let context = try #require(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                         bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let data = try #require(context.data)
    return Drawing(width: image.width, height: image.height,
                   rgba: Array(UnsafeRawBufferPointer(start: data, count: image.width * image.height * 4)))
}

@Test @MainActor func defaultLayoutsDrawExactlyLikeBuiltInWidgets() throws {
    let date = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 9, minute: 41)))
    let cases: [(widget: String, output: String?, frontmost: NSRunningApplication?)] = [
        (#"{"id":"w","type":"text","text":"Ready 12%","icon":"bolt","position":"left"}"#, nil, nil),
        (#"{"id":"w","type":"text","text":"Ready","icon":"","position":"left"}"#, nil, nil),
        (#"{"id":"w","type":"text","text":"","icon":"apple.logo","position":"left"}"#, nil, nil),
        (#"{"id":"w","type":"text","text":"Ready","position":"left"}"#, nil, nil),
        (#"{"id":"w","type":"clock","format":"EEE d MMM  HH:mm","icon":"clock","position":"right"}"#, nil, nil),
        (#"{"id":"w","type":"activeApp","position":"left"}"#, nil, .current),
        (#"{"id":"w","type":"activeApp","position":"left"}"#, nil, nil),
        (#"{"id":"w","type":"script","command":"true","icon":"bolt","position":"right"}"#, #"{"text":"Busy 3","icon":"hammer"}"#, nil),
        (#"{"id":"w","type":"script","command":"true","icon":"cpu","position":"right"}"#, #"{"text":"12%","value":0.12}"#, nil),
        (#"{"id":"w","type":"script","command":"true","position":"right"}"#, #"{"text":"","value":0.5}"#, nil),
        (#"{"id":"w","type":"script","command":"true","icon":"speaker.wave.2","position":"right"}"#, #"{"text":""}"#, nil),
        (#"{"id":"w","type":"battery","position":"right"}"#, #"{"text":"85%","icon":"battery.100percent","value":0.85}"#, nil)
    ]
    let styles = try [
        decode(WidgetStyle.self, "{}"),
        decode(WidgetStyle.self, ##"""
        {"foreground":"#ff8800","accent":"#00aa66","fontName":"Menlo","fontSize":15,"fontWeight":"bold","iconSize":16,"spacing":9,
         "states":{"hover":{"foreground":"#ffffff","fontWeight":"light","spacing":3},"open":{"accent":"#3366ff","iconSize":11}}}
        """##)
    ]
    for item in cases {
        let widget = try decode(WidgetConfiguration.self, item.widget)
        let store = BarStore(configurationURL: FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json"))
        store.activeApp = item.frontmost
        if let json = item.output {
            let script = ScriptWidget()
            script.output = try ScriptOutput.read(Data(json.utf8))
            script.samples = [0.1, 0.6, 0.35, 0.8, 0.12]
            store.scripts[widget.id] = script
        }
        let script = store.scripts[widget.id]
        for (index, style) in styles.enumerated() {
            let resolution = ResolvedWidgetStyle(base: resolveStyle([style, widget.style]))
            for (hovered, open) in [(false, false), (true, true)] {
                let appearance = WidgetAppearance(resolution.style(hovered: hovered, open: open), defaults: WidgetStyle())
                let builtIn = BuiltInLabel(content: widget.content, label: store.label(for: widget, date: date),
                                           appIcon: widget.content == .activeApp ? store.activeApp?.icon : nil,
                                           samples: script?.output.value == nil ? nil : script?.samples, appearance: appearance)
                let blocks = WidgetBlocks(widget: widget, store: store,
                                          style: resolution.layoutStyle(configured: false, hovered: hovered, open: open),
                                          date: date, runAction: { _, _ in })
                let expected = try draw(boxed(builtIn, appearance))
                let drawn = try draw(boxed(blocks, appearance))
                let name = "\(item.widget) with style \(index), hovered and open: \(hovered)"
                #expect(Double(expected.width) / 2 > appearance.paddingHorizontal * 2, "\(name) draws something")
                #expect(drawn.width == expected.width && drawn.height == expected.height, "\(name)")
                #expect(drawn.difference(from: expected) <= tolerance, "\(name)")
            }
        }
    }
}

@Test @MainActor func hiddenBlocksAddNoSpacing() throws {
    for type in ["row", "column"] {
        let shown = try decode(PopupBlock.self, #"{"type":"\#(type)","children":[{"type":"text","text":"A"},{"type":"text","text":"B"}]}"#)
        let hidden = try decode(PopupBlock.self, #"""
        {"type":"\#(type)","children":[{"type":"text","text":"A"},{"type":"field","field":"empty","hideWhenEmpty":"empty"},{"type":"text","text":"B"}]}
        """#)
        let context = BlockContext(fillsWidth: false, open: { _ in }, runAction: { _, _ in })
        let expected = try draw(PopupBlockView(block: shown, inheritedStyle: WidgetStyle(), fields: [:], context: context))
        let drawn = try draw(PopupBlockView(block: hidden, inheritedStyle: WidgetStyle(), fields: [:], context: context))
        #expect(drawn.width == expected.width && drawn.height == expected.height, "\(type)")
        #expect(drawn.difference(from: expected) <= tolerance, "\(type)")
    }
}

@Test func defaultLayoutsDrawTheWidgetsHoverAndOpenStylesWhileConfiguredLayoutsKeepTheirOwnHover() throws {
    let resolution = ResolvedWidgetStyle(base: try decode(WidgetStyle.self, ##"""
    {"foreground":"#111111","states":{"hover":{"fontWeight":"bold","foreground":"#222222"},"open":{"foreground":"#333333"}}}
    """##), state: "warning")
    let byDefault = resolution.layoutStyle(configured: false, hovered: true, open: true)
    #expect(byDefault.inherited == resolution.style(hovered: true, open: true))
    #expect(byDefault.inherited.fontWeight == "bold")
    #expect(byDefault.inherited.foreground == HexColor(0x333333ff))
    #expect(byDefault.states == StyleStates())
    #expect(!byDefault.tracksHover)
    let configured = resolution.layoutStyle(configured: true, hovered: true, open: true)
    #expect(configured.inherited == resolution.base)
    #expect(configured.states == StyleStates(data: "warning", open: true))
    #expect(configured.tracksHover)
    let script = try decode(WidgetConfiguration.self, #"{"id":"w","type":"script","command":"true","position":"right"}"#)
    #expect(script.defaultLayout(WidgetLabel(text: "…", icon: nil, fields: [:]), output: nil, appIcon: false) == nil)
    let spaces = try decode(WidgetConfiguration.self, #"{"id":"w","type":"workspaces","position":"left"}"#)
    #expect(spaces.defaultLayout(WidgetLabel(text: "", icon: nil, fields: [:]), output: nil, appIcon: false) == nil)
}

@Test @MainActor func onlyActiveAppBlocksRedrawWhenTheFrontmostAppChanges() async throws {
    let store = BarStore(configurationURL: FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json"))
    let note = try decode(WidgetConfiguration.self, #"{"id":"note","type":"text","text":"Ready","position":"left"}"#)
    let app = try decode(WidgetConfiguration.self, #"{"id":"app","type":"activeApp","position":"left"}"#)
    let style = ResolvedWidgetStyle(base: WidgetStyle()).layoutStyle(configured: false, hovered: false, open: false)
    await confirmation("The active app redraws", expectedCount: 1) { redrawn in
        await confirmation("The text widget stays valid", expectedCount: 0) { invalidated in
            withObservationTracking { _ = WidgetBlocks(widget: app, store: store, style: style, runAction: { _, _ in }).body } onChange: { redrawn() }
            withObservationTracking { _ = WidgetBlocks(widget: note, store: store, style: style, runAction: { _, _ in }).body } onChange: { invalidated() }
            store.activeApp = NSRunningApplication.current
        }
    }
}
