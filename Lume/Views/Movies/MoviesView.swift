//
//  MoviesView.swift
//  Lume
//
//  Main view for browsing movies. Each category shows a preview row;
//  "Show All" navigates to the full category view.
//

import SwiftData
import SwiftUI

struct MoviesView: View {
    @Namespace private var animationNamespace
    @Environment(\.modelContext) private var modelContext
    @Environment(\.contentRestriction) private var restriction
    /// The playlists the categories, collection rows and genres read from: one
    /// playlist, or the Combined members.
    @Environment(\.catalogScope) private var scope
    // Optional so previews (which don't inject it) fall back to a local path.
    @Environment(DeepLinkRouter.self) private var router: DeepLinkRouter?
    @State private var fallbackPath = NavigationPath()
    @Query private var playlists: [Playlist]
    @Query(filter: #Predicate<Category> { $0.typeRaw == "vod" && $0.isHidden == false })
    private var categories: [Category]

    @AppStorage(PlaylistSelectionStore.key) private var selectedPlaylistID: String = ""
    @State private var showingSync = false
    @State private var showingSettings = false
    @State private var genres: [String] = []
    #if os(iOS)
    @State private var featuredMovie: Movie?
    @State private var featuredPlayback: PlayableMedia?
    @Environment(SportsZonePlaybackSession.self) private var sharedPlayback: SportsZonePlaybackSession?
    #endif

    @AppStorage(SortStorageKey.movieCategories) private var categorySortRaw: String = CategorySortOption.playlist.rawValue
    @AppStorage(SortStorageKey.movieContent) private var contentSortRaw: String = ContentSortOption.playlist.rawValue

    private var categorySort: CategorySortOption {
        CategorySortOption(rawValue: categorySortRaw) ?? .playlist
    }

    private var contentSort: ContentSortOption {
        ContentSortOption(rawValue: contentSortRaw) ?? .playlist
    }

    /// How many movies to render inline per category. The full list is reachable
    /// via the per-row "Show All" link.
    private let previewLimit = 20

    /// How many categories render as full inline preview rows. Each preview row
    /// carries its own live `@Query`, so capping them keeps the browse screen
    /// fast; the remaining categories surface as lightweight name tiles below.
    private let previewCategoryLimit = 4

    var body: some View {
        // Resolve once per render — `categoryLayout` filters + sorts every
        // member's categories, so reading it per use multiplied that work.
        let layout = categoryLayout
        NavigationStack(path: navigationPath) {
            Group {
                if playlists.isEmpty {
                    ContentUnavailableView(
                        "No Playlists",
                        systemImage: "film.stack",
                        description: Text("Add a playlist in Settings to start browsing movies")
                    )
                } else if layout.isEmpty {
                    VStack(spacing: 20) {
                        ContentUnavailableView(
                            "No Movies",
                            systemImage: "film.stack",
                            description: Text("Sync your playlist to load movies")
                        )
                    }
                } else {
                    ScrollViewReader { scroller in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 24, pinnedViews: []) {
                                #if os(iOS)
                                ScrollView(.horizontal) {
                                    HStack(spacing: 9) {
                                        DreamCASTMobileChip(title: "Continue", symbol: "play.circle") {
                                            withAnimation { scroller.scrollTo("recent", anchor: .top) }
                                        }
                                        DreamCASTMobileChip(title: "Favorites", symbol: "star") {
                                            withAnimation { scroller.scrollTo("favorites", anchor: .top) }
                                        }
                                        DreamCASTMobileChip(title: "New Releases", symbol: "sparkles") {
                                            withAnimation { scroller.scrollTo("new", anchor: .top) }
                                        }
                                        DreamCASTMobileChip(title: "Genres", symbol: "square.grid.2x2") {
                                            withAnimation { scroller.scrollTo("genres", anchor: .top) }
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                                .scrollIndicators(.hidden)
                                #endif
                                #if os(iOS)
                                if let featuredMovie {
                                    DreamCASTMobileFeaturedHero(
                                        title: featuredMovie.name,
                                        badge: "Featured Movie",
                                        artworkURL: TMDBClient.backdropURL(featuredMovie.backdropPath),
                                        fallbackURL: URL(string: featuredMovie.streamIcon ?? ""),
                                        genre: featuredMovie.genre,
                                        releaseDate: featuredMovie.releaseDate,
                                        contentRating: featuredMovie.contentRating,
                                        extraInfo: featuredMovie.durationSecs.map { seconds in
                                            let hours = seconds / 3600
                                            let minutes = (seconds % 3600) / 60
                                            return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
                                        },
                                        summary: featuredMovie.plot,
                                        isWatchlisted: featuredMovie.addedToWatchlistDate != nil,
                                        primaryTitle: "Play",
                                        onPrimary: { playFeatured(featuredMovie) },
                                        onInfo: { navigationPath.wrappedValue.append(featuredMovie) },
                                        onWatchlist: {
                                            featuredMovie.addedToWatchlistDate = featuredMovie.addedToWatchlistDate == nil ? .now : nil
                                            try? modelContext.save()
                                        }
                                    )
                                }
                                #endif
                            MovieCollectionRow(kind: .recentlyWatched, scope: scope, animationNamespace: animationNamespace)
                                .id("recent")
                            MovieCollectionRow(kind: .favorites, scope: scope, animationNamespace: animationNamespace)
                                .id("favorites")
                            MovieCollectionRow(kind: .recentlyAdded, scope: scope, animationNamespace: animationNamespace)
                                .id("new")

                            ForEach(layout.previews) { category in
                                MovieCategoryPreview(category: category, limit: previewLimit, sort: contentSort, animationNamespace: animationNamespace)
                                    .id("\(category.id)-\(contentSort.rawValue)")
                            }

                            if !genres.isEmpty {
                                GenreGridSection(genres: genres, type: .vod)
                                    .id("genres")
                            }

                            ForEach(layout.remaining) { group in
                                CategoryGridSection(group: group)
                                    .padding(.top, 12)
                            }
                        }
                            .padding(.vertical)
                        }
                    }
                    .browseActivity()
                    .task(id: scope.token) {
                        genres = await GenreDerivation.movieGenres(in: modelContext.container, scope: scope, restriction: restriction)
                    }
                    #if os(iOS)
                    .task(id: "\(scope.token)-\(categories.count)-\(playlists.map(\.syncStatusRaw).joined(separator: "|"))") {
                        loadFeaturedMovie()
                    }
                    #endif
                }
            }
            #if os(iOS)
            .background { DreamCASTThemeBackground() }
            #endif
            .platformNavigationTitle("Movies")
            .profileMenuToolbar()
            .libraryToolbar(config: LibraryToolbarConfiguration(
                playlists: playlists,
                selectedPlaylistID: $selectedPlaylistID,
                categorySortRaw: $categorySortRaw,
                contentSortRaw: $contentSortRaw,
                showingSync: $showingSync,
                showingSettings: $showingSettings
            ))
            .navigationDestination(for: Category.self) { category in
                MovieCategoryView(category: category, animationNamespace: animationNamespace)
            }
            .navigationDestination(for: LibraryCollection.self) { collection in
                MovieCollectionView(kind: collection.kind, scope: scope, animationNamespace: animationNamespace)
            }
            .navigationDestination(for: GenreSelection.self) { selection in
                MovieGenreView(genre: selection.genre, scope: scope, animationNamespace: animationNamespace)
            }
            .navigationDestination(for: Movie.self) { movie in
                MovieDetailView(movie: movie, animationNamespace: animationNamespace)
                #if os(iOS)
                    .navigationTransition(.zoom(sourceID: movie.id, in: animationNamespace))
                #endif
            }
        }
        #if os(iOS)
        .dreamCASTPageTheme()
        .fullScreenCover(item: $featuredPlayback) { media in
            FullScreenPlayerView(media: media)
        }
        #endif
    }

    #if os(iOS)
    /// A bounded, indexed recent-title query. Never create a live query for
    /// an entire IPTV movie catalog just to render one featured card.
    private func loadFeaturedMovie() {
        var descriptor = FetchDescriptor<Movie>(
            predicate: #Predicate<Movie> { $0.isAdult == 0 },
            sortBy: [SortDescriptor(\Movie.added, order: .reverse)]
        )
        descriptor.fetchLimit = 300
        let visibleCategories = Set(categories.map(\.id))
        let members = Set(playlists.members(of: scope, for: .movies).map(\.id))
        let candidates = ((try? modelContext.fetch(descriptor)) ?? []).filter { movie in
            guard let owner = playlists.owner(ofContentID: movie.id),
                  members.contains(owner.id) else { return false }
            if let category = movie.categoryId, !visibleCategories.contains(category) {
                return false
            }
            return !restriction.hides(categoryID: movie.categoryId)
        }
        featuredMovie = candidates.first(where: { $0.backdropPath != nil })
            ?? candidates.first(where: { $0.streamIcon != nil })
            ?? candidates.first
    }

    private func playFeatured(_ movie: Movie) {
        guard let playlist = playlists.owner(ofContentID: movie.id),
              let media = PlayableMedia.from(movie: movie, playlist: playlist) else {
            navigationPath.wrappedValue.append(movie)
            return
        }
        if ExternalPlayback.open(media) { return }
        if let sharedPlayback {
            sharedPlayback.tune(media, previewMode: .small)
        } else {
            // Standalone previews without the app root retain their player.
            featuredPlayback = media
        }
    }
    #endif

    /// Drives the stack from the shared `DeepLinkRouter` so an `onOpenURL` push
    /// lands here; falls back to a local path in previews where no router exists.
    private var navigationPath: Binding<NavigationPath> {
        guard let router else { return $fallbackPath }
        return Binding(get: { router.moviesPath }, set: { router.moviesPath = $0 })
    }

    /// Categories in scope, as preview rows plus one tile group per member.
    /// The `@Query` fetches every playlist's categories (SwiftData can't
    /// parameterize a `@Query` on view state), so the isolation by
    /// playlist-prefixed category `id` happens here.
    private var categoryLayout: LibraryCategoryLayout {
        LibraryCategoryLayout.make(
            categories: categories,
            members: playlists.members(of: scope, for: .movies).map { (id: $0.id, name: $0.name) },
            sort: categorySort,
            restriction: restriction,
            previewLimit: previewCategoryLimit
        )
    }
}

#Preview("Empty") {
    MoviesView()
        .modelContainer(for: Playlist.self, inMemory: true)
}

#Preview("With Data") {
    MoviesView()
        .modelContainer(previewContainer())
}
