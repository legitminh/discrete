import Foundation

@main
struct WindowBrowserOrderingTests {
    static func main() {
        let recent = Date(timeIntervalSince1970: 200)
        let older = Date(timeIntervalSince1970: 100)
        let candidates = [
            candidate(1, process: 10, spaces: [2], source: 0),
            candidate(2, process: 20, spaces: [1], source: 1),
            candidate(3, process: 10, spaces: [0], source: 2),
            candidate(4, process: 20, spaces: [3], source: 3)
        ]

        let sorted = WindowBrowserOrdering.sorted(candidates, applicationRecency: [10: older, 20: recent])
        assert(sorted.map(\.windowID) == [2, 4, 3, 1],
               "recent applications should come first as a group, then windows should follow Space order")

        let unknown = WindowBrowserOrdering.sorted(candidates, applicationRecency: [:])
        assert(unknown.map(\.windowID) == [3, 1, 2, 4],
               "apps without activation history should stay grouped in first-seen app order")

        let sameSpace = [
            candidate(7, process: 30, spaces: [0], source: 5),
            candidate(6, process: 30, spaces: [0], source: 2)
        ]
        assert(WindowBrowserOrdering.sorted(sameSpace, applicationRecency: [:]).map(\.windowID) == [6, 7],
               "WindowServer order should break ties within one Space")

        print("WindowBrowserOrderingTests passed")
    }

    private static func candidate(_ window: UInt32, process: Int32, spaces: [Int], source: Int)
        -> WindowBrowserOrdering.Candidate {
        .init(windowID: window, processID: process, spaceRanks: spaces, sourceOrder: source)
    }
}
