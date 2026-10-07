/// Runs the builtins that act outside discrete. The graph store handles
/// the ones that stay inside it (search) and decides whether discrete
/// exits afterwards.
enum BuiltinRunner {
    static func run(_ builtin: BuiltinFunction, argument: String?) {
        print("🧰 Running builtin: \(builtin.name)")
        switch builtin.behavior {
        case .openSearch:
            // Handled by DiscreteGraphStore, since it's a discrete state.
            return
        case .moveWindowToNextMonitor:
            WindowMover.moveFocusedWindowToNextMonitor()
        case .openWebsite:
            WebsiteOpener.open(argument)
        }
    }
}
