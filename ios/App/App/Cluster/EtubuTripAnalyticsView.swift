import SwiftUI

/// Mytess-style trip energy summary + Wh/km bars for Settings.
struct EtubuTripAnalyticsView: View {
    @ObservedObject var store: EtubuTripHistoryStore
    var accent: Color = .cyan

    private var summary: EtubuTripHistoryStore.AnalyticsSummary { store.analytics }
    private var series: [(id: String, label: String, whPerKm: Double)] { store.whPerKmSeries }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let active = store.active {
                HStack {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.green)
                    Text(String(format: EtubuClusterL10n.t("tripActiveFmt"), active.distanceKm, active.maxKmh))
                        .font(.caption.weight(.semibold))
                    Spacer()
                }
            }

            if summary.tripCount == 0 {
                Text(EtubuClusterL10n.t("tripEmptyHint"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    statCard(
                        EtubuClusterL10n.t("tripStatDistance"),
                        String(format: "%.0f km", summary.totalDistanceKm)
                    )
                    statCard(
                        EtubuClusterL10n.t("tripStatAvgWh"),
                        summary.avgWhPerKm.map { String(format: "%.0f" , $0) } ?? "—"
                    )
                    statCard(
                        EtubuClusterL10n.t("tripStatBestWh"),
                        summary.bestWhPerKm.map { String(format: "%.0f", $0) } ?? "—"
                    )
                    statCard(
                        EtubuClusterL10n.t("tripStatWeek"),
                        String(format: "%.0f km", summary.last7DayKm)
                    )
                }

                if summary.totalEnergyKwh > 0.05 {
                    Text(String(format: EtubuClusterL10n.t("tripStatEnergyFmt"), summary.totalEnergyKwh, summary.tripCount))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if !series.isEmpty {
                    Text(EtubuClusterL10n.t("tripWhChart"))
                        .font(.caption.weight(.semibold))
                    whChart
                }
            }

            ForEach(store.trips.prefix(8)) { trip in
                tripRow(trip)
            }
        }
        .padding(.vertical, 4)
    }

    private func statCard(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.monospacedDigit().weight(.bold))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private var whChart: some View {
        let maxWh = max(series.map(\.whPerKm).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(series, id: \.id) { item in
                    let h = max(4, CGFloat(item.whPerKm / maxWh) * 56)
                    VStack(spacing: 3) {
                        Text(String(format: "%.0f", item.whPerKm))
                            .font(.system(size: 8, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(accent.opacity(0.85))
                            .frame(height: h)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 78, alignment: .bottom)

            HStack(spacing: 4) {
                ForEach(series, id: \.id) { item in
                    Text(item.label)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .accessibilityLabel(EtubuClusterL10n.t("tripWhChart"))
    }

    private func tripRow(_ trip: EtubuTripRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(trip.routeTo.isEmpty ? EtubuClusterL10n.t("trip") : trip.routeTo)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            HStack(spacing: 8) {
                Text(String(format: "%.1f km", trip.distanceKm))
                Text("·")
                Text(String(format: "%.0f ort", trip.avgKmh))
                if let wh = trip.whPerKm {
                    Text("·")
                    Text(String(format: "%.0f Wh/km", wh))
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}
