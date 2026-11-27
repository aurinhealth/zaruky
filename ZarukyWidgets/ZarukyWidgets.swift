import SwiftUI
import WidgetKit

@main
struct ZarukyWidgetBundle: WidgetBundle {
    var body: some Widget {
        EndingSoonWidget()
    }
}

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

/// One entry for now and one for each of the next midnights, so the days left count down
/// even when the app isn't opened; the app reloads the widgets whenever receipts change.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let saved = WidgetSnapshot.load()
        let useSample = context.isPreview && (saved?.items.isEmpty ?? true)
        let snapshot: WidgetSnapshot? = useSample ? WidgetSnapshot.sample : saved
        completion(SnapshotEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var entries = [SnapshotEntry(date: Date(), snapshot: snapshot)]
        for day in 1...7 {
            if let date = cal.date(byAdding: .day, value: day, to: today) {
                entries.append(SnapshotEntry(date: date, snapshot: snapshot))
            }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

extension WidgetSnapshot {
    static var sample: WidgetSnapshot {
        let now = Date()
        func inDays(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: n, to: now) ?? now }
        var s = WidgetSnapshot()
        s.items = [
            Item(id: UUID(), name: "iPhone 16 Pro", store: "Alza.cz", endDate: inDays(18), symbol: "iphone"),
            Item(id: UUID(), name: "Sony WH-1000XM6", store: "Alza.cz", endDate: inDays(28), symbol: "headphones"),
            Item(id: UUID(), name: L("Pračka Bosch", "Bosch washer"), store: "Datart", endDate: inDays(700), symbol: "washer.fill"),
        ]
        s.value = 98_950
        s.activeCount = 5
        return s
    }

    /// Items still under warranty on the entry's day.
    func active(on date: Date) -> [Item] {
        items.filter { WidgetSnapshot.daysLeft(until: $0.endDate, from: date) >= 0 }
    }
}

// MARK: - Widget

struct EndingSoonWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EndingSoon", provider: SnapshotProvider()) { entry in
            EndingSoonView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(L("Brzy končí", "Ending soon"))
        .description(L("Záruky, které skončí nejdřív.", "The warranties that end first."))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

private let brand = Color(red: 0.03, green: 0.48, blue: 0.35)
private let amber = Color(red: 0.96, green: 0.55, blue: 0.10)

struct EndingSoonView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var items: [WidgetSnapshot.Item] { entry.snapshot?.active(on: entry.date) ?? [] }

    var body: some View {
        if items.isEmpty {
            empty
        } else {
            switch family {
            case .systemMedium: medium
            case .accessoryRectangular: rectangular
            case .accessoryInline: inline
            default: small
            }
        }
    }

    private func days(_ item: WidgetSnapshot.Item) -> Int {
        WidgetSnapshot.daysLeft(until: item.endDate, from: entry.date)
    }

    private func color(_ item: WidgetSnapshot.Item) -> Color {
        days(item) <= 30 ? amber : brand
    }

    // Small: the next one to end, big.
    private var small: some View {
        let item = items[0]
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: item.symbol)
                    .font(.title3)
                    .foregroundStyle(color(item))
                Spacer()
                Text(L("Končí", "Ends"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(AppFormat.remaining(days: days(item)))
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(color(item))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(item.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            if !item.store.isEmpty {
                Text(item.store)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .widgetURL(WidgetSnapshot.url(for: item.id))
    }

    // Medium: value under warranty and the next three.
    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title3)
                    .foregroundStyle(brand)
                Spacer(minLength: 0)
                Text(L("Pod zárukou", "Under warranty"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(AppFormat.price(entry.snapshot?.value ?? 0, currency: entry.snapshot?.currency ?? "CZK"))
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .frame(width: 96, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(items.prefix(3)) { item in
                    Link(destination: WidgetSnapshot.url(for: item.id)) {
                        HStack(spacing: 8) {
                            Image(systemName: item.symbol)
                                .font(.footnote)
                                .foregroundStyle(color(item))
                                .frame(width: 18)
                            Text(item.name)
                                .font(.footnote.weight(.medium))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(AppFormat.remaining(days: days(item)))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(color(item))
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var rectangular: some View {
        let item = items[0]
        return VStack(alignment: .leading, spacing: 1) {
            Label(L("Záruka končí", "Warranty ends"), systemImage: "checkmark.seal")
                .font(.caption2.weight(.semibold))
            Text(item.name).font(.headline).lineLimit(1)
            Text(AppFormat.remaining(days: days(item))).font(.caption)
        }
        .widgetURL(WidgetSnapshot.url(for: item.id))
    }

    private var inline: some View {
        let item = items[0]
        return Label("\(item.name): \(AppFormat.remaining(days: days(item)))", systemImage: "checkmark.seal")
            .widgetURL(WidgetSnapshot.url(for: item.id))
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "doc.viewfinder")
                .font(.title3)
                .foregroundStyle(brand)
            if family == .systemSmall || family == .systemMedium { Spacer(minLength: 0) }
            Text(L("Žádná záruka nekončí", "No warranty ending"))
                .font(.subheadline.weight(.semibold))
            if family == .systemSmall || family == .systemMedium {
                Text(L("Naskenuj účtenku v Zárukách.", "Scan a receipt in Záruky."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
