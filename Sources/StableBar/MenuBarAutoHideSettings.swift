import AppKit
import SwiftUI

/// Settings › General › Native menu bar: the macOS setting that setup turns on for the top edge.
struct MenuBarAutoHideSettings: View {
    @State private var isOn = MenuBarAutoHide.isOn()
    @State private var changing = false
    @State private var error: String?

    var body: some View {
        SettingRow(title: "Automatically hide the menu bar",
                   hint: "The macOS setting that lets the bar take the menu bar’s place on the top edge. macOS asks once to let StableBar control System Events.") {
            Toggle("Automatically hide the menu bar", isOn: Binding(get: { isOn }, set: { change($0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(changing)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isOn = MenuBarAutoHide.isOn()
        }
        if let error {
            Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
        }
    }

    private func change(_ hidden: Bool) {
        changing = true
        Task {
            do {
                try await MenuBarAutoHide.change(to: hidden)
                isOn = hidden
                error = nil
            } catch {
                let detail = errorMessage(error).contains("-1743")
                    ? "Allow StableBar in System Settings → Privacy & Security → Automation." : errorMessage(error)
                self.error = "StableBar couldn’t \(hidden ? "hide" : "show") the macOS menu bar. \(detail)"
            }
            changing = false
        }
    }
}
