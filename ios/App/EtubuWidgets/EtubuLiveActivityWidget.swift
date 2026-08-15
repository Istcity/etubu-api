import WidgetKit
import SwiftUI
import ActivityKit

@main
struct EtubuWidgetsBundle: WidgetBundle {
    var body: some Widget {
        EtubuStatusWidget()
        EtubuLiveActivityWidget()
    }
}

@available(iOS 16.2, *)
struct EtubuLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EtubuDriveAttributes.self) { context in
            EtubuIslandCanvas(
                state: context.state,
                style: .lockScreen
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .activityBackgroundTint(context.state.canvasColor)
            .activitySystemActionForegroundColor(context.state.accentColor)
        } dynamicIsland: { context in
            let accent = context.state.accentColor
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(String(context.state.shortDestination.prefix(12)))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                        Text(context.state.gear)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(accent)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 86, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        if let eta = context.state.etaClockLabel {
                            Text(eta)
                                .font(.system(size: 12, weight: .bold).monospacedDigit())
                                .foregroundStyle(accent)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        } else if let km = context.state.remainKm, km > 0 {
                            Text(km >= 10 ? String(format: "%.0f km", km) : String(format: "%.1f km", km))
                                .font(.system(size: 12, weight: .bold).monospacedDigit())
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        if let soc = context.state.socPercent {
                            Text("\(soc)%")
                                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Color(red: 0.40, green: 0.95, blue: 0.55))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: 72, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Color.clear.frame(height: 1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    EtubuIslandCanvas(state: context.state, style: .island)
                        .padding(.horizontal, 2)
                        .padding(.top, 1)
                        .padding(.bottom, 2)
                }
            } compactLeading: {
                Image("EtubuLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
            } compactTrailing: {
                compactTrailing(context.state)
            } minimal: {
                if let soc = context.state.socPercent {
                    Text("\(soc)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color(red: 0.35, green: 0.95, blue: 0.55))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                } else {
                    Image("EtubuLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                }
            }
            .keylineTint(accent)
            .widgetURL(URL(string: "com.etubu.app://drive"))
        }
    }

    @ViewBuilder
    private func compactTrailing(_ state: EtubuDriveAttributes.ContentState) -> some View {
        let accent = state.accentColor
        Group {
            if state.overLimit == true {
                Text("\(min(state.kmh, 999))")
                    .foregroundStyle(.orange)
            } else if state.kmh >= 5 {
                Text("\(min(state.kmh, 999))")
                    .foregroundStyle(accent)
            } else if let soc = state.socPercent {
                Text("\(soc)%")
                    .foregroundStyle(Color(red: 0.35, green: 0.95, blue: 0.55))
            } else {
                Text(state.gear)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
        .minimumScaleFactor(0.45)
        .lineLimit(1)
        .frame(maxWidth: 36, alignment: .trailing)
    }
}

// MARK: - Cluster-matched Island / lock canvas

@available(iOS 16.2, *)
private enum EtubuIslandStyle {
    case island
    case lockScreen
}

@available(iOS 16.2, *)
private struct EtubuIslandCanvas: View {
    let state: EtubuDriveAttributes.ContentState
    let style: EtubuIslandStyle

    private var accent: Color { state.accentColor }
    private var urgent: Bool {
        !state.primaryWarn.isEmpty || state.overLimit == true || (state.socPercent.map { $0 <= 15 } ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style == .lockScreen ? 6 : 3) {
            if style == .lockScreen {
                headerRow
            }

            hudRow

            routeRow

            if !state.primaryWarn.isEmpty {
                Text(state.primaryWarn)
                    .font(.system(size: style == .lockScreen ? 11 : 10, weight: .semibold))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if style == .lockScreen, !state.aheadWarn2.isEmpty {
                Text(state.aheadWarn2)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let plan = state.planSummary, !plan.isEmpty {
                Text(plan)
                    .font(.system(size: style == .lockScreen ? 11 : 10, weight: .medium))
                    .foregroundStyle(accent)
                    .lineLimit(style == .lockScreen ? 2 : 1)
                    .minimumScaleFactor(0.65)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if style == .lockScreen, let s = state.planStop1, !s.isEmpty {
                Text(s)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            if style == .lockScreen, let s = state.planStop2, !s.isEmpty {
                Text(s)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            if style == .lockScreen {
                tpmsRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Image("EtubuLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
            Text(state.shortDestination)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            if let c = state.outsideC {
                Text("\(c)°")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            Text(Self.clock24())
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
        }
    }

    private var hudRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(min(state.kmh, 999))")
                .font(.system(size: style == .lockScreen ? 28 : 22, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(state.overLimit == true ? .orange : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .layoutPriority(2)
            VStack(alignment: .leading, spacing: 0) {
                Text(state.gear)
                    .font(.system(size: style == .lockScreen ? 13 : 11, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                Text("km/h")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
            if let lim = state.limitKmh, lim > 0 {
                Text("\(lim)")
                    .font(.system(size: style == .lockScreen ? 13 : 11, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(state.overLimit == true ? .orange : .white.opacity(0.8))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(
                        Circle().strokeBorder(state.overLimit == true ? Color.orange : Color.white.opacity(0.45), lineWidth: 1.4)
                            .padding(-3)
                    )
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 0) {
                if let soc = state.socPercent {
                    Text("\(soc)%")
                        .font(.system(size: style == .lockScreen ? 16 : 13, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(soc <= 15 ? .orange : Color(red: 0.40, green: 0.95, blue: 0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                HStack(spacing: 4) {
                    if let range = state.rangeKm {
                        Text("\(range) km")
                            .lineLimit(1)
                    }
                    if let kw = state.powerKw, abs(kw) >= 4 {
                        Text("\(kw) kW")
                            .foregroundStyle(kw < 0 ? Color(red: 0.35, green: 0.92, blue: 0.55) : accent)
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
                .minimumScaleFactor(0.65)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var routeRow: some View {
        HStack(spacing: 8) {
            if let eta = state.etaClockLabel {
                labeled(state.islandEtaLabel.isEmpty ? "ETA" : state.islandEtaLabel, eta)
            }
            if let km = state.remainKm, km > 0 {
                labeled(
                    state.islandKmRemainLabel.isEmpty ? "km" : state.islandKmRemainLabel,
                    km >= 10 ? String(format: "%.0f", km) : String(format: "%.1f", km)
                )
            }
            if let arr = state.arrivalSocPercent {
                labeled("SoC", "\(arr)%")
            }
            if let wh = state.planWhPerKm, style == .lockScreen {
                labeled("Wh", "\(wh)")
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: style == .lockScreen ? 11 : 10, weight: .semibold).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.65)
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(title)
                .foregroundStyle(.white.opacity(0.42))
                .lineLimit(1)
            Text(value)
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var tpmsRow: some View {
        let vals = [state.tpmsFL, state.tpmsFR, state.tpmsRL, state.tpmsRR].compactMap { $0 }
        if !vals.isEmpty {
            HStack(spacing: 8) {
                tpms("FL", state.tpmsFL)
                tpms("FR", state.tpmsFR)
                tpms("RL", state.tpmsRL)
                tpms("RR", state.tpmsRR)
                Spacer(minLength: 0)
            }
            .font(.system(size: 9, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white.opacity(0.5))
        }
    }

    private func tpms(_ corner: String, _ psi: Int?) -> some View {
        Text(psi.map { "\(corner) \($0)" } ?? "\(corner) —")
            .lineLimit(1)
    }

    private static func clock24() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }
}

@available(iOS 16.2, *)
private extension EtubuDriveAttributes.ContentState {
    var accentColor: Color {
        Color(
            red: accentR ?? 0.92,
            green: accentG ?? 0.22,
            blue: accentB ?? 0.22
        )
    }

    var canvasColor: Color {
        Color(
            red: canvasR ?? 0.04,
            green: canvasG ?? 0.04,
            blue: canvasB ?? 0.045
        )
    }
}
