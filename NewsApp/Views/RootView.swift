import SwiftUI

/// Hosts the feed and owns the refresh lifecycle.
struct RootView: View {
    @Environment(ArticleStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    @State private var isRefreshing = false
    @State private var lastRefresh: Date?
    @State private var refreshError: String?
    @State private var showingSaved = false
    @State private var toast: ToastMessage?

    private let service = FeedService()

    var body: some View {
        FeedView(showingSaved: $showingSaved, toast: $toast)
            .overlay(alignment: .top) {
                if let refreshError {
                    banner(refreshError)
                }
            }
            .toast($toast)
            .sheet(isPresented: $showingSaved) {
                SavedView(toast: $toast)
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

    private func banner(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(in: .capsule)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
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
            refreshError = nil
            await pruneImageCache()
        } catch FeedError.notConfigured {
            // Expected until the Vercel URL is filled in — stay quiet, the
            // bundled seed stories are already on screen.
            refreshError = nil
        } catch {
            withAnimation { refreshError = error.localizedDescription }
        }
    }

    /// Drops cached photos for articles that no longer exist in the store.
    private func pruneImageCache() async {
        let live = Set(store.articles.compactMap { $0.imageURL(base: FeedEndpoint.base) })
        await ImageCache.shared.evict(keeping: live)
    }
}
