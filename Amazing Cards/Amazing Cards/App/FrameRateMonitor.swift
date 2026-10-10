import Observation
import QuartzCore
import SwiftUI

/// Debug overlay: frames presented per second, measured with a display link.
/// Frames skipped because the main thread was busy show as a lower rate.
/// Enabled with the `-showFPS` launch argument.
@MainActor
@Observable
final class FrameRateMonitor {
    private(set) var current: Double = 0
    /// Worst half-second window over the last three seconds.
    private(set) var worstRecent: Double = 0
    private(set) var maximum: Double = 0

    private var link: CADisplayLink?
    private var windowStart: CFTimeInterval = 0
    private var frames = 0
    private var history: [(time: CFTimeInterval, fps: Double)] = []

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
        maximum = Double(UIScreen.main.maximumFramesPerSecond)
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        if windowStart == 0 { windowStart = link.timestamp }
        frames += 1
        let elapsed = link.timestamp - windowStart
        guard elapsed >= 0.5 else { return }
        let fps = Double(frames) / elapsed
        current = fps
        history.append((link.timestamp, fps))
        history.removeAll { link.timestamp - $0.time > 3 }
        worstRecent = history.map(\.fps).min() ?? fps
        windowStart = link.timestamp
        frames = 0
    }
}

struct FrameRateOverlay: View {
    @State private var monitor = FrameRateMonitor()

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(Int(monitor.current.rounded())) fps")
                .font(.system(size: 22, weight: .bold, design: .monospaced))
            Text("min \(Int(monitor.worstRecent.rounded())) / \(Int(monitor.maximum))")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(monitor.worstRecent < monitor.maximum * 0.9 ? Color.orange : Color.green)
        .padding(8)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .padding(.top, 50)
        .padding(.trailing, 8)
        .allowsHitTesting(false)
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }
}
