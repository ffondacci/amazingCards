import CardCore
import Foundation
import Observation

/// Orchestrates a pack opening: sealed → torn → cards emerge → browse → done.
/// The choreography after the tear runs in one cancellable task.
@MainActor
@Observable
public final class PackOpeningModel {
    public enum Phase: Hashable, Sendable {
        case sealed
        case torn
        case emerging
        case browsing
        case finished
    }

    public let pack: BoosterPack
    public let tear = TearState()
    public private(set) var phase: Phase = .sealed
    /// Index of the card currently on top of the swipe stack.
    public var topIndex = 0
    /// Cards already swiped away, in order.
    public private(set) var revealed: [Card] = []

    private var choreography: Task<Void, Never>?

    public init(pack: BoosterPack) {
        self.pack = pack
    }

    /// Card currently facing the user, nil outside the browsing phase.
    public var currentCard: Card? {
        guard phase == .browsing, topIndex < pack.cards.count else { return nil }
        return pack.cards[topIndex]
    }

    /// Called by the tear gesture when the strip breaks.
    public func packTorn() {
        guard phase == .sealed else { return }
        phase = .torn
        choreography?.cancel()
        choreography = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled, let self else { return }
            self.phase = .emerging
            try? await Task.sleep(for: .milliseconds(1000))
            guard !Task.isCancelled else { return }
            self.phase = self.pack.cards.isEmpty ? .finished : .browsing
        }
    }

    /// Called by the swipe stack for every card thrown out.
    public func cardSwiped(_ card: Card) {
        revealed.append(card)
        if revealed.count >= pack.cards.count {
            phase = .finished
        }
    }

    /// Skips the tear (accessibility / automation).
    public func openImmediately() {
        guard phase == .sealed else { return }
        packTorn()
    }

    public func cancel() {
        choreography?.cancel()
        choreography = nil
    }

    public func reset() {
        cancel()
        phase = .sealed
        topIndex = 0
        revealed = []
        tear.reset()
    }
}
