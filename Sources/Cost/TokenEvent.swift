import Foundation

/// A single billable unit of token consumption parsed from a local session log.
/// Both `ClaudeLogReader` and `CodexLogReader` emit these so the cost pipeline
/// downstream is provider-agnostic.
struct TokenEvent {
    enum Provider {
        case claude
        case codex
    }

    let provider: Provider
    let timestamp: Date
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    /// Tokens written to the prompt cache during this turn. Anthropic-only.
    let cacheCreationTokens: Int
    /// Tokens served from the prompt cache during this turn. Both providers
    /// (Codex calls these "cached_input_tokens" — they are billed at a
    /// discount but still draw from the input bucket).
    let cacheReadTokens: Int
    /// Canonical local working directory from the CLI transcript, when the
    /// provider log contains one. Never sent off-device.
    let projectID: String?
    /// Compact label derived from `projectID` for UI use.
    let projectName: String?
    /// Identifies the manually configured Codex profile that emitted the event.
    /// nil for Claude and for legacy/unattributed logs.
    let sourceID: String?

    init(
        provider: Provider, timestamp: Date, model: String,
        inputTokens: Int, outputTokens: Int, cacheCreationTokens: Int,
        cacheReadTokens: Int, projectID: String? = nil,
        projectName: String? = nil, sourceID: String? = nil
    ) {
        self.provider = provider
        self.timestamp = timestamp
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.projectID = projectID
        self.projectName = projectName
        self.sourceID = sourceID
    }
}
