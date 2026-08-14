import SwiftUI

extension Notification.Name {
    static let etubuLegalAccepted = Notification.Name("etubuLegalAccepted")
}

/// İlk açılışta hüküm ve koşullar — metin sonunda “Okudum, anladım” olmadan giriş yok.
enum EtubuLegalAcceptance {
    static let acceptedKey = "etubu.legal.accepted.v1"
    static var isAccepted: Bool { UserDefaults.standard.bool(forKey: acceptedKey) }
    static func accept() {
        UserDefaults.standard.set(true, forKey: acceptedKey)
        EtubuLegalGate.shared.accepted = true
        NotificationCenter.default.post(name: .etubuLegalAccepted, object: nil)
    }
}

/// Single source of truth for legal dismiss (survives hosting / layout thrash better than @State alone).
final class EtubuLegalGate: ObservableObject {
    static let shared = EtubuLegalGate()
    @Published var accepted: Bool

    private init() {
        accepted = EtubuLegalAcceptance.isAccepted
    }

    func accept() {
        UserDefaults.standard.set(true, forKey: EtubuLegalAcceptance.acceptedKey)
        accepted = true
    }
}

struct EtubuLegalAcceptanceView: View {
    var theme: ClusterTheme
    var onAccepted: () -> Void

    @State private var checked = false
    @State private var accepting = false
    /// Refresh body when `EtubuAppLanguage` changes.
    @State private var langTick = 0
    /// Avoid reading `UIWindow.safeAreaInsets` inside GeometryReader (layout re-entrancy).
    @State private var cachedTopInset: CGFloat = 47
    @State private var cachedBottomInset: CGFloat = 20

    var body: some View {
        GeometryReader { geo in
            let topInset = max(geo.safeAreaInsets.top, cachedTopInset, 12)
            let bottomInset = max(geo.safeAreaInsets.bottom, cachedBottomInset, 12)
            let _ = langTick

            ZStack {
                LinearGradient(
                    colors: [
                        Color(hue: theme.hue / 360, saturation: 0.55, brightness: 0.38),
                        Color(hue: theme.hue / 360, saturation: 0.4, brightness: 0.18),
                        theme.canvas,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Başlık — güvenli alanın içinde
                    VStack(spacing: 6) {
                        Text("Etubu")
                            .font(EtubuClusterFonts.ui(14, weight: .bold))
                            .tracking(4)
                            .foregroundStyle(theme.accent)
                        Text(EtubuClusterL10n.t("legalTitle"))
                            .font(EtubuClusterFonts.ui(24, weight: .bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        Text(EtubuClusterL10n.t("legalSubtitle"))
                            .font(EtubuClusterFonts.ui(13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, topInset + 8)
                    .padding(.bottom, 12)

                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 14) {
                            legalBody
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    // Sabit onay — ScrollView altına itilmez
                    VStack(spacing: 10) {
                        Button {
                            guard !accepting else { return }
                            checked.toggle()
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: checked ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(checked ? theme.accent : .white.opacity(0.9))
                                Text(EtubuClusterL10n.t("legalCheckbox"))
                                    .font(EtubuClusterFonts.ui(14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(checked ? theme.accent.opacity(0.16) : Color.white.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(
                                                checked ? theme.accent.opacity(0.7) : Color.white.opacity(0.2),
                                                lineWidth: 1.2
                                            )
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(accepting)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel(EtubuClusterL10n.t("legalCheckboxA11y"))
                        .accessibilityIdentifier("etubu.legal.checkbox")

                        Button {
                            guard !accepting else { return }
                            // Require explicit checkbox — Maestro always taps checkbox first.
                            guard checked else { return }
                            accepting = true
                            EtubuLegalAcceptance.accept()
                            onAccepted()
                        } label: {
                            Text(accepting ? EtubuClusterL10n.t("legalStarting") : EtubuClusterL10n.t("legalAccept"))
                                .font(EtubuClusterFonts.ui(17, weight: .bold))
                                .foregroundStyle(checked && !accepting ? .black : .white.opacity(0.45))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .background(
                                    (checked && !accepting ? theme.accent : Color.white.opacity(0.12)),
                                    in: Capsule()
                                )
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        // Do not use .disabled — Maestro can “tap” a disabled control without
                        // invoking the action (leaves legal stuck on the accept screen).
                        .accessibilityIdentifier("etubu.legal.accept")
                        .accessibilityLabel(EtubuClusterL10n.t("legalAccept"))
                        .accessibilityAddTraits(.isButton)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, max(12, bottomInset))
                    .background(theme.canvas.opacity(0.96))
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .onAppear {
            DispatchQueue.main.async { refreshCachedInsets() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .etubuLanguageDidChange)) { _ in
            langTick &+= 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .etubuClusterGeometryDidChange)) { _ in
            DispatchQueue.main.async { refreshCachedInsets() }
        }
    }

    private var legalBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            section(EtubuClusterL10n.t("legalSec1Title"), EtubuClusterL10n.t("legalSec1Body"))
            section(EtubuClusterL10n.t("legalSec2Title"), EtubuClusterL10n.t("legalSec2Body"))
            section(EtubuClusterL10n.t("legalSec2aTitle"), EtubuClusterL10n.t("legalSec2aBody"))
            section(EtubuClusterL10n.t("legalSec3Title"), EtubuClusterL10n.t("legalSec3Body"))
            section(EtubuClusterL10n.t("legalSec4Title"), EtubuClusterL10n.t("legalSec4Body"))
            section(EtubuClusterL10n.t("legalSec5Title"), EtubuClusterL10n.t("legalSec5Body"))
            section(EtubuClusterL10n.t("legalSec6Title"), EtubuClusterL10n.t("legalSec6Body"))
            section(EtubuClusterL10n.t("legalSec7Title"), EtubuClusterL10n.t("legalSec7Body"))

            Text(EtubuClusterL10n.t("legalUpdated"))
                .font(EtubuClusterFonts.ui(11, weight: .medium))
                .foregroundStyle(theme.mutedText)
                .padding(.top, 4)

            Link(destination: EtubuOsmAttribution.copyrightURL) {
                Text(EtubuOsmAttribution.credit + " · ODbL")
                    .font(EtubuClusterFonts.ui(11, weight: .semibold))
                    .foregroundStyle(theme.accent)
            }
        }
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(EtubuClusterFonts.ui(14, weight: .bold))
                .foregroundStyle(theme.accent)
            Text(body)
                .font(EtubuClusterFonts.ui(13, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func refreshCachedInsets() {
        let top = Self.windowTopInset()
        let bottom = Self.windowBottomInset()
        if top != cachedTopInset { cachedTopInset = top }
        if bottom != cachedBottomInset { cachedBottomInset = bottom }
    }

    private static func windowTopInset() -> CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.flatMap(\.windows).first
        return window?.safeAreaInsets.top ?? 47
    }

    private static func windowBottomInset() -> CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.flatMap(\.windows).first
        return window?.safeAreaInsets.bottom ?? 20
    }
}
