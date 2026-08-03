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
                startedAt: context.attributes.startedAt,
                style: .lockScreen
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .activityBackgroundTint(Color.black.opacity(0.92))
            .activitySystemActionForegroundColor(Color(red: 1.0, green: 0.55, blue: 0.2))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 5) {
                        Image(systemName: context.state.routeActive ? "location.fill" : "bolt.car.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.25))
                        Text(context.state.shortDestination)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(Self.clockNow())
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                }
                DynamicIslandExpandedRegion(.center) {
                    Color.clear.frame(height: 1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    EtubuIslandCanvas(
                        state: context.state,
                        startedAt: context.attributes.startedAt,
                        style: .island
                    )
                    .padding(.horizontal, 2)
                    .padding(.top, 2)
                    .padding(.bottom, 4)
                }
            } compactLeading: {
                Image("EtubuLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
            } compactTrailing: {
                compactTrailing(context.state)
            } minimal: {
                if let soc = context.state.socPercent {
                    Text("\(soc)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color(red: 0.35, green: 0.95, blue: 0.55))
                } else {
                    Image("EtubuLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                }
            }
            .keylineTint(Color(red: 1.0, green: 0.45, blue: 0.15))
            .widgetURL(URL(string: "com.etubu.app://drive"))
        }
    }

    @ViewBuilder
    private func compactTrailing(_ state: EtubuDriveAttributes.ContentState) -> some View {
        if state.routeActive, !state.primaryWarn.isEmpty {
            Text(shortWarn(state.primaryWarn))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.orange)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .frame(maxWidth: 56, alignment: .trailing)
        } else if let eta = state.etaClockLabel {
            Text(eta)
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(Color(red: 1.0, green: 0.6, blue: 0.25))
                .minimumScaleFactor(0.55)
                .lineLimit(1)
                .frame(maxWidth: 44, alignment: .trailing)
        } else if let soc = state.socPercent {
            Text("\(soc)%")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(Color(red: 0.35, green: 0.95, blue: 0.55))
                .minimumScaleFactor(0.55)
                .lineLimit(1)
                .frame(maxWidth: 36, alignment: .trailing)
        } else {
            Text("\(min(state.kmh, 999))")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .minimumScaleFactor(0.45)
                .lineLimit(1)
                .frame(maxWidth: 28, alignment: .trailing)
        }
    }

    private func shortWarn(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let dist = t.split(separator: "·").last {
            return String(dist).trimmingCharacters(in: .whitespaces).prefix(8).description
        }
        return String(t.prefix(8))
    }

    private static func clockNow() -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        return f.string(from: Date()).lowercased()
    }
}

// MARK: - Golden-hour canvas (Island + lock screen)

@available(iOS 16.2, *)
private enum EtubuIslandStyle {
    case island
    case lockScreen
}

@available(iOS 16.2, *)
private struct EtubuIslandCanvas: View {
    let state: EtubuDriveAttributes.ContentState
    let startedAt: Date
    let style: EtubuIslandStyle

    private var progress: CGFloat {
        Self.tripProgress(state: state, startedAt: startedAt)
    }

    private var urgent: Bool {
        !state.primaryWarn.isEmpty || (state.socPercent.map { $0 <= 15 } ?? false)
    }

    private var hero: (value: String, label: String) {
        if !state.primaryWarn.isEmpty {
            let short = state.primaryWarn.split(separator: "·").first.map(String.init) ?? state.primaryWarn
            return (String(short.prefix(18)), state.primaryWarn)
        }
        if let eta = state.etaClockLabel {
            let label = state.islandEtaLabel.isEmpty ? "Time left" : state.islandEtaLabel
            return (eta, label)
        }
        if let km = state.remainKm, km > 0 {
            let v = km >= 10 ? String(format: "%.0f", km) : String(format: "%.1f", km)
            let label = state.islandKmRemainLabel.isEmpty ? "km left" : state.islandKmRemainLabel
            return (v, label)
        }
        return ("\(max(0, state.kmh))", "km/h · \(state.gear)")
    }

    private var leftCap: String {
        if let soc = state.socPercent { return "\(soc)%" }
        return state.gear
    }

    private var rightCap: String {
        if let arr = state.arrivalSocPercent { return "\(arr)%" }
        if let km = state.remainKm, km > 0 {
            return km >= 10 ? String(format: "%.0f km", km) : String(format: "%.1f km", km)
        }
        if let range = state.rangeKm { return "\(range) km" }
        return "—"
    }

    var body: some View {
        VStack(spacing: style == .lockScreen ? 8 : 4) {
            if style == .lockScreen {
                headerRow
            }

            EtubuGoldenArc(
                progress: progress,
                leftLabel: leftCap,
                rightLabel: rightCap,
                leftSymbol: state.socPercent != nil ? "bolt.fill" : "flag.fill",
                rightSymbol: state.arrivalSocPercent != nil ? "flag.checkered" : "mappin.and.ellipse",
                urgent: urgent
            )
            .frame(height: style == .lockScreen ? 54 : 44)

            VStack(spacing: 2) {
                Text(hero.value)
                    .font(.system(
                        size: style == .lockScreen ? 34 : 28,
                        weight: .bold,
                        design: .rounded
                    ).monospacedDigit())
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                Text(hero.label)
                    .font(.system(size: style == .lockScreen ? 12 : 11, weight: .medium))
                    .foregroundStyle(urgent
                        ? Color(red: 1.0, green: 0.55, blue: 0.2)
                        : .white.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)

            if style == .lockScreen {
                footerChips
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Image(systemName: state.routeActive ? "location.fill" : "bolt.car.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.25))
            Text(state.shortDestination)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(EtubuLiveActivityWidget.clockLabel())
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    private var footerChips: some View {
        HStack(spacing: 10) {
            Label("\(state.kmh) km/h", systemImage: "gauge.with.dots.needle.67percent")
            if let soc = state.socPercent {
                Label("\(soc)%", systemImage: "bolt.fill")
            }
            Text(state.gear)
                .fontWeight(.bold)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.white.opacity(0.55))
        .labelStyle(.titleAndIcon)
    }

    static func tripProgress(state: EtubuDriveAttributes.ContentState, startedAt: Date) -> CGFloat {
        if let eta = state.etaMinutes, eta >= 0 {
            let remain = Double(eta) * 60
            let elapsed = max(0, Date().timeIntervalSince(startedAt))
            let total = max(elapsed + remain, 1)
            return CGFloat(min(1, max(0, elapsed / total)))
        }
        if let soc = state.socPercent {
            return CGFloat(min(1, max(0, Double(soc) / 100.0)))
        }
        return CGFloat(min(1, max(0, Double(state.kmh) / 130.0)))
    }
}

@available(iOS 16.2, *)
private extension EtubuLiveActivityWidget {
    static func clockLabel() -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        return f.string(from: Date()).lowercased()
    }
}

// MARK: - Arc (sun-path / golden-hour)

@available(iOS 16.2, *)
private struct EtubuGoldenArc: View {
    var progress: CGFloat
    var leftLabel: String
    var rightLabel: String
    var leftSymbol: String
    var rightSymbol: String
    var urgent: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let inset: CGFloat = 28
            let track = arcPath(in: CGSize(width: w, height: h), inset: inset)

            ZStack {
                // Soft glow under the hot zone
                track
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color(red: 0.15, green: 0.35, blue: 0.95).opacity(0.15),
                                Color(red: 1.0, green: 0.45, blue: 0.12).opacity(urgent ? 0.55 : 0.35),
                                Color(red: 0.2, green: 0.35, blue: 0.9).opacity(0.15),
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .blur(radius: 6)
                    .opacity(0.85)

                // Base track
                track
                    .stroke(
                        Color.white.opacity(0.12),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )

                // Colored progress
                track
                    .trim(from: 0, to: max(0.02, min(1, progress)))
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color(red: 0.25, green: 0.45, blue: 1.0),
                                Color(red: 0.45, green: 0.75, blue: 1.0),
                                Color(red: 1.0, green: 0.75, blue: 0.25),
                                Color(red: 1.0, green: 0.35, blue: 0.1),
                            ],
                            center: .center,
                            angle: .degrees(200)
                        ),
                        style: StrokeStyle(lineWidth: 4.5, lineCap: .round)
                    )

                // Knob
                Circle()
                    .fill(.white)
                    .frame(width: 9, height: 9)
                    .shadow(color: Color(red: 1.0, green: 0.5, blue: 0.15).opacity(0.9), radius: 4)
                    .position(pointOnArc(progress: progress, size: CGSize(width: w, height: h), inset: inset))

                // End caps
                HStack {
                    Label(leftLabel, systemImage: leftSymbol)
                    Spacer()
                    Label(rightLabel, systemImage: rightSymbol)
                }
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 2)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    /// Upward sun-path arc (∩).
    private func arcPath(in size: CGSize, inset: CGFloat) -> Path {
        let start = CGPoint(x: inset, y: size.height * 0.72)
        let end = CGPoint(x: size.width - inset, y: size.height * 0.72)
        let control = CGPoint(x: size.width / 2, y: size.height * 0.08)
        var p = Path()
        p.move(to: start)
        p.addQuadCurve(to: end, control: control)
        return p
    }

    private func pointOnArc(progress: CGFloat, size: CGSize, inset: CGFloat) -> CGPoint {
        let t = max(0, min(1, progress))
        let start = CGPoint(x: inset, y: size.height * 0.72)
        let end = CGPoint(x: size.width - inset, y: size.height * 0.72)
        let control = CGPoint(x: size.width / 2, y: size.height * 0.08)
        // Quadratic Bezier
        let mt = 1 - t
        let x = mt * mt * start.x + 2 * mt * t * control.x + t * t * end.x
        let y = mt * mt * start.y + 2 * mt * t * control.y + t * t * end.y
        return CGPoint(x: x, y: y)
    }
}
