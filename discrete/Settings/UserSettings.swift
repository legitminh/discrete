import Combine
import Foundation

/// User-configurable behavior. Currently holds the one dial the signal
/// layer needs: how long a press can last before it stops counting as a
/// short click and starts counting as a hold.
final class UserSettings: ObservableObject {
    @Published var clickHoldThreshold: TimeInterval = 0.35
}
