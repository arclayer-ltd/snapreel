import ReplayKit

/// Placeholder principal class so the extension target builds from the first run.
/// Session B replaces this file with the real writer (AVAssetWriter into the App Group inbox).
final class SampleHandler: RPBroadcastSampleHandler {
    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        BroadcastStateStore.write(BroadcastState(status: .recording, recordingID: UUID(), startedAt: Date()))
        BroadcastSignal.started.post()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {}

    override func broadcastFinished() {
        BroadcastStateStore.write(BroadcastState(status: .finished))
        BroadcastSignal.finished.post()
    }
}
