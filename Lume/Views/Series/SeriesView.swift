//
//  SeriesView.swift
//  Lume
//
//  Main view for browsing TV series. Each category shows a preview row;
//  "Show All" navigates to the full category view.
//

import SwiftData
import SwiftUI

struct SeriesView: View {
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
    @Query(filter: #Predicate<Category> { $0.typeRaw == "series" && $0.isHidden == false })
    private var categories: [Category]

    @AppStorage(PlaylistSelectionStore.key) private var selectedPlaylistID: String = ""
    @State private var showingSync = false
    @State private var showingSettings = false
    @State private var genres: [String] = []
    #if os(iOS)
    @State private var featuredSeries: Series?
    @State private var featuredPlayback: PlayableMedia?
    #endif

    @AppStorage(SortStorageKey.seriesCategories) private var categorySortRaw: String = CategorySortOption.playlist.rawValue
    @AppStorage(SortStorageKey.seriesContent) private var contentSortRaw: String = ContentSortOption.playlist.rawValue

    private var categorySort: CategorySortOption {
        CategorySortOption(rawValue: categorySortRaw) ?? .playlist
    }

    private var contentSort: ContentSortOption {
        ContentSortOption(rawValue: contentSortRaw) ?? .playlist
    }

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
                        systemImage: "tv",
                        description: Text("Add a playlist in Settings to start browsing series")
                    )
                } else if layout.isEmpty {
                    VStack(spacing: 20) {
                        ContentUnavailableView(
                            "No Series",
                            systemImage: "tv.fill",
                            description: Text("Sync your playlist to load TV series")
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
                                if let featuredSeries {
                                    DreamCASTMobileFeaturedHero(
                                        title: featuredSeries.name,
                                        badge: "Featured Series",
                                        artworkURL: TMDBClient.backdropURL(featuredSeries.backdropPath),
                                        fallbackURL: URL(string: featuredSeries.cover ?? ""),
                                        genre: featuredSeries.genre,
                                        releaseDate: featuredSeries.releaseDate,
                                        contentRating: featuredSeries.contentRating,
                                        extraInfo: featuredSeries.episodes.isEmpty ? nil : "\(featuredSeries.episodes.count) Episodes",
                                        summary: featuredSeries.plot,
                                        isWatchlisted: featuredSeries.addedToWatchlistDate != nil,
                                        primaryTitle: featuredSeries.episodes.isEmpty ? "Episodes" : "Play Episode",
                                        onPrimary: { playFeatured(featuredSeries) },
                                        onInfo: { navigationPath.wrappedValue.append(featuredSeries) },
                                        onWatchlist: {
                                            featuredSeries.addedToWatchlistDate = featuredSeries.addedToWatchlistDate == nil ? .now : nil
                                            try? modelContext.save()
                                        }
                                    )
                                }
                                #endif
                            SeriesCollectionRow(kind: .recentlyWatched, scope: scope, animationNamespace: animationNamespace)
                                .id("recent")
                            SeriesCollectionRow(kind: .favorites, scope: scope, animationNamespace: animationNamespace)
                                .id("favorites")
                            SeriesCollectionRow(kind: .recentlyAdded, scope: scope, animationNamespace: animationNamespace)
                                .id("new")

                            ForEach(layout.previews) { category in
                                SeriesCategoryPreview(category: category, limit: previewLimit, sort: contentSort, animationNamespace: animationNamespace)
                                    .id("\(category.id)-\(contentSort.rawValue)")
                            }

                            if !genres.isEmpty {
                                GenreGridSection(genres: genres, type: .series)
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
                        genres = await GenreDerivation.seriesGenres(in: modelContext.container, scope: scope, restriction: restriction)
                    }
                    #if os(iOS)
                    .task(id: "(scope.token)-(categories.count)-(playlists.map(\.syncStatusRaw).joined(separator: "|"))") {
                        loadFeaturedSeries()
                    }
                    #endif
                }
            }
            .platformNavigationTitle("Series")
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
                SeriesCategoryView(category: category, animationNamespace: animationNamespace)
            }
            .navigationDestination(for: LibraryCollection.self) { collection in
                SeriesCollectionView(kind: collection.kind, scope: scope, animationNamespace: animationNamespace)
            }
            .navigationDestination(for: GenreSelection.self) { selection in
                SeriesGenreView(genre: selection.genre, scope: scope, animationNamespace: animationNamespace)
            }
            .navigationDestination(for: Series.self) { series in
                SeriesDetailView(series: series, animationNamespace: animationNamespace)
                #if os(iOS)
                    .navigationTransition(.zoom(sourceID: series.id, in: animationNamespace))
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
    private func loadFeaturedSeries() {
        var descriptor = FetchDescriptor<Series>(
            sortBy: [SortDescriptor(\Series.lastModified, order: .reverse)]
        )
        descriptor.fetchLimit = 300
        let visibleCategories = Set(categories.map(\.id))
        let members = Set(playlists.members(of: scope, for: .series).map(\.id))
        let candidates = ((try? modelContext.fetch(descriptor)) ?? []).filter { series in
            guard let owner = playlists.owner(ofContentID: series.id),
                  members.contains(owner.id) else { return false }
            if let category = series.categoryId, !visibleCategories.contains(category) {
                return false
            }
            return !restriction.hides(categoryID: series.categoryId)
        }
        featuredSeries = candidates.first(where: { $0.backdropPath != nil })
            ?? candidates.first(where: { $0.cover != nil })
            ?? candidates.first
    }

    private func playFeatured(_ series: Series) {
        guard let episode = SeriesEpisodeProgress.nextEpisode(
            in: series.episodes, fallback: series.episodes.first
        ), let playlist = playlists.owner(ofContentID: series.id),
        let media = PlayableMedia.from(episode: episode, playlist: playlist) else {
            // Episode lists are lazy-loaded by the series detail page.
            // Open that page rather than claiming playback can start.
            navigationPath.wrappedValue.append(series)
            return
        }
        if ExternalPlayback.open(media) { return }
        featuredPlayback = media
    }
    #endif

    /// Drives the stack from the shared `DeepLinkRouter` so an `onOpenURL` push
    /// lands here; falls back to a local path in previews where no router exists.
    private var navigationPath: Binding<NavigationPath> {
        guard let router else { return $fallbackPath }
        return Binding(get: { router.seriesPath }, set: { router.seriesPath = $0 })
    }

    /// Categories in scope, as preview rows plus one tile group per member.
    /// The `@Query` fetches every playlist's categories (SwiftData can't
    /// parameterize a `@Query` on view state), so the isolation by
    /// playlist-prefixed category `id` happens here.
    private var categoryLayout: LibraryCategoryLayout {
        LibraryCategoryLayout.make(
            categories: categories,
            members: playlists.members(of: scope, for: .series).map { (id: $0.id, name: $0.name) },
            sort: categorySort,
            restriction: restriction,
            previewLimit: previewCategoryLimit
        )
    }
}

#Preview("Empty") {
    SeriesView()
        .modelContainer(for: Playlist.self, inMemory: true)
}

#Preview("With Data") {
    SeriesView()
        .modelContainer(previewContainer())
}
