import CardCore
import CoreGraphics
import Foundation
import ImageIO
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

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

    private struct AssetKey: Hashable {
        let name: String
        let maxPixelSize: Int
    }

    private var assetCache: [AssetKey: CGImage] = [:]
    private var assetInFlight: [AssetKey: Task<CGImage, any Error>] = [:]

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

    /// Returns a downsampled copy of an image of the main asset catalog.
    /// Decoding a 2-megapixel JPEG on the main actor at first draw is a
    /// visible hitch; this does it here, once, at the size the card needs.
    public func image(forAsset name: String, maxPixelSize: Int = 1024) async throws -> CGImage {
        let key = AssetKey(name: name, maxPixelSize: maxPixelSize)
        if let cached = assetCache[key] { return cached }
        if let task = assetInFlight[key] { return try await task.value }
        let task = Task { try await Self.decodeAsset(named: name, maxPixelSize: maxPixelSize) }
        assetInFlight[key] = task
        defer { assetInFlight[key] = nil }
        let image = try await task.value
        assetCache[key] = image
        return image
    }

    /// Decodes a list of assets ahead of time (app launch, before a reveal).
    public func prewarm(assets names: [String], maxPixelSize: Int = 1024) async {
        await withTaskGroup(of: Void.self) { group in
            for name in names {
                group.addTask { _ = try? await self.image(forAsset: name, maxPixelSize: maxPixelSize) }
            }
        }
    }

    /// Drops every cached image (memory warning, for instance).
    public func purge() {
        cache.removeAll()
        assetCache.removeAll()
    }

    @concurrent
    private static func decodeAsset(named name: String, maxPixelSize: Int) async throws -> CGImage {
        #if canImport(UIKit)
        guard let source = UIImage(named: name, in: .main, with: nil)?.cgImage else { throw Failure.unreadable }
        #else
        guard let source = NSImage(named: name)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw Failure.unreadable
        }
        #endif
        try Task.checkCancellation()
        let longest = max(source.width, source.height)
        let scale = min(1, Double(maxPixelSize) / Double(longest))
        let width = max(Int(Double(source.width) * scale), 1)
        let height = max(Int(Double(source.height) * scale), 1)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw Failure.undecodable }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw Failure.undecodable }
        return image
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
