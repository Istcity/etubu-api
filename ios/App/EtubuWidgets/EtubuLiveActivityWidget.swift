import WidgetKit
import SwiftUI
import ActivityKit

@main
struct EtubuWidgetsBundle: WidgetBundle {
    var body: some Widget {
        EtubuLiveActivityWidget()
    }
}

@available(iOS 16.2, *)
struct EtubuLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EtubuDriveAttributes.self) { context in
            // Lock screen / banner
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image("EtubuLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    Spacer(minLength: 4)
                    Text("\(context.state.kmh)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                    Text("km/h")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(context.state.gear)
                        .font(.headline.weight(.bold))
                        .frame(minWidth: 16)
                }
                if !context.state.routeSummaryLine.isEmpty {
                    Text(context.state.routeSummaryLine)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.cyan)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if context.state.routeActive, context.state.hasRouteBrief {
                    routeBriefRow(context.state)
                }
                if context.state.routeActive, !context.state.primaryWarn.isEmpty {
                    Text(context.state.primaryWarn)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                if context.state.routeActive, !context.state.aheadWarn2.isEmpty {
                    Text(context.state.aheadWarn2)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.orange.opacity(0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                tpmsRow(context.state)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .activityBackgroundTint(Color.black.opacity(0.88))
            .activitySystemActionForegroundColor(.cyan)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Image("EtubuLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        Text(context.state.gear)
                            .font(.system(size: 16, weight: .bold))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(context.state.kmh)")
                            .font(.system(size: 22, weight: .bold).monospacedDigit())
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                        Text("km/h")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    if !context.state.routeSummaryLine.isEmpty {
                        Text(context.state.routeSummaryLine)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.cyan)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        if context.state.routeActive, context.state.hasRouteBrief {
                            routeBriefRow(context.state)
                        }
                        if context.state.routeActive, context.state.remainingPoints > 0 {
                            Text("Kalan \(context.state.remainingPoints) kritik nokta")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        if context.state.routeActive, !context.state.primaryWarn.isEmpty {
                            Text(context.state.primaryWarn)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                        }
                        if context.state.routeActive, !context.state.aheadWarn2.isEmpty {
                            Text(context.state.aheadWarn2)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.orange.opacity(0.75))
                                .lineLimit(1)
                        }
                        tpmsRow(context.state)
                    }
                    .padding(.top, 2)
                }
            } compactLeading: {
                Image("EtubuLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } compactTrailing: {
                if context.state.routeActive, !context.state.primaryWarn.isEmpty {
                    Text(shortWarn(context.state.primaryWarn))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)
                        .frame(maxWidth: 56, alignment: .trailing)
                } else if context.state.routeActive, !context.state.routeTo.isEmpty {
                    Text(shortDest(context.state.routeTo))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.cyan)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: 52, alignment: .trailing)
                } else {
                    Text("\(min(context.state.kmh, 999))")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .minimumScaleFactor(0.45)
                        .lineLimit(1)
                        .frame(maxWidth: 28, alignment: .trailing)
                }
            } minimal: {
                Image("EtubuLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
            .widgetURL(URL(string: "com.etubu.app://drive"))
        }
    }

    private func shortDest(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let slash = t.split(separator: "/").last {
            return String(slash).trimmingCharacters(in: .whitespaces).prefix(10).description
        }
        return String(t.prefix(10))
    }

    private func shortWarn(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let dist = t.split(separator: "·").last {
            return String(dist).trimmingCharacters(in: .whitespaces).prefix(8).description
        }
        return String(t.prefix(8))
    }

    @ViewBuilder
    private func routeBriefRow(_ state: EtubuDriveAttributes.ContentState) -> some View {
        HStack(spacing: 8) {
            briefChip("R", state.radarCount, .orange)
            briefChip("K", state.corridorCount, .yellow)
            briefChip("C", state.controlCount, .purple)
            briefChip("Ş", state.chargeCount, .cyan)
            briefChip("H", state.weatherCount, .blue)
            Spacer(minLength: 0)
        }
    }

    private func briefChip(_ letter: String, _ count: Int, _ color: Color) -> some View {
        HStack(spacing: 2) {
            Text(letter)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(color)
            Text("\(count)")
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(.white.opacity(count > 0 ? 0.95 : 0.35))
        }
    }

    @ViewBuilder
    private func tpmsRow(_ state: EtubuDriveAttributes.ContentState) -> some View {
        HStack(spacing: 6) {
            tpmsCell("FL", state.tpmsFL)
            tpmsCell("FR", state.tpmsFR)
            Spacer(minLength: 2)
            tpmsCell("RL", state.tpmsRL)
            tpmsCell("RR", state.tpmsRR)
        }
    }

    private func tpmsCell(_ label: String, _ psi: Int?) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(psi.map { "\($0)" } ?? "—")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}
