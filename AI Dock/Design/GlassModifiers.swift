import SwiftUI

/// Reusable "liquid glass" surface treatments.
///
/// On macOS 26 we use the native `.glassEffect(_:in:)` modifier for real
/// refractive glass, then layer hand-tuned tints, sheens, strokes and shadows
/// so the surfaces read as premium even where the system material is flat.
///
/// Reference: Apple's Liquid Glass API — `.glassEffect(.regular.tint(...), in: .rect(...))`
/// is a view modifier applied *after* sizing/padding, with an optional
/// `GlassEffectContainer` to blend neighbouring shapes.
extension View {

    /// When set (e.g. for offline preview rendering, where `glassEffect` has no
    /// desktop backdrop to refract and would otherwise draw fully transparent),
    /// surfaces fall back to their opaque tint so shapes/colours are visible.
    private static var opaqueGlass: Bool {
        ProcessInfo.processInfo.environment["AIDOCK_OPAQUE_GLASS"] == "1"
    }

    /// The deep black glass body of the notch, clipped to an arbitrary shape
    /// (the edge-tab silhouette with concave cutouts).
    func dockGlassTab<S: Shape>(_ shape: S) -> some View {
        Group {
            if Self.opaqueGlass {
                // Offline preview: no desktop to refract, so skip glassEffect
                // (which renders fully clear in ImageRenderer) and use a solid
                // dark fill so shapes/rings/text are visible.
                self
                    .background(Dock.Surface.notchBody.clipShape(shape))
            } else {
                self
                    .background(Dock.Surface.notchBody.opacity(0.82).clipShape(shape))
                    .glassEffect(.regular.tint(Color.black.opacity(0.55)), in: shape)
            }
        }
        .overlay {
            LinearGradient(
                colors: [Dock.Surface.glassSheen, .clear],
                startPoint: .top, endPoint: .center
            )
            .clipShape(shape)
        }
        .overlay {
            shape.stroke(
                LinearGradient(
                    colors: [Color.white.opacity(0.30), Color.white.opacity(0.05)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
        }
        .shadow(color: .black.opacity(0.45), radius: 30, x: 0, y: 18)
    }

    /// The deep black glass body of the notch.
    func dockGlassBody(cornerRadius: CGFloat = Dock.Metric.notchRadius) -> some View {
        self
            .background(Dock.Surface.notchBody)
            .glassEffect(
                .regular.tint(Color.black.opacity(0.55)),
                in: .rect(cornerRadius: cornerRadius)
            )
            .overlay {
                // Top sheen — the specular highlight that says "glass".
                LinearGradient(
                    colors: [Dock.Surface.glassSheen, .clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .clipShape(.rect(cornerRadius: cornerRadius))
            }
            .overlay {
                // Hairline stroke = the lit glass rim.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.30),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.45), radius: 30, x: 0, y: 18)
    }

    /// Lighter glass used for the floating usage popover, clipped to the
    /// speech-bubble shape (rounded body + pointer tail).
    func dockGlassBubble<S: Shape>(_ shape: S) -> some View {
        Group {
            if Self.opaqueGlass {
                self.background(Dock.Surface.popoverBody.clipShape(shape))
            } else {
                self
                    .background(Dock.Surface.popoverBody.opacity(0.82).clipShape(shape))
                    .glassEffect(.regular.tint(Color.black.opacity(0.45)), in: shape)
            }
        }
        .overlay {
            LinearGradient(
                colors: [Dock.Surface.glassSheen, .clear],
                startPoint: .top, endPoint: .center
            )
            .clipShape(shape)
        }
        .overlay {
            shape.stroke(
                LinearGradient(
                    colors: [Color.white.opacity(0.24), Color.white.opacity(0.04)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
        }
        .shadow(color: .black.opacity(0.5), radius: 40, x: 0, y: 24)
    }

    /// Lighter glass used for the floating usage popover.
    func dockGlassPopover(cornerRadius: CGFloat = Dock.Metric.popoverRadius) -> some View {
        self
            .background(Dock.Surface.popoverBody)
            .glassEffect(
                .regular.tint(Color.black.opacity(0.45)),
                in: .rect(cornerRadius: cornerRadius)
            )
            .overlay {
                LinearGradient(
                    colors: [Dock.Surface.glassSheen, .clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .clipShape(.rect(cornerRadius: cornerRadius))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.24), Color.white.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.5), radius: 40, x: 0, y: 24)
    }
}
