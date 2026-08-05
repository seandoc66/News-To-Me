import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Disk-and-memory image cache with downsampling.
///
/// Two reasons this exists instead of `AsyncImage`:
///
/// 1. `AsyncImage` doesn't cache. Paging back to a previous card would refetch
///    the photo over the network every time.
/// 2. A saved article needs its photo to still be there months later, after the
///    source file has been rotated off the server. Once cached on disk, it is.
///
/// Images are also downsampled at decode time. A full-resolution JPEG rotated in
/// 3D during the fold transition is the most expensive thing this app could
/// possibly do; decoding straight to display size avoids it.
/// The decoded-image memory cache, deliberately **outside** the actor.
///
/// A view has to be able to ask "do you already have this one?" while building
/// its body, with no `await`. Hopping to an actor costs at least a frame, and a
/// frame is exactly long enough to show the fallback gradient — which is what
/// made the photo flicker at both ends of every page turn, since a turn builds
/// four fresh `CachedImage`s and tears them down again.
///
/// `NSCache` is thread-safe in its own right; the actor isolation was only ever
/// protecting `inFlight`.
/// `nonisolated` throughout: the whole point is to be callable from inside the
/// `ImageCache` actor *and* from a view's `body` without an `await` from either.
nonisolated final class ImageMemoryCache: @unchecked Sendable {
    static let shared = ImageMemoryCache()

    private let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 60
        return cache
    }()

    func image(for url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }
    func store(_ image: UIImage, for url: URL) { cache.setObject(image, forKey: url as NSURL) }
}

actor ImageCache {
    static let shared = ImageCache()

    private let directory: URL
    private let session: URLSession
    /// Coalesces concurrent requests for the same URL into one download.
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    init(session: URLSession = .shared) {
        self.session = session
        let caches = URL.cachesDirectory.appending(path: "Images", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        self.directory = caches
    }

    /// Returns the image for `url`, from memory, then disk, then the network.
    /// `maxPixel` is the longest edge to decode to, in pixels.
    func image(for url: URL, maxPixel: CGFloat) async -> UIImage? {
        if let hit = ImageMemoryCache.shared.image(for: url) { return hit }

        if let existing = inFlight[url] { return await existing.value }

        let task = Task<UIImage?, Never> { [directory, session] in
            let file = Self.cacheFile(for: url, in: directory)

            // Disk
            if let data = try? Data(contentsOf: file),
               let image = Self.downsample(data, maxPixel: maxPixel) {
                return image
            }

            // Network
            guard let data = try? await session.data(from: url).0 else { return nil }
            // Keep the original bytes so a later, larger decode is still possible.
            try? data.write(to: file, options: .atomic)
            return Self.downsample(data, maxPixel: maxPixel)
        }

        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil

        if let image { ImageMemoryCache.shared.store(image, for: url) }
        return image
    }

    /// Warms the cache for upcoming cards so the photo is ready before the card
    /// is on screen.
    func prefetch(_ urls: [URL], maxPixel: CGFloat) async {
        for url in urls {
            _ = await image(for: url, maxPixel: maxPixel)
        }
    }

    /// Removes cached files for articles the app no longer holds, leaving saved
    /// articles' photos alone.
    func evict(keeping keep: Set<URL>) {
        let keepNames = Set(keep.map { Self.cacheKey(for: $0) })
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return }
        for file in files where !keepNames.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: - Helpers

    private static func cacheKey(for url: URL) -> String {
        // Stable, filesystem-safe name derived from the full URL.
        let raw = url.absoluteString
        var hash: UInt64 = 5381
        for byte in raw.utf8 {
            hash = (hash << 5) &+ hash &+ UInt64(byte)
        }
        let ext = url.pathExtension.isEmpty ? "img" : url.pathExtension
        return "\(String(hash, radix: 36)).\(ext)"
    }

    private static func cacheFile(for url: URL, in directory: URL) -> URL {
        directory.appending(path: cacheKey(for: url))
    }

    /// Decodes `data` straight to `maxPixel` on the long edge using ImageIO, so
    /// a 4000px press photo never becomes a 4000px bitmap in memory.
    private static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixel, 1),
        ] as [CFString: Any] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - View

/// Drop-in replacement for `AsyncImage` that goes through `ImageCache` and
/// falls back to a category-tinted gradient while loading or on failure.
struct CachedImage: View {
    let url: URL?
    let category: NewsCategory
    /// Longest edge to decode to, in points; multiplied by the screen scale.
    var maxPointSize: CGFloat = 1200

    @State private var image: UIImage?
    @State private var didFail = false
    /// Which URL `image` and `didFail` actually describe. Everything below keys
    /// off this: state left over from another story is state about another
    /// story, and is never drawn.
    @State private var loadedURL: URL?
    @Environment(\.displayScale) private var displayScale

    /// Spelled out because the synthesised memberwise one inherits the `private`
    /// of the state above and so can't be called from the views.
    init(url: URL?, category: NewsCategory, maxPointSize: CGFloat = 1200) {
        self.url = url
        self.category = category
        self.maxPointSize = maxPointSize
    }

    /// The photo to draw right now, which always belongs to `url`.
    ///
    /// SwiftUI hands this view's `@State` on to whatever takes its place — and
    /// at the end of a page turn the settled card takes the place of the turning
    /// halves, so it inherits the *previous* story's decoded photo. Drawing
    /// `image` directly showed that photo under the new story's headline until
    /// `load()` had hopped to the actor and come back: one frame of the wrong
    /// picture at the end of every turn.
    ///
    /// Reading the memory cache here instead costs a dictionary lookup and makes
    /// the wrong photo unrepresentable. A miss draws the fallback gradient,
    /// which is honest — this view has no photo for this story yet.
    private var shown: UIImage? {
        if loadedURL == url { return image }
        return url.flatMap { ImageMemoryCache.shared.image(for: $0) }
    }

    var body: some View {
        // `Color.clear` accepts exactly the size it's offered, so the overlaid
        // image fills that frame and the overflow from `scaledToFill` gets
        // clipped to it. Putting the image directly in a ZStack instead lets it
        // report an oversized ideal height and push the layout around.
        Color.clear
            .overlay {
                ZStack {
                    fallback
                    if let shown {
                        Image(uiImage: shown)
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity.animation(.easeOut(duration: 0.25)))
                    }
                }
            }
            .clipped()
            .contentShape(.rect)
            .task(id: url) { await load() }
    }

    private var fallback: some View {
        LinearGradient(
            colors: [category.tint.opacity(0.55), category.tint.opacity(0.15)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            // Only once *this* story's photo has been tried and missed.
            if didFail, loadedURL == url {
                Image(systemName: category.symbolName)
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private func load() async {
        guard let url else {
            image = nil
            didFail = true
            loadedURL = nil
            return
        }
        // Already holding the right photo, from an earlier run of this task.
        // Clearing and refetching here unconditionally is what made a settled
        // card flash the fallback gradient when the turn ended.
        if loadedURL == url, image != nil { return }

        // Already decoded: take it without hopping to the actor, which costs a
        // frame. This is the usual case for a card built during a turn.
        if let hit = ImageMemoryCache.shared.image(for: url) {
            image = hit
            didFail = false
            loadedURL = url
            return
        }

        let loaded = await ImageCache.shared.image(
            for: url,
            maxPixel: maxPointSize * displayScale
        )
        image = loaded
        didFail = loaded == nil
        loadedURL = url
    }
}
