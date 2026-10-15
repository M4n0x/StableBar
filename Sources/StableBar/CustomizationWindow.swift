import AppKit
import SwiftUI

@MainActor
final class CustomizationWindow: NSObject, NSWindowDelegate {
    private weak var store: BarStore?
    private var window: NSWindow?

    func show(store: BarStore) {
        self.store = store
        store.setInspectorOpen(true)
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 740),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Customize StableBar"
            window.delegate = self
            window.minSize = NSSize(width: 800, height: 580)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: CustomizationView(store: store))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window!.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { store?.setInspectorOpen(false) }
}

private struct CustomizationView: View {
    let store: BarStore

    var body: some View {
        TabView {
            ConfigurationEditorView(store: store).tabItem { Label("Editor", systemImage: "slider.horizontal.3") }
            InspectorView(store: store).tabItem { Label("Inspector", systemImage: "stethoscope") }
            PackagesView(store: store).tabItem { Label("Packages", systemImage: "shippingbox") }
        }
        .padding(12)
    }
}

private struct ConfigurationEditorView: View {
    let store: BarStore
    @State private var editor: ConfigurationEditor
    @State private var advanced = "{}"

    init(store: BarStore) {
        self.store = store
        _editor = State(initialValue: ConfigurationEditor(store: store))
    }

    var body: some View {
        VStack(spacing: 12) {
            if let screen = NSScreen.main {
                let actual = BarDisplay(screen: screen)
                let display = BarDisplay(id: actual.id, isBuiltIn: actual.isBuiltIn, isMain: actual.isMain, notch: nil)
                BarView(store: editor.preview, display: display)
                    .frame(height: max(editor.preview.configuration?.bar.height ?? 40, 60))
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    .allowsHitTesting(false)
            }
            HSplitView {
                VStack(alignment: .leading) {
                    Text("Widgets · drag to reorder").font(.headline)
                    List(selection: $editor.selectedID) {
                        ForEach(editor.preview.configuration?.widgets ?? []) { widget in
                            HStack {
                                Text(widget.id)
                                Spacer()
                                Text(widget.position.rawValue).foregroundStyle(.secondary)
                            }.tag(widget.id)
                        }
                        .onMove { offsets, destination in
                            var ids = editor.preview.configuration!.widgets.map(\.id)
                            ids.move(fromOffsets: offsets, toOffset: destination)
                            editor.change(ConfigurationEdit(action: .reorder, ids: ids))
                        }
                    }
                    HStack {
                        Button("Add text widget", systemImage: "plus") {
                            let id = "widget-" + UUID().uuidString.prefix(8).lowercased()
                            editor.change(ConfigurationEdit(action: .add, properties: ["id": .string(id),
                                "type": .string("text"), "position": .string("left"), "text": .string("New widget")]))
                            editor.selectedID = id
                        }
                        Button("Remove", systemImage: "minus") {
                            editor.change(ConfigurationEdit(action: .remove, id: editor.selectedID!))
                            editor.selectedID = editor.preview.configuration?.widgets.first?.id
                        }.disabled(editor.selectedID == nil)
                    }.controlSize(.small)
                }.frame(minWidth: 260, idealWidth: 300)
                ScrollView {
                    if editor.selectedID != nil {
                        Form {
                            Text(editor.selectedID!).font(.title2)
                            Picker("Position", selection: string("position", fallback: "left")) {
                                ForEach(["left", "notchLeft", "center", "notchRight", "right"], id: \.self) { Text($0) }
                            }
                            Toggle("Enabled", isOn: Binding(get: {
                                if case let .bool(value) = editor.selected["enabled"] { value } else { true }
                            }, set: { editor.set(["enabled": .bool($0)]) }))
                            TextField("Icon", text: string("icon"))
                            if editor.selected["type"] == .string("text") { TextField("Text", text: string("text")) }
                            if editor.selected["type"] == .string("clock") { TextField("Date format", text: string("format", fallback: "EEE d MMM HH:mm")) }
                            ColorPicker("Text color", selection: color("foreground", fallback: "#1d1d1fff"))
                            ColorPicker("Background", selection: color("background", fallback: "#f8f8faed"))
                            styleNumber("Font size", key: "fontSize", fallback: 12)
                            styleNumber("Horizontal padding", key: "paddingHorizontal", fallback: 10)
                            styleNumber("Corner radius", key: "cornerRadius", fallback: 14)
                            Text("Advanced properties").font(.headline)
                            Text("Merge any widget properties as JSON. Templates and included files stay intact.")
                                .font(.caption).foregroundStyle(.secondary)
                            TextEditor(text: $advanced).font(.system(.body, design: .monospaced)).frame(height: 130)
                            Button("Preview properties") {
                                do {
                                    let properties = try JSONDecoder().decode([String: ConfigurationValue].self, from: Data(advanced.utf8))
                                    editor.change(ConfigurationEdit(action: .set, id: editor.selectedID!, properties: properties))
                                } catch { editor.error = error.localizedDescription }
                            }
                        }.padding()
                    } else { ContentUnavailableView("Select a widget", systemImage: "sidebar.left") }
                }.frame(minWidth: 400)
            }
            if let error = editor.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("Undo", action: editor.undo).keyboardShortcut("z").disabled(editor.undoSteps.isEmpty)
                Button("Redo", action: editor.redo).keyboardShortcut("z", modifiers: [.command, .shift]).disabled(editor.redoSteps.isEmpty)
                Spacer()
                Text("\(editor.edits.count) preview changes").foregroundStyle(.secondary)
                Button("Discard", action: editor.discard).disabled(editor.edits.isEmpty)
                Button("Apply and save", action: editor.apply).buttonStyle(.borderedProminent)
                    .disabled(editor.error != nil || (editor.edits.isEmpty && store.sessionEdits.isEmpty))
            }
        }
        .onChange(of: store.effectiveDocument) { editor.refresh() }
    }

    private func string(_ key: String, fallback: String = "") -> Binding<String> {
        Binding(get: { if case let .string(value) = editor.selected[key] { value } else { fallback } },
                set: { editor.set([key: .string($0)]) })
    }

    private func styleNumber(_ title: String, key: String, fallback: Double) -> some View {
        let displayed: Double
        if case let .number(value) = editor.selectedStyle[key] { displayed = value }
        else { displayed = fallback }
        return TextField(title, value: Binding(get: { displayed }, set: {
            if editor.error != nil || $0 != displayed { editor.set(["style": .object([key: .number($0)])]) }
        }), format: .number)
    }

    private func color(_ key: String, fallback: String) -> Binding<Color> {
        Binding(get: {
            let value: ConfigurationValue
            if let configured = editor.selectedStyle[key] { value = configured }
            else { value = .string(fallback) }
            return (try? value.decoded(HexColor.self))?.color ?? .clear
        }, set: {
            let color = NSColor($0).usingColorSpace(.sRGB)!
            let hex = String(format: "#%02x%02x%02x%02x", Int((color.redComponent * 255).rounded()),
                             Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()),
                             Int((color.alphaComponent * 255).rounded()))
            editor.set(["style": .object([key: .string(hex)])])
        })
    }
}
