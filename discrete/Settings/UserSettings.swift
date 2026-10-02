import Combine
import Foundation

/// User-configurable behavior.
final class UserSettings: ObservableObject {
    /// How long a press can last before it stops counting as a short
    /// click and starts counting as a hold.
    @Published var clickHoldThreshold: TimeInterval = 0.25
    /// How many suggestions state.search shows at most.
    @Published var maxSearchResults = 8
}
