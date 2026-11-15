//
//  PlayerErrorIndicator.swift
//  Lume
//
//  Centered failure state shown over the video host when a stream never starts
//  (or drops permanently mid-playback). It replaces the loading spinner once the
//  startup watchdog fires or the bounded reconnect budget is spent, so a dead
//  stream surfaces a "Try Again / Back" choice instead of locking the player on
//  an endless spinner.
//

import SwiftUI
#if os(tvOS)
import SwiftData
#endif

/// Centered "playback failed" overlay. `title` is the stream name (shown so the
/// viewer knows which stream failed); `onRetry` re-prepares the stream in place
/// and `onClose` leaves the player.
@available(iOS 16.0, macOS 13.0, tvOS 16.0, *)
struct PlayerErrorIndicator: View {
    let title: String?
    let onRetry: () -> Void
    let onClose: () -> Void
    /// SportsZone sets these when playback is opened from a matched fixture.
    var failedMedia: PlayableMedia? = nil
    var onSelectMedia: ((PlayableMedia) -> Void)? = nil

    #if os(tvOS)
        @Environment(\.modelContext) private var modelContext
        @Environment(SportsZonePlaybackSession.self) private var sportsZonePlayback: SportsZonePlaybackSession?
        @State private var showsMatchedChannels = false
        @FocusState private var retryFocused: Bool
        @FocusState private var matchFocus: TVPlayerFocus?

        private var availableMatches: [ResolvedChannel] {
            sportsZonePlayback?.matchedChannels ?? []
        }

        private var failedChannelID: String? {
            guard let failedMedia, case let .live(id) = failedMedia.contentRef else { return nil }
            return id
        }

        private var canChooseMatchedChannels: Bool {
            onSelectMedia != nil && !availableMatches.isEmpty
        }
    #endif

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            #if os(tvOS)
                if showsMatchedChannels {
                    matchedChannelSelection
                } else {
                    failedMessage
                }
            #else
                failedMessage
            #endif
        }
        #if os(tvOS)
            .onExitCommand {
                if showsMatchedChannels {
                    showsMatchedChannels = false
                } else {
                    onClose()
                }
            }
        #endif
    }

    private var failedMessage: some View {
        VStack(spacing: spacing) {
            Image(systemName: "wifi.exclamationmark")
                .font(iconFont)
                .foregroundStyle(.white)

            VStack(spacing: 8) {
                Text("Playback Failed")
                    .font(titleFont)
                    .foregroundStyle(.white)

                if let title, !title.isEmpty {
                    Text(title)
                        .font(streamFont)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Text("This stream couldn’t be loaded. It may be offline or temporarily unavailable.")
                    .font(messageFont)
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: maxTextWidth)
            }

            buttons
                .padding(.top, buttonTopPadding)
        }
        .padding(.horizontal, 40)
        .shadow(radius: 8)
    }

    #if os(tvOS)
        /// Reuse the saved picker results. Focus movement does not tune video.
        private var matchedChannelSelection: some View {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .center, spacing: 32) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Choose Channel")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Highlight a matched channel, then press Select to play.")
                            .font(.system(size: 23))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                    Button {
                        showsMatchedChannels = false
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .font(.system(size: 24, weight: .semibold))
                    }
                    .buttonStyle(TVGlassButtonStyle())
                }
                TVPlayerSportsZoneChannelsPanel(
                    channels: availableMatches,
                    currentChannelID: nil,
                    failedChannelID: failedChannelID,
                    focus: $matchFocus,
                    onSelect: playMatchedChannel,
                    onClose: { showsMatchedChannels = false }
                )
            }
            .padding(64)
            .frame(maxWidth: 1500)
            .onAppear {
                let firstOther = availableMatches.first { $0.id != failedChannelID }
                matchFocus = .channel(firstOther?.id ?? availableMatches.first?.id ?? "")
            }
        }

        private func playMatchedChannel(_ channel: ResolvedChannel) {
            guard let media = SportsPlayback.media(for: channel, in: modelContext) else { return }
            if media.id == failedMedia?.id {
                // Re-selecting the same dead stream means retrying it.
                showsMatchedChannels = false
                onRetry()
            } else {
                onSelectMedia?(media)
            }
        }
    #endif

    // MARK: - Buttons

    @ViewBuilder
    private var buttons: some View {
        #if os(tvOS)
            HStack(spacing: 28) {
                Button(action: onRetry) {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .font(.system(size: 24, weight: .semibold))
                }
                .buttonStyle(TVGlassButtonStyle())
                .focused($retryFocused)

                if canChooseMatchedChannels {
                    Button {
                        showsMatchedChannels = true
                    } label: {
                        Label("Choose Channel", systemImage: "list.bullet.rectangle")
                            .font(.system(size: 24, weight: .semibold))
                    }
                    .buttonStyle(TVGlassButtonStyle())
                }

                Button(action: onClose) {
                    Label("Back", systemImage: "xmark")
                        .font(.system(size: 24, weight: .semibold))
                }
                .buttonStyle(TVGlassButtonStyle())
            }
            .frame(maxWidth: 1200)
            .onAppear { retryFocused = true }
        #else
            HStack(spacing: 14) {
                glassButton("Try Again", systemImage: "arrow.clockwise", action: onRetry)
                glassButton("Back", systemImage: "xmark", action: onClose)
            }
        #endif
    }

    #if !os(tvOS)
        private func glassButton(_ titleKey: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Label(titleKey, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .contentShape(Capsule())
                    .glassEffectCompat(.regularInteractive, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    #endif

    // MARK: - Platform metrics

    #if os(tvOS)
        private var spacing: CGFloat {
            30
        }

        private var iconFont: Font {
            .system(size: 80, weight: .regular)
        }

        private var titleFont: Font {
            .system(size: 40, weight: .semibold)
        }

        private var streamFont: Font {
            .system(size: 26, weight: .regular)
        }

        private var messageFont: Font {
            .system(size: 24, weight: .regular)
        }

        private var maxTextWidth: CGFloat {
            760
        }

        private var buttonTopPadding: CGFloat {
            20
        }
    #else
        private var spacing: CGFloat {
            18
        }

        private var iconFont: Font {
            .system(size: 44, weight: .regular)
        }

        private var titleFont: Font {
            .title2.weight(.semibold)
        }

        private var streamFont: Font {
            .subheadline
        }

        private var messageFont: Font {
            .footnote
        }

        private var maxTextWidth: CGFloat {
            360
        }

        private var buttonTopPadding: CGFloat {
            12
        }
    #endif
}
