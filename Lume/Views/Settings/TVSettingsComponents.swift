//
//  TVSettingsComponents.swift
//  Lume
//
//  Shared building blocks for the tvOS settings surfaces (Settings, Add
//  Playlist, Playlist detail). They give all three a single minimal, flat look
//  that mirrors the Apple TV Settings app: compact rows, small uppercase
//  section labels, and a quiet light focus highlight with no scale or shadow.
//

#if os(tvOS)

    import SwiftUI

    // MARK: - Metrics

    enum TVSettingsMetrics {
        static let rowFontSize: CGFloat = 26
        static let rowHPadding: CGFloat = 20
        static let rowVPadding: CGFloat = 14
        static let rowCornerRadius: CGFloat = 10
        static let labelFontSize: CGFloat = 18
        static let secondaryFontSize: CGFloat = 20
        static let statusFontSize: CGFloat = 24
        static let titleFontSize: CGFloat = 46
        static let contentMaxWidth: CGFloat = 760
        /// Width of the Settings detail pane content (sits next to the rail, so
        /// it gets a touch more room than the full-screen `contentMaxWidth`).
        static let detailMaxWidth: CGFloat = 860
        /// Width of a secondary column sitting beside a `contentMaxWidth` one.
        static let sideColumnWidth: CGFloat = 560
        static var background: Color { DreamCASTDisplayColors.isLight
            ? Color(red: 0.92, green: 0.95, blue: 0.98)
            : DreamCASTVisualSettings.theme.gradientColors[2]
        }
    }

    extension View {
        /// The flat dark fill shared by every tvOS settings surface.
        func tvSettingsBackground() -> some View {
            background(TVSettingsMetrics.background.ignoresSafeArea())
        }

        /// Frames a Settings pane's content beside the rail: its top level
        /// with the rail's first row, room below the last to scroll it clear.
        func tvSettingsPaneContent(maxWidth: CGFloat = TVSettingsMetrics.detailMaxWidth) -> some View {
            frame(maxWidth: maxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 16)
                .padding(.bottom, 72)
        }

        /// The quiet secondary line shared by the status and empty-state
        /// messages, inset to line up with the row labels above it.
        func tvSettingsSecondaryText() -> some View {
            font(.system(size: TVSettingsMetrics.statusFontSize))
                .foregroundStyle(.secondary)
                .padding(.horizontal, TVSettingsMetrics.rowHPadding)
        }
    }

    // MARK: - Section label

    /// A small uppercase grouped-section header.
    struct TVSettingsSectionLabel: View {
        private let title: LocalizedStringKey

        init(_ title: LocalizedStringKey) {
            self.title = title
        }

        var body: some View {
            // `.textCase` uppercases the *localized* string for display while the
            // catalog lookup still happens on the original-case key.
            Text(title)
                .textCase(.uppercase)
                .font(.system(size: TVSettingsMetrics.labelFontSize, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(.secondary)
                .padding(.horizontal, TVSettingsMetrics.rowHPadding)
                .padding(.bottom, 4)
        }
    }

    // MARK: - Read-only value row

    /// Read-only rows must still take tvOS focus. Otherwise, pressing Up
    /// skips the account/server details and cannot navigate back to the top.
    /// Focus here is visual only; Select never changes or reveals stored data.
    struct TVSettingsValueRow<Value: View>: View {
        private let label: LocalizedStringKey
        private let value: Value
        @FocusState private var rowFocused: Bool

        init(_ label: LocalizedStringKey, @ViewBuilder value: () -> Value) {
            self.label = label
            self.value = value()
        }

        var body: some View {
            HStack(spacing: 16) {
                Text(label)
                Spacer(minLength: 16)
                value
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: TVSettingsMetrics.rowFontSize))
            .padding(.horizontal, TVSettingsMetrics.rowHPadding)
            .padding(.vertical, TVSettingsMetrics.rowVPadding + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: TVSettingsMetrics.rowCornerRadius, style: .continuous)
                    .fill(rowFocused ? TVNeonTheme.glassTop : TVNeonTheme.glassBottom)
            }
            .overlay {
                RoundedRectangle(cornerRadius: TVSettingsMetrics.rowCornerRadius, style: .continuous)
                    .strokeBorder(rowFocused ? TVNeonTheme.iceBlue : .clear,
                                  lineWidth: rowFocused ? 2 : 0)
            }
            .contentShape(RoundedRectangle(cornerRadius: TVSettingsMetrics.rowCornerRadius))
            .focusable(true)
            .focusEffectDisabled()
            .focused($rowFocused)
        }
    }

    extension TVSettingsValueRow where Value == Text {
        init(_ label: LocalizedStringKey, value: String) {
            // `value` is dynamic data (a name, URL, status), so it stays verbatim.
            self.init(label) { Text(verbatim: value) }
        }
    }

    // MARK: - Action row

    /// A full-width row that runs an action: icon, title, and a spinner while
    /// `isBusy`.
    struct TVSettingsActionRow: View {
        private let title: LocalizedStringKey
        private let systemImage: String
        private let isDestructive: Bool
        private let isBusy: Bool
        private let action: () -> Void

        init(
            _ title: LocalizedStringKey,
            systemImage: String,
            isDestructive: Bool = false,
            isBusy: Bool = false,
            action: @escaping () -> Void
        ) {
            self.title = title
            self.systemImage = systemImage
            self.isDestructive = isDestructive
            self.isBusy = isBusy
            self.action = action
        }

        var body: some View {
            Button(action: action) {
                HStack(spacing: 16) {
                    Text(Image(systemName: systemImage))
                        .font(.system(size: 22, weight: .medium))
                        .frame(width: 28, height: 31)
                    Text(title)
                    Spacer(minLength: 0)
                    if isBusy { ProgressView() }
                }
            }
            .buttonStyle(TVSettingsRowButtonStyle(isDestructive: isDestructive))
        }
    }

    // MARK: - Labelled text field

    /// A labelled input row. The field itself keeps the native tvOS appearance
    /// (its focus treatment is system-drawn and can't be cleanly replaced); only
    /// the small uppercase label and spacing are ours.
    struct TVSettingsField: View {
        let title: LocalizedStringKey
        let placeholder: LocalizedStringKey
        @Binding var text: String
        var isSecure: Bool = false
        var contentType: UITextContentType?
        var whiteText = false

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .textCase(.uppercase)
                    .font(.system(size: TVSettingsMetrics.labelFontSize, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(whiteText ? Color.white : Color.secondary)
                    .padding(.horizontal, TVSettingsMetrics.rowHPadding)

                Group {
                    if isSecure {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .font(.system(size: TVSettingsMetrics.rowFontSize))
                .foregroundStyle(whiteText ? Color.white : Color.primary)
                .textContentType(contentType)
                .autocorrectionDisabled()
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(DreamCASTDisplayColors.surface)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(DreamCASTVisualSettings.theme.selectionAccent.opacity(0.36),
                                      lineWidth: 1)
                }
            }
        }
    }

    // MARK: - Reorderable row

    /// One row of a reorderable tvOS settings list: caller-supplied leading
    /// content, then up / down controls and an optional remove button. The row
    /// is a full-width focus band — a narrow target wouldn't catch "down" from
    /// the row above.
    ///
    /// `onMove` receives the offset (-1 / +1); `name` is only used for the
    /// controls' VoiceOver labels.
    struct TVSettingsReorderRow<Leading: View>: View {
        private let name: String
        private let index: Int
        private let count: Int
        private let onMove: (Int) -> Void
        private let onRemove: (() -> Void)?
        private let leading: Leading

        init(
            name: String,
            index: Int,
            count: Int,
            onMove: @escaping (Int) -> Void,
            onRemove: (() -> Void)? = nil,
            @ViewBuilder leading: () -> Leading
        ) {
            self.name = name
            self.index = index
            self.count = count
            self.onMove = onMove
            self.onRemove = onRemove
            self.leading = leading()
        }

        var body: some View {
            HStack(spacing: 16) {
                leading

                Spacer(minLength: 0)

                Button {
                    onMove(-1)
                } label: {
                    Text(Image(systemName: "chevron.up"))
                }
                .buttonStyle(TVContentIconButtonStyle())
                .disabled(index == 0)
                .accessibilityLabel("Move \(name) up")

                Button {
                    onMove(1)
                } label: {
                    Text(Image(systemName: "chevron.down"))
                }
                .buttonStyle(TVContentIconButtonStyle())
                .disabled(index == count - 1)
                .accessibilityLabel("Move \(name) down")

                if let onRemove {
                    Button(action: onRemove) {
                        Text(Image(systemName: "minus"))
                    }
                    .buttonStyle(TVContentIconButtonStyle())
                    .accessibilityLabel("Remove \(name)")
                }
            }
            .padding(.horizontal, TVSettingsMetrics.rowHPadding)
            .padding(.vertical, TVSettingsMetrics.rowVPadding)
            .background(
                RoundedRectangle(cornerRadius: TVSettingsMetrics.rowCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
        }
    }

    // MARK: - Reordering

    extension Array {
        /// Swaps the element at `index` with the one `offset` slots away,
        /// reporting whether the move was in bounds.
        mutating func move(at index: Int, by offset: Int) -> Bool {
            let target = index + offset
            guard indices.contains(index), indices.contains(target) else { return false }
            swapAt(index, target)
            return true
        }
    }

    extension View {
        /// Focus decoration for tvOS Menu labels, which don't take a ButtonStyle.
        func dashboardFocusHighlight(_ focused: Bool) -> some View {
            background {
                if focused {
                    RoundedRectangle(cornerRadius: 14).fill(TVNeonTheme.selection)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(focused ? TVNeonTheme.iceBlue : .clear,
                                  lineWidth: focused ? 2 : 0)
            }
        }
    }

    /// Cyan outline and navy glass. No tvOS icon zoom or white focus plate.
    struct TVDashboardCardStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            FocusedCard(configuration: configuration)
        }

        private struct FocusedCard: View {
            let configuration: ButtonStyleConfiguration
            @Environment(\.isFocused) private var isFocused
            @Environment(\.colorScheme) private var scheme
            @AppStorage(AppAppearance.storageKey) private var displayModeRaw = AppAppearance.defaultValue.rawValue
            @AppStorage(DreamCASTAccentTheme.storageKey) private var themeRaw = DreamCASTAccentTheme.defaultValue.rawValue
            @AppStorage(DreamCASTVisualSettings.liquidGlassKey) private var liquidGlass = DreamCASTVisualSettings.defaultLiquidGlass
            @AppStorage(DreamCASTVisualSettings.transparencyKey) private var transparency = DreamCASTVisualSettings.defaultTransparency

            var body: some View {
                let mode = AppAppearance.resolve(displayModeRaw)
                let light = mode == .light || (mode == .system && scheme == .light)
                return configuration.label
                    .foregroundStyle(Color.white)
                    .background {
                        if liquidGlass && !isFocused {
                            Color.clear
                                .glassEffectCompat(.regular, in: RoundedRectangle(cornerRadius: 16))
                                .opacity(1 - transparency)
                        }
                    }
                    .background {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isFocused
                                  ? AnyShapeStyle(TVNeonTheme.selection)
                                  : AnyShapeStyle(TVNeonTheme.glass))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                isFocused ? TVNeonTheme.iceBlue : .white.opacity(0.16),
                                lineWidth: isFocused ? 2.5 : 1
                            )
                    }
                    .shadow(
                        color: isFocused ? TVNeonTheme.electricBlue.opacity(0.43) : .clear,
                        radius: isFocused ? 12 : 0
                    )
                    .focusEffectDisabled()
            }
        }
    }

    // MARK: - Button styles

    /// A minimal full-width content row: a faint resting fill that turns to a
    /// quiet light highlight with dark text when focused. Flat — no scale or
    /// shadow. Pass `isDestructive` for a red treatment.
    struct TVSettingsRowButtonStyle: ButtonStyle {
        var isDestructive: Bool = false

        func makeBody(configuration: Configuration) -> some View {
            StyleBody(configuration: configuration, isDestructive: isDestructive)
        }

        struct StyleBody: View {
            let configuration: ButtonStyleConfiguration
            let isDestructive: Bool
            @Environment(\.isFocused) private var isFocused
            @Environment(\.isEnabled) private var isEnabled
            @Environment(\.colorScheme) private var scheme
            @AppStorage(AppAppearance.storageKey) private var displayModeRaw = AppAppearance.defaultValue.rawValue
            @AppStorage(DreamCASTVisualSettings.liquidGlassKey)
            private var liquidGlass = DreamCASTVisualSettings.defaultLiquidGlass
            @AppStorage(DreamCASTVisualSettings.transparencyKey)
            private var transparency = DreamCASTVisualSettings.defaultTransparency

            var body: some View {
                let mode = AppAppearance.resolve(displayModeRaw)
                let light = mode == .light || (mode == .system && scheme == .light)
                let foreground: Color = isDestructive && !isFocused ? .red : .white
                let fill: AnyShapeStyle = isFocused
                    ? (isDestructive ? AnyShapeStyle(Color.red)
                                     : AnyShapeStyle(TVNeonTheme.selection))
                    : AnyShapeStyle(TVNeonTheme.glass)
                return configuration.label
                    .font(.system(size: TVSettingsMetrics.rowFontSize))
                    .foregroundStyle(foreground)
                    .opacity(isEnabled ? 1 : 0.4)
                    .padding(.horizontal, TVSettingsMetrics.rowHPadding)
                    .padding(.vertical, TVSettingsMetrics.rowVPadding + 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        if liquidGlass && !isFocused {
                            Color.clear
                                .glassEffectCompat(
                                    .regular,
                                    in: RoundedRectangle(cornerRadius: TVSettingsMetrics.rowCornerRadius)
                                )
                                .opacity(1 - transparency)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: TVSettingsMetrics.rowCornerRadius, style: .continuous)
                            .fill(fill)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: TVSettingsMetrics.rowCornerRadius)
                            .strokeBorder(isFocused ? TVNeonTheme.iceBlue : .clear,
                                          lineWidth: isFocused ? 2 : 0)
                    }
                    .focusEffectDisabled()
                    .animation(.easeOut(duration: 0.15), value: isFocused)
            }
        }
    }

    /// A compact, auto-width action button (e.g. Add Playlist / Cancel). Quiet
    /// resting fill, light highlight with dark text on focus. `prominent` gives a
    /// slightly stronger resting fill for the primary action.
    struct TVSettingsActionButtonStyle: ButtonStyle {
        var prominent: Bool = false
        var whiteText: Bool = false

        func makeBody(configuration: Configuration) -> some View {
            StyleBody(configuration: configuration, prominent: prominent, whiteText: whiteText)
        }

        struct StyleBody: View {
            let configuration: ButtonStyleConfiguration
            let prominent: Bool
            let whiteText: Bool
            @Environment(\.isFocused) private var isFocused
            @Environment(\.isEnabled) private var isEnabled
            @Environment(\.colorScheme) private var systemScheme
            @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.defaultValue.rawValue
            @AppStorage(DreamCASTVisualSettings.transparencyKey) private var transparency = DreamCASTVisualSettings.defaultTransparency

            var body: some View {
                let mode = AppAppearance.resolve(appearanceRaw)
                let light = mode == .light || (mode == .system && systemScheme == .light)
                let restFill = TVNeonTheme.glassBottom.opacity(max(0.65, 1 - transparency * 0.35))
                return configuration.label
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color.white)
                    .opacity(isEnabled ? 1 : 0.4)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: TVSettingsMetrics.rowCornerRadius, style: .continuous)
                            .fill(isFocused ? AnyShapeStyle(TVNeonTheme.selection) : AnyShapeStyle(restFill))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: TVSettingsMetrics.rowCornerRadius)
                            .strokeBorder(isFocused ? TVNeonTheme.iceBlue : .clear,
                                          lineWidth: isFocused ? 2 : 0)
                    }
                    .focusEffectDisabled()
                    .animation(.easeOut(duration: 0.15), value: isFocused)
            }
        }
    }

#endif
