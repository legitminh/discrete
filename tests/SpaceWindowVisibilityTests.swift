@main struct SpaceWindowVisibilityTests {
    static var count = 0
    static func check(_ value: Bool, _ expected: Bool, _ reason: String) {
        count += 1
        precondition(value == expected, reason)
    }
    static func main() {
        let proof = SpaceWindowVisibility(windows: [
            .init(id: 1, spaces: [10]), // old Codex Space
            .init(id: 2, spaces: [20]), // Chrome destination
            .init(id: 3, spaces: [30]), // other monitor
            .init(id: 4, spaces: [10, 20]) // all-desktops window
        ], displaySpaces: [10, 20], otherVisibleSpaces: [30], target: 20)
        check(proof.isReady(visibleIDs: [1, 2, 3, 4]), false, "Chrome visible over old Codex isn't a completed switch")
        check(proof.isReady(visibleIDs: [2, 3, 4]), true, "Destination alone plus other-monitor/sticky windows is valid")
        check(proof.isReady(visibleIDs: [1, 3]), false, "Old Space without destination isn't ready")
        let onlyDocuments = SpaceWindowVisibility(windows: [.init(id: 1, spaces: [10]), .init(id: 2, spaces: [20])], displaySpaces: [10, 20], otherVisibleSpaces: [], target: 20)
        check(onlyDocuments.isReady(visibleIDs: []), true, "A destination with hidden/minimized documents can legitimately have no visible document")
        let emptyDesktop = SpaceWindowVisibility(windows: [.init(id: 1, spaces: [10])], displaySpaces: [10, 20], otherVisibleSpaces: [], target: 20)
        check(emptyDesktop.isReady(visibleIDs: []), true, "A legitimately empty desktop doesn't need a target document witness")
        check(emptyDesktop.isReady(visibleIDs: [1]), false, "An empty destination cannot leave old windows behind")
        let preexistingGhost = SpaceWindowVisibility(windows: [.init(id: 1, spaces: [40]), .init(id: 2, spaces: [20])], displaySpaces: [10, 20, 40], otherVisibleSpaces: [], target: 20)
        check(preexistingGhost.isReady(visibleIDs: [1, 2]), false, "Catch a ghost from any foreign Space, even if it predates this navigation")
        print("Space window visibility: \(count) checks passed")
    }
}
