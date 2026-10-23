import AppKit
import SwiftUI

struct CommandLineToolSettings: View {
    @State private var status = Self.currentStatus()
    @State private var installing = false
    @State private var error: String?

    var body: some View {
        SettingRow(title: "\(CommandLineTool.name) command", hint: hint) {
            switch status {
            case .installed: indicator("Installed", SettingsPalette.success)
            case .foreign: indicator("Name in use", .orange)
            case .missing, .otherCopy:
                Button("Install", action: install).disabled(installing || !appIsInApplications())
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            status = Self.currentStatus()
        }
        if let error {
            Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
        }
    }

    private var hint: String {
        let move = appIsInApplications() ? nil : "Move StableBar to Applications to install the command."
        return switch status {
        case let .installed(command):
            "Run StableBar from Terminal as \(CommandLineTool.name). It's installed at \(abbreviated(command))."
        case .missing:
            move ?? "Run StableBar from Terminal as \(CommandLineTool.name). Installing it in \(CommandLineTool.directory.path) may ask for your password."
        case let .otherCopy(command, executable):
            "\(abbreviated(command)) opens another copy of StableBar, at \(abbreviated(Self.app(of: executable))). "
                + (move ?? "Install points it at this one.")
        case let .foreign(command):
            "\(abbreviated(command)) wasn't installed by StableBar, so it's left as it is."
        }
    }

    private func indicator(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
        }
    }

    private func install() {
        guard let executable = Bundle.main.executableURL else { return }
        let command = if case let .otherCopy(command, _) = status { command }
            else { CommandLineTool.directory.appending(path: CommandLineTool.name) }
        installing = true
        Task {
            do {
                try await CommandLineTool.install(executable, at: command)
                error = nil
            } catch is CancellationError {
            } catch {
                self.error = errorMessage(error)
            }
            installing = false
            status = Self.currentStatus()
        }
    }

    private func abbreviated(_ url: URL) -> String {
        url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private static func currentStatus() -> CommandLineTool.Status {
        guard let executable = Bundle.main.executableURL else { return .missing }
        return CommandLineTool.status(for: executable, path: shellEnvironment.withLock { $0["PATH"] })
    }

    /// The app bundle around an executable in `Contents/MacOS`, or the executable itself.
    private static func app(of executable: URL) -> URL {
        let app = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return app.pathExtension == "app" ? app : executable
    }
}
