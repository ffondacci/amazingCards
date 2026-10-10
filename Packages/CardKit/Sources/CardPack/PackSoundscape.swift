import AVFoundation
import Observation

/// Sound files of a pack opening. Nothing is bundled: provide your own.
public struct PackSoundSet: Hashable, Sendable {
    /// Short crinkle played when the finger grabs the strip.
    public var crinkle: URL?
    /// Looped while tearing; its volume follows the finger speed.
    public var tearing: URL?
    /// Played once when the strip flies off.
    public var whoosh: URL?

    public init(crinkle: URL? = nil, tearing: URL? = nil, whoosh: URL? = nil) {
        self.crinkle = crinkle
        self.tearing = tearing
        self.whoosh = whoosh
    }

    /// Looks the three files up in a bundle by name (any extension
    /// `AVAudioPlayer` reads). Missing files are simply left nil.
    public init(bundle: Bundle = .main, crinkle: String, tearing: String, whoosh: String) {
        func url(_ name: String) -> URL? {
            for ext in ["m4a", "caf", "wav", "mp3", "aac", "aiff"] {
                if let url = bundle.url(forResource: name, withExtension: ext) { return url }
            }
            return nil
        }
        self.init(crinkle: url(crinkle), tearing: url(tearing), whoosh: url(whoosh))
    }

    public var isEmpty: Bool { crinkle == nil && tearing == nil && whoosh == nil }
}

/// Plays the sounds of a pack opening from files. Silent, and without an
/// audio session, when no `PackSoundSet` is given. Ambient category: the
/// silent switch is respected and other audio keeps playing.
@MainActor
@Observable
public final class PackSoundscape {
    public private(set) var isReady = false

    private let soundSet: PackSoundSet?
    private var crinklePlayer: AVAudioPlayer?
    private var tearPlayer: AVAudioPlayer?
    private var whooshPlayer: AVAudioPlayer?

    public init(soundSet: PackSoundSet? = nil) {
        self.soundSet = soundSet
    }

    /// Loads the files (off the main actor) and activates the session.
    public func start() async {
        guard let soundSet, !soundSet.isEmpty, !isReady else { return }
        let loaded = await Self.load(soundSet)
        guard !Task.isCancelled else { return }
        await Self.activateSession()
        crinklePlayer = loaded.crinkle.flatMap { try? AVAudioPlayer(data: $0) }
        tearPlayer = loaded.tearing.flatMap { try? AVAudioPlayer(data: $0) }
        whooshPlayer = loaded.whoosh.flatMap { try? AVAudioPlayer(data: $0) }
        tearPlayer?.numberOfLoops = -1
        tearPlayer?.volume = 0
        for player in [crinklePlayer, tearPlayer, whooshPlayer] { player?.prepareToPlay() }
        isReady = true
    }

    public func stop() {
        for player in [crinklePlayer, tearPlayer, whooshPlayer] { player?.stop() }
        crinklePlayer = nil
        tearPlayer = nil
        whooshPlayer = nil
        isReady = false
    }

    /// Crinkle of the wrapper being grabbed; `strength` scales the volume.
    public func crinkle(strength: Double = 1) {
        guard let crinklePlayer else { return }
        crinklePlayer.volume = Float(min(max(strength, 0), 1))
        crinklePlayer.currentTime = 0
        crinklePlayer.play()
    }

    /// Tearing loop; `speed` 0…1 sets the volume, 0 pauses it.
    public func tearing(speed: Double) {
        guard let tearPlayer else { return }
        let level = Float(min(max(speed, 0), 1))
        if level <= 0.01 {
            if tearPlayer.isPlaying { tearPlayer.pause() }
            return
        }
        tearPlayer.volume = level
        if !tearPlayer.isPlaying { tearPlayer.play() }
    }

    /// The strip flying off.
    public func whoosh() {
        tearPlayer?.pause()
        guard let whooshPlayer else { return }
        whooshPlayer.currentTime = 0
        whooshPlayer.play()
    }

    private struct LoadedSounds: Sendable {
        var crinkle: Data?
        var tearing: Data?
        var whoosh: Data?
    }

    @concurrent
    nonisolated private static func load(_ set: PackSoundSet) async -> LoadedSounds {
        LoadedSounds(
            crinkle: set.crinkle.flatMap { try? Data(contentsOf: $0) },
            tearing: set.tearing.flatMap { try? Data(contentsOf: $0) },
            whoosh: set.whoosh.flatMap { try? Data(contentsOf: $0) }
        )
    }

    @concurrent
    nonisolated private static func activateSession() async {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
        #endif
    }
}
