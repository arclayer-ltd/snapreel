import SwiftUI

/// A small block-level Markdown reader for the bundled legal documents: `#` title, `##` and
/// `###` headings, `-` bullets, `1.` numbered items, paragraphs, and a "Last updated:" line.
/// Inline Markdown (bold, italic, links) is handled by `AttributedString`.
enum LegalText {
    enum Block: Hashable {
        case title(String)
        case updated(String)
        case heading(String)
        case subheading(String)
        case paragraph(String)
        case bullet(String)
        case numbered(Int, String)
    }

    static func load(_ document: LegalDocument, bundle: Bundle = .main) -> [Block]? {
        guard let url = bundle.url(forResource: document.resourceName, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let blocks = parse(text)
        return blocks.isEmpty ? nil : blocks
    }

    static func parse(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []

        func flush() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph = []
            }
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("<!--") {
                flush()
            } else if line.hasPrefix("### ") {
                flush()
                blocks.append(.subheading(String(line.dropFirst(4))))
            } else if line.hasPrefix("## ") {
                flush()
                blocks.append(.heading(String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                flush()
                blocks.append(.title(String(line.dropFirst(2))))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flush()
                blocks.append(.bullet(String(line.dropFirst(2))))
            } else if let item = numberedItem(line) {
                flush()
                blocks.append(.numbered(item.number, item.text))
            } else if line.lowercased().hasPrefix("last updated:") {
                flush()
                let date = line.dropFirst("last updated:".count).trimmingCharacters(in: .whitespaces)
                blocks.append(.updated(date))
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return blocks
    }

    /// "12. Text" → (12, "Text").
    private static func numberedItem(_ line: String) -> (number: Int, text: String)? {
        let digits = line.prefix(while: { $0.isNumber })
        guard !digits.isEmpty, let number = Int(digits) else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") else { return nil }
        return (number: number, text: String(rest.dropFirst(2)))
    }

    /// The document as plain text, for sharing.
    static func plainText(_ blocks: [Block]) -> String {
        blocks.map { block -> String in
            switch block {
            case .title(let text): return strip(text) + "\n"
            case .updated(let date): return "Last updated: \(date)\n"
            case .heading(let text), .subheading(let text): return "\n" + strip(text)
            case .paragraph(let text): return strip(text) + "\n"
            case .bullet(let text): return "• " + strip(text)
            case .numbered(let number, let text): return "\(number). " + strip(text)
            }
        }
        .joined(separator: "\n")
    }

    /// Inline Markdown reduced to its characters ("**No account**" → "No account").
    static func strip(_ text: String) -> String {
        String(RichText.inline(text).characters)
    }
}

/// Native viewer for a bundled legal document: title, "Last updated", headings, paragraphs and
/// lists, with a share button for the plain text.
struct LegalDocumentView: View {
    let document: LegalDocument

    @State private var blocks: [LegalText.Block]?
    @State private var loaded = false

    init(document: LegalDocument) {
        self.document = document
    }

    var body: some View {
        Group {
            if let blocks {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.m) {
                        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                            LegalBlockView(block: block)
                        }
                    }
                    .padding(.horizontal, Space.gutter)
                    .padding(.top, Space.s)
                    .padding(.bottom, Space.xxxl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if loaded {
                EmptyStateView(systemImage: "doc.questionmark",
                               title: "\(document.title) isn't available",
                               message: "It couldn't be opened. Write to \(AppInfo.supportEmail) and we'll send you a copy.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
            }
        }
        .background(Color.srSurface.ignoresSafeArea())
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let blocks {
                    ShareLink(item: LegalText.plainText(blocks), subject: Text(document.title)) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .accessibilityLabel("Share \(document.title)")
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            blocks = LegalText.load(document)
            loaded = true
        }
    }
}

/// One block of a legal document.
struct LegalBlockView: View {
    let block: LegalText.Block

    var body: some View {
        switch block {
        case .title(let text):
            Text(text)
                .font(.srDisplay)
                .foregroundStyle(Color.srText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        case .updated(let date):
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .semibold))
                Text("Last updated \(date)")
                    .font(.srCaption)
            }
            .foregroundStyle(Color.srTextSecondary)
            .padding(.horizontal, Space.s)
            .frame(height: 28)
            .background(Capsule().fill(Color.srFill))
            .padding(.bottom, Space.xs)
            .accessibilityElement(children: .combine)
        case .heading(let text):
            Text(RichText.inline(text))
                .font(.srTitle3)
                .foregroundStyle(Color.srText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.s)
                .accessibilityAddTraits(.isHeader)
        case .subheading(let text):
            Text(RichText.inline(text))
                .font(.srHeadline)
                .foregroundStyle(Color.srText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.xxs)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let text):
            Text(RichText.inline(text))
                .font(.srBody)
                .foregroundStyle(Color.srTextSecondary)
                .lineSpacing(4)
                .tint(Color.srRed)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let text):
            listItem(marker: "•", text: text)
        case .numbered(let number, let text):
            listItem(marker: "\(number).", text: text)
        }
    }

    private func listItem(marker: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text(marker)
                .font(.srBody)
                .foregroundStyle(Color.srRed)
                .frame(minWidth: 14, alignment: .leading)
                .accessibilityHidden(true)
            Text(RichText.inline(text))
                .font(.srBody)
                .foregroundStyle(Color.srTextSecondary)
                .lineSpacing(4)
                .tint(Color.srRed)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, Space.xxs)
    }
}
