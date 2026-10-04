import SwiftUI
import WidgetKit

struct CareSnapshot: Decodable {
    let version: Int
    let updatedAt: TimeInterval
    let hasPets: Bool
    let days: [CareDay]
    static let empty = CareSnapshot(version: 1, updatedAt: 0, hasPets: false, days: [])
}
struct CareDay: Decodable {
    let startsAt: TimeInterval
    let doses: [CareDose]
}
struct CareDose: Decodable, Identifiable {
    let id: String
    let pet: String
    let medicine: String
    let amount: String
    let dueAt: TimeInterval
    let scheduledAt: TimeInterval
    let state: String
    var given: Bool { state == "given" }
    var uncertain: Bool { state == "uncertain" }
}
struct CareEntry: TimelineEntry {
    let date: Date
    let snapshot: CareSnapshot
    var day: CareDay? { snapshot.days.first { Calendar.current.isDate(Date(timeIntervalSince1970: $0.startsAt), inSameDayAs: date) } }
    var doses: [CareDose] { day?.doses.sorted { $0.scheduledAt < $1.scheduledAt } ?? [] }
    var given: Int { doses.filter(\.given).count }
    var remaining: [CareDose] { doses.filter { !$0.given } }
    var next: CareDose? { remaining.first }
    var stale: Bool { snapshot.hasPets && (day == nil || date.timeIntervalSince1970 - snapshot.updatedAt > 172800) }
    var headline: String {
        if !snapshot.hasPets { return "A little care, every day" }
        if stale { return "Open to refresh" }
        if doses.isEmpty { return "A quiet care day" }
        if remaining.isEmpty { return "All cared for" }
        if next?.uncertain == true { return "Needs a check" }
        return next!.dueAt <= date.timeIntervalSince1970 ? "Next dose" : "Later today"
    }
    var destination: URL {
        var url = URLComponents()
        url.scheme = "pawsitivesync"
        url.host = "app"
        url.path = "/lock"
        if let next = next, !stale {
            let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.locale = Locale(identifier: "en_US_POSIX")
            url.queryItems = [URLQueryItem(name: "dose", value: next.id), URLQueryItem(name: "day", value: formatter.string(from: date))]
        }
        return url.url!
    }
}

struct CareProvider: TimelineProvider {
    func placeholder(in context: Context) -> CareEntry { sample() }
    func getSnapshot(in context: Context, completion: @escaping (CareEntry) -> Void) {
        completion(context.isPreview ? sample() : CareEntry(date: Date(), snapshot: read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CareEntry>) -> Void) {
        let snapshot = read()
        let now = Date()
        let tomorrow = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: now)!)
        let changes = snapshot.days.flatMap { [$0.startsAt] + $0.doses.map(\.dueAt) }
            .filter { $0 > now.timeIntervalSince1970 && $0 <= tomorrow.timeIntervalSince1970 }
        let dates = ([now] + Set(changes).sorted().map { Date(timeIntervalSince1970: $0) })
        completion(Timeline(entries: dates.map { CareEntry(date: $0, snapshot: snapshot) }, policy: .after(now.addingTimeInterval(1800))))
    }
    private func read() -> CareSnapshot {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "PawsitiveAppGroup") as? String,
              let raw = UserDefaults(suiteName: group)?.string(forKey: "careSnapshotV1"),
              let data = raw.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(CareSnapshot.self, from: data), snapshot.version == 1 else { return .empty }
        return snapshot
    }
    /// Widget-gallery preview and the redacted loading placeholder only
    /// (Apple's pattern). Generic on purpose: never shown as real data.
    private func sample() -> CareEntry {
        let now = Date()
        let dose = CareDose(id: "preview", pet: "Your pet", medicine: "Daily medicine", amount: "1 tablet", dueAt: now.timeIntervalSince1970, scheduledAt: now.timeIntervalSince1970, state: "pending")
        return CareEntry(date: now, snapshot: CareSnapshot(version: 1, updatedAt: now.timeIntervalSince1970, hasPets: true, days: [CareDay(startsAt: Calendar.current.startOfDay(for: now).timeIntervalSince1970, doses: [dose])]))
    }
}

private let forest = Color(red: 0.29, green: 0.49, blue: 0.35)
private let sage = Color(red: 0.91, green: 0.95, blue: 0.92)

struct CareWidgetView: View {
    let entry: CareEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Group {
            if #available(iOSApplicationExtension 16.0, *), family == .accessoryCircular {
                Gauge(value: Double(entry.given), in: 0...Double(max(entry.doses.count, 1))) {
                    Image(systemName: "pawprint.fill")
                } currentValueLabel: {
                    if entry.stale || !entry.snapshot.hasPets { Image(systemName: "pawprint.fill") }
                    else { Text("\(entry.remaining.count)") }
                }.gaugeStyle(.accessoryCircular).accessibilityLabel("\(entry.remaining.count) doses remaining. Open Pawsitive to review.")
            } else if #available(iOSApplicationExtension 16.0, *), family == .accessoryInline {
                Label(entry.next == nil || entry.stale ? entry.headline : "\(entry.next!.pet) · \(entry.next!.medicine)", systemImage: "pawprint.fill")
            } else if #available(iOSApplicationExtension 16.0, *), family == .accessoryRectangular {
                VStack(alignment: .leading, spacing: 2) {
                    Label(entry.headline, systemImage: "pawprint.fill").font(.caption.bold())
                    if let dose = entry.next, !entry.stale {
                        Text("\(dose.pet) · \(dose.medicine)").font(.headline).lineLimit(1)
                        Text(dose.uncertain ? "Open to review" : dose.amount).font(.caption).lineLimit(1)
                    } else { Text("Open Pawsitive").font(.caption) }
                }
            } else {
                home
            }
        }
        .widgetURL(entry.destination)
        .modifier(WidgetBackground(color: scheme == .dark ? Color(red: 0.08, green: 0.13, blue: 0.10) : sage))
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 7 : 10) {
            HStack {
                Label("Daily care", systemImage: "pawprint.fill").font(.caption.weight(.semibold))
                Spacer(minLength: 4)
                if !entry.stale, !entry.doses.isEmpty {
                    Text("\(entry.given)/\(entry.doses.count)").font(.caption.monospacedDigit().bold())
                        .accessibilityLabel("\(entry.given) of \(entry.doses.count) doses given")
                }
            }.foregroundStyle(scheme == .dark ? Color.white.opacity(0.85) : forest)
            Text(entry.headline).font(family == .systemSmall ? .subheadline.bold() : .headline).lineLimit(2)
            if let dose = entry.next, !entry.stale {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dose.medicine).font(family == .systemSmall ? .headline : .title3.weight(.semibold)).lineLimit(1)
                        Text("\(dose.pet)\(dose.amount.isEmpty ? "" : " · \(dose.amount)")").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    if family != .systemSmall {
                        Spacer(minLength: 0)
                        Text(Date(timeIntervalSince1970: dose.scheduledAt), style: .time).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(entry.stale ? "Refresh the latest household care." : entry.snapshot.hasPets ? "Tap to see their care record." : "Add your pet and their routine.")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            if family == .systemLarge, !entry.stale {
                Divider().padding(.vertical, 4)
                ForEach(entry.doses.prefix(4)) { dose in
                    HStack(spacing: 10) {
                        Image(systemName: dose.given ? "checkmark.circle.fill" : dose.uncertain ? "exclamationmark.circle" : "clock").foregroundStyle(forest)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dose.medicine).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text("\(dose.pet) · \(dose.given ? "Given" : dose.uncertain ? "Check first" : dose.amount)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(Date(timeIntervalSince1970: dose.scheduledAt), style: .time).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Text(entry.next?.uncertain == true ? "Review dose" : "Open care").font(.caption.weight(.semibold))
                Image(systemName: "arrow.up.right").font(.caption2.weight(.semibold))
                Spacer(minLength: 0)
                if family != .systemSmall, entry.snapshot.updatedAt > 0 {
                    Text(Date(timeIntervalSince1970: entry.snapshot.updatedAt), style: .relative).font(.caption2).foregroundStyle(.secondary)
                        .accessibilityLabel("Last updated").accessibilityValue(Text(Date(timeIntervalSince1970: entry.snapshot.updatedAt), style: .relative))
                }
            }.foregroundStyle(scheme == .dark ? .white : forest)
        }
    }
}

private struct WidgetBackground: ViewModifier {
    let color: Color
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            content.containerBackground(color, for: .widget)
        } else {
            content.padding().background(color)
        }
    }
}

@main
struct PawsitiveWidgets: Widget {
    private var families: [WidgetFamily] {
        if #available(iOSApplicationExtension 16.0, *) {
            return [.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline]
        }
        return [.systemSmall, .systemMedium, .systemLarge]
    }
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PawsitiveCare", provider: CareProvider()) { entry in CareWidgetView(entry: entry) }
            .configurationDisplayName("Daily pet care")
            .description("See the next dose and today's progress. Open the app to review and log care.")
            .supportedFamilies(families)
    }
}
