import SwiftUI

/// Small pill-row summarizing route hazards (radar / speed corridor / charge stop / control point / weather).
/// Used both in the compact route-summary bar and the full active-route card.
struct EtubuRouteBriefChipsView: View {
    let brief: EtubuRouteBriefSummary
    var compact: Bool = false

    private struct Chip: Identifiable {
        let id: String
        let letter: String
        let count: Int
        let color: Color
    }

    private var chips: [Chip] {
        [
            Chip(id: "radar", letter: "R", count: brief.radarCount, color: .orange),
            Chip(id: "corridor", letter: "K", count: brief.corridorCount, color: .yellow),
            Chip(id: "control", letter: "C", count: brief.controlCount, color: .purple),
            Chip(id: "charge", letter: "Ş", count: brief.chargeCount, color: .cyan),
            Chip(id: "weather", letter: "H", count: brief.weatherCount, color: .blue),
        ].filter { $0.count > 0 }
    }

    var body: some View {
        if !chips.isEmpty {
            HStack(spacing: compact ? 6 : 8) {
                ForEach(chips) { chip in
                    HStack(spacing: 3) {
                        Text(chip.letter)
                            .font(.system(size: compact ? 9 : 10, weight: .heavy))
                            .foregroundStyle(chip.color)
                        Text("\(chip.count)")
                            .font(.system(size: compact ? 10 : 11, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.92))
                    }
                    .padding(.horizontal, compact ? 6 : 8)
                    .padding(.vertical, compact ? 3 : 4)
                    .background(
                        Capsule().fill(chip.color.opacity(0.16))
                    )
                    .overlay(
                        Capsule().strokeBorder(chip.color.opacity(0.4), lineWidth: 1)
                    )
                }
                if !compact { Spacer(minLength: 0) }
            }
        }
    }
}
