import Foundation

/// Hammers the store from several threads while a writer swaps the whole
/// table. Built with `-sanitize=thread`: if the lock in `PricingCatalog` is
/// removed, TSan reports the race on the backing dictionary and aborts, so
/// this fails loudly rather than flaking.
@main
struct PricingCatalogRaceTests {
    static func rates(_ input: Double) -> [String: CatalogRates] {
        ["m": CatalogRates(
            displayName: "M", inputPerMillion: input, outputPerMillion: input * 2,
            cacheCreationPerMillion: input, cacheReadPerMillion: 0
        )]
    }

    static func main() {
        let deadline = Date().addingTimeInterval(2)
        let group = DispatchGroup()

        DispatchQueue.global().async(group: group) {
            var flip = false
            while Date() < deadline {
                PricingCatalog.install(models: rates(flip ? 1 : 9), fetchedAt: Date())
                flip.toggle()
            }
        }
        for _ in 0..<4 {
            DispatchQueue.global().async(group: group) {
                while Date() < deadline {
                    _ = PricingCatalog.rates(for: "m")
                    _ = PricingCatalog.lastFetched
                }
            }
        }

        group.wait()
        print("PASS concurrent install/read is race-free")
        exit(0)
    }
}
