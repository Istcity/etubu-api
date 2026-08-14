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
                            .font(EtubuClusterFonts.ui(16, weight: .semibold))
                        if premium.isSignedIn {
                            Text(premium.appleDisplayName ?? EtubuClusterL10n.t("premiumSignedIn"))
                                .font(EtubuClusterFonts.ui(12, weight: .medium))
                                .foregroundStyle(ClusterTheme.stored.mutedText)
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
                    .font(EtubuClusterFonts.ui(12, weight: .medium))
                    .foregroundStyle(ClusterTheme.stored.mutedText)
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
                        .font(EtubuClusterFonts.ui(14, weight: .medium))
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
                    .font(EtubuClusterFonts.ui(12, weight: .medium))
                    .foregroundStyle(.orange)
            }
        } header: {
            EtubuSheetSectionTitle(title: EtubuClusterL10n.t("premiumSection"), theme: ClusterTheme.stored, motion: .premium)
        } footer: {
            EtubuSheetHint(text: EtubuClusterL10n.t("premiumFooter"), theme: ClusterTheme.stored)
        }
        .etubuSheetSection(ClusterTheme.stored)
    }
}

/// Full-screen / sheet paywall for locked features.
struct EtubuPremiumPaywallView: View {
    @ObservedObject private var premium = EtubuPremiumManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.clusterTheme) private var theme
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
                                .font(EtubuClusterFonts.ui(22, weight: .bold))
                                .foregroundStyle(theme.primaryText)
                            Text(String(format: EtubuClusterL10n.t("premiumPriceOnce"), premium.displayPrice))
                                .font(EtubuClusterFonts.ui(14, weight: .semibold))
                                .foregroundStyle(theme.mutedText)
                                .accessibilityIdentifier("etubu.premium.price")
                                .accessibilityLabel(premium.displayPrice)
                        }
                        Spacer(minLength: 0)
                    }

                    if let highlight, !highlight.isEmpty {
                        Text(highlight)
                            .font(EtubuClusterFonts.ui(14, weight: .medium))
                            .foregroundStyle(theme.secondaryText)
                            .accessibilityIdentifier("etubu.premium.highlight")
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(EtubuClusterL10n.t("premiumFreeNote"))
                            .font(EtubuClusterFonts.ui(12, weight: .semibold))
                            .foregroundStyle(theme.mutedText)
                            .accessibilityIdentifier("etubu.premium.free.note")
                        featureRow("paintpalette.fill", EtubuClusterL10n.t("premiumFeatThemes"), id: "etubu.premium.feat.themes")
                        featureRow("map.fill", EtubuClusterL10n.t("premiumFeatMap"), id: "etubu.premium.feat.map")
                        featureRow("point.topleft.down.to.point.bottomright.curvepath.fill", EtubuClusterL10n.t("premiumFeatRoute"), id: "etubu.premium.feat.route")
                        featureRow("exclamationmark.triangle.fill", EtubuClusterL10n.t("premiumFeatWarn"), id: "etubu.premium.feat.warn")
                    }
                    .etubuSheetCard(theme)

                    if !premium.isSignedIn {
                        Button {
                            Task { _ = await premium.signInWithApple() }
                        } label: {
                            Label(
                                premium.signingIn ? EtubuClusterL10n.t("premiumSigningIn") : EtubuClusterL10n.t("premiumSignInApple"),
                                systemImage: "apple.logo"
                            )
                            .font(EtubuClusterFonts.ui(16, weight: .semibold))
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
                        .font(EtubuClusterFonts.ui(14, weight: .medium))
                        .foregroundStyle(theme.mutedText)
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
                                    .tint(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            } else {
                                Text(String(format: EtubuClusterL10n.t("premiumBuy"), premium.displayPrice))
                                    .font(EtubuClusterFonts.ui(16, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            }
                        }
                        .foregroundStyle(.black)
                    }
                    .background(theme.accent, in: Capsule())
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
                            .font(EtubuClusterFonts.ui(15, weight: .semibold))
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
                            .font(EtubuClusterFonts.ui(15, weight: .medium))
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(premium.restoring || premium.purchasing)
                    .accessibilityIdentifier("etubu.premium.restore")

                    Text(EtubuClusterL10n.t("premiumLegal"))
                        .font(EtubuClusterFonts.ui(11, weight: .medium))
                        .foregroundStyle(theme.mutedText)

                    if let err = premium.lastError, !err.isEmpty {
                        Text(err)
                            .font(EtubuClusterFonts.ui(12, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                }
                .padding(20)
            }
            .background { EtubuSheetBackdrop(theme: theme) }
            .navigationTitle(EtubuClusterL10n.t("premiumSection"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.canvas.opacity(0.94), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(EtubuClusterL10n.close) { dismiss() }
                        .font(EtubuClusterFonts.ui(16, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
            }
            .task {
                if premium.product == nil {
                    await premium.loadProduct()
                }
            }
        }
        .tint(theme.accent)
    }

    private func featureRow(_ symbol: String, _ text: String, id: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(accent == .orange ? theme.accent : accent)
                .frame(width: 22)
            Text(text)
                .font(EtubuClusterFonts.ui(14, weight: .medium))
                .foregroundStyle(theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
        .accessibilityLabel(text)
    }
}
