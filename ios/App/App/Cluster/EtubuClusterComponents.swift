import SwiftUI

struct EtubuSpeedDialView: View {
    let kmh: Int
    let gear: String
    let theme: ClusterTheme
    var compact: Bool = false

    private var dialSize: CGFloat { compact ? 200 : 260 }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(0.14), lineWidth: compact ? 1.5 : 2)
                .frame(width: dialSize, height: dialSize)

            Circle()
                .strokeBorder(theme.accent.opacity(0.22), lineWidth: 1)
                .frame(width: dialSize - 18, height: dialSize - 18)

            VStack(spacing: compact ? 4 : 8) {
                gearRow
                Text("\(kmh)")
                    .font(.system(size: compact ? 72 : 92, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text("km/h")
                    .font(.system(size: compact ? 12 : 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .tracking(1)
            }
        }
        .frame(width: dialSize, height: dialSize)
    }

    private var gearRow: some View {
        HStack(spacing: compact ? 10 : 14) {
            ForEach(["P", "R", "N", "D"], id: \.self) { g in
                VStack(spacing: 3) {
                    Text(g)
                        .font(.system(size: compact ? 13 : 15, weight: .bold, design: .rounded))
                        .foregroundStyle(g == gear ? .white : .white.opacity(0.28))
                    Capsule()
                        .fill(g == gear ? Color.white : Color.clear)
                        .frame(width: 12, height: 2)
                }
            }
        }
    }
}

struct EtubuWarnBannerView: View {
    let item: EtubuWarnItem
    let theme: ClusterTheme

    private var urgent: Bool {
        item.stage == .critical || item.stage == .near
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.kind == "corridor" ? "gauge.with.dots.needle.67percent" : "exclamationmark.triangle.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(urgent ? Color.orange : theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.kind == "corridor" ? "HIZ KORİDORU" : (urgent ? "KRİTİK NOKTA" : "UYARI"))
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(urgent ? Color.orange : theme.accent)
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if !item.distanceLabel.isEmpty {
                Text(item.distanceLabel)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(urgent ? Color.orange.opacity(0.7) : theme.accent.opacity(0.45), lineWidth: 1.2)
                )
        )
        .shadow(color: (urgent ? Color.orange : theme.accent).opacity(0.35), radius: urgent ? 12 : 6)
        .scaleEffect(item.stage == .critical ? 1.02 : 1)
        .animation(item.stage == .critical ? .easeInOut(duration: 0.55).repeatForever(autoreverses: true) : .default, value: item.stage)
    }
}

struct EtubuCorridorChipView: View {
    @ObservedObject var warnings: EtubuDriveWarnings

    var body: some View {
        if warnings.corridorActive {
            HStack(spacing: 10) {
                Text("KORİDOR")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(warnings.corridorOver ? Color.red : Color.orange)
                Text("\(warnings.corridorAvgKmh)")
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                Text("ort")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
                if let limit = warnings.corridorLimit {
                    Text("lim \(limit)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
                if !warnings.corridorRemainLabel.isEmpty {
                    Text(warnings.corridorRemainLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.55))
                }
                if warnings.corridorOver {
                    Text("YAVAŞLA")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(Color.black.opacity(0.65))
                    .overlay(Capsule().strokeBorder(warnings.corridorOver ? Color.red.opacity(0.7) : Color.orange.opacity(0.5), lineWidth: 1))
            )
        }
    }
}
