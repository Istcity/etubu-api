import UIKit
import SwiftUI

/// Presents the native OBD dashboard and hosts a floating entry button on the Cap root VC.
final class EtubuDashboardPresenter: NSObject {
    static let shared = EtubuDashboardPresenter()

    private var fab: UIButton?
    private weak var fabHost: UIViewController?
    private var hosting: UIViewController?

    func installFloatingButton(on host: UIViewController) {
        DispatchQueue.main.async {
            guard self.fab == nil else { return }
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
            button.addTarget(self, action: #selector(self.fabTapped), for: .touchUpInside)
            host.view.addSubview(button)
            NSLayoutConstraint.activate([
                button.trailingAnchor.constraint(equalTo: host.view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
                button.bottomAnchor.constraint(equalTo: host.view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            ])
            self.fab = button
            self.fabHost = host
        }
    }

    @objc private func fabTapped() {
        guard let host = fabHost ?? Self.topViewController() else { return }
        present(from: host)
    }

    func present(from host: UIViewController) {
        if hosting != nil { return }
        let root = EtubuDashboardRootView(onClose: { [weak self] in
            self?.hosting?.dismiss(animated: true) {
                self?.hosting = nil
            }
        })
        let hc = UIHostingController(rootView: root)
        hc.modalPresentationStyle = .fullScreen
        hc.view.backgroundColor = .black
        hosting = hc
        host.present(hc, animated: true)
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
