import Foundation
import Observation

/// Owns every article the app knows about, and persists them to a single JSON
/// file in Application Support.
///
/// Why a JSON file rather than SwiftData: this store holds ~30 articles/day for
/// 7 days (a couple of hundred records), with no relationships and no queries
/// beyond "sort by section". At that scale a file is less code, has no schema
/// migration to get wrong, and can be inspected with `cat` when something looks
/// off. SwiftData would earn its keep if this grew relationships or thousands of
/// records.
@Observable
final class ArticleStore {

    /// How long an unsaved article survives after the app first sees it.
    static let retention: TimeInterval = 7 * 24 * 60 * 60

    /// Every article, ordered the way the feed is read: section by section
    /// (local → national → global → tech → AI), most recent first within a section.
    private(set) var articles: [Article] = []

    /// When the currently-loaded feed was generated on the server. Lets the UI
    /// say "no new stories today" if the daily job didn't run.
    private(set) var feedGeneratedAt: Date?

    /// The publishing rules the last successful fetch reported. Persisted with
    /// the articles so Settings still has something to show offline, and kept
    /// from the previous feed if a newer one omits the block.
    private(set) var feedConfig: FeedConfig?

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        load()
    }

    // MARK: - Reading

    var savedArticles: [Article] {
        articles
            .filter(\.isSaved)
            .sorted { ($0.savedAt ?? .distantPast) > ($1.savedAt ?? .distantPast) }
    }

    func article(id: String) -> Article? {
        articles.first { $0.id == id }
    }

    // MARK: - Mutating

    /// Folds a freshly fetched feed into the store.
    ///
    /// Articles already present keep their local `fetchedAt` and `savedAt` — a
    /// re-published story must never lose its heart or have its purge clock
    /// reset. Genuinely new articles are inserted with `fetchedAt = now`.
    ///
    /// Every article takes this feed's edition and its position in it, including
    /// re-published ones: a story carried into today's edition belongs in
    /// today's running order, at the slot the generator gave it.
    func merge(_ feed: Feed) {
        var byID = Dictionary(uniqueKeysWithValues: articles.map { ($0.id, $0) })

        for (position, incoming) in feed.articles.enumerated() {
            var article = incoming
            if let existing = byID[incoming.id] {
                article.fetchedAt = existing.fetchedAt
                article.savedAt = existing.savedAt
            } else {
                article.fetchedAt = .now
                article.savedAt = nil
            }
            article.editionAt = feed.generatedAt
            article.feedOrder = position
            byID[incoming.id] = article
        }

        feedGeneratedAt = feed.generatedAt
        // A feed without a config block leaves the last known one in place —
        // better a slightly stale Settings screen than an empty one.
        if let config = feed.config { feedConfig = config }
        articles = Self.sorted(Array(byID.values))
        persist()
    }

    /// Drops unsaved articles older than the retention window.
    ///
    /// Called on every launch regardless of whether the fetch succeeded —
    /// otherwise a week with no network would mean nothing ever expires.
    /// Returns the number removed.
    @discardableResult
    func purgeExpired(now: Date = .now) -> Int {
        let cutoff = now.addingTimeInterval(-Self.retention)
        let before = articles.count
        articles.removeAll { !$0.isSaved && $0.fetchedAt < cutoff }
        let removed = before - articles.count
        if removed > 0 { persist() }
        return removed
    }

    /// Hearts or un-hearts an article. Returns true if it is now saved.
    @discardableResult
    func toggleSaved(id: String, now: Date = .now) -> Bool {
        guard let index = articles.firstIndex(where: { $0.id == id }) else { return false }
        let nowSaved = articles[index].savedAt == nil
        articles[index].savedAt = nowSaved ? now : nil
        persist()
        return nowSaved
    }

    // MARK: - Ordering

    /// Sections in reading order; within a section, newest edition first and
    /// then exactly the order the generator emitted.
    ///
    /// Deliberately *not* sorted by `publishedAt`: the generator ranks a section
    /// by significance, and ordering by date silently overrides that — a lead
    /// story researched from a morning source would fall below a lighter one
    /// filed later. `feedOrder` carries the ranking the generator intended.
    ///
    /// Articles stored before those fields existed fall back to `publishedAt`,
    /// which is the old behaviour and orders them sensibly among themselves.
    /// The comparison is a total order, so the result doesn't depend on
    /// `sorted(by:)` being stable — it isn't.
    private static func sorted(_ articles: [Article]) -> [Article] {
        articles.sorted { lhs, rhs in
            if lhs.category.sortOrder != rhs.category.sortOrder {
                return lhs.category.sortOrder < rhs.category.sortOrder
            }
            let lhsEdition = lhs.editionAt ?? lhs.publishedAt
            let rhsEdition = rhs.editionAt ?? rhs.publishedAt
            if lhsEdition != rhsEdition {
                return lhsEdition > rhsEdition
            }
            if lhs.feedOrder != rhs.feedOrder {
                return (lhs.feedOrder ?? .max) < (rhs.feedOrder ?? .max)
            }
            return lhs.id < rhs.id
        }
    }

    // MARK: - Disk

    private struct Snapshot: Codable {
        var generatedAt: Date?
        var articles: [Article]
        /// Optional so snapshots written before the config block existed still
        /// decode.
        var config: FeedConfig?
    }

    private static func defaultFileURL() -> URL {
        let dir = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "articles.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            // Nothing stored yet — fall back to the copy bundled with the app so
            // the very first launch has something to show, online or not.
            if let seed = Self.bundledSeedFeed() {
                feedGeneratedAt = seed.generatedAt
                feedConfig = seed.config
                articles = Self.sorted(seed.articles.enumerated().map { position, article in
                    var a = article
                    a.fetchedAt = .now
                    a.editionAt = seed.generatedAt
                    a.feedOrder = position
                    return a
                })
            }
            return
        }
        do {
            let snapshot = try JSONDecoder.feed.decode(Snapshot.self, from: data)
            feedGeneratedAt = snapshot.generatedAt
            feedConfig = snapshot.config
            articles = Self.sorted(snapshot.articles)
        } catch {
            // A corrupt store must never brick the app. Start clean; the next
            // fetch refills it.
            print("ArticleStore: could not read \(fileURL.lastPathComponent) — \(error)")
            articles = []
        }
    }

    private func persist() {
        let snapshot = Snapshot(generatedAt: feedGeneratedAt, articles: articles, config: feedConfig)
        do {
            let data = try JSONEncoder.feed.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("ArticleStore: could not write \(fileURL.lastPathComponent) — \(error)")
        }
    }

    /// The seed feed shipped inside the app bundle, used on first launch.
    private static func bundledSeedFeed() -> Feed? {
        guard let url = Bundle.main.url(forResource: "seed", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.feed.decode(Feed.self, from: data)
    }
}
