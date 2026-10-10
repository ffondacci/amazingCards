import SwiftUI

/// Renders a view at a fraction of its resolution and lets the compositor
/// scale it back up. Procedural backgrounds (star fields, nebulae) look the
/// same at half resolution and cost a quarter of the GPU time; the main
/// thread otherwise waits for the GPU and drops frames.
private struct RenderScaleModifier: ViewModifier {
    let scale: CGFloat

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            content
                .frame(width: proxy.size.width * scale, height: proxy.size.height * scale)
                .scaleEffect(1 / scale, anchor: .topLeading)
        }
    }
}

public extension View {
    /// Draws the view at `scale` × its size (0.5 = quarter of the pixels).
    func renderScale(_ scale: CGFloat) -> some View {
        modifier(RenderScaleModifier(scale: min(max(scale, 0.1), 1)))
    }
}
