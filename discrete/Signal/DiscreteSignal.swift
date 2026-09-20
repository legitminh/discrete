/// A physical key press, boiled down to one of two discrete outcomes.
/// This is the boundary between "raw input" and "meaning" — everything
/// downstream reacts to signals, never to physical events directly.
enum DiscreteSignal: Equatable {
    case tap
    case hold
}
