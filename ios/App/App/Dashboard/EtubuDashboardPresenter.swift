import UIKit
import SwiftUI

/// Presents the native OBD dashboard and hosts a floating entry button on the Cap root VC.
/// `NSObject` subclass (not an enum) so `@objc` static selectors work for the UIButton target.
final class EtubuDashboardPresenter: NSObject {
    private static var fab: UIButton?
    private static var hosting: UIViewController?

    static func installFloatingButton(on host: UIViewController) {
        DispatchQueue.main.async {
            guard fab == nil else { return }
            let button = UIButton(type: .system)
            button.setTitle("Dashboard", for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
            button.setTitleColor(.black, for: .normal)
            button.backgroundColor = UIColor(red: 0.2, green: 0.85, blue: 0.95, alpha: 0.95)
            button.layer.cornerRadius = 18
            button.layer.shadowColor = UIColor.cyan.cgColor
            button.layer.shadowOpacity = 0.35
            button.layer.shadowRadius = 8
            button.layer.shadowOffset = CGSize(width: 0, height: 3)
            button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.addTarget(self, action: #selector(fabTapped), for: .touchUpInside)
            host.view.addSubview(button)
            NSLayoutConstraint.activate([
                button.trailingAnchor.constraint(equalTo: host.view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
                button.bottomAnchor.constraint(equalTo: host.view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            ])
            fab = button
            fabHost = host
        }
    }

    private static weak var fabHost: UIViewController?

    @objc private static func fabTapped() {
        guard let host = fabHost ?? topViewController() else { return }
        present(from: host)
    }

    static func present(from host: UIViewController) {
        if hosting != nil { return }
        let root = EtubuDashboardRootView()
        let hc = UIHostingController(rootView: root)
        hc.modalPresentationStyle = .fullScreen
        hc.view.backgroundColor = .black
        hosting = hc
        host.present(hc, animated: true) {
            // Keep reference until dismissed via environment dismiss → need wrapper
        }
        // Observe dismiss
        hc.presentationController?.delegate = DismissObserver.shared
        DismissObserver.shared.onDismiss = {
            hosting = nil
        }
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow }
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

private final class DismissObserver: NSObject, UIAdaptivePresentationControllerDelegate {
    static let shared = DismissObserver()
    var onDismiss: (() -> Void)?

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        onDismiss?()
        onDismiss = nil
    }
}
