import SwiftUI

/// The stories you hearted. These are exempt from the 5-day purge, so this is
/// the one place articles accumulate indefinitely.
struct SavedView: View {
    @Binding var toast: ToastMessage?

    @Environment(ArticleStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// The sheet needs its own toast: `RootView`'s overlay sits *behind* a
    /// presented sheet, so unsaving from here would show nothing.
    @State private var sheetToast: ToastMessage?

    var body: some View {
        NavigationStack {
            Group {
                if store.savedArticles.isEmpty {
                    empty
                } else {
                    list
                }
            }
            .background(.black)
            .navigationTitle("Saved")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: String.self) { id in
                if let article = store.article(id: id) {
                    ArticleDetailView(article: article, toast: $sheetToast)
                }
            }
        }
        .toast($sheetToast)
        .preferredColorScheme(.dark)
    }

    private var list: some View {
        List {
            ForEach(store.savedArticles) { article in
                NavigationLink(value: article.id) {
                    row(article)
                }
                .listRowBackground(Color.white.opacity(0.04))
                .swipeActions(edge: .trailing) {
                    Button("Unsave", systemImage: "heart.slash", role: .destructive) {
                        store.toggleSaved(id: article.id)
                        sheetToast = ToastMessage(text: "Removed from saved", symbol: "heart.slash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func row(_ article: Article) -> some View {
        HStack(spacing: 12) {
            CachedImage(
                url: article.imageURL(base: FeedEndpoint.base),
                category: article.category,
                maxPointSize: 200
            )
            .frame(width: 74, height: 74)
            .clipShape(.rect(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 5) {
                CategoryTag(category: article.category)
                    .scaleEffect(0.85, anchor: .leading)
                Text(article.headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text("Nothing saved yet")
                .font(.title3.weight(.semibold))
            Text("Tap the heart on any story to keep it here. Saved stories stay put — everything else clears after five days.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxHeight: .infinity)
    }
}
