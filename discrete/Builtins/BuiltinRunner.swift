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
        case .windowsBrowser:
            // Coordinator-owned: it replaces Discrete's normal overlay and
            // temporarily routes trigger keys into the browser.
            return
        case .newTabOfWebpage:
            BrowserTabOpener.newTab(argument)
        case .openWebpageIfNotPresent:
            BrowserTabOpener.openIfNotPresent(argument)
        case .openApplicationIntelligently:
            ApplicationOpener.open(argument: argument)
        case .toggleFullScreen:
            WindowFullscreen.toggleFocusedWindow()
        case .toggleSketchMode:
            SketchMode.shared.toggle()
        case .activateSketchMode:
            SketchMode.shared.activate()
        case .deactivateSketchMode:
            SketchMode.shared.deactivate()
        }
    }
}
