import CoreMedia
import Foundation

/// Keeps one sound track in step with the picture.
///
/// AVAssetWriter's AAC tracks have no gaps: samples are packed one after the other whatever their
/// timestamps say. Every buffer that is dropped (the writer wasn't ready, the phone was busy) moves
/// all later sound earlier. In an 8:50 screen recording made on an iPhone X with build 37 that added
/// up to 93 seconds. This works out, for each buffer, how much silence has to go in first so that it
/// lands at its own time, and which buffers repeat sound the track already has.
struct SoundTimeline {
    enum Step: Equatable {
        /// Append the buffer as it is.
        case append
        /// Append this many seconds of silence first, then the buffer.
        case fill(seconds: Double)
        /// The track is already past this buffer.
        case drop
    }

    /// A buffer may be this late before silence goes in: under one AAC packet (1024 frames, 23 ms).
    static let tolerance = 0.02
    /// A buffer may overlap what is already there by this much (timestamps jitter) before it is
    /// dropped. The overlap is made up by the next gap.
    static let overlap = 0.06

    private var origin: Double?
    private(set) var length: Double = 0

    /// Where the packed track ends, in movie seconds. Nil before the first buffer.
    var end: Double? { origin.map { $0 + length } }

    func step(forBufferAt time: Double) -> Step {
        guard let end else { return .append }
        let gap = time - end
        if gap > Self.tolerance { return .fill(seconds: gap) }
        if gap < -Self.overlap { return .drop }
        return .append
    }

    /// `seconds` of sound were appended. `time` is the buffer's own time (the first one starts the
    /// track). Counted in seconds, so a microphone that changes its sample rate (a headset) is fine.
    mutating func appended(seconds: Double, at time: Double) {
        if origin == nil { origin = time }
        length += max(0, seconds)
    }
}

/// Buffers of PCM the writer can take: silence in the format of a real buffer, and copies that don't
/// hold on to ReplayKit's own buffers while they wait.
enum SoundBuffer {
    /// Silence is appended in pieces of at most this many frames (about a quarter of a second), so a
    /// long gap never needs a large block of memory.
    static let pieceFrames = 11_025

    static func sampleRate(of sample: CMSampleBuffer) -> Double? {
        guard let basic = basicDescription(of: sample) else { return nil }
        return basic.mSampleRate
    }

    /// `frames` frames of silence in `sample`'s format, starting at `time`.
    static func silence(like sample: CMSampleBuffer, frames: Int, at time: CMTime) -> CMSampleBuffer? {
        guard frames > 0, let format = CMSampleBufferGetFormatDescription(sample),
              let basic = basicDescription(of: sample) else { return nil }
        // Non-interleaved PCM has one plane per channel, each `mBytesPerFrame` wide.
        let separate = basic.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let planes = separate ? max(1, Int(basic.mChannelsPerFrame)) : 1
        let length = frames * Int(basic.mBytesPerFrame) * planes
        guard let block = emptyBlock(length: length),
              CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0,
                                         dataLength: length) == noErr else {
            return nil
        }
        var result: CMSampleBuffer?
        let status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format, sampleCount: frames,
            presentationTimeStamp: time, packetDescriptions: nil, sampleBufferOut: &result)
        return status == noErr ? result : nil
    }

    /// A copy with its own memory.
    static func copy(_ sample: CMSampleBuffer) -> CMSampleBuffer? {
        guard let format = CMSampleBufferGetFormatDescription(sample),
              let source = CMSampleBufferGetDataBuffer(sample) else { return nil }
        let length = CMBlockBufferGetDataLength(source)
        guard length > 0, let block = emptyBlock(length: length) else { return nil }
        var pointer: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: nil,
                                          dataPointerOut: &pointer) == noErr, let pointer,
              CMBlockBufferCopyDataBytes(source, atOffset: 0, dataLength: length, destination: pointer) == noErr else {
            return nil
        }
        var result: CMSampleBuffer?
        let status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
            sampleCount: CMSampleBufferGetNumSamples(sample),
            presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sample),
            packetDescriptions: nil, sampleBufferOut: &result)
        return status == noErr ? result : nil
    }

    private static func basicDescription(of sample: CMSampleBuffer) -> AudioStreamBasicDescription? {
        guard let format = CMSampleBufferGetFormatDescription(sample),
              let basic = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              basic.mFormatID == kAudioFormatLinearPCM, basic.mSampleRate > 0, basic.mBytesPerFrame > 0 else { return nil }
        return basic
    }

    private static func emptyBlock(length: Int) -> CMBlockBuffer? {
        var block: CMBlockBuffer?
        let status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: length,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: length,
            flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
        return status == noErr ? block : nil
    }
}
