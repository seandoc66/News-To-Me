import Foundation

/// A link to one of the places the story was researched from.
struct ArticleSource: Codable, Hashable, Identifiable, Sendable {
    let name: String
    let url: URL

    var id: URL { url }

    /// Host without a leading "www.", for compact display under the name.
    var displayHost: String {
        (url.host() ?? url.absoluteString)
            .replacingOccurrences(of: "www.", with: "")
    }
}

/// One story. This is both the wire format (decoded from the feed JSON) and the
/// on-disk format, with two extra locally-owned fields — `fetchedAt` and
/// `savedAt` — that the server never sends.
struct Article: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let category: NewsCategory
    let headline: String
    let subtitle: String
    let body: String
    /// Either an absolute URL or a path relative to the feed host
    /// (e.g. "/images/2026-07-28-tech-001.jpg"). Resolve with `imageURL(base:)`.
    ///
    /// Optional: a story whose photo couldn't be sourced still publishes, and
    /// renders with the category-tinted fallback instead. Requiring a photo
    /// meant one missing image blocked a whole edition.
    let imageURLString: String?
    let sources: [ArticleSource]
    let publishedAt: Date

    /// When this app first saw the article. Drives the 7-day purge, so it is
    /// deliberately local rather than trusting the server's dates.
    var fetchedAt: Date
    /// Non-nil once hearted. Saved articles are exempt from the purge.
    var savedAt: Date?

    /// The edition this article arrived in — the `generatedAt` of that feed —
    /// and its slot within it.
    ///
    /// Together these preserve the generator's running order. The feed does the
    /// editorial ranking ("most significant story first"), and it isn't
    /// recoverable from the article itself: `publishedAt` is when the source
    /// story broke, not how much it matters. Both optional so articles stored
    /// before these fields existed still decode.
    var editionAt: Date?
    var feedOrder: Int?

    var isSaved: Bool { savedAt != nil }

    enum CodingKeys: String, CodingKey {
        case id, category, headline, subtitle, body
        case imageURLString = "imageURL"
        case sources, publishedAt, fetchedAt, savedAt, editionAt, feedOrder
    }

    init(
        id: String,
        category: NewsCategory,
        headline: String,
        subtitle: String,
        body: String,
        imageURLString: String? = nil,
        sources: [ArticleSource],
        publishedAt: Date,
        fetchedAt: Date = .now,
        savedAt: Date? = nil,
        editionAt: Date? = nil,
        feedOrder: Int? = nil
    ) {
        self.id = id
        self.category = category
        self.headline = headline
        self.subtitle = subtitle
        self.body = body
        self.imageURLString = imageURLString
        self.sources = sources
        self.publishedAt = publishedAt
        self.fetchedAt = fetchedAt
        self.savedAt = savedAt
        self.editionAt = editionAt
        self.feedOrder = feedOrder
    }

    /// `fetchedAt`/`savedAt` are absent from the server payload, so they get
    /// sensible defaults when decoding a fresh feed and are preserved when
    /// decoding our own on-disk store.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        category = try c.decode(NewsCategory.self, forKey: .category)
        headline = try c.decode(String.self, forKey: .headline)
        subtitle = try c.decode(String.self, forKey: .subtitle)
        body = try c.decode(String.self, forKey: .body)
        // Absent, null, or empty all mean "no photo" — the generator writes an
        // empty string when a photo couldn't be fetched.
        let rawImage = try c.decodeIfPresent(String.self, forKey: .imageURLString)
        imageURLString = (rawImage?.isEmpty ?? true) ? nil : rawImage
        sources = try c.decodeIfPresent([ArticleSource].self, forKey: .sources) ?? []
        publishedAt = try c.decode(Date.self, forKey: .publishedAt)
        fetchedAt = try c.decodeIfPresent(Date.self, forKey: .fetchedAt) ?? .now
        savedAt = try c.decodeIfPresent(Date.self, forKey: .savedAt)
        editionAt = try c.decodeIfPresent(Date.self, forKey: .editionAt)
        feedOrder = try c.decodeIfPresent(Int.self, forKey: .feedOrder)
    }

    /// Resolves `imageURLString` against the host serving the feed, so the
    /// generator can emit either relative paths or absolute URLs.
    ///
    /// The feed writes photo paths host-absolute ("/images/<id>.jpg"), but the
    /// feed itself can live under a subpath — GitHub Pages serves this repo from
    /// `/News-To-Me/`. `URL(string:relativeTo:)` reads a leading slash as
    /// "from the host root" and throws that subpath away, so the path is appended
    /// to the base instead.
    /// Returns nil when the story has no photo, which callers render as the
    /// category-tinted fallback.
    func imageURL(base: URL) -> URL? {
        guard let imageURLString else { return nil }
        if imageURLString.hasPrefix("http://") || imageURLString.hasPrefix("https://") {
            return URL(string: imageURLString)
        }
        let path = imageURLString.trimmingPrefix("/")
        guard !path.isEmpty else { return nil }
        return base.appending(path: path)
    }
}
