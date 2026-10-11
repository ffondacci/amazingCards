import CoreGraphics
import Foundation
import Metal
import MetalKit
import simd

/// The pack being opened, its cards, and everything flying around them.
extension StageRenderer {
    /// Rounded rectangle of a card, 0.8 wide, as a fan of triangles.
    static func cardMesh(aspect: Float = 0.716) -> PouchMesh {
        let w: Float = 0.8, h = w / aspect, r: Float = 0.042
        var outline: [SIMD2<Float>] = []
        let corners: [(SIMD2<Float>, Float)] = [([w / 2 - r, h / 2 - r], 0), ([-w / 2 + r, h / 2 - r], .pi / 2), ([-w / 2 + r, -h / 2 + r], .pi), ([w / 2 - r, -h / 2 + r], 3 * .pi / 2)]
        for (center, start) in corners {
            for k in 0...6 {
                let a = start + Float(k) / 6 * (.pi / 2)
                outline.append(center + SIMD2(cos(a), sin(a)) * r)
            }
        }
        var vertices = [PouchVertex(position: [0, 0, 0], normal: [0, 0, 1], uv: [0.5, 0.5])]
        for p in outline {
            vertices.append(PouchVertex(position: [p.x, p.y, 0], normal: [0, 0, 1], uv: [p.x / w + 0.5, p.y / h + 0.5]))
        }
        var indices: [UInt32] = []
        let n = UInt32(outline.count)
        for i in 0..<n {
            indices += [0, 1 + i, 1 + (i + 1) % n]
        }
        return PouchMesh(vertices: vertices, indices: indices)
    }

    /// Uploads the pictures of the cards being dealt, and one of the
    /// prepared ones per idle frame so the deal itself costs nothing.
    func syncCards() {
        let wanted = scene.dealtCards
        if wanted.isEmpty {
            cards = []
            if let next = scene.preparedCards.first(where: { readyCards[$0.id] == nil }) {
                readyCards[next.id] = upload(next, rare: false)
            }
            let keep = Set(scene.preparedCards.map(\.id))
            readyCards = readyCards.filter { keep.contains($0.key) }
            return
        }
        if wanted.map(\.id) == cards.map(\.id) { return }
        let last = wanted.count - 1
        cards = wanted.enumerated().map { i, skin in
            if let existing = cards.first(where: { $0.id == skin.id }) { return existing }
            let rare = i == last && scene.settings.rareLast
            if var ready = readyCards[skin.id] {
                if skin.mask == nil { ready.mask = rare ? rareCardMask : plainCardMask }
                return ready
            }
            return upload(skin, rare: rare)
        }
    }

    func upload(_ skin: CardSkin, rare: Bool) -> CardTextures {
        let front = texture(skin.front, srgb: true) ?? fallbackArt
        let back = texture(skin.back, srgb: true) ?? fallbackArt
        let mask = skin.mask.flatMap { texture($0, srgb: false) } ?? (rare ? rareCardMask : plainCardMask)
        return CardTextures(id: skin.id, front: front, back: back, mask: mask)
    }


    func setDials(_ object: inout ObjectUniforms, _ d: PieceDials) {
        object.tear = [d.tearV, d.tearSide, d.cutP, d.inside]
        object.cut = [d.lineMode, d.cutDir, d.perf, d.heat]
        object.glow = [d.tipGlow, d.dissolve, d.innerGlow, d.guide]
        object.peel = [d.peel, d.peelDir, d.peelAmt, d.fly]
        object.mouth = [d.mouth, d.mouthK, 0, 0]
    }

    /// The pack being opened: its body, its strip and the cards.
    func drawOpening(_ encoder: MTLRenderCommandEncoder, front: GPUMesh, back: GPUMesh) {
        let pose = scene.openingPose
        guard pose.visible else { return }
        let skin = skins[scene.opening.pack]
        encoder.setRenderPipelineState(pouchPipeline)
        encoder.setDepthStencilState(depthWrite)
        encoder.setCullMode(.none)
        func piece(_ model: float4x4, _ dials: PieceDials) {
            for (mesh, isBack) in [(front, false), (back, true)] {
                var object = ObjectUniforms(model: isBack ? model * StageMath.rotationY(.pi) : model, flags: SIMD4(0, isBack ? -1 : 1, 1, 1))
                setDials(&object, dials)
                encoder.setVertexBytes(&object, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
                encoder.setFragmentBytes(&object, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
                encoder.setFragmentTexture((isBack ? skin?.back : skin?.front) ?? fallbackArt, index: 0)
                encoder.setFragmentTexture((isBack ? skin?.backMask : skin?.frontMask) ?? fallbackMask, index: 1)
                encoder.setVertexBuffer(mesh.vertices, offset: 0, index: 0)
                encoder.drawIndexedPrimitives(type: .triangle, indexCount: mesh.count, indexType: .uint32, indexBuffer: mesh.indices, indexBufferOffset: 0)
            }
        }
        if pose.bodyVisible { piece(pose.bodyModel, pose.body) }
        if pose.stripVisible { piece(pose.stripModel, pose.strip) }

        // Cards, back to front, over the aura of the rare one.
        guard let card, !pose.cards.isEmpty else { return }
        drawAura(encoder, pose: pose)
        encoder.setRenderPipelineState(pouchPipeline)
        encoder.setDepthStencilState(depthRead)
        encoder.setCullMode(.back)
        encoder.setVertexBuffer(card.vertices, offset: 0, index: 0)
        let night = scene.settings.lighting == .night
        for (i, draw) in pose.cards.enumerated().sorted(by: { $0.element.order < $1.element.order }) {
            guard i < cards.count else { continue }
            let textures = cards[i]
            for isBack in [false, true] {
                let offset = StageMath.translation([0, 0, isBack ? -0.0006 : 0.0006])
                var object = ObjectUniforms(model: draw.model * offset * (isBack ? StageMath.rotationY(.pi) : matrix_identity_float4x4), flags: SIMD4(0, 1, 0, 1))
                object.mouth = [0, 1, 1, draw.emissive + (night ? 0 : 0)]
                encoder.setVertexBytes(&object, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
                encoder.setFragmentBytes(&object, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
                encoder.setFragmentTexture(isBack ? textures.back : textures.front, index: 0)
                encoder.setFragmentTexture(isBack ? plainCardMask : textures.mask, index: 1)
                encoder.drawIndexedPrimitives(type: .triangle, indexCount: card.count, indexType: .uint32, indexBuffer: card.indices, indexBufferOffset: 0)
            }
        }
    }

    struct FlakeInstance {
        var model: float4x4
        var color: SIMD4<Float>
    }
    struct SpriteInstance {
        var position: SIMD4<Float>
        var color: SIMD4<Float>
        var extra: SIMD4<Float>
    }

    /// Flakes, sparks, smoke, and the aura of the rare card.
    func drawEffects(_ encoder: MTLRenderCommandEncoder) {
        let particles = scene.particles
        let night = scene.settings.lighting == .night
        // Flakes: solid, lit, in chunks small enough for the command buffer.
        var flakes: [FlakeInstance] = []
        flakes.reserveCapacity(StageParticles.flakeCount)
        for f in particles.flakes where f.life > 0 {
            let size = StageParticles.scale(of: f)
            let model = StageMath.translation(f.position) * float4x4(f.rotation) * StageMath.scale(SIMD3(repeating: size))
            flakes.append(FlakeInstance(model: model, color: SIMD4(f.color, 1)))
        }
        if !flakes.isEmpty {
            encoder.setRenderPipelineState(flakePipeline)
            encoder.setDepthStencilState(depthWrite)
            encoder.setCullMode(.none)
            for chunk in stride(from: 0, to: flakes.count, by: 48) {
                let slice = Array(flakes[chunk..<min(chunk + 48, flakes.count)])
                slice.withUnsafeBytes { encoder.setVertexBytes($0.baseAddress!, length: $0.count, index: 3) }
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: slice.count)
            }
        }
        // Sparks and smoke: billboards over everything, no depth write.
        var sprites: [SpriteInstance] = []
        sprites.reserveCapacity(StageParticles.sparkCount + StageParticles.puffCount)
        let smokeColor: SIMD3<Float> = night ? [0.788, 0.839, 0.902] : [0.553, 0.557, 0.592]
        for q in particles.puffs where q.life > 0 {
            let look = StageParticles.look(of: q)
            sprites.append(SpriteInstance(position: SIMD4(q.position, look.size), color: SIMD4(smokeColor, look.opacity), extra: [q.angle, 1, 0, 0]))
        }
        for k in particles.sparks where k.life > 0 {
            sprites.append(SpriteInstance(position: SIMD4(k.position, 0.11), color: SIMD4(k.color, StageParticles.alpha(of: k)), extra: [0, 0, 0, 0]))
        }
        if !sprites.isEmpty {
            encoder.setRenderPipelineState(night ? spriteAdditivePipeline : spritePipeline)
            encoder.setDepthStencilState(depthRead)
            encoder.setCullMode(.none)
            for chunk in stride(from: 0, to: sprites.count, by: 80) {
                let slice = Array(sprites[chunk..<min(chunk + 80, sprites.count)])
                slice.withUnsafeBytes { encoder.setVertexBytes($0.baseAddress!, length: $0.count, index: 3) }
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: slice.count)
            }
        }
    }

    /// Glow and light rays behind the rare card, added to the picture.
    func drawAura(_ encoder: MTLRenderCommandEncoder, pose: OpeningPose) {
        guard pose.auraOpacity > 0.01, let last = pose.cards.last else { return }
        encoder.setRenderPipelineState(auraPipeline)
        encoder.setDepthStencilState(depthNone)
        encoder.setCullMode(.none)
        let cardW = StageScene.cardWidth, cardH = scene.cardHeight
        let pulse = 1 + 0.05 * sin(scene.time * 3.2) + 0.45 * pose.auraPulse
        let base = last.model
        var glow = ObjectUniforms(model: base * StageMath.translation([0, 0, -0.03]) * StageMath.scale([cardW * 2.4 * pulse, cardH * 2 * pulse, 1]), flags: SIMD4(0, 1, 0, min(1, 0.8 * pose.auraOpacity + 0.4 * pose.auraPulse)))
        encoder.setVertexBytes(&glow, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
        encoder.setFragmentBytes(&glow, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        let raySize = cardH * 3 * pulse
        var rays = ObjectUniforms(model: base * StageMath.translation([0, 0, -0.04]) * StageMath.rotationZ(0.05 * sin(scene.time * 0.3)) * StageMath.scale([raySize, raySize, 1]), flags: SIMD4(0, 1, 1, 0.55 * pose.auraOpacity))
        encoder.setVertexBytes(&rays, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
        encoder.setFragmentBytes(&rays, length: MemoryLayout<ObjectUniforms>.stride, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    }

}
