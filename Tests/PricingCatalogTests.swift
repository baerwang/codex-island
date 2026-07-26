import Foundation

/// Locks down payload validation and the in-memory store: what the app is
/// willing to believe from the network, and that a rejection never mutates
/// what it already has.
@main
struct PricingCatalogTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if condition { print("PASS \(label)") } else { print("FAIL \(label)"); failures += 1 }
    }

    static func json(_ raw: String) -> Data { Data(raw.utf8) }

    static let valid = """
    {"schemaVersion":1,"generatedAt":"2026-07-26T01:00:00Z","models":{
      "claude-opus-4-8":{"displayName":"Opus 4.8","inputPerMillion":5,
        "outputPerMillion":25,"cacheCreationPerMillion":6.25,"cacheReadPerMillion":0.5}}}
    """

    static func main() {
        // A well-formed v1 payload is accepted and decoded.
        if case .payload(let p) = PricingCatalog.interpret(status: 200, data: json(valid)) {
            expect(p.models.count == 1, "valid payload decodes one model")
            expect(p.models["claude-opus-4-8"]?.inputPerMillion == 5, "rates decode")
            expect(p.models["claude-opus-4-8"]?.displayName == "Opus 4.8", "displayName decodes")
        } else {
            expect(false, "valid payload accepted")
        }

        expect(PricingCatalog.interpret(status: 304, data: Data()) == .unchanged,
               "304 reports unchanged")

        // Everything below must be rejected — each one would otherwise zero
        // out or corrupt the user's dollar totals.
        let rejects: [(String, CatalogFetchResult)] = [
            ("HTTP 500", PricingCatalog.interpret(status: 500, data: json(valid))),
            ("HTTP 404", PricingCatalog.interpret(status: 404, data: Data())),
            ("malformed JSON", PricingCatalog.interpret(status: 200, data: json("{nope"))),
            ("wrong schema", PricingCatalog.interpret(
                status: 200,
                data: json(#"{"schemaVersion":2,"generatedAt":"x","models":{"a":{"inputPerMillion":1,"outputPerMillion":1,"cacheCreationPerMillion":1,"cacheReadPerMillion":1}}}"#))),
            ("empty catalog", PricingCatalog.interpret(
                status: 200,
                data: json(#"{"schemaVersion":1,"generatedAt":"x","models":{}}"#))),
        ]
        for (label, result) in rejects {
            if case .rejected = result { print("PASS rejects \(label)") }
            else { print("FAIL rejects \(label)"); failures += 1 }
        }

        // displayName is optional — a payload without it still decodes.
        if case .payload(let p) = PricingCatalog.interpret(
            status: 200,
            data: json(#"{"schemaVersion":1,"generatedAt":"x","models":{"gpt-9":{"inputPerMillion":1,"outputPerMillion":2,"cacheCreationPerMillion":1,"cacheReadPerMillion":0}}}"#)
        ) {
            expect(p.models["gpt-9"]?.displayName == nil, "absent displayName decodes as nil")
        } else {
            expect(false, "payload without displayName accepted")
        }

        // Store round trip.
        expect(PricingCatalog.lastFetched == nil, "store starts empty")
        expect(PricingCatalog.rates(for: "claude-opus-4-8") == nil, "empty store returns nil")

        let stamp = Date(timeIntervalSince1970: 1_784_000_000)
        PricingCatalog.install(
            models: ["claude-opus-4-8": CatalogRates(
                displayName: "Opus 4.8", inputPerMillion: 5, outputPerMillion: 25,
                cacheCreationPerMillion: 6.25, cacheReadPerMillion: 0.5)],
            fetchedAt: stamp
        )
        expect(PricingCatalog.rates(for: "claude-opus-4-8")?.outputPerMillion == 25,
               "installed rates are readable")
        expect(PricingCatalog.lastFetched == stamp, "install records the fetch time")
        expect(PricingCatalog.rates(for: "not-a-model") == nil, "unknown id returns nil")

        // Installing replaces wholesale rather than merging.
        PricingCatalog.install(models: ["gpt-5.6": CatalogRates(
            displayName: nil, inputPerMillion: 5, outputPerMillion: 30,
            cacheCreationPerMillion: 6.25, cacheReadPerMillion: 0.5)], fetchedAt: stamp)
        expect(PricingCatalog.rates(for: "claude-opus-4-8") == nil,
               "install replaces the whole table")

        exit(failures == 0 ? 0 : 1)
    }
}
