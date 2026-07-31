import SwiftUI

/// Minimal ETUBU brand mark — transparent logo for chrome, DI, Live Activity.
struct EtubuBrandMark: View {
    var size: CGFloat = 22
    var showGlow: Bool = false

    var body: some View {
        Image("EtubuLogo")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .shadow(color: showGlow ? Color.cyan.opacity(0.35) : .clear, radius: showGlow ? 6 : 0)
            .accessibilityLabel("ETUBU")
    }
}
