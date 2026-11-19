import Foundation
@testable import Lume
import Testing

struct XtreamProviderDirectoryTests {
    @Test func `Xtream UI subtitle never exposes backend server address`() {
        let address = "https://unmapped-playlist-source.example.invalid:9876/private"
        let xtream = Playlist(name: "My IPTV", serverURL: address, username: "user", password: "pass")
        #expect(xtream.sourceType == .xtream)
        #expect(!xtream.displaySourceLabel.contains("example.invalid"))
        #expect(!xtream.displaySourceLabel.contains("https://"))

        let m3u = Playlist(name: "M3U", m3uURL: "https://example.invalid/playlist.m3u")
        #expect(m3u.displaySourceLabel == m3u.displayURL)
    }

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
        #expect(!XtreamProviderEnvelope(schemaVersion: 3, revision: 2, providers: providers).isValid)
        #expect(!XtreamProviderEnvelope(schemaVersion: 1, revision: 2, providers: Array(providers.dropLast())).isValid)
        let conflict = XtreamProvider(id: providers[0].id, name: providers[0].name, serverURL: providers[1].serverURL,
                                     enabled: true, previousURLs: [])
        #expect(!XtreamProviderEnvelope(schemaVersion: 1, revision: 2, providers: [conflict] + Array(providers.dropFirst())).isValid)
    }
    @Test func `dynamic directory accepts new providers and a fully empty list`() {
        let provider = XtreamProvider(id: "CUSTOM_NEW", name: "New Provider", serverURL: "https://new.example.test",
                                      enabled: true, previousURLs: [])
        let directory = XtreamProviderEnvelope(schemaVersion: 2, revision: 3, providers: [provider])
        #expect(directory.isValid)
        #expect(directory.allProviders.map(\.id) == ["CUSTOM_NEW"])
        #expect(XtreamProviderEnvelope(schemaVersion: 2, revision: 4, providers: []).isValid)
    }

    @Test func `deleted providers remain available for resolution but not selection`() {
        let retired = XtreamProvider(id: "CUSTOM_OLD", name: "Old Provider", serverURL: "https://old.example.test",
                                    enabled: false, previousURLs: [])
        let directory = XtreamProviderEnvelope(schemaVersion: 2, revision: 4, providers: [], retiredProviders: [retired])
        #expect(directory.isValid)
        #expect(directory.allProviders.map(\.id) == ["CUSTOM_OLD"])
        #expect(directory.allProviders.filter(\.enabled).isEmpty)
        let reused = XtreamProvider(id: "CUSTOM_NEW", name: "New Provider", serverURL: retired.serverURL,
                                   enabled: true, previousURLs: [])
        #expect(!XtreamProviderEnvelope(schemaVersion: 2, revision: 5, providers: [reused], retiredProviders: [retired]).isValid)
    }

}
