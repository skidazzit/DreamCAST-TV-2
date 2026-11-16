#if os(iOS)
import Foundation
import CryptoKit
import CommonCrypto
import SwiftData
import SwiftUI
import UIKit
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
    enum BackupError: LocalizedError {
        case passwordRequired
        case weakPassword
        case invalidPassword
        case invalidPlaylist
        var errorDescription: String? {
            switch self {
            case .passwordRequired: "Enter the password used to protect this backup."
            case .weakPassword: "Use at least 8 characters to protect your playlist credentials."
            case .invalidPassword: "Wrong backup password, or the backup file is damaged."
            case .invalidPlaylist: "The backup contains an invalid playlist record."
            }
        }
    }

    private struct Archive: Codable {
        let formatVersion: Int
        let createdAt: Date
        let preferences: [String: Data]
        // Version 2 includes encrypted playlist setup; version 1 files still restore.
        var playlistSalt: Data?
        var encryptedPlaylists: Data?
    }

    private struct ProtectedPayload: Codable {
        let preferences: [String: Data]
        let playlists: [PlaylistRecord]
    }

    private struct PlaylistRecord: Codable {
        var name: String
        var serverURL: String
        var username: String
        var password: String
        var sourceTypeRaw: String
        var epgURL: String?
        var streamFormatRaw: String
        var macAddress: String?
        var syncEnabled: Bool
        var hiddenTabsRaw: String
        var combinedTypesRaw: String
        var combinedPriority: Int?

        init(_ p: Playlist) {
            name = p.name
            serverURL = p.serverURL
            username = p.username
            password = p.password
            sourceTypeRaw = p.sourceTypeRaw
            epgURL = p.epgURL
            streamFormatRaw = p.streamFormatRaw
            macAddress = p.macAddress
            syncEnabled = p.syncEnabled
            hiddenTabsRaw = p.hiddenTabsRaw
            combinedTypesRaw = p.combinedTypesRaw
            combinedPriority = p.combinedPriority
        }

        func makePlaylist() throws -> Playlist {
            guard !name.isEmpty, !serverURL.isEmpty,
                  PlaylistSourceType(rawValue: sourceTypeRaw) != nil else {
                throw BackupError.invalidPlaylist
            }
            let p = Playlist(name: name, serverURL: serverURL,
                             username: username, password: password)
            p.sourceTypeRaw = sourceTypeRaw
            p.epgURL = epgURL
            p.streamFormatRaw = PlaylistStreamFormat(rawValue: streamFormatRaw)?.rawValue
                ?? PlaylistStreamFormat.automatic.rawValue
            p.macAddress = macAddress
            p.syncEnabled = syncEnabled
            p.hiddenTabsRaw = hiddenTabsRaw
            p.combinedTypesRaw = combinedTypesRaw
            p.combinedPriority = combinedPriority
            // Never import old access/session tokens or downloaded catalog data.
            return p
        }
    }

    private static func key(password: String, salt: Data) throws -> SymmetricKey {
        guard !password.isEmpty else { throw BackupError.passwordRequired }
        var derived = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { bytes in
            password.withCString { pwd in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2), pwd, password.utf8.count,
                    bytes.bindMemory(to: UInt8.self).baseAddress!, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 210_000,
                    &derived, derived.count
                )
            }
        }
        guard status == kCCSuccess else { throw BackupError.invalidPassword }
        return SymmetricKey(data: Data(derived))
    }

    static func hasEncryptedPlaylists(_ data: Data) throws -> Bool {
        let archive = try JSONDecoder().decode(Archive.self, from: data)
        return archive.formatVersion == 2 && archive.encryptedPlaylists != nil
    }

    // Exclude secrets from the unencrypted settings section.
    private static func allowed(_ key: String) -> Bool {
        let k = key.lowercased()
        if k.hasPrefix("apple") || k.hasPrefix("ns") || k.hasPrefix("com.apple")
            || k.hasPrefix("uikit") || k.hasPrefix("ui")
            || k.hasPrefix("lumecloud") || k.hasPrefix("icloud")
            || k.hasPrefix("premium.") || k.hasPrefix("sync.backend") { return false }
        let sensitive = ["password", "passwd", "secret", "token", "credential",
                         "auth", "apikey", "api_key", "accesskey", "privatekey",
                         "session", "cookie", "refreshkey", "recovery"]
        return !sensitive.contains(where: { k.contains($0) })
    }

    static func exportSettings(playlists: [Playlist] = [], password: String? = nil) throws -> DreamCASTSettingsFile {
        var values: [String: Data] = [:]
        for (name, value) in UserDefaults.standard.dictionaryRepresentation() where allowed(name) {
            if let data = try? PropertyListSerialization.data(
                fromPropertyList: ["value": value], format: .binary, options: 0
            ) { values[name] = data }
        }
        var archive = Archive(formatVersion: 1, createdAt: .now,
                              preferences: values, playlistSalt: nil, encryptedPlaylists: nil)
        if let password {
            guard password.count >= 8 else { throw BackupError.weakPassword }
            // Both saved preferences and IPTV connection data must stay
            // encrypted. Never leave private values in outer JSON fields.
            let records = try JSONEncoder().encode(
                ProtectedPayload(preferences: values, playlists: playlists.map(PlaylistRecord.init))
            )
            let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
            let sealed = try AES.GCM.seal(records, using: key(password: password, salt: salt))
            archive = Archive(formatVersion: 2, createdAt: .now,
                              preferences: [:], playlistSalt: salt,
                              encryptedPlaylists: sealed.combined)
        }
        return DreamCASTSettingsFile(contents: try JSONEncoder().encode(archive))
    }

    @discardableResult
    static func restoreSettings(from data: Data, password: String? = nil,
                                context: ModelContext? = nil) throws -> Int {
        guard data.count <= 8_000_000 else { throw CocoaError(.fileReadTooLarge) }
        let archive = try JSONDecoder().decode(Archive.self, from: data)
        guard archive.formatVersion == 1 || archive.formatVersion == 2 else {
            throw CocoaError(.fileReadCorruptFile)
        }

        var savedPreferences = archive.preferences
        var imported: [Playlist] = []
        if archive.formatVersion == 2 {
            guard let salt = archive.playlistSalt,
                  let ciphertext = archive.encryptedPlaylists,
                  let password else { throw BackupError.passwordRequired }
            do {
                let box = try AES.GCM.SealedBox(combined: ciphertext)
                let clear = try AES.GCM.open(box, using: key(password: password, salt: salt))
                let payload = try JSONDecoder().decode(ProtectedPayload.self, from: clear)
                savedPreferences = payload.preferences
                imported = try payload.playlists.map { try $0.makePlaylist() }
            } catch {
                throw BackupError.invalidPassword
            }
        }

        // Validate every preference before making any changes on this device.
        var staged: [String: Any] = [:]
        for (name, encoded) in savedPreferences where allowed(name) {
            guard let entry = try PropertyListSerialization.propertyList(
                from: encoded, format: nil
            ) as? [String: Any], let value = entry["value"] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            staged[name] = value
        }
        if archive.formatVersion == 2 {
            guard let context else { throw BackupError.invalidPlaylist }
            let existing = try context.fetch(FetchDescriptor<Playlist>())
            // Skip sources already installed and repeated records in one file.
            var seen = Set(existing.map {
                "\($0.sourceTypeRaw)|\($0.serverURL)|\($0.username)"
            })
            for playlist in imported {
                let identifier = "\(playlist.sourceTypeRaw)|\(playlist.serverURL)|\(playlist.username)"
                guard seen.insert(identifier).inserted else { continue }
                context.insert(playlist)
            }
            try context.save()
        }
        for (name, value) in staged { UserDefaults.standard.set(value, forKey: name) }
        UserDefaults.standard.set("off", forKey: "sync.backend")
        return staged.count
    }
}

/// Backup includes encrypted IPTV setup details, but not channel catalogs or history.
struct DreamCASTBackupSettingsSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var playlists: [Playlist]
    @State private var exportDocument: DreamCASTSettingsFile?
    @State private var exporting = false
    @State private var importing = false
    @State private var exportPrompt = false
    @State private var restorePrompt = false
    @State private var backupPassword = ""
    @State private var pendingImport: Data?
    @State private var notice: String?

    var body: some View {
        Section {
            Button {
                backupPassword = ""
                exportPrompt = true
            } label: {
                Label("Back Up Settings and Playlists", systemImage: "square.and.arrow.up")
            }
            Button { importing = true } label: {
                Label("Restore Settings and Playlists", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Local Backup & Restore")
        } footer: {
            Text("Backs up settings and playlist connection details, including credentials, in a password-protected JSON file. Keep the backup password safe. Channel catalogs, watched history, and provider session tokens are not copied. Existing playlists are kept during restore.")
        }
        .alert("Protect IPTV Backup", isPresented: $exportPrompt) {
            SecureField("Backup password (8+ characters)", text: $backupPassword)
            Button("Cancel", role: .cancel) { backupPassword = "" }
            Button("Create Backup") {
                do {
                    exportDocument = try DreamCASTLocalSettingsBackup.exportSettings(
                        playlists: playlists, password: backupPassword
                    )
                    exporting = true
                } catch {
                    notice = "Could not prepare backup: \(error.localizedDescription)"
                }
                backupPassword = ""
            }
        } message: {
            Text("Your backup may contain IPTV passwords and private playlist URLs. Use a strong password.")
        }
        .fileExporter(isPresented: $exporting, document: exportDocument,
                      contentType: .json, defaultFilename: "DreamCAST-TV-backup") { result in
            switch result {
            case .success: notice = "Backup saved to Files. Keep your backup password."
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError {
                    notice = "Could not save backup: \(error.localizedDescription)"
                }
            }
            exportDocument = nil
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                if try DreamCASTLocalSettingsBackup.hasEncryptedPlaylists(data) {
                    pendingImport = data
                    backupPassword = ""
                    restorePrompt = true
                } else {
                    let count = try DreamCASTLocalSettingsBackup.restoreSettings(
                        from: data, context: modelContext
                    )
                    notice = "Restored \(count) settings. Reopen DreamCAST TV to apply them."
                }
            } catch {
                if (error as NSError).code != NSUserCancelledError {
                    notice = "Could not open backup: \(error.localizedDescription)"
                }
            }
        }
        .alert("Unlock IPTV Backup", isPresented: $restorePrompt) {
            SecureField("Backup password", text: $backupPassword)
            Button("Cancel", role: .cancel) {
                pendingImport = nil
                backupPassword = ""
            }
            Button("Restore") {
                do {
                    if let data = pendingImport {
                        let count = try DreamCASTLocalSettingsBackup.restoreSettings(
                            from: data, password: backupPassword, context: modelContext
                        )
                        notice = "Restored \(count) settings and playlist setups. Restart DreamCAST TV to sync the imported playlists."
                    }
                } catch {
                    notice = "Could not restore backup: \(error.localizedDescription)"
                }
                pendingImport = nil
                backupPassword = ""
            }
        } message: {
            Text("Enter the password used when the IPTV backup was created.")
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
