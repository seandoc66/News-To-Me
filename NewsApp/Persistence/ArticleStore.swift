import Foundation
import Observation

/// Owns every article the app knows about, and persists them to a single JSON
/// file in Application Support.
///
/// Why a JSON file rather than SwiftData: this store holds ~30 articles/day for
/// 5 days (a couple of hundred records), with no relationships and no queries
/// beyond "sort by section". At that scale a file is less code, has no schema
/// migration to get wrong, and can be inspected with `cat` when something looks
/// off. SwiftData would earn its keep if this grew relationships or thousands of
/// records.
@Observable
final class ArticleStore {

    /// How many days the picker offers, today included.
    static let dayWindow = 5

    /// How long an unsaved article survives after the app first sees it.
    ///
    /// Tied to `dayWindow` rather than set independently: every story now
    /// reaches you through a day button, so a story older than the oldest button
    /// has nowhere left to be shown and is only taking up space.
    static let retention: TimeInterval = TimeInterval(dayWindow) * 24 * 60 * 60

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

    // MARK: - Days

    /// The day an article belongs to in the picker.
    ///
    /// `editionAt` — the feed the story arrived in — is what a day button means,
    /// so it is the key. Articles stored before that field existed fall back to
    /// `fetchedAt`, which in practice is the same morning.
    ///
    /// Deliberately *not* `publishedAt`: that is when the source story broke,
    /// which is routinely the evening before the edition that carried it, and
    /// bucketing on it would scatter one morning's edition across two buttons.
    static func day(of article: Article, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: article.editionAt ?? article.fetchedAt)
    }

    /// One day's stories, in reading order.
    func articles(on day: Date, calendar: Calendar = .current) -> [Article] {
        let start = calendar.startOfDay(for: day)
        return articles.filter { Self.day(of: $0, calendar: calendar) == start }
    }

    /// Today and the days behind it, newest first, always `dayWindow` long.
    ///
    /// A day with no edition still gets an entry: the picker shows a fixed run
    /// of days, and a morning the generator missed is worth seeing as a gap
    /// rather than being silently closed up.
    func recentDays(now: Date = .now, calendar: Calendar = .current) -> [EditionDay] {
        var byDay: [Date: [Article]] = [:]
        for article in articles {
            byDay[Self.day(of: article, calendar: calendar), default: []].append(article)
        }
        let today = calendar.startOfDay(for: now)
        return (0..<Self.dayWindow).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }
            return EditionDay(date: date, articles: byDay[date] ?? [])
        }
    }

    // MARK: - Mutating

    /// Folds a freshly fetched feed into the store.
    ///
    /// Articles already present keep their local `fetchedAt`, `savedAt` and
    /// `readAt` — a re-published story must never lose its heart, be offered
    /// back as unread, or have its purge clock reset. Genuinely new articles are
    /// inserted with `fetchedAt = now`.
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
                article.readAt = existing.readAt
            } else {
                article.fetchedAt = .now
                article.savedAt = nil
                article.readAt = nil
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

    /// Folds a past edition, fetched from the archive, into the store.
    ///
    /// The app only ever downloads `latest.json`, so a day it wasn't opened on
    /// leaves a hole the day picker has nothing to put in. This fills those
    /// holes from the published archive. Returns true if anything landed.
    ///
    /// Three deliberate differences from a live merge:
    ///
    /// - It leaves `feedGeneratedAt` and `feedConfig` alone. Those describe the
    ///   *current* edition and drive the staleness banner; backfilling Monday
    ///   must not convince the app that Monday is the latest news.
    /// - It only inserts ids the store has never seen. Editions overlap, and
    ///   re-stamping a story that today's feed already claimed would drag it
    ///   back onto an older day button and out of today's.
    /// - It dates `fetchedAt` to the edition rather than to now. `fetchedAt` is
    ///   the purge clock, so stamping it "now" would keep a four-day-old edition
    ///   alive for another five days, long after its button had scrolled out of
    ///   the window.
    @discardableResult
    func merge(archive feed: Feed) -> Bool {
        var byID = Dictionary(uniqueKeysWithValues: articles.map { ($0.id, $0) })
        var added = false

        for (position, incoming) in feed.articles.enumerated() where byID[incoming.id] == nil {
            var article = incoming
            article.fetchedAt = feed.generatedAt
            article.savedAt = nil
            article.readAt = nil
            article.editionAt = feed.generatedAt
            article.feedOrder = position
            byID[article.id] = article
            added = true
        }

        guard added else { return false }
        articles = Self.sorted(Array(byID.values))
        persist()
        return true
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

    /// Records that a story has been opened.
    ///
    /// Only the first visit counts — re-reading a story doesn't move the
    /// timestamp, and there is no way to mark one unread. The day picker asks
    /// "have you been through this day's news", and re-opening a story you've
    /// already read is not new information about that.
    func markRead(id: String, now: Date = .now) {
        guard let index = articles.firstIndex(where: { $0.id == id }),
              articles[index].readAt == nil else { return }
        articles[index].readAt = now
        persist()
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
