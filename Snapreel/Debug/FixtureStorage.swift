#if DEBUG
import AVFoundation
import UIKit

/// In-memory sample library for screenshots (DEBUG builds only; never in the shipped app).
/// Thumbnails and one short sample clip are drawn at launch into a temporary folder.
final class FixtureStorage: LibraryStorage {
    let mediaRoot: URL
    private var records: [String: [String: Data]] = [:]

    /// Bump when the drawn fixture media changes, so cached files are regenerated.
    private static let mediaVersion = 2

    init(set: FixtureSet) {
        // Media is drawn once per install and reused by every later launch (screenshots launch
        // the app ~100 times); records are rebuilt in memory each time.
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        mediaRoot = caches.appendingPathComponent("SnapreelFixtures-v\(Self.mediaVersion)", isDirectory: true)
        try? FileManager.default.createDirectory(at: mediaRoot, withIntermediateDirectories: true)
        if set == .filled { seed() }
    }

    func all<T: StoredRecord>(_ type: T.Type) throws -> [T] {
        (records[T.recordType] ?? [:]).values.compactMap { try? JSONDecoder.snapreel.decode(T.self, from: $0) }
    }

    func save<T: StoredRecord>(_ record: T) throws {
        records[T.recordType, default: [:]][record.recordID] = try JSONEncoder.snapreel.encode(record)
    }

    func delete<T: StoredRecord>(_ type: T.Type, id: String) throws {
        records[T.recordType]?[id] = nil
    }

    func eraseEverything() throws { records = [:] }  // media stays cached for the next launch

    // MARK: - Sample data

    /// Stable ids so debug screens can point at a specific video.
    enum IDs {
        static let checkout = UUID(uuidString: "11111111-0000-4000-8000-000000000001")!
        static let onboardingFeedback = UUID(uuidString: "11111111-0000-4000-8000-000000000002")!
        static let mapBug = UUID(uuidString: "11111111-0000-4000-8000-000000000003")!
        static let weeklyUpdate = UUID(uuidString: "11111111-0000-4000-8000-000000000004")!
        static let launchMemo = UUID(uuidString: "11111111-0000-4000-8000-000000000005")!
        static let shelf = UUID(uuidString: "11111111-0000-4000-8000-000000000006")!
        static let mitosis = UUID(uuidString: "11111111-0000-4000-8000-000000000007")!
        static let untitled = UUID(uuidString: "11111111-0000-4000-8000-000000000008")!
        static let product = UUID(uuidString: "22222222-0000-4000-8000-000000000001")!
        static let clients = UUID(uuidString: "22222222-0000-4000-8000-000000000002")!
        static let personal = UUID(uuidString: "22222222-0000-4000-8000-000000000003")!
    }

    private func seed() {
        let now = Date()
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        let media = MediaLocations(root: mediaRoot)

        let folders = [
            Folder(id: IDs.product, name: "Product", createdAt: ago(60 * 24 * 20), updatedAt: ago(130)),
            Folder(id: IDs.clients, name: "Clients", createdAt: ago(60 * 24 * 18), updatedAt: ago(300)),
            Folder(id: IDs.personal, name: "Personal", createdAt: ago(60 * 24 * 30), updatedAt: ago(60 * 24 * 6)),
        ]
        folders.forEach { try? save($0) }

        struct Sample {
            let id: UUID; let title: String; let kind: RecordingKind; let minutesAgo: Double
            let duration: Double; let size: (Int, Int); let folder: UUID?; let tags: [String]
            let watched: Double?; let watchLater: Double?; let plays: Int; let furthest: Double
            let shares: Int; let transcript: TranscriptStatus; let needsTitle: Bool; let style: FixtureArt.Style
        }
        let samples: [Sample] = [
            Sample(id: IDs.untitled, title: Format.defaultTitle(for: .screen, at: ago(4)), kind: .screen, minutesAgo: 4,
                   duration: 31, size: (886, 1920), folder: nil, tags: [], watched: nil, watchLater: nil, plays: 0,
                   furthest: 0, shares: 0, transcript: .inProgress, needsTitle: true, style: .phoneApp(hue: 0)),
            Sample(id: IDs.checkout, title: "Checkout flow walkthrough", kind: .screen, minutesAgo: 130,
                   duration: 125, size: (886, 1920), folder: IDs.product, tags: ["design", "checkout"], watched: 20,
                   watchLater: nil, plays: 3, furthest: 0.82, shares: 2, transcript: .ready, needsTitle: false,
                   style: .phoneApp(hue: 1)),
            Sample(id: IDs.onboardingFeedback, title: "Feedback on the onboarding copy", kind: .camera, minutesAgo: 300,
                   duration: 192, size: (1920, 1080), folder: IDs.clients, tags: ["feedback"], watched: nil,
                   watchLater: 45, plays: 0, furthest: 0, shares: 1, transcript: .ready, needsTitle: false,
                   style: .camera(hue: 0)),
            Sample(id: IDs.mapBug, title: "Bug: map pins jump on zoom", kind: .screen, minutesAgo: 60 * 26,
                   duration: 48, size: (886, 1920), folder: IDs.product, tags: ["bug"], watched: 60 * 20,
                   watchLater: nil, plays: 2, furthest: 1, shares: 3, transcript: .unavailable, needsTitle: false,
                   style: .phoneMap),
            Sample(id: IDs.weeklyUpdate, title: "Weekly update, week 47", kind: .camera, minutesAgo: 60 * 50,
                   duration: 280, size: (1080, 1920), folder: IDs.product, tags: ["update"], watched: nil,
                   watchLater: 60 * 30, plays: 0, furthest: 0, shares: 0, transcript: .ready, needsTitle: false,
                   style: .camera(hue: 1)),
            Sample(id: IDs.launchMemo, title: "Launch plan, voice memo", kind: .audio, minutesAgo: 60 * 75,
                   duration: 96, size: (0, 0), folder: nil, tags: ["ideas"], watched: 60 * 70, watchLater: nil,
                   plays: 1, furthest: 0.4, shares: 0, transcript: .ready, needsTitle: false, style: .phoneApp(hue: 2)),
            Sample(id: IDs.shelf, title: "Shelf install, step 2", kind: .camera, minutesAgo: 60 * 24 * 6,
                   duration: 362, size: (1920, 1080), folder: IDs.personal, tags: ["home"], watched: 60 * 24 * 5,
                   watchLater: nil, plays: 4, furthest: 1, shares: 1, transcript: .ready, needsTitle: false,
                   style: .camera(hue: 2)),
            Sample(id: IDs.mitosis, title: "Mitosis recap for Year 10", kind: .imported, minutesAgo: 60 * 24 * 9,
                   duration: 555, size: (1920, 1080), folder: nil, tags: ["school"], watched: nil, watchLater: nil,
                   plays: 0, furthest: 0, shares: 0, transcript: .notStarted, needsTitle: false, style: .slides),
        ]

        let clipName = "fixture-sample.mp4"
        if !FileManager.default.fileExists(atPath: media.videoURL(clipName).path) {
            FixtureArt.writeSampleClip(to: media.videoURL(clipName))
        }

        for sample in samples {
            var thumbName: String?
            if sample.kind != .audio {
                let name = sample.id.uuidString + ".jpg"
                if FileManager.default.fileExists(atPath: media.thumbnailURL(name).path) {
                    thumbName = name
                } else {
                    let image = FixtureArt.thumbnail(style: sample.style, portrait: sample.size.1 > sample.size.0)
                    thumbName = try? MediaInspector.writeThumbnail(image, named: sample.id.uuidString, in: media.thumbnails)
                }
            }
            let video = Video(id: sample.id, title: sample.title, createdAt: ago(sample.minutesAgo), kind: sample.kind,
                              fileName: clipName, thumbnailFileName: thumbName, duration: sample.duration,
                              fileSize: Int64(sample.duration * (sample.kind == .audio ? 16_000 : 1_400_000)),
                              pixelWidth: sample.size.0, pixelHeight: sample.size.1, needsTitle: sample.needsTitle,
                              folderID: sample.folder, tags: sample.tags,
                              watchLaterAddedAt: sample.watchLater.map(ago), lastWatchedAt: sample.watched.map(ago),
                              playCount: sample.plays, furthestProgress: sample.furthest, resumePosition: 0,
                              shareCount: sample.shares, photosSaveCount: sample.id == IDs.checkout ? 1 : 0,
                              transcriptStatus: sample.transcript, state: .ready)
            try? save(video)
        }

        // Notes and reactions on the checkout walkthrough.
        let notes: [(Double, String, Double)] = [
            (14, "Totals don't refresh after removing a coupon. Check the basket store.", 118),
            (41, "Address autocomplete feels fast, keep this.", 117),
            (82, "Ask Sam whether Apple Pay should come before card entry.", 116),
        ]
        for (time, text, minutes) in notes {
            try? save(VideoNote(videoID: IDs.checkout, time: time, text: text, createdAt: ago(minutes), updatedAt: ago(minutes)))
        }
        let reactions: [(Double, String)] = [(9, "👍"), (33, "🔥"), (65, "😮"), (110, "👏"), (14, "🤔")]
        for (time, emoji) in reactions {
            try? save(VideoReaction(videoID: IDs.checkout, time: time, emoji: emoji, createdAt: ago(110)))
        }

        // Transcripts.
        let checkoutLines = [
            "Okay, this is the new checkout on the staging build.",
            "I'm adding two items to the basket and going straight to checkout.",
            "Here's the coupon field. I'll apply the welcome code.",
            "If I remove it again, watch the total. It doesn't change, so that's a bug.",
            "Address autocomplete is really quick now, nice work on that.",
            "Payment comes next. Apple Pay sits under the card form at the moment.",
            "I think it should be first, but let's ask Sam.",
            "Last step is the summary. Everything else looks good to ship.",
        ]
        try? save(Transcript(videoID: IDs.checkout, localeIdentifier: "en-GB",
                             segments: FixtureArt.segments(checkoutLines, duration: 125),
                             createdAt: ago(125), summary: nil))
        let memoLines = [
            "Quick memo on the launch plan before I forget.",
            "Press goes out on the Tuesday, the store listing the day before.",
            "We need the screenshots and the short video by Friday.",
            "And I want one more pass on pricing with the team.",
        ]
        try? save(Transcript(videoID: IDs.launchMemo, localeIdentifier: "en-GB",
                             segments: FixtureArt.segments(memoLines, duration: 96),
                             createdAt: ago(60 * 74), summary: nil))
        for id in [IDs.onboardingFeedback, IDs.weeklyUpdate, IDs.shelf] {
            try? save(Transcript(videoID: id, localeIdentifier: "en-GB",
                                 segments: FixtureArt.segments(["Hi, a quick one about this.",
                                                                "Here is what I noticed and what I'd change."], duration: 60),
                                 createdAt: ago(60), summary: nil))
        }

        // Notification feed.
        let feed: [(NotificationKind, UUID?, String, String, Double, Bool)] = [
            (.recordingSaved, IDs.untitled, "Screen recording saved", "0:31 recording is in your library.", 3, false),
            (.needsTitle, IDs.untitled, "Your recording needs a title", "Name it so it's easy to find later.", 2, false),
            (.transcriptReady, IDs.checkout, "Transcript ready", "\u{201C}Checkout flow walkthrough\u{201D} can now be searched.", 120, false),
            (.recordingSaved, IDs.mapBug, "Screen recording saved", "\u{201C}Bug: map pins jump on zoom\u{201D}, 0:48.", 60 * 26, true),
            (.importFinished, IDs.mitosis, "Import finished", "\u{201C}Mitosis recap for Year 10\u{201D} was copied from Photos.", 60 * 24 * 9, true),
            (.storageLow, nil, "Your iPhone is almost full", "Less than 1 GB left. New recordings may not save.", 60 * 24 * 4, true),
        ]
        for (kind, video, title, body, minutes, read) in feed {
            try? save(AppNotification(kind: kind, videoID: video, title: title, body: body, createdAt: ago(minutes), isRead: read))
        }
    }
}

/// Drawn stand-ins for real recordings (DEBUG only).
enum FixtureArt {
    enum Style {
        case phoneApp(hue: Int)
        case phoneMap
        case camera(hue: Int)
        case slides
    }

    static func segments(_ lines: [String], duration: Double) -> [TranscriptSegment] {
        let step = duration / Double(max(1, lines.count))
        return lines.enumerated().map { index, text in
            TranscriptSegment(start: Double(index) * step, duration: step, text: text)
        }
    }

    /// Photographic stand-ins bundled in DEBUG builds only (Release excludes `fixture-*`).
    private static func photoName(for style: Style, portrait: Bool) -> String? {
        switch style {
        case .camera(let hue):
            if portrait || hue == 1 { return "fixture-camera-portrait" }
            return hue == 2 ? "fixture-camera-shelf" : "fixture-camera-desk"
        case .slides: return "fixture-slides"
        case .phoneApp, .phoneMap: return nil
        }
    }

    static func thumbnail(style: Style, portrait: Bool) -> UIImage {
        let size = portrait ? CGSize(width: 443, height: 960) : CGSize(width: 960, height: 540)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        if let name = photoName(for: style, portrait: portrait),
           let path = Bundle.main.path(forResource: name, ofType: "jpg"),
           let photo = UIImage(contentsOfFile: path) {
            // Aspect-fill the photo into the frame.
            return UIGraphicsImageRenderer(size: size, format: format).image { _ in
                let scale = max(size.width / photo.size.width, size.height / photo.size.height)
                let drawn = CGSize(width: photo.size.width * scale, height: photo.size.height * scale)
                photo.draw(in: CGRect(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2,
                                      width: drawn.width, height: drawn.height))
            }
        }
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            switch style {
            case .phoneApp(let hue): drawPhoneApp(cg, size: size, hue: hue)
            case .phoneMap: drawMap(cg, size: size)
            case .camera(let hue): drawCamera(cg, size: size, hue: hue)
            case .slides: drawSlides(cg, size: size)
            }
        }
    }

    private static let accents: [UIColor] = [
        UIColor(red: 0.94, green: 0.28, blue: 0.31, alpha: 1),
        UIColor(red: 0.22, green: 0.24, blue: 0.32, alpha: 1),
        UIColor(red: 0.85, green: 0.62, blue: 0.36, alpha: 1),
    ]

    private static func rounded(_ cg: CGContext, _ rect: CGRect, _ radius: CGFloat, _ color: UIColor) {
        cg.setFillColor(color.cgColor)
        cg.addPath(UIBezierPath(roundedRect: rect, cornerRadius: radius).cgPath)
        cg.fillPath()
    }

    private static func drawPhoneApp(_ cg: CGContext, size: CGSize, hue: Int) {
        let w = size.width, h = size.height
        rounded(cg, CGRect(origin: .zero, size: size), 0, UIColor(white: 0.97, alpha: 1))
        let accent = accents[hue % accents.count]
        rounded(cg, CGRect(x: w * 0.06, y: h * 0.06, width: w * 0.5, height: h * 0.035), 8, UIColor(white: 0.12, alpha: 1))
        rounded(cg, CGRect(x: w * 0.06, y: h * 0.12, width: w * 0.88, height: h * 0.22), 22, accent.withAlphaComponent(0.9))
        for row in 0..<4 {
            let y = h * (0.38 + CGFloat(row) * 0.105)
            rounded(cg, CGRect(x: w * 0.06, y: y, width: w * 0.88, height: h * 0.085), 16, .white)
            rounded(cg, CGRect(x: w * 0.1, y: y + h * 0.018, width: h * 0.05, height: h * 0.05), 12, accent.withAlphaComponent(0.25))
            rounded(cg, CGRect(x: w * 0.1 + h * 0.07, y: y + h * 0.022, width: w * 0.45, height: h * 0.016), 6, UIColor(white: 0.2, alpha: 1))
            rounded(cg, CGRect(x: w * 0.1 + h * 0.07, y: y + h * 0.048, width: w * 0.3, height: h * 0.012), 6, UIColor(white: 0.7, alpha: 1))
        }
        rounded(cg, CGRect(x: w * 0.06, y: h * 0.86, width: w * 0.88, height: h * 0.07), h * 0.035, UIColor(white: 0.1, alpha: 1))
        // Tap indicator
        cg.setFillColor(UIColor(white: 0.5, alpha: 0.35).cgColor)
        cg.fillEllipse(in: CGRect(x: w * 0.62, y: h * 0.46, width: w * 0.14, height: w * 0.14))
    }

    private static func drawMap(_ cg: CGContext, size: CGSize) {
        let w = size.width, h = size.height
        rounded(cg, CGRect(origin: .zero, size: size), 0, UIColor(red: 0.91, green: 0.93, blue: 0.89, alpha: 1))
        cg.setStrokeColor(UIColor.white.cgColor)
        cg.setLineWidth(w * 0.04)
        for i in 0..<5 {
            cg.move(to: CGPoint(x: 0, y: h * (0.15 + CGFloat(i) * 0.18)))
            cg.addLine(to: CGPoint(x: w, y: h * (0.05 + CGFloat(i) * 0.2)))
        }
        cg.move(to: CGPoint(x: w * 0.3, y: 0)); cg.addLine(to: CGPoint(x: w * 0.45, y: h))
        cg.move(to: CGPoint(x: w * 0.75, y: 0)); cg.addLine(to: CGPoint(x: w * 0.62, y: h))
        cg.strokePath()
        rounded(cg, CGRect(x: w * 0.55, y: h * 0.25, width: w * 0.3, height: h * 0.12), 20, UIColor(red: 0.78, green: 0.88, blue: 0.95, alpha: 1))
        for (x, y) in [(0.25, 0.4), (0.6, 0.55), (0.42, 0.68)] {
            cg.setFillColor(accents[0].cgColor)
            cg.fillEllipse(in: CGRect(x: w * x, y: h * y, width: w * 0.09, height: w * 0.09))
        }
        rounded(cg, CGRect(x: w * 0.06, y: h * 0.06, width: w * 0.88, height: h * 0.06), h * 0.03, .white)
    }

    private static func drawCamera(_ cg: CGContext, size: CGSize, hue: Int) {
        let w = size.width, h = size.height
        let palettes: [[UIColor]] = [
            [UIColor(red: 0.36, green: 0.30, blue: 0.27, alpha: 1), UIColor(red: 0.74, green: 0.62, blue: 0.52, alpha: 1)],
            [UIColor(red: 0.20, green: 0.24, blue: 0.30, alpha: 1), UIColor(red: 0.55, green: 0.62, blue: 0.68, alpha: 1)],
            [UIColor(red: 0.42, green: 0.36, blue: 0.24, alpha: 1), UIColor(red: 0.86, green: 0.78, blue: 0.62, alpha: 1)],
        ]
        let colors = palettes[hue % palettes.count]
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [colors[1].cgColor, colors[0].cgColor] as CFArray, locations: [0, 1])!
        cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: w, y: h), options: [])
        // Window light and a soft figure.
        rounded(cg, CGRect(x: w * 0.08, y: h * 0.1, width: w * 0.22, height: h * 0.5), 12, UIColor.white.withAlphaComponent(0.18))
        let cx = w * 0.55, cy = h * 0.42, r = min(w, h) * 0.17
        cg.setFillColor(UIColor(red: 0.55, green: 0.38, blue: 0.30, alpha: 1).cgColor)
        cg.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2.15))
        cg.setFillColor(UIColor(red: 0.16, green: 0.13, blue: 0.13, alpha: 1).cgColor)
        cg.fillEllipse(in: CGRect(x: cx - r * 1.05, y: cy - r * 1.15, width: r * 2.1, height: r * 1.1))
        rounded(cg, CGRect(x: cx - r * 2, y: cy + r * 1.3, width: r * 4, height: h), r * 1.4,
                UIColor(red: 0.94, green: 0.28, blue: 0.31, alpha: 0.9))
    }

    private static func drawSlides(_ cg: CGContext, size: CGSize) {
        let w = size.width, h = size.height
        rounded(cg, CGRect(origin: .zero, size: size), 0, UIColor(red: 0.99, green: 0.98, blue: 0.96, alpha: 1))
        rounded(cg, CGRect(x: w * 0.06, y: h * 0.1, width: w * 0.5, height: h * 0.07), 8, UIColor(white: 0.15, alpha: 1))
        for i in 0..<4 {
            let x = w * (0.1 + CGFloat(i) * 0.21)
            cg.setStrokeColor(UIColor(red: 0.85, green: 0.62, blue: 0.36, alpha: 1).cgColor)
            cg.setLineWidth(5)
            cg.strokeEllipse(in: CGRect(x: x, y: h * 0.35, width: w * 0.15, height: w * 0.15))
            cg.setFillColor(UIColor(red: 0.94, green: 0.28, blue: 0.31, alpha: 0.85).cgColor)
            cg.fillEllipse(in: CGRect(x: x + w * 0.05, y: h * 0.35 + w * 0.05, width: w * 0.05, height: w * 0.05))
        }
        rounded(cg, CGRect(x: w * 0.1, y: h * 0.78, width: w * 0.62, height: h * 0.035), 6, UIColor(white: 0.6, alpha: 1))
    }

    /// A 6-second 640x360 clip so the player has something real to play in screenshots.
    static func writeSampleClip(to url: URL) {
        try? FileManager.default.removeItem(at: url)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return }
        let width = 640, height = 360, fps: Int32 = 30, seconds = 6
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.canAdd(input) else { return }
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        let frame = thumbnail(style: .slides, portrait: false).cgImage
        for index in 0..<(Int(fps) * seconds) {
            while !input.isReadyForMoreMediaData { usleep(1000) }
            guard let pool = adaptor.pixelBufferPool else { break }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { continue }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
                                       bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                       space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                if let frame { context.draw(frame, in: CGRect(x: 0, y: 0, width: width, height: height)) }
                let progress = CGFloat(index) / CGFloat(Int(fps) * seconds)
                context.setFillColor(UIColor(red: 0.94, green: 0.28, blue: 0.31, alpha: 1).cgColor)
                context.fillEllipse(in: CGRect(x: 40 + progress * CGFloat(width - 120), y: 60, width: 40, height: 40))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: fps))
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
    }
}
#endif
