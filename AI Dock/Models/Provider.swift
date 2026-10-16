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

/// A provider's brand mark.
///
/// Was an enum with three hand-drawn cases; it is now an asset name, so adding a
/// provider means dropping its SVG into `Assets.xcassets` and naming it here.
/// The marks themselves come from **LobeIcons** (MIT), which is the same
/// upstream set Codenotch ships — used directly rather than extracted from it.
struct ProviderGlyphKind: Hashable {
    /// Asset catalog name, or nil for the drawn fallback.
    let assetName: String?

    static let claudeSpark = ProviderGlyphKind(assetName: "BrandClaude")
    static let openAIKnot = ProviderGlyphKind(assetName: "BrandOpenAI")
    static let geminiStar = ProviderGlyphKind(assetName: "BrandGemini")
    /// Fallback used when a provider has no mark of its own.
    static let genericBurst = ProviderGlyphKind(assetName: nil)

    static let deepSeek = ProviderGlyphKind(assetName: "BrandDeepSeek")
    static let openRouter = ProviderGlyphKind(assetName: "BrandOpenRouter")
    static let zai = ProviderGlyphKind(assetName: "BrandZhipu")
    static let qwen = ProviderGlyphKind(assetName: "BrandQwen")
    static let ollama = ProviderGlyphKind(assetName: "BrandOllama")
    static let lmStudio = ProviderGlyphKind(assetName: "BrandLMStudio")
    static let kimi = ProviderGlyphKind(assetName: "BrandKimi")
    static let minimax = ProviderGlyphKind(assetName: "BrandMinimax")
    static let grok = ProviderGlyphKind(assetName: "BrandGrok")
    static let cursor = ProviderGlyphKind(assetName: "BrandCursor")
    static let copilot = ProviderGlyphKind(assetName: "BrandCopilot")
    static let windsurf = ProviderGlyphKind(assetName: "BrandWindsurf")
    static let openCode = ProviderGlyphKind(assetName: "BrandOpenCode")
    static let qoder = ProviderGlyphKind(assetName: "BrandQoder")
    static let kilo = ProviderGlyphKind(assetName: "BrandKilo")
    static let amp = ProviderGlyphKind(assetName: "BrandAmp")
    static let devin = ProviderGlyphKind(assetName: "BrandDevin")
    static let commandCode = ProviderGlyphKind(assetName: "BrandCommandCode")
    static let mistral = ProviderGlyphKind(assetName: "BrandMistral")
    static let gemma = ProviderGlyphKind(assetName: "BrandGemma")
    static let moonshot = ProviderGlyphKind(assetName: "BrandMoonshot")
}

enum DetectionSource: Hashable {
    case cliBinary(path: String)
    case configDirectory(path: String)
    case credentialsFile(path: String)
    case unknown
}
