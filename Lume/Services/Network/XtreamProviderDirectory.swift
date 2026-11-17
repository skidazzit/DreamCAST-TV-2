import Foundation
import Synchronization

/// Shared, credential-free directory used by UI, sync, guide and playback.
nonisolated struct XtreamProvider: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let serverURL: String
    let enabled: Bool
    let previousURLs: [String]

    static let catalog = [
        ("DREAMCAST", "DreamCAST TV"), ("KLEPTO", "Klepto TV"),
        ("STRONG", "Strong"), ("IPTVEDITOR", "IPTVeditor")
    ]

    static var bundled: [XtreamProvider] {
        catalog.compactMap { id, name in
            guard let address = Bundle.main.object(forInfoDictionaryKey: "XtreamProvider\(id)URL") as? String,
                  let normalized = normalizedAddress(address) else { return nil }
            return XtreamProvider(id: id, name: name, serverURL: normalized, enabled: true, previousURLs: [])
        }
    }

    static var available: [XtreamProvider] { XtreamProviderDirectory.providers.filter(\.enabled) }

    static func normalizedAddress(_ address: String) -> String? {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return nil }
        var value = url.absoluteString
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }
}

nonisolated struct XtreamProviderEnvelope: Codable, Sendable {
    let schemaVersion: Int
    let revision: Int
    let providers: [XtreamProvider]

    var isValid: Bool {
        guard schemaVersion == 1, revision >= 0,
              providers.count == XtreamProvider.catalog.count,
              Set(providers.map(\.id)) == Set(XtreamProvider.catalog.map { $0.0 }) else { return false }
        var owners: [String: String] = [:]
        for provider in providers {
            for address in [provider.serverURL] + provider.previousURLs {
                guard let normalized = XtreamProvider.normalizedAddress(address) else { return false }
                if let owner = owners[normalized], owner != provider.id { return false }
                owners[normalized] = provider.id
            }
        }
        return true
    }
}

nonisolated enum XtreamProviderDirectory {
    private static let cacheKey = "dreamcast.xtream.providerDirectory.v1"
    private static let state = Mutex<XtreamProviderEnvelope?>(loadCache())

    private static func loadCache() -> XtreamProviderEnvelope? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let envelope = try? JSONDecoder().decode(XtreamProviderEnvelope.self, from: data),
              envelope.isValid else { return nil }
        return envelope
    }

    static var providers: [XtreamProvider] {
        let snapshot = state.withLock { $0 }
        guard let snapshot else { return XtreamProvider.bundled }
        // Names and order are fixed by the app; the website only changes addresses.
        return XtreamProvider.catalog.compactMap { id, name in
            guard let provider = snapshot.providers.first(where: { $0.id == id }) else { return nil }
            return XtreamProvider(id: id, name: name, serverURL: provider.serverURL,
                                  enabled: provider.enabled, previousURLs: provider.previousURLs)
        }
    }

    static func accept(_ envelope: XtreamProviderEnvelope) {
        guard envelope.isValid else { return }
        state.withLock { current in
            guard envelope.revision >= (current?.revision ?? 0) else { return }
            current = envelope
            if let data = try? JSONEncoder().encode(envelope) {
                UserDefaults.standard.set(data, forKey: cacheKey)
            }
        }
    }

    static func provider(id: String? = nil, address: String) -> XtreamProvider? {
        let list = providers
        if let id, let match = list.first(where: { $0.id == id }) { return match }
        guard let normalized = XtreamProvider.normalizedAddress(address) else { return nil }
        return list.first { provider in
            let bundled = XtreamProvider.bundled.first(where: { $0.id == provider.id })
            return ([provider.serverURL] + provider.previousURLs + [bundled?.serverURL].compactMap { $0 })
                .contains { XtreamProvider.normalizedAddress($0) == normalized }
        }
    }

    static func resolvedGuideURL(_ address: String) -> String {
        guard let url = URL(string: address) else { return address }
        for provider in providers {
            let resolved = resolvedURL(url, provider: provider, storedAddress: provider.serverURL)
            if resolved != url { return resolved.absoluteString }
        }
        return address
    }

    /// Only rewrites direct links on a known provider base; CDN links stay intact.
    static func resolvedDirectURL(_ url: URL, playlist: Playlist) -> URL {
        guard playlist.sourceType == .xtream,
              let provider = provider(id: playlist.xtreamProviderID, address: playlist.serverURL) else { return url }
        return resolvedURL(url, provider: provider, storedAddress: playlist.serverURL)
    }

    static func resolvedURL(_ url: URL, provider: XtreamProvider, storedAddress: String) -> URL {
        guard let target = URLComponents(string: provider.serverURL),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        let bundled = XtreamProvider.bundled.first(where: { $0.id == provider.id })
        for address in [storedAddress, provider.serverURL] + provider.previousURLs + [bundled?.serverURL].compactMap({ $0 }) {
            guard let base = URLComponents(string: address),
                  components.scheme?.lowercased() == base.scheme?.lowercased(),
                  components.host?.lowercased() == base.host?.lowercased(),
                  components.port == base.port else { continue }
            var prefix = base.percentEncodedPath
            while prefix.hasSuffix("/") { prefix.removeLast() }
            guard components.percentEncodedPath == prefix || components.percentEncodedPath.hasPrefix(prefix + "/") else { continue }
            let suffix = String(components.percentEncodedPath.dropFirst(prefix.count))
            components.scheme = target.scheme
            components.host = target.host
            components.port = target.port
            components.percentEncodedPath = target.percentEncodedPath + suffix
            return components.url ?? url
        }
        return url
    }
}

/// Bounded, deduplicated background checks. Failed checks retain the last good copy.
actor XtreamProviderRefresh {
    static let shared = XtreamProviderRefresh()
    private var lastAttempt: Date?
    private var inFlight: Task<XtreamProviderEnvelope?, Never>?

    func refresh() async {
        if let inFlight { _ = await inFlight.value; return }
        if let lastAttempt, Date().timeIntervalSince(lastAttempt) < 60 { return }
        lastAttempt = Date()
        let task = Task {
            let envelope = await Self.download()
            if let envelope { XtreamProviderDirectory.accept(envelope) }
            return envelope
        }
        inFlight = task
        _ = await task.value
        inFlight = nil
    }

    private nonisolated static func download() async -> XtreamProviderEnvelope? {
        let address = (Bundle.main.object(forInfoDictionaryKey: "XtreamProviderDirectoryURL") as? String)
            ?? "https://dreamcast-server-manager.inquisitivemagpie.chatgpt.site/api/providers"
        guard let url = URL(string: address), url.scheme == "https" else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 8
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(from: url)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  response.url?.scheme == "https", response.url?.host == url.host,
                  data.count <= 131072 else { return nil }
            let envelope = try JSONDecoder().decode(XtreamProviderEnvelope.self, from: data)
            return envelope.isValid ? envelope : nil
        } catch { return nil }
    }
}

nonisolated extension Playlist {
    var effectiveXtreamServerURL: String {
        guard sourceType == .xtream else { return serverURL }
        return XtreamProviderDirectory.provider(id: xtreamProviderID, address: serverURL)?.serverURL ?? serverURL
    }
}
