import XCTest
@testable import Snapreel

/// Measures what iOS's background session does with many transfers handed over at once: how many it sends at a time,
/// and whether it keeps the limit of three on HTTP/2, where they share one connection. Runs only with PROBE_URL (CI starts
/// scripts/h2-probe-server.mjs for it), and reports rather than fails.
@MainActor
final class BackgroundSessionProbe: XCTestCase {
    func testManyTransfersAtOnce() async throws {
        guard let text = ProcessInfo.processInfo.environment["PROBE_URL"], let url = URL(string: text) else { throw XCTSkip("PROBE_URL isn't set") }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("probe", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let transfers = BackgroundTransfers(identifier: "co.arclayer.snapreel.probe.\(UUID().uuidString)")
        var ended: [(number: Int64, status: Int, error: String?)] = []
        transfers.onFinish = { tag, result in
            ended.append((tag.number, result.status, result.error.map { "\($0)" }))
        }
        let id = UUID()
        let count = 20
        for number in 1...count {
            let tag = TransferTag(videoID: id, part: .video, number: Int64(number), lane: "probe")
            let file = folder.appendingPathComponent(tag.fileName)
            try UploaderTests.noise(2_000_000).write(to: file)
            var request = URLRequest(url: url.appendingPathComponent("piece/\(number)"))
            request.httpMethod = "PUT"
            transfers.start(request, file: file, tag: tag)
        }
        let deadline = Date().addingTimeInterval(240)
        while ended.count < count && Date() < deadline { try await Task.sleep(nanoseconds: 200_000_000) }
        let (data, _) = try await URLSession.shared.data(from: url.appendingPathComponent("report"))
        let order = ended.map { "\($0.number)" }.joined(separator: " ")
        print("PERF|background session: ended \(ended.count)/\(count), statuses \(Set(ended.map(\.status))), errors \(Set(ended.compactMap(\.error)))")
        print("PERF|background session order: \(order)")
        print("PERF|background session server: \(String(decoding: data, as: UTF8.self))")
        transfers.cancel(id)
    }
}
