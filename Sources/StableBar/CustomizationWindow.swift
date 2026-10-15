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
    }
}

extension WidgetPosition {
    var title: String {
        switch self {
        case .left: "Left"
        case .notchLeft: "Left of notch"
        case .center: "Center"
        case .notchRight: "Right of notch"
        case .right: "Right"
        }
    }
}

private extension WidgetContent {
    var title: String {
        switch self {
        case .spacer: "Spacer"
        case let .provider(name): name.capitalized
        case .workspaces: "Workspaces"
        case .activeApp: "Active app"
        case .clock: "Clock"
        case .text: "Text"
        case .script: "Script"
        }
    }

    var symbol: String {
        switch self {
        case .spacer: "arrow.left.and.right"
        case .provider: "gauge.with.dots.needle.33percent"
        case .workspaces: "rectangle.3.group"
        case .activeApp: "macwindow"
        case .clock: "clock"
        case .text: "textformat"
        case .script: "terminal"
        }
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

    private var widgets: [WidgetConfiguration] { editor.preview.configuration?.widgets ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            preview.padding(16)
            Divider()
            HSplitView {
                sidebar.frame(minWidth: 210, maxWidth: 280)
                Group {
                    if let widget = widgets.first(where: { $0.id == editor.selectedID }) {
                        inspector(widget)
                    } else {
                        ContentUnavailableView("Select a widget", systemImage: "sidebar.left",
                                               description: Text("Choose a widget to change how it looks and where it sits."))
                    }
                }
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            }
            if let error = editor.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.red.opacity(0.1))
            }
            Divider()
            footer
        }
        .onChange(of: store.effectiveDocument) { editor.refresh() }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PREVIEW").font(.system(size: 10, weight: .semibold)).tracking(1.4)
                Spacer()
                Text("Changes show here before you save").font(.caption)
            }
            .foregroundStyle(.secondary)
            if let screen = NSScreen.main {
                let actual = BarDisplay(screen: screen)
                let display = BarDisplay(id: actual.id, isBuiltIn: actual.isBuiltIn, isMain: actual.isMain, notch: nil)
                BarView(store: editor.preview, display: display)
                    .frame(height: editor.preview.configuration?.bar.height ?? 40)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: .underPageBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Preview of your bar")
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $editor.selectedID) {
                ForEach(WidgetPosition.allCases, id: \.self) { position in
                    let section = widgets.filter { $0.position == position }
                    if !section.isEmpty {
                        Section(position.title) {
                            ForEach(section) { widget in
                                Label {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(widget.id).lineLimit(1)
                                        Text(widget.content.title).font(.caption).foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: widget.content.symbol)
                                }
                                .opacity(widget.enabled ? 1 : 0.45)
                                .padding(.vertical, 2)
                                .tag(widget.id)
                            }
                            .onMove { offsets, destination in
                                var ids = section.map(\.id)
                                ids.move(fromOffsets: offsets, toOffset: destination)
                                var moved = ids.makeIterator()
                                editor.change(ConfigurationEdit(action: .reorder,
                                    ids: widgets.map { $0.position == position ? moved.next()! : $0.id }))
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            Divider()
            HStack(spacing: 0) {
                Button {
                    let id = "widget-" + UUID().uuidString.prefix(8).lowercased()
                    editor.change(ConfigurationEdit(action: .add, properties: ["id": .string(id),
                        "type": .string("text"), "position": .string("left"), "text": .string("New widget")]))
                    editor.selectedID = id
                } label: {
                    Image(systemName: "plus").frame(width: 28, height: 24)
                }
                .help("Add a text widget")
                Divider().frame(height: 16)
                Button {
                    editor.change(ConfigurationEdit(action: .remove, id: editor.selectedID!))
                    editor.selectedID = editor.preview.configuration?.widgets.first?.id
                } label: {
                    Image(systemName: "minus").frame(width: 28, height: 24)
                }
                .help("Remove the selected widget")
                .disabled(editor.selectedID == nil)
                Spacer()
                Text("Drag to reorder").font(.caption).foregroundStyle(.tertiary).padding(.trailing, 10)
            }
            .buttonStyle(.borderless)
            .padding(4)
        }
    }

    private func inspector(_ widget: WidgetConfiguration) -> some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: widget.content.symbol)
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 40, height: 40)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(widget.id).font(.title3.weight(.semibold))
                        Text(widget.content.title + " widget").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Enabled", isOn: Binding(get: {
                        if case let .bool(value) = editor.selected["enabled"] { value } else { true }
                    }, set: { editor.set(["enabled": .bool($0)]) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help("Show this widget in the bar")
                }
            }
            Section("Content") {
                Picker("Position", selection: string("position", fallback: "left")) {
                    ForEach(WidgetPosition.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                LabeledContent("Icon") {
                    HStack {
                        TextField("Icon", text: string("icon"), prompt: Text("SF Symbol name"))
                            .labelsHidden()
                        Image(systemName: string("icon").wrappedValue)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                    }
                }
                if editor.selected["type"] == .string("text") { TextField("Text", text: string("text")) }
                if editor.selected["type"] == .string("clock") {
                    TextField("Date format", text: string("format", fallback: "EEE d MMM HH:mm"))
                }
            }
            Section("Appearance") {
                ColorPicker("Text color", selection: color("foreground", fallback: "#1d1d1fff"))
                ColorPicker("Background", selection: color("background", fallback: "#f8f8faed"))
                styleNumber("Font size", key: "fontSize", fallback: 12, unit: "pt")
                styleNumber("Horizontal padding", key: "paddingHorizontal", fallback: 10, unit: "pt")
                styleNumber("Corner radius", key: "cornerRadius", fallback: 14, unit: "pt")
            }
            Section {
                DisclosureGroup("Advanced properties") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Merge any widget properties as JSON. Templates and included files stay intact.")
                            .font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $advanced)
                            .font(.system(.body, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .frame(height: 120)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                        HStack {
                            Spacer()
                            Button("Preview properties") {
                                do {
                                    let properties = try JSONDecoder().decode([String: ConfigurationValue].self, from: Data(advanced.utf8))
                                    editor.change(ConfigurationEdit(action: .set, id: editor.selectedID!, properties: properties))
                                } catch { editor.error = error.localizedDescription }
                            }
                        }
                    }
                    .padding(.top, 6)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            ControlGroup {
                Button("Undo", systemImage: "arrow.uturn.backward", action: editor.undo)
                    .keyboardShortcut("z").disabled(editor.undoSteps.isEmpty).help("Undo")
                Button("Redo", systemImage: "arrow.uturn.forward", action: editor.redo)
                    .keyboardShortcut("z", modifiers: [.command, .shift]).disabled(editor.redoSteps.isEmpty).help("Redo")
            }
            .labelStyle(.iconOnly)
            .fixedSize()
            Group {
                if !editor.edits.isEmpty {
                    Text("^[\(editor.edits.count) unsaved change](inflect: true)")
                } else if !store.sessionEdits.isEmpty {
                    Text("Live edits not saved yet")
                } else {
                    Text("All changes saved")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            Spacer()
            Button("Discard", action: editor.discard).disabled(editor.edits.isEmpty)
            Button("Apply and Save", action: editor.apply)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s")
                .disabled(editor.error != nil || (editor.edits.isEmpty && store.sessionEdits.isEmpty))
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func string(_ key: String, fallback: String = "") -> Binding<String> {
        Binding(get: { if case let .string(value) = editor.selected[key] { value } else { fallback } },
                set: { editor.set([key: .string($0)]) })
    }

    private func styleNumber(_ title: String, key: String, fallback: Double, unit: String) -> some View {
        let displayed: Double
        if case let .number(value) = editor.selectedStyle[key] { displayed = value }
        else { displayed = fallback }
        let value = Binding(get: { displayed }, set: {
            if editor.error != nil || $0 != displayed { editor.set(["style": .object([key: .number($0)])]) }
        })
        return LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, value: value, format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 52)
                Text(unit).foregroundStyle(.secondary)
                Stepper(title, value: value, in: 0...200).labelsHidden()
            }
        }
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
