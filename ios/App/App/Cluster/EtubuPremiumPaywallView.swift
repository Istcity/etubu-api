import SwiftUI
import AuthenticationServices

/// Küçük Etubu logo — metin kapsülü yok; chrome ikonlarının üstüne binmez.
struct EtubuPremiumBadge: View {
    var compact: Bool = false

    private var size: CGFloat { compact ? 14 : 20 }

    var body: some View {
        Image("EtubuLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel(EtubuClusterL10n.t("premiumBadge"))
    }
}

/// Settings list section: Apple account + purchase / restore.
struct EtubuPremiumSettingsSection: View {
    @ObservedObject private var premium = EtubuPremiumManager.shared
    @Binding var showPaywall: Bool
    var accent: Color
    /// Ayarlar sheet’ini kapatıp kökte kod sheet’i açmak için.
    var onRequestRedeemCode: (() -> Void)? = nil

    var body: some View {
        Section {
            if premium.isPremium {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(EtubuClusterL10n.t("premiumActive"))
                            .font(.body.weight(.semibold))
                        if premium.isSignedIn {
                            Text(premium.appleDisplayName ?? EtubuClusterL10n.t("premiumSignedIn"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image("EtubuLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                }
                if premium.isSignedIn {
                    Button(role: .destructive) {
                        premium.signOutApple()
                    } label: {
                        Label(EtubuClusterL10n.t("premiumSignOut"), systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .accessibilityIdentifier("etubu.premium.signout")
                }
            } else {
                Button {
                    showPaywall = true
                } label: {
                    HStack(spacing: 10) {
                        Label(EtubuClusterL10n.t("premiumUnlock"), systemImage: "star.circle.fill")
                        Spacer(minLength: 8)
                        Image("EtubuLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                    }
                }
                Text(String(format: EtubuClusterL10n.t("premiumPriceOnce"), premium.displayPrice))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !premium.isSignedIn {
                Button {
                    Task { _ = await premium.signInWithApple() }
                } label: {
                    Label(
                        premium.signingIn ? EtubuClusterL10n.t("premiumSigningIn") : EtubuClusterL10n.t("premiumSignInApple"),
                        systemImage: "apple.logo"
                    )
                }
                .disabled(premium.signingIn)
            } else if !premium.isPremium {
                HStack {
                    Image(systemName: "person.crop.circle.fill")
                        .foregroundStyle(.secondary)
                    Text(premium.appleDisplayName ?? EtubuClusterL10n.t("premiumSignedIn"))
                        .font(.subheadline)
                    Spacer()
                }
                Button(role: .destructive) {
                    premium.signOutApple()
                } label: {
                    Label(EtubuClusterL10n.t("premiumSignOut"), systemImage: "rectangle.portrait.and.arrow.right")
                }
                .accessibilityIdentifier("etubu.premium.signout")
            }

            if !premium.isPremium {
                Button {
                    Task { await premium.restore() }
                } label: {
                    Label(
                        premium.restoring ? EtubuClusterL10n.t("premiumRestoring") : EtubuClusterL10n.t("premiumRestore"),
                        systemImage: "arrow.clockwise"
                    )
                }
                .disabled(premium.restoring || premium.purchasing)

                Button {
                    if let onRequestRedeemCode {
                        onRequestRedeemCode()
                    } else {
                        showPaywall = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            premium.presentOfferCodeRedeem()
                        }
                    }
                } label: {
                    Label(EtubuClusterL10n.t("premiumRedeemCode"), systemImage: "ticket.fill")
                }
                .disabled(premium.purchasing || premium.restoring)
            }

            if let err = premium.lastError, !err.isEmpty {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text(EtubuClusterL10n.t("premiumSection"))
        } footer: {
            Text(EtubuClusterL10n.t("premiumFooter"))
                .font(.caption2)
        }
    }
}

/// Full-screen / sheet paywall for locked features.
struct EtubuPremiumPaywallView: View {
    @ObservedObject private var premium = EtubuPremiumManager.shared
    @Environment(\.dismiss) private var dismiss
    var accent: Color = .orange
    var highlight: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .center, spacing: 12) {
                        Image("EtubuLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(EtubuClusterL10n.t("premiumTitle"))
                                .font(.title2.weight(.bold))
                            Text(String(format: EtubuClusterL10n.t("premiumPriceOnce"), premium.displayPrice))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("etubu.premium.price")
                                .accessibilityLabel(premium.displayPrice)
                        }
                        Spacer(minLength: 0)
                    }

                    if let highlight, !highlight.isEmpty {
                        Text(highlight)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("etubu.premium.highlight")
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(EtubuClusterL10n.t("premiumFreeNote"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("etubu.premium.free.note")
                        featureRow("paintpalette.fill", EtubuClusterL10n.t("premiumFeatThemes"), id: "etubu.premium.feat.themes")
                        featureRow("map.fill", EtubuClusterL10n.t("premiumFeatMap"), id: "etubu.premium.feat.map")
                        featureRow("point.topleft.down.to.point.bottomright.curvepath.fill", EtubuClusterL10n.t("premiumFeatRoute"), id: "etubu.premium.feat.route")
                        featureRow("exclamationmark.triangle.fill", EtubuClusterL10n.t("premiumFeatWarn"), id: "etubu.premium.feat.warn")
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )

                    if !premium.isSignedIn {
                        Button {
                            Task { _ = await premium.signInWithApple() }
                        } label: {
                            Label(
                                premium.signingIn ? EtubuClusterL10n.t("premiumSigningIn") : EtubuClusterL10n.t("premiumSignInApple"),
                                systemImage: "apple.logo"
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                        .disabled(premium.signingIn)
                        .accessibilityIdentifier("etubu.premium.signin")
                    } else {
                        Label(
                            premium.appleDisplayName ?? EtubuClusterL10n.t("premiumSignedIn"),
                            systemImage: "checkmark.circle.fill"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }

                    Button {
                        Task {
                            let ok = await premium.purchase()
                            if ok { dismiss() }
                        }
                    } label: {
                        Group {
                            if premium.purchasing {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            } else {
                                Text(String(format: EtubuClusterL10n.t("premiumBuy"), premium.displayPrice))
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .disabled(premium.purchasing || premium.restoring)
                    .accessibilityIdentifier("etubu.premium.buy")
                    .accessibilityLabel(EtubuClusterL10n.t("premiumBuyA11y"))
                    .accessibilityValue(premium.displayPrice)

                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            premium.presentOfferCodeRedeem()
                        }
                    } label: {
                        Label(EtubuClusterL10n.t("premiumRedeemCode"), systemImage: "ticket.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .disabled(premium.purchasing || premium.restoring)
                    .accessibilityIdentifier("etubu.premium.redeem")

                    Button {
                        Task {
                            await premium.restore()
                            if premium.isPremium { dismiss() }
                        }
                    } label: {
                        Text(premium.restoring ? EtubuClusterL10n.t("premiumRestoring") : EtubuClusterL10n.t("premiumRestore"))
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(premium.restoring || premium.purchasing)
                    .accessibilityIdentifier("etubu.premium.restore")

                    Text(EtubuClusterL10n.t("premiumLegal"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if let err = premium.lastError, !err.isEmpty {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(20)
            }
            .navigationTitle(EtubuClusterL10n.t("premiumSection"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(EtubuClusterL10n.close) { dismiss() }
                }
            }
            .task {
                if premium.product == nil {
                    await premium.loadProduct()
                }
            }
        }
    }

    private func featureRow(_ symbol: String, _ text: String, id: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(accent)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
        .accessibilityLabel(text)
    }
}
