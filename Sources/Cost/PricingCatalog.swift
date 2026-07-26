import Foundation

struct CatalogRates: Codable, Equatable {
    let displayName: String?
    let inputPerMillion: Double
    let outputPerMillion: Double
    let cacheCreationPerMillion: Double
    let cacheReadPerMillion: Double
}

struct CatalogPayload: Codable, Equatable {
    let schemaVersion: Int
    let generatedAt: String
    let models: [String: CatalogRates]
}

enum CatalogFetchResult: Equatable {
    case payload(CatalogPayload)
    case unchanged
    case rejected(String)
}

/// Remote model price table, refreshed daily from the published catalog.
///
/// `Pricing` reads this before its own embedded seed, so anything installed
/// here decides what the user is charged on screen. Every path that fails to
/// produce a complete, current payload therefore leaves the previous state
/// untouched rather than installing something partial.
enum PricingCatalog {
    static let supportedSchemaVersion = 1

    /// Literal, known-good URL — the same force-unwrap idiom `UsageFetcher`
    /// uses for its endpoints.
    static let endpoint = URL(
        string: "https://ericjypark.github.io/codex-island-model-catalog/v1/models.json"
    )!

    /// `CostStore` summarizes on two concurrent detached tasks, so reads land
    /// off the main actor while a refresh installs. The lock is what keeps
    /// that from being a data race.
    private static let lock = NSLock()
    private static var models: [String: CatalogRates] = [:]
    private static var fetchedAt: Date?

    static func rates(for canonical: String) -> CatalogRates? {
        lock.lock()
        defer { lock.unlock() }
        return models[canonical]
    }

    static var lastFetched: Date? {
        lock.lock()
        defer { lock.unlock() }
        return fetchedAt
    }

    static func install(models newModels: [String: CatalogRates], fetchedAt stamp: Date) {
        lock.lock()
        defer { lock.unlock() }
        models = newModels
        fetchedAt = stamp
    }

    /// Decides what a response means. Pure, so the whole trust boundary is
    /// testable without a network.
    static func interpret(status: Int, data: Data) -> CatalogFetchResult {
        if status == 304 { return .unchanged }
        guard status == 200 else { return .rejected("HTTP \(status)") }
        guard let payload = try? JSONDecoder().decode(CatalogPayload.self, from: data) else {
            return .rejected("malformed JSON")
        }
        guard payload.schemaVersion == supportedSchemaVersion else {
            return .rejected("unsupported schemaVersion \(payload.schemaVersion)")
        }
        guard !payload.models.isEmpty else { return .rejected("empty catalog") }
        return .payload(payload)
    }
}
