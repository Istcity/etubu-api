import UIKit
import SwiftUI
import WebKit
import Capacitor

/// Full-screen SwiftUI cluster above Capacitor — **same UIWindow** as Cap.
///
/// A second `UIWindow` caused half-blank landscape on Simulator (frame lagged
/// behind rotation). Hosting as a child of Cap’s root VC rotates correctly.
/// Cap WebView stays alive underneath (alpha low, NOT isHidden) for RouteGuard / Audio JS.
final class EtubuClusterPresenter: NSObject {
    static let shared = EtubuClusterPresenter()

    private(set) var hosting: UIHostingController<EtubuClusterRootView>?
    /// Legacy second-window path — torn down if still present from older builds.
    private var overlayWindow: UIWindow?
    private var installAttempts = 0
    private var keepAliveTimer: Timer?
    private var edgeConstraints: [NSLayoutConstraint] = []

    private let canvasColor = UIColor(red: 0.02, green: 0.05, blue: 0.09, alpha: 1)

    func installOverCapacitor() {
        DispatchQueue.main.async {
            self.tearDownLegacyOverlayWindow()

            guard let window = Self.capWindow(),
                  let root = window.rootViewController,
                  let container = root.view else {
                self.scheduleRetry()
                return
            }

            let bounds = container.bounds.width > 40 ? container.bounds : window.bounds
            guard bounds.width > 40, bounds.height > 40 else {
                self.scheduleRetry()
                return
            }

            let hc: UIHostingController<EtubuClusterRootView>
            if let existing = self.hosting {
                hc = existing
            } else {
                let created = UIHostingController(rootView: EtubuClusterRootView())
                created.view.backgroundColor = self.canvasColor
                created.view.isOpaque = true
                created.view.clipsToBounds = true
                self.hosting = created
                hc = created
            }

            // Child of Cap root + view inside root.view (UIKit-legal; sheets work; rotates with scene).
            if hc.parent !== root {
                hc.willMove(toParent: nil)
                hc.view.removeFromSuperview()
                hc.removeFromParent()
                root.addChild(hc)
                container.addSubview(hc.view)
                hc.didMove(toParent: root)
            } else if hc.view.superview !== container {
                hc.view.removeFromSuperview()
                container.addSubview(hc.view)
            }

            self.pinHosting(hc.view, to: container)
            hc.view.isHidden = false
            hc.view.alpha = 1
            hc.view.isUserInteractionEnabled = true
            hc.view.backgroundColor = self.canvasColor
            container.backgroundColor = self.canvasColor
            window.backgroundColor = self.canvasColor
            container.bringSubviewToFront(hc.view)

            self.hideCapacitorChrome()
            self.startWebKeepAlive()
            self.installAttempts = 0
            NotificationCenter.default.post(name: .etubuClusterGeometryDidChange, object: nil)
        }
    }

    func refreshOverlayGeometry() {
        DispatchQueue.main.async {
            guard let window = Self.capWindow(),
                  let root = window.rootViewController,
                  let hv = self.hosting?.view,
                  let container = root.view else {
                self.installOverCapacitor()
                return
            }
            if hv.superview !== container {
                self.installOverCapacitor()
                return
            }
            self.pinHosting(hv, to: container)
            if !self.isModalOrKeyboardActive() {
                container.bringSubviewToFront(hv)
            }
            hv.setNeedsLayout()
            hv.layoutIfNeeded()
            self.hideCapacitorChrome()
            NotificationCenter.default.post(name: .etubuClusterGeometryDidChange, object: nil)
        }
    }

    private func pinHosting(_ view: UIView, to container: UIView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.deactivate(edgeConstraints)
        edgeConstraints = [
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ]
        NSLayoutConstraint.activate(edgeConstraints)
    }

    private func tearDownLegacyOverlayWindow() {
        guard let ow = overlayWindow else { return }
        ow.isHidden = true
        ow.rootViewController = nil
        overlayWindow = nil
    }

    /// Keep Cap webView in the hierarchy and running JS — only make it invisible / non-interactive.
    func hideCapacitorChrome() {
        DispatchQueue.main.async {
            if let cap = Self.findCapVC() {
                cap.view.backgroundColor = self.canvasColor
                // Always keep Cap's root interactive so child cluster hosting receives touches.
                cap.view.isUserInteractionEnabled = true
                if let wv = cap.webView {
                    // CRITICAL: do not set isHidden = true — that stalls WKWebView JS.
                    wv.isHidden = false
                    wv.alpha = 1
                    wv.isOpaque = false
                    wv.backgroundColor = .clear
                    wv.scrollView.backgroundColor = .clear
                    // If Cap.view === WKWebView, disabling interaction kills ALL subviews
                    // (including the SwiftUI cluster) — Simulator mouse clicks go nowhere.
                    if wv === cap.view {
                        wv.isUserInteractionEnabled = true
                    } else {
                        wv.isUserInteractionEnabled = false
                        wv.scrollView.isUserInteractionEnabled = false
                    }
                    if wv.bounds.width < 2 || wv.bounds.height < 2 {
                        let host = cap.view.bounds
                        wv.frame = CGRect(
                            x: 0, y: 0,
                            width: max(320, host.width),
                            height: max(480, host.height)
                        )
                    }
                }
            }
            if let root = Self.capWindow()?.rootViewController,
               let hv = self.hosting?.view,
               hv.superview === root.view {
                hv.isUserInteractionEnabled = true
                hv.isMultipleTouchEnabled = true
                if !self.isModalOrKeyboardActive() {
                    root.view.bringSubviewToFront(hv)
                }
            }
        }
    }

    private func startWebKeepAlive() {
        guard keepAliveTimer == nil else { return }
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Never fight sheets / keyboard — bringing cluster front covers route/settings.
            if self.isModalOrKeyboardActive() { return }
            guard let wv = Self.findCapVC()?.webView else { return }
            wv.evaluateJavaScript("1", completionHandler: nil)
            if let root = Self.capWindow()?.rootViewController,
               let hv = self.hosting?.view,
               hv.superview === root.view {
                root.view.bringSubviewToFront(hv)
                // Re-assert full size if Cap re-layout shrunk us.
                if root.view.bounds.width > 40,
                   abs(hv.bounds.width - root.view.bounds.width) > 2
                    || abs(hv.bounds.height - root.view.bounds.height) > 2 {
                    self.pinHosting(hv, to: root.view)
                }
            }
        }
        if let t = keepAliveTimer {
            RunLoop.main.add(t, forMode: .common)
        }
    }

    /// True while a sheet/alert is up or the software keyboard is visible.
    private func isModalOrKeyboardActive() -> Bool {
        if let root = Self.capWindow()?.rootViewController, root.presentedViewController != nil {
            return true
        }
        if let host = hosting, host.presentedViewController != nil { return true }
        // Walk children — SwiftUI sheets often attach to the hosting controller.
        var stack: [UIViewController] = []
        if let root = Self.capWindow()?.rootViewController { stack.append(root) }
        while let current = stack.popLast() {
            if current.presentedViewController != nil { return true }
            stack.append(contentsOf: current.children)
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for window in scenes.flatMap(\.windows) where !window.isHidden {
            let name = NSStringFromClass(type(of: window))
            if name.contains("Keyboard") || name.contains("UIRemoteKeyboard") { return true }
        }
        return false
    }

    private func scheduleRetry() {
        installAttempts += 1
        guard installAttempts < 60 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.installOverCapacitor()
        }
    }

    private static func capWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        // Prefer Cap’s normal-level window (not a leftover overlay).
        if let cap = windows.first(where: {
            $0.windowLevel == .normal && !$0.isHidden && scanForCap($0.rootViewController) != nil
        }) {
            return cap
        }
        return windows.first(where: { $0.isKeyWindow && $0.windowLevel == .normal })
            ?? windows.first(where: { $0.windowLevel == .normal })
            ?? windows.first
    }

    private static func findCapVC() -> CAPBridgeViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for window in scenes.flatMap(\.windows) {
            if let cap = scanForCap(window.rootViewController) { return cap }
        }
        return nil
    }

    private static func scanForCap(_ root: UIViewController?) -> CAPBridgeViewController? {
        var stack: [UIViewController] = []
        if let root { stack.append(root) }
        while let current = stack.popLast() {
            if let cap = current as? CAPBridgeViewController { return cap }
            stack.append(contentsOf: current.children)
            if let presented = current.presentedViewController {
                stack.append(presented)
            }
        }
        return nil
    }
}

extension Notification.Name {
    static let etubuClusterGeometryDidChange = Notification.Name("etubuClusterGeometryDidChange")
}
