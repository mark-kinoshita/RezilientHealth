import SwiftUI

extension EnvironmentValues {
    /// True inside glass surfaces (the Ask sheet), where opaque cards would
    /// cover the material.
    @Entry var isOnGlass = false
}

extension View {
    /// Content card background: opaque on the grouped dashboard, a light fill
    /// on glass. Glass itself is reserved for controls, per Liquid Glass guidance.
    func cardBackground(cornerRadius: CGFloat = 16) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius))
    }
}

private struct CardBackground: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.isOnGlass) private var isOnGlass

    func body(content: Content) -> some View {
        content.background(
            isOnGlass ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
            in: .rect(cornerRadius: cornerRadius)
        )
    }
}
