import SwiftUI
import UIKit

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

    /// Spill for FX — larger soft field, biased away from screen hard edges.
    static let maxSpillPoints: CGFloat = 40

    // MARK: - Device model → Dynamic Island pill size (points)

    /// Returns (width, height) of the Dynamic Island pill for known device screen sizes.
    /// Falls back to safe-area heuristics if unrecognized.
    private static func knownIslandSize() -> (w: CGFloat, h: CGFloat)? {
        let b = UIScreen.main.nativeBounds
        let w = min(b.width, b.height)
        let h = max(b.width, b.height)
        // iPhone 14 Pro / 15 Pro / 16 Pro (1179×2556)
        if w == 1179 && h == 2556 { return (126, 37) }
        // iPhone 14 Pro Max / 15 Pro Max / 16 Pro Max (1290×2796)
        if w == 1290 && h == 2796 { return (126, 37) }
        // iPhone 15 / 16 (1179×2556)
        if w == 1170 && h == 2532 { return (126, 37) }
        // iPhone 16e (1206×2622)
        if w == 1206 && h == 2622 { return (126, 37) }
        // iPhone 17 Pro series / future (≥1320 wide)
        if w >= 1290 { return (126, 37) }
        if w >= 1170 { return (126, 37) }
        return nil
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
            let w = known?.w ?? min(size.width * 0.33, max(120, top * 2))
            let h = known?.h ?? min(37, max(32, top * 0.58))
            let y = max(11, (top - h) / 2)
            pill = CGRect(x: (size.width - w) / 2, y: y, width: w, height: h)
        case .notch:
            let h = min(34, max(28, top * 0.55))
            let w = min(size.width * 0.52, max(180, size.width * 0.45))
            let y = max(0, (top - h) / 2)
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
            let shortAxis = known?.h ?? min(38, max(32, gutter * 0.52))
            let longAxis = known?.w ?? min(size.height * 0.22, max(118, shortAxis * 3.4))
            let y = (size.height - longAxis) / 2
            // Center the pill horizontally within the gutter
            let x: CGFloat = edge == .leading
                ? max(4, (gutter - shortAxis) / 2)
                : size.width - max(4, (gutter - shortAxis) / 2) - shortAxis
            pill = CGRect(x: x, y: y, width: shortAxis, height: longAxis)
        case .notch:
            let shortAxis = min(34, max(26, gutter * 0.42))
            let longAxis = min(size.height * 0.36, max(160, gutter * 2.4))
            let y = (size.height - longAxis) / 2
            let x: CGFloat = edge == .leading
                ? max(2, (gutter - shortAxis) / 2)
                : size.width - max(2, (gutter - shortAxis) / 2) - shortAxis
            pill = CGRect(x: x, y: y, width: shortAxis, height: longAxis)
        case .none:
            return nil
        }

        return makeGeometry(pill: pill, style: style, size: size, landscapeEdge: edge)
    }

    private static func makeGeometry(
        pill: CGRect, style: Style, size: CGSize, landscapeEdge: HorizontalAlignment?
    ) -> Geometry {
        // Spill scales with screen so FX fits SE … Pro Max without spilling past bezel
        let spill = min(maxSpillPoints, max(22, min(size.width, size.height) * 0.055))
        let screen = CGRect(origin: .zero, size: size)
        let softScreen = screen.insetBy(dx: 2, dy: 2)
        var aura = pill.insetBy(dx: -spill, dy: -spill).intersection(softScreen)
        if aura.isNull || aura.width < 8 || aura.height < 8 {
            aura = pill.insetBy(dx: -min(spill, 24), dy: -min(spill, 24)).intersection(softScreen)
            if aura.isNull { aura = pill }
        }
        if let edge = landscapeEdge {
            let bias: CGFloat = min(18, spill * 0.45)
            if edge == .leading {
                let maxW = softScreen.maxX - aura.minX
                aura.size.width = min(maxW, aura.width + bias)
            } else {
                let newMinX = max(softScreen.minX, aura.minX - bias)
                aura = CGRect(x: newMinX, y: aura.minY, width: aura.maxX - newMinX, height: aura.height)
            }
        }
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
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.flatMap(\.windows).first
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
