import Foundation
import ActivityKit
import AVFoundation
import UIKit
import SwiftUI

/// Live Activity + Dynamic Island — sürüş sırasında ön/arka plan.
@available(iOS 16.2, *)
enum EtubuLiveActivityController {
    private static var current: Activity<EtubuDriveAttributes>?
    private static var engine: AVAudioEngine?
    private static var player: AVAudioPlayerNode?

    /// Uygulama öldürülürse güncelleme kesilir; seyrek meaningful update’lerde
    /// 75 s bayat çok kısa kalır (Apple: hız tick’i basma).
    private static let staleSeconds: TimeInterval = 4 * 60 * 60
    private static var lastMeaningfulSignature = ""

    /// Sürüş aktifken LA/Island güncellenir — park/idle bağlıyken sürekli tutma.
    @MainActor
    static var isDriveSessionAllowed: Bool {
        let t = EtubuVehicleTelemetry.shared
        if EtubuDemoDrive.isActive { return true }
        // Hareket veya aktif rota — Island anlamlı; salt BLE bağlı parkta kapat.
        return t.kmh >= 3 || t.routeActive
    }

    static func ensureAudioSession(mixWithOthers: Bool) {
        if mixWithOthers {
            AppDelegate.activateDriveAudioSession()
        } else {
            UserDefaults.standard.set("solo", forKey: "etubu.cluster.mixMode")
            AppDelegate.activateDriveAudioSession()
        }
    }

    /// Arka planda audio session canlı kalsın — yalnızca background'da çağır.
    static func startSilentKeepalive() {
        guard engine == nil else { return }
        let eng = AVAudioEngine()
        let node = AVAudioPlayerNode()
        eng.attach(node)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1) else { return }
        eng.connect(node, to: eng.mainMixerNode, format: format)
        eng.mainMixerNode.outputVolume = 0.0001

        let frames = AVAudioFrameCount(22050)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buffer.frameLength = frames
        if let ch = buffer.floatChannelData?[0] {
            for i in 0..<Int(frames) {
                ch[i] = 0.00005 * sinf(Float(i) * 0.01)
            }
        }
        do {
            try eng.start()
            node.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
            node.play()
            engine = eng
            player = node
        } catch {
            print("ETUBU keepalive:", error)
        }
    }

    static func stopSilentKeepalive() {
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
    }

    private static func makeContent(state: EtubuDriveAttributes.ContentState) -> ActivityContent<EtubuDriveAttributes.ContentState> {
        ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(staleSeconds)
        )
    }

    /// Build state from live telemetry + route brief (Island / lock screen).
    @MainActor
    static func makeState(
        voice: String = "ETUBU",
        kmh: Int? = nil,
        gear: String? = nil,
        rpm: Int? = nil,
        source: String? = nil
    ) -> EtubuDriveAttributes.ContentState {
        let t = EtubuVehicleTelemetry.shared
        let w = EtubuDriveWarnings.shared
        let routeOn = t.routeActive
        let rb = routeOn ? w.remainingBrief : EtubuRouteBriefSummary()
        let remaining = routeOn ? w.remainingHazards : []
        let warnPrimary: String = {
            guard routeOn else { return "" }
            if let p = w.primary {
                let dist = p.distanceLabel.isEmpty ? "" : " · \(p.distanceLabel)"
                return String(("\(p.title)\(dist)").prefix(52))
            }
            if let h = remaining.first {
                let dist = h.distanceLabel.isEmpty ? "" : " · \(h.distanceLabel)"
                let name = h.label.isEmpty ? h.kindTitle : h.label
                return String(("\(h.kindTitle): \(name)\(dist)").prefix(52))
            }
            return ""
        }()
        let warn2: String = {
            guard routeOn, remaining.count > 1 else { return "" }
            let h = remaining[1]
            let dist = h.distanceLabel.isEmpty ? "" : " · \(h.distanceLabel)"
            let name = h.label.isEmpty ? h.kindTitle : h.label
            return String(("\(h.kindTitle): \(name)\(dist)").prefix(48))
        }()
        let theme = ClusterTheme.stored
        let accent = Self.rgb(theme.accent)
        let canvas = Self.rgb(theme.canvas)
        let plan = EtubuEvRoutePlanner.shared.plan
        return EtubuDriveAttributes.ContentState(
            kmh: kmh ?? t.kmh,
            gear: gear ?? t.gear,
            rpm: rpm ?? t.rpm,
            voice: voice,
            source: source ?? (t.source == .none ? "idle" : t.source.rawValue),
            tpmsFL: t.tpmsFL.psi.map { Int($0.rounded()) },
            tpmsFR: t.tpmsFR.psi.map { Int($0.rounded()) },
            tpmsRL: t.tpmsRL.psi.map { Int($0.rounded()) },
            tpmsRR: t.tpmsRR.psi.map { Int($0.rounded()) },
            routeActive: routeOn,
            routeFrom: t.routeFrom.isEmpty ? EtubuClusterL10n.myLocation : t.routeFrom,
            routeTo: t.routeTo,
            radarCount: rb.radarCount,
            corridorCount: rb.corridorCount,
            chargeCount: rb.chargeCount,
            controlCount: rb.controlCount,
            weatherCount: rb.weatherCount,
            primaryWarn: warnPrimary,
            aheadWarn2: warn2,
            remainingPoints: remaining.count,
            socPercent: t.displaySocPercent ?? t.socPercent,
            rangeKm: t.displayRangeKm ?? t.rangeKm,
            remainKm: t.effectiveRemainKm,
            etaMinutes: t.navEtaMinutes.map { Int($0.rounded()) },
            arrivalSocPercent: plan?.destSocPlanned ?? t.energyAtArrivalPercent,
            islandEtaLabel: EtubuClusterL10n.t("islandEtaRemain"),
            islandKmRemainLabel: EtubuClusterL10n.t("islandKmRemain"),
            limitKmh: EtubuOsmSpeedLimit.shared.limitKmh,
            overLimit: {
                guard let lim = EtubuOsmSpeedLimit.shared.limitKmh, lim > 0 else { return false }
                return (kmh ?? t.kmh) > lim + 3
            }(),
            accentR: accent.0,
            accentG: accent.1,
            accentB: accent.2,
            canvasR: canvas.0,
            canvasG: canvas.1,
            canvasB: canvas.2,
            outsideC: t.outsideC.map { Int($0.rounded()) },
            powerKw: t.powerKw,
            planSummary: plan?.summaryLine,
            planStop1: plan?.legs.first.map { String($0.compactLine.prefix(52)) },
            planStop2: plan?.legs.dropFirst().first.map { String($0.compactLine.prefix(52)) },
            planWhPerKm: plan.map { Int($0.whPerKm.rounded()) }
        )
    }

    static func start(
        voice: String,
        kmh: Int,
        gear: String,
        rpm: Int,
        source: String,
        tpmsFL: Int? = nil,
        tpmsFR: Int? = nil,
        tpmsRL: Int? = nil,
        tpmsRR: Int? = nil
    ) async -> Bool {
        let allowed = await MainActor.run { isDriveSessionAllowed }
        guard allowed else {
            return false
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("ETUBU Live Activity: disabled in Settings")
            return false
        }
        if let existing = current ?? Activity<EtubuDriveAttributes>.activities.first {
            current = existing
            await publishState(
                await MainActor.run {
                    var s = makeState(voice: voice, kmh: kmh, gear: gear, rpm: rpm, source: source)
                    if tpmsFL != nil { s.tpmsFL = tpmsFL }
                    if tpmsFR != nil { s.tpmsFR = tpmsFR }
                    if tpmsRL != nil { s.tpmsRL = tpmsRL }
                    if tpmsRR != nil { s.tpmsRR = tpmsRR }
                    return s
                },
                force: true
            )
            return true
        }
        let attributes = EtubuDriveAttributes(startedAt: Date())
        let state = await MainActor.run {
            var s = makeState(voice: voice, kmh: kmh, gear: gear, rpm: rpm, source: source)
            if tpmsFL != nil { s.tpmsFL = tpmsFL }
            if tpmsFR != nil { s.tpmsFR = tpmsFR }
            if tpmsRL != nil { s.tpmsRL = tpmsRL }
            if tpmsRR != nil { s.tpmsRR = tpmsRR }
            return s
        }
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: makeContent(state: state),
                pushType: nil
            )
            current = activity
            lastMeaningfulSignature = meaningfulSignature(state)
            return true
        } catch {
            print("ETUBU Live Activity start:", error)
            return false
        }
    }

    static func update(
        kmh: Int,
        gear: String,
        rpm: Int,
        voice: String,
        source: String,
        tpmsFL: Int? = nil,
        tpmsFR: Int? = nil,
        tpmsRL: Int? = nil,
        tpmsRR: Int? = nil
    ) async {
        let allowed = await MainActor.run { isDriveSessionAllowed }
        guard allowed else { return }
        guard let activity = current ?? Activity<EtubuDriveAttributes>.activities.first else { return }
        current = activity
        let state = await MainActor.run {
            var s = makeState(voice: voice, kmh: kmh, gear: gear, rpm: rpm, source: source)
            if tpmsFL != nil { s.tpmsFL = tpmsFL }
            if tpmsFR != nil { s.tpmsFR = tpmsFR }
            if tpmsRL != nil { s.tpmsRL = tpmsRL }
            if tpmsRR != nil { s.tpmsRR = tpmsRR }
            return s
        }
        await publishState(state, force: false)
    }

    /// Sürüşte Island/LA güncelle; yoksa başlat. Oturum bitince kapat.
    static func publishCurrent(voice: String = "ETUBU") async {
        let allowed = await MainActor.run { isDriveSessionAllowed }
        guard allowed else {
            await end()
            return
        }
        guard let activity = current ?? Activity<EtubuDriveAttributes>.activities.first else {
            let snap = await MainActor.run { () -> (Int, String, Int, String) in
                let t = EtubuVehicleTelemetry.shared
                return (t.kmh, t.gear, t.rpm, t.source == .none ? "idle" : t.source.rawValue)
            }
            _ = await start(voice: voice, kmh: snap.0, gear: snap.1, rpm: snap.2, source: snap.3)
            return
        }
        current = activity
        let state = await MainActor.run { makeState(voice: voice) }
        await publishState(state, force: false)
    }

    /// Gear / SoC / warn / nav — never live speed. Apple ActivityKit budget.
    private static func meaningfulSignature(_ s: EtubuDriveAttributes.ContentState) -> String {
        let remain = s.remainKm.map { Int(($0 * 10).rounded()) } ?? -1
        let soc = s.socPercent ?? -1
        let range = s.rangeKm ?? -1
        let eta = s.etaMinutes ?? -1
        let arrival = s.arrivalSocPercent ?? -1
        let limit = s.limitKmh ?? -1
        let over = (s.overLimit ?? false) ? 1 : 0
        let routeFlag = s.routeActive ? 1 : 0
        let tpms = "\(s.tpmsFL ?? -1),\(s.tpmsFR ?? -1),\(s.tpmsRL ?? -1),\(s.tpmsRR ?? -1)"
        let counts = "\(s.radarCount),\(s.corridorCount),\(s.chargeCount),\(s.controlCount),\(s.weatherCount),\(s.remainingPoints)"
        return "\(s.gear)|\(s.source)|\(soc)|\(range)|\(remain)|\(eta)|\(arrival)|\(routeFlag)|\(s.routeTo)|\(counts)|\(s.primaryWarn)|\(s.aheadWarn2)|\(limit)|\(over)|\(tpms)|\(s.planSummary ?? "")|\(s.outsideC ?? -1)"
    }

    private static func publishState(
        _ state: EtubuDriveAttributes.ContentState,
        force: Bool
    ) async {
        guard let activity = current ?? Activity<EtubuDriveAttributes>.activities.first else { return }
        current = activity
        let sig = meaningfulSignature(state)
        if !force, sig == lastMeaningfulSignature { return }
        lastMeaningfulSignature = sig
        await activity.update(makeContent(state: state))
    }

    /// Arka plana geçince Island’ı aç / sürdür.
    static func beginBackgroundSession() async {
        let snap = await MainActor.run { () -> (kmh: Int, gear: String, rpm: Int, source: String, fl: Int?, fr: Int?, rl: Int?, rr: Int?) in
            let t = EtubuVehicleTelemetry.shared
            return (
                t.kmh,
                t.gear,
                t.rpm,
                t.source == .none ? "idle" : t.source.rawValue,
                t.tpmsFL.psi.map { Int($0.rounded()) },
                t.tpmsFR.psi.map { Int($0.rounded()) },
                t.tpmsRL.psi.map { Int($0.rounded()) },
                t.tpmsRR.psi.map { Int($0.rounded()) }
            )
        }
        _ = await start(
            voice: "ETUBU",
            kmh: snap.kmh,
            gear: snap.gear,
            rpm: snap.rpm,
            source: snap.source,
            tpmsFL: snap.fl,
            tpmsFR: snap.fr,
            tpmsRL: snap.rl,
            tpmsRR: snap.rr
        )
    }

    static func end() async {
        stopSilentKeepalive()
        let activities = Activity<EtubuDriveAttributes>.activities
        current = nil
        lastMeaningfulSignature = ""
        for activity in activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Fire-and-forget end from UIKit lifecycle (avoids main-thread semaphore deadlock).
    static func endAllNow() {
        stopSilentKeepalive()
        current = nil
        lastMeaningfulSignature = ""
        Task { @MainActor in
            for activity in Activity<EtubuDriveAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}

@available(iOS 16.2, *)
private extension EtubuLiveActivityController {
    static func rgb(_ color: Color) -> (Double, Double, Double) {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }
}
