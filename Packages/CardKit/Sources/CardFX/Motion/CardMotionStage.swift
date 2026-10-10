import SwiftUI

/// How a `CardMotionStage` turns gestures into tilt.
public enum CardMotionInteraction: Sendable, Hashable {
    /// Drag anywhere on the card: the finger position becomes the pointer,
    /// the card tilts toward it and springs back on release.
    case drag
    /// No gesture (thumbnails, lists). Device motion still applies.
    case none
}

/// Interactive container: drag to tilt, optional gyroscope, perspective
/// rotation, dynamic shadow, and the `cardMotion` environment for shaders.
///
/// ```swift
/// CardMotionStage {
///     CardView(card: card)
/// }
/// ```
public struct CardMotionStage<Content: View>: View {
    private let interaction: CardMotionInteraction
    private let usesDeviceMotion: Bool
    private let animates: Bool
    private let maxRotation: Double
    private let liftsWhileInteracting: Bool
    private let shadowColor: Color
    private let content: Content

    @State private var tilt: CGPoint = .zero
    @State private var pointer: CGPoint?
    @State private var isInteracting = false
    @State private var size: CGSize = .zero
    @State private var deviceMotion = DeviceMotionSource()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - interaction: gesture mapping, `.drag` by default.
    ///   - usesDeviceMotion: adds the gyroscope tilt when available.
    ///   - animates: runs the clock for time-based shaders.
    ///   - maxRotation: degrees of 3D rotation at full tilt.
    ///   - liftsWhileInteracting: scales the card up slightly while touched.
    ///   - shadowColor: colour of the shadow that moves with the tilt.
    public init(
        interaction: CardMotionInteraction = .drag,
        usesDeviceMotion: Bool = true,
        animates: Bool = true,
        maxRotation: Double = 14,
        liftsWhileInteracting: Bool = true,
        shadowColor: Color = .black,
        @ViewBuilder content: () -> Content
    ) {
        self.interaction = interaction
        self.usesDeviceMotion = usesDeviceMotion
        self.animates = animates
        self.maxRotation = maxRotation
        self.liftsWhileInteracting = liftsWhileInteracting
        self.shadowColor = shadowColor
        self.content = content()
    }

    private var effectiveTilt: CGPoint {
        guard !reduceMotion else { return .zero }
        let device = usesDeviceMotion ? deviceMotion.tilt : .zero
        return CGPoint(
            x: max(-1, min(1, tilt.x + device.x)),
            y: max(-1, min(1, tilt.y + device.y))
        )
    }

    public var body: some View {
        let current = effectiveTilt
        let shadowScale = max(min(size.width, size.height) * 0.05, 4)
        content
            .cardMotion(tilt: current, pointer: pointer, isInteracting: isInteracting, animates: animates)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .cardTilt(current, maxRotation: maxRotation)
            .scaleEffect(isInteracting && liftsWhileInteracting ? 1.03 : 1)
            .shadow(
                color: shadowColor.opacity(isInteracting ? 0.45 : 0.3),
                radius: shadowScale * (isInteracting ? 1.6 : 1.1),
                x: -current.x * shadowScale,
                y: -current.y * shadowScale + shadowScale * 0.5
            )
            .gesture(dragGesture, including: interaction == .drag ? .all : .subviews)
            .onAppear { if usesDeviceMotion { deviceMotion.start() } }
            .onDisappear { deviceMotion.stop() }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard size.width > 0, size.height > 0 else { return }
                let p = CGPoint(
                    x: min(max(value.location.x / size.width, 0), 1),
                    y: min(max(value.location.y / size.height, 0), 1)
                )
                withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.85)) {
                    pointer = p
                    tilt = CGPoint(x: (p.x - 0.5) * 2, y: (p.y - 0.5) * 2)
                    isInteracting = true
                }
            }
            .onEnded { _ in
                pointer = nil
                withAnimation(.spring(response: 0.6, dampingFraction: 0.55)) {
                    tilt = .zero
                    isInteracting = false
                }
            }
    }
}
