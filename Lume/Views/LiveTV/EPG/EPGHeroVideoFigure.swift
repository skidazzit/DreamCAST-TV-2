//
//  EPGHeroVideoFigure.swift
//  Lume
//
//  The tvOS Guide hero's 16:9 picture: the settled channel playing with audio, or,
//  while it may not play, the channel's logo on a card tinted with it.
//

#if os(tvOS)
    import SwiftUI

    struct EPGHeroVideoFigure: View {
        let target: EPGPreviewTarget?
        let isAllowed: Bool
        let isFailed: Bool
        let restartToken: Int
        let handle: PreviewPlayerHandle?
        /// Read only by the placeholder card, for the settled channel's tint.
        let hero: GuideHeroModel?
        let onFailure: () -> Void

        @Environment(\.epgHeroLayout) private var layout
        @Environment(SportsZonePlaybackSession.self) private var sharedPlayback: SportsZonePlaybackSession?

        var body: some View {
            ZStack(alignment: .bottom) {
                content

                LinearGradient(colors: [.black.opacity(0), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                    .frame(height: layout.height / 3)
            }
            .frame(width: layout.videoWidth, height: layout.height)
            .clipped()
            .overlay {
                if sharedPlayback?.miniMedia == nil {
                    Rectangle().strokeBorder(TVNeonTheme.iceBlue.opacity(0.86), lineWidth: 2)
                }
            }
            .background {
                // Do not draw a second black video card beneath the
                // shared player. The single root surface fills this slot.
                if sharedPlayback?.miniMedia == nil {
                    Rectangle().fill(.black)
                        .shadow(color: TVNeonTheme.electricBlue.opacity(0.26), radius: 19, y: 8)
                }
            }
        }

        @ViewBuilder
        private var content: some View {
            if sharedPlayback?.miniMedia != nil {
                // Reserve the exact guide hero frame and publish its position.
                // The app-root decoder renders here, without a second player.
                TVEmbeddedPlayerSlot(includesControls: false)
            } else if let target, !isFailed, isAllowed, sharedPlayback == nil, let media = target.media {
                ZStack {
                    Color.black
                    MultiViewTilePlayer(
                        media: media,
                        isMuted: false,
                        role: .guidePreview(handle: handle),
                        onFailure: onFailure
                    )
                    .id("\(target.streamID)-\(restartToken)")
                }
            } else {
                EPGHeroPlaceholderCard(
                    logoURL: target?.logoURL,
                    isUnavailable: isFailed && target != nil,
                    hero: hero
                )
            }
        }
    }

    /// The video slot when nothing plays: never empty, so the hero keeps its
    /// shape and the settle `.task` above it keeps running.
    private struct EPGHeroPlaceholderCard: View {
        let logoURL: URL?
        let isUnavailable: Bool
        let hero: GuideHeroModel?

        @Environment(\.epgHeroLayout) private var layout

        private var tint: Color {
            hero?.glowTint ?? LiveTVPalette.accent
        }

        /// A third of the hero's height: 120 pt regular, about 67 pt small.
        private var logoSide: CGFloat {
            layout.height / 3
        }

        var body: some View {
            ZStack {
                Color(red: 13 / 255, green: 16 / 255, blue: 24 / 255)
                LinearGradient(
                    colors: [tint.opacity(0.42), tint.opacity(0.12)],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
                .animation(.easeInOut(duration: 0.6), value: tint)

                if isUnavailable {
                    LiveChannelUnavailableBadge(logoURL: logoURL, logoSide: logoSide)
                } else {
                    LiveChannelLogoPlaceholder(url: logoURL, side: logoSide)
                }
            }
        }
    }
#endif
