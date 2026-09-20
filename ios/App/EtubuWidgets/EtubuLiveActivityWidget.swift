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
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .activityBackgroundTint(context.state.canvasColor)
            .activitySystemActionForegroundColor(context.state.accentColor)
        } dynamicIsland: { context in
            let accent = context.state.accentColor
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image("EtubuLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .padding(.leading, 6)
                        .frame(maxWidth: 56, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    labeledBattery(context.state, compact: true)
                        .padding(.trailing, 6)
                        .frame(maxWidth: 110, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Color.clear.frame(height: 1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    EtubuIslandCanvas(state: context.state, style: .island)
                        .padding(.horizontal, 10)
                        .padding(.top, 2)
                        .padding(.bottom, 6)
                }
            } compactLeading: {
                Image("EtubuLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
            } compactTrailing: {
                compactTrailing(context.state)
            } minimal: {
                Image("EtubuLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
            }
            .keylineTint(accent)
            .widgetURL(URL(string: "com.etubu.app://drive"))
        }
    }

    @ViewBuilder
    private func compactTrailing(_ state: EtubuDriveAttributes.ContentState) -> some View {
        let accent = state.accentColor
        Group {
            if let soc = state.socPercent {
                Text(Self.labeled(state.batteryCaption, "%\(soc)"))
                    .foregroundStyle(soc <= 15 ? .orange : Color(red: 0.35, green: 0.95, blue: 0.55))
            } else if let lim = state.limitKmh, lim > 0 {
                Text(Self.labeled(state.limitCaption, "\(lim)"))
                    .foregroundStyle(state.overLimit == true ? .orange : accent)
            } else {
                Text("—")
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
        .minimumScaleFactor(0.4)
        .lineLimit(1)
        .frame(maxWidth: 72, alignment: .trailing)
    }

    @ViewBuilder
    private func labeledBattery(_ state: EtubuDriveAttributes.ContentState, compact: Bool) -> some View {
        if let soc = state.socPercent {
            Text(Self.labeled(state.batteryCaption, "%\(soc)"))
                .font(.system(size: compact ? 12 : 13, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(soc <= 15 ? .orange : Color(red: 0.40, green: 0.95, blue: 0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(.trailing)
        }
    }

    static func labeled(_ caption: String, _ value: String) -> String {
        let cap = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        if cap.isEmpty { return value }
        return "\(cap): \(value)"
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

    var body: some View {
        VStack(alignment: .leading, spacing: style == .lockScreen ? 6 : 4) {
            if style == .lockScreen {
                headerRow
            }

            hudRow

            if state.routeActive {
                destWeatherRow
            }

            if let trip = state.lastTripLine, !trip.isEmpty, !state.routeActive {
                Text(trip)
                    .font(.system(size: style == .lockScreen ? 11 : 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if style == .lockScreen {
                tpmsRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image("EtubuLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
            Text("Etubu")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(Self.clock24())
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
        }
    }

    private var hudRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let soc = state.socPercent {
                VStack(alignment: .leading, spacing: 1) {
                    if !state.batteryCaption.isEmpty {
                        Text(state.batteryCaption)
                            .font(.system(size: style == .lockScreen ? 10 : 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                    Text("%\(soc)")
                        .font(.system(size: style == .lockScreen ? 26 : 20, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(soc <= 15 ? .orange : Color(red: 0.40, green: 0.95, blue: 0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                }
                .layoutPriority(2)
            }
            if let lim = state.limitKmh, lim > 0 {
                VStack(alignment: .leading, spacing: 1) {
                    if !state.limitCaption.isEmpty {
                        Text(state.limitCaption)
                            .font(.system(size: style == .lockScreen ? 10 : 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                    Text("\(lim)")
                        .font(.system(size: style == .lockScreen ? 16 : 13, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(state.overLimit == true ? .orange : .white.opacity(0.88))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .overlay(
                            Circle().strokeBorder(state.overLimit == true ? Color.orange : Color.white.opacity(0.45), lineWidth: 1.4)
                                .padding(-3)
                        )
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var destWeatherRow: some View {
        let dest = state.routeTo.trimmingCharacters(in: .whitespacesAndNewlines)
        if !dest.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(dest)
                    .font(.system(size: style == .lockScreen ? 13 : 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !state.destWeatherSymbol.isEmpty, let temp = state.destWeatherTempC {
                    HStack(spacing: 5) {
                        Image(systemName: state.destWeatherSymbol)
                            .font(.system(size: style == .lockScreen ? 12 : 11, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                        Text("\(temp)°C")
                            .font(.system(size: style == .lockScreen ? 12 : 11, weight: .semibold).monospacedDigit())
                    }
                    .foregroundStyle(.white.opacity(0.78))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
