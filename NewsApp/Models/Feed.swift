import Foundation

/// The top-level object in `latest.json`.
struct Feed: Codable, Sendable {
    let generatedAt: Date
    let articles: [Article]
    /// The publishing rules behind this edition. Optional: feeds published
    /// before the config block existed simply don't carry one.
    let config: FeedConfig?
}

extension JSONDecoder {
    /// Decoder configured for the feed contract: ISO-8601 timestamps, which is
    /// what the generator emits and what we write back to disk.
    static var feed: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

extension JSONEncoder {
    static var feed: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}
