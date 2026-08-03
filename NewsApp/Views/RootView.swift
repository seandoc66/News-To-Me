import SwiftUI

/// Hosts the feed and owns the refresh lifecycle.
struct RootView: View {
    @Environment(ArticleStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    @State private var isRefreshing = false
    @State private var lastRefresh: Date?
    @State private var fetchFailure: String?
    /// Re-evaluated on each refresh so the staleness check uses a current clock
    /// rather than whenever the view happened to be built.
    @State private var staleness: FeedNotice?
    @State private var showingSaved = false
    @State private var showingSettings = false
    @State private var toast: ToastMessage?

    private let service = FeedService()

    var body: some View {
        FeedView(showingSaved: $showingSaved, showingSettings: $showingSettings, toast: $toast)
            .overlay(alignment: .top) {
                if let notice {
                    // Clears the category tag and the two floating buttons,
                    // which sit just below the safe-area top.
                    FeedNoticeBanner(notice: notice)
                        .padding(.top, 52)
                }
            }
            .toast($toast)
            .sheet(isPresented: $showingSaved) {
                SavedView(toast: $toast)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .task {
                // Purge first, and unconditionally — retention must not depend on
                // the network being reachable.
                store.purgeExpired()
                await refresh()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                store.purgeExpired()
                Task { await refresh() }
            }
    }

    /// An unreachable feed is the more urgent of the two, so it wins when both
    /// apply — a failed fetch is *why* the edition is stale.
    private var notice: FeedNotice? {
        if let fetchFailure { return .unreachable(fetchFailure) }
        return staleness
    }

    /// Ignore refresh requests that arrive within this window of the last one.
    ///
    /// `scenePhase` flips to `.active` during launch, moments after `.task` has
    /// already fetched — so without a debounce every launch hits the server
    /// twice. A flag can't fix it: on a fast connection the first fetch finishes
    /// before the phase change arrives, so the flag is already set. The feed only
    /// changes once a day, so a minute of coalescing costs nothing.
    private static let refreshDebounce: TimeInterval = 60

    private func refresh() async {
        guard !isRefreshing else { return }
        if let lastRefresh, Date.now.timeIntervalSince(lastRefresh) < Self.refreshDebounce {
            return
        }
        isRefreshing = true
        lastRefresh = .now
        defer { isRefreshing = false }

        do {
            let feed = try await service.fetchLatest()
            store.merge(feed)
            fetchFailure = nil
        } catch FeedError.notConfigured {
            // No feed URL set — stay quiet, the bundled seed stories are already
            // on screen.
            fetchFailure = nil
        } catch {
            withAnimation { fetchFailure = error.localizedDescription }
        }

        // Checked whether or not the fetch succeeded: a feed that loads
        // perfectly but is yesterday's is the failure that used to be silent.
        withAnimation {
            staleness = FeedNotice.staleness(of: store.feedGeneratedAt)
        }

        await pruneImageCache()
    }

    /// Drops cached photos for articles that no longer exist in the store.
    private func pruneImageCache() async {
        let live = Set(store.articles.compactMap { $0.imageURL(base: FeedEndpoint.base) })
        await ImageCache.shared.evict(keeping: live)
    }
}
