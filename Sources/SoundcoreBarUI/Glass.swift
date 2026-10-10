import SwiftUI

public enum PanelPreferences {
    /// Whether the panel uses the clear Liquid Glass variant instead of the regular one (default).
    public static let clearGlassKey = "clearGlass"
}

/// A round glass button: Liquid Glass on macOS 26 and later, tinted with the accent colour when
/// selected; a plain filled circle on older systems. The tint is applied explicitly because the
/// stock prominent style turns grey whenever the panel is not the active window.
struct GlassCircleButton<Label: View>: View {
    let isSelected: Bool
    let diameter: CGFloat
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: action) {
            label
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .modifier(GlassCircle(isSelected: isSelected))
    }
}

private struct GlassCircle: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(
                isSelected ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
                in: .circle
            )
        } else {
            content.background(
                Circle().fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
            )
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
