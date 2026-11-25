import AVFoundation
import XCTest
@testable import Snapreel

/// How long preparing takes and how many bytes it makes, before (build 47's exporter) and now. Runs only with
/// RUN_BENCHMARKS=1 (CI); the simulator encodes on the Mac's hardware, so compare the two columns, not with a phone.
final class WebCopyBenchmarks: XCTestCase {
    func testBenchmarks() async throws {
        guard ProcessInfo.processInfo.environment["RUN_BENCHMARKS"] == "1" else { throw XCTSkip("RUN_BENCHMARKS isn't set") }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("bench-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var lines = ["recording | plan | source MB | before: s, MB | now: s, MB | first bytes ready after s"]
        // The phone's screen recordings come to 1.6 to 2.8 Mbit/s; the camera's to 10.
        let recordings: [(String, Double, Maker, Bool)] = [
            ("screen 1 min", 60, Maker(width: 886, height: 1_918, seconds: 60, bitRate: 2_800_000, frames: .uneven, soundSeconds: 55), true),
            ("screen 5 min", 300, Maker(width: 886, height: 1_918, seconds: 300, bitRate: 2_800_000, frames: .uneven, soundSeconds: 290), true),
            ("screen 9 min", 540, Maker(width: 886, height: 1_918, seconds: 540, bitRate: 2_800_000, frames: .uneven, soundSeconds: 437), true),
            ("camera 1 min", 60, Maker(width: 1_080, height: 1_920, seconds: 60, bitRate: 10_000_000, frames: .even(30), soundSeconds: 60, busy: true), false),
        ]
        for (name, seconds, maker, isScreen) in recordings {
            let source = folder.appendingPathComponent("\(name).mov")
            try await maker.write(to: source)
            for (plan, long) in [("Pro 1080p", 1_920), ("Free 720p", 1_280)] {
                if plan == "Free 720p", seconds > 300 { continue }
                let old = folder.appendingPathComponent("old.mp4")
                var clock = Date()
                try await Self.build47(source, to: old, maxLongSide: long)
                let oldTime = Date().timeIntervalSince(clock)
                let job = folder.appendingPathComponent("job-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: job, withIntermediateDirectories: true)
                clock = Date()
                let first = FirstBytes()
                try await WebPreparer(job: .init(source: source, folder: job, maxLongSide: long, isScreen: isScreen, isAudio: false,
                                                 title: name, duration: seconds)) { update in
                    if case .video(let state) = update, state.finalBytes > state.headerEnd, first.at == nil { first.at = Date() }
                }.run()
                let newTime = Date().timeIntervalSince(clock)
                let video = job.appendingPathComponent("video.mp4")
                let firstBytes = first.at.map { String(format: "%.1f", $0.timeIntervalSince(clock)) } ?? "-"
                lines.append(String(format: "%@ | %@ | %.1f | %.1f s, %.1f | %.1f s, %.1f | %@", name, plan, mb(source), oldTime, mb(old), newTime, mb(video), firstBytes))
                XCTAssertNil(WebPreparer.lastFallback)
                try? FileManager.default.removeItem(at: job)
                try? FileManager.default.removeItem(at: old)
            }
            try? FileManager.default.removeItem(at: source)
        }
        let report = lines.joined(separator: "\n")
        print("BENCHMARKS\n\(report)")
        if let out = ProcessInfo.processInfo.environment["OUT_DIR"], !out.isEmpty {
            try report.write(toFile: out + "/benchmarks.txt", atomically: true, encoding: .utf8)
        }
    }

    @MainActor private final class FirstBytes { var at: Date? }

    private func mb(_ url: URL) -> Double { Double(MediaInspector.fileSize(url)) / 1_000_000 }

    /// Build 47's `WebExport.exportVideo`, as it was.
    private static func build47(_ source: URL, to destination: URL, maxLongSide: Int) async throws {
        try? FileManager.default.removeItem(at: destination)
        let asset = AVURLAsset(url: source)
        let track = try await asset.loadTracks(withMediaType: .video)[0]
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let duration = try await asset.load(.duration)
        let shown = CGRect(origin: .zero, size: natural).applying(transform).size
        let width = abs(shown.width), height = abs(shown.height)
        if max(width, height) <= CGFloat(maxLongSide) + 1 {
            try await run(asset, preset: AVAssetExportPresetPassthrough, to: destination)
            return
        }
        func even(_ value: CGFloat) -> CGFloat { max(2, (value / 2).rounded() * 2) }
        let scale = min(1, CGFloat(maxLongSide) / max(width, height, 1))
        let composition = AVMutableVideoComposition()
        composition.renderSize = CGSize(width: even(width * scale), height: even(height * scale))
        composition.frameDuration = CMTime(value: 1, timescale: 30)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(transform.concatenating(CGAffineTransform(scaleX: scale, y: scale)), at: .zero)
        instruction.layerInstructions = [layer]
        composition.instructions = [instruction]
        try await run(asset, preset: AVAssetExportPresetHighestQuality, to: destination, composition: composition)
    }

    private static func run(_ asset: AVAsset, preset: String, to destination: URL, composition: AVVideoComposition? = nil) async throws {
        let session = AVAssetExportSession(asset: asset, presetName: preset)!
        session.outputURL = destination
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        session.fileLengthLimit = CloudConfig.maxFileBytes
        if let composition { session.videoComposition = composition }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { done.resume() }
        }
        XCTAssertEqual(session.status, .completed, "\(String(describing: session.error))")
    }
}
