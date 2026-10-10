import CoreGraphics
import Foundation
import Observation
#if os(iOS)
import CoreMotion
#endif

/// Gyroscope-driven tilt. Attitude is measured relative to the pose the
/// device had when `start()` was called, low-pass filtered, clamped to −1…1.
///
/// Updates are delivered on the main queue, so the observable state is
/// mutated on the main actor without hopping. Unavailable in the simulator
/// (`isAvailable` is false) and silently inert there.
@MainActor
@Observable
public final class DeviceMotionSource {
    /// Filtered tilt in −1…1.
    public private(set) var tilt: CGPoint = .zero
    public private(set) var isRunning = false

    /// Angle (radians) that maps to a full tilt of 1.
    public var fullTiltAngle: Double = 0.35
    /// 0…1, higher = smoother but laggier.
    public var smoothing: Double = 0.75

    #if os(iOS)
    private let manager = CMMotionManager()
    private var reference: (roll: Double, pitch: Double)?
    public var isAvailable: Bool { manager.isDeviceMotionAvailable }
    #else
    public var isAvailable: Bool { false }
    #endif

    public init() {}

    public func start() {
        #if os(iOS)
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        reference = nil
        isRunning = true
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let roll = motion.attitude.roll
            let pitch = motion.attitude.pitch
            // Delivered on the main queue: assuming main-actor isolation is sound.
            MainActor.assumeIsolated {
                self?.ingest(roll: roll, pitch: pitch)
            }
        }
        #endif
    }

    public func stop() {
        #if os(iOS)
        manager.stopDeviceMotionUpdates()
        reference = nil
        #endif
        isRunning = false
        tilt = .zero
    }

    /// Re-centres the neutral pose on the current attitude.
    public func recenter() {
        #if os(iOS)
        reference = nil
        #endif
    }

    #if os(iOS)
    private func ingest(roll: Double, pitch: Double) {
        guard let reference else {
            reference = (roll, pitch)
            return
        }
        let x = max(-1, min(1, (roll - reference.roll) / fullTiltAngle))
        let y = max(-1, min(1, (pitch - reference.pitch) / fullTiltAngle))
        let keep = smoothing
        tilt = CGPoint(
            x: tilt.x * keep + x * (1 - keep),
            y: tilt.y * keep + y * (1 - keep)
        )
    }
    #endif
}
