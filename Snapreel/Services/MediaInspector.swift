import AVFoundation
import UIKit

/// Reads facts about a media file and makes thumbnails. Used when saving recordings and imports.
struct MediaInfo: Equatable {
    var duration: Double
    var pixelWidth: Int
    var pixelHeight: Int
    var fileSize: Int64
    var hasVideo: Bool
    var hasAudio: Bool
}

enum MediaInspector {
    static func inspect(_ url: URL) async throws -> MediaInfo {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        var width = 0, height = 0
        if let track = videoTracks.first {
            let size = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let rect = CGRect(origin: .zero, size: size).applying(transform)
            width = Int(abs(rect.width).rounded())
            height = Int(abs(rect.height).rounded())
        }
        return MediaInfo(duration: duration.seconds.isFinite ? duration.seconds : 0,
                         pixelWidth: width, pixelHeight: height,
                         fileSize: fileSize(url),
                         hasVideo: !videoTracks.isEmpty, hasAudio: !audioTracks.isEmpty)
    }

    static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
        return Int64(values?.fileSize ?? values?.totalFileAllocatedSize ?? 0)
    }

    /// A frame from the video, scaled so its longer side is at most `maxDimension` pixels.
    static func thumbnail(for url: URL, at seconds: Double = 0.5, maxDimension: CGFloat = 720) async throws -> UIImage {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        let (image, _) = try await generator.image(at: time)
        return UIImage(cgImage: image)
    }

    /// Writes a JPEG thumbnail and returns its file name inside `directory`.
    @discardableResult
    static func writeThumbnail(_ image: UIImage, named name: String, in directory: URL) throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.82) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let fileName = name.hasSuffix(".jpg") ? name : name + ".jpg"
        try data.write(to: directory.appendingPathComponent(fileName), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return fileName
    }
}

/// Free space on the device, for out-of-space checks and Settings › Storage.
enum DiskSpace {
    /// Bytes available for important data (what iOS would free up for a user-initiated save).
    static var available: Int64 {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    static var total: Int64 {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey])
        return Int64(values?.volumeTotalCapacity ?? 0)
    }

    /// Below this, Snapreel warns that new recordings may not save (1 GB).
    static let lowThreshold: Int64 = 1_000_000_000

    /// True when `bytes` more would still leave a small safety margin (200 MB).
    static func hasRoom(for bytes: Int64) -> Bool {
        available - bytes > 200_000_000
    }

    /// Whether an error means the disk is full.
    static func isOutOfSpace(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError { return true }
        if ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOSPC) { return true }
        if ns.domain == AVFoundationErrorDomain && ns.code == AVError.diskFull.rawValue { return true }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error { return isOutOfSpace(underlying) }
        return false
    }
}
