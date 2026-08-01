import SwiftUI
import UIKit
import Darwin

/// Resolves camera cutout / Dynamic Island geometry in **full-screen** coordinates
/// for every iPhone (SE → Pro Max) and all four interface orientations.
///
/// Camera always sits on the **physical top** of the device. In UI coordinates that
/// maps to: portrait → top, portraitUpsideDown → bottom, landscape → leading/trailing.
enum EtubuCameraCutout {
    enum Style { case none, notch, dynamicIsland }

    /// Where the hardware cutout sits in the current interface coordinate space.
    enum Anchor: Equatable {
        case top, bottom, leading, trailing
    }

    struct Geometry: Equatable {
        var style: Style
        var pill: CGRect
        var aura: CGRect
        var landscapeEdge: HorizontalAlignment?
        var anchor: Anchor
    }

    /// Apple hardware Dynamic Island — same on Pro / Pro Max (points).
    private static let islandW: CGFloat = 126
    private static let islandH: CGFloat = 37.33
    /// Padding from physical top / camera-side screen edge to the pill.
    private static let islandEdgePad: CGFloat = 11

    /// Spill for FX — tight rim so the glow reads as the island itself.
    static let maxSpillPoints: CGFloat = 22

    // MARK: - Device catalog

    private struct IslandSpec {
        var width: CGFloat
        var height: CGFloat
    }

    private static func knownIslandSpec() -> IslandSpec? {
        let b = UIScreen.main.nativeBounds
        let w = Int(min(b.width, b.height))
        let h = Int(max(b.width, b.height))
        let di = IslandSpec(width: islandW, height: islandH)
        switch (w, h) {
        case (1179, 2556): return di // 14/15 Pro
        case (1290, 2796): return di // 14/15 Pro Max
        case (1206, 2622): return di // 16 Pro / 17 Pro
        case (1320, 2868): return di // 16/17 Pro Max
        case (1260, 2736): return di // Air class
        case (1284, 2778):
            let id = machineIdentifier()
            if id.contains("iPhone15,3") || id.contains("iPhone16,2")
                || id.contains("iPhone17,2") || id.contains("iPhone18") {
                return di
            }
            return nil
        default:
            let id = machineIdentifier()
            if id.hasPrefix("iPhone15,2") || id.hasPrefix("iPhone15,3")
                || id.hasPrefix("iPhone16,1") || id.hasPrefix("iPhone16,2")
                || id.hasPrefix("iPhone17,1") || id.hasPrefix("iPhone17,2")
                || id.hasPrefix("iPhone18") {
                return di
            }
            return nil
        }
    }

    private static func isKnownNotchDevice() -> Bool {
        if knownIslandSpec() != nil { return false }
        let b = UIScreen.main.nativeBounds
        let w = Int(min(b.width, b.height))
        let h = Int(max(b.width, b.height))
        switch (w, h) {
        case (1125, 2436), // X / XS / 11 Pro
             (828, 1792),  // XR / 11
             (1242, 2688), // XS Max / 11 Pro Max
             (1170, 2532), // 12/13/14
             (1080, 2340), // 12/13 mini
             (1284, 2778): // 12/13/14 Plus / Max
            return true
        default:
            let id = machineIdentifier()
            return id.hasPrefix("iPhone10,") || id.hasPrefix("iPhone11,")
                || id.hasPrefix("iPhone12,") || id.hasPrefix("iPhone13,")
                || id.hasPrefix("iPhone14,")
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

    private static func fallback(size: CGSize, landscape: Bool) -> Geometry {
        let w = islandW
        let h = islandH
        if landscape {
            let pill = CGRect(
                x: islandEdgePad,
                y: (size.height - w) / 2,
                width: h,
                height: w
            )
            return makeGeometry(pill: pill, style: .dynamicIsland, size: size, anchor: .leading)
        }
        let pill = CGRect(x: (size.width - w) / 2, y: islandEdgePad, width: w, height: h)
        return makeGeometry(pill: pill, style: .dynamicIsland, size: size, anchor: .top)
    }

    // MARK: - Portrait (+ upside down)

    private static func resolvePortrait(size: CGSize, insets: EdgeInsets) -> Geometry? {
        let top = max(insets.top, windowInset(for: .top))
        let bottom = max(insets.bottom, windowInset(for: .bottom))
        let orient = interfaceOrientation()

        let cameraAtBottom: Bool = {
            if orient == .portraitUpsideDown { return true }
            return bottom >= 51 && bottom > top + 8
        }()

        let band = cameraAtBottom ? bottom : top
        guard band >= 44 else { return nil }

        let resolvedStyle: Style = {
            if knownIslandSpec() != nil { return .dynamicIsland }
            if isKnownNotchDevice() { return .notch }
            return band >= 51 ? .dynamicIsland : .notch
        }()

        let pill: CGRect
        switch resolvedStyle {
        case .dynamicIsland:
            // Apple hardware Dynamic Island (DynamicIslandUtilities / HIG):
            // 126 × 37.33 pt, origin y = 11 from physical top, centered in screen width.
            // Portrait must match that seat exactly — landscape short-axis pad stays 11.
            let w = islandW
            let h = islandH
            // Center in the cluster canvas (overlay is forced to screen bounds).
            let x = (size.width - w) / 2
            let y: CGFloat = cameraAtBottom
                ? size.height - islandEdgePad - h
                : islandEdgePad
            pill = CGRect(x: x, y: y, width: w, height: h)
        case .notch:
            // Notch is flush with the physical top edge on every notch iPhone.
            let h = portraitNotchHeight(band: band)
            let w = portraitNotchWidth(screenWidth: size.width, band: band)
            let y: CGFloat = cameraAtBottom ? size.height - h : 0
            pill = CGRect(x: (size.width - w) / 2, y: y, width: w, height: h)
        case .none:
            return nil
        }

        return makeGeometry(
            pill: pill,
            style: resolvedStyle,
            size: size,
            anchor: cameraAtBottom ? .bottom : .top
        )
    }

    private static func portraitNotchHeight(band: CGFloat) -> CGFloat {
        // X→14 notch depth ≈ 30–33pt inside a 44–50 status band.
        min(33, max(30, round(band * 0.50)))
    }

    private static func portraitNotchWidth(screenWidth: CGFloat, band: CGFloat) -> CGFloat {
        // Wider notch on Plus/Max; keep ~48–52% and never skinnier than 190.
        let ratio: CGFloat = band >= 48 ? 0.50 : 0.48
        return min(screenWidth * 0.54, max(190, screenWidth * ratio))
    }

    // MARK: - Landscape

    private static func resolveLandscape(size: CGSize, insets: EdgeInsets) -> Geometry? {
        let lead = max(insets.leading, windowInset(for: .left))
        let trail = max(insets.trailing, windowInset(for: .right))
        let side = max(lead, trail)
        guard side >= 40 else { return nil }

        let edge = hardwareEdge(leading: lead, trailing: trail)
        let gutter = edge == .leading ? lead : trail
        let anchor: Anchor = edge == .leading ? .leading : .trailing

        let resolvedStyle: Style = {
            if knownIslandSpec() != nil { return .dynamicIsland }
            if isKnownNotchDevice() { return .notch }
            return side >= 51 ? .dynamicIsland : .notch
        }()

        let pill: CGRect
        switch resolvedStyle {
        case .dynamicIsland:
            let shortAxis = islandH
            let longAxis = islandW
            let y = (size.height - longAxis) / 2
            let x: CGFloat = edge == .leading
                ? islandEdgePad
                : size.width - islandEdgePad - shortAxis
            pill = CGRect(x: x, y: y, width: shortAxis, height: longAxis)
        case .notch:
            let shortAxis = min(33, max(28, gutter * 0.48))
            let longAxis = min(size.height * 0.42, max(170, size.width * 0.28))
            let y = (size.height - longAxis) / 2
            let x = landscapeNotchX(edge: edge, gutter: gutter, shortAxis: shortAxis, sizeWidth: size.width)
            pill = CGRect(x: x, y: y, width: shortAxis, height: longAxis)
        case .none:
            return nil
        }

        return makeGeometry(pill: pill, style: resolvedStyle, size: size, anchor: anchor)
    }

    private static func landscapeNotchX(
        edge: HorizontalAlignment,
        gutter: CGFloat,
        shortAxis: CGFloat,
        sizeWidth: CGFloat
    ) -> CGFloat {
        let inset = max(0, (gutter - shortAxis) * 0.5)
        if edge == .leading { return inset }
        return sizeWidth - gutter + inset
    }

    private static func makeGeometry(
        pill: CGRect,
        style: Style,
        size: CGSize,
        anchor: Anchor
    ) -> Geometry {
        let landscapeEdge: HorizontalAlignment? = {
            switch anchor {
            case .leading: return .leading
            case .trailing: return .trailing
            default: return nil
            }
        }()

        let desiredSpill = min(maxSpillPoints, max(16, min(size.width, size.height) * 0.05))
        let aura = auraRect(pill: pill, desiredSpill: desiredSpill, size: size, anchor: anchor, style: style)
        return Geometry(
            style: style,
            pill: pill,
            aura: aura,
            landscapeEdge: landscapeEdge,
            anchor: anchor
        )
    }

    /// Landscape keeps the symmetric clamp that seats well on 17 Pro Max.
    /// Portrait DI also uses a **symmetric** aura centered on the Apple pill so the
    /// FX doesn’t optically drift under the cutout.
    private static func auraRect(
        pill: CGRect,
        desiredSpill: CGFloat,
        size: CGSize,
        anchor: Anchor,
        style: Style
    ) -> CGRect {
        switch anchor {
        case .top, .bottom:
            if style == .dynamicIsland {
                // Symmetric around the hardware pill (same idea as landscape).
                let spill = min(desiredSpill, 14)
                return pill.insetBy(dx: -spill, dy: -spill)
            }
            return portraitAura(
                pill: pill,
                desiredSpill: desiredSpill,
                size: size,
                atBottom: anchor == .bottom,
                style: style
            )
        case .leading, .trailing:
            let spill = symmetricClampedSpill(pill: pill, desired: desiredSpill, size: size)
            return pill.insetBy(dx: -spill, dy: -spill)
        }
    }

    private static func portraitAura(
        pill: CGRect,
        desiredSpill: CGFloat,
        size: CGSize,
        atBottom: Bool,
        style: Style
    ) -> CGRect {
        let side = desiredSpill
        let cameraRoom = atBottom ? max(0, size.height - pill.maxY) : max(0, pill.minY)
        // Hang past the camera edge (clipped by the display) so the rim reads even.
        let alongCamera = max(desiredSpill, style == .notch ? max(6, pill.height * 0.2) : cameraRoom)
        // Short bloom toward content — stops the “rising from under the cutout” look.
        let towardContent: CGFloat = style == .notch ? 8 : 9
        let top = atBottom ? towardContent : alongCamera
        let bottom = atBottom ? alongCamera : towardContent
        // Keep aura centered on the pill (midX/midY drive .position).
        return CGRect(
            x: pill.minX - side,
            y: pill.minY - top,
            width: pill.width + side * 2,
            height: pill.height + top + bottom
        )
    }

    private static func symmetricClampedSpill(
        pill: CGRect,
        desired: CGFloat,
        size: CGSize
    ) -> CGFloat {
        let soft = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
        var spill = desired
        for _ in 0..<14 {
            let c = pill.insetBy(dx: -spill, dy: -spill)
            let over = max(
                max(0, soft.minX - c.minX),
                max(0, c.maxX - soft.maxX),
                max(0, soft.minY - c.minY),
                max(0, c.maxY - soft.maxY)
            )
            if over <= 0.5 { break }
            spill = max(6, spill - over)
        }
        return spill
    }

    // MARK: - Edge detection

    private static func hardwareEdge(leading: CGFloat, trailing: CGFloat) -> HorizontalAlignment {
        if abs(leading - trailing) > 4 {
            return leading > trailing ? .leading : .trailing
        }
        if let o = interfaceOrientation() {
            switch o {
            case .landscapeLeft:  return .trailing
            case .landscapeRight: return .leading
            default: break
            }
        }
        switch UIDevice.current.orientation {
        case .landscapeLeft:  return .leading
        case .landscapeRight: return .trailing
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
        let overlay = windows.first(where: { $0 is EtubuOverlayWindow })
        let key = windows.first(where: \.isKeyWindow)
        let normal = windows.first(where: { $0.windowLevel == .normal })
        let ranked = [overlay, key, normal].compactMap { $0 } + windows
        let window = ranked.first(where: {
            max($0.safeAreaInsets.top, $0.safeAreaInsets.left,
                $0.safeAreaInsets.right, $0.safeAreaInsets.bottom) > 20
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
