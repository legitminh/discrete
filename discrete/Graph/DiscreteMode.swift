import CoreGraphics

/// What key input currently means while discrete mode is active. Every
/// non-`.navigating` mode is a detour that always resolves back to
/// `.navigating` — either by completing (rename saved, action bound,
/// script set, action deleted) or by CapsLock cancelling it — rather than
/// a nested stack you step back through one level at a time.
enum DiscreteMode: Equatable {
    /// Ordinary graph walking: a key either transitions to a child state
    /// or triggers a reserved action (back / set node actions / set name).
    case navigating

    /// Mid "set state name" (or mid renaming a specific action's target
    /// state, from `.editingAction`): subsequent keys append to `buffer`
    /// for `target`; CapsLock commits it (see AppCoordinator).
    case namingState(target: DiscreteState, buffer: String)

    /// The "set node actions" editing state: an unoccupied key creates a
    /// new child bound to that key; an occupied key opens
    /// `.editingAction` for that child. CapsLock cancels.
    case settingActions

    /// The "action configuration state" for one of the current state's
    /// existing actions (`target`, reachable via `triggerKey`): rename,
    /// set its script, or delete it entirely. CapsLock cancels.
    case editingAction(triggerKey: CGKeyCode, target: DiscreteState)
}
