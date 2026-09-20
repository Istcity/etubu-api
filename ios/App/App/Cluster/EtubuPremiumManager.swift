import Foundation
import StoreKit
import AuthenticationServices
import UIKit
import Security

/// App Store paid download (v1.1+) unlocks all features.
/// Legacy IAP product id kept for restore/history; freemium gates are disabled.
@MainActor
final class EtubuPremiumManager: ObservableObject {
    static let shared = EtubuPremiumManager()

    /// Paid-upfront App Store model — no free/premium feature split.
    static let isPaidAppModel = true

    static let productID = "com.etubu.premium"
    /// Default theme when enforcing (legacy free-tier path; unused in paid-app mode).
    static let freeTheme: ClusterTheme = .tesla

    @Published private(set) var isPremium: Bool = true
    /// Cold start: false until first StoreKit probe finishes (or paid-app unlock settles).
    /// Gates should wait when locked so transient empty entitlements don’t flash paywall.
    @Published private(set) var entitlementReady: Bool = false
    @Published var product: Product?
    @Published var purchasing = false
    @Published var restoring = false
    @Published var signingIn = false
    @Published var lastError: String?
    /// SwiftUI `.offerCodeRedemption` — kök view’dan sun (sheet içinde açılmaz).
    @Published var offerCodeRedeemPresented = false
    @Published private(set) var appleUserID: String?
    @Published private(set) var appleDisplayName: String?

    var isSignedIn: Bool { appleUserID != nil && !(appleUserID?.isEmpty ?? true) }

    static let turkeyPriceLabel = "249 TL"
    static let globalPriceLabel = "$6.99"

    var displayPrice: String {
        if shouldShowTurkeyPrice { return Self.turkeyPriceLabel }
        if let product, !Self.isPaidAppModel { return product.displayPrice }
        return Self.globalPriceLabel
    }

    /// UI dili/bölge TR ise App Store storefront USD olsa bile 249 TL göster.
    private var shouldShowTurkeyPrice: Bool {
        if EtubuAppLanguage.current == .tr { return true }
        let region = Locale.current.region?.identifier
            ?? Locale.current.regionCode
            ?? ""
        if region == "TR" { return true }
        let lang = Locale.preferredLanguages.first?.lowercased() ?? ""
        if lang.hasPrefix("tr") { return true }
        return storefrontCountryCode == "TUR"
    }

    private var storefrontCountryCode: String?

    private var transactionListener: Task<Void, Never>?
    private var appleSession: EtubuAppleSignInCoordinator?

    private init() {
        appleUserID = EtubuKeychain.string(for: .appleUserID)
        appleDisplayName = EtubuKeychain.string(for: .appleDisplayName)
            ?? UserDefaults.standard.string(forKey: "etubu.apple.displayName")

        if Self.isPaidAppModel {
            // App Store purchase unlocks everything — no IAP freemium gate.
            isPremium = true
            entitlementReady = true
            EtubuClusterAudioBridge.setPremium(true)
            Task { await refreshCredentialState() }
            return
        }

        // Legacy freemium path (kept for possible rollback).
        isPremium = false
        EtubuClusterAudioBridge.setPremium(false)
        enforceFreeThemeIfNeeded()
        transactionListener = listenForTransactions()
        Task { await loadProduct() }
        Task { await bootstrap() }
    }

    private func bootstrap() async {
        await refreshCredentialState()
        await checkEntitlement()
        enforceFreeThemeIfNeeded()
    }

    func enforceFreeThemeIfNeeded() {
        guard !Self.isPaidAppModel else { return }
        guard !isPremium else { return }
        if ClusterTheme.stored != Self.freeTheme {
            ClusterTheme.stored = Self.freeTheme
        }
        if EtubuWallpaperStyle.stored != .atmospheric {
            EtubuWallpaperStyle.stored = .atmospheric
        }
    }

    func loadProduct() async {
        do {
            if let storefront = await Storefront.current {
                storefrontCountryCode = storefront.countryCode
            }
            let products = try await Product.products(for: [Self.productID])
            product = products.first
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// SIWA then StoreKit purchase (no-op in paid-app model — already unlocked).
    @discardableResult
    func purchase() async -> Bool {
        if Self.isPaidAppModel {
            applyPremium(true)
            entitlementReady = true
            return true
        }
        lastError = nil
        if !isSignedIn {
            let ok = await signInWithApple()
            guard ok else { return false }
        }
        if product == nil { await loadProduct() }
        guard let product, !purchasing else {
            lastError = product == nil ? EtubuClusterL10n.t("premiumProductMissing") : nil
            return false
        }
        purchasing = true
        defer { purchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let tx = try checkVerified(verification)
                await tx.finish()
                applyPremium(true)
                entitlementReady = true
                return true
            case .userCancelled:
                return false
            case .pending:
                lastError = EtubuClusterL10n.t("premiumPending")
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func restore() async {
        if Self.isPaidAppModel {
            applyPremium(true)
            entitlementReady = true
            return
        }
        lastError = nil
        restoring = true
        defer { restoring = false }
        if !isSignedIn {
            _ = await signInWithApple()
        }
        do {
            try await AppStore.sync()
        } catch {
            lastError = error.localizedDescription
        }
        await checkEntitlement()
        if !isPremium {
            lastError = lastError ?? EtubuClusterL10n.t("premiumRestoreNone")
        }
    }

    /// Await first (or fresh) entitlement probe — route/paywall gates use this on cold start.
    func ensureEntitlementChecked() async {
        if Self.isPaidAppModel {
            applyPremium(true)
            entitlementReady = true
            return
        }
        if entitlementReady { return }
        await checkEntitlement()
    }

    /// Offer code — Ayarlar/Paywall kapandıktan sonra UIKit ile sun (SwiftUI nested sheet kırılır).
    func presentOfferCodeRedeem() {
        lastError = nil
        offerCodeRedeemPresented = false
        Task { @MainActor in
            // Sheet dismiss animasyonu bitsin
            try? await Task.sleep(nanoseconds: 450_000_000)
            if let scene = Self.activeWindowScene() {
                do {
                    try await AppStore.presentOfferCodeRedeemSheet(in: scene)
                    await checkEntitlement()
                    return
                } catch {
                    // Continue to fallbacks
                    let msg = error.localizedDescription
                    if !msg.isEmpty { lastError = msg }
                }
            }
            // StoreKit 1 fallback
            SKPaymentQueue.default().presentCodeRedemptionSheet()
            // SwiftUI yedek (bazı iOS sürümleri)
            offerCodeRedeemPresented = true
            try? await Task.sleep(nanoseconds: 800_000_000)
            await checkEntitlement()
        }
    }

    private static func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let overlay = scenes.first(where: { scene in
            scene.windows.contains(where: { $0 is EtubuOverlayWindow })
        }) {
            return overlay
        }
        return scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
    }

    func handleOfferCodeRedeemResult(_ result: Result<Void, Error>) {
        switch result {
        case .success:
            Task { await checkEntitlement() }
        case .failure(let error):
            let msg = error.localizedDescription
            if !msg.isEmpty { lastError = msg }
        }
    }

    @discardableResult
    func signInWithApple() async -> Bool {
        lastError = nil
        signingIn = true
        defer { signingIn = false }
        guard let anchor = Self.presentationAnchor() else {
            lastError = "no window"
            return false
        }
        return await withCheckedContinuation { cont in
            let session = EtubuAppleSignInCoordinator(anchor: anchor) { [weak self] result in
                Task { @MainActor in
                    self?.appleSession = nil
                    switch result {
                    case .success(let cred):
                        self?.persistAppleIdentity(user: cred.user, name: cred.name)
                        Task { await self?.checkEntitlement() }
                        cont.resume(returning: true)
                    case .failure(let err):
                        if case .message(let msg) = err, !msg.isEmpty {
                            self?.lastError = msg
                        }
                        cont.resume(returning: false)
                    }
                }
            }
            self.appleSession = session
            session.start()
        }
    }

    func signOutApple() {
        appleUserID = nil
        appleDisplayName = nil
        EtubuKeychain.delete(.appleUserID)
        EtubuKeychain.delete(.appleDisplayName)
        UserDefaults.standard.removeObject(forKey: "etubu.apple.displayName")
        if Self.isPaidAppModel {
            applyPremium(true)
            entitlementReady = true
            return
        }
        // Legacy: premium tied to Apple identity + StoreKit entitlement.
        applyPremium(false)
        entitlementReady = true
    }

    private func persistAppleIdentity(user: String, name: String?) {
        appleUserID = user
        EtubuKeychain.set(user, for: .appleUserID)
        if let name, !name.isEmpty {
            appleDisplayName = name
            EtubuKeychain.set(name, for: .appleDisplayName)
            UserDefaults.standard.set(name, forKey: "etubu.apple.displayName")
        }
    }

    private func applyPremium(_ on: Bool) {
        let unlocked = Self.isPaidAppModel ? true : on
        let changed = isPremium != unlocked
        isPremium = unlocked
        EtubuClusterAudioBridge.setPremium(unlocked)
        if !unlocked { enforceFreeThemeIfNeeded() }
        if changed { objectWillChange.send() }
    }

    /// StoreKit entitlement probe (paid-app model always unlocks).
    private func checkEntitlement() async {
        if Self.isPaidAppModel {
            applyPremium(true)
            entitlementReady = true
            return
        }
        guard isSignedIn else {
            applyPremium(false)
            entitlementReady = true
            return
        }

        var found = false
        for await result in Transaction.currentEntitlements {
            if let tx = try? checkVerified(result) {
                if tx.productID == Self.productID {
                    found = true
                    break
                }
            }
        }

        applyPremium(found)
        entitlementReady = true
    }

    func refreshEntitlementQuietly() async {
        if Self.isPaidAppModel {
            applyPremium(true)
            entitlementReady = true
            return
        }
        await checkEntitlement()
        EtubuClusterAudioBridge.setPremium(isPremium)
    }

    private func refreshCredentialState() async {
        guard let id = appleUserID else { return }
        let provider = ASAuthorizationAppleIDProvider()
        do {
            let state = try await provider.credentialState(forUserID: id)
            switch state {
            case .revoked, .notFound:
                signOutApple()
            default:
                break
            }
        } catch {
            // Keep cached identity; network / provider glitches.
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task {
            for await result in Transaction.updates {
                do {
                    let tx = try checkVerified(result)
                    guard tx.productID == Self.productID else { continue }
                    await tx.finish()
                    applyPremium(true)
                    entitlementReady = true
                } catch {}
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    enum StoreError: Error { case failedVerification }

    private static func presentationAnchor() -> ASPresentationAnchor? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let key = scenes.flatMap(\.windows).first(where: \.isKeyWindow) { return key }
        return scenes.flatMap(\.windows).first
    }
}

// MARK: - Keychain

enum EtubuKeychain {
    enum Key: String {
        case appleUserID = "etubu.apple.userID"
        case appleDisplayName = "etubu.apple.displayName"
    }

    static func set(_ value: String, for key: Key) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecAttrService as String: "com.etubu.app",
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func string(for key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecAttrService as String: "com.etubu.app",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: Key) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecAttrService as String: "com.etubu.app",
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - SIWA coordinator

private final class EtubuAppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    struct Cred {
        var user: String
        var name: String?
    }

    enum SignInError: Error {
        case message(String)
    }

    private let anchor: ASPresentationAnchor
    private let completion: (Result<Cred, SignInError>) -> Void
    private var controller: ASAuthorizationController?

    init(anchor: ASPresentationAnchor, completion: @escaping (Result<Cred, SignInError>) -> Void) {
        self.anchor = anchor
        self.completion = completion
    }

    func start() {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        let c = ASAuthorizationController(authorizationRequests: [request])
        c.delegate = self
        c.presentationContextProvider = self
        controller = c
        c.performRequests()
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor { anchor }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            completion(.failure(.message("invalid credential")))
            return
        }
        var name: String?
        if let full = credential.fullName {
            let parts = [full.givenName, full.familyName].compactMap { $0 }.filter { !$0.isEmpty }
            if !parts.isEmpty { name = parts.joined(separator: " ") }
        }
        completion(.success(Cred(user: credential.user, name: name)))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let ns = error as NSError
        if ns.code == ASAuthorizationError.canceled.rawValue {
            completion(.failure(.message("")))
        } else {
            completion(.failure(.message(error.localizedDescription)))
        }
    }
}
