import Foundation

/// One of the places a section is researched from.
///
/// `url` is optional because several entries in the brief are named pages rather
/// than feeds ("Concello de Lugo press page"), and the generator may not have a
/// canonical link for them.
struct ConfiguredSource: Codable, Hashable, Identifiable, Sendable {
    let name: String
    let url: URL?

    var id: String { name }

    /// Host without a leading "www.", shown under the name when there's a link.
    var displayHost: String? {
        guard let host = url?.host() else { return nil }
        return host.replacingOccurrences(of: "www.", with: "")
    }
}

/// How one section is published: how many stories to aim for, and where they
/// come from.
struct SectionConfig: Codable, Hashable, Sendable {
    let min: Int?
    let max: Int?
    let sources: [ConfiguredSource]

    /// "3–6 stories", or nil when the feed didn't state a target.
    var countDescription: String? {
        switch (min, max) {
        case let (lo?, hi?) where lo == hi: "\(lo) \(lo == 1 ? "story" : "stories")"
        case let (lo?, hi?): "\(lo)–\(hi) stories"
        case let (lo?, nil): "at least \(lo)"
        case let (nil, hi?): "up to \(hi)"
        case (nil, nil): nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case min, max, sources
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        min = try c.decodeIfPresent(Int.self, forKey: .min)
        max = try c.decodeIfPresent(Int.self, forKey: .max)
        sources = try c.decodeIfPresent([ConfiguredSource].self, forKey: .sources) ?? []
    }
}

/// The publishing rules the generator used for this edition.
///
/// Read-only by design: the pipeline that researches and writes the feed is the
/// one place these live, so the app surfaces them rather than owning them.
/// Changing them means editing the generator's brief, not tapping in the app.
struct FeedConfig: Codable, Sendable {
    /// Keyed by `NewsCategory.rawValue`. A plain `[String: _]` rather than a
    /// dictionary keyed by the enum: the latter's Codable conformance doesn't
    /// reliably round-trip as a JSON object, and an unrecognised section name
    /// here should be ignored rather than fail the whole decode.
    let sections: [String: SectionConfig]

    /// A section paired with the category it belongs to, ready for a `ForEach`.
    struct Resolved: Identifiable, Sendable {
        let category: NewsCategory
        let config: SectionConfig

        var id: NewsCategory { category }
    }

    /// Sections in reading order, skipping any this feed didn't describe.
    var orderedSections: [Resolved] {
        NewsCategory.allCases
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { category in
                sections[category.rawValue].map { Resolved(category: category, config: $0) }
            }
    }

    enum CodingKeys: String, CodingKey {
        case sections
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sections = try c.decodeIfPresent([String: SectionConfig].self, forKey: .sections) ?? [:]
    }
}
