//
//  EPGGridScroller+Preview.swift
//  Lume
//
//  Wires the tvOS Guide's now-playing hero (`EPGPreviewPane`) into the
//  scroller: the Guide starts on the last watched channel when available.
//  Moving focus never changes playback; Select tunes the mini-player.
//

#if os(tvOS)
    import SwiftData
    import SwiftUI
    import UIKit

    extension EPGGridScroller {
        /// The band above the time ruler. Never focusable and outside the
        /// strip's own focus section (only the scroller's outer one spans it),
        /// so Up from the top row still reaches the tab bar.
        var previewBand: some View {
            EPGPreviewBand(
                target: previewTarget,
                settledRow: previewRow,
                dataVersion: dataVersion,
                isFrozen: isPreviewFrozen,
                isFailed: previewTarget.map { previewFailedStreamIDs.contains($0.streamID) } ?? false,
                controller: preview.controller,
                hero: preview.hero,
                playlistIDs: preview.playlistIDs,
                onFailure: { [streamID = previewTarget?.streamID] in markPreviewFailed(streamID) }
            )
            .equatable()
            .task(id: PreviewSettleKey(streamID: preview.controller?.preferredStreamID, isFrozen: isPreviewFrozen)) {
                await settlePreview()
            }
            .onChange(of: HeroFocusKey(streamID: previewFocusedStreamID, dataVersion: dataVersion), initial: true) {
                publishFocusedRow()
            }
        }

        /// Full screen adopted the preview's running stream: the tile stays
        /// mounted on its channel, whatever focus does underneath the cover.
        private var isPreviewFrozen: Bool {
            guard let controller = preview.controller else { return false }
            return controller.isSuspended && controller.handle.owner == .fullScreen
        }

        /// `nil` while real focus is outside the grid.
        private var previewFocusedStreamID: String? {
            virtualFocusRow?.id
        }

        private var previewRow: EPGChannelRow? {
            guard let target = previewTarget else { return nil }
            if rows.indices.contains(target.rowIndex), rows[target.rowIndex].id == target.streamID {
                return rows[target.rowIndex]
            }
            return rows.first { $0.id == target.streamID }
        }

        private func settlePreview() async {
            // Do not retune merely because remote focus moved to another row.
            guard !isPreviewFrozen else { return }
            let streamID = preview.controller?.preferredStreamID ?? previewTarget?.streamID ?? rows.first?.id
            guard let streamID, previewTarget?.streamID != streamID else { return }
            guard let rowIndex = rows.firstIndex(where: { $0.id == streamID }) else { return }
            let row = rows[rowIndex]
            previewTarget = EPGPreviewTarget(row: row, rowIndex: rowIndex, media: preview.media(row.stream))
            preview.hero?.settleGlow(onLogo: row.logoURL)
        }

        /// Hands the hero's info block the focused row on every row change,
        /// through the hero model so the scroller never reads it back.
        private func publishFocusedRow() {
            guard let hero = preview.hero else { return }
            // A focus move runs in the focus engine's animated context; the
            // info swaps rather than crossfading on every press.
            withTransaction(Transaction(animation: nil)) {
                hero.focusedRow = virtualFocusRow
            }
        }

        private func markPreviewFailed(_ streamID: String?) {
            guard let streamID else { return }
            Task { @MainActor in
                previewFailedStreamIDs.insert(streamID)
            }
        }
    }

    private struct PreviewSettleKey: Equatable {
        let streamID: String?
        let isFrozen: Bool
    }

    private struct HeroFocusKey: Equatable {
        let streamID: String?
        let dataVersion: Int
    }

    /// Decides whether the band's tile may play at all. Owns the reads that change on
    /// their own — Lume Pro and the accessibility autoplay setting — so they
    /// never re-render the scroller.
    private struct EPGPreviewBand: View, Equatable {
        let target: EPGPreviewTarget?
        /// Compared through `target` and `dataVersion` instead: a channel's
        /// row only changes with the data.
        let settledRow: EPGChannelRow?
        let dataVersion: Int
        let isFrozen: Bool
        let isFailed: Bool
        let controller: GuidePreviewController?
        let hero: GuideHeroModel?
        let playlistIDs: [UUID]
        let onFailure: () -> Void

        @State private var premium = PremiumManager.shared
        @State private var autoplayAllowed = UIAccessibility.isVideoAutoplayEnabled
        /// Read here, never by the scroller, so changing it re-renders only
        /// the band; the grid below takes whatever height the band leaves.
        @AppStorage(PlayerSettings.tvGuidePreviewModeKey)
        private var modeRaw = PlayerSettings.tvGuidePreviewModeDefault.rawValue

        private var mode: GuidePreviewMode {
            GuidePreviewMode(storedValue: modeRaw)
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.target == rhs.target
                && lhs.dataVersion == rhs.dataVersion
                && lhs.isFrozen == rhs.isFrozen
                && lhs.isFailed == rhs.isFailed
                && lhs.controller === rhs.controller
                && lhs.hero === rhs.hero
                && lhs.playlistIDs == rhs.playlistIDs
        }

        static func isAvailable(mode: GuidePreviewMode, isPremium: Bool, autoplayAllowed: Bool) -> Bool {
            mode.playsVideo && isPremium && autoplayAllowed
        }

        var body: some View {
            Group {
                // Both hero branches keep the hero's full height, so the grid
                // never moves when the preview becomes available or stops
                // being so. Off leaves a zero-height host, never an empty
                // view, so the settle task above keeps running.
                if !mode.showsHero {
                    Color.clear.frame(height: 0)
                } else if GuidePreviewPolicy.autoplayStreamsInGuide && Self.isAvailable(mode: mode, isPremium: premium.isPremium, autoplayAllowed: autoplayAllowed) {
                    EPGPreviewBandContent(
                        target: target,
                        settledRow: settledRow,
                        isFrozen: isFrozen,
                        isFailed: isFailed,
                        controller: controller,
                        hero: hero,
                        playlistIDs: playlistIDs,
                        onFailure: onFailure
                    )
                } else {
                    EPGPreviewPane(
                        target: target,
                        settledRow: settledRow,
                        hero: hero,
                        isAllowed: false,
                        restartToken: 0,
                        handle: nil,
                        onFailure: onFailure
                    )
                    .equatable()
                }
            }
            .environment(\.epgHeroLayout, EPGHeroLayout(mode))
            .allowsHitTesting(false)
            .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.videoAutoplayStatusDidChangeNotification)) { _ in
                autoplayAllowed = UIAccessibility.isVideoAutoplayEnabled
            }
        }
    }

    /// Whether the band's tile may play. Owns the playlist's sync reads and the
    /// controller's suspension, so they re-render only this view.
    private struct EPGPreviewBandContent: View {
        let target: EPGPreviewTarget?
        let settledRow: EPGChannelRow?
        let isFrozen: Bool
        let isFailed: Bool
        let controller: GuidePreviewController?
        let hero: GuideHeroModel?
        let onFailure: () -> Void

        /// The playlists whose sync pauses the tile: every Combined member
        /// contributing Live TV.
        private let playlistIDs: Set<UUID>

        @State private var epgSync = EPGSyncService.shared
        @Query private var playlists: [Playlist]
        @Query private var guideSources: [EPGSource]

        init(
            target: EPGPreviewTarget?,
            settledRow: EPGChannelRow?,
            isFrozen: Bool,
            isFailed: Bool,
            controller: GuidePreviewController?,
            hero: GuideHeroModel?,
            playlistIDs: [UUID],
            onFailure: @escaping () -> Void
        ) {
            self.target = target
            self.settledRow = settledRow
            self.isFrozen = isFrozen
            self.isFailed = isFailed
            self.controller = controller
            self.hero = hero
            self.onFailure = onFailure
            self.playlistIDs = Set(playlistIDs)
            switch playlistIDs.count {
            case 0:
                _playlists = Query(filter: #Predicate<Playlist> { _ in false })
                _guideSources = Query(filter: #Predicate<EPGSource> { _ in false })
            case 1:
                let playlistID = playlistIDs[0]
                _playlists = Query(filter: #Predicate<Playlist> { $0.id == playlistID })
                _guideSources = Query(filter: #Predicate<EPGSource> { $0.playlistID == playlistID })
            default:
                // An optional key in an `IN` predicate breaks SQL generation, so
                // the playlist-linked sources (a handful of rows) are matched to
                // the members in `isSyncing` instead.
                _playlists = Query(filter: #Predicate<Playlist> { playlistIDs.contains($0.id) })
                _guideSources = Query(filter: #Predicate<EPGSource> { $0.playlistID != nil })
            }
        }

        private var isSyncing: Bool {
            if playlists.contains(where: { $0.syncStatus == .syncing }) { return true }
            return epgSync.isSyncing
                && guideSources.contains { source in
                    source.syncStatus == .syncing && source.playlistID.map { playlistIDs.contains($0) } == true
                }
        }

        private var isAllowed: Bool {
            isFrozen || GuidePreviewPolicy.shouldPreview(
                suspended: controller?.isSuspended ?? false,
                syncing: isSyncing,
                failed: isFailed
            )
        }

        var body: some View {
            EPGPreviewPane(
                target: target,
                settledRow: settledRow,
                hero: hero,
                isAllowed: isAllowed,
                isFailed: isFailed,
                restartToken: controller?.restartToken ?? 0,
                handle: controller?.handle,
                onFailure: onFailure
            )
            .equatable()
        }
    }
#endif
