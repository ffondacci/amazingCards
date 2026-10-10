import AVFoundation
import Observation
import os

/// Procedural sounds of a pack opening: a crinkle when the wrapper is
/// touched, tearing that follows the finger, a whoosh when the strip flies.
/// No audio files: shaped noise synthesized in the audio render callback.
///
/// Uses the ambient session category, so it respects the silent switch and
/// mixes with whatever is playing.
@MainActor
@Observable
public final class PackSoundscape {
    public var isEnabled = true
    public private(set) var isRunning = false

    private let engine = AVAudioEngine()
    private let synth = PackSoundSynth()
    private var sourceNode: AVAudioSourceNode?

    public init() {}

    /// Activates the audio session off the main actor (activation can block
    /// for tens of milliseconds), then starts the engine.
    public func start() async {
        guard !isRunning, isEnabled else { return }
        await Self.activateSession()
        guard !isRunning, isEnabled else { return }
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        guard sampleRate > 0, let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        synth.setSampleRate(Float(sampleRate))
        let node = Self.makeSourceNode(format: format, synth: synth)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.55
        do {
            try engine.start()
            sourceNode = node
            isRunning = true
        } catch {
            engine.detach(node)
        }
    }

    @concurrent
    nonisolated private static func activateSession() async {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
        #endif
    }

    /// Built outside the main actor so the render block is not inferred as
    /// main-actor isolated: it runs on the real-time audio thread.
    nonisolated private static func makeSourceNode(format: AVAudioFormat, synth: PackSoundSynth) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            synth.render(into: audioBufferList, frames: Int(frameCount))
            return noErr
        }
    }

    public func stop() {
        guard isRunning else { return }
        engine.stop()
        if let sourceNode { engine.detach(sourceNode) }
        sourceNode = nil
        isRunning = false
    }

    /// Short crackle of a wrapper being pressed or grabbed.
    public func crinkle(strength: Double = 1) {
        synth.trigger(.crinkle(Float(strength)))
    }

    /// Continuous tearing; `speed` 0…1 drives loudness and brightness.
    /// Call with 0 when the finger stops.
    public func tearing(speed: Double) {
        synth.setTearSpeed(Float(min(max(speed, 0), 1)))
    }

    /// Filtered noise sweep for something flying away.
    public func whoosh() {
        synth.trigger(.whoosh)
    }
}

/// Real-time safe synthesizer: parameters cross threads behind an unfair
/// lock held for a few instructions; the DSP state belongs to the audio
/// thread and only ever changes inside `render`.
final class PackSoundSynth: Sendable {
    enum Trigger {
        case crinkle(Float)
        case whoosh
    }

    private struct Params {
        var crinkleStrength: Float = 0
        var whooshPending = false
        var tearSpeed: Float = 0
        var sampleRate: Float = 48000
    }

    private struct DSP {
        var rng: UInt32 = 0x9E37_79B9
        var crinkleEnv: Float = 0
        var crinkleTimer: Float = 0
        var crinkleStrength: Float = 0
        var crinkleLP: Float = 0
        var tearLevel: Float = 0
        var tearLP: Float = 0
        var tearSlowLP: Float = 0
        var crackle: Float = 1
        var crackleCounter: Int = 0
        var whooshEnv: Float = 0
        var whooshTime: Float = -1
        var whooshLP: Float = 0
        var crinkleBand: Float = 0
        var masterLP: Float = 0
        /// Reused output buffer: the lock's closure cannot capture the
        /// caller's pointer, so samples are produced here and copied out.
        var scratch: [Float] = []
    }

    private let params = OSAllocatedUnfairLock(initialState: Params())
    private let dsp = OSAllocatedUnfairLock(initialState: DSP())

    func setSampleRate(_ rate: Float) {
        params.withLock { $0.sampleRate = rate }
    }

    func trigger(_ trigger: Trigger) {
        params.withLock {
            switch trigger {
            case .crinkle(let strength): $0.crinkleStrength = max($0.crinkleStrength, strength)
            case .whoosh: $0.whooshPending = true
            }
        }
    }

    func setTearSpeed(_ speed: Float) {
        params.withLock { $0.tearSpeed = speed }
    }

    func render(into list: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        guard let data = buffers.first?.mData else { return }
        let out = data.assumingMemoryBound(to: Float.self)
        let snapshot = params.withLock { p -> Params in
            let copy = p
            p.crinkleStrength = 0
            p.whooshPending = false
            return copy
        }
        let samples: [Float] = dsp.withLock { s in
            if s.scratch.count < frames { s.scratch = [Float](repeating: 0, count: frames) }
            let sr = max(snapshot.sampleRate, 8000)
            let dt = 1 / sr
            if snapshot.crinkleStrength > 0 {
                s.crinkleTimer = 0.14
                s.crinkleStrength = snapshot.crinkleStrength
            }
            if snapshot.whooshPending { s.whooshTime = 0 }
            let crinkleDecay = exp(-1 / (sr * 0.008))
            let crinkleHP = 1 - exp(-2 * Float.pi * 700 / sr)
            let crinkleLPk = 1 - exp(-2 * Float.pi * 2600 / sr)
            let tearSlow = 1 - exp(-2 * Float.pi * 180 / sr)
            let masterK = 1 - exp(-2 * Float.pi * 4200 / sr)
            let attack = 1 - exp(-1 / (sr * 0.03))
            let release = 1 - exp(-1 / (sr * 0.12))

            for i in 0..<frames {
                // White noise, xorshift32.
                s.rng ^= s.rng << 13
                s.rng ^= s.rng >> 17
                s.rng ^= s.rng << 5
                let noise = Float(s.rng) / Float(UInt32.max) * 2 - 1
                var sample: Float = 0

                // Crinkle: a flurry of tiny bursts for a short while, bright.
                if s.crinkleTimer > 0 {
                    s.crinkleTimer -= dt
                    if Float(s.rng & 0xFFFF) / 65535 < 1 / (sr * 0.009) * 60 {
                        s.crinkleEnv = max(s.crinkleEnv, s.crinkleStrength * (0.3 + 0.7 * Float(s.rng >> 8 & 0xFF) / 255))
                    }
                }
                s.crinkleEnv *= crinkleDecay
                s.crinkleLP += (noise - s.crinkleLP) * crinkleHP
                s.crinkleBand += ((noise - s.crinkleLP) - s.crinkleBand) * crinkleLPk
                sample += s.crinkleBand * s.crinkleEnv * 0.6

                // Tearing: band-passed noise, brighter and louder with speed,
                // with a coarse random crackle.
                let target = snapshot.tearSpeed
                s.tearLevel += (target - s.tearLevel) * (target > s.tearLevel ? attack : release)
                if s.tearLevel > 0.001 {
                    let cutoff = 320 + 1900 * s.tearLevel
                    let k = 1 - exp(-2 * Float.pi * cutoff / sr)
                    s.tearLP += (noise - s.tearLP) * k
                    s.tearSlowLP += (s.tearLP - s.tearSlowLP) * tearSlow
                    s.crackleCounter -= 1
                    if s.crackleCounter <= 0 {
                        s.crackleCounter = Int(sr * (0.002 + 0.004 * Float(s.rng & 0xFF) / 255))
                        s.crackle = 0.4 + 0.6 * Float(s.rng >> 4 & 0xFF) / 255
                    }
                    sample += (s.tearLP - s.tearSlowLP) * s.tearLevel * s.crackle * 1.1
                }

                // Whoosh: noise through a low-pass whose cutoff sweeps up
                // while the envelope rises then fades.
                if s.whooshTime >= 0 {
                    s.whooshTime += dt
                    let t = s.whooshTime
                    let env = t < 0.08 ? t / 0.08 : max(0, 1 - (t - 0.08) / 0.45)
                    let cutoff = 260 + 1500 * min(t / 0.3, 1)
                    let k = 1 - exp(-2 * Float.pi * cutoff / sr)
                    s.whooshLP += (noise - s.whooshLP) * k
                    sample += s.whooshLP * env * 0.55
                    if t > 0.6 { s.whooshTime = -1 }
                }

                // Gentle master low-pass takes the hiss off everything.
                s.masterLP += (sample - s.masterLP) * masterK
                s.scratch[i] = tanh(s.masterLP)
            }
            return Array(s.scratch[0..<frames])
        }
        for i in 0..<frames { out[i] = samples[i] }
    }
}
