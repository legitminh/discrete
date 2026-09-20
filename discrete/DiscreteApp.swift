//
//  discreteApp.swift
//  discrete
//
//  Created by Minh on 9/12/26.
//

import SwiftUI

@main
struct KeyCommandApp: App {
    private let coordinator = AppCoordinator()

    init() {
        coordinator.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
