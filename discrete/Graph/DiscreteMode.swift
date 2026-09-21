/// What key input currently means while discrete mode is active.
enum DiscreteMode: Equatable {
    /// Ordinary graph walking: a key either transitions to a child state
    /// or triggers a reserved action.
    case navigating
    /// Mid "set state name": subsequent keys append to `buffer`; CapsLock
    /// commits it (see AppCoordinator).
    case namingState(buffer: String)
    /// Mid "set node arguments": the next key pressed becomes the trigger
    /// for a brand-new child state; CapsLock cancels.
    case settingArguments
}
