import SwiftUI

/// One story, one screen: photo across the top half, headline beneath it,
/// subtitle filling what's left, and the heart floating on top.
///
/// The section pill isn't here. It used to sit in the photo's top corner and
/// spent its life dodging the row of floating buttons above it; it now lives in
/// that row, drawn by `FeedView`, which is the only view that knows what else is
/// up there.
struct ArticleCardView: View {
    let article: Article
    @Binding var toast: ToastMessage?
    /// Passed down from `FeedView`, which reads the real inset before the
    /// scroll view ignores it. Only the bottom one is needed: the photo runs
    /// under the status bar on purpose, and everything that has to clear it is
    /// drawn by `FeedView` over the top.
    let safeBottom: CGFloat

    @Environment(ArticleStore.self) private var store

    var body: some View {
        GeometryReader { geo in
            let photoHeight = geo.size.height * 0.5

            VStack(alignment: .leading, spacing: 0) {
                CachedImage(
                    url: article.imageURL(base: FeedEndpoint.base),
                    category: article.category
                )
                .frame(width: geo.size.width, height: photoHeight)
                .overlay(alignment: .bottom) {
                    // Keeps the headline legible against a bright photo edge.
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 90)
                    .allowsHitTesting(false)
                }

                // Neither text is `fixedSize` any more, and the block is given an
                // exact height rather than "whatever's left".
                //
                // `fixedSize(vertical:)` pins a Text to its ideal height, which
                // quietly cancels the `minimumScaleFactor` beneath it — so a long
                // headline over a long teaser grew the card taller than the
                // screen instead of shrinking to fit, and the overflow took the
                // heart off the bottom edge. Bounded, the scale factors do the
                // job they were always there to do.
                VStack(alignment: .leading, spacing: 16) {
                    Text(article.headline)
                        .font(.system(.title, design: .serif, weight: .bold))
                        .foregroundStyle(.white)
                        .lineSpacing(1)
                        .lineLimit(4)
                        .minimumScaleFactor(0.75)

                    // Set at title2 rather than body so a 20–50 word teaser
                    // genuinely fills the lower half of the screen instead of
                    // leaving a dead gap above the heart.
                    Text(article.subtitle)
                        .font(.system(.title2, design: .default))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineSpacing(5)
                        // Shrink rather than push the heart off screen at large
                        // Dynamic Type sizes.
                        .minimumScaleFactor(0.6)

                    Spacer(minLength: 8)

                    HStack(alignment: .bottom) {
                        Text("Tap to read")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.4))
                        Spacer()
                        HeartButton(article: article, toast: $toast)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, max(safeBottom, 16) + 6)
                .frame(
                    width: geo.size.width,
                    height: geo.size.height - photoHeight,
                    alignment: .topLeading
                )
            }
            // `alignment: .top` is load-bearing. A long headline over a long
            // teaser can make this stack taller than the card, and a frame
            // centres what overflows it — so the photo, and the section tag
            // pinned to its top corner, rode up off the top of the screen and
            // the tag ended up level with the clock. Which stories did it
            // depended on how many lines their headline wrapped to.
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .background(.black)
            .contentShape(.rect)
        }
    }
}

// MARK: - Heart

struct HeartButton: View {
    let article: Article
    @Binding var toast: ToastMessage?

    @Environment(ArticleStore.self) private var store
    @State private var bounce = false

    private var isSaved: Bool {
        store.article(id: article.id)?.isSaved ?? article.isSaved
    }

    var body: some View {
        Button {
            let nowSaved = store.toggleSaved(id: article.id)
            bounce.toggle()
            toast = ToastMessage(
                text: nowSaved ? "Saved for later" : "Removed from saved",
                symbol: nowSaved ? "heart.fill" : "heart.slash"
            )
        } label: {
            Image(systemName: isSaved ? "heart.fill" : "heart")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(isSaved ? .pink : .white)
                .frame(width: 46, height: 46)
                .symbolEffect(.bounce, value: bounce)
        }
        .glassButtonStyle()
        .sensoryFeedback(.impact(weight: .light), trigger: bounce)
        .accessibilityLabel(isSaved ? "Remove from saved" : "Save for later")
    }
}

// MARK: - Section tag

struct CategoryTag: View {
    let category: NewsCategory

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: category.symbolName)
                .font(.system(size: 10, weight: .bold))
            Text(category.displayName.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.8)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(category.tint.opacity(0.9), in: .capsule)
        .overlay(
            Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
        )
    }
}
