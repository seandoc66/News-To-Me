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

    /// The measured height of the reading bar and its section name.
    ///
    /// Seeded with what the two of them come to at their current sizes, so the
    /// very first card is laid out clear of them rather than being corrected a
    /// frame later.
    @State private var progressHeight: CGFloat = 26

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
                        bottomInset: bottomInset
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
                        .padding(.bottom, bottomInset + 8)
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

    /// The three buttons, floating over the photo.
    ///
    /// The nav bar is hidden so the photo can run to the top of the screen, so
    /// back is a floating glass circle like the other two — same shape, opposite
    /// corner.
    ///
    /// The section used to be a tinted pill in the middle of this row. A pill
    /// over a photograph is one more small bright object among many and was easy
    /// to look straight past, so the section is named down at the bar instead,
    /// where it sits on plain black and marks the story you're on.
    private var topBar: some View {
        HStack(spacing: 10) {
            button("chevron.left", label: "Back to the week") { dismiss() }
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
        Group {
            if !articles.isEmpty {
                ReadingProgressBar(articles: articles, current: index)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        progressHeight = $0
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, Self.progressBottomGap)
            }
        }
    }

    /// The gap between the reading bar and the bottom of the screen. Clears the
    /// home indicator, or stands in for it on a device without one.
    private static var progressBottomGap: CGFloat {
        max(window?.safeAreaInsets.bottom ?? 0, 10) + 4
    }

    /// How much of the card's bottom the reading bar and its section name take
    /// up, with a gap over them for the story's last line.
    ///
    /// The bar is drawn in an overlay, so it floats over the card and knows
    /// nothing about the text underneath — a long enough teaser ran its last
    /// line straight through the ticks and the word under them. The card can't
    /// work this out for itself either: it is the same size as the screen and
    /// has no idea what the reader has put on top of it. So the reader measures
    /// its own furniture and tells the card how much room to leave.
    private var bottomInset: CGFloat {
        Self.progressBottomGap + progressHeight + 12
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

/// How much of the day has been read and where in it you are: one tick per
/// story, in reading order, each tinted by its section — local, national,
/// world, tech, AI, left to right — with the section you're in named under its
/// own run of ticks.
///
/// Three states. The story you're on is the tint lifted halfway to white; one
/// you've seen is the tint itself; one you haven't is nothing at all, so the bar
/// draws itself in behind you as you go rather than sitting there fully formed
/// and waiting to be filled. The current tick is drawn bright whether or not it
/// has been marked yet, so the bar always says where you are — and once you turn
/// back through stories you've already seen, it is the only thing that does.
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
    let current: Int

    @Environment(ArticleStore.self) private var store

    /// Measured rather than assumed: the section name is placed along the bar by
    /// fraction, so both widths have to be real numbers before it can be centred
    /// over a tick and kept inside the bar's ends.
    @State private var barWidth: CGFloat = 0
    @State private var labelWidth: CGFloat = 0

    private func isRead(_ article: Article) -> Bool {
        store.article(id: article.id)?.isRead ?? article.isRead
    }

    private var readCount: Int { articles.filter(isRead).count }

    private var currentCategory: NewsCategory? {
        articles.indices.contains(current) ? articles[current].category : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ticks
            if let currentCategory { label(currentCategory) }
        }
        // Short, because these now fire as you land on a card rather than on
        // the way back from one — they should settle before the turn finishes.
        .animation(.easeOut(duration: 0.22), value: readCount)
        .animation(.easeOut(duration: 0.25), value: current)
        .accessibilityElement()
        .accessibilityLabel("Reading progress")
        .accessibilityValue(accessibilityValue)
    }

    private var ticks: some View {
        HStack(spacing: 2) {
            ForEach(Array(articles.enumerated()), id: \.element.id) { position, article in
                Capsule()
                    .fill(fill(for: article, at: position))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 4)
        // Only the filled ticks cast this; a clear capsule has nothing to cast.
        // Enough to hold them apart from a pale photograph without putting a
        // slab behind the whole bar.
        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { barWidth = $0 }
    }

    private func fill(for article: Article, at position: Int) -> Color {
        guard position != current else {
            // Full tint is already what "seen" looks like, so the only way up
            // from there is towards white.
            return article.category.tint.mix(with: .white, by: 0.5)
        }
        return isRead(article) ? article.category.tint : .clear
    }

    /// The section, named under its own stretch of the bar.
    ///
    /// Under the whole run rather than under the tick you're on, so it holds
    /// still while you read through a section and only moves when you cross into
    /// the next one. Following the current tick meant a word sliding a few
    /// points under the bar on every single page turn, which pulled the eye down
    /// to it each time for news it had already given you.
    private func label(_ category: NewsCategory) -> some View {
        Text(category.displayName.uppercased())
            .font(.system(size: 12, weight: .heavy))
            .tracking(1.1)
            // The pill's own colour, not the lifted one the tick uses. The bar
            // lives on the plain black under the story's text, which is what
            // makes a flat tint legible here where it wasn't over a photograph.
            .foregroundStyle(category.tint)
            .shadow(color: .black.opacity(0.8), radius: 4, y: 1)
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { labelWidth = $0 }
            .offset(x: labelOffset)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The stretch of ticks the current section owns.
    ///
    /// The store hands a day over ordered by section, so a section is always one
    /// unbroken run and its first and last stories describe the whole of it.
    private var currentRun: ClosedRange<Int>? {
        guard let currentCategory,
              let first = articles.firstIndex(where: { $0.category == currentCategory }),
              let last = articles.lastIndex(where: { $0.category == currentCategory })
        else { return nil }
        return first...last
    }

    /// Centred under the section's run, then pulled back inside the bar at both
    /// ends — the first and last runs reach the very edge, and a word centred on
    /// a short one there would hang off the side of the screen.
    private var labelOffset: CGFloat {
        guard barWidth > 0, !articles.isEmpty, let run = currentRun else { return 0 }
        let runCentre = barWidth
            * CGFloat(run.lowerBound + run.upperBound + 1)
            / (2 * CGFloat(articles.count))
        return min(max(runCentre - labelWidth / 2, 0), max(barWidth - labelWidth, 0))
    }

    private var accessibilityValue: String {
        let position = "story \(current + 1) of \(articles.count)"
        guard let currentCategory else { return position }
        return "\(currentCategory.displayName), \(position), \(readCount) read"
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
