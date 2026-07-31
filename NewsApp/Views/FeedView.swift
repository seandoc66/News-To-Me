import SwiftUI

/// Full-screen vertical pager: one story per screen, turning like the pages of
/// a spiral-bound pad hinged across the middle of the screen.
///
/// The turn itself lives in `FlipPager` — see there for why this can't be a
/// `ScrollView`.
struct FeedView: View {
    @Environment(ArticleStore.self) private var store
    @Binding var showingSaved: Bool
    @Binding var showingSettings: Bool
    @Binding var toast: ToastMessage?

    @State private var index = 0
    /// Article *ids*, not `Article` values. Hearting a story mutates its
    /// `savedAt`, which changes the value's hash — so pushing the value itself
    /// would break navigation identity mid-read.
    @State private var path: [String] = []

    /// Set the first time a page is turned, and remembered, so the hint appears
    /// for a newcomer and never nags again.
    @AppStorage("hasScrolledFeed") private var hasScrolledFeed = false

    #if DEBUG
    /// Dev hook: launching with `-startAt N` opens straight onto the Nth card
    /// (1-based), so layouts can be screenshotted without touch input.
    ///
    ///     xcrun simctl launch <device> com.shanedoc.NewsApp -startAt 3
    private var debugStartIndex: Int? {
        let n = UserDefaults.standard.integer(forKey: "startAt")
        return n > 0 ? n - 1 : nil
    }
    #endif

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.articles.isEmpty {
                    EmptyFeedView()
                } else {
                    pager
                }
            }
            .background(.black)
            .overlay(alignment: .topTrailing) { topButtons }
            .navigationDestination(for: String.self) { id in
                if let article = store.article(id: id) {
                    ArticleDetailView(article: article, toast: $toast)
                }
            }
        }
    }

    private var pager: some View {
        // The safe-area insets have to be read out here, *outside* the
        // `ignoresSafeArea` below — a GeometryReader inside the card sees zeroes
        // and the status bar would sit on top of the category tag.
        GeometryReader { outer in
            let safeTop = outer.safeAreaInsets.top
            let safeBottom = outer.safeAreaInsets.bottom

            FlipPager(count: store.articles.count, index: $index) { i in
                // A NavigationLink rather than .onTapGesture: a full-screen tap
                // recogniser swallows the vertical drag, whereas a link
                // cooperates with it — a drag cancels the link and turns the
                // page instead.
                NavigationLink(value: store.articles[i].id) {
                    ArticleCardView(
                        article: store.articles[i],
                        toast: $toast,
                        safeTop: safeTop,
                        safeBottom: safeBottom
                    )
                }
                .buttonStyle(.plain)
            }
            .ignoresSafeArea()
            .overlay(alignment: .bottom) {
                // Each card fills the screen exactly, so without this there is
                // no visual cue that anything exists below it.
                if !hasScrolledFeed, store.articles.count > 1 {
                    SwipeUpHint()
                        .padding(.bottom, safeBottom + 18)
                        .transition(.opacity)
                }
            }
            .onChange(of: index) { _, i in
                withAnimation(.easeOut(duration: 0.4)) { hasScrolledFeed = true }
                Task { await prefetchNeighbours(of: i) }
            }
            .onChange(of: store.articles.count) { _, count in
                // A refresh or a purge can land while the feed is open.
                index = min(index, max(0, count - 1))
            }
            .task {
                #if DEBUG
                if let start = debugStartIndex, store.articles.indices.contains(start) {
                    index = start
                }
                #endif
                await prefetchNeighbours(of: index)
            }
        }
    }

    private var topButtons: some View {
        HStack(spacing: 10) {
            button("slider.horizontal.3", label: "Sections and sources") {
                showingSettings = true
            }
            button("heart.text.square", label: "Saved stories") {
                showingSaved = true
            }
        }
        .padding(.trailing, 16)
        .padding(.top, 8)
    }

    private func button(
        _ symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.glass)
        .accessibilityLabel(label)
    }

    /// Decodes the photos either side of the current card so the turn never
    /// reveals an empty frame.
    private func prefetchNeighbours(of i: Int) async {
        let neighbours = [i - 1, i + 1, i + 2]
            .filter { store.articles.indices.contains($0) }
            .compactMap { store.articles[$0].imageURL(base: FeedEndpoint.base) }
        await ImageCache.shared.prefetch(neighbours, maxPixel: 1200 * 3)
    }
}

// MARK: - Swipe affordance

/// A gently rising chevron telling you there's another story under this one.
private struct SwipeUpHint: View {
    @State private var lift = false

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "chevron.compact.up")
                .font(.system(size: 26, weight: .medium))
            Text("Swipe for next story")
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(.white.opacity(0.55))
        .offset(y: lift ? -6 : 0)
        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: lift)
        .allowsHitTesting(false)
        .onAppear { lift = true }
    }
}

// MARK: - Empty state

private struct EmptyFeedView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "newspaper")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("No stories yet")
                .font(.title3.weight(.semibold))
            Text("Today's edition hasn't arrived. Pull the app open again once the morning feed has run.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}
