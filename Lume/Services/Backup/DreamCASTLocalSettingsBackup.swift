#if os(iOS)
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Portable local preferences export. This deliberately does NOT copy live
/// SQLite/SwiftData stores, Keychain entries, or account secrets.
struct DreamCASTSettingsFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var contents: Data

    init(contents: Data) { self.contents = contents }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        contents = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: contents)
    }
}

enum DreamCASTLocalSettingsBackup {
    private struct Archive: Codable {
        let formatVersion: Int
        let createdAt: Date
        let preferences: [String: Data]
    }

    // Never export account credentials or operating-system defaults. Prefer
    // excluding an unknown setting over exposing a token in a shared file.
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

    static func exportSettings() throws -> DreamCASTSettingsFile {
        var values: [String: Data] = [:]
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() where allowed(key) {
            // Wrap every value in a dictionary: Foundation's property-list API
            // handles this consistently for String, Bool, Number, Data, and arrays.
            if let data = try? PropertyListSerialization.data(
                fromPropertyList: ["value": value], format: .binary, options: 0
            ) {
                values[key] = data
            }
        }
        let archive = Archive(formatVersion: 1, createdAt: .now, preferences: values)
        return DreamCASTSettingsFile(contents: try JSONEncoder().encode(archive))
    }

    @discardableResult
    static func restoreSettings(from data: Data) throws -> Int {
        guard data.count <= 8_000_000 else { throw CocoaError(.fileReadTooLarge) }
        let archive = try JSONDecoder().decode(Archive.self, from: data)
        guard archive.formatVersion == 1 else { throw CocoaError(.fileReadCorruptFile) }

        // Parse every entry before changing any saved setting.
        var staged: [String: Any] = [:]
        for (key, encoded) in archive.preferences where allowed(key) {
            guard let entry = try PropertyListSerialization.propertyList(
                from: encoded, format: nil
            ) as? [String: Any], let value = entry["value"] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            staged[key] = value
        }

        for (key, value) in staged { UserDefaults.standard.set(value, forKey: key) }
        // Never allow a backup from an older installation to re-enable cloud.
        UserDefaults.standard.set("off", forKey: "sync.backend")
        return staged.count
    }
}

/// Settings-only backup. Media catalogs, playlists and watched records remain
/// in the local SwiftData database, unchanged by this import.
struct DreamCASTBackupSettingsSection: View {
    @State private var exportedFile: DreamCASTSettingsFile?
    @State private var exporting = false
    @State private var importing = false
    @State private var notice: String?

    var body: some View {
        Section {
            Button {
                do {
                    exportedFile = try DreamCASTLocalSettingsBackup.exportSettings()
                    exporting = true
                } catch {
                    notice = "Could not prepare backup: \(error.localizedDescription)"
                }
            } label: {
                Label("Back Up Settings to File", systemImage: "square.and.arrow.up")
            }

            Button {
                importing = true
            } label: {
                Label("Restore Settings from File", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Local Backup & Restore")
        } footer: {
            Text("Saves your app preferences to a JSON file in Files. Passwords, account keys, playlists, and watched history are not included. Importing a file changes saved settings, not your media library. Relaunch the app after restoring.")
        }
        .fileExporter(
            isPresented: $exporting,
            document: $exportedFile,
            contentType: .json,
            defaultFilename: "DreamCAST-TV-settings"
        ) { result in
            if case let .failure(error) = result {
                notice = "Could not save backup: \(error.localizedDescription)"
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                let count = try DreamCASTLocalSettingsBackup.restoreSettings(from: data)
                notice = "Restored \(count) settings. Close and reopen DreamCAST TV to apply them."
            } catch {
                notice = "Could not restore settings: \(error.localizedDescription)"
            }
        }
        .alert("Local Backup & Restore", isPresented: Binding(
            get: { notice != nil },
            set: { if !$0 { notice = nil } }
        )) {
            Button("OK") { notice = nil }
        } message: {
            Text(notice ?? "")
        }
    }
}
#endif
