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
    #if os(tvOS)
    @State private var selectedBrowseRail = "all"
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
                    #if os(tvOS)
                    HStack(alignment: .top, spacing: TVSidebarRail.paneSpacing) {
                        TVSidebarRail(
                            items: browseRailItems(for: layout),
                            selectedID: selectedBrowseRail
                        )
                        browseContent(for: layout)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 35)
                    #else
                    browseContent(for: layout)
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
        #if os(tvOS)
        .onExitCommand {
            NotificationCenter.default.post(name: .dreamCASTReturnToTopMenu, object: nil)
        }
        #endif
    }

    /// The existing category and collection rails, now beside a tvOS sidebar.
    private func browseContent(for layout: LibraryCategoryLayout) -> some View {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 24, pinnedViews: []) {
                            SeriesCollectionRow(kind: .recentlyWatched, scope: scope, animationNamespace: animationNamespace)
                            SeriesCollectionRow(kind: .favorites, scope: scope, animationNamespace: animationNamespace)
                            SeriesCollectionRow(kind: .recentlyAdded, scope: scope, animationNamespace: animationNamespace)

                            ForEach(layout.previews) { category in
                                SeriesCategoryPreview(category: category, limit: previewLimit, sort: contentSort, animationNamespace: animationNamespace)
                                    .id("\(category.id)-\(contentSort.rawValue)")
                            }

                            if !genres.isEmpty {
                                GenreGridSection(genres: genres, type: .series)
                            }

                            ForEach(layout.remaining) { group in
                                CategoryGridSection(group: group)
                                    .padding(.top, 12)
                            }
                        }
                        .padding(.vertical)
                    }
                    .browseActivity()
                    .task(id: scope.token) {
                        genres = await GenreDerivation.seriesGenres(in: modelContext.container, scope: scope, restriction: restriction)
                    }
    }

    #if os(tvOS)
    /// Every rail action opens the existing collection or category destination.
    /// Moving focus alone never changes the selected category.
    private func browseRailItems(for layout: LibraryCategoryLayout) -> [TVSidebarRailItem] {
        var items: [TVSidebarRailItem] = [
            TVSidebarRailItem(
                id: "all", title: Text("All Series"), icon: "play.tv",
                action: {
                    selectedBrowseRail = "all"
                    navigationPath.wrappedValue = NavigationPath()
                }
            )
        ]

        for kind in [LibraryCollection.Kind.recentlyWatched, .favorites, .recentlyAdded] {
            let rowID = "collection-\(kind.rawValue)"
            items.append(TVSidebarRailItem(
                id: rowID, title: Text(kind.title), icon: kind.emptyIcon,
                action: {
                    selectedBrowseRail = rowID
                    navigationPath.wrappedValue.append(
                        LibraryCollection(kind: kind, type: .series)
                    )
                }
            ))
        }

        let visibleCategories = layout.previews + layout.remaining.flatMap { $0.categories }
        for category in visibleCategories.prefix(14) {
            items.append(TVSidebarRailItem(
                id: category.id, title: Text(category.name),
                action: {
                    selectedBrowseRail = category.id
                    navigationPath.wrappedValue.append(category)
                }
            ))
        }
        return items
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
