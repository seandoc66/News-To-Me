import SwiftUI

/// One day's edition: a full-screen vertical pager, one story per screen,
/// turning like the pages of a spiral-bound pad hinged across the middle of the
/// screen.
///
/// Scoped to a single day on purpose. This used to page through everything the
/// store held — five mornings run together with no seam — so the story after the
/// last of today's was yesterday's lead, and nothing said so.
///
/// The turn itself lives in `FlipPager` — see there for why this can't be a
/// `ScrollView`.
struct FeedView: View {
    /// Midnight of the day being read, as handed over by the day picker.
    let day: Date
    @Binding var showingSaved: Bool
    @Binding var showingSettings: Bool
    @Binding var toast: ToastMessage?

    @Environment(ArticleStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// This day's stories, cached rather than recomputed in `body`.
    ///
    /// `FlipPager` rebuilds four clipped half-pages per frame during a turn, and
    /// bucketing the whole store by calendar day on each of them — `startOfDay`
    /// per article, per half, sixty times a second — is not free.
    @State private var articles: [Article] = []
    @State private var index = 0

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
        Group {
            if articles.isEmpty {
                EmptyFeedView(day: day)
            } else {
                pager
            }
        }
        .background(.black)
        // Swipe right anywhere to go back to the week. The nav bar is hidden
        // here so UIKit's own edge swipe is refused outright — this screen had
        // nothing but the chevron until now.
        .backSwipe()
        .overlay(alignment: .topLeading) { backButton }
        .overlay(alignment: .topTrailing) { topButtons }
        .toolbar(.hidden, for: .navigationBar)
        .task { reload() }
        // A refresh, a backfill or a purge can land while a day is open.
        .onChange(of: store.articles) { _, _ in reload() }
    }

    private func reload() {
        articles = store.articles(on: day)
        index = min(index, max(0, articles.count - 1))
    }

    /// The window the feed is being drawn into.
    ///
    /// Both its size and its safe-area insets are needed, and neither can be got
    /// from a proxy on this screen. Inside the card a proxy reads zeroes,
    /// because the card is deliberately bigger than the space it is given. And
    /// just outside it the numbers don't agree with each other: this screen is
    /// laid out from an origin 20pt down while reporting a 47pt top inset, so
    /// anything derived from that pair — `ignoresSafeArea` included — lands the
    /// card 27pt high and takes the category tag up into the status bar.
    private static var window: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow
    }

    private var pager: some View {
        let screen = Self.window?.safeAreaInsets ?? .zero
        let screenSize = Self.window?.bounds.size ?? .zero

        // Sized to the window and pulled up by however far down the screen this
        // reader actually starts, so the card's edges land on the screen's
        // edges — measured rather than inferred.
        return GeometryReader { outer in
            let originY = outer.frame(in: .global).minY

            FlipPager(count: articles.count, index: $index) { i in
                // A NavigationLink rather than .onTapGesture: a full-screen tap
                // recogniser swallows the vertical drag, whereas a link
                // cooperates with it — a drag cancels the link and turns the
                // page instead.
                NavigationLink(value: Route.article(articles[i].id)) {
                    ArticleCardView(
                        article: articles[i],
                        toast: $toast,
                        safeTop: screen.top,
                        safeBottom: screen.bottom,
                        tagTopGap: Self.tagTopGap
                    )
                }
                .buttonStyle(.plain)
            }
            .frame(width: screenSize.width, height: screenSize.height)
            .overlay(alignment: .bottom) {
                // Each card fills the screen exactly, so without this there is
                // no visual cue that anything exists below it. Attached here,
                // inside the offset below, so it travels with the card's bottom
                // edge rather than the reader's.
                if !hasScrolledFeed, articles.count > 1 {
                    SwipeUpHint()
                        .padding(.bottom, screen.bottom + 18)
                        .transition(.opacity)
                }
            }
            .offset(y: -originY)
            .onChange(of: index) { _, i in
                withAnimation(.easeOut(duration: 0.4)) { hasScrolledFeed = true }
                Task { await prefetchNeighbours(of: i) }
            }
            .task {
                #if DEBUG
                if let start = debugStartIndex, articles.indices.contains(start) {
                    index = start
                }
                #endif
                await prefetchNeighbours(of: index)
            }
        }
    }

    /// How far the card's category tag is dropped, to clear the row of floating
    /// buttons. 8pt of padding, a button a little over 40pt tall once its glass
    /// capsule is counted, and a gap under it.
    private static let tagTopGap: CGFloat = 62

    /// The nav bar is hidden so the photo can run to the top of the screen, so
    /// back is a floating glass circle like the other two — same shape, opposite
    /// corner.
    private var backButton: some View {
        button("chevron.left", label: "Back to the week") { dismiss() }
            .padding(.leading, 16)
            .padding(.top, 8)
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
        .glassButtonStyle()
        .accessibilityLabel(label)
    }

    /// Decodes the photos either side of the current card so the turn never
    /// reveals an empty frame.
    private func prefetchNeighbours(of i: Int) async {
        let neighbours = [i - 1, i + 1, i + 2]
            .filter { articles.indices.contains($0) }
            .compactMap { articles[$0].imageURL(base: FeedEndpoint.base) }
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

/// Reachable in one narrow case: a day whose stories were purged, or dropped by
/// a refresh, while its feed was open. The day picker disables a button with
/// nothing behind it, so this is a race rather than a route.
private struct EmptyFeedView: View {
    let day: Date

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "newspaper")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("Nothing for \(day.formatted(.dateTime.weekday(.wide)))")
                .font(.title3.weight(.semibold))
            Text("There's no edition for this day. Pick another from the front page.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}
