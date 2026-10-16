import SwiftUI

/// Real brand marks for each provider, rendered as white template vectors at
/// the centre of a progress ring (matching the reference mockups). The SVGs
/// live in Assets.xcassets as template images with vector data preserved.
struct ProviderGlyph: View {
    let kind: ProviderGlyphKind
    var size: CGFloat = 22

    var body: some View {
        Group {
            if let name = assetName {
                Image(name)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
            } else {
                Image(systemName: "sparkle")
                    .resizable()
                    .scaledToFit()
            }
        }
        .foregroundStyle(.white)
        .frame(width: size, height: size)
    }

    private var assetName: String? { kind.assetName }
}
