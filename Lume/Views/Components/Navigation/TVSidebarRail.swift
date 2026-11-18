//
//  TVSidebarRail.swift
//  Lume
//
//  The tvOS glass sidebar beside a content pane — Live TV's categories and
//  Settings' categories. Moving focus only highlights a row; Select runs it.
//  Focus entering the rail always lands on the selected row.
//

#if os(tvOS)
    import SwiftUI

    /// Keep an SF Symbol inside Text to avoid tvOS button label image zoom.
    /// All action buttons should focus as a whole without enlarging the icon.
    struct TVFixedButtonLabel: View {
        let title: LocalizedStringKey
        let systemName: String
        var iconSize: CGFloat = 22

        var body: some View {
            HStack(spacing: 10) {
                Text(Image(systemName: systemName))
                    .font(.system(size: iconSize, weight: .semibold))
                    .frame(width: iconSize + 5, height: iconSize + 7)
                    .accessibilityHidden(true)
                Text(title)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Fixed-size artwork is drawn outside focused Button labels.
    /// tvOS otherwise lifts and enlarges an AsyncImage when its parent takes focus.
    struct TVFixedFocusIcon: View {
        let url: URL?
        let systemName: String
        let size: CGFloat

        var body: some View {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFit()
                } else {
                    Text(Image(systemName: systemName))
                        .font(.system(size: size * 0.66, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .frame(width: size, height: size)
            .clipped()
            .focusEffectDisabled()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Moves only overflowing category names while their row is highlighted.
    /// The row and its icon stay fixed, so remote focus does not jump.
    private struct TVSidebarMarqueeTitle: View {
        let title: Text
        let isHighlighted: Bool
        let font: Font

        @State private var measuredWidth: CGFloat = 0
        @State private var focusBegan = Date()

        var body: some View {
            GeometryReader { geometry in
                let overflow = max(0, measuredWidth - geometry.size.width)
                TimelineView(.animation(minimumInterval: 1.0 / 30.0,
                                        paused: !isHighlighted || overflow < 2)) { timeline in
                    let elapsed = max(0, timeline.date.timeIntervalSince(focusBegan) - 0.8)
                    let slideTime = Double(overflow) / 34.0
                    let cycle = max(1, slideTime + 2.0)
                    let position = elapsed.truncatingRemainder(dividingBy: cycle)
                    let distance = min(overflow, CGFloat(min(position, slideTime) * 34.0))
                    title
                        .font(font)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .offset(x: isHighlighted ? -distance : 0)
                        .frame(width: geometry.size.width, alignment: .leading)
                }
                .frame(width: geometry.size.width, height: geometry.size.height,
                       alignment: .leading)
                .clipped()
            }
            .frame(height: 35)
            .background(alignment: .leading) {
                title
                    .font(font)
                    .fixedSize(horizontal: true, vertical: false)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) {
                        $0.size.width
                    } action: { measuredWidth = $0 }
            }
            .onChange(of: isHighlighted) { _, highlighted in
                if highlighted { focusBegan = Date() }
            }
        }
    }

    /// One row of a `TVSidebarRail`.
    struct TVSidebarRailItem: Identifiable {
        let id: String
        let title: Text
        /// Appears before the title; nil leaves the row without one.
        var icon: String?
        /// Optional league art. Only SportsZone supplies it.
        var badgeURL: URL?
        /// A group title drawn above the row — a Combined member's name over
        /// its first category. Plain text, so focus steps over it.
        var header: String?
        /// Replaces the symbol's default VoiceOver name when the icon carries
        /// meaning of its own, such as a warning badge.
        var iconAccessibilityLabel: Text?
        let action: () -> Void
    }

    /// Owns the rail's `@FocusState` so focus changes here never propagate up
    /// to the screen and rebuild its (possibly expensive) content pane.
    struct TVSidebarRail: View {
        static let width: CGFloat = 340
        /// The gap between the rail and the pane beside it.
        static let paneSpacing: CGFloat = 32

        /// The rows, in focus order.
        let items: [TVSidebarRailItem]
        /// The row that reads as selected, and the one entry snaps to.
        let selectedID: String?
        /// When true, a horizontal entry stays on the nearest row selected
        /// by tvOS instead of resetting to the active category.
        var preserveGeometricEntry = false
        /// Bumped to move focus onto the selected row from outside the rail —
        /// Menu from the content pane, or an entry catcher.
        var focusRequest = 0
        /// Bumped as the screen sends focus from a row into its pane. A pane
        /// with nothing focusable refuses it, and the engine then drops focus
        /// on some other row (the first); treated as an entry, that landing is
        /// masked and snapped back to the selected row.
        var focusHandOffRequest = 0
        /// Draws every row unfocused and leaves focus where it lands — for
        /// focus only passing through the rail on its way into the pane.
        var masksFocus = false
        /// Told when focus settles into (`true`) or out of (`false`) the rail.
        var onFocusChange: (Bool) -> Void = { _ in }
        /// Optional two-column navigation support. Other rail callers keep
        /// their existing focus behavior.
        var onMoveRight: (String) -> Void = { _ in }
        var onRowCenterChange: (String, CGFloat) -> Void = { _, _ in }
        var requestedFocusID: String? = nil
        var requestedFocusSerial = 0

        /// Coordinates Back focus with the app-root mini-player and menu.
        /// Optional so standalone rail previews still work.
        @Environment(TVBackFocusCoordinator.self) private var backFocus: TVBackFocusCoordinator?

        /// The focused row's id.
        @FocusState private var focused: String?
        /// Whether focus is settled inside the rail. Cleared when focus
        /// leaves, so it is already false — and rendered — before the engine
        /// hands focus back. Entry lands on the geometrically nearest row,
        /// not the selected one (`prefersDefaultFocus` can't steer the UIKit
        /// hand-off), and the snap to the selection only runs a commit later:
        /// without the pre-armed mask the wrong row flashes fully styled for
        /// that first frame.
        @State private var railOwnsFocus = false
        /// Set by `focusHandOffRequest` until focus has left or the pane has
        /// had its chance. Meanwhile the selected row keeps its focused look
        /// while focus is anywhere in the rail, so a refused hand-off's detour
        /// to another row doesn't blink it.
        @State private var handOffPending = false
        /// The pending "focus left the rail" verdict, cancelled when focus
        /// lands on a row again before it runs.
        @State private var exitCheck: Task<Void, Never>?
        /// The panel in window coordinates, to tell focus that left the rail
        /// from focus parked on its scroll view's fast-scroll index.
        @State private var panelFrame: CGRect = .zero
        @State private var crossPaneFocusID: String?
        @AppStorage(DreamCASTAccentTheme.storageKey)
        private var themeRaw = DreamCASTAccentTheme.defaultValue.rawValue
        @AppStorage(DreamCASTVisualSettings.transparencyKey)
        private var transparency = DreamCASTVisualSettings.defaultTransparency
        @AppStorage(DreamCASTVisualSettings.liquidGlassKey)
        private var liquidGlass = DreamCASTVisualSettings.defaultLiquidGlass

        private let panelPadding: CGFloat = 16
        private let rowInset: CGFloat = 18
        private let iconSize: CGFloat = 22

        private var panelShape: RoundedRectangle {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
        }

        private var itemIDs: [String] {
            items.map(\.id)
        }

        var body: some View {
            ScrollViewReader { proxy in
                panel(proxy)
            }
        }

        private func panel(_ proxy: ScrollViewProxy) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        rows
                    }
                    // The same inset on every side, so the first row sits in
                    // the panel's corner like the rest of the rows; it also
                    // holds the focused row's lift.
                    .padding(panelPadding)
                    .padding(.bottom, 60)
                }
                .scrollIndicators(.visible)
                // The ScrollView itself must not paint tvOS's white focus
                // rectangle behind the custom neon selected channel row.
                .focusEffectDisabled()
                // tvOS scroll views draw outside their bounds (for focus
                // effects), so a long list would run out of the panel's
                // bottom; it scrolls inside the glass instead.
                .clipped()
                .focusSection()
            }
            .frame(width: Self.width, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .top)
            .background {
                if liquidGlass {
                    Color.clear
                        .glassEffectCompat(.regular, in: panelShape)
                        .opacity(0.82)
                }
            }
            .background(panelShape.fill(TVNeonTheme.glass))
            .foregroundStyle(.white)
            .overlay(panelShape.strokeBorder(TVNeonTheme.iceBlue.opacity(0.36), lineWidth: 1))
            .shadow(color: .black.opacity(0.42), radius: 20, y: 10)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { panelFrame = $0 }
            .onExitCommand {
                // A sidebar's Back always advances to the top app menu.
                // Routing through the root also preserves its exit prompt.
                NotificationCenter.default.post(
                    name: .dreamCASTReturnToTopMenu,
                    object: nil
                )
            }
            .onChange(of: itemIDs) { _, ids in
                // The focused row went away under focus (an entry turned off
                // or unpaired): hand focus to the selection rather than
                // leaving the engine to pick a row.
                if let focused, !ids.contains(focused) { focusSelection(proxy) }
            }
            .onChange(of: requestedFocusSerial) { _, _ in
                guard let requestedFocusID, itemIDs.contains(requestedFocusID) else { return }
                // A horizontal handoff is not a fresh sidebar entry.
                // Arm focus ownership before UIKit can land on another row,
                // so the normal selected-item snap cannot override it.
                exitCheck?.cancel()
                handOffPending = false
                crossPaneFocusID = requestedFocusID
                railOwnsFocus = true
                focusRow(requestedFocusID, proxy: proxy)
            }
            .onChange(of: focusRequest) { _, _ in
                focusSelection(proxy)
            }
            .onChange(of: backFocus?.sidebarFocusRequest) { _, _ in
                // Back from a mini-player (or a page with no player) enters
                // this exact tab's selected sidebar row, not a random row.
                focusSelection(proxy)
            }
            .onChange(of: focusHandOffRequest) { _, _ in
                railOwnsFocus = false
                handOffPending = true
                // Focus still here once the pane has had its chance means it
                // stayed on the selected row: the rail owns it again, so moves
                // within it aren't snapped back as entries.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    handOffPending = false
                    if focused != nil, !railOwnsFocus {
                        railOwnsFocus = true
                    }
                }
            }
            .onChange(of: focused) { _, newValue in
                if newValue != nil {
                    backFocus?.markFocused(.sidebar)
                }
                focusDidChange(to: newValue, proxy: proxy)
            }
        }

        private func focusDidChange(to newValue: String?, proxy: ScrollViewProxy) {
            exitCheck?.cancel()
            guard let newValue else {
                handOffPending = false
                // A move onto a row the lazy list only just built passes
                // through nil — for several frames while the list is swiped
                // through fast, so a single turn isn't enough: read as an
                // exit, the next row snapped focus back to the selection.
                // Scrolling fast also hands focus to the scroll view's
                // fast-scroll index, for as long as the user scrubs it; it
                // sits inside the panel, so the verdict waits until focus is
                // outside. Only then has focus left the rail; re-entry takes
                // another press, well after. Pre-arm the mask for it.
                exitCheck = Task { @MainActor in
                    repeat {
                        try? await Task.sleep(for: .milliseconds(250))
                        guard !Task.isCancelled, focused == nil else { return }
                    } while systemFocusIsInPanel
                    railOwnsFocus = false
                    if backFocus?.zone == .sidebar {
                        backFocus?.markFocused(.content)
                    }
                    onFocusChange(false)
                }
                return
            }
            if !railOwnsFocus {
                onFocusChange(true)
            }
            if let requested = crossPaneFocusID, newValue != requested {
                // UIKit may briefly pick a geometric neighbor before the
                // explicit horizontal target. Do not snap to selectedID.
                focusRow(requested, proxy: proxy)
                return
            }
            if !railOwnsFocus, !masksFocus, !preserveGeometricEntry,
               let selectedID, newValue != selectedID,
               newValue != crossPaneFocusID {
                // Entry landed on the wrong row (masked, so it never rendered
                // styled) — snap to the selection. It may sit scrolled out of
                // the lazy list, where a focus write finds nothing: bring it
                // in first (only as far as needed, so a visible selection
                // doesn't move), then focus it a turn later. The mask stays on
                // until focus reaches it — lifted any earlier, the landing row
                // starts its focus fade and flashes. Should the engine refuse
                // the write, it lifts anyway so the rail never stays masked.
                withTransaction(Transaction(animation: nil)) {
                    proxy.scrollTo(selectedID)
                }
                Task { @MainActor in
                    focused = selectedID
                    try? await Task.sleep(for: .milliseconds(300))
                    if !railOwnsFocus {
                        railOwnsFocus = true
                    }
                }
            } else {
                railOwnsFocus = true
                if newValue == crossPaneFocusID { crossPaneFocusID = nil }
            }
        }

        /// Whether UIKit's focus sits inside the panel — for a nil `focused`,
        /// on the fast-scroll index, which `@FocusState` can't see.
        private var systemFocusIsInPanel: Bool {
            let window = UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first
            guard let window,
                  let item = UIFocusSystem.focusSystem(for: window)?.focusedItem,
                  let space = item.parentFocusEnvironment?.focusItemContainer?.coordinateSpace
            else { return false }
            let frame = space.convert(item.frame, to: window)
            return panelFrame.contains(CGPoint(x: frame.midX, y: frame.midY))
        }

        /// Focuses the selected row, scrolling it into the lazy list first.
        /// Deferred: a same-frame focus write from a focus or Menu callback
        /// gets dropped.
        private func focusSelection(_ proxy: ScrollViewProxy) {
            guard let selectedID else { return }
            withTransaction(Transaction(animation: nil)) {
                proxy.scrollTo(selectedID)
            }
            Task { @MainActor in focused = selectedID }
        }

        private func focusRow(_ id: String, proxy: ScrollViewProxy) {
            // A previous sidebar focus value can remain set while UIKit's
            // actual focus is on the content pane. Writing the same value
            // again is a no-op, letting the focus engine jump to another row.
            // Clear it first and request the chosen row in the next turn.
            // Avoid scrollTo: horizontal entries should not move the rail.
            focused = nil
            Task { @MainActor in
                await Task.yield()
                guard crossPaneFocusID == id,
                      requestedFocusID == id,
                      itemIDs.contains(id) else { return }
                focused = id
            }
        }

        private var rows: some View {
            ForEach(items) { item in
                if let header = item.header {
                    TVRailGroupHeader(title: header)
                }
                railButton(item)
            }
        }

        private func railButton(_ item: TVSidebarRailItem) -> some View {
            let isSelected = selectedID == item.id
            // The selected row is exempt: when entry lands there directly, it
            // should read as focused from the first frame.
            let suppressed = masksFocus || (!preserveGeometricEntry && !railOwnsFocus && !isSelected)
            let isItemFocused = (focused == item.id && !suppressed)
                || (handOffPending && isSelected && focused != nil)
            let rowShape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            return Button(action: item.action) {
                // The reference uses leading monochrome symbols on each
                // category, aligned with the label and without a focus plate.
                HStack(spacing: 16) {
                    if item.icon != nil || item.badgeURL != nil {
                        // Keep icon space inside the button, but draw the
                        // actual art in an overlay AFTER the focusable button.
                        Color.clear.frame(width: 32, height: 32)
                    }
                    TVSidebarMarqueeTitle(
                        title: item.title,
                        isHighlighted: isItemFocused || isSelected,
                        font: .system(
                            size: 22,
                            weight: isSelected || isItemFocused ? .semibold : .medium
                        )
                    )
                    .frame(maxWidth: .infinity)
                }
                .foregroundStyle(textColor(isFocused: isItemFocused, isSelected: isSelected))
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                .padding(.horizontal, rowInset)
                .contentShape(rowShape)
                // Disable focus plating at the label as well as its Button.
                .focusEffectDisabled()
                .background {
                    rowShape.fill(
                        isItemFocused ? TVNeonTheme.selection :
                            LinearGradient(colors: [rowFill(isFocused: false, isSelected: isSelected),
                                                    rowFill(isFocused: false, isSelected: isSelected)],
                                           startPoint: .top, endPoint: .bottom)
                    )
                }
                .overlay(rowShape.strokeBorder(rowBorder(isFocused: isItemFocused, isSelected: isSelected),
                                               lineWidth: isItemFocused ? 2.4 : 1))
                .shadow(color: isItemFocused ? TVNeonTheme.electricBlue.opacity(0.7) : .clear,
                        radius: isItemFocused ? 14 : 0)
            }
            // Borderless removes the tvOS white focus platter; the row's
            // blue fill and cyan stroke above are the only focus artwork.
            .buttonStyle(.borderless)
            .focusEffectDisabled()
            .focused($focused, equals: item.id)
            .onMoveCommand { direction in
                if direction == .right { onMoveRight(item.id) }
            }
            .onGeometryChange(for: CGFloat.self) {
                $0.frame(in: .global).midY
            } action: { y in
                onRowCenterChange(item.id, y)
            }
            .overlay(alignment: .leading) {
                if item.badgeURL != nil || item.icon != nil {
                    TVFixedFocusIcon(
                        url: item.badgeURL,
                        systemName: item.icon ?? "sportscourt",
                        size: 32
                    )
                    .padding(.leading, rowInset)
                    .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.18), value: isItemFocused)
        }

        private func textColor(isFocused: Bool, isSelected: Bool) -> Color {
            if isFocused || isSelected { return .white }
            return .white.opacity(0.82)
        }

        private func rowFill(isFocused: Bool, isSelected: Bool) -> Color {
            let theme = DreamCASTAccentTheme.resolve(themeRaw)
            if isFocused { return theme.backgroundColors(light: false)[1] }
            if isSelected { return theme.backgroundColors(light: false)[1].opacity(0.9) }
            return .clear
        }

        private func rowBorder(isFocused: Bool, isSelected: Bool) -> Color {
            if isFocused { return TVNeonTheme.iceBlue }
            return isSelected ? TVNeonTheme.electricBlue.opacity(0.55) : .clear
        }
    }
#endif
