#if os(tvOS)
import Foundation

/// The same version-1 JSON settings archive used on iOS.
/// No SQLite stores, Keychain entries, passwords, or account tokens are exported.
nonisolated enum DreamCASTLocalSettingsBackup {
    private struct Archive: Codable {
        let formatVersion: Int
        let createdAt: Date
        let preferences: [String: Data]
    }

    static let maxBytes = 8_000_000

    private static func allowed(_ key: String) -> Bool {
        let k = key.lowercased()
        if k.hasPrefix("apple") || k.hasPrefix("ns") || k.hasPrefix("com.apple")
            || k.hasPrefix("uikit") || k.hasPrefix("ui")
            || k.hasPrefix("lumecloud") || k.hasPrefix("icloud")
            || k.hasPrefix("premium.") || k.hasPrefix("sync.backend") {
            return false
        }
        let sensitive = ["password", "passwd", "secret", "token", "credential",
                         "auth", "apikey", "api_key", "accesskey", "privatekey",
                         "session", "cookie", "refreshkey", "recovery"]
        return !sensitive.contains(where: { k.contains($0) })
    }

    static func exportSettings() throws -> Data {
        var values: [String: Data] = [:]
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() where allowed(key) {
            guard let encoded = try? PropertyListSerialization.data(
                fromPropertyList: ["value": value], format: .binary, options: 0
            ) else { continue }
            values[key] = encoded
        }
        let archive = Archive(formatVersion: 1, createdAt: .now, preferences: values)
        let data = try JSONEncoder().encode(archive)
        guard data.count <= maxBytes else { throw CocoaError(.fileReadTooLarge) }
        return data
    }

    private static func stage(_ data: Data) throws -> [String: Any] {
        guard data.count <= maxBytes else { throw CocoaError(.fileReadTooLarge) }
        let archive = try JSONDecoder().decode(Archive.self, from: data)
        guard archive.formatVersion == 1 else { throw CocoaError(.fileReadCorruptFile) }
        var staged: [String: Any] = [:]
        for (key, encoded) in archive.preferences where allowed(key) {
            guard let entry = try PropertyListSerialization.propertyList(
                from: encoded, format: nil
            ) as? [String: Any], let value = entry["value"] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            staged[key] = value
        }
        return staged
    }

    /// Checks the entire file without writing any settings.
    static func inspectRestore(_ data: Data) throws -> Int {
        try stage(data).count
    }

    @discardableResult
    static func restoreSettings(from data: Data) throws -> Int {
        let staged = try stage(data)
        for (key, value) in staged {
            UserDefaults.standard.set(value, forKey: key)
        }
        // A settings file cannot turn cloud sync back on.
        UserDefaults.standard.set("off", forKey: "sync.backend")
        return staged.count
    }
}
#endif
