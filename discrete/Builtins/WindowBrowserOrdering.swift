import Foundation

/// Keeps every application's windows together. Applications follow actual
/// activation recency; windows within one application follow Mission Control's
/// left-to-right Space order because macOS does not expose dependable
/// per-window activation history.
enum WindowBrowserOrdering {
    struct Candidate: Equatable {
        let windowID: UInt32
        let processID: Int32
        let spaceRanks: [Int]
        let sourceOrder: Int
    }

    static func sorted(_ candidates: [Candidate], applicationRecency: [Int32: Date]) -> [Candidate] {
        let fallbackApplicationRank = Dictionary(grouping: candidates, by: \.processID).mapValues {
            $0.map(\.sourceOrder).min() ?? .max
        }

        return candidates.sorted { lhs, rhs in
            if lhs.processID != rhs.processID {
                let lhsRecency = applicationRecency[lhs.processID]
                let rhsRecency = applicationRecency[rhs.processID]
                if lhsRecency != rhsRecency {
                    if let lhsRecency, let rhsRecency { return lhsRecency > rhsRecency }
                    return lhsRecency != nil
                }
                let lhsFallback = fallbackApplicationRank[lhs.processID] ?? .max
                let rhsFallback = fallbackApplicationRank[rhs.processID] ?? .max
                if lhsFallback != rhsFallback { return lhsFallback < rhsFallback }
                return lhs.processID < rhs.processID
            }

            let lhsSpace = lhs.spaceRanks.min() ?? .max
            let rhsSpace = rhs.spaceRanks.min() ?? .max
            if lhsSpace != rhsSpace { return lhsSpace < rhsSpace }
            if lhs.sourceOrder != rhs.sourceOrder { return lhs.sourceOrder < rhs.sourceOrder }
            return lhs.windowID < rhs.windowID
        }
    }
}
