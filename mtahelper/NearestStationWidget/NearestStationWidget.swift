import AppIntents
import SwiftUI
import WidgetKit

struct NearestStationEntry: TimelineEntry {
    enum State {
        case placeholder
        case noData
        case ready(NearestStationSnapshot)
    }

    let date: Date
    let state: State
}

struct NearestStationProvider: TimelineProvider {
    func placeholder(in context: Context) -> NearestStationEntry {
        NearestStationEntry(date: Date(), state: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (NearestStationEntry) -> Void) {
        Task {
            if context.isPreview {
                completion(NearestStationEntry(date: Date(), state: .ready(.preview)))
            } else {
                completion(await loadEntry())
            }
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NearestStationEntry>) -> Void) {
        Task {
            let entry = await loadEntry()
            let refreshDate = Calendar.current.date(byAdding: .minute, value: 10, to: Date()) ?? Date().addingTimeInterval(600)
            completion(Timeline(entries: [entry], policy: .after(refreshDate)))
        }
    }

    private func loadEntry() async -> NearestStationEntry {
        guard let snapshot = WidgetDataStore.load() else {
            return NearestStationEntry(date: Date(), state: .noData)
        }

        return NearestStationEntry(date: snapshot.lastUpdated, state: .ready(snapshot))
    }
}

struct NearestStationWidgetEntryView: View {
    let entry: NearestStationEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Button(intent: RefreshNearestStationIntent()) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .buttonStyle(.plain)
        .contentMargins(.all, family == .systemSmall ? 12 : 10)
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch entry.state {
        case .placeholder:
            placeholderContent
        case .noData:
            VStack(alignment: .leading, spacing: 8) {
                Text("Nearest Station")
                    .font(.headline)
                Text("Open mtahelper to load nearby stations.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                refreshFooter(lastUpdated: nil)
            }
        case .ready(let snapshot):
            VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 10) {
                VStack(alignment: .leading, spacing: family == .systemSmall ? 2 : 0) {
                    Text(snapshot.stationName)
                        .font(.system(size: family == .systemSmall ? 13 : 13.5, weight: .semibold, design: .default))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.55)
                        .layoutPriority(1)
                        .multilineTextAlignment(.leading)
                }

                let lineLimit = lineDisplayLimit(for: family)
                let arrivalLimit = arrivalDisplayLimit(for: family)

                ForEach(snapshot.lines.prefix(lineLimit), id: \.id) { line in
                    HStack(spacing: 5) {
                        lineBadge(for: line.id, compact: family == .systemSmall)
                        Text(arrivalText(for: line, limit: arrivalLimit))
                            .font(.system(size: family == .systemSmall ? 10.5 : 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .lineSpacing(0)
                    }
                    .alignmentGuide(.leading) { $0[.leading] }
                }

                Spacer(minLength: family == .systemSmall ? 4 : 4)
                refreshFooter(lastUpdated: snapshot.lastUpdated)
            }
        }
    }

    private var placeholderContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("14 St - Union Sq")
                .font(.headline)
                .redacted(reason: .placeholder)
            Text("320 ft away")
                .font(.caption)
                .foregroundStyle(.secondary)
                .redacted(reason: .placeholder)
            Spacer()
            HStack {
                Text("Updated just now")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "arrow.clockwise")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .redacted(reason: .placeholder)
        }
    }

    private func arrivalText(for line: NearestStationSnapshot.Line, limit: Int) -> String {
        let arrivals = Array(line.arrivals.prefix(limit))
        guard !arrivals.isEmpty else {
            return "No arrivals"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated

        let snippets = arrivals.map { arrival -> String in
            formatter.localizedString(for: arrival, relativeTo: Date())
        }

        return snippets.joined(separator: ", ")
    }

    private func distanceString(for distance: Double?) -> String? {
        guard let distance, distance >= 0 else { return nil }

        let measurement = Measurement(value: distance, unit: UnitLength.meters)
        let formatter = MeasurementFormatter()
        formatter.unitOptions = [.naturalScale]
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter.string(from: measurement)
    }

    @ViewBuilder
    private func refreshFooter(lastUpdated: Date? = nil) -> some View {
        HStack(spacing: 6) {
            if let lastUpdated {
                Text("Updated \(relativeString(for: lastUpdated))")
            } else {
                Text("Tap to refresh")
            }
            Spacer()
            Image(systemName: "arrow.clockwise")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func relativeString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func lineBadge(for line: String, compact: Bool) -> some View {
        let badgeColor = LineAppearance.color(for: line)
        let textColor = LineAppearance.textColor(for: line)

        return Text(line)
            .font(.system(compact ? .footnote : .subheadline, design: .rounded).weight(.bold))
            .foregroundStyle(textColor)
            .padding(.horizontal, compact ? 7 : 9)
            .padding(.vertical, compact ? 3 : 5)
            .background(
                Capsule()
                    .fill(badgeColor)
            )
            .minimumScaleFactor(0.8)
    }

    private func lineDisplayLimit(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall:
            return 3
        default:
            return 3
        }
    }

    private func arrivalDisplayLimit(for family: WidgetFamily) -> Int {
        return 2
    }
}

struct RefreshNearestStationIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Nearest Station"

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadTimelines(ofKind: NearestStationWidget.kind)
        return .result()
    }
}

@main
struct NearestStationWidget: Widget {
    static let kind = "NearestStationWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NearestStationProvider()) { entry in
            NearestStationWidgetEntryView(entry: entry)
        }
        .supportedFamilies([.systemSmall, .systemMedium])
        .configurationDisplayName("Nearest Station")
        .description("See the closest subway stop at a glance.")
    }
}
