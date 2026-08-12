import SwiftUI

/// The full story. Reached by tapping a card, which slides in from the right —
/// the photo reappears much smaller at the top, and neither headline overlay nor
/// subtitle are repeated here.
struct ArticleDetailView: View {
    let article: Article
    @Binding var toast: ToastMessage?

    @Environment(\.openURL) private var openURL
    @Environment(ArticleStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CachedImage(
                    url: article.imageURL(base: FeedEndpoint.base),
                    category: article.category,
                    maxPointSize: 700
                )
                .frame(height: 200)
                .overlay(alignment: .bottomLeading) {
                    CategoryTag(category: article.category)
                        .padding(16)
                }

                // Neither headline nor subtitle is repeated here — both have
                // already done their job of getting you to open the story, and
                // the space belongs to the body text.
                VStack(alignment: .leading, spacing: 18) {
                    StoryBodyView(markdown: article.body)

                    digDeeperButton

                    if !article.sources.isEmpty {
                        sourcesSection
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, 40)
            }
        }
        .background(Palette.page)
        .scrollIndicators(.hidden)
        // Swipe right anywhere on the story to go back, not only from the left
        // edge — a hand holding a phone one-handed doesn't reach that edge, and
        // there is nothing else a rightward swipe could mean while reading.
        .backSwipe()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HeartButton(article: article, toast: $toast)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        // Opening the full story is what "read" means here. Deliberately not
        // gated on scrolling to the end: the day picker is asking whether you've
        // been through the day's news, not whether you finished every word.
        .task { store.markRead(id: article.id) }
    }

    /// Hands the story to the system Share Sheet with a prompt asking an AI to
    /// verify and expand on it — Claude and Gemini both surface themselves there
    /// directly (as "Ask Claude" / their share extension) already signed in to
    /// whichever account the reader uses, so this needed no per-service logic.
    private var digDeeperPrompt: String {
        """
        Please verify and tell me more about this news story. Provide links to your sources.

        \(article.headline)

        \(article.body)
        """
    }

    private var digDeeperButton: some View {
        ShareLink(item: digDeeperPrompt, preview: SharePreview(article.headline)) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                Text("Find out more with AI")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .opacity(0.7)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NewsCategory.ai.tint, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .overlay(Palette.ink.opacity(0.15))
                .padding(.vertical, 6)

            Text("SOURCES")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(Palette.ink.opacity(0.45))

            ForEach(article.sources) { source in
                Button {
                    openURL(source.url)
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                            Text(source.displayHost)
                                .font(.caption)
                                .foregroundStyle(Palette.ink.opacity(0.45))
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.ink.opacity(0.5))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.ink.opacity(0.07), in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }

            Text(article.publishedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(Palette.ink.opacity(0.3))
                .padding(.top, 4)
        }
    }
}
