import Foundation

/// Where the app gets its news from.
///
/// `base` is the host serving the feed; `latest.json` sits at its root and
/// photos live under `/images/`.
enum FeedEndpoint {
    #if DEBUG
    /// Debug builds read from a local server, so the feed and photos can be
    /// changed without deploying:
    ///
    ///     cd docs && python3 -m http.server 8765
    ///
    /// This works from the simulator, which shares the Mac's network. To run a
    /// Debug build on the phone, swap `localhost` for the Mac's LAN IP.
    static let base = URL(string: "http://localhost:8765/")!
    #else
    static let base = URL(string: "https://seandoc66.github.io/News-To-Me/")!
    #endif

    static var latest: URL { base.appending(path: "latest.json") }

    /// A past edition, named by its own calendar day: `/archive/2026-08-03.json`.
    static func archive(for day: Date) -> URL {
        base.appending(path: "archive/\(archiveDay.string(from: day)).json")
    }

    /// Formats in the phone's own timezone, not UTC. The generator names archive
    /// files for the local day it published on, and an edition stamped 06:00
    /// Madrid time is still the previous day in UTC — formatting in UTC would
    /// ask for yesterday's file every single morning.
    private static let archiveDay: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// True while still pointing at the placeholder, so the UI can explain why
    /// there's nothing new rather than showing a bare network error.
    static var isConfigured: Bool { base.host() != "example.invalid" }
}

enum FeedError: LocalizedError {
    case notConfigured
    case badStatus(Int)
    case decoding(any Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "No feed URL set yet — showing the stories bundled with the app."
        case .badStatus(let code):
            "The news server returned an error (\(code))."
        case .decoding:
            "Today's feed couldn't be read."
        }
    }
}

struct FeedService: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetches and decodes `latest.json`.
    func fetchLatest() async throws -> Feed {
        guard FeedEndpoint.isConfigured else { throw FeedError.notConfigured }

        var request = URLRequest(url: FeedEndpoint.latest)
        // The feed changes once a day; skip any stale cached copy so a morning
        // refresh always gets today's batch.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FeedError.badStatus(http.statusCode)
        }

        do {
            return try JSONDecoder.feed.decode(Feed.self, from: data)
        } catch {
            throw FeedError.decoding(error)
        }
    }

    /// Fetches one past edition from the archive, for a day the app didn't see
    /// live.
    ///
    /// Returns nil for a day that was never published. The generator refuses to
    /// publish a batch it can't fill, so a 404 here is an ordinary quiet morning
    /// rather than a fault worth surfacing.
    ///
    /// Unlike `fetchLatest` this leaves the URL cache alone: an archived edition
    /// never changes once written, so a cached copy is as good as the original.
    func fetchArchive(for day: Date) async throws -> Feed? {
        guard FeedEndpoint.isConfigured else { throw FeedError.notConfigured }

        var request = URLRequest(url: FeedEndpoint.archive(for: day))
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 { return nil }
            guard (200..<300).contains(http.statusCode) else {
                throw FeedError.badStatus(http.statusCode)
            }
        }

        do {
            return try JSONDecoder.feed.decode(Feed.self, from: data)
        } catch {
            throw FeedError.decoding(error)
        }
    }
}
