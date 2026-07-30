import Foundation
import StoreKit

final class EtubuPremiumManager: ObservableObject {
    static let shared = EtubuPremiumManager()

    static let productID = "com.etubu.premium"

    /// App Store'a yayınlanana kadar herkes premium — `frozenOpen` kaldırılınca gate aktif olur.
    static let frozenOpen = true

    @Published var isPremium: Bool {
        didSet { UserDefaults.standard.set(isPremium, forKey: "etubu.premium.unlocked") }
    }

    @Published var product: Product?
    @Published var purchasing = false

    private var transactionListener: Task<Void, Never>?

    private init() {
        isPremium = Self.frozenOpen || UserDefaults.standard.bool(forKey: "etubu.premium.unlocked")
        guard !Self.frozenOpen else { return }
        transactionListener = listenForTransactions()
        Task { @MainActor in await self.loadProduct() }
        Task { @MainActor in await self.checkEntitlement() }
    }

    @MainActor
    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
        } catch {}
    }

    @MainActor
    func purchase() async -> Bool {
        guard let product, !purchasing else { return false }
        purchasing = true
        defer { purchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if let tx = try? verification.payloadValue {
                    await tx.finish()
                    unlock()
                    return true
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {}
        return false
    }

    @MainActor
    func restore() async {
        try? await AppStore.sync()
        await checkEntitlement()
    }

    func unlock() {
        DispatchQueue.main.async {
            self.isPremium = true
            EtubuClusterAudioBridge.setPremium(true)
        }
    }

    @MainActor
    private func checkEntitlement() async {
        for await result in Transaction.currentEntitlements {
            if let tx = try? result.payloadValue, tx.productID == Self.productID {
                unlock()
                return
            }
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached {
            for await result in Transaction.updates {
                if let tx = try? result.payloadValue, tx.productID == EtubuPremiumManager.productID {
                    await tx.finish()
                    await MainActor.run {
                        EtubuPremiumManager.shared.unlock()
                    }
                }
            }
        }
    }
}
