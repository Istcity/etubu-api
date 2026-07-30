import SwiftUI

struct EtubuGaugeClusterView: View {
    @ObservedObject var telemetry: EtubuObdTelemetry

    var body: some View {
        VStack(spacing: 20) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(telemetry.kmh)")
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("km/h")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.bottom, 14)
            }

            HStack(spacing: 28) {
                metric(title: "RPM", value: "\(telemetry.rpm)")
                Divider().frame(height: 28).overlay(Color.white.opacity(0.15))
                metric(
                    title: "Coolant",
                    value: telemetry.coolantC.map { "\($0)°" } ?? "—"
                )
                Divider().frame(height: 28).overlay(Color.white.opacity(0.15))
                metric(
                    title: "Batt",
                    value: telemetry.voltageV.map { String(format: "%.1fV", $0) } ?? "—"
                )
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                tile(title: "Throttle", value: telemetry.throttlePct.map { "\($0)%" } ?? "—")
                tile(title: "Engine load", value: telemetry.engineLoadPct.map { "\($0)%" } ?? "—")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func metric(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(.cyan)
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private func tile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.4))
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
