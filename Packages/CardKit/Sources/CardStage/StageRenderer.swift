import CoreGraphics
import Foundation
import Metal
import MetalKit
import simd

/// Pictures printed on one pack: the front, the back (defaults to the
/// front) and their masks (red = foil, green = holo, blue = matte; a
/// missing mask means full foil with the holo dial).
public struct PackSkin: Identifiable, Sendable {
    public var id: String
    public var front: CGImage
    public var back: CGImage?
    public var frontMask: CGImage?
    public var backMask: CGImage?

    public init(id: String, front: CGImage, back: CGImage? = nil, frontMask: CGImage? = nil, backMask: CGImage? = nil) {
        self.id = id
        self.front = front
        self.back = back
        self.frontMask = frontMask
        self.backMask = backMask
    }
}

/// Meshes and the wrinkle map, built off the main actor.
struct StageAssets: Sendable {
    var front: PouchMesh
    var back: PouchMesh
    var wrinkles: WrinkleNormalMap
}

/// Draws a `StageScene` into an `MTKView`: background, packs, their
/// reflection and their shadow, with the studio lighting of `Stage.metal`.
@MainActor
final class StageRenderer: NSObject, MTKViewDelegate {
    let scene: StageScene
    let device: MTLDevice
    let queue: MTLCommandQueue
    let pouchPipeline: MTLRenderPipelineState
    private let reflectionPipeline: MTLRenderPipelineState
    private let shadowPipeline: MTLRenderPipelineState
    private let backgroundPipeline: MTLRenderPipelineState
    let flakePipeline: MTLRenderPipelineState
    let spritePipeline: MTLRenderPipelineState
    let spriteAdditivePipeline: MTLRenderPipelineState
    let auraPipeline: MTLRenderPipelineState
    let depthWrite: MTLDepthStencilState
    let depthRead: MTLDepthStencilState
    let depthNone: MTLDepthStencilState
    private let sampler: MTLSamplerState
    let fallbackArt: MTLTexture
    let fallbackMask: MTLTexture

    struct GPUMesh {
        var vertices: MTLBuffer
        var indices: MTLBuffer
        var count: Int
    }
    struct Skin {
        var id: String
        var front: MTLTexture
        var back: MTLTexture
        var frontMask: MTLTexture
        var backMask: MTLTexture
    }

    struct CardTextures {
        var id: String
        var front: MTLTexture
        var back: MTLTexture
        var mask: MTLTexture
    }

    var front: GPUMesh?
    var back: GPUMesh?
    var card: GPUMesh?
    var tab: GPUMesh?
    var tabSlider: GPUMesh?
    var tabArt: MTLTexture?
    var tabMask: MTLTexture?
    var wrinkles: MTLTexture?
    var skins: [Int: Skin] = [:]
    var cards: [CardTextures] = []
    let plainCardMask: MTLTexture
    let rareCardMask: MTLTexture
    private var builtLook: (puff: Float, wrinkles: Float)?
    var assetTask: Task<Void, Never>?
    /// The two layers of light rays, like the stage's conic gradients.
    private let coarseRays = StageRenderer.rayWedges(seed: 7, minWidth: 2.2, maxWidth: 7.5, gap: 5, gapRandom: 16)
    private let fineRays = StageRenderer.rayWedges(seed: 31, minWidth: 0.5, maxWidth: 1.6, gap: 3, gapRandom: 9)
    /// Pictures uploaded ahead of a deal, by skin id.
    var readyCards: [String: CardTextures] = [:]
    private var lastFrame: CFTimeInterval?

    enum Failure: Error { case noDevice, noLibrary }

    init(scene: StageScene, device: MTLDevice, colorFormat: MTLPixelFormat, sampleCount: Int) throws {
        self.scene = scene
        self.device = device
        guard let queue = device.makeCommandQueue() else { throw Failure.noDevice }
        self.queue = queue
        let library = try device.makeDefaultLibrary(bundle: .module)

        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float3
        vertexDescriptor.attributes[1].offset = 16
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.attributes[2].format = .float2
        vertexDescriptor.attributes[2].offset = 32
        vertexDescriptor.attributes[2].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<PouchVertex>.stride

        enum Blend { case none, alpha, premultiplied, additive }
        func pipeline(_ vertex: String, _ fragment: String, blend: Blend, coverage: Bool, descriptor: MTLVertexDescriptor?) throws -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: vertex)
            d.fragmentFunction = library.makeFunction(name: fragment)
            d.vertexDescriptor = descriptor
            d.rasterSampleCount = sampleCount
            d.depthAttachmentPixelFormat = .depth32Float
            d.isAlphaToCoverageEnabled = coverage
            let c = d.colorAttachments[0]!
            c.pixelFormat = colorFormat
            c.isBlendingEnabled = blend != .none
            switch blend {
            case .none: break
            case .alpha:
                c.sourceRGBBlendFactor = .sourceAlpha
                c.destinationRGBBlendFactor = .oneMinusSourceAlpha
            case .premultiplied:
                c.sourceRGBBlendFactor = .one
                c.destinationRGBBlendFactor = .oneMinusSourceAlpha
            case .additive:
                c.sourceRGBBlendFactor = .one
                c.destinationRGBBlendFactor = .one
            }
            c.sourceAlphaBlendFactor = .one
            c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try device.makeRenderPipelineState(descriptor: d)
        }
        pouchPipeline = try pipeline("ck_stage_pouch_vertex", "ck_stage_pouch_fragment", blend: .none, coverage: true, descriptor: vertexDescriptor)
        reflectionPipeline = try pipeline("ck_stage_pouch_vertex", "ck_stage_pouch_fragment", blend: .alpha, coverage: false, descriptor: vertexDescriptor)
        shadowPipeline = try pipeline("ck_stage_sprite_vertex", "ck_stage_shadow_fragment", blend: .alpha, coverage: false, descriptor: nil)
        backgroundPipeline = try pipeline("ck_stage_background_vertex", "ck_stage_background_fragment", blend: .none, coverage: false, descriptor: nil)
        flakePipeline = try pipeline("ck_stage_flake_vertex", "ck_stage_flake_fragment", blend: .none, coverage: false, descriptor: nil)
        spritePipeline = try pipeline("ck_stage_particle_vertex", "ck_stage_particle_fragment", blend: .premultiplied, coverage: false, descriptor: nil)
        spriteAdditivePipeline = try pipeline("ck_stage_particle_vertex", "ck_stage_particle_fragment", blend: .additive, coverage: false, descriptor: nil)
        auraPipeline = try pipeline("ck_stage_aura_vertex", "ck_stage_aura_fragment", blend: .additive, coverage: false, descriptor: nil)

        func depth(_ compare: MTLCompareFunction, write: Bool) -> MTLDepthStencilState {
            let d = MTLDepthStencilDescriptor()
            d.depthCompareFunction = compare
            d.isDepthWriteEnabled = write
            return device.makeDepthStencilState(descriptor: d)!
        }
        depthWrite = depth(.less, write: true)
        depthRead = depth(.less, write: false)
        depthNone = depth(.always, write: false)

        let s = MTLSamplerDescriptor()
        s.minFilter = .linear
        s.magFilter = .linear
        s.mipFilter = .linear
        s.maxAnisotropy = 8
        s.sAddressMode = .clampToEdge
        s.tAddressMode = .clampToEdge
        sampler = device.makeSamplerState(descriptor: s)!

        fallbackArt = Self.solidTexture(device: device, rgba: [120, 130, 150, 255], srgb: true)
        fallbackMask = Self.solidTexture(device: device, rgba: [77, 25, 0, 255], srgb: false)
        plainCardMask = Self.solidTexture(device: device, rgba: [0, 0, 90, 255], srgb: false)
        rareCardMask = Self.solidTexture(device: device, rgba: [150, 200, 0, 255], srgb: false)
        super.init()
        card = gpuMesh(Self.cardMesh())
        tab = gpuMesh(Self.slabMesh(width: 0.085, height: 0.046, depth: 0.006, corner: 0.014))
        tabSlider = gpuMesh(Self.slabMesh(width: 0.034, height: 0.03, depth: 0.016, corner: 0.003))
        tabArt = Self.tabTexture(device: device)
        tabMask = Self.solidTexture(device: device, rgba: [255, 0, 20, 255], srgb: false)
        rebuildAssetsIfNeeded()
    }

    func stop() {
        assetTask?.cancel()
        assetTask = nil
    }

    // MARK: - Skins

    func setSkin(_ skin: PackSkin?, for index: Int) {
        guard let skin else { skins[index] = nil; return }
        if skins[index]?.id == skin.id { return }
        let front = texture(skin.front, srgb: true) ?? fallbackArt
        let back = skin.back.flatMap { texture($0, srgb: true) } ?? front
        let frontMask = skin.frontMask.flatMap { texture($0, srgb: false) } ?? fallbackMask
        let backMask = skin.backMask.flatMap { texture($0, srgb: false) } ?? frontMask
        skins[index] = Skin(id: skin.id, front: front, back: back, frontMask: frontMask, backMask: backMask)
    }

    /// Draws the picture into an RGBA buffer and uploads it with mipmaps.
    /// Rendered pictures come in formats the texture loader rejects, so the
    /// conversion is done here, once per picture.
    func texture(_ image: CGImage, srgb: Bool) -> MTLTexture? {
        let w = image.width, h = image.height
        guard w > 0, h > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              )
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = context.data else { return nil }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: srgb ? .rgba8Unorm_srgb : .rgba8Unorm, width: w, height: h, mipmapped: true)
        d.usage = .shaderRead
        guard let t = device.makeTexture(descriptor: d) else { return nil }
        t.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: data, bytesPerRow: w * 4)
        generateMipmaps(t)
        return t
    }

    func generateMipmaps(_ texture: MTLTexture) {
        guard let cmd = queue.makeCommandBuffer(), let blit = cmd.makeBlitCommandEncoder() else { return }
        blit.generateMipmaps(for: texture)
        blit.endEncoding()
        cmd.commit()
    }

    static func solidTexture(device: MTLDevice, rgba: [UInt8], srgb: Bool) -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: srgb ? .rgba8Unorm_srgb : .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        d.usage = .shaderRead
        let t = device.makeTexture(descriptor: d)!
        rgba.withUnsafeBytes { t.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 4) }
        return t
    }

    /// Wedges of a ray layer: random widths and gaps around the circle.
    private static func rayWedges(seed: UInt32, minWidth: Float, maxWidth: Float, gap: Float, gapRandom: Float) -> [RayWedge] {
        var gen = StageNoise.Generator(seed: seed)
        var wedges: [RayWedge] = []
        var angle = gen.next() * gapRandom
        while angle < 360 - maxWidth {
            let width = minWidth + gen.next() * (maxWidth - minWidth)
            let alpha = 0.3 + 0.7 * pow(gen.next(), 1.5)
            wedges.append(RayWedge(start: angle, width: width, alpha: alpha))
            angle += width + gap + gen.next() * (gapRandom - gap)
        }
        return wedges
    }

    // MARK: - Geometry

    private func rebuildAssetsIfNeeded() {
        let look = (puff: scene.settings.puff, wrinkles: scene.settings.wrinkles)
        if let builtLook, builtLook == look { return }
        builtLook = look
        assetTask?.cancel()
        assetTask = Task { [weak self] in
            guard let assets = await Self.buildAssets(puff: look.puff, wrinkles: look.wrinkles) else { return }
            guard !Task.isCancelled, let self else { return }
            self.upload(assets)
        }
    }

    @concurrent
    private static func buildAssets(puff: Float, wrinkles: Float) async -> StageAssets? {
        let front = PouchMesh.make(back: false, seed: 11, puff: puff, wrinkles: wrinkles)
        if Task.isCancelled { return nil }
        let back = PouchMesh.make(back: true, seed: 29, puff: puff, wrinkles: wrinkles)
        if Task.isCancelled { return nil }
        let map = WrinkleNormalMap.make()
        return StageAssets(front: front, back: back, wrinkles: map)
    }

    private func upload(_ assets: StageAssets) {
        front = gpuMesh(assets.front)
        back = gpuMesh(assets.back)
        if wrinkles == nil {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: WrinkleNormalMap.width, height: WrinkleNormalMap.height, mipmapped: true)
            d.usage = .shaderRead
            if let t = device.makeTexture(descriptor: d) {
                assets.wrinkles.rgba.withUnsafeBytes {
                    t.replace(region: MTLRegionMake2D(0, 0, WrinkleNormalMap.width, WrinkleNormalMap.height), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: WrinkleNormalMap.width * 4)
                }
                generateMipmaps(t)
                wrinkles = t
            }
        }
    }

    func gpuMesh(_ mesh: PouchMesh) -> GPUMesh? {
        guard let v = device.makeBuffer(bytes: mesh.vertices, length: mesh.vertices.count * MemoryLayout<PouchVertex>.stride, options: .storageModeShared),
              let i = device.makeBuffer(bytes: mesh.indices, length: mesh.indices.count * MemoryLayout<UInt32>.stride, options: .storageModeShared)
        else { return nil }
        return GPUMesh(vertices: v, indices: i, count: mesh.indices.count)
    }

    // MARK: - MTKViewDelegate

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        MainActor.assumeIsolated { fit(view) }
    }

    private var fittedSize: CGSize = .zero

    /// Keeps the scene's viewport in step with the view, in points.
    private func fit(_ view: MTKView) {
        #if canImport(UIKit)
        let scale = max(view.contentScaleFactor, 1)
        #else
        let scale = max(view.layer?.contentsScale ?? 1, 1)
        #endif
        var size = view.bounds.size
        if size.width < 1 || size.height < 1 {
            size = CGSize(width: view.drawableSize.width / scale, height: view.drawableSize.height / scale)
        }
        guard size.width >= 1, size.height >= 1, size != fittedSize else { return }
        fittedSize = size
        scene.resize(size)
    }

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated { render(in: view) }
    }

    private func render(in view: MTKView) {
        fit(view)
        let now = CACurrentMediaTime()
        let dt = Float(lastFrame.map { now - $0 } ?? 1 / 60)
        lastFrame = now
        rebuildAssetsIfNeeded()
        scene.advance(by: dt)
        syncCards()

        guard let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor,
              let cmd = queue.makeCommandBuffer(),
              let encoder = cmd.makeRenderCommandEncoder(descriptor: pass)
        else { return }
        let settings = scene.settings
        let night = settings.lighting == .night
        var frame = FrameUniforms(
            viewProjection: scene.camera.viewProjection,
            cameraPosition: SIMD4(scene.camera.position, 1),
            lightDirection: SIMD4(normalize(SIMD3<Float>(-2.5, 3.5, 4.5)), night ? 0.9 : 1.4),
            lightColor: night ? SIMD4(0.784, 0.831, 1.0, 1) : SIMD4(1, 1, 1, 1),
            params: SIMD4(scene.time, scene.sweep, night ? 1 : 0, PouchMetrics.floorY),
            look: SIMD4(settings.foil, settings.holo, settings.gloss, settings.shine),
            reflect: SIMD4(0.85, 0.5 * settings.reflection, 0.25 + 1.75 * settings.wrinkles, 0)
        )
        let flash: Float = scene.burstTime.map { Float(max(0, 1 - (Date.timeIntervalSinceReferenceDate - $0) / 0.6)) } ?? 0
        frame.screen = SIMD4(scene.floorLine, scene.raysLevel, scene.raysLevel, scene.dimLevel)
        frame.screen2 = SIMD4(scene.openingPose.premium ? 1 : 0, scene.viewport.x, scene.viewport.y, flash * flash)
        encoder.setFrontFacing(.counterClockwise)
        encoder.setVertexBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        encoder.setFragmentSamplerState(sampler, index: 0)

        if settings.background {
            encoder.setRenderPipelineState(backgroundPipeline)
            encoder.setDepthStencilState(depthNone)
            encoder.setCullMode(.none)
            coarseRays.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 3) }
            fineRays.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 4) }
            var counts = SIMD2<Int32>(Int32(coarseRays.count), Int32(fineRays.count))
            encoder.setFragmentBytes(&counts, length: MemoryLayout<SIMD2<Int32>>.stride, index: 5)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }

        if let front, let back, let wrinkles {
            encoder.setFragmentTexture(wrinkles, index: 2)
            // Packs.
            encoder.setRenderPipelineState(pouchPipeline)
            encoder.setDepthStencilState(depthWrite)
            encoder.setCullMode(.back)
            for (i, pose) in scene.poses.enumerated() where pose.visible {
                drawPack(encoder, index: i, model: pose.model, reflected: false, front: front, back: back)
            }
            drawOpening(encoder, front: front, back: back)
            drawEffects(encoder)
            // Reflections in the floor.
            if settings.reflection > 0 {
                encoder.setRenderPipelineState(reflectionPipeline)
                encoder.setDepthStencilState(depthRead)
                encoder.setCullMode(.front)
                let mirror = StageMath.mirror(y: PouchMetrics.floorY)
                for (i, pose) in scene.poses.enumerated() where pose.visible {
                    drawPack(encoder, index: i, model: mirror * pose.model, reflected: true, front: front, back: back)
                }
            }
        }

        if settings.shadow > 0 {
            encoder.setRenderPipelineState(shadowPipeline)
            encoder.setDepthStencilState(depthRead)
            encoder.setCullMode(.none)
            for pose in scene.poses where pose.visible && pose.shadowOpacity > 0.001 {
                var object = ObjectUniforms(model: pose.shadowModel, flags: SIMD4(0, 1, 0, pose.shadowOpacity))
                encoder.setVertexBytes(&object, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
                encoder.setFragmentBytes(&object, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            }
        }

        encoder.endEncoding()
        cmd.present(drawable)
        cmd.commit()
        if let request = scene.captureRequest, !view.framebufferOnly {
            scene.captureRequest = nil
            cmd.waitUntilCompleted()
            if let image = Self.picture(of: drawable.texture) { request(image) }
        }
    }

    /// Copies a BGRA drawable into a picture.
    private static func picture(of texture: MTLTexture) -> CGImage? {
        let w = texture.width, h = texture.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        bytes.withUnsafeMutableBytes { texture.getBytes($0.baseAddress!, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0) }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: space, bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    private func drawPack(_ encoder: MTLRenderCommandEncoder, index: Int, model: float4x4, reflected: Bool, front: GPUMesh, back: GPUMesh) {
        let skin = skins[index]
        // Front side.
        var object = ObjectUniforms(model: model, flags: SIMD4(reflected ? 1 : 0, 1, 1, 1))
        encoder.setVertexBytes(&object, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
        encoder.setFragmentBytes(&object, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
        encoder.setFragmentTexture(skin?.front ?? fallbackArt, index: 0)
        encoder.setFragmentTexture(skin?.frontMask ?? fallbackMask, index: 1)
        encoder.setVertexBuffer(front.vertices, offset: 0, index: 0)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: front.count, indexType: .uint32, indexBuffer: front.indices, indexBufferOffset: 0)
        // Back side, turned around.
        object.model = model * StageMath.rotationY(.pi)
        object.flags.y = -1
        encoder.setVertexBytes(&object, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
        encoder.setFragmentBytes(&object, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
        encoder.setFragmentTexture(skin?.back ?? fallbackArt, index: 0)
        encoder.setFragmentTexture(skin?.backMask ?? fallbackMask, index: 1)
        encoder.setVertexBuffer(back.vertices, offset: 0, index: 0)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: back.count, indexType: .uint32, indexBuffer: back.indices, indexBufferOffset: 0)
    }
}
