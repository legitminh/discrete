import Foundation

/// Something state.search can open. Declared in tie-break order:
/// functions, then states, then apps, then files.
enum SearchItem {
    case function(DiscreteFunction)
    case state(DiscreteState)
    case app(URL)
    case file(URL)

    var kindOrder: Int {
        switch self {
        case .function: return 0
        case .state: return 1
        case .app: return 2
        case .file: return 3
        }
    }
}

/// One suggestion: what it opens, the name it's matched on, and a short
/// description of what/where it is for the overlay.
struct SearchResult {
    let item: SearchItem
    let name: String
    let detail: String
}
