//
//  TVAmbientBackground.swift
//  Lume
//
//  The tvOS backdrop of Live TV and Settings: a near-black fill lit from the
//  top right by a soft glow — in the settled channel's logo colour in the
//  guide, the Live TV accent elsewhere — darkened towards the bottom so the
//  content stays legible. Drawn with gradients rather than a
//  runtime blur, so it costs nothing per frame.
//

#if os(tvOS)
    import SwiftUI

    /// DreamCAST TV 2 visual tokens, matched to the approved dark/neon reference.
    /// Names here keep every tvOS tab using the same colors and outlines.
    enum TVNeonTheme {
        static var midnight: Color {
            DreamCASTVisualSettings.theme.backgroundColors(light: DreamCASTDisplayColors.isLight)[2]
        }
        static var electricBlue: Color { DreamCASTVisualSettings.theme.selectionAccent }
        static var iceBlue: Color { DreamCASTVisualSettings.theme.selectionAccent.opacity(0.88) }
        static var glassTop: Color {
            DreamCASTVisualSettings.theme.backgroundColors(light: DreamCASTDisplayColors.isLight)[1]
        }
        static var glassBottom: Color {
            DreamCASTVisualSettings.theme.backgroundColors(light: DreamCASTDisplayColors.isLight)[0]
        }

        static var glass: LinearGradient {
            let a = DreamCASTVisualSettings.transparency
            return LinearGradient(
                colors: [glassTop.opacity(1 - a), glassBottom.opacity(1 - a)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
        static var selection: LinearGradient {
            LinearGradient(colors: [electricBlue, DreamCASTVisualSettings.theme.gradientColors[1]],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    /// App-root backdrop state. The guide writes the settled channel tint once;
    /// tab changes read it without rebuilding the live playback view.
    @MainActor @Observable
    final class TVAmbientThemeSession {
        var liveHero: GuideHeroModel?
    }

    struct TVAmbientBackground: View {
        /// `nil` paints the Live TV accent; only this view reads its glow.
        let hero: GuideHeroModel?

        /// `#090B10`.
        static var base: Color { TVNeonTheme.midnight }

        /// Laid out on the 1920 × 1080 design canvas and scaled to the screen.
        private static let canvasWidth: CGFloat = 1920
        private static let glowCenter = CGPoint(x: 1470, y: 230)
        /// The design's 1300 × 980 ellipse blurred by 170 pt: the gradient runs
        /// out roughly two blur radii beyond the ellipse's edge.
        private static let glowSize = CGSize(width: 1980, height: 1660)
        private static let glowOpacity = 0.5

        @AppStorage(DreamCASTAccentTheme.storageKey) private var selectedThemeRaw = DreamCASTAccentTheme.defaultValue.rawValue
        @AppStorage(DreamCASTVisualSettings.transparencyKey) private var transparency = DreamCASTVisualSettings.defaultTransparency
        @AppStorage(AppAppearance.storageKey) private var displayModeRaw = AppAppearance.defaultValue.rawValue
        @Environment(\.colorScheme) private var systemScheme

        private var lightBackground: Bool {
            let mode = AppAppearance.resolve(displayModeRaw)
            return mode == .light || (mode == .system && systemScheme == .light)
        }

        private var tint: Color {
            DreamCASTAccentTheme.resolve(selectedThemeRaw).color
        }

        var body: some View {
            let tint = tint
            GeometryReader { proxy in
                let scale = proxy.size.width / Self.canvasWidth
                let size = CGSize(width: Self.glowSize.width * scale, height: Self.glowSize.height * scale)
                DreamCASTThemeBackground()
                    .overlay(alignment: .topLeading) {
                        Rectangle()
                            .fill(Self.glow(tint))
                            // The crossfade lives here, keyed on the colour,
                            // rather than in the model's write.
                            .animation(.easeInOut(duration: 0.6), value: tint)
                            .frame(width: size.width, height: size.height)
                            .offset(
                                x: Self.glowCenter.x * scale - size.width / 2,
                                y: Self.glowCenter.y * scale - size.height / 2
                            )
                    }
                    // Keep the cool blue header glow blended into the
                    // channel-color warmth below it, never as a second layer
                    // that begins abruptly at the content/tab boundary.
                    .overlay {
                        LinearGradient(
                            stops: [
                                .init(color: TVNeonTheme.electricBlue.opacity(0.24), location: 0),
                                .init(color: TVNeonTheme.electricBlue.opacity(0.1), location: 0.3),
                                .init(color: .clear, location: 0.62)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .overlay {
                        if !lightBackground { Self.darkening }
                    }
                    .overlay {
                        // Subtle corner light streaks from the approved mockup.
                        // Simple paths keep the background cheap during playback.
                        GeometryReader { canvas in
                            let w = canvas.size.width
                            let h = canvas.size.height

                            Path { path in
                                path.move(to: CGPoint(x: w * 0.84, y: 0))
                                path.addLine(to: CGPoint(x: w * 0.98, y: 0))
                                path.addLine(to: CGPoint(x: w * 0.89, y: h * 0.17))
                            }
                            .stroke(
                                LinearGradient(colors: [.clear, TVNeonTheme.electricBlue.opacity(0.8), .clear],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                            )
                            .shadow(color: TVNeonTheme.electricBlue.opacity(0.7), radius: 11)

                            Path { path in
                                path.move(to: CGPoint(x: 0, y: h * 0.83))
                                path.addCurve(to: CGPoint(x: w * 0.43, y: h),
                                              control1: CGPoint(x: w * 0.16, y: h * 0.69),
                                              control2: CGPoint(x: w * 0.24, y: h * 0.86))
                                path.move(to: CGPoint(x: w * 0.69, y: h))
                                path.addCurve(to: CGPoint(x: w, y: h * 0.84),
                                              control1: CGPoint(x: w * 0.78, y: h * 0.88),
                                              control2: CGPoint(x: w * 0.91, y: h * 0.97))
                            }
                            .stroke(
                                LinearGradient(colors: [TVNeonTheme.electricBlue.opacity(0.12),
                                                        TVNeonTheme.electricBlue.opacity(0.75),
                                                        TVNeonTheme.iceBlue.opacity(0.35)],
                                               startPoint: .leading, endPoint: .trailing),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round)
                            )
                            .shadow(color: TVNeonTheme.electricBlue.opacity(0.55), radius: 12)
                        }
                    }
                    .clipped()
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }

        /// Approximates a blurred solid ellipse: a flat core, half strength at
        /// the original edge, nothing at the frame's edge.
        private static let glowFalloff: [(strength: Double, location: CGFloat)] = [
            (1, 0), (0.97, 0.25), (0.8, 0.45), (0.5, 0.62), (0.2, 0.8), (0.05, 0.92), (0, 1)
        ]

        private static func glow(_ tint: Color) -> EllipticalGradient {
            EllipticalGradient(
                stops: glowFalloff.map {
                    .init(color: tint.opacity(glowOpacity * $0.strength), location: $0.location)
                },
                center: .center,
                startRadiusFraction: 0,
                endRadiusFraction: 0.5
            )
        }

        private static var darkening: LinearGradient { LinearGradient(
            stops: [
                .init(color: base.opacity(0.15), location: 0),
                .init(color: base.opacity(0.7), location: 0.52),
                .init(color: base, location: 0.78),
                .init(color: base, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        ) }
    }
#endif
