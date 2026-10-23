import CryptoKit
import XCTest
@testable import StableBar

struct LocalPackageIndex {
    let fixture: ThemeGalleryFixture
    var folder = "store"
    var url: URL { fixture.directory.appending(path: "\(folder)/index.json") }

    func add(id: String = "store-theme", kind: String? = "theme", configuration: String = #"{"bar":{"height":31}}"#,
             checksum: String? = nil, listedKind: String? = nil, settings: String = "{}", version: String = "1",
             hosts: String = "[]", permissions: String = "[]", requires: String = "[]",
             screenshot: String? = nil, name: String = "Store theme") async throws -> PackageIndex.Entry {
        let source = fixture.directory.appending(path: "sources/\(id)")
        let kindField = kind.map { #", "kind":"\#($0)""# } ?? ""
        try fixture.write(#"{"id":"\#(id)","name":"\#(name)","version":"\#(version)","entry":"config.json","settings":\#(settings),"hosts":\#(hosts),"permissions":\#(permissions),"requires":\#(requires)\#(kindField)}"#,
                          to: source.appending(path: "package.json"))
        try fixture.write(configuration, to: source.appending(path: "config.json"))
        let archive = url.deletingLastPathComponent().appending(path: "\(id).tar.gz")
        try FileManager.default.createDirectory(at: archive.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try await runCommand("/usr/bin/tar", arguments: ["-czf", archive.path, "-C", source.path, "."])
        let hash = try checksum ?? SHA256.hash(data: Data(contentsOf: archive)).map { String(format: "%02x", $0) }.joined()
        let indexKind = (listedKind ?? kind).map { #", "kind":"\#($0)""# } ?? ""
        let screenshotField = screenshot.map { #", "screenshot":"\#($0)""# } ?? ""
        try fixture.write(#"""
        {"packages":[{"id":"future","kind":"future-kind"},
         {"id":"\#(id)","name":"\#(name)","version":"\#(version)","archive":"\#(id).tar.gz","sha256":"\#(hash)",
          "source":"https://example.com/package","future":true\#(indexKind)\#(screenshotField)}],"future":true}
        """#, to: url)
        return try await PackageIndex.load(from: url).packages[0]
    }
}

final class PackageStoreClientTests: XCTestCase {
    func testIndexAndVerifiedDownloadsAreCachedForTheSession() async throws {
        let fixture = try ThemeGalleryFixture()
        defer { fixture.close() }
        let index = LocalPackageIndex(fixture: fixture)
        let entry = try await index.add()
        let client = PackageStoreClient(packages: fixture.packages, indexURL: index.url)
        let entries = try await client.index().packages
        XCTAssertEqual(entries.map(\.id), ["store-theme"])
        let download = try await client.package(entries[0])
        XCTAssertEqual(download.manifest.kind, .theme)
        XCTAssertTrue(download.commands.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.packages.directory.path))
        try FileManager.default.removeItem(at: index.url.deletingLastPathComponent())
        let cached = try await client.index().packages
        XCTAssertEqual(cached.map(\.id), [entry.id])
        let package = try await client.package(entry)
        XCTAssertEqual(package.directory, download.directory)
        let installed = try await client.installWithoutReview(entry)
        XCTAssertEqual(installed.directory, fixture.directory.appending(path: "packages/store-theme/1"))
        let repeated = try await client.installWithoutReview(entry)
        XCTAssertEqual(repeated.directory, installed.directory)
    }

    func testOfflineIndexFailureCanBeRetriedWithoutAffectingInstalledPackages() async throws {
        let fixture = try ThemeGalleryFixture()
        defer { fixture.close() }
        _ = try fixture.theme(#"{}"#)
        let index = LocalPackageIndex(fixture: fixture)
        let client = PackageStoreClient(packages: fixture.packages, indexURL: index.url)
        do { _ = try await client.index(); XCTFail("A missing local index must fail") } catch {}
        _ = try await index.add()
        let result = try await client.index()
        XCTAssertEqual(result.packages.count, 1)
        XCTAssertEqual(try fixture.packages.list().map(\.id), ["test-theme"])
    }

    func testCommandFreeWidgetsAndLegacyPackagesCanInstallWithoutReview() async throws {
        for kind: String? in ["widgets", nil] {
            let fixture = try ThemeGalleryFixture()
            defer { fixture.close() }
            let index = LocalPackageIndex(fixture: fixture)
            let entry = try await index.add(id: "clock", kind: kind, configuration: #"{"widgets":[{"id":"clock","type":"clock","position":"right"}]}"#)
            let installed = try await PackageStoreClient(packages: fixture.packages, indexURL: index.url).installWithoutReview(entry)
            XCTAssertEqual(installed.manifest.id, "clock")
            XCTAssertTrue(installed.commands.isEmpty)
        }
    }

    func testCommandsIncludingInactiveProfilesAndTemplatesAlwaysRequireReview() async throws {
        for configuration in [
            #"{"widgets":[{"id":"script","type":"script","position":"left","command":"echo forbidden"}]}"#,
            #"{"widgets":[],"profiles":[{"name":"inactive","when":{"appearance":"dark"},"configuration":{"widgets":[{"id":"note","type":"text","position":"left","text":"Note","onClick":"echo forbidden"}]}}]}"#,
            #"{"widgets":[],"templates":{"unused":{"type":"script","command":"echo forbidden"}}}"#
        ] {
            let fixture = try ThemeGalleryFixture()
            defer { fixture.close() }
            let index = LocalPackageIndex(fixture: fixture)
            let entry = try await index.add(id: "commands", kind: nil, configuration: configuration)
            let client = PackageStoreClient(packages: fixture.packages, indexURL: index.url)
            do { _ = try await client.installWithoutReview(entry); XCTFail("Commands must require review") }
            catch { XCTAssertTrue(error is PackageStoreClientError) }
            XCTAssertTrue(try fixture.packages.list().isEmpty)
        }
    }

    func testHostsOnlyDownloadRequiresReviewBeforeInstalling() async throws {
        let fixture = try ThemeGalleryFixture()
        defer { fixture.close() }
        let index = LocalPackageIndex(fixture: fixture)
        let entry = try await index.add(id: "hosts", kind: "widgets", configuration: #"{"widgets":[]}"#,
                                        hosts: #"["example.com"]"#)
        let client = PackageStoreClient(packages: fixture.packages, indexURL: index.url)
        do { _ = try await client.installWithoutReview(entry); XCTFail("Declared hosts must require review") }
        catch PackageStoreClientError.reviewRequired {}
        XCTAssertTrue(try fixture.packages.list().isEmpty)
    }

    func testHostsOnlyInstalledVersionRequiresReviewEvenWithAPlainDownload() async throws {
        let fixture = try ThemeGalleryFixture()
        defer { fixture.close() }
        let index = LocalPackageIndex(fixture: fixture)
        let entry = try await index.add(id: "hosts", kind: "widgets", configuration: #"{"widgets":[]}"#)
        let client = PackageStoreClient(packages: fixture.packages, indexURL: index.url)
        let installed = try await client.installWithoutReview(entry)
        try fixture.write(#"{"id":"hosts","name":"Hosts","version":"1","kind":"widgets","entry":"config.json","hosts":["example.com"]}"#,
                          to: installed.directory.appending(path: "package.json"))
        do { _ = try await client.installWithoutReview(entry); XCTFail("Installed hosts must require review") }
        catch PackageStoreClientError.reviewRequired {}
        XCTAssertEqual(try fixture.packages.list().count, 1)
    }

    func testBadChecksumInvalidThemeAndMisleadingKindCannotBeInstalled() async throws {
        for failure in ["checksum", "theme", "kind"] {
            let fixture = try ThemeGalleryFixture()
            defer { fixture.close() }
            let index = LocalPackageIndex(fixture: fixture)
            let entry = try await index.add(kind: failure == "kind" ? nil : "theme",
                configuration: failure == "theme" ? #"{"providers":{"bad":{"type":"command","command":"echo forbidden"}}}"# : #"{}"#,
                checksum: failure == "checksum" ? String(repeating: "0", count: 64) : nil,
                listedKind: failure == "kind" ? "theme" : nil)
            do {
                _ = try await PackageStoreClient(packages: fixture.packages, indexURL: index.url).installWithoutReview(entry)
                XCTFail("Invalid package must fail: \(failure)")
            } catch {}
            XCTAssertTrue(try fixture.packages.list().isEmpty)
        }
    }
    func testCachedCommandFreeInspectionCannotBypassReviewIfItsFilesChange() async throws {
        let fixture = try ThemeGalleryFixture()
        defer { fixture.close() }
        let index = LocalPackageIndex(fixture: fixture)
        let entry = try await index.add(id: "legacy", kind: nil, configuration: #"{"widgets":[]}"#)
        let client = PackageStoreClient(packages: fixture.packages, indexURL: index.url)
        let cached = try await client.package(entry)
        try fixture.write(#"{"widgets":[{"id":"script","type":"script","position":"left","command":"echo forbidden"}]}"#,
                          to: cached.directory.appending(path: "config.json"))
        do { _ = try await client.installWithoutReview(entry); XCTFail("Changed commands must require review") }
        catch { XCTAssertTrue(error is PackageStoreClientError) }
        XCTAssertTrue(try fixture.packages.list().isEmpty)
    }

    func testCatalogMergesSourcesAndKeepsWorkingWhenOneFails() async throws {
        let fixture = try ThemeGalleryFixture(); defer { fixture.close() }
        let store = LocalPackageIndex(fixture: fixture)
        let acme = LocalPackageIndex(fixture: fixture, folder: "acme")
        _ = try await store.add(id: "clock", kind: "widgets", configuration: #"{"widgets":[]}"#)
        _ = try await acme.add(id: "clock", kind: "widgets", configuration: #"{"widgets":[{"id":"c2","type":"clock","position":"right"}]}"#)
        let broken = PackageSource(id: "broken", name: "Broken", url: fixture.directory.appending(path: "missing/index.json"))
        let client = PackageStoreClient(packages: fixture.packages, indexURL: store.url)
        await client.setPrivateSources([PackageSource(id: "acme", name: "Acme", url: acme.url), broken])
        let catalog = await client.catalog()
        XCTAssertEqual(catalog.entries.map(\.key), ["stablebar:clock/1", "acme:clock/1"])
        XCTAssertEqual(Array(catalog.errors.keys), ["broken"])
        let index = try await client.index()
        XCTAssertEqual(index.packages.count, 2)
        let fromStore = try await client.package(catalog.entries[0]), fromAcme = try await client.package(catalog.entries[1])
        XCTAssertNotEqual(fromStore.directory, fromAcme.directory)
        XCTAssertEqual(fromAcme.widgets.map(\.id), ["c2"])
    }

    func testIndexThrowsOnlyWhenEverySourceFails() async throws {
        let fixture = try ThemeGalleryFixture(); defer { fixture.close() }
        let client = PackageStoreClient(packages: fixture.packages, indexURL: fixture.directory.appending(path: "none/index.json"))
        do { _ = try await client.index(); XCTFail("Every source failed") } catch {}
    }

    func testHTMLIndexAndDuplicateIDsDoNotHideOtherSources() async throws {   // Review Focus 1, 5
        let fixture = try ThemeGalleryFixture(); defer { fixture.close() }
        let store = LocalPackageIndex(fixture: fixture)
        _ = try await store.add(id: "clock", kind: "widgets", configuration: #"{"widgets":[]}"#)
        try fixture.write("<html>Sign in</html>", to: fixture.directory.appending(path: "sso/index.json"))
        let index = try String(contentsOf: store.url, encoding: .utf8)
        try fixture.write(index.replacingOccurrences(of: #"{"packages":["#, with: #"{"packages":[{"id":"clock","name":"Dup","version":"9","archive":"x","sha256":"0"},"#),
                          to: fixture.directory.appending(path: "dup/index.json"))
        let client = PackageStoreClient(packages: fixture.packages, indexURL: store.url)
        await client.setPrivateSources([PackageSource(id: "sso", name: "SSO", url: fixture.directory.appending(path: "sso/index.json")),
                                        PackageSource(id: "dup", name: "Dup", url: fixture.directory.appending(path: "dup/index.json"))])
        let catalog = await client.catalog()
        XCTAssertEqual(catalog.errors["sso"], "the index isn’t a StableBar package index.")
        XCTAssertEqual(catalog.entries.filter { $0.sourceID == "dup" }.map(\.version), ["9"])
        XCTAssertEqual(catalog.entries.filter { $0.sourceID == "stablebar" }.count, 1)
    }

    func testChangingASourceURLReloadsItsIndex() async throws {   // Review Focus 2
        let fixture = try ThemeGalleryFixture(); defer { fixture.close() }
        let a = LocalPackageIndex(fixture: fixture, folder: "a"), b = LocalPackageIndex(fixture: fixture, folder: "b")
        _ = try await a.add(id: "one"); _ = try await b.add(id: "two")
        let client = PackageStoreClient(packages: fixture.packages, indexURL: fixture.directory.appending(path: "none/index.json"))
        await client.setPrivateSources([PackageSource(id: "team", name: "Team", url: a.url)])
        let first = await client.catalog()
        XCTAssertEqual(first.entries.map(\.id), ["one"])
        await client.setPrivateSources([PackageSource(id: "team", name: "Team", url: b.url)])
        let second = await client.catalog()
        XCTAssertEqual(second.entries.map(\.id), ["two"])
    }

    func testPrivateRequestsCarryTheTokenOnlyToTheirHost() async throws {   // Review Focus 4
        let fixture = try ThemeGalleryFixture(); defer { fixture.close() }
        let local = LocalPackageIndex(fixture: fixture)
        let entry = try await local.add(id: "clock", kind: "widgets", configuration: #"{"widgets":[]}"#)
        let base = URL(string: "https://packages.token-test.example/team/")!
        StubURLProtocol.serve(try Data(contentsOf: local.url.deletingLastPathComponent().appending(path: "clock.tar.gz")),
                              at: base.appending(path: "clock.tar.gz"))
        StubURLProtocol.serve(Data(#"{"packages":[{"id":"clock","name":"Clock","version":"1","kind":"widgets","archive":"clock.tar.gz","sha256":"\#(entry.sha256)","screenshot":"https://cdn.token-test.example/shot.png"},{"id":"evil","name":"Evil","version":"1","archive":"../../https://evil.example/x.tar.gz","sha256":"0"}]}"#.utf8),
                              at: base.appending(path: "index.json"))
        StubURLProtocol.serve(Data("png".utf8), at: URL(string: "https://cdn.token-test.example/shot.png")!)
        let client = PackageStoreClient(packages: fixture.packages, indexURL: fixture.directory.appending(path: "none/index.json"),
                                        tokens: .memory(["source:team": SavedSourceToken(token: "secret", for: base).stored]),
                                        session: StubURLProtocol.session())
        await client.setPrivateSources([PackageSource(id: "team", name: "Team", url: base.appending(path: "index.json"))])
        let entries = await client.catalog().entries
        _ = try await client.package(entries.first { $0.id == "clock" }!)
        _ = try? await client.package(entries.first { $0.id == "evil" }!)
        _ = try await client.screenshot(for: entries.first { $0.id == "clock" }!)
        let requests = StubURLProtocol.requests.filter { $0.url!.host()!.hasSuffix("token-test.example") || $0.url!.host() == "evil.example" }
        XCTAssertTrue(requests.allSatisfy { $0.url!.host() != "evil.example" })
        for request in requests {
            let expected = request.url!.host() == "packages.token-test.example" ? "Bearer secret" : nil
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), expected, request.url!.absoluteString)
        }
    }

    /// A token is bound to the origin it was saved for: a source moved to another host, by any configuration
    /// change, doesn't send it there, and moving back sends it again.
    func testTokensGoOnlyToTheOriginTheyWereSavedFor() async throws {
        let fixture = try ThemeGalleryFixture(); defer { fixture.close() }
        let a = PackageSource(id: "team", name: "Team", url: URL(string: "https://a.token-bind.example/index.json")!)
        let b = PackageSource(id: "team", name: "Team", url: URL(string: "https://b.token-bind.example/index.json")!)
        for source in [a, b] { StubURLProtocol.serve(Data(#"{"packages":[]}"#.utf8), at: source.url) }
        let tokens = PackageSourceTokens.memory()
        let client = PackageStoreClient(packages: fixture.packages, indexURL: fixture.directory.appending(path: "none/index.json"),
                                        tokens: tokens, session: StubURLProtocol.session())
        func authorizations(_ host: String) -> [String?] {
            StubURLProtocol.requests.filter { $0.url?.host() == host }.map { $0.value(forHTTPHeaderField: "Authorization") }
        }
        await client.setPrivateSources([a])
        try await client.saveToken("  secret\n", for: a)
        XCTAssertEqual(tokens.read("source:team"), #"{"origin":"https://a.token-bind.example","token":"secret"}"#)
        _ = await client.catalog(reload: true)
        XCTAssertEqual(authorizations("a.token-bind.example"), ["Bearer secret"])
        let savedForA = await client.tokenIsSaved(for: "team")
        XCTAssertTrue(savedForA)

        await client.setPrivateSources([b])
        _ = await client.catalog(reload: true)
        _ = try await client.check(b, token: nil)
        _ = try await client.checkWithSavedToken(b)
        XCTAssertEqual(authorizations("b.token-bind.example").count, 3)
        XCTAssertEqual(authorizations("b.token-bind.example"), [nil, nil, nil])
        let savedForB = await client.tokenIsSaved(for: "team")
        XCTAssertFalse(savedForB)

        await client.setPrivateSources([a])
        _ = await client.catalog(reload: true)
        XCTAssertEqual(authorizations("a.token-bind.example"), ["Bearer secret", "Bearer secret"])
    }

    /// A plain value, as an older build or another tool might leave, names no origin, so it's never sent.
    func testAStoredTokenWithoutAnOriginIsNeverSent() async throws {
        let fixture = try ThemeGalleryFixture(); defer { fixture.close() }
        let team = PackageSource(id: "team", name: "Team", url: URL(string: "https://raw.token-bind.example/index.json")!)
        StubURLProtocol.serve(Data(#"{"packages":[]}"#.utf8), at: team.url)
        for stored in ["raw", #"{"token":"raw"}"#, #"{"origin":"not a url","token":"raw"}"#] {
            let client = PackageStoreClient(packages: fixture.packages, indexURL: fixture.directory.appending(path: "none/index.json"),
                                            tokens: .memory(["source:team": stored]), session: StubURLProtocol.session())
            await client.setPrivateSources([team])
            _ = await client.catalog(reload: true)
            _ = try await client.checkWithSavedToken(team)
            let saved = await client.tokenIsSaved(for: "team")
            XCTAssertFalse(saved, stored)
        }
        let requests = StubURLProtocol.requests.filter { $0.url?.host() == "raw.token-bind.example" }
        XCTAssertEqual(requests.count, 6)
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
    }

    /// Get claims an unclaimed installed copy only when its files are the ones the source published.
    func testGetClaimsAnUnclaimedCopyOnlyWhenItsFilesMatchTheDownload() async throws {
        let fixture = try ThemeGalleryFixture()
        defer { fixture.close() }
        let index = LocalPackageIndex(fixture: fixture)
        let entry = try await index.add()
        let published = fixture.directory.appending(path: "sources/store-theme")
        let installedFolder = fixture.packages.directory.appending(path: "store-theme")
        let client = PackageStoreClient(packages: fixture.packages, indexURL: index.url)
        // A folder install, and one from before install records, of the Store's own files become the Store's.
        for keepsRecord in [true, false] {
            _ = try fixture.packages.install(published)
            try fixture.write("", to: installedFolder.appending(path: "1/.DS_Store"))
            if !keepsRecord { try FileManager.default.removeItem(at: installedFolder.appending(path: PackageInstallRecord.fileName)) }
            _ = try await client.installWithoutReview(entry)
            XCTAssertEqual(try fixture.packages.record(id: "store-theme")?.source, PackageSource.storeID)
            try FileManager.default.removeItem(at: installedFolder)
        }
        // A folder with other files under the same ID and version keeps its record, and Get refuses it.
        let edited = fixture.directory.appending(path: "edited")
        try FileManager.default.copyItem(at: published, to: edited)
        try fixture.write(#"{"bar":{"height":40}}"#, to: edited.appending(path: "config.json"))
        _ = try fixture.packages.install(edited)
        do { _ = try await client.installWithoutReview(entry); XCTFail("Other files must not take the Store's name") }
        catch {
            XCTAssertEqual(error as? PackageSourceError, .differentFiles(package: "Store theme", version: "1", requested: "StableBar Store"))
            XCTAssertEqual(error.localizedDescription,
                           "Store theme 1 is already installed from a folder with different files. Uninstall it before getting it from StableBar Store.")
        }
        XCTAssertEqual(try fixture.packages.record(id: "store-theme"), .local)
        // An extra file is a difference too.
        try fixture.write(#"{"bar":{"height":31}}"#, to: installedFolder.appending(path: "1/config.json"))
        try fixture.write("echo", to: installedFolder.appending(path: "1/extra.sh"))
        do { _ = try await client.installWithoutReview(entry); XCTFail("An extra file is a difference") }
        catch PackageSourceError.differentFiles {}
        XCTAssertEqual(try fixture.packages.record(id: "store-theme"), .local)
    }

    func testSameContentsComparesFilesBytesAndLinks() throws {
        let fixture = try ThemeGalleryFixture()
        defer { fixture.close() }
        let a = fixture.directory.appending(path: "a"), b = fixture.directory.appending(path: "b")
        for folder in [a, b] {
            try fixture.write("one", to: folder.appending(path: "x/one.txt"))
            try FileManager.default.createSymbolicLink(atPath: folder.appending(path: "link").path, withDestinationPath: "x/one.txt")
        }
        try fixture.write("", to: b.appending(path: ".DS_Store"))
        XCTAssertTrue(try fixture.packages.sameContents(a, b))
        try fixture.write("two", to: b.appending(path: "x/one.txt"))
        XCTAssertFalse(try fixture.packages.sameContents(a, b))
        try fixture.write("one", to: b.appending(path: "x/one.txt"))
        try FileManager.default.removeItem(at: b.appending(path: "link"))
        try FileManager.default.createSymbolicLink(atPath: b.appending(path: "link").path, withDestinationPath: "x")
        XCTAssertFalse(try fixture.packages.sameContents(a, b))
        try FileManager.default.removeItem(at: b.appending(path: "link"))
        try fixture.write("one", to: b.appending(path: "link"))
        XCTAssertFalse(try fixture.packages.sameContents(a, b))
        try FileManager.default.removeItem(at: b.appending(path: "link"))
        XCTAssertFalse(try fixture.packages.sameContents(a, b))
        // A link out of the package is refused, as inspecting it would.
        try FileManager.default.createSymbolicLink(atPath: b.appending(path: "link").path, withDestinationPath: "/etc/hosts")
        XCTAssertThrowsError(try fixture.packages.sameContents(a, b))
    }

    /// Only Finder's litter is skipped: `.DS_Store` and AppleDouble `._` files, never a directory with such a name.
    func testSameContentsSkipsOnlyFinderFiles() throws {
        let fixture = try ThemeGalleryFixture()
        defer { fixture.close() }
        let a = fixture.directory.appending(path: "a"), b = fixture.directory.appending(path: "b")
        for folder in [a, b] {
            try fixture.write("one", to: folder.appending(path: "x/one.txt"))
            try fixture.write("same", to: folder.appending(path: "._x/run.sh"))
        }
        try fixture.write("finder", to: b.appending(path: ".DS_Store"))
        try fixture.write("finder", to: b.appending(path: "x/._one.txt"))
        XCTAssertTrue(try fixture.packages.sameContents(a, b))
        // A package can ship and run such a file: when both sides have it, its bytes count.
        try fixture.write("echo one", to: a.appending(path: "._run.sh"))
        try fixture.write("echo two", to: b.appending(path: "._run.sh"))
        XCTAssertFalse(try fixture.packages.sameContents(a, b))
        try fixture.write("echo one", to: b.appending(path: "._run.sh"))
        XCTAssertTrue(try fixture.packages.sameContents(a, b))
        try fixture.write("other", to: a.appending(path: ".DS_Store"))
        XCTAssertFalse(try fixture.packages.sameContents(a, b))
        try FileManager.default.removeItem(at: a.appending(path: ".DS_Store"))
        XCTAssertTrue(try fixture.packages.sameContents(a, b))
        // A difference inside a directory named like AppleDouble or Finder files is a difference.
        try fixture.write("other", to: b.appending(path: "._x/run.sh"))
        XCTAssertFalse(try fixture.packages.sameContents(a, b))
        try fixture.write("same", to: b.appending(path: "._x/run.sh"))
        try fixture.write("extra", to: b.appending(path: ".DS_Store.d/extra.sh"))
        XCTAssertFalse(try fixture.packages.sameContents(a, b))
        try FileManager.default.removeItem(at: b.appending(path: ".DS_Store.d"))
        try FileManager.default.removeItem(at: b.appending(path: ".DS_Store"))
        try fixture.write("x", to: b.appending(path: ".DS_Store/extra.sh"))
        XCTAssertFalse(try fixture.packages.sameContents(a, b))
        try FileManager.default.removeItem(at: b.appending(path: ".DS_Store"))
        // A file named like an install record inside a version folder is a package file.
        try fixture.write("{}", to: b.appending(path: PackageInstallRecord.fileName))
        XCTAssertFalse(try fixture.packages.sameContents(a, b))
    }

    func testInstallingByIDNeedsASourceWhenSeveralListIt() async throws {
        let fixture = try ThemeGalleryFixture(); defer { fixture.close() }
        let store = LocalPackageIndex(fixture: fixture)
        let acme = LocalPackageIndex(fixture: fixture, folder: "acme")
        _ = try await store.add(id: "clock", kind: "widgets", configuration: #"{"widgets":[]}"#, version: "2")
        _ = try await acme.add(id: "clock", kind: "widgets", configuration: #"{"widgets":[]}"#)
        let client = PackageStoreClient(packages: fixture.packages, indexURL: store.url)
        await client.setPrivateSources([PackageSource(id: "acme", name: "Acme", url: acme.url)])
        do { _ = try await client.install(id: "clock", from: nil); XCTFail("Two sources list clock") }
        catch { XCTAssertEqual(error.localizedDescription, "clock is listed in StableBar Store and Acme. Add --source stablebar or --source acme.") }
        do { _ = try await client.install(id: "clock", from: "nope"); XCTFail("No source is named nope") }
        catch { XCTAssertEqual(error.localizedDescription, "No package source named nope. Configured: stablebar, acme.") }
        do { _ = try await client.install(id: "missing", from: "acme"); XCTFail("Acme doesn't list missing") }
        catch WidgetPackageError.notInStore("missing") {}
        XCTAssertTrue(try fixture.packages.list().isEmpty)

        let installed = try await client.install(id: "clock", from: "acme")
        XCTAssertEqual(installed.manifest.id, "clock")
        XCTAssertEqual(try fixture.packages.record(id: "clock")?.source, "acme")
        do { _ = try await client.install(id: "clock", from: "stablebar"); XCTFail("Acme installed clock") }
        catch PackageSourceError.claimed {}
        XCTAssertEqual(try fixture.packages.list().map(\.version), ["1"])
    }

    func testInstallingByIDUsesTheOnlySourceThatListsIt() async throws {
        let fixture = try ThemeGalleryFixture(); defer { fixture.close() }
        let store = LocalPackageIndex(fixture: fixture)
        let acme = LocalPackageIndex(fixture: fixture, folder: "acme")
        _ = try await store.add(id: "weather", kind: "widgets", configuration: #"{"widgets":[]}"#)
        _ = try await acme.add(id: "clock", kind: "widgets", configuration: #"{"widgets":[]}"#)
        let client = PackageStoreClient(packages: fixture.packages, indexURL: store.url)
        await client.setPrivateSources([PackageSource(id: "acme", name: "Acme", url: acme.url)])
        _ = try await client.install(id: "clock", from: nil)
        XCTAssertEqual(try fixture.packages.record(id: "clock")?.source, "acme")
    }

    func testInstallingByIDFromAnUnreachableSourceSaysWhy() async throws {
        let fixture = try ThemeGalleryFixture(); defer { fixture.close() }
        let store = LocalPackageIndex(fixture: fixture)
        _ = try await store.add(id: "weather", kind: "widgets", configuration: #"{"widgets":[]}"#)
        try fixture.write("<html>Sign in</html>", to: fixture.directory.appending(path: "sso/index.json"))
        let client = PackageStoreClient(packages: fixture.packages, indexURL: store.url)
        await client.setPrivateSources([PackageSource(id: "sso", name: "SSO", url: fixture.directory.appending(path: "sso/index.json"))])
        do { _ = try await client.install(id: "clock", from: nil); XCTFail("No reachable source lists clock") }
        catch { XCTAssertEqual(error.localizedDescription, "SSO is unavailable: the index isn’t a StableBar package index.") }
        // SSO might list weather too, so the Store's copy isn't picked without --source.
        do { _ = try await client.install(id: "weather", from: nil); XCTFail("SSO might also list weather") }
        catch {
            XCTAssertEqual(error.localizedDescription,
                           "SSO is unavailable: the index isn’t a StableBar package index. It may also list weather. Add --source stablebar to install from StableBar Store.")
        }
        XCTAssertTrue(try fixture.packages.list().isEmpty)
        XCTAssertNil(try fixture.packages.record(id: "weather"))
        _ = try await client.install(id: "weather", from: "stablebar")
        XCTAssertEqual(try fixture.packages.record(id: "weather")?.source, "stablebar")
    }

    func testRelativeScreenshotsResolveAgainstTheIndex() async throws {
        let fixture = try ThemeGalleryFixture(); defer { fixture.close() }
        let acme = LocalPackageIndex(fixture: fixture, folder: "acme")
        _ = try await acme.add(id: "clock", screenshot: "shots/clock.png")
        try fixture.write("png", to: fixture.directory.appending(path: "acme/shots/clock.png"))
        let client = PackageStoreClient(packages: fixture.packages, indexURL: fixture.directory.appending(path: "none/index.json"))
        await client.setPrivateSources([PackageSource(id: "acme", name: "Acme", url: acme.url)])
        let catalog = await client.catalog()
        let entry = try XCTUnwrap(catalog.entries.first)
        XCTAssertEqual(entry.screenshot, fixture.directory.appending(path: "acme/shots/clock.png").absoluteURL)
        let screenshot = try await client.screenshot(for: entry)
        XCTAssertEqual(screenshot, Data("png".utf8))
    }
}
