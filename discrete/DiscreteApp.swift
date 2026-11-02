//
//  discreteApp.swift
//  discrete
//
//  Created by Minh on 9/12/26.
//

import SwiftUI

@main
struct KeyCommandApp: App {
    private let coordinator: AppCoordinator?

    init() {
        #if DEBUG
        if SearchDiagnostics.startIfRequested() {
            coordinator = nil
            return
        }
        #endif
        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        coordinator.start()
    }

    /// Background only: no window at launch (and no Dock icon, via
    /// LSUIElement). The overlay is the only UI; SwiftUI still needs a scene.
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
