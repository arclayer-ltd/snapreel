import SwiftUI

/// The top of the stats sheet for a shared recording: what happened on snapreel.video. Views
/// and unique viewers for everyone; average watched, the drop-off chart, who watched and
/// where from on Pro (Free sees an upsell instead). Drawn in the stage colours of the sheet.
struct InsightsSection: View {
    let link: CloudLink

    @ObservedObject private var auth = AuthService.shared
    @State private var insights: CloudInsights?
    @State private var failed = false

    private let columns = [GridItem(.flexible(), spacing: Space.s), GridItem(.flexible(), spacing: Space.s)]

    init(link: CloudLink, insights: CloudInsights? = nil) {
        self.link = link
        _insights = State(initialValue: insights)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            header
            if let insights {
                content(insights)
            } else if failed {
                Label("Viewer numbers didn't load. Pull down to try again later.", systemImage: "wifi.exclamationmark")
                    .font(.srFootnote)
                    .foregroundStyle(Color.srStageTextSecondary)
                counts(views: link.views, viewers: link.uniqueViewers)
            } else {
                counts(views: link.views, viewers: link.uniqueViewers)
                    .redacted(reason: .placeholder)
            }
        }
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: "link")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.srStageRed)
            Text("On snapreel.video")
                .font(.srHeadline)
                .foregroundStyle(Color.srStageText)
            Spacer()
            Button {
                ShareLinks.shared.open(link)
            } label: {
                Label("Open", systemImage: "safari")
                    .font(.srSubheadlineStrong)
                    .foregroundStyle(Color.srStageRed)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func content(_ insights: CloudInsights) -> some View {
        if insights.hasDetail {
            LazyVGrid(columns: columns, spacing: Space.s) {
                InsightTile(title: "Views", value: "\(insights.views)", systemImage: "play.fill")
                InsightTile(title: "Unique viewers", value: "\(insights.uniqueViewers)", systemImage: "person.2.fill")
                InsightTile(title: "Average watched", value: percent(insights.avgPercent), systemImage: "chart.line.uptrend.xyaxis")
                InsightTile(title: "Watched to the end", value: percent(insights.completionPercent), systemImage: "flag.checkered")
            }
            if let dropoff = insights.dropoff, dropoff.contains(where: { $0 > 0 }) {
                DropoffCard(values: dropoff, duration: link.durationS ?? 0)
            }
            if let viewers = insights.viewers, !viewers.isEmpty {
                ViewersCard(viewers: viewers)
            }
            if let countries = insights.countries, !countries.isEmpty {
                CountriesCard(countries: countries)
            }
        } else {
            counts(views: insights.views, viewers: insights.uniqueViewers)
            ProUpsellCard(title: "See who watched",
                          message: "Pro shows each viewer, how far they got, where they stopped on a drop-off chart, and which countries they watched from.",
                          onStage: true) {
                ProPresenter.paywall(.feature(.insights))
            }
        }
        if insights.views == 0 {
            Text("No views yet. A view counts once someone watches 5 seconds, or to the end. Your own views don't count.")
                .font(.srFootnote)
                .foregroundStyle(Color.srStageTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func counts(views: Int, viewers: Int) -> some View {
        LazyVGrid(columns: columns, spacing: Space.s) {
            InsightTile(title: "Views", value: "\(views)", systemImage: "play.fill")
            InsightTile(title: "Unique viewers", value: "\(viewers)", systemImage: "person.2.fill")
        }
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "–" }
        return "\(Int(value.rounded()))%"
    }

    private func load() async {
        do {
            let latest = try await APIClient.shared.insights(link.serverID)
            insights = latest
            failed = false
        } catch {
            failed = insights == nil
        }
    }
}

private struct InsightTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Label(title, systemImage: systemImage)
                .font(.srFootnote)
                .foregroundStyle(Color.srStageTextSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.srStat)
                .foregroundStyle(Color.srStageText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.srStageControl))
        .accessibilityElement(children: .combine)
    }
}

/// "Where people stopped": how many views reached each 1% of the video.
private struct DropoffCard: View {
    let values: [Int]
    let duration: Double

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text("Where people stopped")
                    .font(.srSubheadlineStrong)
                    .foregroundStyle(Color.srStageText)
                Spacer()
                Text("\(retainedAtEnd)% to the end")
                    .font(.srFootnote)
                    .foregroundStyle(Color.srStageTextSecondary)
            }
            DropoffChart(values: values)
                .frame(height: 120)
            HStack {
                Text("0:00")
                Spacer()
                Text(Format.clock(duration / 2))
                Spacer()
                Text(Format.clock(duration))
            }
            .font(.srTimerSmall)
            .foregroundStyle(Color.srStageTextTertiary)
        }
        .padding(Space.m)
        .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.srStageControl))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Drop-off chart. \(retainedAtEnd) percent of views reached the end.")
    }

    private var retainedAtEnd: Int {
        guard let first = values.first, first > 0, let last = values.last else { return 0 }
        return Int((Double(last) / Double(first) * 100).rounded())
    }
}

/// The drop-off curve: a red line over a soft red fill.
struct DropoffChart: View {
    let values: [Int]

    var body: some View {
        GeometryReader { proxy in
            let points = self.points(in: proxy.size)
            ZStack {
                // Quarter lines.
                Path { path in
                    for step in 1...3 {
                        let y = proxy.size.height * CGFloat(step) / 4
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    }
                }
                .stroke(Color.srStageLine, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: first.x, y: proxy.size.height))
                    for point in points { path.addLine(to: point) }
                    path.addLine(to: CGPoint(x: points.last?.x ?? 0, y: proxy.size.height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [Color.srRed.opacity(0.35), Color.srRed.opacity(0.04)],
                                     startPoint: .top, endPoint: .bottom))
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() { path.addLine(to: point) }
                }
                .stroke(Color.srRed, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let top = Double(max(1, values.max() ?? 1))
        return values.enumerated().map { index, value in
            CGPoint(x: size.width * CGFloat(index) / CGFloat(values.count - 1),
                    y: size.height * CGFloat(1 - Double(value) / top) * 0.92 + size.height * 0.04)
        }
    }
}

/// "Who watched": name (or Anonymous), where from, which device, when, and how far.
private struct ViewersCard: View {
    let viewers: [CloudViewer]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Who watched")
                .font(.srSubheadlineStrong)
                .foregroundStyle(Color.srStageText)
                .padding(.bottom, Space.xs)
            ForEach(Array(viewers.prefix(20).enumerated()), id: \.offset) { index, viewer in
                if index > 0 { Rectangle().fill(Color.srStageLine).frame(height: 0.5) }
                row(viewer)
            }
            if viewers.count > 20 {
                Text("And \(viewers.count - 20) more on snapreel.video")
                    .font(.srFootnote)
                    .foregroundStyle(Color.srStageTextTertiary)
                    .padding(.top, Space.xs)
            }
        }
        .padding(Space.m)
        .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.srStageControl))
    }

    private func row(_ viewer: CloudViewer) -> some View {
        HStack(spacing: Space.s) {
            ZStack {
                Circle().fill(viewer.anonymous ? Color.srStageText.opacity(0.12) : Color.srRed.opacity(0.18))
                if viewer.anonymous {
                    Image(systemName: "person.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.srStageTextSecondary)
                } else {
                    Text(String((viewer.name ?? "?").prefix(1)).uppercased())
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.srStageRed)
                }
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(viewer.anonymous ? "Anonymous" : (viewer.name ?? "Viewer"))
                    .font(.srSubheadlineStrong)
                    .foregroundStyle(Color.srStageText)
                HStack(spacing: 4) {
                    Text(ProText.flag(viewer.country))
                    if let device = viewer.device {
                        Image(systemName: device.systemImage)
                    }
                    Text(Format.age(viewer.lastSeenAt))
                }
                .font(.srFootnote)
                .foregroundStyle(Color.srStageTextSecondary)
            }
            Spacer(minLength: Space.xs)
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(Int(viewer.percent.rounded()))%")
                    .font(.srSubheadlineStrong.monospacedDigit())
                    .foregroundStyle(Color.srStageText)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.srStageText.opacity(0.12))
                        Capsule().fill(Color.srRed)
                            .frame(width: proxy.size.width * CGFloat(min(100, max(0, viewer.percent)) / 100))
                    }
                }
                .frame(width: 56, height: 4)
            }
        }
        .padding(.vertical, Space.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(viewer.anonymous ? "Anonymous" : (viewer.name ?? "Viewer")), \(ProText.country(viewer.country)), watched \(Int(viewer.percent.rounded())) percent, \(Format.age(viewer.lastSeenAt))")
    }
}

private struct CountriesCard: View {
    let countries: [CloudCountryCount]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Where from")
                .font(.srSubheadlineStrong)
                .foregroundStyle(Color.srStageText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.xs) {
                    ForEach(countries.sorted { $0.count > $1.count }, id: \.code) { country in
                        HStack(spacing: 5) {
                            Text(ProText.flag(country.code))
                            Text(ProText.country(country.code))
                                .foregroundStyle(Color.srStageText)
                            Text("\(country.count)")
                                .foregroundStyle(Color.srStageTextSecondary)
                        }
                        .font(.srFootnote)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.srStageRaised))
                    }
                }
            }
        }
        .padding(Space.m)
        .background(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Color.srStageControl))
    }
}
