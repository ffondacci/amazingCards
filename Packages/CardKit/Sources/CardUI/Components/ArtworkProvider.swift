import CardCore
import SwiftUI

/// Draws the `.custom(key)` artworks of an app: any SwiftUI view, sized by
/// the card, the pack or the layer that shows it. Views must draw
/// synchronously (no network, no `.task`): the 3D stage renders them into
/// pictures with `ImageRenderer`, which takes one frame. A UIKit or AppKit
/// view is used by drawing it into an image first and returning that
/// `Image` (a platform view inside `ImageRenderer` renders blank).
///
/// ```swift
/// RootView()
///     .artworkProvider { key in
///         switch key {
///         case "aurora": AnyView(AuroraView())
///         default: nil
///         }
///     }
/// ```
public struct ArtworkProvider: Sendable {
    private let make: @MainActor @Sendable (String) -> AnyView?

    /// - Parameter make: returns the view for a key, nil when the key is
    ///   unknown. The one type erasure sits at the artwork leaf, so a
    ///   registry can mix views.
    public init(_ make: @escaping @MainActor @Sendable (String) -> AnyView?) {
        self.make = make
    }

    /// The view for a key, nil when the provider does not know it.
    @MainActor public func callAsFunction(_ key: String) -> AnyView? {
        make(key)
    }

    /// Knows no key: every custom artwork shows the procedural placeholder.
    public static let none = ArtworkProvider { _ in nil }
}

private struct ArtworkProviderKey: EnvironmentKey {
    static let defaultValue = ArtworkProvider.none
}

public extension EnvironmentValues {
    /// Who draws the `.custom` artworks under this view.
    var artworkProvider: ArtworkProvider {
        get { self[ArtworkProviderKey.self] }
        set { self[ArtworkProviderKey.self] = newValue }
    }
}

public extension View {
    /// Draws the `.custom(key)` artworks of every card, pack and parallax
    /// layer under this view with the views `make` returns.
    func artworkProvider(_ make: @escaping @MainActor @Sendable (String) -> AnyView?) -> some View {
        environment(\.artworkProvider, ArtworkProvider(make))
    }

    /// Same, with a provider built elsewhere (handed to `PackPrints` too).
    func artworkProvider(_ provider: ArtworkProvider) -> some View {
        environment(\.artworkProvider, provider)
    }
}
