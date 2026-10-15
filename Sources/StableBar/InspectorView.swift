import SwiftUI

struct InspectorView: View {
    let store: BarStore
    @State private var selectedID = ""
    @State private var event = "manual"
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("Widget", selection: $selectedID) {
                    Text("All widgets").tag("")
                    ForEach(store.configuration?.widgets ?? []) { Text($0.id).tag($0.id) }
                }
                .fixedSize()
                Button("Run Now", systemImage: "play.fill") { store.scripts[selectedID]?.refresh(ScriptEvent(sender: "manual")) }
                    .disabled(store.scripts[selectedID] == nil)
                    .help("Run this widget’s script now")
                if let widget = store.configuration?.widgets.first(where: { $0.id == selectedID }), let action = store.scripts[selectedID]?.output.onClick ?? widget.onClick {
                    Button("Run Click Action", systemImage: "cursorarrow.click") { store.runAction(action, widget: widget) }
                        .help(action)
                }
                Spacer()
                Label(store.activeProfiles.isEmpty ? "base" : store.activeProfiles.joined(separator: ", "), systemImage: "person.crop.square")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .help("Active profiles")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()
            HStack(spacing: 8) {
                TextField("Event name", text: $event, prompt: Text("Event name"))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                    .onSubmit { store.refreshScripts(for: event) }
                Button("Send Event") { store.refreshScripts(for: event) }.disabled(event.isEmpty)
                Spacer()
                Button("Copy Snapshot", systemImage: "doc.on.doc") {
                    do {
                        let data = try JSONEncoder().encode(store.snapshot(id: selectedID.isEmpty ? nil : selectedID))
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(String(decoding: data, as: UTF8.self), forType: .string)
                    } catch { self.error = error.localizedDescription }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.background.secondary)
            Divider()
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                ScrollView([.vertical, .horizontal]) {
                    Text(snapshot).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                        .padding(16)
                }
                .defaultScrollAnchor(.topLeading)
                .background(Color(nsColor: .textBackgroundColor))
            }
            if let error = error ?? store.configurationError ?? store.actionError {
                Divider()
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.red.opacity(0.1))
            }
        }
        .controlSize(.regular)
        .onAppear { store.setInspectedWidget(selectedID.isEmpty ? nil : selectedID) }
        .onChange(of: selectedID) { store.setInspectedWidget(selectedID.isEmpty ? nil : selectedID) }
        .onDisappear { store.setInspectedWidget(nil) }
    }

    private var snapshot: String {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            return String(decoding: try encoder.encode(store.snapshot(id: selectedID.isEmpty ? nil : selectedID)), as: UTF8.self)
        } catch { return error.localizedDescription }
    }
}
