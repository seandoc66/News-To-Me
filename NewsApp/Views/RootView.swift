import SwiftUI

/// Everywhere the app can push to.
///
/// One enum rather than two `navigationDestination`s, so the stack's path stays
/// a single homogeneous array — with two element types you can't express "day,
/// then story" as one path.
///
/// The story case carries an *id*, not an `Article`: hearting or reading a story
/// mutates it, which changes the value's hash and would break navigation
/// identity mid-read.
enum Route: Hashable {
    case day(Date)
    case article(String)
}

/// Hosts the day picker and owns the refresh lifecycle.
struct RootView: View {
    @Environment(ArticleStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    @State private var path: [Route] = []
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

    #if DEBUG
    /// Dev hook: launching with `-openDay N` opens straight onto the Nth day
    /// button (0 = today), so the feed can be screenshotted without touch input.
    ///
    ///     xcrun simctl launch <device> com.shanedoc.NewsApp -openDay 1
    private func debugOpenDay() {
        guard UserDefaults.standard.object(forKey: "openDay") != nil else { return }
        let offset = UserDefaults.standard.integer(forKey: "openDay")
        let days = store.recentDays()
        guard days.indices.contains(offset) else { return }
        path = [.day(days[offset].date)]
    }
    #endif

    var body: some View {
        NavigationStack(path: $path) {
            DayPickerView(
                notice: notice,
                showingSaved: $showingSaved,
                showingSettings: $showingSettings
            )
            // Registered on the stack's root so it covers everything pushed
            // above it — a destination declared inside a lazily-built pushed
            // view isn't there yet when the push happens.
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .day(let date):
                    FeedView(
                        day: date,
                        showingSaved: $showingSaved,
                        showingSettings: $showingSettings,
                        toast: $toast
                    )
                case .article(let id):
                    if let article = store.article(id: id) {
                        ArticleDetailView(article: article, toast: $toast)
                    }
                }
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
            #if DEBUG
            debugOpenDay()
            #endif
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

        // After the live merge, so today's edition claims its stories before the
        // archive is asked for anything.
        await backfillMissingDays()

        // Checked whether or not the fetch succeeded: a feed that loads
        // perfectly but is yesterday's is the failure that used to be silent.
        withAnimation {
            staleness = FeedNotice.staleness(of: store.feedGeneratedAt)
        }

        await pruneImageCache()
    }

    /// Fills any day button that has no stories from the published archive.
    ///
    /// The app only ever downloads `latest.json`, so before this a past day was
    /// populated only if the app happened to be opened that morning — a fresh
    /// install, or a few days away, would show a row of empty days. Days that
    /// were genuinely never published stay empty and are re-checked cheaply on
    /// each refresh; a 404 is one request and the refresh debounce caps how
    /// often it can happen.
    private func backfillMissingDays() async {
        for day in store.recentDays() where day.isEmpty {
            guard let feed = try? await service.fetchArchive(for: day.date) else { continue }
            store.merge(archive: feed)
        }
    }

    /// Drops cached photos for articles that no longer exist in the store.
    private func pruneImageCache() async {
        let live = Set(store.articles.compactMap { $0.imageURL(base: FeedEndpoint.base) })
        await ImageCache.shared.evict(keeping: live)
    }
}
