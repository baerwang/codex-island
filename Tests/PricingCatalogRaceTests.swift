import Foundation

/// Hammers the store from several threads, one accessor per thread. Built
/// with `-sanitize=thread`: removing a lock leaves that thread with no
/// happens-before edges, TSan reports the race and aborts, so this fails
/// loudly rather than flaking.
///
/// One accessor per thread is load-bearing, not style. With a single thread
/// calling several accessors in sequence, the locks on either side of an
/// unlocked one cover it and the sanitizer stays silent.
///
/// Known gap: `markVerified(at:)` is NOT covered. Removing its lock is not
/// detected, across two harness designs and ten runs. The likely cause is
/// shadow-memory eviction — `install` also writes `fetchedAt`, at high
/// frequency and under the lock, and TSan keeps only four shadow cells per
/// eight-byte granule. `install`, `rates(for:)` and `storedETag` are all
/// verified to fail when their locks are removed.
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
        DispatchQueue.global().async(group: group) {
            while Date() < deadline {
                PricingCatalog.markVerified(at: Date())
            }
        }
        DispatchQueue.global().async(group: group) {
            var flip = false
            while Date() < deadline {
                // to: nil writes no file — this exists only to touch the ETag,
                // which nothing public reads, so the race it must expose is
                // write-against-write between this thread and the next.
                PricingCatalog.persist(
                    CatalogPayload(schemaVersion: 1, generatedAt: "x", models: rates(1)),
                    etag: flip ? "\"a\"" : "\"b\"", at: Date(), to: nil)
                flip.toggle()
            }
        }
        DispatchQueue.global().async(group: group) {
            while Date() < deadline {
                PricingCatalog.persist(
                    CatalogPayload(schemaVersion: 1, generatedAt: "y", models: rates(2)),
                    etag: "\"c\"", at: Date(), to: nil)
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
