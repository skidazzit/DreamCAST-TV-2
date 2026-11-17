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
    static var midnight: Color { DreamCASTVisualSettings.theme.gradientColors[2] }
    static var electricBlue: Color { DreamCASTVisualSettings.theme.color }
    static var iceBlue: Color { DreamCASTVisualSettings.theme.color.opacity(0.9) }
    static var glassTop: Color { DreamCASTVisualSettings.theme.gradientColors[1] }
    static var glassBottom: Color { DreamCASTVisualSettings.theme.gradientColors[0] }
}

struct DreamCASTMobileWallpaper: View {
    var body: some View {
        DreamCASTThemeBackground()
            .allowsHitTesting(false)
    }
}

/// Shared neon-glass surfaces derived from the tvOS design references.
struct DreamCASTMobileGlass: ViewModifier {
    var highlighted = false
    var radius: CGFloat = 18
    @AppStorage(DreamCASTAccentTheme.storageKey) private var themeRaw = DreamCASTAccentTheme.defaultValue.rawValue
    @AppStorage(DreamCASTVisualSettings.liquidGlassKey) private var liquidGlass = DreamCASTVisualSettings.defaultLiquidGlass
    @AppStorage(DreamCASTVisualSettings.transparencyKey) private var transparency = DreamCASTVisualSettings.defaultTransparency

    func body(content: Content) -> some View {
        let theme = DreamCASTAccentTheme.resolve(themeRaw)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content
            .background {
                shape.fill(LinearGradient(
                    colors: theme.gradientColors.map { $0.opacity(liquidGlass ? transparency * 0.46 : transparency) },
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            }
            .background {
                if liquidGlass {
                    Color.clear
                        .glassEffectCompat(.regular, in: shape)
                        .opacity(transparency * 0.75)
                }
            }
            .overlay {
                shape.strokeBorder(
                    theme.color.opacity(highlighted ? 1 : 0.30),
                    lineWidth: highlighted ? 1.7 : 0.8
                )
            }
            .shadow(color: highlighted ? theme.color.opacity(0.4) : .clear,
                    radius: highlighted ? 13 : 0)
    }
}

struct DreamCASTMobileChip: View {
    @AppStorage(DreamCASTAccentTheme.storageKey) private var themeRaw = DreamCASTAccentTheme.defaultValue.rawValue
    let title: String
    var symbol: String? = nil
    var selected = false
    let action: () -> Void

    init(title: String, symbol: String? = nil, selected: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.selected = selected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.subheadline.weight(.semibold))
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(minHeight: 43)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(LinearGradient(
                            colors: [
                                DreamCASTAccentTheme.resolve(themeRaw).color,
                                DreamCASTAccentTheme.resolve(themeRaw).gradientColors[1]
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                }
            }
            .dreamCASTGlass(highlighted: selected, radius: 14)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// A compact shared brand and section header above the persistent player.
/// Content tabs retain their own navigation stacks and data-driven labels.
struct DreamCASTMobilePageHeading: View {
    let title: String

    var body: some View {
        HStack(alignment: .center) {
            // Shared brand logo, sized to half its former width and height.
            // Keep the tab name only as an accessibility label, not on screen.
            Image("DreamCASTHeaderLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 45, alignment: .leading)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("DreamCAST TV, \(title)")
    }
}

extension View {
    func dreamCASTGlass(highlighted: Bool = false, radius: CGFloat = 18) -> some View {
        modifier(DreamCASTMobileGlass(highlighted: highlighted, radius: radius))
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
