import SwiftUI

/// A detected AI provider on the user's machine (Claude Code, Codex CLI, …).
struct Provider: Identifiable, Hashable {
    let id: String            // stable key, e.g. "claude-code"
    let displayName: String   // "Claude", "Codex"
    let glyph: ProviderGlyphKind
    let accent: Color

    /// Where we found evidence of this provider (for the UI / debugging).
    let source: DetectionSource
}

enum ProviderGlyphKind: Hashable {
    case claudeSpark   // asterisk-like spark (Anthropic)
    case openAIKnot    // interlocked knot (OpenAI / Codex)
    case geminiStar    // four-point sparkle (Google Gemini)
    case genericBurst  // fallback starburst
}

enum DetectionSource: Hashable {
    case cliBinary(path: String)
    case configDirectory(path: String)
    case credentialsFile(path: String)
    case unknown
}
