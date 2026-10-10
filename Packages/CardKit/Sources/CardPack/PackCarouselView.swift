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
    /// Namespace shared with `PackOpeningView.packTransition`; the pack at
    /// `selection` is matched under the id `PackCarouselView.packID(index)`.
    public var packNamespace: Namespace.ID?
    public var onOpen: (Int) -> Void

    @State private var scrolledID: Int?

    public init(
        designs: [PackDesign],
        selection: Binding<Int>,
        packNamespace: Namespace.ID? = nil,
        onOpen: @escaping (Int) -> Void
    ) {
        self.designs = designs
        self._selection = selection
        self.packNamespace = packNamespace
        self.onOpen = onOpen
    }

    /// Matched-geometry id of the pack at an index.
    public static func packID(_ index: Int) -> AnyHashable { "pack-\(index)" }

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
                                .modifier(MatchedSource(id: Self.packID(index), namespace: packNamespace))
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
                                onOpen(index)
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

private struct MatchedSource: ViewModifier {
    let id: AnyHashable
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: id, in: namespace, isSource: true)
        } else {
            content
        }
    }
}
