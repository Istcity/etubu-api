import SwiftUI
import UIKit
import Darwin

/// Resolves camera cutout / Dynamic Island geometry in **full-screen** coordinates.
/// Landscape: pill is a *vertical* capsule on the physical top edge (camera side) of the phone.
enum EtubuCameraCutout {
    enum Style { case none, notch, dynamicIsland }

    struct Geometry: Equatable {
        var style: Style
        var pill: CGRect
        var aura: CGRect
        var landscapeEdge: HorizontalAlignment?
    }

    /// Spill for FX — symmetric around pill (keep aura.mid == pill.mid).
    static let maxSpillPoints: CGFloat = 36

    // MARK: - Device model → Dynamic Island pill size (points)

    /// Returns (width, height) of the Dynamic Island pill for known Pro-class devices.
    /// Non-Pro / unknown → nil (safe-area heuristics decide notch vs none).
    private static func knownIslandSize() -> (w: CGFloat, h: CGFloat)? {
        let b = UIScreen.main.nativeBounds
        let w = Int(min(b.width, b.height))
        let h = Int(max(b.width, b.height))
        let di = (w: CGFloat(126), h: CGFloat(37.33))
        switch (w, h) {
        case (1179, 2556): return di // 14/15 Pro
        case (1290, 2796): return di // 14/15 Pro Max
        case (1206, 2622): return di // 16 Pro / 17 Pro class
        case (1320, 2868): return di // 16/17 Pro Max class
        case (1284, 2778): return di // legacy Pro Max-ish
        default:
            // utsname fallback for new models with unknown nativeBounds mapping
            let id = machineIdentifier()
            if id.contains("iPhone15,2") || id.contains("iPhone15,3")
                || id.contains("iPhone16,1") || id.contains("iPhone16,2")
                || id.contains("iPhone17,1") || id.contains("iPhone17,2")
                || id.contains("iPhone18") {
                return di
            }
            return nil
        }
    }

    private static func machineIdentifier() -> String {
        var sys = utsname()
        uname(&sys)
        return withUnsafePointer(to: &sys.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }

    // MARK: - Public

    static func resolve(size: CGSize, insets: EdgeInsets, landscape: Bool) -> Geometry? {
        if landscape {
            return resolveLandscape(size: size, insets: insets) ?? fallback(size: size, landscape: true)
        }
        return resolvePortrait(size: size, insets: insets) ?? fallback(size: size, landscape: false)
    }

    /// Simulator / no-cutout devices still get a theme FX pill so settings remain meaningful.
    private static func fallback(size: CGSize, landscape: Bool) -> Geometry {
        let known = knownIslandSize() ?? (126, 37)
        if landscape {
            let shortAxis = known.h
            let longAxis = known.w
            let edge: HorizontalAlignment = .leading
            let pill = CGRect(
                x: max(6, (44 - shortAxis) / 2),
                y: (size.height - longAxis) / 2,
                width: shortAxis,
                height: longAxis
            )
            return makeGeometry(pill: pill, style: .dynamicIsland, size: size, landscapeEdge: edge)
        }
        let w = known.w
        let h = known.h
        let pill = CGRect(x: (size.width - w) / 2, y: max(11, 14), width: w, height: h)
        return makeGeometry(pill: pill, style: .dynamicIsland, size: size, landscapeEdge: nil)
    }

    // MARK: - Portrait

    private static func resolvePortrait(size: CGSize, insets: EdgeInsets) -> Geometry? {
        let top = max(insets.top, windowInset(for: .top))
        guard top >= 44 else { return nil }

        let style: Style = top >= 51 ? .dynamicIsland : .notch
        let pill: CGRect
        switch style {
        case .dynamicIsland:
            let known = knownIslandSize()
            // Hardware DI ~126×37.33. Prefer centering in the top safe band when
            // Cap/overlay insets disagree with the classic y≈11 placement.
            let w = known?.w ?? 126
            let h = known?.h ?? 37.33
            let classicY: CGFloat = 11
            let bandY = max(0, (top - h) * 0.5)
            // Prefer classic when top inset looks like a real DI device (~59).
            let y: CGFloat = (top >= 54 && top <= 64) ? classicY : bandY
            pill = CGRect(x: (size.width - w) / 2, y: y, width: w, height: h)
        case .notch:
            let h = min(34, max(28, top * 0.52))
            let w = min(size.width * 0.48, max(170, size.width * 0.42))
            // Notch hugs the top edge (not mid-safe-area).
            let y: CGFloat = 0
            pill = CGRect(x: (size.width - w) / 2, y: y, width: w, height: h)
        case .none:
            return nil
        }

        return makeGeometry(pill: pill, style: style, size: size, landscapeEdge: nil)
    }

    // MARK: - Landscape

    private static func resolveLandscape(size: CGSize, insets: EdgeInsets) -> Geometry? {
        let lead = max(insets.leading, windowInset(for: .left))
        let trail = max(insets.trailing, windowInset(for: .right))
        let side = max(lead, trail)
        guard side >= 40 else { return nil }

        let edge = hardwareEdge(leading: lead, trailing: trail)
        let gutter = edge == .leading ? lead : trail
        let style: Style = side >= 51 ? .dynamicIsland : .notch

        let pill: CGRect
        switch style {
        case .dynamicIsland:
            let known = knownIslandSize()
            // Portrait (w×h) → landscape (h×w); physical top offset stays ~11pt.
            let shortAxis = known?.h ?? 37.33
            let longAxis = known?.w ?? 126
            let y = (size.height - longAxis) / 2
            let edgePad: CGFloat = 11
            let x: CGFloat = edge == .leading
                ? edgePad
                : size.width - edgePad - shortAxis
            pill = CGRect(x: x, y: y, width: shortAxis, height: longAxis)
        case .notch:
            let shortAxis = min(34, max(26, gutter * 0.42))
            let longAxis = min(size.height * 0.36, max(160, gutter * 2.4))
            let y = (size.height - longAxis) / 2
            let edgePad: CGFloat = 0
            let x: CGFloat = edge == .leading
                ? edgePad
                : size.width - edgePad - shortAxis
            pill = CGRect(x: x, y: y, width: shortAxis, height: longAxis)
        case .none:
            return nil
        }

        return makeGeometry(pill: pill, style: style, size: size, landscapeEdge: edge)
    }

    private static func makeGeometry(
        pill: CGRect, style: Style, size: CGSize, landscapeEdge: HorizontalAlignment?
    ) -> Geometry {
        let screen = CGRect(origin: .zero, size: size)
        let softScreen = screen.insetBy(dx: 1, dy: 1)
        let desiredSpill = min(maxSpillPoints, max(28, min(size.width, size.height) * 0.072))

        // Keep aura centered on the pill. Asymmetric screen-clip / landscape bias
        // shifts aura.mid away from pill.mid → feather mask + Metal look off-notch.
        var spill = desiredSpill
        for _ in 0..<14 {
            let candidate = pill.insetBy(dx: -spill, dy: -spill)
            let over = max(
                max(0, softScreen.minX - candidate.minX),
                max(0, candidate.maxX - softScreen.maxX),
                max(0, softScreen.minY - candidate.minY),
                max(0, candidate.maxY - softScreen.maxY)
            )
            if over <= 0.5 { break }
            spill = max(8, spill - over)
        }
        let aura = pill.insetBy(dx: -spill, dy: -spill)
        return Geometry(style: style, pill: pill, aura: aura, landscapeEdge: landscapeEdge)
    }

    // MARK: - Edge detection

    /// Camera is always on the physical top of the phone.
    ///
    /// UIInterfaceOrientation.landscapeLeft  = home button on LEFT  → camera on RIGHT → .trailing
    /// UIInterfaceOrientation.landscapeRight = home button on RIGHT → camera on LEFT  → .leading
    /// UIDevice.landscapeLeft  = home on RIGHT → camera on LEFT  → .leading
    /// UIDevice.landscapeRight = home on LEFT  → camera on RIGHT → .trailing
    private static func hardwareEdge(leading: CGFloat, trailing: CGFloat) -> HorizontalAlignment {
        // 1) Largest safe-area inset = camera side. Works on every iPhone.
        if abs(leading - trailing) > 4 {
            return leading > trailing ? .leading : .trailing
        }

        // 2) UIInterfaceOrientation (foreground-stable).
        if let o = interfaceOrientation() {
            switch o {
            case .landscapeLeft:  return .trailing  // home LEFT → camera RIGHT
            case .landscapeRight: return .leading    // home RIGHT → camera LEFT
            default: break
            }
        }

        // 3) UIDevice (gyroscope-based).
        switch UIDevice.current.orientation {
        case .landscapeLeft:  return .leading   // home RIGHT → camera LEFT
        case .landscapeRight: return .trailing  // home LEFT → camera RIGHT
        default: break
        }

        return .leading
    }

    private static func interfaceOrientation() -> UIInterfaceOrientation? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive })?.interfaceOrientation
            ?? scenes.first?.interfaceOrientation
    }

    private static func windowInset(for edge: UIRectEdge) -> CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        // Prefer overlay cluster window — Cap underlay insets can disagree with where we draw.
        let overlay = windows.first(where: { $0 is EtubuOverlayWindow })
        let key = windows.first(where: \.isKeyWindow)
        let normal = windows.first(where: { $0.windowLevel == .normal })
        let ranked = [overlay, key, normal].compactMap { $0 }
            + windows
        let window = ranked.first(where: {
            max($0.safeAreaInsets.top, $0.safeAreaInsets.left, $0.safeAreaInsets.right) > 20
        }) ?? ranked.first
        guard let inset = window?.safeAreaInsets else { return 0 }
        switch edge {
        case .top: return inset.top
        case .left: return inset.left
        case .right: return inset.right
        case .bottom: return inset.bottom
        default: return 0
        }
    }
}
