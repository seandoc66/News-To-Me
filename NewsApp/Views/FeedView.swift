import SwiftUI

/// Full-screen vertical pager: one story per screen, folding as you swipe.
///
/// Built on `ScrollView` + `.scrollTargetBehavior(.paging)` rather than a
/// rotated `TabView` (the pre-iOS-17 trick) so paging, safe areas and
/// `.scrollTransition` all behave natively.
struct FeedView: View {
    @Environment(ArticleStore.self) private var store
    @Binding var showingSaved: Bool
    @Binding var toast: ToastMessage?

    @State private var currentID: String?
    /// Article *ids*, not `Article` values. Hearting a story mutates its
    /// `savedAt`, which changes the value's hash — so pushing the value itself
    /// would break navigation identity mid-read.
    @State private var path: [String] = []

    /// Set the first time a page is turned, and remembered, so the swipe hint
    /// appears for a newcomer and never nags again.
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
            .overlay(alignment: .topTrailing) { savedButton }
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

            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(store.articles) { article in
                        // A NavigationLink rather than .onTapGesture: a
                        // full-screen tap recogniser inside a ScrollView can
                        // swallow the vertical drag, whereas a link cooperates
                        // with scrolling — a drag cancels it and pages instead.
                        NavigationLink(value: article.id) {
                            ArticleCardView(
                                article: article,
                                toast: $toast,
                                safeTop: safeTop,
                                safeBottom: safeBottom
                            )
                        }
                        .buttonStyle(.plain)
                        .containerRelativeFrame([.horizontal, .vertical])
                        .fold()
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $currentID)
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
            .onChange(of: currentID) { old, id in
                // Only a genuine page change counts — `currentID` also goes from
                // nil to the first article's id on appear.
                if let old, let id, old != id {
                    withAnimation(.easeOut(duration: 0.4)) { hasScrolledFeed = true }
                }
                Task { await prefetchNeighbours(of: id) }
            }
            #if DEBUG
            .task(id: store.articles.count) {
                guard let index = debugStartIndex,
                      store.articles.indices.contains(index) else { return }
                try? await Task.sleep(for: .milliseconds(400))
                currentID = store.articles[index].id
            }
            #endif
        }
    }

    private var savedButton: some View {
        Button {
            showingSaved = true
        } label: {
            Image(systemName: "heart.text.square")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.glass)
        .padding(.trailing, 16)
        .padding(.top, 8)
        .accessibilityLabel("Saved stories")
    }

    /// Decodes the photos either side of the current card so the fold never
    /// reveals an empty frame.
    private func prefetchNeighbours(of id: String?) async {
        guard let id, let index = store.articles.firstIndex(where: { $0.id == id }) else { return }
        let neighbours = [index - 1, index + 1, index + 2]
            .filter { store.articles.indices.contains($0) }
            .compactMap { store.articles[$0].imageURL(base: FeedEndpoint.base) }
        await ImageCache.shared.prefetch(neighbours, maxPixel: 1200 * 3)
    }
}

// MARK: - Fold transition

private extension View {
    /// Flipboard-style hinge fold driven by scroll position.
    ///
    /// `phase.value` runs continuously from -1 (card is above, folding away
    /// upward) through 0 (flat and centred) to +1 (card is below, still folded
    /// down). The hinge sits on whichever edge faces the centre of the screen,
    /// so a card pivots on its top edge as it leaves and its bottom edge as it
    /// arrives.
    ///
    /// The angle and perspective values are deliberately tuneable — how
    /// aggressive this looks is a matter of taste and needs judging on a real
    /// device, not in a simulator screenshot.
    func fold(maxAngle: Double = 76, perspective: CGFloat = 0.42) -> some View {
        scrollTransition(.interactive, axis: .vertical) { content, phase in
            let t = Double(phase.value)          // -1 ... 0 ... 1
            let magnitude = abs(t)
            return content
                .rotation3DEffect(
                    .degrees(t * maxAngle),
                    axis: (x: 1, y: 0, z: 0),
                    anchor: t < 0 ? .top : .bottom,
                    perspective: perspective
                )
                // Darken as the page turns away — this is what sells the crease.
                // (The transition closure hands back a VisualEffect, not a View,
                // so this has to be brightness rather than a black overlay.)
                .brightness(-magnitude * 0.45)
                .scaleEffect(1 - magnitude * 0.06)
        }
    }
}

// MARK: - Swipe affordance

/// A gently rising chevron telling you there's another story above this one.
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
