import Foundation

/// Screens of the demo. Launch with `-demoRoute effects` to open one
/// directly (used for screenshots and QA automation).
enum DemoRoute: String, CaseIterable, Identifiable {
    case collection
    case effects
    case animations
    case booster

    var id: String { rawValue }

    var title: String {
        switch self {
        case .collection: "Collection"
        case .effects: "Effects"
        case .animations: "Animations"
        case .booster: "Booster"
        }
    }

    var symbol: String {
        switch self {
        case .collection: "rectangle.stack.fill"
        case .effects: "sparkles.rectangle.stack.fill"
        case .animations: "wand.and.stars"
        case .booster: "shippingbox.fill"
        }
    }

    /// Route requested on the command line, if any.
    static var fromLaunchArguments: DemoRoute? {
        UserDefaults.standard.string(forKey: "demoRoute").flatMap(DemoRoute.init(rawValue:))
    }
}
