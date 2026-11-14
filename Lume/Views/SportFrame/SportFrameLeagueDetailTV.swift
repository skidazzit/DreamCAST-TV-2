#if os(tvOS)
import SwiftData
import SwiftUI

/// Opened from a league heading without changing SportsZone's main tab focus.
struct SportFrameLeagueRoute: Identifiable {
    let leagueID: String?
    let leagueName: String
    let sport: String
    let badgeURL: URL?
    var id: String { "\(sport)|\(leagueID ?? leagueName)" }
}

struct SportFrameLeagueDetailTV: View {
    let league: SportFrameLeagueRoute
    let playback: SportsZonePlaybackSession

    @StateObject private var store = SportFrameLeagueDetailStore()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMatch: SportEvent?
    @State private var pendingMedia: PlayableMedia?
    @State private var openingHighlightsFor: String?
    @Environment(\.openURL) private var openURL

    private let background = Color(red: 0.025, green: 0.055, blue: 0.11)

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    header
                    fixtures
                    standings
                    highlights
                }
                .padding(.horizontal, 90)
                .padding(.vertical, 45)
            }
            .safeAreaInset(edge: .bottom) {
                if playback.miniMedia != nil {
                    SportsZoneMiniPlayer(session: playback)
                        .frame(maxWidth: 1100)
                        .padding(.horizontal, 90)
                        .padding(.bottom, 16)
                }
            }
        }
        .fullScreenCover(item: $selectedMatch, onDismiss: presentPendingMedia) { event in
            SportFrameMatchSheet(event: event, onPlay: queueChannelPlayback)
        }
        .fullScreenCover(item: Binding(
            get: { playback.fullScreenMedia },
            set: { playback.fullScreenMedia = $0 }
        ), onDismiss: {
            playback.returnedFromFullScreen()
        }) { media in
            FullScreenPlayerView(media: media, adopting: playback.handle)
        }
        .task(id: league.id) {
            await store.refresh(
                leagueID: league.leagueID, leagueName: league.leagueName,
                sport: league.sport
            )
        }
    }

    /// Uses the same PlayableMedia and full-screen engine as Live TV.
    /// Present when the match sheet finishes closing to avoid a double-start.
    private func queueChannelPlayback(_ channel: ResolvedChannel) {
        guard pendingMedia == nil,
              let media = SportsPlayback.media(for: channel, in: modelContext) else { return }
        if ExternalPlayback.open(media) {
            selectedMatch = nil
            return
        }
        pendingMedia = media
        selectedMatch = nil
    }

    private func presentPendingMedia() {
        guard let media = pendingMedia else { return }
        pendingMedia = nil
        playback.tune(media)
    }

    private var header: some View {
        HStack(spacing: 25) {
            AsyncImage(url: store.badgeURL ?? league.badgeURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Image(systemName: "sportscourt").foregroundStyle(.secondary)
            }
            .frame(width: 110, height: 110)
            VStack(alignment: .leading, spacing: 8) {
                Text(league.leagueName).font(.system(size: 49, weight: .bold))
                Text([league.sport, store.season].compactMap { $0 }.joined(separator: " • "))
                    .font(.title3).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Refresh") {
                Task {
                    await store.refresh(
                        leagueID: league.leagueID, leagueName: league.leagueName,
                        sport: league.sport
                    )
                }
            }
            .buttonStyle(.bordered)
            Button("Back") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(.bottom, 20)
        .focusSection()
    }

    private var fixtures: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Live & upcoming matches").font(.system(size: 38, weight: .bold))
                .focusable()
            if store.loadingMatches { ProgressView("Loading league matches…") }
            if let error = store.matchError {
                Text(error).foregroundStyle(.orange)
            }
            if !store.loadingMatches && store.liveUpcoming.isEmpty
                && store.espnMatches.isEmpty && store.matchError == nil {
                missing("No live or upcoming matches found for this league.")
            }
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 16) {
                ForEach(store.upcomingMatches) { match in
                    switch match {
                    case .sportsDB(let event):
                        Button { selectedMatch = event } label: {
                            sportsDBFixture(event)
                        }
                        .buttonStyle(.card)
                    case .espn(let event):
                        espnFixture(event)
                    }
                }
            }
            if !store.recentResults.isEmpty {
                Text("Recent results").font(.title2.bold()).foregroundStyle(.secondary)
                    .focusable()
                recentResultsTable
            }
        }
        .focusSection()
    }

    /// One focusable table row per result, ordered by kickoff.
    private var recentResultsTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                Text("Matchup").frame(maxWidth: .infinity, alignment: .leading)
                Text("Score").frame(width: 150)
                Text("Date & time").frame(width: 210, alignment: .leading)
            }
            .font(.headline).foregroundStyle(.secondary)
            .padding(.horizontal, 26).padding(.vertical, 18)

            ForEach(store.recentResults) { event in
                Button { openHighlights(for: event) } label: {
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            team(event.strHomeTeam ?? "Home", logo: event.homeBadge)
                            team(event.strAwayTeam ?? "Away", logo: event.awayBadge)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Group {
                            if let home = event.intHomeScore, let away = event.intAwayScore {
                                Text("\(home) – \(away)")
                            } else {
                                Text("Result")
                            }
                        }
                        .font(.title3.bold().monospacedDigit())
                        .frame(width: 150)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(event.startDate?.formatted(date: .abbreviated, time: .omitted)
                                 ?? event.dateEvent ?? "Date TBA")
                            if openingHighlightsFor == event.idEvent {
                                ProgressView().controlSize(.small).tint(.cyan)
                            } else {
                                Text(event.timeLabel).foregroundStyle(.secondary)
                            }
                        }
                        .font(.subheadline)
                        .frame(width: 210, alignment: .leading)
                    }
                    .padding(.horizontal, 26).padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.card)
                Divider().overlay(.white.opacity(0.10))
            }
        }
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .focusSection()
    }

    /// Results open the correct highlight video, not the live-channel picker.
    private func openHighlights(for event: SportEvent) {
        guard openingHighlightsFor == nil else { return }
        openingHighlightsFor = event.idEvent
        Task {
            let destination = await store.highlightDestination(for: event)
            openingHighlightsFor = nil
            openURL(destination)
        }
    }

    private func sportsDBFixture(_ event: SportEvent) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                team(event.strHomeTeam ?? "Home", logo: event.homeBadge)
                team(event.strAwayTeam ?? "Away", logo: event.awayBadge)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 8) {
                if let home = event.intHomeScore, let away = event.intAwayScore {
                    Text("\(home) – \(away)").font(.title3.bold())
                } else {
                    Text(event.timeLabel).font(.title3.bold())
                }
                Text(event.isLive ? "LIVE" : "TheSportsDB")
                    .font(.subheadline).foregroundStyle(event.isLive ? .green : .secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 125)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 15))
    }

    private func espnFixture(_ event: SportsZoneESPNMatch) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                team(event.home, logo: event.homeLogo)
                team(event.away, logo: event.awayLogo)
            }
            Spacer(minLength: 5)
            VStack(alignment: .trailing, spacing: 8) {
                if event.isLive || event.isFinal {
                    Text("\(event.homeScore ?? "-") – \(event.awayScore ?? "-")")
                        .font(.title3.bold())
                } else {
                    Text(event.start.formatted(date: .omitted, time: .shortened))
                        .font(.title3.bold())
                }
                Text(event.isLive ? "LIVE • ESPN" : "ESPN")
                    .font(.subheadline)
                    .foregroundStyle(event.isLive ? .green : .secondary)
                Text(event.start.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 125)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 15))
    }

    private func team(_ name: String, logo: URL?) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: logo) { image in image.resizable().scaledToFit() } placeholder: {
                Image(systemName: "shield").foregroundStyle(.secondary)
            }
            .frame(width: 37, height: 37)
            Text(name).font(.system(size: 23, weight: .medium)).lineLimit(2)
        }
    }

    private var standings: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("League standings").font(.system(size: 38, weight: .bold))
                    .focusable()
                Spacer()
                if !store.standings.isEmpty {
                    Text("Source: \(store.standingsSource)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if store.loadingStandings { ProgressView("Loading standings…") }
            if let error = store.tableError { Text(error).foregroundStyle(.orange) }
            if !store.loadingStandings && store.standings.isEmpty && store.tableError == nil {
                missing("No table available from TheSportsDB or ESPN for this league.")
            }
            ForEach(store.tableGroups) { group in
                VStack(alignment: .leading, spacing: 12) {
                    Text(group.name).font(.title3.bold())
                        .focusable()
                    tableHeader
                    ForEach(group.standings) { row in standing(row) }
                }
                .padding(24)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            }
            if !store.standings.isEmpty
                && store.standingsSource == "TheSportsDB" && !SportsDBAccess.hasPremiumKey {
                Text("The Free API may show only five table rows.")
                    .foregroundStyle(.secondary).font(.subheadline)
            }
        }
        .focusSection()
    }

    private var usesRecordColumns: Bool {
        store.standingsSource == "ESPN" &&
            ["Basketball", "Baseball", "American Football"].contains(league.sport)
    }

    private var tableHeader: some View {
        HStack(spacing: 14) {
            Text("#").frame(width: 45)
            Text("Team").frame(maxWidth: .infinity, alignment: .leading)
            Text("P").frame(width: 55)
            Text("W").frame(width: 55)
            Text("D").frame(width: 55)
            Text("L").frame(width: 55)
            Text(usesRecordColumns ? "PCT" : "GD").frame(width: 65)
            Text(usesRecordColumns ? "GB" : "Pts").frame(width: 70)
        }
        .font(.subheadline.bold()).foregroundStyle(.secondary)
    }

    private func standing(_ row: SportFrameLeagueStanding) -> some View {
        HStack(spacing: 14) {
            Text(row.intRank ?? "-").frame(width: 45)
            HStack(spacing: 12) {
                AsyncImage(url: row.badgeURL) { image in image.resizable().scaledToFit() } placeholder: {
                    Image(systemName: "shield").foregroundStyle(.secondary)
                }
                .frame(width: 32, height: 32)
                Text(row.strTeam).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.intPlayed ?? "-").frame(width: 55)
            Text(row.intWin ?? "-").frame(width: 55)
            Text(row.intDraw ?? "-").frame(width: 55)
            Text(row.intLoss ?? "-").frame(width: 55)
            Text(row.intGoalDifference ?? "-").frame(width: 65)
            Text(row.intPoints ?? "-").fontWeight(.bold).frame(width: 70)
        }
        .font(.system(size: 22))
        .padding(.vertical, 7)
        .focusable()
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
        }
    }

    private var highlights: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Recent match highlights").font(.system(size: 38, weight: .bold))
                .focusable()
            if store.loadingHighlights { ProgressView("Loading highlights…") }
            if let error = store.highlightError { Text(error).foregroundStyle(.orange) }
            if !store.loadingHighlights && store.highlights.isEmpty && store.highlightError == nil {
                missing("No recent highlights available from TheSportsDB.")
            }
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 15) {
                ForEach(store.highlights) { video in
                    Button { openURL(video.videoURL) } label: {
                        HStack(spacing: 16) {
                            AsyncImage(url: video.thumbnailURL) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Image(systemName: "play.rectangle")
                                    .resizable().scaledToFit().foregroundStyle(.secondary)
                            }
                            .frame(width: 130, height: 90).clipped()
                            VStack(alignment: .leading, spacing: 7) {
                                Text(video.title).font(.title3.bold()).lineLimit(2)
                                Text(video.dateLabel).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "play.circle.fill").foregroundStyle(.cyan)
                        }
                        .padding(14)
                    }
                    .buttonStyle(.card)
                }
            }
        }
        .focusSection()
    }

    private func missing(_ label: String) -> some View {
        Text(label).font(.title3).foregroundStyle(.secondary).padding(20)
            .focusable()
    }
}
#endif
