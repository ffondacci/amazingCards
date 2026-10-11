import MetalKit
import SwiftUI

/// The booster stage as a SwiftUI view: a Metal-rendered carousel of
/// pouches with the gestures wired to the scene. Give it the scene, the
/// skins of the packs (by index) and it draws at the display rate while
/// on screen.
public struct StageView: View {
    private let scene: StageScene
    private let skins: [Int: PackSkin]
    private let capturable: Bool
    @State private var dragging = false

    /// - Parameter capturable: lets `StageScene.captureRequest` read frames back (a small cost per frame).
    public init(scene: StageScene, skins: [Int: PackSkin], capturable: Bool = false) {
        self.scene = scene
        self.skins = skins
        self.capturable = capturable
    }

    public var body: some View {
        MetalStageView(scene: scene, skins: skins, capturable: capturable)
            .contentShape(Rectangle())
            .gesture(drag)
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): scene.pointerMoved(to: point)
                case .ended: scene.pointerMoved(to: nil)
                }
            }
            .accessibilityLabel("Booster packs")
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let t = value.time.timeIntervalSinceReferenceDate
                if !dragging {
                    dragging = true
                    scene.dragBegan(at: value.startLocation, time: t)
                }
                scene.dragChanged(to: value.location, time: t)
            }
            .onEnded { value in
                dragging = false
                scene.dragEnded(at: value.location, time: value.time.timeIntervalSinceReferenceDate)
            }
    }
}

#if canImport(UIKit)
private typealias StageRepresentable = UIViewRepresentable
#else
private typealias StageRepresentable = NSViewRepresentable
#endif

/// Hosts the `MTKView` and its renderer.
private struct MetalStageView: StageRepresentable {
    let scene: StageScene
    let skins: [Int: PackSkin]
    let capturable: Bool

    @MainActor
    final class Coordinator {
        var renderer: StageRenderer?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func make(context: Context) -> MTKView {
        let view = MTKView()
        guard let device = MTLCreateSystemDefaultDevice() else { return view }
        view.device = device
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .depth32Float
        view.sampleCount = 4
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.preferredFramesPerSecond = 60
        view.framebufferOnly = !capturable
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        #if canImport(UIKit)
        view.isOpaque = scene.settings.background
        view.backgroundColor = .clear
        #else
        view.layer?.isOpaque = scene.settings.background
        #endif
        if let renderer = try? StageRenderer(scene: scene, device: device, colorFormat: view.colorPixelFormat, sampleCount: view.sampleCount) {
            context.coordinator.renderer = renderer
            view.delegate = renderer
        }
        return view
    }

    private func sync(_ view: MTKView, context: Context) {
        guard let renderer = context.coordinator.renderer else { return }
        for index in 0..<scene.settings.packs {
            renderer.setSkin(skins[index], for: index)
        }
        view.isPaused = false
    }

    private static func tearDown(_ coordinator: Coordinator) {
        coordinator.renderer?.stop()
        coordinator.renderer = nil
    }

    #if canImport(UIKit)
    func makeUIView(context: Context) -> MTKView { make(context: context) }
    func updateUIView(_ view: MTKView, context: Context) { sync(view, context: context) }
    static func dismantleUIView(_ view: MTKView, coordinator: Coordinator) {
        view.isPaused = true
        view.delegate = nil
        tearDown(coordinator)
    }
    #else
    func makeNSView(context: Context) -> MTKView { make(context: context) }
    func updateNSView(_ view: MTKView, context: Context) { sync(view, context: context) }
    static func dismantleNSView(_ view: MTKView, coordinator: Coordinator) {
        view.isPaused = true
        view.delegate = nil
        tearDown(coordinator)
    }
    #endif
}
