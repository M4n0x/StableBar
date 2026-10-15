import SwiftUI

struct InspectorView: View {
    let store: BarStore
    @State private var selectedID = ""
    @State private var event = "manual"
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Widget", selection: $selectedID) {
                    Text("Choose a widget").tag("")
                    ForEach(store.configuration?.widgets ?? []) { Text($0.id).tag($0.id) }
                }
                Button("Run now") { store.scripts[selectedID]?.refresh(ScriptEvent(sender: "manual")) }
                    .disabled(store.scripts[selectedID] == nil)
                Button("Copy snapshot") {
                    do {
                        let data = try JSONEncoder().encode(store.snapshot(id: selectedID.isEmpty ? nil : selectedID))
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(String(decoding: data, as: UTF8.self), forType: .string)
                    } catch { self.error = error.localizedDescription }
                }
            }
            HStack {
                TextField("Event name", text: $event)
                Button("Send event") { store.refreshScripts(for: event) }.disabled(event.isEmpty)
                Text("Profiles: " + (store.activeProfiles.isEmpty ? "base" : store.activeProfiles.joined(separator: ", ")))
                    .foregroundStyle(.secondary)
            }
            if let widget = store.configuration?.widgets.first(where: { $0.id == selectedID }), let action = store.scripts[selectedID]?.output.onClick ?? widget.onClick {
                HStack {
                    Text(action).font(.system(.caption, design: .monospaced)).lineLimit(2)
                    Button("Run click action") { store.runAction(action, widget: widget) }
                }
            }
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                ScrollView([.vertical, .horizontal]) {
                    Text(snapshot).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }.background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
            if let error = error ?? store.configurationError ?? store.actionError { Text(error).foregroundStyle(.red) }
        }
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
