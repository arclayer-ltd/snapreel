import SwiftUI

/// Help centre: live search, suggestions for the person's use case, and every category with its
/// articles ("See all" opens a category up). Pushed inside the Settings NavigationStack.
struct HelpCenterView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var query: String
    @State private var expanded: Set<String>
    @FocusState private var searchFocused: Bool

    private let help = HelpLibrary.shared
    /// Articles shown per category before "See all".
    private let previewCount = 3

    init(initialQuery: String = "", expandedCategories: Set<String> = []) {
        _query = State(initialValue: initialQuery)
        var opened = expandedCategories
        #if DEBUG
        if let debugOpened = HelpCenterDebug.expanded { opened = debugOpened }
        #endif
        _expanded = State(initialValue: opened)
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                if trimmedQuery.isEmpty {
                    browse
                } else {
                    results
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.s)
            .padding(.bottom, Space.xxl)
        }
        .scrollDismissesKeyboard(.immediately)
        .safeAreaInset(edge: .top, spacing: 0) { searchBar }
        .background(Color.srCanvas.ignoresSafeArea())
        .navigationTitle("Help centre")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(value: SettingsPage.contact(nil)) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 17, weight: .semibold))
                }
                .accessibilityLabel("Contact support")
            }
        }
    }

    /// "1 article", "4 articles"
    static func articleCount(_ count: Int) -> String {
        count == 1 ? "1 article" : "\(count) articles"
    }

    // MARK: Search

    private var searchBar: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.srTextTertiary)
            TextField("Search help", text: $query)
                .font(.srBody)
                .foregroundStyle(Color.srText)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.srTextTertiary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Space.s)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Color.srFill))
        .padding(.horizontal, Space.gutter)
        .padding(.vertical, Space.xs)
        .background(Color.srCanvas)
    }

    // MARK: Browse

    @ViewBuilder private var browse: some View {
        if help.isEmpty {
            EmptyStateView(systemImage: "book.closed",
                           title: "Help isn't available",
                           message: "The help articles couldn't be loaded. You can still write to us.")
                .padding(.top, Space.xxl)
        } else {
            if let useCase = settings.useCase {
                let suggestions = help.suggested(for: useCase)
                if !suggestions.isEmpty {
                    suggestedSection(useCase: useCase, articles: suggestions)
                }
            }
            ForEach(help.categories) { category in
                categorySection(category)
            }
        }
        stillStuck
    }

    private func suggestedSection(useCase: UseCase, articles: [HelpArticle]) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                Image(systemName: useCase.systemImage)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.srRed)
                Text("Suggested for you")
                    .font(.srHeadline)
                    .foregroundStyle(Color.srText)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(articles.enumerated()), id: \.element.id) { offset, article in
                    if offset > 0 { SettingsDivider(inset: Space.m) }
                    HelpArticleRow(article: article, showsSummary: true)
                }
            }
            .srCard()
            .clipShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        }
    }

    private func categorySection(_ category: HelpCategory) -> some View {
        let all = help.articles(in: category.id)
        let isExpanded = expanded.contains(category.id)
        let shown = isExpanded ? all : Array(all.prefix(previewCount))
        return VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.s) {
                IconTile(systemName: category.systemImage, size: 28)
                Text(category.title)
                    .font(.srHeadline)
                    .foregroundStyle(Color.srText)
                Spacer()
                Text(HelpCenterView.articleCount(all.count))
                    .font(.srFootnote)
                    .foregroundStyle(Color.srTextTertiary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { offset, article in
                    if offset > 0 { SettingsDivider(inset: Space.m) }
                    HelpArticleRow(article: article, showsSummary: false)
                }
                if all.count > previewCount {
                    SettingsDivider(inset: Space.m)
                    seeAllButton(category: category, total: all.count, isExpanded: isExpanded)
                }
            }
            .srCard()
            .clipShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        }
    }

    private func toggleExpanded(_ categoryID: String) {
        if expanded.contains(categoryID) {
            expanded.remove(categoryID)
        } else {
            expanded.insert(categoryID)
        }
    }

    private func seeAllButton(category: HelpCategory, total: Int, isExpanded: Bool) -> some View {
        Button {
            Haptics.selection()
            withAnimation(Motion.standard) {
                toggleExpanded(category.id)
            }
        } label: {
            HStack(spacing: 6) {
                Text(isExpanded ? String("Show fewer") : String("See all \(total) articles"))
                    .font(.srSubheadlineStrong)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                Spacer()
            }
            .foregroundStyle(Color.srRed)
            .padding(.horizontal, Space.m)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsRowStyle())
        .accessibilityLabel(Text(isExpanded ? String("Show fewer \(category.title) articles") : String("See all \(total) \(category.title) articles")))
    }

    private var stillStuck: some View {
        HStack(alignment: .center, spacing: Space.m) {
            IconTile(systemName: "envelope.fill", size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Still need a hand?")
                    .font(.srHeadline)
                    .foregroundStyle(Color.srText)
                Text("Write to us and we'll reply by email.")
                    .font(.srFootnote)
                    .foregroundStyle(Color.srTextSecondary)
            }
            Spacer(minLength: Space.xs)
            NavigationLink(value: SettingsPage.contact(nil)) {
                Text("Contact")
            }
            .buttonStyle(.srSecondaryCompact)
        }
        .padding(Space.m)
        .srCard()
    }

    // MARK: Results

    @ViewBuilder private var results: some View {
        let found = help.search(trimmedQuery)
        if found.isEmpty {
            EmptyStateView(systemImage: "magnifyingglass",
                           title: "Nothing matches “\(trimmedQuery)”",
                           message: "Try another word, such as microphone, folder or share. Or ask us directly.")
                .padding(.top, Space.xxl)
            NavigationLink(value: SettingsPage.contact(nil)) {
                Text("Contact support")
            }
            .buttonStyle(.srPrimaryCompact)
            .frame(maxWidth: .infinity)
        } else {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(HelpCenterView.articleCount(found.count))
                    .font(.srFootnote)
                    .foregroundStyle(Color.srTextTertiary)
                    .padding(.horizontal, Space.xxs)
                VStack(spacing: 0) {
                    ForEach(Array(found.enumerated()), id: \.element.id) { offset, article in
                        if offset > 0 { SettingsDivider(inset: Space.m) }
                        HelpArticleRow(article: article, showsSummary: true, highlight: trimmedQuery,
                                       categoryTitle: help.category(article.category)?.title)
                    }
                }
                .srCard()
                .clipShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
            }
        }
    }
}

#if DEBUG
/// Lets a debug entry open the help centre with categories already opened up.
enum HelpCenterDebug {
    @MainActor static var expanded: Set<String>? = nil
}
#endif

/// One article in a list: title, optional category and summary, chevron.
struct HelpArticleRow: View {
    let article: HelpArticle
    var showsSummary = false
    var highlight: String? = nil
    var categoryTitle: String? = nil

    var body: some View {
        NavigationLink(value: SettingsPage.helpArticle(article.id)) {
            HStack(spacing: Space.s) {
                VStack(alignment: .leading, spacing: 3) {
                    if let categoryTitle {
                        Text(categoryTitle)
                            .font(.srCaption)
                            .foregroundStyle(Color.srTextTertiary)
                    }
                    title
                        .font(.srBody)
                        .foregroundStyle(Color.srText)
                        .multilineTextAlignment(.leading)
                    if showsSummary {
                        Text(article.summary)
                            .font(.srFootnote)
                            .foregroundStyle(Color.srTextSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.srTextTertiary)
            }
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsRowStyle())
    }

    private var title: Text {
        if let highlight, !highlight.isEmpty {
            return Text(RichText.highlighted(article.title, query: highlight))
        }
        return Text(article.title)
    }
}
