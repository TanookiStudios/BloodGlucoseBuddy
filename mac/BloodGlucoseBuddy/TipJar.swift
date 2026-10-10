#if APP_STORE
import StoreKit

/// Three one-off tips, bought through Apple (App Store builds only; Apple doesn't allow tip links there).
@MainActor
final class TipJar: ObservableObject {
    static let ids = ["com.tanookistudios.bloodglucosebuddy.tip.small",
                      "com.tanookistudios.bloodglucosebuddy.tip.medium",
                      "com.tanookistudios.bloodglucosebuddy.tip.large"]

    static func caption(_ id: String) -> String {
        switch id {
        case ids[0]: return "Thanks!"
        case ids[1]: return "A coffee"
        default: return "A very good sandwich"
        }
    }

    @Published private(set) var products: [Product] = []
    @Published private(set) var problem: String?
    @Published private(set) var busy = false
    @Published private(set) var thanked = false
    private var updates: Task<Void, Never>?

    init() {
        // Finishes tips that complete later (Ask to Buy, or an interrupted purchase), as Apple requires.
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                guard case .verified(let t) = update else { continue }
                await t.finish()
                self?.thanked = true
            }
        }
        Task { await load() }
    }

    deinit { updates?.cancel() }

    func load() async {
        do {
            products = try await Product.products(for: Self.ids).sorted { $0.price < $1.price }
            if products.isEmpty { problem = "Tips aren't available right now." }
        } catch {
            problem = "Couldn't reach the App Store. Tips aren't available right now."
        }
    }

    func buy(_ product: Product) async {
        busy = true
        defer { busy = false }
        problem = nil
        do {
            switch try await product.purchase() {
            case .success(.verified(let t)):
                await t.finish()
                thanked = true
            case .success(.unverified):
                problem = "The App Store couldn't confirm that tip, so nothing was charged."
            case .pending:
                problem = "Waiting for approval. Thank you!"
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            problem = "That didn't go through: \(error.localizedDescription)"
        }
    }
}
#endif
