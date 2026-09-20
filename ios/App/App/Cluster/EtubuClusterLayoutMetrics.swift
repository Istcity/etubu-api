import SwiftUI
import UIKit

/// Single device-adaptive layout pass for every iPhone size (SE → Pro Max) and orientation.
/// Built from the live canvas (`GeometryReader`) + safe area — not `UIScreen.main`.
struct EtubuClusterLayoutMetrics {
    let canvas: CGSize
    let insets: EdgeInsets
    let landscape: Bool

    let scale: CGFloat
    let fontScale: CGFloat

    let dialSize: CGFloat
    /// Landscape: gear / unit / kW chrome diameter (speed digits use `dialSize`).
    let dialChrome: CGFloat
    let boxW: CGFloat
    let sideW: CGFloat
    let signSize: CGFloat

    let leadPad: CGFloat
    let trailPad: CGFloat
    let topChrome: CGFloat
    let contentHPad: CGFloat
    let contentVGap: CGFloat

    let isCompactHeight: Bool
    let isCompactWidth: Bool
    /// Top icon strip uses compact glyphs + tight gaps (always on portrait phones).
    let chromeCompact: Bool
    let chromeGap: CGFloat
    let showSparkline: Bool
    let mapWashHeight: CGFloat
    let iconHit: CGFloat
    /// Nose-up TPMS car + psi labels — hard box so the graphic cannot report a taller ideal size.
    let tpmsMaxW: CGFloat
    let tpmsMaxH: CGFloat
    /// Portrait bottom-left cluster (TPMS) — scales SE → Max; not camera chrome.
    let bottomClusterLead: CGFloat
    let bottomClusterTrail: CGFloat
    let bottomClusterPad: CGFloat
    /// Portrait MapKit Legal inset so “Yasal” sits to the right of TPMS.
    let mapLegalLead: CGFloat

    var cutoutEdge: HorizontalAlignment?
    var cutoutStyle: EtubuCameraCutout.Style

    // MARK: - Factory

    static func make(
        size: CGSize,
        insets: EdgeInsets,
        landscape: Bool,
        cutout: EtubuCameraCutout.Geometry?
    ) -> EtubuClusterLayoutMetrics {
        if landscape {
            return makeLandscape(size: size, insets: insets, cutout: cutout)
        }
        return makePortrait(size: size, insets: insets, cutout: cutout)
    }

    /// Push font scale for this canvas — call from onAppear / onChange, never inside `body` math alone if mutating.
    func applyFontScale() {
        EtubuClusterFonts.setContentScale(fontScale)
    }

    // MARK: - Landscape

    private static func makeLandscape(
        size: CGSize,
        insets: EdgeInsets,
        cutout: EtubuCameraCutout.Geometry?
    ) -> EtubuClusterLayoutMetrics {
        let leadIns = max(0, insets.leading)
        let trailIns = max(0, insets.trailing)
        let topIns = max(0, insets.top)
        let botIns = max(0, insets.bottom)
        let edge = cutout?.landscapeEdge ?? (leadIns > trailIns ? .leading : .trailing)
        let style = cutout?.style ?? .none

        // Camera gutter scales with real inset (SE ~0, DI ~59) — no fake 40pt floor on home-button phones.
        let camInset = edge == .leading ? leadIns : trailIns
        let camGutter: CGFloat = {
            if style == .none || camInset < 20 { return max(camInset, 8) }
            return max(camInset, style == .dynamicIsland ? 44 : 36)
        }()
        let rawLeadPad = edge == .leading ? max(camGutter + 8, 16) : max(leadIns + 8, 14)
        let rawTrailPad = edge == .trailing ? max(camGutter + 8, 16) : max(trailIns + 8, 14)
        let symPad = max(rawLeadPad, rawTrailPad)
        let leadPad = symPad
        let trailPad = symPad

        let usableW = max(200, size.width - leadPad - trailPad - 4)
        let usableH = max(120, size.height - topIns - botIns - 4)

        // Design ref ≈ landscape Pro; clamp soft so SE…Max all fit.
        var scale = min(usableW / 820, usableH / 360)
        scale = min(1.14, max(0.62, scale))

        // Dual symmetrical dials (Left Speedometer & Right Multi-Function Gauge)
        var dialChrome = min(usableH * 0.84, usableW * 0.30) * scale
        dialChrome = min(295, max(130, dialChrome))
        var dialSize = dialChrome
        var boxW = min(usableW * 0.26, max(120, usableW * 0.22 * scale))
        boxW = min(200, max(110, boxW))
        var sideW = min(68, max(44, usableW * 0.08 * scale))

        // Fit-to-width: [Left Dial] + [Left Flank] + [Center Cards] + [Right Flank] + [Right Dial]
        let gaps: CGFloat = 20
        let budget = usableW - gaps
        var total = dialSize * 2 + boxW + sideW * 2
        if total > budget, total > 1 {
            let k = budget / total
            dialSize *= k
            dialChrome *= k
            boxW *= k
            sideW *= k
            scale *= k
        }

        // Fit-to-height vs dial (top/bottom bars + ring glow bloom).
        let barReserve = min(72, max(42, usableH * 0.16))
        let glowReserve: CGFloat = 10
        let dialBudget = max(110, usableH - barReserve - glowReserve)
        if dialSize > dialBudget {
            let k = dialBudget / dialSize
            dialSize *= k
            dialChrome *= k
        }

        let compactH = usableH < 300 || size.height < 390
        let compactW = usableW < 560 || size.width < 700
        let fontScale = min(1.22, max(0.78, scale * 1.12))
        var signSize = min(36, max(22, dialChrome * 0.13))
        let tpmsMaxW = max(44, sideW)
        let tpmsMaxH = min(
            compactH ? 108 : 132,
            max(68, min(usableH * 0.52, usableH - 80))
        )
        let chromeCompact = true
        let chromeGap: CGFloat = compactW ? 3 : 5
        let iconHit: CGFloat = compactH ? 30 : 34

        return EtubuClusterLayoutMetrics(
            canvas: size,
            insets: insets,
            landscape: true,
            scale: scale,
            fontScale: fontScale,
            dialSize: dialSize.rounded(.toNearestOrAwayFromZero),
            dialChrome: dialChrome.rounded(.toNearestOrAwayFromZero),
            boxW: boxW.rounded(.toNearestOrAwayFromZero),
            sideW: sideW.rounded(.toNearestOrAwayFromZero),
            signSize: signSize.rounded(.toNearestOrAwayFromZero),
            leadPad: leadPad,
            trailPad: trailPad,
            topChrome: max(topIns, 4),
            contentHPad: compactW ? 8 : 12,
            contentVGap: compactH ? 2 : 4,
            isCompactHeight: compactH,
            isCompactWidth: compactW,
            chromeCompact: chromeCompact,
            chromeGap: chromeGap,
            showSparkline: !compactH,
            mapWashHeight: min(size.height * 0.55, usableH),
            iconHit: iconHit.rounded(.toNearestOrAwayFromZero),
            tpmsMaxW: tpmsMaxW.rounded(.toNearestOrAwayFromZero),
            tpmsMaxH: tpmsMaxH.rounded(.toNearestOrAwayFromZero),
            bottomClusterLead: 8,
            bottomClusterTrail: 8,
            bottomClusterPad: 4,
            mapLegalLead: 0,
            cutoutEdge: edge,
            cutoutStyle: style
        )
    }

    // MARK: - Portrait

    private static func makePortrait(
        size: CGSize,
        insets: EdgeInsets,
        cutout: EtubuCameraCutout.Geometry?
    ) -> EtubuClusterLayoutMetrics {
        let style = cutout?.style ?? .none
        let topIns = max(0, insets.top)
        let botIns = max(0, insets.bottom)
        let cutoutAtBottom = cutout?.anchor == .bottom

        let compactH = size.height < 720
        // 17e (390) and 17 Pro (402) must use compact chrome — 7×40pt icons overflow.
        let compactW = size.width < 428

        var scale = min(size.width / 402, size.height / 874)
        scale = min(1.10, max(0.72, scale))

        // Camera band clearance — top for upright, bottom for upside-down.
        let cameraChrome: CGFloat = {
            switch style {
            case .dynamicIsland:
                if let cutout {
                    if cutoutAtBottom {
                        return max(botIns + 4, size.height - cutout.pill.minY + 6, 28)
                    }
                    return max(topIns + 4, cutout.pill.maxY + 6, 28)
                }
                return max((cutoutAtBottom ? botIns : topIns) + 4, 28)
            case .notch:
                return max((cutoutAtBottom ? botIns : topIns) + 2, 22)
            case .none:
                return max((cutoutAtBottom ? botIns : topIns) + 6, 12)
            }
        }()

        let topChrome = cutoutAtBottom ? max(topIns + 4, 12) : cameraChrome
        let bottomChrome = cutoutAtBottom ? cameraChrome : botIns
        let usableH = max(280, size.height - topChrome - bottomChrome - 8)
        let usableW = max(280, size.width - 16)

        var dialFrac: CGFloat = compactW ? 0.46 : 0.52
        var dialCap: CGFloat = compactH ? 220 : 300
        if !compactH, size.height >= 900 { dialCap = 310 }
        if compactH, size.height < 680 { dialCap = 200; dialFrac = 0.44 }

        var dialSize = min(dialCap, usableW * dialFrac) * scale
        let twinShare = min(126, usableW * 0.27) * scale
        if dialSize + twinShare + 20 > usableW {
            dialSize = max(120, usableW - twinShare - 20)
        }

        let homeIndicator = botIns >= 20
        let wide = size.width >= 428
        let bottomClusterLead: CGFloat = {
            if compactW { return homeIndicator ? 20 : 16 }
            return wide ? 30 : 26
        }()
        let bottomClusterTrail: CGFloat = compactW ? 14 : 20
        let bottomClusterPad: CGFloat = {
            if !homeIndicator { return compactH ? 10 : 14 }
            if compactH { return 16 }
            return wide ? 26 : 22
        }()
        let clockReserve: CGFloat = compactH ? 100 : 128
        let tpmsBudgetW = max(
            72,
            usableW - bottomClusterLead - bottomClusterTrail - clockReserve - 10
        )
        let tpmsMaxH: CGFloat = {
            let cap: CGFloat = compactH
                ? (size.height < 680 ? 78 : 90)
                : (size.height >= 920 ? 120 : 108)
            let floor: CGFloat = compactH ? 64 : 80
            return min(cap, max(floor, usableH * (compactH ? 0.12 : 0.125)))
        }()
        let tpmsMaxW: CGFloat = {
            let fromHeight = tpmsMaxH * (680.0 / 1408.0) + (compactW ? 36 : 48)
            return min(tpmsBudgetW, fromHeight, compactW ? 110 : 132)
        }()
        let mapLegalLead = min(
            usableW * 0.40,
            max(insets.leading, 6) + bottomClusterLead + tpmsMaxW + 8
        )

        let bottomReserve: CGFloat = compactH ? (132 + tpmsMaxH) : (148 + tpmsMaxH)
        let dialHBudget = max(130, usableH - bottomReserve)
        if dialSize > dialHBudget {
            dialSize = dialHBudget
        }

        var boxW = min(126, usableW * 0.27) * scale
        boxW = min(boxW, max(72, usableW - dialSize - 18))
        var signSize: CGFloat = compactH ? 28 : 32
        let rowGaps: CGFloat = compactW ? 14 : 20
        let rowBudget = max(200, usableW - rowGaps)
        let rowTotal = dialSize + boxW + signSize
        if rowTotal > rowBudget, rowTotal > 1 {
            let k = rowBudget / rowTotal
            dialSize *= k
            boxW *= k
            signSize *= k
        }

        let chromeGap: CGFloat = size.width < 400 ? 2 : 3
        let chipReserve: CGFloat = 100
        let chromeN: CGFloat = 7
        let chromeBudget = max(196, usableW - chipReserve)
        let iconHit = min(34, max(28, (chromeBudget - (chromeN - 1) * chromeGap) / chromeN))

        let fontScale = min(1.16, max(0.78, scale * 0.95))
        let mapWash = min(compactH ? 280 : 420, size.height * (compactH ? 0.36 : 0.42))

        return EtubuClusterLayoutMetrics(
            canvas: size,
            insets: insets,
            landscape: false,
            scale: scale,
            fontScale: fontScale,
            dialSize: dialSize.rounded(.toNearestOrAwayFromZero),
            dialChrome: dialSize.rounded(.toNearestOrAwayFromZero),
            boxW: boxW.rounded(.toNearestOrAwayFromZero),
            sideW: 0,
            signSize: signSize.rounded(.toNearestOrAwayFromZero),
            leadPad: max(insets.leading, 10),
            trailPad: max(insets.trailing, 10),
            topChrome: topChrome,
            contentHPad: compactW ? 14 : 16,
            contentVGap: compactH ? 2 : 6,
            isCompactHeight: compactH,
            isCompactWidth: compactW,
            chromeCompact: true,
            chromeGap: chromeGap,
            showSparkline: !compactH && size.height >= 760,
            mapWashHeight: mapWash,
            iconHit: iconHit.rounded(.toNearestOrAwayFromZero),
            tpmsMaxW: tpmsMaxW.rounded(.toNearestOrAwayFromZero),
            tpmsMaxH: tpmsMaxH.rounded(.toNearestOrAwayFromZero),
            bottomClusterLead: bottomClusterLead.rounded(.toNearestOrAwayFromZero),
            bottomClusterTrail: bottomClusterTrail.rounded(.toNearestOrAwayFromZero),
            bottomClusterPad: bottomClusterPad.rounded(.toNearestOrAwayFromZero),
            mapLegalLead: mapLegalLead.rounded(.toNearestOrAwayFromZero),
            cutoutEdge: nil,
            cutoutStyle: style
        )
    }
}
