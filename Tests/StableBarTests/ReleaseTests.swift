import Foundation
import Sparkle
import Testing
@testable import StableBar

private let setVersion = URL(filePath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "scripts/set-version.sh").path

@Test(arguments: ["1.2.3-beta.4", "1.2.3-beta.20261020103000.114"])
func releaseVersionWritesTheVersionAndBuildNumberAndNothingElse(version: String) async throws {
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
    _ = try await runCommand(setVersion, arguments: [version, "57", plist.path])
    #expect(try String(contentsOf: plist, encoding: .utf8) == """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
            <key>CFBundleShortVersionString</key><string>\(version)</string>
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

@Test @MainActor func updateChangesReadGeneratedAndChangelogNotes() {
    #expect(AppUpdate.changes(in: """
        ## What's Changed
        * fix: ignore unchanged settings selections by @M4n0x in https://github.com/Seb-GRAF/StableBar/pull/61

        ## New Contributors
        * @M4n0x made their first contribution in https://github.com/Seb-GRAF/StableBar/pull/59

        **Full Changelog**: https://github.com/Seb-GRAF/StableBar/compare/v0.5.0-beta.84...v0.5.0-beta.85
        """) == ["fix: ignore unchanged settings selections"])
    #expect(AppUpdate.changes(in: """
        ## [0.4.0](https://github.com/Seb-GRAF/StableBar/compare/v0.3.0...v0.4.0) (2026-10-15)

        ### Features

        * add yabai workspaces and profile editing ([5c30c63](https://github.com/Seb-GRAF/StableBar/commit/5c30c63))
        """) == ["add yabai workspaces and profile editing ([5c30c63](https://github.com/Seb-GRAF/StableBar/commit/5c30c63))"])
}

@Test(arguments: AppUpdate.Stage.allCases) @MainActor
func updateTileStaysAtTheRightEndOfTheBar(stage: AppUpdate.Stage) {
    let tile = AppUpdate.tile(stage)
    #expect(tile.position == .right)
    #expect(tile.overflow == .never)
}

@MainActor private final class ProbeUpdater: SPUUpdater {
    var checksAutomatically = true
    var busy = false
    var probes = 0
    var backgroundChecks = 0
    var userChecks = 0

    override var automaticallyChecksForUpdates: Bool {
        get { checksAutomatically }
        set { checksAutomatically = newValue }
    }

    override var sessionInProgress: Bool { busy }

    override func checkForUpdateInformation() {
        #expect(!busy)
        probes += 1
        busy = true
    }

    override func checkForUpdatesInBackground() {
        #expect(!busy)
        backgroundChecks += 1
        busy = true
    }

    override func checkForUpdates() {
        #expect(!busy)
        userChecks += 1
        busy = true
    }
}

@MainActor private func updateProbe() -> (AppUpdate, ProbeUpdater) {
    let update = AppUpdate { driver, delegate in
        ProbeUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: delegate)
    }
    return (update, update.updater as! ProbeUpdater)
}

@Test @MainActor func updateProbesRespectAutomaticChecksAndDoNotOverlapSessions() {
    let (update, updater) = updateProbe()
    updater.checksAutomatically = false
    update.checkForUpdateInformation()
    #expect(updater.probes == 0)
    updater.checksAutomatically = true
    update.checkForUpdateInformation()
    #expect(updater.probes == 1)
    update.checkForUpdateInformation()
    #expect(updater.probes == 1)
    updater.busy = false
    update.updater(updater, didFinishUpdateCycleFor: .updateInformation, error: nil)
    update.checkForUpdateInformation()
    #expect(updater.probes == 2)
}

@Test @MainActor func updateProbeHandsOffOnlyAfterFindingAReleaseAndFinishing() {
    let (update, updater) = updateProbe()
    update.checkForUpdateInformation()
    update.updater(updater, didFindValidUpdate: .empty())
    #expect(updater.backgroundChecks == 0)
    updater.busy = false
    update.updater(updater, didFinishUpdateCycleFor: .updateInformation, error: nil)
    #expect(updater.backgroundChecks == 1)
    update.checkForUpdateInformation()
    #expect(updater.probes == 1)
}

@Test @MainActor func failedUpdateProbesWaitForTheNextPollAndForgetThePreviousResult() {
    let (update, updater) = updateProbe()
    update.checkForUpdateInformation()
    update.updater(updater, didFindValidUpdate: .empty())
    updater.busy = false
    update.updater(updater, didFinishUpdateCycleFor: .updateInformation, error: URLError(.notConnectedToInternet))
    #expect(updater.backgroundChecks == 0)
    #expect(updater.probes == 1)
    update.checkForUpdateInformation()
    updater.busy = false
    update.updater(updater, didFinishUpdateCycleFor: .updateInformation, error: nil)
    #expect(updater.probes == 2)
    #expect(updater.backgroundChecks == 0)
}

@Test @MainActor func disablingAutomaticChecksDuringAProbePreventsTheHandoff() {
    let (update, updater) = updateProbe()
    update.checkForUpdateInformation()
    update.updater(updater, didFindValidUpdate: .empty())
    updater.checksAutomatically = false
    updater.busy = false
    update.updater(updater, didFinishUpdateCycleFor: .updateInformation, error: nil)
    #expect(updater.backgroundChecks == 0)
}

@Test(arguments: [SPUUpdateCheck.updates, .updatesInBackground]) @MainActor
func completedUpdateSessionsDoNotStartAnotherBackgroundCheck(check: SPUUpdateCheck) {
    let (update, updater) = updateProbe()
    update.updater(updater, didFindValidUpdate: .empty())
    update.updater(updater, didFinishUpdateCycleFor: check, error: nil)
    #expect(updater.backgroundChecks == 0)
}

private func updateState(_ stage: SPUUserUpdateStage = .notDownloaded) throws -> SPUUserUpdateState {
    let encoder = NSKeyedArchiver(requiringSecureCoding: true)
    encoder.encode(stage.rawValue, forKey: "SPUUserUpdateStateStage")
    encoder.encode(false, forKey: "SPUUserUpdateStateUserInitiated")
    encoder.finishEncoding()
    let decoder = try NSKeyedUnarchiver(forReadingFrom: encoder.encodedData)
    defer { decoder.finishDecoding() }
    return try #require(SPUUserUpdateState(coder: decoder))
}

@Test @MainActor func downloadingAPendingUpdateChecksAgainAndInstallsOnlyTheNewOffer() throws {
    let (update, updater) = updateProbe()
    var oldChoices: [SPUUserUpdateChoice] = []
    update.showUpdateFound(with: .empty(), state: try updateState()) { oldChoices.append($0) }
    let offeredVersion = update.version
    updater.busy = true
    updater.checksAutomatically = false

    update.proceed()
    #expect(oldChoices == [.dismiss])
    #expect(updater.userChecks == 0)
    #expect(!update.canProceed)
    #expect(update.action == "Checking…")
    update.dismissUpdateInstallation()
    #expect(update.version == offeredVersion)

    updater.busy = false
    update.updater(updater, didFinishUpdateCycleFor: .updatesInBackground, error: nil)
    #expect(updater.userChecks == 1)
    #expect(!update.canProceed)

    var newChoices: [SPUUserUpdateChoice] = []
    update.showUpdateFound(with: .empty(), state: try updateState()) { newChoices.append($0) }
    #expect(oldChoices == [.dismiss])
    #expect(newChoices == [.install])
    #expect(update.stage == .downloading)
    #expect(!update.canProceed)
    updater.checksAutomatically = true
    update.checkForUpdateInformation()
    #expect(updater.probes == 0)

    var installChoices: [SPUUserUpdateChoice] = []
    update.showReady(toInstallAndRelaunch: { installChoices.append($0) })
    update.proceed()
    #expect(installChoices == [.install])
    #expect(updater.userChecks == 1)
}

@Test @MainActor func failedDownloadChecksDoNotDownloadALaterOffer() throws {
    let (update, updater) = updateProbe()
    update.showUpdateFound(with: .empty(), state: try updateState()) { _ in }
    update.proceed()
    update.dismissUpdateInstallation()
    update.updater(updater, didFinishUpdateCycleFor: .updates, error: nil)
    update.dismissUpdateInstallation()
    updater.busy = false
    update.updater(updater, didFinishUpdateCycleFor: .updates, error: URLError(.notConnectedToInternet))
    #expect(update.version == nil)
    #expect(updater.userChecks == 1)

    var choices: [SPUUserUpdateChoice] = []
    update.showUpdateFound(with: .empty(), state: try updateState()) { choices.append($0) }
    #expect(choices.isEmpty)
    #expect(update.canProceed)
    #expect(update.action == "Download")
}

@Test @MainActor func alreadyDownloadedUpdatesInstallWithoutCheckingAgain() throws {
    let (update, updater) = updateProbe()
    var choices: [SPUUserUpdateChoice] = []
    update.showUpdateFound(with: .empty(), state: try updateState(.downloaded)) { choices.append($0) }
    update.proceed()
    #expect(choices == [.install])
    #expect(updater.userChecks == 0)
}
