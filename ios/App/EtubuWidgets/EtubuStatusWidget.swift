import WidgetKit
import SwiftUI

/// Home-screen widget — App Group'tan canlı SOC / hız okur.
struct EtubuStatusWidget: Widget {
    let kind = "EtubuStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: EtubuStatusProvider()) { entry in
            EtubuStatusEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.black.opacity(0.92)
                }
        }
        .configurationDisplayName("Etubu")
        .description("Hız, şarj ve uyarı özeti")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

private struct EtubuStatusEntry: TimelineEntry {
    let date: Date
    let kmh: Int
    let soc: Int?
    let gear: String
    let rangeKm: Int?
    let warn: String
    let stale: Bool
}

private struct EtubuStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> EtubuStatusEntry {
        EtubuStatusEntry(date: Date(), kmh: 72, soc: 64, gear: "D", rangeKm: 280, warn: "", stale: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (EtubuStatusEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EtubuStatusEntry>) -> Void) {
        let entry = makeEntry()
        let next = entry.stale
            ? Date().addingTimeInterval(300)
            : Date().addingTimeInterval(30)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func makeEntry() -> EtubuStatusEntry {
        let suite = UserDefaults(suiteName: "group.com.etubu.app")
        let ts = suite?.double(forKey: "updatedAt") ?? 0
        let updated = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        let stale = updated.map { Date().timeIntervalSince($0) > 180 } ?? true
        let kmh = suite?.integer(forKey: "kmh") ?? 0
        let soc = suite?.object(forKey: "soc") as? Int
        let gear = suite?.string(forKey: "gear") ?? "P"
        let rangeKm = suite?.object(forKey: "rangeKm") as? Int
        let warn = suite?.string(forKey: "primaryWarn") ?? ""
        return EtubuStatusEntry(
            date: Date(),
            kmh: stale ? 0 : kmh,
            soc: stale ? nil : soc,
            gear: stale ? "—" : gear,
            rangeKm: stale ? nil : rangeKm,
            warn: stale ? "" : warn,
            stale: stale
        )
    }
}

private struct EtubuStatusEntryView: View {
    var entry: EtubuStatusEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Text(entry.stale ? "—" : "\(entry.kmh)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .minimumScaleFactor(0.6)
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.stale ? "Etubu" : "\(entry.kmh) km/h · \(entry.gear)")
                    .font(.caption.weight(.bold))
                Text(socLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image("EtubuLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                    Spacer(minLength: 0)
                    Text(entry.gear)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.cyan)
                }
                Text(entry.stale ? "—" : "\(entry.kmh)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                Text(entry.stale ? "Veri yok" : "km/h")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(socLine)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                if !entry.warn.isEmpty {
                    Text(entry.warn)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
            .padding(4)
        }
    }

    private var socLine: String {
        if entry.stale { return "Sürüşte aç" }
        var parts: [String] = []
        if let soc = entry.soc { parts.append("\(soc)%") }
        if let range = entry.rangeKm { parts.append("\(range) km") }
        return parts.isEmpty ? "Etubu" : parts.joined(separator: " · ")
    }
}
