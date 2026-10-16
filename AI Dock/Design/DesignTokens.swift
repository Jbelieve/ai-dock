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
        /// Z.ai / GLM — deep indigo.
        static let zai = Color(red: 0.42, green: 0.40, blue: 0.98)
        /// OpenCode — slate teal.
        static let opencode = Color(red: 0.30, green: 0.78, blue: 0.82)
        /// Qwen / Bailian — violet.
        static let qwen = Color(red: 0.65, green: 0.40, blue: 0.98)
        /// DeepSeek — signature blue.
        static let deepseek = Color(red: 0.29, green: 0.49, blue: 0.98)
        /// OpenRouter — muted slate.
        static let openrouter = Color(red: 0.55, green: 0.60, blue: 0.70)
        /// Neutral fallback ring.
        static let neutral = Color.white.opacity(0.55)
    }

    // MARK: - Severity ramp

    /// The continuous colour ramp.
    ///
    /// Codenotch's rule, from its own release notes: *"The colour blends
    /// continuously from ample to critical across the full range, turning yellow
    /// at the watch limit below."* AI Dock previously jumped between three flat
    /// colours, which makes a ring at 79% look identical to one at 5%.
    enum Ramp {
        /// Comfortable.
        static let ample = Color(red: 0.20, green: 0.92, blue: 0.55)
        /// The watch point.
        static let watch = Color(red: 0.98, green: 0.78, blue: 0.20)
        /// Spent.
        static let critical = Color(red: 1.00, green: 0.30, blue: 0.24)

        /// Interpolate ample → watch → critical. `watch` is the fraction at which
        /// the colour turns yellow (the user's watch threshold).
        static func color(for fraction: Double, watch watchPoint: Double = 0.8) -> Color {
            let t = min(max(fraction, 0), 1)
            let turn = min(max(watchPoint, 0.05), 0.95)
            if t <= turn {
                return blend(ample, self.watch, t / turn)
            }
            return blend(self.watch, critical, (t - turn) / (1 - turn))
        }

        /// Blend two colours in sRGB, which is what the source palette is in.
        private static func blend(_ a: Color, _ b: Color, _ t: Double) -> Color {
            let f = min(max(t, 0), 1)
            guard let na = NSColor(a).usingColorSpace(.sRGB),
                  let nb = NSColor(b).usingColorSpace(.sRGB) else { return b }
            return Color(
                red:   na.redComponent   + (nb.redComponent   - na.redComponent)   * f,
                green: na.greenComponent + (nb.greenComponent - na.greenComponent) * f,
                blue:  na.blueComponent  + (nb.blueComponent  - na.blueComponent)  * f)
        }
    }

    // MARK: - Surfaces

    enum Surface {
        /// Deep smoked-obsidian glass body of the notch — translucent enough for
        /// macOS `.glassEffect` to refract the desktop, rich enough for contrast.
        static let notchBody = Color(red: 0.04, green: 0.04, blue: 0.07).opacity(0.68)
        /// Opaque fallback base color for offline preview rendering.
        static let notchOpaqueBase = Color(red: 0.05, green: 0.06, blue: 0.09)
        /// Hairline highlight that sells the lit glass edge.
        static let glassStroke = Color.white.opacity(0.18)
        /// Soft inner specular glow at the top of a glass surface.
        static let glassSheen = Color.white.opacity(0.14)
        /// Popover body — smoked crystal glass.
        static let popoverBody = Color(red: 0.05, green: 0.06, blue: 0.10).opacity(0.64)
        /// Inner elevated glass card fill.
        static let cardFill = Color.white.opacity(0.055)
        /// Inner recessed glass well fill.
        static let wellFill = Color.black.opacity(0.32)
        /// Full ring track behind the progress arc.
        static let ringTrack = Color.white.opacity(0.12)
    }

    // MARK: - Text

    enum Ink {
        static let primary = Color.white.opacity(0.96)
        static let secondary = Color.white.opacity(0.68)
        static let tertiary = Color.white.opacity(0.44)
    }

    // MARK: - Geometry

    enum Metric {
        static let ringSize: CGFloat = 58
        static let ringStroke: CGFloat = 5.5
        static let glyphInset: CGFloat = 16
        static let notchWidth: CGFloat = 96
        static let notchRadius: CGFloat = 28
        static let itemSpacing: CGFloat = 14
        static let popoverRadius: CGFloat = 26
        static let cardRadius: CGFloat = 14
        static let barHeight: CGFloat = 5.5
        static let barRadius: CGFloat = 3
    }

    // MARK: - Motion

    enum Motion {
        /// Silky, slightly bouncy spring used for rings, bars, and snap-to-edge.
        static let organic = Animation.spring(response: 0.52, dampingFraction: 0.74, blendDuration: 0.15)
        /// Crisp micro-interaction spring for toggles, pills, and hover states.
        static let snappy = Animation.spring(response: 0.30, dampingFraction: 0.78, blendDuration: 0.1)
        /// Fluid morphing spring when gliding the popover from ring to ring.
        static let morph = Animation.spring(response: 0.38, dampingFraction: 0.82, blendDuration: 0.12)
        /// Gentle ease for subtle opacity / reveal transitions.
        static let gentle = Animation.spring(response: 0.34, dampingFraction: 0.84)
        /// Slow ambient breathing for idle glow and live indicators.
        static let breathe = Animation.easeInOut(duration: 2.6).repeatForever(autoreverses: true)

        /// Staggered spring for cascading list/chart items.
        static func stagger(_ index: Int, baseDelay: Double = 0.025) -> Animation {
            Animation.spring(response: 0.45, dampingFraction: 0.78)
                .delay(Double(index) * baseDelay)
        }
    }
}
