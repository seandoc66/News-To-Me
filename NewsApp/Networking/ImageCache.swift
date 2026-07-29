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
actor ImageCache {
    static let shared = ImageCache()

    private let directory: URL
    private let session: URLSession
    /// Coalesces concurrent requests for the same URL into one download.
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    /// Thread-safe in its own right, but kept actor-isolated so it needs no
    /// Sendable gymnastics.
    private let memory: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 60
        return cache
    }()

    init(session: URLSession = .shared) {
        self.session = session
        let caches = URL.cachesDirectory.appending(path: "Images", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        self.directory = caches
    }

    /// Returns the image for `url`, from memory, then disk, then the network.
    /// `maxPixel` is the longest edge to decode to, in pixels.
    func image(for url: URL, maxPixel: CGFloat) async -> UIImage? {
        if let hit = memory.object(forKey: url as NSURL) { return hit }

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

        if let image { memory.setObject(image, forKey: url as NSURL) }
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
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack {
            fallback
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity.animation(.easeOut(duration: 0.25)))
            }
        }
        .clipped()
        .task(id: url) { await load() }
    }

    private var fallback: some View {
        LinearGradient(
            colors: [category.tint.opacity(0.55), category.tint.opacity(0.15)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            if didFail {
                Image(systemName: category.symbolName)
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private func load() async {
        guard let url else {
            didFail = true
            return
        }
        image = nil
        didFail = false
        let loaded = await ImageCache.shared.image(
            for: url,
            maxPixel: maxPointSize * displayScale
        )
        if let loaded {
            image = loaded
        } else {
            didFail = true
        }
    }
}
