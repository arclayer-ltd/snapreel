import SwiftUI

/// Every reaction, from Snapreel's own list: search by name, jump between categories, and your
/// recent picks at the top. No emoji keyboard needed.
struct EmojiPickerSheet: View {
    /// "Reactions" in the player, "Emoji" in the editor.
    var title = "Reactions"
    let onPick: @MainActor (String) -> Void
    let onClose: @MainActor () -> Void

    @State private var query = ""
    @State private var recents: [String] = EmojiRecents.load()
    @State private var selectedCategory: EmojiCategory?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: title, leadingTitle: "Close", leadingAction: { onClose() }, onStage: true)
            searchField
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.s)
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    if query.isEmpty {
                        categoryChips(proxy)
                            .padding(.bottom, Space.xs)
                    }
                    ScrollView {
                        if query.isEmpty {
                            sections
                        } else {
                            results
                        }
                    }
                    .scrollDismissesKeyboard(.immediately)
                }
            }
        }
        .background(Color.srStageRaised.ignoresSafeArea())
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.srStageTextTertiary)
            TextField("Search, like party or heart", text: $query)
                .font(.srBody)
                .foregroundStyle(Color.srStageText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.srStageTextTertiary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Space.s)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Color.srStageControl))
    }

    @ViewBuilder private var results: some View {
        let found = EmojiCatalog.search(query)
        if found.isEmpty {
            Text("No reactions match \u{201C}\(query)\u{201D}.")
                .font(.srSubheadline)
                .foregroundStyle(Color.srStageTextSecondary)
                .frame(maxWidth: .infinity)
                .padding(.top, Space.xxl)
        } else {
            grid(found.map(\.emoji))
                .padding(.horizontal, Space.s)
                .padding(.bottom, Space.xl)
        }
    }

    // MARK: - Browsing

    private func categoryChips(_ proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.xs) {
                ForEach(EmojiCategory.allCases) { category in
                    let selected = category == selectedCategory
                    Button {
                        Haptics.selection()
                        selectedCategory = category
                        withAnimation(Motion.standard) { proxy.scrollTo(category.id, anchor: .top) }
                    } label: {
                        Label(category.shortTitle, systemImage: category.symbol)
                            .font(.srCaption)
                            .foregroundStyle(selected ? Color.srStage : Color.srStageTextSecondary)
                            .padding(.horizontal, Space.s)
                            .frame(height: 32)
                            .background(Capsule().fill(selected ? Color.srStageText : Color.srStageControl))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(category.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, Space.gutter)
        }
    }

    private var sections: some View {
        LazyVStack(alignment: .leading, spacing: Space.m) {
            if !recents.isEmpty {
                section(title: "Recently used", emoji: recents)
                    .id("recents")
            }
            ForEach(EmojiCategory.allCases) { category in
                section(title: category.title, emoji: EmojiCatalog.items(in: category).map(\.emoji))
                    .id(category.id)
            }
        }
        .padding(.horizontal, Space.s)
        .padding(.bottom, Space.xl)
    }

    private func section(title: String, emoji: [String]) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title)
                .font(.srCaption)
                .foregroundStyle(Color.srStageTextTertiary)
                .padding(.horizontal, Space.xs)
                .accessibilityAddTraits(.isHeader)
            grid(emoji)
        }
    }

    private func grid(_ emoji: [String]) -> some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(emoji, id: \.self) { item in
                Button {
                    pick(item)
                } label: {
                    Text(item)
                        .font(.system(size: 30))
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle(scale: 0.8))
                .accessibilityLabel(EmojiCatalog.name(for: item))
            }
        }
    }

    private func pick(_ emoji: String) {
        Haptics.selection()
        EmojiRecents.record(emoji)
        recents = EmojiRecents.load()
        onPick(emoji)
    }
}
