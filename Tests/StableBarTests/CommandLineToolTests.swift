import Foundation
import Testing
@testable import StableBar

private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(path: "Stable Bar's \(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func executableFile(at url: URL, _ text: String = "#!/bin/sh\necho other\n") throws -> URL {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}

@Test func commandLineScriptRunsTheAppWithEveryArgument() async throws {
    let directory = try temporaryDirectory()
    let script = try executableFile(at: directory.appending(path: "stablebar"),
                                    CommandLineTool.script(running: URL(filePath: "/bin/echo")))
    let output = try await runCommand(script.path, arguments: ["a b", "c'd", "$HOME"])
    #expect(String(decoding: output, as: UTF8.self) == "a b c'd $HOME\n")
}

@Test func commandLineScriptNamesTheAppItRuns() {
    let app = URL(filePath: "/Users/me/Apps/Stable Bar's copy.app/Contents/MacOS/StableBar")
    #expect(CommandLineTool.executable(inScript: CommandLineTool.script(running: app)) == app)
    #expect(CommandLineTool.executable(inScript: "#!/bin/sh\nexec '/usr/bin/true' \"$@\"\n") == nil)
}

@Test func commandLineStatusIsMissingWithoutACommand() throws {
    let path = try temporaryDirectory(), directory = try temporaryDirectory()
    #expect(CommandLineTool.status(for: URL(filePath: "/Applications/StableBar.app/Contents/MacOS/StableBar"),
                                   path: path.path, directory: directory) == .missing)
}

@Test func commandLineStatusRecognizesItsOwnScript() throws {
    let directory = try temporaryDirectory()
    let app = try executableFile(at: directory.appending(path: "StableBar.app/Contents/MacOS/StableBar"))
    let command = try executableFile(at: directory.appending(path: "bin/stablebar"), CommandLineTool.script(running: app))
    #expect(CommandLineTool.status(for: app, path: command.deletingLastPathComponent().path, directory: directory) == .installed(command))
}

@Test func commandLineStatusRecognizesALinkToTheApp() throws {
    let directory = try temporaryDirectory()
    let app = try executableFile(at: directory.appending(path: "StableBar.app/Contents/MacOS/StableBar"))
    let command = directory.appending(path: "stablebar")
    try FileManager.default.createSymbolicLink(at: command, withDestinationURL: app)
    #expect(CommandLineTool.status(for: app, path: directory.path, directory: directory) == .installed(command))
}

@Test func commandLineStatusNamesAnotherCopyOfTheApp() throws {
    let directory = try temporaryDirectory()
    let app = try executableFile(at: directory.appending(path: "StableBar.app/Contents/MacOS/StableBar"))
    let other = URL(filePath: "/Users/me/Downloads/StableBar.app/Contents/MacOS/StableBar")
    let command = try executableFile(at: directory.appending(path: "stablebar"), CommandLineTool.script(running: other))
    #expect(CommandLineTool.status(for: app, path: directory.path, directory: directory) == .otherCopy(command, executable: other))
}

@Test func commandLineStatusLeavesOtherCommandsAlone() throws {
    let directory = try temporaryDirectory()
    let app = try executableFile(at: directory.appending(path: "StableBar.app/Contents/MacOS/StableBar"))
    let command = try executableFile(at: directory.appending(path: "stablebar"))
    #expect(CommandLineTool.status(for: app, path: directory.path, directory: directory) == .foreign(command))
}

@Test func commandLineStatusUsesTheFirstCommandOnPath() throws {
    let directory = try temporaryDirectory()
    let app = try executableFile(at: directory.appending(path: "StableBar.app/Contents/MacOS/StableBar"))
    let first = try executableFile(at: directory.appending(path: "first/stablebar"))
    _ = try executableFile(at: directory.appending(path: "second/stablebar"), CommandLineTool.script(running: app))
    try FileManager.default.createDirectory(at: directory.appending(path: "empty/stablebar"), withIntermediateDirectories: true)
    let path = ["empty", "first", "second"].map { directory.appending(path: $0).path }.joined(separator: ":")
    #expect(CommandLineTool.status(for: app, path: path, directory: directory.appending(path: "second")) == .foreign(first))
}

@Test func commandLineStatusSkipsFilesThatCannotRun() throws {
    let directory = try temporaryDirectory()
    let app = try executableFile(at: directory.appending(path: "StableBar.app/Contents/MacOS/StableBar"))
    try Data("text".utf8).write(to: directory.appending(path: "stablebar"))
    #expect(CommandLineTool.status(for: app, path: directory.path, directory: directory) == .missing)
}

@Test func commandLineStatusChecksTheInstallDirectoryOffPath() throws {
    let directory = try temporaryDirectory()
    let app = try executableFile(at: directory.appending(path: "StableBar.app/Contents/MacOS/StableBar"))
    let command = try executableFile(at: directory.appending(path: "bin/stablebar"), CommandLineTool.script(running: app))
    #expect(CommandLineTool.status(for: app, path: nil, directory: command.deletingLastPathComponent()) == .installed(command))
}

@Test func commandLineInstallWritesARunnableScript() async throws {
    let directory = try temporaryDirectory()
    let app = try executableFile(at: directory.appending(path: "StableBar.app/Contents/MacOS/StableBar"))
    let command = directory.appending(path: "bin/stablebar")
    try await CommandLineTool.install(app, at: command)
    #expect(FileManager.default.isExecutableFile(atPath: command.path))
    #expect(CommandLineTool.status(for: app, path: nil, directory: command.deletingLastPathComponent()) == .installed(command))
}

@Test func commandLineInstallPointsAnOldScriptAtThisApp() async throws {
    let directory = try temporaryDirectory()
    let app = try executableFile(at: directory.appending(path: "StableBar.app/Contents/MacOS/StableBar"))
    let command = try executableFile(at: directory.appending(path: "stablebar"),
                                     CommandLineTool.script(running: URL(filePath: "/Volumes/StableBar/StableBar.app/Contents/MacOS/StableBar")))
    try await CommandLineTool.install(app, at: command)
    #expect(CommandLineTool.status(for: app, path: directory.path, directory: directory) == .installed(command))
}

@Test func commandLineInstallKeepsAnotherCommand() async throws {
    let directory = try temporaryDirectory()
    let app = try executableFile(at: directory.appending(path: "StableBar.app/Contents/MacOS/StableBar"))
    let command = try executableFile(at: directory.appending(path: "stablebar"))
    await #expect(throws: (any Error).self) { try await CommandLineTool.install(app, at: command) }
    #expect(try String(contentsOf: command, encoding: .utf8) == "#!/bin/sh\necho other\n")
}

@Test func commandLinePrivilegedInstallCreatesTheDirectoryAndScript() async throws {
    let directory = try temporaryDirectory()
    let source = try executableFile(at: directory.appending(path: "source"), "#!/bin/sh\necho ok\n")
    let command = directory.appending(path: "new bin/it's/stablebar")
    _ = try await runCommand("/bin/sh", arguments: ["-c", CommandLineTool.installCommand(from: source, to: command)])
    #expect(FileManager.default.isExecutableFile(atPath: command.path))
    #expect(try String(contentsOf: command, encoding: .utf8) == "#!/bin/sh\necho ok\n")
}
