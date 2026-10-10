import QuartzCore
import SwiftUI

/// 3D rotation around the centre with perspective, animatable. Rotation X
/// tips the card forward/backward, rotation Y turns it left/right.
public struct TiltTransform: GeometryEffect {
    public var rotationX: Double
    public var rotationY: Double
    /// Perspective strength relative to the larger side (bigger = flatter).
    public var perspectiveDistance: Double

    public init(rotationX: Double, rotationY: Double, perspectiveDistance: Double = 2.6) {
        self.rotationX = rotationX
        self.rotationY = rotationY
        self.perspectiveDistance = perspectiveDistance
    }

    public var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(rotationX, rotationY) }
        set {
            rotationX = newValue.first
            rotationY = newValue.second
        }
    }

    public func effectValue(size: CGSize) -> ProjectionTransform {
        let longest = max(size.width, size.height, 1)
        var transform = CATransform3DIdentity
        transform.m34 = -1 / (longest * perspectiveDistance)
        transform = CATransform3DTranslate(transform, size.width / 2, size.height / 2, 0)
        transform = CATransform3DRotate(transform, rotationX * .pi / 180, 1, 0, 0)
        transform = CATransform3DRotate(transform, rotationY * .pi / 180, 0, 1, 0)
        transform = CATransform3DTranslate(transform, -size.width / 2, -size.height / 2, 0)
        return ProjectionTransform(transform)
    }
}

public extension View {
    /// Rotates the view in 3D according to a −1…1 tilt. The finger side dips
    /// away, like pressing on the corner of a real card.
    func cardTilt(_ tilt: CGPoint, maxRotation: Double = 14) -> some View {
        modifier(TiltTransform(rotationX: -tilt.y * maxRotation, rotationY: tilt.x * maxRotation))
    }
}
