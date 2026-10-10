import SwiftUI

/// Round buttons in Liquid Glass on macOS 26 and later (tinted when prominent), and regular
/// bordered buttons on older systems.
struct GlassCircleButtonStyle: ViewModifier {
    let isProminent: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            if isProminent {
                content.buttonStyle(.glassProminent).buttonBorderShape(.circle)
            } else {
                content.buttonStyle(.glass).buttonBorderShape(.circle)
            }
        } else if #available(macOS 14, *) {
            if isProminent {
                content.buttonStyle(.borderedProminent).buttonBorderShape(.circle)
            } else {
                content.buttonStyle(.bordered).buttonBorderShape(.circle)
            }
        } else if isProminent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

/// Lets neighbouring glass shapes blend and morph into each other on macOS 26 and later.
struct GlassGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
