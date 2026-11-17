import SwiftUI

/// Whether an article helped. Kept on this iPhone only; nothing is sent anywhere.
enum HelpFeedback: String {
    case helpful
    case notHelpful
}

/// A native help article: category, title, summary, the body (paragraphs, headings, steps,
/// bullets, tips), "Was this helpful?", related articles and a way to contact support.
struct HelpArticleView: View {
    let articleID: String

    @EnvironmentObject private var settings: AppSettings
    @State private var feedback: HelpFeedback?

    private let help = HelpLibrary.shared

    init(articleID: String) {
        self.articleID = articleID
    }

    var body: some View {
        Group {
            if let article = help.article(articleID) {
                content(article)
            } else {
                EmptyStateView(systemImage: "doc.questionmark",
                               title: "This article isn't here",
                               message: "It may have moved. Search the help centre or write to us.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.srCanvas.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadFeedback() }
    }

    private func content(_ article: HelpArticle) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                header(article)
                VStack(alignment: .leading, spacing: Space.m) {
                    ForEach(Array(article.body.enumerated()), id: \.offset) { _, block in
                        HelpBlockView(block: block)
                    }
                }
                feedbackCard
                relatedSection(article)
                contactRow(article)
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.s)
            .padding(.bottom, Space.xxl)
        }
    }

    private func header(_ article: HelpArticle) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if let category = help.category(article.category) {
                HStack(spacing: 6) {
                    Image(systemName: category.systemImage)
                        .font(.system(size: 12, weight: .bold))
                    Text(category.title.uppercased())
                        .font(.srCaption)
                        .kerning(0.8)
                }
                .foregroundStyle(Color.srRed)
            }
            Text(article.title)
                .font(.srDisplay)
                .foregroundStyle(Color.srText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(article.summary)
                .font(.srCallout)
                .foregroundStyle(Color.srTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Feedback

    private var feedbackCard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if let feedback {
                HStack(alignment: .top, spacing: Space.s) {
                    Image(systemName: feedback == .helpful ? "hand.thumbsup.fill" : "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.srRed)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feedback == .helpful ? "Glad it helped" : "Sorry it didn't help")
                            .font(.srHeadline)
                            .foregroundStyle(Color.srText)
                        Text(feedback == .helpful
                             ? "Thanks for letting us know."
                             : "Tell us what you were trying to do and we'll answer by email.")
                            .font(.srFootnote)
                            .foregroundStyle(Color.srTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button("Change") { setFeedback(nil) }
                        .font(.srFootnote)
                        .foregroundStyle(Color.srTextTertiary)
                        .accessibilityLabel("Change your answer")
                }
                .transition(.opacity)
            } else {
                Text("Was this helpful?")
                    .font(.srHeadline)
                    .foregroundStyle(Color.srText)
                HStack(spacing: Space.s) {
                    feedbackButton(.helpful, title: "Yes", systemImage: "hand.thumbsup")
                    feedbackButton(.notHelpful, title: "No", systemImage: "hand.thumbsdown")
                }
                .transition(.opacity)
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srCard()
        .animation(Motion.standard, value: feedback)
    }

    private func feedbackButton(_ value: HelpFeedback, title: String, systemImage: String) -> some View {
        Button {
            setFeedback(value)
        } label: {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.srSecondaryCompact)
    }

    private var feedbackKey: String { "help.feedback.\(articleID)" }

    private func loadFeedback() {
        feedback = settings.defaults.string(forKey: feedbackKey).flatMap(HelpFeedback.init(rawValue:))
    }

    private func setFeedback(_ value: HelpFeedback?) {
        if value != nil { Haptics.success() } else { Haptics.tap() }
        feedback = value
        settings.defaults.set(value?.rawValue, forKey: feedbackKey)
    }

    // MARK: Related and contact

    @ViewBuilder private func relatedSection(_ article: HelpArticle) -> some View {
        let related = help.related(to: article)
        if !related.isEmpty {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Related")
                    .font(.srHeadline)
                    .foregroundStyle(Color.srText)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    ForEach(Array(related.enumerated()), id: \.element.id) { offset, item in
                        if offset > 0 { SettingsDivider(inset: Space.m) }
                        HelpArticleRow(article: item, showsSummary: true)
                    }
                }
                .srCard()
                .clipShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
            }
        }
    }

    private func contactRow(_ article: HelpArticle) -> some View {
        NavigationLink(value: SettingsPage.contact(SupportTopic.suggested(forCategory: article.category))) {
            HStack(spacing: Space.s) {
                IconTile(systemName: "envelope.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Still stuck?")
                        .font(.srBody)
                        .foregroundStyle(Color.srText)
                    Text("Contact support")
                        .font(.srFootnote)
                        .foregroundStyle(Color.srRed)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.srTextTertiary)
            }
            .padding(Space.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsRowStyle())
        .srCard()
        .clipShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
    }
}

/// Renders one block of an article.
struct HelpBlockView: View {
    let block: HelpBlock

    var body: some View {
        switch block.type {
        case .paragraph:
            Text(RichText.inline(block.text ?? ""))
                .font(.srBody)
                .foregroundStyle(Color.srText)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        case .heading:
            Text(block.text ?? "")
                .font(.srTitle3)
                .foregroundStyle(Color.srText)
                .padding(.top, Space.xs)
                .accessibilityAddTraits(.isHeader)
        case .steps:
            steps
        case .bullets:
            bullets
        case .tip:
            tip
        }
    }

    private var items: [String] { block.items ?? [] }

    private var steps: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: Space.s) {
                    Text("\(index + 1)")
                        .font(.srTimerSmall)
                        .foregroundStyle(Color.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.srRed))
                        .accessibilityHidden(true)
                    Text(RichText.inline(item))
                        .font(.srBody)
                        .foregroundStyle(Color.srText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 1)
                        .accessibilityLabel(Text("Step \(index + 1). ") + Text(RichText.inline(item)))
                }
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srCard()
    }

    private var bullets: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text("•")
                        .font(.srBody)
                        .foregroundStyle(Color.srRed)
                        .accessibilityHidden(true)
                    Text(RichText.inline(item))
                        .font(.srBody)
                        .foregroundStyle(Color.srText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var tip: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.srRed)
                .padding(.top, 2)
                .accessibilityHidden(true)
            Text(RichText.inline(block.text ?? ""))
                .font(.srCallout)
                .foregroundStyle(Color.srText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.srRedSoft))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Tip. ") + Text(RichText.inline(block.text ?? "")))
    }
}
