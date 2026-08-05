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
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottom) { progress }
        .toolbar(.hidden, for: .navigationBar)
        .task { reload() }
        // A refresh, a backfill or a purge can land while a day is open.
        .onChange(of: store.articles) { _, _ in reload() }
    }

    /// Only a genuine change to the day's line-up gets through to the pager.
    ///
    /// Every mutation of the store lands here, and turning a page is now one of
    /// them: the card you arrive on is marked read. Replacing `articles`
    /// wholesale on the way past would hand `FlipPager` a brand-new model
    /// mid-turn — the same stories in the same order, but a new array — and it
    /// would rebuild its four half-pages in the middle of the fold. The
    /// progress bar reads its own state from the store, so it stays live
    /// without this.
    private func reload() {
        let fresh = store.articles(on: day)
        guard fresh.map(\.id) != articles.map(\.id) else { return }
        articles = fresh
        index = min(index, max(0, articles.count - 1))
    }

    /// Marks the card you've landed on, whether or not you open it.
    ///
    /// Seeing the photo and the headline is reading enough to count: the
    /// question the day picker asks is whether you've been through the day's
    /// news, and a story you looked at and chose not to open has been answered.
    private func markSeen(_ i: Int) {
        guard articles.indices.contains(i) else { return }
        store.markRead(id: articles[i].id)
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
                        safeBottom: screen.bottom
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
                markSeen(i)
                Task { await prefetchNeighbours(of: i) }
            }
            .task {
                #if DEBUG
                if let start = debugStartIndex, articles.indices.contains(start) {
                    index = start
                }
                #endif
                markSeen(index)
                await prefetchNeighbours(of: index)
            }
        }
    }

    /// The furniture floating over the photo: the three buttons and the section
    /// pill for the story you're on.
    ///
    /// The nav bar is hidden so the photo can run to the top of the screen, so
    /// back is a floating glass circle like the other two — same shape, opposite
    /// corner. The pill sits in that row rather than on the card below it, so
    /// the whole strip reads as one band of chrome and the photograph starts
    /// cleanly beneath it.
    ///
    /// The pill is centred in the gap between the buttons, not on the screen.
    /// Glass lays a button out at about 60pt, half again as wide as its 40pt
    /// label, so the three of them leave a gap of roughly 165pt that isn't
    /// centred on anything — and "NATIONAL" is wide enough that centring it on
    /// the screen puts its right edge under the settings button.
    private var topBar: some View {
        HStack(spacing: 10) {
            button("chevron.left", label: "Back to the week") { dismiss() }

            Spacer(minLength: 12)
            if articles.indices.contains(index) {
                // `fixedSize` because the pill and the two spacers are
                // otherwise all flexible, and an HStack shares the slack out
                // between them rather than settling the pill at its ideal
                // width first — so "LOCAL" came out stacked three letters
                // deep in a circle. The tag's type is a fixed size, not
                // Dynamic Type, so its ideal width can't run away with the
                // row.
                CategoryTag(category: articles[index].category)
                    .fixedSize()
            }
            Spacer(minLength: 12)

            button("slider.horizontal.3", label: "Sections and sources") {
                showingSettings = true
            }
            button("heart.text.square", label: "Saved stories") {
                showingSaved = true
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// The day's progress, along the very bottom of the screen.
    ///
    /// It used to run under the top row, where it lay across the photograph at
    /// its most interesting point. Down here it sits under the story's text,
    /// where the card is plain black and the bar is the only thing on it.
    private var progress: some View {
        let screen = Self.window?.safeAreaInsets ?? .zero

        return Group {
            if !articles.isEmpty {
                ReadingProgressBar(articles: articles)
                    .padding(.horizontal, 16)
                    .padding(.bottom, max(screen.bottom, 10) + 4)
            }
        }
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

// MARK: - Reading progress

/// How much of the day has been read: one tick per story, in reading order,
/// each tinted by its section — local, national, world, tech, AI, left to
/// right. A story you've seen is in full colour; one you haven't is nothing at
/// all, so the bar draws itself in behind you as you go rather than sitting
/// there fully formed and waiting to be filled.
///
/// There is no track under it. There used to be an opaque black one, because an
/// unread tick was a dimmed tint and dimmed tints get lost against a photograph
/// — over a card that fell back to its own section colour, unread local ticks
/// came out the exact green of the page and disappeared. Unread ticks draw
/// nothing now, so there is nothing left to lose, and the black bar it needed
/// was the heaviest thing on the screen.
///
/// Read state comes from the store rather than the `Article` values handed in:
/// the feed deliberately holds its array still while you turn pages, so those
/// copies stop being current the moment a card is marked.
private struct ReadingProgressBar: View {
    let articles: [Article]

    @Environment(ArticleStore.self) private var store

    private func isRead(_ article: Article) -> Bool {
        store.article(id: article.id)?.isRead ?? article.isRead
    }

    private var readCount: Int { articles.filter(isRead).count }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(articles) { article in
                Capsule()
                    .fill(isRead(article) ? article.category.tint : .clear)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 4)
        // Only the filled ticks cast this; a clear capsule has nothing to cast.
        // Enough to hold them apart from a pale photograph without putting a
        // slab behind the whole bar.
        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
        // Short, because this now fires as you land on a card rather than on
        // the way back from one — it should settle before the turn finishes.
        .animation(.easeOut(duration: 0.22), value: readCount)
        .accessibilityElement()
        .accessibilityLabel("Reading progress")
        .accessibilityValue("\(readCount) of \(articles.count) stories read")
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
