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
    let showSparkline: Bool
    let mapWashHeight: CGFloat
    let iconHit: CGFloat

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
        let leadPad = edge == .leading ? max(camGutter + 4, 10) : max(leadIns + 4, 8)
        let trailPad = edge == .trailing ? max(camGutter + 4, 10) : max(trailIns + 4, 8)

        let usableW = max(200, size.width - leadPad - trailPad - 4)
        let usableH = max(120, size.height - topIns - botIns - 4)

        // Design ref ≈ landscape Pro; clamp soft so SE…Max all fit.
        var scale = min(usableW / 820, usableH / 360)
        scale = min(1.14, max(0.62, scale))

        var dialChrome = min(usableH * 0.74, usableW * 0.36) * scale
        dialChrome = min(320, max(132, dialChrome))
        var dialSize = min(usableH * 0.90, dialChrome * 1.15)
        var boxW = min(usableW * 0.17, dialChrome * 0.58)
        boxW = min(180, max(84, boxW))
        var sideW = min(usableW * 0.145, max(80, (usableW - dialSize - boxW - 16) * 0.48))
        sideW = min(152, max(72, sideW))

        // Fit-to-width: independent floors can overflow SE landscape — shrink together.
        let gaps: CGFloat = 16
        let budget = usableW - gaps
        var total = dialSize + boxW + sideW * 2
        if total > budget, total > 1 {
            let k = budget / total
            dialSize *= k
            dialChrome *= k
            boxW *= k
            sideW *= k
            scale *= k
        }

        // Fit-to-height vs dial (top/bottom bars claim ~70–90pt).
        let barReserve = min(96, max(56, usableH * 0.22))
        let dialBudget = max(110, usableH - barReserve)
        if dialSize > dialBudget {
            let k = dialBudget / dialSize
            dialSize *= k
            dialChrome *= k
        }

        let compactH = usableH < 300 || size.height < 390
        let compactW = usableW < 560 || size.width < 700
        let fontScale = min(1.22, max(0.78, scale * 1.12))

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
            signSize: min(40, max(24, dialChrome * 0.14)),
            leadPad: leadPad,
            trailPad: trailPad,
            topChrome: max(topIns, 4),
            contentHPad: compactW ? 8 : 12,
            contentVGap: compactH ? 2 : 4,
            isCompactHeight: compactH,
            isCompactWidth: compactW,
            showSparkline: !compactH,
            mapWashHeight: min(size.height * 0.55, usableH),
            iconHit: compactW ? 36 : 40,
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
        let compactW = size.width < 390

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
        let bottomReserve: CGFloat = compactH ? 210 : 280
        let dialHBudget = max(130, usableH - bottomReserve)
        if dialSize > dialHBudget {
            dialSize = dialHBudget
        }

        var boxW = min(126, usableW * 0.27) * scale
        boxW = min(boxW, max(72, usableW - dialSize - 18))

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
            signSize: compactH ? 28 : 34,
            leadPad: max(insets.leading, 6),
            trailPad: max(insets.trailing, 6),
            topChrome: topChrome,
            contentHPad: compactW ? 10 : 12,
            contentVGap: compactH ? 2 : 6,
            isCompactHeight: compactH,
            isCompactWidth: compactW,
            showSparkline: !compactH && size.height >= 760,
            mapWashHeight: mapWash,
            iconHit: compactW ? 36 : 40,
            cutoutEdge: nil,
            cutoutStyle: style
        )
    }
}
