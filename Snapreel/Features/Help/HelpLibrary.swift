import Foundation
import SwiftUI

/// A group of help articles ("Recording", "Troubleshooting").
struct HelpCategory: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let systemImage: String
}

/// One block of an article body.
struct HelpBlock: Decodable, Hashable {
    enum Kind: String, Decodable {
        case paragraph
        case heading
        case steps
        case bullets
        case tip
    }

    let type: Kind
    let text: String?
    let items: [String]?
}

/// A help article, bundled in `help-articles.json`. Text may use inline Markdown (**bold**, *italic*).
struct HelpArticle: Decodable, Identifiable, Hashable {
    let id: String
    let category: String
    let title: String
    let summary: String
    let body: [HelpBlock]
    let related: [String]?
    /// `UseCase` raw values this article is suggested for in the help centre.
    let useCases: [String]?

    /// Everything readable in the article, for search.
    var plainText: String {
        var parts: [String] = [title, summary]
        for block in body {
            if let text = block.text { parts.append(text) }
            if let items = block.items { parts.append(contentsOf: items) }
        }
        return parts.joined(separator: " ").replacingOccurrences(of: "*", with: "")
    }
}

private struct HelpContent: Decodable {
    let categories: [HelpCategory]
    let articles: [HelpArticle]
}

/// The bundled help centre: categories, articles and an in-memory search.
struct HelpLibrary {
    static let shared = HelpLibrary.load()

    let categories: [HelpCategory]
    let articles: [HelpArticle]
    /// Article id → folded searchable text.
    private let searchIndex: [String: String]
    private let titleIndex: [String: String]

    init(categories: [HelpCategory], articles: [HelpArticle]) {
        self.categories = categories
        self.articles = articles
        var index: [String: String] = [:]
        var titles: [String: String] = [:]
        for article in articles {
            index[article.id] = HelpLibrary.fold(article.plainText)
            titles[article.id] = HelpLibrary.fold(article.title)
        }
        searchIndex = index
        titleIndex = titles
    }

    static func load(bundle: Bundle = .main) -> HelpLibrary {
        guard let url = bundle.url(forResource: "help-articles", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let content = try? JSONDecoder().decode(HelpContent.self, from: data) else {
            return HelpLibrary(categories: [], articles: [])
        }
        let known = Set(content.categories.map(\.id))
        return HelpLibrary(categories: content.categories,
                           articles: content.articles.filter { known.contains($0.category) })
    }

    // MARK: Queries

    var isEmpty: Bool { articles.isEmpty }

    func article(_ id: String) -> HelpArticle? { articles.first { $0.id == id } }

    func category(_ id: String) -> HelpCategory? { categories.first { $0.id == id } }

    func articles(in categoryID: String) -> [HelpArticle] {
        articles.filter { $0.category == categoryID }
    }

    func related(to article: HelpArticle) -> [HelpArticle] {
        (article.related ?? []).compactMap { self.article($0) }
    }

    /// Articles suggested for what the person said they'd use Snapreel for.
    func suggested(for useCase: UseCase, limit: Int = 3) -> [HelpArticle] {
        Array(articles.filter { ($0.useCases ?? []).contains(useCase.rawValue) }.prefix(limit))
    }

    /// Every word of the query must appear somewhere in the article (case and accent
    /// insensitive). Title matches come first.
    func search(_ query: String) -> [HelpArticle] {
        let words = HelpLibrary.fold(query)
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map(String.init)
        guard !words.isEmpty else { return [] }
        var scored: [(article: HelpArticle, score: Int, order: Int)] = []
        for (order, article) in articles.enumerated() {
            guard let text = searchIndex[article.id],
                  words.allSatisfy({ text.contains($0) }) else { continue }
            let title = titleIndex[article.id] ?? ""
            let titleHits = words.filter { title.contains($0) }.count
            scored.append((article: article, score: titleHits, order: order))
        }
        scored.sort { lhs, rhs in
            lhs.score != rhs.score ? lhs.score > rhs.score : lhs.order < rhs.order
        }
        return scored.map { $0.article }
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

// MARK: - Text helpers shared by help and legal

enum RichText {
    /// Inline Markdown (bold, italic, links) as an AttributedString; plain text if it doesn't parse.
    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    /// `text` with every case- and accent-insensitive occurrence of the query's words tinted red.
    static func highlighted(_ text: String, query: String) -> AttributedString {
        var attributed = AttributedString(text)
        let words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init).filter { !$0.isEmpty }
        for word in words {
            var searchRange = attributed.startIndex..<attributed.endIndex
            while let found = attributed[searchRange].range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) {
                attributed[found].foregroundColor = Color.srRed
                searchRange = found.upperBound..<attributed.endIndex
            }
        }
        return attributed
    }
}
