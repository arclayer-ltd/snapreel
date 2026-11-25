import AVFoundation
import ReplayKit
import XCTest

/// The screen recorder's writer (compiled into the tests; the app doesn't contain it): sound stays in
/// step with the picture whatever is lost on the way.
final class BroadcastSoundTests: MovieTestCase {
    // MARK: The timeline

    func testStepsThroughAGap() {
        var timeline = SoundTimeline()
        XCTAssertEqual(timeline.step(forBufferAt: 5), .append)
        timeline.appended(seconds: 0.1, at: 5)
        XCTAssertEqual(timeline.end ?? 0, 5.1, accuracy: 0.0001)
        XCTAssertEqual(timeline.step(forBufferAt: 5.1), .append)
        XCTAssertEqual(timeline.step(forBufferAt: 5.11), .append, "jitter")
        XCTAssertEqual(timeline.step(forBufferAt: 5.06), .append, "jitter")
        XCTAssertEqual(timeline.step(forBufferAt: 5.0), .drop, "the same sound again")
        guard case .fill(let gap) = timeline.step(forBufferAt: 7.1) else { return XCTFail("no gap") }
        XCTAssertEqual(gap, 2, accuracy: 0.0001)
    }

    /// Small errors must not add up: an hour of buffers whose times are each a little off.
    func testJitterDoesNotDrift() {
        var timeline = SoundTimeline()
        let length = 1024.0 / 44_100
        var time = 0.0
        for index in 0..<155_000 {
            let seen = time + (index % 3 == 0 ? 0.004 : index % 3 == 1 ? -0.004 : 0)
            switch timeline.step(forBufferAt: seen) {
            case .append: timeline.appended(seconds: length, at: seen)
            case .fill(let gap): timeline.appended(seconds: gap + length, at: seen)
            case .drop: break
            }
            time += length
        }
        XCTAssertEqual(timeline.end ?? 0, time, accuracy: 0.1)
    }

    func testSilenceHasTheSameFormat() throws {
        let real = try XCTUnwrap(TestMovie.pcmBuffer(frames: 1024, startingAt: 0, pitch: 440))
        let silence = try XCTUnwrap(SoundBuffer.silence(like: real, frames: 500, at: CMTime(value: 1, timescale: 1)))
        XCTAssertEqual(CMSampleBufferGetNumSamples(silence), 500)
        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(silence).seconds, 1)
        XCTAssertEqual(CMSampleBufferGetFormatDescription(silence), CMSampleBufferGetFormatDescription(real))
        let copy = try XCTUnwrap(SoundBuffer.copy(real))
        XCTAssertEqual(CMSampleBufferGetNumSamples(copy), 1024)
        XCTAssertNil(SoundBuffer.silence(like: real, frames: 0, at: .zero))
    }

    // MARK: The fault

    /// What AVAssetWriter does with gaps, and why the timeline is needed (builds up to 47).
    func testAACTracksSwallowGaps() async throws {
        let url = folder.appendingPathComponent("gaps.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128_000,
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        // Ten seconds with every fifth buffer missing.
        for index in 0..<431 where index % 5 != 4 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            let time = CMTime(value: CMTimeValue(index * 1024), timescale: 44_100)
            XCTAssertTrue(input.append(try XCTUnwrap(TestMovie.pcmBuffer(frames: 1024, startingAt: 0, pitch: 440, at: time))))
        }
        input.markAsFinished()
        await writer.finishWriting()
        let length = try await AVURLAsset(url: url).loadTracks(withMediaType: .audio)[0].load(.timeRange).duration.seconds
        measure(String(format: "AAC track of 10.0 s with a fifth of its buffers missing: %.1f s long", length))
    }

    // MARK: The writer

    func testSoundStaysInStepWhenBuffersAreLost() async throws {
        let facts = try await record(seconds: 8) { index in
            // A fifth of the buffers, and everything between 3 and 5 seconds.
            index % 5 == 4 || (129..<215).contains(index)
        }
        XCTAssertEqual(facts.audio.count, 1)
        XCTAssertEqual(facts.audio[0], facts.video, accuracy: 0.25)
        measure(String(format: "recorder, buffers lost: picture %.2f s, sound %.2f s, %d frames", facts.video, facts.audio[0], facts.frames))
        // The tone after the hole is where it belongs, and the hole is silent.
        let hole = try await loudness(from: 3.4, to: 4.6)
        let after = try await loudness(from: 6, to: 7.5)
        XCTAssertLessThan(hole, 0.02)
        XCTAssertGreaterThan(after, 0.1)
    }

    func testSoundStaysInStepNormally() async throws {
        let facts = try await record(seconds: 8) { _ in false }
        XCTAssertEqual(facts.audio[0], facts.video, accuracy: 0.25)
        measure(String(format: "recorder, real time: picture %.2f s, sound %.2f s, %d of 480 frames", facts.video, facts.audio[0], facts.frames))
    }

    func testTurnedPicturesStayInView() {
        for orientation in [CGImagePropertyOrientation.up, .right, .left, .down] {
            let transform = BroadcastWriter.transform(for: orientation, width: 886, height: 1918)
            let placed = CGRect(x: 0, y: 0, width: 886, height: 1918).applying(transform)
            XCTAssertEqual(placed.minX, 0)
            XCTAssertEqual(placed.minY, 0)
        }
    }

    // MARK: Recording

    private var recorded: URL { folder.appendingPathComponent("screen.mov") }

    /// Sends 60 frames and 43 sound buffers a second in real time, as ReplayKit does, with the
    /// microphone off.
    private func record(seconds: Double, loses: (Int) -> Bool) async throws -> (video: Double, audio: [Double], frames: Int) {
        let writer = BroadcastWriter(url: recorded, quality: "1080p")
        let start = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        let buffer = try XCTUnwrap(TestMovie.noise(width: 886, height: 1918))
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format)
        var frame = 0, sound = 0
        while true {
            let now = CMClockGetTime(CMClockGetHostTimeClock()).seconds - start
            if now > seconds { break }
            let nextFrame = Double(frame) / 60, nextSound = Double(sound) * 1024 / 44_100
            if nextFrame <= now, nextFrame <= nextSound {
                var timing = CMSampleTimingInfo(duration: .invalid,
                                                presentationTimeStamp: CMTime(seconds: start + nextFrame, preferredTimescale: 1_000_000_000),
                                                decodeTimeStamp: .invalid)
                var sample: CMSampleBuffer?
                CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: buffer, formatDescription: try XCTUnwrap(format),
                                                         sampleTiming: &timing, sampleBufferOut: &sample)
                writer.append(try XCTUnwrap(sample), type: .video)
                frame += 1
            } else if nextSound <= now {
                if !loses(sound) {
                    let time = CMTime(seconds: start + nextSound, preferredTimescale: 1_000_000_000)
                    let sample = try XCTUnwrap(TestMovie.pcmBuffer(frames: 1024, startingAt: sound * 1024, pitch: 440, at: time))
                    writer.append(sample, type: .audioApp)
                }
                sound += 1
            } else {
                usleep(1_000)
            }
        }
        guard case .written(let url) = writer.finish() else {
            XCTFail("not written")
            throw TestMovie.Failed(reason: "not written")
        }
        let facts = try await MovieFacts.read(url)
        return (facts.videoSeconds, facts.audioSeconds, facts.frames)
    }

    private func loudness(from start: Double, to end: Double) async throws -> Double {
        try await MovieFacts.loudness(recorded, from: start, to: end)
    }
}
