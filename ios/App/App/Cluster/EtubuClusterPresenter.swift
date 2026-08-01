import UIKit
import SwiftUI
import WebKit
import Capacitor

/// SwiftUI cluster on a dedicated overlay UIWindow above Capacitor.
///
/// Size comes from screen bounds + interface orientation (never Cap’s lagging
/// portrait frame) — that was the landscape half-blank root cause.
final class EtubuClusterPresenter: NSObject {
    static let shared = EtubuClusterPresenter()

    private(set) var hosting: UIHostingController<EtubuClusterRootView>?
    private var overlayWindow: EtubuOverlayWindow?
    private var installAttempts = 0
    private var keepAliveTimer: Timer?
    private var geometryObservers: [NSObjectProtocol] = []

    private let canvasColor = EtubuRuntimeProfile.canvasUIColor

    func installOverCapacitor() {
        DispatchQueue.main.async {
            EtubuRuntimeProfile.hideLingeringSplashOverlays()

            guard let scene = Self.activeWindowScene() else {
                self.scheduleRetry()
                return
            }

            let bounds = Self.sceneInterfaceBounds(scene)
            guard bounds.width > 40, bounds.height > 40 else {
                self.scheduleRetry()
                return
            }

            self.detachHostingFromCapIfNeeded()
            let hc = self.ensureHostingController()
            let overlay = self.ensureOverlayWindow(scene: scene, bounds: bounds)

            if overlay.rootViewController !== hc {
                if hc.parent != nil {
                    hc.willMove(toParent: nil)
                    hc.view.removeFromSuperview()
                    hc.removeFromParent()
                }
                overlay.rootViewController = hc
            }

            self.applyOverlayFrame(bounds, overlay: overlay, hosting: hc)
            overlay.makeKeyAndVisible()

            self.hideCapacitorChrome()
            self.startWebKeepAlive()
            self.observeGeometryChanges()
            self.observeLegalAcceptance()
            self.installAttempts = 0
            NotificationCenter.default.post(name: .etubuClusterGeometryDidChange, object: nil)

            for delay in [0.05, 0.2, 0.5, 1.0] as [Double] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    EtubuRuntimeProfile.hideLingeringSplashOverlays()
                    guard !self.isModalOrKeyboardActive() else { return }
                    self.syncOverlayGeometry()
                    self.hideCapacitorChrome()
                    self.makeOverlayKeyIfSafe()
                }
            }
        }
    }

    func refreshOverlayGeometry() {
        DispatchQueue.main.async {
            guard !self.isModalOrKeyboardActive() else { return }
            self.syncOverlayGeometry()
            self.hideCapacitorChrome()
            self.makeOverlayKeyIfSafe()
            NotificationCenter.default.post(name: .etubuClusterGeometryDidChange, object: nil)
        }
    }

    /// Cap rotation — prefer transition `size`, fall back to oriented screen bounds.
    func syncOverlayGeometry(
        to size: CGSize? = nil,
        animatedWith coordinator: UIViewControllerTransitionCoordinator?
    ) {
        let apply = { [weak self] in
            guard let self else { return }
            // Still resize during sheets on rotate, but never steal key from the sheet window.
            if let size, size.width > 40, size.height > 40 {
                self.applyExplicitSize(size)
            } else {
                self.syncOverlayGeometry()
            }
            self.makeOverlayKeyIfSafe()
        }
        if let coordinator {
            coordinator.animate(alongsideTransition: { _ in apply() }, completion: { _ in
                apply()
                NotificationCenter.default.post(name: .etubuClusterGeometryDidChange, object: nil)
            })
        } else {
            apply()
            for delay in [0.05, 0.18, 0.4] as [Double] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: apply)
            }
        }
    }

    /// CapBridge calls this; cluster stays on the overlay window.
    @discardableResult
    func attachHostingToCap(preferredSize: CGSize? = nil) -> Bool {
        if let preferredSize, preferredSize.width > 40, preferredSize.height > 40 {
            applyExplicitSize(preferredSize)
        } else {
            syncOverlayGeometry()
        }
        return overlayWindow != nil && hosting != nil
    }

    private func applyExplicitSize(_ size: CGSize) {
        guard let scene = Self.activeWindowScene() else {
            installOverCapacitor()
            return
        }
        // Prefer oriented screen size; transition size only if aspect already matches.
        let screenBounds = Self.sceneInterfaceBounds(scene)
        var final = screenBounds.size
        let orient = scene.interfaceOrientation
        let wantLand = orient == .landscapeLeft || orient == .landscapeRight
        let sizeLand = size.width > size.height + 1
        if wantLand == sizeLand || orient == .unknown {
            final = size
        }
        if wantLand {
            final = CGSize(width: max(final.width, final.height), height: min(final.width, final.height))
        } else if orient == .portrait || orient == .portraitUpsideDown {
            final = CGSize(width: min(final.width, final.height), height: max(final.width, final.height))
        }
        guard final.width > 40, final.height > 40 else { return }

        detachHostingFromCapIfNeeded()
        let overlay = ensureOverlayWindow(scene: scene, bounds: CGRect(origin: .zero, size: final))
        let hc = ensureHostingController()
        if overlay.rootViewController !== hc {
            overlay.rootViewController = hc
        }
        applyOverlayFrame(CGRect(origin: .zero, size: final), overlay: overlay, hosting: hc)
        makeOverlayKeyIfSafe()
    }

    private func detachHostingFromCapIfNeeded() {
        guard let cap = Self.findCapVC() else { return }
        if let hc = hosting, hc.parent === cap {
            hc.willMove(toParent: nil)
            hc.view.removeFromSuperview()
            hc.removeFromParent()
        }
        // Strip leftover hosting children from earlier embed attempts.
        for child in cap.children {
            guard child is UIHostingController<EtubuClusterRootView> else { continue }
            child.willMove(toParent: nil)
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
    }

    // MARK: - Window / hosting

    private func ensureHostingController() -> UIHostingController<EtubuClusterRootView> {
        if let existing = hosting { return existing }
        let created = EtubuClusterHostingController(rootView: EtubuClusterRootView())
        created.view.backgroundColor = canvasColor
        created.view.isOpaque = true
        created.view.clipsToBounds = true
        created.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if #available(iOS 16.4, *) {
            created.safeAreaRegions = []
        }
        hosting = created
        return created
    }

    private func ensureOverlayWindow(scene: UIWindowScene, bounds: CGRect) -> EtubuOverlayWindow {
        if let existing = overlayWindow {
            if existing.windowScene !== scene {
                existing.windowScene = scene
            }
            existing.isHidden = false
            existing.isUserInteractionEnabled = true
            return existing
        }
        let window = EtubuOverlayWindow(windowScene: scene)
        window.frame = bounds
        window.windowLevel = .normal + 1
        window.backgroundColor = canvasColor
        window.isOpaque = true
        window.accessibilityViewIsModal = true
        overlayWindow = window
        return window
    }

    private func applyOverlayFrame(
        _ bounds: CGRect,
        overlay: EtubuOverlayWindow,
        hosting: UIHostingController<EtubuClusterRootView>
    ) {
        let next = CGRect(origin: .zero, size: bounds.size)
        guard next.width > 40, next.height > 40 else { return }

        overlay.isHidden = false
        overlay.alpha = 1
        overlay.backgroundColor = canvasColor
        hosting.view.isHidden = false
        hosting.view.alpha = 1
        hosting.view.backgroundColor = canvasColor
        hosting.view.isOpaque = true
        hosting.view.isUserInteractionEnabled = true

        overlay.frame = next
        if overlay.rootViewController !== hosting {
            overlay.rootViewController = hosting
        }
        hosting.view.frame = overlay.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hosting.view.setNeedsLayout()
    }

    private func syncOverlayGeometry() {
        guard let scene = Self.activeWindowScene() else {
            installOverCapacitor()
            return
        }
        detachHostingFromCapIfNeeded()
        let bounds = Self.sceneInterfaceBounds(scene)
        guard bounds.width > 40, bounds.height > 40 else { return }
        let overlay = ensureOverlayWindow(scene: scene, bounds: bounds)
        let hc = ensureHostingController()
        if overlay.rootViewController !== hc {
            overlay.rootViewController = hc
        }
        applyOverlayFrame(bounds, overlay: overlay, hosting: hc)
        makeOverlayKeyIfSafe()
    }

    private func makeOverlayKeyIfSafe() {
        // Keep cluster key except when a real presented VC is up.
        if let host = hosting, host.presentedViewController != nil { return }
        if let root = overlayWindow?.rootViewController, root.presentedViewController != nil { return }
        overlayWindow?.makeKeyAndVisible()
    }

    /// Screen points forced to match interface orientation — ignores Cap lag.
    private static func sceneInterfaceBounds(_ scene: UIWindowScene) -> CGRect {
        let raw = scene.screen.bounds.size
        let longSide = max(raw.width, raw.height)
        let shortSide = min(raw.width, raw.height)
        guard longSide > 40, shortSide > 40 else {
            return scene.coordinateSpace.bounds
        }

        let orientation = scene.interfaceOrientation
        let landscape: Bool
        switch orientation {
        case .landscapeLeft, .landscapeRight:
            landscape = true
        case .portrait, .portraitUpsideDown:
            landscape = false
        default:
            // Fall back to device orientation when interface is unknown mid-rotate.
            switch UIDevice.current.orientation {
            case .landscapeLeft, .landscapeRight:
                landscape = true
            default:
                let cs = scene.coordinateSpace.bounds.size
                landscape = cs.width > cs.height + 1
            }
        }

        let size = landscape
            ? CGSize(width: longSide, height: shortSide)
            : CGSize(width: shortSide, height: longSide)
        return CGRect(origin: .zero, size: size)
    }

    private var legalObserver: NSObjectProtocol?

    private func observeLegalAcceptance() {
        guard legalObserver == nil else { return }
        legalObserver = NotificationCenter.default.addObserver(
            forName: .etubuLegalAccepted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            // Tear down hosting VC entirely — assigning rootView alone left legal stuck.
            if let old = self.hosting {
                if let overlay = self.overlayWindow, overlay.rootViewController === old {
                    overlay.rootViewController = nil
                }
                old.willMove(toParent: nil)
                old.view.removeFromSuperview()
                old.removeFromParent()
            }
            self.hosting = nil
            EtubuLegalGate.shared.accepted = true
            let hc = self.ensureHostingController()
            if let scene = Self.activeWindowScene() {
                let bounds = Self.sceneInterfaceBounds(scene)
                let overlay = self.ensureOverlayWindow(scene: scene, bounds: bounds)
                overlay.rootViewController = hc
                self.applyOverlayFrame(bounds, overlay: overlay, hosting: hc)
                overlay.makeKeyAndVisible()
            }
            self.hideCapacitorChrome()
        }
    }

    private func observeGeometryChanges() {
        guard geometryObservers.isEmpty else { return }

        let names: [Notification.Name] = [
            UIDevice.orientationDidChangeNotification,
            UIScene.didActivateNotification,
            UIScene.willEnterForegroundNotification,
            UIApplication.didBecomeActiveNotification,
        ]
        for name in names {
            let token = NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.syncOverlayGeometry(animatedWith: nil)
            }
            geometryObservers.append(token)
        }
    }

    // MARK: - Cap chrome (underlay only)

    func hideCapacitorChrome() {
        DispatchQueue.main.async {
            EtubuRuntimeProfile.hideLingeringSplashOverlays()

            if let cap = Self.findCapVC() {
                cap.view.backgroundColor = self.canvasColor
                cap.view.isUserInteractionEnabled = false
                cap.view.accessibilityElementsHidden = true
                // Critical: disabled Cap *view* still lets the Cap *window* swallow
                // touches if it sits above/key — then legal/cluster taps never fire.
                if let capWin = cap.view.window {
                    capWin.isUserInteractionEnabled = false
                    if capWin.windowLevel >= .normal + 1 {
                        capWin.windowLevel = .normal
                    }
                }
                if let wv = cap.webView {
                    wv.isHidden = false
                    wv.alpha = 0.02
                    wv.isOpaque = false
                    wv.backgroundColor = .clear
                    wv.scrollView.backgroundColor = .clear
                    wv.scrollView.isOpaque = false
                    wv.isUserInteractionEnabled = false
                    wv.scrollView.isUserInteractionEnabled = false
                    wv.accessibilityElementsHidden = true
                    if #available(iOS 15.0, *) {
                        wv.underPageBackgroundColor = .clear
                    }
                    Self.installGeolocationGate(on: wv)
                    wv.evaluateJavaScript(Self.geoGateJavaScript + Self.hidePageJavaScript, completionHandler: nil)
                }
            }

            if let overlay = self.overlayWindow {
                overlay.isUserInteractionEnabled = true
                overlay.windowLevel = .normal + 1
                for window in overlay.windowScene?.windows ?? [] where window !== overlay {
                    if window.windowLevel == .normal {
                        window.backgroundColor = self.canvasColor
                        window.isUserInteractionEnabled = false
                    }
                }
                overlay.accessibilityViewIsModal = true
                self.makeOverlayKeyIfSafe()
            }
        }
    }

    private func startWebKeepAlive() {
        guard keepAliveTimer == nil else { return }
        var tick = 0
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            tick &+= 1
            let parked = EtubuVehicleTelemetry.shared.kmh < 3 && !EtubuDemoDrive.isActive
            // Cap JS ping her tick; geometry/chrome daha seyrek (sürüşte ~6s, parkta ~12s).
            let doGeom = parked ? (tick % 4 == 0) : (tick % 2 == 0)
            if self.isModalOrKeyboardActive() {
                Self.findCapVC()?.webView?.evaluateJavaScript("1", completionHandler: nil)
                return
            }
            if doGeom {
                self.syncOverlayGeometry()
                self.hideCapacitorChrome()
            }
            Self.findCapVC()?.webView?.evaluateJavaScript("1", completionHandler: nil)
        }
        if let t = keepAliveTimer {
            RunLoop.main.add(t, forMode: .common)
        }
    }

    private func isModalOrKeyboardActive() -> Bool {
        if let host = hosting, host.presentedViewController != nil { return true }
        if let root = overlayWindow?.rootViewController, root.presentedViewController != nil {
            return true
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
        guard installAttempts < 80 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            self.installOverCapacitor()
        }
    }

    // MARK: - Scene helpers

    private static func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first(where: { !$0.windows.isEmpty })
            ?? scenes.first
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

    private static var didInstallGeoGate = false
    private static let geoGateJavaScript = """
    (function(){
      try {
        window.__ETUBU_NATIVE_CLUSTER__ = true;
        if (typeof window.__ETUBU_GPS_ARMED__ === 'undefined') {
          window.__ETUBU_GPS_ARMED__ = false;
        }
        var geo = navigator.geolocation;
        if (!geo || geo.__etubuGated) return;
        geo.__etubuGated = true;
        var watch = geo.watchPosition.bind(geo);
        var get = geo.getCurrentPosition.bind(geo);
        geo.watchPosition = function(success, error, opts) {
          if (window.__ETUBU_GPS_ARMED__ !== true) {
            if (typeof error === 'function') {
              try { error({ code: 1, message: 'etubu-gated' }); } catch (e) {}
            }
            return -1;
          }
          return watch(success, error, opts);
        };
        geo.getCurrentPosition = function(success, error, opts) {
          if (window.__ETUBU_GPS_ARMED__ !== true) {
            if (typeof error === 'function') {
              try { error({ code: 1, message: 'etubu-gated' }); } catch (e) {}
            }
            return;
          }
          return get(success, error, opts);
        };
      } catch (e) {}
    })();
    """
    private static let hidePageJavaScript = """
    (function(){
      try {
        document.documentElement.style.opacity='0';
        document.documentElement.style.background='transparent';
        if (document.body) {
          document.body.style.opacity='0';
          document.body.style.background='transparent';
        }
      } catch (e) {}
    })();
    """

    private static func installGeolocationGate(on webView: WKWebView) {
        guard !didInstallGeoGate else { return }
        didInstallGeoGate = true
        let script = WKUserScript(
            source: geoGateJavaScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        webView.configuration.userContentController.addUserScript(script)
    }

    func armCapGeolocation() {
        DispatchQueue.main.async {
            Self.findCapVC()?.webView?.evaluateJavaScript(
                "window.__ETUBU_GPS_ARMED__=true;",
                completionHandler: nil
            )
        }
    }
}

/// Hosting VC that keeps SwiftUI sized to the overlay and forwards rotation.
final class EtubuClusterHostingController: UIHostingController<EtubuClusterRootView> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }
    override var shouldAutorotate: Bool { true }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let parentBounds = view.superview?.bounds,
           parentBounds.width > 40, parentBounds.height > 40,
           abs(view.frame.width - parentBounds.width) > 0.5
            || abs(view.frame.height - parentBounds.height) > 0.5 {
            view.frame = parentBounds
        }
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        EtubuClusterPresenter.shared.syncOverlayGeometry(to: size, animatedWith: coordinator)
    }
}

/// Overlay window that always re-fills the scene during layout (rotation-safe).
final class EtubuOverlayWindow: UIWindow {
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let scene = windowScene else { return }
        let next = EtubuClusterPresenter.sceneBoundsForOverlay(scene)
        guard next.width > 40, next.height > 40 else { return }
        if abs(frame.width - next.width) > 0.5 || abs(frame.height - next.height) > 0.5 {
            frame = CGRect(origin: .zero, size: next.size)
            rootViewController?.view.frame = bounds
        }
    }
}

extension EtubuClusterPresenter {
    /// Shared by overlay window layout — same orientation-safe sizing as install path.
    fileprivate static func sceneBoundsForOverlay(_ scene: UIWindowScene) -> CGRect {
        sceneInterfaceBounds(scene)
    }
}

extension Notification.Name {
    static let etubuClusterGeometryDidChange = Notification.Name("etubuClusterGeometryDidChange")
}
