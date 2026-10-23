import Foundation
import Testing
@testable import StableBar

struct PackageSourceLinkTests {
    private static let index = "https://gitlab.example.com/api/v4/projects/1/packages/generic/stablebar/store/index.json"

    @Test func joinLinksParseValidateKeepAnOptionalIDAndNeverCarryATokenBack() throws {
        let index = Self.index
        let encoded = index.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let query = (index + "?ref=main").addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let link = try #require(PackageSourceLink(url: URL(string: "stablebar://add-source?name=Acme&url=\(encoded)&id=acme&token=abc")!))
        #expect(link == PackageSourceLink(id: "acme", name: "Acme", url: URL(string: index)!))
        #expect(!link.link.absoluteString.contains("token"))
        #expect(PackageSourceLink(url: link.link) == link)
        for bad in ["stablebar://add-source?name=Acme&url=http%3A%2F%2Fa.example%2Findex.json",
                    "stablebar://other?name=Acme&url=\(encoded)", "stablebar://add-source?name=Acme",
                    "https://add-source?name=Acme&url=\(encoded)", "stablebar://add-source?name=Acme&url=\(encoded)&id=a%20b",
                    "stablebar://add-source?name=Acme&url=\(query)", "stablebar://add-source?name=%20&url=\(encoded)",
                    "stablebar://add-source?name=Acme&url=\(encoded)&id=stablebar"] {
            #expect(PackageSourceLink(url: URL(string: bad)!) == nil, "\(bad)")
        }
        let withoutID = try #require(PackageSourceLink(url: URL(string: "stablebar://add-source?name=Acme&url=\(encoded)")!))
        #expect(withoutID.id == nil)
    }

    @Test func aSourceMakesALinkWithItsNameURLAndID() throws {
        let source = PackageSource(id: "acme", name: "Acme & Co", url: URL(string: Self.index)!)
        let link = PackageSourceLink(source: source)
        #expect(link.id == "acme" && link.name == "Acme & Co")
        #expect(link.link.scheme == "stablebar" && link.link.host() == "add-source")
        #expect(PackageSourceLink(url: link.link) == link)
    }

    @MainActor @Test func linkDraftsPrefillAndDetectKnownSources() async throws {
        let link = PackageSourceLink(id: "acme", name: "Acme", url: URL(string: "https://a.example/index.json")!)
        let fresh = PackageSourceDraft(existing: [.store], link: link)
        #expect(fresh.fromLink && fresh.name == "Acme" && fresh.id == "acme")
        #expect(fresh.urlText == "https://a.example/index.json" && fresh.token.isEmpty && fresh.source != nil)
        #expect(!PackageSourceDraft(existing: [.store]).fromLink)

        // A taken id falls back to one derived from the name.
        let known = PackageSource(id: "acme", name: "Team Acme", url: URL(string: "https://a.example/index.json")!)
        let taken = PackageSourceDraft(existing: [.store, known], link: link)
        #expect(taken.id == "acme-2")
        // A link without an id derives it from the name.
        #expect(PackageSourceDraft(existing: [.store], link: PackageSourceLink(id: nil, name: "Acme Tools", url: link.url)).id == "acme-tools")

        let fixture = try ThemeGalleryFixture(#"{"widgets":[]}"#)
        defer { fixture.close() }
        let store = try fixture.store()
        defer { store.stop() }
        await taken.check(using: PackageLibrary(store: store))
        #expect(taken.state == .duplicate("Team Acme"))
    }

    private static let teamConfiguration = #"{"widgets":[],"packageSources":[{"id":"acme","name":"Acme","url":"https://a.example/index.json"}]}"#

    @MainActor @Test func linkDraftsJudgeTheConfiguredSourcesBeforeAnyCatalogLoads() async throws {
        let fixture = try ThemeGalleryFixture(Self.teamConfiguration)
        defer { fixture.close() }
        let store = try fixture.store()
        defer { store.stop() }
        let library = PackageLibrary(store: store)
        // No catalog load yet: the library only lists the Store, but the configuration has acme.
        #expect(library.sources.map(\.id) == ["stablebar"])
        let sameID = PackageSourceLink(id: "acme", name: "Acme", url: URL(string: "https://b.example/index.json")!)
        #expect(PackageSourceDraft(library: library, link: sameID).id == "acme-2")
        let sameURL = PackageSourceLink(id: "other", name: "Other", url: URL(string: "https://a.example/index.json")!)
        let draft = PackageSourceDraft(library: library, link: sameURL)
        await draft.check(using: library)
        #expect(draft.state == .duplicate("Acme"))
    }

    @MainActor @Test func addingASourceNeverReplacesAConfiguredOne() async throws {
        let fixture = try ThemeGalleryFixture(Self.teamConfiguration)
        defer { fixture.close() }
        let store = try fixture.store()
        defer { store.stop() }
        let library = PackageLibrary(store: store)
        let before = try Data(contentsOf: fixture.url)
        let other = PackageSource(id: "acme", name: "Impostor", url: URL(string: "https://evil.example/index.json")!)
        await #expect(throws: PackageSourceError.idTaken("acme")) { try await library.addSource(other, token: "") }
        try store.customizationHistory.flush()
        #expect(try Data(contentsOf: fixture.url) == before)
    }

    @Test func sourcesRefuseACredentialInTheURLEverywhere() throws {
        let url = URL(string: "https://oauth2:glpat-x@gitlab.example/i.json")!
        #expect(throws: PackageSourceError.credentialsInURL("acme")) { try PackageSource.validated(id: "acme", name: "Acme", url: url) }
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode([PackageSource].self, from: Data(#"[{"id":"acme","name":"Acme","url":"https://oauth2:glpat-x@gitlab.example/i.json"}]"#.utf8))
        }
        let encoded = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        #expect(PackageSourceLink(url: URL(string: "stablebar://add-source?name=Acme&url=\(encoded)")!) == nil)
        #expect(PackageSourceError.credentialsInURL("acme").errorDescription?.contains("without a user name or password") == true)
    }
}
