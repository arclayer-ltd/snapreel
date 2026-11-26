import AVFoundation
import CoreGraphics
import Foundation
import UIKit
import XCTest
@testable import Snapreel

/// Recordings made for the tests. Every frame carries its own number as a row of black and white
/// blocks, so a test can tell which source frame an edited video shows at any moment; the sound
/// has a short beep at the start of every second, so it can tell where the sound ended up.
enum TestMedia {
    struct Spec {
        var duration: Double = 10
        var size = CGSize(width: 886, height: 1918)
        /// Uneven frames on a 60 Hz grid, like an iOS screen recording (about 37 a second).
        var variableFrameRate = true
        var frameRate: Double = 30
        /// nil = no sound. Shorter than the picture = like a screen recording with the sound cut off.
        var audioDuration: Double? = 10
        var audioStart: Double = 0
        var transform = CGAffineTransform.identity
        var codec: AVVideoCodecType = .h264
        var bitRate = 2_500_000
        /// The picture stops moving for this long at this time (one long frame).
        var stillAt: Double?
        var stillLength: Double = 2
        var name: String = "clip"
    }

    static var folder: URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("EditorTests", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Frame times of a spec, in 600ths of a second.
    static func frameTimes(_ spec: Spec) -> [CMTime] {
        var result: [CMTime] = []
        var random: UInt64 = 88172645463325252
        func next() -> Double {
            random ^= random << 13
            random ^= random >> 7
            random ^= random << 17
            return Double(random % 10_000) / 10_000
        }
        if spec.variableFrameRate {
            var tick = 0
            let total = Int(spec.duration * 60)
            while tick < total {
                let seconds = Double(tick) / 60
                result.append(CMTime(value: CMTimeValue(tick * 10), timescale: 600))
                if let still = spec.stillAt, seconds >= still, seconds < still + 0.2 {
                    tick += Int(spec.stillLength * 60)
                    continue
                }
                let dice = next()
                tick += dice < 0.665 ? 1 : (dice < 0.945 ? 3 : 2)
            }
        } else {
            let count = Int((spec.duration * spec.frameRate).rounded())
            for index in 0..<count {
                result.append(CMTime(value: CMTimeValue((Double(index) * 600 / spec.frameRate).rounded()), timescale: 600))
            }
        }
        return result
    }

    static let bits = 16

    /// Makes (or reuses) the recording.
    static func make(_ spec: Spec) async throws -> (url: URL, times: [CMTime]) {
        let times = frameTimes(spec)
        let url = folder.appendingPathComponent(spec.name + ".mov")
        if FileManager.default.fileExists(atPath: url.path) { return (url, times) }
        let partial = folder.appendingPathComponent("partial-" + spec.name + ".mov")
        try? FileManager.default.removeItem(at: partial)
        let writer = try AVAssetWriter(outputURL: partial, fileType: .mov)
        var compression: [String: Any] = [AVVideoAverageBitRateKey: spec.bitRate,
                                          AVVideoMaxKeyFrameIntervalDurationKey: 3]
        if spec.codec == .h264 { compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel }
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: spec.codec,
            AVVideoWidthKey: spec.size.width,
            AVVideoHeightKey: spec.size.height,
            AVVideoCompressionPropertiesKey: compression,
        ])
        video.transform = spec.transform
        video.mediaTimeScale = 600
        video.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(spec.size.width),
            kCVPixelBufferHeightKey as String: Int(spec.size.height),
        ])
        writer.add(video)
        var audio: AVAssetWriterInput?
        if spec.audioDuration != nil {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 96_000,
            ])
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            audio = input
        }
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)

        let job = Job(writer: writer, video: video, adaptor: adaptor, audio: audio)
        let end = CMTime(seconds: max(spec.duration, (spec.audioDuration ?? 0) + spec.audioStart), preferredTimescale: 600)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try write(job, spec: spec, times: times)
                    let done = DispatchSemaphore(value: 0)
                    job.writer.endSession(atSourceTime: end)
                    job.writer.finishWriting { done.signal() }
                    done.wait()
                    if job.writer.status != .completed { throw job.writer.error ?? CocoaError(.fileWriteUnknown) }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        try FileManager.default.moveItem(at: partial, to: url)
        return (url, times)
    }

    private struct Job: @unchecked Sendable {
        let writer: AVAssetWriter
        let video: AVAssetWriterInput
        let adaptor: AVAssetWriterInputPixelBufferAdaptor
        let audio: AVAssetWriterInput?
    }

    private static func write(_ job: Job, spec: Spec, times: [CMTime]) throws {
        var frame = 0
        var sample = 0
        let audioSamples = Int((spec.audioDuration ?? 0) * 44_100)
        var audioDone = job.audio == nil
        var videoDone = false
        var idle = 0
        while !(videoDone && audioDone) {
            var moved = false
            if !videoDone, job.video.isReadyForMoreMediaData {
                try autoreleasepool {
                    guard let pool = job.adaptor.pixelBufferPool else { throw CocoaError(.fileWriteUnknown) }
                    var made: CVPixelBuffer?
                    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
                    guard let buffer = made else { throw CocoaError(.fileWriteUnknown) }
                    draw(index: frame, into: buffer)
                    if !job.adaptor.append(buffer, withPresentationTime: times[frame]) {
                        throw job.writer.error ?? CocoaError(.fileWriteUnknown)
                    }
                }
                frame += 1
                if frame == times.count {
                    job.video.markAsFinished()
                    videoDone = true
                }
                moved = true
            }
            if !audioDone, let audio = job.audio, audio.isReadyForMoreMediaData {
                let count = min(4_410, audioSamples - sample)
                if count <= 0 {
                    audio.markAsFinished()
                    audioDone = true
                } else {
                    guard let buffer = beepBuffer(from: sample, count: count, start: spec.audioStart),
                          audio.append(buffer) else { throw job.writer.error ?? CocoaError(.fileWriteUnknown) }
                    sample += count
                }
                moved = true
            }
            if moved {
                idle = 0
            } else {
                idle += 1
                if idle > 60_000 { throw job.writer.error ?? CocoaError(.fileWriteUnknown) }
                usleep(1_000)
            }
        }
    }

    /// The frame's number along the top as blocks, a red square in the top-left corner, a blue one
    /// in the top-right and scrolling rows below (like a list being scrolled).
    private static func draw(index: Int, into buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return }
        // Top-left origin.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        let w = CGFloat(width), h = CGFloat(height)
        let paper = CGColor(red: 0.95, green: 0.95, blue: 0.96, alpha: 1)
        context.setFillColor(paper)
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let row = h / 14
        for line in 0..<15 {
            let y = CGFloat(line) * row - CGFloat(index % 60) / 60 * row + h * 0.25
            context.setFillColor(line % 2 == 0 ? CGColor(red: 0.3, green: 0.33, blue: 0.4, alpha: 1)
                                 : CGColor(red: 0.8, green: 0.82, blue: 0.86, alpha: 1))
            context.fill(CGRect(x: w * 0.06, y: y, width: w * 0.88, height: row * 0.6))
        }
        context.setFillColor(paper)
        context.fill(CGRect(x: 0, y: 0, width: w, height: h * 0.25))
        let corner = min(w, h) * 0.1
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: corner, height: corner))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: w - corner, y: 0, width: corner, height: corner))
        let block = w / CGFloat(bits)
        for bit in 0..<bits {
            let on = (index >> bit) & 1 == 1
            context.setFillColor(on ? CGColor(red: 1, green: 1, blue: 1, alpha: 1) : CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: CGFloat(bit) * block, y: h * 0.12, width: block, height: h * 0.06))
        }
    }

    /// A 50 ms beep at every whole second; silence otherwise.
    private static func beepBuffer(from sample: Int, count: Int, start: Double) -> CMSampleBuffer? {
        var data = [Int16](repeating: 0, count: count)
        for offset in 0..<count {
            let position = sample + offset
            if position % 44_100 < 2_205 {
                data[offset] = Int16(12_000 * sin(Double(position) * 2 * .pi * 1_000 / 44_100))
            }
        }
        var asbd = AudioStreamBasicDescription(mSampleRate: 44_100, mFormatID: kAudioFormatLinearPCM,
                                               mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                                               mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
                                               mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0,
                                       magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        guard let format else { return nil }
        var made: CMBlockBuffer?
        let bytes = count * 2
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil,
                                           customBlockSource: nil, offsetToData: 0, dataLength: bytes,
                                           flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &made)
        guard let block = made else { return nil }
        data.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                _ = CMBlockBufferReplaceDataBytes(with: base, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes)
            }
        }
        var buffer: CMSampleBuffer?
        let at = CMTime(seconds: start, preferredTimescale: 44_100) + CMTime(value: CMTimeValue(sample), timescale: 44_100)
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block, formatDescription: format,
                                                             sampleCount: count, presentationTimeStamp: at,
                                                             packetDescriptions: nil, sampleBufferOut: &buffer)
        return buffer
    }

    /// A long recording: a 60-second one played `minutes` times over (copied, not encoded again),
    /// with its sound `audioShortBy` seconds shorter than the picture.
    static func long(minutes: Int, audioShortBy: Double) async throws -> URL {
        let url = folder.appendingPathComponent("long-\(minutes).mov")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        var spec = Spec()
        spec.duration = 60
        spec.audioDuration = 60
        spec.name = "minute"
        let (minute, _) = try await make(spec)
        let asset = AVURLAsset(url: minute, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let composition = AVMutableComposition()
        let video = try await asset.loadTracks(withMediaType: .video)[0]
        let audio = try await asset.loadTracks(withMediaType: .audio)[0]
        let videoRange = try await video.load(.timeRange)
        let audioRange = try await audio.load(.timeRange)
        let videoOut = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        let audioOut = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
        let length = CMTime(value: 36_000, timescale: 600)
        let soundEnd = Double(minutes * 60) - audioShortBy
        for index in 0..<minutes {
            let at = CMTimeMultiply(length, multiplier: Int32(index))
            try videoOut.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(length, videoRange.duration)), of: video, at: at)
            let room = min(60, soundEnd - Double(index) * 60)
            if room > 0 {
                let wanted = CMTimeMinimum(CMTime(seconds: room, preferredTimescale: 44_100), audioRange.duration)
                try audioOut.insertTimeRange(CMTimeRange(start: audioRange.start, duration: wanted), of: audio, at: at)
            }
        }
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw CocoaError(.fileWriteUnknown)
        }
        session.outputURL = url
        session.outputFileType = .mov
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { continuation.resume() }
        }
        guard session.status == .completed else { throw session.error ?? CocoaError(.fileWriteUnknown) }
        return url
    }

    // MARK: - Reading back

    struct ReadFrame {
        var time: Double
        /// The number drawn on the frame, nil when it can't be read.
        var index: Int?
    }

    /// Every frame of a file: its time and the number drawn on it.
    static func readFrames(_ url: URL) async throws -> [ReadFrame] {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { return [] }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        reader.startReading()
        var frames: [ReadFrame] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            frames.append(ReadFrame(time: CMSampleBufferGetPresentationTimeStamp(sample).seconds, index: number(in: buffer)))
        }
        if reader.status == .failed { throw reader.error ?? CocoaError(.fileReadUnknown) }
        return frames.sorted { $0.time < $1.time }
    }

    static func number(in buffer: CVPixelBuffer) -> Int? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let y = Int(Double(height) * 0.15)
        var value = 0
        for bit in 0..<bits {
            let x = Int((Double(bit) + 0.5) * Double(width) / Double(bits))
            let pixel = base + y * stride + x * 4
            let luma = (Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2])) / 3
            if luma > 160 { value |= 1 << bit } else if luma > 95 { return nil }
        }
        return value
    }

    /// Colour (r, g, b) at a normalised point of the frame at `seconds`, as shown (upright).
    static func color(_ url: URL, at seconds: Double, x: Double, y: Double) async throws -> (Double, Double, Double) {
        color(try await image(url, at: seconds), x: x, y: y)
    }

    static func image(_ url: URL, at seconds: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }

    static func color(_ image: CGImage, x: Double, y: Double) -> (Double, Double, Double) {
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            let w = CGFloat(image.width), h = CGFloat(image.height)
            context?.draw(image, in: CGRect(x: -CGFloat(x) * w, y: -(1 - CGFloat(y)) * h, width: w, height: h))
        }
        return (Double(pixel[0]) / 255, Double(pixel[1]) / 255, Double(pixel[2]) / 255)
    }

    /// Times where a beep starts, in seconds, and the length of the sound.
    static func beeps(_ url: URL) async throws -> (starts: [Double], length: Double) {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { return ([], 0) }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        reader.startReading()
        var starts: [Double] = []
        var last = -1.0
        var end = 0.0
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            let length = CMBlockBufferGetDataLength(block)
            var data = [Int16](repeating: 0, count: length / 2)
            data.withUnsafeMutableBytes { raw in
                if let base = raw.baseAddress {
                    _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base)
                }
            }
            for (offset, value) in data.enumerated() where abs(Int(value)) > 3_000 {
                let t = time + Double(offset) / 44_100
                if t - last > 0.2 { starts.append(t) }
                last = t
            }
            end = time + Double(data.count) / 44_100
        }
        return (starts, end)
    }

    static func fileSize(_ url: URL) -> Int { (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }

    // MARK: - Library

    /// A fresh library in memory with `url` in it (hard linked, so nothing is copied).
    @MainActor
    static func library(with url: URL, kind: RecordingKind = .camera) async throws -> (Library, UUID) {
        let library = emptyLibrary()
        let info = try await MediaInspector.inspect(url)
        let id = UUID()
        let name = id.uuidString + "." + url.pathExtension
        try FileManager.default.linkItem(at: url, to: library.media.videoURL(name))
        library.add(Video(id: id, title: "Test", createdAt: Date(), kind: kind, fileName: name, thumbnailFileName: nil,
                          duration: info.duration, fileSize: info.fileSize, pixelWidth: info.pixelWidth,
                          pixelHeight: info.pixelHeight, needsTitle: false, state: .ready, reviewedAt: Date()))
        return (library, id)
    }

    @MainActor
    static func emptyLibrary() -> Library {
        let root = folder.appendingPathComponent("library-\(UUID().uuidString)", isDirectory: true)
        return Library(storage: InMemoryStorage(mediaRoot: root))
    }

    /// A library with one recording that has no file, for tests of the recipe alone.
    @MainActor
    static func placeholder(duration: Double) -> (Library, UUID) {
        let library = emptyLibrary()
        let id = UUID()
        library.add(Video(id: id, title: "Test", createdAt: Date(), kind: .camera, fileName: "none.mov", thumbnailFileName: nil,
                          duration: duration, fileSize: 0, pixelWidth: 886, pixelHeight: 1918, needsTitle: false,
                          state: .ready, reviewedAt: Date()))
        return (library, id)
    }

    /// Saves `recipe` as a new recording and returns its file.
    @MainActor
    static func export(_ recipe: EditRecipe, library: Library, timeout: Double = 3_000) async throws -> (Video, URL) {
        let source = library.video(recipe.sourceID)!
        let id = EditRenderer.shared.begin(recipe: recipe, source: source, library: library)
        let started = Date()
        while Date().timeIntervalSince(started) < timeout {
            try await Task.sleep(nanoseconds: 50_000_000)
            guard let video = library.video(id) else { throw CocoaError(.fileNoSuchFile) }
            switch video.state {
            case .ready:
                await RecordingSaver.shared.waitUntilFinished(id)
                return (library.video(id) ?? video, library.fileURL(for: video))
            case .failed(let reason, _):
                let why = EditRenderer.shared.lastFailure ?? "no detail"
                print("NOTE|save failed: \(reason) | \(why)")
                throw NSError(domain: "Export", code: 1, userInfo: [NSLocalizedDescriptionKey: reason + " | " + why])
            case .saving:
                continue
            }
        }
        throw NSError(domain: "Export", code: 2, userInfo: [NSLocalizedDescriptionKey: "timed out"])
    }
}

/// Memory the app holds, in megabytes (what iOS counts against its limit).
func memoryMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
}

/// Highest memory seen while it runs.
final class MemoryPeak {
    private let queue = DispatchQueue(label: "memory-peak")
    private var timer: DispatchSourceTimer?
    private var highest = 0.0

    init() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(50))
        timer.setEventHandler { [weak self] in self?.note() }
        timer.resume()
        self.timer = timer
    }

    private func note() { highest = max(highest, memoryMB()) }

    func stop() -> Double {
        queue.sync {
            note()
            timer?.cancel()
            return highest
        }
    }
}

/// Measured values, printed so the CI job can collect them.
func perf(_ name: String, _ metric: String, _ value: Double, _ unit: String) {
    print(String(format: "PERF|%@|%@|%.2f|%@", name, metric, value, unit))
}
