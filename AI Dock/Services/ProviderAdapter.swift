import SwiftUI

/// One provider integration, as data.
///
/// This is the architectural port from Codenotch, where **32 types conform to
/// `UsageProvider`** and `AppDelegate` simply holds a list. Before this, AI Dock
/// discovered providers in one place and read them in a `switch` in another, so
/// adding a provider meant editing two files and remembering to keep them in
/// sync. Now a provider is one value in `ProviderCatalog.all`.
///
/// The contract each provider fulfils is Codenotch's:
///   detect → borrow a credential some other tool already stores → ask the
///   provider's own endpoint → fall back to something local and honest.
@MainActor
struct ProviderAdapter {
    let id: String
    let displayName: String
    let glyph: ProviderGlyphKind
    let accent: Color

    /// Where we found evidence this provider is installed / signed in, or nil
    /// when it is not present at all.
    let detect: () -> DetectionSource?

    /// A real reading, or nil when the provider cannot be read right now. The
    /// caller renders "—" rather than inventing a zero.
    let read: (_ force: Bool) async -> UsageReading?
}

/// Every provider AI Dock knows how to read.
///
/// Each entry must be readable from a credential the user already has — AI Dock
/// never asks anyone to sign in again. A provider whose credential is absent
/// simply never appears.
@MainActor
enum ProviderCatalog {

    static var all: [ProviderAdapter] {
        [
            claude,
            codex,
            gemini,
            deepSeek,
            openRouter,
            zai
        ]
    }

    // MARK: - Claude

    static let claude = ProviderAdapter(
        id: "claude-code",
        displayName: "Claude",
        glyph: .claudeSpark,
        accent: Dock.Accent.claude,
        detect: { ClaudeCodeDetector.detect()?.source },
        read: { force in
            var reading = await ClaudeCodeDetector.fetchRealUsage(force: force)
            reading?.stats = await ClaudeCodeDetector.localStats()
            return reading
        }
    )

    // MARK: - Codex

    static let codex = ProviderAdapter(
        id: "codex-cli",
        displayName: "Codex",
        glyph: .openAIKnot,
        accent: Dock.Accent.codex,
        detect: { CodexCLIDetector.detect()?.source },
        read: { _ in await CodexCLIDetector.fetchRealUsage() }
    )

    // MARK: - Gemini

    static let gemini = ProviderAdapter(
        id: "gemini",
        displayName: "Gemini",
        glyph: .geminiStar,
        accent: Dock.Accent.gemini,
        detect: { GeminiDetector.detect()?.source },
        read: { _ in GeminiDetector.fetchUsage() }
    )

    // MARK: - DeepSeek (prepaid balance)

    static let deepSeek = ProviderAdapter(
        id: "deepseek",
        displayName: "DeepSeek",
        glyph: .deepSeek,
        accent: Dock.Accent.deepseek,
        detect: { DeepSeekDetector.detect() },
        read: { force in await DeepSeekDetector.fetchUsage(force: force) }
    )

    // MARK: - OpenRouter (prepaid credits)

    static let openRouter = ProviderAdapter(
        id: "openrouter",
        displayName: "OpenRouter",
        glyph: .openRouter,
        accent: Dock.Accent.openrouter,
        detect: { OpenRouterDetector.detect() },
        read: { force in await OpenRouterDetector.fetchUsage(force: force) }
    )

    // MARK: - Z.ai (GLM Coding Plan)

    static let zai = ProviderAdapter(
        id: "zai",
        displayName: "Z.ai",
        glyph: .zai,
        accent: Dock.Accent.zai,
        detect: { ZaiDetector.detect() },
        read: { force in await ZaiDetector.fetchUsage(force: force) }
    )
}
