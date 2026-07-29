import Foundation

/// Where the app gets its news from.
///
/// `base` is the host serving the feed; `latest.json` sits at its root and
/// photos live under `/images/`. Set this once the Vercel project exists.
enum FeedEndpoint {
    #if DEBUG
    /// Debug builds read from a local server, so the feed and photos can be
    /// changed without deploying:
    ///
    ///     cd feed-data/public && python3 -m http.server 8765
    ///
    /// This works from the simulator, which shares the Mac's network. To run a
    /// Debug build on the phone, swap `localhost` for the Mac's LAN IP.
    static let base = URL(string: "http://localhost:8765/")!
    #else
    /// TODO: replace with the real Vercel URL once the feed-data project is deployed.
    static let base = URL(string: "https://example.invalid/")!
    #endif

    static var latest: URL { base.appending(path: "latest.json") }

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
}
