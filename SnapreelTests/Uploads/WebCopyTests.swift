import AVFoundation
import UIKit
import XCTest
@testable import Snapreel

/// Makes recordings of the kinds Snapreel makes, prepares them for the web, and checks the result as a player would
/// see it. The files are kept as attachments, to be checked again with ffprobe and Chrome.
final class WebCopyTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("webcopy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        WebPreparer.lastFallback = nil
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: - Helpers

    struct Seen {
        var copyIDs: [String] = []
        var fractions: [Double] = []
        /// What was reported final, with the bytes as they were then.
        var final: [(end: Int64, header: Int64, tail: Data)] = []
        var files: [UploadJob.Part.Kind: Int64] = [:]
        var done: (copyID: String, size: Int64, headerEnd: Int64)?
    }

    @MainActor private final class Box {
        var seen = Seen()
        var task: Task<Void, Error>?
    }

    /// Runs the preparer; `stopAfter` cancels it once that many stretches were reported.
    private func prepare(_ source: URL, screen: Bool = true, audio: Bool = false, long: Int = 1_920, duration: Double,
                         into name: String = "job", stopAfter: Int? = nil) async throws -> (Seen, URL) {
        let jobFolder = folder.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: jobFolder, withIntermediateDirectories: true)
        let job = WebPreparer.Job(source: source, folder: jobFolder, maxLongSide: long, isScreen: screen, isAudio: audio,
                                  title: "Test recording", duration: duration)
        let box = await Box()
        let video = jobFolder.appendingPathComponent("video.mp4")
        let preparer = WebPreparer(job: job) { update in
            switch update {
            case .file(let kind, let size): box.seen.files[kind] = size
            case .video(let state):
                if box.seen.copyIDs.last != state.copyID { box.seen.copyIDs.append(state.copyID) }
                box.seen.fractions.append(state.fraction)
                if state.finalBytes > 0 {
                    // The last bytes reported final, as they are right now.
                    let from = max(state.headerEnd, state.finalBytes - 65_536)
                    let handle = try? FileHandle(forReadingFrom: video)
                    try? handle?.seek(toOffset: UInt64(from))
                    let tail = (try? handle?.read(upToCount: Int(state.finalBytes - from))) ?? Data()
                    box.seen.final.append((state.finalBytes, state.headerEnd, tail))
                    if let stopAfter, box.seen.final.count >= stopAfter { box.task?.cancel() }
                }
            case .videoDone(let copyID, let size, let headerEnd): box.seen.done = (copyID, size, headerEnd)
            }
        }
        let task = Task { try await preparer.run() }
        await MainActor.run { box.task = task }
        do {
            try await task.value
        } catch is CancellationError where stopAfter != nil {
        }
        return (await box.seen, video)
    }

    /// Kept with the test's results (CI exports them), to be checked again with ffprobe and Chrome.
    private func keep(_ url: URL, as name: String) {
        guard let data = try? Data(contentsOf: url) else { return }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.mpeg-4")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The top-level boxes, in order.
    private func boxes(_ url: URL) throws -> [(type: String, start: Int64, size: Int64)] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let length = MediaInspector.fileSize(url)
        var found: [(String, Int64, Int64)] = []
        var at: Int64 = 0
        while at + 8 <= length {
            try handle.seek(toOffset: UInt64(at))
            let head = [UInt8](try handle.read(upToCount: 16) ?? Data())
            guard head.count >= 8 else { break }
            var size = Int64(head[0]) << 24 | Int64(head[1]) << 16 | Int64(head[2]) << 8 | Int64(head[3])
            let type = String(decoding: head[4..<8], as: UTF8.self)
            if size == 1, head.count == 16 { size = head[8..<16].reduce(Int64(0)) { $0 << 8 | Int64($1) } }
            found.append((type, at, size))
            guard size >= 8 else { break }
            at += size
        }
        XCTAssertEqual(at, length, "the boxes fill the file")
        return found
    }

    /// Frame times, in seconds.
    private func frameTimes(_ url: URL) async throws -> [Double] {
        let asset = AVURLAsset(url: url)
        let track = try await asset.loadTracks(withMediaType: .video)[0]
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var times: [Double] = []
        while let buffer = output.copyNextSampleBuffer() {
            if CMSampleBufferGetImageBuffer(buffer) != nil { times.append(CMSampleBufferGetPresentationTimeStamp(buffer).seconds) }
        }
        XCTAssertEqual(reader.status, .completed, "\(String(describing: reader.error))")
        return times
    }

    /// The time of the first bright frame and of the first loud sample.
    private func flashAndBeep(_ url: URL) async throws -> (flash: Double, beep: Double?) {
        let asset = AVURLAsset(url: url)
        let video = try await asset.loadTracks(withMediaType: .video)[0]
        let reader = try AVAssetReader(asset: asset)
        let frames = AVAssetReaderTrackOutput(track: video, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
        reader.add(frames)
        XCTAssertTrue(reader.startReading())
        var flash = -1.0
        while let buffer = frames.copyNextSampleBuffer() {
            guard let image = CMSampleBufferGetImageBuffer(buffer) else { continue }
            CVPixelBufferLockBaseAddress(image, .readOnly)
            let base = CVPixelBufferGetBaseAddressOfPlane(image, 0)!.assumingMemoryBound(to: UInt8.self)
            let bright = base[CVPixelBufferGetBytesPerRowOfPlane(image, 0) * (CVPixelBufferGetHeight(image) / 2) + CVPixelBufferGetWidth(image) / 2]
            CVPixelBufferUnlockBaseAddress(image, .readOnly)
            if bright > 200, flash < 0 { flash = CMSampleBufferGetPresentationTimeStamp(buffer).seconds }
        }
        guard let sound = try await asset.loadTracks(withMediaType: .audio).first else { return (flash, nil) }
        let audioReader = try AVAssetReader(asset: asset)
        let samples = AVAssetReaderTrackOutput(track: sound, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false, AVNumberOfChannelsKey: 1, AVSampleRateKey: 44_100,
        ])
        audioReader.add(samples)
        XCTAssertTrue(audioReader.startReading())
        var beep = -1.0
        while let buffer = samples.copyNextSampleBuffer() {
            guard beep < 0, let block = CMSampleBufferGetDataBuffer(buffer), let data = try? block.dataBytes() else { continue }
            let start = CMSampleBufferGetOutputPresentationTimeStamp(buffer).seconds
            data.withUnsafeBytes { raw in
                for (index, value) in raw.bindMemory(to: Int16.self).enumerated() where abs(Int(value)) > 6_000 {
                    beep = start + Double(index) / 44_100
                    break
                }
            }
        }
        return (flash, beep)
    }

    /// Checks everything a player needs.
    private func check(_ video: URL, _ seen: Seen, source: URL, keepAs name: String, file: StaticString = #filePath, line: UInt = #line) async throws {
        keep(video, as: name)
        XCTAssertNil(WebPreparer.lastFallback, file: file, line: line)
        let done = try XCTUnwrap(seen.done, file: file, line: line)
        XCTAssertEqual(done.size, MediaInspector.fileSize(video), file: file, line: line)
        // The index first, the media last, the room exactly filled.
        let parts = try boxes(video)
        XCTAssertEqual(parts.first?.type, "ftyp", file: file, line: line)
        XCTAssertEqual(parts.dropFirst().first?.type, "moov", file: file, line: line)
        XCTAssertEqual(parts.last?.type, "mdat", file: file, line: line)
        XCTAssertEqual((parts.last?.start ?? 0) + 16, done.headerEnd, file: file, line: line)
        // What was reported final didn't change afterwards.
        let handle = try FileHandle(forReadingFrom: video)
        for state in seen.final {
            try handle.seek(toOffset: UInt64(max(state.header, state.end - 65_536)))
            XCTAssertEqual(try handle.read(upToCount: state.tail.count), state.tail, "bytes before \(state.end) changed", file: file, line: line)
        }
        XCTAssertEqual(seen.final.map(\.end), seen.final.map(\.end).sorted(), file: file, line: line)
        XCTAssertEqual(seen.fractions, seen.fractions.sorted(), file: file, line: line)
        let asset = AVURLAsset(url: video), original = AVURLAsset(url: source)
        let playable = try await asset.load(.isPlayable)
        XCTAssertTrue(playable, file: file, line: line)
        let length = try await asset.load(.duration).seconds, wanted = try await original.load(.duration).seconds
        XCTAssertEqual(length, wanted, accuracy: 0.15, file: file, line: line)
        XCTAssertGreaterThan(seen.files[.poster] ?? 0, 0, file: file, line: line)
        XCTAssertGreaterThan(seen.files[.preview] ?? 0, 0, file: file, line: line)
    }

    // MARK: - Copying

    func testScreenRecordingIsCopiedWithItsUnevenFramesAndShortSound() async throws {
        let source = folder.appendingPathComponent("screen.mov")
        try await Maker(width: 886, height: 1_918, seconds: 24, bitRate: 1_800_000, frames: .uneven, soundSeconds: 17).write(to: source)
        let (seen, video) = try await prepare(source, duration: 24)
        try await check(video, seen, source: source, keepAs: "copy-screen.mp4")
        let before = try await frameTimes(source), after = try await frameTimes(video)
        XCTAssertEqual(before.count, after.count)
        for (a, b) in zip(before, after) { XCTAssertEqual(a - before[0], b, accuracy: 0.002) }
        let audio = try await AVURLAsset(url: video).loadTracks(withMediaType: .audio)
        XCTAssertEqual(audio.count, 1)
        let sound = try await audio[0].load(.timeRange)
        XCTAssertEqual(sound.duration.seconds, 17, accuracy: 0.1)
        let (flash, beep) = try await flashAndBeep(video)
        XCTAssertEqual(flash, 2, accuracy: 0.05)
        XCTAssertEqual(try XCTUnwrap(beep), 2, accuracy: 0.05)
        // Copying costs next to nothing: the same bytes plus the index.
        XCTAssertLessThan(Double(MediaInspector.fileSize(video)), Double(MediaInspector.fileSize(source)) * 1.08)
    }

    func testReorderedFramesAreCopiedInOrder() async throws {
        let source = folder.appendingPathComponent("b-frames.mov")
        try await Maker(width: 640, height: 360, seconds: 12, bitRate: 900_000, frames: .even(30), soundSeconds: 12, reorders: true).write(to: source)
        let (seen, video) = try await prepare(source, screen: false, duration: 12)
        try await check(video, seen, source: source, keepAs: "copy-b-frames.mp4")
        let before = try await frameTimes(source), after = try await frameTimes(video)
        XCTAssertEqual(before.count, after.count)
        for (a, b) in zip(before, after) { XCTAssertEqual(a - before[0], b, accuracy: 0.002) }
        let (flash, beep) = try await flashAndBeep(video)
        XCTAssertEqual(flash, try XCTUnwrap(beep), accuracy: 0.05)
    }

    func testARecordingWithoutSound() async throws {
        let source = folder.appendingPathComponent("silent.mov")
        try await Maker(width: 886, height: 1_918, seconds: 11, bitRate: 1_500_000, frames: .uneven, soundSeconds: 0).write(to: source)
        let (seen, video) = try await prepare(source, duration: 11)
        try await check(video, seen, source: source, keepAs: "copy-silent.mp4")
        let audio = try await AVURLAsset(url: video).loadTracks(withMediaType: .audio)
        XCTAssertTrue(audio.isEmpty)
    }

    func testLandscapeStaysTurned() async throws {
        let source = folder.appendingPathComponent("turned.mov")
        try await Maker(width: 886, height: 1_918, seconds: 11, bitRate: 1_500_000, frames: .even(30), soundSeconds: 11,
                        transform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1_918, ty: 0)).write(to: source)
        for (long, name) in [(1_920, "copy-turned.mp4"), (1_280, "encode-turned.mp4")] {
            let (seen, video) = try await prepare(source, long: long, duration: 11, into: name)
            try await check(video, seen, source: source, keepAs: name)
            let track = try await AVURLAsset(url: video).loadTracks(withMediaType: .video)[0]
            let size = try await track.load(.naturalSize), turn = try await track.load(.preferredTransform)
            let shown = CGRect(origin: .zero, size: size).applying(turn)
            XCTAssertGreaterThan(shown.width, shown.height)
            XCTAssertEqual(shown.minX, 0, accuracy: 1)
            XCTAssertEqual(shown.minY, 0, accuracy: 1)
            XCTAssertEqual(shown.width, long == 1_280 ? 1_280 : 1_918, accuracy: 2)
        }
    }

    // MARK: - Encoding

    func testScreenRecordingIsMadeSmallerForFree() async throws {
        let source = folder.appendingPathComponent("free.mov")
        try await Maker(width: 886, height: 1_918, seconds: 45, bitRate: 4_000_000, frames: .uneven, soundSeconds: 40).write(to: source)
        let (seen, video) = try await prepare(source, long: 1_280, duration: 45)
        try await check(video, seen, source: source, keepAs: "encode-screen-720p.mp4")
        let track = try await AVURLAsset(url: video).loadTracks(withMediaType: .video)[0]
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 592, height: 1_280))
        XCTAssertGreaterThanOrEqual(seen.final.count, 3, "sent in stretches")
        let after = try await frameTimes(video)
        for (a, b) in zip(after, after.dropFirst()) { XCTAssertGreaterThan(b - a, 0.02) }
        let before = try await frameTimes(source)
        // The last change on screen is kept.
        XCTAssertEqual(try XCTUnwrap(after.last), try XCTUnwrap(before.last) - before[0], accuracy: 0.05)
        let (flash, beep) = try await flashAndBeep(video)
        XCTAssertEqual(flash, try XCTUnwrap(beep), accuracy: 0.06)
        let rate = try await track.load(.estimatedDataRate)
        XCTAssertLessThan(rate, 1_700_000)
    }

    func testCameraClipIsMadeSmaller() async throws {
        let source = folder.appendingPathComponent("camera.mov")
        try await Maker(width: 1_080, height: 1_920, seconds: 14, bitRate: 10_000_000, frames: .even(30), soundSeconds: 14, busy: true).write(to: source)
        let (seen, video) = try await prepare(source, screen: false, duration: 14)
        try await check(video, seen, source: source, keepAs: "encode-camera-1080p.mp4")
        XCTAssertLessThan(Double(MediaInspector.fileSize(video)), Double(MediaInspector.fileSize(source)) * 0.75)
        let (flash, beep) = try await flashAndBeep(video)
        XCTAssertEqual(flash, try XCTUnwrap(beep), accuracy: 0.06)
    }

    func testSixtyFramesBecomeThirty() async throws {
        let source = folder.appendingPathComponent("sixty.mov")
        try await Maker(width: 1_080, height: 1_920, seconds: 11, bitRate: 12_000_000, frames: .even(60), soundSeconds: 11, busy: true).write(to: source)
        let (seen, video) = try await prepare(source, screen: false, duration: 11)
        try await check(video, seen, source: source, keepAs: "encode-60fps.mp4")
        let after = try await frameTimes(video)
        XCTAssertEqual(Double(after.count), 11 * 30, accuracy: 8)
    }

    func testTwoSoundsAreMixed() async throws {
        let source = folder.appendingPathComponent("two.mov")
        try await Maker(width: 886, height: 1_918, seconds: 12, bitRate: 1_800_000, frames: .uneven, soundSeconds: 12, soundTracks: 2).write(to: source)
        let (seen, video) = try await prepare(source, duration: 12)
        try await check(video, seen, source: source, keepAs: "copy-two-sounds.mp4")
        let audio = try await AVURLAsset(url: video).loadTracks(withMediaType: .audio)
        XCTAssertEqual(audio.count, 1)
        let (flash, beep) = try await flashAndBeep(video)
        XCTAssertEqual(flash, try XCTUnwrap(beep), accuracy: 0.06)
    }

    // MARK: - Stopping and carrying on

    func testEncodingCarriesOnWhereItStopped() async throws {
        let source = folder.appendingPathComponent("long.mov")
        try await Maker(width: 886, height: 1_918, seconds: 60, bitRate: 4_000_000, frames: .uneven, soundSeconds: 52).write(to: source)
        let (whole, reference) = try await prepare(source, long: 1_280, duration: 60, into: "whole")
        try await check(reference, whole, source: source, keepAs: "encode-whole.mp4")
        let (first, _) = try await prepare(source, long: 1_280, duration: 60, into: "parts", stopAfter: 2)
        XCTAssertNil(first.done)
        let (second, _) = try await prepare(source, long: 1_280, duration: 60, into: "parts", stopAfter: 2)
        XCTAssertEqual(second.copyIDs, first.copyIDs, "the same web copy")
        XCTAssertGreaterThan(second.fractions.first ?? 0, 0.2, "not from the start")
        let (last, video) = try await prepare(source, long: 1_280, duration: 60, into: "parts")
        XCTAssertEqual(last.copyIDs, first.copyIDs)
        var joined = last
        joined.final = first.final + second.final + last.final
        joined.fractions = last.fractions
        joined.files = first.files
        try await check(video, joined, source: source, keepAs: "encode-resumed.mp4")
        let a = try await frameTimes(reference), b = try await frameTimes(video)
        XCTAssertEqual(Double(a.count), Double(b.count), accuracy: 3)
        let (flash, beep) = try await flashAndBeep(video)
        XCTAssertEqual(flash, try XCTUnwrap(beep), accuracy: 0.06)
        // Running again when it is done costs nothing.
        let (again, _) = try await prepare(source, long: 1_280, duration: 60, into: "parts")
        XCTAssertEqual(again.done?.copyID, last.done?.copyID)
        XCTAssertTrue(again.fractions.isEmpty)
    }

    func testCopyingCarriesOnWhereItStopped() async throws {
        let source = folder.appendingPathComponent("longcopy.mov")
        try await Maker(width: 640, height: 360, seconds: 70, bitRate: 700_000, frames: .uneven, soundSeconds: 70).write(to: source)
        let (first, _) = try await prepare(source, duration: 70, into: "parts", stopAfter: 2)
        let (last, video) = try await prepare(source, duration: 70, into: "parts")
        if first.done == nil { XCTAssertEqual(last.copyIDs, first.copyIDs) }
        var joined = last
        joined.final = first.final + last.final
        joined.files = first.files
        if first.done == nil { try await check(video, joined, source: source, keepAs: "copy-resumed.mp4") }
        let before = try await frameTimes(source), after = try await frameTimes(video)
        XCTAssertEqual(before.count, after.count)
    }

    func testAChangedRecordingStartsOver() async throws {
        let source = folder.appendingPathComponent("changing.mov")
        try await Maker(width: 640, height: 360, seconds: 8, bitRate: 700_000, frames: .even(30), soundSeconds: 8).write(to: source)
        let (first, _) = try await prepare(source, duration: 8, into: "parts")
        try await Maker(width: 640, height: 360, seconds: 10, bitRate: 700_000, frames: .even(30), soundSeconds: 10).write(to: source)
        let (second, _) = try await prepare(source, duration: 10, into: "parts")
        XCTAssertNotEqual(first.done?.copyID, second.done?.copyID)
    }

    func testAMissingRecordingSaysSo() async throws {
        do {
            _ = try await prepare(folder.appendingPathComponent("nothing.mov"), duration: 3)
            XCTFail("no error")
        } catch WebExport.Failure.gone {
        }
    }

    func testAVoiceRecording() async throws {
        let movie = folder.appendingPathComponent("voice-movie.mov"), source = folder.appendingPathComponent("voice.m4a")
        try await Maker(width: 320, height: 180, seconds: 9, bitRate: 300_000, frames: .even(30), soundSeconds: 9).write(to: movie)
        try await WebExport.exportAudio(AVURLAsset(url: movie), to: source)
        let soundOnly = folder.appendingPathComponent("voice-only.m4a")
        let tracks = try await AVURLAsset(url: movie).loadTracks(withMediaType: .audio)
        _ = try await WebExport.encodeSound(AVURLAsset(url: movie), tracks: tracks, to: soundOnly)
        let (seen, video) = try await prepare(soundOnly, audio: true, duration: 9)
        keep(video, as: "voice.mp4")
        XCTAssertGreaterThan(seen.done?.size ?? 0, 10_000)
        XCTAssertGreaterThan(seen.files[.poster] ?? 0, 0)
        XCTAssertGreaterThan(seen.files[.preview] ?? 0, 0)
    }

    func testStandIns() throws {
        for (kind, name) in [(UploadJob.Part.Kind.poster, "p.jpg"), (.preview, "p.mp4")] {
            let url = folder.appendingPathComponent(name)
            WebExport.writeStandIn(kind, to: url, title: "Something")
            XCTAssertGreaterThan(MediaInspector.fileSize(url), 500)
        }
    }
}

// MARK: - Making recordings

/// Writes a fragmented .mov like the recorder's: a picture with text that changes, a white flash at 2 s, and a beep at
/// the same moment.
struct Maker {
    enum Frames {
        case even(Int)
        /// About 37 a second in bursts, with stretches where nothing changes, like a screen recording.
        case uneven
    }

    var width: Int
    var height: Int
    var seconds: Double
    var bitRate: Int
    var frames: Frames
    var soundSeconds: Double
    var soundTracks = 1
    var transform = CGAffineTransform.identity
    var reorders = false
    /// A picture that changes everywhere, like a camera's.
    var busy = false

    private func times() -> [Double] {
        switch frames {
        case .even(let rate):
            return (0..<Int(seconds * Double(rate))).map { Double($0) / Double(rate) }
        case .uneven:
            var list: [Double] = []
            var time = 0.0
            var index = 0
            while time < seconds - 0.05 {
                list.append(time)
                // Bursts at 60, then still for a moment; the flash needs its frame.
                let second = time.truncatingRemainder(dividingBy: 3)
                time += second < 1.6 ? 1.0 / 60 : second < 2.4 ? 1.0 / 30 : 0.28
                index += 1
            }
            if !list.contains(where: { abs($0 - 2) < 0.02 }) { list.append(2); list.sort() }
            // Two quick changes, then nothing until the end.
            list = list.filter { $0 < seconds - 1.5 }
            list += [seconds - 1.2, seconds - 1.2 + 1.0 / 60]
            return list
        }
    }

    func write(to url: URL) async throws {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            DispatchQueue.global().async {
                do {
                    try writeNow(to: url)
                    done.resume()
                } catch {
                    done.resume(throwing: error)
                }
            }
        }
    }

    private func writeNow(to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        writer.movieFragmentInterval = CMTime(seconds: 2, preferredTimescale: 600)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate, AVVideoExpectedSourceFrameRateKey: 30, AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel, AVVideoAllowFrameReorderingKey: reorders,
            ] as [String: Any],
        ])
        input.expectsMediaDataInRealTime = false
        input.transform = transform
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ])
        writer.add(input)
        var sounds: [AVAssetWriterInput] = []
        for _ in 0..<(soundSeconds > 0 ? soundTracks : 0) {
            let sound = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 96_000,
            ])
            sound.expectsMediaDataInRealTime = false
            writer.add(sound)
            sounds.append(sound)
        }
        XCTAssertTrue(writer.startWriting(), "\(String(describing: writer.error))")
        writer.startSession(atSourceTime: .zero)
        let group = DispatchGroup()
        group.enter()
        var list = times()[...]
        var count = 0
        let texture = busy ? Self.texture(width: width, height: height) : nil
        input.requestMediaDataWhenReady(on: DispatchQueue(label: "video")) {
            while input.isReadyForMoreMediaData {
                guard let time = list.popFirst() else {
                    input.markAsFinished()
                    group.leave()
                    return
                }
                autoreleasepool {
                    var buffer: CVPixelBuffer?
                    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
                    draw(buffer!, time: time, index: count, texture: texture)
                    adaptor.append(buffer!, withPresentationTime: CMTime(seconds: time, preferredTimescale: 600))
                }
                count += 1
            }
        }
        for (index, sound) in sounds.enumerated() {
            group.enter()
            var at = 0
            let total = Int(soundSeconds * 44_100)
            sound.requestMediaDataWhenReady(on: DispatchQueue(label: "sound\(index)")) {
                while sound.isReadyForMoreMediaData {
                    guard at < total else {
                        sound.markAsFinished()
                        group.leave()
                        return
                    }
                    let length = min(4_096, total - at)
                    sound.append(Self.tone(from: at, count: length))
                    at += length
                }
            }
        }
        group.wait()
        let done = DispatchSemaphore(value: 0)
        writer.endSession(atSourceTime: CMTime(seconds: seconds, preferredTimescale: 600))
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }

    private static func texture(width: Int, height: Int) -> [UInt8] {
        var value: UInt64 = 0x9E37_79B9_7F4A_7C15
        return (0..<(width * 4 * 64)).map { _ in
            value ^= value << 13; value ^= value >> 7; value ^= value << 17
            return UInt8(truncatingIfNeeded: value) / 3 + 60
        }
    }

    private func draw(_ buffer: CVPixelBuffer, time: Double, index: Int, texture: [UInt8]?) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let row = CVPixelBufferGetBytesPerRow(buffer)
        let base = CVPixelBufferGetBaseAddress(buffer)!
        if let texture {
            // Noise that moves: nothing stays where it was.
            texture.withUnsafeBytes { source in
                for y in 0..<height {
                    let from = ((y / 3 + index * 2) % 64) * width * 4
                    memcpy(base + y * row, source.baseAddress! + from, width * 4)
                }
            }
        }
        guard let context = CGContext(data: base, width: width, height: height, bitsPerComponent: 8, bytesPerRow: row,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
        let flash = time >= 1.99 && time < 2.1
        if texture == nil {
            context.setFillColor(UIColor(white: 0.08, alpha: 1).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        UIGraphicsPushContext(context)
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        // Lines of small text that scroll, and a clock.
        let line = CGFloat(height) / 48
        let font = UIFont.systemFont(ofSize: line * 0.62)
        let scroll = texture == nil ? CGFloat((time * 1.5).rounded(.down)) * line : 0
        if texture == nil {
            for number in 0..<46 {
                let text = "\(Int(scroll / line) + number)  The quick brown fox jumps over the lazy dog 0123456789" as NSString
                text.draw(at: CGPoint(x: 12, y: CGFloat(number) * line), withAttributes: [.font: font, .foregroundColor: UIColor(white: 0.85, alpha: 1)])
            }
            context.setFillColor(UIColor.systemRed.cgColor)
            context.fill(CGRect(x: CGFloat(index * 7 % max(1, width - 80)), y: CGFloat(height) * 0.9, width: 80, height: line))
        }
        ("\(String(format: "%.2f", time))" as NSString).draw(at: CGPoint(x: 20, y: CGFloat(height) * 0.8),
                                                            withAttributes: [.font: UIFont.boldSystemFont(ofSize: line * 2), .foregroundColor: UIColor.yellow])
        if flash {
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        } else {
            // The middle stays dark, so only the flash is bright there.
            context.setFillColor(UIColor(white: 0.1, alpha: 1).cgColor)
            context.fill(CGRect(x: width / 2 - 24, y: height / 2 - 24, width: 48, height: 48))
        }
        UIGraphicsPopContext()
    }

    private static func tone(from start: Int, count: Int) -> CMSampleBuffer {
        var samples = [Int16](repeating: 0, count: count)
        for index in 0..<count {
            let time = Double(start + index) / 44_100
            if time >= 2, time < 2.1 { samples[index] = Int16(20_000 * sin(2 * .pi * 880 * (time - 2) + 0.4)) }
        }
        var description = AudioStreamBasicDescription(mSampleRate: 44_100, mFormatID: kAudioFormatLinearPCM,
                                                      mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                                                      mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
                                                      mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &description, layoutSize: 0, layout: nil, magicCookieSize: 0,
                                       magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: count * 2, blockAllocator: nil,
                                           customBlockSource: nil, offsetToData: 0, dataLength: count * 2, flags: 0, blockBufferOut: &block)
        CMBlockBufferReplaceDataBytes(with: samples, blockBuffer: block!, offsetIntoDestination: 0, dataLength: count * 2)
        var buffer: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block!, formatDescription: format!,
                                                             sampleCount: count, presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: 44_100),
                                                             packetDescriptions: nil, sampleBufferOut: &buffer)
        return buffer!
    }
}
