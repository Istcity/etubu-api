import Foundation
import StoreKit
import AuthenticationServices
import UIKit
import Security

/// Lifetime premium (`com.etubu.premium`) + Sign in with Apple identity.
@MainActor
final class EtubuPremiumManager: ObservableObject {
    static let shared = EtubuPremiumManager()

    static let productID = "com.etubu.premium"
    /// Free tier: only this theme.
    static let freeTheme: ClusterTheme = .tesla

    /// Production gates on — entitlement from StoreKit.
    static let frozenOpen = false

    @Published private(set) var isPremium: Bool = false
    /// Cold start: false until first StoreKit probe finishes (or force/cache path settles).
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

    private static let unlockedDefaultsKey = "etubu.premium.unlocked"

    var isSignedIn: Bool { appleUserID != nil && !(appleUserID?.isEmpty ?? true) }

    /// Maestro / debug / review launch overrides — always win over StoreKit.
    static var isForcePremiumLaunch: Bool {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-etubuForcePremium") || args.contains("etubuForcePremium") {
            return true
        }
        let env = ProcessInfo.processInfo.environment
        if env["etubuForcePremium"] == "1" || env["etubuForcePremium"]?.lowercased() == "true" {
            return true
        }
        if UserDefaults.standard.bool(forKey: "etubuForcePremium") { return true }
        return false
    }

    /// Türkiye vitrin fiyatı (ASC’de de 249 TRY olmalı).
    static let turkeyPriceLabel = "249 TL"

    var displayPrice: String {
        if shouldShowTurkeyPrice {
            return Self.turkeyPriceLabel
        }
        if let product { return product.displayPrice }
        return Self.turkeyPriceLabel
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

        if Self.frozenOpen || Self.isForcePremiumLaunch {
            // Force / open build: unlock immediately; never race StoreKit into a lock.
            applyPremium(true, persistCache: !Self.isForcePremiumLaunch || Self.frozenOpen)
            entitlementReady = true
            // Still listen so a real purchase can refresh product metadata; never downgrade force.
            if !Self.frozenOpen {
                transactionListener = listenForTransactions()
                Task { await loadProduct() }
            }
            return
        }

        // Cached flag until StoreKit confirms (false if never purchased).
        // Keep unlocked UI from the first frame when UserDefaults says so — avoid false-locked flash.
        let cached = UserDefaults.standard.bool(forKey: Self.unlockedDefaultsKey)
        isPremium = cached
        if cached { EtubuClusterAudioBridge.setPremium(true) }

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

    /// SIWA then StoreKit purchase.
    @discardableResult
    func purchase() async -> Bool {
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
        // After AppStore.sync(), empty entitlements are authoritative — allow lock.
        await checkEntitlement(allowDowngrade: true)
        if !isPremium {
            lastError = lastError ?? EtubuClusterL10n.t("premiumRestoreNone")
        }
    }

    /// Await first (or fresh) entitlement probe — route/paywall gates use this on cold start.
    func ensureEntitlementChecked() async {
        if Self.frozenOpen || Self.isForcePremiumLaunch {
            applyPremium(true, persistCache: Self.frozenOpen)
            entitlementReady = true
            return
        }
        if entitlementReady { return }
        await checkEntitlement(allowDowngrade: false)
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
        // Premium entitlement stays with Apple ID / StoreKit — do not lock on sign-out.
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

    private func applyPremium(_ on: Bool, persistCache: Bool = true) {
        // Force / frozen unlock sources must not be cleared by a later StoreKit miss.
        if !on && (Self.frozenOpen || Self.isForcePremiumLaunch) {
            isPremium = true
            EtubuClusterAudioBridge.setPremium(true)
            objectWillChange.send()
            return
        }
        let changed = isPremium != on
        isPremium = on
        if persistCache {
            UserDefaults.standard.set(on, forKey: Self.unlockedDefaultsKey)
        }
        EtubuClusterAudioBridge.setPremium(on)
        if !on { enforceFreeThemeIfNeeded() }
        if changed { objectWillChange.send() }
    }

    /// StoreKit entitlement probe.
    /// - `allowDowngrade: false` (cold start / offer redeem): never clear a cached unlock when
    ///   `currentEntitlements` is briefly empty — that was the flaky “premium locked” bug.
    /// - `allowDowngrade: true` (explicit Restore after `AppStore.sync()`): empty = lock.
    private func checkEntitlement(allowDowngrade: Bool = false) async {
        if Self.frozenOpen || Self.isForcePremiumLaunch {
            applyPremium(true, persistCache: Self.frozenOpen)
            entitlementReady = true
            return
        }

        var found = false
        for await result in Transaction.currentEntitlements {
            if let tx = try? checkVerified(result), tx.productID == Self.productID {
                found = true
                break
            }
        }

        if found {
            applyPremium(true)
        } else if allowDowngrade {
            applyPremium(false)
        } else {
            // Keep cached unlock; only confirm lock when we never had one.
            let cached = UserDefaults.standard.bool(forKey: Self.unlockedDefaultsKey)
            if cached {
                // Stay unlocked; re-mirror web bridge in case Cap loaded late.
                applyPremium(true)
            } else if !isPremium {
                applyPremium(false)
            }
        }
        entitlementReady = true
    }

    /// Foreground: re-check without flashing lock if cache says unlocked.
    func refreshEntitlementQuietly() async {
        if Self.frozenOpen || Self.isForcePremiumLaunch {
            applyPremium(true, persistCache: Self.frozenOpen)
            entitlementReady = true
            EtubuClusterAudioBridge.setPremium(true)
            return
        }
        await checkEntitlement(allowDowngrade: false)
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
