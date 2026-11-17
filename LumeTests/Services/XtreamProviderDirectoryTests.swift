import Foundation
@testable import Lume
import Testing

struct XtreamProviderDirectoryTests {
    @Test func `rejects unsafe provider addresses`() {
        for address in ["file:///tmp/list", "ftp://example.test", "https://user:pass@example.test", "https://example.test?token=x", "https://example.test/#x"] {
            #expect(XtreamProvider.normalizedAddress(address) == nil)
        }
        #expect(XtreamProvider.normalizedAddress(" https://example.test:8443/base/ ") == "https://example.test:8443/base")
    }

    @Test func `direct playback links follow a changed base with their query intact`() throws {
        let provider = XtreamProvider(id: "DREAMCAST", name: "DreamCAST TV", serverURL: "https://new.example.test/base",
                                      enabled: true, previousURLs: ["http://old.example.test/root"])
        let old = try #require(URL(string: "http://old.example.test/root/live/user/pass/123.ts?token=abc"))
        let result = XtreamProviderDirectory.resolvedURL(old, provider: provider, storedAddress: "http://old.example.test/root")
        #expect(result.absoluteString == "https://new.example.test/base/live/user/pass/123.ts?token=abc")
        let cdn = try #require(URL(string: "https://cdn.example.test/live/123.ts"))
        #expect(XtreamProviderDirectory.resolvedURL(cdn, provider: provider, storedAddress: "http://old.example.test/root") == cdn)
        let otherPath = try #require(URL(string: "http://old.example.test/root-other/live/123.ts"))
        #expect(XtreamProviderDirectory.resolvedURL(otherPath, provider: provider, storedAddress: "http://old.example.test/root") == otherPath)
    }

    @Test func `directory requires all four stable IDs and unique address ownership`() {
        let providers = XtreamProvider.catalog.enumerated().map { index, item in
            XtreamProvider(id: item.0, name: item.1, serverURL: "https://server\(index).example.test", enabled: true, previousURLs: [])
        }
        #expect(XtreamProviderEnvelope(schemaVersion: 1, revision: 2, providers: providers).isValid)
        #expect(!XtreamProviderEnvelope(schemaVersion: 2, revision: 2, providers: providers).isValid)
        #expect(!XtreamProviderEnvelope(schemaVersion: 1, revision: 2, providers: Array(providers.dropLast())).isValid)
        let conflict = XtreamProvider(id: providers[0].id, name: providers[0].name, serverURL: providers[1].serverURL,
                                     enabled: true, previousURLs: [])
        #expect(!XtreamProviderEnvelope(schemaVersion: 1, revision: 2, providers: [conflict] + Array(providers.dropFirst())).isValid)
    }
}
