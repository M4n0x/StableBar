import CryptoKit
import XCTest
@testable import StableBar

final class PackageSourceBuilderTests: XCTestCase {
    private let examples = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "examples/packages")

    /// A temporary "packages" folder holding copies of the named example packages.
    private func packages(_ names: [String], in fixture: ThemeGalleryFixture) throws -> URL {
        let packages = fixture.directory.appending(path: "packages-source")
        try FileManager.default.createDirectory(at: packages, withIntermediateDirectories: true)
        for name in names {
            try FileManager.default.copyItem(at: examples.appending(path: name), to: packages.appending(path: name))
        }
        return packages
    }

    private func sha256(_ url: URL) throws -> String {
        try SHA256.hash(data: Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    private func entry(_ id: String, in directory: URL) async throws -> PackageIndex.Entry {
        let index = try await PackageIndex.load(from: directory.appending(path: "index.json"))
        return try XCTUnwrap(index.packages.first { $0.id == id })
    }

    func testBuiltSourceInstallsThroughTheClient() async throws {
        let fixture = try ThemeGalleryFixture()
        defer { fixture.close() }
        let packages = try packages(["local-clock", "system-monitor"], in: fixture)
        let dist = fixture.directory.appending(path: "dist")
        let build = try await PackageSourceBuilder(packages: packages, output: dist).build()
        XCTAssertEqual(build.ids, ["local-clock", "system-monitor"])
        XCTAssertEqual(build.written, ["local-clock-1.0.0.tar.gz", "system-monitor-1.1.0.tar.gz"])
        let index = try await PackageIndex.load(from: dist.appending(path: "index.json"))
        XCTAssertEqual(index.packages.map(\.id), build.ids)
        for entry in index.packages {
            XCTAssertEqual(entry.archive, "\(entry.id)-\(entry.version).tar.gz")
            XCTAssertEqual(try sha256(dist.appending(path: entry.archive)), entry.sha256)
        }
        // The index is the Store's format: a "packages" object, no nulls, and only the keys the Store lists.
        let raw = try JSONDecoder().decode([String: ConfigurationValue].self, from: Data(contentsOf: dist.appending(path: "index.json")))
        guard case let .array(listed)? = raw["packages"], case let .object(first)? = listed.first else {
            return XCTFail("The index has no packages array.")
        }
        XCTAssertFalse(first.values.contains(.null))
        XCTAssertTrue(Set(first.keys).isSubset(of: ["id", "name", "version", "kind", "description", "author", "minimumVersion",
                                                    "screenshot", "archive", "sha256", "source"]))
        // A client reads the built source: a package without commands installs, and one with a script lists its commands.
        let client = PackageStoreClient(packages: fixture.packages, indexURL: dist.appending(path: "index.json"))
        let monitor = try XCTUnwrap(index.packages.first { $0.id == "system-monitor" })
        let installed = try await client.installWithoutReview(monitor)
        XCTAssertEqual(installed.manifest.id, "system-monitor")
        let clock = try XCTUnwrap(index.packages.first { $0.id == "local-clock" })
        let download = try await client.package(clock)
        XCTAssertFalse(download.commands.isEmpty)
    }

    func testRebuildKeepsPublishedVersionsAndWritesOnlyNewArchives() async throws {
        let fixture = try ThemeGalleryFixture()
        defer { fixture.close() }
        let packages = try packages(["local-clock", "system-monitor"], in: fixture)
        let dist = fixture.directory.appending(path: "dist")
        _ = try await PackageSourceBuilder(packages: packages, output: dist).build()
        let previous = fixture.directory.appending(path: "previous.json")
        try FileManager.default.copyItem(at: dist.appending(path: "index.json"), to: previous)
        // Rebuilding unchanged versions without --previous would write the same files again, so it is refused.
        do {
            _ = try await PackageSourceBuilder(packages: packages, output: dist).build()
            XCTFail("Overwriting a published archive was accepted.")
        } catch {
            XCTAssertTrue(errorMessage(error).contains("local-clock-1.0.0.tar.gz already exists"), errorMessage(error))
        }
        // A changed package gets a new version; the other keeps its published entry.
        let manifest = packages.appending(path: "system-monitor/package.json")
        let text = try String(contentsOf: manifest, encoding: .utf8).replacingOccurrences(of: #""version": "1.1.0""#, with: #""version": "1.2.0""#)
        try text.write(to: manifest, atomically: true, encoding: .utf8)
        let dist2 = fixture.directory.appending(path: "dist2")
        let second = try await PackageSourceBuilder(packages: packages, output: dist2, previous: previous).build()
        XCTAssertEqual(second.ids, ["local-clock", "system-monitor"])
        XCTAssertEqual(second.written, ["system-monitor-1.2.0.tar.gz"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: dist2.appending(path: "local-clock-1.0.0.tar.gz").path))
        let kept = try await entry("local-clock", in: dist2)
        let published = try await entry("local-clock", in: dist)
        XCTAssertEqual(kept.sha256, published.sha256)
        XCTAssertEqual(kept.archive, published.archive)
        let bumped = try await entry("system-monitor", in: dist2)
        XCTAssertEqual(bumped.version, "1.2.0")
        XCTAssertEqual(bumped.archive, "system-monitor-1.2.0.tar.gz")
    }

    func testBuildRejectsDuplicateAndInvalidPackagesAndCopiesScreenshots() async throws {
        let fixture = try ThemeGalleryFixture()
        defer { fixture.close() }
        // Two folders with the same package ID.
        let duplicates = try packages(["local-clock"], in: fixture)
        try FileManager.default.copyItem(at: duplicates.appending(path: "local-clock"), to: duplicates.appending(path: "b"))
        try FileManager.default.moveItem(at: duplicates.appending(path: "local-clock"), to: duplicates.appending(path: "a"))
        do {
            _ = try await PackageSourceBuilder(packages: duplicates, output: fixture.directory.appending(path: "dist-duplicates")).build()
            XCTFail("Two folders with one ID were accepted.")
        } catch {
            XCTAssertEqual(errorMessage(error), "Two folders contain package local-clock: a, b.")
        }
        // A folder whose manifest is invalid names the folder.
        let invalid = fixture.directory.appending(path: "invalid")
        try fixture.write(#"{"id":"bad id","name":"Bad","version":"1","kind":"widgets","entry":"config.json"}"#,
                          to: invalid.appending(path: "broken/package.json"))
        try fixture.write(#"{"widgets":[]}"#, to: invalid.appending(path: "broken/config.json"))
        do {
            _ = try await PackageSourceBuilder(packages: invalid, output: fixture.directory.appending(path: "dist-invalid")).build()
            XCTFail("An invalid package was accepted.")
        } catch {
            XCTAssertTrue(errorMessage(error).hasPrefix("broken: "), errorMessage(error))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directory.appending(path: "dist-invalid/index.json").path))
        // A manifest screenshot is copied beside the archive and listed by its new name.
        let shots = fixture.directory.appending(path: "shots")
        try FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: examples.appending(path: "local-clock"), to: shots.appending(path: "local-clock"))
        let manifest = shots.appending(path: "local-clock/package.json")
        let text = try String(contentsOf: manifest, encoding: .utf8)
            .replacingOccurrences(of: #""version": "1.0.0","#, with: #""version": "1.0.0", "screenshot": "shot.png","#)
        try text.write(to: manifest, atomically: true, encoding: .utf8)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: shots.appending(path: "local-clock/shot.png"))
        let dist = fixture.directory.appending(path: "dist")
        let build = try await PackageSourceBuilder(packages: shots, output: dist).build()
        XCTAssertEqual(build.written, ["local-clock-1.0.0.tar.gz", "local-clock-1.0.0-shot.png"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: dist.appending(path: "local-clock-1.0.0-shot.png").path))
        let listed = try await entry("local-clock", in: dist)
        XCTAssertEqual(listed.screenshot, dist.appending(path: "local-clock-1.0.0-shot.png"))
    }

    func testThemePackageKeepsItsKindAndRepository() async throws {
        let fixture = try ThemeGalleryFixture()
        defer { fixture.close() }
        let packages = try packages(["tonhalle-line"], in: fixture)
        let manifest = packages.appending(path: "tonhalle-line/package.json")
        let text = try String(contentsOf: manifest, encoding: .utf8)
            .replacingOccurrences(of: #""kind": "theme","#, with: #""kind": "theme", "repository": "https://example.com/tonhalle","#)
        try text.write(to: manifest, atomically: true, encoding: .utf8)
        let dist = fixture.directory.appending(path: "dist")
        _ = try await PackageSourceBuilder(packages: packages, output: dist).build()
        let theme = try await entry("tonhalle-line", in: dist)
        XCTAssertEqual(theme.kind, .theme)
        XCTAssertEqual(theme.repository, URL(string: "https://example.com/tonhalle"))
        XCTAssertNil(theme.screenshot)
    }
}
