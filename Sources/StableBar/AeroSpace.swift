import Foundation
import Observation
import os

struct Workspace: Decodable, Identifiable, Sendable, Equatable {
    let name: String
    let isFocused: Bool
    let isVisible: Bool
    let monitor: Int
    var apps: [WorkspaceApp] = []
    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name = "workspace"
        case isFocused = "workspace-is-focused"
        case isVisible = "workspace-is-visible"
        case monitor = "monitor-appkit-nsscreen-screens-id"
    }
}

struct WorkspaceApp: Decodable, Identifiable, Sendable, Equatable {
    let workspace: String
    let name: String
    let bundleID: String
    var id: String { bundleID }

    enum CodingKeys: String, CodingKey {
        case workspace
        case name = "app-name"
        case bundleID = "app-bundle-id"
    }
}

private struct AeroSpaceEvent: Decodable {
    let mode: String?
}

func workspaceSnapshot(workspaces: Data, windows: Data) throws -> [Workspace] {
    let apps = try JSONDecoder().decode([WorkspaceApp].self, from: windows)
    return try JSONDecoder().decode([Workspace].self, from: workspaces)
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        .map { workspace in
            var workspace = workspace
            var bundleIDs = Set<String>()
            workspace.apps = apps.filter { $0.workspace == workspace.name && bundleIDs.insert($0.bundleID).inserted }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return workspace
        }
}

@MainActor @Observable
final class AeroSpace {
    var workspaces: [Workspace] = []
    var error: String?
    var onWorkspaceChange: (() -> Void)?
    var onModeChange: ((String) -> Void)?
    private var mode: String?
    private var task: Task<Void, Never>?
    private var process: Process?

    func start() {
        stop()
        task = Task {
            while !Task.isCancelled {
                do {
                    let stream = Process()
                    let output = Pipe()
                    stream.executableURL = URL(filePath: try executable())
                    stream.arguments = ["subscribe", "focused-workspace-changed", "focused-monitor-changed", "focus-changed",
                                        "window-detected", "mode-changed"]
                    stream.standardOutput = output
                    stream.standardError = FileHandle.standardError
                    let received = OSAllocatedUnfairLock(initialState: (pending: Data(), mode: String?.none))
                    let events = AsyncStream<Void>(bufferingPolicy: .bufferingNewest(1)) { continuation in
                        output.fileHandleForReading.readabilityHandler = { handle in
                            let data = handle.availableData
                            if data.isEmpty {
                                continuation.finish()
                                return
                            }
                            received.withLock { received in
                                received.pending.append(data)
                                while let newline = received.pending.firstIndex(of: 10) {
                                    let line = Data(received.pending[..<newline])
                                    received.pending.removeSubrange(...newline)
                                    if let mode = try? JSONDecoder().decode(AeroSpaceEvent.self, from: line).mode { received.mode = mode }
                                }
                            }
                            continuation.yield(())
                        }
                        continuation.onTermination = { _ in output.fileHandleForReading.readabilityHandler = nil }
                    }
                    try Task.checkCancellation()
                    try stream.run()
                    process = stream
                    defer {
                        output.fileHandleForReading.readabilityHandler = nil
                        if stream.isRunning { stream.terminate() }
                    }
                    try await refresh()
                    for await _ in events {
                        try Task.checkCancellation()
                        try await refresh()
                        let current = received.withLock { $0.mode }
                        if let current, current != mode {
                            mode = current
                            onModeChange?(current)
                        }
                    }
                    throw CommandFailure(message: "AeroSpace disconnected. Reconnecting…")
                } catch {
                    if Task.isCancelled { return }
                    self.error = error.localizedDescription
                }
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch { return }
            }
        }
    }

    private func refresh() async throws {
        let executable = try executable()
        async let spaces = runCommand(executable, arguments: [
            "list-workspaces", "--all", "--format",
            "%{workspace} %{workspace-is-focused} %{workspace-is-visible} %{monitor-appkit-nsscreen-screens-id}", "--json"
        ])
        async let windows = runCommand(executable, arguments: [
            "list-windows", "--all", "--format", "%{workspace} %{app-name} %{app-bundle-id}", "--json"
        ])
        let snapshot = try await workspaceSnapshot(workspaces: spaces, windows: windows)
        try Task.checkCancellation()
        let previousWorkspace = workspaces.first(where: \.isFocused)?.name
        if workspaces != snapshot { workspaces = snapshot }
        if previousWorkspace != workspaces.first(where: \.isFocused)?.name { onWorkspaceChange?() }
        error = nil
    }

    func select(_ workspace: Workspace) {
        Task {
            do {
                _ = try await runCommand(executable(), arguments: ["workspace", workspace.name])
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func executable() throws -> String {
        let directories = shellEnvironment.withLock { $0["PATH"] ?? "" }.split(separator: ":")
        guard let directory = directories.first(where: { FileManager.default.isExecutableFile(atPath: "\($0)/aerospace") }) else {
            throw CommandFailure(message: "AeroSpace is not on your login shell's PATH.")
        }
        return "\(directory)/aerospace"
    }

    func stop() {
        task?.cancel()
        if let process, process.isRunning { process.terminate() }
        process = nil
    }
}
