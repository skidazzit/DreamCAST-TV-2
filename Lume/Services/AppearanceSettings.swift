//
//  AppearanceSettings.swift
//  Lume
//
//  The user's app-wide appearance override (System / Dark / Light). Persisted
//  as a plain string and applied at the scene root, so a device in Light Mode
//  can still run Lume permanently dark (and vice versa). `system` keeps the
//  previous follow-the-device behaviour. Not offered on tvOS — the TV UI is
//  designed dark and the whole app is pinned dark via the Info.plist
//  `UIUserInterfaceStyle` key (`INFOPLIST_KEY_UIUserInterfaceStyle
//  [sdk=appletv*]` in the target build settings), so the applier is a no-op.
//  A runtime window override is not enough on tvOS: the system draws the
//  scene backdrop behind the (transparent) window from the *device*
//  appearance, so content pinned dark still sat on a light backdrop (#140).
//
//  Applied as a *window-level* style override (`overrideUserInterfaceStyle` /
//  `NSApp.appearance`) rather than `.preferredColorScheme`: once that modifier
//  has set a non-nil scheme, passing `nil` never returns the presentation to
//  following the device, and a change doesn't reach an already-presented sheet
//  (the Settings sheet stayed in the old scheme). The window override resets
//  cleanly and restyles everything in the window immediately.
//

import SwiftUI
#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case dark
    case light

    static let storageKey = "app.appearance"
    static let defaultValue: AppAppearance = .system

    /// Resolves a persisted raw value, falling back to `system` for missing
    /// or unknown values.
    static func resolve(_ raw: String) -> AppAppearance {
        AppAppearance(rawValue: raw) ?? defaultValue
    }

    var id: String {
        rawValue
    }

    #if canImport(UIKit) && !os(tvOS)
        /// The window override style; `.unspecified` follows the device.
        var interfaceStyle: UIUserInterfaceStyle {
            switch self {
            case .system: .unspecified
            case .dark: .dark
            case .light: .light
            }
        }

    #elseif canImport(AppKit)
        /// The app-wide appearance; `nil` follows the device.
        var nsAppearance: NSAppearance? {
            switch self {
            case .system: nil
            case .dark: NSAppearance(named: .darkAqua)
            case .light: NSAppearance(named: .aqua)
            }
        }
    #endif

    var title: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .dark: "Dark"
        case .light: "Light"
        }
    }
}


/// Accent presets. This is separate from light/dark appearance so users can
/// keep their preferred contrast while changing the app's interactive tint.
enum DreamCASTAccentTheme: String, CaseIterable, Identifiable {
    case dreamcast, lightBlue, ocean, violet, emerald, sunset, ruby, grey, charcoal, white

    static let storageKey = "dreamcast.appearance.accent"
    static let defaultValue: DreamCASTAccentTheme = .dreamcast
    static func resolve(_ raw: String) -> DreamCASTAccentTheme {
        Self(rawValue: raw) ?? defaultValue
    }
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dreamcast: "DreamCAST Blue"
        case .lightBlue: "Light Blue"
        case .ocean: "Ocean"
        case .violet: "Violet"
        case .emerald: "Emerald"
        case .sunset: "Sunset"
        case .ruby: "Ruby"
        case .grey: "Grey"
        case .charcoal: "Charcoal"
        case .white: "White"
        }
    }
    var color: Color {
        switch self {
        case .dreamcast: Color(red: 0.12, green: 0.53, blue: 1)
        case .lightBlue: Color(red: 0.30, green: 0.72, blue: 0.98)
        case .ocean: Color(red: 0, green: 0.76, blue: 0.86)
        case .violet: Color(red: 0.66, green: 0.43, blue: 1)
        case .emerald: Color(red: 0.13, green: 0.79, blue: 0.53)
        case .sunset: Color(red: 1, green: 0.58, blue: 0.25)
        case .ruby: Color(red: 0.99, green: 0.34, blue: 0.44)
        case .grey: Color(red: 0.68, green: 0.71, blue: 0.76)
        case .charcoal: Color(red: 0.43, green: 0.46, blue: 0.51)
        case .white: Color(red: 0.86, green: 0.89, blue: 0.94)
        }
    }
    var gradientColors: [Color] {
        switch self {
        case .lightBlue: [Color(red: 0.08, green: 0.19, blue: 0.28), Color(red: 0.12, green: 0.34, blue: 0.49), Color(red: 0.05, green: 0.12, blue: 0.20)]
        case .dreamcast: [Color(red: 0.05, green: 0.10, blue: 0.21), Color(red: 0.07, green: 0.20, blue: 0.36), Color(red: 0.02, green: 0.06, blue: 0.16)]
        case .ocean: [Color(red: 0.03, green: 0.15, blue: 0.18), Color(red: 0.02, green: 0.30, blue: 0.34), Color(red: 0.01, green: 0.11, blue: 0.14)]
        case .violet: [Color(red: 0.15, green: 0.08, blue: 0.24), Color(red: 0.24, green: 0.12, blue: 0.38), Color(red: 0.10, green: 0.04, blue: 0.18)]
        case .emerald: [Color(red: 0.04, green: 0.16, blue: 0.11), Color(red: 0.06, green: 0.29, blue: 0.19), Color(red: 0.03, green: 0.11, blue: 0.08)]
        case .sunset: [Color(red: 0.24, green: 0.12, blue: 0.07), Color(red: 0.40, green: 0.18, blue: 0.10), Color(red: 0.18, green: 0.08, blue: 0.05)]
        case .ruby: [Color(red: 0.22, green: 0.06, blue: 0.10), Color(red: 0.36, green: 0.08, blue: 0.15), Color(red: 0.16, green: 0.04, blue: 0.08)]
        case .grey: [Color(red: 0.16, green: 0.18, blue: 0.22), Color(red: 0.24, green: 0.26, blue: 0.31), Color(red: 0.11, green: 0.12, blue: 0.16)]
        case .charcoal: [Color(red: 0.05, green: 0.06, blue: 0.08), Color(red: 0.10, green: 0.11, blue: 0.14), Color(red: 0.03, green: 0.04, blue: 0.05)]
        case .white: [Color(red: 0.94, green: 0.96, blue: 0.99), Color(red: 0.86, green: 0.90, blue: 0.95), Color(red: 0.78, green: 0.84, blue: 0.91)]
        }
    }
    /// In Light Mode, retain the chosen hue with pale backgrounds.
    func backgroundColors(light: Bool) -> [Color] {
        if self == .white {
            return light ? gradientColors : [
                Color(red: 0.16, green: 0.19, blue: 0.24),
                Color(red: 0.26, green: 0.30, blue: 0.36),
                Color(red: 0.10, green: 0.13, blue: 0.17)
            ]
        }
        if !light { return gradientColors }
        return [
            Color.white.opacity(0.94),
            Color(red: 0.91, green: 0.94, blue: 0.98),
            Color(red: 0.84, green: 0.89, blue: 0.95)
        ]
    }
    var selectionAccent: Color {
        self == .white ? Color(red: 0.24, green: 0.33, blue: 0.45) : color
    }
    var gradient: LinearGradient {
        LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Shared per-device visual options. An old install keeps its current feel.
enum DreamCASTVisualSettings {
    static let liquidGlassKey = "dreamcast.appearance.liquidGlass"
    static let transparencyKey = "dreamcast.appearance.transparency"
    static let defaultLiquidGlass = true
    static let defaultTransparency = 0.35

    static var theme: DreamCASTAccentTheme {
        DreamCASTAccentTheme.resolve(UserDefaults.standard.string(forKey: DreamCASTAccentTheme.storageKey) ?? "")
    }
    static var transparency: Double {
        guard UserDefaults.standard.object(forKey: transparencyKey) != nil else { return defaultTransparency }
        return min(0.85, max(0, UserDefaults.standard.double(forKey: transparencyKey)))
    }
    static var liquidGlass: Bool {
        guard UserDefaults.standard.object(forKey: liquidGlassKey) != nil else { return defaultLiquidGlass }
        return UserDefaults.standard.bool(forKey: liquidGlassKey)
    }
}

/// Shared tinted settings rows and sections that follow the selected theme.
struct DreamCASTThemePanel: View {
    @AppStorage(DreamCASTAccentTheme.storageKey)
    private var themeRaw = DreamCASTAccentTheme.defaultValue.rawValue
    @AppStorage(AppAppearance.storageKey)
    private var appearanceRaw = AppAppearance.defaultValue.rawValue
    @Environment(\.colorScheme) private var deviceScheme

    var body: some View {
        let theme = DreamCASTAccentTheme.resolve(themeRaw)
        let mode = AppAppearance.resolve(appearanceRaw)
        let light = mode == .light || (mode == .system && deviceScheme == .light)
        Rectangle()
            .fill(light ? Color.white.opacity(0.75)
                        : theme.gradientColors[1].opacity(0.94))
            .overlay(theme.selectionAccent.opacity(light ? 0.055 : 0.08))
    }
}

/// A static, low-cost ambient glow that changes when the saved theme changes.
/// No timer or animation loop is used, so playback stays smooth.
struct DreamCASTThemeBackground: View {
    @AppStorage(DreamCASTAccentTheme.storageKey)
    private var themeRaw = DreamCASTAccentTheme.defaultValue.rawValue
    @AppStorage(AppAppearance.storageKey)
    private var appearanceRaw = AppAppearance.defaultValue.rawValue
    @Environment(\.colorScheme) private var systemColorScheme

    var body: some View {
        let theme = DreamCASTAccentTheme.resolve(themeRaw)
        let mode = AppAppearance.resolve(appearanceRaw)
        let isLight = mode == .light || (mode == .system && systemColorScheme == .light)
        ZStack {
            LinearGradient(colors: theme.backgroundColors(light: isLight),
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(
                colors: [theme.color.opacity(isLight ? 0.10 : 0.22), .clear],
                center: .topTrailing,
                startRadius: 30,
                endRadius: 600
            )
            RadialGradient(
                colors: [theme.color.opacity(isLight ? 0.05 : 0.09), .clear],
                center: .bottomLeading,
                startRadius: 30,
                endRadius: 450
            )
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.35), value: themeRaw)
        .animation(.easeInOut(duration: 0.25), value: appearanceRaw)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Applies the user's appearance override to the hosting window (see the
    /// file header for why this is not `.preferredColorScheme`). Views that
    /// force their own scheme (the players' `.preferredColorScheme(.dark)`)
    /// still win for their presentation. No-op on tvOS, which has no
    /// Appearance setting — the TV UI is pinned dark by the Info.plist
    /// `UIUserInterfaceStyle` key (see the file header).
    func appAppearance(_ appearance: AppAppearance) -> some View {
        #if os(tvOS)
            return self
        #elseif canImport(UIKit)
            return background(
                AppearanceWindowApplier(style: appearance.interfaceStyle)
                    .allowsHitTesting(false)
            )
        #elseif canImport(AppKit)
            return onChange(of: appearance, initial: true) { _, newValue in
                NSApp.appearance = newValue.nsAppearance
            }
        #endif
    }
}

#if canImport(UIKit) && !os(tvOS)
    /// A zero-size probe that reaches its hosting `UIWindow` and sets
    /// `overrideUserInterfaceStyle` — restyling every presentation in the
    /// window (including open sheets) and cleanly reverting to the device
    /// appearance with `.unspecified`.
    private struct AppearanceWindowApplier: UIViewRepresentable {
        let style: UIUserInterfaceStyle

        func makeUIView(context _: Context) -> ProbeView {
            ProbeView()
        }

        func updateUIView(_ view: ProbeView, context _: Context) {
            view.style = style
        }

        final class ProbeView: UIView {
            var style: UIUserInterfaceStyle = .unspecified {
                didSet { window?.overrideUserInterfaceStyle = style }
            }

            /// The window is nil during makeUIView; re-apply once attached.
            override func didMoveToWindow() {
                super.didMoveToWindow()
                window?.overrideUserInterfaceStyle = style
            }
        }
    }
#endif
