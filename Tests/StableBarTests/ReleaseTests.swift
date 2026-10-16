import Foundation
import Testing
@testable import StableBar

private let setVersion = URL(filePath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "scripts/set-version.sh").path

@Test func releaseVersionWritesTheVersionAndBuildNumberAndNothingElse() async throws {
    let plist = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).plist")
    defer { try? FileManager.default.removeItem(at: plist) }
    try Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
            <key>CFBundleShortVersionString</key><string>0.1.0</string>
            <key>CFBundleVersion</key>
            <string>1</string>
            <key>LSMinimumSystemVersion</key><string>14.0</string>
        </dict></plist>

        """.utf8).write(to: plist)
    _ = try await runCommand(setVersion, arguments: ["1.2.3-beta.4", "57", plist.path])
    #expect(try String(contentsOf: plist, encoding: .utf8) == """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
            <key>CFBundleShortVersionString</key><string>1.2.3-beta.4</string>
            <key>CFBundleVersion</key>
            <string>57</string>
            <key>LSMinimumSystemVersion</key><string>14.0</string>
        </dict></plist>

        """)
}

@Test func releaseVersionLeavesThePlistUntouchedWhenAVersionKeyIsMissing() async throws {
    let plist = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).plist")
    defer { try? FileManager.default.removeItem(at: plist) }
    let original = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
            <key>CFBundleShortVersionString</key><string>0.1.0</string>
        </dict></plist>

        """.utf8)
    try original.write(to: plist)
    await #expect(throws: CommandFailure.self) {
        try await runCommand(setVersion, arguments: ["1.2.3", "57", plist.path])
    }
    #expect(try Data(contentsOf: plist) == original)
}

// CFBundleVersion takes one to three dot-separated integers, so a prerelease version must not end
// up there. A plist path in second place is the old two-argument call.
@Test(arguments: ["1.2.3-beta.4", "1.2.3.4", "Resources/Info.plist"])
func releaseVersionRejectsABuildNumberThatIsNotOneToThreeIntegers(build: String) async throws {
    let plist = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).plist")
    defer { try? FileManager.default.removeItem(at: plist) }
    let original = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
            <key>CFBundleShortVersionString</key><string>0.1.0</string>
            <key>CFBundleVersion</key><string>1</string>
        </dict></plist>

        """.utf8)
    try original.write(to: plist)
    await #expect(throws: CommandFailure.self) {
        try await runCommand(setVersion, arguments: ["1.2.3-beta.4", build, plist.path])
    }
    #expect(try Data(contentsOf: plist) == original)
}
