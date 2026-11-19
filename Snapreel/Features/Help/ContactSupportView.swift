import MessageUI
import SwiftUI
import UIKit

/// What a support message is about. Becomes part of the email subject.
enum SupportTopic: String, CaseIterable, Identifiable, Hashable {
    case recording
    case screen
    case playback
    case library
    case sharing
    case idea
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recording: return "Recording"
        case .screen: return "Screen recording"
        case .playback: return "Watching and transcripts"
        case .library: return "Library and search"
        case .sharing: return "Sharing and saving"
        case .idea: return "An idea"
        case .other: return "Something else"
        }
    }

    var systemImage: String {
        switch self {
        case .recording: return "video.fill"
        case .screen: return "rectangle.inset.filled.on.rectangle"
        case .playback: return "play.fill"
        case .library: return "folder.fill"
        case .sharing: return "square.and.arrow.up"
        case .idea: return "lightbulb.fill"
        case .other: return "ellipsis.bubble.fill"
        }
    }

    /// The topic that fits a help category, so "Contact support" from an article arrives ready.
    static func suggested(forCategory categoryID: String) -> SupportTopic? {
        switch categoryID {
        case "recording": return .recording
        case "screen": return .screen
        case "watching", "notes": return .playback
        case "library": return .library
        case "sharing": return .sharing
        default: return nil
        }
    }
}

/// The details a person may choose to attach: never recordings or anything they made.
struct DeviceDetails {
    let model: String
    let system: String
    let app: String
    let freeSpace: String
    /// How long the last recordings took from Stop to review, step by step (`ReviewTiming`).
    var recentSaves: [String] = []
    /// What the last Lock Screen end push got back from the relay (`LiveActivityPush`).
    var lockScreenPush: String? = nil

    @MainActor
    static func current() -> DeviceDetails {
        DeviceDetails(model: modelIdentifier(),
                      system: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
                      app: "Snapreel \(AppInfo.version) (\(AppInfo.build))",
                      freeSpace: "\(Format.bytes(DiskSpace.available)) free",
                      recentSaves: ReviewTiming.recent,
                      lockScreenPush: LiveActivityPush.lastOutcome)
    }

    /// One line per detail, as they appear in the email.
    var lines: [String] {
        var device = ["Device: \(model)", "System: \(system)", "App: \(app)", "Storage: \(freeSpace)"]
        if let lockScreenPush { device.append("Lock Screen end: \(lockScreenPush)") }
        return recentSaves.isEmpty ? device : device + ["Recent saves (seconds):"] + recentSaves
    }

    /// "iPhone16,1" on a device; the simulated model in the simulator.
    private static func modelIdentifier() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(simulated) (Simulator)"
        }
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        return machine.isEmpty ? "iPhone" : machine
    }
}

/// A support email ready to hand to Mail.
struct SupportMailDraft: Identifiable {
    let id = UUID()
    let recipient: String
    let subject: String
    let body: String

    /// A `mailto:` link for other mail apps.
    var mailtoURL: URL? {
        URL(string: "mailto:\(recipient)?subject=\(Self.encode(subject))&body=\(Self.encode(body))")
    }

    private static func encode(_ text: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}

#if DEBUG
/// Lets a debug entry open the form already filled in.
enum ContactSupportDebug {
    @MainActor static var message: String? = nil
}
#endif

/// Contact support: topic, message, optional device details, then Send opens Mail addressed to
/// support. When Mail isn't set up, offers to copy the address or message, or open another
/// mail app.
struct ContactSupportView: View {
    @State private var topic: SupportTopic?
    @State private var message: String
    @State private var includesDeviceDetails = true
    @State private var mailDraft: SupportMailDraft?
    @State private var fallbackDraft: SupportMailDraft?
    @State private var toast: ToastMessage?
    @FocusState private var messageFocused: Bool

    init(initialTopic: SupportTopic? = nil, initialMessage: String = "") {
        _topic = State(initialValue: initialTopic)
        _message = State(initialValue: initialMessage)
    }

    private var trimmedMessage: String { message.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool { !trimmedMessage.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                intro
                topicSection
                messageSection
                detailsSection
                sendSection
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.s)
            .padding(.bottom, Space.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.srCanvas.ignoresSafeArea())
        .navigationTitle("Contact support")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { messageFocused = false }
                    .font(.srHeadline)
            }
        }
        .sheet(item: $mailDraft) { draft in
            MailComposeView(draft: draft) { result in
                mailFinished(result)
            }
            .ignoresSafeArea()
        }
        .sheet(item: $fallbackDraft) { draft in
            MailUnavailableSheet(draft: draft, onToast: { toast = $0 })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .toast($toast, bottomInset: Space.xl)
        .onAppear { applyDebugPrefill() }
    }

    // MARK: Sections

    private var intro: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("How can we help?")
                .font(.srDisplay)
                .foregroundStyle(Color.srText)
                .accessibilityAddTraits(.isHeader)
            Text("A real person reads every message and replies by email.")
                .font(.srCallout)
                .foregroundStyle(Color.srTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var topicSection: some View {
        let chips = ChipFlowLayout(spacing: Space.xs, rowSpacing: Space.xs)
        return VStack(alignment: .leading, spacing: Space.s) {
            fieldLabel("Topic")
            chips {
                ForEach(SupportTopic.allCases) { item in
                    topicChip(item)
                }
            }
        }
    }

    private func topicChip(_ item: SupportTopic) -> some View {
        let selected = topic == item
        return Button {
            Haptics.selection()
            withAnimation(Motion.quick) { topic = selected ? nil : item }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(item.title)
                    .font(.srSubheadlineStrong)
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? Color.white : Color.srText)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(Capsule().fill(selected ? Color.srRed : Color.srSurface))
            .overlay(Capsule().strokeBorder(selected ? Color.clear : Color.srLine, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle(scale: 0.96))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
    }

    private var messageSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            fieldLabel("Message")
            ZStack(alignment: .topLeading) {
                if message.isEmpty {
                    Text("What happened, what you expected, and how we can see it for ourselves.")
                        .font(.srBody)
                        .foregroundStyle(Color.srTextTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                TextEditor(text: $message)
                    .font(.srBody)
                    .foregroundStyle(Color.srText)
                    .scrollContentBackground(.hidden)
                    .focused($messageFocused)
                    .frame(minHeight: 150)
                    .accessibilityLabel("Message")
            }
            .padding(Space.s)
            .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.srSurface))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                    .strokeBorder(messageFocused ? Color.srRed : Color.srLine, lineWidth: messageFocused ? 1.5 : 1)
            )
            .animation(Motion.quick, value: messageFocused)
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Toggle(isOn: $includesDeviceDetails) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Include device details")
                        .font(.srBody)
                        .foregroundStyle(Color.srText)
                    Text("Helps us find the problem. Never includes your recordings.")
                        .font(.srFootnote)
                        .foregroundStyle(Color.srTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Color.srRed)
            if includesDeviceDetails {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(DeviceDetails.current().lines, id: \.self) { line in
                        Text(line)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Color.srTextSecondary)
                    }
                }
                .padding(Space.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Color.srFill))
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityElement(children: .combine)
            }
        }
        .padding(Space.m)
        .srCard()
        .animation(Motion.standard, value: includesDeviceDetails)
    }

    private var sendSection: some View {
        VStack(spacing: Space.s) {
            Button {
                send()
            } label: {
                HStack(spacing: Space.xs) {
                    Image(systemName: "paperplane.fill")
                    Text("Send")
                }
            }
            .buttonStyle(.srPrimary)
            .disabled(!canSend)
            Text(canSend
                 ? "Opens Mail with your message ready to send to \(AppInfo.supportEmail)."
                 : "Write a message to continue.")
                .font(.srFootnote)
                .foregroundStyle(Color.srTextTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.srCaption)
            .kerning(0.6)
            .foregroundStyle(Color.srTextTertiary)
            .padding(.horizontal, Space.xxs)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Sending

    private func makeDraft() -> SupportMailDraft {
        let subjectTopic = topic?.title ?? "Question"
        var text = trimmedMessage
        if includesDeviceDetails {
            text += "\n\n—\n" + DeviceDetails.current().lines.joined(separator: "\n")
        }
        return SupportMailDraft(recipient: AppInfo.supportEmail,
                                subject: "Snapreel: \(subjectTopic)",
                                body: text)
    }

    private func send() {
        guard canSend else { return }
        messageFocused = false
        Haptics.tap()
        let draft = makeDraft()
        if MFMailComposeViewController.canSendMail() {
            mailDraft = draft
        } else {
            fallbackDraft = draft
        }
    }

    private func mailFinished(_ result: MFMailComposeResult) {
        mailDraft = nil
        switch result {
        case .sent:
            Haptics.success()
            message = ""
            topic = nil
            toast = ToastMessage(text: "Sent. We'll reply by email.")
        case .saved:
            toast = ToastMessage(text: "Saved to your drafts in Mail", systemImage: "tray.and.arrow.down.fill")
        case .failed:
            Haptics.error()
            toast = ToastMessage(text: "Mail couldn't send it. Try again.", systemImage: "exclamationmark.circle.fill")
        case .cancelled:
            break
        @unknown default:
            break
        }
    }

    private func applyDebugPrefill() {
        #if DEBUG
        if let prefill = ContactSupportDebug.message {
            ContactSupportDebug.message = nil
            message = prefill
        }
        #endif
    }
}

// MARK: - Mail unavailable

/// Shown when Mail has no account: copy the address or the message, or open another mail app.
struct MailUnavailableSheet: View {
    let draft: SupportMailDraft
    let onToast: @MainActor (ToastMessage) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var openFailed = false

    init(draft: SupportMailDraft, onToast: @escaping @MainActor (ToastMessage) -> Void) {
        self.draft = draft
        self.onToast = onToast
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack {
                Spacer()
                CircleIconButton(systemName: "xmark", label: "Close") { dismiss() }
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                IconTile(systemName: "envelope.badge.fill", size: 44)
                    .padding(.bottom, Space.xxs)
                Text("Mail isn't set up")
                    .font(.srTitle)
                    .foregroundStyle(Color.srText)
                    .accessibilityAddTraits(.isHeader)
                Text("Send your message from any email app to \(draft.recipient). We've kept what you wrote, so you can paste it in.")
                    .font(.srCallout)
                    .foregroundStyle(Color.srTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: Space.s) {
                Button {
                    UIPasteboard.general.string = draft.recipient
                    Haptics.success()
                    onToast(ToastMessage(text: "Address copied", systemImage: "doc.on.doc.fill"))
                    dismiss()
                } label: {
                    Label("Copy address", systemImage: "at")
                }
                .buttonStyle(.srPrimary)
                Button {
                    UIPasteboard.general.string = "\(draft.subject)\n\n\(draft.body)"
                    Haptics.success()
                    onToast(ToastMessage(text: "Message copied", systemImage: "doc.on.doc.fill"))
                    dismiss()
                } label: {
                    Label("Copy message", systemImage: "doc.on.doc")
                }
                .buttonStyle(.srSecondary)
                Button {
                    openOtherMailApp()
                } label: {
                    Label("Open another mail app", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.srTertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, Space.xxs)
                if openFailed {
                    Text("No mail app could open the message. Copy the address instead.")
                        .font(.srFootnote)
                        .foregroundStyle(Color.srRedText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.gutter)
        .background(Color.srSurface.ignoresSafeArea())
    }

    private func openOtherMailApp() {
        guard let url = draft.mailtoURL else {
            openFailed = true
            return
        }
        openURL(url) { accepted in
            Task { @MainActor in
                if accepted {
                    dismiss()
                } else {
                    Haptics.warning()
                    openFailed = true
                }
            }
        }
    }
}

// MARK: - Mail composer

/// Mail's compose sheet, prefilled. Reports how it ended.
struct MailComposeView: UIViewControllerRepresentable {
    let draft: SupportMailDraft
    let onFinish: @MainActor (MFMailComposeResult) -> Void

    init(draft: SupportMailDraft, onFinish: @escaping @MainActor (MFMailComposeResult) -> Void) {
        self.draft = draft
        self.onFinish = onFinish
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([draft.recipient])
        controller.setSubject(draft.subject)
        controller.setMessageBody(draft.body, isHTML: false)
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: @MainActor (MFMailComposeResult) -> Void

        init(onFinish: @escaping @MainActor (MFMailComposeResult) -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            let callback = onFinish
            Task { @MainActor in
                callback(result)
            }
        }
    }
}

// MARK: - Flow layout

/// Lays chips out left to right, wrapping onto new rows.
struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let limit = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? .greatestFiniteMagnitude
        let rows = arrange(maxWidth: limit, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let widest = rows.map { $0.width }.max() ?? 0
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? widest
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(maxWidth: bounds.width, subviews: subviews)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y),
                                      anchor: .topLeading,
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if current.indices.isEmpty {
                current.indices = [index]
                current.width = size.width
                current.height = size.height
            } else if current.width + spacing + size.width <= maxWidth {
                current.indices.append(index)
                current.width += spacing + size.width
                current.height = max(current.height, size.height)
            } else {
                rows.append(current)
                var next = Row()
                next.y = current.y + current.height + rowSpacing
                next.indices = [index]
                next.width = size.width
                next.height = size.height
                current = next
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
