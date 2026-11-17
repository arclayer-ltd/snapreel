import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A two-to-three sentence summary of a transcript, written by Apple's on-device language model
/// (Apple Intelligence, iOS 26 or later on supported iPhones). Everywhere else `isAvailable` is
/// false, `summary(of:)` returns nil and the player shows no summary block. Never faked.
enum OnDeviceSummarizer {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// Nil when the model isn't available on this iPhone, can't handle the language, or fails.
    static func summary(of lines: [String]) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await generate(from: lines)
        }
        #endif
        return nil
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func generate(from lines: [String]) async -> String? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let session = LanguageModelSession(instructions: "You summarise transcripts of short screen, camera and voice recordings. Reply with two or three plain sentences in the same language as the transcript. Describe only what the speaker says. No title, no lists, no quotation marks.")
        let prompt: String = "Summarise this transcript:\n\n" + excerpt(from: lines, limit: 6000)
        do {
            let response = try await session.respond(to: prompt)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }
    #endif

    /// Keeps long transcripts inside the model's context: evenly spaced lines up to `limit`
    /// characters, in order.
    static func excerpt(from lines: [String], limit: Int) -> String {
        let total = lines.reduce(0) { $0 + $1.count + 1 }
        guard total > limit, !lines.isEmpty else { return lines.joined(separator: "\n") }
        let keepRatio = Double(limit) / Double(total)
        var kept: [String] = []
        var budget = 0.0
        var used = 0
        for line in lines {
            budget += keepRatio
            if budget >= 1, used + line.count + 1 <= limit {
                kept.append(line)
                used += line.count + 1
                budget -= 1
            }
        }
        return kept.joined(separator: "\n")
    }
}
