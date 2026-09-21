import CoreGraphics

/// What key input currently means while discrete mode is active. Every
/// non-`.navigating` mode is a detour that always resolves back to
/// `.navigating` — either by completing or by CapsLock cancelling it —
/// rather than a nested stack you step back through one level at a time.
enum DiscreteMode: Equatable {
    /// Ordinary graph walking: a key either transitions to a child state
    /// or triggers a reserved action (back / configure).
    case navigating

    /// Mid "rename this state" (from `.configuring`) or mid "rename an
    /// action" (from `.pickingAction(.rename)`): subsequent keys append to
    /// `buffer` for `target`; CapsLock/completion commits it.
    case namingState(target: DiscreteState, buffer: String)

    /// Mid naming a just-created action (from `.addingAction`): same as
    /// `namingState`, but committing chains into the script picker instead
    /// of returning straight to navigating.
    case namingNewLeaf(target: DiscreteState, buffer: String)

    /// The "configure" menu for the current state: add a state, add an
    /// action, rename/retarget/delete an existing action, or delete/rename
    /// the current state itself. CapsLock cancels.
    case configuring

    /// "add state": the next unoccupied key creates a new child bound to
    /// it, then moves into naming it. CapsLock cancels.
    case addingState

    /// "add an action": the next unoccupied key creates a new child bound
    /// to it, then moves into naming it (which, on commit, opens the
    /// script picker). CapsLock cancels.
    case addingAction

    /// "rename an action" / "set an action trigger" / "delete action":
    /// shows the current state's existing actions; pressing an action's
    /// own trigger key selects it for `purpose`. CapsLock cancels.
    case pickingAction(purpose: ActionPickerPurpose)

    /// Mid "set an action trigger," after an action was selected: the next
    /// unoccupied key becomes `target`'s new trigger, replacing `oldKey`.
    /// CapsLock cancels.
    case pickingNewTrigger(oldKey: CGKeyCode, target: DiscreteState)
}

enum ActionPickerPurpose: Equatable {
    case rename
    case setTrigger
    case delete
}
