#if DEBUG
import Foundation

/// Lines a debug screen writes for CI: appended to Documents/debug-trace.txt while the app runs
/// a `-screen <id>` launch. The screenshot script collects them per screen into the artifacts'
/// `debug-trace.txt`, for values a screenshot can't show (sizes, offsets).
@MainActor
enum DebugTrace {
    static func log(_ line: @autoclosure () -> String) {
        guard AppEnvironment.shared.debugScreenID != nil else { return }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("debug-trace.txt")
        let data = Data((line() + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
#endif
