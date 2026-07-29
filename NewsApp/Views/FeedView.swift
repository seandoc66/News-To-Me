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
                        ArticleCardView(
                            article: article,
                            toast: $toast,
                            safeTop: safeTop,
                            safeBottom: safeBottom
                        )
                        .containerRelativeFrame([.horizontal, .vertical])
                        .fold()
                        .onTapGesture { path.append(article.id) }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $currentID)
            .ignoresSafeArea()
            .onChange(of: currentID) { _, id in
                Task { await prefetchNeighbours(of: id) }
            }
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
