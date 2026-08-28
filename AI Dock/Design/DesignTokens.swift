import SwiftUI

/// Central design language for AI Dock: the "liquid glass" palette, spacing,
/// radii and motion curves that give the notch its premium Apple-2026 feel.
enum Dock {

    // MARK: - Provider accent colors (match the reference mockups)

    enum Accent {
        /// Claude — warm signal orange/red.
        static let claude = Color(red: 1.00, green: 0.36, blue: 0.18)
        /// Codex / OpenAI — fresh mint green.
        static let codex = Color(red: 0.20, green: 0.92, blue: 0.55)
        /// Third provider — electric yellow.
        static let spark = Color(red: 0.98, green: 0.92, blue: 0.20)
        /// Google Gemini — signature blue.
        static let gemini = Color(red: 0.26, green: 0.52, blue: 1.00)
        /// Neutral fallback ring.
        static let neutral = Color.white.opacity(0.55)
    }

    // MARK: - Surfaces

    enum Surface {
        /// Deep near-black body of the notch (the mockups are essentially
        /// pure black — the glass reads through a whisper of translucency).
        static let notchBody = Color.black.opacity(0.92)
        /// Hairline highlight that sells the glass edge — barely there.
        static let glassStroke = Color.white.opacity(0.07)
        /// Soft inner glow at the top of a glass surface.
        static let glassSheen = Color.white.opacity(0.05)
        /// Popover body — same deep black as the tab.
        static let popoverBody = Color.black.opacity(0.90)
        /// Full ring track behind the progress arc.
        static let ringTrack = Color.white.opacity(0.16)
    }

    // MARK: - Text

    enum Ink {
        static let primary = Color.white
        static let secondary = Color.white.opacity(0.62)
        static let tertiary = Color.white.opacity(0.45)
    }

    // MARK: - Geometry

    enum Metric {
        static let ringSize: CGFloat = 58
        static let ringStroke: CGFloat = 5
        static let glyphInset: CGFloat = 16
        static let notchWidth: CGFloat = 96
        static let notchRadius: CGFloat = 28
        static let itemSpacing: CGFloat = 14
        static let popoverRadius: CGFloat = 24
        static let barHeight: CGFloat = 7
        static let barRadius: CGFloat = 4
    }

    // MARK: - Motion

    enum Motion {
        /// Organic, slightly bouncy settle used for rings and snap-to-edge.
        static let organic = Animation.spring(duration: 0.62, bounce: 0.32)
        /// Gentle ease for hover / reveal transitions.
        static let gentle = Animation.easeInOut(duration: 0.28)
        /// Slow ambient breathing for idle glow.
        static let breathe = Animation.easeInOut(duration: 3.2).repeatForever(autoreverses: true)
    }
}
