import Foundation

struct CommandFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

func runCommand(_ executable: String, arguments: [String]) async throws -> Data {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(filePath: executable)
    process.arguments = arguments
    var environment = ProcessInfo.processInfo.environment
    environment["STABLEBAR_SCRIPTS"] = Bundle.main.resourceURL!.appending(path: "widgets").path
    process.environment = environment
    process.standardOutput = output
    process.standardError = output
    try Task.checkCancellation()
    try process.run()
    return try await withTaskCancellationHandler {
        let data = await Task.detached {
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return data
        }.value
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else {
            throw CommandFailure(message: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return data
    } onCancel: {
        if process.isRunning { process.terminate() }
    }
}
