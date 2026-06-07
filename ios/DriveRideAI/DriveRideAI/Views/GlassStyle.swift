import SwiftUI

struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 22
    var tint: Color = .white
    var material: Material = .ultraThinMaterial

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(material)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint.opacity(0.05))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.32), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 8)
    }
}

struct GlassCapsule: ViewModifier {
    var tint: Color = .accentColor
    var filled: Bool = false

    func body(content: Content) -> some View {
        content
            .background {
                if filled {
                    Capsule(style: .continuous)
                        .fill(tint)
                } else {
                    Capsule(style: .continuous)
                        .fill(.thinMaterial)
                        .overlay(
                            Capsule(style: .continuous)
                                .fill(tint.opacity(0.08))
                        )
                }
            }
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(filled ? 0.18 : 0.35), lineWidth: 0.8)
            )
            .shadow(color: tint.opacity(filled ? 0.18 : 0.08), radius: 10, x: 0, y: 5)
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 22,
                    tint: Color = .white,
                    material: Material = .ultraThinMaterial) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius, tint: tint, material: material))
    }

    func glassCapsule(tint: Color = .accentColor,
                      filled: Bool = false) -> some View {
        modifier(GlassCapsule(tint: tint, filled: filled))
    }
}
