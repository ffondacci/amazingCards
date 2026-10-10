/// CardPack: booster pack view, tear gesture and the pack-opening flow.
/// See `PackOpeningView` for the orchestrated experience.
import CardCore
import CardFX
import CardUI

extension Duration {
    /// Seconds as a Double, for gesture speed math.
    var seconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
