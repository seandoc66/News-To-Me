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
    ///
    /// The generator used to write whole seconds ("…06:00:00+02:00"), but
    /// editions from 26 Aug 2026 carried milliseconds ("…04:34:05.464Z")
    /// because `merge-sections.mjs` emitted `toISOString()` verbatim. Swift's
    /// `.iso8601` strategy — `ISO8601DateFormatter` with only
    /// `.withInternetDateTime` — rejects fractional seconds, which took the
    /// whole feed down on the phone: iOS 18's Foundation is strict about them,
    /// so decoding `generatedAt` threw and every story failed with it. Rather
    /// than depend on the generator's format, the decoder accepts both shapes;
    /// the generator is fixed separately to write whole seconds again.
    static var feed: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = Self.wholeSeconds.date(from: raw) { return date }
            if let date = Self.millisecondDate.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized ISO-8601 date: \(raw)"
            )
        }
        return d
    }

    /// Parses the whole-second shape the generator writes — "…06:00:00Z",
    /// "…06:00:00+02:00". This is the same grammar `.iso8601` uses, but as an
    /// explicit formatter so the custom strategy can fall through to the
    /// millisecond one below when the fraction is present.
    private static var wholeSeconds: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }

    /// Parses the millisecond shape the generator wrote between 26–31 Aug 2026
    /// ("…04:34:05.464Z"). `.withFractionalSeconds` expects exactly three
    /// digits, which is what `toISOString()` emits — a malformed fraction fails
    /// loudly here rather than being silently truncated.
    private static var millisecondDate: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
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
