import CardCore
import CardFX
import CardUI
import SwiftUI

/// Horizontal, paging carousel of sealed packs. The centred pack is raised
/// and full size, the others recede; a soft shadow floats under each one.
/// Tap the centred pack to open it.
public struct PackCarouselView: View {
    public var designs: [PackDesign]
    @Binding public var selection: Int
    /// Called with the index of the centred pack and its frame on screen
    /// (global coordinates), to hand to `PackOpeningView(arrivesFrom:)`.
    public var onOpen: (Int, CGRect) -> Void

    @State private var scrolledID: Int?
    @State private var frames: [Int: CGRect] = [:]

    public init(
        designs: [PackDesign],
        selection: Binding<Int>,
        onOpen: @escaping (Int, CGRect) -> Void
    ) {
        self.designs = designs
        self._selection = selection
        self.onOpen = onOpen
    }

    public var body: some View {
        GeometryReader { proxy in
            let packWidth = min(proxy.size.width * 0.5, proxy.size.height * 0.6 * PackDesign.aspectRatio)
            let side = (proxy.size.width - packWidth) / 2
            ScrollView(.horizontal) {
                LazyHStack(alignment: .center, spacing: packWidth * 0.12) {
                    ForEach(Array(designs.enumerated()), id: \.offset) { index, design in
                        VStack(spacing: packWidth * 0.08) {
                            BoosterPackView(design: design)
                                .frame(width: packWidth)
                                .cardMotionIdle(animates: false)
                                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames[index] = $0 }
                                .shadow(color: .black.opacity(0.35), radius: packWidth * 0.06, y: packWidth * 0.04)
                            Ellipse()
                                .fill(.black.opacity(0.35))
                                .frame(width: packWidth * 0.7, height: packWidth * 0.12)
                                .blur(radius: packWidth * 0.04)
                        }
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 0.84)
                                .offset(y: phase.isIdentity ? 0 : packWidth * 0.12)
                                .opacity(phase.isIdentity ? 1 : 0.75)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if scrolledID == index {
                                onOpen(index, frames[index] ?? .zero)
                            } else {
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { scrolledID = index }
                            }
                        }
                        .accessibilityLabel("\(design.title) pack")
                        .accessibilityAddTraits(.isButton)
                    }
                }
                .scrollTargetLayout()
                .frame(height: proxy.size.height)
            }
            .contentMargins(.horizontal, side, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $scrolledID, anchor: .center)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
        .onAppear { scrolledID = selection }
        .onChange(of: scrolledID) { _, newValue in
            if let newValue { selection = newValue }
        }
        .onChange(of: selection) { _, newValue in
            if scrolledID != newValue { scrolledID = newValue }
        }
    }
}
