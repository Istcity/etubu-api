import WidgetKit
import SwiftUI

/// Home-screen descriptor — Live Activity-only extension'larda Xcode/SpringBoard
/// "Failed to get descriptors" hatasını önler. Kullanıcıya küçük bir durum kartı da sunar.
struct EtubuStatusWidget: Widget {
    let kind = "EtubuStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: EtubuStatusProvider()) { entry in
            EtubuStatusEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.black.opacity(0.92)
                }
        }
        .configurationDisplayName("ETUBU")
        .description("Cluster & Live Activity durumu")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

private struct EtubuStatusEntry: TimelineEntry {
    let date: Date
}

private struct EtubuStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> EtubuStatusEntry {
        EtubuStatusEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (EtubuStatusEntry) -> Void) {
        completion(EtubuStatusEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EtubuStatusEntry>) -> Void) {
        let entry = EtubuStatusEntry(date: Date())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600))))
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
                Image("EtubuLogo")
                    .resizable()
                    .scaledToFit()
                    .padding(6)
            }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image("EtubuLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ETUBU")
                        .font(.caption.weight(.bold))
                    Text("Live Activity")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                Image("EtubuLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                Text("ETUBU")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text("Sürüşte Dynamic Island")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(12)
        }
    }
}
