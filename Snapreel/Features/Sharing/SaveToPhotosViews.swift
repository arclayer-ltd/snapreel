import SwiftUI

// MARK: - Question sheet

/// The small sheet for the save-to-Photos stages that ask something: the permission
/// explanation, access off, audio-only and failures. Sized to its content.
struct PhotosQuestionSheet: View {
    let stage: PhotosSaveStage
    let video: Video
    let onPrimary: () -> Void
    let onSecondary: () -> Void

    @State private var contentHeight: CGFloat = 420
    @State private var bottomSafeArea: CGFloat = 0

    var body: some View {
        ScrollView {
            content
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { contentHeight = proxy.size.height }
                            .onChange(of: proxy.size.height) { newHeight in contentHeight = newHeight }
                    }
                )
        }
        .background(
            GeometryReader { proxy in
                Color.clear.onAppear { bottomSafeArea = proxy.safeAreaInsets.bottom }
            }
        )
        .background(Color.srSurface.ignoresSafeArea())
        .presentationDetents([.height(contentHeight + bottomSafeArea)])
        .presentationDragIndicator(.visible)
    }

    private var content: some View {
        VStack(spacing: Space.l) {
            symbol
            VStack(spacing: Space.xs) {
                Text(copy.title)
                    .font(.srTitle3)
                    .foregroundStyle(Color.srText)
                Text(copy.message)
                    .font(.srSubheadline)
                    .foregroundStyle(Color.srTextSecondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            PhotosVideoChip(video: video)
            if let note = copy.note {
                Label {
                    Text(note)
                } icon: {
                    Image(systemName: "lock.fill")
                }
                .font(.srFootnote)
                .foregroundStyle(Color.srTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            buttons
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.xxl)
        .padding(.bottom, Space.m)
    }

    private var symbol: some View {
        ZStack {
            Circle().fill(Color.srRedSoft)
            Image(systemName: copy.systemImage)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.srRed)
        }
        .frame(width: 64, height: 64)
        .accessibilityHidden(true)
    }

    private var buttons: some View {
        VStack(spacing: Space.xs) {
            Button(copy.primary) {
                Haptics.tap()
                onPrimary()
            }
            .buttonStyle(.srPrimary)
            if let secondary = copy.secondary {
                Button(secondary, action: onSecondary)
                    .buttonStyle(.srTertiary)
                    .frame(height: 44)
            }
        }
    }

    // MARK: Copy

    private struct Copy {
        var systemImage: String
        var title: String
        var message: String
        var note: String? = nil
        var primary: String
        var secondary: String?
    }

    private var quotedTitle: String { "\u{201C}\(video.title)\u{201D}" }

    private var copy: Copy {
        switch stage {
        case .permission, .saving, .saved:
            return Copy(systemImage: "photo.on.rectangle",
                        title: "Save to your Photos",
                        message: "Next, your iPhone will ask if Snapreel can add to Photos. Choose Allow to keep a copy of \(quotedTitle) there.",
                        note: "Snapreel can only add what you choose. It can't see or change anything already in your library.",
                        primary: "Continue",
                        secondary: "Not now")
        case .denied:
            return Copy(systemImage: "hand.raised.fill",
                        title: "Photos access is off",
                        message: "To save recordings to Photos, open Settings, tap Photos and choose Add Photos Only.",
                        primary: "Open Settings",
                        secondary: "Not now")
        case .audioOnly:
            return Copy(systemImage: "waveform",
                        title: "Audio can't go to Photos",
                        message: "Photos only keeps pictures and videos. Share \(quotedTitle) instead to save it to Files, send it in Messages or open it in another app.",
                        primary: "Share instead",
                        secondary: "Close")
        case .failed(.outOfSpace):
            return Copy(systemImage: "externaldrive.fill.badge.exclamationmark",
                        title: "Not enough space",
                        message: "Photos needs about \(Format.bytes(video.fileSize)) free to keep its own copy. Free up some space on your iPhone, then try again.",
                        primary: "Try again",
                        secondary: "Close")
        case .failed(.missingFile):
            return Copy(systemImage: "questionmark.folder",
                        title: "Recording not found",
                        message: "The file for this recording is no longer on this iPhone, so there's nothing to save.",
                        primary: "Close",
                        secondary: nil)
        case .failed(.other(let reason)):
            return Copy(systemImage: "exclamationmark.triangle.fill",
                        title: "Couldn't save to Photos",
                        message: reason,
                        primary: "Try again",
                        secondary: "Close")
        }
    }
}

/// Which recording a sheet is about: thumbnail, title, size and length.
struct PhotosVideoChip: View {
    let video: Video

    var body: some View {
        HStack(spacing: Space.s) {
            VideoThumbnail(video: video, cornerRadius: Radius.s, showsDuration: false)
                .frame(width: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(video.title)
                    .font(.srSubheadlineStrong)
                    .foregroundStyle(Color.srText)
                    .lineLimit(2)
                Text("\(Format.bytes(video.fileSize)) · \(Format.clock(video.duration))")
                    .font(.srFootnote)
                    .foregroundStyle(Color.srTextSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s)
        .background(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).fill(Color.srCanvas))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Status card

/// Floating card along the bottom edge: "Saving to Photos…" with a spinner, then
/// "Saved to Photos" with Open Photos. Dark so it reads over light lists and the player alike.
struct PhotosStatusCard: View {
    let video: Video
    let isSaved: Bool
    let onOpenPhotos: () -> Void

    var body: some View {
        HStack(spacing: Space.s) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(isSaved ? "Saved to Photos" : "Saving to Photos\u{2026}")
                    .font(.srSubheadlineStrong)
                    .foregroundStyle(Color.srOnDark)
                Text(video.title)
                    .font(.srFootnote)
                    .foregroundStyle(Color.srOnDarkSecondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: Space.xs)
            trailing
        }
        .padding(Space.s)
        .frame(maxWidth: 440)
        .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.srInkRaised))
        .overlay(RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.22), radius: 18, x: 0, y: 8)
    }

    private var thumbnail: some View {
        VideoThumbnail(video: video, cornerRadius: Radius.s, showsDuration: false)
            .frame(width: 52)
            .overlay(alignment: .bottomTrailing) {
                if isSaved {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white, Color.srRed)
                        .offset(x: 5, y: 5)
                        .transition(.scale.combined(with: .opacity))
                }
            }
    }

    @ViewBuilder private var trailing: some View {
        if isSaved {
            Button(action: onOpenPhotos) {
                Text("Open Photos")
                    .font(.srSubheadlineStrong)
                    .foregroundStyle(Color.srInk)
                    .padding(.horizontal, Space.s)
                    .frame(height: 34)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityHint("Opens the Photos app")
        } else {
            ProgressView()
                .tint(Color.white)
                .padding(.trailing, Space.xs)
                .accessibilityHidden(true)
        }
    }
}
