import AVFoundation
import ReplayKit
import UserNotifications

/// Snapreel's screen recorder. ReplayKit runs this in its own process while the screen is
/// recorded; it writes the movie into the App Group and leaves it in the inbox for the app.
///
/// How it ends, in every case the movie is finished and moved to the inbox first:
/// - the person stops from the red status pill or Control Centre, or the phone locks
///   (`broadcastFinished`),
/// - the app asks it to stop (`BroadcastSignal.stopRequested`),
/// - the phone is nearly full (stops early and keeps what was recorded).
/// Except when the app asked (it's in front and ends the card itself), it then ends the Lock
/// Screen card through the push relay (`LiveActivityPush.sendEnd`), because the app is
/// usually suspended and can't.
final class SampleHandler: RPBroadcastSampleHandler {
    /// Must match `PendingImports.broadcastNotificationPrefix` in the app.
    static let notificationPrefix = "broadcast-"

    private let work = DispatchQueue(label: "co.arclayer.snapreel.broadcast.work")
    private let stateLock = NSLock()
    private var writer: BroadcastWriter?
    private var recordingID = UUID()
    private var startedAt = Date()
    private var stopObserver: BroadcastSignalObserver?
    private var heartbeat: DispatchSourceTimer?
    private var didFinish = false

    /// Below this much free space a recording doesn't start.
    private static let spaceToStart: Int64 = 300_000_000
    /// Below this much free space a running recording stops and keeps what it has.
    private static let spaceToContinue: Int64 = 150_000_000

    // MARK: - ReplayKit

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        recordingID = UUID()
        startedAt = Date()

        guard Self.freeSpace() > Self.spaceToStart else {
            let message = "Your iPhone is almost full. Free up some space, then try again."
            writeState(.failed, message: message)
            BroadcastSignal.finished.post()
            SharedLog.append("broadcast: not started, the phone is almost full")
            LiveActivityPush.sendEnd(elapsed: 0)
            finishBroadcastWithError(Self.error(.insufficientStorage, message))
            return
        }

        let quality = AppGroup.defaults.string(forKey: SharedDefaultsKey.recordingQuality)
        let url = AppGroup.inProgressURL.appendingPathComponent("\(recordingID.uuidString).mov")
        writer = BroadcastWriter(url: url, quality: quality)
        writeState(.recording)
        BroadcastSignal.started.post()

        stopObserver = BroadcastSignalObserver(.stopRequested) { [weak self] in
            self?.stopRequestedByApp()
        }
        startHeartbeat()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        writer?.append(sampleBuffer, type: sampleBufferType)
    }

    override func broadcastPaused() {
        writer?.pause()
    }

    override func broadcastResumed() {
        writer?.resume()
    }

    override func broadcastFinished() {
        finalize(endedEarly: false, note: nil)
    }

    // MARK: - Stopping

    /// The app's Stop button. Finish the movie first, then end the broadcast with a friendly
    /// reason (iOS shows it in its "stopped" alert).
    private func stopRequestedByApp() {
        work.async { [weak self] in
            guard let self else { return }
            self.finalize(endedEarly: false, note: nil, endsCardByPush: false)
            self.finishBroadcastWithError(Self.savedMessage)
        }
    }

    private func startHeartbeat() {
        let timer = DispatchSource.makeTimerSource(queue: work)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        timer.resume()
        heartbeat = timer
    }

    /// Every two seconds: tell the app the recording is alive, and stop before the disk fills.
    private func tick() {
        guard !isFinished else { return }
        if Self.freeSpace() < Self.spaceToContinue {
            finalize(endedEarly: true,
                     note: "Your iPhone ran out of space, so the recording stopped early. Everything up to that point is saved.")
            finishBroadcastWithError(Self.error(.insufficientStorage,
                                                "Your iPhone is almost full, so Snapreel stopped recording and saved what it had."))
            return
        }
        writeState(.recording)
    }

    private var isFinished: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return didFinish
    }

    /// Finishes the movie, moves it to the inbox with its manifest, updates the shared state,
    /// tells the app and schedules the "ready" notification. Runs once.
    private func finalize(endedEarly: Bool, note: String?, endsCardByPush: Bool = true) {
        stateLock.lock()
        if didFinish {
            stateLock.unlock()
            return
        }
        didFinish = true
        let timer = heartbeat
        heartbeat = nil
        stateLock.unlock()
        timer?.cancel()
        let stoppedAt = Date()

        writeState(.finishing)
        let outcome = writer?.finish() ?? .nothingRecorded
        let microphone = writer?.microphoneHeard ?? false

        switch outcome {
        case .written(let url):
            deliver(url, endedEarly: endedEarly, note: note, microphone: microphone)
        case .partial(let url):
            deliver(url, endedEarly: true,
                    note: note ?? "The recording stopped unexpectedly. Snapreel kept everything it could.",
                    microphone: microphone)
        case .nothingRecorded:
            writeState(.failed, message: "Nothing was recorded. Try again, and keep the recording going for a moment before you stop it.")
        }
        BroadcastSignal.finished.post()
        let length = stoppedAt.timeIntervalSince(startedAt)
        SharedLog.append(String(format: "broadcast: finished after %.1f s%@", length, endedEarly ? ", early" : ""))
        // Last: the app (if it is running) has heard the signal and ends the card itself; this
        // covers the usual case where it is suspended. Waits up to 6 s for the relay.
        if endsCardByPush { LiveActivityPush.sendEnd(elapsed: length) }
    }

    private func deliver(_ movie: URL, endedEarly: Bool, note: String?, microphone: Bool) {
        let fm = FileManager.default
        let name = movie.lastPathComponent
        let destination = AppGroup.inboxURL.appendingPathComponent(name)
        try? fm.removeItem(at: destination)
        do {
            try fm.moveItem(at: movie, to: destination)
        } catch {
            writeState(.failed, message: "Snapreel couldn't keep this recording. Try again.")
            return
        }
        let manifest = InboxRecording(id: recordingID, movieFileName: name, createdAt: startedAt,
                                      finishedAt: Date(), microphoneEnabled: microphone,
                                      endedEarly: endedEarly, note: note)
        if let data = try? JSONEncoder.snapreel.encode(manifest) {
            try? data.write(to: InboxRecording.manifestURL(for: recordingID), options: .atomic)
        }
        writeState(.finished)
        notifyReady()
    }

    // MARK: - Shared state and notification

    private func writeState(_ status: BroadcastState.Status, message: String? = nil) {
        let state = BroadcastState(status: status,
                                   recordingID: recordingID,
                                   startedAt: startedAt,
                                   updatedAt: Date(),
                                   microphoneEnabled: writer?.microphoneHeard ?? false,
                                   errorMessage: message)
        BroadcastStateStore.write(state)
    }

    /// "Your screen recording is ready" with a tap that brings the person back to review.
    /// Respects the Recording saved toggle in Snapreel's notification settings.
    private func notifyReady() {
        let enabled = AppGroup.defaults.object(forKey: SharedDefaultsKey.notifyRecordingSaved) as? Bool ?? true
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Screen recording finished"
        content.body = "Your screen recording is ready. Tap to give it a title."
        content.sound = .default
        content.threadIdentifier = "recordingSaved"
        content.userInfo = ["kind": "recordingSaved", "broadcastID": recordingID.uuidString]
        let request = UNNotificationRequest(identifier: Self.notificationPrefix + recordingID.uuidString,
                                            content: content, trigger: nil)
        let done = DispatchSemaphore(value: 0)
        UNUserNotificationCenter.current().add(request) { _ in
            done.signal()
        }
        _ = done.wait(timeout: .now() + 2)
    }

    // MARK: - Helpers

    private static func freeSpace() -> Int64 {
        let values = try? AppGroup.containerURL.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        guard let available = values?.volumeAvailableCapacity else { return Int64.max }
        return Int64(available)
    }

    private static func error(_ code: RPRecordingErrorCode, _ message: String) -> NSError {
        NSError(domain: RPRecordingErrorDomain, code: code.rawValue,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static var savedMessage: NSError {
        NSError(domain: "co.arclayer.snapreel.broadcast", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Your recording is saved. Open Snapreel to give it a title."])
    }
}
