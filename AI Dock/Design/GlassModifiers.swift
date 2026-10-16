import SwiftUI

/// Reusable "liquid glass" surface treatments.
///
/// On macOS 26 we use the native `.glassEffect(_:in:)` modifier for real
/// refractive glass, then layer hand-tuned caustic tints, diagonal specular
/// sheens, dual-rim strokes and multi-stage shadows so every surface reads as
/// physical, multi-layered crystal glass.
extension View {

    /// When set (e.g. for offline preview rendering, where `glassEffect` has no
    /// desktop backdrop to refract and would otherwise draw fully transparent),
    /// surfaces fall back to a rich simulated frosted-glass gradient.
    private static var opaqueGlass: Bool {
        ProcessInfo.processInfo.environment["AIDOCK_OPAQUE_GLASS"] == "1"
    }

    /// Simulated frosted-glass base gradient used behind glass surfaces.
    private static func glassBaseGradient(opacity: Double) -> LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.11, green: 0.13, blue: 0.18).opacity(opacity),
                Color(red: 0.05, green: 0.06, blue: 0.10).opacity(opacity * 1.04),
                Color(red: 0.03, green: 0.04, blue: 0.07).opacity(opacity * 1.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// The deep liquid-glass body of the notch, clipped to an arbitrary shape
    /// (the edge-tab silhouette with concave cutouts).
    func dockGlassTab<S: Shape, R: Shape>(
        _ shape: S,
        rimShape: R,
        accentTint: Color? = nil
    ) -> some View {
        Group {
            if Self.opaqueGlass {
                self
                    .background(Self.glassBaseGradient(opacity: 0.90).clipShape(shape))
            } else {
                self
                    .background(Self.glassBaseGradient(opacity: 0.62).clipShape(shape))
                    .glassEffect(
                        .regular.tint(Color(red: 0.04, green: 0.05, blue: 0.08).opacity(0.52)),
                        in: shape
                    )
            }
        }
        // Subtle ambient caustic bleed from the active provider
        .overlay {
            if let accentTint {
                RadialGradient(
                    colors: [accentTint.opacity(0.16), .clear],
                    center: .leading,
                    startRadius: 4,
                    endRadius: 140
                )
                .clipShape(shape)
                .allowsHitTesting(false)
            }
        }
        // Top-to-center diagonal specular sheen
        .overlay {
            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(0.16), location: 0.0),
                    .init(color: Color.white.opacity(0.05), location: 0.28),
                    .init(color: .clear, location: 0.62)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(shape)
            .allowsHitTesting(false)
        }
        // Inner vertical glass edge highlight on the free outer contour only
        .overlay {
            rimShape.stroke(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.30), location: 0.0),
                        .init(color: (accentTint ?? .white).opacity(0.20), location: 0.45),
                        .init(color: Color.white.opacity(0.06), location: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
            )
            .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.50), radius: 28, x: 0, y: 16)
        .shadow(color: .black.opacity(0.28), radius: 6, x: 0, y: 3)
    }

    func dockGlassTab<S: Shape>(_ shape: S, accentTint: Color? = nil) -> some View {
        dockGlassTab(shape, rimShape: shape, accentTint: accentTint)
    }

    /// The deep black glass body of the notch (rectangular variant).
    func dockGlassBody(cornerRadius: CGFloat = Dock.Metric.notchRadius) -> some View {
        dockGlassTab(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Lighter, refractive crystal glass used for the floating usage popover,
    /// clipped to the unified speech-bubble shape.
    func dockGlassBubble<S: Shape>(_ shape: S, accentTint: Color? = nil) -> some View {
        Group {
            if Self.opaqueGlass {
                self
                    .background(Self.glassBaseGradient(opacity: 0.88).clipShape(shape))
            } else {
                self
                    .background(Self.glassBaseGradient(opacity: 0.56).clipShape(shape))
                    .glassEffect(
                        .regular.tint(Color(red: 0.05, green: 0.06, blue: 0.10).opacity(0.46)),
                        in: shape
                    )
            }
        }
        // Ambient provider aurora glow in the top-left of the bubble
        .overlay {
            if let accentTint {
                ZStack {
                    RadialGradient(
                        colors: [accentTint.opacity(0.20), accentTint.opacity(0.04), .clear],
                        center: .topLeading,
                        startRadius: 2,
                        endRadius: 210
                    )
                    RadialGradient(
                        colors: [Color.white.opacity(0.05), .clear],
                        center: .bottomTrailing,
                        startRadius: 10,
                        endRadius: 180
                    )
                }
                .clipShape(shape)
                .allowsHitTesting(false)
            }
        }
        // Specular top sheen
        .overlay {
            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(0.18), location: 0.0),
                    .init(color: Color.white.opacity(0.04), location: 0.30),
                    .init(color: .clear, location: 0.58)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(shape)
            .allowsHitTesting(false)
        }
        // Crisp refractive rim around the entire unified bubble + tail contour
        .overlay {
            shape.stroke(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.36), location: 0.0),
                        .init(color: (accentTint ?? .white).opacity(0.22), location: 0.35),
                        .init(color: Color.white.opacity(0.10), location: 0.75),
                        .init(color: Color.white.opacity(0.05), location: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.2
            )
            .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.52), radius: 34, x: 0, y: 20)
        .shadow(color: (accentTint ?? .black).opacity(0.12), radius: 18, x: 0, y: 6)
    }

    /// Lighter glass used for a rectangular floating usage popover.
    func dockGlassPopover(cornerRadius: CGFloat = Dock.Metric.popoverRadius) -> some View {
        dockGlassBubble(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Elevated inner glass card used inside the popover and Settings window.
    func dockGlassCard(
        cornerRadius: CGFloat = Dock.Metric.cardRadius,
        tint: Color? = nil,
        isHovered: Bool = false
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background {
                ZStack {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isHovered ? 0.095 : 0.068),
                                Color.white.opacity(isHovered ? 0.050 : 0.032)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    if let tint {
                        RadialGradient(
                            colors: [tint.opacity(isHovered ? 0.14 : 0.08), .clear],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 180
                        )
                        .clipShape(shape)
                    }
                }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(isHovered ? 0.26 : 0.16), location: 0.0),
                            .init(color: (tint ?? .white).opacity(isHovered ? 0.14 : 0.07), location: 0.5),
                            .init(color: Color.white.opacity(0.03), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 5)
    }

    /// Recessed dark glass well used for segmented pickers, sliders and tracks.
    func dockGlassWell(cornerRadius: CGFloat = 11) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.46),
                        Color.black.opacity(0.28)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: shape
            )
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.45),
                            Color.white.opacity(0.10)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
            }
    }
}
