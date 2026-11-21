#if os(tvOS)
import SwiftData
import SwiftUI

struct TVCatalogShowcase<Library: View>: View {
    let isSeries: Bool
    let scope: CatalogScope
    let genres: [String]
    let open: (HomeMediaItem) -> Void
    let openGenre: (String) -> Void
    @ViewBuilder let library: () -> Library

    @Environment(\.modelContext) private var context
    @Environment(\.contentRestriction) private var restriction
    @Environment(SportsZonePlaybackSession.self) private var playback: SportsZonePlaybackSession?
    @Query private var playlists: [Playlist]
    @State private var section = "home"
    @State private var expandedGenres = false
    @State private var feedDetails: [Int: TrendingTitle] = [:]
    @State private var ranked: [HomeMediaItem] = []
    @State private var shelves: [Shelf] = []
    @State private var featured: HomeMediaItem?
    @State private var startingEpisode = false
    @State private var playError = false
    @FocusState private var focusedCard: String?

    private struct Shelf: Identifiable {
        let id: String
        let title: String
        let items: [HomeMediaItem]
    }

    var body: some View {
        HStack(alignment: .top, spacing: TVSidebarRail.paneSpacing) {
            TVSidebarRail(items: sidebar, selectedID: section)
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 28) {
                    if let featured {
                        hero(featured)
                    } else {
                        Text(isSeries ? "Series" : "Movies").font(.largeTitle.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if playback?.miniMedia != nil {
                        TVEmbeddedPlayerSlot()
                    }
                }
                .frame(height: playback?.miniMedia == nil ? 350 : TVEmbeddedPlayerSlot.totalHeight)
                .focusSection()
                if section == "library" {
                    library()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            ForEach(shelves) { shelf in
                                shelfView(shelf)
                            }
                            if shelves.isEmpty {
                                Text("No matching titles in this library").foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 35)
        .task(id: section) {
            loadShelves()
            guard section == "popular" || section == "home" || section == "trending",
                  TMDBClient.shared.isConfigured else { return }
            let feed: [TrendingTitle]?
            if section == "popular" {
                feed = try? await TMDBClient.shared.popularMovies()
            } else {
                feed = try? await TMDBClient.shared.trending(isSeries ? .tvShow : .movie)
            }
            guard !Task.isCancelled else { return }
            let titles = feed ?? []
            feedDetails = Dictionary(titles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let matches = match(titles)
            if section == "popular" {
                setShelves([Shelf(id: "popular", title: "Popular", items: matches)])
            } else {
                ranked = matches
                loadShelves()
            }
        }
        .onChange(of: focusedCard) { _, key in
            guard let key else { return }
            for shelf in shelves {
                if let item = shelf.items.first(where: { shelf.id + $0.id == key }) {
                    featured = item
                    return
                }
            }
        }
        .alert("Unable to play this title", isPresented: $playError) { Button("OK") {} }
    }

    private var sidebar: [TVSidebarRailItem] {
        let navigation = isSeries
            ? [("home","All Series","square.3.layers.3d"),("favorites","My Series","star"),
               ("resume","Continue Watching","play.circle"),("trending","Trending","flame"),
               ("releases","New Releases","calendar"),("future","Coming Soon","calendar.badge.clock")]
            : [("home","Featured","film"),("trending","Trending","flame"),("releases","New Releases","sparkles"),
               ("popular","Popular","square.grid.2x2"),("rated","Top Rated","star")]
        var rows = navigation.map { id, title, symbol in
            TVSidebarRailItem(id: id, title: Text(title), icon: symbol) { section = id }
        }
        let preferred = isSeries
            ? ["Drama", "Comedy", "Action & Adventure", "Crime", "Sci-Fi & Fantasy", "Romance"]
            : ["Action", "Adventure", "Animation", "Comedy", "Crime", "Drama", "Fantasy", "Horror", "Sci-Fi"]
        let first = preferred.compactMap { name in genres.first { $0.caseInsensitiveCompare(name) == .orderedSame } }
        let ordered = first + genres.filter { !first.contains($0) }
        let count = preferred.count
        for (index, genre) in ordered.prefix(expandedGenres ? ordered.count : count).enumerated() {
            rows.append(TVSidebarRailItem(id: "genre-" + genre, title: Text(genre), icon: "tag",
                                          header: index == 0 ? "GENRES" : nil) { openGenre(genre) })
        }
        if genres.count > count {
            rows.append(TVSidebarRailItem(id: "genres", title: Text(expandedGenres ? "Fewer Genres" : "More Genres"), icon: "ellipsis") {
                expandedGenres.toggle()
            })
        }
        rows.append(TVSidebarRailItem(id: "library", title: Text("Browse Library"), icon: "rectangle.stack") { section = "library" })
        return rows
    }

    private func hero(_ item: HomeMediaItem) -> some View {
        let info = metadata(item)
        return VStack(alignment: .leading, spacing: 10) {
            if !isSeries { Text("FEATURED").font(.caption.bold()).foregroundStyle(.cyan) }
            if case let .series(show) = item, let logo = TMDBClient.logoURL(show.logoPath) {
                CachedAsyncImage(url: logo, maxPixelSize: 420) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else {
                        Text(item.title).font(.title.bold())
                    }
                }.frame(maxWidth: 370, maxHeight: 76, alignment: .leading)
                .accessibilityLabel(item.title)
            } else {
                Text(item.title).font(.system(size: 46, weight: .heavy)).lineLimit(2)
            }
            if let episode = info.episode { Text(episodeLabel(episode)).font(.headline).lineLimit(1) }
            Text(info.details).font(.system(size: 22)).lineLimit(1)
            if !info.plot.isEmpty { Text(info.plot).font(.system(size: 23)).lineLimit(2) }
            HStack(spacing: 14) {
                Button(isSeries ? "▶ Play Episode" : "▶ Play") { Task { await play(item) } }
                    .disabled(startingEpisode)
                Button(isSeries ? "More Info" : "Info") { open(item) }
                Button(info.saved ? "✓ Watchlist" : "+ Watchlist") {
                    switch item {
                    case let .movie(movie): MediaFavorites.toggle(movie, in: context)
                    case let .series(show): MediaFavorites.toggle(show, in: context)
                    case .live: break
                    }
                    if section == "favorites" { loadShelves() }
                }
            }
            .font(.system(size: 21, weight: .semibold))
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            if !isSeries {
                GeometryReader { geometry in
                    ZStack {
                        AsyncImage(url: info.backdrop ?? item.imageURL) { image in image.resizable().scaledToFill() } placeholder: { Color.clear }
                        LinearGradient(colors: [.black.opacity(0.92), .black.opacity(0.35)], startPoint: .leading, endPoint: .trailing)
                    }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }
            }
        }
    }

    private func shelfView(_ shelf: Shelf) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(shelf.title).font(.title3.bold())
                Spacer()
                if section == "home" {
                    Button("See All ›") { section = shelf.id == "catalog" ? "library" : shelf.id }
                        .font(.system(size: 20)).buttonStyle(.plain)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(section == "home" ? Array(shelf.items.prefix(20)) : shelf.items) { item in
                        let wide = isSeries
                        let resume = shelf.id == "resume"
                        let episode = resume ? nextEpisode(item) : nil
                        let width: CGFloat = wide ? (resume ? 318 : 224) : 185
                        let height: CGFloat = wide ? (resume ? 178 : 138) : 242
                        Button { open(item) } label: {
                            ZStack(alignment: .bottomLeading) {
                                TVShowcaseArtwork(url: wide ? backdrop(item) ?? item.imageURL : item.imageURL,
                                                  width: width, height: height)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title).font(.system(size: 18, weight: .bold)).lineLimit(2)
                                    if let episode {
                                        Text(episodeLabel(episode)).font(.system(size: 15)).lineLimit(1)
                                        ProgressView(value: min(1, max(0, episode.watchProgress / Double(max(1, episode.durationSecs ?? 1)))))
                                            .tint(.cyan)
                                    }
                                }.padding(9).frame(width: width, alignment: .leading)
                                .background(LinearGradient(colors: [.clear,.black.opacity(0.92)], startPoint: .top, endPoint: .bottom))
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 15))
                        }
                        .buttonStyle(TVShowcaseCardStyle())
                        .focused($focusedCard, equals: shelf.id + item.id)
                    }
                }.padding(8)
            }.scrollClipDisabled()
        }.focusSection()
    }

    private func loadShelves() {
        let trending = Shelf(id: "trending", title: isSeries ? "Trending Series" : "Trending Movies", items: ranked)
        switch section {
        case "home":
            let latest = Shelf(id: "added", title: "Recently Added", items: collection(.recentlyAdded))
            if isSeries {
                let resume = Shelf(id: "resume", title: "Continue Watching", items: unfinishedSeries())
                setShelves([resume, trending, latest])
            } else {
                setShelves([trending, latest])
            }
            if shelves.isEmpty { setShelves([Shelf(id: "catalog", title: isSeries ? "All Series" : "Movies", items: localTitles())]) }
        case "trending": setShelves([trending])
        case "popular", "library": setShelves([])
        case "favorites", "resume", "added":
            let kind: LibraryCollection.Kind = section == "favorites" ? .favorites : section == "resume" ? .recentlyWatched : .recentlyAdded
            let title = section == "favorites" ? "My Series" : section == "resume" ? "Continue Watching" : "Recently Added"
            let items = section == "resume" ? unfinishedSeries() : collection(kind)
            setShelves([Shelf(id: section, title: title, items: items)])
        default:
            let titles = ["rated":"Top Rated","future":"Coming Soon","releases":"New Releases","catalog":"Browse Library"]
            setShelves([Shelf(id: section, title: titles[section] ?? section, items: localTitles())])
        }
    }

    private func setShelves(_ rows: [Shelf]) {
        shelves = rows.filter { !$0.items.isEmpty }
        if focusedCard != nil, let featured, shelves.contains(where: { $0.items.contains(featured) }) { return }
        featured = shelves.first?.items.first
    }

    private func unfinishedSeries() -> [HomeMediaItem] {
        collection(.recentlyWatched).filter { item in
            guard case let .series(show) = item else { return false }
            return show.episodes.contains { !$0.isWatched }
        }
    }

    private func collection(_ kind: LibraryCollection.Kind) -> [HomeMediaItem] {
        if isSeries {
            let rows = (try? context.fetch(SeriesCollectionQuery.rowDescriptor(for: kind, scope: scope))) ?? []
            return rows.excludingRestricted(restriction).map(HomeMediaItem.series)
        }
        let rows = (try? context.fetch(MovieCollectionQuery.rowDescriptor(for: kind, scope: scope))) ?? []
        return rows.excludingRestricted(restriction).map(HomeMediaItem.movie)
    }

    private func localTitles() -> [HomeMediaItem] {
        let today = String(Date.now.ISO8601Format().prefix(10))
        if isSeries {
            let scoped = scope.seriesPredicate()
            var descriptor = FetchDescriptor<Series>(predicate: scoped, sortBy: [SortDescriptor(\.name)])
            if section == "future" {
                descriptor.predicate = #Predicate { scoped.evaluate($0) && ($0.releaseDate ?? "") > today }
                descriptor.sortBy = [SortDescriptor(\.releaseDate)]
            } else if section == "releases" {
                descriptor.predicate = #Predicate { scoped.evaluate($0) && ($0.releaseDate ?? "") > "" && ($0.releaseDate ?? "") <= today }
                descriptor.sortBy = [SortDescriptor(\.releaseDate, order: .reverse)]
            }
            descriptor.fetchLimit = 200
            return ((try? context.fetch(descriptor)) ?? []).excludingRestricted(restriction).map(HomeMediaItem.series)
        }
        let scoped = scope.moviePredicate()
        var descriptor = FetchDescriptor<Movie>(predicate: scoped, sortBy: [SortDescriptor(\.name)])
        if section == "releases" {
            descriptor.predicate = #Predicate { scoped.evaluate($0) && ($0.releaseDate ?? "") > "" && ($0.releaseDate ?? "") <= today }
            descriptor.sortBy = [SortDescriptor(\.releaseDate, order: .reverse)]
        } else if section == "rated" {
            descriptor.predicate = #Predicate { scoped.evaluate($0) && $0.rating > 0 }
            descriptor.sortBy = [SortDescriptor(\.rating, order: .reverse)]
        }
        descriptor.fetchLimit = 200
        return ((try? context.fetch(descriptor)) ?? []).excludingRestricted(restriction).map(HomeMediaItem.movie)
    }

    private func match(_ feed: [TrendingTitle]) -> [HomeMediaItem] {
        let ids = Set(feed.map(\.id))
        guard !ids.isEmpty else { return [] }
        var byID: [Int: HomeMediaItem] = [:]
        if isSeries {
            let rows = (try? context.fetch(FetchDescriptor<Series>(predicate: seriesTmdbIdPredicate(ids: ids)))) ?? []
            for prefix in scope.prefixes(for: .series) {
                for show in rows.excludingRestricted(restriction) where show.id.hasPrefix(prefix) {
                    if let id = show.tmdbId, byID[id] == nil { byID[id] = .series(show) }
                }
            }
        } else {
            let rows = (try? context.fetch(FetchDescriptor<Movie>(predicate: movieTmdbIdPredicate(ids: ids)))) ?? []
            for prefix in scope.prefixes(for: .movies) {
                for movie in rows.excludingRestricted(restriction) where movie.id.hasPrefix(prefix) {
                    if let id = movie.tmdbId, byID[id] == nil { byID[id] = .movie(movie) }
                }
            }
        }
        var seen = Set<Int>()
        return feed.filter { seen.insert($0.id).inserted }.compactMap { byID[$0.id] }
    }

    private func nextEpisode(_ item: HomeMediaItem) -> Episode? {
        guard case let .series(show) = item else { return nil }
        return SeriesEpisodeProgress.nextEpisode(in: show.episodes, fallback: nil)
    }

    private func episodeLabel(_ episode: Episode) -> String {
        "S\(episode.seasonNum) • E\(episode.episodeNum)   \(episode.title)"
    }

    private func backdrop(_ item: HomeMediaItem) -> URL? {
        switch item {
        case let .movie(movie): TMDBClient.backdropURL(movie.backdropPath ?? movie.tmdbId.flatMap { feedDetails[$0]?.backdropPath })
        case let .series(show): TMDBClient.backdropURL(show.backdropPath ?? show.tmdbId.flatMap { feedDetails[$0]?.backdropPath })
        case .live: nil
        }
    }

    private func metadata(_ item: HomeMediaItem) -> (plot: String, details: String, episode: Episode?, saved: Bool, backdrop: URL?) {
        switch item {
        case let .movie(movie):
            let runtime = movie.durationSecs.map { "\($0 / 3600)h \(($0 % 3600) / 60)m" }
            let facts = [movie.releaseDate.map { String($0.prefix(4)) }, movie.contentRating, movie.genre, runtime]
            return (movie.plot ?? movie.tmdbId.flatMap { feedDetails[$0]?.overview } ?? "", facts.compactMap { $0 }.joined(separator: "  •  "), nil, movie.isFavorite, backdrop(item))
        case let .series(show):
            let episodes = show.episodes
            var facts = [show.contentRating, show.genre, show.releaseDate.map { String($0.prefix(4)) }].compactMap { $0 }
            if !episodes.isEmpty {
                facts.append("\(Set(episodes.map(\.seasonNum)).count) Seasons")
                facts.append("\(episodes.count) Episodes")
            }
            let ep = nextEpisode(item)
            return (ep?.plot ?? show.plot ?? show.tmdbId.flatMap { feedDetails[$0]?.overview } ?? "", facts.joined(separator: "  •  "), ep, show.isFavorite, backdrop(item))
        case .live: return ("", "", nil, false, nil)
        }
    }

    private func play(_ item: HomeMediaItem) async {
        guard !startingEpisode else { return }
        startingEpisode = true
        defer { startingEpisode = false }
        var media: PlayableMedia?
        switch item {
        case let .movie(movie):
            if let playlist = playlists.owner(ofContentID: movie.id) {
                media = PlayableMedia.from(movie: movie, playlist: playlist)
            }
        case let .series(show):
            if let playlist = playlists.owner(ofContentID: show.id) {
                if show.episodes.isEmpty {
                    let manager = ContentSyncManager(modelContainer: context.container)
                    if let episodes = try? await manager.fetchEpisodes(seriesId: show.seriesId, seriesElementId: show.id, playlist: playlist) {
                        show.insertEpisodes(episodes, into: context)
                    }
                }
                if let episode = nextEpisode(item) { media = PlayableMedia.from(episode: episode, playlist: playlist) }
            }
        case .live: break
        }
        guard let media else { playError = true; return }
        if ExternalPlayback.open(media) { return }
        playback?.matchedChannels = []
        playback?.tune(media, previewMode: .small)
    }
}

struct TVShowcaseCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Card(configuration: configuration)
    }

    private struct Card: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(focused ? Color.cyan : .white.opacity(0.18), lineWidth: focused ? 4 : 1)
                }
                .shadow(color: focused ? .cyan.opacity(0.65) : .clear, radius: 6)
                .opacity(configuration.isPressed ? 0.82 : 1)
        }
    }
}

struct TVShowcaseArtwork: View {
    let url: URL?
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        CachedAsyncImage(url: url, maxPixelSize: width * 2) { phase in
            if let image = phase.image { image.resizable().scaledToFill() }
            else { Color.white.opacity(0.08).overlay { Image(systemName: "play.rectangle").foregroundStyle(.secondary) } }
        }
        .frame(width: width, height: height)
        .clipped()
    }
}
#endif
