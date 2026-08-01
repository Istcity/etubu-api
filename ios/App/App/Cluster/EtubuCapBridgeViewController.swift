import UIKit
import WebKit
import Capacitor

/// Cap start page is a blank stub (`index.html`). Full www (`index-app.html`) loads
/// only after legal/onboarding — prevents RouteGuard geolocation prompts on launch.
final class EtubuCapBridgeViewController: CAPBridgeViewController {
    private static var webArmed = false
    private var lastSyncedSize: CGSize = .zero
    private var armRetryWork: DispatchWorkItem?

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .all
    }

    override var shouldAutorotate: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleArmCapWeb),
            name: .etubuArmCapWeb,
            object: nil
        )
        webView?.evaluateJavaScript(
            "window.__ETUBU_NATIVE_CLUSTER__=true;window.__ETUBU_GPS_ARMED__=false;",
            completionHandler: nil
        )
        // Arm may have fired before this VC registered — apply if already requested.
        if Self.webArmed {
            applyArmToWeb(retriesLeft: 12)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if Self.webArmed {
            applyArmToWeb(retriesLeft: 8)
        }
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        lastSyncedSize = size
        EtubuClusterPresenter.shared.syncOverlayGeometry(to: size, animatedWith: coordinator)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Size-only — avoids layout feedback loops that caused black screen.
        let size = view.bounds.size
        guard size.width > 40, size.height > 40 else { return }
        if abs(size.width - lastSyncedSize.width) > 1
            || abs(size.height - lastSyncedSize.height) > 1 {
            lastSyncedSize = size
            EtubuClusterPresenter.shared.syncOverlayGeometry(to: size, animatedWith: nil)
        }
    }

    deinit {
        armRetryWork?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    static var isWebArmed: Bool { webArmed }

    static func armWebContent() {
        DispatchQueue.main.async {
            webArmed = true
            NotificationCenter.default.post(name: .etubuArmCapWeb, object: nil)
            // Direct apply — notification alone can miss if webView was nil.
            findCapBridge()?.applyArmToWeb(retriesLeft: 16)
        }
    }

    @objc private func handleArmCapWeb() {
        applyArmToWeb(retriesLeft: 16)
    }

    private func applyArmToWeb(retriesLeft: Int) {
        guard Self.webArmed else { return }
        guard let wv = webView else {
            scheduleArmRetry(retriesLeft: retriesLeft)
            return
        }
        wv.evaluateJavaScript(
            """
            (function(){
              window.__ETUBU_NATIVE_CLUSTER__=true;
              window.__ETUBU_GPS_ARMED__=true;
              // Already on full app — leave alone.
              if (window.RouteGuard && window.RouteGuard.buildRoute) return 'ready';
              if (document.getElementById('routeGuard')) return 'loading';
              if (typeof window.__ETUBU_LOAD_APP__ === 'function') {
                window.__ETUBU_LOAD_APP__();
                return 'load';
              }
              try { location.replace('index-app.html'); } catch (e) {}
              return 'replace';
            })();
            """
        ) { [weak self] result, _ in
            let s = (result as? String) ?? ""
            if s == "ready" { return }
            // Stub → index-app navigation or scripts still loading — retry briefly.
            if retriesLeft > 0, s == "load" || s == "replace" || s == "loading" || s.isEmpty {
                self?.scheduleArmRetry(retriesLeft: retriesLeft - 1, delay: 0.4)
            }
        }
    }

    private func scheduleArmRetry(retriesLeft: Int, delay: TimeInterval = 0.25) {
        guard retriesLeft > 0 else { return }
        armRetryWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.applyArmToWeb(retriesLeft: retriesLeft)
        }
        armRetryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private static func findCapBridge() -> EtubuCapBridgeViewController? {
        for scene in UIApplication.shared.connectedScenes {
            guard let winScene = scene as? UIWindowScene else { continue }
            for window in winScene.windows {
                if let found = scan(window.rootViewController) { return found }
            }
        }
        return nil
    }

    private static func scan(_ root: UIViewController?) -> EtubuCapBridgeViewController? {
        var stack: [UIViewController] = []
        if let root { stack.append(root) }
        while let cur = stack.popLast() {
            if let cap = cur as? EtubuCapBridgeViewController { return cap }
            stack.append(contentsOf: cur.children)
            if let presented = cur.presentedViewController { stack.append(presented) }
        }
        return nil
    }
}

extension Notification.Name {
    static let etubuArmCapWeb = Notification.Name("etubuArmCapWeb")
}
