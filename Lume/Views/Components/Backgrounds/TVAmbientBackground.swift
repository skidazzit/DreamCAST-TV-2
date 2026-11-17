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

    struct TVAmbientBackground: View {
        /// `nil` paints the Live TV accent; only this view reads its glow.
        let hero: GuideHeroModel?

        /// `#090B10`.
        static let base = Color(.sRGB, red: 9 / 255, green: 11 / 255, blue: 16 / 255, opacity: 1)

        /// Laid out on the 1920 × 1080 design canvas and scaled to the screen.
        private static let canvasWidth: CGFloat = 1920
        private static let glowCenter = CGPoint(x: 1470, y: 230)
        /// The design's 1300 × 980 ellipse blurred by 170 pt: the gradient runs
        /// out roughly two blur radii beyond the ellipse's edge.
        private static let glowSize = CGSize(width: 1980, height: 1660)
        private static let glowOpacity = 0.5

        private var tint: Color {
            hero?.glowTint ?? LiveTVPalette.accent
        }

        var body: some View {
            let tint = tint
            GeometryReader { proxy in
                let scale = proxy.size.width / Self.canvasWidth
                let size = CGSize(width: Self.glowSize.width * scale, height: Self.glowSize.height * scale)
                Self.base
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
                    .overlay(Self.darkening)
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

        private static let darkening = LinearGradient(
            stops: [
                .init(color: base.opacity(0.15), location: 0),
                .init(color: base.opacity(0.7), location: 0.52),
                .init(color: base, location: 0.78),
                .init(color: base, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
#endif

#if os(iOS)
import SwiftUI

/// Matches the tvOS DreamCAST backdrop, sized for a portrait iPhone.
/// A stable root gradient avoids scrolling/parallax and player re-renders.
enum DreamCASTMobileTheme {
    static let midnight = Color(red: 3 / 255, green: 11 / 255, blue: 25 / 255)
    static let electricBlue = Color(red: 17 / 255, green: 127 / 255, blue: 255 / 255)
    static let iceBlue = Color(red: 89 / 255, green: 205 / 255, blue: 255 / 255)
    static let glassTop = Color(red: 27 / 255, green: 45 / 255, blue: 68 / 255)
    static let glassBottom = Color(red: 14 / 255, green: 27 / 255, blue: 47 / 255)
}

struct DreamCASTMobileWallpaper: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            DreamCASTMobileTheme.midnight
                .overlay(alignment: .topTrailing) {
                    EllipticalGradient(
                        stops: [
                            .init(color: DreamCASTMobileTheme.electricBlue.opacity(0.45), location: 0),
                            .init(color: Color(red: 0.36, green: 0.12, blue: 0.35).opacity(0.35), location: 0.35),
                            .init(color: DreamCASTMobileTheme.electricBlue.opacity(0.08), location: 0.7),
                            .init(color: .clear, location: 1)
                        ],
                        center: .center,
                        startRadiusFraction: 0,
                        endRadiusFraction: 0.5
                    )
                    .frame(width: w * 1.7, height: h * 0.95)
                    .offset(x: w * 0.36, y: -h * 0.32)
                }
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: DreamCASTMobileTheme.electricBlue.opacity(0.16), location: 0),
                            .init(color: .clear, location: 0.52)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: DreamCASTMobileTheme.midnight.opacity(0.55), location: 0.6),
                            .init(color: DreamCASTMobileTheme.midnight, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .overlay {
                    Path { path in
                        path.move(to: CGPoint(x: w * 0.78, y: 0))
                        path.addLine(to: CGPoint(x: w * 0.98, y: 0))
                        path.addLine(to: CGPoint(x: w * 0.88, y: h * 0.12))
                        path.move(to: CGPoint(x: 0, y: h * 0.84))
                        path.addCurve(
                            to: CGPoint(x: w * 0.52, y: h),
                            control1: CGPoint(x: w * 0.17, y: h * 0.78),
                            control2: CGPoint(x: w * 0.29, y: h * 0.9)
                        )
                        path.move(to: CGPoint(x: w * 0.7, y: h))
                        path.addCurve(
                            to: CGPoint(x: w, y: h * 0.84),
                            control1: CGPoint(x: w * 0.78, y: h * 0.9),
                            control2: CGPoint(x: w * 0.91, y: h * 0.95)
                        )
                    }
                    .stroke(
                        LinearGradient(
                            colors: [
                                DreamCASTMobileTheme.electricBlue.opacity(0.1),
                                DreamCASTMobileTheme.electricBlue.opacity(0.65),
                                DreamCASTMobileTheme.iceBlue.opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )
                }
                .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Apply to page roots. The wallpaper is not inside ScrollView content.
private struct DreamCASTMobilePageTheme: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background { DreamCASTMobileWallpaper() }
            .toolbarBackground(.hidden, for: .navigationBar)
            .preferredColorScheme(.dark)
    }
}

extension View {
    func dreamCASTPageTheme() -> some View {
        modifier(DreamCASTMobilePageTheme())
    }
}
#endif
