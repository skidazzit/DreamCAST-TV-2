#if os(iOS)
import Foundation
import CryptoKit
import CommonCrypto
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Portable encrypted backup of preferences, playlist setup and user watch state.
/// This copies selected SwiftData values, never raw databases or session tokens.
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
        // Optional for existing version-2 backups.
        var viewingState: ViewingState?
    }

    /// Minimal changes only; never copy provider catalogs into the archive.
    /// Content IDs are replayed after the destination's playlist has synced.
    struct ViewingState: Codable {
        var live: [LiveState]
        var movies: [MovieState]
        var series: [SeriesState]
        var episodes: [EpisodeState]
    }

    struct LiveState: Codable {
        let id: String
        let isFavorite: Bool
        let favoriteOrder: Int?
        let lastWatchedDate: Date?
    }

    struct MovieState: Codable {
        let id: String
        let isFavorite: Bool
        let favoriteOrder: Int?
        let watchProgress: Double
        let isWatched: Bool
        let lastWatchedDate: Date?
        let addedToWatchlistDate: Date?
    }

    struct SeriesState: Codable {
        let id: String
        let isFavorite: Bool
        let favoriteOrder: Int?
        let lastWatchedDate: Date?
        let addedToWatchlistDate: Date?
    }

    struct EpisodeState: Codable {
        let id: String
        let watchProgress: Double
        let isWatched: Bool
        let lastWatchedDate: Date?
    }

    /// Gather only rows that contain user changes. The catalog can contain
    /// hundreds of thousands of titles, so never export every catalog row.
    static func captureViewingState(in context: ModelContext) throws -> ViewingState {
        let live = try context.fetch(FetchDescriptor<LiveStream>(
            predicate: #Predicate { $0.isFavorite || $0.lastWatchedDate != nil }
        )).map {
            LiveState(id: $0.id, isFavorite: $0.isFavorite,
                      favoriteOrder: $0.favoriteOrder, lastWatchedDate: $0.lastWatchedDate)
        }
        let movies = try context.fetch(FetchDescriptor<Movie>(
            predicate: #Predicate {
                $0.isFavorite || $0.lastWatchedDate != nil || $0.isWatched
                    || $0.watchProgress > 0 || $0.addedToWatchlistDate != nil
            }
        )).map {
            MovieState(id: $0.id, isFavorite: $0.isFavorite,
                       favoriteOrder: $0.favoriteOrder, watchProgress: $0.watchProgress,
                       isWatched: $0.isWatched, lastWatchedDate: $0.lastWatchedDate,
                       addedToWatchlistDate: $0.addedToWatchlistDate)
        }
        let series = try context.fetch(FetchDescriptor<Series>(
            predicate: #Predicate {
                $0.isFavorite || $0.lastWatchedDate != nil || $0.addedToWatchlistDate != nil
            }
        )).map {
            SeriesState(id: $0.id, isFavorite: $0.isFavorite,
                        favoriteOrder: $0.favoriteOrder, lastWatchedDate: $0.lastWatchedDate,
                        addedToWatchlistDate: $0.addedToWatchlistDate)
        }
        let episodes = try context.fetch(FetchDescriptor<Episode>(
            predicate: #Predicate {
                $0.isWatched || $0.watchProgress > 0 || $0.lastWatchedDate != nil
            }
        )).map {
            EpisodeState(id: $0.id, watchProgress: $0.watchProgress,
                         isWatched: $0.isWatched, lastWatchedDate: $0.lastWatchedDate)
        }
        return ViewingState(live: live, movies: movies, series: series, episodes: episodes)
    }

    private struct PlaylistRecord: Codable {
        var name: String
        var serverURL: String
        var xtreamProviderID: String?
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
            serverURL = p.effectiveXtreamServerURL
            xtreamProviderID = p.sourceType == .xtream
                ? (p.xtreamProviderID ?? XtreamProviderDirectory.provider(address: p.serverURL)?.id) : nil
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
            p.xtreamProviderID = xtreamProviderID
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
            || k.hasPrefix("premium.") || k.hasPrefix("sync.backend")
            || k.hasPrefix("dreamcast.backup.") { return false }
        let sensitive = ["password", "passwd", "secret", "token", "credential",
                         "auth", "apikey", "api_key", "accesskey", "privatekey",
                         "session", "cookie", "refreshkey", "recovery"]
        return !sensitive.contains(where: { k.contains($0) })
    }

    static func exportSettings(playlists: [Playlist] = [], password: String? = nil,
                               context: ModelContext? = nil) throws -> DreamCASTSettingsFile {
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
                ProtectedPayload(
                    preferences: values,
                    playlists: playlists.map(PlaylistRecord.init),
                    viewingState: try context.map { try captureViewingState(in: $0) }
                )
            )
            let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
            let sealed = try AES.GCM.seal(records, using: key(password: password, salt: salt))
            archive = Archive(formatVersion: 2, createdAt: .now,
                              preferences: [:], playlistSalt: salt,
                              encryptedPlaylists: sealed.combined)
        }
        return DreamCASTSettingsFile(contents: try JSONEncoder().encode(archive))
    }

    // Save pending records so a first-run restore works before the IPTV
    // provider has downloaded channel, movie and episode catalogs.
    private static let pendingViewingStateKey = "dreamcast.backup.pendingViewingState"

    private static func mergePending(_ imported: ViewingState) throws {
        var result = imported
        if let previous = UserDefaults.standard.data(forKey: pendingViewingStateKey),
           let old = try? JSONDecoder().decode(ViewingState.self, from: previous) {
            result.live = Array(Dictionary(
                (old.live + imported.live).map { ($0.id, $0) },
                uniquingKeysWith: { _, incoming in incoming }
            ).values)
            result.movies = Array(Dictionary(
                (old.movies + imported.movies).map { ($0.id, $0) },
                uniquingKeysWith: { _, incoming in incoming }
            ).values)
            result.series = Array(Dictionary(
                (old.series + imported.series).map { ($0.id, $0) },
                uniquingKeysWith: { _, incoming in incoming }
            ).values)
            result.episodes = Array(Dictionary(
                (old.episodes + imported.episodes).map { ($0.id, $0) },
                uniquingKeysWith: { _, incoming in incoming }
            ).values)
        }
        UserDefaults.standard.set(try JSONEncoder().encode(result),
                                  forKey: pendingViewingStateKey)
    }

    /// Reapply records as each provider sync creates matching SwiftData rows.
    /// Leave unmatched IDs pending for a later catalog sync.
    @discardableResult
    static func applyPendingViewingState(in context: ModelContext) throws -> Int {
        guard let data = UserDefaults.standard.data(forKey: pendingViewingStateKey),
              var state = try? JSONDecoder().decode(ViewingState.self, from: data) else {
            return 0
        }
        var count = 0
        let liveIDs = state.live.map(\.id)
        let movieIDs = state.movies.map(\.id)
        let seriesIDs = state.series.map(\.id)
        let episodeIDs = state.episodes.map(\.id)

        let liveMap = Dictionary(uniqueKeysWithValues:
            try context.fetch(FetchDescriptor<LiveStream>(
                predicate: #Predicate { liveIDs.contains($0.id) }
            )).map { ($0.id, $0) })
        state.live.removeAll { record in
            guard let item = liveMap[record.id] else { return false }
            item.isFavorite = record.isFavorite
            item.favoriteOrder = record.favoriteOrder
            item.lastWatchedDate = record.lastWatchedDate
            count += 1
            return true
        }

        let movieMap = Dictionary(uniqueKeysWithValues:
            try context.fetch(FetchDescriptor<Movie>(
                predicate: #Predicate { movieIDs.contains($0.id) }
            )).map { ($0.id, $0) })
        state.movies.removeAll { record in
            guard let item = movieMap[record.id] else { return false }
            item.isFavorite = record.isFavorite
            item.favoriteOrder = record.favoriteOrder
            item.watchProgress = record.watchProgress
            item.isWatched = record.isWatched
            item.lastWatchedDate = record.lastWatchedDate
            item.addedToWatchlistDate = record.addedToWatchlistDate
            count += 1
            return true
        }

        let seriesMap = Dictionary(uniqueKeysWithValues:
            try context.fetch(FetchDescriptor<Series>(
                predicate: #Predicate { seriesIDs.contains($0.id) }
            )).map { ($0.id, $0) })
        state.series.removeAll { record in
            guard let item = seriesMap[record.id] else { return false }
            item.isFavorite = record.isFavorite
            item.favoriteOrder = record.favoriteOrder
            item.lastWatchedDate = record.lastWatchedDate
            item.addedToWatchlistDate = record.addedToWatchlistDate
            count += 1
            return true
        }

        let episodeMap = Dictionary(uniqueKeysWithValues:
            try context.fetch(FetchDescriptor<Episode>(
                predicate: #Predicate { episodeIDs.contains($0.id) }
            )).map { ($0.id, $0) })
        state.episodes.removeAll { record in
            guard let item = episodeMap[record.id] else { return false }
            item.watchProgress = record.watchProgress
            item.isWatched = record.isWatched
            item.lastWatchedDate = record.lastWatchedDate
            count += 1
            return true
        }
        if count > 0 { try context.save() }
        if state.live.isEmpty && state.movies.isEmpty &&
            state.series.isEmpty && state.episodes.isEmpty {
            UserDefaults.standard.removeObject(forKey: pendingViewingStateKey)
        } else {
            UserDefaults.standard.set(try JSONEncoder().encode(state),
                                      forKey: pendingViewingStateKey)
        }
        return count
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
        var restoredViewingState: ViewingState?
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
                restoredViewingState = payload.viewingState
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
                "\($0.sourceTypeRaw)|\($0.effectiveXtreamServerURL)|\($0.username)"
            })
            for playlist in imported {
                let identifier = "\(playlist.sourceTypeRaw)|\(playlist.effectiveXtreamServerURL)|\(playlist.username)"
                guard seen.insert(identifier).inserted else { continue }
                context.insert(playlist)
            }
            try context.save()
        }
        for (name, value) in staged { UserDefaults.standard.set(value, forKey: name) }
        UserDefaults.standard.set("off", forKey: "sync.backend")
        if let restoredViewingState {
            try mergePending(restoredViewingState)
            if let context { _ = try applyPendingViewingState(in: context) }
        }
        return staged.count
    }
}

/// Keep Files and password entry on a stable navigation destination.
/// Alerts attached to a virtualized List Section can dismiss when the
/// keyboard opens. Do not mount a password alert on the settings row.
struct DreamCASTBackupSettingsSection: View {
    var body: some View {
        Section {
            NavigationLink {
                DreamCASTBackupCenterView(mode: .backup)
            } label: {
                Label("Back Up Settings and Playlists", systemImage: "square.and.arrow.up")
            }
            NavigationLink {
                DreamCASTBackupCenterView(mode: .restore)
            } label: {
                Label("Restore Settings and Playlists", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Local Backup & Restore")
        } footer: {
            Text("Encrypted backups include IPTV connections, app settings, favorites and watch progress. A backup password is required. Downloaded channels and guide data sync after restore.")
        }
    }
}

/// Dedicated full-page flow. The password field never lives in a transient
/// UIAlertController or the List's virtualized row hierarchy.
private struct DreamCASTBackupCenterView: View {
    enum Mode: Equatable {
        case backup
        case restore
    }

    let mode: Mode

    @Environment(\.modelContext) private var modelContext
    @Query private var playlists: [Playlist]

    @State private var password = ""
    @State private var exporting = false
    @State private var importing = false
    @State private var exportDocument: DreamCASTSettingsFile?
    @State private var pendingImport: Data?
    @State private var selectedFilename: String?
    @State private var needsPassword = true
    @State private var message: String?
    @State private var messageIsError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label(mode == .backup ? "Protect Your Backup" : "Restore Your Backup",
                      systemImage: mode == .backup ? "lock.shield" : "square.and.arrow.down")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Text(mode == .backup
                     ? "Back up IPTV playlist logins, app settings, favorites and watch history. Your file is encrypted with the password you choose."
                     : "Select a DreamCAST TV backup from Files. Enter the password used to create it, then restore your playlists and settings.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))

                if mode == .restore {
                    Button {
                        message = nil
                        importing = true
                    } label: {
                        Label("Choose Backup File", systemImage: "doc")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)

                    if let selectedFilename {
                        Label(selectedFilename, systemImage: "doc.text")
                            .font(.subheadline)
                            .lineLimit(2)
                            .foregroundStyle(.white)
                    }
                }

                if mode == .backup || (pendingImport != nil && needsPassword) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(mode == .backup ? "Backup Password" : "Backup Password")
                            .font(.headline)
                        SecureField(
                            mode == .backup ? "At least 8 characters" : "Enter your backup password",
                            text: $password
                        )
                        .textContentType(mode == .backup ? .newPassword : .password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .privacySensitive()
                        .padding(14)
                        .dreamCASTGlass(radius: 13)

                        Text(mode == .backup
                             ? "Keep this password safe. You need it to open the file on another device."
                             : "This password is never saved in DreamCAST TV.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if mode == .backup {
                    Button(action: prepareBackup) {
                        Label("Create Encrypted Backup", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(password.count < 8)
                } else if pendingImport != nil {
                    Button(action: restoreBackup) {
                        Label("Restore Settings and Playlists", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(needsPassword && password.isEmpty)
                }

                if let message {
                    Label(message, systemImage: messageIsError
                          ? "exclamationmark.triangle" : "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(messageIsError ? .orange : .green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .dreamCASTGlass(radius: 13)
                }
            }
            .frame(maxWidth: 550)
            .frame(maxWidth: .infinity)
            .padding(20)
        }
        .background { DreamCASTMobileWallpaper() }
        .navigationTitle(mode == .backup ? "Back Up DreamCAST TV" : "Restore DreamCAST TV")
        .navigationBarTitleDisplayMode(.inline)
        // Present the exporter from this stable navigation page, not a
        // Section embedded within a virtualized Settings list.
        .fileExporter(
            isPresented: $exporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "DreamCAST-TV-backup"
        ) { result in
            switch result {
            case .success:
                showMessage("Encrypted backup saved to Files. Keep your backup password.", error: false)
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError {
                    showMessage("Could not save backup: \(error.localizedDescription)", error: true)
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
                needsPassword = try DreamCASTLocalSettingsBackup.hasEncryptedPlaylists(data)
                pendingImport = data
                selectedFilename = url.lastPathComponent
                password = ""
                showMessage("Backup selected. Confirm the restore below.", error: false)
            } catch {
                if (error as NSError).code != NSUserCancelledError {
                    showMessage("Could not open backup: \(error.localizedDescription)", error: true)
                }
            }
        }
    }

    private func prepareBackup() {
        do {
            exportDocument = try DreamCASTLocalSettingsBackup.exportSettings(
                playlists: playlists, password: password, context: modelContext
            )
            password = ""
            message = nil
            // Allow SwiftUI to register the new FileDocument before opening
            // Files. The document stays owned by this navigation page.
            Task { @MainActor in
                await Task.yield()
                exporting = true
            }
        } catch {
            showMessage("Could not prepare backup: \(error.localizedDescription)", error: true)
        }
    }

    private func restoreBackup() {
        guard let pendingImport else { return }
        do {
            let count = try DreamCASTLocalSettingsBackup.restoreSettings(
                from: pendingImport,
                password: needsPassword ? password : nil,
                context: modelContext
            )
            self.pendingImport = nil
            password = ""
            showMessage("Restored \(count) settings and your playlist setups. Restart DreamCAST TV to sync channels, favorites and watch progress.", error: false)
        } catch {
            // Keep the selected file so an incorrect password can be retried.
            showMessage("Could not restore backup: \(error.localizedDescription)", error: true)
        }
    }

    private func showMessage(_ text: String, error: Bool) {
        message = text
        messageIsError = error
    }
}
#endif
