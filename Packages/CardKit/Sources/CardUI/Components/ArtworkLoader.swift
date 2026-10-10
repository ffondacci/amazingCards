import CardCore
import CoreGraphics
import Foundation
import ImageIO

/// Decodes and caches card artwork off the main actor.
///
/// Images are downsampled with ImageIO to `maxPixelSize` so a 4000 px
/// painting never lands in memory at full size. Concurrent requests for the
/// same key share one decode task; cancelling one waiter does not cancel the
/// decode, which other waiters may still need.
public actor ArtworkLoader {
    public static let shared = ArtworkLoader()

    public enum Failure: Error, Sendable {
        case undecodable
        case unreadable
    }

    private struct Key: Hashable {
        let url: URL
        let maxPixelSize: Int
    }

    private var cache: [Key: CGImage] = [:]
    private var inFlight: [Key: Task<CGImage, any Error>] = [:]
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Returns a decoded, downsampled image for the URL (file or remote).
    public func image(for url: URL, maxPixelSize: Int = 1024) async throws -> CGImage {
        let key = Key(url: url, maxPixelSize: maxPixelSize)
        if let cached = cache[key] { return cached }
        if let task = inFlight[key] { return try await task.value }

        let session = self.session
        let task = Task { try await Self.decode(url: url, maxPixelSize: maxPixelSize, session: session) }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        let image = try await task.value
        cache[key] = image
        return image
    }

    /// Drops every cached image (memory warning, for instance).
    public func purge() {
        cache.removeAll()
    }

    @concurrent
    private static func decode(url: URL, maxPixelSize: Int, session: URLSession) async throws -> CGImage {
        let data: Data
        if url.isFileURL {
            guard let fileData = try? Data(contentsOf: url) else { throw Failure.unreadable }
            data = fileData
        } else {
            (data, _) = try await session.data(from: url)
        }
        try Task.checkCancellation()
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            throw Failure.undecodable
        }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            throw Failure.undecodable
        }
        return image
    }
}
