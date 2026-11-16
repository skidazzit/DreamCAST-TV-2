#if os(tvOS)
import SwiftData
import SwiftUI

/// Connection result for the currently selected TheSportsDB tier.
/// A stored key means Premium is configured, not that the key is valid.
private enum SportsZoneAPIConnectionStatus: Equatable {
    case unchecked
    case checking
    case connected
    case invalidKey
    case rateLimited
    case unavailable
    case unexpectedResponse

    var title: String {
        switch self {
        case .unchecked: "Not checked"
        case .checking: "Checking connection…"
        case .connected: "Connected"
        case .invalidKey: "Premium key rejected"
        case .rateLimited: "Rate limit reached"
        case .unavailable: "Connection failed"
        case .unexpectedResponse: "Unexpected API response"
        }
    }

    var detail: String {
        switch self {
        case .unchecked: "Test access to TheSportsDB."
        case .checking: "Contacting TheSportsDB…"
        case .connected: "The selected API returned valid sports data."
        case .invalidKey: "Check your key or remove it to switch to Free."
        case .rateLimited: "Too many requests. Try again shortly."
        case .unavailable: "Check your connection and try again."
        case .unexpectedResponse: "The server returned data we could not verify."
        }
    }

    var symbol: String {
        switch self {
        case .connected: "checkmark.circle.fill"
        case .checking: "arrow.clockwise"
        case .unchecked: "questionmark.circle"
        case .invalidKey, .rateLimited, .unexpectedResponse: "exclamationmark.triangle.fill"
        case .unavailable: "wifi.exclamationmark"
        }
    }

    var tint: Color {
        switch self {
        case .connected: .green
        case .checking, .unchecked: .secondary
        case .invalidKey, .rateLimited, .unexpectedResponse, .unavailable: .orange
        }
    }
}

/// DreamCAST's SportsFrame presentation, using Lume's own playback and EPG index.
struct SportFrameHome: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.contentRestriction) private var restriction
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var fixtures = FixtureStore()
    @StateObject private var catalog = SportFrameCatalog()
    @AppStorage("sportFrameFollowedSportsV2") private var followedValue = "Soccer|Basketball|American Football"
    @AppStorage("sportFrameSportOrderV2") private var orderValue = "Soccer|Basketball|American Football|Tennis|Motorsport|Ice Hockey|Cricket"
    @AppStorage("sportFrameLeagueSelectionsV2") private var leagueValue = "{}"
    @State private var page = 0
    @State private var dayOffset = 0
    @State private var hubWindow: SportsHubWindow = .now

    private enum SportsHubWindow: Hashable {
        case now, upcoming, yesterday
    }
    @State private var selectedSport = "All Sports"
    @State private var selectedLeague = "All Leagues"
    @State private var expandedLeagueSport: String?
    @State private var sportsFollowExpanded = false
    @State private var selectedEvent: SportEvent?
    @State private var openedLeague: SportFrameLeagueRoute?
    @State private var sportsPlayback = SportsZonePlaybackSession()
    @Environment(SportsZonePlaybackSession.self) private var sharedPlayback: SportsZonePlaybackSession?

    private var activePlayback: SportsZonePlaybackSession {
        sharedPlayback ?? sportsPlayback
    }
    @State private var pendingMedia: PlayableMedia?
    @State private var premiumKeyInput = ""
    @State private var keyMessage: String?
    @State private var apiConnectionStatus: SportsZoneAPIConnectionStatus = .unchecked
    @State private var apiLastChecked: Date?
    /// A new ID cancels the previous test when changing or checking the key.
    @State private var apiCheckID = 0
    @FocusState private var focusedControl: FocusControl?

    private enum FocusControl: Hashable {
        case tab(Int)
        case hubWindow(SportsHubWindow)
        case date
        case refresh
        case sport(String)
        case leagueMenu
        case fixture(String)
        case selectAll
        case selectNone
        case sportSetting(String)
    }

    private let accent = Color(red: 0.0, green: 0.8, blue: 0.94)
    private let fallbackSports = ["Soccer", "Basketball", "American Football", "Tennis", "Motorsport", "Ice Hockey", "Cricket", "Baseball", "Rugby", "Golf"]

    private var sportOrder: [String] {
        var seen = Set<String>()
        return (orderValue.split(separator: "|").map(String.init) + catalog.sports + fallbackSports)
            .filter { seen.insert($0).inserted }
    }

    private var followedSports: [String] {
        let saved = Set(followedValue.split(separator: "|").map(String.init))
        return sportOrder.filter { saved.contains($0) }
    }

    // Honor saved sports even if TheSportsDB has not loaded their catalog data.
    private var followedSportsForLeagueEditor: [String] {
        Array(Set(followedValue.split(separator: "|").map(String.init)))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var leagueSelections: [String: [String]] {
        guard let data = leagueValue.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: [String]].self, from: data)) ?? [:]
    }

    private func selectedLeagueNames(for sport: String, available: [SportsCatalogLeague]) -> Set<String> {
        if let saved = leagueSelections[sport] { return Set(saved) }
        return Set(available.map(\.strLeague))
    }

    private func saveLeagueChoices(_ names: Set<String>?, for sport: String) {
        var choices = leagueSelections
        if let names { choices[sport] = names.sorted() }
        else { choices.removeValue(forKey: sport) }
        guard let data = try? JSONEncoder().encode(choices),
              let value = String(data: data, encoding: .utf8) else { return }
        leagueValue = value
    }

    /// Parse each kickoff once per sort, instead of constructing a date
    /// formatter during every O(n log n) comparison in All Sports.
    private func sortedHubEvents(_ events: [SportEvent], newestFirst: Bool = false) -> [SportEvent] {
        let fallback = newestFirst ? Date.distantPast : Date.distantFuture
        let keyed = events.map { (event: $0, kickoff: $0.startDate ?? fallback) }
        return keyed.sorted { lhs, rhs in
            if lhs.kickoff != rhs.kickoff {
                return newestFirst ? lhs.kickoff > rhs.kickoff : lhs.kickoff < rhs.kickoff
            }
            return lhs.event.idEvent < rhs.event.idEvent
        }.map(\.event)
    }

    private var visibleEvents: [SportEvent] {
        // These values must be decoded/collected once, not for each event.
        // This matters when All Sports contains matches across many leagues.
        let selectedSports = Set(followedSports)
        let chosenLeagues = leagueSelections.mapValues { Set($0) }
        let allSports = selectedSport == "All Sports"
        let allLeagues = selectedLeague == "All Leagues"
        let matching = fixtures.events.filter { event in
            guard let sport = fixtures.eventSports[event.idEvent],
                  selectedSports.contains(sport) else { return false }
            guard allSports || selectedSport == sport else { return false }
            guard allLeagues || selectedLeague == event.league else { return false }
            return chosenLeagues[sport]?.contains(event.league) ?? true
        }
        return sortedHubEvents(matching)
    }

    private var visibleLeagues: [(String, [SportEvent])] {
        let grouped = Dictionary(grouping: visibleEvents, by: \.league)
        return grouped.keys.sorted { lhs, rhs in
            let left = grouped[lhs]?.first?.startDate ?? .distantFuture
            let right = grouped[rhs]?.first?.startDate ?? .distantFuture
            return left == right ? lhs < rhs : left < right
        }.map { ($0, grouped[$0] ?? []) }
    }

    private var availableLeagues: [String] {
        let sports = selectedSport == "All Sports" ? followedSports : [selectedSport]
        let names = sports.flatMap { sport -> [String] in
            // Explicit picks are shown even when a league has no match today.
            if let saved = leagueSelections[sport] { return saved }
            return fixtures.events.filter { fixtures.eventSports[$0.idEvent] == sport }.map(\.league)
        }
        return Array(Set(names)).sorted()
    }

    var body: some View {
        ZStack {
            // The app root paints a single continuous glow for all tabs.
            VStack(spacing: 0) {
                // A single player host remains mounted while the main page
                // and league pages exchange their scrollable content.
                // It occupies the same fixed, top position as the Live TV guide.
                // The tvOS app root hosts the same video on every tab.
                // Keep this local host only for standalone previews and iOS.
                if sharedPlayback == nil {
                    SportsZoneMiniPlayer(session: sportsPlayback)
                        .padding(.horizontal, 55)
                }

                if let openedLeague {
                    SportFrameLeagueDetailTV(
                        league: openedLeague,
                        playback: activePlayback,
                        onBack: { self.openedLeague = nil },
                        scores: fixtures
                    )
                } else if page == 0 {
                    // The mockup's stable two-column SportsZone hub. The
                    // player is owned by MainTabView and embedded in its hero.
                    sportsHubPage
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 26) {
                            header
                            if activePlayback.miniMedia != nil {
                                HStack {
                                    Spacer()
                                    TVEmbeddedPlayerSlot(width: 560, height: 315)
                                }
                            }
                            settingsPage
                        }
                        .padding(.horizontal, 55)
                        .padding(.vertical, 28)
                    }
                }
            }
        }
        // Match the Live TV guide's scene and handoff lifecycle. On a
        // non-adoptable engine, its cooldown prevents overlapping streams.
        // On an adopted KS/AV decoder, the video surface stays mounted.
        .guidePreviewSuspension(
            sportsPlayback.guidePreview,
            playingMedia: Binding(
                get: { sportsPlayback.fullScreenMedia },
                set: { sportsPlayback.fullScreenMedia = $0 }
            )
        )
        .fullScreenCover(item: $selectedEvent, onDismiss: presentPendingMedia) { event in
            SportFrameMatchSheet(event: event, onPlay: queueChannelPlayback)
        }
        .fullScreenCover(item: Binding(
            get: { sportsPlayback.fullScreenMedia },
            set: { sportsPlayback.fullScreenMedia = $0 }
        ), onDismiss: {
            sportsPlayback.returnedFromFullScreen()
        }) { media in
            FullScreenPlayerView(media: media, adopting: sportsPlayback.handle)
                .environment(sportsPlayback)
        }
        .task { await catalog.refresh() }
        .task(id: "\(dayOffset)|\(followedValue)|\(SportsDBAccess.apiKey)|\(page)|\(scenePhase == .active)") {
            guard page == 0, scenePhase == .active else { return }
            let selectedDay = Calendar.current.date(byAdding: .day, value: dayOffset, to: .now) ?? .now
            await fixtures.pollSportsZone(sports: followedSports, date: selectedDay)
        }
        .onChange(of: followedValue) { _, _ in
            if selectedSport != "All Sports" && !followedSports.contains(selectedSport) {
                selectedSport = "All Sports"
            }
            if selectedLeague != "All Leagues" && !availableLeagues.contains(selectedLeague) {
                selectedLeague = "All Leagues"
            }
        }
        .onChange(of: leagueValue) { _, _ in
            if selectedLeague != "All Leagues" && !availableLeagues.contains(selectedLeague) {
                selectedLeague = "All Leagues"
            }
        }
        .onChange(of: page) { _, newPage in
            focusedControl = newPage == 0 ? .hubWindow(hubWindow) : .tab(newPage)
        }
        .onExitCommand {
            NotificationCenter.default.post(name: .dreamCASTReturnToTopMenu, object: nil)
        }
        // tvOS handles directional moves through the focus sections below.
        // No programmatic Up/Down moves compete with the system focus engine.
    }

    // MARK: - SportsZone NFL-hub layout

    /// Use real followed sports, saved league picks and live fixtures. The
    /// mockup's NFL / NBA / NHL labels are shortcuts, not hardcoded data.
    private func hubSportTitle(_ sport: String) -> String {
        switch sport {
        case "American Football": "NFL"
        case "Basketball": "NBA"
        case "Baseball": "MLB"
        case "Ice Hockey": "NHL"
        case "Mixed Martial Arts": "UFC"
        case "Motorsport": "Motorsports"
        default: sport
        }
    }

    private func hubSportSymbol(_ sport: String) -> String {
        switch sport {
        case "American Football": "sportscourt"
        case "Basketball": "basketball"
        case "Baseball": "baseball"
        case "Ice Hockey": "hockey.puck"
        case "Soccer": "soccerball"
        case "Tennis": "tennis.racket"
        case "Golf": "figure.golf"
        case "Motorsport": "flag.checkered"
        case "Boxing": "figure.boxing"
        case "Mixed Martial Arts": "figure.martial.arts"
        default: "sportscourt"
        }
    }

    /// A league shortcut only becomes a league filter when the catalog
    /// actually has that league and the viewer follows it.
    private func hubPreferredLeague(for sport: String) -> SportsCatalogLeague? {
        let aliases: [String]
        switch sport {
        case "American Football": aliases = ["NFL", "National Football League"]
        case "Basketball": aliases = ["NBA", "National Basketball Association"]
        case "Baseball": aliases = ["MLB", "Major League Baseball"]
        case "Ice Hockey": aliases = ["NHL", "National Hockey League"]
        case "Mixed Martial Arts": aliases = ["UFC", "Ultimate Fighting"]
        default: aliases = []
        }
        guard !aliases.isEmpty else { return nil }
        return catalog.leagues(for: sport).first { league in
            let permitted = leagueSelections[sport]?.contains(league.strLeague) ?? true
            return permitted && aliases.contains {
                league.strLeague.localizedCaseInsensitiveContains($0)
            }
        }
    }

    private var hubRailItems: [TVSidebarRailItem] {
        // All Sports stays at the top, followed by the user's saved sports.
        var items: [TVSidebarRailItem] = [
            TVSidebarRailItem(
                id: "all", title: Text("All Sports"),
                icon: "square.grid.2x2",
                header: "★  My Sports"
            ) {
                page = 0
                selectedSport = "All Sports"
                selectedLeague = "All Leagues"
            }
        ]

        for sport in followedSports {
            let preferred = hubPreferredLeague(for: sport)
            let art = preferred.flatMap { league in
                [league.strBadge, league.strLogo]
                    .compactMap { $0 }
                    .first(where: { !$0.isEmpty })
                    .flatMap(URL.init(string:))
            }
            let id = "sport:" + sport
            items.append(TVSidebarRailItem(
                id: id, title: Text(hubSportTitle(sport)),
                icon: hubSportSymbol(sport), badgeURL: art
            ) {
                page = 0
                selectedSport = sport
                selectedLeague = preferred?.strLeague ?? "All Leagues"
            })
        }

        items.append(TVSidebarRailItem(
            id: "settings", title: Text("SportsZone Settings"), icon: "gearshape"
        ) {
            page = 1
        })
        return items
    }

    private var hubSelectedRailID: String {
        page == 1 ? "settings" :
            (selectedSport == "All Sports" ? "all" : "sport:" + selectedSport)
    }

    private var hubTitle: String {
        if selectedLeague != "All Leagues" { return selectedLeague }
        return selectedSport == "All Sports" ? "My Sports" : hubSportTitle(selectedSport)
    }

    /// Derived once per page evaluation. Separate properties previously
    /// filtered/sorted everything again for the list, hero and tab counts.
    private struct SportsHubSnapshot {
        let displayed: [SportEvent]
        let liveCount: Int
        let upcomingCount: Int
        var featured: SportEvent? { displayed.first }
    }

    private func makeSportsHubSnapshot() -> SportsHubSnapshot {
        let visible = visibleEvents
        let now = Date()
        let live = visible.filter { fixtures.isLive($0) }
        let laterToday = visible.filter { ($0.startDate ?? .distantPast) > now }
        let allowedSports = Set(followedSports)
        let choices = leagueSelections.mapValues { Set($0) }
        let tomorrow = fixtures.nextDayEvents.filter { event in
            guard let sport = fixtures.nextDaySports[event.idEvent],
                  allowedSports.contains(sport) else { return false }
            guard selectedSport == "All Sports" || selectedSport == sport else { return false }
            guard selectedLeague == "All Leagues" || selectedLeague == event.league else { return false }
            guard choices[sport]?.contains(event.league) ?? true else { return false }
            return (event.startDate ?? .distantPast) > now
        }
        let upcoming = sortedHubEvents(laterToday + tomorrow)
        let displayed: [SportEvent]
        switch hubWindow {
        case .now: displayed = live
        case .upcoming: displayed = upcoming
        case .yesterday: displayed = Array(visible.reversed())
        }
        return SportsHubSnapshot(
            displayed: displayed,
            liveCount: live.count,
            upcomingCount: upcoming.count
        )
    }

    private func hubLeagueBadge(for featured: SportEvent?) -> URL? {
        if let event = featured {
            return event.leagueBadge ?? catalog.badgeURL(
                for: event.league,
                sport: fixtures.eventSports[event.idEvent] ?? event.strSport ?? "",
                idLeague: event.idLeague
            )
        }
        guard selectedSport != "All Sports",
              let league = hubPreferredLeague(for: selectedSport) else { return nil }
        return [league.strBadge, league.strLogo]
            .compactMap { $0 }
            .first(where: { !$0.isEmpty })
            .flatMap(URL.init(string:))
    }

    private var sportsHubPage: some View {
        let snapshot = makeSportsHubSnapshot()
        return HStack(alignment: .top, spacing: TVSidebarRail.paneSpacing) {
            TVSidebarRail(items: hubRailItems, selectedID: hubSelectedRailID)
            VStack(alignment: .leading, spacing: 17) {
                sportsHubHero(featured: snapshot.featured)
                sportsHubFilterBar(
                    liveCount: snapshot.liveCount,
                    upcomingCount: snapshot.upcomingCount
                )

                if fixtures.loading {
                    ProgressView("Loading sports fixtures…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let error = fixtures.error {
                    Text(error).foregroundStyle(.orange).font(.system(size: 18))
                }

                ScrollView(.vertical) {
                    LazyVStack(spacing: 9) {
                        if snapshot.displayed.isEmpty && !fixtures.loading {
                            VStack(spacing: 13) {
                                Image(systemName: "sportscourt")
                                    .font(.system(size: 42))
                                Text(hubWindow == .now
                                     ? "No matches live right now"
                                     : hubWindow == .upcoming
                                       ? "No upcoming matches for these leagues"
                                       : "No results found for yesterday")
                                    .font(.system(size: 26, weight: .semibold))
                                Text("Choose another sport or time range, or refresh the schedule.")
                                    .font(.system(size: 18))
                            }
                            .foregroundStyle(.white.opacity(0.68))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 45)
                        }

                        ForEach(snapshot.displayed) { event in
                            SportsHubMatchRow(
                                event: event,
                                score: fixtures.score(for: event),
                                isLive: fixtures.isLive(event)
                            ) {
                                // Selection only: playback starts in the
                                // existing matched-channel picker.
                                selectedEvent = event
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 5)
                    .padding(.bottom, 78)
                }
                .scrollIndicators(.visible)
                .focusSection()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 35)
        .padding(.top, 14)
        .padding(.bottom, 18)
    }

    private func sportsHubHero(featured: SportEvent?) -> some View {
        HStack(alignment: .top, spacing: 23) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 16) {
                    hubBadge(hubLeagueBadge(for: featured), fallback: "shield", size: 58)
                    Text(hubTitle)
                        .font(.system(size: 40, weight: .bold))
                        .lineLimit(1)
                    Rectangle()
                        .fill(TVNeonTheme.iceBlue.opacity(0.7))
                        .frame(width: 2, height: 47)
                        .padding(.horizontal, 7)
                    Text(hubWindow == .now ? "Happening Now" :
                         (hubWindow == .upcoming ? "Coming Up" : "Yesterday"))
                        .font(.system(size: 27, weight: .bold))
                        .foregroundStyle(TVNeonTheme.iceBlue)
                        .lineLimit(1)
                }

                if let featured {
                    HStack(spacing: 12) {
                        if fixtures.isLive(featured) {
                            Label("LIVE", systemImage: "circle.fill")
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(Color.red.opacity(0.9), in: Capsule())
                        }
                        Text(activePlayback.miniMedia?.title ?? featured.league)
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(.white.opacity(0.83))
                            .lineLimit(1)
                    }

                    Text(featured.name)
                        .font(.system(size: 37, weight: .bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    HStack(spacing: 18) {
                        Text(featured.timeLabel)
                            .font(.system(size: 22))
                        if let home = fixtures.score(for: featured).home,
                           let away = fixtures.score(for: featured).away {
                            Text(home + " – " + away)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(TVNeonTheme.iceBlue)
                        }
                    }
                    .foregroundStyle(.white.opacity(0.78))
                } else {
                    Text(hubWindow == .now
                         ? "Live games will appear here"
                         : "Choose a match from the schedule")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white.opacity(0.78))
                    Text("Schedules and scores come from TheSportsDB.")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.56))
                }

                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    Text("League")
                        .font(.system(size: 17))
                        .foregroundStyle(.white.opacity(0.7))
                    Menu {
                        Button("All Leagues") { selectedLeague = "All Leagues" }
                        ForEach(availableLeagues, id: \.self) { league in
                            Button(league) { selectedLeague = league }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Text(Image(systemName: "chevron.down"))
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 23, height: 26)
                            Text(selectedLeague)
                        }
                            .lineLimit(1)
                    }
                    .buttonStyle(SportsZonePillStyle())
                    .focused($focusedControl, equals: .leagueMenu)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 305, alignment: .topLeading)

            Group {
                if activePlayback.miniMedia != nil {
                    TVEmbeddedPlayerSlot(width: 580, height: 326 + TVPersistentMiniPlayer.controlsHeight)
                } else {
                    VStack(spacing: 15) {
                        Image(systemName: "play.tv")
                            .font(.system(size: 52))
                        Text("Select a matched channel to watch")
                            .font(.system(size: 20, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.64))
                    .frame(width: 580, height: 326)
                    .background(TVNeonTheme.glass, in: RoundedRectangle(cornerRadius: 22))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22)
                            .strokeBorder(TVNeonTheme.iceBlue.opacity(0.42), lineWidth: 1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func sportsHubFilterBar(liveCount: Int, upcomingCount: Int) -> some View {
        HStack(spacing: 8) {
            sportsHubWindowButton(
                .now,
                title: "Happening Now (\(liveCount))",
                symbol: "dot.radiowaves.left.and.right"
            )
            sportsHubWindowButton(
                .upcoming, title: "Coming Up (\(upcomingCount))",
                symbol: "calendar"
            )
            sportsHubWindowButton(
                .yesterday, title: "Yesterday", symbol: "clock.arrow.circlepath"
            )

            Spacer(minLength: 12)
            Button {
                Task { await refresh() }
            } label: {
                TVFixedButtonLabel(title: "Refresh", systemName: "arrow.clockwise")
                    .font(.system(size: 19, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .focusEffectDisabled()
            .focused($focusedControl, equals: .refresh)
        }
        .focusSection()
    }

    private func sportsHubWindowButton(_ window: SportsHubWindow,
                                       title: String, symbol: String) -> some View {
        let selected = hubWindow == window
        let focused = focusedControl == .hubWindow(window)
        return Button {
            hubWindow = window
            dayOffset = window == .yesterday ? -1 : 0
        } label: {
            HStack(spacing: 12) {
                Text(Image(systemName: symbol)).font(.system(size: 24))
                Text(title).font(.system(size: 20, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 23)
            .frame(height: 58)
            .background {
                Capsule().fill(selected || focused ? TVNeonTheme.selection : TVNeonTheme.glass)
            }
            .overlay {
                Capsule().strokeBorder(
                    focused ? TVNeonTheme.iceBlue : .white.opacity(0.12),
                    lineWidth: focused ? 2 : 1
                )
            }
            .shadow(color: focused ? TVNeonTheme.electricBlue.opacity(0.5) : .clear,
                    radius: focused ? 10 : 0)
            .contentShape(Capsule())
            .focusEffectDisabled()
        }
        .buttonStyle(.borderless)
        .focusEffectDisabled()
        .focused($focusedControl, equals: .hubWindow(window))
    }

    private func sportsHubMatchRow(_ event: SportEvent) -> some View {
        let focused = focusedControl == .fixture(event.idEvent)
        let isLive = fixtures.isLive(event)
        return Button {
            // Only Select opens the saved match/channel picker.
            selectedEvent = event
        } label: {
            HStack(spacing: 18) {
                // Real logo images live outside the focused Button to
                // prevent tvOS from zooming just one team's badge.
                Color.clear.frame(width: 44, height: 44)
                Color.clear.frame(width: 44, height: 44)
                Text(event.name)
                    .font(.system(size: 22, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isLive {
                    Text("● LIVE")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(.red, in: Capsule())
                }

                Text(event.timeLabel)
                    .font(.system(size: 19))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(minWidth: 125, alignment: .trailing)
                if let home = fixtures.score(for: event).home,
                   let away = fixtures.score(for: event).away {
                    Text(home + " – " + away)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(TVNeonTheme.iceBlue)
                        .frame(width: 76)
                }
                Text(Image(systemName: "chevron.right"))
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(width: 24, height: 28)
            }
            .padding(.horizontal, 16)
            .frame(height: 75)
            .background {
                RoundedRectangle(cornerRadius: 18)
                    .fill(focused ? TVNeonTheme.selection : TVNeonTheme.glass)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(focused ? TVNeonTheme.iceBlue :
                                  .white.opacity(0.14), lineWidth: focused ? 2.5 : 1)
            }
            .shadow(color: focused ? TVNeonTheme.electricBlue.opacity(0.65) : .clear,
                    radius: focused ? 12 : 0)
            .contentShape(RoundedRectangle(cornerRadius: 18))
            .focusEffectDisabled()
        }
        .buttonStyle(.borderless)
        .focusEffectDisabled()
        .focused($focusedControl, equals: .fixture(event.idEvent))
        .overlay(alignment: .leading) {
            HStack(spacing: 18) {
                TVFixedFocusIcon(url: event.homeBadge, systemName: "shield", size: 44)
                TVFixedFocusIcon(url: event.awayBadge, systemName: "shield", size: 44)
            }
            .padding(.leading, 16)
            .allowsHitTesting(false)
        }
    }

    private func hubBadge(_ url: URL?, fallback: String, size: CGFloat) -> some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFit()
            } else {
                Image(systemName: fallback)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(width: size, height: size)
        .focusEffectDisabled()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 25) {
            HStack {
                Spacer()
                HStack(spacing: 24) {
                    pageButton("Sports", index: 0)
                    pageButton("Settings", index: 1)
                }
                Spacer()
            }
            .padding(.bottom, 10)
            .focusSection()

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("SportsZone").font(.system(size: 53, weight: .bold, design: .rounded))
                    Text("Happening now & coming up").font(.title3).foregroundStyle(.secondary)
                }
                Spacer()
                if page == 0 {
                    Picker("Day", selection: $dayOffset) {
                        Text("Yesterday").tag(-1)
                        Text("Today").tag(0)
                        Text("Tomorrow").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 650)
                    .focused($focusedControl, equals: .date)
                }
                Button { Task { await refresh() } } label: {
                    Text(Image(systemName: "arrow.clockwise"))
                        .font(.system(size: 24, weight: .semibold))
                        .frame(width: 32, height: 34)
                }
                    .accessibilityLabel("Refresh sports")
                    .buttonStyle(SportsZonePillStyle())
                    .focused($focusedControl, equals: .refresh)
            }
            .focusSection()
            if page == 0 {
                HStack(spacing: 20) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            sportButton("All Sports")
                            ForEach(followedSports, id: \.self) { sport in sportButton(sport) }
                        }
                    }
                    .scrollIndicators(.hidden)

                    Menu {
                        Button("All Leagues") { selectedLeague = "All Leagues" }
                        ForEach(availableLeagues, id: \.self) { league in
                            Button(league) { selectedLeague = league }
                        }
                    } label: {
                        HStack(spacing: 18) {
                            Text(selectedLeague)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                        }
                        .frame(maxWidth: 275)
                    }
                    .buttonStyle(SportsZonePillStyle())
                    .focused($focusedControl, equals: .leagueMenu)
                }
                .focusSection()
            }
        }
    }

    private func pageButton(_ name: String, index: Int) -> some View {
        Button(name) { page = index }
            .buttonStyle(SportsZonePillStyle(isSelected: page == index))
            .focused($focusedControl, equals: .tab(index))
    }

    private func sportButton(_ sport: String) -> some View {
        let selected = selectedSport == sport
        return Button(sport) {
            selectedSport = sport
            selectedLeague = "All Leagues"
        }
        .buttonStyle(SportsZonePillStyle(isSelected: selected))
        .focused($focusedControl, equals: .sport(sport))
    }

    private var matchesPage: some View {
        VStack(alignment: .leading, spacing: 25) {
            if fixtures.loading { ProgressView("Loading matches…") }
            if let error = fixtures.error { Text(error).foregroundStyle(.orange) }
            if visibleEvents.isEmpty && !fixtures.loading {
                Text("No fixtures available. Choose more sports in Settings.")
                    .foregroundStyle(.secondary).padding(30)
            }

            // Two league tables per row, each anchored to the top of its grid cell.
            LazyVGrid(columns: [.init(.flexible(), alignment: .top), .init(.flexible(), alignment: .top)],
                      alignment: .leading, spacing: 24) {
                ForEach(visibleLeagues, id: \.0) { league, events in
                    VStack(alignment: .leading, spacing: 12) {
                        let first = events[0]
                        let sport = fixtures.eventSports[first.idEvent] ?? first.strSport ?? ""
                        let leagueID = first.idLeague ?? catalog.leagueID(for: league, sport: sport)
                        let logoURL = first.leagueBadge ?? catalog.badgeURL(
                            for: league, sport: sport, idLeague: leagueID
                        )
                        Button {
                            openedLeague = SportFrameLeagueRoute(
                                leagueID: leagueID, leagueName: league,
                                sport: sport, badgeURL: logoURL
                            )
                        } label: {
                            HStack(spacing: 17) {
                                AsyncImage(url: logoURL) { image in
                                    image.resizable().scaledToFit()
                                } placeholder: {
                                    Image(systemName: "shield.lefthalf.filled")
                                }
                                .frame(width: 62, height: 62)
                                Text(league).font(.system(size: 30, weight: .bold)).lineLimit(1)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.title3)
                            }
                            .padding(.horizontal, 22)
                            .frame(height: 92)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                LinearGradient(
                                    colors: [accent.opacity(0.67), .blue.opacity(0.16)],
                                    startPoint: .leading, endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 18)
                            )
                        }
                        .buttonStyle(TVCardButtonStyle(focusScale: 1.02))
                        .accessibilityLabel("Open \(league) league page")
                        .task(id: leagueID ?? league) {
                            if first.leagueBadge == nil {
                                await catalog.loadBadge(for: league, sport: sport, idLeague: leagueID)
                            }
                        }

                        ForEach(events) { event in
                            Button { selectedEvent = event } label: {
                                SportFrameFixtureCard(
                                    event: event,
                                    score: fixtures.score(for: event),
                                    isLive: fixtures.isLive(event)
                                )
                            }
                                .buttonStyle(TVCardButtonStyle(focusScale: 1.03))
                                .focused($focusedControl, equals: .fixture(event.idEvent))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .focusSection()
        }
    }

    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            sportsDBAPISettings
            Divider()

            Button {
                sportsFollowExpanded.toggle()
                // When collapsing, remove focus from any child now hidden.
                if !sportsFollowExpanded { focusedControl = nil }
            } label: {
                HStack(spacing: 18) {
                    Text("Which sports you follow").font(.largeTitle.bold())
                    Spacer()
                    Text("\(followedSports.count) selected")
                        .font(.title3).foregroundStyle(.secondary)
                    Text(Image(systemName: sportsFollowExpanded ? "chevron.up" : "chevron.down"))
                        .font(.title2)
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(SportsZonePillStyle())
            .focusSection()

            if sportsFollowExpanded {
                HStack {
                    Button("Select All") { followedValue = sportOrder.joined(separator: "|") }
                        .buttonStyle(SportsZonePillStyle())
                        .focused($focusedControl, equals: .selectAll)
                    Button("Select None") { followedValue = "" }
                        .buttonStyle(SportsZonePillStyle())
                        .focused($focusedControl, equals: .selectNone)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .focusSection()
                LazyVGrid(columns: [.init(.flexible()), .init(.flexible()), .init(.flexible())], spacing: 12) {
                    ForEach(sportOrder, id: \.self) { sport in
                        let selected = followedSports.contains(sport)
                        Button {
                            var saved = Set(followedValue.split(separator: "|").map(String.init))
                            if selected { saved.remove(sport) } else { saved.insert(sport) }
                            followedValue = sportOrder.filter { saved.contains($0) }.joined(separator: "|")
                        } label: {
                            HStack(spacing: 9) {
                                Text(Image(systemName: selected ? "checkmark.circle.fill" : "circle"))
                                    .font(.system(size: 20))
                                    .frame(width: 26, height: 27)
                                Text(sport)
                            }
                                .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        }
                        .buttonStyle(SportsZonePillStyle())
                        .focused($focusedControl, equals: .sportSetting(sport))
                    }
                }
                .focusSection()
            }
            Text("Which leagues you follow").font(.largeTitle.bold()).padding(.top, 22)
            Text("Choose a sport to pick its leagues. All leagues are followed until you change them.")
                .foregroundStyle(.secondary)
            if let message = catalog.message {
                Text(message).foregroundStyle(.orange)
            }
            ForEach(followedSportsForLeagueEditor, id: \.self) { sport in
                let leagues = catalog.leagues(for: sport)
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        expandedLeagueSport = expandedLeagueSport == sport ? nil : sport
                    } label: {
                        HStack(spacing: 16) {
                            Text(sport).font(.title2.bold())
                            Spacer()
                            let selectedCount = selectedLeagueNames(for: sport, available: leagues).count
                            Text(leagues.isEmpty ? "No leagues found" : "\(selectedCount) of \(leagues.count) leagues")
                                .foregroundStyle(.secondary)
                            Text(Image(systemName: expandedLeagueSport == sport ? "chevron.up" : "chevron.down"))
                        }
                        .padding(14)
                    }
                    .buttonStyle(SportsZonePillStyle())

                    if expandedLeagueSport == sport {
                        if leagues.isEmpty {
                            Text("No leagues are listed for this sport yet.").foregroundStyle(.secondary)
                        } else {
                            HStack {
                                Button("Select All") { saveLeagueChoices(nil, for: sport) }
                                    .buttonStyle(SportsZonePillStyle())
                                Button("Select None") { saveLeagueChoices([], for: sport) }
                                    .buttonStyle(SportsZonePillStyle())
                            }
                            LazyVGrid(columns: [.init(.flexible()), .init(.flexible()), .init(.flexible())], spacing: 10) {
                                ForEach(leagues) { league in
                                    let selected = selectedLeagueNames(for: sport, available: leagues)
                                        .contains(league.strLeague)
                                    Button {
                                        var names = selectedLeagueNames(for: sport, available: leagues)
                                        if selected { names.remove(league.strLeague) }
                                        else { names.insert(league.strLeague) }
                                        saveLeagueChoices(names.count == leagues.count ? nil : names, for: sport)
                                    } label: {
                                        Label(league.strLeague,
                                              systemImage: selected ? "checkmark.circle.fill" : "circle")
                                            .lineLimit(2)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(8)
                                    }
                                    .buttonStyle(SportsZonePillStyle())
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// First section of the tvOS SportsZone settings page. It tests the
    /// selected tier rather than treating a saved key as proof of access.
    private var sportsDBAPISettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 20) {
                Label("TheSportsDB API", systemImage: "network")
                    .font(.largeTitle.bold())
                Spacer()
                Text(SportsDBAccess.hasPremiumKey ? "Premium" : "Free")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(accent.opacity(0.18), in: Capsule())
            }

            HStack(alignment: .center, spacing: 16) {
                Image(systemName: apiConnectionStatus.symbol)
                    .font(.title2)
                    .foregroundStyle(apiConnectionStatus.tint)
                VStack(alignment: .leading, spacing: 6) {
                    Text(apiConnectionStatus.title)
                        .font(.title3.weight(.semibold))
                    Text(apiConnectionStatus.detail)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if apiConnectionStatus == .checking { ProgressView() }
            }

            if let apiLastChecked {
                Text("Last checked: \(apiLastChecked.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(SportsDBAccess.hasPremiumKey
                 ? "A Premium key is saved. The status above checks whether v2 access works."
                 : "Using the public Free API. Save a Premium key to test v2 access.")
                .foregroundStyle(.secondary)

            SecureField("Premium API key", text: $premiumKeyInput)
                .textContentType(.password)

            HStack(spacing: 16) {
                Button("Save Key") {
                    if SportsDBAccess.save(premiumKeyInput) {
                        premiumKeyInput = ""
                        keyMessage = "Premium key saved."
                        apiCheckID += 1
                    } else {
                        keyMessage = "Enter a valid Premium API key."
                    }
                }
                Button("Remove Key") {
                    SportsDBAccess.remove()
                    premiumKeyInput = ""
                    keyMessage = "Premium key removed. Using Free API."
                    apiCheckID += 1
                }
                Button("Test Connection") {
                    apiCheckID += 1
                }
                .disabled(apiConnectionStatus == .checking)
            }
            .buttonStyle(SportsZonePillStyle())
            .focusSection()

            if let keyMessage {
                Text(keyMessage).foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
        // The panel is mounted only on the Settings page. Re-test on entry,
        // and after Save, Remove, or an explicit Test Connection action.
        .task(id: apiCheckID) {
            await checkSportsDBConnection()
        }
    }

    @MainActor
    private func checkSportsDBConnection() async {
        apiConnectionStatus = .checking
        apiLastChecked = nil

        // The public v1 API uses key 123. Premium v2 requires a private key
        // in the X-API-KEY header. Never show or log the saved key.
        let isPremium = SportsDBAccess.hasPremiumKey
        let endpoint = isPremium
            ? "https://www.thesportsdb.com/api/v2/json/all/sports"
            : "https://www.thesportsdb.com/api/v1/json/123/all_sports.php"
        guard let url = URL(string: endpoint) else {
            apiConnectionStatus = .unavailable
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if isPremium {
            request.setValue(SportsDBAccess.apiKey, forHTTPHeaderField: "X-API-KEY")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled else { return }
            guard let response = response as? HTTPURLResponse else {
                apiConnectionStatus = .unexpectedResponse
                apiLastChecked = .now
                return
            }

            switch response.statusCode {
            case 200:
                let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                // Reject error messages and empty payloads even if the server
                // replied 200. Both tiers return a list of sports.
                let hasSports = payload?.values.contains {
                    ($0 as? [[String: Any]])?.isEmpty == false
                } == true
                apiConnectionStatus = hasSports ? .connected : .unexpectedResponse
            case 401, 403:
                apiConnectionStatus = isPremium ? .invalidKey : .unavailable
            case 429:
                apiConnectionStatus = .rateLimited
            default:
                apiConnectionStatus = .unavailable
            }
            apiLastChecked = .now
        } catch {
            guard !Task.isCancelled else { return }
            apiConnectionStatus = .unavailable
            apiLastChecked = .now
        }
    }

    /// Live TV and SportsZone both resolve channels through PlayableMedia.
    /// Wait for the match sheet's real dismissal rather than a fixed timer:
    /// presenting during dismissal can start the same stream twice.
    private func queueChannelPlayback(_ channel: ResolvedChannel, matches: [ResolvedChannel]) {
        guard pendingMedia == nil,
              let media = SportsPlayback.media(for: channel, in: modelContext) else { return }
        if ExternalPlayback.open(media) {
            selectedEvent = nil
            return
        }
        activePlayback.rememberMatches(matches, selected: channel)
        pendingMedia = media
        selectedEvent = nil
    }

    private func presentPendingMedia() {
        guard let media = pendingMedia else { return }
        pendingMedia = nil
        #if os(tvOS)
        activePlayback.tune(media, previewMode: .small)
        #else
        activePlayback.tune(
            media,
            previewMode: GuidePreviewMode(storedValue:
                UserDefaults.standard.string(forKey: PlayerSettings.tvGuidePreviewModeKey))
        )
        #endif
    }

    private func refresh() async {
        let selectedDay = Calendar.current.date(byAdding: .day, value: dayOffset, to: .now) ?? .now
        await fixtures.fetch(sports: followedSports, date: selectedDay)
    }
}

/// Match the app's neon blue focus styling without the old white plate.
private struct SportsZonePillStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        FocusedPill(configuration: configuration, isSelected: isSelected)
    }

    private struct FocusedPill: View {
        let configuration: ButtonStyleConfiguration
        let isSelected: Bool
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background {
                    Capsule().fill(
                        isFocused || isSelected
                            ? TVNeonTheme.electricBlue
                            : Color.white.opacity(0.10)
                    )
                }
                .overlay {
                    Capsule().strokeBorder(
                        isFocused ? TVNeonTheme.iceBlue : .clear,
                        lineWidth: isFocused ? 2 : 0
                    )
                }
                .shadow(color: isFocused ? TVNeonTheme.electricBlue.opacity(0.45) : .clear,
                        radius: isFocused ? 10 : 0)
                .animation(.easeOut(duration: 0.16), value: isFocused)
                .contentShape(Capsule())
                .focusEffectDisabled()
        }
    }
}

private struct SportFrameFixtureCard: View {
    let event: SportEvent
    let score: SportFrameScore
    let isLive: Bool
    @Environment(\.isFocused) private var focused
    private let accent = Color(red: 0.0, green: 0.8, blue: 0.94)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 15) {
                VStack(alignment: .leading, spacing: 16) {
                    team(event.strHomeTeam ?? "Home", badge: event.homeBadge)
                    team(event.strAwayTeam ?? "Away", badge: event.awayBadge)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 9) {
                    if score.home != nil && score.away != nil {
                        Text(scoreText).font(.system(size: 29, weight: .bold))
                    } else {
                        Text(event.timeLabel).font(.system(size: 23, weight: .bold))
                    }
                    Text(isLive ? "LIVE" : (score.status ?? "Scheduled"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isLive ? .green : .secondary)
                    if score.home != nil && score.away != nil {
                        Text(event.timeLabel).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 115, alignment: .trailing)
            }
            Divider().overlay(.white.opacity(0.15))
            SportFrameFixtureBroadcasters(eventID: event.idEvent)
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 205, alignment: .topLeading)
        .background(.white.opacity(focused ? 0.17 : 0.07), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(focused ? accent : .clear, lineWidth: 3))
    }

    private var scoreText: String {
        if let home = score.home, let away = score.away { return "\(home) : \(away)" }
        return "vs"
    }

    private func team(_ name: String, badge: URL?) -> some View {
        HStack(spacing: 13) {
            AsyncImage(url: badge) { image in image.resizable().scaledToFit() }
                placeholder: { Image(systemName: "shield").resizable().scaledToFit().foregroundStyle(.secondary) }
                .frame(width: 47, height: 47)
            Text(name).font(.system(size: 21, weight: .semibold)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SportFrameBroadcaster: Decodable, Identifiable {
    let id: String?
    let strChannel: String?
    let strLogo: String?
    var name: String { strChannel ?? "TV Channel" }
    var logoURL: URL? { strLogo.flatMap(URL.init(string:)) }
    var stableID: String { id ?? name }
}

private struct SportFrameBroadcastResponse: Decodable { let tvevent: [SportFrameBroadcaster]? }

@MainActor
private enum SportFrameBroadcasts {
    static func fetch(eventID: String) async -> [SportFrameBroadcaster] {
        guard let url = URL(string: "https://www.thesportsdb.com/api/v1/json/\(SportsDBAccess.apiKey)/lookuptv.php?id=\(eventID)") else { return [] }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            let records = try JSONDecoder().decode(SportFrameBroadcastResponse.self, from: data).tvevent ?? []
            var seen = Set<String>()
            return records.filter { seen.insert(ChannelMatcher.normalize($0.name)).inserted }
        } catch { return [] }
    }
}

private struct SportFrameFixtureBroadcasters: View {
    let eventID: String
    @State private var listings: [SportFrameBroadcaster] = []
    @State private var loaded = false

    var body: some View {
        HStack(spacing: 12) {
            if !loaded { ProgressView().controlSize(.small) }
            else if listings.isEmpty { Text("No broadcasters listed").foregroundStyle(.secondary) }
            ForEach(listings.prefix(3), id: \.stableID) { listing in
                HStack(spacing: 6) {
                    AsyncImage(url: listing.logoURL) { image in image.resizable().scaledToFit() }
                        placeholder: { Image(systemName: "tv") }
                        .frame(width: 35, height: 25)
                    Text(listing.name).font(.system(size: 15)).lineLimit(1)
                }
            }
            if listings.count > 3 { Text("+\(listings.count - 3)").foregroundStyle(.secondary) }
        }
        .task(id: eventID) {
            loaded = false
            listings = await SportFrameBroadcasts.fetch(eventID: eventID)
            loaded = true
        }
    }
}

/// Search the actual IPTV channel list, excluding unrelated sister networks.
/// Match only the selected network plus safe region/quality feed labels.
nonisolated private enum SportsZoneBroadcasterSearch {
    static func find(name: String, container: ModelContainer, restriction: ContentRestriction) async -> [ResolvedChannel] {
        guard let lookup = SportsZoneBroadcasterMatcher.Lookup(broadcaster: name) else { return [] }
        return await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let descriptor = SportsChannelResolver.candidateStreamDescriptor(restriction: restriction)
            let streams = (try? context.fetch(descriptor)) ?? []
            var results: [(channel: ResolvedChannel, match: SportsZoneBroadcasterMatcher.Match)] = []
            for stream in streams {
                if Task.isCancelled { return [ResolvedChannel]() }
                guard let match = lookup.match(channelName: stream.name),
                      let playlistID = UUID(uuidString: String(stream.id.prefix(36))) else { continue }
                results.append((
                    ResolvedChannel(
                        stream: ResolvedStreamSummary(id: stream.id, name: stream.name,
                                                      streamIcon: stream.streamIcon, epgChannelId: stream.epgChannelId),
                        playlistID: playlistID,
                        matchedTitle: nil,
                        matchedStart: nil,
                        score: match.score,
                        source: .channelName,
                        isConfident: false
                    ), match
                ))
            }
            return results.sorted {
                if $0.match.score != $1.match.score { return $0.match.score > $1.match.score }
                return $0.channel.stream.name.localizedStandardCompare($1.channel.stream.name) == .orderedAscending
            }.map(\.channel)
        }.value
    }
}

/// Broadcaster-first lookup from DreamCAST, with Lume's indexed EPG search below it.
struct SportFrameMatchSheet: View {
    let event: SportEvent
    let onPlay: (ResolvedChannel, [ResolvedChannel]) -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.contentRestriction) private var restriction
    @Environment(\.dismiss) private var dismiss
    @State private var broadcasters: [SportFrameBroadcaster] = []
    @State private var selectedBroadcaster: String?
    @State private var foundChannels: [ResolvedChannel] = []
    @State private var broadcasterChannels: [ResolvedChannel] = []
    @State private var searchingBroadcaster = false
    @State private var loading = true
    @FocusState private var focusedBroadcaster: String?
    @FocusState private var focusedChannel: String?

    private var broadcasterMatches: [ResolvedChannel] {
        broadcasterChannels
    }

    private var epgMatches: [ResolvedChannel] {
        let used = Set(broadcasterMatches.map(\.id))
        return foundChannels.filter { !used.contains($0.id) }
    }

    /// The IPTV guide results are available even before a broadcaster is
    /// chosen. Move focus only; a Select click still starts playback.
    private func focusFirstRightChannel() {
        guard let first = (broadcasterMatches + epgMatches).first else { return }
        focusedBroadcaster = nil
        focusedChannel = first.id
    }

    private func focusLeftBroadcaster() {
        guard let first = broadcasters.first else {
            // A fixture with no broadcaster list must not strand focus.
            focusFirstRightChannel()
            return
        }
        focusedChannel = nil
        focusedBroadcaster = first.name
    }

    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.055, blue: 0.11).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 25) {
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Match channels").font(.system(size: 29, weight: .semibold)).foregroundStyle(.secondary)
                        Text("\(event.strHomeTeam ?? "Home") vs \(event.strAwayTeam ?? "Away")")
                            .font(.system(size: 39, weight: .bold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 16)
                    Button("Back") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }

                HStack(alignment: .top, spacing: 32) {
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Broadcasters").font(.system(size: 28, weight: .bold))
                        Text("Choose a network to search your IPTV channels.")
                            .font(.system(size: 18)).foregroundStyle(.secondary)
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                if loading { ProgressView("Loading broadcasters…") }
                                else if broadcasters.isEmpty {
                                    Text("No broadcasters listed.").foregroundStyle(.secondary)
                                }
                                ForEach(broadcasters, id: \.stableID) { broadcaster in
                                    Button {
                                        selectedBroadcaster = broadcaster.name
                                    } label: {
                                        HStack(spacing: 15) {
                                            Color.clear.frame(width: 52, height: 36)
                                            Text(broadcaster.name).font(.system(size: 21)).lineLimit(2)
                                            Spacer(minLength: 0)
                                            if selectedBroadcaster == broadcaster.name {
                                                Text(Image(systemName: "checkmark.circle.fill"))
                                                    .foregroundStyle(TVNeonTheme.iceBlue)
                                            }
                                        }
                                        .padding(10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background {
                                            RoundedRectangle(cornerRadius: 14)
                                                .fill(focusedBroadcaster == broadcaster.name ||
                                                      selectedBroadcaster == broadcaster.name
                                                      ? TVNeonTheme.selection : TVNeonTheme.glass)
                                        }
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 14)
                                                .strokeBorder(focusedBroadcaster == broadcaster.name
                                                              ? TVNeonTheme.iceBlue : .clear,
                                                              lineWidth: 2)
                                        }
                                    }
                                    .buttonStyle(.borderless)
                                    .focusEffectDisabled()
                                    .focused($focusedBroadcaster, equals: broadcaster.name)
                                    .onMoveCommand { direction in
                                        // The left pane may have no chosen broadcaster.
                                        // Either horizontal direction can enter the
                                        // ready-to-play IPTV matches on the right.
                                        if direction == .right ||
                                            (direction == .left && selectedBroadcaster == nil) {
                                            focusFirstRightChannel()
                                        }
                                    }
                                    .overlay(alignment: .leading) {
                                        TVFixedFocusIcon(url: broadcaster.logoURL,
                                                         systemName: "tv", size: 36)
                                            .frame(width: 52, height: 36)
                                            .padding(.leading, 10)
                                            .allowsHitTesting(false)
                                    }
                                }
                            }
                        }
                    }
                    .frame(width: 440)
                    .focusSection()

                    VStack(alignment: .leading, spacing: 15) {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 15) {
                                if let selectedBroadcaster {
                                    Text("Channels matching \(selectedBroadcaster)")
                                        .font(.system(size: 27, weight: .bold)).lineLimit(2)
                                    if searchingBroadcaster { ProgressView("Searching IPTV channels…") }
                                    else if broadcasterMatches.isEmpty {
                                        Text("No matching network found. Check the other game matches below.").foregroundStyle(.secondary)
                                    }
                                    ForEach(broadcasterMatches) { channel in channelRow(channel) }
                                } else {
                                    Text("Select a broadcaster on the left")
                                        .font(.title3).foregroundStyle(.secondary)
                                }
                                Divider().padding(.vertical, 10)
                                Text("More matches from your IPTV guide")
                                    .font(.system(size: 27, weight: .bold)).lineLimit(2)
                                if epgMatches.isEmpty && !loading {
                                    Text("No other match-name results found.").foregroundStyle(.secondary)
                                }
                                ForEach(epgMatches) { channel in channelRow(channel) }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .focusSection()
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, 75)
            .padding(.vertical, 55)
        }
        .task(id: event.idEvent) {
            loading = true
            broadcasters = await SportFrameBroadcasts.fetch(eventID: event.idEvent)
            guard !Task.isCancelled else { return }
            let fixture = makeFixture()
            let matches = await SportsChannelResolver.resolve(
                container: modelContext.container, fixtures: [fixture], now: Date(), restriction: restriction
            )
            guard !Task.isCancelled else { return }
            foundChannels = matches[fixture.id] ?? []
            loading = false
        }
        .task(id: selectedBroadcaster) {
            broadcasterChannels = []
            guard let selectedBroadcaster else { return }
            searchingBroadcaster = true
            let channels = await SportsZoneBroadcasterSearch.find(
                name: selectedBroadcaster, container: modelContext.container, restriction: restriction
            )
            guard !Task.isCancelled else { return }
            broadcasterChannels = channels
            searchingBroadcaster = false
        }
    }

    private func channelRow(_ channel: ResolvedChannel) -> some View {
        let focused = focusedChannel == channel.id
        return Button { onPlay(channel, broadcasterMatches + epgMatches) } label: {
            HStack(spacing: 13) {
                Color.clear.frame(width: 60, height: 40)
                Text(channel.stream.name).font(.system(size: 21)).lineLimit(2)
                Spacer()
                Text(Image(systemName: "play.fill"))
                    .font(.system(size: 20))
                    .frame(width: 28, height: 30)
            }
            .padding(.horizontal, 13)
            .frame(minHeight: 62)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(focused ? TVNeonTheme.selection : TVNeonTheme.glass)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(focused ? TVNeonTheme.iceBlue : .white.opacity(0.1),
                                  lineWidth: focused ? 2 : 1)
            }
        }
        .buttonStyle(.borderless)
        .focusEffectDisabled()
        .focused($focusedChannel, equals: channel.id)
        .onMoveCommand { direction in
            if direction == .left {
                // Moving back toward Broadcasters must not require choosing
                // one first. If none exist, keep the right list accessible.
                focusLeftBroadcaster()
            }
        }
        .overlay(alignment: .leading) {
            TVFixedFocusIcon(url: channel.stream.streamIcon.flatMap(URL.init(string:)),
                             systemName: "play.tv", size: 40)
                .frame(width: 60, height: 40)
                .padding(.leading, 13)
                .allowsHitTesting(false)
        }
    }

    private func makeFixture() -> SportsFixture {
        let leagueID = "sportsdb:\(event.idLeague ?? "unknown")"
        func competitor(_ name: String?, badge: URL?, score: String?) -> SportsCompetitor? {
            guard let name else { return nil }
            let team = SportsTeam(leagueId: leagueID, teamId: ChannelMatcher.normalize(name),
                                  name: name, shortName: name, abbreviation: String(name.prefix(3)), logoURL: badge)
            return SportsCompetitor(team: team, score: score.flatMap(Int.init))
        }
        let state: SportsFixtureState = event.isLive ? .inProgress : .scheduled
        return SportsFixture(id: "sportsdb:\(event.idEvent)", leagueId: leagueID,
                             leagueName: event.league, leagueAbbreviation: event.league,
                             startDate: event.startDate ?? Date(),
                             status: SportsFixtureStatus(state: state, detail: event.strStatus ?? ""),
                             home: competitor(event.strHomeTeam, badge: event.homeBadge, score: event.intHomeScore),
                             away: competitor(event.strAwayTeam, badge: event.awayBadge, score: event.intAwayScore),
                             broadcasters: broadcasters.map(\.name), name: event.name)
    }
}
#endif
